-- ============================================================================
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
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
-- =========================================================================
-- PERF LOCALS (Auras2 runtime)
--  - Reduce global table lookups in high-frequency aura pipelines.
--  - Secret-safe: localizing function references only (no value comparisons).
-- =========================================================================
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local C_UnitAuras = C_UnitAuras
local C_Secrets = C_Secrets
local C_CurveUtil = C_CurveUtil

ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

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
    if API.EnsureDB then return API.EnsureDB() end
    return nil, nil
end

local function GetAuras2DB()
    if API.GetDB then return API.GetDB() end
    return EnsureDB()
end


-- Edit Mode state detection (use Render's cached check if available)

local function IsEditModeActive()
    if API.IsEditModeActive then return API.IsEditModeActive() end
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active == true then return true end
    if rawget(_G, "MSUF_UnitEditModeActive") == true then return true end
    return false
end


-- Per-unit state (shared with Render)

local function GetAurasByUnit()
    local st = API.state
    return (type(st) == "table") and st.aurasByUnit or nil
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
    local val = 0

    -- Check perUnit override first
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    local pu = a2 and a2.perUnit and a2.perUnit[unitKey]
    local lay = pu and pu.overrideLayout == true and pu.layout

    local ox, oy = 0, 0
    if lay and type(lay[kx]) == "number" then ox = lay[kx] end
    if lay and type(lay[ky]) == "number" then oy = lay[ky] end

    -- Fallback to shared
    if ox == 0 and shared and type(shared[kx]) == "number" then ox = shared[kx] end
    if oy == 0 and shared and type(shared[ky]) == "number" then oy = shared[ky] end

    return ox, oy
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

local function IsAnyPopupOpen()
    local st = rawget(_G, "MSUF_EditState")
    if not st or not st.popupOpen then return false end
    -- Allow dragging while the Auras2 position popup is open
    local ap = _G.MSUF_Auras2PositionPopup
    if ap and ap.IsShown and ap:IsShown() then return false end
    return true
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
    mover:SetFrameStrata("DIALOG")
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

    -- â”€â”€ Header bar + label â”€â”€
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

    -- â”€â”€ Drag logic â”€â”€

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
        if shared.bossEditTogether == true and type(key) == "string" and key:match("^boss%d+$") then
            for i = 1, 5 do ApplyToUnit("boss" .. i) end
        else
            ApplyToUnit(key)
        end

        -- Sync position popup if open
        if type(_G.MSUF_SyncAuras2PositionPopup) == "function" then
            _G.MSUF_SyncAuras2PositionPopup(key)
        end
    end

    -- OnMouseDown: start drag
    mover:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then return end
        if IsAnyPopupOpen() then return end

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
            if self._msufDragMoved then
                self._msufDragMoved = false
                -- Invalidate DB so config cache updates with new offsets
                if API.InvalidateDB then API.InvalidateDB() end
                return
            end
        end

        -- Click without drag: open position popup
        local key = self._msufAuraUnitKey
        if type(_G.MSUF_OpenAuras2PositionPopup) == "function" then
            _G.MSUF_OpenAuras2PositionPopup(key, self)
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
    local n = type(unit) == "string" and unit:match("^boss(%d+)$")
    if n then return "Boss " .. n end
    return tostring(unit)
end

function EM.EnsureMovers(entry, unit, shared, iconSize, spacing)
    if not entry or not unit then return end

    local base = UnitLabel(unit)
    CreateMover(entry, unit, "buff",    base .. " Buffs")
    CreateMover(entry, unit, "debuff",  base .. " Debuffs")
    -- Private auras are player-only; no mover for target.
    if unit ~= "target" then
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
    local privW   = 4 * step  -- max private aura slots

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
    if entry.editMoverBuff    then entry.editMoverBuff:Show()    end
    if entry.editMoverDebuff  then entry.editMoverDebuff:Show()  end
    -- Private auras are player-only; skip mover for target.
    if entry.editMoverPrivate and entry.unit ~= "target" then entry.editMoverPrivate:Show() end
end

function EM.HideMovers(entry)
    if not entry then return end
    if entry.editMoverBuff    then entry.editMoverBuff:Hide()    end
    if entry.editMoverDebuff  then entry.editMoverDebuff:Hide()  end
    if entry.editMoverPrivate then entry.editMoverPrivate:Hide() end
end

function EM.AnyMoverExists(entry)
    return entry and (entry.editMoverBuff or entry.editMoverDebuff or entry.editMoverPrivate) and true or false
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
        -- Hide all movers
        EM.HideAllMovers()

        -- Clear previews
        if API.ClearAllPreviews then API.ClearAllPreviews() end

        -- Stop preview tickers
        if API.UpdatePreviewStackTicker then API.UpdatePreviewStackTicker() end
        if API.UpdatePreviewCooldownTicker then API.UpdatePreviewCooldownTicker() end

        -- Unregister cooldown text for preview icons
        local CT = API.CooldownText
        if CT and CT.UnregisterAll then CT.UnregisterAll() end

        -- Refresh to clear preview state
        if API.MarkAllDirty then API.MarkAllDirty(0) end
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
