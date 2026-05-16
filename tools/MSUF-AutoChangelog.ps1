[CmdletBinding()]
param(
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$DisplayVersion,
    [string]$BaseRef,
    [int]$SinceHours = 0,
    [string]$ReleaseDate = (Get-Date -Format "yyyy-MM-dd"),
    [switch]$Gui,
    [switch]$NoGui,
    [switch]$Watch,
    [switch]$RegenerateAddonChangelog,
    [switch]$IncludeTooling,
    [switch]$CreateMissingRelease,
    [switch]$KeepExistingAutoEntries,
    [switch]$IncludePrereleaseAutoEntries,
    [int]$PollSeconds = 2,
    [int]$DebounceSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$AddonChangelogScript = Join-Path $RepoRoot "tools/update-addon-changelog.ps1"
$script:AutoLogBox = $null
$SectionOrder = @(
    "Performance",
    "Bugfixes",
    "Changes / Improvements",
    "Release / Tooling",
    "Documentation"
)

function Write-AutoLog {
    param([AllowNull()][string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), ($Message -replace "`r?`n", " ")
    if ($script:AutoLogBox -and -not $script:AutoLogBox.IsDisposed) {
        $script:AutoLogBox.AppendText($line + [Environment]::NewLine)
        $script:AutoLogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host $line
    }
}

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $candidate = $Path
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path $RepoRoot $candidate
    }

    $full = [System.IO.Path]::GetFullPath($candidate)
    $root = $RepoRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $comparison = [System.StringComparison]::OrdinalIgnoreCase

    if (-not (
        $full.Equals($root, $comparison) -or
        $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, $comparison) -or
        $full.StartsWith($root + [System.IO.Path]::AltDirectorySeparatorChar, $comparison)
    )) {
        throw "Refusing to use a path outside the repository: $full"
    }

    return $full
}

function Normalize-VersionKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    return ($v.ToLowerInvariant() -replace '[^a-z0-9]+', '')
}

function Get-PrereleaseVersionInfo {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    if ($v -notmatch '^(?<base>\d+(?:\.\d+)*)[\s._-]*(?<channel>alpha|beta|rc|pre)(?:[\s._-]*(?<number>\d+))?\s*$') {
        return $null
    }

    $hasNumber = -not [string]::IsNullOrWhiteSpace($Matches["number"])
    $number = if ($hasNumber) { [int]$Matches["number"] } else { $null }

    return [pscustomobject]@{
        BaseKey   = Normalize-VersionKey $Matches["base"]
        Channel   = $Matches["channel"].ToLowerInvariant()
        HasNumber = $hasNumber
        Number    = $number
    }
}

function Test-IsPrereleaseCarrySource {
    param(
        [AllowNull()][string]$SourceVersion,
        [AllowNull()][string]$TargetVersion
    )

    $source = Get-PrereleaseVersionInfo $SourceVersion
    $target = Get-PrereleaseVersionInfo $TargetVersion
    if ($null -eq $source -or $null -eq $target) { return $false }
    if ($source.BaseKey -ne $target.BaseKey) { return $false }
    if ($source.Channel -ne $target.Channel) { return $false }
    if ((Normalize-VersionKey $SourceVersion) -eq (Normalize-VersionKey $TargetVersion)) { return $false }

    if ($target.HasNumber) {
        if ($source.HasNumber) { return ($source.Number -lt $target.Number) }
        return $true
    }

    return $source.HasNumber
}

function Get-StableVersionKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    if ($v -notmatch '^\d+(?:\.\d+)*$') { return "" }
    return (Normalize-VersionKey $v)
}

function Test-IsFinalReleasePrereleaseSource {
    param(
        [AllowNull()][string]$SourceVersion,
        [AllowNull()][string]$TargetVersion
    )

    $source = Get-PrereleaseVersionInfo $SourceVersion
    $targetKey = Get-StableVersionKey $TargetVersion
    if ($null -eq $source -or [string]::IsNullOrWhiteSpace($targetKey)) { return $false }
    return ($source.BaseKey -eq $targetKey)
}

function Convert-PathForGit {
    param([Parameter(Mandatory = $true)][string]$Path)

    return ($Path -replace '\\', '/')
}

function Get-DefaultBaseRef {
    Push-Location $RepoRoot
    try {
        $tag = (& git describe --tags --abbrev=0 HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($tag)) {
            return $tag.Trim()
        }

        $root = (& git rev-list --max-parents=0 HEAD 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root)) {
            return $root.Trim()
        }
    } finally {
        Pop-Location
    }

    return ""
}

function Test-GitRefExists {
    param([AllowNull()][string]$Ref)

    if ([string]::IsNullOrWhiteSpace($Ref)) { return $false }
    Push-Location $RepoRoot
    try {
        $null = & git rev-parse --verify --quiet "$($Ref.Trim())^{commit}" 2>$null
        return ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
    }
}

function Get-EffectiveSinceHours {
    if ($SinceHours -lt 0) { throw "Since hours must be 0 or between 1 and 100." }
    if ($SinceHours -gt 100) { throw "Since hours must be between 1 and 100." }
    return $SinceHours
}

function Get-EffectiveBaseRef {
    if ((Get-EffectiveSinceHours) -gt 0) { return "" }

    $base = if ([string]::IsNullOrWhiteSpace($BaseRef)) { Get-DefaultBaseRef } else { $BaseRef.Trim() }
    if ([string]::IsNullOrWhiteSpace($base)) { return "" }
    if (Test-GitRefExists $base) { return $base }

    $targetKey = Normalize-VersionKey $DisplayVersion
    if ($targetKey -ne "" -and (Normalize-VersionKey $base) -eq $targetKey) {
        $fallback = Get-DefaultBaseRef
        if (-not [string]::IsNullOrWhiteSpace($fallback) -and (Test-GitRefExists $fallback)) {
            Write-AutoLog "Since ref '$base' is the target version, not an existing Git ref. Writing only '$DisplayVersion' and using '$fallback' as commit range base."
            $script:BaseRef = $fallback
            return $fallback
        }
    }

    throw "Since ref '$base' does not exist as a Git tag, branch, or commit. Use the previous release tag, the Last tag button, or clear it with All history. The changelog target is still '$DisplayVersion'."
}

function Test-IsAutoIgnoredPath {
    param([AllowNull()][string]$Path)

    $p = Convert-PathForGit "$Path"
    if ([string]::IsNullOrWhiteSpace($p)) { return $true }

    if ($p -eq "CHANGELOG.md") { return $true }
    if ($p -eq "MidnightSimpleUnitFrames/Foundation/MSUF_Changelog.lua") { return $true }
    if ($p -match '^tools/MSUF-AutoChangelog\.(ps1|cmd)$') { return $true }

    if (-not $IncludeTooling) {
        if ($p -match '^\.github/|^tools/|^docs/') { return $true }
        if ($p -match '\.pkgmeta$|MidnightSimpleUnitFrames\.toc$') { return $true }
    }

    return $false
}

function Get-ChangeArea {
    param([AllowNull()][string]$Path)

    $p = Convert-PathForGit "$Path"
    if ([string]::IsNullOrWhiteSpace($p)) { return "General" }
    if ($p -match '^\.github/|^tools/|^docs/|^CHANGELOG\.md$|MSUF_Changelog\.lua$') { return "Release / Tooling" }
    if ($p -match '/Foundation/MSUF_Profiles\.lua$') { return "Profiles" }
    if ($p -match '/Foundation/') { return "Foundation" }
    if ($p -match '/Menu2/') { return "Menu / Dashboard" }
    if ($p -match '/Auras2/') { return "Unit Auras" }
    if ($p -match '/GroupFrames/') { return "Group Frames" }
    if ($p -match '/Modules/MSUF_InterruptReady\.lua$') { return "Interrupt Ready" }
    if ($p -match '/Core/MSUF_Text\.lua$') { return "Unit Text" }
    if ($p -match '/Core/MSUF_Borders\.lua$') { return "Borders / Outlines" }
    if ($p -match '/Core/MSUF_Bars\.lua$') { return "Bars / Power Bars" }
    if ($p -match '/Core/') { return "Core Runtime" }
    if ($p -match '/Features/') { return "Features" }
    if ($p -match 'MidnightSimpleUnitFrames\.toc$|\.pkgmeta$') { return "Addon Metadata" }
    return "General"
}

function Get-ChangeCategory {
    param(
        [AllowNull()][string]$Subject,
        [AllowNull()][string[]]$Paths,
        [AllowNull()][string]$Context
    )

    $subjectText = if ($null -eq $Subject) { "" } else { $Subject.ToLowerInvariant() }
    $pathText = if ($null -eq $Paths) { "" } else { (($Paths | ForEach-Object { $_.ToLowerInvariant() }) -join " ") }
    $contextText = if ($null -eq $Context) { "" } else { $Context.ToLowerInvariant() }
    $haystack = "$subjectText $pathText $contextText"

    if ($IncludeTooling -and $pathText -match '(^| )docs/') { return "Documentation" }
    if ($IncludeTooling -and $pathText -match '(^| )\.github/|(^| )tools/|pkgmeta|\.toc|publish-|package-release|workflow|changelog') {
        return "Release / Tooling"
    }
    if ($haystack -match 'perf|performance|optim|cache|hot path|fast|less work|skip|coalesce|throttle|debounce|allocation') {
        return "Performance"
    }
    if ($haystack -match 'fix|fixed|bug|crash|taint|error|broken|guard|fallback|secret|nil|wrong|misdetect') {
        return "Bugfixes"
    }
    return "Changes / Improvements"
}

