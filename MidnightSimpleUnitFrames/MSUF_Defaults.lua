local addonName, ns = ...
ns = ns or {}

-- MSUF Defaults / DB initialization

-- ---------------------------------------------------------------------------
-- Factory default profile (MSUF2 compact string)
--
-- If MSUF_DB is NEW (fresh install / full reset), we seed it from this payload
-- so the addon boots with your preferred baseline.
--
-- Existing installs are NOT overwritten. This only runs when MSUF_DB was
-- created empty in this session.
-- ---------------------------------------------------------------------------

local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = [[MSUF2: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]]

local function MSUF_Defaults_TryDecodeCompactString(str)
    if type(str) ~= "string" then return nil end

    local E = _G and _G.C_EncodingUtil
    if type(E) ~= "table" then return nil end
    if type(E.DeserializeCBOR) ~= "function" then return nil end
    if type(E.DecompressString) ~= "function" then return nil end
    if type(E.DecodeBase64) ~= "function" then return nil end

    local ok, b64 = pcall(string.match, str, "^%s*MSUF2:%s*(.-)%s*$")
    if not ok or type(b64) ~= "string" or b64 == "" then return nil end

    local ok2, cleaned = pcall(string.gsub, b64, "%s+", "")
    if not ok2 or type(cleaned) ~= "string" then return nil end
    b64 = cleaned

    local ok3, comp = pcall(E.DecodeBase64, b64)
    if not ok3 or type(comp) ~= "string" then return nil end

    local method = (_G.Enum and _G.Enum.CompressionMethod and _G.Enum.CompressionMethod.Deflate) or nil

    local ok4, bin
    if method ~= nil then
        ok4, bin = pcall(E.DecompressString, comp, method)
    end
    if not ok4 or type(bin) ~= "string" then
        ok4, bin = pcall(E.DecompressString, comp)
    end
    if not ok4 or type(bin) ~= "string" then return nil end

    local ok5, tbl = pcall(E.DeserializeCBOR, bin)
    if not ok5 or type(tbl) ~= "table" then return nil end
    return tbl
end

local function MSUF_Defaults_WipeInPlace(t)
    if type(t) ~= "table" then return end
    for k in pairs(t) do t[k] = nil end
end

local function MSUF_Defaults_DeepCopy(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        local tk = type(k)
        if tk == "string" or tk == "number" then
            local tv = type(v)
            if tv == "table" then
                local d = dst[k]
                if type(d) ~= "table" then
                    d = {}
                    dst[k] = d
                else
                    MSUF_Defaults_WipeInPlace(d)
                end
                MSUF_Defaults_DeepCopy(d, v)
            elseif tv == "string" or tv == "number" or tv == "boolean" then
                dst[k] = v
            end
        end
    end
end

local function MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall()
    if type(MSUF_DB) ~= "table" then return end
    local g = (type(MSUF_DB.general) == "table") and MSUF_DB.general or nil
    if g and g._msufFactoryProfileApplied then
        return
    end

    -- Only seed when the DB was just created empty.
    -- (Existing installs always already have keys before EnsureDB_Heavy runs.)
    local isEmpty = (next(MSUF_DB) == nil)
    if not isEmpty then
        return
    end

    local tbl = MSUF_Defaults_TryDecodeCompactString(MSUF_FACTORY_DEFAULT_PROFILE_COMPACT)
    if type(tbl) ~= "table" then return end
    local payload = tbl.payload
    if type(payload) ~= "table" then return end

    -- Replace the empty DB with the decoded payload.
    MSUF_Defaults_DeepCopy(MSUF_DB, payload)
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general._msufFactoryProfileApplied = true
end

local MSUF_DB_LastHeavyRun

function MSUF_EnsureDB_Heavy()
    if not MSUF_DB then
        MSUF_DB = {}
    end

    -- Seed brand-new installs / hard-resets from the factory profile payload.
    MSUF_Defaults_TryApplyFactoryProfileIfFreshInstall()

    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    MSUF_DB.classColors = MSUF_DB.classColors or {}
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}

    if g.fontKey == nil then
        g.fontKey = "FRIZQT"
    end

    if g.hardKillBlizzardPlayerFrame == nil then
        -- Default: Hard-hide Blizzard PlayerFrame (compat mode OFF).
        g.hardKillBlizzardPlayerFrame = true
    end
if g.anchorName == nil then
    g.anchorName = "UIParent"
end

if g.anchorToCooldown == nil then
    g.anchorToCooldown = false
end


-- New install defaults (UI scale + Flash menu anchor)
if g.globalUiScalePreset == nil then
    g.globalUiScalePreset = "1080p"
end
if g.globalUiScaleValue == nil then
    g.globalUiScaleValue = 0.71111111111111
end

if g.flashFullPoint == nil then g.flashFullPoint = "LEFT" end
if g.flashFullRelPoint == nil then g.flashFullRelPoint = "LEFT" end
if g.flashFullX == nil then g.flashFullX = -2.0000178813934 end
if g.flashFullY == nil then g.flashFullY = 91.75 end
if g.flashFullW == nil then g.flashFullW = 880.75018310547 end
if g.flashFullH == nil then g.flashFullH = 628.50018310547 end
if g.flashFullXpx == nil then g.flashFullXpx = -1.4222349723183 end
if g.flashFullYpx == nil then g.flashFullYpx = 65.244446024299 end

if g.tipCycleIndex == nil then
    g.tipCycleIndex = 11
end


