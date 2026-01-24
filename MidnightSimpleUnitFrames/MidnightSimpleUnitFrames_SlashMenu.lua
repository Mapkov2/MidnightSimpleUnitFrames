-- MidnightSimpleUnitFrames_SlashMenu.lua
-- /msuf -> Full window (Menu page)
-- /msuf options -> Full window (Options page)
-- /msufmini -> optional mini menu (In the long term this should show in edit mode the status indicator options | Shows right now just the dashboard no matter what)
-- Includes a robust "Full Options" mirror window that temporarily hosts the real MSUF options panels:
--   - Main Options
--   - Colors
--   - Gameplay
--
-- This file needs to be refactored later down the line 

local addonName, ns = ...

-- ---------------------------------------------------------------------------
-- Shared helper: left-justify button text (rail nav items)
-- Some patch builds may call LeftJustify() or MSUF_LeftJustifyButtonText().
-- Define both safely (file-scope + global aliases) to avoid nil-scope crashes.
-- ---------------------------------------------------------------------------
local function MSUF_LeftJustifyButtonText(btn, leftPad)
    leftPad = leftPad or 10
    if not btn or not btn.GetFontString then return end
    local fs = btn:GetFontString()
    if not fs then return end
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    if fs.ClearAllPoints and fs.SetPoint then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        fs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    end
end
_G.MSUF_LeftJustifyButtonText = _G.MSUF_LeftJustifyButtonText or MSUF_LeftJustifyButtonText
_G.LeftJustify = _G.LeftJustify or MSUF_LeftJustifyButtonText


-- Forward declarations (prevents Lua from treating calls as globals if referenced above definitions)
local MSUF_BuildTools
local MSUF_CapturePanelState
local MSUF_RestorePanelState
local MSUF_SaveWindowGeometry
local MSUF_LoadWindowGeometry
local MSUF_AddTooltip
local MSUF_RegisterEscClose
local MSUF_PickSessionTip
local MSUF_SkinButton

-- ---------------------------------------------------------------------------
-- Panel state helpers (some patch builds omitted these; keep defensive)
-- Used by mirror pages to preserve scroll/expanded state when switching panels.
-- ---------------------------------------------------------------------------
if type(MSUF_CapturePanelState) ~= "function" then
    MSUF_CapturePanelState = function(panel)
        local st = {}
        if not panel then return st end
        -- Capture vertical scroll if we can find a ScrollFrame
        local sf = panel.ScrollFrame or panel.scrollFrame or panel.scroll or panel.Scroll or panel.scrollChild
        if sf and sf.GetVerticalScroll then
            st.vScroll = sf:GetVerticalScroll()
        end
        return st
    end
end

if type(MSUF_RestorePanelState) ~= "function" then
    MSUF_RestorePanelState = function(panel, st)
        if not panel or type(st) ~= "table" then return end
        local sf = panel.ScrollFrame or panel.scrollFrame or panel.scroll or panel.Scroll or panel.scrollChild
        if sf and sf.SetVerticalScroll and st.vScroll then
            pcall(sf.SetVerticalScroll, sf, st.vScroll)
        end
    end
end

-- Locals used across builders (must be declared before functions capture them)
local S = {
    win = nil,
    content = nil,
    mini = nil,
    scale = { baseUiScale = nil },
    mirror = {
        host = nil,
        currentKey = "home",
        currentPanel = nil,
        homePanel = nil,
        homeToolsApi = nil,
        tipText = nil,
    },
}

-- ------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------
local function MSUF_Print(msg)
    if type(print) == "function" then
        print("|cff00ff00MSUF:|r " .. tostring(msg))
    end
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Safe function/method calls (keeps the file defensive but reduces boilerplate)
local function MSUF_SafeCall(fn, ...)
    if type(fn) ~= "function" then return end
    return pcall(fn, ...)
end


-- Tiny UI factories (reduce repeated CreateFrame/SetSize/SetPoint/SetText/Skin blocks)
local function UI_Button(parent, text, w, h, a1, rel, a2, x, y, onClick, template)
    local b = CreateFrame("Button", nil, parent, template or "UIPanelButtonTemplate")
    if w and h then b:SetSize(w, h) end
    if a1 then b:SetPoint(a1, rel or parent, a2 or a1, x or 0, y or 0) end
    if text ~= nil and b.SetText then b:SetText(text) end
    if type(MSUF_SkinButton) == "function" then
        MSUF_SkinButton(b)
    end
    if onClick then
        b:SetScript("OnClick", onClick)
    end
    return b
end

local function UI_CloseButton(parent, a1, rel, a2, x, y, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    if a1 then b:SetPoint(a1, rel or parent, a2 or a1, x or 0, y or 0) end
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Attach a bottom-right resize grip that resizes manually (no StartSizing jump)
local function MSUF_AttachManualResizeGrip(frame)
    if not frame or frame._msufResizeGrip then return end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    local function Stop()
        if not frame._msufResizing then return end
        frame._msufResizing = false
        if grip and grip.SetScript then
            grip:SetScript("OnUpdate", nil)
        end
        if MSUF_SaveWindowGeometry then
            MSUF_SaveWindowGeometry(frame, frame._msufGeomKey or "full")
        end
    end

    grip:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        if not (frame and frame.GetWidth and frame.GetHeight) then return end

        local cx, cy = GetCursorPosition()
        frame._msufResizing = true
        frame._msufResizeStartX = cx
        frame._msufResizeStartY = cy
        frame._msufResizeStartW = frame:GetWidth()
        frame._msufResizeStartH = frame:GetHeight()

        self:SetScript("OnUpdate", function()
            if not frame._msufResizing then return end
            local x, y = GetCursorPosition()
            local s = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
            if s == 0 then s = 1 end

            local dw = (x - (frame._msufResizeStartX or x)) / s
            local dh = ((frame._msufResizeStartY or y) - y) / s -- drag down => taller

            local newW = (frame._msufResizeStartW or frame:GetWidth()) + dw
            local newH = (frame._msufResizeStartH or frame:GetHeight()) + dh

            local minW = frame._msufMinW or 760
            local minH = frame._msufMinH or 520
            local maxW = frame._msufMaxW or 2200
            local maxH = frame._msufMaxH or 1400

            frame:SetSize(clamp(newW, minW, maxW), clamp(newH, minH, maxH))
        end)
    end)

    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnHide", Stop)

    -- Safety: if mouse is released outside the grip, stop resizing on any mouse up on the window
    do
        local prev = frame.GetScript and frame:GetScript("OnMouseUp")
        frame:SetScript("OnMouseUp", function(self, btn)
            Stop()
            if prev then
                pcall(prev, self, btn)
            end
        end)
    end

    frame._msufResizeGrip = grip
    frame._msufStopManualResize = Stop
end


local function MSUF_EnsureGeneral()
    MSUF_SafeCall(EnsureDB)
    if type(MSUF_DB) ~= "table" then
        return nil
    end
    MSUF_DB.general = MSUF_DB.general or {}
    return MSUF_DB.general
end


-- ------------------------------------------------------------
-- Window persistence / tooltips / ESC close (Quick Wins)
-- ------------------------------------------------------------
local function MSUF_GetGeomPrefix(which)
    if which == "mini" then
        return "flashMini"
    end
    return "flashFull"
end

MSUF_RegisterEscClose = function(frame)
    if not frame or not frame.GetName then return end
    local name = frame:GetName()
    if not name or name == "" then return end
    if type(UISpecialFrames) == "table" then
        for _, v in ipairs(UISpecialFrames) do
            if v == name then
                return
            end
        end
        table.insert(UISpecialFrames, name)
    end
end

MSUF_SaveWindowGeometry = function(frame, which)
    if not frame or not frame.GetWidth or not frame.GetHeight or not frame.GetPoint then return end
    local g = MSUF_EnsureGeneral()
    if not g then return end
    local pfx = MSUF_GetGeomPrefix(which)

    local w = frame:GetWidth()
    local h = frame:GetHeight()
    if w and h then
        g[pfx .. "W"] = w
        g[pfx .. "H"] = h
    end


    local point, relTo, relPoint, xOfs, yOfs = frame:GetPoint(1)
    if point and relPoint and xOfs and yOfs then
        g[pfx .. "Point"] = point
        g[pfx .. "RelPoint"] = relPoint

        -- Store offsets in a scale-stable form as well.
        -- If the user changes Global UI Scale (UIParent scale), restoring raw X/Y causes the window
        -- to appear to "not move with" the new scale. Saving as pixel offsets fixes that.
        local s = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
        if not s or s == 0 then s = 1 end
        g[pfx .. "X"] = xOfs
        g[pfx .. "Y"] = yOfs
        g[pfx .. "Xpx"] = (tonumber(xOfs) or 0) * s
        g[pfx .. "Ypx"] = (tonumber(yOfs) or 0) * s
    end
end

MSUF_LoadWindowGeometry = function(frame, which, defaultW, defaultH, defaultPoint, defaultX, defaultY)
    if not frame then return end
    local g = MSUF_EnsureGeneral()
    local pfx = MSUF_GetGeomPrefix(which)

    local w = defaultW
    local h = defaultH
    local point = defaultPoint or "CENTER"
    local relPoint = point
    local x = defaultX or 0
    local y = defaultY or 0

    if g then
        w = tonumber(g[pfx .. "W"]) or w
        h = tonumber(g[pfx .. "H"]) or h
        point = g[pfx .. "Point"] or point
        relPoint = g[pfx .. "RelPoint"] or relPoint

        -- Prefer pixel-stable offsets if present (see SaveWindowGeometry).
        local s = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
        if not s or s == 0 then s = 1 end

        local xpx = tonumber(g[pfx .. "Xpx"])
        local ypx = tonumber(g[pfx .. "Ypx"])

        if xpx ~= nil then
            x = xpx / s
        else
            x = tonumber(g[pfx .. "X"]) or x
        end

        if ypx ~= nil then
            y = ypx / s
        else
            y = tonumber(g[pfx .. "Y"]) or y
        end
    end

    -- Respect resize bounds (avoid restoring sizes below min/max)
    local minW = frame._msufMinW or 760
    local minH = frame._msufMinH or 520
    local maxW = frame._msufMaxW or 2200
    local maxH = frame._msufMaxH or 1400
    if w and h then
        w = clamp(w, minW, maxW)
        h = clamp(h, minH, maxH)
        if frame.SetSize then
            frame:SetSize(w, h)
        end
    end

    if frame.ClearAllPoints and frame.SetPoint then
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relPoint, x, y)
    end
end

MSUF_AddTooltip = function(widget, title, body)
    if not widget or not widget.SetScript then return end
    widget:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title and title ~= "" then
            GameTooltip:SetText(title, 1, 1, 1)
        end
        if body and body ~= "" then
            GameTooltip:AddLine(body, 0.80, 0.86, 1.00, true)
        end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

-- Tip-of-the-day: pick once per full-window open (avoid cycling when just switching pages)
local MSUF_GetNextTip -- forward declare for tip picker (avoid global lookup)
MSUF_PickSessionTip = function()
    local tip = (_G.MSUF_GetNextTip and _G.MSUF_GetNextTip())
    if tip then
        S.mirror.tipText = tip
    end
end

-- ------------------------------------------------------------
-- Midnight skin helpers (blue theme + compact sizing)
-- ------------------------------------------------------------
local MSUF_THEME = {
    bgR = 0.03, bgG = 0.05, bgB = 0.12, bgA = 0.95,           -- midnight blue background
    edgeR = 0.10, edgeG = 0.20, edgeB = 0.45, edgeA = 0.90,   -- blue border
    titleR = 0.75, titleG = 0.88, titleB = 1.00, titleA = 1.00,
    textR = 0.86, textG = 0.92, textB = 1.00, textA = 1.00
}

-- Pill (superellipse) tint: slightly brighter than the general frame border to read better in the nav rail.
local function MSUF_Clamp01(x)
    x = tonumber(x) or 0
    if x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
end

local MSUF_PILL_EDGE_R = MSUF_Clamp01((MSUF_THEME.edgeR or 0.10) * 1.25)
local MSUF_PILL_EDGE_G = MSUF_Clamp01((MSUF_THEME.edgeG or 0.20) * 1.25)
local MSUF_PILL_EDGE_B = MSUF_Clamp01((MSUF_THEME.edgeB or 0.45) * 1.18)
local MSUF_PILL_EDGE_A = MSUF_Clamp01((MSUF_THEME.edgeA or 0.90) + 0.05)

-- Superellipse texture (alpha-based) used for pill buttons / rounded chips.
-- IMPORTANT: Use forward slashes to avoid Lua backslash escaping issues.
local MSUF_SUPERELLIPSE_TEX = "Interface/AddOns/" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "/Media/superellipse.tga"

-- Create (once) a superellipse border + fill stack on a button.
-- Returns: fillTex, borderTex
-- Create (once) a superellipse border + fill stack on a button.
-- Uses a 3-slice layout (left cap / stretch middle / right cap) to avoid pixelation on scaled UI.
-- Returns: fillGroup, borderGroup  (each group supports :SetVertexColor(), :Show(), :Hide())
local function MSUF_EnsureSuperellipseLayers(btn, inset)
    if not btn or not btn.CreateTexture then return nil, nil end
    inset = tonumber(inset) or 2

    local function SnapOff(tex)
        if tex and tex.SetSnapToPixelGrid then
            tex:SetSnapToPixelGrid(false)
            if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
        end
    end

    local function MakeGroup(key, layer, subLevel)
        local g = btn[key]
        if g then return g end

        g = {}
        g.L = btn:CreateTexture(nil, layer, nil, subLevel or 0)
        g.M = btn:CreateTexture(nil, layer, nil, subLevel or 0)
        g.R = btn:CreateTexture(nil, layer, nil, subLevel or 0)
        g._msufSEParts = { g.L, g.M, g.R }

        g.L:SetTexture(MSUF_SUPERELLIPSE_TEX)
        g.M:SetTexture(MSUF_SUPERELLIPSE_TEX)
        g.R:SetTexture(MSUF_SUPERELLIPSE_TEX)

        -- Atlas UVs: 128x64, L=0..0.25, M=0.25..0.75, R=0.75..1
        g.L:SetTexCoord(0.0, 0.25, 0.0, 1.0)
        g.M:SetTexCoord(0.25, 0.75, 0.0, 1.0)
        g.R:SetTexCoord(0.75, 1.0, 0.0, 1.0)

        SnapOff(g.L); SnapOff(g.M); SnapOff(g.R)

        g.SetVertexColor = function(self, r, gg, b, a)
            for i = 1, #self._msufSEParts do
                local t = self._msufSEParts[i]
                if t and t.SetVertexColor then t:SetVertexColor(r, gg, b, a) end
            end
        end
        g.Hide = function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]; if t and t.Hide then t:Hide() end end end
        g.Show = function(self) for i=1,#self._msufSEParts do local t=self._msufSEParts[i]; if t and t.Show then t:Show() end end end

        btn[key] = g
        return g
    end

    local border = MakeGroup("_msufSEBorder3", "BACKGROUND", 0)
    local fill   = MakeGroup("_msufSEFill3",   "BACKGROUND", 1)

    -- Prevent AA bleed overlap between stacked buttons
    if btn.SetClipsChildren then pcall(btn.SetClipsChildren, btn, true) end

    local function Layout(g, pad)
        local w = (btn.GetWidth and btn:GetWidth()) or 140
        local h = (btn.GetHeight and btn:GetHeight()) or 22

        local innerW = math.max(1, w - pad * 2)
        local innerH = math.max(1, h - pad * 2)

        local r = math.floor(innerH * 0.5 + 0.5) -- cap width = radius
        local capW = math.min(r, math.floor(innerW * 0.5))

        g.L:ClearAllPoints()
        g.M:ClearAllPoints()
        g.R:ClearAllPoints()

        g.L:SetPoint("TOPLEFT", btn, "TOPLEFT", pad, -pad)
        g.L:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", pad, pad)
        g.L:SetWidth(capW)

        g.R:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -pad, -pad)
        g.R:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -pad, pad)
        g.R:SetWidth(capW)

        g.M:SetPoint("TOPLEFT", g.L, "TOPRIGHT", 0, 0)
        g.M:SetPoint("BOTTOMRIGHT", g.R, "BOTTOMLEFT", 0, 0)
    end

    Layout(border, 1)
    Layout(fill, math.max(2, inset))

    if btn.HookScript and not btn._msufSE3Hooked then
        btn._msufSE3Hooked = true
        btn:HookScript("OnSizeChanged", function()
            Layout(border, 1)
            Layout(fill, math.max(2, inset))
        end)
    end

    -- Theme tint (project-style)
    if border and border.SetVertexColor then
        border:SetVertexColor(MSUF_PILL_EDGE_R, MSUF_PILL_EDGE_G, MSUF_PILL_EDGE_B, MSUF_PILL_EDGE_A)
    end
    if fill and fill.SetVertexColor then
        fill:SetVertexColor(MSUF_THEME.bgR, MSUF_THEME.bgG, MSUF_THEME.bgB, 0.90)
    end

    return fill, border
end


-- ------------------------------------------------------------
-- Tip of the Day (Flash Menu) - cycles on every open of the Menu page
-- ------------------------------------------------------------
local MSUF_TIPS = {
    "Bigger steps: Hold |cff00ff00SHIFT|r while adjusting sliders to change values faster.",
    "Fine tuning: Hold |cff00ff00CTRL|r while adjusting sliders for smaller steps.",
    "Quick reset: If something feels off, try |cff00ff00/msuf reset|r (frame positions).",
    "Factory reset: Use |cff00ff00Menu → Advanced → Factory Reset|r (or /msuf fullreset confirm + /reload).",
    "Edit Mode: Use |cff00ff00Toggle Edit Mode|r to move frames quickly, then fine-tune with the position popup.",
    "Profiles safety: Create a new profile before big experiments — switch back instantly if needed.",
    "Colors: The |cff00ff00Colors|r tab lets you customize almost everything (fonts, bars, castbars, highlights).",
    "Gameplay: The |cff00ff00Gameplay|r tab contains extra UI tools and warnings you can enable/disable.",
    "Recommended: |cff00ff00Sensei Resource Bar|r pairs insanely well with MSUF to track resources cleanly.",
    "UI scale tip: MSUF has its own UI scale — separate from the Global UI scale.",
    "Troubleshoot: If visuals don’t update, a quick |cff00ff00/reload|r fixes most UI state issues.",
    "Readability: Slightly larger fonts often help more than bigger frames (especially in raids).",
    "During development of MSUF Unhalted, R41z0r and other great addon developers helped out!",
    "Danders is a great Party/Raidframe addon and works really well with MSUF",
    "Community: If you like MSUF, share it with a friend — UI addons grow by word of mouth.",
}

MSUF_GetNextTip = function()
    local tips = MSUF_TIPS
    if not tips or #tips == 0 then
        return nil, 0, 0
    end

    local general = MSUF_EnsureGeneral()
    local idx = 1
    if general then
        idx = (tonumber(general.tipCycleIndex) or 0) + 1
        if idx > #tips then idx = 1 end
        general.tipCycleIndex = idx
    end

    return tips[idx], idx, #tips
end
_G.MSUF_GetNextTip = MSUF_GetNextTip

local function MSUF_ForceItalicFont(fs)
    if not fs or not fs.GetFont or not fs.SetFont then return end
    local font, size, flags = fs:GetFont()
    if not font or not size then return end
    flags = flags or ""
    if flags:find("ITALIC") then return end
    if flags ~= "" then
        flags = flags .. ",ITALIC"
    else
        flags = "ITALIC"
    end
    fs:SetFont(font, size, flags)
end

-- ------------------------------------------------------------
-- Presets (named settings snapshots loaded via dropdown on Home page)
-- Note: These are NOT MSUF "profiles"; they simply overwrite the *current* active profile.
-- Data lives in MSUF_Presets.lua to keep this file smaller/cleaner.
-- ------------------------------------------------------------

local MSUF_PRESETS = (ns and ns.MSUF_PRESETS) or _G.MSUF_PRESETS
if type(MSUF_PRESETS) ~= "table" then MSUF_PRESETS = {} end

local MSUF_PRESET_ALLOWED_KEYS = {
  "general",
  "player",
  "target",
  "focus",
  "pet",
  "targettarget",
  "boss",
  "bars",
  "auras",
  "gameplay",
  "npcColors",
  "classColors",
  "shortenNames",
}

local function MSUF_WipeTable(t)
  if type(t) ~= "table" then return end
  for k in pairs(t) do
    t[k] = nil
  end
end

local function MSUF_DeepCopy(src, depth)
  if type(src) ~= "table" then return src end
  depth = (depth or 0) + 1
  if depth > 30 then return {} end
  local dst = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = MSUF_DeepCopy(v, depth)
    else
      dst[k] = v
    end
  end
  return dst
end

local function MSUF_CopyValue(v)
  if type(v) ~= "table" then return v end
  if type(CopyTable) == "function" then
    -- Blizzard helper
    return CopyTable(v)
  end
  return MSUF_DeepCopy(v)
end

-- Forward-declare (defined further down): reload recommendation popup.
local MSUF_ShowReloadRecommendedPopup

local function MSUF_ApplyPreset(presetName)
  local preset = MSUF_PRESETS and MSUF_PRESETS[presetName]
  if type(preset) ~= "table" then
    print("|cffff3333MSUF:|r Preset not found: " .. tostring(presetName))
    return
  end

  -- Make sure MSUF_DB exists and points at the active profile table.
  if type(MSUF_InitProfiles) == "function" then
    pcall(MSUF_InitProfiles)
  end
  if type(MSUF_DB) ~= "table" then
    print("|cffff3333MSUF:|r DB not ready (MSUF_DB missing).")
    return
  end


  -- Special-case: compact MSUF2/MSUF3 preset strings (exported via ProfileIO).
  -- Keeps this feature optional and 0-regression for normal table-based presets.
  local importStr = preset._msufImportString or preset._msufImport
  if type(importStr) == "string" then
    local okPrefix, prefix = pcall(string.match, importStr, "^%s*(MSUF%d+):")
    if okPrefix and (prefix == "MSUF2" or prefix == "MSUF3") then
      local imp = _G and _G.MSUF_ImportFromString
      if type(imp) == "function" then
        pcall(imp, importStr)
        if type(ApplyAllSettings) == "function" then pcall(ApplyAllSettings) end
        if type(UpdateAllFonts) == "function" then pcall(UpdateAllFonts) end
        print("|cff00ff00MSUF:|r Loaded preset: " .. tostring(presetName))
        if type(MSUF_ShowReloadRecommendedPopup) == "function" then
          MSUF_ShowReloadRecommendedPopup("Preset: " .. tostring(presetName))
        end
        return
      else
        print("|cffff3333MSUF:|r Cannot load this preset (MSUF_ImportFromString missing).")
      end
    end
  end

  -- Overwrite current active profile (keep the table reference!)
  MSUF_WipeTable(MSUF_DB)
  for _, key in ipairs(MSUF_PRESET_ALLOWED_KEYS) do
    local val = preset[key]
    if val ~= nil then
      MSUF_DB[key] = MSUF_CopyValue(val)
    end
  end

  -- Re-apply defaults/migrations and refresh everything.
  if type(EnsureDB) == "function" then
    pcall(EnsureDB)
  end
  if type(ApplyAllSettings) == "function" then
    pcall(ApplyAllSettings)
  end
  if type(UpdateAllFonts) == "function" then
    pcall(UpdateAllFonts)
  end

  print("|cff00ff00MSUF:|r Loaded preset: " .. tostring(presetName))
  if type(MSUF_ShowReloadRecommendedPopup) == "function" then
    MSUF_ShowReloadRecommendedPopup("Preset: " .. tostring(presetName))
  end
end

local function MSUF_GetPresetNames()
  local names = {}
  if type(MSUF_PRESETS) ~= "table" then return names end
  for name in pairs(MSUF_PRESETS) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

local MSUF_PENDING_PRESET = nil

