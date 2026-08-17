---
name: edge-tts-podcast
description: >
  生成播客音频：给定一个主题/关键词/URL，自动搜索语料、生成双人（或单人）
  播客文字稿（tab分隔CSV），逐行调用 Edge TTS 服务生成音频片段，最终拼合
  成完整播客 MP3。

  **触发词**: /edge-tts-podcast, "帮我生成播客", "做一期播客", "制作播客",
  "生成播客音频", "podcast"

  支持跨会话断点续传：在已有工作目录中继续未完成的 TTS 生成任务。
---

# Edge TTS Podcast — 播客语音生成技能

利用 Tavily 搜索 + WebFetch 采集语料，AI 生成高质量双人播客脚本，
逐行调用 Edge TTS 服务，最终拼合成完整的播客 MP3 文件。

---

## 环境变量 (必须提前配置)

技能启动时立即检查以下环境变量。加载优先级：

| 优先级 | 来源 |
|--------|------|
| 1 | 系统环境变量（`$env:TTS_BASE_URL` / `export TTS_BASE_URL=`） |
| 2 | `~/.env` 文件（`KEY=VALUE` 格式） |
| 3 | 项目根目录 `.env`（仅 tts.py/concat.py 等脚本读取） |

必需变量：

```
TTS_BASE_URL=https://your-worker.workers.dev   # Edge TTS Cloudflare Worker 地址
TTS_API_KEY=your_api_key_here                  # TTS 服务 Bearer Token
TAVILY_API_KEY=tvly-your_key_here              # Tavily 搜索 API Key
```

配置模板见 `.env.example`（复制为 `~/.env` 或设置系统环境变量）。

**若环境变量未配置完整，立即提示用户配置并终止执行。**

---

## 工作目录结构

技能一旦明确播客主题，立即在**当前工作目录**创建：

```
{yyyy-MM-dd}_{topic}/
├── meta.md              # 播客元信息（随引导阶段逐步更新）
├── lines.csv            # 播客文字稿（tab分隔，见下方格式说明）
├── sources/             # 语料文件（article.md / 1.md / 2.md …）
├── voices/              # 逐行音频产物（1.mp3 / 2.mp3 …）
└── podcast.mp3          # 最终拼合产物（Phase 5 生成）
```

`{topic}` 使用英文或拼音，只含字母、数字、连字符，例如：`2026-08-17_ai-agent-trends`

---

## lines.csv 格式

Tab（`\t`）分隔，**含表头行**，行号 = 音频文件名（1.mp3 起）：

```
done	voice_id	content	speed	pitch
0	zh-CN-YunxiNeural	大家好，欢迎收听今天的播客。	1	1.0	
0	zh-CN-XiaoxiaoNeural	对，今天我们聊的话题是 AI Agent 的发展趋势。
```

| 列 | 说明 |
|----|------|
| `done` | `1` = 已完成 TTS，`0` 或空 = 待处理 |
| `voice_id` | Edge TTS 音色 ID，参考 `references/edge_tts_voices.md` |
| `content` | 说话内容（纯文本，无 Markdown/Emoji） |
| `speed` | 语速 0.25–2.0，留空使用默认（1.0） |
| `pitch` | 音调，留空使用默认 |

**注意**：表头行本身不生成音频，数据行从第 1 行开始对应 `voices/1.mp3`。

---

## 音色预设

默认使用**男女组合**（辨识度最高）：

| 预设名 | 主持人 | 嘉宾 | 说明 |
|--------|--------|------|------|
| `male_female`（默认） | `zh-CN-YunxiNeural`（云希，男） | `zh-CN-XiaoxiaoNeural`（晓晓，女） | 最高辨识度 |
| `female_male` | `zh-CN-XiaoxiaoNeural`（晓晓，女） | `zh-CN-YunxiNeural`（云希，男） | 女主持 |
| `female_female` | `zh-CN-XiaoxiaoNeural`（晓晓，女） | `zh-CN-XiaohanNeural`（晓涵，女） | 双女声 |
| `male_male` | `zh-CN-YunxiNeural`（云希，男） | `zh-CN-YunyangNeural`（云扬，男） | 双男声 |
| `news` | `zh-CN-YunyangNeural`（云扬，男，新闻风格） | `zh-CN-XiaoxiaoNeural`（晓晓，女） | 新闻播报风 |

用户可直接指定任意 voice_id（见 `references/edge_tts_voices.md`）。

---

## 工作流（5个阶段，严格顺序执行）

> ⚠️ 每个阶段完成前不得跳入下一阶段。在每个阶段边界处明确告知用户当前进入哪个阶段。

---

### Phase 0 — 前置检查

**执行时机**：技能激活后立即执行，早于任何用户交互。

**步骤**：

1. 检查 `TTS_BASE_URL`、`TTS_API_KEY`、`TAVILY_API_KEY` 是否已配置
   - 检查系统环境变量
   - 若未找到，尝试读取 `~/.env`（grep `KEY=` 格式）
2. 若任何一项缺失：
   ```
   ❌ 缺少环境变量: TTS_BASE_URL, TTS_API_KEY
   请在 ~/.env 或系统环境变量中配置以下项：
     TTS_BASE_URL=https://your-worker.workers.dev
     TTS_API_KEY=your_api_key_here
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
- 目标时长：
  - 短（3-5分钟，约600-800字）
  - 中（8-10分钟，约1600-2000字）
  - 长（15分钟，约3000字）
  - 默认：中
- 语言风格：轻松对话（默认）/ 专业严肃 / 科普趣味
- 音色方案：默认男女组合，或用户指定

**1.3 创建工作目录（尽早执行）**

只要明确了主题（step 1.1 完成后），立即：

```
1. 创建目录：{yyyy-MM-dd}_{topic}/
2. 创建 meta.md（初始版本）
3. 创建 sources/、voices/ 子目录
4. 告知用户工作目录已创建
```

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

## 搜索策略
（Phase 2 填写）

## 主要语料
（Phase 2 填写）

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
1. WebFetch 抓取 URL 内容
2. 保存为 sources/article.md
3. 简要总结文章核心观点（300字以内，写入 meta.md）
4. 若内容不足，自动生成2-3个补充搜索查询 → 执行 2.2
```

