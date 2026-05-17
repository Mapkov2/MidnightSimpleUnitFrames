-- MSUF_EM2_Movers.lua — Movers + Elements + Compat (consolidated)

-- MSUF_EM2_Movers.lua

-- MSUF_EM2_Movers.lua — v9 Ticker-driven
-- Movers are dumb overlays. All drag math lives in Ticker.lua.
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Movers = {}
EM2.Movers = Movers

local max = math.max
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local round = function(n) return n + (2^52 + 2^51) - (2^52 + 2^51) end
local function ApplySettingsForKeySafe(key)
    local fn = _G.MSUF_ApplySettingsForKey
    if type(fn) == "function" then fn(key); return true end
    return false
end
local function ApplyAllSettingsSafe()
    local fn = _G.MSUF_ApplyAllSettings
    if type(fn) == "function" then fn(); return true end
    return false
end

local function Tr(text)
    if type(text) ~= "string" then return text end
    if type(ns) == "table" and type(ns.Translate) == "function" then
        return ns.Translate(text)
    end
    local locale = (type(ns) == "table" and ns.L) or _G.MSUF_L
    if type(locale) == "table" then
        local translated = rawget(locale, text)
        if translated ~= nil then return translated end
    end
    return text
end

local function T()
    return _G.MSUF_THEME or {
        bgR=0.08, bgG=0.09, bgB=0.10,
        edgeR=0.20, edgeG=0.30, edgeB=0.50,
        textR=0.92, textG=0.94, textB=1.00,
        titleR=1.00, titleG=0.82, titleB=0.00,
    }
end

local movers = {}
local moverParent

local function RefreshUFPreview(reason)
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then return end
    local fn = _G.MSUF_UFPreview_RequestRefresh
    if type(fn) == "function" then fn(reason or "EM2_MOVERS") end
end

local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then
        return _G.MSUF_IsConfigCombatLocked() and true or false
    end
    if InCombatLockdown and InCombatLockdown() then return true end
    return (UnitAffectingCombat and UnitAffectingCombat("player")) and true or false
end

local function BlockConfigCombatLocked()
    if type(_G.MSUF_BlockConfigCombatLocked) == "function" then
        return _G.MSUF_BlockConfigCombatLocked() and true or false
    end
    if IsConfigCombatLocked() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        end
        return true
    end
    return false
end

