-- The runtime grid must quantize the pitch and preserve settings and wrap capacity.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local w = World.Open(root, flavor)
local core = w.core
local visual = core.MSUF_Auras3.Runtime.ButtonVisuals
local pixelSize = core.Require("MSUF_GetPhysicalPixelSize", "aura physical grid test")
local scale = 0.8
local owner = { _msufPixelLayoutEnabled = true }
function owner:GetEffectiveScale() return scale end
function owner:SetFlowLayoutMaximumLineSize(size) self.limit = size end
function owner:SetFlowLayoutPadding(left, right, top, bottom)
    assert(left == right and right == top and top == bottom, "asymmetric aura padding")
    self.padding = left
end
local function Close(actual, expected)
    assert(math.abs(actual - expected) < 1e-5, ("%g differs from %g"):format(actual, expected))
end
local lane = { buttonWidth = 22, buttonHeight = 17, spacing = 1, width = 22 * 7 + 6 + 4, padding = 2 }
local rawWidth, rawHeight, rawSpacing, rawLimit, rawPadding =
    lane.buttonWidth, lane.buttonHeight, lane.spacing, lane.width, lane.padding
for _, value in ipairs({ 0.25, 0.64, 0.8, 1.0, 1.23 }) do
    scale = value
    local pixel = pixelSize(owner)
    assert(visual.GridPixel(owner) == pixel, "grid ignored effective owner scale")
    local width, height, gap = visual.GridMetrics(lane, pixel)
    Close(width / pixel, math.floor(rawWidth / pixel + 0.5))
    Close(height / pixel, math.floor(rawHeight / pixel + 0.5))
    Close(gap / pixel, math.max(1, math.floor(rawSpacing / pixel + 0.5)))
    visual.SyncPixelFlow(owner, lane)
    Close(owner.limit, width * 7 + gap * 6 + pixel * 0.125)
    Close(owner.padding / pixel, math.floor(rawPadding / pixel + 0.5))
end
assert(lane.buttonWidth == rawWidth and lane.buttonHeight == rawHeight and lane.spacing == rawSpacing
    and lane.width == rawLimit and lane.padding == rawPadding, "layout rewrote configured values")
owner._msufPixelLayoutEnabled = nil
assert(visual.GridPixel(owner) == nil, "legacy owner adopted physical grid")
visual.SyncPixelFlow(owner, lane)
assert(owner.limit == rawLimit - 2 * rawPadding and owner.padding == rawPadding, "legacy layout changed")
-- Combined buff/debuff rows keep their unbounded native flow and the original
-- layout indices. The item enchant group must use the same pixel gap.
local groups = core.MSUF_Auras3.Runtime.Containers
local written = {}
function owner:SetAuraGroupLayout(key, options) written[key] = options end
function owner:SetItemEnchantmentLayout(options) self.enchantment = options end
owner._msufPixelLayoutEnabled = true
owner._msufA3GroupSlotsRoot = true
owner._msufA3ManagedGroupKey = "buff"
owner._msufA3FlowLayoutIndex = 1
owner._msufA3EnchantmentLayoutIndex = 0
owner._msufA3TrailingFlowGroup = { _msufA3ManagedGroupKey = "debuff", _msufA3FlowLayoutIndex = 2 }
local buff = { buttonWidth = 22, buttonHeight = 17, spacing = 1, width = 156, weaponEnchants = true }
local debuff = { buttonWidth = 24, buttonHeight = 18, spacing = 2, width = 172 }
groups.RefreshFlowOwner(owner, {
    flowLane = buff, trailingFlowLane = debuff,
    flowGeometry = { combinedAuraBarFlow = true, padding = 2 },
})
assert(owner.limit == nil, "combined aura flow gained a finite line limit")
assert(written.buff.layoutIndex == 1 and written.debuff.layoutIndex == 2 and owner.enchantment.layoutIndex == 0,
    "flow refresh reordered group placement")
assert(written.buff.elementWidth == owner.enchantment.elementWidth
    and written.buff.elementSpacing == owner.enchantment.elementSpacing,
    "weapon enchants use a different grid from buffs")
