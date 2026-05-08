param(
    [string]$Profile = "dev",
    [switch]$Release,
    [switch]$Help
)

# jcode Windows 构建脚本
# - 支持 dev/release 构建
# - 构建前会尝试停止正在运行的 jcode 进程
# - 为避免本地缓存影响，默认会清理 jcode crate 的构建产物（cargo clean -p jcode）

if ($Help) {
    Write-Host "用法：.\build_bywin.ps1 [-Release] [-Profile <profile>]"
    Write-Host ""
    Write-Host "参数："
    Write-Host "  -Release    使用 release 模式构建（等同于 --release）"
    Write-Host "  -Profile    Cargo profile（默认：dev；当指定 -Release 时会被强制为 release）"
    Write-Host ""
    Write-Host "示例："
    Write-Host "  .\build_bywin.ps1              # dev 构建"
    Write-Host "  .\build_bywin.ps1 -Release     # release 构建"
    exit 0
}

# 计算 cargo build 参数
if ($Release) {
    $Profile = "release"
    $BuildArgs = @("--release")
} else {
    $BuildArgs = @()
}

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RootDir

# [1/4] 停止正在运行的 jcode（避免文件占用影响构建/验证）
Write-Host "[1/4] 正在停止运行中的 jcode 进程..." -ForegroundColor Cyan
$procs = Get-Process -Name "jcode" -ErrorAction SilentlyContinue
if ($procs) {
    $procs | Stop-Process -Force
    Write-Host "  已终止 $($procs.Count) 个进程" -ForegroundColor DarkGray
    Start-Sleep -Milliseconds 500
} else {
    Write-Host "  未发现正在运行的 jcode 进程" -ForegroundColor DarkGray
}

# [2/4] 清理 jcode crate 的构建缓存（只清理 -p jcode）
Write-Host "[2/4] 正在清理 jcode 构建缓存..." -ForegroundColor Cyan
cargo clean -p jcode
if ($LASTEXITCODE -ne 0) {
    Write-Host "清理失败" -ForegroundColor Red
    exit $LASTEXITCODE
}

# [3/4] 构建
Write-Host "[3/4] 正在构建 jcode（$Profile）..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
cargo build @BuildArgs -p jcode --bin jcode
if ($LASTEXITCODE -ne 0) {
    Write-Host "构建失败" -ForegroundColor Red
    exit $LASTEXITCODE
}
$sw.Stop()

# 选择输出二进制路径
if ($Release) {
    $Binary = "target\release\jcode.exe"
} else {
    $Binary = "target\debug\jcode.exe"
}

# [4/4] 验证：运行 --version 确认可执行文件可启动
Write-Host "[4/4] 正在验证..." -ForegroundColor Cyan
$Version = & $Binary --version
Write-Host ""
Write-Host "  可执行文件：$Binary" -ForegroundColor Yellow
Write-Host "  版本信息  ：$Version" -ForegroundColor Yellow
Write-Host "  构建耗时  ：$($sw.Elapsed.ToString('mm\:ss'))" -ForegroundColor Yellow
Write-Host ""
Write-Host "完成。" -ForegroundColor Green
