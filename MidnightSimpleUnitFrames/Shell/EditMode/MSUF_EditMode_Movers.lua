--- EditMode/MSUF_EditMode_Movers.lua - Edit Mode mover registration and dragging

--- MSUF_EM2_Movers.lua

--- MSUF_EM2_Movers.lua ? v9 Ticker-driven
--- Movers are dumb overlays. All drag math lives in Ticker.lua.
local addonName, MSUF = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Movers = {}
EM2.Movers = Movers

local max = math.max
local W8 = "Interface/Buttons/WHITE8X8"
local FONT = STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF"
local U = EM2.Util or {}
local round = U.Round
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local ApplyAllSettingsSafe = U.ApplyAllSettingsSafe
local Tr = U.Tr
local ThemeColor = U.ThemeColor

local function T()
    local legacy = _G.MSUF_THEME or {}
    local bg = ThemeColor("card", { legacy.bgR or 0.08, legacy.bgG or 0.09, legacy.bgB or 0.10, legacy.bgA or 0.55 })
    local edge = ThemeColor("borderSoft", { legacy.edgeR or 0.20, legacy.edgeG or 0.30, legacy.edgeB or 0.50, legacy.edgeA or 0.60 })
    local text = ThemeColor("text", { legacy.textR or 0.92, legacy.textG or 0.94, legacy.textB or 1.00, legacy.textA or 1.00 })
    local accent = ThemeColor("accent", { legacy.titleR or 1.00, legacy.titleG or 0.82, legacy.titleB or 0.00, 1 })
    return {
        bgR = bg[1], bgG = bg[2], bgB = bg[3],
        edgeR = edge[1], edgeG = edge[2], edgeB = edge[3],
        textR = text[1], textG = text[2], textB = text[3],
        titleR = accent[1], titleG = accent[2], titleB = accent[3],
    }
end

local movers = {}
local moverParent

local function RefreshUFPreview(reason)
    if _G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()) then return end
    if U.RefreshUFPreview then U.RefreshUFPreview(reason or "EM2_MOVERS") end
end

local IsConfigCombatLocked = U.IsConfigCombatLocked
local BlockConfigCombatLocked = U.BlockConfigCombatLocked

local function FrameRectToUI(frame)
    if not (frame and frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom) then
        return nil
    end
    if frame.IsShown and not frame:IsShown() then return nil end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (l and r and t and b) then return nil end
    local fS = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    local uiS = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not fS or fS == 0 then fS = 1 end
    if not uiS or uiS == 0 then uiS = 1 end
    local ratio = fS / uiS
    return l * ratio, r * ratio, t * ratio, b * ratio
end

local function ExpandRect(bounds, region)
    local l, r, t, b = FrameRectToUI(region)
    if not l then return bounds end
    if not bounds then
        return { l = l, r = r, t = t, b = b }
    end
    if l < bounds.l then bounds.l = l end
    if r > bounds.r then bounds.r = r end
    if t > bounds.t then bounds.t = t end
    if b < bounds.b then bounds.b = b end
    return bounds
end

local function UnitVisualBounds(frame)
    --- Unitframes can draw important parts outside the root frame
    --- (portrait, detached powerbar). The edit overlay should match what the
    --- user actually sees, while drag math keeps the root-frame offset stable.
    local bounds = ExpandRect(nil, frame)
    bounds = ExpandRect(bounds, frame and (frame.hpBar or frame.Health))

    local power = frame and (frame.targetPowerBar or frame.powerBar or frame.Power)
    if power and power.IsShown and power:IsShown() then
        bounds = ExpandRect(bounds, power)
    end

    bounds = ExpandRect(bounds, frame and frame.MSUFPortraitHolder)
    bounds = ExpandRect(bounds, frame and frame.MSUFBorderOverlay)

    if not bounds then return nil end
    return bounds.l, bounds.r, bounds.t, bounds.b
end

