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
local function _MSUF_GetDB()
  local db = rawget(_G, "MSUF_DB")
  if type(db) == "table" then  return db end
  -- some builds store DB on namespace
  if type(ns) == "table" and type(ns.MSUF_DB) == "table" then return ns.MSUF_DB end
   return nil
end
local function _MSUF_NormalizeDropdownStyleMode(mode)
  if mode == "old" or mode == "blizzard" or mode == "legacy" then
    return "old"
  end
  return "msuf"
end
local function _MSUF_CommitPendingDropdownStyleMode()
  local db = _MSUF_GetDB()
  local g = db and db.general or nil
  if not g then return end
  local pending = g.pendingDropdownStyleMode
  if pending ~= nil then
    g.dropdownStyleMode = _MSUF_NormalizeDropdownStyleMode(pending)
    g.pendingDropdownStyleMode = nil
  elseif g.dropdownStyleMode ~= nil then
    g.dropdownStyleMode = _MSUF_NormalizeDropdownStyleMode(g.dropdownStyleMode)
  end
end
_MSUF_CommitPendingDropdownStyleMode()
function Style.IsEnabled()
  local db = _MSUF_GetDB()
  if db and db.general and db.general.styleEnabled ~= nil then
    return db.general.styleEnabled and true or false
  end
   return true
end
function Style.SetEnabled(enabled)
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
 end
local function _MSUF_GetDropdownStyleMode()
  local db = _MSUF_GetDB()
  local g = db and db.general or nil
  return _MSUF_NormalizeDropdownStyleMode(g and g.dropdownStyleMode or nil)
end
function Style.UseModernDropdowns()
  return _MSUF_GetDropdownStyleMode() ~= "old"
end
-- public globals for UI (flash menu etc.)
_G.MSUF_StyleIsEnabled = function()  return Style.IsEnabled() end
_G.MSUF_SetStyleEnabled = function(v)  return Style.SetEnabled(v) end
_G.MSUF_GetDropdownStyleMode = function() return _MSUF_GetDropdownStyleMode() end
function Style.GetTheme()
   return THEME
end
local function SafeTextColor(fs, r, g, b, a)
  if fs and fs.SetTextColor then
    fs:SetTextColor(r, g, b, a)
  end
 end
function Style.SkinTitle(fs)
  if not Style.IsEnabled() then  return end
  SafeTextColor(fs, THEME.titleR, THEME.titleG, THEME.titleB, THEME.titleA)
 end
function Style.SkinText(fs)
  if not Style.IsEnabled() then  return end
  SafeTextColor(fs, THEME.textR, THEME.textG, THEME.textB, THEME.textA)
 end
function Style.SkinMuted(fs)
  if not Style.IsEnabled() then  return end
  SafeTextColor(fs, THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA)
 end
local function KillTexture(tex)
  if tex and tex.Hide then
    tex:Hide()
    if tex.SetTexture then tex:SetTexture(nil) end
  end
 end
local function EnsureBackdropFrame(frame)
  if not frame or not CreateFrame then  return nil end
  if frame._msufMidnightBackdrop then return frame._msufMidnightBackdrop end
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
   return b
end
-- Apply the Midnight panel style (background + border) to a frame.
-- alphaOverride: optional background alpha
-- thinBorder: use thin border colors/size
function Style.ApplyBackdrop(frame, alphaOverride, thinBorder)
  if not Style.IsEnabled() then  return end
  local b = EnsureBackdropFrame(frame)
  if not b or not b.SetBackdrop then  return end
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
 end
local function EnsureTex(btn, key, layer)
  if not btn or not btn.CreateTexture then  return nil end
  local tex = btn[key]
  if tex then  return tex end
  tex = btn:CreateTexture(nil, layer)
  tex:SetAllPoints(btn)
  btn[key] = tex
   return tex
end
local function UpdateButtonEnabled(btn)
  if not btn then  return end
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
 end
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
local function _MSUF_GetButtonLabel(btn)
  if not btn then  return nil end
  local fs = btn.GetFontString and btn:GetFontString()
  if fs and fs.GetText and fs:GetText() and fs:GetText() ~= "" then  return fs end
  local t = btn.Text
  if t and t.GetText and t:GetText() and t:GetText() ~= "" then  return t end
   return nil
end
local function _MSUF_IsDropButton(btn)
  if not btn then  return false end
  local n = (type(btn.GetName) == "function") and btn:GetName() or nil
  if type(n) == "string" and (n:find("DropButton", 1, true) or n:find("DropDown", 1, true) or n:find("Dropdown", 1, true)) then
     return true
  end
  -- Heuristic: dedicated arrow buttons usually have only the texture regions, not UIPanelButton parts.
  if btn.NormalTexture and btn.HighlightTexture and btn.PushedTexture and not btn.Left and not btn.Middle and not btn.Right then
     return true
  end
   return false
end
local function _MSUF_IsIconButton(btn)
  if not btn then  return false end
  -- If it has a text label, treat it as normal button.
  if _MSUF_GetButtonLabel(btn) then  return false end
  local nt = btn.GetNormalTexture and btn:GetNormalTexture()
  if nt and nt.GetTexture and nt:GetTexture() then
     return true
  end
  local icon = btn.Icon or btn.icon
  if icon and icon.GetTexture and icon:GetTexture() then
     return true
  end
   return false
end
local function _MSUF_InstallHoverDownScripts(btn, hoverTexKey, downTexKey, opts)
  if not btn or not btn.SetScript then  return end
  btn._msufBtnIsDown = false
  btn._msufBtnIsActive = (opts and opts.active) and true or false
  local function ApplyState(self)
    if not self then  return end
    local enabled = true
    if self.IsEnabled then enabled = self:IsEnabled() and true or false end
    if not enabled then
      if self[hoverTexKey] then self[hoverTexKey]:Hide() end
      if self[downTexKey] then self[downTexKey]:Hide() end
      UpdateButtonEnabled(self)
       return
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
   end
  btn._msufApplyBtnState = ApplyState
  local oldEnter = btn:GetScript("OnEnter")
  local oldLeave = btn:GetScript("OnLeave")
  local oldDown  = btn:GetScript("OnMouseDown")
  local oldUp    = btn:GetScript("OnMouseUp")
  btn:SetScript("OnEnter", function(self, ...)
    if oldEnter then pcall(oldEnter, self, ...) end
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
   end)
  btn:SetScript("OnLeave", function(self, ...)
    if oldLeave then pcall(oldLeave, self, ...) end
    if self[hoverTexKey] then self[hoverTexKey]:Hide() end
    if self._msufBtnIsDown then self._msufBtnIsDown = false end
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
   end)
  btn:SetScript("OnMouseDown", function(self, ...)
    if oldDown then pcall(oldDown, self, ...) end
    self._msufBtnIsDown = true
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
   end)
  btn:SetScript("OnMouseUp", function(self, ...)
    if oldUp then pcall(oldUp, self, ...) end
    self._msufBtnIsDown = false
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
   end)
  -- Also update when enabled state changes
  if not btn.__msufEnabledHook and hooksecurefunc and btn.Enable then
    btn.__msufEnabledHook = true
    hooksecurefunc(btn, "Enable", function(self)
      if self._msufApplyBtnState then self._msufApplyBtnState(self) end
     end)
    hooksecurefunc(btn, "Disable", function(self)
      if self._msufApplyBtnState then self._msufApplyBtnState(self) end
     end)
  end
  if btn._msufApplyBtnState then btn._msufApplyBtnState(btn) end
 end
function Style.SkinDropButton(btn, opts)
  if not btn then  return end
  if btn.__msufMidnightDropSkinned then
    UpdateButtonEnabled(btn)
     return
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
 end
function Style.SkinIconButton(btn, opts)
  if not btn then  return end
  if btn.__msufMidnightIconSkinned then
    UpdateButtonEnabled(btn)
     return
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
 end
-- Generic button skin (works for UIPanelButtonTemplate and simple Buttons).
-- opts:
--   - isNav: bool (uses nav down alpha)
--   - active: bool (initial selected state)
function Style.SkinButton(btn, opts)
  if not Style.IsEnabled() then  return end
  if not btn then  return end
  -- Opt-out: some buttons manage their own visuals (Options action buttons).
  if btn._msufNoSlashSkin or btn.__msufMidnightActionSkinned or btn.__msufMidnightTabSkinned then
    if type(_G.MSUF_ForceShowUIPanelButtonPieces) == "function" then
      pcall(_G.MSUF_ForceShowUIPanelButtonPieces, btn)
    end
    return
  end
  -- Specialized: dropdown arrows / icon-only buttons
  if _MSUF_IsDropButton(btn) then
    return Style.SkinDropButton(btn, opts)
  end
  if _MSUF_IsIconButton(btn) then
    return Style.SkinIconButton(btn, opts)
  end
  if btn.__msufMidnightSkinned then
    UpdateButtonEnabled(btn)
     return
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
 end
function Style.SkinNavButton(btn, opts)
  if not Style.IsEnabled() then  return end
  if not btn then  return end
  if btn.__msufMidnightNavSkinned then  return end
  btn.__msufMidnightNavSkinned = true
  Style.SkinButton(btn, { isNav = true })
  btn._msufNavIsActive = false
  local sel = EnsureTex(btn, "_msufNavSelected", "ARTWORK")
  if sel then
    sel:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.navSelectedA)
    sel:Hide()
  end
  local function ApplyNavState(self)
    if not self then  return end
    local enabled = true
    if self.IsEnabled then enabled = self:IsEnabled() and true or false end
    if not enabled then
      if self._msufNavSelected then self._msufNavSelected:Hide() end
      if self._msufBtnHover then self._msufBtnHover:Hide() end
      if self._msufBtnDown then self._msufBtnDown:Hide() end
      UpdateButtonEnabled(self)
       return
    end
    if self._msufNavSelected then
      if self._msufNavIsActive then self._msufNavSelected:Show() else self._msufNavSelected:Hide() end
    end
    if self._msufApplyBtnState then self._msufApplyBtnState(self) end
   end
  btn._msufApplyNavState = ApplyNavState
  -- Public toggle used by menus to highlight the current page
  btn._msufSetActive = function(self, isActive)
    self._msufNavIsActive = isActive and true or false
    if self._msufApplyNavState then self._msufApplyNavState(self) end
   end
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
    btn:SetScript("OnLeave", function(self, ...)
      if oldLeave then pcall(oldLeave, self, ...) end
      if self._msufApplyNavState then self._msufApplyNavState(self) end
     end)
  end
  if btn._msufApplyNavState then btn._msufApplyNavState(btn) end
 end
