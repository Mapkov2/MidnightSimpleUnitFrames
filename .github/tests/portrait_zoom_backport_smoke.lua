-- Focused runtime and preview regression for 5.74 2D portrait zoom.
_G = _G or _ENV

_G.C_Timer = { After = function(_, callback) callback() end }
_G.SetPortraitTexture = function(texture, unit) texture.portraitUnit = unit end
_G.UnitExists = function() return true end

local ns = {
    Cache = {
        F = {
            GetTime = function() return 1 end,
            UnitClass = function() return "Mage", "MAGE" end,
            UnitClassBase = function() return "MAGE" end,
            UnitGUID = function() return "Player-1" end,
            InCombatLockdown = function() return false end,
        },
        StampChanged = function() return true end,
    },
    PortraitMedia = {},
}

assert(loadfile("MidnightSimpleUnitFrames/Core/MSUF_Portraits.lua"))("MidnightSimpleUnitFrames", ns)

local function NewPortrait()
    return {
        shown = false,
        SetTexCoord = function(self, l, r, t, b) self.coords = { l, r, t, b } end,
        SetTexture = function(self, texture) self.texture = texture end,
        ClearAllPoints = function() end,
        SetSize = function() end,
        SetPoint = function() end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
end

local function AssertNear(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.0001,
        string.format("%s: expected %.4f, got %s", label, expected, tostring(actual)))
end

local portrait = NewPortrait()
local frame = {
    portrait = portrait,
    hpBar = {},
    GetHeight = function() return 30 end,
    _msufPortraitDirty = true,
    _msufPortraitNextAt = 0,
}
local conf = { portraitMode = "LEFT", portraitRender = "2D", portraitZoom = 150, height = 30 }
_G.MSUF_UpdatePortraitIfNeeded(frame, "player", conf, true)
local expectedInset = (1 - (0.8 * (100 / 150))) * 0.5
AssertNear(portrait.coords[1], expectedInset, "150 percent live portrait zoom")
AssertNear(portrait.coords[2], 1 - expectedInset, "150 percent live portrait right crop")

frame._msufPortraitDirty = true
conf.portraitZoom = 100
_G.MSUF_UpdatePortraitIfNeeded(frame, "player", conf, true)
AssertNear(portrait.coords[1], 0.1, "default live crop changed")
AssertNear(portrait.coords[2], 0.9, "default live crop changed")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local preview = Read("MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_UnitPreview.lua")
assert(preview:find('PortraitStyleGet(key, "portraitZoom", 100)', 1, true)
    and preview:find("local span = 0.84 * (100 / zoom)", 1, true),
    "Menu2 preview does not mirror portrait zoom")

local menu = Read("MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
assert(menu:find('W.Slider(geometryCard, "Portrait zoom", 100, 200, 1', 1, true)
    and menu:find('SetPortraitValue(unit, "portraitZoom"', 1, true),
    "Portrait zoom control is missing or not using the cold portrait sync path")

print("portrait_zoom_backport_smoke: ok")
