# Browser Obscura - 快速开始指南

## 🚀 5 分钟快速上手

### 步骤 1: 安装 Obscura

**Linux/macOS:**
```bash
cd browser-obscura
bash scripts/install-obscura.sh
```

**Windows PowerShell:**
```powershell
cd browser-obscura
.\scripts\install-obscura.ps1
```

### 步骤 2: 验证安装

```bash
obscura --version
```

### 步骤 3: 第一个命令

```bash
# 获取网页内容
obscura fetch https://example.com --dump text
```

成功! 🎉

---

## 📚 学习路径

### 初学者 (10 分钟)

```bash
# 1. 获取页面标题
obscura fetch https://example.com --eval "document.title"

# 2. 转换为 Markdown
obscura fetch https://example.com --dump markdown

# 3. 提取所有链接
obscura fetch https://example.com --dump links
```

### 进阶用户 (20 分钟)

```bash
# 1. 运行基础示例
bash examples/01-basic-fetch.sh

# 2. 批量抓取
bash examples/02-batch-scrape.sh

# 3. 页面截图
bash examples/03-screenshot.sh
```

### 专家级 (30 分钟)

```bash
# 1. 隐身模式
bash examples/04-stealth-mode.sh

# 2. 网页监控
bash examples/05-monitoring.sh https://news.ycombinator.com

# 3. 数据提取管道
bash examples/06-data-extraction.sh
```

---

## 🎯 常见任务速查

### 任务: 抓取网页文本

```bash
obscura fetch <URL> --dump text
```

### 任务: 提取结构化数据

```bash
obscura fetch <URL> --eval "Array.from(document.querySelectorAll('h2')).map(h => h.textContent)"
```

### 任务: 保存截图

```bash
obscura fetch <URL> --screenshot page.png
```

### 任务: 批量处理多个 URL

```bash
obscura scrape url1 url2 url3 --eval "document.title" --concurrency 10
```

### 任务: 使用代理

```bash
obscura --proxy socks5://user:pass@proxy:1080 fetch <URL>
```

### 任务: 隐身模式爬取

```bash
obscura --stealth --proxy <PROXY> fetch <URL> --dump text
```

---

## 🔧 实用脚本

### 网页完整归档

```bash
bash scripts/archive-page.sh https://example.com
```

### 新闻监控

```bash
# 创建 URL 列表
cat > news-urls.txt << EOF
https://news.ycombinator.com
https://reddit.com/r/programming
EOF

# 开始监控 (每 5 分钟检查一次)
bash scripts/monitor-news.sh news-urls.txt 300
```

### API 端点发现

```bash
bash scripts/api-discovery.sh https://example.com
```

### 隐身爬虫

```bash
# 不使用代理
bash scripts/stealth-crawler.sh https://example.com

# 使用代理
bash scripts/stealth-crawler.sh https://example.com socks5://user:pass@proxy:1080
```

---

## 💡 最佳实践

### 1. 选择合适的等待策略

- **快速静态页面**: `--wait-until domcontentloaded`
- **普通页面**: `--wait-until load` (默认)
- **SPA 应用**: `--wait-until networkidle0`
- **动态内容**: 添加 `--wait 2-3` 秒

### 2. 处理错误和重试

```bash
# 增加超时
obscura fetch <URL> --timeout 60

# 或在脚本中实现重试逻辑
for i in {1..3}; do
  obscura fetch <URL> && break
  sleep 5
done
```

### 3. 避免被封禁

- 使用 `--stealth` 隐身模式
- 配置代理 `--proxy`
- 添加随机延迟
- 降低并发数

### 4. 优化性能

- 只提取需要的数据
- 使用 `--quiet` 减少输出
- 合理设置并发数
- 避免不必要的 `--wait`

---

## 🆘 遇到问题?

### 命令未找到

```bash
# 检查安装
which obscura

# 添加到 PATH
export PATH="$HOME/.local/bin:$PATH"
```

### 连接超时

```bash
# 增加超时时间
obscura fetch <URL> --timeout 120
```

### 截图为空

```bash
# 等待页面完全加载
obscura fetch <URL> --wait-until networkidle0 --wait 2 --screenshot page.png
```

### 更多帮助

- 查看完整文档: [SKILL.md](./SKILL.md)
- 查看示例: [examples/](./examples/)
- GitHub 问题: https://github.com/h4ckf0r0day/obscura/issues

---

## 🎓 下一步

1. 阅读完整的 [SKILL.md](./SKILL.md) 文档
2. 运行 `examples/` 目录下的所有示例
3. 尝试 `scripts/` 目录下的实用工具
4. 根据你的需求定制脚本

祝你使用愉快! 🚀
