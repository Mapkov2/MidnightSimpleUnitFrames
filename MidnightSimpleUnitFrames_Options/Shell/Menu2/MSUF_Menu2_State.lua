--- Menu2 persisted UI state.
---
--- Stores cold Menu2 shell selections under `MSUF_GlobalDB.char[char].menu2State`.
--- Page builders should use `M.GetPersistentMenuStateTable` for table fields and
--- `M.SetMenuStateValue` for scalar selections so saved state stays
--- centralized and migration-safe.
local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local MENU_STATE_VERSION = 6
local MENU_STATE_TABLE_FIELDS = M.WordList [[
    accordionState navHeaderState unitTextTabSelection unitTextSlotSelection unitPortraitTabSelection
    unitStatusSelection unitStatusTabSelection gfTextTabSelection gfTextSlotSelection
    gfStatusIconTabSelection gfSpellMultiSpecSelection gfSpellIndicatorSelection
    collapseHintClickState
]]
local MENU_STATE_SCALAR_DEFAULTS = {
    gfScope = "party",
    auraScope = "shared",
    auraStyleTab = "overview",
    auraStyleGFScope = "raid",
    auraStyleGFLane = "debuff",
    auraStyleContainer = "debuff",
    auraAppearanceContainer = "debuff",
    previewBackground = "silvermoon",
    previewBackgroundCustomR = 0.08,
    previewBackgroundCustomG = 0.12,
    previewBackgroundCustomB = 0.18,
    auraStyleGFBlacklistLane = "debuff",
    auraBlacklistPreset = "RAID_BUFFS",
    gfStatusIconSelection = "roleIcon",
    gfCornerSlotSelection = "TL",
    gfStatusPreviewMode = "current",
    colorsPowerToken = "MANA",
    colorsCPToken = "COMBO_POINTS",
    profileExportKind = "all",
    profileImportCreateNew = false,
    searchIntroSeen = false,
    dashboardChangelogOpen = false,
    dashboardRecoveryOpen = false,
    dashboardScalingOpen = false,
    lastPandemicMode = "PULSE",
}
local function MenuCharKey()
    local fn = rawget(_G, "MSUF_GetCharKey")
    if type(fn) == "function" then
        local key = fn()
        if type(key) == "string" and key ~= "" then return key end
    end
    local name = (_G.UnitName and _G.UnitName("player")) or "Unknown"
    local realm = (_G.GetRealmName and _G.GetRealmName()) or "Realm"
    return tostring(name) .. "-" .. tostring(realm)
end
local function CopyMissingStateValues(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
end
local function MigrateMenuState(state, oldVersion)
    oldVersion = tonumber(oldVersion) or 0
    if type(state) ~= "table" then return end
    if oldVersion < 2 then
        local accordion = state.accordionState
        if type(accordion) == "table" then
            for key in pairs(accordion) do
                local textKey = type(key) == "string" and (key == "gf_bars:text" or key:match("^uf_[^:]+:text$"))
                if textKey then accordion[key] = nil end
            end
        end
    end
    -- The last selected menu page is intentionally session-only.
    if oldVersion < 4 then state.lastPage = nil end
    if oldVersion < 6 then
        state.auraStylePreviewScope = nil
        state.auraStylePreviewMode = nil
    end
end
local function EnsurePersistentMenuState()
    ExportPublic("MSUF_GlobalDB", type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {})
    local gdb = _G.MSUF_GlobalDB
    gdb.char = type(gdb.char) == "table" and gdb.char or {}
    local charKey = MenuCharKey()
    local charDB = type(gdb.char[charKey]) == "table" and gdb.char[charKey] or {}
    gdb.char[charKey] = charDB
    local state = type(charDB.menu2State) == "table" and charDB.menu2State or {}
    charDB.menu2State = state
    local oldVersion = tonumber(state.version) or 0
    state.version = MENU_STATE_VERSION
    local firstLoad = M._persistentMenuState ~= state or M._persistentMenuStateLoaded ~= true
    for i = 1, #MENU_STATE_TABLE_FIELDS do
        local field = MENU_STATE_TABLE_FIELDS[i]
        local saved = state[field]
        if type(saved) ~= "table" then
            saved = {}
            state[field] = saved
        end
        if type(M[field]) == "table" and M[field] ~= saved then CopyMissingStateValues(saved, M[field]) end
        M[field] = saved
    end
    if firstLoad then MigrateMenuState(state, oldVersion) end
    for field, defaultValue in pairs(MENU_STATE_SCALAR_DEFAULTS) do
        if firstLoad and state[field] ~= nil then
            M[field] = state[field]
        elseif M[field] ~= nil then
            state[field] = M[field]
        else
            M[field] = defaultValue
            state[field] = defaultValue
        end
    end
    M._persistentMenuState = state
    M._persistentMenuStateLoaded = true
    return state
end
local function SavePersistentMenuState()
    local state = EnsurePersistentMenuState()
    for field in pairs(MENU_STATE_SCALAR_DEFAULTS) do
        state[field] = M[field]
    end
    return state
end
function M.EnsurePersistentMenuState()
    return EnsurePersistentMenuState()
end
function M.GetPersistentMenuStateTable(field)
    local state = EnsurePersistentMenuState()
    if type(state[field]) ~= "table" then state[field] = {} end
    M[field] = state[field]
    return state[field]
end
function M.PersistMenuStateValue(field, value)
    local state = EnsurePersistentMenuState()
    M[field] = value
    state[field] = value
    return value
end
function M.SavePersistentMenuState()
    return SavePersistentMenuState()
end
