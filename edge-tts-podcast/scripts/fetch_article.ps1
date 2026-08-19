#!/usr/bin/env pwsh
# =============================================================================
# Edge TTS Podcast - 文章抓取脚本（Windows PowerShell 版，零依赖）
# =============================================================================
# 为「没有 Git Bash、也没有 Python bs4」的 Windows 用户提供的纯 PowerShell
# 实现。仅依赖系统自带的 PowerShell（Windows PowerShell 5.1 或 PowerShell 7+），
# 无需 bash / curl / Python / 任何第三方包。
#
# 功能：伪装微信浏览器抓取 URL -> HTML 清理 -> 纯文本抽取 -> 输出 JSON 或 Markdown
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File fetch_article.ps1 -Url <url> [-Output PATH] [-Format json|markdown]
#   powershell -NoProfile -ExecutionPolicy Bypass -File fetch_article.ps1 -Url <url> -Output <path> -Format markdown
#
#   默认行为（兼容老调用）：JSON 输出到 stdout
#
#   -Output PATH         输出到指定文件（缺省输出到 stdout）
#   -Format json|markdown 输出格式（仅在指定 -Output 时生效；缺省 json）
#                        markdown 格式自动加 "# title" / 来源: url / 字数: N 前缀
#
# 输出与 fetch_article.sh 一致：{"title","url","content","content_length"}
#   content        —— 纯文本（无 Markdown 转换，与 .sh 一致）
#   content_length —— 中文字符数 + 英文词数（统计于截断前）
# =============================================================================

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,

    [Parameter(Mandatory = $false)]
    [string]$Output = '',

    [Parameter(Mandatory = $false)]
    [ValidateSet('json', 'markdown')]
    [string]$Format = 'json'
)

$ErrorActionPreference = 'Stop'

# 统一 UTF-8 输出，避免中文乱码
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 兼容旧系统：启用 TLS 1.2；注册代码页编码（供 GBK 解码，PS7 需要）
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}
try {
    [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
} catch {}

# 校验 URL
if ($Url -notmatch '^https?://') {
    [Console]::Error.WriteLine('Error: Invalid URL')
    exit 1
}

# markdown 格式必须配合 -Output（否则 markdown 含真换行，stdout 会破坏管道假设）
if ($Format -eq 'markdown' -and [string]::IsNullOrEmpty($Output)) {
    [Console]::Error.WriteLine('Error: -Format markdown requires -Output PATH')
    exit 1
}

# -----------------------------------------------------------------------------
# 抓取原始字节（伪装微信浏览器），并按页面 charset 解码为字符串
# -----------------------------------------------------------------------------
function Get-HtmlString([string]$targetUrl) {
    $req = [System.Net.HttpWebRequest]::Create($targetUrl)
    $req.Method = 'GET'
    $req.Timeout = 15000
    $req.AllowAutoRedirect = $true
    # 自动解压 gzip/deflate，避免拿到二进制垃圾
    $req.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 NetType/WIFI MicroMessenger/7.0.20.1781(0x6700143B) WindowsWechat(0x63090a13) UnifiedPCWindowswechat(0xf254101f) XWEB/16389 SideBar Flue'
    $req.Accept = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8'
    $req.Referer = 'https://www.bing.com/'
    # 附加请求头（部分为受限头，逐个 try 以防抛错）
    foreach ($h in @{ 'Accept-Language' = 'zh-CN,zh;q=0.9,en;q=0.8' }.GetEnumerator()) {
        try { $req.Headers.Add($h.Key, $h.Value) } catch {}
    }

    $resp = $req.GetResponse()
    try {
        $stream = $resp.GetResponseStream()
        $ms = New-Object System.IO.MemoryStream
        $stream.CopyTo($ms)
        $bytes = $ms.ToArray()
    } finally {
        $resp.Close()
    }

    # 检测编码：优先读取 meta charset，其次响应头，默认 UTF-8
    $charset = 'utf-8'
    $peekLen = [Math]::Min($bytes.Length, 4096)
    $asciiHead = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $peekLen)
    if ($asciiHead -match 'charset["'']?\s*=\s*["'']?\s*([a-zA-Z0-9\-_]+)') {
        $charset = $matches[1].ToLower()
    } elseif ($resp.CharacterSet) {
        $charset = $resp.CharacterSet.ToLower()
    }
    # gb2312 / gbk 统一用 gb18030（超集）解码
    if ($charset -in @('gb2312', 'gbk')) { $charset = 'gb18030' }

    try {
        $enc = [System.Text.Encoding]::GetEncoding($charset)
    } catch {
        $enc = [System.Text.Encoding]::UTF8
    }
    return $enc.GetString($bytes)
}

# -----------------------------------------------------------------------------
# 提取标题：<title> 优先，其次 <h1>；去掉常见站点名后缀
# -----------------------------------------------------------------------------
function Get-Title([string]$html) {
    $title = ''
    if ($html -match '(?is)<title[^>]*>(.*?)</title>') {
        $title = ([regex]::Replace($matches[1], '(?s)<[^>]+>', '')).Trim()
        $title = [System.Net.WebUtility]::HtmlDecode($title)
        # 要求分隔符前后都至少有 1 个空格，避免 "US-China" 这种连字符被误拆（对齐 .sh 的 sed 行为）
        $title = ($title -split '\s[-|_–—]\s')[0].Trim()
    }
    if (-not $title -and $html -match '(?is)<h1[^>]*>(.*?)</h1>') {
        $title = ([regex]::Replace($matches[1], '(?s)<[^>]+>', '')).Trim()
        $title = [System.Net.WebUtility]::HtmlDecode($title)
    }
    return $title
}

