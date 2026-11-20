-- Canonical player defensive container for defaults and the aura runtime.
local _, MSUF = ...
local AuraConfig = {}
MSUF.AuraConfig = AuraConfig

function AuraConfig.CreateAliasAdder(A3)
    return function(out, spellID)
    spellID = tonumber(spellID)
    if not (out and spellID and spellID > 0) then return end
    spellID = math.floor(spellID + 0.5)
    out[spellID] = true
    local aliases = A3.AuraSpellIDAliases[spellID]
    for i = 1, type(aliases) == "table" and #aliases or 0 do
        local auraSpellID = tonumber(aliases[i])
        if auraSpellID and auraSpellID > 0 then out[math.floor(auraSpellID + 0.5)] = true end
    end
end
end

function AuraConfig.ClampNumber(value, defaultValue, minValue, maxValue)
    value = tonumber(value)
    if value == nil then value = defaultValue end
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

function AuraConfig.NewAlphaPulse(root)
    local pulse = root:CreateAnimationGroup()
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.45)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.7)
    if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
    pulse:SetLooping("BOUNCE")
    return pulse
end

function AuraConfig.InvalidateGroupRuntimeConfig(groupConfigRevisions, scope)
    if type(scope) ~= "string" then return false end
    local party = scope == "party" or scope == "gf_party" or scope:match("^party%d+$") ~= nil
    local raid = scope == "raid" or scope == "gf_raid" or scope:match("^raid%d+$") ~= nil
    local mythic = raid or scope == "mythicraid" or scope == "gf_mythicraid"
    if scope == "group" or scope == "groups" then party, raid, mythic = true, true, true end
    if not (party or raid or mythic) then return false end
    if party then groupConfigRevisions.party = groupConfigRevisions.party + 1 end
    if raid then groupConfigRevisions.raid = groupConfigRevisions.raid + 1 end
    if mythic then groupConfigRevisions.mythicraid = groupConfigRevisions.mythicraid + 1 end
    groupConfigRevisions[false] = groupConfigRevisions[false] + 1
    return true
end

function AuraConfig.NormalizePreviewScope(scope)
    scope = tostring(scope or "shared"):lower()
    if scope == "" or scope == "all" or scope == "global" then return "shared" end
    if scope == "gf_party" then return "party" end
    if scope == "gf_raid" then return "raid" end
    if scope == "gf_mythicraid" then return "mythicraid" end
    return scope
end

function AuraConfig.ForEachGroupPreviewFrame(gf, fn)
    local previews = gf._previewFrames
    if type(previews) ~= "table" then return end
    for _, frames in pairs(previews) do
        if type(frames) == "table" then
            for _, frame in pairs(frames) do
                if type(frame) == "table" then fn(frame) end
            end
        end
    end
end

function AuraConfig.PreviewProxy(frame, unit, frameSpec)
    local proxy = frame._msufA3AuraPreviewConfigProxy or {}
    frame._msufA3AuraPreviewConfigProxy = proxy
    proxy._msufIsGroupFrame = true
    proxy._msufGFIsPreviewFrame = true
    proxy._msufGFKind = frame._msufGFKind
    proxy.MSUFUnitKey = unit or frame.MSUFUnitKey
    proxy.MSUFSpec = frameSpec
    return proxy
end

function AuraConfig.NewContainerFilters()
    return {
            enabled = true,
            hidePermanent = false,
            onlyMine = false,
            onlyImportant = false,
            raid = false,
            raidInCombat = false,
            includeNameplateOnly = false,
            includeDispellable = false,
            dispellableAny = false,
            cancelable = false,
            notCancelable = false,
            crowdControl = false,
            externalDefensive = false,
            bigDefensive = false,
            exclusive = "none",
        }
end

local stylePadding = not MSUF.Client.IsClassic and 0 or nil
local function MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer()
    return {
        enabled = true,
        name = "Defensive Buffs",
        auraType = "BUFF",
        sourceUnit = "player",
        playerDefensives = true,
        portraitIcon = false,
        portraitMaxIcons = 1,
        portraitCooldownText = true,
        portraitPositionWhenDisabled = false,
        autoBlacklistPlayerBuffs = true,
        disabledPredefinedSpellIDs = {},
        spellIDs = "",
        filters = AuraConfig.NewContainerFilters(),
        placed = {
            type = "icon", anchor = "TOPRIGHT", growth = "LEFTDOWN",
            x = 0, y = 0, size = 24, barWidth = 54,
            max = 8, perRow = 4, spacing = 2, stylePadding = stylePadding,
            showCooldown = true, showCooldownSwipe = true, showStacks = true,
        },
        layer = 9,
        strata = "AUTO",
        frame = {
            type = "none", color = { 0.69, 0.50, 0.88, 0.80 },
            priority = 5, thickness = 2, layer = 0, strata = "AUTO",
        },
    }