local function SyncMoverToFrame(mover, frame)
    if not frame then return end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return end
    local fS = frame:GetEffectiveScale()
    local uiS = UIParent:GetEffectiveScale()
    local ratio = fS / uiS
    local w = round((r - l) * ratio)
    local h = round((t - b) * ratio)
    local x = round(l * ratio)
    local y = round(t * ratio - UIParent:GetHeight())
    mover:ClearAllPoints()
    mover:SetSize(w, h)
    mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function CreateMover(key, cfg)
    local th = T()

    local mover = CreateFrame("Button", nil, moverParent)
    mover:SetSize(100, 30)
    mover:SetFrameStrata("FULLSCREEN"); mover:SetFrameLevel(300)
    mover:SetMovable(true); mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true); mover:SetClampedToScreen(true)
    mover._barKey = key

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
    mover._bg = bg

    local brd = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    brd:SetAllPoints(); brd:SetFrameLevel(max(0, mover:GetFrameLevel() - 1))
    brd:SetBackdrop({ edgeFile = W8, edgeSize = 1 })
    brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
    mover._brd = brd

    local label = mover:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT, 10, "OUTLINE"); label:SetPoint("CENTER")
    label:SetTextColor(th.textR, th.textG, th.textB, 0.85); label:SetText(Tr(cfg.label or key))
    mover._label = label

    local coordFS = mover:CreateFontString(nil, "OVERLAY")
    coordFS:SetFont(FONT, 9, "OUTLINE"); coordFS:SetPoint("TOP", mover, "BOTTOM", 0, -2)
    coordFS:SetTextColor(th.titleR, th.titleG, th.titleB, 0.90); coordFS:Hide()
    mover._coordFS = coordFS

    mover:SetScript("OnEnter", function(self)
        if self._dragging then return end
        local t = T()
        self._bg:SetColorTexture(t.bgR+0.05, t.bgG+0.05, t.bgB+0.08, 0.75)
        self._brd:SetBackdropBorderColor(t.titleR, t.titleG, t.titleB, 0.80)
        if self._label:IsShown() then self._label:SetTextColor(1, 1, 1, 1) end
    end)
    mover:SetScript("OnLeave", function(self)
        if self._dragging then return end
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        if self._label:IsShown() then self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85) end
    end)

    -- Hide label when preview is active (preview frame already shows unit name)
    function mover:UpdateLabelVisibility()
        if _G.MSUF_PreviewTestMode and not (_G.MSUF_InCombat or (_G.InCombatLockdown and _G.InCombatLockdown())) and not self._dragging then
            self._label:Hide()
            self._bg:SetColorTexture(0, 0, 0, 0)
            self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.25)
        else
            self._label:Show()
            self._bg:SetColorTexture(th.bgR, th.bgG, th.bgB, 0.55)
            self._brd:SetBackdropBorderColor(th.edgeR, th.edgeG, th.edgeB, 0.60)
        end
    end

    -- Drag → delegate to Ticker
    mover:SetScript("OnDragStart", function(self)
        if BlockConfigCombatLocked() then return end
        if _G.MSUF_EM2_SetPreviewNudgeTarget then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        self._dragging = true
        self._coordFS:Show()

        if _G.MSUF_EM_UndoBeforeChange then
            _G.MSUF_EM_UndoBeforeChange("unit", key)
        end

        if EM2.Ticker then EM2.Ticker.BeginDrag(self, key, cfg) end
    end)

    mover:SetScript("OnDragStop", function(self)
        self._dragging = false
        self._coordFS:Hide()

        if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

        local moved = false
        if EM2.Ticker then moved = EM2.Ticker.EndDrag() end

        -- Restore hover
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85)
    end)

    -- Click → popup
    mover:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        if _G.MSUF_EM2_SetPreviewNudgeTarget then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        if EM2.State then EM2.State.SetUnitKey(key) end
        if EM2.HUD then EM2.HUD.RefreshUnitSelector() end
        if EM2.Popups and EM2.Popups.Open then EM2.Popups.Open(key, self) end
    end)

    movers[key] = mover
    local frame = cfg.getFrame and cfg.getFrame()
    if frame then SyncMoverToFrame(mover, frame) end
    return mover
end

function Movers.Show()
    if not moverParent then
        moverParent = CreateFrame("Frame", "MSUF_EM2_MoverParent", UIParent)
        moverParent:SetAllPoints(UIParent); moverParent:SetFrameStrata("FULLSCREEN")
    end
    moverParent:Show()
    local reg = EM2.Registry and EM2.Registry.All()
    if not reg then return end
    for k, c in pairs(reg) do
        if not movers[k] then CreateMover(k, c) end
        local m = movers[k]
        local f = c.getFrame and c.getFrame()
        if f then SyncMoverToFrame(m, f); m:Show(); m:UpdateLabelVisibility() else m:Hide() end
    end
end

function Movers.Hide()
    if moverParent then moverParent:Hide() end
    for _, m in pairs(movers) do m:Hide() end
end
function Movers.IsShown() return moverParent and moverParent:IsShown() or false end
function Movers.All() return movers end
function Movers.Get(k) return movers[k] end

function Movers.SyncAll()
    if not moverParent or not moverParent:IsShown() then return end
    if EM2.Ticker and EM2.Ticker.IsDragging() then return end
    local reg = EM2.Registry and EM2.Registry.All()
    if not reg then return end
    for k, c in pairs(reg) do
        if c then
            if not movers[k] then CreateMover(k, c) end
            local m = movers[k]
            local f = c.getFrame and c.getFrame()
            if f then
                SyncMoverToFrame(m, f)
                m:Show()
                m:UpdateLabelVisibility()
            elseif m then
                m:Hide()
            end
        end
    end
end

-- MSUF_EM2_Elements.lua

-- MSUF_EM2_Elements.lua
-- Registers all existing MSUF elements with the EM2 Registry.
-- Deferred to PLAYER_LOGIN so unit frames exist.
local addonName, ns = ...

local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry then return end

local Reg = EM2.Registry

-- Frame resolvers (always live, no cached refs)
local function GetUF(key)
    local uf = _G.MSUF_UnitFrames
    if uf and uf[key] then return uf[key] end
    return _G["MSUF_" .. key]
end

local function GetBossUF(i)
    return _G["MSUF_boss" .. i]
end

