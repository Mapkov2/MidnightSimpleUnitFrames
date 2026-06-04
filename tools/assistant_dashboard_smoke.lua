_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local addonRoot = "MidnightSimpleUnitFrames/Shell/Menu2/"
if not exists(addonRoot .. "Assistant/MSUF_Assistant.lua") then
    addonRoot = "Shell/Menu2/"
end
local stateRoot = "MidnightSimpleUnitFrames/State/"
if not exists(stateRoot .. "MSUF_Profiles.lua") then
    stateRoot = "State/"
end

local MSUF = { MSUF2 = {} }
local capturedPrints = {}
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    capturedPrints[#capturedPrints + 1] = table.concat(parts, " ")
end
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = {
    general = {},
    bars = {},
    gameplay = {},
    player = {},
    target = {},
    focus = {},
    pet = {},
    targettarget = {},
    focustarget = {},
    boss = {},
    gf_party = {},
    gf_raid = {},
    gf_mythicraid = {},
}
_G.MSUF_GlobalDB = {
    global = { dashboard = {} },
    profiles = {
        Default = { general = {}, bars = {}, gameplay = {} },
        Raid = _G.MSUF_DB,
    },
    char = {
        ["Player-Realm"] = {
            activeProfile = "Raid",
            specProfileMap = { [123] = "Raid" },
        },
    },
}
_G.MSUF_ActiveProfile = "Raid"
_G.InCombatLockdown = function() return false end
_G.GetLocale = function() return "enUS" end
_G.UnitName = function() return "Player" end
_G.GetRealmName = function() return "Realm" end
_G.CopyTable = function(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = _G.CopyTable(v) end
    return out
end
_G.CreateFrame = function()
    return {
        SetScript = function() end,
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
    }
end

local M = MSUF.MSUF2
M.activeKey = "home"
M.Tr = function(text) return tostring(text or "") end
M.Format = function(fmt, ...) return string.format(tostring(fmt or ""), ...) end
M.WordList = function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
    return out
end
M.KeySetFromWords = function(text)
    local out = {}
    for word in tostring(text or ""):gmatch("%S+") do out[word] = true end
    return out
end
M.EnsureDB = function()
    _G.MSUF_DB.general = _G.MSUF_DB.general or {}
    return _G.MSUF_DB
end
M.RequestUnitApply = function(unit, reason) MSUF._lastUnitApply = { unit = unit, reason = reason } end
M.RequestGeneralApply = function(reason) MSUF._lastGeneralApply = reason end
M.Open = function(page) M.activeKey = page; return true end
M.SelectPage = M.Open
M.InvalidatePage = function() end
M.PersistMenuStateValue = function(key, value) M[key] = value end
M.GetPersistentMenuStateTable = function(key)
    M[key] = type(M[key]) == "table" and M[key] or {}
    return M[key]
end
M.navItems = {
    { header = "Frames", id = "unitframes", defaultOpen = true },
    { key = "uf_player", group = "unitframes" },
    { header = "Group Frames", id = "groupframes", defaultOpen = true },
    { key = "gf_layout", group = "groupframes" },
    { header = "Appearance", id = "globalstyle", defaultOpen = true },
    { key = "opt_bars", group = "globalstyle" },
}
M.navHeaderState = { unitframes = true, groupframes = false, globalstyle = true }
M.nav = {
    _msuf2NavReflow = function()
        MSUF._navReflowed = (MSUF._navReflowed or 0) + 1
    end,
}

local function loadAddon(relative)
    local path = addonRoot .. relative
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local function loadState(relative)
    local path = stateRoot .. relative
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

loadState("MSUF_Profiles.lua")
assert(type(_G.MSUF_RenameProfile) == "function", "Core profile rename helper missing")

local assistantFiles = {
    "Assistant/MSUF_AssistantHistory.lua",
    "Assistant/MSUF_AssistantUndo.lua",
    "Assistant/MSUF_AssistantQueue.lua",
    "Assistant/MSUF_AssistantRegistry.lua",
    "Assistant/MSUF_AssistantRegistry_Core.lua",
    "Assistant/MSUF_AssistantRegistry_Unitframes.lua",
    "Assistant/MSUF_AssistantRegistry_Castbars.lua",
    "Assistant/MSUF_AssistantRegistry_Auras.lua",
    "Assistant/MSUF_AssistantRegistry_GroupFrames.lua",
    "Assistant/MSUF_AssistantRegistry_Boss.lua",
    "Assistant/MSUF_AssistantRegistry_ClassPower.lua",
    "Assistant/MSUF_AssistantRegistry_Gameplay.lua",
    "Assistant/MSUF_AssistantRegistry_Global.lua",
    "Assistant/MSUF_AssistantRegistry_Dashboard.lua",
    "Assistant/MSUF_AssistantRegistry_Profiles.lua",
    "Assistant/MSUF_AssistantRegistry_EditMode.lua",
    "Assistant/MSUF_AssistantRegistry_Workflows.lua",
    "Assistant/MSUF_AssistantRegistry_Diagnostics.lua",
    "Assistant/MSUF_AssistantMediaResolver.lua",
    "Assistant/MSUF_AssistantParser.lua",
    "Assistant/MSUF_Assistant.lua",
}

local searchFiles = {
    "Search/MSUF_Menu2_Search_Data.lua",
    "Search/MSUF_Menu2_Search_Keywords.lua",
    "Search/MSUF_Menu2_Search_QueryAliases.lua",
    "Search/MSUF_Menu2_Search_FAQ.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_01.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_02.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_03.lua",
    "Search/MSUF_Menu2_Search_FAQ_Catalog_04.lua",
}

for _, file in ipairs(assistantFiles) do loadAddon(file) end
for _, file in ipairs(searchFiles) do loadAddon(file) end
loadAddon("Assistant/MSUF_AssistantKnowledge.lua")
loadAddon("Assistant/MSUF_AssistantRouter.lua")

local A = assert(MSUF.Assistant, "Assistant namespace missing")
assert(type(A.Submit) == "function", "Assistant Submit path missing")
assert(type(A.HandleInput) == "function", "Assistant input handler missing")
assert(type(A.RouteInput) == "function", "Assistant router missing")

local function submit(text)
    local result = A.Submit(text)
    assert(type(result) == "table", text .. ": missing result")
    return result
end

local function expectStatus(text, status, contains)
    local result = submit(text)
    assert(result.status == status, text .. ": wrong status " .. tostring(result.status))
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), text .. ": missing text " .. tostring(contains))
    end
    return result