function Convert-CommitSubjectToText {
    param([AllowNull()][string]$Subject)

    $text = if ($null -eq $Subject) { "" } else { $Subject.Trim() }
    if ($text -eq "") { return "Updated addon behavior" }
    $text = $text -replace '^\s*(feat|fix|perf|docs|chore|refactor|test)(\(.+?\))?:\s*', ''
    $text = $text -replace '\s+', ' '
    $text = $text.Trim().TrimEnd(".")
    if ($text.Length -gt 0) {
        $text = $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
    }
    return $text
}

function Test-IsIgnoredCommitSubject {
    param([AllowNull()][string]$Subject)

    if ([string]::IsNullOrWhiteSpace($Subject)) { return $false }
    $text = $Subject.ToLowerInvariant()
    if ($text -match 'release helper|msuf-releasehelper|auto changelog|updated changelog|changelog only') { return $true }
    return $false
}

function Get-PathDescription {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StatusCode,
        [AllowNull()][string]$DiffText
    )

    $p = Convert-PathForGit $Path
    $prefix = "Updated"
    if ($StatusCode -match 'A|\?\?') { $prefix = "Added" }
    if ($StatusCode -match 'D') { $prefix = "Removed" }
    if ($StatusCode -match 'R') { $prefix = "Renamed" }

    $diff = if ($null -eq $DiffText) { "" } else { $DiffText.ToLowerInvariant() }
    if ($p -match '/Foundation/MSUF_Profiles\.lua$') {
        if ($diff -match 'encode|export|import|serial|secret|fallback|cbor') {
            return "$prefix profile export/import safety and serialization handling"
        }
        return "$prefix profile handling"
    }
    if ($p -match '/Foundation/MSUF_Changelog\.lua$') { return "$prefix bundled in-game changelog data" }
    if ($p -match '/Auras2/') { return "$prefix Aura2 event, reminder, or aura handling" }
    if ($p -match '/GroupFrames/MSUF_GF_Effects\.lua$') { return "$prefix Group Frame effects, range fade, or highlight behavior" }
    if ($p -match '/GroupFrames/') { return "$prefix Group Frame behavior" }
    if ($p -match '/Menu2/') { return "$prefix menu, dashboard, or live apply behavior" }
    if ($p -match '/Modules/MSUF_InterruptReady\.lua$') { return "$prefix Interrupt Ready behavior" }
    if ($p -match '/Core/MSUF_Text\.lua$') { return "$prefix unit text rendering" }
    if ($p -match '/Core/MSUF_Borders\.lua$') { return "$prefix border and outline behavior" }
    if ($p -match '/Core/MSUF_Bars\.lua$') { return "$prefix bar and power bar behavior" }
    if ($p -match '/Core/') { return "$prefix core runtime behavior" }
    return "$prefix addon behavior"
}

function Get-UserFacingChangeText {
    param(
        [AllowNull()][string]$Subject,
        [AllowNull()][string[]]$Paths,
        [AllowNull()][string]$DiffText,
        [Parameter(Mandatory = $true)][string]$Category
    )

    $subjectText = if ($null -eq $Subject) { "" } else { $Subject.Trim() }
    $pathText = if ($null -eq $Paths) { "" } else { (($Paths | ForEach-Object { Convert-PathForGit "$_" }) -join " ") }
    $diffText = if ($null -eq $DiffText) { "" } else { $DiffText }
    $haystack = (($subjectText + " " + $pathText + " " + $diffText) -replace '\s+', ' ').ToLowerInvariant()
    $areas = [string[]]@($Paths | ForEach-Object { Get-ChangeArea $_ } | Select-Object -Unique)
    $scope = if ($areas.Count -gt 0) { (($areas | Select-Object -First 2) -join ", ") } else { "addon behavior" }
    $scopeText = Get-FriendlyScopeText $scope

    if ($haystack -match 'class.?color|classcolor|barbackground|bar background') {
        return "Improved class-colored bar backgrounds across unit and group frames."
    }
    if ($haystack -match 'long.?raid.?buff|raid.?buff|ignorelong|longbuff') {
        return "Improved Group Frame aura filtering so long raid buffs are no longer tracked incorrectly."
    }
    if ($haystack -match 'test.?mode|preview.?mode') {
        return "Improved menu preview handling so test mode is cleaned up when leaving the menu."
    }
    if ($haystack -match 'spell.?indicator|external.*cooldown|blessing|power infusion|\bpi\b') {
        return "Improved Group Frame spell indicators and tracked cooldown display."
    }
    if ($haystack -match 'pin|pinned|scroll|preview') {
        return "Improved menu previews so layouts are easier to inspect and adjust."
    }
    if ($haystack -match 'tooltip|tiptac') {
        return "Improved tooltip compatibility with other addons."
    }
    if ($haystack -match 'container|font|text option|font runtime|unit text') {
        return "Improved text and container controls for unit and group frames."
    }
    if ($haystack -match 'coalesc|throttle|debounce|cache|dirty|refresh|update queue') {
        return "Improved update batching and refresh performance for addon UI changes."
    }
    if ($haystack -match 'range.?fade|highlight|alpha') {
        return "Improved Group Frame range, highlight, and visibility behavior."
    }
    if ($haystack -match 'aura|buff|debuff|reminder') {
        return "Improved aura and reminder behavior."
    }
    if ($haystack -match 'profile|import|export|serialization|cbor') {
        return "Improved profile import, export, and serialization handling."
    }
    if ($haystack -match 'dashboard|menu|options|settings') {
        return "Improved menu and dashboard usability."
    }

    $cleanSubject = Convert-CommitSubjectToText $subjectText
    $cleanSubject = $cleanSubject -replace '\s*\([^)]*\)\s*$', ''
    $cleanSubject = $cleanSubject.Trim().TrimEnd(".")
    if ($cleanSubject -ne "" -and $cleanSubject -notmatch '^(updated addon behavior|some stuff|changelog stuff)$') {
        return (Format-FriendlySentence $cleanSubject)
    }

    if ($Category -eq "Performance") {
        return "Improved performance for $scopeText."
    }
    if ($Category -eq "Bugfixes") {
        return "Fixed issues affecting $scopeText."
    }
    if ($Category -eq "Release / Tooling") {
        return "Improved release tooling and changelog generation."
    }
    if ($Category -eq "Documentation") {
        return "Updated documentation and release notes."
    }
    return "Improved $scopeText."
}

function Add-GroupedBullet {
    param(
        [Parameter(Mandatory = $true)]$Groups,
        [Parameter(Mandatory = $true)]$Seen,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Bullet
    )

    $target = if ($Groups.Contains($Category)) { $Category } else { "Changes / Improvements" }
    $key = $Bullet.ToLowerInvariant()
    if ($Seen.Contains($key)) { return }
    [void]$Seen.Add($key)
    $Groups[$target].Add($Bullet)
}

function Get-CommitPaths {
    param([Parameter(Mandatory = $true)][string]$Hash)

    $nameStatus = & git show --format= --name-status $Hash 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git show failed for $Hash`: $($nameStatus -join ' ')"
    }

    $paths = @()
    foreach ($entry in $nameStatus) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $cols = $entry -split "`t"
        if ($cols.Count -ge 3 -and $cols[0] -match '^R|^C') {
            $paths += $cols[2]
        } elseif ($cols.Count -ge 2) {
            $paths += $cols[1]
        }
    }

    return [string[]]@($paths | Where-Object { -not (Test-IsAutoIgnoredPath $_) } | Select-Object -Unique)
}