local function SyncMoverToFrame(mover, frame, cfg)
    if not frame then return end
    local l, r, t, b
    if cfg and cfg.popupType == "unit" then
        l, r, t, b = UnitVisualBounds(frame)
    else
        l, r, t, b = FrameRectToUI(frame)
    end
    if not (l and r and t and b) then return end
    local w = max(2, round(r - l))
    local h = max(2, round(t - b))
    local x = round(l)
    local y = round(t - UIParent:GetHeight())
    mover:ClearAllPoints()
    mover:SetSize(w, h)
    mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)
end

local function CreateMover(key, cfg)
    local th = T()

    local mover = CreateFrame("Button", nil, moverParent)
    mover:SetSize(100, 30)
    mover:SetFrameStrata("FULLSCREEN")
    mover:SetFrameLevel(cfg.popupType == "castbar" and 340 or 300)
    mover:SetMovable(true); mover:RegisterForDrag("LeftButton")
    if mover.RegisterForClicks then mover:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
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
        if EM2.Focus and EM2.Focus.SetHover then
            EM2.Focus.SetHover(key, nil, nil, { source = "mover" })
        end
    end)
    mover:SetScript("OnLeave", function(self)
        if self._dragging then return end
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        if self._label:IsShown() then self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85) end
        if EM2.Focus and EM2.Focus.ClearHover then
            EM2.Focus.ClearHover("mover")
        end
    end)

    --- Hide label when preview is active (preview frame already shows unit name)
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

    --- Drag ? delegate to Ticker
    mover:SetScript("OnDragStart", function(self)
        if BlockConfigCombatLocked() then return end
        if _G.MSUF_EM2_SetPreviewNudgeTarget then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        self._dragging = true
        self._coordFS:Show()
        if EM2.Focus and EM2.Focus.ClearHover then EM2.Focus.ClearHover("drag") end

        if _G.MSUF_EM_UndoBeforeChange then
            if cfg.popupType == "castbar" then
                _G.MSUF_EM_UndoBeforeChange("castbar", cfg.castbarUnit or key:sub(9))
            else
                _G.MSUF_EM_UndoBeforeChange("unit", key)
            end
        end

        if EM2.Ticker then EM2.Ticker.BeginDrag(self, key, cfg) end
        if EM2.Focus and EM2.Focus.SetSelection then EM2.Focus.SetSelection(key, nil, nil, { source = "drag" }) end
    end)

    mover:SetScript("OnDragStop", function(self)
        self._dragging = false
        self._coordFS:Hide()

        if EM2.Snap and EM2.Snap.HideGuides then EM2.Snap.HideGuides() end

        local moved = false
        if EM2.Ticker then moved = EM2.Ticker.EndDrag() end

        --- Restore hover
        local t = T()
        self._bg:SetColorTexture(t.bgR, t.bgG, t.bgB, 0.55)
        self._brd:SetBackdropBorderColor(t.edgeR, t.edgeG, t.edgeB, 0.60)
        self._label:SetTextColor(t.textR, t.textG, t.textB, 0.85)
        if EM2.Focus and EM2.Focus.SetHover and self:IsMouseOver() then
            EM2.Focus.SetHover(key, nil, nil, { source = "mover", force = true })
        end
    end)

    --- Click keeps the legacy edit-mode behavior: select the item and open
    --- its popup. Focus visuals are handled separately by the popup veil.
    mover:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        if _G.MSUF_EM2_SetPreviewNudgeTarget then _G.MSUF_EM2_SetPreviewNudgeTarget(nil) end
        if EM2.State then EM2.State.SetUnitKey(key) end
        if EM2.HUD then EM2.HUD.RefreshUnitSelector() end
        if EM2.Focus and EM2.Focus.SetSelection then EM2.Focus.SetSelection(key, nil, nil, { source = "mover" }) end
        if EM2.Popups and EM2.Popups.Open then
            EM2.Popups.Open(key, self)
        elseif EM2.Focus and EM2.Focus.NotifyPositionChanged then
            EM2.Focus.NotifyPositionChanged(key)
        end
    end)

    movers[key] = mover
    local frame = cfg.getFrame and cfg.getFrame()
    if frame then SyncMoverToFrame(mover, frame, cfg) end
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
        if f then SyncMoverToFrame(m, f, c); m:Show(); m:UpdateLabelVisibility() else m:Hide() end
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
                SyncMoverToFrame(m, f, c)
                m:Show()
                m:UpdateLabelVisibility()
            elseif m then
                m:Hide()
            end
        end
    end