-- Minimap icon (LibDBIcon) defaults
if g.showMinimapIcon == nil then
    g.showMinimapIcon = true
end
if type(g.minimapIconDB) ~= "table" then
    g.minimapIconDB = { hide = false, minimapPos = 220, radius = 80 }
else
    if g.minimapIconDB.hide == nil then g.minimapIconDB.hide = false end
    if g.minimapIconDB.minimapPos == nil then g.minimapIconDB.minimapPos = 220 end
    if g.minimapIconDB.radius == nil then g.minimapIconDB.radius = 80 end
end

    if g.editModeSnapToGrid == nil then
        g.editModeSnapToGrid = false -- Default: Snap OFF
    end
    if g.editModeGridStep == nil then
        g.editModeGridStep = 20
    end
if g.editModeSnapEnabled == nil then
    g.editModeSnapEnabled = false
end
if g.editModeSnapMode == nil then
    g.editModeSnapMode = "grid"
end
if g.editModeSnapModeGrid == nil then
    g.editModeSnapModeGrid = true
end
if g.editModeSnapModeFrames == nil then
    g.editModeSnapModeFrames = false
end
if g.editModeHideWhiteArrows == nil then
    g.editModeHideWhiteArrows = true
end

    if g.linkEditModes == nil then
        g.linkEditModes = true
    end
 if g.darkMode == nil then
        g.darkMode = false
    end
    if g.darkBarTone == nil then
        g.darkBarTone = "black"
    end
    if g.darkBgBrightness == nil then
        g.darkBgBrightness = 0.25      -- 25% Grau als Standard
    end

    if g.classBarBgR == nil or g.classBarBgG == nil or g.classBarBgB == nil then
        g.classBarBgR = 0.0   -- default: black background
        g.classBarBgG = 0.0
        g.classBarBgB = 0.0
    end

    if g.enableGradient == nil then
        g.enableGradient = true
    end
    if g.gradientStrength == nil then
        g.gradientStrength = 0.45
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

    if g.gradientDirLeft == nil then g.gradientDirLeft = false end
    if g.gradientDirRight == nil then g.gradientDirRight = false end
    if g.gradientDirUp == nil then g.gradientDirUp = false end
    if g.gradientDirDown == nil then g.gradientDirDown = false end

    if (not g.gradientDirLeft) and (not g.gradientDirRight) and (not g.gradientDirUp) and (not g.gradientDirDown) then
        g.gradientDirRight = true
    end

    -- Keep legacy key as a reasonable fallback for older builds/tools.
    if type(g.gradientDirection) ~= "string" or g.gradientDirection == "" then
        g.gradientDirection = "RIGHT"
    end