function Get-CommitDiffText {
    param([Parameter(Mandatory = $true)][string]$Hash)

    $diff = & git -c core.autocrlf=false show --format= --no-ext-diff --unified=0 $Hash 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git show diff failed for $Hash`: $($diff -join ' ')"
    }
    return ($diff -join [Environment]::NewLine)
}

function Add-CommitChangesToGroups {
    param(
        [Parameter(Mandatory = $true)]$Groups,
        [Parameter(Mandatory = $true)]$Seen
    )

    $hours = Get-EffectiveSinceHours
    $base = Get-EffectiveBaseRef
    $range = if ($hours -gt 0) { "HEAD --since=$hours hours" } elseif ([string]::IsNullOrWhiteSpace($base)) { "HEAD" } else { "$base..HEAD" }

    Push-Location $RepoRoot
    try {
        $commitLines = if ($hours -gt 0) {
            & git log --reverse --format="%H`t%h`t%s" "--since=$hours hours ago" HEAD 2>&1
        } else {
            & git log --reverse --format="%H`t%h`t%s" $range 2>&1
        }
        if ($LASTEXITCODE -ne 0) {
            throw "git log failed for range '$range': $($commitLines -join ' ')"
        }

        foreach ($line in $commitLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t", 3
            if ($parts.Count -lt 3) { continue }
            $hash = $parts[0]
            $short = $parts[1]
            $subject = $parts[2]
            if (Test-IsIgnoredCommitSubject $subject) { continue }
            $paths = [string[]]@(Get-CommitPaths $hash)
            if ($paths.Count -eq 0) { continue }
            $diff = Get-CommitDiffText $hash
            $category = Get-ChangeCategory -Subject $subject -Paths $paths -Context $diff
            $bullet = Get-UserFacingChangeText -Subject $subject -Paths $paths -DiffText $diff -Category $category
            Add-GroupedBullet -Groups $Groups -Seen $Seen -Category $category -Bullet $bullet
        }
    } finally {
        Pop-Location
    }
}

function Get-GitStatusEntries {
    Push-Location $RepoRoot
    try {
        $lines = & git status --porcelain=v1 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git status failed: $($lines -join ' ')"
        }

        $entries = @()
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
            $code = $line.Substring(0, 2)
            $path = $line.Substring(3).Trim()
            if ($path -match ' -> ') {
                $path = ($path -split ' -> ', 2)[1].Trim()
            }
            if (Test-IsAutoIgnoredPath $path) { continue }
            $entries += [pscustomobject]@{
                Code = $code
                Path = $path
            }
        }
        return [object[]]$entries
    } finally {
        Pop-Location
    }
}

function Get-DirtyDiffText {
    param([Parameter(Mandatory = $true)]$Entry)

    Push-Location $RepoRoot
    try {
        $parts = New-Object System.Collections.Generic.List[string]
        $code = [string]$Entry.Code
        $path = [string]$Entry.Path
        if ($code.Substring(0, 1) -ne " " -and $code.Substring(0, 1) -ne "?") {
            $cached = & git -c core.autocrlf=false diff --cached -- $path 2>$null
            if ($LASTEXITCODE -eq 0 -and $cached) { $parts.Add(($cached -join [Environment]::NewLine)) }
        }
        if ($code.Substring(1, 1) -ne " " -and $code.Substring(1, 1) -ne "?") {
            $work = & git -c core.autocrlf=false diff -- $path 2>$null
            if ($LASTEXITCODE -eq 0 -and $work) { $parts.Add(($work -join [Environment]::NewLine)) }
        }
        return ($parts -join [Environment]::NewLine)
    } finally {
        Pop-Location
    }
}

function Add-WorkingTreeChangesToGroups {
    param(
        [Parameter(Mandatory = $true)]$Groups,
        [Parameter(Mandatory = $true)]$Seen
    )

    foreach ($entry in Get-GitStatusEntries) {
        $path = [string]$entry.Path
        $diff = Get-DirtyDiffText -Entry $entry
        $category = Get-ChangeCategory -Subject "" -Paths @($path) -Context $diff
        $description = Get-UserFacingChangeText -Subject "" -Paths @($path) -DiffText $diff -Category $category
        $bullet = if ($description -match '^\s*(Added|Removed|Renamed|Updated|Improved|Fixed)\b') {
            $description
        } else {
            Get-PathDescription -Path $path -StatusCode ([string]$entry.Code) -DiffText $diff
        }
        Add-GroupedBullet -Groups $Groups -Seen $Seen -Category $category -Bullet $bullet
    }
}

function Get-AutoChangelogGroups {
    $groups = [ordered]@{}
    foreach ($title in $SectionOrder) {
        $groups[$title] = New-Object System.Collections.Generic.List[string]
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    Add-CommitChangesToGroups -Groups $groups -Seen $seen
    Add-WorkingTreeChangesToGroups -Groups $groups -Seen $seen

    return $groups
}

function New-AutoGroupMap {
    $groups = [ordered]@{}
    foreach ($title in $SectionOrder) {
        $groups[$title] = New-Object System.Collections.Generic.List[string]
    }
    return $groups
}

function Get-SectionTitleFromMarkerKey {
    param([AllowNull()][string]$MarkerKey)

    if ([string]::IsNullOrWhiteSpace($MarkerKey)) { return $null }
    foreach ($title in $SectionOrder) {
        if ((Get-MarkerKey $title) -eq $MarkerKey.Trim()) {
            return $title
        }
    }
    return $null
}

function Add-AutoBulletToGroup {
    param(
        [Parameter(Mandatory = $true)]$Groups,
        [Parameter(Mandatory = $true)]$Seen,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Bullet
    )

    $target = if ($Groups.Contains($Title)) { $Title } else { "Changes / Improvements" }
    $text = $Bullet.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $key = ($target + "|" + $text).ToLowerInvariant()
    if ($Seen.Contains($key)) { return }
    [void]$Seen.Add($key)
    $Groups[$target].Add($text)
}

function Get-ExistingAutoBlocks {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines)

    $groups = New-AutoGroupMap
    $currentTitle = $null
    $currentHeading = $null
    $lastList = $null

    foreach ($line in $Lines) {
        if ($line -match '^###\s+(.+?)\s*$') {
            $currentHeading = $Matches[1].Trim()
        }

        if ($line -match '^\s*<!--\s*MSUF-AUTO-CHANGELOG:\s*-->\s*$') {
            $currentTitle = if ($currentTitle) { $null } else { $currentHeading }
            $lastList = if ($currentTitle -and $groups.Contains($currentTitle)) { ,$groups[$currentTitle] } else { $null }
            continue
        }

        if ($line -match '^\s*<!--\s*MSUF-AUTO-CHANGELOG:([^:>]+):START\s*-->\s*$') {
            $currentTitle = Get-SectionTitleFromMarkerKey $Matches[1]
            $lastList = if ($currentTitle -and $groups.Contains($currentTitle)) { ,$groups[$currentTitle] } else { $null }
            continue
        }

        if ($line -match '^\s*<!--\s*MSUF-AUTO-CHANGELOG:[^:>]+:END\s*-->\s*$') {
            $currentTitle = $null
            $lastList = $null
            continue
        }

        if ([string]::IsNullOrWhiteSpace($currentTitle) -or $null -eq $lastList) { continue }

        if ($line -match '^\s*-\s+(.+?)\s*$') {
            $lastList.Add($Matches[1].Trim())
            continue
        }

        if ($lastList.Count -gt 0 -and $line -match '^\s{2,}(.+?)\s*$') {
            $lastList[$lastList.Count - 1] = ($lastList[$lastList.Count - 1] + " " + $Matches[1].Trim()).Trim()
        }
    }

    return $groups
}

function Merge-AutoGroups {
    param(
        [Parameter(Mandatory = $true)]$Existing,
        [Parameter(Mandatory = $true)]$Generated
    )

    $merged = New-AutoGroupMap
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($title in $SectionOrder) {
        foreach ($bullet in $Existing[$title]) {
            Add-AutoBulletToGroup -Groups $merged -Seen $seen -Title $title -Bullet $bullet
        }
        foreach ($bullet in $Generated[$title]) {
            Add-AutoBulletToGroup -Groups $merged -Seen $seen -Title $title -Bullet $bullet
        }
    }

    return $merged
}

function Get-AutoGroupEntryCount {
    param([Parameter(Mandatory = $true)]$Groups)

    $count = 0
    foreach ($title in $SectionOrder) {
        if ($Groups.Contains($title)) {
            $count += $Groups[$title].Count
        }
    }
    return $count
}

function Get-ChangelogReleaseSections {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines)

    $sections = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -notmatch '^##\s+(.+?)(?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$') { continue }

        $version = $Matches[1].Trim()
        $end = $Lines.Count
        for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
            if ($Lines[$j] -match '^##\s+') {
                $end = $j
                break
            }
        }

        $sections.Add([pscustomobject]@{
            Start   = $i
            End     = $end
            Version = $version
        })
    }

    return [object[]]$sections.ToArray()
}

function Get-ReleaseLinesFromBounds {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)]$Bounds
    )

    if ($Bounds.End -gt $Bounds.Start) {
        return [string[]]$Lines[$Bounds.Start..($Bounds.End - 1)]
    }
    return @($Lines[$Bounds.Start])
}

function Get-CarriedPrereleaseAutoGroups {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$TargetVersion
    )

    $carried = New-AutoGroupMap
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($section in Get-ChangelogReleaseSections -Lines $Lines) {
        if (-not (Test-IsPrereleaseCarrySource -SourceVersion $section.Version -TargetVersion $TargetVersion)) {
            continue
        }

        $sectionLines = Get-ReleaseLinesFromBounds -Lines $Lines -Bounds $section
        $groups = Get-ExistingAutoBlocks -Lines $sectionLines
        foreach ($title in $SectionOrder) {
            foreach ($bullet in $groups[$title]) {
                Add-AutoBulletToGroup -Groups $carried -Seen $seen -Title $title -Bullet $bullet
            }
        }
    }

    return $carried
}

function Get-CarriedFinalReleaseAutoGroups {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$TargetVersion
    )

    $carried = New-AutoGroupMap
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($section in Get-ChangelogReleaseSections -Lines $Lines) {
        if (-not (Test-IsFinalReleasePrereleaseSource -SourceVersion $section.Version -TargetVersion $TargetVersion)) {
            continue
        }

        $sectionLines = Get-ReleaseLinesFromBounds -Lines $Lines -Bounds $section
        $groups = Get-ExistingAutoBlocks -Lines $sectionLines
        foreach ($title in $SectionOrder) {
            foreach ($bullet in $groups[$title]) {
                Add-AutoBulletToGroup -Groups $carried -Seen $seen -Title $title -Bullet $bullet
            }
        }
    }

    return $carried
}

function Get-KeepExistingAutoGroups {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)]$Bounds
    )

    $releaseLines = Get-ReleaseLinesFromBounds -Lines $Lines -Bounds $Bounds
    $existingGroups = Get-ExistingAutoBlocks -Lines $releaseLines
    $carriedGroups = Get-CarriedPrereleaseAutoGroups -Lines $Lines -TargetVersion $Bounds.Version
    return (Merge-AutoGroups -Existing $existingGroups -Generated $carriedGroups)
}

function Convert-AutoGroupsToMarkdown {
    param([Parameter(Mandatory = $true)]$Groups)

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($title in $SectionOrder) {
        $items = if ($Groups.Contains($title)) { $Groups[$title] } else { @() }
        $lines.Add("### $title")
        $lines.Add("")
        foreach ($item in $items) {
            if (-not [string]::IsNullOrWhiteSpace("$item")) {
                $lines.Add("- $item")
            }
        }
        $lines.Add("")
    }
    return (($lines.ToArray() -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Convert-MarkdownToAutoGroups {
    param([AllowNull()][string]$Markdown)

    $groups = New-AutoGroupMap
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $currentTitle = "Changes / Improvements"
    $lastList = $groups[$currentTitle]

    if ([string]::IsNullOrWhiteSpace($Markdown)) { return $groups }

    foreach ($line in ([regex]::Split($Markdown, "\r?\n"))) {
        if ($line -match '^\s*###\s+(.+?)\s*$') {
            $mapped = Get-SectionTitleFromMarkerKey (Get-MarkerKey $Matches[1].Trim())
            $currentTitle = if ($mapped) { $mapped } else { "Changes / Improvements" }
            $lastList = $groups[$currentTitle]
            continue
        }

        if ($line -match '^\s*-\s+(.+?)\s*$') {
            Add-AutoBulletToGroup -Groups $groups -Seen $seen -Title $currentTitle -Bullet $Matches[1].Trim()
            $lastList = $groups[$currentTitle]
            continue
        }

        if ($lastList.Count -gt 0 -and $line -match '^\s{2,}(.+?)\s*$') {
            $lastList[$lastList.Count - 1] = ($lastList[$lastList.Count - 1] + " " + $Matches[1].Trim()).Trim()
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed -ne "" -and $trimmed -notmatch '^<!--') {
            Add-AutoBulletToGroup -Groups $groups -Seen $seen -Title $currentTitle -Bullet $trimmed
            $lastList = $groups[$currentTitle]
        }
    }

    return $groups
}

function Format-FriendlySentence {
    param([AllowNull()][string]$Text)

    $value = if ($null -eq $Text) { "" } else { $Text.Trim() }
    if ($value -eq "") { return "" }
    $value = $value -replace '\s+', ' '
    $value = $value.Trim().TrimEnd(".")
    if ($value.Length -gt 0) {
        $value = $value.Substring(0, 1).ToUpperInvariant() + $value.Substring(1)
    }
    return ($value + ".")
}

function Get-FriendlyScopeText {
    param([AllowNull()][string]$Scope)

    $s = if ($null -eq $Scope) { "" } else { $Scope.ToLowerInvariant() }
    if ($s -match 'menu|dashboard') { return "menu and dashboard" }
    if ($s -match 'group frame') { return "Group Frames" }
    if ($s -match 'unit aura|aura2') { return "auras" }
    if ($s -match 'interrupt') { return "Interrupt Ready" }
    if ($s -match 'unit text') { return "unit text" }
    if ($s -match 'border|outline') { return "borders and outlines" }
    if ($s -match 'bar|power') { return "bars and power bars" }
    if ($s -match 'profile') { return "profiles" }
    if ($s -match 'core|runtime|foundation') { return "unit frame runtime" }
    if ($s -match 'tool|release|doc') { return "release tooling" }
    return "addon behavior"
}

function Convert-AutoBulletToFriendlyText {
    param(
        [Parameter(Mandatory = $true)][string]$Bullet,
        [Parameter(Mandatory = $true)][string]$Category
    )

    $text = $Bullet.Trim()
    if ($text -eq "") { return "" }

    $text = $text -replace '\*\*', ''
    $text = $text -replace '\s+\((?:working tree|[0-9a-f]{6,40}|[^)]*;)[^)]*\)\.?$', ''
    $text = $text.Trim().TrimEnd(".")

    $scope = ""
    $body = $text
    if ($text -match '^([^:]+):\s*(.+)$') {
        $scope = $Matches[1].Trim()
        $body = $Matches[2].Trim()
    }

    $body = $body -replace '(?i)^(updated|added|removed|renamed)\s+', ''
    $body = $body -replace '(?i)^(some\s+)?user friendly stuff$', 'menu and dashboard usability'
    $body = $body -replace '(?i)^class color background$', 'class color background handling'
    $body = $body.Trim().TrimEnd(".")

    $scopeText = Get-FriendlyScopeText $scope
    $haystack = (($scope + " " + $body) -replace '\s+', ' ').ToLowerInvariant()

    if ($haystack -match 'class color background') {
        return Format-FriendlySentence "Improved class color background handling across unit and group frames"
    }
    if ($haystack -match 'user friendly|usability|menu and dashboard usability') {
        return Format-FriendlySentence "Improved menu and dashboard wording, layout, and everyday usability"
    }
    if ($haystack -match 'combat gating|protected') {
        return Format-FriendlySentence "Improved combat safety for protected UI changes"
    }
    if ($haystack -match 'range fade|highlight') {
        return Format-FriendlySentence "Improved Group Frame range fade and highlight behavior"
    }
    if ($haystack -match 'aura|reminder') {
        return Format-FriendlySentence "Improved aura and reminder behavior"
    }
    if ($haystack -match 'profile|export|import') {
        return Format-FriendlySentence "Improved profile import and export handling"
    }
    if ($haystack -match 'changelog|release notes') {
        return Format-FriendlySentence "Updated the release notes shown in the in-game dashboard"
    }

    if ($Category -eq "Performance") {
        return Format-FriendlySentence "Improved performance for $scopeText"
    }
    if ($Category -eq "Bugfixes") {
        if ($body -match '(?i)^fixed\s+') {
            return Format-FriendlySentence $body
        }
        return Format-FriendlySentence "Fixed issues affecting $scopeText"
    }
    if ($Category -eq "Release / Tooling") {
        return Format-FriendlySentence "Improved release tooling and changelog generation"
    }
    if ($Category -eq "Documentation") {
        return Format-FriendlySentence "Updated documentation and release notes"
    }

    if ($body -match '(?i)^(improved|fixed|added|removed|updated)\s+') {
        return Format-FriendlySentence $body
    }
    if ($body -ne "" -and $body -notmatch '(?i)^(addon behavior|behavior)$') {
        return Format-FriendlySentence ("Improved " + $body)
    }

    return Format-FriendlySentence "Improved $scopeText"
}

function Convert-AutoGroupsToFriendlyGroups {
    param([Parameter(Mandatory = $true)]$Groups)

    $friendly = New-AutoGroupMap
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($title in $SectionOrder) {
        if (-not $Groups.Contains($title)) { continue }
        foreach ($bullet in $Groups[$title]) {
            $text = Convert-AutoBulletToFriendlyText -Bullet "$bullet" -Category $title
            Add-AutoBulletToGroup -Groups $friendly -Seen $seen -Title $title -Bullet $text
        }
    }
    return $friendly
}

function Get-EditableAutoChangelogGroups {
    $generated = Get-AutoChangelogGroups
    if (-not $KeepExistingAutoEntries -and -not $IncludePrereleaseAutoEntries) { return $generated }

    $fullPath = Resolve-RepoPath $ChangelogPath
    if (-not (Test-Path -LiteralPath $fullPath)) { return $generated }

    $content = Get-Content -LiteralPath $fullPath -Raw
    $lines = [regex]::Split($content, "\r?\n")
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        $lines = [string[]]$lines[0..($lines.Count - 2)]
    }

    try {
        $bounds = Find-ReleaseBounds -Lines $lines -WantedVersion $DisplayVersion
    } catch {
        return $generated
    }

    $existing = if ($KeepExistingAutoEntries) {
        Get-KeepExistingAutoGroups -Lines $lines -Bounds $bounds
    } else {
        New-AutoGroupMap
    }
    if ($IncludePrereleaseAutoEntries) {
        $releaseGroups = Get-CarriedFinalReleaseAutoGroups -Lines $lines -TargetVersion $bounds.Version
        $existing = Merge-AutoGroups -Existing $existing -Generated $releaseGroups
    }
    return (Merge-AutoGroups -Existing $existing -Generated $generated)
}

function Remove-AutoBlocks {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines)

    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $Lines) {
        if ($line -match '^\s*<!--\s*MSUF-AUTO-CHANGELOG:\s*-->\s*$') {
            $skip = -not $skip
            continue
        }
        if ($line -match '^\s*<!--\s*MSUF-AUTO-CHANGELOG:[^:]+:START\s*-->\s*$') {
            $skip = $true
            continue
        }
        if ($skip) {
            if ($line -match '^\s*<!--\s*MSUF-AUTO-CHANGELOG:[^:]+:END\s*-->\s*$') {
                $skip = $false
            }
            continue
        }
        $out.Add($line)
    }
    return [string[]]$out.ToArray()
}

function Remove-EmptyMarkdownSections {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines)

    $out = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $Lines.Count) {
        $line = $Lines[$i]
        if ($line -match '^###\s+') {
            $start = $i
            $end = $Lines.Count
            for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                if ($Lines[$j] -match '^###\s+|^##\s+') {
                    $end = $j
                    break
                }
            }

            $hasContent = $false
            for ($j = $start + 1; $j -lt $end; $j++) {
                if (-not [string]::IsNullOrWhiteSpace($Lines[$j])) {
                    $hasContent = $true
                    break
                }
            }

            if ($hasContent) {
                for ($j = $start; $j -lt $end; $j++) {
                    $out.Add($Lines[$j])
                }
            }

            $i = $end
            continue
        }

        $out.Add($line)
        $i++
    }

    return [string[]]$out.ToArray()
}

function Get-MarkerKey {
    param([Parameter(Mandatory = $true)][string]$Title)

    return ([regex]::Replace($Title, '[^A-Za-z0-9]+', '-')).Trim('-')
}

function Compress-BlankLines {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines)

    $out = New-Object System.Collections.Generic.List[string]
    $blankCount = 0
    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            $blankCount++
            if ($blankCount -le 1) {
                $out.Add("")
            }
            continue
        }

        $blankCount = 0
        $out.Add($line)
    }

    return [string[]]$out.ToArray()
}

function Insert-AutoBlock {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Bullets
    )

    if ($Bullets.Count -eq 0) { return }

    $heading = "### $Title"
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $heading) {
            $start = $i
            break
        }
    }

    if ($start -lt 0) {
        while ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1].Trim() -eq "") {
            $Lines.RemoveAt($Lines.Count - 1)
        }
        if ($Lines.Count -gt 0) { $Lines.Add("") }
        $Lines.Add($heading)
        $Lines.Add("")
        $start = $Lines.Count - 2
    }

    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^###\s+') {
            $end = $i
            break
        }
    }

    $insert = $end
    while ($insert -gt ($start + 1) -and $Lines[$insert - 1].Trim() -eq "") {
        $insert--
    }

    $marker = Get-MarkerKey $Title
    $block = New-Object System.Collections.Generic.List[string]
    if ($insert -gt 0 -and $Lines[$insert - 1].Trim() -ne "") {
        $block.Add("")
    }
    $block.Add("<!-- MSUF-AUTO-CHANGELOG:${marker}:START -->")
    foreach ($bullet in $Bullets) {
        $block.Add("- $bullet")
    }
    $block.Add("<!-- MSUF-AUTO-CHANGELOG:${marker}:END -->")
    $block.Add("")

    $Lines.InsertRange($insert, [string[]]$block.ToArray())
}

function Find-ReleaseBounds {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [AllowNull()][string]$WantedVersion
    )

    $wantedKey = Normalize-VersionKey $WantedVersion
    $firstRelease = $null
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^##\s+(.+?)(?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$') {
            $version = $Matches[1].Trim()
            if ($null -eq $firstRelease) {
                $firstRelease = [pscustomobject]@{ Start = $i; Version = $version }
            }
            if ($wantedKey -eq "" -or (Normalize-VersionKey $version) -eq $wantedKey) {
                $end = $Lines.Count
                for ($j = $i + 1; $j -lt $Lines.Count; $j++) {
                    if ($Lines[$j] -match '^##\s+') {
                        $end = $j
                        break
                    }
                }
                return [pscustomobject]@{ Start = $i; End = $end; Version = $version }
            }
        }
    }

    if ($null -ne $firstRelease -and $wantedKey -eq "") {
        return $firstRelease
    }
    throw "Could not find release section in CHANGELOG.md for '$WantedVersion'."
}

function New-ChangelogWithReleaseSection {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Version,
        [AllowNull()][string]$Date
    )

    $cleanVersion = $Version.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanVersion)) {
        throw "Cannot create a changelog section without a version title."
    }

    $cleanDate = if ($null -eq $Date) { "" } else { $Date.Trim() }
    if ($cleanDate -ne "" -and $cleanDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Release date must be empty or YYYY-MM-DD."
    }

    $heading = if ($cleanDate -eq "") { "## $cleanVersion" } else { "## $cleanVersion - $cleanDate" }
    $newSection = @($heading, "")

    $titleIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^#\s+Changelog\s*$') {
            $titleIndex = $i
            break
        }
    }

    if ($titleIndex -lt 0) {
        return [string[]](@("# Changelog", "") + $newSection + @($Lines))
    }

    $restStart = $titleIndex + 1
    while ($restStart -lt $Lines.Count -and $Lines[$restStart].Trim() -eq "") {
        $restStart++
    }

    $before = [string[]]($Lines[0..$titleIndex] + @(""))
    $after = if ($restStart -lt $Lines.Count) { [string[]]$Lines[$restStart..($Lines.Count - 1)] } else { @() }
    return [string[]](@($before) + $newSection + @($after))
}

function Update-ChangelogAutoBlocks {
    param([Parameter(Mandatory = $true)]$Groups)

    $fullPath = Resolve-RepoPath $ChangelogPath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Changelog file not found: $fullPath"
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    $newline = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [regex]::Split($content, "\r?\n")
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        $lines = [string[]]$lines[0..($lines.Count - 2)]
    }

    try {
        $bounds = Find-ReleaseBounds -Lines $lines -WantedVersion $DisplayVersion
    } catch {
        if (-not $CreateMissingRelease) { throw }
        $lines = New-ChangelogWithReleaseSection -Lines $lines -Version $DisplayVersion -Date $ReleaseDate
        $bounds = Find-ReleaseBounds -Lines $lines -WantedVersion $DisplayVersion
        Write-AutoLog "Created new CHANGELOG.md section for $($bounds.Version)."
    }
    if ($KeepExistingAutoEntries) {
        $releaseLines = Get-ReleaseLinesFromBounds -Lines $lines -Bounds $bounds
        $existingGroups = Get-ExistingAutoBlocks -Lines $releaseLines
        $carriedGroups = Get-CarriedPrereleaseAutoGroups -Lines $lines -TargetVersion $bounds.Version
        $carriedCount = Get-AutoGroupEntryCount -Groups $carriedGroups
        if ($carriedCount -gt 0) {
            Write-AutoLog "Carried $carriedCount old auto entries from earlier $($bounds.Version) prerelease sections."
        }
        $keptGroups = Merge-AutoGroups -Existing $existingGroups -Generated $carriedGroups
        $mergedGroups = Merge-AutoGroups -Existing $keptGroups -Generated $Groups
    } else {
        $mergedGroups = $Groups
    }
    if ($IncludePrereleaseAutoEntries) {
        $releaseGroups = Get-CarriedFinalReleaseAutoGroups -Lines $lines -TargetVersion $bounds.Version
        $releaseCount = Get-AutoGroupEntryCount -Groups $releaseGroups
        if ($releaseCount -gt 0) {
            Write-AutoLog "Included $releaseCount old auto entries from earlier prerelease sections for final release $($bounds.Version)."
        }
        $mergedGroups = Merge-AutoGroups -Existing $releaseGroups -Generated $mergedGroups
    }

    $lines = Remove-AutoBlocks -Lines $lines
    $lines = Remove-EmptyMarkdownSections -Lines $lines
    $bounds = Find-ReleaseBounds -Lines $lines -WantedVersion $DisplayVersion
    $before = if ($bounds.Start -gt 0) { [string[]]$lines[0..($bounds.Start - 1)] } else { @() }
    $cleanReleaseLines = if ($bounds.End -gt $bounds.Start) { [string[]]$lines[$bounds.Start..($bounds.End - 1)] } else { @($lines[$bounds.Start]) }
    $after = if ($bounds.End -lt $lines.Count) { [string[]]$lines[$bounds.End..($lines.Count - 1)] } else { @() }

    $releaseList = New-Object System.Collections.Generic.List[string]
    foreach ($line in $cleanReleaseLines) { $releaseList.Add($line) }

    foreach ($title in $SectionOrder) {
        $items = [string[]]$mergedGroups[$title].ToArray()
        Insert-AutoBlock -Lines $releaseList -Title $title -Bullets $items
    }

    $compressedReleaseLines = Compress-BlankLines -Lines ([string[]]$releaseList.ToArray())
    $releaseList.Clear()
    foreach ($line in $compressedReleaseLines) { $releaseList.Add($line) }

    $updated = @($before) + [string[]]$releaseList.ToArray() + @($after)
    $updated = Compress-BlankLines -Lines ([string[]]$updated)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($fullPath, (($updated -join $newline).TrimEnd() + $newline), $utf8NoBom)
    return $bounds.Version
}

function Update-AddonChangelog {
    param([Parameter(Mandatory = $true)][string]$Version)

    if (-not $RegenerateAddonChangelog) { return }
    if (-not (Test-Path -LiteralPath $AddonChangelogScript)) {
        throw "Missing addon changelog generator: $AddonChangelogScript"
    }

    $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if ([string]::IsNullOrWhiteSpace($exe)) { $exe = "powershell" }
    $output = & $exe -NoProfile -ExecutionPolicy Bypass -File $AddonChangelogScript -Version $Version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Addon changelog generation failed: $($output -join ' ')"
    }
    foreach ($line in $output) {
        if (-not [string]::IsNullOrWhiteSpace("$line")) { Write-AutoLog "$line" }
    }
}

function Invoke-AutoChangelogUpdate {
    $groups = Get-AutoChangelogGroups
    $count = 0
    foreach ($title in $SectionOrder) { $count += $groups[$title].Count }
    $version = Update-ChangelogAutoBlocks -Groups $groups
    Update-AddonChangelog -Version $version
    Write-AutoLog "Updated CHANGELOG.md auto blocks for $version ($count entries)."
}

function Invoke-EditedAutoChangelogUpdate {
    param([AllowNull()][string]$Markdown)

    $groups = Convert-MarkdownToAutoGroups -Markdown $Markdown
    $count = 0
    foreach ($title in $SectionOrder) { $count += $groups[$title].Count }

    $previousKeep = $KeepExistingAutoEntries
    $previousIncludePrerelease = $IncludePrereleaseAutoEntries
    $script:KeepExistingAutoEntries = $false
    $script:IncludePrereleaseAutoEntries = $false
    try {
        $version = Update-ChangelogAutoBlocks -Groups $groups
    } finally {
        $script:KeepExistingAutoEntries = $previousKeep
        $script:IncludePrereleaseAutoEntries = $previousIncludePrerelease
    }

    Update-AddonChangelog -Version $version
    Write-AutoLog "Updated CHANGELOG.md auto blocks from edited text for $version ($count entries)."
}

function Get-RepoChangeSignature {
    Push-Location $RepoRoot
    try {
        $head = (& git rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) { $head = "" }

        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add("HEAD=$head")
        foreach ($entry in Get-GitStatusEntries) {
            $path = [string]$entry.Path
            $full = Resolve-RepoPath $path
            if (Test-Path -LiteralPath $full) {
                $item = Get-Item -LiteralPath $full
                $parts.Add(("{0}|{1}|{2}|{3}" -f $entry.Code, $path, $item.Length, $item.LastWriteTimeUtc.Ticks))
            } else {
                $parts.Add(("{0}|{1}|deleted" -f $entry.Code, $path))
            }
        }

        $raw = $parts -join "`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "")
        } finally {
            $sha.Dispose()
        }
    } finally {
        Pop-Location
    }
}

