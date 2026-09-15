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

$clientMatrixPath = Join-Path $root "tools/classic-client-matrix.tsv"
if (-not (Test-Path -LiteralPath $clientMatrixPath -PathType Leaf)) {
    throw "Client matrix is missing: $clientMatrixPath"
}
$clientMatrix = @(Import-Csv -LiteralPath $clientMatrixPath -Delimiter "`t")
$branches = @($clientMatrix |
    Where-Object { $_.IsClassic -ceq "true" } |
    ForEach-Object { @{ Name = $_.Suffix; Ref = $_.MirrorBranch; GameType = $_.GameType; Family = "classic" } })
if ($branches.Count -eq 0) { throw "Client matrix names no Classic client: $clientMatrixPath" }

# Blizzard_APIDocumentationGenerated is shared by every Classic family and proves
# nothing about which client actually has an API. A call from a file that the
# flavor's TOC loads does. TOC tags name game types (vanilla, tbc, mists,
# standard, ...) and family tokens (classic, mainline), separated by commas or
# spaces. A client loads a tagged file when an AllowLoadGameType tag names its
# game type or its family, and skips it when an ExcludeLoadGameType tag does.
function Get-GameTypeTokens {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Tags)
    return @($Tags -split '[,\s]+' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}
function Test-GameTypeNamed {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Tags,
        [Parameter(Mandatory = $true)][string]$GameType,
        [Parameter(Mandatory = $true)][string]$Family
    )
    $tokens = Get-GameTypeTokens -Tags $Tags
    return ($tokens -contains $GameType) -or ($tokens -contains $Family)
}
function Assert-GameTypeCallSite {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$GameType,
        [Parameter(Mandatory = $true)][string]$Family,
        [Parameter(Mandatory = $true)][string]$Toc,
        [Parameter(Mandatory = $true)][string]$Entry,
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $true)][string[]]$Needles,
        [Parameter(Mandatory = $true)][string]$Context
    )
    $tocText = Read-BranchFile $Ref $Toc
    foreach ($header in [regex]::Matches($tocText, '(?m)^##\s*(?<kind>Allow|Exclude)LoadGameType:\s*(?<tags>.+?)\s*$')) {
        $named = Test-GameTypeNamed -Tags $header.Groups['tags'].Value -GameType $GameType -Family $Family
        if (($header.Groups['kind'].Value -ceq "Allow") -ne $named) {
            throw "$Context`: $Toc does not load for game type $GameType"
        }
    }
    $lines = @($tocText -split "`n" | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ceq $Entry -or $_ -match ('^' + [regex]::Escape($Entry) + '\s+\[') })
    if ($lines.Count -ne 1) { throw "$Context`: $Toc lists '$Entry' $($lines.Count) times" }
    foreach ($tag in [regex]::Matches($lines[0], '\[(?<kind>Allow|Exclude)LoadGameType\s+(?<tags>[^\]]+)\]')) {
        $named = Test-GameTypeNamed -Tags $tag.Groups['tags'].Value -GameType $GameType -Family $Family
        if (($tag.Groups['kind'].Value -ceq "Allow") -ne $named) {
            throw "$Context`: $Entry is not loaded for game type $GameType"
        }
    }
    Assert-Contains (Read-BranchFile $Ref $File) $Needles $Context
}

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
    Assert-GameTypeCallSite -Ref $ref -GameType $target.GameType -Family $target.Family `
        -Toc "Interface/AddOns/Blizzard_FrameXMLUtil/Blizzard_FrameXMLUtil.toc" -Entry "AuraUtil.lua" `
        -File "Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua" `
        -Needles @('local AuraUtilDataProvider = C_UnitAuras;', 'CallDataProviderMethod("GetAuraSlots"', 'CallDataProviderMethod("GetAuraDataBySlot"') `
        -Context "$($target.Name) loaded C_UnitAuras slot-scan call site"
    Assert-GameTypeCallSite -Ref $ref -GameType $target.GameType -Family $target.Family `
        -Toc "Interface/AddOns/Blizzard_EditMode/Blizzard_EditMode.toc" -Entry "Shared\EditModeManager.lua" `
        -File "Interface/AddOns/Blizzard_EditMode/Shared/EditModeManager.lua" `
        -Needles @('C_EditMode.GetLayouts()', 'C_EditMode.SaveLayouts(', 'C_EditMode.SetActiveLayout(') `
        -Context "$($target.Name) loaded C_EditMode call site"
    Assert-GameTypeCallSite -Ref $ref -GameType $target.GameType -Family $target.Family `
        -Toc "Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlates.toc" -Entry "Blizzard_NamePlateAuras.lua" `
        -File "Interface/AddOns/Blizzard_NamePlates/Blizzard_NamePlateAuras.lua" `
        -Needles @('C_UnitAuras.IsAuraFilteredOutByInstanceID(') `
        -Context "$($target.Name) loaded aura filter call site"
    Write-Host "Blizzard source contract: $($target.Name) documents C_UnitAuras.GetAuraDuration and StatusBar:SetTimerDuration without a call site its client loads; MSUF treats both as optional"
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

