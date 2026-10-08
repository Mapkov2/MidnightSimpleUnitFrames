-- probe_a5_glow_overwrites_tint.lua <repoRoot> [flavor]
-- "Show castbar glow effect" on: a target cast that is non-interruptible from
-- its start (UnitCastingInfo notInterruptible = true) is tinted red through
-- SetVertexColorFromBoolean, but the glow base is the interruptible colour, so
-- the glow fade repaints the bar with SetStatusBarColor in the interruptible hue.
local root = arg[1]
local World = assert(loadfile(root .. "/tools/tests/castbar_world.lua"))()
local world = World.New(root, "timer", {
    flavor = arg[2] or "Mists",
    setup = function(ns, w)
        _G.UnitCastingInfo = function(unit)
            local cast = w.casting[unit]
            if not cast then return nil end
            return cast.name, cast.name, 135812, cast.startMS, cast.endMS, false, cast.guid,
                cast.notInterruptible == true, cast.spellID, cast.castBarID
        end
    end,
})
_G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
local general = _G.MSUF_DB.general
general.castbarShowGlow = true
general.castbarInterruptibleR, general.castbarInterruptibleG, general.castbarInterruptibleB = 0, 1, 0
general.castbarNonInterruptibleR, general.castbarNonInterruptibleG, general.castbarNonInterruptibleB = 1, 0, 0

local bar = world:Driver("target")
-- The bar's fill texture: one vertex colour shared by SetVertexColorFromBoolean
-- and StatusBar:SetStatusBarColor (both document SecretAspect.VertexColor).
local fill = { }
function fill:SetVertexColorFromBoolean(value, ifTrue, ifFalse)
    local c = value and ifTrue or ifFalse
    self.r, self.g, self.b = c.r, c.g, c.b
    self.lastWriter = "SetVertexColorFromBoolean"
end
local allocations = 0
bar.statusBar.CreateTexture = function()
    allocations = allocations + 1
    return { SetColorTexture = function() end, SetBlendMode = function() end,
        ClearAllPoints = function() end, SetAllPoints = function(self, parent) self.parent = parent end,
        SetAlpha = function(self, alpha) self.alpha = alpha end,
        Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end }
end
bar.statusBar.GetStatusBarTexture = function() return fill end
bar.statusBar.SetStatusBarColor = function(_, r, g, b)
    fill.r, fill.g, fill.b = r, g, b
    fill.lastWriter = "SetStatusBarColor"
end
local function Shown()
    return string.format("%.2f,%.2f,%.2f (%s)", fill.r or -1, fill.g or -1, fill.b or -1, tostring(fill.lastWriter))
end

world:StartCast("target", "Shield Wall Cast", 3, 61)
world.casting.target.notInterruptible = true
world:Fire(bar, "UNIT_SPELLCAST_START", "SWC-guid", 133, 61)
print("cast start          bar colour " .. Shown())
for _, t in ipairs({ 0.5, 1.0, 1.5, 2.5 }) do
    world:Advance(0.5)
    print(string.format("elapsed ~%.1f s      bar colour %s", t, Shown()))
end
print("expected: red 1,0,0 (non-interruptible) for the whole cast")

assert(fill.r == 1 and fill.g == 0 and fill.b == 0, "glow overwrote native uninterruptible color")
assert(bar.statusBar._msufGlowOverlay and allocations == 1, "glow overlay not reused")
local overlay = bar.statusBar._msufGlowOverlay
assert(overlay.alpha > 0 and overlay.parent == fill, "glow does not follow native fill")
_G.MSUF_ResetCastbarGlowFade(bar)
assert(not overlay.shown, "reset retained glow")
