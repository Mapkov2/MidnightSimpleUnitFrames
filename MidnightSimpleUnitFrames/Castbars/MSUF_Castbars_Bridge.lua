--- MSUF_Castbars_Bridge.lua
--- Core castbar bridge for MSUF Castbars (+ BossCastbars + FocusKickIcon).
--- The runtime now loads from MidnightSimpleUnitFrames.toc; this file keeps the
--- old public API and feature gates without touching the former castbar sub-addon.
--- - Provide MSUF_Castbars_OnSettingsChanged() for menus/options to call after toggles.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF
MSUF.UF = MSUF.UF or {}

local function _EnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB()
    end
end

--- PERF: Cache general ref - invalidated only when MSUF_DB itself changes.
local _cachedGeneral, _cachedGeneralDB
local function _GetGeneral()
    local db = MSUF_DB
    if not db then _EnsureDB(); db = MSUF_DB end
    if _cachedGeneralDB == db and _cachedGeneral then return _cachedGeneral end
    _cachedGeneralDB = db
    _cachedGeneral = (db and db.general) or {}
    return _cachedGeneral
end

local function _GetUF()
    local root = MSUF or _G.MSUF_NS
    return root and root.UF or nil
end

local function _CastbarConfigKey(unit)
    if type(unit) == "string" and unit:match("^boss%d*$") then
        unit = "boss"
    end
    if unit == "player" then
        return "enablePlayerCastbar"
    elseif unit == "target" then
        return "enableTargetCastbar"
    elseif unit == "focus" then
        return "enableFocusCastbar"
    elseif unit == "boss" then
        return "enableBossCastbar"
    end
    return nil
end

local function _CastbarBackend(unit)
    if type(unit) == "string" and unit:match("^boss%d*$") then
        unit = "boss"
    end
    local fn = _G.MSUF_GetCastbarBackend
    if type(fn) == "function" then
        return fn(unit)
    end
    local key = _CastbarConfigKey(unit)
    if not key then
        return nil
    end
    return (_GetGeneral()[key] == false) and ((unit == "player") and "BLIZZARD" or "HIDE") or "MSUF"
end

local function _ShouldUseMSUFCastbar(unit)
    local fnGlobal = _G.MSUF_ShouldUseMSUFCastbar
    if type(fnGlobal) == "function" then
        return fnGlobal(unit) == true
    end
    local uf = _GetUF()
    local fn = uf and uf.ShouldUseMSUFCastbar
    if type(fn) == "function" then
        return fn(unit) == true
    end
    return _CastbarBackend(unit) == "MSUF"
end

local function _ShouldUseBlizzardCastbar(unit)
    if unit ~= "player" then
        return false
    end
    local fnGlobal = _G.MSUF_ShouldUseBlizzardCastbar
    if type(fnGlobal) == "function" then
        return fnGlobal(unit) == true
    end
    local uf = _GetUF()
    local fn = uf and uf.ShouldUseBlizzardCastbar
    if type(fn) == "function" then
        return fn(unit) == true
    end
    return _CastbarBackend(unit) == "BLIZZARD"
end

local function _ShouldHideCastbar(unit)
    local fnGlobal = _G.MSUF_ShouldHideCastbar
    if type(fnGlobal) == "function" then
        return fnGlobal(unit) == true
    end
    local uf = _GetUF()
    local fn = uf and uf.ShouldHideCastbar
    if type(fn) == "function" then
        return fn(unit) == true
    end
    return _CastbarBackend(unit) == "HIDE"
end

local function _SetBlizzardCastbarOwner(owner)
    local uf = _GetUF()
    if uf then
        uf.blizzardCastbarOwner = owner
    end
end

local function _ClaimBlizzardCastbarOwnership(tag, unit)
    local uf = _GetUF()
    local fn = uf and uf.ClaimBlizzardCastbarOwnership
    if type(fn) == "function" then
        return fn(tag, unit)
    end
    if not uf then
        return false
    end
    if tag == nil then
        tag = "MSUF_Unknown"
    end
    if not _ShouldUseMSUFCastbar(unit or "player") then
        uf.blizzardCastbarOwner = _ShouldUseBlizzardCastbar(unit or "player") and "Blizzard" or "Hidden"
        return false
    end
    local cur = uf.blizzardCastbarOwner
    if cur and cur ~= tag then
        return false
    end
    uf.blizzardCastbarOwner = tag
    return true