local function MSUF_ShowPresetConfirm(presetName)
  if not presetName or presetName == "" then return end
  MSUF_PENDING_PRESET = presetName

  -- Optional per-preset warning (stored in MSUF_Presets.lua as preset._msufWarning).
  local preset = MSUF_PRESETS and MSUF_PRESETS[presetName]
  local warn = preset and preset._msufWarning
  if warn ~= nil and warn ~= "" then
    warn = tostring(warn)
  else
    warn = nil
  end

  if not StaticPopupDialogs["MSUF_LOAD_PRESET_CONFIRM"] then
    StaticPopupDialogs["MSUF_LOAD_PRESET_CONFIRM"] = {
      text = "Load preset: %s?\n\nThis will overwrite your CURRENT active profile settings.",
      button1 = YES,
      button2 = NO,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
      OnAccept = function()
        if MSUF_PENDING_PRESET then
          MSUF_ApplyPreset(MSUF_PENDING_PRESET)
        end
        MSUF_PENDING_PRESET = nil
      end,
      OnCancel = function()
        MSUF_PENDING_PRESET = nil
      end,
    }
  end

  local dlg = StaticPopupDialogs["MSUF_LOAD_PRESET_CONFIRM"]
  if dlg then
    if warn then
      dlg.text = "Load preset: %s?\n\n|cffffaa00Warning:|r " .. warn .. "\n\nThis will overwrite your CURRENT active profile settings."
    else
      dlg.text = "Load preset: %s?\n\nThis will overwrite your CURRENT active profile settings."
    end
  end

  StaticPopup_Show("MSUF_LOAD_PRESET_CONFIRM", presetName)
end

-- Recommend (optional) ReloadUI after large state changes (presets/imports).
-- Can always be declined; no DB persistence (0-regression).
local MSUF_PENDING_RELOAD_RECOMMEND_LABEL = nil

MSUF_ShowReloadRecommendedPopup = function(label)
  if InCombatLockdown and InCombatLockdown() then
    if type(MSUF_Print) == "function" then
      MSUF_Print("Reload recommended (cannot show popup in combat).")
    else
      print("|cffffaa00MSUF:|r Reload recommended (cannot show popup in combat).")
    end
    return
  end

  MSUF_PENDING_RELOAD_RECOMMEND_LABEL = tostring(label or "")
  if MSUF_PENDING_RELOAD_RECOMMEND_LABEL == "" then
    MSUF_PENDING_RELOAD_RECOMMEND_LABEL = "these changes"
  end

  if not StaticPopupDialogs["MSUF_RELOAD_RECOMMENDED"] then
    StaticPopupDialogs["MSUF_RELOAD_RECOMMENDED"] = {
      text = "MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?",
      button1 = "Reload",
      button2 = "Not now",
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
      OnAccept = function()
        MSUF_PENDING_RELOAD_RECOMMEND_LABEL = nil
        if type(ReloadUI) == "function" then
          ReloadUI()
        end
      end,
      OnCancel = function()
        MSUF_PENDING_RELOAD_RECOMMEND_LABEL = nil
      end,
    }
  end

  StaticPopup_Show("MSUF_RELOAD_RECOMMENDED", MSUF_PENDING_RELOAD_RECOMMEND_LABEL)
end

-- Reload confirmation (used by UI-scale preset buttons)
local MSUF_PENDING_RELOAD_LABEL = nil
local MSUF_PENDING_RELOAD_FN = nil

local function MSUF_ShowReloadConfirm(label, fn)
  if InCombatLockdown and InCombatLockdown() then
    MSUF_Print("Cannot reload UI in combat.")
    return
  end

  MSUF_PENDING_RELOAD_LABEL = tostring(label or "")
  MSUF_PENDING_RELOAD_FN = fn

  if not StaticPopupDialogs["MSUF_RELOAD_UI_CONFIRM"] then
    StaticPopupDialogs["MSUF_RELOAD_UI_CONFIRM"] = {
      text = "Reload UI now?\n\nThis will apply: %s",
      button1 = YES,
      button2 = NO,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1,
      preferredIndex = 3,
      OnAccept = function()
        local f = MSUF_PENDING_RELOAD_FN
        MSUF_PENDING_RELOAD_FN = nil
        MSUF_PENDING_RELOAD_LABEL = nil
        if type(f) == "function" then
          pcall(f)
        end
      end,
      OnCancel = function()
        MSUF_PENDING_RELOAD_FN = nil
        MSUF_PENDING_RELOAD_LABEL = nil
      end,
    }
  end

  StaticPopup_Show("MSUF_RELOAD_UI_CONFIRM", MSUF_PENDING_RELOAD_LABEL)
end


-- Copy/link popup (used by Dashboard support icons)
-- NOTE: StaticPopup editboxes can be flaky in some UI contexts (empty editbox).
-- We use a tiny MSUF-owned modal frame so the URL is ALWAYS pasted into the box.
local MSUF_CopyLinkPopup = nil

local function MSUF_EnsureCopyLinkPopup()
    if MSUF_CopyLinkPopup then return MSUF_CopyLinkPopup end

    local f = CreateFrame("Frame", "MSUF_CopyLinkPopup", UIParent, "BackdropTemplate")
    f:SetSize(420, 150)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.90)
    f:SetBackdropBorderColor(0.10, 0.10, 0.10, 0.90)

    local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOP", f, "TOP", 0, -14)
    titleFS:SetText("Link")
    f._msufTitleFS = titleFS

    local hintFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hintFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -6)
    hintFS:SetText("Press Ctrl+C to copy:")
    hintFS:SetTextColor(0.90, 0.90, 0.90, 1)

    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetAutoFocus(false)
    eb:SetSize(360, 32)
    eb:SetPoint("TOP", hintFS, "BOTTOM", 0, -10)
    if eb.SetTextInsets then eb:SetTextInsets(8, 8, 0, 0) end
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnEnterPressed", function() f:Hide() end)
    f._msufEditBox = eb

    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ok:SetSize(120, 24)
    ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    ok:SetText(OKAY)
    ok:SetScript("OnClick", function() f:Hide() end)
    if type(MSUF_SkinButton) == "function" then
        MSUF_SkinButton(ok)
    end

    f:SetScript("OnShow", function(self)
        if self._msufTitleFS then
            self._msufTitleFS:SetText(self._msufTitle or "Link")
        end
        if self._msufEditBox then
            self._msufEditBox:SetText(self._msufUrl or "")
            self._msufEditBox:HighlightText()
            self._msufEditBox:SetFocus()
        end
    end)

    f:SetScript("OnHide", function(self)
        if self._msufEditBox then
            self._msufEditBox:SetText("")
            self._msufEditBox:ClearFocus()
        end
        self._msufTitle = nil
        self._msufUrl = nil
    end)

    f:Hide()
    MSUF_CopyLinkPopup = f
    return f
end

local function MSUF_ShowCopyLink(title, url)
    local f = MSUF_EnsureCopyLinkPopup()
    f._msufTitle = tostring(title or "Link")
    f._msufUrl = tostring(url or "")
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:Show()
    if f.Raise then f:Raise() end
end
-- Scale used for mirrored (real) option panels inside the standalone window.
local MIRROR_PANEL_SCALE = 1.00
-- Readability helpers:
-- * Home/Menu page: we can bump fonts safely (our own layout)
-- * Mirrored real MSUF option panels: DO NOT bump fonts (can cause overlaps due to fixed anchoring)
local MENU_FONT_BUMP = 3
local MIRRORED_PANEL_FONT_BUMP = 1

-- Crop amounts for mirroring the real options panel inside the slash menu window.
-- The main MSUF_OptionsPanel contains a large top header/tab strip; when mirrored (and header text is hidden/tabs are dimmed)
-- this becomes wasted space. Cropping shifts the whole panel upward inside the clip host so content starts near the top.
local MSUF_MIRROR_MAIN_CROP_Y = 42      -- default crop for the full "Options" view
local MSUF_MIRROR_DEEPLINK_CROP_Y = 96  -- deeper crop for subpages (castbar/profiles/unitframes/etc)


local function MSUF_ApplyMidnightBackdrop(frame, alphaOverride)
    if not frame or not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local a = alphaOverride or MSUF_THEME.bgA
    frame:SetBackdropColor(MSUF_THEME.bgR, MSUF_THEME.bgG, MSUF_THEME.bgB, a)
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(MSUF_THEME.edgeR, MSUF_THEME.edgeG, MSUF_THEME.edgeB, MSUF_THEME.edgeA)
    end
end

local function MSUF_SkinTitle(fs)
    if fs and fs.SetTextColor then
        fs:SetTextColor(MSUF_THEME.titleR, MSUF_THEME.titleG, MSUF_THEME.titleB, MSUF_THEME.titleA)
    end
end

local function MSUF_SkinText(fs)
    if fs and fs.SetTextColor then
        fs:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA)
    end
end

local function MSUF_SkinMuted(fs)
    if fs and fs.SetTextColor then
        -- Slightly dimmer than normal text
        fs:SetTextColor(MSUF_THEME.textR * 0.80, MSUF_THEME.textG * 0.80, MSUF_THEME.textB * 0.80, 0.85)
    end
end


-- Create an "active selection" overlay that persists even when the mouse is not hovering.
-- Uses the same superellipse texture and UV slicing as the base fill, but renders above it.
local function MSUF_EnsureNavActiveOverlay(btn, fillGroup)
    if not (btn and btn.CreateTexture and fillGroup and fillGroup.L and fillGroup.M and fillGroup.R) then return nil end
    if btn._msufNavActive3 then
        -- Keep it pinned to the fill parts (in case something re-anchored them).
        local g = btn._msufNavActive3
        if g and g.L and g.L.SetAllPoints then g.L:SetAllPoints(fillGroup.L) end
        if g and g.M and g.M.SetAllPoints then g.M:SetAllPoints(fillGroup.M) end
        if g and g.R and g.R.SetAllPoints then g.R:SetAllPoints(fillGroup.R) end
        return g
    end

    local g = {}
    g.L = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    g.M = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    g.R = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    g._msufSEParts = { g.L, g.M, g.R }

    g.L:SetTexture(MSUF_SUPERELLIPSE_TEX)
    g.M:SetTexture(MSUF_SUPERELLIPSE_TEX)
    g.R:SetTexture(MSUF_SUPERELLIPSE_TEX)

    g.L:SetTexCoord(0.0, 0.25, 0.0, 1.0)
    g.M:SetTexCoord(0.25, 0.75, 0.0, 1.0)
    g.R:SetTexCoord(0.75, 1.0, 0.0, 1.0)

    for i = 1, #g._msufSEParts do
        local t = g._msufSEParts[i]
        if t and t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        end
    end

    g.SetVertexColor = function(self, r, gg, b, a)
        for i = 1, #self._msufSEParts do
            local t = self._msufSEParts[i]
            if t and t.SetVertexColor then t:SetVertexColor(r, gg, b, a) end
        end
    end
    g.Hide = function(self)
        for i = 1, #self._msufSEParts do
            local t = self._msufSEParts[i]
            if t and t.Hide then t:Hide() end
        end
    end
    g.Show = function(self)
        for i = 1, #self._msufSEParts do
            local t = self._msufSEParts[i]
            if t and t.Show then t:Show() end
        end
    end

    -- Pin exactly to the base fill so it scales cleanly at fractional UI scales.
    g.L:SetAllPoints(fillGroup.L)
    g.M:SetAllPoints(fillGroup.M)
    g.R:SetAllPoints(fillGroup.R)

    -- Default: hidden until selected.
    g:Hide()

    btn._msufNavActive3 = g
    return g
end

MSUF_SkinButton = function(btn)
    if not btn then return end
    if btn.__MSUF_MidnightSkinned or btn.__MSUF_NavSkinned or btn.__MSUF_DashSkinned then return end
    btn.__MSUF_MidnightSkinned = true

    -- Only target standard UIPanelButton-style buttons (avoid breaking dropdown arrows, etc.)
    local looksPanel = false
    if (btn.Left and btn.Middle and btn.Right) then
        looksPanel = true
    elseif btn.GetRegions then
        local regions = { btn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then
                local ok, tex = pcall(r.GetTexture, r)
                if ok and type(tex) == "string" then
                    if tex:find("UI%-Panel%-Button") or tex:find("UIPanelButton") then
                        looksPanel = true
                        break
                    end
                end
            end
        end
    end

    if not looksPanel then
        -- Keep the old lightweight tint behavior for non-panel buttons.
        local nt = btn.GetNormalTexture and btn:GetNormalTexture()
        if nt and nt.SetVertexColor then nt:SetVertexColor(0.18, 0.36, 0.90, 1.00) end
        local pt = btn.GetPushedTexture and btn:GetPushedTexture()
        if pt and pt.SetVertexColor then pt:SetVertexColor(0.12, 0.26, 0.70, 1.00) end
        local ht = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if ht and ht.SetVertexColor then ht:SetVertexColor(0.25, 0.55, 1.00, 0.85) end
        local dt = btn.GetDisabledTexture and btn:GetDisabledTexture()
        if dt and dt.SetVertexColor then dt:SetVertexColor(0.25, 0.25, 0.25, 0.55) end
        return
    end

    -- Strip template pieces (default red/grey Blizzard art)
    if btn.Left and btn.Left.Hide then btn.Left:Hide() end
    if btn.Middle and btn.Middle.Hide then btn.Middle:Hide() end
    if btn.Right and btn.Right.Hide then btn.Right:Hide() end

    if btn.GetRegions then
        local regions = { btn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then
                local ok, tex = pcall(r.GetTexture, r)
                if ok and type(tex) == "string" then
                    local isPanelArt = false
                    if tex:find("UI%-Panel%-Button") or tex:find("UIPanelButton") then
                        isPanelArt = true
                    end
                    if isPanelArt then
                        if r.SetAlpha then r:SetAlpha(0) end
                        if r.Hide then r:Hide() end
                    end
                end
            end
        end
    end

    -- Kill template textures so the skin is deterministic
    if btn.GetNormalTexture and btn.SetNormalTexture then
        local nt = btn:GetNormalTexture()
        if nt and nt.SetAlpha then nt:SetAlpha(0) end
        pcall(btn.SetNormalTexture, btn, nil)
    end
    if btn.GetPushedTexture and btn.SetPushedTexture then
        local pt = btn:GetPushedTexture()
        if pt and pt.SetAlpha then pt:SetAlpha(0) end
        pcall(btn.SetPushedTexture, btn, nil)
    end
    if btn.GetHighlightTexture and btn.SetHighlightTexture then
        local ht = btn:GetHighlightTexture()
        if ht and ht.SetAlpha then ht:SetAlpha(0) end
        pcall(btn.SetHighlightTexture, btn, nil)
    end
    if btn.GetDisabledTexture and btn.SetDisabledTexture then
        local dt = btn:GetDisabledTexture()
        if dt and dt.SetAlpha then dt:SetAlpha(0) end
        pcall(btn.SetDisabledTexture, btn, nil)
    end


    -- Our own layers (superellipse / pill style)
    local bg, border = MSUF_EnsureSuperellipseLayers(btn, 2)

    if border and border.SetVertexColor then
        border:SetVertexColor(MSUF_PILL_EDGE_R, MSUF_PILL_EDGE_G, MSUF_PILL_EDGE_B, 0.90)
    end
    if bg and bg.SetVertexColor then
        bg:SetVertexColor(0.09, 0.10, 0.12, 0.92)
    end
    btn._msufBtnBorder = border
    btn._msufBtnBG = bg
    -- No separate hover/pressed textures (avoids stretch aliasing); tint the BG instead.
    btn._msufBtnBG_base = { 0.09, 0.10, 0.12, 0.92 }
    btn._msufBtnBG_hover = { 0.10, 0.11, 0.13, 0.98 }
    btn._msufBtnBG_pressed = { 0.08, 0.09, 0.11, 0.98 }
    local fs = btn.GetFontString and btn:GetFontString()
    if fs and fs.SetTextColor then
        fs:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA)
        if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.6) end
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
    -- Keep label reliably visible (prevents 'hidden until hover' on some templates)
        if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
        if fs.SetAlpha then fs:SetAlpha(1) end
        if fs.Show then pcall(fs.Show, fs) end
        if fs.GetText and fs.SetText then
            local ok, t = pcall(fs.GetText, fs)
            if ok then pcall(fs.SetText, fs, t or "") end
        end
    end

    -- Never let the button get stuck invisible due to inherited alpha
    if btn.SetAlpha then btn:SetAlpha(1) end

    -- Self-heal on show (covers create-while-hidden + template alpha edge cases)
    if btn.HookScript and not btn.__msufBtnShowFix then
        btn.__msufBtnShowFix = true
        btn:HookScript("OnShow", function(self)
            if self.SetAlpha then self:SetAlpha(1) end
            local f = self.GetFontString and self:GetFontString()
            if f then
                if f.Show then pcall(f.Show, f) end
                if f.SetDrawLayer then f:SetDrawLayer("OVERLAY", 7) end
                if f.SetAlpha then f:SetAlpha(1) end
                if f.GetText and f.SetText then
                    local ok, t = pcall(f.GetText, f)
                    if ok then pcall(f.SetText, f, t or "") end
                end
            end
            -- Re-apply base BG tint (in case alpha drifted)
            if self._msufBtnBG and self._msufBtnBG_base then
                local col = self._msufBtnBG_base
                if self._msufBtnBG.SetVertexColor then
                    self._msufBtnBG:SetVertexColor(col[1], col[2], col[3], col[4])
                end
            end
        end)
    end

    -- Self-heal on hide too (OnLeave may not fire if the parent panel hides while hovered)
    if btn.HookScript and not btn.__msufBtnHideFix then
        btn.__msufBtnHideFix = true
        btn:HookScript("OnHide", function(self)
            if self.UnlockHighlight then pcall(self.UnlockHighlight, self) end
            if self.SetButtonState then pcall(self.SetButtonState, self, "NORMAL") end
            if self._msufBtnBG and self._msufBtnBG_base and self._msufBtnBG.SetVertexColor then
                local col = self._msufBtnBG_base
                self._msufBtnBG:SetVertexColor(col[1], col[2], col[3], col[4])
            end
            if self.SetAlpha then self:SetAlpha(1) end
            local f = self.GetFontString and self:GetFontString()
            if f then
                if f.SetDrawLayer then f:SetDrawLayer("OVERLAY", 7) end
                if f.SetAlpha then f:SetAlpha(1) end
            end
        end)
    end

    -- Preserve existing scripts
    local oldEnter = btn:GetScript("OnEnter")
    local oldLeave = btn:GetScript("OnLeave")
    local oldDown  = btn:GetScript("OnMouseDown")
    local oldUp    = btn:GetScript("OnMouseUp")
    local oldDis   = btn:GetScript("OnDisable")
    local oldEn    = btn:GetScript("OnEnable")

    local function ApplyBG(self, col)
    if not self or type(col) ~= "table" then return end
    local bg = self._msufBtnBG
    if bg and bg.SetVertexColor then
        bg:SetVertexColor(col[1], col[2], col[3], col[4])
    end
end

btn:SetScript("OnEnter", function(self, ...)
    ApplyBG(self, self._msufBtnBG_hover or self._msufBtnBG_base)
    if oldEnter then pcall(oldEnter, self, ...) end
end)
btn:SetScript("OnLeave", function(self, ...)
    ApplyBG(self, self._msufBtnBG_base)
    if oldLeave then pcall(oldLeave, self, ...) end
end)
btn:SetScript("OnMouseDown", function(self, ...)
    ApplyBG(self, self._msufBtnBG_pressed or self._msufBtnBG_hover)
    if oldDown then pcall(oldDown, self, ...) end
end)
btn:SetScript("OnMouseUp", function(self, ...)
    if self.IsMouseOver and self:IsMouseOver() then
        ApplyBG(self, self._msufBtnBG_hover or self._msufBtnBG_base)
    else
        ApplyBG(self, self._msufBtnBG_base)
    end
    if oldUp then pcall(oldUp, self, ...) end
end)
btn:SetScript("OnDisable", function(self, ...)
        if self._msufBtnBG then self._msufBtnBG:SetVertexColor(0.07, 0.07, 0.08, 0.65) end
        if self._msufBtnBorder and self._msufBtnBorder.SetVertexColor then self._msufBtnBorder:SetVertexColor(MSUF_PILL_EDGE_R, MSUF_PILL_EDGE_G, MSUF_PILL_EDGE_B, 0.45) end
        local f = self.GetFontString and self:GetFontString()
        if f and f.SetTextColor then f:SetTextColor(0.55, 0.60, 0.70, 0.85) end
        if oldDis then pcall(oldDis, self, ...) end
    end)
    btn:SetScript("OnEnable", function(self, ...)
        if self._msufBtnBG then self._msufBtnBG:SetVertexColor(0.09, 0.10, 0.12, 0.92) end
        if self._msufBtnBorder and self._msufBtnBorder.SetVertexColor then self._msufBtnBorder:SetVertexColor(MSUF_PILL_EDGE_R, MSUF_PILL_EDGE_G, MSUF_PILL_EDGE_B, 0.90) end
        local f = self.GetFontString and self:GetFontString()
        if f and f.SetTextColor then
            f:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA)
        end
        if oldEn then pcall(oldEn, self, ...) end
    end)
end


-- Apply Midnight black/blue styling to standard UIPanelButtons inside a frame (mirrored option panels etc.)
local function MSUF_ApplyMidnightControlsToFrame(root)
    if not root or not root.GetChildren then return end

    local function LooksLikePanelButton(b)
        if not b then return false end
        if (b.Left and b.Middle and b.Right) then return true end
        if not b.GetRegions then return false end
        local regions = { b:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.GetTexture then
                local ok, tex = pcall(r.GetTexture, r)
                if ok and type(tex) == "string" then
                    if tex:find("UI%-Panel%-Button") or tex:find("UIPanelButton") then
                        return true
                    end
                end
            end
        end
        return false
    end

    local function MaybeFixCheckLabel(cb)
        local fs = cb and (cb.Text or cb.text or (cb.GetFontString and cb:GetFontString()))
        if not (fs and fs.GetTextColor and fs.SetTextColor) then return end
        local r, g, b = fs:GetTextColor()
        -- Treat Blizzard's gold/yellow as "needs whitening"
        if r and g and b and r >= 0.86 and g >= 0.66 and b <= 0.45 then
            fs:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA)
        end
    end

    local function Walk(f)
        if not f then return end

        if f.GetObjectType then
            local ot = f:GetObjectType()
            if ot == "Button" then
                if not (f.IsObjectType and f:IsObjectType("CheckButton")) then
                    if LooksLikePanelButton(f) then
                        MSUF_SkinButton(f)
                    end
                end
            elseif ot == "CheckButton" then
                MaybeFixCheckLabel(f)
            end
        end

        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do
                Walk(kids[i])
            end
        end
    end

    Walk(root)
end


