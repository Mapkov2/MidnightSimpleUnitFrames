[CmdletBinding()]
param(
    [switch]$NoGui
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$ChangelogPath = Join-Path $RepoRoot "CHANGELOG.md"
$AddonChangelogScript = Join-Path $RepoRoot "tools/update-addon-changelog.ps1"
$AutoChangelogScript = Join-Path $RepoRoot "tools/MSUF-AutoChangelog.ps1"
$PackageScript = Join-Path $RepoRoot "tools/package-release.ps1"
$script:LogBox = $null

function Write-ReleaseLog {
    param([AllowNull()][string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), ($Message -replace "`r?`n", " ")
    if ($script:LogBox -and -not $script:LogBox.IsDisposed) {
        $script:LogBox.AppendText($line + [Environment]::NewLine)
        $script:LogBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host $line
    }
}

function Normalize-ReleaseVersion {
    param([Parameter(Mandatory = $true)][string]$Value)

    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    if ([string]::IsNullOrWhiteSpace($v)) { throw "Release version/tag cannot be empty." }
    return $v
}

function Normalize-VersionKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $v = $Value.Trim()
    $v = $v -replace '^refs/tags/', ''
    $v = $v -replace '^v(?=\d)', ''
    return ($v.ToLowerInvariant() -replace '[^a-z0-9]+', '')
}

function Convert-TagToDisplayVersion {
    param([Parameter(Mandatory = $true)][string]$Tag)

    $v = Normalize-ReleaseVersion $Tag
    $v = $v -replace '(?i)[\-_]?beta[\-_.]?(\d+)', ' Beta $1'
    $v = $v -replace '(?i)[\-_]?alpha[\-_.]?(\d+)', ' Alpha $1'
    $v = $v -replace '(?i)[\-_]?rc[\-_.]?(\d+)', ' RC $1'
    $v = $v -replace '[-_]+', ' '
    return ($v -replace '\s+', ' ').Trim()
}

function Get-RepoVersionText {
    $versionPath = Join-Path $RepoRoot "VERSION"
    if (-not (Test-Path -LiteralPath $versionPath)) { return "" }

    $line = Get-Content -LiteralPath $versionPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) { return "" }
    return $line.Trim()
}

function Test-PrereleaseVersion {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return ($Value -match '(?i)(alpha|beta|rc|pre)')
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-ReleaseLog ("> " + $FilePath + " " + ($Arguments -join " "))
    Push-Location $RepoRoot
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $FilePath @Arguments 2>&1
        $exit = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
        foreach ($line in $output) {
            if ($line -ne $null -and "$line" -ne "") { Write-ReleaseLog "$line" }
        }
        if ($exit -ne 0) {
            throw "Command failed with exit code $exit`: $FilePath"
        }
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }
}

function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if ([string]::IsNullOrWhiteSpace($exe)) { $exe = "powershell" }
    Invoke-External $exe (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments)
}

function Quote-ProcessArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '""' }
    $escaped = $Value -replace '\\(?=\\*")', '$0$0'
    $escaped = $escaped -replace '"', '\"'
    if ($escaped -match '[\s"]') { return '"' + $escaped + '"' }
    return $escaped
}

function Start-PowerShellScriptWindow {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $exe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
    if ([string]::IsNullOrWhiteSpace($exe)) { $exe = "powershell" }
    $processArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
    $argumentLine = (($processArgs | ForEach-Object { Quote-ProcessArgument $_ }) -join " ")
    Write-ReleaseLog ("> open " + $ScriptPath + " " + ($Arguments -join " "))
    Start-Process -FilePath $exe -ArgumentList $argumentLine -WorkingDirectory $RepoRoot | Out-Null
}

function Convert-BoxTextToSection {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [AllowNull()][string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $bullets = @()
    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "") { continue }
        if ($trimmed.StartsWith("- ")) {
            $bullets += $trimmed
        } else {
            $bullets += ("- " + $trimmed)
        }
    }
    if ($bullets.Count -eq 0) { return @() }
    return @("### $Title", "") + $bullets + @("")
}

function New-ChangelogBody {
    param(
        [string]$Performance,
        [string]$Bugfixes,
        [string]$Changes,
        [string]$Tooling,
        [string]$Docs
    )

    $body = @()
    $body += Convert-BoxTextToSection "Performance" $Performance
    $body += Convert-BoxTextToSection "Bugfixes" $Bugfixes
    $body += Convert-BoxTextToSection "Changes / Improvements" $Changes
    $body += Convert-BoxTextToSection "Release / Tooling" $Tooling
    $body += Convert-BoxTextToSection "Documentation" $Docs

    if ($body.Count -eq 0) {
        throw "Add at least one changelog line before updating files."
    }
    return $body
}

function Get-ChangelogSections {
    if (-not (Test-Path -LiteralPath $ChangelogPath)) {
        throw "CHANGELOG.md not found: $ChangelogPath"
    }

    $lines = [regex]::Split((Get-Content -LiteralPath $ChangelogPath -Raw), "\r?\n")
    $sections = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+(.+?)(?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$') {
            $version = $Matches[1].Trim()
            $date = if ($Matches.ContainsKey(2) -and -not [string]::IsNullOrWhiteSpace($Matches[2])) { $Matches[2].Trim() } else { "" }
            $start = $i
            $end = $lines.Count
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match '^##\s+') {
                    $end = $j
                    break
                }
            }

            $sectionLines = if ($end -gt $start) { $lines[$start..($end - 1)] } else { @($lines[$start]) }
            $sections += [pscustomobject]@{
                Version = $version
                Date = $date
                Start = $start
                End = $end
                Lines = [string[]]$sectionLines
                Markdown = (($sectionLines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
            }
        }
    }
    return [object[]]$sections
}

function Find-ChangelogSection {
    param(
        [AllowNull()][string]$ReleaseTag,
        [AllowNull()][string]$DisplayVersion
    )

    $sections = Get-ChangelogSections
    if ($sections.Count -eq 0) { throw "No release sections found in CHANGELOG.md." }

    $tagKey = Normalize-VersionKey $ReleaseTag
    $displayKey = Normalize-VersionKey $DisplayVersion
    foreach ($section in $sections) {
        $key = Normalize-VersionKey $section.Version
        if (($tagKey -ne "" -and $key -eq $tagKey) -or ($displayKey -ne "" -and $key -eq $displayKey)) {
            return $section
        }
    }

    return $sections[0]
}