**输入类型 A/B（想法/关键词）**：

执行 2.2。

**2.2 Tavily 搜索（用于 A/B 输入，或 C 输入的补充）**

搜索策略：
1. 将用户输入拆解为 **3-4 个正交查询**
2. 每个查询 `num_results=6`，控制总条目 ≤ 24
3. 执行并行搜索：

```bash
bash {{INSkillDir}}/scripts/search.sh --num-results 6 "query1" "query2" "query3"
# Windows PowerShell:
powershell -NoProfile -ExecutionPolicy Bypass -File {{INSkillDir}}/scripts/search.ps1 -NumResults 6 "query1" "query2" "query3"
```

4. 从搜索结果中选取 **相关度 ≥ 0.7 的前5条**，WebFetch 抓取正文
5. 每篇文章提取**核心信息摘要**（500字以内），保存为 `sources/{n}.md`
6. 将搜索策略和语料清单写入 `meta.md` 的"搜索策略"和"主要语料"章节

**2.3 语料质量检查**

确保已收集到足够语料：
- 关键事实/数据至少3处
- 不同视角/来源至少2个
- 若语料严重不足，额外补充1-2次搜索

Phase 2 完成后，更新 `meta.md` 中的 Phase 2 复选框，告知用户已完成语料收集，准备生成文字稿。

---

### Phase 3 — 播客文字稿生成

**执行时机**：Phase 2 完成后。

**目标**：基于语料生成高质量、自然流畅的播客对话脚本，输出为 `lines.csv`。

**3.1 加载主提示词**

使用 `{{INSkillDir}}/prompts/podcast_script.md` 中的完整提示词作为生成指导。

**3.2 生成脚本**

基于语料和提示词，生成符合以下要求的播客对话：

- 结构：开场介绍 → 核心话题展开（2-4个子话题）→ 总结收尾
- 每轮说话 50-150 字（不宜过长，TTS 分块处理更稳定）
- 双人播客总行数建议：
  - 短（3-5分钟）：20-30 行
  - 中（8-10分钟）：40-60 行
  - 长（15分钟）：80-100 行

**3.3 写入 lines.csv**

将生成的脚本按格式写入工作目录的 `lines.csv`，所有行 `done` 列初始为 `0`。

**3.4 展示并确认**

- 在对话中展示前5行和后3行（让用户有感知）
- 告知总行数和预估时长
- 询问用户是否满意，或需要调整（可重新生成或手动修改 lines.csv）

Phase 3 完成后，更新 `meta.md`。

---

### Phase 4 — 逐行 TTS 生成

**执行时机**：Phase 3 完成，用户确认文字稿后。

**目标**：调用 TTS 服务，为 `lines.csv` 中每个未完成的行生成音频文件。

**4.1 执行 TTS 批量生成**

```bash
python {{INSkillDir}}/scripts/tts.py <workdir>
```

脚本会：
1. 读取 `lines.csv`，跳过 `done=1` 的行
2. 对每个未完成行调用 TTS API
3. 将音频保存为 `voices/{行号}.mp3`
4. 每行完成后立即将 `done` 更新为 `1`（断点续传保障）
5. 输出进度日志

**4.2 断点续传**

若在新会话中继续未完成的任务：
- Phase 0 检测到已有 `lines.csv` 时，询问用户是否继续
- 用户确认后直接执行步骤 4.1（脚本自动跳过已完成行）

**4.3 错误处理**

- 单行 TTS 失败：记录错误，跳过该行继续处理，最终报告失败行数
- API 连接失败：等待10秒后重试，最多3次，仍失败则暂停并报告

Phase 4 完成后，告知用户"所有音频片段已生成，共 N 个文件"，更新 `meta.md`。

---

### Phase 5 — 音频拼合

**执行时机**：Phase 4 完成后。

**目标**：将所有 `voices/*.mp3` 按顺序拼合为完整的 `podcast.mp3`，行间插入静音。

**5.1 执行拼合**

```bash
python {{INSkillDir}}/scripts/concat.py <workdir> --silence 500
```

参数说明：
- `--silence N`：行间静音时长，单位 ms，可选值 250/500/750/1000，默认 500
- `--output <path>`：输出路径，默认为 `<workdir>/podcast.mp3`

**5.2 完成**

- 告知用户输出文件路径和文件大小
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
- 静音间隔可适当缩短（300ms）

### 用户临时修改文字稿

若用户在 Phase 3 后手动编辑了 `lines.csv`：
- 修改的行需将 `done` 重置为 `0`（否则不会重新生成）
- 重新运行 Phase 4 即可

---

## 注意事项

1. **分阶段严格执行**：每个阶段有明确的完成标志（meta.md 复选框），不得越过
2. **工作目录优先级**：所有产物集中在工作目录，避免散落在工作区
3. **lines.csv 是状态中心**：任何时候都可以查看该文件了解进度
4. **脚本路径**：始终使用 `{{INSkillDir}}/scripts/` 前缀调用脚本
5. **静音文件**：`{{INSkillDir}}/scripts/silence/` 下需有 `250ms.mp3`、`500ms.mp3`、`750ms.mp3`、`1000ms.mp3`；若缺失，concat.py 会跳过静音插入并给出警告
