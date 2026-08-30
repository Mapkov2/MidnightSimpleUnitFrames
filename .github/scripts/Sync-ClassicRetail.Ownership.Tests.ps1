[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptUnderTest = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "Sync-ClassicRetail.ps1"))
$powerShellHost = (Get-Process -Id $PID).Path
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$suiteRoot = Join-Path $tempParent ("msuf-sync-ownership-" + [guid]::NewGuid().ToString("N"))
$addonRoots = @(
    "MidnightSimpleUnitFrames",
    "MidnightSimpleUnitFrames_Options",
    "MidnightSimpleUnitFrames_Assistant"
)

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $Repository @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "Fixture Git failed: git -C '$Repository' $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return (($output | Out-String).Trim())
}

function Write-TestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $fullPath = [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    if (-not $fullPath.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Fixture path escaped its root: $fullPath"
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $fullPath)) | Out-Null
    [IO.File]::WriteAllText($fullPath, $Content, [Text.UTF8Encoding]::new($false))
}

function Copy-TestFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $source = [IO.Path]::GetFullPath((Join-Path $SourceRoot $SourcePath))
    $destination = [IO.Path]::GetFullPath((Join-Path $DestinationRoot $DestinationPath))
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    [IO.File]::Copy($source, $destination, $true)
}

function Commit-All {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Body = ""
    )

    [void](Invoke-TestGit -Repository $Repository -Arguments @("add", "-A"))
    $arguments = @("commit", "-m", $Message)
    if (-not [string]::IsNullOrWhiteSpace($Body)) { $arguments += @("-m", $Body) }
    [void](Invoke-TestGit -Repository $Repository -Arguments $arguments)
}

function Get-TestBlob {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$Path
    )

    return Invoke-TestGit -Repository $Repository -Arguments @("rev-parse", "$Commit`:$Path")
}

