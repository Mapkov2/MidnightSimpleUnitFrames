-- Final parser guard for deterministic Assistant action inputs.
--
-- Parser specialists are allowed to recognize incomplete natural-language
-- intents, but an incomplete action must never escape as an executable plan.
-- Convert it into a non-executable, user-facing clarification before the
-- transaction layer sees it.  The authoritative registry contract remains
-- strict and is still enforced again at ExecuteAction.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local P = A.Parser or {}
A.Parser = P

local Guard = A.ActionInputParseGuard or {}
A.ActionInputParseGuard = Guard

local RawParse = A.Parse
if type(RawParse) ~= "function" then return end

local FIELD_PROMPTS = {
    anchor = "Which anchor do you want to use?",
    category = "Which category do you want to use?",
    color = "Which color do you want to use?",
    destination = "What destination name do you want to use?",
    field = "Which exact part do you want to change?",
    icon = "Which status icon do you want to use?",
    link = "Which support link do you want me to copy?",
    name = "What name do you want to use?",
    page = "Which MSUF page do you want me to open?",
    panel = "Which Dashboard panel do you mean?",
    position = "Which destination position do you want to use?",
    preset = "Which preset do you want to use?",
    query = "What do you want me to search for?",
    resourceToken = "Which class-resource color set do you want to reset?",
    scope = "Which MSUF frame or group scope do you mean?",
    section = "Which navigation section do you mean?",
    selector = "Which exact menu choice do you want me to select?",
    settingKey = "Which exact MSUF setting do you want me to show?",
    slot = "Which slot do you want to use?",
    source = "Which source do you want to copy from?",
    spec = "Which class or specialization do you mean?",
    target = "Which target do you want to copy to?",
    targets = "Which targets do you want to copy to?",
    text = "What exact text do you want to use?",
    token = "Which color token do you mean?",
    unit = "Which unit frame do you mean?",
    value = "What value do you want me to use?",
}

local ACTION_PROMPTS = {
    ["assistant.action.editMode.backgroundOpacity"] = "What background opacity do you want in Edit Mode?",
    ["assistant.action.editMode.gridStep"] = "What Edit Mode grid step do you want, from 8 to 64?",
    apply_global_scale_preset = "Which scale preset do you want to apply?",
    aura_blacklist_add_preset = "Which frame or Aura lane and which blacklist preset do you want to use?",
    aura_blacklist_add_spell = "Which frame or Aura lane and which spell do you want to blacklist?",
    aura_blacklist_remove_spell = "Which frame or Aura lane and which spell do you want to remove from the blacklist?",
    aura_blacklist_summary = "Which frame or Aura lane blacklist do you want to see?",
    aura_custom_whitelist_add_spell = "Which frame or Aura lane and which spell do you want to whitelist?",
    aura_custom_whitelist_clear_spells = "Which frame or Aura lane whitelist do you want to clear?",
    aura_custom_whitelist_remove_spell = "Which frame or Aura lane and which spell do you want to remove from the whitelist?",
    aura_custom_whitelist_summary = "Which frame or Aura lane whitelist do you want to see?",
    aura_group_blacklist_add_preset = "Which group scope and which blacklist preset do you want to use?",
    aura_group_blacklist_add_spell = "Which group scope and which spell do you want to blacklist?",
    aura_group_blacklist_remove_spell = "Which group scope and which spell do you want to remove from the blacklist?",
    aura_group_category_blacklist_set = "Which group scope and Aura category do you want to change?",
    import_legacy_profile_string = "Paste the legacy profile string you want to import.",
    import_profile_string = "Paste the profile string you want to import.",
    import_profile_string_new = "Paste the profile string you want to import as a new profile.",
    move_group_spell_indicator_order = "Which tracked spell do you want to move, and to which list position?",
    reset_group_spell_indicator_aura = "Which group scope, specialization, and tracked spell do you want to reset?",
    set_crosshair_melee_spell = "Which spell name or spell ID do you want to use for the melee-range check?",
    set_global_font_color = "Which font color do you want to use?",
    set_group_spell_indicator_aura = "Which group scope, specialization, tracked spell, and field do you want to change?",
    set_group_spell_indicator_multi_spec = "Which group scope and specialization do you want to change?",
    set_menu_selector_state = "Which exact menu selector and choice do you want to use?",
}

