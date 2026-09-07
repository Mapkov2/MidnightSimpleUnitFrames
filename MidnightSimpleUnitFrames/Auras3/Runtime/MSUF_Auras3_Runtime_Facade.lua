-- Auras3 runtime: Facade.
-- Stable public Auras3 API and UF element integration. This is the sole runtime entry surface; Blizzard retains UNIT_AURA ownership.
-- The factory runs once at addon load; dependency bindings are local upvalues on live paths.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
MSUF.Auras3RuntimeFactories = MSUF.Auras3RuntimeFactories or {}
MSUF.Auras3RuntimeFactories.Facade = function(addonName, MSUF, A3, UF, ExportPublic, dependencies)
local pairs = pairs
local tostring = tostring
local type = type
local ApplyAuraTooltipStyle = dependencies.Platform.ApplyAuraTooltipStyle
local ApplyConfig = dependencies.NativeApply.ApplyConfig
local AuraRuntimeCombatBlocked = dependencies.Platform.AuraRuntimeCombatBlocked
local C_Timer = dependencies.Platform.C_Timer
local CreateClassPowerAuraSensor = dependencies.NativeApply.CreateClassPowerAuraSensor
local CreateFrame = dependencies.Platform.CreateFrame
local DrainDirectIdentityEventTopologyBatch = dependencies.IdentityEvents.DrainDirectIdentityEventTopologyBatch
local EMPTY_EVENTS = dependencies.Platform.EMPTY_EVENTS
local EnsureNativeAuraRefreshDriver = dependencies.NativeApply.EnsureNativeAuraRefreshDriver
local EnsureRoot = dependencies.NativeContract.EnsureRoot
local FrameAppliedConfigIsCurrent = dependencies.NativeContract.FrameAppliedConfigIsCurrent
local FrameAuraConfig = dependencies.GroupConfig.FrameAuraConfig
local HideState = dependencies.NativeApply.HideState
local IDENTITY_AURA_REFRESH_REASONS = dependencies.Schema.IDENTITY_AURA_REFRESH_REASONS
local InCombat = dependencies.Platform.InCombat
local InvalidateUnitRuntimeConfig = dependencies.UnitConfig.InvalidateUnitRuntimeConfig
local IsGroupFrame = dependencies.ConfigValues.IsGroupFrame
local MANAGED_UNITS = dependencies.Schema.MANAGED_UNITS
local NormalizeRuntimeUnit = dependencies.ConfigValues.NormalizeRuntimeUnit
local ReasonRequiresAuraApply = dependencies.NativeContract.ReasonRequiresAuraApply
local ResolveGroupFrameConfig = dependencies.GroupConfig.ResolveGroupFrameConfig
local RootAppliedConfigIsCurrent = dependencies.NativeContract.RootAppliedConfigIsCurrent
local RootCanReuseContainersForConfig = dependencies.NativeApply.RootCanReuseContainersForConfig
local RunNextFrame = dependencies.Platform.RunNextFrame

function A3.SetUnitFrameOwner(unit, frame, owns)
    if not unit then return end
    A3._unitFrameOwners = A3._unitFrameOwners or {}
    if owns and frame then
        A3._unitFrameOwners[unit] = frame
    elseif A3._unitFrameOwners[unit] == frame or frame == nil then
        A3._unitFrameOwners[unit] = nil
    end
end

function A3.EnableFrame(frame)
    if not (frame and frame.MSUFUnitKey and MANAGED_UNITS[frame.MSUFUnitKey]) then return false end
    if EnsureNativeAuraRefreshDriver then EnsureNativeAuraRefreshDriver() end
    local cfg = A3.ResolveUnitFrameConfig(frame.MSUFUnitKey, frame.MSUFSpec)
    if not (cfg and cfg.enabled) then
        HideState(frame)
        A3.SetUnitFrameOwner(frame.MSUFUnitKey, frame, false)
        return false
    end
    A3._runtimeFrames = A3._runtimeFrames or {}
    A3._runtimeFrames[frame.MSUFUnitKey] = frame
    A3.SetUnitFrameOwner(frame.MSUFUnitKey, frame, true)
    return ApplyConfig(frame, cfg)
