<#
.SYNOPSIS
Registers a one-time Windows task that publishes an MSUF release tag.

.DESCRIPTION
The scheduler pins the current remote branch head when the task is registered.
At the requested time it verifies that the remote branch still points at that
exact commit, creates an annotated release tag, and pushes only that tag. The
existing GitHub Actions release workflow then performs the build and upload.

The computer must be running (or wake later with StartWhenAvailable), and the
scheduled user must still have working Git credentials at execution time.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\.github\scripts\schedule-release.ps1 `
    -ReleaseAt "2026-08-14T20:30:00+02:00" `
    -TagName "v6.06" `
    -PublishTarget curseforge

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\.github\scripts\schedule-release.ps1 `
    -ReleaseAt "2026-08-14T20:30:00+02:00" `
    -TagName "v6.06" `
    -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Schedule")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Schedule")]
    [DateTimeOffset]$ReleaseAt,

    [Parameter(Mandatory = $true, ParameterSetName = "Schedule")]
    [Parameter(Mandatory = $true, ParameterSetName = "Execute")]
    [ValidatePattern('^(?:v?[0-9][A-Za-z0-9._-]*|MSUF_[0-9][A-Za-z0-9._-]*)$')]
    [string]$TagName,

    [Parameter(ParameterSetName = "Schedule")]
    [Parameter(ParameterSetName = "Execute")]
    [ValidateSet("all", "github", "wago", "curseforge", "wago+curseforge")]
    [string]$PublishTarget = "curseforge",

    [Parameter(ParameterSetName = "Schedule")]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Branch = "main",

    [Parameter(ParameterSetName = "Schedule")]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$TaskName,

    [Parameter(Mandatory = $true, ParameterSetName = "Execute")]
    [switch]$ExecuteScheduledRelease,

    [Parameter(Mandatory = $true, ParameterSetName = "Execute")]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedCommit,

    [Parameter(Mandatory = $true, ParameterSetName = "Execute")]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$ExpectedBranch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$releaseWorkflowPath = Join-Path $repoRoot ".github\workflows\release.yml"
$logDirectory = Join-Path $repoRoot "_local_workflows\logs\scheduled-releases"
$payloadDirectory = Join-Path $repoRoot "_local_workflows\scheduled-release-tasks"

function Invoke-GitText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowEmpty
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 can promote native stderr to a terminating
        # error. Capture git's exit code ourselves so normal fetch progress is
        # not mistaken for failure.
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $repoRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }

    $text = ($output -join "`n").Trim()
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) {
        throw "git $($Arguments -join ' ') returned no output."
    }
    return $text
}

function Assert-ReleaseWorkflow {
    if (-not (Test-Path -LiteralPath $releaseWorkflowPath -PathType Leaf)) {
        throw "Release workflow not found: $releaseWorkflowPath"
    }

    $workflow = Get-Content -LiteralPath $releaseWorkflowPath -Raw
    if ($workflow -notmatch '(?m)^\s*push:\s*$' -or $workflow -notmatch '(?m)^\s*tags:\s*$') {
        throw "The release workflow is not configured for tag pushes."
    }
}

function Test-RemoteTagExists {
    param([Parameter(Mandatory = $true)][string]$Name)

    $remoteTag = Invoke-GitText -Arguments @("ls-remote", "--tags", "origin", "refs/tags/$Name") -AllowEmpty
    return -not [string]::IsNullOrWhiteSpace($remoteTag)
}

function Assert-TagIsAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (Test-RemoteTagExists -Name $Name) {
        throw "Remote tag '$Name' already exists. Nothing was published."
    }

    $localTag = Invoke-GitText -Arguments @("tag", "--list", $Name) -AllowEmpty
    if (-not [string]::IsNullOrWhiteSpace($localTag)) {
        throw "Local tag '$Name' already exists. Nothing was published."
    }
}

