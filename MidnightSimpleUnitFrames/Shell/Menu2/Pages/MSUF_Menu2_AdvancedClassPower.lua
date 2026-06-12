local addonName, MSUF = ...
MSUF = MSUF or {}

local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local AP = M.AdvancedPage or {}

local floor = math.floor
local max = math.max
local min = math.min
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local RefreshClassPowerInlinePreview

local CallGlobal, Bars, BoolValue, NumValue, SetValue, DeepCopyTable, BindTableToggle, BindTableSlider, BindTableDropdown, SwitchAt, SetControlEnabled = M.Pick(AP, [[CallGlobal Bars BoolValue NumValue SetValue DeepCopyTable BindTableToggle BindTableSlider BindTableDropdown SwitchAt SetControlEnabled]])
local MoveWidget = W.MoveWidget or AP.MoveWidget
local CPPreview = M.ClassPowerPreview or {}
local function ApplyClassPower()
    CallGlobal("MSUF_ClassPower_Refresh")
    CallGlobal("MSUF_ClassPower_RefreshTextures")
    CallGlobal("MSUF_ClassPower_RefreshCDMWidthBindings", true)
    if RefreshClassPowerInlinePreview then RefreshClassPowerInlinePreview() end
    M.RequestGeneralApply("MSUF2_CLASSPOWER", { preview = true, applyAll = false })
end

local TextureValues = M.StatusBarTextureItems
local VT = M.ValueTextList
local CP_SHAPE_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\"
local CP_SHAPE_TEXTURES = {
    CIRCLE = {
        fill = CP_SHAPE_MEDIA .. "pip_circle_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_circle_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_circle_edge.tga",
    },
    DIAMOND = {
        fill = CP_SHAPE_MEDIA .. "pip_diamond_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_diamond_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_diamond_edge.tga",
    },
    HEX = {
        fill = CP_SHAPE_MEDIA .. "pip_hex_fill.tga",
        bg = CP_SHAPE_MEDIA .. "pip_hex_bg.tga",
        edge = CP_SHAPE_MEDIA .. "pip_hex_edge.tga",
    },
}

local function NormalizeClassPowerShape(value)
    value = tostring(value or "BAR"):upper()
    if value == "CIRCLE" or value == "DIAMOND" or value == "HEX" then return value end
    return "BAR"
end

local function ClassPowerShapeTextures(value)
    return CP_SHAPE_TEXTURES[NormalizeClassPowerShape(value)]
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

local function RequestClassPowerPreviewRefresh()
    if RefreshClassPowerInlinePreview then RefreshClassPowerInlinePreview() end
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

M.ClassPowerPreviewSpecValues = CLASS_POWER_PREVIEW_VALUES
M.ClassPowerPreviewSpecs = CLASS_POWER_PREVIEW_BY_KEY

local function ApplyClassPowerPreviewFont(region, size)
    if not (region and region.SetFont) then return end
    size = floor(tonumber(size) or 12)
    if size < 6 then size = 6 end
    local fontPath = type(_G.MSUF_GetFontPath) == "function" and _G.MSUF_GetFontPath() or _G.STANDARD_TEXT_FONT
    local fontFlags = type(_G.MSUF_GetFontFlags) == "function" and _G.MSUF_GetFontFlags() or "OUTLINE"
    if not fontPath or fontPath == "" then fontPath = "Fonts\\FRIZQT__.TTF" end
    if not fontFlags or fontFlags == "" then fontFlags = "OUTLINE" end
    if type(_G.MSUF_SetFontSafe) == "function" then
        _G.MSUF_SetFontSafe(region, fontPath, size, fontFlags)
    else
        pcall(region.SetFont, region, fontPath, size, fontFlags)
    end
    if region.SetShadowColor then region:SetShadowColor(0, 0, 0, 1) end
    if region.SetShadowOffset then region:SetShadowOffset(1, -1) end
end

RefreshClassPowerInlinePreview = function()
    local preview = M._msuf2ClassPowerInlinePreview
    if preview and preview.Refresh then preview:Refresh() end
end

local function BindBarsAlphaPercent(ctx, section, label, key, default, apply, step)
    local slider = W.Slider(section, label, 0, 100, step or 5, 300)
    M.BindSlider(ctx, slider,
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
        end)
    return slider
end

local function ApplyDetachedPowerBar()
    CallGlobal("MSUF_DetachedPowerBar_RefreshTextures")
    CallGlobal("MSUF_ApplyPowerBarEmbedLayout_All")
    M.RequestGeneralApply("MSUF2_DETACHED_POWER_BAR", { preview = true, power = true, applyAll = false })
end

local function ApplyDetachedPowerBarOutline()
    CallGlobal("MSUF_ApplyBarOutlineThickness_All")
    ApplyDetachedPowerBar()
end

local QUICK_SETUP_FLAG = "quickSetupClassBarOffered"
local QUICK_CP_HEIGHT = 4
local QUICK_DPB_HEIGHT = 6
local QUICK_DPB_GAP = 2
local QUICK_CDM_GAP = 2
local QUICK_FALLBACK_Y_FRAC = 0.60

local QUICK_BARS_KEYS = {
    "showClassPower",
    "classPowerShape",
    "classPowerShowText",
    "classPowerAnchorToCooldown",
    "classPowerWidthMode",
    "showEleMaelstrom",
    "showEbonMight",
    "showChargedComboPoints",
    "runeShowTime",
    "runeShowTimeText",
    "classPowerOffsetX",
    "classPowerOffsetY",
    "classPowerOutline",
    "detachedPowerBarWidthMode",
    "detachedPowerBarOutline",
}

