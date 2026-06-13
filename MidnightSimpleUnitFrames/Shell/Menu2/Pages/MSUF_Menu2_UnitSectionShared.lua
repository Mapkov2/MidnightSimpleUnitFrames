local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local T = M.Theme or {}
local Shared = M.UnitSectionsShared or {}
M.UnitSectionsShared = Shared

-- Shared helpers for Unit page sections.
-- Provides common warning notices, name-anchor filtering, badges, and small UI adapters used
-- by text/status/visual subpages without coupling them to each other's internals.
local CreateFrame = _G.CreateFrame
local pairs = pairs
local tostring = tostring
local type = type

local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_NOTICE_BG = { 0.105, 0.082, 0.052, 0.34 }
local WARNING_NOTICE_TOP = { 0.48, 0.36, 0.20, 0.55 }
local WARNING_NOTICE_BOTTOM = { 0.28, 0.21, 0.12, 0.48 }

local function IsNameRelativeAnchor(value)
    return value == "NAMERIGHT" or value == "NAMELEFT"
end

local DISABLED_NAME_ANCHOR_VALUE_CACHE = setmetatable({}, { __mode = "k" })

function Shared.DisabledNameAnchorValues(values)
    if type(values) ~= "table" then return {} end
    local cached = DISABLED_NAME_ANCHOR_VALUE_CACHE[values]
    if cached then return cached end

    local out = {}
    for i = 1, #(values or {}) do
        local item = values[i]
        if type(item) == "table" then
            local value = item.value or item.key or item[2] or item[1]
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy.disabled = IsNameRelativeAnchor(value)
            out[#out + 1] = copy
        else
            out[#out + 1] = item
        end
    end
    DISABLED_NAME_ANCHOR_VALUE_CACHE[values] = out
    return out
end

function Shared.SetSectionHeaderStatus(sec, opts)
    local entry = sec and sec._msuf2CollapsibleEntry
    if not entry then return end

    if T.ApplyCollapseVisual then T.ApplyCollapseVisual(entry.arrow, entry.hint, entry.open) end

    if entry.headerBg and entry.headerBg.SetColorTexture then
        entry.headerBg:SetColorTexture(0.040, 0.050, 0.088, entry.open and 0.40 or 0.34)
    end
    if entry.label and entry.label.SetTextColor and T and T.colors and T.colors.text then
        local c = T.colors.text
        entry.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    opts = opts or {}
    if opts.bg and entry.headerBg and entry.headerBg.SetColorTexture then
        local bg = opts.bg
        entry.headerBg:SetColorTexture(bg[1] or 0.060, bg[2] or 0.070, bg[3] or 0.130, bg[4] or 0.48)
    end
    if opts.labelColor and entry.label and entry.label.SetTextColor then
        local c = opts.labelColor
        entry.label:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if opts.arrowColor and entry.arrow and entry.arrow.SetVertexColor then
        local c = opts.arrowColor
        entry.arrow:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if entry.hint and entry.hint.SetText then
        if opts.hint ~= nil then
            entry.hint:SetText(opts.hint)
            if opts.hintColor and entry.hint.SetTextColor then
                local c = opts.hintColor
                entry.hint:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
        else
            if T.ApplyCollapseVisual then T.ApplyCollapseVisual(entry.arrow, entry.hint, entry.open) end
        end
    end
end

function Shared.CreateSectionNotice(sec, topY, buttonLabel, buttonWidth, gateKey)
    local notice = CreateFrame("Frame", nil, sec)
    notice:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, topY)
    notice:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, topY)
    notice:SetHeight(24)
    gateKey = gateKey or "_msuf2UnitFrameGateAlwaysEnabled"
    notice[gateKey] = true

    local bg = notice:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.018, 0.040, 0.088, 0.30)
    local top = notice:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(0.16, 0.34, 0.66, 0.55)
    local bottom = notice:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(0.10, 0.20, 0.38, 0.48)

    local text = T.Font(notice, "GameFontDisableSmall", "", T.colors.dim)
    text:SetPoint("LEFT", notice, "LEFT", 10, 0)
    text:SetJustifyH("LEFT")

    local button
    if buttonLabel and buttonLabel ~= "" then
        button = (W.StyleTopActionButton and W.StyleTopActionButton(T.Button(notice, buttonLabel, buttonWidth or 92, 20))) or T.Button(notice, buttonLabel, buttonWidth or 92, 20)
        button:SetPoint("RIGHT", notice, "RIGHT", -2, 0)
        button[gateKey] = true
        text:SetPoint("RIGHT", notice, "RIGHT", -(buttonWidth or 92) - 18, 0)
    else
        text:SetPoint("RIGHT", notice, "RIGHT", -10, 0)
    end

    function notice:SetTone(kind)
        if kind == "warning" then
            bg:SetColorTexture(WARNING_NOTICE_BG[1], WARNING_NOTICE_BG[2], WARNING_NOTICE_BG[3], WARNING_NOTICE_BG[4])
            top:SetColorTexture(WARNING_NOTICE_TOP[1], WARNING_NOTICE_TOP[2], WARNING_NOTICE_TOP[3], WARNING_NOTICE_TOP[4])
            bottom:SetColorTexture(WARNING_NOTICE_BOTTOM[1], WARNING_NOTICE_BOTTOM[2], WARNING_NOTICE_BOTTOM[3], WARNING_NOTICE_BOTTOM[4])
            if text.SetTextColor then text:SetTextColor(WARNING_HINT[1], WARNING_HINT[2], WARNING_HINT[3], WARNING_HINT[4]) end
        else
            bg:SetColorTexture(0.018, 0.040, 0.088, 0.30)
            top:SetColorTexture(0.16, 0.34, 0.66, 0.55)
            bottom:SetColorTexture(0.10, 0.20, 0.38, 0.48)
            if text.SetTextColor and T.colors and T.colors.dim then
                text:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1)
            end
        end
    end

    function notice:SetMessage(message, tone)
        self:SetTone(tone)
        text:SetText(tostring(message or ""))
    end

    notice:Hide()
    return notice, text, button
