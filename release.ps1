param(
    [string]$OutputDir   = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) "releases"),
    [ValidateSet("release","beta","alpha")]
    [string]$ReleaseType = "release",
    [switch]$DryRun,
    [switch]$SkipTag,
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"
$Root             = Split-Path -Parent $MyInvocation.MyCommand.Definition
$AddonName        = "DjinnisCircularBars"
$TocFile          = Join-Path $Root "$AddonName.toc"
$ReleaseNotesFile = Join-Path $Root "RELEASE_NOTES.md"
$ChangelogFile    = Join-Path $Root "CHANGELOG.md"

$_ghCmd = Get-Command "gh" -ErrorAction SilentlyContinue
$GhExe  = if ($_ghCmd) { $_ghCmd.Source } else { $null }
if (-not $GhExe) {
    $candidates = @(
        "C:\Program Files\GitHub CLI\gh.exe",
        "$env:LOCALAPPDATA\Programs\GitHub CLI\gh.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { $GhExe = $c; break } }
}

function Write-Info    { param($m) Write-Host $m -ForegroundColor Cyan    }
function Write-Success { param($m) Write-Host $m -ForegroundColor Green   }
function Write-Warn    { param($m) Write-Host $m -ForegroundColor Yellow  }
function Write-Err     { param($m) Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Make-Tag {
    param([string]$ver, [string]$type)
    if ($type -eq "release") { return "v$ver" }
    return "v$ver-$type"
}

# ---------------------------------------------------------------------------
# 1. Read version from RELEASE_NOTES.md
# ---------------------------------------------------------------------------

if (-not (Test-Path $ReleaseNotesFile)) {
    Write-Err "RELEASE_NOTES.md not found. Create it with a '## Version: x.y.z' line."
}

$rnContent    = Get-Content $ReleaseNotesFile -Raw -Encoding UTF8
$versionMatch = [regex]::Match($rnContent, '##\s+Version:\s*(\S+)')
if (-not $versionMatch.Success) {
    Write-Err "No '## Version: x.y.z' line found in RELEASE_NOTES.md."
}
$Version = $versionMatch.Groups[1].Value.TrimStart('v')
$Tag     = Make-Tag $Version $ReleaseType

Write-Info ""
Write-Info "=== $AddonName Release: $Tag ($ReleaseType) ==="
if ($DryRun) { Write-Warn "  DRY RUN - no files will be written, committed, tagged, or pushed" }
Write-Info ""

# ---------------------------------------------------------------------------
# 2. Sync TOC version
# ---------------------------------------------------------------------------

$tocContent      = Get-Content $TocFile -Raw -Encoding UTF8
$tocVersionMatch = [regex]::Match($tocContent, '##\s+Version:\s*(\S+)')
if (-not $tocVersionMatch.Success) { Write-Err "No '## Version:' in $AddonName.toc." }
$tocVersion = $tocVersionMatch.Groups[1].Value.TrimStart('v')

if ($tocVersion -ne $Version) {
    Write-Warn "  TOC version ($tocVersion) differs from RELEASE_NOTES.md ($Version) - auto-updating .toc"
    $tocContent = $tocContent -replace '(##\s+Version:\s*)\S+', "`${1}$Version"
    if (-not $DryRun) {
        [System.IO.File]::WriteAllText($TocFile, $tocContent, (New-Object System.Text.UTF8Encoding $false))
        Write-Success "  Updated $AddonName.toc to $Version"
    }
} else {
    Write-Info "  TOC version: $tocVersion  OK"
}

# ---------------------------------------------------------------------------
# 3. Check git state
# ---------------------------------------------------------------------------

$gitStatus   = & git -C $Root status --porcelain 2>&1
$rnFileName  = [System.IO.Path]::GetFileName($ReleaseNotesFile)
$tocFileName = [System.IO.Path]::GetFileName($TocFile)
$dirtyFiles  = $gitStatus | Where-Object {
    $_ -match '^\s*[MADRCU?]' -and
    $_ -notmatch '\.claude' -and
    $_ -notmatch ([regex]::Escape($rnFileName)) -and
    $_ -notmatch ([regex]::Escape($tocFileName))
}

if ($dirtyFiles) {
    Write-Warn "  Uncommitted changes detected:"
    $dirtyFiles | ForEach-Object { Write-Warn "    $_" }
    if (-not $DryRun) {
        Write-Err "Commit or stash non-release changes before releasing. Use -DryRun to preview."
    }
}

$tagExists = & git -C $Root tag -l $Tag 2>&1
if ($tagExists -contains $Tag) {
    Write-Warn "  Tag '$Tag' already exists - auto-bumping patch version..."
    $parts = $Version.Split('.')
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]($parts[2] -replace '[^0-9].*', '')
    do {
        $patch++
        $Version  = "$major.$minor.$patch"
        $Tag      = Make-Tag $Version $ReleaseType
        $tagCheck = & git -C $Root tag -l $Tag 2>&1
    } while ($tagCheck -contains $Tag)
    Write-Success "  Bumped to: $Tag"
    $rnContent = $rnContent -replace '(##\s+Version:\s*)\S+', "`${1}$Version"
    [System.IO.File]::WriteAllText($ReleaseNotesFile, $rnContent, (New-Object System.Text.UTF8Encoding $false))
    $tocContent = $tocContent -replace '(##\s+Version:\s*)\S+', "`${1}$Version"
    [System.IO.File]::WriteAllText($TocFile, $tocContent, (New-Object System.Text.UTF8Encoding $false))
    $rnContent = Get-Content $ReleaseNotesFile -Raw -Encoding UTF8
}

# ---------------------------------------------------------------------------
# 4. Extract release notes body
# ---------------------------------------------------------------------------

$notesBody = $rnContent -replace '(?s)<!--.*?-->\s*', ''
$notesBody = $notesBody -replace '(?m)^#\s+Release Notes\s*(\r?\n)?', ''
$notesBody = $notesBody -replace '(?m)^##\s+Version:.*(\r?\n)?', ''
$notesBody = $notesBody.Trim()

# ---------------------------------------------------------------------------
# 5. Prepend entry to CHANGELOG.md
# ---------------------------------------------------------------------------

$today        = (Get-Date).ToString("yyyy-MM-dd")
$versionLabel = if ($ReleaseType -ne "release") { "$Version-$ReleaseType" } else { $Version }
$changelogEntry = "## [$versionLabel] - $today`r`n`r`n$notesBody`r`n"

if (-not $DryRun) {
    $existing = ""
    if (Test-Path $ChangelogFile) { $existing = Get-Content $ChangelogFile -Raw -Encoding UTF8 }
    if ($existing -match "(?m)^##\s+\[$([regex]::Escape($versionLabel))\]") {
        Write-Warn "  CHANGELOG.md already contains [$versionLabel] -- skipping prepend"
    } else {
        $nl        = if ($existing -match "`r`n") { "`r`n" } else { "`n" }
        $separator = "${nl}---${nl}"
        $sepIndex  = $existing.IndexOf($separator)
        if ($sepIndex -ge 0) {
            $before       = $existing.Substring(0, $sepIndex + $separator.Length)
            $after        = $existing.Substring($sepIndex + $separator.Length)
            $newChangelog = $before + $nl + $changelogEntry + $nl + $after
        } else {
            $newChangelog = $existing + "${nl}---${nl}${nl}" + $changelogEntry
        }
        [System.IO.File]::WriteAllText($ChangelogFile, $newChangelog, (New-Object System.Text.UTF8Encoding $false))
        Write-Success "  CHANGELOG.md updated"
    }
} else {
    Write-Warn "  [DryRun] Would prepend to CHANGELOG.md:"
    Write-Host $changelogEntry -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 6. Build local zip
# ---------------------------------------------------------------------------

$ExcludeNames = @(
    ".git"
    ".gitignore"
    ".github"
    ".claude"
    "CHANGELOG.md"
    "CLAUDE.md"
    "deploy.ps1"
    "pkgmeta.yaml"
    "README.md"
    "release.ps1"
    "RELEASE_NOTES.md"
    "releases"
    "task.md"
)

$ZipName = "$AddonName-$Tag.zip"
$ZipPath = Join-Path $OutputDir $ZipName

if (-not $DryRun) {
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
    if (Test-Path $ZipPath)         { Remove-Item $ZipPath -Force }
}

Write-Info "  Building zip: $ZipPath"

$allItems   = Get-ChildItem -Path $Root -Recurse
$filesToZip = $allItems | Where-Object {
    if ($_.PSIsContainer) { return $false }
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\','/')
    foreach ($ex in $ExcludeNames) {
        $pattern = "^" + [regex]::Escape($ex) + "(/|\\|$)"
        if ($rel -eq $ex -or $rel -match $pattern) { return $false }
    }
    return $true
}

if ($DryRun) {
    $count = @($filesToZip).Count
    Write-Warn "  [DryRun] Would include $count files in zip"
} else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
    try {
        foreach ($file in $filesToZip) {
            $rel       = $file.FullName.Substring($Root.Length).TrimStart('\','/')
            $entryName = ("$AddonName/" + $rel) -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.FullName, $entryName,
                [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    } finally {
        $zip.Dispose()
    }
    $sizeKB = [math]::Round((Get-Item $ZipPath).Length / 1KB, 1)
    $count  = @($filesToZip).Count
    Write-Success "  Zip created: $ZipName ($sizeKB KB, $count files)"
}

# ---------------------------------------------------------------------------
# 7. Commit, tag, push
# ---------------------------------------------------------------------------

if (-not $DryRun) {
    & git -C $Root add CHANGELOG.md RELEASE_NOTES.md "$TocFile" | Out-Null
    $commitMsg = "Release $Tag"
    & git -C $Root commit -m $commitMsg | Out-Null
    Write-Success "  Committed: $commitMsg"

    if (-not $SkipTag) {
        & git -C $Root tag -a $Tag -m $commitMsg
        Write-Success "  Tagged:    $Tag"
    }

    if (-not $SkipPush) {
        Write-Info "  Pushing to origin..."
        & git -C $Root push origin HEAD
        Write-Success "  Pushed commits"
        if (-not $SkipTag) {
            & git -C $Root push origin $Tag
            Write-Success "  Pushed tag $Tag -> CurseForge webhook will trigger packaging as [$ReleaseType]"
        }
    } else {
        Write-Warn "  SkipPush set - run manually: git push origin HEAD && git push origin $Tag"
    }
} else {
    Write-Warn "  [DryRun] Would commit, tag '$Tag', and push to trigger CurseForge"
}

# ---------------------------------------------------------------------------
# 8. Create GitHub Release
# ---------------------------------------------------------------------------

$ghAvailable = $null -ne $GhExe

if (-not $ghAvailable) {
    Write-Warn ""
    Write-Warn "  GitHub CLI (gh) not found -- skipping GitHub Release creation."
    Write-Warn "  Install from https://cli.github.com then run 'gh auth login'."
} elseif ($SkipPush -or $SkipTag) {
    Write-Warn "  Skipping GitHub Release (SkipPush or SkipTag is set)"
} elseif ($DryRun) {
    Write-Warn "  [DryRun] Would create GitHub Release '$Tag' with $(Split-Path $ZipPath -Leaf) attached"
} else {
    Write-Info "  Creating GitHub Release $Tag..."
    $isPrerelease = ($ReleaseType -ne "release")
    $tmpNotes     = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpNotes, $notesBody, (New-Object System.Text.UTF8Encoding $false))
    $ZipLabel = "$AddonName-$Tag.zip"
    $ZipAsset = "${ZipPath}#${ZipLabel}"
    $ghArgs   = @("release", "create", $Tag, $ZipAsset, "--title", $Tag, "--notes-file", $tmpNotes)
    if ($isPrerelease) { $ghArgs += "--prerelease"; $ghArgs += "--latest=false" }
    & $GhExe @ghArgs
    Remove-Item $tmpNotes -Force
    if ($LASTEXITCODE -eq 0) {
        Write-Success "  GitHub Release created: https://github.com/RobertLCraig/DjinnisCircularBars/releases/tag/$Tag"
    } else {
        Write-Warn "  gh release create failed (exit $LASTEXITCODE)"
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

Write-Info ""
Write-Success "=== Release $Tag complete! ==="
Write-Info ""
Write-Info "  Local zip:  $ZipPath"
if (-not $DryRun -and -not $SkipPush -and -not $SkipTag) {
    Write-Info "  GitHub:     https://github.com/RobertLCraig/DjinnisCircularBars/releases/tag/$Tag"
    Write-Info "  CurseForge: packaging triggered by pushed tag (file type: $ReleaseType)"
}
Write-Info ""
Write-Info "Next steps:"
Write-Info "  1. Verify the zip locally: extract and load in WoW"
Write-Info "  2. Clear RELEASE_NOTES.md and set the next version placeholder"
Write-Info ""