local QUICK_PLAYER_KEYS = {
    "powerBarDetached",
    "detachedPowerBarShape",
    "detachedPowerBarSyncClassPower",
    "detachedPowerBarAnchorToClassPower",
    "detachedPowerBarTextOnBar",
    "detachedPowerBarOffsetX",
    "detachedPowerBarOffsetY",
    "hpPowerTextOverride",
    "hpTextMode",
    "textLeft",
    "textCenter",
    "textRight",
    "powerTextMode",
    "powerTextLeft",
    "powerTextCenter",
    "powerTextRight",
    "hpTextSeparator",
    "powerTextSeparator",
    "absorbTextMode",
    "absorbAnchorMode",
    "healPredAnchorMode",
}

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
    if not (pf and pf.GetLeft and pf.GetBottom and pf.GetEffectiveScale and ecv and ecv.GetCenter and ecv.GetTop and ecv.GetWidth) then
        return fallback
    end
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

    bars.showClassPower = true
    bars.classPowerShowText = true
    bars.classPowerAnchorToCooldown = offsets.anchorCPtoCDM and true or false
    bars.classPowerWidthMode = "cooldown"
    bars.detachedPowerBarWidthMode = "cooldown"
    bars.showEleMaelstrom = true
    bars.showEbonMight = true
    bars.showChargedComboPoints = true
    bars.runeShowTime = true
    bars.runeShowTimeText = true
    bars.classPowerOffsetX = offsets.cpOffsetX
    bars.classPowerOffsetY = offsets.cpOffsetY
    bars.classPowerOutline = 1
    bars.detachedPowerBarOutline = 1

    player.powerBarDetached = true
    player.detachedPowerBarSyncClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    player.detachedPowerBarTextOnBar = true
    player.detachedPowerBarOffsetX = offsets.dpbOffsetX
    player.detachedPowerBarOffsetY = offsets.dpbOffsetY
    player.hpPowerTextOverride = true

    if player.hpTextMode == nil then player.hpTextMode = general.hpTextMode end
    if player.powerTextMode == nil then player.powerTextMode = general.powerTextMode end
    if player.textLeft == nil and player.textCenter == nil and player.textRight == nil then
        player.textLeft = "NONE"
        player.textCenter = "NONE"
        player.textRight = player.hpTextMode or general.hpTextMode or "CURPERCENT"
    end
    if player.powerTextLeft == nil and player.powerTextCenter == nil and player.powerTextRight == nil then
        player.powerTextLeft = "NONE"
        player.powerTextCenter = "NONE"
        player.powerTextRight = player.powerTextMode or general.powerTextMode or "CURPERCENT"
    end
    if player.hpTextSeparator == nil then player.hpTextSeparator = general.hpTextSeparator end
    if player.powerTextSeparator == nil then player.powerTextSeparator = general.powerTextSeparator or general.hpTextSeparator end
    if player.absorbTextMode == nil then player.absorbTextMode = general.absorbTextMode end
    if player.absorbAnchorMode == nil then player.absorbAnchorMode = general.absorbAnchorMode end
    if player.healPredAnchorMode == nil then player.healPredAnchorMode = general.healPredAnchorMode end
    player.powerTextMode = "CURRENT"
    player.powerTextLeft = "NONE"
    player.powerTextCenter = "CURRENT"
    player.powerTextRight = "NONE"
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
    if not _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_RESULT then
        _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_RESULT = {
            text = "%s",
            button1 = OKAY,
            button2 = QuickTr("Undo"),
            OnAccept = function() quickSetupUndoSnapshot = nil end,
            OnCancel = function()
                if quickSetupUndoSnapshot then
                    QuickRestore(quickSetupUndoSnapshot)
                    quickSetupUndoSnapshot = nil
                    QuickRefreshAll("ClassPowerQuickSetupUndo")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = false,
            preferredIndex = 3,
        }
    end
    if not _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_OFFER then
        _G.StaticPopupDialogs.MSUF2_CLASSPOWER_QUICK_OFFER = {
            text = QuickTr("Welcome to Class Resources!\n\n"
                .. "Would you like to automatically set up a\n"
                .. "detached Class Bar positioned above your\n"
                .. "Essential Cooldowns?\n\n"
                .. "This configures class resources, power bar,\n"
                .. "anchoring and width matching in one click.\n\n"
                .. "You can always run this later via the\n"
                .. "|cff00ff00Quick Setup: Class Bar|r button below."),
            button1 = QuickTr("Setup Now"),
            button2 = QuickTr("Not Now"),
            OnAccept = function()
                QuickMarkOffered()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.05, function()
                        if _G.MSUF2_ClassPowerQuickSetup then _G.MSUF2_ClassPowerQuickSetup() end
                    end)
                elseif _G.MSUF2_ClassPowerQuickSetup then
                    _G.MSUF2_ClassPowerQuickSetup()
                end
            end,
            OnCancel = QuickMarkOffered,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            showAlert = true,
        }
    end
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
_G.MSUF_QuickSetup_ResetFirstRun = function()
    local db = M.EnsureDB()
    db.general = db.general or {}
    db.general[QUICK_SETUP_FLAG] = nil
    quickSetupFirstRunChecked = false
end

local function MaybeOfferQuickSetup()
    if quickSetupFirstRunChecked or QuickWasOffered() then return end
    quickSetupFirstRunChecked = true
    QuickEnsurePopups()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            if not QuickWasOffered() and StaticPopup_Show then
                StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_OFFER")
            end
        end)
    elseif StaticPopup_Show then
        StaticPopup_Show("MSUF2_CLASSPOWER_QUICK_OFFER")
    end
end

