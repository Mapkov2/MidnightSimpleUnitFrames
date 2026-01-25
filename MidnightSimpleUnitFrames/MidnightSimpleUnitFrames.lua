local addonName, ns = ...
ns = ns or {}
-- Root global table (addon env-safe)
-- Heart of the addon
local ROOT_G = (getfenv and getfenv(0)) or _G
do
    local realG = _G
    if type(realG.MSUF_GetCastbarTexture) ~= "function" then
        function realG.MSUF_GetCastbarTexture()
            return "Interface\TARGETINGFRAME\UI-StatusBar"
        end
    end
    ROOT_G.MSUF_GetCastbarTexture = realG.MSUF_GetCastbarTexture
end
-- Performance: Localize frequently used globals
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitIsPlayer = UnitIsPlayer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math_floor = math.floor
local math_max = math.max
local tonumber = tonumber
local type = type
-- Performance: Fast indexed unitframe iteration list (Step 7)
local UnitFramesList = {}
local function MSUF_SetShown(obj, show)
    if not obj then return end
    if show then obj:Show() else obj:Hide() end
end
local function MSUF_Offset(v, default) return v == nil and default or v end
local function MSUF_EnsureUnitFlags(f)
    if not f or f._msufUnitFlagsInited then return end
    local u = f.unit
    f._msufIsPlayer = (u == "player")
    f._msufIsTarget = (u == "target")
    f._msufIsFocus  = (u == "focus")
    f._msufIsPet    = (u == "pet")
    f._msufIsToT    = (u == "targettarget")
    local bi = u and u:match("^boss(%d+)$")
    f._msufBossIndex = bi and tonumber(bi) or nil
    f._msufUnitFlagsInited = true
end
local function MSUF_IsTargetLikeFrame(f)
    return (f and (f.isBoss or f._msufIsPlayer or f._msufIsTarget or f._msufIsFocus)) and true or false
end

local function MSUF_ResetBarZero(bar, hide)
    if not bar then return end
    bar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    if hide then bar:Hide() end
end

local function MSUF_ClearText(fs, hide)
    if not fs then return end
    MSUF_SetTextIfChanged(fs, "")
    if hide then fs:Hide() end
end


local MSUF_BarBorderCache = { stamp = nil, thickness = 0 }
local function MSUF_GetBarBorderStyleId(style)
    if style == "THICK" then return 2 end
    if style == "SHADOW" then return 3 end
    if style == "GLOW" then return 4 end
    return 1 -- THIN/default
end
local function MSUF_GetDesiredBarBorderThicknessAndStamp()
    local barsDB = MSUF_DB and MSUF_DB.bars
    local gDB    = MSUF_DB and MSUF_DB.general

    local raw = barsDB and barsDB.barOutlineThickness
    local rawNum = (type(raw) == "number") and raw or tonumber(raw)
    local rawToken = rawNum and math_floor(rawNum * 10 + 0.5) or -999

    local useBit = 1
    if gDB and gDB.useBarBorder == false then useBit = 0 end

    local showToken = 1 -- nil/unspecified
    if barsDB and barsDB.showBarBorder ~= nil then
        if barsDB.showBarBorder == false then showToken = 0 else showToken = 2 end
    end

    local styleId = MSUF_GetBarBorderStyleId(gDB and gDB.barBorderStyle)
    local stamp = rawToken * 10000 + useBit * 1000 + showToken * 10 + styleId

    if MSUF_BarBorderCache.stamp ~= stamp then
        local thickness = rawNum
        if type(thickness) ~= "number" then
            local enabled = (useBit == 1)
            if barsDB and barsDB.showBarBorder ~= nil then
                enabled = (barsDB.showBarBorder ~= false)
            end
            if not enabled then
                thickness = 0
            else
                local map = { THIN = 1, THICK = 2, SHADOW = 3, GLOW = 3 }
                local style = (gDB and gDB.barBorderStyle) or "THIN"
                thickness = map[style] or 1
            end
        end
        thickness = tonumber(thickness) or 0
        thickness = math_floor(thickness + 0.5)
        if thickness < 0 then thickness = 0 end
        if thickness > 6 then thickness = 6 end
        MSUF_BarBorderCache.stamp = stamp
        MSUF_BarBorderCache.thickness = thickness
    end

    return MSUF_BarBorderCache.thickness, MSUF_BarBorderCache.stamp
end
local function MSUF_ApplyFont(fs, fontPath, size, flags)
    if not fs or not fontPath or not size then return end
    fs:SetFont(fontPath, size, flags)
end
local function MSUF_ApplyPoint(frame, point, relFrame, relPoint, x, y)
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint(point, relFrame, relPoint, x, y)
end
local function MSUF_SetStatusBarColor(bar, r, g, b, a)
    if not bar or not bar.SetStatusBarColor then return end
    if a ~= nil then
        bar:SetStatusBarColor(r, g, b, a)
    else
        bar:SetStatusBarColor(r, g, b)
    end
end
local function MSUF_SetVertexColor(tex, r, g, b, a)
    if not tex or not tex.SetVertexColor then return end
    if a ~= nil then
        tex:SetVertexColor(r, g, b, a)
    else
        tex:SetVertexColor(r, g, b)
    end
end
local function MSUF_SetTextColor(fs, r, g, b, a)
    if not fs or not fs.SetTextColor then return end
    if a ~= nil then
        fs:SetTextColor(r, g, b, a)
    else
        fs:SetTextColor(r, g, b)
    end
end
local function MSUF_CreateStyledFontString(parent, layer, template, fontPath, size, flags, justifyH, r, g, b, a)
    if not parent then return nil end
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlight")
    if fs.SetFont and fontPath and size then
        fs:SetFont(fontPath, size, flags)
    end
    if justifyH and fs.SetJustifyH then
        fs:SetJustifyH(justifyH)
    end
    if r and g and b and fs.SetTextColor then
        fs:SetTextColor(r, g, b, a or 1)
    end
    return fs
end
local function MSUF_CreateOverlayStatusBar(parent, baseBar, frameLevel, r, g, b, a, reverseFill)
    if not parent or not baseBar then return nil end
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetAllPoints(baseBar)
    bar:SetStatusBarTexture(MSUF_GetBarTexture())
    bar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(bar, 0, false)
    bar.MSUF_lastValue = 0
    if frameLevel then
        bar:SetFrameLevel(frameLevel)
    end
    if r and g and b then
        bar:SetStatusBarColor(r, g, b, a or 1)
    end
    if reverseFill ~= nil and bar.SetReverseFill then
        bar:SetReverseFill(reverseFill and true or false)
    end
    bar:Hide()
    return bar
end

-- Extra Color Options: Absorb / Heal-Absorb overlay colors
-- Stored under MSUF_DB.general.absorbBarColorR/G/B and healAbsorbBarColorR/G/B.
-- Nil = default overlay colors.
local function MSUF_GetAbsorbOverlayColor()
    local r, g, b, a = 0.8, 0.9, 1.0, 0.6
    local gen = MSUF_DB and MSUF_DB.general
    if gen then
        local ar, ag, ab = gen.absorbBarColorR, gen.absorbBarColorG, gen.absorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            if ar < 0 then ar = 0 elseif ar > 1 then ar = 1 end
            if ag < 0 then ag = 0 elseif ag > 1 then ag = 1 end
            if ab < 0 then ab = 0 elseif ab > 1 then ab = 1 end
            r, g, b = ar, ag, ab
        end
    end
    return r, g, b, a
end

local function MSUF_GetHealAbsorbOverlayColor()
    local r, g, b, a = 1.0, 0.4, 0.4, 0.7
    local gen = MSUF_DB and MSUF_DB.general
    if gen then
        local ar, ag, ab = gen.healAbsorbBarColorR, gen.healAbsorbBarColorG, gen.healAbsorbBarColorB
        if type(ar) == "number" and type(ag) == "number" and type(ab) == "number" then
            if ar < 0 then ar = 0 elseif ar > 1 then ar = 1 end
            if ag < 0 then ag = 0 elseif ag > 1 then ag = 1 end
            if ab < 0 then ab = 0 elseif ab > 1 then ab = 1 end
            r, g, b = ar, ag, ab
        end
    end
    return r, g, b, a
end

local function MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
    if not bar or not bar.SetStatusBarColor then return end
    if bar.MSUF_overlayR == r and bar.MSUF_overlayG == g and bar.MSUF_overlayB == b and bar.MSUF_overlayA == a then
        return
    end
    MSUF_SetStatusBarColor(bar, r, g, b, a)
    bar.MSUF_overlayR, bar.MSUF_overlayG, bar.MSUF_overlayB, bar.MSUF_overlayA = r, g, b, a
end

local function MSUF_ApplyAbsorbOverlayColor(bar)
    local r, g, b, a = MSUF_GetAbsorbOverlayColor()
    MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
end

local function MSUF_ApplyHealAbsorbOverlayColor(bar)
    local r, g, b, a = MSUF_GetHealAbsorbOverlayColor()
    MSUF_ApplyOverlayBarColorCached(bar, r, g, b, a)
end

local function MSUF_ApplyBackdrop(frame, backdrop)
    if not frame or not frame.SetBackdrop or not backdrop then return end
    frame:SetBackdrop(backdrop)
end
local function MSUF_ApplyBackdropBorderColor(frame, r, g, b, a)
    if not frame or not frame.SetBackdropBorderColor then return end
    if a ~= nil then
        frame:SetBackdropBorderColor(r, g, b, a)
    else
        frame:SetBackdropBorderColor(r, g, b)
    end
end
local function MSUF_ApplyBackdropColor(frame, r, g, b, a)
    if not frame or not frame.SetBackdropColor then return end
    if a ~= nil then
        frame:SetBackdropColor(r, g, b, a)
    else
        frame:SetBackdropColor(r, g, b)
    end
end
local function MSUF_NormalizeUnitKeyForDB(key)
    if not key or type(key) ~= "string" then return nil end
    if key == "tot" then
        return "targettarget"
    end
    if key:match("^boss%d+$") then
        return "boss"
    end
    return key
end
local function MSUF_ResolveFrameDBKey(f)
    local key = f and (f.unitKey or f.unit or f.msufConfigKey)
    return MSUF_NormalizeUnitKeyForDB(key or "player") or "player"
end
local function MSUF_ApplyLevelIndicatorLayout_Internal(f, conf)
    if not f or not f.levelText or not f.nameText then return end
    conf = conf or {}
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local lx = (type(conf.levelIndicatorOffsetX) == "number") and conf.levelIndicatorOffsetX
        or ((type(g.levelIndicatorOffsetX) == "number") and g.levelIndicatorOffsetX or 0)
    local ly = (type(conf.levelIndicatorOffsetY) == "number") and conf.levelIndicatorOffsetY
        or ((type(g.levelIndicatorOffsetY) == "number") and g.levelIndicatorOffsetY or 0)
    local anchor = (type(conf.levelIndicatorAnchor) == "string") and conf.levelIndicatorAnchor
        or ((type(g.levelIndicatorAnchor) == "string") and g.levelIndicatorAnchor or "NAMERIGHT")

    f._msufLevelAnchor = anchor

    local stamp = tostring(anchor) .. "|" .. tostring(lx) .. "|" .. tostring(ly)
    if f._msufLevelLayoutStamp == stamp then
        return
    end
    f._msufLevelLayoutStamp = stamp

    f.levelText:ClearAllPoints()
    if anchor == "NAMELEFT" then
        f.levelText:SetPoint("RIGHT", f.nameText, "LEFT", -6 + lx, ly)
    elseif anchor == "NAMERIGHT" then
        f.levelText:SetPoint("LEFT", f.nameText, "RIGHT", 6 + lx, ly)
    else
        local af = f.textFrame or f
        f.levelText:SetPoint(anchor, af, anchor, lx, ly)
    end
end
if not _G.MSUF_ApplyLevelIndicatorLayout then
    function _G.MSUF_ApplyLevelIndicatorLayout(f)
        if not f or not f.levelText or not f.nameText then return end
        local key = MSUF_ResolveFrameDBKey(f)
        local conf = (MSUF_DB and MSUF_DB[key]) or {}
        if key == "targettarget" and MSUF_DB and MSUF_DB.tot and
           (conf.levelIndicatorAnchor == nil and conf.levelIndicatorOffsetX == nil and conf.levelIndicatorOffsetY == nil) then
            conf = MSUF_DB.tot
        end
        MSUF_ApplyLevelIndicatorLayout_Internal(f, conf)
    end
end
local MSUF_ECV_ANCHORS = {
    player       = { "RIGHT", "LEFT",  -20,   0 },
    target       = { "LEFT",  "RIGHT",  20,   0 },
    focus        = { "TOP",   "LEFT",    0,   0 },
    targettarget = { "TOP",   "RIGHT",   0, -40 },
}
local MSUF_MAX_BOSS_FRAMES = 5          -- how many boss frames MSUF creates/handles
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
-- Performance: reuse backdrop tables to avoid allocations on style changes.
local MSUF_BORDER_BACKDROPS = {
    THIN  = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 },
    THICK = { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16 },
    SHADOW = { edgeFile = "Interface\\GLUES\\COMMON\\TextPanel-Border", edgeSize = 14 },
    GLOW  = { edgeFile = MSUF_TEX_WHITE8, edgeSize = 8 },
}
local MSUF_BORDER_DEFAULT = MSUF_BORDER_BACKDROPS.THIN
local floor  = math.floor
local max    = math.max
local min    = math.min
local format = string.format
local MSUF_Transactions = {}  -- scopeKey -> { snapshot=table, restore=function|nil, active=true }
function MSUF_BeginTransaction(scopeKey, snapshot, restoreFunc)
    if not scopeKey then
        return
    end
    MSUF_Transactions[scopeKey] = {
        snapshot = MSUF_DeepCopy(snapshot) or {},
        restore = restoreFunc,
        active = true,
    }
end
function MSUF_HasTransaction(scopeKey)
    local t = scopeKey and MSUF_Transactions[scopeKey]
    return not not (t and t.active and t.snapshot)
end
function MSUF_GetTransactionSnapshot(scopeKey)
    local t = scopeKey and MSUF_Transactions[scopeKey]
    return t and t.snapshot
end
function MSUF_CommitTransaction(scopeKey)
    if not scopeKey then
        return
    end
    MSUF_Transactions[scopeKey] = nil
end
function MSUF_RollbackTransaction(scopeKey)
    if not scopeKey then
        return
    end
    local t = MSUF_Transactions[scopeKey]
    if not (t and t.active) then
        return
    end
    if type(t.restore) == "function" then
        local ok, err = pcall(t.restore, MSUF_DeepCopy(t.snapshot))
        if not ok then
            if type(print) == "function" then
                print("MSUF: rollback failed for scope", scopeKey, err)
            end
        end
    end
    return t.snapshot
end
ns.MSUF_DeepCopy = MSUF_DeepCopy
ns.MSUF_CaptureKeys = MSUF_CaptureKeys
ns.MSUF_RestoreKeys = MSUF_RestoreKeys
ns.MSUF_Transactions = MSUF_Transactions
local MSUF_SMOOTH_INTERPOLATION = (type(Enum) == "table"
    and Enum.StatusBarInterpolation
    and Enum.StatusBarInterpolation.ExponentialEaseOut) or nil

-- Performance/Secret-safe (no pcall): NEVER compare (numbers can be "secret"). Always apply the value.
-- This avoids secret-compare crashes entirely and removes tostring/tonumber churn from hotpaths.
function MSUF_SetBarValue(bar, value, smooth)
    if not bar or value == nil then return end

    -- Allow numeric strings (some APIs/config paths may pass "0" etc.)
    if type(value) == "string" then
        local n = tonumber(value)
        if type(n) ~= "number" then
            return
        end
        value = n
    end

    if smooth and MSUF_SMOOTH_INTERPOLATION then
        bar:SetValue(value, MSUF_SMOOTH_INTERPOLATION)
    else
        bar:SetValue(value)
    end
end

function MSUF_SetBarMinMax(bar, minValue, maxValue)
    if not bar or minValue == nil or maxValue == nil then
        return
    end

    if type(minValue) == "string" then
        minValue = tonumber(minValue)
    end
    if type(maxValue) == "string" then
        maxValue = tonumber(maxValue)
    end
    if type(minValue) ~= "number" or type(maxValue) ~= "number" then
        return
    end

    -- No caching/compare here either (secret-safe, no pcall).
    bar:SetMinMaxValues(minValue, maxValue)
end
local pairs   = pairs   -- wir nutzen pairs ziemlich oft, bisher als Global
MSUF_UnitEditModeActive = (MSUF_UnitEditModeActive == true)
MSUF_CurrentOptionsKey = MSUF_CurrentOptionsKey
MSUF_CurrentEditUnitKey = MSUF_CurrentEditUnitKey
MSUF_EditModeSizing = (MSUF_EditModeSizing == true)
if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
    MSUF_SyncBossUnitframePreviewWithUnitEdit()
end
local LSM = (ns and ns.LSM) or _G.MSUF_LSM or (LibStub and LibStub("LibSharedMedia-3.0", true))

-- Load-order safety: MSUF_Libs.lua may acquire LibSharedMedia after this file loads.
-- We cache LSM in this file as a local upvalue for performance, so provide a hook to refresh it.
_G.MSUF_OnLSMReady = function(lsm)
    LSM = lsm
end

if LSM and not _G.MSUF_LSM_CallbacksRegistered and not MSUF_LSM_FontCallbackRegistered then
    MSUF_LSM_FontCallbackRegistered = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediatype, key)
        if mediatype ~= "font" then return end
        if MSUF_RebuildFontChoices then
            MSUF_RebuildFontChoices()
        end
        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.fontKey == key then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if UpdateAllFonts then
                        UpdateAllFonts()
                    end
                end)
            elseif UpdateAllFonts then
                UpdateAllFonts()
            end
        end
    end)
end
local FONT_LIST = {
    {
        key  = "FRIZQT",
        name = "Friz Quadrata (default)",
        path = "Fonts\\FRIZQT__.TTF",
    },
{
        key  = "ARIALN",
        name = "Arial (default)",
        path = "Fonts\\ARIALN.TTF",
    },
    {
        key  = "MORPHEUS",
        name = "Morpheus (default)",
        path = "Fonts\\MORPHEUS.TTF",
    },
    {
        key  = "SKURRI",
        name = "Skurri (default)",
        path = "Fonts\\SKURRI.TTF",
    },
}

-- Bundled MSUF fonts (Media/Fonts) must be selectable even when LibSharedMedia
-- is not installed. These entries use direct file paths and therefore do not
-- depend on LSM.
do
    local base = "Interface\\AddOns\\" .. tostring(addonName) .. "\\Media\\Fonts\\"
    local bundled = {
        { key = "EXPRESSWAY",                 name = "Expressway Regular (MSUF)",          file = "Expressway Regular.ttf" },
        { key = "EXPRESSWAY_BOLD",            name = "Expressway Bold (MSUF)",             file = "Expressway Bold.ttf" },
        { key = "EXPRESSWAY_SEMIBOLD",        name = "Expressway SemiBold (MSUF)",         file = "Expressway SemiBold.ttf" },
        { key = "EXPRESSWAY_EXTRABOLD",       name = "Expressway ExtraBold (MSUF)",        file = "Expressway ExtraBold.ttf" },
        { key = "EXPRESSWAY_CONDENSED_LIGHT", name = "Expressway Condensed Light (MSUF)",  file = "Expressway Condensed Light.otf" },
    }

    local function HasFontKey(list, key)
        if type(key) ~= "string" or key == "" then return false end
        if type(list) ~= "table" then return false end
        for i = 1, #list do
            local t = list[i]
            if t and t.key == key then
                return true
            end
        end
        return false
    end

    for _, info in ipairs(bundled) do
        if not HasFontKey(FONT_LIST, info.key) then
            table.insert(FONT_LIST, {
                key  = info.key,
                name = info.name,
                path = base .. info.file,
            })
        end
    end
end
_G.MSUF_FONT_LIST = _G.MSUF_FONT_LIST or FONT_LIST
local MSUF_FONT_COLORS = {
    white     = {1.0, 1.0, 1.0},
    black     = {0.0, 0.0, 0.0},
    red       = {1.0, 0.0, 0.0},
    green     = {0.0, 1.0, 0.0},
    blue      = {0.0, 0.0, 1.0},
    yellow    = {1.0, 1.0, 0.0},
    cyan      = {0.0, 1.0, 1.0},
    magenta   = {1.0, 0.0, 1.0},
    orange    = {1.0, 0.5, 0.0},
    purple    = {0.6, 0.0, 0.8},
    pink      = {1.0, 0.6, 0.8},
    turquoise = {0.0, 0.9, 0.8},
    grey      = {0.5, 0.5, 0.5},
    brown     = {0.6, 0.3, 0.1},
    gold      = {1.0, 0.85, 0.1},
}
ns.MSUF_FONT_COLORS = MSUF_FONT_COLORS
_G.MSUF_FONT_COLORS = _G.MSUF_FONT_COLORS or MSUF_FONT_COLORS
local function MSUF_GetNPCReactionColor(kind)
    local defaultR, defaultG, defaultB
    if kind == "friendly" then
        defaultR, defaultG, defaultB = 0, 1, 0           -- grün
    elseif kind == "neutral" then
        defaultR, defaultG, defaultB = 1, 1, 0           -- gelb
    elseif kind == "enemy" then
        defaultR, defaultG, defaultB = 0.85, 0.10, 0.10  -- rot
    elseif kind == "dead" then
        defaultR, defaultG, defaultB = 0.4, 0.4, 0.4     -- grau (tote NPCs)
    else
        defaultR, defaultG, defaultB = 1, 1, 1
    end
    if not MSUF_DB or not EnsureDB then
        return defaultR, defaultG, defaultB
    end
    EnsureDB()
    MSUF_DB.npcColors = MSUF_DB.npcColors or {}
    local t = MSUF_DB.npcColors[kind]
    if t and t.r and t.g and t.b then
        return t.r, t.g, t.b
    end
    return defaultR, defaultG, defaultB
end
local function MSUF_GetClassBarColor(classToken)
    local defaultR, defaultG, defaultB = 0, 1, 0
    if not classToken then
        return defaultR, defaultG, defaultB
    end
    EnsureDB()
    MSUF_DB.classColors = MSUF_DB.classColors or {}
    local override = MSUF_DB.classColors[classToken]
    if type(override) == "table" and override.r and override.g and override.b then
        return override.r, override.g, override.b
    end
    if type(override) == "string" and MSUF_FONT_COLORS and MSUF_FONT_COLORS[override] then
        local c = MSUF_FONT_COLORS[override]
        return c[1], c[2], c[3]
    end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then
        return color.r, color.g, color.b
    end
    return defaultR, defaultG, defaultB
end
local function MSUF_GetPowerBarColor(powerType, powerToken)
    if not powerToken or powerToken == "" then
        return nil
    end
    if not MSUF_DB or not EnsureDB then
        return nil
    end
    EnsureDB()
    local g = MSUF_DB.general
    local ov = g and g.powerColorOverrides
    if type(ov) ~= "table" then
        return nil
    end
    local c = ov[powerToken]
    if type(c) ~= "table" then
        return nil
    end
    local r, gg, b
    if type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        r, gg, b = c.r, c.g, c.b
    else
        r, gg, b = c[1], c[2], c[3]
    end
    if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
        return r, gg, b
    end
    return nil
end
_G.MSUF_GetPowerBarColor = MSUF_GetPowerBarColor

-- Returns the effective power color for a given unit power type.
-- Priority: MSUF overrides (if configured) -> Blizzard PowerBarColor -> nil.
local function MSUF_GetResolvedPowerColor(powerType, powerToken)
    -- 1) MSUF override table (if present)
    if type(MSUF_GetPowerBarColor) == "function" then
        local r, g, b = MSUF_GetPowerBarColor(powerType, powerToken)
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    -- 2) Blizzard power colors (prefer token)
    local pbc = _G.PowerBarColor
    if type(powerToken) == "string" and pbc and pbc[powerToken] then
        local c = pbc[powerToken]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    -- 3) Fallback by numeric power type index
    if type(powerType) == "number" and pbc and pbc[powerType] then
        local c = pbc[powerType]
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end

    return nil
end
_G.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor
ns.MSUF_GetResolvedPowerColor = MSUF_GetResolvedPowerColor

local function MSUF_GetConfiguredFontColor()
    EnsureDB()
    local g = MSUF_DB.general or {}
    if g.useCustomFontColor and g.fontColorCustomR and g.fontColorCustomG and g.fontColorCustomB then
        return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
    end
    local key   = (g.fontColor or "white"):lower()
    local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
    return color[1], color[2], color[3]
end
ns.MSUF_GetConfiguredFontColor = MSUF_GetConfiguredFontColor
local MSUF_FontPreviewObjects = {}
local function MSUF_GetFontPreviewObject(key)
    if not key or key == "" then
        return GameFontHighlightSmall
    end
    local obj = MSUF_FontPreviewObjects[key]
    if not obj then
        obj = CreateFont("MSUF_FontPreview_" .. tostring(key))
        MSUF_FontPreviewObjects[key] = obj
    end
    local path
    if LSM then
        -- IMPORTANT: use noDefault=true so internal (non-LSM) keys like "FRIZQT"/"ARIALN"/"MORPHEUS"
        local p = LSM:Fetch("font", key, true)
        if p then
            path = p
        end
    end
    if not path then
        path = GetInternalFontPathByKey(key) or FONT_LIST[1].path
    end
    obj:SetFont(path, 14, "")
    return obj
end
ns.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
_G.MSUF_GetFontPreviewObject = MSUF_GetFontPreviewObject
local function MSUF_GetColorFromKey(key, fallbackColor)
    if type(key) ~= "string" then
        if fallbackColor then
            return fallbackColor
        end
        return CreateColor(1, 1, 1, 1)
    end
    local normalized = string.lower(key)
    local rgb = MSUF_FONT_COLORS[normalized]
    if rgb then
        local r, g, b = rgb[1], rgb[2], rgb[3]
        return CreateColor(r or 1, g or 1, b or 1, 1)
    end
    if fallbackColor then
        return fallbackColor
    end
    return CreateColor(1, 1, 1, 1)
end
ns.MSUF_GetColorFromKey = MSUF_GetColorFromKey
_G.MSUF_GetColorFromKey = MSUF_GetColorFromKey
MSUF_DARK_TONES = {
    black    = {0.0, 0.0, 0.0},
    darkgray = {0.08, 0.08, 0.08},
    softgray = {0.16, 0.16, 0.16},
}
function GetInternalFontPathByKey(key)
    if not key then return nil end
    for _, info in ipairs(FONT_LIST) do
        if info.key == key or info.name == key then
            return info.path
        end
    end
    return nil
end
MSUF_BossTestMode = MSUF_BossTestMode or false
local MSUF_CooldownWarningFrame
_G.MSUF_CastbarUnitInfo = _G.MSUF_CastbarUnitInfo or {
    player = { label = "Player Castbar", prefix = "castbarPlayer", defaultX = 0,  defaultY = 5,   showTimeKey = "showPlayerCastTime", isBoss = false },
    target = { label = "Target Castbar", prefix = "castbarTarget", defaultX = 65, defaultY = -15, showTimeKey = "showTargetCastTime", isBoss = false },
    focus  = { label = "Focus Castbar",  prefix = "castbarFocus",  defaultX = 65, defaultY = -15, showTimeKey = "showFocusCastTime",  isBoss = false },
    boss   = { label = "Boss Castbar",   prefix = nil,             defaultX = 0,  defaultY = 0,   showTimeKey = "showBossCastTime",   isBoss = true  },
}
function MSUF_GetCastbarUnitInfo(unitKey)
    local m = _G.MSUF_CastbarUnitInfo
    return m and m[unitKey] or nil
