---
name: sense-tts-podcast
description: >
  生成播客音频：给定一个主题/关键词/URL，自动搜索语料、生成双人（或单人）
  播客文字稿（tab分隔CSV），逐行调用商汤 SenseAudio TTS 服务（付费，按字符计费）
  生成音频片段，最终拼合成完整播客 MP3。

  **触发词**: /sense-tts-podcast, "帮我生成播客", "做一期播客", "制作播客",
  "生成播客音频", "podcast"

  支持跨会话断点续传：在已有工作目录中继续未完成的 TTS 生成任务。
---

# Sense TTS Podcast — 播客语音生成技能

利用 Tavily 搜索 + WebFetch 采集语料，AI 生成高质量双人播客脚本，
逐行调用商汤 SenseAudio TTS（非流式 `POST /v1/t2a_v2`），最终拼合成完整的播客 MP3 文件。

---

## 环境变量

加载优先级：

| 优先级 | 来源 |
|--------|------|
| 1 | 系统环境变量（`$env:TAVILY_API_KEY` / `export TAVILY_API_KEY=`） |
| 2 | `~/.env` 文件（`KEY=VALUE` 格式） |

**必需**（两项都缺一不可）：

```
TAVILY_API_KEY=tvly-your_key_here              # Tavily 搜索 API Key
SENSE_AUDIO_TOKEN=your_senseaudio_token        # 商汤 SenseAudio API Token（Bearer）
```

`TAVILY_API_KEY` 支持**多 Key 轮询**：用逗号拼接多个 Key，脚本会按逗号切分、剔除空白项，
每次运行从有效 Key 中随机选一个，用于分摊配额。

```
TAVILY_API_KEY=tvly-11111,tvly-22222,tvly-33333
```

用 `bash {{INSkillDir}}/scripts/search.sh --check` 可列出已识别的全部 Key（脱敏显示）。

可选：

```
SENSE_TTS_MODEL=sensenova-tts-2.0              # 默认值；可改 senseaudio-tts-1.5-260319
SENSE_WEB_TOKEN=v2.public.eyJ...               # 网页版通道令牌（见下方"TTS 后端选择"）
```

配置模板见 `.env.example`（复制为 `~/.env` 或设置系统环境变量）。

**⚠️ 计费提示**：与 Edge TTS 的免费方案不同，SenseAudio 是**付费服务，按合成字符数计费**
（约等于文字稿总字数）。中等时长播客（约 2500 字）全量生成一次约消耗 2500 字符额度；
单行问题用 `--line N` 定点重生成，不要整篇重跑。

**任一必需变量缺失，立即提示用户配置并终止执行。**

---

## TTS 后端选择

Phase 4 有两个可选后端，命令与 lines.csv 格式完全一致（voice_id 都用短码）：