local function GetConf(key)
    local db = _G.MSUF_DB
    return db and db[key]
end

-- isEnabled: true when the unit frame exists and unit tracking is on
local function UnitEnabled(key)
    return function()
        local f = GetUF(key)
        if not f then return false end
        local db = _G.MSUF_DB
        if not db or not db[key] then return true end
        if db[key].enabled == false then return false end
        return true
    end
end

local function BossEnabled(i)
    return function()
        local f = GetBossUF(i)
        if not f then return false end
        local db = _G.MSUF_DB
        if not db or not db.boss then return true end
        if db.boss.enabled == false then return false end
        return true
    end
end

-- Registration (deferred)
local function RegisterAll()
    -- Core unit frames
    local units = {
        { key = "player",       label = "Player",           order = 10 },
        { key = "target",       label = "Target",           order = 20 },
        { key = "focus",        label = "Focus",            order = 30 },
        { key = "targettarget", label = "Target of Target", order = 40 },
        { key = "focustarget",  label = "Focus Target",     order = 45 },
        { key = "pet",          label = "Pet",              order = 50 },
    }

    for _, u in ipairs(units) do
        Reg.Register({
            key       = u.key,
            label     = u.label,
            order     = u.order,
            popupType = "unit",
            canResize = true,
            canNudge  = true,
            getFrame  = function() return GetUF(u.key) end,
            getConf   = function() return GetConf(u.key) end,
            isEnabled = UnitEnabled(u.key),
        })
    end

    -- Boss: only boss1 gets a mover. All boss frames share one config ("boss").
    -- Moving boss1 writes offsetX/Y → ApplySettingsForKey("boss") repositions all.
    -- Boss2-5 auto-position via (index-1)*spacing in PositionUnitFrame.
    Reg.Register({
        key       = "boss",
        label     = "Boss",
        order     = 61,
        popupType = "unit",
        canResize = true,
        canNudge  = true,
        getFrame  = function() return GetBossUF(1) end,
        getConf   = function() return GetConf("boss") end,
        isEnabled = BossEnabled(1),
    })

    -- Future Phase 2 registrations:
    -- Castbar elements (per-unit)
    -- Auras2 groups (per-unit)
    -- Class Power bar
    -- These will register when their respective modules load.
end

-- Deferred init: register once frames are ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Delay one frame to ensure all unit frames are created
    C_Timer.After(0, function()
        RegisterAll()
    end)
end)

-- MSUF_EM2_Compat.lua

-- MSUF_EM2_Compat.lua
-- Legacy global stubs so external files (30+) continue to work after
-- MSUF_EditMode.lua is deleted. Every function listed here was exported
-- by the old EditMode and is called from at least one other file.
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
    if BlockConfigCombatLocked() then return false end
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
        if BlockConfigCombatLocked() then return end
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
    conf.anchorFrameName = nil
    conf.anchorToUnitframe = "GLOBAL"
    if db.general then
        db.general.anchorToCooldown = false
        db.general.anchorName = "UIParent"
    end
    if not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
end

-- ── MSUF_UpdateEditModeInfo (called by Castbars/main) ─────
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
_G.MSUF_SyncUnitPositionPopup = function(unit)
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_UNIT_POPUP", unit)
end

-- ── MSUF_SyncCastbarPositionPopup ────────────────────────────────────────
_G.MSUF_SyncCastbarPositionPopup = function(unit)
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_CASTBAR_POPUP", unit)
end

-- ── MSUF_SyncAuras2PositionPopup ─────────────────────────────────────────
_G.MSUF_SyncAuras2PositionPopup = function(unit)
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
end

-- ── MSUF_SetMSUFEditModeDirect (THE primary entry point) ─────────────────
_G.MSUF_SetMSUFEditModeDirect = function(active, unitKey)
    if not EM2.State then return end
    if active and type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then return false end
    if active and IsConfigCombatLocked() then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
        return false
    end
    if active then EM2.State.Enter(unitKey)
    else EM2.State.Exit("direct") end
    return true
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

local PREVIEW_UNITS = { "target", "focus", "focustarget", "targettarget", "pet" }

_G.MSUF_EM2_ReforcePreviewFrames = function()
    if not _G.MSUF_PreviewTestMode then return end
    if IsConfigCombatLocked() then return end
    local UpdateFn = _G.MSUF_UpdateSimpleUnitFrame
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
        if _G.MSUF_EM2_ReforcePreviewFrames then
            _G.MSUF_EM2_ReforcePreviewFrames()
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    end)
end

