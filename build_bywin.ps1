param(
    [string]$Profile = "dev",
    [switch]$Release,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: .\build_bywin.ps1 [-Release] [-Profile <profile>]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Release    Build in release mode"
    Write-Host "  -Profile    Cargo profile (default: dev)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\build_bywin.ps1              # dev build"
    Write-Host "  .\build_bywin.ps1 -Release     # release build"
    exit 0
}

if ($Release) {
    $Profile = "release"
    $BuildArgs = @("--release")
} else {
    $BuildArgs = @()
}

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RootDir

Write-Host "[1/3] Cleaning jcode build cache..." -ForegroundColor Cyan
cargo clean -p jcode 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Clean failed" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "[2/3] Building jcode ($Profile)..." -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
cargo build @BuildArgs -p jcode --bin jcode 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed" -ForegroundColor Red
    exit $LASTEXITCODE
}
$sw.Stop()

if ($Release) {
    $Binary = "target\release\jcode.exe"
} else {
    $Binary = "target\debug\jcode.exe"
}

Write-Host "[3/3] Verifying..." -ForegroundColor Cyan
$Version = & $Binary --version 2>&1
Write-Host ""
Write-Host "  Binary : $Binary" -ForegroundColor Yellow
Write-Host "  Version: $Version" -ForegroundColor Yellow
Write-Host "  Time   : $($sw.Elapsed.ToString('mm\:ss'))" -ForegroundColor Yellow
Write-Host ""
Write-Host "Done." -ForegroundColor Green
