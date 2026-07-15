[CmdletBinding()]
param(
    [string]$OutputDirectory = "tools/AssistantTraining/out-release-gate"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$expectedAssistantScriptCount = 328
$expectedAssistantOrderSha256 = "6D93B5BB79D3EDAFDF14D2838216E6ACEE814645ED37AFDEFB28863A9F232A39"
$startingLocation = Get-Location
$previousEnglishSuiteFull = $env:MSUF_ENGLISH_SUITE_FULL
$previousPerfMultiplier = $env:MSUF_ASSISTANT_PERF_BUDGET_MULTIPLIER
$previousSchemaGateLockHeld = $env:MSUF_ASSISTANT_SCHEMA_GATE_LOCK_HELD

function Resolve-RepositoryRoot {
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
    $required = @(
        ".github/scripts/msuf_static_checks.py",
        "MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.toc",
        "MidnightSimpleUnitFrames_Assistant/MidnightSimpleUnitFrames_Assistant.toc",
        "MidnightSimpleUnitFrames_Assistant/MSUF_AssistantRuntime.xml"
    )
    foreach ($relative in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $candidate $relative) -PathType Leaf)) {
            throw "Repository root resolution failed; missing '$relative' below '$candidate'."
        }
    }
    return $candidate
}

function Require-File {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $path = Join-Path $script:repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release-gate file is missing: $RelativePath"
    }
    return $path
}

