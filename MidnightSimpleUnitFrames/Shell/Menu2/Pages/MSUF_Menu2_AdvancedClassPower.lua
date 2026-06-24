-- Menu2 Advanced ClassPower page: builds class-resource, detached power, and player HP controls.
-- Runtime application is delegated to ClassPower refresh helpers and the shared apply queue.
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

-- Advanced Class Power page.
-- Builds the Menu2 controls for class-resource pips, detached power, player HP bridge, and
-- shape media. Runtime changes are delegated through ClassPower refresh helpers and the
-- general apply queue so preview and live frames stay in sync.
local floor = math.floor
local max = math.max
local min = math.min
local RefreshClassPowerInlinePreview = M.RefreshProxy()
local CallGlobal, Bars, BoolValue, NumValue, SetValue, DeepCopyTable, BuildTableControlSpecs, SwitchAt, SetControlEnabled = M.Pick(AP, [[CallGlobal Bars BoolValue NumValue SetValue DeepCopyTable BuildTableControlSpecs SwitchAt SetControlEnabled]])
local MoveWidget = W.MoveWidget or AP.MoveWidget
local SetControlsEnabled = W.SetControlsEnabled
local CPPreview = M.ClassPowerPreview or {}
local function AddTooltip(control, title, body) if M.AddTooltip then M.AddTooltip(control, title, body, { hook = true, owner = "ANCHOR_RIGHT" }) end end
local function ApplyClassPower()
    -- ClassPower spans several runtimes: core bars, textures, cooldown-manager width binding,
    -- inline preview, and global preview alpha. Keep the page fanout centralized here.
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    RefreshClassPowerInlinePreview()
    M.RequestGeneralApply("MSUF2_CLASSPOWER", { preview = true, applyAll = false })
end
local TextureValues = M.StatusBarTextureItems
local VT, VTP = M.ValueTextList, M.ValueTextPairs
local NormalizeClassPowerShape = CPPreview.NormalizeClassShape
local function NormalizeClassPowerShapeAlign(value)
    value = tostring(value or "CENTER"):upper()
    if value == "LEFT" or value == "RIGHT" then return value end
    return "CENTER"
end
local function NormalizePowerShape(value)
    return CPPreview.ResolvePowerShape(value)
end
local function NormalizeDetachedPowerShape(value)
    value = tostring(value or "FOLLOW_CLASS"):upper()
    if value == "FOLLOW_CLASS" or value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "FOLLOW_CLASS"
end
local function NormalizePlayerHPShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "FOLLOW_POWER" or value == "BAR" or value == "ROUND" or value == "CRYSTAL" or value == "ORB" then return value end
    return "BAR"
end
local function ResolvePlayerHPShape(bars, db)
    local value = NormalizePlayerHPShape(bars and bars.playerHPBarShape)
    if value ~= "FOLLOW_POWER" then return NormalizePowerShape(value) end
    local player = db and db.player or nil
    if not (player and player.powerBarDetached == true) then return "BAR" end
    return CPPreview.ResolvePowerShape(player.detachedPowerBarShape or "FOLLOW_CLASS", bars and bars.classPowerShape)
end
local SHAPE_PRESET_VALUES = VTP "classic=Classic Bar|dots=Clean Dots|gems=Gems|hex=Hex Pips|compact=Compact"
local SHAPE_PRESETS = {
    classic = { shape = "BAR", height = 4, gap = 0, bgAlpha = 0.30, filledAlpha = 1.00, emptyAlpha = 0.30 },
    dots = { shape = "CIRCLE", height = 10, gap = 3, bgAlpha = 0.24, filledAlpha = 1.00, emptyAlpha = 0.22 },
    gems = { shape = "DIAMOND", height = 12, gap = 4, bgAlpha = 0.24, filledAlpha = 1.00, emptyAlpha = 0.20 },
    hex = { shape = "HEX", height = 10, gap = 3, bgAlpha = 0.24, filledAlpha = 1.00, emptyAlpha = 0.20 },
    compact = { shape = "CIRCLE", height = 7, gap = 1, bgAlpha = 0.18, filledAlpha = 0.95, emptyAlpha = 0.16 },
}
local DETACHED_POWER_TEXT_PRESET_VALUES = VTP "OFF=Off|CURRENT=Current|CURMAX=Current / Max|PERCENT=Percent|CURPERCENT=Current + Percent|CURMAXPERCENT=Current / Max + Percent|CUSTOM=Custom Slots"
local PLAYER_HP_ANCHOR_VALUES = VTP "CLASS_TOP=Above Class Resource|CLASS_BOTTOM=Below Class Resource|POWER_TOP=Above Player Power|POWER_BOTTOM=Below Player Power"
local PLAYER_HP_WIDTH_VALUES = VTP "class=Class Resource|power=Player Power|player=Player Frame|custom=Custom"
local PLAYER_HP_SHAPE_VALUES = VTP "BAR=Bar|FOLLOW_POWER=Follow Player Power|ROUND=Round|CRYSTAL=Crystal|ORB=Orb"
local PLAYER_HP_COLOR_VALUES = VTP "GLOBAL=Global|CLASS=Class Color|DARK=Dark Mode|GRADIENT=HP Gradient"
local PLAYER_HP_TEXT_VALUES = VTP "PERCENT=Percent|CURRENT=Current|MAX=Max|DEFICIT=Deficit|CURMAX=Current / Max|CURPERCENT=Current / Percent|CURMAXPERCENT=Current / Max / Percent|MAXPERCENT=Max / Percent|PERCENTCUR=Percent / Current|PERCENTMAX=Percent / Max|PERCENTCURMAX=Percent / Current / Max|NONE=None"
local PLAYER_HP_SEPARATORS = VT("", "space", "-", "-", "/", "/", "\\", "\\", "|", "|", "<", "<", ">", ">", "~", "~", ":", ":")
local DETACHED_POWER_TEXT_PRESETS = M.KeySetFromWords "CURRENT CURMAX PERCENT CURPERCENT CURMAXPERCENT"
local function ApplyShapePreset(key)
    local preset = SHAPE_PRESETS[key]
    if not preset then return end
    local bars = Bars()
    bars.classPowerShape = preset.shape
    bars.classPowerHeight = preset.height
    bars.classPowerGap = preset.gap
    bars.classPowerOutline = 0
    bars.classPowerBgAlpha = preset.bgAlpha
    bars.classPowerFilledAlpha = preset.filledAlpha
    bars.classPowerEmptyAlpha = preset.emptyAlpha
    ApplyClassPower()
end
local function CurrentShapePreset()
    local bars = Bars()
    local shape = NormalizeClassPowerShape(bars.classPowerShape)
    local height = floor(tonumber(bars.classPowerHeight) or 4)
    local gap = floor(tonumber(bars.classPowerGap) or 0)
    local outline = floor(tonumber(bars.classPowerOutline) or 0)
    local bgAlpha = tonumber(bars.classPowerBgAlpha) or 0.30
    local filledAlpha = tonumber(bars.classPowerFilledAlpha) or 1.00
    local emptyAlpha = tonumber(bars.classPowerEmptyAlpha) or 0.30
    for key, preset in pairs(SHAPE_PRESETS) do
        if shape == preset.shape
            and height == preset.height
            and gap == preset.gap
            and outline == 0
            and math.abs(bgAlpha - preset.bgAlpha) < 0.001
            and math.abs(filledAlpha - preset.filledAlpha) < 0.001
            and math.abs(emptyAlpha - preset.emptyAlpha) < 0.001
        then
            return key
        end
    end
    return nil
