local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

-- =============================================================================
-- MSUF.Apply -- idempotent paint-layer backbone (shared by UF + GF).
--
-- The data layer already only computes what changed (dirty queues, the
-- delta-consuming AuraCache). The old paint-layer problem was re-issuing C
-- setters on every event regardless of whether the input changed.
-- oUF / Unhalted avoid this by construction: static styling is applied once at
-- build/config time and the per-event path touches only the changing value.
-- 6.0 has a unified runtime that re-derives, so it gets the same property by
-- memoizing each setter: a C call fires only when its own input actually moved.
--
-- One module, called by every element -> the single shared hot path Marco wants,
-- with no second implementation for group frames.
--
-- SECRET-SAFETY (Midnight 12.0): memo state is plain Lua fields on the region
-- table (never protected attributes, no taint). Any value that *could* be a
-- secret (texture file IDs, computed colors) is checked with issecretvalue
-- BEFORE the `~=` memo compare. If secret, we delegate straight to the C setter
-- (which accepts secrets) and poison the memo so the next plain value re-applies.
-- We never run `==`/`~=`/arithmetic on a secret value.
-- =============================================================================

local Apply = MSUF.Apply or {}
MSUF.Apply = Apply

local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
Apply.IsSecret = IsSecret
local issecretvalue = _G.issecretvalue or function(_) return false end

-- Texture (file ID or path). Aura icons are pre-filtered non-secret upstream,
-- but the guard makes the helper safe to call from anywhere.
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

-- Solid colour texture. Kept separate from Texture() so callers that switch
-- between file textures and generated colour textures never trust stale memo
-- state from the previous texture kind.
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

-- Size. w/h are plain config-derived numbers.
function Apply.Size(region, w, h)
    if not region then return end
    h = h or w
    if region._aW ~= w or region._aH ~= h then
        region:SetSize(w, h)
        region._aW = w
        region._aH = h
    end
end

-- Single anchor point (the common case for icons/indicators). `rel` is a frame
-- reference -- identity compare is fine and never secret.
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

-- Shown / hidden.
function Apply.Shown(region, show)
    if not region then return end
    show = show and true or false
    if region._aShown ~= show then
        region:SetShown(show)
        region._aShown = show
    end
end

-- FontString text. Secret strings/numbers are passed straight to the C-side
-- FontString sink and poison the plain-text memo. Plain text is deduped before
-- SetText to avoid C calls and string churn on unchanged text updates.
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

-- StatusBar fill colour. Colours in 6.0 are plain RGBA (class tables, config,
-- or ColorMixin:GetRGB() from curve eval); guard anyway.
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

-- Texture vertex colour.
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

-- Drop all memo state on a region. Call after a foreign actor mutates the region
-- behind our back (e.g. Masque:ReSkin re-anchors/re-textures icons) so the next
-- Apply.* re-asserts our values instead of trusting a now-stale cache.
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