end

function A3.DisableFrame(frame)
    if not frame then return true end
    HideState(frame)
    A3._HideDispelOverlayPreview(frame)
    local unit = frame.MSUFUnitKey
    if unit and A3._runtimeFrames and A3._runtimeFrames[unit] == frame then
        A3._runtimeFrames[unit] = nil
    end
    if unit then A3.SetUnitFrameOwner(unit, frame, false) end
    frame._msufA3UnitAuraOwner = nil
    return true
end

function A3.RenderFrame(frame, reason)
    if not frame then return false end
    local cfg
    local cfgReady = false

    if IDENTITY_AURA_REFRESH_REASONS[reason] == true then
        -- Group identity stays synchronous so roster builds settle in one pass,
        -- but never forces filter reconstruction: keep geometry/registration
        -- current and let the container's UNIT_AURA own aura content.
        if not cfgReady then cfg = FrameAuraConfig(frame, frame.MSUFUnitKey) end
        cfgReady = true
        if not (cfg and cfg.enabled == true) then
            HideState(frame)
            return false
        end
        if RootAppliedConfigIsCurrent(frame.Auras, frame, cfg, nil)
            and A3._RefreshAppliedNativeAuras(frame, false) then
            return true
        end
        if AuraRuntimeCombatBlocked() then return false end
    end
    if not cfgReady then cfg = FrameAuraConfig(frame, frame.MSUFUnitKey) end
    if FrameAppliedConfigIsCurrent(frame, reason, cfg) then
        A3._RefreshAppliedNativeAuras(frame, false)
        return true
    end
    return ApplyConfig(frame, cfg, reason)
end

A3.RenderUnitChangedFrame = function(frame, oldUnit, newUnit)
    if not frame then return false end
    if type(newUnit) == "string" and newUnit ~= "" then
        frame.MSUFUnitKey = newUnit
        frame.unitKey = newUnit
    end
    local cfg = FrameAuraConfig(frame, frame.MSUFUnitKey)
    if not (cfg and cfg.enabled == true) then
        HideState(frame)
        return false
    end
    local root = frame.Auras
    -- PTR 7: recreate is combat-legal; only the unloaded-addon case still bails.
    if AuraRuntimeCombatBlocked() and not RootCanReuseContainersForConfig(root, cfg) then
        return false
    end
    return ApplyConfig(frame, cfg, "MSUF_UNIT_CHANGED_AURAS")
end

A3.OnFrameUnitChanged = A3.RenderUnitChangedFrame

A3.ForceUpdateFrame = A3.RenderFrame
A3.RenderCachedFrame = A3.RenderFrame

function A3.RuntimeOwnsUnit(unit)
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._runtimeFrames and A3._runtimeFrames[unit] ~= nil or false
end

function A3._EnsureDeferredAuraRuntimeDriver()
    if A3._deferredAuraRuntimeFrame then return A3._deferredAuraRuntimeFrame end
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" or InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if type(A3._FlushDeferredAuraRuntime) == "function" then A3._FlushDeferredAuraRuntime() end
    end)
    A3._deferredAuraRuntimeFrame = frame
    return frame
end

function A3._QueueDeferredAuraRuntime(scope, reason, visuals)
    scope = tostring(scope or "shared"):lower()
    reason = reason or A3._deferredAuraRuntimeReason or "AURAS3_DEFERRED"
    A3._deferredAuraRuntime = true
    A3._deferredAuraRuntimeReason = reason
    if visuals == true then A3._deferredAuraRuntimeVisuals = true end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
    elseif A3._deferredAuraRuntimeAll ~= true then
        A3._deferredAuraRuntimeScopes = A3._deferredAuraRuntimeScopes or {}
        A3._deferredAuraRuntimeScopes[scope] = true
    end
    local frame = A3._EnsureDeferredAuraRuntimeDriver()
    if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
    return false
end

