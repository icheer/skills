# OpenClaw Workspace Builder - 使用说明

## 📦 技能包内容

```
openclaw-workspace-builder/
├── SKILL.md                    # 主技能文件(对话流程、生成逻辑)
├── references/
│   ├── generation-rules.md     # 文件生成规则详解
│   └── scenes.md               # 5大场景模板库
└── README.md                   # 本文件
```

## 🚀 安装方法

### 方法1:手动安装(推荐)

1. 将整个 `openclaw-workspace-builder/` 目录复制到:
   - **OpenClaw**: `~/.openclaw/skills/`
   - **Nanobot**: `~/.nanobot/skills/`
   - **其他平台**: 参考平台文档的技能目录位置

2. 重启AI助手,技能将自动加载

### 方法2:通过ClawHub安装(如已发布)

```bash
clawhub install openclaw-workspace-builder
```

## 💡 使用方式

### 主动调用(推荐)

在对话中输入:

```
/workspace
```

或

```
帮我配置一个AI助手的Workspace
```

### 被动触发

当用户提到以下关键词时,AI会自动建议使用本技能:

- "创建AI助手配置"
- "生成SOUL.md"
- "配置OpenClaw Workspace"
- "我想定制一个AI助手"

## 📋 使用流程

1. **第一轮提问**(3个问题):确定场景类型
2. **第二轮提问**(2-3个问题):个性化定制
3. **第三轮提问**(1-2个问题,条件触发):工具与权限
4. **确认与生成**:展示理解,等待确认后生成文件

整个过程约5分钟。

## 📄 生成的文件

### 必定生成(4个核心文件):

- **SOUL.md** - AI的性格和价值观
- **IDENTITY.md** - AI的名字和角色
- **AGENTS.md** - AI的工作流程和规则
- **USER.md** - 用户画像和偏好

### 条件生成:

- **TOOLS.md** - 当用户提到飞书/钉钉等工具时
- **MEMORY.md** - 当场景为项目管理或客服支持时

## 🎯 适用场景

- ✅ 个人行政助理(邮件、日程管理)
- ✅ 项目管理(进度跟踪、团队协作)
- ✅ 内容创作(文案、报告起草)
- ✅ 客服支持(客户咨询、问题处理)
- ✅ 数据分析(数据整理、报表生成)
- ✅ 通用助理(灵活适配)

## 🔧 平台兼容性

- **OpenClaw**: 完全兼容(默认格式)
- **Nanobot/NanoClaw**: 自动适配(IDENTITY.md合并到SOUL.md)
- **Claude Code / Cursor / Windsurf**: 遵循SoulSpec标准,理论兼容

## ⚠️ 注意事项

- 不要在生成的文件中记录密码或API Key
- 生成的文件是起点,不是终点 - 使用后可根据实际情况调整
- 如需接入飞书/钉钉等工具,需单独配置 `.mcp.json` 文件
- 本技能面向非技术用户,使用日常语言而非技术术语

## 🐛 问题反馈

如遇到以下情况,请反馈:

- 生成的文件内容空洞或不符合场景
- 对话流程卡顿或问题不清晰
- 平台兼容性问题

## 📚 参考资源

- SoulSpec开放标准
- OpenClaw官方文档
- Nanobot文档

---

**版本**: v1.0  
**创建日期**: 2026-03-13  
**适用平台**: OpenClaw / Nanobot / 通用SoulSpec兼容平台