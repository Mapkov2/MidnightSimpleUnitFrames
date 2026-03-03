-- ============================================================================
-- MSUF_A2_Reminder.lua  Buff Reminder — Ghost icons for missing/expiring buffs
--
-- Own container (entry.reminder) with independent X/Y offset + Edit Mode mover.
-- Edit Mode popup with X, Y, Size, Spacing, Growth direction.
--
-- Default: all reminders ON (nil = enabled). User sets key = false to disable.
-- Secret-safe: reads Cache._msufA2_sid, Cache.GetMinRemaining.
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
ns.MSUF_Auras2 = (type(ns.MSUF_Auras2) == "table") and ns.MSUF_Auras2 or {}
local API = ns.MSUF_Auras2

if ns.__MSUF_A2_REMINDER_LOADED then return end
ns.__MSUF_A2_REMINDER_LOADED = true

API.Reminder = (type(API.Reminder) == "table") and API.Reminder or {}
local Reminder = API.Reminder

-- =========================================================================
-- Hot locals
-- =========================================================================
local type, next = type, next
local wipe = table.wipe or function(t) for k in next, t do t[k] = nil end return t end
local CreateFrame, GetTime = CreateFrame, GetTime
local UnitClass, UnitExists, UnitIsDeadOrGhost = UnitClass, UnitExists, UnitIsDeadOrGhost
local IsInGroup, IsInRaid, GetNumGroupMembers = IsInGroup, IsInRaid, GetNumGroupMembers
local InCombatLockdown = InCombatLockdown
local GetCursorPosition = GetCursorPosition
local floor, format, max, min = math.floor, string.format, math.max, math.min
local C_Spell_GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local GetSpellTexture_fn = GetSpellTexture

local function _GetIcon(spellId)
    if C_Spell_GetSpellTexture then
        local ok, tex = pcall(C_Spell_GetSpellTexture, spellId)
        if ok and tex then return tex end
    end
    if GetSpellTexture_fn then
        local ok, tex = pcall(GetSpellTexture_fn, spellId)
        if ok and tex then return tex end
    end
    return 134400
end

-- =========================================================================
-- BUFF PROVIDERS
-- =========================================================================
local _PROVIDERS = {
    { key="FORTITUDE",       label="Power Word: Fortitude",  providerClass="PRIEST",     satisfiedBy={[21562]=true},  iconSpell=21562  },
    { key="ARCANE_INTELLECT",label="Arcane Intellect",       providerClass="MAGE",       satisfiedBy={[1459]=true},   iconSpell=1459   },
    { key="MARK_OF_WILD",    label="Mark of the Wild",       providerClass="DRUID",      satisfiedBy={[1126]=true},   iconSpell=1126   },
    { key="BATTLE_SHOUT",    label="Battle Shout",           providerClass="WARRIOR",    satisfiedBy={[6673]=true},   iconSpell=6673   },
    { key="SKYFURY",         label="Skyfury",                providerClass="SHAMAN",     satisfiedBy={[462854]=true}, iconSpell=462854 },
    { key="SOURCE_OF_MAGIC", label="Source of Magic",        providerClass="EVOKER",     satisfiedBy={[369459]=true}, iconSpell=369459 },
    { key="BLESSING_BRONZE", label="Blessing of the Bronze", providerClass="EVOKER",
        satisfiedBy={[381732]=true,[381741]=true,[381746]=true,[381748]=true,[381749]=true,[381750]=true,
                     [381751]=true,[381752]=true,[381753]=true,[381754]=true,[381756]=true,[381757]=true,[381758]=true},
        iconSpell=381732 },
    { key="ROGUE_LETHAL",    label="Lethal Poison",          providerClass="ROGUE_SELF", satisfiedBy={[2823]=true,[8679]=true,[315584]=true,[381664]=true}, iconSpell=2823 },
    { key="ROGUE_NONLETHAL", label="Non-Lethal Poison",      providerClass="ROGUE_SELF", satisfiedBy={[3408]=true,[5761]=true,[381637]=true},               iconSpell=3408 },
}
Reminder.PROVIDERS = _PROVIDERS