function Convert-TagToDisplayVersion {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    $v = $v -replace '(?i)[\-_]?beta[\-_.]?(\d+)', ' Beta $1'
    $v = $v -replace '(?i)[\-_]?alpha[\-_.]?(\d+)', ' Alpha $1'
    $v = $v -replace '(?i)[\-_]?rc[\-_.]?(\d+)', ' RC $1'
    $v = $v -replace '[-_]+', ' '
    return ($v -replace '\s+', ' ').Trim()
}

function Get-RepoVersionText {
    $versionPath = Join-Path $RepoRoot "VERSION"
    if (-not (Test-Path -LiteralPath $versionPath)) { return "" }
    return ((Get-Content -LiteralPath $versionPath -Raw).Trim())
}

function Get-LatestChangelogVersion {
    param([AllowNull()][string]$Path = $ChangelogPath)

    $targetPath = if ([string]::IsNullOrWhiteSpace($Path)) { "CHANGELOG.md" } else { $Path }
    $fullPath = Resolve-RepoPath $targetPath
    if (-not (Test-Path -LiteralPath $fullPath)) { return "" }

    foreach ($line in (Get-Content -LiteralPath $fullPath)) {
        if ($line -match '^##\s+(.+?)(?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$') {
            return $Matches[1].Trim()
        }
    }
    return ""
}

