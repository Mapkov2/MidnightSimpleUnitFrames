-- ============================================================================
-- MSUF_Options_ClassPower_QuickSetup.lua
--
-- "Quick Setup: Detached Class Bar" — One-click configuration for a fully
-- detached, CDM-anchored class resource + power bar combo, positioned ABOVE
-- the Essential Cooldowns bar.
--
-- Features:
--   - First-time popup: when the Class Resources tab is opened for the first
--     time, a prompt offers to run the quick setup automatically.
--     Flag stored in MSUF_DB.general.quickSetupClassBarOffered.
--   - Button: always available in the quick-action row for manual triggering.
--   - Two-phase apply: handles specs without class resources (Havoc DH etc.).
--   - Width mode: both CP and DPB auto-match Essential Cooldown width.
--   - Undo via popup.
--
-- Debug:
--   /run MSUF_QuickSetup_ResetFirstRun()
--   Resets the "already offered" flag so the first-time popup shows again.
--
-- Architecture:
--   - Injection via hooksecurefunc on MSUF_ClassPower_SyncOptions.
--   - Secret-safe: no value comparisons, pure boolean/number writes.
-- ============================================================================

if _G.__MSUF_QuickSetup_ClassBar_Loaded then return end
_G.__MSUF_QuickSetup_ClassBar_Loaded = true

-- Search helper (additive): quick setup lives under Class Resources.
if _G and _G.MSUF_Search_RegisterRoots then
    _G.MSUF_Search_RegisterRoots({ "classpower" }, { "MSUF_ClassPowerOptionsPanel" }, "Class Resources")
end

local type, tonumber = type, tonumber
local math_floor, math_ceil = math.floor, math.ceil

-- Localization
local ns = (_G and _G.MSUF_NS) or {}
local L = ns.L or {}
if not getmetatable(L) then
    setmetatable(L, { __index = function(_, k) return k end })
end
local function TR(v) return (type(v) == "string" and L[v]) or v end

-- Chat helper
local function QS_Print(msg)
    local prefix = "|cff00ccff[MSUF QuickSetup]|r "
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(prefix .. msg)
    end
end

-- ============================================================================
-- Constants
-- ============================================================================
local DEFAULT_CP_HEIGHT  = 4
local DEFAULT_DPB_HEIGHT = 6
local DPB_GAP            = 2
local CDM_GAP            = 2
local FALLBACK_Y_FRAC    = 0.60

-- DB flag key
local FLAG_KEY = "quickSetupClassBarOffered"

-- ============================================================================
-- Snapshot keys
-- ============================================================================
local BARS_KEYS = {
    "showClassPower",
    "classPowerShowText",
    "classPowerAnchorToCooldown",
    "classPowerWidthMode",
    "showEleMaelstrom",
    "showEbonMight",
    "showChargedComboPoints",
    "runeShowTimeText",
    "classPowerOffsetX",
    "classPowerOffsetY",
    "classPowerOutline",
    "detachedPowerBarWidthMode",
    "detachedPowerBarOutline",
    "showPlayerPowerBar",
}

local PLAYER_KEYS = {
    "showPower",
    "powerBarDetached",
    "detachedPowerBarSyncClassPower",
    "detachedPowerBarAnchorToClassPower",
    "detachedPowerBarTextOnBar",
    "detachedPowerBarOffsetX",
    "detachedPowerBarOffsetY",
    -- Per-unit text override (mirrors _MSUF_HPText_EnableOverride fields)
    "hpPowerTextOverride",
    "hpTextMode",
    "powerTextMode",
    "hpTextSeparator",
    "powerTextSeparator",
    "hpTextSpacerEnabled",
    "hpTextSpacerX",
    "powerTextSpacerEnabled",
    "powerTextSpacerX",
    "absorbTextMode",
    "absorbAnchorMode",
    "hpTextAnchor",
    "powerTextAnchor",
}

