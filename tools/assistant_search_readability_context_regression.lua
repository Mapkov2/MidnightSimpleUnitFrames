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

local lastExactOpen
_G.MSUF_OpenExactSettingControl = function(settingKey, label, page)
    lastExactOpen = { settingKey = settingKey, label = label, page = page }
    return true, "Opened " .. tostring(label or settingKey) .. " and focused its exact control."
end

local function resetTransient()
    if type(A.SetPendingResults) == "function" then A.SetPendingResults(nil) end
    A.pendingChoices = nil
    A.pendingSelectedResult = nil
    A.pendingConfirmation = nil
    A.lastAssistantHelpContext = nil
    lastExactOpen = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.pendingConfirmation = nil
        ctx.guidedSetup = nil
    end
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
end

local function submit(input, contains)
    local result = assert(A.Submit(input), input .. ": missing result")
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true),
            input .. ": missing " .. contains .. ": " .. tostring(result.text or ""))
    end
    return result
end

local canonical = {
    { "search class resources player power width", "Player Detached Power Bar Width", "player.detachedPowerBarWidth" },
    { "search class resources player power bar texture", "Detached Power Bar Foreground Texture", "bars.detachedPowerBarTexture" },
    { "search global font outline", "Shared Font Outline", "fontScope.shared.outline" },
    { "search global font monochrome", "Shared Rendering", "fontScope.shared.fontMonochrome" },
    { "search global bar right absorb", "Absorb Bar Anchor", "general.absorbAnchorMode" },
    { "search global bar absorb color", "Absorb Bar Color", "general.absorbBarColor" },
}

for i = 1, #canonical do
    resetTransient()
    local case = canonical[i]
    local result = submit(case[1], case[2])
    assert((result.status or result.result) == "info", case[1] .. ": search should remain read-only")
    assert(type(A.pendingResults) == "table" and #A.pendingResults == 1, case[1] .. ": missing exact result")
    assert(A.pendingResults[1].settingKey == case[3], case[1] .. ": wrong exact setting")
end

resetTransient()
local actionSearch = submit("search group indicator test mode", "Preview Group Status Icon")
assert((actionSearch.status or actionSearch.result) == "info", "group preview search should remain read-only")
assert(type(A.pendingResults) == "table" and A.pendingResults[1].actionKey == "preview_group_status_icon",
    "group preview search did not retain its executable action")
submit("run 1", "Previewing the current group status icon")

resetTransient()
local raidSearch = submit("search raid background color", "Raid background color could mean two different MSUF controls")
assert((raidSearch.status or raidSearch.result) == "ambiguous", "raid background search should offer a choice")
assert(tostring(raidSearch.text):find("Raid Backdrop Color - Group Layout", 1, true), "missing normal Raid backdrop choice")
assert(tostring(raidSearch.text):find("Raid Dead Background Color - Group Health & Text", 1, true), "missing dead Raid background choice")
assert(type(A.pendingResults) == "table" and #A.pendingResults == 2, "raid background choices were not selectable")
assert(A.pendingResults[1].settingKey == "gf_raid.bgColor", "first Raid background choice is wrong")
assert(A.pendingResults[2].settingKey == "gf_raid.deadBgColor", "second Raid background choice is wrong")
submit("open 2", "Raid Dead Background Color")
assert(lastExactOpen and lastExactOpen.settingKey == "gf_raid.deadBgColor", "opening choice 2 targeted the wrong setting")

resetTransient()
submit("make my raid frames easier to read", "Group frame readability help")
submit("what should i change first", "open Group Layout")
local groupOpen = submit("open that", "Opened Group Layout")
assert((groupOpen.status or groupOpen.result) == "navigated", "group readability follow-up did not navigate")

resetTransient()
submit("make target buffs easier to read", "Aura readability help")
submit("what should i change first", "adjust the named lane's Icon Size first")
local auraOpen = submit("open that", "Opened Target and focused Aura Buffs")
assert((auraOpen.status or auraOpen.result) == "navigated", "aura readability follow-up did not navigate")

io.write("assistant_search_readability_context_regression: ok cases=12\n")
