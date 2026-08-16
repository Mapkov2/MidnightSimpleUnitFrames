--- Shell/Menu2/MSUF_Menu2_ThemeSkin.lua
--- Consumes the MSUF UI theme bridge (Runtime/MSUF_UIThemeBridge.lua in the
--- core addon): a registered skin provider (MidnightSkin) supplies a palette
--- ramp and a control-shape choice, and this file maps them onto Menu2's
--- token layer. The provider never paints Menu2 frames - it only supplies
--- values, so the menu's live token repaints stay the single painter.
---
--- Token rows are mutated IN PLACE: widgets capture references to the color
--- arrays, so writing r/g/b/a into the existing tables reaches captured
--- references and fresh reads alike. Menu2's WCAG-tuned text ramp and the
--- semantic colors (ok/danger/warning) deliberately stay MSUF-owned.
local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme

local CORE_ADDON = "MidnightSimpleUnitFrames"
local SHAPE_PATH = "Interface\\AddOns\\" .. CORE_ADDON .. "\\Media\\Shapes\\"
local SHAPE_FAMILIES = { round = true, continuous = true, squircle = true }
local SHAPE_RADII = { 4, 6, 8, 12 }
local PILL_HEIGHTS = { 20, 24, 28, 32 }

-- token = source palette key, optional alpha override keeps MSUF's layering.
local TOKEN_MAP = {
    { "bg", "background", 0.94 },
    { "glassShell", "background", 0.90 },
    { "glassRail", "ink", 0.88 },
    { "glassHost", "surface", 0.86 },
    { "glassStatus", "surface", 0.88 },
    { "glassPopup", "popup", 0.94 },
    { "coreShadow", "background", 1.00 },
    { "coreInk", "ink", 1.00 },
    { "coreSurface", "surface", 1.00 },
    { "coreRaised", "raised", 1.00 },
    { "coreRim", "rim", 1.00 },
    { "coreBlue", "pressed", 1.00 },
    { "coreGlow", "accent", 1.00 },
    { "coreHot", "accentBright", 1.00 },
    { "panel", "surface", 0.90 },
    { "panelNav", "ink", 0.92 },
    { "panel2", "raised", 0.90 },
    { "header", "surface", 0.92 },
    { "border", "border", 0.86 },
    { "borderSoft", "borderSoft", 0.72 },
    { "cardBorder", "border", 0.82 },
    { "accent", "accent", 1.00 },
    { "guide", "accent", 0.58 },
    { "focus", "raised", 0.78 },
    { "checkActive", "pressed", 1.00 },
    { "checkActiveEdge", "accentBright", 0.94 },
    { "checkInactive", "input", 1.00 },
    { "checkInactiveEdge", "border", 0.88 },
    { "pillBase", "buttonFillAlt", 0.92 },
    { "pillBaseSolid", "buttonFill", 0.94 },
    { "pillHover", "hover", 0.96 },
    { "pillActive", "active", 0.96 },
    { "pillEdge", "buttonBorder", 0.68 },
    { "pillEdgeButton", "buttonBorder", 0.76 },
    { "pillEdgeHover", "accent", 0.58 },
    { "pillEdgeActive", "accentBright", 0.78 },
    { "navPillBase", "background", 0.86 },
    { "navPillBaseSolid", "surface", 0.92 },
    { "navPillHover", "hover", 0.96 },
    { "navPillActive", "active", 0.96 },
    { "navPillEdge", "buttonBorder", 0.62 },
    { "navPillEdgeHover", "accent", 0.60 },
    { "navPillEdgeActive", "accentBright", 0.80 },
    { "navHeaderHover", "accentBright", 1.00 },
    { "navArrowOpen", "accentBright", 1.00 },
}

local originalTokens
local applied = false

local function SnapshotOriginals()
    if originalTokens then return end
    originalTokens = {}
    for i = 1, #TOKEN_MAP do
        local row = T.colors[TOKEN_MAP[i][1]]
        if row then
            originalTokens[TOKEN_MAP[i][1]] = { row[1], row[2], row[3], row[4] }
        end
    end
end

local function WriteToken(name, source, alpha)
    local row = T.colors[name]
    if not (row and source) then return end
    row[1], row[2], row[3] = source[1], source[2], source[3]
    row[4] = alpha or source[4] or row[4]
end