-- ============================================================================
-- Snapshot / Restore
-- ============================================================================
local function SnapshotState()
    if type(MSUF_DB) ~= "table" then return nil end
    local snap = {}

    snap.bars = {}
    local b = MSUF_DB.bars
    if type(b) == "table" then
        for i = 1, #BARS_KEYS do snap.bars[BARS_KEYS[i]] = b[BARS_KEYS[i]] end
    end

    snap.player = {}
    local p = MSUF_DB.player
    if type(p) == "table" then
        for i = 1, #PLAYER_KEYS do snap.player[PLAYER_KEYS[i]] = p[PLAYER_KEYS[i]] end
    end

    return snap
end

local function RestoreState(snap)
    if type(snap) ~= "table" or type(MSUF_DB) ~= "table" then return end
    if type(snap.bars) == "table" then
        MSUF_DB.bars = MSUF_DB.bars or {}
        for i = 1, #BARS_KEYS do MSUF_DB.bars[BARS_KEYS[i]] = snap.bars[BARS_KEYS[i]] end
    end
    if type(snap.player) == "table" then
        MSUF_DB.player = MSUF_DB.player or {}
        for i = 1, #PLAYER_KEYS do MSUF_DB.player[PLAYER_KEYS[i]] = snap.player[PLAYER_KEYS[i]] end
    end
end

-- ============================================================================
-- CDM detection helpers
-- ============================================================================
local function GetVisibleCDM()
    local ecv = _G["EssentialCooldownViewer"]
    if ecv and ecv.IsShown and ecv:IsShown()
       and ecv.GetHeight and ecv.GetCenter then
        local h = ecv:GetHeight()
        if type(h) == "number" and h > 0 then return ecv end
    end
    return nil
end

local function IsCPContainerVisible()
    local cpc = _G["MSUF_ClassPowerContainer"]
    return cpc and cpc.IsShown and cpc:IsShown()
end

local function GetPlayerFrame()
    return (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames.player)
        or _G.MSUF_player
end

-- ============================================================================
-- Position calculations
-- ============================================================================

-- Path A: CP above CDM (normal path)
local function CalcCPAboveCDM(ecv)
    local bars = (type(MSUF_DB) == "table" and type(MSUF_DB.bars) == "table")
                 and MSUF_DB.bars or {}
    local cpH  = tonumber(bars.classPowerHeight) or DEFAULT_CP_HEIGHT
    local playerDB = (type(MSUF_DB) == "table" and type(MSUF_DB.player) == "table")
                     and MSUF_DB.player or {}
    local dpbH = tonumber(playerDB.detachedPowerBarHeight) or DEFAULT_DPB_HEIGHT
    local ecvH = ecv:GetHeight()

    return {
        cpOffsetX  = 0,
        cpOffsetY  = math_ceil(ecvH + CDM_GAP + cpH + DPB_GAP + dpbH),
        dpbOffsetX = 0,
        dpbOffsetY = -DPB_GAP,
        anchorCPtoCDM = true,
        anchorDPBtoCP = true,
    }
end

-- Path B: DPB above CDM when CP is hidden (Havoc DH etc.)
local function CalcDPBAboveCDM_NoCP(ecv)
    local playerDB = (type(MSUF_DB) == "table" and type(MSUF_DB.player) == "table")
                     and MSUF_DB.player or {}
    local dpbH = tonumber(playerDB.detachedPowerBarHeight) or DEFAULT_DPB_HEIGHT

    local pf = GetPlayerFrame()
    local zero = { cpOffsetX = 0, cpOffsetY = 0, dpbOffsetX = 0, dpbOffsetY = -DPB_GAP,
                   anchorCPtoCDM = true, anchorDPBtoCP = true }
    if not (pf and pf.GetLeft and pf.GetBottom and pf.GetEffectiveScale) then return zero end

    local pfLeft = pf:GetLeft()
    local pfBot  = pf:GetBottom()
    if not (pfLeft and pfBot) then return zero end

    local pfScale  = pf:GetEffectiveScale()  or 1
    local ecvScale = ecv:GetEffectiveScale() or 1
    if pfScale  <= 0 then pfScale  = 1 end
    if ecvScale <= 0 then ecvScale = 1 end

    local pfLeft_abs = pfLeft * pfScale
    local pfBot_abs  = pfBot  * pfScale

    local ecvCX_abs  = (select(1, ecv:GetCenter()) or 0) * ecvScale
    local ecvTop_abs = (ecv:GetTop() or 0) * ecvScale
    local ecvW_abs   = (ecv:GetWidth() or 200) * ecvScale

    local dpbH_abs       = dpbH * pfScale
    local targetTop_abs  = ecvTop_abs + CDM_GAP * pfScale + dpbH_abs
    local targetLeft_abs = ecvCX_abs - ecvW_abs / 2

    return {
        cpOffsetX  = 0,
        cpOffsetY  = 0,
        dpbOffsetX = math_floor((targetLeft_abs - pfLeft_abs) / pfScale + 0.5),
        dpbOffsetY = math_floor((targetTop_abs - pfBot_abs) / pfScale + 0.5),
        anchorCPtoCDM = true,
        anchorDPBtoCP = false,
    }
