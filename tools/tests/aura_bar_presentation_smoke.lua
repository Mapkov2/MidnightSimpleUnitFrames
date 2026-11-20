-- aura_bar_presentation_smoke.lua <root> <flavor>
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local cursorX, cursorY, mouseHeld = 300, 400, false
local mw = MenuWorld.Open(root, flavor, { page = "home", beforeCore = function(world)
    local methods = world.widgets.Methods
    world.env.GetCursorPosition = function() return cursorX, cursorY end
    world.env.IsMouseButtonDown = function(button) return button == "LeftButton" and mouseHeld end
    world.env.C_AddOns.IsAddOnLoaded = function() return true end
    if flavor == "Mainline" or flavor == "Forever" then
        world.env.UnitIsPlayerControlledOrGroupMember = function(unit)
            return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
        end
    end
    world.env.AnchorUtil = { FlowDirection = { Left = -1, Right = 1, Down = -1, Up = 1 },
        FlowLayoutAxis = { Horizontal = 0, Vertical = 1 } }
    local function Noop() end
    for _, method in ipairs({ "AddAuraSlot", "AddItemEnchantment", "SetAuraSlotFilterString",
        "SetAuraSlotCandidateFilters", "SetAuraSlotSortMethod", "SetFlowLayoutAnchorPoint" }) do
        methods[method] = Noop
    end
    function methods:SetFlowLayoutAxis(axis) self.auraSmokeAxis = axis end
    function methods:SetFlowLayoutGrowthDirection(x, y) self.auraSmokeX, self.auraSmokeY = x, y end
    function methods:SetFlowLayoutMaximumLineSize(size) self.auraSmokeLimit = size end
    function methods:SetEnabled(enabled) self.auraSmokeEnabled = enabled end
    function methods:SetUnit(unit) self.auraSmokeUnit = unit end
    function methods:GetUnit() return self.auraSmokeUnit end
    function methods:AddAuraGroup(key, filter, options)
        self.auraSmokeGroups = self.auraSmokeGroups or {}
        assert(not self.auraSmokeGroups[key], "native AuraGroup was registered twice")
        self.auraSmokeGroups[key] = { filter = filter, max = options.maxFrameCount }
    end
    function methods:SetAuraGroupFilterString(key, filter) self.auraSmokeGroups[key].filter = filter end
    function methods:SetAuraGroupCandidateFilters(key, filters) self.auraSmokeGroups[key].candidates = filters end
    function methods:SetAuraGroupSortMethod(key, sort) self.auraSmokeGroups[key].sort = sort end
    function methods:SetAuraGroupMaxFrameCount(key, count) self.auraSmokeGroups[key].max = count end
    function methods:SetAuraGroupLayout(key, layout) self.auraSmokeGroups[key].layout = layout end
    function methods:SetOrientation(value) self.orientation = value end
    function methods:SetReverseFill(value) self.reverseFill = value end
    local setTexture = methods.SetStatusBarTexture
    function methods:SetStatusBarTexture(texture, ...)
        self.auraBarSmokeTexture = texture
        return setTexture(self, texture, ...)
    end
    local setBarColor, setVertexColor = methods.SetStatusBarColor, methods.SetVertexColor
    function methods:SetStatusBarColor(r, g, b, a)
        self.auraBarSmokeColor = { r, g, b, a }
        return setBarColor(self, r, g, b, a)
    end
    function methods:SetVertexColor(r, g, b, a)
        self.auraBarSmokeVertex = { r, g, b, a }
        return setVertexColor(self, r, g, b, a)
    end
    local setValue = methods.SetValue
    function methods:SetValue(value, ...)
        self.auraBarSmokeValue = value
        return setValue(self, value, ...)
    end
end })
local core, env, menu = mw.core, mw.env, mw.M
local auras, groupFrames = core.MSUF_Auras3, core.GF
local model = auras.MenuModel
local native = flavor == "Mainline" or flavor == "Forever"

