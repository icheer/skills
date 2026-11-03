---
name: context-dev
description: >
  Direct Context.dev API toolkit: web search, page scraping (markdown /
  HTML / screenshot / structured JSON / highlights / prebuilt parsers for
  Maps, app stores, Reddit, TikTok, Instagram, Yelp, G2, emails/phones/
  links), site URL mapping, crawling, async batches, deep-research answers
  with sources, company search, people search & enrichment, brand &
  company data, company news, topic news, page & search monitors, and
  document parsing — all via one bash + curl + jq script. No MCP, no SDK,
  no Python. Single-key by design (multi-account rotation is banned by
  Context.dev) with context-budgeted output.

  **Slash command**: `/context-dev <任务描述>`

  Activate on: "scrape", "抓取这个网页", "读取这个链接", "打开这个网址看看",
  "网页截图", "screenshot this page", "爬取这个网站", "crawl this site",
  "提取这个页面的数据", "结构化提取", "列出这个网站的 URL", "这家公司的信息",
  "品牌查询", "公司logo", "公司相关新闻", "找一下做XX的公司", "company search",
  "找个人/联系人", "people search", "盯住这个页面的变化", "监控这个话题",
  "monitor this page", "批量抓取这些链接", "解析这个 PDF/文档",
  "深度研究并给出结论和来源", or any task that needs current web page
  content, structured web data extraction, or research with citations.
  Also activates for explicit web search when the task needs page-level
  reading right after search.

  Cost-aware by default: answers defaults to fast mode, crawl defaults to
  10 pages, stdout is truncated to a budget while full responses are
  always saved to files.
license: MIT
---

# Context.dev 直调工具

通过 `ctx.sh`(bash + curl + jq)直接调用 Context.dev API 获取网页数据,无需 MCP / SDK / Python。

```bash
bash {{INSkillDir}}/scripts/ctx.sh <子命令> [参数]
```

## 环境与 Key

- **依赖**: `bash` + `curl` + `jq`
- **Key**: 环境变量 `CONTEXT_DEV_API_KEY` 或 `~/.env` 中的同名行,**只配置一个**
- ⚠ **绝对不要配置多个账号的 key 轮流使用**:官方明确禁止("multiple accounts trigger our bot detection"),检测到多账号轮询会导致**所有关联账号同时被封、积分清零**。免费版单 key 每月 1000 积分已够用,慢就慢点。若配置里残留逗号分隔的多个 key,脚本只用第一个并打印警告——请及时清理
- 首次使用先验证:`bash {{INSkillDir}}/scripts/ctx.sh check --live`(0 credits)
- 输出目录 `/tmp/context-dev/`(可用 `CTX_OUT_DIR` 覆盖),2 天前的旧响应自动清理

## 快速路由表

**永远选最窄的操作**——能用专用端点就不要用通用 scrape:

| 任务 | 命令 | credits |
|---|---|---|
| 网页搜索(条数 1-100 任选) | `search "query" --num N` | 1/10条 |
| 读单个页面→Markdown | `scrape <url>` | 1 |
| YouTube 视频转写(带时间戳)+元数据 | `scrape <youtube-url>` | 1 |
| 公开 PDF/文档 URL→文字 | `scrape <pdf-url>` | 1(+OCR页) |
| 页面问答(找相关段落) | `scrape <url> --formats hl --query "问题"` | 1(+1有结果时) |
| 结构化提取**单页**字段 | `scrape <url> --formats json --schema '{...}'` | 1(+4成功时) |
| 结构化提取**整站**(爬多页按 Schema 出对象) | `extract <url> --schema '{...}'` | 10 |
| CSS 选择器提取(无LLM) | `scrape <url> --formats parse --rules '{...}'` | 1 |
| **预置解析器**(Maps/应用商店/Reddit/TikTok/IG/Yelp/G2/邮箱/电话/链接) | `scrape <url> --formats parse --parser <name>` | 1 |
| 网页截图(视口/整页/元素) | `scrape <url> --formats screenshot [--full-page\|--shot-selector css]` | 1 |
| 商品页数据 | `scrape <url> --formats product` | 1(+1) |
| 原始文件下载 | `scrape <url> --formats bytes` | 1 |
| 列出网站全部 URL | `map <domain>` | 1(带 --search 为 2) |
| 爬取站点(≤500页/次,同步) | `crawl <url> --max-pages N` | 1/页 |
| **批量抓取 URL 列表/整站**(异步,≤10万页) | `batch submit <urls...>` / `batch submit --crawl <url>` | 1/页 |
| 深度研究→JSON+来源 | `answers "task"`(默认 fast) | fast 10 / ultra 100 |
| **自然语言搜公司**(档案/总部/规模/融资/社交主页) | `companies "描述"` | 2/页(ultra 10;无结果免费) |
| **自然语言找人**(职位/雇主/技能/主页) | `people search "描述"` | 10/页(ultra 50;无结果免费) |
| 身份线索匹配一个人 | `people enrich --email E \| --linkedin U` | 20/匹配 |
| 公司档案(logo/规模/行业EIC标签/联系方式) | `brand --domain stripe.com` | 10 |
| 品牌模糊搜索 | `brandsearch "stripe"` | 1 |
| 网站 design style/字体 | `styleguide <domain>` | 10 |
| 公司相关新闻(按实体) | `news --domain x.com` | 1/10条 |
| **主题新闻**(自然语言,≤100条按相关性) | `news --query "主题"` | 1/10条 |
| **定时盯页面/话题变化** | `monitor page <url>` / `monitor search "query"` | page 1/次,search 2/次 |
| 文本/公司描述→NAICS/SIC 行业代码 | `raw GET "/web/naics?input=<urlencode>"` | 0-1 |
| PDF/DOCX 文件→Markdown | `parse <file>`(扫描件加 `--ocr`) | 1(+OCR页) |
| 其他端点(access-policies/webhooks 等) | `raw <METHOD> <path> '<json>'` | 见官方文档 |

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
bash {{INSkillDir}}/scripts/ctx.sh search "MCP adoption 2026" --num 5
# --num 1-100                 结果条数(要几条给几条,省额度)
# --freshness last_24_hours|last_week|last_month|last_year   时效过滤
# --include arxiv.org,github.com --exclude pinterest.com     域名过滤
# --country us --languages en,de    地区/语言过滤
# --desc-chars 800            每条 description 上限(默认 280 省上下文;新闻类查询调大可拿到匹配段落)
# --markdown  顺带抓每条结果的正文(每条返回正文的 +1 credit/条,截断1000字符)
# --highlights 顺带抓每条结果的相关段落(+1 credit/10条)
```

多个正交查询**默认串行**逐个执行(并发限制见"最佳实践");仅当并发预算允许时才并行。

### scrape — 抓取单页

```bash
bash {{INSkillDir}}/scripts/ctx.sh scrape https://example.com/post
# 默认: formats=md + mainContentOnly(去导航/页脚), 缓存3天内直接命中
# --formats md,html,screenshot,images,bytes,parse,highlights,json,product  任选组合,一次访问多格式
# --query "退款政策"          highlights 模式的检索问题
# --schema '{"name":{"type":"string"},"price":{"type":"number"}}'  json 模式(+4 credits)
# --rules '{"title":{"selector":"h1"}}'  parse 模式自定义CSS(无LLM)
# --parser reddit-post        预置解析器(见下,与 --rules 互斥,无LLM)
# 注意: --query/--schema/--rules/--parser 会自动开启对应格式,不必再写 --formats parse/json/highlights
# --prefer-md                 优先用站点自带的 Markdown 源(文档站常更干净,保留代码块/锚点)
# --page-numbers              PDF 每页加 <!-- page N --> 标记(便于引用/按页切分)
# --fresh                     绕过缓存强制重抓
# --country jp                出口地区(2字母)
# --wait-for 2000             等 JS 渲染(毫秒或 CSS 选择器)
# --full-page                 整页截图(渲染慢,长页可达数分钟,已自动放宽超时)
# --shot-selector "#hero"     只截某个元素(矩形区域/viewport 尺寸/深色主题等用 raw 传 screenshotParams)
# --timeout 30000 --partial   超时返回部分结果
```

响应中每个格式有独立的 `success` 标志(`true/false/null`),单项失败不影响其他项——**读数据前先看 success**。

YouTube 链接用 markdown 格式即可得到带时间戳的转写;公开 PDF/文档 URL 同样直接 scrape。

**预置解析器**(`--parser <name>`,1 credit,结构化输出,无需写规则;自动开启 parse 格式):
`google-maps` / `google-maps-reviews`(`--parser-sort newest|oldest|relevant|highest|lowest`, `--parser-limit ≤1000`)、`google-play(-reviews)`、`app-store(-reviews)`、`g2-reviews`、`instagram-{profile,post,feed}`、`tiktok-{profile,video,feed,comments,followers,following,user-search}`、`reddit-{post,search,subreddit,user}`(reddit 可用 `--parser-limit ≤1000` 控制条数)、`yelp-{search,reviews}`、`emails`、`phone-numbers`、`links`。
社交平台无需登录,`tiktok-video` 返回可直接下载的 `video_url`。
排序/翻页注意:`--parser-sort`/`--parser-limit` 只对 maps-reviews 和 reddit 生效;**Reddit 的评论排序要写在 URL 上**(`...?sort=top|new|qa`),Yelp 翻页用 URL `?start=20`;reddit/yelp 评论带 `author.id`/`author.url`,可跨页识别同一评论者。

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

### companies / people — 公司与人物搜索

自然语言查询,返回结构化档案;**无结果的请求免费**,适合先试再筛:

```bash
bash {{INSkillDir}}/scripts/ctx.sh companies "solar startups in California that raised a Series B" \
  --countries US --employees-min 50
