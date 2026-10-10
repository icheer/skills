---
name: context-dev
description: >
  Direct Context.dev API toolkit: web search, page scraping (markdown /
  HTML / screenshot / structured JSON / highlights), site URL mapping,
  crawling, deep-research answers with sources, brand & company data,
  company news, and document parsing — all via one bash + curl + jq
  script. No MCP, no SDK, no Python. Multi-key rotation and
  context-budgeted output built in.

  **Slash command**: `/context-dev <任务描述>`

  Activate on: "scrape", "抓取这个网页", "读取这个链接", "打开这个网址看看",
  "网页截图", "screenshot this page", "爬取这个网站", "crawl this site",
  "提取这个页面的数据", "结构化提取", "列出这个网站的 URL", "这家公司的信息",
  "品牌查询", "公司logo", "公司相关新闻", "解析这个 PDF/文档",
  "深度研究并给出结论和来源", or any task that needs current web page
  content, structured web data extraction, or research with citations.
  Also activates for explicit web search when the task needs page-level
  reading right after search.

  Cost-aware by default: answers defaults to fast mode, crawl defaults to
  10 pages, stdout is truncated to a budget while full responses are
  always saved to files.
metadata:
  version: "1.0"
  source: 改造自 Context.dev 官方 integration skill v5.3
  last_verified: "2026-10-10"
license: MIT
---

# Context.dev 直调工具

通过 `ctx.sh`(bash + curl + jq)直接调用 Context.dev API 获取网页数据,无需 MCP / SDK / Python。

```bash
bash {{INSkillDir}}/scripts/ctx.sh <子命令> [参数]
```

## 环境与 Key

- **依赖**: `bash` + `curl` + `jq`
- **Key**: 环境变量 `CONTEXT_DEV_API_KEY` 或 `~/.env` 中的同名行;**多个 key 用逗号分隔**,每次调用随机轮换(分摊额度,401/403/429 自动切换下一个)
- 首次使用先验证:`bash {{INSkillDir}}/scripts/ctx.sh check --live`(0 credits)
- 输出目录 `/tmp/context-dev/`(可用 `CTX_OUT_DIR` 覆盖),2 天前的旧响应自动清理

## 快速路由表

**永远选最窄的操作**——能用专用端点就不要用通用 scrape:

| 任务 | 命令 | credits |
|---|---|---|
| 网页搜索 | `search "query"` | 1/10条 |
| 读单个页面→Markdown | `scrape <url>` | 1 |
| YouTube 视频转写(带时间戳)+元数据 | `scrape <youtube-url>` | 1 |
| 公开 PDF/文档 URL→文字 | `scrape <pdf-url>` | 1(+OCR页) |
| 页面问答(找相关段落) | `scrape <url> --formats hl --query "问题"` | 1(+1有结果时) |
| 结构化提取**单页**字段 | `scrape <url> --formats json --schema '{...}'` | 1(+4成功时) |
| 结构化提取**整站**(爬多页按 Schema 出对象) | `extract <url> --schema '{...}'` | 10 |
| CSS 选择器提取(无LLM) | `scrape <url> --formats parse --rules '{"name":{"selector":"h1"}}'` | 1 |
| 网页截图(视口) | `scrape <url> --formats screenshot` | 1 |
| 网页**整页**截图 | `scrape <url> --formats screenshot --full-page` | 1 |
| 网页**元素**截图 | `scrape <url> --formats screenshot --shot-selector "css"` | 1 |
| 商品页数据 | `scrape <url> --formats product` | 1(+1) |
| 原始文件下载 | `scrape <url> --formats bytes` | 1 |
| 列出网站全部 URL | `map <domain>` | 1(带 --search 为 2) |
| 爬取站点(≤500页/次) | `crawl <url> --max-pages N` | 1/页 |
| 深度研究→JSON+来源 | `answers "task"`(默认 fast) | fast 10 / ultra 100 |
| 公司档案(logo/规模/行业EIC标签/联系方式) | `brand --domain stripe.com` | 10 |
| 品牌模糊搜索 | `brandsearch "stripe"` | 1 |
| 网站 design style/字体 | `styleguide <domain>` | 10 |
| 公司相关新闻 | `news --domain x.com` | 1/10条 |
| 文本/公司描述→NAICS/SIC 行业代码 | `raw GET "/web/naics?input=<urlencode>"` | 0-1 |
| PDF/DOCX 文件→Markdown | `parse <file>`(扫描件加 `--ocr`) | 1(+OCR页) |
| 其他端点(people/prefetch/monitors/batch) | `raw <METHOD> <path> '<json>'` | 见官方文档 |

## 上下文预算机制(重要)

curl 原始响应可能几十上百 KB,直接进 context 会爆炸。本脚本的两级输出设计:

1. **stdout = 预算视图**:摘要行(HTTP/credits/cache/key/文件路径)+ 按 `--max-chars`(默认 6000)截断的紧凑 JSON;数组超 20 项自动封顶;截图/原始字节自动解码落盘,stdout 只留文件路径
2. **完整响应 = 文件**:stdout 第一行给出路径,需要深读时用 `Read` 工具带 `offset/limit` 分段读,或 `grep` 定位,不要 `cat` 整个文件

```
[context.dev] scrape | HTTP 200 | credits: 1 (剩余 993) | cache: hit | key: ctxt****c98d | 响应 113787 bytes
[context.dev] 完整响应: /tmp/context-dev/20261010-144228-scrape.json
[context.dev] 截图已保存: /tmp/context-dev/20261010-144228-scrape.png (png)
{"url":..., "markdown":{"success":true,"data":"...(截断到 6000 字符)"}}
```

- 预算不够(如长文完整阅读):`--max-chars 20000`,或直接读响应文件
- `--full`:stdout 完全不截断(仅小响应时用)
- crawl 默认只输出页面清单(url/title/ok),全文在文件;search 结果每条 markdown 截断 1000 字符

## 子命令详解

### search — 网页搜索

```bash
bash {{INSkillDir}}/scripts/ctx.sh search "MCP adoption 2026" --num 10
# --freshness last_24_hours|last_week|last_month|last_year   时效过滤
# --include arxiv.org,github.com --exclude pinterest.com     域名过滤
# --country us                                               地区
# --markdown  顺带抓每条结果的正文(+1 credit/10条,每条截断1000字符)
# --highlights 顺带抓每条结果的相关段落(+1 credit/10条)
# --fanout    查询扩展
```

多个正交查询**默认串行**逐个执行(并发限制见"最佳实践");仅当并发预算允许时才并行。

### scrape — 抓取单页

```bash
bash {{INSkillDir}}/scripts/ctx.sh scrape https://example.com/post
# 默认: formats=md + mainContentOnly(去导航/页脚), 缓存3天内直接命中
# --formats md,html,screenshot,images,bytes,parse,highlights,json,product  任选组合,一次访问多格式
# --query "退款政策"          highlights 模式的检索问题
# --schema '{"name":{"type":"string"},"price":{"type":"number"}}'  json 模式(+4 credits)
# --rules '{"title":{"selector":"h1"},"links":{"selector":"a","type":"list"}}'  parse 模式(无LLM)
# --fresh                     绕过缓存强制重抓
# --country jp                出口地区(2字母)
# --wait-for 2000             等 JS 渲染(毫秒或 CSS 选择器)
# --full-page                 整页截图(渲染慢,长页可达数分钟,已自动放宽超时)
# --shot-selector "#hero"     只截某个元素(矩形区域/viewport 尺寸/深色主题等用 raw 传 screenshotParams)
# --timeout 30000 --partial   超时返回部分结果
```

响应中每个格式有独立的 `success` 标志(`true/false/null`),单项失败不影响其他项——**读数据前先看 success**。

YouTube 链接用 markdown 格式即可得到带时间戳的转写;公开 PDF/文档 URL 同样直接 scrape(markdownParams 支持 `pdf.ocr/start/end` 控制页码与 OCR)。

### extract — 整站结构化提取

从起始 URL 爬多页(默认 5 页,上限 50),按 JSON Schema 提取出一个对象;适合"从这个网站把 XX 信息整理出来"类任务(定价、团队、功能列表等)。

```bash
bash {{INSkillDir}}/scripts/ctx.sh extract https://example.com/pricing \
  --schema '{"type":"object","properties":{"plans":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"price":{"type":"string"}}}}}}' \
  --instructions "优先官方定价页" --max-pages 5
# --fact-check  只采信页面上明确陈述的事实,找不到的字段为 null
# --follow-subdomains --max-depth N
```

### answers — 深度研究

```bash
bash {{INSkillDir}}/scripts/ctx.sh answers "对比 Vite 和 webpack 2026 年的生态与性能数据"
# 默认 --mode fast(10 credits);ultra 更强但 100 credits,重要问题才用
# --json-format '{"items":[{"name":"","verdict":""}]}'  指定返回结构
```

返回 `answer`(结构化结论)+ `sources`(来源 URL),回答时必须附来源链接。

注意 `--json-format` 传的是**示例对象**(给键和值类型的样例),不是 JSON Schema——与 `scrape --schema` / `extract --schema`(真 JSON Schema)不同。上限:8 层嵌套、500 个值、16,000 序列化字符;页面上查不到的事实返回 `null`,不要编造。

### map / crawl — 站点级

```bash
bash {{INSkillDir}}/scripts/ctx.sh map docs.example.com --max-links 200 --max-items 50
# --regex '/blog/' 只取匹配路径; --search "quickstart" 相关性排序; --subdomains 含子域

bash {{INSkillDir}}/scripts/ctx.sh crawl https://example.com/docs --max-pages 10 --main-content
# stdout 只列页面清单;每页 1 credit,务必用 --max-pages 控制预算(上限500)
# 大规模(≤25000页)用 raw POST /batch/submit 异步批处理
```