function New-Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$OwnedPaths = @("MidnightSimpleUnitFrames/Game/Classic/Owned.lua"),
        [string[]]$OverridePaths = @("MidnightSimpleUnitFrames/Override.lua")
    )

    $caseRoot = Join-Path $suiteRoot $Name
    $retail = Join-Path $caseRoot "retail"
    $classic = Join-Path $caseRoot "classic"
    [IO.Directory]::CreateDirectory($retail) | Out-Null
    [IO.Directory]::CreateDirectory($classic) | Out-Null
    [void](Invoke-TestGit -Repository $retail -Arguments @("init", "-b", "main"))
    [void](Invoke-TestGit -Repository $classic -Arguments @("init", "-b", "classic"))
    foreach ($repository in @($retail, $classic)) {
        [void](Invoke-TestGit -Repository $repository -Arguments @("config", "user.name", "MSUF Sync Test"))
        [void](Invoke-TestGit -Repository $repository -Arguments @("config", "user.email", "sync-test@example.invalid"))
        [void](Invoke-TestGit -Repository $repository -Arguments @("config", "core.autocrlf", "false"))
        Write-TestFile -Root $repository -RelativePath ".gitattributes" -Content "* -text`n"
    }

    foreach ($addonRoot in $addonRoots) {
        Write-TestFile -Root $retail -RelativePath "$addonRoot/$addonRoot.toc" -Content "## Interface: 120100`n"
    }
    Write-TestFile -Root $retail -RelativePath "MidnightSimpleUnitFrames/Core.lua" -Content "return 'baseline'`n"
    Write-TestFile -Root $retail -RelativePath "MidnightSimpleUnitFrames/Deleted.lua" -Content "return 'delete-me'`n"
    Write-TestFile -Root $retail -RelativePath "MidnightSimpleUnitFrames/Swap/Old.lua" -Content "return 'old-child'`n"
    foreach ($overridePath in $OverridePaths) {
        Write-TestFile -Root $retail -RelativePath $overridePath -Content "return 'retail-base:$overridePath'`n"
    }
    Commit-All -Repository $retail -Message "retail baseline"
    $baseline = Invoke-TestGit -Repository $retail -Arguments @("rev-parse", "HEAD")
    $overrideBaseBlobs = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($overridePath in $OverridePaths) {
        $overrideBaseBlobs.Add($overridePath, (Get-TestBlob -Repository $retail -Commit $baseline -Path $overridePath))
    }

    foreach ($addonRoot in $addonRoots) {
        Copy-TestFile -SourceRoot $retail -DestinationRoot $classic `
            -SourcePath "$addonRoot/$addonRoot.toc" `
            -DestinationPath "$addonRoot/${addonRoot}_Mainline.toc"
    }
    Copy-TestFile -SourceRoot $retail -DestinationRoot $classic `
        -SourcePath "MidnightSimpleUnitFrames/Core.lua" `
        -DestinationPath "MidnightSimpleUnitFrames/Core.lua"
    Copy-TestFile -SourceRoot $retail -DestinationRoot $classic `
        -SourcePath "MidnightSimpleUnitFrames/Deleted.lua" `
        -DestinationPath "MidnightSimpleUnitFrames/Deleted.lua"
    Copy-TestFile -SourceRoot $retail -DestinationRoot $classic `
        -SourcePath "MidnightSimpleUnitFrames/Swap/Old.lua" `
        -DestinationPath "MidnightSimpleUnitFrames/Swap/Old.lua"
    foreach ($overridePath in $OverridePaths) {
        Copy-TestFile -SourceRoot $retail -DestinationRoot $classic `
            -SourcePath $overridePath -DestinationPath $overridePath
        Write-TestFile -Root $classic -RelativePath $overridePath -Content "return 'classic-override:$overridePath'`n"
    }
    foreach ($ownedPath in $OwnedPaths) {
        if ($ownedPath -ne "MidnightSimpleUnitFrames/Deleted.lua") {
            Write-TestFile -Root $classic -RelativePath $ownedPath -Content "return 'classic-owned'`n"
        }
    }
    $sortedOwned = [string[]]$OwnedPaths.Clone()
    [Array]::Sort($sortedOwned, [StringComparer]::Ordinal)
    Write-TestFile -Root $classic -RelativePath "tools/classic-owned-addon-paths.txt" `
        -Content (($sortedOwned -join "`n") + "`n")
    $sortedOverrides = [string[]]$OverridePaths.Clone()
    [Array]::Sort($sortedOverrides, [StringComparer]::Ordinal)
    $overrideRows = @($sortedOverrides | ForEach-Object { "$_`t$($overrideBaseBlobs[$_])" })
    $overrideContent = if ($overrideRows.Count -eq 0) { "" } else { ($overrideRows -join "`n") + "`n" }
    Write-TestFile -Root $classic -RelativePath "tools/classic-retail-overrides.tsv" -Content $overrideContent
    Write-TestFile -Root $classic -RelativePath "tools/test-classic-prototype.ps1" `
        -Content "param([string]`$RetailReferenceRoot = '')`nexit 0`n"
    Commit-All -Repository $classic -Message "classic baseline" -Body "Retail-Source: $baseline"

    return [pscustomobject]@{
        Root = $caseRoot
        Retail = $retail
        Classic = $classic
        Baseline = $baseline
        OwnedPaths = $sortedOwned
        OverridePaths = $sortedOverrides
        OverrideBaseBlobs = $overrideBaseBlobs
    }
}

function Set-RetailDelta {
    param([Parameter(Mandatory = $true)]$Fixture)

    Write-TestFile -Root $Fixture.Retail -RelativePath "MidnightSimpleUnitFrames/Core.lua" -Content "return 'current'`n"
    $deleted = Join-Path $Fixture.Retail "MidnightSimpleUnitFrames/Deleted.lua"
    if (Test-Path -LiteralPath $deleted -PathType Leaf) { Remove-Item -LiteralPath $deleted -Force }
    Write-TestFile -Root $Fixture.Retail -RelativePath "MidnightSimpleUnitFrames/New.lua" -Content "return 'new'`n"
    Commit-All -Repository $Fixture.Retail -Message "retail delta"
}

