local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local h = Harness.New(root, flavor, { beforeBoot = function(harness)
    MenuWorld.InstallNativeUnitInputs(harness.world)
    local env = harness.env
    env.MAX_BOSS_FRAMES = 5
    local power = env.Enum.PowerType
    env.UnitClass = function() return "Rogue", "ROGUE", 4 end
    env.C_SpecializationInfo.GetSpecialization = function() return 2 end
    env.UnitPowerType = function() return power.Energy, "ENERGY" end
    local unitPower = env.UnitPower
    env.UnitPower = function(unit, kind, ...)
        if kind == power.ComboPoints then
            harness.comboReads = (harness.comboReads or 0) + 1
        end
        return unitPower(unit, kind, ...)
    end
    env.UnitPowerMax = function(_, kind) return kind == power.ComboPoints and 7 or 100 end
    env.GetUnitChargedPowerPoints = function() return { 2 } end
    harness.physicalHeight = 1024
    env.GetPhysicalScreenSize = function() return 1920, harness.physicalHeight end
end })
local surface = assert(h.core.UF.PreviewSurfaces.ClassPower)
local bars = {
    showClassPower = true, classPowerHeight = 10, classPowerWidthMode = "custom",
    classPowerWidth = 209.3, classPowerGap = 1, classPowerTickWidth = 1,
    classPowerShape = "BAR", classPowerOutline = 0,
}
local scene = {
    root = { parent = h.env.UIParent },
    opts = { scale = 0.9, sample = { class = "ROGUE", spec = 1, maximum = 7, bars = bars } },
}
scene.frame = surface.Create(scene)
local cp = scene.CP
local PixelSize = h.core.Require("MSUF_GetPhysicalPixelSize", "class resources pip test")

local function Pixels(value)
    local pixels = value / PixelSize(cp.container, 1)
    local nearest = math.floor(pixels + 0.5)
    assert(math.abs(pixels - nearest) < 0.000001, ("off-grid geometry: %.6f pixels"):format(pixels))
    return nearest
end

local function CheckPips(count, expectedWidth, expectedGap, start, trailing, tickWidth, minWidth, maxWidth)
    assert(cp.currentMax == count, "unexpected number of pips")
    assert(Pixels(cp.container:GetWidth()) == expectedWidth, "unexpected container width")
    local endX = start
    for i = 1, count do
        local bar = cp.bars[i]
        local point, anchor, relativePoint, x = bar:GetPoint()
        local side = bars.classPowerFillReverse and "TOPRIGHT" or "TOPLEFT"
        assert(point == side and anchor == cp.container and relativePoint == side, "pip anchor changed")
        local offset, width = Pixels(math.abs(x)), Pixels(bar:GetWidth())
        assert(offset == endX, ("pip %d has an uneven gap"):format(i))
        assert(width >= minWidth and width <= maxWidth, "pip consumed an uneven share of the row")
        endX = offset + width
        local tick = cp.ticks[i]
        if i < count then
            if tickWidth > 0 then
                local tickSide, tickAnchor, tickRelative, tickOffset = tick:GetPoint()
                assert(tick:IsShown() and Pixels(tick:GetWidth()) == tickWidth, "unexpected separator width")
                assert(tickSide == side and tickAnchor == cp.container and tickRelative == side, "separator anchor changed")
                assert(Pixels(math.abs(tickOffset)) == endX + math.floor((expectedGap - tickWidth) / 2),
                    "separator shifted inside the gap")
            else
                assert(not tick:IsShown(), "unexpected separator")
            end
            endX = endX + expectedGap
        end
    end
    assert(endX == expectedWidth - trailing, "last pip does not reach the expected edge")
end

-- Seven rectangular pips occupy 251 pixels including six identical dividers.
-- Reverse mirrors the same grid. Reducing the gap allows adjacent pips to meet.
for _, reverse in ipairs({ false, true }) do
    bars.classPowerFillReverse = reverse
    surface.Paint(scene)
    CheckPips(7, 251, 2, 0, 0, 1, 34, 35)
end
bars.classPowerFillReverse, bars.classPowerGap, bars.classPowerTickWidth = false, 0, 0
surface.Paint(scene)
CheckPips(7, 251, 0, 0, 0, 0, 35, 36)

-- The second effective scale has a different pixel budget. This also
-- exercises centering an odd amount of spare space and reversing the row.
scene.opts.scale = 0.75
bars.classPowerShape, bars.classPowerGap, bars.classPowerTickWidth = "CIRCLE", 1, 4
for _, alignment in ipairs({ "LEFT", "CENTER", "RIGHT" }) do
    bars.classPowerShapeAlign = alignment
    local left = alignment == "LEFT" and 0 or (alignment == "RIGHT" and 133 or 67)
    for _, reverse in ipairs({ false, true }) do
        bars.classPowerFillReverse = reverse
        surface.Paint(scene)
        local right = 133 - left
        CheckPips(7, 209, 1, reverse and right or left, reverse and left or right, 0, 10, 10)
    end
end

bars.classPowerWidthMode, bars.classPowerGap = "auto_pips", 3
surface.Paint(scene)
CheckPips(7, 88, 3, 0, 0, 0, 10, 10)

-- Following the player must round its measured width once, on the pixel grid.
scene.opts.scale, scene.opts.playerWidth = 0.9, 209.3
bars.classPowerShape, bars.classPowerWidthMode = "BAR", "player"
bars.classPowerGap, bars.classPowerTickWidth = 1, 1
surface.Paint(scene)
CheckPips(7, 251, 2, 0, 0, 1, 34, 35)

