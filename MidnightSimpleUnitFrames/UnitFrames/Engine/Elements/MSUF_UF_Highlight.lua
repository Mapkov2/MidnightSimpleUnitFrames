local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF


-- Unitframe highlight overlay runtime.
-- Owns the optional mouseover/target-style highlight frame layered above unitframes. Global
-- DB changes update cached config, while per-frame calls only show/hide/recolor the overlay.
local CreateFrame = CreateFrame
local tonumber = tonumber
local type = type

local Highlight = {}
MSUF.Highlight = Highlight

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local BACKDROP_TEMPLATE = (BackdropTemplateMixin and "BackdropTemplate") or nil

local cfgEnabled = true
local cfgR, cfgG, cfgB = 1, 1, 1
local cfgSize = 1
local cfgGen = 0
local sawDB = false

local function HideFrameHighlight(frame)
  local hb = frame and frame._msufHL
  if hb and hb.Hide then
    hb:Hide()
  end
end

local function HideExistingHighlights()
  local frames = _G.MSUF_UnitFrames
  if type(frames) == "table" then
    for _, frame in pairs(frames) do
      HideFrameHighlight(frame)
    end
  end

  local list = _G.MSUF_UnitFramesList
  if type(list) == "table" then
    for i = 1, #list do
      HideFrameHighlight(list[i])
    end
  end

  local ns = _G.MSUF_NS or _G.MSUF or MSUF
  local gf = ns and ns.GF
  if gf and type(gf.ForEachFrame) == "function" then
    gf.ForEachFrame(HideFrameHighlight, true)
  elseif gf and type(gf.frameList) == "table" then
    for i = 1, #gf.frameList do
      HideFrameHighlight(gf.frameList[i])
    end
  end
end

local function ResolveHighlightRGB(general)
  local hc = general and general.highlightColor
  if type(hc) == "table" then
    return hc[1] or 1, hc[2] or 1, hc[3] or 1
  end
  local key = (type(hc) == "string" and hc:lower()) or "white"
  local colors = (MSUF and MSUF.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
  local col = colors and (colors[key] or colors.white)
  if col then
    return col[1] or 1, col[2] or 1, col[3] or 1
  end
  return 1, 1, 1
end

local function RoundedOwnsMouseover()
  return _G.MSUF_RoundedUF_MouseoverActive == true
end

local ShowImpl, HideImpl
local function NoOp() end

function Highlight.Refresh()
  local db = _G.MSUF_DB
  local general = db and db.general or nil
  if general then sawDB = true end

  local enabled = not (general and general.highlightEnabled == false)
  if general and general.highlightEnabled == nil and general.enableHighlightOnHover ~= nil then
    enabled = general.enableHighlightOnHover == true
  end
  cfgEnabled = enabled

  cfgR, cfgG, cfgB = ResolveHighlightRGB(general)

  local size = general and tonumber(general.highlightThickness)
  if not size or size < 1 then size = 1 end
  if size > 8 then size = 8 end
  cfgSize = size

  cfgGen = cfgGen + 1

  if enabled then
    Highlight.Show = ShowImpl
    Highlight.Hide = HideImpl
  else
    Highlight.Show = NoOp
    Highlight.Hide = HideImpl
    HideExistingHighlights()
  end
  return true
end

local function EnsureBorder(frame)
  local hb = frame._msufHL
  if not hb then
    hb = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    hb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    hb:EnableMouse(false)
    hb:Hide()
    frame._msufHL = hb
  end

  if hb.SetFrameStrata and frame.GetFrameStrata then
    hb:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
  end
  if hb.SetFrameLevel and frame.GetFrameLevel then
    hb:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
  end

  local w = hb.GetWidth and hb:GetWidth() or 0
  local h = hb.GetHeight and hb:GetHeight() or 0
  if not (w and h and w >= 1 and h >= 1 and w < 10000 and h < 10000) then
    if hb._appliedGen ~= nil then
      if hb.SetBackdrop then hb:SetBackdrop(nil) end
      hb._appliedGen = nil
    end
    if hb.Hide then hb:Hide() end
    return hb
  end

  if hb._appliedGen ~= cfgGen then
    hb._appliedGen = cfgGen
    if hb.SetBackdrop then
      hb:SetBackdrop({ edgeFile = WHITE8, edgeSize = cfgSize })
    end
    if hb.SetBackdropBorderColor then
      hb:SetBackdropBorderColor(cfgR, cfgG, cfgB, 1)
    end
  end
  return hb
end

ShowImpl = function(frame)
  if not frame then return end
  if not cfgEnabled then return end
  if not sawDB and _G.MSUF_DB and _G.MSUF_DB.general then
    Highlight.Refresh()
    if not cfgEnabled then return end
  end
  if RoundedOwnsMouseover() then
    local hb = frame._msufHL
    if hb then hb:Hide() end
    return
  end
  local hb = EnsureBorder(frame)
  if hb then hb:Show() end
end

HideImpl = function(frame)
  if not frame then return end
  local hb = frame._msufHL
  if hb then hb:Hide() end
end

Highlight.Refresh()

_G.MSUF_RefreshMouseoverHighlight = Highlight.Refresh

function _G.MSUF_HighlightDebug()
  Highlight.Refresh()
  local p = print
  p("MSUF Highlight: loaded=YES enabled=" .. tostring(cfgEnabled)
    .. " color=" .. string.format("%.2f,%.2f,%.2f", cfgR, cfgG, cfgB)
    .. " size=" .. tostring(cfgSize)
    .. " roundedOwns=" .. tostring(RoundedOwnsMouseover()))
  local f = _G.MSUF_target
  if not f then
    local list = _G.MSUF_UnitFramesList
    if type(list) == "table" then
      for i = 1, #list do
        if list[i] and list[i].unit == "target" then f = list[i] break end
      end
    end
  end
  if not f then p("MSUF Highlight: no target frame found (target something first)"); return end
  p("MSUF Highlight: target frame = " .. tostring(f:GetName()) .. " size=" .. tostring(f:GetWidth()) .. "x" .. tostring(f:GetHeight()))
  Highlight.Show(f)
  p("MSUF Highlight: forced Show. Border shown = " .. tostring(f._msufHL and f._msufHL:IsShown()))
end
