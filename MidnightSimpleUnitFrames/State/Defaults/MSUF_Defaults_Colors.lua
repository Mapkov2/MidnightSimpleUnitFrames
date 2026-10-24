-- Bar color, gradient, aggro and outline default stages.
local _, MSUF = ...
local Parts = MSUF.DefaultsParts
local IS_CLASSIC_FAMILY = Parts.IS_CLASSIC_FAMILY
local barColorStages = {}
function barColorStages.Background(profileDB, g)
    MSUF.DefaultsSchema.SeedGeneral(g, "base_01")
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreDarkBgBrightness)
    --- When true, dark mode uses the bar-background tint color directly (no brightness dimming).
    --- Allows fully custom background colors (including white) in dark mode.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreDarkBgCustomColor)
    if g.classBarBgR == nil or g.classBarBgG == nil or g.classBarBgB == nil then
        g.classBarBgR = 0.0   --- default: black background
        g.classBarBgG = 0.0
        g.classBarBgB = 0.0
    end
    --- If enabled, bar background tint color follows the current HP bar color (class/reaction/unified),
    --- instead of using the custom tint swatch.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreBarBgMatchHPColor)
    --- If enabled, the HP background uses the unit's class color while the HP
    --- foreground can stay in Dark/Unified/Gradient mode.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreBarBgClassColor)
    --- Background fill geometry and color source are independent. Migrate the
    --- two legacy booleans into the canonical mode without changing existing
    --- profiles; invalid imported values fail back to the current full/custom
    --- appearance.
    if g.barBgFillMode ~= "full" and g.barBgFillMode ~= "missing" then
        g.barBgFillMode = "full"
    end
    do
        local mode = g.barBgColorMode
        if mode ~= "custom" and mode ~= "match_health" and mode ~= "class" and mode ~= "health_gradient" then
            if g.barBgClassColor == true then
                mode = "class"
            elseif g.barBgMatchHPColor == true then
                mode = "match_health"
            else
                mode = "custom"
            end
        end
        g.barBgColorMode = mode
        g.barBgMatchHPColor = mode == "match_health"
        g.barBgClassColor = mode == "class"
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "base_02")
    if g.healthGradientLowR == nil or g.healthGradientLowG == nil or g.healthGradientLowB == nil then
        g.healthGradientLowR = 1
        g.healthGradientLowG = 0
        g.healthGradientLowB = 0
    end
    if g.healthGradientMidR == nil or g.healthGradientMidG == nil or g.healthGradientMidB == nil then
        g.healthGradientMidR = 1
        g.healthGradientMidG = 1
        g.healthGradientMidB = 0
    end
    if g.healthGradientHighR == nil or g.healthGradientHighG == nil or g.healthGradientHighB == nil then
        g.healthGradientHighR = 0
        g.healthGradientHighG = 1
        g.healthGradientHighB = 0
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreEnablePowerGradient)
    if g.healthBarGradientColorR == nil or g.healthBarGradientColorG == nil or g.healthBarGradientColorB == nil then
        g.healthBarGradientColorR, g.healthBarGradientColorG, g.healthBarGradientColorB = 0, 0, 0
    end
    if g.powerBarGradientColorR == nil or g.powerBarGradientColorG == nil or g.powerBarGradientColorB == nil then
        g.powerBarGradientColorR, g.powerBarGradientColorG, g.powerBarGradientColorB = 0, 0, 0
    end
    --- Not adopted on Classic: no Classic profile has ever stored these six
    --- keys, and MSUF_UF_Config falls back to exactly these values, so seeding
    --- them there would only change what a saved profile carries.
    if not IS_CLASSIC_FAMILY then
        MSUF.DefaultsSchema.SeedGeneral(g, "base_03")
    end
end

