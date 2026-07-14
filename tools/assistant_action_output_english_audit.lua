_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local Registry = assert(A.Registry, "Assistant registry missing")

local configureEnvironment = rawget(_G, "MSUF_AssistantAuditConfigureEnvironment")
if type(configureEnvironment) == "function" then configureEnvironment(A, Registry) end

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "\195\182ffne", "waehle", "w\195\164hle",
    "einstellungen", "assistent", "zurueck", "zur\195\188ck", "rueck",
    "nicht", "keine", "abbrechen", "anwenden", "ausfuehren", "ausf\195\188hren",
    "hilfe", "spieler", "ziel", "auren", "profil", "zauberleiste", "menue", "fuer",
    "loeschen", "kopiere", "verschiebe", "groesse", "hoehe", "breite",
}

local extraForbiddenTerms = rawget(_G, "MSUF_AssistantAuditForbiddenTerms")
if type(extraForbiddenTerms) == "table" then
    for i = 1, #extraForbiddenTerms do germanTerms[#germanTerms + 1] = extraForbiddenTerms[i] end
end

local sampleArgsByKey = {
    copy_unit = { src = "player", dst = "target" },
    reset_unit_position = { unit = "player" },
    reset_unit_page = { unit = "player" },
    reset_unit_status_indicator = { unit = "player", key = "leader" },
    preview_unit_status_indicator = { unit = "player", key = "leader" },
    clear_unit_custom_anchor = { unit = "player" },
    preview_castbar = { unit = "target" },
    set_aura_edit_scope = { scope = "target" },
    reset_aura_scope_overrides = { scope = "target" },
    aura_blacklist_add_spell = { scope = "target", value = "12345" },
    aura_blacklist_remove_spell = { scope = "target", value = "12345" },
    aura_blacklist_clear_spells = { scope = "target" },
    aura_blacklist_add_preset = { scope = "target", preset = "pvp" },
    aura_blacklist_summary = { scope = "target" },
    aura_group_category_blacklist_set = { scope = "party", lane = "buffs", category = "raid", value = true },
    aura_group_category_blacklist_summary = { scope = "party", lane = "buffs" },
    aura_group_category_blacklist_clear = { scope = "party", lane = "buffs" },
    aura_group_blacklist_add_spell = { scope = "party", lane = "buffs", value = "12345" },
    aura_group_blacklist_remove_spell = { scope = "party", lane = "buffs", value = "12345" },
    aura_group_blacklist_clear_spells = { scope = "party", lane = "buffs" },
    aura_group_blacklist_add_preset = { scope = "party", lane = "buffs", preset = "pvp" },
    aura_group_blacklist_summary = { scope = "party", lane = "buffs" },
    reset_group_status_icon = { group = "party", key = "leader" },
    reset_group_status_icons = { group = "party" },
    preview_group_status_icon = { group = "party", key = "leader" },
    copy_group = { src = "party", dst = "raid" },
    clear_group_custom_anchor = { group = "party" },
    set_group_spell_indicator_aura = { group = "party", slot = "corner1", spell = "Power Word: Shield" },
    reset_group_spell_indicator_aura = { group = "party", slot = "corner1" },
    set_group_spell_indicator_multi_spec = { group = "party", slot = "corner1" },
    move_group_spell_indicator_order = { group = "party", slot = "corner1", direction = "up" },
    reset_group_corner_indicator_slot = { group = "party", slot = "corner1" },
    reset_group_corner_indicators = { group = "party" },
    class_power_quick_setup = { preset = "default" },
    set_crosshair_melee_spell = { spell = 6603 },
    apply_global_scale_preset = { preset = "default" },
    set_global_font_color = { color = { 1, 1, 1, 1 } },
    reset_power_color_token = { token = "MANA" },
    reset_class_power_color_token = { token = "combo1" },
    reset_scoped_global_bars_override = { scope = "player" },
    reset_all_scoped_global_bars_overrides = { scope = "player" },
    reset_scoped_global_font_override = { scope = "player" },
    reset_all_scoped_global_font_overrides = { scope = "player" },
    set_dispel_border_test_type = { value = "Magic" },
    open_dashboard_panel = { panel = "recovery" },
    set_dashboard_panel = { panel = "recovery" },
    set_nav_section = { section = "unitframes" },
    set_nav_search_intro = { value = true },
    set_menu_selector_state = { key = "text", value = "player" },
    export_profile = { kind = "current" },
    set_spec_profile = { spec = 123, profile = "Raid" },
    clear_spec_profile = { spec = 123 },
    ["assistant.action.editMode.gridStep"] = { value = 16 },
    ["assistant.action.editMode.backgroundOpacity"] = { value = 0.45 },
    dashboard_page_back = { direction = "back" },
    dashboard_page_forward = { direction = "forward" },
    start_unit_custom_anchor_picker = { unit = "player" },
    start_group_custom_anchor_picker = { group = "party" },
    copy_profile_from_to = { source = "Default", dest = "Raid" },
    rename_profile = { name = "Raid" },
    open_page = { page = "home", label = "Dashboard" },
    assistant_scope_help = { page = "home", label = "Dashboard" },
    copy_support_link = { link = "discord" },
    diagnose_castbar_visibility = { unit = "target" },
    diagnose_unit_visibility = { unit = "target" },
    diagnose_group_visibility = { group = "party" },
    diagnose_aura_visibility = { scope = "target", lane = "buffs" },
    guided_setup_step = { direction = "next" },
}

