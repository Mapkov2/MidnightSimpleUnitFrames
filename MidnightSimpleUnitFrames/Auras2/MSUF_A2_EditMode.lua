-- MSUF_A2_EditMode.lua — EditMode + Preview (consolidated)

-- MSUF_A2_EditMode.lua

-- MSUF_A2_EditMode.lua  Auras 3.0 Edit Mode Integration
--
-- Responsibilities:
--   1. Per-unit draggable movers for Buffs, Debuffs, Private aura groups
--   2. Drag-to-position with offset persistence to perUnit DB
--   3. Mover show/hide on edit mode transitions
--   4. Boss-linked editing (bossEditTogether)
--   5. Integration with preview tickers (stack cycling, cooldown preview)
--
-- NOT in this file: preview icon rendering (Icons.lua / Preview.lua),
-- aura collection (Collect.lua), flush scheduling (Render.lua)

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local type, tostring = type, tostring
local pairs = pairs
local math_max = math.max
local CreateFrame, GetTime = CreateFrame, GetTime
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

-- Cross-file references from MSUF_A2_Core.lua (exported to _G there).
local A2_PREVIEW_BUFF_TEXTURES = _G.MSUF_A2_PREVIEW_BUFF_TEXTURES or {}
local A2_PREVIEW_DEBUFF_TEXTURES = _G.MSUF_A2_PREVIEW_DEBUFF_TEXTURES or {}
local A2_PREVIEW_BUFF_TEX_N = _G.MSUF_A2_PREVIEW_BUFF_TEX_N or 1
local A2_PREVIEW_DEBUFF_TEX_N = _G.MSUF_A2_PREVIEW_DEBUFF_TEX_N or 1
local A2_PREVIEW_CD_DURATIONS = _G.MSUF_A2_PREVIEW_CD_DURATIONS or { 12 }
local A2_PREVIEW_CD_DUR_N = _G.MSUF_A2_PREVIEW_CD_DUR_N or 1

local function _A2E_ApplyMouseState(icon, wantMS)
    local fn = _G.MSUF_A2_ApplyMouseState
    if fn then fn(icon, wantMS) end
end
local function _A2E_ResolveTextConfig(icon, unit, shared, gen)
    local fn = _G.MSUF_A2_ResolveTextConfig
    if fn then fn(icon, unit, shared, gen) end
end

if ns.__MSUF_A2_EDITMODE_LOADED then return end
ns.__MSUF_A2_EDITMODE_LOADED = true

API.EditMode = (type(API.EditMode) == "table") and API.EditMode or {}
local EM = API.EditMode

-- Locals

local type = type
local pairs = pairs
local floor = math.floor
local CreateFrame = CreateFrame
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local UIParent = UIParent

local function FastCall(fn, ...)
    if fn == nil then return false end
    return true, fn(...)
end

-- DB access

local function EnsureDB()
    local DB = API.DB
    if DB and DB.Ensure then return DB.Ensure() end
    return nil, nil
end
local function GetAuras2DB()
    local api = ns and ns.MSUF_Auras2
    if api and api.GetDB then return api.GetDB() end
    if not _G.MSUF_DB then if type(EnsureDB) == "function" then EnsureDB() end end
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    return a2, a2 and a2.shared
end

