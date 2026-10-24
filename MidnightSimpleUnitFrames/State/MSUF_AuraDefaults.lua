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