end
function MSUF_IsBossCastbarUnit(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return (i and i.isBoss) and true or false
end
function MSUF_GetCastbarPrefix(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return i and i.prefix or nil
end
function MSUF_GetCastbarLabel(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return (i and i.label) or tostring(unitKey or "")
end
function MSUF_GetCastbarDefaultOffsets(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    if not i then return 0, 0 end
    return i.defaultX or 0, i.defaultY or 0
end
function MSUF_GetCastbarShowTimeKey(unitKey)
    local i = MSUF_GetCastbarUnitInfo(unitKey)
    return i and i.showTimeKey or nil
end
function MSUF_GetCastbarShowNameKey(unitKey)
    if MSUF_IsBossCastbarUnit(unitKey) then
        return "showBossCastName"
    end
    local p = MSUF_GetCastbarPrefix(unitKey)
    return p and (p .. "ShowSpellName") or nil
end
function MSUF_GetCastbarShowIconKey(unitKey)
    if MSUF_IsBossCastbarUnit(unitKey) then
        return "showBossCastIcon"
    end
    local p = MSUF_GetCastbarPrefix(unitKey)
    return p and (p .. "ShowIcon") or nil
end
function MSUF_GetCastbarUnitFromFrame(frame)
    if not frame then return nil end
    if _G.MSUF_BossCastbarPreview and frame == _G.MSUF_BossCastbarPreview then
        return "boss"
    end
    if (MSUF_PlayerCastbar and frame == MSUF_PlayerCastbar) or (MSUF_PlayerCastbarPreview and frame == MSUF_PlayerCastbarPreview) then
        return "player"
    end
    if (MSUF_TargetCastbar and frame == MSUF_TargetCastbar) or (MSUF_TargetCastbarPreview and frame == MSUF_TargetCastbarPreview) then
        return "target"
    end
    if (MSUF_FocusCastbar and frame == MSUF_FocusCastbar) or (MSUF_FocusCastbarPreview and frame == MSUF_FocusCastbarPreview) then
        return "focus"
    end
    return nil
end
function MSUF_ApplyUnitframeKeyAndSync(key, changedFonts)
    if not key then return end
    EnsureDB()
    if ApplySettingsForKey then
        ApplySettingsForKey(key)
    elseif ApplyAllSettings then
        ApplyAllSettings()
    end
    if changedFonts then
        if _G.MSUF_UpdateAllFonts then
            _G.MSUF_UpdateAllFonts()
        elseif ns and ns.MSUF_UpdateAllFonts then
            ns.MSUF_UpdateAllFonts()
        end
    end


-- Centralized live refresh for Target/ToT-Inline after unitframe apply.
if (key == "target" or key == "targettarget") and ns and ns.MSUF_ToTInline_RequestRefresh then
    ns.MSUF_ToTInline_RequestRefresh("UF_APPLY")
end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
function MSUF_ApplyCastbarUnitAndSync(unitKey)
    if not unitKey then return end
    EnsureDB()
    if MSUF_IsBossCastbarUnit(unitKey) then
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
            _G.MSUF_ApplyBossCastbarPositionSetting()
        end
        if type(_G.MSUF_ApplyBossCastbarTimeSetting) == "function" then
            _G.MSUF_ApplyBossCastbarTimeSetting()
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
        end
        if type(MSUF_SyncCastbarPositionPopup) == "function" then
            MSUF_SyncCastbarPositionPopup("boss")
        end
        return
    end
    if unitKey == "player" and type(MSUF_ReanchorPlayerCastBar) == "function" then
        MSUF_ReanchorPlayerCastBar()
    elseif unitKey == "target" and type(MSUF_ReanchorTargetCastBar) == "function" then
        MSUF_ReanchorTargetCastBar()
    elseif unitKey == "focus" and type(MSUF_ReanchorFocusCastBar) == "function" then
        MSUF_ReanchorFocusCastBar()
    end
    do
        local fn = _G.MSUF_UpdateCastbarVisuals_Immediate or MSUF_UpdateCastbarVisuals
        if type(fn) == "function" then
            fn()
        end
    end
    if type(MSUF_UpdateCastbarEditInfo) == "function" then
        MSUF_UpdateCastbarEditInfo(unitKey)
    end
    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup(unitKey)
    end
end
local function MSUF_GetFontPath()
    -- Safety: EnsureDB() should initialize MSUF_DB.general, but we guard here
    -- to avoid nil-index crashes if DB init order changes.
    if type(EnsureDB) == "function" then EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}

    local key = MSUF_DB.general.fontKey
    if LSM and key and key ~= "" then
        local p = LSM:Fetch("font", key, true)
        if p then
            return p
        end
    end

    local internalPath = GetInternalFontPathByKey(key)
    if internalPath then
        return internalPath
    end
    return FONT_LIST[1].path
end

local function MSUF_GetFontFlags()
    if type(EnsureDB) == "function" then EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}

    local g = MSUF_DB.general
    if g.noOutline then
        return ""              -- kein OUTLINE / THICKOUTLINE
    elseif g.boldText then
        return "THICKOUTLINE"  -- fetter schwarzer Rand
    else
        return "OUTLINE"       -- normaler dünner Rand
    end
end
function ns.MSUF_GetGlobalFontSettings()
    EnsureDB()
    local g = MSUF_DB.general or {}
    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    local baseSize  = g.fontSize or 14
    local useShadow = g.textBackdrop and true or false
    return path, flags, fr, fg, fb, baseSize, useShadow
end
function MSUF_GetGlobalFontSettings()
    if ns and ns.MSUF_GetGlobalFontSettings then
        return ns.MSUF_GetGlobalFontSettings()
    end
    return "Fonts\\FRIZQT__.TTF", "OUTLINE", 1, 1, 1, 14, false
end
function MSUF_GetCastbarTexture()
    if not MSUF_DB then
        EnsureDB()
    end
    local g = MSUF_DB and MSUF_DB.general
    local castKey = g and g.castbarTexture or nil
    local barKey = g and g.barTexture or nil
    local cache = ROOT_G.MSUF_CastbarTextureCache
    if not cache then
        cache = {}
        ROOT_G.MSUF_CastbarTextureCache = cache
    end
    local ck = tostring(castKey or "") .. "|" .. tostring(barKey or "")
    local cached = cache[ck]
    if cached then
        return cached
    end
    local tex
    if castKey and castKey ~= "" and LSM and LSM.Fetch then
        tex = LSM:Fetch("statusbar", castKey)
    end
    if not tex or tex == "" then
        if barKey and barKey ~= "" and LSM and LSM.Fetch then
            tex = LSM:Fetch("statusbar", barKey)
        end
    end
    if not tex or tex == "" then
        tex = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    cache[ck] = tex
    return tex
end
ROOT_G.MSUF_GetCastbarTexture = MSUF_GetCastbarTexture
_G.MSUF_GetCastbarTexture = MSUF_GetCastbarTexture
local function MSUF_IsCastTimeEnabled(frame)
    if not frame or not frame.unit then
        return true
    end
    local g = MSUF_DB and MSUF_DB.general
    if not g then
        return true
    end
    local u = frame.unit
    if u == "player" then
        return g.showPlayerCastTime ~= false
    elseif u == "target" then
        return g.showTargetCastTime ~= false
    elseif u == "focus" then
        return g.showFocusCastTime ~= false
    end
    return true
end
function MSUF_GetCastbarReverseFill(isChanneled)
    if not MSUF_DB then
        EnsureDB()
    end
    local g = MSUF_DB and MSUF_DB.general
    local dir = g and g.castbarFillDirection or "RTL"
    local uni = g and g.castbarUnifiedDirection or false
    if dir == "LEFT" then
        dir = "RTL"
    elseif dir == "RIGHT" then
        dir = "LTR"
    end
    if dir ~= "RTL" and dir ~= "LTR" then
        dir = "RTL"
    end
    local cache = _G.MSUF_CastbarReverseFillCache
    if not cache then
        cache = {}
        _G.MSUF_CastbarReverseFillCache = cache
    end
    local ck = tostring(dir) .. "|" .. tostring(uni) .. "|" .. tostring(isChanneled and 1 or 0)
    local cached = cache[ck]
    if cached ~= nil then
        return cached
    end
    local reverseNormal = (dir == "RTL")
    local reverse
    if uni then
        reverse = reverseNormal
    else
        if isChanneled then
            reverse = not reverseNormal
        else
            reverse = reverseNormal
        end
    end
    cache[ck] = reverse and true or false
    return cache[ck]
end
if not _G.MSUF_CastbarStyleRevision then
    _G.MSUF_CastbarStyleRevision = 1
end
function MSUF_BumpCastbarStyleRevision()
    local r = _G.MSUF_CastbarStyleRevision or 1
    _G.MSUF_CastbarStyleRevision = r + 1
    return _G.MSUF_CastbarStyleRevision
end
function MSUF_GetGlobalCastbarStyleCache()
    local rev = _G.MSUF_CastbarStyleRevision or 1
    local cache = _G.MSUF_GlobalCastbarStyleCache
    if cache and cache.rev == rev then
        return cache
    end
    cache = cache or {}
    cache.rev = rev
    if not MSUF_DB then
        EnsureDB()
    end
    local g = (MSUF_DB and MSUF_DB.general) or {}
    cache.unifiedDirection = (g.castbarUnifiedDirection == true)
    local tex
    if type(MSUF_GetCastbarTexture) == "function" then
        tex = MSUF_GetCastbarTexture()
    end
    if not tex or tex == "" then
        tex = "Interface\\TARGETINGFRAME\\UI-StatusBar"
    end
    cache.texture = tex
    if type(MSUF_GetCastbarReverseFill) == "function" then
        cache.reverseFillNormal    = MSUF_GetCastbarReverseFill(false) and true or false
        cache.reverseFillChanneled = MSUF_GetCastbarReverseFill(true)  and true or false
    else
        cache.reverseFillNormal    = false
        cache.reverseFillChanneled = false
    end
    _G.MSUF_GlobalCastbarStyleCache = cache
    return cache
end
function MSUF_RefreshCastbarStyleCache(frame)
    if not frame then return end
    local rev = _G.MSUF_CastbarStyleRevision or 1
    if frame.MSUF_castbarStyleRev == rev then
        return
    end
    local c = MSUF_GetGlobalCastbarStyleCache and MSUF_GetGlobalCastbarStyleCache() or nil
    frame.MSUF_castbarStyleRev = rev
    if c then
        frame.MSUF_cachedUnifiedDirection     = (c.unifiedDirection == true)
        frame.MSUF_cachedCastbarTexture       = c.texture
        frame.MSUF_cachedReverseFillNormal    = (c.reverseFillNormal == true)
        frame.MSUF_cachedReverseFillChanneled = (c.reverseFillChanneled == true)
    end
end
local function MSUF_GetCastbarReverseFillForFrame(frame, isChanneled)
    if type(MSUF_RefreshCastbarStyleCache) == "function" then
        MSUF_RefreshCastbarStyleCache(frame)
    end
    local base
    if frame then
        if isChanneled then
            base = (frame.MSUF_cachedReverseFillChanneled == true)
        else
            base = (frame.MSUF_cachedReverseFillNormal == true)
        end
    else
        base = (type(MSUF_GetCastbarReverseFill) == "function" and MSUF_GetCastbarReverseFill(isChanneled)) or false
    end
    return base and true or false
end
_G.MSUF_GetCastbarReverseFillForFrame = MSUF_GetCastbarReverseFillForFrame
local function MSUF_ForMainCastbars(fn)
    fn(MSUF_PlayerCastbar)
    fn(MSUF_TargetCastbar)
    fn(MSUF_FocusCastbar)
    fn(MSUF_PlayerCastbarPreview)
    fn(MSUF_TargetCastbarPreview)
    fn(MSUF_FocusCastbarPreview)
end
function MSUF_UpdateCastbarTextures()
    if type(MSUF_BumpCastbarStyleRevision) == "function" then MSUF_BumpCastbarStyleRevision() end
    local __msufStyleRev = _G.MSUF_CastbarStyleRevision or 1
    local tex = MSUF_GetCastbarTexture()
    if not tex then return end
    local function Apply(frame)
        if frame and frame.statusBar then
            frame.statusBar:SetStatusBarTexture(tex)
            frame.MSUF_castbarStyleRev = __msufStyleRev
            frame.MSUF_cachedCastbarTexture = tex
            if type(MSUF_GetCastbarReverseFill) == "function" then
                frame.MSUF_cachedReverseFillNormal    = MSUF_GetCastbarReverseFill(false) and true or false
                frame.MSUF_cachedReverseFillChanneled = MSUF_GetCastbarReverseFill(true)  and true or false
            end
            EnsureDB(); frame.MSUF_cachedUnifiedDirection = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarUnifiedDirection) == true
        end
        if frame and frame.backgroundBar then
            frame.backgroundBar:SetTexture(tex)
        end
    end
    MSUF_ForMainCastbars(Apply)
end
function MSUF_UpdateCastbarFillDirection()
    if type(MSUF_BumpCastbarStyleRevision) == "function" then
        MSUF_BumpCastbarStyleRevision()
    end
    local function Apply(frame)
        if frame and frame.statusBar and frame.statusBar.SetReverseFill then
            local isChanneled = false
            if frame.isEmpower then
                isChanneled = true
            elseif frame.MSUF_isChanneled then
                isChanneled = true
            elseif frame.unit and (frame.unit == "player" or frame.unit == "target" or frame.unit == "focus") then
                if UnitChannelInfo and UnitChannelInfo(frame.unit) then
                    isChanneled = true
                end
            end
            if type(MSUF_RefreshCastbarStyleCache) == "function" then
                MSUF_RefreshCastbarStyleCache(frame)
            end
            local rf = MSUF_GetCastbarReverseFillForFrame(frame, isChanneled)
            pcall(frame.statusBar.SetReverseFill, frame.statusBar, rf and true or false)
        end
    end
    MSUF_ForMainCastbars(Apply)
end
function MSUF_ResolveStatusbarTextureKey(key)
    local defaultTex = "Interface\\TargetingFrame\\UI-StatusBar"
    local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES
    if type(builtins) == "table" and type(key) == "string" then
        local t = builtins[key]
        if type(t) == "string" and t ~= "" then
            return t
        end
    end
    if type(key) == "string" then
        if key:find("\\") or key:find("/") then
            return key
        end
    end
    if LSM and type(LSM.Fetch) == "function" and type(key) == "string" and key ~= "" then
        local tex = LSM:Fetch("statusbar", key, true)
        if tex then
            return tex
        end
    end
    return defaultTex
end
_G.MSUF_ResolveStatusbarTextureKey = MSUF_ResolveStatusbarTextureKey
_G.MSUF_BUILTIN_BAR_TEXTURES = _G.MSUF_BUILTIN_BAR_TEXTURES or {
    Blizzard   = "Interface\\TargetingFrame\\UI-StatusBar",
    Flat       = "Interface\\Buttons\\WHITE8x8",
    RaidHP     = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    RaidPower  = "Interface\\RaidFrame\\Raid-Bar-Resource-Fill",
    Skills     = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
    Outline        = "Interface\\Tooltips\\UI-Tooltip-Background",
    TooltipBorder  = "Interface\\Tooltips\\UI-Tooltip-Border",
    DialogBG       = "Interface\\DialogFrame\\UI-DialogBox-Background",
    Parchment      = "Interface\\AchievementFrame\\UI-Achievement-StatsBackground",
}
function MSUF_GetBarTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.barTexture
    return MSUF_ResolveStatusbarTextureKey(key)
end
function MSUF_GetBarBackgroundTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.barBackgroundTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end

function MSUF_GetAbsorbBarTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.absorbBarTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end

function MSUF_GetHealAbsorbBarTexture()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local key = g and g.healAbsorbBarTexture
    if key == nil or key == "" then
        key = g and g.barTexture
    end
    return MSUF_ResolveStatusbarTextureKey(key)
end

local function MSUF_Clamp01(v)
    v = tonumber(v)
    if not v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end
function MSUF_GetBarBackgroundTintRGBA()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local r = MSUF_Clamp01(g.classBarBgR)
    local gg = MSUF_Clamp01(g.classBarBgG)
    local b = MSUF_Clamp01(g.classBarBgB)
    local a = 0.9
    if g.darkMode then
        local br = MSUF_Clamp01(g.darkBgBrightness)
        r, gg, b = r * br, gg * br, b * br
    end
    return r, gg, b, a
end


-- Extra Color Options: Power bar background tint (power background only)
-- Stored under MSUF_DB.general.powerBarBgColorR/G/B.
-- Nil = follow the global bar background tint.
function MSUF_GetPowerBarBackgroundTintRGBA()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local ar, ag, ab = g.powerBarBgColorR, g.powerBarBgColorG, g.powerBarBgColorB
    if type(ar) ~= "number" or type(ag) ~= "number" or type(ab) ~= "number" then
        return MSUF_GetBarBackgroundTintRGBA()
    end
    local r = MSUF_Clamp01(ar)
    local gg = MSUF_Clamp01(ag)
    local b = MSUF_Clamp01(ab)
    local a = 0.9
    if g.darkMode then
        local br = MSUF_Clamp01(g.darkBgBrightness)
        r, gg, b = r * br, gg * br, b * br
    end
    return r, gg, b, a
end
function MSUF_ApplyBarBackgroundVisual(frame)
    if not frame then return end
    local tex = MSUF_GetBarBackgroundTexture()
    local r, gg, b, a = MSUF_GetBarBackgroundTintRGBA()

    -- Optional: match the HP background tint hue to the current HEALTH bar color.
    -- Lets users keep the background automatically in sync with whatever health color mode is active
    -- (class/reaction/unified), without having to pick a separate tint color.
    local gen = MSUF_DB and MSUF_DB.general
    if gen and gen.barBgMatchHPColor and frame.hpBar and frame.hpBar.GetStatusBarColor then
        local fr, fg, fb = frame.hpBar:GetStatusBarColor()
        if type(fr) == "number" and type(fg) == "number" and type(fb) == "number" then
            if gen.darkMode then
                local br = gen.darkBgBrightness
                if type(br) == "number" then
                    if br < 0 then br = 0 elseif br > 1 then br = 1 end
                    fr, fg, fb = fr * br, fg * br, fb * br
                end
            end
            r, gg, b = MSUF_Clamp01(fr), MSUF_Clamp01(fg), MSUF_Clamp01(fb)
        end
    end
    -- User-controlled base alpha for bar background textures (0..100).
    -- Independent from unit alpha in/out of combat.
    local alphaPct = 90
    if MSUF_DB and MSUF_DB.bars and type(MSUF_DB.bars.barBackgroundAlpha) == 'number' then
        alphaPct = MSUF_DB.bars.barBackgroundAlpha
    end
    if alphaPct < 0 then alphaPct = 0 elseif alphaPct > 100 then alphaPct = 100 end
    local alphaMul = alphaPct / 100
    if type(a) == 'number' then a = a * alphaMul end
    local function ApplyToTexture(t, cachePrefix, cr, cg, cb, ca)
        if not t then return end
        local kTex = "_msuf" .. cachePrefix .. "BgTex"
        local kR   = "_msuf" .. cachePrefix .. "BgR"
        local kG   = "_msuf" .. cachePrefix .. "BgG"
        local kB   = "_msuf" .. cachePrefix .. "BgB"
        local kA   = "_msuf" .. cachePrefix .. "BgA"
        if frame[kTex] ~= tex then
            t:SetTexture(tex)
            frame[kTex] = tex
        end
        if frame[kR] ~= cr or frame[kG] ~= cg or frame[kB] ~= cb or frame[kA] ~= ca then
            t:SetVertexColor(cr, cg, cb, ca)
            frame[kR], frame[kG], frame[kB], frame[kA] = cr, cg, cb, ca
        end
    end
    ApplyToTexture(frame.hpBarBG, "HP", r, gg, b, a)
    local pr, pg, pb, pa = MSUF_GetPowerBarBackgroundTintRGBA()

    if type(pa) == 'number' then pa = pa * alphaMul end

    -- Optional: match the power bar background hue to the current HEALTH bar color.
    -- (Primarily useful when the power bar is embedded into the health bar.)
    local bars = MSUF_DB and MSUF_DB.bars
    local matchHP = (gen and gen.powerBarBgMatchHPColor) or (bars and bars.powerBarBgMatchBarColor)
    if matchHP and frame.hpBar and frame.hpBar.GetStatusBarColor then
        local fr, fg, fb = frame.hpBar:GetStatusBarColor()
        if type(fr) == "number" and type(fg) == "number" and type(fb) == "number" then
            if gen and gen.darkMode then
                local br = gen.darkBgBrightness
                if type(br) == "number" then
                    if br < 0 then br = 0 elseif br > 1 then br = 1 end
                    fr, fg, fb = fr * br, fg * br, fb * br
                end
            end
            pr, pg, pb = MSUF_Clamp01(fr), MSUF_Clamp01(fg), MSUF_Clamp01(fb)
        end
    end

    ApplyToTexture(frame.powerBarBG, "Power", pr, pg, pb, pa)
    if (not frame.hpBarBG) and (not frame.powerBarBG) and frame.bg then
        ApplyToTexture(frame.bg, "Frame", r, gg, b, a)
    end
end
local function GetConfigKeyForUnit(unit)
    if unit == "player"
        or unit == "target"
        or unit == "focus"
        or unit == "targettarget"
        or unit == "pet"
    then
        return unit
    elseif unit and unit:match("^boss%d+$") then
        return "boss"
    end
    return nil
end

-- HP Spacer UI selection: which unit's settings are currently shown in the Bars menu.
-- This is a non-gameplay UI state stored in MSUF_DB.general.hpSpacerSelectedUnitKey.
function _G.MSUF_GetHpSpacerSelectedUnitKey()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local k = g.hpSpacerSelectedUnitKey or "player"
    if k == "tot" then k = "targettarget" end
    if type(k) == "string" and k:match("^boss%d+$") then k = "boss" end
    if k ~= "player" and k ~= "target" and k ~= "focus" and k ~= "targettarget" and k ~= "pet" and k ~= "boss" then
        k = "player"
    end
    g.hpSpacerSelectedUnitKey = k
    return k
end

function _G.MSUF_SetHpSpacerSelectedUnitKey(unitKey, suppressUIRefresh)
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local k = unitKey or "player"
    if k == "tot" then k = "targettarget" end
    if type(k) == "string" and k:match("^boss%d+$") then k = "boss" end
    if k ~= "player" and k ~= "target" and k ~= "focus" and k ~= "targettarget" and k ~= "pet" and k ~= "boss" then
        k = "player"
    end
    g.hpSpacerSelectedUnitKey = k
    if not suppressUIRefresh and type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then
        _G.MSUF_Options_RefreshHPSpacerControls()
    end
end
function _G.MSUF_GetDesiredUnitAlpha(key)
    EnsureDB()
    local conf = key and MSUF_DB and MSUF_DB[key]
    if not conf then
        return 1
    end

    local aInLegacy  = tonumber(conf.alphaInCombat) or 1
    local aOutLegacy = tonumber(conf.alphaOutOfCombat) or 1

    -- Layered alpha uses separate values per layer mode, so switching the dropdown doesn't
    -- suddenly reuse the same slider values for the other layer.
    local aIn, aOut = aInLegacy, aOutLegacy
    if conf.alphaExcludeTextPortrait == true then
        local mode = conf.alphaLayerMode
        -- Accept compact numeric/bool encoding (survives aggressive DB sanitizers).
        --   background: true / 1 / "background"
        --   foreground: false / 0 / "foreground" (default)
        if mode == true or mode == 1 or mode == "background" then
            mode = "background"
        else
            mode = "foreground"
        end

        if mode == "background" then
            aIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy
        else
            aIn  = tonumber(conf.alphaFGInCombat) or aInLegacy
            aOut = tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
        end
    end

    local sync = conf.alphaSyncBoth
    if sync == nil then
        sync = conf.alphaSync
    end
    if sync then
        aOut = aIn
    end

    local inCombat = _G.MSUF_InCombat
    if inCombat == nil then
        inCombat = (InCombatLockdown and InCombatLockdown()) or false
    end

    local a = inCombat and aIn or aOut
    if a < 0 then
        a = 0
    elseif a > 1 then
        a = 1
    end
    return a
end


-- Unit Alpha: optional layered mode (keep text/portrait visible; apply alpha only to background or foreground).
local function MSUF_Alpha_SetTextureAlpha(tex, a)
    if tex and tex.SetAlpha and type(a) == "number" then
        if a < 0 then a = 0 elseif a > 1 then a = 1 end
        tex:SetAlpha(a)
    end
end

local function MSUF_Alpha_SetStatusTextureAlpha(sb, a)
    if not sb or not sb.GetStatusBarTexture then return end
    local t = sb:GetStatusBarTexture()
    MSUF_Alpha_SetTextureAlpha(t, a)
end

local function MSUF_Alpha_SetGradientAlphaArray(grads, a)
    if not grads or type(grads) ~= "table" then return end
    for i = 1, #grads do
        MSUF_Alpha_SetTextureAlpha(grads[i], a)
    end
end

local function MSUF_Alpha_SetTextAlpha(fs, a)
    if fs and fs.SetAlpha then
        MSUF_Alpha_SetTextureAlpha(fs, a)
    end
end

local function MSUF_Alpha_ResetLayered(frame)
    if not frame or not frame._msufAlphaLayeredMode then
        return
    end

    -- Restore normal unit alpha and clear any per-layer overrides
    local unitAlpha = frame._msufAlphaUnitAlpha or 1
    frame._msufAlphaLayeredMode = nil
    frame._msufAlphaLayerMode = nil
    frame._msufAlphaUnitAlpha = nil

    if frame.SetAlpha then
        frame:SetAlpha(unitAlpha)
    end

    -- Reset: show everything at full opacity (relative to frame alpha)
    local one = 1

    MSUF_Alpha_SetStatusTextureAlpha(frame.hpBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.targetPowerBar or frame.powerBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.absorbBar, one)
    MSUF_Alpha_SetStatusTextureAlpha(frame.healAbsorbBar, one)

    MSUF_Alpha_SetTextureAlpha(frame.hpBarBG, one)
    MSUF_Alpha_SetTextureAlpha(frame.powerBarBG, one)
    MSUF_Alpha_SetTextureAlpha(frame.bg, one)

    MSUF_Alpha_SetGradientAlphaArray(frame.hpGradients, one)
    MSUF_Alpha_SetGradientAlphaArray(frame.powerGradients, one)

    MSUF_Alpha_SetTextureAlpha(frame.portrait, one)
    MSUF_Alpha_SetTextAlpha(frame.nameText, one)
    MSUF_Alpha_SetTextAlpha(frame.hpText, one)
    MSUF_Alpha_SetTextAlpha(frame.powerText, one)
end

local function MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, mode)
    if not frame then return end
    -- Accept compact numeric/bool encoding (survives aggressive DB sanitizers).
    --   background: true / 1 / "background"
    --   foreground: false / 0 / "foreground" (default)
    if mode == true or mode == 1 or mode == "background" then
        mode = "background"
    else
        mode = "foreground"
    end

    -- Keep overall frame alpha at 1, then drive background/foreground via their own alphas.
    frame._msufAlphaLayeredMode = true
    frame._msufAlphaLayerMode = mode
    frame._msufAlphaUnitAlphaFG = alphaFG
    frame._msufAlphaUnitAlphaBG = alphaBG

    if frame.SetAlpha then
        frame:SetAlpha(1)
    end

    local fg = type(alphaFG) == "number" and alphaFG or 1
    local bg = type(alphaBG) == "number" and alphaBG or 1
    if fg < 0 then fg = 0 elseif fg > 1 then fg = 1 end
    if bg < 0 then bg = 0 elseif bg > 1 then bg = 1 end

    -- Background elements
    MSUF_Alpha_SetTextureAlpha(frame.hpBarBG, bg)
    MSUF_Alpha_SetTextureAlpha(frame.powerBarBG, bg)
    MSUF_Alpha_SetTextureAlpha(frame.bg, bg)

    -- Foreground elements (bar fills + gradients)
    MSUF_Alpha_SetStatusTextureAlpha(frame.hpBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.targetPowerBar or frame.powerBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.absorbBar, fg)
    MSUF_Alpha_SetStatusTextureAlpha(frame.healAbsorbBar, fg)

    MSUF_Alpha_SetGradientAlphaArray(frame.hpGradients, fg)
    MSUF_Alpha_SetGradientAlphaArray(frame.powerGradients, fg)

    -- Keep text/portrait fully visible
    local one = 1
    MSUF_Alpha_SetTextureAlpha(frame.portrait, one)
    MSUF_Alpha_SetTextAlpha(frame.nameText, one)
    MSUF_Alpha_SetTextAlpha(frame.hpText, one)
    MSUF_Alpha_SetTextAlpha(frame.powerText, one)
end

function _G.MSUF_ApplyUnitAlpha(frame, key)
    if not frame or not frame.SetAlpha then
        return
    end

    EnsureDB()

    local unit = frame.unit or key

    -- Offline / Dead: keep legacy "dim whole frame" behavior, and reset layered state so it can't stick.
    if unit and UnitExists and UnitExists(unit) then
        if UnitIsConnected and (UnitIsConnected(unit) == false) then
            MSUF_Alpha_ResetLayered(frame)
            local a = 0.5
            if frame.GetAlpha then
                local cur = frame:GetAlpha() or 1
                if math.abs(cur - a) > 0.001 then frame:SetAlpha(a) end
            else
                frame:SetAlpha(a)
            end
            return
        end
        if UnitIsDead and UnitIsDead(unit) and (not (UnitIsGhost and UnitIsGhost(unit))) then
            MSUF_Alpha_ResetLayered(frame)
            local a = 0.5
            if frame.GetAlpha then
                local cur = frame:GetAlpha() or 1
                if math.abs(cur - a) > 0.001 then frame:SetAlpha(a) end
            else
                frame:SetAlpha(a)
            end
            return
        end
    end

    local conf = (key and MSUF_DB and MSUF_DB[key]) or nil
local layered = (conf and conf.alphaExcludeTextPortrait == true) or false
local layerMode = conf and conf.alphaLayerMode or nil

if layered and conf then
    local inCombat = _G.MSUF_InCombat
    if inCombat == nil then
        inCombat = (InCombatLockdown and InCombatLockdown()) or false
    end

    local aInLegacy  = tonumber(conf.alphaInCombat) or 1
    local aOutLegacy = tonumber(conf.alphaOutOfCombat) or 1

    local fgIn  = tonumber(conf.alphaFGInCombat) or aInLegacy
    local fgOut = tonumber(conf.alphaFGOutOfCombat) or aOutLegacy
    local bgIn  = tonumber(conf.alphaBGInCombat) or aInLegacy
    local bgOut = tonumber(conf.alphaBGOutOfCombat) or aOutLegacy

    -- Sync in/out per layer if enabled
    if conf.alphaSync == true then
        fgOut = fgIn
        bgOut = bgIn
    end

    local alphaFG = inCombat and fgIn or fgOut
    local alphaBG = inCombat and bgIn or bgOut

    MSUF_Alpha_ApplyLayered(frame, alphaFG, alphaBG, layerMode)
    return
end

local a = _G.MSUF_GetDesiredUnitAlpha and _G.MSUF_GetDesiredUnitAlpha(key) or 1
if type(a) ~= "number" then a = 1 end
if a < 0 then a = 0 elseif a > 1 then a = 1 end

    -- Legacy: alpha applies to whole unitframe (all children)
    if frame._msufAlphaLayeredMode then
        MSUF_Alpha_ResetLayered(frame)
    end
    if frame.GetAlpha then
        local cur = frame:GetAlpha() or 1
        if math.abs(cur - a) > 0.001 then
            frame:SetAlpha(a)
        end
    else
        frame:SetAlpha(a)
    end
end

function _G.MSUF_RefreshAllUnitAlphas()
    EnsureDB()
    local list = UnitFramesList
    if list and #list > 0 then
        for i = 1, #list do
            local f = list[i]
            if f then
                local unit = f.unit
                if unit then
                    local k = f.msufConfigKey or GetConfigKeyForUnit(unit)
                    local conf = (k and MSUF_DB and MSUF_DB[k]) or nil
                    if conf and conf.enabled == false then
                    else
                        local unitValid = (type(unit) == "string" and unit ~= "") and true or false
                        local exists = (unitValid and UnitExists and UnitExists(unit)) and true or false
                        if exists or unit == "player" or (f.isBoss and MSUF_BossTestMode) then
                            _G.MSUF_ApplyUnitAlpha(f, k)
                        else
                            if unit ~= "player" and f.SetAlpha and f.GetAlpha and (f:GetAlpha() or 0) > 0.01 then
                                f:SetAlpha(0)
                            end
                        end
                    end
                end
            end
        end
        return
    end
    local frames = _G.MSUF_UnitFrames or UnitFrames
    if not frames then
        return
    end
    for unitKey, f in pairs(frames) do
        if f then
            local unit = f.unit or unitKey
            if unit then
                local k = f.msufConfigKey or GetConfigKeyForUnit(unit)
                local conf = (k and MSUF_DB and MSUF_DB[k]) or nil
                if conf and conf.enabled == false then
                else
                    local exists = UnitExists(unit)
                    if exists or unit == "player" or (f.isBoss and MSUF_BossTestMode) then
                        _G.MSUF_ApplyUnitAlpha(f, k)
                    else
                        if unit ~= "player" and f.SetAlpha and f.GetAlpha and (f:GetAlpha() or 0) > 0.01 then
                            f:SetAlpha(0)
                        end
                    end
                end
            end
        end
    end
end
if not _G.MSUF_AlphaEventFrame then
    _G.MSUF_AlphaEventFrame = CreateFrame("Frame")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    _G.MSUF_AlphaEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    local function MSUF_DoAlphaRefresh()
        if _G.MSUF_RefreshAllUnitAlphas then
            _G.MSUF_RefreshAllUnitAlphas()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if _G.MSUF_RefreshAllUnitAlphas then
                        _G.MSUF_RefreshAllUnitAlphas()
                    end
                end)
            end
        end
    end
    _G.MSUF_AlphaEventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.MSUF_InCombat = true
        elseif event == "PLAYER_REGEN_ENABLED" then
            _G.MSUF_InCombat = false
        end
        MSUF_DoAlphaRefresh()
    end)
end
local function MSUF_InitPlayerCastbarPreviewToggle()
    if not MSUF_DB or not MSUF_DB.general then
        return
    end
    local playerGroup = _G["MSUF_CastbarPlayerGroup"]
    if not playerGroup then
        return
    end
    local castbarGroup = playerGroup:GetParent() or playerGroup
    local anchorParent = castbarGroup
    local function MSUF_GetLastCastbarSubTabButton()
        return _G["MSUF_CastbarBossButton"]
            or _G["MSUF_CastbarFocusButton"]
            or _G["MSUF_CastbarTargetButton"]
            or _G["MSUF_CastbarPlayerButton"]
            or _G["MSUF_CastbarEnemyButton"]
    end
    local oldCB = _G["MSUF_CastbarPlayerPreviewCheck"]
    if oldCB then
        oldCB:Hide()
        oldCB:SetScript("OnClick", nil)
        oldCB:SetScript("OnShow", nil)
    end
    local btn = _G["MSUF_CastbarEditModeButton"]
    if not btn then
        btn = CreateFrame("Button", "MSUF_CastbarEditModeButton", anchorParent, "UIPanelButtonTemplate")
        btn:SetSize(160, 21)
        local fs = btn:GetFontString()
        if fs then
            fs:SetFontObject("GameFontNormal")
        end
    end
    if btn and not btn.__msufMidnightActionSkinned then
        btn.__msufMidnightActionSkinned = true
        if btn.Left then btn.Left:SetAlpha(0) end
        if btn.Middle then btn.Middle:SetAlpha(0) end
        if btn.Right then btn.Right:SetAlpha(0) end
        local n = btn.GetNormalTexture and btn:GetNormalTexture()
        if n then n:SetAlpha(0) end
        local p = btn.GetPushedTexture and btn:GetPushedTexture()
        if p then p:SetAlpha(0) end
        local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if h then h:SetAlpha(0) end
        local d = btn.GetDisabledTexture and btn:GetDisabledTexture()
        if d then d:SetAlpha(0) end
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8x8")
        bg:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        bg:SetVertexColor(0.06, 0.06, 0.06, 0.92)
        btn.__msufBg = bg
        local bd = btn:CreateTexture(nil, "BORDER")
        bd:SetTexture("Interface\\Buttons\\WHITE8x8")
        bd:SetAllPoints(btn)
        bd:SetVertexColor(0, 0, 0, 0.85)
        btn.__msufBorder = bd
        local fs = btn.GetFontString and btn:GetFontString()
        if fs then
            fs:SetTextColor(1, 0.82, 0)
            fs:SetShadowColor(0, 0, 0, 0.9)
            fs:SetShadowOffset(1, -1)
        end
    end
    btn:ClearAllPoints()
    local lastTab = MSUF_GetLastCastbarSubTabButton()
    if lastTab then
        btn:SetParent(lastTab:GetParent() or anchorParent)
        btn:SetPoint("LEFT", lastTab, "RIGHT", 8, 0)
    else
        btn:SetPoint("TOPRIGHT", anchorParent, "TOPRIGHT", -175, -152)
    end
    local function UpdateButtonLabel()
        EnsureDB()
        local g       = MSUF_DB.general or {}
        local active  = g.castbarPlayerPreviewEnabled and true or false
        if active then
            btn:SetText("Castbar Edit Mode: ON")
        else
            btn:SetText("Castbar Edit Mode: OFF")
        end
    end
    btn:SetScript("OnClick", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local wasActive = g.castbarPlayerPreviewEnabled and true or false
        if wasActive then
            local bf = _G and _G.MSUF_BossCastbarPreview
            if bf and bf.GetWidth and bf.GetHeight then
                g.bossCastbarWidth  = math.floor((bf:GetWidth()  or (tonumber(g.bossCastbarWidth)  or 240)) + 0.5)
                g.bossCastbarHeight = math.floor((bf:GetHeight() or (tonumber(g.bossCastbarHeight) or 18)) + 0.5)
                bf.isDragging = false
                if bf.SetScript then
                    bf:SetScript("OnUpdate", nil)
                end
            end
            if type(MSUF_SyncBossCastbarSliders) == "function" then
                MSUF_SyncBossCastbarSliders()
            end
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                _G.MSUF_ApplyBossCastbarPositionSetting()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
        end
        g.castbarPlayerPreviewEnabled = not (g.castbarPlayerPreviewEnabled and true or false)
        if g.castbarPlayerPreviewEnabled then
            print("|cffffd700MSUF:|r Castbar Edit Mode |cff00ff00ON|r – drag player/target/focus castbars with the mouse.")
        else
            print("|cffffd700MSUF:|r Castbar Edit Mode |cffff0000OFF|r.")
        end
        if MSUF_UpdatePlayerCastbarPreview then
            MSUF_UpdatePlayerCastbarPreview()
        end
        if g.castbarPlayerPreviewEnabled then
            if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                _G.MSUF_ApplyBossCastbarPositionSetting()
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                _G.MSUF_UpdateBossCastbarPreview()
            end
            if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
                _G.MSUF_SetupBossCastbarPreviewEditMode()
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                        _G.MSUF_UpdateBossCastbarPreview()
                    end
                    if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
                        _G.MSUF_SetupBossCastbarPreviewEditMode()
                    end
                end)
            end
        end
        UpdateButtonLabel()
    end)
    btn:SetScript("OnShow", UpdateButtonLabel)
    UpdateButtonLabel()
    btn:Show()
end
local function KillFrame(frame, allowInEditMode)
    if not frame then return end
    if frame.UnregisterAllEvents then
        frame:UnregisterAllEvents()
    end
    frame:Hide()
    local isProtected = frame.IsProtected and frame:IsProtected()
    if isProtected then
        if RegisterStateDriver and not frame.MSUF_StateDriverHidden then
            if not (InCombatLockdown and InCombatLockdown()) then
                RegisterStateDriver(frame, "visibility", "hide")
                frame.MSUF_StateDriverHidden = true
            end
        end
    elseif frame.SetScript then
        frame:SetScript("OnShow", function(f)
            if allowInEditMode and MSUF_IsInEditMode and MSUF_IsInEditMode() then
                return
            end
            f:Hide()
        end)
    end
    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
end
-- Soft-disable Blizzard PlayerFrame visuals (compat mode).
-- Keeps PlayerFrame alive as an anchor parent for third-party resource bars,
-- while stripping Blizzard visuals so MSUF can fully replace the frame.
local function MSUF_HideRegions(frame)
    if not frame or not frame.GetRegions then return end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r then
            if r.SetAlpha then r:SetAlpha(0) end
            if r.Hide then r:Hide() end
        end
    end
end

local function MSUF_SoftHidePlayerFrame()
    if not PlayerFrame then return end

    -- Don't touch protected UI while in combat; retry once we're out.
    if InCombatLockdown and InCombatLockdown() then
        if not PlayerFrame.MSUF_SoftHideQueued and C_Timer and C_Timer.After then
            PlayerFrame.MSUF_SoftHideQueued = true
            C_Timer.After(0.25, function()
                if PlayerFrame then
                    PlayerFrame.MSUF_SoftHideQueued = nil
                end
                MSUF_SoftHidePlayerFrame()
            end)
        end
        return
    end

    -- Keep PlayerFrame alive as an anchor parent for third-party addons,
    -- but stop Blizzard logic + remove Blizzard visuals.
    if PlayerFrame.UnregisterAllEvents then
        PlayerFrame:UnregisterAllEvents()
    end
    if PlayerFrame.EnableMouse then
        PlayerFrame:EnableMouse(false)
    end

    if PlayerFrame.SetMouseClickEnabled then
        PlayerFrame:SetMouseClickEnabled(false)
    end
    if PlayerFrame.SetMouseMotionEnabled then
        PlayerFrame:SetMouseMotionEnabled(false)
    end
    -- Ensure the (now invisible) PlayerFrame cannot ever be a mouseover/click target.
    -- This keeps third-party bars parented to PlayerFrame working while removing the "ghost frame" feel.
    if PlayerFrame.SetHitRectInsets then
        PlayerFrame:SetHitRectInsets(10000, 10000, 10000, 10000)
    end
    local function KillVisual(f)
        if not f then return end
        if f.UnregisterAllEvents then f:UnregisterAllEvents() end
        if f.EnableMouse then f:EnableMouse(false) end
        if f.Hide then f:Hide() end
        if f.SetScript then
            f:SetScript("OnShow", function(x) x:Hide() end)
            f:SetScript("OnEnter", nil)
            f:SetScript("OnLeave", nil)
        end
        if f.SetAlpha then f:SetAlpha(0) end
    end

    -- Strip any regions on the root itself (safety).
    MSUF_HideRegions(PlayerFrame)

    -- 1) Kill the known Blizzard visual containers on the PlayerFrame.
    -- These are where Blizzard actually draws the default PlayerFrame.
    KillVisual(PlayerFrame.PlayerFrameContainer)
    KillVisual(PlayerFrame.PlayerFrameContent)

    -- Common alternative keys / globals (safe no-ops if nil).
    KillVisual(PlayerFrame.healthbar)
    KillVisual(PlayerFrame.manabar)
    KillVisual(PlayerFrame.powerBarAlt)
    KillVisual(PlayerFrame.alternateManaBar)
    KillVisual(PlayerFrame.totalAbsorbBar)
    KillVisual(PlayerFrame.tempMaxHealthLossBar)
    KillVisual(PlayerFrame.myHealPredictionBar)
    KillVisual(PlayerFrame.otherHealPredictionBar)
    KillVisual(PlayerFrame.name)
    KillVisual(PlayerFrame.portrait)

    KillVisual(_G and _G.PlayerFrameContainer)
    KillVisual(_G and _G.PlayerFrameContent)

    -- 2) Recursively strip Blizzard-owned children only (name starts with "PlayerFrame").
    -- This avoids nuking third-party resource bars parented to PlayerFrame.
    local function Recurse(parent)
        if not parent or not parent.GetChildren then return end
        local kids = { parent:GetChildren() }
        for i = 1, #kids do
            local child = kids[i]
            if child and child.GetName then
                local n = child:GetName()
                if n and string.sub(n, 1, 10) == "PlayerFrame" then
                    KillVisual(child)
                    MSUF_HideRegions(child)
                    Recurse(child)
                end
            end
        end
    end
    Recurse(PlayerFrame)

    -- Re-apply if Blizzard shows/rebuilds parts later (rare, not hotpath).
    if PlayerFrame.HookScript and not PlayerFrame.MSUF_SoftHiddenHooked then
        PlayerFrame.MSUF_SoftHiddenHooked = true
        PlayerFrame:HookScript("OnShow", function()
            MSUF_SoftHidePlayerFrame()
        end)
    end