function Style.SkinDashboardButton(btn)
  if not Style.IsEnabled() then  return end
  if not btn then  return end
  Style.SkinNavButton(btn)
  -- Alias used by some dashboards
  btn._msufSetSelected = function(self, isSelected)
    if self._msufSetActive then
      self:_msufSetActive(isSelected)
    else
      self._msufNavIsActive = isSelected and true or false
      if self._msufApplyNavState then self._msufApplyNavState(self) end
    end
   end
 end
-- Walk a frame and skin obvious widgets (buttons, checkbuttons, editboxes).
-- Use sparingly (e.g. once on panel creation) to avoid runtime overhead.
function Style.ApplyToFrame(root)
  if not Style.IsEnabled() then  return end
  if not root or not root.GetChildren then  return end
  local function SkinCheckButton(cb)
    if not cb or cb.__msufMidnightCheckSkinned then  return end
    cb.__msufMidnightCheckSkinned = true
    local label = cb.Text or (cb.GetFontString and cb:GetFontString())
    if label and label.SetTextColor then
      Style.SkinText(label)
    end
   end
  local function SkinEditBox(eb)
    if not eb or eb.__msufMidnightEditSkinned then  return end
    eb.__msufMidnightEditSkinned = true
    Style.ApplyBackdrop(eb, 0.80, true)
    local fs = eb.GetFontString and eb:GetFontString()
    if fs and fs.SetTextColor then
      Style.SkinText(fs)
    end
   end
  local function Walk(f)
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
   end
  Walk(root)
 end
-- ---------------------------------------------------------------------------
-- Edit Mode styling (no separate file; uses the same Flash/Dashboard style)
-- ---------------------------------------------------------------------------
local function _MSUF_IsFontString(obj)
  return obj and obj.GetObjectType and obj:GetObjectType() == "FontString"
end
local function _MSUF_SkinAnyTitle(frame)
  if not frame then  return end
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
 end
local function _MSUF_SkinAnyMuted(frame)
  if not frame then  return end
  local candidates = {
    frame.Subtitle, frame.subtitle,
    frame.Description, frame.description,
    frame.HelpText, frame.helpText,
    frame.Note, frame.note,
  }
  for _, fs in ipairs(candidates) do
    if _MSUF_IsFontString(fs) then Style.SkinMuted(fs) end
  end
 end
local function _MSUF_SkinKnownButtons(frame)
  if not frame then  return end
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
 end
function Style.SkinEditModePopupFrame(frame)
  if not Style.IsEnabled() then  return end
  if not frame or frame.__msufMidnightEditModeSkinned then  return end
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
 end
local function _MSUF_LooksLikeEditModePopup(f)
  -- IMPORTANT: Only skin MSUF-owned Edit Mode popups.
  -- Never touch Blizzard Edit Mode / HUD Edit Mode frames.
  if not f or type(f.GetName) ~= "function" then  return false end
  if f.GetObjectType and f:GetObjectType() ~= "Frame" then  return false end
  local n = f:GetName()
  if type(n) ~= "string" then  return false end
  -- Hard whitelist (root popups)
  if n == "MSUF_EditPositionPopup" then  return true end
  if n == "MSUF_CastbarPositionPopup" or n == "MSUF_BossCastbarPositionPopup" then  return true end
  -- Auras 2.0 Edit Mode popup (target auras, etc.)
  if n == "MSUF_AuraPositionPopup" then  return true end
  -- Allow additional MSUF edit popups by prefix (but still require popup-ish names)
  if n:find("MSUF_Edit", 1, true) then
    if n:find("Popup", 1, true) or n:find("Position", 1, true) then
       return true
    end
  end
   return false
end
function Style.ScanAndSkinEditMode()
  if not Style.IsEnabled() then  return end
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
 end
function Style.InstallEditModeAutoSkin()
  if _G.__MSUF_EDITMODE_STYLE_INSTALLED then  return end
  _G.__MSUF_EDITMODE_STYLE_INSTALLED = true
  local function RunSoon()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, function()  Style.ScanAndSkinEditMode()  end)
    else
      Style.ScanAndSkinEditMode()
    end
   end
  local function HookIfExists(globalName)
    local fn = _G[globalName]
    if type(fn) ~= "function" or not hooksecurefunc then  return end
    _G.__MSUF_EditModeStyleHooked = _G.__MSUF_EditModeStyleHooked or {}
    if _G.__MSUF_EditModeStyleHooked[globalName] then  return end
    _G.__MSUF_EditModeStyleHooked[globalName] = true
    hooksecurefunc(globalName, function()
      RunSoon()
     end)
   end
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
  boot:SetScript("OnEvent", function(self, event, arg1)
    if arg1 ~= addonName then  return end
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
   end)
  -- Initial pass
  RunSoon()
 end
-- Auto-enable edit mode styling by default (visual only, safe)
Style.InstallEditModeAutoSkin()
-- ---------------------------------------------------------------------------
-- Backwards-compatible globals (so other files can just call these)
-- ---------------------------------------------------------------------------
_G.MSUF_ApplyMidnightBackdrop = function(frame, alphaOverride, thinBorder)
  return Style.ApplyBackdrop(frame, alphaOverride, thinBorder)
end
_G.MSUF_SkinTitle = function(fs)  return Style.SkinTitle(fs) end
_G.MSUF_SkinText  = function(fs)  return Style.SkinText(fs) end
_G.MSUF_SkinMuted = function(fs)  return Style.SkinMuted(fs) end
_G.MSUF_SkinButton = function(btn, opts)  return Style.SkinButton(btn, opts) end
_G.MSUF_SkinNavButton = function(btn, isHeader, isIndented)
  return Style.SkinNavButton(btn, { header = isHeader, indented = isIndented })
end
_G.MSUF_SkinDashboardButton = function(btn)  return Style.SkinDashboardButton(btn) end
_G.MSUF_ApplyMidnightControlsToFrame = function(root)  return Style.ApplyToFrame(root) end
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
  local function _GetLabelFS(cb)
    if not cb then  return nil end
    local fs = cb.text or cb.Text
    if (not fs) and cb.GetName and cb:GetName() and _G then
      fs = _G[cb:GetName() .. "Text"]
    end
     return fs
  end
  local function _StyleToggleText(cb)
    if not cb or cb.__msufToggleTextStyled then  return end
    cb.__msufToggleTextStyled = true
    local fs = _GetLabelFS(cb)
    if not (fs and fs.SetTextColor) then  return end
    cb.__msufToggleFS = fs
    local function Update()
      if cb.IsEnabled and (not cb:IsEnabled()) then
        fs:SetTextColor(0.35, 0.35, 0.35)
      else
        if cb.GetChecked and cb:GetChecked() then
          fs:SetTextColor(1, 1, 1)
        else
          fs:SetTextColor(0.55, 0.55, 0.55)
        end
      end
     end
    cb.__msufToggleUpdate = Update
    cb:HookScript("OnShow", Update)
    cb:HookScript("OnClick", Update)
    pcall(hooksecurefunc, cb, "SetChecked", function()  Update()  end)
    pcall(hooksecurefunc, cb, "SetEnabled", function()  Update()  end)
    Update()
   end
  local function _StyleCheckmark(cb)
    if not cb or cb.__msufCheckmarkStyled then  return end
    cb.__msufCheckmarkStyled = true
    local check = (cb.GetCheckedTexture and cb:GetCheckedTexture())
    if (not check) and cb.GetName and cb:GetName() and _G then
      check = _G[cb:GetName() .. "Check"]
    end
    if not (check and check.SetTexture) then  return end
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
      local function Reapply()
        if cb.__msufCheckmarkReapplying then  return end
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
       end
      cb:HookScript("OnShow", Reapply)
      cb:HookScript("OnSizeChanged", Reapply)
    end
   end
  local function _WalkAndStyle(root)
    if not root or not root.GetChildren then  return end
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
   end
  -- Public entry points (ns + globals) so other option panels can call it.
  Style.ApplyOptionCheckmarks = function(root)
    _WalkAndStyle(root or UIParent)
   end
  ns.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
  _G.MSUF_StyleAllToggles = Style.ApplyOptionCheckmarks
end
-- Marker for gating / debug
_G.__MSUF_STYLE_VERSION = 5
_G.__MSUF_STYLE_TAG = "editmode-scanfix-v5-optionCheckmarks"

-- ---------------------------------------------------------------------------
-- UIDropDownMenuTemplate: minimal flat field + tiny 1px "blue bars" accent
-- Used by Edit Mode popups (Copy settings dropdowns). Keeps full Blizzard behavior.
-- ---------------------------------------------------------------------------
local function _MSUF_GetDropRegion(drop, suffix)
  if not drop then return nil end
  local name = (drop.GetName and drop:GetName()) or nil
  if name and _G[name .. suffix] then
    return _G[name .. suffix]
  end
  return drop[suffix]
end