# fast(默认)=2 credits/页;ultra=10,逐条核对全部条件,最多约20秒
# 返回: 名称/域名/简介/行业/总部/员工数/营收区间/融资历史/社交主页(LinkedIn/X/GitHub/Crunchbase…)

bash {{INSkillDir}}/scripts/ctx.sh people search "VPs of sales at solar companies in California" --countries US --exp-min 8
# fast(默认)=10 credits/页;ultra=50 且返回 match.confidence 0-1 置信分
# 返回: 姓名/当前职位与雇主/地点/年限/是否创始人/技能/学校/主页链接

bash {{INSkillDir}}/scripts/ctx.sh people enrich --linkedin https://www.linkedin.com/in/xxx
# 或 --email E(免费邮箱域名会 422),或 --first F --last L --company C
# 20 credits/匹配,按身份线索定位一个人并返回档案
```

查询里可用**引号精确短语**:`"payroll" OR "invoicing"`、`-"consulting"`(排除),companies/people/news 通用。

### batch — 异步批处理

一次提交 ≤10 万 URL 列表(或整站爬取)异步抓取,适合"把这几十个链接都读了";**1 credit/页**(失败页退回),提交即预留积分,结果保留 180 天:

```bash
bash {{INSkillDir}}/scripts/ctx.sh batch submit https://a.com https://b.com    # URL 列表
bash {{INSkillDir}}/scripts/ctx.sh batch submit --file urls.txt               # 每行一个 URL
bash {{INSkillDir}}/scripts/ctx.sh batch submit --crawl https://docs.example.com --max-pages 50 \
  --exclude-regex '/tag/|/blog/' --languages en        # 只跟英文页,防多语言副本吃掉配额(same_as_start_url 表跟随起始页语言)
