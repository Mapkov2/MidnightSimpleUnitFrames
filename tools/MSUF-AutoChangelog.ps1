[CmdletBinding()]
param(
    [string]$ChangelogPath = "CHANGELOG.md",
    [string]$DisplayVersion,
    [string]$BaseRef,
    [switch]$Watch,
    [switch]$RegenerateAddonChangelog,
    [switch]$IncludeTooling,
    [int]$PollSeconds = 2,
    [int]$DebounceSeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$AddonChangelogScript = Join-Path $RepoRoot "tools/update-addon-changelog.ps1"
$SectionOrder = @(
    "Performance",
    "Bugfixes",
    "Changes / Improvements",
    "Release / Tooling",
    "Documentation"
)

function Write-AutoLog {
    param([AllowNull()][string]$Message)

    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
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

function Add-GroupedBullet {
    param(
        [Parameter(Mandatory = $true)]$Groups,
        [Parameter(Mandatory = $true)]$Seen,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Bullet
    )

    $target = if ($Groups.Contains($Category)) { $Category } else { "Changes / Improvements" }
    $key = ($target + "|" + $Bullet).ToLowerInvariant()
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

function Add-CommitChangesToGroups {
    param(
        [Parameter(Mandatory = $true)]$Groups,
        [Parameter(Mandatory = $true)]$Seen
    )

    $base = if ([string]::IsNullOrWhiteSpace($BaseRef)) { Get-DefaultBaseRef } else { $BaseRef.Trim() }
    $range = if ([string]::IsNullOrWhiteSpace($base)) { "HEAD" } else { "$base..HEAD" }

    Push-Location $RepoRoot
    try {
        $commitLines = & git log --reverse --format="%H`t%h`t%s" $range 2>&1
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

            $areas = [string[]]@($paths | ForEach-Object { Get-ChangeArea $_ } | Select-Object -Unique)
            if ($areas.Count -eq 0) { $areas = @("General") }
            $scope = (($areas | Select-Object -First 3) -join ", ")
            $shownPaths = [string[]]@($paths | ForEach-Object { $_ -replace '^MidnightSimpleUnitFrames/', '' } | Select-Object -First 3)
            $pathText = if ($shownPaths.Count -gt 0) { "; " + ($shownPaths -join ", ") } else { "" }
            if ($paths.Count -gt 3) { $pathText += (" +" + ($paths.Count - 3) + " more") }

            $category = Get-ChangeCategory -Subject $subject -Paths $paths -Context ""
            $text = Convert-CommitSubjectToText $subject
            $bullet = "**$scope**: $text ($short$pathText)."
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
        $area = Get-ChangeArea $path
        $category = Get-ChangeCategory -Subject "" -Paths @($path) -Context $diff
        $description = Get-PathDescription -Path $path -StatusCode ([string]$entry.Code) -DiffText $diff
        $file = Split-Path -Path $path -Leaf
        $bullet = "**$area**: $description (working tree; $file)."
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

    $bounds = Find-ReleaseBounds -Lines $lines -WantedVersion $DisplayVersion
    $before = if ($bounds.Start -gt 0) { [string[]]$lines[0..($bounds.Start - 1)] } else { @() }
    $releaseLines = if ($bounds.End -gt $bounds.Start) { [string[]]$lines[$bounds.Start..($bounds.End - 1)] } else { @($lines[$bounds.Start]) }
    $after = if ($bounds.End -lt $lines.Count) { [string[]]$lines[$bounds.End..($lines.Count - 1)] } else { @() }

    $cleanReleaseLines = Remove-AutoBlocks -Lines $releaseLines
    $releaseList = New-Object System.Collections.Generic.List[string]
    foreach ($line in $cleanReleaseLines) { $releaseList.Add($line) }

    foreach ($title in $SectionOrder) {
        $items = [string[]]$Groups[$title].ToArray()
        Insert-AutoBlock -Lines $releaseList -Title $title -Bullets $items
    }

    $compressedReleaseLines = Compress-BlankLines -Lines ([string[]]$releaseList.ToArray())
    $releaseList.Clear()
    foreach ($line in $compressedReleaseLines) { $releaseList.Add($line) }

    $updated = @($before) + [string[]]$releaseList.ToArray() + @($after)
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

if ($PollSeconds -lt 1) { $PollSeconds = 1 }
if ($DebounceSeconds -lt 0) { $DebounceSeconds = 0 }

if (-not $Watch) {
    Invoke-AutoChangelogUpdate
    return
}

Write-AutoLog "Watching repository changes. Press Ctrl+C to stop."
Write-AutoLog "Base ref: $(if ([string]::IsNullOrWhiteSpace($BaseRef)) { Get-DefaultBaseRef } else { $BaseRef })"

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
