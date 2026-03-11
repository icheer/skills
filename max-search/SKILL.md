---
name: max-search
description: >
  Use this skill when the user asks any question that would benefit from
  real-time, comprehensive web information — current events, industry
  analysis, fact-checking, market data, technology trends, product
  comparisons, or any topic where training data may be outdated. This skill
  decomposes the question into orthogonal search keywords, executes parallel
  Tavily searches to maximize coverage, and synthesizes all results into a
  grounded, citation-rich answer. Activate even when the user does not
  explicitly say "search" or "look up" — phrases like "what's happening
  with…", "latest on…", "最近…", "how is X doing", "use tavily/max search",
  or any factual question about recent events should trigger this skill.
  Covers English and Chinese queries.
---

# Max Search — 最大化搜索

对用户的问题进行多维关键词拆解，并行执行 Tavily 搜索，将搜索语料与当前真实时间合成为一份高质量回答提示词，确保信息的广度、深度和时效性。

## 前置要求

- Python 3.8+（脚本使用 asyncio）
- 可选但推荐预装：`pip install aiohttp`（不可用时自动回退到同步模式）
- **Tavily API 密钥**——首次使用前必须配置，支持两种方式（任选其一）：

### 配置 API Key

**方式 A — 通过 config 子命令持久化保存（推荐）：**

```bash
python scripts/search.py config --set-api-key YOUR_TAVILY_API_KEY
````

密钥将保存到 `~/.tavily_api_key`（文件权限 0600），后续所有调用自动加载，无需反复设置。

**方式 B — 通过环境变量（临时 / CI 场景）：**

```bash
export TAVILY_API_KEY="YOUR_TAVILY_API_KEY"
```

> 加载优先级：环境变量 `TAVILY_API_KEY` > 文件 `~/.tavily_api_key`。

**查看当前配置状态：**

```bash
python scripts/search.py config
```

会以掩码形式显示已配置的密钥（如 `tvly****abcd`），或打印配置引导。

---

## 工作流程

### Step 1 — 关键词提取（由你完成）

使用下方的 **关键词提取 Prompt** 分析用户的原始问题，输出严格的纯 JSON。

将用户的原始问题填入 `<User_Question>` 占位符，然后执行推理，输出格式如下：

```json
{
  "search_queries": ["keyword1", "keyword2", "..."],
  "num_results": 7
}
```

如果判定不需要搜索（闲聊、纯逻辑题等），JSON 中 `search_queries` 为空数组，`num_results` 为 0——此时跳过后续步骤，直接用自身知识回答用户。

<details>
<summary>📋 关键词提取 Prompt（点击展开）</summary>

```
# Role: Advanced Search Strategist

## 核心定位
你是Max，一个专为Tavily Search API设计的搜索策略生成器。你的唯一目标是最大化信息获取的广度与深度，同时通过精准的关键词设计避免信息冗余或无关联性。

## 关键任务
从用户的自然语言中提取意图，构造 0 到 5 个搜索关键词，并设定合适的结果数量。

## 决策流程

### 第一步：是否搜索 (Search-Or-Not Determination)
判断用户输入是否需要外部增强信息。
- 🚫 直接阻断（返回空数组）：
  - 闲聊/问候 ("你好")
  - 纯逻辑/数学问题 ("1+1=?", "Python列表推导式怎么写?") —— 除非涉及最新版本特性
  - 翻译/改写/创作请求 ("帮我润色这段话")
  - 上下文严重缺失 ("他在哪里？")
- ✅ 启动搜索：
  - 任何需要实时数据、事实核查、行业分析、观点对比的任务。

### 第二步：多维发散 (Orthogonal Expansion)
如果启动搜索，针对问题核心进行正交拆解（即：关键词之间尽量不重叠，覆盖不同维度）。
- 维度参考列表：
  1. [Definition] 核心概念定义/基础事实
  2. [News] 最新动态/时事新闻
  3. [Data] 统计数据/财报/市场份额
  4. [Opinion] 专家评论/争议/论坛讨论
  5. [Comparison] 竞品对比/历史对比
  6. [Technical] 技术文档/白皮书/Github Issues

### 第三步：语言策略 (Language Weighting)
根据信息源熵值决定关键词语言：
- English Heavy (4:1 或 5:0)：计算机科学、Web3/Crypto、国际金融(美股/外汇)、前沿医学、国际政治。
- Chinese Heavy (1:4 或 0:5)：中国本土政策、A股、中文流行文化、本地生活服务、中文语境特有的社会现象。

## 输出配置

严格按照 JSON 格式输出，不要包含任何其他文字：

### search_queries (Array[String])
- 简单事实：1-2个关键词（精准打击）。
- 深度探索：3-5个关键词（最大化覆盖）。针对复杂问题，必须填满5个槽位，分别对应不同维度。
- 关键词必须精炼（去停用词）。
- 如果混合语言，请将高质量源语言放在数组前面。

### num_results (Integer)
- 1-2 个关键词：设为 10
- 3-5 个关键词：设为 5 到 8（总条目数 = search_queries.length × num_results，控制在40以内）
```

</details>

---

### Step 2 — 执行搜索（调用脚本）

将 Step 1 输出的 JSON 和用户原始问题传给 Python 脚本的 `search` 子命令。脚本会并行调用 Tavily API 并将搜索结果合成为最终回答提示词。

运行方式：

```bash
python scripts/search.py search --question "<用户原始问题>" --search-json '<Step1输出的JSON>'
```

**参数说明：**
| 参数 | 说明 |
|------|------|
| `search` | 子命令——执行搜索流程 |
| `--question` | 用户的原始问题文本（用引号包裹） |
| `--search-json` | Step 1 生成的 JSON 字符串（用单引号包裹） |

脚本会将完整的合成提示词输出到 stdout。

---

### Step 3 — 基于搜索语料回答用户

将脚本的 stdout 输出作为你的上下文，按照其中的指引（结构框架、事实基准原则等）生成最终回答。

**关键原则提醒（脚本输出中已包含完整说明，此处是摘要）：**

1. **搜索语料优先于你的内部知识**——时效性信息有冲突时，以搜索结果为准
2. **不简单罗列**——交叉验证不同来源，综合叙述
3. **诚实标注空白**——搜索结果未覆盖的信息要明确说明
4. **提供真实可点击的来源链接**

## 注意事项

- 如果 API Key 未配置，脚本会打印详细的配置引导信息并退出——此时按提示运行 `config --set-api-key` 即可
- 如果 `aiohttp` 不可用，脚本自动回退到同步模式（`urllib`），功能不受影响但速度较慢
- 单次技能调用的总搜索条目上限约 40 条（由关键词提取 Prompt 的 `num_results` 策略控制），这是为了防止 context 过载导致注意力分散