function barColorStages.Aggro(profileDB, g)
    --- Bars: Aggro highlight overlay (Target/Focus/Boss)
    --- Aggro indicator: re-uses the HP outline border as an orange warning when YOU have aggro (target/focus/boss).
    --- Bars offers "Aggro border" with dropdown default 1 (On), menu search
    --- manifest declares 1, and group frames default aggroEnabled = true. The
    --- compiled unitframe fallback, however, only consulted the retired
    --- indicator key below - which this very block coerces to "off" for every
    --- profile that never carried it. A profile without an explicit choice
    --- therefore read "On" in the menu while the border stayed dark, and only
    --- an Off/On round trip through the dropdown repaired it. Seed the real key
    --- once, before that coercion, so stored state and menu agree. A profile
    --- that carries the retired key keeps the decision it recorded.
    --- aggroOutlineMode is shared with the group frames, whose own default is
    --- on. Never seed 0 from the coerced "off" below: that would silently kill
    --- a working group aggro border. Only enableAggroHighlight == false is a
    --- real recorded off.
    if g.aggroOutlineMode == nil then
        g.aggroOutlineMode = (g.aggroIndicatorMode == "border"
        or g.enableAggroHighlight ~= false) and 1 or 0
    end
    if g.aggroIndicatorMode == nil then
        if g.enableAggroHighlight == true then
            g.aggroIndicatorMode = "border" --- legacy migrate
        else
            g.aggroIndicatorMode = "off"
        end
    end
    if g.aggroIndicatorMode ~= "border" then
        g.aggroIndicatorMode = "off"
    end

end

function barColorStages.Gradients(profileDB, g)
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreGradientStrength)
    if g.powerGradientStrength == nil then
        g.powerGradientStrength = g.gradientStrength
    end
    do
        local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
        if not hasNew then
            local dir = g.gradientDirection
            if type(dir) ~= "string" or dir == "" then
                dir = "RIGHT"
            else
                dir = string.upper(dir)
            end
            if dir == "LEFT" then
                g.gradientDirLeft = true
            elseif dir == "UP" then
                g.gradientDirUp = true
            elseif dir == "DOWN" then
                g.gradientDirDown = true
            else
                g.gradientDirRight = true
            end
        end
        MSUF.DefaultsSchema.SeedGeneral(g, "base_04")
        if (not g.gradientDirLeft) and (not g.gradientDirRight) and (not g.gradientDirUp) and (not g.gradientDirDown) then
            g.gradientDirRight = true
        end
        --- Keep legacy key as a reasonable fallback for older builds/tools.
        if type(g.gradientDirection) ~= "string" or g.gradientDirection == "" then
            g.gradientDirection = "RIGHT"
        end
        local hasPowerDirections = (g.powerGradientDirLeft ~= nil) or (g.powerGradientDirRight ~= nil)
            or (g.powerGradientDirUp ~= nil) or (g.powerGradientDirDown ~= nil)
        if not hasPowerDirections then
            g.powerGradientDirLeft = g.gradientDirLeft == true
            g.powerGradientDirRight = g.gradientDirRight == true
            g.powerGradientDirUp = g.gradientDirUp == true
            g.powerGradientDirDown = g.gradientDirDown == true
        end
        MSUF.DefaultsSchema.SeedGeneral(g, "base_05")
        if (not g.powerGradientDirLeft) and (not g.powerGradientDirRight)
            and (not g.powerGradientDirUp) and (not g.powerGradientDirDown)
        then
            g.powerGradientDirRight = true
        end
        if type(g.powerGradientDirection) ~= "string" or g.powerGradientDirection == "" then
            g.powerGradientDirection = g.gradientDirection
        end
    end
end