end
local CLASS_POWER_PREVIEW_SPECS = {
    { key = "deathknight_runes", label = "Death Knight - Runes", token = "RUNES", mode = "rune", segments = 6, value = 3, previewText = "3", runeDuration = 10 },
    { key = "demonhunter_devourer", label = "Demon Hunter - Soul Fragments", token = "SOUL_FRAGMENTS", mode = "aura_single", segments = 1, value = 0.58, previewText = "2" },
    { key = "demonhunter_vengeance", label = "Demon Hunter - Vengeance Fragments", token = "SOUL_FRAGMENTS_VENG", mode = "aura_segmented", segments = 6, value = 4, previewText = "4 / 6" },
    { key = "druid_feral", label = "Druid - Feral Combo Points", token = "COMBO_POINTS", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "druid_balance", label = "Druid - Balance (no class bar)", mode = "none", enabled = false },
    { key = "evoker_essence", label = "Evoker - Essence", token = "ESSENCE", mode = "segmented", segments = 6, value = 4, previewText = "4" },
    { key = "evoker_augmentation_ebon", label = "Evoker - Augmentation Ebon Might", token = "EBON_MIGHT", mode = "timer_bar", segments = 1, value = 0.58, previewText = "12.0s" },
    { key = "hunter_survival_tip", label = "Hunter - Survival Tip of the Spear", token = "TIP_OF_THE_SPEAR", mode = "aura_segmented", segments = 3, value = 2, previewText = "2" },
    { key = "mage_arcane", label = "Mage - Arcane Charges", token = "ARCANE_CHARGES", mode = "segmented", segments = 4, value = 3, previewText = "3" },
    { key = "monk_brewmaster", label = "Monk - Brewmaster Stagger", token = "STAGGER_YELLOW", mode = "stagger", segments = 1, value = 0.42, previewText = "14K" },
    { key = "monk_windwalker", label = "Monk - Windwalker Chi", token = "CHI", mode = "segmented", segments = 6, value = 4, previewText = "4" },
    { key = "paladin_holy_power", label = "Paladin - Holy Power", token = "HOLY_POWER", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "priest_shadow", label = "Priest - Shadow Insanity", token = "INSANITY", mode = "continuous", segments = 1, value = 0.62, previewText = "62 / 100" },
    { key = "rogue_combo", label = "Rogue - Combo Points", token = "COMBO_POINTS", mode = "segmented", segments = 7, value = 5, previewText = "5", chargedSlots = { [1] = true, [2] = true } },
    { key = "shaman_elemental", label = "Shaman - Elemental Maelstrom", token = "MAELSTROM", mode = "continuous", segments = 1, value = 0.68, previewText = "68 / 100" },
    { key = "shaman_enhancement", label = "Shaman - Enhancement Maelstrom Weapon", token = "MAELSTROM", mode = "aura_segmented", segments = 10, value = 7, previewText = "7", threshold = 5, thresholdToken = "MAELSTROM_ABOVE_5" },
    { key = "warlock_soul_shards", label = "Warlock - Soul Shards", token = "SOUL_SHARDS", mode = "segmented", segments = 5, value = 3, previewText = "3" },
    { key = "warlock_destruction", label = "Warlock - Destruction Soul Shards", token = "SOUL_SHARDS", mode = "fractional", segments = 5, value = 3.4, previewText = "3.4" },
    { key = "warrior_whirlwind", label = "Warrior - Whirlwind Stacks", token = "WHIRLWIND", mode = "aura_segmented", segments = 4, value = 2, previewText = "2" },
}
local CLASS_POWER_PREVIEW_BY_KEY = {}
local CLASS_POWER_PREVIEW_VALUES = {}
for i = 1, #CLASS_POWER_PREVIEW_SPECS do
    local spec = CLASS_POWER_PREVIEW_SPECS[i]
    CLASS_POWER_PREVIEW_BY_KEY[spec.key] = spec
    CLASS_POWER_PREVIEW_VALUES[i] = { value = spec.key, text = spec.label }
end
local function NormalizeClassPowerPreviewSpecKey(key)
    key = tostring(key or "rogue_combo")
    return CLASS_POWER_PREVIEW_BY_KEY[key] and key or "rogue_combo"
end
local CLASS_POWER_PREVIEW_CLASS_BY_PREFIX = { deathknight = "DEATHKNIGHT", demonhunter = "DEMONHUNTER", druid = "DRUID", evoker = "EVOKER", hunter = "HUNTER", mage = "MAGE", monk = "MONK", paladin = "PALADIN", priest = "PRIEST", rogue = "ROGUE", shaman = "SHAMAN", warlock = "WARLOCK", warrior = "WARRIOR" }
local function ClassPowerPreviewClassTokenForSpec(spec)
    if spec and spec.classToken then return tostring(spec.classToken):upper() end
    if spec and spec.class then return tostring(spec.class):upper() end
    local key = tostring(spec and spec.key or M.GetClassPowerPreviewSpecKey())
    local prefix = key:match("^([^_]+)")
    return prefix and CLASS_POWER_PREVIEW_CLASS_BY_PREFIX[prefix] or nil
end
local function RequestClassPowerPreviewRefresh()
    RefreshClassPowerInlinePreview()
    if type(_G.MSUF_UFPreview_RequestRefresh) == "function" then
        _G.MSUF_UFPreview_RequestRefresh("MSUF2_CLASSPOWER_PREVIEW_SPEC")
    elseif type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF2_CLASSPOWER_PREVIEW_SPEC", { preview = true, applyAll = false, notify = false })
    end
end
function M.GetClassPowerPreviewSpecKey()
    return NormalizeClassPowerPreviewSpecKey(M._msuf2ClassPowerPreviewSpecKey or "rogue_combo")
end
function M.SetClassPowerPreviewSpecKey(key)
    key = NormalizeClassPowerPreviewSpecKey(key)
    if M._msuf2ClassPowerPreviewSpecKey == key then return true, key end
    M._msuf2ClassPowerPreviewSpecKey = key
    RequestClassPowerPreviewRefresh()
    return true, key
end
function M.GetClassPowerPreviewSpec()
    local key = M.GetClassPowerPreviewSpecKey()
    return CLASS_POWER_PREVIEW_BY_KEY[key]
end
function M.GetClassPowerPreviewClassToken()
    return ClassPowerPreviewClassTokenForSpec(M.GetClassPowerPreviewSpec())
end
M.ClassPowerPreviewSpecValues = CLASS_POWER_PREVIEW_VALUES
M.ClassPowerPreviewSpecs = CLASS_POWER_PREVIEW_BY_KEY
RefreshClassPowerInlinePreview = RefreshClassPowerInlinePreview(function()
    local preview = M._msuf2ClassPowerInlinePreview
    if preview and preview.Refresh then preview:Refresh() end
end)
local function BindBarsAlphaPercent(ctx, section, label, key, default, apply, step)
    local slider = W.Slider(section, label, 0, 100, step or 5, 300)
    M.BindNumberWidget(ctx, slider,
        function()
            local value = NumValue(Bars(), key, default or 0)
            if value <= 1 then value = value * 100 end
            if value < 0 then value = 0 elseif value > 100 then value = 100 end
            return floor(value + 0.5)
        end,
        function(v)
            v = tonumber(v) or ((default or 0) * 100)
            if v < 0 then v = 0 elseif v > 100 then v = 100 end
            SetValue(Bars(), key, v / 100, apply)
        end,
        (default or 0) * 100, { step = step or 5, roundStep = true })
    return slider
end
local APPLY_DETACHED_POWER = { preview = true, power = true, applyAll = false }
local APPLY_DETACHED_POWER_TEXT = { preview = true, power = true, text = true, applyAll = false }
local APPLY_PLAYER_HP = { preview = true, applyAll = false }
local APPLY_PLAYER_HP_TEXT = { preview = true, text = true, applyAll = false }
local function ApplyClassPowerPage(reason, flags, ...)
    for i = 1, select("#", ...) do CallGlobal(select(i, ...)) end
    RefreshClassPowerInlinePreview()
    M.RequestGeneralApply(reason, flags)
end
local function ApplyDetachedPowerBar()
    ApplyClassPowerPage("MSUF2_DETACHED_POWER_BAR", APPLY_DETACHED_POWER,
        "MSUF_DetachedPowerBar_RefreshTextures", "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_ClassPower_PlayerHP_Refresh")
end
local function ApplyDetachedPowerText()
    ApplyClassPowerPage("MSUF2_DETACHED_POWER_TEXT", APPLY_DETACHED_POWER_TEXT,
        "MSUF_DetachedPowerBar_RefreshTextures", "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_ClassPower_PlayerHP_Refresh", "MSUF_UpdateAllFonts_Immediate")
end
local function ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    ApplyDetachedPowerBar()
end
local function ApplyPlayerHPBar()
    ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP", APPLY_PLAYER_HP, "MSUF_ClassPower_PlayerHP_Refresh")
end
local function ApplyPlayerHPTextures()
    ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP_TEXTURES", APPLY_PLAYER_HP, "MSUF_ClassPower_PlayerHP_RefreshTextures")
end
local function ApplyPlayerHPText()
    ApplyClassPowerPage("MSUF2_CLASSPOWER_PLAYER_HP_TEXT", APPLY_PLAYER_HP_TEXT, "MSUF_ClassPower_PlayerHP_Refresh", "MSUF_UpdateAllFonts_Immediate")
end
local function Player()
    local db = M.EnsureDB()
    db.player = db.player or {}
    return db.player
end
local function NormalizeDetachedPowerTextPreset(player)
    player = player or Player()
    if player.showPower == false then return "OFF" end
    local left = tostring(player.powerTextLeft or "NONE"):upper()
    local center = tostring(player.powerTextCenter or player.powerTextMode or "CURPERCENT"):upper()
    local right = tostring(player.powerTextRight or "NONE"):upper()
    if left == "NONE" and right == "NONE" and DETACHED_POWER_TEXT_PRESETS[center] then return center end
    return "CUSTOM"
end
local function SetDetachedPowerTextPreset(value)
    value = tostring(value or "CURPERCENT"):upper()
    if value == "CUSTOM" then return end
    local player = Player()
    if value == "OFF" then
        player.showPower = false
        return
    end
    if not DETACHED_POWER_TEXT_PRESETS[value] then value = "CURPERCENT" end
    player.showPower = true
    player.detachedPowerBarTextOnBar = true
    player.powerTextLeft = "NONE"
    player.powerTextCenter = value
    player.powerTextRight = "NONE"
    player.powerTextMode = value
