-- ============================================================================
-- MSUF_EM2_Compat.lua
-- Legacy global stubs so external files (30+) continue to work after
-- MSUF_EditMode.lua is deleted. Every function listed here was exported
-- by the old EditMode and is called from at least one other file.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

-- ── Edit namespace (old code references _G.MSUF_Edit.*) ──────────────────
_G.MSUF_Edit = _G.MSUF_Edit or {}
local Edit = _G.MSUF_Edit
Edit.Popups = Edit.Popups or {}
Edit.Flow   = Edit.Flow   or {}
Edit.Util   = Edit.Util   or {}
Edit.UI     = Edit.UI     or {}

-- ── MSUF_EditState table (rawget'd by A2, Util, etc.) ────────────────────
if not _G.MSUF_EditState then
    _G.MSUF_EditState = { active = false, unitKey = nil, popupOpen = false }
end

-- ── MSUF_IsInEditMode ────────────────────────────────────────────────────
_G.MSUF_IsInEditMode = function()
    if EM2.State then return EM2.State.IsActive() end
    return _G.MSUF_UnitEditModeActive == true
end

-- ── MSUF_GetAnchorFrame ──────────────────────────────────────────────────
_G.MSUF_GetAnchorFrame = function()
    local db = _G.MSUF_DB
    local g = db and db.general or {}
    if g.anchorToCooldown then
        local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer")) or _G["EssentialCooldownViewer"]
        if ecv then return ecv end
        return UIParent
    end
    local anchorName = g.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local f = _G[anchorName]
        if f then return f end
    end
    return UIParent
end

-- ── MSUF_GetCurrentGridStep ──────────────────────────────────────────────
_G.MSUF_GetCurrentGridStep = function()
    if EM2.Grid then return EM2.Grid.GetGridStep() end
    local db = _G.MSUF_DB
    return (db and db.general and db.general.editModeGridStep) or 20
end

-- ── MSUF_MakeBlizzardOptionsMovable ──────────────────────────────────────
_G.MSUF_MakeBlizzardOptionsMovable = function()
    if InCombatLockdown and InCombatLockdown() then return end
    local frame = _G.SettingsPanel or _G.InterfaceOptionsFrame
    if not frame then return end
    if frame.MSUF_Movable then return end
    frame.MSUF_Movable = true
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
    local drag = CreateFrame("Frame", "MSUF_SettingsPanelDragHandle", frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -4)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -60, -4)
    drag:SetHeight(22)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then return end
        local p = self:GetParent()
        if p and p.StartMoving then p:StartMoving() end
    end)
    drag:SetScript("OnDragStop", function(self)
        local p = self:GetParent()
        if p and p.StopMovingOrSizing then p:StopMovingOrSizing() end
    end)
end

-- ── MSUF_ResetCurrentEditUnit ────────────────────────────────────────────
_G.MSUF_ResetCurrentEditUnit = function()
    local key = _G.MSUF_CurrentEditUnitKey
    if not key then return end
    local db = _G.MSUF_DB
    local conf = db and db[key]
    if not conf then return end
    conf.width = nil; conf.height = nil; conf.offsetX = nil; conf.offsetY = nil
    if type(ApplySettingsForKey) == "function" then ApplySettingsForKey(key)
    elseif type(ApplyAllSettings) == "function" then ApplyAllSettings() end
end

-- ── MSUF_UpdateEditModeInfo (called by Castbars, Options_Core, main) ─────
_G.MSUF_UpdateEditModeInfo = function()
    -- No-op: EM2 HUD handles display. Old GridFrame.infoText is gone.
end

-- ── MSUF_UpdateCastbarEditInfo ───────────────────────────────────────────
_G.MSUF_UpdateCastbarEditInfo = function() end

-- ── MSUF_UpdateGridOverlay ───────────────────────────────────────────────
_G.MSUF_UpdateGridOverlay = function()
    if EM2.State and EM2.State.IsActive() then
        if EM2.Grid then EM2.Grid.Show() end
    else
        if EM2.Grid then EM2.Grid.Hide() end
    end
end

-- ── MSUF_UpdateEditModeVisuals ───────────────────────────────────────────
_G.MSUF_UpdateEditModeVisuals = function()
    _G.MSUF_UpdateGridOverlay()
end

