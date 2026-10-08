-- Probe C24: menu accent vs MenuSkin palette snapshot ordering.
-- Loads the real core MSUF_MapkoSkin.lua, Theme_Forever, Theme_Tokens and Theme.lua
-- in Menu2.xml order, then runs the BuildWindow accent call and a skin refresh.
local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/"
local function load(path, ns) return assert(loadfile(ROOT .. path))("MidnightSimpleUnitFrames", ns) end

-- WoW stubs (no leniency: hooksecurefunc is a post-hook, CreateFrame returns a frame)
function hooksecurefunc(t, name, fn)
    local orig = t[name]
    t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
local function NewFrame()
    local f = { events = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(k, v) self[k] = v end
    return f
end
CreateFrame = function() return NewFrame() end
InCombatLockdown = function() return false end
IsLoggedIn = function() return true end
UnitClass = function() return "Mage", "MAGE" end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }

-- Saved state: the player chose the Jade menu accent and switched
-- "Use MapkoSkin for MSUF menus" off (Misc > MapkoSkin).
MSUF_DB = { general = { menuAccent = "jade", mapkoSkinMenus = false } }
MSUF_EnsureDB = function() return MSUF_DB end

-- Minimal MapkoSkin provider API 2.1 (installed and enabled).
local client = { ReleaseAll = function() end, Release = function() end }
local api = {}
function api:RegisterAddon() return client end
function api:IsEnabled() return true end
function api:GetAppearanceSnapshot() return {} end
function api:GetColor() return 0.5, 0.5, 0.5, 1 end
function api:OnAppearanceChanged() end
MapkoSkin = { GetAPI = function() return api end }

local ns = { Translate = function(s) return s end, GetEffectiveLocale = function() return "enUS" end,
    Client = { IsForever = false } }
ns.MSUF2 = {
    Assign = function(t, v) for k, x in pairs(v) do t[k] = x end return t end,
    WordList = function(s) local t = {} for v in s:gmatch("%S+") do t[#t + 1] = v end return t end,
    Lines = function(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end,
}
-- core addon file (TOC Shell\UI\MSUF_MapkoSkin.lua)
load("MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua", ns)
-- Options TOC: Theme_Forever, then Menu2.xml: ... Theme_Tokens (7), Theme (8), ... Bindings (22)
load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Forever.lua", ns)
load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua", ns)
local M, T = ns.MSUF2, ns.MSUF2.Theme
local stock = { unpack(T.colors.accent) }
load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua", ns)
print("after Theme.lua load: _menuAccentApplied =", tostring(T._menuAccentApplied),
    " (M.GetGeneralDB defined:", type(M.GetGeneralDB) == "function", ")")

-- MSUF_Menu2_Bindings.lua:90 defines it later; Window.lua:2088 BuildWindow calls ApplyMenuAccent.
function M.GetGeneralDB() return MSUF_DB.general end
T.ApplyMenuAccent()
local accented = { unpack(T.colors.accent) }
print(("BuildWindow accent: %s  accent = %.3f %.3f %.3f"):format(T._menuAccentApplied, accented[1], accented[2], accented[3]))

-- Any later skin refresh: MapkoSkin appearance change (hooked OnAppearanceChanged)
-- or the Misc toggle apply (Bindings_History.lua:705 / GlobalMisc.lua:462).
api:OnAppearanceChanged("theme")
local after = { unpack(T.colors.accent) }
print(("after MenuSkin.Refresh: accent = %.3f %.3f %.3f  (stock %.3f %.3f %.3f)"):format(
    after[1], after[2], after[3], stock[1], stock[2], stock[3]))
print("observed: accent reverted to stock =", after[1] == stock[1] and after[2] == stock[2] and after[3] == stock[3])
print("expected: accent stays on the applied jade tone =", after[1] == accented[1] and after[2] == accented[2])
print("session still reports applied accent:", T._menuAccentApplied, " MenuAccentActive:", T.MenuAccentActive())

assert(after[1] == accented[1] and after[2] == accented[2] and after[3] == accented[3], "skin refresh reverted the saved accent")