end
MSUF.MSUF_CreateCanonicalPlayerDefensiveAuraContainer = MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer
MSUF.ExportPublic("MSUF_CreateCanonicalPlayerDefensiveAuraContainer", MSUF_Defaults_CreateCanonicalPlayerDefensiveAuraContainer)

function AuraConfig.LanePreviewFields(lane)
    return {
        enabled = lane.enabled == true,
        num = lane.max,
        size = lane.size,
        spacing = lane.spacing,
        step = lane.step,
        perRow = lane.perRow,
        cols = lane.cols,
        rows = lane.rows,
        width = lane.width,
        height = lane.height,
        padding = lane.padding,
        alpha = lane.alpha,
        iconZoom = lane.iconZoom,
        iconShape = lane.iconShape,
        growth = lane.growthX,
        rowWrap = lane.growthY,
        growthX = lane.xSign,
        growthY = lane.ySign,
        xSign = lane.xSign,
        ySign = lane.ySign,
        verticalGrowth = lane.verticalGrowth == true,
        initialAnchor = lane.initialAnchor,
        x = lane.x,
        y = lane.y,
        anchor = lane.anchor,
        iconStyle = lane.iconStyle,
    }
end

-- Configuration rebuild helpers; unchanged cache-hit event routes do not call these.
function AuraConfig.NormalizeAuraBarFill(direction)
    if direction == "LEFT" or direction == "UP" or direction == "DOWN" then return direction end
    return "RIGHT"
end

local AURA_BAR_ICON_PLACEMENTS = {
    LEFT = "LEFT", RIGHT = "RIGHT",
    OUTSIDE_LEFT = "LEFT", OUTSIDE_RIGHT = "RIGHT",
}
local AURA_BAR_DEFAULTS = {
    iconPlacement = "NONE", iconSize = 90, iconGap = 2, texture = "", outline = "", outlineThickness = 1,
    fillColorMode = "SHARED", outlineColorMode = "DEFAULT", growth = "DEFAULT", combineDebuffs = false,
}
local AURA_BAR_DIRECTIONS = { LEFT = true, RIGHT = true, UP = true, DOWN = true }
local AURA_BAR_COLOR_MODES = {
    fillColorMode = { CUSTOM = true, AUTO = true, DARK = true },
    outlineColorMode = { CUSTOM = true, AUTO = true },
}
local AURA_BAR_COLOR_DEFAULTS = { fillColor = { 0.32, 0.69, 0.49 }, outlineColor = { 0.18, 0.19, 0.22 } }
local AURA_BAR_NUMBER_RANGES = { iconSize = { 50, 100, 10 }, iconGap = { 0, 12, 1 }, outlineThickness = { 1, 4, 1 } }

local function NormalizeAuraBarStyleValue(value, key)
    local default = AURA_BAR_DEFAULTS[key]
    if key == "combineDebuffs" then return value == true end
    local range = AURA_BAR_NUMBER_RANGES[key]
    if range then
        value = tonumber(value) or default
        if value ~= value then return default end
        local step = range[3]
        return math.max(range[1], math.min(range[2], math.floor(value / step + 0.5) * step))
    end
    if type(value) ~= "string" then return default end
    if key == "iconPlacement" and not AURA_BAR_ICON_PLACEMENTS[value] then return default end
    if key == "growth" and not AURA_BAR_DIRECTIONS[value] then return default end
    local modes = AURA_BAR_COLOR_MODES[key]
    if modes and not modes[value] then return default end
    return value
end

function AuraConfig.ReadAuraBarStyle(raw, key)
    return NormalizeAuraBarStyleValue(type(raw) == "table" and raw[key] or nil, key)
end

local function ReadAuraBarRGB(color)
    if type(color) ~= "table" then return end
    local r, g, b = tonumber(color[1] or color.r), tonumber(color[2] or color.g), tonumber(color[3] or color.b)
    if not (r and g and b) or r ~= r or g ~= g or b ~= b then return end
    return math.max(0, math.min(1, r)), math.max(0, math.min(1, g)), math.max(0, math.min(1, b))
