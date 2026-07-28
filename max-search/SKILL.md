---
name: max-search
description: >
  Executes a complete "maximize information coverage" web search: decompose
  a user's natural language question into orthogonal search keywords, run
  parallel Tavily searches, and synthesize a grounded, cited answer.

  **Slash command**: `/max-search <question>`

  Activate on: /max-search, "深度搜索", "max search", "全面搜索", "最大化搜索",
  "做个调研", "帮我调查一下", "最新动态是什么", "最近有什么进展",
  "对比一下", "分析一下", "做个对比分析", or any question that is factual,
  multi-faceted, or benefits from multiple orthogonal search queries.
  Specifically: company/technology research, market analysis, fact-checking,
  opinion comparison, trend research, competitive analysis, or any question
  where a single search query would not suffice. Also activates when the
  user says things like "帮我深度搜索一下 DeepSeek" or "我想要全面了解一下
  某话题" or asks "最近 XXX 有什么新消息". This skill is the authoritative
  entry point for Tavily-powered deep searching in this codebase. Do NOT use
  the old tavily-keyword-extractor or tavily-max-search skills; use this one.
---

# Max Search — 最大化信息覆盖的深度搜索

通过关键词智能拆解 → 并行 Tavily 搜索 → 综合分析，一站式完成深度调研式搜索。

## 工作流

```
用户输入: /max-search <自然语言问题>
    │
    ▼
Step 1 — 关键词拆解（内部执行）
    ├─ 判断是否需要搜索
    ├─ 多维拆解（Definition / News / Data / Opinion / Comparison / Technical）
    ├─ 语言策略（英文为主 vs 中文为主）
    └─ 输出 JSON（见下方 Schema）
    │
    ▼
Step 2 — 执行搜索
    └─ 调用 bash {{INSkillDir}}/scripts/search.sh [--num-results N] "query1" "query2" ...（路径相对于 skill bundle 根目录）
    │
    ▼
Step 3 — 综合回答
    ├─ 分析搜索结果
    ├─ 交叉验证多来源
    ├─ 禁止编造未找到的信息
    └─ 输出带来源链接的 Markdown 回答
```

---

## Step 1 — 关键词拆解

### 1.1 判断是否需要搜索

**不需要搜索**（`search_queries` 返回空数组，直接用内部知识回答）：

- 闲聊问候："你好"、"怎么样"
- 纯逻辑/数学/编程基础：无需实时信息
- 翻译改写/纯文本任务

**意图模糊，先问再搜**（不要猜着搜）：

- 问题过于宽泛且无上下文，无法判断用户真正想了解什么（如单独一个词"AI"、"区块链"）
- 问题中有明显歧义，不同理解会导致完全不同的搜索方向
- 处理方式：用一句话说明你的困惑，提出 1-2 个澄清选项，等用户确认后再搜索

**需要搜索**：

- 实时数据：股价、天气、汇率、新闻事件
- 事实核查：某公司状态、事件真伪
- 行业/技术趋势分析
- 观点对比：不同立场对某事件的评价
- 任何需要**多维度交叉验证**的问题

### 1.2 多维拆解策略

从以下维度中选择 1-5 个，生成**正交**的搜索关键词（尽量不重叠）：

| 维度 | 说明 | 示例关键词 |
|------|------|-----------|
| Definition | 核心概念定义 | "DeepSeek 是什么" |
| News | 最新动态 | "DeepSeek 2026 news" |
| Data | 统计数据/市场份额 | "DeepSeek market share" |
| Opinion | 专家评论/争议 | "DeepSeek controversy" |
| Comparison | 竞品对比 | "DeepSeek vs GPT-4" |
| Technical | 技术文档/白皮书 | "DeepSeek architecture paper" |

**正交原则**：关键词之间尽量不重叠，覆盖不同角度。简单问题 1-2 个维度，深度探索 3-5 个。

### 1.3 语言策略

根据信息源分布选择语言比例：

| 领域 | 推荐比例 |
|------|---------|
| 计算机科学、Web3/Crypto、国际金融、前沿医学、国际政治 | 英文为主（4:1 ~ 5:0） |
| 中国本土政策、A股、中文流行文化、本地生活服务 | 中文为主（1:4 ~ 0:5） |

### 1.4 输出 Schema（JSON）

**Keyword Extraction Output Contract**

```json
{
  "refined_question": "string  — 改写后的专业化问题，保留核心意图但更精准",
  "search_queries": ["query1", "query2", "query3"],
  "num_results": "integer  — 每个查询返回的结果数，默认 7，范围 5-10",
  "reasoning": "string  — 拆解逻辑说明，包含维度选择原因和语言策略依据"
}
```

**约束**：
- `search_queries.length × num_results ≤ 40`（总条目数控制）
- 关键词要精炼，加上具体限定词（避免单独搜"AI"、"中国"这类过泛的词）
- `refined_question` 需保留用户原始意图，不能偏离
- `search_queries` 是字符串数组，每个元素就是一个独立的搜索关键词

---

## Step 2 — 调用搜索脚本

