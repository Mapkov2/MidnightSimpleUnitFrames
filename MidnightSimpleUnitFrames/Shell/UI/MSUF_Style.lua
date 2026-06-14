--- Shared legacy style compatibility.
--- Menu2 and EM2 now own their visual systems through MSUF.UI and Menu2 theme.
--- This file intentionally stays small: it preserves the old public globals
--- while delegating all actual chrome work to the central UI layer.
local addonName, MSUF = ...
if type(MSUF) ~= "table" then MSUF = {} end
_G.MSUF = _G.MSUF or MSUF

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

MSUF.Style = MSUF.Style or {}
local Style = MSUF.Style
local UI = MSUF.UI or _G.MSUF_UI or {}
MSUF.UI = UI
ExportPublic("MSUF_UI", UI)

local WHITE8X8 = "Interface/Buttons/WHITE8X8"
local THEME = _G.MSUF_THEME or {}
ExportPublic("MSUF_THEME", THEME)
THEME.tex = THEME.tex or WHITE8X8

--- Keep legacy scalar colors for old external macros/addons. Runtime UI uses
--- table colors through MSUF.UI/Menu2, so these values are compatibility data.
local LEGACY_COLORS = {
    bg = { "bgR", "bgG", "bgB", "bgA", 0.03, 0.05, 0.12, 0.95 },
    edge = { "edgeR", "edgeG", "edgeB", "edgeA", 0.10, 0.20, 0.45, 0.90 },
    edgeThin = { "edgeThinR", "edgeThinG", "edgeThinB", "edgeThinA", 0.10, 0.20, 0.45, 0.95 },
    title = { "titleR", "titleG", "titleB", "titleA", 0.75, 0.88, 1.00, 1.00 },
    text = { "textR", "textG", "textB", "textA", 0.86, 0.92, 1.00, 1.00 },
    muted = { "mutedR", "mutedG", "mutedB", "mutedA", 0.69, 0.74, 0.80, 0.85 },
    btn = { "btnR", "btnG", "btnB", "btnA", 0.07, 0.09, 0.14, 0.95 },
    btnHover = { "btnHoverR", "btnHoverG", "btnHoverB", "btnHoverA", 0.30, 0.60, 1.00, 0.16 },
    btnDown = { "btnDownR", "btnDownG", "btnDownB", "btnDownA", 0.30, 0.60, 1.00, 0.22 },
    btnDisabled = { "btnDisabledR", "btnDisabledG", "btnDisabledB", "btnDisabledA", 0.45, 0.45, 0.45, 0.35 },
}
for _, spec in pairs(LEGACY_COLORS) do
    for i = 1, 4 do
        if THEME[spec[i]] == nil then THEME[spec[i]] = spec[i + 4] end
    end
end
THEME.navHoverA, THEME.navSelectedA, THEME.navDownA = THEME.navHoverA or 0.14, THEME.navSelectedA or 0.24, THEME.navDownA or 0.20

ExportPublic("MSUF_Style", _G.MSUF_Style or Style)
ExportPublic("MSUF_STYLE", _G.MSUF_STYLE or Style)
_G.__MSUF_STYLE_VERSION = 7
_G.__MSUF_STYLE_TAG = "central-ui-compat-cold"

local function GetDB()
    local db = rawget(_G, "MSUF_DB")
    if type(db) == "table" then return db end
    return type(MSUF.MSUF_DB) == "table" and MSUF.MSUF_DB or nil
end

function Style.IsEnabled()
    local db = GetDB()
    local general = db and db.general
    return not (general and general.styleEnabled == false)
end

function Style.SetEnabled(enabled)
    local db = GetDB()
    if db then
        db.general = db.general or {}
        db.general.styleEnabled = enabled and true or false
    end
    if enabled then Style.ApplyPeelOptionsSkin() end
end

function Style.UseModernDropdowns() return true end

