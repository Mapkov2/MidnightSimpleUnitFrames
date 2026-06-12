--- Shared legacy style compatibility.
--- Menu2 and EM2 popups now use their own cold-path widget/theme layers. This
--- file keeps the old public style globals available without installing global
--- frame scanners, dropdown hooks, or addon-load reskin events.
local addonName, MSUF = ...
if type(MSUF) ~= "table" then MSUF = {} end
_G.MSUF_NS = _G.MSUF_NS or MSUF

MSUF.Style = MSUF.Style or {}
local Style = MSUF.Style
local WHITE8X8 = "Interface/Buttons/WHITE8X8"

local THEME = _G.MSUF_THEME or {}
_G.MSUF_THEME = THEME
THEME.tex = THEME.tex or WHITE8X8
THEME.bgR, THEME.bgG, THEME.bgB, THEME.bgA = 0.03, 0.05, 0.12, 0.95
THEME.edgeR, THEME.edgeG, THEME.edgeB, THEME.edgeA = 0.10, 0.20, 0.45, 0.90
THEME.edgeThinR, THEME.edgeThinG, THEME.edgeThinB, THEME.edgeThinA = 0.10, 0.20, 0.45, 0.95
THEME.titleR, THEME.titleG, THEME.titleB, THEME.titleA = 0.75, 0.88, 1.00, 1.00
THEME.textR, THEME.textG, THEME.textB, THEME.textA = 0.86, 0.92, 1.00, 1.00
THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA = 0.69, 0.74, 0.80, 0.85
THEME.btnR, THEME.btnG, THEME.btnB, THEME.btnA = 0.07, 0.09, 0.14, 0.95
THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.btnHoverA = 0.30, 0.60, 1.00, 0.16
THEME.btnDownR, THEME.btnDownG, THEME.btnDownB, THEME.btnDownA = 0.30, 0.60, 1.00, 0.22
THEME.btnDisabledR, THEME.btnDisabledG, THEME.btnDisabledB, THEME.btnDisabledA = 0.45, 0.45, 0.45, 0.35
THEME.navHoverA, THEME.navSelectedA, THEME.navDownA = 0.14, 0.24, 0.20

_G.MSUF_Style = _G.MSUF_Style or Style
_G.MSUF_STYLE = _G.MSUF_STYLE or Style
_G.__MSUF_STYLE_VERSION = 6
_G.__MSUF_STYLE_TAG = "menu2-legacy-compat-cold"

local function GetDB()
    local db = rawget(_G, "MSUF_DB")
    if type(db) == "table" then return db end
    if type(MSUF) == "table" and type(MSUF.MSUF_DB) == "table" then return MSUF.MSUF_DB end
    return nil
end

function Style.IsEnabled()
    local db = GetDB()
    if db and db.general and db.general.styleEnabled ~= nil then
        return db.general.styleEnabled and true or false
    end
    return true
end

function Style.SetEnabled(enabled)
    local db = GetDB()
    if db then
        db.general = db.general or {}
        db.general.styleEnabled = enabled and true or false
    end
    if enabled then
        Style.ScanAndSkinEditMode()
        Style.ApplyPeelOptionsSkin()
    end
end

function Style.UseModernDropdowns()
    return true
end

local function SafeTextColor(fs, r, g, b, a)
    if fs and fs.SetTextColor then fs:SetTextColor(r, g, b, a) end
end

function Style.SkinTitle(fs)
    if Style.IsEnabled() then SafeTextColor(fs, THEME.titleR, THEME.titleG, THEME.titleB, THEME.titleA) end
    return fs
end

function Style.SkinText(fs)
    if Style.IsEnabled() then SafeTextColor(fs, THEME.textR, THEME.textG, THEME.textB, THEME.textA) end
    return fs
end

function Style.SkinMuted(fs)
    if Style.IsEnabled() then SafeTextColor(fs, THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA) end
    return fs
end

local function EnsureBackdropFrame(frame)
    if not (frame and CreateFrame) then return nil end
    if frame._msufMidnightBackdrop then return frame._msufMidnightBackdrop end
    local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    b:SetAllPoints(frame)
    local level = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
    if b.SetFrameLevel then b:SetFrameLevel(math.max(0, level - 1)) end
    if frame.GetFrameStrata and b.SetFrameStrata then b:SetFrameStrata(frame:GetFrameStrata()) end
    frame._msufMidnightBackdrop = b
    return b
end

