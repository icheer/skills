# Browser Obscura - 无头浏览器自动化技能

一个轻量级、高性能的无头浏览器自动化工具,基于 Rust 编写的 Obscura 引擎。

## 📋 功能概览

- **网页内容提取**: HTML/Text/Markdown/Links/Assets/Cookies
- **JavaScript 执行**: 在页面上下文中执行自定义脚本
- **页面截图**: PNG 截图和 PDF 导出
- **批量抓取**: 并发处理多个 URL
- **隐身模式**: 反指纹和追踪器拦截
- **CDP 集成**: 支持 Puppeteer/Playwright 连接

## 🚀 快速开始

### 安装 Obscura

使用自动安装脚本:

```bash
# Linux/macOS
bash scripts/install-obscura.sh

# Windows PowerShell
.\scripts\install-obscura.ps1
```

### 基础使用

```bash
# 获取页面文本内容
obscura fetch https://example.com --dump text

# 执行 JavaScript 获取标题
obscura fetch https://example.com --eval "document.title"

# 截图
obscura fetch https://example.com --screenshot page.png
```

---

## 📖 详细功能指南

### 1. 网页内容提取 (fetch)

#### 1.1 输出格式

**HTML - 渲染后的 HTML 内容**
```bash
obscura fetch https://news.ycombinator.com --dump html > page.html
```

**Text - 纯文本内容**
```bash
obscura fetch https://en.wikipedia.org/wiki/Rust --dump text
```

**Markdown - 转换为 Markdown 格式**
```bash
obscura fetch https://docs.rs/tokio --dump markdown > docs.md
```

**Links - 提取所有链接**
```bash
obscura fetch https://example.com --dump links
# 输出: 每行一个 URL
```

**Assets - 提取所有资源 URL**
```bash
obscura fetch https://example.com --dump assets
# 输出: NDJSON 格式,包含样式表/脚本/图片/字体等
```

**Cookies - 导出所有 Cookie**
```bash
obscura fetch https://example.com --dump cookies
# 输出: JSON 数组格式
```

**Original - 原始 HTTP 响应**
```bash
# 获取 JavaScript 执行前的原始 HTML
obscura fetch https://my-spa.example --dump original > before.html

# 下载二进制文件 (图片/PDF 等)
obscura fetch https://picsum.photos/200/300 --dump original > photo.jpg
```

#### 1.2 JavaScript 执行

**获取简单值**
```bash
obscura fetch https://example.com --eval "document.title"
obscura fetch https://example.com --eval "window.location.href"
obscura fetch https://example.com --eval "document.querySelectorAll('a').length"
```

**提取结构化数据**
```bash
# 提取 Hacker News 头条
obscura fetch https://news.ycombinator.com --eval "
Array.from(document.querySelectorAll('.titleline > a'))
  .map(a => ({ title: a.textContent, url: a.href }))
"
```

**注意事项:**
- 多语句脚本如果以 `const`/`let` 开头会返回 `null`,需要用 IIFE 包裹:
```bash
obscura fetch https://example.com --eval "
(function(){
  const title = document.title;
  const url = window.location.href;
  return { title, url };
})()
"
```

#### 1.3 等待策略

**等待事件**
```bash
# 等待 DOM 内容加载
obscura fetch https://example.com --wait-until domcontentloaded

# 等待完全加载 (默认)
obscura fetch https://example.com --wait-until load

# 等待网络空闲 (500ms 内无新请求)
obscura fetch https://example.com --wait-until networkidle2

# 等待网络完全空闲 (500ms 内无任何网络活动)
obscura fetch https://example.com --wait-until networkidle0
```

**等待 CSS 选择器**
```bash
# 等待特定元素出现
obscura fetch https://example.com --selector "#content"

# 组合使用
obscura fetch https://spa.example.com \
  --wait-until networkidle0 \
  --selector ".article-content" \
  --dump markdown
```

**固定延迟**
```bash
# 等待 3 秒后再提取内容
obscura fetch https://example.com --wait 3

# 省略 --wait 则使用自适应等待 (最多 5 秒)
```

