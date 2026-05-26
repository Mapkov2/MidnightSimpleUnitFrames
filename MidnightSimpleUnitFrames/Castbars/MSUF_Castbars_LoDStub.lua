--- MSUF_Castbars_LoDStub.lua
--- LoadOnDemand bridge for MSUF Castbars (+ BossCastbars + FocusKickIcon).
--- Step 24: tighter enable-gate
--- - Do NOT load the Castbars LoD addon unless at least one castbar-related feature is enabled.
--- - Keep a tiny LoD API available at PLAYER_LOGIN without forcing a load.
--- - Provide MSUF_Castbars_OnSettingsChanged() for menus/options to call after toggles.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF
MSUF.UF = MSUF.UF or {}

local CASTBARS_ADDON = "MidnightSimpleUnitFrames_Castbars"

local function _IsLoaded(addonName)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName)
    end
    return IsAddOnLoaded(addonName)
end

local function _Load(addonName)
    if C_AddOns and C_AddOns.LoadAddOn then
        local ok = C_AddOns.LoadAddOn(addonName)
        return ok and true or false
    end
    local ok = LoadAddOn(addonName)
    return ok and true or false
end

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
    local fn = _G.MSUF_GetCastbarBackend
    if type(fn) == "function" then
        return fn(unit)
    end
    local key = _CastbarConfigKey(unit)
    if not key then
        return nil
    end
    return (_GetGeneral()[key] == false) and "BLIZZARD" or "MSUF"
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
--- If enablePlayerCastbar is false, Blizzard or another addon may own it.
if type(_G.MSUF_SuppressBlizzardPlayerCastbars) ~= "function" then
    --- Shared helpers (avoid per-call closures/allocations).
    local function _MSUF_HideNow(self)
        if _ShouldUseBlizzardCastbar("player") then return end
        if self and self.Hide then
            self:Hide()
        end
    end

    local function _MSUF_HideIfShown(self, shown)
        if shown and not _ShouldUseBlizzardCastbar("player") then
            _MSUF_HideNow(self)
        end
    end

    local function _MSUF_TryStopFrameWork(frame)
        if not frame or frame.MSUF_WorkStopped then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if frame.IsForbidden and frame:IsForbidden() then return end

        frame.MSUF_WorkStopped = true

        --- Best-effort: stop Blizzard casting bar from doing any work since we will never show it.
        if frame.UnregisterAllEvents then
            frame:UnregisterAllEvents()
        end
        if frame.SetScript then
            frame:SetScript("OnEvent", nil)
            frame:SetScript("OnUpdate", nil)
        end
    end

    local function _MSUF_HardenAndHide(frame)
        if not frame then return end

        _MSUF_TryStopFrameWork(frame)

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

        if _ShouldUseBlizzardCastbar("player") then
            return
        end

        if type(_G.MSUF_SuppressBlizzardPlayerCastbars) == "function" then
            _G.MSUF_SuppressBlizzardPlayerCastbars()
        end
    end)
end

--- Public helper (idempotent): used by other files to force-load castbars.
_G.MSUF_EnsureCastbarsLoaded = _G.MSUF_EnsureCastbarsLoaded or function(_reason)
    if _IsLoaded(CASTBARS_ADDON) then
        return true
    end
    return _Load(CASTBARS_ADDON)
end

--- Determine whether we should load the LoD addon at all.
--- IMPORTANT: boss castbars and focus kick also live in the LoD addon, so they count as "enabled".
_G.MSUF_AreAnyCastbarsEnabled = _G.MSUF_AreAnyCastbarsEnabled or function()
    local g = _GetGeneral()

    if _ShouldUseMSUFCastbar("player") then return true end
    if _ShouldUseMSUFCastbar("target") then return true end
    if _ShouldUseMSUFCastbar("focus") then return true end

    --- Boss castbars: only count if boss frames are enabled (otherwise avoid forcing LoD).
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