function Assert-ReleaseMetadataAtCommit {
    param(
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $expectedVersion = if ($Name.StartsWith("MSUF_", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Name.Substring(5)
    } elseif ($Name.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $Name.Substring(1)
    } else {
        $Name
    }

    $version = (Invoke-GitText -Arguments @("show", "${Commit}:VERSION")).Trim()
    if (-not $version.Equals($expectedVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Tag '$Name' expects version '$expectedVersion', but VERSION at $Commit is '$version'. Nothing was published."
    }

    $tocPaths = @(
        "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc"
        "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc"
        "MidnightSimpleUnitFrames_Options/MidnightSimpleUnitFrames_Options.toc"
    )
    foreach ($tocPath in $tocPaths) {
        $toc = Invoke-GitText -Arguments @("show", "${Commit}:$tocPath")
        $match = [regex]::Match($toc, '(?m)^## Version:\s*(.+?)\s*$')
        if (-not $match.Success -or -not $match.Groups[1].Value.Equals($version, [System.StringComparison]::OrdinalIgnoreCase)) {
            $actual = if ($match.Success) { $match.Groups[1].Value } else { "<missing>" }
            throw "TOC version mismatch at ${Commit}:$tocPath. Expected '$version', got '$actual'. Nothing was published."
        }
    }
}

function Update-RemoteBranch {
    param([Parameter(Mandatory = $true)][string]$Name)

    Invoke-GitText -Arguments @(
        "fetch",
        "--no-tags",
        "origin",
        "+refs/heads/${Name}:refs/remotes/origin/${Name}"
    ) -AllowEmpty | Out-Null

    return Invoke-GitText -Arguments @("rev-parse", "refs/remotes/origin/${Name}^{commit}")
}

function Invoke-ScheduledRelease {
    Assert-ReleaseWorkflow

    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $safeTag = $TagName -replace '[^A-Za-z0-9._-]', '_'
    $logPath = Join-Path $logDirectory "$safeTag.log"
    Start-Transcript -LiteralPath $logPath -Append | Out-Null

    try {
        Write-Host "Scheduled release started at $([DateTimeOffset]::Now.ToString('o'))."
        Write-Host "Expected origin/${ExpectedBranch}: $ExpectedCommit"

        $remoteCommit = Update-RemoteBranch -Name $ExpectedBranch
        if ($remoteCommit -ne $ExpectedCommit) {
            throw "origin/${ExpectedBranch} moved from $ExpectedCommit to $remoteCommit. Nothing was published."
        }

        Assert-TagIsAvailable -Name $TagName
        Assert-ReleaseMetadataAtCommit -Commit $ExpectedCommit -Name $TagName

        $workflowAtCommit = Invoke-GitText -Arguments @("show", "${ExpectedCommit}:.github/workflows/release.yml")
        if ($workflowAtCommit -notmatch '(?m)^\s*push:\s*$' -or $workflowAtCommit -notmatch '(?m)^\s*tags:\s*$') {
            throw "Commit $ExpectedCommit does not contain a tag-triggered release workflow."
        }

        $tagMessage = "$TagName`n`npublish-target: $PublishTarget"
        Invoke-GitText -Arguments @("tag", "--annotate", $TagName, $ExpectedCommit, "--message", $tagMessage) -AllowEmpty | Out-Null

        try {
            Invoke-GitText -Arguments @("push", "origin", "refs/tags/${TagName}:refs/tags/${TagName}") -AllowEmpty | Out-Null
        } catch {
            Write-Warning "The local tag '$TagName' was created, but its push failed. It was left in place for inspection."
            throw
        }

        Write-Host "Release tag '$TagName' was pushed successfully. GitHub Actions now owns build and publication verification."
    } finally {
        Stop-Transcript | Out-Null
    }
}

if ($PSCmdlet.ParameterSetName -eq "Execute") {
    Invoke-ScheduledRelease
    exit 0
}

Assert-ReleaseWorkflow

$now = [DateTimeOffset]::Now
if ($ReleaseAt -le $now.AddMinutes(1)) {
    throw "ReleaseAt must be at least one minute in the future. Current time: $($now.ToString('o'))"
}

$expectedCommit = Update-RemoteBranch -Name $Branch
Assert-TagIsAvailable -Name $TagName
Assert-ReleaseMetadataAtCommit -Commit $expectedCommit -Name $TagName

$workflowAtCommit = Invoke-GitText -Arguments @("show", "${expectedCommit}:.github/workflows/release.yml")
if ($workflowAtCommit -notmatch '(?m)^\s*push:\s*$' -or $workflowAtCommit -notmatch '(?m)^\s*tags:\s*$') {
    throw "origin/$Branch at $expectedCommit does not contain a tag-triggered release workflow."
}

if ([string]::IsNullOrWhiteSpace($TaskName)) {
    $safeTag = $TagName -replace '[^A-Za-z0-9._-]', '_'
    $TaskName = "MSUF-Release-$safeTag"
}

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask) {
    throw "Scheduled task '$TaskName' already exists. Remove or rename it before scheduling another release."
}

$powerShellExecutable = (Get-Process -Id $PID).Path
$payloadName = ($TaskName -replace '[^A-Za-z0-9._-]', '_') + ".ps1"
$payloadPath = Join-Path $payloadDirectory $payloadName
$scriptArgument = '"{0}"' -f $payloadPath
$arguments = @(
    "-NoLogo"
    "-NoProfile"
    "-NonInteractive"
    "-ExecutionPolicy Bypass"
    "-File $scriptArgument"
    "-ExecuteScheduledRelease"
    "-TagName $TagName"
    "-PublishTarget $PublishTarget"
    "-ExpectedCommit $expectedCommit"
    "-ExpectedBranch $Branch"
) -join " "

$localReleaseTime = $ReleaseAt.ToLocalTime()
$action = New-ScheduledTaskAction `
    -Execute $powerShellExecutable `
    -Argument $arguments `
    -WorkingDirectory $repoRoot
$trigger = New-ScheduledTaskTrigger -Once -At $localReleaseTime.DateTime
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

$description = "Push $TagName for origin/$Branch at $expectedCommit; target=$PublishTarget; scheduled=$($ReleaseAt.ToString('o'))"
$target = "$TaskName at $($localReleaseTime.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
if ($PSCmdlet.ShouldProcess($target, "Register one-time MSUF release task")) {
    New-Item -ItemType Directory -Path $payloadDirectory -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $payloadPath
    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description $description | Out-Null
    } catch {
        Remove-Item -LiteralPath $payloadPath -Force -ErrorAction SilentlyContinue
        throw
    }
}

Write-Host "Release timer prepared:"
Write-Host "  Task:           $TaskName"
Write-Host "  Local time:     $($localReleaseTime.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
Write-Host "  UTC time:       $($ReleaseAt.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss'))Z"
Write-Host "  Tag:            $TagName"
Write-Host "  Publish target: $PublishTarget"
Write-Host "  Pinned commit:  $expectedCommit (origin/$Branch)"
Write-Host "  Log:            $logDirectory"
Write-Host "  Task payload:   $payloadPath"
Write-Host ""
Write-Host "The task will fail closed if origin/$Branch moves or the tag already exists."
