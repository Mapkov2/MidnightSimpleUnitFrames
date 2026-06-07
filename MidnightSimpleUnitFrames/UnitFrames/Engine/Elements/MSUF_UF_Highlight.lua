local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

--- ===========================================================================
--- Mouseover Highlight (standalone, performant)
--- ---------------------------------------------------------------------------
--- The classic 5.57 highlight, just cleaner: a single BackdropTemplate frame
--- with a WHITE8x8 edge, built once per unit/group frame, shown on hover.
---
---   COLDPATH  -> Highlight.Refresh()      : read config once (enabled/colour/
---               size) and cache it. Called only when the DB/options change.
---   COLDPATH  -> EnsureBorder + ApplyBorder : build the backdrop + colour it,
---               re-run only when the cache generation changed.
---   WARMPATH  -> Highlight.Show/Hide      : OnEnter/OnLeave just Show()/Hide()
---               an already-built, already-coloured border. No API work.
---
--- When the Rounded Frames effect owns the mouseover edge we stay hidden so two
--- borders never stack.
--- ===========================================================================

local CreateFrame = CreateFrame
local tonumber = tonumber
local type = type

local Highlight = {}
MSUF.Highlight = Highlight

local WHITE8 = "Interface\\Buttons\\WHITE8x8"
local BACKDROP_TEMPLATE = (BackdropTemplateMixin and "BackdropTemplate") or nil

--- Coldpath cache ------------------------------------------------------------
local cfgEnabled = true
local cfgR, cfgG, cfgB = 1, 1, 1
local cfgSize = 1
--- Bumped every Refresh() so built borders lazily re-apply on their next show.
local cfgGen = 0
--- True once we've read the real DB (not the load-time placeholder).
local sawDB = false

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

--- True when the Rounded Frames effect owns the mouseover edge for this frame.
local function RoundedOwnsMouseover()
    return _G.MSUF_RoundedUF_MouseoverActive == true
end

--- Warmpath entry points are swapped between real/no-op by Refresh() so that,
--- when the feature is OFF, OnEnter/OnLeave hit a bare `return` -> zero overhead.
local ShowImpl, HideImpl
local function NoOp() end

--- COLDPATH: recompute cached config + (re)wire the warmpath. Only called on
--- config changes, never on hover.
function Highlight.Refresh()
    local db = _G.MSUF_DB
    local general = db and db.general or nil
    if general then sawDB = true end

    --- Canonical key is highlightEnabled; keep old enableHighlightOnHover compat.
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

    --- Swap the public Show/Hide: disabled => no-op (0 hover cost). Hide stays
    --- real for one Refresh so an on->off toggle can clear a visible border.
    if enabled then
        Highlight.Show = ShowImpl
        Highlight.Hide = HideImpl
    else
        Highlight.Show = NoOp
        Highlight.Hide = HideImpl
    end
    return true
end

--- COLDPATH: build the backdrop border once, then (re)colour it whenever the
--- cached config generation changed. Returns the border frame (or nil).
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

    --- Keep it above the frame's own bars/text so the edge is always visible.
    if hb.SetFrameStrata and frame.GetFrameStrata then
        hb:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    end
    if hb.SetFrameLevel and frame.GetFrameLevel then
        hb:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
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

--- WARMPATH (enabled): called from OnEnter. Show the border (build/colour
--- lazily once). Active only while the feature is on; otherwise Show == NoOp.
ShowImpl = function(frame)
    if not frame then return end
    --- One-time safety: if the cache was filled before the DB existed, re-pull.
    if not sawDB and _G.MSUF_DB and _G.MSUF_DB.general then
        Highlight.Refresh()
        --- Refresh may have just turned us off; honour that immediately.
        if not cfgEnabled then return end
    end
    if RoundedOwnsMouseover() then
        --- Rounded mouseover edge handles the visual; keep ours hidden.
        local hb = frame._msufHL
        if hb then hb:Hide() end
        return
    end
    local hb = EnsureBorder(frame)
    if hb then hb:Show() end
end

--- WARMPATH: called from OnLeave. Pure hide, no work.
HideImpl = function(frame)
    if not frame then return end
    local hb = frame._msufHL
    if hb then hb:Hide() end
end

--- Initial cache fill + warmpath wiring (config re-pushed once the DB is ready).
Highlight.Refresh()

--- Expose a global so options/colors code can repaint after edits.
_G.MSUF_RefreshMouseoverHighlight = Highlight.Refresh

--- Diagnostic: `/run MSUF_HighlightDebug()` prints live state + force-shows a
--- border on the current target frame so we can see if rendering works at all.
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
