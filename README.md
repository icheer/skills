# AI Skills 集合

一组为 Claude Code / OpenClaw 设计的 AI 技能，覆盖产品开发全流程、网络搜索增强、新闻简报生成及语音类工具。

## 快速导航

| 技能包 | 适用场景 |
|--------|---------|
| [openclaw-workspace-builder](#openclaw-workspace-builder) | 交互式引导生成 AI 助手 Workspace 配置 |
| [great-product-skills](#great-product-skills) | 从想法到可交互原型的完整产品工作流 |
| [max-search-skills](#max-search-skills) | 基于 Tavily 的深度网络搜索 |
| [deep-reader](#deep-reader) | 网页文章深度抓取 + 认知增强分析报告 |
| [daily-news](#daily-news) | 每日中文新闻简报生成 |
| [geek-news](#geek-news) | 极客科技新闻简报生成 |

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

## max-search-skills

> 让 Claude 在回答问题前先做一次像样的搜索，而不是直接凭记忆作答。两个技能配合使用效果最佳。

### tavily-keyword-extractor

把你的自然语言问题拆解成适合搜索引擎的关键词组合。区分哪些话题适合用英文搜（CS、Web3、国际金融）、哪些用中文搜（中国政策、A股），并判断当前问题是否真的需要联网查询。

输出为 JSON，供 `tavily-max-search` 直接消费：

```json
{
  "search_queries": ["keyword1", "keyword2"],
  "num_results": 7,
  "reasoning": "为什么拆成这几个词"
}
```

### tavily-max-search

拿到关键词后并行发起多路 Tavily 搜索，聚合结果、过滤低质量域名，30 秒超时兜底。需要 Python 3.8+ 和 Tavily API Key。

```bash
# 首次配置
python scripts/search.py config --set-api-key YOUR_KEY

# 执行搜索（配合 keyword-extractor 的 JSON 输出）
python scripts/search.py search --question "你的问题" --search-json '{...}'
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

---

## 使用方式

### Claude Code

在对话中直接用自然语言触发，Claude 会根据上下文激活对应技能。也可以用 `/` 命令直接调用某个 skill。

```
"帮我配置一个 AI 助手 Workspace" → openclaw-workspace-builder
"帮我梳理一下这个产品方向"       → pm-strategist
"根据刚才的讨论写个 PRD"         → spec-engineer
"做一个可以点击的 demo"          → frontend-prototype-builder
"现在搜一下最新消息"             → max-search-skills
"帮我深度分析这篇公众号文章"      → deep-reader
"给我一份极客日报"               → geek-news
```

### OpenClaw

直接在聊天中告诉 OpenClaw Bot 安装目标仓库即可，它会自动完成克隆和注册：

```
请安装这个仓库的 Skills：https://github.com/NoizAI/skills
```

安装后在对话中直接叫技能名，或用 `/` 命令调用。

---

## 参考

- [OpenClaw 文档](https://docs.openclaw.ai/tools/skills)
- [ClawHub — Skills 商店](https://clawhub.com)
- [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)

---

[MIT License](LICENSE)