-- Nav-only skin: dark/blue buttons like Blizzard-style menus (self-contained, no textures required beyond WHITE8X8).
-- isHeader   = tree header (+/-)
-- isIndented = child leaf inside a tree (so its width stays inside the header row)
local function MSUF_SkinNavButton(btn, isHeader, isIndented)
    if not btn or btn.__MSUF_NavSkinned then return end
    btn.__MSUF_NavSkinned = true

    -- Never rely on the disabled-state to mark an active nav item;
    -- disabled buttons go grey and ignore highlight textures.
    if btn.SetEnabled then pcall(btn.SetEnabled, btn, true) end

    -- Kill UIPanelButtonTemplate pieces (these are what show the red/grey Blizzard button art)
    if btn.Left and btn.Left.Hide then btn.Left:Hide() end
    if btn.Middle and btn.Middle.Hide then btn.Middle:Hide() end
    if btn.Right and btn.Right.Hide then btn.Right:Hide() end

    -- Kill template textures so our skin is consistent
    if btn.GetNormalTexture and btn.SetNormalTexture then
        local nt = btn:GetNormalTexture()
        if nt and nt.SetAlpha then nt:SetAlpha(0) end
        pcall(btn.SetNormalTexture, btn, nil)
    end
    if btn.GetPushedTexture and btn.SetPushedTexture then
        local pt = btn:GetPushedTexture()
        if pt and pt.SetAlpha then pt:SetAlpha(0) end
        pcall(btn.SetPushedTexture, btn, nil)
    end
    if btn.GetHighlightTexture and btn.SetHighlightTexture then
        local ht = btn:GetHighlightTexture()
        if ht and ht.SetAlpha then ht:SetAlpha(0) end
        pcall(btn.SetHighlightTexture, btn, nil)
    end
    if btn.GetDisabledTexture and btn.SetDisabledTexture then
        local dt = btn:GetDisabledTexture()
        if dt and dt.SetAlpha then dt:SetAlpha(0) end
        pcall(btn.SetDisabledTexture, btn, nil)
    end


    -- Background (superellipse / pill style)
    local bg, border = MSUF_EnsureSuperellipseLayers(btn, 2)
    local active = MSUF_EnsureNavActiveOverlay(btn, bg)
    if active and active.SetVertexColor then
        -- Persistent selection highlight (stronger than hover, matches v11 request)
        active:SetVertexColor(0.16, 0.36, 0.80, 0.55)
    end
    if border and border.SetVertexColor then
        border:SetVertexColor(MSUF_PILL_EDGE_R, MSUF_PILL_EDGE_G, MSUF_PILL_EDGE_B, 0.90)
    end
    if bg and bg.SetVertexColor then
        if isIndented then
            bg:SetVertexColor(0.09, 0.10, 0.12, 0.82)
        else
            bg:SetVertexColor(0.09, 0.10, 0.12, 0.92)
        end
    end
    btn._msufNavBorder = border
    btn._msufNavBG = bg
    -- No separate hover/active textures (avoids stretch aliasing); we tint the BG instead.
    -- Text color (bluish-white like Blizzard AddOns menu)
    local fs = btn.GetFontString and btn:GetFontString()
    if fs and fs.SetTextColor then
        if isHeader then
            fs:SetTextColor(0.86, 0.92, 1.00, 0.92)
        else
            if isIndented then
                fs:SetTextColor(0.80, 0.88, 1.00, 0.92)
            else
                fs:SetTextColor(0.82, 0.90, 1.00, 1.00)
            end
        end
    end

    -- Stateful apply
    btn._msufApplyNavState = function(self, activeState, hovered)
    -- Persistent selection highlight (not just hover)
    if self._msufNavActive3 then
        if activeState then
            self._msufNavActive3:Show()
        else
            self._msufNavActive3:Hide()
        end
    end

    activeState = activeState and true or false
    hovered = hovered and true or false

    -- Text color
    local fs2 = self.GetFontString and self:GetFontString()
    if fs2 and fs2.SetTextColor then
        if activeState then
            fs2:SetTextColor(0.92, 0.96, 1.00, 1.00)
        else
            if isHeader then
                fs2:SetTextColor(0.86, 0.92, 1.00, 0.92)
            else
                if isIndented then
                    fs2:SetTextColor(0.80, 0.88, 1.00, 0.92)
                else
                    fs2:SetTextColor(0.82, 0.90, 1.00, 1.00)
                end
            end
        end
    end

    -- Background tint (no overlay textures -> avoids stretch aliasing)
    if self._msufNavBG and self._msufNavBG.SetVertexColor then
        if activeState then
            self._msufNavBG:SetVertexColor(0.12, 0.22, 0.40, 0.98)
        else
            if hovered then
                if isIndented then
                    self._msufNavBG:SetVertexColor(0.10, 0.11, 0.13, 0.90)
                else
                    self._msufNavBG:SetVertexColor(0.10, 0.11, 0.13, 0.99)
                end
            else
                if isIndented then
                    self._msufNavBG:SetVertexColor(0.09, 0.10, 0.12, 0.82)
                else
                    self._msufNavBG:SetVertexColor(0.09, 0.10, 0.12, 0.92)
                end
            end
        
-- Border tint (active gets a strong blue edge so selection is obvious)
if self._msufNavBorder and self._msufNavBorder.SetVertexColor then
    if activeState then
        self._msufNavBorder:SetVertexColor(0.30, 0.60, 1.00, 1.00)
    else
        if hovered then
            self._msufNavBorder:SetVertexColor(0.22, 0.45, 0.90, 0.95)
        else
            self._msufNavBorder:SetVertexColor(MSUF_PILL_EDGE_R, MSUF_PILL_EDGE_G, MSUF_PILL_EDGE_B, 0.80)
        end
    end
end

end
    end
end

-- Hook hover without breaking existing scripts
    local oldEnter = btn:GetScript("OnEnter")
    local oldLeave = btn:GetScript("OnLeave")

    btn:SetScript("OnEnter", function(self, ...)
        if self._msufApplyNavState then self:_msufApplyNavState(self._msufNavIsActive, true) end
        if oldEnter then pcall(oldEnter, self, ...) end
    end)
    btn:SetScript("OnLeave", function(self, ...)
        if self._msufApplyNavState then self:_msufApplyNavState(self._msufNavIsActive, false) end
        if oldLeave then pcall(oldLeave, self, ...) end
    end)
end


-- Export for any older call-sites that still reference the global.
_G.MSUF_SkinNavButton = MSUF_SkinNavButton


-- Dashboard-only button skin (used on the Menu/Dashboard page: shortcuts, scale preset buttons, etc.)
-- Goal: match the left nav style (dark + blue), without borders, and allow an optional "selected" state.
------------------------------------------------------


local function MSUF_SkinDashboardButton(btn)
    if not btn or btn.__MSUF_DashSkinned then return end
    btn.__MSUF_DashSkinned = true

    -- Remove UIPanelButtonTemplate art (the default red/grey pieces).
    -- NOTE: With unnamed buttons, template regions are not always exposed as .Left/.Middle/.Right,
    -- so we also scan regions defensively.
    if btn.Left and btn.Left.Hide then btn.Left:Hide() end
    if btn.Middle and btn.Middle.Hide then btn.Middle:Hide() end
    if btn.Right and btn.Right.Hide then btn.Right:Hide() end

    if btn.GetRegions then
        local regions = { btn:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then
				local tex = r.GetTexture and r:GetTexture()
				local atlas = r.GetAtlas and r:GetAtlas()

				-- These are the common UIPanelButtonTemplate textures / atlases that create the red look.
				-- NOTE: we use plain string matching; do NOT escape '-' when using find(..., true).
				local isPanelArt = false
				if type(atlas) == "string" then
					if atlas:find("UI-Panel-Button", 1, true) or atlas:find("UIPanelButton", 1, true) then
						isPanelArt = true
					end
				end
				if (not isPanelArt) and type(tex) == "string" then
					if tex:find("UI-Panel-Button", 1, true) or tex:find("UIPanelButton", 1, true) or tex:find("Buttons\\UI-Panel-Button", 1, true) then
						isPanelArt = true
					end
				end

				if isPanelArt then
					if r.SetAlpha then r:SetAlpha(0) end
					if r.Hide then r:Hide() end
				end
            end
        end
    end

    -- Kill template textures so the skin is deterministic
    if btn.GetNormalTexture and btn.SetNormalTexture then
        local nt = btn:GetNormalTexture()
        if nt and nt.SetAlpha then nt:SetAlpha(0) end
        pcall(btn.SetNormalTexture, btn, nil)
    end
    if btn.GetPushedTexture and btn.SetPushedTexture then
        local pt = btn:GetPushedTexture()
        if pt and pt.SetAlpha then pt:SetAlpha(0) end
        pcall(btn.SetPushedTexture, btn, nil)
    end
    if btn.GetHighlightTexture and btn.SetHighlightTexture then
        local ht = btn:GetHighlightTexture()
        if ht and ht.SetAlpha then ht:SetAlpha(0) end
        pcall(btn.SetHighlightTexture, btn, nil)
    end
    if btn.GetDisabledTexture and btn.SetDisabledTexture then
        local dt = btn:GetDisabledTexture()
        if dt and dt.SetAlpha then dt:SetAlpha(0) end
        pcall(btn.SetDisabledTexture, btn, nil)
    end

    -- Background + subtle rounded border (tooltip border gives the "superellipse-ish" Apple vibe)
    local bgHost = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bgHost:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    bgHost:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    local lvl = (btn.GetFrameLevel and btn:GetFrameLevel()) or 1
    if bgHost.SetFrameLevel then bgHost:SetFrameLevel((lvl > 1) and (lvl - 1) or 0) end
    if bgHost.SetBackdrop then
        bgHost:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        bgHost:SetBackdropColor(0.08, 0.09, 0.11, 0.92)
        if bgHost.SetBackdropBorderColor then
            bgHost:SetBackdropBorderColor(0, 0, 0, 0.92)
        end
    end
    btn._msufDashBGFrame = bgHost

    -- Fallback flat fill (kept for safety even if Backdrop is unavailable)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface/Buttons/WHITE8X8")
    bg:SetAllPoints(bgHost)
    bg:SetVertexColor(0.09, 0.10, 0.12, 0.92)
    if btn._msufDashBGFrame and btn._msufDashBGFrame.SetBackdrop then
        -- Backdrop already draws the fill; keep this nearly invisible.
        bg:SetAlpha(0.01)
    end
    btn._msufDashBG = bg

    -- Hover
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetTexture("Interface/Buttons/WHITE8X8")
    hover:SetAllPoints(bg)
    hover:SetVertexColor(0.25, 0.55, 1.0, 0.18)
    hover:Hide()
    btn._msufDashHover = hover

    -- Selected (optional persistent highlight)
    local sel = btn:CreateTexture(nil, "ARTWORK")
    sel:SetTexture("Interface/Buttons/WHITE8X8")
    sel:SetAllPoints(bg)
    sel:SetVertexColor(0.25, 0.55, 1.0, 0.30)
    sel:Hide()
    btn._msufDashSelected = sel

    -- Pressed feedback (brief)
    local down = btn:CreateTexture(nil, "OVERLAY")
    down:SetTexture("Interface/Buttons/WHITE8X8")
    down:SetAllPoints(bg)
    down:SetVertexColor(0.25, 0.55, 1.0, 0.22)
    down:Hide()
    btn._msufDashDown = down

    local function ApplyText(active)
        local fs = btn.GetFontString and btn:GetFontString()
        if fs and fs.SetTextColor then
            if active then
                fs:SetTextColor(0.92, 0.96, 1.00, 1.00)
            else
                fs:SetTextColor(0.82, 0.90, 1.00, 1.00)
            end
        end
    end
    ApplyText(false)

    btn._msufSetSelected = function(self, active)
        self._msufDashIsSelected = active and true or false
        if self._msufDashSelected then
            if self._msufDashIsSelected then self._msufDashSelected:Show() else self._msufDashSelected:Hide() end
        end
        ApplyText(self._msufDashIsSelected)
        if self._msufDashHover then
            if self._msufDashHover._msufHovering and not self._msufDashIsSelected then self._msufDashHover:Show() else self._msufDashHover:Hide() end
        end
    end

    -- Hover hooks
    local oldEnter = btn:GetScript("OnEnter")
    local oldLeave = btn:GetScript("OnLeave")
    btn:SetScript("OnEnter", function(self, ...)
        if self._msufDashHover then
            self._msufDashHover._msufHovering = true
            if not self._msufDashIsSelected then self._msufDashHover:Show() end
        end
        if oldEnter then pcall(oldEnter, self, ...) end
    end)
    btn:SetScript("OnLeave", function(self, ...)
        if self._msufDashHover then
            self._msufDashHover._msufHovering = false
            self._msufDashHover:Hide()
        end
        if oldLeave then pcall(oldLeave, self, ...) end
    end)

    -- Mouse down/up (pressed feedback)
    local oldDown = btn:GetScript("OnMouseDown")
    local oldUp = btn:GetScript("OnMouseUp")
    btn:SetScript("OnMouseDown", function(self, ...)
        if self._msufDashDown then self._msufDashDown:Show() end
        if oldDown then pcall(oldDown, self, ...) end
    end)
    btn:SetScript("OnMouseUp", function(self, ...)
        if self._msufDashDown then self._msufDashDown:Hide() end
        if oldUp then pcall(oldUp, self, ...) end
    end)

    -- If a button ever gets disabled, keep it readable (don’t fall back to Blizzard grey art)
    local oldDisable = btn:GetScript("OnDisable")
    local oldEnable  = btn:GetScript("OnEnable")
    btn:SetScript("OnDisable", function(self, ...)
        if self._msufDashBG then self._msufDashBG:SetVertexColor(0.06, 0.06, 0.07, 0.65) end
        local fs = self.GetFontString and self:GetFontString()
        if fs and fs.SetTextColor then fs:SetTextColor(0.55, 0.60, 0.70, 0.85) end
        if oldDisable then pcall(oldDisable, self, ...) end
    end)
    btn:SetScript("OnEnable", function(self, ...)
        if self._msufDashBG then self._msufDashBG:SetVertexColor(0.08, 0.09, 0.11, 0.92) end
        ApplyText(self._msufDashIsSelected)
        if oldEnable then pcall(oldEnable, self, ...) end
    end)
end


-- Force mirrored option panels to use the same "white" text as the mini menu.
-- We only recolor *yellow-ish* labels (most MSUF option headers/labels) to avoid breaking disabled grey text.
local function MSUF_IsYellowish(r, g, b)
    if not r or not g or not b then return false end
    -- Typical WoW yellow is roughly (1.0, 0.82, 0.0). Use generous thresholds.
    if r >= 0.88 and g >= 0.68 and b <= 0.35 and (g >= (b + 0.25)) then
        return true
    end
    return false
end

local function MSUF_ApplyWhiteTextToFrame(root)
    if not root then return end

    -- This function can be called very early after /reload while Settings is still building.
    -- A deep recursive walk can easily trigger "script ran too long", and some frames can appear
    -- multiple times in GetChildren chains. We therefore:
    -- 1) walk iteratively (no recursion),
    -- 2) de-dupe nodes via a seen table,
    -- 3) time-slice the scan over multiple frames when possible.
    local token = (root.__MSUF_WhiteTextToken or 0) + 1
    root.__MSUF_WhiteTextToken = token

    local useTimer = (C_Timer and C_Timer.After) and true or false
    local maxNodes = useTimer and 4500 or 800
    local budgetMs = useTimer and 1.0 or nil
    local debugprofilestop = debugprofilestop

    local stack, sp = { root }, 1
    local seen = {}
    local nodes = 0

    local function ProcessChunk()
        if not root or root.__MSUF_WhiteTextToken ~= token then return end

        local t0 = (budgetMs and debugprofilestop) and debugprofilestop() or nil

        while sp > 0 do
            if t0 and (debugprofilestop() - t0) >= budgetMs then
                break
            end

            local frame = stack[sp]
            stack[sp] = nil
            sp = sp - 1

            if frame and not seen[frame] then
                seen[frame] = true
                nodes = nodes + 1
                if nodes > maxNodes then
                    break
                end

                -- Regions (FontStrings)
                if frame.GetRegions then
                    local regions = { frame:GetRegions() }
                    for i = 1, #regions do
                        local reg = regions[i]
                        if reg and reg.GetObjectType and reg:GetObjectType() == "FontString" and reg.GetTextColor and reg.SetTextColor then
                            local r, g, b = reg:GetTextColor()
                            if MSUF_IsYellowish(r, g, b) then
                                reg:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA)
                            end
                        end
                    end
                end

                -- Children
                if frame.GetChildren then
                    local children = { frame:GetChildren() }
                    for i = 1, #children do
                        local c = children[i]
                        if c and not seen[c] then
                            sp = sp + 1
                            stack[sp] = c
                        end
                    end
                end
            end
        end

        -- More to process? yield to avoid "script ran too long".
        if sp > 0 and nodes <= maxNodes and root and root.__MSUF_WhiteTextToken == token then
            if useTimer then
                C_Timer.After(0, ProcessChunk)
            end
        end
    end

    ProcessChunk()
end


-- ------------------------------------------------------------
-- Font size bump (readability)
-- Applies a consistent +N size to all FontStrings / EditBoxes under a root,
-- while remembering original fonts so we never "stack" bumps across page swaps.
local function MSUF_ApplyFontBumpToFrame(root, bump)
    bump = tonumber(bump or 0) or 0
    if bump == 0 or not root then return end
    if root.__MSUF_FontBumpApplied == bump then
        return
    end

    local function bumpFont(obj)
        if not obj or not obj.GetFont or not obj.SetFont then return end
        local ok, font, size, flags = pcall(obj.GetFont, obj)
        if not ok or not font or not size then return end

        if not obj.__MSUF_FontOrig then
            obj.__MSUF_FontOrig = { font = font, size = size, flags = flags }
        end
        local orig = obj.__MSUF_FontOrig
        pcall(obj.SetFont, obj, orig.font, (orig.size or size) + bump, orig.flags)
    end

    local function applyOnFrame(frame)
        if not frame then return end

        -- Frames like EditBox also have GetFont/SetFont
        bumpFont(frame)

        if frame.GetRegions then
            local regions = { frame:GetRegions() }
            for i = 1, #regions do
                bumpFont(regions[i])
            end
        end

        if frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                applyOnFrame(children[i])
            end
        end
    end

    applyOnFrame(root)
    root.__MSUF_FontBumpApplied = bump
end

-- ------------------------------------------------------------
-- Open MSUF Blizzard Settings category (robust: always pass numeric ID)
-- ------------------------------------------------------------
local function MSUF_CollectMsufScaleFrames()
    local frames, seen = {}, {}

    local function add(f)
        if not f or seen[f] then return end
        if type(f) == "table" and type(f.SetScale) == "function" then
            seen[f] = true
            table.insert(frames, f)
        end
    end

    if type(_G.MSUF_UnitFrames) == "table" then
        for _, f in pairs(_G.MSUF_UnitFrames) do
            add(f)
        end
    end

    -- Common castbar globals (real + preview)
    add(_G.MSUF_PlayerCastbar)
    add(_G.MSUF_TargetCastbar)
    add(_G.MSUF_FocusCastbar)
    add(_G.MSUF_PlayerCastbarPreview)
    add(_G.MSUF_TargetCastbarPreview)
    add(_G.MSUF_FocusCastbarPreview)
    add(_G.MSUF_BossCastbar)
    add(_G.MSUF_BossCastbarPreview)

    return frames
end

local function MSUF_GetSavedMsufScale()
    local g = MSUF_EnsureGeneral()
    if not g then return 1.0 end

    -- migration: older builds may have used general.uiScale for MSUF scale
    local v = tonumber(g.msufUiScale)
    if not v then v = tonumber(g.uiScale) end
    if not v then v = 1.0 end
    return clamp(v, 0.6, 1.4)
end

local function MSUF_SetSavedMsufScale(v)
    local g = MSUF_EnsureGeneral()
    if not g then return end
    v = tonumber(v) or 1.0
    g.msufUiScale = clamp(v, 0.6, 1.4)
end

-- Master kill-switch for any MSUF scaling (global UI scale + MSUF-only scale).
-- When enabled, MSUF will not apply/enforce scaling on login, resize, or deferred combat-exit applies.
local function MSUF_IsScalingDisabled()
    local g = MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
    return (g and g.disableScaling) and true or false
end

local _MSUF_pendingMsufScale
local _MSUF_pendingGlobalScale
local _MSUF_pendingDisableScaling
local _MSUF_pendingReloadOnScalingOff
local _MSUF_scaleApplyWatcher
local MSUF_EnsureScaleApplyAfterCombat -- forward

local function MSUF_ApplyMsufScale(scale, opts)
    if MSUF_IsScalingDisabled() and not (opts and opts.ignoreDisable) then
        return
    end

    scale = tonumber(scale)
    if not scale then return end
    scale = clamp(scale, 0.6, 1.4)
    -- Secure/taint-safe: unitframe buttons are typically protected; scaling them in combat will trigger ADDON_ACTION_BLOCKED.
    if InCombatLockdown and InCombatLockdown() then
        _MSUF_pendingMsufScale = scale
        if MSUF_EnsureScaleApplyAfterCombat then
            MSUF_EnsureScaleApplyAfterCombat()
        end
        return
    end


    local frames = MSUF_CollectMsufScaleFrames()
    for i = 1, #frames do
        local f = frames[i]
        pcall(f.SetScale, f, scale)
    end
end

-- ------------------------------------------------------------
-- Global UI scale (whole WoW UI) - MSUF override (Hybrid: CVars + UIParent)
-- Pattern: Razor-style robust scaling
--   1) Set CVars (useUiScale/uiScale) so Blizzard + other addons see a sane value (clamped to >= 0.64)
--   2) Also set UIParent scale to the exact desired value (can be < 0.64, e.g. 1440p 0.5333)
--   3) Never apply in combat: defer until PLAYER_REGEN_ENABLED (prevents ADDON_ACTION_BLOCKED)
-- ------------------------------------------------------------
local UI_SCALE_1080 = 768 / 1080 -- ~0.7111
local UI_SCALE_1440 = 768 / 1440 -- ~0.5333

local MSUF_MIN_UISCALE_CVAR = 0.64
local MSUF_MAX_UISCALE_CVAR = 1.0

local _MSUF_lastGlobalCVarScale
local _MSUF_lastGlobalUiParentScale

local function MSUF_GetCurrentGlobalUiScale()
    if UIParent and UIParent.GetScale then
        return tonumber(UIParent:GetScale())
    end
    return nil
end

local function MSUF_SetCVarIfChanged(name, value)
    if not name or value == nil then return end
    local v = tostring(value)

    if C_CVar and C_CVar.GetCVar and C_CVar.SetCVar then
        local cur = C_CVar.GetCVar(name)
        if cur ~= v then
            pcall(C_CVar.SetCVar, name, v)
        end
        return
    end

    if GetCVar and SetCVar then
        local cur = GetCVar(name)
        if cur ~= v then
            pcall(SetCVar, name, v)
        end
    end
end

local function MSUF_EnforceUIParentScale(scale)
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = clamp(scale, 0.3, 2.0)

    if not (UIParent and UIParent.SetScale) then return end

    -- IMPORTANT: do NOT rely only on "last value we set".
    -- UIParent scale can be overridden after we set it (Blizzard login flow / other addons).
    -- So we compare against the *current* UIParent:GetScale() and re-apply if it drifted.
    local cur = nil
    if UIParent.GetScale then
        cur = tonumber(UIParent:GetScale())
    end
    cur = cur or 0

    if math.abs(cur - scale) > 0.001 then
        pcall(UIParent.SetScale, UIParent, scale)
    end

    -- Cache the desired value (for informational/diagnostic use only).
    _MSUF_lastGlobalUiParentScale = scale
end

local function MSUF_ScheduleUIParentNudges(scale)
    if MSUF_IsScalingDisabled() then return end
    -- Short, finite "watch" that re-applies UIParent scale a few times after we set CVars.
    -- This beats late login-time overrides without running a permanent ticker.
    if not (C_Timer and C_Timer.After) then return end
    scale = tonumber(scale)
    if not scale or scale <= 0 then return end

    local want = scale
    local function nudge()
        if InCombatLockdown and InCombatLockdown() then
            _MSUF_pendingGlobalScale = want
            if MSUF_EnsureScaleApplyAfterCombat then
                MSUF_EnsureScaleApplyAfterCombat()
            end
            return
        end
        MSUF_EnforceUIParentScale(want)
    end

    -- Coalesced nudges (covers most "late reset to 0.64" scenarios)
    C_Timer.After(0.05, nudge)
    C_Timer.After(0.25, nudge)
    C_Timer.After(0.60, nudge)
end

local function MSUF_SetGlobalUiScale(scale, silent, opts)
    opts = opts or {}
    if MSUF_IsScalingDisabled() and not opts.ignoreDisable then
        return
    end
    local applyCVars = (opts.applyCVars ~= false) and true or false

    scale = tonumber(scale)
    if not scale or scale <= 0 then return end
    scale = clamp(scale, 0.3, 2.0)

    if InCombatLockdown and InCombatLockdown() then
        -- Secure/taint-safe: scale changes may be protected in combat.
        _MSUF_pendingGlobalScale = scale
        if MSUF_EnsureScaleApplyAfterCombat then
            MSUF_EnsureScaleApplyAfterCombat()
        end
        if not silent then
            MSUF_Print("Cannot change global UI scale in combat. Will apply after combat.")
        end
        return
    end

    if applyCVars then
        local cvarScale = clamp(scale, MSUF_MIN_UISCALE_CVAR, MSUF_MAX_UISCALE_CVAR)
        if _MSUF_lastGlobalCVarScale ~= cvarScale then
            MSUF_SetCVarIfChanged("useUiScale", "1")
            MSUF_SetCVarIfChanged("uiScale", cvarScale)
            -- Some clients/addons read lowercase as well; harmless to set.
            MSUF_SetCVarIfChanged("uiscale", cvarScale)
            _MSUF_lastGlobalCVarScale = cvarScale
        end
    end

    MSUF_EnforceUIParentScale(scale)
    MSUF_ScheduleUIParentNudges(scale)

    if not silent then
        local cvarScale = clamp(scale, MSUF_MIN_UISCALE_CVAR, MSUF_MAX_UISCALE_CVAR)
        MSUF_Print(string.format("Global UI scale set to %.3f (CVar %.3f)", scale, cvarScale))
    end