end

-- Compat-Anchor mode (for third-party addons):
-- Keep Blizzard PlayerFrame fully alive + clickable, but make it invisible (alpha=0) and
-- anchor it tiny behind the MSUF player frame. This allows addons that hook/parent to
-- the Blizzard PlayerFrame to keep working, while MSUF remains the visible unitframe.
local function MSUF_GetMSUFPlayerFrame()
    if _G and _G.MSUF_player then return _G.MSUF_player end
    local list = _G and _G.MSUF_UnitFrames
    if list and list.player then return list.player end
    return nil
end

local MSUF_CompatAnchorEventFrame
local MSUF_CompatAnchorPending

local function MSUF_ApplyCompatAnchor_PlayerFrame()
    if not PlayerFrame then return end
    if not MSUF_DB or not MSUF_DB.general then return end
    local g = MSUF_DB.general
    if g.disableBlizzardUnitFrames == false then return end

    if g.hardKillBlizzardPlayerFrame == true then
        PlayerFrame.MSUF_CompatAnchorActive = nil
        return
    end

    PlayerFrame.MSUF_CompatAnchorActive = true

    -- Always invisible, but still clickable/interactive.
    if PlayerFrame.SetAlpha then PlayerFrame:SetAlpha(0) end
    if PlayerFrame.Show then PlayerFrame:Show() end

    -- Protected operations must not run in combat.
    if InCombatLockdown and InCombatLockdown() then
        MSUF_CompatAnchorPending = true
        if not MSUF_CompatAnchorEventFrame then
            MSUF_CompatAnchorEventFrame = CreateFrame("Frame")
            MSUF_CompatAnchorEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            MSUF_CompatAnchorEventFrame:SetScript("OnEvent", function()
                if MSUF_CompatAnchorPending then
                    MSUF_CompatAnchorPending = nil
                    MSUF_ApplyCompatAnchor_PlayerFrame()
                end
            end)
        end
        return
    end

    local anchor = MSUF_GetMSUFPlayerFrame()
    if anchor and PlayerFrame.ClearAllPoints and PlayerFrame.SetPoint then
        PlayerFrame:ClearAllPoints()
        PlayerFrame:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end

    -- Tiny + behind MSUF.
    if PlayerFrame.SetScale then PlayerFrame:SetScale(0.05) end
    if PlayerFrame.SetFrameStrata then PlayerFrame:SetFrameStrata("BACKGROUND") end
    if PlayerFrame.SetFrameLevel then PlayerFrame:SetFrameLevel(0) end

    -- Re-apply if Blizzard shows/repositions later.
    if PlayerFrame.HookScript and not PlayerFrame.MSUF_CompatAnchorHooked then
        PlayerFrame.MSUF_CompatAnchorHooked = true
        PlayerFrame:HookScript("OnShow", function()
            if not PlayerFrame or not PlayerFrame.MSUF_CompatAnchorActive then return end
            if PlayerFrame.SetAlpha then PlayerFrame:SetAlpha(0) end
            if InCombatLockdown and InCombatLockdown() then
                MSUF_CompatAnchorPending = true
                return
            end
            local a = MSUF_GetMSUFPlayerFrame()
            if a and PlayerFrame.ClearAllPoints and PlayerFrame.SetPoint then
                PlayerFrame:ClearAllPoints()
                PlayerFrame:SetPoint("CENTER", a, "CENTER", 0, 0)
            end
        end)
    end
end

_G.MSUF_ApplyCompatAnchor_PlayerFrame = MSUF_ApplyCompatAnchor_PlayerFrame


local function MSUF_KillBlizzardVisual(child)
    if not child then return end
    if child.UnregisterAllEvents then
        child:UnregisterAllEvents()
    end
    child:Hide()
    if child.EnableMouse then
        child:EnableMouse(false)
    end
    if child.SetScript then
        child:SetScript("OnShow", function(f) f:Hide() end)
        child:SetScript("OnEnter", nil)
        child:SetScript("OnLeave", nil)
    end
end

local function MSUF_HideBlizzardFrameVisuals(frame, prefix)
    if not frame then return end

    -- Hide known subframes/regions
    local fields = frame._msufHideVisualFields
    if not fields then
        fields = {
            "TargetFrameContainer",
            "TargetFrameContent",
            "healthbar",
            "manabar",
            "powerBarAlt",
            "overAbsorbGlow",
            "overHealAbsorbGlow",
            "totalAbsorbBar",
            "tempMaxHealthLossBar",
            "myHealPredictionBar",
            "otherHealPredictionBar",
            "name",
            "portrait",
            "threatIndicator",
            "threatNumericIndicator",
        }
        frame._msufHideVisualFields = fields
    end

    for i = 1, #fields do
        MSUF_KillBlizzardVisual(frame[fields[i]])
    end

    -- Hide aura buttons (classic style)
    if prefix then
        for i = 1, 40 do
            MSUF_KillBlizzardVisual(_G[prefix.."Buff"..i])
            MSUF_KillBlizzardVisual(_G[prefix.."Debuff"..i])
        end
    end

    -- Also hide any remaining direct children (runs once, not hotpath)
    if frame.GetChildren then
        local kids = { frame:GetChildren() }
        for i = 1, #kids do
            MSUF_KillBlizzardVisual(kids[i])
        end
    end

    -- Clear aura pools (prevents Blizzard auras building behind our UI)
    if frame.auraPools and frame.auraPools.ReleaseAll then
        frame.auraPools:ReleaseAll()
    end
    if not frame.MSUF_AurasHooked and frame.UpdateAuras then
        frame.MSUF_AurasHooked = true
        hooksecurefunc(frame, "UpdateAuras", function(f)
            if f ~= frame then return end
            if f.auraPools and f.auraPools.ReleaseAll then
                f.auraPools:ReleaseAll()
            end
        end)
    end

    if frame.EnableMouse then
        frame:EnableMouse(false)
    end
end

local function MSUF_HideBlizzardTargetVisuals()
    MSUF_HideBlizzardFrameVisuals(TargetFrame, "TargetFrame")
end

local function MSUF_HideBlizzardFocusVisuals()
    MSUF_HideBlizzardFrameVisuals(FocusFrame, "FocusFrame")
end
local function HideDefaultFrames()
    EnsureDB()
    local g = MSUF_DB.general or {}
    if g.disableBlizzardUnitFrames == false then
        return
    end
    if g.hardKillBlizzardPlayerFrame == true then
        KillFrame(PlayerFrame)
    else
        if type(_G.MSUF_ApplyCompatAnchor_PlayerFrame) == "function" then
            _G.MSUF_ApplyCompatAnchor_PlayerFrame()
        end
    end
    KillFrame(TargetFrameToT)
    KillFrame(PetFrame)
    KillFrame(TargetFrame)
    KillFrame(FocusFrame)
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local bossFrame = _G["Boss"..i.."TargetFrame"]
        KillFrame(bossFrame) -- kein allowInEditMode: immer tot, auch im Blizzard Edit Mode
    end
    if BossTargetFrameContainer then
        KillFrame(BossTargetFrameContainer)
        if BossTargetFrameContainer.Selection then
            local sel = BossTargetFrameContainer.Selection
            if sel.UnregisterAllEvents then
                sel:UnregisterAllEvents()
            end
            if sel.EnableMouse then
                sel:EnableMouse(false)
            end
            sel:Hide()
            if sel.SetScript then
                sel:SetScript("OnShow", function(f) f:Hide() end)
                sel:SetScript("OnEnter", nil)
                sel:SetScript("OnLeave", nil)
            end
        end
    end
    MSUF_HideBlizzardTargetVisuals()
    MSUF_HideBlizzardFocusVisuals()
end
local UnitFrames = {}
_G.MSUF_UnitFrames = UnitFrames
local function MSUF_GetVisibilityDriverForUnit(unit)
    if unit == "target" then
        return "[@target,exists] show; hide"
    elseif unit == "focus" then
        return "[@focus,exists] show; hide"
    elseif unit == "pet" then
        return "[@pet,exists] show; hide"
    elseif unit == "targettarget" then
        return "[@targettarget,exists] show; hide"
    elseif type(unit) == "string" and unit:match("^boss%d+$") then
        return ("[@" .. unit .. ",exists] show; hide")
    end
    return nil
end
local function MSUF_ApplyUnitVisibilityDriver(frame, forceShow)
    if not frame or not frame.unit then return end
    if frame.unit == "player" then return end
if type(EnsureDB) == "function" then
    EnsureDB()
end
local confKey
if frame.isBoss or (type(frame.unit) == "string" and frame.unit:match("^boss%d+$")) then
    confKey = "boss"
else
    confKey = frame.unit
end
local conf = (type(MSUF_DB) == "table" and confKey and MSUF_DB[confKey]) or nil
if conf and conf.enabled == false then
    local rsd2 = _G and _G.RegisterStateDriver
    local usd2 = _G and _G.UnregisterStateDriver
    if type(rsd2) == "function" and type(usd2) == "function" then
        usd2(frame, "visibility")
        rsd2(frame, "visibility", "hide")
    end
    -- IMPORTANT: use a sentinel so re-enabling outside Edit Mode forces the real driver to re-register.
    frame._msufVisibilityForced = "disabled"
    return
end
    local drv = frame._msufVisibilityDriver
    if not drv then
        drv = MSUF_GetVisibilityDriverForUnit(frame.unit)
        frame._msufVisibilityDriver = drv
    end
    if not drv then return end
    local rsd = _G and _G.RegisterStateDriver
    local usd = _G and _G.UnregisterStateDriver
    if type(rsd) ~= "function" or type(usd) ~= "function" then return end
    if not forceShow and frame.isBoss and MSUF_BossTestMode then
        forceShow = true
    end
    if frame._msufVisibilityForced == (forceShow and true or false) then
        return
    end
    frame._msufVisibilityForced = (forceShow and true or false)
    usd(frame, "visibility")
    if forceShow then
        rsd(frame, "visibility", "show")
    else
        rsd(frame, "visibility", drv)
    end
end
local function MSUF_RefreshAllUnitVisibilityDrivers(forceShow)
    if not UnitFrames then return end
    for _, f in pairs(UnitFrames) do
        MSUF_ApplyUnitVisibilityDriver(f, forceShow)
    end
end
_G.MSUF_RefreshAllUnitVisibilityDrivers = MSUF_RefreshAllUnitVisibilityDrivers
local MSUF_GridFrame
function ns.MSUF_RefreshAllFrames()
    if not UnitFrames then return end
    for _, f in pairs(UnitFrames) do
        if f and f.unit and f.hpBar then
            if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                _G.MSUF_RequestUnitframeUpdate(f, true, false, "RefreshAllFrames")
            elseif UpdateSimpleUnitFrame then
                UpdateSimpleUnitFrame(f)
            end
        end
    end
end


-- Unified, coalesced unitframe refresh entrypoint.
-- Prefer UFCore queue + optional layout request; fallback to legacy UpdateSimpleUnitFrame.
-- forceFull: request a full unitframe update (safe default for option toggles)
-- wantLayout: also request a UFCore layout pass (anchors/size/layout-driven visuals)
-- reason: optional debug string (no functional impact)
function _G.MSUF_RequestUnitframeUpdate(frame, forceFull, wantLayout, reason, urgentNow)
    if not frame then return end

    -- Step 3: Coalesce multiple calls (often bursty around target/focus changes) into a single
    -- next-frame flush per frame. This prevents redundant MarkDirty/UI work without changing behavior.
    -- urgentNow=true keeps legacy "do it now" semantics for rare callers that truly need synchronous apply.

    if urgentNow == true then
        if wantLayout and type(_G.MSUF_UFCore_RequestLayout) == "function" then
            _G.MSUF_UFCore_RequestLayout(frame, reason or "MSUF_RequestUnitframeUpdate", true)
        end
        local q = _G.MSUF_QueueUnitframeUpdate
        if type(q) == "function" then
            q(frame, forceFull and true or false)
            return
        end
        local upd = _G.UpdateSimpleUnitFrame
        if type(upd) == "function" then
            upd(frame)
        end
        return
    end

    -- Global coalescer state (file-scope via upvalues inside this function's chunk).
    local co = _G.__MSUF_UFREQ_CO
    if not co then
        co = {
            queued = false,
            frames = {},
            force = {},
            layout = {},
        }
        _G.__MSUF_UFREQ_CO = co
    end

    -- Merge request for this frame.
    co.frames[frame] = true
    if forceFull then
        co.force[frame] = true
    end
    if wantLayout then
        co.layout[frame] = true
    end

    if co.queued then
        return
    end
    co.queued = true

    local function Flush()
        co.queued = false

        -- Snapshot then clear tables (avoid re-entrancy edgecases).
        local frames = co.frames
        local force = co.force
        local layout = co.layout
        co.frames = {}
        co.force = {}
        co.layout = {}

        -- Apply coalesced work.
        for f in pairs(frames) do
            if f then
                if layout[f] and type(_G.MSUF_UFCore_RequestLayout) == "function" then
                    -- urgent=false: allow UFCore to merge layout passes as well.
                    _G.MSUF_UFCore_RequestLayout(f, reason or "MSUF_RequestUnitframeUpdate", false)
                end

                local q = _G.MSUF_QueueUnitframeUpdate
                if type(q) == "function" then
                    q(f, force[f] and true or false)
                else
                    local upd = _G.UpdateSimpleUnitFrame
                    if type(upd) == "function" then
                        upd(f)
                    end
                end
            end
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, Flush)
    else
        Flush()
    end
end
local function MSUF_GetUnitLabelForKey(key)
    if key == "player" then
        return "Player"
    elseif key == "target" then
        return "Target"
    elseif key == "targettarget" then
        return "Target of Target"
    elseif key == "focus" then
        return "Focus"
    elseif key == "pet" then
        return "Pet"
    elseif key == "boss" then
        return "Boss"
    else
        return key or "Unknown"
    end
end
_G.MSUF_GetUnitLabelForKey = MSUF_GetUnitLabelForKey
local MSUF_POPUP_LABEL_W = 88
local MSUF_POPUP_BOX_W   = 92
local MSUF_POPUP_BOX_H   = 20
local MSUF_PositionPopup
local MSUF_CastbarPositionPopup
local function MSUF_OpenOptionsToKey(tabKey)
-- Slash-menu-only routing (primary UI). Keep legacy Settings open code as a fallback
-- for edge cases where the Slash Menu file failed to load.
if _G and type(_G.MSUF_OpenPage) == "function" then
    local k = (type(tabKey) == "string") and tabKey:lower() or "home"
    if k == "castbar" then k = "opt_castbar" end
    _G.MSUF_OpenPage(k)
    return
end

    local panel = _G and _G.MSUF_OptionsPanel
    MSUF_SuppressGameMenuAfterOptionsClose = true
    if not MSUF_HookedSuppressGameMenu then
        MSUF_HookedSuppressGameMenu = true
        local function MSUF_SuppressGameMenuNow()
    if InCombatLockdown and InCombatLockdown() then return end
            if not MSUF_SuppressGameMenuAfterOptionsClose then return end
            MSUF_SuppressGameMenuAfterOptionsClose = false
            if GameMenuFrame then
                if HideUIPanel then HideUIPanel(GameMenuFrame) end
                if GameMenuFrame.Hide then GameMenuFrame:Hide() end
            end
        end
        local function HookHide(frame)
            if not frame or frame.MSUF_SuppressHooked then return end
            frame.MSUF_SuppressHooked = true
            frame:HookScript("OnHide", function()
                if not MSUF_SuppressGameMenuAfterOptionsClose then return end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, MSUF_SuppressGameMenuNow)
                else
                    MSUF_SuppressGameMenuNow()
                end
            end)
        end
        HookHide(_G and _G.InterfaceOptionsFrame)
        HookHide(_G and _G.SettingsPanel)
        local function RestoreEditModePanelNow()
            if not MSUF_RestoreBlizzardEditModePanelAfterOptionsClose then return end
            if InCombatLockdown and InCombatLockdown() then
                MSUF_RestoreBlizzardEditModePanelPending = true
                MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_RESTORE_EDITMODE_PANEL", function(event)
if not MSUF_RestoreBlizzardEditModePanelPending then return end
                        if InCombatLockdown and InCombatLockdown() then return end
                        MSUF_RestoreBlizzardEditModePanelPending = false
            if _G then
                _G.MSUF_SuppressBlizzEditToMSUF = nil
            end
                        RestoreEditModePanelNow()
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_RESTORE_EDITMODE_PANEL")
end)
                return
            end
            MSUF_RestoreBlizzardEditModePanelAfterOptionsClose = false
            MSUF_RestoreBlizzardEditModePanelPending = false
            local em = _G and _G.EditModeManagerFrame
            if em and em.Show then
                if ShowUIPanel and securecallfunction then
                    securecallfunction(ShowUIPanel, em)
                elseif ShowUIPanel then
                    ShowUIPanel(em)
                else
                    em:Show()
                end
            end
        end
        local function HookHideRestoreEditMode(frame)
            if not frame or frame.MSUF_EditModeRestoreHooked then return end
            frame.MSUF_EditModeRestoreHooked = true
            frame:HookScript("OnHide", function()
                if not MSUF_RestoreBlizzardEditModePanelAfterOptionsClose then return end
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, RestoreEditModePanelNow)
                else
                    RestoreEditModePanelNow()
                end
            end)
        end
        HookHideRestoreEditMode(_G and _G.InterfaceOptionsFrame)
        HookHideRestoreEditMode(_G and _G.SettingsPanel)
        if _G and _G.GameMenuFrame and not _G.GameMenuFrame.MSUF_SuppressHooked then
            _G.GameMenuFrame.MSUF_SuppressHooked = true
            _G.GameMenuFrame:HookScript("OnShow", function()
                if not MSUF_SuppressGameMenuAfterOptionsClose then return end
                MSUF_SuppressGameMenuAfterOptionsClose = false
                if HideUIPanel then HideUIPanel(_G.GameMenuFrame) end
                _G.GameMenuFrame:Hide()
            end)
        end
    end
    if GameMenuFrame and GameMenuFrame.IsShown and GameMenuFrame:IsShown() then
        if HideUIPanel then HideUIPanel(GameMenuFrame) end
        if GameMenuFrame.Hide then GameMenuFrame:Hide() end
    end
    if _G and _G.EditModeManagerFrame and _G.EditModeManagerFrame.IsShown and _G.EditModeManagerFrame:IsShown() then
        if InCombatLockdown and InCombatLockdown() then
            MSUF_RestoreBlizzardEditModePanelAfterOptionsClose = false
        else
        MSUF_RestoreBlizzardEditModePanelAfterOptionsClose = true
        _G.MSUF_SuppressBlizzEditToMSUF = true
        if HideUIPanel then HideUIPanel(_G.EditModeManagerFrame) end
        if _G.EditModeManagerFrame.Hide then _G.EditModeManagerFrame:Hide() end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if _G then _G.MSUF_SuppressBlizzEditToMSUF = nil end
            end)
        else
            if _G then _G.MSUF_SuppressBlizzEditToMSUF = nil end
        end
        end
    end
    if Settings and Settings.OpenToCategory and MSUF_SettingsCategory and MSUF_SettingsCategory.GetID then
        Settings.OpenToCategory(MSUF_SettingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
    if GameMenuFrame and GameMenuFrame.IsShown and GameMenuFrame:IsShown() then
        if HideUIPanel then HideUIPanel(GameMenuFrame) end
        if GameMenuFrame.Hide then GameMenuFrame:Hide() end
    end
    local function SelectTab()
        local p = _G and _G.MSUF_OptionsPanel
        if type(MSUF_GetTabButtonHelpers) == "function" and p then
            local _, setKey = MSUF_GetTabButtonHelpers(p)
            if type(setKey) == "function" then
                setKey(tabKey)
                if p.LoadFromDB then p:LoadFromDB() end
            end
        end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, SelectTab)
    else
        SelectTab()
    end
end
local function MSUF_OpenOptionsToUnitMenu(unitKey)
    if not unitKey then return end
    if _G and type(_G.MSUF_OpenPage) == "function" then
        local k = tostring(unitKey):lower()
        if k:match("^boss%d+$") then k = "boss" end
        _G.MSUF_OpenPage("uf_" .. k)
        return
    end
    MSUF_OpenOptionsToKey(unitKey)
end
_G.MSUF_OpenOptionsToUnitMenu = MSUF_OpenOptionsToUnitMenu
local function MSUF_OpenOptionsToCastbarMenu(unitKey)
    if not unitKey then return end
    if _G and type(_G.MSUF_OpenPage) == "function" then
        _G.MSUF_OpenPage("opt_castbar")
        local function SelectSub()
            local k = tostring(unitKey):lower()
            if k:match("^boss%d+$") then k = "boss" end
            if type(_G.MSUF_SetActiveCastbarSubPage) == "function" then
                _G.MSUF_SetActiveCastbarSubPage(k)
            elseif type(MSUF_SetActiveCastbarSubPage) == "function" then
                MSUF_SetActiveCastbarSubPage(k)
            end
            local p = _G and _G.MSUF_OptionsPanel
            if p and p.LoadFromDB then p:LoadFromDB() end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, SelectSub)
        else
            SelectSub()
        end
        return
    end
    MSUF_OpenOptionsToKey("castbar")
    local function SelectSub()
        if type(_G.MSUF_SetActiveCastbarSubPage) == "function" then
            _G.MSUF_SetActiveCastbarSubPage(unitKey)
        elseif type(MSUF_SetActiveCastbarSubPage) == "function" then
            MSUF_SetActiveCastbarSubPage(unitKey)
        end
        local p = _G and _G.MSUF_OptionsPanel
        if p and p.LoadFromDB then p:LoadFromDB() end
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, SelectSub)
    else
        SelectSub()
    end
end
_G.MSUF_OpenOptionsToCastbarMenu = MSUF_OpenOptionsToCastbarMenu
local function MSUF_OpenOptionsToBossCastbarMenu()
    MSUF_OpenOptionsToCastbarMenu("boss")
end
_G.MSUF_OpenOptionsToBossCastbarMenu = MSUF_OpenOptionsToBossCastbarMenu
function MSUF_UpdateCastbarVisuals()
    if type(MSUF_BumpCastbarStyleRevision) == "function" then MSUF_BumpCastbarStyleRevision() end
    EnsureDB()
    local g = MSUF_DB.general or {}
    local showIcon    = (g.castbarShowIcon ~= false)
    local showName    = (g.castbarShowSpellName ~= false)
    local fontSize    = tonumber(g.castbarSpellNameFontSize) or 0
    local iconOffsetX = tonumber(g.castbarIconOffsetX) or 0
    local iconOffsetY = tonumber(g.castbarIconOffsetY) or 0
    local fontPath    = MSUF_GetFontPath()
    local fontFlags   = MSUF_GetFontFlags()

    local fr, fg, fb = 1, 1, 1
    if type(MSUF_GetCastbarTextColor) == "function" then
        fr, fg, fb = MSUF_GetCastbarTextColor()
    elseif type(MSUF_GetConfiguredFontColor) == "function" then
        fr, fg, fb = MSUF_GetConfiguredFontColor()
    else
        local colorKey = (g.fontColor or "white"):lower()
        local colorDef = (MSUF_FONT_COLORS and (MSUF_FONT_COLORS[colorKey] or MSUF_FONT_COLORS.white)) or { 1, 1, 1 }
        fr, fg, fb = colorDef[1], colorDef[2], colorDef[3]
    end

    local useShadow = g.textBackdrop and true or false
    local baseSize = g.fontSize or 14
    local effectiveSize = (fontSize > 0) and fontSize or baseSize

    local function ApplyFontColor(fs, size)
        fs:SetFont(fontPath, size, fontFlags)
        fs:SetTextColor(fr, fg, fb, 1)
    end
    local function ApplyShadow(fs)
        if useShadow then
            fs:SetShadowColor(0, 0, 0, 1)
            fs:SetShadowOffset(1, -1)
        else
            fs:SetShadowOffset(0, 0)
        end
    end

    local function ApplyBlizzard(frame)
        if not frame then return end
        local icon = frame.Icon or frame.icon or (frame.IconFrame and frame.IconFrame.Icon)
        if icon then icon:SetShown(showIcon) end
        local text = frame.Text or frame.text
        if text then
            text:SetShown(showName)
            ApplyFontColor(text, effectiveSize)
            ApplyShadow(text)
        end
    end

    ApplyBlizzard(TargetFrameSpellBar)
    ApplyBlizzard(PetCastingBarFrame)

    local function ApplyMSUF(frame)
        if not frame or not frame.statusBar then return end

        local statusBar = frame.statusBar
        local icon      = frame.icon
        local width     = frame:GetWidth()  or statusBar:GetWidth()  or 250
        local height    = frame:GetHeight() or statusBar:GetHeight() or 18

        local cfg = MSUF_DB and MSUF_DB.general
        local unitKey, prefix
        if cfg then
            local gw = tonumber(cfg.castbarGlobalWidth)
            local gh = tonumber(cfg.castbarGlobalHeight)
            if gw and gw > 0 then width = gw; frame:SetWidth(width) end
            if gh and gh > 0 then height = gh; frame:SetHeight(gh) end
            unitKey = MSUF_GetCastbarUnitFromFrame(frame)
            prefix = unitKey and MSUF_GetCastbarPrefix(unitKey) or nil
            if prefix then
                local bw = tonumber(cfg[prefix .. "BarWidth"])
                local bh = tonumber(cfg[prefix .. "BarHeight"])
                if bw and bw > 0 then width = bw; frame:SetWidth(width) end
                if bh and bh > 0 then height = bh; frame:SetHeight(bh) end
            end
        end

        local showIconLocal = showIcon
        local iconOXLocal   = iconOffsetX
        local iconOYLocal   = iconOffsetY
        local iconSizeLocal = height
        local cfgR = cfg

        if cfgR then
            if prefix then
                local v = cfgR[prefix .. "ShowIcon"]
                if v ~= nil then showIconLocal = (v ~= false) end
                v = cfgR[prefix .. "IconOffsetX"]; if v ~= nil then iconOXLocal = tonumber(v) or 0 end
                v = cfgR[prefix .. "IconOffsetY"]; if v ~= nil then iconOYLocal = tonumber(v) or 0 end
                v = cfgR[prefix .. "IconSize"]
                if v ~= nil then
                    iconSizeLocal = tonumber(v) or iconSizeLocal
                else
                    local gv = tonumber(cfgR.castbarIconSize) or 0
                    if gv and gv > 0 then iconSizeLocal = gv end
                end
            else
                local gv = tonumber(cfgR.castbarIconSize) or 0
                if gv and gv > 0 then iconSizeLocal = gv end
            end
        end

        if iconSizeLocal < 6 then iconSizeLocal = 6 end
        if iconSizeLocal > 128 then iconSizeLocal = 128 end

        local isPlayerCastbar = (frame == MSUF_PlayerCastbar or frame == MSUF_PlayerCastbarPreview)
        local iconDetached = (iconOXLocal ~= 0)
        local backgroundBar = frame.backgroundBar

        if isPlayerCastbar and type(_G.MSUF_ApplyPlayerCastbarIconLayout) == "function" then
            _G.MSUF_ApplyPlayerCastbarIconLayout(frame, g, -1, 1)
            if backgroundBar and frame.statusBar then
                backgroundBar:ClearAllPoints()
                backgroundBar:SetAllPoints(frame.statusBar)
            end
        else
            if icon and statusBar and icon.GetParent and icon.SetParent then
                local desiredParent = iconDetached and statusBar or frame
                if icon:GetParent() ~= desiredParent then icon:SetParent(desiredParent) end
            end

            if icon then
                icon:SetShown(showIconLocal)
                icon:ClearAllPoints()
                icon:SetPoint("LEFT", frame, "LEFT", iconOXLocal, iconOYLocal)
                icon:SetSize(iconSizeLocal, iconSizeLocal)
                if icon.SetDrawLayer then icon:SetDrawLayer("OVERLAY", 7) end
            end

            statusBar:ClearAllPoints()
            if showIconLocal and icon and not iconDetached then
                statusBar:SetPoint("LEFT", frame, "LEFT", iconSizeLocal + 1, 0)
                statusBar:SetWidth(width - (iconSizeLocal + 1))
            else
                statusBar:SetPoint("LEFT", frame, "LEFT", 0, 0)
                statusBar:SetWidth(width)
            end
            statusBar:SetHeight(height - 2)

            if backgroundBar then
                backgroundBar:ClearAllPoints()
                backgroundBar:SetAllPoints(statusBar)
            end
        end

        local cfg2 = cfg or {}
        local showNameLocal = showName
        local effectiveSizeLocal = effectiveSize
        local textOX, textOY = 0, 0
        local timeSizeLocal = effectiveSizeLocal

        if prefix then
            local v = cfg2[prefix .. "ShowSpellName"]
            if v ~= nil then showNameLocal = (v ~= false) end
            textOX = tonumber(cfg2[prefix .. "TextOffsetX"]) or 0
            textOY = tonumber(cfg2[prefix .. "TextOffsetY"]) or 0

            local ov = tonumber(cfg2[prefix .. "SpellNameFontSize"]) or 0
            if ov and ov > 0 then effectiveSizeLocal = ov end

            local tov = tonumber(cfg2[prefix .. "TimeFontSize"]) or 0
            if tov and tov > 0 then
                timeSizeLocal = tov
            else
                timeSizeLocal = effectiveSizeLocal
            end
        end

        local text = frame.castText or frame.Text or frame.text
        if text then
            text:SetShown(showNameLocal)
            ApplyFontColor(text, effectiveSizeLocal)
            if text.SetPoint then
                text:ClearAllPoints()
                text:SetPoint("LEFT", statusBar, "LEFT", 2 + textOX, 0 + textOY)
            end
            ApplyShadow(text)
        end

        local tt = frame.timeText
        if tt and MSUF_IsCastTimeEnabled(frame) then
            ApplyFontColor(tt, timeSizeLocal or effectiveSize)
            ApplyShadow(tt)
        end
    end

    ApplyMSUF(MSUF_PlayerCastbar)
    ApplyMSUF(MSUF_TargetCastbar)
    ApplyMSUF(MSUF_FocusCastbar)
    ApplyMSUF(MSUF_PlayerCastbarPreview)
    ApplyMSUF(MSUF_TargetCastbarPreview)
    ApplyMSUF(MSUF_FocusCastbarPreview)

    -- Boss castbar preview (Castbar Edit Mode)
    if _G.MSUF_BossCastbarPreview then
        ApplyMSUF(_G.MSUF_BossCastbarPreview)
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" and not _G.MSUF_BossPreviewRefreshLock then
        _G.MSUF_BossPreviewRefreshLock = true
        _G.MSUF_UpdateBossCastbarPreview()
        if type(_G.MSUF_SetupBossCastbarPreviewEditMode) == "function" then
            _G.MSUF_SetupBossCastbarPreviewEditMode()
        end
        _G.MSUF_BossPreviewRefreshLock = false
    end

    local bossN = _G.MSUF_MAX_BOSS_FRAMES or 5
    for i = 1, bossN do
        local bf = _G["MSUF_boss" .. i .. "CastBar"]
        if bf then ApplyMSUF(bf) end
    end
end
local function MSUF_UpdateNameColor(frame)
    if not frame or not frame.nameText then return end
    EnsureDB()
    local g = MSUF_DB.general
    local r, gCol, b
    if g.nameClassColor and frame.unit and UnitIsPlayer(frame.unit) then
        local _, classToken = UnitClass(frame.unit)
        if classToken then
            r, gCol, b = MSUF_GetClassBarColor(classToken)
        end
    end
    if (not (r and gCol and b)) and g.npcNameRed and frame.unit and not UnitIsPlayer(frame.unit) then
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(frame.unit) then
            r, gCol, b = MSUF_GetNPCReactionColor("dead")
        else
            local reaction = UnitReaction and UnitReaction("player", frame.unit)
            if reaction then
                if reaction >= 5 then
                    r, gCol, b = MSUF_GetNPCReactionColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = MSUF_GetNPCReactionColor("neutral")
                else
                    r, gCol, b = MSUF_GetNPCReactionColor("enemy")
                end
            end
        end
    end
    if not (r and gCol and b) then
        r, gCol, b = MSUF_GetConfiguredFontColor()
    end
    frame.nameText:SetTextColor(r or 1, gCol or 1, b or 1, 1)
    if frame.levelText then
        frame.levelText:SetTextColor(r or 1, gCol or 1, b or 1, 1)
    end
end


-- Public helpers for option toggles (keep logic single-owner, avoid blink/fighting)
_G.MSUF_RefreshAllIdentityColors = function()
    if type(_G.MSUF_DB) ~= "table" then return end
    local list = UnitFramesList
    if not list or #list == 0 then return end
    for i = 1, #list do
        local f = list[i]
        if f and f.nameText and f.unit and UnitExists and UnitExists(f.unit) then
            MSUF_UpdateNameColor(f)
        end
    end
end

_G.MSUF_RefreshAllPowerTextColors = function()
    if type(_G.MSUF_DB) ~= "table" then return end
    local g = (_G.MSUF_DB and _G.MSUF_DB.general) or nil
    local enabled = (g and g.colorPowerTextByType == true)
    local list = UnitFramesList
    if not list or #list == 0 then return end
    for i = 1, #list do
        local f = list[i]
        if f and f.powerText and f.unit and UnitExists and UnitExists(f.unit) then
            if enabled and type(_G.MSUF_UFCore_UpdatePowerTextFast) == "function" then
                -- Re-run fast-path once; it will apply the correct power color and sync the cache stamp.
                _G.MSUF_UFCore_UpdatePowerTextFast(f)
            else
                -- When disabled, fall back to configured font color immediately.
                local fr, fg, fb = 1, 1, 1
                if type(MSUF_GetConfiguredFontColor) == "function" then
                    fr, fg, fb = MSUF_GetConfiguredFontColor()
                end
                if f.powerText.SetTextColor then
                    f.powerText:SetTextColor(fr, fg, fb, 1)
                    f.powerText._msufColorStamp = tostring(fr) .. "|" .. tostring(fg) .. "|" .. tostring(fb)
                end
                f._msufPTColorByPower = nil
                f._msufPTColorType = nil
                f._msufPTColorTok = nil
            end
        end
    end
end

local function MSUF_HideTex(t) if t then t:Hide() end end
local _MSUF_GRAD_HIDE_KEYS = { "left", "right", "up", "down", "left2", "right2", "up2", "down2" }
local function MSUF_HideGradSet(grads, startIdx)
    if not grads then return end
    for i = startIdx or 1, 8 do
        local t = grads[_MSUF_GRAD_HIDE_KEYS[i]]
        if t then t:Hide() end
    end
end
local function MSUF_SetGrad(tex, orientation, a1, a2, strength)
    if not tex then return end
    if tex.SetGradientAlpha then
        tex:SetGradientAlpha(orientation, 0, 0, 0, a1, 0, 0, 0, a2)
    elseif tex.SetGradient then
        tex:SetGradient(orientation, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2))
    else
        tex:SetColorTexture(0, 0, 0, (a1 > a2) and a1 or a2)
    end
    if strength > 0 then tex:Show() else tex:Hide() end
