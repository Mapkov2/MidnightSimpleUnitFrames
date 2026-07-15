-- Focused spell-aware player channel tick marker regression.
_G = _G or _ENV

local knownSpells = {}
_G.issecretvalue = function() return false end
_G.IsPlayerSpell = function(spellID) return knownSpells[spellID] == true end

local MSUF = {}
local chunk, err = loadfile("MidnightSimpleUnitFrames/Castbars/MSUF_CastbarChannelTicks.lua")
assert(chunk, err)
assert(pcall(chunk, "MidnightSimpleUnitFrames", MSUF))

local function NewMarker()
    return {
        shown = false,
        points = {},
        SetColorTexture = function() end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        SetWidth = function(self, width) self.width = width end,
        SetPoint = function(self, ...)
            self.points[#self.points + 1] = { ... }
        end,
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
        _msufPlayerState = {
            spellId = spellID,
            startTimeMS = 1000,
            endTimeMS = 1000 + ((duration or 2) * 1000),
        },
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

local frame = NewFrame(356995, 2) -- Disintegrate: four ticks, three separators.
update(frame, true)
assert(ShownCount(frame) == 3, "Disintegrate did not use three internal separators")
AssertNear(frame._msufPlayerChannelHasteMarkers[1].points[1][4], 50, "Disintegrate first separator")

knownSpells[1219723] = true -- Azure Celerity adds a fifth tick.
update(frame, true)
assert(ShownCount(frame) == 4, "Azure Celerity did not add the Disintegrate separator")
knownSpells[1219723] = nil

frame._msufActiveSpellID = 115175 -- Soothing Mist: twelve ticks.
frame._msufPlayerState.spellId = 115175
update(frame, true)
assert(ShownCount(frame) == 11, "Soothing Mist did not use eleven internal separators")

frame._msufActiveSpellID = 47757 -- Penance: three ticks.
frame._msufPlayerState.spellId = 47757
update(frame, true)
assert(ShownCount(frame) == 2, "pooled surplus separators were not hidden")

frame._msufActiveSpellID = 198013 -- Eye Beam: 0.2-second interval over two seconds.
frame._msufPlayerState.spellId = 198013
update(frame, true)
assert(ShownCount(frame) == 9, "Eye Beam interval did not resolve to ten ticks")

frame._msufActiveSpellID = 999999 -- Unknown: preserve legacy five-line behavior.
frame._msufPlayerState.spellId = 999999
update(frame, true)
assert(ShownCount(frame) == 5, "unknown channel lost the five-line fallback")
AssertNear(frame._msufPlayerChannelHasteMarkers[1].points[1][4], 200 / 6, "fallback first separator")

MSUF_DB.player.castbar.channelTickUseCustom = true
MSUF_DB.player.castbar.channelTickCount = 3
MSUF_DB.player.castbar.channelTickPosPct = { 20, 50, 80 }
update(frame, true)
assert(ShownCount(frame) == 3, "custom layout did not override spell-aware markers")
AssertNear(frame._msufPlayerChannelHasteMarkers[1].points[1][4], 40, "custom first separator")

frame._msufStripeReverseFill = true
update(frame, true)
local reversePoint = frame._msufPlayerChannelHasteMarkers[1].points[1]
assert(reversePoint[2] == frame.statusBar and reversePoint[3] == "TOPRIGHT",
    "reverse fill did not anchor separators from the right")
AssertNear(reversePoint[4], -40, "reverse custom first separator")

frame.statusBar.widthReads = 0
frame.statusBar.onSizeChanged()
assert(frame.statusBar.widthReads == 1, "size change did not refresh marker geometry directly")

MSUF_DB.general.castbarShowChannelTicks = false
update(frame, true)
assert(ShownCount(frame) == 0 and _G.MSUF_IsChannelTickLinesEnabled() == false,
    "global Off did not hide spell-aware channel ticks")

local menuFile = assert(io.open("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua", "rb"))
local menuSource = menuFile:read("*a")
menuFile:close()
assert(menuSource:find('"Spell-specific channel tick markers"', 1, true),
    "spell-aware channel tick toggle name is missing")
assert(menuSource:find("M.AddTooltip(behaviorControls.castbarShowChannelTicks", 1, true)
    and menuSource:find("five evenly spaced fallback lines", 1, true)
    and menuSource:find("labelHit = true", 1, true),
    "spell-aware channel tick tooltip contract is incomplete")

print("castbar_spell_channel_ticks_smoke: ok")