function A3._AuraPreviewGroupKind(scope)
    local key = tostring(scope or ""):lower()
    if key == "party" or key == "gf_party" or key:match("^party%d+$") then return "party", true end
    if key == "raid" or key == "gf_raid" or key:match("^raid%d+$") then return "raid", true end
    if key == "mythicraid" or key == "gf_mythicraid" then return "mythicraid", true end
    if key == "" or key == "shared" or key == "global" or key == "all" or key == "*"
        or key == "group" or key == "groups" then
        return nil, true
    end
    return nil, false
end

function A3._NotifyAuraColdpathPreview(reason, scope)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_PREVIEW") end
    local did = false
    reason = reason or "AURAS3_PREVIEW"
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh(reason)
        did = true
    end
    local gf = A3._GroupAPI and A3._GroupAPI() or nil
    local kind, touchesGroup = A3._AuraPreviewGroupKind(scope)
    if touchesGroup and gf and type(gf.RefreshPreviewLayout) == "function" then
        gf.RefreshPreviewLayout(kind)
        did = true
    elseif touchesGroup and type(_G.MSUF_GF_RefreshPreviewLayout) == "function" then
        _G.MSUF_GF_RefreshPreviewLayout()
        did = true
    end
    return did
end

local function RuntimeFrame(runtimeUnit)
    return (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit])
        or (UF.GetFrame and UF.GetFrame(runtimeUnit))
        or (UF.frames and UF.frames[runtimeUnit])
        or _G["MSUF_" .. runtimeUnit]
end

A3._ApplyRuntimeUnit = function(runtimeUnit)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(runtimeUnit, "AURAS3_RUNTIME_UNIT") end
    local frame = RuntimeFrame(runtimeUnit)
    if not frame then return false end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.EnableFrame(frame)
    end
    return true
end

function A3._GroupAPI()
    local ns = MSUF or _G.MSUF_NS or _G.MSUF
    return ns and ns.GF or nil
end

function A3._ApplyGroupAuraFrame(frame, unit, kind)
    if not (frame and type(unit) == "string" and unit ~= "") then return false end
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_GROUP_FRAME") end
    if EnsureNativeAuraRefreshDriver then EnsureNativeAuraRefreshDriver() end
    frame._msufIsGroupFrame = true
    if kind then frame._msufGFKind = kind end
    if UF.ApplyElementToFrame then
        UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    else
        A3.RenderFrame(frame)
    end
    return true
end

function A3._RequestGroupKindNow(kind)
    local gf = A3._GroupAPI()
    if not gf then return false end
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(kind or "group", "AURAS3_GROUP_KIND") end
    if type(gf.RefreshVisuals) == "function" then
        return gf.RefreshVisuals(kind, gf.DIRTY_AURAS) == true
    end
    local didWork = false
    if type(gf.ForEachFrame) == "function" then
        didWork = gf.ForEachFrame(function(frame, frameUnit, frameKind)
            if kind == nil or frameKind == kind then
                return A3._ApplyGroupAuraFrame(frame, frameUnit, frameKind)
            end
            return false
        end, true) == true
    end
    if not didWork and type(gf.RefreshVisuals) == "function" then
        gf.RefreshVisuals(kind, gf.DIRTY_AURAS)
        return true
    end
    return didWork
end

local function ApplyRequestedGroupUnitFrame(frame, unit, gf)
    if type(gf.MarkDirty) == "function" then
        return gf.MarkDirty(frame, gf.DIRTY_AURAS) == true
    end
    return A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) == true
end

function A3._RequestGroupUnitNow(unit)
    local gf = A3._GroupAPI()
    if not (gf and type(unit) == "string" and unit ~= "") then return false end
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_GROUP_UNIT") end
    if type(gf.ForEachFrameForUnit) == "function" then
        return gf.ForEachFrameForUnit(unit, ApplyRequestedGroupUnitFrame, gf)
    end
    local frame = type(gf.FrameForUnit) == "function" and gf.FrameForUnit(unit) or nil
    if frame and type(gf.MarkDirty) == "function" then
        return gf.MarkDirty(frame, gf.DIRTY_AURAS) == true
    end
    return frame and A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) or false
end

