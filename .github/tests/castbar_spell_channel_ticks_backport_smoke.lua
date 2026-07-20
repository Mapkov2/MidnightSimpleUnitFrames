-- Focused regression for the 5.74 spell-aware Player channel markers.
_G = _G or _ENV

local knownSpells = {}
_G.issecretvalue = function() return false end
_G.IsPlayerSpell = function(spellID) return knownSpells[spellID] == true end

assert(loadfile("MidnightSimpleUnitFrames_Castbars/Castbars/MSUF_CastbarChannelTicks.lua"))()

local function NewMarker()
    return {
        shown = false,
        points = {},
        SetColorTexture = function() end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        SetWidth = function(self, width) self.width = width end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        ClearAllPoints = function(self) self.points = {} end,
        Hide = function(self) self.shown = false end,
        Show = function(self) self.shown = true end,
    }
end

local function NewFrame(spellID, duration)
    local statusBar = { width = 200, widthReads = 0 }
    function statusBar:CreateTexture()
        local marker = NewMarker()
        self.created = self.created or {}
        self.created[#self.created + 1] = marker
        return marker
    end
    function statusBar:GetWidth()
        self.widthReads = self.widthReads + 1
        return self.width
    end
    function statusBar:HookScript(script, callback)
        assert(script == "OnSizeChanged")
        self.onSizeChanged = callback
    end
    return {
        unit = "player",
        statusBar = statusBar,
        MSUF_isChanneled = true,
        _msufActiveSpellID = spellID,
        _msufPlainTotal = duration or 2,
    }
end

local function ShownCount(frame)
    local count = 0
    for _, marker in ipairs(frame._msufPlayerChannelHasteMarkers or {}) do
        if marker.shown then count = count + 1 end
    end
    return count
end

local function AssertNear(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.001,
        string.format("%s: expected %.3f, got %s", label, expected, tostring(actual)))
end

MSUF_DB = {
    general = { castbarShowChannelTicks = true },
    player = { castbar = { channelTickUseCustom = false } },
}

local update = assert(_G.MSUF_PlayerChannelHasteMarkers_Update)
assert(_G.MSUF_ApplyPlayerChannelTickMarkers == _G.MSUF_UpdateCastbarChannelTicks,
    "legacy LoD custom renderer was not replaced")
local frame = NewFrame(356995, 2)
update(frame, true)
assert(ShownCount(frame) == 3, "Disintegrate did not use three internal separators")
AssertNear(frame._msufPlayerChannelHasteMarkers[1].points[1][4], 50, "Disintegrate first separator")

knownSpells[1219723] = true
update(frame, true)
assert(ShownCount(frame) == 4, "Azure Celerity did not add the Disintegrate separator")
knownSpells[1219723] = nil

frame._msufActiveSpellID = 115175
update(frame, true)
assert(ShownCount(frame) == 11, "Soothing Mist did not use eleven internal separators")

frame._msufActiveSpellID = 47757
update(frame, true)
assert(ShownCount(frame) == 2, "pooled surplus separators were not hidden")

frame._msufActiveSpellID = 198013
frame._msufPlainTotal = 2
update(frame, true)
assert(ShownCount(frame) == 9, "Eye Beam interval did not resolve to ten ticks")

frame._msufActiveSpellID = 999999
update(frame, true)
assert(ShownCount(frame) == 5, "unknown channels lost the five-marker fallback")
AssertNear(frame._msufPlayerChannelHasteMarkers[1].points[1][4], 200 / 6, "fallback first separator")

MSUF_DB.player.castbar.channelTickUseCustom = true
MSUF_DB.player.castbar.channelTickCount = 3
MSUF_DB.player.castbar.channelTickPosPct = { 20, 50, 80 }
update(frame, true)
assert(ShownCount(frame) == 3, "custom layout did not override automatic markers")
AssertNear(frame._msufPlayerChannelHasteMarkers[1].points[1][4], 40, "custom first separator")

frame._msufStripeReverseFill = true
update(frame, true)
local reversePoint = frame._msufPlayerChannelHasteMarkers[1].points[1]
assert(reversePoint[2] == frame.statusBar and reversePoint[3] == "TOPRIGHT", "reverse fill used the wrong anchor")
AssertNear(reversePoint[4], -40, "reverse custom first separator")

frame.statusBar.widthReads = 0
frame.statusBar.onSizeChanged()
assert(frame.statusBar.widthReads == 1, "size change did not refresh geometry directly")

MSUF_DB.general.castbarShowChannelTicks = false
update(frame, true)
assert(ShownCount(frame) == 0 and _G.MSUF_IsChannelTickLinesEnabled() == false,
    "global Off did not hide channel markers")

local source = assert(io.open("MidnightSimpleUnitFrames_Castbars/MSUF_Castbars.lua", "rb"))
local mainSource = source:read("*a")
source:close()
assert(not mainSource:find("_msufHasteMarkersNext", 1, true), "periodic channel-marker refresh is still present")

source = assert(io.open("MidnightSimpleUnitFrames/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", "rb"))
local menuSource = source:read("*a")
source:close()
assert(menuSource:find("for i = 1, 5 do", 1, true)
    and menuSource:find('W.Toggle(behavior, "Spell-specific channel tick markers")', 1, true)
    and menuSource:find("five evenly spaced fallback lines", 1, true),
    "Menu2 preview or spell-aware explanation is incomplete")

print("castbar_spell_channel_ticks_backport_smoke: ok")