-- =========================================================================
-- Group roster scan
-- =========================================================================
local _presentClasses = {}
local _playerClass = nil

local function _ScanRoster()
    wipe(_presentClasses)
    local _, cls = UnitClass("player")
    _playerClass = cls
    if cls then _presentClasses[cls] = true end
    if not IsInGroup() and not IsInRaid() then return end
    local n = GetNumGroupMembers() or 0
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) then
            local _, c = UnitClass(u)
            if c then _presentClasses[c] = true end
        end
    end
end

-- =========================================================================
-- Missing / expiring computation
-- =========================================================================
local _results = {}
local _resultCount = 0

local function _ComputeMissing(reminders, threshold, isPreview)
    wipe(_results)
    _resultCount = 0
    local Cache = API.Cache
    local hasSpell  = Cache and Cache.HasAnySpell
    local getMinRem = Cache and Cache.GetMinRemaining
    local thr = (type(threshold) == "number" and threshold > 0) and threshold or 0

    for i = 1, #_PROVIDERS do
        local p = _PROVIDERS[i]
        if not reminders or reminders[p.key] ~= false then
            if isPreview then
                _resultCount = _resultCount + 1
                _results[_resultCount] = { provider = p, state = "MISSING", remaining = nil }
            else
                local shouldCheck = false
                if p.providerClass == "ROGUE_SELF" then
                    shouldCheck = (_playerClass == "ROGUE")
                else
                    shouldCheck = (_presentClasses[p.providerClass] == true)
                end
                if shouldCheck and hasSpell then
                    local hasBuff = hasSpell("player", p.satisfiedBy)
                    if not hasBuff then
                        _resultCount = _resultCount + 1
                        _results[_resultCount] = { provider = p, state = "MISSING", remaining = nil }
                    elseif thr > 0 and getMinRem then
                        local rem = getMinRem("player", p.satisfiedBy)
                        if rem and rem < thr then
                            _resultCount = _resultCount + 1
                            _results[_resultCount] = { provider = p, state = "EXPIRING", remaining = rem }
                        end
                    end
                end
            end
        end
    end
end

-- =========================================================================
-- Timer text formatting
-- =========================================================================
local function _FormatTime(sec)
    if not sec or sec <= 0 then return "" end
    sec = floor(sec)
    if sec < 60 then return sec .. "s" end
    local m = floor(sec / 60)
    local s = sec - m * 60
    if s > 0 then return format("%d:%02d", m, s) end
    return m .. "m"
end

-- =========================================================================
-- Ghost icon pool
-- =========================================================================
local _ghostPool = {}
local _ghostActive = 0