local function AssertLegacyImport()
    local profile = {
        auras3 = {
            shared = { buffShowDurationBar = true, buffDurationBarDisplay = "BAR_ONLY" },
            perUnit = { target = { overrideLayout = true, layout = {
                buffShowDurationBar = false,
                debuffShowDurationBar = true, debuffDurationBarDisplay = "BAR_ONLY", debuffDurationBarDirection = "ELAPSED",
            } } },
        },
        gf_party = { auras = {
            enabled = true, renderer = "CUSTOM",
            buff = { enabled = true, showDurationBar = true, durationBarDisplay = "BAR_ONLY" },
            debuff = { showDurationBar = true, durationBarDisplay = "OVERLAY" },
        } },
    }
    core.ProfileNormalize.TranslateProfileToCurrent(profile, { source = "legacy_aura_import", markProfile = true })
    auras.NormalizeProfileDB(profile)
    groupFrames.RepairGroupDB(profile)
    local target = profile.auras3.perUnit.target.layoutShared
    local party = profile.gf_party.auras
    assert((profile.auras3.shared.buffShowAuraBars == true) == native, "legacy shared buff lost")
    assert(target.buffShowAuraBars ~= true, "legacy per-unit Off lost to shared preference")
    assert((target.debuffShowAuraBars == true) == native, "legacy unit Style setting lost")
    assert((party.buff.showAuraBars == true) == native, "legacy group buff lost")
    assert(party.debuff.showAuraBars ~= true, "icon overlay promoted to a full bar")
    if native then
        assert(target.debuffDurationBarDirection == "ELAPSED", "legacy elapsed timer lost")
        assert(party.debuff.showDurationBar and party.debuff.durationBarDisplay == "OVERLAY", "group icon overlay lost")
        assert(party.renderer == "CUSTOM" and party.enabled and party.buff.enabled, "group bar would remain hidden")
    end
end

AssertLegacyImport()
local db = env.MSUF_DB
local target = db.auras3.perUnit.target.layoutShared
db.auras3.enabled, db.auras3.showTarget = true, true
target.showBuffs, target.maxBuffs = true, 3
target.buffShowDurationBar, target.buffDurationBarDisplay = true, "BAR_ONLY"
target.buffDurationBarDirection = "ELAPSED"
target.buffShowAuraBars = nil
auras.NormalizeProfileDB(db)
assert((target.buffShowAuraBars == true) == native, "canonical unit Style migration did not respect client")
if not native then
    print("aura_bar_presentation_smoke " .. flavor .. ": legacy migration gated")
    return
end

local fill = {
    { "RIGHT", "HORIZONTAL", false, "LEFT" }, { "LEFT", "HORIZONTAL", true, "RIGHT" },
    { "UP", "VERTICAL", false, "OUTSIDE_LEFT" }, { "DOWN", "VERTICAL", true, "OUTSIDE_RIGHT" },
}
local function AssertFill(sample, direction)
    assert(sample and sample:IsShown(), "expected a visible native-status-bar sample")
    assert(sample.orientation == direction[2] and sample.reverseFill == direction[3], "fill direction " .. direction[1])
end

local function AssertColor(actual, r, g, b, a)
    assert(actual and math.abs(actual[1] - r) < 0.0001 and math.abs(actual[2] - g) < 0.0001
        and math.abs(actual[3] - b) < 0.0001 and math.abs(actual[4] - a) < 0.0001, "aura bar color mismatch")
end

local function AssertAppearance(sample, lane, placement)
    local appearance = assert(lane.auraBarAppearance)
    local icon = assert(sample._msufA3AuraBarIcon)
    local side = placement:find("LEFT", 1, true) and "LEFT" or "RIGHT"
    assert(icon:IsShown() and icon:GetWidth() == appearance.iconSize, "missing or wrongly sized aura icon")
    assert(appearance.iconAnchor == side and icon:GetPoint(1) == side, "aura icon placed on the wrong side")
    if placement:find("OUTSIDE", 1, true) then
        assert(lane.buttonWidth == appearance.barWidth + appearance.iconSize + 4, "outside icon footprint lost its gap")
    else
        assert(appearance.barWidth == lane.buttonWidth, "inside icon escaped the bar")
    end
    assert(sample.auraBarSmokeTexture == appearance.texture, "preview lost selected bar texture")
    local outline = appearance.outlineTexture and sample._msufA3AuraBarEdge or sample._msufA3AuraBarStrips
    assert(outline[1]:IsShown(), "solid or textured bar outline was not painted")
    AssertColor(sample.auraBarSmokeColor, 0.32, 0, 0.72, 0.86)
    AssertColor(outline[1].auraBarSmokeVertex, 0.2, 0.66, 0, 1)
end

