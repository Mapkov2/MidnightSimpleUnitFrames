-- Exercise the live Edit Mode registry and offset drag path for Class Resources
-- and a detached Player Power Bar without a WoW client.
local root = assert(arg[1], "repo root missing")
local function Widget(left, bottom, width, height, parent)
    local frame = { left = left, bottom = bottom, width = width, height = height, parent = parent, shown = true }
    function frame:GetLeft() return self.left end
    function frame:GetRight() return self.left + self.width end
    function frame:GetBottom() return self.bottom end
    function frame:GetTop() return self.bottom + self.height end
    function frame:GetWidth() return self.width end
    function frame:GetHeight() return self.height end
    function frame:GetCenter() return self.left + self.width / 2, self.bottom + self.height / 2 end
    function frame:GetEffectiveScale() return 1 end
    function frame:GetParent() return self.parent end
    function frame:GetPoint() return unpack(self.point) end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:IsShown() return self.shown end
    return frame
end

UIParent = Widget(0, 0, 1920, 1080)
GetCursorPosition = function() return 150, 108 end
InCombatLockdown = function() return false end
MSUF_GetGeneralDB = function() return nil end
local player = Widget(100, 100, 250, 40, UIParent)
player._msufOwnedAnchorRoot = true
local combo = Widget(100, 140, 250, 8, player)
combo._msufOwnedAnchorRoot = true
combo:SetPoint("TOPLEFT", player, "TOPLEFT", 3, 5)
MSUF_ClassPowerContainer = combo
local energy = Widget(100, 125, 250, 6, player)
energy._msufDetached = true
energy:SetPoint("TOP", combo, "BOTTOM", 0, -4)
player.targetPowerBar = energy
MSUF_DB = {
    bars = { classPowerOffsetX = 3, classPowerOffsetY = 5 },
    player = { powerBarDetached = true, detachedPowerBarAnchorToClassPower = true,
        detachedPowerBarOffsetX = 0, detachedPowerBarOffsetY = -4 },
}

