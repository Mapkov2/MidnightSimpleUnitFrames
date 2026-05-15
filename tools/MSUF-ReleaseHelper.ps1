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

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-ReleaseLog ("> " + $FilePath + " " + ($Arguments -join " "))
    Push-Location $RepoRoot
    try {
        $output = & $FilePath @Arguments 2>&1
        $exit = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
        foreach ($line in $output) {
            if ($line -ne $null -and "$line" -ne "") { Write-ReleaseLog "$line" }
        }
        if ($exit -ne 0) {
            throw "Command failed with exit code $exit`: $FilePath"
        }
    } finally {
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
    param([AllowNull()][string]$BaseRef)

    Push-Location $RepoRoot
    try {
        $range = if ([string]::IsNullOrWhiteSpace($BaseRef)) { "HEAD" } else { "$BaseRef..HEAD" }
        $commitLines = & git log --reverse --format="%H`t%h`t%s" $range 2>&1
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
        [AllowNull()][string]$BaseRef
    )

    $commits = Get-GitCommitsForChangelog -BaseRef $BaseRef
    if ($commits.Count -eq 0) {
        throw "No commits found for changelog range '$BaseRef..HEAD'."
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
    $status = & git status --porcelain 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git status failed. Is this a git repository?" }
    return [string[]]$status
}

function Commit-AllChanges {
    param([Parameter(Mandatory = $true)][string]$ReleaseTag)

    Invoke-External "git" @("add", "-A")
    $status = Test-GitCleanEnough
    if ($status.Count -eq 0) {
        Write-ReleaseLog "No staged changes to commit."
        return
    }
    Invoke-External "git" @("commit", "-m", "Release $ReleaseTag")
}

function Create-ReleaseTag {
    param([Parameter(Mandatory = $true)][string]$ReleaseTag)

    & git rev-parse -q --verify "refs/tags/$ReleaseTag" *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-ReleaseLog "Git tag already exists locally: $ReleaseTag"
        return
    }
    Invoke-External "git" @("tag", "-a", $ReleaseTag, "-m", "MSUF $ReleaseTag")
}

function Push-ReleaseTag {
    param([Parameter(Mandatory = $true)][string]$ReleaseTag)

    Invoke-External "git" @("push", "origin", "HEAD")
    Invoke-External "git" @("push", "origin", $ReleaseTag)
}

function Start-GitHubWorkflow {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][bool]$Prerelease
    )

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        throw "GitHub CLI (gh) is not installed or not in PATH."
    }

    Invoke-External "gh" @("auth", "status")
    Invoke-External "gh" @("workflow", "run", "release.yml", "-f", "tag_name=$ReleaseTag", "-f", ("prerelease=" + $Prerelease.ToString().ToLowerInvariant()))
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
        [AllowNull()][string]$BaseRef
    )

    if (-not (Test-Path -LiteralPath $AutoChangelogScript)) {
        throw "Missing auto changelog tool: $AutoChangelogScript"
    }

    $args = @("-DisplayVersion", $DisplayVersion, "-RegenerateAddonChangelog")
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
$form.Size = New-Object System.Drawing.Size(1040, 930)
$form.MinimumSize = New-Object System.Drawing.Size(900, 820)

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

New-Label "Release tag" 16 16 | Out-Null
$tagBox = New-TextBox 130 14 180 "5.1-beta4"
New-Label "Changelog title" 330 16 | Out-Null
$displayBox = New-TextBox 450 14 190 "5.1 Beta 4"
New-Label "Date" 660 16 50 | Out-Null
$dateBox = New-TextBox 710 14 105 (Get-Date -Format "yyyy-MM-dd")

$preBox = New-Object System.Windows.Forms.CheckBox
$preBox.Text = "Prerelease / beta"
$preBox.Checked = $true
$preBox.Location = New-Object System.Drawing.Point(835, 14)
$preBox.Size = New-Object System.Drawing.Size(160, 24)
$form.Controls.Add($preBox)

New-Label "Output dir" 16 48 | Out-Null
$outBox = New-TextBox 130 46 220 "dist"