function Invoke-Sync {
    param(
        [Parameter(Mandatory = $true)]$Fixture,
        [switch]$PushCapable
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $arguments = @(
            "-NoLogo", "-NoProfile", "-File", $scriptUnderTest,
            "-RetailRoot", $Fixture.Retail, "-ClassicRoot", $Fixture.Classic
        )
        if (-not $PushCapable) { $arguments += "-NoPush" }
        $output = & $powerShellHost @arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($output | Out-String).Trim())
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Assert-Failure {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Case
    )
    Assert-True -Condition ($Result.ExitCode -ne 0) -Message "$Case unexpectedly succeeded"
    Assert-True -Condition ($Result.Output -match $Pattern) `
        -Message "$Case failed for the wrong reason:`n$($Result.Output)"
}

[IO.Directory]::CreateDirectory($suiteRoot) | Out-Null
try {
    $fixture = New-Fixture -Name "happy"
    Set-RetailDelta -Fixture $fixture
    $ownedPath = Join-Path $fixture.Classic $fixture.OwnedPaths[0]
    $overridePath = Join-Path $fixture.Classic $fixture.OverridePaths[0]
    $ownerBefore = (Get-FileHash -LiteralPath $ownedPath -Algorithm SHA256).Hash
    $overrideBefore = (Get-FileHash -LiteralPath $overridePath -Algorithm SHA256).Hash
    $result = Invoke-Sync -Fixture $fixture
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Happy sync failed:`n$($result.Output)"
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua"))) `
        -Message "Happy sync retained a deleted Retail file"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/New.lua")) `
        -Message "Happy sync did not add the new Retail file"
    Assert-True -Condition ((Get-FileHash -LiteralPath $ownedPath -Algorithm SHA256).Hash -ceq $ownerBefore) `
        -Message "Happy sync changed a Classic-owned file"
    Assert-True -Condition ((Get-FileHash -LiteralPath $overridePath -Algorithm SHA256).Hash -ceq $overrideBefore) `
        -Message "Happy sync changed an explicit Classic Retail override"
    $headAfterFirstSync = Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")
    $result = Invoke-Sync -Fixture $fixture
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Second no-op sync failed:`n$($result.Output)"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")) -ceq $headAfterFirstSync) `
        -Message "Second no-op sync created an unnecessary commit"
    Assert-True -Condition ((Get-FileHash -LiteralPath $overridePath -Algorithm SHA256).Hash -ceq $overrideBefore) `
        -Message "Second no-op sync changed an explicit Classic Retail override"
    Write-Host "PASS override happy add/update/delete, O/P preservation, and no-op repeat"

    $fixture = New-Fixture -Name "retail-override-conflict"
    Set-RetailDelta -Fixture $fixture
    Write-TestFile -Root $fixture.Retail -RelativePath $fixture.OverridePaths[0] `
        -Content "return 'retail-changed-after-recorded-base'`n"
    Commit-All -Repository $fixture.Retail -Message "retail changes overridden path"
    $classicHead = Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "Retail changed a Classic override since its recorded base" `
        -Case "Retail override conflict"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Retail-override conflict mutated the Classic worktree"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua") -PathType Leaf) `
        -Message "Retail-override conflict deleted a baseline file before failing"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")) -ceq $classicHead) `
        -Message "Retail-override conflict created a commit"
    Write-Host "PASS Retail change to an overridden path conflicts before mutation"

    $fixture = New-Fixture -Name "malformed-override-manifest"
    Write-TestFile -Root $fixture.Classic -RelativePath "tools/classic-retail-overrides.tsv" `
        -Content "$($fixture.OverridePaths[0]) $($fixture.OverrideBaseBlobs[$fixture.OverridePaths[0]])`n"
    Commit-All -Repository $fixture.Classic -Message "malformed override manifest"
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "must contain exactly one TAB" -Case "Malformed override manifest"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Malformed-manifest failure mutated the Classic worktree"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua") -PathType Leaf) `
        -Message "Malformed-manifest failure deleted a baseline file before failing"
    Write-Host "PASS malformed Retail-override manifest fails before mutation"

    $fixture = New-Fixture -Name "unsorted-override-manifest" -OverridePaths @(
        "MidnightSimpleUnitFrames/OverrideA.lua",
        "MidnightSimpleUnitFrames/OverrideZ.lua"
    )
    $unsortedRows = @(
        "$($fixture.OverridePaths[1])`t$($fixture.OverrideBaseBlobs[$fixture.OverridePaths[1]])",
        "$($fixture.OverridePaths[0])`t$($fixture.OverrideBaseBlobs[$fixture.OverridePaths[0]])"
    )
    Write-TestFile -Root $fixture.Classic -RelativePath "tools/classic-retail-overrides.tsv" `
        -Content (($unsortedRows -join "`n") + "`n")
    Commit-All -Repository $fixture.Classic -Message "unsorted override manifest"
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "must be sorted with ordinal path" `
        -Case "Unsorted override manifest"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Unsorted-manifest failure mutated the Classic worktree"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua") -PathType Leaf) `
        -Message "Unsorted-manifest failure deleted a baseline file before failing"
    Write-Host "PASS unsorted Retail-override manifest fails before mutation"

    $fixture = New-Fixture -Name "ownership-override-collision"
    $collidingOwners = @($fixture.OwnedPaths) + @($fixture.OverridePaths[0])
    [Array]::Sort($collidingOwners, [StringComparer]::Ordinal)
    Write-TestFile -Root $fixture.Classic -RelativePath "tools/classic-owned-addon-paths.txt" `
        -Content (($collidingOwners -join "`n") + "`n")
    Commit-All -Repository $fixture.Classic -Message "ownership and override collision"
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "ownership and Retail-override manifests collide" `
        -Case "Ownership/override collision"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Ownership/override collision mutated the Classic worktree"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua") -PathType Leaf) `
        -Message "Ownership/override collision deleted a baseline file before failing"
    Write-Host "PASS O/P manifest collision fails before mutation"

    $fixture = New-Fixture -Name "takeover" -OwnedPaths @("MidnightSimpleUnitFrames/Deleted.lua")
    $ownedPath = Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua"
    $ownerBefore = (Get-FileHash -LiteralPath $ownedPath -Algorithm SHA256).Hash
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Explicit ownership takeover failed:`n$($result.Output)"
    Assert-True -Condition ((Get-FileHash -LiteralPath $ownedPath -Algorithm SHA256).Hash -ceq $ownerBefore) `
        -Message "Explicitly owned retired Retail path was deleted or changed"
    Write-Host "PASS deleted Retail path can transfer explicitly to Classic ownership"

    $fixture = New-Fixture -Name "directory-to-file"
    $retailSwapChild = Join-Path $fixture.Retail "MidnightSimpleUnitFrames/Swap/Old.lua"
    Remove-Item -LiteralPath $retailSwapChild -Force
    Remove-Item -LiteralPath (Split-Path -Parent $retailSwapChild) -Force
    Write-TestFile -Root $fixture.Retail -RelativePath "MidnightSimpleUnitFrames/Swap" -Content "return 'replacement-file'`n"
    Commit-All -Repository $fixture.Retail -Message "retail replaces directory with file"
    $result = Invoke-Sync -Fixture $fixture
    Assert-True -Condition ($result.ExitCode -eq 0) -Message "Directory-to-file sync failed:`n$($result.Output)"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Swap") -PathType Leaf) `
        -Message "Directory-to-file sync did not create the replacement file"
    Write-Host "PASS verified Retail directory-to-file transition"

    $fixture = New-Fixture -Name "modified-baseline"
    Write-TestFile -Root $fixture.Classic -RelativePath "MidnightSimpleUnitFrames/Core.lua" -Content "return 'classic-drift'`n"
    Commit-All -Repository $fixture.Classic -Message "classic edits canonical file"
    Set-RetailDelta -Fixture $fixture
    $classicHead = Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "modified a Retail-owned baseline path" -Case "Modified baseline"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Modified-baseline failure mutated the Classic worktree"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")) -ceq $classicHead) `
        -Message "Modified-baseline failure created a commit"
    Write-Host "PASS modified canonical baseline fails before mutation"

    $fixture = New-Fixture -Name "deleted-baseline"
    [void](Invoke-TestGit -Repository $fixture.Classic -Arguments @("rm", "MidnightSimpleUnitFrames/Core.lua"))
    Commit-All -Repository $fixture.Classic -Message "classic deletes canonical file"
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "deleted a Retail-owned baseline path" -Case "Deleted baseline"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Deleted-baseline failure mutated the Classic worktree"
    Write-Host "PASS deleted canonical baseline fails before mutation"

    $fixture = New-Fixture -Name "undeclared-additive"
    Write-TestFile -Root $fixture.Classic -RelativePath "MidnightSimpleUnitFrames/Game/Classic/Undeclared.lua" `
        -Content "return 'undeclared'`n"
    Commit-All -Repository $fixture.Classic -Message "classic adds undeclared file"
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "neither Retail-owned nor declared Classic-owned" -Case "Undeclared additive"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Undeclared-additive failure mutated the Classic worktree"
    Write-Host "PASS undeclared additive file fails before mutation"

    $fixture = New-Fixture -Name "retail-owner-collision"
    Write-TestFile -Root $fixture.Retail -RelativePath $fixture.OwnedPaths[0] -Content "return 'retail-collision'`n"
    Commit-All -Repository $fixture.Retail -Message "retail claims classic path"
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "collides with Classic ownership" -Case "Retail ownership collision"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Retail-collision failure mutated the Classic worktree"
    Write-Host "PASS new Retail path collision fails before mutation"

    $fixture = New-Fixture -Name "divergent-baseline"
    $tree = Invoke-TestGit -Repository $fixture.Retail -Arguments @("rev-parse", "HEAD^{tree}")
    $orphan = ("divergent retail`n" | & git -C $fixture.Retail commit-tree $tree).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Unable to create divergent Retail fixture commit" }
    [void](Invoke-TestGit -Repository $fixture.Retail -Arguments @("checkout", "-b", "divergent", $orphan))
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "not an ancestor" -Case "Divergent baseline"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Divergent-baseline failure mutated the Classic worktree"
    Write-Host "PASS stale or divergent Retail baseline fails before mutation"

    $fixture = New-Fixture -Name "missing-gate"
    [void](Invoke-TestGit -Repository $fixture.Classic -Arguments @("rm", "tools/test-classic-prototype.ps1"))
    Commit-All -Repository $fixture.Classic -Message "classic gate missing"
    Set-RetailDelta -Fixture $fixture
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "Classic gate is missing" -Case "Missing gate"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua") -PathType Leaf) `
        -Message "Missing-gate failure deleted a baseline file before failing"
    Write-Host "PASS missing Classic gate fails before mutation"

    $fixture = New-Fixture -Name "missing-retail-source"
    Set-RetailDelta -Fixture $fixture
    [void](Invoke-TestGit -Repository $fixture.Retail -Arguments @(
        "update-index", "--skip-worktree", "MidnightSimpleUnitFrames/New.lua"
    ))
    Remove-Item -LiteralPath (Join-Path $fixture.Retail "MidnightSimpleUnitFrames/New.lua") -Force
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Retail -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Missing-source fixture is not Git-clean"
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "Tracked Retail source file is missing" -Case "Missing Retail source"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Classic "MidnightSimpleUnitFrames/Deleted.lua") -PathType Leaf) `
        -Message "Missing-source failure deleted a baseline file before failing"
    Write-Host "PASS sparse or missing Retail source fails before mutation"

    $fixture = New-Fixture -Name "push-source-guard"
    Set-RetailDelta -Fixture $fixture
    [void](Invoke-TestGit -Repository $fixture.Retail -Arguments @(
        "update-ref", "refs/remotes/origin/main", $fixture.Baseline
    ))
    $result = Invoke-Sync -Fixture $fixture -PushCapable
    Assert-Failure -Result $result -Pattern "requires Retail HEAD to equal origin/main exactly" -Case "Push source guard"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "Push-source failure mutated the Classic worktree"
    Write-Host "PASS push-capable sync rejects non-origin Retail HEAD"

    $fixture = New-Fixture -Name "gate-owner-mutation"
    Set-RetailDelta -Fixture $fixture
    $ownedRelative = $fixture.OwnedPaths[0].Replace('/', [IO.Path]::DirectorySeparatorChar)
    Write-TestFile -Root $fixture.Classic -RelativePath "tools/test-classic-prototype.ps1" -Content @"
param([string]`$RetailReferenceRoot = '')
[IO.File]::AppendAllText((Join-Path (git rev-parse --show-toplevel).Trim() '$ownedRelative'), 'mutated')
exit 0
"@
    Commit-All -Repository $fixture.Classic -Message "gate mutates owner"
    $classicHead = Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "Protected Classic file changed during Classic validation" -Case "Gate owner mutation"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")) -ceq $classicHead) `
        -Message "Gate-owner failure created a commit"
    Write-Host "PASS validation cannot mutate a Classic-owned file"

    $fixture = New-Fixture -Name "gate-override-mutation"
    Set-RetailDelta -Fixture $fixture
    $overrideRelative = $fixture.OverridePaths[0].Replace('/', [IO.Path]::DirectorySeparatorChar)
    Write-TestFile -Root $fixture.Classic -RelativePath "tools/test-classic-prototype.ps1" -Content @"