function barColorStages.Modes(profileDB, g)
    if g.editModeBgAlpha == nil or type(g.editModeBgAlpha) ~= "number" then
        g.editModeBgAlpha = 0.75
    else
        if g.editModeBgAlpha < 0.1 then
            g.editModeBgAlpha = 0.1
        elseif g.editModeBgAlpha > 0.8 then
            g.editModeBgAlpha = 0.8
        end
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreUseClassColors)
    if g.barMode == nil then
        if g.useClassColors then
            g.barMode = "class"
        elseif g.darkMode then
            g.barMode = "dark"
        else
            g.barMode = "dark"
            g.darkMode = true
            g.useClassColors = false
        end
    end
    --- Normalize Bar mode (supports: dark / class / unified / gradient) and keep legacy flags in sync
    if g.barMode ~= "dark" and g.barMode ~= "class" and g.barMode ~= "unified" and g.barMode ~= "gradient" then
        g.barMode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
    end
    if g.barMode == "dark" then
        g.darkMode = true
        g.useClassColors = false
    elseif g.barMode == "class" then
        g.darkMode = false
        g.useClassColors = true
    elseif g.barMode == "gradient" then
        --- Gradient mode is HP-derived; neither legacy flag applies.
        g.darkMode = false
        g.useClassColors = false
    else --- unified
        g.darkMode = false
        g.useClassColors = false
    end
    --- NPC Color Mode: "reaction" (classic friendly/neutral/enemy) or "type" (boss/miniboss/caster/melee/regular).
    --- When "type", enemy NPC health bars in barMode "class" show classification-based colors.
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreNpcColorMode)
    if g.npcColorMode ~= "reaction" and g.npcColorMode ~= "type" then
        g.npcColorMode = "reaction"
    end
    MSUF.DefaultsSchema.SeedGeneral(g, "base_06")
    --- Per-unit NPC Type enable (nil/true = on, false = off)
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreNpcTypeTarget)
    if type(g.unifiedBarR) ~= "number" then g.unifiedBarR = 0.10 end
    if type(g.unifiedBarG) ~= "number" then g.unifiedBarG = 0.60 end
    if type(g.unifiedBarB) ~= "number" then g.unifiedBarB = 0.90 end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreUseBarBorder)
end

function barColorStages.Outline(profileDB, g)
    local function NormalizeStaticOutlineColor(tbl)
        if type(tbl) ~= "table" then return end
        if tbl.barOutlineColorMode ~= nil then
            local mode = type(tbl.barOutlineColorMode) == "string" and tbl.barOutlineColorMode:upper() or "BLACK"
            local hasStaticColor = type(tbl.barOutlineColorR) == "number"
                and type(tbl.barOutlineColorG) == "number"
                and type(tbl.barOutlineColorB) == "number"
                and (tbl.barOutlineColorR ~= 0 or tbl.barOutlineColorG ~= 0 or tbl.barOutlineColorB ~= 0)
            if mode == "CLASS" or (mode ~= "CUSTOM" and not hasStaticColor) then
                tbl.barOutlineColorR = 0
                tbl.barOutlineColorG = 0
                tbl.barOutlineColorB = 0
            end
            tbl.barOutlineColorMode = nil
        end
        if tbl.barOutlineColorR ~= nil or tbl.barOutlineColorG ~= nil or tbl.barOutlineColorB ~= nil then
            tbl.barOutlineColorA = 1
        end
    end
    NormalizeStaticOutlineColor(g)
    for _, key in ipairs({ "player", "target", "focus", "boss", "arena",
        "pet", "pettarget", "targettarget", "focustarget", "gf_party", "gf_raid", "gf_mythicraid" }) do
        NormalizeStaticOutlineColor(profileDB[key])
    end
    MSUF.DefaultsSchema.Fill(g, MSUF.DefaultsSchema.Values.CoreBarBorderStyle)end

local function MSUF_Defaults_Stage_SeedBarColorDefaults(profileDB, g)
    barColorStages.Background(profileDB, g)
    barColorStages.Aggro(profileDB, g)
    barColorStages.Gradients(profileDB, g)
    barColorStages.Modes(profileDB, g)
    barColorStages.Outline(profileDB, g)
end

--- Text style flags, name shortening baseline, number abbreviation, custom
--- font colour, slug/monochrome exclusivity, shadow metrics, alpha/baseline.

Parts.MSUF_Defaults_Stage_SeedBarColorDefaults = MSUF_Defaults_Stage_SeedBarColorDefaults