A3._RequestUnitNow = function(unit)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        local didWork = A3._ApplyRuntimeUnit("player")
        didWork = A3._ApplyRuntimeUnit("target") or didWork
        didWork = A3._ApplyRuntimeUnit("focus") or didWork
        for i = 1, 5 do didWork = A3._ApplyRuntimeUnit("boss" .. i) or didWork end
        for i = 1, 3 do didWork = A3._ApplyRuntimeUnit("arena" .. i) or didWork end
        didWork = A3._RequestGroupKindNow(nil) or didWork
        return didWork
    end
    if unit == "boss" then
        local didWork = false
        for i = 1, 5 do didWork = A3._ApplyRuntimeUnit("boss" .. i) or didWork end
        return didWork
    end
    if unit == "arena" then
        local didWork = false
        for i = 1, 3 do didWork = A3._ApplyRuntimeUnit("arena" .. i) or didWork end
        return didWork
    end
    if unit == "group" or unit == "groups" then return A3._RequestGroupKindNow(nil) end
    if unit == "party" or unit == "gf_party" then return A3._RequestGroupKindNow("party") end
    if unit == "raid" or unit == "gf_raid" then
        local didWork = A3._RequestGroupKindNow("raid")
        return A3._RequestGroupKindNow("mythicraid") or didWork
    end
    if unit == "mythicraid" or unit == "gf_mythicraid" then return A3._RequestGroupKindNow("mythicraid") end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then return A3._RequestGroupUnitNow(unit) end
    unit = NormalizeRuntimeUnit(unit)
    return unit and A3._ApplyRuntimeUnit(unit) or false
end

function A3.RequestUnit(unit)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_REQUEST_UNIT") end
    return A3._RequestUnitNow(unit)
end

A3._DoRefreshAll = function()
    ApplyAuraTooltipStyle()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    -- One full refresh can rebuild every Unit and Group Aura owner. Keep the
    -- shared identity-event topology batched across that complete cold pass;
    -- the inner UF/GF batches then remain cheap nested scopes and the shard
    -- registrations are reconciled exactly once at the outer boundary.
    A3._BeginDirectIdentityEventTopologyBatch()
    A3._RequestUnitNow("*")
    A3._EndDirectIdentityEventTopologyBatch()
    return true
end

A3._FlushCoalescedRefreshAll = function()
    -- A hard Lua-budget abort skips the normal batch epilogue. These scopes
    -- are synchronous by contract, so any depth surviving to the next frame is
    -- stale and must be drained before a merged retry rebuilds the topology.
    DrainDirectIdentityEventTopologyBatch()
    local pending = A3._refreshAllPending == true or A3._refreshAllIncomplete == true
    A3._refreshAllPending = nil
    A3._refreshAllIncomplete = nil
    A3._refreshAllCoalescing = nil
    if pending then
        return A3.RefreshAll()
    end
    return true
end

function A3._FlushDeferredAuraRuntime()
    if InCombat() or A3._deferredAuraRuntime ~= true then return false end
    local all = A3._deferredAuraRuntimeAll == true
    local scopes = A3._deferredAuraRuntimeScopes
    local visuals = A3._deferredAuraRuntimeVisuals == true
    local reason = A3._deferredAuraRuntimeReason or "AURAS3_DEFERRED"
    A3._deferredAuraRuntime = nil
    A3._deferredAuraRuntimeAll = nil
    A3._deferredAuraRuntimeScopes = nil
    A3._deferredAuraRuntimeVisuals = nil
    A3._deferredAuraRuntimeReason = nil
    if visuals then A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1 end
    local previewScope = all and "shared" or nil
    if all or not scopes then
        A3.RefreshAll()
    else
        for scope in pairs(scopes) do
            if previewScope == nil then previewScope = scope end
            local _, touchesGroup = A3._AuraPreviewGroupKind(scope)
            if touchesGroup then previewScope = scope end
            A3.RefreshUnit(scope)
        end
    end
    A3._NotifyAuraColdpathPreview(reason, previewScope)
    return true
end