_G.MSUF_SyncAllUnitPreviews = function()
    local active = _G.MSUF_UnitPreviewActive and true or false
    local editOn = EM2.State and EM2.State.IsActive()
    local want = active and editOn

    if IsConfigCombatLocked() then
        _G.MSUF_PreviewTestMode = false
        _G.MSUF_BossTestMode = false
        return
    end

    -- Set preview flag (core visibility driver reads this)
    _G.MSUF_PreviewTestMode = want

    -- 1) Boss: existing system
    _G.MSUF_BossTestMode = want
    if _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
        _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end

    -- 2) Non-player: refresh visibility drivers (reads MSUF_PreviewTestMode),
    --    then update each frame (pipeline calls EditPrev for unitless frames)
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
    end

    local UpdateFn = _G.MSUF_UpdateSimpleUnitFrame
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
    if _G.MSUF_SyncCastbarEditModeWithUnitEdit then
        _G.MSUF_SyncCastbarEditModeWithUnitEdit()
    end
    for _, fn in ipairs({
        "MSUF_SetPlayerCastbarTestMode", "MSUF_SetTargetCastbarTestMode",
        "MSUF_SetFocusCastbarTestMode", "MSUF_SetBossCastbarTestMode",
    }) do
        local f = _G[fn]; if type(f) == "function" then f(want, true) end
    end

    -- 4) Aura refresh
    if _G.MSUF_Auras2_RefreshAll then
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
        if IsConfigCombatLocked() then return end
        C_Timer.After(delay, function()
            if not _G.MSUF_PreviewTestMode then return end
            if IsConfigCombatLocked() then return end
            if _G.MSUF_EM2_ReforcePreviewFrames then
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
        if type(_G.MSUF_ApplyAllSettings) ~= "function" then return end
        _hooksInstalled = true

        -- Pipeline entry points (async commit → 0.12s settle)
        SafeHook("MSUF_ApplyAllSettings", 0.12)
        SafeHook("ApplyAllSettings", 0.12)
        SafeHook("MSUF_ApplySettingsForKey", 0.12)
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

    if _G.MSUF_UpdateCastbarVisuals then
        _G.MSUF_UpdateCastbarVisuals()
    end
    if _G.MSUF_UpdatePlayerCastbarPreview then
        _G.MSUF_UpdatePlayerCastbarPreview()
    end
    if _G.MSUF_UpdateTargetCastbarPreview then
        _G.MSUF_UpdateTargetCastbarPreview()
    end
    if _G.MSUF_UpdateFocusCastbarPreview then
        _G.MSUF_UpdateFocusCastbarPreview()
    end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and _G.MSUF_UpdateBossCastbarPreview
    then
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
    if _G.MSUF_UpdateCastbarVisuals then _G.MSUF_UpdateCastbarVisuals() end
    RefreshUFPreview("EM2_CASTBAR_ANCHOR_TOGGLE", unit)
end

-- ── Anchor Picker Singleton ─────────────────────────────────────────────
-- Shared by Edit Mode and Menu2 anchor pickers.
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
        local topPanel = CreateFrame("Frame", nil, ov, "BackdropTemplate")
        topPanel:SetPoint("TOP", ov, "TOP", 0, -92)
        topPanel:SetSize(760, 58)
        topPanel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        topPanel:SetBackdropColor(0.01, 0.015, 0.025, 0.96)
        topPanel:SetBackdropBorderColor(1, 0.82, 0, 0.75)
        ov._topPanel = topPanel
        local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        local info = topPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        info:SetPoint("TOP", topPanel, "TOP", 0, -8)
        info:SetJustifyH("CENTER")
        info:SetFont(font, 15, "OUTLINE")
        info:SetTextColor(1.00, 0.88, 0.22, 1)
        info:SetShadowColor(0, 0, 0, 1)
        info:SetShadowOffset(1, -1)
        ov._info = info
        local sub = topPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOP", info, "BOTTOM", 0, -8)
        sub:SetJustifyH("CENTER")
        sub:SetWidth(720)
        sub:SetFont(font, 12, "OUTLINE")
        sub:SetTextColor(1, 1, 1, 1)
        sub:SetShadowColor(0, 0, 0, 1)
        sub:SetShadowOffset(1, -1)
        ov._sub = sub
        local hover = ov:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hover:SetPoint("BOTTOMLEFT", ov, "BOTTOMLEFT", 24, 24); hover:SetTextColor(0.9, 0.9, 0.9); ov._hover = hover
        local ctrl = ov:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ctrl:SetPoint("BOTTOM", ov, "BOTTOM", 0, 54); ctrl:SetJustifyH("CENTER"); ov._ctrlHint = ctrl
        local hl = CreateFrame("Frame", "MSUF_AnchorPickerHighlight", ov, "BackdropTemplate")
        hl:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        hl:SetBackdropBorderColor(0, 1, 0, 0.95); hl:Hide(); ov._highlight = hl

        ov:SetScript("OnShow", function(self)
            if type(_G.MSUF_BlockConfigCombatLocked) == "function" and _G.MSUF_BlockConfigCombatLocked() then
                self:Hide()
                return
            end
            self._elapsed = 0; self._pickedFrame = nil; self._pickedName = nil
            self._lCtrlHeld = Tr("CTRL: held - click to anchor!")
            self._lCtrlNotHeld = Tr("CTRL: not held")
            self._lHoverNone = Tr("Hover: no named frame found")
            self._lHoverFmt = Tr("Hover: %s")
            self._lCtrlRequired = Tr("|cffff6060CTRL required:|r |cffffffffhold |r|cff55ff55CTRL + Left-Click|r|cffffffff to confirm the anchor target.|r")
            self._lNoNamedFrame = Tr("|cffffcc33No named frame found under cursor.|r |cffffffffTry a different spot.|r")
            self._info:SetText(Tr("Anchor Picker"))
            self._sub:SetText(Tr("|cffffffffHover a frame, then hold |r|cff55ff55CTRL + Left-Click|r|cffffffff to anchor.  |  Right-Click or Escape cancels.|r"))
            self._hover:SetText(self._lHoverNone)
            self._ctrlHint:SetText(self._lCtrlNotHeld); self._ctrlHint:SetTextColor(1, 0.3, 0.3)
            self._highlight:Hide()
            if self.RegisterEvent then self:RegisterEvent("GLOBAL_MOUSE_DOWN") end
            if self.RegisterEvent then self:RegisterEvent("PLAYER_REGEN_DISABLED") end
        end)
        ov:SetScript("OnHide", function(self)
            if self.UnregisterEvent then self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
            if self.UnregisterEvent then self:UnregisterEvent("PLAYER_REGEN_DISABLED") end
            self._pickedFrame = nil; self._pickedName = nil; self._highlight:Hide()
        end)
        ov:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = (self._elapsed or 0) + elapsed; if self._elapsed < 0.03 then return end; self._elapsed = 0
            local cd = IsControlKeyDown and IsControlKeyDown()
            if cd then self._ctrlHint:SetText(self._lCtrlHeld); self._ctrlHint:SetTextColor(0.2, 1, 0.2)
            else self._ctrlHint:SetText(self._lCtrlNotHeld); self._ctrlHint:SetTextColor(1, 0.3, 0.3) end
            local f, n = _GetNamed(); self._pickedFrame = f; self._pickedName = n
            if n then
                self._hover:SetText(string.format(self._lHoverFmt, n))
                local l, b, w, h = _SafeGetRect(f)
                if l then
                    self._highlight:ClearAllPoints(); self._highlight:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b); self._highlight:SetSize(w, h)
                    self._highlight:SetBackdropBorderColor(cd and 0 or 1, cd and 1 or 1, 0, cd and 0.95 or 0.6); self._highlight:Show()
                else self._highlight:Hide() end
            else self._hover:SetText(self._lHoverNone); self._highlight:Hide() end
        end)
        ov:SetScript("OnEvent", function(self, event, button)
            if event == "PLAYER_REGEN_DISABLED" then
                if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then _G.MSUF_ShowConfigCombatLockMessage() end
                self:Hide()
                return
            end
            if event ~= "GLOBAL_MOUSE_DOWN" then return end
            if button == "RightButton" then self:Hide(); return end
            if button ~= "LeftButton" then return end
            if not (IsControlKeyDown and IsControlKeyDown()) then
                self._sub:SetText(self._lCtrlRequired); return
            end
            local n = self._pickedName
            if not n or n == "" then self._sub:SetText(self._lNoNamedFrame); return end
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
