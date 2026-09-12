-- Auras3 runtime: NativeContract.
-- Native capability validation and MSUF root reuse checks. Native delegates are called directly; MSUF never reaches into restricted AuraButtons.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.NativeContract = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local tostring = tostring
local type = type
local COLD_APPLY_REASONS = dependencies.Schema.COLD_APPLY_REASONS
local CreateFrame = dependencies.Platform.CreateFrame
local FrameAuraConfig = dependencies.GroupConfig.FrameAuraConfig
local IDENTITY_AURA_REFRESH_REASONS = dependencies.Schema.IDENTITY_AURA_REFRESH_REASONS
local RefreshAppliedNativeRoot

local NATIVE_AURA_CONTAINER_METHODS = {
    -- Keep the required surface at Retail 12.1. Later client additions are
    -- capability-checked where used so this beta remains loadable on 12.1.
    "SetUnit",
    "SetEnabled",
    "AddAuraGroup",
    "SetAuraGroupFilterString",
    "SetAuraGroupLayout",
    "SetAuraGroupMaxFrameCount",
    "SetAuraGroupCandidateFilters",
    "SetAuraGroupSortMethod",
    "AddAuraSlot",
    "SetAuraSlotFilterString",
    "SetAuraSlotCandidateFilters",
    "SetAuraSlotSortMethod",
    "AddItemEnchantment",
    -- PTR 7 flow layout API (replaced SetAuraLayout{AnchorPoint,GrowthDirection,RowWidth}).
    "SetFlowLayoutAnchorPoint",
    "SetFlowLayoutGrowthDirection",
    "SetFlowLayoutMaximumLineSize",
}

local NATIVE_AURA_BUTTON_METHODS = {
    -- These are the Retail 12.1 requirements. Caster-name and native Pandemic
    -- animation methods arrive later and remain optional at their call sites.
    "SetIcon",
    "ClearIcon",
    "SetDurationCooldown",
    "ClearDurationCooldown",
    "SetDurationBar",
    "ClearDurationBar",
    "SetDurationText",
    "ClearDurationText",
    "SetApplicationCount",
    "ClearApplicationCount",
    -- PTR 7 names; the SetAuraBorder/SetAuraSymbol aliases are deprecated and
    -- flagged for removal after 12.1.
    "AddDispelTypeTexture",
    "ClearDispelTypeTextures",
    "SetDispelTypeText",
    "ClearDispelTypeText",
    "SetMouseClickEnabled",
    "SetMouseMotionEnabled",
    "SetCancelAuraButtons",
}

local function ValidateNativeAuraContainerContract(container)
    if not container then return false end
    for i = 1, #NATIVE_AURA_CONTAINER_METHODS do
        local methodName = NATIVE_AURA_CONTAINER_METHODS[i]
        if type(container[methodName]) ~= "function" then
            A3.nativeAuraRuntimeAvailable = false
            A3._RecordNativeAuraRuntimeError("native AuraContainer missing " .. methodName)
            return false
        end
    end
    return true
end

local function ValidateNativeAuraButtonContract(button)
    if not button then
        A3.nativeAuraRuntimeAvailable = false
        A3.nativeAuraRuntimeError = "native AuraButton missing"
        error(A3.nativeAuraRuntimeError, 3)
    end
    for i = 1, #NATIVE_AURA_BUTTON_METHODS do
        local methodName = NATIVE_AURA_BUTTON_METHODS[i]
        if type(button[methodName]) ~= "function" then
            A3.nativeAuraRuntimeAvailable = false
            A3.nativeAuraRuntimeError = "native AuraButton missing " .. methodName
            error(A3.nativeAuraRuntimeError, 3)
        end
    end
    return true
end

local function ConfigureNativeAuraContainer(container, unit)
    container:SetUnit(unit)
    -- 12.1.5's CustomAuraContainerTemplate ships editModePreviewEnabled = true,
    -- so a container swaps to Blizzard's preview aura source while the player is
    -- in Edit Mode and draws its own icons underneath the MSUF-owned previews.
    -- MSUF owns that surface end to end; opt out once at creation.
    if type(container.SetEditModePreviewEnabled) == "function" then
        container:SetEditModePreviewEnabled(false)
    end
    container:SetEnabled(true)
end