end

function AuraConfig.ReadAuraBarColor(raw, key)
    local r, g, b = ReadAuraBarRGB(type(raw) == "table" and raw[key])
    if r then return r, g, b end
    return unpack(AURA_BAR_COLOR_DEFAULTS[key])
end

function AuraConfig.CopyAuraBarStyle(raw, field, value)
    local copy = {}
    for key, default in pairs(AURA_BAR_DEFAULTS) do
        local saved
        if key == field then saved = NormalizeAuraBarStyleValue(value, key)
        else saved = AuraConfig.ReadAuraBarStyle(raw, key) end
        if saved ~= default then copy[key] = saved end
    end
    for key in pairs(AURA_BAR_COLOR_DEFAULTS) do
        local color
        if key == field then color = value
        elseif type(raw) == "table" then color = raw[key] end
        local r, g, b = ReadAuraBarRGB(color)
        if r then copy[key] = { r, g, b } end
    end
    return copy
end

local function CompileAuraBarAppearance(raw, width, height)
    if type(raw) ~= "table" then return end
    local read = AuraConfig.ReadAuraBarStyle
    local placement = read(raw, "iconPlacement")
    local anchor = AURA_BAR_ICON_PLACEMENTS[placement]
    local textureKey, outlineKey = read(raw, "texture"), read(raw, "outline")
    local fillMode = read(raw, "fillColorMode")
    if not anchor and textureKey == "" and outlineKey == "" and fillMode == "SHARED" then return end
    local iconSize, iconX, left, right, nameLeft, textRight = 0, 0, 0, 0, 4, 4
    if anchor then
        iconSize = math.max(1, math.floor(height * read(raw, "iconSize") / 100 + 0.5))
        local gap = read(raw, "iconGap")
        if placement == "OUTSIDE_LEFT" then
            left, nameLeft = iconSize + gap, iconSize + gap + 4
        elseif placement == "OUTSIDE_RIGHT" then
            right, textRight = iconSize + gap, iconSize + gap + 4
        elseif anchor == "LEFT" then
            iconX, nameLeft = gap, iconSize + gap + 4
        else
            iconX, textRight = -gap, iconSize + gap + 4
        end
        -- An inset icon uses part of the fill area, so keep the text's original width.
        if left == 0 and right == 0 then width = width + iconSize + gap end
    end
    local texture = textureKey ~= "" and MSUF.Media.ResolveTextureCandidate(textureKey) or nil
    local edge, edgeSize
    if outlineKey ~= "" then
        local borders = MSUF.BorderStyles
        edge = borders.Resolve(outlineKey)
        local thickness = read(raw, "outlineThickness")
        edgeSize = edge and math.min(math.floor(height / 2), borders.EdgeSize(outlineKey, thickness)) or thickness
    end
    local outlineMode = edgeSize and read(raw, "outlineColorMode") or "DEFAULT"
    local color = AuraConfig.ReadAuraBarColor
    local fillColor = fillMode == "CUSTOM" and { color(raw, "fillColor") } or nil
    local outlineColor = outlineMode == "CUSTOM" and { color(raw, "outlineColor") } or nil
    return {
        fillColorMode = fillMode, fillColor = fillColor, outlineColorMode = outlineMode, outlineColor = outlineColor,
        iconAnchor = anchor, iconX = iconX, iconSize = iconSize,
        left = left, right = right, nameLeft = nameLeft, textRight = textRight,
        texture = texture, outlineTexture = edge, outlineSize = edgeSize,
        barWidth = width, barHeight = height,
        signature = table.concat({ anchor or "", iconX, iconSize, left, right, nameLeft, textRight,
            texture or "", edge or "", edgeSize or 0, fillMode, outlineMode,
            fillColor and table.concat(fillColor, ",") or "", outlineColor and table.concat(outlineColor, ",") or "" }, "\030"),
    }
end

