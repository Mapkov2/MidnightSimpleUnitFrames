local addonName, MSUF = ...
MSUF = MSUF or {}
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
-- Dark Apple-glass palette derived from Media/MSUF_MinimapIcon.tga.
-- Keep blue UI values on these RGB triplets; use alpha/gradients for variation.
T.colors = ColorRows [[
coreShadow=0.006,0.016,0.032,1.00
coreInk=0.010,0.024,0.046,1.00
coreSurface=0.014,0.038,0.072,1.00
coreRaised=0.026,0.070,0.110,1.00
coreRim=0.060,0.110,0.210,1.00
coreBlue=0.115,0.300,0.650,1.00
coreGlow=0.150,0.380,0.780,1.00
coreHot=0.225,0.470,0.940,1.00
bg=0.006,0.016,0.032,0.820
panel=0.010,0.024,0.046,0.620
panelNav=0.010,0.024,0.046,0.660
panel2=0.014,0.038,0.072,0.660
header=0.014,0.038,0.072,0.560
border=0.090,0.180,0.380,0.540
borderSoft=0.075,0.150,0.310,0.440
cardBorder=0.085,0.165,0.350,0.500
text=0.880,0.910,1.000,1.00
title=0.890,0.940,1.000,1.00
muted=0.620,0.700,0.820,0.90
searchPlaceholder=0.620,0.700,0.820,0.96
dim=0.360,0.460,0.600,0.82
accent=0.150,0.380,0.780,1.00
checkActive=0.105,0.250,0.560,1.00
checkActiveEdge=0.225,0.470,0.940,0.92
checkInactive=0.018,0.055,0.115,1.00
checkInactiveEdge=0.075,0.150,0.310,0.82
accent2=0.965,0.760,0.150,1.00
danger=0.880,0.280,0.280,1.00
ok=0.240,0.820,0.460,1.00
pillBase=0.010,0.024,0.046,0.84
pillBaseSolid=0.014,0.038,0.072,0.90
pillHover=0.040,0.075,0.145,0.90
pillActive=0.160,0.310,0.760,0.96
pillEdge=0.060,0.110,0.210,0.42
pillEdgeButton=0.060,0.110,0.210,0.50
pillEdgeHover=0.150,0.380,0.780,0.42
pillEdgeActive=0.225,0.470,0.940,0.72
pillText=0.820,0.890,1.000,0.94
pillTextActive=0.920,0.960,1.000,1.00
navPillBase=0.008,0.020,0.038,0.74
navPillBaseSolid=0.010,0.030,0.055,0.82
navPillHover=0.040,0.075,0.145,0.88
navPillActive=0.160,0.310,0.760,0.96
navPillEdge=0.060,0.110,0.210,0.38
navPillEdgeHover=0.150,0.380,0.780,0.44
navPillEdgeActive=0.225,0.470,0.940,0.74
navText=0.840,0.900,1.000,0.96
navTextActive=0.970,0.990,1.000,1.00
navHeaderText=0.620,0.700,0.820,0.86
navHeaderHover=0.150,0.380,0.780,0.92
navArrowOpen=1.000,0.760,0.250,1.00
navArrowClosed=1.000,0.560,0.060,1.00
glassShell=0.006,0.016,0.032,0.660
glassRail=0.010,0.024,0.046,0.620
glassHost=0.010,0.024,0.046,0.520
glassStatus=0.014,0.038,0.072,0.500
glassPopup=0.006,0.016,0.032,0.700
guide=0.150,0.380,0.780,0.46
focus=0.026,0.070,0.110,0.64
warning=0.920,0.680,0.250,1.00
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
modules 4 2
profiles 5 2
]]
T.navIconColors = NavIconColors [[
home=0.150,0.380,0.780
uf_player uf_target uf_targettarget uf_focustarget uf_focus uf_boss uf_pet=0.150,0.380,0.780
opt_bars opt_fonts auras3 auras3_buffs auras3_debuffs auras3_custom auras3_styling auras3_filters opt_castbar opt_misc opt_colors=0.88,0.74,0.36
classpower=0.35,0.82,0.50
gameplay=0.72,0.50,0.92
groupframes gf_layout gf_bars gf_auras gf_indicators=0.520,0.610,0.720
modules=0.150,0.380,0.780
profiles=0.90,0.62,0.30
]]
T.glassVariants = T.glassVariants or GlassVariants [[
shell tint=0.006,0.016,0.032,0.170 wash=0.014,0.038,0.072,0.026 depth=0.000,0.000,0.000,0.220 grain=0.014,0.038,0.072,0.014 top=0.150,0.380,0.780,0.046 bottom=0.000,0.000,0.000,0.300 glow=0.150,0.380,0.780,0.014 side=0.060,0.110,0.210,0.044
rail tint=0.010,0.024,0.046,0.165 wash=0.014,0.038,0.072,0.024 depth=0.000,0.000,0.000,0.200 grain=0.014,0.038,0.072,0.014 top=0.150,0.380,0.780,0.040 bottom=0.000,0.000,0.000,0.275 glow=0.150,0.380,0.780,0.012 side=0.060,0.110,0.210,0.040
host tint=0.010,0.024,0.046,0.150 wash=0.014,0.038,0.072,0.020 depth=0.000,0.000,0.000,0.180 grain=0.014,0.038,0.072,0.012 top=0.150,0.380,0.780,0.034 bottom=0.000,0.000,0.000,0.255 glow=0.150,0.380,0.780,0.010 side=0.060,0.110,0.210,0.036
status tint=0.014,0.038,0.072,0.145 wash=0.026,0.070,0.110,0.020 depth=0.000,0.000,0.000,0.170 top=0.150,0.380,0.780,0.036 bottom=0.000,0.000,0.000,0.260 glow=0.150,0.380,0.780,0.012 side=0.060,0.110,0.210,0.038
popup tint=0.006,0.016,0.032,0.200 wash=0.014,0.038,0.072,0.024 depth=0.000,0.000,0.000,0.220 grain=0.014,0.038,0.072,0.014 top=0.150,0.380,0.780,0.038 bottom=0.000,0.000,0.000,0.310 glow=0.150,0.380,0.780,0.012 side=0.060,0.110,0.210,0.040
card tint=0.010,0.024,0.046,0.145 wash=0.014,0.038,0.072,0.018 depth=0.000,0.000,0.000,0.175 grain=0.014,0.038,0.072,0.010 top=0.150,0.380,0.780,0.030 bottom=0.000,0.000,0.000,0.245 glow=0.150,0.380,0.780,0.008 side=0.060,0.110,0.210,0.032
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
DefaultToken(T.gradients, "shell", { orientation = "VERTICAL", from = { 0.014, 0.038, 0.072, 0.30 }, to = { 0.006, 0.016, 0.032, 0.70 }, inset = 3 })
DefaultToken(T.gradients, "rail", { orientation = "VERTICAL", from = { 0.014, 0.038, 0.072, 0.28 }, to = { 0.010, 0.024, 0.046, 0.62 }, inset = 3 })
DefaultToken(T.gradients, "host", { orientation = "VERTICAL", from = { 0.014, 0.038, 0.072, 0.24 }, to = { 0.010, 0.024, 0.046, 0.58 }, inset = 3 })
DefaultToken(T.gradients, "status", { orientation = "VERTICAL", from = { 0.014, 0.038, 0.072, 0.26 }, to = { 0.010, 0.024, 0.046, 0.58 }, inset = 2 })
DefaultToken(T.gradients, "card", { orientation = "VERTICAL", from = { 0.014, 0.038, 0.072, 0.24 }, to = { 0.010, 0.024, 0.046, 0.56 }, inset = 2 })
DefaultToken(T.gradients, "popup", { orientation = "VERTICAL", from = { 0.014, 0.038, 0.072, 0.28 }, to = { 0.006, 0.016, 0.032, 0.66 }, inset = 2 })
DefaultToken(T.gradients, "guide", { orientation = "VERTICAL", from = { 0.150, 0.380, 0.780, 0.055 }, to = { 0.010, 0.024, 0.046, 0.40 }, inset = 2 })
DefaultToken(T.gradients, "warning", { orientation = "VERTICAL", from = { 0.260, 0.180, 0.080, 0.26 }, to = { 0.044, 0.028, 0.012, 0.36 }, inset = 2 })
DefaultToken(T.gradients, "button", { orientation = "VERTICAL", amountTop = 0.16, amountBottom = -0.20 })
DefaultToken(T.gradients, "sliderFill", { orientation = "HORIZONTAL", from = { 0.150, 0.380, 0.780, 0.62 }, to = { 0.030, 0.070, 0.160, 0.78 } })
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