end

-- Path C: no CDM → screen center
local function CalcScreenCenter()
    local zero = { cpOffsetX = 0, cpOffsetY = 0, dpbOffsetX = 0, dpbOffsetY = -DPB_GAP,
                   anchorCPtoCDM = false, anchorDPBtoCP = true }

    local pf = GetPlayerFrame()
    if not (pf and pf.GetLeft and pf.GetTop and pf.GetWidth and pf.GetEffectiveScale) then return zero end

    local pfLeft = pf:GetLeft()
    local pfTop  = pf:GetTop()
    local pfW    = pf:GetWidth()
    if not (pfLeft and pfTop and pfW) then return zero end

    local pfScale = pf:GetEffectiveScale() or 1
    if pfScale <= 0 then pfScale = 1 end

    local uip = UIParent
    local uipScale = (uip and uip.GetEffectiveScale and uip:GetEffectiveScale()) or 1
    if uipScale <= 0 then uipScale = 1 end

    local screenW = (uip and uip.GetWidth  and uip:GetWidth())  or 1920
    local screenH = (uip and uip.GetHeight and uip:GetHeight()) or 1080

    local pfLeft_abs = pfLeft * pfScale
    local pfTop_abs  = pfTop  * pfScale

    local cpW = math_floor(pfW + 0.5)
    if cpW < 30 then cpW = 275 end

    local targetX_abs = screenW * uipScale / 2
    local targetY_abs = screenH * uipScale * FALLBACK_Y_FRAC

    return {
        cpOffsetX  = math_floor(targetX_abs / pfScale - pfLeft - 2 - cpW / 2 + 0.5),
        cpOffsetY  = math_floor(targetY_abs / pfScale - pfTop + 2 + 0.5),
        dpbOffsetX = 0,
        dpbOffsetY = -DPB_GAP,
        anchorCPtoCDM = false,
        anchorDPBtoCP = true,
    }
end