function Require-TrackedFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    [void](Require-File -RelativePath $RelativePath)
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $indexOutput = @(& git -C $script:repoRoot ls-files --error-unmatch -- $RelativePath 2>&1 |
            ForEach-Object { [string]$_ })
        $indexExitCode = $LASTEXITCODE
        $headOutput = @(& git -C $script:repoRoot cat-file -e ("HEAD:{0}" -f $RelativePath) 2>&1 |
            ForEach-Object { [string]$_ })
        $headExitCode = $LASTEXITCODE
        $diffOutput = @(& git -C $script:repoRoot diff --quiet HEAD -- $RelativePath 2>&1 |
            ForEach-Object { [string]$_ })
        $diffExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($indexExitCode -ne 0) {
        throw "Required release-gate file is not Git-tracked: $RelativePath`n$($indexOutput -join "`n")"
    }
    if ($headExitCode -ne 0) {
        throw "Required release-gate file is not committed in HEAD: $RelativePath`n$($headOutput -join "`n")"
    }
    if ($diffExitCode -ne 0) {
        throw "Required release-gate file differs from HEAD: $RelativePath`n$($diffOutput -join "`n")"
    }
}

function Resolve-RequiredTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$VersionArguments,
        [Parameter(Mandatory = $true)][string]$VersionPattern,
        [Parameter(Mandatory = $true)][string]$Requirement
    )

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) { throw "$Requirement is required on PATH ('$Name' was not found)." }

    # Lua 5.1 writes `-v` to stderr.  Keep that version banner in the captured
    # output without letting Windows PowerShell promote it to a terminating
    # NativeCommandError while this gate runs under ErrorActionPreference=Stop.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $versionOutput = @(& $command.Source @VersionArguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $versionText = ($versionOutput -join " ").Trim()
    if ($exitCode -ne 0 -or $versionText -notmatch $VersionPattern) {
        throw "$Requirement is required; '$($command.Source)' reported '$versionText'."
    }
    return $command.Source
}

function Get-ReferenceHash {
    param([Parameter(Mandatory = $true)][string[]]$References)

    $payload = (@($References | ForEach-Object { $_.Trim().Replace('\', '/') }) -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($payload)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha.Dispose()
    }
}

function Assert-GraphifySourceInventoryFreshness {
    param(
        [Parameter(Mandatory = $true)][string]$SourceSnapshotScript,
        [Parameter(Mandatory = $true)][string]$InventoryPath
    )

    Write-Host "[gate] Graphify source-snapshot freshness"
    $actualRows = @(& $SourceSnapshotScript -RepositoryRoot $script:repoRoot)
    if ($actualRows.Count -ne 1) {
        throw "Graphify source snapshot calculator returned $($actualRows.Count) objects; expected exactly one."
    }
    $actual = $actualRows[0]

    $inventoryText = [System.IO.File]::ReadAllText($InventoryPath)
    $blockMatch = [regex]::Match(
        $inventoryText,
        'sourceSnapshot\s*=\s*\{(?<body>.*?)\}\s*,',
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $blockMatch.Success) {
        throw "Tracked Graphify inventory has no sourceSnapshot metadata block."
    }
    $body = $blockMatch.Groups['body'].Value

    $readString = {
        param([string]$Name)
        $match = [regex]::Match($body, ('\b{0}\s*=\s*"([^"]+)"' -f [regex]::Escape($Name)))
        if (-not $match.Success) { throw "Tracked Graphify source snapshot is missing '$Name'." }
        return $match.Groups[1].Value
    }
    $readInteger = {
        param([string]$Name)
        $match = [regex]::Match($body, ('\b{0}\s*=\s*(\d+)' -f [regex]::Escape($Name)))
        if (-not $match.Success) { throw "Tracked Graphify source snapshot is missing '$Name'." }
        return [int]$match.Groups[1].Value
    }

    $tracked = [pscustomobject]@{
        schemaVersion = & $readInteger "schemaVersion"
        manifestFormat = & $readString "manifestFormat"
        algorithm = & $readString "algorithm"
        manifestSha256 = & $readString "manifestSha256"
        fileCount = & $readInteger "fileCount"
    }
    if ($tracked.schemaVersion -ne 1 -or
        $tracked.manifestFormat -ne "msuf-addon-source-sha256-v1" -or
        $tracked.algorithm -ne "SHA256" -or
        $tracked.manifestSha256 -notmatch '^[0-9A-F]{64}$' -or
        $tracked.fileCount -le 0) {
        throw "Tracked Graphify inventory has invalid source-snapshot metadata."
    }

    foreach ($property in @("schemaVersion", "manifestFormat", "algorithm", "manifestSha256", "fileCount")) {
        if ($tracked.$property -ne $actual.$property) {
            throw "Tracked Graphify inventory is stale for addon source ($property tracked='$($tracked.$property)' current='$($actual.$property)'). Rebuild through tools/update_assistant_graphify_snapshot.ps1, then regenerate and review the tracked inventory."
        }
    }
    Write-Host ("  PASS: {0} files, SHA256 {1}" -f $actual.fileCount, $actual.manifestSha256)
}

function Get-AssistantManifestFiles {
    $assistantRoot = Join-Path $script:repoRoot "MidnightSimpleUnitFrames_Assistant"
    $manifestPath = Join-Path $assistantRoot "MSUF_AssistantRuntime.xml"
    $manifest = [System.IO.File]::ReadAllText($manifestPath)
    $matches = [regex]::Matches($manifest, '<Script\s+file="([^"]+)"')
    if ($matches.Count -ne $expectedAssistantScriptCount) {
        throw "Assistant manifest must contain exactly $expectedAssistantScriptCount Lua scripts; found $($matches.Count)."
    }

    $references = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $files = [System.Collections.Generic.List[string]]::new()
    $rootPrefix = $assistantRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($match in $matches) {
        $reference = $match.Groups[1].Value.Trim().Replace('\', '/')
        if (-not $reference.EndsWith('.lua', [System.StringComparison]::OrdinalIgnoreCase) -or
            $reference -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($reference)) {
            throw "Unsafe or non-Lua Assistant manifest reference: $reference"
        }
        if (-not $seen.Add($reference)) { throw "Duplicate Assistant manifest reference: $reference" }

        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $assistantRoot $reference))
        if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Assistant manifest reference escapes its addon: $reference"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Assistant manifest references a missing Lua file: $reference"
        }
        $references.Add($reference)
        $files.Add($fullPath)
    }

    $hash = Get-ReferenceHash -References $references.ToArray()
    if ($hash -ne $expectedAssistantOrderSha256) {
        throw "Assistant manifest load-order hash mismatch. Expected $expectedAssistantOrderSha256, got $hash."
    }
    return $files.ToArray()
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    Write-Host ("[gate] {0}" -f $Label)
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $details = ($output -join "`n").Trim()
        if (-not $details) { $details = "No diagnostic output was produced." }
        throw "$Label failed with exit code $exitCode.`n$details"
    }

    $summary = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Last 1)
    if ($summary.Count -gt 0) { Write-Host ("  PASS: {0}" -f $summary[0].Trim()) }
    else { Write-Host "  PASS" }
}

function Test-AssistantManifestCompilation {
    param(
        [Parameter(Mandatory = $true)][string]$Compiler,
        [Parameter(Mandatory = $true)][string[]]$Files
    )

    Write-Host "[gate] Assistant manifest Lua 5.1 compilation"
    $compiled = 0
    foreach ($path in $Files) {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            throw "Assistant manifest Lua source has a UTF-8 BOM: $path"
        }
        $output = @(& $Compiler -p $path 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Lua 5.1 compilation failed for '$path'.`n$($output -join "`n")"
        }
        $compiled++
    }
    if ($compiled -ne $expectedAssistantScriptCount) {
        throw "Manifest compilation was incomplete: compiled $compiled of $expectedAssistantScriptCount files."
    }
    Write-Host "  PASS: compiled all $compiled manifest Lua files"
}

