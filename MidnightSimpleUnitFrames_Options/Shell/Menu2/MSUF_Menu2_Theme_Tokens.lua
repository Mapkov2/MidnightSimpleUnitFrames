local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local T = M.Theme or {}
M.Theme = T

-- Menu2 theme tokens.
-- Declarative media paths, color rows, typography defaults, and token maps consumed by the
-- Theme module. Avoid runtime frame work here; this file is loaded as shared design data.
local ADDON = (type(addonName) == "string" and addonName ~= "" and addonName) or "MidnightSimpleUnitFrames"
local ADDON_PATH = "Interface\\AddOns\\" .. ADDON .. "\\"
T.media = T.media or {
    superellipse = ADDON_PATH .. "Media\\superellipse.tga",
    checkBoxFill = ADDON_PATH .. "Media\\msuf_checkbox_fill.tga",
    checkBoxEdge = ADDON_PATH .. "Media\\msuf_checkbox_edge.tga",
    checkTick = ADDON_PATH .. "Media\\msuf_check_tick_bold.tga",
    checkTickMedium = ADDON_PATH .. "Media\\msuf_check_tick_medium.tga",
    checkRim = ADDON_PATH .. "Media\\msuf_check_superellipse_hole.tga",
    dropdownChevron = ADDON_PATH .. "Media\\msuf_dropdown_chevron_down.tga",
    collapseArrow = "Interface\\ChatFrame\\ChatFrameExpandArrow",
    sliderThumb = ADDON_PATH .. "Media\\msuf_slider_thumb.tga",
    switchTrack = ADDON_PATH .. "Media\\msuf_switch_track.tga",
    switchKnob = ADDON_PATH .. "Media\\msuf_switch_knob.tga",
    bgSmooth = ADDON_PATH .. "Media\\Bars\\Smoothv2.tga",
    bgCharcoal = ADDON_PATH .. "Media\\Bars\\Charcoal.tga",
    logo = ADDON_PATH .. "Media\\MSUF_MinimapIcon.tga",
    navIcons = ADDON_PATH .. "Media\\msuf_nav_icons",
    navPillIdle = ADDON_PATH .. "Media\\Menu2\\msuf2_nav_idle.png",
    navPillHover = ADDON_PATH .. "Media\\Menu2\\msuf2_nav_hover.png",
    navPillActive = ADDON_PATH .. "Media\\Menu2\\msuf2_nav_active.png",
    windowControls = ADDON_PATH .. "Media\\Menu2\\msuf2_window_controls.png",
    windowControlIcons = ADDON_PATH .. "Media\\Menu2\\msuf2_window_control_icons.png",
    panelShell = ADDON_PATH .. "Media\\Menu2\\msuf2_panel_shell.png",
    panelRail = ADDON_PATH .. "Media\\Menu2\\msuf2_panel_rail.png",
    panelHost = ADDON_PATH .. "Media\\Menu2\\msuf2_panel_host.png",
    panelStatus = ADDON_PATH .. "Media\\Menu2\\msuf2_panel_status.png",
    panelCard = ADDON_PATH .. "Media\\Menu2\\msuf2_panel_card.png",
    panelPopup = ADDON_PATH .. "Media\\Menu2\\msuf2_panel_popup.png",
    historyUndo = ADDON_PATH .. "Media\\msuf_history_undo_red.png",
    historyRedo = ADDON_PATH .. "Media\\msuf_history_redo_green.png",
}
T.media.checkBoxFill = T.media.checkBoxFill or ADDON_PATH .. "Media\\msuf_checkbox_fill.tga"
T.media.checkBoxEdge = T.media.checkBoxEdge or ADDON_PATH .. "Media\\msuf_checkbox_edge.tga"
T.media.checkTickMedium = T.media.checkTickMedium or ADDON_PATH .. "Media\\msuf_check_tick_medium.tga"
T.media.gradH = T.media.gradH or ADDON_PATH .. "Media\\MSUF_Grad_H.tga"
T.media.gradHRev = T.media.gradHRev or ADDON_PATH .. "Media\\MSUF_Grad_H_Rev.tga"
T.media.gradV = T.media.gradV or ADDON_PATH .. "Media\\MSUF_Grad_V.tga"
T.media.gradVRev = T.media.gradVRev or ADDON_PATH .. "Media\\MSUF_Grad_V_Rev.tga"
local function ColorRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local key, values = line:match("^([^=]+)=(.+)$")
        if key then
            local c, n = {}, 0
            for value in values:gmatch("[^,]+") do n = n + 1; c[n] = tonumber(value) end
            out[key] = c
        end
    end
    return out
