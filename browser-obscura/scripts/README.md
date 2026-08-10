# Scripts 目录

本目录包含实用工具脚本和安装脚本。

## 📦 安装脚本

### install-obscura.sh (Linux/macOS)
自动下载和安装 Obscura 二进制文件。

**使用方法:**
```bash
bash scripts/install-obscura.sh
```

**功能:**
- 自动检测操作系统和架构
- 下载对应的二进制文件
- 安装到 `~/.local/bin`
- 验证安装

**环境变量:**
- `OBSCURA_VERSION`: 指定版本 (默认: latest)
- `OBSCURA_INSTALL_DIR`: 安装目录 (默认: ~/.local/bin)

### install-obscura.ps1 (Windows)
Windows PowerShell 版本的安装脚本。

**使用方法:**
```powershell
.\scripts\install-obscura.ps1
```

**参数:**
- `-Version`: 指定版本 (默认: latest)
- `-InstallDir`: 安装目录 (默认: $env:USERPROFILE\.local\bin)

---

## 🔧 实用工具

### archive-page.sh
完整归档网页的所有内容。

**使用方法:**
```bash
bash scripts/archive-page.sh <URL> [输出目录]
```

**保存内容:**
- 原始 HTML
- 渲染后的 HTML
- 纯文本
- Markdown
- 截图
- 所有链接
- 资源列表
- 元数据

**示例:**
```bash
bash scripts/archive-page.sh https://example.com
bash scripts/archive-page.sh https://example.com ./my-archive
```

### monitor-news.sh
持续监控新闻网站的更新。

**使用方法:**
```bash
bash scripts/monitor-news.sh [URL文件] [间隔秒数]
```

**准备工作:**
```bash
# 创建 URL 列表
cat > news-urls.txt << EOF
https://news.ycombinator.com
https://reddit.com/r/programming
https://dev.to
EOF

# 开始监控 (每 5 分钟)
bash scripts/monitor-news.sh news-urls.txt 300
```

**功能:**
- 批量抓取多个新闻源
- 定期保存快照
- 提取标题
- 按 Ctrl+C 停止

### api-discovery.sh
发现页面中的 API 端点。

**使用方法:**
```bash
bash scripts/api-discovery.sh <URL>
```

**功能:**
- 提取所有外部资源
- 过滤 API 相关的 URL
- 生成发现报告
- 统计资源类型

**示例:**
```bash
bash scripts/api-discovery.sh https://example.com
```

### stealth-crawler.sh
使用隐身模式的爬虫工具。

**使用方法:**
```bash
bash scripts/stealth-crawler.sh <URL> [代理地址]
```

**功能:**
- 启用隐身模式
- 支持代理
- 自定义 User-Agent
- 会话持久化
- 随机延迟

**示例:**
```bash
# 不使用代理
bash scripts/stealth-crawler.sh https://example.com

# 使用代理
bash scripts/stealth-crawler.sh https://example.com socks5://user:pass@proxy:1080

# 使用环境变量
export SOCKS5_PROXY=socks5://user:pass@proxy:1080
bash scripts/stealth-crawler.sh https://example.com
```

### test-suite.sh
完整的功能测试套件。

**使用方法:**
```bash
bash scripts/test-suite.sh
```

**测试项目:**
- 环境检查
- 基础功能
- 等待策略
- 输出格式
- 截图功能
- 批量抓取
- 示例脚本验证
- 实用工具验证

**退出代码:**
- `0`: 所有测试通过
- `1`: 部分测试失败

---

## 💡 使用技巧

### 1. 脚本组合

```bash
# 先归档，再发现 API
bash scripts/archive-page.sh https://example.com
bash scripts/api-discovery.sh https://example.com
```

### 2. 定时任务

```bash
# 使用 cron 定期运行
# 每天凌晨 2 点归档网页
0 2 * * * /path/to/scripts/archive-page.sh https://example.com
```

### 3. 批量处理

```bash
# 批量归档多个网页
for url in url1 url2 url3; do
  bash scripts/archive-page.sh "$url"
done
```

### 4. 错误处理

```bash
# 添加重试逻辑
for i in {1..3}; do
  bash scripts/archive-page.sh https://example.com && break
  sleep 10
done
```

---

## ⚙️ 自定义脚本

你可以基于这些脚本创建自己的工具:

```bash
#!/usr/bin/env bash
# my-custom-script.sh

# 引用 obscura
source scripts/archive-page.sh

# 添加自定义逻辑
# ...
```

---

## 🔍 故障排查

### 脚本无法执行

```bash
# 添加执行权限
chmod +x scripts/*.sh
```

### 找不到 obscura

```bash
# 确保已安装
which obscura

# 或运行安装脚本
bash scripts/install-obscura.sh
```

### 依赖缺失

某些脚本需要 `jq` 来处理 JSON:

```bash
# Ubuntu/Debian
sudo apt install jq

# macOS
brew install jq

# Arch Linux
sudo pacman -S jq
```
