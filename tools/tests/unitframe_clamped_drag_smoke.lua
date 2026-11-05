-- A native screen clamp changes GetCenter/GetLeft without changing GetPoint.
-- Dragging must start at the visible button, not its saved off-screen offset.
-- Runs the real client graph, unit runtime, mover scripts and drag ticker.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
local world = World.New(root, "Forever")
local env, core = world.env, world.core
env.MAX_BOSS_FRAMES = 5
env.TotemFrame = false
env.UnitClass = function() return "Hunter", "HUNTER", 3 end
env.UnitExists = function() return true end
env.UnitIsConnected = function() return true end
env.UnitHealth = function() return 800 end
env.UnitHealthMax = function() return 1000 end
env.UnitHealthPercent = function() return 80 end
env.UnitPower = function() return 50 end
env.UnitPowerMax = function() return 100 end
env.UnitPowerPercent = function() return 50 end
env.UnitLevel = function() return 60 end
env.AbbreviateLargeNumbers = tostring
env.AbbreviateNumbers = tostring
env.BreakUpLargeNumbers = tostring
env.GetPhysicalScreenSize = function() return 2560, 1440 end
env.C_PetInfo = { GetPetHappiness = function() return 3, 1.25, 0 end }
world:Boot()
local failure = world:FirstFailure()
assert(not failure, failure and failure.message)
local function Public(name)
    return core.PublicGlobals and core.PublicGlobals[name] or env[name]
