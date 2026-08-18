#!/usr/bin/env pwsh
# =============================================================================
# edge-tts-podcast: Parallel Tavily Search (Windows PowerShell 版本)
# =============================================================================
# 为「没有安装 Git Bash」的 Windows 用户提供的等价脚本。仅依赖系统自带的
# PowerShell（Windows PowerShell 5.1 或 PowerShell 7+），无需 bash / curl。
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File search.ps1 [-NumResults N] "query1" "query2" ...
#   powershell -NoProfile -ExecutionPolicy Bypass -File search.ps1 -Check   # 检查 API Key 配置
#
# API Key 加载优先级:
#   1. 环境变量 TAVILY_API_KEY
#   2. ~/.env         (TAVILY_API_KEY=key1,key2,key3)
#   3. ~/.tavily_api_key
# 支持多 Key（逗号或换行分隔），每次运行随机选一个。
# =============================================================================

param(
    [switch]$Check,
    [int]$NumResults = 8,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Queries
)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

$TavilyUrl = 'https://api.tavily.com/search'

$ExcludeDomains = @(
    'ntdtv.com','ntd.tv','aboluowang.com','epochtimes.com','epochtimes.jp',
    'dafahao.com','minghui.org','secretchina.com','kanzhongguo.com',
    'soundofhope.org','rfa.org','bannedbook.org','boxun.com','peacehall.com',
    'creaders.net','backchina.com','guancha.cn','wenxuecity.com',
    'awaker.cn','tuidang.org',
    'breitbart.com','infowars.com','naturalnews.com','globalresearch.ca',
    'zerohedge.com','thegatewaypundit.com','newsmax.com','oann.com',
    'dailywire.com','theblaze.com','redstate.com','thenationalpulse.com',
    'thefederalist.com',
    'dailykos.com','alternet.org','commondreams.org','thecanary.co',
    'occupydemocrats.com','truthout.org',
    'dailymail.co.uk','thesun.co.uk','nypost.com','express.co.uk',
    'mirror.co.uk','dailystar.co.uk',
    'theonion.com','clickhole.com','babylonbee.com','newspunch.com',
    'beforeitsnews.com',
    'rt.com','sputniknews.com','tass.com','wikileaks.org'
)

function Get-RawKeys {
    if ($env:TAVILY_API_KEY -and $env:TAVILY_API_KEY.Trim()) {
        return $env:TAVILY_API_KEY
    }
    $envFile = Join-Path $HOME '.env'
    if (Test-Path $envFile) {
        foreach ($line in (Get-Content -LiteralPath $envFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*TAVILY_API_KEY=(.*)$') {
                if ($matches[1].Trim()) { return $matches[1] }
            }
        }
    }
    $keyFile = Join-Path $HOME '.tavily_api_key'
    if (Test-Path $keyFile) {
        $raw = (Get-Content -LiteralPath $keyFile -Raw -ErrorAction SilentlyContinue)
        if ($raw -and $raw.Trim()) { return $raw.Trim() }
    }
    return $null
}