end
    if g.editModeBgAlpha == nil or type(g.editModeBgAlpha) ~= "number" then
        g.editModeBgAlpha = 0.5
    else
        if g.editModeBgAlpha < 0.1 then
            g.editModeBgAlpha = 0.1
        elseif g.editModeBgAlpha > 0.8 then
            g.editModeBgAlpha = 0.8
        end
    end
    if g.useClassColors == nil then
        g.useClassColors = true
    end
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
    -- Normalize Bar mode (supports: dark / class / unified) and keep legacy flags in sync
    if g.barMode ~= "dark" and g.barMode ~= "class" and g.barMode ~= "unified" then
        g.barMode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
    end
    if g.barMode == "dark" then
        g.darkMode = true
        g.useClassColors = false
    elseif g.barMode == "class" then
        g.darkMode = false
        g.useClassColors = true
    else -- unified
        g.darkMode = false
        g.useClassColors = false
        if type(g.unifiedBarR) ~= "number" then g.unifiedBarR = 0.10 end
        if type(g.unifiedBarG) ~= "number" then g.unifiedBarG = 0.60 end
        if type(g.unifiedBarB) ~= "number" then g.unifiedBarB = 0.90 end
    end

    if g.useBarBorder == nil then
        g.useBarBorder = true
    end
    if g.barBorderStyle == nil then
        g.barBorderStyle = "THIN"
    end
    if g.boldText == nil then
        g.boldText = false
    end
    if g.noOutline == nil then
        g.noOutline = false
    end
    if g.nameClassColor == nil then
        g.nameClassColor = false
    end
    if g.npcNameRed == nil then
        g.npcNameRed = false
    end
    if g.fontColor == nil then
        g.fontColor = "white"
    end


    if g.shortenNameMaxChars == nil then
        g.shortenNameMaxChars = 6
    end
    if g.shortenNameClipSide == nil then
        g.shortenNameClipSide = "LEFT" -- default: clip LEFT, keep name end (R41z0r-style)
    end
    if g.shortenNameFrontMaskPx == nil then
        g.shortenNameFrontMaskPx = 8 -- px eaten from the clipped side (secret-safe, viewport inset)
    end
    if g.shortenNameShowDots == nil then
        g.shortenNameShowDots = true -- show '...' on the clipped edge (secret-safe)
    end
    if g.useCustomFontColor == nil then
        g.useCustomFontColor = false
    end
    if g.useCustomFontColor and (g.fontColorCustomR == nil or g.fontColorCustomG == nil or g.fontColorCustomB == nil) then
        g.useCustomFontColor = false
        g.fontColorCustomR = nil
        g.fontColorCustomG = nil
        g.fontColorCustomB = nil
    end

        if g.textBackdrop == nil then
        g.textBackdrop = true
    end
    if g.highlightEnabled == nil then
        g.highlightEnabled = true
    end
    local fontColors = (ns and ns.MSUF_FONT_COLORS) or _G.MSUF_FONT_COLORS
    if type(g.highlightColor) ~= "string" then
        g.highlightColor = "white"
    else
        g.highlightColor = string.lower(g.highlightColor)
        if not (type(fontColors) == "table" and fontColors[g.highlightColor]) then
            g.highlightColor = "white"
        end
    end

    -- Status indicators (AFK/DND/Dead/Ghost toggles)
    if g.statusIndicators == nil then
        g.statusIndicators = {}
    end
    local si = g.statusIndicators
    if si.showAFK == nil then si.showAFK = true end
    if si.showDND == nil then si.showDND = true end
    if si.showDead == nil then si.showDead = true end
    if si.showGhost == nil then si.showGhost = true end

    if g.frameUpdateInterval == nil or type(g.frameUpdateInterval) ~= "number" then
        g.frameUpdateInterval = 0.05
    end
    MSUF_FrameUpdateInterval = g.frameUpdateInterval

    if g.castbarUpdateInterval == nil or type(g.castbarUpdateInterval) ~= "number" then
        g.castbarUpdateInterval = 0.02
    end
    MSUF_CastbarUpdateInterval = g.castbarUpdateInterval
    -- UFCore flush budgeting (spike cap)
    if g.ufcoreFlushBudgetMs == nil or type(g.ufcoreFlushBudgetMs) ~= "number" then
        g.ufcoreFlushBudgetMs = 2.0
    end
    if g.ufcoreUrgentMaxPerFlush == nil or type(g.ufcoreUrgentMaxPerFlush) ~= "number" then
        g.ufcoreUrgentMaxPerFlush = 10
    end


    if g.disableUnitInfoTooltips == nil then
        g.disableUnitInfoTooltips = true
    end

    if g.unitInfoTooltipStyle == nil then
        g.unitInfoTooltipStyle = "classic"
    end

    if g.castbarInterruptibleColor == nil then
        g.castbarInterruptibleColor = "turquoise"
    end
    if g.castbarNonInterruptibleColor == nil then
        g.castbarNonInterruptibleColor = "red"
    end
    if g.castbarInterruptColor == nil then
        g.castbarInterruptColor = "red"
    end

    if g.playerCastbarOverrideEnabled == nil then
        g.playerCastbarOverrideEnabled = true
    end
    if g.playerCastbarOverrideMode == nil then
        g.playerCastbarOverrideMode = "CLASS" -- "CLASS" or "CUSTOM"
    end
    if g.playerCastbarOverrideR == nil then g.playerCastbarOverrideR = 1 end
    if g.playerCastbarOverrideG == nil then g.playerCastbarOverrideG = 1 end
    if g.playerCastbarOverrideB == nil then g.playerCastbarOverrideB = 1 end
    if g.castbarFillDirection == nil then
        g.castbarFillDirection = "RTL"
    end
if g.castbarUnifiedFillDirection ~= nil then
        if g.castbarUnifiedDirection == nil then
            g.castbarUnifiedDirection = (g.castbarUnifiedFillDirection == true)
        end
        g.castbarUnifiedFillDirection = nil
    end

    if g.castbarUnifiedDirection == nil then
        g.castbarUnifiedDirection = false
    end

    -- Channeled casts: show 5 tick lines (channel tick markers)
    if g.castbarShowChannelTicks == nil then
        g.castbarShowChannelTicks = false
    end

    if g.empowerColorStages == nil then
        g.empowerColorStages = true
    end

    if g.empowerStageBlink == nil then
        g.empowerStageBlink = true
    end
    if g.empowerStageBlinkTime == nil or type(g.empowerStageBlinkTime) ~= "number" then
        g.empowerStageBlinkTime = 0.25
    end
    if g.enableTargetCastbar == nil then
        g.enableTargetCastbar = true
    end
    if g.enableFocusCastbar == nil then
        g.enableFocusCastbar = true
    end
    if g.enablePlayerCastbar == nil then
        g.enablePlayerCastbar = true
    end

    if g.enableBossCastbar == nil then
        g.enableBossCastbar = true
    end

if g.showPlayerCastTime == nil then
    g.showPlayerCastTime = true
end
if g.showTargetCastTime == nil then
    g.showTargetCastTime = true
end
if g.showFocusCastTime == nil then
    g.showFocusCastTime = true
end
if g.showBossCastTime == nil then
    g.showBossCastTime = true
end

if g.bossCastbarOffsetX == nil then
    g.bossCastbarOffsetX = 2
end
if g.bossCastbarOffsetY == nil then
    g.bossCastbarOffsetY = -46
end

if g.bossCastbarWidth == nil then
    g.bossCastbarWidth = 176
end
if g.bossCastbarHeight == nil then
    g.bossCastbarHeight = 12