function Set-AutoChangelogSettings {
    param(
        [Parameter(Mandatory = $true)][string]$ChangelogFile,
        [Parameter(Mandatory = $true)][string]$VersionTitle,
        [AllowNull()][string]$VersionDate,
        [AllowNull()][string]$GitBaseRef,
        [int]$GitSinceHours,
        [bool]$CreateMissingSection,
        [bool]$KeepExistingEntries,
        [bool]$IncludePrereleaseEntries,
        [bool]$RegenerateAddon,
        [bool]$IncludeReleaseTooling,
        [int]$PollEverySeconds,
        [int]$DebounceEverySeconds
    )

    if ([string]::IsNullOrWhiteSpace($VersionTitle)) {
        throw "Changelog title cannot be empty. Use Latest CHANGELOG.md or VERSION if you want a detected value."
    }

    $cleanChangelog = if ([string]::IsNullOrWhiteSpace($ChangelogFile)) { "CHANGELOG.md" } else { $ChangelogFile.Trim() }
    $resolvedChangelog = Resolve-RepoPath $cleanChangelog
    if (-not (Test-Path -LiteralPath $resolvedChangelog)) {
        throw "Changelog file not found: $resolvedChangelog"
    }

    $script:ChangelogPath = $cleanChangelog
    $script:DisplayVersion = $VersionTitle.Trim()
    $script:ReleaseDate = if ([string]::IsNullOrWhiteSpace($VersionDate)) { "" } else { $VersionDate.Trim() }
    if ($script:ReleaseDate -ne "" -and $script:ReleaseDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Release date must be empty or YYYY-MM-DD."
    }
    $script:BaseRef = if ([string]::IsNullOrWhiteSpace($GitBaseRef)) { "" } else { $GitBaseRef.Trim() }
    if ($GitSinceHours -lt 0 -or $GitSinceHours -gt 100) {
        throw "Since hours must be 0 or between 1 and 100."
    }
    $script:SinceHours = $GitSinceHours
    $script:CreateMissingRelease = [bool]$CreateMissingSection
    $script:KeepExistingAutoEntries = [bool]$KeepExistingEntries
    $script:IncludePrereleaseAutoEntries = [bool]$IncludePrereleaseEntries
    $script:RegenerateAddonChangelog = [bool]$RegenerateAddon
    $script:IncludeTooling = [bool]$IncludeReleaseTooling
    $script:PollSeconds = [Math]::Max(1, $PollEverySeconds)
    $script:DebounceSeconds = [Math]::Max(0, $DebounceEverySeconds)
}