function Style.ApplyBackdrop(frame, alphaOverride, thinBorder)
    if not Style.IsEnabled() then return frame end
    local b = EnsureBackdropFrame(frame)
    if not (b and b.SetBackdrop) then return frame end
    b:SetBackdrop({
        bgFile = WHITE8X8,
        edgeFile = WHITE8X8,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    b:SetBackdropColor(THEME.bgR, THEME.bgG, THEME.bgB, alphaOverride or THEME.bgA)
    local er, eg, eb, ea = THEME.edgeR, THEME.edgeG, THEME.edgeB, THEME.edgeA
    if thinBorder then er, eg, eb, ea = THEME.edgeThinR, THEME.edgeThinG, THEME.edgeThinB, THEME.edgeThinA end
    b:SetBackdropBorderColor(er, eg, eb, ea)
    b:Show()
    return frame
end

local function KillTexture(tex)
    if tex and tex.Hide then
        tex:Hide()
        if tex.SetTexture then tex:SetTexture(nil) end
    end
end

local function EnsureOverlay(btn, key, layer, r, g, b, a)
    if not (btn and btn.CreateTexture) then return nil end
    local tex = btn[key]
    if not tex then
        tex = btn:CreateTexture(nil, layer or "BORDER")
        tex:SetAllPoints(btn)
        btn[key] = tex
    end
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) end
    return tex
end

local function ButtonLabel(btn)
    if not btn then return nil end
    local fs = btn.GetFontString and btn:GetFontString()
    if fs then return fs end
    return btn.Text or btn.text or btn._label or btn._msuf2Label
end

local function RefreshButtonState(btn)
    local enabled = not (btn.IsEnabled and not btn:IsEnabled())
    local label = ButtonLabel(btn)
    if label then
        if enabled then Style.SkinText(label) else SafeTextColor(label, THEME.mutedR, THEME.mutedG, THEME.mutedB, 0.70) end
    end
    if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.65) end
end

function Style.SkinButton(btn, opts)
    if not (Style.IsEnabled() and btn) then return btn end
    if btn._msufNoSlashSkin or btn.__msufMidnightActionSkinned or btn.__msufMidnightTabSkinned then return btn end
    if btn.__msufMidnightSkinned then
        RefreshButtonState(btn)
        return btn
    end
    btn.__msufMidnightSkinned = true
    KillTexture(btn.Left)
    KillTexture(btn.Middle)
    KillTexture(btn.Right)
    if btn.GetNormalTexture then KillTexture(btn:GetNormalTexture()) end
    if btn.GetPushedTexture then KillTexture(btn:GetPushedTexture()) end
    if btn.GetHighlightTexture then KillTexture(btn:GetHighlightTexture()) end
    if btn.GetDisabledTexture then KillTexture(btn:GetDisabledTexture()) end
    Style.ApplyBackdrop(btn, 0.88, true)
    local hover = EnsureOverlay(btn, "_msufBtnHover", "BORDER", THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, opts and opts.isNav and THEME.navHoverA or THEME.btnHoverA)
    local down = EnsureOverlay(btn, "_msufBtnDown", "BORDER", THEME.btnDownR, THEME.btnDownG, THEME.btnDownB, opts and opts.isNav and THEME.navDownA or THEME.btnDownA)
    if hover then hover:Hide() end
    if down then down:Hide() end
    if btn.HookScript then
        btn:HookScript("OnEnter", function(self) if self._msufBtnHover then self._msufBtnHover:Show() end end)
        btn:HookScript("OnLeave", function(self)
            if self._msufBtnHover then self._msufBtnHover:Hide() end
            if self._msufBtnDown then self._msufBtnDown:Hide() end
        end)
        btn:HookScript("OnMouseDown", function(self) if self._msufBtnDown then self._msufBtnDown:Show() end end)
        btn:HookScript("OnMouseUp", function(self) if self._msufBtnDown then self._msufBtnDown:Hide() end end)
    end
    RefreshButtonState(btn)
    return btn
end

function Style.SkinDropButton(btn, opts) return Style.SkinButton(btn, opts) end
function Style.SkinIconButton(btn, opts) return Style.SkinButton(btn, opts) end

function Style.SkinNavButton(btn, opts)
    Style.SkinButton(btn, { isNav = true })
    if btn then
        btn._msufSetActive = function(self, active)
            self._msufNavIsActive = active and true or false
            if self._msufBtnDown then self._msufBtnDown:SetShown(self._msufNavIsActive) end
        end
        local label = ButtonLabel(btn)
        if label then
            if opts and opts.header then Style.SkinTitle(label) else Style.SkinText(label) end
        end
    end
    return btn
end

function Style.SkinDashboardButton(btn)
    Style.SkinNavButton(btn)
    if btn then
        btn._msufSetSelected = function(self, selected)
            if self._msufSetActive then self:_msufSetActive(selected) end
        end
    end
    return btn
end