$buildBox = New-Object System.Windows.Forms.CheckBox
$buildBox.Text = "Build local zip"
$buildBox.Checked = $true
$buildBox.Location = New-Object System.Drawing.Point(370, 46)
$buildBox.Size = New-Object System.Drawing.Size(130, 24)
$form.Controls.Add($buildBox)

$commitBox = New-Object System.Windows.Forms.CheckBox
$commitBox.Text = "Commit all changes"
$commitBox.Checked = $false
$commitBox.Location = New-Object System.Drawing.Point(510, 46)
$commitBox.Size = New-Object System.Drawing.Size(150, 24)
$form.Controls.Add($commitBox)

$tagCreateBox = New-Object System.Windows.Forms.CheckBox
$tagCreateBox.Text = "Create tag"
$tagCreateBox.Checked = $false
$tagCreateBox.Location = New-Object System.Drawing.Point(670, 46)
$tagCreateBox.Size = New-Object System.Drawing.Size(100, 24)
$form.Controls.Add($tagCreateBox)

$pushBox = New-Object System.Windows.Forms.CheckBox
$pushBox.Text = "Push"
$pushBox.Checked = $false
$pushBox.Location = New-Object System.Drawing.Point(780, 46)
$pushBox.Size = New-Object System.Drawing.Size(70, 24)
$form.Controls.Add($pushBox)

$workflowBox = New-Object System.Windows.Forms.CheckBox
$workflowBox.Text = "Run GitHub workflow"
$workflowBox.Checked = $false
$workflowBox.Location = New-Object System.Drawing.Point(850, 46)
$workflowBox.Size = New-Object System.Drawing.Size(170, 24)
$form.Controls.Add($workflowBox)

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

$perfBox = New-TextArea "Performance (one bullet per line)" 16 108 490 90
$bugBox = New-TextArea "Bugfixes (one bullet per line)" 526 108 490 90
$changeBox = New-TextArea "Changes / Improvements" 16 228 490 75
$toolBox = New-TextArea "Release / Tooling" 526 228 490 75
$docBox = New-TextArea "Documentation" 16 333 1000 58
$mdBox = New-TextArea "Markdown changelog from repo" 16 420 1000 92

$useMarkdownBox = New-Object System.Windows.Forms.CheckBox
$useMarkdownBox.Text = "Use Markdown text as release source"
$useMarkdownBox.Checked = $false
$useMarkdownBox.Location = New-Object System.Drawing.Point(760, 420)
$useMarkdownBox.Size = New-Object System.Drawing.Size(260, 22)
$form.Controls.Add($useMarkdownBox)

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(16, 620)
$script:LogBox.Size = New-Object System.Drawing.Size(1000, 244)
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

function Read-UiRelease {
    $tag = Normalize-ReleaseVersion $tagBox.Text
    $display = $displayBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($display)) { $display = Convert-TagToDisplayVersion $tag }
    $date = $dateBox.Text.Trim()
    if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date must be YYYY-MM-DD." }
    $output = $outBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($output)) { $output = "dist" }

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
        Tag = $tag
        Display = $display
        Date = $date
        OutputDir = $output
        Body = $body
        Prerelease = $preBox.Checked
    }
}