end
-- Accessible midnight palette. Structural surfaces stay neutral, blue owns interaction,
-- and green/red/amber are reserved for success, danger, and warning semantics.
-- Text legibility ramp against `panel`, in WCAG contrast: text 17.1:1, muted 8.4:1,
-- dim 4.9:1, disabled 3.7:1. Disabled is deliberately the floor but must stay
-- readable: gated controls (see ControlGates) are common, and a user who cannot
-- read a gated label cannot tell what enabling its parent would unlock.
T.colors = ColorRows [[
coreShadow=0.020,0.039,0.071,1.00
coreInk=0.027,0.063,0.106,1.00
coreSurface=0.035,0.067,0.114,1.00
coreRaised=0.055,0.098,0.161,1.00
coreRim=0.102,0.173,0.259,1.00
coreBlue=0.141,0.365,0.741,1.00
coreGlow=0.231,0.510,0.965,1.00
coreHot=0.357,0.608,1.000,1.00
bg=0.020,0.039,0.071,0.940
panel=0.035,0.067,0.114,0.900
panelNav=0.027,0.063,0.106,0.920
panel2=0.055,0.098,0.161,0.900
header=0.035,0.067,0.114,0.920
border=0.102,0.173,0.259,0.860
borderSoft=0.086,0.149,0.227,0.720
cardBorder=0.102,0.173,0.259,0.820
text=0.933,0.957,1.000,1.00
title=0.957,0.973,1.000,1.00
muted=0.659,0.706,0.780,0.96
searchPlaceholder=0.659,0.706,0.780,0.94
dim=0.500,0.550,0.650,0.92
disabled=0.460,0.510,0.590,0.82
accent=0.231,0.510,0.965,1.00
checkActive=0.141,0.365,0.741,1.00
checkActiveEdge=0.357,0.608,1.000,0.94
checkInactive=0.043,0.090,0.149,1.00
checkInactiveEdge=0.102,0.173,0.259,0.88
accent2=0.851,0.643,0.255,1.00
danger=0.878,0.322,0.369,1.00
ok=0.259,0.827,0.573,1.00
pillBase=0.035,0.067,0.114,0.92
pillBaseSolid=0.055,0.098,0.161,0.94
pillHover=0.063,0.145,0.255,0.96
pillActive=0.141,0.365,0.741,0.96
pillEdge=0.102,0.173,0.259,0.68
pillEdgeButton=0.102,0.173,0.259,0.76
pillEdgeHover=0.231,0.510,0.965,0.58
pillEdgeActive=0.357,0.608,1.000,0.78
pillText=0.839,0.890,0.961,0.98
pillTextActive=0.957,0.973,1.000,1.00
navPillBase=0.020,0.039,0.071,0.86
navPillBaseSolid=0.035,0.067,0.114,0.92
navPillHover=0.063,0.145,0.255,0.96
navPillActive=0.141,0.365,0.741,0.96
navPillEdge=0.102,0.173,0.259,0.62
navPillEdgeHover=0.231,0.510,0.965,0.60
navPillEdgeActive=0.357,0.608,1.000,0.80
navText=0.839,0.890,0.961,0.98
navTextActive=0.957,0.973,1.000,1.00
navHeaderText=0.659,0.706,0.780,0.94
navHeaderHover=0.357,0.608,1.000,1.00
navArrowOpen=0.357,0.608,1.000,1.00
navArrowClosed=0.659,0.706,0.780,0.78
glassShell=0.020,0.039,0.071,0.900
glassRail=0.027,0.063,0.106,0.880
glassHost=0.035,0.067,0.114,0.860
glassStatus=0.035,0.067,0.114,0.880
glassPopup=0.020,0.039,0.071,0.940
guide=0.231,0.510,0.965,0.58
focus=0.055,0.098,0.161,0.78
warning=0.851,0.643,0.255,1.00
]]
T.fontBump = T.fontBump or 1
local function NavIconGrid(rows)
    local out = {}
    for line in M.Lines(rows) do
        local key, x, y = line:match("^(%S+)%s+(%d+)%s+(%d+)$")
        if key then out[key] = { tonumber(x), tonumber(y) } end
    end
    return out
end
local function NavIconColors(rows)
    local out = {}
    for line in M.Lines(rows) do
        local keys, values = line:match("^([^=]+)=(.+)$")
        if keys then
            local c, n = {}, 0
            for value in values:gmatch("[^,]+") do n = n + 1; c[n] = tonumber(value) end
            for key in keys:gmatch("%S+") do out[key] = { c[1], c[2], c[3] } end
        end
    end
    return out
end
local function GlassVariants(rows)
    local out = {}
    for line in M.Lines(rows) do
        local key, rest = line:match("^(%S+)%s+(.+)$")
        local spec = {}
        for field, values in tostring(rest or ""):gmatch("(%w+)=([%d%.,]+)") do
            local c, n = {}, 0
            for value in values:gmatch("[^,]+") do n = n + 1; c[n] = tonumber(value) end
            spec[field] = c
        end
        if key then out[key] = spec end
    end
    return out