end


    if g.castbarShowIcon == nil then
        g.castbarShowIcon = true
    end
    if g.castbarShowSpellName == nil then
        g.castbarShowSpellName = true
    end
    if g.castbarShakeStrength == nil then
        g.castbarShakeStrength = 8   -- pixels; 0 = no movement
    end

    if g.castbarSpellNameFontSize == nil then
        g.castbarSpellNameFontSize = 0
    end

    if g.castbarIconOffsetX == nil then
        g.castbarIconOffsetX = 0
    end
    if g.castbarIconOffsetY == nil then
        g.castbarIconOffsetY = 0
    end

    if g.castbarTargetOffsetX == nil then
        g.castbarTargetOffsetX = 0
    end
    if g.castbarTargetOffsetY == nil then
        g.castbarTargetOffsetY = -60
    end
    if g.castbarFocusOffsetX == nil then
        g.castbarFocusOffsetX = 2
    end
    if g.castbarFocusOffsetY == nil then
        g.castbarFocusOffsetY = -50
    end

    if g.castbarPlayerOffsetX == nil then
        g.castbarPlayerOffsetX = -2
    end
    if g.castbarPlayerOffsetY == nil then
        g.castbarPlayerOffsetY = -59
    end
    if g.castbarPlayerTimeOffsetX == nil then
        g.castbarPlayerTimeOffsetX = -2
    end
    if g.castbarPlayerTimeOffsetY == nil then
        g.castbarPlayerTimeOffsetY = 0
    end
    if g.castbarFocusTimeOffsetX == nil then
        g.castbarFocusTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarFocusTimeOffsetY == nil then
        g.castbarFocusTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end

    if g.castbarTargetTimeOffsetX == nil then
        g.castbarTargetTimeOffsetX = g.castbarPlayerTimeOffsetX or -2
    end
    if g.castbarTargetTimeOffsetY == nil then
        g.castbarTargetTimeOffsetY = g.castbarPlayerTimeOffsetY or 0
    end
    if g.castbarGlobalWidth == nil then
        g.castbarGlobalWidth = 200   -- Standardbreite
    end
    if g.castbarGlobalHeight == nil then
        g.castbarGlobalHeight = 18   -- Standardhöhe
    end


    -- Per-castbar default sizes (match Edit Mode preview defaults)
    if g.castbarPlayerBarWidth == nil then g.castbarPlayerBarWidth = 271 end
    if g.castbarPlayerBarHeight == nil then g.castbarPlayerBarHeight = 18 end
    if g.castbarTargetBarWidth == nil then g.castbarTargetBarWidth = 272 end
    if g.castbarTargetBarHeight == nil then g.castbarTargetBarHeight = 18 end
    if g.castbarFocusBarWidth == nil then g.castbarFocusBarWidth = 175 end
    if g.castbarFocusBarHeight == nil then g.castbarFocusBarHeight = 18 end

    if g.castbarPlayerPreviewEnabled == nil then
        g.castbarPlayerPreviewEnabled = true
    end

-- Legacy Auras 1.x DB cleanup (Patch 6D Step 2)
g.targetAuraFilter = nil
g.targetAuraWidth = nil
g.targetAuraHeight = nil
g.targetAuraScale = nil
g.targetAuraAlpha = nil
g.targetAuraOffsetX = nil
g.targetAuraOffsetY = nil
g.targetAuraDisplay = nil

if g.fontSize == nil then
        g.fontSize = 14
    end
    -- Per-text font sizes (0 means "use global" in some menus, but these are explicit defaults)
    if g.nameFontSize == nil then g.nameFontSize = 14 end
    if g.hpFontSize == nil then g.hpFontSize = 14 end
    if g.powerFontSize == nil then g.powerFontSize = 14 end
    if g.auraFontSize == nil then g.auraFontSize = 25 end


    if g.castbarBackgroundTexture == nil then
        g.castbarBackgroundTexture = "Solid"
    end
-- Textures (explicit defaults)
if g.castbarTexture == nil then
    g.castbarTexture = "Solid"
end

-- Castbar visuals
if g.castbarShowGlow == nil then
    g.castbarShowGlow = false
end

-- Aura highlight/border colors (used by Auras 2.0 highlight pipeline)
if g.aurasDispelBorderColor == nil then
    g.aurasDispelBorderColor = { ["1"] = 0.2, ["2"] = 0.6, ["3"] = 1 }
end
if g.aurasOwnBuffHighlightColor == nil then
    g.aurasOwnBuffHighlightColor = { ["1"] = 1, ["2"] = 0.85, ["3"] = 0.2 }
end
if g.aurasOwnDebuffHighlightColor == nil then
    g.aurasOwnDebuffHighlightColor = { ["1"] = 1, ["2"] = 0.85, ["3"] = 0.2 }
end
if g.aurasStackCountColor == nil then
    g.aurasStackCountColor = { ["1"] = 1, ["2"] = 1, ["3"] = 1 }
end
if g.aurasStealableBorderColor == nil then
    g.aurasStealableBorderColor = { ["1"] = 0, ["2"] = 0.75, ["3"] = 1 }