**超时控制**
```bash
# 设置 60 秒超时
obscura fetch https://slow-site.example --timeout 60
```

#### 1.4 输出控制

**保存到文件**
```bash
obscura fetch https://example.com --dump markdown -o output.md
obscura fetch https://example.com --dump html > page.html
```

**静默模式 (禁用进度输出)**
```bash
obscura fetch https://example.com --dump text --quiet
```

**与管道结合**
```bash
# 统计单词数
obscura fetch https://example.com --dump text --quiet | wc -w

# 搜索关键词
obscura fetch https://example.com --dump text --quiet | grep "keyword"

# 提取链接并过滤
obscura fetch https://example.com --dump links | grep "\.pdf$"
```

---

### 2. 页面截图

**基础截图**
```bash
obscura fetch https://example.com --screenshot page.png
```

**全页截图**
```bash
# 先滚动到底部,再截图
obscura fetch https://example.com \
  --eval "window.scrollTo(0, document.body.scrollHeight)" \
  --screenshot fullpage.png
```

**指定视口大小**
```bash
# 通过 JavaScript 设置视口
obscura fetch https://example.com \
  --eval "/* 设置视口后的截图逻辑 */" \
  --screenshot mobile.png
```

**等待加载后截图**
```bash
obscura fetch https://example.com \
  --wait-until networkidle0 \
  --screenshot page.png
```

---

### 3. 批量抓取 (scrape)

#### 3.1 基础用法

**从命令行传入 URL**
```bash
obscura scrape \
  https://example.com/page1 \
  https://example.com/page2 \
  https://example.com/page3 \
  --eval "document.title"
```

**从文件读取 URL**
```bash
# urls.txt 每行一个 URL
obscura scrape - --eval "document.title" < urls.txt

# 或使用管道
cat urls.txt | obscura scrape - --eval "document.title"
```

#### 3.2 并发控制

```bash
# 默认并发数为 10
obscura scrape url1 url2 url3 --eval "document.title"

# 设置并发数为 25
obscura scrape url1 url2 url3 --concurrency 25 --eval "document.title"

# 低并发 (避免被限流)
obscura scrape url1 url2 url3 --concurrency 2 --eval "document.title"
```

#### 3.3 输出格式

**JSON 格式 (默认)**
```bash
obscura scrape url1 url2 url3 \
  --eval "({ title: document.title, url: location.href })" \
  --format json
```

**纯文本格式**
```bash
obscura scrape url1 url2 url3 \
  --eval "document.title" \
  --format text
```

#### 3.4 超时设置

```bash
# 每个 URL 的超时时间 (默认 60 秒)
obscura scrape url1 url2 url3 \
  --timeout 120 \
  --eval "document.title"
```

#### 3.5 实际应用示例

**批量提取文章元数据**
```bash
obscura scrape \
  https://blog.example.com/post-1 \
  https://blog.example.com/post-2 \
  https://blog.example.com/post-3 \
  --concurrency 10 \
  --eval "({
    title: document.querySelector('h1').textContent,
    author: document.querySelector('.author')?.textContent,
    date: document.querySelector('.date')?.textContent,
    excerpt: document.querySelector('.excerpt')?.textContent
  })" \
  --format json > articles.json
```

**监控页面变化**
```bash
# 定期检查多个页面的标题
while true; do
  obscura scrape url1 url2 url3 \
    --eval "document.title" \
    --quiet \
    --format json > snapshot.json
  sleep 300  # 每 5 分钟检查一次
done
```

---

### 4. 代理配置

#### 4.1 HTTP 代理

```bash
obscura --proxy http://user:pass@proxy.example.com:8080 \
  fetch https://example.com --dump text
```

#### 4.2 SOCKS5 代理

```bash
obscura --proxy socks5://user:pass@proxy.example.com:1080 \
  fetch https://example.com --dump text
```

#### 4.3 代理与批量抓取

