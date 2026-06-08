local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets or {}
local T = M.Theme or {}
local Shared = M.UnitSectionsShared or {}
M.UnitSectionsShared = Shared

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
