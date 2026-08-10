# Obscura 自动安装脚本 - Windows PowerShell
param(
    [string]$Version = "latest",
    [string]$InstallDir = "$env:USERPROFILE\.local\bin"
)

$ErrorActionPreference = "Stop"

function Write-Info { Write-Host "[INFO] $args" -ForegroundColor Green }
function Write-Warn { Write-Host "[WARN] $args" -ForegroundColor Yellow }
function Write-Err { Write-Host "[ERROR] $args" -ForegroundColor Red; exit 1 }

# 检测架构
function Get-Platform {
    $arch = (Get-WmiObject Win32_Processor).Architecture

    switch ($arch) {
        9 { return "x86_64-windows" }  # x64
        12 { return "aarch64-windows" } # ARM64
        default { Write-Err "不支持的架构: $arch" }
    }
}

# 下载二进制文件
function Download-Obscura {
    param([string]$Platform)

    $downloadUrl = "https://github.com/h4ckf0r0day/obscura/releases/$Version/download/obscura-$Platform.zip"
    $tempDir = [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
    $tempZip = "$tempDir\obscura.zip"

    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Info "从以下地址下载: $downloadUrl"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
        Write-Info "下载完成"
    } catch {
        Write-Err "下载失败: $_"
    }

    return $tempDir, $tempZip
}

# 解压和安装
function Install-Obscura {
    param(
        [string]$TempDir,
        [string]$ZipFile,
        [string]$TargetDir
    )

    Write-Info "解压到 $TempDir..."
    Expand-Archive -Path $ZipFile -DestinationPath $TempDir -Force

    # 创建安装目录
    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    Write-Info "安装到 $TargetDir..."

    # 安装主程序
    Copy-Item "$TempDir\obscura.exe" "$TargetDir\obscura.exe" -Force

    # 尝试安装 worker (如果存在)
    if (Test-Path "$TempDir\obscura-worker.exe") {
        Copy-Item "$TempDir\obscura-worker.exe" "$TargetDir\obscura-worker.exe" -Force
        Write-Info "已安装 obscura-worker.exe"
    }

    Write-Info "安装完成"
}

# 添加到 PATH
function Add-ToPath {
    param([string]$Dir)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($userPath -notlike "*$Dir*") {
        Write-Info "添加到 PATH..."
        [Environment]::SetEnvironmentVariable(
            "Path",
            "$userPath;$Dir",
            "User"
        )
        $env:Path += ";$Dir"
        Write-Info "已添加到 PATH (需要重启终端生效)"
    } else {
        Write-Info "已在 PATH 中"
    }
}

# 验证安装
function Test-Installation {
    param([string]$InstallDir)

    Write-Info "验证安装..."

    $obscuraPath = "$InstallDir\obscura.exe"

    if (-not (Test-Path $obscuraPath)) {
        Write-Err "找不到 obscura.exe"
    }

    # 运行版本检查
    & $obscuraPath --version
    if ($LASTEXITCODE -ne 0) {
        Write-Err "验证失败"
    }

    # 快速功能测试
    Write-Info "运行功能测试..."
    & $obscuraPath fetch https://example.com --eval "document.title" --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "功能测试失败"
    }

    Write-Info "✅ Obscura 安装成功!"
    Write-Host ""
    Write-Host "快速开始:"
    Write-Host "  obscura fetch https://example.com --dump text"
    Write-Host "  obscura fetch https://example.com --screenshot page.png"
}

# 清理临时文件
function Remove-TempFiles {
    param([string]$TempDir)

    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir
    }
}

# 主流程
try {
    Write-Info "开始安装 Obscura..."

    $platform = Get-Platform
    Write-Info "检测到平台: $platform"

    $tempDir, $zipFile = Download-Obscura -Platform $platform
    Install-Obscura -TempDir $tempDir -ZipFile $zipFile -TargetDir $InstallDir
    Add-ToPath -Dir $InstallDir
    Test-Installation -InstallDir $InstallDir

} catch {
    Write-Err "安装过程中出错: $_"
} finally {
    if ($tempDir) {
        Remove-TempFiles -TempDir $tempDir
    }
}