end

--- Shared castbar next-frame deferral.
--- Scope intentionally stays narrow: only true next-frame castbar/runtime deferrals
--- that are already equivalent to C_Timer.After(0, fn).
local _CastbarsRunNextFrame = _G.MSUF_Castbars_RunNextFrame
if type(_CastbarsRunNextFrame) ~= "function" then
    _CastbarsRunNextFrame = function(fn)
        if type(fn) ~= "function" then return end
        local timer = _G.C_Timer
        if timer and timer.After then
            timer.After(0, fn)
        else
            fn()
        end
    end
    _G.MSUF_Castbars_RunNextFrame = _CastbarsRunNextFrame
end

--- Suppress Blizzard player castbars only while MSUF owns the player castbar.
--- When the backend is Blizzard, the same frames must keep their own event scripts intact.
if type(_G.MSUF_SuppressBlizzardPlayerCastbars) ~= "function" then
    --- Shared helpers (avoid per-call closures/allocations).
    local function _MSUF_HideNow(self)
        if self and self.MSUF_PlayerCastbarAllowShown then return end
        if self and self.Hide then
            self:Hide()
        end
    end

    local function _MSUF_HideIfShown(self, shown)
        if shown then
            _MSUF_HideNow(self)
        end
    end

    local function _MSUF_SetPlayerBlizzardAllowed(allowed)
        local f1 = rawget(_G, "PlayerCastingBarFrame")
        local f2 = rawget(_G, "CastingBarFrame")
        if f1 then
            f1.MSUF_PlayerCastbarAllowShown = allowed and true or false
            f1.showCastbar = allowed and true or false
        end
        if f2 and f2 ~= f1 then
            f2.MSUF_PlayerCastbarAllowShown = allowed and true or false
            f2.showCastbar = allowed and true or false
        end
    end

    local function _MSUF_HardenAndHide(frame)
        if not frame then return end
        frame.MSUF_PlayerCastbarAllowShown = false
        frame.showCastbar = false

        if not frame.MSUF_HideHooked then
            frame.MSUF_HideHooked = true

            --- Fallback hooks (covers code that tries to show it manually).
            hooksecurefunc(frame, "Show", _MSUF_HideNow)
            if frame.SetShown then
                hooksecurefunc(frame, "SetShown", _MSUF_HideIfShown)
            end
            if frame.HookScript then
                frame:HookScript("OnShow", _MSUF_HideNow)
            end
        end

        _MSUF_HideNow(frame)
    end

    function _G.MSUF_SuppressBlizzardPlayerCastbars()
        if _ShouldUseBlizzardCastbar("player") then
            _MSUF_SetPlayerBlizzardAllowed(true)
            _SetBlizzardCastbarOwner("Blizzard")
            return false
        end

        local didAny = false

        local f1 = rawget(_G, "PlayerCastingBarFrame")
        local f2 = rawget(_G, "CastingBarFrame")

        if f1 then
            didAny = true
            _MSUF_HardenAndHide(f1)
        end
        if f2 and f2 ~= f1 then
            didAny = true
            _MSUF_HardenAndHide(f2)
        end

        if didAny then
            _ClaimBlizzardCastbarOwnership("MSUF", "player")
        end

        return didAny
    end

    --- Event-driven: Blizzard_CastingBarFrame may load after MSUF.
    local _msufCbSuppressEvt = CreateFrame("Frame")
    _msufCbSuppressEvt:RegisterEvent("PLAYER_LOGIN")
    _msufCbSuppressEvt:RegisterEvent("PLAYER_ENTERING_WORLD")
    _msufCbSuppressEvt:RegisterEvent("ADDON_LOADED")
    _msufCbSuppressEvt:SetScript("OnEvent", function(_, event, arg1)
        --- Prefer event-driven suppression (Blizzard_CastingBarFrame typically creates PlayerCastingBarFrame).
        if event == "ADDON_LOADED" then
            if arg1 ~= "Blizzard_CastingBarFrame" and arg1 ~= "Blizzard_CastingBar" then return end
        end

        if type(_G.MSUF_SuppressBlizzardPlayerCastbars) == "function" then
            _G.MSUF_SuppressBlizzardPlayerCastbars()
        end
    end)
