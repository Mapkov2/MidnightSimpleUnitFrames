-- Exercise the Retail resource stack against a moving Essential anchor.
local root = (... and ... ~= "" and ...) or "."

_G.MSUF_NS = {
    UF = { GetFrame = function() end },
    ExportPublic = function(name, value) _G[name] = value; return value end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Core.lua"))()

local viewer = { height = 40, scale = 1 }
function viewer:GetEffectiveScale() return self.scale end
local container = { scale = 1 }
function container:SetSize(width, height) self.width, self.height = width, height end
function container:ClearAllPoints() self.point = nil end
function container:SetPoint(point, relative, relativePoint, x, y)
    self.point = { point, relative, relativePoint, x, y }
end
function container:GetCenter() return 500, 500 end
function container:GetEffectiveScale() return self.scale end

_G.MSUF_GetUsableCooldownAnchorSize = function(frame)
    if frame == viewer then return 360, viewer.height end
end
_G.MSUF_GetEffectiveCooldownFrame = function(name)
    assert(name == "EssentialCooldownViewer")
    return viewer
end
_G.MSUF_CacheUnitFrameScreenPosition = function(_, _, _, point)
    assert(point == "BOTTOM", "the cached combat edge must match the live anchor")
end
_G.MSUF_DB = { player = {
    showPowerBar = true, powerBarDetached = true,
    detachedPowerBarAnchorToClassPower = true,
    detachedPowerBarHeight = 6, detachedPowerBarOffsetY = -4,
} }

local build = assert(_G.MSUF_CP_CORE_BUILDERS.LAYOUT)({
    CP = { container = container }, _cpDB = {}, CPConst = {},
})
local function Upvalue(fn, wanted)
    for i = 1, 30 do
        local name, value = debug.getupvalue(fn, i)
        if name == wanted then return value end
        if name == nil then break end
    end
    error("missing upvalue " .. wanted)
end
local layout = Upvalue(build.CP_Layout, "Layout")
local pass = Upvalue(layout.Position, "pass")
pass.playerFrame, pass.h, pass.userW = {}, 4, 360
pass.inLockdown, pass.cdmName = false, nil
pass.b = { classPowerAnchorToCooldown = true, classPowerOffsetY = 0 }

local function Position(expectedGap)
    layout.Position()
    local point = assert(container.point)
    assert(point[1] == "BOTTOM" and point[2] == viewer and point[3] == "TOP",
        "ClassPower must follow the Essential top edge")
    assert(point[5] == expectedGap, "unexpected gap above Essential: " .. tostring(point[5]))
end

Position(14) -- 4px Essential gap + 6px Player Power + 4px bar gap.
viewer.height = 80
Position(14) -- A taller preset must not push resources into Essential.
pass.b.classPowerOffsetY = 58 -- Legacy Quick Setup: 40px viewer + 4px class + 14px stack.
pass.b.classPowerCooldownTopAnchor = nil
viewer.height = 40
Position(14)
assert(pass.b.classPowerCooldownTopAnchor == true and pass.b.classPowerOffsetY == 0,
    "legacy offset must migrate to a stable above-Viewer offset")
viewer.height = 80
Position(14)
pass.b.classPowerOffsetY = 5
Position(19) -- The Y control must work after migration.
viewer.height, viewer.scale = 40, 2
pass.b.classPowerOffsetY, pass.b.classPowerCooldownTopAnchor = 98, nil
Position(14) -- Existing positions migrate in the resource bar's scale.
pass.b.classPowerOffsetY, pass.b.classPowerCooldownTopAnchor = 110, nil
Position(26) -- A user's additional spacing survives the one-time conversion.
viewer.height = 80
Position(26)
container._msufAnchorOnly = true
Position(26) -- A spec with no visible resource still reserves the Power row.
_G.MSUF_DB.player.powerBarDetached = false
pass.b.classPowerOffsetY = 0
Position(4)
_G.MSUF_DB.player.powerBarDetached = true
_G.MSUF_DB.player.detachedPowerBarShape = "ORB"
_G.MSUF_DB.player.detachedPowerOrbSize = 54
Position(62)

print("classpower_cooldown_stack_smoke: OK")
