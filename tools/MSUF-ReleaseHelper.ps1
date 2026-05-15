[CmdletBinding()]
param(
    [switch]$NoGui
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$ChangelogPath = Join-Path $RepoRoot "CHANGELOG.md"
$AddonChangelogScript = Join-Path $RepoRoot "tools/update-addon-changelog.ps1"
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

function Update-ChangelogFile {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$DisplayVersion,
        [Parameter(Mandatory = $true)][string]$ReleaseDate,
        [Parameter(Mandatory = $true)][string[]]$BodyLines
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
        [Parameter(Mandatory = $true)][string[]]$BodyLines,
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [bool]$BuildZip = $true
    )

    Update-ChangelogFile -ReleaseTag $ReleaseTag -DisplayVersion $DisplayVersion -ReleaseDate $ReleaseDate -BodyLines $BodyLines
    Update-AddonChangelog -ReleaseTag $ReleaseTag
    if ($BuildZip) {
        Build-ReleaseZip -ReleaseTag $ReleaseTag -OutputDir $OutputDir
    }
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
$form.Size = New-Object System.Drawing.Size(1040, 780)
$form.MinimumSize = New-Object System.Drawing.Size(900, 680)

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

$perfBox = New-TextArea "Performance (one bullet per line)" 16 82 490 90
$bugBox = New-TextArea "Bugfixes (one bullet per line)" 526 82 490 90
$changeBox = New-TextArea "Changes / Improvements" 16 202 490 75
$toolBox = New-TextArea "Release / Tooling" 526 202 490 75
$docBox = New-TextArea "Documentation" 16 307 1000 58

$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Location = New-Object System.Drawing.Point(16, 474)
$script:LogBox.Size = New-Object System.Drawing.Size(1000, 220)
$script:LogBox.Multiline = $true
$script:LogBox.ScrollBars = "Vertical"
$script:LogBox.ReadOnly = $true
$form.Controls.Add($script:LogBox)

function Read-UiRelease {
    $tag = Normalize-ReleaseVersion $tagBox.Text
    $display = $displayBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($display)) { $display = Convert-TagToDisplayVersion $tag }
    $date = $dateBox.Text.Trim()
    if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') { throw "Date must be YYYY-MM-DD." }
    $output = $outBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($output)) { $output = "dist" }
    $body = New-ChangelogBody -Performance $perfBox.Text -Bugfixes $bugBox.Text -Changes $changeBox.Text -Tooling $toolBox.Text -Docs $docBox.Text

    return [pscustomobject]@{
        Tag = $tag
        Display = $display
        Date = $date
        OutputDir = $output
        Body = $body
        Prerelease = $preBox.Checked
    }
}

$previewButton = New-Object System.Windows.Forms.Button
$previewButton.Text = "Preview Changelog"
$previewButton.Location = New-Object System.Drawing.Point(16, 396)
$previewButton.Size = New-Object System.Drawing.Size(150, 32)
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
$prepButton.Location = New-Object System.Drawing.Point(180, 396)
$prepButton.Size = New-Object System.Drawing.Size(160, 32)
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
$publishButton.Location = New-Object System.Drawing.Point(354, 396)
$publishButton.Size = New-Object System.Drawing.Size(145, 32)
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
$statusButton.Location = New-Object System.Drawing.Point(514, 396)
$statusButton.Size = New-Object System.Drawing.Size(110, 32)
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
$closeButton.Location = New-Object System.Drawing.Point(906, 396)
$closeButton.Size = New-Object System.Drawing.Size(110, 32)
$closeButton.Add_Click({ $form.Close() })
$form.Controls.Add($closeButton)

Write-ReleaseLog "Ready. Fill changelog sections, preview, then update/build or publish."
[void]$form.ShowDialog()