local function _AcquireGhost(container, index)
    local ghost = _ghostPool[index]
    if ghost then
        ghost:SetParent(container)
        if not ghost:IsShown() then ghost:Show() end
        return ghost
    end

    ghost = CreateFrame("Button", nil, container)
    ghost:SetSize(22, 22)
    ghost:EnableMouse(true)
    ghost:RegisterForClicks("AnyUp")

    local tex = ghost:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetDesaturated(true)
    ghost._tex = tex

    local overlay = ghost:CreateTexture(nil, "OVERLAY")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.3)
    ghost._overlay = overlay

    local badge = ghost:CreateTexture(nil, "OVERLAY", nil, 2)
    badge:SetSize(10, 10)
    badge:SetPoint("TOPRIGHT", ghost, "TOPRIGHT", 2, 2)
    ghost._badge = badge

    local bang = ghost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bang:SetPoint("CENTER", badge, "CENTER", 0, 0)
    bang:SetText("!")
    bang:SetTextColor(1, 1, 1, 1)
    ghost._bang = bang

    local timer = ghost:CreateFontString(nil, "OVERLAY")
    timer:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    timer:SetPoint("BOTTOM", ghost, "BOTTOM", 0, 1)
    timer:SetTextColor(1, 0.8, 0.2, 1)
    timer:Hide()
    ghost._timer = timer

    ghost:SetScript("OnEnter", function(self)
        if not self._result then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        local r = self._result
        if self._isPreview then
            GameTooltip:AddLine("Buff Reminder Preview", 0.4, 0.7, 1)
            GameTooltip:AddLine(r.provider.label, 1, 1, 1)
            GameTooltip:AddLine("Click the mover to open position settings.", 0.7, 0.7, 0.7, true)
        elseif r.state == "EXPIRING" then
            GameTooltip:AddLine("Expiring: " .. r.provider.label, 1, 0.6, 0.1)
            GameTooltip:AddLine(_FormatTime(r.remaining) .. " remaining", 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine("Missing: " .. r.provider.label, 1, 0.3, 0.3)
            if r.provider.providerClass == "ROGUE_SELF" then
                GameTooltip:AddLine("Apply your poison!", 0.8, 0.8, 0.8, true)
            else
                local cls = r.provider.providerClass
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                local cName = color and color.colorStr and ("|c" .. color.colorStr .. cls .. "|r") or cls
                GameTooltip:AddLine("A " .. cName .. " in your group can provide this.", 0.8, 0.8, 0.8, true)
            end
        end
        GameTooltip:Show()
    end)
    ghost:SetScript("OnLeave", function() GameTooltip:Hide() end)

    _ghostPool[index] = ghost
    return ghost
end

local function _HideGhosts(fromIndex)
    for i = fromIndex, _ghostActive do
        local g = _ghostPool[i]
        if g then g:Hide() end
    end
end

-- =========================================================================
-- DB helpers — read/write reminder layout fields
-- =========================================================================
local function _GetCursorScaled()
    local scale = (UIParent and UIParent.GetEffectiveScale) and UIParent:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    return cx / scale, cy / scale
end

local function _GetDB()
    if not MSUF_DB or not MSUF_DB.auras2 then return nil, nil, nil end
    local a2 = MSUF_DB.auras2
    local shared = a2.shared or {}
    local pu = a2.perUnit and a2.perUnit.player
    local lay = (pu and pu.overrideLayout == true and type(pu.layout) == "table") and pu.layout or nil
    return a2, shared, lay
end

local function _ReadVal(shared, lay, key, def)
    if lay and lay[key] ~= nil then return tonumber(lay[key]) or def end
    if shared and shared[key] ~= nil then return tonumber(shared[key]) or def end
    return def
end

local function _WriteLayout(key, value)
    if not MSUF_DB or not MSUF_DB.auras2 then return end
    local a2 = MSUF_DB.auras2
    a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
    local u = a2.perUnit.player
    if type(u) ~= "table" then u = {}; a2.perUnit.player = u end
    u.overrideLayout = true
    u.layout = (type(u.layout) == "table") and u.layout or {}
    u.layout[key] = value
end

local function _ApplyAndRefresh()
    if API.UpdateUnitAnchor then API.UpdateUnitAnchor("player") end
    if API.MarkDirty then API.MarkDirty("player") end
end

-- =========================================================================
-- Edit Mode Popup — Position/Size/Spacing/Growth for reminder container
-- Matches existing MSUF popup visual style 1:1.
-- =========================================================================
local _popup = nil

-- Numeric row builder (label + editbox + stepper buttons)
-- Replicates MSUF_EM_CreateNumericRowStored pattern.
local _popupRowCount = 0
local function _CreateNumericRow(parent, labelText, anchorTo, dy, onChanged)
    _popupRowCount = _popupRowCount + 1
    local rowName = "MSUF_ReminderPopupRow" .. _popupRowCount

    -- Label
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, dy or -8)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)

    -- EditBox
    local box = CreateFrame("EditBox", rowName .. "Box", parent, "InputBoxTemplate")
    box:SetSize(55, 18)
    box:SetPoint("LEFT", label, "RIGHT", 8, 0)
    box:SetAutoFocus(false)
    box:SetNumeric(false)
    box:SetMaxLetters(6)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if onChanged then onChanged() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Minus button
    local minus = CreateFrame("Button", nil, parent)
    minus:SetSize(16, 16)
    minus:SetPoint("LEFT", box, "RIGHT", 2, 0)
    minus:SetNormalFontObject("GameFontNormal")
    local mTex = minus:CreateTexture(nil, "ARTWORK")
    mTex:SetAllPoints()
    mTex:SetColorTexture(0.25, 0.25, 0.25, 0.6)
    local mText = minus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mText:SetPoint("CENTER")
    mText:SetText("-")
    minus:SetScript("OnClick", function()
        local v = tonumber(box:GetText()) or 0
        local step = IsShiftKeyDown() and 10 or 1
        box:SetText(tostring(floor(v - step)))
        if onChanged then onChanged() end
    end)

    -- Plus button
    local plus = CreateFrame("Button", nil, parent)
    plus:SetSize(16, 16)
    plus:SetPoint("LEFT", minus, "RIGHT", 1, 0)
    local pTex = plus:CreateTexture(nil, "ARTWORK")
    pTex:SetAllPoints()
    pTex:SetColorTexture(0.25, 0.25, 0.25, 0.6)
    local pText = plus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pText:SetPoint("CENTER")
    pText:SetText("+")
    plus:SetScript("OnClick", function()
        local v = tonumber(box:GetText()) or 0
        local step = IsShiftKeyDown() and 10 or 1
        box:SetText(tostring(floor(v + step)))
        if onChanged then onChanged() end
    end)

    return { label = label, box = box, minus = minus, plus = plus }