assert(buff.spacing == 1 and debuff.spacing == 2, "flow refresh rewrote the profile layout")
function owner:CanBeAccessedInContext() return false end
function owner:GetEffectiveScale() error("restricted aura geometry was read") end
assert(visual.GridPixel(owner) == nil, "restricted owner opted into the physical grid")
local A3 = core.MSUF_Auras3
local edgeFrame = { MSUFNormalOutlineBounds = {
    pixelSize = .6, runtimeOutset = 1.8, frameWidth = 200, frameHeight = 80, leftOffset = -1.65, rightOffset = 1.74,
    bottomOffset = -1.68, topOffset = 1.62,
} }
local row = { kind = "buff", anchor = "TOPLEFT", initialAnchor = "TOPLEFT", xSign = 1, ySign = -1,
    size = 25, buttonWidth = 25, buttonHeight = 25, spacing = 1, padding = 3, width = 135, height = 31, max = 5 }
local function VerifyPlacement(x, y, expectedX, expectedY, expectedSnap)
    local px, py, solved = A3.ResolveOutlineLaneOffset(edgeFrame, row, x, y, 1)
    Close(px, expectedX)
    Close(py, expectedY)
    assert((solved == true) == expectedSnap, "wrong native anchor rounding policy")
end
VerifyPlacement(-5, 30, -4.65, 29.82, true)
VerifyPlacement(-6, 31, -6, 31, false)
row.anchor, row.initialAnchor, row.xSign, row.ySign = "BOTTOMRIGHT", "BOTTOMRIGHT", -1, 1
VerifyPlacement(5, -30, 4.74, -29.88, true)
row.anchor, row.initialAnchor = "TOPRIGHT", "BOTTOMLEFT"
row.xSign, row.ySign = 1, 1
VerifyPlacement(134, 30, 133.74, 29.82, true)
row.anchor = "CENTER"
VerifyPlacement(0, 0, 0, 0, false)
row.anchor, row.initialAnchor = "TOPLEFT", "TOPLEFT"
row.xSign, row.ySign = 1, -1
row.iconStyle = { borderEnabled = true, borderThickness = 2 }
VerifyPlacement(-3, 32, -2.85, 31.62, true)
row.iconStyle = { borderEnabled = true, borderThickness = 2, borderTexture = "skin", borderEdge = 6, borderPlacement = "inner" }
VerifyPlacement(-5, 30, -4.65, 29.82, true)
row.portraitOverlay = true
VerifyPlacement(-5, 30, -5, 30, false)
row.portraitOverlay = nil
row.max = 1
VerifyPlacement(-2, 27, -1.65, 26.82, true)
local bounds = edgeFrame.MSUFNormalOutlineBounds
bounds.runtimeOutset, bounds.pixelSize = 0, 1.5
bounds.leftOffset = .7
row.iconStyle, row.max, row.padding, row.anchor = nil, 1, 0, "LEFT"
local x1, _, solved1 = A3.ResolveOutlineLaneOffset(edgeFrame, row, 0, 40, 1)
bounds.pixelSize, bounds.leftOffset = 1.5 / 4, .1
local x4, _, solved4 = A3.ResolveOutlineLaneOffset(edgeFrame, row, 0, 40, 4)
assert(solved1 and solved4, "viewport phase changed which saved integer can sit flush")
Close(x1, .7)
Close(x4, .1)
-- A single slot's nominal padding does not create a second inset. Its real
-- rectangle and static skin, including independent x/y extent, determine contact.
bounds.pixelSize, bounds.runtimeOutset = .6, 1.8
bounds.leftOffset, bounds.topOffset = -1.65, 1.62
local styled = { kind = "spellIndicator", visual = "icon", anchor = "TOPLEFT", size = 20,
    width = 30, height = 12, padding = 9, x = 2, y = 15, iconShape = "RECTANGLE",
    iconStyle = { skin = { def = { shape = "RECTANGLE", layers = {
        { kind = "quad", extentX = 4, extentY = 2 },
        { kind = "quad", file = "msuf_skin_shadow_soft", extent = 16 },
    } } } } }
