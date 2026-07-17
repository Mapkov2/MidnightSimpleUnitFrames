[CmdletBinding()]
param(
    [string]$LuaCommand = "lua"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$lua = Get-Command $LuaCommand -ErrorAction Stop

# This is intentionally explicit: adding a non-Assistant smoke without adding
# it here fails the manifest check instead of silently leaving CI coverage red.
$tests = @(
    "tools/advanced_colors_page_contract_smoke.lua",
    ".github/scripts/tests/aggro_runtime_routing_smoke.lua",
    "tools/apply_service_dedup_smoke.lua",
    "tools/castbar_native_manager_smoke.lua",
    "tools/castbar_refresh_ownership_smoke.lua",
    "tools/classpower_native_duration_smoke.lua",
    "tools/classpower_smooth_runtime_smoke.lua",
    "tools/color_painter_lifecycle_smoke.lua",
    "tools/color_refresh_dedup_smoke.lua",
    "tools/font_color_cache_smoke.lua",
    "tools/global_bars_page_smoke.lua",
    "tools/group_adapter_preview_smoke.lua",
    "tools/group_adapter_state_smoke.lua",
    "tools/group_aggro_combat_gate_smoke.lua",
    "tools/group_member_lifecycle_smoke.lua",
    "tools/group_preview_layer_click_smoke.lua",
    "tools/group_preview_lifecycle_smoke.lua",
    "tools/group_preview_render_contract_smoke.lua",
    "tools/group_range_coalesce_smoke.lua",
    "tools/health_prediction_dispatch_smoke.lua",
    "tools/interrupt_ready_perf_smoke.lua",
    "tools/locale_reload_smoke.lua",
    "tools/perf_runtime_smoke.lua",
    "tools/portrait_refresh_smoke.lua",
    "tools/powerbar_runtime_smoke.lua",
    "tools/prediction_fastpath_smoke.lua",
    "tools/preview_exact_pan_smoke.lua",
    ".github/scripts/tests/unit_preview_geometry_smoke.lua",
    "tools/profile_apply_smoke.lua",
    "tools/range_visibility_smoke.lua",
    "tools/ready_check_targeting_smoke.lua",
    "tools/secret_group_health_smoke.lua",
    "tools/targeted_spells_smoke.lua",
    "tools/text_lazy_sinks_smoke.lua",
    "tools/uf_notify_config_refresh_smoke.lua",
    "tools/unit_event_routing_smoke.lua",
    "tools/value_source_hotpath_smoke.lua",
    "tools/window_build_contract_smoke.lua",
    ".github/scripts/tests/aura_growth_anchor_smoke.lua",
    ".github/scripts/tests/boss_castbar_lifecycle_smoke.lua",
    ".github/scripts/tests/castbar_duration_identity_smoke.lua",
    ".github/scripts/tests/castbar_engine_identity_smoke.lua",
    ".github/scripts/tests/castbar_focus_subscription_smoke.lua",
    ".github/scripts/tests/castbar_hotpath_smoke.lua",
    ".github/scripts/tests/castbar_legacy55_anchor_smoke.lua",
    ".github/scripts/tests/castbar_native_ownership_smoke.lua",
    ".github/scripts/tests/castbar_spell_channel_ticks_smoke.lua",
    ".github/scripts/tests/castbar_target_name_color_smoke.lua",
    ".github/scripts/tests/combat_crosshair_zoom_contract_smoke.lua",
    ".github/scripts/tests/disabled_feature_lifecycle_smoke.lua",
    ".github/scripts/tests/detached_power_preview_width_smoke.lua",
    ".github/scripts/tests/editmode_castbar_nudge_smoke.lua",
    ".github/scripts/tests/event_bus_dispatch_smoke.lua",
    ".github/scripts/tests/first_load_action_lifecycle_smoke.lua",
    ".github/scripts/tests/font_color_key_smoke.lua",
    ".github/scripts/tests/frame_screen_clamp_contract_smoke.lua",
    ".github/scripts/tests/group_frame_growth_live_smoke.lua",
    ".github/scripts/tests/group_frame_login_anchor_repair_smoke.lua",
    ".github/scripts/tests/group_frame_position_smoke.lua",
    ".github/scripts/tests/group_frame_scale_roster_smoke.lua",
    ".github/scripts/tests/group_foreground_layer_smoke.lua",
    ".github/scripts/tests/group_lifecycle_workplan_smoke.lua",
    ".github/scripts/tests/group_preview_aura_menu_routing_smoke.lua",
    ".github/scripts/tests/group_preview_chrome_parity_smoke.lua",
    ".github/scripts/tests/group_preview_external_menu_click_smoke.lua",
    ".github/scripts/tests/group_role_coldpath_smoke.lua",
    ".github/scripts/tests/group_role_icon_defaults_smoke.lua",
    ".github/scripts/tests/guided_tour_inactive_perf_smoke.lua",
    ".github/scripts/tests/guided_tour_interaction_smoke.lua",
    ".github/scripts/tests/hp_text_class_color_smoke.lua",
    ".github/scripts/tests/hp_text_abbreviation_smoke.lua",
    ".github/scripts/tests/identity_payload_hotpath_smoke.lua",
    ".github/scripts/tests/layer_contract_smoke.lua",
    ".github/scripts/tests/layer_strata_runtime_smoke.lua",
    ".github/scripts/tests/legacy55_profile_migration_smoke.lua",
    ".github/scripts/tests/level_name_anchor_smoke.lua",
    ".github/scripts/tests/menu2_visible_page_layout_settle_smoke.lua",
    ".github/scripts/tests/menu_refresh_proxy_smoke.lua",
    ".github/scripts/tests/name_shortening_level_reservation_smoke.lua",
    ".github/scripts/tests/npc_class_color_group_smoke.lua",
    ".github/scripts/tests/npc_kind_dispatch_cache_smoke.lua",
    ".github/scripts/tests/player_alpha_apply_smoke.lua",
    ".github/scripts/tests/portrait_identity_hotpath_smoke.lua",
    ".github/scripts/tests/power_bar_visibility_hotpath_smoke.lua",
    ".github/scripts/tests/power_text_meta_hotpath_smoke.lua",
    ".github/scripts/tests/mouseover_highlight_runtime_smoke.lua",
    ".github/scripts/tests/pet_frame_color_isolation_smoke.lua",
    ".github/scripts/tests/prediction_coalescer_smoke.lua",
    ".github/scripts/tests/priority_frames_binding_smoke.lua",
    ".github/scripts/tests/priority_frames_duplicate_registry_smoke.lua",
    ".github/scripts/tests/priority_frames_editmode_smoke.lua",
    ".github/scripts/tests/priority_frames_lifecycle_fanout_smoke.lua",
    ".github/scripts/tests/priority_frames_menu_smoke.lua",
    ".github/scripts/tests/priority_frames_runtime_smoke.lua",
    ".github/scripts/tests/priority_frames_secure_header_smoke.lua",
    ".github/scripts/tests/priority_frames_selection_smoke.lua",
    ".github/scripts/tests/range_driver_event_delta_smoke.lua",
    ".github/scripts/tests/runtime_route_intern_smoke.lua",
    ".github/scripts/tests/spell_indicator_auto_blacklist_smoke.lua",
    ".github/scripts/tests/spell_indicator_buff_style_smoke.lua",
    ".github/scripts/tests/spell_indicator_position_lifecycle_smoke.lua",
    ".github/scripts/tests/status_identity_state_reuse_smoke.lua",
    ".github/scripts/tests/status_lifecycle_smoke.lua",
    ".github/scripts/tests/status_symbol_legacy55_smoke.lua",
    ".github/scripts/tests/target_sound_driver_smoke.lua",
    ".github/scripts/tests/typography_role_smoke.lua",
    ".github/scripts/tests/version_check_prerelease_smoke.lua"
)

function Convert-ToRelativePath([string]$path) {
    return $path.Substring($repoRoot.Length + 1).Replace("\", "/")
}

$discovered = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot "tools") -File -Filter "*smoke.lua" |
        Where-Object { $_.Name -notlike "assistant*" } |
        ForEach-Object { Convert-ToRelativePath $_.FullName }
    Get-ChildItem -LiteralPath (Join-Path $repoRoot ".github/scripts/tests") -File -Filter "*.lua" |
        Where-Object { $_.Name -notlike "assistant*" } |
        ForEach-Object { Convert-ToRelativePath $_.FullName }
) | Sort-Object -Unique

$manifestDelta = Compare-Object ($tests | Sort-Object -Unique) $discovered
if ($manifestDelta) {
    $details = ($manifestDelta | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" }) -join [Environment]::NewLine
    throw "Core smoke manifest does not match discovered tests:`n$details"
}

$failures = @()
Push-Location $repoRoot
try {
    foreach ($test in $tests) {
        $absolute = Join-Path $repoRoot $test
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            $failures += "$test (missing)"
            continue
        }
        Write-Host "CORE SMOKE: $test"
        if ($test.StartsWith(".github/")) {
            & $lua.Source $absolute $repoRoot
        } else {
            & $lua.Source $absolute
        }
        if ($LASTEXITCODE -ne 0) {
            $failures += "$test (exit $LASTEXITCODE)"
        }
    }
} finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    throw "Core smoke failures ($($failures.Count)):`n$($failures -join [Environment]::NewLine)"
}

Write-Host "PASS: $($tests.Count) core Lua 5.1 smoke tests"