脚本用 **bash + curl** 实现（无需 Python）。调用前需确保系统有 `bash` 和 `curl`（Windows 用 Git Bash 运行）。

### 脚本路径与调用方式

```bash
bash {{INSkillDir}}/scripts/search.sh [--num-results N] "<query1>" "<query2>" ...
```

- 搜索关键词以**位置参数**传入，每个用引号包裹
- `--num-results` 可选，默认 `8`
- 脚本会**并行**请求所有查询，stdout 输出每个查询的原始 JSON（以 `===== QUERY: ... =====` 分隔），stderr 输出执行日志

### API Key 配置（首次使用）

```bash
# 查看配置状态（含已加载的 key 数量，打码显示）
bash {{INSkillDir}}/scripts/search.sh --check
```

支持多 Key（每次搜索随机选一个），加载优先级：环境变量 → `~/.env` → `~/.tavily_api_key`

- **推荐：`~/.env`**（标准 KEY=VALUE 格式，逗号或换行分隔）
  ```
  TAVILY_API_KEY=tvly-key1,tvly-key2,tvly-key3
  ```
- **环境变量**：`export TAVILY_API_KEY="tvly-key1,tvly-key2"`
- **`~/.tavily_api_key`**（单 Key 文件，向后兼容）

获取 Key：<https://app.tavily.com/home>

---

## Step 3 — 综合回答

### 核心原则

1. **事实基准**：搜索结果**优先于**内部训练知识，特别是时效性信息
2. **禁止编造**：搜索结果中没有的信息，明确说明"搜索结果未提及"，绝不猜测
3. **交叉验证**：不要简单罗列，合并不同来源的数据和观点
4. **引用来源**：每条引用必须有真实可点击的链接，格式 `[标题](URL)`

### 输出格式要求

**结论先行**：开头先简述搜索执行情况（查询次数、结果数量）并给出核心结论。

格式根据内容决定，不强制套模板。基本原则：

1. **开头**：一句话复述理解的问题方向（来自 `refined_question`）、搜索概况，然后直接给出核心结论
其中，搜索概况（查询次数、结果数量）示例如下：
```
📊 搜索概况：执行了 N 次查询（M 次成功），获取 X 条结果，
   其中 Y 条高度相关（相关度 ≥ 0.8）
```
2. **中间**：根据内容选择最合适的结构——可以是分点、可以是对比表格、可以是叙述段落
3. **结尾**：参考来源列表，格式 `[标题](URL)`

---

## 特殊情况处理

### 情况 1：`search_queries` 为空（不需要搜索）

**触发**：问题属于纯闲聊、基础知识、翻译等不需要实时信息的类型。

**处理**：
1. 输出 `{}`（空 JSON 对象）
2. 直接用内部知识回答，无需调用搜索脚本

### 情况 2：API Key 未配置

**脚本输出**：
```
[FATAL] 未配置 Tavily API Key。
配置方式（任选其一）:
  A. ~/.env: TAVILY_API_KEY=key1,key2,key3
  B. export TAVILY_API_KEY="YOUR_KEY"
  C. ~/.tavily_api_key（单 Key）
获取 Key: https://app.tavily.com/home
```

**处理**：向用户说明配置步骤，等用户完成后再执行。

### 情况 3：部分搜索失败

**脚本输出**：`[INFO] N/M 个查询成功。`（失败的查询块会标记 `[ERROR]`）

**处理**：
- 告知用户有部分查询失败，不阻塞流程
- 用成功的搜索结果回答，对失败维度予以说明

### 情况 4：所有搜索失败

**处理**：告知用户，检查 API Key 和网络连接，建议重新配置。

---

## 示例

### 示例 1：正常流程

**用户输入**：`/max-search DeepSeek 最近有什么进展？`

**Step 1 关键词拆解**（内部输出）：

```json
{
  "refined_question": "DeepSeek AI 在 2026 年的最新技术进展和产品发布情况",
  "search_queries": [
    "DeepSeek AI 2026 news",
    "DeepSeek latest model release",
    "DeepSeek R1 update"
  ],
  "num_results": 8,
  "reasoning": "技术公司动态，英文信息源更全面，覆盖新闻发布和技术更新两个维度"
}
```

**Step 2 调用脚本**：

```bash
bash {{INSkillDir}}/scripts/search.sh --num-results 8 \
  "DeepSeek AI 2026 news" "DeepSeek latest model release" "DeepSeek R1 update"
```

**Step 3 综合回答**：基于脚本输出的 JSON 结果，合成带来源的 Markdown 回答。

---

### 示例 2：不需要搜索

**用户输入**：`/max-search Python 列表推导式怎么写？`

**Step 1 输出**：

```json
{
  "refined_question": "Python 列表推导式的语法结构和使用方法",
  "search_queries": [],
  "num_results": 0,
  "reasoning": "编程基础知识，无需实时信息，可直接用内部知识回答"
}
```

**处理**：直接用内部知识回答，无需调用搜索脚本。

---

### 示例 3：中文话题