end

-- ------------------------------------------------------------
-- Combat lockdown deferral for scaling (prevents ADDON_ACTION_BLOCKED)
-- ------------------------------------------------------------
MSUF_EnsureScaleApplyAfterCombat = function()
    if _MSUF_scaleApplyWatcher then return end
    if not CreateFrame then return end

    local f = CreateFrame("Frame")
    _MSUF_scaleApplyWatcher = f
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if InCombatLockdown and InCombatLockdown() then return end

        -- If the user pressed the scaling "OFF" kill-switch in combat, apply the hard reset now.
        if _MSUF_pendingDisableScaling then
            _MSUF_pendingDisableScaling = nil
            _MSUF_pendingMsufScale = nil
            _MSUF_pendingGlobalScale = nil
            MSUF_ResetGlobalUiScale(true)
            MSUF_ApplyMsufScale(1.0, { ignoreDisable = true })

        -- If scaling is disabled, never apply any deferred scale changes.
        elseif MSUF_IsScalingDisabled() then
            _MSUF_pendingMsufScale = nil
            _MSUF_pendingGlobalScale = nil

        else
            local s = _MSUF_pendingMsufScale
            local g = _MSUF_pendingGlobalScale
            _MSUF_pendingMsufScale = nil
            _MSUF_pendingGlobalScale = nil

            if s then
                MSUF_ApplyMsufScale(s)
            end
            if g then
                MSUF_SetGlobalUiScale(g, true)
            end
        end

        -- If the user requested a forced reload after disabling scaling, do it once we're safe.
        if _MSUF_pendingReloadOnScalingOff then
            _MSUF_pendingReloadOnScalingOff = nil
            if type(ReloadUI) == "function" then
                ReloadUI()
                return
            end
        end

        -- If nothing remains pending, remove the watcher to keep things idle-clean.
        if (not _MSUF_pendingDisableScaling) and (not _MSUF_pendingMsufScale) and (not _MSUF_pendingGlobalScale) then
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", nil)
            _MSUF_scaleApplyWatcher = nil
        end
    end)
end

local function MSUF_ResetGlobalUiScale(silent)
    if InCombatLockdown and InCombatLockdown() then
        if not silent then
            MSUF_Print("Cannot reset global UI scale in combat.")
        end
        return
    end

    -- Best-effort restore to Blizzard defaults. A ReloadUI() is the clean restore path.
    MSUF_SetCVarIfChanged("useUiScale", "0")
    MSUF_SetCVarIfChanged("uiScale", "1.0")
    MSUF_SetCVarIfChanged("uiscale", "1.0")

    if UIParent and UIParent.SetScale then
        pcall(UIParent.SetScale, UIParent, 1.0)
    end

    _MSUF_lastGlobalCVarScale = nil
    _MSUF_lastGlobalUiParentScale = nil

    if not silent then
        MSUF_Print("Global UI scale reset (fallback).")
    end
end

-- Public helper: disables/enables ALL MSUF scaling.
-- disable=true will:
--   - stop enforcing MSUF global UI scale (set preset to Auto)
--   - reset Blizzard CVars/UIParent scale to defaults (best-effort)
--   - reset MSUF-only scale to 1.0
-- Works in combat (defers protected changes until combat ends).
local function MSUF_SetScalingDisabled(disable, silent)
    local g = MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
    if not g then return end

    disable = disable and true or false
    g.disableScaling = disable

    if not disable then
        _MSUF_pendingDisableScaling = nil
        return
    end

    -- Stop enforcing global presets.
    g.globalUiScalePreset = "auto"
    g.globalUiScaleValue = nil

    -- Reset MSUF-only scale to 1.0 and persist it.
    MSUF_SetSavedMsufScale(1.0)

    -- Protected operations: defer until out of combat.
    if InCombatLockdown and InCombatLockdown() then
        _MSUF_pendingDisableScaling = true
        if MSUF_EnsureScaleApplyAfterCombat then
            MSUF_EnsureScaleApplyAfterCombat()
        end
        if not silent then
            MSUF_Print("MSUF scaling disabled. Will fully reset after combat.")
        end
        return
    end

    MSUF_ResetGlobalUiScale(true)
    MSUF_ApplyMsufScale(1.0, { ignoreDisable = true })

    _MSUF_pendingDisableScaling = nil
    _MSUF_pendingMsufScale = nil
    _MSUF_pendingGlobalScale = nil

    if not silent then
        MSUF_Print("MSUF scaling disabled (Blizzard handles scaling now).")
    end
end

-- Optional global access for other modules/UI
_G.MSUF_SetScalingDisabled = MSUF_SetScalingDisabled

local function MSUF_SaveGlobalPreset(preset, scale)
    local g = MSUF_EnsureGeneral()
    if not g then return end
    g.globalUiScalePreset = preset
    g.globalUiScaleValue = scale
end

local function MSUF_GetDesiredGlobalScaleFromDB()
    local g = MSUF_EnsureGeneral()
    if not g then
        return nil
    end

    if g.disableScaling then
        return nil
    end

    local preset = g.globalUiScalePreset
    if preset == "1080p" then
        return UI_SCALE_1080
    elseif preset == "1440p" then
        return UI_SCALE_1440
    elseif preset == "custom" and g.globalUiScaleValue then
        return tonumber(g.globalUiScaleValue)
    end
    -- "auto" or nil => do nothing (let Blizzard / other addons decide)
    return nil
end

-- ------------------------------------------------------------
-- Global UI scale guardian (nudges UIParent back if it got overridden)
-- NOTE: guardian is UIParent-only to avoid CVar spam. CVars are set on login / preset changes.
-- ------------------------------------------------------------
local MSUF_SCALE_GUARD = { suppressUntil = 0 }

local function MSUF_EnsureGlobalUiScaleApplied(silent)
    if MSUF_IsScalingDisabled() then return end
    local now = (GetTime and GetTime()) or 0
    if now < (MSUF_SCALE_GUARD.suppressUntil or 0) then return end

    local want = MSUF_GetDesiredGlobalScaleFromDB()
    want = tonumber(want)
    if not want or want <= 0 then
        return -- auto: do not enforce
    end

    local have = MSUF_GetCurrentGlobalUiScale()
    have = tonumber(have) or want

    local diff = math.abs(have - want)
    if diff > 0.001 then
        MSUF_SCALE_GUARD.suppressUntil = now + 0.10

        if InCombatLockdown and InCombatLockdown() then
            _MSUF_pendingGlobalScale = want
            if MSUF_EnsureScaleApplyAfterCombat then
                MSUF_EnsureScaleApplyAfterCombat()
            end
            return
        end

        MSUF_EnforceUIParentScale(want)

        -- Extra nudges to beat race conditions / one-time overrides (UIParent only).
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() MSUF_EnforceUIParentScale(want) end)
            C_Timer.After(0.25, function() MSUF_EnforceUIParentScale(want) end)
            C_Timer.After(1.0, function() MSUF_EnforceUIParentScale(want) end)
        end
    end
end


-- ------------------------------------------------------------
-- Edit Mode state helper (used for Dashboard button highlight)
-- ------------------------------------------------------------
-- ------------------------------------------------------------
local function MSUF_IsMSUFEditModeActive()
    local st = _G and _G.MSUF_EditState
    if type(st) == "table" and st.active ~= nil then
        return st.active and true or false
    end
    if _G and type(_G.MSUF_IsEditModeActive) == "function" then
        local ok, res = pcall(_G.MSUF_IsEditModeActive)
        if ok then return res and true or false end
    end
    if _G and _G.MSUF_EDITMODE_ACTIVE ~= nil then
        return _G.MSUF_EDITMODE_ACTIVE and true or false
    end
    return false
end

local function MSUF_TryHookEditModeForDashboard()
    if _G and _G.__MSUF_DashEditHooked then return end
    if not hooksecurefunc then return end

    -- Prefer the direct MSUF EditMode function (known-good baseline in this project).
    if _G and type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        hooksecurefunc("MSUF_SetMSUFEditModeDirect", function(active)
            local win = _G and _G.MSUF_StandaloneOptionsWindow
            local b = win and win._msufDashEditBtn
            if b and b._msufSetSelected then
                b:_msufSetSelected(active)
            end
        end)
        if _G then _G.__MSUF_DashEditHooked = true end
    end
end

-- ------------------------------------------------------------
-- Mini menu tools builder (kept small + robust)
-- ------------------------------------------------------------
MSUF_BuildTools = function(parent, opts)
    opts = opts or {}
    local isWide = opts.wide and true or false
    if not parent then
        return { Refresh = function() end }
    end

    local api = {}

    local isXL = opts.xl and true or false


    local seg = opts.segmented and true or false
    local segGap = seg and -1 or 8
    local segW = seg and (isXL and 84 or 78) or 56
    local segH = seg and 22 or 20
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 6, -2)
    local titleText = (opts and opts.title) or "Tools"
    title:SetText(titleText)
    MSUF_SkinTitle(title)

    -- Global UI scale
    local globalLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    globalLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    globalLabel:SetText("Global UI Scale")
    MSUF_SkinText(globalLabel)

    local globalCur = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    globalCur:SetPoint("TOPLEFT", globalLabel, "BOTTOMLEFT", 0, -6)
    globalCur:SetText("Current: ...")
    MSUF_SkinText(globalCur)

local btn1080 = UI_Button(parent, "1080", segW, segH, "TOPLEFT", globalCur, "BOTTOMLEFT", 0, -8, function()
    MSUF_ShowReloadConfirm("Global UI Scale: 1080p", function()
        -- If the user previously disabled scaling entirely, re-enable it on intent.
        if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false, true) end
        MSUF_SaveGlobalPreset("1080p", UI_SCALE_1080)
        MSUF_SetGlobalUiScale(UI_SCALE_1080, true)
        ReloadUI()
    end)
end)

    -- Dashboard styling (dark + blue, no red)
    MSUF_SkinDashboardButton(btn1080)

local btn1440 = UI_Button(parent, "1440", segW, segH, "LEFT", btn1080, "RIGHT", segGap, 0, function()
    MSUF_ShowReloadConfirm("Global UI Scale: 1440p", function()
        if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false, true) end
        MSUF_SaveGlobalPreset("1440p", UI_SCALE_1440)
        MSUF_SetGlobalUiScale(UI_SCALE_1440, true)
        ReloadUI()
    end)
end)

    MSUF_SkinDashboardButton(btn1440)

local btnAuto = UI_Button(parent, "Auto", segW, segH, "LEFT", btn1440, "RIGHT", segGap, 0, function()
    MSUF_ShowReloadConfirm("Global UI Scale: Auto", function()
        if _G and _G.MSUF_SetScalingDisabled then _G.MSUF_SetScalingDisabled(false, true) end
        MSUF_SaveGlobalPreset("auto", nil)
        MSUF_ResetGlobalUiScale(true)
        ReloadUI()
    end)
end)

    MSUF_SkinDashboardButton(btnAuto)

    if MSUF_AddTooltip then
        MSUF_AddTooltip(btn1080, "Global UI Scale: 1080", "Applies MSUF\'s global scale preset for 1080p-like setups and reloads your UI. Auto restores Blizzard scaling on reload.")
        MSUF_AddTooltip(btn1440, "Global UI Scale: 1440", "Applies MSUF\'s global scale preset for 1440p-like setups and reloads your UI. Auto restores Blizzard scaling on reload.")
        MSUF_AddTooltip(btnAuto, "Global UI Scale: Auto", "Stops enforcing MSUF global scale and restores your previous Blizzard UI scale.")
    end


    -- UI scale slider (GLOBAL: scales the whole WoW UI via UIParent)
    -- Requested: 100% -> 10% range, and apply to everything (not only MSUF frames).
    local msufLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    msufLabel:SetPoint("TOPLEFT", btn1080, "BOTTOMLEFT", 0, -12)
    msufLabel:SetText("UI Scale (10–100%)")
    MSUF_SkinText(msufLabel)

    local sliderName = "MSUF_MiniMenuGlobalUiScalePctSlider"
    local msufSlider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    -- NOTE: The +/- buttons sit left/right of the slider. If the slider starts at x=0,
    -- the minus button can extend beyond the box padding and get clipped by the panel mask.
    -- Offset the slider to the right by (button width + gap) so the minus button stays fully visible.
    msufSlider:SetPoint("TOPLEFT", msufLabel, "BOTTOMLEFT", 30, -6)
    msufSlider:SetWidth(190) -- keep compact so +/- stay inside; avoids layout pushing right
    msufSlider:SetMinMaxValues(10, 100)
    msufSlider:SetValueStep(1)
    if msufSlider.SetObeyStepOnDrag then
        msufSlider:SetObeyStepOnDrag(true)
    end


    -- Step helper used by both buttons and click-overlay
    local function MSUF_ScaleSlider_GetStepMult()
        if IsControlKeyDown and IsControlKeyDown() then return 10 end
        if IsShiftKeyDown and IsShiftKeyDown() then return 5 end
        return 1
    end

    local function MSUF_ScaleSlider_Bump(delta)
        if not msufSlider or not msufSlider.GetValue then return end
        local v = tonumber(msufSlider:GetValue()) or 100
        v = math.floor(v + 0.5)
        local step = (msufSlider.GetValueStep and tonumber(msufSlider:GetValueStep())) or 1
        local mult = MSUF_ScaleSlider_GetStepMult()
        local nv = v + (delta * step * mult)
        nv = clamp(nv, 10, 100)
        msufSlider:SetValue(nv)
    end

    -- IMPORTANT UX:
    -- Global UI scale changes immediately alter effective frame scales/positions.
    -- Dragging a slider thumb while the world is rescaling causes the cursor math
    -- to "fight" the new scale and the value appears to jump around.
    -- Request: make the slider edge-clickable (no thumb drag).
    do
        -- Disable direct mouse interaction on the Slider (prevents thumb dragging).
        if msufSlider.EnableMouse then msufSlider:EnableMouse(false) end

        -- Hide the thumb to make it obvious this is not a drag-control.
        local sn = msufSlider.GetName and msufSlider:GetName() or nil
        local thumb = sn and _G[sn .. "Thumb"] or nil
        if thumb then
            if thumb.Hide then thumb:Hide() end
            if thumb.EnableMouse then thumb:EnableMouse(false) end
        end

        -- Transparent click overlay: click LEFT edge to -1, RIGHT edge to +1.
        local click = CreateFrame("Button", nil, msufSlider)
        click:SetAllPoints(msufSlider)
        click:EnableMouse(true)
        click:SetFrameLevel((msufSlider.GetFrameLevel and msufSlider:GetFrameLevel() or 1) + 10)

        -- Use shared bump helper (buttons + click-overlay)
        click:SetScript("OnMouseDown", function(self, btn)
            if btn ~= "LeftButton" then return end
            local w = (self.GetWidth and self:GetWidth()) or 0
            if w <= 0 then return end

            local x = select(1, GetCursorPosition())
            local s = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
            if s == 0 then s = 1 end
            x = x / s

            local left = select(1, self:GetLeft()) or 0
            local relX = x - left

            -- Only the outer edges are clickable (prevents accidental changes).
            local edge = 26
            if relX <= edge then
                MSUF_ScaleSlider_Bump(-1)
            elseif relX >= (w - edge) then
                MSUF_ScaleSlider_Bump(1)
            end
        end)

        -- Optional: mouse wheel adjusts too (up = +, down = -).
        click:EnableMouseWheel(true)
        click:SetScript("OnMouseWheel", function(self, delta)
            if delta and delta > 0 then
                MSUF_ScaleSlider_Bump(1)
            elseif delta and delta < 0 then
                MSUF_ScaleSlider_Bump(-1)
            end
        end)
    end

    local n = msufSlider:GetName()
    if n and _G[n .. "Text"] then _G[n .. "Text"]:SetText("") end
    if n and _G[n .. "Low"] then _G[n .. "Low"]:SetText("10%") end
    if n and _G[n .. "High"] then _G[n .. "High"]:SetText("100%") end
    if n and _G[n .. "Low"] and _G[n .. "Low"].SetTextColor then _G[n .. "Low"]:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA) end
    if n and _G[n .. "High"] and _G[n .. "High"].SetTextColor then _G[n .. "High"]:SetTextColor(MSUF_THEME.textR, MSUF_THEME.textG, MSUF_THEME.textB, MSUF_THEME.textA) end

    -- +/- buttons (requested: buttons to press instead of dragging/clicking slider)
    local msufMinus = UI_Button(parent, "–", 24, 18, "RIGHT", msufSlider, "LEFT", -6, 0, function()
        MSUF_ScaleSlider_Bump(-1)
    end)
    local msufPlus = UI_Button(parent, "+", 24, 18, "LEFT", msufSlider, "RIGHT", 6, 0, function()
        MSUF_ScaleSlider_Bump(1)
    end)
    MSUF_SkinDashboardButton(msufMinus)
    MSUF_SkinDashboardButton(msufPlus)

    if MSUF_AddTooltip then
        MSUF_AddTooltip(msufMinus, "UI Scale -", "Decrease global UI scale. Shift=5%, Ctrl=10%.")
        MSUF_AddTooltip(msufPlus, "UI Scale +", "Increase global UI scale. Shift=5%, Ctrl=10%.")
    end

    local msufValue = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Always show the current percent (requested)
    msufValue:SetPoint("BOTTOM", msufSlider, "TOP", 0, 2)
    msufValue:SetText("100%")
    msufValue:Show()
    MSUF_SkinText(msufValue)

    local resetW = (isWide and (isXL and 92 or 80)) or (isXL and 78 or 62)

    -- Tiny local helpers (keep the scaling UI actions readable)
    local function MSUF_EnableScalingSilently()
        if _G and _G.MSUF_SetScalingDisabled then
            _G.MSUF_SetScalingDisabled(false, true)
        end
    end

    local function MSUF_SetSliderValueSilent(v)
        if not msufSlider then return end
        msufSlider._msufIgnore = true
        msufSlider:SetValue(v)
        msufSlider._msufIgnore = false
    end

    local function MSUF_RequestReloadSafe()
        -- If clicked in combat, defer the reload until combat ends so the scale reset can apply first.
        if InCombatLockdown and InCombatLockdown() then
            _MSUF_pendingReloadOnScalingOff = true
            if MSUF_EnsureScaleApplyAfterCombat then
                MSUF_EnsureScaleApplyAfterCombat()
            end
            return
        end
        if type(ReloadUI) == "function" then
            ReloadUI()
        end
    end

    local msufOff -- forward (used by MSUF_SetScalingToggleVisual)

    local function MSUF_SetScalingToggleVisual(disabled)
        if not msufOff or not msufOff.GetFontString then return end
        local fs = msufOff:GetFontString()
        if not fs then return end
        if disabled then
            if msufOff.SetText then msufOff:SetText("Scaling OFF") end
            if fs.SetTextColor then fs:SetTextColor(1.0, 0.2, 0.2, 1.0) end -- red
        else
            if msufOff.SetText then msufOff:SetText("Scaling ON") end
            if fs.SetTextColor then fs:SetTextColor(0.2, 1.0, 0.2, 1.0) end -- green
        end
    end

    local msufReset = UI_Button(parent, "Reset", resetW, 18, "TOPLEFT", msufSlider, "BOTTOMLEFT", 0, -6, function()
        MSUF_EnableScalingSilently()

        -- Reset GLOBAL UI scale to 100% (custom)
        local scale = 1.0
        MSUF_SaveGlobalPreset("custom", scale)
        MSUF_SetGlobalUiScale(scale, true)

        MSUF_SetSliderValueSilent(100)

        if msufValue and msufValue.SetText then
            msufValue:SetText("100%")
        end
        if api and api.Refresh then api.Refresh() end
    end)

    local offW = (isWide and (isXL and 164 or 140)) or (isXL and 150 or 120)
    msufOff = UI_Button(parent, "Scaling OFF", offW, 18, "LEFT", msufReset, "RIGHT", 8, 0, function()
        local g = MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
        local isDisabled = g and g.disableScaling

        if isDisabled then
            -- Turn scaling back ON (no forced reload; picking a preset still reloads as before)
            if _G and _G.MSUF_SetScalingDisabled then
                _G.MSUF_SetScalingDisabled(false, true)
            else
                if g then g.disableScaling = false end
            end
            if api and api.Refresh then api.Refresh() end
            return
        end

        -- Turn scaling fully OFF (Global + MSUF-only), then reload (combat-safe)
        if _G and _G.MSUF_SetScalingDisabled then
            _G.MSUF_SetScalingDisabled(true, false)
        else
            -- Fallback (shouldn't happen): hard reset best-effort
            MSUF_ResetGlobalUiScale(true)
            MSUF_SetSavedMsufScale(1.0)
            MSUF_ApplyMsufScale(1.0)
            if g then
                g.disableScaling = true
                g.globalUiScalePreset = "auto"
                g.globalUiScaleValue = nil
            end
        end

        -- Keep UI controls in sync immediately.
        MSUF_SetSliderValueSilent(100)
        if api and api.Refresh then api.Refresh() end

        MSUF_RequestReloadSafe()
    end)

    MSUF_SkinDashboardButton(msufReset)
    MSUF_SkinDashboardButton(msufOff)

    if MSUF_AddTooltip then
        MSUF_AddTooltip(msufReset, "Reset UI Scale", "Resets global UI scale back to 100% (custom).")
        MSUF_AddTooltip(msufOff, "Disable ALL MSUF scaling", "Turns off all scaling MSUF applies (global UI scale + MSUF-only scale), then reloads your UI. Blizzard handles scaling.")
        MSUF_AddTooltip(msufSlider, "UI Scale (Global)", "Scales the entire WoW UI (UIParent). 100% = 1.0, 10% = 0.10. This sets the preset to Custom.")
    end

    msufSlider:SetScript("OnValueChanged", function(self, value)
        if self._msufIgnore then return end

        MSUF_EnableScalingSilently()

        local pct = tonumber(value) or 100
        pct = math.floor(pct + 0.5)
        pct = clamp(pct, 10, 100)

        local scale = pct / 100
        MSUF_SaveGlobalPreset("custom", scale)
        MSUF_SetGlobalUiScale(scale, true)

        if msufValue and msufValue.SetText then
            msufValue:SetText(string.format("%d%%", pct))
        end
        if api and api.Refresh then api.Refresh() end
    end)
    function api.Refresh()
        -- UI Scale slider (global)
        local g = MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
        local preset = g and g.globalUiScalePreset
        local disabled = g and g.disableScaling

        local desired
        if disabled then
            desired = MSUF_GetCurrentGlobalUiScale() or 1.0
        else
            if preset == "1080p" then
                desired = UI_SCALE_1080
            elseif preset == "1440p" then
                desired = UI_SCALE_1440
            elseif preset == "custom" and g and g.globalUiScaleValue then
                desired = tonumber(g.globalUiScaleValue)
            else
                desired = MSUF_GetCurrentGlobalUiScale() or 1.0
            end
        end

        local pct = clamp(math.floor((tonumber(desired) or 1.0) * 100 + 0.5), 10, 100)
        MSUF_SetSliderValueSilent(pct)
        if msufValue and msufValue.SetText then
            msufValue:SetText(string.format("%d%%", pct))
        end



        -- Global scale (UIParent scale)
        local cur = MSUF_GetCurrentGlobalUiScale()
        if cur then
            globalCur:SetText(string.format("Current: %.3f", cur))
        else
            globalCur:SetText("Current: ?")
        end

        
-- Highlight the active global preset button (matches the left-nav selection style)
        local g = MSUF_EnsureGeneral and MSUF_EnsureGeneral() or nil
        local preset = g and g.globalUiScalePreset
        local disabled = g and g.disableScaling

        if disabled then
            -- When Scaling OFF is active, do NOT highlight Auto (or any preset).
            if btn1080 and btn1080._msufSetSelected then btn1080:_msufSetSelected(false) end
            if btn1440 and btn1440._msufSetSelected then btn1440:_msufSetSelected(false) end
            if btnAuto and btnAuto._msufSetSelected then btnAuto:_msufSetSelected(false) end
        else
            if btn1080 and btn1080._msufSetSelected then btn1080:_msufSetSelected(preset == "1080p") end
            if btn1440 and btn1440._msufSetSelected then btn1440:_msufSetSelected(preset == "1440p") end
            if btnAuto and btnAuto._msufSetSelected then btnAuto:_msufSetSelected((preset == "auto") or (preset == nil)) end
        end

        -- Scaling toggle visuals (green = ON, red = OFF)
        MSUF_SetScalingToggleVisual(disabled and true or false)

        -- Optional selection glow only when OFF (acts as the "active" state)
        if msufOff and msufOff._msufSetSelected then
            msufOff:_msufSetSelected(disabled and true or false)
        end
    end


    -- Dynamic layout (prevents overlap when the window is narrower / scaled).
    -- We size the segmented buttons + slider based on the parent width.
    if not parent.__MSUF_ToolsLayoutHooked then
        parent.__MSUF_ToolsLayoutHooked = true

        local function Layout()
            local pw = (parent.GetWidth and parent:GetWidth()) or 0
            if not pw or pw <= 1 then return end

            -- Parent padding budget (matches how we place the controls)
            local avail = pw - 20
            -- avail is based on the current width; never force a larger minimum (prevents overlap)
            if btn1080 and btn1080.SetWidth and btn1440 and btnAuto then
                local wEach = math.floor((avail - 16) / 3)
                if wEach < 1 then wEach = 1 end
                btn1080:SetWidth(wEach)
                btn1440:SetWidth(wEach)
                btnAuto:SetWidth(wEach)
            end

            if msufSlider and msufSlider.SetWidth then
                local valueW = (opts and opts.showValue) and 60 or 0
                local sliderW = avail - valueW - 8
                if sliderW < 1 then sliderW = 1 end
                msufSlider:SetWidth(sliderW)
            end

            -- Keep the big "Scaling OFF" button inside the box on narrow widths.
            if msufOff and msufOff.SetWidth and msufReset and msufReset.GetWidth then
                local rw = msufReset:GetWidth() or resetW
                local ow = avail - rw - 8
                if ow < 90 then ow = 90 end
                if ow > 260 then ow = 260 end
                msufOff:SetWidth(ow)
            end
        end

        api.Layout = Layout

        if parent.HookScript then
            parent:HookScript("OnShow", function() if C_Timer and C_Timer.After then C_Timer.After(0, Layout) else Layout() end end)
            parent:HookScript("OnSizeChanged", function() if C_Timer and C_Timer.After then C_Timer.After(0, Layout) else Layout() end end)
        end

        Layout()
    elseif api.Layout then
        api.Layout()
    end

    api.Refresh()
    return api
end

-- ------------------------------------------------------------
-- Full options mirroring (robust attach/detach)
-- ------------------------------------------------------------
local function MSUF_ShowHideForLazy(panel, builtKey)
    if not panel then return end
    if panel.__MSUF_LazyBuildHooked and builtKey and not panel[builtKey] then
        panel:Show()
        panel:Hide()
    end
end

local function MSUF_EnsureMainOptionsPanelBuilt()
    MSUF_SafeCall(EnsureDB)
    MSUF_SafeCall(_G and _G.MSUF_RegisterOptionsCategoryLazy)
    MSUF_SafeCall(_G and _G.CreateOptionsPanel)

    local p = _G and _G.MSUF_OptionsPanel
    if not p then return nil end

    MSUF_ShowHideForLazy(p, "__MSUF_FullBuilt")
    return p
end

local function MSUF_GetMainSettingsCategory()
    return (_G and _G.MSUF_SettingsCategory) or (ns and ns.MSUF_MainCategory)
end

local function MSUF_EnsureMainSettingsCategory()
    local cat = MSUF_GetMainSettingsCategory()
    if not cat then
        MSUF_SafeCall(_G and _G.MSUF_RegisterOptionsCategoryLazy)
        cat = MSUF_GetMainSettingsCategory()
    end
    return cat
end

local SETTINGS_PANEL_DEFS = {
    colors = {
        full = "MSUF_RegisterColorsOptions_Full",
        fallback = "MSUF_RegisterColorsOptions",
        globals = { "MSUF_ColorsPanel", "MSUF_ColorsOptionsPanel" },
        builtKey = "__MSUF_ColorsBuilt",
    },
    auras2 = {
        full = "MSUF_RegisterAurasOptions_Full",
        fallback = "MSUF_RegisterAurasOptions",
        globals = { "MSUF_AurasPanel", "MSUF_AurasOptionsPanel" },
        builtKey = "__MSUF_AurasBuilt",
    },
    gameplay = {
        full = "MSUF_RegisterGameplayOptions_Full",
        fallback = "MSUF_RegisterGameplayOptions",
        globals = { "MSUF_GameplayPanel", "MSUF_GameplayOptionsPanel" },
        builtKey = "__MSUF_GameplayBuilt",
    },
}

local function MSUF_FindFirstGlobal(nameList)
    if not _G or type(nameList) ~= "table" then return nil end
    for i = 1, #nameList do
        local k = nameList[i]
        local obj = _G[k]
        if obj then return obj end
    end
    return nil
end

local function MSUF_EnsureSubOptionsPanelBuilt(kind)
    local def = SETTINGS_PANEL_DEFS[kind]
    if not def then return nil end

    local cat = MSUF_EnsureMainSettingsCategory()
    if not cat then return nil end

    if ns then
        local fn = ns[def.full]
        if type(fn) == "function" then
            pcall(fn, cat)
        else
            fn = ns[def.fallback]
            if type(fn) == "function" then
                pcall(fn, cat)
            end
        end
    end

    local p = MSUF_FindFirstGlobal(def.globals)
    MSUF_ShowHideForLazy(p, def.builtKey)
    return p
end

local function MSUF_EnsureColorsPanelBuilt()
    return MSUF_EnsureSubOptionsPanelBuilt("colors")
end

local function MSUF_EnsureAuras2PanelBuilt()
    return MSUF_EnsureSubOptionsPanelBuilt("auras2")
end

local function MSUF_EnsureGameplayPanelBuilt()
    return MSUF_EnsureSubOptionsPanelBuilt("gameplay")
end

local function MSUF_EnsureModulesPanelBuilt()
    if _G.MSUF_ModulesMirrorPanel and _G.MSUF_ModulesMirrorPanel.__MSUF_ModulesBuilt then
        return _G.MSUF_ModulesMirrorPanel
    end

    local p = CreateFrame("Frame", "MSUF_ModulesMirrorPanel", UIParent)
    _G.MSUF_ModulesMirrorPanel = p
    p.__MSUF_ModulesBuilt = true
    -- This panel is only meant to exist inside the Flash Menu window.
    -- If it remains "shown" on UIParent, it can cover the entire screen and make the UI feel "stuck".
    -- Mark it as mirror-only and keep it hidden unless explicitly attached.
    p.__MSUF_MirrorNoRestoreShow = true

    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Prevent the default shown-state from capturing clicks outside the Flash Menu.
    if p.Hide then p:Hide() end

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Modules")

    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText("Optional MSUF modules and UI styling (MSUF only).")

    if type(_G.MSUF_ApplyMidnightBackdrop) == "function" then
        pcall(_G.MSUF_ApplyMidnightBackdrop, p, 0.96)
    end
    if type(_G.MSUF_SkinTitle) == "function" then pcall(_G.MSUF_SkinTitle, title) end
    if type(_G.MSUF_SkinMuted) == "function" then pcall(_G.MSUF_SkinMuted, sub) end

    -- Style toggle (MSUF-only skinning)
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -14)
    if cb.Text then
        cb.Text:SetText("Enable MSUF Style")
        if type(_G.MSUF_SkinText) == "function" then pcall(_G.MSUF_SkinText, cb.Text) end
    end

    local note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 28, -6)
    note:SetText("Disabling may require /reload to fully remove existing styling.")
    if type(_G.MSUF_SkinMuted) == "function" then pcall(_G.MSUF_SkinMuted, note) end

    local function GetEnabled()
        if type(_G.MSUF_StyleIsEnabled) == "function" then
            local ok, v = pcall(_G.MSUF_StyleIsEnabled)
            if ok then return v and true or false end
        end
        if _G.MSUF_DB and _G.MSUF_DB.general then
            return _G.MSUF_DB.general.styleEnabled ~= false
        end
        return true
    end

    local function SetEnabled(v)
        if type(_G.MSUF_SetStyleEnabled) == "function" then
            pcall(_G.MSUF_SetStyleEnabled, v and true or false)
        else
            if _G.MSUF_DB and _G.MSUF_DB.general then
                _G.MSUF_DB.general.styleEnabled = v and true or false
            end
        end
    end

    cb:SetScript("OnShow", function() cb:SetChecked(GetEnabled()) end)
    cb:SetScript("OnClick", function(self) SetEnabled(self:GetChecked()) end)

