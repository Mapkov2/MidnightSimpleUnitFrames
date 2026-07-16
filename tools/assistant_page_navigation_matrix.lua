_G = _G or _ENV

local function Exists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not Exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing")
local M = assert(_G.MSUF_NS and _G.MSUF_NS.MSUF2, "Menu2 missing")

local function ClearContext()
    local ctx = assert(A.GetContext and A.GetContext(), "Assistant context missing")
    for key in pairs(ctx) do ctx[key] = nil end
    for _, key in ipairs({
        "pendingChoices", "pendingCandidates", "pendingConfirmation", "pendingFlow",
        "pendingResults", "pendingSelectedResult", "pendingSettingSearch",
        "lastAssistantPlanningContext", "lastAssistantHelpContext",
    }) do
        A[key] = nil
    end
    if type(A.SetPendingResults) == "function" then A.SetPendingResults(nil) end
end

local function ExistingScalars(root)
    local out, seen = {}, {}
    local function Walk(value, path)
        if type(value) ~= "table" then
            out[path] = type(value) .. ":" .. tostring(value)
            return
        end
        if seen[value] then return end
        seen[value] = true
        for key, child in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                Walk(child, path .. "/" .. tostring(key))
            end
        end
        seen[value] = nil
    end
    Walk(root, "db")
    return out
end

local function ExistingScalarsUnchanged(before, root)
    local after = ExistingScalars(root)
    for path, value in pairs(before) do
        if after[path] ~= value then return false, path, value, after[path] end
    end
    return true
end

local pages = {
    { "home", "dashboard", "Dashboard", "home" },
    { "search", "search", "Search", "search" },
    { "uf_player", "player frame", "Player", "uf_player" },
    { "uf_target", "target frame", "Target", "uf_target" },
    { "uf_focus", "focus frame", "Focus", "uf_focus" },
    { "uf_pet", "pet frame", "Pet", "uf_pet" },
    { "uf_boss", "boss frames", "Boss", "uf_boss" },
    { "uf_targettarget", "target of target", "Target of Target", "uf_targettarget" },
    { "uf_focustarget", "focus target", "Focus Target", "uf_focustarget" },
    { "gf_layout", "group layout", "Group Layout", "gf_layout" },
    { "gf_bars", "group dispel overlay", "Group Dispel Overlay", "gf_bars" },
    { "gf_indicators", "group status and indicators", "Group Status & Indicators", "gf_indicators" },
    { "gf_auras", "group auras", "Group Auras", "gf_auras" },
    { "gf_priority", "priority frames", "Priority", "gf_priority" },
    { "opt_bars", "bars", "Bars", "opt_bars" },
    { "opt_castbar", "cast bars", "Cast Bars", "opt_castbar" },
    { "opt_colors", "colors", "Colors", "opt_colors" },
    { "opt_fonts", "fonts", "Fonts", "opt_fonts" },
    { "opt_misc", "miscellaneous", "Miscellaneous", "opt_misc" },
    { "auras3_styling", "aura style", "Aura Style", "auras3_styling" },
    -- Compatibility Aura pages route into the visible Player Aura workspace.
    { "auras3_filters", "aura filters", "Aura Filters", "uf_player" },
    { "auras3_custom", "custom auras", "Custom Auras", "uf_player" },
    { "auras3_buffs", "aura buffs", "Aura Buffs", "uf_player" },
    { "auras3_debuffs", "aura debuffs", "Aura Debuffs", "uf_player" },
    { "classpower", "class resources", "Class Resources", "classpower" },
    { "gameplay", "gameplay", "Gameplay", "gameplay" },
    { "profiles", "profiles", "Profiles", "profiles" },
    { "modules", "modules", "Modules", "modules" },
}

local navigators = {
    "open %s", "show me %s", "take me to %s", "find %s",
}
local checks = 0
for i = 1, #pages do
    local row = pages[i]
    for v = 1, #navigators do
        ClearContext()
        M.activeKey = "home"
        local dbBefore = ExistingScalars(_G.MSUF_DB or {})
        local prompt = string.format(navigators[v], row[2])
        local result = assert(A.HandleInput(prompt), "no result for " .. prompt)
        assert((result.status or result.result) == "navigated",
            prompt .. " did not navigate: " .. tostring(result.text))
        assert(M.activeKey == row[4], string.format(
            "%s opened %s instead of %s", prompt, tostring(M.activeKey), row[4]))
        local unchanged, path = ExistingScalarsUnchanged(dbBefore, _G.MSUF_DB or {})
        assert(unchanged, prompt .. " changed existing profile state at " .. tostring(path))
        checks = checks + 1
    end

    ClearContext()
    M.activeKey = "home"
    local dbBefore = ExistingScalars(_G.MSUF_DB or {})
    local prompt = "where is " .. row[2]
    local result = assert(A.HandleInput(prompt), "no result for " .. prompt)
    local status = result.status or result.result
    assert(status == "navigated" or status == "info",
        prompt .. " returned an unsafe/unresolved status: " .. tostring(status))
    if status == "navigated" then
        assert(M.activeKey == row[4], string.format(
            "%s opened %s instead of %s", prompt, tostring(M.activeKey), row[4]))
    else
        local text = tostring(result.text or ""):lower()
        local expected = tostring(row[3]):lower():gsub("&", "and")
        local comparable = text:gsub("&", "and")
        assert(comparable:find(expected, 1, true),
            prompt .. " did not identify " .. row[3] .. ": " .. tostring(result.text))
    end
    local unchanged, path = ExistingScalarsUnchanged(dbBefore, _G.MSUF_DB or {})
    assert(unchanged, prompt .. " changed existing profile state at " .. tostring(path))
    checks = checks + 1
end

assert(#pages == 28, "canonical page matrix drifted")
print(string.format("assistant_page_navigation_matrix: ok pages=%d intents=%d zero_profile_writes=true",
    #pages, checks))