```bash
# 通过代理批量抓取
obscura --proxy socks5://user:pass@proxy.example.com:1080 \
  scrape url1 url2 url3 \
  --concurrency 10 \
  --eval "document.title"
```

---

### 5. Cookie 和存储管理

#### 5.1 持久化存储

```bash
# 指定存储目录，保存 cookies 和 localStorage
obscura --storage-dir ./browser-data \
  fetch https://example.com/login --dump text

# 后续请求会自动使用之前保存的 cookies
obscura --storage-dir ./browser-data \
  fetch https://example.com/dashboard --dump text
```

#### 5.2 导出 Cookies

```bash
# 导出所有 cookies (包括 HttpOnly)
obscura fetch https://example.com --dump cookies > cookies.json
```

#### 5.3 会话保持示例

```bash
# 1. 登录并保存会话
obscura --storage-dir ./session \
  fetch https://example.com/login --wait 5

# 2. 使用保存的会话访问其他页面
obscura --storage-dir ./session \
  fetch https://example.com/profile --dump text
```

---

### 6. 隐身模式

#### 6.1 启用隐身模式

隐身模式提供：
- 一致的浏览器指纹 (TLS/HTTP/User-Agent)
- 随机化指纹 (GPU/屏幕/Canvas/音频/电池)
- 真实的 `navigator.userAgentData`
- 屏蔽 `navigator.webdriver`
- 追踪器域名拦截 (3,520+ 域名)

```bash
# 启用隐身模式
obscura --stealth fetch https://example.com --dump text

# 隐身模式 + 代理
obscura --stealth --proxy socks5://user:pass@proxy.example.com:1080 \
  fetch https://example.com --dump text

# 隐身模式 + 截图
obscura --stealth fetch https://example.com --screenshot page.png
```

#### 6.2 隐身模式最佳实践

```bash
# 完整的反检测配置
obscura --stealth \
  --proxy socks5://user:pass@proxy.example.com:1080 \
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  --storage-dir ./session \
  fetch https://example.com --dump text
```

---

### 7. CDP 服务器模式

#### 7.1 启动 CDP 服务器

```bash
# 默认端口 9222
obscura serve

# 指定端口
obscura serve --port 9333

# 启用隐身模式
obscura serve --stealth --port 9222

# 多工作进程
obscura serve --workers 4 --port 9222
```

#### 7.2 与 Puppeteer 集成

```javascript
import puppeteer from 'puppeteer-core';

const browser = await puppeteer.connect({
  browserWSEndpoint: 'ws://127.0.0.1:9222/devtools/browser',
});

const page = await browser.newPage();
await page.goto('https://news.ycombinator.com');

const stories = await page.evaluate(() =>
  Array.from(document.querySelectorAll('.titleline > a'))
    .map(a => ({ title: a.textContent, url: a.href }))
);

console.log(stories);
await browser.close();
```

#### 7.3 与 Playwright 集成

```javascript
import { chromium } from 'playwright-core';

const browser = await chromium.connectOverCDP({
  endpointURL: 'ws://127.0.0.1:9222',
});

const context = await browser.contexts()[0];
const page = await context.newPage();

await page.goto('https://en.wikipedia.org/wiki/Web_scraping');
await page.screenshot({ path: 'wikipedia.png', fullPage: true });

await browser.close();
```

---

### 8. 高级选项

#### 8.1 自定义 User-Agent

```bash
obscura --user-agent "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" \
  fetch https://example.com --dump text
```

#### 8.2 遵守 robots.txt

```bash
# 默认不遵守，启用此选项会检查 robots.txt
obscura --obey-robots fetch https://example.com --dump text
```

#### 8.3 允许本地网络访问

```bash
# 默认阻止 localhost/RFC1918/链路本地请求
# 开发测试时可启用
obscura --allow-private-network fetch http://localhost:3000 --dump text
```

#### 8.4 V8 引擎参数

```bash
# 调整 V8 堆大小
obscura --v8-flags "--max-old-space-size=4096" \
  fetch https://example.com --dump text
```

