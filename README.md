# AI Skills 集合

> 本目录包含用于 Claude Code 的各种 AI Skills，涵盖新闻简报、产品开发工作流、网络搜索等功能。

## 目录结构

```
skills/
├── daily-news/              # 每日新闻简报生成
├── great-product-skills/   # 产品开发团队工作流
│   ├── product-team-lead/  # 产品团队负责人 (阿七)
│   ├── pm-strategist/      # 产品策略师
│   ├── spec-engineer/      # 需求文档工程师
│   ├── frontend-prototype-builder/ # 前端原型构建
│   └── ux-walkthrough/     # UX 走查专家
├── max-search-skills/      # Tavily 搜索工具
│   ├── tavily-keyword-extractor/  # 关键词拆解
│   └── tavily-max-search/ # 并行搜索执行
└── noiz-ai-skills/         # 类人化语音技能集合
    ├── characteristic-voice/  # 情绪化语音
    ├── chat-with-anyone/      # 对话任意对象
    ├── daily-news-caster/     # 新闻播报
    ├── tts/                   # 文字转语音
    └── video-translation/     # 视频翻译
```

## Skills 详情

### 1. daily-news — 每日新闻简报

生成每日的纯文本新闻简报，包含天气、新闻、历史事件、成语、语录等信息。

**核心功能：**
- 从 topurl.cn API 获取数据
- 智能去重和分类（时事/国内/国际/商业）
- 输出纯文本格式，方便复制分享

**使用方式：**
```bash
# 获取数据
python3 fetch_news.py > today.json

# 生成简报
python3 generate_briefing.py today.json
```

**触发关键词：** 每日新闻、新闻简报、今日简报

---

### 2. great-product-skills — 产品开发团队工作流

一个完整的 4 阶段产品开发流程，包含产品讨论、需求文档编写、前端原型构建、UX 走查。

#### 2.1 product-team-lead (阿七)

**角色：** 产品团队负责人 / Supervisor

**职责：**
- 协调 PM 策略师、需求工程师、前端工程师、UX 评审员
- 4 阶段流水线管理
- 向上管理，给boss汇报和决策

**工作流阶段：**
| 阶段 | 成员 | 产出 |
|------|------|------|
| Phase 1 | PM Strategist | 产品讨论共识 |
| Phase 2 | Spec Engineer | 需求文档 PRD |
| Phase 3 | Frontend Engineer | 可交互原型 |
| Phase 4 | UX Reviewer | P0/P1/P2 问题报告 |

**触发关键词：** 聊聊、讨论一下、写 spec、需求文档、做 demo、出个原型、走查、检查体验

#### 2.2 pm-strategist

**角色：** 高级产品经理 / 讨论伙伴

**职责：**
- 产品方向头脑风暴
- 多维度分析（用户、商业、技术）
- 压力测试产品想法
- 构造性批评

**特点：**
- 15年+经验的高级产品经理角色
- 对话式风格，不使用bullet列表
- 支持中英混杂

**触发关键词：** 产品讨论、头脑风暴、方向可行性分析

#### 2.3 spec-engineer

**角色：** 需求文档工程师 / PRD 编写者

**职责：**
- 将产品方向转化为结构化需求文档
- Step 0 → Step 10 标准化流程
- 确保需求可测试、可执行

**流程：**
1. Step 0: 初始化（收集8项基础信息）
2. Step 1: 概述（背景 + 目标）
3. Step 2: 竞品分析（可选）
4. Step 3: 用户场景
5. Step 4: 用户流程 & 功能
6. Step 4.5: 流程图（可选）
7. Step 5-9: 高级章节（可选：遥测、实验、评测、路线图、GTM）
8. Step 10: 定稿

**输出：** 英文 Markdown 格式 PRD

**触发关键词：** 写需求文档、写 PRD、define feature、需求整理

#### 2.4 frontend-prototype-builder

**角色：** Vue 3 前端原型工程师