-- ============================================================================
-- DB writes
-- ============================================================================
local function ApplyPhase1(offsets)
    if type(MSUF_DB) ~= "table" then return end

    MSUF_DB.bars = MSUF_DB.bars or {}
    local b = MSUF_DB.bars

    b.showClassPower              = true
    b.classPowerShowText          = true
    b.classPowerAnchorToCooldown  = offsets.anchorCPtoCDM and true or false
    b.classPowerWidthMode         = "cooldown"
    b.detachedPowerBarWidthMode   = "cooldown"
    b.showEleMaelstrom            = true
    b.showEbonMight               = true
    b.showChargedComboPoints      = true
    b.runeShowTimeText            = true
    b.classPowerOffsetX           = offsets.cpOffsetX
    b.classPowerOffsetY           = offsets.cpOffsetY
    b.classPowerOutline           = 1
    b.detachedPowerBarOutline     = 1
    -- Force player power bar ON — installer requires visible power bar
    b.showPlayerPowerBar          = true

    MSUF_DB.player = MSUF_DB.player or {}
    local p = MSUF_DB.player

    -- Force per-unit power display ON
    p.showPower                          = true
    p.powerBarDetached                   = true
    p.detachedPowerBarSyncClassPower     = offsets.anchorDPBtoCP and true or false
    p.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    p.detachedPowerBarTextOnBar          = true
    p.detachedPowerBarOffsetX            = offsets.dpbOffsetX
    p.detachedPowerBarOffsetY            = offsets.dpbOffsetY

    -- ── Per-unit text override for player ──
    -- Mirrors _MSUF_HPText_EnableOverride: copy all shared values first so
    -- nothing changes except the one key we want, then override powerTextMode.
    local g = MSUF_DB.general or {}

    p.hpPowerTextOverride  = true

    -- Copy shared → player (only if player doesn't already have a value)
    if p.hpTextMode          == nil then p.hpTextMode          = g.hpTextMode          end
    if p.powerTextMode       == nil then p.powerTextMode       = g.powerTextMode       end
    if p.hpTextSeparator     == nil then p.hpTextSeparator     = g.hpTextSeparator     end
    if p.powerTextSeparator  == nil then
        p.powerTextSeparator = (g.powerTextSeparator ~= nil) and g.powerTextSeparator
                                                               or g.hpTextSeparator
    end
    if p.hpTextSpacerEnabled    == nil then p.hpTextSpacerEnabled    = g.hpTextSpacerEnabled    end
    if p.hpTextSpacerX          == nil then p.hpTextSpacerX          = g.hpTextSpacerX          end
    if p.powerTextSpacerEnabled == nil then p.powerTextSpacerEnabled = g.powerTextSpacerEnabled end
    if p.powerTextSpacerX       == nil then p.powerTextSpacerX       = g.powerTextSpacerX       end
    if p.absorbTextMode         == nil then p.absorbTextMode         = g.absorbTextMode         end
    if p.absorbAnchorMode       == nil then p.absorbAnchorMode       = g.absorbAnchorMode       end
    if p.hpTextAnchor           == nil then p.hpTextAnchor           = g.hpTextAnchor           end
    if p.powerTextAnchor        == nil then p.powerTextAnchor        = g.powerTextAnchor        end

    -- Now set the actual target: full current value only
    p.powerTextMode = "CURRENT"
end

local function ApplyPhase2_NoCPFix(offsets)
    if type(MSUF_DB) ~= "table" then return end
    MSUF_DB.player = MSUF_DB.player or {}
    local p = MSUF_DB.player
    p.detachedPowerBarSyncClassPower     = offsets.anchorDPBtoCP and true or false
    p.detachedPowerBarAnchorToClassPower = offsets.anchorDPBtoCP and true or false
    p.detachedPowerBarOffsetX            = offsets.dpbOffsetX
    p.detachedPowerBarOffsetY            = offsets.dpbOffsetY
end

-- ============================================================================
-- Refresh chain
-- ============================================================================
local function RefreshCP()
    if type(_G.MSUF_ClassPower_Refresh) == "function" then
        _G.MSUF_ClassPower_Refresh()
    end
end

local function RefreshAll()
    RefreshCP()
    if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == "function" then
        _G.MSUF_ApplyPowerBarEmbedLayout_All()
    end
    if type(_G.MSUF_ApplyBarOutlineThickness_All) == "function" then
        _G.MSUF_ApplyBarOutlineThickness_All()
    end
    if type(_G.MSUF_RefreshDPBOutlineSliderState) == "function" then
        _G.MSUF_RefreshDPBOutlineSliderState()
    end
    -- Refresh text rendering (invalidate cache + mark frames dirty for re-render)
    if type(_G.MSUF_UFCore_NotifyConfigChanged) == "function" then
        _G.MSUF_UFCore_NotifyConfigChanged(nil, true, true, "QuickSetup")
    end
    if type(_G.MSUF_ClassPower_SyncOptions) == "function" then
        _G.MSUF_ClassPower_SyncOptions()
    end
end

-- ============================================================================
-- "Offered" flag read/write
-- ============================================================================
local function HasBeenOffered()
    if type(MSUF_DB) ~= "table" then return false end
    local g = MSUF_DB.general
    if type(g) ~= "table" then return false end
    return g[FLAG_KEY] == true
end

local function MarkAsOffered()
    if type(MSUF_DB) ~= "table" then return end
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general[FLAG_KEY] = true
end

-- ============================================================================
-- Confirmation / Result popups
-- ============================================================================
local _undoSnapshot = nil

local function MakePopup(name, text)
    StaticPopupDialogs[name] = {
        text = TR(text),
        button1 = TR("OK"),
        button2 = TR("Undo"),
        OnAccept = function() _undoSnapshot = nil end,
        OnCancel = function()
            if _undoSnapshot then
                RestoreState(_undoSnapshot); _undoSnapshot = nil; RefreshAll()
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = false,
        preferredIndex = 3, showAlert = false,
    }
end

MakePopup("MSUF_QUICKSETUP_CDM",
    "Quick Setup applied!\n\n"
    .. "Class Power + Power Bar are now\n"
    .. "positioned above Essential Cooldowns.\n\n"
    .. "Use Edit Mode for fine-tuning.")

MakePopup("MSUF_QUICKSETUP_CDM_NOCP",
    "Quick Setup applied!\n\n"
    .. "Power Bar is positioned above\n"
    .. "Essential Cooldowns.\n\n"
    .. "Your spec has no class resource bar.\n"
    .. "If you respec, it will appear automatically.\n\n"
    .. "Use Edit Mode for fine-tuning.")

MakePopup("MSUF_QUICKSETUP_NOCDM",
    "Quick Setup applied!\n\n"
    .. "Class Power + Power Bar are detached\n"
    .. "and positioned at screen center.\n\n"
    .. "Essential Cooldowns not detected.\n"
    .. "Enable it for automatic anchoring.\n\n"
    .. "Use Edit Mode for fine-tuning.")

-- ============================================================================
-- Master action
-- ============================================================================
local function ExecuteQuickSetup()
    if type(MSUF_DB) ~= "table" then return end

    -- Mark as offered (regardless of how it was triggered)
    MarkAsOffered()

    local ecv = GetVisibleCDM()

    -- Phase 1: initial calc assuming CP visible
    local offsets
    if ecv then
        offsets = CalcCPAboveCDM(ecv)
    else
        offsets = CalcScreenCenter()
    end

    _undoSnapshot = SnapshotState()
    ApplyPhase1(offsets)
    RefreshCP()

    -- Phase 2: detect if CP actually appeared
    local cpVisible = IsCPContainerVisible()
    local popupName

    if ecv and not cpVisible then
        local fixedOffsets = CalcDPBAboveCDM_NoCP(ecv)
        ApplyPhase2_NoCPFix(fixedOffsets)
        popupName = "MSUF_QUICKSETUP_CDM_NOCP"
    elseif ecv then
        popupName = "MSUF_QUICKSETUP_CDM"
    else
        popupName = "MSUF_QUICKSETUP_NOCDM"
    end

    RefreshAll()
    StaticPopup_Show(popupName)
end

-- ============================================================================
-- First-time offer popup (shown once on first Class Resources tab open)
-- ============================================================================
StaticPopupDialogs["MSUF_QUICKSETUP_FIRSTRUN_OFFER"] = {
    text = TR("Welcome to Class Resources!\n\n"
        .. "Would you like to automatically set up a\n"
        .. "detached Class Bar positioned above your\n"
        .. "Essential Cooldowns?\n\n"
        .. "This configures class resources, power bar,\n"
        .. "anchoring and width matching in one click.\n\n"
        .. "You can always run this later via the\n"
        .. "|cff00ff00Quick Setup: Class Bar|r button below."),
    button1 = TR("Setup Now"),
    button2 = TR("Not Now"),
    OnAccept = function()
        -- Run the quick setup
        MarkAsOffered()
        -- Slight delay so the options panel is fully settled
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, ExecuteQuickSetup)
        else
            ExecuteQuickSetup()
        end
    end,
    OnCancel = function()
        -- Just dismiss, mark as offered
        MarkAsOffered()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    showAlert = true,     -- exclamation mark icon for visibility
}