#### 8.5 环境变量

```bash
# 脚本执行超时 (毫秒)
export OBSCURA_SCRIPT_DEADLINE_MS=60000

# 响应体缓存限制 (字节)
export OBSCURA_NETWORK_BODY_BUFFER_BYTES=4194304

obscura fetch https://example.com --dump text
```

---

## 🎯 实际应用场景

### 场景 1: 新闻监控

```bash
#!/bin/bash
# monitor-news.sh - 监控新闻网站更新

URLS=(
  "https://news.ycombinator.com"
  "https://reddit.com/r/programming"
  "https://dev.to"
)

while true; do
  timestamp=$(date +%Y%m%d_%H%M%S)
  
  obscura scrape "${URLS[@]}" \
    --concurrency 3 \
    --eval "({
      url: location.href,
      title: document.title,
      headlines: Array.from(document.querySelectorAll('h1, h2, h3'))
        .slice(0, 10)
        .map(h => h.textContent.trim())
    })" \
    --format json > "snapshot_${timestamp}.json"
  
  echo "[$(date)] Snapshot saved"
  sleep 600  # 每 10 分钟检查一次
done
```

### 场景 2: 网页归档

```bash
#!/bin/bash
# archive-page.sh - 完整归档网页

URL="$1"
OUTPUT_DIR="archive_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$OUTPUT_DIR"

echo "归档: $URL"

# 1. 保存 HTML
obscura fetch "$URL" --dump html > "$OUTPUT_DIR/page.html"

# 2. 保存 Markdown
obscura fetch "$URL" --dump markdown > "$OUTPUT_DIR/page.md"

# 3. 保存截图
obscura fetch "$URL" --screenshot "$OUTPUT_DIR/screenshot.png"

# 4. 保存所有链接
obscura fetch "$URL" --dump links > "$OUTPUT_DIR/links.txt"

# 5. 保存资源列表
obscura fetch "$URL" --dump assets > "$OUTPUT_DIR/assets.ndjson"

# 6. 保存 cookies
obscura fetch "$URL" --dump cookies > "$OUTPUT_DIR/cookies.json"

echo "归档完成: $OUTPUT_DIR"
```

### 场景 3: 数据采集管道

```bash
#!/bin/bash
# scrape-pipeline.sh - 批量数据采集

# 1. 获取列表页的所有文章链接
obscura fetch https://blog.example.com \
  --dump links \
  --quiet | grep "/post/" > article_urls.txt

# 2. 批量抓取文章内容
cat article_urls.txt | obscura scrape - \
  --concurrency 20 \
  --eval "({
    url: location.href,
    title: document.querySelector('h1')?.textContent,
    author: document.querySelector('.author')?.textContent,
    date: document.querySelector('.date')?.textContent,
    content: document.querySelector('article')?.textContent,
    tags: Array.from(document.querySelectorAll('.tag')).map(t => t.textContent)
  })" \
  --format json > articles.json

# 3. 处理数据
jq '.[] | {title, author, date}' articles.json > metadata.json

echo "采集完成，共 $(wc -l < article_urls.txt) 篇文章"
```

### 场景 4: API 端点发现

```bash
#!/bin/bash
# discover-apis.sh - 发现页面中的 API 端点

URL="$1"

echo "分析: $URL"

# 提取所有外部资源
obscura fetch "$URL" --dump assets | \
  jq -r 'select(.url | test("api|graphql|rest")) | .url' | \
  sort -u > api_endpoints.txt

echo "发现 $(wc -l < api_endpoints.txt) 个可能的 API 端点"
cat api_endpoints.txt
```

### 场景 5: 隐身爬虫