local function Color(name)
    if UI.Color then return UI.Color(name, UI.colors and UI.colors[name]) end
    if name == "accent" then return { THEME.titleR, THEME.titleG, THEME.titleB, THEME.titleA } end
    if name == "muted" then return { THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA } end
    return { THEME.textR, THEME.textG, THEME.textB, THEME.textA }
end

local function SetTextColor(fs, color)
    if fs and fs.SetTextColor and color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    return fs
end

function Style.SkinTitle(fs) return Style.IsEnabled() and SetTextColor(fs, Color("accent")) or fs end
function Style.SkinText(fs) return Style.IsEnabled() and SetTextColor(fs, Color("text")) or fs end
function Style.SkinMuted(fs) return Style.IsEnabled() and SetTextColor(fs, Color("muted")) or fs end

function Style.ApplyBackdrop(frame, alphaOverride, thinBorder)
    if not (Style.IsEnabled() and frame) then return frame end
    if UI.ApplyMaterial then
        UI.ApplyMaterial(frame, alphaOverride and alphaOverride >= 0.99 and "popup" or "card")
        return frame
    end
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        frame:SetBackdropColor(THEME.bgR, THEME.bgG, THEME.bgB, alphaOverride or THEME.bgA)
        frame:SetBackdropBorderColor(thinBorder and THEME.edgeThinR or THEME.edgeR, thinBorder and THEME.edgeThinG or THEME.edgeG, thinBorder and THEME.edgeThinB or THEME.edgeB, thinBorder and THEME.edgeThinA or THEME.edgeA)
    end
    return frame
end

function Style.SkinButton(btn, opts)
    if not (Style.IsEnabled() and btn) then return btn end
    if btn._msufNoSlashSkin or btn.__msufMidnightActionSkinned or btn.__msufMidnightTabSkinned then return btn end
    if UI.Button and not btn.__msufMidnightSkinned then
        btn.__msufMidnightSkinned = true
        Style.ApplyBackdrop(btn, 0.88, true)
    end
    local label = btn.GetFontString and btn:GetFontString() or btn.Text or btn.text or btn._label or btn._msuf2Label
    if label then Style.SkinText(label) end
    return btn
end

function Style.SkinDropButton(btn, opts) return Style.SkinButton(btn, opts) end
function Style.SkinIconButton(btn, opts) return Style.SkinButton(btn, opts) end
function Style.SkinNavButton(btn, opts)
    Style.SkinButton(btn, opts)
    if btn and not btn._msufSetActive then
        btn._msufSetActive = function(self, active)
            self._msufNavIsActive = active and true or false
            if self.SetActive then self:SetActive(self._msufNavIsActive) end
        end
    end
    return btn
end
function Style.SkinDashboardButton(btn)
    Style.SkinNavButton(btn)
    if btn and not btn._msufSetSelected then btn._msufSetSelected = function(self, selected) if self._msufSetActive then self:_msufSetActive(selected) end end end
    return btn
end

function Style.ApplyToFrame(root)
    if not (Style.IsEnabled() and root and root.GetChildren) then return root end
    for _, child in ipairs({ root:GetChildren() }) do
        if child and child.IsObjectType then
            if child:IsObjectType("Button") then Style.SkinButton(child)
            elseif child:IsObjectType("EditBox") then Style.ApplyBackdrop(child, 0.96, true)
            elseif child:IsObjectType("CheckButton") then
                local label = child.GetFontString and child:GetFontString() or child.Text or child.text
                if label then Style.SkinText(label) end
            end
        end
        Style.ApplyToFrame(child)
    end
    return root
end

function Style.SkinEditModePopupFrame(frame) Style.ApplyBackdrop(frame); return Style.ApplyToFrame(frame) end
function Style.ScanAndSkinEditMode()
    for _, name in ipairs({ "MSUF_EM2_UnitPopup", "MSUF_EM2_CastPopup", "MSUF_EM2_AuraPopup" }) do
        local frame = rawget(_G, name)
        if frame then Style.SkinEditModePopupFrame(frame) end
    end
