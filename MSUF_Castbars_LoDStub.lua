-- MSUF_Castbars_LoDStub.lua
-- LoadOnDemand bridge for MSUF Castbars (+ BossCastbars + FocusKickIcon).
--
-- Step 24: tighter enable-gate
-- - Do NOT load the Castbars LoD addon unless at least one castbar-related feature is enabled.
-- - Provide wrapper globals that core can call safely at PLAYER_LOGIN without forcing a load.
-- - Provide a helper MSUF_Castbars_OnSettingsChanged() for menus/options to call after toggles.

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
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
end

local function _GetGeneral()
    _EnsureDB()
    return (MSUF_DB and MSUF_DB.general) or {}
end
---------------------------------------------------------------------
-- Blizzard castbar ownership handshake (stub-level)
--
-- Why here:
-- - Core loads this stub without forcing the Castbars LoD addon.
-- - Both Core and the LoD module can use the same owner tag to avoid
--   double-suppressing Blizzard castbars (duplicate hooks / timing drift).
---------------------------------------------------------------------

if type(_G.MSUF_ClaimBlizzardCastbarOwnership) ~= "function" then
    function _G.MSUF_ClaimBlizzardCastbarOwnership(tag)
        if tag == nil then tag = "MSUF_Unknown" end
        local cur = rawget(_G, "MSUF_BlizzardCastbarOwner")
        if cur and cur ~= tag then
            return false
        end
        _G.MSUF_BlizzardCastbarOwner = tag
        return true
    end
end

if type(_G.MSUF_GetBlizzardCastbarOwner) ~= "function" then
    function _G.MSUF_GetBlizzardCastbarOwner()
        return rawget(_G, "MSUF_BlizzardCastbarOwner")
    end
end

-- Public helper (idempotent): used by other files to force-load castbars.
_G.MSUF_EnsureCastbarsLoaded = _G.MSUF_EnsureCastbarsLoaded or function(_reason)
    if _IsLoaded(CASTBARS_ADDON) then
        return true
    end
    return _Load(CASTBARS_ADDON)
end

-- Determine whether we should load the LoD addon at all.
-- IMPORTANT: boss castbars and focus kick also live in the LoD addon, so they count as "enabled".
_G.MSUF_AreAnyCastbarsEnabled = _G.MSUF_AreAnyCastbarsEnabled or function()
    local g = _GetGeneral()

    if g.enablePlayerCastbar ~= false then return true end
    if g.enableTargetCastbar ~= false then return true end
    if g.enableFocusCastbar ~= false then return true end

    -- Boss castbars: only count if boss frames are enabled (otherwise avoid forcing LoD).
    if g.enableBossCastbar then
        local bossFramesEnabled = true
        if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
            bossFramesEnabled = false
        end
        if bossFramesEnabled then
            return true
        end
    end

    -- Focus kick icon: only count if focus frame is enabled.
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

-- Minimal helper copies (these used to be provided by MSUF_Castbars.lua).
-- Keeping them here prevents nil-access during early load, and allows the stub
-- to decide whether to load the LoD addon.
if not _G.MSUF_IsCastbarEnabledForUnit then
    function _G.MSUF_IsCastbarEnabledForUnit(unit)
        local g = _GetGeneral()
        if unit == "player" then
            return g.enablePlayerCastbar ~= false
        elseif unit == "target" then
            return g.enableTargetCastbar ~= false
        elseif unit == "focus" then
            return g.enableFocusCastbar ~= false
        end
        return true
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

-- Force-hide known MSUF castbar frames (best-effort). Useful when the LoD addon
-- is already loaded but the user disables all castbars.
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

    -- Boss castbars (best-effort)
    for i = 1, 10 do
        _hide(_G["MSUF_boss" .. i .. "CastBar"])
    end
end

-- Settings change helper (menus/options may call this after toggles change).
_G.MSUF_Castbars_OnSettingsChanged = _G.MSUF_Castbars_OnSettingsChanged or function(_reason)
    if _G.MSUF_AreAnyCastbarsEnabled() then
        _G.MSUF_EnsureCastbarsLoaded("settings")
        local fn = rawget(_G, "MSUF_Castbars_ApplyEnabledState")
        if type(fn) == "function" then
            fn()
        end
    else
        -- Can't unload an addon in WoW, but we can stop showing our frames.
        if _IsLoaded(CASTBARS_ADDON) then
            local fn = rawget(_G, "MSUF_Castbars_ApplyEnabledState")
            if type(fn) == "function" then
                fn()
            end
            _G.MSUF_Castbars_ForceHideAll()
        end
    end
end

-- Wrappers for legacy global APIs that core expects during PLAYER_LOGIN.
-- These MUST exist even when the LoD addon isn't loaded yet.
-- The real implementations in the LoD addon re-define these globals
-- unconditionally, so these wrappers will be replaced automatically after load.

