local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

-- =============================================================================
-- MSUF.Apply -- idempotent paint-layer backbone (shared by UF + GF).
--
-- 6.0's data layer already only computes what changed (dirty queues, the
-- delta-consuming AuraCache). The regression vs 5.54 was that the *paint* layer
-- re-issued C setters on every event regardless of whether the input changed.
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

local issecretvalue = _G.issecretvalue
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
Apply.IsSecret = IsSecret

-- Texture (file ID or path). Aura icons are pre-filtered non-secret upstream,
-- but the guard makes the helper safe to call from anywhere.
function Apply.Texture(region, tex)
    if not region then return end
    if IsSecret(tex) then
        region:SetTexture(tex)
        region._aTex = nil
        return
    end
    if region._aTex ~= tex then
        region:SetTexture(tex)
        region._aTex = tex
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