local function Appearance(placement)
    return { iconPlacement = placement, iconSize = 100, iconGap = 4, texture = "Blizzard",
        outline = placement == "RIGHT" and "BLIZZARD" or "SOLID", outlineThickness = 2,
        fillColorMode = "CUSTOM", fillColor = { 0.32, 0, 0.72 },
        outlineColorMode = "CUSTOM", outlineColor = { 0.2, 0.66, 0 } }
end

assert(mw:Select("uf_target"))
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(500, 300)
local scene = menu.PreviewHelpers.NewRuntimeUnitSurface(host, "target", {})
local layoutFrame = env.CreateFrame("Frame", nil, env.UIParent)
layoutFrame:SetSize(150, 30)
layoutFrame:SetPoint("CENTER")
layoutFrame:Show()
auras._runtimeFrames = auras._runtimeFrames or {}
auras._runtimeFrames.target = layoutFrame
local editState = core.PublicGlobals.MSUF_EditState
editState.active = true
core.ExportPublic("MSUF_UnitPreviewActive", true)
db.auras3.shared.showInEditMode = true

for _, direction in ipairs(fill) do
    model.WriteLaneAuraBarFill("target", "buff", direction[1])
    model.WriteLaneAuraBarStyle("target", "buff", Appearance(direction[4]))
    assert(model.ReadLaneAuraBarStyle("target", "buff").iconPlacement == direction[4])
    assert(model.ReadLaneAuraBarFill("target", "buff") == direction[1])
    auras.BumpRuntimeConfig()
    local lane = auras.ResolveUnitFrameConfig("target").lanes.buff
    assert(lane.auraBarFill == direction[1] and lane.durationBarDirection == "ELAPSED")
    assert(lane.verticalGrowth and lane.perRow == 1 and lane.buttonWidth > lane.buttonHeight)
    local frame = scene:Refresh()
    local visual = frame._msufGFFrameAuraPreviews[1]
    AssertFill(visual._msufA3AuraBarSample, direction)
    AssertAppearance(visual._msufA3AuraBarSample, lane, direction[4])
    assert(visual:GetWidth() == lane.buttonWidth and visual:GetHeight() == lane.buttonHeight, "unit preview dimensions differ")

    auras.RefreshEditPreview("target")
    local mover = auras.EditMode.groups.target.buff
    assert(mover.Body:GetWidth() == lane.width and mover.Body:GetHeight() == lane.height, "Edit Mode bounds differ")
    local editBar = mover._icons[1]._msufA3AuraBarSample
    AssertFill(editBar, direction)
    AssertAppearance(editBar, lane, direction[4])
    assert(auras.RefreshEditPreviewAnimation("target", 1))
    local previous = editBar.auraBarSmokeValue
    assert(auras.RefreshEditPreviewAnimation("target", 4) and editBar.auraBarSmokeValue ~= previous,
        "Edit Mode did not update the bar through its existing preview clock")
end