-- Edit Mode state detection (use Render's cached check if available)

local function IsEditModeActive()
    if API.IsEditModeActive then return API.IsEditModeActive() end
    local st = rawget(_G, "MSUF_EditState")
    if st and st.active == true then return true end
    if rawget(_G, "MSUF_UnitEditModeActive") == true then return true end
    return false
end

-- Per-unit state (shared with Render)

local function GetAurasByUnit()
    local st = API.state
    return (st) and st.aurasByUnit or nil
end

local _IS_BOSS = { boss1=true, boss2=true, boss3=true, boss4=true, boss5=true }

-- Offset DB keys per mover kind

local MOVER_KEYS = {
    buff    = { x = "buffGroupOffsetX",   y = "buffGroupOffsetY"   },
    buffs   = { x = "buffGroupOffsetX",   y = "buffGroupOffsetY"   },
    debuff  = { x = "debuffGroupOffsetX", y = "debuffGroupOffsetY" },
    debuffs = { x = "debuffGroupOffsetX", y = "debuffGroupOffsetY" },
    private = { x = "privateOffsetX",     y = "privateOffsetY"     },
}

local function GetMoverKeyPair(kind)
    local k = (type(kind) == "string") and kind:lower() or "private"
    local pair = MOVER_KEYS[k] or MOVER_KEYS.private
    return pair.x, pair.y
end

local function ReadOffset(unitKey, shared, kind)
    local kx, ky = GetMoverKeyPair(kind)

    -- Check perUnit override first
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    local pu = a2 and a2.perUnit and a2.perUnit[unitKey]
    local lay = pu and pu.overrideLayout == true and pu.layout

    local ox, oy
    if lay then
        if type(lay[kx]) == "number" then ox = lay[kx] end
        if type(lay[ky]) == "number" then oy = lay[ky] end
    end

    -- Fallback to shared only when perUnit didn't provide the value
    if ox == nil and shared and type(shared[kx]) == "number" then ox = shared[kx] end
    if oy == nil and shared and type(shared[ky]) == "number" then oy = shared[ky] end

    return ox or 0, oy or 0
end

local function WriteOffset(a2, unitKey, kind, newX, newY)
    if not a2 or not unitKey or not kind then return end
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local u = a2.perUnit[unitKey]
    if type(u) ~= "table" then
        u = {}
        a2.perUnit[unitKey] = u
    end

    u.overrideLayout = true
    u.layout = (type(u.layout) == "table") and u.layout or {}

    local kx, ky = GetMoverKeyPair(kind)
    u.layout[kx] = newX
    u.layout[ky] = newY
end

-- Mover creation

local function GetCursorScaled()
    local scale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    return cx / scale, cy / scale
end

local function SetLegacyPopupOpen(open)
    local EM2 = rawget(_G, "MSUF_EM2")
    local State = EM2 and EM2.State
    if State and type(State.SetPopupOpen) == "function" then
        State.SetPopupOpen(open == true)
        return
    end

    local st = rawget(_G, "MSUF_EditState")
    if st then st.popupOpen = open == true end
end

local function IsPopupOpen(popup)
    return popup and type(popup.IsOpen) == "function" and popup.IsOpen() == true
end

local function IsAuraPopupOpen()
    local EM2 = rawget(_G, "MSUF_EM2")
    if IsPopupOpen(EM2 and EM2.AuraPopup) then return true end

    -- Legacy popup name kept for older callers/builds.
    local ap = rawget(_G, "MSUF_Auras2PositionPopup")
    return ap and ap.IsShown and ap:IsShown() or false
end

local function IsLiveNonAuraPopupOpen()
    local EM2 = rawget(_G, "MSUF_EM2")
    if IsPopupOpen(EM2 and EM2.UnitPopup) then return true end
    if IsPopupOpen(EM2 and EM2.CastPopup) then return true end

    local gfOpen = rawget(_G, "MSUF_EM2_GFPopupIsOpen")
    if type(gfOpen) == "function" and gfOpen() == true then return true end

    return false
end

local function IsAnyPopupOpen()
    if IsLiveNonAuraPopupOpen() then return true end
    if IsAuraPopupOpen() then
        SetLegacyPopupOpen(false)
        return false
    end

    local st = rawget(_G, "MSUF_EditState")
    if not st or not st.popupOpen then return false end

    -- If EM2 can report live popup state and no popup is actually open, this
    -- flag is stale (for example after closing a unit popup with its X button).
    local EM2 = rawget(_G, "MSUF_EM2")
    local Popups = EM2 and EM2.Popups
    if Popups and type(Popups.IsAnyOpen) == "function" and Popups.IsAnyOpen() ~= true then
        SetLegacyPopupOpen(false)
        return false
    end

    return true
end

local function CloseNonAuraEditPopups()
    local EM2 = rawget(_G, "MSUF_EM2")
    local closed = false

    local function CloseIfOpen(popup)
        if popup and type(popup.IsOpen) == "function" and popup.IsOpen() == true then
            if type(popup.Close) == "function" then
                popup.Close()
                return true
            end
        end
        return false
    end

    if EM2 then
        closed = CloseIfOpen(EM2.UnitPopup) or closed
        closed = CloseIfOpen(EM2.CastPopup) or closed
    end

    local gfOpen = rawget(_G, "MSUF_EM2_GFPopupIsOpen")
    local hideGF = rawget(_G, "MSUF_EM2_HideGFPopup")
    if type(gfOpen) == "function" and gfOpen() == true and type(hideGF) == "function" then
        hideGF("party")
        hideGF("raid")
        hideGF("mythicraid")
        closed = true
    end

    -- The aura popup itself must not block aura dragging. Keep it open so its
    -- fields can sync while dragging, but clear the legacy blocking bit.
    if closed or IsAuraPopupOpen() or (not IsLiveNonAuraPopupOpen()) then
        SetLegacyPopupOpen(false)
    end
end

-- Kind-specific visuals
local MOVER_COLORS = {
    buff    = { hr = 0.18, hg = 0.80, hb = 0.30, icon = "Interface\\Icons\\Spell_Holy_WordFortitude"     },
    debuff  = { hr = 0.90, hg = 0.20, hb = 0.20, icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain"  },
    private = { hr = 0.20, hg = 0.65, hb = 1.00, icon = "Interface\\Icons\\Ability_Creature_Cursed_03"   },
}

local function CreateMover(entry, unitKey, kind, labelText)
    if not entry or not unitKey or not kind then return nil end

    local field
    if kind == "buff" then field = "editMoverBuff"
    elseif kind == "debuff" then field = "editMoverDebuff"
    else field = "editMoverPrivate" end

    -- Already exists
    if entry[field] then return entry[field] end

    local safeName = tostring(unitKey):gsub("%W", "")
    local moverName = "MSUF_A2_" .. safeName .. "_Mover_" .. tostring(kind)

    local mover = CreateFrame("Frame", moverName, UIParent, "BackdropTemplate")
    mover:SetFrameStrata("FULLSCREEN")
    mover:SetFrameLevel(500)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)

    -- QoL: expand hit rect so header label is easy to grab
    if mover.SetHitRectInsets then
        mover:SetHitRectInsets(-2, -2, -22, -2)
    end

    mover:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mover:SetBackdropColor(0.20, 0.65, 1.00, 0.12)
    mover:SetBackdropBorderColor(0.20, 0.65, 1.00, 0.55)

    --  Header bar + label
    local style = MOVER_COLORS[kind] or MOVER_COLORS.private
    local headerH = 18

    local header = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    header:SetPoint("TOPLEFT", mover, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -2, -2)
    header:SetHeight(headerH)
    header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    header:SetBackdropColor(style.hr, style.hg, style.hb, 0.22)
    mover._msufHeader = header

    -- Route header mouse events to mover (drag QoL)
    header:EnableMouse(true)
    header:SetScript("OnMouseDown", function(h, btn)
        local p = h:GetParent()
        local fn = p and p:GetScript("OnMouseDown")
        if fn then fn(p, btn) end
    end)
    header:SetScript("OnMouseUp", function(h, btn)
        local p = h:GetParent()
        local fn = p and p:GetScript("OnMouseUp")
        if fn then fn(p, btn) end
    end)

    -- Icon
    local ico = header:CreateTexture(nil, "OVERLAY")
    ico:SetSize(14, 14)
    ico:SetPoint("LEFT", header, "LEFT", 6, 0)
    ico:SetTexture(style.icon)
    ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Label
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", ico, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText or (tostring(unitKey) .. " Auras"))
    label:SetTextColor(0.95, 0.95, 0.95, 0.92)
    mover._msufLabel = label

    mover:Hide()

    -- Mover metadata
    mover._msufAuraEntry    = entry
    mover._msufAuraUnitKey  = unitKey
    mover._msufA2MoverKind  = kind

    --  Drag logic

    local function ApplyDragDelta(self, dx, dy)
        if InCombatLockdown() then return end

        local a2, shared = GetAuras2DB()
        if not a2 or not shared then return end

        local key = self._msufAuraUnitKey
        local mk  = self._msufA2MoverKind or "buff"

        local startX = self._msufDragStartOffsetX or 0
        local startY = self._msufDragStartOffsetY or 0

        local newX = floor(startX + dx + 0.5)
        local newY = floor(startY + dy + 0.5)

        -- Clamp to safe range
        if newX < -2000 then newX = -2000 end
        if newX >  2000 then newX =  2000 end
        if newY < -2000 then newY = -2000 end
        if newY >  2000 then newY =  2000 end

        -- Write to DB
        local function ApplyToUnit(unitK)
            WriteOffset(a2, unitK, mk, newX, newY)
            -- Immediate anchor refresh for instant drag feedback
            if API.UpdateUnitAnchor then API.UpdateUnitAnchor(unitK) end
        end

        -- Boss units: edit together when enabled
        if shared.bossEditTogether == true and _G.MSUF_IsBossUnitToken and _G.MSUF_IsBossUnitToken(key) then
            for i = 1, 5 do ApplyToUnit("boss" .. i) end
        else
            ApplyToUnit(key)
        end

        -- Sync position popup if open
        -- Perf: cache global lookup + avoid repeated type() on the global.
        local SyncPopup = _G.MSUF_SyncAuras2PositionPopup
        if type(SyncPopup) == "function" then
            SyncPopup(key)
        end
    end

    -- OnMouseDown: start drag + set active nudge group for arrow-key nudging
    mover:SetScript("OnMouseDown", function(self, button)
        -- Always track which group was last clicked for arrow-key nudging,
        -- even if drag is blocked (popup open, combat, etc.)
        _G.MSUF_EM2_ActiveAuraGroup = kind
        _G.MSUF_EM2_ActiveAuraUnit  = self._msufAuraUnitKey or unitKey
        local pf = _G.MSUF_Auras2PositionPopup
        if pf then
            pf._msufActiveNudgeGroup = kind
        end

        if button ~= "LeftButton" then return end
        if InCombatLockdown() then return end
        CloseNonAuraEditPopups()
        if IsAnyPopupOpen() then return end

        -- Undo: capture aura state BEFORE drag writes to DB
        if not _G.MSUF__UndoRestoring then
            local bc = _G.MSUF_EM_UndoBeforeChange
            if type(bc) == "function" then
                bc("aura", self._msufAuraUnitKey or unitKey)
            end
        end

        local _, shared = GetAuras2DB()
        if not shared then return end

        local key = self._msufAuraUnitKey
        local mk  = self._msufA2MoverKind or "buff"

        local startX, startY = ReadOffset(key, shared, mk)
        self._msufDragStartOffsetX = startX
        self._msufDragStartOffsetY = startY

        local cx, cy = GetCursorScaled()
        self._msufDragStartCursorX = cx
        self._msufDragStartCursorY = cy
        self._msufDragMoved = false
        self._msufDragging = true

        local mL = self:GetLeft() or 0
        local mR = self:GetRight() or 0
        local mT = self:GetTop() or 0
        local mB = self:GetBottom() or 0
        self._msufSnapStartCX = (mL + mR) * 0.5
        self._msufSnapStartCY = (mT + mB) * 0.5
        self._msufSnapHW = (mR - mL) * 0.5
        self._msufSnapHH = (mT - mB) * 0.5

        if not self._msufOnUpdate then
            self._msufOnUpdate = function(me)
                local mx, my = GetCursorScaled()
                local ddx = mx - (me._msufDragStartCursorX or mx)
                local ddy = my - (me._msufDragStartCursorY or my)
                if not me._msufDragMoved then
                    if (ddx * ddx + ddy * ddy) >= 9 then  -- 3px threshold
                        me._msufDragMoved = true
                    else
                        return
                    end
                end
                local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
                if Snap and Snap.IsEnabled and Snap.IsEnabled() and Snap.Apply then
                    Snap.HideGuides()
                    local rawCX = (me._msufSnapStartCX or 0) + ddx
                    local rawCY = (me._msufSnapStartCY or 0) + ddy
                    local hw = me._msufSnapHW or 0
                    local hh = me._msufSnapHH or 0
                    local sCX, sCY = Snap.Apply(rawCX, rawCY, hw, hh, moverName)
                    ddx = sCX - (me._msufSnapStartCX or 0)
                    ddy = sCY - (me._msufSnapStartCY or 0)
                end
                ApplyDragDelta(me, ddx, ddy)
            end
        end
        self:SetScript("OnUpdate", self._msufOnUpdate)
    end)

    -- OnMouseUp: stop drag or open popup
    mover:SetScript("OnMouseUp", function(self, button)
        self._msufDragging = false
        if self:GetScript("OnUpdate") then
            self:SetScript("OnUpdate", nil)
            local Snap = _G.MSUF_EM2 and _G.MSUF_EM2.Snap
            if Snap and Snap.HideGuides then Snap.HideGuides() end
            if self._msufDragMoved then
                self._msufDragMoved = false
                -- Invalidate DB so config cache updates with new offsets
                if API.InvalidateDB then API.InvalidateDB() end
                return
            end
        end

        -- Click without drag: open position popup
        -- Set nudge group BEFORE opening popup so arrow keys target the correct group.
        _G.MSUF_EM2_ActiveAuraGroup = self._msufA2MoverKind or kind
        _G.MSUF_EM2_ActiveAuraUnit  = self._msufAuraUnitKey or unitKey
        local pf = _G.MSUF_Auras2PositionPopup
        if pf then
            pf._msufActiveNudgeGroup = self._msufA2MoverKind or kind
        end

        local key = self._msufAuraUnitKey
        if _G.MSUF_OpenAuras2PositionPopup then
            _G.MSUF_OpenAuras2PositionPopup(key, self)
        end

        -- Popup may have been created lazily — set group on newly created popup too
        if not pf then
            pf = _G.MSUF_Auras2PositionPopup
            if pf then
                pf._msufActiveNudgeGroup = self._msufA2MoverKind or kind
            end
        end
    end)

    entry[field] = mover
    return mover
end

-- Ensure all three movers exist for a unit

local function UnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus"  then return "Focus"  end
    local n = (_G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unit))
    if n then return "Boss " .. n end
    return tostring(unit)