-- Rounded Unitframes module (superellipse mask)
local rb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
rb:SetPoint("TOPLEFT", note, "BOTTOMLEFT", -28, -12)
if rb.Text then
    rb.Text:SetText("Rounded unitframes")
    if type(_G.MSUF_SkinText) == "function" then pcall(_G.MSUF_SkinText, rb.Text) end
end
rb.tooltipText = "Round MSUF unitframes by masking HP/Power/Absorb bars and backgrounds with the superellipse mask."

local function GetRoundedEnabled()
    if _G.MSUF_DB and _G.MSUF_DB.general then
        return _G.MSUF_DB.general.roundedUnitframes == true
    end
    return false
end

local function SetRoundedEnabled(v)
    if _G.MSUF_DB and _G.MSUF_DB.general then
        _G.MSUF_DB.general.roundedUnitframes = v and true or false
    end
    if type(_G.MSUF_ApplyModules) == "function" then
        pcall(_G.MSUF_ApplyModules)
    end
end

rb:SetScript("OnShow", function() rb:SetChecked(GetRoundedEnabled()) end)
rb:SetScript("OnClick", function(self) SetRoundedEnabled(self:GetChecked()) end)


    return p
end

local function MSUF_SelectMainOptionsKey(key)
    local p = _G and _G.MSUF_OptionsPanel
    if not p then return end
    if type(MSUF_GetTabButtonHelpers) ~= "function" then return end

    local _, setKey = MSUF_GetTabButtonHelpers(p)
    if type(setKey) == "function" then
        setKey(key)
        if p.LoadFromDB then
            pcall(p.LoadFromDB, p)
        end
    end
end

local function MSUF_SelectCastbarSubPage(unitKey)
    if type(_G and _G.MSUF_SetActiveCastbarSubPage) == "function" then
        pcall(_G.MSUF_SetActiveCastbarSubPage, unitKey)
    elseif type(MSUF_SetActiveCastbarSubPage) == "function" then
        pcall(MSUF_SetActiveCastbarSubPage, unitKey)
    end

    local p = _G and _G.MSUF_OptionsPanel
    if p and p.LoadFromDB then
        pcall(p.LoadFromDB, p)
    end
end

local MIRROR_PAGES = {
    home     = { title = "Midnight Simple Unitframes (Release 1.70h2)", nav = "Dashboard", build = nil },
    main     = { title = "MSUF Options",  nav = "Options",  build = MSUF_EnsureMainOptionsPanelBuilt,
        select = function(subkey)
            if not subkey then return end

            -- Allow future structured deep-links (Phase 3+) without breaking Phase 2.
            if type(subkey) == "table" then
                local tab = subkey.tab or subkey.key or subkey.page
                if tab then
                    MSUF_SelectMainOptionsKey(tab)
                end
                local castSub = subkey.castbarSub or subkey.castbar or subkey.sub
                if tab == "castbar" and castSub then
                    MSUF_SelectCastbarSubPage(castSub)
                end
                return
            end

            if type(subkey) == "string" then
                MSUF_SelectMainOptionsKey(subkey)
            end
        end
    },

main     = { title = "MSUF Options",  nav = "Options",  build = MSUF_EnsureMainOptionsPanelBuilt,
        select = function(subkey)
            if not subkey then return end

            -- Allow future structured deep-links (Phase 3+) without breaking Phase 2.
            if type(subkey) == "table" then
                local tab = subkey.tab or subkey.key or subkey.page
                if tab then
                    MSUF_SelectMainOptionsKey(tab)
                end
                local castSub = subkey.castbarSub or subkey.castbar or subkey.sub
                if tab == "castbar" and castSub then
                    MSUF_SelectCastbarSubPage(castSub)
                end
                return
            end

            if type(subkey) == "string" then
                MSUF_SelectMainOptionsKey(subkey)
            end
        end
    },


    -- Unit Frames tree (Phase 4b)
    uf_player       = { title = "MSUF Player",           nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("player") end },
    uf_target       = { title = "MSUF Target",           nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("target") end },
    uf_targettarget = { title = "MSUF Target of Target", nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("targettarget") end },
    uf_focus        = { title = "MSUF Focus",            nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("focus") end },
    uf_boss         = { title = "MSUF Boss Frames",      nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("boss") end },
    uf_pet          = { title = "MSUF Pet",              nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("pet") end },

    -- Options tree (Phase 4b)
    opt_bars        = { title = "MSUF Bars",             nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("bars") end },
    opt_fonts       = { title = "MSUF Fonts",            nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("fonts") end },
    opt_auras       = { title = "MSUF Auras",            nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("auras") end },
    auras2         = { title = "MSUF Auras 2.0",        nav = nil, build = MSUF_EnsureAuras2PanelBuilt },
    opt_castbar     = { title = "MSUF Castbar",          nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("castbar") end },
    opt_misc        = { title = "MSUF Miscellaneous",    nav = nil, build = MSUF_EnsureMainOptionsPanelBuilt, select = function() MSUF_SelectMainOptionsKey("misc") end },
    opt_colors      = { title = "MSUF Colors",           nav = nil, build = MSUF_EnsureColorsPanelBuilt },
    -- Phase 2: low-risk shortcuts into the main panel (same underlying panel, just pre-select a tab)
    castbar  = { title = "MSUF Castbar",  nav = "nil",  build = MSUF_EnsureMainOptionsPanelBuilt,
        select = function(subkey)
            MSUF_SelectMainOptionsKey("castbar")
            if subkey and subkey ~= "" then
                -- optional: castbar subpage (player/target/focus/boss)
                MSUF_SelectCastbarSubPage(subkey)
            end
        end
    },
    profiles = { title = "MSUF Profiles", nav = "nil", build = MSUF_EnsureMainOptionsPanelBuilt,
        select = function()
            MSUF_SelectMainOptionsKey("profiles")
        end
    },

    colors   = { title = "MSUF Colors",   nav = "nil",   build = MSUF_EnsureColorsPanelBuilt },
    gameplay = { title = "MSUF Gameplay", nav = "nil", build = MSUF_EnsureGameplayPanelBuilt },
    modules  = { title = "MSUF Modules", nav = "nil", build = MSUF_EnsureModulesPanelBuilt },
}

local function MSUF_GetMirrorPageInfo(key)
    return MIRROR_PAGES and key and MIRROR_PAGES[key] or nil
end

local function MSUF_NormalizeMirrorKey(key, allowHome)
    key = key or (allowHome and "home" or "main")

    if allowHome and key == "home" then
        return "home"
    end

    local info = MSUF_GetMirrorPageInfo(key)
    if info and key ~= "home" then
        return key
    end

    return allowHome and "home" or "main"
end

local function MSUF_GetPanelForKey(key)
    key = MSUF_NormalizeMirrorKey(key, false)

    local info = MSUF_GetMirrorPageInfo(key) or MSUF_GetMirrorPageInfo("main")
    local builder = info and info.build

    if type(builder) == "function" then
        return builder()
    end
    return nil
end

local MSUF_MirrorSetHeaderHidden

local function MSUF_DetachMirroredPanel(panel)
    if not panel or not panel.__MSUF_MirrorActive then
        return
    end

    -- Restore any header text we hid while mirrored
    MSUF_MirrorSetHeaderHidden(panel, false)

    -- Restore scroll/expanded state (captured on attach)
    if panel.__MSUF_MirrorState then
        MSUF_RestorePanelState(panel, panel.__MSUF_MirrorState)
    end

    -- Fully restore original parent/points/scale so the panel doesn't keep rendering behind other pages.
    local orig = panel.__MSUF_MirrorOrig
    if orig then
        if panel.Hide then pcall(panel.Hide, panel) end

        if panel.SetScale and orig.scale then
            pcall(panel.SetScale, panel, orig.scale)
        end
        if panel.SetFrameStrata and orig.strata then
            pcall(panel.SetFrameStrata, panel, orig.strata)
        end
        if panel.SetFrameLevel and orig.level then
            pcall(panel.SetFrameLevel, panel, orig.level) end

        if panel.SetParent and orig.parent then
            pcall(panel.SetParent, panel, orig.parent)
        end

        if panel.ClearAllPoints then
            pcall(panel.ClearAllPoints, panel)
        end

        if panel.SetPoint and orig.points and #orig.points > 0 then
            for i = 1, #orig.points do
                local pt = orig.points[i]
                if pt and pt[1] then
                    pcall(panel.SetPoint, panel, pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
        end

        if orig.shown and not panel.__MSUF_MirrorNoRestoreShow and panel.Show then
            pcall(panel.Show, panel)
        end
    else
        -- Fallback: at least hide it so it can't show through.
        if panel.Hide then pcall(panel.Hide, panel) end
    end

    panel.__MSUF_MirrorActive = nil
    panel.__MSUF_MirrorState = nil
end

MSUF_MirrorSetHeaderHidden = function(panel, hidden)
    if not panel then return end

    if hidden then
        if panel.__MSUF_MirrorHiddenHeader then return end
        panel.__MSUF_MirrorHiddenHeader = {}

        -- NOTE: This can run on large Settings panels.
        -- It needs to be efficient and avoid "script ran too long" errors.
        -- Fast path: if we already discovered header targets for this panel once, just hide them.
        local targets = panel.__MSUF_MirrorHeaderTargets
        if type(targets) == "table" and #targets > 0 then
            for i = 1, #targets do
                local r = targets[i]
                if r then
                    panel.__MSUF_MirrorHiddenHeader[r] = (r.IsShown and r:IsShown()) and 1 or 0
                    if r.Hide then r:Hide() end
                end
            end
            return
        end

        -- Lazy-init target cache.
        if type(targets) ~= "table" then
            targets = {}
            panel.__MSUF_MirrorHeaderTargets = targets
        end

        -- Cancel any prior scan (defensive).
        if panel.__MSUF_MirrorHeaderScanToken then
            panel.__MSUF_MirrorHeaderScanToken = nil
            panel.__MSUF_MirrorHeaderScanState = nil
        end

        local function IsHeaderText(t)
            if type(t) ~= "string" or t == "" then return false end
            local tl = string.lower(t)
            return string.find(tl, "midnight simple unit frames", 1, true)
                or string.find(tl, "beta version", 1, true)
                or string.find(tl, "early version", 1, true)
                or string.find(tl, "thank you for using", 1, true)
        end

        local function ScanChunk()
            -- Abort if we got unhidden/detached mid-scan.
            if not panel.__MSUF_MirrorHiddenHeader then
                panel.__MSUF_MirrorHeaderScanToken = nil
                panel.__MSUF_MirrorHeaderScanState = nil
                return
            end

            local token = panel.__MSUF_MirrorHeaderScanToken
            if not token then
                return
            end

            local st = panel.__MSUF_MirrorHeaderScanState
            if type(st) ~= "table" then
                st = {
                    stack = { panel },
                    sp = 1,
                    nodes = 0,
                    maxNodes = 450, -- hard safety cap; we only need a few header FontStrings
                }
                panel.__MSUF_MirrorHeaderScanState = st
            end

            local debugprofilestop = debugprofilestop
            local t0 = debugprofilestop and debugprofilestop() or nil
            local budgetMs = 1.0 -- tiny time slice to avoid "script ran too long"

            local stack = st.stack
            local sp = st.sp or 0
            local nodes = st.nodes or 0
            local maxNodes = st.maxNodes or 450

            while sp > 0 do
                if t0 and (debugprofilestop() - t0) >= budgetMs then
                    break
                end

                local frame = stack[sp]
                stack[sp] = nil
                sp = sp - 1
                if frame then
                    nodes = nodes + 1
                    if nodes > maxNodes then
                        break
                    end

                    -- Regions (FontStrings)
                    if frame.GetRegions then
                        local regions = { frame:GetRegions() }
                        for i = 1, #regions do
                            local r = regions[i]
                            if r and r.GetObjectType and r:GetObjectType() == "FontString" and r.GetText then
                                local t = r:GetText()
                                if IsHeaderText(t) then
                                    panel.__MSUF_MirrorHiddenHeader[r] = (r.IsShown and r:IsShown()) and 1 or 0
                                    if r.Hide then r:Hide() end
                                    targets[#targets + 1] = r
                                    -- We typically only have a handful; no need to keep scanning forever.
                                    if #targets >= 6 then
                                        nodes = maxNodes + 1
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- Children
                    if frame.GetChildren then
                        local children = { frame:GetChildren() }
                        for i = 1, #children do
                            local c = children[i]
                            if c then
                                sp = sp + 1
                                stack[sp] = c
                            end
                        end
                    end
                end
            end

            st.sp = sp
            st.nodes = nodes

            -- If there's more to scan, yield and continue next frame.
            if sp > 0 and nodes <= maxNodes and panel.__MSUF_MirrorHiddenHeader and panel.__MSUF_MirrorHeaderScanToken == token then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, ScanChunk)
                end
                return
            end

            -- Done (or capped). Cleanup scan state.
            panel.__MSUF_MirrorHeaderScanToken = nil
            panel.__MSUF_MirrorHeaderScanState = nil
        end

        -- Kick off the time-sliced scan.
        panel.__MSUF_MirrorHeaderScanToken = tostring(GetTime and GetTime() or math.random())
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ScanChunk)
        else
            -- No timer API; do a minimal one-shot scan to avoid infinite work.
            ScanChunk()
        end
    else
        local st = panel.__MSUF_MirrorHiddenHeader
        if not st then return end

        -- If a scan is still pending, kill it.
        panel.__MSUF_MirrorHeaderScanToken = nil
        panel.__MSUF_MirrorHeaderScanState = nil

        panel.__MSUF_MirrorHiddenHeader = nil
        for r, wasShown in pairs(st) do
            if r and wasShown == 1 then
                if r.Show then r:Show() end
            end
        end
    end
end

