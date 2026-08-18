# AI Skills 合集

一组为 Claude Code / OpenClaw 设计的自制 AI 技能合集，覆盖产品开发全流程、网络搜索增强、新闻简报生成及语音类工具。

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
| [pain-killer](#pain-killer) | 情绪去魔化学者：通过学术命名削弱情绪压倒性力量 |
| [life-guide](#life-guide) | 人间指南顾问：结构化生活困境分析 + 分阶段行动方案 |
| [browser-obscura](#browser-obscura) | 轻量无头浏览器自动化：网页抓取、截图、批量采集、隐身爬取 |
| [edge-tts-podcast](#edge-tts-podcast) | 播客语音生成：智能搜索语料 + AI生成对话脚本 + Edge TTS逐行合成 |

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

## pain-killer

> 通过学术命名削弱情绪的压倒性力量。"叫出魔鬼真名的瞬间，魔鬼便开始失去力量。"

**触发词：** `/pain-killer`、焦虑、抑郁、倦怠、压力、情绪困扰

### 工作方式

当你描述情绪困境时，从心理学、社会学、哲学三个视角为你的情绪提供精确的学术命名和理论阐释，解释为什么"被命名"本身就能削弱痛苦。

**这不是心理咨询** — 不提供安慰、共情或行动建议，只做学术分析。遇到危机信号（自杀/自伤意图）会立即提供紧急资源。

---

## life-guide

> 人间指南顾问：基于结构化输入生成两份深度报告（自我审视 + 破局行动），帮助用户理清困境、找到出路。

**触发词：** `/life-guide`、生活指导、人生建议、困境分析、需要建议

### 与 pain-killer 的配合使用

推荐工作流：
```
1. 用户调用 /pain-killer 描述情绪困境
   → 获得学术命名和理论分析（情绪去魔化）

2. 用户继续调用 /life-guide 提供结构化信息
   → 获得两份实用报告（自我审视 + 行动方案）
```

### 输入格式

需要提供五个结构化部分：

```markdown
## 背景信息
[你的基本情况和背景]

## 当前困境与担忧
[具体的困难和担心的事]

## 已采取的行动
[你已经尝试过什么]

## 限制条件
[你面临的约束和限制]

## 期望
[你希望达成什么目标]
```

### 输出结构

生成两份独立报告，用 `-----` 分隔：

**报告一：自我审视指南**
- 信息完整性检查 — 指出缺失的关键信息，引导补充
- 逻辑与认知自查 — 识别期望与限制的张力、认知偏差
- 沟通模式反思 — 发现沟通盲点

**报告二：破局行动指南**
- 核心问题洞察 — 揭示表象下的真正问题，展示推理过程
- 行动建议 — 短期(1-2周)、中期(1-3月)、长期方向，具体可操作
- 资源与支持 — 书籍、社群、专业服务推荐

### 核心特点

- **温暖但专业** — 使用"您"，像有经验的朋友而非冷冰冰的专家
- **展示推理** — 说明"为什么这是核心问题"和"为什么这个方案可能有效"
- **跨学科视角** — 整合心理学、社会学、系统思维
- **安全边界** — 不提供医疗诊断、法律建议，遇危机立即引导求助

**这不是心理治疗** — 提供生活规划和沟通层面的建议，不能替代专业心理咨询或医疗服务。

---

## browser-obscura

> 基于 Rust 编写的轻量无头浏览器引擎 [Obscura](https://github.com/h4ckf0r0day/obscura)，单一二进制文件驱动，无需 Node.js，比 Headless Chrome 快 ~12 倍、内存占用少 ~6 倍。

### 功能层级

| 层级 | 功能 |
|------|------|
| **基础** | 网页内容提取（HTML / Text / Markdown / Links / Assets / Cookies）、JavaScript 执行、等待策略 |
| **进阶** | 页面截图（PNG）、PDF 导出、批量并发抓取（`scrape`）、Cookie 持久化、代理配置 |
| **完整** | 隐身模式（反指纹 + 追踪器拦截）、CDP 服务器（`serve`）、Puppeteer / Playwright 集成 |

### 快速上手

```bash
# 安装（Linux/macOS）
bash browser-obscura/scripts/install-obscura.sh

# 安装（Windows PowerShell）
.\browser-obscura\scripts\install-obscura.ps1

# 获取网页纯文本
obscura fetch https://example.com --dump text

# 提取结构化数据
obscura fetch https://news.ycombinator.com --eval "
  Array.from(document.querySelectorAll('.titleline > a'))
    .map(a => ({ title: a.textContent, url: a.href }))"

# 页面截图
obscura fetch https://example.com --screenshot page.png

# 批量抓取（并发 10）
obscura scrape url1 url2 url3 --eval "document.title" --concurrency 10

# 隐身模式 + 代理
obscura --stealth --proxy socks5://user:pass@proxy:1080 fetch https://example.com
```

### 实用工具脚本

| 脚本 | 功能 |
|------|------|
| `scripts/archive-page.sh` | 一键完整归档网页（HTML / Markdown / 截图 / 链接 / 资源） |
| `scripts/monitor-news.sh` | 定时批量监控多个新闻源，保存快照 |
| `scripts/api-discovery.sh` | 从页面资源中发现 API 端点 |
| `scripts/stealth-crawler.sh` | 隐身模式爬虫，支持代理和随机延迟 |
| `scripts/test-suite.sh` | 完整功能验证套件 |

### 注意事项

- ⚠️ **截图不支持 CJK 字体**：Obscura 不内置中文/日文/韩文字体，截图中的 CJK 文字会渲染为方框。文本提取（`--dump text / markdown`）不受影响。
- 截图 / PDF 功能需要带 `render` 特性的构建版本（官方二进制已包含）。
- `scrape` 命令依赖 `obscura-worker`，需与主程序放在同一目录。

**触发词：** `/browser-obscura`、无头浏览器、网页截图、批量抓取、网页归档、隐身爬虫

---

## edge-tts-podcast

> 播客语音自动生成流水线：从一个想法/URL/关键词出发，自动搜索语料 → AI 生成自然对话脚本 → 逐行调用 Edge TTS 合成音频 → 拼接成完整播客 MP3。TTS 直连微软、零配置，支持断点续传和跨会话恢复。

### 5 阶段工作流

```
Phase 0: 环境检查（TTS 后端连通性 + TAVILY_API_KEY）
    ↓
Phase 1: 引导式需求收集（主题、时长、音色、语言风格）
    ↓  （创建工作目录 {yyyy-MM-dd}_{topic}/ ）
Phase 2: 语料搜索与收集（Tavily 搜索 / WebFetch URL / 保存到 sources/）
    ↓
Phase 3: 播客文字稿生成（双人对话 CSV: done / voice_id / content / speed / pitch）
    ↓
Phase 4: 逐行 TTS 生成（调用 Edge TTS API，断点续传，更新 done 列）
    ↓
Phase 5: 音频拼接（MP3 二进制拼接 + 行间静音，输出 podcast.mp3）
```

### 核心特性

**智能语料采集**
- **URL 输入** — 伪装微信浏览器 UA，绕过反爬检测，提取纯文本（无 HTML 噪音）
- **关键词搜索** — 3-4 个正交查询并行搜索（Tavily），自动抓取 Top 5 高相关度结果
- **自动补充** — URL 内容不足时，自动生成补充搜索查询

**播客脚本生成**
- **引导式交互** — 逐步明确主题、类型（单人/双人）、时长（短/中/长）、音色方案
- **自然对话风格** — 基于专业提示词（`prompts/podcast_script.md`）生成高质量对话
- **CSV 格式** — Tab 分隔，包含 `done / voice_id / content / speed / pitch` 五列
- **音色场景适配** — 根据播客主题推荐合适的音色组合（科技/生活/商业/体育等）

**可靠 TTS 生成**
- **零配置直连** — 内置微软 Edge TTS 完整调用链（HMAC 签名换取 token → SSML 合成），默认无需任何 TTS 相关环境变量
- **代理逃生舱** — 配置 `TTS_BASE_URL` 即可切回 Cloudflare Worker 代理，应对直连被限流/被墙
- **逐行串行处理** — 每行生成完立即原子更新 `done` 列，确保断点续传
- **跨会话恢复** — 在新会话中继续未完成任务，自动跳过已生成的行
- **本地文本清洗** — 去 Markdown / Emoji / URL / 引用数字，按标点智能分块

**音频拼接**
- **纯 Python 实现** — 无需 ffmpeg，二进制 MP3 拼接 + ID3 标签处理
- **行间静音** — 可配置 250ms / 500ms / 750ms / 1000ms 静音间隔

### 音色推荐

| 播客类型 | 推荐组合 | 理由 |
| --- | --- | --- |
| **科技/数码** | 云扬（男）+ 晓涵（女） | 专业稳重 + 知性大方 |
| **商业/财经** | 云扬（男）+ 晓墨（女） | 双方都偏播音腔，契合商业严肃调性 |
| **生活方式** | 云希（男）+ 晓晓（女） | 阳光活泼 + 温暖治愈 |
| **情感/心理** | 晓晓（女）+ 云希（男） | 温暖倾听者 + 阳光陪伴者 |
| **体育/电竞** | 云健（男）+ 晓伊（女） | 激情解说 + 元气助攻 |

完整音色列表和场景适配指南见 `references/edge_tts_voices.md`。

### 工作目录结构

```
{yyyy-MM-dd}_{topic}/
├── meta.md              # 播客元信息（主题、参数、搜索策略、语料清单）
├── lines.csv            # 播客文字稿（tab 分隔，done 列追踪进度）
├── sources/             # 语料文件（article.md / 1.md / 2.md …）
├── voices/              # 逐行音频（1.mp3 / 2.mp3 …）
└── podcast.mp3          # 最终拼合产物
```

### 环境配置

只需一个环境变量（优先级：系统环境变量 → `~/.env`）：

```bash
TAVILY_API_KEY=tvly-your_key_here              # Tavily 搜索 API Key（必需）
```

支持多 Key 轮询，用逗号拼接即可，每次运行随机选用一个以分摊配额：

```bash
TAVILY_API_KEY=tvly-11111,tvly-22222,tvly-33333
```

TTS 默认直连微软，无需配置。仅当直连被限流或不可达时，才需要指定代理：

```bash
TTS_BASE_URL=https://your-worker.workers.dev   # 可选，Edge TTS Worker 地址
TTS_API_KEY=your_tts_api_key_here              # 可选，仅当该 worker 启用鉴权
```

配置模板见 `.env.example`。用 `python scripts/tts.py --check` 可查看当前后端并实测连通性。

### 技术依赖

| 组件 | 依赖 | 说明 |
| --- | --- | --- |
| `scripts/fetch_article.py` | requests + beautifulsoup4 | 自动安装 |
| `scripts/tts.py` | 纯 Python（stdlib） | 无额外依赖，内置微软 TTS 调用链 |
| `scripts/concat.py` | 纯 Python（stdlib） | 无额外依赖 |
| `scripts/search.sh` | bash + curl | macOS / Linux / Git Bash |
| `scripts/search.ps1` | PowerShell（系统自带） | Windows 回退方案 |

所有 Python 脚本兼容 **Python 3.7+**。

### 使用示例

```
用户: 帮我做一期关于"AI Agent 最新进展"的播客

Agent:
 → Phase 0: 检查 TTS 后端（直连微软 ✅）+ TAVILY_API_KEY ✅
 → Phase 1: 引导式提问（主题确认、时长选择、音色方案）
 → Phase 2: Tavily 搜索 3 个正交查询 → 抓取 Top 5 结果 → 保存到 sources/
 → Phase 3: 生成 lines.csv（40-60 行，男女对话）
 → Phase 4: 调用 tts.py 逐行生成音频（显示进度：[3/50]）
 → Phase 5: 调用 concat.py 拼接 → podcast.mp3

✅ 播客生成完成！
📁 工作目录: 2026-08-17_ai-agent-trends/
🎙️ 音频文件: podcast.mp3（约 8 分钟）
```

**触发词：** `/edge-tts-podcast`、帮我生成播客、做一期播客、制作播客音频、生成播客

---

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
"我最近感觉很焦虑压力很大"        → pain-killer
"帮我分析一下我的生活困境"        → life-guide
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