# 通用: --formats md,html,... --parser NAME --schema JSON --main-content --prefer-md --page-numbers
# 提交返回 batch_id → status 轮询 → completed 后 results 取内容
bash {{INSkillDir}}/scripts/ctx.sh batch status <id>      # 进度/失败页/结算(0 credits)
bash {{INSkillDir}}/scripts/ctx.sh batch results <id> --limit 50 --cursor <next_cursor>   # 全文在响应文件(0 credits)
bash {{INSkillDir}}/scripts/ctx.sh batch list | cancel <id> | rm <id>
```

免费档同时只允许 1 个活跃 batch,大批量等前一个完成再提。status 结果里附 ndjson.gz 下载链接(适合超大结果集离线处理)。

### monitor — 定时监控

让 Context.dev 按周期盯着页面或全网话题,之后轮询变更即可(webhook 可选):

```bash
bash {{INSkillDir}}/scripts/ctx.sh monitor page https://competitor.com/pricing \
  --every 6h --instructions "只关心价格和套餐变化"
bash {{INSkillDir}}/scripts/ctx.sh monitor search "context.dev funding OR acquisition" \
  --every 1d --instructions "只要实质进展,忽略重复转载"
# --every 30m|6h|2d|1w(最小10分钟) --name N --exact(关闭AI过滤,每次变化都报)
# 创建即跑一次基线(page 1 credit,search 2 credits/run);之后按周期计费
bash {{INSkillDir}}/scripts/ctx.sh monitor changes [id] --limit 20   # 取变更(0 credits;search 型变更含 matched_urls/evidence;不带 id 取全部)
bash {{INSkillDir}}/scripts/ctx.sh monitor list | run <id> | rm <id> | limits   # limits 查配额(免费档 10 个)
```

默认 AI 判断哪些变化值得报告(过滤常青内容/重复转载);`--exact` 改为逐条报告。search 型每次 run 2 credits,变更带 `matched_urls`/`evidence`。

### map / crawl — 站点级

```bash
bash {{INSkillDir}}/scripts/ctx.sh map docs.example.com --max-links 200 --max-items 50
# --regex '/blog/' 只取匹配路径; --exclude-regex '/tag/|/author/' 排除匹配(优先于 --regex)
# --search "quickstart" 相关性排序(2 credits); --subdomains 含子域

bash {{INSkillDir}}/scripts/ctx.sh crawl https://example.com/docs --max-pages 10 --main-content
# stdout 只列页面清单;每页 1 credit,务必用 --max-pages 控制预算(上限500)
# --exclude-regex 排除路径; --prefer-md 优先站点自带 Markdown
# 页数多或不想等: 用 batch submit --crawl(异步,≤10万页)
```

### brand / brandsearch / styleguide / news — 商业数据与新闻

```bash
bash {{INSkillDir}}/scripts/ctx.sh brand --domain stripe.com          # 10 credits,冷域名首查较慢(已内置75s超时)
bash {{INSkillDir}}/scripts/ctx.sh brand --name "Stripe" --country-gl us
bash {{INSkillDir}}/scripts/ctx.sh brandsearch "stripe" --country US  # 1 credit,先搜后查可省额度
bash {{INSkillDir}}/scripts/ctx.sh styleguide stripe.com              # 10 credits,取 design tokens/字体
bash {{INSkillDir}}/scripts/ctx.sh news --query "EU AI Act enforcement"          # 主题新闻,≤100条按相关性
bash {{INSkillDir}}/scripts/ctx.sh news --domain anthropic.com --limit 10        # 公司实体新闻
# 过滤: --source-country us,gb --languages en,zh(文章语言)
```

brand 只能指定一种查询方式(`--domain/--name/--email/--ticker/--direct-url/--transaction`)。
公司数据是"发现的资料"而非法定记录,地址/人数/分类可能有缺失或过时。

### parse — 文档解析

```bash
bash {{INSkillDir}}/scripts/ctx.sh parse report.pdf --ocr --page-numbers   # 扫描件加 --ocr(每恢复页+1);--page-numbers 加 <!-- page N --> 标记
```

### raw — 逃生舱

任何未封装端点或未暴露参数(viewport/theme/矩形截图/pdf 页码范围等)直接透传:

```bash
bash {{INSkillDir}}/scripts/ctx.sh raw POST /web/scrape '{"url":"https://example.com","formats":{"screenshot":true},"screenshotParams":{"area":{"x":0,"y":0,"width":1200,"height":800}},"sharedParams":{"theme":"dark"}}'
bash {{INSkillDir}}/scripts/ctx.sh raw POST /utility/prefetch '{"type":"domain","domain":"stripe.com"}'  # 0 credits,预热 brand 缓存
bash {{INSkillDir}}/scripts/ctx.sh raw GET /org/usage        # 0 credits,查余额
bash {{INSkillDir}}/scripts/ctx.sh raw GET "/web/naics?input=<urlencode>"   # 行业代码分类
```

raw 调用 `/web/scrape` 时截图/bytes 同样自动落盘,stdout 只留文件路径。

端点定义以 `https://docs.context.dev/openapi.json` 为权威(个别端点如 `/web/extract` 实际可用但未收录进规范)。

