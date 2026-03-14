local addonName, ns = ...
ns = ns or _G.MSUF_NS or {}
_G.MSUF_NS = ns

local F = (ns.Cache and ns.Cache.F) or {}
local UnitExists = F.UnitExists or _G.UnitExists

local function GetToTFrame()
    local unitFrames = _G.MSUF_UnitFrames or _G.UnitFrames
    return unitFrames and unitFrames["targettarget"] or nil
end

local function MarkToTDirty()
    local tot = GetToTFrame()
    if tot then tot._msufToTDirty = true end
end

local function TryUpdateToT(force)
    local tot = GetToTFrame()
    if not (tot and tot.IsShown and tot:IsShown()) then return end
    if ns.UF and ns.UF.IsDisabled then
        local conf = _G.MSUF_DB and _G.MSUF_DB.targettarget
        if ns.UF.IsDisabled(conf) then return end
    end
    if not (UnitExists and UnitExists("targettarget")) then return end
    if not force and not tot._msufToTDirty then return end
    tot._msufToTDirty = false
    if ns.UF and ns.UF.RequestUpdate then
        ns.UF.RequestUpdate(tot, true, false, "ToTDirty")
    end
end

local function EnsureTargetToTInlineFS(targetFrame)
    if not (targetFrame and targetFrame.nameText) then return end
    if targetFrame._msufToTInlineText and targetFrame._msufToTInlineSep then return end
    local parent = targetFrame.textFrame or targetFrame
    local sep = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sep:SetJustifyH("LEFT")
    sep:SetJustifyV("MIDDLE")
    sep:SetWordWrap(false)
    if sep.SetNonSpaceWrap then sep:SetNonSpaceWrap(false) end
    sep:SetText(" | ")
    local txt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetJustifyH("LEFT")
    txt:SetJustifyV("MIDDLE")
    txt:SetWordWrap(false)
    if txt.SetNonSpaceWrap then txt:SetNonSpaceWrap(false) end
    sep:ClearAllPoints()
    sep:SetPoint("LEFT", targetFrame.nameText, "RIGHT", 0, 0)
    txt:ClearAllPoints()
    txt:SetPoint("LEFT", sep, "RIGHT", 0, 0)
    local nameFS = targetFrame.nameText
    if nameFS and nameFS.GetFont then
        local font, size, flags = nameFS:GetFont()
        if font then
            sep:SetFont(font, size, flags)
            txt:SetFont(font, size, flags)
            sep._msufFontRev = nil
            txt._msufFontRev = nil
        end
    end
    targetFrame._msufToTInlineSep = sep
    targetFrame._msufToTInlineText = txt
end

function MSUF_RuntimeUpdateTargetToTInline(targetFrame)
    if not (targetFrame and targetFrame.nameText) then return end
    if not _G.MSUF_DB and type(_G.EnsureDB) == "function" then _G.EnsureDB() end
    if not _G.MSUF_DB then return end
    if type(_G.MSUF_DB.targettarget) ~= "table" then _G.MSUF_DB.targettarget = {} end
    if _G.MSUF_DB.targettarget.showToTInTargetName == nil and type(_G.MSUF_DB.target) == "table" and _G.MSUF_DB.target.showToTInTargetName ~= nil then
        _G.MSUF_DB.targettarget.showToTInTargetName = (_G.MSUF_DB.target.showToTInTargetName and true) or false
    end
    if _G.MSUF_DB.targettarget.totInlineSeparator == nil and type(_G.MSUF_DB.target) == "table" and type(_G.MSUF_DB.target.totInlineSeparator) == "string" then
        _G.MSUF_DB.targettarget.totInlineSeparator = _G.MSUF_DB.target.totInlineSeparator
    end
    if type(_G.MSUF_DB.targettarget.totInlineSeparator) ~= "string" or _G.MSUF_DB.targettarget.totInlineSeparator == "" then
        _G.MSUF_DB.targettarget.totInlineSeparator = "|"
    end
    EnsureTargetToTInlineFS(targetFrame)
    local totConf = _G.MSUF_DB.targettarget
    if ns.Text and ns.Text.RenderToTInline then
        ns.Text.RenderToTInline(targetFrame, totConf)
    end
end
_G.MSUF_RuntimeUpdateTargetToTInline = MSUF_RuntimeUpdateTargetToTInline

function MSUF_UpdateTargetToTInlineNow()
    local unitFrames = _G.MSUF_UnitFrames or _G.UnitFrames
    local targetFrame = unitFrames and unitFrames.target or nil
    if not targetFrame then return end
    MSUF_RuntimeUpdateTargetToTInline(targetFrame)
end
_G.MSUF_UpdateTargetToTInlineNow = MSUF_UpdateTargetToTInlineNow

local _queued = false
local function FlushInlineRefresh()
    _queued = false
    _G.MSUF_UpdateTargetToTInlineNow()
end

function ns.MSUF_ToTInline_RequestRefresh()
    if _queued then return end
    _queued = true
    C_Timer.After(0, FlushInlineRefresh)
end
_G.MSUF_ToTInline_RequestRefresh = ns.MSUF_ToTInline_RequestRefresh

local function StopToTFallbackTicker()
    local t = _G.MSUF_ToTFallbackTicker
    if t and t.Cancel then t:Cancel() end
    _G.MSUF_ToTFallbackTicker = nil
end

function _G.MSUF_EnsureToTFallbackTicker()
    StopToTFallbackTicker()
end