function Get-KeyList {
    $raw = Get-RawKeys
    if (-not $raw) { return @() }
    return @($raw -split '[,\r\n]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Format-MaskedKey([string]$k) {
    if ($k.Length -le 8) { return '****' }
    return ($k.Substring(0,4) + '****' + $k.Substring($k.Length - 4))
}

if ($Check) {
    $keys = Get-KeyList
    if ($keys.Count -eq 0) {
        Write-Output @'
[未配置] 未找到 Tavily API Key。

配置方式（任选其一）:
  A. ~/.env 文件（推荐，支持多 Key）:
       TAVILY_API_KEY=key1,key2,key3
  B. 环境变量:
       $env:TAVILY_API_KEY = "key1,key2"
  C. ~/.tavily_api_key 文件（单 Key，向后兼容）

获取 Key: https://app.tavily.com/home
'@
        exit 1
    }
    Write-Output '[已配置] 检测到 Tavily API Key:'
    $i = 0
    foreach ($k in $keys) {
        $i++
        Write-Output ("  [{0}] {1}" -f $i, (Format-MaskedKey $k))
    }
    Write-Output ("共 {0} 个 Key（每次搜索随机选用）" -f $keys.Count)
    exit 0
}

if (-not $Queries -or $Queries.Count -eq 0) {
    [Console]::Error.WriteLine('[FATAL] 未提供搜索查询。用法: search.ps1 [-NumResults N] "query1" "query2"')
    exit 1
}

$keyList = Get-KeyList
if ($keyList.Count -eq 0) {
    [Console]::Error.WriteLine(@'
[FATAL] 未配置 Tavily API Key。

配置方式（任选其一）:
  A. ~/.env: TAVILY_API_KEY=key1,key2,key3
  B. $env:TAVILY_API_KEY = "YOUR_KEY"
  C. ~/.tavily_api_key（单 Key）

获取 Key: https://app.tavily.com/home
'@)
    exit 1
}
$ApiKey = $keyList | Get-Random

$searchBlock = {
    param($Url, $Query, $NumResults, $ApiKey, $ExcludeDomains)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {}

    $bodyObj = @{
        query           = $Query
        max_results     = $NumResults
        include_answer  = 'basic'
        auto_parameters = $true
        exclude_domains = $ExcludeDomains
    }
    $body = $bodyObj | ConvertTo-Json -Compress -Depth 5

    # Windows PowerShell 5.1 用默认（非 UTF-8）编码序列化字符串型 -Body，
    # 中文会被替换成 "?" 且不可恢复。改为显式传 UTF-8 字节数组。
    # Content-Type 只能走 -ContentType，不能同时出现在 -Headers 里（5.1 会报重复）。
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $headers = @{ 'Authorization' = "Bearer $ApiKey" }
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method Post -Headers $headers `
            -ContentType 'application/json; charset=utf-8' `
            -Body $bodyBytes -TimeoutSec 30 -UseBasicParsing
        # 反向同理：响应头常不带 charset，5.1 会按 ISO-8859-1 解码 $resp.Content，
        # 把中文搜索结果也弄成乱码。直接从原始字节按 UTF-8 解。
        $text = $null
        try {
            $text = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
        } catch {
            $text = $resp.Content
        }
        return [pscustomobject]@{ Query = $Query; Ok = $true; Content = $text }
    } catch {
        $detail = $_.Exception.Message
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                $errBody = $reader.ReadToEnd()
                if ($errBody) { $detail = $errBody }
            }
        } catch {}
        return [pscustomobject]@{ Query = $Query; Ok = $false; Content = $detail }
    }
}

[Console]::Error.WriteLine("[INFO] 并行执行 $($Queries.Count) 个查询（每个 num_results=$NumResults）...")

$jobs = @()
foreach ($q in $Queries) {
    $jobs += Start-Job -ScriptBlock $searchBlock `
        -ArgumentList $TavilyUrl, $q, $NumResults, $ApiKey, $ExcludeDomains
}
$null = Wait-Job -Job $jobs

$success = 0
foreach ($job in $jobs) {
    $r = Receive-Job -Job $job
    Remove-Job -Job $job | Out-Null
    [Console]::Out.WriteLine("===== QUERY: $($r.Query) =====")
    if ($r.Ok) {
        [Console]::Out.WriteLine($r.Content)
        $success++
    } else {
        [Console]::Out.WriteLine("[ERROR] $($r.Content)")
    }
    [Console]::Out.WriteLine('---')
}

[Console]::Error.WriteLine("[INFO] $success/$($Queries.Count) 个查询成功。")
if ($success -eq 0) {
    [Console]::Error.WriteLine('[FATAL] 所有查询均失败，请检查 API Key 与网络连接。')
    exit 1
}
