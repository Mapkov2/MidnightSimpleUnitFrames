local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
-- All three menu looks are selectable on every client. Only the fresh
-- profile default is client-specific: Forever uses Classic Glass, others Midnight.
-- Register before Menu2 tokens so renderers capture the selected palette.
local _, MSUF = ...
if not MSUF then return end
MSUF.ApplyClassicMenuTheme = function(T)
    -- Appearance presets own materials as well as colors. Resolve before any
    -- renderer captures tokens; switching presets uses the existing reload flow.
    T.defaultMenuAppearancePreset = MSUF.Client and MSUF.Client.IsForever == true and "classicGlass" or "midnight"
    function T.GetMenuAppearancePreset(g)
        local saved = type(g) == "table" and g.menuAppearancePreset
        if saved == "classicGlass" or saved == "midnight" or saved == "midnightDark" then return saved end
        return T.defaultMenuAppearancePreset
    end
    function T.GetMenuBackgroundOpacity(settings)
        local value = type(settings) == "table" and tonumber(settings.menuBackgroundOpacity) or nil
        return math.max(80, math.min(100, value or 96))
    end
    -- Bindings (and GetGeneralDB) load after tokens. Read the normalized saved
    -- profile directly at this early point in the Options load order.
    if type(_G.MSUF_EnsureDB) == "function" then _G.MSUF_EnsureDB() end
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    T.menuAppearancePreset = T.GetMenuAppearancePreset(g)
    -- The Midnight preset keeps the stock tokens: this return skips the whole
    -- atlas skin below, including T.PrepareMenuAccent and T.ApplyAtlasDecoration.
    if T.menuAppearancePreset == "midnight" then return end
    local function Paint(keys, hex, alpha)
        local r, green, b = tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
        for key in keys:gmatch("%S+") do
            local row = assert(T.colors[key], "Unknown menu color: " .. key)
            row[1], row[2], row[3], row[4] = r, green, b, alpha or 1
        end
    end
    if T.menuAppearancePreset == "midnightDark" then
        -- Use the existing glass renderer and tint its shared panel artwork.
        -- Every page, popup, dropdown, button and navigation row reads these
        -- same tokens, including hover and pressed states.
        Paint("coreShadow bg glassShell", "151719", 0.92)
        Paint("coreInk panelNav glassRail", "111315", 0.89)
        Paint("coreSurface panel glassHost", "222424", 0.87)
        Paint("coreRaised panel2 glassStatus", "292D31", 0.88)
        Paint("glassPopup", "1A1C1F", 0.96)
        Paint("header", "202326", 0.90)
        Paint("coreRim border", "575B58", 0.78)
        Paint("cardBorder borderSoft", "414541", 0.68)
        Paint("coreBlue", "353A37")
        Paint("coreGlow pillEdgeHover navPillEdgeHover", "777A71", 0.78)
        Paint("coreHot accent checkActive pillEdgeActive navPillEdgeActive checkActiveEdge navArrowOpen", "B9AB86")
        Paint("accent2 guide", "B9AB86", 0.72)
        Paint("text pillText navText", "E9E9E4")
        Paint("title pillTextActive navTextActive", "F3F0E7")
        Paint("muted searchPlaceholder navHeaderText navArrowClosed", "B9BDB9")
        Paint("dim", "A3A8A3")
        Paint("disabled", "878D88")
        Paint("checkInactive navPillBase", "202326", 0.88)
        Paint("checkInactiveEdge pillEdge pillEdgeButton navPillEdge", "555A56", 0.72)
        Paint("pillBase navPillBaseSolid", "292D31", 0.89)
        Paint("pillBaseSolid", "292D31", 0.96)
        Paint("pillHover navPillHover", "424743", 0.91)
        Paint("pillActive navPillActive", "353A37", 0.94)
        Paint("navHeaderHover", "D8CEB5")
        Paint("focus", "292D31", 0.78)
        T.fontRoleColors = {
            heading = T.colors.title, hero = T.colors.title, section = T.colors.title,
            accordion = T.colors.title, card = T.colors.title,
        }
        T.accentSourceTones = {
            { 53 / 255, 58 / 255, 55 / 255 },
            { 119 / 255, 122 / 255, 113 / 255 },
            { 185 / 255, 171 / 255, 134 / 255 },
        }
        for _, color in pairs(T.navIconColors) do
            color[1], color[2], color[3] = 185 / 255, 189 / 255, 185 / 255
        end
        for _, spec in pairs(T.glassVariants) do
            spec.tint = { 24 / 255, 26 / 255, 27 / 255, spec.tint[4] }
            spec.wash = { 41 / 255, 45 / 255, 49 / 255, spec.wash[4] }
            spec.top = { 185 / 255, 171 / 255, 134 / 255, spec.top[4] }
            spec.side = { 87 / 255, 91 / 255, 88 / 255, spec.side[4] }
        end
        for name, gradient in pairs(T.gradients) do
            if name ~= "warning" and name ~= "button" then
                if gradient.from then gradient.from[1], gradient.from[2], gradient.from[3] = 41 / 255, 45 / 255, 49 / 255 end
                if gradient.to then gradient.to[1], gradient.to[2], gradient.to[3] = 17 / 255, 19 / 255, 21 / 255 end
            end
        end
        for _, veil in pairs(T.focusVeils) do
            for _, layer in ipairs(veil) do
                local color = layer.color
                if color and color[1] > 0 then
                    color[1], color[2], color[3] = 32 / 255, 35 / 255, 38 / 255
                end
            end
        end
        T.materials.guide.bg = { 32 / 255, 35 / 255, 38 / 255, 0.28 }
        T.MenuAccentSurfacesTinted = function() return true end
        return
    end
    local root = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Menu2\\Classic\\"
    T.classicAtlas = true
    T.controlCapWidth = 4
    T.controlGradientScale = 0.25
    T.staticMaterials = true
    T.quietSections = true
    local shells = setmetatable({}, { __mode = "k" })
    local shellAlpha = T.GetMenuBackgroundOpacity(g) / 100
    function T.ApplyMenuBackgroundOpacity(frame, variant)
        if variant ~= "shell" then return end
        shells[frame] = true
        local art = frame._msuf2PanelAsset
        for _, region in pairs(art or {}) do
            if type(region) == "table" and region.SetAlpha then region:SetAlpha(shellAlpha) end
        end
    end
    function T.RefreshMenuBackgroundOpacity()
        shellAlpha = T.GetMenuBackgroundOpacity(_G.MSUF_DB and _G.MSUF_DB.general) / 100
        T.colors.glassShell[4], T.colors.bg[4] = shellAlpha, shellAlpha
        for frame in pairs(shells) do T.ApplyMenuBackgroundOpacity(frame, "shell") end
    end
    -- Keep the user's readable menu font; the artwork carries the fantasy theme.

    Paint("coreShadow", "14181B")
    Paint("bg glassShell", "14181B", shellAlpha)
    Paint("glassPopup", "191D20", 0.98)
    Paint("coreInk", "111517")
    Paint("panelNav glassRail", "111517", 0.44)
    Paint("coreSurface", "20272A")
    Paint("panel glassHost", "20272A", 0.08)
    Paint("glassStatus", "111517", 0.30)
    Paint("header", "282D2E", 0.30)
    Paint("coreRaised", "292F31")
    Paint("panel2", "292F31", 0.22)
    Paint("coreRim border", "9F8960", 0.26)
    Paint("cardBorder borderSoft", "68716F", 0.12)
    Paint("coreBlue", "363C3C")
    Paint("coreGlow", "515956")
    Paint("pillActive navPillActive", "363C3C", 0.64)
    Paint("coreHot accent checkActive pillEdgeHover navPillEdgeHover navPillEdgeActive checkActiveEdge navArrowOpen pillEdgeActive", "D8B66A")
    Paint("text pillText navText", "F4F3EB")
    Paint("title pillTextActive navTextActive navHeaderHover", "F1E3C4")
    Paint("navHeaderText", "C3B48E")
    Paint("muted searchPlaceholder dim navArrowClosed", "D4DCE2")
    Paint("disabled", "8F9999")
    Paint("checkInactive navPillBase", "20272A")
    Paint("checkInactiveEdge", "727774")
    Paint("pillEdge pillEdgeButton navPillEdge", "727774", 0.26)
    Paint("pillBase navPillBaseSolid", "292F31", 0.44)
    Paint("pillBaseSolid", "292F31", 0.90)
    Paint("pillHover navPillHover", "454A47", 0.55)
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
        { 54 / 255, 60 / 255, 60 / 255 },
        { 81 / 255, 89 / 255, 86 / 255 },
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