local function MSUF_AttachMirroredPanel(panel, parent, activeKey)
    if not panel or not parent then return end

    -- Snapshot original panel layout the first time we mirror it, so we can fully restore it on detach.
    -- Without this, panels stay parented to the mirror host and will show through the Dashboard page.
    if not panel.__MSUF_MirrorOrig then
        local orig = {}
        orig.parent = (panel.GetParent and panel:GetParent()) or nil
        orig.scale  = (panel.GetScale and panel:GetScale()) or 1
        orig.strata = (panel.GetFrameStrata and panel:GetFrameStrata()) or nil
        orig.level  = (panel.GetFrameLevel and panel:GetFrameLevel()) or nil
        -- For mirror-only panels (custom frames that default to shown on UIParent),
        -- never restore the original shown-state on detach.
        if panel.__MSUF_MirrorNoRestoreShow then
            orig.shown = false
        else
            orig.shown  = (panel.IsShown and panel:IsShown()) and true or false
        end
        orig.points = {}
        if panel.GetNumPoints and panel.GetPoint then
            local n = panel:GetNumPoints() or 0
            for i = 1, n do
                local p, relTo, relPoint, xOfs, yOfs = panel:GetPoint(i)
                orig.points[i] = { p, relTo, relPoint, xOfs, yOfs }
            end
        end
        panel.__MSUF_MirrorOrig = orig
    end

    -- Capture per-attach state (fresh snapshot each time) to avoid drift.
    if not panel.__MSUF_MirrorActive then
        panel.__MSUF_MirrorState = MSUF_CapturePanelState(panel)
        panel.__MSUF_MirrorActive = true
    end

    if panel.SetParent then
        pcall(panel.SetParent, panel, parent)
    end
    if panel.ClearAllPoints then
        pcall(panel.ClearAllPoints, panel)
    end
    if panel.SetPoint then
        local cropY = 0
        -- Crop the main options panel (MSUF_OptionsPanel).
        -- In the mirror window we hide the big header text and dim the legacy top tab strips;
        -- without cropping, the reserved header/tab area turns into a large empty block at the top.
        if panel == (_G and _G.MSUF_OptionsPanel) then
            local deep = (type(activeKey) == "string" and activeKey ~= "main") and true or false
            cropY = deep and MSUF_MIRROR_DEEPLINK_CROP_Y or MSUF_MIRROR_MAIN_CROP_Y
            MSUF_MirrorSetHeaderHidden(panel, true)
        end
        pcall(panel.SetPoint, panel, "TOPLEFT", parent, "TOPLEFT", 0, cropY)
        pcall(panel.SetPoint, panel, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end

    -- Slightly shrink the mirrored real panel (home page stays full-size).
    if panel.SetScale then
        pcall(panel.SetScale, panel, MIRROR_PANEL_SCALE)
    end

    if panel.SetFrameStrata then
        pcall(panel.SetFrameStrata, panel, "DIALOG")
    end

    if panel.Show then
        pcall(panel.Show, panel)
    end

    if not panel.__MSUF_MirrorWhiteHooked and panel.HookScript then
        panel.__MSUF_MirrorWhiteHooked = true
        panel:HookScript("OnShow", function()
            MSUF_ApplyWhiteTextToFrame(panel)
            MSUF_ApplyFontBumpToFrame(panel, MIRRORED_PANEL_FONT_BUMP)
            MSUF_ApplyMidnightControlsToFrame(panel)
        end)
    end

    if panel.LoadFromDB then
        pcall(panel.LoadFromDB, panel)
    elseif panel.Refresh then
        pcall(panel.Refresh, panel)
    end

    -- Whiten yellow labels inside the mirrored panel + bump fonts for readability.
    MSUF_ApplyWhiteTextToFrame(panel)
    MSUF_ApplyFontBumpToFrame(panel, MIRRORED_PANEL_FONT_BUMP)
    MSUF_ApplyMidnightControlsToFrame(panel)
end


-- ------------------------------------------------------------
-- Standalone mirror layout fixes
-- ------------------------------------------------------------
-- (crop constants moved up near MIRROR_PANEL_SCALE)

-- In the real Blizzard/Settings container, some MSUF buttons are positioned using
-- offsets relative to the panel's bottom/legacy container height. When we mirror
-- the panels into the standalone window, that can push them into the content.
-- Fix: re-anchor the Castbar top buttons (Focus Kick + Castbar Edit Mode) to the
-- panel's TOPLEFT while the standalone window is open.
local function MSUF_Standalone_SetCastbarTopButtonsHidden(hidden)
    -- Standalone (slash menu) UX:
    --  - Keep Focus Kick visible (it's the only navigation into Focus Kick options).
    --  - Hide the "Castbar Edit Mode: ON/OFF" info/button here (requested), because it is
    --    redundant/noisy in the slash menu context.
    -- We still capture/restore anchors so the real Options UI remains unchanged.

    local panel    = _G and _G.MSUF_OptionsPanel
    local editBtn  = _G and _G["MSUF_CastbarEditModeButton"]
    local focusBtn = _G and _G["MSUF_CastbarFocusButton"]

    local function Capture(btn)
        if not btn or btn.__msufStandaloneAnchorBackup then return end
        local st = {}
        st.parent = (btn.GetParent and btn:GetParent()) or nil
        st.shown  = (btn.IsShown and btn:IsShown()) and true or false
        st.points = {}
        if btn.GetNumPoints and btn.GetPoint then
            local n = btn:GetNumPoints() or 0
            for i = 1, n do
                local pnt, relTo, relPoint, xOfs, yOfs = btn:GetPoint(i)
                st.points[i] = { pnt, relTo, relPoint, xOfs, yOfs }
            end
        end
        btn.__msufStandaloneAnchorBackup = st
    end

    local function Restore(btn)
        if not btn then return end
        local st = btn.__msufStandaloneAnchorBackup
        if not st then return end
        btn.__msufStandaloneAnchorBackup = nil

        if st.parent and btn.SetParent then
            pcall(btn.SetParent, btn, st.parent)
        end

        if btn.ClearAllPoints then
            pcall(btn.ClearAllPoints, btn)
        end
        if btn.SetPoint and st.points then
            for i = 1, #st.points do
                local pt = st.points[i]
                if pt and pt[1] then
                    pcall(btn.SetPoint, btn, pt[1], pt[2], pt[3], pt[4], pt[5])
                end
            end
        end

        if st.shown then
            if btn.Show then pcall(btn.Show, btn) end
        else
            if btn.Hide then pcall(btn.Hide, btn) end
        end
    end

    if hidden then
        -- Anchor to a stable TOPLEFT reference so it doesn't drift with the mirrored panel crop/scale.
        Capture(focusBtn)
        Capture(editBtn)

        -- Focus Kick: always visible + stable anchor.
        if panel and focusBtn and focusBtn.ClearAllPoints and focusBtn.SetPoint then
            if focusBtn.SetParent then pcall(focusBtn.SetParent, focusBtn, panel) end
            if focusBtn.Show then pcall(focusBtn.Show, focusBtn) end
            pcall(focusBtn.ClearAllPoints, focusBtn)
            -- Keep this in the visible area even with the mirror header crop.
            pcall(focusBtn.SetPoint, focusBtn, "TOPLEFT", panel, "TOPLEFT", 16, -150)
        end

        -- Castbar Edit Mode info/button: hide in slash menu.
        if editBtn and editBtn.Hide then
            pcall(editBtn.Hide, editBtn)
        end
    else
        Restore(editBtn)
        Restore(focusBtn)
    end
end
-- Phase 3 (minimal-risk UX): when the left rail is used as the primary navigation,
-- the big "legacy" top tab strips inside the MAIN options panel are visually distracting
-- on deep-linked pages like Castbar / Profiles.
-- We *do not* re-anchor anything (risk), we only dim + disable mouse on those buttons,
-- and restore exactly when returning to the full Options page.
local _MSUF_LEGACY_TAB_TEXTS = {
    -- Row 1 (unit tabs)
    ["Player"] = true,
    ["Target"] = true,
    ["Target of Target"] = true,
    ["Focus"] = true,
    ["Boss Frames"] = true,
    ["Pet"] = true,
    -- Row 2 (section tabs)
    ["Bars"] = true,
    ["Fonts"] = true,
    ["Auras"] = true,
    ["Castbar"] = true,
    ["Miscellaneous"] = true,
    ["Profiles"] = true,
    -- Extra
    ["Focus Kick"] = true,

    -- (defensive) German client strings / mixed locales
    ["Spieler"] = true,
    ["Ziel"] = true,
    ["Ziel des Ziels"] = true,
    ["Fokus"] = true,
    ["Boss"] = true,
    ["Begleiter"] = true,
    ["Leisten"] = true,
    ["Schrift"] = true,
    ["Stärkungszauber"] = true,
    ["Zauberleiste"] = true,
    ["Verschiedenes"] = true,
    ["Profile"] = true,
}

local function MSUF_SetLegacyTabStripDimmed(panel, dim)
    if not panel or not panel.GetChildren then return end

    -- Only applies to the MAIN options panel; other panels do not have this strip.
    if panel ~= (_G and _G.MSUF_OptionsPanel) then
        return
    end

    if dim then
        if panel.__MSUF_LegacyTabsDimmed then return end
        panel.__MSUF_LegacyTabsDimmed = true
        panel.__MSUF_LegacyTabsDimState = panel.__MSUF_LegacyTabsDimState or {}

        local q = { panel }
        local seen = {}
        local safety = 0
        while #q > 0 do
            local f = table.remove(q)
            if f and not seen[f] then
                seen[f] = true
                safety = safety + 1
                if safety > 6000 then break end

                -- Dim clickable tab buttons by their label text
                if f.GetText and f.EnableMouse and f.GetAlpha and f.SetAlpha then
                    local ok, t = pcall(f.GetText, f)
                    local nm = f.GetName and f:GetName() or nil
                    if ok and t and _MSUF_LEGACY_TAB_TEXTS[t] and nm ~= "MSUF_CastbarFocusButton" then
                        if not panel.__MSUF_LegacyTabsDimState[f] then
                            panel.__MSUF_LegacyTabsDimState[f] = {
                                alpha = f:GetAlpha(),
                                mouse = f:IsMouseEnabled() and true or false,
                            }
                        end
                        -- Keep layout, just make it feel "non-primary" on deep-linked pages
                        f:SetAlpha(0)
                        f:EnableMouse(false)
                    end
                end

                local children = { f:GetChildren() }
                for i = 1, #children do
                    q[#q + 1] = children[i]
                end
            end
        end

        return
    end

    -- restore
    if not panel.__MSUF_LegacyTabsDimmed then return end
    panel.__MSUF_LegacyTabsDimmed = nil

    local st = panel.__MSUF_LegacyTabsDimState
    if st then
        for btn, s in pairs(st) do
            if btn and btn.SetAlpha and btn.EnableMouse then
                if s and s.alpha ~= nil then
                    pcall(btn.SetAlpha, btn, s.alpha)
                end
                if s and s.mouse ~= nil then
                    pcall(btn.EnableMouse, btn, s.mouse)
                end
            end
        end
        -- keep table allocated, but clear keys
        for k in pairs(st) do st[k] = nil end
    end
end


-- Helper: treat both the Options-tree Castbar leaf ("opt_castbar") and the shortcut page ("castbar")
-- as the same "Castbar context" inside the standalone Slash/Flash menu.
local function MSUF_IsCastbarKey(k)
    return k == "castbar" or k == "opt_castbar"
end

-- Phase 4: Context sub-navigation (minimal risk).
-- Only used for the Castbar shortcut page to quickly jump to player/target/focus/boss castbar subpages.
local function MSUF_UpdateContextNav(activeKey)
    local rail = S.win and S.win._msufNavRail
    if not rail then return end

    local ctx = rail._msufContextFrame
    if not ctx then return end

    if not MSUF_IsCastbarKey(activeKey) then
        if ctx.Hide then ctx:Hide() end
        return
    end

    if ctx.Show then ctx:Show() end

    local sub = (S and S.mirror and S.mirror.currentSubKey)
    if type(sub) ~= "string" then sub = nil end

    local buttons = rail._msufContextButtons
    local hl = rail._msufContextHighlight
    local stripe = rail._msufContextStripe

    if hl then hl:Hide() end
    if stripe then stripe:Hide() end

    if not buttons then return end

    for k, btn in pairs(buttons) do
        if btn and btn.SetEnabled then
            btn:SetEnabled(true)
        end

        if k == sub and btn then
            if hl and hl.ClearAllPoints and hl.SetPoint then
                hl:ClearAllPoints()
                hl:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 2)
                hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 4, -2)
                hl:Show()
            end
            if stripe and stripe.ClearAllPoints and stripe.SetPoint then
                stripe:ClearAllPoints()
                stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", -4, 2)
                stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -4, -2)
                stripe:Show()
            end
        end
    end
end

local function MSUF_SwitchMirrorPage(key, subkey)
    key = MSUF_NormalizeMirrorKey(key, true)

    local function UpdateTitle(activeKey)
        if S.win and S.win._msufTitleFS and S.win._msufTitleFS.SetText then
            local info = MSUF_GetMirrorPageInfo(activeKey)
            S.win._msufTitleFS:SetText((info and info.title) or "MSUF Menu")
        end
    end

    local function UpdateNav(activeKey)
        if not (S.win and S.win._msufNavButtons) then return end

        local buttons = S.win._msufNavButtons

-- Choose a visible button to highlight.
-- If the active leaf is inside a collapsed tree, highlight the header instead.
local highlightKey = activeKey
do
    local b = buttons and buttons[activeKey]
    local visible = b and b.IsShown and b:IsShown()
    if not visible then
        if type(activeKey) == "string" then
            if activeKey:match("^uf_") then
                highlightKey = "hdr_unitframes"
            elseif activeKey:match("^opt_") then
                highlightKey = "hdr_options"
            elseif activeKey == "modules" then
                highlightKey = "hdr_modules"
            end
        end
    end
end

for k, btn in pairs(buttons) do
    if btn then
        -- Keep all nav buttons enabled so the skin doesn't fall into "disabled grey".
        if btn.SetEnabled then btn:SetEnabled(true) end

        btn._msufNavIsActive = (k == highlightKey)

        if btn._msufApplyNavState then
            btn:_msufApplyNavState(btn._msufNavIsActive, false)
        end
    end
end

MSUF_UpdateContextNav(activeKey)

    end

    -- HOME: our "mini main menu" page inside the full window
    if key == "home" then
        -- Ensure any previous deep-link dimming is restored when returning to the Menu.
        MSUF_SetLegacyTabStripDimmed(_G and _G.MSUF_OptionsPanel, false)

    -- If we are leaving the Castbar page inside the standalone window, restore the global Castbar buttons.
if S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey) and not MSUF_IsCastbarKey(key) then
    MSUF_Standalone_SetCastbarTopButtonsHidden(false)
end

    if S.mirror.currentPanel then
            MSUF_DetachMirroredPanel(S.mirror.currentPanel)
            S.mirror.currentPanel = nil
        end

        S.mirror.currentKey = "home"

        if S.mirror.homePanel then
            if S.mirror.homePanel.Show then S.mirror.homePanel:Show() end
            if S.mirror.homeToolsApi and S.mirror.homeToolsApi.Refresh then
                S.mirror.homeToolsApi.Refresh()
            end
        end

        UpdateTitle("home")
        UpdateNav("home")
        return
    end

    -- Non-home: hide the home panel if present
    if S.mirror.homePanel and S.mirror.homePanel.Hide then
        S.mirror.homePanel:Hide()
    end

    if S.mirror.currentKey == key and S.mirror.currentPanel and S.mirror.currentPanel.IsShown and S.mirror.currentPanel:IsShown() then
        -- Already visible on the same page: still apply Phase-2 deep-links (subkey) so
        -- Edit-Mode "Menu" can switch unit tabs/castbar subpages even if the Flash window is already open.
        do
            local info = MSUF_GetMirrorPageInfo(key)
            local sel = info and info.select
            local wantSub = subkey
            if wantSub == nil and S and S.mirror then
                wantSub = S.mirror.pendingSubKey
                S.mirror.pendingSubKey = nil
            end

            -- Track sub-selection for context highlight (used on Castbar shortcut page)
            if S and S.mirror then
                if MSUF_IsCastbarKey(key) and type(wantSub) == "string" and wantSub ~= "" then
                    S.mirror.currentSubKey = wantSub
                elseif not MSUF_IsCastbarKey(key) then
                    S.mirror.currentSubKey = nil
                end
            end

            if type(sel) == "function" and (wantSub ~= nil) then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function() pcall(sel, wantSub) end)
                    C_Timer.After(0.05, function() pcall(sel, wantSub) end)
                else
                    pcall(sel, wantSub)
                end
            end
        end

        UpdateTitle(key)
        UpdateNav(key)
        return
    end

    -- Leaving Castbar page: restore global Castbar top buttons (they were hidden in standalone).
    if S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey) and not MSUF_IsCastbarKey(key) then
        MSUF_Standalone_SetCastbarTopButtonsHidden(false)
    end

    if S.mirror.currentPanel then
        MSUF_DetachMirroredPanel(S.mirror.currentPanel)
        S.mirror.currentPanel = nil
    end

    S.mirror.currentKey = key
    S.mirror.currentPanel = MSUF_GetPanelForKey(key)

    if S.mirror.currentPanel and S.mirror.host then
        MSUF_AttachMirroredPanel(S.mirror.currentPanel, S.mirror.host, key)

        -- Force "midnight white" on yellow labels after attach (and again next tick for late-created children)
        MSUF_ApplyWhiteTextToFrame(S.mirror.currentPanel)
        MSUF_ApplyFontBumpToFrame(S.mirror.currentPanel, MIRRORED_PANEL_FONT_BUMP)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if S.mirror.currentPanel and S.mirror.currentPanel.__MSUF_MirrorActive then
                    MSUF_ApplyWhiteTextToFrame(S.mirror.currentPanel)
                    MSUF_ApplyFontBumpToFrame(S.mirror.currentPanel, MIRRORED_PANEL_FONT_BUMP)
                end
            end)
        end
    end


    -- Phase 2: apply per-page selection (deep-links) after attach.
    -- This enables MSUF_OpenPage('castbar','player'), MSUF_OpenPage('profiles'), etc.
    do
        local info = MSUF_GetMirrorPageInfo(key)
        local sel = info and info.select
        local wantSub = subkey
        if wantSub == nil and S and S.mirror then
            wantSub = S.mirror.pendingSubKey
            S.mirror.pendingSubKey = nil
        end

        -- Track sub-selection for context highlight (used on Castbar shortcut page)
        if S and S.mirror then
            if MSUF_IsCastbarKey(key) and type(wantSub) == "string" and wantSub ~= "" then
                S.mirror.currentSubKey = wantSub
            elseif not MSUF_IsCastbarKey(key) then
                S.mirror.currentSubKey = nil
            end
        end

        if type(sel) == "function" then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function() pcall(sel, wantSub) end)
                C_Timer.After(0.05, function() pcall(sel, wantSub) end)
            else
                pcall(sel, wantSub)
            end
        end
    end


    -- Standalone mirror fix: keep Castbar top buttons aligned like in Blizzard/Options
    if MSUF_IsCastbarKey(key) then
        -- Panel refresh can re-anchor these buttons AFTER attach, so run a few times.
        MSUF_Standalone_SetCastbarTopButtonsHidden(true)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end)
            C_Timer.After(0.05, function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end)
            C_Timer.After(0.15, function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end)
            C_Timer.After(0.30, function() MSUF_Standalone_SetCastbarTopButtonsHidden(true) end)
        end
    end

    if MSUF_IsCastbarKey(key) then
        -- Also hook the Castbar panel itself: it can re-run its internal layout on resize and
        -- re-anchor the Focus Kick button after our window-level hook.
        local p = S and S.mirror and S.mirror.currentPanel
        if p and p.HookScript and not p.__MSUF_FocusKickResizeHooked then
            p.__MSUF_FocusKickResizeHooked = true
            p:HookScript("OnSizeChanged", function()
                if S and S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey) then
                    local function repin()
                        if S and S.mirror and MSUF_IsCastbarKey(S.mirror.currentKey) then
                            MSUF_Standalone_SetCastbarTopButtonsHidden(true)
                        end
                    end
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, repin)
                        C_Timer.After(0.05, repin)
                        C_Timer.After(0.15, repin)
                        C_Timer.After(0.30, repin)
                    else
                        repin()
                    end
                end
            end)
        end
    end

    -- Hide legacy top tab strips inside the Main Options panel while using the Flash window
    MSUF_SetLegacyTabStripDimmed(_G and _G.MSUF_OptionsPanel, true)

    UpdateTitle(key)
    UpdateNav(key)
end

-- Build a unified left-side navigation rail (Menu/Options/Colors/Gameplay).
-- This replaces the old top-right tab row so navigation is always in the same place.
local function MSUF_BuildMirrorNavButtons(navParent, btnW, btnH)
    if not navParent then return {} end
    btnH = btnH or 24

    local padL = 2  -- moved left to align pills with rail (per UI screenshot)
    local padT = 10
    -- Extra right margin so the pill outline never touches the rail box border.
    -- (Needed especially at fractional UI scales like 0.64 where AA edges can visually "bleed".)
    local extraRight = 42
    local gap  = 8
    local indent = 10 -- slightly less indent so child pills also shift left

    local railW = navParent.GetWidth and navParent:GetWidth() or 150
    btnW = btnW or math.max(110, railW - (padL * 2) - extraRight)
    local hasTitle = not navParent._msufSkipNavTitle
    if hasTitle then

    
        local title = navParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", navParent, "TOPLEFT", padL, -padT)
        title:SetText("Navigation")
        MSUF_SkinTitle(title)
    
        local sub = navParent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
        sub:SetText("Quick access")
        MSUF_SkinMuted(sub)
        end

    -- Active selection highlight (positioned in UpdateNav)
    if not navParent._msufNavHighlight then
        local hl = navParent:CreateTexture(nil, "BACKGROUND")
        hl:SetTexture(MSUF_SUPERELLIPSE_TEX)
        hl:SetVertexColor(1, 1, 1, 0.06)
        hl:Hide()
        navParent._msufNavHighlight = hl

        local stripe = navParent:CreateTexture(nil, "BORDER")
        stripe:SetTexture("Interface/Buttons/WHITE8X8")
        stripe:SetVertexColor(0.18, 0.45, 1.00, 0.55)
        stripe:SetWidth(3)
        stripe:Hide()
        navParent._msufNavStripe = stripe
    end

    local function LeftJustify(b, leftPad)
        leftPad = leftPad or 12
        if b and b.GetFontString then
            local fs = b:GetFontString()
            if fs then
                if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
                -- Add inner padding so the UIPanelButtonTemplate left cap does not look like a "checkbox".
                if fs.ClearAllPoints and fs.SetPoint then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", b, "LEFT", leftPad, 0)
                    fs:SetPoint("RIGHT", b, "RIGHT", -8, 0)
                end
            end
        end
    end

    local out = {}
    local prev = sub

    -- Leaf helper
    local function AddLeaf(key, label, prefix)
        local b = UI_Button(navParent, tostring(label), btnW, btnH, "TOPLEFT", prev, "BOTTOMLEFT", 0, -gap, function()
            MSUF_SwitchMirrorPage(key)
        end)
        LeftJustify(b)
        MSUF_SkinNavButton(b, false, false)
        out[key] = b
        prev = b
        return b
    end

    -- Header helper (toggle open/closed). Uses ASCII + / - (no unicode triangles, avoids missing-glyph squares).
    local headers = navParent._msufTreeHeaders or {}
    navParent._msufTreeHeaders = headers

    local function AddHeader(headerKey, label, opened)
        local b = UI_Button(navParent, label, btnW, btnH, "TOPLEFT", prev, "BOTTOMLEFT", 0, -gap, function()
            headers[headerKey] = not headers[headerKey]
            if navParent._msufTreeReflow then navParent._msufTreeReflow() end
        end)
        LeftJustify(b)
        MSUF_SkinNavButton(b, true, false)
        headers[headerKey] = (headers[headerKey] ~= nil) and headers[headerKey] or opened
        prev = b
        return b
    end

    -- Indented leaf helper
    local function AddIndentedLeaf(key, label, prefix)
        -- Keep child rows *inside* the header width: shift right, but reduce width by the same indent.
        local w = math.max(40, (btnW or 0) - indent)
        local b = UI_Button(navParent, tostring(label), w, btnH, "TOPLEFT", prev, "BOTTOMLEFT", indent, -gap, function()
            MSUF_SwitchMirrorPage(key)
        end)
        LeftJustify(b, 10)
        MSUF_SkinNavButton(b, false, true)
        out[key] = b
        prev = b
        return b
    end

    -- Build
    AddLeaf("home", "Dashboard", "Menu")

    local hdrUF = AddHeader("unitframes", "- Unit Frames", true)
    out["hdr_unitframes"] = hdrUF
    local ufButtons = {
        AddIndentedLeaf("uf_player", "Player", "Unit Frames"),
        AddIndentedLeaf("uf_target", "Target", "Unit Frames"),
        AddIndentedLeaf("uf_targettarget", "Target of Target", "Unit Frames"),
        AddIndentedLeaf("uf_focus", "Focus", "Unit Frames"),
        AddIndentedLeaf("uf_boss", "Boss Frames", "Unit Frames"),
        AddIndentedLeaf("uf_pet", "Pet", "Unit Frames"),
    }

    local hdrOpt = AddHeader("options", "- Options", true)
    out["hdr_options"] = hdrOpt
    local optButtons = {
        AddIndentedLeaf("opt_bars", "Bars", "Options"),
        AddIndentedLeaf("opt_fonts", "Fonts", "Options"),
        -- Auras (legacy) intentionally hidden (Auras 2.0 replaces it)
        AddIndentedLeaf("auras2", "Auras 2.0", "Options"),
        AddIndentedLeaf("opt_castbar", "Castbar", "Options"),
        AddIndentedLeaf("opt_misc", "Miscellaneous", "Options"),
        AddIndentedLeaf("opt_colors", "Colors", "Options"),
    }


-- Gameplay (standalone, no tree)
AddLeaf("gameplay", "Gameplay", "Menu")