end
-- The generic boot fixture treats unknown native globals as callable tables.
-- Unit-frame names use the full addon prefix, so mark their absence explicitly.
for _, unit in ipairs(core.UF.unitOrder) do env[core.UF.FrameName(unit)] = false end
Public("MSUF_InitProfiles")()
local db = env.MSUF_DB
db.general.anchorToCooldown, db.general.anchorName = false, "UIParent"
db.general.msufUiScale, db.general.editModeSnapEnabled = 1, false
db.general.UIScale = { Enabled = false, Scale = 1 }
local ui = env.UIParent
ui.width, ui.height, ui.scale = 1366, 768, 1
ui.left, ui.bottom = 0, 0
local conf = db.pet
conf.enabled, conf.width, conf.height = true, 220, 30
core.UF.Factory.SpawnAll()
local frame = assert(core.UF.frames.pet)
local EM2 = core.EditModeController or Public("MSUF_EM2")
local POINTS = { CENTER = { .5, .5 }, TOP = { .5, 1 }, BOTTOM = { .5, 0 }, LEFT = { 0, .5 }, RIGHT = { 1, .5 },
    TOPLEFT = { 0, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { 0, 0 }, BOTTOMRIGHT = { 1, 0 } }

-- Model the native distinction: raw anchor points remain unchanged while a
-- clamped frame reports its actual visible rectangle in its own scale units.
local function NativeCenter(self)
    if type(self.allPoints) == "table" then
        local target = self.allPoints
        local x, y = target:GetCenter()
        local factor = target:GetEffectiveScale() / self:GetEffectiveScale()
        return x * factor, y * factor
    end
    local point, anchor, relativePoint, x, y = self:GetPoint()
    if not point then return 0, 0 end
    anchor = anchor or self:GetParent()
    local own, relative = assert(POINTS[point]), assert(POINTS[relativePoint])
    local scale, anchorScale = self:GetEffectiveScale(), anchor:GetEffectiveScale()
    local ax = anchor:GetLeft() + anchor:GetWidth() * relative[1]
    local ay = anchor:GetBottom() + anchor:GetHeight() * relative[2]
    local cx = ax * anchorScale / scale + (x or 0) + (.5 - own[1]) * self:GetWidth()
    local cy = ay * anchorScale / scale + (y or 0) + (.5 - own[2]) * self:GetHeight()
    if self.clampedToScreen then
        local halfW, halfH = self:GetWidth() / 2, self:GetHeight() / 2
        local screenW, screenH = ui:GetWidth() * ui:GetEffectiveScale() / scale, ui:GetHeight() * ui:GetEffectiveScale() / scale
        cx = math.max(halfW, math.min(screenW - halfW, cx))
        cy = math.max(halfH, math.min(screenH - halfH, cy))
    end
    return cx, cy
end
local function NativeGeometry(region)
    region.GetCenter = NativeCenter
    region.GetWidth = function(self)
        local target = self.allPoints
        if type(target) == "table" then return target:GetWidth() * target:GetEffectiveScale() / self:GetEffectiveScale() end
        return self.width
    end
    region.GetHeight = function(self)
        local target = self.allPoints
        if type(target) == "table" then return target:GetHeight() * target:GetEffectiveScale() / self:GetEffectiveScale() end
        return self.height
    end
    region.GetLeft = function(self) return (self:GetCenter()) - self:GetWidth() / 2 end
    region.GetRight = function(self) return (self:GetCenter()) + self:GetWidth() / 2 end
    region.GetBottom = function(self) local _, y = self:GetCenter(); return y - self:GetHeight() / 2 end
    region.GetTop = function(self) local _, y = self:GetCenter(); return y + self:GetHeight() / 2 end
end
NativeGeometry(frame)
local function CenterUI(region)
    local x, y = region:GetCenter()
    local factor = region:GetEffectiveScale() / ui:GetEffectiveScale()
    return x * factor, y * factor
end
local function RootBounds()
    local x, y = CenterUI(frame)
    local factor = frame:GetEffectiveScale() / ui:GetEffectiveScale()
    local halfW, halfH = frame:GetWidth() * factor / 2, frame:GetHeight() * factor / 2
    return x - halfW, x + halfW, y + halfH, y - halfH
end
local registry = assert(EM2.Registry.Get("pet"))
-- Cosmetic descendants are not laid out by client_world. Their real native
-- rectangles follow this button; the regression exercises its mover bounds.
registry.getMoverBounds = RootBounds
assert(EM2.State.Enter("pet"))
world.widgets:RunTimers()
local mover = assert(EM2.Movers.Get("pet"))
NativeGeometry(mover)
local cursorX, cursorY
env.GetCursorPosition = function() return cursorX, cursorY end
env.IsMouseButtonDown = function() return true end
local ticker
for _, candidate in ipairs(world.widgets.frames) do
    if candidate.frameName == "MSUF_EM2_TickerFrame" then ticker = candidate end
end
assert(ticker, "drag ticker not created")
local failures, checks = {}, 0
local function Check(ok, message)
    checks = checks + 1
    if not ok then failures[#failures + 1] = message end
end
local function Near(a, b) return math.abs(a - b) <= 1.1 end
local function Prepare(case)
    ui.scale = case.uiScale or 1
    frame:SetScale(case.frameScale or 1)
    conf.point, conf.relativePoint = case.point or "CENTER", case.relativePoint or "CENTER"
    conf.anchorFrameName, conf.anchorToUnitframe = case.external and "ClampDragExternal" or nil, "GLOBAL"
    conf.screenPositionMode = case.tagged and "relativeHeight" or nil
    conf.screenPositionHeight = case.tagged and 1440 or nil
    conf.offsetX, conf.offsetY = case.x, case.y
    core.UF.Config.RefreshUnit("pet")
    core.UF.Factory.ForceReanchor("pet")
    local _, actualAnchor = frame:GetPoint()
    if actualAnchor and actualAnchor._msufUnitExternalAnchorProxy == true then NativeGeometry(actualAnchor) end
    EM2.Movers.SyncKey("pet")
    local x, y = CenterUI(mover)
    cursorX, cursorY = x * ui:GetEffectiveScale(), y * ui:GetEffectiveScale()
end
local cases = {
    { name = "release Pet at left edge", x = -785, y = -294, dx = 100, dy = 0, tagged = true },
    { name = "untagged left edge", x = -900, y = 0, dx = 80, dy = 0 },
    { name = "right edge", x = 900, y = 0, dx = -80, dy = 0 },
    { name = "top edge", x = 0, y = 600, dx = 0, dy = -80 },
    { name = "bottom edge", x = 0, y = -600, dx = 0, dy = 80 },
    { name = "top-left point", x = -200, y = 100, point = "TOPLEFT", relativePoint = "TOPLEFT", dx = 80, dy = -80 },
    { name = "mixed anchor points", x = -1800, y = 100, point = "RIGHT", relativePoint = "TOPRIGHT", dx = 80, dy = -80 },
    { name = "fractional effective scale", x = -900, y = 0, uiScale = .8, frameScale = 1.25, dx = 80, dy = 0 },
    { name = "smaller frame", x = 1000, y = 0, uiScale = .7, frameScale = .8, dx = -80, dy = 0 },
    { name = "ordinary unclamped offsets", x = -200.25, y = -80.25, dx = 80, dy = 40, exact = true },
    { name = "external frame", x = 10, y = 20, dx = 80, dy = 40, external = true, exact = true },
}
local external = env.CreateFrame("Frame", "ClampDragExternal", ui)
external.left, external.bottom, external.width, external.height = 500, 300, 200, 100
external:SetPoint("CENTER", ui, "CENTER", 0, 0)
env.ClampDragExternal = external
for _, case in ipairs(cases) do
    Prepare(case)
    local startX, startY = CenterUI(frame)
    local oldX, oldY = conf.offsetX, conf.offsetY
    Check(mover:GetScript("OnMouseDown")(mover, "LeftButton") == true, case.name .. ": drag rejected")
    mover:GetScript("OnDragStart")(mover, "LeftButton")
    cursorX = cursorX + case.dx * ui:GetEffectiveScale()
    cursorY = cursorY + case.dy * ui:GetEffectiveScale()
    ticker:GetScript("OnUpdate")(ticker, .06)
    local x, y = CenterUI(frame)
    Check(Near(x, startX + case.dx) and Near(y, startY + case.dy), case.name .. ": visible button did not follow the cursor")
    mover:GetScript("OnDragStop")(mover, "LeftButton")
    mover:GetScript("OnMouseUp")(mover, "LeftButton")
    world.widgets:RunTimers()
    local endX, endY = CenterUI(frame)
    local moverX, moverY = CenterUI(mover)
    Check(Near(endX, x) and Near(endY, y), case.name .. ": runtime apply snapped the button back")
    Check(Near(moverX, endX) and Near(moverY, endY), case.name .. ": mover sync snapped away from the button")
    if case.exact then
        Check(conf.offsetX == oldX + case.dx and conf.offsetY == oldY + case.dy,
            case.name .. ": normal saved coordinates were rebased")
    end
    if case.external then
        local _, actualAnchor = frame:GetPoint()
        Check(actualAnchor == external or actualAnchor._msufExternalAnchorSource == external,
            "external frame: drag replaced the configured anchor provider")
    end
end

Prepare({ x = -900, y = 0 })
local unchangedX, unchangedY = conf.offsetX, conf.offsetY
local writes, realSetPoint = 0, frame.SetPoint
frame.SetPoint = function(self, ...)
    writes = writes + 1
    return realSetPoint(self, ...)
end
Check(mover:GetScript("OnMouseDown")(mover, "LeftButton") == true, "clamped click rejected")
ticker:GetScript("OnUpdate")(ticker, .016)
Check(writes == 0 and conf.offsetX == unchangedX and conf.offsetY == unchangedY, "stationary click wrote the corrected origin")
Check(mover:GetScript("OnMouseUp")(mover, "LeftButton") == false, "stationary click counted as a move")
Check(conf.offsetX == unchangedX and conf.offsetY == unchangedY, "stationary click rewrote saved offsets")
frame.SetPoint = realSetPoint
Prepare({ x = -900, y = 0 })
local originX, originY = CenterUI(frame)
local initialCursorX = cursorX
Check(mover:GetScript("OnMouseDown")(mover, "LeftButton") == true, "out-and-back drag rejected")
cursorX = initialCursorX + 30 * ui:GetEffectiveScale()
ticker:GetScript("OnUpdate")(ticker, .016)
cursorX = initialCursorX
ticker:GetScript("OnUpdate")(ticker, .016)
Check(mover:GetScript("OnMouseUp")(mover, "LeftButton") == true, "returning to visible origin skipped the changed offset commit")
world.widgets:RunTimers()
local spec = core.UF.Config.GetSpec("pet")
Check(spec.x == conf.offsetX and spec.y == conf.offsetY, "out-and-back drag left the compiled position stale")
core.UF.Factory.ForceReanchor("pet")
local returnedX, returnedY = CenterUI(frame)
Check(Near(returnedX, originX) and Near(returnedY, originY), "out-and-back runtime refresh changed the final visible position")
local drag = assert(EM2.Ticker.BeginExternalDrag(mover, "pet", registry, { bar = frame, offsetX = 12, offsetY = 34 }))
Check(drag.unitStartX == 12 and drag.unitStartY == 34, "explicit external-shell drag origin was overwritten")
EM2.Ticker.EndExternalDrag(drag, false)
assert(#failures == 0, "unitframe_clamped_drag_smoke failed:\n" .. table.concat(failures, "\n"))
print("unitframe_clamped_drag_smoke: PASS (" .. checks .. " checks)")