local px, py, snapped = A3.ResolveOutlineLaneOffset(edgeFrame, styled, styled.x, styled.y)
assert(snapped, "rectangular skinned slot could not reach outside bounds")
Close(px - 4.2 - bounds.leftOffset, 0)
Close(py - 12 - 1.2 - bounds.topOffset, 0)
local nativePixel = bounds.pixelSize
bounds.pixelSize, bounds.runtimeOutset = .8, 1.6
local fixed = { visual = "icon", anchor = "LEFT", size = 24, x = -2, y = -2 }
local _, manualY, manualMatch = A3.ResolveOutlineLaneOffset(edgeFrame, fixed, fixed.x, fixed.y)
assert(manualMatch)
Close(manualY, -2.4) -- the other axis keeps the original signed native half-pixel rounding
bounds.pixelSize = nativePixel

-- A sealed one-icon button captures this proxy once. Bounds changes move only
-- the proxy, including the first OOC replay when the real native owner was born in combat.
local unit = w.env.CreateFrame("Frame", nil, w.env.UIParent)
unit.MSUFSpec, unit.MSUFNormalOutlineBounds = {}, bounds
bounds.pixelSize, bounds.runtimeOutset = .6, 1.8
bounds.leftOffset, bounds.topOffset, bounds.revision = -1.65, 1.62, 1
local slot = { kind = "buff", rootKey = "Buffs", initialAnchor = "TOPLEFT", anchor = "TOPLEFT",
    x = -2, y = 27, size = 25, width = 31, height = 31, buttonWidth = 25, buttonHeight = 25, padding = 3, max = 1 }
local native = {}
local proxy, x, y = A3.ResolveOutlineSlotAnchor(unit, slot, "Buffs", native)
assert(proxy ~= unit and x == 0 and y == 0 and native._msufA3OutlineSlotLanes.Buffs == slot)
local function CheckProxy(expectedX, expectedY)
    local point, ownerFrame, relativePoint, px, py = proxy:GetPoint(1)
    assert(point == "TOPLEFT" and relativePoint == point and ownerFrame == unit)
    Close(px, expectedX)
    Close(py, expectedY)
end
CheckProxy(-1.65, 26.82)
local originalSetPoint, writes = proxy.SetPoint, 0
proxy.SetPoint = function(self, ...)
    writes = writes + 1
    return originalSetPoint(self, ...)
end
A3.RefreshOutlineLaneAnchors(unit)
assert(writes == 0, "warm bounds rewrote slot geometry")
bounds.leftOffset, bounds.revision = -1.81, 2
A3.RefreshOutlineLaneAnchors(unit)
CheckProxy(-1.81, 26.82)
assert(writes == 1, "cold bounds change did not move the slot proxy once")

w.world:EnterCombat()
local fresh = { _msufA3StructuralSignature = "new" }
local frameCount = w:Frames()
local ref, rawX, rawY = A3.ResolveOutlineSlotAnchor(unit, slot, "CombatBorn", fresh)
assert(ref == unit and rawX == slot.x and rawY == slot.y and w:Frames() <= frameCount + 1,
    "combat-born fixed button did not retain its original native anchor") -- one shared regen driver at most
assert(not unit._msufA3OutlineSlotProxies.CombatBorn, "combat allocated a new slot proxy")
bounds.topOffset, bounds.revision = 1.51, 3
proxy.IsProtected = function() return true end
proxy.SetPoint = function() error("protected slot moved in combat") end
A3.ResolveOutlineSlotAnchor(unit, slot, "Buffs", native)
A3.RefreshOutlineLaneAnchors(unit)
CheckProxy(-1.81, 26.82)
proxy.SetPoint = originalSetPoint
w.world:LeaveCombat()
if A3._pendingOutlineOwners then
    local driver = A3._deferredAuraRuntimeFrame
    driver:GetScript("OnEvent")(driver, "PLAYER_REGEN_ENABLED")
end
assert(not A3._pendingOutlineOwners and not fresh._msufA3StructuralSignature,
    "regen did not invalidate the specific combat-born owner")