end

function EM.EnsureMovers(entry, unit, shared, iconSize, spacing)
    if not entry or not unit then return end
    -- Skip lightweight child frames that do not support aura editing.
    if unit == "pet" or unit == "targettarget" or unit == "focustarget" then return end

    local base = UnitLabel(unit)
    CreateMover(entry, unit, "buff",    base .. " Buffs")
    CreateMover(entry, unit, "debuff",  base .. " Debuffs")
    if unit == "player" or unit == "target" then
        CreateMover(entry, unit, "private", base .. " Private")
    end
    -- Mover positioning is handled by Render's UpdateAnchor after containers are placed
end

-- Mover positioning (mirrors container anchors)

function EM.PositionMovers(entry, shared, iconSize, spacing)
    if not entry then return end

    iconSize = iconSize or (shared and shared.iconSize) or 26
    spacing  = spacing  or (shared and shared.spacing)  or 2

    local perRow   = (shared and shared.perRow) or 12
    local maxBuffs = (shared and (shared.maxBuffs or shared.maxIcons)) or 12
    local maxDebuffs = (shared and (shared.maxDebuffs or shared.maxIcons)) or 12

    local step = iconSize + spacing
    local buffCols  = (maxBuffs  < perRow) and maxBuffs  or perRow
    local debuffCols = (maxDebuffs < perRow) and maxDebuffs or perRow

    local buffW  = buffCols  * step
    local debuffW = debuffCols * step
    local privMax = (shared and tonumber(shared.privateAuraMaxPlayer)) or 4
    if privMax < 1 then privMax = 1 elseif privMax > 12 then privMax = 12 end
    local privW   = privMax * step

    local rowH = iconSize
    local headerH = 20

    -- Mirror mover to its container's anchor
    local function MirrorToContainer(mover, container, w, h)
        if not mover then return end
        mover:ClearAllPoints()
        if container then
            local n = container:GetNumPoints()
            if n and n > 0 then
                local p, rel, rp, ox, oy = container:GetPoint(1)
                if p and rel then
                    mover:SetPoint(p, rel, rp, ox or 0, oy or 0)
                else
                    mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
                end
            else
                mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
            end
        else
            mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", 0, 0)
        end
        if w and h then mover:SetSize(w, h) end
    end

    local function SetMover(mover, w, h, ox, oy)
        if not mover then return end
        mover:ClearAllPoints()
        mover:SetPoint("BOTTOMLEFT", entry.anchor, "BOTTOMLEFT", ox or 0, oy or 0)
        if w and h then mover:SetSize(w, h) end
    end

    MirrorToContainer(entry.editMoverBuff, entry.buffs, buffW, rowH + headerH)
    MirrorToContainer(entry.editMoverDebuff, entry.debuffs, debuffW, rowH + headerH)

    -- Private: position relative to anchor with offset
    if entry.editMoverPrivate and entry.private then
        MirrorToContainer(entry.editMoverPrivate, entry.private, privW, rowH + headerH)
    end
end

-- Show / Hide movers

function EM.ShowMovers(entry)
    if not entry then return end
    -- Skip lightweight child frames that do not support aura editing.
    local u = entry.unit
    if u == "pet" or u == "targettarget" or u == "focustarget" then return end
    if entry.editMoverBuff then
        entry.editMoverBuff:Show()
    end
    if entry.editMoverDebuff then
        entry.editMoverDebuff:Show()
    end
    if entry.editMoverPrivate and u == "player" then
        entry.editMoverPrivate:Show()
    end
end

function EM.HideMovers(entry)
    if not entry then return end
    if entry.editMoverBuff      then entry.editMoverBuff:Hide()      end
    if entry.editMoverDebuff    then entry.editMoverDebuff:Hide()    end
    if entry.editMoverPrivate   then entry.editMoverPrivate:Hide()   end
    if entry.editMoverReminder  then entry.editMoverReminder:Hide()  end
end

function EM.AnyMoverExists(entry)
    return entry and (entry.editMoverBuff or entry.editMoverDebuff or entry.editMoverPrivate or entry.editMoverReminder) and true or false
end

-- Hide all movers across all units

function EM.HideAllMovers()
    local aby = GetAurasByUnit()
    if not aby then return end
    for _, entry in pairs(aby) do
        if entry then EM.HideMovers(entry) end
    end
end