-- Cooldown Manager supplies a fractional width in layout units. The
-- physical width stays the same when the protected anchor is frozen.
scene.opts.scale = 1.25
bars.classPowerWidthMode, bars.classPowerFillReverse = "cooldown", false
scene.opts.cooldowns = { EssentialCooldownViewer = { width = 209.4 } }
surface.Paint(scene)
CheckPips(7, 349, 4, 0, 0, 2, 46, 47)
scene.opts.cooldowns.EssentialCooldownViewer.width = 300
h.widgets:SetCombat(true)
surface.Paint(scene)
CheckPips(7, 349, 4, 0, 0, 2, 46, 47)
h.widgets:SetCombat(false)

-- A single-icon provider near the old 30-unit cutoff stays eligible.
scene.opts.cooldowns.EssentialCooldownViewer.width = 29.6
surface.Paint(scene)
CheckPips(7, 49, 4, 0, 0, 2, 3, 4)
scene.opts.cooldowns.EssentialCooldownViewer.width = 300
h.widgets:SetCombat(true)
surface.Paint(scene)
CheckPips(7, 49, 4, 0, 0, 2, 3, 4)
h.widgets:SetCombat(false)

bars.classPowerWidthMode, bars.classPowerWidth = "custom", 207.8
for _, height in ipairs({ 768, 1080, 1440 }) do
    h.physicalHeight = height
    scene.opts.scale = height == 768 and 0.85 or 1.1
    local pixel = 768 / height / scene.opts.scale
    local rowPixels = math.floor(bars.classPowerWidth / pixel + 0.5)
    local tickPixels = math.floor(1 / pixel + 0.5)
    for count = 1, 10 do
        scene.opts.sample.maximum = count
        surface.Paint(scene)
        local average = (rowPixels - (count - 1) * 2 * tickPixels) / count
        CheckPips(count, rowPixels, 2 * tickPixels, 0, 0, tickPixels, math.floor(average), math.ceil(average))
    end
end
h.physicalHeight = 1024
bars.classPowerWidth = 209.3

-- The real display event must redistribute the existing runtime pips.
if flavor == "Mainline" or flavor == "Forever" then
    h:RunTimers()
    local env = h.env
    local player = env.CreateFrame("Frame", nil, env.UIParent)
    player:SetSize(209.3, 30)
    h.UF.frames.player = player
    h.UF.frameList[#h.UF.frameList + 1] = player
    env.UIParent:SetScale(0.9)
    local liveBars = h.UF.Config.GetDB().bars
    for key, value in pairs(bars) do liveBars[key] = value end
    liveBars.classPowerWidthMode, liveBars.classPowerFillReverse = "custom", false
    liveBars.showChargedComboPoints = true
    local refresh = h.core.Require("MSUF_ClassPower_Refresh", "class resources pip test")
    refresh()
    local container
    for _, frame in ipairs(h.widgets.frames) do
        if frame:GetName() == "MSUF_ClassPowerContainer" then container = frame break end
    end
    assert(container and container:IsShown(), "runtime resource row missing")
    local liveCP = { container = container, currentMax = 7, bars = {}, ticks = {} }
    for _, child in ipairs({ container:GetChildren() }) do
        if child:GetObjectType() == "StatusBar" then liveCP.bars[#liveCP.bars + 1] = child end
    end
    for _, region in ipairs({ container:GetRegions() }) do
        if region:GetDrawLayer() == "OVERLAY" then liveCP.ticks[#liveCP.ticks + 1] = region end
    end
    assert(#liveCP.bars >= 7 and #liveCP.ticks >= 6, "runtime pip pool missing")
    cp, bars = liveCP, liveBars
    CheckPips(7, 251, 2, 0, 0, 1, 34, 35)
    local charged = liveCP.bars[2]._bg
    local r, g, b, a = charged:GetVertexColor()
    if flavor == "Mainline" then assert(a == 1, "charged pip fixture was not active") end
    env.UIParent:SetScale(0.75)
    h:Event("UI_SCALE_CHANGED")
    CheckPips(7, 209, 2, 0, 0, 1, 28, 29)
    local rr, gg, bb, aa = charged:GetVertexColor()
    assert(rr == r and gg == g and bb == b and aa == a, "display relayout changed the resource paint")

    liveBars.classPowerIndependentVisibility = true
    refresh()
    assert(container:GetParent() ~= player, "independent visibility did not reparent the row")
    env.MSUF_ApplyMsufScale(1.25)
    h:RunTimers()
    assert(container:GetEffectiveScale() == player:GetEffectiveScale(), "independent row missed the MSUF frame scale")
    CheckPips(7, 262, 2, 0, 0, 1, 35, 36)

    -- Combat begins after SetScale but before its coalesced reanchor.
    env.MSUF_ApplyMsufScale(1.1)
    h:EnterCombat()
    h:RunTimers()
    h:LeaveCombat()
    h:RunTimers()
    assert(container:GetEffectiveScale() == player:GetEffectiveScale(), "deferred scale was not replayed after combat")
    CheckPips(7, 230, 2, 0, 0, 1, 31, 32)

    local reads = h.comboReads
    container.IsProtected = function() return true end
    h.widgets:SetCombat(true)
    local resize = h.core.Require("MSUF_ClassPower_RefreshLayout", "class resources pip test")
    resize(true)
    assert(h.comboReads == reads, "refused protected relayout still repainted")
    h.widgets:SetCombat(false)
end

print("PASS classpower_pip_layout_smoke " .. flavor)
