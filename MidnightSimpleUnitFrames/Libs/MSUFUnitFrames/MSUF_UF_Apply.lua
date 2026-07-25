local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}


local Apply = MSUF.Apply or {}
MSUF.Apply = Apply

--- Libs/MSUFUnitFrames/MSUF_UF_Apply.lua
---
--- Tiny idempotent wrappers around common Region/StatusBar setters. Elements
--- use these in hot and warm paths to avoid repeated SetTexture/SetPoint/SetText
--- calls when the value has not changed. Secret values bypass the cache because
--- comparing or storing them can be unsafe on Midnight clients.

local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
Apply.IsSecret = IsSecret
local issecretvalue = _G.issecretvalue or function(_) return false end

function Apply.Texture(region, tex)
  if not region then return end
  if IsSecret(tex) then
    region:SetTexture(tex)
    region._aTex = nil
    region._aColorTexture = nil
    return
  end
  if region._aTex ~= tex then
    region:SetTexture(tex)
    region._aTex = tex
    region._aColorTexture = nil
  end
end

function Apply.ColorTexture(region, r, g, b, a)
  if not region then return end
  a = a or 1
  if IsSecret(r) or IsSecret(g) or IsSecret(b) or IsSecret(a) then
    region:SetColorTexture(r, g, b, a)
    region._aColorTexture = nil
    region._aTex = nil
    return
  end
  if region._aColorTexture ~= true or region._aCTR ~= r or region._aCTG ~= g
    or region._aCTB ~= b or region._aCTA ~= a then
    region:SetColorTexture(r, g, b, a)
    region._aColorTexture = true
    region._aCTR = r
    region._aCTG = g
    region._aCTB = b
    region._aCTA = a
    region._aTex = nil
  end
end

function Apply.Size(region, w, h)
  if not region then return end
  h = h or w
  if region._aW ~= w or region._aH ~= h then
    region:SetSize(w, h)
    region._aW = w
    region._aH = h
  end
end

function Apply.Point(region, point, rel, relPoint, x, y)
  if not region then return end
  if region._aPt ~= point or region._aRel ~= rel or region._aRelPt ~= relPoint
    or region._aX ~= x or region._aY ~= y then
    region:ClearAllPoints()
    region:SetPoint(point, rel, relPoint, x, y)
    region._aPt = point
    region._aRel = rel
    region._aRelPt = relPoint
    region._aX = x
    region._aY = y
  end
end

function Apply.Shown(region, show)
  if not region then return end
  show = show and true or false
  if region._aShown ~= show then
    region:SetShown(show)
    region._aShown = show
  end
end

function Apply.Text(region, text)
  if not region then return end
  if issecretvalue(text) == true then
    region:SetText(text)
    region._aText = nil
    region._aTextPlain = nil
    return
  end
  text = text or ""
  if region._aTextPlain == true and region._aText == text then
    return
  end
  region:SetText(text)
  region._aText = text
  region._aTextPlain = true
end

function Apply.StatusColor(bar, r, g, b, a)
  if not bar then return end
  a = a or 1
  if IsSecret(r) or IsSecret(g) or IsSecret(b) or IsSecret(a) then
    bar:SetStatusBarColor(r, g, b, a)
    bar._aCR = nil
    return
  end
  if bar._aCR ~= r or bar._aCG ~= g or bar._aCB ~= b or bar._aCA ~= a then
    bar:SetStatusBarColor(r, g, b, a)
    bar._aCR = r
    bar._aCG = g
    bar._aCB = b
    bar._aCA = a
  end
end

function Apply.VertexColor(region, r, g, b, a)
  if not region then return end
  a = a or 1
  if IsSecret(r) or IsSecret(g) or IsSecret(b) or IsSecret(a) then
    region:SetVertexColor(r, g, b, a)
    region._aVR = nil
    return
  end
  if region._aVR ~= r or region._aVG ~= g or region._aVB ~= b or region._aVA ~= a then
    region:SetVertexColor(r, g, b, a)
    region._aVR = r
    region._aVG = g
    region._aVB = b
    region._aVA = a
  end
end

function Apply.Invalidate(region)
  if not region then return end
  region._aTex = nil
  region._aColorTexture = nil
  region._aCTR = nil
  region._aCTG = nil
  region._aCTB = nil
  region._aCTA = nil
  region._aText = nil
  region._aTextPlain = nil
  region._aW = nil
  region._aH = nil
  region._aPt = nil
  region._aRel = nil
  region._aRelPt = nil
  region._aX = nil
  region._aY = nil
  region._aShown = nil
  region._aCR = nil
  region._aVR = nil
end

return Apply