$loadRepoButton = New-Object System.Windows.Forms.Button
$loadRepoButton.Text = "Load CHANGELOG.md"
$loadRepoButton.Location = New-Object System.Drawing.Point(16, 542)
$loadRepoButton.Size = New-Object System.Drawing.Size(145, 32)
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
$loadCommitsButton.Text = "Load Git Commits"
$loadCommitsButton.Location = New-Object System.Drawing.Point(170, 542)
$loadCommitsButton.Size = New-Object System.Drawing.Size(145, 32)
$loadCommitsButton.Add_Click({
    try {
        $tag = Normalize-ReleaseVersion $tagBox.Text
        $display = $displayBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($display)) { $display = Convert-TagToDisplayVersion $tag }
        $date = $dateBox.Text.Trim()
        if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date must be YYYY-MM-DD." }
        $baseRef = $baseRefBox.Text.Trim()

        $markdown = New-GitCommitChangelogMarkdown -ReleaseTag $tag -DisplayVersion $display -ReleaseDate $date -BaseRef $baseRef
        $mdBox.Text = $markdown
        Set-UiFromMarkdown -Markdown $markdown | Out-Null
        $useMarkdownBox.Checked = $true
        Write-ReleaseLog ("Generated changelog draft from git commits: " + ($(if ($baseRef) { $baseRef } else { "initial history" }) + "..HEAD"))
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($loadCommitsButton)

$autoChangelogButton = New-Object System.Windows.Forms.Button
$autoChangelogButton.Text = "Auto Changelog"
$autoChangelogButton.Location = New-Object System.Drawing.Point(16, 580)
$autoChangelogButton.Size = New-Object System.Drawing.Size(145, 32)
$autoChangelogButton.Add_Click({
    try {
        $tag = Normalize-ReleaseVersion $tagBox.Text
        $display = $displayBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($display)) { $display = Convert-TagToDisplayVersion $tag }
        $baseRef = $baseRefBox.Text.Trim()

        Update-AutoChangelogFromRepo -DisplayVersion $display -BaseRef $baseRef
        $section = Find-ChangelogSection -ReleaseTag $tag -DisplayVersion $display
        $mdBox.Text = $section.Markdown
        Set-UiFromMarkdown -Markdown $section.Markdown | Out-Null
        $useMarkdownBox.Checked = $true
        Write-ReleaseLog ("Auto changelog updated from repo changes for " + $display)
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($autoChangelogButton)

$fillFieldsButton = New-Object System.Windows.Forms.Button
$fillFieldsButton.Text = "Map Markdown"
$fillFieldsButton.Location = New-Object System.Drawing.Point(324, 542)
$fillFieldsButton.Size = New-Object System.Drawing.Size(125, 32)
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
$previewButton.Text = "Preview Changelog"
$previewButton.Location = New-Object System.Drawing.Point(458, 542)
$previewButton.Size = New-Object System.Drawing.Size(125, 32)
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
$prepButton.Text = "Update Files + Build"
$prepButton.Location = New-Object System.Drawing.Point(592, 542)
$prepButton.Size = New-Object System.Drawing.Size(145, 32)
$prepButton.Add_Click({
    try {
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
$publishButton.Text = "GitHub Release"
$publishButton.Location = New-Object System.Drawing.Point(746, 542)
$publishButton.Size = New-Object System.Drawing.Size(125, 32)
$publishButton.Add_Click({
    try {
        $r = Read-UiRelease
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "This can commit, tag, push, and queue the GitHub release workflow depending on the selected checkboxes.`n`nContinue?",
            "MSUF Release Helper",
            "YesNo",
            "Warning"
        )
        if ($confirm -ne "Yes") { return }

        Start-LocalPreparation -ReleaseTag $r.Tag -DisplayVersion $r.Display -ReleaseDate $r.Date -BodyLines $r.Body -OutputDir $r.OutputDir -BuildZip $buildBox.Checked
        if ($commitBox.Checked) { Commit-AllChanges -ReleaseTag $r.Tag }
        if ($tagCreateBox.Checked) { Create-ReleaseTag -ReleaseTag $r.Tag }
        if ($pushBox.Checked) { Push-ReleaseTag -ReleaseTag $r.Tag }
        if ($workflowBox.Checked) { Start-GitHubWorkflow -ReleaseTag $r.Tag -Prerelease $r.Prerelease }
        Write-ReleaseLog "GitHub release step complete."
    } catch {
        Write-ReleaseLog ("ERROR: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "MSUF Release Helper", "OK", "Error") | Out-Null
    }
})
$form.Controls.Add($publishButton)

$statusButton = New-Object System.Windows.Forms.Button
$statusButton.Text = "Git Status"
$statusButton.Location = New-Object System.Drawing.Point(880, 542)
$statusButton.Size = New-Object System.Drawing.Size(75, 32)
$statusButton.Add_Click({
    try {
        $status = Test-GitCleanEnough
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
$closeButton.Location = New-Object System.Drawing.Point(963, 542)
$closeButton.Size = New-Object System.Drawing.Size(53, 32)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

Write-ReleaseLog "Ready. Fill changelog sections, preview, then update/build or publish."
[void]$form.ShowDialog()