### brand / brandsearch / styleguide / news — 商业数据

```bash
bash {{INSkillDir}}/scripts/ctx.sh brand --domain stripe.com          # 10 credits,冷域名首查较慢(已内置75s超时)
bash {{INSkillDir}}/scripts/ctx.sh brand --name "Stripe" --country-gl us
bash {{INSkillDir}}/scripts/ctx.sh brandsearch "stripe"               # 1 credit,先搜后查可省额度
bash {{INSkillDir}}/scripts/ctx.sh styleguide stripe.com              # 10 credits,取 design tokens/字体
bash {{INSkillDir}}/scripts/ctx.sh news --domain anthropic.com --limit 10
```

brand 只能指定一种查询方式(`--domain/--name/--email/--ticker/--direct-url/--transaction`)。
公司数据是"发现的资料"而非法定记录,地址/人数/分类可能有缺失或过时。

### parse — 文档解析

```bash
bash {{INSkillDir}}/scripts/ctx.sh parse report.pdf --ocr    # 扫描件加 --ocr(每恢复页+1 credit)
```

### raw — 逃生舱

任何未封装端点或未暴露参数(viewport/theme/矩形截图/pdf 页码范围等)直接透传:

```bash
bash {{INSkillDir}}/scripts/ctx.sh raw POST /web/scrape '{"url":"https://example.com","formats":{"screenshot":true},"screenshotParams":{"area":{"x":0,"y":0,"width":1200,"height":800}},"sharedParams":{"theme":"dark"}}'
bash {{INSkillDir}}/scripts/ctx.sh raw POST /utility/prefetch '{"type":"domain","domain":"stripe.com"}'  # 0 credits,预热 brand 缓存
bash {{INSkillDir}}/scripts/ctx.sh raw GET /org/usage        # 0 credits,查余额
bash {{INSkillDir}}/scripts/ctx.sh raw POST /people/enrich '{"email":"a@b.com"}'  # 20/match, beta
```

raw 调用 `/web/scrape` 时截图/bytes 同样自动落盘,stdout 只留文件路径。

端点定义以 `https://docs.context.dev/openapi.json` 为权威。

## 错误处理速查

失败时 stderr 给出 `HTTP 状态 + error_code + message`,完整错误体在响应文件:

| 状态 | 含义 | 处理 |
|---|---|---|
| 400 | 参数错误 / 目标站屏蔽(`WEBSITE_BLOCKED`)/ PDF 仅图片 | 换 URL、加 `--fresh`、parse 加 `--ocr`;有 fallback 就用 |
| 401/403 | key 失效 / 额度尽 / 权限或付费功能 | 脚本已自动换 key;仍失败则告知用户换 key |
| 404 | 目标不存在 | 视为正常空结果 |
| 408 | 超时(`--timeout` 设的) | 提高 `--timeout`、加 `--partial`、或 brand 先 prefetch |
| 429 | 组织并发限制或每分钟请求上限(Free 并发=1) | 降并行度/改串行;脚本已自动换 key |
| 422 | 输入限制(如免费邮箱域名) | 改输入,不要原样重试 |
| 5xx | 服务端瞬时故障 | 隔几秒重试一次 |

**不要**对 400/401/403/422 原样重试。

## 最佳实践

1. **省 credit**:search/scrape 默认配置已最省;`--fresh` 只在明确要最新内容时用(默认 3 天缓存命中率很高且不损失质量);先 `brandsearch`(1)再 `brand`(10)确认目标存在
2. **省 context**:默认预算视图足够;长文用响应文件 + `Read offset/limit`;禁止对大文件 `cat`
3. **串行为默认,并行看并发预算**:并发限制按**组织**(即每个 key 所属账号)计——Free=1、Developer=10、Pro=100、Growth=250、Scale=500(旧组织为每分钟请求数,Free 30/min);超并发立刻 429。因此:
   - 默认逐条串行执行,1-3 个调用延迟完全可接受
   - 多 key 想并行时,用 `--key-index` 把并发请求**错开到不同组织**,并行度 ≤ key 数,如:
     ```bash
     bash {{INSkillDir}}/scripts/ctx.sh search "q1" --key-index 1 &
     bash {{INSkillDir}}/scripts/ctx.sh search "q2" --key-index 2 &
     wait
     ```
   - 收到 429 不要立即重试;脚本已自动轮换 key,仍失败则降并行度或串行
4. **来源**:引用 scrape/search/answers 的内容时附原始 URL
5. **给用户报账**:多次调用后可 `raw GET /org/usage`(0 credits)查余额

## 参考资料

- 官方文档:<https://docs.context.dev/introduction>(目录见 <https://docs.context.dev/llms.txt>)
- 端点权威定义:<https://docs.context.dev/openapi.json>(部分端点领先于文档,如 `/web/extract`)
- 积分与套餐:<https://docs.context.dev/account/credits>