end
local function MSUF_ApplyHPGradient(frameOrTex)
    if not frameOrTex then return end
    EnsureDB()
    local g = MSUF_DB.general or {}
    local strength = g.gradientStrength or 0.45
    if g.enableGradient == false then
        strength = 0
    end
    if frameOrTex.SetGradientAlpha and (not frameOrTex.hpGradients) then
        local tex = frameOrTex
        local dir = g.gradientDirection
        if type(dir) ~= "string" or dir == "" then
            dir = "RIGHT"
            g.gradientDirection = dir
        end
        local orientation = "HORIZONTAL"
        local a1, a2 = 0, strength
        if dir == "LEFT" then
            orientation = "HORIZONTAL"; a1, a2 = strength, 0
        elseif dir == "RIGHT" then
            orientation = "HORIZONTAL"; a1, a2 = 0, strength
        elseif dir == "UP" then
            orientation = "VERTICAL"; a1, a2 = strength, 0
        elseif dir == "DOWN" then
            orientation = "VERTICAL"; a1, a2 = 0, strength
        else
            orientation = "HORIZONTAL"; a1, a2 = 0, strength
            g.gradientDirection = "RIGHT"
        end
        MSUF_SetGrad(tex, orientation, a1, a2, strength)
        return
    end

    local frame = frameOrTex
    local hpBar = frame.hpBar
    local grads = frame.hpGradients
    if not hpBar or not grads then return end

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

    local left  = (g.gradientDirLeft == true)
    local right = (g.gradientDirRight == true)
    local up    = (g.gradientDirUp == true)
    local down  = (g.gradientDirDown == true)
    if (not left) and (not right) and (not up) and (not down) then
        right = true
        g.gradientDirRight = true
    end

    if strength <= 0 then
        MSUF_HideGradSet(grads)
        return
    end

    if left and right then
        if grads.left then
            grads.left:ClearAllPoints()
            grads.left:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 0, 0)
            grads.left:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOM", 0, 0) -- bottom-center
            MSUF_SetGrad(grads.left, "HORIZONTAL", strength, 0, strength)
        end
        if grads.right then
            grads.right:ClearAllPoints()
            grads.right:SetPoint("TOPLEFT", hpBar, "TOP", 0, 0) -- top-center
            grads.right:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            MSUF_SetGrad(grads.right, "HORIZONTAL", 0, strength, strength)
        end
    elseif left then
        if grads.left then
            grads.left:ClearAllPoints()
            grads.left:SetAllPoints(hpBar)
            MSUF_SetGrad(grads.left, "HORIZONTAL", strength, 0, strength)
        end
        MSUF_HideTex(grads.right)
    elseif right then
        if grads.right then
            grads.right:ClearAllPoints()
            grads.right:SetAllPoints(hpBar)
            MSUF_SetGrad(grads.right, "HORIZONTAL", 0, strength, strength)
        end
        MSUF_HideTex(grads.left)
    else
        MSUF_HideTex(grads.left)
        MSUF_HideTex(grads.right)
    end

    if up and down then
        if grads.up then
            grads.up:ClearAllPoints()
            grads.up:SetPoint("TOPLEFT", hpBar, "TOPLEFT", 0, 0)
            grads.up:SetPoint("BOTTOMRIGHT", hpBar, "RIGHT", 0, 0) -- center-right
            MSUF_SetGrad(grads.up, "VERTICAL", strength, 0, strength)
        end
        if grads.down then
            grads.down:ClearAllPoints()
            grads.down:SetPoint("TOPLEFT", hpBar, "LEFT", 0, 0) -- center-left
            grads.down:SetPoint("BOTTOMRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
            MSUF_SetGrad(grads.down, "VERTICAL", 0, strength, strength)
        end
    elseif up then
        if grads.up then
            grads.up:ClearAllPoints()
            grads.up:SetAllPoints(hpBar)
            MSUF_SetGrad(grads.up, "VERTICAL", strength, 0, strength)
        end
        MSUF_HideTex(grads.down)
    elseif down then
        if grads.down then
            grads.down:ClearAllPoints()
            grads.down:SetAllPoints(hpBar)
            MSUF_SetGrad(grads.down, "VERTICAL", 0, strength, strength)
        end
        MSUF_HideTex(grads.up)
    else
        MSUF_HideTex(grads.up)
        MSUF_HideTex(grads.down)
    end

    MSUF_HideGradSet(grads, 5)
end


local function MSUF_ApplyPowerGradient(frameOrTex)
    if not frameOrTex then return end
    EnsureDB()
    local g = MSUF_DB.general or {}
    local strength = g.gradientStrength or 0.45
    if g.enablePowerGradient == false then
        strength = 0
    end

    -- Allow calling with a single texture (legacy-style) just like HP.
    if frameOrTex.SetGradientAlpha and (not frameOrTex.powerGradients) then
        local tex = frameOrTex
        local dir = g.gradientDirection
        if type(dir) ~= "string" or dir == "" then
            dir = "RIGHT"
            g.gradientDirection = dir
        end
        local orientation = "HORIZONTAL"
        local a1, a2 = 0, strength
        if dir == "LEFT" then
            orientation = "HORIZONTAL"; a1, a2 = strength, 0
        elseif dir == "RIGHT" then
            orientation = "HORIZONTAL"; a1, a2 = 0, strength
        elseif dir == "UP" then
            orientation = "VERTICAL"; a1, a2 = strength, 0
        elseif dir == "DOWN" then
            orientation = "VERTICAL"; a1, a2 = 0, strength
        else
            orientation = "HORIZONTAL"; a1, a2 = 0, strength
            g.gradientDirection = "RIGHT"
        end
        MSUF_SetGrad(tex, orientation, a1, a2, strength)
        return
    end

    local frame = frameOrTex
    local pbBar = frame.targetPowerBar or frame.powerBar
    local grads = frame.powerGradients
    if not pbBar or not grads then return end

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

    local left  = (g.gradientDirLeft == true)
    local right = (g.gradientDirRight == true)
    local up    = (g.gradientDirUp == true)
    local down  = (g.gradientDirDown == true)
    if (not left) and (not right) and (not up) and (not down) then
        right = true
        g.gradientDirRight = true
    end

    if strength <= 0 then
        MSUF_HideGradSet(grads)
        return
    end

    if left and right then
        if grads.left then
            grads.left:ClearAllPoints()
            grads.left:SetPoint("TOPLEFT", pbBar, "TOPLEFT", 0, 0)
            grads.left:SetPoint("BOTTOMRIGHT", pbBar, "BOTTOM", 0, 0)
            MSUF_SetGrad(grads.left, "HORIZONTAL", strength, 0, strength)
        end
        if grads.right then
            grads.right:ClearAllPoints()
            grads.right:SetPoint("TOPLEFT", pbBar, "TOP", 0, 0)
            grads.right:SetPoint("BOTTOMRIGHT", pbBar, "BOTTOMRIGHT", 0, 0)
            MSUF_SetGrad(grads.right, "HORIZONTAL", 0, strength, strength)
        end
    elseif left then
        if grads.left then
            grads.left:ClearAllPoints()
            grads.left:SetAllPoints(pbBar)
            MSUF_SetGrad(grads.left, "HORIZONTAL", strength, 0, strength)
        end
        MSUF_HideTex(grads.right)
    elseif right then
        if grads.right then
            grads.right:ClearAllPoints()
            grads.right:SetAllPoints(pbBar)
            MSUF_SetGrad(grads.right, "HORIZONTAL", 0, strength, strength)
        end
        MSUF_HideTex(grads.left)
    else
        MSUF_HideTex(grads.left)
        MSUF_HideTex(grads.right)
    end

    if up and down then
        if grads.up then
            grads.up:ClearAllPoints()
            grads.up:SetPoint("TOPLEFT", pbBar, "TOPLEFT", 0, 0)
            grads.up:SetPoint("BOTTOMRIGHT", pbBar, "RIGHT", 0, 0)
            MSUF_SetGrad(grads.up, "VERTICAL", strength, 0, strength)
        end
        if grads.down then
            grads.down:ClearAllPoints()
            grads.down:SetPoint("TOPLEFT", pbBar, "LEFT", 0, 0)
            grads.down:SetPoint("BOTTOMRIGHT", pbBar, "BOTTOMRIGHT", 0, 0)
            MSUF_SetGrad(grads.down, "VERTICAL", 0, strength, strength)
        end
    elseif up then
        if grads.up then
            grads.up:ClearAllPoints()
            grads.up:SetAllPoints(pbBar)
            MSUF_SetGrad(grads.up, "VERTICAL", strength, 0, strength)
        end
        MSUF_HideTex(grads.down)
    elseif down then
        if grads.down then
            grads.down:ClearAllPoints()
            grads.down:SetAllPoints(pbBar)
            MSUF_SetGrad(grads.down, "VERTICAL", 0, strength, strength)
        end
        MSUF_HideTex(grads.up)
    else
        MSUF_HideTex(grads.up)
        MSUF_HideTex(grads.down)
    end

    MSUF_HideGradSet(grads, 5)
end


-- Power bar separator line (uses the existing "power bar border" toggle + thickness).
-- Instead of drawing a full frame border around the powerbar, we draw a clean overlay line
-- between HP and Power by anchoring to the TOP edge of the powerbar.
function _G.MSUF_ApplyPowerBarBorder(bar)
    if not bar then return end
    local bdb = (MSUF_DB and MSUF_DB.bars) or nil
    local enabled = bdb and (bdb.powerBarBorderEnabled == true) or false
    local size = bdb and tonumber(bdb.powerBarBorderSize) or 1
    if type(size) ~= 'number' then size = 1 end
    if size < 1 then size = 1 elseif size > 10 then size = 10 end

    local border = bar._msufPowerBorder
    if not border then
        -- Keep using the historical storage key to avoid any external assumptions.
        border = CreateFrame('Frame', nil, bar)
        border:SetFrameLevel((bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 2)
        border:EnableMouse(false)
        bar._msufPowerBorder = border
    end

    if not enabled then
        if border.Hide then border:Hide() end
        return
    end

    -- If an older build used Backdrop borders, clear them so only the separator line remains.
    if border.SetBackdrop then
        border:SetBackdrop(nil)
    end

    border:ClearAllPoints()
    border:SetPoint('TOPLEFT', bar, 'TOPLEFT', 0, 0)
    border:SetPoint('TOPRIGHT', bar, 'TOPRIGHT', 0, 0)
    border:SetHeight(size)

    local line = border._msufSeparatorLine
    if not line and border.CreateTexture then
        line = border:CreateTexture(nil, 'OVERLAY')
        line:SetTexture('Interface\\Buttons\\WHITE8x8')
        line:SetVertexColor(0, 0, 0, 1)
        line:SetAllPoints(border)
        border._msufSeparatorLine = line
    elseif line and line.SetAllPoints then
        line:SetAllPoints(border)
    end

    border:Show()
end

function _G.MSUF_ApplyPowerBarBorder_All()
    local frames = _G.MSUF_UnitFrames
    if type(frames) ~= 'table' then return end
    for _, f in pairs(frames) do
        local bar = f and (f.targetPowerBar or f.powerBar)
        if bar then
            _G.MSUF_ApplyPowerBarBorder(bar)
        end
    end
end
local function MSUF_PreCreateHPGradients(hpBar)
    if not hpBar or not hpBar.CreateTexture then return nil end
    local function MakeTex()
        local t = hpBar:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetBlendMode("BLEND")
        t:Hide()
        return t
    end
    return {
        left  = MakeTex(),
        right = MakeTex(),
        up    = MakeTex(),
        down  = MakeTex(),
    }
end
local function MSUF_UpdateAbsorbBar(self, unit, maxHP)
    if not self or not self.absorbBar or not UnitGetTotalAbsorbs then
        return
    end
    if type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
        _G.MSUF_ApplyAbsorbAnchorMode(self)
    end
    EnsureDB()
    MSUF_ApplyAbsorbOverlayColor(self.absorbBar)
    -- Options preview: force-show fake absorb overlay so users can preview absorb textures.
    if _G.MSUF_AbsorbTextureTestMode then
        local max = maxHP or (unit and UnitHealthMax(unit)) or 1
        -- Secret-safe: UnitHealthMax/preview max can be a secret value on Midnight/Beta.
        -- Only do numeric comparisons/arithmetic when the value is a real number.
        if type(max) ~= "number" or max < 1 then max = 1 end
        self.absorbBar:SetMinMaxValues(0, max)
        MSUF_SetBarValue(self.absorbBar, max * 0.25)
        self.absorbBar:Show()
        return
    end

    local g = MSUF_DB.general or {}
    if g.enableAbsorbBar == false then
        MSUF_ResetBarZero(self.absorbBar, true)
        return
    end
    local totalAbs = UnitGetTotalAbsorbs(unit)
    -- Secret-safe: totalAbs/max can be secret values; never compare/arithmetic unless they're real numbers.
    if type(totalAbs) ~= "number" then
        MSUF_ResetBarZero(self.absorbBar, true)
        return
    end
    local max = maxHP or UnitHealthMax(unit) or 1
    if type(max) ~= "number" or max < 1 then max = 1 end
    self.absorbBar:SetMinMaxValues(0, max)
    MSUF_SetBarValue(self.absorbBar, totalAbs)
    self.absorbBar:Show()
end
local function MSUF_UpdateHealAbsorbBar(self, unit, maxHP)
    if not self or not self.healAbsorbBar or not UnitGetTotalHealAbsorbs then
        return
    end
    if type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
        _G.MSUF_ApplyAbsorbAnchorMode(self)
    end
    MSUF_ApplyHealAbsorbOverlayColor(self.healAbsorbBar)
    -- Options preview: force-show fake heal-absorb overlay so users can preview heal-absorb textures.
    if _G.MSUF_AbsorbTextureTestMode then
        local max = maxHP or (unit and UnitHealthMax(unit)) or 1
        -- Secret-safe: UnitHealthMax/preview max can be a secret value on Midnight/Beta.
        if type(max) ~= "number" or max < 1 then max = 1 end
        self.healAbsorbBar:SetMinMaxValues(0, max)
        MSUF_SetBarValue(self.healAbsorbBar, max * 0.15)
        self.healAbsorbBar:Show()
        return
    end

    local totalHealAbs = UnitGetTotalHealAbsorbs(unit)
    if type(totalHealAbs) ~= "number" then
        MSUF_ResetBarZero(self.healAbsorbBar, true)
        return
    end
    local max = maxHP or UnitHealthMax(unit) or 1
    if type(max) ~= "number" or max < 1 then max = 1 end
    self.healAbsorbBar:SetMinMaxValues(0, max)
    MSUF_SetBarValue(self.healAbsorbBar, totalHealAbs)
    self.healAbsorbBar:Show()
end

-- Absorb overlay anchoring (positive absorb vs heal-absorb side)
-- Secret-safe: pure layout change via StatusBar:SetReverseFill.
local function MSUF_ApplyAbsorbAnchorMode(self)
    if not self then return end
    EnsureDB()
    local g = MSUF_DB and MSUF_DB.general or {}
    local mode = g.absorbAnchorMode or 2
    if self._msufAbsorbAnchorModeStamp == mode then
        return
    end
    self._msufAbsorbAnchorModeStamp = mode

    -- mode 1: Left Absorb / Right Heal-Absorb
    -- mode 2: Right Absorb / Left Heal-Absorb (default)
    local absorbReverse = (mode ~= 1)
    local healReverse   = not absorbReverse

    if self.absorbBar and self.absorbBar.SetReverseFill then
        self.absorbBar:SetReverseFill(absorbReverse and true or false)
    end
    if self.healAbsorbBar and self.healAbsorbBar.SetReverseFill then
        self.healAbsorbBar:SetReverseFill(healReverse and true or false)
    end
end
_G.MSUF_ApplyAbsorbAnchorMode = MSUF_ApplyAbsorbAnchorMode

local function PositionUnitFrame(f, unit)
    if not f or not unit then return end
    -- While dragging in MSUF Edit Mode, do not let background refreshes fight the cursor.
    if f._msufDragActive then return end
    local key = f.msufConfigKey
    if not key then
        key = GetConfigKeyForUnit(unit)
        f.msufConfigKey = key
    end
    if not key then return end
    if InCombatLockdown() then
        return
    end
    local conf = f.cachedConfig
    if not conf then
        EnsureDB()
        conf = MSUF_DB and MSUF_DB[key]
        f.cachedConfig = conf
    end
    if not conf then return end
    local anchor = MSUF_GetAnchorFrame()
    local ecv = _G["EssentialCooldownViewer"]
    if MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown and ecv and anchor == ecv then
        local rule = MSUF_ECV_ANCHORS[key]
        if rule then
            local point, relPoint, baseX, extraY = rule[1], rule[2], rule[3], rule[4]
            local gapY = (conf.offsetY ~= nil) and conf.offsetY or -20
            local x = baseX + (conf.offsetX or 0)
            local y = gapY + (extraY or 0)
            MSUF_ApplyPoint(f, point, ecv, relPoint, x, y)
            return
        end
    end
    if key == "boss" then
        local index = tonumber(unit:match("^boss(%d+)$")) or 1
        local x = conf.offsetX
        local spacing = conf.spacing or -36
        local y = conf.offsetY + (index - 1) * spacing
        MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", x, y)
    else
        MSUF_ApplyPoint(f, "CENTER", anchor, "CENTER", conf.offsetX, conf.offsetY)
    end
end

local function MSUF_GetApproxPercentTextWidth(templateFS)
    if not templateFS or not templateFS.GetFont then
        return 0
    end

    local font, size, flags = templateFS:GetFont()
    local fontKey = tostring(font or "") .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_PctWidthCache = _G.MSUF_PctWidthCache or {}
    local cache = _G.MSUF_PctWidthCache
    local cached = cache[fontKey]
    if cached then
        return cached
    end

    local fs = _G.MSUF_PctMeasureFS
    if not fs then
        local holder = CreateFrame("Frame", "MSUF_PctMeasureFrame", UIParent)
        holder:Hide()
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs:Hide()
        _G.MSUF_PctMeasureFS = fs
    end

    fs:SetFont(font, size, flags)
    fs:SetText("100.0%")
    local w = 0
    if fs.GetStringWidth then
        w = fs:GetStringWidth() or 0
    end
    w = tonumber(w) or 0
    if w < 0 then w = 0 end
    -- Add a tiny safety margin so we never clip due to rounding.
    w = math.ceil(w + 2)
    cache[fontKey] = w
    return w
end

-- Approximate width for a "full HP" value text (secret-safe).
-- We measure with our own hidden FontString so we never mutate the live hpText.
local function MSUF_GetApproxHpFullTextWidth(templateFS)
    if not templateFS or not templateFS.GetFont then
        return 0
    end

    local font, size, flags = templateFS:GetFont()
    local fontKey = tostring(font or "") .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_HPFullWidthCache = _G.MSUF_HPFullWidthCache or {}
    local cache = _G.MSUF_HPFullWidthCache
    local cached = cache[fontKey]
    if cached then
        return cached
    end

    local fs = _G.MSUF_HPFullMeasureFS
    if not fs then
        local holder = CreateFrame("Frame", "MSUF_HPFullMeasureFrame", UIParent)
        holder:Hide()
        fs = holder:CreateFontString(nil, "OVERLAY")
        fs:Hide()
        _G.MSUF_HPFullMeasureFS = fs
    end

    fs:SetFont(font, size, flags)
    -- Keep this representative but worst-case-ish for our compact HP formatting.
    -- (We avoid any secret arithmetic/string ops by using a constant.)
    fs:SetText("999.9M")

    local w = 0
    if fs.GetStringWidth then
        w = fs:GetStringWidth() or 0
    end
    w = tonumber(w) or 0
    if w < 0 then w = 0 end
    -- Tiny safety margin so we never clip due to rounding.
    w = math.ceil(w + 2)

    cache[fontKey] = w
    return w
end

-- Compute the maximum safe HP spacer value for a given config key.
-- Used by the Bars menu to clamp the slider per unitframe width.
local MSUF_HP_SPACER_SCALE = 1.15
local MSUF_HP_SPACER_MAXCAP = 2000

function _G.MSUF_GetHPSpacerMaxForUnitKey(unitKey)
    EnsureDB()
    local k = unitKey
    if not k or k == "" then
        k = (MSUF_DB.general and MSUF_DB.general.hpSpacerSelectedUnitKey) or "player"
    end
    if k == "tot" then k = "targettarget" end
    if type(k) == "string" and k:match("^boss%d+$") then k = "boss" end
    if k ~= "player" and k ~= "target" and k ~= "focus" and k ~= "targettarget" and k ~= "pet" and k ~= "boss" then
        k = "player"
    end

    local frameName
    if k == "boss" then
        frameName = "MSUF_boss1"
    else
        frameName = "MSUF_" .. k
    end
    local f = _G[frameName]
    local tf = f and f.textFrame
    local w = 0
    if f and f.GetWidth then
        w = f:GetWidth() or 0
    elseif tf and tf.GetWidth then
        w = tf:GetWidth() or 0
    end
    w = tonumber(w) or 0
    if w <= 0 then
        local confFallback = MSUF_DB[k]
        w = tonumber(confFallback and confFallback.width) or tonumber(MSUF_DB.general and MSUF_DB.general.frameWidth) or 0
    end

    local conf = MSUF_DB[k] or {}
    local hX = MSUF_Offset(conf.hpOffsetX, -4)
    local leftPad = 8

    local pctW = 0
    if f and f.hpTextPct then
        pctW = MSUF_GetApproxPercentTextWidth(f.hpTextPct)
    end

    -- Which text is the one that moves left when the spacer increases depends on hpTextMode.
    -- FULL_PLUS_PERCENT: Full value is left, % is right  -> full value moves.
    -- PERCENT_PLUS_FULL: % is left, full value is right  -> percent moves.
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hpMode = g.hpTextMode or "FULL_PLUS_PERCENT"
    local movingW = pctW
    if hpMode == "FULL_PLUS_PERCENT" then
        if f and f.hpText then
            movingW = MSUF_GetApproxHpFullTextWidth(f.hpText)
        elseif f and f.hpTextPct then
            -- Fallback: best-effort font match.
            movingW = MSUF_GetApproxHpFullTextWidth(f.hpTextPct)
        else
            movingW = 0
        end
    end

    local maxSpacer = (tonumber(w) or 0) + (tonumber(hX) or 0) - (leftPad + (tonumber(movingW) or 0))
    maxSpacer = tonumber(maxSpacer) or 0
    if maxSpacer < 0 then maxSpacer = 0 end
    -- Allow a bit more range (~15%) per user request, while keeping a hard upper cap.
    maxSpacer = maxSpacer * MSUF_HP_SPACER_SCALE
    maxSpacer = math.floor(maxSpacer + 0.5)
    if maxSpacer > MSUF_HP_SPACER_MAXCAP then maxSpacer = MSUF_HP_SPACER_MAXCAP end
    return maxSpacer
end

local function ApplyTextLayout(f, conf)
    if not f or not f.textFrame or not conf then return end
    local tf = f.textFrame
    local nX = MSUF_Offset(conf.nameOffsetX,   4)
    local nY = MSUF_Offset(conf.nameOffsetY,  -4)
    local hX = MSUF_Offset(conf.hpOffsetX,    -4)
    local hY = MSUF_Offset(conf.hpOffsetY,    -4)
    local pX = MSUF_Offset(conf.powerOffsetX, -4)
    local pY = MSUF_Offset(conf.powerOffsetY,  4)

    local key = f.msufConfigKey
    if not key and f.unit and GetConfigKeyForUnit then
        key = GetConfigKeyForUnit(f.unit)
    end
    local udb = (MSUF_DB and key and MSUF_DB[key]) or nil
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local hpMode = (g and g.hpTextMode) or "FULL_PLUS_PERCENT"
    local spacerOn = false
    local spacerX = 0
    if f.hpTextPct then
        spacerOn = (udb and udb.hpTextSpacerEnabled == true) or (not udb and g and g.hpTextSpacerEnabled == true)
        spacerX = (udb and tonumber(udb.hpTextSpacerX)) or ((g and tonumber(g.hpTextSpacerX)) or 0)
    end

    local wUsed = nil
    if f and f.GetWidth then wUsed = f:GetWidth() end
    if (not wUsed or wUsed == 0) and tf and tf.GetWidth then wUsed = tf:GetWidth() end
    if (not wUsed or wUsed == 0) and conf then wUsed = tonumber(conf.width) end
    wUsed = tonumber(wUsed) or 0

    local effSpacerX = 0
    if f.hpTextPct then
        local maxSpacer = 0
        do
            local w = wUsed
            local leftPad = 8
            local pctW = 0
            if f and f.hpTextPct then
                pctW = MSUF_GetApproxPercentTextWidth(f.hpTextPct)
            end

            local movingW = pctW
            if hpMode == "FULL_PLUS_PERCENT" then
                -- In FULL_PLUS_PERCENT spacer mode we move the full value left, so clamp based on full-text width.
                if f and f.hpText then
                    movingW = MSUF_GetApproxHpFullTextWidth(f.hpText)
                elseif f and f.hpTextPct then
                    movingW = MSUF_GetApproxHpFullTextWidth(f.hpTextPct)
                else
                    movingW = 0
                end
            end

            maxSpacer = (tonumber(w) or 0) + (tonumber(hX) or 0) - (leftPad + (tonumber(movingW) or 0))
            maxSpacer = tonumber(maxSpacer) or 0
            if maxSpacer < 0 then maxSpacer = 0 end
            -- Keep layout clamp consistent with the slider (see MSUF_GetHPSpacerMaxForUnitKey).
            maxSpacer = maxSpacer * MSUF_HP_SPACER_SCALE
            maxSpacer = math.floor(maxSpacer + 0.5)
            if maxSpacer > MSUF_HP_SPACER_MAXCAP then maxSpacer = MSUF_HP_SPACER_MAXCAP end
        end
        effSpacerX = tonumber(spacerX) or 0
        if effSpacerX < 0 then effSpacerX = 0 end
        if effSpacerX > maxSpacer then effSpacerX = maxSpacer end
        if (not spacerOn) then
            effSpacerX = 0
        end
    end

    local stamp = tostring(tf).."|"..tostring(nX).."|"..tostring(nY).."|"..tostring(hX).."|"..tostring(hY).."|"..tostring(pX).."|"..tostring(pY)
        .."|pct:"..tostring(f.hpTextPct and 1 or 0).."|"..tostring(spacerOn and 1 or 0).."|"..tostring(effSpacerX).."|w:"..tostring(wUsed).."|k:"..tostring(key or "")
        .."|hpMode:"..tostring(hpMode or "")
    if f._msufTextLayoutStamp == stamp then
        return
    end
    f._msufTextLayoutStamp = stamp

    if f.nameText then
        MSUF_ApplyPoint(f.nameText, "TOPLEFT", tf, "TOPLEFT", nX, nY)
        f._msufNameAnchorPoint = "TOPLEFT"
        f._msufNameAnchorRel = tf
        f._msufNameAnchorRelPoint = "TOPLEFT"
        f._msufNameAnchorX = nX
        f._msufNameAnchorY = nY
        -- Changing anchors invalidates name clipping state.
        f._msufNameClipSideApplied = nil
        f._msufNameClipReservedRight = nil
        f._msufNameClipTextStamp = nil
        f._msufNameClipAnchorStamp = nil
        f._msufClampStamp = nil
    end
    if f.levelText and f.nameText then
        MSUF_ApplyLevelIndicatorLayout_Internal(f, conf)
    end
    if f.hpText then
        if spacerOn and effSpacerX ~= 0 and hpMode == "FULL_PLUS_PERCENT" and f.hpTextPct then
            -- Respect dropdown order: FULL + % -> full value on the left, percent on the right.
            MSUF_ApplyPoint(f.hpText, "TOPRIGHT", tf, "TOPRIGHT", hX - effSpacerX, hY)
        else
            -- Default: full value stays on the right.
            MSUF_ApplyPoint(f.hpText, "TOPRIGHT", tf, "TOPRIGHT", hX, hY)
        end
    end
    if f.hpTextPct then
        if spacerOn and effSpacerX ~= 0 then
            if hpMode == "FULL_PLUS_PERCENT" then
                -- FULL + % -> percent on the right.
                MSUF_ApplyPoint(f.hpTextPct, "TOPRIGHT", tf, "TOPRIGHT", hX, hY)
            else
                -- % + FULL (and anything else) -> percent is the left part.
                MSUF_ApplyPoint(f.hpTextPct, "TOPRIGHT", tf, "TOPRIGHT", hX - effSpacerX, hY)
            end
        else
            MSUF_ApplyPoint(f.hpTextPct, "TOPRIGHT", tf, "TOPRIGHT", hX, hY)
        end
    end
    if f.powerText then
        MSUF_ApplyPoint(f.powerText, "BOTTOMRIGHT", tf, "BOTTOMRIGHT", pX, pY)
    end
end

-- Force a one-shot text layout + HP text refresh for a specific MSUF unit key.
-- Used by Options sliders (HP Spacer etc.) so changes are visible immediately without needing a separator toggle.
function _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
    if type(EnsureDB) == "function" then
        EnsureDB()
    end

    local k = unitKey
    if not k or k == "" then
        k = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.hpSpacerSelectedUnitKey) or "player"
    end
    if k == "tot" then k = "targettarget" end
    if type(k) == "string" and string.match(k, "^boss%d+$") then k = "boss" end
    if k ~= "player" and k ~= "target" and k ~= "focus" and k ~= "targettarget" and k ~= "pet" and k ~= "boss" then
        k = "player"
    end

    local function ApplyForFrame(f)
        if not f then return end

        -- Force ApplyTextLayout() to run even if its stamp would otherwise early-return.
        f._msufTextLayoutStamp = nil

        -- Resolve config (cached or from DB).
        local key = f.msufConfigKey
        if not key and f.unit and type(GetConfigKeyForUnit) == "function" then
            key = GetConfigKeyForUnit(f.unit)
            f.msufConfigKey = key
        end

        local conf = f.cachedConfig
        if (not conf) and key and MSUF_DB then
            conf = MSUF_DB[key]
            f.cachedConfig = conf
        end
        if (not conf) and MSUF_DB and k and MSUF_DB[k] then
            conf = MSUF_DB[k]
            f.cachedConfig = conf
        end
        if not conf then return end

        if type(ApplyTextLayout) == "function" then
            ApplyTextLayout(f, conf)
        end

        -- Anchors can affect name clipping; refresh once to avoid stale clipping state.
        if type(MSUF_ClampNameWidth) == "function" then
            MSUF_ClampNameWidth(f, conf)
        end

        -- IMPORTANT: Spacer changes do not necessarily trigger a UNIT_HEALTH event.
        -- Force a one-shot HP text refresh so % (hpTextPct) shows/hides and the split is visible immediately.
        if conf.showHP ~= nil then
            f.showHPText = (conf.showHP ~= false)
        end

        local unit = f.unit
        local hasUnit = false
        if unit and UnitExists then
            local okExists, exists = pcall(UnitExists, unit)
            hasUnit = okExists and exists
        end

        if hasUnit and type(_G.MSUF_UFCore_UpdateHpTextFast) == "function" and UnitHealth then
            local okHp, hp = pcall(UnitHealth, unit)
            if okHp then
                f._msufLastHpValue = nil
                _G.MSUF_UFCore_UpdateHpTextFast(f, hp)
            end
        else
            -- Edit Mode previews (focus / ToT etc.) may have no real unit; refresh once so preview texts re-evaluate.
            if not (InCombatLockdown and InCombatLockdown()) and (MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode)) then
                if f.isBoss and MSUF_BossTestMode and type(_G.MSUF_ApplyBossTestHpPreviewText) == "function" then
                    _G.MSUF_ApplyBossTestHpPreviewText(f, conf)
                elseif type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                    f._msufLastHpValue = nil
                    _G.MSUF_RequestUnitframeUpdate(f, true, false, "HPSpacer")
                elseif type(UpdateSimpleUnitFrame) == "function" then
                    f._msufLastHpValue = nil
                    UpdateSimpleUnitFrame(f)
                end
            elseif f.isBoss and MSUF_BossTestMode and type(_G.MSUF_ApplyBossTestHpPreviewText) == "function" then
                _G.MSUF_ApplyBossTestHpPreviewText(f, conf)
            end
        end
    end

    if k == "boss" then
        for i = 1, 5 do
            ApplyForFrame(_G["MSUF_boss" .. i])
        end
    else
        ApplyForFrame(_G["MSUF_" .. k])
    end
end

function MSUF_UpdateBossPortraitLayout(f, conf)
    if not f or not f.portrait or not conf then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local size = math.max(16, h - 4)
    local portrait = f.portrait
    portrait:ClearAllPoints()
    portrait:SetSize(size, size)
    local anchor = f.hpBar or f
    if f._msufPowerBarReserved then
        anchor = f
    end
    if mode == "LEFT" then
        portrait:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
        portrait:Show()
    elseif mode == "RIGHT" then
        portrait:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
        portrait:Show()
    else
        portrait:Hide()
    end
end

-- Portrait performance: apply layout + texture only when needed (avoid SetPortraitTexture spam)
-- Portrait limiter (oUF-like): portraits are event-driven, but we avoid running SetPortraitTexture
-- multiple times in a burst (e.g. target-swap spam). We budget updates globally to ~1 per frame
-- and also apply a small per-frame minimum interval. This keeps portraits accurate while reducing
-- spikes from repeated portrait/model updates.
local MSUF_PORTRAIT_MIN_INTERVAL = 0.06 -- seconds; small enough to feel instant
local MSUF_PORTRAIT_BUDGET_USED = false
local MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false

local function MSUF_ResetPortraitBudgetNextFrame()
    if MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED then return end
    MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            MSUF_PORTRAIT_BUDGET_USED = false
            MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false
        end)
    else
        -- Fallback: if C_Timer isn't available, just release immediately.
        MSUF_PORTRAIT_BUDGET_USED = false
        MSUF_PORTRAIT_BUDGET_RESET_SCHEDULED = false
    end
end
local function MSUF_ApplyPortraitLayoutIfNeeded(f, conf)
    if not f or not conf then return end
    local portrait = f.portrait
    if not portrait then return end
    local mode = conf.portraitMode or "OFF"
    local h = conf.height or (f.GetHeight and f:GetHeight()) or 30
    local stamp = tostring(mode) .. "|" .. tostring(h)
    if f._msufPortraitLayoutStamp ~= stamp then
        f._msufPortraitLayoutStamp = stamp
        MSUF_UpdateBossPortraitLayout(f, conf)
    end
end

