--- Game/Classic/Auras/MSUF_Auras3_Requests.lua
--- The apply service of the Classic aura backend: scoped and full refresh
--- requests from the menu, the profile layer and the font follower, their
--- deferral while combat blocks the work and the combat-end flush, group
--- frame re-applies, and the menu preview notify. Every entry point is a cold
--- path; UNIT_AURA never reaches this file.
---
--- Game/<Flavor>/Auras.xml loads the unit-frame aura backend after Compile.lua
--- in this order: Buttons, Filters, FrameVisuals, Lanes, UnitFrames, Requests.
--- Each file imports the earlier ones from A3._ClassicBackend at load time.
if not (select(2, ...) and select(2, ...).Client and select(2, ...).Client.IsClassic) then return end
local _, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}
local A3 = MSUF.MSUF_Auras3
local Backend = type(A3) == "table" and A3._ClassicBackend
assert(Backend and Backend.Element, "Classic aura requests require Game/Classic/Auras/MSUF_Auras3_UnitFrames.lua")
if Backend.Requests then return end
local Compile = A3._ClassicCompile
local Requests = {}

local UF = MSUF.UF
local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local math_max = math.max
local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer

local MANAGED_UNITS = Compile.MANAGED_UNITS
local NormalizeRuntimeUnit = Compile.NormalizeRuntimeUnit
local WipeTable = Compile.WipeTable
local CombatBlocked = Compile.AuraRuntimeCombatBlocked

function A3._EnsureDeferredAuraRuntimeDriver()
    if A3._deferredAuraRuntimeFrame then return A3._deferredAuraRuntimeFrame end
    local frame = CreateFrame("Frame")
    local function FlushAfterCombatLatch() A3._FlushDeferredAuraRuntime() end
    frame:SetScript("OnEvent", function(self, event)
        if event ~= "PLAYER_REGEN_ENABLED" then return end
        if CombatBlocked() then
            -- The lockdown has ended, so only the MSUF_InCombat latch blocks.
            -- The group runtime clears it in its own PLAYER_REGEN_ENABLED
            -- handler, which can run after this one: flush on the next frame.
            -- A flush that combat blocks again keeps its queue and this event.
            if C_Timer and C_Timer.After then C_Timer.After(0, FlushAfterCombatLatch) end
            return
        end
        -- The flush unregisters this event only after its queue is consumed,
        -- so an error while applying one scope keeps the retry armed.
        A3._FlushDeferredAuraRuntime()
    end)
    A3._deferredAuraRuntimeFrame = frame
    return frame
end

-- The queue (A3._QueueDeferredAuraRuntime), the scope test and the preview
-- group kind are shared with Retail in Auras3/MSUF_Auras3_Core.lua.
A3._deferredAuraDefaultReason = "AURAS3_CLASSIC_DEFERRED"

function A3._NotifyAuraColdpathPreview(reason, scope)
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_CLASSIC_PREVIEW")
    end
    local didWork = false
    -- The unit preview belongs to the Options addon, which loads on demand.
    local refreshUnitPreview = MSUF.Optional("MSUF_UFPreview_RequestRefresh")
    if refreshUnitPreview then
        refreshUnitPreview(reason or "AURAS3_CLASSIC_PREVIEW")
        didWork = true
    end
    local kind, touchesGroup = A3._AuraPreviewGroupKind(scope)
    if touchesGroup then
        MSUF.GF.RefreshPreviewLayout(kind)
        didWork = true
    end
    return didWork
end

local function ApplyRuntimeUnit(runtimeUnit)
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(runtimeUnit, "AURAS3_CLASSIC_RUNTIME_UNIT")
    end
    -- The frame that owns the unit's auras, else the unit frame itself. The
    -- unit-frame factory registers every frame in UF.frames together with its
    -- MSUF_<unit> global and _G.MSUF_UnitFrames, the same table
    -- (RegisterGlobals in UnitFrames/Engine/MSUF_UF_Factory.lua).
    local frame = (A3._runtimeFrames and A3._runtimeFrames[runtimeUnit]) or UF.frames[runtimeUnit]
    if not frame then return false end
    UF.ApplyElementToFrame(frame, "Auras", frame.MSUFSpec, nil)
    return true
end

function A3._ApplyGroupAuraFrame(frame, unit, kind)
    if not (frame and type(unit) == "string" and unit ~= "") then return false end
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_GROUP_FRAME")
    end
    frame._msufIsGroupFrame = true
    if kind then frame._msufGFKind = kind end
    local spec = frame.MSUFSpec
    if kind then spec = MSUF.GF.CompileSpec(kind, frame, unit) end
    UF.ApplyElementToFrame(frame, "Auras", spec, nil)
    return true
end