end


    -- Per-castbar toggles + offsets
    if g.castbarTargetShowIcon == nil then g.castbarTargetShowIcon = true end
    if g.castbarFocusShowIcon == nil then g.castbarFocusShowIcon = true end
    if g.castbarPlayerShowIcon == nil then g.castbarPlayerShowIcon = true end

    if g.castbarTargetShowSpellName == nil then g.castbarTargetShowSpellName = true end
    if g.castbarFocusShowSpellName == nil then g.castbarFocusShowSpellName = true end
    if g.castbarPlayerShowSpellName == nil then g.castbarPlayerShowSpellName = true end

    if g.castbarTargetTextOffsetX == nil then g.castbarTargetTextOffsetX = 0 end
    if g.castbarTargetTextOffsetY == nil then g.castbarTargetTextOffsetY = 0 end
    if g.castbarFocusTextOffsetX == nil then g.castbarFocusTextOffsetX = 0 end
    if g.castbarFocusTextOffsetY == nil then g.castbarFocusTextOffsetY = 0 end
    if g.castbarPlayerTextOffsetX == nil then g.castbarPlayerTextOffsetX = 0 end
    if g.castbarPlayerTextOffsetY == nil then g.castbarPlayerTextOffsetY = 0 end

    if g.castbarTargetIconOffsetX == nil then g.castbarTargetIconOffsetX = 0 end
    if g.castbarTargetIconOffsetY == nil then g.castbarTargetIconOffsetY = 0 end
    if g.castbarFocusIconOffsetX == nil then g.castbarFocusIconOffsetX = 0 end
    if g.castbarFocusIconOffsetY == nil then g.castbarFocusIconOffsetY = 0 end
    if g.castbarPlayerIconOffsetX == nil then g.castbarPlayerIconOffsetX = 0 end
    if g.castbarPlayerIconOffsetY == nil then g.castbarPlayerIconOffsetY = 0 end

    -- Boss castbar UI bits (BossCastbars module reads these from general)
    if g.showBossCastIcon == nil then g.showBossCastIcon = true end
    if g.showBossCastName == nil then g.showBossCastName = true end
    if g.bossPreviewEnabled == nil then g.bossPreviewEnabled = true end
    if g.bossCastIconOffsetX == nil then g.bossCastIconOffsetX = 0 end
    if g.bossCastIconOffsetY == nil then g.bossCastIconOffsetY = 0 end
    if g.bossCastTextOffsetX == nil then g.bossCastTextOffsetX = 0 end
    if g.bossCastTextOffsetY == nil then g.bossCastTextOffsetY = 0 end
    if g.bossCastTimeOffsetX == nil then g.bossCastTimeOffsetX = 0 end
    if g.bossCastTimeOffsetY == nil then g.bossCastTimeOffsetY = 0 end

    -- Focus Kick Icon defaults
    if g.enableFocusKickIcon == nil then g.enableFocusKickIcon = false end
    if g.focusKickIconWidth == nil then g.focusKickIconWidth = 40 end
    if g.focusKickIconHeight == nil then g.focusKickIconHeight = 40 end
    if g.focusKickIconOffsetX == nil then g.focusKickIconOffsetX = 300 end
    if g.focusKickIconOffsetY == nil then g.focusKickIconOffsetY = 0 end

    if g.barTexture == nil then
        g.barTexture = "Solid"
    end

    if g.barBackgroundTexture == nil then
        g.barBackgroundTexture = "Solid"
    end
    if g.hpTextMode == nil then
        g.hpTextMode = "FULL_PLUS_PERCENT"
    end

    if g.hpTextSeparator == nil then
        g.hpTextSeparator = "-"
    end


    if g.powerTextSeparator == nil then
        g.powerTextSeparator = g.hpTextSeparator
    end

    if g.hpTextSpacerEnabled == nil then
        g.hpTextSpacerEnabled = false
    end
    if g.hpTextSpacerX == nil then
        g.hpTextSpacerX = 140
    end

    -- Which unit's HP spacer settings are currently shown/edited in the Bars menu.
    -- This is purely a UI selection state (does not change gameplay behavior).
    if g.hpSpacerSelectedUnitKey == nil then
        g.hpSpacerSelectedUnitKey = "player"
    end
    if g.hpSpacerSelectedUnitKey == "tot" then
        g.hpSpacerSelectedUnitKey = "targettarget"
    end

    -- HP spacer is now per-unit (Step 4). Keep legacy general.* values as fallback,
    -- but migrate them into per-unit fields once (without overwriting per-unit edits).
    local legacyHpSpacerEnabled = g.hpTextSpacerEnabled
    local legacyHpSpacerX = g.hpTextSpacerX
    for _, unitKey in ipairs({"player","target","focus","targettarget","pet","boss"}) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        local u = MSUF_DB[unitKey]
        if u.hpTextSpacerEnabled == nil and legacyHpSpacerEnabled ~= nil then
            u.hpTextSpacerEnabled = legacyHpSpacerEnabled
        end
        if u.hpTextSpacerX == nil and legacyHpSpacerX ~= nil then
            u.hpTextSpacerX = legacyHpSpacerX
        end
        if u.hpTextSpacerEnabled == nil then
            u.hpTextSpacerEnabled = false
        end
        if u.hpTextSpacerX == nil then
            u.hpTextSpacerX = 140
        end
    end
    if g.powerTextMode == nil then
        g.powerTextMode = "FULL_PLUS_PERCENT"
    end

    if g.showTotalAbsorbAmount == nil then
        g.showTotalAbsorbAmount = false
    end

    if g.enableAbsorbBar == nil then
        g.enableAbsorbBar = true
    end

    if g.absorbAnchorMode == nil then
        -- 1 = Left Absorb, Right Heal-Absorb; 2 = Right Absorb, Left Heal-Absorb (default)
        g.absorbAnchorMode = 2
    end

    if g.showLeaderIcon == nil then
        g.showLeaderIcon = true
    end

    if g.leaderIconOffsetX == nil then
        g.leaderIconOffsetX = 0
    end
    if g.leaderIconOffsetY == nil then
        g.leaderIconOffsetY = 3
    end


    -- Level indicator offset (global)
    if g.levelIndicatorOffsetX == nil then
        g.levelIndicatorOffsetX = 0
    end
    if g.levelIndicatorOffsetY == nil then
        g.levelIndicatorOffsetY = 0
    end


    if g.levelIndicatorAnchor == nil then
        g.levelIndicatorAnchor = 'NAMERIGHT'
    end
    -- Misc -> Indicators
    if g.showIncomingResIndicator == nil then
        g.showIncomingResIndicator = true
    end
    if g.incomingResIndicatorPos == nil then
        g.incomingResIndicatorPos = 'TOPRIGHT'
    end

    if g.showCombatStateIndicator == nil then
        g.showCombatStateIndicator = true
    end
    if g.combatStateIndicatorPos == nil then
        g.combatStateIndicatorPos = 'TOPLEFT'
    end

    -- Player indicators (Frames -> Player)
    if g.showLevel == nil then
        g.showLevel = true
    end

    if g.showRaidMarker == nil then
        g.showRaidMarker = true
    end

    local legacyShowRaidMarker = g.showRaidMarker
    for _, key in ipairs({"player","target","focus","targettarget","pet","boss"}) do
        MSUF_DB[key] = MSUF_DB[key] or {}
        if MSUF_DB[key].showRaidMarker == nil and legacyShowRaidMarker ~= nil then
            MSUF_DB[key].showRaidMarker = legacyShowRaidMarker
        end
        if MSUF_DB[key].showRaidMarker == nil then
            MSUF_DB[key].showRaidMarker = true
        end