function Start-AutoChangelogGui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $initialDisplay = if ([string]::IsNullOrWhiteSpace($DisplayVersion)) { Get-LatestChangelogVersion -Path $ChangelogPath } else { $DisplayVersion.Trim() }
    if ([string]::IsNullOrWhiteSpace($initialDisplay)) {
        $initialDisplay = Convert-TagToDisplayVersion (Get-RepoVersionText)
    }
    $initialReleaseDate = if ([string]::IsNullOrWhiteSpace($ReleaseDate)) { Get-Date -Format "yyyy-MM-dd" } else { $ReleaseDate.Trim() }
    $initialBaseRef = if ([string]::IsNullOrWhiteSpace($BaseRef)) { Get-DefaultBaseRef } else { $BaseRef.Trim() }
    $script:AutoGuiBusy = $false
    $script:AutoGuiPendingSignature = $null
    $script:AutoGuiPendingSince = Get-Date
    $script:AutoGuiLastWrittenSignature = $null

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "MSUF Auto Changelog"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size(1040, 880)
    $form.MinimumSize = New-Object System.Drawing.Size(960, 760)

    $tips = New-Object System.Windows.Forms.ToolTip
    $tips.AutoPopDelay = 12000
    $tips.InitialDelay = 500
    $tips.ReshowDelay = 200

    function New-AutoLabel {
        param([string]$Text, [int]$X, [int]$Y, [int]$W = 120)
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Text
        $label.Location = New-Object System.Drawing.Point($X, $Y)
        $label.Size = New-Object System.Drawing.Size($W, 20)
        $form.Controls.Add($label)
        return $label
    }

    function New-AutoTextBox {
        param([int]$X, [int]$Y, [int]$W, [string]$Text = "")
        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point($X, $Y)
        $box.Size = New-Object System.Drawing.Size($W, 22)
        $box.Text = $Text
        $form.Controls.Add($box)
        return $box
    }

    function New-AutoButton {
        param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 30)
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $Text
        $button.Location = New-Object System.Drawing.Point($X, $Y)
        $button.Size = New-Object System.Drawing.Size($W, $H)
        $form.Controls.Add($button)
        return $button
    }

    New-AutoLabel "Changelog title" 16 18 120 | Out-Null
    $displayBox = New-AutoTextBox 145 16 230 $initialDisplay
    $tips.SetToolTip($displayBox, "The release heading in CHANGELOG.md, for example '5.1 Beta 4'.")

    $latestButton = New-AutoButton "Latest CHANGELOG.md" 385 13 150 28
    $tips.SetToolTip($latestButton, "Use the first release section currently found in CHANGELOG.md.")

    $versionButton = New-AutoButton "VERSION" 545 13 86 28
    $tips.SetToolTip($versionButton, "Read the repository VERSION file and format beta/alpha/rc tags for display.")

    New-AutoLabel "Date" 650 18 40 | Out-Null
    $dateBox = New-AutoTextBox 695 16 100 $initialReleaseDate
    $tips.SetToolTip($dateBox, "Date for a newly created release section. Use YYYY-MM-DD or leave empty.")

    New-AutoLabel "Source ref" 16 54 120 | Out-Null
    $baseRefBox = New-AutoTextBox 145 52 230 $initialBaseRef
    $tips.SetToolTip($baseRefBox, "Existing Git ref used as the start of the commit range. This is usually the previous release tag, not the changelog target.")

    $lastTagButton = New-AutoButton "Last tag" 385 49 90 28
    $tips.SetToolTip($lastTagButton, "Detect the latest reachable Git tag.")

    $clearBaseButton = New-AutoButton "All history" 485 49 90 28
    $tips.SetToolTip($clearBaseButton, "Clear Since ref so the tool reads all commits up to HEAD.")

    New-AutoLabel "Hours" 590 54 45 | Out-Null
    $sinceHoursBox = New-Object System.Windows.Forms.NumericUpDown
    $sinceHoursBox.Location = New-Object System.Drawing.Point(640, 52)
    $sinceHoursBox.Size = New-Object System.Drawing.Size(55, 22)
    $sinceHoursBox.Minimum = 0
    $sinceHoursBox.Maximum = 100
    $sinceHoursBox.Value = [Math]::Min(100, [Math]::Max(0, $SinceHours))
    $tips.SetToolTip($sinceHoursBox, "0 uses Since ref. 1-100 generates from commits made in the last N hours.")
    $form.Controls.Add($sinceHoursBox)

    New-AutoLabel "Changelog file" 16 90 120 | Out-Null
    $changelogBox = New-AutoTextBox 145 88 360 $ChangelogPath
    $tips.SetToolTip($changelogBox, "Path must stay inside the repository. Default is CHANGELOG.md.")

    $regenBox = New-Object System.Windows.Forms.CheckBox
    $regenBox.Text = "Regenerate addon changelog"
    $regenBox.Checked = $true
    if ($PSBoundParameters.ContainsKey("RegenerateAddonChangelog")) {
        $regenBox.Checked = [bool]$RegenerateAddonChangelog
    }
    $regenBox.Location = New-Object System.Drawing.Point(525, 86)
    $regenBox.Size = New-Object System.Drawing.Size(210, 24)
    $tips.SetToolTip($regenBox, "Also update MidnightSimpleUnitFrames\\Foundation\\MSUF_Changelog.lua.")
    $form.Controls.Add($regenBox)

    $toolingBox = New-Object System.Windows.Forms.CheckBox
    $toolingBox.Text = "Include tooling/docs"
    $toolingBox.Checked = [bool]$IncludeTooling
    $toolingBox.Location = New-Object System.Drawing.Point(745, 86)
    $toolingBox.Size = New-Object System.Drawing.Size(150, 24)
    $tips.SetToolTip($toolingBox, "Include docs, workflow, packaging, and tool changes in generated notes.")
    $form.Controls.Add($toolingBox)

    New-AutoLabel "Poll seconds" 16 126 120 | Out-Null
    $pollBox = New-Object System.Windows.Forms.NumericUpDown
    $pollBox.Location = New-Object System.Drawing.Point(145, 124)
    $pollBox.Size = New-Object System.Drawing.Size(70, 22)
    $pollBox.Minimum = 1
    $pollBox.Maximum = 60
    $pollBox.Value = [Math]::Max(1, $PollSeconds)
    $tips.SetToolTip($pollBox, "How often the watcher checks Git state.")
    $form.Controls.Add($pollBox)

    New-AutoLabel "Debounce seconds" 235 126 125 | Out-Null
    $debounceBox = New-Object System.Windows.Forms.NumericUpDown
    $debounceBox.Location = New-Object System.Drawing.Point(365, 124)
    $debounceBox.Size = New-Object System.Drawing.Size(70, 22)
    $debounceBox.Minimum = 0
    $debounceBox.Maximum = 120
    $debounceBox.Value = [Math]::Max(0, $DebounceSeconds)
    $tips.SetToolTip($debounceBox, "How long changes must be quiet before the watcher writes.")
    $form.Controls.Add($debounceBox)

    $createMissingBox = New-Object System.Windows.Forms.CheckBox
    $createMissingBox.Text = "Create missing release"
    $createMissingBox.Checked = [bool]$CreateMissingRelease
    if (-not $CreateMissingRelease) { $createMissingBox.Checked = $true }
    $createMissingBox.Location = New-Object System.Drawing.Point(525, 122)
    $createMissingBox.Size = New-Object System.Drawing.Size(190, 24)
    $tips.SetToolTip($createMissingBox, "If the selected changelog title does not exist, create it at the top of CHANGELOG.md.")
    $form.Controls.Add($createMissingBox)

    $keepExistingBox = New-Object System.Windows.Forms.CheckBox
    $keepExistingBox.Text = "Keep old auto entries"
    $keepExistingBox.Checked = [bool]$KeepExistingAutoEntries
    $keepExistingBox.Location = New-Object System.Drawing.Point(720, 122)
    $keepExistingBox.Size = New-Object System.Drawing.Size(175, 24)
    $tips.SetToolTip($keepExistingBox, "Merge existing auto entries and carry older Alpha/Beta/RC/Pre entries from the same version line. Leave off to replace old auto entries.")
    $form.Controls.Add($keepExistingBox)

    $includePrereleaseBox = New-Object System.Windows.Forms.CheckBox
    $includePrereleaseBox.Text = "Include prerelease logs"
    $includePrereleaseBox.Checked = [bool]$IncludePrereleaseAutoEntries
    $includePrereleaseBox.Location = New-Object System.Drawing.Point(720, 146)
    $includePrereleaseBox.Size = New-Object System.Drawing.Size(210, 24)
    $tips.SetToolTip($includePrereleaseBox, "For a final release such as 5.1, include managed auto entries from 5.1 Alpha/Beta/RC/Pre sections.")
    $form.Controls.Add($includePrereleaseBox)

    $summaryBox = New-Object System.Windows.Forms.TextBox
    $summaryBox.Location = New-Object System.Drawing.Point(16, 178)
    $summaryBox.Size = New-Object System.Drawing.Size(1000, 74)
    $summaryBox.Multiline = $true
    $summaryBox.ReadOnly = $true
    $summaryBox.ScrollBars = "Vertical"
    $summaryBox.Text = "Changelog title is the only release section written, for example 5.2. Generate Editor scans commits, patches, and working-tree changes into user-facing notes. Write Edited writes exactly those managed auto blocks."
    $form.Controls.Add($summaryBox)

    $previewButton = New-AutoButton "Generate Editor" 16 270 125 32
    $makeFriendlyButton = New-AutoButton "Make Friendly" 151 270 115 32
    $writeEditedButton = New-AutoButton "Write Edited" 276 270 105 32
    $runButton = New-AutoButton "Run Once" 391 270 85 32
    $startWatchButton = New-AutoButton "Start Watch" 486 270 100 32
    $stopWatchButton = New-AutoButton "Stop Watch" 596 270 100 32
    $stopWatchButton.Enabled = $false
    $statusButton = New-AutoButton "Git Status" 706 270 85 32
    $openButton = New-AutoButton "Open CHANGELOG.md" 801 270 135 32
    $closeButton = New-AutoButton "Close" 946 270 70 32

    New-AutoLabel "Editable auto changelog Markdown" 16 318 240 | Out-Null
    $editBox = New-Object System.Windows.Forms.TextBox
    $editBox.Location = New-Object System.Drawing.Point(16, 340)
    $editBox.Size = New-Object System.Drawing.Size(1000, 190)
    $editBox.Multiline = $true
    $editBox.ScrollBars = "Vertical"
    $editBox.AcceptsReturn = $true
    $editBox.AcceptsTab = $true
    $tips.SetToolTip($editBox, "Generate entries here, edit the bullets, then use Write Edited to write these auto blocks.")
    $form.Controls.Add($editBox)

    $script:AutoLogBox = New-Object System.Windows.Forms.TextBox
    $script:AutoLogBox.Location = New-Object System.Drawing.Point(16, 560)
    $script:AutoLogBox.Size = New-Object System.Drawing.Size(1000, 250)
    $script:AutoLogBox.Multiline = $true
    $script:AutoLogBox.ScrollBars = "Vertical"
    $script:AutoLogBox.ReadOnly = $true
    $form.Controls.Add($script:AutoLogBox)

    function Set-SettingsFromUi {
        Set-AutoChangelogSettings `
            -ChangelogFile $changelogBox.Text `
            -VersionTitle $displayBox.Text `
            -VersionDate $dateBox.Text `
            -GitBaseRef $baseRefBox.Text `
            -GitSinceHours ([int]$sinceHoursBox.Value) `
            -CreateMissingSection $createMissingBox.Checked `
            -KeepExistingEntries $keepExistingBox.Checked `
            -IncludePrereleaseEntries $includePrereleaseBox.Checked `
            -RegenerateAddon $regenBox.Checked `
            -IncludeReleaseTooling $toolingBox.Checked `
            -PollEverySeconds ([int]$pollBox.Value) `
            -DebounceEverySeconds ([int]$debounceBox.Value)
    }

    function Set-WatchControls {
        param([bool]$Watching)
        $startWatchButton.Enabled = -not $Watching
        $stopWatchButton.Enabled = $Watching
        $runButton.Enabled = -not $Watching
        $previewButton.Enabled = -not $Watching
        $makeFriendlyButton.Enabled = -not $Watching
        $writeEditedButton.Enabled = -not $Watching
    }

    function Resolve-SourceRefFromUi {
        if ((Get-EffectiveSinceHours) -gt 0) {
            Write-AutoLog ("Using commits from the last " + $script:SinceHours + " hours; Since ref is ignored.")
            return ""
        }
        $entered = $baseRefBox.Text.Trim()
        $effective = Get-EffectiveBaseRef
        if (-not [string]::IsNullOrWhiteSpace($entered) -and $effective -ne $entered) {
            $baseRefBox.Text = $effective
            $script:BaseRef = $effective
            Write-AutoLog ("Source ref updated to existing Git ref: " + $effective)
        }
        return $effective
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = [Math]::Max(1, [int]$pollBox.Value) * 1000

    $latestButton.Add_Click({
        try {
            $version = Get-LatestChangelogVersion -Path $changelogBox.Text
            if ([string]::IsNullOrWhiteSpace($version)) { throw "No release section found in CHANGELOG.md." }
            $displayBox.Text = $version
            Write-AutoLog ("Changelog title set to latest section: " + $version)
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $versionButton.Add_Click({
        try {
            $version = Convert-TagToDisplayVersion (Get-RepoVersionText)
            if ([string]::IsNullOrWhiteSpace($version)) { throw "VERSION file is missing or empty." }
            $displayBox.Text = $version
            Write-AutoLog ("Changelog title set from VERSION: " + $version)
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $lastTagButton.Add_Click({
        try {
            $baseRefBox.Text = Get-DefaultBaseRef
            Write-AutoLog ("Source ref set to: " + $baseRefBox.Text)
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
        }
    })

    $clearBaseButton.Add_Click({
        $baseRefBox.Text = ""
        Write-AutoLog "Source ref cleared; commit range will use full history."
    })

    $previewButton.Add_Click({
        try {
            Set-SettingsFromUi
            Resolve-SourceRefFromUi | Out-Null
            $groups = Get-EditableAutoChangelogGroups
            $editBox.Text = Convert-AutoGroupsToMarkdown -Groups $groups
            $count = 0
            Write-AutoLog "----- Editable generated entries -----"
            foreach ($title in $SectionOrder) {
                if ($groups[$title].Count -eq 0) { continue }
                Write-AutoLog ("### " + $title)
                foreach ($item in $groups[$title]) {
                    $count++
                    Write-AutoLog ("- " + $item)
                }
            }
            if ($count -eq 0) {
                Write-AutoLog "No entries generated for the selected settings; you can still type entries into the editor."
            } else {
                Write-AutoLog ("Editor loaded: " + $count + " entries.")
            }
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $makeFriendlyButton.Add_Click({
        try {
            Set-SettingsFromUi
            $groups = if ([string]::IsNullOrWhiteSpace($editBox.Text)) {
                Resolve-SourceRefFromUi | Out-Null
                Get-EditableAutoChangelogGroups
            } else {
                Convert-MarkdownToAutoGroups -Markdown $editBox.Text
            }

            $friendly = Convert-AutoGroupsToFriendlyGroups -Groups $groups
            $editBox.Text = Convert-AutoGroupsToMarkdown -Groups $friendly

            $count = 0
            foreach ($title in $SectionOrder) { $count += $friendly[$title].Count }
            Write-AutoLog ("Converted editor entries to user-friendly changelog text (" + $count + " entries).")
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $writeEditedButton.Add_Click({
        if ($script:AutoGuiBusy) { return }
        $script:AutoGuiBusy = $true
        try {
            Set-SettingsFromUi
            Invoke-EditedAutoChangelogUpdate -Markdown $editBox.Text
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        } finally {
            $script:AutoGuiBusy = $false
        }
    })

    $runButton.Add_Click({
        if ($script:AutoGuiBusy) { return }
        $script:AutoGuiBusy = $true
        try {
            Set-SettingsFromUi
            Resolve-SourceRefFromUi | Out-Null
            Invoke-AutoChangelogUpdate
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        } finally {
            $script:AutoGuiBusy = $false
        }
    })

    $timer.Add_Tick({
        if ($script:AutoGuiBusy) { return }
        try {
            Set-SettingsFromUi
            Resolve-SourceRefFromUi | Out-Null
            $timer.Interval = [Math]::Max(1, [int]$pollBox.Value) * 1000
            $signature = Get-RepoChangeSignature
            if ($signature -ne $script:AutoGuiPendingSignature) {
                $script:AutoGuiPendingSignature = $signature
                $script:AutoGuiPendingSince = Get-Date
                return
            }

            if ($signature -ne $script:AutoGuiLastWrittenSignature -and ((Get-Date) - $script:AutoGuiPendingSince).TotalSeconds -ge $script:DebounceSeconds) {
                $script:AutoGuiBusy = $true
                try {
                    Invoke-AutoChangelogUpdate
                    $script:AutoGuiLastWrittenSignature = $signature
                } finally {
                    $script:AutoGuiBusy = $false
                }
            }
        } catch {
            $timer.Stop()
            Set-WatchControls -Watching $false
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $startWatchButton.Add_Click({
        try {
            Set-SettingsFromUi
            $effectiveBaseRef = Resolve-SourceRefFromUi
            $script:AutoGuiPendingSignature = $null
            $script:AutoGuiPendingSince = Get-Date
            $script:AutoGuiLastWrittenSignature = $null
            $timer.Interval = [Math]::Max(1, [int]$pollBox.Value) * 1000
            $timer.Start()
            Set-WatchControls -Watching $true
            $shownBaseRef = if ([string]::IsNullOrWhiteSpace($effectiveBaseRef)) { "full history" } else { $effectiveBaseRef }
            Write-AutoLog ("Watching repository changes for changelog section " + $script:DisplayVersion + ". Source ref: " + $shownBaseRef)
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $stopWatchButton.Add_Click({
        $timer.Stop()
        Set-WatchControls -Watching $false
        Write-AutoLog "Watcher stopped."
    })

    $statusButton.Add_Click({
        try {
            Push-Location $RepoRoot
            try {
                $status = @(git status --short 2>&1)
                if ($LASTEXITCODE -ne 0) { throw "git status failed: $($status -join ' ')" }
                if ($status.Count -eq 0) {
                    Write-AutoLog "Git worktree is clean."
                } else {
                    Write-AutoLog "Git worktree changes:"
                    foreach ($line in $status) { Write-AutoLog $line }
                }
            } finally {
                Pop-Location
            }
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
        }
    })

    $openButton.Add_Click({
        try {
            $fullPath = Resolve-RepoPath $changelogBox.Text
            if (-not (Test-Path -LiteralPath $fullPath)) { throw "Changelog file not found: $fullPath" }
            Start-Process $fullPath
        } catch {
            Write-AutoLog ("ERROR: " + $_.Exception.Message)
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Auto Changelog", "OK", "Error") | Out-Null
        }
    })

    $closeButton.Add_Click({ $form.Close() })
    $form.Add_FormClosed({
        $timer.Stop()
        $timer.Dispose()
        $script:AutoLogBox = $null
    })

    Write-AutoLog "Ready. Pick the changelog title, base ref, and write mode."
    [void]$form.ShowDialog()
}

if ($NoGui) {
    Write-AutoLog "NoGui mode is only a syntax/load check for this helper."
    return
}

if ($Gui) {
    Start-AutoChangelogGui
    return
}

if ($PollSeconds -lt 1) { $PollSeconds = 1 }
if ($DebounceSeconds -lt 0) { $DebounceSeconds = 0 }

if (-not $Watch) {
    Invoke-AutoChangelogUpdate
    return
}

Write-AutoLog "Watching repository changes. Press Ctrl+C to stop."
$startupHours = Get-EffectiveSinceHours
$startupBaseRef = if ($startupHours -gt 0) { "" } else { Get-EffectiveBaseRef }
if (-not [string]::IsNullOrWhiteSpace($startupBaseRef)) { $script:BaseRef = $startupBaseRef }
Write-AutoLog "Target changelog section: $DisplayVersion"
Write-AutoLog "Source range: $(if ($startupHours -gt 0) { "last $startupHours hours" } elseif ([string]::IsNullOrWhiteSpace($startupBaseRef)) { "full history" } else { $startupBaseRef })"

$pendingSignature = $null
$pendingSince = Get-Date
$lastWrittenSignature = $null

while ($true) {
    $signature = Get-RepoChangeSignature
    if ($signature -ne $pendingSignature) {
        $pendingSignature = $signature
        $pendingSince = Get-Date
    } elseif ($signature -ne $lastWrittenSignature -and ((Get-Date) - $pendingSince).TotalSeconds -ge $DebounceSeconds) {
        Invoke-AutoChangelogUpdate
        $lastWrittenSignature = $signature
    }

    Start-Sleep -Seconds $PollSeconds
}