end
local QUICK_SETUP_FLAG = "quickSetupClassBarOffered"
local QUICK_CP_HEIGHT = 4
local QUICK_DPB_HEIGHT = 6
local QUICK_DPB_GAP = 2
local QUICK_CDM_GAP = 2
local QUICK_FALLBACK_Y_FRAC = 0.60
local QUICK_BARS_KEYS = M.WordList [[
showClassPower classPowerShape classPowerShapeAlign classPowerShowText classPowerAnchorToCooldown classPowerWidthMode showEleMaelstrom showEbonMight showChargedComboPoints
runeShowTime runeShowTimeText classPowerOffsetX classPowerOffsetY classPowerOutline detachedPowerBarWidthMode detachedPowerBarOutline
]]
local QUICK_PLAYER_KEYS = M.WordList [[
powerBarDetached detachedPowerBarShape detachedPowerOrbSize detachedPowerBarSyncClassPower detachedPowerBarAnchorToClassPower detachedPowerBarTextOnBar detachedPowerBarOffsetX detachedPowerBarOffsetY
hpPowerTextOverride hpTextMode textLeft textCenter textRight powerTextMode powerTextLeft powerTextCenter powerTextRight hpTextSeparator powerTextSeparator absorbTextMode absorbAnchorMode healPredAnchorMode
]]
local quickSetupUndoSnapshot
local quickSetupFirstRunChecked = false
local function QuickTr(text)
    return (M.Tr and M.Tr(text)) or text
end
local function QuickCopyValue(value)
    if type(value) ~= "table" then return value end
    if type(DeepCopyTable) == "function" then return DeepCopyTable(value) end
    if type(CopyTable) == "function" then return CopyTable(value) end
    local out = {}
    for k, v in pairs(value) do out[k] = QuickCopyValue(v) end
    return out
end
local function QuickAssign(target, values)
    for key, value in pairs(values) do target[key] = value end
end
local function QuickAssignOffsets(target, offsets, values, asBool)
    for key, offsetKey in pairs(values) do
        local value = offsets[offsetKey]
        target[key] = asBool and (value and true or false) or value
    end
end
local function QuickFillDefaultsFromGeneral(player, general, values)
    for key, generalKey in pairs(values) do
        if player[key] == nil then player[key] = general[generalKey] end
    end
end
local function QuickSeedTextSlots(player, leftKey, centerKey, rightKey, modeKey, fallback)
    if player[leftKey] ~= nil or player[centerKey] ~= nil or player[rightKey] ~= nil then return end
    player[leftKey], player[centerKey], player[rightKey] = "NONE", "NONE", player[modeKey] or fallback or "CURPERCENT"
end
local function QuickSnapshot()
    local db = M.EnsureDB()
    local snap = { bars = {}, player = {} }
    local bars = db.bars or {}
    local player = db.player or {}
    for i = 1, #QUICK_BARS_KEYS do
        local key = QUICK_BARS_KEYS[i]
        snap.bars[key] = QuickCopyValue(bars[key])
    end
    for i = 1, #QUICK_PLAYER_KEYS do
        local key = QUICK_PLAYER_KEYS[i]
        snap.player[key] = QuickCopyValue(player[key])
    end
    return snap
end
local function QuickRestore(snap)
    if type(snap) ~= "table" then return end
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    db.player = db.player or {}
    if type(snap.bars) == "table" then
        for i = 1, #QUICK_BARS_KEYS do
            local key = QUICK_BARS_KEYS[i]
            db.bars[key] = QuickCopyValue(snap.bars[key])
        end
    end
    if type(snap.player) == "table" then
        for i = 1, #QUICK_PLAYER_KEYS do
            local key = QUICK_PLAYER_KEYS[i]
            db.player[key] = QuickCopyValue(snap.player[key])
        end
    end
end
local function QuickGetVisibleCDM()
    local ecv = (type(_G.MSUF_GetEffectiveCooldownFrame) == "function" and _G.MSUF_GetEffectiveCooldownFrame("EssentialCooldownViewer"))
        or _G.EssentialCooldownViewer
    if ecv and ecv.IsShown and ecv:IsShown() and ecv.GetHeight and ecv.GetCenter then
        local h = ecv:GetHeight()
        if type(h) == "number" and h > 0 then return ecv end
    end
    return nil
end
local function QuickPlayerFrame()
    return (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player) or _G.MSUF_player
end
local function QuickClassPowerVisible()
    local c = _G.MSUF_ClassPowerContainer
    return c and c.IsShown and c:IsShown()
end
local function QuickCalcCPAboveCDM(ecv)
    local bars = Bars()
    local player = M.EnsureDB().player or {}
    local cpH = tonumber(bars.classPowerHeight) or QUICK_CP_HEIGHT
    local dpbH = tonumber(player.detachedPowerBarHeight) or QUICK_DPB_HEIGHT
    local ecvH = (ecv and ecv.GetHeight and ecv:GetHeight()) or 0
    return {
        cpOffsetX = 0,
        cpOffsetY = math.ceil(ecvH + QUICK_CDM_GAP + cpH + QUICK_DPB_GAP + dpbH),
        dpbOffsetX = 0,
        dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = true,
        anchorDPBtoCP = true,
    }
