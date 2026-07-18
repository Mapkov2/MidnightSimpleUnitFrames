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
disabled=0.388,0.439,0.537,0.68
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
T.glassVariants = T.glassVariants or GlassVariants [[
shell tint=0.020,0.039,0.071,0.170 wash=0.035,0.067,0.114,0.026 depth=0.000,0.000,0.000,0.220 grain=0.035,0.067,0.114,0.014 top=0.231,0.510,0.965,0.046 bottom=0.000,0.000,0.000,0.300 glow=0.231,0.510,0.965,0.014 side=0.102,0.173,0.259,0.044
rail tint=0.027,0.063,0.106,0.165 wash=0.035,0.067,0.114,0.024 depth=0.000,0.000,0.000,0.200 grain=0.035,0.067,0.114,0.014 top=0.231,0.510,0.965,0.040 bottom=0.000,0.000,0.000,0.275 glow=0.231,0.510,0.965,0.012 side=0.102,0.173,0.259,0.040
host tint=0.035,0.067,0.114,0.150 wash=0.055,0.098,0.161,0.020 depth=0.000,0.000,0.000,0.180 grain=0.035,0.067,0.114,0.012 top=0.231,0.510,0.965,0.034 bottom=0.000,0.000,0.000,0.255 glow=0.231,0.510,0.965,0.010 side=0.102,0.173,0.259,0.036
status tint=0.035,0.067,0.114,0.145 wash=0.055,0.098,0.161,0.020 depth=0.000,0.000,0.000,0.170 top=0.231,0.510,0.965,0.036 bottom=0.000,0.000,0.000,0.260 glow=0.231,0.510,0.965,0.012 side=0.102,0.173,0.259,0.038
popup tint=0.020,0.039,0.071,0.200 wash=0.035,0.067,0.114,0.024 depth=0.000,0.000,0.000,0.220 grain=0.035,0.067,0.114,0.014 top=0.231,0.510,0.965,0.038 bottom=0.000,0.000,0.000,0.310 glow=0.231,0.510,0.965,0.012 side=0.102,0.173,0.259,0.040
card tint=0.055,0.098,0.161,0.145 wash=0.035,0.067,0.114,0.018 depth=0.000,0.000,0.000,0.175 grain=0.035,0.067,0.114,0.010 top=0.231,0.510,0.965,0.030 bottom=0.000,0.000,0.000,0.245 glow=0.231,0.510,0.965,0.008 side=0.102,0.173,0.259,0.032
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
