param(
    [switch]$Help
)

if ($Help) {
    Write-Host "用法：.\scripts\install_git_hooks.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "作用：" -ForegroundColor Cyan
    Write-Host "  将当前仓库 git hooks 目录设置为 .githooks（core.hooksPath）" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "说明：" -ForegroundColor Cyan
    Write-Host "  用于在提交时自动将默认的时间戳提交信息替换为 AI 总结（需要本机可执行 jcode 命令）。" -ForegroundColor Cyan
    exit 0
}

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
Set-Location $RepoRoot

git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "错误：当前目录不是 git 仓库。" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath ".githooks\prepare-commit-msg")) {
    Write-Host "错误：未找到 .githooks\prepare-commit-msg。" -ForegroundColor Red
    exit 1
}

git config core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) {
    Write-Host "错误：设置 core.hooksPath 失败。" -ForegroundColor Red
    exit 1
}

$hooksPath = git config --get core.hooksPath
Write-Host "已设置 core.hooksPath=$hooksPath" -ForegroundColor Green
Write-Host "提示：如需临时关闭 AI 提交信息生成，可设置环境变量 JCODE_COMMIT_AI=0" -ForegroundColor DarkGray