end

--- MSUF_EM2_Elements.lua

--- MSUF_EM2_Elements.lua
--- Registers all existing MSUF elements with the EM2 Registry.
--- Deferred to PLAYER_LOGIN so unit frames exist.
if not EM2.Registry then return end

local Reg = EM2.Registry

--- Frame resolvers (always live, no cached refs)
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

--- isEnabled: true when the unit frame exists and unit tracking is on
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

local function GetCastbarFrame(unit)
    local frame
    if unit == "player" then
        frame = _G.MSUF_PlayerCastbarPreview or _G.MSUF_PlayerCastbar
    elseif unit == "target" then
        frame = _G.MSUF_TargetCastbarPreview or _G.MSUF_TargetCastbar
    elseif unit == "focus" then
        frame = _G.MSUF_FocusCastbarPreview or _G.MSUF_FocusCastbar
    elseif unit == "boss" then
        frame = _G.MSUF_BossCastbarPreview or _G.MSUF_BossCastbarPreview1 or _G.MSUF_BossCastbar1
    end
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    return frame
end

local function GetCastbarConf()
    if type(_G.MSUF_EnsureDB) == "function" then _G.MSUF_EnsureDB() end
    local db = _G.MSUF_DB
    if type(db) ~= "table" then
        _G.MSUF_DB = {}
        db = _G.MSUF_DB
    end
    db.general = db.general or {}
    return db.general
end

local function CastbarEnabled(unit)
    return function()
        local db = _G.MSUF_DB
        local g = db and db.general or nil
        if not g or g.castbarPlayerPreviewEnabled == false then return false end
        local shouldUse = _G.MSUF_ShouldUseMSUFCastbar
        if type(shouldUse) == "function" and not shouldUse(unit, g) then return false end
        if type(shouldUse) ~= "function" then
            if unit == "player" and g.enablePlayerCastbar == false then return false end
            if unit == "target" and g.enableTargetCastbar == false then return false end
            if unit == "focus" and g.enableFocusCastbar == false then return false end
            if unit == "boss" and g.enableBossCastbar == false then return false end
        end
        return GetCastbarFrame(unit) ~= nil
    end
end

local function RegisterCastbarMover(unit, label, order)
    Reg.Register({
        key         = "castbar_" .. unit,
        label       = label,
        order       = order,
        popupType   = "castbar",
        canResize   = false,
        canNudge    = true,
        castbarUnit = unit,
        getFrame    = function() return GetCastbarFrame(unit) end,
        getConf     = GetCastbarConf,
        isEnabled   = CastbarEnabled(unit),
    })
end

--- Registration (deferred)
local function RegisterAll()
    --- Core unit frames
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

    --- Boss: only boss1 gets a mover. All boss frames share one config ("boss").
    --- Moving boss1 writes offsetX/Y ? ApplySettingsForKey("boss") repositions all.
    --- Boss2-5 auto-position via (index-1)*spacing in PositionUnitFrame.
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

    RegisterCastbarMover("player", "Player Castbar", 110)
    RegisterCastbarMover("target", "Target Castbar", 111)
    RegisterCastbarMover("focus", "Focus Castbar", 112)
    RegisterCastbarMover("boss", "Boss Castbar", 113)

    --- Future Phase 2 registrations:
    --- Auras3 groups (per-unit)
    --- Class Power bar
    --- These will register when their respective modules load.
end

--- Deferred init: register once frames are ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent("PLAYER_LOGIN")

    --- Delay one frame to ensure all unit frames are created
    C_Timer.After(0, function()
        RegisterAll()
    end)