function Convert-MarkdownSectionToReleaseInput {
    param([Parameter(Mandatory = $true)][string]$Markdown)

    $lines = [regex]::Split($Markdown.Trim(), "\r?\n")
    if ($lines.Count -eq 0) { throw "Markdown changelog text is empty." }

    $display = $null
    $date = $null
    $bodyStart = 0
    if ($lines[0] -match '^##\s+(.+?)(?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$') {
        $display = $Matches[1].Trim()
        $date = if ($Matches.ContainsKey(2) -and -not [string]::IsNullOrWhiteSpace($Matches[2])) { $Matches[2].Trim() } else { $null }
        $bodyStart = 1
    }

    while ($bodyStart -lt $lines.Count -and $lines[$bodyStart].Trim() -eq "") {
        $bodyStart++
    }

    $body = if ($bodyStart -lt $lines.Count) { [string[]]$lines[$bodyStart..($lines.Count - 1)] } else { @() }
    while ($body.Count -gt 0 -and $body[$body.Count - 1].Trim() -eq "") {
        if ($body.Count -eq 1) { $body = @(); break }
        $body = [string[]]$body[0..($body.Count - 2)]
    }

    if ($body.Count -eq 0) { throw "Markdown changelog text has no section body." }
    return [pscustomobject]@{
        Display = $display
        Date = $date
        Body = [string[]]$body
    }
}

function Convert-ChangelogBodyToFieldMap {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$BodyLines)

    $map = @{
        Performance = New-Object System.Collections.Generic.List[string]
        Bugfixes = New-Object System.Collections.Generic.List[string]
        Changes = New-Object System.Collections.Generic.List[string]
        Tooling = New-Object System.Collections.Generic.List[string]
        Docs = New-Object System.Collections.Generic.List[string]
    }

    $current = "Changes"
    $lastList = $map[$current]
    for ($i = 0; $i -lt $BodyLines.Count; $i++) {
        $line = $BodyLines[$i]
        if ($line -match '^###\s+(.+?)\s*$') {
            $title = $Matches[1].Trim()
            if ($title -match '(?i)performance|perf') {
                $current = "Performance"
            } elseif ($title -match '(?i)bug|fix') {
                $current = "Bugfixes"
            } elseif ($title -match '(?i)release|tool|workflow|package|publish') {
                $current = "Tooling"
            } elseif ($title -match '(?i)doc') {
                $current = "Docs"
            } else {
                $current = "Changes"
            }
            $lastList = $map[$current]
            continue
        }

        if ($line -match '^\s*-\s+(.+?)\s*$') {
            $lastList = $map[$current]
            $lastList.Add($Matches[1].Trim())
            continue
        }

        if ($lastList.Count -gt 0 -and $line -match '^\s{2,}(.+?)\s*$') {
            $lastList[$lastList.Count - 1] = ($lastList[$lastList.Count - 1] + " " + $Matches[1].Trim()).Trim()
        }
    }

    return $map
}