function EM.ShowAllMovers()
    local aby = GetAurasByUnit()
    if not aby then return end
    local _, shared = GetAuras2DB()
    -- Respect the toggle: if showInEditMode is off, don't show movers
    if shared and shared.showInEditMode == false then return end
    for _, entry in pairs(aby) do
        if entry and EM.AnyMoverExists(entry) then
            EM.ShowMovers(entry)
        end
    end
end

-- Edit Mode transition handler
-- (Called by the AnyEditModeListener registered below)

local function OnEditModeChanged(active)
    if active then
        -- Movers are created lazily by Render's hook calling EM.EnsureMovers.
        -- Just ensure preview tickers are started.
        if API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
        if API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end

        -- Schedule a full refresh so all units get their movers
        if API.MarkAllDirty then API.MarkAllDirty(0) end
    else
        -- Hide all movers (incl. reminder mover)
        EM.HideAllMovers()
        _G.MSUF_EM2_ActiveAuraGroup = nil
        _G.MSUF_EM2_ActiveAuraUnit  = nil

        -- Close reminder position popup if open
        local Reminder = API.Reminder
        if Reminder and Reminder.HidePopup then Reminder.HidePopup() end

        -- Clear previews
        if API.ClearAllPreviews then API.ClearAllPreviews() end

        -- Stop preview tickers
        if API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
        if API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end

        -- Unregister cooldown text for preview icons
        local CT = API.CooldownText
        if CT and CT.UnregisterAll then CT.UnregisterAll() end

        -- Bump configGen so UpdateAnchor re-runs with final saved offsets
        -- (MarkAllDirty alone skips re-anchor when gen is unchanged)
        if API.InvalidateDB then API.InvalidateDB() elseif API.MarkAllDirty then API.MarkAllDirty(0) end
    end
end

EM.OnEditModeChanged = OnEditModeChanged

-- Backward compatibility exports
-- (Old Render.lua exposed these globally; some code may reference them)

-- Global offsets writer (used by position popup)
_G.MSUF_A2_WriteMoverOffsets = _G.MSUF_A2_WriteMoverOffsets or function(a2, unitKey, kind, newX, newY)
    return WriteOffset(a2, unitKey, kind, newX, newY)
end

-- Global offset reader
_G.MSUF_A2_GetMoverStartOffsets = _G.MSUF_A2_GetMoverStartOffsets or function(unitKey, shared, kind)
    return ReadOffset(unitKey, shared, kind)
end

-- Global mover key pair
_G.MSUF_A2_GetMoverKeyPair = _G.MSUF_A2_GetMoverKeyPair or function(kind)
    return GetMoverKeyPair(kind)
end

-- Register for Edit Mode notifications

local _registered = false

local function TryRegister()
    if _registered then return end
    local reg = _G.MSUF_RegisterAnyEditModeListener
    if type(reg) == "function" then
        reg(OnEditModeChanged)
        _registered = true

        -- Sync on registration (covers /reload while edit mode active)
        if IsEditModeActive() then
            OnEditModeChanged(true)
        end
    end
end

-- Try immediately
TryRegister()

-- Retry after a short delay (load order: EditMode.lua may not be loaded yet)
if not _registered then
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            TryRegister()
            if not _registered then
                C_Timer.After(0.5, TryRegister)
            end
        end)
    end
end

-- ── Global exports for EM2 HUD Aura toggle ──
_G.MSUF_A2_HideAllEditMovers = function() EM.HideAllMovers() end
_G.MSUF_A2_ShowAllEditMovers = function() EM.ShowAllMovers() end

-- MSUF_A2_Preview.lua

-- Auras2: Preview + Edit Mode helper (split from MSUF_A2_Render.lua)
-- Goal: isolate preview/ticker/cleanup logic to reduce Render bloat, with zero feature regression.

local addonName, ns = ...

local type, tostring = type, tostring
local pairs, ipairs = pairs, ipairs
local GetTime = GetTime
local C_Timer = C_Timer

local API = ns and ns.MSUF_Auras2
if not API then  return end

API.Preview = (type(API.Preview) == "table") and API.Preview or {}
local Preview = API.Preview

-- Helpers

local function IsEditModeActive()
    local fn = API.IsEditModeActive
    if type(fn) == "function" then return fn() == true end
    local st = rawget(_G, "MSUF_EditState")
    if st and st.active == true then return true end
    if rawget(_G, "MSUF_UnitEditModeActive") == true then return true end
    return false
end

-- API.IsEditModeActive is owned by Render (cached). Preview must not override it.

local function EnsureDB()
    local DB = API.DB
    if DB and DB.Ensure then return DB.Ensure() end
    return nil, nil
end
local function GetAurasByUnit()
    local st = API.state
    if not st then  return nil end
    return st.aurasByUnit
end

local function GetCooldownTextMgr()
    -- Prefer split module API, but keep legacy global aliases.
    local CT = API.CooldownText
    local reg = CT and CT.RegisterIcon
    local unreg = CT and CT.UnregisterIcon

    if type(reg) ~= "function" then
        reg = rawget(_G, "MSUF_A2_CooldownTextMgr_RegisterIcon")
    end
    if type(unreg) ~= "function" then
        unreg = rawget(_G, "MSUF_A2_CooldownTextMgr_UnregisterIcon")
    end

     return reg, unreg
end

-- Phase F: Preview no longer depends on Render helpers.
-- It calls Apply directly so Render can stay orchestration-only.
local function GetApply()
    return (type(API.Apply) == "table") and API.Apply or nil
end

-- Preview cleanup (safety): ensure preview icons never block real auras

-- Forward-declared here because ClearPreviewIconsInContainer needs it,
-- but the full preview CD text block is defined later with the other helpers.
local function ClearPreviewCDText(icon, cd)
    if not icon then return end
    local fs = icon._msufA2_previewCDText
    if fs then
        fs:Hide()
        fs:SetText("")
    end
    if cd then
        cd._msufA2_pvCDSize = nil
        cd._msufA2_pvCDOffX = nil
        cd._msufA2_pvCDOffY = nil
        cd._msufA2_pvCDFont = nil
    end
    icon._msufA2_pvCDSize = nil
    icon._msufA2_pvCDOffX = nil
    icon._msufA2_pvCDOffY = nil
    icon._msufA2_pvCDFont = nil
end

local function ClearPreviewIconsInContainer(container)
    if not container or not container._msufIcons then  return end

    local _, unreg = GetCooldownTextMgr()

    for _, icon in ipairs(container._msufIcons) do
        if icon and icon._msufA2_isPreview == true then
            -- Ensure preview cooldown text/ticker stops tracking this icon.
            if type(unreg) == "function" then
                unreg(icon)
            end

            icon._msufA2_isPreview = nil
            icon._msufA2_previewMeta = nil
            icon._msufA2_previewDurationObj = nil
            icon._msufA2_previewStackT = nil
            icon._msufA2_previewCooldownT = nil
            icon._msufA2_previewCDCounter = nil
            -- Clear render-side caches so preview textures never 'stick' on reused icon frames.
            icon._msufA2_lastVisualAuraInstanceID = nil
            icon._msufA2_lastCooldownAuraInstanceID = nil
            icon._msufA2_lastDurationObject = nil
            icon._msufA2_lastCooldownUsesDurationObject = nil
            icon._msufA2_lastCooldownUsesExpiration = nil
            icon._msufA2_lastCooldownType = nil
            -- Bug 1 fix: Also clear texture diff cache so real auras always
            -- get their texture set after preview exit.
            icon._msufA2_lastTexAid = nil
            -- Force CommitIcon to do a full apply (bypass diff-gate).
            icon._msufA2_lastCommit = nil

            if icon.cooldown then
                -- Clean up preview-only cooldown text FontString.
                ClearPreviewCDText(icon, icon.cooldown)

                -- Clear cooldown visuals so preview never leaves "dark" state.
                if icon.cooldown.Clear then icon.cooldown:Clear() end
                if icon.cooldown.SetCooldown then icon.cooldown:SetCooldown(0, 0) end
                if icon.cooldown.SetCooldownDuration then icon.cooldown:SetCooldownDuration(0) end

                -- Restore Blizzard native countdown for real auras.
                if icon.cooldown.SetHideCountdownNumbers then
                    icon.cooldown._msufA2_lastHideNumbers = false
                    icon.cooldown:SetHideCountdownNumbers(false)
                end
            end

            icon:Hide()
        end
    end
 end