function Style.SkinUIDDropDownTinyBars(drop)
  if not drop or drop.__msufTinyDropSkinned then return end
  if Style.IsEnabled and not Style.IsEnabled() then return end
  drop.__msufTinyDropSkinned = true

  -- Soft-hide Blizzard dropdown body textures (do not nil them so the template keeps working).
  local left   = drop.Left   or _MSUF_GetDropRegion(drop, "Left")
  local middle = drop.Middle or _MSUF_GetDropRegion(drop, "Middle")
  local right  = drop.Right  or _MSUF_GetDropRegion(drop, "Right")
  if left and left.SetAlpha then left:SetAlpha(0) end
  if middle and middle.SetAlpha then middle:SetAlpha(0) end
  if right and right.SetAlpha then right:SetAlpha(0) end

  -- Flat background field.
  local bg = drop._msufTinyDropBG
  if not bg then
    bg = drop:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(drop)
    drop._msufTinyDropBG = bg
  end
  if bg.SetColorTexture then
    bg:SetColorTexture(THEME.btnR, THEME.btnG, THEME.btnB, 0.88)
  end

  -- Tiny top/bottom accent bars (1px) – keep them subtle.
  local barA = 0.18
  local top = drop._msufTinyDropTop
  if not top then
    top = drop:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", drop, "TOPLEFT", 1, -1)
    top:SetPoint("TOPRIGHT", drop, "TOPRIGHT", -1, -1)
    top:SetHeight(1)
    drop._msufTinyDropTop = top
  end
  if top.SetColorTexture then
    top:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, barA)
  end

  local bottom = drop._msufTinyDropBottom
  if not bottom then
    bottom = drop:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", drop, "BOTTOMLEFT", 1, 1)
    bottom:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", -1, 1)
    bottom:SetHeight(1)
    drop._msufTinyDropBottom = bottom
  end
  if bottom.SetColorTexture then
    bottom:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, barA)
  end

  -- Thin dark border (also 1px) so the field still reads as an input.
  local border = drop._msufTinyDropBorder
  if not border and drop.CreateTexture then
    border = {
      l = drop:CreateTexture(nil, "BORDER"),
      r = drop:CreateTexture(nil, "BORDER"),
      t = drop:CreateTexture(nil, "BORDER"),
      b = drop:CreateTexture(nil, "BORDER"),
    }
    drop._msufTinyDropBorder = border
    border.l:SetPoint("TOPLEFT", drop, "TOPLEFT", 0, 0)
    border.l:SetPoint("BOTTOMLEFT", drop, "BOTTOMLEFT", 0, 0)
    border.l:SetWidth(1)
    border.r:SetPoint("TOPRIGHT", drop, "TOPRIGHT", 0, 0)
    border.r:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", 0, 0)
    border.r:SetWidth(1)
    border.t:SetPoint("TOPLEFT", drop, "TOPLEFT", 0, 0)
    border.t:SetPoint("TOPRIGHT", drop, "TOPRIGHT", 0, 0)
    border.t:SetHeight(1)
    border.b:SetPoint("BOTTOMLEFT", drop, "BOTTOMLEFT", 0, 0)
    border.b:SetPoint("BOTTOMRIGHT", drop, "BOTTOMRIGHT", 0, 0)
    border.b:SetHeight(1)
  end
  if border then
    local br, bgc, bb, ba = 0, 0, 0, 0.85
    if border.l and border.l.SetColorTexture then border.l:SetColorTexture(br, bgc, bb, ba) end
    if border.r and border.r.SetColorTexture then border.r:SetColorTexture(br, bgc, bb, ba) end
    if border.t and border.t.SetColorTexture then border.t:SetColorTexture(br, bgc, bb, ba) end
    if border.b and border.b.SetColorTexture then border.b:SetColorTexture(br, bgc, bb, ba) end
  end
end


