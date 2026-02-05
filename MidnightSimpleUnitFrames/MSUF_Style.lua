--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua"); -- MSUF_Style.lua
-- Shared “Flash Menu / Dashboard” Midnight styling helpers.
--
-- Goal
--   - Centralize the Flash Menu style so Options / Edit Mode / popups reuse the same look.
--   - Provide backwards-compatible globals so existing UI code can call skin helpers directly.
--
-- Notes
--   - Pure visuals (no MSUF_DB dependency) so this file can load early.
--   - Idempotent: safe to call multiple times on the same widget.

local addonName, ns = ...
if type(ns) ~= "table" then ns = {} end
_G.MSUF_NS = _G.MSUF_NS or ns

ns.Style = ns.Style or {}
local Style = ns.Style

local WHITE8X8 = "Interface/Buttons/WHITE8X8"

-- Theme (keep flat so old code can keep using MSUF_THEME.foo)
local DEFAULT_THEME = {
  tex = WHITE8X8,

  -- Panels / windows
  -- Slightly brighter default so the custom MSUF options match the other UI panels better
  bgR = 0.08, bgG = 0.09, bgB = 0.10, bgA = 0.94,
  edgeR = 0.20, edgeG = 0.30, edgeB = 0.50, edgeA = 0.55,
  edgeThinR = 0.10, edgeThinG = 0.12, edgeThinB = 0.18, edgeThinA = 0.90,

  -- Text
  titleR = 1.00, titleG = 0.82, titleB = 0.00, titleA = 1.00,
  textR  = 0.92, textG  = 0.94, textB  = 1.00, textA  = 0.95,
  mutedR = 0.65, mutedG = 0.70, mutedB = 0.80, mutedA = 0.65,

  -- Buttons
  btnR = 0.08, btnG = 0.09, btnB = 0.11, btnA = 0.92,
  btnHoverR = 0.25, btnHoverG = 0.55, btnHoverB = 1.00, btnHoverA = 0.18,
  btnDownR  = 0.25, btnDownG  = 0.55, btnDownB  = 1.00, btnDownA  = 0.22,
  btnDisabledR = 0.45, btnDisabledG = 0.45, btnDisabledB = 0.45, btnDisabledA = 0.35,

  -- Nav / dashboard buttons
  navHoverA = 0.18,
  navSelectedA = 0.28,
  navDownA = 0.22,
}

-- Source of truth (if Flash Menu already created MSUF_THEME, keep it)
local THEME = _G.MSUF_THEME or DEFAULT_THEME
_G.MSUF_THEME = THEME

-- Optional public handle
_G.MSUF_Style = _G.MSUF_Style or Style
_G.MSUF_STYLE = _G.MSUF_STYLE or Style

-- ---------------------------------------------------------------------------
-- Enable / Disable gating (controlled via DB; default = enabled)
-- ---------------------------------------------------------------------------

local function _MSUF_GetDB() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:60:6");
  local db = rawget(_G, "MSUF_DB")
  if type(db) == "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:60:6"); return db end
  -- some builds store DB on namespace
  if type(ns) == "table" and type(ns.MSUF_DB) == "table" then return Perfy_Trace_Passthrough("Leave", "_MSUF_GetDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:60:6", ns.MSUF_DB) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:60:6"); return nil
end

function Style.IsEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "Style.IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:68:0");
  local db = _MSUF_GetDB()
  if db and db.general and db.general.styleEnabled ~= nil then
    return Perfy_Trace_Passthrough("Leave", "Style.IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:68:0", db.general.styleEnabled and true or false)
  end
  Perfy_Trace(Perfy_GetTime(), "Leave", "Style.IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:68:0"); return true
end

function Style.SetEnabled(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:76:0");
  local db = _MSUF_GetDB()
  if db and db.general then
    db.general.styleEnabled = enabled and true or false
  end

  -- Best-effort live apply when enabling. Disabling is best handled with /reload.
  if enabled then
    if type(Style.ScanAndSkinEditMode) == "function" then
      Style.ScanAndSkinEditMode()
    end
    local flash = rawget(_G, "MSUF_FlashMenuFrame") or rawget(_G, "MSUF_DashboardFrame")
    if flash and type(Style.ApplyToFrame) == "function" then
      Style.ApplyToFrame(flash)
    end
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SetEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:76:0"); end

-- public globals for UI (flash menu etc.)
_G.MSUF_StyleIsEnabled = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_StyleIsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:95:25"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_StyleIsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:95:25", Style.IsEnabled()) end
_G.MSUF_SetStyleEnabled = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetStyleEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:96:26"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SetStyleEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:96:26", Style.SetEnabled(v)) end

function Style.GetTheme() Perfy_Trace(Perfy_GetTime(), "Enter", "Style.GetTheme file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:98:0");
  Perfy_Trace(Perfy_GetTime(), "Leave", "Style.GetTheme file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:98:0"); return THEME
end

local function SafeTextColor(fs, r, g, b, a) Perfy_Trace(Perfy_GetTime(), "Enter", "SafeTextColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:102:6");
  if fs and fs.SetTextColor then
    fs:SetTextColor(r, g, b, a)
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "SafeTextColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:102:6"); end