**职责：**
- 根据 PRD 构建可交互原型
- 使用 Vue 3 (Options API) + TDesign
- 支持单 HTML 和完整 Vite 项目

**技术栈：**
- Vue 3 (Options API only)
- TDesign (PC: tdesign-vue-next, Mobile: tdesign-mobile-vue)
- LESS (完整项目) / 纯 CSS (单文件)
- 禁止：Composition API、`<script setup>`、Tailwind、SCSS

**工作流程：**
1. 确认演示范围
2. 选择实现方式（单 HTML vs 完整项目）
3. 阅读 Spec 并映射需求
4. 按优先级实现
5. 交付预览

**触发关键词：** build a demo、prototype、前面原型、交互演示

#### 2.5 ux-walkthrough

**角色：** UX 评审专家

**职责：**
- 系统性检查前端原型
- 6 个维度评审：页面加载、视觉一致性、交互体验、流程连续性、错误处理、边缘情况
- 输出 P0/P1/P2 分级报告

**评审维度：**
- P0：阻塞核心任务、数据丢失、不可恢复状态
- P1：体验降级、可用绕过
- P2：优化建议

**触发关键词：** review the demo、UX walkthrough、走查、体验审查、原型评审

---

### 3. max-search-skills — Tavily 搜索工具

基于 Tavily API 的网络搜索工具，包含关键词拆解和并行搜索执行。

#### 3.1 tavily-keyword-extractor

**功能：** 将用户自然语言问题拆解为结构化搜索关键词

**核心能力：**
- 语义理解（口语→标准术语）
- 多维度拆解（定义、新闻、数据、观点、对比、技术）
- 智能判断是否需要搜索

**输出格式：**
```json
{
  "search_queries": ["keyword1", "keyword2"],
  "num_results": 7,
  "reasoning": "简短说明"
}
```

**语言策略：**
- 英文为主：计算机科学、Web3、国际金融、前沿医学
- 中文为主：中国政策、A股、本土文化

#### 3.2 tavily-max-search

**功能：** 并行执行 Tavily 搜索并格式化结果

**前置要求：**
- Python 3.8+
- Tavily API Key

**配置方式：**
```bash
# 配置 API Key
python scripts/search.py config --set-api-key YOUR_KEY

# 执行搜索
python scripts/search.py search --question "问题" --search-json '{...}'
```

**特点：**
- 并行执行（需要 aiohttp）
- 自动过滤低质量域名
- 超时控制（30秒）

---

### 4. noiz-ai-skills — 类人化语音技能集合

> 此技能托管在独立仓库 [noiz-ai-skills](https://github.com/icheer/noiz-ai-skills/tree/main/skills)

**技能列表：**

| 技能名称 | 功能说明 |
|---------|---------|
| **characteristic-voice** | 情绪化/人格化语音能力 |
| **chat-with-anyone** | 与任意对象对话 |
| **daily-news-caster** | 每日新闻播报 |
| **template-skill** | 技能模板（示例） |
| **tts** | 文字转语音流程 |
| **video-translation** | 视频翻译 |

---

## 使用方式

### Claude Code

```bash
# 使用 Skill 工具
/skill-name

# 或者在对话中触发
# 例如："帮我写个 PRD" → 触发 spec-engineer
# 例如："做个 demo" → 触发 frontend-prototype-builder
```

### OpenClaw

#### 安装 Skills

在聊天中直接告诉 OpenClaw Bot 安装远程仓库的 Skills，提供仓库 URL 即可：

> "请安装这个仓库的 Skills：https://github.com/icheer/noiz-ai-skills"

或者细化到特定路径：

> "安装 /tree/main/skills 下面的 characteristic-voice 技能"

OpenClaw 会自动处理克隆和安装。

#### 调用 Skills

在对话中直接使用技能名称，或使用内置的 `/` 命令。

---

## 参考链接

- [OpenClaw 官方文档](https://docs.openclaw.ai/tools/skills)
- [ClawHub - Skills 商店](https://clawhub.com)
- [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)

---

## 许可证

[MIT License](LICENSE)