end)

--- MSUF_EM2_Compat.lua

--- MSUF_EM2_Compat.lua
--- Legacy global stubs so external files (30+) continue to work after
--- MSUF_EditMode.lua is deleted. Every function listed here was exported
--- by the old EditMode and is called from at least one other file.
--- --- Edit namespace (old code references _G.MSUF_Edit.*) ---
_G.MSUF_Edit = _G.MSUF_Edit or {}
local Edit = _G.MSUF_Edit
Edit.Popups = Edit.Popups or {}
Edit.Flow   = Edit.Flow   or {}
Edit.Util   = Edit.Util   or {}
Edit.UI     = Edit.UI     or {}

--- --- MSUF_EditState table (rawget'd by A2, Util, etc.) ---
if not _G.MSUF_EditState then
    _G.MSUF_EditState = { active = false, unitKey = nil, popupOpen = false }
end

--- --- MSUF_IsInEditMode ---
_G.MSUF_IsInEditMode = function()
    if EM2.State then return EM2.State.IsActive() end
    return _G.MSUF_UnitEditModeActive == true
end

--- --- MSUF_GetAnchorFrame ---
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

--- --- MSUF_GetCurrentGridStep ---
_G.MSUF_GetCurrentGridStep = function()
    if EM2.Grid then return EM2.Grid.GetGridStep() end
    local db = _G.MSUF_DB
    return (db and db.general and db.general.editModeGridStep) or 20
end

--- --- MSUF_MakeBlizzardOptionsMovable ---
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

--- --- MSUF_ResetCurrentEditUnit ---
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

--- --- MSUF_UpdateEditModeInfo (called by Castbars/main) ---
_G.MSUF_UpdateEditModeInfo = function()
    --- No-op: EM2 HUD handles display. Old GridFrame.infoText is gone.
end

--- --- MSUF_UpdateCastbarEditInfo ---
_G.MSUF_UpdateCastbarEditInfo = function() end

--- --- MSUF_UpdateGridOverlay ---
_G.MSUF_UpdateGridOverlay = function()
    if EM2.State and EM2.State.IsActive() then
        if EM2.Grid then EM2.Grid.Show() end
    else
        if EM2.Grid then EM2.Grid.Hide() end
    end
end

--- --- MSUF_UpdateEditModeVisuals ---
_G.MSUF_UpdateEditModeVisuals = function()
    _G.MSUF_UpdateGridOverlay()
end

--- --- MSUF_CreateGridFrame ---
_G.MSUF_CreateGridFrame = function()
    if EM2.Grid then EM2.Grid.Show() end
end

--- --- MSUF_OpenPositionPopup (called from MidnightSimpleUnitFrames.lua OnMouseUp) ---
_G.MSUF_OpenPositionPopup = function(unit, parent)
    if EM2.Popups then EM2.Popups.Open(unit, parent) end
end

--- --- MSUF_OpenCastbarPositionPopup ---
_G.MSUF_OpenCastbarPositionPopup = function(unit, parent)
    if EM2.Popups then
        EM2.Popups.Open("castbar_" .. tostring(unit or ""), parent)
    elseif EM2.CastPopup then
        EM2.CastPopup.Open(unit, parent)
    end
end

--- --- MSUF_OpenAuras3PositionPopup ---
_G.MSUF_OpenAuras3PositionPopup = function(unit, parent)
    if EM2.Popups then
        EM2.Popups.Open("aura_" .. tostring(unit or ""), parent)
    elseif EM2.AuraPopup then
        EM2.AuraPopup.Open(unit, parent)
    end
end

--- --- MSUF_SyncUnitPositionPopup ---
_G.MSUF_SyncUnitPositionPopup = function(unit)
    if EM2.UnitPopup and EM2.UnitPopup.Sync then EM2.UnitPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_UNIT_POPUP", unit)
end

--- --- MSUF_SyncCastbarPositionPopup ---
_G.MSUF_SyncCastbarPositionPopup = function(unit)
    if EM2.CastPopup and EM2.CastPopup.Sync then EM2.CastPopup.Sync() end
    RefreshUFPreview("EM2_SYNC_CASTBAR_POPUP", unit)
end

--- --- MSUF_SyncAuras3PositionPopup ---
_G.MSUF_SyncAuras3PositionPopup = function(unit)
    if EM2.AuraPopup and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
end

--- --- MSUF_SetMSUFEditModeDirect (THE primary entry point) ---
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

--- --- MSUF_SetMSUFEditModeFromBlizzard ---
_G.MSUF_SetMSUFEditModeFromBlizzard = function(active)
    _G.MSUF_SetMSUFEditModeDirect(active, nil)
end

--- --- Preview System ---
--- One global flag: MSUF_PreviewTestMode. Mirrors MSUF_BossTestMode exactly.
--- The core's visibility driver (line 2000) checks this flag to force-show.
--- The core's UpdateSimpleUnitFrame (line 4017) already applies EditPrev data.
--- Zero hooks, zero timers, zero pipeline fighting.
_G.MSUF_UnitPreviewActive = false
_G.MSUF_PreviewTestMode = false

local PREVIEW_UNITS = { "target", "focus", "focustarget", "targettarget", "pet" }
local CASTBAR_TEST_FUNCS = {
    "MSUF_SetPlayerCastbarTestMode",
    "MSUF_SetTargetCastbarTestMode",
    "MSUF_SetFocusCastbarTestMode",
    "MSUF_SetBossCastbarTestMode",
}
local CASTBAR_REFRESH_FUNCS = {
    "MSUF_UpdateCastbarVisuals",
    "MSUF_UpdatePlayerCastbarPreview",
    "MSUF_UpdateTargetCastbarPreview",
    "MSUF_UpdateFocusCastbarPreview",
}

local function GetPreviewFrame(unitKey)
    return _G["MSUF_" .. unitKey]
        or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unitKey])