--- The group frame modules (MSUF.GF) load after this file; every request
--- arrives after they did.
function A3._RequestGroupKindNow(kind)
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(kind or "group", "AURAS3_CLASSIC_GROUP_KIND")
    end
    local gf = MSUF.GF
    local didWork = gf.ForEachFrame(function(frame, frameUnit, frameKind)
        if kind == nil or frameKind == kind then
            return A3._ApplyGroupAuraFrame(frame, frameUnit, frameKind)
        end
        return false
    end, true) == true
    if not didWork then
        gf.RefreshVisuals(kind, gf.DIRTY_AURAS)
        return true
    end
    return didWork
end

function A3._RequestGroupUnitNow(unit)
    if not (type(unit) == "string" and unit ~= "") then return false end
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_GROUP_UNIT")
    end
    local frame = MSUF.GF.FrameForUnit(unit)
    return frame and A3._ApplyGroupAuraFrame(frame, unit, frame._msufGFKind) or false
end

local function RequestUnitNow(unit)
    unit = tostring(unit or "")
    if unit == "" or unit == "*" then
        local didWork = ApplyRuntimeUnit("player")
        didWork = ApplyRuntimeUnit("pet") or didWork
        didWork = ApplyRuntimeUnit("target") or didWork
        didWork = ApplyRuntimeUnit("focus") or didWork
        for i = 1, 5 do
            didWork = ApplyRuntimeUnit("boss" .. i) or didWork
        end
        for i = 1, math_max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3) do
            didWork = ApplyRuntimeUnit("arena" .. i) or didWork
        end
        didWork = A3._RequestGroupKindNow(nil) or didWork
        return didWork
    end
    if unit == "boss" then
        local didWork = false
        for i = 1, 5 do
            didWork = ApplyRuntimeUnit("boss" .. i) or didWork
        end
        return didWork
    end
    if unit == "arena" then
        local didWork = false
        for i = 1, math_max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3) do
            didWork = ApplyRuntimeUnit("arena" .. i) or didWork
        end
        return didWork
    end
    if unit == "group" or unit == "groups" then
        return A3._RequestGroupKindNow(nil)
    end
    if unit == "party" or unit == "gf_party" then
        return A3._RequestGroupKindNow("party")
    end
    if unit == "raid" or unit == "gf_raid" then
        local didWork = A3._RequestGroupKindNow("raid")
        return A3._RequestGroupKindNow("mythicraid") or didWork
    end
    if unit == "mythicraid" or unit == "gf_mythicraid" then
        return A3._RequestGroupKindNow("mythicraid")
    end
    if unit:match("^party%d+$") or unit:match("^raid%d+$") then
        return A3._RequestGroupUnitNow(unit)
    end
    unit = NormalizeRuntimeUnit(unit)
    return unit and ApplyRuntimeUnit(unit) or false
end

function A3.RequestUnit(unit, delay)
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_REQUEST_UNIT")
    end
    delay = tonumber(delay) or 0
    if delay > 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, function() A3.RequestUnit(unit, 0) end)
        return true
    end
    return RequestUnitNow(unit)
end

local function RefreshAllNow()
    A3.BumpRuntimeConfig()
    A3._runtimeConfigCache = nil
    Compile.ResetFrameSpecConfigCache()
    RequestUnitNow("*")
    return true
end

function A3.RefreshAll()
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime("shared", "AURAS3_CLASSIC_REFRESH_ALL")
    end
    if A3._deferredAuraRuntime == true then
        -- Out of combat a queue survives only a flush that stopped on an error.
        -- A full refresh covers every queued scope, so widen that queue and let
        -- the flush run it once and consume it.
        A3._deferredAuraRuntimeAll = true
        A3._deferredAuraRuntimeScopes = nil
        return A3._FlushDeferredAuraRuntime()
    end
    return RefreshAllNow()
end

--- The shared Auras3 core installs a no-runtime RequestScope stub before the
--- client backend loads.  Classic must replace it just like Mainline does;
--- otherwise Menu2 changes only invalidate configuration and never reach the
--- scan lanes until a reload or unrelated identity event.
function A3.RequestScope(scope, reason)
    scope = tostring(scope or "shared"):lower()
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope, reason or "AURAS3_CLASSIC_SCOPE_APPLY")
    end
    if scope == "" or scope == "shared" or scope == "global" or scope == "all" or scope == "*" then
        return A3.RefreshAll()
    end
    local result = A3.RefreshUnit(scope)
    A3._NotifyAuraColdpathPreview(reason or "AURAS3_CLASSIC_SCOPE_APPLY", scope)
    return result
end

function A3.RequestApply(scopeOrReason, reason)
    if A3._LooksLikeApplyScope(scopeOrReason) then
        local result = A3.RequestScope(scopeOrReason, reason or "AURAS3_CLASSIC_REQUEST_APPLY")
        -- Retry a queue left by a flush that stopped on an error. The requested
        -- scope is applied first, so a still-failing queued scope cannot block
        -- it. RefreshAll below consumes a stale queue itself.
        if A3._deferredAuraRuntime == true and not CombatBlocked() then
            A3._FlushDeferredAuraRuntime()
        end
        return result
    end
    return A3.RefreshAll()
end