function Get-DefaultGitBaseRef {
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

function Get-ChangeArea {
    param([AllowNull()][string]$Path)

    $p = ($Path -replace '\\', '/')
    if ([string]::IsNullOrWhiteSpace($p)) { return "General" }
    if ($p -match '^\.github/|^tools/|^docs/|^CHANGELOG\.md$|MSUF_Changelog\.lua$') { return "Release / Tooling" }
    if ($p -match 'MSUF_ReleaseHelper|update-addon-changelog|package-release|publish-') { return "Release / Tooling" }
    if ($p -match 'MidnightSimpleUnitFrames\.toc$|\.pkgmeta$') { return "Addon Metadata" }
    if ($p -match '/Menu2/') { return "Menu / Dashboard" }
    if ($p -match '/Auras2/') { return "Unit Auras" }
    if ($p -match '/GroupFrames/') { return "Group Frames" }
    if ($p -match '/Modules/MSUF_InterruptReady\.lua$') { return "Interrupt Ready" }
    if ($p -match '/MidnightSimpleUnitFrames\.lua$') { return "Core Runtime" }
    if ($p -match '/Core/MSUF_Text\.lua$') { return "Unit Text" }
    if ($p -match '/Core/MSUF_Borders\.lua$') { return "Borders / Outlines" }
    if ($p -match '/Core/MSUF_Bars\.lua$') { return "Bars / Power Bars" }
    if ($p -match '/Core/') { return "Core Runtime" }
    if ($p -match '/Foundation/') { return "Foundation" }
    if ($p -match '/Features/') { return "Features" }
    return "General"
}

function Get-CommitCategory {
    param(
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    $subjectText = $Subject.ToLowerInvariant()
    $pathText = (($Paths | ForEach-Object { $_.ToLowerInvariant() }) -join " ")
    if ($pathText -match '(^| )docs/|release_helper|releasehelper|update-addon-changelog|package-release|publish-|\.github|changelog|msuf_changelog|\.toc') {
        return "Release / Tooling"
    }
    if ($subjectText -match 'doc|readme|workflow doc') {
        return "Documentation"
    }
    if ($subjectText -match 'perf|performance|optim|cache|hot path|fast|less work') {
        return "Performance"
    }
    if ($subjectText -match 'fix|fixed|bug|crash|taint|error|broken') {
        return "Bugfixes"
    }
    return "Changes / Improvements"
}

function Convert-CommitSubjectToText {
    param([AllowNull()][string]$Subject)

    $text = if ($null -eq $Subject) { "" } else { $Subject.Trim() }
    if ($text -eq "") { return "Updated addon behavior" }
    $text = $text -replace '\s+', ' '
    if ($text.Length -gt 0) {
        $text = $text.Substring(0, 1).ToUpperInvariant() + $text.Substring(1)
    }
    return $text
}

function Get-GitCommitsForChangelog {
    param(
        [AllowNull()][string]$BaseRef,
        [int]$SinceHours = 0
    )

    Push-Location $RepoRoot
    try {
        if ($SinceHours -lt 0 -or $SinceHours -gt 100) { throw "Since hours must be 0 or between 1 and 100." }
        $range = if ($SinceHours -gt 0) { "HEAD --since=$SinceHours hours" } elseif ([string]::IsNullOrWhiteSpace($BaseRef)) { "HEAD" } else { "$BaseRef..HEAD" }
        $commitLines = if ($SinceHours -gt 0) {
            & git log --reverse --format="%H`t%h`t%s" "--since=$SinceHours hours ago" HEAD 2>&1
        } else {
            & git log --reverse --format="%H`t%h`t%s" $range 2>&1
        }
        if ($LASTEXITCODE -ne 0) {
            throw "git log failed for range '$range': $($commitLines -join ' ')"
        }

        $commits = @()
        foreach ($line in $commitLines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t", 3
            if ($parts.Count -lt 3) { continue }
            $hash = $parts[0]
            $short = $parts[1]
            $subject = $parts[2]

            $nameStatus = & git show --format= --name-status $hash 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git show failed for $short`: $($nameStatus -join ' ')"
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

            $paths = @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            $areas = @($paths | ForEach-Object { Get-ChangeArea $_ } | Select-Object -Unique)
            if ($areas.Count -eq 0) { $areas = @("General") }
            $category = Get-CommitCategory -Subject $subject -Paths $paths

            $commits += [pscustomobject]@{
                Hash = $hash
                ShortHash = $short
                Subject = $subject
                Text = Convert-CommitSubjectToText $subject
                Paths = [string[]]$paths
                Areas = [string[]]$areas
                Category = $category
            }
        }

        return [object[]]$commits
    } finally {
        Pop-Location
    }
}

function New-GitCommitChangelogMarkdown {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$DisplayVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseDate,
        [AllowNull()][string]$BaseRef,
        [int]$SinceHours = 0
    )

    $commits = @(Get-GitCommitsForChangelog -BaseRef $BaseRef -SinceHours $SinceHours)
    if ($commits.Count -eq 0) {
        $rangeText = if ($SinceHours -gt 0) { "the last $SinceHours hours" } else { "$BaseRef..HEAD" }
        throw "No commits found for changelog range '$rangeText'."
    }

    $groups = [ordered]@{
        "Performance" = New-Object System.Collections.Generic.List[string]
        "Bugfixes" = New-Object System.Collections.Generic.List[string]
        "Changes / Improvements" = New-Object System.Collections.Generic.List[string]
        "Release / Tooling" = New-Object System.Collections.Generic.List[string]
        "Documentation" = New-Object System.Collections.Generic.List[string]
    }

    foreach ($commit in $commits) {
        $areas = @($commit.Areas)
        $paths = @($commit.Paths)
        $scope = (($areas | Select-Object -First 3) -join ", ")
        if ([string]::IsNullOrWhiteSpace($scope)) { $scope = "General" }

        $pathText = ""
        if ($paths.Count -gt 0) {
            $shown = @($paths | Select-Object -First 3)
            $pathText = "; " + (($shown | ForEach-Object { $_ -replace '^MidnightSimpleUnitFrames/', '' }) -join ", ")
            if ($paths.Count -gt 3) { $pathText += (" +" + ($paths.Count - 3) + " more") }
        }

        $bullet = "{0}: {1} ({2}{3})." -f $scope, $commit.Text, $commit.ShortHash, $pathText
        if (-not $groups.Contains($commit.Category)) {
            $groups["Changes / Improvements"].Add($bullet)
        } else {
            $groups[$commit.Category].Add($bullet)
        }
    }

    $lines = @("## $DisplayVersion - $ReleaseDate", "")
    foreach ($title in $groups.Keys) {
        $items = $groups[$title]
        if ($items.Count -eq 0) { continue }
        $lines += "### $title"
        $lines += ""
        foreach ($item in $items) {
            $lines += "- $item"
        }
        $lines += ""
    }

    return (($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine)
}

function Update-ChangelogFile {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$DisplayVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseDate,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$BodyLines
    )

    if (-not (Test-Path -LiteralPath $ChangelogPath)) {
        throw "CHANGELOG.md not found: $ChangelogPath"
    }

    $content = Get-Content -LiteralPath $ChangelogPath -Raw
    $newline = if ($content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = [regex]::Split($content, "\r?\n")
    $tagKey = Normalize-VersionKey $ReleaseTag
    $displayKey = Normalize-VersionKey $DisplayVersion

    $newSection = @("## $DisplayVersion - $ReleaseDate", "") + $BodyLines + @("")
    $start = -1
    $end = $lines.Count

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s+(.+?)(?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$') {
            $key = Normalize-VersionKey $Matches[1]
            if ($key -eq $tagKey -or $key -eq $displayKey) {
                $start = $i
                for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                    if ($lines[$j] -match '^##\s+') {
                        $end = $j
                        break
                    }
                }
                break
            }
        }
    }

    if ($start -ge 0) {
        $before = if ($start -gt 0) { $lines[0..($start - 1)] } else { @() }
        $after = if ($end -lt $lines.Count) { $lines[$end..($lines.Count - 1)] } else { @() }
        $updated = @($before) + $newSection + @($after)
        Write-ReleaseLog "Replaced existing CHANGELOG.md section for $DisplayVersion."
    } else {
        $titleIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^#\s+Changelog\s*$') {
                $titleIndex = $i
                break
            }
        }
        if ($titleIndex -lt 0) { throw "CHANGELOG.md does not contain '# Changelog'." }

        $restStart = $titleIndex + 1
        while ($restStart -lt $lines.Count -and $lines[$restStart].Trim() -eq "") { $restStart++ }

        $before = $lines[0..$titleIndex] + @("")
        $after = if ($restStart -lt $lines.Count) { $lines[$restStart..($lines.Count - 1)] } else { @() }
        $updated = @($before) + $newSection + @($after)
        Write-ReleaseLog "Inserted new CHANGELOG.md section for $DisplayVersion."
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($ChangelogPath, (($updated -join $newline).TrimEnd() + $newline), $utf8NoBom)
}

function Update-AddonChangelog {
    param([Parameter(Mandatory = $true)][string]$ReleaseTag)

    if (-not (Test-Path -LiteralPath $AddonChangelogScript)) {
        throw "Missing addon changelog generator: $AddonChangelogScript"
    }
    Invoke-PowerShellScript $AddonChangelogScript @("-Version", $ReleaseTag)
}

function Build-ReleaseZip {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$OutputDir
    )

    if (-not (Test-Path -LiteralPath $PackageScript)) {
        throw "Missing package script: $PackageScript"
    }
    Invoke-PowerShellScript $PackageScript @("-Version", $ReleaseTag, "-OutputDir", $OutputDir)
}

function Test-GitCleanEnough {
    $status = @(git status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "git status failed. Is this a git repository?" }
    return [string[]]$status
}

function Get-GitCurrentBranch {
    Push-Location $RepoRoot
    try {
        $branch = (& git symbolic-ref --quiet --short HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
            return $branch.Trim()
        }
    } finally {
        Pop-Location
    }

    return ""
}

function Get-GitHubReleaseBranches {
    Push-Location $RepoRoot
    try {
        $lines = & git ls-remote --heads origin 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Could not scan origin branches: $($lines -join ' ')"
        }

        $branches = @()
        foreach ($line in $lines) {
            if ($line -match 'refs/heads/(.+?)\s*$') {
                $branches += $Matches[1].Trim()
            }
        }

        return [string[]]@($branches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    } finally {
        Pop-Location
    }
}

function Assert-ReleaseBranch {
    param([AllowNull()][string]$ReleaseBranch)

    if ([string]::IsNullOrWhiteSpace($ReleaseBranch)) {
        throw "Select the GitHub branch that should be released."
    }

    $current = Get-GitCurrentBranch
    if ([string]::IsNullOrWhiteSpace($current)) {
        throw "Current checkout is detached. Checkout '$ReleaseBranch' before publishing."
    }

    if ($current -ne $ReleaseBranch) {
        throw "Selected release branch is '$ReleaseBranch', but the current checkout is '$current'. Checkout '$ReleaseBranch' before publishing."
    }
}

function Commit-AllChanges {
    param([Parameter(Mandatory = $true)][string]$ReleaseTag)

    Invoke-External "git" @("add", "-A")
    $status = @(Test-GitCleanEnough)
    if ($status.Count -eq 0) {
        Write-ReleaseLog "No staged changes to commit."
        return
    }
    Invoke-External "git" @("commit", "-m", "Release $ReleaseTag")
}

function Create-ReleaseTag {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$ReleaseName
    )

    & git rev-parse -q --verify "refs/tags/$ReleaseTag" *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-ReleaseLog "Git tag already exists locally: $ReleaseTag"
        return
    }
    Invoke-External "git" @("tag", "-a", $ReleaseTag, "-m", $ReleaseName)
}

function Push-ReleaseTag {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$ReleaseBranch
    )

    Assert-ReleaseBranch -ReleaseBranch $ReleaseBranch
    Invoke-External "git" @("push", "origin", ("HEAD:refs/heads/" + $ReleaseBranch))
    Invoke-External "git" @("push", "origin", $ReleaseTag)
}

function Start-GitHubWorkflow {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][bool]$Prerelease,
        [AllowNull()][string]$ReleaseBranch,
        [AllowNull()][string]$ReleaseName
    )

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-ReleaseLog "GitHub CLI (gh) is not installed or not in PATH; manual workflow dispatch skipped."
        return
    }

    Invoke-External "gh" @("auth", "status")
    $args = @("workflow", "run", "release.yml")
    if (-not [string]::IsNullOrWhiteSpace($ReleaseBranch)) {
        $args += @("--ref", $ReleaseBranch)
    }
    $args += @("-f", "tag_name=$ReleaseTag", "-f", ("prerelease=" + $Prerelease.ToString().ToLowerInvariant()))
    if (-not [string]::IsNullOrWhiteSpace($ReleaseName)) {
        $args += @("-f", "release_name=$ReleaseName")
    }
    Invoke-External "gh" $args
    Write-ReleaseLog "GitHub release workflow queued for $ReleaseTag."
}

function Start-LocalPreparation {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$DisplayVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseDate,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$BodyLines,
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [bool]$BuildZip = $true
    )

    Update-ChangelogFile -ReleaseTag $ReleaseTag -DisplayVersion $DisplayVersion -ReleaseDate $ReleaseDate -BodyLines $BodyLines
    Update-AddonChangelog -ReleaseTag $ReleaseTag
    if ($BuildZip) {
        Build-ReleaseZip -ReleaseTag $ReleaseTag -OutputDir $OutputDir
    }
}

function Update-AutoChangelogFromRepo {
    param(
        [Parameter(Mandatory = $true)][string]$DisplayVersion,
        [AllowNull()][string]$BaseRef,
        [int]$SinceHours = 0,
        [AllowNull()][string]$ReleaseDate,
        [bool]$CreateMissingRelease = $true,
        [bool]$KeepExistingAutoEntries = $false,
        [bool]$IncludePrereleaseAutoEntries = $false,
        [bool]$ReleaseLineScan = $false,
        [bool]$FilterJunk = $true
    )

    if (-not (Test-Path -LiteralPath $AutoChangelogScript)) {
        throw "Missing auto changelog tool: $AutoChangelogScript"
    }

    $args = @("-DisplayVersion", $DisplayVersion, "-RegenerateAddonChangelog")
    if (-not [string]::IsNullOrWhiteSpace($ReleaseDate)) {
        $args += @("-ReleaseDate", $ReleaseDate)
    }
    if ($CreateMissingRelease) {
        $args += "-CreateMissingRelease"
    }
    if ($KeepExistingAutoEntries) {
        $args += "-KeepExistingAutoEntries"
    }
    if ($SinceHours -lt 0 -or $SinceHours -gt 100) {
        throw "Since hours must be 0 or between 1 and 100."
    }
    if ($SinceHours -gt 0) {
        $args += @("-SinceHours", "$SinceHours")
    }
    if ($IncludePrereleaseAutoEntries) {
        $args += "-IncludePrereleaseAutoEntries"
    }
    if ($ReleaseLineScan) {
        $args += "-ReleaseLineScan"
    }
    if (-not $FilterJunk) {
        $args += "-NoJunkFilter"
    }
    if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
        $args += @("-BaseRef", $BaseRef)
    }

    Invoke-PowerShellScript $AutoChangelogScript $args
}

if ($NoGui) {
    Write-ReleaseLog "NoGui mode is only a syntax/load check for this helper."
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:LogBox = $null

$form = New-Object System.Windows.Forms.Form
$form.Text = "MSUF Release Helper"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1140, 980)
$form.MinimumSize = New-Object System.Drawing.Size(1120, 900)

$defaultTag = Get-RepoVersionText
if ([string]::IsNullOrWhiteSpace($defaultTag)) { $defaultTag = "5.1-beta4" }
$defaultDisplay = Convert-TagToDisplayVersion $defaultTag
$defaultReleaseName = "MSUF $defaultDisplay"
$defaultBranch = Get-GitCurrentBranch

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 120)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, 20)
    $form.Controls.Add($label)
    return $label
}

function New-TextBox {
    param([int]$X, [int]$Y, [int]$W, [string]$Text = "")
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($X, $Y)
    $box.Size = New-Object System.Drawing.Size($W, 22)
    $box.Text = $Text
    $form.Controls.Add($box)
    return $box
}

function New-TextArea {
    param([string]$Title, [int]$X, [int]$Y, [int]$W, [int]$H)
    New-Label $Title $X $Y 180 | Out-Null
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($X, ($Y + 20))
    $box.Size = New-Object System.Drawing.Size($W, $H)
    $box.Multiline = $true
    $box.ScrollBars = "Vertical"
    $box.AcceptsReturn = $true
    $box.AcceptsTab = $true
    $form.Controls.Add($box)
    return $box
}

New-Label "Version / tag" 16 16 | Out-Null
$tagBox = New-TextBox 130 14 165 $defaultTag
$versionButton = New-Object System.Windows.Forms.Button
$versionButton.Text = "VERSION"
$versionButton.Location = New-Object System.Drawing.Point(305, 12)
$versionButton.Size = New-Object System.Drawing.Size(76, 26)
$form.Controls.Add($versionButton)

New-Label "Changelog title" 395 16 90 | Out-Null
$displayBox = New-TextBox 495 14 190 $defaultDisplay
New-Label "Date" 700 16 40 | Out-Null
$dateBox = New-TextBox 745 14 90 (Get-Date -Format "yyyy-MM-dd")

$preBox = New-Object System.Windows.Forms.CheckBox
$preBox.Text = "Prerelease / beta"
$preBox.Checked = Test-PrereleaseVersion $defaultTag
$preBox.Location = New-Object System.Drawing.Point(16, 868)
$preBox.Size = New-Object System.Drawing.Size(160, 24)
$preBox.Visible = $false
$form.Controls.Add($preBox)

$releaseTypeGroup = New-Object System.Windows.Forms.GroupBox
$releaseTypeGroup.Text = "Release type"
$releaseTypeGroup.Location = New-Object System.Drawing.Point(950, 6)
$releaseTypeGroup.Size = New-Object System.Drawing.Size(166, 66)
$form.Controls.Add($releaseTypeGroup)

$fullReleaseRadio = New-Object System.Windows.Forms.RadioButton
$fullReleaseRadio.Text = "Full release"
$fullReleaseRadio.Location = New-Object System.Drawing.Point(10, 18)
$fullReleaseRadio.Size = New-Object System.Drawing.Size(130, 20)
$releaseTypeGroup.Controls.Add($fullReleaseRadio)

$preReleaseRadio = New-Object System.Windows.Forms.RadioButton
$preReleaseRadio.Text = "Beta / prerelease"
$preReleaseRadio.Location = New-Object System.Drawing.Point(10, 40)
$preReleaseRadio.Size = New-Object System.Drawing.Size(145, 20)
$releaseTypeGroup.Controls.Add($preReleaseRadio)

if ($preBox.Checked) {
    $preReleaseRadio.Checked = $true
} else {
    $fullReleaseRadio.Checked = $true
}

New-Label "Release name" 16 48 | Out-Null
$releaseNameBox = New-TextBox 130 46 220 $defaultReleaseName

New-Label "Output dir" 370 48 70 | Out-Null
$outBox = New-TextBox 445 46 100 "dist"

$advancedGroup = New-Object System.Windows.Forms.GroupBox
$advancedGroup.Text = "Advanced publish actions"
$advancedGroup.Location = New-Object System.Drawing.Point(16, 104)
$advancedGroup.Size = New-Object System.Drawing.Size(1100, 44)
$advancedGroup.Visible = $false
$form.Controls.Add($advancedGroup)

$buildBox = New-Object System.Windows.Forms.CheckBox
$buildBox.Text = "Build local zip"
$buildBox.Checked = $true
$buildBox.Location = New-Object System.Drawing.Point(14, 17)
$buildBox.Size = New-Object System.Drawing.Size(115, 22)
$advancedGroup.Controls.Add($buildBox)

$commitBox = New-Object System.Windows.Forms.CheckBox
$commitBox.Text = "Commit all changes"
$commitBox.Checked = $true
$commitBox.Location = New-Object System.Drawing.Point(150, 17)
$commitBox.Size = New-Object System.Drawing.Size(145, 22)
$advancedGroup.Controls.Add($commitBox)

$tagCreateBox = New-Object System.Windows.Forms.CheckBox
$tagCreateBox.Text = "Create tag"
$tagCreateBox.Checked = $true
$tagCreateBox.Location = New-Object System.Drawing.Point(315, 17)
$tagCreateBox.Size = New-Object System.Drawing.Size(95, 22)
$advancedGroup.Controls.Add($tagCreateBox)

$pushBox = New-Object System.Windows.Forms.CheckBox
$pushBox.Text = "Push"
$pushBox.Checked = $true
$pushBox.Location = New-Object System.Drawing.Point(430, 17)
$pushBox.Size = New-Object System.Drawing.Size(70, 22)
$advancedGroup.Controls.Add($pushBox)

$workflowBox = New-Object System.Windows.Forms.CheckBox
$workflowBox.Text = "Run GitHub workflow"
$workflowBox.Checked = $true
$workflowBox.Location = New-Object System.Drawing.Point(520, 17)
$workflowBox.Size = New-Object System.Drawing.Size(165, 22)
$advancedGroup.Controls.Add($workflowBox)

$advancedButton = New-Object System.Windows.Forms.Button
$advancedButton.Text = "Advanced actions"
$advancedButton.Location = New-Object System.Drawing.Point(555, 44)
$advancedButton.Size = New-Object System.Drawing.Size(130, 28)
$form.Controls.Add($advancedButton)

$flowLabel = New-Object System.Windows.Forms.Label
$flowLabel.Text = "Flow: 1 Auto Changelog, 2 Build ZIP, 3 Publish."
$flowLabel.Location = New-Object System.Drawing.Point(695, 49)
$flowLabel.Size = New-Object System.Drawing.Size(250, 20)
$form.Controls.Add($flowLabel)

$script:AdvancedActionsVisible = $false
function Set-AdvancedActionVisibility {
    param([bool]$Visible)

    $script:AdvancedActionsVisible = $Visible
    $advancedGroup.Visible = $Visible
    $flowLabel.Visible = -not $Visible
    $advancedButton.Text = if ($Visible) { "Hide advanced" } else { "Advanced actions" }
}

$advancedButton.Add_Click({
    Set-AdvancedActionVisibility (-not $script:AdvancedActionsVisible)
})

$fullReleaseRadio.Add_CheckedChanged({
    if ($fullReleaseRadio.Checked) { $preBox.Checked = $false }
})

$preReleaseRadio.Add_CheckedChanged({
    if ($preReleaseRadio.Checked) { $preBox.Checked = $true }
})

$versionButton.Add_Click({
    try {
        $version = Get-RepoVersionText
        if ([string]::IsNullOrWhiteSpace($version)) { throw "VERSION file is missing or empty." }
        $tagBox.Text = $version
        $displayBox.Text = Convert-TagToDisplayVersion $version
        $releaseNameBox.Text = "MSUF " + $displayBox.Text
        if (Test-PrereleaseVersion $version) {
            $preReleaseRadio.Checked = $true
        } else {
            $fullReleaseRadio.Checked = $true
        }
        Write-ReleaseLog ("Release data loaded from VERSION: " + $version)
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})

$tagBox.Add_Leave({
    try {
        if ([string]::IsNullOrWhiteSpace($displayBox.Text)) {
            $displayBox.Text = Convert-TagToDisplayVersion $tagBox.Text
        }
        if ([string]::IsNullOrWhiteSpace($releaseNameBox.Text)) {
            $releaseNameBox.Text = "MSUF " + $displayBox.Text.Trim()
        }
        if (Test-PrereleaseVersion $tagBox.Text) {
            $preReleaseRadio.Checked = $true
        } else {
            $fullReleaseRadio.Checked = $true
        }
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
    }
})

$displayBox.Add_Leave({
    if ([string]::IsNullOrWhiteSpace($releaseNameBox.Text) -and -not [string]::IsNullOrWhiteSpace($displayBox.Text)) {
        $releaseNameBox.Text = "MSUF " + $displayBox.Text.Trim()
    }
})

New-Label "Since ref" 16 76 | Out-Null
$baseRefBox = New-TextBox 130 74 220 (Get-DefaultGitBaseRef)
$lastTagButton = New-Object System.Windows.Forms.Button
$lastTagButton.Text = "Last tag"
$lastTagButton.Location = New-Object System.Drawing.Point(360, 72)
$lastTagButton.Size = New-Object System.Drawing.Size(90, 26)
$lastTagButton.Add_Click({
    try {
        $baseRefBox.Text = Get-DefaultGitBaseRef
        Write-ReleaseLog ("Since ref set to " + $baseRefBox.Text)
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
    }
})
$form.Controls.Add($lastTagButton)

New-Label "Since hours" 16 102 | Out-Null
$sinceHoursBox = New-Object System.Windows.Forms.NumericUpDown
$sinceHoursBox.Location = New-Object System.Drawing.Point(130, 100)
$sinceHoursBox.Size = New-Object System.Drawing.Size(70, 22)
$sinceHoursBox.Minimum = 0
$sinceHoursBox.Maximum = 100
$sinceHoursBox.Value = 0
$form.Controls.Add($sinceHoursBox)

$sinceHoursHint = New-Object System.Windows.Forms.Label
$sinceHoursHint.Text = "0 = Since ref"
$sinceHoursHint.Location = New-Object System.Drawing.Point(210, 102)
$sinceHoursHint.Size = New-Object System.Drawing.Size(120, 20)
$form.Controls.Add($sinceHoursHint)

$keepAutoBox = New-Object System.Windows.Forms.CheckBox
$keepAutoBox.Text = "Keep old auto entries"
$keepAutoBox.Checked = $false
$keepAutoBox.Location = New-Object System.Drawing.Point(465, 74)
$keepAutoBox.Size = New-Object System.Drawing.Size(165, 24)
$form.Controls.Add($keepAutoBox)

$includePrereleaseBox = New-Object System.Windows.Forms.CheckBox
$includePrereleaseBox.Text = "Include prerelease logs"
$includePrereleaseBox.Checked = $false
$includePrereleaseBox.Location = New-Object System.Drawing.Point(465, 98)
$includePrereleaseBox.Size = New-Object System.Drawing.Size(170, 24)
$form.Controls.Add($includePrereleaseBox)

$releaseLineBox = New-Object System.Windows.Forms.CheckBox
$releaseLineBox.Text = "Release line scan"
$releaseLineBox.Checked = $true
$releaseLineBox.Location = New-Object System.Drawing.Point(465, 122)
$releaseLineBox.Size = New-Object System.Drawing.Size(170, 24)
$form.Controls.Add($releaseLineBox)

$junkFilterBox = New-Object System.Windows.Forms.CheckBox
$junkFilterBox.Text = "Filter junk"
$junkFilterBox.Checked = $true
$junkFilterBox.Location = New-Object System.Drawing.Point(585, 122)
$junkFilterBox.Size = New-Object System.Drawing.Size(120, 20)
$form.Controls.Add($junkFilterBox)

New-Label "Release branch" 645 76 95 | Out-Null
$branchBox = New-Object System.Windows.Forms.ComboBox
$branchBox.Location = New-Object System.Drawing.Point(745, 74)
$branchBox.Size = New-Object System.Drawing.Size(235, 22)
$branchBox.DropDownStyle = "DropDown"
$branchBox.Text = $defaultBranch
$form.Controls.Add($branchBox)

$scanBranchesButton = New-Object System.Windows.Forms.Button
$scanBranchesButton.Text = "Scan"
$scanBranchesButton.Location = New-Object System.Drawing.Point(990, 72)
$scanBranchesButton.Size = New-Object System.Drawing.Size(126, 26)
$scanBranchesButton.Add_Click({
    try {
        $branches = @(Get-GitHubReleaseBranches)
        $branchBox.Items.Clear()
        foreach ($branch in $branches) {
            [void]$branchBox.Items.Add($branch)
        }
        if (-not [string]::IsNullOrWhiteSpace($defaultBranch) -and $branches -contains $defaultBranch) {
            $branchBox.Text = $defaultBranch
        } elseif ($branches.Count -gt 0 -and [string]::IsNullOrWhiteSpace($branchBox.Text)) {
            $branchBox.Text = $branches[0]
        }
        Write-ReleaseLog ("Scanned origin branches: " + $branches.Count)
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($scanBranchesButton)

$sinceHoursBox.Add_ValueChanged({
    if ([int]$sinceHoursBox.Value -gt 0 -and $releaseLineBox.Checked) {
        $releaseLineBox.Checked = $false
        Write-ReleaseLog "Since hours selected; Release line scan disabled."
    }
})

$releaseLineBox.Add_CheckedChanged({
    if ($releaseLineBox.Checked -and [int]$sinceHoursBox.Value -gt 0) {
        $sinceHoursBox.Value = 0
        Write-ReleaseLog "Release line scan enabled; Since hours reset to 0."
    }
})

$perfBox = New-TextArea "Performance (one bullet per line)" 16 156 530 86
$bugBox = New-TextArea "Bugfixes (one bullet per line)" 586 156 530 86
$changeBox = New-TextArea "Changes / Improvements" 16 272 530 72
$toolBox = New-TextArea "Release / Tooling" 586 272 530 72
$docBox = New-TextArea "Documentation" 16 374 1100 54
$mdBox = New-TextArea "Markdown changelog from repo" 16 462 1100 92

$autoSourceBox = New-Object System.Windows.Forms.CheckBox
$autoSourceBox.Text = "Auto Changelog before Build/Publish"
$autoSourceBox.Checked = $true
$autoSourceBox.Location = New-Object System.Drawing.Point(590, 462)
$autoSourceBox.Size = New-Object System.Drawing.Size(260, 22)
$form.Controls.Add($autoSourceBox)

$useMarkdownBox = New-Object System.Windows.Forms.CheckBox
$useMarkdownBox.Text = "Use shown notes as release source"
$useMarkdownBox.Checked = $true
$useMarkdownBox.Location = New-Object System.Drawing.Point(850, 462)
$useMarkdownBox.Size = New-Object System.Drawing.Size(260, 22)
$form.Controls.Add($useMarkdownBox)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(16, 704)
$script:LogBox.Size = New-Object System.Drawing.Size(1100, 218)
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$form.Controls.Add($script:LogBox)

function Convert-StringListToText {
    param($List)
    if (-not $List -or $List.Count -eq 0) { return "" }
    return (($List | ForEach-Object { "$_" }) -join [Environment]::NewLine)
}

function Set-UiFromMarkdown {
    param([Parameter(Mandatory = $true)][string]$Markdown)

    $parsed = Convert-MarkdownSectionToReleaseInput -Markdown $Markdown
    if (-not [string]::IsNullOrWhiteSpace($parsed.Display)) { $displayBox.Text = $parsed.Display }
    if (-not [string]::IsNullOrWhiteSpace($parsed.Date)) { $dateBox.Text = $parsed.Date }

    $map = Convert-ChangelogBodyToFieldMap -BodyLines $parsed.Body
    $perfBox.Text = Convert-StringListToText $map.Performance
    $bugBox.Text = Convert-StringListToText $map.Bugfixes
    $changeBox.Text = Convert-StringListToText $map.Changes
    $toolBox.Text = Convert-StringListToText $map.Tooling
    $docBox.Text = Convert-StringListToText $map.Docs
    return $parsed
}

function Read-UiReleaseMetadata {
    $tag = Normalize-ReleaseVersion $tagBox.Text
    $display = $displayBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($display)) { $display = Convert-TagToDisplayVersion $tag }
    $isPrereleaseTag = Test-PrereleaseVersion $tag
    if ($preBox.Checked -and -not $isPrereleaseTag) {
        throw "Beta / prerelease publishing needs a prerelease tag such as 5.2-beta1, 5.2-alpha1, or 5.2-rc1."
    }
    if (-not $preBox.Checked -and $isPrereleaseTag) {
        throw "Full release publishing needs a stable tag without alpha, beta, rc, or pre in the name."
    }
    $date = $dateBox.Text.Trim()
    if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date must be YYYY-MM-DD." }
    $releaseName = $releaseNameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($releaseName)) { $releaseName = "MSUF $display" }
    if ($releaseName -match ':') { throw "Release name cannot contain ':' because CurseForge packager uses ':' as a separator." }
    $output = $outBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($output)) { $output = "dist" }
    $branch = $branchBox.Text.Trim()

    return [pscustomobject]@{
        Tag = $tag
        Display = $display
        Date = $date
        ReleaseName = $releaseName
        OutputDir = $output
        Branch = $branch
        Prerelease = $preBox.Checked
    }
}

function Read-UiRelease {
    $meta = Read-UiReleaseMetadata
    $display = $meta.Display
    $date = $meta.Date

    if ($useMarkdownBox.Checked) {
        if ([string]::IsNullOrWhiteSpace($mdBox.Text)) { throw "Markdown changelog text is empty." }
        $parsed = Convert-MarkdownSectionToReleaseInput -Markdown $mdBox.Text
        if (-not [string]::IsNullOrWhiteSpace($parsed.Display)) { $display = $parsed.Display }
        if (-not [string]::IsNullOrWhiteSpace($parsed.Date)) { $date = $parsed.Date }
        $body = $parsed.Body
    } else {
        $body = New-ChangelogBody -Performance $perfBox.Text -Bugfixes $bugBox.Text -Changes $changeBox.Text -Tooling $toolBox.Text -Docs $docBox.Text
    }

    return [pscustomobject]@{
        Tag = $meta.Tag
        Display = $display
        Date = $date
        ReleaseName = $meta.ReleaseName
        OutputDir = $meta.OutputDir
        Branch = $meta.Branch
        Body = $body
        Prerelease = $meta.Prerelease
    }
}

function Sync-AutoChangelogSource {
    param([string]$Reason = "release")

    $meta = Read-UiReleaseMetadata
    $baseRef = $baseRefBox.Text.Trim()
    Update-AutoChangelogFromRepo -DisplayVersion $meta.Display -BaseRef $baseRef -SinceHours ([int]$sinceHoursBox.Value) -ReleaseDate $meta.Date -CreateMissingRelease $true -KeepExistingAutoEntries $keepAutoBox.Checked -IncludePrereleaseAutoEntries $includePrereleaseBox.Checked -ReleaseLineScan $releaseLineBox.Checked -FilterJunk $junkFilterBox.Checked
    $section = Find-ChangelogSection -ReleaseTag $meta.Tag -DisplayVersion $meta.Display
    $mdBox.Text = $section.Markdown
    Set-UiFromMarkdown -Markdown $section.Markdown | Out-Null
    $useMarkdownBox.Checked = $true
    Write-ReleaseLog ("Auto changelog refreshed for " + $Reason + ": " + $section.Version)
}

function Open-AutoChangelogUiFromReleaseHelper {
    $meta = Read-UiReleaseMetadata
    $baseRef = $baseRefBox.Text.Trim()
    $args = @(
        "-Gui",
        "-DisplayVersion", $meta.Display,
        "-BaseRef", $baseRef,
        "-SinceHours", ([string][int]$sinceHoursBox.Value),
        "-ReleaseDate", $meta.Date,
        "-CreateMissingRelease",
        "-RegenerateAddonChangelog"
    )

    if ($keepAutoBox.Checked) { $args += "-KeepExistingAutoEntries" }
    if ($includePrereleaseBox.Checked) { $args += "-IncludePrereleaseAutoEntries" }
    if ($releaseLineBox.Checked) { $args += "-ReleaseLineScan" }
    if (-not $junkFilterBox.Checked) { $args += "-NoJunkFilter" }

    Start-PowerShellScriptWindow -ScriptPath $AutoChangelogScript -Arguments $args
    Write-ReleaseLog ("Opened Auto Changelog UI for " + $meta.Display + ". Use Generate Preview and Write Edited there, then Load Notes here.")
}

$loadRepoButton = New-Object System.Windows.Forms.Button
$loadRepoButton.Text = "Load Notes"
$loadRepoButton.Location = New-Object System.Drawing.Point(16, 590)
$loadRepoButton.Size = New-Object System.Drawing.Size(150, 32)
$loadRepoButton.Add_Click({
    try {
        $section = Find-ChangelogSection -ReleaseTag $tagBox.Text -DisplayVersion $displayBox.Text
        $mdBox.Text = $section.Markdown
        Set-UiFromMarkdown -Markdown $section.Markdown | Out-Null
        $useMarkdownBox.Checked = $true
        Write-ReleaseLog ("Loaded CHANGELOG.md section: " + $section.Version)
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($loadRepoButton)

$loadCommitsButton = New-Object System.Windows.Forms.Button
$loadCommitsButton.Text = "Draft from Git"
$loadCommitsButton.Location = New-Object System.Drawing.Point(176, 590)
$loadCommitsButton.Size = New-Object System.Drawing.Size(150, 32)
$loadCommitsButton.Add_Click({
    try {
        $tag = Normalize-ReleaseVersion $tagBox.Text
        $display = $displayBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($display)) { $display = Convert-TagToDisplayVersion $tag }
        $date = $dateBox.Text.Trim()
        if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date must be YYYY-MM-DD." }
        $baseRef = $baseRefBox.Text.Trim()
        $hours = [int]$sinceHoursBox.Value

        $markdown = New-GitCommitChangelogMarkdown -ReleaseTag $tag -DisplayVersion $display -ReleaseDate $date -BaseRef $baseRef -SinceHours $hours
        $mdBox.Text = $markdown
        Set-UiFromMarkdown -Markdown $markdown | Out-Null
        $useMarkdownBox.Checked = $true
        $rangeText = if ($hours -gt 0) { "last $hours hours" } else { ($(if ($baseRef) { $baseRef } else { "initial history" }) + "..HEAD") }
        Write-ReleaseLog ("Generated changelog draft from git commits: " + $rangeText)
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($loadCommitsButton)

$autoChangelogButton = New-Object System.Windows.Forms.Button
$autoChangelogButton.Text = "1 Generate Changelog"
$autoChangelogButton.Location = New-Object System.Drawing.Point(16, 628)
$autoChangelogButton.Size = New-Object System.Drawing.Size(150, 32)
$autoChangelogButton.Add_Click({
    try {
        Sync-AutoChangelogSource -Reason "manual refresh"
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($autoChangelogButton)

$openAutoChangelogButton = New-Object System.Windows.Forms.Button
$openAutoChangelogButton.Text = "Open Auto UI"
$openAutoChangelogButton.Location = New-Object System.Drawing.Point(176, 628)
$openAutoChangelogButton.Size = New-Object System.Drawing.Size(150, 32)
$openAutoChangelogButton.Add_Click({
    try {
        Open-AutoChangelogUiFromReleaseHelper
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($openAutoChangelogButton)

$fillFieldsButton = New-Object System.Windows.Forms.Button
$fillFieldsButton.Text = "Map Markdown"
$fillFieldsButton.Location = New-Object System.Drawing.Point(336, 590)
$fillFieldsButton.Size = New-Object System.Drawing.Size(135, 32)
$fillFieldsButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($mdBox.Text)) { throw "Markdown changelog text is empty." }
        Set-UiFromMarkdown -Markdown $mdBox.Text | Out-Null
        Write-ReleaseLog "Mapped Markdown text into changelog fields."
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($fillFieldsButton)

$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "Preview Notes"
$previewButton.Location = New-Object System.Drawing.Point(481, 590)
$previewButton.Size = New-Object System.Drawing.Size(135, 32)
$previewButton.Add_Click({
    try {
        $r = Read-UiRelease
        $preview = @("## $($r.Display) - $($r.Date)", "") + $r.Body
        Write-ReleaseLog "----- Changelog preview -----"
        foreach ($line in $preview) { Write-ReleaseLog $line }
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
    }
})
$form.Controls.Add($previewButton)

$prepButton = New-Object System.Windows.Forms.Button
$prepButton.Text = "2 Build ZIP"
$prepButton.Location = New-Object System.Drawing.Point(626, 590)
$prepButton.Size = New-Object System.Drawing.Size(150, 32)
$prepButton.Add_Click({
    try {
        if ($autoSourceBox.Checked) {
            Sync-AutoChangelogSource -Reason "Build ZIP"
        }
        $r = Read-UiRelease
        Start-LocalPreparation -ReleaseTag $r.Tag -DisplayVersion $r.Display -ReleaseDate $r.Date -BodyLines $r.Body -OutputDir $r.OutputDir -BuildZip $buildBox.Checked
        Write-ReleaseLog "Local release preparation complete."
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($prepButton)

$publishButton = New-Object System.Windows.Forms.Button
$publishButton.Text = "3 Publish"
$publishButton.Location = New-Object System.Drawing.Point(786, 590)
$publishButton.Size = New-Object System.Drawing.Size(135, 32)
$publishButton.Add_Click({
    try {
        $meta = Read-UiReleaseMetadata
        Assert-ReleaseBranch -ReleaseBranch $meta.Branch
        $releaseKind = if ($meta.Prerelease) { "Beta / prerelease" } else { "Full release" }
        $steps = @("update changelog files")
        if ($autoSourceBox.Checked) { $steps = @("refresh Auto Changelog from repo") + $steps }
        if ($buildBox.Checked) { $steps += "build local ZIP" }
        if ($commitBox.Checked) { $steps += "commit all changes" }
        if ($tagCreateBox.Checked) { $steps += "create annotated tag" }
        if ($pushBox.Checked) { $steps += ("push HEAD to origin/" + $meta.Branch + " and push tag") }
        if ($workflowBox.Checked) { $steps += "publish through GitHub Actions" }
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Publish $($meta.Tag) as $releaseKind.`nChangelog title: $($meta.Display)`nRelease name: $($meta.ReleaseName)`nBranch: $($meta.Branch)`n`nSteps:`n- $($steps -join "`n- ")`n`nContinue?",
            "MSUF Release Helper",
            "YesNo",
            "Warning"
        )
        if ($confirm -ne "Yes") { return }

        if ($autoSourceBox.Checked) {
            Sync-AutoChangelogSource -Reason "Publish"
        }
        $r = Read-UiRelease
        Start-LocalPreparation -ReleaseTag $r.Tag -DisplayVersion $r.Display -ReleaseDate $r.Date -BodyLines $r.Body -OutputDir $r.OutputDir -BuildZip $buildBox.Checked
        if ($commitBox.Checked) { Commit-AllChanges -ReleaseTag $r.Tag }
        if ($tagCreateBox.Checked) { Create-ReleaseTag -ReleaseTag $r.Tag -ReleaseName $r.ReleaseName }
        if ($pushBox.Checked) { Push-ReleaseTag -ReleaseTag $r.Tag -ReleaseBranch $r.Branch }
        if ($workflowBox.Checked) {
            if ($pushBox.Checked) {
                Write-ReleaseLog "GitHub Actions release workflow will start from the pushed release tag."
            } else {
                Start-GitHubWorkflow -ReleaseTag $r.Tag -Prerelease $r.Prerelease -ReleaseBranch $r.Branch -ReleaseName $r.ReleaseName
            }
        }
        Write-ReleaseLog "GitHub release step complete."
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($publishButton)

$statusButton = New-Object System.Windows.Forms.Button
$statusButton.Text = "Git Status"
$statusButton.Location = New-Object System.Drawing.Point(931, 590)
$statusButton.Size = New-Object System.Drawing.Size(85, 32)
$statusButton.Add_Click({
    try {
        $status = @(Test-GitCleanEnough)
        if ($status.Count -eq 0) {
            Write-ReleaseLog "Git worktree is clean."
        } else {
            Write-ReleaseLog "Git worktree changes:"
            foreach ($line in $status) { Write-ReleaseLog $line }
        }
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
    }
})
$form.Controls.Add($statusButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "Close"
$closeButton.Location = New-Object System.Drawing.Point(1026, 590)
$closeButton.Size = New-Object System.Drawing.Size(90, 32)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

Write-ReleaseLog "Ready. Fill changelog sections, preview, then update/build or publish."
[void]$form.ShowDialog()