function A3.RefreshAll()
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime("shared", "AURAS3_REFRESH_ALL") end
    if A3._refreshAllCoalescing == true then
        A3._refreshAllPending = true
        return true
    end
    A3._refreshAllCoalescing = true
    -- Arm the unlock before entering the expensive synchronous pass. If WoW
    -- aborts that pass with "script ran too long", the next-frame callback can
    -- still clear the latch (and service a merged retry) instead of leaving all
    -- later Aura refreshes permanently stuck as pending.
    if RunNextFrame then
        RunNextFrame(A3._FlushCoalescedRefreshAll)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, A3._FlushCoalescedRefreshAll)
    end
    A3._refreshAllIncomplete = true
    A3._DoRefreshAll()
    A3._refreshAllIncomplete = nil
    if not RunNextFrame and not (C_Timer and C_Timer.After) then
        A3._refreshAllCoalescing = nil
    end
    return true
end

-- Rounded masks and border rings on native Dispel regions are immutable after
-- Blizzard accepts them. A rounded setting change therefore advances the
-- existing visual generation and recreates the affected native containers on
-- this cold configuration path; aura events never call this function.
function A3.RefreshRoundedDispelOverlayMasks()
    if AuraRuntimeCombatBlocked() then
        return A3._QueueDeferredAuraRuntime("shared", "AURAS3_ROUNDED_DISPEL_MASKS", true)
    end
    A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1
    return A3.RefreshAll()
end

A3._requestApplyScopeKeys = A3._requestApplyScopeKeys or {
    player = true, target = true, focus = true, boss = true, arena = true,
    party = true, raid = true, mythicraid = true,
    gf_party = true, gf_raid = true, gf_mythicraid = true,
    group = true, groups = true,
    shared = true, global = true, all = true, ["*"] = true,
}

A3._LooksLikeApplyScope = function(value)
    value = tostring(value or ""):lower()
    if value == "" then return false end
    if A3._requestApplyScopeKeys[value] then return true end
    return value:match("^boss%d+$") ~= nil
        or value:match("^arena%d+$") ~= nil
        or value:match("^party%d+$") ~= nil
        or value:match("^raid%d+$") ~= nil
end

function A3.RequestApply(scopeOrReason, reason)
    if A3._LooksLikeApplyScope(scopeOrReason) then
        return A3.RequestScope(scopeOrReason, reason or "AURAS3_REQUEST_APPLY")
    end
    return A3.RefreshAll()
end

function A3.RequestScope(scope, reason)
    scope = tostring(scope or "shared"):lower()
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(scope, reason or "AURAS3_SCOPE_APPLY") end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        return A3.RefreshAll()
    end
    local result = A3.RefreshUnit(scope)
    A3._NotifyAuraColdpathPreview(reason or "AURAS3_SCOPE_APPLY", scope)
    return result
end

function A3.RefreshUnit(unit)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(unit, "AURAS3_REFRESH_UNIT") end
    if unit == "boss" then
        for i = 1, 5 do InvalidateUnitRuntimeConfig("boss" .. i) end
        return A3.RequestUnit("boss")
    end
    if unit == "arena" then
        for i = 1, 3 do InvalidateUnitRuntimeConfig("arena" .. i) end
        return A3.RequestUnit("arena")
    end
    local runtimeUnit = InvalidateUnitRuntimeConfig(unit)
    if runtimeUnit then return A3.RequestUnit(runtimeUnit) end
    if A3.InvalidateGroupRuntimeConfig(unit) then return A3.RequestUnit(unit) end
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    return A3.RequestUnit(unit)
end