local function BuildInlineClassPowerPreview(ctx, b)
    local section = b:Section("Preview", 124)
    local sectionW = section._msuf2Width or b.width or ctx.width or 720
    local innerW = max(320, sectionW - 28)
    local box = T.Panel(section, nil, { 0.018, 0.022, 0.044, 0.88 }, T.colors.borderSoft)
    box:SetPoint("TOPLEFT", section, "TOPLEFT", 14, -38)
    box:SetSize(innerW, 68)

    local label = T.Font(box, "GameFontDisableSmall", "", T.colors.muted)
    label:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)
    label:SetJustifyH("LEFT")

    local animate = W.TopButton and W.TopButton(section, "Animate", 92, 24, nil, false) or T.Button(section, "Animate", 92, 24)
    animate._msuf2AllowCombatClick = true
    animate._msuf2SkipHistoryCheckpoint = true
    animate:SetPoint("TOPRIGHT", section, "TOPRIGHT", -14, -12)
    if animate.SetActive then animate:SetActive(false) end
    if animate.EnableMouse then animate:EnableMouse(true) end
    if animate.RegisterForClicks then animate:RegisterForClicks("LeftButtonUp") end

    local noResource = T.Font(box, "GameFontDisableSmall", "No class resource bar", T.colors.muted)
    noResource:SetPoint("CENTER", box, "CENTER", 0, -2)
    noResource:Hide()

    local bar = CreateFrame("Frame", nil, box, "BackdropTemplate")
    bar:SetPoint("CENTER", box, "CENTER", 0, -8)
    bar.segments = {}
    for i = 1, 10 do
        local seg = CreateFrame("StatusBar", nil, bar)
        seg:SetMinMaxValues(0, 1)
        seg:SetValue(0)
        seg:SetStatusBarTexture(WHITE8)
        if seg.SetReverseFill then seg:SetReverseFill(false) end
        local bg = seg:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(seg)
        bg:SetTexture(WHITE8)
        bg:SetVertexColor(0, 0, 0, 0.3)
        seg._bg = bg
        local edge = seg:CreateTexture(nil, "OVERLAY", nil, 5)
        edge:SetAllPoints(seg)
        edge:SetVertexColor(0, 0, 0, 1)
        edge:Hide()
        seg._edge = edge
        local runeText = T.Font(seg, "GameFontHighlightSmall", "", T.colors.text)
        runeText:SetPoint("CENTER", seg, "CENTER", 0, 0)
        runeText:SetJustifyH("CENTER")
        if runeText.SetJustifyV then runeText:SetJustifyV("MIDDLE") end
        if runeText.SetShadowColor then runeText:SetShadowColor(0, 0, 0, 1) end
        if runeText.SetShadowOffset then runeText:SetShadowOffset(1, -1) end
        runeText:Hide()
        seg._runeText = runeText
        bar.segments[i] = seg
    end
    bar.text = T.Font(bar, "GameFontHighlightSmall", "", T.colors.text)
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetJustifyH("CENTER")
    if bar.text.SetJustifyV then bar.text:SetJustifyV("MIDDLE") end

    local animFrame = CreateFrame("Frame", nil, section)
    animFrame:Hide()
    local scratch = {}
    local function StopAnimationDriver()
        if section._msuf2AnimTicker and section._msuf2AnimTicker.Cancel then
            section._msuf2AnimTicker:Cancel()
        end
        section._msuf2AnimTicker = nil
        box:SetScript("OnUpdate", nil)
        animFrame:SetScript("OnUpdate", nil)
        animFrame:Hide()
    end
    local function StepAnimation(delta)
        delta = tonumber(delta) or 0.033
        if delta < 0 or delta > 0.25 then delta = 0.033 end
        section._msuf2AnimElapsed = (section._msuf2AnimElapsed or 0) + delta
        section:Refresh()
    end
    local function StartAnimationDriver()
        StopAnimationDriver()
        box:SetScript("OnUpdate", function(_, elapsed)
            if not section._msuf2Animating or (section.IsShown and not section:IsShown()) then
                section:SetPreviewAnimating(false, true)
                return
            end
            section._msuf2AnimTick = (section._msuf2AnimTick or 0) + (tonumber(elapsed) or 0)
            if section._msuf2AnimTick >= 0.016 then
                local delta = section._msuf2AnimTick
                section._msuf2AnimTick = 0
                StepAnimation(delta)
            end
        end)
    end
    function section:SetPreviewAnimating(active, skipRefresh)
        active = active and true or false
        if self._msuf2Animating == active and not skipRefresh then return end
        self._msuf2Animating = active
        if active then
            self._msuf2AnimElapsed = 0
            self._msuf2AnimTick = 0
            animate:SetText("Stop")
            if animate.SetActive then animate:SetActive(true) end
            StartAnimationDriver()
        else
            animate:SetText("Animate")
            if animate.SetActive then animate:SetActive(false) end
            StopAnimationDriver()
        end
        if not skipRefresh then self:Refresh() end
    end
    animate:SetScript("OnClick", function()
        section:SetPreviewAnimating(not section._msuf2Animating)
    end)
    section:SetScript("OnHide", function(self)
        if self._msuf2Animating then self:SetPreviewAnimating(false, true) end
    end)

    function section:Refresh()
        local bars = Bars()
        local spec = M.GetClassPowerPreviewSpec()
        label:SetText(spec and spec.label or "")
        if not spec or spec.enabled == false or spec.mode == "none" or bars.showClassPower == false then
            if self._msuf2Animating then self:SetPreviewAnimating(false, true) end
            if animate.SetEnabled then animate:SetEnabled(false) else animate:Disable() end
            bar:Hide()
            for i = 1, #bar.segments do bar.segments[i]:Hide() end
            bar.text:Hide()
            noResource:Show()
            return
        end

        noResource:Hide()
        bar:Show()
        if animate.SetEnabled then animate:SetEnabled(true) else animate:Enable() end
        scratch.isRune = spec.mode == "rune"
        scratch.value = (self._msuf2Animating and not scratch.isRune) and CPPreview.AnimatedValue(spec, self._msuf2AnimElapsed) or nil
        scratch.token = CPPreview.TokenForValue(spec, scratch.value)
        if bars and bars.classPowerColorByType == false then
            scratch.r, scratch.g, scratch.b = 1, 1, 1
        else
            scratch.r, scratch.g, scratch.b = CPPreview.ResolveColor(scratch.token, 1, 1, 1)
        end
        scratch.filledAlpha = tonumber(bars.classPowerFilledAlpha) or 1
        if scratch.filledAlpha < 0 then scratch.filledAlpha = 0 elseif scratch.filledAlpha > 1 then scratch.filledAlpha = 1 end
        scratch.emptyAlpha = tonumber(bars.classPowerEmptyAlpha) or 0.3
        if scratch.emptyAlpha < 0 then scratch.emptyAlpha = 0 elseif scratch.emptyAlpha > 1 then scratch.emptyAlpha = 1 end
        scratch.bgAlpha = tonumber(bars.classPowerBgAlpha) or 0.3
        if scratch.bgAlpha < 0 then scratch.bgAlpha = 0 elseif scratch.bgAlpha > 1 then scratch.bgAlpha = 1 end
        scratch.bgr, scratch.bgg, scratch.bgb = CPPreview.ColorOverride("classPowerBgColorOverrides", scratch.token)

        scratch.fgTexture = CPPreview.ResolveTexture(bars.classPowerTexture)
        scratch.bgTexture = CPPreview.ResolveTexture(bars.classPowerBgTexture, scratch.fgTexture)
        scratch.shape = NormalizeClassPowerShape(bars.classPowerShape)
        scratch.shapeInfo = ClassPowerShapeTextures(scratch.shape)
        scratch.outline = floor(tonumber(bars.classPowerOutline) or 1)
        if scratch.outline < 0 then scratch.outline = 0 elseif scratch.outline > 4 then scratch.outline = 4 end
        if bar.SetBackdrop then
            if scratch.shapeInfo then
                bar:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
                bar:SetBackdropColor(0, 0, 0, 0)
                bar:SetBackdropBorderColor(0, 0, 0, 0)
            else
                bar:SetBackdrop({ bgFile = scratch.bgTexture, edgeFile = WHITE8, edgeSize = max(1, scratch.outline) })
                bar:SetBackdropColor(scratch.bgr or 0, scratch.bgg or 0, scratch.bgb or 0, scratch.bgAlpha)
                bar:SetBackdropBorderColor(0, 0, 0, scratch.outline > 0 and 1 or 0)
            end
        end

        scratch.rawW = tonumber(bars.classPowerWidth) or 275
        if bars.classPowerWidthMode ~= "custom" or scratch.rawW <= 0 then scratch.rawW = 275 end
        scratch.w = min(max(180, scratch.rawW), max(180, innerW - 48))
        scratch.h = floor(tonumber(bars.classPowerHeight) or 8)
        if scratch.h < 4 then scratch.h = 4 elseif scratch.h > 36 then scratch.h = 36 end
        bar:SetSize(scratch.w, scratch.h)

        scratch.segCount = floor(tonumber(spec.segments) or 5)
        if scratch.segCount < 1 then scratch.segCount = 1 elseif scratch.segCount > #bar.segments then scratch.segCount = #bar.segments end
        scratch.tickW = floor(tonumber(bars.classPowerTickWidth) or 1)
        if scratch.tickW < 0 then scratch.tickW = 0 elseif scratch.tickW > 4 then scratch.tickW = 4 end
        scratch.gap = floor(tonumber(bars.classPowerGap) or 0)
        if scratch.gap < 0 then scratch.gap = 0 elseif scratch.gap > 8 then scratch.gap = 8 end
        scratch.sepW = scratch.shapeInfo and scratch.gap or (scratch.tickW + scratch.gap)
        if scratch.segCount > 1 then
            scratch.maxSepW = floor((scratch.w - scratch.segCount) / (scratch.segCount - 1))
            if scratch.maxSepW < 0 then scratch.maxSepW = 0 end
            if scratch.sepW > scratch.maxSepW then scratch.sepW = scratch.maxSepW end
        end
        scratch.totalBarSpace = scratch.w - ((scratch.segCount - 1) * scratch.sepW)
        if scratch.totalBarSpace < scratch.segCount then scratch.totalBarSpace = scratch.segCount end
        if scratch.shapeInfo then
            scratch.slot = scratch.h
            scratch.maxSlot = floor((scratch.w - ((scratch.segCount - 1) * scratch.sepW)) / scratch.segCount)
            if scratch.maxSlot < 1 then scratch.maxSlot = 1 end
            if scratch.slot > scratch.maxSlot then scratch.slot = scratch.maxSlot end
            scratch.totalBarSpace = scratch.slot * scratch.segCount
            scratch.rowW = scratch.totalBarSpace + ((scratch.segCount - 1) * scratch.sepW)
            scratch.startX = floor((scratch.w - scratch.rowW) * 0.5 + 0.5)
            if scratch.startX < 0 then scratch.startX = 0 end
        else
            scratch.slot = nil
            scratch.startX = 0
        end
        scratch.xPos, scratch.prevBoundary = 0, 0
        scratch.reverse = bars.classPowerFillReverse == true
        scratch.runeOrder = scratch.isRune and CPPreview.BuildRuneOrder(scratch, bars, spec, self._msuf2AnimElapsed or 0, self._msuf2Animating) or nil
        scratch.runeShowTime = bars.runeShowTime ~= false
        if bars.runeShowTime == nil and bars.runeShowTimeText ~= nil then scratch.runeShowTime = bars.runeShowTimeText == true end
        scratch.textSize = floor(tonumber(bars.classPowerFontSize) or 16)
        if scratch.textSize < 6 then scratch.textSize = 6 end
        scratch.runeTextSize = scratch.textSize - 2
        if scratch.runeTextSize < 6 then scratch.runeTextSize = 6 end
        scratch.tr, scratch.tg, scratch.tb = CPPreview.ResolveTextColor()

        for i = 1, #bar.segments do
            local seg = bar.segments[i]
            if i <= scratch.segCount then
                if scratch.shapeInfo then
                    scratch.boundary = i * scratch.slot
                    scratch.segW = scratch.slot
                else
                    scratch.boundary = floor((scratch.totalBarSpace * i) / scratch.segCount)
                    scratch.segW = scratch.boundary - scratch.prevBoundary
                    if scratch.segW < 1 then scratch.segW = 1 end
                end
                scratch.rune = scratch.runeOrder and scratch.runeOrder[i] or nil
                scratch.fill = scratch.rune and ((scratch.rune.elapsed or 0) / (scratch.rune.total or 1)) or CPPreview.FillForSegment(spec, i, scratch.value)
                if scratch.fill < 0 then scratch.fill = 0 elseif scratch.fill > 1 then scratch.fill = 1 end
                scratch.drawW = scratch.fill > 0 and max(1, floor(scratch.segW * scratch.fill + 0.5)) or 0
                scratch.xBase = scratch.startX + scratch.xPos
                scratch.x = scratch.reverse and (scratch.w - scratch.xBase - scratch.segW) or scratch.xBase
                if seg.SetStatusBarTexture then seg:SetStatusBarTexture((scratch.shapeInfo and scratch.shapeInfo.fill) or scratch.fgTexture) end
                if scratch.rune then
                    if seg.SetMinMaxValues then seg:SetMinMaxValues(0, scratch.rune.total or 1) end
                elseif seg.SetMinMaxValues then
                    seg:SetMinMaxValues(0, 1)
                end
                if seg.SetReverseFill then seg:SetReverseFill(false) end
                if seg._bg then
                    seg._bg:SetTexture((scratch.shapeInfo and scratch.shapeInfo.bg) or scratch.bgTexture)
                    if scratch.rune then
                        seg._bg:SetVertexColor(0, 0, 0, scratch.bgAlpha)
                    else
                        seg._bg:SetVertexColor(scratch.bgr or 0, scratch.bgg or 0, scratch.bgb or 0, scratch.bgAlpha)
                    end
                end
                seg:ClearAllPoints()
                seg:SetPoint("TOPLEFT", bar, "TOPLEFT", scratch.x, 0)
                seg:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", scratch.x, 0)
                seg:SetWidth(scratch.segW)
                if seg._edge then
                    seg._edge:Hide()
                end
                scratch.sr, scratch.sg, scratch.sb = scratch.r, scratch.g, scratch.b
                if CPPreview.IsCharged(spec, bars, i) then
                    scratch.sr, scratch.sg, scratch.sb = CPPreview.ResolveColor("CHARGED", 0.60, 0.20, 0.80)
                elseif scratch.token == "COMBO_POINTS" then
                    scratch.sr, scratch.sg, scratch.sb = CPPreview.ResolveComboColor(bars, i, scratch.r, scratch.g, scratch.b)
                end
                if spec.threshold and scratch.fill > 0 and i > spec.threshold then
                    scratch.sr, scratch.sg, scratch.sb = CPPreview.ResolveColor(spec.thresholdToken, scratch.sr, scratch.sg, scratch.sb)
                end
                scratch.alpha = scratch.rune and scratch.filledAlpha or (scratch.fill > 0 and scratch.filledAlpha or scratch.emptyAlpha)
                if CPPreview.IsCharged(spec, bars, i) and scratch.fill <= 0 then
                    scratch.alpha = max(scratch.alpha, 0.55)
                end
                if seg.SetAlpha then seg:SetAlpha(scratch.alpha) end
                if seg.SetStatusBarColor then seg:SetStatusBarColor(scratch.sr, scratch.sg, scratch.sb, 1) end
                if seg.SetValue then seg:SetValue(scratch.rune and (scratch.rune.elapsed or 0) or scratch.fill) end
                if seg.GetStatusBarTexture then
                    local tex = seg:GetStatusBarTexture()
                    if tex then
                        if scratch.shapeInfo and scratch.fill > 0 and scratch.fill < 1 then
                            if scratch.reverse then
                                tex:SetTexCoord(1 - scratch.fill, 1, 0, 1)
                            else
                                tex:SetTexCoord(0, scratch.fill, 0, 1)
                            end
                        else
                            tex:SetTexCoord(0, 1, 0, 1)
                        end
                    end
                end
                if seg._runeText then
                    if scratch.rune and scratch.runeShowTime and not scratch.rune.ready then
                        scratch.runeText = CPPreview.FormatSeconds(scratch.rune.remaining)
                        if scratch.runeText ~= "" then
                            ApplyClassPowerPreviewFont(seg._runeText, scratch.runeTextSize)
                            seg._runeText:SetText(scratch.runeText)
                            seg._runeText:SetTextColor(scratch.tr, scratch.tg, scratch.tb, 1)
                            seg._runeText:Show()
                        else
                            seg._runeText:SetText("")
                            seg._runeText:Hide()
                        end
                    else
                        seg._runeText:SetText("")
                        seg._runeText:Hide()
                    end
                end
                seg:Show()
                scratch.xPos = scratch.xPos + scratch.segW + scratch.sepW
                scratch.prevBoundary = scratch.boundary
            else
                if seg._runeText then seg._runeText:Hide() end
                if seg._edge then seg._edge:Hide() end
                if seg.SetAlpha then seg:SetAlpha(1) end
                seg:Hide()
            end
        end

        if bars.classPowerShowText == true then
            bar.text:SetTextColor(scratch.tr, scratch.tg, scratch.tb, 1)
            ApplyClassPowerPreviewFont(bar.text, scratch.textSize)
            bar.text:SetText(CPPreview.TextForValue(spec, scratch.value))
            bar.text:ClearAllPoints()
            bar.text:SetPoint("CENTER", bar, "CENTER", tonumber(bars.classPowerTextOffsetX) or 0, tonumber(bars.classPowerTextOffsetY) or 0)
            bar.text:Show()
        else
            bar.text:Hide()
        end
    end

    M._msuf2ClassPowerInlinePreview = section
    M.AddRefresher(ctx, function() section:Refresh() end)
    section:Refresh()
    return section