**用户输入**：`/max-search 打工人最近流行什么减压方式？`

**Step 1 关键词拆解**（内部输出）：

```json
{
  "refined_question": "职场人士当前主流的压力管理方法和减压活动有哪些？",
  "search_queries": [
    "职场人士 减压方式 2026 趋势",
    "上班族 压力管理 流行活动",
    "工作压力 缓解方法 调查报告"
  ],
  "num_results": 7,
  "reasoning": "打工人是网络用语（指职场人士），拆解为趋势数据、流行观点、调查报告三个维度，中文为主"
}
```

---

## 注意事项

1. **关键词精炼**：去除"的"、"是"、"如何"等停用词，加上具体限定词
2. **总条目数控制**：`search_queries.length × num_results ≤ 40`，避免 context 过载
3. **禁止过度搜索**：简单事实查询不需要 5 个维度的关键词，控制在 1-2 个
4. **脚本路径**：始终使用 `{{INSkillDir}}/scripts/search.sh`，不要使用相对路径
5. **stderr vs stdout**：脚本的 stderr 包含执行日志（可忽略），stdout 才是搜索结果（每个查询一段原始 JSON）

---

## CLI 接口

脚本采用位置参数传入查询，简单直接：

```bash
bash {{INSkillDir}}/scripts/search.sh [--num-results N] "query1" "query2" "query3"
```

**参数**：
- 位置参数：一个或多个搜索关键词，每个用引号包裹
- `--num-results N`：可选，每个查询返回结果数，默认 8
- `--check`：不搜索，仅检查 API Key 配置状态

**示例**：
```bash
bash {{INSkillDir}}/scripts/search.sh --num-results 8 \
  "WordPress Duplicator review" "WP Migrate Guru features"
```

---

## 常见问题（FAQ）

### Q1: 脚本无法运行 / 找不到 bash 或 curl？

**问题**：提示 `bash: command not found` 或 `curl: command not found`。

**解决方案**：脚本需要 `bash` + `curl`。
- Windows：使用 **Git Bash** 运行（Git for Windows 自带 bash 与 curl）
- macOS / Linux：通常已内置，若缺 curl 用包管理器安装

### Q2: 如何使用多个 API Key？

**解决方案**：在 `~/.env` 文件中使用逗号或换行分隔多个 key：

```
TAVILY_API_KEY=tvly-key1,tvly-key2,tvly-key3
```

脚本会在每次搜索时随机选择一个 key，实现负载均衡。

### Q3: 搜索失败怎么办？

**可能原因**：
1. API key 未配置或已过期
2. 网络连接问题
3. API 配额用尽

**排查步骤**：
1. 检查 API key 配置：`bash scripts/search.sh --check`
2. 测试网络连接：`curl https://api.tavily.com`
3. 查看 Tavily 控制台的配额使用情况

### Q4: 每次搜索最多可以有多少个查询？

**限制**：`search_queries.length × num_results ≤ 40`

**示例**：
- 4 个查询 × 10 结果 = 40 条（最大）
- 5 个查询 × 8 结果 = 40 条（最大）
- 8 个查询 × 5 结果 = 40 条（最大）

超过此限制会导致 context 过载，影响综合分析质量。


---

## 故障排除指南

### 问题 1：脚本无法找到或执行

**症状**：`No such file or directory` 或 `Permission denied`

**解决方案**：
1. 确认使用 `bash` 显式调用：`bash {{INSkillDir}}/scripts/search.sh ...`
2. 使用完整路径：`bash ~/.claude/skills/max-search/scripts/search.sh ...`
3. 确认已安装 `bash` 与 `curl`

### 问题 2：API Key 配置后仍然提示未找到

**症状**：`[FATAL] 未配置 Tavily API Key`

**排查步骤**：
1. 运行 `bash scripts/search.sh --check` 查看加载情况
2. 验证 `~/.env` 中 `TAVILY_API_KEY=` 行格式正确（无多余空格）
3. 尝试环境变量：`export TAVILY_API_KEY="your-key"`

### 问题 3：搜索速度很慢

**可能原因**：
1. 网络延迟
2. 查询数量过多
3. 单个查询 `num_results` 过大

**优化方案**：
1. 减少查询数量（控制在 3-5 个）
2. 降低 `num_results`（推荐 5-8）
3. 脚本已并行请求，总耗时取决于最慢的单个查询

### 问题 4：部分搜索失败

**症状**：`[INFO] 3/4 个查询成功。`（失败查询块标记 `[ERROR]`）

**处理方式**：
- 这是正常现象，脚本会继续使用成功的结果
- 如果失败率过高（>50%），检查：
  1. API key 是否有效
  2. 网络连接是否稳定
  3. Tavily 服务状态

### 问题 5：输出结果为空或不完整

**可能原因**：
1. 查询关键词过于宽泛或不准确
2. 搜索结果被域名黑名单过滤
3. Tavily 返回的结果质量较低

**解决方案**：
1. 优化查询关键词，添加具体限定词
2. 增加查询的多样性（不同角度）
3. 提高 `num_results` 参数