local function AssertNativeColorBinding(lane, expectedCount, mode, outline)
    local painter = auras.MockAuraPainter
    local button = painter.NewNativeSample(host, { name = "Buff", duration = 20, remaining = 7 })
    local bindings = {}
    function button:SetCancelAuraButtons() end
    function button:SetMouseMotionEnabled() end
    function button:SetMouseClickEnabled() end
    function button:ClearDispelTypeTextures() bindings = {} end
    function button:AddDispelTypeTexture(texture, options)
        local parent = texture:GetParent()
        while parent and parent ~= self do parent = parent:GetParent() end
        assert(parent == self, "tint target is outside the native aura button")
        assert(options.showAlways and options.style == env.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset)
        bindings[#bindings + 1] = { texture = texture, map = options.customDispelColorMap }
    end
    auras.Runtime.ButtonVisuals.PrepareAuraButton(button, lane, 1)
    assert(#bindings == expectedCount, "native aura bar tint bound the wrong number of textures")
    if expectedCount == 0 then return end
    assert(bindings[1].texture == button._msufA3DurationBar:GetStatusBarTexture(),
        "automatic fill missed the native StatusBar texture")
    local map = bindings[1].map
    local r, g, b = auras.GetDispelTypeColor("Magic")
    if mode == "DARK" then r, g, b = 0.05 + 0.36 * r, 0.05 + 0.36 * g, 0.05 + 0.36 * b end
    AssertColor({ map.Magic:GetRGBA() }, r, g, b, 1)
    assert(map[""] == map.None and map.Enrage == map.None, "untyped native colors diverged from the lane fallback")
    local edge, bright = bindings[2].texture, bindings[2].map
    local expectedEdge = outline == "BLIZZARD" and button._msufA3DurationBar._msufA3AuraBarEdge
        or button._msufA3DurationBar._msufA3AuraBarStrips
    assert(edge == expectedEdge[1], "automatic outline missed the selected border")
    AssertColor({ bright.None:GetRGBA() }, 0.28, 0.72, 0.49, 1)
end

local function AssertAuraBarColors(mode, outline, expectedCount)
    local style = Appearance("LEFT")
    style.fillColorMode, style.outlineColorMode, style.outline = mode, "AUTO", outline
    model.WriteLaneAuraBarStyle("target", "buff", style)
    auras.BumpRuntimeConfig()
    local lane = auras.ResolveUnitFrameConfig("target").lanes.buff
    local unit = scene:Refresh()._msufGFFrameAuraPreviews[1]._msufA3AuraBarSample
    auras.RefreshEditPreview("target")
    local edit = auras.EditMode.groups.target.buff._icons[1]._msufA3AuraBarSample
    local r, g, b = 0.28, 0.72, 0.49
    if mode == "DARK" then r, g, b = 0.05 + 0.36 * r, 0.05 + 0.36 * g, 0.05 + 0.36 * b end
    AssertColor(unit.auraBarSmokeColor, r, g, b, 1)
    AssertColor(edit.auraBarSmokeColor, r, g, b, 1)
    for _, sample in ipairs({ unit, edit }) do
        local border = outline == "BLIZZARD" and sample._msufA3AuraBarEdge or sample._msufA3AuraBarStrips
        AssertColor(border[1].auraBarSmokeVertex, 0.28, 0.72, 0.49, 1)
    end
    AssertNativeColorBinding(lane, expectedCount, mode, outline)
end

env.MSUF_DB.general.dispelTypeColorOverrides = { Magic = { 0.22, 0.86, 0.6 } }
auras.InvalidateNativeVisualInputs()
AssertAuraBarColors("AUTO", "SOLID", 5)
AssertAuraBarColors("DARK", "BLIZZARD", 9)
model.WriteLaneAuraBarStyle("target", "buff", Appearance("RIGHT"))
auras.BumpRuntimeConfig()
AssertNativeColorBinding(auras.ResolveUnitFrameConfig("target").lanes.buff, 0)

model.WriteLaneAuraBars("target", "debuff", true)
model.WriteLaneAuraBarStyle("target", "debuff", { fillColorMode = "AUTO", outline = "SOLID", outlineColorMode = "AUTO" })
auras.SetDispelColorPreviewType("Magic")
auras.BumpRuntimeConfig()
auras.RefreshEditPreview("target")
local editDebuff = auras.EditMode.groups.target.debuff._icons[1]._msufA3AuraBarSample
AssertColor(editDebuff.auraBarSmokeColor, 0.22, 0.86, 0.6, 1)
db.general.dispelTypeColorOverrides.Magic = { 0.1875, 0.25, 0.5625 }
auras.RefreshNativeVisuals()
auras.RefreshEditPreview("target")
AssertColor(editDebuff.auraBarSmokeColor, 0.1875, 0.25, 0.5625, 1)
AssertColor(editDebuff._msufA3AuraBarStrips[1].auraBarSmokeVertex, 0.1875, 0.25, 0.5625, 1)

local staleEditBar = auras.EditMode.groups.target.buff._icons[1]._msufA3AuraBarSample
local revisedStyle = Appearance("OUTSIDE_RIGHT")
revisedStyle.texture = "RaidHP"
model.WriteLaneAuraBarStyle("target", "buff", revisedStyle)
auras.BumpRuntimeConfig()
auras.RefreshEditPreview("target")
assert(staleEditBar.auraBarSmokeTexture == core.Media.ResolveTextureCandidate("RaidHP"),
    "Edit Mode ignored the texture change within the same footprint")

model.WriteLaneAuraBarStyle("target", "buff", {})
auras.BumpRuntimeConfig()
auras.RefreshEditPreview("target")
assert(not staleEditBar._msufA3AuraBarIcon:IsShown(), "pooled edit row kept the removed icon")
assert(not staleEditBar._msufA3AuraBarStrips[1]:IsShown(), "pooled edit row kept the removed outline")
assert(not staleEditBar._msufA3AuraBarEdge[1]:IsShown(), "pooled edit row kept the textured outline")
local r, g, b = auras.GetDurationBarColor()
AssertColor(staleEditBar.auraBarSmokeColor, r, g, b, auras.MockAuraPainter.AURA_BAR_FILL_ALPHA)
assert(staleEditBar.auraBarSmokeTexture ~= core.Media.ResolveTextureCandidate("Blizzard"), "pooled edit row kept the old texture")

editState.active = false
core.ExportPublic("MSUF_UnitPreviewActive", false)
auras.RefreshEditPreview("target")
assert(not auras.EditMode.groups.target.buff:IsShown(), "Edit Mode leaked the aura mover")

model.WriteLaneAuraBars("target", "buff", false)
auras.NormalizeProfileDB(db)
auras.BumpRuntimeConfig()
local disabled = auras.ResolveUnitFrameConfig("target").lanes.buff
assert(target.buffShowAuraBars == false and not disabled.auraBarFill and not disabled.showDurationBar, "explicit Off remigrated")
local frame = scene:Refresh()
local visual = frame._msufGFFrameAuraPreviews[1]
assert(not visual._msufA3AuraBarSample:IsShown() and visual._texture:IsShown(), "preview slot did not return to the icon")

local focus = db.auras3.perUnit.focus.layoutShared
focus.buffShowAuraBars = nil
assert(model.CopyUnitStyle("target", "focus"))
auras.NormalizeProfileDB(db)
assert(focus.buffShowAuraBars ~= true, "Style copy reactivated a migrated Layout option")

local party = groupFrames.GetConf("party")
party.enabled, party.auras.enabled, party.auras.renderer = true, true, "CUSTOM"
party.auras.buff.enabled, party.auras.buff.max = true, 3
party.auras.buff.showDurationBar, party.auras.buff.durationBarDisplay = true, "BAR_ONLY"
party.auras.buff.showAuraBars = nil
groupFrames.RepairGroupDB(db)
assert(party.auras.buff.showAuraBars == true, "canonical group Style migration missing")

local preview = groupFrames.NewPreviewScene(host)
preview:Activate()
local group = preview:Group("party")
for _, direction in ipairs(fill) do
    party.auras.buff.auraBarFill = direction[1]
    party.auras.buff.auraBarStyle = Appearance(direction[4])
    groupFrames.InvalidateCompiledSpecs("party")
    auras.BumpRuntimeConfig()
    group:Hide()
    group:Show(1, { immediate = true })
    local cell = group:Frames()[1]
    assert(cell.MSUFSpec.auras.buffAuraBarFill == direction[1], "group Style dropped direction")
    local visual = cell._msufGFFrameAuraPreviews[1]
    AssertFill(visual._msufA3AuraBarSample, direction)
    AssertAppearance(visual._msufA3AuraBarSample, visual._sceneAuraLane, direction[4])
end

local debuff = party.auras.debuff
debuff.enabled, debuff.max, debuff.showAuraBars = true, 2, true
debuff.auraBarStyle = { fillColorMode = "DARK", outline = "SOLID", outlineColorMode = "AUTO" }
groupFrames.InvalidateCompiledSpecs("party")
auras.BumpRuntimeConfig()
group:Hide()
group:Show(1, { immediate = true })
local count = 0
for _, display in ipairs(group:Frames()[1]._msufGFFrameAuraPreviews) do
    if display:IsShown() and display._sceneAuraKind == "debuff" then
        count = count + 1
        local sample = assert(display._msufA3AuraBarSample)
        local r, g, b = auras.GetDispelTypeColor(auras.PreviewDispelTypeForIndex(display._sceneAuraIndex))
        AssertColor(sample.auraBarSmokeColor, 0.05 + 0.36 * r, 0.05 + 0.36 * g, 0.05 + 0.36 * b, 1)
        AssertColor(sample._msufA3AuraBarStrips[1].auraBarSmokeVertex, r, g, b, 1)
    end
end
assert(count == 2, "no distinct automatic debuff samples were checked")

assert(menu.GroupPage.CopyGroupSettings("party", "raid", { aurastyle = true }))
groupFrames.RepairGroupDB(db)
assert(db.gf_raid.auras.buff.showAuraBars ~= true, "group Style copy reactivated a migrated Layout option")

local function AssertRelativeBarPositions(first, nextBuff, nextDebuff, direction, a, b)
    local point, owner, _, x, y = first:GetPoint(1)
    local nextPoint, nextOwner, _, x2, y2 = nextBuff:GetPoint(1)
    local tailPoint, tailOwner, _, tx, ty = nextDebuff:GetPoint(1)
    assert(point == nextPoint and point == tailPoint and owner == nextOwner and owner == tailOwner,
        "joined samples did not use the same starting edge")
    if direction == "UP" or direction == "DOWN" then
        assert(x2 == x and tx == x and y2 - y == a and ty - y == b, "vertical joined bar spacing")
    else
        assert(y2 == y and ty == y and x2 - x == a and tx - x == b,
            string.format("horizontal joined bar spacing: got %.3f / %.3f, expected %.3f / %.3f", x2 - x, tx - x, a, b))
    end
end

local function AssertJoinedNative(cfg, frame, direction)
    local runtime = auras.Runtime
    local plan = runtime.OwnerConfig.GetNativeOwnerPlan(cfg)
    local owner = assert(plan.owners.GroupAuraFlow)
    assert(plan.ownedLaneKeys.Buffs and plan.ownedLaneKeys.Debuffs and owner.flowLane.kind == "buff")
    assert(runtime.NativeApply.ApplyConfig(frame, cfg, "AURA_BAR_TEST"), "native apply failed")
    local nativeOwner = assert(frame.Auras.GroupAuraFlow)
    local groups, axis = nativeOwner.auraSmokeGroups, env.AnchorUtil.FlowLayoutAxis
    assert(groups.msuf_buff.filter:find("HELPFUL", 1, true) and groups.msuf_debuff.filter:find("HARMFUL", 1, true))
    assert(groups.msuf_buff.layout.layoutIndex == 1 and groups.msuf_debuff.layout.layoutIndex == 2)
    assert(groups.msuf_buff.max == cfg.lanes.buff.max and groups.msuf_debuff.max == cfg.lanes.debuff.max)
    local vertical = direction == "UP" or direction == "DOWN"
    assert(nativeOwner.auraSmokeAxis == (vertical and axis.Vertical or axis.Horizontal) and nativeOwner.auraSmokeLimit == nil)
    local sign = vertical and nativeOwner.auraSmokeY or nativeOwner.auraSmokeX
    assert(sign == ((direction == "UP" or direction == "RIGHT") and 1 or -1))
    assert(frame.Auras.Buffs == nil and frame.Auras.Debuffs == nil, "duplicate native aura consumers")
    assert(runtime.NativeApply.ApplyConfig(frame, cfg, "AURA_BAR_TEST") and frame.Auras.GroupAuraFlow == nativeOwner)
    return nativeOwner
end

local function AssertJoinedDrag(both)
    local snap = core.EditModeController.Snap
    local isSnapEnabled = snap.IsEnabled
    snap.IsEnabled = function() return false end
    local _, _, _, initialX, initialY = both:GetPoint(1)
    local debuffX, debuffY = target.debuffOffsetX, target.debuffOffsetY
    cursorX, cursorY, mouseHeld = 300, 400, true
    MenuWorld.FireScript(both, "OnDragStart")
    assert(both._dragging, "combined mover did not start dragging")
    local ticker = core.EditModeDragDriver.GetFrame()
    local function Move(dx, dy, elapsed)
        cursorX, cursorY = 300 + dx, 400 + dy
        MenuWorld.FireScript(ticker, "OnUpdate", elapsed)
        local _, _, _, x, y = both:GetPoint(1)
        assert(x == initialX + dx and y == initialY + dy,
            ("combined mover jumped outside the cursor delta: expected %.1f/%.1f, got %.1f/%.1f")
                :format(initialX + dx, initialY + dy, x, y))
        assert(both:IsShown() and not auras.EditMode.groups.target.debuff:IsShown(), "a second mover appeared during the drag")
    end
    Move(13, 7, 0.016)
    Move(24, 11, 0.016)
    Move(30, 14, 0.060)
    mouseHeld = false
    MenuWorld.FireScript(both, "OnDragStop")
    local _, _, _, finalX, finalY = both:GetPoint(1)
    assert(not both._dragging and finalX == initialX + 30 and finalY == initialY + 14, "combined mover snapped on drop")
    assert(target.debuffOffsetX == debuffX and target.debuffOffsetY == debuffY, "combined mover rewrote the separate debuff offsets")
    snap.IsEnabled = isSnapEnabled
end

local function AssertGrowthAndJoining()
    editState.active = true
    core.ExportPublic("MSUF_UnitPreviewActive", true)
    model.WriteLaneAuraBars("target", "buff", true)
    model.WriteLaneAuraBars("target", "debuff", true)
    model.WriteLaneAuraBarFill("target", "buff", "DOWN")
    model.WriteLaneAuraBarStyle("target", "debuff", Appearance("RIGHT"))
    target.buffAnchor = "CENTER"
    local nativeFrame = env.CreateFrame("Frame", nil, host)
    nativeFrame.MSUFUnitKey = "target"
    local owner
    for _, direction in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
        model.WriteLaneAuraBarStyle("target", "buff", { growth = direction, combineDebuffs = true, iconPlacement = "OUTSIDE_LEFT" })
        auras.BumpRuntimeConfig()
        local cfg = auras.ResolveUnitFrameConfig("target")
        local buff, debuff = core.AuraConfig.CombinedAuraBarLanes(cfg.lanes)
        assert(buff and debuff and buff.auraBarFill == "DOWN", "growth changed fill or joining")
        local vertical = direction == "UP" or direction == "DOWN"
        local advance = (vertical and (buff.buttonHeight + buff.spacing) or (buff.buttonWidth + buff.spacing))
            * ((direction == "UP" or direction == "RIGHT") and 1 or -1)
        local visuals = scene:Refresh()._msufGFFrameAuraPreviews
        local firstDebuff = visuals[3]
        assert(visuals[1]._sceneAuraKind == "buff" and firstDebuff._sceneAuraKind == "debuff")
        AssertRelativeBarPositions(visuals[1], visuals[2], firstDebuff, direction, advance, advance * 2)
        auras.RefreshEditPreview("target")
        local both = auras.EditMode.groups.target.buff
        assert(both:IsShown() and not auras.EditMode.groups.target.debuff:IsShown())
        local edit = both._icons
        AssertRelativeBarPositions(edit[1], edit[2], edit[4], direction, advance, advance * 3)
        assert(edit[4]._msufA3AuraBarSample.name:GetText() == auras.MockAuraPainter.AuraBarSampleName("debuff"))
        owner = AssertJoinedNative(cfg, nativeFrame, direction)
        if direction == "UP" or direction == "RIGHT" then AssertJoinedDrag(both) end
    end

    -- Editing a filter on the second group reuses its native owner and leaves Buffs intact.
    local cfg = auras.ResolveUnitFrameConfig("target")
    cfg.lanes.debuff.nativeFilter = "HARMFUL|PLAYER"
    local ownerPlan = auras.Runtime.OwnerConfig.GetNativeOwnerPlan(cfg)
    assert(auras.Runtime.NativeApply.ApplyGroupSlots(nativeFrame.Auras, ownerPlan.owners.GroupAuraFlow, nativeFrame) == owner)
    assert(owner.auraSmokeGroups.msuf_debuff.filter == "HARMFUL|PLAYER")
    assert(owner.auraSmokeGroups.msuf_buff.filter == cfg.lanes.buff.nativeFilter)

    local saved = model.ReadLaneAuraBarStyle("target", "buff")
    model.WriteLaneAuraBarStyle("target", "buff", core.AuraConfig.CopyAuraBarStyle(saved, "combineDebuffs", false))
    auras.BumpRuntimeConfig()
    local separate = auras.ResolveUnitFrameConfig("target")
    assert(separate.lanes.buff.xSign == 1 and separate.lanes.buff.verticalGrowth == false)
    assert(auras.Runtime.NativeApply.ApplyConfig(nativeFrame, separate, "AURA_BAR_TEST"))
    assert(nativeFrame.Auras.GroupAuraFlow == nil and owner.auraSmokeEnabled == false and not owner:IsShown())
    auras.RefreshEditPreview("target")
    assert(auras.EditMode.groups.target.debuff:IsShown(), "the separate Debuff mover did not return")
    model.WriteLaneAuraBarStyle("target", "buff", saved)
    auras.BumpRuntimeConfig()
    assert(AssertJoinedNative(auras.ResolveUnitFrameConfig("target"), nativeFrame, "RIGHT") == owner, "joined owner did not survive a toggle")
end

AssertGrowthAndJoining()

party.auras.buff.auraBarStyle = { growth = "LEFT", combineDebuffs = true, iconPlacement = "OUTSIDE_LEFT" }
groupFrames.InvalidateCompiledSpecs("party")
auras.BumpRuntimeConfig()
group:Hide()
group:Show(1, { immediate = true })
local partyCell = group:Frames()[1]
local partyConfig = auras.ResolveAuraPreviewConfig(partyCell, partyCell.MSUFUnitKey or "player")
local lead, tail = core.AuraConfig.CombinedAuraBarLanes(partyConfig.lanes)
assert(lead and tail, "Party omitted combined bars")
local partyVisuals = partyCell._msufGFFrameAuraPreviews
local advance = -(lead.buttonWidth + lead.spacing)
AssertRelativeBarPositions(partyVisuals[1], partyVisuals[2], partyVisuals[3], "LEFT", advance, advance * 2)
assert(partyVisuals[3]._sceneAuraLayoutHost == partyVisuals[1]._sceneAuraLayoutHost)
local left, right = groupFrames.PreviewAuraBarBounds(partyConfig.lanes, 100, 40, 2, true, true)
assert(right - left == -advance * 2 + 2 * tail.buttonWidth + tail.spacing, "Fit omitted bar length or boundary gap")
tail.groupAccessGate = true
assert(not core.AuraConfig.CombinedAuraBarLanes(partyConfig.lanes), "joined AuraGroups with different visibility policies")
tail.groupAccessGate = nil

local function AuraBarCommand(page, prefix, suffix, prepareKind, prepareValue)
    local id = prefix .. suffix
    local _, found, exact = menu.Search._CoreAPI.OpenSearchTarget(page, "Aura bars", nil, nil, nil, {
        controlId = id, sectionId = page == "uf_target" and "auras" or "group_auras",
        prepareKind = prepareKind, prepareValue = prepareValue,
    })
    local record = menu.RuntimeControlCatalog.Get(id)
    assert(found and exact and record, "missing aura bar control: " .. id)
    local widget = record.widget
    assert(widget._msuf2ControlSchema.write, "aura bar write policy missing: " .. id)
    return assert(widget._msuf2CommandAction)
end

local function UnitControl(path)
    return AuraBarCommand("uf_target", "menu2.uf_target.auras.unit-workspace.lane.buff.", path, "unitAuraWorkspace", "buff_bars")
end

local function GroupControl(path)
    return AuraBarCommand("gf_auras", "menu2.gf_auras.auras.group-workspace.lane.buff.", path, "groupAuraWorkspace", "party_buff_bars")
end

local showUnitBars = UnitControl("layout.show-as-bars")
showUnitBars.set(false)
assert(not model.ReadLaneAuraBars("target", "buff"))
showUnitBars.set(true)
assert(model.ReadLaneAuraBars("target", "buff"))
UnitControl("layout.aura-bar-fill").set("RIGHT")
assert(model.ReadLaneAuraBarFill("target", "buff") == "RIGHT")
UnitControl("bars.fill-color-mode").set("CUSTOM")
UnitControl("bars.fill-color").set(0.15, 0.35, 0.65)
local unitStyle = model.ReadLaneAuraBarStyle("target", "buff")
assert(unitStyle and unitStyle.fillColorMode == "CUSTOM")
assert(unitStyle.fillColor[1] == 0.15 and unitStyle.fillColor[2] == 0.35 and unitStyle.fillColor[3] == 0.65)

GroupControl("layout.show-as-bars").set(true)
GroupControl("layout.aura-bar-fill").set("LEFT")
GroupControl("bars.fill-color-mode").set("CUSTOM")
GroupControl("bars.fill-color").set(0.25, 0.45, 0.75)
local savedBuff = menu.EnsureDB().gf_party.auras.buff
assert(savedBuff.showAuraBars and savedBuff.auraBarFill == "LEFT")
assert(savedBuff.auraBarStyle.fillColorMode == "CUSTOM")
assert(savedBuff.auraBarStyle.fillColor[1] == 0.25 and savedBuff.auraBarStyle.fillColor[2] == 0.45 and savedBuff.auraBarStyle.fillColor[3] == 0.75)

print("aura_bar_presentation_smoke " .. flavor .. ": fill, growth, colors, joined native groups and both preview layouts")