-- ── MSUF_CreateGridFrame ─────────────────────────────────────────────────
_G.MSUF_CreateGridFrame = function()
    if EM2.Grid then EM2.Grid.Show() end
end

-- ── MSUF_OpenPositionPopup (called from MidnightSimpleUnitFrames.lua OnMouseUp) ──
_G.MSUF_OpenPositionPopup = function(unit, parent)
    if EM2.Popups then EM2.Popups.Open(unit, parent) end
end

-- ── MSUF_OpenCastbarPositionPopup ────────────────────────────────────────
_G.MSUF_OpenCastbarPositionPopup = function(unit, parent)
    if EM2.CastPopup then EM2.CastPopup.Open(unit, parent) end
end

-- ── MSUF_OpenAuras2PositionPopup ─────────────────────────────────────────
_G.MSUF_OpenAuras2PositionPopup = function(unit, parent)
    if EM2.AuraPopup then EM2.AuraPopup.Open(unit, parent) end
end

-- ── MSUF_A2_EnsureAuraPositionPopup ──────────────────────────────────────
_G.MSUF_A2_EnsureAuraPositionPopup = function()
    -- Old code called this to lazily create the popup. EM2 creates on first Open.
    return nil
end

-- ── MSUF_SyncUnitPositionPopup ───────────────────────────────────────────
_G.MSUF_SyncUnitPositionPopup = function()
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
end

-- ── MSUF_SyncCastbarPositionPopup ────────────────────────────────────────
_G.MSUF_SyncCastbarPositionPopup = function(unit)
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
end

-- ── MSUF_SyncAuras2PositionPopup ─────────────────────────────────────────
_G.MSUF_SyncAuras2PositionPopup = function(unit)
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
end

-- ── MSUF_SetMSUFEditModeDirect (THE primary entry point) ─────────────────
_G.MSUF_SetMSUFEditModeDirect = function(active, unitKey)
    if not EM2.State then return end
    if active and InCombatLockdown and InCombatLockdown() then return end
    if active then EM2.State.Enter(unitKey)
    else EM2.State.Exit("direct") end
end

-- ── MSUF_SetMSUFEditModeFromBlizzard ─────────────────────────────────────
_G.MSUF_SetMSUFEditModeFromBlizzard = function(active)
    _G.MSUF_SetMSUFEditModeDirect(active, nil)
end

-- ── Preview System ───────────────────────────────────────────────────────
-- One global flag: MSUF_PreviewTestMode. Mirrors MSUF_BossTestMode exactly.
-- The core's visibility driver (line 2000) checks this flag to force-show.
-- The core's UpdateSimpleUnitFrame (line 4017) already applies EditPrev data.
-- Zero hooks, zero timers, zero pipeline fighting.
_G.MSUF_UnitPreviewActive = false
_G.MSUF_PreviewTestMode = false

local PREVIEW_UNITS = { "target", "focus", "targettarget", "pet" }

_G.MSUF_EM2_ReforcePreviewFrames = function()
    if not _G.MSUF_PreviewTestMode then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local UpdateFn = _G.UpdateSimpleUnitFrame
    for _, uk in ipairs(PREVIEW_UNITS) do
        local frame = _G["MSUF_" .. uk]
            or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[uk])
        if frame then
            if type(UpdateFn) == "function" then UpdateFn(frame) end
            frame:Show()
            if frame.SetAlpha then frame:SetAlpha(1) end
            if frame.EnableMouse then frame:EnableMouse(true) end
        end
    end
end

_G.MSUF_EM2_SchedulePreviewReforce = function()
    C_Timer.After(0.1, function()
        if type(_G.MSUF_EM2_ReforcePreviewFrames) == "function" then
            _G.MSUF_EM2_ReforcePreviewFrames()
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end)
end

