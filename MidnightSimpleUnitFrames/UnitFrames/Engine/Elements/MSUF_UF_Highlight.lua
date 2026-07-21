local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
  _G[name] = value
  return value
end


-- Unitframe highlight overlay runtime.
-- Owns the optional mouseover/target-style highlight frame layered above unitframes. Global
-- DB changes update cached config, while per-frame calls only show/hide/recolor the overlay.
local CreateFrame = CreateFrame
local CreateColor = _G.CreateColor
local floor = math.floor
local tonumber = tonumber
local type = type
local issecretvalue = _G.issecretvalue or function(_) return false end

local Highlight = {}
MSUF.Highlight = Highlight

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local BACKDROP_TEMPLATE = (BackdropTemplateMixin and "BackdropTemplate") or nil

local cfgEnabled = true
local cfgR, cfgG, cfgB = 1, 1, 1
local cfgStyle = "GRADIENT"
local cfgSize = 6
local cfgGen = 0
local sawDB = false

local function HideFrameHighlight(frame)
  local hb = frame and frame._msufHL
  if hb and hb.Hide then
    hb:Hide()
  end
end

local function ForEachHighlightFrame(fn)
  local uf = MSUF and MSUF.UF
  if uf and type(uf.ForEachFrame) == "function" then
    uf.ForEachFrame(fn)
  else
    local frames = uf and uf.frames
    if type(frames) == "table" then
      for _, frame in pairs(frames) do
        fn(frame)
      end
    end
  end

  local list = uf and uf.frameList
  if type(list) == "table" then
    for i = 1, #list do
      fn(list[i])
    end
  end

  local ns = _G.MSUF_NS or _G.MSUF or MSUF
  local gf = ns and ns.GF
  if gf and type(gf.ForEachFrame) == "function" then
    gf.ForEachFrame(fn, true)
  elseif gf and type(gf.frameList) == "table" then
    for i = 1, #gf.frameList do
      fn(gf.frameList[i])
    end
  end
end

local function HideExistingHighlights()
  ForEachHighlightFrame(HideFrameHighlight)
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

local ShowImpl, HideImpl
local RefreshExistingHighlights
local roundedUnitMouseover
local roundedGroupMouseover

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
  if not size then size = 6 end
  cfgSize = floor(size + 0.5)
  if cfgSize < 1 then cfgSize = 1 end
  if cfgSize > 16 then cfgSize = 16 end

  cfgStyle = general and tostring(general.highlightStyle or "GRADIENT"):upper() or "GRADIENT"
  if cfgStyle ~= "BORDER" then cfgStyle = "GRADIENT" end

  cfgGen = cfgGen + 1

  if not enabled then
    HideExistingHighlights()
  elseif RefreshExistingHighlights then
    RefreshExistingHighlights()
  end
  return true
end

local function ConfigureGradientTexture(tex, direction)
  if not tex then return end
  local orientation = (direction == "up" or direction == "down") and "VERTICAL" or "HORIZONTAL"
  local minA, maxA = 0, 0.78
  if direction == "left" or direction == "down" then minA, maxA = maxA, minA end
  tex:SetTexture(WHITE8)
  if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
  if tex.SetGradient and CreateColor then
    tex:SetGradient(orientation, CreateColor(cfgR, cfgG, cfgB, minA), CreateColor(cfgR, cfgG, cfgB, maxA))
  elseif tex.SetGradientAlpha then
    tex:SetGradientAlpha(orientation, cfgR, cfgG, cfgB, minA, cfgR, cfgG, cfgB, maxA)
  elseif tex.SetColorTexture then
    tex:SetColorTexture(cfgR, cfgG, cfgB, 0.62)
  end
end

local function EnsureGradient(hb)
  local gradient = hb._msufGradient
  if not gradient then
    gradient = {}
    for _, direction in ipairs({ "left", "right", "up", "down" }) do
      gradient[direction] = hb:CreateTexture(nil, "OVERLAY")
    end
    gradient.left:SetPoint("TOPLEFT", hb, "TOPLEFT", 0, 0)
    gradient.left:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", 0, 0)
    gradient.right:SetPoint("TOPRIGHT", hb, "TOPRIGHT", 0, 0)
    gradient.right:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
    gradient.up:SetPoint("TOPLEFT", hb, "TOPLEFT", 0, 0)
    gradient.up:SetPoint("TOPRIGHT", hb, "TOPRIGHT", 0, 0)
    gradient.down:SetPoint("BOTTOMLEFT", hb, "BOTTOMLEFT", 0, 0)
    gradient.down:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 0, 0)
    hb._msufGradient = gradient
  end
  gradient.left:SetWidth(cfgSize)
  gradient.right:SetWidth(cfgSize)
  gradient.up:SetHeight(cfgSize)
  gradient.down:SetHeight(cfgSize)
  for direction, tex in pairs(gradient) do
    ConfigureGradientTexture(tex, direction)
    tex:Show()
  end
end

local function HideGradient(hb)
  local gradient = hb and hb._msufGradient
  if type(gradient) ~= "table" then return end
  for _, tex in pairs(gradient) do
    if tex and tex.Hide then tex:Hide() end
  end
end