local _firstRunChecked = false

local function CheckFirstRunOffer()
    if _firstRunChecked then return end
    if HasBeenOffered() then
        _firstRunChecked = true
        return
    end

    -- Panel must be built for the button to exist
    local cpPanel = _G["MSUF_ClassPowerOptionsPanel"]
    if not cpPanel then return end

    _firstRunChecked = true

    -- Show after a brief delay so the tab is visually settled
    if C_Timer and C_Timer.After then
        C_Timer.After(0.15, function()
            if not HasBeenOffered() then
                StaticPopup_Show("MSUF_QUICKSETUP_FIRSTRUN_OFFER")
            end
        end)
    end
end

-- ============================================================================
-- Debug: reset first-run flag
--   /run MSUF_QuickSetup_ResetFirstRun()
-- ============================================================================
_G.MSUF_QuickSetup_ResetFirstRun = function()
    if type(MSUF_DB) == "table" then
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general[FLAG_KEY] = nil
    end
    _firstRunChecked = false
    QS_Print("First-run flag reset. Reopen the Class Resources tab to see the offer popup.")
end

-- ============================================================================
-- Button injection
-- ============================================================================
local _btnInjected = false

local function InjectQuickSetupButton()
    if _btnInjected then return end

    local cpPanel  = _G["MSUF_ClassPowerOptionsPanel"]
    local colorBtn = _G["MSUF_ClassPower_ClassColorButton"]
    if not (cpPanel and colorBtn) then return end

    _btnInjected = true

    local qsBtn = CreateFrame("Button", "MSUF_ClassPower_QuickSetupButton", cpPanel, "UIPanelButtonTemplate")
    qsBtn:SetHeight(22)
    qsBtn:SetText(TR("Quick Setup: Class Bar"))

    do
        local fs = qsBtn:GetFontString()
        local tw = (fs and fs.GetStringWidth and fs:GetStringWidth()) or 0
        local w = tw + 24
        if w < 160 then w = 160 end
        qsBtn:SetWidth(w)
    end

    qsBtn:ClearAllPoints()
    qsBtn:SetPoint("LEFT", colorBtn, "RIGHT", 12, 0)
    qsBtn:SetScript("OnClick", ExecuteQuickSetup)

    -- MSUF midnight skin
    qsBtn._msufNoSlashSkin = true
    if _G.MSUF_SkinMidnightActionButton then
        _G.MSUF_SkinMidnightActionButton(qsBtn)
    else
        qsBtn.__msufMidnightActionSkinned = true
    end

    -- Dynamic tooltip
    qsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(TR("Quick Setup: Detached Class Bar"), 1, 1, 1)
        GameTooltip:AddLine(TR("One-click setup for a ready-to-use class bar:"), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(TR("Detaches power bar from unit frame"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(TR("Positions class bar ABOVE Essential Cooldowns"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(TR("Match width: Essential Cooldowns"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(TR("Syncs & anchors power bar to class resources"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(TR("Enables all features (text, Maelstrom,"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(TR("Ebon Might, charged CP, rune timers)"), 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        local ecv = GetVisibleCDM()
        local cpv = IsCPContainerVisible()
        if ecv and cpv then
            GameTooltip:AddLine(TR("CDM + Class Power detected"), 0.3, 0.9, 0.3)
        elseif ecv then
            GameTooltip:AddLine(TR("CDM detected (no class resource for this spec)"), 0.9, 0.8, 0.3)
        else
            GameTooltip:AddLine(TR("CDM not visible — will center on screen"), 0.9, 0.7, 0.3)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(TR("Click to apply. Undo available in popup."), 0.5, 0.8, 0.5)
        GameTooltip:Show()
    end)
    qsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ============================================================================
-- Combined hook: button injection + first-run check
-- ============================================================================
local function OnSyncOptions()
    InjectQuickSetupButton()
    CheckFirstRunOffer()
end

do
    if type(_G.MSUF_ClassPower_SyncOptions) == "function" then
        hooksecurefunc(_G, "MSUF_ClassPower_SyncOptions", OnSyncOptions)
    end
    if type(_G.MSUF_EnsureClassPowerMenuBuilt) == "function" then
        hooksecurefunc(_G, "MSUF_EnsureClassPowerMenuBuilt", OnSyncOptions)
    end
end