-- ---------------------------------------------------------------------------
-- PeelDamage-inspired options/menu skin.
-- Behavior-preserving: keeps Blizzard/native widgets alive and only reskins them.
-- Dropdowns use a shared spec-driven template helper so every dropdown gets the
-- same field + popup treatment without rewriting each menu's selection logic.
-- ---------------------------------------------------------------------------
do
  local _addon = (type(addonName) == "string" and addonName ~= "" and addonName) or "MidnightSimpleUnitFrames"
  local _ADDON_PATH = "Interface/AddOns/" .. _addon .. "/"
  local SE_TEX = _ADDON_PATH .. "Media/superellipse.tga"
  local CHECK_HOLE_TEX = _ADDON_PATH .. "Media/msuf_check_superellipse_hole.tga"
  local CHECK_TICK_TEX = _ADDON_PATH .. "Media/msuf_check_tick_bold.tga"

  THEME.bgR, THEME.bgG, THEME.bgB, THEME.bgA = 0.03, 0.05, 0.12, 0.95
  THEME.edgeR, THEME.edgeG, THEME.edgeB, THEME.edgeA = 0.10, 0.20, 0.45, 0.90
  THEME.edgeThinR, THEME.edgeThinG, THEME.edgeThinB, THEME.edgeThinA = 0.10, 0.20, 0.45, 0.95
  THEME.titleR, THEME.titleG, THEME.titleB, THEME.titleA = 0.75, 0.88, 1.00, 1.00
  THEME.textR, THEME.textG, THEME.textB, THEME.textA = 0.86, 0.92, 1.00, 1.00
  THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA = 0.69, 0.74, 0.80, 0.85
  THEME.btnR, THEME.btnG, THEME.btnB, THEME.btnA = 0.07, 0.09, 0.14, 0.95
  THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, THEME.btnHoverA = 0.30, 0.60, 1.00, 0.16
  THEME.btnDownR, THEME.btnDownG, THEME.btnDownB, THEME.btnDownA = 0.30, 0.60, 1.00, 0.22
  THEME.navHoverA = 0.14
  THEME.navSelectedA = 0.24
  THEME.navDownA = 0.20

  local pillEdgeR = math.min(1, THEME.edgeR * 1.25)
  local pillEdgeG = math.min(1, THEME.edgeG * 1.25)
  local pillEdgeB = math.min(1, THEME.edgeB * 1.18)
  local pillEdgeA = math.min(1, THEME.edgeA + 0.05)

  local function CreateSuperellipseLayers(frame, key, inset, fillLayer, borderLayer)
    if not frame or not frame.CreateTexture then return nil, nil end
    inset = inset or 1
    fillLayer = fillLayer or "BACKGROUND"
    borderLayer = borderLayer or "ARTWORK"
    if frame[key .. "Fill"] and frame[key .. "Border"] then
      return frame[key .. "Fill"], frame[key .. "Border"]
    end

    local h = (frame.GetHeight and frame:GetHeight()) or 22
    local capW = math.max(4, math.floor(h * 0.5))

    local fill = {}
    fill.L = frame:CreateTexture(nil, fillLayer, nil, 0)
    fill.M = frame:CreateTexture(nil, fillLayer, nil, 0)
    fill.R = frame:CreateTexture(nil, fillLayer, nil, 0)
    fill.L:SetTexture(SE_TEX); fill.L:SetTexCoord(0.0, 0.25, 0.0, 1.0)
    fill.M:SetTexture(SE_TEX); fill.M:SetTexCoord(0.25, 0.75, 0.0, 1.0)
    fill.R:SetTexture(SE_TEX); fill.R:SetTexCoord(0.75, 1.0, 0.0, 1.0)
    fill.L:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    fill.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", inset, inset)
    fill.L:SetWidth(capW)
    fill.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
    fill.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
    fill.R:SetWidth(capW)
    fill.M:SetPoint("TOPLEFT", fill.L, "TOPRIGHT")
    fill.M:SetPoint("BOTTOMRIGHT", fill.R, "BOTTOMLEFT")
    fill._parts = { fill.L, fill.M, fill.R }
    fill.SetVertexColor = function(self, r, g, b, a)
      for _, tex in ipairs(self._parts) do tex:SetVertexColor(r, g, b, a) end
    end

    local border = {}
    border.L = frame:CreateTexture(nil, borderLayer, nil, -1)
    border.M = frame:CreateTexture(nil, borderLayer, nil, -1)
    border.R = frame:CreateTexture(nil, borderLayer, nil, -1)
    border.L:SetTexture(SE_TEX); border.L:SetTexCoord(0.0, 0.25, 0.0, 1.0)
    border.M:SetTexture(SE_TEX); border.M:SetTexCoord(0.25, 0.75, 0.0, 1.0)
    border.R:SetTexture(SE_TEX); border.R:SetTexCoord(0.75, 1.0, 0.0, 1.0)
    local bInset = math.max(0, inset - 1)
    border.L:SetPoint("TOPLEFT", frame, "TOPLEFT", bInset, -bInset)
    border.L:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", bInset, bInset)
    border.L:SetWidth(capW + 1)
    border.R:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -bInset, -bInset)
    border.R:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -bInset, bInset)
    border.R:SetWidth(capW + 1)
    border.M:SetPoint("TOPLEFT", border.L, "TOPRIGHT")
    border.M:SetPoint("BOTTOMRIGHT", border.R, "BOTTOMLEFT")
    border._parts = { border.L, border.M, border.R }
    border.SetVertexColor = function(self, r, g, b, a)
      for _, tex in ipairs(self._parts) do tex:SetVertexColor(r, g, b, a) end
    end

    frame[key .. "Fill"] = fill
    frame[key .. "Border"] = border
    return fill, border
  end

  local function ApplyPillState(btn, fill, border, active)
    if not btn or not fill or not border then return end
    local enabled = true
    if btn.IsEnabled then enabled = btn:IsEnabled() and true or false end
    if not enabled then
      fill:SetVertexColor(0.12, 0.14, 0.20, 0.55)
      border:SetVertexColor(0.22, 0.26, 0.34, 0.45)
      local fs = btn.GetFontString and btn:GetFontString() or btn.Text
      if fs and fs.SetTextColor then fs:SetTextColor(0.50, 0.52, 0.58, 0.95) end
      return
    end

    local fs = btn.GetFontString and btn:GetFontString() or btn.Text
    if fs and fs.SetTextColor then fs:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA) end

    if active then
      fill:SetVertexColor(0.11, 0.18, 0.30, 0.98)
      border:SetVertexColor(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 0.95)
      return
    end

    if btn._msufBtnIsDown then
      fill:SetVertexColor(0.10, 0.15, 0.25, 0.98)
      border:SetVertexColor(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 0.85)
    elseif btn.IsMouseOver and btn:IsMouseOver() then
      fill:SetVertexColor(0.09, 0.13, 0.22, 0.98)
      border:SetVertexColor(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 1.0)
    else
      fill:SetVertexColor(THEME.btnR + 0.02, THEME.btnG + 0.02, THEME.btnB + 0.02, 0.96)
      border:SetVertexColor(pillEdgeR, pillEdgeG, pillEdgeB, pillEdgeA)
    end
  end

  local function InstallPillScripts(btn, fill, border, activeGetter)
    if not btn or btn.__msufPeelPillHooked then return end
    btn.__msufPeelPillHooked = true
    local oldEnter = btn:GetScript("OnEnter")
    local oldLeave = btn:GetScript("OnLeave")
    local oldDown = btn:GetScript("OnMouseDown")
    local oldUp = btn:GetScript("OnMouseUp")
    btn:SetScript("OnEnter", function(self, ...)
      if oldEnter then oldEnter(self, ...) end
      ApplyPillState(self, fill, border, activeGetter and activeGetter(self))
    end)
    btn:SetScript("OnLeave", function(self, ...)
      if oldLeave then oldLeave(self, ...) end
      self._msufBtnIsDown = false
      ApplyPillState(self, fill, border, activeGetter and activeGetter(self))
    end)
    btn:SetScript("OnMouseDown", function(self, ...)
      if oldDown then oldDown(self, ...) end
      self._msufBtnIsDown = true
      ApplyPillState(self, fill, border, activeGetter and activeGetter(self))
    end)
    btn:SetScript("OnMouseUp", function(self, ...)
      if oldUp then oldUp(self, ...) end
      self._msufBtnIsDown = false
      ApplyPillState(self, fill, border, activeGetter and activeGetter(self))
    end)
    if hooksecurefunc and not btn.__msufPeelEnableHook and btn.Enable and btn.Disable then
      btn.__msufPeelEnableHook = true
      hooksecurefunc(btn, "Enable", function(self)
        ApplyPillState(self, fill, border, activeGetter and activeGetter(self))
      end)
      hooksecurefunc(btn, "Disable", function(self)
        ApplyPillState(self, fill, border, activeGetter and activeGetter(self))
      end)
    end
  end

  function Style.ApplyBackdrop(frame, alphaOverride, thinBorder)
    if not Style.IsEnabled() then return end
    local b = EnsureBackdropFrame(frame)
    if not b or not b.SetBackdrop then return end
    local edgeSize = 1
    b:SetBackdrop({
      bgFile = WHITE8X8,
      edgeFile = WHITE8X8,
      edgeSize = edgeSize,
      insets = { left = edgeSize, right = edgeSize, top = edgeSize, bottom = edgeSize },
    })
    b:SetBackdropColor(THEME.bgR, THEME.bgG, THEME.bgB, alphaOverride or THEME.bgA)
    local er, eg, eb, ea = THEME.edgeThinR, THEME.edgeThinG, THEME.edgeThinB, THEME.edgeThinA
    if not thinBorder then
      er, eg, eb, ea = THEME.edgeR, THEME.edgeG, THEME.edgeB, THEME.edgeA
    end
    b:SetBackdropBorderColor(er, eg, eb, ea)
    b:Show()
  end

  local function SkinButtonPeel(btn, opts)
    if not btn then return end
    if _MSUF_IsDropButton(btn) then
      Style.SkinDropButton(btn, opts)
      return
    end
    if _MSUF_IsIconButton(btn) then
      if not btn.__msufPeelIconSkinned then
        btn.__msufPeelIconSkinned = true
        Style.ApplyBackdrop(btn, 0.0, true)
        local bg = EnsureTex(btn, "_msufPeelIconBG", "BACKGROUND")
        if bg and bg.SetColorTexture then bg:SetColorTexture(0.08, 0.10, 0.16, 0.96) end
        local hov = EnsureTex(btn, "_msufPeelIconHover", "BORDER")
        if hov and hov.SetColorTexture then
          hov:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 0.14)
          hov:Hide()
        end
        _MSUF_InstallHoverDownScripts(btn, "_msufPeelIconHover", "_msufPeelIconHover", opts)
      end
      return
    end
    if not btn.__msufPeelButtonSkinned then
      btn.__msufPeelButtonSkinned = true
      local left = btn.Left or _MSUF_GetDropRegion(btn, "Left")
      local middle = btn.Middle or _MSUF_GetDropRegion(btn, "Middle")
      local right = btn.Right or _MSUF_GetDropRegion(btn, "Right")
      if left and left.SetAlpha then left:SetAlpha(0) end
      if middle and middle.SetAlpha then middle:SetAlpha(0) end
      if right and right.SetAlpha then right:SetAlpha(0) end
      local fill, border = CreateSuperellipseLayers(btn, "_msufPeelBtn", 1, "BACKGROUND", "BORDER")
      btn._msufPeelFill = fill
      btn._msufPeelBorder = border
      InstallPillScripts(btn, fill, border, function() return false end)
    end
    ApplyPillState(btn, btn._msufPeelFill, btn._msufPeelBorder, false)
  end

  local function SkinNavButtonPeel(btn)
    if not btn then return end
    if not btn.__msufPeelNavSkinned then
      btn.__msufPeelNavSkinned = true
      Style.SkinButton(btn, { isNav = true })
      btn._msufNavIsActive = btn._msufNavIsActive and true or false
      InstallPillScripts(btn, btn._msufPeelFill, btn._msufPeelBorder, function(self)
        return self._msufNavIsActive and true or false
      end)
      btn._msufSetActive = function(self, isActive)
        self._msufNavIsActive = isActive and true or false
        ApplyPillState(self, self._msufPeelFill, self._msufPeelBorder, self._msufNavIsActive)
      end
      btn._msufSetSelected = btn._msufSetActive
    end
    ApplyPillState(btn, btn._msufPeelFill, btn._msufPeelBorder, btn._msufNavIsActive)
  end

  local function SkinEditBoxPeel(eb)
    if not eb or eb.__msufPeelEditSkinned then return end
    eb.__msufPeelEditSkinned = true
    Style.ApplyBackdrop(eb, 0.96, true)
    local n = eb.GetName and eb:GetName() or nil
    if n and _G then
      for _, suffix in ipairs({ "Left", "Right", "Middle", "Mid" }) do
        local tex = _G[n .. suffix]
        if tex and tex.SetAlpha then tex:SetAlpha(0) end
      end
    end
    local fs = eb.GetFontString and eb:GetFontString() or nil
    if fs and fs.SetTextColor then fs:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA) end
    eb:HookScript("OnEditFocusGained", function(self)
      local bd = self._msufMidnightBackdrop
      if bd and bd.SetBackdropBorderColor then
        bd:SetBackdropBorderColor(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 1)
      end
    end)
    eb:HookScript("OnEditFocusLost", function(self)
      local bd = self._msufMidnightBackdrop
      if bd and bd.SetBackdropBorderColor then
        bd:SetBackdropBorderColor(THEME.edgeThinR, THEME.edgeThinG, THEME.edgeThinB, THEME.edgeThinA)
      end
    end)
  end

  local function SkinSliderPeel(slider)
    if not slider or slider.__msufPeelSliderSkinned then return end
    slider.__msufPeelSliderSkinned = true
    local name = slider.GetName and slider:GetName() or nil
    local low = name and _G[name .. "Low"] or nil
    local high = name and _G[name .. "High"] or nil
    local text = name and _G[name .. "Text"] or nil
    if low and low.SetTextColor then low:SetTextColor(THEME.textR, THEME.textG, THEME.textB, 0.85) end
    if high and high.SetTextColor then high:SetTextColor(THEME.textR, THEME.textG, THEME.textB, 0.85) end
    if text and text.SetTextColor then text:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA) end

    if not slider._msufPeelTrack and slider.CreateTexture then
      local track = slider:CreateTexture(nil, "BACKGROUND")
      track:SetPoint("LEFT", slider, "LEFT", 0, 0)
      track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
      track:SetHeight(6)
      track:SetColorTexture(0.07, 0.09, 0.14, 0.98)
      slider._msufPeelTrack = track
      local fill = slider:CreateTexture(nil, "ARTWORK")
      fill:SetPoint("LEFT", slider, "LEFT", 0, 0)
      fill:SetHeight(2)
      fill:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
      fill:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 0.55)
      slider._msufPeelTrackFill = fill
    end

    local thumb = slider.GetThumbTexture and slider:GetThumbTexture() or nil
    if thumb then
      thumb:SetSize(14, 14)
      if thumb.SetColorTexture then
        thumb:SetColorTexture(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 1)
      elseif thumb.SetVertexColor then
        thumb:SetVertexColor(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 1)
      end
    end
  end

  local DD_DEFAULT_SPEC = {
    width = 160,
    height = 22,
    leftInset = 15,
    topInset = -1,
    textLeft = 10,
    textRight = 22,
    arrowWidth = 18,
    bgR = 0.06, bgG = 0.08, bgB = 0.14, bgA = 0.98,
    borderR = pillEdgeR, borderG = pillEdgeG, borderB = pillEdgeB, borderA = 0.90,
    accentR = THEME.btnHoverR, accentG = THEME.btnHoverG, accentB = THEME.btnHoverB, accentA = 0.55,
    hoverR = 1.00, hoverG = 1.00, hoverB = 1.00, hoverA = 0.045,
    downR = THEME.btnHoverR, downG = THEME.btnHoverG, downB = THEME.btnHoverB, downA = 0.10,
    disabledA = 0.45,
    arrowText = "v",
    dividerA = 0.42,
    shadowA = 0.20,
    fontMinSize = 12,
    fontSizeAdjust = 0.5,
    textShadowA = 0.95,
    menuBgR = 0.02, menuBgG = 0.03, menuBgB = 0.06, menuBgA = 0.985,
    menuBorderR = pillEdgeR, menuBorderG = pillEdgeG, menuBorderB = pillEdgeB, menuBorderA = 1.00,
    menuHoverR = 1.00, menuHoverG = 1.00, menuHoverB = 1.00, menuHoverA = 0.055,
    menuSelectR = THEME.btnHoverR, menuSelectG = THEME.btnHoverG, menuSelectB = THEME.btnHoverB, menuSelectA = 0.22,
  }

  local function CopySpec(spec)
    local out = {}
    for k, v in pairs(DD_DEFAULT_SPEC) do out[k] = v end
    if type(spec) == "table" then
      for k, v in pairs(spec) do out[k] = v end
    end
    return out
  end

  local function IsDropdownFrame(frame)
    if not frame then return false end
    local n = frame.GetName and frame:GetName() or nil
    return type(n) == "string" and (n:find("DropDown", 1, true) or n:find("Dropdown", 1, true))
  end

  local function GetNativeDropButton(drop)
    return drop and (drop._msufNativeButton or drop.Button or _MSUF_GetDropRegion(drop, "Button")) or nil
  end

  local function GetNativeDropText(drop)
    return drop and (drop._msufNativeText or drop.Text or _MSUF_GetDropRegion(drop, "Text")) or nil
  end

  local function GetDropdownDisplayText(drop)
    local txt = GetNativeDropText(drop)
    if txt and txt.GetText then
      local v = txt:GetText()
      if type(v) == "string" and v ~= "" then return v end
    end
    return " "
  end

  local function SetPeelDropdownVisible(drop, shown)
    if not drop then return end
    local show = shown and true or false
    local parts = {
      drop._msufPeelButton,
      drop._msufPeelText,
      drop._msufPeelArrow,
      drop._msufPeelDivider,
      drop._msufPeelShadow,
    }
    for i = 1, #parts do
      local obj = parts[i]
      if obj then
        if show then
          if obj.Show then obj:Show() end
        else
          if obj.Hide then obj:Hide() end
        end
      end
    end
  end

  local function IsDropdownEffectivelyShown(drop)
    if not drop or not drop.IsShown or not drop:IsShown() then return false end
    local nativeBtn = GetNativeDropButton(drop)
    if nativeBtn and nativeBtn.IsShown and not nativeBtn:IsShown() then
      return false
    end
    return true
  end

  local function SyncPeelDropdownState(drop)
    if not drop or not drop._msufPeelButton then return end
    if not Style.UseModernDropdowns() then
      SetPeelDropdownVisible(drop, false)
      return
    end
    local visible = IsDropdownEffectivelyShown(drop)
    SetPeelDropdownVisible(drop, visible)
    if not visible then
      return
    end
    local spec = drop._msufPeelSpec or DD_DEFAULT_SPEC
    local nativeBtn = GetNativeDropButton(drop)
    local enabled = true
    if nativeBtn and nativeBtn.IsEnabled then enabled = nativeBtn:IsEnabled() and true or false end

    if drop._msufPeelButton.SetAlpha then drop._msufPeelButton:SetAlpha(enabled and 1 or spec.disabledA) end
    if drop._msufPeelButton.EnableMouse then drop._msufPeelButton:EnableMouse(enabled) end

    local fill = drop._msufPeelFill
    local border = drop._msufPeelBorder
    if fill and border then
      if not enabled then
        fill:SetVertexColor(0.12, 0.14, 0.20, 0.58)
        border:SetVertexColor(0.22, 0.26, 0.34, 0.42)
      elseif drop._msufPeelButton._msufBtnIsDown then
        fill:SetVertexColor(0.10, 0.15, 0.25, 0.98)
        border:SetVertexColor(spec.accentR, spec.accentG, spec.accentB, 0.90)
      elseif drop._msufPeelButton.IsMouseOver and drop._msufPeelButton:IsMouseOver() then
        fill:SetVertexColor(0.09, 0.13, 0.22, 0.98)
        border:SetVertexColor(spec.accentR, spec.accentG, spec.accentB, 1.0)
      else
        fill:SetVertexColor(spec.bgR, spec.bgG, spec.bgB, spec.bgA)
        border:SetVertexColor(spec.borderR, spec.borderG, spec.borderB, spec.borderA)
      end
    end

    if drop._msufPeelShadow then
      drop._msufPeelShadow:SetAlpha(enabled and spec.shadowA or 0.08)
    end
    if drop._msufPeelDivider then
      drop._msufPeelDivider:SetAlpha(enabled and spec.dividerA or 0.16)
    end
    if drop._msufPeelText and drop._msufPeelText.SetTextColor then
      if enabled then
        drop._msufPeelText:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA)
      else
        drop._msufPeelText:SetTextColor(THEME.mutedR, THEME.mutedG, THEME.mutedB, 0.9)
      end
    end
    if drop._msufPeelArrow and drop._msufPeelArrow.SetTextColor then
      if enabled then
        drop._msufPeelArrow:SetTextColor(THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA)
      else
        drop._msufPeelArrow:SetTextColor(THEME.mutedR, THEME.mutedG, THEME.mutedB, 0.45)
      end
    end
  end

  local function ApplyReadableDropdownFont(dst, src, spec)
    if not dst then return end
    spec = spec or DD_DEFAULT_SPEC

    local fontObj = src and src.GetFontObject and src:GetFontObject() or nil
    if fontObj and dst.SetFontObject then
      dst:SetFontObject(fontObj)
    else
      dst:SetFontObject(GameFontHighlightSmall)
    end

    local fontPath, fontSize, fontFlags = src and src.GetFont and src:GetFont() or nil, nil, nil
    if type(fontPath) == "string" then
      local _, s, f = src:GetFont()
      fontSize = tonumber(s)
      fontFlags = f
      if fontSize then
        local adjusted = math.max(spec.fontMinSize or 12, math.floor(fontSize + (spec.fontSizeAdjust or 0.5) + 0.5))
        dst:SetFont(fontPath, adjusted, fontFlags)
      end
    end

    if dst.SetShadowColor then dst:SetShadowColor(0, 0, 0, spec.textShadowA or 0.95) end
    if dst.SetShadowOffset then dst:SetShadowOffset(1, -1) end
    if dst.SetSpacing then dst:SetSpacing(0) end
    if dst.SetWordWrap then dst:SetWordWrap(false) end
    if dst.SetMaxLines then dst:SetMaxLines(1) end
    if dst.SetNonSpaceWrap then dst:SetNonSpaceWrap(false) end
  end

  local function UpdatePeelDropdownText(drop, explicitText)
    if not drop or not drop._msufPeelText then return end
    ApplyReadableDropdownFont(drop._msufPeelText, GetNativeDropText(drop), drop._msufPeelSpec)
    drop._msufPeelText:SetText(explicitText or GetDropdownDisplayText(drop))
    SyncPeelDropdownState(drop)
  end

  local function UpdatePeelDropdownWidth(drop, width)
    if not drop then return end
    local spec = drop._msufPeelSpec or DD_DEFAULT_SPEC
    local w = tonumber(width) or tonumber(drop._msufButtonWidth) or tonumber(drop._msufPeelWidth) or spec.width
    if w < 60 then w = 60 end
    drop._msufPeelWidth = w
    if drop._msufPeelButton and drop._msufPeelButton.SetWidth then
      drop._msufPeelButton:SetWidth(w)
    end
    if drop._msufPeelFill and drop._msufPeelFill.L and drop._msufPeelFill.R and drop._msufPeelFill.M then
      local capW = math.max(4, math.floor(((spec.height or 22) * 0.5) + 0.5))
      drop._msufPeelFill.L:SetWidth(capW)
      drop._msufPeelFill.R:SetWidth(capW)
      drop._msufPeelBorder.L:SetWidth(capW + 1)
      drop._msufPeelBorder.R:SetWidth(capW + 1)
    end
    if drop._msufPeelText then
      drop._msufPeelText:ClearAllPoints()
      drop._msufPeelText:SetPoint("LEFT", drop._msufPeelButton, "LEFT", spec.textLeft, 0)
      drop._msufPeelText:SetPoint("RIGHT", drop._msufPeelButton, "RIGHT", -(spec.arrowWidth + 8), 0)
    end
    if drop._msufPeelArrow then
      drop._msufPeelArrow:ClearAllPoints()
      drop._msufPeelArrow:SetPoint("RIGHT", drop._msufPeelButton, "RIGHT", -8, -1)
    end
    if drop._msufPeelDivider then
      drop._msufPeelDivider:ClearAllPoints()
      drop._msufPeelDivider:SetPoint("TOPRIGHT", drop._msufPeelButton, "TOPRIGHT", -(spec.arrowWidth + 4), -4)
      drop._msufPeelDivider:SetPoint("BOTTOMRIGHT", drop._msufPeelButton, "BOTTOMRIGHT", -(spec.arrowWidth + 4), 4)
    end
    if drop._msufPeelShadow then
      drop._msufPeelShadow:ClearAllPoints()
      drop._msufPeelShadow:SetPoint("TOPLEFT", drop._msufPeelButton, "TOPLEFT", 0, -1)
      drop._msufPeelShadow:SetPoint("TOPRIGHT", drop._msufPeelButton, "TOPRIGHT", 0, -1)
      drop._msufPeelShadow:SetHeight(1)
    end
  end

  local function HideDefaultDropRegions(drop)
    local left = drop.Left or _MSUF_GetDropRegion(drop, "Left")
    local middle = drop.Middle or _MSUF_GetDropRegion(drop, "Middle")
    local right = drop.Right or _MSUF_GetDropRegion(drop, "Right")
    if left and left.SetAlpha then left:SetAlpha(0) end
    if middle and middle.SetAlpha then middle:SetAlpha(0) end
    if right and right.SetAlpha then right:SetAlpha(0) end
    local txt = GetNativeDropText(drop)
    if txt then
      if txt.SetAlpha then txt:SetAlpha(0) end
      if txt.Hide then txt:Hide() end
    end
    local btn = GetNativeDropButton(drop)
    if btn then
      local nt = btn.GetNormalTexture and btn:GetNormalTexture() or nil
      local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
      local ht = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
      if nt and nt.SetAlpha then nt:SetAlpha(0) end
      if pt and pt.SetAlpha then pt:SetAlpha(0) end
      if ht and ht.SetAlpha then ht:SetAlpha(0) end
      if btn.SetAlpha then btn:SetAlpha(0.01) end
    end
  end

  local function EnsureDropdownHooks(drop)
    if not drop or drop.__msufPeelButtonHooks then return end
    drop.__msufPeelButtonHooks = true
    local nativeBtn = GetNativeDropButton(drop)
    if nativeBtn and hooksecurefunc then
      if nativeBtn.Enable then hooksecurefunc(nativeBtn, "Enable", function() SyncPeelDropdownState(drop) end) end
      if nativeBtn.Disable then hooksecurefunc(nativeBtn, "Disable", function() SyncPeelDropdownState(drop) end) end
      if nativeBtn.Show then hooksecurefunc(nativeBtn, "Show", function() SyncPeelDropdownState(drop) end) end
      if nativeBtn.Hide then hooksecurefunc(nativeBtn, "Hide", function() SyncPeelDropdownState(drop) end) end
    end
    if drop.HookScript then
      drop:HookScript("OnShow", function(self)
        if Style.UseModernDropdowns() then
          SyncPeelDropdownState(self)
        else
          SetPeelDropdownVisible(self, false)
        end
      end)
      drop:HookScript("OnHide", function(self)
        if self._msufPeelButton then self._msufPeelButton._msufBtnIsDown = false end
        SetPeelDropdownVisible(self, false)
      end)
    end
  end

  local function RestoreNativeDropRegions(drop)
    local left = drop and (drop.Left or _MSUF_GetDropRegion(drop, "Left")) or nil
    local middle = drop and (drop.Middle or _MSUF_GetDropRegion(drop, "Middle")) or nil
    local right = drop and (drop.Right or _MSUF_GetDropRegion(drop, "Right")) or nil
    if left and left.SetAlpha then left:SetAlpha(1) end
    if middle and middle.SetAlpha then middle:SetAlpha(1) end
    if right and right.SetAlpha then right:SetAlpha(1) end
    local txt = GetNativeDropText(drop)
    if txt then
      if txt.SetAlpha then txt:SetAlpha(1) end
      if txt.Show then txt:Show() end
    end
    local btn = GetNativeDropButton(drop)
    if btn then
      local nt = btn.GetNormalTexture and btn:GetNormalTexture() or nil
      local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
      local ht = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
      if nt and nt.SetAlpha then nt:SetAlpha(1) end
      if pt and pt.SetAlpha then pt:SetAlpha(1) end
      if ht and ht.SetAlpha then ht:SetAlpha(1) end
      if btn.SetAlpha then btn:SetAlpha(1) end
      if btn.EnableMouse then btn:EnableMouse(true) end
      if btn.Show then btn:Show() end
    end
  end

  local function RevertPeelDropdownTemplate(drop)
    if not drop then return nil end
    if drop._msufPeelButton then drop._msufPeelButton._msufBtnIsDown = false end
    SetPeelDropdownVisible(drop, false)
    RestoreNativeDropRegions(drop)
    drop.__msufPeelDropSkinned = nil
    return drop
  end

  function Style.ApplyPeelDropdownTemplate(drop, spec)
    if not drop then return nil end
    drop.__msufMSUFDropdown = true
    if not Style.UseModernDropdowns() then
      return RevertPeelDropdownTemplate(drop)
    end
    drop._msufPeelSpec = CopySpec(spec or drop._msufPeelSpec)
    spec = drop._msufPeelSpec
    if not drop._msufNativeButton then drop._msufNativeButton = GetNativeDropButton(drop) end
    if not drop._msufNativeText then drop._msufNativeText = GetNativeDropText(drop) end
    HideDefaultDropRegions(drop)

    local btn = drop._msufPeelButton
    if not btn then
      btn = CreateFrame("Button", nil, drop)
      btn:SetPoint("TOPLEFT", drop, "TOPLEFT", spec.leftInset, spec.topInset)
      btn:SetHeight(spec.height)
      btn:SetFrameLevel((drop.GetFrameLevel and drop:GetFrameLevel() or 1) + 5)
      btn:RegisterForClicks("LeftButtonUp")
      btn:SetHitRectInsets(0, 0, 0, 0)

      local fill, border = CreateSuperellipseLayers(btn, "_msufDrop", 1, "ARTWORK", "ARTWORK")
      fill:SetVertexColor(spec.bgR, spec.bgG, spec.bgB, spec.bgA)
      border:SetVertexColor(spec.borderR, spec.borderG, spec.borderB, spec.borderA)

      local shadow = btn:CreateTexture(nil, "BACKGROUND")
      shadow:SetColorTexture(spec.accentR, spec.accentG, spec.accentB, spec.shadowA)
      shadow:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -1)
      shadow:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 0, -1)
      shadow:SetHeight(1)

      local divider = btn:CreateTexture(nil, "ARTWORK")
      divider:SetColorTexture(spec.borderR, spec.borderG, spec.borderB, spec.dividerA)
      divider:SetWidth(1)

      local hover = btn:CreateTexture(nil, "HIGHLIGHT")
      hover:SetTexture(SE_TEX)
      hover:SetTexCoord(0.25, 0.75, 0.0, 1.0)
      hover:SetPoint("TOPLEFT", btn, "TOPLEFT", 9, -1)
      hover:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -9, 1)
      hover:SetVertexColor(spec.hoverR, spec.hoverG, spec.hoverB, spec.hoverA)

      local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      arrow:SetPoint("RIGHT", btn, "RIGHT", -8, -1)
      arrow:SetText(spec.arrowText)
      arrow:SetTextColor(THEME.mutedR, THEME.mutedG, THEME.mutedB, THEME.mutedA)

      local textFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      textFS:SetJustifyH("LEFT")
      textFS:SetJustifyV("MIDDLE")
      textFS:SetPoint("LEFT", btn, "LEFT", spec.textLeft, 0)
      textFS:SetPoint("RIGHT", btn, "RIGHT", -(spec.arrowWidth + 8), 0)
      ApplyReadableDropdownFont(textFS, drop._msufNativeText, spec)
      textFS:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA)

      btn:SetScript("OnMouseDown", function(self)
        self._msufBtnIsDown = true
        SyncPeelDropdownState(drop)
      end)
      btn:SetScript("OnMouseUp", function(self)
        self._msufBtnIsDown = false
        SyncPeelDropdownState(drop)
      end)
      btn:SetScript("OnEnter", function(self)
        SyncPeelDropdownState(drop)
      end)
      btn:SetScript("OnLeave", function(self)
        self._msufBtnIsDown = false
        SyncPeelDropdownState(drop)
      end)
      btn:SetScript("OnClick", function(self)
        local nativeBtn = GetNativeDropButton(drop)
        if nativeBtn and nativeBtn.IsEnabled and not nativeBtn:IsEnabled() then return end
        if type(ToggleDropDownMenu) == "function" then
          ToggleDropDownMenu(1, nil, drop, self, 0, -1)
        end
      end)
      drop._msufPeelButton = btn
      drop._msufPeelFill = fill
      drop._msufPeelBorder = border
      drop._msufPeelShadow = shadow
      drop._msufPeelDivider = divider
      drop._msufPeelText = textFS
      drop._msufPeelArrow = arrow
    end

    SetPeelDropdownVisible(drop, IsDropdownEffectivelyShown(drop))
    btn:SetPoint("TOPLEFT", drop, "TOPLEFT", spec.leftInset, spec.topInset)
    UpdatePeelDropdownWidth(drop, spec.width)
    EnsureDropdownHooks(drop)
    UpdatePeelDropdownText(drop)
    SyncPeelDropdownState(drop)
    drop.__msufPeelDropSkinned = true
    return drop
  end

  Style.SkinUIDDropDownTinyBars = Style.ApplyPeelDropdownTemplate
  ns.MSUF_CreateStyledDropdown = function(name, parent, spec)
    local drop = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    drop.__msufMSUFDropdown = true
    if Style.UseModernDropdowns() then
      Style.ApplyPeelDropdownTemplate(drop, spec)
    else
      RevertPeelDropdownTemplate(drop)
    end
    return drop
  end
  _G.MSUF_CreateStyledDropdown = ns.MSUF_CreateStyledDropdown
  ns.MSUF_PeelDropdownTemplate = Style.ApplyPeelDropdownTemplate
  _G.MSUF_PeelDropdownTemplate = Style.ApplyPeelDropdownTemplate
  ns.MSUF_PeelDropdownDefaults = DD_DEFAULT_SPEC
  _G.MSUF_PeelDropdownDefaults = DD_DEFAULT_SPEC
  ns.MSUF_RevertDropdownTemplate = RevertPeelDropdownTemplate
  _G.MSUF_RevertDropdownTemplate = RevertPeelDropdownTemplate

  local function SkinCheckButtonPeel(cb)
    if not cb or cb.__msufPeelCheckSkinned then return end
    cb.__msufPeelCheckSkinned = true
    local check = (cb.GetCheckedTexture and cb:GetCheckedTexture())
    if (not check) and cb.GetName and cb:GetName() and _G then
      check = _G[cb:GetName() .. "Check"]
    end
    local normal = cb.GetNormalTexture and cb:GetNormalTexture() or nil
    if normal and normal.SetAlpha then normal:SetAlpha(0) end
    if not cb._msufPeelHole and cb.CreateTexture then
      local hole = cb:CreateTexture(nil, "BACKGROUND")
      hole:SetAllPoints(cb)
      hole:SetTexture(CHECK_HOLE_TEX)
      hole:SetVertexColor(0.12, 0.14, 0.20, 0.98)
      cb._msufPeelHole = hole
    end
    if check and check.SetTexture then
      check:SetTexture(CHECK_TICK_TEX)
      if check.SetVertexColor then check:SetVertexColor(THEME.btnHoverR, THEME.btnHoverG, THEME.btnHoverB, 1) end
      if check.SetSize then
        local s = math.max(12, math.floor((((cb.GetHeight and cb:GetHeight()) or 24) * 0.72) + 0.5))
        check:SetSize(s, s)
      end
    end
    local label = cb.Text or (cb.GetFontString and cb:GetFontString()) or nil
    if label and label.SetTextColor then label:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA) end
  end

  local function _MSUF_CaptureDropDownButtonState(button, textFS, hl)
    if not button then return end
    if button._msufOrigHeight == nil and button.GetHeight then
      button._msufOrigHeight = button:GetHeight()
    end
    if textFS and not textFS._msufOrigDropPointsCaptured then
      textFS._msufOrigDropPointsCaptured = true
      textFS._msufOrigDropPoints = {}
      local n = textFS.GetNumPoints and textFS:GetNumPoints() or 0
      for i = 1, n do
        local point, relTo, relPoint, xOfs, yOfs = textFS:GetPoint(i)
        textFS._msufOrigDropPoints[i] = { point, relTo, relPoint, xOfs, yOfs }
      end
      textFS._msufOrigDropJustifyH = textFS.GetJustifyH and textFS:GetJustifyH() or nil
    end
    if hl and not hl._msufOrigDropPointsCaptured and hl.GetNumPoints then
      hl._msufOrigDropPointsCaptured = true
      hl._msufOrigDropPoints = {}
      local n = hl:GetNumPoints() or 0
      for i = 1, n do
        local point, relTo, relPoint, xOfs, yOfs = hl:GetPoint(i)
        hl._msufOrigDropPoints[i] = { point, relTo, relPoint, xOfs, yOfs }
      end
    end
  end

  local function _MSUF_RestoreFontStringPoints(fs)
    if not fs or not fs._msufOrigDropPointsCaptured then return end
    if fs.ClearAllPoints then fs:ClearAllPoints() end
    local pts = fs._msufOrigDropPoints or {}
    if #pts > 0 and fs.SetPoint then
      for i = 1, #pts do
        local p = pts[i]
        fs:SetPoint(p[1], p[2], p[3], p[4], p[5])
      end
    end
    if fs._msufOrigDropJustifyH and fs.SetJustifyH then
      fs:SetJustifyH(fs._msufOrigDropJustifyH)
    end
  end

  local function _MSUF_RestoreTexturePoints(tex)
    if not tex or not tex._msufOrigDropPointsCaptured then return end
    if tex.ClearAllPoints then tex:ClearAllPoints() end
    local pts = tex._msufOrigDropPoints or {}
    if #pts > 0 and tex.SetPoint then
      for i = 1, #pts do
        local p = pts[i]
        tex:SetPoint(p[1], p[2], p[3], p[4], p[5])
      end
    end
  end

  local function SkinDropDownLists()
    if not Style.UseModernDropdowns() then
      return
    end

    local openOwner = _G.UIDROPDOWNMENU_OPEN_MENU
    if not (openOwner and openOwner.__msufMSUFDropdown and openOwner.__msufPeelDropSkinned) then
      return
    end

    for level = 1, (_G.UIDROPDOWNMENU_MAXLEVELS or 2) do
      local list = _G["DropDownList" .. level]
      if list and list.IsShown and list:IsShown() then
        local spec = openOwner._msufPeelSpec or DD_DEFAULT_SPEC
        local mb = _G["DropDownList" .. level .. "MenuBackdrop"]
        local bb = _G["DropDownList" .. level .. "Backdrop"]

        if not list._msufPeelBackdrop then
          local skin = CreateFrame("Frame", nil, list, "BackdropTemplate")
          skin:SetFrameLevel(math.max(0, (list.GetFrameLevel and list:GetFrameLevel() or 1) - 1))
          skin:SetAllPoints(list)
          skin:SetBackdrop({
            bgFile = WHITE8X8,
            edgeFile = WHITE8X8,
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
          })
          list._msufPeelBackdrop = skin
        end

        list._msufPeelBackdrop:SetBackdropColor(spec.menuBgR, spec.menuBgG, spec.menuBgB, spec.menuBgA)
        list._msufPeelBackdrop:SetBackdropBorderColor(spec.menuBorderR, spec.menuBorderG, spec.menuBorderB, spec.menuBorderA)
        if list._msufPeelBackdrop.Show then list._msufPeelBackdrop:Show() end

        if mb then
          if mb.Hide then mb:Hide() end
          if mb.SetAlpha then mb:SetAlpha(0) end
          if mb.NineSlice and mb.NineSlice.Hide then mb.NineSlice:Hide() end
        end
        if bb then
          if bb.Hide then bb:Hide() end
          if bb.SetAlpha then bb:SetAlpha(0) end
        end

        for i = 1, (_G.UIDROPDOWNMENU_MAXBUTTONS or 32) do
          local b = _G["DropDownList" .. level .. "Button" .. i]
          if b then
            if not b._msufPeelSel then
              b._msufPeelSel = b:CreateTexture(nil, "BACKGROUND")
              b._msufPeelSel:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
              b._msufPeelSel:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
            end
            b._msufPeelSel:SetColorTexture(spec.menuSelectR, spec.menuSelectG, spec.menuSelectB, spec.menuSelectA)
            local fs = _G[b:GetName() .. "NormalText"]
            local hl = b.GetHighlightTexture and b:GetHighlightTexture() or nil
            _MSUF_CaptureDropDownButtonState(b, fs, hl)
            if fs then
              ApplyReadableDropdownFont(fs, fs, DD_DEFAULT_SPEC)
              fs:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA)
              fs:ClearAllPoints()
              fs:SetPoint("LEFT", b, "LEFT", 10, 0)
              fs:SetPoint("RIGHT", b, "RIGHT", -10, 0)
              fs:SetJustifyH("LEFT")
            end
            if b.SetHeight then b:SetHeight(20) end
            if hl and hl.SetColorTexture then
              hl:SetColorTexture(spec.menuHoverR, spec.menuHoverG, spec.menuHoverB, spec.menuHoverA)
              if hl.SetPoint then
                hl:ClearAllPoints()
                hl:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
                hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
              end
            end
            local check = _G[b:GetName() .. "Check"] or b.Check
            local uncheck = _G[b:GetName() .. "UnCheck"] or b.UnCheck
            local checked = false
            if check and check.IsShown and check:IsShown() then checked = true end
            b._msufPeelSel:SetShown(checked)
            if check and check.Hide then check:Hide() end
            if uncheck and uncheck.Hide then uncheck:Hide() end
            if b:IsEnabled() then
              if fs then fs:SetTextColor(THEME.textR, THEME.textG, THEME.textB, THEME.textA) end
            else
              if fs then fs:SetTextColor(THEME.mutedR, THEME.mutedG, THEME.mutedB, 0.9) end
            end
          end
        end
      end
    end
  end
  Style.ReskinDropdownLists = SkinDropDownLists
  ns.MSUF_ReskinDropdownLists = SkinDropDownLists
  _G.MSUF_ReskinDropdownLists = SkinDropDownLists

  if hooksecurefunc and not _G.__MSUF_PEEL_DROPDOWN_HOOKS_INSTALLED then
    _G.__MSUF_PEEL_DROPDOWN_HOOKS_INSTALLED = true
    if type(_G.UIDropDownMenu_SetText) == "function" then
      hooksecurefunc("UIDropDownMenu_SetText", function(drop, text)
        if not (Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned) then return end
        UpdatePeelDropdownText(drop, text)
      end)
    end
    if type(_G.UIDropDownMenu_SetWidth) == "function" then
      hooksecurefunc("UIDropDownMenu_SetWidth", function(drop, width)
        if not (Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned) then return end
        UpdatePeelDropdownWidth(drop, width)
      end)
    end
    if type(_G.UIDropDownMenu_SetSelectedValue) == "function" then
      hooksecurefunc("UIDropDownMenu_SetSelectedValue", function(drop)
        if not (Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned) then return end
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function()
            if Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned then
              UpdatePeelDropdownText(drop)
            end
          end)
        else
          UpdatePeelDropdownText(drop)
        end
      end)
    end
    if type(_G.UIDropDownMenu_SetSelectedName) == "function" then
      hooksecurefunc("UIDropDownMenu_SetSelectedName", function(drop)
        if not (Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned) then return end
        if C_Timer and C_Timer.After then
          C_Timer.After(0, function()
            if Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned then
              UpdatePeelDropdownText(drop)
            end
          end)
        else
          UpdatePeelDropdownText(drop)
        end
      end)
    end
    if type(_G.UIDropDownMenu_EnableDropDown) == "function" then
      hooksecurefunc("UIDropDownMenu_EnableDropDown", function(drop)
        if Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned then
          SyncPeelDropdownState(drop)
        end
      end)
    end
    if type(_G.UIDropDownMenu_DisableDropDown) == "function" then
      hooksecurefunc("UIDropDownMenu_DisableDropDown", function(drop)
        if Style.UseModernDropdowns() and drop and drop.__msufPeelDropSkinned then
          SyncPeelDropdownState(drop)
        end
      end)
    end
    if type(_G.ToggleDropDownMenu) == "function" then
      hooksecurefunc("ToggleDropDownMenu", function(_, _, drop)
        if not (Style.UseModernDropdowns() and drop and drop.__msufMSUFDropdown and drop.__msufPeelDropSkinned) then
          return
        end
        local function Run()
          if Style.UseModernDropdowns() and _G.UIDROPDOWNMENU_OPEN_MENU == drop then
            SkinDropDownLists()
          end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0, Run) else Run() end
      end)
    end
  end

  function Style.RefreshDropdownSkinMode(root)
    if root and root.GetChildren then
      local function Walk(f)
        if not f or not f.GetChildren then return end
        for i = 1, select("#", f:GetChildren()) do
          local child = select(i, f:GetChildren())
          if child then
            if IsDropdownFrame(child) then
              if Style.UseModernDropdowns() then
                Style.ApplyPeelDropdownTemplate(child)
              else
                RevertPeelDropdownTemplate(child)
              end
            end
            Walk(child)
          end
        end
      end
      Walk(root)
    end
    SkinDropDownLists()
  end
  ns.MSUF_RefreshDropdownSkinMode = Style.RefreshDropdownSkinMode
  _G.MSUF_RefreshDropdownSkinMode = Style.RefreshDropdownSkinMode


  -- -------------------------------------------------------------------------
  -- Old/native dropdown hardening
  --   Goal: keep Blizzard old-mode behavior, but make MSUF-owned dropdown
  --   selection commits deterministic and isolated from reused global list
  --   frame state. This does not restyle Blizzard lists; it only wraps the
  --   selection pipeline for MSUF-owned old-mode dropdowns.
  -- -------------------------------------------------------------------------
  local function _MSUF_IsProbablyOwnedDropdown(drop)
    if not drop then return false end
    if drop.__msufMSUFDropdown or drop.__msufDropdownHardening then return true end
    local function HasMSUFName(frame)
      local n = frame and frame.GetName and frame:GetName() or nil
      return type(n) == "string" and (n:find("MSUF", 1, true) or n:find("MidnightSimpleUnitFrames", 1, true))
    end
    if HasMSUFName(drop) then return true end
    local parent = drop
    for _ = 1, 8 do
      parent = parent and parent.GetParent and parent:GetParent() or nil
      if not parent then break end
      if HasMSUFName(parent) then return true end
    end
    return false
  end

  local function _MSUF_ShouldHardenOldDropdown(drop)
    if Style.UseModernDropdowns() then return false end
    return _MSUF_IsProbablyOwnedDropdown(drop)
  end

  local function _MSUF_CopyDropdownInfo(info)
    local copy = {}
    for k, v in pairs(info or {}) do
      copy[k] = v
    end
    return copy
  end

  local function _MSUF_GetButtonLabelText(btn)
    if not btn then return nil end
    local fs = _G[btn:GetName() .. "NormalText"]
    if fs and fs.GetText then
      local t = fs:GetText()
      if type(t) == "string" and t ~= "" then return t end
    end
    if btn.GetText then
      local t = btn:GetText()
      if type(t) == "string" and t ~= "" then return t end
    end
    return nil
  end

  local _msuf_unpack = table.unpack or unpack

  local function _MSUF_ForceDropdownVisualCommit(drop, value, text)
    if not drop or not _MSUF_ShouldHardenOldDropdown(drop) then return end
    if value ~= nil and type(_G.UIDropDownMenu_SetSelectedValue) == "function" then
      _G.UIDropDownMenu_SetSelectedValue(drop, value)
    end
    if text ~= nil and type(_G.UIDropDownMenu_SetText) == "function" then
      _G.UIDropDownMenu_SetText(drop, text)
    end
  end

  local function _MSUF_HardenedDropdownSelect(info, btn, arg1, arg2, checked)
    local original = info and info._msufOrigFunc or nil
    if type(original) ~= "function" then return end

    local drop = (info and info._msufOwnerDropdown) or _G.UIDROPDOWNMENU_OPEN_MENU
    if not _MSUF_ShouldHardenOldDropdown(drop) then
      return original(btn, arg1, arg2, checked)
    end

    local value = (btn and btn.value) or (info and info.value) or arg1
    local text = (info and info.text) or _MSUF_GetButtonLabelText(btn)
    if text == "" then text = nil end

    if drop then
      if drop.__msufDropdownSelectInFlight then
        return original(btn, arg1, arg2, checked)
      end
      drop.__msufDropdownSelectInFlight = true
      drop.__msufLastSelectValue = value
      drop.__msufLastSelectText = text
    end

    local results
    local ok, err = xpcall(function()
      results = { original(btn, arg1, arg2, checked) }
    end, function(e)
      return e
    end)

    if drop then
      drop.__msufDropdownSelectInFlight = nil
    end

    _MSUF_ForceDropdownVisualCommit(drop, value, text)

    local function Validate()
      _MSUF_ForceDropdownVisualCommit(drop, value, text)
    end
    if C_Timer and C_Timer.After then
      C_Timer.After(0, Validate)
    else
      Validate()
    end

    if not ok then
      error(err, 0)
    end
    return _msuf_unpack(results or {})
  end

  if type(_G.UIDropDownMenu_Initialize) == "function" and type(_G.UIDropDownMenu_AddButton) == "function" and not _G.__MSUF_OLD_DROPDOWN_HARDENING_INSTALLED then
    _G.__MSUF_OLD_DROPDOWN_HARDENING_INSTALLED = true

    local _orig_UIDropDownMenu_Initialize = _G.UIDropDownMenu_Initialize
    local _orig_UIDropDownMenu_AddButton = _G.UIDropDownMenu_AddButton

    _G.UIDropDownMenu_Initialize = function(drop, initFunc, displayMode, level, menuList)
      if not (_MSUF_ShouldHardenOldDropdown(drop) and type(initFunc) == "function") then
        return _orig_UIDropDownMenu_Initialize(drop, initFunc, displayMode, level, menuList)
      end

      drop.__msufMSUFDropdown = true
      drop.__msufDropdownHardening = true

      local function WrappedInitialize(self, initLevel, initMenuList)
        local prevAddButton = _G.UIDropDownMenu_AddButton
        _G.UIDropDownMenu_AddButton = function(info, addLevel)
          if not (_MSUF_ShouldHardenOldDropdown(drop) and type(info) == "table") then
            return _orig_UIDropDownMenu_AddButton(info, addLevel)
          end

          local copy = _MSUF_CopyDropdownInfo(info)
          copy._msufOwnerDropdown = drop
          if type(copy.func) == "function" and not copy.hasArrow and not copy.notCheckable and not copy.isTitle then
            copy._msufOrigFunc = copy.func
            copy.func = function(btn, a1, a2, isChecked)
              return _MSUF_HardenedDropdownSelect(copy, btn, a1, a2, isChecked)
            end
          end
          return _orig_UIDropDownMenu_AddButton(copy, addLevel)
        end

        local ok, err = xpcall(function()
          return initFunc(self, initLevel, initMenuList)
        end, function(e)
          return e
        end)

        _G.UIDropDownMenu_AddButton = prevAddButton
        if not ok then
          error(err, 0)
        end
      end

      return _orig_UIDropDownMenu_Initialize(drop, WrappedInitialize, displayMode, level, menuList)
    end
  end

  function Style.QueueDropdownStyleMode(mode)
    local normalized = _MSUF_NormalizeDropdownStyleMode(mode)
    local db = _MSUF_GetDB()
    if db and db.general then
      db.general.pendingDropdownStyleMode = normalized
    end
    return normalized
  end

  function Style.SetDropdownStyleMode(mode)
    return Style.QueueDropdownStyleMode(mode)
  end

  function Style.ApplyDropdownStyleModeImmediate(mode)
    local normalized = _MSUF_NormalizeDropdownStyleMode(mode)
    local db = _MSUF_GetDB()
    if db and db.general then
      db.general.dropdownStyleMode = normalized
      db.general.pendingDropdownStyleMode = nil
    end
    return normalized
  end

  _G.MSUF_SetDropdownStyleMode = function(mode) return Style.SetDropdownStyleMode(mode) end
  _G.MSUF_QueueDropdownStyleMode = function(mode) return Style.QueueDropdownStyleMode(mode) end
  _G.MSUF_ApplyDropdownStyleModeImmediate = function(mode) return Style.ApplyDropdownStyleModeImmediate(mode) end

  function Style.ApplyToFrame(root)
    if not Style.IsEnabled() or not root or not root.GetChildren then return end
    local function Walk(f)
      if not f or not f.GetChildren then return end
      for i = 1, select("#", f:GetChildren()) do
        local child = select(i, f:GetChildren())
        if child then
          if child.IsObjectType and child:IsObjectType("CheckButton") then
            SkinCheckButtonPeel(child)
          elseif child.IsObjectType and child:IsObjectType("Button") then
            Style.SkinButton(child)
          elseif child.IsObjectType and child:IsObjectType("EditBox") then
            SkinEditBoxPeel(child)
          elseif child.IsObjectType and child:IsObjectType("Slider") then
            SkinSliderPeel(child)
          end
          if IsDropdownFrame(child) then
            Style.ApplyPeelDropdownTemplate(child)
          end
          Walk(child)
        end
      end
    end
    Walk(root)
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
    SkinDropDownLists()
  end

  function Style.InstallStandaloneOptionsAutoSkin()
    if _G.__MSUF_PEEL_OPTIONS_SKIN_INSTALLED then return end
    _G.__MSUF_PEEL_OPTIONS_SKIN_INSTALLED = true
    local function RunSoon()
      if C_Timer and C_Timer.After then
        C_Timer.After(0, SkinStandaloneWindow)
        C_Timer.After(0.05, SkinStandaloneWindow)
      else
        SkinStandaloneWindow()
      end
    end
    if hooksecurefunc then
      if type(_G.MSUF_ShowStandaloneOptionsWindow) == "function" then
        hooksecurefunc("MSUF_ShowStandaloneOptionsWindow", RunSoon)
      end
      if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        hooksecurefunc("MSUF_OpenStandaloneOptionsWindow", RunSoon)
      end
      if type(_G.MSUF_SwitchMirrorPage) == "function" then
        hooksecurefunc("MSUF_SwitchMirrorPage", RunSoon)
      end
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, arg1)
      if arg1 ~= _addon then return end
      RunSoon()
    end)
    RunSoon()
  end

  ns.MSUF_ApplyPeelOptionsSkin = SkinStandaloneWindow
  _G.MSUF_ApplyPeelOptionsSkin = SkinStandaloneWindow
  Style.InstallStandaloneOptionsAutoSkin()
end



local _msufDropdownModeBootstrap = CreateFrame("Frame")
_msufDropdownModeBootstrap:RegisterEvent("ADDON_LOADED")
_msufDropdownModeBootstrap:SetScript("OnEvent", function(self, _, arg1)
  if arg1 ~= addonName then return end
  _MSUF_CommitPendingDropdownStyleMode()
  self:UnregisterEvent("ADDON_LOADED")
end)