local function Trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function DisplayActionLabel(action)
    if type(A.DisplayActionLabel) == "function" then
        local label = A.DisplayActionLabel(action)
        if type(label) == "string" and label ~= "" then return label end
    end
    return tostring(action and (action.label or action.key) or "that MSUF task")
end

local function PromptForError(action, err)
    local key = tostring(action and action.key or "")
    if ACTION_PROMPTS[key] then return ACTION_PROMPTS[key] end
    err = tostring(err or "")
    local field = err:match("requires input field ([%w_]+)")
    if field and FIELD_PROMPTS[field] then return FIELD_PROMPTS[field] end
    local fields = err:match("requires one of:%s*(.+)")
    if fields then
        for candidate in fields:gmatch("[%w_]+") do
            if FIELD_PROMPTS[candidate] then return FIELD_PROMPTS[candidate] end
        end
    end
    field = err:match("unknown input field ([%w_]+)")
    if field then
        return "Please name the exact target and value for this task instead of using " .. tostring(field) .. " as a shortcut."
    end
    return "Which exact target and value do you want me to use?"
end

local function NormalizeActionPlan(plan)
    if type(plan) ~= "table" then return true end
    local action = plan.action
    local key = type(action) == "table" and action.key or plan.actionKey
    if type(key) ~= "string" or key == "" then return false, action, "action key is missing" end
    if type(A.NormalizeAssistantActionInput) ~= "function" then
        return false, action, "explicit action input contract is unavailable"
    end
    local ok, normalized, err = pcall(A.NormalizeAssistantActionInput, key, plan.args or {})
    if not ok or type(normalized) ~= "table" then
        return false, action or { key = key, label = plan.label }, ok and err or normalized
    end
    plan.args = normalized
    return true
end

local function ClarificationFor(invalid, parsed, raw)
    local lines = { "I need a little more detail before I can safely run that." }
    local seen, added = {}, 0
    for i = 1, #invalid do
        local item = invalid[i]
        local prompt = PromptForError(item.action, item.error)
        local fingerprint = DisplayActionLabel(item.action) .. "\031" .. prompt
        if not seen[fingerprint] then
            seen[fingerprint] = true
            added = added + 1
            if #invalid == 1 then
                lines[#lines + 1] = DisplayActionLabel(item.action) .. ": " .. prompt
            elseif added <= 4 then
                lines[#lines + 1] = "- " .. DisplayActionLabel(item.action) .. ": " .. prompt
            end
        end
    end
    if added > 4 then lines[#lines + 1] = "Name the exact action, target, and value you want me to use." end
    lines[#lines + 1] = "I kept MSUF unchanged."
    return {
        kind = "answer",
        status = "ambiguous",
        text = table.concat(lines, "\n"),
        summary = "Asks for missing action details before execution.",
        raw = parsed and parsed.raw or raw,
        normalized = parsed and parsed.normalized,
        actionInputClarification = true,
        actionInputClarificationCount = #invalid,
    }
end

function Guard.ValidateParsedPlan(parsed, raw)
    if type(parsed) ~= "table" then return parsed end
    local invalid = {}
    if parsed.kind == "action" then
        local valid, action, err = NormalizeActionPlan(parsed)
        if not valid then invalid[#invalid + 1] = { action = action, error = err } end
    end
    for i = 1, #(parsed.choices or {}) do
        local choice = parsed.choices[i]
        if type(choice) == "table" and (choice.action ~= nil or choice.actionKey ~= nil or choice.kind == "action") then
            local valid, action, err = NormalizeActionPlan(choice)
            if not valid then invalid[#invalid + 1] = { action = action, error = err } end
        end
    end
    if #invalid > 0 then return ClarificationFor(invalid, parsed, raw) end
    return parsed
end

function Guard.Parse(text, ctxOverride)
    return Guard.ValidateParsedPlan(RawParse(text, ctxOverride), text)
end

Guard.RawParse = RawParse
Guard.Installed = true
A.Parse = Guard.Parse
A.ParsePlan = Guard.Parse
A.ParseForTest = Guard.Parse
MSUF.Public = MSUF.Public or {}
MSUF.Public.Assistant = MSUF.Public.Assistant or {}
MSUF.Public.Assistant.Parse = Guard.Parse