```bash
#!/bin/bash
# stealth-scraper.sh - 使用隐身模式和代理的爬虫

PROXY="socks5://user:pass@proxy.example.com:1080"
STORAGE_DIR="./stealth-session"

# 创建会话目录
mkdir -p "$STORAGE_DIR"

# 第一次访问，建立会话
obscura --stealth \
  --proxy "$PROXY" \
  --storage-dir "$STORAGE_DIR" \
  --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  fetch https://example.com --wait 3

# 后续请求使用相同会话
for page in page1 page2 page3; do
  obscura --stealth \
    --proxy "$PROXY" \
    --storage-dir "$STORAGE_DIR" \
    fetch "https://example.com/$page" \
    --dump markdown > "${page}.md"
  
  sleep $(( RANDOM % 5 + 2 ))  # 随机延迟 2-7 秒
done
```

---

## ⚠️ 注意事项和限制

### 1. 与 Chrome 的差异

Obscura **不是** Chrome 的完整实现，某些功能有差异：
- ❌ Service Workers
- ❌ 原生媒体解码
- ❌ GPU 效果
- ❌ PDF 结构化输出
- ⚠️ 长尾 CSS 特性
- ⚠️ 部分 Web APIs
- ⚠️ 系统字体光栅化

### 2. 多语句 JavaScript 陷阱

```bash
# ❌ 错误：返回 null
obscura fetch https://example.com --eval "const title = document.title; title"

# ✅ 正确：使用 IIFE
obscura fetch https://example.com --eval "(function(){ const title = document.title; return title; })()"

# ✅ 或者：使用简单表达式
obscura fetch https://example.com --eval "document.title"
```

### 3. SSRF 防护

默认情况下，Obscura 阻止以下请求：
- `localhost` / `127.0.0.1`
- RFC1918 私有地址 (10.x, 172.16-31.x, 192.168.x)
- 链路本地地址

开发测试时使用 `--allow-private-network` 绕过。

### 4. scrape 命令依赖

`scrape` 命令需要 `obscura-worker` 二进制文件在同一目录或 PATH 中。

### 5. 渲染功能

截图和 PDF 功能需要使用带 `render` 特性编译的版本。官方发布的二进制文件已包含此特性。

---

## 🔧 故障排查

### 问题: 命令未找到

```bash
# 检查安装
which obscura

# 添加到 PATH (Linux/macOS)
export PATH="$HOME/.local/bin:$PATH"

# 添加到 PATH (Windows PowerShell)
$env:Path += ";$HOME\.local\bin"
```

### 问题: GLIBC 版本错误 (Linux)

```
error while loading shared libraries: libc.so.6: version 'GLIBC_2.35' not found
```

**解决方案:**
1. 升级到 Ubuntu 22.04+ 或等效版本
2. 或使用 Docker: `docker run h4ckf0r0day/obscura`
3. 或从源码编译

### 问题: macOS Gatekeeper 警告

```bash
# 移除隔离标记
xattr -d com.apple.quarantine ./obscura
```

### 问题: 截图为空白

**可能原因:**
1. 页面加载未完成 - 使用 `--wait-until networkidle0`
2. JavaScript 渲染需要时间 - 添加 `--wait 3`
3. 需要滚动 - 使用 `--eval` 滚动到目标位置

```bash
# 解决方案
obscura fetch https://example.com \
  --wait-until networkidle0 \
  --wait 2 \
  --screenshot page.png
```

### 问题: 超时错误

```bash
# 增加超时时间
obscura fetch https://slow-site.example --timeout 120

# 或调整脚本超时
export OBSCURA_SCRIPT_DEADLINE_MS=60000
```

---

## 📚 更多资源

- **官方仓库**: https://github.com/h4ckf0r0day/obscura
- **文档**: https://github.com/h4ckf0r0day/obscura/tree/main/docs
- **问题反馈**: https://github.com/h4ckf0r0day/obscura/issues

---

## 📝 最佳实践

### 1. 选择合适的等待策略

```bash
# 静态页面：快速加载
obscura fetch https://example.com --wait-until domcontentloaded

# 普通页面：平衡速度和完整性
obscura fetch https://example.com --wait-until load

# SPA 应用：等待异步内容
obscura fetch https://spa.example.com --wait-until networkidle0

# 复杂交互：组合使用
obscura fetch https://complex.example.com \
  --wait-until networkidle0 \
  --selector "#main-content" \
  --wait 2
```