local function ClearPreviewsForEntry(entry)
    if not entry then  return end
    ClearPreviewIconsInContainer(entry.buffs)
    ClearPreviewIconsInContainer(entry.debuffs)
    ClearPreviewIconsInContainer(entry.mixed)
    ClearPreviewIconsInContainer(entry.private)
    entry._msufA2_previewActive = nil
 end

local function HideUnsupportedAuraPreviewEntry(entry)
    if not entry then return end
    ClearPreviewsForEntry(entry)
    if API.EditMode and API.EditMode.HideMovers then
        API.EditMode.HideMovers(entry)
    end
    if entry.buffs then entry.buffs:Hide() end
    if entry.debuffs then entry.debuffs:Hide() end
    if entry.mixed then entry.mixed:Hide() end
    if entry.private then entry.private:Hide() end
    if entry.anchor then entry.anchor:Hide() end
end

local function ClearAllPreviews()
    local AurasByUnit = GetAurasByUnit()
    if not AurasByUnit then  return end

    for _, entry in pairs(AurasByUnit) do
        if entry and entry._msufA2_previewActive == true then
            ClearPreviewsForEntry(entry)
        end
    end
 end

Preview.ClearPreviewsForEntry = ClearPreviewsForEntry
Preview.ClearAllPreviews = ClearAllPreviews

-- Keep existing public exports stable for Options + other modules.
API.ClearPreviewsForEntry = API.ClearPreviewsForEntry or ClearPreviewsForEntry
API.ClearAllPreviews = API.ClearAllPreviews or ClearAllPreviews

if _G and type(_G.MSUF_Auras2_ClearAllPreviews) ~= "function" then
    _G.MSUF_Auras2_ClearAllPreviews = function()  return API.ClearAllPreviews() end
end

local function RenderEntryPreview(entry, unit, shared, isEditActive, cfg)
    if not entry or not unit or not shared then
        return false, false
    end

    -- Skip aura previews for lightweight child frames that do not support auras.
    if unit == "pet" or unit == "targettarget" or unit == "focustarget" then
        HideUnsupportedAuraPreviewEntry(entry)
        return false, false
    end

    -- Skip aura previews for units that don't have auras enabled
    local DB = API and API.DB
    if DB and DB.UnitEnabledCached and DB.UnitEnabledCached(unit) ~= true then
        HideUnsupportedAuraPreviewEntry(entry)
        return false, false
    end

    local showTest = (shared.showInEditMode == true and isEditActive == true)
    cfg = cfg or {}
    local showPrivatePreview = (shared.privateAurasEnabled == true)
        and unit == "player"
        and shared.showPrivateAurasPlayer == true

    if showTest then
        if entry.buffs then entry.buffs:Show() end
        if entry.debuffs then entry.debuffs:Show() end
        if entry.mixed then entry.mixed:Hide() end
        if entry.private and showPrivatePreview then entry.private:Show()
        elseif entry.private then entry.private:Hide() end
        entry._msufA2_previewActive = true
    elseif entry._msufA2_previewActive then
        if API.ClearPreviewsForEntry then
            API.ClearPreviewsForEntry(entry)
        else
            entry._msufA2_previewActive = nil
        end
        entry._msufA2_playerPreviewInit = nil
        return false, false
    else
        return false, false
    end

    local Icons = API.Icons or API.Apply
    if not Icons then
        return showTest, false
    end

    local isPlayer = (unit == "player")

    if Icons.RenderPreviewIcons and not isPlayer then
        local buffCap = cfg.maxBuffs or 0
        local debuffCap = cfg.maxDebuffs or 0
        local bc, dc = 0, 0
        if buffCap > 0 or debuffCap > 0 then
            bc, dc = Icons.RenderPreviewIcons(entry, unit, shared, false, buffCap, debuffCap, cfg.stackCountAnchor)
        else
            ClearPreviewIconsInContainer(entry.buffs)
            ClearPreviewIconsInContainer(entry.debuffs)
        end
        if Icons.LayoutIcons then
            Icons.LayoutIcons(entry.buffs, bc or 0, cfg.buffIconSize, cfg.spacing, cfg.perRow, cfg.buffGrowth, cfg.buffRowWrap)
        end
        if Icons.LayoutIcons then
            Icons.LayoutIcons(entry.debuffs, dc or 0, cfg.debuffIconSize, cfg.spacing, cfg.perRow, cfg.debuffGrowth, cfg.debuffRowWrap)
        end
    elseif Icons.RenderPreviewIcons and isPlayer then
        local _, dc = Icons.RenderPreviewIcons(entry, unit, shared, false, 0, cfg.maxDebuffs, cfg.stackCountAnchor)
        if Icons.LayoutIcons then
            Icons.LayoutIcons(entry.debuffs, dc or 0, cfg.debuffIconSize, cfg.spacing, cfg.perRow, cfg.debuffGrowth, cfg.debuffRowWrap)
        end
    end

    if Icons.RenderPreviewPrivateIcons and showPrivatePreview then
        Icons.RenderPreviewPrivateIcons(entry, unit, shared, cfg.privateIconSize, cfg.spacing, cfg.stackCountAnchor, cfg.privateGrowth)
    end

    if isPlayer then
        if not entry._msufA2_playerPreviewInit then
            entry._msufA2_playerPreviewInit = true
        end
        return showTest, false
    end

    local anyCustomPreview = ((cfg.maxBuffs or 0) > 0) or ((cfg.maxDebuffs or 0) > 0)
    return showTest, anyCustomPreview
end

Preview.RenderEntryPreview = RenderEntryPreview
API.RenderEntryPreview = API.RenderEntryPreview or RenderEntryPreview

-- Preview loops (Edit Mode): cycle stacks + cooldowns while previews are active.

local PreviewTickers = {
    stacks = nil,
    cooldown = nil,
}

local function ShouldRunPreviewTicker(kind, a2, shared)
    if not a2 or not a2.enabled then  return false end
    local DB = API and API.DB
    if DB and DB.AnyUnitEnabledCached and DB.AnyUnitEnabledCached() ~= true then  return false end
    if not shared or shared.showInEditMode ~= true then  return false end
    if not API.IsEditModeActive or API.IsEditModeActive() ~= true then  return false end
    if kind == "stacks" and shared.showStackCount == false then  return false end
     return true
end

