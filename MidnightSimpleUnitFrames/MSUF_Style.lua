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
-- public globals for UI (flash menu etc.)
_G.MSUF_StyleIsEnabled = function()  return Style.IsEnabled() end
_G.MSUF_SetStyleEnabled = function(v)  return Style.SetEnabled(v) end
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