end

local function BuildClassPower(ctx)
    local b = W.PageBuilder(ctx)
    local head = b:Header("Class Resources", "Native class-resource layout, visibility and text controls.", 94)

    local previewW = min(330, max(220, (ctx.width or 900) - 380))
    local previewDrop = W.Dropdown(head, "Preview resource", CLASS_POWER_PREVIEW_VALUES, previewW)
    MoveWidget(previewDrop, head, 14, -48, previewW)
    previewDrop:SetOnValueChanged(function(value)
        M.SetClassPowerPreviewSpecKey(value)
        previewDrop:SetValue(M.GetClassPowerPreviewSpecKey())
    end)
    previewDrop:SetValue(M.GetClassPowerPreviewSpecKey())
    if M.AddTooltip then
        M.AddTooltip(previewDrop, "Class Resource Preview", "Shows the selected class/spec resource below without changing your character, spec or saved settings.", { hook = true, owner = "ANCHOR_RIGHT" })
    end
    M.AddRefresher(ctx, function()
        previewDrop:SetValue(M.GetClassPowerPreviewSpecKey())
    end)

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

    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, head, quickSetup, { width = 88 })
    end
    M.WireEditModeButton(ctx, edit)
    BuildInlineClassPowerPreview(ctx, b)

    local layoutWidth = ctx.width or 900
    local compactLayout = layoutWidth < 620
    local display = b:CollapsibleSection("classpower_display", "Layout", compactLayout and 620 or 360, true)
    local cpControls = {}
    local textControls = {}
    local dpbControls = {}
    local dpbPlayerControls = {}
    local altManaControls = {}
    local RefreshClassPowerControls
    local function AddControls(list, ...)
        for i = 1, select("#", ...) do
            list[#list + 1] = select(i, ...)
        end
    end
    local function PlaceColumn(parent, x, y, step, width, titleJustify, ...)
        for i = 1, select("#", ...) do
            MoveWidget(select(i, ...), parent, x, y - ((i - 1) * step), width, titleJustify)
        end
    end

    local cpEnable = SwitchAt(ctx, display, "Class Resource", 32, -64, 180, Bars, "showClassPower", true, function()
        ApplyClassPower()
        if RefreshClassPowerControls then RefreshClassPowerControls() end
    end)
    local cpShape = BindTableDropdown(ctx, display, "Shape", VT("BAR", "Bar", "CIRCLE", "Circle", "DIAMOND", "Diamond", "HEX", "Hex"), 260, Bars, "classPowerShape", "BAR", ApplyClassPower)
    local cpHeight = BindTableSlider(ctx, display, "Height", 1, 40, 1, 300, Bars, "classPowerHeight", 4, ApplyClassPower)
    local cpWidthMode = BindTableDropdown(ctx, display, "Width mode", VT("player", "Player frame", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns", "tracked_buffs", "Tracked Buffs", "custom", "Custom"), 260, Bars, "classPowerWidthMode", "player", ApplyClassPower)
    local cpWidth = BindTableSlider(ctx, display, "Width", 30, 800, 1, 300, Bars, "classPowerWidth", 0, ApplyClassPower)
    local cpX = BindTableSlider(ctx, display, "Offset X", -800, 800, 1, 300, Bars, "classPowerOffsetX", 0, ApplyClassPower)
    local cpY = BindTableSlider(ctx, display, "Offset Y", -800, 800, 1, 300, Bars, "classPowerOffsetY", 0, ApplyClassPower)
    local cpLevel = BindTableSlider(ctx, display, "Frame level", 0, 30, 1, 300, Bars, "classPowerFrameLevelOffset", 5, ApplyClassPower)
    AddControls(cpControls, cpShape, cpHeight, cpWidthMode, cpX, cpY, cpLevel)
    local layoutLeftX = 32
    local layoutRightX = compactLayout and layoutLeftX or min(max(430, floor(layoutWidth * 0.52)), max(360, layoutWidth - 360))
    local layoutLeftW = compactLayout and max(250, layoutWidth - layoutLeftX - 32) or max(250, layoutRightX - layoutLeftX - 42)
    local layoutRightW = compactLayout and layoutLeftW or max(250, layoutWidth - layoutRightX - 32)
    local layoutControlW = compactLayout and max(250, min(320, layoutWidth - layoutLeftX - 42)) or 300
    local positionCardY = compactLayout and -350 or -38
    local positionTopY = compactLayout and -404 or -92
    W.ControlCard(display, "Bar", nil, layoutLeftX - 14, -38, layoutLeftW + 28, compactLayout and 292 or 306)
    W.ControlCard(display, "Position", nil, layoutRightX - 14, positionCardY, layoutRightW + 28, 232)
    MoveWidget(cpEnable, display, layoutLeftX, -78)
    PlaceColumn(display, layoutLeftX, -116, 54, layoutControlW, nil, cpShape, cpHeight, cpWidthMode, cpWidth)
    PlaceColumn(display, layoutRightX, positionTopY, 54, layoutControlW, nil, cpX, cpY, cpLevel)

    local behavior = b:CollapsibleSection("classpower_behavior", "Behavior", 206, false)
    local cpAnchor = BindTableToggle(ctx, behavior, "Anchor to Essential Cooldown", Bars, "classPowerAnchorToCooldown", false, ApplyClassPower)
    local cpCharged = BindTableToggle(ctx, behavior, "Show empowered combo points", Bars, "showChargedComboPoints", true, ApplyClassPower)
    local cpText = BindTableToggle(ctx, behavior, "Show resource text", Bars, "classPowerShowText", false, ApplyClassPower)
    local cpRune = BindTableToggle(ctx, behavior, "Show rune time (per rune)", Bars, "runeShowTime", true, ApplyClassPower)
    local cpReverse = BindTableToggle(ctx, behavior, "Fill right-to-left", Bars, "classPowerFillReverse", false, ApplyClassPower)
    local cpEle = BindTableToggle(ctx, behavior, "Show Maelstrom bar (Ele)", Bars, "showEleMaelstrom", false, ApplyClassPower)
    local cpEbon = BindTableToggle(ctx, behavior, "Show Ebon Might timer (Aug)", Bars, "showEbonMight", true, ApplyClassPower)
    local cpShadow = BindTableToggle(ctx, behavior, "Show Insanity bar (Shadow)", Bars, "showShadowMana", false, ApplyClassPower)
    local cpPrediction = BindTableToggle(ctx, behavior, "Show resource prediction", Bars, "classPowerShowPrediction", true, ApplyClassPower)
    AddControls(cpControls, cpAnchor, cpCharged, cpText, cpRune, cpReverse, cpEle, cpEbon, cpShadow, cpPrediction)
    local behaviorRightX = min(max(380, floor((ctx.width or 900) * 0.45)), max(320, (ctx.width or 900) - 420))
    local behaviorW = behavior._msuf2Width or ctx.width or 900
    local behaviorLeftW = max(280, behaviorRightX - 42)
    local behaviorRightW = max(280, behaviorW - behaviorRightX - 28)
    W.ControlCardBackdrop(behavior, 14, -38, behaviorLeftW, 154)
    W.ControlCardBackdrop(behavior, behaviorRightX - 14, -38, behaviorRightW + 14, 154)
    PlaceColumn(behavior, 14, -38, 32, nil, nil, cpAnchor, cpCharged, cpText, cpRune, cpReverse)
    PlaceColumn(behavior, behaviorRightX, -38, 32, nil, nil, cpEle, cpEbon, cpShadow, cpPrediction)

    local visual = b:CollapsibleSection("classpower_visuals", "Style", 430, false)
    local styleWidth = visual._msuf2Width or ctx.width or 900
    local styleInnerW = max(320, styleWidth - 64)
    local styleLeftX = 32
    local styleCardW = min(540, styleInnerW)
    local styleControlW = min(360, styleCardW - 32)
    local styleTabFrames = {}
    local function CurrentStyleTab()
        local tab = M.classPowerStyleTab or "resources"
        if tab ~= "resources" and tab ~= "text" and tab ~= "opacity" and tab ~= "pips" then tab = "resources" end
        return tab
    end
    local function RefreshStyleTabs()
        local tab = CurrentStyleTab()
        for key, frame in pairs(styleTabFrames) do frame:SetShown(key == tab) end
    end
    local function SetStyleTab(tab)
        tab = (tab == "text" or tab == "opacity" or tab == "pips") and tab or "resources"
        if type(M.PersistMenuStateValue) == "function" then
            M.PersistMenuStateValue("classPowerStyleTab", tab)
        else
            M.classPowerStyleTab = tab
        end
        RefreshStyleTabs()
    end

    local styleTabs = W.Segment(visual, "Style area", VT("resources", "Textures", "text", "Text", "opacity", "Opacity", "pips", "Pips"), min(620, styleInnerW))
    MoveWidget(styleTabs, visual, styleLeftX, -44, min(620, styleInnerW), "LEFT")
    M.BindSegment(ctx, styleTabs, CurrentStyleTab, SetStyleTab)

    local function StyleTabFrame(key)
        return M.UnitSectionsShared.MakeTabFrame(visual, key, -88, styleWidth, styleTabFrames)
    end
    local resourcesFrame, textFrame = StyleTabFrame("resources"), StyleTabFrame("text")
    local opacityFrame, pipsFrame = StyleTabFrame("opacity"), StyleTabFrame("pips")
    if styleTabs.SetValue then styleTabs:SetValue(CurrentStyleTab()) end
    M.AddRefresher(ctx, RefreshStyleTabs)
    RefreshStyleTabs()

    local cpColor = BindTableToggle(ctx, resourcesFrame, "Color by resource type", Bars, "classPowerColorByType", true, ApplyClassPower)
    local cpComboColor = BindTableDropdown(ctx, resourcesFrame, "Combo point colors", VT("default", "Resource color", "ramp", "Combo ramp", "custom", "Custom slots"), 260, Bars, "classPowerComboPointColorMode", "default", ApplyClassPower)
    local cpFgTex = BindTableDropdown(ctx, resourcesFrame, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "classPowerTexture", "", ApplyClassPower)
    local cpBgTex = BindTableDropdown(ctx, resourcesFrame, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "classPowerBgTexture", "", ApplyClassPower)
    local cpFont = BindTableSlider(ctx, textFrame, "Font size", 6, 32, 1, 300, Bars, "classPowerFontSize", 16, ApplyClassPower)
    local cpTextX = BindTableSlider(ctx, textFrame, "Text X", -200, 200, 1, 300, Bars, "classPowerTextOffsetX", 0, ApplyClassPower)
    local cpTextY = BindTableSlider(ctx, textFrame, "Text Y", -200, 200, 1, 300, Bars, "classPowerTextOffsetY", 0, ApplyClassPower)
    local cpBg = BindBarsAlphaPercent(ctx, opacityFrame, "BG opacity", "classPowerBgAlpha", 0.3, ApplyClassPower, 1)
    local cpFilled = BindBarsAlphaPercent(ctx, opacityFrame, "Filled %", "classPowerFilledAlpha", 1.0, ApplyClassPower, 5)
    local cpEmpty = BindBarsAlphaPercent(ctx, opacityFrame, "Empty %", "classPowerEmptyAlpha", 0.3, ApplyClassPower, 5)
    local cpSeparator = BindTableSlider(ctx, pipsFrame, "Separator", 0, 4, 1, 300, Bars, "classPowerTickWidth", 1, ApplyClassPower)
    local cpOutline = BindTableSlider(ctx, pipsFrame, "Outline", 0, 4, 1, 300, Bars, "classPowerOutline", 1, ApplyClassPower)
    local cpGap = BindTableSlider(ctx, pipsFrame, "Pip gap", 0, 8, 1, 300, Bars, "classPowerGap", 0, ApplyClassPower)
    AddControls(cpControls, cpColor, cpComboColor, cpBg, cpSeparator, cpOutline, cpFilled, cpEmpty, cpGap, cpFgTex, cpBgTex)
    AddControls(textControls, cpFont, cpTextX, cpTextY)
    W.ControlCard(resourcesFrame, "Resource & Textures", nil, styleLeftX - 14, -38, styleCardW + 28, 248)
    W.ControlCard(textFrame, "Text", nil, styleLeftX - 14, -38, styleCardW + 28, 210)
    W.ControlCard(opacityFrame, "Opacity", nil, styleLeftX - 14, -38, styleCardW + 28, 204)
    W.ControlCard(pipsFrame, "Pips & Border", nil, styleLeftX - 14, -38, styleCardW + 28, 230)
    MoveWidget(cpColor, resourcesFrame, styleLeftX, -72)
    MoveWidget(cpComboColor, resourcesFrame, styleLeftX, -104, styleControlW)
    PlaceColumn(resourcesFrame, styleLeftX, -192, 54, styleControlW, nil, cpFgTex, cpBgTex)
    PlaceColumn(textFrame, styleLeftX, -84, 52, styleControlW, nil, cpFont, cpTextX, cpTextY)
    PlaceColumn(opacityFrame, styleLeftX, -84, 52, styleControlW, nil, cpBg, cpFilled, cpEmpty)
    PlaceColumn(pipsFrame, styleLeftX, -84, 52, styleControlW, nil, cpSeparator, cpOutline, cpGap)

    local visibility = b:CollapsibleSection("classpower_visibility", "Auto-Hide", 216, false)
    local visibilityW = min(560, (visibility._msuf2Width or ctx.width or 900) - 28)
    W.ControlCard(visibility, "Auto-Hide Rules", nil, 14, -54, visibilityW, 142)
    local hideOOC = SwitchAt(ctx, visibility, "Hide out of combat", 32, -86, visibilityW - 48, Bars, "classPowerHideOOC", false, ApplyClassPower)
    local hideFull = SwitchAt(ctx, visibility, "Hide when full", 32, -118, visibilityW - 48, Bars, "classPowerHideWhenFull", false, ApplyClassPower)
    local hideEmpty = SwitchAt(ctx, visibility, "Hide when empty", 32, -150, visibilityW - 48, Bars, "classPowerHideWhenEmpty", false, ApplyClassPower)
    AddControls(cpControls, hideOOC, hideFull, hideEmpty)

    local dpb = b:CollapsibleSection("classpower_detached_power", "Detached Power Bar", 382, false)
    local dpbCardW = min(620, (dpb._msuf2Width or ctx.width or 900) - 28)
    local dpbControlW = min(360, dpbCardW - 64)
    W.ControlCard(dpb, "Detached Power Bar", "Only applies when power bar is detached.", 14, -38, dpbCardW, 284)
    local dpbMode = W.Dropdown(dpb, "Width mode", VT("manual", "Manual", "cooldown", "Essential Cooldowns", "utility", "Utility Cooldowns", "tracked_buffs", "Tracked Buffs"), 260)
    M.BindDropdown(ctx, dpbMode,
        function() return Bars().detachedPowerBarWidthMode or "manual" end,
        function(v)
            Bars().detachedPowerBarWidthMode = (v ~= "manual") and v or nil
            ApplyDetachedPowerBar()
        end)
    local dpbShape = W.Dropdown(dpb, "Player power shape", VT("FOLLOW_CLASS", "Follow Class Resource", "BAR", "Bar", "ROUND", "Round", "CRYSTAL", "Crystal"), 300)
    M.BindDropdown(ctx, dpbShape,
        function()
            local db = M.EnsureDB()
            local player = db.player or {}
            local v = tostring(player.detachedPowerBarShape or "FOLLOW_CLASS"):upper()
            if v ~= "FOLLOW_CLASS" and v ~= "BAR" and v ~= "ROUND" and v ~= "CRYSTAL" then v = "FOLLOW_CLASS" end
            return v
        end,
        function(v)
            v = tostring(v or "FOLLOW_CLASS"):upper()
            if v ~= "FOLLOW_CLASS" and v ~= "BAR" and v ~= "ROUND" and v ~= "CRYSTAL" then v = "FOLLOW_CLASS" end
            local db = M.EnsureDB()
            db.player = db.player or {}
            db.player.detachedPowerBarShape = v
            ApplyDetachedPowerBar()
        end)
    local dpbFg = BindTableDropdown(ctx, dpb, "Foreground texture", function() return TextureValues("Use global bar texture") end, 300, Bars, "detachedPowerBarTexture", "", ApplyDetachedPowerBar)
    local dpbBg = BindTableDropdown(ctx, dpb, "Background texture", function() return TextureValues("Use foreground texture") end, 300, Bars, "detachedPowerBarBgTexture", "", ApplyDetachedPowerBar)
    local dpbOutline = BindTableSlider(ctx, dpb, "Power bar outline", 0, 6, 1, 300, Bars, "detachedPowerBarOutline", 1, ApplyDetachedPowerBarOutline)
    PlaceColumn(dpb, 32, -100, 54, dpbControlW, "LEFT", dpbMode, dpbShape, dpbFg, dpbBg, dpbOutline)
    AddControls(dpbControls, dpbMode, dpbFg, dpbBg, dpbOutline)
    AddControls(dpbPlayerControls, dpbShape)

    local altMana = b:CollapsibleSection("classpower_alt_mana", "Alternative Mana Bar", 306, false)
    local altManaCardW = min(620, (altMana._msuf2Width or ctx.width or 900) - 28)
    local altManaControlW = min(360, altManaCardW - 64)
    W.ControlCard(altMana, "Alternative Mana Bar", "Shadow, Ret, Ele, Enh, Balance, Feral, WW", 14, -38, altManaCardW, 234)
    local altManaToggle = SwitchAt(ctx, altMana, "Show mana bar (dual resource)", 32, -98, altManaControlW, Bars, "showAltMana", false, ApplyClassPower)
    local altManaHeight = BindTableSlider(ctx, altMana, "Height", 2, 30, 1, 300, Bars, "altManaHeight", 4, ApplyClassPower)
    local altManaY = BindTableSlider(ctx, altMana, "Y offset", -50, 50, 1, 300, Bars, "altManaOffsetY", -2, ApplyClassPower)
    PlaceColumn(altMana, 32, -138, 54, altManaControlW, "LEFT", altManaHeight, altManaY)
    AddControls(altManaControls, altManaHeight, altManaY)

    RefreshClassPowerControls = function()
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
        for i = 1, #cpControls do SetControlEnabled(cpControls[i], cpOn) end
        SetControlEnabled(cpWidth, customWidth)
        local classShapeIsBar = NormalizeClassPowerShape(bars.classPowerShape) == "BAR"
        SetControlEnabled(cpSeparator, cpOn and classShapeIsBar)
        SetControlEnabled(cpOutline, cpOn and classShapeIsBar)
        for i = 1, #textControls do SetControlEnabled(textControls[i], textOn) end
        for i = 1, #dpbControls do SetControlEnabled(dpbControls[i], anyDetached) end
        for i = 1, #dpbPlayerControls do SetControlEnabled(dpbPlayerControls[i], playerDetached) end
        local altOn = BoolValue(bars, "showAltMana", false)
        for i = 1, #altManaControls do SetControlEnabled(altManaControls[i], altOn) end
        SetControlEnabled(altManaToggle, true)
        SetControlEnabled(cpEnable, true)
    end
    M.RefreshClassPowerDetachedState = RefreshClassPowerControls
    M.AddRefresher(ctx, RefreshClassPowerControls)
    RefreshClassPowerControls()
    MaybeOfferQuickSetup()

    ctx:SetContentHeight(math.abs(b.y) + 42)
end

M.RegisterPage("classpower", { title = "MSUF Class Resources", build = BuildClassPower, version = 8 })