local function ForEachPreviewIcon(fn)
    local AurasByUnit = GetAurasByUnit()
    if not AurasByUnit then  return end

    for _, entry in pairs(AurasByUnit) do
        if entry and entry._msufA2_previewActive == true then
            -- Inline container iteration (no temp table allocation)
            local container = entry.buffs
            if container and container._msufIcons then
                for _, icon in ipairs(container._msufIcons) do
                    if icon and icon:IsShown() and icon._msufA2_isPreview == true then
                        fn(icon)
                    end
                end
            end
            container = entry.debuffs
            if container and container._msufIcons then
                for _, icon in ipairs(container._msufIcons) do
                    if icon and icon:IsShown() and icon._msufA2_isPreview == true then
                        fn(icon)
                    end
                end
            end
            container = entry.mixed
            if container and container._msufIcons then
                for _, icon in ipairs(container._msufIcons) do
                    if icon and icon:IsShown() and icon._msufA2_isPreview == true then
                        fn(icon)
                    end
                end
            end
            container = entry.private
            if container and container._msufIcons then
                for _, icon in ipairs(container._msufIcons) do
                    if icon and icon:IsShown() and icon._msufA2_isPreview == true then
                        fn(icon)
                    end
                end
            end
        end
    end
 end

-- File-scope state for preview tick callbacks (avoid closure per tick)
local _tickShared = nil
local _tickA2db = nil
local _tickStackCountAnchor = nil
local _tickApplyAnchorStyle = nil
local _tickApplyOffsets = nil
local _tickApplyCDOffsets = nil
local _tickReg = nil
local _tickFontPath = nil
local _tickFontFlags = nil

-- Preview cooldown text: own FontString that responds to user's
-- cooldownTextSize / cooldownTextOffsetX / cooldownTextOffsetY
-- in real-time while the Edit Mode popup is open.

local PREVIEW_CD_FONT = "Fonts\\FRIZQT__.TTF"

local function ResolvePreviewCDConfig(icon, shared, a2db)
    local size = (shared and shared.cooldownTextSize) or 14
    local offX = (shared and shared.cooldownTextOffsetX) or 0
    local offY = (shared and shared.cooldownTextOffsetY) or 0

    local unit = icon._msufUnit
    if unit and a2db and a2db.perUnit then
        local pu = a2db.perUnit[unit]
        if pu and pu.overrideLayout == true and type(pu.layout) == "table" then
            local lay = pu.layout
            if type(lay.cooldownTextSize) == "number" then size = lay.cooldownTextSize end
            if type(lay.cooldownTextOffsetX) == "number" then offX = lay.cooldownTextOffsetX end
            if type(lay.cooldownTextOffsetY) == "number" then offY = lay.cooldownTextOffsetY end
        end
    end

    if type(size) ~= "number" or size <= 0 then size = 14 end
    if type(offX) ~= "number" then offX = 0 end
    if type(offY) ~= "number" then offY = 0 end
    return size, offX, offY
end

