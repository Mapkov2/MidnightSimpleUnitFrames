[CmdletBinding()]
param(
    [string]$MirrorPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = (git rev-parse --show-toplevel).Trim()
if (-not $MirrorPath) {
    $MirrorPath = Join-Path $root "_local_workflows/references/wow-ui-source"
}
$MirrorPath = [IO.Path]::GetFullPath($MirrorPath)
if (-not (Test-Path -LiteralPath (Join-Path $MirrorPath ".git") -PathType Container)) {
    throw "Blizzard UI source mirror is missing: $MirrorPath"
}

function Read-BranchFile {
    param(
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $content = git -C $MirrorPath show ("{0}:{1}" -f $Branch, $Path)
    if ($LASTEXITCODE -ne 0) { throw "Cannot read $Branch`:$Path" }
    return ($content -join "`n")
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [Parameter(Mandatory = $true)][string]$Context
    )
    foreach ($needle in $Needles) {
        if ($Content.IndexOf($needle, [StringComparison]::Ordinal) -lt 0) {
            throw "$Context is missing '$needle'"
        }
    }
}

$branches = @(
    @{ Name = "Vanilla"; Ref = "upstream/classic_era" },
    @{ Name = "Mists"; Ref = "upstream/classic" },
    @{ Name = "TBC"; Ref = "upstream/classic_anniversary" }
)

foreach ($target in $branches) {
    $ref = $target.Ref
    git -C $MirrorPath rev-parse --verify $ref | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing Blizzard source ref: $ref" }

    $unitFrame = Read-BranchFile $ref "Interface/AddOns/Blizzard_UnitFrame/Classic/UnitFrame.lua"
    Assert-Contains $unitFrame @(
        'UNIT_HEAL_PREDICTION',
        'UNIT_ABSORB_AMOUNT_CHANGED',
        'UNIT_HEAL_ABSORB_AMOUNT_CHANGED',
        'UnitGetIncomingHeals(frame.unit',
        'UnitGetTotalAbsorbs(frame.unit)',
        'UnitGetTotalHealAbsorbs(frame.unit)',
        'castID, notInterruptible, spellID = UnitCastingInfo(unit)'
    ) "$($target.Name) UnitFrame"

    $auraUtil = Read-BranchFile $ref "Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua"
    Assert-Contains $auraUtil @(
        'IncludeNameplateOnly = "INCLUDE_NAME_PLATE_ONLY"',
        'Cancelable = "CANCELABLE"',
        'NotCancelable = "NOT_CANCELABLE"',
        'ExternalDefensive = "EXTERNAL_DEFENSIVE"',
        'CrowdControl = "CROWD_CONTROL"',
        'RaidInCombat = "RAID_IN_COMBAT"',
        'RaidPlayerDispellable = "RAID_PLAYER_DISPELLABLE"',
        'BigDefensive = "BIG_DEFENSIVE"',
        'auraData.isStealable',
        'auraData.isBossAura'
    ) "$($target.Name) AuraUtil"

    $unitAuraAPI = Read-BranchFile $ref "Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua"
    Assert-Contains $unitAuraAPI @(
        'Name = "GetAuraDataBySlot"',
        'Name = "GetAuraDuration"',
        'Name = "GetAuraSlots"',
        'Name = "IsAuraFilteredOutByInstanceID"'
    ) "$($target.Name) UnitAura API"

    $statusBarAPI = Read-BranchFile $ref "Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua"
    Assert-Contains $statusBarAPI @('Name = "SetTimerDuration"') "$($target.Name) status-bar timer API"

    $editModeAPI = Read-BranchFile $ref "Interface/AddOns/Blizzard_APIDocumentationGenerated/EditModeManagerDocumentation.lua"
    Assert-Contains $editModeAPI @(
        'Namespace = "C_EditMode"',
        'Name = "GetLayouts"',
        'Name = "SaveLayouts"',
        'Name = "SetActiveLayout"'
    ) "$($target.Name) Edit Mode API"
    $editModeSystemXML = Read-BranchFile $ref "Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.xml"
    Assert-Contains $editModeSystemXML @(
        'Enum.EditModeSystem.DamageMeter'
    ) "$($target.Name) Edit Mode Damage Meter system"
    $editModeSystems = Read-BranchFile $ref "Interface/AddOns/Blizzard_EditMode/Shared/EditModeSystemTemplates.lua"
    Assert-Contains $editModeSystems @(
        'self:SetBarHeight(barHeight)',
        'self:SetBarSpacing(barSpacing)',
        'self:SetWindowTransparency(transparency)',
        'self:SetShowBarIcons(showBarIcons)',
        'self:SetUseClassColor(useClassColor)',
        'self:SetTextSize(textSize)',
        'self:SetBackgroundTransparency(backgroundTransparency)'
    ) "$($target.Name) Edit Mode Damage Meter"

    $compact = Read-BranchFile $ref "Interface/AddOns/Blizzard_CompactRaidFrames/Classic/Blizzard_CompactRaidFrameManager.lua"
    Assert-Contains $compact @(
        'function CompactRaidFrameManager_UpdateOptionsFlowContainer(self)',
        'local container = self.displayFrame.optionsFlowContainer'
    ) "$($target.Name) CompactRaidFrameManager"

    $combo = Read-BranchFile $ref "Interface/AddOns/Blizzard_UnitFrame/Classic/ComboFrame.xml"
    Assert-Contains $combo @('name="ComboFrame"') "$($target.Name) ComboFrame"

    $petFrame = Read-BranchFile $ref "Interface/AddOns/Blizzard_UnitFrame/Classic/PetFrame.lua"
    Assert-Contains $petFrame @(
        'self:RegisterEvent("UNIT_HAPPINESS")',
        'local happiness, damagePercentage, loyaltyRate = GetPetHappiness()',
        'PetFrameHappinessTexture:SetTexCoord(0.375, 0.5625, 0, 0.359375)',
        'PetFrameHappinessTexture:SetTexCoord(0.1875, 0.375, 0, 0.359375)',
        'PetFrameHappinessTexture:SetTexCoord(0, 0.1875, 0, 0.359375)'
    ) "$($target.Name) Pet Happiness"
    $petFrameXML = Read-BranchFile $ref "Interface/AddOns/Blizzard_UnitFrame/Classic/PetFrame.xml"
    Assert-Contains $petFrameXML @('Interface\PetPaperDollFrame\UI-PetHappiness') "$($target.Name) Pet Happiness texture"
    if ($target.Name -eq "Mists") {
        Assert-Contains $petFrame @('If Pet Happiness is disabled (e.g., Cata+), then happiness should be nil') "Mists disabled Pet Happiness contract"
    }
    if ($target.Name -eq "Mists") {
        $resourceFiles = @(
            @{ Path = "Interface/AddOns/Blizzard_UnitFrame/Cata/EclipseBarFrame.xml"; Name = 'name="EclipseBarFrame"' },
            @{ Path = "Interface/AddOns/Blizzard_UnitFrame/Cata/RuneFrame.xml"; Name = 'name="RuneFrame"' },
            @{ Path = "Interface/AddOns/Blizzard_UnitFrame/Mists/PaladinPowerBar.xml"; Name = 'name="PaladinPowerBar"' },
            @{ Path = "Interface/AddOns/Blizzard_UnitFrame/Mists/MonkHarmonyBar.xml"; Name = 'name="MonkHarmonyBar"' },
            @{ Path = "Interface/AddOns/Blizzard_UnitFrame/Mists/PriestBar.xml"; Name = 'name="PriestBarFrame"' },
            @{ Path = "Interface/AddOns/Blizzard_UnitFrame/Mists/ShardBar.xml"; Name = 'name="WarlockPowerFrame"' }
        )
        foreach ($resource in $resourceFiles) {
            $content = Read-BranchFile $ref $resource.Path
            Assert-Contains $content @($resource.Name) "$($target.Name) $($resource.Path)"
        }
    }

    Write-Host "Blizzard source contract passed: $($target.Name) ($ref)"
}

# PTR refs are drift sentinels only. They are not packaged as separate clients,
# but their aura contracts warn us before a live branch changes underneath MSUF.
foreach ($ref in @("upstream/ptr", "upstream/ptr2", "upstream/classic_ptr", "upstream/classic_era_ptr")) {
    git -C $MirrorPath rev-parse --verify $ref 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { continue }
    $unitAuraAPI = Read-BranchFile $ref "Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua"
    Assert-Contains $unitAuraAPI @(
        'Name = "GetAuraDataBySlot"',
        'Name = "GetAuraDuration"',
        'Name = "GetAuraSlots"',
        'Name = "IsAuraFilteredOutByInstanceID"'
    ) "$ref UnitAura API"
    $statusBarAPI = Read-BranchFile $ref "Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleStatusBarAPIDocumentation.lua"
    Assert-Contains $statusBarAPI @('Name = "SetTimerDuration"') "$ref status-bar timer API"
    Write-Host "Blizzard PTR aura drift contract passed: $ref"
}
