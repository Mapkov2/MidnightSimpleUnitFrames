-- frame_outline_class_color_smoke.lua <root> <flavor>
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local colors = { MAGE = { r = .1, g = .6, b = 1 }, WARRIOR = { r = .8, g = .5, b = .2 } }
local classes = { target = "MAGE", raid1 = "MAGE", raid2 = "WARRIOR" }
local classReads, threat = 0, 0
local targetIsPlayer = true
local physicalHeight, logicalHeight = 1440, 768
local h = Harness.New(root, flavor, { beforeBoot = function(h)
    local env = h.env
    env.issecretvalue, env.type = issecretvalue, type
    env.GetPhysicalScreenSize = function() return 2560, physicalHeight end
    env.GetScreenHeight = function() return logicalHeight / env.UIParent:GetEffectiveScale() end
    local rosterExists = env.UnitExists
    env.UnitExists = function(unit) return unit == "target" or rosterExists(unit) end
    local rosterGUID = env.UnitGUID
    env.UnitGUID = function(unit)
        if unit == "raid1" then return "Player-raid1-" .. classes.raid1 end
        return rosterGUID(unit)
    end
    env.UnitIsPlayer = function(unit)
        if unit == "target" then return targetIsPlayer end
        return true
    end
    env.UnitClass = function(unit)
        classReads = classReads + 1
        return "Class", classes[unit], 1
    end
    env.UnitThreatSituation = function() return threat end
    env.RAID_CLASS_COLORS = colors
end })

local db, UF, GF = h.env.MSUF_DB, h.UF, h.GF
local target = h.env.CreateFrame("Button", nil, h.env.UIParent)
target.MSUFUnitKey = "target"
UF.frames.target = target
db.bars.barOutlineThickness = 2
db.bars.barOutlineClassColor = true
db.general.barOutlineColorR, db.general.barOutlineColorG, db.general.barOutlineColorB = .2, .3, .4
db.classColors = { MAGE = { r = .15, g = .65, b = .95 } }
db.target.hlOverride, db.target.aggroOutlineMode = true, 1
assert(UF.ApplySpec(target, UF.Config.RefreshUnit("target"), nil, { Health = true, Borders = true }))

local function Check(frame, r, g, b, source)
    local actual = assert(UF.GetActiveBorderVisual(frame), "missing outline")
    assert(actual.source == source and actual.r == r and actual.g == g and actual.b == b,
        ("%s %s outline was %s %.2f %.2f %.2f"):format(frame.MSUFUnitKey, source, actual.source, actual.r, actual.g, actual.b))
end
local function Event(frame, event)
    frame:GetScript("OnEvent")(frame, event, frame.MSUFUnitKey)
end