--- Minimal helper copies (these used to be provided by MSUF_Castbars.lua).
--- Keeping them here prevents nil-access during early load, and allows the stub
--- to decide whether to load the LoD addon.
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

--- Force-hide known MSUF castbar frames (best-effort). Useful when the LoD addon
--- is already loaded but the user disables all castbars.
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

    if _G.MSUF_AreAnyCastbarsEnabled() then
        _G.MSUF_EnsureCastbarsLoaded("settings")
        local ensureUnit = rawget(_G, "MSUF_CastbarDriver_EnsureUnit")
        if type(ensureUnit) == "function" then
            ensureUnit("target")
            ensureUnit("focus")
        end
        local fn = rawget(_G, "MSUF_Castbars_ApplyEnabledState")
        if type(fn) == "function" then
            fn()
        end
    else
        --- Can't unload an addon in WoW, but we can stop showing our frames.
        if _IsLoaded(CASTBARS_ADDON) then
            local fn = rawget(_G, "MSUF_Castbars_ApplyEnabledState")
            if type(fn) == "function" then
                fn()
            end
            _G.MSUF_Castbars_ForceHideAll()
        end
    end
end

--- Load-on-demand entry points that core may call during PLAYER_LOGIN.
--- These MUST exist even when the LoD addon isn't loaded yet.
--- The real implementations in the LoD addon re-define these globals
--- unconditionally, so these stubs will be replaced automatically after load.

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
    if _IsLoaded(CASTBARS_ADDON) then
        return true
    end

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

        --- If previews are off, there is nothing to do (and we should not force-load).
        if not g.castbarPlayerPreviewEnabled then return end

        --- If boss castbars are explicitly disabled, don't force-load just to hide a preview
        --- that can't exist yet. If LoD is already loaded, the real function will handle hiding.
        if not _ShouldUseMSUFCastbar("boss") then
            if _IsLoaded(CASTBARS_ADDON) then
                local fn = rawget(_G, "MSUF_UpdateBossCastbarPreview")
                if type(fn) == "function" and fn ~= _BossPreviewStub then
                    return fn()
                end
            end
            return
        end

        if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then return end

        --- Reentrancy guard: during LoadAddOn the boss module may call MSUF_UpdateBossCastbarPreview()
        --- before it replaces this stub, which can cause infinite recursion / C stack overflow.
        _G.MSUF__BossPreviewStubGuard = _G.MSUF__BossPreviewStubGuard or false
        if _G.MSUF__BossPreviewStubGuard then return end
        _G.MSUF__BossPreviewStubGuard = true

        local ok = _G.MSUF_EnsureCastbarsLoaded("boss_preview")
        if not ok then
            _G.MSUF__BossPreviewStubGuard = false
            return
        end

        --- Defer one frame to guarantee the LoD addon finished loading & replaced the global.
        _CastbarsRunNextFrame(_BossPreviewStubCallReal)
    end
    _G.MSUF_UpdateBossCastbarPreview = _BossPreviewStub
end

if type(_G.MSUF_SetBossCastbarTestMode) ~= "function" then
    local stub
    stub = function(active, keepSetting)
        if _CastbarPreviewCombatLocked() then return end
        if not _ShouldLoadForBoss() then return end
        _G.MSUF_EnsureCastbarsLoaded("boss_testmode")
        local fn = rawget(_G, "MSUF_SetBossCastbarTestMode")
        if type(fn) == "function" and fn ~= stub then
            return fn(active, keepSetting)
        end
    end
    _G.MSUF_SetBossCastbarTestMode = stub
end

--- Focus kick icon lives in the Castbars LoD addon. Provide an entry point so core can
--- call it safely even if the addon isn't loaded yet.
if type(_G.MSUF_InitFocusKickIcon) ~= "function" then
    local stub
    stub = function()
        _EnsureDB()
        local g = _GetGeneral()
        if g.enableFocusKickIcon ~= true then return end
        if MSUF_DB and MSUF_DB.focus and MSUF_DB.focus.enabled == false then return end
        _G.MSUF_EnsureCastbarsLoaded("focus_kick")
        local fn = rawget(_G, "MSUF_InitFocusKickIcon")
        if type(fn) == "function" and fn ~= stub then
            return fn()
        end
    end
    _G.MSUF_InitFocusKickIcon = stub