-- Modules tree (starts with Style)
local hdrModules = AddHeader("modules", "+ Modules", false)
out["hdr_modules"] = hdrModules
local modButtons = {
    AddIndentedLeaf("modules", "Style", "Modules"),
}
-- Standalone pages
AddLeaf("profiles", "Profiles", "Menu")

    -- Reflow/hide by header state
    navParent._msufTreeReflow = function()
        local y = -(padT + 2)
        -- Title/sub are fixed; we reposition buttons by walking from the first button.
        local first = navParent._msufFirstNavButton
        -- Build list in order
        local list = {}
            end

    -- Implement reflow (Lua-style)
    local function Reflow()
        local yOfs = hasTitle and - (padT + 26) or -padT
        local lowestBottomY = 0

        local function Place(btn, x)
            if not btn then return end
            if btn.ClearAllPoints and btn.SetPoint then
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", navParent, "TOPLEFT", padL + (x or 0), yOfs)
            end

            -- Track the lowest bottom edge (local navStack coords).
            -- This gives us a scale-independent, reliable minimum height
            -- so the last menu item (Profiles) never gets clipped.
            local bottomY = yOfs - btnH
            if bottomY < lowestBottomY then
                lowestBottomY = bottomY
            end

            yOfs = yOfs - (btnH + gap)
        end

        -- Dashboard
        Place(out["home"], 0)

        -- Unit Frames header
        if hdrUF then
            hdrUF:SetText((headers.unitframes and "- Unit Frames") or "+ Unit Frames")
            Place(hdrUF, 0)
        end
        for _, b in ipairs(ufButtons) do
            if headers.unitframes then
                if b.Show then b:Show() end
                Place(b, indent)
            else
                if b.Hide then b:Hide() end
            end
        end

        -- Options header
        if hdrOpt then
            hdrOpt:SetText((headers.options and "- Options") or "+ Options")
            Place(hdrOpt, 0)
        end
        for _, b in ipairs(optButtons) do
            if headers.options then
                if b.Show then b:Show() end
                Place(b, indent)
            else
                if b.Hide then b:Hide() end
            end
        end
        -- Gameplay (standalone)
        Place(out["gameplay"], 0)

        -- Modules header
        local hdrModules = out["hdr_modules"]
        if hdrModules then
            hdrModules:SetText((headers.modules and "- Modules") or "+ Modules")
            Place(hdrModules, 0)
        end
        for _, b in ipairs(modButtons or {}) do
            if headers.modules then
                if b.Show then b:Show() end
                Place(b, indent)
            else
                if b.Hide then b:Hide() end
            end
        end
-- Standalone leaf pages
        Place(out["profiles"], 0)

        -- Enforce a minimum window height so the last menu item (Profiles) is always visible.
        -- We compute this from the actual reflow layout (local coords), not from screen coords,
        -- so it doesn't break under custom UI scale / effective scale changes.
        do
            local function ApplyMinHeight()
                local navRail = navParent and navParent.GetParent and navParent:GetParent()
                if not navRail then return end
                local pad = 8

                -- Required navStack height (local coords): bottom of last placed button + small margin.
                local used = -lowestBottomY
                if used < 0 then used = 0 end
                local insideBottomMargin = 4
                local requiredNavStackH = used + insideBottomMargin

                -- Window chrome: difference between outer frame height and inner content height.
                local content = navRail.GetParent and navRail:GetParent()
                local win = content and content.GetParent and content:GetParent()
                if not win then return end

                local chromeH = 38
                if win.GetHeight and content and content.GetHeight then
                    local wh, ch = win:GetHeight(), content:GetHeight()
                    if wh and ch then
                        chromeH = (wh - ch)
                    end
                end

                -- Total minimum height: navStack + padding + chrome
                local overhead = (pad + pad)
                local minH = math.floor((requiredNavStackH + overhead + chromeH) + 0.5)

                -- Absolute safety floor (keeps host panels sane even if something goes odd)
                if minH < 520 then minH = 520 end

                win._msufMinH = minH

                local minW = win._msufMinW or 760
                local maxW = win._msufMaxW or 2200
                local maxH = win._msufMaxH or 1400
                if win.SetResizeBounds then
                    pcall(win.SetResizeBounds, win, minW, minH, maxW, maxH)
                elseif win.SetMinResize then
                    pcall(win.SetMinResize, win, minW, minH)
                end

                if win.GetHeight and win.SetHeight then
                    local curH = win:GetHeight()
                    if curH and curH < minH then
                        win:SetHeight(minH)
                    end
                end
            end

            if C_Timer and C_Timer.After then
                C_Timer.After(0, ApplyMinHeight)
                C_Timer.After(0.05, ApplyMinHeight)
            else
                ApplyMinHeight()
            end
        end

    end

    navParent._msufTreeReflow = Reflow
    Reflow()
    return out
end

local function MSUF_CreateOptionsWindow()

    if S.win then return S.win end

    local f = CreateFrame("Frame", "MSUF_StandaloneOptionsWindow", UIParent, "BackdropTemplate")
    f:SetSize(900, 650) -- slightly larger to avoid clipping/overlap in mirrored panels
    f:SetPoint("CENTER", UIParent, "CENTER", -60, 10)

    if f.SetClipsChildren then
        f:SetClipsChildren(false) -- defensive: avoid hard clipping when mirroring panels
    end
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    if f.SetClampRectInsets then
        f:SetClampRectInsets(8, 8, 8, 8)
    end
    if MSUF_RegisterEscClose then
        MSUF_RegisterEscClose(f)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    -- Allow the window to be resized by dragging the bottom-right corner (Windows-style)
    f:SetResizable(true)
    -- Resize bounds (Midnight/Beta: SetMinResize may not exist; prefer SetResizeBounds)
    do
        local minW, minH = 760, 560
        local maxW, maxH = 2200, 1400
        if f.SetResizeBounds then
            f:SetResizeBounds(minW, minH, maxW, maxH)
        elseif f.SetMinResize then
            f:SetMinResize(minW, minH)
        end
    
        -- store for manual grip resize (prevents first-drag jump on some clients)
        f._msufMinW, f._msufMinH, f._msufMaxW, f._msufMaxH = minW, minH, maxW, maxH
    end
    f._msufGeomKey = "full"
    -- Restore last saved window size/position (defaults match the old hardcoded values)
    if MSUF_LoadWindowGeometry then
        MSUF_LoadWindowGeometry(f, "full", 900, 650, "CENTER", -60, 10)
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if MSUF_SaveWindowGeometry then
            MSUF_SaveWindowGeometry(self, self._msufGeomKey or "full")
        end
    end)

    -- Bottom-right resize grip
    MSUF_AttachManualResizeGrip(f)

    MSUF_ApplyMidnightBackdrop(f, 1.0)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("MSUF Options")
    MSUF_SkinTitle(title)
    f._msufTitleFS = title

    
local close = UI_CloseButton(f, "TOPRIGHT", f, "TOPRIGHT", -4, -4)
    -- Secret/Taint-safe keyboard propagation:
    -- SetPropagateKeyboardInput can be protected in some contexts (especially combat).
    -- We avoid calling it during combat; instead we defer until PLAYER_REGEN_ENABLED.
    local function MSUF_SetPropagateKeyboardInputSafe(frame, enabled)
        if not frame or not frame.SetPropagateKeyboardInput then return end
        if type(InCombatLockdown) == "function" and InCombatLockdown() then
            frame._msufPendingPropagateKeyboard = enabled
            return
        end
        frame._msufPendingPropagateKeyboard = nil
        frame:SetPropagateKeyboardInput(enabled)
    end

    if not f._msufPropagateRegenFrame then
        local rf = CreateFrame("Frame")
        rf:RegisterEvent("PLAYER_REGEN_ENABLED")
        rf:SetScript("OnEvent", function()
            if f and f._msufPendingPropagateKeyboard ~= nil then
                if f:IsShown() then
                    MSUF_SetPropagateKeyboardInputSafe(f, f._msufPendingPropagateKeyboard)
                else
                    -- Window hidden: just clear pending to avoid stale state.
                    f._msufPendingPropagateKeyboard = nil
                end
            end
        end)
        f._msufPropagateRegenFrame = rf
    end

    -- Main content container (holds the navigation rail + the active page host)
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    content:SetScale(1.0)
    if content.SetClipsChildren then
        content:SetClipsChildren(false)
    end
    S.content = content

    -- Unified left navigation rail (replaces the old top-right tabs)
    local navRail = CreateFrame("Frame", nil, content, "BackdropTemplate")
    navRail:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    navRail:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
    navRail:SetWidth(150)
    MSUF_ApplyMidnightBackdrop(navRail, 0.22)
    f._msufNavRail = navRail

    -- Host area where pages are shown (home + mirrored Settings panels)
    local host = CreateFrame("Frame", nil, content)
    host:SetPoint("TOPLEFT", navRail, "TOPRIGHT", 8, 0)
    host:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    host:SetScale(1.0)
    if host.SetClipsChildren then
        host:SetClipsChildren(false)
    end
    f._msufMirrorHost = host


    -- Clipping container: lets us "crop" the top of mirrored panels without them spilling outside.
    local clip = CreateFrame("Frame", nil, host)
    clip:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    if clip.SetClipsChildren then
        clip:SetClipsChildren(true)
    end
    f._msufMirrorClipHost = clip

    -- Navigation buttons (tree)
    local navStack = CreateFrame("Frame", nil, navRail)
    navStack._msufSkipNavTitle = true
    local railW = navRail.GetWidth and navRail:GetWidth() or 150
    if navStack.SetWidth then navStack:SetWidth(math.max(80, railW - 16)) end
    f._msufNavStack = navStack

    f._msufNavButtons = MSUF_BuildMirrorNavButtons(navStack, 130, 22)
    do
        local pad = 8
        if navStack.ClearAllPoints then navStack:ClearAllPoints() end
        navStack:SetPoint("TOPLEFT", navRail, "TOPLEFT", pad, -pad)
        navStack:SetPoint("TOPRIGHT", navRail, "TOPRIGHT", -pad, -pad)
        navStack:SetPoint("BOTTOMLEFT", navRail, "BOTTOMLEFT", pad, pad)
        navStack:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", -pad, pad)
    end


    -- Home page
    -- (full-size "mini menu" shown first)
    local home = CreateFrame("Frame", nil, host, "BackdropTemplate")
    home:SetAllPoints(host)
    MSUF_ApplyMidnightBackdrop(home, 0.35)
    home:Hide()
    S.mirror.homePanel = home
    f._msufHomePanel = home

    MSUF_ApplyMidnightControlsToFrame(home)

    local homeTitle = home:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    homeTitle:SetPoint("TOPLEFT", 12, -10)
    homeTitle:SetText("Main Menu")
    MSUF_SkinTitle(homeTitle)

    local homeHint = home:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    homeHint:SetPoint("TOPLEFT", homeTitle, "BOTTOMLEFT", 0, -2)
    homeHint:SetText("Quick tools & UI scale (same content as /msuf options).")
    MSUF_SkinText(homeHint)

    -- Tip of the Day (cycles on every open of this Menu page) - subtle
    local tipBox = CreateFrame("Frame", nil, home)
    tipBox:SetPoint("TOPLEFT", home, "TOPLEFT", 12, -44)
    tipBox:SetPoint("TOPRIGHT", home, "TOPRIGHT", -12, -44)
    tipBox:SetHeight(22)

    local tipLabel = tipBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tipLabel:SetPoint("TOPLEFT", tipBox, "TOPLEFT", 0, 0)
    tipLabel:SetJustifyH("LEFT")
    tipLabel:SetJustifyV("TOP")
    tipLabel:SetAlpha(0.82)
    tipLabel:SetText("Tip:")
    MSUF_SkinMuted(tipLabel)

        local tipText = tipBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tipText:SetPoint("TOPLEFT", tipLabel, "TOPRIGHT", 6, 0)
    tipText:SetPoint("TOPRIGHT", tipBox, "TOPRIGHT", 0, 0)
    tipText:SetJustifyH("LEFT")
    tipText:SetJustifyV("TOP")
    tipText:SetAlpha(0.82)
    tipText:SetText("")
    MSUF_SkinMuted(tipText)
    MSUF_ForceItalicFont(tipText) -- italic only for the tip text (label stays normal)

    home._msufTipLabel = tipLabel
    home._msufTipText = tipText

    home:SetScript("OnShow", function(self)
        local tip = S.mirror.tipText
        if not tip then
            tip = _G.MSUF_GetNextTip()
            S.mirror.tipText = tip
        end
        if tip and self._msufTipText then
            self._msufTipText:SetText(tip)
            -- Re-apply subtle styling after any global font bump / skin call
            MSUF_ForceItalicFont(self._msufTipText)
            self._msufTipText:SetAlpha(0.82)
        end

        -- Refresh dashboard-selected states (scale preset buttons + Edit Mode toggle)
        if S and S.mirror and S.mirror.homeToolsApi and S.mirror.homeToolsApi.Refresh then
            pcall(S.mirror.homeToolsApi.Refresh)
        end
        local win = _G and _G.MSUF_StandaloneOptionsWindow
        local b = win and win._msufDashEditBtn
        if b and b._msufSetSelected then
            b:_msufSetSelected(MSUF_IsMSUFEditModeActive())
        end

        -- Status line + profile label (dashboard)
        local prof = (_G and _G.MSUF_ActiveProfile) or "Default"
        if self._msufProfileValue and self._msufProfileValue.SetText then
            self._msufProfileValue:SetText(prof)
        end
        if self._msufStatusLine and self._msufStatusLine.SetText then
            local edit = MSUF_IsMSUFEditModeActive() and "On" or "Off"
            local combat = (InCombatLockdown and InCombatLockdown()) and "In combat" or "Out of combat"
            self._msufStatusLine:SetText("Profile: " .. tostring(prof) .. "   •   Edit Mode: " .. edit .. "   •   " .. combat)
        end
    end)

-- Readability: bump text sizes for the home/menu page (and its children) once.
MSUF_ApplyFontBumpToFrame(home, MENU_FONT_BUMP)
MSUF_ForceItalicFont(tipText)

-- Status line (profile + Edit Mode + combat state)
local statusLine = home:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
statusLine:SetPoint("TOPLEFT", tipBox, "BOTTOMLEFT", 0, -6)
statusLine:SetPoint("TOPRIGHT", tipBox, "BOTTOMRIGHT", 0, -6)
statusLine:SetJustifyH("LEFT")
statusLine:SetJustifyV("TOP")
statusLine:SetAlpha(0.78)
statusLine:SetText("")
MSUF_SkinMuted(statusLine)
home._msufStatusLine = statusLine

-- Clean 2-column dashboard (responsive; no overlap at smaller window sizes)
local split = CreateFrame("Frame", nil, home)
split:SetPoint("TOPLEFT", home, "TOPLEFT", 12, -96)
split:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", -12, 14)

local colGap = 14

local colL = CreateFrame("Frame", nil, split)
colL:SetPoint("TOPLEFT", split, "TOPLEFT", 0, 0)
colL:SetPoint("BOTTOMLEFT", split, "BOTTOMLEFT", 0, 0)
colL:SetPoint("TOPRIGHT", split, "TOP", -(colGap/2), 0)
colL:SetPoint("BOTTOMRIGHT", split, "BOTTOM", -(colGap/2), 0)

local colR = CreateFrame("Frame", nil, split)
colR:SetPoint("TOPLEFT", split, "TOP", (colGap/2), 0)
colR:SetPoint("BOTTOMLEFT", split, "BOTTOM", (colGap/2), 0)
colR:SetPoint("TOPRIGHT", split, "TOPRIGHT", 0, 0)
colR:SetPoint("BOTTOMRIGHT", split, "BOTTOMRIGHT", 0, 0)

local function CreateCard(parent, titleText, anchorTo, yOff, skipTitle)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if anchorTo then
        card:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOff or -12)
        card:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, yOff or -12)
    else
        card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        card:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end
    MSUF_ApplyMidnightBackdrop(card, 0.18)

    if not skipTitle then
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText(titleText or "")
        MSUF_SkinTitle(title)
        card._msufTitle = title
    end
    return card
end

local function DashToggleEditMode()
    -- Prefer the canonical direct Edit Mode entry point (works even when unlinked from Blizzard Edit Mode).
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        local st = _G.MSUF_EditState
        local nextActive = true
        if st and st.active ~= nil then
            nextActive = not st.active
        end
        pcall(_G.MSUF_SetMSUFEditModeDirect, nextActive)
        return
    end

    -- Legacy fallbacks (older builds / compatibility)
    if type(_G.MSUF_ToggleEditMode) == "function" then
        pcall(_G.MSUF_ToggleEditMode)
    elseif type(_G.MSUF_EditMode_Toggle) == "function" then
        pcall(_G.MSUF_EditMode_Toggle)
    else
        MSUF_Print("Edit Mode function not found.")
    end
end

-- Confirm: Reset positions
local function MSUF_ShowResetPositionsConfirm()
    if InCombatLockdown and InCombatLockdown() then
        MSUF_Print("Cannot reset while in combat.")
        return
    end

    if not StaticPopupDialogs["MSUF_RESET_POS_CONFIRM"] then
        StaticPopupDialogs["MSUF_RESET_POS_CONFIRM"] = {
            text = "Reset MSUF frame positions now?\n\nThis resets MSUF frame positions + visibility to defaults for the ACTIVE profile.",
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
            OnAccept = function()
                if _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"] then
                    pcall(_G.SlashCmdList["MIDNIGHTSUF"], "reset")
                else
                    MSUF_Print("/msuf reset handler not found.")
                end
            end,
        }
    end

    StaticPopup_Show("MSUF_RESET_POS_CONFIRM")
end

-- Confirm: Factory reset (hard reset + reload)
local function MSUF_ShowFactoryResetConfirm()
    if InCombatLockdown and InCombatLockdown() then
        MSUF_Print("Cannot factory reset while in combat.")
        return
    end

    if not StaticPopupDialogs["MSUF_FACTORY_RESET_CONFIRM"] then
        StaticPopupDialogs["MSUF_FACTORY_RESET_CONFIRM"] = {
            text = "FACTORY RESET MSUF now?\n\nThis deletes ALL MSUF profiles & settings for this account.\n\nThe UI will reload.",
            button1 = YES,
            button2 = NO,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
            OnAccept = function()
                -- Prefer the shared reset function (exported by MSUF_ChatAndTooltips.lua)
                if type(_G.MSUF_DoFullReset) == "function" then
                    pcall(_G.MSUF_DoFullReset)
                    return
                end

                -- Fallback: do the bare-minimum reset here.
                _G.MSUF_DB = nil
                _G.MSUF_GlobalDB = nil
                _G.MSUF_ActiveProfile = nil
                if type(ReloadUI) == "function" then
                    ReloadUI()
                end
            end,
        }
    end

    StaticPopup_Show("MSUF_FACTORY_RESET_CONFIRM")
end


-- LEFT COLUMN: Quick Actions
local quick = CreateCard(colL, "Quick Actions")
quick:SetHeight(206)

local bigW = 410
local bigH = 26

local bEdit = UI_Button(quick, "Toggle Edit Mode", bigW, bigH, "TOPLEFT", quick, "TOPLEFT", 12, -34, DashToggleEditMode)
MSUF_SkinDashboardButton(bEdit)
if MSUF_AddTooltip then
    MSUF_AddTooltip(bEdit, "Toggle Edit Mode", "Enter MSUF Edit Mode to drag frames and adjust positions.")
end

local win = _G and _G.MSUF_StandaloneOptionsWindow
if win then
    win._msufDashEditBtn = bEdit
end
if bEdit and bEdit._msufSetSelected then
    bEdit:_msufSetSelected(MSUF_IsMSUFEditModeActive())
end
MSUF_TryHookEditModeForDashboard()


local bReset = UI_Button(quick, "Reset Frame Positions", bigW, bigH, "TOPLEFT", bEdit, "BOTTOMLEFT", 0, -8, MSUF_ShowResetPositionsConfirm)
MSUF_SkinDashboardButton(bReset)
if MSUF_AddTooltip then
    MSUF_AddTooltip(bReset, "Reset Frame Positions", "Resets MSUF frame positions + visibility to defaults (active profile).")
end

-- Row: open pages
local smallH = 22

-- We are already in the Options window here, so the "Options" shortcut is redundant.
-- Keep just Colors + Gameplay, and make Gameplay intentionally smaller.
local bColors = UI_Button(quick, "Colors", 160, smallH, "TOPLEFT", bReset, "BOTTOMLEFT", 0, -10, function() MSUF_SwitchMirrorPage("colors") end)
MSUF_SkinDashboardButton(bColors)

local bGame = UI_Button(quick, "Gameplay", 118, smallH, "LEFT", bColors, "RIGHT", 10, 0, function() MSUF_SwitchMirrorPage("gameplay") end)
MSUF_SkinDashboardButton(bGame)


-- LEFT COLUMN: Profile card
local profCard = CreateCard(colL, "Profile", quick, -12)
profCard:SetHeight(92)

local profLabel = profCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
profLabel:SetPoint("TOPLEFT", profCard, "TOPLEFT", 12, -34)
profLabel:SetText("Active profile:")
MSUF_SkinText(profLabel)

local profValue = profCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
profValue:SetPoint("LEFT", profLabel, "RIGHT", 8, 0)
profValue:SetText((_G and _G.MSUF_ActiveProfile) or "Default")
MSUF_SkinTitle(profValue)
home._msufProfileValue = profValue

local bProfiles = UI_Button(profCard, "Open Profiles", 160, 22, "TOPRIGHT", profCard, "TOPRIGHT", -12, -30, function() MSUF_SwitchMirrorPage("profiles") end)
MSUF_SkinDashboardButton(bProfiles)


-- Discord link (Masque-style: selectable text + Select button)
do
    local DISCORD_URL = "https://discord.gg/JQnhZXnTAK"

    local discordRow = CreateFrame("Frame", nil, profCard)
    discordRow:SetPoint("TOPLEFT", profCard, "TOPLEFT", 12, -56)
    discordRow:SetPoint("TOPRIGHT", profCard, "TOPRIGHT", -12, -56)
    discordRow:SetHeight(20)

    local discordLabel = discordRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    discordLabel:SetPoint("LEFT", discordRow, "LEFT", 0, 0)
    discordLabel:SetText("Discord:")
    MSUF_SkinText(discordLabel)

    local bDiscordSelect = UI_Button(discordRow, "Select", 72, 18, "RIGHT", discordRow, "RIGHT", 0, 0, function()
        if discordRow._msufDiscordBox and discordRow._msufDiscordBox.SetFocus then
            discordRow._msufDiscordBox:SetFocus()
            if discordRow._msufDiscordBox.HighlightText then
                discordRow._msufDiscordBox:HighlightText()
            end
        end
    end)
    MSUF_SkinDashboardButton(bDiscordSelect)
    if MSUF_AddTooltip then
        MSUF_AddTooltip(bDiscordSelect, "Select", "Click to select this text.")
    end

    local discordBox = CreateFrame("EditBox", nil, discordRow, "InputBoxTemplate")
    discordBox:SetAutoFocus(false)
    discordBox:SetHeight(18)
    discordBox:SetPoint("LEFT", discordLabel, "RIGHT", 8, 0)
    discordBox:SetPoint("RIGHT", bDiscordSelect, "LEFT", -8, 0)
    discordBox:SetText(DISCORD_URL)
    discordBox:SetCursorPosition(0)
    if discordBox.SetTextColor then
        discordBox:SetTextColor(0.30, 0.60, 1.00) -- link-ish blue
    end
    if discordBox.SetScript then
        discordBox:SetScript("OnEditFocusGained", function(self)
            if self.HighlightText then self:HighlightText() end
        end)
        discordBox:SetScript("OnEscapePressed", function(self)
            if self.ClearFocus then self:ClearFocus() end
            if self.HighlightText then self:HighlightText(0, 0) end
        end)
        discordBox:SetScript("OnEnterPressed", function(self)
            if self.ClearFocus then self:ClearFocus() end
        end)
    end

    -- Store for button handler
    discordRow._msufDiscordBox = discordBox
end


-- LEFT COLUMN: Advanced card (fills remainder; collapsible)
local adv = CreateCard(colL, "Advanced", profCard, -12)
adv:SetPoint("BOTTOMLEFT", colL, "BOTTOMLEFT", 0, 0)
adv:SetPoint("BOTTOMRIGHT", colL, "BOTTOMRIGHT", 0, 0)

local advTitle = adv._msufTitle

local advToggle = UI_Button(adv, "Show", 88, 18, "TOPRIGHT", adv, "TOPRIGHT", -12, -8, function() end)
MSUF_SkinDashboardButton(advToggle)

local advHint = adv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
advHint:SetPoint("TOPLEFT", adv, "TOPLEFT", 12, -34)
advHint:SetWidth(410)
advHint:SetJustifyH("LEFT")
advHint:SetJustifyV("TOP")
advHint:SetAlpha(0.82)
MSUF_SkinMuted(advHint)