end

local function expectApplied(text, contains)
    return expectStatus(text, "applied", contains)
end

expectApplied("turn off player name", "Done.")
assert(_G.MSUF_DB.player.showName == false, "Dashboard Submit did not write player.showName")
assert(MSUF._lastUnitApply and MSUF._lastUnitApply.unit == "player", "Dashboard Submit did not request player apply")
expectApplied("turn off player frame", "Done.")
assert(_G.MSUF_DB.player.enabled == false, "Dashboard Submit did not write player.enabled")
expectApplied("turn it back on", "Done.")
assert(_G.MSUF_DB.player.enabled == true, "Dashboard context follow-up did not re-enable player.enabled")

expectStatus("reset player settings", "confirmation_needed", "Type 'yes'")
expectStatus("cancel", "failed", "Cancelled.")

local ambiguous = submit("turn off name")
assert(ambiguous.status == "ambiguous", "turn off name should ask for a numbered choice")
assert(type(A.pendingChoices) == "table" and #A.pendingChoices > 0, "pending choices missing")
expectApplied("option 1")

local firstAmbiguous = submit("turn on name")
assert(firstAmbiguous.status == "ambiguous", "turn on name should ask for a numbered choice")
expectApplied("first")

expectApplied("how do i move the player frame", "Edit Mode")
expectApplied("where is castbar texture", "MSUF")
expectApplied("what can i change here")
expectApplied("help")

expectApplied("collapse frames navigation section", "Closed Frames navigation section.")
assert(M.navHeaderState.unitframes == false, "NavRail frames section did not collapse")
assert((MSUF._navReflowed or 0) > 0, "NavRail section action did not reflow")
expectApplied("open group frames navigation section", "Opened Group Frames navigation section.")
assert(M.navHeaderState.groupframes == true, "NavRail group frames section did not open")
M.searchIntroSeen = true
expectApplied("reset search intro", "Search intro")
assert(M.searchIntroSeen == false, "Search intro reset did not clear seen state")
expectApplied("show search intro", "Search intro")
assert(M.searchIntroSeen == false, "Search intro fallback should remain pending when the NavRail UI is not built")

expectApplied("turn on class color mode for raidframe", "Done.")
assert(_G.MSUF_DB.gf_raid.gfBarMode == "CLASS", "Raid frame class color mode did not set gf_raid.gfBarMode")
assert(_G.MSUF_DB.gf_raid.healthColorMode == "CLASS", "Raid frame class color mode did not sync healthColorMode")
_G.MSUF_DB.gf_party.gfBarMode = "CUSTOM"
_G.MSUF_DB.gf_raid.gfBarMode = "CUSTOM"
_G.MSUF_DB.gf_mythicraid.gfBarMode = "CUSTOM"
expectApplied("turn on class color mode for group frames", "Done.")
assert(_G.MSUF_DB.gf_party.gfBarMode == "CLASS", "Group frames class color mode did not set party")
assert(_G.MSUF_DB.gf_raid.gfBarMode == "CLASS", "Group frames class color mode did not set raid")
assert(_G.MSUF_DB.gf_mythicraid.gfBarMode == "CLASS", "Group frames class color mode did not set mythic raid")
_G.MSUF_DB.general.darkBarGray = 0.07
expectApplied("make unitframe dark mode a bit lighter", "Done.")
assert(_G.MSUF_DB.general.darkBarGray == 0.10, "Dark mode lighter command did not increase darkBarGray")
expectApplied("make unitframe dark mode super dark", "Done.")
assert(_G.MSUF_DB.general.darkBarGray == 0.01, "Dark mode super dark command did not set darkBarGray")
expectApplied("set player custom anchor frame to PlayerFrame", "Done.")
assert(_G.MSUF_DB.player.anchorFrameName == "PlayerFrame", "Player custom anchor frame did not set anchorFrameName")
assert(_G.MSUF_DB.player.anchorToUnitframe == "GLOBAL", "Player custom anchor frame did not force global anchor mode")
expectApplied("set raid custom anchor to CompactRaidFrame1", "Done.")
assert(_G.MSUF_DB.gf_raid.anchorToFrame == "CompactRaidFrame1", "Raid custom anchor frame did not set anchorToFrame")

expectApplied("select player hp left slot", "Selected Player HP Text left slot.")
assert(M.activeKey == "uf_player", "Unit text selector did not open player page")
assert(M.unitTextTabSelection.player == "hp", "Unit text selector did not select HP tab")
assert(M.unitTextSlotSelection.player.hp == "left", "Unit text selector did not select left slot")
expectApplied("select party power text right slot", "Selected Party Power Text right slot.")
assert(M.activeKey == "gf_bars", "Group text selector did not open Group Health & Text")
assert(M.gfScope == "party", "Group text selector did not set party scope")
assert(M.gfTextTabSelection.party == "power", "Group text selector did not select power tab")
assert(M.gfTextSlotSelection.party.power == "right", "Group text selector did not select right slot")
expectApplied("turn off party hp move text as one group", "Set Party HP Text move text as one group off.")
assert(M.gfTextMoveTogether.party.hp == false, "Group text move-together selector did not set party HP per-slot mode")
expectApplied("set player power text per slot", "Set Player Power Text move text as one group off.")
assert(M.unitTextMoveTogether.player.power == false, "Unit text move-together selector did not set player power per-slot mode")
expectApplied("select target advanced status tab", "Selected Target Advanced status tab.")
assert(M.activeKey == "uf_target", "Unit status selector did not open target page")
assert(M.unitStatusTabSelection.target == "advanced", "Unit status selector did not select advanced tab")
expectApplied("select party leader icon indicator", "Selected Party Leader Icon indicator.")
assert(M.activeKey == "gf_indicators", "Group status selector did not open Group Indicators")
assert(M.gfStatusIconSelection == "leaderIcon", "Group status selector did not select leader icon")
expectApplied("select bottom right corner editor slot", "Selected Party Bottom Right corner editor slot.")
assert(M.gfCornerSlotSelection == "BR", "Corner editor selector did not select bottom right")
expectApplied("select mana power color token", "Selected Mana power color token.")
assert(M.activeKey == "opt_colors", "Color token selector did not open Colors page")
assert(M.colorsPowerToken == "MANA", "Power color token selector did not select mana")
expectApplied("set profile name field to Raid Draft", "Set profile create/copy name")
assert(M.activeKey == "profiles", "Profile name staging did not open Profiles page")
assert(M.profileCreateCopyName == "Raid Draft", "Profile create/copy name staging did not set runtime field")
expectApplied("select profile export kind group frames", "Selected Group Frames profile export kind.")
assert(M.profileExportKind == "groupframe", "Profile export kind staging did not set groupframe")
expectApplied("turn on profile import and create new profile", "Set profile import and create new profile on.")
assert(M.profileImportCreateNew == true, "Profile import-create-new staging did not enable toggle")
expectApplied("set profile import new profile name to Imported Raid", "Set profile import new-profile name")
assert(M.profileImportNewName == "Imported Raid", "Profile import new-profile name staging did not set runtime field")
expectApplied("set profile string field to MSUF5:staged", "Set profile string field.")
assert(M.profileImportString == "MSUF5:staged", "Profile string staging did not set runtime field")
expectApplied("clear group copy categories", "Cleared all group copy categories.")
assert(M.activeKey == "gf_layout", "Group copy staging did not open Group Layout page")
assert(M.gfCopyScopes and M.gfCopyScopes.general == false and M.gfCopyScopes.health == false, "Group copy clear did not disable categories")
expectApplied("select only group copy health and text categories", "Selected only group copy categories")
assert(M.gfCopyScopes.health == true and M.gfCopyScopes.text == true, "Group copy only did not enable health/text")
assert(M.gfCopyScopes.general == false and M.gfCopyScopes.font == false, "Group copy only did not disable other categories")
expectApplied("turn off group copy auras category", "Set group copy category Auras off.")
assert(M.gfCopyScopes.auras == false, "Group copy category toggle did not disable auras")

expectStatus("rename profile Raid to Raid PvP", "confirmation_needed", "Type 'yes'")
expectApplied("yes", "Renamed profile Raid to Raid PvP")
assert(_G.MSUF_GlobalDB.profiles.Raid == nil, "Profile rename did not remove old profile key")
assert(type(_G.MSUF_GlobalDB.profiles["Raid PvP"]) == "table", "Profile rename did not create destination profile key")
assert(_G.MSUF_ActiveProfile == "Raid PvP", "Profile rename did not move active profile")
assert(_G.MSUF_DB == _G.MSUF_GlobalDB.profiles["Raid PvP"], "Profile rename did not update active DB reference")
assert(_G.MSUF_GlobalDB.char["Player-Realm"].specProfileMap[123] == "Raid PvP", "Profile rename did not update spec profile mapping")

local history = A.GetHistory and A.GetHistory() or {}
assert(#history >= 12, "Dashboard Submit did not record conversation history")

io.write("assistant_dashboard_smoke: ok\n")