## 错误处理速查

失败时 stderr 给出 `HTTP 状态 + error_code + message`,完整错误体在响应文件:

| 状态 | 含义 | 处理 |
|---|---|---|
| 400 | 参数错误 / 目标站屏蔽(`WEBSITE_BLOCKED`)/ PDF 仅图片 | 换 URL、加 `--fresh`、parse 加 `--ocr`;有 fallback 就用 |
| 401/403 | key 失效 / 权限或付费功能 | 告知用户检查 key;若 `error_code=ACCESS_POLICY_DENIED`(不扣费)是组织级域名策略拦截,换域名即可。**不要创建多个账号轮换,会被封号** |
| 402 | 积分不足(`USAGE_EXCEEDED`) | `raw GET /org/usage` 查余额;被拒操作不扣费,不要原样重试 |
| 404 | 目标不存在 | 视为正常空结果 |
| 408 | 超时(`--timeout` 设的) | 提高 `--timeout`、加 `--partial`、或 brand 先 prefetch |
| 409 | batch/monitor 状态冲突(如未完成的 batch 取 results) | 先 status 等完成再取 |
| 429 | 组织并发限制或每分钟请求上限 | 降并行度/改串行,稍后重试(被拒请求不扣费) |
| 422 | 输入限制(如免费邮箱域名/监控数量超配额) | 改输入,不要原样重试 |
| 5xx | 服务端瞬时故障 | 隔几秒重试一次 |

**不要**对 400/401/402/403/422 原样重试。

## 最佳实践

1. **省 credit**:search/scrape 默认配置已最省,`--num` 按需要几条给几条;companies/people 无结果免费,先用窄查询试探;`--fresh` 只在明确要最新内容时用(默认 3 天缓存命中率很高);先 `brandsearch`(1)再 `brand`(10)确认目标存在;批量和监控记得用完清理(`batch rm` / `monitor rm`)
2. **省 context**:默认预算视图足够;长文用响应文件 + `Read offset/limit`;禁止对大文件 `cat`
3. **串行为默认**:并发限制按组织计——新组织按并发数(Free=2、Developer=10、Pro=100、Growth=250、Scale=500),老组织按每分钟请求数;超限立刻 429。**不要**用多个账号 key 来提高并发(官方会检测并封号);串行逐条执行完全够用;收到 429 降速稍后重试
4. **单 key 原则**:只用一个 key。给用户配置指导时明确说明:多账号轮询会被检测封禁、积分清零,免费 1000 积分/月够用
5. **来源**:引用 scrape/search/answers 的内容时附原始 URL
6. **给用户报账**:多次调用后可 `raw GET /org/usage`(0 credits)查余额

## 参考资料

- 官方文档:<https://docs.context.dev/introduction>(目录见 <https://docs.context.dev/llms.txt>)
- 端点权威定义:<https://docs.context.dev/openapi.json>(部分端点领先于文档,如 `/web/extract`)
- 积分与套餐:<https://docs.context.dev/account/credits>
