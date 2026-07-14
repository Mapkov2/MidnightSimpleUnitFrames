-- Dev-only WoW API stubs for the external MSUF Assistant training runner.
-- Keep these permissive: the runner is interested in parser behavior, not UI rendering.

local G = _G

G.MSUF_ASSISTANT_TRAINING = true
G.WOW_PROJECT_MAINLINE = G.WOW_PROJECT_MAINLINE or 1
G.WOW_PROJECT_ID = G.WOW_PROJECT_ID or G.WOW_PROJECT_MAINLINE
G.LE_EXPANSION_CURRENT = G.LE_EXPANSION_CURRENT or 10

G.unpack = G.unpack or table.unpack
G.format = G.format or string.format

function G.wipe(tbl)
    if type(tbl) ~= "table" then return tbl end
    for key in pairs(tbl) do tbl[key] = nil end
    return tbl
end

function G.tContains(tbl, item)
    if type(tbl) ~= "table" then return false end
    for i = 1, #tbl do
        if tbl[i] == item then return true end
    end
    return false
end

local function copyTable(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[copyTable(key, seen)] = copyTable(child, seen)
    end
    return out
end
G.CopyTable = G.CopyTable or copyTable

function G.strtrim(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function G.strsplit(delim, text)
    delim = tostring(delim or "")
    text = tostring(text or "")
    if delim == "" then return text end
    local out = {}
    local startAt = 1
    while true do
        local pos = text:find(delim, startAt, true)
        if not pos then
            out[#out + 1] = text:sub(startAt)
            break
        end
        out[#out + 1] = text:sub(startAt, pos - 1)
        startAt = pos + #delim
    end
    return table.unpack(out)
end

local CLASS_CONTEXTS = {
    WARRIOR = { "Warrior", 1, { { 71, "Arms" }, { 72, "Fury" }, { 73, "Protection" } } },
    PALADIN = { "Paladin", 2, { { 65, "Holy" }, { 66, "Protection" }, { 70, "Retribution" } } },
    HUNTER = { "Hunter", 3, { { 253, "Beast Mastery" }, { 254, "Marksmanship" }, { 255, "Survival" } } },
    ROGUE = { "Rogue", 4, { { 259, "Assassination" }, { 260, "Outlaw" }, { 261, "Subtlety" } } },
    PRIEST = { "Priest", 5, { { 256, "Discipline" }, { 257, "Holy" }, { 258, "Shadow" } } },
    DEATHKNIGHT = { "Death Knight", 6, { { 250, "Blood" }, { 251, "Frost" }, { 252, "Unholy" } } },
    SHAMAN = { "Shaman", 7, { { 262, "Elemental" }, { 263, "Enhancement" }, { 264, "Restoration" } } },
    MAGE = { "Mage", 8, { { 62, "Arcane" }, { 63, "Fire" }, { 64, "Frost" } } },
    WARLOCK = { "Warlock", 9, { { 265, "Affliction" }, { 266, "Demonology" }, { 267, "Destruction" } } },
    MONK = { "Monk", 10, { { 268, "Brewmaster" }, { 269, "Windwalker" }, { 270, "Mistweaver" } } },
    DRUID = { "Druid", 11, { { 102, "Balance" }, { 103, "Feral" }, { 104, "Guardian" }, { 105, "Restoration" } } },
    DEMONHUNTER = { "Demon Hunter", 12, { { 577, "Havoc" }, { 581, "Vengeance" }, { 1480, "Devourer" } } },
    EVOKER = { "Evoker", 13, { { 1467, "Devastation" }, { 1468, "Preservation" }, { 1473, "Augmentation" } } },
}
local TEST_CLASS_TOKEN = tostring(os.getenv("MSUF_TEST_CLASS_TOKEN") or "MAGE"):upper()
local TEST_CLASS = CLASS_CONTEXTS[TEST_CLASS_TOKEN] or CLASS_CONTEXTS.MAGE
local TEST_SPEC_INDEX = tonumber(os.getenv("MSUF_TEST_SPEC_INDEX")) or 1
if not TEST_CLASS[3][TEST_SPEC_INDEX] then TEST_SPEC_INDEX = 1 end

function G.GetLocale() return os.getenv("MSUF_TEST_LOCALE") or "enUS" end
function G.GetTime() return os.clock() end
function G.date(...) return os.date(...) end
function G.InCombatLockdown() return false end
function G.UnitAffectingCombat() return false end
function G.IsLoggedIn() return true end
function G.GetRealmName() return "AssistantTraining" end
function G.UnitName(unit) return tostring(unit or "player") end
function G.UnitClass() return TEST_CLASS[1], TEST_CLASS_TOKEN, TEST_CLASS[2] end
function G.UnitPowerType() return 0, "MANA" end
function G.GetSpecialization() return TEST_SPEC_INDEX end
function G.GetSpecializationInfo(index)
    local spec = TEST_CLASS[3][tonumber(index) or TEST_SPEC_INDEX]
    if not spec then return nil end
    return spec[1], spec[2], "", nil, "DAMAGER", nil, 0
end
function G.GetSpecializationInfoForClassID(classID, index)
    for token, class in pairs(CLASS_CONTEXTS) do
        if class[2] == tonumber(classID) then
            local spec = class[3][tonumber(index) or 1]
            if spec then return spec[1], spec[2], "", nil, "DAMAGER", true, true, token end
        end
    end
end
function G.GetSpecializationInfoForSpecID(specID)
    for _, class in pairs(CLASS_CONTEXTS) do
        for i = 1, #class[3] do
            local spec = class[3][i]
            if spec[1] == tonumber(specID) then return spec[1], spec[2], "", nil, "DAMAGER", class[1] end
        end
    end
end
G.GetSpecializationInfoByID = G.GetSpecializationInfoForSpecID
function G.GetBuildInfo() return "12.1.0", "120100", "Jul 1 2026", 120100 end
function G.GetAddOnMetadata(_, field)
    if field == "Version" then return "training" end
    return nil
end

G.C_AddOns = G.C_AddOns or {}
function G.C_AddOns.GetAddOnMetadata(addonName, field) return G.GetAddOnMetadata(addonName, field) end
function G.C_AddOns.IsAddOnLoaded() return true end
function G.C_AddOns.LoadAddOn() return true end

G.C_Timer = G.C_Timer or {}
function G.C_Timer.After(_, fn)
    -- Do not run timer callbacks while loading parser files; many of them create UI.
    return { Cancel = function() end }
end
function G.C_Timer.NewTicker(_, fn)
    return { Cancel = function() end }
end

local frameId = 0
local function fakeRegion()
    local object = { _scripts = {}, _children = {} }
    local mt
    mt = {
        __index = function(tbl, key)
            if key == "GetName" then return function(self) return rawget(self, "_name") end end
            if key == "SetScript" or key == "HookScript" then
                return function(self, event, fn)
                    self._scripts[event] = fn
                    return self
                end
            end
            if key == "CreateTexture" or key == "CreateFontString" then
                return function(self)
                    local child = fakeRegion()
                    self._children[#self._children + 1] = child
                    return child
                end
            end
            if key == "GetChildren" then
                return function(self) return table.unpack(self._children or {}) end
            end
            if key == "GetRegions" then
                return function(self) return table.unpack(self._children or {}) end
            end
            if key == "GetParent" then return function(self) return rawget(self, "_parent") end end
            if key == "GetWidth" or key == "GetHeight" then return function() return 1 end end
            if key == "GetSize" then return function() return 1, 1 end end
            if key == "GetPoint" then return function() return "CENTER", G.UIParent, "CENTER", 0, 0 end end
            if key == "IsShown" or key == "IsVisible" then return function() return true end end
            if key == "CanChangeAttribute" then return function() return true end end
            if key == "RegisterEvent" or key == "UnregisterEvent" or key == "RegisterUnitEvent" then
                return function(self) return self end
            end
            return function(self) return self end
        end,
    }
    return setmetatable(object, mt)
end

G.UIParent = G.UIParent or fakeRegion()
G.UIParent._name = "UIParent"

function G.CreateFrame(_, name, parent)
    frameId = frameId + 1
    local frame = fakeRegion()
    frame._name = name or ("MSUFTrainingFrame" .. tostring(frameId))
    frame._parent = parent or G.UIParent
    return frame
end

G.BackdropTemplateMixin = G.BackdropTemplateMixin or {}
function G.Mixin(object, ...)
    object = object or {}
    for i = 1, select("#", ...) do
        local mixin = select(i, ...)
        if type(mixin) == "table" then
            for key, value in pairs(mixin) do object[key] = value end
        end
    end
    return object
end

local mediaLibrary = {
    Fetch = function(_, mediaType, key) return key or mediaType or "default" end,
    List = function(_, mediaType)
        if mediaType == "font" then return { "Friz Quadrata TT", "Arial Narrow", "MSUF Default", "Expressway Bold", "Expressway Condensed Light", "Expressway ExtraBold", "Expressway Regular", "Expressway SemiBold" } end
        if mediaType == "statusbar" then return { "Blizzard", "Smooth", "MSUF Flat" } end
        return { "Default" }
    end,
    HashTable = function(_, mediaType)
        if mediaType == "font" then
            return {
                ["Friz Quadrata TT"] = "Fonts\\FRIZQT___CYR.TTF",
                ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
                ["MSUF Default"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\MSUF_Default.ttf",
                ["Expressway Bold"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Bold.ttf",
                ["Expressway Condensed Light"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Condensed Light.ttf",
                ["Expressway ExtraBold"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway ExtraBold.ttf",
                ["Expressway Regular"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf",
                ["Expressway SemiBold"] = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway SemiBold.ttf",
            }
        end
        return {}
    end,
    Register = function() return true end,
    IsValid = function() return true end,
}

local function getLibrary(name)
    if name == "LibSharedMedia-3.0" then return mediaLibrary end
    if name == "AceSerializer-3.0" then
        return {
            Serialize = function(_, value) return tostring(value) end,
            Deserialize = function(_, value) return true, value end,
        }
    end
    if name == "LibDeflate" then
        return {
            CompressDeflate = function(_, value) return value end,
            DecompressDeflate = function(_, value) return value end,
            EncodeForPrint = function(_, value) return value end,
            DecodeForPrint = function(_, value) return value end,
        }
    end
    return {}
end

local libStub = G.LibStub
if type(libStub) ~= "table" then
    libStub = {}
    setmetatable(libStub, { __call = function(_, name, silent) return getLibrary(name, silent) end })
    G.LibStub = libStub
end
G.LibStub.GetLibrary = G.LibStub.GetLibrary or function(_, name, silent) return getLibrary(name, silent) end

G.RAID_CLASS_COLORS = G.RAID_CLASS_COLORS or {
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 },
}

G.PowerBarColor = G.PowerBarColor or {
    MANA = { r = 0.00, g = 0.44, b = 0.87 },
    RAGE = { r = 0.78, g = 0.25, b = 0.25 },
    FOCUS = { r = 1.00, g = 0.50, b = 0.25 },
    ENERGY = { r = 1.00, g = 0.86, b = 0.10 },
    RUNIC_POWER = { r = 0.00, g = 0.82, b = 1.00 },
}

G.Enum = G.Enum or {}
G.Enum.PowerType = G.Enum.PowerType or {
    Mana = 0,
    Rage = 1,
    Focus = 2,
    Energy = 3,
    RunicPower = 6,
}

G.MSUF_DB = G.MSUF_DB or { general = {}, bars = {}, gameplay = {} }
G.MSUF_GlobalDB = G.MSUF_GlobalDB or {}

local MSUF = G.MSUF_NS or {}
G.MSUF_NS = MSUF
MSUF.MSUF2 = MSUF.MSUF2 or {}
MSUF.Assistant = MSUF.Assistant or {}
MSUF.LSM = MSUF.LSM or mediaLibrary
MSUF.ExportPublic = MSUF.ExportPublic or function(name, value)
    G[name] = value
    return value
end

local M = MSUF.MSUF2
G.MSUF2 = M
M.activeKey = M.activeKey or "home"
M.ApplyService = M.ApplyService or {
    Request = function() end,
    Flush = function() end,
    CallGlobal = function(_, name, ...)
        local fn = G[name]
        if type(fn) == "function" then return fn(...) end
        return nil
    end,
}
M.EnsureDB = M.EnsureDB or function()
    G.MSUF_DB.general = type(G.MSUF_DB.general) == "table" and G.MSUF_DB.general or {}
    G.MSUF_DB.bars = type(G.MSUF_DB.bars) == "table" and G.MSUF_DB.bars or {}
    G.MSUF_DB.gameplay = type(G.MSUF_DB.gameplay) == "table" and G.MSUF_DB.gameplay or {}
    return G.MSUF_DB
end
M.RequestGeneralApply = M.RequestGeneralApply or function() end
M.RefreshAdvancedNavVisibility = M.RefreshAdvancedNavVisibility or function() end
M.RefreshNavIconVisibility = M.RefreshNavIconVisibility or function() end

MSUF.MSUF_Auras3 = MSUF.MSUF_Auras3 or { RequestApply = function() end }
MSUF.GroupFrames = MSUF.GroupFrames or {}

return {
    MSUF = MSUF,
    M = M,
    FakeRegion = fakeRegion,
}