local function MSUF_UpdatePortraitIfNeeded(f, unit, conf, existsForPortrait)
    if not f or not f.portrait or not conf then return end
    local mode = conf.portraitMode or "OFF"

    -- Fix: portraits could stay blank across /reload or relog if multiple frames become dirty in the same frame.
    -- Our global portrait budget allows ~1 SetPortraitTexture per frame; the "losing" frame can remain dirty with
    -- no further unit updates to trigger a retry. We stamp mode transitions and schedule a one-shot retry when
    -- we miss the budget/interval, without adding any tickers or heavy code.
    if f._msufPortraitModeStamp ~= mode then
        f._msufPortraitModeStamp = mode
        if mode ~= "OFF" then
            f._msufPortraitDirty = true
            f._msufPortraitNextAt = 0
        end
    end

    if mode == "OFF" or not existsForPortrait then
        f.portrait:Hide()
        return
    end

    MSUF_ApplyPortraitLayoutIfNeeded(f, conf)

    if f._msufPortraitDirty then
        local now = (GetTime and GetTime()) or 0
        local nextAt = tonumber(f._msufPortraitNextAt) or 0
        if (now >= nextAt) and (not MSUF_PORTRAIT_BUDGET_USED) then
            if SetPortraitTexture then
                SetPortraitTexture(f.portrait, unit)
            end
            f._msufPortraitDirty = nil
            f._msufPortraitNextAt = now + MSUF_PORTRAIT_MIN_INTERVAL
            MSUF_PORTRAIT_BUDGET_USED = true
            MSUF_ResetPortraitBudgetNextFrame()
        else
            -- Keep dirty; schedule a single retry after the interval/budget resets.
            if not f._msufPortraitRetryScheduled and C_Timer and C_Timer.After then
                f._msufPortraitRetryScheduled = true
                local delay = 0
                if now < nextAt then
                    delay = nextAt - now
                    if delay < 0 then delay = 0 end
                end
                C_Timer.After(delay, function()
                    if not f then return end
                    f._msufPortraitRetryScheduled = nil
                    if not f._msufPortraitDirty then return end
                    if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                        _G.MSUF_RequestUnitframeUpdate(f, false, false, "PortraitRetry")
                    else
                        local upd = _G.UpdateSimpleUnitFrame
                        if type(upd) == "function" then
                            upd(f)
                        end
                    end
                end)
            end
            MSUF_ResetPortraitBudgetNextFrame()
        end
    end

    f.portrait:Show()
end

-- then multiplies by maxChars to get a clip width. Never measures secret unit names. to get a clip width. Never measures secret unit names.
local function MSUF_GetApproxNameWidthForChars(templateFS, maxChars)
    if not templateFS or not templateFS.GetFont then return nil end
    maxChars = tonumber(maxChars) or 16
    if maxChars < 1 then maxChars = 1 end
    if maxChars > 60 then maxChars = 60 end
    local font, size, flags = templateFS:GetFont()
    local fontKey = tostring(font or "") .. "|" .. tostring(size or 0) .. "|" .. tostring(flags or "")
    _G.MSUF_NameWidthAvgCache = _G.MSUF_NameWidthAvgCache or {}
    local cache = _G.MSUF_NameWidthAvgCache
    local avg = cache[fontKey]
    if not avg then
        local fs = _G.MSUF_NameMeasureFS
        if not fs then
            local holder = CreateFrame("Frame", "MSUF_NameMeasureFrame", UIParent)
            holder:Hide()
            fs = holder:CreateFontString(nil, "OVERLAY")
            fs:Hide()
            _G.MSUF_NameMeasureFS = fs
        end
        if font and size then
            fs:SetFont(font, size, flags)
        end
        local sample = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        fs:SetText(sample)
        local w = fs:GetStringWidth()
        if type(w) == "number" and w > 0 then
            avg = w / #sample
        else
            avg = (tonumber(size) or 12) * 0.55
        end
        cache[fontKey] = avg
    end
    return avg * maxChars
end
function MSUF_ClampNameWidth(f, conf)
    if not f or not f.nameText then return end

    f.nameText:SetWordWrap(false)
    if f.nameText.SetNonSpaceWrap then
        f.nameText:SetNonSpaceWrap(false)
    end

    local shorten = (MSUF_DB and MSUF_DB.shortenNames) and true or false

    local unitKey = f and (f.unitKey or f.unit or f.msufConfigKey)
    -- Do NOT apply name shortening to the Player unitframe, but keep it for all other frames.
    -- Be robust to different key tokens (player / Player / PLAYER) and config keys.
    if unitKey == "player" or unitKey == "Player" or unitKey == "PLAYER" then
        shorten = false
    end

    -- If shorten is OFF: reset to normal, but only once (stamp)
    if not shorten then
        local tf = f.textFrame or f
        local ap  = f._msufNameAnchorPoint or "TOPLEFT"
        local rel = f._msufNameAnchorRel or tf
        local arp = f._msufNameAnchorRelPoint or "TOPLEFT"
        local ax  = (type(f._msufNameAnchorX) == "number") and f._msufNameAnchorX or 4
        local ay  = (type(f._msufNameAnchorY) == "number") and f._msufNameAnchorY or -4

        local stamp = "OFF|"..tostring(ap).."|"..tostring(arp).."|"..tostring(ax).."|"..tostring(ay)
        if f._msufClampStamp == stamp then
            return
        end
        f._msufClampStamp = stamp

        if f._msufNameClipAnchorMode ~= nil then
            f.nameText:ClearAllPoints()
            f.nameText:SetPoint(ap, rel, arp, ax, ay)
            f._msufNameClipAnchorMode = nil
            f._msufNameClipSideApplied = nil
            f._msufNameClipAnchorX = nil
            f._msufNameClipAnchorY = nil
        end
        if f.nameText.SetJustifyH then
            f.nameText:SetJustifyH("LEFT")
        end
        -- If we were using the clip viewport, restore original parenting + hide viewport
        if f._msufNameClipFrame then
            local clip = f._msufNameClipFrame
            if clip.Hide then clip:Hide() end
            if f.nameText and f.nameText.GetParent and f.nameText:GetParent() == clip then
                local p = f._msufNameTextOrigParent or (f.textFrame or f)
                f.nameText:SetParent(p)
            end
        end
        f._msufNameClipAnchorStamp = nil
        f._msufNameClipTextStamp = nil

        if f._msufNameDotsFS then
            if f._msufNameDotsFS.Hide then f._msufNameDotsFS:Hide() end
        end

        f.nameText:SetWidth(0)
        return
    end

    -- Secret-safe: avoid measuring real (secret) unit names. We only compute a pixel clamp width.
    local frameWidth = 0
    if conf and type(conf.width) == "number" then
        frameWidth = conf.width
    elseif type(f._msufW) == "number" then
        frameWidth = f._msufW
    elseif f.GetWidth then
        local w = f:GetWidth()
        if type(w) == "number" then
            frameWidth = w
        end
    end
    if frameWidth <= 0 then
        frameWidth = 220
    end

    -- Hard cap budget: ~80% of frame width (still secret-safe and prevents overlaps)
    local baseWidth = math.floor((frameWidth * 0.80) + 0.5)
    if baseWidth < 80 then baseWidth = 80 end

    -- Fixed reservations (secret-safe; never derived from unit names)
    local reservedRight = 0
    local lvlShown = false
    local lvlAnchor = f._msufLevelAnchor or "NAMERIGHT"
    if lvlAnchor == "NAMERIGHT" and f.levelText and f.levelText.IsShown and f.levelText:IsShown() then
        reservedRight = reservedRight + 26
        lvlShown = true
    end

    local nameWidth = baseWidth - reservedRight
    if nameWidth < 40 then nameWidth = 40 end

    -- Optionally tighten width using a safe font-average approximation
    local maxChars = 16
    local g = MSUF_DB and MSUF_DB.general
    if g and type(g.shortenNameMaxChars) == "number" then
        maxChars = g.shortenNameMaxChars
    end
    if maxChars < 4 then maxChars = 4 end
    if maxChars > 40 then maxChars = 40 end

    if MSUF_GetApproxNameWidthForChars then
        local approx = MSUF_GetApproxNameWidthForChars(f.nameText, maxChars)
        if type(approx) == "number" and approx > 0 then
            local w = math.floor(approx + 0.5) - reservedRight
            if w < nameWidth then
                nameWidth = w
                if nameWidth < 40 then nameWidth = 40 end
            end
        end
    end

    -- Name shortening mode (secret-safe).
    -- Keep end (clip left) remains the viewport-based mode.
    -- The old keep-start (clip right) viewport mode is removed and replaced by the legacy-clean mode:
    --   LEFT  = clip LEFT via viewport, keep name end/suffix (R41z0r-style)
    --   RIGHT = legacy MSUF clean end-shortening (clips the END) by setting a fixed FontString width
    local mode = (g and g.shortenNameClipSide) or "LEFT"
    if mode ~= "LEFT" and mode ~= "RIGHT" then
        mode = "LEFT"
    end

    local legacyEndClip = (mode == "RIGHT")
    -- Viewport path only ever uses LEFT clipping.
    local clipSide = "LEFT"

    local maskPx = 0
    if not legacyEndClip then
        if g and g.shortenNameFrontMaskPx ~= nil then
            maskPx = tonumber(g.shortenNameFrontMaskPx) or 0
        end
        maskPx = math.floor(maskPx + 0.5)
        if maskPx < 0 then maskPx = 0 end
        if maskPx > 80 then maskPx = 80 end
    end

    local showDots = true
    if g and g.shortenNameShowDots ~= nil then
        showDots = (g.shortenNameShowDots and true or false)
    end
    -- Legacy clean mode intentionally has no dots/ellipsis UI.
    if legacyEndClip then
        showDots = false
    end

    -- Stamp: if nothing relevant changed, do nothing (no SetWidth, no anchor ops)
    local tf = f.textFrame or f
    local ap  = f._msufNameAnchorPoint or "TOPLEFT"
    local rel = f._msufNameAnchorRel or tf
    local arp = f._msufNameAnchorRelPoint or "TOPLEFT"
    local ax  = (type(f._msufNameAnchorX) == "number") and f._msufNameAnchorX or 4
    local ay  = (type(f._msufNameAnchorY) == "number") and f._msufNameAnchorY or -4

    local stamp = "ON|"..tostring(frameWidth).."|"..tostring(baseWidth).."|"..tostring(reservedRight).."|"..tostring(nameWidth).."|"..tostring(maxChars).."|"..tostring(lvlShown and 1 or 0).."|"..tostring(ap).."|"..tostring(arp).."|"..tostring(ax).."|"..tostring(ay).."|"..tostring(mode).."|"..tostring(maskPx).."|"..tostring(showDots and 1 or 0)
    if f._msufClampStamp == stamp then
        return
    end
    f._msufClampStamp = stamp


    -- Legacy "clean" end-shortening: no viewport. Just constrain the FontString width and let it clip on the right.
    if legacyEndClip then
        -- Ensure we are not parented to the viewport from another mode.
        if f._msufNameClipFrame then
            local clip = f._msufNameClipFrame
            if clip.Hide then clip:Hide() end
            if f.nameText and f.nameText.GetParent and f.nameText:GetParent() == clip then
                local p = f._msufNameTextOrigParent or (f.textFrame or f)
                f.nameText:SetParent(p)
            end
        end
        if f._msufNameDotsFS then
            if f._msufNameDotsFS.Hide then f._msufNameDotsFS:Hide() end
        end
        -- Restore original anchor
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint(ap, rel, arp, ax, ay)
        f._msufNameClipAnchorStamp = nil
        f._msufNameClipTextStamp = nil

        if f.nameText.SetJustifyH then
            f.nameText:SetJustifyH("LEFT")
        end
        -- Constrain width so the end of the name is clipped cleanly.
        f.nameText:SetWidth(nameWidth)
        f._msufNameClipSideApplied = "RIGHT"
        return
    end

    local clipW = nameWidth - maskPx
    if clipW < 10 then clipW = 10 end

    -- Ensure clip viewport frame
    local clip = f._msufNameClipFrame
    if not clip then
        clip = CreateFrame("Frame", nil, tf)
        clip:SetClipsChildren(true)
        clip:Show()
        f._msufNameClipFrame = clip
        if not f._msufNameTextOrigParent then
            f._msufNameTextOrigParent = f.nameText:GetParent()
        end
        if tf and tf.GetFrameStrata then
            clip:SetFrameStrata(tf:GetFrameStrata())
        end
        if tf and tf.GetFrameLevel then
            clip:SetFrameLevel(tf:GetFrameLevel() + 1)
        end
    else
        if clip.GetParent and clip:GetParent() ~= tf then
            clip:SetParent(tf)
        end
        clip:Show()
    end

    if f.nameText:GetParent() ~= clip then
        if not f._msufNameTextOrigParent then
            f._msufNameTextOrigParent = tf
        end
        f.nameText:SetParent(clip)
    end

    -- Size viewport (height based on font / frame)
    local fontH = 0
    if f.nameText.GetFont then
        local _, sz = f.nameText:GetFont()
        if type(sz) == "number" then
            fontH = sz
        end
    end
    local clipH = math.floor(((fontH > 0 and fontH or 12) * 1.6) + 0.5)
    if conf and type(conf.height) == "number" then
        local hh = math.floor((conf.height * 0.80) + 0.5)
        if hh > clipH then
            clipH = hh
        end
    end
    if clipH < 12 then clipH = 12 end
    if clipH > 48 then clipH = 48 end

    clip:SetSize(clipW, clipH)

    -- Anchor viewport. Prefer right-anchored viewport for LEFT-clip so maskPx does not shift the suffix.
    local anchorStamp = tostring(ap) .. "|" .. tostring(arp) .. "|" .. tostring(ax) .. "|" .. tostring(ay)
        .. "|" .. tostring(clipSide) .. "|" .. tostring(maskPx) .. "|" .. tostring(clipW) .. "|" .. tostring(clipH)

    if f._msufNameClipAnchorStamp ~= anchorStamp then
        f._msufNameClipAnchorStamp = anchorStamp
        clip:ClearAllPoints()

        if clipSide == "LEFT" and ap == "TOPLEFT" and arp == "TOPLEFT" then
            -- Keep right edge stable; shrink viewport from the left (leaves maskPx space on the left).
            clip:SetPoint("TOPRIGHT", rel, "TOPLEFT", ax + nameWidth, ay)
        elseif clipSide == "RIGHT" and ap == "TOPLEFT" and arp == "TOPLEFT" then
            -- Keep left edge stable; shrink viewport from the right (leaves maskPx space on the right).
            clip:SetPoint("TOPLEFT", rel, "TOPLEFT", ax, ay)
        else
            -- Fallback: keep legacy anchor (maskPx may shift position for non-standard anchors)
            clip:SetPoint(ap, rel, arp, ax, ay)
        end
    end

    -- Anchor name text inside viewport (no FontString width; viewport does the clipping)
    -- IMPORTANT: this must be resilient against other code (e.g. font/apply passes) resetting justify/anchors.
    local textStamp = tostring(clipSide)
    local desiredJustify = (clipSide == "LEFT") and "RIGHT" or "LEFT"
    local needTextReanchor = (f._msufNameClipTextStamp ~= textStamp)
    if not needTextReanchor then
        if f.nameText and f.nameText.GetParent and f.nameText:GetParent() ~= clip then
            needTextReanchor = true
        elseif f.nameText and f.nameText.GetJustifyH and f.nameText:GetJustifyH() ~= desiredJustify then
            needTextReanchor = true
        end
    end

    if needTextReanchor then
        f._msufNameClipTextStamp = textStamp
        f.nameText:ClearAllPoints()
        if clipSide == "LEFT" then
            f.nameText:SetPoint("TOPRIGHT", clip, "TOPRIGHT", 0, 0)
        else
            f.nameText:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
        end
        if f.nameText and f.nameText.SetJustifyH then
            f.nameText:SetJustifyH(desiredJustify)
        end
        if f.nameText and f.nameText.SetParent then
            f.nameText:SetParent(clip)
        end
    end

    -- Optional ellipsis/dots indicator (secret-safe: never inspects the actual name text)
    if showDots and maskPx > 0 then
        local dots = f._msufNameDotsFS
        if not dots then
	            -- IMPORTANT: FontStrings without a template may have no font assigned.
	            -- Calling :SetText() without a font triggers "Font not set" errors.
	            dots = tf:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	            -- Try to match the name font BEFORE setting any text.
	            if f.nameText and f.nameText.GetFont and dots and dots.SetFont then
	                local ff, sz, fl = f.nameText:GetFont()
	                if ff and sz then
	                    dots:SetFont(ff, sz, fl)
	                end
	            end

	            -- Fallback font object if something still left us without a font.
	            if dots and dots.GetFont and dots.SetFontObject then
	                local ff = dots:GetFont()
	                if not ff and GameFontNormalSmall then
	                    dots:SetFontObject(GameFontNormalSmall)
	                end
	            end

	            dots:SetText("...")
            dots:Hide()
            f._msufNameDotsFS = dots
            if tf and tf.GetFrameLevel then
                -- Ensure dots are above the clip viewport + name
                dots:SetDrawLayer("OVERLAY", 7)
            end
        end

        -- Match name font
        if f.nameText and f.nameText.GetFont and dots.SetFont then
            local ff, sz, fl = f.nameText:GetFont()
            if ff and sz then
                dots:SetFont(ff, sz, fl)
            end
        end

        local dotStamp = tostring(clipSide) .. "|" .. tostring(maskPx) .. "|" .. tostring(ap) .. "|" .. tostring(arp) .. "|" .. tostring(ax) .. "|" .. tostring(ay) .. "|" .. tostring(nameWidth)
        if f._msufNameDotsStamp ~= dotStamp then
            f._msufNameDotsStamp = dotStamp
            dots:ClearAllPoints()

            if clipSide == "LEFT" then
                -- Dots on the LEFT edge (clipped side). Use clip frame to stay stable even for non-standard anchors.
                dots:SetPoint("TOPLEFT", clip, "TOPLEFT", -maskPx, 0)
            else
                -- Dots on the RIGHT edge (clipped side).
                dots:SetPoint("TOPRIGHT", clip, "TOPRIGHT", maskPx, 0)
            end
        end

        dots:Show()
    else
        if f._msufNameDotsFS then
            f._msufNameDotsFS:Hide()
        end
    end


    f.nameText:SetWidth(0)
    f._msufNameClipSideApplied = clipSide
end

local function MSUF_GetUnitLevelText(unit)
    if not unit or not UnitLevel then return "" end
    local lvl = UnitLevel(unit)
    if not lvl then return "" end
    if lvl == -1 then
        return "??"
    end
    if lvl <= 0 then
        return ""
    end
    return tostring(lvl)
end
local function MSUF_GetUnitHealthPercent(unit)
    if type(UnitHealthPercent) == "function" then
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            -- Secret-safe + snappy: usePredicted=true (avoid Lua arithmetic on secret values)
            ok, pct = MSUF_FastCall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        else
            ok, pct = MSUF_FastCall(UnitHealthPercent, unit, true, true)
        end
        -- Secret-safe: avoid comparing returned values in Lua (pct may be a "secret" number).
        if ok then
            return pct
        end
        return nil
    end
    -- 12.0+: If UnitHealthPercent is unavailable, avoid computing percent in Lua (secret-safe).
    return nil
end
local function MSUF_GetUnitPowerPercent(unit)
    if type(UnitPowerPercent) == "function" then
        -- IMPORTANT: never compute percent in Lua (secret-safe). Also pass the unit's active powerType
        local pType
        if type(UnitPowerType) == "function" then
            local okType, pt = MSUF_FastCall(UnitPowerType, unit)
            if okType then
                pType = pt
            end
        end
        local ok, pct
        if CurveConstants and CurveConstants.ScaleTo100 then
            ok, pct = MSUF_FastCall(UnitPowerPercent, unit, pType, false, CurveConstants.ScaleTo100)
        else
            ok, pct = MSUF_FastCall(UnitPowerPercent, unit, pType, false, true)
        end
        -- Secret-safe: avoid comparing returned values in Lua (pct may be a "secret" number).
        if ok then
            return pct
        end
        return nil
    end
    -- 12.0+: If UnitPowerPercent is unavailable, avoid computing percent in Lua (secret-safe).
    return nil
end
local function MSUF_NumberToTextFast(v)
    if type(v) ~= "number" then
        return nil
    end
    -- Prefer Blizzard/C-side abbreviators (K/M/B). Treat returned text as opaque (secret-safe).
    local abbr = _G.ShortenNumber or _G.AbbreviateNumbers or _G.AbbreviateLargeNumbers
    if abbr then
        local ok, s = MSUF_FastCall(abbr, v)
        if ok then
            return s
        end
    end
    return tostring(v)
end
function MSUF_ApplyLeaderIconLayout(f)
    if not f or not f.leaderIcon then return end
    EnsureDB()
    if not MSUF_DB then return end

    local g = MSUF_DB.general or {}

    local key
    if f.unit and type(GetConfigKeyForUnit) == "function" then
        key = GetConfigKeyForUnit(f.unit)
    end
    local conf = (key and MSUF_DB[key]) or nil

    local size = tonumber((conf and conf.leaderIconSize) or g.leaderIconSize or 14) or 14
    size = math.floor(size + 0.5)
    if size < 8 then size = 8 end
    if size > 64 then size = 64 end

    local ox = tonumber((conf and conf.leaderIconOffsetX) or g.leaderIconOffsetX or 0) or 0
    local oy = tonumber((conf and conf.leaderIconOffsetY) or g.leaderIconOffsetY or 3) or 3
    local anchor = (conf and conf.leaderIconAnchor) or g.leaderIconAnchor or "TOPLEFT"

    -- Layout stamp: avoid re-anchoring every UpdateSimpleUnitFrame()
    local stamp = tostring(size).."|"..tostring(ox).."|"..tostring(oy).."|"..tostring(anchor).."|"..tostring(key or "")
    if f._msufLeaderIconLayoutStamp == stamp then
        return
    end
    f._msufLeaderIconLayoutStamp = stamp

    local point, relPoint = "LEFT", "TOPLEFT"
    if anchor == "TOPRIGHT" then
        point, relPoint = "RIGHT", "TOPRIGHT"
    elseif anchor == "BOTTOMLEFT" then
        point, relPoint = "LEFT", "BOTTOMLEFT"
    elseif anchor == "BOTTOMRIGHT" then
        point, relPoint = "RIGHT", "BOTTOMRIGHT"
    end

    f.leaderIcon:SetSize(size, size)
    f.leaderIcon:ClearAllPoints()
    f.leaderIcon:SetPoint(point, f, relPoint, ox, oy)

    if f.assistantIcon then
        f.assistantIcon:SetSize(size, size)
        f.assistantIcon:ClearAllPoints()
        f.assistantIcon:SetPoint(point, f, relPoint, ox, oy - (size - 1))
    end
end
function MSUF_ApplyRaidMarkerLayout(f)
    if not f or not f.raidMarkerIcon then return end
    if not MSUF_DB or not MSUF_DB.general then return end
    local g = MSUF_DB.general
    if g.raidMarkerSize == nil then
        g.raidMarkerSize = 14
    end
    local key = (f.unit and GetConfigKeyForUnit and GetConfigKeyForUnit(f.unit)) or nil
    local conf = (key and MSUF_DB and MSUF_DB[key]) or nil
    local size = tonumber((conf and conf.raidMarkerSize) or g.raidMarkerSize or 14) or 14
    size = math.floor(size + 0.5)
    if size < 8 then size = 8 end
    if size > 64 then size = 64 end
    local ox = tonumber((conf and conf.raidMarkerOffsetX) or g.raidMarkerOffsetX)
    if ox == nil then ox = 16 end
    local oy = tonumber((conf and conf.raidMarkerOffsetY) or g.raidMarkerOffsetY)
    if oy == nil then oy = 3 end
    local anchor = (conf and conf.raidMarkerAnchor) or g.raidMarkerAnchor or "TOPLEFT"
    local point, relPoint = "LEFT", "TOPLEFT"
    if anchor == "CENTER" then
        point, relPoint = "CENTER", "CENTER"
    elseif anchor == "TOPRIGHT" then
        point, relPoint = "RIGHT", "TOPRIGHT"
    elseif anchor == "BOTTOMLEFT" then
        point, relPoint = "LEFT", "BOTTOMLEFT"
    elseif anchor == "BOTTOMRIGHT" then
        point, relPoint = "RIGHT", "BOTTOMRIGHT"
    end
    local stamp = tostring(size) .. "|" .. tostring(ox) .. "|" .. tostring(oy) .. "|" .. tostring(anchor) .. "|" .. tostring(key or "")
    if f._msufRaidMarkerLayoutStamp == stamp then
        return
    end
    f._msufRaidMarkerLayoutStamp = stamp
    f.raidMarkerIcon:SetSize(size, size)
    f.raidMarkerIcon:ClearAllPoints()
    f.raidMarkerIcon:SetPoint(point, f, relPoint, ox, oy)
end

function _G.MSUF_UFCore_UpdateHealthFast(self)
    if not self or not self.unit or not self.hpBar then return nil, nil, false end
    local unit = self.unit

    if not UnitExists(unit) then
        MSUF_ResetBarZero(self.hpBar)
        MSUF_ResetBarZero(self.absorbBar, true)
        MSUF_ResetBarZero(self.healAbsorbBar, true)
        return 0, 1, false
    end

    -- Secret-safe: UnitHealthMax(unit) may return a "secret" number in Beta.
    -- Never compare/clamp in Lua; just pass it through to SetMinMaxValues.
    local maxHP = UnitHealthMax(unit) or 1
    self.hpBar:SetMinMaxValues(0, maxHP)

    local hp = UnitHealth(unit) or 0
    MSUF_SetBarValue(self.hpBar, hp)

    -- Keep absorb overlays accurate (cheap; API numbers only)
    if self.absorbBar then
        MSUF_UpdateAbsorbBar(self, unit, maxHP)
    end
    if self.healAbsorbBar then
        MSUF_UpdateHealAbsorbBar(self, unit, maxHP)
    end

    return hp, maxHP, true
end

function _G.MSUF_UFCore_UpdateHpTextFast(self, hp)
    if not self or not self.unit or not self.hpText then return end
    local unit = self.unit
    local conf = self.cachedConfig

    if self.hpText then
        local wantHP = (self.showHPText ~= false and hp)
        MSUF_SetShown(self.hpText, wantHP)
        if self.hpTextPct then
            MSUF_SetShown(self.hpTextPct, false)
        end
    end

    if self.showHPText ~= false and hp then
        local hpStr = MSUF_NumberToTextFast(hp)
        local hpPct = MSUF_GetUnitHealthPercent(unit)
        local hasPct = (type(hpPct) == "number")
        local g = MSUF_DB.general or {}
        local hpMode = g.hpTextMode or "FULL_PLUS_PERCENT"
        local sep = g.hpTextSeparator
        if sep == nil then
            sep = ""
        end
        if sep == "" then
            sep = " "
        else
            sep = " " .. sep .. " "
        end

        local spacerOn = (conf and conf.hpTextSpacerEnabled == true) or (not conf and g.hpTextSpacerEnabled == true)
        local spacerX = (conf and tonumber(conf.hpTextSpacerX)) or (tonumber(g.hpTextSpacerX) or 0)

        local absorbSuffix = ""
        if g.showTotalAbsorbAmount and UnitGetTotalAbsorbs then
            if C_StringUtil and C_StringUtil.TruncateWhenZero then
                local ok, absorbText = pcall(function()
                    return C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(unit))
                end)
                if ok and absorbText then
                    absorbSuffix = " " .. absorbText .. ""
                end
            else
                -- Secret-safe fallback: never compare absorb numbers in Lua (may be "secret").
                local absorbValue = UnitGetTotalAbsorbs(unit)
                if absorbValue ~= nil then
                    local abbr = _G.AbbreviateLargeNumbers or _G.ShortenNumber or _G.AbbreviateNumbers
                    if abbr then
                        local ok, txt = pcall(abbr, absorbValue)
                        if ok and txt and txt ~= "0" and txt ~= "0.0" then
                            absorbSuffix = " (" .. txt .. ")"
                        end
                    else
                        local ok, s = pcall(tostring, absorbValue)
                        if ok and s and s ~= "0" and s ~= "0.0" then
                            absorbSuffix = " (" .. s .. ")"
                        end
                    end
                end
            end
        end

        if hasPct then
            if spacerOn and spacerX > 0 and (hpMode == "FULL_PLUS_PERCENT" or hpMode == "PERCENT_PLUS_FULL") and self.hpTextPct then
                MSUF_SetFormattedTextIfChanged(self.hpText, "%s%s", hpStr or "", absorbSuffix)
                MSUF_SetFormattedTextIfChanged(self.hpTextPct, "%.1f%%%s", hpPct, "")
                MSUF_SetShown(self.hpTextPct, true)
            else
                if hpMode == "FULL_ONLY" then
                    MSUF_SetFormattedTextIfChanged(self.hpText, "%s%s", hpStr or "", absorbSuffix)
                elseif hpMode == "PERCENT_ONLY" then
                    MSUF_SetFormattedTextIfChanged(self.hpText, "%.1f%%%s", hpPct, absorbSuffix)
                elseif hpMode == "PERCENT_PLUS_FULL" then
                    MSUF_SetFormattedTextIfChanged(self.hpText, "%.1f%%%s%s%s", hpPct, sep, hpStr or "", absorbSuffix)
                else
                    MSUF_SetFormattedTextIfChanged(self.hpText, "%s%s%.1f%%%s", hpStr or "", sep, hpPct, absorbSuffix)
                end
                if self.hpTextPct then
                    MSUF_SetTextIfChanged(self.hpTextPct, "")
                    self.hpTextPct:Hide()
                end
            end
        else
            MSUF_SetFormattedTextIfChanged(self.hpText, "%s%s", hpStr or "", absorbSuffix)
            if self.hpTextPct then
                MSUF_SetTextIfChanged(self.hpTextPct, "")
                self.hpTextPct:Hide()
            end
        end
    else
        if self.hpText then
            MSUF_SetTextIfChanged(self.hpText, "")
        end
        if self.hpTextPct then
            MSUF_SetTextIfChanged(self.hpTextPct, "")
            self.hpTextPct:Hide()
        end
    end
end