# Game-type tripwire. Every game-type token in Blizzard's TOC tags and every
# C_GameRules Is* function is pinned for the matrix branches and the PTR
# sentinels. A new client or game mode (WoW Forever) adds a token or an Is<Mode>
# function there before addons can rely on it, so a refreshed mirror fails here
# until Game/Shared/Initialize.lua handles it. Update the pins together with that
# change; AGENTS.md has the Forever hour-0 runbook.
$knownGameTypeTokens = @("cata", "classic", "mainline", "mists", "plunderstorm", "standard", "tbc", "vanilla", "wowhack", "wrath")
$knownGameRuleFunctions = @(
    "IsCharacterlessLoginActive", "IsClassAllowedForGameMode", "IsGameModeEnabled", "IsGameRuleActive",
    "IsHardcoreActive", "IsMultiActionBarVisibilityForced", "IsPersonalResourceDisplayEnabled",
    "IsPlunderstorm", "IsSelfFoundAllowed", "IsStandard", "IsWoWHack"
)
$tripwireRefs = [Collections.Generic.List[string]]::new()
foreach ($client in $clientMatrix) {
    if (-not $tripwireRefs.Contains($client.MirrorBranch)) { $tripwireRefs.Add($client.MirrorBranch) }
}
foreach ($ref in @("upstream/ptr", "upstream/ptr2", "upstream/classic_ptr", "upstream/classic_era_ptr")) {
    if ($tripwireRefs.Contains($ref)) { continue }
    git -C $MirrorPath rev-parse --verify $ref 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $tripwireRefs.Add($ref) }
}
foreach ($ref in $tripwireRefs) {
    git -C $MirrorPath rev-parse --verify $ref 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Missing Blizzard source ref: $ref" }
    $tagLines = @(git -C $MirrorPath grep -h -E "(Allow|Exclude)LoadGameType" $ref -- "*.toc")
    if ($LASTEXITCODE -ne 0 -or $tagLines.Count -eq 0) {
        throw "$ref`: no TOC game-type tags found; the tripwire would pass without checking anything"
    }
    $tokens = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($tagLine in $tagLines) {
        foreach ($tagMatch in [regex]::Matches($tagLine, '(?:^\s*##\s*(?:Allow|Exclude)LoadGameType:\s*(?<tags>.+?)\s*$)|(?:\[(?:Allow|Exclude)LoadGameType\s+(?<tags>[^\]]+)\])')) {
            foreach ($token in (Get-GameTypeTokens -Tags $tagMatch.Groups['tags'].Value)) { [void]$tokens.Add($token) }
        }
    }
    $newTokens = @($tokens | Where-Object { $knownGameTypeTokens -notcontains $_ })
    if ($newTokens.Count -gt 0) {
        throw "$ref`: Blizzard TOCs use new game-type token(s): $($newTokens -join ', '). A new client or game mode shipped; follow the Forever hour-0 runbook in AGENTS.md, then pin the token(s) here."
    }
    $rulesDoc = Read-BranchFile $ref "Interface/AddOns/Blizzard_APIDocumentationGenerated/GameRulesDocumentation.lua"
    $functions = [Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    foreach ($functionMatch in [regex]::Matches($rulesDoc, 'Name = "(?<name>Is[A-Z][A-Za-z0-9_]*)"')) {
        [void]$functions.Add($functionMatch.Groups['name'].Value)
    }
    if ($functions.Count -eq 0) {
        throw "$ref`: GameRulesDocumentation.lua lists no Is* function; the tripwire would pass without checking anything"
    }
    $newFunctions = @($functions | Where-Object { $knownGameRuleFunctions -cnotcontains $_ })
    if ($newFunctions.Count -gt 0) {
        throw "$ref`: C_GameRules has new Is* function(s): $($newFunctions -join ', '). A new game mode may have shipped; follow the Forever hour-0 runbook in AGENTS.md, then pin the function(s) here."
    }
    Write-Host "Blizzard game-type tripwire passed: $ref ($($tokens.Count) TOC tokens, $($functions.Count) C_GameRules Is functions)"
}