assert(native._msufA3OutlineSlotLanes.Buffs == slot, "regen lost the previously bound slot")
CheckProxy(-1.81, 26.71)
assert(A3.ResolveOutlineSlotAnchor(unit, slot, "CombatBorn", fresh) ~= unit)
assert(slot.x == -2 and slot.y == 27 and slot.padding == 3, "the slot solver rewrote the profile")
-- Generated reminders retain the same origin and cell dimensions in each row.
-- Their native AuraSlot, missing placeholder and secure button share the proxy.
local reminderIDs = { 17, 18, 19, 20, 21, 22, 23 }
local allowed = {}
for _, id in ipairs(reminderIDs) do allowed[id] = true end
for _, anchor in ipairs({ "TOPLEFT", "CENTER", "BOTTOMRIGHT" }) do
    for _, spacing in ipairs({ -1, 0, 2 }) do
        local size = 17
        local grid = { unit = "player", anchor = anchor, x = 8, y = -7, max = 8, perRow = 3,
            sourceSpellIDs = allowed, size = size, spacing = spacing, step = size + spacing, xSign = -1, ySign = 1 }
        local definition = { prioritySpellIDs = reminderIDs, reminderEnchantMainHand = true }
        local items = assert(A3.Runtime.CustomConfig.CompileCustomReminderItems(grid, definition, 1, { reminderEnabled = true }, {}))
        local slots = assert(A3.SpellIndicators.CompileSlots("player", { enabled = true, items = items })).slots
        assert(#slots == 8 and slots[8].enchantSlot == "MAINHAND")
        for _, zoom in ipairs({ 1, 4 }) do
            local pixel = 1 / 1.37
            bounds.pixelSize = pixel / zoom
            local pitch = (math.floor(size / pixel + .5) +
                (spacing < 0 and -1 or 1) * math.floor(math.abs(spacing) / pixel + .5)) * pixel
            local firstX, firstY = A3.ResolveOutlineLaneOffset(unit, slots[1], slots[1].x, slots[1].y, zoom)
            for i, reminder in ipairs(slots) do
                local col, row = -((i - 1) % 3), math.floor((i - 1) / 3)
                local x, y = A3.ResolveOutlineLaneOffset(unit, reminder, reminder.x, reminder.y, zoom)
                Close(x, firstX + col * pitch)
                Close(y, firstY + row * pitch)
                assert(reminder.x == grid.x + col * grid.step and reminder.y == grid.y + row * grid.step)
            end
        end
    end
end

-- A number or effect-only slot has no canvas to cover a filled border.
-- Squares, however, keep their original frame around the coloured swatch.
local spells = A3.SpellIndicators
local style = { borderEnabled = true, borderThickness = 2, borderR = 0, borderG = 0, borderB = 0, borderA = 1,
    shadowEnabled = true, shadowSize = 5, shadowR = 0, shadowG = 0, shadowB = 0, shadowA = 1 }
local preview = w.env.CreateFrame("Frame", nil, w.env.UIParent)
preview.hpBar = w.env.CreateFrame("StatusBar", nil, preview)
local resolveConfig = A3.ResolveAuraPreviewConfig
local function Noop() end
local function VerifySquareEdges(visual, size, band)
    local flat = visual._msufA3StyleBorder
    local pieces = visual._msufA3StyleBorderPieces
    local edge = band and pieces[1] or flat
    assert(edge:IsShown() and visual:GetWidth() == size and visual:GetHeight() == size)
    local _, _, _, x, y = edge:GetPoint(1)
    Close(x, band and -4 or -2)
    Close(y, band and 4 or 2)
    local shadow = visual._msufA3StyleShadow
    for i = 1, 8 do
        assert(shadow[i]:IsShown() == (i <= 4 or size > 14), "incorrect square shadow geometry")
    end
    _, _, _, x, y = shadow[1]:GetPoint(1)
    Close(x, -7)
    Close(y, 7)
end
local function CheckIndicator(display, size, band)
    style.borderTexture = band and "Interface\\DialogFrame\\UI-DialogBox-Border" or nil
    style.borderEdge = 8
    local indicator = { enabled = true, key = "testSpell", includeSpellIDs = { [17] = true },
        placed = { type = display, anchor = "TOPLEFT", size = size },
        color = { .24, .51, .79, .85 }, frame = display == "none" and { type = "tint" } or nil }
    local compiled = assert(spells.CompileSlots("party1", { enabled = true, items = { indicator } }, { iconStyle = style }))
    local container = w.env.CreateFrame("Frame", nil, unit)
    container._msufA3ParentFrame = unit
    function container:AddAuraSlot(key, filter, options)
        local button = w.env.CreateFrame("Button", nil, self)
        for _, method in ipairs({ "SetIcon", "ClearIcon", "SetDurationCooldown", "ClearDurationCooldown",
            "SetDurationBar", "ClearDurationBar", "SetDurationText", "ClearDurationText", "SetApplicationCount",
            "ClearApplicationCount", "AddDispelTypeTexture", "ClearDispelTypeTextures", "SetDispelTypeText",
            "ClearDispelTypeText", "SetMouseClickEnabled", "SetMouseMotionEnabled", "SetCancelAuraButtons" }) do
            button[method] = Noop
        end
        options.initializeFrame(button)
        self.testButton = button
    end
    spells.AttachSlots(container, compiled)
    local button = assert(container.testButton)
    local border = button._msufA3StyleBorder
    if display == "square" then
        assert(button._msufA3SpellIndicatorSwatch:IsShown())
        VerifySquareEdges(button, size, band)
    else
        assert((border and border:IsShown() or false) == (display == "icon"), display .. " runtime border")
    end
    if display == "none" then assert(compiled.slots[1].frameEffect and not button.Icon:IsShown()) end
    A3.ResolveAuraPreviewConfig = function() return { spellIndicators = compiled } end
    assert(core.GF.PreviewSpellIndicators(preview, "party", nil, "party1", false))
    local standIn = assert(preview._msufGFSpellIndicatorPreviews[1])
    border = standIn._msufA3StyleBorder
    if display == "square" then
        assert(standIn._texture:IsShown() and standIn._msufSquareTextureOverlay)
        VerifySquareEdges(standIn, size, band)
    else
        assert((border and border:IsShown() or false) == (display == "icon"), display .. " preview border")
        assert(not standIn._msufSquareTextureOverlay)
    end
    if display == "number" then assert(standIn._stack:IsShown()) end
end
CheckIndicator("icon", 18)
for _, size in ipairs({ 12, 18, 31 }) do
    CheckIndicator("square", size, false)
    CheckIndicator("square", size, true)
end
CheckIndicator("number", 18)
CheckIndicator("none", 18)
CheckIndicator("bar", 18)
A3.ResolveAuraPreviewConfig = resolveConfig
-- ALL-mode dispel types keep their reserved positions (including absent
-- types). Every adjacent pair uses the same pitch, even at 4x preview zoom.
local symbols = A3.DispelSymbol
for _, growth in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
    for _, gap in ipairs({ 0, 2 }) do
        local sensor = { kind = "dispelSymbol", visual = "symbol", x = 8, y = -7,
            size = 17, spacing = gap, growth = growth, anchor = "CENTER" }
        sensor.slots = symbols.Slots(sensor, sensor.size, gap)
        assert(#sensor.slots == 5)
        local runtimePixel = 1 / 1.37
        for _, zoom in ipairs({ 1, 4 }) do
            bounds.pixelSize, unit._msufBorderPreviewZoom = runtimePixel / zoom, zoom
            local originX, originY = symbols.SlotOffset(sensor, 1, unit)
            local width = math.floor(sensor.size / runtimePixel + .5) * runtimePixel
            local pitch = width + math.floor(gap / runtimePixel + .5) * runtimePixel
            for i, typedSlot in ipairs(sensor.slots) do
                local x, y, size = symbols.SlotOffset(sensor, i, unit)
                local n = i - 1
                Close(x, originX + (growth == "LEFT" and -n or growth == "RIGHT" and n or 0) * pitch)
                Close(y, originY + (growth == "DOWN" and -n or growth == "UP" and n or 0) * pitch)
                Close(size, width)
                if zoom == 1 then
                    local proxy = A3.ResolveOutlineSlotAnchor(unit, typedSlot.pixelLane, "DispelSymbol:" .. i)
                    assert(proxy ~= unit)
                    local _, relativeTo, _, rx, ry = proxy:GetPoint(1)
                    assert(relativeTo == unit)
                    Close(rx, x)
                    Close(ry, y)
                end
            end
        end
    end
end
unit._msufBorderPreviewZoom = nil
print("aura_physical_grid_smoke " .. flavor .. ": passed")
