# AI Skills 集合

一组为 Claude Code / OpenClaw 设计的 AI 技能，覆盖产品开发全流程、网络搜索增强、新闻简报生成及语音类工具。

## 快速导航

| 技能包 | 适用场景 |
|--------|---------|
| [openclaw-workspace-builder](#openclaw-workspace-builder) | 交互式引导生成 AI 助手 Workspace 配置 |
| [great-product-skills](#great-product-skills) | 从想法到可交互原型的完整产品工作流 |
| [max-search](#max-search) | 最大化信息覆盖的深度网络搜索 |
| [deep-reader](#deep-reader) | 网页文章深度抓取 + 认知增强分析报告 |
| [daily-news](#daily-news) | 每日中文新闻简报生成 |
| [geek-news](#geek-news) | 极客科技新闻简报生成 |
| [better-prompt](#better-prompt) | 双专家流水线：从粗糙想法到生产级 AI 提示词 |
| [mean-assistant](#mean-assistant) | 技术型毒舌助手，精准答案 + 专业讽刺 |

---

## 收藏集

以下为外部 Skills 收藏，通过 OpenClaw Bot 直接命令其安装即可使用。

| 来源 | 技能包 | 说明 |
|------|--------|------|
| [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator) | skill-creator | Anthropic官方提供的元技能：从零创建技能、修改优化现有技能、定量评估性能，含盲测对比与触发词优化 |
| [NoizAI Skills](https://github.com/NoizAI/skills) | noiz-ai-skills | 类人化语音与 TTS 工具集，含 `characteristic-voice`、`chat-with-anyone`、`daily-news-caster`、`tts`、`video-translation` |

---

## openclaw-workspace-builder

> 通过 3 轮对话（约 5 分钟）引导非技术用户定制专属的 OpenClaw / Nanobot Workspace 配置文件，无需了解 Markdown 或配置文件格式。

### 对话流程

```
第一轮（3 问）→ 场景定位
第二轮（2-3 问）→ 个性化风格与习惯
第三轮（条件触发）→ 工具与权限设置
确认 → 批量生成配置文件
```

### 生成文件

| 文件 | 说明 | 是否必须 |
|------|------|--------|
| `SOUL.md` | AI 的性格和价值观 | ✅ 必须 |
| `IDENTITY.md` | AI 的名字和角色定义 | ✅ 必须 |
| `AGENTS.md` | 工作流程和规则 | ✅ 必须 |
| `USER.md` | 用户画像和偏好 | ✅ 必须 |
| `TOOLS.md` | 可接入的外部工具（飞书、钉钉等） | 条件生成 |
| `MEMORY.md` | 重要历史记忆（项目管理 / 客服场景） | 条件生成 |

### 支持场景

- **个人行政助理** — 邮件处理、日程安排
- **项目管理** — 项目进度跟踪、团队协作（含 MEMORY.md）
- **内容创作** — 文案、报告起草
- **客服支持** — 客户咨询处理（含 MEMORY.md）
- **数据分析** — 数据整理、报表生成
- **通用助理** — 灵活适配

### 平台兼容

- **OpenClaw** — 完全兼容，保持 SOUL.md 和 IDENTITY.md 独立
- **Nanobot / NanoClaw** — 自动将 IDENTITY.md 合并到 SOUL.md
- **Claude Code / Cursor / Windsurf** — 遵循 SoulSpec 标准，理论兼容

**触发词：** 创建 AI 助手配置、生成 SOUL.md、配置 Workspace、定制 AI 助手、`/workspace`

---

## great-product-skills

> 一套模拟真实产品团队协作的工作流，由 4 个专业角色接力完成从讨论到原型再到体验评审的全过程。

### 工作流总览

```
用户输入想法
    ↓
[阿七] product-team-lead  ← 调度中枢，串联所有角色
    ↓           ↓           ↓           ↓
[Phase 1]   [Phase 2]   [Phase 3]   [Phase 4]
PM 策略讨论  PRD 文档    前端原型    UX 走查报告
```

| 阶段 | 角色 | 触发词示例 | 产出 |
|------|------|-----------|------|
| Phase 1 | `pm-strategist` | 聊聊、讨论一下、可行性 | 产品方向共识 |
| Phase 2 | `spec-engineer` | 写 PRD、需求文档 | Markdown PRD |
| Phase 3 | `frontend-prototype-builder` | 做 demo、出原型 | 可交互 Vue 3 原型 |
| Phase 4 | `ux-walkthrough` | 走查、review | P0/P1/P2 问题报告 |

### product-team-lead（阿七）

产品流水线的调度中枢。根据你说的话判断当前处于哪个阶段，激活对应角色，并在阶段结束后汇报进展、推进下一步。不直接做具体工作，但确保整个流程不跑偏。

### pm-strategist

扮演一位有 15 年经验的高级 PM，用对话而非 bullet 风格和你探讨产品方向。会主动挑战你的假设、从用户 / 商业 / 技术三个维度拆解问题，给出有建设性的批评，而不是一味肯定。支持中英混杂。

### spec-engineer

把产品讨论的共识转化为结构化 PRD。流程从 Step 0（收集 8 项基础信息）走到 Step 10（定稿），中间按需包含竞品分析、用户场景、流程图等模块。输出为英文 Markdown，确保需求可测试、可验收。

### frontend-prototype-builder

根据 PRD 用 Vue 3 + TDesign 构建可交互原型。支持两种交付形式：

- **单 HTML 文件** — 适合快速演示，CDN 引入，零环境依赖
- **完整 Vite 项目** — 适合多页面、复杂交互场景

技术约束：仅用 Options API，禁止 Composition API / `<script setup>` / Tailwind / SCSS。

### ux-walkthrough

对原型做系统性 UX 评审，从 6 个维度逐项检查：页面加载、视觉一致性、交互反馈、流程连续性、错误处理、边缘情况。输出按严重程度分级：

- **P0** — 阻塞核心任务 / 数据丢失 / 不可恢复状态
- **P1** — 体验明显降级，但有绕过路径
- **P2** — 锦上添花的优化建议

---

## max-search

> 最大化信息覆盖的深度搜索。通过关键词智能拆解 → 并行 Tavily 搜索 → 综合分析，一站式完成深度调研式搜索。

**触发词：** `/max-search`、深度搜索、max search、全面搜索、帮我搜一下、做个调研、帮我调查一下

### 工作流程

```
用户输入: /max-search <自然语言问题>
    ↓
Step 1 — 关键词拆解（自动判断是否需要搜索，多维拆解）
Step 2 — 并行 Tavily 搜索（自动聚合结果、过滤低质量域名）
Step 3 — 综合回答（交叉验证、带来源链接的 Markdown 输出）
```

### 核心能力

- **智能判断**：闲聊/基础知识无需搜索，直接回答；实时信息/事实核查触发搜索
- **多维拆解**：Definition / News / Data / Opinion / Comparison / Technical 六个维度
- **语言策略**：CS/Web3/国际金融 英文为主；中国政策/A股 中文为主
- **配置简单**：需要 Python 3.8+ 和 [Tavily API Key](https://app.tavily.com/home)

```bash
# 首次配置 API Key
python {{INSkillDir}}/scripts/search.py config --set-api-key YOUR_KEY

# 执行搜索
python {{INSkillDir}}/scripts/search.py search --question "..." --search-json '{...}'
```

---

## deep-reader

> 给一个 URL，深度抓取网页内容并生成认知增强型分析报告。支持微信公号、Hexo 博客等主流平台。

### 工作流程

```
用户提供 URL
    ↓
scripts/fetch_article.py（或 .sh 回退版）
    ↓
提取 title / content / content_length
    ↓
Sage（认知增强型阅读专家）→ 完整分析报告
    ↓
魔法指令深度互动
```

### 核心能力

**抓取引擎**（`fetch_article.py` / `fetch_article.sh`）

| 特性 | `fetch_article.py` | `fetch_article.sh` |
|------|-------------------|---------------------|
| 依赖 | requests + BeautifulSoup + markdownify | curl + Python + BeautifulSoup |
| 输出格式 | 完整 Markdown | 纯文本 |
| 编码处理 | 自动检测（含混合编码兜底） | 自动检测 |
| 回退方案 | 依赖安装失败时自动调 | 自动调用 |

抓取时自动处理：

- 伪装微信浏览器 UA（抓取微信公众号更佳）
- 绕过 `Accept-Encoding: gzip` 自动解压失效问题
- 自动检测 GBK / UTF-8 混合编码（微信公号正文 GBK + meta UTF-8）
- 微信 JS 注入正文（`content_noencode` → `\x` 解码）
- Hexo 等静态博客直接提取 `<article>` / `<main>`

输出为 JSON：
```json
{
  "title": "文章标题",
  "url": "https://...",
  "content_length": 3200,
  "content": "Markdown 格式正文"
}
```

**分析专家（Sage）**

批判性思维教练，不仅总结文章，还帮助用户构建知识体系。输出协议包含：

- **阅前情报** — 一句话速读、金量评分、推荐人群
- **逻辑解构** — 还原思考路径，引用原文 + 深度解读
- **批判性视角** — 盲点探测、逻辑漏洞、利益相关方分析
- **知识迁移** — 跨学科模型关联、跨界类比
- **苏格拉底式追问** — 反事实、行动转化、底层质询

### 魔法指令

| 指令 | 动作 |
|------|------|
| `/ELI5` | 用极简喻体重述核心逻辑（类比讲给5岁孩子听） |
| `/Challenge` | 扮演反方辩手，列出 3 个最强反驳观点 |
| `/Action` | 转化为具体可执行的 To-Do List |
| `/Graph` | 用 ASCII 画出逻辑流程图或概念关系图 |
| `/Deep` + 问题 | 深度挖掘，针对文章内任意微观细节追问 |

### 触发方式

```
"帮我深度分析这篇文章：https://mp.weixin.qq.com/s/..."  → 直接抓取 + 分析
"深度阅读" + 粘贴正文内容                                 → 有内容，直接分析
"/ELI5" 或 "/Challenge"（在有上文时）                     → 魔法指令
"帮我抓取这个页面"                                       → 仅抓取
```

**触发词：** 深度阅读、深度分析、文章解读、URL 链接、抓取网页

---

## daily-news

每天生成一份中文纯文本简报，内容来自 [news.topurl.cn](https://news.topurl.cn) API，包含时事热点、国内外新闻、历史上的今天、成语和名言。自动去重分类，方便直接复制分享。

**触发词：** 每日新闻、今日简报、新闻简报

---

## geek-news

从 [geek.keyi.ma](https://geek.keyi.ma) 获取 AI 整理的极客科技新闻，生成纯文本简报。数据来源于 Tavily 搜索引擎以及 Hacker News，由 AI 生成标题、摘要和标签。

**触发词：** 极客日报、geek news、科技简报、HN news summary

---

## better-prompt

> 双专家流水线式提示词优化：**Lyra**（Prompt Architect）负责从粗糙想法构建结构化初稿，**Meta**（Meta-Prompt Engineer）负责深度精炼，最终产出生产级 AI 提示词。

### 三种使用模式

| 命令 | 模式 | 适用场景 |
|------|------|---------|
| `/better-prompt <input>` | 完整流水线（Lyra → 确认 → Meta） | 从零开始，或想法还比较模糊 |
| `/better-prompt lyra: <input>` | 仅 Lyra | 快速构建结构化初稿 |
| `/better-prompt meta: <input>` | 仅 Meta | 已有 prompt，只需深度精炼 |

### 工作流程

```
用户输入（想法 / 现有 prompt）
    ↓
[Lyra] 分析复杂度 → 选择模式（TURBO / ARCHITECT）→ 构建结构化初稿
    ↓
用户确认（检查点：可调整方向后再继续）
    ↓
[Meta] 诊断扫描 → 应用高级框架（CoT / Tree of Thoughts / Step-Back）→ 安全加固 → 输出终稿
```

### 两位专家

**Lyra — Prompt Architect**
- 擅长将模糊想法转化为结构清晰的 prompt 初稿
- 自动评估复杂度：简单任务秒出（TURBO），复杂任务先提几个关键问题再构建（ARCHITECT）
- 产出：优化后的 prompt + 设计决策说明

**Meta — Meta-Prompt Engineer**
- 资深精炼专家，不从零构建，专注于把现有 prompt 打磨到专业水准
- 工具箱：认知框架注入（CoT、自洽性验证、思维树）、安全防护加固（注入防御、幻觉缓解）、结构优化
- 产出：精炼后的终稿 + 关键改进清单 + 已知局限说明

### 核心护栏

- **只优化 prompt，绝不执行它** — 给一个"写诗"的 prompt 进来，改进这条指令而不是去写诗
- **绝不编造上下文** — 缺信息就问用户，不凭空捏造品牌名、受众、场景等细节
- **自动匹配用户语言** — 中文输入得到中文输出

### 智能边界处理

| 场景 | 自动行为 |
|------|---------|
| "优化这个提示词" + 粘贴现有 prompt | 直接走 Meta 精炼 |
| "帮我写一个提示词" | 走完整流水线 |
| 输入极短（1-2 个词） | 先追问一个澄清问题 |
| 用户粘贴超长现有 prompt | 默认 Meta Only |

**触发词：** 优化提示词、写系统提示词、prompt engineering、改进 prompt、`/better-prompt`

---

## mean-assistant

> 技术专家，但表达方式充满刻薄的专业讽刺。精准答案 + 毒舌风格，复杂问题反而会得到尊重。

**触发词：** `/mean`、毒舌、刻薄、讽刺、挖苦

### 核心原则

**黄金比例**：讽刺内容 ≤ 40%，实质内容 ≥ 60%

### 刻薄度评分

| 问题等级 | 特征 | 讽刺强度 |
|---------|------|---------|
| 1级 | 基础常识、一搜就有答案 | 5/5（最高） |
| 2级 | 简单搜索可解决的常识 | 4/5 |
| 3级 | 需要专业知识的普通问题 | 3/5 |
| 4级 | 深度推理、系统设计、复杂调试 | 2/5 |
| 5级 | 展现深度思考的前沿问题 | 1/5（最低） |

### 使用示例

```
用户: "AI是怎么工作的？"
→ 5/5 刻薄度：毫不留情讽刺 + 完整技术解释

用户: "在CAP定理约束下，如何权衡一致性和可用性？"
→ 1/5 刻薄度：略带讽刺的认可 + 深度专业分析
```

---

## 使用方式

### Claude Code

在对话中直接用自然语言触发，Claude 会根据上下文激活对应技能。也可以用 `/` 命令直接调用某个 skill。

```
"帮我配置一个 AI 助手 Workspace" → openclaw-workspace-builder
"帮我梳理一下这个产品方向"        → pm-strategist
"根据刚才的讨论写个 PRD"         → spec-engineer
"做一个可以点击的 demo"          → frontend-prototype-builder
"现在搜一下最新消息"             → max-search
"帮我深度分析这篇公众号文章"       → deep-reader
"给我一份极客日报"               → geek-news
"用毒舌风格解释一下"             → mean-assistant
```

### OpenClaw

直接在聊天中告诉 OpenClaw Bot 安装目标仓库即可，它会自动完成克隆和注册：

```
请安装这个仓库的 Skill：https://github.com/icheer/skills/tree/main/max-search
```

安装后在对话中直接叫技能名，或用 `/` 命令调用。

---

## 参考

- [OpenClaw 文档](https://docs.openclaw.ai/tools/skills)
- [ClawHub — Skills 商店](https://clawhub.com)
- [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)

---

[MIT License](LICENSE)