end

local legacyRaidMarkerOffsetX = g.raidMarkerOffsetX
local legacyRaidMarkerOffsetY = g.raidMarkerOffsetY
local legacyRaidMarkerAnchor  = g.raidMarkerAnchor
local legacyRaidMarkerSize    = g.raidMarkerSize
for _, key in ipairs({"player","target","focus","targettarget","pet","boss"}) do
    MSUF_DB[key] = MSUF_DB[key] or {}
    local conf = MSUF_DB[key]

    if conf.raidMarkerOffsetX == nil and legacyRaidMarkerOffsetX ~= nil then
        conf.raidMarkerOffsetX = legacyRaidMarkerOffsetX
    end
    if conf.raidMarkerOffsetY == nil and legacyRaidMarkerOffsetY ~= nil then
        conf.raidMarkerOffsetY = legacyRaidMarkerOffsetY
    end
    if conf.raidMarkerAnchor == nil and legacyRaidMarkerAnchor ~= nil then
        conf.raidMarkerAnchor = legacyRaidMarkerAnchor
    end
    if conf.raidMarkerSize == nil and legacyRaidMarkerSize ~= nil then
        conf.raidMarkerSize = legacyRaidMarkerSize
    end

    if conf.raidMarkerOffsetX == nil then
        if key == "player" then
            conf.raidMarkerOffsetX = 21
        elseif key == "target" then
            conf.raidMarkerOffsetX = -15
        else
            conf.raidMarkerOffsetX = 16
        end
    end
    if conf.raidMarkerOffsetY == nil then conf.raidMarkerOffsetY = 3 end
    if conf.raidMarkerAnchor == nil then
        if key == "target" then
            conf.raidMarkerAnchor = "TOPRIGHT"
        else
            conf.raidMarkerAnchor = "TOPLEFT"
        end
    end
    if conf.raidMarkerSize == nil then conf.raidMarkerSize = 14 end
end

if MSUF_DB.bars == nil then
        MSUF_DB.bars = {}
    end
    if MSUF_DB.bars.showTargetPowerBar == nil then
        MSUF_DB.bars.showTargetPowerBar = true
    end

        if MSUF_DB.bars.showBossPowerBar == nil then
        MSUF_DB.bars.showBossPowerBar = true
    end
    if MSUF_DB.bars.showFocusPowerBar == nil then
        MSUF_DB.bars.showFocusPowerBar = true
    end
    if MSUF_DB.bars.showPlayerPowerBar == nil then
        MSUF_DB.bars.showPlayerPowerBar = true
    end
    if MSUF_DB.bars.showBarBorder == nil then
        MSUF_DB.bars.showBarBorder = true
    end

    if MSUF_DB.bars.powerBarHeight == nil then
        MSUF_DB.bars.powerBarHeight = 3
    end
    if MSUF_DB.bars.embedPowerBarIntoHealth == nil then
        -- Pixel-perfect default: keep the power bar *inside* the unitframe bounds.
        -- This prevents the power bar from extending below the frame and breaking
        -- pixel-accurate layouts when toggling power bars on.
        -- Users who want the legacy behavior can disable this in Bars.
        MSUF_DB.bars.embedPowerBarIntoHealth = true
    end


if MSUF_DB.bars.barOutlineThickness == nil then
    -- New slider-based bar outline. Backwards compatible default:
    -- - If legacy border is off -> 0
    -- - Else map legacy style to a sensible thickness
    local enabled = true
    if MSUF_DB.general and MSUF_DB.general.useBarBorder == false then
        enabled = false
    end
    if MSUF_DB.bars.showBarBorder ~= nil then
        enabled = (MSUF_DB.bars.showBarBorder ~= false)
    end

    if not enabled then
        MSUF_DB.bars.barOutlineThickness = 0
    else
        local style = (MSUF_DB.general and MSUF_DB.general.barBorderStyle) or "THIN"
        local map = { THIN = 2, THICK = 3, SHADOW = 4, GLOW = 4 }
        MSUF_DB.bars.barOutlineThickness = map[style] or 2
    end