-- Boss Test Mode preview helper: render HP text using the real HP text mode + spacer behavior.
-- (Boss units often don't exist out of combat, so we need a safe dummy renderer.)
function _G.MSUF_ApplyBossTestHpPreviewText(self, conf)
    if not self or not self.hpText then return end

    local show = (self.showHPText ~= false)
    if not show then
        MSUF_SetTextIfChanged(self.hpText, "")
        if self.hpTextPct then
            MSUF_SetTextIfChanged(self.hpTextPct, "")
            self.hpTextPct:Hide()
        end
        return
    end

    local g = (MSUF_DB and MSUF_DB.general) or {}
    local hpMode = g.hpTextMode or "FULL_PLUS_PERCENT"

    local sep = g.hpTextSeparator
    if sep == nil then sep = "" end
    if sep == "" then
        sep = " "
    else
        sep = " " .. sep .. " "
    end

    local spacerOn = (conf and conf.hpTextSpacerEnabled == true) or (not conf and g.hpTextSpacerEnabled == true)
    local spacerX  = (conf and tonumber(conf.hpTextSpacerX)) or (tonumber(g.hpTextSpacerX) or 0)

    -- Dummy values that look sane in preview.
    local hp = 750000
    local hpPct = 75.0

    local hpStr = MSUF_NumberToTextFast(hp)

    -- Default: hide pct text unless spacer mode actually uses it.
    if self.hpTextPct then
        MSUF_SetShown(self.hpTextPct, false)
    end

    if spacerOn and spacerX > 0 and (hpMode == "FULL_PLUS_PERCENT" or hpMode == "PERCENT_PLUS_FULL") and self.hpTextPct then
        MSUF_SetFormattedTextIfChanged(self.hpText, "%s", hpStr or "")
        MSUF_SetFormattedTextIfChanged(self.hpTextPct, "%.1f%%", hpPct)
        MSUF_SetShown(self.hpTextPct, true)
    else
        if hpMode == "FULL_ONLY" then
            MSUF_SetFormattedTextIfChanged(self.hpText, "%s", hpStr or "")
        elseif hpMode == "PERCENT_ONLY" then
            MSUF_SetFormattedTextIfChanged(self.hpText, "%.1f%%", hpPct)
        elseif hpMode == "PERCENT_PLUS_FULL" then
            MSUF_SetFormattedTextIfChanged(self.hpText, "%.1f%%%s%s", hpPct, sep, hpStr or "")
        else
            MSUF_SetFormattedTextIfChanged(self.hpText, "%s%s%.1f%%", hpStr or "", sep, hpPct)
        end
        if self.hpTextPct then
            MSUF_SetTextIfChanged(self.hpTextPct, "")
            self.hpTextPct:Hide()
        end
    end
end

function _G.MSUF_UFCore_UpdatePowerTextFast(self)
    if not self or not self.unit or not self.powerText then return end
    local unit = self.unit
    local showPower = self.showPowerText
    if showPower == nil then
        showPower = true
    end
    if not showPower then
        MSUF_SetTextIfChanged(self.powerText, "")
        self.powerText:Hide()
        return
    end

    local gPower = MSUF_DB and MSUF_DB.general or {}
    local colorPowerTextByType = (gPower.colorPowerTextByType == true)
    local pMode  = gPower.powerTextMode or "FULL_SLASH_MAX"
    local powerSep = gPower.powerTextSeparator
    if powerSep == nil then
        powerSep = gPower.hpTextSeparator
    end
    if powerSep == nil then
        powerSep = ""
    end
    if powerSep == "" then
        powerSep = " "
    else
        powerSep = " " .. powerSep .. " "
    end

    MSUF_EnsureUnitFlags(self)
    local isPlayer = self._msufIsPlayer
    local isFocus  = self._msufIsFocus


    -- Optional: color PowerText by current power type.
    -- Re-apply if some other code path overwrote the color (prevents blinking/conflicts).
    local function MSUF_ApplyPowerTextColorByType()
        if not colorPowerTextByType then return end
        if not (UnitPowerType and self.powerText) then return end

        local okPT, pType, pTok = pcall(UnitPowerType, unit)
        if not okPT then return end

        local pr, pg, pb
        if type(MSUF_GetResolvedPowerColor) == "function" then
            pr, pg, pb = MSUF_GetResolvedPowerColor(pType, pTok)
        end
        if not pr then return end

        local doApply = (self._msufPTColorByPower ~= true) or (self._msufPTColorType ~= pType) or (self._msufPTColorTok ~= pTok)
        if not doApply and self.powerText.GetTextColor then
            local cr, cg, cb = self.powerText:GetTextColor()
            if type(cr) == "number" and type(cg) == "number" and type(cb) == "number" then
                if (math.abs(cr - pr) > 0.01) or (math.abs(cg - pg) > 0.01) or (math.abs(cb - pb) > 0.01) then
                    doApply = true
                end
            end
        end

        if doApply then
            self.powerText:SetTextColor(pr, pg, pb, 1)
            self._msufPTColorByPower = true
            self._msufPTColorType = pType
            self._msufPTColorTok = pTok
            -- Keep the font-cache stamp in sync so UpdateAllFonts doesn't fight us.
            self.powerText._msufColorStamp = tostring(pr) .. "|" .. tostring(pg) .. "|" .. tostring(pb)
        end
    end


    if isPlayer or isFocus or UnitIsPlayer(unit) then
        local curText, maxText
        local okCur, curValue = pcall(UnitPower, unit)
        if okCur and curValue ~= nil then
            if AbbreviateLargeNumbers then
                curText = AbbreviateLargeNumbers(curValue)
            else
                curText = tostring(curValue)
            end
        end
        local okMax, maxValue = pcall(UnitPowerMax, unit)
        if okMax and maxValue ~= nil then
            if AbbreviateLargeNumbers then
                maxText = AbbreviateLargeNumbers(maxValue)
            else
                maxText = tostring(maxValue)
            end
        end
        local powerPct = MSUF_GetUnitPowerPercent(unit)
        local hasPowerPct = (type(powerPct) == "number")
        if pMode == "FULL_ONLY" then
            MSUF_SetTextIfChanged(self.powerText, curText or "")
        elseif pMode == "PERCENT_ONLY" then
            if hasPowerPct then
                MSUF_SetFormattedTextIfChanged(self.powerText, "%.1f%%", powerPct)
            else
                MSUF_SetTextIfChanged(self.powerText, curText or "")
            end
        elseif pMode == "FULL_PLUS_PERCENT" then
            if hasPowerPct then
                MSUF_SetFormattedTextIfChanged(self.powerText, "%s%s%.1f%%", curText or "", powerSep, powerPct)
            else
                MSUF_SetTextIfChanged(self.powerText, curText or "")
            end
        elseif pMode == "PERCENT_PLUS_FULL" then
            if hasPowerPct then
                MSUF_SetFormattedTextIfChanged(self.powerText, "%.1f%%%s%s", powerPct, powerSep, curText or "")
            else
                MSUF_SetTextIfChanged(self.powerText, curText or "")
            end
        else
            if curText and maxText then
                MSUF_SetFormattedTextIfChanged(self.powerText, "%s%s%s", curText, powerSep, maxText)
            elseif curText then
                MSUF_SetTextIfChanged(self.powerText, curText)
            elseif maxText then
                MSUF_SetTextIfChanged(self.powerText, maxText)
            else
                MSUF_SetTextIfChanged(self.powerText, "")
            end
        end
        MSUF_ApplyPowerTextColorByType()
        self.powerText:Show()
    elseif self.isBoss and C_StringUtil and C_StringUtil.TruncateWhenZero then
        local okCur, curText2 = pcall(function()
            return C_StringUtil.TruncateWhenZero(UnitPower(unit))
        end)
        local okMax, maxText2 = pcall(function()
            return C_StringUtil.TruncateWhenZero(UnitPowerMax(unit))
        end)
        local finalText
        if okCur and curText2 and okMax and maxText2 then
            finalText = curText2 .. powerSep .. maxText2
        elseif okCur and curText2 then
            finalText = curText2
        elseif okMax and maxText2 then
            finalText = maxText2
        end
        if finalText then
            MSUF_SetTextIfChanged(self.powerText, finalText)
            MSUF_ApplyPowerTextColorByType()
            self.powerText:Show()
        else
            MSUF_SetTextIfChanged(self.powerText, "")
            self.powerText:Hide()
        end
    else
        MSUF_SetTextIfChanged(self.powerText, "")
        self.powerText:Hide()
    end
end

function _G.MSUF_UFCore_UpdatePowerBarFast(self)
    if not self or not self.unit then return end
    local bar = self.targetPowerBar
    if not bar then return end
    local unit = self.unit
    local barsConf = (MSUF_DB and MSUF_DB.bars) or {}

    if not UnitExists(unit) then
        bar:SetScript("OnUpdate", nil)
        bar:Hide()
        MSUF_ResetBarZero(bar, true)
        return
    end

    if not MSUF_IsTargetLikeFrame(self) then
        bar:SetScript("OnUpdate", nil)
        bar:Hide()
        MSUF_ResetBarZero(bar, true)
        return
    end

    MSUF_EnsureUnitFlags(self)
    local hideForUnit = false
    if self._msufIsPlayer then
        hideForUnit = (barsConf.showPlayerPowerBar == false)
    elseif self._msufIsFocus then
        hideForUnit = (barsConf.showFocusPowerBar == false)
    elseif self._msufIsTarget then
        hideForUnit = (barsConf.showTargetPowerBar == false)
    elseif self.isBoss then
        hideForUnit = (barsConf.showBossPowerBar == false)
    end

    if hideForUnit then
        bar:SetScript("OnUpdate", nil)
        bar:Hide()
        MSUF_ResetBarZero(bar, true)
        return
    end

    local pType = UnitPowerType(unit)
    local cur   = UnitPower(unit, pType)
    local max   = UnitPowerMax(unit, pType)
    if max ~= nil and cur ~= nil then
        local _, pTok = UnitPowerType(unit)
        local pr, pg, pb = MSUF_GetPowerBarColor(pType, pTok)
        if not pr then
            local col = PowerBarColor[pType] or { r = 0.8, g = 0.8, b = 0.8 }
            pr, pg, pb = col.r, col.g, col.b
        end
        bar:SetStatusBarColor(pr, pg, pb)
        if self.powerGradients then
            MSUF_ApplyPowerGradient(self)
        elseif self.powerGradient then
            MSUF_ApplyPowerGradient(self.powerGradient)
        end
        bar:SetMinMaxValues(0, max)
        bar:SetScript("OnUpdate", nil)
        MSUF_SetBarValue(bar, cur)
        bar:Show()
    else
        bar:SetScript("OnUpdate", nil)
        bar:Hide()
        MSUF_ResetBarZero(bar, true)
    end
end

local function MSUF_ClearHpTextPct(self)
    if self.hpTextPct then
        MSUF_SetTextIfChanged(self.hpTextPct, "")
        self.hpTextPct:Hide()
    end
end

local function MSUF_ClearUnitFrameState(self, clearAbsorbs)
    MSUF_ResetBarZero(self.hpBar)
    if clearAbsorbs then
        MSUF_ResetBarZero(self.absorbBar, true)
        MSUF_ResetBarZero(self.healAbsorbBar, true)
    end
    if self.nameText then MSUF_SetTextIfChanged(self.nameText, "") end
    MSUF_ClearText(self.levelText, true)
    if self.hpText then MSUF_SetTextIfChanged(self.hpText, "") end
    MSUF_ClearText(self.powerText, true)
end

local function MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus)
    local pbBar = self and self.targetPowerBar
    if not pbBar then return false end
    local function Hide()
        pbBar:SetScript("OnUpdate", nil)
        pbBar:Hide()
        return true
    end
    if not MSUF_IsTargetLikeFrame(self) then
        return Hide()
    end
    local hideForUnitPB = false
    if isPlayer then
        if barsConf.showPlayerPowerBar == false then hideForUnitPB = true end
    elseif isFocus then
        if barsConf.showFocusPowerBar == false then hideForUnitPB = true end
    elseif isTarget then
        if barsConf.showTargetPowerBar == false then hideForUnitPB = true end
    elseif self.isBoss then
        if barsConf.showBossPowerBar == false then hideForUnitPB = true end
    end
    if hideForUnitPB then
        return Hide()
    end
    local okPT, pTypePB, pTokPB = MSUF_FastCall(UnitPowerType, unit)
    if not okPT then
        return Hide()
    end
    local okPct, pctPB
    if CurveConstants and CurveConstants.ScaleTo100 then
        okPct, pctPB = MSUF_FastCall(UnitPowerPercent, unit, pTypePB, false, CurveConstants.ScaleTo100)
    else
        okPct, pctPB = MSUF_FastCall(UnitPowerPercent, unit, pTypePB, false, true)
    end
    if not okPct then
        return Hide()
    end
    local pr, pg, pb = MSUF_GetPowerBarColor(pTypePB, pTokPB)
    if not pr then
        local colPB = PowerBarColor[pTypePB] or { r = 0.8, g = 0.8, b = 0.8 }
        pr, pg, pb = colPB.r, colPB.g, colPB.b
    end
    pbBar:SetStatusBarColor(pr, pg, pb)
    if self.powerGradients then
        MSUF_ApplyPowerGradient(self)
    elseif self.powerGradient then
        MSUF_ApplyPowerGradient(self.powerGradient)
    end
    if self.powerGradients then
        MSUF_ApplyPowerGradient(self)
    elseif self.powerGradient then
        MSUF_ApplyPowerGradient(self.powerGradient)
    end
    MSUF_SetBarMinMax(pbBar, 0, 100)
    pbBar:SetScript("OnUpdate", nil)
    MSUF_SetBarValue(pbBar, pctPB, true)
    pbBar:Show()
    return true
end

-- Table-driven UpdateSimpleUnitFrame steps (kept local; preserve call ordering/side-effects)
local function MSUF_UFStep_BasicHealth(self, unit)
        local maxHP = UnitHealthMax(unit)
        if maxHP then
            self.hpBar:SetMinMaxValues(0, maxHP)
        end
        local hp = UnitHealth(unit)
        if hp then
            MSUF_SetBarValue(self.hpBar, hp)
        end
        if self.absorbBar then
            MSUF_UpdateAbsorbBar(self, unit, maxHP)
        end
        if self.healAbsorbBar then
            MSUF_UpdateHealAbsorbBar(self, unit, maxHP)
        end
    return hp
end

local function MSUF_UFStep_HeavyVisual(self, unit, key)
        -- 3f: Throttle heavy visual work (bar color + gradients + background) to reduce CPU spikes.
        -- Safe: HP values/visibility still update every tick; only expensive recolor/retexture is throttled.
        local doHeavyVisual = true
        local forceHeavy = false
        local tokenFlags = _G.MSUF_UnitTokenChanged
        if tokenFlags and key and tokenFlags[key] then
            tokenFlags[key] = nil
            forceHeavy = true
        end
        local now = GetTime()
        if not forceHeavy then
            local nextAt = self._msufHeavyVisualNextAt or 0
            if now < nextAt then
                doHeavyVisual = false
            else
                self._msufHeavyVisualNextAt = now + 0.05 -- ~20 Hz
            end
        else
            self._msufHeavyVisualNextAt = now
        end
        if doHeavyVisual then
        local g = (MSUF_DB and MSUF_DB.general) or {}

        -- Bar mode (authoritative): "dark" | "class" | "unified"
        -- Backwards compatibility: if barMode is missing/invalid, derive it from legacy flags.
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
            mode = (g.useClassColors and "class") or (g.darkMode and "dark") or "dark"
        end

        -- Dark tone (used only when mode == "dark")
        local darkR, darkG, darkB = 0, 0, 0
        local _gray = g.darkBarGray
        if type(_gray) == "number" then
            if _gray < 0 then _gray = 0 end
            if _gray > 1 then _gray = 1 end
            darkR, darkG, darkB = _gray, _gray, _gray
        else
            local toneKey = g.darkBarTone or "black"
            local tone = MSUF_DARK_TONES and MSUF_DARK_TONES[toneKey]
            if tone then
                darkR, darkG, darkB = tone[1], tone[2], tone[3]
            end
        end

        local barR, barG, barB

        if mode == "dark" then
            barR, barG, barB = darkR, darkG, darkB

        elseif mode == "unified" then
            -- One color for ALL frames (player + NPCs). Stored in MSUF_DB.general.unifiedBarR/G/B.
            local ur, ug, ub = g.unifiedBarR, g.unifiedBarG, g.unifiedBarB
            if type(ur) ~= "number" then ur = 0.10 end
            if type(ug) ~= "number" then ug = 0.60 end
            if type(ub) ~= "number" then ub = 0.90 end
            if ur < 0 then ur = 0 elseif ur > 1 then ur = 1 end
            if ug < 0 then ug = 0 elseif ug > 1 then ug = 1 end
            if ub < 0 then ub = 0 elseif ub > 1 then ub = 1 end
            barR, barG, barB = ur, ug, ub

        else
            -- mode == "class" (default): players = class, NPCs = reaction (friendly/neutral/enemy/dead)
            local isPlayerUnit = UnitIsPlayer(unit)
            if isPlayerUnit then
                local _, class = UnitClass(unit)
                barR, barG, barB = MSUF_GetClassBarColor(class)
            else
                if UnitIsDeadOrGhost(unit) then
                    barR, barG, barB = MSUF_GetNPCReactionColor("dead")
                else
                    local reaction = UnitReaction("player", unit)
                    if reaction and reaction >= 5 then
                        barR, barG, barB = MSUF_GetNPCReactionColor("friendly")
                    elseif reaction == 4 then
                        barR, barG, barB = MSUF_GetNPCReactionColor("neutral")
                    else
                        barR, barG, barB = MSUF_GetNPCReactionColor("enemy")
                    end
                end
            end
        end

        -- Pet frame color override (foreground HP bar) - only when using Class mode.
        -- Stored via Colors menu under MSUF_DB.general.petFrameColorR/G/B.
        if mode == "class" and self._msufIsPet then
            local pr, pg, pb = g.petFrameColorR, g.petFrameColorG, g.petFrameColorB
            if type(pr) == "number" and type(pg) == "number" and type(pb) == "number" then
                if pr < 0 then pr = 0 elseif pr > 1 then pr = 1 end
                if pg < 0 then pg = 0 elseif pg > 1 then pg = 1 end
                if pb < 0 then pb = 0 elseif pb > 1 then pb = 1 end
                barR, barG, barB = pr, pg, pb
            end
        end
        self.hpBar:SetStatusBarColor(barR, barG, barB, 1)
        if self.hpGradients then
            MSUF_ApplyHPGradient(self)
        elseif self.hpGradient then
            MSUF_ApplyHPGradient(self.hpGradient)
        end
        if self.bg then
            MSUF_ApplyBarBackgroundVisual(self)
        end
        end
end

local function MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus)
  -- Fast-path sync: when the power bar is already visible, we can update value/color
  -- without running the full UpdatePowerBarFast (which may re-anchor/layout).
  local pb = self.targetPowerBar or self.powerBar
  if not (pb and pb.IsShown and pb:IsShown()) then
    return false
  end

  if self.isBoss then
    if barsConf.showBossPowerBar == false then
      return false
    end
  elseif isPlayer then
    if barsConf.showPlayerPowerBar == false then
      return false
    end
  elseif isTarget then
    if barsConf.showTargetPowerBar == false then
      return false
    end
  elseif isFocus then
    if barsConf.showFocusPowerBar == false then
      return false
    end
  end

  if MSUF_SyncTargetPowerBar(self, unit, barsConf, isPlayer, isTarget, isFocus) then
    return true
  end

  return false
end

local function MSUF_UFStep_Border(self)
        -- Bar outline/border is a rare visual: queue it once-per-frame to avoid doing it on every update tick.
        do
            if self.border then
                self.border:Hide()
            end
            local thickness, stamp = MSUF_GetDesiredBarBorderThicknessAndStamp()
            local pb = self.targetPowerBar
            local bottomIsPower = (pb and pb.IsShown and pb:IsShown()) and true or false

            local need = false
            if self._msufBarBorderStamp ~= stamp then
                self._msufBarBorderStamp = stamp
                need = true
            end
            if self._msufBarOutlineThickness ~= thickness then
                need = true
            end
            if self._msufBarOutlineBottomIsPower ~= bottomIsPower then
                need = true
            end

            if need and type(_G.MSUF_QueueUnitframeVisual) == "function" then
                _G.MSUF_QueueUnitframeVisual(self)
            end
        end
end

local function MSUF_UFStep_NameLevelLeaderRaid(self, unit, conf, g)
    local name = UnitName(unit)
    if self.showName ~= false and name then
        MSUF_SetTextIfChanged(self.nameText, name)
        if self.nameText and self.nameText.Show then
            self.nameText:Show()
        end
    else
        MSUF_SetTextIfChanged(self.nameText, "")
        if self.nameText and self.nameText.Hide then
            self.nameText:Hide()
        end
    end
    if self.levelText then
        local showLevel = true
        if conf and conf.showLevelIndicator == false then
            showLevel = false
        end
        if showLevel and unit and UnitExists(unit) then
            local lvlText = MSUF_GetUnitLevelText(unit)
            MSUF_SetTextIfChanged(self.levelText, lvlText)
            if lvlText ~= "" then
                self.levelText:Show()
            else
                self.levelText:Hide()
            end
        else
            MSUF_SetTextIfChanged(self.levelText, "")
            self.levelText:Hide()
        end
        MSUF_ClampNameWidth(self, conf)
    end
        MSUF_UpdateNameColor(self)
        if self.leaderIcon then
            local showAllowed = true
            if conf and conf.showLeaderIcon ~= nil then
                showAllowed = (conf.showLeaderIcon ~= false)
            else
                showAllowed = (g.showLeaderIcon ~= false)
            end
    if not showAllowed then
                self.leaderIcon:Hide()
            else
                local isLeader = (UnitIsGroupLeader and UnitIsGroupLeader(unit)) and true or false
                local isAssist = (not isLeader) and (UnitIsGroupAssistant and UnitIsGroupAssistant(unit)) and true or false
                if isLeader then
                    if self.leaderIcon.SetTexture then
                        self.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                    end
                    self.leaderIcon:Show()
                elseif isAssist then
                    if self.leaderIcon.SetTexture then
                        self.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
                    end
                    self.leaderIcon:Show()
                else
                    self.leaderIcon:Hide()
                end
            end
        end
        if self.leaderIcon and _G.MSUF_ApplyLeaderIconLayout then
            _G.MSUF_ApplyLeaderIconLayout(self)
        end
        if self.raidMarkerIcon then
    local show = true
            if conf and conf.showRaidMarker ~= nil then
                show = (conf.showRaidMarker ~= false)
            else
                show = (g.showRaidMarker ~= false)
            end
            if not show then
                self.raidMarkerIcon:Hide()
            else
    local idx = (GetRaidTargetIndex and GetRaidTargetIndex(unit)) or nil
                -- Midnight/Beta can return idx as a "secret value"; never compare / do math on it.
                if addon and addon.EditModeLib and addon.EditModeLib.IsInEditMode and addon.EditModeLib:IsInEditMode() then
                    idx = idx or 8 -- stable preview while editing
                end
                if idx and SetRaidTargetIconTexture then
                    SetRaidTargetIconTexture(self.raidMarkerIcon, idx)
                    self.raidMarkerIcon:Show()
                else
                    self.raidMarkerIcon:Hide()
                end
            end
        end
    if self.raidMarkerIcon and _G.MSUF_ApplyRaidMarkerLayout then
        _G.MSUF_ApplyRaidMarkerLayout(self)
    end
end

local function MSUF_UFStep_Finalize(self, hp, didPowerBarSync)
    _G.MSUF_UFCore_UpdateHpTextFast(self, hp)
    _G.MSUF_UFCore_UpdatePowerTextFast(self)
    if not didPowerBarSync then
        _G.MSUF_UFCore_UpdatePowerBarFast(self)
    end
    MSUF_UpdateStatusIndicatorForFrame(self)
end

function UpdateSimpleUnitFrame(self)
	    if (not MSUF_DB) and type(EnsureDB) == "function" then
	        EnsureDB()
	    end
	    local db = MSUF_DB
	    local g = (db and db.general) or {}
	    local barsConf = (db and db.bars) or {}
    local unit   = self.unit
    MSUF_EnsureUnitFlags(self)
    local isPlayer = self._msufIsPlayer
    local isTarget = self._msufIsTarget
    local isFocus  = self._msufIsFocus
    local isPet    = self._msufIsPet
    local isToT    = self._msufIsToT
    local unitValid = (type(unit) == "string" and unit ~= "") and true or false
    local exists = (unitValid and UnitExists and UnitExists(unit)) and true or false
    local key = self.msufConfigKey
    if not key then
        key = GetConfigKeyForUnit(unit)
        self.msufConfigKey = key
    end
    local conf = self.cachedConfig
    if not conf then
        conf = (key and db and db[key]) or nil
        self.cachedConfig = conf
    end
    if conf and conf.enabled == false then
        if not InCombatLockdown() then
            self:Hide()
            if self.portrait then self.portrait:Hide() end
            if self.isFocus and MSUF_ReanchorFocusCastBar then
                MSUF_ReanchorFocusCastBar()
            end
        end
        MSUF_ClearUnitFrameState(self, true)
        if self.leaderIcon then
            self.leaderIcon:Hide()
        end
        if self.raidMarkerIcon then
            self.raidMarkerIcon:Hide()
        end
        return
    end

-- Live-sync text visibility flags every update (prevents "needs reload" for toggles)
if conf then
    local sn = (conf.showName  ~= false)
    local sh = (conf.showHP    ~= false)
    local sp = (conf.showPower ~= false)
    self.showName      = sn
    self.showHPText    = sh
    self.showPowerText = sp
end

-- Portrait state: mark dirty when unit presence toggles (texture update is event-driven + on acquire)
        if self.portrait then
    if exists then
        if not self._msufHadUnit then
            self._msufHadUnit = true
            self._msufPortraitDirty = true
            self._msufPortraitNextAt = 0
        end
    else
        if self._msufHadUnit then
            self._msufHadUnit = nil
            self._msufPortraitDirty = true
            self._msufPortraitNextAt = 0
        end
    end
end

    local didPowerBarSync = false
    if self.isBoss and MSUF_BossTestMode then
        if not InCombatLockdown() then
            self:Show()
            _G.MSUF_ApplyUnitAlpha(self, key)
        end
    if self.bg then
        MSUF_ApplyBarBackgroundVisual(self)
    end
               if self.targetPowerBar then
            if (barsConf.showBossPowerBar == false) then
                self.targetPowerBar:SetScript("OnUpdate", nil)
                self.targetPowerBar:Hide()
                MSUF_ResetBarZero(self.targetPowerBar, true)
            else
                self.targetPowerBar:SetMinMaxValues(0, 100)
                MSUF_SetBarValue(self.targetPowerBar, 40, false)
                self.targetPowerBar.MSUF_lastValue = 40
                do
                    local tok = "MANA"
                    local pr, pg, pb = MSUF_GetPowerBarColor(nil, tok)
                    if not pr then pr, pg, pb = 0.6, 0.2, 1.0 end
                    self.targetPowerBar:SetStatusBarColor(pr, pg, pb)
                    if self.powerGradients then
                        MSUF_ApplyPowerGradient(self)
                    elseif self.powerGradient then
                        MSUF_ApplyPowerGradient(self.powerGradient)
                    end
                    if self.powerGradients then
                        MSUF_ApplyPowerGradient(self)
                    elseif self.powerGradient then
                        MSUF_ApplyPowerGradient(self.powerGradient)
                    end
                end
                self.targetPowerBar:Show()
            end
        end
        if self.nameText then
            local show = (self.showName ~= false)
            if show then
                local idx
                if type(unit) == "string" then
                    idx = unit:match("boss(%d+)")
                end
                if idx then
                    MSUF_SetTextIfChanged(self.nameText, "Test Boss " .. idx)
                else
                    MSUF_SetTextIfChanged(self.nameText, "Test Boss")
                end
            else
                MSUF_SetTextIfChanged(self.nameText, "")
            end
            MSUF_SetShown(self.nameText, show)
        end
        if self.levelText then
            local show = (self.showName ~= false)
            if show then
                MSUF_SetTextIfChanged(self.levelText, "??")
            else
                MSUF_SetTextIfChanged(self.levelText, "")
            end
            MSUF_SetShown(self.levelText, show)
            MSUF_ClampNameWidth(self, conf)
        end
        if self.hpText then
    local show = (self.showHPText ~= false)
    if show then
        if type(_G.MSUF_ApplyBossTestHpPreviewText) == "function" then
            _G.MSUF_ApplyBossTestHpPreviewText(self, conf)
        else
            MSUF_SetTextIfChanged(self.hpText, "75")
            MSUF_ClearHpTextPct(self)
        end
    else
        MSUF_SetTextIfChanged(self.hpText, "")
        MSUF_ClearHpTextPct(self)
    end
    MSUF_SetShown(self.hpText, show)
end
if self.powerText then
            local showPower = self.showPowerText
            if showPower == nil then
                showPower = true
            end
            if showPower then
                MSUF_SetTextIfChanged(self.powerText, "40 / 100")
            else
                MSUF_SetTextIfChanged(self.powerText, "")
            end
            MSUF_SetShown(self.powerText, showPower)
        end
        return
    end
if self.isBoss then
    if not exists then
        if self._msufNoUnitCleared and (self.GetAlpha and self:GetAlpha() or 0) <= 0.01 then
            return
        end
        self:SetAlpha(0)
        MSUF_ClearUnitFrameState(self, false)
        if self.portrait then
            self.portrait:Hide()
        end
        self._msufNoUnitCleared = true
        return
    else
        -- Boss has a unit: clear stale "no unit" marker; shared path below handles alpha + portrait.
        self._msufNoUnitCleared = nil
    end
end

-- Unit existence gate: bail out BEFORE any heavy work (portrait, colors, auras, etc.)
if not exists then
    if unit ~= "player" and self._msufNoUnitCleared and (self.GetAlpha and self:GetAlpha() or 0) <= 0.01 then
        return
    end
    if unit ~= "player" then
        self:SetAlpha(0)
    end
    if self.portrait then self.portrait:Hide() end
    MSUF_ClearUnitFrameState(self, true)
    self._msufNoUnitCleared = true
    return
else
    _G.MSUF_ApplyUnitAlpha(self, key)
    self._msufNoUnitCleared = nil
    MSUF_UpdatePortraitIfNeeded(self, unit, conf, exists)
end
    -- Step pipeline (table-driven)
    local hp = MSUF_UFStep_BasicHealth(self, unit)
    MSUF_UFStep_HeavyVisual(self, unit, key)
    if MSUF_UFStep_SyncTargetPower(self, unit, barsConf, isPlayer, isTarget, isFocus) then
        didPowerBarSync = true
    end
    MSUF_UFStep_Border(self)
    MSUF_UFStep_NameLevelLeaderRaid(self, unit, conf, g)
    MSUF_UFStep_Finalize(self, hp, didPowerBarSync)

    -- IMPORTANT: layered alpha uses per-texture alpha, which visual steps reset.
    -- Re-apply AFTER the full visual pipeline so alpha persists across any live updates.
    if conf and conf.alphaExcludeTextPortrait == true then
        _G.MSUF_ApplyUnitAlpha(self, key)
    end
end

local MSUF_ApplyRareVisuals

MSUF_ApplyRareVisuals = function(self)
    if not self or not self.unit then return end

    -- Always hide legacy border if it exists (we use the outline frame now)
    if self.border then
        self.border:Hide()
    end

    local thickness = 0
    if type(MSUF_GetDesiredBarBorderThicknessAndStamp) == "function" then
        thickness = select(1, MSUF_GetDesiredBarBorderThicknessAndStamp())
    end
    thickness = tonumber(thickness) or 0

    local o = self._msufBarOutline
    if thickness <= 0 then
        if o then
            if o.top then o.top:Hide() end
            if o.bottom then o.bottom:Hide() end
            if o.left then o.left:Hide() end
            if o.right then o.right:Hide() end
            if o.tl then o.tl:Hide() end
            if o.tr then o.tr:Hide() end
            if o.bl then o.bl:Hide() end
            if o.br then o.br:Hide() end
            if o.frame then o.frame:Hide() end
        end
        self._msufBarOutlineThickness = 0
        self._msufBarOutlineBottomIsPower = false
        return
    end

    if not o then
        o = {}
        self._msufBarOutline = o
    end

    if o.top then o.top:Hide() end
    if o.bottom then o.bottom:Hide() end
    if o.left then o.left:Hide() end
    if o.right then o.right:Hide() end
    if o.tl then o.tl:Hide() end
    if o.tr then o.tr:Hide() end
    if o.bl then o.bl:Hide() end
    if o.br then o.br:Hide() end

    if not o.frame then
        local template = (BackdropTemplateMixin and "BackdropTemplate") or nil
        local f = CreateFrame("Frame", nil, self, template)
        f:EnableMouse(false)
        f:SetFrameStrata(self:GetFrameStrata())
        local baseLevel = self:GetFrameLevel() + 2
        if self.hpBar and self.hpBar.GetFrameLevel then
            baseLevel = self.hpBar:GetFrameLevel() + 2
        end
        f:SetFrameLevel(baseLevel)
        o.frame = f
        o._msufLastEdgeSize = -1
    end

    local hb = self.hpBar
    local pb = self.targetPowerBar
    local pbWanted = (pb ~= nil) and (self._msufPowerBarReserved or (pb.IsShown and pb:IsShown()))
    local bottomBar = pbWanted and pb or hb
    local bottomIsPower = pbWanted and true or false

    local f = o.frame
    if o._msufLastEdgeSize ~= thickness then
        f:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8, edgeSize = thickness })
        f:SetBackdropBorderColor(0, 0, 0, 1)
        o._msufLastEdgeSize = thickness
        self._msufBarOutlineThickness = -1
    end

    if (self._msufBarOutlineThickness ~= thickness) or (self._msufBarOutlineBottomIsPower ~= (bottomIsPower and true or false)) then
        f:ClearAllPoints()
        if hb then
            f:SetPoint("TOPLEFT", hb, "TOPLEFT", -thickness, thickness)
        end
        if bottomBar then
            f:SetPoint("BOTTOMRIGHT", bottomBar, "BOTTOMRIGHT", thickness, -thickness)
        end
        self._msufBarOutlineThickness = thickness
        self._msufBarOutlineBottomIsPower = bottomIsPower and true or false
    end

    f:Show()
end

-- Export for the unitframe core (rare visuals are still applied out-of-band).
_G.MSUF_RefreshRareBarVisuals = MSUF_ApplyRareVisuals

-- One-shot resync helper for PLAYER_ENTERING_WORLD (no closures; keeps load-time smooth)
local function MSUF_PlayerEnteringWorldResync()
    local frames = _G.MSUF_UnitFrames or UnitFrames
    local f = frames and frames.player
    if not f then return end
    f._msufLastUpdate = 0
    f._msufPortraitDirty = true
    f._msufPortraitNextAt = 0

    if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
        _G.MSUF_RequestUnitframeUpdate(f, true, true, "PEW")
    elseif type(_G.MSUF_QueueUnitframeUpdate) == "function" then
        _G.MSUF_QueueUnitframeUpdate(f, true)
    elseif type(_G.UpdateSimpleUnitFrame) == "function" then
        _G.UpdateSimpleUnitFrame(f)
    end
end

local function MSUF_ApplyUnitFrameKey_Immediate(key)
    EnsureDB()
    local conf = MSUF_DB[key]
    if not conf then return end
    local function hideFrame(unit)
        local f = UnitFrames[unit]
        if f then
if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
    MSUF_ApplyUnitVisibilityDriver(f, false)
end
f:Hide()
        end
    end
    if conf.enabled == false then
        if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
            hideFrame(key)
        elseif key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                hideFrame("boss" .. i)
            end
        end
        return
    end
    local function applyToFrame(unit)
        local f = UnitFrames[unit]
        if not f then return end
        -- Performance: cache this config table on the frame (hot-path lookup avoidance)
        f.cachedConfig = conf
        if type(MSUF_ApplyUnitVisibilityDriver) == "function" then
            if f._msufVisibilityForced == "disabled" then
                f._msufVisibilityForced = nil
            end
            MSUF_ApplyUnitVisibilityDriver(f, (MSUF_UnitEditModeActive and true or false))
        end
        local w = tonumber(conf.width)  or (f.GetWidth and f:GetWidth())  or 275
        local h = tonumber(conf.height) or (f.GetHeight and f:GetHeight()) or 40
        conf.width, conf.height = w, h
        f:SetSize(w, h)
        if f.targetPowerBar then
            MSUF_ApplyPowerBarEmbedLayout(f)
        end
        local showName  = (conf.showName  ~= false)
        local showHP    = (conf.showHP    ~= false)
        local showPower = (conf.showPower ~= false)
        f.showName      = showName
        f.showHPText    = showHP
        f.showPowerText = showPower
        if unit == "player" then
            f:Show()
        elseif MSUF_UnitEditModeActive or (f.isBoss and MSUF_BossTestMode) then
            f:Show()
        else
            if UnitExists and UnitExists(unit) then
                f:Show()
            else
                f:Hide()
            end
        end
        PositionUnitFrame(f, unit)
        if f.portrait then
            MSUF_UpdateBossPortraitLayout(f, conf)
        end
        ApplyTextLayout(f, conf)
        MSUF_ClampNameWidth(f, conf)
        if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
            _G.MSUF_RequestUnitframeUpdate(f, true, true, "ApplyUnitKey")
        elseif type(_G.UpdateSimpleUnitFrame) == "function" then
            _G.UpdateSimpleUnitFrame(f)
        end
    end
    if key == "player" or key == "target" or key == "focus" or key == "targettarget" or key == "pet" then
        applyToFrame(key)
    elseif key == "boss" then
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            applyToFrame("boss" .. i)
        end
    end
    if key == "player" and MSUF_ReanchorPlayerCastBar then
        MSUF_ReanchorPlayerCastBar()
    elseif key == "target" and MSUF_ReanchorTargetCastBar then
        MSUF_ReanchorTargetCastBar()
    elseif key == "focus" and MSUF_ReanchorFocusCastBar then
        MSUF_ReanchorFocusCastBar()
    end
end
_G.MSUF_ApplyUnitFrameKey_Immediate = MSUF_ApplyUnitFrameKey_Immediate
_G.MSUF_UnitFrameApplyState = _G.MSUF_UnitFrameApplyState or { dirty = {}, queued = false }
function MSUF_MarkUnitFrameDirty(key)
    local st = _G.MSUF_UnitFrameApplyState
    st.dirty[key] = true
end
function MSUF_ApplyDirtyUnitFrames()
    local st = _G.MSUF_UnitFrameApplyState
    if not st or not st.dirty then return end
    if InCombatLockdown and InCombatLockdown() then
        st.queued = true
        return
    end
    for key in pairs(st.dirty) do
        if MSUF_ApplyUnitFrameKey_Immediate then
            MSUF_ApplyUnitFrameKey_Immediate(key)
        end
        st.dirty[key] = nil
    end
    st.queued = false
end
function MSUF_OnRegenEnabled_ApplyDirty(event)
    local st = _G.MSUF_UnitFrameApplyState
    if st and st.queued then
        MSUF_ApplyDirtyUnitFrames()
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY")
end

_G.MSUF_ApplyCommitState = _G.MSUF_ApplyCommitState or {
    pending = false,
    queued = false,
    fonts = false,
    bars = false,
    castbars = false,
    tickers = false,
    bossPreview = false,
}

local function MSUF_CommitApplyDirty_Scheduled()
    local st = _G.MSUF_ApplyCommitState
    if st then
        st.pending = false
    end
    if type(MSUF_CommitApplyDirty) == "function" then
        MSUF_CommitApplyDirty()
    end
end

local function MSUF_ScheduleApplyCommit()
    local st = _G.MSUF_ApplyCommitState
    if not st or st.pending then
        return
    end

    st.pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, MSUF_CommitApplyDirty_Scheduled)
    else
        st.pending = false
        MSUF_CommitApplyDirty_Scheduled()
    end
end

function MSUF_OnRegenEnabled_ApplyCommit(event)
    local st = _G.MSUF_ApplyCommitState
    if st and st.queued then
        st.queued = false
        if type(MSUF_CommitApplyDirty) == "function" then
            MSUF_CommitApplyDirty()
        end
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
end

function ApplySettingsForKey(key)
    if not key then return end
    MSUF_MarkUnitFrameDirty(key)

    local st = _G.MSUF_ApplyCommitState
    if key == "boss" then
        st.bossPreview = true
    end

    -- Per-key changes are usually just unitframe layout; keep it cheap.
    MSUF_ScheduleApplyCommit()
end

function ApplyAllSettings()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end

    -- Mark all unitframes dirty (coalesced apply)
    MSUF_MarkUnitFrameDirty("player")
    MSUF_MarkUnitFrameDirty("target")
    MSUF_MarkUnitFrameDirty("focus")
    MSUF_MarkUnitFrameDirty("targettarget")
    MSUF_MarkUnitFrameDirty("pet")
    MSUF_MarkUnitFrameDirty("boss")

    -- Expensive global refreshes; we only want them once per interaction burst.
    st.fonts = true
    st.bars = true
    st.castbars = true
    st.tickers = true
    st.bossPreview = true

    MSUF_ScheduleApplyCommit()
end

-- Keep immediate helper available for startup/critical paths
_G.MSUF_ApplySettingsForKey_Immediate = _G.MSUF_ApplySettingsForKey_Immediate or function(key)
    if not key then return end
    MSUF_MarkUnitFrameDirty(key)

    if InCombatLockdown and InCombatLockdown() then
        local stUF = _G.MSUF_UnitFrameApplyState
        if stUF then
            stUF.queued = true
        end
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY", MSUF_OnRegenEnabled_ApplyDirty)
        end
        return
    end

    if MSUF_ApplyUnitFrameKey_Immediate then
        MSUF_ApplyUnitFrameKey_Immediate(key)
    end

    local stUF = _G.MSUF_UnitFrameApplyState
    if stUF and stUF.dirty then
        stUF.dirty[key] = nil
    end
end