end

--- Public helper (idempotent): kept for older core/menu call sites.
_G.MSUF_EnsureCastbarsLoaded = _G.MSUF_EnsureCastbarsLoaded or function(_reason)
    return true
end

--- Determine whether any core castbar runtime should be active.
--- IMPORTANT: boss castbars and focus kick share this castbar feature gate.
_G.MSUF_AreAnyCastbarsEnabled = _G.MSUF_AreAnyCastbarsEnabled or function()
    local g = _GetGeneral()

    if _ShouldUseMSUFCastbar("player") then return true end
    if _ShouldUseMSUFCastbar("target") then return true end
    if _ShouldUseMSUFCastbar("focus") then return true end

    --- Boss castbars: only count if boss frames are enabled.
    if _ShouldUseMSUFCastbar("boss") then
        local bossFramesEnabled = true
        if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
            bossFramesEnabled = false
        end
        if bossFramesEnabled then
            return true
        end
    end

    --- Focus kick icon: only count if focus frame is enabled.
    if g.enableFocusKickIcon then
        local focusEnabled = true
        if MSUF_DB and MSUF_DB.focus and MSUF_DB.focus.enabled == false then
            focusEnabled = false
        end
        if focusEnabled then
            return true
        end
    end

    return false
end

--- Minimal helper copies (also provided by MSUF_Castbars.lua later in the TOC).
--- Keeping them here prevents nil-access during early load before full runtime files run.
if not _G.MSUF_IsCastbarEnabledForUnit then
    --- PERF: Cache enabled state per unit/backend - invalidated when MSUF_DB or backend changes.
    local _cbEnabledCache = {}
    local _cbEnabledDBRef = nil
    function _G.MSUF_IsCastbarEnabledForUnit(unit)
        if _cbEnabledDBRef ~= MSUF_DB then
            _cbEnabledDBRef = MSUF_DB
            _cbEnabledCache = {}
        end
        local backend = _CastbarBackend(unit)
        local cached = _cbEnabledCache[unit]
        if cached and cached.backend == backend then return cached.result end
        local result = (backend == nil) and true or (backend == "MSUF")
        _cbEnabledCache[unit] = {
            backend = backend,
            result = result,
        }
        return result
    end
end

if not _G.MSUF_IsCastbarHiddenForUnit then
    function _G.MSUF_IsCastbarHiddenForUnit(unit)
        return _ShouldHideCastbar(unit)
    end
end

if not _G.MSUF_IsBlizzardCastbarEnabledForUnit then
    function _G.MSUF_IsBlizzardCastbarEnabledForUnit(unit)
        return _ShouldUseBlizzardCastbar(unit)
    end
end

if not _G.MSUF_IsCastTimeEnabled then
    function _G.MSUF_IsCastTimeEnabled(frame)
        if not frame or not frame.unit then
            return true
        end
        local g = _GetGeneral()
        local u = frame.unit
        if u == "player" then
            return g.showPlayerCastTime ~= false
        elseif u == "target" then
            return g.showTargetCastTime ~= false
        elseif u == "focus" then
            return g.showFocusCastTime ~= false
        end
        return true
    end
end

--- Force-hide known MSUF castbar frames (best-effort). Useful when the user
--- disables all castbars.
_G.MSUF_Castbars_ForceHideAll = _G.MSUF_Castbars_ForceHideAll or function()
    local function _hide(f)
        if f and f.Hide then
            f:Hide()
        end
    end

    _hide(_G.MSUF_PlayerCastBar)
    _hide(_G.MSUF_TargetCastbar)
    _hide(_G.TargetCastBar)
    _hide(_G.MSUF_FocusCastbar)
    _hide(_G.FocusCastBar)

    --- Boss castbars (best-effort)
    for i = 1, 10 do
        _hide(_G["MSUF_boss" .. i .. "CastBar"])
    end