# -----------------------------------------------------------------------------
# 微信正文特例：content_noencode: JsDecode('\xNN\xNN...') —— hex 解码为 UTF-8
# -----------------------------------------------------------------------------
function Get-WechatContent([string]$html) {
    if ($html -match "content_noencode\s*:\s*JsDecode\s*\(\s*['""]([^'""]+)['""]\s*\)") {
        $hexStr = $matches[1]
        $ms = New-Object System.IO.MemoryStream
        foreach ($m in [regex]::Matches($hexStr, '\\x([0-9a-fA-F]{2})')) {
            $ms.WriteByte([Convert]::ToByte($m.Groups[1].Value, 16))
        }
        return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    }
    return $null
}

# -----------------------------------------------------------------------------
# HTML 片段 -> 纯文本：移除脚本/样式，块级标签转换行，去标签，解码实体
# -----------------------------------------------------------------------------
function Convert-HtmlToText([string]$h) {
    if (-not $h) { return '' }
    $h = [regex]::Replace($h, '(?is)<script[^>]*>.*?</script>', ' ')
    $h = [regex]::Replace($h, '(?is)<style[^>]*>.*?</style>', ' ')
    $h = [regex]::Replace($h, '(?is)<noscript[^>]*>.*?</noscript>', ' ')
    $h = [regex]::Replace($h, '(?s)<!--.*?-->', ' ')
    # 块级标签结束处插入换行，保留段落结构
    $h = [regex]::Replace($h, '(?i)<(br|/p|/div|/h[1-6]|/li|/tr|/section|/article)[^>]*>', "`n")
    # 去掉其余标签
    $h = [regex]::Replace($h, '(?s)<[^>]+>', '')
    # 解码 HTML 实体
    return [System.Net.WebUtility]::HtmlDecode($h)
}

# -----------------------------------------------------------------------------
# 混合字数统计：中文字符数 + 英文词数
# -----------------------------------------------------------------------------
function Get-ContentLength([string]$text) {
    $zh = ([regex]::Matches($text, '[一-鿿㐀-䶿豈-﫿]')).Count
    # 英文计数对齐 .sh 的 grep -oE '[A-Za-z0-9]+'：只数"纯字母数字连续串"，
    # 避免把 "2025-12-31."、"5,000."、"$1.2B" 这种带标点的 token 整体算 1 个词
    $en = ([regex]::Matches($text, '[A-Za-z0-9]+')).Count
    return $zh + $en
}

# -----------------------------------------------------------------------------
# 主流程
# -----------------------------------------------------------------------------
try {
    $html = Get-HtmlString $Url

    $title = Get-Title $html

    # 优先微信正文特例，否则依次尝试主内容容器 -> article -> body
    $wechat = Get-WechatContent $html
    if ($wechat) {
        $fragment = $wechat
    } elseif ($html -match '(?is)<(?:div|section)[^>]*(?:id|class)=["''][^"'']*(?:rich_media_content|img-content|article-content|post-content|mw-content-text|bodyContent|content_block_0|posts-expand|content-wrap)[^"'']*["''][^>]*>(.*)</(?:div|section)>') {
        # 容器名表：rich_media_content/.../post-content 是微信/公众号/WordPress 等；
        # posts-expand/content-wrap 是 Hexo 主题默认容器（同时支持 <div> 和 <section>）。
        $fragment = $matches[1]
    } elseif ($html -match '(?is)<body[^>]*>(.*)</body>') {
        $fragment = $matches[1]
    } else {
        $fragment = $html
    }

    $text = Convert-HtmlToText $fragment

    # 逐行清理：去首尾空白，丢弃空行
    $lines = @()
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t) { $lines += $t }
    }

    # 内容截断：最多保留 500 行 / 48000 字符
    if ($lines.Count -gt 500) { $lines = $lines[0..499] }
    $content = ($lines -join "`n")
    if ($content.Length -gt 48000) {
        $content = $content.Substring(0, 48000) + "`n`n... (内容过长，已截断)"
    }

    # 字数统计（基于截断后内容，与 .sh 一致——反映实际输出长度）
    $contentLength = Get-ContentLength $content

    # -----------------------------------------------------------------------------
    # 输出：按 Format / Output 分流
    # -----------------------------------------------------------------------------
    if ([string]::IsNullOrEmpty($Output)) {
        # 默认：JSON 到 stdout（向后兼容老调用方 `... | Out-File article.json`）
        $result = [ordered]@{
            title          = $title
            url            = $Url
            content        = $content
            content_length = $contentLength
        }
        [Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 3))
    } else {
        # 确保目标目录存在
        $outDir = [System.IO.Path]::GetDirectoryName($Output)
        if ($outDir -and -not (Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        switch ($Format) {
            'json' {
                $result = [ordered]@{
                    title          = $title
                    url            = $Url
                    content        = $content
                    content_length = $contentLength
                }
                # UTF-8 with BOM 让 PowerShell 5.1 文件 I/O 也认中文不乱码
                $json = $result | ConvertTo-Json -Compress -Depth 3
                [System.IO.File]::WriteAllText($Output, $json + "`n", [System.Text.UTF8Encoding]::new($true))
            }
            'markdown' {
                # Markdown 格式（人读最终产物）：
                #   # {title}
                #   来源: {url}
                #   字数: {content_length}
                #   {content}
                $md = "# $title`n`n来源: $Url`n`n字数: $contentLength`n`n$content`n"
                [System.IO.File]::WriteAllText($Output, $md, [System.Text.UTF8Encoding]::new($true))
            }
        }
    }
} catch {
    [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    exit 1
}