local function PlaceAuraBars(lane, width, height, growth)
    local x, y = lane.xSign or 1, lane.ySign or -1
    if growth == "LEFT" then x = -1
    elseif growth == "RIGHT" then x = 1
    elseif growth == "UP" then y = 1
    elseif growth == "DOWN" then y = -1 end

    local vertical = growth ~= "LEFT" and growth ~= "RIGHT"
    local count = math.max(lane.max, 1)
    lane.xSign, lane.ySign, lane.verticalGrowth = x, y, vertical
    lane.growthX, lane.growthY = x < 0 and "LEFT" or "RIGHT", y > 0 and "UP" or "DOWN"
    lane.initialAnchor = (y > 0 and "BOTTOM" or "TOP") .. (x < 0 and "RIGHT" or "LEFT")
    lane.perRow = vertical and 1 or count
    lane.cols, lane.rows = lane.perRow, vertical and count or 1
    local spacing, padding = lane.spacing or 0, lane.padding or 0
    lane.buttonWidth, lane.buttonHeight = width, height
    lane.stepX, lane.stepY = width + spacing, height + spacing
    lane.step = lane.stepX
    lane.width = width + (lane.cols - 1) * lane.stepX + 2 * padding
    lane.height = height + (lane.rows - 1) * lane.stepY + 2 * padding
end

function AuraConfig.ApplyAuraBarGeometry(lane, direction, compact, style)
    local height = math.max(10, math.min(28, math.floor((lane.buttonHeight or lane.size) * 0.65 + 0.5)))
    local width = math.floor(lane.size * (compact and 3.5 or 5) + 0.5)
    width = math.max(compact and 66 or 96, math.min(compact and 136 or 220, width))
    local appearance = CompileAuraBarAppearance(style, width, height)
    if appearance then width = appearance.barWidth end
    lane.auraBarAppearance = appearance
    lane.auraBarFill = AuraConfig.NormalizeAuraBarFill(direction)
    lane.showDurationBar, lane.durationBarDisplay = true, "BAR_ONLY"
    lane.showCooldownSwipe = false
    lane.combineDebuffs = lane.kind == "buff" and AuraConfig.ReadAuraBarStyle(style, "combineDebuffs")
    local rowWidth = width + (appearance and appearance.left + appearance.right or 0)
    PlaceAuraBars(lane, rowWidth, height, AuraConfig.ReadAuraBarStyle(style, "growth"))
    local fontLimit = math.min(14, height - 2)
    lane.cooldownSize = math.min(lane.cooldownSize or fontLimit, fontLimit)
    lane.stackSize = math.min(lane.stackSize or fontLimit, fontLimit)
    local textRight = appearance and appearance.textRight or 4
    local nameLeft = appearance and appearance.nameLeft or 4
    lane.cooldownAnchor, lane.cooldownX, lane.cooldownY = "RIGHT", -textRight, 0
    local timerSpace = lane.showCooldownText and math.ceil(lane.cooldownSize * 2.4) or 0
    lane.stackAnchor, lane.stackX, lane.stackY = "RIGHT", -textRight - timerSpace, 0
    local stackSpace = lane.showStacks and math.ceil(lane.stackSize * 1.4) or 0
    local nameInset = textRight + math.min(math.floor(width * 0.64) - 4, 4 + timerSpace + stackSpace)
    lane.auraBarNameInset = math.min(rowWidth - nameLeft - 4, nameInset)
end

function AuraConfig.CombinedAuraBarLanes(lanes)
    local buff, debuff = lanes and lanes.buff, lanes and lanes.debuff
    if buff and buff.enabled and buff.auraBarFill and buff.combineDebuffs
        and debuff and debuff.enabled and debuff.auraBarFill
        and not buff.groupAccessGate and not debuff.groupAccessGate then
        return buff, debuff
    end
end

function AuraConfig.AuraBarFlowAdvance(lead, lane, count)
    local span = lead.verticalGrowth and lane.buttonHeight or lane.buttonWidth
    return count * (span + (lane.spacing or 0))
end

function AuraConfig.AuraBarFlowOffset(lead, distance)
    if lead.verticalGrowth then return 0, distance * lead.ySign end
    return distance * lead.xSign, 0
end

function AuraConfig.CombinedAuraBarBounds(buff, debuff)
    local length = AuraConfig.AuraBarFlowAdvance(buff, buff, buff.max)
        + AuraConfig.AuraBarFlowAdvance(buff, debuff, debuff.max) - (debuff.spacing or 0)
    local pad = 2 * (buff.padding or 0)
    if buff.verticalGrowth then return math.max(buff.buttonWidth, debuff.buttonWidth) + pad, length + pad end
    return length + pad, math.max(buff.buttonHeight, debuff.buttonHeight) + pad
end