end

--- Settings change helper (menus/options may call this after toggles change).
_G.MSUF_Castbars_OnSettingsChanged = _G.MSUF_Castbars_OnSettingsChanged or function(_reason)
    local sync = _G.MSUF_SyncCastbarBackendLegacyFlags
    if type(sync) == "function" then
        sync(_GetGeneral())
    end
    if _ShouldUseBlizzardCastbar("player") then
        _SetBlizzardCastbarOwner("Blizzard")
    elseif type(_G.MSUF_SuppressBlizzardPlayerCastbars) == "function" then
        _G.MSUF_SuppressBlizzardPlayerCastbars()
    end
    local applyPlayerState = rawget(_G, "MSUF_PlayerCastbar_ApplyBackendState")
    if type(applyPlayerState) == "function" then
        applyPlayerState()
    end

    local anyEnabled = _G.MSUF_AreAnyCastbarsEnabled()
    local applyDriverState = rawget(_G, "MSUF_CastbarDriver_ApplyBackendState")
    if type(applyDriverState) == "function" then
        applyDriverState("target")
        applyDriverState("focus")
    elseif anyEnabled then
        local ensureUnit = rawget(_G, "MSUF_CastbarDriver_EnsureUnit")
        if type(ensureUnit) == "function" then
            ensureUnit("target")
            ensureUnit("focus")
        end
    end
    local applyBoss = rawget(_G, "MSUF_ApplyBossCastbarsEnabled")
    if type(applyBoss) == "function" then
        applyBoss()
    end
    local fn = rawget(_G, "MSUF_Castbars_ApplyEnabledState")
    if type(fn) == "function" then
        fn()
    end
    if not anyEnabled then
        _G.MSUF_Castbars_ForceHideAll()
    end
end

--- Entry points that core may call during PLAYER_LOGIN.
--- These MUST exist before the full castbar runtime files load later in the TOC.
--- Runtime implementations replace the relevant globals automatically.

local _BossPreviewStub
local function _CastbarPreviewCombatLocked()
    return _G.MSUF_InCombat == true
        or ((_G.InCombatLockdown and _G.InCombatLockdown()) and true or false)
        or ((_G.UnitAffectingCombat and _G.UnitAffectingCombat("player")) and true or false)
end
local function _BossPreviewStubCallReal()
    if _CastbarPreviewCombatLocked() then
        _G.MSUF__BossPreviewStubGuard = false
        return
    end
    local fn = rawget(_G, "MSUF_UpdateBossCastbarPreview")
    if type(fn) == "function" and fn ~= _BossPreviewStub then
        fn()
    end
    _G.MSUF__BossPreviewStubGuard = false
end

local function _ShouldLoadForBoss()
    _EnsureDB()
    if not _ShouldUseMSUFCastbar("boss") then
        return false
    end
    if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
        return false
    end
    return true
end

if type(_G.MSUF_ReanchorTargetCastBar) ~= "function" then
    _BossPreviewStub = function()
        if _CastbarPreviewCombatLocked() then return end
        _EnsureDB()
        local g = _GetGeneral()

        --- If previews are off, there is nothing to do.
        if not g.castbarPlayerPreviewEnabled then return end

        --- If boss castbars are explicitly disabled, don't initialize just to hide a preview
        --- that can't exist yet. If runtime already exists, the real function will handle hiding.
        if not _ShouldUseMSUFCastbar("boss") then
            local fn = rawget(_G, "MSUF_UpdateBossCastbarPreview")
            if type(fn) == "function" and fn ~= _BossPreviewStub then
                return fn()
            end
            return
        end

        if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then return end

        --- Reentrancy guard: during runtime initialization the boss module may call
        --- MSUF_UpdateBossCastbarPreview() before it replaces this stub.
        _G.MSUF__BossPreviewStubGuard = _G.MSUF__BossPreviewStubGuard or false
        if _G.MSUF__BossPreviewStubGuard then return end
        _G.MSUF__BossPreviewStubGuard = true

        --- Defer one frame to guarantee runtime initialization replaced the global.
        _CastbarsRunNextFrame(_BossPreviewStubCallReal)
    end
    _G.MSUF_UpdateBossCastbarPreview = _BossPreviewStub