param([string]`$RetailReferenceRoot = '')
[IO.File]::AppendAllText((Join-Path (git rev-parse --show-toplevel).Trim() '$overrideRelative'), 'mutated')
exit 0
"@
    Commit-All -Repository $fixture.Classic -Message "gate mutates override"
    $classicHead = Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "Protected Classic file changed during Classic validation" `
        -Case "Gate override mutation"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("rev-parse", "HEAD")) -ceq $classicHead) `
        -Message "Gate-override failure created a commit"
    Write-Host "PASS validation cannot mutate an explicit Classic Retail override"

    $fixture = New-Fixture -Name "toc-mapping-collision"
    Write-TestFile -Root $fixture.Retail `
        -RelativePath "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_Mainline.toc" `
        -Content "## Interface: collision`n"
    Commit-All -Repository $fixture.Retail -Message "retail adds colliding toc"
    $result = Invoke-Sync -Fixture $fixture
    Assert-Failure -Result $result -Pattern "mapping is not injective" -Case "TOC mapping collision"
    Assert-True -Condition ((Invoke-TestGit -Repository $fixture.Classic -Arguments @("status", "--porcelain")) -ceq "") `
        -Message "TOC-mapping failure mutated the Classic worktree"
    Write-Host "PASS TOC mapping collision fails before mutation"

    Write-Host "Sync-ClassicRetail ownership regression suite: PASS"
} finally {
    $suiteRootFull = [IO.Path]::GetFullPath($suiteRoot)
    $expectedPrefix = $tempParent + [IO.Path]::DirectorySeparatorChar + "msuf-sync-ownership-"
    if ($suiteRootFull.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $suiteRootFull -PathType Container)) {
        Remove-Item -LiteralPath $suiteRootFull -Recurse -Force
    }
}