end

-- Growth direction dropdown builder
local _GROWTH_OPTIONS = {
    { value = "RIGHT", text = "Left to Right" },
    { value = "LEFT",  text = "Right to Left" },
    { value = "UP",    text = "Bottom to Top" },
    { value = "DOWN",  text = "Top to Bottom" },
}

local function _CreateGrowthDropdown(parent, anchorTo, dy, onChanged)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, dy or -8)
    label:SetText("Growth:")
    label:SetTextColor(0.85, 0.85, 0.85, 1)

    local dd = CreateFrame("Frame", "MSUF_ReminderGrowthDropdown", parent, "UIDropDownMenuTemplate")
    dd:SetPoint("LEFT", label, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(dd, 120)

    dd._value = "RIGHT"

    local function OnSelect(self, arg1)
        dd._value = arg1
        UIDropDownMenu_SetText(dd, self:GetText())
        if onChanged then onChanged() end
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, opt in ipairs(_GROWTH_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.text
            info.arg1 = opt.value
            info.func = OnSelect
            info.checked = (dd._value == opt.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    return { label = label, dropdown = dd }
end

local function _EnsurePopup()
    if _popup then return _popup end

    local pf = CreateFrame("Frame", "MSUF_ReminderPositionPopup", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    pf:SetSize(300, 290)
    pf:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    pf:SetFrameStrata("FULLSCREEN_DIALOG")
    pf:SetFrameLevel(500)
    pf:SetClampedToScreen(true)
    pf:SetMovable(true)
    pf:EnableMouse(true)
    pf:RegisterForDrag("LeftButton")
    pf:SetScript("OnDragStart", function(self) self:StartMoving() end)
    pf:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    -- Backdrop: matches MSUF_POPUP_DEFAULT_BACKDROP
    pf:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    pf:SetBackdropColor(0, 0, 0, 0.9)

    -- Title
    local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("MSUF Edit  Player Reminders")
    pf.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", "$parentClose", pf, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", pf, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() pf:Hide() end)

    -- Section header
    local header = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", pf, "TOPLEFT", 16, -36)
    header:SetText("Reminder Icons")
    header:SetTextColor(1, 0.82, 0, 1)

    -- Apply callback — reads all boxes, writes to DB, refreshes
    local function Apply()
        if pf._applying then return end
        if _G.MSUF__UndoRestoring then return end
        pf._applying = true

        pcall(function()
            -- Undo
            if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
                _G.MSUF_EM_UndoBeforeChange("aura", "player")
            end

            local ox = tonumber(pf._rowX and pf._rowX.box:GetText()) or 0
            local oy = tonumber(pf._rowY and pf._rowY.box:GetText()) or 0
            local sz = tonumber(pf._rowSize and pf._rowSize.box:GetText()) or 22
            local sp = tonumber(pf._rowSpacing and pf._rowSpacing.box:GetText()) or 2
            local gr = pf._growth and pf._growth.dropdown._value or "RIGHT"

            -- Clamp
            ox = max(-2000, min(2000, floor(ox + 0.5)))
            oy = max(-2000, min(2000, floor(oy + 0.5)))
            sz = max(10, min(80, floor(sz + 0.5)))
            sp = max(0, min(30, floor(sp + 0.5)))

            _WriteLayout("reminderOffsetX", ox)
            _WriteLayout("reminderOffsetY", oy)
            _WriteLayout("reminderIconSize", sz)
            _WriteLayout("reminderSpacing", sp)
            _WriteLayout("reminderGrowth", gr)

            -- Also write to shared as defaults
            local _, shared = _GetDB()
            if shared then
                shared.reminderOffsetX = ox
                shared.reminderOffsetY = oy
                shared.reminderIconSize = sz
                shared.reminderSpacing = sp
                shared.reminderGrowth = gr
            end

            _ApplyAndRefresh()
        end)
        pf._applying = false
    end

    -- Build numeric rows
    pf._rowX = _CreateNumericRow(pf, "Offset X:", header, -10, Apply)
    pf._rowY = _CreateNumericRow(pf, "Offset Y:", pf._rowX.label, -8, Apply)
    pf._rowSize = _CreateNumericRow(pf, "Icon Size:", pf._rowY.label, -8, Apply)
    pf._rowSpacing = _CreateNumericRow(pf, "Spacing:", pf._rowSize.label, -8, Apply)

    -- Growth dropdown
    pf._growth = _CreateGrowthDropdown(pf, pf._rowSpacing.label, -12, Apply)

    -- Step hint
    local stepHint = pf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stepHint:SetPoint("BOTTOM", pf, "BOTTOM", 0, 14)
    stepHint:SetText("Hold Shift for \194\177 10 steps")
    stepHint:SetTextColor(0.5, 0.5, 0.5, 0.8)

    pf:Hide()
    _popup = pf

    -- Register with edit mode popup system
    local Edit = _G.MSUF_Edit
    if Edit and Edit.Popups and Edit.Popups.Register then
        Edit.Popups.Register(pf)
    end

    return pf
end

-- Sync popup boxes from DB
function Reminder.SyncPopup()
    if not _popup or not _popup:IsShown() then return end
    if _popup._applying then return end

    local _, shared, lay = _GetDB()
    local ox = _ReadVal(shared, lay, "reminderOffsetX", 0)
    local oy = _ReadVal(shared, lay, "reminderOffsetY", 0)
    local sz = _ReadVal(shared, lay, "reminderIconSize", 22)
    local sp = _ReadVal(shared, lay, "reminderSpacing", 2)
    local gr = nil
    if lay and type(lay.reminderGrowth) == "string" then gr = lay.reminderGrowth end
    if not gr and shared and type(shared.reminderGrowth) == "string" then gr = shared.reminderGrowth end
    gr = gr or "RIGHT"

    local function setBox(row, v)
        if row and row.box and not row.box:HasFocus() then
            row.box:SetText(tostring(floor(v + 0.5)))
        end
    end
    setBox(_popup._rowX, ox)
    setBox(_popup._rowY, oy)
    setBox(_popup._rowSize, sz)
    setBox(_popup._rowSpacing, sp)

    -- Sync dropdown
    if _popup._growth and _popup._growth.dropdown then
        _popup._growth.dropdown._value = gr
        for _, opt in ipairs(_GROWTH_OPTIONS) do
            if opt.value == gr then
                UIDropDownMenu_SetText(_popup._growth.dropdown, opt.text)
                break
            end
        end
    end
end

function Reminder.OpenPopup(parent)
    if InCombatLockdown() then return end
    local pf = _EnsurePopup()

    -- Smart positioning: to the right of the mover if possible
    if parent and parent.GetRight then
        local sw = UIParent and UIParent:GetWidth() or 0
        local pr = parent:GetRight() or 0
        local pw = pf:GetWidth() or 300
        pf:ClearAllPoints()
        if (sw - pr) > (pw + 20) then
            pf:SetPoint("TOPLEFT", parent, "TOPRIGHT", 10, 0)
        elseif (parent:GetLeft() or 0) > (pw + 20) then
            pf:SetPoint("TOPRIGHT", parent, "TOPLEFT", -10, 0)
        else
            pf:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        end
    end

    pf:Show()
    Reminder.SyncPopup()
end

function Reminder.HidePopup()
    if _popup and _popup:IsShown() then _popup:Hide() end
end

-- Expose for sync from mover drag
_G.MSUF_SyncReminderPopup = Reminder.SyncPopup

-- =========================================================================
-- Edit Mode Mover — writes reminderOffsetX/Y, opens popup on click
-- =========================================================================
function Reminder.EnsureMover(entry, unit, shared)
    if not entry or unit ~= "player" then return end
    if entry.editMoverReminder then return entry.editMoverReminder end

    local mover = CreateFrame("Frame", "MSUF_A2_player_Mover_reminder", UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetFrameLevel(500)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    if mover.SetHitRectInsets then mover:SetHitRectInsets(-2, -2, -22, -2) end

    mover:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mover:SetBackdropColor(1.00, 0.75, 0.20, 0.12)
    mover:SetBackdropBorderColor(1.00, 0.75, 0.20, 0.55)

    local headerH = 18
    local hdr = CreateFrame("Frame", nil, mover, "BackdropTemplate")
    hdr:SetPoint("TOPLEFT", mover, "TOPLEFT", 2, -2)
    hdr:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -2, -2)
    hdr:SetHeight(headerH)
    hdr:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    hdr:SetBackdropColor(1.0, 0.75, 0.20, 0.22)
    hdr:EnableMouse(true)
    hdr:SetScript("OnMouseDown", function(h, btn) local p = h:GetParent(); local fn = p and p:GetScript("OnMouseDown"); if fn then fn(p, btn) end end)
    hdr:SetScript("OnMouseUp",   function(h, btn) local p = h:GetParent(); local fn = p and p:GetScript("OnMouseUp");   if fn then fn(p, btn) end end)

    local ico = hdr:CreateTexture(nil, "OVERLAY")
    ico:SetSize(14, 14)
    ico:SetPoint("LEFT", hdr, "LEFT", 6, 0)
    ico:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local lbl = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", ico, "RIGHT", 6, 0)
    lbl:SetPoint("RIGHT", hdr, "RIGHT", -6, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetText("Player Reminders")
    lbl:SetTextColor(0.95, 0.95, 0.95, 0.92)

    mover:Hide()
    mover._msufAuraEntry = entry
    mover._msufAuraUnitKey = "player"

    -- Drag state
    local _dragged = false

    local function ApplyDrag(self, dx, dy)
        if InCombatLockdown() then return end
        local sx = self._dragStartOX or 0
        local sy = self._dragStartOY or 0
        local nx = max(-2000, min(2000, floor(sx + dx + 0.5)))
        local ny = max(-2000, min(2000, floor(sy + dy + 0.5)))
        _WriteLayout("reminderOffsetX", nx)
        _WriteLayout("reminderOffsetY", ny)
        _ApplyAndRefresh()
        -- Sync popup if open
        if Reminder.SyncPopup then Reminder.SyncPopup() end
    end

    mover:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if InCombatLockdown() then return end
        _dragged = false

        if not _G.MSUF__UndoRestoring then
            local bc = _G.MSUF_EM_UndoBeforeChange
            if type(bc) == "function" then bc("aura", "player") end
        end

        local _, sh, lay = _GetDB()
        self._dragStartOX = _ReadVal(sh, lay, "reminderOffsetX", 0)
        self._dragStartOY = _ReadVal(sh, lay, "reminderOffsetY", 0)
        local cx, cy = _GetCursorScaled()
        self._dragStartCX = cx
        self._dragStartCY = cy
        self._isDragging = true
    end)

    mover:SetScript("OnUpdate", function(self)
        if not self._isDragging then return end
        local cx, cy = _GetCursorScaled()
        local dx = cx - (self._dragStartCX or cx)
        local dy = cy - (self._dragStartCY or cy)
        if (dx * dx + dy * dy) > 4 then _dragged = true end
        ApplyDrag(self, dx, dy)
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        self._isDragging = false
        if not _G.MSUF__UndoRestoring then
            local ac = _G.MSUF_EM_UndoAfterChange
            if type(ac) == "function" then ac("aura", "player") end
        end
        -- Click without drag: open popup
        if not _dragged then
            Reminder.OpenPopup(self)
        end
    end)

    entry.editMoverReminder = mover
    return mover
end

-- =========================================================================
-- Render: show ghost icons into entry.reminder container
-- =========================================================================
function Reminder.Render(entry, unit, shared, iconSize, spacing, growth, isEditMode)
    if unit ~= "player" then
        if _ghostActive > 0 then _HideGhosts(1); _ghostActive = 0 end
        return
    end

    local container = entry and entry.reminder
    if not container then
        if _ghostActive > 0 then _HideGhosts(1); _ghostActive = 0 end
        return
    end

    local remindersOn = (shared and shared.showReminders ~= false)
    if not remindersOn then
        if _ghostActive > 0 then _HideGhosts(1); _ghostActive = 0 end
        container:Hide()
        return
    end

    if not isEditMode and UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        if _ghostActive > 0 then _HideGhosts(1); _ghostActive = 0 end
        container:Hide()
        return
    end

    local reminders = shared and shared.reminders
    local thr = (shared and type(shared.reminderThreshold) == "number") and shared.reminderThreshold or 0

    -- Read per-icon size/spacing/growth from layout
    local _, sh, lay = _GetDB()
    local remSize    = _ReadVal(sh, lay, "reminderIconSize", iconSize or 22)
    local remSpacing = _ReadVal(sh, lay, "reminderSpacing", spacing or 2)
    local remGrowth  = nil
    if lay and type(lay.reminderGrowth) == "string" then remGrowth = lay.reminderGrowth end
    if not remGrowth and sh and type(sh.reminderGrowth) == "string" then remGrowth = sh.reminderGrowth end
    remGrowth = remGrowth or growth or "RIGHT"

    _ComputeMissing(reminders, thr, isEditMode)

    if _resultCount < _ghostActive then
        _HideGhosts(_resultCount + 1)
    end
    _ghostActive = _resultCount

    if _resultCount == 0 then
        container:Hide()
        return
    end
    container:Show()

    local size = remSize
    local gap = remSpacing
    local growDir = remGrowth

    for i = 1, _resultCount do
        local r = _results[i]
        local p = r.provider
        local ghost = _AcquireGhost(container, i)
        ghost:SetSize(size, size)
        ghost._result = r
        ghost._isPreview = isEditMode or false

        ghost:ClearAllPoints()
        local col = i - 1
        if growDir == "RIGHT" then
            ghost:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", col * (size + gap), 0)
        elseif growDir == "LEFT" then
            ghost:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(col * (size + gap)), 0)
        elseif growDir == "UP" then
            ghost:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, col * (size + gap))
        elseif growDir == "DOWN" then
            ghost:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(col * (size + gap)))
        end

        if not p._cachedIcon then p._cachedIcon = _GetIcon(p.iconSpell) end
        ghost._tex:SetTexture(p._cachedIcon)
        ghost._tex:SetDesaturated(true)

        if isEditMode then
            ghost:SetAlpha(0.7)
            ghost._badge:SetColorTexture(0.3, 0.5, 0.9, 0.9)
            ghost._bang:SetText("?")
            ghost._timer:Hide()
        elseif r.state == "EXPIRING" then
            ghost:SetAlpha(0.65)
            ghost._badge:SetColorTexture(1.0, 0.6, 0.1, 0.9)
            ghost._bang:SetText("!")
            ghost._timer:SetText(_FormatTime(r.remaining))
            ghost._timer:Show()
        else
            ghost:SetAlpha(0.55)
            ghost._badge:SetColorTexture(0.85, 0.12, 0.12, 0.9)
            ghost._bang:SetText("!")
            ghost._timer:Hide()
        end
    end
end

-- =========================================================================
-- Events
-- =========================================================================
local _eventFrame = CreateFrame("Frame")
_eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
_eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
_eventFrame:SetScript("OnEvent", function()
    _ScanRoster()
    if API.MarkDirty then API.MarkDirty("player") end
end)

if UnitExists("player") then _ScanRoster() end