local registry = {}
MSUF_EM2 = {
    Registry = { Register = function(cfg) registry[cfg.key] = cfg end,
        Get = function(key) return registry[key] end },
    Util = {
        Round = function(value) return math.floor(value + 0.5) end,
        IsConfigCombatLocked = function() return false end,
        BlockConfigCombatLocked = function() return InCombatLockdown() end,
        RefreshUFPreview = function() end,
        ApplySettingsForKeySafe = function(unit)
            if unit == "player" then
                energy.width = MSUF_DB.player.detachedPowerBarWidth or energy.width
                energy.height = MSUF_DB.player.detachedPowerBarHeight or energy.height
                energy:SetPoint("TOP", MSUF_DB.player.detachedPowerBarAnchorToClassPower and combo or player,
                    "BOTTOM", MSUF_DB.player.detachedPowerBarOffsetX, MSUF_DB.player.detachedPowerBarOffsetY)
            end
            return true
        end,
        FrameRectToUI = function(frame)
            if not frame then return nil end
            return frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        end,
    },
}
local namespace = {
    ExportPublic = function(name, value) _G[name] = value end,
    UF = { GetFrame = function(key) if key == "player" then return player end end },
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Movers.lua"))("MSUF", namespace)
local classCfg, powerCfg = assert(registry.classpower), assert(registry.power_player)
assert(classCfg.getFrame() == combo and powerCfg.getFrame() == energy,
    "visible Class Resources and detached Player Power must have separate movers")
assert(classCfg.historyCategory == "classpower" and powerCfg.historyCategory == "power",
    "resource movers must preserve separate undo state")
assert(classCfg.canNudge == true and powerCfg.canNudge == true,
    "resource movers must accept Edit Mode arrow-key movement")
MSUF_DB.player.powerBarDetached = false
assert(powerCfg.getFrame() == nil, "embedded Player Power must not expose a detached mover")
MSUF_DB.player.powerBarDetached = true
combo.shown = false
combo._msufAnchorOnly = true
MSUF_UnitEditModeActive = true
assert(classCfg.getFrame() == combo, "inactive Class Resources lost their Edit Mode mover")
energy.shown = false
assert(powerCfg.getFrame() == energy, "linked detached Power lost its independent mover")
energy.shown = true
combo._msufAnchorOnly = nil
combo.shown = true

MSUF_ClassPowerContainer = nil
local ensureCalls = 0
MSUF_ClassPower_EnsureEditModeAnchor = function()
    ensureCalls = ensureCalls + 1
    combo._msufAnchorOnly = true
    combo.shown = false
    MSUF_ClassPowerContainer = combo
    return true
end
assert(classCfg.getFrame() == combo and ensureCalls == 1,
    "first Edit Mode entry did not lazily create an inactive resource anchor")
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_Layout.lua"))("MSUF", namespace)
MSUF_InstallEditLayoutUI("MSUF", namespace)
local ticker = assert(MSUF_EM2.Ticker)
energy.shown = false
local inactivePowerMover = Widget(100, 125, 250, 16, UIParent)
local inactivePowerDrag = assert(ticker.BeginExternalDrag(inactivePowerMover, "power_player", powerCfg,
    { bar = powerCfg.getFrame() }))
inactivePowerMover.left = inactivePowerMover.left + 2
assert(ticker.ApplyExternalDrag(inactivePowerDrag) == true
    and MSUF_DB.player.detachedPowerBarOffsetX == 2,
    "inactive detached Power could not be dragged")
ticker.EndExternalDrag(inactivePowerDrag, false)
MSUF_DB.player.detachedPowerBarOffsetX = 0
energy:SetPoint("TOP", combo, "BOTTOM", 0, -4)
energy.shown = true
local inactiveMover = Widget(100, 140, 250, 16, UIParent)
local inactiveDrag = assert(ticker.BeginExternalDrag(inactiveMover, "classpower", classCfg, { bar = combo }))
inactiveMover.left = inactiveMover.left + 3
assert(ticker.ApplyExternalDrag(inactiveDrag) == true
    and MSUF_DB.bars.classPowerOffsetX == 6,
    "inactive Class Resources could not be dragged")
ticker.EndExternalDrag(inactiveDrag, false)
MSUF_DB.bars.classPowerOffsetX = 3
combo:SetPoint("TOPLEFT", player, "TOPLEFT", 3, 5)
combo.shown = true
combo._msufAnchorOnly = nil
MSUF_UnitEditModeActive = false
assert(classCfg.getFrame() == combo, "live Class Resources were lost after Edit Mode")

local mover = Widget(100, 140, 250, 16, UIParent)
local drag = assert(ticker.BeginExternalDrag(mover, "classpower", classCfg, { bar = combo }))
mover.left, mover.bottom = mover.left + 20, mover.bottom + 10
assert(ticker.ApplyExternalDrag(drag) == true, "Class Resource drag was not applied")
assert(MSUF_DB.bars.classPowerOffsetX == 23 and MSUF_DB.bars.classPowerOffsetY == 15,
    "Class Resource drag did not update its own offsets")
assert(combo.point[4] == 23 and combo.point[5] == 15,
    "Class Resource visual did not follow its saved offsets")
assert(energy.point[2] == combo and energy.point[4] == 0 and energy.point[5] == -4,
    "bound Energy must keep following Combo Points without rewriting its own offsets")
ticker.EndExternalDrag(drag, false)

local powerMover = Widget(100, 125, 250, 16, UIParent)
local powerDrag = assert(ticker.BeginExternalDrag(powerMover, "power_player", powerCfg, { bar = energy }))
powerMover.left, powerMover.bottom = powerMover.left + 7, powerMover.bottom - 6
assert(ticker.ApplyExternalDrag(powerDrag) == true, "detached Power drag was not applied")
assert(MSUF_DB.player.detachedPowerBarOffsetX == 7 and MSUF_DB.player.detachedPowerBarOffsetY == -10,
    "detached Power drag did not update only its own offsets")
assert(MSUF_DB.bars.classPowerOffsetX == 23 and MSUF_DB.bars.classPowerOffsetY == 15,
    "detached Power drag moved Class Resources")
assert(energy.point[2] == combo, "detached Power drag broke its Class Resource anchor")
ticker.EndExternalDrag(powerDrag, false)

local lockedMover = Widget(100, 125, 250, 16, UIParent)
local lockedDrag = assert(ticker.BeginExternalDrag(lockedMover, "power_player", powerCfg, { bar = energy }))
lockedMover.left = lockedMover.left + 20
InCombatLockdown = function() return true end
assert(ticker.ApplyExternalDrag(lockedDrag) == false
    and MSUF_DB.player.detachedPowerBarOffsetX == 7,
    "combat-edge drag mutated protected Power geometry or saved offsets")
ticker.EndExternalDrag(lockedDrag, false)
InCombatLockdown = function() return false end

local function Box()
    local box = { text = "" }
    function box:GetText() return self.text end
    function box:SetText(value) self.text = tostring(value) end
    return box
end
MSUF_EM2.Util.SyncMovers = function() end
MSUF_EM2.Util.RefreshUFPreview = function() end
MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function() return true end
MSUF_ClassPower_RefreshLayout = function()
    local bars = MSUF_DB.bars
    combo.width = bars.classPowerWidth or combo.width
    combo.height = bars.classPowerHeight or combo.height
    combo:SetPoint("TOPLEFT", player, "TOPLEFT", bars.classPowerOffsetX, bars.classPowerOffsetY)
    return true
end
MSUF_EM2.PopupFactory = { BlockConfigCombatLocked = function() return false end, Tr = function(value) return value end }
MSUF_EM2.QuickPopup = {
    CreateShell = function(name)
        local frame = { shown = false, callbacks = {}, _titleFS = { SetText = function() end } }
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:IsShown() return self.shown end
        _G[name] = frame
        return frame
    end,
    ValuePairAt = function(owner, _, _, _, _, key1, cb1, _, key2, cb2)
        owner[key1], owner[key2] = Box(), Box()
        owner.callbacks[key1], owner.callbacks[key2] = cb1, cb2
    end,
    ToggleAt = function(_, _, _, _, _, _, cb)
        local toggle = { _checked = false, callback = cb }
        function toggle:SetShown(shown) self.shown = shown end
        function toggle:SetCheckedVisual(checked) self._checked = checked end
        return toggle
    end,
    SetBoxText = function(box, value) box:SetText(value) end,
    AddFooterControls = function() end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Popups.lua"))("MSUF", namespace)
local popups = MSUF_EM2.Popups
assert(popups.Open("classpower") == true, "Class Resource quick popup did not open")
local popup = assert(MSUF_EM2_ResourcePopup)
popup.wBox:SetText("300")
popup.callbacks.wBox()
assert(MSUF_DB.bars.classPowerWidth == 300 and MSUF_DB.bars.classPowerWidthMode == "custom",
    "Class Resource width edit did not switch to manual size")
popup.hBox:SetText("12")
popup.callbacks.hBox()
assert(MSUF_DB.bars.classPowerHeight == 12, "Class Resource height edit was not saved")
popup.yBox:SetText("-35")
popup.callbacks.yBox()
assert(MSUF_DB.bars.classPowerOffsetY == -35 and MSUF_DB.bars.classPowerCooldownTopAnchor == true
    and combo.point[5] == -35, "negative Class Resource Y was not applied")
MSUF_DB.bars.detachedPowerBarWidthMode = "cooldown"
assert(popups.Open("power_player") == true, "detached Power quick popup did not open")
popup.wBox:SetText("220")
popup.callbacks.wBox()
assert(MSUF_DB.player.detachedPowerBarWidth == 220
    and MSUF_DB.player.detachedPowerBarSyncClassPower == false
    and MSUF_DB.bars.detachedPowerBarWidthMode == nil,
    "manual Power width remained coupled to the class or cooldown width")
popup.hBox:SetText("10")
popup.callbacks.hBox()
assert(MSUF_DB.player.detachedPowerBarHeight == 10, "detached Power height edit was not saved")
popup.yBox:SetText("-20")
popup.callbacks.yBox()
assert(MSUF_DB.player.detachedPowerBarOffsetY == -20 and energy.point[5] == -20,
    "negative detached Power Y was not applied")
popup.anchorBtn._checked = false
popup.anchorBtn.callback(false)
assert(MSUF_DB.player.detachedPowerBarAnchorToClassPower == false,
    "separate Power placement was not saved")

local selectedKey
local historyCommits = 0
MSUF_EM2.State = {
    IsActive = function() return true end,
    GetUnitKey = function() return selectedKey end,
    SetUnitKey = function(key) selectedKey = key end,
}
MSUF_EM2.Undo = {
    PrepareChange = function(category, key) return { category = category, key = key } end,
    CommitPrepared = function() historyCommits = historyCommits + 1; return true end,
}
MSUF_EM2.Focus = { NotifyPositionChanged = function() end }
assert(MSUF_EM2.Nudge.Move(0, -1, "classpower") == true
    and MSUF_DB.bars.classPowerOffsetY == -36 and combo.point[5] == -36,
    "Class Resource arrow nudge did not move its own Y offset")
assert(MSUF_DB.player.detachedPowerBarOffsetY == -20,
    "Class Resource arrow nudge changed detached Power")
assert(MSUF_EM2.Nudge.Move(0, 1, "power_player") == true
    and MSUF_DB.player.detachedPowerBarOffsetY == -19 and energy.point[5] == -19,
    "detached Power arrow nudge did not move its own Y offset")
assert(MSUF_EM2.Nudge.Move(1, 0, "power_player") == true
    and MSUF_DB.player.detachedPowerBarOffsetX == 8 and energy.point[4] == 8,
    "detached Power arrow nudge did not move its own X offset")
assert(MSUF_DB.bars.classPowerOffsetX == 23 and historyCommits == 3,
    "resource arrow nudges changed Class Resource X or missed undo history")
InCombatLockdown = function() return true end
assert(MSUF_EM2.Nudge.Move(0, 1, "classpower") == false
    and MSUF_DB.bars.classPowerOffsetY == -36 and historyCommits == 3,
    "resource arrow nudge changed position or undo history in combat")
InCombatLockdown = function() return false end
local refreshClass = MSUF_ClassPower_RefreshLayout
MSUF_ClassPower_RefreshLayout = function() return false end
assert(MSUF_EM2.Nudge.Move(0, 1, "classpower") == false
    and MSUF_DB.bars.classPowerOffsetY == -36 and historyCommits == 3,
    "failed resource layout apply was saved or added to undo history")
MSUF_ClassPower_RefreshLayout = refreshClass

-- The menu preview is display-only; the Edit Mode movement assertions above
-- remain authoritative even while this preview is selected.
do
    local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()
    local previewPath = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua"
    local file = assert(io.open(previewPath, "rb"))
    local source = file:read("*a")
    file:close()
    for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
        local world = World.New(root, flavor):Boot()
        local failure = world:FirstFailure()
        assert(not failure, flavor .. ": " .. tostring(failure and failure.message))
        local env, ns = world.env, world.core
        local M = ns.MSUF2
        env.MSUF_EnsureDB(true)
        M.activeKey = "classpower"
        M.GetClassPowerPreviewSpec = function() return M.ClassPowerPreviewSpecs.rogue_combo end
        local chunk = assert(loadstring(source .. "\nreturn { fit = ResolvePreviewFit, apply = ApplyPreviewZoom }", "@preview-fit-test"))
        setfenv(chunk, env)
        local geometry = chunk("MidnightSimpleUnitFrames_Options", ns)
        local parent = env.CreateFrame("Frame", nil, env.UIParent)
        parent:SetSize(800, 400)
        M.Widgets.FixedPreviewSection = function()
            return env.CreateFrame("Frame", nil, parent), env.CreateFrame("Frame", nil, parent)
        end
        M.Widgets.AttachPinnedPreview = nil
        M.Widgets.AttachFixedPreviewExpander = nil
        local ctx = { key = "classpower", width = 800, entry = {}, wrapper = parent }
        assert(M.ClassPowerStackPreview.Create(ctx, { width = 800 }))
        local box = assert(ctx.entry.classPowerPreview)
        box:Refresh()
        assert(box._msufCPPreviewAnim.classFrame and box._msufCPPreviewAnim.classFrame:IsShown(),
            flavor .. ": enabled class resource is missing from the menu preview")
        assert(not box.dragFrame and not box.zoomBar and not box:GetScript("OnKeyDown"),
            flavor .. ": preview still captures movement or manual camera input")
        assert(not box.canvas:GetScript("OnMouseWheel"), "preview wheel still changes the camera")
        assert(not box._msufCPPreviewNudgeTarget, "preview takes over Edit Mode arrow movement")
        local beforeX, beforeY = env.MSUF_DB.bars.classPowerOffsetX, env.MSUF_DB.bars.classPowerOffsetY
        local route
        M.SelectPage = function(key) route = key; return true end
        for _, handle in ipairs(box.handles) do
            assert(not handle:GetScript("OnDragStart") and not handle:GetScript("OnMouseDown")
                and not handle:GetScript("OnKeyDown"), "preview handle can still move saved offsets")
            handle:GetScript("OnClick")(handle, "LeftButton")
            assert(route == "classpower" and env.MSUF_EM2_MenuFocusRequest.sectionId,
                "click no longer opens the exact resource settings")
            box:Refresh()
        end
        for _, active in ipairs({ false, true }) do
            env.MSUF_UnitEditModeActive = active
            local ok, reason = env.MSUF_ClassPowerPreview_NudgeHandle("classPower", 20, -30)
            assert(ok == false and reason == "edit-mode-required", "retired nudge API still writes")
            ok, reason = env.MSUF_ClassPowerPreview_Pan(99999, -99999)
            assert(ok == false and reason == "preview-auto-fit", "retired pan API can lose the resource")
        end
        assert(env.MSUF_DB.bars.classPowerOffsetX == beforeX and env.MSUF_DB.bars.classPowerOffsetY == beforeY,
            "preview interaction changed a saved resource position")

        -- Use explicit local rectangles so the assertion measures containment,
        -- independently of the permissive frame-stub anchor implementation.
        local function Region(x, y, w, h, layer)
            return { _layerKey = layer, _msufPlaced = true,
                IsShown = function() return true end,
                GetCenter = function() return x, y end,
                GetWidth = function() return w end, GetHeight = function() return h end }
        end
        local stage = env.CreateFrame("Frame")
        stage.GetCenter = function() return 0, 0 end
        local reference = Region(-300, 70, 270, 38)
        local resource = Region(2200, -1300, 400, 14)
        local power = Region(2200, -1320, 400, 8)
        local hp = Region(-500, 900, 270, 16)
        local text = Region(3600, -2400, 110, 20, "classText")
        local preview = { stage = stage, canvas = box.canvas, playerRef = reference,
            handles = { text }, layerVisibility = {},
            _manualZoom = 1.5, _zoomPanX = 99999, _zoomPanY = -99999,
            _dragFrozenScale = 2, _dragFrozenBaseOffsetX = 9999 }
        for _, size in ipairs({ { 760, 112 }, { 628, 288 }, { 320, 96 } }) do
            preview.canvasW, preview.canvasH = size[1], size[2]
            geometry.apply(preview, resource, nil, power, hp)
            local scale = preview._mockScale
            assert(scale > 0 and scale <= 1, "invalid fitted scale")
            for _, region in ipairs({ reference, resource, power, hp, text }) do
                local x, y = region:GetCenter()
                x = x * scale + preview._mockBaseOffsetX
                y = y * scale + preview._mockBaseOffsetY
                assert(math.abs(x) + region:GetWidth() * scale / 2 <= size[1] / 2,
                    flavor .. ": preview clips a visible resource/text horizontally")
                assert(math.abs(y) + region:GetHeight() * scale / 2 <= size[2] / 2,
                    flavor .. ": preview clips a visible resource/text vertically")
            end
        end
        local scaleWithText = preview._mockScale
        preview.layerVisibility.classText = false
        geometry.apply(preview, resource, nil, power, hp)
        assert(preview._mockScale > scaleWithText, "hidden text still shrinks the resource preview")
    end
end
print("classic_resource_editmode_smoke: OK (Edit Mode movement, display-only menu, auto-fit bars/text on five clients)")