end

if type(_G.MSUF_SetBossCastbarTestMode) ~= "function" then
    local stub
    stub = function(active, keepSetting)
        if _CastbarPreviewCombatLocked() then return end
        if not _ShouldLoadForBoss() then return end
        local fn = rawget(_G, "MSUF_SetBossCastbarTestMode")
        if type(fn) == "function" and fn ~= stub then
            return fn(active, keepSetting)
        end
    end
    _G.MSUF_SetBossCastbarTestMode = stub
end

--- Focus kick icon lives in the core castbar runtime. Provide an entry point so core can
--- call it safely before the runtime file has loaded.
if type(_G.MSUF_InitFocusKickIcon) ~= "function" then
    local stub
    stub = function()
        _EnsureDB()
        local g = _GetGeneral()
        if g.enableFocusKickIcon ~= true then return end
        if MSUF_DB and MSUF_DB.focus and MSUF_DB.focus.enabled == false then return end
        local fn = rawget(_G, "MSUF_InitFocusKickIcon")
        if type(fn) == "function" and fn ~= stub then
            return fn()
        end
    end
    _G.MSUF_InitFocusKickIcon = stub
end

--- Channeled cast tick markers (5 lines)
--- The core castbar runtime overrides this with the actual implementation.
if type(_G.MSUF_UpdateCastbarChannelTicks) ~= "function" then
    function _G.MSUF_UpdateCastbarChannelTicks()
        --- Stub fallback: request a full visuals refresh if available.
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            if _G.MSUF_EnsureCastbars then
                _G.MSUF_EnsureCastbars()
            end
            _G.MSUF_UpdateCastbarVisuals()
        end
    end
end

if type(_G.MSUF_ApplyPlayerChannelTickMarkers) ~= "function" then
    function _G.MSUF_ApplyPlayerChannelTickMarkers()
        local fn = rawget(_G, "MSUF_UpdateCastbarChannelTicks")
        if type(fn) == "function" then
            return fn()
        end
    end
end

--- Phase 4: Module Registration
--- Castbars registers into the unified module lifecycle so that:
--- - Profile switches broadcast RefreshSettings -> castbar visuals re-apply
--- - Debug toggle can suppress all castbars at runtime
--- - Runtime loads from the main TOC; the bridge handles enable/disable logic.
do
    local reg = _G.MSUF_RegisterModule
    if type(reg) == "function" then
        reg("Castbars", {
            order = 40,
            IsEnabled = function()
                return _G.MSUF_AreAnyCastbarsEnabled and _G.MSUF_AreAnyCastbarsEnabled() or false
            end,
            Enable = function() end,
            Disable = function()
                if _G.MSUF_Castbars_ForceHideAll then
                    _G.MSUF_Castbars_ForceHideAll()
                end
            end,
            RefreshSettings = function(_, source)
                if _G.MSUF_Castbars_OnSettingsChanged then
                    _G.MSUF_Castbars_OnSettingsChanged(source or "module_refresh")
                end
                --- Bump style revision so castbar frames pick up texture/font changes
                if type(_G.MSUF_CastbarStyleRevision) == "number" then
                    _G.MSUF_CastbarStyleRevision = _G.MSUF_CastbarStyleRevision + 1
                end
                if _G.MSUF_ApplyPlayerChannelTickMarkers then
                    _G.MSUF_ApplyPlayerChannelTickMarkers()
                end
            end,
            Shutdown = function()
                if _G.MSUF_Castbars_ForceHideAll then
                    _G.MSUF_Castbars_ForceHideAll()
                end
            end,
        })
    end
end