end

local function ForPreviewFrames(fn)
    for _, unitKey in ipairs(PREVIEW_UNITS) do
        local frame = GetPreviewFrame(unitKey)
        if frame then fn(frame, unitKey) end
    end
end

_G.MSUF_EM2_ReforcePreviewFrames = function()
    if not _G.MSUF_PreviewTestMode then return end
    if IsConfigCombatLocked() then return end
    ForPreviewFrames(function(frame)
        if frame.ForceUpdate then frame:ForceUpdate("EM2_PREVIEW") end
        frame:Show()
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.EnableMouse then frame:EnableMouse(true) end
    end)
    if EM2.Movers and EM2.Movers.SyncAll then
        EM2.Movers.SyncAll()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if _G.MSUF_PreviewTestMode and EM2.Movers and EM2.Movers.SyncAll then
                    EM2.Movers.SyncAll()
                end
            end)
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

    --- Set preview flag (core visibility driver reads this)
    _G.MSUF_PreviewTestMode = want

    --- 1) Boss: existing system
    _G.MSUF_BossTestMode = want
    if _G.MSUF_SyncBossUnitframePreviewWithUnitEdit then
        _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
    end

    --- 2) Non-player: refresh visibility drivers (reads MSUF_PreviewTestMode),
    --- then update each frame (pipeline calls EditPrev for unitless frames)
    if _G.MSUF_RefreshAllUnitVisibilityDrivers then
        _G.MSUF_RefreshAllUnitVisibilityDrivers(want)
    end

    ForPreviewFrames(function(frame)
        if frame.ForceUpdate then frame:ForceUpdate("EM2_PREVIEW") end
        if want then
            frame:Show()
            if frame.SetAlpha then frame:SetAlpha(1) end
            if frame.EnableMouse then frame:EnableMouse(true) end
        end
    end)

    --- 3) Castbars
    if _G.MSUF_SyncCastbarEditModeWithUnitEdit then
        _G.MSUF_SyncCastbarEditModeWithUnitEdit()
    end
    for _, fn in ipairs(CASTBAR_TEST_FUNCS) do
        local f = _G[fn]; if type(f) == "function" then f(want, true) end
    end

    --- 4) Aura refresh
    if _G.MSUF_Auras3_RefreshAll then
        _G.MSUF_Auras3_RefreshAll()
    end

    --- 5) Sync movers
    if EM2.Movers and EM2.Movers.SyncAll then
        C_Timer.After(0.08, function()
            if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        end)
    end
