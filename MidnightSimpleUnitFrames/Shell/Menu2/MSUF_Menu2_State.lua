--- Menu2 persisted UI state.
---
--- Stores cold Menu2 shell selections under `MSUF_GlobalDB.char[char].menu2State`.
--- Page builders should use `M.GetPersistentMenuStateTable` for table fields and
--- `M.PersistMenuStateValue` for scalar selections so saved state stays
--- centralized and migration-safe.
local _, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local function WordList(text)
    if type(M.WordList) == "function" then return M.WordList(text) end
    local out = {}
    for value in tostring(text or ""):gmatch("%S+") do out[#out + 1] = value end
    return out
end

local MENU_STATE_VERSION = 2
local MENU_STATE_TABLE_FIELDS = WordList [[
    accordionState previewPinState navHeaderState unitTextTabSelection unitTextSlotSelection
    unitStatusSelection unitStatusTabSelection gfTextTabSelection gfTextSlotSelection
    gfStatusIconTabSelection gfSpellMultiSpecSelection gfSpellIndicatorSelection
]]
local MENU_STATE_SCALAR_DEFAULTS = {
    lastPage = "home",
    gfScope = "party",
    auraScope = "shared",
    auraStyleTab = "overview",
    auraStyleGFScope = "raid",
    auraStyleGFLane = "debuff",
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
        local ok, key = pcall(fn)
        if ok and type(key) == "string" and key ~= "" then return key end
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
    if oldVersion >= 2 then return end
    local accordion = type(state) == "table" and state.accordionState
    if type(accordion) ~= "table" then return end
    for key in pairs(accordion) do
        local textKey = type(key) == "string" and (key == "gf_bars:text" or key:match("^uf_[^:]+:text$"))
        if textKey then accordion[key] = nil end
    end
end

local function EnsurePersistentMenuState()
    _G.MSUF_GlobalDB = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {}
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
        if type(M[field]) == "table" and M[field] ~= saved then
            CopyMissingStateValues(saved, M[field])
        end
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
