# Browser Obscura Skill

一个轻量级、高性能的无头浏览器自动化技能，基于 [Obscura](https://github.com/h4ckf0r0day/obscura) 构建。

## 🚀 特性

- **轻量快速**: 30MB 内存占用 vs Chrome 的 200MB+
- **即时启动**: 无需等待浏览器启动时间
- **独立部署**: 单个二进制文件，无需 Node.js
- **隐身模式**: 内置反指纹和追踪器拦截
- **多输出格式**: HTML/Text/Markdown/Links/Assets/截图/PDF

## 📦 安装

### 自动安装

**Windows (PowerShell):**
```powershell
.\scripts\install-obscura.ps1
```

**Linux/macOS (Bash):**
```bash
bash scripts/install-obscura.sh
```

### 手动安装

从 [Releases](https://github.com/h4ckf0r0day/obscura/releases/latest) 下载对应平台的二进制文件。

## 📚 功能层级

### 基础版 - 网页内容提取
- 单页面抓取
- 多种输出格式
- JavaScript 执行
- 等待策略配置

### 进阶版 - 截图与批量操作
- 页面截图和 PDF 生成
- 批量 URL 抓取
- 并发控制
- Cookie 持久化
- 代理配置

### 完整版 - 高级自动化
- 隐身模式
- CDP 服务器模式
- 请求拦截
- 与 Puppeteer/Playwright 集成

## 📖 使用文档

详见 [SKILL.md](./SKILL.md) 了解完整的使用指南和示例。

## 🔧 系统要求

- **Linux**: Ubuntu 22.04+ (glibc 2.35+)
- **macOS**: 10.15+
- **Windows**: Windows 10+

## 📄 许可证

遵循 Obscura 项目的 Apache 2.0 许可证。
