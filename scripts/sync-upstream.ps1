<#
.SYNOPSIS
    Sync upstream 1jehuang/jcode:master into local master branch via merge.
.DESCRIPTION
    Fetches 1jehuang/jcode:master, shows incoming commits, and merges them
    into the local master branch. Requires a clean working directory and
    being on the master branch. Does not push automatically.

    Usage:
      .\scripts\sync-upstream.ps1
#>

$ErrorActionPreference = 'Stop'

$UpstreamUrl   = "https://github.com/1jehuang/jcode.git"
$UpstreamName  = "upstream"
$UpstreamBranch = "master"
$LocalBranch   = "master"

function Write-Info($msg)  { Write-Host $msg -ForegroundColor Blue }
function Write-Err($msg)   { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }
function Write-Warn($msg)  { Write-Host "warning: $msg" -ForegroundColor Yellow }

# 1. Check we're inside a git repository
git rev-parse --git-dir > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "Not inside a git repository."
}

# 2. Check working directory is clean
$Status = git status --porcelain
if ($Status) {
    Write-Err "Working directory is not clean. Please stash or commit your changes before syncing."
}

# 3. Check current branch
$CurrentBranch = git rev-parse --abbrev-ref HEAD
if ($CurrentBranch -ne $LocalBranch) {
    Write-Err "Not on '$LocalBranch' branch (currently on '$CurrentBranch'). Run: git switch $LocalBranch"
}

# 4. Configure upstream remote (idempotent)
$remotes = @(git remote)
$hasUpstream = $remotes -contains $UpstreamName

if ($hasUpstream) {
    $ExistingUrl = git remote get-url $UpstreamName
    if ($ExistingUrl -ne $UpstreamUrl) {
        Write-Err "Remote '$UpstreamName' already exists with a different URL: $ExistingUrl`n  Expected: $UpstreamUrl`n  Please resolve manually."
    }
} else {
    Write-Info "Adding remote: $UpstreamName -> $UpstreamUrl"
    git remote add $UpstreamName $UpstreamUrl
}

# 5. Fetch upstream
Write-Info "Fetching $UpstreamName/$UpstreamBranch..."
git --no-pager fetch $UpstreamName $UpstreamBranch --tags

# 6. Show commits to be merged
$CommitCountStr = git rev-list --count "$LocalBranch..$UpstreamName/$UpstreamBranch"
$CommitCount = [int]$CommitCountStr

if ($CommitCount -eq 0) {
    Write-Info "Local $LocalBranch is already up to date with $UpstreamName/$UpstreamBranch. Nothing to sync."
    exit 0
}

Write-Info "Found $CommitCount new commit(s) from upstream:"
Write-Host ""
git --no-pager log --oneline --max-count=20 "$LocalBranch..$UpstreamName/$UpstreamBranch"
if ($CommitCount -gt 20) {
    $More = $CommitCount - 20
    Write-Host "  ... and $More more"
}
Write-Host ""

# 7. Prompt for confirmation
$Confirm = Read-Host "Merge these $CommitCount commit(s) into local $LocalBranch? [y/N]"
if ($Confirm -notin @("y", "Y")) {
    Write-Info "Sync cancelled by user."
    exit 1
}

# 8. Merge
Write-Info "Merging $UpstreamName/$UpstreamBranch into $LocalBranch..."
git --no-pager merge --no-edit "$UpstreamName/$UpstreamBranch"
$MergeExit = $LASTEXITCODE

if ($MergeExit -eq 0) {
    $NewHead = git rev-parse --short HEAD
    Write-Info "Successfully merged upstream changes."
    Write-Info "New HEAD: $NewHead"
    Write-Host ""
    Write-Info "To push to your origin:"
    Write-Host "  git push origin $LocalBranch"
} else {
    Write-Warn "Merge failed — there are conflicts to resolve."
    Write-Host ""
    Write-Warn "Conflicting files:"
    git --no-pager diff --name-only --diff-filter=U
    Write-Host ""
    Write-Info "Resolve conflicts, then stage and continue:"
    Write-Host "  git add <resolved-files>"
    Write-Host "  git merge --continue"
    Write-Host ""
    Write-Info "Or abort the merge:"
    Write-Host "  git merge --abort"
    exit 1
}