$repoRoot = Resolve-RepositoryRoot
$lua = Resolve-RequiredTool -Name "lua" -VersionArguments @("-v") `
    -VersionPattern 'Lua 5\.1(?:\.|\s|$)' -Requirement "Lua 5.1 interpreter"
$luac = Resolve-RequiredTool -Name "luac" -VersionArguments @("-v") `
    -VersionPattern 'Lua 5\.1(?:\.|\s|$)' -Requirement "Lua 5.1 compiler"
$python = Resolve-RequiredTool -Name "python" -VersionArguments @("--version") `
    -VersionPattern 'Python 3\.' -Requirement "Python 3 interpreter"
$powerShell = (Get-Process -Id $PID).Path
if (-not $powerShell) { throw "Could not resolve the current PowerShell executable." }

$outputPath = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    [System.IO.Path]::GetFullPath($OutputDirectory)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDirectory))
}
if ($outputPath -eq $repoRoot) { throw "OutputDirectory must not be the repository root." }

$pythonGates = @(
    [pscustomobject]@{ Label = "repository Python static checks"; Path = ".github/scripts/msuf_static_checks.py" },
    [pscustomobject]@{ Label = "AutoCoverage generated-manifest freshness"; Path = "tools/assistant_autocoverage_manifest_regression.py" }
)

# Every test is named explicitly. A removed, renamed, ignored, or forgotten test
# is a hard failure before the expensive schema and training passes begin.
$luaGates = @(
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_control_catalog_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_control_catalog_contract_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_control_catalog_global_scope_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_control_catalog_unit_group_aura_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_graphify_inventory_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_v1_catalog_crosswalk.lua"; Args = @("--graphify-inventory") },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_setting_graph_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "graph"; Path = "tools/assistant_setting_graph_audit.lua"; Args = @() },

    [pscustomobject]@{ Category = "no-menu"; Path = "tools/assistant_v1_lod_schema_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "no-menu"; Path = "tools/assistant_lod_zero_idle_smoke.lua"; Args = @() },

    [pscustomobject]@{ Category = "schema"; Path = "tools/assistant_control_schema_collect_semantics_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "schema/mode"; Path = "tools/assistant_control_schema_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "schema"; Path = "tools/assistant_control_schema_conversation_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "schema/transaction"; Path = "tools/assistant_control_schema_transaction_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "schema/search"; Path = "tools/assistant_control_schema_retrieval_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "schema/navigation"; Path = ".github/scripts/tests/assistant_schema_navigation_state_smoke.lua"; Args = @() },

    [pscustomobject]@{ Category = "search"; Path = "tools/assistant_menu_search_coverage_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "search"; Path = "tools/assistant_search_workspace_route_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "search/editmode"; Path = "tools/assistant_group_page_route_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "search"; Path = "tools/assistant_search_readability_context_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "search"; Path = "tools/assistant_knowledge_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "page"; Path = "tools/assistant_page_navigation_matrix.lua"; Args = @() },
    [pscustomobject]@{ Category = "page/guide/no-menu"; Path = "tools/assistant_menu_guide_routing_audit.lua"; Args = @() },

    [pscustomobject]@{ Category = "controller"; Path = "tools/assistant_exact_setting_control_contract.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller"; Path = "tools/assistant_parser_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller/color"; Path = ".github/scripts/tests/assistant_color_picker_bridge_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller/color"; Path = ".github/scripts/tests/assistant_bar_gradient_reset_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller/layer"; Path = ".github/scripts/tests/layer_contract_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller"; Path = "tools/assistant_actual_parse_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller"; Path = ".github/scripts/tests/assistant_three_controller_gaps_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller"; Path = "tools/assistant_autocoverage_identity_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller/safety"; Path = "tools/assistant_autocoverage_safety_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller/safety"; Path = "tools/assistant_readonly_submit_e2e.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller/safety"; Path = "tools/assistant_profile_copy_readonly_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "controller"; Path = "tools/assistant_channel_tick_controller_smoke.lua"; Args = @() },

    [pscustomobject]@{ Category = "action-input"; Path = "tools/assistant_action_input_contract_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "action-input"; Path = "tools/assistant_action_alias_input_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "action-input"; Path = "tools/assistant_action_parse_audit.lua"; Args = @() },

    [pscustomobject]@{ Category = "transaction"; Path = "tools/assistant_transaction_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "transaction"; Path = "tools/assistant_owner_transaction_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "transaction"; Path = "tools/assistant_aura_filter_transaction_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "transaction"; Path = "tools/assistant_failure_recovery_smoke.lua"; Args = @() },

    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_router_safety_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_semantic_write_safety_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_prompt_intent_safety_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_nested_persisted_state_audit.lua"; Args = @("--require-complete") },
    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_shell_contract_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_reported_crash_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "safety"; Path = "tools/assistant_pending_choice_fresh_command_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "safety/page"; Path = "tools/assistant_pending_setting_page_precedence_smoke.lua"; Args = @() },

    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_context_alignment_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = ".github/scripts/tests/assistant_context_object_followup_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_natural_setting_conversation_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_planning_followup_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_real_prompt_output_audit.lua"; Args = @("--quiet") },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_aura_filter_conversation_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_name_dots_semantic_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_open_ended_setting_idea_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_open_ended_aura_growth_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_status_semantics_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation"; Path = "tools/assistant_nomatch_learning_audit.lua"; Args = @() },

    [pscustomobject]@{ Category = "locale"; Path = "tools/assistant_dialog_locale_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "conversation/locale"; Path = "tools/assistant_english_output_suite.lua"; Args = @() },

    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_combat_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_perf_budget_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_cold_compound_callback_perf_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_fuzzy_cache_bounds_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_history_lazy_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_autocoverage_lazy_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_knowledge_cold_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_hp_text_color_coldpath_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_name_shortening_coldstart_regression.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_performance_report_smoke.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_runtime_overhead_audit.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_runtime_file_profile.lua"; Args = @() },
    [pscustomobject]@{ Category = "performance"; Path = "tools/assistant_coldstart_benchmark.lua"; Args = @("all") }
)

# These files are loaded by a named gate or harness rather than invoked as a
# top-level gate. Keep the closure explicit so an ignored local helper cannot
# make a dirty checkout pass while a clean release checkout fails.
$transitiveGateDependencies = @(
    "tools/assistant_action_output_english_audit.lua",
    "tools/assistant_aura_output_audit.lua",
    "tools/assistant_aura_registry_coverage_audit.lua",
    "tools/assistant_command_surface_output_audit.lua",
    "tools/assistant_control_schema_collect.lua",
    "tools/assistant_dashboard_smoke.lua",
    "tools/assistant_dialog_output_audit.lua",
    "tools/assistant_explanations_output_audit.lua",
    "tools/assistant_followup_surface_output_audit.lua",
    "tools/assistant_guided_setup_output_audit.lua",
    "tools/assistant_history_output_english_audit.lua",
    "tools/assistant_locale_action_output_audit.lua",
    "tools/assistant_locale_output_audit.lua",
    "tools/assistant_nomatch_output_english_audit.lua",
    "tools/assistant_output_english_audit.lua",
    "tools/assistant_parse_metadata_english_audit.lua",
    "tools/assistant_registry_label_language_audit.lua",
    "tools/assistant_registry_metadata_english_audit.lua",
    "tools/assistant_router_conversation_output_audit.lua",
    "tools/assistant_runtime_manifest_loader.lua",
    "tools/assistant_setting_search_output_english_audit.lua",
    "tools/assistant_undo_output_audit.lua",
    "tools/assistant_value_display_english_audit.lua",
    "tools/assistant_visible_language_static_audit.lua",
    "tools/assistant_workflow_output_audit.lua",
    "tools/AssistantTraining/runner.lua",
    "tools/AssistantTraining/wow_stubs.lua",
    "tools/lua51_bom_runner.lua",
    "tools/test-wow-lua51-loadability.ps1"
)

$releaseAssets = @(
    "tools/generate_assistant_control_schema.ps1",
    "tools/generate_assistant_graphify_inventory.lua",
    "tools/assistant_graphify_source_snapshot.ps1",
    "tools/update_assistant_graphify_snapshot.ps1",
    "tools/AssistantTraining/run.ps1",
    "tools/assistant_v1_training_oracle.lua",
    "tools/assistant_graphify_inventory.lua",
    "tools/assistant_graphify_inventory_data.lua",
    ".github/scripts/assistant_graphify_setting_dispositions.lua",
    ".github/scripts/assistant_training_coverage_dispositions.lua",
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema.lua",
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantControlSchema_Data.lua",
    "MidnightSimpleUnitFrames_Assistant/Assistant/MSUF_AssistantRegistry_ActionInputs.lua"
)

$schemaGateMutex = [System.Threading.Mutex]::new(
    $false, "Local\MSUF_AssistantSchemaAndReleaseGate_v1")
$schemaGateMutexHeld = $false
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

try {
    Set-Location -LiteralPath $repoRoot
    $env:MSUF_ENGLISH_SUITE_FULL = "1"
    $env:MSUF_ASSISTANT_PERF_BUDGET_MULTIPLIER = "1"
    $env:MSUF_ASSISTANT_SCHEMA_GATE_LOCK_HELD = "1"

    $manifestFiles = @(Get-AssistantManifestFiles)
    foreach ($gate in $pythonGates) { [void](Require-File -RelativePath $gate.Path) }
    foreach ($gate in $luaGates) { [void](Require-File -RelativePath $gate.Path) }
    foreach ($path in $transitiveGateDependencies) { [void](Require-File -RelativePath $path) }
    foreach ($path in $releaseAssets) { [void](Require-File -RelativePath $path) }

    $trackedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($gate in $pythonGates) { [void]$trackedPaths.Add($gate.Path) }
    foreach ($gate in $luaGates) { [void]$trackedPaths.Add($gate.Path) }
    foreach ($path in $transitiveGateDependencies) { [void]$trackedPaths.Add($path) }
    foreach ($path in $releaseAssets) { [void]$trackedPaths.Add($path) }
    [void]$trackedPaths.Add(".github/scripts/run_assistant_release_gate.ps1")
    [void]$trackedPaths.Add("MidnightSimpleUnitFrames_Assistant/MSUF_AssistantRuntime.xml")
    foreach ($manifestFile in $manifestFiles) {
        $relative = $manifestFile.Substring($repoRoot.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
        [void]$trackedPaths.Add($relative)
    }
    foreach ($path in $trackedPaths) { Require-TrackedFile -RelativePath $path }
    Write-Host ("[gate] Git-tracked release closure: {0} files" -f $trackedPaths.Count)

    Write-Host "MSUF Assistant release gate"
    Write-Host "  repo: $repoRoot"
    Write-Host "  Lua: $lua"
    Write-Host "  output: $outputPath"

    Assert-GraphifySourceInventoryFreshness `
        -SourceSnapshotScript (Join-Path $repoRoot "tools/assistant_graphify_source_snapshot.ps1") `
        -InventoryPath (Join-Path $repoRoot "tools/assistant_graphify_inventory_data.lua")

    Test-AssistantManifestCompilation -Compiler $luac -Files $manifestFiles

    foreach ($gate in $pythonGates) {
        Invoke-CheckedCommand -Label $gate.Label -FilePath $python `
            -Arguments @((Join-Path $repoRoot $gate.Path))
    }

    Invoke-CheckedCommand -Label "full 40-context generated-schema freshness" -FilePath $powerShell `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            (Join-Path $repoRoot "tools/generate_assistant_control_schema.ps1"), "-Check")

    foreach ($gate in $luaGates) {
        $arguments = @((Join-Path $repoRoot $gate.Path)) + @($gate.Args)
        Invoke-CheckedCommand -Label ("{0}: {1}" -f $gate.Category, $gate.Path) `
            -FilePath $lua -Arguments $arguments
    }

    [void][System.IO.Directory]::CreateDirectory($outputPath)
    Invoke-CheckedCommand -Label "uncapped AssistantTraining" -FilePath $powerShell `
        -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            (Join-Path $repoRoot "tools/AssistantTraining/run.ps1"),
            "-Root", (Join-Path $repoRoot "MidnightSimpleUnitFrames_Assistant"),
            "-Out", $outputPath,
            "-Lua51", $lua)

    $trainingReport = Join-Path $outputPath "report.md"
    if (-not (Test-Path -LiteralPath $trainingReport -PathType Leaf)) {
        throw "Uncapped AssistantTraining did not produce its required report: $trainingReport"
    }
    Invoke-CheckedCommand -Label "AssistantTraining conservation/coverage oracle" -FilePath $lua `
        -Arguments @((Join-Path $repoRoot "tools/assistant_v1_training_oracle.lua"), $trainingReport)

    Write-Host "MSUF Assistant release gate: PASS"
} finally {
    try {
        $env:MSUF_ENGLISH_SUITE_FULL = $previousEnglishSuiteFull
        $env:MSUF_ASSISTANT_PERF_BUDGET_MULTIPLIER = $previousPerfMultiplier
        $env:MSUF_ASSISTANT_SCHEMA_GATE_LOCK_HELD = $previousSchemaGateLockHeld
        Set-Location -LiteralPath $startingLocation
    } finally {
        try {
            if ($schemaGateMutexHeld) { $schemaGateMutex.ReleaseMutex() }
        } finally {
            $schemaGateMutex.Dispose()
        }
    }
}