end
T.navIconGrid = NavIconGrid [[
home 0 0
uf_player 1 0
uf_target 3 0
uf_targettarget 2 0
uf_focustarget 2 0
uf_focus 2 0
uf_boss 6 2
uf_pet 6 0
opt_bars 7 0
opt_fonts 0 1
auras3 3 1
auras3_buffs 3 1
auras3_debuffs 3 1
auras3_custom 3 1
auras3_styling 3 1
auras3_filters 3 1
opt_castbar 2 1
opt_misc 4 2
opt_colors 4 1
classpower 0 2
gameplay 7 1
groupframes 1 2
gf_layout 2 2
gf_bars 3 2
gf_auras 3 1
gf_indicators 6 1
gf_priority 1 2
modules 4 2
profiles 5 2
]]
T.navIconColors = NavIconColors [[
home=0.231,0.510,0.965
uf_player uf_target uf_targettarget uf_focustarget uf_focus uf_boss uf_pet=0.231,0.510,0.965
opt_bars opt_fonts auras3 auras3_buffs auras3_debuffs auras3_custom auras3_styling auras3_filters opt_castbar opt_misc opt_colors=0.659,0.706,0.780
classpower=0.659,0.706,0.780
gameplay=0.659,0.706,0.780
groupframes gf_layout gf_bars gf_auras gf_indicators gf_priority=0.659,0.706,0.780
modules=0.231,0.510,0.965
profiles=0.659,0.706,0.780
]]
-- Glass material layers, painted back-to-front by `T.ApplyGlass`.
-- `grain` and `glow` were removed deliberately: both sat at 0.008-0.014 alpha
-- carrying a color within ~0.01 of the surface beneath them, so their per-pixel
-- delta landed below one 8-bit level and rendered nothing on any display. They
-- cost three textures per glassed frame to be invisible. Keep new layers above
-- ~0.02 alpha, or with a color that actually differs from the surface below.
T.glassVariants = T.glassVariants or GlassVariants [[
shell tint=0.020,0.039,0.071,0.170 wash=0.035,0.067,0.114,0.026 depth=0.000,0.000,0.000,0.220 top=0.231,0.510,0.965,0.046 bottom=0.000,0.000,0.000,0.300 side=0.102,0.173,0.259,0.044
rail tint=0.027,0.063,0.106,0.165 wash=0.035,0.067,0.114,0.024 depth=0.000,0.000,0.000,0.200 top=0.231,0.510,0.965,0.040 bottom=0.000,0.000,0.000,0.275 side=0.102,0.173,0.259,0.040
host tint=0.035,0.067,0.114,0.150 wash=0.055,0.098,0.161,0.020 depth=0.000,0.000,0.000,0.180 top=0.231,0.510,0.965,0.034 bottom=0.000,0.000,0.000,0.255 side=0.102,0.173,0.259,0.036
status tint=0.035,0.067,0.114,0.145 wash=0.055,0.098,0.161,0.020 depth=0.000,0.000,0.000,0.170 top=0.231,0.510,0.965,0.036 bottom=0.000,0.000,0.000,0.260 side=0.102,0.173,0.259,0.038
popup tint=0.020,0.039,0.071,0.200 wash=0.035,0.067,0.114,0.024 depth=0.000,0.000,0.000,0.220 top=0.231,0.510,0.965,0.038 bottom=0.000,0.000,0.000,0.310 side=0.102,0.173,0.259,0.040
card tint=0.055,0.098,0.161,0.145 wash=0.035,0.067,0.114,0.018 depth=0.000,0.000,0.000,0.175 top=0.231,0.510,0.965,0.030 bottom=0.000,0.000,0.000,0.245 side=0.102,0.173,0.259,0.032
]]
local function DefaultToken(tbl, key, value)
    if tbl[key] == nil then tbl[key] = value end
end
local function DefaultNumberRows(tbl, rows)
    for line in M.Lines(rows) do
        local key, value = line:match("^(%S+)%s+([%d%.]+)$")
        if key then DefaultToken(tbl, key, tonumber(value)) end
    end
