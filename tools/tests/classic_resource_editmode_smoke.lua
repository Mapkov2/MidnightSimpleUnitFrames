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
MSUF_DB.player.powerBarDetached = false
assert(powerCfg.getFrame() == nil, "embedded Player Power must not expose a detached mover")
MSUF_DB.player.powerBarDetached = true
combo.shown = false
assert(classCfg.getFrame() == nil, "hidden Class Resources must not expose a mover")
combo.shown = true

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Shell/UI/EditMode/MSUF_EditMode_Layout.lua"))("MSUF", namespace)
MSUF_InstallEditLayoutUI("MSUF", namespace)
local ticker = assert(MSUF_EM2.Ticker)
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
MSUF_EM2.Util.ApplySettingsForKeySafe = function(unit)
    if unit == "player" then
        energy.width = MSUF_DB.player.detachedPowerBarWidth or energy.width
        energy.height = MSUF_DB.player.detachedPowerBarHeight or energy.height
    end
    return true
end
MSUF_EM2.Util.SyncMovers = function() end
MSUF_EM2.Util.RefreshUFPreview = function() end
MSUF_ApplyPowerBarEmbedLayout_ForUnitKey = function() return true end
MSUF_ClassPower_RefreshLayout = function()
    local bars = MSUF_DB.bars
    combo.width = bars.classPowerWidth or combo.width
    combo.height = bars.classPowerHeight or combo.height
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
popup.anchorBtn._checked = false
popup.anchorBtn.callback(false)
assert(MSUF_DB.player.detachedPowerBarAnchorToClassPower == false,
    "separate Power placement was not saved")

print("classic_resource_editmode_smoke: OK (bound and independent drags, width, height, anchor)")