if type(_G.MSUF_ReanchorTargetCastBar) ~= "function" then
    local wrapper
    wrapper = function()
        _EnsureDB()
        local g = _GetGeneral()

        -- If previews are off, there is nothing to do (and we should not force-load).
        if not g.castbarPlayerPreviewEnabled then
            return
        end

        -- If boss castbars are explicitly disabled, don't force-load just to hide a preview
        -- that can't exist yet. If LoD is already loaded, the real function will handle hiding.
        if g.enableBossCastbar == false then
            if _IsLoaded(CASTBARS_ADDON) then
                local fn = rawget(_G, "MSUF_UpdateBossCastbarPreview")
                if type(fn) == "function" and fn ~= wrapper then
                    return fn()
                end
            end
            return
        end

        if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
            return
        end

        -- Reentrancy guard: during LoadAddOn the boss module may call MSUF_UpdateBossCastbarPreview()
        -- before it replaces this stub wrapper, which can cause infinite recursion / C stack overflow.
        _G.MSUF__BossPreviewStubGuard = _G.MSUF__BossPreviewStubGuard or false
        if _G.MSUF__BossPreviewStubGuard then
            return
        end
        _G.MSUF__BossPreviewStubGuard = true

        local ok = _G.MSUF_EnsureCastbarsLoaded("boss_preview")
        if not ok then
            _G.MSUF__BossPreviewStubGuard = false
            return
        end

        local function _CallReal()
            local fn = rawget(_G, "MSUF_UpdateBossCastbarPreview")
            if type(fn) == "function" and fn ~= wrapper then
                pcall(fn)
            end
            _G.MSUF__BossPreviewStubGuard = false
        end

        -- Defer one frame to guarantee the LoD addon finished loading & replaced the global.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, _CallReal)
        else
            _CallReal()
        end
    end
    _G.MSUF_UpdateBossCastbarPreview = wrapper
end

if type(_G.MSUF_SetBossCastbarTestMode) ~= "function" then
    local wrapper
    wrapper = function(active, keepSetting)
        if not _ShouldLoadForBoss() then
            return
        end
        _G.MSUF_EnsureCastbarsLoaded("boss_testmode")
        local fn = rawget(_G, "MSUF_SetBossCastbarTestMode")
        if type(fn) == "function" and fn ~= wrapper then
            return fn(active, keepSetting)
        end
    end
    _G.MSUF_SetBossCastbarTestMode = wrapper
end


-- Focus kick icon lives in the Castbars LoD addon. Provide a wrapper so core can
-- call it safely even if the addon isn't loaded yet.
if type(_G.MSUF_InitFocusKickIcon) ~= "function" then
    local wrapper
    wrapper = function()
        _EnsureDB()
        local g = _GetGeneral()
        if g.enableFocusKickIcon ~= true then
            return
        end
        if MSUF_DB and MSUF_DB.focus and MSUF_DB.focus.enabled == false then
            return
        end
        _G.MSUF_EnsureCastbarsLoaded("focus_kick")
        local fn = rawget(_G, "MSUF_InitFocusKickIcon")
        if type(fn) == "function" and fn ~= wrapper then
            return fn()
        end
    end
    _G.MSUF_InitFocusKickIcon = wrapper
end

-- Convenience: autoload castbars on login ONLY if enabled.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if _G.MSUF_AreAnyCastbarsEnabled() then
        _G.MSUF_EnsureCastbarsLoaded("login")
    end
end)


-- Channeled cast tick markers (5 lines)
-- The real Castbars LoD addon should override this with the actual implementation.
if type(_G.MSUF_UpdateCastbarChannelTicks) ~= "function" then
    function _G.MSUF_UpdateCastbarChannelTicks()
        -- Stub fallback: force a full visuals refresh if available.
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            if type(_G.MSUF_EnsureCastbars) == "function" then
                _G.MSUF_EnsureCastbars()
            end
            _G.MSUF_UpdateCastbarVisuals()
        end
    end
end


-- ============================================================
-- Player castbar: Custom channel tick markers (REAL CASTBAR)
-- - Reads MSUF_DB.player.castbar.channelTickUseCustom / channelTickCount / channelTickPosPct
-- - Renders vertical tick lines ON the real MSUF player castbar statusbar.
-- - Shows lines only while the player is CHANNELING (UnitChannelInfo("player") exists).
-- - Player-only. Does not affect target/focus/boss.
-- ============================================================

do
    local WHITE = "Interface\\Buttons\\WHITE8x8"
    local MAX_TICKS = 10

    local REAL = {
        bar = nil,          -- StatusBar
        ticks = {},         -- textures
        sizeHooked = false,
    }

    local function _GetPlayerCastbarDB()
        if type(EnsureDB) == "function" then EnsureDB() end
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
        -- Ensure the LoD addon is loaded when player castbar is enabled.
        if type(_G.MSUF_IsCastbarEnabledForUnit) == "function" then
            if not _G.MSUF_IsCastbarEnabledForUnit("player") then
                return nil
            end
        end
        if type(_G.MSUF_EnsureCastbarsLoaded) == "function" then
            _G.MSUF_EnsureCastbarsLoaded("player_custom_channel_ticks")
        end

        local candidates = {
            rawget(_G, "MSUF_PlayerCastBar"),
            rawget(_G, "MSUF_PlayerCastbar"),
            rawget(_G, "MSUF_PlayerCastBarFrame"),
            rawget(_G, "MSUF_PlayerCastbarFrame"),
            rawget(_G, "PlayerCastBar"), -- just in case
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

        -- Show ticks only while channeling.
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
            -- Defer until layout.
            if C_Timer and C_Timer.After then
                C_Timer.After(0, _RenderTicks)
            end
            return
        end

        -- IMPORTANT: Keep the same ordering as the Options preview:
        -- Line 1 is the "first" line you see from LEFT -> RIGHT (no implicit reversing here).
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

    -- Public: can be called by Options on any setting change.
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

    -- Event-driven updates: show/hide on channel start/stop/update.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    if ev.RegisterUnitEvent then
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    else
        -- Fallback (older API): still ok in practice.
        ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
        ev:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    end

    ev:SetScript("OnEvent", function(_, event, unit)
        if unit and unit ~= "player" then return end
        if event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "PLAYER_ENTERING_WORLD" then
            if type(_G.MSUF_ApplyPlayerChannelTickMarkers) == "function" then
                _G.MSUF_ApplyPlayerChannelTickMarkers()
            end
        end
    end)
end