local function ClosestValue(values, requested)
    requested = tonumber(requested) or values[1]
    local best, distance = values[1], math.abs((tonumber(requested) or values[1]) - values[1])
    for i = 2, #values do
        local d = math.abs(requested - values[i])
        if d < distance then best, distance = values[i], d end
    end
    return best
end

local function CornerSpec(family, radius, border)
    local stem = tostring(family) .. "_r" .. tostring(radius)
    local margin = radius == 12 and 15.5 or 9.5
    return {
        fill = SHAPE_PATH .. stem .. "_fill.png",
        edge = SHAPE_PATH .. stem .. "_edge" .. tostring(border) .. ".png",
        margins = { margin, margin, margin, margin },
    }
end

local function ResolveShapeSet(shapes)
    if type(shapes) ~= "table" then return nil end
    local family = tostring(shapes.controlShape or "")
    local border = (tonumber(shapes.border) == 2) and 2 or 1
    if family == "pill" then
        local perHeight = {}
        for i = 1, #PILL_HEIGHTS do
            local h = PILL_HEIGHTS[i]
            local stem = "pill_h" .. tostring(h)
            perHeight[h] = {
                fill = SHAPE_PATH .. stem .. "_fill.png",
                edge = SHAPE_PATH .. stem .. "_edge" .. tostring(border) .. ".png",
                margins = { h / 2, 0, h / 2, 0 },
            }
        end
        return {
            kind = "pill",
            ResolvePill = function(height)
                return perHeight[ClosestValue(PILL_HEIGHTS, height)]
            end,
        }
    end
    if not SHAPE_FAMILIES[family] then return nil end
    local spec = CornerSpec(family, ClosestValue(SHAPE_RADII, shapes.radius), border)
    spec.kind = "corner"
    return spec
end

--- Applies (or clears) the provider theme. Returns true when a provider theme
--- is active afterwards.
local function ApplyProviderTheme()
    local getTheme = rawget(_G, "MSUF_GetUITheme")
    local theme = type(getTheme) == "function" and getTheme() or nil
    local palette = theme and theme.palette
    if type(palette) == "table" then
        SnapshotOriginals()
        for i = 1, #TOKEN_MAP do
            local map = TOKEN_MAP[i]
            WriteToken(map[1], palette[map[2]], map[3])
        end
        T.activeShapeSet = ResolveShapeSet(theme.shapes)
        -- Join the menu-accent session contract: the "+tint" marker makes
        -- every authored-art owner (panel bitmaps, window controls) follow
        -- MenuAccentSurfacesTinted() and re-hue from the remapped coreSurface
        -- token - and ApplyMenuAccent's already-applied short-circuit keeps
        -- the user's saved menu accent from overwriting the provider tokens.
        T._menuAccentApplied = "provider+tint"
        applied = true
        return true
    end
    if applied and originalTokens then
        for name, saved in pairs(originalTokens) do
            local row = T.colors[name]
            if row then row[1], row[2], row[3], row[4] = saved[1], saved[2], saved[3], saved[4] end
        end
    end
    if T._menuAccentApplied == "provider+tint" then T._menuAccentApplied = nil end
    T.activeShapeSet = nil
    applied = false
    return false
end

local function ReapplyAndRefresh()
    local active = ApplyProviderTheme()
    if not M.frame then return end
    -- Already-built pages carry the old paint; rebuild them all. The window
    -- shell itself repaints on the next UI reload - the palette swap normally
    -- happens at login, where everything builds skinned from the start.
    if type(M.InvalidatePage) == "function" and type(M.cache) == "table" then
        for key in pairs(M.cache) do M.InvalidatePage(key) end
    end
    if M.frame.IsShown and M.frame:IsShown() and M.activeKey and type(M.SelectPage) == "function" then
        M.SelectPage(M.activeKey)
    end
    if M.ShowStatusFeedback then
        M.ShowStatusFeedback(M.Tr(active and "Theme updated" or "Theme reset"), "info", 1.4)
    end
end

-- Apply at load: this file runs right after the token/theme modules and before
-- any widget factory or page builds, so a login-time provider paints the very
-- first build. Late provider changes re-enter through the bridge listener.
ApplyProviderTheme()
local addListener = rawget(_G, "MSUF_AddUIThemeListener")
if type(addListener) == "function" then
    addListener(ReapplyAndRefresh)
end
M.ApplyUIThemeProvider = ApplyProviderTheme