local sampleArgOverrides = rawget(_G, "MSUF_AssistantAuditSampleArgs")
if type(sampleArgOverrides) == "table" then
    for key, value in pairs(sampleArgOverrides) do sampleArgsByKey[key] = value end
end

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishOutput(label, output)
    local haystack = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        local needle = " " .. tostring(term):lower() .. " "
        assert(not haystack:find(needle, 1, true), label .. ": output contains German visible term " .. term .. ": " .. tostring(output))
    end
end

local function clearState()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
    A.pendingChoices = nil
    A.pendingConfirmation = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    local ctx = A.GetContext and A.GetContext()
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingConfirmation = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
    end
end

local function checkPanel(label)
    local panel = A.largeTextPanel
    if type(panel) ~= "table" then return end
    assertEnglishOutput(label .. " panel title", panel.title or "")
    assertEnglishOutput(label .. " panel help", panel.help or "")
    assertEnglishOutput(label .. " panel status", panel.status or "")
    assertEnglishOutput(label .. " panel text", panel.text or "")
end

local function actionOutput(action, args)
    if action.confirmRequired == true then
        return A.ExecutePlan({
            kind = "action",
            action = action,
            args = args,
            label = action.label,
            summary = "Assistant action output English audit.",
        })
    end
    if not (action and type(action.run) == "function") then
        return { text = "Open the MSUF menu first so I can run that task.", result = "failed" }
    end
    local ok, message = action.run(args or {})
    if ok then return { text = message or "Done.", result = "applied" } end
    return { text = message or "I kept that task as it was.", result = "failed" }
end

local failures = {}
local checked, confirmations = 0, 0

for _, action in ipairs(Registry:AllActions() or {}) do
    checked = checked + 1
    clearState()
    local args = sampleArgsByKey[action.key] or {}
    local ok, result = pcall(actionOutput, action, args)
    local label = tostring(action.key or action.label or ("action " .. tostring(checked)))
    if not ok then
        failures[#failures + 1] = label .. ": error " .. tostring(result)
    elseif type(result) ~= "table" then
        failures[#failures + 1] = label .. ": missing result"
    else
        assertEnglishOutput(label, result.text or "")
        assertEnglishOutput(label .. " summary", result.summary or "")
        checkPanel(label)
        if (result.status or result.result) == "confirmation_needed" then
            confirmations = confirmations + 1
            local cancel = A.Submit("cancel")
            assert(type(cancel) == "table", label .. ": missing cancel result")
            assertEnglishOutput(label .. " cancel", cancel.text or "")
            assertEnglishOutput(label .. " cancel summary", cancel.summary or "")
        end
    end
    clearState()
end

if #failures > 0 then
    for i = 1, #failures do io.stderr:write(failures[i], "\n") end
    error("assistant_action_output_english_audit failed")
end

io.write("assistant_action_output_english_audit: ok actions=" .. tostring(checked)
    .. " confirmations=" .. tostring(confirmations)
    .. "\n")