local function CheckOutlineAnchors(frame, thickness)
    local edges = assert(frame.MSUFBorderEdges)
    local function CheckPoint(edge, index, point, owner, corner, x, y)
        local actualPoint, actualOwner, actualCorner, dx, dy = edges[edge]:GetPoint(index)
        assert(actualPoint == point and actualOwner == owner and actualCorner == corner
            and math.abs(dx - x) < .00001 and math.abs(dy - y) < .00001,
            ("%s outline %s anchor %d"):format(tostring(frame.MSUFUnitKey), edge, index))
    end
    if h.core.Client.IsRetail then
        local step = 768 / 1440 / frame:GetEffectiveScale()
        thickness = math.max(1, math.floor(thickness / step + .5)) * step
        frame = assert(frame.MSUFBorderOverlay)
        CheckPoint("top", 1, "TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
        CheckPoint("top", 2, "BOTTOMRIGHT", frame, "TOPRIGHT", thickness, 0)
        CheckPoint("bottom", 1, "TOPLEFT", frame, "BOTTOMLEFT", -thickness, 0)
        CheckPoint("bottom", 2, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
        CheckPoint("left", 1, "TOPLEFT", frame, "TOPLEFT", -thickness, 0)
        CheckPoint("left", 2, "BOTTOMRIGHT", frame, "BOTTOMLEFT", 0, 0)
        CheckPoint("right", 1, "TOPLEFT", frame, "TOPRIGHT", 0, 0)
        CheckPoint("right", 2, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, 0)
    else
        CheckPoint("left", 1, "TOPLEFT", edges.top, "BOTTOMLEFT", 0, 0)
        CheckPoint("right", 1, "TOPRIGHT", edges.top, "BOTTOMRIGHT", 0, 0)
    end
end

local function CheckTexturedOutline(frame)
    local pieces = assert(frame.MSUFBorderTexturePieces)
    local w, h = frame:GetSize()
    local function Point(piece, index)
        local point, owner, corner, x, y = piece:GetPoint(index)
        assert(owner == frame.MSUFBorderOverlay and point == (index == 1 and "TOPLEFT" or "BOTTOMRIGHT"),
            "textured outline point must resolve directly from the frame")
        if corner:find("RIGHT", 1, true) then x = x + w end
        if corner:find("TOP", 1, true) then y = y + h end
        return x, y
    end
    local function Coord(index, axis, high)
        local x, y = Point(pieces[index], (axis == "x") == high and 2 or 1)
        return axis == "x" and x or y
    end
    for _, seam in ipairs({
        {1, 5, "x"}, {5, 2, "x"}, {3, 6, "x"}, {6, 4, "x"},
        {7, 1, "y"}, {3, 7, "y"}, {8, 2, "y"}, {4, 8, "y"},
    }) do
        local first, second, axis = seam[1], seam[2], seam[3]
        local perpendicular = axis == "x" and "y" or "x"
        assert(Coord(first, axis, true) == Coord(second, axis, false)
            and Coord(first, perpendicular, true) == Coord(second, perpendicular, true)
            and Coord(first, perpendicular, false) == Coord(second, perpendicular, false),
            ("%s textured outline seam %d/%d"):format(frame.MSUFUnitKey, seam[1], seam[2]))
    end
end

Check(target, .15, .65, .95, "normal")
CheckOutlineAnchors(target, 2)
if h.core.Client.IsRetail then
    local owner = target.MSUFBorderOverlay
    local oldScale = target.GetEffectiveScale
    target.GetEffectiveScale = function() return 1.64 * 768 / 1440 end
    local pixel = 768 / 1440 / target:GetEffectiveScale()
    local rawLeft, rawRight = 1595.49990177, 1777.49982834
    local rawBottom, rawTop = 49.51, 79.49
    local geometryReads = 0
    target.GetRect = function()
        geometryReads = geometryReads + 1
        return rawLeft * pixel, rawBottom * pixel, (rawRight - rawLeft) * pixel, (rawTop - rawBottom) * pixel
    end
    local function Near(a, b) return math.abs(a - b) < .00001 end
    assert(type(UF.GetNormalOutlineBounds) == "function", "missing stable normal outline anchor for attachments")
    local bounds = assert(UF.GetNormalOutlineBounds(target))
    local function CheckScreenRect()
        local p, relative, rp, x, y = owner:GetPoint(1)
        assert(p == "BOTTOMLEFT" and relative == target and rp == p, "screen-aligned outline origin missing")
        local q, far, rq, dx, dy = owner:GetPoint(2)
        assert(q == "TOPRIGHT" and far == target and rq == q, "outline must follow the owner's far corner")
        local left, bottom = rawLeft + x / pixel, rawBottom + y / pixel
        local right, top = rawRight + dx / pixel, rawTop + dy / pixel
        for _, v in ipairs({ left, bottom, right, top }) do
            assert(Near(v, math.floor(v + .5)), "outline boundary between physical pixels")
        end
        assert(Near(left, math.floor(rawLeft + .5)) and Near(right, math.floor(rawRight + .5)))
        local _, _, _, leftOut = target.MSUFBorderEdges.left:GetPoint(1)
        local _, _, _, rightOut = target.MSUFBorderEdges.right:GetPoint(2)
        local n = math.max(1, math.floor(target.MSUFSpec.border.thickness / pixel + .5))
        assert(bounds == UF.GetNormalOutlineBounds(target) and Near(bounds.pixelSize, pixel))
        assert(Near(bounds.leftOffset, x + leftOut) and Near(bounds.rightOffset, dx + rightOut)
            and Near(bounds.topOffset, dy + rightOut) and Near(bounds.bottomOffset, y + leftOut),
            "attachment bounds differ from the rendered outline")
        local bp, base, _, lx, by = bounds:GetPoint(1)
        local fp, edge, _, rx, ty = bounds:GetPoint(2)
        assert(bp == "BOTTOMLEFT" and fp == "TOPRIGHT" and base == target and edge == target
            and Near(lx, bounds.leftOffset) and Near(by, bounds.bottomOffset)
            and Near(rx, bounds.rightOffset) and Near(ty, bounds.topOffset))
        assert(Near(-leftOut / pixel, n) and Near(rightOut / pixel, n), "unequal physical band")
    end
    local borders = UF.elements.Borders
    db.bars.barOutlineThickness = 1
    UF.RefreshBorders("target")
    CheckScreenRect()
    -- The secure click surface, native icon and missing-aura placeholder share a
    -- bounded ordinal anchor. Re-importing different spell keys reuses it.
    local spells = h.core.MSUF_Auras3.SpellIndicators
    local slot = {kind="spellIndicator", visual="icon", anchor="TOPLEFT", x=-1, y=4,
        width=20, height=16, size=20, max=1, slotKey="alignmentOne",
        layer=5, iconShape="RECTANGLE", castSpellID=123, showWhenMissing=true}
    local function SetupIndicator(key, visual)
        slot.slotKey, slot.visual = key, visual
        local container = h.env.CreateFrame("Frame", nil, target)
        local slotRoot = {slots={slot}, spellIndicatorRoot=true, enabled=true,
            rootKey="SpellIndicators", unit="target", _msufA3StructuralSignature=key .. visual}
        assert(spells.SyncGeometry(container, slotRoot, target))
        local icon = h.env.CreateFrame("Frame", nil, target)
        spells.AnchorSlotRegion(icon, target, slot, container)
        local _, ref = icon:GetPoint(1)
        local missing = target._msufA3SpellIndicatorMissingFrames[key]
        local cast = target._msufA3ReminderCastButtons[key]
        assert(missing and cast, "missing reminder fixture")
        assert(select(2, missing:GetPoint(1)) == ref and select(2, cast:GetPoint(1)) == ref,
            "reminder icon and secure click region diverged")
        return ref
    end
    local proxy = SetupIndicator("alignmentOne", "icon")
    assert(proxy ~= target and SetupIndicator("alignmentTwo", "icon") == proxy, "proxy pool grew on spell key change")
    assert(SetupIndicator("alignmentTwo", "square") == target, "manual colored square adopted old icon anchor")
    rawLeft, rawRight = rawLeft + .35, rawRight + 1.12
    borders.RefreshPixelGeometry(target)
    CheckScreenRect()
    local getRootHeight = h.env.UIParent.GetHeight
    physicalHeight, logicalHeight = 720, 720
    h.env.UIParent.GetHeight = h.env.GetScreenHeight
    pixel = 1 / target:GetEffectiveScale()
    borders.RefreshPixelGeometry(target)
    CheckScreenRect()
    h.env.UIParent.GetHeight = function() return 685 end
    pixel = 768 / physicalHeight / target:GetEffectiveScale()
    borders.RefreshPixelGeometry(target)
    CheckScreenRect()
    h.env.UIParent.GetHeight = getRootHeight
    physicalHeight, logicalHeight = 1440, 768
    pixel = 768 / 1440 / target:GetEffectiveScale()
    borders.RefreshPixelGeometry(target)
    local reads = geometryReads
    h:EnterCombat()
    for i = 1, 64 do
        threat = i % 2 == 0 and 0 or 2
        Event(target, "UNIT_HEALTH")
        Event(target, "UNIT_THREAT_SITUATION_UPDATE")
    end
    assert(geometryReads == reads, "combat update measured the outline")
    h:LeaveCombat()
    local source = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Borders.lua"
    local rectStop = Secrets.Watch(source, { strict = true })
    target.GetRect = function() return Secrets.New("number"), 1, 100, 40 end
    borders.RefreshPixelGeometry(target)
    assert(bounds.pixelSize == nil and bounds.allPoints == target, "stale attachment bounds on restricted geometry")
    assert(owner.allPoints == target and owner:GetNumPoints() == 0, "secret geometry reused a stale correction")
    target.GetEffectiveScale = function() return Secrets.New("number") end
    borders.RefreshPixelGeometry(target)
    assert(#rectStop() == 0, "restricted geometry entered outline arithmetic")
    target.GetRect, target.GetEffectiveScale = nil, oldScale
    db.bars.barOutlineThickness = 2
    UF.RefreshBorders("target")
end
classes.target = "WARRIOR"
Event(target, "PLAYER_TARGET_CHANGED")
Check(target, .8, .5, .2, "normal")

-- Enter and leave a highlight, even as new identity data arrives behind it.
threat = 2
Event(target, "UNIT_THREAT_SITUATION_UPDATE")
assert(UF.GetActiveBorderVisual(target).source == "aggro", "class outline hid aggro")
CheckOutlineAnchors(target, target._msufBorderVisualThickness)
classes.target = "MAGE"
Event(target, "UNIT_NAME_UPDATE")
assert(UF.GetActiveBorderVisual(target).source == "aggro", "name update hid aggro")
threat = 0
classReads = 0
for _ = 1, 64 do
    Event(target, "UNIT_HEALTH")
    Event(target, "UNIT_THREAT_SITUATION_UPDATE")
end
assert(classReads == 0, "outline caused a class lookup on the health or threat route")
Check(target, .15, .65, .95, "normal")
CheckOutlineAnchors(target, 2)

targetIsPlayer = false
Event(target, "PLAYER_TARGET_CHANGED")
Check(target, .2, .3, .4, "normal")
targetIsPlayer = true
classes.target = nil
Event(target, "PLAYER_TARGET_CHANGED")
Check(target, .2, .3, .4, "normal")
classes.target = "MAGE"
Event(target, "UNIT_NAME_UPDATE")
Check(target, .15, .65, .95, "normal")

local sourceRoot = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/"
local stop = Secrets.Watch({
    sourceRoot .. "MSUF_UF_Elements_Borders.lua",
    sourceRoot .. "MSUF_UF_Elements_BarsCommon.lua",
}, { strict = true })
classes.target = Secrets.New("string")
Event(target, "UNIT_NAME_UPDATE")
Check(target, .2, .3, .4, "normal")
assert(#stop() == 0, "restricted class escaped the class resolver")

db.target.barOutlineClassColor = false
UF.RefreshBorders("target")
assert(target.MSUFSpec.border.classColor == false, "explicit off did not override shared class outlines")
Check(target, .2, .3, .4, "normal")

local function CheckSecureChildGeometry(member)
    if not h.core.Client.IsRetail then return end
    local borders = UF.elements.Borders
    local oldRect, oldScale = member.GetRect, member.GetEffectiveScale
    assert(member._msufIsGroupFrameShell and not member._msufGFPreviewScene)
    local point, parent, relative, shellX, shellY = member:GetPoint(1)
    local scale = 1.37
    member.GetEffectiveScale = function() return scale end
    local phase, reads = .49, 0
    member.GetRect = function()
        reads = reads + 1
        return (1600 + phase) / scale, (200 + phase) / scale, 104, 27
    end
    local overlay = assert(member.MSUFBorderOverlay)
    local bounds = assert(h.UF.GetNormalOutlineBounds(member))
    for _, value in ipairs({ .49, .5, .51 }) do
        phase = value
        borders.RefreshPixelGeometry(member)
        assert(overlay._msufBorderLeft == 0 and overlay._msufBorderRight == 0
            and overlay._msufBorderBottom == 0 and overlay._msufBorderTop == 0,
            "secure header border retained an obsolete screen-space offset")
        local outset = assert(overlay._msufNormalOutset)
        assert(bounds.leftOffset == -outset and bounds.rightOffset == outset
            and bounds.bottomOffset == -outset and bounds.topOffset == outset,
            "docked group aura bounds did not follow the secure child")
    end
    h.widgets:SetCombat(true)
    local before = reads
    phase = .75
    borders.RefreshPixelGeometry(member)
    assert(reads == before, "combat read screen coordinates")
    h.widgets:SetCombat(false)
    local p, host, r, x, y = member:GetPoint(1)
    assert(p == point and host == parent and r == relative and x == shellX and y == shellY)
    member.GetRect, member.GetEffectiveScale = oldRect, oldScale
    borders.RefreshPixelGeometry(member)
end

-- Secure group children consume the same compiled color on roster changes.
local raid = GF.GetConf("raid")
raid.enabled, raid.preserveRaidGroups = true, false
raid.hlOverride, raid.barOutlineThickness = true, 2
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(2)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local member = assert(GF.FrameForUnit("raid1"), "raid member missing")
Check(member, .15, .65, .95, "normal")
classes.raid1 = "WARRIOR"
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
Check(member, .8, .5, .2, "normal")
CheckOutlineAnchors(member, 2)
CheckSecureChildGeometry(member)

local party = GF.GetConf("party")
party.enabled, party.hlOverride, party.barOutlineThickness = true, true, 1
GF.InvalidateCompiledSpecs("party")
h:SetRoster({ "player", "party1" })
GF.RefreshHeaderLayout()
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local partyMember = assert(GF.FrameForUnit("party1"), "party member missing")
CheckOutlineAnchors(partyMember, 1)
CheckSecureChildGeometry(partyMember)
if h.core.Client.IsRetail then
    local host = h.env.CreateFrame("Frame", nil, h.env.UIParent)
    local scene = GF.NewPreviewScene(host)
    scene:Activate()
    for _, kind in ipairs({ "party", "raid" }) do
        local cell = scene:Group(kind)
        cell:Show(1, { immediate = true })
        local sample = assert(cell:Frames()[1])
        local first = 1595.49990177
        local scale = 1.64 * 768 / 1440
        local zoom = 1
        sample.GetEffectiveScale = function() return scale * zoom end
        sample.GetRect = function()
            local step = 768 / 1440 / (scale * zoom)
            return first * step, 40 * step, 111, 16
        end
        for _, nextZoom in ipairs({ 1, 4, .85 }) do
            zoom = nextZoom
            cell:Configure({ scale = zoom })
            cell:Show(1, { immediate = true })
            local overlay = sample.MSUFBorderOverlay
            local _, relative, _, dx = overlay:GetPoint(1)
            local step = 768 / 1440 / (scale * zoom)
            assert(relative == sample and math.abs(first + dx / step - math.floor(first + .5)) < .00001,
                kind .. " cached preview kept stale placement")
            local width = GF.GetConf(kind).barOutlineThickness
            local pixels = math.max(1, math.floor(math.floor(width * 1.64 + .5) * zoom + .5))
            assert(math.abs(overlay._msufBorderBands[width] / step - pixels) < .00001, kind .. " zoom changed the live band")
            first = first + .35
        end
    end
    scene:Deactivate()

    local boss = h.env.CreateFrame("Button", nil, h.env.UIParent)
    boss.MSUFUnitKey = "boss1"
    boss:SetSize(111, 16)
    boss.left, boss.bottom = 75.2, 20.3
    UF.AttachFrame(boss, { scope = "single" })
    local bossSpec = UF.Config.GetSpec("boss1")
    assert(UF.ApplySpec(boss, bossSpec, nil, { Health = true, Power = true, Borders = true }))
    assert(boss._msufBossPhysicalGeometryApplied, "boss physical bar layout did not run")
    local pixel = 768 / 1440 / boss:GetEffectiveScale()
    local scale = boss:GetEffectiveScale()
    boss.hpBar.GetEffectiveScale = function() return scale end
    boss.hpBar.GetRect = function() return 75.6, 25.1, 110.5, 10.9 end
    local embedded = boss.targetPowerBar and bossSpec.power.enabled and not bossSpec.power.detached
        and bossSpec.power.embed ~= false and not boss._msufPowerResourceMissing
    if embedded then
        boss.targetPowerBar.GetEffectiveScale = function() return scale end
        boss.targetPowerBar.GetRect = function() return 75.6, 20.8, 110.5, 4.3 end
    end
    UF.elements.Borders.RefreshPixelGeometry(boss)
    local _, a, _, x, y = boss.MSUFBorderOverlay:GetPoint(1)
    local _, z, _, dx, dy = boss.MSUFBorderOverlay:GetPoint(2)
    local function Match(v, expected)
        return math.abs(v / pixel - math.floor(expected / pixel + .5)) < .00001
    end
    assert(a == boss and z == boss and Match(75.2 + x, 75.6) and Match(186.2 + dx, 186.1)
        and Match(20.3 + y, embedded and 20.8 or 25.1) and Match(36.3 + dy, 36), "boss outline missed the resolved bars")
    local bounds = assert(UF.GetNormalOutlineBounds(boss))
    local band = boss.MSUFBorderOverlay._msufNormalOutset
    assert(Match(75.2 + bounds.leftOffset + band, 75.6)
        and Match(186.2 + bounds.rightOffset - band, 186.1)
        and Match(20.3 + bounds.bottomOffset + band, embedded and 20.8 or 25.1),
        "boss attachments ignored the painted bars")
    CheckOutlineAnchors(boss, boss._msufBorderThickness)

    db.target.barOutlineTexture = "BORDER:BLIZZARD"
    UF.RefreshBorders("target")
    assert(target.MSUFSpec.border.textureMode == h.core.BorderStyles.FRAME_BORDER, "target True Outline did not apply")
    CheckTexturedOutline(target)

    party.barOutlineTexture = "BORDER:BLIZZARD"
    GF.InvalidateCompiledSpecs("party")
    GF.RefreshVisuals("party", GF.DIRTY_BORDER)
    assert(partyMember.MSUFSpec.border.textureMode == h.core.BorderStyles.FRAME_BORDER, "party True Outline did not apply")
    CheckTexturedOutline(partyMember)
end
print("frame_outline_class_color_smoke: ok " .. flavor)