end
local function QuickCalcDPBAboveCDMNoCP(ecv)
    local player = M.EnsureDB().player or {}
    local dpbH = tonumber(player.detachedPowerBarHeight) or QUICK_DPB_HEIGHT
    local fallback = {
        cpOffsetX = 0, cpOffsetY = 0,
        dpbOffsetX = 0, dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = true, anchorDPBtoCP = true,
    }
    local pf = QuickPlayerFrame()
    if not (pf and pf.GetLeft and pf.GetBottom and pf.GetEffectiveScale and ecv and ecv.GetCenter and ecv.GetTop and ecv.GetWidth) then return fallback end
    local pfLeft, pfBottom = pf:GetLeft(), pf:GetBottom()
    if not (pfLeft and pfBottom) then return fallback end
    local pfScale = (pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
    local ecvScale = (ecv.GetEffectiveScale and ecv:GetEffectiveScale()) or 1
    if pfScale <= 0 then pfScale = 1 end
    if ecvScale <= 0 then ecvScale = 1 end
    local ecvCenterX = (select(1, ecv:GetCenter()) or 0) * ecvScale
    local ecvTop = (ecv:GetTop() or 0) * ecvScale
    local ecvWidth = (ecv:GetWidth() or 200) * ecvScale
    local targetLeft = ecvCenterX - (ecvWidth * 0.5)
    local targetTop = ecvTop + QUICK_CDM_GAP * pfScale + dpbH * pfScale
    return {
        cpOffsetX = 0,
        cpOffsetY = 0,
        dpbOffsetX = floor((targetLeft - pfLeft * pfScale) / pfScale + 0.5),
        dpbOffsetY = floor((targetTop - pfBottom * pfScale) / pfScale + 0.5),
        anchorCPtoCDM = true,
        anchorDPBtoCP = false,
    }
end
local function QuickCalcScreenCenter()
    local fallback = {
        cpOffsetX = 0, cpOffsetY = 0,
        dpbOffsetX = 0, dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = false, anchorDPBtoCP = true,
    }
    local pf = QuickPlayerFrame()
    if not (pf and pf.GetLeft and pf.GetTop and pf.GetWidth and pf.GetEffectiveScale) then return fallback end
    local pfLeft, pfTop, pfW = pf:GetLeft(), pf:GetTop(), pf:GetWidth()
    if not (pfLeft and pfTop and pfW) then return fallback end
    local pfScale = (pf:GetEffectiveScale()) or 1
    if pfScale <= 0 then pfScale = 1 end
    local uip = UIParent
    local uipScale = (uip and uip.GetEffectiveScale and uip:GetEffectiveScale()) or 1
    if uipScale <= 0 then uipScale = 1 end
    local screenW = (uip and uip.GetWidth and uip:GetWidth()) or 1920
    local screenH = (uip and uip.GetHeight and uip:GetHeight()) or 1080
    local cpW = floor((pfW or 275) + 0.5)
    if cpW < 30 then cpW = 275 end
    return {
        cpOffsetX = floor((screenW * uipScale * 0.5) / pfScale - pfLeft - 2 - cpW * 0.5 + 0.5),
        cpOffsetY = floor((screenH * uipScale * QUICK_FALLBACK_Y_FRAC) / pfScale - pfTop + 2 + 0.5),
        dpbOffsetX = 0,
        dpbOffsetY = -QUICK_DPB_GAP,
        anchorCPtoCDM = false,
        anchorDPBtoCP = true,
    }
end
local function QuickApplyPhase1(offsets)
    local db = M.EnsureDB()
    db.bars = db.bars or {}
    db.player = db.player or {}
    local bars = db.bars
    local player = db.player
    local general = db.general or {}
    QuickAssign(bars, {
        showClassPower = true, classPowerShowText = true, classPowerWidthMode = "cooldown", detachedPowerBarWidthMode = "cooldown",
        showEleMaelstrom = true, showEbonMight = true, showChargedComboPoints = true, runeShowTime = true, runeShowTimeText = true,
        classPowerOutline = 1, detachedPowerBarOutline = 1,
    })
    QuickAssignOffsets(bars, offsets, { classPowerAnchorToCooldown = "anchorCPtoCDM" }, true)
    QuickAssignOffsets(bars, offsets, { classPowerOffsetX = "cpOffsetX", classPowerOffsetY = "cpOffsetY" })
    QuickAssign(player, { powerBarDetached = true, detachedPowerBarTextOnBar = true, hpPowerTextOverride = true })
    QuickAssignOffsets(player, offsets, {
        detachedPowerBarSyncClassPower = "anchorDPBtoCP",
        detachedPowerBarAnchorToClassPower = "anchorDPBtoCP",
    }, true)
    QuickAssignOffsets(player, offsets, { detachedPowerBarOffsetX = "dpbOffsetX", detachedPowerBarOffsetY = "dpbOffsetY" })
    QuickFillDefaultsFromGeneral(player, general, {
        hpTextMode = "hpTextMode", powerTextMode = "powerTextMode", hpTextSeparator = "hpTextSeparator",
        absorbTextMode = "absorbTextMode", absorbAnchorMode = "absorbAnchorMode", healPredAnchorMode = "healPredAnchorMode",
    })
    QuickSeedTextSlots(player, "textLeft", "textCenter", "textRight", "hpTextMode", general.hpTextMode)
    QuickSeedTextSlots(player, "powerTextLeft", "powerTextCenter", "powerTextRight", "powerTextMode", general.powerTextMode)
    if player.powerTextSeparator == nil then player.powerTextSeparator = general.powerTextSeparator or general.hpTextSeparator end
    QuickAssign(player, { powerTextMode = "CURRENT", powerTextLeft = "NONE", powerTextCenter = "CURRENT", powerTextRight = "NONE" })
end
local function QuickApplyPhase2NoCP(offsets)
    local db = M.EnsureDB()
    db.player = db.player or {}
    local player = db.player
    player.detachedPowerBarSyncClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarOffsetX = offsets.dpbOffsetX
    player.detachedPowerBarOffsetY = offsets.dpbOffsetY
end
local function QuickRefreshAll(reason)
    ApplyClassPower()
    ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_UFCore_NotifyConfigChanged", nil, false, true, reason or "ClassPowerQuickSetup")
end
local function QuickMarkOffered()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = true
end
local function QuickWasOffered()
    local db = M.EnsureDB()
    return db.general and db.general[QUICK_SETUP_FLAG] == true
end
local function QuickEnsurePopups()
    if not _G.StaticPopupDialogs then return end
    M.InstallStaticPopup("MSUF2_CLASSPOWER_QUICK_RESULT", {
        text = "%s", button1 = OKAY, button2 = QuickTr("Undo"), hideOnEscape = false,
        OnAccept = function() quickSetupUndoSnapshot = nil end,
        OnCancel = function()
            if not quickSetupUndoSnapshot then return end
            QuickRestore(quickSetupUndoSnapshot)
            quickSetupUndoSnapshot = nil
            QuickRefreshAll("ClassPowerQuickSetupUndo")
        end,
    })
    M.InstallStaticPopup("MSUF2_CLASSPOWER_QUICK_OFFER", {
        text = QuickTr("Welcome to Class Resources!\n\n"
            .. "Would you like to automatically set up a\n"
            .. "detached Class Bar positioned above your\n"
            .. "Essential Cooldowns?\n\n"
            .. "This configures class resources, power bar,\n"
            .. "anchoring and width matching in one click.\n\n"
            .. "You can always run this later via the\n"
            .. "|cff00ff00Quick Setup: Class Bar|r button below."),
        button1 = QuickTr("Setup Now"), button2 = QuickTr("Not Now"), hideOnEscape = true, showAlert = true,
        OnAccept = function()
            QuickMarkOffered()
            C_Timer.After(0.05, function()
                if _G.MSUF2_ClassPowerQuickSetup then _G.MSUF2_ClassPowerQuickSetup() end
            end)
        end,
        OnCancel = QuickMarkOffered,
    })
end
local function ExecuteQuickSetup()
    QuickEnsurePopups()
    QuickMarkOffered()
    local ecv = QuickGetVisibleCDM()
    local offsets = ecv and QuickCalcCPAboveCDM(ecv) or QuickCalcScreenCenter()
    quickSetupUndoSnapshot = QuickSnapshot()
    QuickApplyPhase1(offsets)
    ApplyClassPower()
    local popupText
    if ecv and not QuickClassPowerVisible() then
        QuickApplyPhase2NoCP(QuickCalcDPBAboveCDMNoCP(ecv))
        popupText = "Quick Setup applied!\n\nPower Bar is positioned above\nEssential Cooldowns.\n\nYour spec has no class resource bar.\nIf you respec, it will appear automatically.\n\nUse Edit Mode for fine-tuning."
    elseif ecv then
        popupText = "Quick Setup applied!\n\nClass Power + Power Bar are now\npositioned above Essential Cooldowns.\n\nUse Edit Mode for fine-tuning."
    else
        popupText = "Quick Setup applied!\n\nClass Power + Power Bar are detached\nand positioned at screen center.\n\nEssential Cooldowns not detected.\nEnable it for automatic anchoring.\n\nUse Edit Mode for fine-tuning."
    end
    QuickRefreshAll("ClassPowerQuickSetup")
    if StaticPopup_Show then StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_RESULT", QuickTr(popupText)) end
end
_G.MSUF2_ClassPowerQuickSetup = ExecuteQuickSetup
ExportPublic("MSUF_QuickSetup_ResetFirstRun", function()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = nil
    quickSetupFirstRunChecked = false
end)
local function MaybeOfferQuickSetup()
    if quickSetupFirstRunChecked or QuickWasOffered() then return end
    quickSetupFirstRunChecked = true
    QuickEnsurePopups()
    C_Timer.After(0.15, function()
        if not QuickWasOffered() and StaticPopup_Show then StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_OFFER") end
    end)
end
local function BuildInlineClassPowerPreview(ctx, b)
    -- ClassPower preview was split into Preview/MSUF_Menu2_ClassPowerPreview.lua.
    -- Keeping only this loader guard prevents a second renderer from drifting out of sync.
    if ctx and ctx.hiddenBuild then
        local section = b:Section("Preview", 64)
        W.Text(section, "Class resource preview is built when this page is opened.", 14, -38, ctx.width - 28, T.colors.muted)
        return section
    end
    local preview = M.ClassPowerStackPreview and M.ClassPowerStackPreview.Create
    if type(preview) == "function" then return preview(ctx, b) end
    return b:Section("Preview unavailable", 64)
end
local function BuildClassPower(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Class Resources", "Class resource first; optional attached Player Power, second HP and alternative mana bars below.", 94)
    local previewW = min(330, max(220, (ctx.width or 900) - 380))
    local previewDrop = W.Dropdown(head, "Preview resource", CLASS_POWER_PREVIEW_VALUES, previewW)
    MoveWidget(previewDrop, head, 14, -48, previewW)
    previewDrop:SetOnValueChanged(function(value)
        M.SetClassPowerPreviewSpecKey(value)
        previewDrop:SetValue(M.GetClassPowerPreviewSpecKey())
    end)
    previewDrop:SetValue(M.GetClassPowerPreviewSpecKey())
    AddTooltip(previewDrop, "Class Resource Preview", "Shows the selected class/spec resource below without changing your character, spec or saved settings.")
    M.TrackRefresh(ctx, function() previewDrop:SetValue(M.GetClassPowerPreviewSpecKey()) end)
    local colors = T.Button(head, "Class Color", 112, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(colors) end
    colors:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -14)
    colors:SetScript("OnClick", function() M.SelectPage("opt_colors") end)
    local edit = T.Button(head, "MSUF Edit Mode", 128, 24)
    if W.StyleTopActionButton then W.StyleTopActionButton(edit) end
    edit:SetPoint("RIGHT", colors, "LEFT", -10, 0)
    local quickSetup = T.Button(head, "Quick Setup: Class Bar", 158, 24)
    if W.StyleTopSuccessButton then
        W.StyleTopSuccessButton(quickSetup)
    elseif W.StyleTopActionButton then
        W.StyleTopActionButton(quickSetup)
    end
    quickSetup:SetPoint("TOPRIGHT", head, "TOPRIGHT", -14, -54)
    quickSetup:SetScript("OnClick", ExecuteQuickSetup)
    quickSetup:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(QuickTr("Quick Setup: Detached Class Bar"), 1, 1, 1)
        GameTooltip:AddLine(QuickTr("One-click setup for a ready-to-use class bar:"), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(QuickTr("Detaches power bar from unit frame"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(QuickTr("Positions class bar ABOVE Essential Cooldowns"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(QuickTr("Match width: Essential Cooldowns"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(QuickTr("Syncs & anchors power bar to class resources"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        local ecv = QuickGetVisibleCDM()
        if ecv and QuickClassPowerVisible() then
            GameTooltip:AddLine(QuickTr("CDM + Class Power detected"), 0.3, 0.9, 0.3)
        elseif ecv then
            GameTooltip:AddLine(QuickTr("CDM detected (no class resource for this spec)"), 0.9, 0.8, 0.3)
        else
            GameTooltip:AddLine(QuickTr("CDM not visible - will center on screen"), 0.9, 0.7, 0.3)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(QuickTr("Click to apply. Undo available in popup."), 0.5, 0.8, 0.5)
        GameTooltip:Show()
    end)
    quickSetup:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    if W.CreatePageResetButton then W.CreatePageResetButton(ctx, head, quickSetup, { width = 88 }) end
    M.WireEditModeButton(ctx, edit)
    BuildInlineClassPowerPreview(ctx, b)
    local layoutWidth = ctx.width or 900
    local compactLayout = layoutWidth < 620
    b:Header("Class Resource Bar", "Combo Points, Runes, Holy Power, Chi and similar class-specific resources.", 64)
    local display = b:CollapsibleSection("classpower_display", "Class Resource Layout", compactLayout and 820 or 540, true)
    local cpControls, textControls, dpbControls, dpbPlayerControls = {}, {}, {}, {}
    local phpControls, phpTextControls, phpCustomTextControls, phpTextPositionControls = {}, {}, {}, {}
    local phpManualControls, phpOrbControls, phpTextureControls, altManaControls = {}, {}, {}, {}
    local RefreshClassPowerControls = M.RefreshProxy()
    local AddControls, AddNamedControls = M.AppendValues, M.AppendNamedValues
    local function PlaceColumn(parent, x, y, step, width, titleJustify, ...)
        for i = 1, select("#", ...) do
            MoveWidget(select(i, ...), parent, x, y - ((i - 1) * step), width, titleJustify)
        end
    end
    local boundControlKinds = {
        alpha = function(_, parent, _, defaultApply, spec)
            return BindBarsAlphaPercent(ctx, parent, spec[3], spec[4], spec[5], spec[6] or defaultApply, spec[7])
        end,
        nilDefaultDropdown = function(_, parent, source, defaultApply, spec)
            local control, key, default, apply = W.Dropdown(parent, spec[3], spec[4], spec[5]), spec[6], spec[7], spec[8] or defaultApply
            M.BindDropdownWidget(ctx, control, function() return source()[key] or default end, function(v) source()[key] = (v ~= default) and v or nil; apply() end)
            return control
        end,
        playerShape = function(_, parent, _, defaultApply, spec)
            local control = W.Dropdown(parent, spec[3], spec[4], spec[5])
            local apply = spec[6] or defaultApply
            M.BindDropdownWidget(ctx, control,
                function() return NormalizeDetachedPowerShape(Player().detachedPowerBarShape) end,
                function(v)
                    local player = Player()
                    player.detachedPowerBarShape = NormalizeDetachedPowerShape(v)
                    if player.detachedPowerBarShape == "ORB" and player.detachedPowerOrbSize == nil then player.detachedPowerOrbSize = 54 end
                    apply()
                    RefreshClassPowerControls()
                end)
            return control
        end,
        detachedTextPreset = function(_, parent, _, defaultApply, spec)
            local control = W.Dropdown(parent, spec[3], spec[4], spec[5])
            local apply = spec[6] or defaultApply
            M.BindDropdownWidget(ctx, control,
                function() return NormalizeDetachedPowerTextPreset(Player()) end,
                function(v)
                    SetDetachedPowerTextPreset(v)
                    apply()
                    RefreshClassPowerControls()
                end)
            return control
        end,
    }
    local function BuildBoundControls(parent, source, defaultApply, specs)
        return BuildTableControlSpecs(ctx, parent, source, defaultApply, specs, boundControlKinds)
    end
    local function WithClassPowerRefresh(apply)
        return function(...)
            apply(...)
            RefreshClassPowerControls()
        end
    end
    local ApplyClassPowerAndRefresh = WithClassPowerRefresh(ApplyClassPower)
    local cpEnable = SwitchAt(ctx, display, "Class Resource", 32, -64, 180, Bars, "showClassPower", true, ApplyClassPowerAndRefresh)
    local cpPreset = W.Dropdown(display, "Shape Presets", SHAPE_PRESET_VALUES, 300)
    M.BindDropdownWidget(ctx, cpPreset, CurrentShapePreset, WithClassPowerRefresh(ApplyShapePreset))
    AddTooltip(cpPreset, "Shape Presets", "Applies a ready style by setting only Shape, Height/Pip size, Pip gap, Outline off and opacity values.")
    local cpShapeQuick = W.Segment(display, "Quick shape", VT("BAR", "Bar", "CIRCLE", "Dot", "DIAMOND", "Gem", "HEX", "Hex"), 300)
    M.BindSegment(ctx, cpShapeQuick,
        function() return NormalizeClassPowerShape(Bars().classPowerShape) end,
        function(value)
            Bars().classPowerShape = NormalizeClassPowerShape(value)
            ApplyClassPowerAndRefresh()
        end)
    local cp = BuildBoundControls(display, Bars, ApplyClassPower, {
        { "shape", "dropdown", "Shape", VT("BAR", "Bar", "CIRCLE", "Circle", "DIAMOND", "Diamond", "HEX", "Hex"), 260, "classPowerShape", "BAR", ApplyClassPowerAndRefresh },
        { "height", "slider", "Height", 1, 40, 1, 300, "classPowerHeight", 4 },
        { "widthMode", "dropdown", "Width mode", VT("player", "Player frame", "auto_pips", "Auto fit pips", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns", "tracked_buffs", "Tracked Buffs", "custom", "Custom"), 260, "classPowerWidthMode", "player", ApplyClassPowerAndRefresh },
        { "width", "slider", "Width", 30, 800, 1, 300, "classPowerWidth", 0 },
        { "x", "slider", "Offset X", -800, 800, 1, 300, "classPowerOffsetX", 0 },
        { "y", "slider", "Offset Y", -800, 800, 1, 300, "classPowerOffsetY", 0 },
        { "level", "slider", "Frame level", 0, 30, 1, 300, "classPowerFrameLevelOffset", 5 },
    })
    AddTooltip(cp.widthMode, "Width Mode", "Auto fit pips is active only for Circle, Diamond and Hex. It uses pip count x pip size plus gaps.")
    local cpAlign = W.Segment(display, "Shape alignment", VT("LEFT", "Left", "CENTER", "Center", "RIGHT", "Right"), 300)
    M.BindSegment(ctx, cpAlign,
        function() return NormalizeClassPowerShapeAlign(Bars().classPowerShapeAlign) end,
        function(value)
            Bars().classPowerShapeAlign = NormalizeClassPowerShapeAlign(value)
            ApplyClassPower()
        end)
    AddControls(cpControls, cpPreset, cpShapeQuick, cp.shape, cp.height, cp.widthMode, cpAlign, cp.x, cp.y, cp.level)
    local layoutLeftX = 32
    local layoutRightX = compactLayout and layoutLeftX or min(max(430, floor(layoutWidth * 0.52)), max(360, layoutWidth - 360))
    local layoutLeftW = compactLayout and max(250, layoutWidth - layoutLeftX - 32) or max(250, layoutRightX - layoutLeftX - 42)
    local layoutRightW = compactLayout and layoutLeftW or max(250, layoutWidth - layoutRightX - 32)
    local layoutControlW = compactLayout and max(250, min(320, layoutWidth - layoutLeftX - 42)) or 300
    local positionCardY = compactLayout and -562 or -38
    local positionTopY = compactLayout and -616 or -92
    W.ControlCard(display, "Class Resource", nil, layoutLeftX - 14, -38, layoutLeftW + 28, compactLayout and 504 or 478)
    W.ControlCard(display, "Position", nil, layoutRightX - 14, positionCardY, layoutRightW + 28, 232)
    MoveWidget(cpEnable, display, layoutLeftX, -78)
    PlaceColumn(display, layoutLeftX, -116, 54, layoutControlW, nil, cpPreset, cpShapeQuick, cp.shape, cp.height, cp.widthMode, cp.width, cpAlign)
    PlaceColumn(display, layoutRightX, positionTopY, 54, layoutControlW, nil, cp.x, cp.y, cp.level)
    local behavior = b:CollapsibleSection("classpower_behavior", "Class Resource Behavior", 206, false)
    local cpBehavior = BuildBoundControls(behavior, Bars, ApplyClassPower, {
        { "anchor", "toggle", "Anchor to Essential Cooldown", "classPowerAnchorToCooldown", false },
        { "charged", "toggle", "Show empowered combo points", "showChargedComboPoints", true },
        { "text", "toggle", "Show resource text", "classPowerShowText", false },
        { "rune", "toggle", "Show rune time (per rune)", "runeShowTime", true },
        { "reverse", "toggle", "Fill right-to-left", "classPowerFillReverse", false },
        { "ele", "toggle", "Show Maelstrom bar (Ele)", "showEleMaelstrom", false },
        { "ebon", "toggle", "Show Ebon Might timer (Aug)", "showEbonMight", true },
        { "shadow", "toggle", "Show Insanity bar (Shadow)", "showShadowMana", false },
        { "prediction", "toggle", "Show resource prediction", "classPowerShowPrediction", true },
    })
    AddNamedControls(cpControls, cpBehavior, "anchor charged text rune reverse ele ebon shadow prediction")
    local behaviorRightX = min(max(380, floor((ctx.width or 900) * 0.45)), max(320, (ctx.width or 900) - 420))
    local behaviorW = behavior._msuf2Width or ctx.width or 900
    local behaviorLeftW = max(280, behaviorRightX - 42)
    local behaviorRightW = max(280, behaviorW - behaviorRightX - 28)
    W.ControlCardBackdrop(behavior, 14, -38, behaviorLeftW, 154)
    W.ControlCardBackdrop(behavior, behaviorRightX - 14, -38, behaviorRightW + 14, 154)
    PlaceColumn(behavior, 14, -38, 32, nil, nil, cpBehavior.anchor, cpBehavior.charged, cpBehavior.text, cpBehavior.rune, cpBehavior.reverse)
    PlaceColumn(behavior, behaviorRightX, -38, 32, nil, nil, cpBehavior.ele, cpBehavior.ebon, cpBehavior.shadow, cpBehavior.prediction)
    local visual = b:CollapsibleSection("classpower_visuals", "Class Resource Style", 430, false)
    local styleWidth = visual._msuf2Width or ctx.width or 900
    local styleInnerW = max(320, styleWidth - 64)
    local styleLeftX = 32
    local styleCardW = min(540, styleInnerW)
    local styleControlW = min(360, styleCardW - 32)
    local styleTabFrames = {}
    local resourcesFrame, textFrame, opacityFrame, pipsFrame = M.UnitSectionsShared.MakeTabFrames(visual, -88, styleWidth, styleTabFrames, "resources", "text", "opacity", "pips")
    W.SegmentTabs(ctx, visual, {
        stateKey = "classPowerStyleTab", label = "Style area",
        values = VT("resources", "Textures", "text", "Text", "opacity", "Opacity", "pips", "Pips"),
        width = min(620, styleInnerW), frames = styleTabFrames, defaultTab = "resources",
        x = styleLeftX, y = -44,
    })
    M.Assign(cp, BuildBoundControls(resourcesFrame, Bars, ApplyClassPower, {
        { "color", "toggle", "Color by resource type", "classPowerColorByType", true },
        { "comboColor", "dropdown", "Combo point colors", VT("default", "Resource color", "ramp", "Combo ramp", "custom", "Custom slots"), 260, "classPowerComboPointColorMode", "default" },
        { "fgTex", "dropdown", "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, "classPowerTexture", "" },
        { "bgTex", "dropdown", "Background texture", function() return TextureValues("Use foreground texture") end, 300, "classPowerBgTexture", "" },
    }))
    M.Assign(cp, BuildBoundControls(textFrame, Bars, ApplyClassPower, {
        { "font", "slider", "Font size", 6, 32, 1, 300, "classPowerFontSize", 16 },
        { "textX", "slider", "Text X", -200, 200, 1, 300, "classPowerTextOffsetX", 0 },
        { "textY", "slider", "Text Y", -200, 200, 1, 300, "classPowerTextOffsetY", 0 },
    }))
    M.Assign(cp, BuildBoundControls(opacityFrame, Bars, ApplyClassPower, {
        { "bg", "alpha", "BG opacity", "classPowerBgAlpha", 0.3, nil, 1 },
        { "filled", "alpha", "Filled %", "classPowerFilledAlpha", 1.0, nil, 5 },
        { "empty", "alpha", "Empty %", "classPowerEmptyAlpha", 0.3, nil, 5 },
    }))
    M.Assign(cp, BuildBoundControls(pipsFrame, Bars, ApplyClassPower, {
        { "separator", "slider", "Separator", 0, 4, 1, 300, "classPowerTickWidth", 1 },
        { "outline", "slider", "Outline", 0, 4, 1, 300, "classPowerOutline", 1 },
        { "gap", "slider", "Pip gap", 0, 8, 1, 300, "classPowerGap", 0 },
    }))
    AddControls(cpControls, cp.color, cp.comboColor, cp.bg, cp.separator, cp.outline, cp.filled, cp.empty, cp.gap, cp.fgTex, cp.bgTex)
    AddControls(textControls, cp.font, cp.textX, cp.textY)
    W.ControlCard(resourcesFrame, "Resource & Textures", nil, styleLeftX - 14, -38, styleCardW + 28, 248)
    W.ControlCard(textFrame, "Text", nil, styleLeftX - 14, -38, styleCardW + 28, 210)
    W.ControlCard(opacityFrame, "Opacity", nil, styleLeftX - 14, -38, styleCardW + 28, 204)
    W.ControlCard(pipsFrame, "Pips & Border", nil, styleLeftX - 14, -38, styleCardW + 28, 230)
    MoveWidget(cp.color, resourcesFrame, styleLeftX, -72)
    MoveWidget(cp.comboColor, resourcesFrame, styleLeftX, -104, styleControlW)
    PlaceColumn(resourcesFrame, styleLeftX, -192, 54, styleControlW, nil, cp.fgTex, cp.bgTex)
    PlaceColumn(textFrame, styleLeftX, -84, 52, styleControlW, nil, cp.font, cp.textX, cp.textY)
    PlaceColumn(opacityFrame, styleLeftX, -84, 52, styleControlW, nil, cp.bg, cp.filled, cp.empty)
    PlaceColumn(pipsFrame, styleLeftX, -84, 52, styleControlW, nil, cp.separator, cp.outline, cp.gap)
    local visibility = b:CollapsibleSection("classpower_visibility", "Class Resource Visibility", 216, false)
    local visibilityW = min(560, (visibility._msuf2Width or ctx.width or 900) - 28)
    W.ControlCard(visibility, "Auto-Hide Rules", nil, 14, -54, visibilityW, 142)
    local hideOOC = SwitchAt(ctx, visibility, "Hide out of combat", 32, -86, visibilityW - 48, Bars, "classPowerHideOOC", false, ApplyClassPower)
    local hideFull = SwitchAt(ctx, visibility, "Hide when full", 32, -118, visibilityW - 48, Bars, "classPowerHideWhenFull", false, ApplyClassPower)
    local hideEmpty = SwitchAt(ctx, visibility, "Hide when empty", 32, -150, visibilityW - 48, Bars, "classPowerHideWhenEmpty", false, ApplyClassPower)
    AddControls(cpControls, hideOOC, hideFull, hideEmpty)
    b:Header("Attached Player Bars", "Optional Player Power and second HP bars managed by the Class Resources stack.", 64)
    local dpbCompact = layoutWidth < 680
    local dpb = b:CollapsibleSection("classpower_detached_power", "Player Power Bar", dpbCompact and 920 or 640, false)
    local dpbWidth = dpb._msuf2Width or ctx.width or 900
    local dpbInnerW = max(320, dpbWidth - 64)
    local dpbCardW = min(650, dpbWidth - 28)
    local dpbControlW = min(300, max(240, dpbCardW - 64))
    local dpbTwoColumn = (not dpbCompact) and dpbCardW >= 620
    local dpbRightX = dpbTwoColumn and (32 + dpbControlW + 28) or 32
    local dpbSecondColY = dpbTwoColumn and -154 or -520
    local dpbTextSecondColY = dpbTwoColumn and -154 or -300
    local dpbTabFrames = {}
    local dpbLayout, dpbTextures, dpbText = M.UnitSectionsShared.MakeTabFrames(dpb, -88, dpbWidth, dpbTabFrames, "layout", "textures", "text")
    W.SegmentTabs(ctx, dpb, {
        stateKey = "classPowerDetachedPowerTab", label = "Power area",
        values = VT("layout", "Layout", "textures", "Textures", "text", "Text"),
        width = min(520, dpbInnerW), frames = dpbTabFrames, defaultTab = "layout",
        x = 32, y = -44,
    })
    W.ControlCard(dpbLayout, "Detached Player Power", "When anchored or synced here, Player power settings are managed by Class Resources.", 14, -38, dpbCardW, dpbTwoColumn and 482 or 760)
    local dpbUse = W.SwitchAt(dpbLayout, "Detached player power", 32, -104, dpbControlW)
    M.BindBoolWidget(ctx, dpbUse,
        function() return Player().powerBarDetached == true end,
        function(v)
            local player = Player()
            player.powerBarDetached = v and true or false
            if v then
                player.showPowerBar = true
                if player.detachedPowerBarSyncClassPower == nil then player.detachedPowerBarSyncClassPower = true end
                if player.detachedPowerBarAnchorToClassPower == nil then player.detachedPowerBarAnchorToClassPower = true end
                player.detachedPowerBarOffsetX = tonumber(player.detachedPowerBarOffsetX) or 0
                player.detachedPowerBarOffsetY = tonumber(player.detachedPowerBarOffsetY) or -4
                player.detachedPowerBarHeight = tonumber(player.detachedPowerBarHeight) or 6
                player.detachedPowerBarFrameLevelOffset = tonumber(player.detachedPowerBarFrameLevelOffset) or 6
            end
            ApplyDetachedPowerBar()
            RefreshClassPowerControls()
        end)
    local dpbModeField = BuildBoundControls(dpbLayout, Bars, ApplyDetachedPowerBar, {
        { "mode", "nilDefaultDropdown", "Width mode", VT("manual", "Manual", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns", "tracked_buffs", "Tracked Buffs"), 260, "detachedPowerBarWidthMode", "manual" },
    })
    local dpbFields = BuildBoundControls(dpbLayout, Player, ApplyDetachedPowerBar, {
        { "anchor", "toggle", "Anchor to Class Resource", "detachedPowerBarAnchorToClassPower", false },
        { "sync", "toggle", "Sync width to Class Resource", "detachedPowerBarSyncClassPower", true },
        { "shape", "playerShape", "Player power shape", VT("FOLLOW_CLASS", "Follow Class Resource", "BAR", "Bar", "ROUND", "Round", "CRYSTAL", "Crystal", "ORB", "Orb"), 300 },
        { "orbSize", "slider", "Orb size", 20, 160, 1, 300, "detachedPowerOrbSize", 54 },
        { "x", "slider", "Power X", -1000, 1000, 1, 300, "detachedPowerBarOffsetX", 0 },
        { "y", "slider", "Power Y", -1000, 1000, 1, 300, "detachedPowerBarOffsetY", -4 },
        { "height", "slider", "Power height", 2, 80, 1, 300, "detachedPowerBarHeight", 6 },
        { "layer", "slider", "Power layer", 0, 20, 1, 300, "detachedPowerBarFrameLevelOffset", 6 },
    })
    AddTooltip(dpbUse, "Detached Player Power", "Moves the Player power bar out of the unit frame. When Sync width or Anchor is enabled, Player power settings are managed here.")
    AddTooltip(dpbFields.anchor, "Anchor To Class Resource", "Keeps detached Player power attached to the Class Resource bar. Player power controls are disabled while this connection is active.")
    AddTooltip(dpbFields.sync, "Sync Width", "Uses the Class Resource width for detached Player power. Player power controls are disabled while this connection is active.")
    AddTooltip(dpbFields.shape, "Player Power Shape", "FOLLOW_CLASS resolves from Class Resource shape: Bar -> Bar, Circle -> Round, Diamond/Hex -> Crystal. Orb is a single bottom-to-top filled mana/power sphere.")
    W.ControlCard(dpbText, "Power Text", "Text shown on the detached Player power bar managed here.", 14, -38, dpbCardW, dpbTwoColumn and 260 or 410)
    local dpbTextFields = BuildBoundControls(dpbText, Player, ApplyDetachedPowerText, {
        { "onBar", "toggle", "Power text on bar", "detachedPowerBarTextOnBar", false },
        { "size", "slider", "Power text size", 6, 48, 1, 300, "powerFontSize", 14 },
        { "preset", "detachedTextPreset", "Power text", DETACHED_POWER_TEXT_PRESET_VALUES, 300 },
    })
    AddTooltip(dpbTextFields.preset, "Power Text", "Simple presets for Player power text while detached power is managed by Class Resources. Custom Slots means the existing slot layout is kept until you choose a preset.")
    W.ControlCard(dpbTextures, "Power Textures", "Bar uses SharedMedia textures. Shapes use fixed alpha assets.", 14, -38, dpbCardW, 260)
    local dpbTextureFields = BuildBoundControls(dpbTextures, Bars, ApplyDetachedPowerBar, {
        { "fg", "dropdown", "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, "detachedPowerBarTexture", "" },
        { "bg", "dropdown", "Background texture", function() return TextureValues("Use foreground texture") end, 300, "detachedPowerBarBgTexture", "" },
        { "outline", "slider", "Power bar outline", 0, 8, 1, 300, "detachedPowerBarOutline", 1, ApplyDetachedPowerBarOutline },
    })
    AddTooltip(dpbTextureFields.outline, "Power Bar Outline", "Controls only the detached Player power outline managed here. Bar uses an outside border; shapes use their fixed edge texture. 0 disables only the outline.")
    PlaceColumn(dpbLayout, 32, -154, 54, dpbControlW, "LEFT", dpbFields.anchor, dpbFields.sync, dpbModeField.mode, dpbFields.shape, dpbFields.orbSize, dpbFields.height)
    PlaceColumn(dpbLayout, dpbRightX, dpbSecondColY, 54, dpbControlW, "LEFT", dpbFields.x, dpbFields.y, dpbFields.layer)
    PlaceColumn(dpbTextures, 32, -104, 54, dpbControlW, "LEFT", dpbTextureFields.fg, dpbTextureFields.bg, dpbTextureFields.outline)
    PlaceColumn(dpbText, 32, -104, 54, dpbControlW, "LEFT", dpbTextFields.onBar, dpbTextFields.preset)
    PlaceColumn(dpbText, dpbRightX, dpbTextSecondColY, 54, dpbControlW, "LEFT", dpbTextFields.size)
    AddControls(dpbControls, dpbModeField.mode)
    AddNamedControls(dpbControls, dpbTextureFields, "fg bg outline")
    AddNamedControls(dpbPlayerControls, dpbFields, "anchor sync x y height layer")
    AddNamedControls(dpbPlayerControls, dpbTextFields, "onBar size preset")
    AddNamedControls(dpbPlayerControls, dpbFields, "shape orbSize")
    local phpCompact = layoutWidth < 680
    local php = b:CollapsibleSection("classpower_player_hp", "Second Player HP Bar", phpCompact and 980 or 700, false)
    local phpWidth = php._msuf2Width or ctx.width or 900
    local phpInnerW = max(320, phpWidth - 64)
    local phpCardW = min(650, phpWidth - 28)
    local phpControlW = min(300, max(240, phpCardW - 64))
    local phpTwoColumn = (not phpCompact) and phpCardW >= 620
    local phpRightX = phpTwoColumn and (32 + phpControlW + 28) or 32
    local phpSecondColY = phpTwoColumn and -154 or -580
    local phpTextSecondColY = phpTwoColumn and -188 or -440
    local phpTabFrames = {}
    local phpLayout, phpTextures, phpText = M.UnitSectionsShared.MakeTabFrames(php, -88, phpWidth, phpTabFrames, "layout", "textures", "text")
    W.SegmentTabs(ctx, php, {
        stateKey = "classPowerPlayerHPTab", label = "HP area",
        values = VT("layout", "Layout", "textures", "Textures", "text", "Text"),
        width = min(520, phpInnerW), frames = phpTabFrames, defaultTab = "layout",
        x = 32, y = -44,
    })
    W.ControlCard(phpLayout, "Second Player HP Bar", "Optional duplicate HP bar managed by Class Resources.", 14, -38, phpCardW, phpTwoColumn and 500 or 760)
    local ApplyPlayerHPBarAndRefresh = WithClassPowerRefresh(ApplyPlayerHPBar)
    local phpUse = SwitchAt(ctx, phpLayout, "Second Player HP bar", 32, -104, phpControlW, Bars, "playerHPBarEnabled", false, ApplyPlayerHPBarAndRefresh)
    local phpLayoutControls = BuildBoundControls(phpLayout, Bars, ApplyPlayerHPBar, {
        { "anchor", "dropdown", "Anchor", PLAYER_HP_ANCHOR_VALUES, 300, "playerHPBarAnchor", "CLASS_TOP" },
        { "widthMode", "dropdown", "Width mode", PLAYER_HP_WIDTH_VALUES, 300, "playerHPBarWidthMode", "class", ApplyPlayerHPBarAndRefresh },
        { "manualWidth", "slider", "Custom width", 20, 1200, 1, 300, "playerHPBarWidth", 0 },
        { "shape", "dropdown", "HP shape", PLAYER_HP_SHAPE_VALUES, 300, "playerHPBarShape", "BAR", ApplyPlayerHPBarAndRefresh },
        { "orbSize", "slider", "Orb size", 20, 160, 1, 300, "playerHPBarOrbSize", 54 },
        { "height", "slider", "Height", 2, 80, 1, 300, "playerHPBarHeight", 6 },
        { "smooth", "toggle", "Smooth fill", "playerHPBarSmoothFill", false },
        { "gap", "slider", "Gap", 0, 60, 1, 300, "playerHPBarGap", 2 },
        { "x", "slider", "Offset X", -1000, 1000, 1, 300, "playerHPBarOffsetX", 0 },
        { "y", "slider", "Offset Y", -1000, 1000, 1, 300, "playerHPBarOffsetY", 0 },
        { "layer", "slider", "Frame layer", 0, 30, 1, 300, "playerHPBarFrameLevelOffset", 7 },
    })
    PlaceColumn(phpLayout, 32, -154, 54, phpControlW, "LEFT", phpLayoutControls.anchor, phpLayoutControls.widthMode, phpLayoutControls.manualWidth, phpLayoutControls.shape, phpLayoutControls.orbSize, phpLayoutControls.height, phpLayoutControls.smooth)
    PlaceColumn(phpLayout, phpRightX, phpSecondColY, 54, phpControlW, "LEFT", phpLayoutControls.gap, phpLayoutControls.x, phpLayoutControls.y, phpLayoutControls.layer)
    AddNamedControls(phpControls, phpLayoutControls, "anchor widthMode shape height smooth gap x y layer")
    AddNamedControls(phpManualControls, phpLayoutControls, "manualWidth")
    AddNamedControls(phpOrbControls, phpLayoutControls, "orbSize")
    AddTooltip(phpUse, "Second Player HP Bar", "Renders a second native Player health bar. The normal Player unitframe HP bar is untouched, so you can show HP twice.")
    AddTooltip(phpLayoutControls.anchor, "Anchor", "Power anchors use the Player power bar when it is visible; otherwise the HP bar falls back to the Class Resource anchor.")
    AddTooltip(phpLayoutControls.widthMode, "Width Mode", "Class Resource and Player Power follow existing frames. Custom uses the slider below. Width is resolved only during layout refresh.")
    AddTooltip(phpLayoutControls.shape, "HP Shape", "Bar keeps the normal statusbar. Follow Player Power mirrors the effective detached Player power shape: Follow Class Resource still resolves Circle to Round and Diamond/Hex to Crystal. Orb uses a single vertical fill.")
    AddTooltip(phpLayoutControls.orbSize, "Orb Size", "Used only when this HP bar is explicitly set to Orb. Follow Player Power inherits the Player power orb size instead.")
    AddTooltip(phpLayoutControls.smooth, "Smooth Fill", "Optional interpolation for this second HP bar. Off keeps direct native SetValue updates.")
    W.ControlCard(phpTextures, "HP Textures", "Bar uses SharedMedia textures. Shapes use fixed alpha assets.", 14, -38, phpCardW, 346)
    local phpTextureFields = BuildBoundControls(phpTextures, Bars, ApplyPlayerHPBar, {
        { "color", "dropdown", "HP color", PLAYER_HP_COLOR_VALUES, 300, "playerHPBarColorMode", "GLOBAL" },
        { "fg", "dropdown", "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, "playerHPBarTexture", "", ApplyPlayerHPTextures },
        { "bg", "dropdown", "Background texture", function() return TextureValues("Use foreground texture") end, 300, "playerHPBarBgTexture", "", ApplyPlayerHPTextures },
        { "bgAlpha", "alpha", "BG opacity", "playerHPBarBgAlpha", 0.35, ApplyPlayerHPBar, 1 },
        { "outline", "slider", "Outline", 0, 8, 1, 300, "playerHPBarOutline", 1 },
    })
    PlaceColumn(phpTextures, 32, -104, 54, phpControlW, "LEFT", phpTextureFields.color, phpTextureFields.fg, phpTextureFields.bg, phpTextureFields.bgAlpha, phpTextureFields.outline)
    AddNamedControls(phpControls, phpTextureFields, "color fg bg bgAlpha outline")
    AddNamedControls(phpTextureControls, phpTextureFields, "fg bg")
    AddTooltip(phpTextureFields.color, "HP Color", "Global follows the normal MSUF health color mode. Class Color forces your class color. Dark Mode forces the configured dark bar color. HP Gradient colors only this second HP bar by current health.")
    AddTooltip(phpTextureFields.bg, "Background Texture", "Visible behind the filled HP amount. At 100% HP the fill covers the background; Outline 0 does not disable this texture.")
    AddTooltip(phpTextureFields.outline, "HP Outline", "Controls only the second HP bar outline. Bar uses four outside border edges; shapes use their fixed edge texture. 0 disables only the outline.")
    W.ControlCard(phpText, "HP Text", "Same value modes as Player unitframe health text.", 14, -38, phpCardW, phpTwoColumn and 440 or 690)
    local ApplyPlayerHPTextAndRefresh = WithClassPowerRefresh(ApplyPlayerHPText)
    local phpTextEnable = SwitchAt(ctx, phpText, "Show HP text", 32, -104, phpControlW, Bars, "playerHPBarTextEnabled", true, ApplyPlayerHPTextAndRefresh)
    local phpTextShared = SwitchAt(ctx, phpText, "Use Player HP text", 32, -136, phpControlW, Bars, "playerHPBarUsePlayerText", true, ApplyPlayerHPTextAndRefresh)
    local phpTextFields = BuildBoundControls(phpText, Bars, ApplyPlayerHPText, {
        { "right", "dropdown", "Right slot", PLAYER_HP_TEXT_VALUES, 300, "playerHPBarTextRight", "CURPERCENT" },
        { "left", "dropdown", "Left slot", PLAYER_HP_TEXT_VALUES, 300, "playerHPBarTextLeft", "NONE" },
        { "center", "dropdown", "Center slot", PLAYER_HP_TEXT_VALUES, 300, "playerHPBarTextCenter", "NONE" },
        { "sep", "dropdown", "Delimiter", PLAYER_HP_SEPARATORS, 180, "playerHPBarTextSeparator", "" },
        { "reverse", "toggle", "Reverse order", "playerHPBarTextReverse", false },
        { "size", "slider", "Text size", 6, 48, 1, 300, "playerHPBarTextSize", 14 },
        { "x", "slider", "Text X", -300, 300, 1, 300, "playerHPBarTextOffsetX", 0 },
        { "y", "slider", "Text Y", -300, 300, 1, 300, "playerHPBarTextOffsetY", 0 },
    })
    PlaceColumn(phpText, 32, -188, 54, phpControlW, "LEFT", phpTextFields.right, phpTextFields.left, phpTextFields.center, phpTextFields.sep)
    PlaceColumn(phpText, phpRightX, phpTextSecondColY, 54, phpControlW, "LEFT", phpTextFields.reverse, phpTextFields.size, phpTextFields.x, phpTextFields.y)
    AddControls(phpControls, phpTextEnable)
    AddControls(phpTextControls, phpTextShared)
    AddNamedControls(phpCustomTextControls, phpTextFields, "right left center sep reverse size")
    AddNamedControls(phpTextPositionControls, phpTextFields, "x y")
    AddTooltip(phpTextEnable, "HP Text", "Controls only this second HP bar. The normal Player unitframe HP text remains separate.")
    AddTooltip(phpTextShared, "Use Player HP Text", "Uses Player HP text settings and copies already-rendered Player HP text when it is current. Local Text X/Y still belong to this bar.")
    b:Header("Other Resource Bars", "Extra class/resource bars that are not the main class-resource row.", 64)
    local altMana = b:CollapsibleSection("classpower_alt_mana", "Alternative Mana", 306, false)
    local altManaCardW = min(620, (altMana._msuf2Width or ctx.width or 900) - 28)
    local altManaControlW = min(360, altManaCardW - 64)
    W.ControlCard(altMana, "Alternative Mana", "Shadow, Ret, Ele, Enh, Balance, Feral, WW", 14, -38, altManaCardW, 234)
    local altManaToggle = SwitchAt(ctx, altMana, "Show mana bar (dual resource)", 32, -98, altManaControlW, Bars, "showAltMana", false, ApplyClassPower)
    local altManaFields = BuildBoundControls(altMana, Bars, ApplyClassPower, {
        { "height", "slider", "Height", 2, 30, 1, 300, "altManaHeight", 4 },
        { "y", "slider", "Y offset", -50, 50, 1, 300, "altManaOffsetY", -2 },
    })
    PlaceColumn(altMana, 32, -138, 54, altManaControlW, "LEFT", altManaFields.height, altManaFields.y)
    AddNamedControls(altManaControls, altManaFields, "height y")
    RefreshClassPowerControls = RefreshClassPowerControls(function()
        local bars = Bars()
        local cpOn = BoolValue(bars, "showClassPower", true)
        local textOn = cpOn and BoolValue(bars, "classPowerShowText", false)
        local customWidth = cpOn and ((bars.classPowerWidthMode or "player") == "custom")
        local anyDetached = false
        local playerDetached = false
        local db = M.EnsureDB()
        for _, key in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }) do
            if db[key] and db[key].powerBarDetached then anyDetached = true; break end
        end
        playerDetached = db.player and db.player.powerBarDetached == true
        SetControlsEnabled(cpControls, cpOn)
        SetControlEnabled(cp.width, customWidth)
        local classShapeIsBar = NormalizeClassPowerShape(bars.classPowerShape) == "BAR"
        if cp.height and cp.height._msuf2Title then cp.height._msuf2Title:SetText(M.Tr(classShapeIsBar and "Height" or "Pip size")) end
        SetControlEnabled(cp.separator, cpOn and classShapeIsBar)
        SetControlEnabled(cp.outline, cpOn and classShapeIsBar)
        SetControlEnabled(cpAlign, cpOn and not classShapeIsBar)
        SetControlsEnabled(textControls, textOn)
        SetControlsEnabled(dpbControls, anyDetached)
        SetControlsEnabled(dpbPlayerControls, playerDetached)
        SetControlEnabled(dpbUse, true)
        local playerShape = NormalizeDetachedPowerShape(db.player and db.player.detachedPowerBarShape)
        SetControlEnabled(dpbFields.orbSize, playerDetached and playerShape == "ORB")
        SetControlEnabled(dpbFields.height, playerDetached and playerShape ~= "ORB")
        local playerTextOn = db.player and db.player.showPower ~= false
        SetControlEnabled(dpbTextFields.onBar, playerDetached and playerTextOn)
        SetControlEnabled(dpbTextFields.size, playerDetached and playerTextOn)
        local phpOn = BoolValue(bars, "playerHPBarEnabled", false)
        local phpShapeValue = ResolvePlayerHPShape(bars, db)
        local phpRawShape = NormalizePlayerHPShape(bars.playerHPBarShape)
        local phpShapeIsBar = phpShapeValue == "BAR"
        local phpShapeIsOrb = phpShapeValue == "ORB"
        SetControlsEnabled(phpControls, phpOn)
        SetControlsEnabled(phpManualControls, phpOn and not phpShapeIsOrb and (bars.playerHPBarWidthMode or "class") == "custom")
        SetControlsEnabled(phpOrbControls, phpOn and phpRawShape == "ORB")
        SetControlsEnabled(phpTextureControls, phpOn and phpShapeIsBar)
        SetControlEnabled(phpLayoutControls.height, phpOn and not phpShapeIsOrb)
        local phpTextOn = phpOn and BoolValue(bars, "playerHPBarTextEnabled", true)
        local phpSharedText = BoolValue(bars, "playerHPBarUsePlayerText", true)
        SetControlsEnabled(phpTextControls, phpTextOn)
        SetControlsEnabled(phpCustomTextControls, phpTextOn and not phpSharedText)
        SetControlsEnabled(phpTextPositionControls, phpTextOn)
        SetControlEnabled(phpUse, true)
        local altOn = BoolValue(bars, "showAltMana", false)
        SetControlsEnabled(altManaControls, altOn)
        SetControlEnabled(altManaToggle, true)
        SetControlEnabled(cpEnable, true)
    end)
    M.RefreshClassPowerDetachedState = RefreshClassPowerControls
    M.TrackRefresh(ctx, RefreshClassPowerControls)
    MaybeOfferQuickSetup()
    ctx:SetContentHeight(math.abs(b.y) + 42)
end
M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 14 })