end

--- Convenience: autoload castbars on login ONLY if enabled.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if _G.MSUF_AreAnyCastbarsEnabled() then
        _G.MSUF_EnsureCastbarsLoaded("login")
    end
end)

--- Channeled cast tick markers (5 lines)
--- The real Castbars LoD addon should override this with the actual implementation.
if type(_G.MSUF_UpdateCastbarChannelTicks) ~= "function" then
    function _G.MSUF_UpdateCastbarChannelTicks()
        --- Stub fallback: force a full visuals refresh if available.
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            if _G.MSUF_EnsureCastbars then
                _G.MSUF_EnsureCastbars()
            end
            _G.MSUF_UpdateCastbarVisuals()
        end
    end
end

--- Player castbar: Custom channel tick markers (REAL CASTBAR)
--- - Reads MSUF_DB.player.castbar.channelTickUseCustom / channelTickCount / channelTickPosPct
--- - Renders vertical tick lines ON the real MSUF player castbar statusbar.
--- - Shows lines only while the player is CHANNELING (UnitChannelInfo("player") exists).
--- - Player-only. Does not affect target/focus/boss.

do
    local WHITE = "Interface\\Buttons\\WHITE8x8"
    local MAX_TICKS = 10

    local REAL = {
        bar = nil,          --- StatusBar
        ticks = {},         --- textures
        sizeHooked = false,
    }

    local function _GetPlayerCastbarDB()
        _EnsureDB()
        if not MSUF_DB then return nil end
        MSUF_DB.player = MSUF_DB.player or {}
        MSUF_DB.player.castbar = MSUF_DB.player.castbar or {}
        local pc = MSUF_DB.player.castbar
        if pc.channelTickUseCustom == nil then pc.channelTickUseCustom = false end
        if type(pc.channelTickCount) ~= "number" then pc.channelTickCount = 5 end
        if type(pc.channelTickPosPct) ~= "table" then pc.channelTickPosPct = {} end
        return pc
    end

    local function _FindStatusBar(obj)
        if not obj then return nil end
        if obj.GetObjectType and obj:GetObjectType() == "StatusBar" then
            return obj
        end
        local sb = obj.statusBar
        if sb and sb.GetObjectType and sb:GetObjectType() == "StatusBar" then
            return sb
        end
        sb = obj.bar
        if sb and sb.GetObjectType and sb:GetObjectType() == "StatusBar" then
            return sb
        end
        sb = obj.castbar
        if sb and sb.GetObjectType and sb:GetObjectType() == "StatusBar" then
            return sb
        end
        return nil
    end

    local function _FindRealPlayerCastbar()
        --- Ensure the LoD addon is loaded when player castbar is enabled.
        if type(_G.MSUF_IsCastbarEnabledForUnit) == "function" then
            if not _G.MSUF_IsCastbarEnabledForUnit("player") then
                return nil
            end
        end
        if _G.MSUF_EnsureCastbarsLoaded then
            _G.MSUF_EnsureCastbarsLoaded("player_custom_channel_ticks")
        end

        local candidates = {
            rawget(_G, "MSUF_PlayerCastBar"),
            rawget(_G, "MSUF_PlayerCastbar"),
            rawget(_G, "MSUF_PlayerCastBarFrame"),
            rawget(_G, "MSUF_PlayerCastbarFrame"),
            rawget(_G, "PlayerCastBar"), --- just in case
        }
        for i = 1, #candidates do
            local sb = _FindStatusBar(candidates[i])
            if sb then
                return sb
            end
        end
        return nil
    end

    local function _EnsureTick(i)
        local t = REAL.ticks[i]
        if t and t.SetPoint then
            return t
        end
        if not REAL.bar then return nil end

        t = REAL.bar:CreateTexture(nil, "OVERLAY")
        t:SetTexture(WHITE)
        t:SetVertexColor(1, 1, 1, 0.75)
        t:SetSize(1, 1)
        REAL.ticks[i] = t
        return t
    end

    local function _HideFrom(i)
        for n = i, #REAL.ticks do
            local t = REAL.ticks[n]
            if t then t:Hide() end
        end
    end

    local function _RenderTicks()
        local pc = _GetPlayerCastbarDB()
        if not pc or pc.channelTickUseCustom ~= true then
            _HideFrom(1)
            return
        end

        local bar = REAL.bar
        if not bar or not bar.GetWidth then
            _HideFrom(1)
            return
        end

        --- Show ticks only while channeling.
        local isChannel = false
        if UnitChannelInfo then
            isChannel = UnitChannelInfo("player") ~= nil
        end
        if not isChannel then
            _HideFrom(1)
            return
        end

        local count = tonumber(pc.channelTickCount) or 0
        if count < 0 then count = 0 elseif count > MAX_TICKS then count = MAX_TICKS end
        if count == 0 then
            _HideFrom(1)
            return
        end

        local w = bar:GetWidth() or 0
        local h = bar:GetHeight() or 0
        if w <= 1 or h <= 1 then
            --- Defer until layout.
            _CastbarsRunNextFrame(_RenderTicks)
            return
        end

        --- IMPORTANT: Keep the same ordering as the Options preview:
        --- Line 1 is the "first" line you see from LEFT -> RIGHT (no implicit reversing here).
        for i = 1, count do
            local pct = pc.channelTickPosPct and pc.channelTickPosPct[i]
            if type(pct) ~= "number" then
                pct = (i / (count + 1)) * 100
            end
            if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end

            local x = w * (pct / 100)

            local t = _EnsureTick(i)
            if t then
                t:ClearAllPoints()
                t:SetPoint("CENTER", bar, "LEFT", x, 0)
                t:SetSize(1, h)
                t:Show()
            end
        end
        _HideFrom(count + 1)
    end

    --- Public: can be called by Options on any setting change.
    _G.MSUF_ApplyPlayerChannelTickMarkers = function()
        REAL.bar = _FindRealPlayerCastbar()
        if not REAL.bar then
            _HideFrom(1)
            return
        end

        if not REAL.sizeHooked and REAL.bar.HookScript then
            REAL.sizeHooked = true
            REAL.bar:HookScript("OnSizeChanged", function()
                _RenderTicks()
            end)
        end

        _RenderTicks()
    end

    --- Event-driven updates: show/hide on channel start/stop/update.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    if ev.RegisterUnitEvent then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    else
        --- Fallback (older API): still ok in practice.
        ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
        ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    end

    ev:SetScript("OnEvent", function(_, event, unit)
        if unit and unit ~= "player" then return end
        if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "PLAYER_ENTERING_WORLD" then
            if _G.MSUF_ApplyPlayerChannelTickMarkers then
                _G.MSUF_ApplyPlayerChannelTickMarkers()
            end
        end
    end)
end

--- Phase 4: Module Registration
--- Castbars registers into the unified module lifecycle so that:
--- - Profile switches broadcast RefreshSettings -> castbar visuals re-apply
--- - Debug toggle can suppress all castbars at runtime
--- - LoD loading is NOT touched - existing stub handles load/unload logic
do
    local reg = _G.MSUF_RegisterModule
    if type(reg) == "function" then
        reg("Castbars", {
            order = 40,
            IsEnabled = function()
                return _G.MSUF_AreAnyCastbarsEnabled and _G.MSUF_AreAnyCastbarsEnabled() or false
            end,
            Enable = function()
                if _G.MSUF_AreAnyCastbarsEnabled and _G.MSUF_AreAnyCastbarsEnabled() then
                    if _G.MSUF_EnsureCastbarsLoaded then
                        _G.MSUF_EnsureCastbarsLoaded("module_enable")
                    end
                end
            end,
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