_G.MSUF_SyncAllUnitPreviews = function()
    local active = _G.MSUF_UnitPreviewActive and true or false
    local editOn = EM2.State and EM2.State.IsActive()
    local want = active and editOn

    if InCombatLockdown and InCombatLockdown() then return end

    -- Set preview flag (core visibility driver reads this)
    _G.MSUF_PreviewTestMode = want

    -- 1) Boss: existing system
    _G.MSUF_BossTestMode = want
    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end

    -- 2) Non-player: refresh visibility drivers (reads MSUF_PreviewTestMode),
    --    then update each frame (pipeline calls EditPrev for unitless frames)
    if type(_G.MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
    end

    local UpdateFn = _G.UpdateSimpleUnitFrame
    for _, uk in ipairs(PREVIEW_UNITS) do
        local frame = _G["MSUF_" .. uk]
            or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[uk])
        if frame then
            if type(UpdateFn) == "function" then UpdateFn(frame) end
            if want then
                frame:Show()
                if frame.SetAlpha then frame:SetAlpha(1) end
                if frame.EnableMouse then frame:EnableMouse(true) end
            end
        end
    end

    -- 3) Castbars
    if want and type(_G.MSUF_EnsureCastbarsLoaded) == "function" then
        _G.MSUF_EnsureCastbarsLoaded("msuf_preview")
    end
    if type(_G.MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
        _G.MSUF_SyncCastbarEditModeWithUnitEdit()
    end
    for _, fn in ipairs({
        "MSUF_SetPlayerCastbarTestMode", "MSUF_SetTargetCastbarTestMode",
        "MSUF_SetFocusCastbarTestMode", "MSUF_SetBossCastbarTestMode",
    }) do
        local f = _G[fn]; if type(f) == "function" then f(want, true) end
    end

    -- 4) Aura refresh
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end

    -- 5) Sync movers
    if EM2.Movers and EM2.Movers.SyncAll then
        C_Timer.After(0.08, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end
end

-- ── Auto-reforce hooks ──────────────────────────────────────────────────
-- ANY pipeline trigger (fonts, indicators, bars, settings) can overwrite
-- ── Auto-reforce hooks ──────────────────────────────────────────────────
-- ANY visual update function can overwrite preview text/bars/colors.
-- Hook every entry point to schedule ReforcePreviewFrames after settle.
-- All hooks gate on MSUF_PreviewTestMode → zero combat overhead.
do
    local _hooksInstalled = false

    local function ScheduleReforce(delay)
        if not _G.MSUF_PreviewTestMode then return end
        C_Timer.After(delay, function()
            if not _G.MSUF_PreviewTestMode then return end
            if type(_G.MSUF_EM2_ReforcePreviewFrames) == "function" then
                _G.MSUF_EM2_ReforcePreviewFrames()
            end
        end)
    end

    local function SafeHook(name, delay)
        if type(_G[name]) == "function" then
            hooksecurefunc(name, function() ScheduleReforce(delay) end)
        end
    end

    local function InstallPipelineHooks()
        if _hooksInstalled then return end
        if type(_G.ApplyAllSettings) ~= "function" then return end
        _hooksInstalled = true

        -- Pipeline entry points (async commit → 0.12s settle)
        SafeHook("ApplyAllSettings", 0.12)
        SafeHook("ApplySettingsForKey", 0.12)

        -- Font updates (direct overwrite → 0.05s)
        SafeHook("MSUF_UpdateAllFonts", 0.05)
        SafeHook("MSUF_UpdateAllFonts_Immediate", 0.05)

        -- Color updates (direct per-frame iteration)
        SafeHook("MSUF_RefreshAllIdentityColors", 0.05)
        SafeHook("MSUF_RefreshAllPowerTextColors", 0.05)

        -- Bar visual updates
        SafeHook("MSUF_UpdateAllBarTextures", 0.05)
        SafeHook("MSUF_UpdateAllBarTextures_Immediate", 0.05)
        SafeHook("MSUF_ApplyBarOutlineThickness_All", 0.05)
        SafeHook("MSUF_ApplyPowerBarBorder_All", 0.05)
        SafeHook("MSUF_RefreshRareBarVisuals", 0.05)
        SafeHook("MSUF_ApplyReverseFillBars", 0.05)

        -- Castbar visuals
        SafeHook("MSUF_UpdateCastbarVisuals", 0.05)
        SafeHook("MSUF_UpdateCastbarVisuals_Immediate", 0.05)
        SafeHook("MSUF_UpdateCastbarTextures", 0.05)
        SafeHook("MSUF_UpdateCastbarTextures_Immediate", 0.05)

        -- Border/outline updates
        SafeHook("MSUF_RefreshDispelOutlineStates", 0.05)

        -- Alpha updates
        SafeHook("MSUF_ApplyAllAlpha", 0.05)
    end

    local _origSync = _G.MSUF_SyncAllUnitPreviews
    _G.MSUF_SyncAllUnitPreviews = function(...)
        InstallPipelineHooks()
        return _origSync(...)
    end
end

-- ── MSUF_SyncCastbarEditModeWithUnitEdit (castbar LoD preview sync) ───────
_G.MSUF_SyncCastbarEditModeWithUnitEdit = function()
    local db = _G.MSUF_DB
    if not db then return end
    db.general = db.general or {}
    local g = db.general
    local active = EM2.State and EM2.State.IsActive()
    g.castbarPlayerPreviewEnabled = active and true or false

    if active and type(_G.MSUF_EnsureCastbarsLoaded) == "function" then
        _G.MSUF_EnsureCastbarsLoaded("msuf_edit_mode")
    end

    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if type(_G.MSUF_UpdatePlayerCastbarPreview) == "function" then
        _G.MSUF_UpdatePlayerCastbarPreview()
    end
    if type(_G.MSUF_UpdateTargetCastbarPreview) == "function" then
        _G.MSUF_UpdateTargetCastbarPreview()
    end
    if type(_G.MSUF_UpdateFocusCastbarPreview) == "function" then
        _G.MSUF_UpdateFocusCastbarPreview()
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end

-- ── MSUF_SyncBossUnitframePreviewWithUnitEdit ────────────────────────────
_G.MSUF_SyncBossUnitframePreviewWithUnitEdit = _G.MSUF_SyncBossUnitframePreviewWithUnitEdit or function()
    -- Provided by MidnightSimpleUnitFrames.lua; stub if not yet available
end

-- ── Edit.Flow.Exit ───────────────────────────────────────────────────────
Edit.Flow.Exit = function(source, opts)
    if EM2.State then EM2.State.Exit(source or "flow") end
end

-- ── Edit.Transitions ─────────────────────────────────────────────────────
Edit.Transitions = Edit.Transitions or {}
Edit.Transitions.SetMSUFEditModeDirect = _G.MSUF_SetMSUFEditModeDirect

-- ── AnyEditMode listeners (registration handled in State.lua) ────────────

-- ── MSUF_EM_DropdownPreset (used by old Options code) ────────────────────
_G.MSUF_EM_DropdownPreset = function(drop, width, placeholder)
    if drop and UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(drop, width or 120) end
    if drop and UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, placeholder or "Select...") end