end

--- --- Auto-reforce hooks ---
--- ANY visual update function can overwrite preview text/bars/colors.
--- Hook every entry point to schedule ReforcePreviewFrames after settle.
--- All hooks gate on MSUF_PreviewTestMode ? zero combat overhead.
do
    local _hooksInstalled = false
    local PIPELINE_REFORCE_HOOKS = {
        --- Font/color/bar/castbar visual entry points that can overwrite preview state.
        "MSUF_UpdateAllFonts",
        "MSUF_UpdateAllFonts_Immediate",
        "MSUF_RefreshAllIdentityColors",
        "MSUF_RefreshAllPowerTextColors",
        "MSUF_UpdateAllBarTextures",
        "MSUF_UpdateAllBarTextures_Immediate",
        "MSUF_ApplyBarOutlineThickness_All",
        "MSUF_ApplyPowerBarBorder_All",
        "MSUF_ApplyReverseFillBars",
        "MSUF_UpdateCastbarVisuals",
        "MSUF_UpdateCastbarVisuals_Immediate",
        "MSUF_UpdateCastbarTextures",
        "MSUF_UpdateCastbarTextures_Immediate",
        "MSUF_RefreshDispelOutlineStates",
        "MSUF_ApplyAllAlpha",
    }

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
        _hooksInstalled = true

        for _, name in ipairs(PIPELINE_REFORCE_HOOKS) do
            SafeHook(name, 0.05)
        end
    end

    local _origSync = _G.MSUF_SyncAllUnitPreviews
    local function SyncAllUnitPreviewsWithPipelineHooks(...)
        InstallPipelineHooks()
        return _origSync(...)
    end
    _G.MSUF_SyncAllUnitPreviews = SyncAllUnitPreviewsWithPipelineHooks
end

--- --- MSUF_SyncCastbarEditModeWithUnitEdit (castbar preview sync) ---
_G.MSUF_SyncCastbarEditModeWithUnitEdit = function()
    local db = _G.MSUF_DB
    if not db then return end
    db.general = db.general or {}
    local g = db.general
    local active = EM2.State and EM2.State.IsActive()
    g.castbarPlayerPreviewEnabled = active and true or false

    for _, name in ipairs(CASTBAR_REFRESH_FUNCS) do
        local fn = _G[name]
        if type(fn) == "function" then fn() end
    end
    if not (_G.MSUF_InCombat == true or (InCombatLockdown and InCombatLockdown()))
        and _G.MSUF_UpdateBossCastbarPreview
    then
        _G.MSUF_UpdateBossCastbarPreview()
    end
end

--- --- MSUF_SyncBossUnitframePreviewWithUnitEdit ---
_G.MSUF_SyncBossUnitframePreviewWithUnitEdit = _G.MSUF_SyncBossUnitframePreviewWithUnitEdit or function()
    --- Provided by MidnightSimpleUnitFrames.lua; stub if not yet available
end

--- --- Edit.Flow.Exit ---
Edit.Flow.Exit = function(source, opts)
    if EM2.State then EM2.State.Exit(source or "flow") end
end

--- --- Edit.Transitions ---
Edit.Transitions = Edit.Transitions or {}
Edit.Transitions.SetMSUFEditModeDirect = _G.MSUF_SetMSUFEditModeDirect

--- --- AnyEditMode listeners (registration handled in State.lua) ---

--- --- Castbar anchor toggle (detach/attach to unitframe) ---
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

    --- If detaching, save current castbar center as UIParent offset
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

    --- Re-anchor
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