end


    -- Gameplay defaults (module-safe: some modules expect MSUF_DB.gameplay to exist)
    if MSUF_DB.gameplay == nil then
        MSUF_DB.gameplay = {}
    end
    local gp = MSUF_DB.gameplay
    if gp.enableCombatTimer == nil then gp.enableCombatTimer = false end
    if gp.lockCombatTimer == nil then gp.lockCombatTimer = false end
    if gp.combatFontSize == nil then gp.combatFontSize = 24 end
    if gp.combatOffsetX == nil then gp.combatOffsetX = 0 end
    if gp.combatOffsetY == nil then gp.combatOffsetY = -200 end

    if gp.enableCombatStateText == nil then gp.enableCombatStateText = false end
    if gp.lockCombatState == nil then gp.lockCombatState = false end
    if gp.combatStateFontSize == nil then gp.combatStateFontSize = 24 end
    if gp.combatStateOffsetX == nil then gp.combatStateOffsetX = 0 end
    if gp.combatStateOffsetY == nil then gp.combatStateOffsetY = 80 end
    if gp.combatStateDuration == nil then gp.combatStateDuration = 1.5 end

    if gp.enableCombatCrosshair == nil then gp.enableCombatCrosshair = false end
    if gp.enableCombatCrosshairMeleeRangeColor == nil then gp.enableCombatCrosshairMeleeRangeColor = false end
    if gp.crosshairSize == nil then gp.crosshairSize = 40 end
    if gp.crosshairThickness == nil then gp.crosshairThickness = 2 end

    if gp.cooldownIcons == nil then gp.cooldownIcons = false end
    if gp.enableFirstDanceTimer == nil then gp.enableFirstDanceTimer = false end
    if gp.nameplateMeleeSpellID == nil then gp.nameplateMeleeSpellID = 0 end
    -- Auras: legacy auras DB removed in Patch 6D Step 2 (Auras 2.0 uses MSUF_DB.auras2)
    if MSUF_DB.auras ~= nil then MSUF_DB.auras = nil end

-- Root toggle: Shorten unit names (Frames -> General)
if MSUF_DB.shortenNames == nil then
    MSUF_DB.shortenNames = false
end

-- Auras 2.0 defaults (new installs / reset profile)
    if MSUF_DB.auras2 == nil then
        MSUF_DB.auras2 = {
            enabled = true,
            showTarget = true,
            showFocus = true,
            showBoss = true,
            shared = {
                _msufA2_migrated_v11f = true,
                bossEditTogether = true,
                buffOffsetY = 30,
                cooldownTextSize = 14,
                iconSize = 26,
                offsetX = 0,
                offsetY = 6,
                spacing = 2,
                stackTextSize = 14,
                growth = "RIGHT",
                layoutMode = "SINGLE",
                perRow = 11,
                maxIcons = 12,
                maxBuffs = 8,
                maxDebuffs = 15,
                showBuffs = true,
                showDebuffs = true,
                showCooldownSwipe = true,
                showStackCount = true,
                showTooltip = true,
                showInEditMode = true,
                stackCountAnchor = "TOPRIGHT",
                hidePermanent = false,
                onlyMyBuffs = false,
                onlyMyDebuffs = false,
                masqueEnabled = false,
                highlightDispellableDebuffs = true,
                highlightOwnBuffs = false,
                highlightOwnDebuffs = false,
                highlightStealableBuffs = true,
                filters = {
                    _msufA2_sharedFiltersMigrated_v1 = true,
                    enabled = true,
                    hidePermanent = false,
                    onlyBossAuras = false,
                    buffs = {
                        includeBoss = false,
                        includeStealable = false,
                        onlyMine = false,
                    },
                    debuffs = {
                        dispelCurse = false,
                        dispelDisease = false,
                        dispelEnrage = false,
                        dispelMagic = false,
                        dispelPoison = false,
                        includeBoss = false,
                        includeDispellable = false,
                        onlyMine = false,
                    },
                },
            },
            perUnit = {
                target = {
                    overrideLayout = true,
                    overrideFilters = false,
                    layout = {
                        cooldownTextSize = 14,
                        iconSize = 26,
                        offsetX = -1,
                        offsetY = 0,
                        spacing = 2,
                        stackTextSize = 14,
                    },
                    filters = {
                        _msufA2_filtersMigrated_v2 = true,
                        enabled = true,
                        hidePermanent = false,
                        onlyBossAuras = false,
                        buffs = {
                            includeBoss = false,
                            includeStealable = false,
                            onlyMine = false,
                        },
                        debuffs = {
                            dispelCurse = false,
                            dispelDisease = false,
                            dispelEnrage = false,
                            dispelMagic = false,
                            dispelPoison = false,
                            includeBoss = false,
                            includeDispellable = false,
                            onlyMine = false,
                        },
                    },
                },
                focus = {
                    overrideLayout = true,
                    overrideFilters = false,
                    layout = {
                        cooldownTextSize = 14,
                        iconSize = 26,
                        offsetX = 0,
                        offsetY = -1,
                        spacing = 2,
                        stackTextSize = 14,
                    },
                    filters = {
                        _msufA2_filtersMigrated_v2 = true,
                        enabled = true,
                        hidePermanent = false,
                        onlyBossAuras = false,
                        buffs = {
                            includeBoss = false,
                            includeStealable = false,
                            onlyMine = false,
                        },
                        debuffs = {
                            dispelCurse = false,
                            dispelDisease = false,
                            dispelEnrage = false,
                            dispelMagic = false,
                            dispelPoison = false,
                            includeBoss = false,
                            includeDispellable = false,
                            onlyMine = false,
                        },
                    },
                },
            },
        }

        -- Boss per-unit defaults (1-5)
        for i = 1, 5 do
            local key = "boss" .. i
            MSUF_DB.auras2.perUnit[key] = {
                overrideLayout = true,
                overrideFilters = false,
                layout = {
                    cooldownTextSize = 14,
                    iconSize = 26,
                    offsetX = 0,
                    offsetY = 0,
                    spacing = 2,
                    stackTextSize = 14,
                },
                filters = {
                    _msufA2_filtersMigrated_v2 = true,
                    enabled = true,
                    hidePermanent = false,
                    onlyBossAuras = false,
                    buffs = {
                        includeBoss = false,
                        includeStealable = false,
                        onlyMine = false,
                    },
                    debuffs = {
                        dispelCurse = false,
                        dispelDisease = false,
                        dispelEnrage = false,
                        dispelMagic = false,
                        dispelPoison = false,
                        includeBoss = false,
                        includeDispellable = false,
                        onlyMine = false,
                    },
                },
            }
        end
    end