end

-- ── MSUF_EM_RegisterPopupDropdown (no-op, EM2 popups don't need layer management) ──
_G.MSUF_EM_RegisterPopupDropdown = function() end

-- ── MSUF_EM_AddPopupTitleAndClose (no-op, EM2 popups use Factory.Panel) ──
_G.MSUF_EM_AddPopupTitleAndClose = function() end

-- ── MSUF_EM_AddSectionHeader (no-op) ─────────────────────────────────────
_G.MSUF_EM_AddSectionHeader = function() end

-- ── MSUF_EM_AddDivider (no-op) ──────────────────────────────────────────
_G.MSUF_EM_AddDivider = function() end

-- ── Castbar anchor toggle (detach/attach to unitframe) ──────────────────
_G.MSUF_EM_SetCastbarAnchoredToUnit = _G.MSUF_EM_SetCastbarAnchoredToUnit or function(unit, anchored)
    if not unit then return end
    local db = _G.MSUF_DB; if not db then return end
    db.general = db.general or {}
    local g = db.general

    local detachedKey, oxKey, oyKey
    if unit == "boss" then
        detachedKey = "bossCastbarDetached"
        oxKey = "bossCastbarOffsetX"
        oyKey = "bossCastbarOffsetY"
    else
        local prefix = _G.MSUF_GetCastbarPrefix and _G.MSUF_GetCastbarPrefix(unit)
        if not prefix then return end
        detachedKey = prefix .. "Detached"
        oxKey = prefix .. "OffsetX"
        oyKey = prefix .. "OffsetY"
    end

    local wantDetached = (anchored == false)
    g[detachedKey] = wantDetached or nil

    -- If detaching, save current castbar center as UIParent offset
    if wantDetached then
        local castbar
        local pvNames = { player="MSUF_PlayerCastbarPreview", target="MSUF_TargetCastbarPreview", focus="MSUF_FocusCastbarPreview" }
        local pvName = pvNames[unit]
        if pvName then castbar = _G[pvName] end
        if not castbar and unit == "boss" then castbar = _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"] end
        if castbar and castbar.GetCenter then
            local cx, cy = castbar:GetCenter()
            local uiW = UIParent:GetWidth() or 1
            local uiH = UIParent:GetHeight() or 1
            if cx and cy then
                g[oxKey] = math.floor(cx - uiW * 0.5 + 0.5)
                g[oyKey] = math.floor(cy - uiH * 0.5 + 0.5)
            end
        end
    end

    -- Re-anchor
    local reanchorFns = {
        player = "MSUF_ReanchorPlayerCastBar",
        target = "MSUF_ReanchorTargetCastBar",
        focus  = "MSUF_ReanchorFocusCastBar",
        boss   = "MSUF_ApplyBossCastbarPositionSetting",
    }
    local ra = reanchorFns[unit]
    if ra and type(_G[ra]) == "function" then _G[ra]() end
    if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
end

-- ── Anchor Picker Singleton ─────────────────────────────────────────────
-- Shared by Edit Mode (global anchor) and Options_Player (per-unit anchor).
-- Caller sets _G.MSUF_AnchorPicker._onPick = function(frameName) ... end
-- before showing, to control where the picked name is written.
if not _G.MSUF_EnsureAnchorPicker then
do
    local function _IsBlocked(frame)
        if not frame then return true end
        if frame == UIParent or frame == WorldFrame then return true end
        if frame.IsForbidden and frame:IsForbidden() then return true end
        if frame.unitToken then return true end
        local ov = _G.MSUF_AnchorPicker
        if ov and (frame == ov or frame == ov._highlight) then return true end
        return false
    end
    local function _IsBlockedName(name)
        if type(name) ~= "string" or name == "" then return true end
        if name == "WorldFrame" or name == "UIParent" then return true end
        if name == "MSUF_AnchorPickerOverlay" or name == "MSUF_AnchorPickerHighlight" then return true end
        return false
    end
    local function _SafeGetRect(frame)
        if not frame or not frame.GetRect then return nil end
        if frame.IsForbidden and frame:IsForbidden() then return nil end
        local ok, l, b, w, h = pcall(frame.GetRect, frame)
        if not ok then return nil end
        l = tonumber(l); b = tonumber(b); w = tonumber(w); h = tonumber(h)
        if not (l and b and w and h) then return nil end
        if w <= 0 or h <= 0 then return nil end
        return l, b, w, h
    end
    local function _NamedFromFocus(frame)
        local seen = 0
        while frame and seen < 40 do
            if not _IsBlocked(frame) and frame.GetName then
                local n = frame:GetName()
                if not _IsBlockedName(n) then return frame, n end
            end
            frame = frame.GetParent and frame:GetParent() or nil
            seen = seen + 1
        end
        return nil, nil
    end
    local _isv = type(_G.issecretvalue) == "function" and _G.issecretvalue or nil
    local function _PlainBool(v)
        if _isv and _isv(v) then return nil end
        if v == true or v == 1 then return true end
        if v == false or v == 0 then return false end
        return nil
    end
    local function _SafeVis(frame)
        if not frame or not frame.IsVisible then return false end
        local ok, v = pcall(frame.IsVisible, frame)
        return ok and _PlainBool(v) == true
    end
    local _lastF, _lastN
    local function _GetNamed()
        local cx, cy = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale() or 1
        cx, cy = cx / sc, cy / sc
        if EnumerateFrames then
            local bestF, bestN, bestA = nil, nil, nil
            local fr = EnumerateFrames()
            while fr do
                if not (fr.IsForbidden and fr:IsForbidden()) and _SafeVis(fr) and not _IsBlocked(fr) then
                    local name = fr.GetName and fr:GetName() or nil
                    if not _IsBlockedName(name) then
                        local l, b, w, h = _SafeGetRect(fr)
                        if l and cx >= l and cx <= (l+w) and cy >= b and cy <= (b+h) then
                            local area = w * h
                            if (not bestA) or area < bestA then bestF, bestN, bestA = fr, name, area end
                        end
                    end
                end
                fr = EnumerateFrames(fr)
            end
            if bestN then _lastF, _lastN = bestF, bestN; return bestF, bestN end
        end
        if GetMouseFoci then
            local foci = GetMouseFoci()
            if type(foci) == "table" then
                for i = 1, #foci do
                    local f, n = _NamedFromFocus(foci[i])
                    if n then return f, n end
                end
            end
        end
        if GetMouseFocus then
            local f, n = _NamedFromFocus(GetMouseFocus())
            if n then return f, n end
        end
        return _lastF, _lastN
    end

    function _G.MSUF_EnsureAnchorPicker()
        if _G.MSUF_AnchorPicker then return _G.MSUF_AnchorPicker end
        local ov = CreateFrame("Frame", "MSUF_AnchorPickerOverlay", UIParent, "BackdropTemplate")
        _G.MSUF_AnchorPicker = ov
        ov:SetAllPoints(UIParent)
        ov:SetFrameStrata("FULLSCREEN_DIALOG"); ov:SetFrameLevel(100)
        ov:EnableMouse(false); ov:EnableKeyboard(true)
        if ov.SetPropagateKeyboardInput then ov:SetPropagateKeyboardInput(true) end
        ov:Hide(); ov._onPick = nil
        local bg = ov:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.12)
        local info = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        info:SetPoint("TOP", ov, "TOP", 0, -28); info:SetJustifyH("CENTER"); ov._info = info
        local sub = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOP", info, "BOTTOM", 0, -10); sub:SetJustifyH("CENTER"); ov._sub = sub
        local hover = ov:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hover:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", 24, 24); hover:SetTextColor(0.9, 0.9, 0.9); ov._hover = hover
        local ctrl = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ctrl:SetPoint("BOTTOM", ov, "BOTTOM", 0, 54); ctrl:SetJustifyH("CENTER"); ov._ctrlHint = ctrl
        local hl = CreateFrame("Frame", "MSUF_AnchorPickerHighlight", ov, "BackdropTemplate")
        hl:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        hl:SetBackdropBorderColor(0, 1, 0, 0.95); hl:Hide(); ov._highlight = hl

        ov:SetScript("OnShow", function(self)
            self._elapsed = 0; self._pickedFrame = nil; self._pickedName = nil
            self._info:SetText("Anchor Picker")
            self._sub:SetText("Hover over any frame, then CTRL + Left-Click to anchor.  |  Right-Click or Escape to cancel.")
            self._hover:SetText("Hover: no named frame found")
            self._ctrlHint:SetText("CTRL: not held"); self._ctrlHint:SetTextColor(1, 0.3, 0.3)
            self._highlight:Hide()
            if self.RegisterEvent then self:RegisterEvent("GLOBAL_MOUSE_DOWN") end
        end)
        ov:SetScript("OnHide", function(self)
            if self.UnregisterEvent then self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
            self._pickedFrame = nil; self._pickedName = nil; self._highlight:Hide()
        end)
        ov:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = (self._elapsed or 0) + elapsed; if self._elapsed < 0.03 then return end; self._elapsed = 0
            local cd = IsControlKeyDown and IsControlKeyDown()
            if cd then self._ctrlHint:SetText("CTRL: held  —  click to anchor!"); self._ctrlHint:SetTextColor(0.2, 1, 0.2)
            else self._ctrlHint:SetText("CTRL: not held"); self._ctrlHint:SetTextColor(1, 0.3, 0.3) end
            local f, n = _GetNamed(); self._pickedFrame = f; self._pickedName = n
            if n then
                self._hover:SetText("Hover: " .. n)
                local l, b, w, h = _SafeGetRect(f)
                if l then
                    self._highlight:ClearAllPoints(); self._highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b); self._highlight:SetSize(w, h)
                    self._highlight:SetBackdropBorderColor(cd and 0 or 1, cd and 1 or 1, 0, cd and 0.95 or 0.6); self._highlight:Show()
                else self._highlight:Hide() end
            else self._hover:SetText("Hover: no named frame found"); self._highlight:Hide() end
        end)
        ov:SetScript("OnEvent", function(self, event, button)
            if event ~= "GLOBAL_MOUSE_DOWN" then return end
            if button == "RightButton" then self:Hide(); return end
            if button ~= "LeftButton" then return end
            if not (IsControlKeyDown and IsControlKeyDown()) then
                self._sub:SetText("|cffff5555You must hold CTRL|r while left-clicking to confirm the anchor target."); return
            end
            local n = self._pickedName
            if not n or n == "" then self._sub:SetText("No named frame found under cursor. Try a different spot."); return end
            if type(self._onPick) == "function" then self._onPick(n) end
            self:Hide()
        end)
        ov:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end; self:Hide()
            else if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(true) end end
        end)
        return ov
    end
end
end
