-- ============================================================================
-- MSUF_Widgets.lua
-- Minimal widget helpers for Midnight Simple Unit Frames.
-- Phase 7: Legacy dropdown factory (MSUF_DD_*) and modern dropdown system
-- removed — zero external callers after Widget SDK migration.
-- ============================================================================
local addonName, ns = ...

-- ── Theme ───────────────────────────────────────────────────────────────────
local T = {
    bgR = 0.04,  bgG = 0.06,  bgB = 0.13,  bgA = 0.95,
    edgeR = 0.12, edgeG = 0.22, edgeB = 0.48, edgeA = 0.90,
    textR = 0.86,  textG = 0.92,  textB = 1.00,  textA = 1.00,
    accentR = 0.30, accentG = 0.60, accentB = 1.00,
    mutedR = 0.55, mutedG = 0.60, mutedB = 0.70,
    hoverBgR = 0.08, hoverBgG = 0.10, hoverBgB = 0.18,
    selR = 0.20, selG = 0.40, selB = 0.80, selA = 0.30,
}

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function UseModern()
    local db = _G.MSUF_DB
    if not db then return true end
    local g = db.general
    if not g then return true end
    if g.useModernWidgets == nil then return true end
    return g.useModernWidgets and true or false
end

local function GetLSM()
    return _G.MSUF_GetLSM and _G.MSUF_GetLSM()
        or _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
        or nil
end

-- Export module onto ns for split-file usage
ns.MSUF_Widgets = {
    Theme     = T,
    UseModern = UseModern,
    GetLSM    = GetLSM,
}
