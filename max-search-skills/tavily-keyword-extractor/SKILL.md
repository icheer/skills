---
name: tavily-keyword-extractor
description: >
  Use this skill when you need to decompose a user's natural language question
  into structured search keywords for Tavily or other web search APIs. Analyzes
  semantic intent and generates orthogonal search queries that maximize
  information coverage. Activate when the user asks factual questions requiring
  real-time web data, or when preparing search parameters before calling search
  tools. Works with both English and Chinese queries.
---

# Tavily Keyword Extractor — 搜索关键词拆解器

将用户的自然语言问题拆解为多维度的搜索关键词，输出标准化的 JSON 配置供 Tavily 搜索使用。

## 核心能力

- 语义理解：识别口语化表达背后的标准术语（如"打工人" → "职场人士 上班族"）
- 多维拆解：按定义、新闻、数据、观点、对比、技术等维度生成正交关键词
- 智能判断：区分需要搜索的问题 vs 可直接回答的问题
- 问题改写：将模糊或口语化的问题改写为更精准的搜索友好表达

## 输出格式

严格输出 JSON，无其他文字：

```json
{
  "refined_question": "改写后的专业化问题",
  "search_queries": ["keyword1", "keyword2"],
  "num_results": 7,
  "reasoning": "为什么选择这些关键词的简短说明"
}
```

## 拆解策略

### 1. 判断是否需要搜索

**不需要搜索**（返回空数组）：

- 闲聊问候："你好"、"怎么样"
- 纯逻辑/数学："1+1等于几"、"排序算法原理"
- 翻译改写："帮我润色这段话"
- 上下文缺失："他在哪里？"

**需要搜索**：

- 实时数据："最新股价"、"今天天气"
- 事实核查："某公司是否倒闭"
- 行业分析："AI 发展趋势"
- 观点对比："专家如何评价某事件"

### 2. 多维度拆解（选择 1-5 个维度）

| 维度         | 说明        | 示例                            |
| ---------- | --------- | ----------------------------- |
| Definition | 核心概念定义    | "DeepSeek 是什么"                |
| News       | 最新动态      | "DeepSeek 2026 news"          |
| Data       | 统计数据/市场份额 | "DeepSeek market share"       |
| Opinion    | 专家评论/争议   | "DeepSeek controversy"        |
| Comparison | 竞品对比      | "DeepSeek vs GPT-4"           |
| Technical  | 技术文档/白皮书  | "DeepSeek architecture paper" |

**正交原则**：关键词之间尽量不重叠，覆盖不同角度。

### 3. 语言策略

根据信息源分布选择语言：

**英文为主**（4:1 或 5:0）：

- 计算机科学、Web3/Crypto
- 国际金融（美股/外汇）
- 前沿医学、国际政治

**中文为主**（1:4 或 0:5）：

- 中国本土政策、A股
- 中文流行文化
- 本地生活服务

### 4. 数量控制

- **简单事实**：1-2 个关键词，`num_results: 10`
- **深度探索**：3-5 个关键词，`num_results: 5-8`
- **总条目数**：控制在 40 以内（`关键词数 × num_results ≤ 40`）

## 示例

### 示例 1：口语化表达

**输入**：打工人最近流行什么减压方式？

**输出**：

```json
{
  "refined_question": "职场人士当前主流的压力管理方法和减压活动有哪些？",
  "search_queries": [
    "职场人士 减压方式 2026",
    "上班族 压力管理 流行趋势",
    "工作压力 缓解方法 调查报告"
  ],
  "num_results": 7,
  "reasoning": "用户说的'打工人'是网络用语（指职场人士/上班族），拆解为当前趋势、管理方法、调查数据三个维度"
}
```

### 示例 2：技术话题

**输入**：DeepSeek 最近有什么进展？

**输出**：

```json
{
  "refined_question": "DeepSeek AI 在 2026 年的最新技术进展和产品发布情况",
  "search_queries": [
    "DeepSeek AI 2026 news",
    "DeepSeek latest model release",
    "DeepSeek R1 update"
  ],
  "num_results": 8,
  "reasoning": "技术公司动态，英文信息源更全面，覆盖新闻、产品发布、技术更新三个维度"
}
```

### 示例 3：不需要搜索

**输入**：Python 列表推导式怎么写？

**输出**：

```json
{
  "refined_question": "Python 列表推导式的语法结构和使用方法",
  "search_queries": [],
  "num_results": 0,
  "reasoning": "这是编程基础知识，无需实时信息，可直接用内部知识回答"
}
```

## 注意事项

- 关键词要精炼，去除停用词（"的"、"是"、"如何"等）
- 如果用户问题包含专业术语的口语化表达，在关键词中补全标准术语
- `refined_question` 应保持问题的核心意图，但使用更精准的表达
- `reasoning` 字段帮助后续步骤理解你的拆解逻辑，必须填写
- 避免关键词过于宽泛（如单独搜索"AI"），要加上具体限定词