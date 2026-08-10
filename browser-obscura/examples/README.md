# Browser Obscura - 使用示例

本目录包含各种使用场景的示例脚本。

## 📁 示例列表

### 基础示例

- **01-basic-fetch.sh** - 基础网页内容获取
  - 获取纯文本
  - 提取标题
  - 获取链接
  - 转换为 Markdown
  - 提取结构化数据

- **02-batch-scrape.sh** - 批量抓取
  - 批量获取标题
  - 批量提取元数据
  - 从文件读取 URL

- **03-screenshot.sh** - 页面截图
  - 基础截图
  - 等待加载后截图
  - 延迟截图
  - 滚动后截图

### 进阶示例

- **04-stealth-mode.sh** - 隐身模式
  - 基础隐身
  - 自定义 User-Agent
  - 代理配置
  - 持久化会话

- **05-monitoring.sh** - 网页监控
  - 定期快照
  - 保存 HTML/截图
  - 提取关键指标
  - 变化对比

- **06-data-extraction.sh** - 数据提取管道
  - 多步骤数据采集
  - 批量处理
  - 生成报告

### 实用工具

- **archive-page.sh** - 完整网页归档
- **monitor-news.sh** - 新闻监控脚本
- **api-discovery.sh** - API 端点发现
- **stealth-crawler.sh** - 隐身爬虫

## 🚀 运行示例

```bash
# 运行单个示例
bash examples/01-basic-fetch.sh

# 带参数的示例
bash examples/05-monitoring.sh https://example.com

# 给所有脚本添加执行权限后直接运行
chmod +x examples/*.sh
./examples/01-basic-fetch.sh
```

## 📋 前置要求

1. **已安装 Obscura**
   ```bash
   bash scripts/install-obscura.sh
   ```

2. **可选依赖** (某些示例需要)
   - `jq` - JSON 处理
   - `curl` - HTTP 请求

## 💡 提示

- 某些示例会创建临时目录和文件
- 运行前请确保有足够的磁盘空间
- 代理相关示例需要配置 `HTTP_PROXY` 环境变量

## 🔧 故障排查

如果遇到问题：

1. 确认 obscura 已安装: `obscura --version`
2. 检查网络连接
3. 查看详细日志: 移除脚本中的 `--quiet` 参数