### 2. 错误处理和重试

```bash
#!/bin/bash
# 带重试的 fetch

URL="$1"
MAX_RETRIES=3
RETRY_DELAY=5

for i in $(seq 1 $MAX_RETRIES); do
  if obscura fetch "$URL" --dump text --quiet > output.txt 2>/dev/null; then
    echo "成功"
    exit 0
  else
    echo "尝试 $i/$MAX_RETRIES 失败"
    [ $i -lt $MAX_RETRIES ] && sleep $RETRY_DELAY
  fi
done

echo "所有重试均失败"
exit 1
```

### 3. 速率限制

```bash
#!/bin/bash
# 限制请求速率，避免被封

URLS=(url1 url2 url3)
DELAY=2

for url in "${URLS[@]}"; do
  obscura fetch "$url" --dump text > "$(basename "$url").txt"
  sleep $DELAY
done
```

### 4. 数据验证

```bash
#!/bin/bash
# 验证抓取结果

URL="$1"
OUTPUT="page.html"

obscura fetch "$URL" --dump html > "$OUTPUT"

# 检查文件大小
if [ ! -s "$OUTPUT" ]; then
  echo "错误：输出为空"
  exit 1
fi

# 检查是否包含预期内容
if ! grep -q "<title>" "$OUTPUT"; then
  echo "警告：未找到 title 标签"
fi

echo "验证通过"
```

### 5. 资源清理

```bash
#!/bin/bash
# 自动清理临时文件

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

obscura fetch https://example.com \
  --dump html > "$TEMP_DIR/page.html"

# 处理数据
grep "keyword" "$TEMP_DIR/page.html"

# 脚本结束时自动清理
```

---

## 🎓 从入门到精通

### 新手路径

1. **第一步**: 基础内容提取
   ```bash
   obscura fetch https://example.com --dump text
   ```

2. **第二步**: 使用不同格式
   ```bash
   obscura fetch https://example.com --dump markdown
   obscura fetch https://example.com --dump links
   ```

3. **第三步**: 执行 JavaScript
   ```bash
   obscura fetch https://example.com --eval "document.title"
   ```

4. **第四步**: 等待策略
   ```bash
   obscura fetch https://example.com --wait-until networkidle0
   ```

### 进阶路径

1. **批量操作**
   ```bash
   obscura scrape url1 url2 url3 --eval "document.title"
   ```

2. **截图功能**
   ```bash
   obscura fetch https://example.com --screenshot page.png
   ```

3. **会话管理**
   ```bash
   obscura --storage-dir ./session fetch https://example.com
   ```

### 专家路径

1. **隐身模式 + 代理**
   ```bash
   obscura --stealth --proxy socks5://proxy fetch https://example.com
   ```

2. **CDP 自动化**
   ```bash
   obscura serve --stealth --port 9222
   # 然后使用 Puppeteer/Playwright 连接
   ```

3. **生产环境部署**
   ```bash
   obscura serve --workers 8 --port 9222
   ```

---

## 💡 提示和技巧

1. **快速测试**: 使用 `--quiet` 减少输出噪音
2. **调试**: 移除 `--quiet` 查看详细日志
3. **性能优化**: 根据需求选择最小的 `--wait-until` 级别
4. **避免检测**: 结合 `--stealth`、代理和随机延迟
5. **数据管道**: 利用 Unix 管道和 `jq` 处理 JSON 输出
6. **批量作业**: 使用 `xargs` 或 `parallel` 并行处理多个 URL

---

## 🔄 版本历史

- **v1.0.0** (基础版): 网页内容提取、JavaScript 执行
- **v1.1.0** (进阶版): 截图、批量抓取、Cookie 管理
- **v1.2.0** (完整版): 隐身模式、CDP 服务器、代理支持

---

**许可证**: Apache 2.0 (遵循 Obscura 项目)