local advBody = CreateFrame("Frame", nil, adv)
advBody:SetPoint("TOPLEFT", advHint, "BOTTOMLEFT", 0, -8)
advBody:SetPoint("TOPRIGHT", adv, "TOPRIGHT", -12, -58)
advBody:SetPoint("BOTTOMLEFT", adv, "BOTTOMLEFT", 12, 12)
advBody:SetPoint("BOTTOMRIGHT", adv, "BOTTOMRIGHT", -12, 12)

local cmds = advBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
cmds:SetPoint("TOPLEFT", advBody, "TOPLEFT", 0, 0)
cmds:SetJustifyH("LEFT")
cmds:SetJustifyV("TOP")
cmds:SetWidth(410)
cmds:SetText("/msuf  - Open MSUF menu\n" .. "/msuf options  - Open Options\n" .. "/msuf colors  - Open Colors\n" .. "/msuf gameplay  - Open Gameplay\n" .. "/msuf reset  - Reset frame positions\n" .. "/msuf fullreset  - Factory reset\n" .. "/msuf absorb  - Toggle absorb in HP text\n" .. "/msufprofile on/off/reset/show\n" .. "/msuf help  - Print help in chat")
MSUF_SkinText(cmds)

local btnRow = CreateFrame("Frame", nil, advBody)
btnRow:SetPoint("BOTTOMLEFT", advBody, "BOTTOMLEFT", 0, 0)
btnRow:SetPoint("BOTTOMRIGHT", advBody, "BOTTOMRIGHT", 0, 0)
btnRow:SetHeight(24)

local bHelp = UI_Button(btnRow, "Print Help", 120, 20, "BOTTOMLEFT", btnRow, "BOTTOMLEFT", 0, 0, function()
    if _G.SlashCmdList and _G.SlashCmdList["MIDNIGHTSUF"] then
        pcall(_G.SlashCmdList["MIDNIGHTSUF"], "help")
    end
end)
MSUF_SkinDashboardButton(bHelp)

local bFullReset = UI_Button(btnRow, "Factory Reset", 120, 20, "LEFT", bHelp, "RIGHT", 8, 0, function()
    -- Use a real button-confirm flow so ReloadUI happens from a hardware event (no /msuf fullreset confirm taint).
    MSUF_ShowFactoryResetConfirm()
end)
MSUF_SkinDashboardButton(bFullReset)

local function AdvApplyState(open)
    if open then
        advToggle:SetText("Hide")
        advHint:SetText("")
        advBody:Show()
    else
        advToggle:SetText("Show")
        advHint:SetText("Hidden. Click Show to reveal slash commands + power tools.")
        advBody:Hide()
    end
end

advToggle:SetScript("OnClick", function()
    S.mirror.dashAdvOpen = not S.mirror.dashAdvOpen
    AdvApplyState(S.mirror.dashAdvOpen)
end)

AdvApplyState(S.mirror.dashAdvOpen == true)


-- RIGHT COLUMN: Scale & Layout (uses existing tool builder, but with apple-ish segmented scale buttons)
local scaleCard = CreateCard(colR, nil, nil, nil, true)
scaleCard:SetHeight(238)
S.mirror.homeToolsApi = MSUF_BuildTools(scaleCard, { compact = false, wide = true, xl = true, title = "Scale & Layout", segmented = true, showValue = true })


-- RIGHT COLUMN: Presets (fills remainder)
local presetsCard = CreateCard(colR, "Presets", scaleCard, -12)
presetsCard:SetPoint("BOTTOMLEFT", colR, "BOTTOMLEFT", 0, 0)
presetsCard:SetPoint("BOTTOMRIGHT", colR, "BOTTOMRIGHT", 0, 0)

local presetsTitle = presetsCard._msufTitle

local presetDrop = CreateFrame("Frame", "MSUF_PresetDropdown", presetsCard, "UIDropDownMenuTemplate")
presetDrop:SetPoint("TOPLEFT", presetsTitle, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(presetDrop, 220)
UIDropDownMenu_SetText(presetDrop, presetsCard._msufSelectedPreset or "Select preset...")

UIDropDownMenu_Initialize(presetDrop, function(self, level)
    local names = MSUF_GetPresetNames()
    if not names or #names == 0 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "(no presets)"
        info.notCheckable = true
        UIDropDownMenu_AddButton(info, level)
        return
    end

    for _, name in ipairs(names) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.checked = (presetsCard._msufSelectedPreset == name)
        info.func = function()
            presetsCard._msufSelectedPreset = name
            UIDropDownMenu_SetText(presetDrop, name)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)

do
    local names = MSUF_GetPresetNames()
    if (not presetsCard._msufSelectedPreset) and names and names[1] then
        presetsCard._msufSelectedPreset = names[1]
        UIDropDownMenu_SetText(presetDrop, names[1])
    end
end

local bLoadPreset = UI_Button(presetsCard, "Load preset", 240, 24, "TOPLEFT", presetDrop, "BOTTOMLEFT", 16, -6, function()
    local sel = presetsCard._msufSelectedPreset
    if not sel then
        MSUF_Print("Select a preset first.")
        return
    end
    MSUF_ShowPresetConfirm(sel)
end)
MSUF_SkinDashboardButton(bLoadPreset)
if MSUF_AddTooltip then
    MSUF_AddTooltip(bLoadPreset, "Load preset", "Applies the selected preset to your current active profile. This overwrites settings (export first if unsure).")
end

local presetHint = presetsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
presetHint:SetPoint("TOPLEFT", bLoadPreset, "BOTTOMLEFT", 0, -4)
presetHint:SetText("Overwrites your current active profile settings.")
MSUF_SkinMuted(presetHint)


-- Support links (bottom-right, under Presets)
do
    local KO_FI_URL = "https://ko-fi.com/midnightsimpleunitframes#linkModal"
    local PAYPAL_URL = "https://www.paypal.com/ncp/payment/H3N2P87S53KBQ"
    local GITHUB_URL = "https://github.com/Mapkov2/MidnightSimpleUnitFrames"
    local ICON_DIR = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Masks\\"

    -- Left-side label (requested): keep it simple, unobtrusive, and anchored to the Presets card.
    local supportLabel = presetsCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    supportLabel:SetPoint("BOTTOMLEFT", presetsCard, "BOTTOMLEFT", 12, 14)
    supportLabel:SetText("Support the MSUF Development:")
    supportLabel:SetTextColor(0.90, 0.90, 0.90)
    supportLabel:SetJustifyH("LEFT")
    supportLabel:SetJustifyV("MIDDLE")
    if MSUF_SkinMuted then
        -- Slightly muted like other helper text, but still readable.
        pcall(MSUF_SkinMuted, supportLabel)
    end

    local row = CreateFrame("Frame", nil, presetsCard)
    row:SetHeight(24)
    row:SetWidth(120)
    row:SetPoint("BOTTOMRIGHT", presetsCard, "BOTTOMRIGHT", -12, 12)

    local function CreateIcon(texFile, size, tooltipTitle, tooltipText, onClick)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(size, size)

        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(ICON_DIR .. texFile)

        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.10)

        b:SetScript("OnClick", onClick)

        if MSUF_AddTooltip then
            MSUF_AddTooltip(b, tooltipTitle, tooltipText)
        else
            b:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                GameTooltip:AddLine(tooltipTitle or "", 1, 1, 1)
                if tooltipText and tooltipText ~= "" then
                    GameTooltip:AddLine(tooltipText, 0.85, 0.85, 0.85, true)
                end
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end

        return b
    end

    local sz = 22
    local gap = 7

    local bPayPal = CreateIcon("PayPal.png", sz,
        "PayPal",
        "Click to copy the PayPal support link.",
        function()
            MSUF_ShowCopyLink("PayPal", PAYPAL_URL)
        end)
    bPayPal:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    local bKoFi = CreateIcon("Ko-Fi.png", sz,
        "Ko-fi",
        "Click to copy the Ko-fi link.",
        function()
            MSUF_ShowCopyLink("Ko-fi", KO_FI_URL)
        end)
    bKoFi:SetPoint("RIGHT", bPayPal, "LEFT", -gap, 0)

    local bGitHub = CreateIcon("GitHub.png", sz,
        "GitHub",
        "Click to copy the GitHub repository link.",
        function()
            MSUF_ShowCopyLink("GitHub", GITHUB_URL)
        end)
    bGitHub:SetPoint("RIGHT", bKoFi, "LEFT", -gap, 0)
end


    -- Responsive dashboard layout: prevent overlaps on smaller window sizes / lower UI scale.
    local function MSUF_DashboardLayout()
        local wL = (colL and colL.GetWidth and colL:GetWidth()) or 0
        local wR = (colR and colR.GetWidth and colR:GetWidth()) or 0
        if wL <= 0 or wR <= 0 then return end

        local innerL = math.floor(wL - 24)
        local innerR = math.floor(wR - 24)
        if innerL < 1 then innerL = 1 end
        if innerR < 1 then innerR = 1 end

        -- Left column: big primary actions
        if bEdit and bEdit.SetWidth then bEdit:SetWidth(innerL) end
        if bReset and bReset.SetWidth then bReset:SetWidth(innerL) end

        -- Left column: 3-wide shortcuts row
        local gap = 7
        local each = math.floor((innerL - (gap * 2)) / 3)
        if each < 1 then each = 1 end
        if bOptions and bOptions.SetWidth then bOptions:SetWidth(each) end
        if bColors and bColors.SetWidth then bColors:SetWidth(each) end
        if bGameplay and bGameplay.SetWidth then bGameplay:SetWidth(each) end

        -- Advanced hints / slash list should follow column width
        if advHint and advHint.SetWidth then advHint:SetWidth(innerL) end
        if cmds and cmds.SetWidth then cmds:SetWidth(innerL) end

        -- Right column: preset dropdown + button widths
        local ddW = math.floor(innerR - 18)
        if ddW > 320 then ddW = 320 end
        if ddW < 1 then ddW = 1 end
        if presetDrop and UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(presetDrop, ddW) end
        if bLoadPreset and bLoadPreset.SetWidth then bLoadPreset:SetWidth(math.max(1, math.min(innerR, ddW + 20))) end
        if presetHint and presetHint.SetWidth then presetHint:SetWidth(innerR) end

        if S and S.mirror and S.mirror.homeToolsApi and S.mirror.homeToolsApi.Layout then
            pcall(S.mirror.homeToolsApi.Layout)
        end
    end

    if not home.__MSUF_DashboardLayoutHooked then
        home.__MSUF_DashboardLayoutHooked = true
        if home.HookScript then
            home:HookScript("OnShow", function() if C_Timer and C_Timer.After then C_Timer.After(0, MSUF_DashboardLayout) else MSUF_DashboardLayout() end end)
            home:HookScript("OnSizeChanged", function() if C_Timer and C_Timer.After then C_Timer.After(0, MSUF_DashboardLayout) else MSUF_DashboardLayout() end end)
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, MSUF_DashboardLayout)
    else
        MSUF_DashboardLayout()
    end

    -- Blue tint overlay for the mirrored content (keeps it "midnight" even if underlying UI is red)
    local tint = f:CreateTexture(nil, "BORDER")
    tint:SetColorTexture(0.06, 0.12, 0.25, 0.16)
    tint:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    tint:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    f._msufTint = tint

    f:SetScript("OnShow", function()
        S.mirror.host = f._msufMirrorClipHost or f._msufMirrorHost or content

        -- Always start with the left tree expanded when the window is opened.
        -- (Users can collapse it while the window is open, but a fresh open should be "ready".)
        do
            local nav = f._msufNavRail
            if nav and nav._msufTreeHeaders then
                nav._msufTreeHeaders.unitframes = true
                nav._msufTreeHeaders.options = true
                if nav._msufTreeReflow then nav._msufTreeReflow() end
            end
        end

        -- Pick tip once per window open (do not cycle just because you switch pages)
        if MSUF_PickSessionTip then
            MSUF_PickSessionTip()
        end

        -- Open to a requested page (set by MSUF_ToggleOptionsWindow/MSUF_ShowOptionsWindow),
        -- otherwise default to the Menu/Home page.
        local startKey = f._msufInitialKey or "home"
        local startSubKey = f._msufInitialSubKey
        f._msufInitialKey = nil
        f._msufInitialSubKey = nil

        S.mirror.currentKey = startKey
        MSUF_SwitchMirrorPage(startKey, startSubKey)
    end)

    f:SetScript("OnHide", function()
        -- Restore any globally hidden buttons used by mirrored pages
        MSUF_Standalone_SetCastbarTopButtonsHidden(false)
        if MSUF_SaveWindowGeometry then
            MSUF_SaveWindowGeometry(f, f._msufGeomKey or "full")
        end
        if S.mirror.currentPanel then
            MSUF_DetachMirroredPanel(S.mirror.currentPanel)
            S.mirror.currentPanel = nil
        end
    end)

    f:Hide()
    S.win = f
    return f
end

local function MSUF_ToggleOptionsWindow(key, subkey)
    local w = MSUF_CreateOptionsWindow()

    -- If already shown:
    --  - If a key was provided and it's different, just switch pages (do NOT hide).
    --  - Otherwise behave like a normal toggle (hide).
    if w:IsShown() then
        -- If a key/subkey was provided, never hide the window – just navigate.
        if key and S.mirror.currentKey ~= key then
            MSUF_SwitchMirrorPage(key, subkey)
            return
        end
        if subkey then
            MSUF_SwitchMirrorPage(key or S.mirror.currentKey or "home", subkey)
            return
        end
        w:Hide()
        return
    end

    -- If hidden, remember the desired start page for OnShow.
    w._msufInitialKey = key
    w._msufInitialSubKey = subkey or "home"
    w._msufInitialSubKey = subkey
    w:Show()
end


-- ------------------------------------------------------------
-- Phase 1: Public navigation API (single entry-point)
-- ------------------------------------------------------------
-- We expose a stable, global router so *all* MSUF UI can be opened the same way
-- (Flash/Standalone window is the only settings UI.)

local function MSUF_ShowOptionsWindow(key, subkey)
    local w = MSUF_CreateOptionsWindow()
    key = key or "home"

    if w.IsShown and w:IsShown() then
        -- Already visible: just switch pages (never hide).
        if key and S and S.mirror and S.mirror.currentKey ~= key then
            MSUF_SwitchMirrorPage(key, subkey)
        elseif key then
            MSUF_SwitchMirrorPage(key, subkey)
        end
        return w
    end

    -- Hidden: remember desired start page for OnShow.
    w._msufInitialKey = key
    w._msufInitialSubKey = subkey
    if w.Show then w:Show() end
    return w
end

local function MSUF_HideOptionsWindow()
    if S and S.win and S.win.IsShown and S.win:IsShown() and S.win.Hide then
        S.win:Hide()
    end
end


-- Public: open the standalone "Flash" window to a page.
-- (Back-compat aliases keep older calls working.)
_G.MSUF_ShowStandaloneOptionsWindow = MSUF_ShowOptionsWindow
_G.MSUF_OpenStandaloneOptionsWindow = MSUF_ShowOptionsWindow
_G.MSUF_HideStandaloneOptionsWindow = MSUF_HideOptionsWindow

-- Public: single navigation entry-point.
-- key: home|main|colors|gameplay (more keys can be added later)
-- subkey is reserved for Phase 2/3 (per-section selection inside a page)
_G.MSUF_OpenPage = function(key, subkey)
    key = (key or "home")
    if type(key) == "string" then
        key = key:lower()
    else
        key = "home"
    end

    -- Aliases / deep-links (Phase 2)
    --   menu|flash -> home
    --   options     -> main
    --   unit|frames <unitKey> -> main + select unit
    --   castbar <unitKey?> -> castbar shortcut page (select castbar tab + optional subpage)
    if key == "menu" or key == "flash" then
        key = "home"
    elseif key == "options" then
        key = "main"
    elseif key == "unit" or key == "frames" then
        key = "main"
        -- keep subkey as-is (unitKey)
    elseif key == "boss_castbar" or key == "bosscastbar" then
        key = "castbar"
        subkey = subkey or "boss"
    end

    -- If the caller passes a 2nd param but uses a shortcut page name as the key:
    -- e.g. MSUF_OpenPage("player") -> treat as unit key
    if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" or key == "boss" then
        subkey = key
        key = "main"
    end

    -- Also allow direct tab keys as first argument (QoL):
    if key == "bars" or key == "fonts" or key == "auras" or key == "misc" or key == "profiles" then
        subkey = key
        key = "main"
    end

    -- Castbar deep-link shorthand:
    if MSUF_IsCastbarKey(key) and (subkey == nil or subkey == true) then
        -- keep key as castbar page
    end

-- Prefer the standalone window (Flash menu) for any known mirror page.
    local info = (type(MSUF_GetMirrorPageInfo) == "function") and MSUF_GetMirrorPageInfo(key) or nil
    if info then
        -- Try to ensure the mirrored panel exists first (prevents "only dashboard" issues).
        local panel
        if type(info.build) == "function" then
            panel = info.build()
        end

        -- If we failed to build the panel, fall back to Blizzard Settings instead of doing nothing.
        if (key ~= "home") and (type(info.build) == "function") and (not panel) then
            MSUF_ShowOptionsWindow("home")
            return false
        end

        MSUF_ShowOptionsWindow(key, subkey)
        return true
    end

    -- Unknown key: fall back to Home.
    MSUF_ShowOptionsWindow("home")
    return false
end

-- Back-compat: some older code calls MSUF_OpenOptionsMenu() to open settings.
-- In Phase 1, this should open the Flash window (home page), since Flash is the new primary UI.
_G.MSUF_OpenOptionsMenu = function()
    if _G and _G.MSUF_OpenPage then
        _G.MSUF_OpenPage("home")
    else
        MSUF_ShowOptionsWindow("home")
    end
end

-- ------------------------------------------------------------
-- Mini Menu (the slash UI)
-- ------------------------------------------------------------
local function MSUF_CreateMiniMenu()
    if S.mini then return S.mini end

    local f = CreateFrame("Frame", "MSUF_MiniMenuFrame", UIParent, "BackdropTemplate")
    f:SetSize(340, 235) -- smaller
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 10)
    f:SetFrameStrata("DIALOG")
    f._msufGeomKey = "mini"
    f._msufMinW, f._msufMinH, f._msufMaxW, f._msufMaxH = 260, 180, 720, 520
    if MSUF_LoadWindowGeometry then
        MSUF_LoadWindowGeometry(f, "mini", 340, 235, "CENTER", 260, 10)
    end
    if MSUF_RegisterEscClose then
        MSUF_RegisterEscClose(f)
    end
    if f.SetClampRectInsets then
        f:SetClampRectInsets(8, 8, 8, 8)
    end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if MSUF_SaveWindowGeometry then
            MSUF_SaveWindowGeometry(self, self._msufGeomKey or "mini")
        end
    end)

    MSUF_ApplyMidnightBackdrop(f, 0.94)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("MSUF Mini Menu")
    MSUF_SkinTitle(title)

    local close = UI_CloseButton(f, "TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local fullBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    fullBtn:SetSize(150, 20)
    fullBtn:SetPoint("TOPRIGHT", -14, -16)
    fullBtn:SetText("Open Full Options")
    MSUF_SkinButton(fullBtn)
    fullBtn:SetScript("OnClick", function()
        MSUF_ToggleOptionsWindow("main")
    end)

    if MSUF_AddTooltip then
        MSUF_AddTooltip(fullBtn, "Open Full Options", "Opens the full MSUF options window.")
    end

    local tools = CreateFrame("Frame", nil, f)
    tools:SetPoint("TOPLEFT", 8, -36)
    tools:SetPoint("BOTTOMRIGHT", -8, 8)
    f._MSUF_ToolsApi = MSUF_BuildTools(tools, { compact = false })

    f:SetScript("OnShow", function()
        if f._MSUF_ToolsApi and f._MSUF_ToolsApi.Refresh then
            f._MSUF_ToolsApi.Refresh()
        end
    end)

    f:SetScript("OnHide", function()
        if MSUF_SaveWindowGeometry then
            MSUF_SaveWindowGeometry(f, f._msufGeomKey or "mini")
        end
    end)

    f:Hide()
    S.mini = f
    return f
end

local function MSUF_ToggleMiniMenu()
    local f = MSUF_CreateMiniMenu()
    if f:IsShown() then f:Hide() else f:Show() end
end

-- ------------------------------------------------------------
-- Slash hook: keep /msuf behavior, add "options"
-- ------------------------------------------------------------
local function MSUF_InstallSlashHook()


    if _G.MSUF_MiniMenuSlashHooked then return end

    if SlashCmdList and SlashCmdList["MIDNIGHTSUF"] then
        local original = SlashCmdList["MIDNIGHTSUF"]
        SlashCmdList["MIDNIGHTSUF"] = function(msg)
            local raw = msg or ""
            raw = raw:gsub("^%s+", "")
            local first, rest = raw:match("^(%S+)%s*(.-)%s*$")
            first = first and first:lower() or ""
            rest = rest or ""

            local function openKey(key)
                if S.mini and S.mini.IsShown and S.mini:IsShown() then
                    S.mini:Hide()
                end
                MSUF_ToggleOptionsWindow(key)
            end

            -- /msuf (no args) opens the full window directly on the Menu/Home page
            if first == "" then
                openKey("home")
                return
            end

            -- Quick-open pages (these are purely UI shortcuts; other commands still go to the original handler)
            if first == "menu" or first == "home" then
                openKey("home")
                return
            end
            if first == "options" then
                openKey("main")
                return
            end
            if first == "colors" or first == "colours" then
                openKey("colors")
                return
            end
            if first == "gameplay" then
                openKey("gameplay")
                return
            end

            if first == "castbar" then
                -- Optional: /msuf castbar player|target|focus|boss
                local sub = rest and rest:lower() or ""
                if sub ~= "" then
                    MSUF_ToggleOptionsWindow("castbar", sub)
                else
                    openKey("castbar")
                end
                return
            end
            if first == "profiles" then
                openKey("profiles")
                return
            end

            return original(msg)
        end
    end

    SLASH_MSUFOPTIONS1 = "/msufoptions"
    SlashCmdList["MSUFOPTIONS"] = function()
        if S.mini and S.mini.IsShown and S.mini:IsShown() then
            S.mini:Hide()
        end
        MSUF_ToggleOptionsWindow("main")
    end

    -- Optional: keep the tiny window for debugging / quick testing
    SLASH_MSUFMINI1 = "/msufmini"
    SlashCmdList["MSUFMINI"] = function()
        MSUF_ToggleMiniMenu()
    end

    _G.MSUF_MiniMenuSlashHooked = true
end

MSUF_InstallSlashHook()

-- Apply saved scales after login/entering world (silent)
local scaleEvent = CreateFrame("Frame")
scaleEvent:RegisterEvent("PLAYER_LOGIN")
scaleEvent:RegisterEvent("PLAYER_ENTERING_WORLD")
scaleEvent:RegisterEvent("DISPLAY_SIZE_CHANGED")

scaleEvent:SetScript("OnEvent", function(_, event, arg1)
    -- Respect the global scaling kill-switch.
    if MSUF_IsScalingDisabled and MSUF_IsScalingDisabled() then
        return
    end
    -- Always apply MSUF-only scale
    MSUF_ApplyMsufScale(MSUF_GetSavedMsufScale())

    -- Apply/enforce MSUF global UI scale override (if preset isn't Auto).
    local want = MSUF_GetDesiredGlobalScaleFromDB()
    if want then
        if event == "PLAYER_LOGIN" then
            -- Full apply on login: CVars + UIParent
            MSUF_SetGlobalUiScale(want, true)
            -- Extra nudge in case something overrides UIParent shortly after login.
            MSUF_EnsureGlobalUiScaleApplied(true)
        else
            -- For resize/zone transitions: UIParent-only guardian (no CVar spam).
            MSUF_EnsureGlobalUiScaleApplied(true)
        end
    end
end)

-- Initial kick (covers rare load orders where events fired before our handler existed)
if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
        if MSUF_IsScalingDisabled and MSUF_IsScalingDisabled() then
            return
        end
        MSUF_ApplyMsufScale(MSUF_GetSavedMsufScale())
        local want = MSUF_GetDesiredGlobalScaleFromDB()
        if want then
            -- UIParent-only kick before login events (avoid early CVar churn).
            MSUF_SetGlobalUiScale(want, true, { applyCVars = false })
            MSUF_EnsureGlobalUiScaleApplied(true)
        end
    end)
end