local function fill(key, defaults)
        MSUF_DB[key] = MSUF_DB[key] or {}
        local t = MSUF_DB[key]
        for k, v in pairs(defaults) do
            if t[k] == nil then
                t[k] = v
            end
        end
    end

    local textDefaults = {
        nameOffsetX   = 4,
        nameOffsetY   = -4,
        hpOffsetX     = -4,
        hpOffsetY     = -4,
        powerOffsetX  = -4,
        powerOffsetY  = 4,
    }

    fill("player", {
        width     = 275,
        height    = 40,
        offsetX   = -256,
        offsetY   = -180,
        portraitMode = "LEFT",
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        showInterrupt = true,
        portraitMode = "LEFT",
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.player[k] == nil then MSUF_DB.player[k] = v end
    end

    -- Player castbar: custom channel tick markers (PLAYER ONLY)
    -- Stored under MSUF_DB.player.castbar.* so it does not touch general castbar settings.
    MSUF_DB.player.castbar = MSUF_DB.player.castbar or {}
    do
        local pc = MSUF_DB.player.castbar
        if pc.channelTickUseCustom == nil then pc.channelTickUseCustom = false end
        if type(pc.channelTickCount) ~= "number" then pc.channelTickCount = 5 end
        if type(pc.channelTickPreviewDuration) ~= "number" then pc.channelTickPreviewDuration = 2.5 end
        if pc.channelTickPreviewLoop == nil then pc.channelTickPreviewLoop = true end
        if type(pc.channelTickPosPct) ~= "table" then pc.channelTickPosPct = {} end
    end

    fill("target", {
        width     = 275,
        height    = 40,
        offsetX   = 320,
        offsetY   = -180,
        portraitMode = "RIGHT",
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
        showInterrupt = true,
        portraitMode = "RIGHT",
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.target[k] == nil then MSUF_DB.target[k] = v end
    end

    fill("focus", {
        width     = 180,
        height    = 30,
        offsetX   = -260,
        offsetY   = -300,
        portraitMode = "OFF",
        showName  = true,
        showLevelIndicator = false,
        showHP    = true,
        showPower = false,
        showInterrupt = true,
        portraitMode = "OFF",
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.focus[k] == nil then MSUF_DB.focus[k] = v end
    end
    fill("targettarget", {
        width     = 180,
        height    = 30,
        offsetX   = 220,
        offsetY   = -300,
        showName  = false,
        showLevelIndicator = true,
        showHP    = true,
        showPower = false,
    })
    if MSUF_DB.targettarget.showToTInTargetName == nil then MSUF_DB.targettarget.showToTInTargetName = false end
    -- Target-of-Target inline-in-Target separator token (rendered with spaces around it).
    -- Keep the default as the legacy behavior (" | ") by storing the token "|".
    if MSUF_DB.targettarget.totInlineSeparator == nil then MSUF_DB.targettarget.totInlineSeparator = "|" end

    for k, v in pairs(textDefaults) do
        if MSUF_DB.targettarget[k] == nil then MSUF_DB.targettarget[k] = v end
    end

    fill("pet", {
        width     = 220,
        height    = 30,
        offsetX   = -275,
        offsetY   = -250,
        showName  = true,
        showLevelIndicator = true,
        showHP    = true,
        showPower = true,
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.pet[k] == nil then MSUF_DB.pet[k] = v end
    end

    fill("boss", {
        width        = 180,
        height       = 30,
        offsetX      = 507,
        offsetY      = 309,
        spacing      = -96,
        showName     = true,
        showLevelIndicator = false,
        showHP       = true,
        showPower    = false,
        showInterrupt = true,
        portraitMode = "OFF",
    })
    for k, v in pairs(textDefaults) do
        if MSUF_DB.boss[k] == nil then MSUF_DB.boss[k] = v end
    end
    for _, unitKey in ipairs({"player", "target", "targettarget", "focus", "pet", "boss"}) do
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        if MSUF_DB[unitKey].enabled == nil then
            MSUF_DB[unitKey].enabled = true
        end
    end

    MSUF_DB_LastHeavyRun = MSUF_DB

end

function EnsureDB()
    if MSUF_DB and MSUF_DB_LastHeavyRun == MSUF_DB then
        return
    end

    MSUF_EnsureDB_Heavy()
end

-- Optional exports for other modules
ns.MSUF_EnsureDB_Heavy = MSUF_EnsureDB_Heavy
ns.EnsureDB = EnsureDB
