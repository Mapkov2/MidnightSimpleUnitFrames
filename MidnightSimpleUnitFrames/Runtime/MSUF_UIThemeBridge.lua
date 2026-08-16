--- Runtime/MSUF_UIThemeBridge.lua
--- Official theming contract for MSUF's interface chrome (Menu2, popups,
--- floating windows). A skin addon registers a THEME PROVIDER here; MSUF
--- surfaces consume it through their token layers. The provider supplies
--- values only - it never paints MSUF frames itself, so the owner's live
--- token repaints can never fight an external skin.
---
--- Provider contract:
---   provider = {
---       name = "MidnightSkin",              -- display/debug name
---       GetTheme = function() return {
---           palette = {                      -- {r,g,b[,a]} rows, all optional
---               background=, ink=, surface=, raised=, card=, popup=, input=,
---               buttonFill=, buttonFillAlt=, buttonBorder=,
---               border=, borderSoft=, rim=,
---               accent=, accentBright=, hover=, pressed=, active=,
---           },
---           shapes = {                       -- optional
---               controlShape = "continuous" | "round" | "squircle" | "pill",
---               radius = 4|6|8|12,
---               border = 1|2,
---           },
---       } end,                               -- return nil = provider inactive
---   }
--- A provider that loads BEFORE this file sets _G.MSUF_UIThemeProviderCandidate
--- instead; the bridge adopts it here. Consumers register listeners and re-read
--- the theme whenever MSUF_NotifyUIThemeChanged fires.
local _, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local provider
local serial = 0
local listeners = {}

local function ValidProvider(candidate)
    return type(candidate) == "table" and type(candidate.GetTheme) == "function"
end

local function Notify()
    serial = serial + 1
    for i = 1, #listeners do
        local fn = listeners[i]
        if type(fn) == "function" then fn() end
    end
end

local function RegisterUIThemeProvider(candidate)
    if not ValidProvider(candidate) then return false end
    provider = candidate
    Notify()
    return true
end

local function GetUIThemeProvider()
    return provider
end

--- Resolved theme or nil (no provider, provider disabled, or bad data).
local function GetUITheme()
    if not provider then return nil end
    local theme = provider.GetTheme()
    if type(theme) ~= "table" then return nil end
    return theme
end

local function AddUIThemeListener(fn)
    if type(fn) ~= "function" then return false end
    listeners[#listeners + 1] = fn
    return true
end

local function UIThemeSerial()
    return serial
end

ExportPublic("MSUF_RegisterUIThemeProvider", RegisterUIThemeProvider)
ExportPublic("MSUF_GetUIThemeProvider", GetUIThemeProvider)
ExportPublic("MSUF_GetUITheme", GetUITheme)
ExportPublic("MSUF_AddUIThemeListener", AddUIThemeListener)
ExportPublic("MSUF_NotifyUIThemeChanged", Notify)
ExportPublic("MSUF_UIThemeSerial", UIThemeSerial)

-- A skin addon that loaded before MSUF parks its provider here.
local candidate = rawget(_G, "MSUF_UIThemeProviderCandidate")
if ValidProvider(candidate) then
    provider = candidate
end
