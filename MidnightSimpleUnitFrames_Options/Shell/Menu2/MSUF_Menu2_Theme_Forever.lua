local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
-- WoW Forever's menu skin (Classic Glass). Every Options TOC registers it before
-- Menu2 loads so the token owner can apply it before any renderer captures
-- colors, but only the WoW Forever client applies it (owner decision
-- 2026-09-16): Classic Era, TBC, Mists and Midnight keep the stock menu.
-- Client identity (MSUF.Client.IsForever), never a guessed interface number,
-- selects it.
local _, MSUF = ...
if not (MSUF and MSUF.Client and MSUF.Client.IsForever == true) then return end
MSUF.ApplyClassicMenuTheme = function(T)
    -- Appearance presets own materials as well as colors. Resolve before any
    -- renderer captures tokens; switching presets uses the existing reload flow.
    function T.GetMenuAppearancePreset(g)
        return type(g) == "table" and g.menuAppearancePreset == "midnight" and "midnight" or "classicGlass"
    end
    -- Bindings (and GetGeneralDB) load after tokens. Read the normalized saved
    -- profile directly at this early point in the Options load order.
    if type(_G.MSUF_EnsureDB) == "function" then _G.MSUF_EnsureDB() end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if type(g) == "table" and g.menuAppearancePreset == nil then g.menuAppearancePreset = "classicGlass" end
    T.menuAppearancePreset = T.GetMenuAppearancePreset(g)
    -- The Midnight preset keeps the stock tokens: this return skips the whole
    -- atlas skin below, including T.PrepareMenuAccent and T.ApplyAtlasDecoration.
    if T.menuAppearancePreset == "midnight" then return end
    local root = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Menu2\\Classic\\"
    T.classicAtlas = true
    T.controlCapWidth = 4
    T.controlGradientScale = 0.25
    T.staticMaterials = true
    -- Keep the user's readable menu font; the artwork carries the fantasy theme.

    local function Paint(keys, hex, alpha)
        local r, g, b = tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
        for key in keys:gmatch("%S+") do
            local row = assert(T.colors[key], "Unknown atlas color: " .. key)
            row[1], row[2], row[3], row[4] = r, g, b, alpha or 1
        end
    end
    Paint("coreShadow", "09121E")
    Paint("bg glassShell", "09121E", 0.90)
    Paint("glassPopup", "0B1725", 0.96)
    Paint("coreInk", "0E1B2B")
    Paint("panelNav glassRail", "0E1B2B", 0.34)
    Paint("coreSurface", "122235")
    Paint("panel glassHost", "122235", 0.16)
    Paint("glassStatus", "122235", 0.30)
    Paint("header", "203B53", 0.30)
    Paint("coreRaised", "16232E")
    Paint("panel2", "16232E", 0.36)
    Paint("coreRim border", "727774", 0.24)
    Paint("cardBorder borderSoft", "424D55", 0.14)
    Paint("coreBlue", "26333E")
    Paint("coreGlow", "3B4D59")
    Paint("pillActive navPillActive", "26333E", 0.64)
    Paint("coreHot accent checkActive pillEdgeHover navPillEdgeHover navPillEdgeActive checkActiveEdge navArrowOpen pillEdgeActive", "D8B66A")
    Paint("text pillText navText", "F4F3EB")
    Paint("title pillTextActive navTextActive navHeaderHover", "F1E3C4")
    Paint("navHeaderText", "C3B48E")
    Paint("muted searchPlaceholder dim navArrowClosed", "D4DCE2")
    Paint("disabled", "839FAF")
    Paint("checkInactive navPillBase", "102B43")
    Paint("checkInactiveEdge", "727774")
    Paint("pillEdge pillEdgeButton navPillEdge", "727774", 0.26)
    Paint("pillBase navPillBaseSolid", "162C40", 0.34)
    Paint("pillBaseSolid", "162C40", 0.75)
    Paint("pillHover navPillHover", "35434D", 0.46)
    Paint("guide", "D8B66A", 0.65)
    Paint("focus", "193C58", 0.80)
    -- Ivory headings and restrained gold accents keep a clear reading hierarchy.
    T.fontRoleColors = {
        heading = T.colors.title, hero = T.colors.title, section = T.colors.title,
        accordion = T.colors.title, card = T.colors.title,
    }
    -- Keep warning/success/danger semantic colors independent of the art palette.
    -- Saved class/custom accents remain functional with this new source ramp.
    T.accentSourceTones = {
        { 38 / 255, 51 / 255, 62 / 255 },
        { 59 / 255, 77 / 255, 89 / 255 },
        { 216 / 255, 182 / 255, 106 / 255 },
    }
    for _, color in pairs(T.navIconColors) do
        color[1], color[2], color[3] = 189 / 255, 172 / 255, 141 / 255
    end
    for _, name in ipairs({ "shell", "rail", "host", "status", "card", "popup" }) do
        local key = "panel" .. name:sub(1, 1):upper() .. name:sub(2)
        T.media[key] = root .. name .. ".tga"
        local grad = T.gradients[name]
        -- The bitmap owns this surface's alpha; no second opaque underpaint.
        grad.from = { 18 / 255, 34 / 255, 53 / 255, 0 }
        grad.to = { 9 / 255, 18 / 255, 30 / 255, 0 }
    end
    T.gradients.sliderFill.from = { 216 / 255, 182 / 255, 106 / 255, 0.85 }
    T.gradients.sliderFill.to = { 0.46, 0.36, 0.20, 0.90 }

    -- Retire the old near-black surface tint once when adopting the revised skin.
    -- Preserve the previous selection, and never fight later deliberate choices.
    function T.PrepareMenuAccent(g)
        if g.menuClassicAtlasRevision == 2 then return end
        local r, green, b = T.MenuAccentHexToRGB(g.menuAccentColor)
        if g.menuAccent == "custom" and g.menuAccentTintSurfaces == true and r
            and math.max(r, green, b) <= 0.15 and math.max(r, green, b) - math.min(r, green, b) <= 0.04 then
            g.menuClassicAtlasPreviousAppearance = {
                menuAccent = g.menuAccent, menuAccentColor = g.menuAccentColor,
                menuAccentTintSurfaces = g.menuAccentTintSurfaces,
            }
            g.menuAccent, g.menuAccentTintSurfaces = "midnight", false
        end
        g.menuClassicAtlasRevision = 2
    end
    T.media.superellipse = root .. "bevel.tga"
    T.media.checkBoxFill = root .. "check_fill.tga"
    T.media.checkBoxEdge = root .. "check_edge.tga"
    T.media.sliderThumb = root .. "slider_thumb.tga"
    T.media.switchTrack = root .. "switch_track.tga"
    T.media.switchKnob = root .. "switch_knob.tga"
    T.media.navPillIdle = root .. "nav_idle.tga"
    T.media.navPillHover = root .. "nav_hover.tga"
    T.media.navPillActive = root .. "nav_active.tga"
    T.media.windowControls = root .. "window_controls.tga"

    -- One static, mouse-transparent decoration on each structural surface. Keep
    -- maps away from settings rows and reuse the texture on repeated paints.
    function T.ApplyAtlasDecoration(frame, variant)
        if variant ~= "shell" and variant ~= "rail" then
            if frame._msuf2AtlasDecoration then frame._msuf2AtlasDecoration:Hide() end
            return
        end
        local tex = frame._msuf2AtlasDecoration
        if not tex then
            tex = PixelLayoutRegion(frame:CreateTexture(nil, "BORDER", nil, -7))
            frame._msuf2AtlasDecoration = tex
        end
        tex:ClearAllPoints()
        if variant == "shell" then
            tex:SetTexture(root .. "chart.tga")
            tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -58, -6)
            tex:SetSize(320, 48)
            tex:SetAlpha(0.20)
        else
            tex:SetTexture(root .. "compass.tga")
            tex:SetPoint("BOTTOM", frame, "BOTTOM", 0, 24)
            tex:SetSize(112, 112)
            tex:SetAlpha(0.12)
        end
        tex:Show()
    end
end