function Style.ApplyToFrame(root)
    if not (Style.IsEnabled() and root and root.GetChildren) then return root end
    local function Walk(frame)
        if not (frame and frame.GetChildren) then return end
        local children = { frame:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            if child and child.IsObjectType then
                if child:IsObjectType("Button") then
                    Style.SkinButton(child)
                elseif child:IsObjectType("EditBox") then
                    Style.ApplyBackdrop(child, 0.96, true)
                elseif child:IsObjectType("CheckButton") then
                    local label = ButtonLabel(child)
                    if label then Style.SkinText(label) end
                end
            end
            Walk(child)
        end
    end
    Walk(root)
    return root
end

function Style.SkinEditModePopupFrame(frame)
    Style.ApplyBackdrop(frame)
    return Style.ApplyToFrame(frame)
end

function Style.ScanAndSkinEditMode()
    for _, name in ipairs({
        "MSUF_EM2_UnitPopup",
        "MSUF_EM2_CastPopup",
        "MSUF_EM2_AuraPopup",
    }) do
        local frame = rawget(_G, name)
        if frame then Style.SkinEditModePopupFrame(frame) end
    end
end

function Style.InstallEditModeAutoSkin() end
function Style.InstallStandaloneOptionsAutoSkin() end

local function DropdownNoop(drop)
    if drop then drop.__msufMSUFDropdown = true end
    return drop
end

function Style.ApplyPeelDropdownTemplate(drop) return DropdownNoop(drop) end
Style.SkinUIDDropDownTinyBars = Style.ApplyPeelDropdownTemplate
Style.RevertPeelDropdownTemplate = DropdownNoop
Style.ReskinDropdownLists = function() end
function Style.RefreshDropdownSkinMode() return Style.ReskinDropdownLists() end
function Style.QueueDropdownStyleMode() return "msuf" end
Style.SetDropdownStyleMode = Style.QueueDropdownStyleMode
Style.ApplyDropdownStyleModeImmediate = Style.QueueDropdownStyleMode

function Style.ApplyOptionCheckmarks(root)
    return Style.ApplyToFrame(root or _G.UIParent)
end

local function SkinStandaloneWindow()
    local win = rawget(_G, "MSUF_StandaloneOptionsWindow")
    if not win then return end
    Style.ApplyBackdrop(win, 1.0)
    if win._msufNavRail then Style.ApplyBackdrop(win._msufNavRail, 0.22) end
    if win._msufMirrorHost then Style.ApplyToFrame(win._msufMirrorHost) end
    if win._msufNavStack then Style.ApplyToFrame(win._msufNavStack) end
    Style.ApplyToFrame(win)
    if win._msufTitleFS then Style.SkinTitle(win._msufTitleFS) end
end
Style.ApplyPeelOptionsSkin = SkinStandaloneWindow

local DROPDOWN_COMPAT_DEFAULTS = {}
MSUF.MSUF_PeelDropdownDefaults = DROPDOWN_COMPAT_DEFAULTS
_G.MSUF_PeelDropdownDefaults = DROPDOWN_COMPAT_DEFAULTS
MSUF.MSUF_CreateStyledDropdown = function(name, parent)
    return CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
end
_G.MSUF_CreateStyledDropdown = MSUF.MSUF_CreateStyledDropdown
MSUF.MSUF_PeelDropdownTemplate = Style.ApplyPeelDropdownTemplate
_G.MSUF_PeelDropdownTemplate = Style.ApplyPeelDropdownTemplate
MSUF.MSUF_RevertDropdownTemplate = DropdownNoop
_G.MSUF_RevertDropdownTemplate = DropdownNoop
MSUF.MSUF_ReskinDropdownLists = Style.ReskinDropdownLists
_G.MSUF_ReskinDropdownLists = Style.ReskinDropdownLists
MSUF.MSUF_RefreshDropdownSkinMode = Style.RefreshDropdownSkinMode
_G.MSUF_RefreshDropdownSkinMode = Style.RefreshDropdownSkinMode
_G.MSUF_SetDropdownStyleMode = Style.SetDropdownStyleMode
_G.MSUF_QueueDropdownStyleMode = Style.QueueDropdownStyleMode
_G.MSUF_ApplyDropdownStyleModeImmediate = Style.ApplyDropdownStyleModeImmediate
MSUF.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
_G.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
MSUF.MSUF_ApplyPeelOptionsSkin = SkinStandaloneWindow
_G.MSUF_ApplyPeelOptionsSkin = SkinStandaloneWindow

_G.MSUF_StyleIsEnabled = function() return Style.IsEnabled() end
_G.MSUF_SetStyleEnabled = function(v) return Style.SetEnabled(v) end
_G.MSUF_GetDropdownStyleMode = function() return "msuf" end
_G.MSUF_ApplyMidnightBackdrop = function(frame, alphaOverride, thinBorder) return Style.ApplyBackdrop(frame, alphaOverride, thinBorder) end
_G.MSUF_SkinTitle = function(fs) return Style.SkinTitle(fs) end
_G.MSUF_SkinText = function(fs) return Style.SkinText(fs) end
_G.MSUF_SkinMuted = function(fs) return Style.SkinMuted(fs) end
_G.MSUF_SkinButton = function(btn, opts) return Style.SkinButton(btn, opts) end
_G.MSUF_SkinNavButton = function(btn, isHeader, isIndented) return Style.SkinNavButton(btn, { header = isHeader, indented = isIndented }) end
_G.MSUF_SkinDashboardButton = function(btn) return Style.SkinDashboardButton(btn) end
_G.MSUF_ApplyMidnightControlsToFrame = function(root) return Style.ApplyToFrame(root) end