local function EnsurePreviewCDText(icon)
    if not icon then return nil end
    local fs = icon._msufA2_previewCDText
    if fs then return fs end

    -- Parent to the icon frame (not the Cooldown widget which may reject CreateFontString).
    if not icon.CreateFontString then return nil end
    fs = icon:CreateFontString(nil, "OVERLAY")
    if not fs then return nil end

    -- Resolve global MSUF font if available; otherwise use default
    local fontPath = PREVIEW_CD_FONT
    local fontFlags = "OUTLINE"
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        local p, fl = gfs()
        if type(p) == "string" and p ~= "" then fontPath = p end
        if type(fl) == "string" then fontFlags = fl end
    end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(fs, fontPath, 14, fontFlags, (g and g.fontKey) or "FRIZQT")
    else
        fs:SetFont(fontPath, 14, fontFlags)
    end
    -- Anchor to the cooldown frame center so it visually overlays the swirl.
    local cd = icon.cooldown
    local anchor = (cd and cd.GetObjectType) and cd or icon
    fs:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(1, 1, 1, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    icon._msufA2_previewCDText = fs
    return fs
end

local function ReadPreviewColor(t, dr, dg, db)
    if type(t) ~= "table" then return dr, dg, db, 1 end
    local r = t[1] or t.r
    local g = t[2] or t.g
    local b = t[3] or t.b
    if type(r) ~= "number" then r = dr end
    if type(g) ~= "number" then g = dg end
    if type(b) ~= "number" then b = db end
    return r, g, b, 1
end

local function GetPreviewBaseCooldownColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if g and g.useCustomFontColor == true then
        local r = g.fontColorCustomR
        local gg = g.fontColorCustomG
        local b = g.fontColorCustomB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, 1
        end
    end
    return 1, 1, 1, 1
end

local function GetPreviewCooldownColor(remain)
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local br, bg, bb = GetPreviewBaseCooldownColor()
    local sr, sg, sb, sa = ReadPreviewColor(g and g.aurasCooldownTextSafeColor, br, bg, bb)
    if g and g.aurasCooldownTextUseBuckets == false then
        return sr, sg, sb, sa
    end

    local warn = (g and type(g.aurasCooldownTextWarningSeconds) == "number") and g.aurasCooldownTextWarningSeconds or 15
    local urgent = (g and type(g.aurasCooldownTextUrgentSeconds) == "number") and g.aurasCooldownTextUrgentSeconds or 5
    if urgent > warn then urgent = warn end

    remain = tonumber(remain) or 0
    if remain <= urgent then
        return ReadPreviewColor(g and g.aurasCooldownTextUrgentColor, 1, 0.55, 0.10)
    end
    if remain <= warn then
        return ReadPreviewColor(g and g.aurasCooldownTextWarningColor, 1, 0.85, 0.20)
    end
    return sr, sg, sb, sa
end

local function _PreviewStackIconFn(icon)
    if not icon or not icon.count then return end

    if _tickApplyAnchorStyle then
        _tickApplyAnchorStyle(icon, _tickStackCountAnchor)
    end
    if _tickApplyOffsets then
        _tickApplyOffsets(icon, icon._msufUnit, _tickShared, _tickStackCountAnchor)
    end

    icon._msufA2_previewStackT = (icon._msufA2_previewStackT or 0) + 1

    local num = icon._msufA2_previewStackT
    if num > 9 then
        num = 1
        icon._msufA2_previewStackT = 1
    end

    icon.count:SetText(num)

    if _tickShared and _tickShared.showStackCount == false then
        icon.count:Hide()
    else
        icon.count:Show()
    end
end

local function PreviewTickStacks()
    local a2, shared = EnsureDB()
    if not ShouldRunPreviewTicker("stacks", a2, shared) then  return end

    local A = GetApply()

    -- Set file-scope upvalues for callback
    _tickShared = shared
    _tickStackCountAnchor = shared and shared.stackCountAnchor
    _tickApplyAnchorStyle = A and A.ApplyStackCountAnchorStyle
    _tickApplyOffsets = A and A.ApplyStackTextOffsets

    ForEachPreviewIcon(_PreviewStackIconFn)
 end

local function _PreviewCooldownIconFn(icon)
    if not icon or not icon.cooldown then return end
    local cd = icon.cooldown

    -- Hide Blizzard's native countdown; we render our own preview text.
    if cd.SetHideCountdownNumbers then
        cd._msufA2_lastHideNumbers = true
        cd:SetHideCountdownNumbers(true)
    end

    -- Apply cooldown offsets from Icons module (invalidates caches, applies font family)
    if _tickApplyCDOffsets then
        _tickApplyCDOffsets(icon, icon._msufUnit, _tickShared)
    end

    -- Update cooldown swirl visuals (duration object preferred; fallback to SetCooldown).
    if icon._msufA2_previewDurationObj and cd.SetCooldownFromDurationObject then
        cd:SetCooldownFromDurationObject(icon._msufA2_previewDurationObj)
    elseif cd.SetCooldown then
        local now = GetTime()
        local start = (icon._msufA2_previewCooldownT or 0) + (now - 10)
        cd:SetCooldown(start, 10)
    end

    if _tickReg then
        _tickReg(icon)
    end

    -- Preview-only cooldown text: create FontString and keep it synced
    -- with the user's cooldownTextSize / cooldownTextOffsetX / Y settings.
    local fs = EnsurePreviewCDText(icon)
    if not fs then return end

    local size, offX, offY = ResolvePreviewCDConfig(icon, _tickShared, _tickA2db)

    local fontPath = _tickFontPath or PREVIEW_CD_FONT
    local fontFlags = _tickFontFlags or "OUTLINE"

    -- Apply font family + size (diff-gated)
    if icon._msufA2_pvCDSize ~= size or icon._msufA2_pvCDFont ~= fontPath then
        local g = _G.MSUF_DB and _G.MSUF_DB.general
        if type(_G.MSUF_SetFontSafe) == "function" then
            _G.MSUF_SetFontSafe(fs, fontPath, size, fontFlags, (g and g.fontKey) or "FRIZQT")
        else
            fs:SetFont(fontPath, size, fontFlags)
        end
        icon._msufA2_pvCDSize = size
        icon._msufA2_pvCDFont = fontPath
    end

    -- Apply offsets (diff-gated); anchor to cooldown center
    if icon._msufA2_pvCDOffX ~= offX or icon._msufA2_pvCDOffY ~= offY then
        local anchor = (cd and cd.GetObjectType) and cd or icon
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", anchor, "CENTER", offX, offY)
        icon._msufA2_pvCDOffX = offX
        icon._msufA2_pvCDOffY = offY
    end

    -- Cycle a fake countdown value (1-9, updates each tick ~0.5s)
    local counter = (icon._msufA2_previewCDCounter or 0) + 1
    if counter > 9 then counter = 1 end
    icon._msufA2_previewCDCounter = counter
    fs:SetText(tostring(counter))
    fs:SetTextColor(GetPreviewCooldownColor(counter))
    fs:Show()
end

local function PreviewTickCooldown()
    local a2, shared = EnsureDB()
    if not ShouldRunPreviewTicker("cooldown", a2, shared) then  return end

    local A = GetApply()

    -- Set file-scope upvalues for callback
    _tickShared = shared
    _tickA2db = a2
    _tickApplyCDOffsets = A and A.ApplyCooldownTextOffsets
    _tickReg, _ = GetCooldownTextMgr()

    local fontPath = PREVIEW_CD_FONT
    local fontFlags = "OUTLINE"
    local gfs = _G.MSUF_GetGlobalFontSettings
    if type(gfs) == "function" then
        local p, fl = gfs()
        if type(p) == "string" and p ~= "" then fontPath = p end
        if type(fl) == "string" then fontFlags = fl end
    end
    _tickFontPath = fontPath
    _tickFontFlags = fontFlags

    ForEachPreviewIcon(_PreviewCooldownIconFn)
 end

local function RunPreviewLoop(kind)
    local loop = PreviewTickers[kind]
    if not loop then return end

    loop.fn()

    if PreviewTickers[kind] ~= loop then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(loop.interval, loop.step)
    else
        PreviewTickers[kind] = nil
    end
end

local function EnsureTicker(kind, need, interval, fn)
    local t = PreviewTickers[kind]
    if need then
        if not t then
            local loop = { interval = interval, fn = fn }
            loop.step = function()
                if PreviewTickers[kind] == loop then
                    RunPreviewLoop(kind)
                end
            end
            PreviewTickers[kind] = loop
            if C_Timer and C_Timer.After then
                C_Timer.After(interval, loop.step)
            else
                fn()
                PreviewTickers[kind] = nil
            end
        end
    else
        PreviewTickers[kind] = nil
    end
 end

local function UpdatePreviewStackTicker()
    local a2, shared = EnsureDB()

    -- If the user disables Edit Mode previews, hard-clear any existing preview icons immediately.
    if shared and shared.showInEditMode ~= true then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    local need = ShouldRunPreviewTicker("stacks", a2, shared)
    EnsureTicker("stacks", need, 0.50, PreviewTickStacks)
 end

local function UpdatePreviewCooldownTicker()
    local a2, shared = EnsureDB()

    -- If the user disables Edit Mode previews, hard-clear any existing preview icons immediately.
    if shared and shared.showInEditMode ~= true then
        if API.ClearAllPreviews then
            API.ClearAllPreviews()
        end
    end

    local need = ShouldRunPreviewTicker("cooldown", a2, shared)
    EnsureTicker("cooldown", need, 0.50, PreviewTickCooldown)
 end

Preview.UpdatePreviewStackTicker = UpdatePreviewStackTicker
Preview.UpdatePreviewCooldownTicker = UpdatePreviewCooldownTicker

API.UpdatePreviewStackTicker = API.UpdatePreviewStackTicker or UpdatePreviewStackTicker
API.UpdatePreviewCooldownTicker = API.UpdatePreviewCooldownTicker or UpdatePreviewCooldownTicker

if _G and type(_G.MSUF_Auras2_UpdatePreviewStackTicker) ~= "function" then
    _G.MSUF_Auras2_UpdatePreviewStackTicker = function()
        if API and API.UpdatePreviewStackTicker then
            return API.UpdatePreviewStackTicker()
        end
     end
end

if _G and type(_G.MSUF_Auras2_UpdatePreviewCooldownTicker) ~= "function" then
    _G.MSUF_Auras2_UpdatePreviewCooldownTicker = function()
        if API and API.UpdatePreviewCooldownTicker then
            return API.UpdatePreviewCooldownTicker()
        end
     end
end

-- Preview rendering (moved from A2_Core for hot-path slimming)

do
local Icons = ns.MSUF_Auras2 and ns.MSUF_Auras2.Icons
local Apply = API and API.Apply
if Icons then

function Icons.RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    -- Delegate to existing preview system if available
    local fn = API._Render and API._Render.RenderPreviewIcons
    if type(fn) == "function" then
        return fn(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    end

    local buffCount = 0
    local debuffCount = 0
    local gen = _G.MSUF_A2_ConfigGen or 0
    local showStacks = (shared and shared.showStackCount ~= false)
    local now = GetTime()

    -- Apply full text config + cooldown to a preview icon
    local function SetupPreviewIcon(icon, idx, kind)
        icon._msufA2_isPreview = true
        icon._msufA2_previewKind = kind
        icon._msufUnit = unit

        -- Varied texture
        if icon.tex then
            if kind == "buff" then
                icon.tex:SetTexture(A2_PREVIEW_BUFF_TEXTURES[((idx - 1) % A2_PREVIEW_BUFF_TEX_N) + 1])
            else
                icon.tex:SetTexture(A2_PREVIEW_DEBUFF_TEXTURES[((idx - 1) % A2_PREVIEW_DEBUFF_TEX_N) + 1])
            end
        end

        icon:Show()

        -- Click-through: apply same 3-state setting as live icons (diff-gated)
        local wantMS = _G.MSUF_A2_ClickThrough and (_G.MSUF_A2_ShowTooltip and 1 or 2) or 0
        _A2E_ApplyMouseState(icon, wantMS)

        -- Invalidate + resolve text config
        icon._msufA2_textCfgGen = nil
        _A2E_ResolveTextConfig(icon, unit, shared, gen)

        -- Stack text
        icon._msufA2_lastStackFontSize = nil
        icon._msufA2_lastStackFontPath = nil
        icon._msufA2_lastStackPointAnchor = nil
        icon._msufA2_lastStackPointX = nil
        icon._msufA2_lastStackPointY = nil
        icon._msufA2_lastStackJustifyAnchor = nil
        Apply.ApplyStackTextOffsets(icon, unit, shared, stackCountAnchor)

        if icon.count then
            if showStacks then
                local n = icon._msufA2_previewStackT or (((idx - 1) % 9) + 1)
                icon._msufA2_previewStackT = icon._msufA2_previewStackT or n
                icon.count:SetText(n)
                icon.count:Show()
            else
                icon.count:Hide()
            end
        end

        -- Cooldown swipe + countdown text
        local cd = icon.cooldown
        if cd then
            cd._msufA2_cdTextSize = nil
            cd._msufA2_cdFontPath = nil
            cd._msufA2_cdTextOffX = nil
            cd._msufA2_cdTextOffY = nil

            local dur = A2_PREVIEW_CD_DURATIONS[((idx - 1) % A2_PREVIEW_CD_DUR_N) + 1]
            -- Stagger start times so icons show different remaining times
            local elapsed = (idx * 2.7) % dur
            local startTime = now - elapsed

            if cd.SetHideCountdownNumbers then
                cd._msufA2_lastHideNumbers = false
                cd:SetHideCountdownNumbers(false)
            end
            if cd.SetCooldown then
                cd:SetCooldown(startTime, dur)
            end

            Apply.ApplyCooldownTextOffsets(icon, unit, shared)
        end
    end

    -- Buffs: show up to buffCap preview icons
    if entry.buffs and buffCap > 0 then
        for i = 1, buffCap do
            local icon = Icons.AcquireIcon(entry.buffs, i)
            if icon then
                SetupPreviewIcon(icon, i, "buff")
                buffCount = buffCount + 1
            end
        end
        Icons.HideUnused(entry.buffs, buffCount + 1)
    end

    -- Debuffs: show up to debuffCap preview icons
    if entry.debuffs and debuffCap > 0 then
        for i = 1, debuffCap do
            local icon = Icons.AcquireIcon(entry.debuffs, i)
            if icon then
                SetupPreviewIcon(icon, i, "debuff")
                debuffCount = debuffCount + 1
            end
        end
        Icons.HideUnused(entry.debuffs, debuffCount + 1)
    end

    entry._msufA2_previewActive = true
    return buffCount, debuffCount
end

function Icons.RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor, privateGrowth)
    -- Delegate to existing preview system
    local fn = API._Render and API._Render.RenderPreviewPrivateIcons
    if type(fn) == "function" then
        return fn(entry, unit, shared, privIconSize, spacing, stackCountAnchor, privateGrowth)
    end

    -- Private aura previews: player-only (12.0.1 combat restriction).
    local container = entry.private
    if not container then return end
    if unit ~= "player" then container:Hide(); return end

    local maxN = (shared and shared.privateAuraMaxPlayer) or 4
    if maxN <= 0 then maxN = 4 end

    -- Growth direction
    privateGrowth = privateGrowth or "RIGHT"
    local vertical = (privateGrowth == "UP" or privateGrowth == "DOWN")
    local anchorX, anchorY = "LEFT", "BOTTOM"
    local dirX, dirY = 1, 0
    if vertical then
        dirX, dirY = 0, 1
        if privateGrowth == "DOWN" then
            anchorY = "TOP"
            dirY = -1
        end
    else
        if privateGrowth == "LEFT" then
            anchorX = "RIGHT"
            dirX = -1
        end
    end
    local anchorPt = anchorY .. anchorX

    local gen = _G.MSUF_A2_ConfigGen or 0
    local now = GetTime()
    local showStacks = (shared and shared.showStackCount ~= false)
    local privCount = 0

    -- Sample private-aura-ish textures (shield/lock/eye themed)
    local privTex = { 136177, 134400, 135894, 136116, 135987, 136085,
                      132333, 135932, 136075, 135981, 136048, 132316 }
    local privTexN = #privTex

    for i = 1, maxN do
        local icon = Icons.AcquireIcon(container, i)
        if icon then
            icon._msufA2_isPreview = true
            icon._msufA2_previewKind = "private"
            icon._msufUnit = unit

            -- Aura texture (varied)
            if icon.tex then
                icon.tex:SetTexture(privTex[((i - 1) % privTexN) + 1])
            end
            icon:SetSize(privIconSize, privIconSize)

            --  Purple border to mark as "private aura" 
            if not icon._msufPrivateBorder then
                local border = icon:CreateTexture(nil, "OVERLAY", nil, 2)
                border:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
                border:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
                border:SetColorTexture(0.6, 0.2, 0.9, 0.0) -- start transparent
                icon._msufPrivateBorder = border
            end
            icon._msufPrivateBorder:SetColorTexture(0.6, 0.2, 0.9, 0.55)
            icon._msufPrivateBorder:Show()

            -- Small lock icon overlay (bottom-left corner)
            if not icon._msufPrivateLock then
                local lock = icon:CreateTexture(nil, "OVERLAY", nil, 3)
                lock:SetSize(math_max(10, privIconSize * 0.35), math_max(10, privIconSize * 0.35))
                lock:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
                lock:SetTexture(134400) -- padlock
                lock:SetDesaturated(false)
                icon._msufPrivateLock = lock
            end
            icon._msufPrivateLock:SetSize(math_max(10, privIconSize * 0.35), math_max(10, privIconSize * 0.35))
            icon._msufPrivateLock:Show()

            icon:Show()

            -- Click-through (3-state, diff-gated)
            local wantMS = _G.MSUF_A2_ClickThrough and (_G.MSUF_A2_ShowTooltip and 1 or 2) or 0
            _A2E_ApplyMouseState(icon, wantMS)

            -- Position using growth direction
            icon:ClearAllPoints()
            local off = (i - 1) * (privIconSize + spacing)
            icon:SetPoint(anchorPt, container, anchorPt, off * dirX, off * dirY)

            -- Text config
            icon._msufA2_textCfgGen = nil
            _A2E_ResolveTextConfig(icon, unit, shared, gen)

            -- Stack text
            icon._msufA2_lastStackFontSize = nil
            icon._msufA2_lastStackFontPath = nil
            icon._msufA2_lastStackPointAnchor = nil
            Apply.ApplyStackTextOffsets(icon, unit, shared, stackCountAnchor)

            if icon.count then
                if showStacks then
                    local n = icon._msufA2_previewStackT or (((i - 1) % 5) + 1)
                    icon._msufA2_previewStackT = icon._msufA2_previewStackT or n
                    icon.count:SetText(n)
                    icon.count:Show()
                else
                    icon.count:Hide()
                end
            end

            -- Cooldown swipe + countdown text
            local cd = icon.cooldown
            if cd then
                cd._msufA2_cdTextSize = nil
                cd._msufA2_cdFontPath = nil
                cd._msufA2_cdTextOffX = nil
                cd._msufA2_cdTextOffY = nil

                local dur = A2_PREVIEW_CD_DURATIONS[((i - 1) % A2_PREVIEW_CD_DUR_N) + 1]
                local elapsed = (i * 3.1) % dur

                if cd.SetHideCountdownNumbers then
                    cd._msufA2_lastHideNumbers = false
                    cd:SetHideCountdownNumbers(false)
                end
                if cd.SetCooldown then
                    cd:SetCooldown(now - elapsed, dur)
                end
                Apply.ApplyCooldownTextOffsets(icon, unit, shared)
            end

            privCount = privCount + 1
        end
    end
    Icons.HideUnused(container, privCount + 1)

    -- Size the container to wrap its children
    local step = privIconSize + spacing
    if step <= 0 then step = privIconSize + 2 end
    if vertical then
        container:SetSize(math_max(1, privIconSize), math_max(1, (privCount * step) - spacing))
    else
        container:SetSize(math_max(1, (privCount * step) - spacing), math_max(1, privIconSize))
    end
    container:Show()
end

end -- Icons
end -- do
