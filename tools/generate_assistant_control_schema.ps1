param(
    [switch]$Check,
    [switch]$Quick,
    [ValidateRange(1, 8)]
    [int]$Parallelism = 4,
    [string]$OutputPath = "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data.lua"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$schemaGateMutex = $null
$schemaGateMutexHeld = $false
if ($env:MSUF_ASSISTANT_SCHEMA_GATE_LOCK_HELD -ne "1") {
    $schemaGateMutex = [System.Threading.Mutex]::new(
        $false, "Local\MSUF_AssistantSchemaAndReleaseGate_v1")
    Write-Host "[gate-lock] Waiting for exclusive Assistant schema/release access..."
    try {
        try {
            $schemaGateMutexHeld = $schemaGateMutex.WaitOne([TimeSpan]::FromMinutes(30))
        } catch [System.Threading.AbandonedMutexException] {
            $schemaGateMutexHeld = $true
        }
    } catch {
        $schemaGateMutex.Dispose()
        throw
    }
    if (-not $schemaGateMutexHeld) {
        $schemaGateMutex.Dispose()
        throw "Timed out waiting for exclusive Assistant schema/release access."
    }
    Write-Host "[gate-lock] Exclusive Assistant schema/release access acquired."
}

try {
$repo = (git rev-parse --show-toplevel).Trim()
if (-not $repo) { throw "Repository root was not found." }
Set-Location $repo

$lua = Get-Command lua -ErrorAction Stop
$contexts = @(
    @("WARRIOR", 1, 71, "Arms"), @("WARRIOR", 2, 72, "Fury"), @("WARRIOR", 3, 73, "Protection"),
    @("PALADIN", 1, 65, "Holy"), @("PALADIN", 2, 66, "Protection"), @("PALADIN", 3, 70, "Retribution"),
    @("HUNTER", 1, 253, "Beast Mastery"), @("HUNTER", 2, 254, "Marksmanship"), @("HUNTER", 3, 255, "Survival"),
    @("ROGUE", 1, 259, "Assassination"), @("ROGUE", 2, 260, "Outlaw"), @("ROGUE", 3, 261, "Subtlety"),
    @("PRIEST", 1, 256, "Discipline"), @("PRIEST", 2, 257, "Holy"), @("PRIEST", 3, 258, "Shadow"),
    @("DEATHKNIGHT", 1, 250, "Blood"), @("DEATHKNIGHT", 2, 251, "Frost"), @("DEATHKNIGHT", 3, 252, "Unholy"),
    @("SHAMAN", 1, 262, "Elemental"), @("SHAMAN", 2, 263, "Enhancement"), @("SHAMAN", 3, 264, "Restoration"),
    @("MAGE", 1, 62, "Arcane"), @("MAGE", 2, 63, "Fire"), @("MAGE", 3, 64, "Frost"),
    @("WARLOCK", 1, 265, "Affliction"), @("WARLOCK", 2, 266, "Demonology"), @("WARLOCK", 3, 267, "Destruction"),
    @("MONK", 1, 268, "Brewmaster"), @("MONK", 2, 270, "Mistweaver"), @("MONK", 3, 269, "Windwalker"),
    @("DRUID", 1, 102, "Balance"), @("DRUID", 2, 103, "Feral"), @("DRUID", 3, 104, "Guardian"), @("DRUID", 4, 105, "Restoration"),
    @("DEMONHUNTER", 1, 577, "Havoc"), @("DEMONHUNTER", 2, 581, "Vengeance"), @("DEMONHUNTER", 3, 1480, "Devourer"),
    @("EVOKER", 1, 1467, "Devastation"), @("EVOKER", 2, 1468, "Preservation"), @("EVOKER", 3, 1473, "Augmentation")
)
if ($Quick) { $contexts = @($contexts | Where-Object { $_[0] -eq "MAGE" -and $_[1] -eq 1 }) }

# Build the reviewed finite matrix structurally. Individual page counts are
# learned from the first clean context and must match every later context; this
# avoids a brittle 138-entry magic map while still failing on drift.
$expectedStateIds = [System.Collections.Generic.List[string]]::new()
[void]$expectedStateIds.Add("base")
$units = @("player", "target", "focus", "boss")
$normalTools = @("layout", "filters", "blacklist")
$customTools = @("setup", "layout", "filters", "whitelist")
foreach ($unit in $units) {
    foreach ($container in @("buff", "debuff")) {
        foreach ($tool in $normalTools) { [void]$expectedStateIds.Add("unit_${unit}_${container}_${tool}") }
    }
    foreach ($index in 1..3) {
        foreach ($tool in $customTools) { [void]$expectedStateIds.Add("unit_${unit}_custom${index}_${tool}") }
    }
    [void]$expectedStateIds.Add("unit_${unit}_custom1_filters_debuff")
}
foreach ($scope in @("party", "raid", "mythicraid")) {
    foreach ($lane in @("buff", "debuff")) {
        foreach ($tool in $normalTools) { [void]$expectedStateIds.Add("gf_${scope}_${lane}_${tool}") }
    }
    [void]$expectedStateIds.Add("gf_${scope}_externals_layout")
}
foreach ($scope in @("shared", "player", "target", "focus", "boss", "party", "raid")) {
    $containers = if ($scope -in @("player", "target", "focus", "boss")) {
        @("buff", "debuff", "custom1", "custom2", "custom3")
    } else {
        @("buff", "debuff")
    }
    foreach ($container in $containers) { [void]$expectedStateIds.Add("style_${scope}_${container}") }
}
foreach ($scope in @("shared", "player", "target", "focus", "boss", "party", "raid")) {
    foreach ($lane in @("buff", "debuff")) { [void]$expectedStateIds.Add("compat_${lane}_${scope}") }
}
if ($expectedStateIds.Count -ne 138) { throw "Finite state-matrix definition drifted from 138 states." }
$expectedStateSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($stateId in $expectedStateIds) {
    if (-not $expectedStateSet.Add($stateId)) { throw "Duplicate expected collection state '$stateId'." }
}

function Resolve-StatePage([string]$StateId) {
    if ($StateId -eq "base") { return $null }
    if ($StateId -match '^unit_(player|target|focus|boss)_') { return "uf_$($Matches[1])" }
    if ($StateId -match '^gf_') { return "gf_auras" }
    if ($StateId -match '^style_') { return "auras3_styling" }
    if ($StateId -match '^compat_buff_') { return "auras3_buffs" }
    if ($StateId -match '^compat_debuff_') { return "auras3_debuffs" }
    throw "Collection state '$StateId' has no reviewed page ownership."
}

function Decode-Field([string]$Value) {
    return $Value.Replace("%0A", "`n").Replace("%0D", "`r").Replace("%09", "`t").Replace("%25", "%")
}

function Lua-String([AllowNull()][string]$Value) {
    if ($null -eq $Value) { return "''" }
    $escaped = $Value.Replace("\", "\\").Replace("'", "\'").Replace("`r", "\r").Replace("`n", "\n").Replace("`t", "\t")
    $escaped = $escaped.Replace(([string][char]30), "\030").Replace(([string][char]31), "\031")
    return "'$escaped'"
}

$records = [System.Collections.Generic.SortedDictionary[string, object]]::new([System.StringComparer]::Ordinal)
$contextRows = [System.Collections.Generic.List[object]]::new()
$referenceStateCounts = [ordered]@{}
$referenceUnionCount = $null
$previousEnvironment = @{
    Class = $env:MSUF_TEST_CLASS_TOKEN
    Spec = $env:MSUF_TEST_SPEC_INDEX
    Context = $env:MSUF_TEST_CONTEXT_ID
    Locale = $env:MSUF_TEST_LOCALE
}

# Collection is the expensive phase. Run a small bounded number of completely
# isolated Lua 5.1 processes in parallel, then feed their captured rows through
# the existing deterministic merge in the canonical context order below.
$collectedOutputs = @{}
for ($batchStart = 0; $batchStart -lt $contexts.Count; $batchStart += $Parallelism) {
    $batchEnd = [Math]::Min($batchStart + $Parallelism - 1, $contexts.Count - 1)
    $jobs = [System.Collections.Generic.List[object]]::new()
    try {
        for ($contextIndex = $batchStart; $contextIndex -le $batchEnd; $contextIndex++) {
            $context = $contexts[$contextIndex]
            $classToken = [string]$context[0]
            $specIndex = [int]$context[1]
            $specId = [int]$context[2]
            $contextId = "$classToken-$specId"
            $job = Start-Job -ScriptBlock {
                param($LuaPath, $Repository, $ClassToken, $SpecIndex, $ContextId)
                Set-Location -LiteralPath $Repository
                $env:MSUF_TEST_CLASS_TOKEN = $ClassToken
                $env:MSUF_TEST_SPEC_INDEX = [string]$SpecIndex
                $env:MSUF_TEST_CONTEXT_ID = $ContextId
                $env:MSUF_TEST_LOCALE = "enUS"
                $rows = @(& $LuaPath "tools/assistant_control_schema_collect.lua" $ContextId 2>&1 |
                    ForEach-Object { [string]$_ })
                if ($LASTEXITCODE -ne 0) {
                    throw "Schema collection failed for $ContextId.`n$($rows -join "`n")"
                }
                $rows
            } -ArgumentList $lua.Source, $repo, $classToken, $specIndex, $contextId
            $job | Add-Member -NotePropertyName MSUFContextId -NotePropertyValue $contextId
            [void]$jobs.Add($job)
        }
        Wait-Job -Job $jobs.ToArray() | Out-Null
        foreach ($job in $jobs) {
            if ($job.State -ne "Completed") {
                $failure = @(Receive-Job -Job $job -ErrorAction SilentlyContinue 2>&1 | ForEach-Object { [string]$_ })
                throw "Schema collection job failed for $($job.MSUFContextId).`n$($failure -join "`n")"
            }
            $collectedOutputs[$job.MSUFContextId] = @(Receive-Job -Job $job | ForEach-Object { [string]$_ })
        }
    } finally {
        if ($jobs.Count -gt 0) { Remove-Job -Job $jobs.ToArray() -Force -ErrorAction SilentlyContinue }
    }
}

try {
    foreach ($context in $contexts) {
        $classToken = [string]$context[0]
        $specIndex = [int]$context[1]
        $specId = [int]$context[2]
        $specName = [string]$context[3]
        $contextId = "$classToken-$specId"
        $env:MSUF_TEST_CLASS_TOKEN = $classToken
        $env:MSUF_TEST_SPEC_INDEX = [string]$specIndex
        $env:MSUF_TEST_CONTEXT_ID = $contextId
        $env:MSUF_TEST_LOCALE = "enUS"

        $output = @($collectedOutputs[$contextId])
        if ($output.Count -eq 0) { throw "Schema collection produced no output for $contextId." }

        $schemaLines = @($output | Where-Object { $_.StartsWith("CONTEXT`t") -or $_.StartsWith("RECORD`t") })
        if (@($schemaLines | Where-Object { $_.StartsWith("CONTEXT`t") }).Count -ne 1) {
            throw "Schema collection for $contextId did not emit exactly one context header."
        }
        $stateLines = @($output | Where-Object { $_.StartsWith("STATE`t") })
        if ($stateLines.Count -ne $expectedStateIds.Count) {
            throw "Schema collection for $contextId emitted $($stateLines.Count) states; expected $($expectedStateIds.Count)."
        }
        $isReferenceContext = $referenceStateCounts.Count -eq 0
        $seenStates = @{}
        for ($stateIndex = 0; $stateIndex -lt $stateLines.Count; $stateIndex++) {
            $line = $stateLines[$stateIndex]
            $stateFields = @($line.Split("`t") | ForEach-Object { Decode-Field $_ })
            if ($stateFields.Count -ne 3) { throw "Malformed collection state row for ${contextId}: $line" }
            $stateId, $stateCount = $stateFields[1], [int]$stateFields[2]
            $expectedStateId = $expectedStateIds[$stateIndex]
            if ($stateId -cne $expectedStateId) {
                throw "Collection state order drift for ${contextId}: expected '$expectedStateId', got '$stateId'."
            }
            if ($seenStates.ContainsKey($stateId)) { throw "Duplicate collection state '$stateId' for $contextId." }
            if ($stateCount -le 0) { throw "Collection state '$stateId' for $contextId captured no controls." }
            if ($isReferenceContext) {
                $referenceStateCounts[$stateId] = $stateCount
            } elseif ($stateCount -ne [int]$referenceStateCounts[$stateId]) {
                throw "Collection state '$stateId' for $contextId has $stateCount controls; reference context has $($referenceStateCounts[$stateId])."
            }
            $seenStates[$stateId] = $stateCount
        }
        $unionLines = @($output | Where-Object { $_.StartsWith("UNION`t") })
        if ($unionLines.Count -ne 1) { throw "Schema collection for $contextId did not emit exactly one union summary." }
        $unionFields = @($unionLines[0].Split("`t") | ForEach-Object { Decode-Field $_ })
        if ($unionFields.Count -ne 2) { throw "Malformed collection union for ${contextId}." }
        $contextUnionCount = [int]$unionFields[1]
        if ($contextUnionCount -le 0) { throw "Schema collection union for $contextId is empty." }
        if ($null -eq $referenceUnionCount) { $referenceUnionCount = $contextUnionCount }
        elseif ($contextUnionCount -ne $referenceUnionCount) {
            throw "Schema collection union for $contextId has $contextUnionCount controls; reference context has $referenceUnionCount."
        }
        $recordLines = @($schemaLines | Where-Object { $_.StartsWith("RECORD`t") })
        if ($recordLines.Count -ne $contextUnionCount) {
            throw "Schema collection for $contextId emitted $($recordLines.Count) records for a declared $contextUnionCount-control union."
        }
        $contextRows.Add([pscustomobject]@{ Id=$contextId; Class=$classToken; SpecIndex=$specIndex; SpecId=$specId; SpecName=$specName; Locale="enUS" })

        $observedMembershipStates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($line in $recordLines) {
            $fields = @($line.Split("`t") | ForEach-Object { Decode-Field $_ })
            if ($fields.Count -ne 31) { throw "Malformed schema row for ${contextId}: expected 31 fields, got $($fields.Count)." }
            $semanticId = $fields[1]
            if (-not $semanticId) { throw "A control in $contextId has no semantic ID." }
            $membership = $fields[30]
            $membershipSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            if ($membership -eq "*") {
                foreach ($stateId in $expectedStateIds) {
                    [void]$membershipSet.Add($stateId)
                    [void]$observedMembershipStates.Add($stateId)
                }
            } else {
                if (-not $membership) { throw "Control '$semanticId' in $contextId has empty state membership." }
                foreach ($stateId in $membership.Split([char]',', [System.StringSplitOptions]::RemoveEmptyEntries)) {
                    if (-not $expectedStateSet.Contains($stateId)) {
                        throw "Control '$semanticId' in $contextId references unknown state '$stateId'."
                    }
                    if (-not $membershipSet.Add($stateId)) {
                        throw "Control '$semanticId' in $contextId repeats state '$stateId'."
                    }
                    [void]$observedMembershipStates.Add($stateId)
                    $statePage = Resolve-StatePage $stateId
                    if ($statePage -and $fields[5] -cne $statePage) {
                        throw "Control '$semanticId' from page '$($fields[5])' leaked into page-local state '$stateId' owned by '$statePage'."
                    }
                }
                $canonicalMembership = [System.Collections.Generic.List[string]]::new()
                foreach ($stateId in $expectedStateIds) {
                    if ($membershipSet.Contains($stateId)) { [void]$canonicalMembership.Add($stateId) }
                }
                if ([string]::Join(",", [string[]]$canonicalMembership) -cne $membership) {
                    throw "Control '$semanticId' in $contextId has non-deterministic state membership order '$membership'."
                }
            }

            if (-not $records.ContainsKey($semanticId)) {
                $record = [pscustomobject]@{
                    Fields = $fields[1..30]
                    Contexts = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
                }
                $records.Add($semanticId, $record)
            } else {
                $record = $records[$semanticId]
                foreach ($index in 1..18) {
                    if ($record.Fields[$index] -cne $fields[$index + 1]) {
                        throw "Semantic identity drift for '$semanticId' in $contextId (field $($index + 2))."
                    }
                }
                foreach ($metadataIndex in 19..20) {
                    $oldMetadata, $newMetadata = [string]$record.Fields[$metadataIndex], [string]$fields[$metadataIndex + 1]
                    if ($oldMetadata -and $newMetadata -and $oldMetadata -cne $newMetadata) {
                        throw "Semantic metadata drift for '$semanticId' in $contextId (field $($metadataIndex + 2))."
                    }
                    if (-not $oldMetadata -and $newMetadata) { $record.Fields[$metadataIndex] = $newMetadata }
                }
                if ($record.Fields[21] -cne $fields[22]) {
                    $valueSet = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
                    foreach ($item in @($record.Fields[21], $fields[22])) {
                        foreach ($valueRow in ([string]$item).Split([char]31, [System.StringSplitOptions]::RemoveEmptyEntries)) { [void]$valueSet.Add($valueRow) }
                    }
                    $record.Fields[21] = [string]::Join(([string][char]31), $valueSet)
                }
                foreach ($contractIndex in 22..28) {
                    if ($record.Fields[$contractIndex] -cne $fields[$contractIndex + 1]) {
                        throw "Semantic action/domain contract drift for '$semanticId' in $contextId (field $($contractIndex + 2))."
                    }
                }
                if ($record.Fields[29] -cne $fields[30]) {
                    throw "Collection-state membership drift for '$semanticId' in $contextId."
                }
            }
            [void]$record.Contexts.Add($contextId)
        }
        foreach ($stateId in $expectedStateIds) {
            if (-not $observedMembershipStates.Contains($stateId)) {
                throw "Collection state '$stateId' for $contextId is absent from every emitted record membership."
            }
        }
        Write-Host ("collected {0}: {1} union controls across {2} finite states" -f $contextId,
            $recordLines.Count, $seenStates.Count)
    }
} finally {
    $env:MSUF_TEST_CLASS_TOKEN = $previousEnvironment.Class
    $env:MSUF_TEST_SPEC_INDEX = $previousEnvironment.Spec
    $env:MSUF_TEST_CONTEXT_ID = $previousEnvironment.Context
    $env:MSUF_TEST_LOCALE = $previousEnvironment.Locale
}

if ($records.Count -lt [int]$referenceUnionCount) {
    throw "Cross-context schema union has fewer controls than one context: $($records.Count) < $referenceUnionCount."
}

$guidedControls = [System.Collections.Generic.List[string]]::new()
$readOnlySettings = [System.Collections.Generic.List[string]]::new()
foreach ($pair in $records.GetEnumerator()) {
    $fields = $pair.Value.Fields
    if ($fields[11] -ceq "guided") { [void]$guidedControls.Add([string]$pair.Key) }
    if ($fields[6] -ceq "setting" -and $fields[11] -ceq "readOnly") {
        [void]$readOnlySettings.Add([string]$pair.Key)
    }
}
if ($guidedControls.Count -gt 0) {
    throw "Release schema contains $($guidedControls.Count) unowned guided controls: $([string]::Join(', ', $guidedControls))"
}
if ($readOnlySettings.Count -gt 0) {
    throw "Release schema contains $($readOnlySettings.Count) read-only settings: $([string]::Join(', ', $readOnlySettings))"
}

$builder = [System.Text.StringBuilder]::new()
[void]$builder.AppendLine("-- Generated by tools/generate_assistant_control_schema.ps1. Do not edit by hand.")
[void]$builder.AppendLine("local _, MSUF = ...")
[void]$builder.AppendLine("MSUF = MSUF or _G.MSUF_NS or {}")
[void]$builder.AppendLine("MSUF.Assistant = MSUF.Assistant or {}")
[void]$builder.AppendLine("local Data = { version = 3 }")
[void]$builder.AppendLine("Data.columns = { 'semanticId', 'controlId', 'familyId', 'memberKey', 'pageKey', 'controlPath', 'classification', 'kind', 'settingKey', 'actionKey', 'navigationKey', 'safety', 'valueKind', 'min', 'max', 'step', 'percentIsValue', 'confirmRequired', 'identityStable', 'label', 'help', 'values', 'actionFixedArgs', 'actionInputArg', 'actionInputKind', 'actionInputDomain', 'storageUnit', 'displayUnit', 'displayScale', 'states', 'contexts' }")
[void]$builder.AppendLine("Data.collectionStates = {")
foreach ($stateId in $expectedStateIds) {
    [void]$builder.AppendLine(("    {{ {0}, {1} }}," -f (Lua-String $stateId), $referenceStateCounts[$stateId]))
}
[void]$builder.AppendLine("}")
[void]$builder.AppendLine("Data.collectionUnionControls = $($records.Count)")
[void]$builder.AppendLine("Data.contexts = {")
foreach ($context in $contextRows) {
    [void]$builder.AppendLine(("    {{ {0}, {1}, {2}, {3}, {4}, {5} }}," -f (Lua-String $context.Id), (Lua-String $context.Class), $context.SpecIndex, $context.SpecId, (Lua-String $context.SpecName), (Lua-String $context.Locale)))
}
[void]$builder.AppendLine("}")
[void]$builder.AppendLine("Data.records = {")
foreach ($pair in $records.GetEnumerator()) {
    $record = $pair.Value
    $contextValue = if ($record.Contexts.Count -eq $contexts.Count) { "*" } else { [string]::Join(",", $record.Contexts) }
    $encoded = [System.Collections.Generic.List[string]]::new()
    foreach ($field in $record.Fields) { $encoded.Add((Lua-String ([string]$field))) }
    $encoded.Add((Lua-String $contextValue))
    [void]$builder.AppendLine("    { $([string]::Join(', ', $encoded)) },")
}
[void]$builder.AppendLine("}")
[void]$builder.AppendLine("Data.packs = {")
[void]$builder.AppendLine("    enUS = { found = 'I found {label}.', current = 'The current value is {value}.', unavailable = 'That control is not available in the current context.', confirm = 'Please confirm before I change {label}.', guided = 'I can guide you to {label}, but I will not change it automatically.', readOnly = '{label} is available for guidance or inspection only.' },")
[void]$builder.AppendLine("    deDE = { found = 'Ich habe {label} gefunden.', current = 'Der aktuelle Wert ist {value}.', unavailable = 'Dieses Steuerelement ist im aktuellen Kontext nicht verfuegbar.', confirm = 'Bitte bestaetige, bevor ich {label} aendere.', guided = 'Ich kann dich zu {label} fuehren, aendere es aber nicht automatisch.', readOnly = '{label} ist nur zur Anleitung oder Einsicht verfuegbar.' },")
[void]$builder.AppendLine("}")
[void]$builder.AppendLine("MSUF.Assistant.ControlSchemaData = Data")

$content = $builder.ToString().Replace("`r`n", "`n")
$absoluteOutput = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repo $OutputPath }
$existing = if (Test-Path -LiteralPath $absoluteOutput) { [IO.File]::ReadAllText($absoluteOutput) } else { $null }
if ($Check) {
    if ($null -eq $existing) { throw "Generated schema is missing: $absoluteOutput" }
    if ($existing.Replace("`r`n", "`n") -cne $content) { throw "Generated control schema is stale. Run tools/generate_assistant_control_schema.ps1." }
    Write-Host "assistant control schema is current: $($records.Count) controls across $($contexts.Count) contexts and $($expectedStateIds.Count) finite states"
} else {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($absoluteOutput)) | Out-Null
    [IO.File]::WriteAllText($absoluteOutput, $content, [Text.UTF8Encoding]::new($false))
    Write-Host "wrote $absoluteOutput ($($records.Count) controls, $($contexts.Count) contexts, $($expectedStateIds.Count) finite states, $([Text.Encoding]::UTF8.GetByteCount($content)) bytes)"
}
} finally {
    if ($schemaGateMutex) {
        try {
            if ($schemaGateMutexHeld) { $schemaGateMutex.ReleaseMutex() }
        } finally {
            $schemaGateMutex.Dispose()
        }
    }
}