| | `scripts/tts.py`（默认） | `scripts/web_tts.py`（网页版通道） |
|---|---|---|
| 端点 | 开放 API `api.senseaudio.cn/v1/t2a_v2` | 网页控制台 `platform.senseaudio.cn/api/voice/tts`（未公开文档） |
| 凭证 | `SENSE_AUDIO_TOKEN`（API Key，稳定） | `SENSE_WEB_TOKEN`（**网页登录态**，约 60 天过期、重新登录即轮换） |
| 音色 | 34 个标签，**受套餐限制**（Free 档仅 3 角色） | **74 角色/167 标签**，限免 SVIP 可用（含 播客才女/专业女播/利落青年 等播客向音色） |
| 计费 | 按字符计费 | 限免期间通常免费（活动可能随时结束） |
| 音频 | MP3 44.1kHz/128kbps/mono（API 直出） | WAV 24kHz **原生存放**（voices/*.wav，无损）；拼合时单次编码 MP3 |
| 静音资产 | `scripts/silence/`（44.1kHz MP3 资产） | **无需资产**（拼合时按毫秒精确生成零采样） |
| 适用 | 稳定、长期、无人值守的批量生成 | 想用丰富音色（尤其女声/SVIP）且接受偶尔换 token |

**选择建议**：需要女声、SVIP 音色或播客向音色（播客才女/利落青年等）→ 网页版通道；
追求稳定无人值守 → 开放 API。**同一期播客的 voices/ 必须来自同一后端**（`.mp3` 与
`.wav` 不能混放，concat.py 会拒绝拼合并提示）；换后端请清空 voices/ 重新生成。
网页通道最终 MP3 编码发生在 Phase 5 拼合时（需 `pip install lameenc`），拼合同时
**始终保留无损 `podcast.wav`** 作为重编码/剪辑母带。

`SENSE_WEB_TOKEN` 获取：浏览器登录 senseaudio.cn → F12 → Network → 在"文本转语音"里
试听任意音色 → 找到 `api/voice/tts` 请求 → 复制 `authorization` 头中 `Bearer ` 后的整串。
脚本对 401 会明确提示换 token，并在临近过期（<7 天）时预警。

---

## 工作目录结构

技能一旦明确播客主题，立即在**当前工作目录**创建：

```
{yyyy-MM-dd}_{topic}/
├── meta.md              # 播客元信息（随引导阶段逐步更新）
├── lines.csv            # 播客文字稿（tab分隔，见下方格式说明）
├── transcript.md        # 便于阅读的文字稿（Phase 5 自动从 lines.csv 导出）
├── podcast.srt          # 完整句子字幕（每个 CSV 行一条，不做行内切分，Phase 5 自动导出）
├── podcast_splitted.srt # 按阅读阈值切分的时间轴字幕（长句在标点附近切分，不含说话人）
├── sources/             # 可追溯语料（Tavily 原始结果、文章正文、研究笔记）
├── voices/              # 逐行音频产物（1.mp3 / 2.mp3 …）
└── podcast.mp3          # 最终拼合产物（Phase 5 生成）
```

`{topic}` 使用英文或拼音，只含字母、数字、连字符，例如：`2026-08-17_ai-agent-trends`

---

## lines.csv 格式

Tab（`\t`）分隔，**含表头行**，行号 = 音频文件名（1.mp3 起）：

```
done	voice_id	content	speed	pitch
0	male_0004_a	大家好，欢迎收听今天的播客。	1	0
0	male_0018_a	对，今天我们聊的话题是 AI Agent 的发展趋势。
```

| 列 | 说明 |
|----|------|
| `done` | `1` = 已完成 TTS，`0` 或空 = 待处理 |
| `voice_id` | SenseAudio 音色 ID，根据播客主题选择合适的音色组合，参考 `references/sense_tts_voices.md` |
| `content` | 说话内容（纯文本，无 Markdown/Emoji） |
| `speed` | 语速倍率 0.5–2.0，留空使用默认（1.0） |
| `pitch` | 音调偏移，**整数半音** -12 ～ +12，留空使用默认（0）。注意：与 Edge 版的倍率语义不同 |

**注意**：表头行本身不生成音频，数据行从第 1 行开始对应 `voices/1.mp3`。

---

## 音色预设

**根据播客主题选择合适预设**，避免音色风格与内容严重不匹配。
所有音色均为中文普通话；能否使用某个音色取决于账号套餐（Free/Plus/SVIP），
完整分级与场景组合见 `references/sense_tts_voices.md`。

**默认预设（Free 档，任何账号可用）**：

| 预设名 | 主持人 | 嘉宾 | 适合场景 |
|--------|--------|------|----------|
| `default` | `male_0004_a`（儒雅道长，男） | `male_0018_a`（沙哑青年，男） | 通用兜底：文化读书、科技漫谈、深夜电台 |
| `narrative` | `male_0004_a`（儒雅道长，男） | — （单人） | 叙事型单人播客 |
| `chill` | `male_0018_a`（沙哑青年，男） | — （单人） | 氛围型单人播客（深夜/音乐/情感） |
| `kids` | `male_0004_a`（儒雅道长，男） | `child_0001_a`（可爱萌娃，儿童） | 儿童故事、亲子内容 |

**升级套餐后的场景预设**（用到 SVIP 音色，账号无权限时 tts.py 会报 403 并中止）：

| 预设名 | 主持人 | 嘉宾 | 适合场景 |
|--------|--------|------|----------|
| `tech` | `male_0028_a`（可靠青叔，男） | `female_0036_a`（青春女声，女）※ | 科技解读、数码产品、AI/Web3、技术深度 |
| `business` | `male_0028_a`（可靠青叔，男） | `female_0027_a`（魅力姐姐，女） | 商业分析、财经投资、行业洞察、创业故事 |
| `lifestyle` | `male_0026_a`（乐观少年，男） | `female_0006_a`（温柔御姐，女） | 生活方式、旅行分享、美食探店、轻科普 |
| `emotion` | `female_0006_a`（温柔御姐，女） | `male_0018_a`（沙哑青年，男） | 情感话题、心理健康、人际关系 |
| `sports` | `male_0019_a`（孔武青年，男） | `male_0027_a`（亢奋主播，男） | 体育赛事、电竞、励志创业 |

※ `female_0036` 青春女声（≈ Edge 晓涵）仅**网页通道**（web_tts.py）可用，且与可靠青叔同为
播客六状态组，可逐行选情绪变体；API 通道（tts.py）改用 `female_0008_a` 气质学姐。

用户也可直接在 `lines.csv` 中指定任意 voice_id（完整列表见 `references/sense_tts_voices.md`）。
**选择超出套餐的音色前，先用 `python {{INSkillDir}}/scripts/tts.py --check --probe` 确认可用性。**

**情绪变体**：30 个网页通道角色带多变体（`_a`~`_f`），同一角色不同后缀 = 同音色不同演绎
状态。其中 `male_0029` 利落青年、`female_0036` 青春女声、`male_0028` 可靠青叔、
`female_0035` 知心少女共享"播客六状态"组（内容剖析/开场介绍/广告中插/轻松铺陈/细心提问/
主题升华），生成文字稿时按台词功能逐行选变体（规则见 `prompts/podcast_script.md` 的
"情绪变体选择"，完整对照表见 `references/sense_tts_voices.md`）。

---

## 工作流（5个阶段，严格顺序执行）

> ⚠️ 每个阶段完成前不得跳入下一阶段。在每个阶段边界处明确告知用户当前进入哪个阶段。

---

### Phase 0 — 前置检查

**执行时机**：技能激活后立即执行，早于任何用户交互。

**步骤**：

1. 检查 SenseAudio TTS 可用性（需要 `SENSE_AUDIO_TOKEN`）：
   ```bash
   python {{INSkillDir}}/scripts/tts.py --check
   ```
   该命令会验证 token、实测连接并列出账号可见音色。若 token 缺失/无效，
   把脚本的提示原样转达给用户，**不要修改脚本**。

   若用户想用网页版通道（更丰富音色），检查：
   ```bash
   python {{INSkillDir}}/scripts/web_tts.py --check
   ```
   （需要 `SENSE_WEB_TOKEN`；缺失时脚本会给出抓取指引）

2. 检查 `TAVILY_API_KEY` 是否已配置（系统环境变量 → `~/.env`）。若缺失：
   ```
   ❌ 缺少环境变量: TAVILY_API_KEY
   请在 ~/.env 或系统环境变量中配置：
     TAVILY_API_KEY=tvly-your_key_here
   参考: .env.example
   ```
   终止并等待用户配置后重新激活。

3. 检查是否在已有工作目录中（当前目录或子目录有 `lines.csv`）→ 询问是否继续断点任务（直接跳到 Phase 4）

---

### Phase 1 — 引导式需求收集

**执行时机**：Phase 0 通过后。

**原则**：引导式对话，每个问题等待用户回答后再问下一个。**边问边更新 `meta.md`**，不要一次性抛出所有问题。

**流程**：

**1.1 明确输入类型**

询问用户播客内容来源：
- A. 一个想法 / 主题描述（如"AI Agent 的发展趋势"）
- B. 搜索关键词（如"量子计算 2026"）
- C. 文章 URL（直接抓取内容）

**1.2 确认播客基本参数**（根据上一步答案，相机提问）

- 播客类型：双人（默认）/ 单人
- 目标时长（按实测语速约 250 字/分钟）：
  - 短（3-5分钟，约750-1250字）
  - 中（8-10分钟，约2000-2500字）
  - 长（15分钟，约3750-4000字）
  - 默认：中
- 语言风格：轻松对话（默认）/ 专业严肃 / 科普趣味
- 音色方案：默认免费档组合，或用户指定（参考 `references/sense_tts_voices.md`）；
  若选用多状态/多情绪角色（如利落青年/可靠青叔），在 meta.md 中记录变体映射
  （如：开场=`male_0029_b`、剖析=`male_0029_a`、提问=`male_0029_e`、升华=`male_0029_f`），
  供 Phase 3 逐行选变体使用

**1.3 创建工作目录（尽早执行）**

只要明确了主题（step 1.1 完成后），立即创建工作目录。

**⚠️ 重要**：必须使用**绝对路径**，避免相对路径在多轮对话中因上下文污染导致文件分散到错误位置。

**PowerShell 示例**：

```powershell
# 获取当前目录的绝对路径
$baseDir = (Get-Location).Path
$topic = "your-topic-name"  # 从用户输入提取
$dateStr = (Get-Date -Format "yyyy-MM-dd")
$workdir = Join-Path $baseDir "${dateStr}_${topic}"

# 创建目录结构
New-Item -ItemType Directory -Path $workdir -Force
New-Item -ItemType Directory -Path (Join-Path $workdir "sources") -Force
New-Item -ItemType Directory -Path (Join-Path $workdir "voices") -Force

Write-Output "工作目录已创建: $workdir"
```

**Bash 示例**：

```bash
baseDir=$(pwd)
topic="your-topic-name"
dateStr=$(date +%Y-%m-%d)
workdir="$baseDir/${dateStr}_${topic}"

mkdir -p "$workdir"/{sources,voices}
echo "工作目录已创建: $workdir"
```

将此**绝对路径**记录在 `meta.md` 第一行，并在后续所有 Phase 中使用该路径调用脚本：

```markdown
工作目录: /absolute/path/to/2026-08-18_topic-name
```

**脚本会自动**：
- 验证路径是否符合 `YYYY-MM-DD_topic` 命名约定
- 创建缺失的子目录（`sources/`、`voices/`）
- 写入 `.workdir_anchor` 锚点文件记录绝对路径

**meta.md 初始模板**：

```markdown
# 播客元信息

## 主题
{topic}

## 输入
- 类型: {想法/关键词/URL}
- 原始输入: {用户输入}

## 播客参数
- 类型: {双人/单人}
- 时长目标: {短/中/长}
- 语言风格: {轻松/专业/科普}
- 音色方案: {preset名称}
  - 主持人: {voice_id}（{角色名}）
  - 嘉宾: {voice_id}（{角色名}）（双人时）
  - 情绪变体映射（多状态/多情绪音色时填写，如 male_0029）:
    - 开场/欢迎: {voice_id 变体，如 male_0029_b}
    - 讲解/剖析: {如 male_0029_a}
    - 提问/追问: {如 male_0029_e}
    - 过渡/闲聊: {如 male_0029_d}
    - 收尾/升华: {如 male_0029_f}

## 搜索策略
（Phase 2 填写）

## 主要语料
（Phase 2 填写）

## 提示词加载
（Phase 3 填写：读取 podcast_script.md 后记录 `已加载: {yyyy-MM-dd HH:mm}`，作为生成文字稿的前置凭证）

## 生成状态
- [ ] Phase 2: 语料收集
- [ ] Phase 3: 文字稿生成
- [ ] Phase 4: TTS 生成
- [ ] Phase 5: 音频拼合
```

Phase 1 结束时，`meta.md` 应完整记录所有已确认的参数。

---

### Phase 2 — 语料搜索与收集

**执行时机**：Phase 1 完成，用户确认参数后。

**目标**：为播客脚本生成提供充分、可靠的事实性语料。

**2.1 根据输入类型执行不同策略**

**输入类型 C（URL）**：

```
1. 调用 fetch_article 脚本（伪装微信浏览器，绕过常见反爬），
   直接生成 markdown 写到 <workdir>/sources/article.md：

   # 默认（macOS / Linux / Windows + Git Bash）
   bash {{INSkillDir}}/scripts/fetch_article.sh "<url>" \
       --output "<workdir>/sources/article.md" --format markdown

   # Windows 无 Git Bash
   powershell -NoProfile -File {{INSkillDir}}/scripts/fetch_article.ps1 `
       -Url "<url>" `
       -Output "<workdir>\sources\article.md" `
       -Format markdown

   # 输出格式（自动）：
   #   # {title}
   #   来源: {url}
   #   字数: {content_length}
   #   {content}

2. 读取 sources/article.md，简要总结文章核心观点（300字以内，写入 meta.md）
3. 若内容不足（content_length < 300），自动生成2-3个补充搜索查询 → 执行 2.2
```

**脚本选型指南**：

| 环境 | 推荐脚本 | 依赖 |
|---|---|---|
| macOS / Linux | `fetch_article.sh` | bash + curl + sed/awk/grep（系统自带，零外部语言运行时） |
| Windows + Git Bash | `fetch_article.sh` | 同上 |
| Windows + PowerShell（无 Git Bash） | `fetch_article.ps1` | **零依赖**（系统自带 PowerShell 即可） |

两个脚本参数与输出格式完全一致：
- 必填：`<url>`
- 可选：`-o/--output PATH`、`-f/--format json|markdown`
- 默认行为（不传 `-o`）：JSON 输出到 stdout（向后兼容老调用方）
- `-f markdown` 必须配合 `-o`（否则 markdown 含真换行，stdout 会破坏 shell 管道假设）

两种格式对照：
- **JSON**（机器读中间产物）：`{"title", "url", "content", "content_length"}`
- **Markdown**（人读最终产物）：`# title` / `来源: url` / `字数: N` / 正文

**输入类型 A/B（想法/关键词）**：

执行 2.2。

**2.2 Tavily 搜索（用于 A/B 输入，或 C 输入的补充）**

**① 查询拆解**

将用户输入拆解为 **3-4 个正交查询**——关键词之间尽量不重叠，各自覆盖一个角度。
从以下维度中挑选：

| 维度 | 说明 | 在播客里的用处 |
|------|------|---------------|
| Definition | 核心概念是什么 | 开场向听众交代背景 |
| News | 最新动态、时间线 | 话题的由头，"最近为什么火" |
| Data | 统计数据、市场份额、基准测试 | 嘉宾口中的"有数据显示……" |
| Opinion | 专家评论、争议、批评声音 | 制造对话张力，让两人有得争 |
| Comparison | 与竞品/旧方案对比 | 主持人追问"那跟 X 比呢" |
| Technical | 论文、白皮书、技术细节 | 深度展开时的硬核支撑 |

**Data 和 Opinion 对播客尤其关键**：前者让对话有实感，避免通篇空谈；
后者提供可争论的立场，避免两位主播一路互相点头。

**② 语言策略**

按**信息源的实际分布**决定查询语言，而不是按播客的输出语言。
用英文搜到的语料，在 Phase 3 里照样转述成中文口语。

| 领域 | 推荐比例（英 : 中） |
|------|-------------------|
| 计算机科学、AI、Web3/Crypto、国际金融、前沿医学、国际政治 | 英文为主 4:1 ~ 5:0 |
| 中国本土政策、A股、中文流行文化、本地生活服务、国内互联网产品 | 中文为主 1:4 ~ 0:5 |
| 跨境话题（中美科技竞争、品牌出海、跨国监管） | 中英各半 2:2 |

英文查询的两个额外好处：一手信源更多（官方博客、论文、财报、开发者文档），且能绕开中文内容农场的多手转述。
但涉及国内语境的细节——政策名称、平台生态、用户习惯、本地价格——必须用中文查，英文报道在这些地方经常失真。

**③ 执行并行搜索**

每个查询 `num_results=6`，控制总条目 ≤ 24。**必须使用 `--output`（`-Output`）参数**，
而不是自己拼 `| tee`：脚本会把每个查询的原始 JSON 完整落盘，同时向终端打印按相关度
排序的精简摘要（每条含 score/标题/URL，以及截取前 100 字的 `content` 片段，外加
Tavily 的简短 answer），避免整段原始 JSON 刷屏或被工具截断而看不全。保留 `content`
片段是为了让 Agent 能据此判断该结果是否值得 `fetch_article` 抓取全文，而不必先落盘
再逐条打开原文：

```bash
bash {{INSkillDir}}/scripts/search.sh --num-results 6 --output "<workdir>/sources/tavily-search-results.txt" \
  "query1" "query2" "query3"
# Windows PowerShell:
powershell -NoProfile -File {{INSkillDir}}/scripts/search.ps1 `
    -NumResults 6 -Output "<workdir>\sources\tavily-search-results.txt" `
    "query1" "query2" "query3"
```

`sources/tavily-search-results.txt` 是本次检索的**最低限度、必需的可复用证据**：
它保留原始 URL、标题、摘要、相关度与 Tavily 回答，供后续审阅、重写脚本及跨会话续作使用。
即使 Agent 已从终端输出中获得足够信息，也仍未完成"收集"——必须先执行上述带落盘的命令。

**⚠️ 禁止的替代做法**：不要在终端摘要看起来不够用时，另写内联 Python/Node 脚本重新
调用 Tavily API 或手工解析原始 JSON——这会绕过落盘文件、重复消耗搜索配额，且结果不会
被持久化。终端摘要本身已经是解析好的结构化数据（由 `search.sh`/`search.ps1` 内部生成，
无需额外脚本或步骤）；若摘要缺失或格式异常，应检查是否漏传了 `--output` 参数并重新运行，
而不是自行重新实现。

**④ 结果处理**

1. 阅读终端打印的摘要（或已落盘的 `sources/tavily-search-results.txt`），从中选取 **相关度 ≥ 0.7 的 3-5 条**。优先抓取能支撑关键事实、数据或分歧观点的来源；不必为了凑数量抓取内容农场、重复转述或无法访问页面。
2. 用 fetch_article 脚本抓取所选文章，直接生成 markdown 写入 `<workdir>/sources/<n>.md`：
   ```bash
   # Unix / Git Bash（默认）
   bash {{INSkillDir}}/scripts/fetch_article.sh "<url>" \
       --output "<workdir>/sources/<n>.md" --format markdown

   # Windows PowerShell（零依赖）
   powershell -NoProfile -File {{INSkillDir}}/scripts/fetch_article.ps1 `
       -Url "<url>" `
       -Output "<workdir>\sources\<n>.md" `
       -Format markdown
   ```
   若某个页面抓取失败，保留已存在的 Tavily 原始条目，在 `sources/research-notes.md` 中注明失败原因，然后换用下一条候选来源；不要因此删除检索证据或阻塞整个任务。
3. 创建并写入 `sources/research-notes.md`。按以下格式列出实际会用于脚本的论点；每个事实性条目必须标注其来源文件和 URL，避免 Phase 3 只能依赖对终端输出的短期记忆：
   ```markdown
   # 语料研究笔记

   ## 将用于脚本的论点
   - 论点/数据：…
     - 依据：`1.md` — https://example.com/article
     - 使用方式：背景/数据/不同观点/反问

   ## 未采用或抓取失败的候选
   - https://example.com/…：重复、相关度不足或抓取失败（原因）。
   ```
4. 将搜索策略（含所选维度与语言比例的理由）和语料清单写入 `meta.md` 的
   "搜索策略"和"主要语料"章节

**2.3 语料质量检查**

确保已收集到足够语料：
- 关键事实/数据至少3处
- 不同视角/来源至少2个
- 若语料严重不足，额外补充1-2次搜索

**Phase 2 退出门槛（Phase 3 的前置条件）**

在标记 Phase 2 完成前，逐项确认：

- [ ] `sources/tavily-search-results.txt` 已存在且非空（URL 输入直接抓取时，至少存在 `sources/article.md`）
- [ ] `sources/research-notes.md` 已存在且至少列出 3 条将用于脚本的论点；URL 输入且无需补充搜索时，也必须为原文写此笔记
- [ ] 已抓取至少 2 篇高价值页面，**或**在研究笔记中说明为何只能依赖原文/Tavily 摘要（例如页面受限、主题缺乏一手长文）
- [ ] `meta.md` 已更新搜索策略、语料清单和 Phase 2 勾选状态

搜索结果显示在当前对话或终端中，**不等于**完成语料收集；在以上文件没有写入并核对前，
不得宣称"语料已充分"、不得勾选 Phase 2，也不得进入 Phase 3。通过门槛后，告知用户已完成语料收集，准备生成文字稿。

---

### Phase 3 — 播客文字稿生成

**执行时机**：Phase 2 完成后。

**目标**：基于已落盘、可追溯的语料生成高质量、自然流畅的播客对话脚本，输出为 `lines.csv`。

**开始前检查**：先读取 `sources/research-notes.md`，以其中已标注来源的论点作为脚本依据。仅在需要核对具体数据、引文、归因或补足上下文时，按需读取 `sources/tavily-search-results.txt` 或对应单篇文章的相关片段；不得一次性全文读取全部原始搜索结果及文章正文。若 Phase 2 的退出门槛未满足，返回 Phase 2 补齐产物；不能以对话记忆或终端摘要代替。

**3.1 加载主提示词（硬性门槛）**

**未完整读取 `{{INSkillDir}}/prompts/podcast_script.md` 前，禁止生成任何一行文字稿。**不得凭先验知识或本文件中的摘要直接开始写作。

读取后、写 CSV 前，先在回复中列出 3 条关键约束（从提示词中摘取，如：单轮不超过 150 字、语速基准 250 字/分钟、voice_id 必须用 meta.md 音色方案），再开始生成。

**3.2 生成脚本**

所有创作规则（角色设定、单人/双人模式、节奏、反 AI 腔、TTS 口播友好、时长估算表、最终检查清单）**以 podcast_script.md 为唯一事实源**，此处不重复。生成后按其中的"最终检查清单"逐项自查。

**3.3 写入 lines.csv**

将生成的脚本按格式写入工作目录的 `lines.csv`，所有行 `done` 列初始为 `0`。

写入前在 `meta.md` 的"提示词加载"小节记录 `已加载: {yyyy-MM-dd HH:mm}`——该标记证明 3.1 已执行，缺失时不得进入后续步骤。

**3.4 展示并确认**

- 在对话中展示前5行和后3行（让用户有感知）
- 告知总行数、总字数和预估时长（约 250 字/分钟），以及**预估计费字符数**
- 询问用户是否满意，或需要调整（可重新生成或手动修改 lines.csv）

Phase 3 完成后，更新 `meta.md`，停下来，等待用户指示，**不自动进入 Phase 4**。

---

### Phase 4 — 逐行 TTS 生成

**执行时机**：Phase 3 完成，进入中断（Human-in-the-loop），用户确认文字稿，用户明确表示可以开始生成音频时。

**目标**：调用 SenseAudio TTS 服务，为 `lines.csv` 中每个未完成的行生成音频文件。

**4.1 执行 TTS 批量生成**

默认后端（开放 API）：

```bash
python {{INSkillDir}}/scripts/tts.py <workdir>
```

或网页版通道（74 角色/167 标签，含限免 SVIP；需 `SENSE_WEB_TOKEN`）：

```bash
python {{INSkillDir}}/scripts/web_tts.py <workdir>
```

两个脚本的行为一致：
1. 读取对应 token（缺失时报错退出）
2. 读取 `lines.csv`，跳过 `done=1` 的行
3. **串行**逐行调用 TTS（不并发，避免限流并保证状态一致）
4. 保存音频：tts.py 剥离 ID3 头保存纯 MPEG 帧 `voices/{n}.mp3`（44.1kHz）；
   web_tts.py 原生保存 `voices/{n}.wav`（24kHz，无损）
5. 每行完成后立即将 `done` 更新为 `1`（原子写入，断点续传保障）
6. 输出进度日志与本次消耗的字符额度

可选参数（两个脚本相同）：
- `--line N`：只处理第 N 行（1-indexed），用于**单行定点重生成，节省计费额度**
- `--delay S`：行间等待秒数，默认 0.3s。若报 HTTP 429 被限流，加大到 1~2s

**4.2 断点续传**

若在新会话中继续未完成的任务：
- Phase 0 检测到已有 `lines.csv` 时，询问用户是否继续
- 用户确认后直接执行步骤 4.1（脚本自动跳过已完成行）

**4.3 错误处理**

- 单行 TTS 失败：记录错误，跳过该行继续处理，最终报告失败行数
- 网络失败：退避重试（10s / 20s），最多 3 次，仍失败则跳过该行并报告
- tts.py：HTTP 401 / token 无效 → **立即中止整轮运行**，提示检查 `SENSE_AUDIO_TOKEN`
- tts.py：`403 no access to the specified voice`：音色不在账号套餐内，**立即中止**；
  改用 `references/sense_tts_voices.md` 中当前套餐可用的音色后重跑（已完成行自动跳过）
- web_tts.py：HTTP 401 未登录 → **立即中止**，提示重新登录 senseaudio.cn 抓取新
  `SENSE_WEB_TOKEN`（token 约 60 天过期，重新登录即轮换）
- web_tts.py：音色 404 → 脚本自动刷新音色目录缓存并重试一次；仍失败则跳过该行
- HTTP 429（限流）：加大 `--delay` 重跑
- speed 超出 [0.5, 2.0] / pitch 超出 [-12, 12]：脚本自动钳制并警告

Phase 4 完成后，告知用户"所有音频片段已生成，共 N 个文件"，更新 `meta.md`。

---

### Phase 5 — 音频拼合

**执行时机**：Phase 4 完成后。

**目标**：将所有 `voices/*` 音频按顺序拼合为完整的 `podcast.mp3`，行间插入静音。
- MP3 片段（tts.py）：MPEG 帧字节拼接，静音取自 `scripts/silence/` 资产
- WAV 片段（web_tts.py）：PCM 无损合并，静音按毫秒精确生成（无需资产），最后**单次**
  lameenc 编码为 MP3，并**始终保留无损 `podcast.wav`**（重编码/剪辑母带；未安装
  lameenc 时仅保留 WAV 并提示安装）

拼合成功后，脚本还会尽力从 `lines.csv` 导出：
- `transcript.md`：正文使用"儒雅道长""沙哑青年"等简短说话人名称；未知音色则按首次出现顺序标为"说话人 1 / 2 / 3"，完整 `voice_id` 保留在文件开头的说话人对照表中。
- `podcast.srt`：不含说话人名称的完整句子版字幕。每个 `lines.csv` 数据行对应一条字幕，不做行内切分，适合阅读、检索、校对等场景。每段音频均读取实际时长（MP3 帧级 / WAV 采样级精确），行间静音也按实际时长计入，因此**不**用"总时长 / 行数"平均推算。
- `podcast_splitted.srt`：不含说话人名称的按阅读阈值切分版字幕。单行内超过阈值时，在靠近 50% 的句号、分号或逗号切分；切分点的时长按文本单位比例估算（SenseAudio 非流式接口没有词级时间戳），允许存在小幅偏差。适合播放器挂载观看。

两种文本产物的导出失败都只会给出警告，不影响已生成的音频。

**5.1 执行拼合**

```bash
python {{INSkillDir}}/scripts/concat.py <workdir> --silence 500
```

参数说明：
- `--silence N`：行间静音时长，单位 ms，可选值 250/500/750/1000，默认 500
- `--output <path>`：输出路径，默认为 `<workdir>/podcast.mp3`
- `--subtitle-max-length N`：单条字幕最大可见单位数，默认 `40`；中文按单字计，英文按单词计。仅影响 `podcast_splitted.srt` 的长句切分，不影响音频、`transcript.md` 或 `podcast.srt`。如需长期调整默认值，可直接修改 `concat.py` 顶部的 `DEFAULT_SUBTITLE_MAX_UNITS` 常量。

**5.2 完成**

- 告知用户输出文件路径和文件大小
- 同时告知 `transcript.md` 的输出路径（若文字稿导出成功）
- 同时告知 `podcast.srt` 与 `podcast_splitted.srt` 的输出路径和字幕条数（若字幕导出成功）
- 更新 `meta.md` 中的 Phase 5 复选框
- 输出总结：
  ```
  ✅ 播客生成完成！
  📁 工作目录: {workdir}
  🎙️ 音频文件: {workdir}/podcast.mp3
  📊 总行数: N 行，时长约 X 分钟
  ```

---

## 特殊情况处理

### 断点续传（跨会话）

Phase 0 检测逻辑：
- 扫描当前目录下符合 `{date}_{topic}` 格式的子目录
- 若存在 `lines.csv` 且有 `done=0` 的行 → 提示用户是否继续该任务
- 用户确认后：读取 `meta.md` 恢复上下文，跳转到对应阶段继续执行

### 单人播客

- `lines.csv` 所有行使用同一个 `voice_id`
- 静音间隔可适当缩短（250ms）

### 用户临时修改文字稿

若用户在 Phase 3 后手动编辑了 `lines.csv`：
- 修改的行需将 `done` 重置为 `0`（否则不会重新生成）
- 重新运行 Phase 4 即可

### 英文内容较多的话题

SenseAudio 音色全部为中文普通话，英文单词按中文口音朗读。文字稿务必遵守
podcast_script.md 的"TTS 口播友好"规则（英文缩写首次出现给中文读法、大数字口播化）。

---

## 注意事项

1. **分阶段严格执行**：每个阶段有明确的完成标志（meta.md 复选框），不得越过
2. **工作目录优先级**：所有产物集中在工作目录，避免散落在工作区
3. **lines.csv 是状态中心**：任何时候都可以查看该文件了解进度
4. **脚本路径**：始终使用 `{{INSkillDir}}/scripts/` 前缀调用脚本
5. **静音文件**：仅 MP3 通道（tts.py）需要——`{{INSkillDir}}/scripts/silence/` 下需有 `250ms.mp3`、`500ms.mp3`、`750ms.mp3`、`1000ms.mp3`（44.1kHz/128kbps/mono，与 API 输出一致）；缺失时 concat.py 跳过静音插入并警告。网页通道（WAV）无需静音资产
6. **成本意识**：TTS 按字符计费。重生成优先用 `--line N`；整篇重跑前先向用户确认