end
T.gradients = T.gradients or {}
DefaultToken(T.gradients, "shell", { orientation = "VERTICAL", from = { 0.055, 0.098, 0.161, 0.30 }, to = { 0.020, 0.039, 0.071, 0.70 }, inset = 3 })
DefaultToken(T.gradients, "rail", { orientation = "VERTICAL", from = { 0.055, 0.098, 0.161, 0.28 }, to = { 0.027, 0.063, 0.106, 0.62 }, inset = 3 })
DefaultToken(T.gradients, "host", { orientation = "VERTICAL", from = { 0.055, 0.098, 0.161, 0.24 }, to = { 0.035, 0.067, 0.114, 0.58 }, inset = 3 })
DefaultToken(T.gradients, "status", { orientation = "VERTICAL", from = { 0.055, 0.098, 0.161, 0.26 }, to = { 0.035, 0.067, 0.114, 0.58 }, inset = 2 })
DefaultToken(T.gradients, "card", { orientation = "VERTICAL", from = { 0.055, 0.098, 0.161, 0.24 }, to = { 0.035, 0.067, 0.114, 0.56 }, inset = 2 })
DefaultToken(T.gradients, "popup", { orientation = "VERTICAL", from = { 0.055, 0.098, 0.161, 0.28 }, to = { 0.020, 0.039, 0.071, 0.66 }, inset = 2 })
DefaultToken(T.gradients, "guide", { orientation = "VERTICAL", from = { 0.231, 0.510, 0.965, 0.055 }, to = { 0.035, 0.067, 0.114, 0.40 }, inset = 2 })
DefaultToken(T.gradients, "warning", { orientation = "VERTICAL", from = { 0.220, 0.160, 0.060, 0.26 }, to = { 0.055, 0.039, 0.018, 0.36 }, inset = 2 })
DefaultToken(T.gradients, "button", { orientation = "VERTICAL", amountTop = 0.16, amountBottom = -0.20 })
DefaultToken(T.gradients, "sliderFill", { orientation = "HORIZONTAL", from = { 0.231, 0.510, 0.965, 0.68 }, to = { 0.141, 0.365, 0.741, 0.82 } })
T.motion = T.motion or {}
DefaultNumberRows(T.motion, [[
fast 0.075
standard 0.105
soft 0.150
dropdownIn 0.095
dropdownOut 0.075
popupIn 0.105
popupOut 0.085
focusIn 0.095
focusOut 0.080
accordionIn 0.135
accordionOut 0.105
contentIn 0.095
contentOut 0.075
controlFocusIn 0.060
controlFocusOut 0.055
controlFeedback 0.100
]])
T.motionPolicy = T.motionPolicy or {}
DefaultNumberRows(T.motionPolicy, [[
min 0.045
max 0.160
popupScaleFrom 0.988
popupScaleOut 0.994
]])
T.dropdownMotion = T.dropdownMotion or {}
DefaultToken(T.dropdownMotion, "listFadeIn", T.motion.dropdownIn)
DefaultToken(T.dropdownMotion, "listFadeOut", T.motion.dropdownOut)
DefaultToken(T.dropdownMotion, "focusFadeIn", T.motion.focusIn)
DefaultToken(T.dropdownMotion, "focusFadeOut", T.motion.focusOut)
T.motionProfiles = T.motionProfiles or {}
DefaultToken(T.motionProfiles, "dropdownIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "dropdownIn", smoothing = "OUT" })
DefaultToken(T.motionProfiles, "dropdownOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "dropdownOut", smoothing = "IN" })
DefaultToken(T.motionProfiles, "popupIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "popupIn", smoothing = "OUT", scaleFrom = T.motionPolicy.popupScaleFrom, scaleTo = 1, scaleOrigin = "CENTER" })
DefaultToken(T.motionProfiles, "popupOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "popupOut", smoothing = "IN", scaleFrom = 1, scaleTo = T.motionPolicy.popupScaleOut, scaleOrigin = "CENTER" })
DefaultToken(T.motionProfiles, "focusIn", { type = "alpha", fromCurrent = true, toAlpha = 1, duration = "focusIn", smoothing = "OUT" })
DefaultToken(T.motionProfiles, "focusOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "focusOut", smoothing = "IN" })
DefaultToken(T.motionProfiles, "accordionIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "accordionIn", smoothing = "OUT" })
DefaultToken(T.motionProfiles, "accordionOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "accordionOut", smoothing = "IN" })
DefaultToken(T.motionProfiles, "contentIn", { type = "alpha", fromAlpha = 0, toAlpha = 1, duration = "contentIn", smoothing = "OUT" })
DefaultToken(T.motionProfiles, "contentOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "contentOut", smoothing = "IN" })
DefaultToken(T.motionProfiles, "controlFocusIn", { type = "alpha", fromCurrent = true, toAlpha = 1, duration = "controlFocusIn", smoothing = "OUT" })
DefaultToken(T.motionProfiles, "controlFocusOut", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "controlFocusOut", smoothing = "IN" })
DefaultToken(T.motionProfiles, "controlFeedback", { type = "alpha", fromCurrent = true, toAlpha = 0, duration = "controlFeedback", smoothing = "OUT" })
T.materials = T.materials or {}
DefaultToken(T.materials, "shell", { bg = T.colors.glassShell, border = T.colors.border, glass = "shell", gradient = "shell" })
DefaultToken(T.materials, "rail", { bg = T.colors.glassRail, border = T.colors.borderSoft, glass = "rail", gradient = "rail" })
DefaultToken(T.materials, "host", { bg = T.colors.glassHost, border = T.colors.borderSoft, glass = "host", gradient = "host" })
DefaultToken(T.materials, "status", { bg = T.colors.glassStatus, border = T.colors.borderSoft, glass = "status", gradient = "status" })
DefaultToken(T.materials, "card", { bg = T.colors.panel2, border = T.colors.cardBorder or T.colors.borderSoft, glass = "card", gradient = "card" })
DefaultToken(T.materials, "popup", { bg = T.colors.glassPopup, border = T.colors.borderSoft, glass = "popup", gradient = "popup" })
DefaultToken(T.materials, "focus", { veil = "dropdown" })
DefaultToken(T.materials, "guide", { bg = { 0.018, 0.052, 0.082, 0.28 }, border = T.colors.guide, glass = "card", gradient = "guide" })
DefaultToken(T.materials, "warning", { bg = { 0.105, 0.082, 0.052, 0.34 }, border = { 0.480, 0.360, 0.200, 0.62 }, glass = "card", gradient = "warning" })
T.focusVeils = T.focusVeils or {}
T.focusVeils.dropdown = T.focusVeils.dropdown or {
    { key = "_msuf2FocusDim", layer = "BACKGROUND", subLevel = 0, color = { 0.000, 0.000, 0.000, 0.145 } },
    { key = "_msuf2FocusHaze", layer = "BACKGROUND", subLevel = 1, color = { 0.010, 0.014, 0.026, 0.045 } },
    { key = "_msuf2FocusSmearA", layer = "BORDER", subLevel = 0, texture = "bgSmooth", points = { -5, 5, 5, -5 }, color = { 0.018, 0.026, 0.052, 0.032 }, blend = "BLEND" },
    { key = "_msuf2FocusSmearB", layer = "BORDER", subLevel = 1, texture = "bgSmooth", points = { 4, -4, -4, 4 }, texCoord = { 0, 0, 1, 0, 0, 1, 1, 1 }, color = { 0.014, 0.022, 0.046, 0.026 }, blend = "BLEND" },
    { key = "_msuf2FocusWash", layer = "BORDER", subLevel = 2, texture = "bgSmooth", color = { 0.024, 0.034, 0.068, 0.040 }, blend = "BLEND" },
    { key = "_msuf2FocusGrain", layer = "BORDER", subLevel = 3, texture = "bgCharcoal", color = { 0.035, 0.040, 0.070, 0.052 }, blend = "BLEND" },
}
T.focusVeils.edit = T.focusVeils.edit or {
    { key = "_msuf2FocusDim", layer = "BACKGROUND", subLevel = 0, color = { 0.000, 0.000, 0.000, 0.105 } },
    { key = "_msuf2FocusHaze", layer = "BACKGROUND", subLevel = 1, color = { 0.010, 0.014, 0.026, 0.040 } },
    { key = "_msuf2FocusWash", layer = "BORDER", subLevel = 0, texture = "bgSmooth", color = { 0.018, 0.030, 0.060, 0.038 }, blend = "BLEND" },
    { key = "_msuf2FocusGrain", layer = "BORDER", subLevel = 1, texture = "bgCharcoal", color = { 0.030, 0.035, 0.060, 0.042 }, blend = "BLEND" },
}

-- Menu accent override (Misc > Menu behavior). The stock midnight accent family
-- is rewritten IN PLACE (same tables, alphas preserved) so every consumer that
-- bakes token colors at build time picks up the chosen accent transparently.
-- Structural surfaces and the green/red/amber semantics stay untouched. This
-- must run before the first themed frame is built; a mid-session change needs
-- a UI reload, mirroring the locale contract.
local ACCENT_SOURCE_TONES = {
    { 0.141, 0.365, 0.741 }, -- deep (coreBlue family)
    { 0.231, 0.510, 0.965 }, -- base (coreGlow family)
    { 0.357, 0.608, 1.000 }, -- bright (coreHot family)
}
-- Non-midnight hues can be much more luminous than the stock blue at the same
-- numeric value (especially class greens). Keep their shared interaction ramp
-- subdued so nav, tabs, pinned controls, focus and hover highlights stay accents
-- instead of becoming the brightest surfaces in the menu. Midnight never enters
-- ApplyMenuAccent(), so its shipped palette remains byte-for-byte unchanged.
local NON_MIDNIGHT_ACCENT_VALUE_SCALE = 0.72
local NON_MIDNIGHT_ACCENT_MIN_VALUE = 0.40
local NON_MIDNIGHT_ACCENT_BRIGHT_MAX_VALUE = 0.82
local NON_MIDNIGHT_ACCENT_BRIGHT_SCALE = 1.14
local function AccentToneIndex(color)
    for i = 1, 3 do
        local ref = ACCENT_SOURCE_TONES[i]
        if math.abs(color[1] - ref[1]) < 0.006
            and math.abs(color[2] - ref[2]) < 0.006
            and math.abs(color[3] - ref[3]) < 0.006 then
            return i
        end
    end
    return nil
end
local function SwapAccentDeep(tbl, tones, depth)
    for _, value in pairs(tbl) do
        if type(value) == "table" then
            if type(value[1]) == "number" and type(value[2]) == "number" and type(value[3]) == "number" then
                local index = AccentToneIndex(value)
                if index then
                    local tone = tones[index]
                    value[1], value[2], value[3] = tone[1], tone[2], tone[3]
                    value._msuf2AccentTone = true
                end
            elseif depth < 3 then
                SwapAccentDeep(value, tones, depth + 1)
            end
        end
    end
end
-- Midnight keeps its authored blue hover. Non-midnight themes derive hover
-- from the same accent ramp as selection, at a lower alpha so pointer feedback
-- remains subordinate to the persistent active state.
local function ApplyAccentNavHoverColors(tones)
    local mappings = {
        { "navPillHover", tones[1], 0.92 },
        { "navPillEdgeHover", tones[2], 0.60 },
        { "navHeaderHover", tones[3], 1.00 },
    }
    for i = 1, #mappings do
        local mapping = mappings[i]
        local color, tone = T.colors[mapping[1]], mapping[2]
        if type(color) == "table" and type(tone) == "table" then
            color[1], color[2], color[3], color[4] = tone[1], tone[2], tone[3], mapping[3]
            color._msuf2AccentTone = true
        end
    end
end
local function RGBToHSV(r, g, b)
    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)
    local delta = maxc - minc
    local h = 0
    if delta > 0 then
        if maxc == r then
            h = ((g - b) / delta) % 6
        elseif maxc == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h * 60
    end
    local s = maxc > 0 and delta / maxc or 0
    return h, s, maxc
end
local function HSVToRGB(h, s, v)
    local c = v * s
    local hp = (h % 360) / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local r, g, b
    if hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    local m = v - c
    return r + m, g + m, b + m
end
-- WCAG relative luminance, used to re-validate the text ramp after an accent has
-- rewritten the palette. Rotating hue at a constant HSV value is NOT luminance
-- preserving -- green contributes ~10x what blue does -- so an accent can lift a
-- surface out from under the low-contrast end of the ramp, or make an accent-
-- tinted pill bright enough that near-white labels on it stop being readable.
local function Linearize(c)
    if c <= 0.03928 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end
local function RelativeLuminance(c)
    return 0.2126 * Linearize(c[1]) + 0.7152 * Linearize(c[2]) + 0.0722 * Linearize(c[3])
end
local function ContrastRatio(a, b)
    local la, lb = RelativeLuminance(a), RelativeLuminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end
-- Text tokens carry alpha; flatten onto the surface before measuring.
local function CompositeOver(fg, surface)
    local a = fg[4] or 1
    if a >= 1 then return fg end
    return {
        a * fg[1] + (1 - a) * surface[1],
        a * fg[2] + (1 - a) * surface[2],
        a * fg[3] + (1 - a) * surface[3],
    }
end
--- Re-values a text token until it clears `floor` against the surface it is drawn
--- on, keeping its hue and saturation. Sweeps the whole value axis rather than
--- stepping away from the surface: a near-white label on a bright accent pill
--- (gold class colors, jade) has no headroom upward, and the correct answer
--- there is dark text on a light surface, not a brighter white.
--- Picks the qualifying value closest to the original so the palette moves as
--- little as possible; if nothing clears the floor it takes the best available.
--- The surface is treated as opaque -- what sits behind a translucent panel is
--- the game world, so the surface's own RGB is the only honest reference.
local function EnforceContrast(colorKey, surfaceKey, floor)
    local c, surface = T.colors[colorKey], T.colors[surfaceKey]
    if type(c) ~= "table" or type(surface) ~= "table" or type(c[1]) ~= "number" then return end
    if ContrastRatio(CompositeOver(c, surface), surface) >= floor then return end
    local h, s, v0 = RGBToHSV(c[1], c[2], c[3])
    local nearestV, nearestGap, bestV, bestRatio = nil, math.huge, v0, -1
    for i = 0, 40 do
        local v = i / 40
        local r, g, b = HSVToRGB(h, s, v)
        local ratio = ContrastRatio(CompositeOver({ r, g, b, c[4] }, surface), surface)
        if ratio >= floor then
            local gap = v > v0 and (v - v0) or (v0 - v)
            if gap < nearestGap then nearestV, nearestGap = v, gap end
        end
        if ratio > bestRatio then bestV, bestRatio = v, ratio end
    end
    c[1], c[2], c[3] = HSVToRGB(h, s, nearestV or bestV)
end
-- Text on a structural (neutral) surface: the surface is the design, so the
-- label moves. Floors sit at or below what stock midnight already achieves, so
-- this only ever engages to repair an accent -- it never restyles the shipped
-- palette.
local TEXT_CONTRAST_FLOORS = {
    { "text", "panel", 7.0 },
    { "title", "panel", 7.0 },
    { "muted", "panel", 4.5 },
    { "searchPlaceholder", "panel", 4.5 },
    { "dim", "panel", 4.5 },
    { "disabled", "panel", 3.0 },
    { "navText", "panelNav", 4.5 },
    { "navHeaderText", "panelNav", 4.5 },
    { "pillText", "pillBaseSolid", 4.5 },
}
--- Re-values an accent-colored *surface* until the label drawn on it clears
--- `floor`. The surface's own alpha is composited over the backdrop it sits on,
--- which is what actually reaches the screen.
local function EnforceSurfaceContrast(surfaceKey, backdropKey, textKey, floor)
    local surface, backdrop, text = T.colors[surfaceKey], T.colors[backdropKey], T.colors[textKey]
    if type(surface) ~= "table" or type(backdrop) ~= "table" or type(text) ~= "table" then return end
    if type(surface[1]) ~= "number" or type(text[1]) ~= "number" then return end
    local function RatioAt(candidate)
        return ContrastRatio(CompositeOver(text, candidate), candidate)
    end
    if RatioAt(CompositeOver(surface, backdrop)) >= floor then return end
    local h, s, v0 = RGBToHSV(surface[1], surface[2], surface[3])
    local nearestV, nearestGap, bestV, bestRatio = nil, math.huge, v0, -1
    for i = 0, 40 do
        local v = i / 40
        local r, g, b = HSVToRGB(h, s, v)
        local ratio = RatioAt(CompositeOver({ r, g, b, surface[4] }, backdrop))
        if ratio >= floor then
            local gap = v > v0 and (v - v0) or (v0 - v)
            if gap < nearestGap then nearestV, nearestGap = v, gap end
        end
        if ratio > bestRatio then bestV, bestRatio = v, ratio end
    end
    surface[1], surface[2], surface[3] = HSVToRGB(h, s, nearestV or bestV)
end
-- Text on an accent-colored surface: here the *surface* moves instead. An active
-- pill is meant to carry a near-white label in every accent, and a bright pick
-- (gold class colors, jade) breaks that. Darkening the pill to a deeper shade of
-- the same accent preserves the design language; flipping the label to black
-- would not, and on a marginal failure it looks like a rendering bug.
-- surface, backdrop it sits on, label drawn on it, minimum contrast.
local SURFACE_CONTRAST_FLOORS = {
    { "navPillActive", "panelNav", "navTextActive", 4.5 },
    { "pillActive", "panel", "pillTextActive", 4.5 },
}
local function EnforceTextContrast()
    for i = 1, #TEXT_CONTRAST_FLOORS do
        local row = TEXT_CONTRAST_FLOORS[i]
        EnforceContrast(row[1], row[2], row[3])
    end
    for i = 1, #SURFACE_CONTRAST_FLOORS do
        local row = SURFACE_CONTRAST_FLOORS[i]
        EnforceSurfaceContrast(row[1], row[2], row[3], row[4])
    end
end
-- The structural midnight family is a blue-hue ramp. When surface tinting is
-- enabled the whole menu body is rotated onto the accent hue (keeping each
-- color's own lightness and relative saturation). Semantic colors (ok green,
-- danger red, warning amber) sit outside the blue band and are skipped by
-- construction. Tinting is opt-in: the default is that the accent owns
-- interaction (pills, focus, highlights) while surfaces stay midnight, which is
-- the conventional split and keeps the addon's identity under any class color.
local REHUE_MIN_HUE, REHUE_MAX_HUE = 185, 262
local function LooksLikeColor(t)
    local n = #t
    if n < 3 or n > 4 then return false end
    for i = 1, n do
        local v = t[i]
        if type(v) ~= "number" or v < 0 or v > 1 then return false end
    end
    return true
end
local function RehueColor(c)
    if c._msuf2AccentTone or c._msuf2Rehued then return end
    local h, s, v = RGBToHSV(c[1], c[2], c[3])
    if s <= 0.01 then return end
    if h < REHUE_MIN_HUE or h > REHUE_MAX_HUE then return end
    c._msuf2Rehued = true
    local ns = s * (T._menuAccentSatScale or 1)
    if ns > 1 then ns = 1 end
    c[1], c[2], c[3] = HSVToRGB(T._menuAccentHue or 0, ns, v)
end
local function RehueDeep(tbl, depth)
    for _, value in pairs(tbl) do
        if type(value) == "table" then
            if LooksLikeColor(value) then
                RehueColor(value)
            elseif depth < 4 then
                RehueDeep(value, depth + 1)
            end
        end
    end
end
--- Re-hues a hardcoded blue-family color literal in place (once) when a custom
--- accent is active. For paint-path literals that live outside the token tables.
function T.MenuAccentRehueLiteral(color)
    if type(color) ~= "table" then return color end
    if T._menuAccentApplied ~= nil and T._menuAccentApplied ~= "midnight"
        and T._menuAccentHue ~= nil and LooksLikeColor(color) then
        RehueColor(color)
    end
    return color
end
function T.MenuAccentHexToRGB(hex)
    local r, g, b = tostring(hex or ""):match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
    if not r then return nil end
    return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end
local function AccentColorByte(value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 elseif value > 1 then value = 1 end
    return math.floor(value * 255 + 0.5)
end
function T.MenuAccentRGBToHex(r, g, b)
    return string.format("%02x%02x%02x", AccentColorByte(r), AccentColorByte(g), AccentColorByte(b))
end
local function PlayerClassAccent()
    local UnitClass = _G.UnitClass
    local class = type(UnitClass) == "function" and select(2, UnitClass("player")) or nil
    local colors = _G.CUSTOM_CLASS_COLORS or _G.RAID_CLASS_COLORS
    local c = class and type(colors) == "table" and colors[class] or nil
    if type(c) ~= "table" or type(c.r) ~= "number" then return nil end
    return c.r, c.g, c.b, class
end
-- Curated accent presets selectable directly from the dropdown (no picker).
T.MENU_ACCENT_PRESETS = T.MENU_ACCENT_PRESETS or {
    ember = "e0603c",
    jade = "2fbf8f",
    violet = "8b5cf6",
}
--- Opt-in: rotate the structural surfaces onto the accent hue too, instead of
--- letting the accent own only the interactive layer. Default off.
function T.MenuAccentTintsSurfaces(g)
    return type(g) == "table" and g.menuAccentTintSurfaces == true
end
--- Stable identity of the accent a given general DB describes. Compared against
--- `T._menuAccentApplied` to decide whether a change needs a reload prompt.
--- Surface tinting is part of the identity: toggling it changes what the palette
--- bakes at build time, so it needs the same reload the accent itself does.
function T.MenuAccentSignature(g)
    local mode = type(g) == "table" and g.menuAccent or nil
    local suffix = T.MenuAccentTintsSurfaces(g) and "+tint" or ""
    if mode == "class" then
        local r, _, _, class = PlayerClassAccent()
        if r then return "class:" .. tostring(class) .. suffix end
    elseif mode == "custom" then
        local hex = type(g) == "table" and g.menuAccentColor or nil
        if T.MenuAccentHexToRGB(hex) then return "custom:" .. tostring(hex):lower() .. suffix end
    elseif mode ~= nil and T.MENU_ACCENT_PRESETS[mode] then
        return "preset:" .. tostring(mode) .. suffix
    end
    return "midnight"
end
--- True when a non-midnight accent is active this session. Token-aware controls
--- use this for color selection; nav may use its neutral fill textures, but the
--- shared visual-width/cap contract keeps geometry identical to Midnight.
function T.MenuAccentActive()
    local applied = T._menuAccentApplied
    return applied ~= nil and applied ~= "midnight"
end
--- True only when the applied non-midnight accent also owns structural
--- surfaces. Kept as an applied-session query so every art owner follows the
--- same reload boundary as the token mutation itself.
function T.MenuAccentSurfacesTinted()
    local applied = T._menuAccentApplied
    return type(applied) == "string" and applied ~= "midnight"
        and applied:sub(-5) == "+tint"
end
--- Idempotent: applies the saved accent once per session and records what was
--- applied. Returns nil (and retries on the next call) while the DB is not
--- readable yet.
function T.ApplyMenuAccent()
    if T._menuAccentApplied then return T._menuAccentApplied end
    local M2 = MSUF.MSUF2
    local g = M2 and type(M2.GetGeneralDB) == "function" and M2.GetGeneralDB() or nil
    if type(g) ~= "table" then return nil end
    local sig = T.MenuAccentSignature(g)
    T._menuAccentApplied = sig
    if sig == "midnight" then return sig end
    local r, gr, b
    if g.menuAccent == "class" then
        r, gr, b = PlayerClassAccent()
    else
        local presetHex = T.MENU_ACCENT_PRESETS[g.menuAccent]
        r, gr, b = T.MenuAccentHexToRGB(presetHex or g.menuAccentColor)
    end
    if not r then return sig end
    -- Keep murky picks readable, then dim every non-midnight pick before
    -- deriving the shared deep/base/bright interaction ramp.
    local maxComponent = math.max(r, gr, b)
    if maxComponent <= 0.001 then
        r, gr, b = 0.45, 0.45, 0.45
        maxComponent = 0.45
    elseif maxComponent < 0.45 then
        local lift = 0.45 / maxComponent
        r, gr, b = r * lift, gr * lift, b * lift
        maxComponent = 0.45
    end
    local dimmedValue = math.max(
        NON_MIDNIGHT_ACCENT_MIN_VALUE,
        maxComponent * NON_MIDNIGHT_ACCENT_VALUE_SCALE
    )
    local dim = dimmedValue / maxComponent
    r, gr, b = r * dim, gr * dim, b * dim
    maxComponent = dimmedValue
    local brightValue = math.min(
        NON_MIDNIGHT_ACCENT_BRIGHT_MAX_VALUE,
        maxComponent * NON_MIDNIGHT_ACCENT_BRIGHT_SCALE
    )
    local brightScale = brightValue / maxComponent
    local tones = {
        { r * 0.72, gr * 0.72, b * 0.72 },
        { r, gr, b },
        { r * brightScale, gr * brightScale, b * brightScale },
    }
    SwapAccentDeep(T.colors, tones, 1)
    SwapAccentDeep(T.navIconColors, tones, 1)
    SwapAccentDeep(T.glassVariants, tones, 1)
    SwapAccentDeep(T.gradients, tones, 1)
    ApplyAccentNavHoverColors(tones)
    -- Optional second pass: rotate the structural midnight body onto the accent
    -- hue so the whole menu follows the accent, not just interactive highlights.
    -- The saturation scale keeps a muted accent from over-tinting the surfaces
    -- (0.761 is the stock coreGlow saturation the ramp was tuned against).
    if T.MenuAccentTintsSurfaces(g) then
        local hue, sat = RGBToHSV(r, gr, b)
        T._menuAccentHue = hue
        local satScale = sat / 0.761
        if satScale > 1.05 then satScale = 1.05 end
        T._menuAccentSatScale = satScale
        RehueDeep(T.colors, 1)
        RehueDeep(T.navIconColors, 1)
        RehueDeep(T.glassVariants, 1)
        RehueDeep(T.gradients, 1)
        RehueDeep(T.focusVeils, 1)
    end
    -- Runs for every accent, tinted or not: the tone swap alone already repaints
    -- pill/nav backgrounds in the accent color, so a bright pick (amber class
    -- colors, jade) can leave near-white labels sitting on a light surface.
    EnforceTextContrast()
    return sig
end