_G.MSUF_ApplyAllSettings_Immediate = _G.MSUF_ApplyAllSettings_Immediate or function()
    MSUF_ApplyUnitFrameKey_Immediate("player")
    MSUF_ApplyUnitFrameKey_Immediate("target")
    MSUF_ApplyUnitFrameKey_Immediate("focus")
    MSUF_ApplyUnitFrameKey_Immediate("targettarget")
    MSUF_ApplyUnitFrameKey_Immediate("pet")
    MSUF_ApplyUnitFrameKey_Immediate("boss")

    -- Use exported immediate refresh helpers when available (avoid wrappers / recursion).
    if type(_G.MSUF_UpdateAllFonts_Immediate) == "function" then
        _G.MSUF_UpdateAllFonts_Immediate()
    elseif type(_G.MSUF_UpdateAllFonts) == "function" then
        _G.MSUF_UpdateAllFonts()
    elseif type(UpdateAllFonts) == "function" then
        UpdateAllFonts()
    end

    if type(_G.MSUF_UpdateAllBarTextures_Immediate) == "function" then
        _G.MSUF_UpdateAllBarTextures_Immediate()
    elseif type(_G.MSUF_UpdateAllBarTextures) == "function" then
        _G.MSUF_UpdateAllBarTextures()
    elseif type(UpdateAllBarTextures) == "function" then
        UpdateAllBarTextures()
    end

    if type(_G.MSUF_UpdateCastbarTextures_Immediate) == "function" then
        _G.MSUF_UpdateCastbarTextures_Immediate()
    elseif type(MSUF_UpdateCastbarTextures) == "function" then
        MSUF_UpdateCastbarTextures()
    end

    if type(_G.MSUF_UpdateCastbarVisuals_Immediate) == "function" then
        _G.MSUF_UpdateCastbarVisuals_Immediate()
    elseif type(MSUF_UpdateCastbarVisuals) == "function" then
        MSUF_UpdateCastbarVisuals()
    end

    if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        pcall(_G.MSUF_UpdateBossCastbarPreview)
    end

    if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then
        _G.MSUF_EnsureStatusIndicatorTicker()
    end
    if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then
        _G.MSUF_EnsureToTFallbackTicker()
    end

    if _G.MSUF_UnitFrameApplyState and _G.MSUF_UnitFrameApplyState.dirty then
        for k in pairs(_G.MSUF_UnitFrameApplyState.dirty) do
            _G.MSUF_UnitFrameApplyState.dirty[k] = nil
        end
        _G.MSUF_UnitFrameApplyState.queued = false
    end
    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_DIRTY")
end

-- Central commit: runs once per burst, applies queued dirty work.
function MSUF_CommitApplyDirty()
    local st = _G.MSUF_ApplyCommitState
    if not st then return end

    if InCombatLockdown and InCombatLockdown() then
        st.queued = true
        if type(MSUF_EventBus_Register) == "function" then
            MSUF_EventBus_Register("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT", MSUF_OnRegenEnabled_ApplyCommit)
        end
        return
    end

    -- Unitframes (dirty-key apply)
    if type(MSUF_ApplyDirtyUnitFrames) == "function" then
        MSUF_ApplyDirtyUnitFrames()
    end

    -- Fonts / Bars / Castbars (coalesced)
    if st.fonts then
        if type(_G.MSUF_UpdateAllFonts_Immediate) == "function" then
            _G.MSUF_UpdateAllFonts_Immediate()
        elseif type(_G.MSUF_UpdateAllFonts) == "function" then
            _G.MSUF_UpdateAllFonts()
        end
    end

    if st.bars then
        if type(_G.MSUF_UpdateAllBarTextures_Immediate) == "function" then
            _G.MSUF_UpdateAllBarTextures_Immediate()
        elseif type(_G.MSUF_UpdateAllBarTextures) == "function" then
            _G.MSUF_UpdateAllBarTextures()
        elseif type(UpdateAllBarTextures) == "function" then
            UpdateAllBarTextures()
        end
    end

    if st.castbars then
        if type(_G.MSUF_UpdateCastbarTextures_Immediate) == "function" then
            _G.MSUF_UpdateCastbarTextures_Immediate()
        elseif type(MSUF_UpdateCastbarTextures) == "function" then
            MSUF_UpdateCastbarTextures()
        end

        if type(_G.MSUF_UpdateCastbarVisuals_Immediate) == "function" then
            _G.MSUF_UpdateCastbarVisuals_Immediate()
        elseif type(MSUF_UpdateCastbarVisuals) == "function" then
            MSUF_UpdateCastbarVisuals()
        end
    end

    if st.bossPreview then
        if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            pcall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            pcall(_G.MSUF_UpdateBossCastbarPreview)
        end
    end

    if st.tickers then
        if type(_G.MSUF_EnsureStatusIndicatorTicker) == "function" then
            _G.MSUF_EnsureStatusIndicatorTicker()
        end
        if type(_G.MSUF_EnsureToTFallbackTicker) == "function" then
            _G.MSUF_EnsureToTFallbackTicker()
        end
    end

    st.fonts = false
    st.bars = false
    st.castbars = false
    st.tickers = false
    st.bossPreview = false
    st.queued = false

    MSUF_EventBus_Unregister("PLAYER_REGEN_ENABLED", "MSUF_APPLY_COMMIT")
end

local function UpdateAllFonts()

    local path  = MSUF_GetFontPath()
    local flags = MSUF_GetFontFlags()
    EnsureDB()
    local g = MSUF_DB.general or {}
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    local baseSize       = g.fontSize or 14
    local globalNameSize = g.nameFontSize  or baseSize
    local globalHPSize   = g.hpFontSize    or baseSize
    local globalPowSize  = g.powerFontSize or baseSize
    
local useShadow = g.textBackdrop and true or false
local colorPowerTextByType = (g.colorPowerTextByType == true)
        local list = UnitFramesList
        local UpdateNameColor = MSUF_UpdateNameColor


        local function _MSUF_ApplyFontCached(fs, size, setColor, cr, cg, cb, useShadow)
            if not fs then return end
            local stamp = tostring(path) .. "|" .. tostring(size) .. "|" .. tostring(flags)
            if fs._msufFontStamp ~= stamp then
                fs:SetFont(path, size, flags)
                fs._msufFontStamp = stamp
                -- after a font change, we must re-apply shadow state
                fs._msufShadowOn = nil
            end
            if setColor then
                local cstamp = tostring(cr) .. "|" .. tostring(cg) .. "|" .. tostring(cb)
                if fs._msufColorStamp ~= cstamp then
                    fs:SetTextColor(cr, cg, cb, 1)
                    fs._msufColorStamp = cstamp
                end
            end
            local sh = useShadow and 1 or 0
            if fs._msufShadowOn ~= sh then
                if sh == 1 then
                    fs:SetShadowColor(0, 0, 0, 1)
                    fs:SetShadowOffset(1, -1)
                else
                    fs:SetShadowOffset(0, 0)
                end
                fs._msufShadowOn = sh
            end
        end

        local function ApplyFontsToFrame(f)

            if not f then return end

            local conf
            if f.unit and MSUF_DB then
                local key = f.msufConfigKey
                if not key then
                    local fn = GetConfigKeyForUnit
                    if type(fn) == "function" then
                        key = fn(f.unit)
                    end
                end
                if key then
                    conf = MSUF_DB[key]
                end
            end

            local nameSize  = (conf and conf.nameFontSize)  or globalNameSize
            local hpSize    = (conf and conf.hpFontSize)    or globalHPSize
            local powerSize = (conf and conf.powerFontSize) or globalPowSize
            local nameText = f.nameText
            if nameText then
                _MSUF_ApplyFontCached(nameText, nameSize, false, 0,0,0, useShadow)
            end
            local levelText = f.levelText
            if levelText then
                _MSUF_ApplyFontCached(levelText, nameSize, false, 0,0,0, useShadow)
            end

            -- Status indicators (player/target) must follow the global font too.
            local statusSize = nameSize + 2
            local st = f.statusIndicatorText
            if st then
                _MSUF_ApplyFontCached(st, statusSize, true, fr, fg, fb, useShadow)
            end
            local st2 = f.statusIndicatorOverlayText
            if st2 then
                _MSUF_ApplyFontCached(st2, statusSize, true, fr, fg, fb, useShadow)
            end

            if nameText and UpdateNameColor then
                UpdateNameColor(f)
            end
            local hpText = f.hpText
            if hpText then
                _MSUF_ApplyFontCached(hpText, hpSize, true, fr, fg, fb, useShadow)
            end
            local hpTextPct = f.hpTextPct
            if hpTextPct then
                _MSUF_ApplyFontCached(hpTextPct, hpSize, true, fr, fg, fb, useShadow)
            end
            local powerText = f.powerText
            if powerText then
                -- When "Color power text by power type" is enabled, power text coloring is owned by the
                -- runtime fast-path (no fighting/blinking on font refresh). UpdateAllFonts only applies font/shadow.
                if colorPowerTextByType then
                    _MSUF_ApplyFontCached(powerText, powerSize, false, 0, 0, 0, useShadow)
                else
                    _MSUF_ApplyFontCached(powerText, powerSize, true, fr, fg, fb, useShadow)
                end
            end
        end

        if list and #list > 0 then
            for i = 1, #list do
                ApplyFontsToFrame(list[i])
            end
        else
            for _, f in pairs(UnitFrames) do
                ApplyFontsToFrame(f)
            end
        end
    if type(_G.MSUF_UpdateCastbarVisuals_Immediate) == "function" then _G.MSUF_UpdateCastbarVisuals_Immediate() else MSUF_UpdateCastbarVisuals() end
    if ns and ns.MSUF_ApplyGameplayFontFromGlobal then
        ns.MSUF_ApplyGameplayFontFromGlobal()
    end
    if type(MSCB_ApplyFontsFromMSUF) == "function" then
        pcall(MSCB_ApplyFontsFromMSUF)
    end

    if type(_G.MSUF_Auras2_ApplyFontsFromGlobal) == "function" then
        _G.MSUF_Auras2_ApplyFontsFromGlobal()
    end

-- Ensure ToT-Inline (target) reflects any font/color changes immediately.
if ns and ns.MSUF_ToTInline_RequestRefresh then
    ns.MSUF_ToTInline_RequestRefresh("FONTS")
end
end
ns.MSUF_UpdateAllFonts = UpdateAllFonts
_G.MSUF_UpdateAllFonts = UpdateAllFonts

-- Ensure legacy global names exist (some modules call these)
_G.UpdateAllFonts = _G.UpdateAllFonts or _G.MSUF_UpdateAllFonts

-- Castbar refresh wrappers (keep immediate for internal code paths)
if type(MSUF_UpdateCastbarVisuals) == "function" and not _G.MSUF_UpdateCastbarVisuals_Immediate then
    _G.MSUF_UpdateCastbarVisuals_Immediate = MSUF_UpdateCastbarVisuals
    MSUF_UpdateCastbarVisuals = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        MSUF_ScheduleApplyCommit()
    end
end

if type(MSUF_UpdateCastbarTextures) == "function" and not _G.MSUF_UpdateCastbarTextures_Immediate then
    _G.MSUF_UpdateCastbarTextures_Immediate = MSUF_UpdateCastbarTextures
    MSUF_UpdateCastbarTextures = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.castbars = true end
        MSUF_ScheduleApplyCommit()
    end
end

-- Font refresh wrapper
if type(_G.MSUF_UpdateAllFonts) == "function" and not _G.MSUF_UpdateAllFonts_Immediate then
    _G.MSUF_UpdateAllFonts_Immediate = _G.MSUF_UpdateAllFonts
    _G.MSUF_UpdateAllFonts = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.fonts = true end
        MSUF_ScheduleApplyCommit()
    end
    _G.UpdateAllFonts = _G.MSUF_UpdateAllFonts
end

local function UpdateAllBarTextures()
    local texHP = MSUF_GetBarTexture()
    if not texHP then return end

    local texAbs  = MSUF_GetAbsorbBarTexture()
    local texHeal = MSUF_GetHealAbsorbBarTexture()
    -- Safety: if per-absorb keys resolve to nil, fall back to the main foreground texture.
    texAbs  = texAbs  or texHP
    texHeal = texHeal or texHP

    local function ApplyTex(sb, tex)
        if not sb or not tex then return end
        if sb.MSUF_cachedStatusbarTexture ~= tex then
            sb:SetStatusBarTexture(tex)
            sb.MSUF_cachedStatusbarTexture = tex
        end
    end

    local list = UnitFramesList
    if list and #list > 0 then
        for i = 1, #list do
            local f = list[i]
            if f then
                ApplyTex(f.hpBar, texHP)
                ApplyTex(f.absorbBar, texAbs)
                ApplyTex(f.healAbsorbBar, texHeal)
                if MSUF_ApplyBarBackgroundVisual then
                    MSUF_ApplyBarBackgroundVisual(f)
                end
                ApplyTex(f.targetPowerBar, texHP)
            end
        end
        return
    end

    if not UnitFrames then return end
    for _, f in pairs(UnitFrames) do
        ApplyTex(f.hpBar, texHP)
        ApplyTex(f.absorbBar, texAbs)
        ApplyTex(f.healAbsorbBar, texHeal)
        if MSUF_ApplyBarBackgroundVisual then
            MSUF_ApplyBarBackgroundVisual(f)
        end
        ApplyTex(f.targetPowerBar, texHP)
    end
end

local function UpdateAbsorbBarTextures()
    local texAbs  = MSUF_GetAbsorbBarTexture()
    local texHeal = MSUF_GetHealAbsorbBarTexture()
    if not texAbs or not texHeal then
        -- Fallback to foreground texture if something fails to resolve (e.g., missing media).
        local texHP = MSUF_GetBarTexture()
        texAbs  = texAbs  or texHP
        texHeal = texHeal or texHP
        if not texAbs or not texHeal then return end
    end

    local function ApplyTex(sb, tex)
        if not sb or not tex then return end
        if sb.MSUF_cachedStatusbarTexture ~= tex then
            sb:SetStatusBarTexture(tex)
            sb.MSUF_cachedStatusbarTexture = tex
        end
    end

    local list = UnitFramesList
    if list and #list > 0 then
        for i = 1, #list do
            local f = list[i]
            if f then
                ApplyTex(f.absorbBar, texAbs)
                ApplyTex(f.healAbsorbBar, texHeal)
            end
        end
        return
    end

    if not UnitFrames then return end
    for _, f in pairs(UnitFrames) do
        ApplyTex(f.absorbBar, texAbs)
        ApplyTex(f.healAbsorbBar, texHeal)
    end
end
_G.MSUF_UpdateAbsorbBarTextures = UpdateAbsorbBarTextures
if ns then ns.MSUF_UpdateAbsorbBarTextures = UpdateAbsorbBarTextures end

_G.UpdateAllBarTextures = UpdateAllBarTextures
_G.MSUF_UpdateAllBarTextures = UpdateAllBarTextures

_G.UpdateAllBarTextures = _G.UpdateAllBarTextures or _G.MSUF_UpdateAllBarTextures
if type(_G.MSUF_UpdateAllBarTextures) == "function" and not _G.MSUF_UpdateAllBarTextures_Immediate then
    _G.MSUF_UpdateAllBarTextures_Immediate = _G.MSUF_UpdateAllBarTextures
    _G.MSUF_UpdateAllBarTextures = function()
        local st = _G.MSUF_ApplyCommitState
        if st then st.bars = true end
        MSUF_ScheduleApplyCommit()
    end

    _G.UpdateAllBarTextures = _G.MSUF_UpdateAllBarTextures
end
if ns then
    ns.MSUF_UpdateAllBarTextures = UpdateAllBarTextures
end
local function MSUF_NudgeUnitFrameOffset(unit, parent, deltaX, deltaY)
    if not unit or not parent then return end
    EnsureDB()
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key]
    if not conf then return end
    local STEP = 1
    deltaX = (deltaX or 0) * STEP
    deltaY = (deltaY or 0) * STEP
    if MSUF_EditModeSizing then
        local w = conf.width  or parent:GetWidth()  or 250
        local h = conf.height or parent:GetHeight() or 40
        w = w + deltaX
        h = h + deltaY
        if w < 80  then w = 80  end
        if w > 600 then w = 600 end
        if h < 20  then h = 20  end
        if h > 220 then h = 220 end
        conf.width  = w
        conf.height = h
        if key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bossUnit = "boss" .. i
                local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                if frame then
                    frame:SetSize(w, h)
                    if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                        _G.MSUF_RequestUnitframeUpdate(frame, true, true, "EditModeSizing")
                    elseif UpdateSimpleUnitFrame then
                        UpdateSimpleUnitFrame(frame)
                    end
                end
            end
        else
            parent:SetSize(w, h)
            if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                _G.MSUF_RequestUnitframeUpdate(parent, true, true, "EditModeSizing")
            elseif UpdateSimpleUnitFrame then
                UpdateSimpleUnitFrame(parent)
            end
        end
    else
        conf.offsetX = (conf.offsetX or 0) + deltaX
        conf.offsetY = (conf.offsetY or 0) + deltaY
        if key == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bossUnit = "boss" .. i
                local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                if frame then
                    PositionUnitFrame(frame, bossUnit)
                end
            end
        else
            PositionUnitFrame(parent, unit)
        end
        if MSUF_CurrentOptionsKey == key then
            local xSlider = _G["MSUF_OffsetXSlider"]
            local ySlider = _G["MSUF_OffsetYSlider"]
            if xSlider and xSlider.SetValue then
                xSlider:SetValue(conf.offsetX or 0)
            end
            if ySlider and ySlider.SetValue then
                ySlider:SetValue(conf.offsetY or 0)
            end
        end
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
local function MSUF_EnableUnitFrameDrag(f, unit)
    if not f or not unit then return end

    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(false)
    if f.RegisterForDrag then
        f:RegisterForDrag("LeftButton", "RightButton")
    end

    local function _DisableClicks(self)
        -- Temporarily suppress SecureUnitButton click actions so drag doesn't target/menu/etc.
        if not self or not self.GetAttribute or not self.SetAttribute then return end
        if not self._msufSavedClickAttrs then
            self._msufSavedClickAttrs = {
                type1 = self:GetAttribute("*type1"),
                type2 = self:GetAttribute("*type2"),
            }
        end
        self:SetAttribute("*type1", nil)
        self:SetAttribute("*type2", nil)
    end

    local function _RestoreClicks(self)
        local saved = self and self._msufSavedClickAttrs
        if not saved or not self.SetAttribute then return end
        self:SetAttribute("*type1", saved.type1)
        self:SetAttribute("*type2", saved.type2)
        self._msufSavedClickAttrs = nil
    end

    local function _GetConfAndKey()
        EnsureDB()
        local key = GetConfigKeyForUnit(unit)
        local conf = key and MSUF_DB and MSUF_DB[key]
        return key, conf
    end

    local function _ApplySnapAndClamp(key, conf)
        if not conf then return end
        local g = MSUF_DB and MSUF_DB.general or nil

        if not MSUF_EditModeSizing then
            if g and g.editModeSnapToGrid then
                local gridStep = g.editModeGridStep or 20
                if gridStep < 1 then gridStep = 1 end
                local half = gridStep / 2
                local x = conf.offsetX or 0
                local y = conf.offsetY or 0
                conf.offsetX = math.floor((x + half) / gridStep) * gridStep
                conf.offsetY = math.floor((y + half) / gridStep) * gridStep
            end
        else
            -- Clamp sizes like the old logic did
            local w = conf.width  or (f.GetWidth and f:GetWidth()) or 250
            local h = conf.height or (f.GetHeight and f:GetHeight()) or 40
            if w < 80  then w = 80  end
            if w > 600 then w = 600 end
            if h < 20  then h = 20  end
            if h > 600 then h = 600 end
            conf.width, conf.height = w, h
        end
    end

    local function _UpdateDBFromFrame(self, key, conf)
        if not self or not conf or not key then return end

        if MSUF_EditModeSizing then
            local w, h = self:GetSize()
            if w and h then
                conf.width = w
                conf.height = h
            end
            if MSUF_SyncUnitPositionPopup then
                MSUF_SyncUnitPositionPopup(unit, conf)
            end
            if key == "boss" then
                for i = 1, MSUF_MAX_BOSS_FRAMES do
                    local bossUnit = "boss" .. i
                    local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                    if frame then
                        frame:SetSize(conf.width, conf.height)
                        if type(_G.MSUF_RequestUnitframeUpdate) == "function" then _G.MSUF_RequestUnitframeUpdate(frame, true, true, "EditModeDrag") elseif UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(frame) end
                    end
                end
            else
                if type(_G.MSUF_RequestUnitframeUpdate) == "function" then _G.MSUF_RequestUnitframeUpdate(self, true, true, "EditModeDrag") elseif UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(self) end
            end
            return
        end

        local anchor = MSUF_GetAnchorFrame and MSUF_GetAnchorFrame() or UIParent
        if not anchor or not anchor.GetCenter or not self.GetCenter then return end


        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown then
            local ecv = _G and _G["EssentialCooldownViewer"]
            if ecv and anchor == ecv then
                local rule = MSUF_ECV_ANCHORS and MSUF_ECV_ANCHORS[key]
                if rule then
                    local point, relPoint, baseX, extraY = rule[1], rule[2], rule[3] or 0, rule[4] or 0

                    local function _PointXY(fr, p)
                        if not fr or not p then return nil, nil end
                        if p == "CENTER" then
                            return fr:GetCenter()
                        end
                        local l, r, t, b = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
                        if not (l and r and t and b) then
                            return nil, nil
                        end
                        local cx = (l + r) * 0.5
                        local cy = (t + b) * 0.5
                        if p == "TOPLEFT" then return l, t end
                        if p == "TOP" then return cx, t end
                        if p == "TOPRIGHT" then return r, t end
                        if p == "LEFT" then return l, cy end
                        if p == "RIGHT" then return r, cy end
                        if p == "BOTTOMLEFT" then return l, b end
                        if p == "BOTTOM" then return cx, b end
                        if p == "BOTTOMRIGHT" then return r, b end
                        return fr:GetCenter()
                    end

                    local ax2, ay2 = _PointXY(ecv, relPoint)
                    local fx2, fy2 = _PointXY(self, point)
                    if ax2 and ay2 and fx2 and fy2 then
                        local x = fx2 - ax2
                        local y = fy2 - ay2
                        conf.offsetX = floor((x - baseX) + 0.5)
                        conf.offsetY = floor((y - extraY) + 0.5)
                        if MSUF_SyncUnitPositionPopup then
                            MSUF_SyncUnitPositionPopup(unit, conf)
                        end
                        if MSUF_UpdateEditModeInfo then
                            MSUF_UpdateEditModeInfo()
                        end
                        return
                    end
                end
            end
        end
        local ax, ay = anchor:GetCenter()
        local fx, fy = self:GetCenter()
        if not ax or not ay or not fx or not fy then return end

        local newX = fx - ax
        local newY = fy - ay

        if key == "boss" then
            -- bossN = baseY + (index-1)*spacing => baseY = newY - (index-1)*spacing
            local index = tonumber(unit:match("^boss(%d+)$")) or 1
            local spacing = conf.spacing or -36
            newY = newY - ((index - 1) * spacing)
        end

        conf.offsetX = newX
        conf.offsetY = newY

        if MSUF_SyncUnitPositionPopup then
            MSUF_SyncUnitPositionPopup(unit, conf)
        end

        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end
    end

    f:SetScript("OnMouseDown", function(self, button)
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end
        self._msufClickButton = button
        self._msufDragDidStart = false
    end)

    f:SetScript("OnDragStart", function(self, button)
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end

        local key, conf = _GetConfAndKey()
        if not key or not conf then return end

        self._msufDragDidStart = true
        self._msufDragActive = true
        self._msufDragKey = key
        self._msufDragConf = conf

        _DisableClicks(self)

        if MSUF_EditModeSizing then
            self:SetResizable(true)
            self:StartSizing("BOTTOMRIGHT")
        else
            self:StartMoving()
        end

        -- While dragging, keep DB/popup in sync without re-anchoring the frame.
        self._msufDragAccum = 0
        if _G.MSUF_UnregisterBucketUpdate then
            _G.MSUF_UnregisterBucketUpdate(self, "EditDrag")
        end
        if _G.MSUF_RegisterBucketUpdate then
            _G.MSUF_RegisterBucketUpdate(self, 0.02, function(s, dt)
                if not s._msufDragActive then return end
                _UpdateDBFromFrame(s, s._msufDragKey, s._msufDragConf)
            end, "EditDrag")
        else
            -- Fallback (should not happen): per-frame OnUpdate
            self:SetScript("OnUpdate", function(s, elapsed)
                if not s._msufDragActive then
                    s:SetScript("OnUpdate", nil)
                    return
                end
                s._msufDragAccum = (s._msufDragAccum or 0) + (elapsed or 0)
                if s._msufDragAccum < 0.02 then return end
                s._msufDragAccum = 0
                _UpdateDBFromFrame(s, s._msufDragKey, s._msufDragConf)
            end)
        end
    end)

    f:SetScript("OnDragStop", function(self, button)
        if not self._msufDragActive then return end
        self:StopMovingOrSizing()

        local key = self._msufDragKey
        local conf = self._msufDragConf

        self._msufDragActive = false
        self._msufDragKey = nil
        self._msufDragConf = nil

        if _G.MSUF_UnregisterBucketUpdate then
            _G.MSUF_UnregisterBucketUpdate(self, "EditDrag")
        end
        self:SetScript("OnUpdate", nil)
        _RestoreClicks(self)

        if key and conf then
            _UpdateDBFromFrame(self, key, conf)
            _ApplySnapAndClamp(key, conf)

            if key == "boss" then
                for i = 1, MSUF_MAX_BOSS_FRAMES do
                    local bossUnit = "boss" .. i
                    local frame = UnitFrames and UnitFrames[bossUnit] or _G["MSUF_" .. bossUnit]
                    if frame then
                        PositionUnitFrame(frame, bossUnit)
                    end
                end
            else
                PositionUnitFrame(self, unit)
            end
        end
    end)

    f:SetScript("OnMouseUp", function(self, button)
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if self._msufDragDidStart then
            -- Drag already handled; don't open popup.
            return
        end
        if not MSUF_EditModeSizing and MSUF_OpenPositionPopup then
            MSUF_OpenPositionPopup(unit, self)
        end
    end)
end
local function MSUF_CreateEditArrowButton(name, parent, unit, direction, point, relTo, relPoint, ofsX, ofsY, deltaX, deltaY)
    local btn = CreateFrame("Button", name, parent)
    btn:SetSize(18, 18)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    btn._bg = bg
    local symbols = {
        LEFT  = "<",
        RIGHT = ">",
        UP    = "^",
        DOWN  = "v",
    }
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(symbols[direction] or "")
    label:SetTextColor(0, 0, 0, 1)
    btn._label = label
    btn:SetScript("OnEnter", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self._bg then self._bg:SetColorTexture(1, 1, 1, 1) end
    end)
    btn:SetPoint(point, relTo or parent, relPoint or point, ofsX, ofsY)
    btn.deltaX = deltaX or 0
    btn.deltaY = deltaY or 0
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if not MSUF_UnitEditModeActive then return end
            if InCombatLockdown and InCombatLockdown() then return end
            if MSUF_OpenPositionPopup then
                MSUF_OpenPositionPopup(unit, parent)
            end
            return
        end
        if button ~= "LeftButton" then
            return
        end
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if MSUF_NudgeUnitFrameOffset then
            MSUF_NudgeUnitFrameOffset(unit, parent, self.deltaX or 0, self.deltaY or 0)
        end
    end)
    return btn
end
local function MSUF_AttachEditArrowsToFrame(f, unit, baseName)
    local pad = 8
    f.MSUF_ArrowLeft  = MSUF_CreateEditArrowButton(baseName .. "Left",  f, unit, "LEFT",  "RIGHT",  f, "LEFT",   -pad,  0, -1,  0)
    f.MSUF_ArrowRight = MSUF_CreateEditArrowButton(baseName .. "Right", f, unit, "RIGHT", "LEFT",   f, "RIGHT",   pad,  0,  1,  0)
    f.MSUF_ArrowUp    = MSUF_CreateEditArrowButton(baseName .. "Up",    f, unit, "UP",    "BOTTOM", f, "TOP",      0,  pad, 0,  1)
    f.MSUF_ArrowDown  = MSUF_CreateEditArrowButton(baseName .. "Down",  f, unit, "DOWN",  "TOP",    f, "BOTTOM",   0, -pad, 0, -1)
    if not f.UpdateEditArrows then
        function f:UpdateEditArrows()
            if not (self.MSUF_ArrowLeft and self.MSUF_ArrowRight and self.MSUF_ArrowUp and self.MSUF_ArrowDown) then
                return
            end
            local show = MSUF_UnitEditModeActive and (not InCombatLockdown or not InCombatLockdown())
            if show then
                self.MSUF_ArrowLeft:Show()
                self.MSUF_ArrowRight:Show()
                self.MSUF_ArrowUp:Show()
                self.MSUF_ArrowDown:Show()
            else
                self.MSUF_ArrowLeft:Hide()
                self.MSUF_ArrowRight:Hide()
                self.MSUF_ArrowUp:Hide()
                self.MSUF_ArrowDown:Hide()
            end
        end
    end
    f:UpdateEditArrows()
end
local MSUF_EDIT_ARROW_BASENAMES = {
    player       = "MSUF_PlayerArrow",
    target       = "MSUF_TargetArrow",
    focus        = "MSUF_FocusArrow",
    pet          = "MSUF_PetArrow",
    targettarget = "MSUF_TargetTargetArrow",
}
local function MSUF_CreateEditArrowsForUnit(f, unit)
    if not f or f.MSUF_ArrowsCreated then return end
    local baseName = MSUF_EDIT_ARROW_BASENAMES[unit]
    if not baseName then
        if type(unit) == "string" and unit:match("^boss%d+$") then
            baseName = "MSUF_" .. unit .. "_Arrow"
        else
            return
        end
    end
    f.MSUF_ArrowsCreated = true
    MSUF_AttachEditArrowsToFrame(f, unit, baseName)
end

local function MSUF_GetStatusIndicatorDB()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.statusIndicators = MSUF_DB.general.statusIndicators or {}
    return MSUF_DB.general.statusIndicators
end
local MSUF_UNIT_EVENTS_BASE = {
    "UNIT_NAME_UPDATE",
    "UNIT_LEVEL",
    "UNIT_POWER_UPDATE",
    "UNIT_MAXPOWER",
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_PORTRAIT_UPDATE",
    "UNIT_MODEL_CHANGED",
}
local MSUF_UNIT_EVENTS_PLAYER_TARGET_EXTRA = {
    "UNIT_FLAGS",
    "UNIT_CONNECTION",
}
local MSUF_GLOBAL_EVENTS_ALWAYS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_TARGET_CHANGED",
    "PLAYER_FOCUS_CHANGED",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
}
local MSUF_GLOBAL_EVENTS_GROUP_PLAYER_TARGET = {
    "GROUP_ROSTER_UPDATE",
    "PARTY_LEADER_CHANGED",
}
local function MSUF_RegisterGlobalEventList(f, list)
    if not f or not list then return end
    for i = 1, #list do
        f:RegisterEvent(list[i])
    end
end
local function MSUF_RegisterUnitOrGlobalEventList(f, list, unit, useUnitEvents)
    if not f or not list then return end
    if useUnitEvents and f.RegisterUnitEvent and unit then
        for i = 1, #list do
            f:RegisterUnitEvent(list[i], unit)
        end
    else
        for i = 1, #list do
            f:RegisterEvent(list[i])
        end
    end
end
local function MSUF_ConfBool(conf, field, default)
    local v = conf and conf[field]
    if v == nil then
        return default and true or false
    end
    return v and true or false