function AuraConfig.AuraBarPreviewRect(lead, count, tail, tailCount, frameWidth, frameHeight)
    if count + tailCount == 0 then return end
    local advance = AuraConfig.AuraBarFlowAdvance
    local span = advance(lead, lead, count)
    if tailCount > 0 then span = span + advance(lead, tail, tailCount) end
    span = span - ((tailCount > 0 and tail or lead).spacing or 0)
    local crossField = lead.verticalGrowth and "buttonWidth" or "buttonHeight"
    local cross = math.max(count > 0 and lead[crossField] or 0, tailCount > 0 and tail[crossField] or 0)
    local width, height = lead.verticalGrowth and cross or span, lead.verticalGrowth and span or cross
    local hostWidth, hostHeight = lead.width, lead.height
    if tail then hostWidth, hostHeight = AuraConfig.CombinedAuraBarBounds(lead, tail) end
    local anchor = lead.anchor or "CENTER"
    local fx = anchor:find("LEFT", 1, true) and 0 or (anchor:find("RIGHT", 1, true) and 1 or 0.5)
    local fy = anchor:find("BOTTOM", 1, true) and 0 or (anchor:find("TOP", 1, true) and 1 or 0.5)
    local pad = lead.padding or 0
    local x = (frameWidth - hostWidth) * fx + (lead.x or 0)
    local y = (frameHeight - hostHeight) * fy + (lead.y or 0)
    x = x + (lead.xSign < 0 and hostWidth - width - pad or pad)
    y = y + (lead.ySign < 0 and hostHeight - height - pad or pad)
    return x, x + width, y, y + height
end

function AuraConfig.StampSlot(placed, anchor, x, y, size)
    placed.type, placed.anchor = "icon", anchor
    placed.x, placed.y, placed.size = x, y, size
    return placed
end

function AuraConfig.StampLaneGeometry(lane, iconShape, requestedIconShape, spacing, step,
    perRow, cols, rows, growthX, growthY, xSign, ySign, verticalGrowth, initialAnchor)
    lane.iconShape, lane.requestedIconShape = iconShape, requestedIconShape
    lane.spacing, lane.step, lane.perRow = spacing, step, perRow
    lane.cols, lane.rows = cols, rows
    lane.growthX, lane.growthY = growthX, growthY
    lane.xSign, lane.ySign = xSign, ySign
    lane.verticalGrowth, lane.initialAnchor = verticalGrowth == true, initialAnchor
    return lane
end

function AuraConfig.RefuseSyntheticGroupAura(frame, hide)
    if frame._msufGFIsPreviewFrame ~= true then return false end
    frame._msufA3GroupRuntime = nil
    hide(frame)
    return true
end

-- Shared spell-indicator defaults use the active backend's table constructors.
-- Each caller still receives fresh tables and keeps its client-only additions.
function AuraConfig.DisciplineIndicatorAuras(Aura)
    return {
        Aura("PowerWordShield", 1.00, 0.84, 0.28, "PW: Shield"),
        Aura("PrayerOfMending", 0.56, 0.93, 0.56, "Prayer of Mending"),
        Aura("PainSuppression", 0.81, 0.58, 0.93, "Pain Suppression"),
        Aura("PowerInfusion", 0.94, 0.82, 0.31, "Power Infusion"),
    }
end

function AuraConfig.DisciplineIndicatorDefaults(Placed, Frame)
    return {
        PowerWordShield = Placed("icon", "TOPRIGHT", -1, -1, 22),
        PrayerOfMending = Placed("icon", "BOTTOMLEFT", 1, 1, 20),
        PainSuppression = Frame("border", 0.81, 0.58, 0.93, 1, 1),
        PowerInfusion = Frame("glow", 0.94, 0.82, 0.31, 1, 2),
    }
end

function AuraConfig.BlessingIndicatorDefaults(Frame)
    return {
        BlessingOfProtection = Frame("border", 0.94, 0.82, 0.31, 1, 1),
        BlessingOfSacrifice = Frame("border", 0.94, 0.50, 0.50, 1, 2),
        BlessingOfFreedom = Frame("border", 0.47, 0.77, 1.00, 1, 3),
    }
end

function AuraConfig.SeedDruidIndicators(defaults, Placed, wildGrowth)
    defaults.Rejuvenation = Placed("icon", "TOPLEFT", 1, -1, 22)
    defaults.Regrowth = Placed("icon", "TOPRIGHT", -1, -1, 22)
    defaults.Lifebloom = Placed("icon", "BOTTOMLEFT", 1, 1, 22)
    if wildGrowth then defaults.WildGrowth = Placed("square", "BOTTOMRIGHT", -3, 3, 9) end
    return defaults
end