function A3.ApplyFontsFromGlobal(scope, reason)
    if AuraRuntimeCombatBlocked() then return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_FONT_VISUALS", true) end
    A3._nativeVisualGen = (A3._nativeVisualGen or 0) + 1
    if scope ~= nil then
        return A3.RequestScope(scope, reason or "AURAS3_FONT_VISUALS")
    end
    -- FontRuntime has already refreshed the UnitFrame and GroupFrame text
    -- elements before reaching this global follower. A second RefreshAll here
    -- routes every group frame through GF.RefreshVisuals -> UF.ApplySpec even
    -- though only the aura fonts changed. Refresh the existing aura owners.
    local visualReason = reason or "AURAS3_FONT_VISUALS"
    local didWork = false
    local function RefreshRuntimeUnit(runtimeUnit)
        local frame = RuntimeFrame(runtimeUnit)
        if frame then didWork = A3.RenderFrame(frame, visualReason) == true or didWork end
    end

    RefreshRuntimeUnit("player")
    RefreshRuntimeUnit("target")
    RefreshRuntimeUnit("focus")
    for i = 1, 5 do RefreshRuntimeUnit("boss" .. i) end
    for i = 1, 3 do RefreshRuntimeUnit("arena" .. i) end

    local gf = A3._GroupAPI()
    if gf and type(gf.ForEachFrame) == "function" then
        didWork = gf.ForEachFrame(function(frame)
            return A3.RenderFrame(frame, visualReason) == true
        end, true) == true or didWork
    end
    A3._NotifyAuraColdpathPreview(visualReason, "shared")
    if type(A3.RefreshEditPreview) == "function" then
        didWork = A3.RefreshEditPreview() == true or didWork
    end
    return didWork
end

--- Narrow ClassPower bridge for secret player auras. AuraContainer retains
--- ownership of UNIT_AURA parsing and binds protected values directly to its
--- regions; callers only configure the frame once.
A3.CreateClassPowerAuraSensor = CreateClassPowerAuraSensor

-- AuraContainer owns UNIT_AURA and per-aura churn. Do not add an MSUF UNIT_AURA
-- scanner here; target/focus identity refresh is handled by the coalesced
-- container refresh path above.
local AurasElement = {
    events = EMPTY_EVENTS,
    unitlessEvents = EMPTY_EVENTS,
}

function AurasElement.GetEvents()
    return EMPTY_EVENTS
end

function AurasElement.SelectEventUpdate()
    return nil
end

function AurasElement.IsEnabled(frame)
    if IsGroupFrame(frame) and frame._msufGFIsPreviewFrame == true then
        return false
    end
    local cfg = FrameAuraConfig(frame, frame and frame.MSUFUnitKey)
    return cfg and cfg.enabled == true or false
end

function AurasElement.Create(frame)
    EnsureRoot(frame)
end

function AurasElement.Apply(frame)
    return frame ~= nil
end

function AurasElement.Enable(frame)
    if IsGroupFrame(frame) then
        -- Edit Mode uses pooled addon-owned stand-ins compiled from the same
        -- lane geometry. Never attach a native player AuraContainer to a
        -- synthetic row: it would show the player's current auras instead of
        -- deterministic dummy data and allocate AuraButtons in batches.
        if frame._msufGFIsPreviewFrame == true then
            frame._msufA3GroupRuntime = nil
            HideState(frame)
            return false
        end
        frame._msufA3GroupRuntime = true
        local cfg = ResolveGroupFrameConfig(frame, frame and frame.MSUFUnitKey)
        if not (cfg and cfg.enabled) then
            HideState(frame)
            return false
        end
        return ApplyConfig(frame, cfg)
    end
    return A3.EnableFrame(frame)
end

function AurasElement.Disable(frame)
    return A3.DisableFrame(frame)
end

function AurasElement.Update(frame, event)
    if event ~= nil and not ReasonRequiresAuraApply(event) then
        local root = frame and frame.Auras
        if root and root._msufA3NativeRoot == true and root._msufA3Applied == true then
            A3._RefreshAppliedNativeAuras(frame, false)
            return true
        end
        return false
    end
    return A3.RenderFrame(frame, event)
end

UF.RegisterElement("Auras", AurasElement)

A3.frontendOnly = false
A3.backendEnabled = true
A3.unitFrameAuras = true
A3.nativeAuraBackend = true
A3.RefreshRuntime = A3.RefreshAll
MSUF.AuraBackendEnabled = true
MSUF.AuraCore = MSUF.AuraCore or _G.MSUF_AuraCore or {}
MSUF.AuraCore.Auras3 = A3

return {
}
end