end

function Shared.MakeTabFrame(parent, key, topOffset, width, store)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, topOffset or -118)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 12)
    frame._msuf2Width = width
    if store and key then store[key] = frame end
    return frame
end

function Shared.MakeDragSortRows(parent, defs, opts)
    opts = opts or {}
    defs = defs or {}
    local rowW, rowH, rowGap = opts.width or 220, opts.rowHeight or 22, opts.gap or 4
    local rowCount = opts.maxRows or #defs
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x or 0, opts.y or 0)
    holder:SetSize(rowW, rowCount * (rowH + rowGap))
    holder.rows, holder._enabled, holder._activeCount = {}, true, rowCount

    local function SlotY(slot) return -((slot - 1) * (rowH + rowGap)) end
    function holder:SnapRows()
        local active = self._activeCount or rowCount
        for i = 1, #self.rows do
            local row = self.rows[i]
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, SlotY(row.slotIndex))
            if row.frame._numText then row.frame._numText:SetText(tostring(row.slotIndex)) end
            if i <= active then row.frame:Show() else row.frame:Hide() end
        end
        self:SetHeight(active * (rowH + rowGap))
    end
    function holder:SetActiveCount(count)
        self._activeCount = math.max(0, math.min(rowCount, tonumber(count) or rowCount))
        self:SnapRows()
    end
    function holder:SetRowsEnabled(enabled)
        self._enabled = enabled and true or false
        for i = 1, #self.rows do
            local row = self.rows[i]
            local frame = row.frame
            frame:SetAlpha(self._enabled and (opts.enabledAlpha or 1) or (opts.disabledAlpha or 0.42))
            frame:EnableMouse(self._enabled)
            if frame._label and frame._label.SetTextColor then
                local c = self._enabled and (opts.enabledLabelColor or T.colors.text) or (opts.disabledLabelColor or T.colors.dim)
                frame._label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
            end
        end
    end

    local function DragAllowed(row) return holder._enabled and (not opts.dragAllowed or opts.dragAllowed(row, holder) ~= false) end
    local function OnEnter(self)
        local row = self._msuf2DragRow
        if not DragAllowed(row) then return end
        if self.SetBackdropBorderColor then
            local c = opts.hoverBorder or { 0.380, 0.550, 0.900, 0.95 }
            self:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
        end
        if opts.tooltip and _G.GameTooltip then opts.tooltip(self, row, _G.GameTooltip) end
    end
    local function OnLeave(self)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
        if self.SetBackdropBorderColor then
            local c = opts.border or { 0.210, 0.230, 0.300, 0.78 }
            self:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
    local function OnDragStart(self)
        local row = self._msuf2DragRow
        if not DragAllowed(row) then return end
        if _G.GameTooltip then _G.GameTooltip:Hide() end
        self._msuf2OldStrata = self.GetFrameStrata and self:GetFrameStrata() or nil
        if self.SetFrameStrata then self:SetFrameStrata("TOOLTIP") end
        self:StartMoving()
    end
    local function OnDragStop(self)
        local row = self._msuf2DragRow
        if not row then return end
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
        if self.SetFrameStrata and self._msuf2OldStrata then self:SetFrameStrata(self._msuf2OldStrata) end

        local _, centerY = self:GetCenter()
        local top = holder:GetTop()
        local active, bestSlot, bestDist = holder._activeCount or rowCount, 1, math.huge
        if centerY and top then
            for slot = 1, active do
                local dist = math.abs(centerY - (top + SlotY(slot) - (rowH * 0.5)))
                if dist < bestDist then bestDist, bestSlot = dist, slot end
            end
        end

        local changed = row.slotIndex ~= bestSlot
        if changed then
            for i = 1, #holder.rows do
                if holder.rows[i] ~= row and holder.rows[i].slotIndex == bestSlot then
                    holder.rows[i].slotIndex = row.slotIndex
                    break
                end
            end
            row.slotIndex = bestSlot
        end
        holder:SnapRows()
        if (changed or opts.saveAlways) and opts.onReorder then opts.onReorder(holder.rows, holder) end
    end

    for i = 1, rowCount do
        local def = defs[i] or {}
        local frame = CreateFrame("Frame", nil, holder, T.Template and T.Template() or nil)
        frame:SetSize(rowW, rowH)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if frame.SetBackdrop then
            local bg, border = opts.bg or { 0.055, 0.060, 0.075, 0.88 }, opts.border or { 0.210, 0.230, 0.300, 0.78 }
            frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        end
        local stripe = frame:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("LEFT", frame, "LEFT", 2, 0)
        stripe:SetSize(4, rowH - 2)
        stripe:SetColorTexture(def.r or 0.30, def.g or 0.55, def.b or 0.85, 1)
        frame._stripe = stripe
        local label = T.Font(frame, "GameFontHighlightSmall", def.label or "", T.colors.text)
        label:SetPoint("LEFT", stripe, "RIGHT", opts.labelOffsetX or 7, 0)
        label:SetJustifyH("LEFT")
        frame._label = label
        local number = T.Font(frame, "GameFontNormalSmall", tostring(i), T.colors.dim)
        number:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
        number:SetJustifyH("RIGHT")
        frame._numText = number
        frame:SetScript("OnEnter", OnEnter)
        frame:SetScript("OnLeave", OnLeave)
        frame:SetScript("OnDragStart", OnDragStart)
        frame:SetScript("OnDragStop", OnDragStop)
        local row = { frame = frame, key = def.key or "", slotIndex = i, def = def }
        frame._msuf2DragRow, holder.rows[i] = row, row
    end

    holder:SnapRows()
    return holder
end