local function EnsureRoot(frame)
    if not frame then return nil end
    local root = frame.Auras
    if root and root._msufA3NativeRoot == true then return root end
    root = CreateFrame("Frame", nil, frame._msufHealthVisualRoot or frame)
    local roundLayout = _G.MSUF_SetRoundLayoutToNearestPixel
    if type(roundLayout) == "function" then roundLayout(root, true) end
    root._msufA3ParentFrame = frame
    root._msufA3NativeRoot = true
    root:SetAllPoints(frame)
    root:SetScript("OnShow", function(self)
        -- Child AuraContainers already run UpdateAllAuras from their secure
        -- OnShow; avoid a second forced full parse here.
        if RefreshAppliedNativeRoot then RefreshAppliedNativeRoot(self, false) end
        -- Hidden secure-header children register their native owners only now.
        -- Seed after registration so a newly visible group frame cannot spend
        -- one frame fail-open while waiting for an unrelated identity event.
        if type(A3._SeedGroupAuraAssistGate) == "function" then
            A3._SeedGroupAuraAssistGate(self._msufA3ParentFrame or self:GetParent(), self.unit)
        end
        if type(A3._SeedGroupAuraPresenceGate) == "function" then
            A3._SeedGroupAuraPresenceGate(self._msufA3ParentFrame or self:GetParent(), self.unit)
        end
    end)
    root:Hide()
    frame.Auras = root
    return root
end

local function ConfigGen(cfg)
    return cfg and cfg._msufA3ConfigGen or (A3._runtimeConfigGen or 1)
end

local function VisualGen(cfg)
    return cfg and cfg._msufA3VisualGen or (A3._nativeVisualGen or 0)
end

local function ReasonRequiresAuraApply(reason)
    if reason == nil then return true end
    if IDENTITY_AURA_REFRESH_REASONS[reason] == true then return true end
    if COLD_APPLY_REASONS[reason] == true then return true end
    reason = tostring(reason or "")
    return reason:find("^AURAS3_", 1, false) ~= nil
        or reason:find("^MSUF2_", 1, false) ~= nil
        or reason:find("^MSUF_ASSISTANT_", 1, false) ~= nil
end

local function RootAppliedConfigIsCurrent(root, frame, cfg, reason)
    if not (root and root._msufA3NativeRoot == true and root._msufA3Applied == true) then return false end
    if root.needFullUpdate == true then return false end
    if ReasonRequiresAuraApply(reason) and not (reason == nil and cfg and root._msufA3Config == cfg) then return false end
    if cfg and root._msufA3Config ~= cfg then return false end
    if root._msufA3ConfigGen ~= (cfg and ConfigGen(cfg) or (A3._runtimeConfigGen or 1)) then return false end
    if root._msufA3VisualGen ~= (cfg and VisualGen(cfg) or (A3._nativeVisualGen or 0)) then return false end
    if root._msufA3AppliedUnit ~= (cfg and cfg.unit or (frame and frame.MSUFUnitKey)) then return false end
    if root._msufA3FrameSpec ~= (frame and frame.MSUFSpec) then return false end
    return true
end

local function FrameAppliedConfigIsCurrent(frame, reason, cfg)
    if not frame then return false end
    if cfg == nil then cfg = FrameAuraConfig(frame, frame.MSUFUnitKey) end
    return RootAppliedConfigIsCurrent(frame.Auras, frame, cfg, reason)
end

return {
    ConfigGen = ConfigGen,
    ConfigureNativeAuraContainer = ConfigureNativeAuraContainer,
    EnsureRoot = EnsureRoot,
    FrameAppliedConfigIsCurrent = FrameAppliedConfigIsCurrent,
    ReasonRequiresAuraApply = ReasonRequiresAuraApply,
    RootAppliedConfigIsCurrent = RootAppliedConfigIsCurrent,
    ValidateNativeAuraButtonContract = ValidateNativeAuraButtonContract,
    ValidateNativeAuraContainerContract = ValidateNativeAuraContainerContract,
    VisualGen = VisualGen,
    -- Bootstrap-only cycle resolution; no lookup or forwarding wrapper is added to events.
    Bind = function(dependencies)
        RefreshAppliedNativeRoot = dependencies.RefreshAppliedNativeRoot
    end,
}
end