function Style.SkinTitle(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:108:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:108:0"); return end
  SafeTextColor(fs, THEME.titleR, THEME.titleG, THEME.titleB, THEME.titleA)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:108:0"); end

function Style.SkinText(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:113:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:113:0"); return end
  SafeTextColor(fs, THEME.textR, THEME.textG, THEME.textB, THEME.textA)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:113:0"); end

function Style.SkinMuted(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:118:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:118:0"); return end
  SafeTextColor(fs, THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:118:0"); end

local function KillTexture(tex) Perfy_Trace(Perfy_GetTime(), "Enter", "KillTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:123:6");
  if tex and tex.Hide then
    tex:Hide()
    if tex.SetTexture then tex:SetTexture(nil) end
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "KillTexture file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:123:6"); end

local function EnsureBackdropFrame(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureBackdropFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:130:6");
  if not frame or not CreateFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureBackdropFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:130:6"); return nil end
  if frame._msufMidnightBackdrop then return Perfy_Trace_Passthrough("Leave", "EnsureBackdropFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:130:6", frame._msufMidnightBackdrop) end

  -- BackdropTemplate is required in modern clients for :SetBackdrop
  local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  b:SetAllPoints(frame)

  local lvl = (frame.GetFrameLevel and frame:GetFrameLevel()) or 0
  if b.SetFrameLevel then
    b:SetFrameLevel(math.max(0, lvl - 1))
  end
  if frame.GetFrameStrata and b.SetFrameStrata then
    b:SetFrameStrata(frame:GetFrameStrata())
  end

  frame._msufMidnightBackdrop = b
  Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureBackdropFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:130:6"); return b
end

-- Apply the Midnight panel style (background + border) to a frame.
-- alphaOverride: optional background alpha
-- thinBorder: use thin border colors/size
function Style.ApplyBackdrop(frame, alphaOverride, thinBorder) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.ApplyBackdrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:153:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyBackdrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:153:0"); return end
  local b = EnsureBackdropFrame(frame)
  if not b or not b.SetBackdrop then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyBackdrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:153:0"); return end

  local edgeSize = thinBorder and 1 or 2
  b:SetBackdrop({
    bgFile = THEME.tex,
    edgeFile = THEME.tex,
    edgeSize = edgeSize,
    insets = { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize },
  })

  b:SetBackdropColor(THEME.bgR, THEME.bgG, THEME.bgB, alphaOverride or THEME.bgA)

  local er, eg, eb, ea = THEME.edgeR, THEME.edgeG, THEME.edgeB, THEME.edgeA
  if thinBorder then
    er, eg, eb, ea = THEME.edgeThinR, THEME.edgeThinG, THEME.edgeThinB, THEME.edgeThinA
  end
  b:SetBackdropBorderColor(er, eg, eb, ea)
  b:Show()
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyBackdrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:153:0"); end

local function EnsureTex(btn, key, layer) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureTex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:176:6");
  if not btn or not btn.CreateTexture then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureTex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:176:6"); return nil end
  local tex = btn[key]
  if tex then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureTex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:176:6"); return tex end
  tex = btn:CreateTexture(nil, layer)
  tex:SetAllPoints(btn)
  btn[key] = tex
  Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureTex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:176:6"); return tex
end

local function UpdateButtonEnabled(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateButtonEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:186:6");
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateButtonEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:186:6"); return end
  local enabled = true
  if btn.IsEnabled then
    enabled = btn:IsEnabled() and true or false
  end

  local fs = btn.GetFontString and btn:GetFontString() or (btn.Text or nil)

  if enabled then
    if btn._msufBtnDisabled then btn._msufBtnDisabled:Hide() end
    if fs and fs.SetTextColor then
      Style.SkinText(fs)
    end
    if btn.SetAlpha then btn:SetAlpha(1) end
  else
    if btn._msufBtnDisabled then btn._msufBtnDisabled:Show() end
    if fs and fs.SetTextColor then
      SafeTextColor(fs, THEME.mutedR, THEME.mutedG, THEME.mutedB, 0.70)
    end
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateButtonEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:186:6"); end

-- Generic button skin (works for UIPanelButtonTemplate and simple Buttons).
-- opts:
--   - isNav: bool (uses nav down alpha)
--   - active: bool (initial selected state)

-- ---------------------------------------------------------------------------
-- Button skinning
--  - Handles normal text buttons (UIPanelButtonTemplate)
--  - Handles icon buttons (close / small icon buttons) without nuking their icon
--  - Handles dropdown arrow buttons ("DropButton") without breaking SetNormalTexture(nil)
-- ---------------------------------------------------------------------------

local function _MSUF_GetButtonLabel(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetButtonLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:221:6");
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetButtonLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:221:6"); return nil end
  local fs = btn.GetFontString and btn:GetFontString()
  if fs and fs.GetText and fs:GetText() and fs:GetText() ~= "" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetButtonLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:221:6"); return fs end
  local t = btn.Text
  if t and t.GetText and t:GetText() and t:GetText() ~= "" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetButtonLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:221:6"); return t end
  Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetButtonLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:221:6"); return nil
end

local function _MSUF_IsDropButton(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_IsDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:230:6");
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:230:6"); return false end
  local n = (type(btn.GetName) == "function") and btn:GetName() or nil
  if type(n) == "string" and (n:find("DropButton", 1, true) or n:find("DropDown", 1, true) or n:find("Dropdown", 1, true)) then
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:230:6"); return true
  end
  -- Heuristic: dedicated arrow buttons usually have only the texture regions, not UIPanelButton parts.
  if btn.NormalTexture and btn.HighlightTexture and btn.PushedTexture and not btn.Left and not btn.Middle and not btn.Right then
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:230:6"); return true
  end
  Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:230:6"); return false
end

local function _MSUF_IsIconButton(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_IsIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:243:6");
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:243:6"); return false end
  -- If it has a text label, treat it as normal button.
  if _MSUF_GetButtonLabel(btn) then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:243:6"); return false end

  local nt = btn.GetNormalTexture and btn:GetNormalTexture()
  if nt and nt.GetTexture and nt:GetTexture() then
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:243:6"); return true
  end

  local icon = btn.Icon or btn.icon
  if icon and icon.GetTexture and icon:GetTexture() then
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:243:6"); return true
  end

  Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_IsIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:243:6"); return false
end

local function _MSUF_InstallHoverDownScripts(btn, hoverTexKey, downTexKey, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_InstallHoverDownScripts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:261:6");
  if not btn or not btn.SetScript then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_InstallHoverDownScripts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:261:6"); return end

  btn._msufBtnIsDown = false
  btn._msufBtnIsActive = (opts and opts.active) and true or false

  local function ApplyState(self) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:267:8");
    if not self then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:267:8"); return end

    local enabled = true
    if self.IsEnabled then enabled = self:IsEnabled() and true or false end

    if not enabled then
      if self[hoverTexKey] then self[hoverTexKey]:Hide() end
      if self[downTexKey] then self[downTexKey]:Hide() end
      UpdateButtonEnabled(self)
      Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:267:8"); return
    end

    if self._msufBtnDisabled then self._msufBtnDisabled:Hide() end

    if self[downTexKey] then
      if self._msufBtnIsDown then self[downTexKey]:Show() else self[downTexKey]:Hide() end
    end

    if self[hoverTexKey] then
      if not self._msufBtnIsDown and self:IsMouseOver() then
        self[hoverTexKey]:Show()
      else
        self[hoverTexKey]:Hide()
      end
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:267:8"); end

  btn._msufApplyBtnState = ApplyState

  local oldEnter = btn:GetScript("OnEnter")
  local oldLeave = btn:GetScript("OnLeave")
  local oldDown  = btn:GetScript("OnMouseDown")
  local oldUp    = btn:GetScript("OnMouseUp")

  btn:SetScript("OnEnter", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:302:27");
    if oldEnter then pcall(oldEnter, self, ...) end
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:302:27"); end)

  btn:SetScript("OnLeave", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:307:27");
    if oldLeave then pcall(oldLeave, self, ...) end
    if self[hoverTexKey] then self[hoverTexKey]:Hide() end
    if self._msufBtnIsDown then self._msufBtnIsDown = false end
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:307:27"); end)

  btn:SetScript("OnMouseDown", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:314:31");
    if oldDown then pcall(oldDown, self, ...) end
    self._msufBtnIsDown = true
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:314:31"); end)

  btn:SetScript("OnMouseUp", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:320:29");
    if oldUp then pcall(oldUp, self, ...) end
    self._msufBtnIsDown = false
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:320:29"); end)

  -- Also update when enabled state changes
  if not btn.__msufEnabledHook and hooksecurefunc and btn.Enable then
    btn.__msufEnabledHook = true
    hooksecurefunc(btn, "Enable", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:329:34");
      if self._msufApplyBtnState then self._msufApplyBtnState(self) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:329:34"); end)
    hooksecurefunc(btn, "Disable", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:332:35");
      if self._msufApplyBtnState then self._msufApplyBtnState(self) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:332:35"); end)
  end

  if btn._msufApplyBtnState then btn._msufApplyBtnState(btn) end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_InstallHoverDownScripts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:261:6"); end

function Style.SkinDropButton(btn, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:340:0");
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:340:0"); return end
  if btn.__msufMidnightDropSkinned then
    UpdateButtonEnabled(btn)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:340:0"); return
  end
  btn.__msufMidnightDropSkinned = true

  -- Keep arrow textures. Just give it the Midnight frame + hover/down behind it.
  Style.ApplyBackdrop(btn, 0.85, true)

  local bg = EnsureTex(btn, "_msufDropBG", "BACKGROUND")
  if bg then
    bg:SetColorTexture(THEME.btnR, THEME.btnG, THEME.btnB, THEME.btnA)
  end

  local hover = EnsureTex(btn, "_msufDropHover", "BORDER")
  if hover then
    hover:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.btnHoverA)
    hover:Hide()
  end

  local down = EnsureTex(btn, "_msufDropDown", "BORDER")
  if down then
    local a = THEME.btnDownA
    if opts and opts.isNav then a = THEME.navDownA end
    down:SetColorTexture(THEME.btnDownR, THEME.btnDownG, THEME.btnDownB, a)
    down:Hide()
  end

  _MSUF_InstallHoverDownScripts(btn, "_msufDropHover", "_msufDropDown", opts)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinDropButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:340:0"); end

function Style.SkinIconButton(btn, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:373:0");
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:373:0"); return end
  if btn.__msufMidnightIconSkinned then
    UpdateButtonEnabled(btn)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:373:0"); return
  end
  btn.__msufMidnightIconSkinned = true

  -- Do NOT strip existing icon textures; just unify background + hover/down.
  Style.ApplyBackdrop(btn, 0.85, true)

  local bg = EnsureTex(btn, "_msufIconBG", "BACKGROUND")
  if bg then
    bg:SetColorTexture(THEME.btnR, THEME.btnG, THEME.btnB, THEME.btnA)
  end

  local hover = EnsureTex(btn, "_msufIconHover", "BORDER")
  if hover then
    hover:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.btnHoverA)
    hover:Hide()
  end

  local down = EnsureTex(btn, "_msufIconDown", "BORDER")
  if down then
    local a = THEME.btnDownA
    if opts and opts.isNav then a = THEME.navDownA end
    down:SetColorTexture(THEME.btnDownR, THEME.btnDownG, THEME.btnDownB, a)
    down:Hide()
  end

  _MSUF_InstallHoverDownScripts(btn, "_msufIconHover", "_msufIconDown", opts)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinIconButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:373:0"); end

-- Generic button skin (works for UIPanelButtonTemplate and simple Buttons).
-- opts:
--   - isNav: bool (uses nav down alpha)
--   - active: bool (initial selected state)
function Style.SkinButton(btn, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0"); return end
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0"); return end

  -- Specialized: dropdown arrows / icon-only buttons
  if _MSUF_IsDropButton(btn) then
    return Perfy_Trace_Passthrough("Leave", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0", Style.SkinDropButton(btn, opts))
  end
  if _MSUF_IsIconButton(btn) then
    return Perfy_Trace_Passthrough("Leave", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0", Style.SkinIconButton(btn, opts))
  end

  if btn.__msufMidnightSkinned then
    UpdateButtonEnabled(btn)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0"); return
  end
  btn.__msufMidnightSkinned = true

  -- Strip Blizzard template pieces (UIPanelButtonTemplate)
  KillTexture(btn.Left)
  KillTexture(btn.Middle)
  KillTexture(btn.Right)

  -- IMPORTANT: Do NOT call SetNormalTexture(nil) etc.
  -- Some buttons error if you pass nil (usage expects an asset string).
  if btn.GetNormalTexture then KillTexture(btn:GetNormalTexture()) end
  if btn.GetPushedTexture then KillTexture(btn:GetPushedTexture()) end
  if btn.GetHighlightTexture then KillTexture(btn:GetHighlightTexture()) end
  if btn.GetDisabledTexture then KillTexture(btn:GetDisabledTexture()) end

  local bg = EnsureTex(btn, "_msufBtnBG", "BACKGROUND")
  if bg then
    bg:SetColorTexture(THEME.btnR, THEME.btnG, THEME.btnB, THEME.btnA)
  end

  local hover = EnsureTex(btn, "_msufBtnHover", "BORDER")
  if hover then
    hover:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.btnHoverA)
    hover:Hide()
  end

  local down = EnsureTex(btn, "_msufBtnDown", "BORDER")
  if down then
    local a = THEME.btnDownA
    if opts and opts.isNav then a = THEME.navDownA end
    down:SetColorTexture(THEME.btnDownR, THEME.btnDownG, THEME.btnDownB, a)
    down:Hide()
  end

  local disabled = EnsureTex(btn, "_msufBtnDisabled", "OVERLAY")
  if disabled then
    disabled:SetColorTexture(THEME.btnDisabledR, THEME.btnDisabledG, THEME.btnDisabledB, THEME.btnDisabledA)
    disabled:Hide()
  end

  -- Text
  local fs = _MSUF_GetButtonLabel(btn) or (btn.GetFontString and btn:GetFontString()) or (btn.Text or nil)
  if fs and fs.SetTextColor then
    Style.SkinText(fs)
  end

  _MSUF_InstallHoverDownScripts(btn, "_msufBtnHover", "_msufBtnDown", opts)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:410:0"); end

function Style.SkinNavButton(btn, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:474:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:474:0"); return end
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:474:0"); return end
  if btn.__msufMidnightNavSkinned then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:474:0"); return end
  btn.__msufMidnightNavSkinned = true

  Style.SkinButton(btn, { isNav = true })

  btn._msufNavIsActive = false

  local sel = EnsureTex(btn, "_msufNavSelected", "ARTWORK")
  if sel then
    sel:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.navSelectedA)
    sel:Hide()
  end

  local function ApplyNavState(self) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyNavState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:490:8");
    if not self then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyNavState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:490:8"); return end

    local enabled = true
    if self.IsEnabled then enabled = self:IsEnabled() and true or false end

    if not enabled then
      if self._msufNavSelected then self._msufNavSelected:Hide() end
      if self._msufBtnHover then self._msufBtnHover:Hide() end
      if self._msufBtnDown then self._msufBtnDown:Hide() end
      UpdateButtonEnabled(self)
      Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyNavState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:490:8"); return
    end

    if self._msufNavSelected then
      if self._msufNavIsActive then self._msufNavSelected:Show() else self._msufNavSelected:Hide() end
    end

    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyNavState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:490:8"); end

  btn._msufApplyNavState = ApplyNavState

  -- Public toggle used by menus to highlight the current page
  btn._msufSetActive = function(self, isActive) Perfy_Trace(Perfy_GetTime(), "Enter", "btn._msufSetActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:514:23");
    self._msufNavIsActive = isActive and true or false
    if self._msufApplyNavState then self._msufApplyNavState(self) end
  Perfy_Trace(Perfy_GetTime(), "Leave", "btn._msufSetActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:514:23"); end

  -- Text color
  local fs = btn.GetFontString and btn:GetFontString() or (btn.Text or nil)
  if fs and fs.SetTextColor then
    if opts and opts.header then
      Style.SkinTitle(fs)
    else
      Style.SkinText(fs)
    end
  end

  -- Ensure selected state doesn't get lost after hover leave
  local oldLeave = btn.GetScript and btn:GetScript("OnLeave")
  if btn.SetScript then
    btn:SetScript("OnLeave", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:532:29");
      if oldLeave then pcall(oldLeave, self, ...) end
      if self._msufApplyNavState then self._msufApplyNavState(self) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:532:29"); end)
  end

  if btn._msufApplyNavState then btn._msufApplyNavState(btn) end
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:474:0"); end

function Style.SkinDashboardButton(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinDashboardButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:541:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinDashboardButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:541:0"); return end
  if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinDashboardButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:541:0"); return end
  Style.SkinNavButton(btn)

  -- Alias used by some dashboards
  btn._msufSetSelected = function(self, isSelected) Perfy_Trace(Perfy_GetTime(), "Enter", "btn._msufSetSelected file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:547:25");
    if self._msufSetActive then
      self:_msufSetActive(isSelected)
    else
      self._msufNavIsActive = isSelected and true or false
      if self._msufApplyNavState then self._msufApplyNavState(self) end
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "btn._msufSetSelected file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:547:25"); end
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinDashboardButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:541:0"); end

-- Walk a frame and skin obvious widgets (buttons, checkbuttons, editboxes).
-- Use sparingly (e.g. once on panel creation) to avoid runtime overhead.
function Style.ApplyToFrame(root) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:559:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:559:0"); return end
  if not root or not root.GetChildren then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:559:0"); return end

  local function SkinCheckButton(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "SkinCheckButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:563:8");
    if not cb or cb.__msufMidnightCheckSkinned then Perfy_Trace(Perfy_GetTime(), "Leave", "SkinCheckButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:563:8"); return end
    cb.__msufMidnightCheckSkinned = true

    local label = cb.Text or (cb.GetFontString and cb:GetFontString())
    if label and label.SetTextColor then
      Style.SkinText(label)
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "SkinCheckButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:563:8"); end

  local function SkinEditBox(eb) Perfy_Trace(Perfy_GetTime(), "Enter", "SkinEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:573:8");
    if not eb or eb.__msufMidnightEditSkinned then Perfy_Trace(Perfy_GetTime(), "Leave", "SkinEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:573:8"); return end
    eb.__msufMidnightEditSkinned = true

    Style.ApplyBackdrop(eb, 0.80, true)

    local fs = eb.GetFontString and eb:GetFontString()
    if fs and fs.SetTextColor then
      Style.SkinText(fs)
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "SkinEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:573:8"); end

  local function Walk(f) Perfy_Trace(Perfy_GetTime(), "Enter", "Walk file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:585:8");
    for i = 1, select("#", f:GetChildren()) do
      local child = select(i, f:GetChildren())
      if child then
        if child.IsObjectType and child:IsObjectType("Button") then
          if child:IsObjectType("CheckButton") then
            SkinCheckButton(child)
          else
            Style.SkinButton(child)
          end
        elseif child.IsObjectType and child:IsObjectType("EditBox") then
          SkinEditBox(child)
        end

        if child.GetChildren then
          Walk(child)
        end
      end
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "Walk file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:585:8"); end

  Walk(root)
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:559:0"); end

-- ---------------------------------------------------------------------------
-- Edit Mode styling (no separate file; uses the same Flash/Dashboard style)
-- ---------------------------------------------------------------------------

local function _MSUF_IsFontString(obj) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_IsFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:613:6");
  return Perfy_Trace_Passthrough("Leave", "_MSUF_IsFontString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:613:6", obj and obj.GetObjectType and obj:GetObjectType() == "FontString")
end

local function _MSUF_SkinAnyTitle(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SkinAnyTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:617:6");
  if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SkinAnyTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:617:6"); return end
  local candidates = {
    frame.Title, frame.title,
    frame.TitleText, frame.titleText,
    frame.Header, frame.header,
    frame.HeaderText, frame.headerText,
    frame.TitleLabel, frame.titleLabel,
    frame.titleFS, frame._msufTitle,
    frame.Name, frame.name,
  }
  for _, fs in ipairs(candidates) do
    if _MSUF_IsFontString(fs) then Style.SkinTitle(fs) end
  end
  if _MSUF_IsFontString(frame.text) then Style.SkinTitle(frame.text) end
  if _MSUF_IsFontString(frame.Label) then Style.SkinTitle(frame.Label) end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SkinAnyTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:617:6"); end

local function _MSUF_SkinAnyMuted(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SkinAnyMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:635:6");
  if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SkinAnyMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:635:6"); return end
  local candidates = {
    frame.Subtitle, frame.subtitle,
    frame.Description, frame.description,
    frame.HelpText, frame.helpText,
    frame.Note, frame.note,
  }
  for _, fs in ipairs(candidates) do
    if _MSUF_IsFontString(fs) then Style.SkinMuted(fs) end
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SkinAnyMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:635:6"); end

local function _MSUF_SkinKnownButtons(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SkinKnownButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:648:6");
  if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SkinKnownButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:648:6"); return end
  local keys = {
    "OkayButton","OkButton","okButton","Okay","ok","okay",
    "CancelButton","cancelButton","Cancel","cancel",
    "CloseButton","closeButton","Close","close",
    "MenuButton","menuButton","Menu","menu",
    "ResetButton","resetButton","Reset","reset",
    "ApplyButton","applyButton","Apply","apply",
    "ExitButton","exitbutton","exitButton","Exit","exit",
  }
  for _, k in ipairs(keys) do
    local b = frame[k]
    if b and b.GetObjectType and b:GetObjectType() == "Button" then
      Style.SkinButton(b)
    end
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SkinKnownButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:648:6"); end

function Style.SkinEditModePopupFrame(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.SkinEditModePopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:667:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinEditModePopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:667:0"); return end
  if not frame or frame.__msufMidnightEditModeSkinned then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinEditModePopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:667:0"); return end
  frame.__msufMidnightEditModeSkinned = true

  -- Main window
  Style.ApplyBackdrop(frame)

  -- Common inset/content containers (keep subtle)
  local inset = frame.Inset or frame.inset or frame.Content or frame.content or frame.Body or frame.body
  if inset and inset.GetObjectType then
    Style.ApplyBackdrop(inset, 0.65, true)
  end

  _MSUF_SkinAnyTitle(frame)
  _MSUF_SkinAnyMuted(frame)
  _MSUF_SkinKnownButtons(frame)

  -- Skin all nested widgets using the global style walker (buttons, checkboxes, editboxes, dropdown buttons, etc.)
  Style.ApplyToFrame(frame)

  -- Some builds use a dedicated header frame
  local header = frame.Header or frame.header or frame.Top or frame.top
  if header then
    _MSUF_SkinAnyTitle(header)
    _MSUF_SkinAnyMuted(header)
    _MSUF_SkinKnownButtons(header)
    Style.ApplyToFrame(header)
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.SkinEditModePopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:667:0"); end

local function _MSUF_LooksLikeEditModePopup(f) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6");
  -- IMPORTANT: Only skin MSUF-owned Edit Mode popups.
  -- Never touch Blizzard Edit Mode / HUD Edit Mode frames.
  if not f or type(f.GetName) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return false end
  if f.GetObjectType and f:GetObjectType() ~= "Frame" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return false end

  local n = f:GetName()
  if type(n) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return false end

  -- Hard whitelist (root popups)
  if n == "MSUF_EditPositionPopup" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return true end
  if n == "MSUF_CastbarPositionPopup" or n == "MSUF_BossCastbarPositionPopup" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return true end
  -- Auras 2.0 Edit Mode popup (target auras, etc.)
  if n == "MSUF_AuraPositionPopup" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return true end

  -- Allow additional MSUF edit popups by prefix (but still require popup-ish names)
  if n:find("MSUF_Edit", 1, true) then
    if n:find("Popup", 1, true) or n:find("Position", 1, true) then
      Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return true
    end
  end

  Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_LooksLikeEditModePopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:698:6"); return false
end

function Style.ScanAndSkinEditMode() Perfy_Trace(Perfy_GetTime(), "Enter", "Style.ScanAndSkinEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:723:0");
  if not Style.IsEnabled() then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ScanAndSkinEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:723:0"); return end
  -- Known globals (cheap)
  local known = {
    _G.MSUF_EditPositionPopup,
    _G.MSUF_CastbarPositionPopup,
    _G.MSUF_BossCastbarPositionPopup,
    _G.MSUF_AuraPositionPopup,
  }
  for _, f in ipairs(known) do
    if f then Style.SkinEditModePopupFrame(f) end
  end

  -- Fallback: enumerate frames to catch lazily created popups (bounded)
  if type(_G.EnumerateFrames) == "function" then
    local f = _G.EnumerateFrames()
    local safety = 0
    while f and safety < 4000 do
      safety = safety + 1
      if _MSUF_LooksLikeEditModePopup(f) then
        Style.SkinEditModePopupFrame(f)
      end
      f = _G.EnumerateFrames(f)
    end
  end
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ScanAndSkinEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:723:0"); end

function Style.InstallEditModeAutoSkin() Perfy_Trace(Perfy_GetTime(), "Enter", "Style.InstallEditModeAutoSkin file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:750:0");
  if _G.__MSUF_EDITMODE_STYLE_INSTALLED then Perfy_Trace(Perfy_GetTime(), "Leave", "Style.InstallEditModeAutoSkin file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:750:0"); return end
  _G.__MSUF_EDITMODE_STYLE_INSTALLED = true

  local function RunSoon() Perfy_Trace(Perfy_GetTime(), "Enter", "RunSoon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:754:8");
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:756:23"); Style.ScanAndSkinEditMode() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:756:23"); end)
    else
      Style.ScanAndSkinEditMode()
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "RunSoon file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:754:8"); end

  local function HookIfExists(globalName) Perfy_Trace(Perfy_GetTime(), "Enter", "HookIfExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:762:8");
    local fn = _G[globalName]
    if type(fn) ~= "function" or not hooksecurefunc then Perfy_Trace(Perfy_GetTime(), "Leave", "HookIfExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:762:8"); return end

    _G.__MSUF_EditModeStyleHooked = _G.__MSUF_EditModeStyleHooked or {}
    if _G.__MSUF_EditModeStyleHooked[globalName] then Perfy_Trace(Perfy_GetTime(), "Leave", "HookIfExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:762:8"); return end
    _G.__MSUF_EditModeStyleHooked[globalName] = true

    hooksecurefunc(globalName, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:770:31");
      RunSoon()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:770:31"); end)
  Perfy_Trace(Perfy_GetTime(), "Leave", "HookIfExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:762:8"); end

  -- Try to hook immediately (in case EditMode already loaded)
  HookIfExists("MSUF_ToggleEditMode")
  HookIfExists("MSUF_EnterEditMode")
  HookIfExists("MSUF_ExitEditMode")
  HookIfExists("MSUF_OpenPositionPopup")
  HookIfExists("MSUF_OpenCastbarPositionPopup")
  HookIfExists("MSUF_OpenBossCastbarPositionPopup")
  HookIfExists("MSUF_OpenAuraPositionPopup")

  -- Also retry on addon load (handles different load orders / LoD)
  local boot = CreateFrame("Frame")
  boot:RegisterEvent("ADDON_LOADED")
  boot:SetScript("OnEvent", function(self, event, arg1) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:787:28");
    if arg1 ~= addonName then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:787:28"); return end
    HookIfExists("MSUF_ToggleEditMode")
    HookIfExists("MSUF_EnterEditMode")
    HookIfExists("MSUF_ExitEditMode")
    HookIfExists("MSUF_OpenPositionPopup")
    HookIfExists("MSUF_OpenCastbarPositionPopup")
    HookIfExists("MSUF_OpenBossCastbarPositionPopup")
    HookIfExists("MSUF_OpenAuraPositionPopup")

    -- A couple of delayed passes to catch frames created after login/open
    if C_Timer and C_Timer.After then
      C_Timer.After(0, Style.ScanAndSkinEditMode)
      C_Timer.After(0.25, Style.ScanAndSkinEditMode)
      C_Timer.After(1.0, Style.ScanAndSkinEditMode)
    else
      Style.ScanAndSkinEditMode()
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:787:28"); end)

  -- Initial pass
  RunSoon()
Perfy_Trace(Perfy_GetTime(), "Leave", "Style.InstallEditModeAutoSkin file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:750:0"); end

-- Auto-enable edit mode styling by default (visual only, safe)
Style.InstallEditModeAutoSkin()


-- ---------------------------------------------------------------------------
-- Backwards-compatible globals (so other files can just call these)
-- ---------------------------------------------------------------------------

_G.MSUF_ApplyMidnightBackdrop = function(frame, alphaOverride, thinBorder) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_ApplyMidnightBackdrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:819:32");
  return Perfy_Trace_Passthrough("Leave", "_G.MSUF_ApplyMidnightBackdrop file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:819:32", Style.ApplyBackdrop(frame, alphaOverride, thinBorder))
end

_G.MSUF_SkinTitle = function(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SkinTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:823:20"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SkinTitle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:823:20", Style.SkinTitle(fs)) end
_G.MSUF_SkinText  = function(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SkinText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:824:20"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SkinText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:824:20", Style.SkinText(fs)) end
_G.MSUF_SkinMuted = function(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SkinMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:825:20"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SkinMuted file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:825:20", Style.SkinMuted(fs)) end

_G.MSUF_SkinButton = function(btn, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:827:21"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SkinButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:827:21", Style.SkinButton(btn, opts)) end
_G.MSUF_SkinNavButton = function(btn, isHeader, isIndented) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:828:24");
  return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SkinNavButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:828:24", Style.SkinNavButton(btn, { header = isHeader, indented = isIndented }))
end
_G.MSUF_SkinDashboardButton = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SkinDashboardButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:831:30"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SkinDashboardButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:831:30", Style.SkinDashboardButton(btn)) end
_G.MSUF_ApplyMidnightControlsToFrame = function(root) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_ApplyMidnightControlsToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:832:39"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_ApplyMidnightControlsToFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:832:39", Style.ApplyToFrame(root)) end

-- Marker for gating / debug
-- ---------------------------------------------------------------------------
-- Options checkmark replacement (MSUF tick)
--   - Replaces Blizzard yellow checkmarks for MSUF option panels (Gameplay/Colors/etc.)
--   - Alpha-texture ticks (thin + bold) so they match MSUF theme and can be tinted.
--   - Idempotent + safe to call multiple times.
-- ---------------------------------------------------------------------------

do
  local _addon = (type(addonName) == "string" and addonName ~= "" and addonName) or "MidnightSimpleUnitFrames"
  local CHECK_TEX_THIN = "Interface/AddOns/" .. _addon .. "/Media/msuf_check_tick_thin.tga"
  local CHECK_TEX_BOLD = "Interface/AddOns/" .. _addon .. "/Media/msuf_check_tick_bold.tga"

  local function _GetLabelFS(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "_GetLabelFS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:847:8");
    if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "_GetLabelFS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:847:8"); return nil end
    local fs = cb.text or cb.Text
    if (not fs) and cb.GetName and cb:GetName() and _G then
      fs = _G[cb:GetName() .. "Text"]
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_GetLabelFS file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:847:8"); return fs
  end

  local function _StyleToggleText(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:856:8");
    if not cb or cb.__msufToggleTextStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:856:8"); return end
    cb.__msufToggleTextStyled = true

    local fs = _GetLabelFS(cb)
    if not (fs and fs.SetTextColor) then Perfy_Trace(Perfy_GetTime(), "Leave", "_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:856:8"); return end

    cb.__msufToggleFS = fs

    local function Update() Perfy_Trace(Perfy_GetTime(), "Enter", "Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:865:10");
      if cb.IsEnabled and (not cb:IsEnabled()) then
        fs:SetTextColor(0.35, 0.35, 0.35)
      else
        if cb.GetChecked and cb:GetChecked() then
          fs:SetTextColor(1, 1, 1)
        else
          fs:SetTextColor(0.55, 0.55, 0.55)
        end
      end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:865:10"); end

    cb.__msufToggleUpdate = Update
    cb:HookScript("OnShow", Update)
    cb:HookScript("OnClick", Update)
    pcall(hooksecurefunc, cb, "SetChecked", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:880:44"); Update() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:880:44"); end)
    pcall(hooksecurefunc, cb, "SetEnabled", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:881:44"); Update() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:881:44"); end)
    Update()
  Perfy_Trace(Perfy_GetTime(), "Leave", "_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:856:8"); end

  local function _StyleCheckmark(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:885:8");
    if not cb or cb.__msufCheckmarkStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:885:8"); return end
    cb.__msufCheckmarkStyled = true

    local check = (cb.GetCheckedTexture and cb:GetCheckedTexture())
    if (not check) and cb.GetName and cb:GetName() and _G then
      check = _G[cb:GetName() .. "Check"]
    end
    if not (check and check.SetTexture) then Perfy_Trace(Perfy_GetTime(), "Leave", "_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:885:8"); return end

    local h = (cb.GetHeight and cb:GetHeight()) or 24
    local tex = (h >= 24) and CHECK_TEX_BOLD or CHECK_TEX_THIN

    check:SetTexture(tex)
    check:SetTexCoord(0, 1, 0, 1)
    if check.SetBlendMode then check:SetBlendMode("BLEND") end

    if check.ClearAllPoints then
      check:ClearAllPoints()
      check:SetPoint("CENTER", cb, "CENTER", 0, 0)
    end
    if check.SetSize then
      local s = math.floor((h * 0.72) + 0.5)
      if s < 12 then s = 12 end
      check:SetSize(s, s)
    end

    -- Keep it stable if the template tries to reset the checked texture later.
    if cb.HookScript and not cb.__msufCheckmarkHooked then
      cb.__msufCheckmarkHooked = true
      local function Reapply() Perfy_Trace(Perfy_GetTime(), "Enter", "Reapply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:915:12");
        if cb.__msufCheckmarkReapplying then Perfy_Trace(Perfy_GetTime(), "Leave", "Reapply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:915:12"); return end
        cb.__msufCheckmarkReapplying = true
        local hh = (cb.GetHeight and cb:GetHeight()) or h
        local tt = (hh >= 24) and CHECK_TEX_BOLD or CHECK_TEX_THIN
        local c = (cb.GetCheckedTexture and cb:GetCheckedTexture()) or check
        if c and c.SetTexture then
          c:SetTexture(tt)
          if c.SetBlendMode then c:SetBlendMode("BLEND") end
          if c.ClearAllPoints then
            c:ClearAllPoints()
            c:SetPoint("CENTER", cb, "CENTER", 0, 0)
          end
          if c.SetSize then
            local ss = math.floor((hh * 0.72) + 0.5)
            if ss < 12 then ss = 12 end
            c:SetSize(ss, ss)
          end
        end
        cb.__msufCheckmarkReapplying = nil
      Perfy_Trace(Perfy_GetTime(), "Leave", "Reapply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:915:12"); end
      cb:HookScript("OnShow", Reapply)
      cb:HookScript("OnSizeChanged", Reapply)
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:885:8"); end

  local function _WalkAndStyle(root) Perfy_Trace(Perfy_GetTime(), "Enter", "_WalkAndStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:941:8");
    if not root or not root.GetChildren then Perfy_Trace(Perfy_GetTime(), "Leave", "_WalkAndStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:941:8"); return end
    local children = { root:GetChildren() }
    for i = 1, #children do
      local c = children[i]
      if c and c.GetObjectType and c:GetObjectType() == "CheckButton" then
        _StyleToggleText(c)
        _StyleCheckmark(c)
      end
      if c and c.GetChildren then
        _WalkAndStyle(c)
      end
    end
  Perfy_Trace(Perfy_GetTime(), "Leave", "_WalkAndStyle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:941:8"); end

  -- Public entry points (ns + globals) so other option panels can call it.
  Style.ApplyOptionCheckmarks = function(root) Perfy_Trace(Perfy_GetTime(), "Enter", "Style.ApplyOptionCheckmarks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:957:32");
    _WalkAndStyle(root or UIParent)
  Perfy_Trace(Perfy_GetTime(), "Leave", "Style.ApplyOptionCheckmarks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua:957:32"); end

  ns.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
  _G.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
end

-- Marker for gating / debug
_G.__MSUF_STYLE_VERSION = 5
_G.__MSUF_STYLE_TAG = "editmode-scanfix-v5-optionCheckmarks"

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_Style.lua");