end
local MSUF_UNIT_CREATE_DEFS = {
    player =      { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    target =      { w = 275, h = 40, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
    focus =       { w = 220, h = 30, showName = true,  showHP = false, showPower = false, isBoss = false, startHidden = false },
    targettarget ={ w = 220, h = 30, showName = true,  showHP = true,  showPower = false, isBoss = false, startHidden = false },
    pet =         { w = 220, h = 30, showName = true,  showHP = true,  showPower = true,  isBoss = false, startHidden = false },
}
local MSUF_UNIT_CREATE_DEF_BOSS = { w = 220, h = 30, showName = true, showHP = true, showPower = true, isBoss = true, startHidden = true }

-- Shared tooltip dispatch: keep semantics (errors if missing functions) while collapsing unit if-chains.
local MSUF_UNIT_TIP_FUNCS = {
    player = "MSUF_ShowPlayerInfoTooltip",
    target = "MSUF_ShowTargetInfoTooltip",
    focus = "MSUF_ShowFocusInfoTooltip",
    targettarget = "MSUF_ShowTargetTargetInfoTooltip",
    pet = "MSUF_ShowPetInfoTooltip",
}

-- Power bar: optionally reserve space *inside* the Health bar instead of growing below it.
-- Toggle: MSUF_DB.bars.embedPowerBarIntoHealth
local function MSUF_ApplyPowerBarEmbedLayout(f)
    if not f or not f.hpBar then return end

    local pb = f.targetPowerBar
    if not pb then
        f._msufPowerBarReserved = nil
        f._msufPBLayoutStamp = nil
        return
    end

    EnsureDB()
    local b = (MSUF_DB and MSUF_DB.bars) or {}

    local h = tonumber(b.powerBarHeight) or 3
    h = math.floor(h + 0.5)
    if h < 1 then h = 1 elseif h > 80 then h = 80 end

    local embed = (b.embedPowerBarIntoHealth == true)

    local enabled = false
    local unit = f.unit
    if unit == 'player' then
        enabled = (b.showPlayerPowerBar ~= false)
    elseif unit == 'target' then
        enabled = (b.showTargetPowerBar ~= false)
    elseif unit == 'focus' then
        enabled = (b.showFocusPowerBar ~= false)
    elseif type(unit) == 'string' and string.sub(unit, 1, 4) == 'boss' then
        enabled = (b.showBossPowerBar ~= false)
    end

        local reserve = (embed and enabled and h > 0)

    local stamp = (reserve and '1' or '0') .. ':' .. tostring(h)
    if f._msufPBLayoutStamp == stamp then return end
    f._msufPBLayoutStamp = stamp
    f._msufPowerBarReserved = reserve and true or nil

    local hb = f.hpBar
    hb:ClearAllPoints()
    hb:SetPoint('TOPLEFT', f, 'TOPLEFT', 2, -2)
    if reserve then
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2 + h)
    else
        hb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    end

    pb:ClearAllPoints()
    pb:SetHeight(h)
    if reserve then
        pb:SetPoint('BOTTOMLEFT', f, 'BOTTOMLEFT', 2, 2)
        pb:SetPoint('BOTTOMRIGHT', f, 'BOTTOMRIGHT', -2, 2)
    else
        pb:SetPoint('TOPLEFT', hb, 'BOTTOMLEFT', 0, 0)
        pb:SetPoint('TOPRIGHT', hb, 'BOTTOMRIGHT', 0, 0)
    end

    -- Force bar-outline re-eval (outline caches thickness/anchors).
    f._msufBarOutlineThickness = -1
end

_G.MSUF_ApplyPowerBarEmbedLayout = MSUF_ApplyPowerBarEmbedLayout

_G.MSUF_ApplyPowerBarEmbedLayout_All = function()
    if not UnitFrames then return end
    for _, fr in pairs(UnitFrames) do
        if fr and fr.hpBar and fr.targetPowerBar then
            MSUF_ApplyPowerBarEmbedLayout(fr)
        end
    end
end

local function CreateSimpleUnitFrame(unit)
    EnsureDB()
    local key  = GetConfigKeyForUnit(unit)
    local conf = key and MSUF_DB[key] or {}
    local f = CreateFrame("Button", "MSUF_" .. unit, UIParent, "BackdropTemplate,SecureUnitButtonTemplate,PingableUnitFrameTemplate")
    f.unit = unit
    MSUF_EnsureUnitFlags(f)
    f.msufConfigKey = key
    f.cachedConfig = conf -- Step 5: cache config on creation as well
    f:SetClampedToScreen(true)

    local isBossUnit = (f._msufBossIndex ~= nil)
    local def = MSUF_UNIT_CREATE_DEFS[unit] or (isBossUnit and MSUF_UNIT_CREATE_DEF_BOSS) or nil
    if def then
        f:SetSize(conf.width or def.w, conf.height or def.h)
        f.showName      = MSUF_ConfBool(conf, "showName",  def.showName)
        f.showHPText    = MSUF_ConfBool(conf, "showHP",    def.showHP)
        f.showPowerText = MSUF_ConfBool(conf, "showPower", def.showPower)
        f.isBoss = def.isBoss and true or false
        if def.startHidden then f:Hide() end
        if f.isBoss and MSUF_ApplyUnitVisibilityDriver then MSUF_ApplyUnitVisibilityDriver(f, false) end
    end

    PositionUnitFrame(f, unit)
    MSUF_EnableUnitFrameDrag(f, unit)
    MSUF_CreateEditArrowsForUnit(f, unit)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    if ClickCastFrames then ClickCastFrames[f] = true end

    -- Outside Edit Mode as well: clicking a MSUF unitframe selects which unit's HP spacer
    -- settings are shown in the Bars menu.
    if not f._msufHpSpacerSelectHooked then
        f._msufHpSpacerSelectHooked = true
        f:HookScript("OnMouseDown", function(self)
            if type(_G.MSUF_SetHpSpacerSelectedUnitKey) ~= "function" then return end
            local k = self.msufConfigKey or (self.unit and GetConfigKeyForUnit(self.unit))
            if k then _G.MSUF_SetHpSpacerSelectedUnitKey(k) end
        end)
    end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    f.bg = bg

    local hpBar = CreateFrame("StatusBar", nil, f)
    hpBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    hpBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    hpBar:SetStatusBarTexture(MSUF_GetBarTexture())
    hpBar:SetMinMaxValues(0, 1)
    MSUF_SetBarValue(hpBar, 0, false); hpBar.MSUF_lastValue = 0
    hpBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f.hpBar = hpBar
    do
        local bgTex = hpBar:CreateTexture(nil, "BACKGROUND")
        bgTex:SetAllPoints(hpBar)
        f.hpBarBG = bgTex
        MSUF_ApplyBarBackgroundVisual(f)
    end

    local portrait = f:CreateTexture(nil, "ARTWORK")
    portrait:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    portrait:Hide()
    f.portrait = portrait

    local grads = f.hpGradients
    if not grads then
        grads = MSUF_PreCreateHPGradients(hpBar)
        f.hpGradients = grads
        f.hpGradient = grads and grads.right or nil
    end
    MSUF_ApplyHPGradient(f)

    f.absorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 2, MSUF_GetAbsorbOverlayColor(), true)
    f.healAbsorbBar = MSUF_CreateOverlayStatusBar(f, hpBar, hpBar:GetFrameLevel() + 3, MSUF_GetHealAbsorbOverlayColor(), false)

    -- Apply per-overlay textures (optional overrides; default follows foreground texture)
    if f.absorbBar and f.absorbBar.SetStatusBarTexture then
        local atex = MSUF_GetAbsorbBarTexture()
        if atex then
            f.absorbBar:SetStatusBarTexture(atex)
            f.absorbBar.MSUF_cachedStatusbarTexture = atex
        end
    end
    if f.healAbsorbBar and f.healAbsorbBar.SetStatusBarTexture then
        local htex = MSUF_GetHealAbsorbBarTexture()
        if htex then
            f.healAbsorbBar:SetStatusBarTexture(htex)
            f.healAbsorbBar.MSUF_cachedStatusbarTexture = htex
        end
    end

    if unit == "player" or unit == "focus" or unit == "target" or isBossUnit then
        local pBar = CreateFrame("StatusBar", nil, f)
        pBar:SetStatusBarTexture(MSUF_GetBarTexture())
        local h = ((MSUF_DB and MSUF_DB.bars and type(MSUF_DB.bars.powerBarHeight) == "number" and MSUF_DB.bars.powerBarHeight > 0) and MSUF_DB.bars.powerBarHeight) or 3
        pBar:SetHeight(h)
        pBar:SetPoint("TOPLEFT",  hpBar, "BOTTOMLEFT",  0, 0)
        pBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, 0)
        pBar:SetMinMaxValues(0, 1)
        MSUF_SetBarValue(pBar, 0, false); pBar.MSUF_lastValue = 0
        pBar:SetFrameLevel(hpBar:GetFrameLevel())
        f.targetPowerBar = pBar
        do
            local pbg = pBar:CreateTexture(nil, "BACKGROUND")
            pbg:SetAllPoints(pBar)
            f.powerBarBG = pbg
            MSUF_ApplyBarBackgroundVisual(f)

            local pgrads = f.powerGradients
            if not pgrads then
                pgrads = MSUF_PreCreateHPGradients(pBar)
                f.powerGradients = pgrads
                f.powerGradient = pgrads and pgrads.right or nil
            end
            MSUF_ApplyPowerGradient(f)
        end

        -- Power bar border (applies immediately; bar hide will hide border too).
        if type(_G.MSUF_ApplyPowerBarBorder) == "function" then
            _G.MSUF_ApplyPowerBarBorder(pBar)
        end

        pBar:Hide()
    end

    local textFrame = CreateFrame("Frame", nil, f)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(hpBar:GetFrameLevel() + 3)
    f.textFrame = textFrame

    local fontPath = MSUF_GetFontPath()
    local flags    = MSUF_GetFontFlags()
    local fr, fg, fb = MSUF_GetConfiguredFontColor()
    do
        local defs = {
            { "nameText",   "GameFontHighlight",      "LEFT",  1 },
            { "levelText",  "GameFontHighlightSmall", "LEFT",  1,   true },
            { "hpText",     "GameFontHighlightSmall", "RIGHT", 0.9 },
            { "hpTextPct",  "GameFontHighlightSmall", "RIGHT", 0.9, true },
            { "powerText",  "GameFontHighlightSmall", "RIGHT", 0.9 },
        }
        for i = 1, #defs do
            local d = defs[i]
            local fs = MSUF_CreateStyledFontString(textFrame, "OVERLAY", d[2], fontPath, 14, flags, d[3], fr, fg, fb, d[4])
            f[d[1]] = fs
            if d[5] then fs:SetText(""); fs:Hide() end
        end
    end

    if unit == "player" or unit == "target" then
        local g = (MSUF_DB and MSUF_DB.general) or nil
        local stSize = ((g and (g.nameFontSize or g.fontSize)) or 14) + 2
        local st = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        st:SetFont(fontPath, stSize, flags); st:SetJustifyH("CENTER"); if st.SetJustifyV then st:SetJustifyV("MIDDLE") end
        st:SetTextColor(fr, fg, fb, 0.95); st:SetPoint("CENTER", f, "CENTER", 0, 0); st:SetText(""); st:Hide()
        f.statusIndicatorText = st

        local ov = CreateFrame("Frame", nil, UIParent)
        ov:SetFrameStrata("HIGH"); ov:SetFrameLevel(999)
        ov:ClearAllPoints(); ov:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0); ov:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        ov:Hide()
        f.statusIndicatorOverlayFrame = ov

        local st2 = ov:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        st2:SetFont(fontPath, stSize, flags); st2:SetJustifyH("CENTER"); if st2.SetJustifyV then st2:SetJustifyV("MIDDLE") end
        st2:SetTextColor(fr, fg, fb, 1); st2:ClearAllPoints(); st2:SetPoint("CENTER", f, "CENTER", 0, 0); st2:SetText(""); st2:Hide()
        f.statusIndicatorOverlayText = st2
    end

    ApplyTextLayout(f, conf)
    MSUF_ClampNameWidth(f, conf)
    MSUF_UpdateNameColor(f)

    if unit == "player" or unit == "target" then
        local leaderIcon = f:CreateTexture(nil, "OVERLAY")
        leaderIcon:SetSize(16, 16)
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        leaderIcon:SetPoint("LEFT", f, "TOPLEFT", 0, 3)
        leaderIcon:Hide()
        f.leaderIcon = leaderIcon
        if _G.MSUF_ApplyLeaderIconLayout then _G.MSUF_ApplyLeaderIconLayout(f) end
    end

    local raidIcon = textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    raidIcon:SetSize(16, 16)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    raidIcon:SetPoint("LEFT", textFrame, "TOPLEFT", 16, 3)
    raidIcon:Hide()
    f.raidMarkerIcon = raidIcon
    if _G.MSUF_ApplyRaidMarkerLayout then _G.MSUF_ApplyRaidMarkerLayout(f) end

    -- Status Icons (Combat / Resting / Summon / Incoming Rez)
    -- Player + Target only (matches Status element event registrations).
    if unit == "player" or unit == "target" then
        local function _SetAtlasOrFallback(tex, atlas, fallbackFile, l, r, t, b)
            if tex and tex.SetAtlas and _G.C_Texture and _G.C_Texture.GetAtlasInfo and atlas and _G.C_Texture.GetAtlasInfo(atlas) then
                tex:SetAtlas(atlas, true)
            else
                tex:SetTexture(fallbackFile)
                if l then tex:SetTexCoord(l, r, t, b) end
            end
        end

        local iconSize = 18

        local combatIcon = textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        combatIcon:SetSize(iconSize, iconSize)
        _SetAtlasOrFallback(combatIcon, "UI-HUD-UnitFrame-Player-PortraitCombatIcon", "Interface\\CharacterFrame\\UI-StateIcon", 0.5, 1, 0, 0.5)
        combatIcon:Hide()
        f.combatStateIndicatorIcon = combatIcon

        if unit == "player" then
            local restIcon = textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            restIcon:SetSize(iconSize, iconSize)
            _SetAtlasOrFallback(restIcon, "UI-HUD-UnitFrame-Player-PortraitRestingIcon", "Interface\\CharacterFrame\\UI-StateIcon", 0, 0.5, 0, 0.5)
            restIcon:Hide()
            f.restingIndicatorIcon = restIcon
        end

        local rezIcon = textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        rezIcon:SetSize(iconSize, iconSize)
        rezIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
        rezIcon:Hide()
        f.incomingResIndicatorIcon = rezIcon

        local summonIcon = textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        summonIcon:SetSize(iconSize, iconSize)
        _SetAtlasOrFallback(summonIcon, "Raid-Icon-SummonPending", "Interface\\RaidFrame\\Raid-Icon-Summon", nil)
        summonIcon:Hide()
        f.summonIndicatorIcon = summonIcon
    end

    -- NOTE: Unitframe events are now registered centrally by MSUF_UnitframeCore.lua.
    -- Centralized event routing + update scheduling (MSUF_UnitframeCore.lua).
    if _G.MSUF_UFCore_AttachFrame then _G.MSUF_UFCore_AttachFrame(f) end

    f:EnableMouse(true)
        local highlight = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
    f.highlightBorder = highlight
    -- Anchor to the full unitframe, not the hpBar: when portraits/spacers shrink hpBar,
    -- the hover border must still match the visible "box" like other units.
    highlight:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
    highlight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    -- Ensure the border draws above bars/text for all units (player often has higher-level regions).
    do
        local baseLevel = 0
        if f.GetFrameLevel then baseLevel = f:GetFrameLevel() or 0 end
        if f.hpBar and f.hpBar.GetFrameLevel then
            local hb = f.hpBar:GetFrameLevel() or 0
            if hb > baseLevel then baseLevel = hb end
        end
        highlight:SetFrameLevel(baseLevel + 10)
    end
    highlight:EnableMouse(false)
    highlight:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    highlight:Hide()

    function f:UpdateHighlightColor()
        EnsureDB()
        local g = MSUF_DB.general or {}
        local r, gCol, b
        if type(g.highlightColor) == "table" and #g.highlightColor == 3 then
            r, gCol, b = g.highlightColor[1], g.highlightColor[2], g.highlightColor[3]
        else
            local key = (type(g.highlightColor) == "string" and g.highlightColor:lower()) or "white"
            local color = MSUF_FONT_COLORS[key] or MSUF_FONT_COLORS.white
            r, gCol, b = color[1], color[2], color[3]
        end
        local stamp = tostring(r) .. "|" .. tostring(gCol) .. "|" .. tostring(b)
        if self._msufHighlightColorStamp ~= stamp then
            self.highlightBorder:SetBackdropBorderColor(r, gCol, b, 1)
            self._msufHighlightColorStamp = stamp
        end
    end

    f:SetScript("OnEnter", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local hb = self.highlightBorder
        if hb then
            if g.highlightEnabled == false then
                hb:Hide()
            else
                self:UpdateHighlightColor(); hb:Show()
            end
        end

        if g.disableUnitInfoTooltips then
            if GameTooltip and self.unit and UnitExists and UnitExists(self.unit) then
                local style = g.unitInfoTooltipStyle or "classic"
                if style == "modern" then
                    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR", 0, -100)
                else
                    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                    GameTooltip:ClearAllPoints()
                    GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -16, 16)
                end
                GameTooltip:SetUnit(self.unit)
                GameTooltip:Show()
            end
            return
        end

        local u = self.unit
        local fnName = u and MSUF_UNIT_TIP_FUNCS[u]
        if fnName then
            if UnitExists(u) then (_G[fnName])() end
        elseif u and string.sub(u, 1, 4) == "boss" and UnitExists(u) then
            MSUF_ShowBossInfoTooltip(u)
        end
    end)

    f:SetScript("OnLeave", function(self)
        if self.highlightBorder then self.highlightBorder:Hide() end
        local u = self.unit
        if u and (MSUF_UNIT_TIP_FUNCS[u] or string.sub(u, 1, 4) == "boss") then
            MSUF_HidePlayerInfoTooltip()
        end
        GameTooltip:Hide()
    end)

    if f.targetPowerBar and f.hpBar then
        MSUF_ApplyPowerBarEmbedLayout(f)
    end

    if type(_G.MSUF_RequestUnitframeUpdate) == "function" then
        _G.MSUF_RequestUnitframeUpdate(f, true, true, "CreateFrame")
    else
        UpdateSimpleUnitFrame(f)
    end
    if unit == "target" then MSUF_UpdateTargetAuras(f) end
    UnitFrames[unit] = f
    if not f._msufInUnitFramesList then
        f._msufInUnitFramesList = true
        table.insert(UnitFramesList, f)
    end
    MSUF_ApplyUnitVisibilityDriver(f, MSUF_UnitEditModeActive)
end


-- Target select / target lost sounds (opt-in).
-- Mirrors default Blizzard TargetFrame behavior without depending on Blizzard frames.
-- IMPORTANT (Midnight): do NOT compare UnitGUID values (they can be "secret").
do
    local _msufTargetSoundFrame
    local _msufHadTarget

    local function MSUF_TargetSoundDriver_ResetState()
        _msufHadTarget = UnitExists and UnitExists("target") or false
    end

    local function MSUF_TargetSoundDriver_OnTargetChanged()
        if type(EnsureDB) == "function" then EnsureDB() end
        local g = (MSUF_DB and MSUF_DB.general) or {}

        local hasTarget = (UnitExists and UnitExists("target")) or false
        local hadTarget = _msufHadTarget
        _msufHadTarget = hasTarget

        -- Opt-in (but still keep our cached state correct while disabled).
        if g.playTargetSelectLostSounds ~= true then
            return
        end

        -- Lost target
        if (not hasTarget) and hadTarget then
            if type(_G.IsTargetLoose) == "function" and _G.IsTargetLoose() then
                return
            end
            if _G.SOUNDKIT and _G.SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT and PlaySound then
                local forceNoDuplicates = true
                PlaySound(_G.SOUNDKIT.INTERFACE_SOUND_LOST_TARGET_UNIT, nil, forceNoDuplicates)
            end
            return
        end

        -- New target selected (or switched target)
        if hasTarget then
            -- Match Blizzard: don't play selection sounds while the interaction manager is replacing units.
            if _G.C_PlayerInteractionManager
                and _G.C_PlayerInteractionManager.IsReplacingUnit
                and _G.C_PlayerInteractionManager.IsReplacingUnit() then
                return
            end

            local sk = _G.SOUNDKIT
            if not (sk and PlaySound) then return end

            local id
            if UnitIsEnemy and UnitIsEnemy("player", "target") then
                id = sk.IG_CREATURE_AGGRO_SELECT
            elseif UnitIsFriend and UnitIsFriend("player", "target") then
                id = sk.IG_CHARACTER_NPC_SELECT
            else
                id = sk.IG_CREATURE_NEUTRAL_SELECT
            end

            if id then
                PlaySound(id)
            end
        end
    end

    local function MSUF_TargetSoundDriver_Ensure()
        if _msufTargetSoundFrame then
            return
        end
        _msufTargetSoundFrame = CreateFrame("Frame")
        _msufTargetSoundFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        _msufTargetSoundFrame:SetScript("OnEvent", MSUF_TargetSoundDriver_OnTargetChanged)
        MSUF_TargetSoundDriver_ResetState()
    end

    _G.MSUF_TargetSoundDriver_Ensure = MSUF_TargetSoundDriver_Ensure
    _G.MSUF_TargetSoundDriver_ResetState = MSUF_TargetSoundDriver_ResetState
end



MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_STARTUP", function(event)
    MSUF_InitProfiles()
    EnsureDB()

    -- Lazy-init: only create/register the target-sound driver if the feature is enabled.
    do
        local g = (MSUF_DB and MSUF_DB.general) or {}
        if g.playTargetSelectLostSounds == true and _G.MSUF_TargetSoundDriver_Ensure then
            _G.MSUF_TargetSoundDriver_Ensure()
        end
    end


    HideDefaultFrames()
    CreateSimpleUnitFrame("player")
    if type(_G.MSUF_ApplyCompatAnchor_PlayerFrame) == "function" then
        _G.MSUF_ApplyCompatAnchor_PlayerFrame()
    end
    CreateSimpleUnitFrame("target")
if ns and ns.MSUF_CreateSecureTargetAuraHeaders then
    local targetFrame = UnitFrames and (UnitFrames.target or UnitFrames["target"])
    if targetFrame then
        ns.MSUF_CreateSecureTargetAuraHeaders(targetFrame)
    else
        print("MSUF: Target frame not found, cannot attach secure auras.")
    end
end
    CreateSimpleUnitFrame("targettarget")
    CreateSimpleUnitFrame("focus")
    CreateSimpleUnitFrame("pet")
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        CreateSimpleUnitFrame("boss" .. i)
    end
    if MSUF_ApplyUnitVisibilityDriver and UnitFrames then
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            local bf = UnitFrames["boss" .. i]
            if bf and bf.isBoss then
                MSUF_ApplyUnitVisibilityDriver(bf, false)
            end
        end
    end
    do
        local function MSUF_MarkToTDirty()
            local tot = UnitFrames and UnitFrames["targettarget"]
            if tot then
                tot._msufToTDirty = true
            end
        end
        local function MSUF_TryUpdateToT(force)
            local tot = UnitFrames and UnitFrames["targettarget"]
            if not tot or not tot.IsShown or not tot:IsShown() then
                return
            end
            local key = GetConfigKeyForUnit and GetConfigKeyForUnit("targettarget")
            local conf = key and MSUF_DB and MSUF_DB[key]
            if conf and conf.enabled == false then
                return
            end
            if not (UnitExists and UnitExists("targettarget")) then
                return
            end
            if not force and not tot._msufToTDirty then
                return
            end
            tot._msufToTDirty = false
            if type(_G.MSUF_QueueUnitframeUpdate) == "function" then
                _G.MSUF_QueueUnitframeUpdate(tot, true)
            elseif type(_G.UpdateSimpleUnitFrame) == "function" then
                _G.UpdateSimpleUnitFrame(tot)
            end
        end
-- Target name: optional inline "ToT" text (secret-safe)
local function MSUF_EnsureTargetToTInlineFS(targetFrame)
    if not targetFrame or not targetFrame.nameText then return end
    if targetFrame._msufToTInlineText and targetFrame._msufToTInlineSep then return end
    local parent = targetFrame.textFrame or targetFrame
    local sep = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sep:SetJustifyH("LEFT")
    sep:SetJustifyV("MIDDLE")
    sep:SetWordWrap(false)
    if sep.SetNonSpaceWrap then sep:SetNonSpaceWrap(false) end
    -- Default separator. Actual value is pulled from DB in MSUF_RuntimeUpdateTargetToTInline().
    sep:SetText(" | ")
    local txt = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetJustifyH("LEFT")
    txt:SetJustifyV("MIDDLE")
    txt:SetWordWrap(false)
    if txt.SetNonSpaceWrap then txt:SetNonSpaceWrap(false) end
    sep:ClearAllPoints()
    sep:SetPoint("LEFT", targetFrame.nameText, "RIGHT", 0, 0)
    txt:ClearAllPoints()
    txt:SetPoint("LEFT", sep, "RIGHT", 0, 0)
    targetFrame._msufToTInlineSep = sep
    targetFrame._msufToTInlineText = txt
end
function MSUF_RuntimeUpdateTargetToTInline(targetFrame)
    if not targetFrame or not targetFrame.nameText then return end
    -- Ensure DB exists even if the ToT unitframe is disabled (inline must not depend on ToT frame initialization).
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
    if not MSUF_DB then return end
    if type(MSUF_DB.targettarget) ~= "table" then
        MSUF_DB.targettarget = {}
    end
    -- Migration/fallback: older builds may have stored the toggle under target instead of targettarget.
    if MSUF_DB.targettarget.showToTInTargetName == nil and type(MSUF_DB.target) == "table" and MSUF_DB.target.showToTInTargetName ~= nil then
        MSUF_DB.targettarget.showToTInTargetName = (MSUF_DB.target.showToTInTargetName and true) or false
    end
    -- Migration/fallback: older builds may have stored the separator under target instead of targettarget.
    if MSUF_DB.targettarget.totInlineSeparator == nil and type(MSUF_DB.target) == "table" and type(MSUF_DB.target.totInlineSeparator) == "string" then
        MSUF_DB.targettarget.totInlineSeparator = MSUF_DB.target.totInlineSeparator
    end
    if type(MSUF_DB.targettarget.totInlineSeparator) ~= "string" or MSUF_DB.targettarget.totInlineSeparator == "" then
        MSUF_DB.targettarget.totInlineSeparator = "|"
    end
    MSUF_EnsureTargetToTInlineFS(targetFrame)
    local sep = targetFrame._msufToTInlineSep
    local txt = targetFrame._msufToTInlineText
    if not sep or not txt then return end
    local totConf = MSUF_DB.targettarget
    local enabled = (totConf and totConf.showToTInTargetName) and true or false
    if not enabled or not (UnitExists and UnitExists("target")) or not (UnitExists and UnitExists("targettarget")) then
        sep:Hide()
        txt:Hide()
        return
    end

    -- Apply separator token (stored in DB) with spaces around it (legacy style).
    local _sepTok = (totConf and totConf.totInlineSeparator) or "|"
    if type(_sepTok) ~= "string" or _sepTok == "" then _sepTok = "|" end
    sep:SetText(" " .. _sepTok .. " ")
    -- Match target name font (no secret ops).
    local font, size, flags = targetFrame.nameText:GetFont()
    if font and sep.SetFont then
        sep:SetFont(font, size, flags)
        txt:SetFont(font, size, flags)
    end
    -- Clamp ToT inline width (secret-safe, no string width math).
    local frameWidth = (targetFrame.GetWidth and targetFrame:GetWidth()) or 0
    local maxW = 120
    if frameWidth and frameWidth > 0 then
        maxW = floor(frameWidth * 0.32)
        if maxW < 80 then maxW = 80 end
        if maxW > 180 then maxW = 180 end
    end
    txt:SetWidth(maxW)
    local r, gCol, b = 1, 1, 1
    if UnitIsPlayer and UnitIsPlayer("targettarget") then
        -- Respect "Color player names by class". If OFF, ToT-Inline must use the configured global font color (no drift).
        local useClass = false
        local g = MSUF_DB and MSUF_DB.general
        if g and g.nameClassColor then
            useClass = true
        end
        if useClass then
            local _, classToken = UnitClass("targettarget")
            r, gCol, b = MSUF_GetClassBarColor(classToken)
        else
            if ns and ns.MSUF_GetConfiguredFontColor then
                r, gCol, b = ns.MSUF_GetConfiguredFontColor()
            else
                r, gCol, b = 1, 1, 1
            end
        end
    else
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("targettarget") then
            r, gCol, b = MSUF_GetNPCReactionColor("dead")
        else
            local reaction = UnitReaction and UnitReaction("player", "targettarget")
            if reaction then
                if reaction >= 5 then
                    r, gCol, b = MSUF_GetNPCReactionColor("friendly")
                elseif reaction == 4 then
                    r, gCol, b = MSUF_GetNPCReactionColor("neutral")
                else
                    r, gCol, b = MSUF_GetNPCReactionColor("enemy")
                end
            else
                r, gCol, b = MSUF_GetNPCReactionColor("enemy")
            end
        end
    end
    -- Apply separator token (render with spaces around it).
    local sepToken = (totConf and totConf.totInlineSeparator) or "|"
    if type(sepToken) ~= "string" or sepToken == "" then sepToken = "|" end
    sep:SetText(" " .. sepToken .. " ")
    sep:SetTextColor(0.7, 0.7, 0.7)
    txt:SetTextColor(r, gCol, b)
    local totName = UnitName and UnitName("targettarget")
    txt:SetText(totName or "")
    sep:Show()
    txt:Show()
end
function MSUF_UpdateTargetToTInlineNow()
    local targetFrame = UnitFrames and (UnitFrames.target or UnitFrames["target"])
    if not targetFrame then return end
    MSUF_RuntimeUpdateTargetToTInline(targetFrame)
end
_G.MSUF_RuntimeUpdateTargetToTInline = MSUF_RuntimeUpdateTargetToTInline
_G.MSUF_UpdateTargetToTInlineNow = MSUF_UpdateTargetToTInlineNow

-- ToT-Inline unified live-refresh entry point (coalesced, target-only).
-- Any settings change that can affect ToT-Inline (text/sep/font/color/layout) should route through this.
do
    local _msufToTInlineQueued = false
    local function _MSUF_ToTInline_Flush()
        _msufToTInlineQueued = false
        if _G.MSUF_UpdateTargetToTInlineNow then
            _G.MSUF_UpdateTargetToTInlineNow()
        end
    end

    function ns.MSUF_ToTInline_RequestRefresh(_reason)
        -- coalesce multiple requests into a single next-tick refresh
        if _msufToTInlineQueued then return end
        _msufToTInlineQueued = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0, _MSUF_ToTInline_Flush)
        else
            _MSUF_ToTInline_Flush()
        end
    end

    _G.MSUF_ToTInline_RequestRefresh = ns.MSUF_ToTInline_RequestRefresh
end
        if not _G.MSUF_UFCore_HasToTInlineDriver then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_TARGET_CHANGED")
        if f.RegisterUnitEvent then
            f:RegisterUnitEvent("UNIT_TARGET", "target")
            f:RegisterUnitEvent("UNIT_HEALTH", "targettarget")
            f:RegisterUnitEvent("UNIT_MAXHEALTH", "targettarget")
            f:RegisterUnitEvent("UNIT_POWER_UPDATE", "targettarget")
            f:RegisterUnitEvent("UNIT_MAXPOWER", "targettarget")
            f:RegisterUnitEvent("UNIT_DISPLAYPOWER", "targettarget")
            f:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "targettarget")
            f:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "targettarget")
            f:RegisterUnitEvent("UNIT_NAME_UPDATE", "targettarget")
            f:RegisterUnitEvent("UNIT_LEVEL", "targettarget")
            f:RegisterUnitEvent("UNIT_CONNECTION", "targettarget")
        else
            f:RegisterEvent("UNIT_TARGET")
            f:RegisterEvent("UNIT_HEALTH")
            f:RegisterEvent("UNIT_MAXHEALTH")
            f:RegisterEvent("UNIT_POWER_UPDATE")
            f:RegisterEvent("UNIT_MAXPOWER")
            f:RegisterEvent("UNIT_DISPLAYPOWER")
            f:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
            f:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
            f:RegisterEvent("UNIT_NAME_UPDATE")
            f:RegisterEvent("UNIT_LEVEL")
            f:RegisterEvent("UNIT_CONNECTION")
        end
        local MSUF_ToTEventFramePending = nil
        local function MSUF_ToTFlushScheduled()
            local frm = MSUF_ToTEventFramePending
            MSUF_ToTEventFramePending = nil
            if frm then
                frm._msufPending = false
            end
            MSUF_TryUpdateToT(false)
            if type(_G.MSUF_UpdateTargetToTInlineNow) == "function" then
                _G.MSUF_UpdateTargetToTInlineNow()
            end
        end

        f._msufPending = false
        f:SetScript("OnEvent", function(self, event, unit)
            if unit and unit ~= "target" and unit ~= "targettarget" then
                return
            end
            MSUF_MarkToTDirty()
            if not self._msufPending and C_Timer and C_Timer.After then
                self._msufPending = true
                MSUF_ToTEventFramePending = self
                C_Timer.After(0, MSUF_ToTFlushScheduled)
            else
                MSUF_TryUpdateToT(false)
            end
        end)
        -- ToT fallback ticker removed (event-driven ToT lane is stable)
        -- Keep a compatibility stub because older code may call this helper.
        local function MSUF_StopToTFallbackTicker()
            local t = _G.MSUF_ToTFallbackTicker
            if t and t.Cancel then
                t:Cancel()
            end
            _G.MSUF_ToTFallbackTicker = nil
        end
        _G.MSUF_EnsureToTFallbackTicker = function()
            MSUF_StopToTFallbackTicker()
        end
        MSUF_StopToTFallbackTicker()
    end
        end
if type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
    _G.MSUF_ApplyAllSettings_Immediate()
else
    ApplyAllSettings()
end

    if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
        _G.MSUF_ReanchorTargetCastBar()
    end
    if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
        _G.MSUF_ReanchorFocusCastBar()
    end
    if MSUF_InitFocusKickIcon then
        MSUF_InitFocusKickIcon()
    end
    if TargetFrameSpellBar and not TargetFrameSpellBar.MSUF_Hooked then
        TargetFrameSpellBar.MSUF_Hooked = true
        TargetFrameSpellBar:HookScript("OnShow", function()
            if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
                _G.MSUF_ReanchorTargetCastBar()
            end
        end)
        TargetFrameSpellBar:HookScript("OnEvent", function()
            if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
                _G.MSUF_ReanchorTargetCastBar()
            end
        end)
    end
    if FocusFrameSpellBar and not FocusFrameSpellBar.MSUF_Hooked then
        FocusFrameSpellBar.MSUF_Hooked = true
        FocusFrameSpellBar:HookScript("OnShow", function()
            if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
                _G.MSUF_ReanchorFocusCastBar()
            end
        end)
        FocusFrameSpellBar:HookScript("OnEvent", function()
            if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
                _G.MSUF_ReanchorFocusCastBar()
            end
        end)
    end
if PetCastingBarFrame then
    if not PetCastingBarFrame.MSUF_HideHooked then
        PetCastingBarFrame.MSUF_HideHooked = true
        hooksecurefunc(PetCastingBarFrame, "Show", function(self)
            self:Hide()
        end)
    end
    PetCastingBarFrame:Hide()
end
    C_Timer.After(0.5, MSUF_MakeBlizzardOptionsMovable)

    if type(_G.MSUF_RegisterOptionsCategoryLazy) == "function" then
        _G.MSUF_RegisterOptionsCategoryLazy()
    elseif type(_G.CreateOptionsPanel) ~= "function" then
        if not _G.MSUF_OptionsPanelMissingWarned then
            _G.MSUF_OptionsPanelMissingWarned = true
            print("|cffff0000MSUF:|r Options panel not loaded (CreateOptionsPanel missing). Check your .toc includes MSUF_Options_Core.lua.")
        end
    end
    if _G.MSUF_CheckAndRunFirstSetup then _G.MSUF_CheckAndRunFirstSetup() end
    if _G.MSUF_HookCooldownViewer then C_Timer.After(1, _G.MSUF_HookCooldownViewer) end
    C_Timer.After(1.1, MSUF_InitPlayerCastbarPreviewToggle)
    print("|cff7aa2f7MSUF|r: |cffc0caf5/msuf|r |cff565f89to open options|r  |cff565f89•|r  |cff9ece6aBuild 1.8r1|r  |cff565f89•|r  |cffc0caf5 Check out new Status Icon -|r  |cfff7768eReport bugs in the Discord.|r")

end, nil, true)


do
    if not _G.MSUF__BucketUpdateManager then
        _G.MSUF__BucketUpdateManager = {
            buckets = {},
        }
    end

    local M = _G.MSUF__BucketUpdateManager

    local function _GetBucket(interval)
        local key = tostring(interval or 0)
        local bucket = M.buckets[key]
        if bucket then return bucket end

        bucket = {
            interval = interval or 0,
            accum = 0,
            jobs = {},   -- [ownerFrame] = { [tag] = job }
            frame = CreateFrame("Frame"),
        }

        bucket._onUpdate = function(_, elapsed)
            elapsed = elapsed or 0
            bucket.accum = (bucket.accum or 0) + elapsed
            if bucket.accum < bucket.interval then return end

            local tick = bucket.accum
            bucket.accum = 0

            -- Iterate jobs
            for owner, tagMap in pairs(bucket.jobs) do
                if owner and owner.GetObjectType then
                    -- Visible gate (oUF-style)
                    local visible = owner.IsVisible and owner:IsVisible()
                    for _, job in pairs(tagMap) do
                        if job then
                            if job.allowHidden or visible then
                                local cb = job.cb
                                if cb then
                                    -- Do NOT pcall in hot path; keep it direct.
                                    cb(owner, tick)
                                end
                            end
                        end
                    end
                end
            end

            -- Auto-stop empty buckets (no CPU when unused)
            local hasAny = false
            for _, tagMap in pairs(bucket.jobs) do
                if tagMap and next(tagMap) then
                    hasAny = true
                    break
                end
            end
            if not hasAny then
                bucket.frame:SetScript("OnUpdate", nil)
                bucket.active = false
            end
        end

        bucket.frame:SetScript("OnUpdate", bucket._onUpdate)
        bucket.active = true
        M.buckets[key] = bucket
        return bucket
    end

    _G.MSUF_RegisterBucketUpdate = function(owner, interval, cb, tag, allowHidden)
        if not owner or not cb then return end
        interval = tonumber(interval) or 0
        if interval <= 0 then interval = 0.02 end
        tag = tag or "_"

        local bucket = _GetBucket(interval)
        if not bucket.active then
            -- restart
            bucket.accum = 0
            bucket.frame:SetScript("OnUpdate", bucket._onUpdate)
            bucket.active = true
        end

        bucket.jobs[owner] = bucket.jobs[owner] or {}
        bucket.jobs[owner][tag] = {
            cb = cb,
            allowHidden = allowHidden and true or false,
        }

        -- Mark back-reference for quick unregister
        owner._msufBucketJobs = owner._msufBucketJobs or {}
        owner._msufBucketJobs[tag] = interval

        -- Ensure bucket ticking
        if not bucket.frame:GetScript("OnUpdate") then
            bucket.accum = 0
            bucket.frame:SetScript("OnUpdate", bucket._onUpdate)
            bucket.active = true
        end
    end

    _G.MSUF_UnregisterBucketUpdate = function(owner, tag)
        if not owner then return end
        tag = tag or "_"

        local jobs = owner._msufBucketJobs
        local interval = jobs and jobs[tag]
        if not interval then return end

        local bucket = M.buckets[tostring(interval)]
        if bucket and bucket.jobs and bucket.jobs[owner] then
            bucket.jobs[owner][tag] = nil
            if not next(bucket.jobs[owner]) then
                bucket.jobs[owner] = nil
            end
        end

        jobs[tag] = nil
        if not next(jobs) then
            owner._msufBucketJobs = nil
        end
    end
end