local function ApplyHighlightVisual(hb)
  if cfgStyle == "GRADIENT" and hb.CreateTexture then
    if hb.SetBackdrop then hb:SetBackdrop(nil) end
    EnsureGradient(hb)
  else
    HideGradient(hb)
    if hb.SetBackdrop then hb:SetBackdrop({ edgeFile = WHITE8, edgeSize = cfgSize }) end
    if hb.SetBackdropBorderColor then hb:SetBackdropBorderColor(cfgR, cfgG, cfgB, 1) end
  end
end

local function EnsureHighlight(frame)
  local hb = frame._msufHL
  if not hb then
    hb = CreateFrame("Frame", nil, frame, BACKDROP_TEMPLATE)
    hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    hb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    hb:EnableMouse(false)
    hb:Hide()
    frame._msufHL = hb
  end

  -- PERF: strata/level writes invalidate render batching even when the value
  -- is unchanged; every mouseover lands here, so only write on real change.
  if hb.SetFrameStrata and frame.GetFrameStrata then
    local strata = frame:GetFrameStrata()
    if issecretvalue(strata) ~= true then
      strata = strata or "MEDIUM"
      local cachedStrata = hb._appliedStrata
      if issecretvalue(cachedStrata) == true or cachedStrata ~= strata then
        hb._appliedStrata = strata
        hb:SetFrameStrata(strata)
      end
    end
  end
  if hb.SetFrameLevel and frame.GetFrameLevel then
    local level = (frame:GetFrameLevel() or 0) + 5
    if hb._appliedLevel ~= level then
      hb._appliedLevel = level
      hb:SetFrameLevel(level)
    end
  end

  local w = hb.GetWidth and hb:GetWidth() or 0
  local h = hb.GetHeight and hb:GetHeight() or 0
  if not (w and h and w >= 1 and h >= 1 and w < 10000 and h < 10000) then
    if hb._appliedGen ~= nil then
      if hb.SetBackdrop then hb:SetBackdrop(nil) end
      hb._appliedGen = nil
    end
    if hb.Hide then hb:Hide() end
    return nil
  end

  if hb._appliedGen ~= cfgGen then
    hb._appliedGen = cfgGen
    ApplyHighlightVisual(hb)
  end
  return hb
end

RefreshExistingHighlights = function(frame)
  local function RefreshFrame(current)
    local hb = current and current._msufHL
    if hb and hb.IsShown and hb:IsShown() then EnsureHighlight(current) end
  end
  if frame then return RefreshFrame(frame) end
  ForEachHighlightFrame(RefreshFrame)
end

ShowImpl = function(frame)
  if not frame then return end
  if not cfgEnabled then return end
  if not sawDB and _G.MSUF_DB and _G.MSUF_DB.general then
    Highlight.Refresh()
    if not cfgEnabled then return end
  end
  local hb = frame._msufHL
  if not hb or hb._appliedGen ~= cfgGen then
    hb = EnsureHighlight(frame)
  end
  if hb then hb:Show() end
end

HideImpl = function(frame)
  if not frame then return end
  local hb = frame._msufHL
  if hb then hb:Hide() end
end

-- These are the callbacks installed directly on live buttons. Rounded state is
-- resolved only when settings change, so mouseover never reads globals or DB.
local function UnitEnter(frame)
  local rounded = roundedUnitMouseover
  if rounded then return rounded(frame, true) end
  if not cfgEnabled then return end
  return ShowImpl(frame)
end

local function UnitLeave(frame)
  local rounded = roundedUnitMouseover
  if rounded then return rounded(frame, false) end
  if not cfgEnabled then return end
  return HideImpl(frame)
end

local function GroupEnter(frame)
  local rounded = roundedGroupMouseover
  if rounded then return rounded(frame, true) end
  if not cfgEnabled then return end
  return ShowImpl(frame)
end

local function GroupLeave(frame)
  local rounded = roundedGroupMouseover
  if rounded then return rounded(frame, false) end
  if not cfgEnabled then return end
  return HideImpl(frame)
end

function Highlight.SetRoundedMouseoverState(unitActive, groupActive, unitHandler, groupHandler)
  local nextUnit = unitActive == true and unitHandler or nil
  local nextGroup = groupActive == true and groupHandler or nil
  local changed = roundedUnitMouseover ~= nextUnit or roundedGroupMouseover ~= nextGroup
  roundedUnitMouseover = nextUnit
  roundedGroupMouseover = nextGroup
  if changed and (nextUnit or nextGroup) then HideExistingHighlights() end
end

Highlight.UnitEnter = UnitEnter
Highlight.UnitLeave = UnitLeave
Highlight.GroupEnter = GroupEnter
Highlight.GroupLeave = GroupLeave
Highlight.Show = UnitEnter
Highlight.Hide = UnitLeave

Highlight.Refresh()

ExportPublic("MSUF_RefreshMouseoverHighlight", Highlight.Refresh)

local function HighlightDebug()
  Highlight.Refresh()
  local p = print
  p("MSUF Highlight: loaded=YES enabled=" .. tostring(cfgEnabled)
    .. " color=" .. string.format("%.2f,%.2f,%.2f", cfgR, cfgG, cfgB)
    .. " style=" .. tostring(cfgStyle)
    .. " size=" .. tostring(cfgSize)
    .. " roundedOwns=" .. tostring(roundedUnitMouseover ~= nil))
  local f = _G.MSUF_target
  if not f then
    local uf = MSUF and MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
      f = uf.GetFrame("target")
    end
    local list = not f and uf and uf.frameList
    if not f and type(list) == "table" then
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
ExportPublic("MSUF_HighlightDebug", HighlightDebug)