end
function Style.InstallEditModeAutoSkin() end
function Style.InstallStandaloneOptionsAutoSkin() end

local function DropdownNoop(drop) if drop then drop.__msufMSUFDropdown = true end; return drop end
function Style.ApplyPeelDropdownTemplate(drop) return DropdownNoop(drop) end
Style.SkinUIDDropDownTinyBars = Style.ApplyPeelDropdownTemplate
Style.RevertPeelDropdownTemplate = DropdownNoop
Style.ReskinDropdownLists = function() end
function Style.RefreshDropdownSkinMode() return Style.ReskinDropdownLists() end
function Style.QueueDropdownStyleMode() return "msuf" end
Style.SetDropdownStyleMode = Style.QueueDropdownStyleMode
Style.ApplyDropdownStyleModeImmediate = Style.QueueDropdownStyleMode
function Style.ApplyOptionCheckmarks(root) return Style.ApplyToFrame(root or _G.UIParent) end

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
ExportPublic("MSUF_PeelDropdownDefaults", DROPDOWN_COMPAT_DEFAULTS)
MSUF.MSUF_CreateStyledDropdown = function(name, parent) return CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate") end
ExportPublic("MSUF_CreateStyledDropdown", MSUF.MSUF_CreateStyledDropdown)
MSUF.MSUF_PeelDropdownTemplate = Style.ApplyPeelDropdownTemplate
ExportPublic("MSUF_PeelDropdownTemplate", Style.ApplyPeelDropdownTemplate)
MSUF.MSUF_RevertDropdownTemplate = DropdownNoop
ExportPublic("MSUF_RevertDropdownTemplate", DropdownNoop)
MSUF.MSUF_ReskinDropdownLists = Style.ReskinDropdownLists
ExportPublic("MSUF_ReskinDropdownLists", Style.ReskinDropdownLists)
MSUF.MSUF_RefreshDropdownSkinMode = Style.RefreshDropdownSkinMode
ExportPublic("MSUF_RefreshDropdownSkinMode", Style.RefreshDropdownSkinMode)
ExportPublic("MSUF_SetDropdownStyleMode", Style.SetDropdownStyleMode)
ExportPublic("MSUF_QueueDropdownStyleMode", Style.QueueDropdownStyleMode)
ExportPublic("MSUF_ApplyDropdownStyleModeImmediate", Style.ApplyDropdownStyleModeImmediate)
MSUF.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
ExportPublic("MSUF_StyleAllToggles", Style.ApplyOptionCheckmarks)
MSUF.MSUF_ApplyPeelOptionsSkin = SkinStandaloneWindow
ExportPublic("MSUF_ApplyPeelOptionsSkin", SkinStandaloneWindow)

ExportPublic("MSUF_StyleIsEnabled", function() return Style.IsEnabled() end)
ExportPublic("MSUF_SetStyleEnabled", function(v) return Style.SetEnabled(v) end)
ExportPublic("MSUF_GetDropdownStyleMode", function() return "msuf" end)
ExportPublic("MSUF_ApplyMidnightBackdrop", function(frame, alphaOverride, thinBorder) return Style.ApplyBackdrop(frame, alphaOverride, thinBorder) end)
ExportPublic("MSUF_SkinTitle", function(fs) return Style.SkinTitle(fs) end)
ExportPublic("MSUF_SkinText", function(fs) return Style.SkinText(fs) end)
ExportPublic("MSUF_SkinMuted", function(fs) return Style.SkinMuted(fs) end)
ExportPublic("MSUF_SkinButton", function(btn, opts) return Style.SkinButton(btn, opts) end)
ExportPublic("MSUF_SkinNavButton", function(btn, isHeader, isIndented) return Style.SkinNavButton(btn, { header = isHeader, indented = isIndented }) end)
ExportPublic("MSUF_SkinDashboardButton", function(btn) return Style.SkinDashboardButton(btn) end)
ExportPublic("MSUF_ApplyMidnightControlsToFrame", function(root) return Style.ApplyToFrame(root) end)