--- A scoped refresh recompiles only its own frames, as on Retail
--- (Runtime_Facade): a unit scope drops that unit's cached configs before
--- RequestUnit re-applies it, and a group scope's re-apply recompiles its
--- frames. Only an unknown scope still invalidates every frame.
function A3.RefreshUnit(unit)
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(unit, "AURAS3_CLASSIC_REFRESH_UNIT")
    end
    local key = tostring(unit or ""):lower()
    if key == "boss" then
        for i = 1, 5 do A3.InvalidateUnitRuntimeConfig("boss" .. i) end
    elseif key == "arena" then
        for i = 1, math_max(3, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3) do
            A3.InvalidateUnitRuntimeConfig("arena" .. i)
        end
    elseif MANAGED_UNITS[key] then
        A3.InvalidateUnitRuntimeConfig(key)
    elseif not (A3._AuraPreviewGroupKind(key) ~= nil or key == "group" or key == "groups") then
        -- A shared or unknown scope still invalidates every frame.
        A3.BumpRuntimeConfig()
        A3._runtimeConfigCache = nil
        Compile.ResetFrameSpecConfigCache()
    end
    return A3.RequestUnit(unit, 0)
end

--- The global font follower. FontRuntime calls it after a global font change
--- and the profile layer after a switch, reset, import or Profile Variant, so
--- without a scope it is a real refresh of every aura owner, group frames
--- included: each recompiles from the active profile and re-lays out its
--- buttons (Retail bumps its visual generation and re-renders the same set).
--- The aura Edit Mode wraps A3.RefreshAll and refreshes its preview from there.
function A3.ApplyFontsFromGlobal(scope, reason)
    if CombatBlocked() then
        return A3._QueueDeferredAuraRuntime(scope or "shared", reason or "AURAS3_CLASSIC_FONT_VISUALS", true)
    end
    if scope ~= nil then return A3.RequestScope(scope, reason or "AURAS3_CLASSIC_FONT_VISUALS") end
    local didWork = A3.RefreshAll() == true
    A3._NotifyAuraColdpathPreview(reason or "AURAS3_CLASSIC_FONT_VISUALS", "shared")
    return didWork
end

--- Applies the queue collected while combat blocked aura runtime work. The
--- queue is consumed only as work completes: a scope entry is removed after its
--- RefreshUnit returns, and the flags and PLAYER_REGEN_ENABLED registration are
--- cleared only after every scope succeeded. A Lua error while applying one
--- scope therefore leaves that scope and the not-yet-run ones queued, and the
--- next combat end, RefreshAll or scoped RequestApply retries them. Returns
--- false without consuming anything if combat blocks the work, including when
--- combat begins mid-flush.
function A3._FlushDeferredAuraRuntime()
    if CombatBlocked() then return false end
    local driver = A3._deferredAuraRuntimeFrame
    if A3._deferredAuraRuntime ~= true then
        if driver then driver:UnregisterEvent("PLAYER_REGEN_ENABLED") end
        return false
    end
    local all = A3._deferredAuraRuntimeAll == true
    local scopes = A3._deferredAuraRuntimeScopes
    local reason = A3._deferredAuraRuntimeReason or "AURAS3_CLASSIC_DEFERRED"
    local previewScope = all and "shared" or nil
    if all or not scopes then
        RefreshAllNow()
        if CombatBlocked() then return false end
    else
        -- Snapshot the keys: RefreshUnit may requeue a scope, and pairs must
        -- not see the live table change while it walks it.
        local keys = WipeTable(A3._deferredAuraFlushKeys)
        A3._deferredAuraFlushKeys = keys
        local count = 0
        for scope in pairs(scopes) do
            count = count + 1
            keys[count] = scope
        end
        for i = 1, count do
            local scope = keys[i]
            if scope == nil then break end
            previewScope = previewScope or scope
            A3.RefreshUnit(scope)
            if CombatBlocked() then return false end
            local live = A3._deferredAuraRuntimeScopes
            if live then live[scope] = nil end
        end
    end
    A3._deferredAuraRuntime = nil
    A3._deferredAuraRuntimeAll = nil
    A3._deferredAuraRuntimeScopes = nil
    A3._deferredAuraRuntimeVisuals = nil
    A3._deferredAuraRuntimeReason = nil
    if driver then driver:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    A3._NotifyAuraColdpathPreview(reason, previewScope)
    return true
end

--- Drops one unit's cached configs (the menu apply service and scoped
--- refreshes call it before re-applying that unit). Every other unit keeps its
--- compiled config, so its next UNIT_AURA neither recompiles nor rescans.
function A3.InvalidateUnitRuntimeConfig(unit)
    local runtimeUnit = unit ~= nil and NormalizeRuntimeUnit(unit) or nil
    if runtimeUnit then
        if A3._runtimeConfigCache then A3._runtimeConfigCache[runtimeUnit] = nil end
        Compile.InvalidateFrameSpecConfig(runtimeUnit)
    end
    return runtimeUnit
end

Backend.Requests = Requests
