local addonName, ns = ...
ns = ns or {}
_G.MSUF_NS = _G.MSUF_NS or ns

-- Forward declarations (needed by early popup helpers)
local MSUF_EDITMODE_UNIT_KEYS, MSUF_EDITMODE_UNIT_FIELDS, MSUF_EDITMODE_GENERAL_FIELDS
-- Forward declare: needed so Castbar popup spec tables and builders capture the correct function.
-- Fixes dead Show/Override checkboxes (OnClick=nil) and makes overrides apply instantly.
local ApplyCastbarPopupValues

-- This needs to be refactored - Way to much spagetti code here.
local function MSUF_UFDirty(frame, reason, urgent)
    if not frame then return end
    local md = _G.MSUF_UFCore_MarkDirty
    if type(md) == "function" then
        md(frame, nil, urgent, reason)
        return
    end
    local upd = _G.UpdateSimpleUnitFrame
    if type(upd) == "function" then
        upd(frame)
    end
end

-- Load-order safety: EnsureDB may not be available at the moment Edit Mode code runs (prepatch/load timing).
-- Always guard DB initialization so missing globals don't break Edit Mode entry points.
local function MSUF_EM_EnsureDB()
    if _G.MSUF_DB then
        return true
    end
    local fn = _G.EnsureDB
    if type(fn) == "function" then
        fn()
        return (_G.MSUF_DB ~= nil)
    end
    if ns and type(ns.EnsureDB) == "function" then
        ns.EnsureDB()
        return (_G.MSUF_DB ~= nil)
    end
    return false
end

-- Edit Mode namespace (Phase 1 refactor scaffold)
_G.MSUF_Edit = _G.MSUF_Edit or {}
local Edit = _G.MSUF_Edit
Edit.VERSION = Edit.VERSION or "v10_refactor_phase1"
Edit.Modules = Edit.Modules or {}

Edit.Util   = Edit.Util   or {}
Edit.Bind   = Edit.Bind   or {}
Edit.Preview= Edit.Preview or {}
Edit.Flow   = Edit.Flow   or {}

Edit.UI      = Edit.UI      or {}
Edit.Dock    = Edit.Dock    or {}
Edit.Targets = Edit.Targets or {}

-- Local aliases (avoid repeated global table lookups)
local EM_UI      = Edit.UI
local EM_Dock    = Edit.Dock
local EM_Targets = Edit.Targets

-- Safeguard helpers (fail-open, taint-safe-ish)
local MSUF__SafeCallErrorOnce = {}
local MSUF__SafeCallErrorCountByTag = {}
local MSUF__SafeFeatureErrorCount = {}
local MSUF__SafeFeatureDisabled = {}
local MSUF__SafeFeatureDisableOnce = {}

local MSUF__EditModeFatalDisabled = false
local MSUF__EditModeFatalTag = nil
local MSUF__EditModeFatalReason = nil
local MSUF__EditModeFatalPrinted = false
local MSUF_EditMode_FatalDisable -- forward decl
local MSUF_EM_CombatSafeHideBossPreviewNow -- forward decl
local MSUF_SafeCall -- forward decl (used widely; must be local to avoid global drift)
local MSUF_SafeAfter -- forward decl (used by various helpers; keep local to avoid global drift)
local function MSUF_EM_GetState()
    local st = Edit.State or _G.MSUF_EditState
    if not st then
        st = {
            active = false,
            unitKey = nil,
            popupOpen = false,
            arrowBindingsActive = false,
            pendingSecureCleanup = false,
            fatalDisabled = false,
            fatalTag = nil,
            fatalReason = nil,
        }
        Edit.State = st
        _G.MSUF_EditState = st
    else
        -- Ensure both references stay aligned
        Edit.State = st
        _G.MSUF_EditState = st
    end
    return st
end

local function MSUF_EM_SyncLegacyFromState()
    local st = MSUF_EM_GetState()
    MSUF_UnitEditModeActive = st.active and true or false
    MSUF_CurrentEditUnitKey = st.unitKey
end

-- Any-EditMode listeners (enter/exit notifications)
-- Modules can subscribe to avoid their own polling (e.g. Auras edit-mode previews).
if not _G.MSUF_AnyEditModeListeners then
    _G.MSUF_AnyEditModeListeners = {}
end

if not _G.MSUF_RegisterAnyEditModeListener then
    function _G.MSUF_RegisterAnyEditModeListener(fn)
        if type(fn) ~= "function" then return end
        local t = _G.MSUF_AnyEditModeListeners
        t[#t + 1] = fn
    end
end

-- Any-EditMode state = (MSUF Edit Mode) OR (Blizzard Edit Mode)
-- This is used by modules (Auras2 previews, etc.) to reliably start/stop preview visuals
-- even when MSUF Edit Mode is running unlinked from Blizzard Edit Mode.
local function MSUF_EM_IsBlizzardEditModeActive()
    -- Blizzard Edit Mode integration disabled (TEMP/Hotfix):
    -- Blizzard started transiently showing EditModeManagerFrame during reload/zone transitions,
    -- which can incorrectly force MSUF Edit Mode to open. We now treat Blizzard Edit Mode as unrelated.
    return false
end

local function MSUF_EM_GetAnyEditModeActive()
    local st = MSUF_EM_GetState()
    if type(st) == "table" and st.active == true then
        return true
    end
    return MSUF_EM_IsBlizzardEditModeActive()
end

-- Seed baseline so listeners only fire on transitions.
local MSUF_EM_LastAnyEditMode = MSUF_EM_GetAnyEditModeActive()

local function MSUF_EM_NotifyAnyEditMode(active)
    if active == nil then
        active = MSUF_EM_GetAnyEditModeActive()
    end

    active = active and true or false
    if MSUF_EM_LastAnyEditMode == active then
        return
    end
    MSUF_EM_LastAnyEditMode = active

    local t = _G.MSUF_AnyEditModeListeners
    if not t then return end

    -- Avoid hard dependency on MSUF_FastCall during very early load edge cases
    local call = (type(MSUF_FastCall) == "function") and MSUF_FastCall or function(f, ...) return f(...) end

    for i = 1, #t do
        local fn = t[i]
        if type(fn) == "function" then
            call(fn, active)
        end
    end
end

local function MSUF_EM_ClearKeyboardFocus()

    if ChatEdit_DeactivateChat then
        if ChatEdit_GetActiveWindow then
            local eb = ChatEdit_GetActiveWindow()
            if eb then
                ChatEdit_DeactivateChat(eb)
            end
        end
    end
    -- Clear any active editbox focus
    if GetCurrentKeyBoardFocus then
        local f = GetCurrentKeyBoardFocus()
        if f and f.ClearFocus then
            f:ClearFocus()
        end
    end
end

local MSUF_EM_EnableUpdateSimpleUnitFrameHook

local function MSUF_EM_SetActive(active, unitKey)
    local st = MSUF_EM_GetState()
    local prevActive = st.active and true or false
    st.active = active and true or false
    if st.active then
        if unitKey ~= nil then
            st.unitKey = unitKey
        end
    else
        st.unitKey = nil
    end
    MSUF_EM_SyncLegacyFromState()
    if st.active ~= prevActive then
        MSUF_EM_NotifyAnyEditMode()
    end

    if (not st.active) and prevActive then
        -- Fail-closed: never allow the preview/test mode to persist.
        MSUF_BossTestMode = false

        -- Prefer the shared sync helper (handles secure drivers + per-boss hide rules).
        if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            _G.MSUF_SyncBossUnitframePreviewWithUnitEdit()
        else
            if InCombatLockdown and InCombatLockdown() then
                if MSUF_EM_CombatSafeHideBossPreviewNow then
                    MSUF_EM_CombatSafeHideBossPreviewNow()
                end
            else
                local max = _G.MSUF_MAX_BOSS_FRAMES or 5
                for i = 1, max do
                    local unit = "boss" .. i
                    local f = _G["MSUF_" .. unit] or _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit])
                    if f and f.Hide then
                        f:Hide()
                    end
                end
            end
        end

        -- Also guarantee boss castbar preview is torn down on deactivation (keeps systems consistent).
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
        end
    end

    if st.active and not prevActive then
        if type(MSUF_EM_EnableUpdateSimpleUnitFrameHook) == "function" then
            MSUF_EM_EnableUpdateSimpleUnitFrameHook(true)
        end
    elseif (not st.active) and prevActive then
        if type(MSUF_EM_EnableUpdateSimpleUnitFrameHook) == "function" then
            MSUF_EM_EnableUpdateSimpleUnitFrameHook(false)
        end
    end
    if st.active and not prevActive then
        MSUF_EM_ClearKeyboardFocus()
    end
    if not st.active and MSUF_EM_CombatSafeHideBossPreviewNow then
        MSUF_EM_CombatSafeHideBossPreviewNow()
    end
end

local function MSUF_EM_SetPopupOpen(open)
    local st = MSUF_EM_GetState()
    st.popupOpen = open and true or false
end

local function MSUF_EM_SetArrowBindingsActive(active)
    local st = MSUF_EM_GetState()
    st.arrowBindingsActive = active and true or false
end

local function MSUF_EM_SetPendingSecureCleanup(pending)
    local st = MSUF_EM_GetState()
    st.pendingSecureCleanup = pending and true or false
end

local function MSUF_EM_SetFatalDisabled(tag, reason)
    local st = MSUF_EM_GetState()
    st.fatalDisabled = true
    st.fatalTag = tostring(tag or "?")
    st.fatalReason = tostring(reason or "unknown")
end

local function MSUF_EM_ForceWhiteButtonText(btn)
    if not btn then return end

    -- Prefer white font objects for normal/highlight states.
    if btn.SetNormalFontObject then
        btn:SetNormalFontObject("GameFontHighlight")
    end
    if btn.SetHighlightFontObject then
        btn:SetHighlightFontObject("GameFontHighlight")
    end
    if btn.SetDisabledFontObject then
        btn:SetDisabledFontObject("GameFontDisable")
    end

    local fs = btn.GetFontString and btn:GetFontString()
    if fs and fs.SetTextColor then
        fs:SetTextColor(1, 1, 1, 1)
    end
end

do
    local UIH = (ns and ns.MSUF_EM_UIH) or {}
    if ns then ns.MSUF_EM_UIH = UIH end

    local CreateFrame = CreateFrame

    function UIH.Button(parent, name, w, h, text, template)
        local b = CreateFrame("Button", name, parent, template or "UIPanelButtonTemplate")
        if w and h then b:SetSize(w, h) end
        if text ~= nil and b.SetText then b:SetText(text) end
        if type(MSUF_EM_ForceWhiteButtonText) == "function" then
            MSUF_EM_ForceWhiteButtonText(b)
        end
        return b
    end

    function UIH.ButtonAt(parent, name, w, h, point, rel, relPoint, x, y, text, template)
        local b = UIH.Button(parent, name, w, h, text, template)
        if point and rel then b:SetPoint(point, rel, relPoint or point, x or 0, y or 0)
        elseif point then b:SetPoint(point, x or 0, y or 0) end
        return b
    end

    -- Creates the same checkbox label style we used previously (GameFontHighlightSmall + manual anchor).
    function UIH.TextCheck(parent, name, point, rel, relPoint, x, y, text, onClick, opts)
        local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
        if opts and opts.w and opts.h then cb:SetSize(opts.w, opts.h) end

        if point and rel then cb:SetPoint(point, rel, relPoint or point, x or 0, y or 0)
        elseif point then cb:SetPoint(point, x or 0, y or 0) end

        local font = (opts and opts.font) or "GameFontHighlightSmall"
        local dx   = (opts and opts.dx) or 4
        local dy   = (opts and opts.dy) or 0
        local label = cb:CreateFontString(nil, "ARTWORK", font)
        label:SetPoint("LEFT", cb, "RIGHT", dx, dy)
        label:SetText(text or "")
        cb.text = label

        if onClick then cb:SetScript("OnClick", onClick) end
        return cb
    end
end

function MSUF_EM_DropdownPreset(drop, width, placeholder)
    if not drop then return end
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(drop, width or 150) end
    if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(drop, "LEFT") end
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, placeholder or "") end
end

function MSUF_EM_BuildCopyItems(list, srcValue, labelFn)
    if not list then return nil end
    local out = {}
    for i = 1, #list do
        local v = list[i]
        if v ~= srcValue then
            out[#out + 1] = { value = v, text = labelFn and labelFn(v) or tostring(v) }
        end
    end
    return out
end

function MSUF_EM_InitCopyDropdown(drop, placeholder, itemsProvider, onPick)
    if not drop or not UIDropDownMenu_Initialize or not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then return end
    MSUF_EM_DropdownPreset(drop, 150, placeholder)

    UIDropDownMenu_Initialize(drop, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true

        local items = itemsProvider and itemsProvider()
        if not items then return end

        for i = 1, #items do
            local item = items[i]
            local value = item and item.value
            local label = (item and item.text) or (value ~= nil and tostring(value)) or ""

            info.text = label
            info.func = function()
                if onPick then onPick(value, item) end
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, label) end
                if CloseDropDownMenus then CloseDropDownMenus() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
end

function MSUF_EM_GetCastbarCopyUnits(srcUnit)
    return (srcUnit == "boss") and { "player", "target", "focus" } or { "player", "target", "focus", "boss" }
end

-- Table-driven castbar text field mapping (boss keys differ from prefix-based keys)
local BOSS_CASTBAR_TEXT_MAP = {
    { key = "textX",    boss = "bossCastTextOffsetX",       suffix = "TextOffsetX" },
    { key = "textY",    boss = "bossCastTextOffsetY",       suffix = "TextOffsetY" },
    { key = "showName", boss = "showBossCastName",          suffix = "ShowSpellName" },
    { key = "nameSize", boss = "bossCastSpellNameFontSize", suffix = "SpellNameFontSize" },
    { key = "iconX",    boss = "bossCastIconOffsetX",       suffix = "IconOffsetX" },
    { key = "iconY",    boss = "bossCastIconOffsetY",       suffix = "IconOffsetY" },
    { key = "showIcon", boss = "showBossCastIcon",          suffix = "ShowIcon" },
    { key = "iconSize", boss = "bossCastIconSize",          suffix = "IconSize" },
    { key = "timeX",    boss = "bossCastTimeOffsetX",       suffix = "TimeOffsetX" },
    { key = "timeY",    boss = "bossCastTimeOffsetY",       suffix = "TimeOffsetY" },
    { key = "showTime", boss = "showBossCastTime" },  -- uses showTimeKey for non-boss
    { key = "timeSize", boss = "bossCastTimeFontSize",      suffix = "TimeFontSize" },
}

local function MSUF_EM_GetCastbarPrefix_Safe(u)
    return type(MSUF_GetCastbarPrefix) == "function" and MSUF_GetCastbarPrefix(u) or nil
end

local function MSUF_EM_EnsureCastbarDB()
    MSUF_EM_EnsureDB()
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    return MSUF_DB.general
end

local function MSUF_EM_CopyCastbarSizeSettings(srcUnit, dstUnit)
    if not srcUnit or not dstUnit or srcUnit == dstUnit then return end
    local g = MSUF_EM_EnsureCastbarDB()

    local function getKeys(u)
        if u == "boss" then return "bossCastbarWidth", "bossCastbarHeight" end
        local p = MSUF_EM_GetCastbarPrefix_Safe(u)
        if not p then return nil end
        return p .. "BarWidth", p .. "BarHeight"
    end

    local srcW, srcH = getKeys(srcUnit)
    if not srcW then return end
    local dstW, dstH = getKeys(dstUnit)
    if not dstW then return end

    local w, h = tonumber(g[srcW]), tonumber(g[srcH])
    if w == nil and h == nil then return end
    if w ~= nil then g[dstW] = w end
    if h ~= nil then g[dstH] = h end

    if type(MSUF_ApplyCastbarUnitAndSync) == "function" then
        MSUF_SafeCall("CopyCastbarSize:Apply", MSUF_ApplyCastbarUnitAndSync, dstUnit)
    end
end

local function MSUF_EM_CopyCastbarTextSettings(srcUnit, dstUnit)
    if not srcUnit or not dstUnit or srcUnit == dstUnit then return end
    local g = MSUF_EM_EnsureCastbarDB()

    local function xferFields(fromUnit, toUnit)
        local fromBoss, toBoss = (fromUnit == "boss"), (toUnit == "boss")
        local fromP = not fromBoss and MSUF_EM_GetCastbarPrefix_Safe(fromUnit) or nil
        local toP   = not toBoss   and MSUF_EM_GetCastbarPrefix_Safe(toUnit) or nil
        if not fromBoss and not fromP then return false end
        if not toBoss   and not toP   then return false end
        local fromSTK = type(MSUF_GetCastbarShowTimeKey) == "function" and MSUF_GetCastbarShowTimeKey(fromUnit) or nil
        local toSTK   = type(MSUF_GetCastbarShowTimeKey) == "function" and MSUF_GetCastbarShowTimeKey(toUnit) or nil
        for _, m in ipairs(BOSS_CASTBAR_TEXT_MAP) do
            local srcKey = fromBoss and m.boss or (m.suffix and (fromP .. m.suffix) or (m.key == "showTime" and fromSTK or nil))
            local dstKey = toBoss   and m.boss or (m.suffix and (toP   .. m.suffix) or (m.key == "showTime" and toSTK   or nil))
            if srcKey and dstKey then
                g[dstKey] = g[srcKey]
            end
        end
        return true
    end

    if not xferFields(srcUnit, dstUnit) then return end

    if type(MSUF_ApplyCastbarUnitAndSync) == "function" then
        MSUF_SafeCall("CopyCastbarText:Apply", MSUF_ApplyCastbarUnitAndSync, dstUnit)
    end
end

local function MSUF_EM_RefreshCastbarCopyDropdown(pf, drop, label, placeholder, mode)
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then return end
    if not pf or not drop or not label then return end

    local srcUnit = pf.unit
    label:Show()
    drop:Show()

    local labelFn = (type(MSUF_GetCastbarLabel) == "function") and MSUF_GetCastbarLabel or function(u) return tostring(u) end
    local onPick = function(dstUnit)
        if mode == "size" then
            MSUF_EM_CopyCastbarSizeSettings(srcUnit, dstUnit)
        else
            MSUF_EM_CopyCastbarTextSettings(srcUnit, dstUnit)
        end
    end

    MSUF_EM_InitCopyDropdown(drop, placeholder,
        function()
            return MSUF_EM_BuildCopyItems(MSUF_EM_GetCastbarCopyUnits(srcUnit), srcUnit, labelFn)
        end,
        function(dstUnit) onPick(dstUnit) end
    )
end

local MSUF_EM_UNIT_COPY_ALLOWED = { player=true, target=true, targettarget=true, focus=true, boss=true }

local function MSUF_EM_CopyUnitSettings(srcKey, dstKey, mode)
    if not srcKey or not dstKey or srcKey == dstKey then return end
    MSUF_EM_EnsureDB()
    if not MSUF_DB then return end
    MSUF_DB[srcKey] = MSUF_DB[srcKey] or {}
    MSUF_DB[dstKey] = MSUF_DB[dstKey] or {}

    local src, dst = MSUF_DB[srcKey], MSUF_DB[dstKey]

    local function ForceApplyDestination(changedFonts)
        local st = (type(MSUF_EM_GetState) == "function") and MSUF_EM_GetState()
        local wasOpen = st and st.popupOpen
        if st then st.popupOpen = false end

        if type(MSUF_ApplyUnitFrameKey_Immediate) == "function" then
            MSUF_ApplyUnitFrameKey_Immediate(dstKey)

            if changedFonts then
                if _G.MSUF_UpdateAllFonts then
                    _G.MSUF_UpdateAllFonts()
                elseif ns and ns.MSUF_UpdateAllFonts then
                    ns.MSUF_UpdateAllFonts()
                end
            end

            if MSUF_UpdateEditModeInfo then
                MSUF_UpdateEditModeInfo()
            end
        elseif type(MSUF_ApplyUnitframeKeyAndSync) == "function" then
            MSUF_ApplyUnitframeKeyAndSync(dstKey, changedFonts and true or false)
        elseif type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
            _G.MSUF_ApplyAllSettings_Immediate()
        end

        -- Force text layout update for destination (anchors may have changed)
        if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
            _G.MSUF_ForceTextLayoutForUnitKey(dstKey)
        end

        if st then st.popupOpen = wasOpen end
    end

    if mode == "size" then
        dst.width, dst.height = src.width, src.height
        ForceApplyDestination(false)
        return
    end

    dst.showName, dst.showHP, dst.showPower = src.showName, src.showHP, src.showPower
    dst.nameOffsetX, dst.nameOffsetY = src.nameOffsetX, src.nameOffsetY
    dst.hpOffsetX, dst.hpOffsetY = src.hpOffsetX, src.hpOffsetY
    dst.powerOffsetX, dst.powerOffsetY = src.powerOffsetX, src.powerOffsetY
    dst.nameFontSize, dst.hpFontSize, dst.powerFontSize = src.nameFontSize, src.hpFontSize, src.powerFontSize
    dst.nameTextAnchor, dst.hpTextAnchor, dst.powerTextAnchor = src.nameTextAnchor, src.hpTextAnchor, src.powerTextAnchor

    ForceApplyDestination(true)
end

local function MSUF_EM_GetUnitPopupSrcKey(pf)
    pf = pf or MSUF_PositionPopup
    local unit = pf and pf.unit
    return (unit and type(GetConfigKeyForUnit) == "function" and GetConfigKeyForUnit(unit)) or MSUF_CurrentEditUnitKey
end

local function MSUF_EM_RefreshUnitCopyDropdown(pf, drop, label, placeholder, mode)
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then return end
    if not pf or not drop or not label then return end

    local srcKey = MSUF_EM_GetUnitPopupSrcKey(pf)
    if not srcKey or not MSUF_EM_UNIT_COPY_ALLOWED[srcKey] then
        label:Hide(); drop:Hide()
        return
    end

    label:Show(); drop:Show()

    local labelFn = (type(MSUF_GetUnitLabelForKey) == "function") and MSUF_GetUnitLabelForKey or function(k) return tostring(k) end
    MSUF_EM_InitCopyDropdown(drop, placeholder,
        function()
            return MSUF_EM_BuildCopyItems(MSUF_EDITMODE_UNIT_KEYS, srcKey, labelFn)
        end,
        function(dstKey) MSUF_EM_CopyUnitSettings(srcKey, dstKey, mode) end
    )
end

function MSUF_EM_AddPopupTitleAndClose(pf, titleText)
    if not pf then return end

    local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(titleText or "MSUF Edit")
    pf.title = title

    local closeBtn = (ns and ns.MSUF_EM_UIH and ns.MSUF_EM_UIH.ButtonAt) and ns.MSUF_EM_UIH.ButtonAt(
        pf, "$parentClose", nil, nil, "TOPRIGHT", pf, "TOPRIGHT", -6, -6, nil, "UIPanelCloseButton"
    )

    if closeBtn then
        closeBtn:SetScript("OnClick", function()
            if pf.cancelBtn and pf.cancelBtn.Click then
                pf.cancelBtn:Click()
            else
                pf:Hide()
            end
        end)
        pf.closeBtn = closeBtn
    end
end

function MSUF_EM_AddSectionHeader(pf, key, text, point, rel, relPoint, x, y)
    if not pf then return nil end
    local fs = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint(point or "TOPLEFT", rel or pf, relPoint or (point or "TOPLEFT"), x or 0, y or 0)
    fs:SetText(text or "")
    fs:SetTextColor(1, 0.82, 0, 1)
    if key then pf[key] = fs end
    return fs
end

function MSUF_EM_AddDivider(pf, key, width, point, rel, relPoint, x, y)
    if not pf then return nil end
    local tex = pf:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(1, 1, 1, 0.12)
    tex:SetHeight(1)
    tex:SetWidth(width or 230)
    tex:SetPoint(point or "TOPLEFT", rel or pf, relPoint or (point or "TOPLEFT"), x or 0, y or 0)
    if key then pf[key] = tex end
    return tex
end

local function MSUF_EM_GetGeneralDB()
    MSUF_EM_EnsureDB()

    if not MSUF_DB then
        Edit.Util._fallbackGeneralDB = Edit.Util._fallbackGeneralDB or {}
        return Edit.Util._fallbackGeneralDB
    end

    MSUF_DB.general = MSUF_DB.general or {}
    return MSUF_DB.general
end

-- Snap (removed)
-- The snapping feature (grid/frames docking) has been fully removed.
-- Keep no-op compatibility stubs to avoid nil errors from legacy callsites.
local function MSUF_EM_GetSnapConfig()
    local g = MSUF_EM_GetGeneralDB()
    return g, false, "grid", false, false
end

local function MSUF_EM_SetSnapEnabled(_enabled) end
local function MSUF_EM_SetSnapMode(_mode) end

Edit.Util.GetSnapConfig  = MSUF_EM_GetSnapConfig
Edit.Util.SetSnapEnabled = MSUF_EM_SetSnapEnabled
Edit.Util.SetSnapMode    = MSUF_EM_SetSnapMode

local function MSUF_EM_SuppressNextBlizzardExit()

    local st = MSUF_EM_GetState()
    st.suppressNextBlizzardExit = true

    local function Clear()
        local s = MSUF_EM_GetState()
        s.suppressNextBlizzardExit = false
    end

    MSUF_SafeAfter(0.6, "MSUF_EM_ClearSuppressBlizzExit", Clear)
end

Edit.Popups = Edit.Popups or {}

local function _MSUF_Resolve_impl(v, ctx)
    if type(v) == "function" then
        return v(ctx)
    end
    return v
end

if type(_G) == "table" and type(_G._MSUF_Resolve) ~= "function" then
    _G._MSUF_Resolve = _MSUF_Resolve_impl
end

local _MSUF_Resolve = _MSUF_Resolve_impl

do
    local P = Edit.Popups
    P._frames = P._frames or setmetatable({}, { __mode = "k" })

    local function AnyOpen()
        for f in pairs(P._frames) do
            if f and f.IsShown and f:IsShown() then
                return true
            end
        end
        return false
    end
    P.AnyOpen = AnyOpen

    function P.Register(frame)
        if not frame then return end
        P._frames[frame] = true

        if frame.HookScript and not frame.__msufPopupReg then
            frame.__msufPopupReg = true
            frame:HookScript("OnShow", function()
                MSUF_EM_SetPopupOpen(true)
            end)
            frame:HookScript("OnHide", function()
                if not AnyOpen() then
                    MSUF_EM_SetPopupOpen(false)
                end
            end)
        end
    end

    function P.CloseAll()
        for f in pairs(P._frames) do
            if f and f.Hide then
                f:Hide()
            end
        end
        if GameTooltip and GameTooltip.Hide then
            GameTooltip:Hide()
        end
        MSUF_EM_SetPopupOpen(false)
    end
end

Edit.Popups.UI = Edit.Popups.UI or {}
do
    local UI = Edit.Popups.UI

    function UI.SetLabelEnabled(fs, enabled)
        if not fs or not fs.SetTextColor then return end
        if enabled then
            fs:SetTextColor(1, 1, 1, 0.95)
        else
            fs:SetTextColor(0.55, 0.55, 0.55, 0.9)
        end
    end

    function UI.SetControlEnabled(w, enabled)
        if not w then return end

        -- Buttons / CheckButtons
        if w.SetEnabled then
            w:SetEnabled(enabled and true or false)
        elseif enabled and w.Enable then
            w:Enable()
        elseif (not enabled) and w.Disable then
            w:Disable()
        end

        -- EditBoxes
        if w.ClearFocus and (not enabled) then
            w:ClearFocus()
        end
        if w.EnableMouse then
            w:EnableMouse(enabled and true or false)
        end

        -- Visual cue
        if w.SetAlpha then
            w:SetAlpha(enabled and 1 or 0.35)
        end
        if w.SetTextColor then
            if enabled then
                w:SetTextColor(1, 1, 1, 1)
            else
                w:SetTextColor(0.65, 0.65, 0.65, 1)
            end
        end
    end

    function UI.EnableStepper(btnMinus, btnPlus, enabled)
        UI.SetControlEnabled(btnMinus, enabled)
        UI.SetControlEnabled(btnPlus, enabled)
    end

    function UI.SetSizeControlsEnabled(box, minusBtn, plusBtn, enabled)
        UI.SetControlEnabled(box, enabled)
        UI.EnableStepper(minusBtn, plusBtn, enabled)
    end
end

Edit.Popups.Util = Edit.Popups.Util or {}
do
    local U = Edit.Popups.Util

    local function ClampNumber(v, minV, maxV)
        v = tonumber(v)
        if not v then return nil end
        v = math.floor(v + 0.5)
        if minV and v < minV then v = minV end
        if maxV and v > maxV then v = maxV end
        return v
    end

    function U.ReadOverrideChecked(cb, fallback)
        if cb and cb.GetChecked then
            local ok, val = pcall(cb.GetChecked, cb)
            if ok then
                return (val and true or false)
            end
        end
        return (fallback and true or false)
    end

    function U.ApplyOptionalOverrideNumber(conf, fieldKey, box, overrideCB, enableFn, minusBtn, plusBtn, enabledGate, baseValue, minV, maxV)
        if type(conf) ~= "table" then return false end

        local old = conf[fieldKey]
        local want = (old ~= nil)
        want = U.ReadOverrideChecked(overrideCB, want)

        if enableFn then
            enableFn(box, minusBtn, plusBtn, (want and (enabledGate ~= false)))
        end

        if want then
            local raw = (box and box.GetText and box:GetText())
            local v = tonumber(raw or "") or tonumber(old) or tonumber(baseValue)
            v = ClampNumber(v, minV, maxV) or ClampNumber(baseValue, minV, maxV) or old
            conf[fieldKey] = v
        else
            conf[fieldKey] = nil
        end

        local display = want and (conf[fieldKey] or baseValue) or baseValue
        if box and box.SetText and (not box.HasFocus or not box:HasFocus()) then
            box:SetText(tostring(display or ""))
        end

        return (old ~= conf[fieldKey])
    end

    function U.SyncOptionalOverrideNumber(conf, fieldKey, box, overrideCB, enableFn, minusBtn, plusBtn, enabledGate, baseValue)
        if type(conf) ~= "table" then return end

        local want = (conf[fieldKey] ~= nil)

        if overrideCB and overrideCB.SetChecked then
            overrideCB:SetChecked(want and true or false)
        end

        local display = want and (tonumber(conf[fieldKey]) or baseValue) or baseValue
        if box and box.SetText and (not box.HasFocus or not box:HasFocus()) then
            box:SetText(tostring(display or ""))
        end

        if enableFn then
            enableFn(box, minusBtn, plusBtn, (want and (enabledGate ~= false)))
        end
    end
end
local function MSUF_GetFeatureForTag(tag)
    tag = tostring(tag or "")
    -- Arrow-key nudging
    if tag:find("^ArrowKey:") then
        return "arrowKeys"
    end
    -- Boss preview sync/update (non-critical to keep the rest of Edit Mode usable)
    if tag == "Flush:BossCastbarPreview" or tag == "Flush:BossCastbarPopupSync" then
        return "bossPreview"
    end
    -- Popup helper features
    if tag == "Stepper:onStep" then
        return "popupSteppers"
    end
    if tag == "CopyCastbarSize:Apply" then
        return "popupCopyCastbarSize"
    end
    return nil
end

local function MSUF_DisableFeature(feature)
    if not feature or MSUF__SafeFeatureDisabled[feature] then
        return
    end
    MSUF__SafeFeatureDisabled[feature] = true

    if not MSUF__SafeFeatureDisableOnce[feature] then
        MSUF__SafeFeatureDisableOnce[feature] = true
        if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
            _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff4444MSUF EditMode disabled feature due to repeated errors:|r " .. tostring(feature))
        end
    end

    if feature == "arrowKeys" then
        if _G.MSUF_EnableArrowKeyNudge then
            _G.MSUF_EnableArrowKeyNudge(false)
        end
    end
end

MSUF_SafeCall = function(tag, fn, ...)
    if type(fn) ~= "function" then return nil end

    local feature = MSUF_GetFeatureForTag(tag)
    if feature and MSUF__SafeFeatureDisabled[feature] then
        return nil
    end

    local t = tostring(tag or "")
    if MSUF__EditModeFatalDisabled then
        if t == "MSUF_SetMSUFEditModeDirect" or t == "MSUF_SetMSUFEditModeFromBlizzard" or t:find("^Popup:") or t:find("^Hook:") or t:find("^Flush:UnitApply:") or t:find("^Flush:CastbarApply:") or t == "Flush:CastbarVisuals" then
            return nil
        end
    end

    local args = { ... }
    local ok, r1, r2, r3, r4, r5 = xpcall(function()
        return fn(unpack(args))
    end, geterrorhandler())

    if not ok then

        if feature ~= "arrowKeys" then
            if t == "MSUF_SetMSUFEditModeDirect" or t == "MSUF_SetMSUFEditModeFromBlizzard" or t:find("^Popup:") or t:find("^Hook:") or t:find("^Flush:UnitApply:") or t:find("^Flush:CastbarApply:") or t == "Flush:CastbarVisuals" then
                if MSUF_EditMode_FatalDisable then
                    MSUF_EditMode_FatalDisable(t, r1)
                end
            end
        end

        MSUF__SafeCallErrorCountByTag[tag] = (MSUF__SafeCallErrorCountByTag[tag] or 0) + 1

        if feature then
            MSUF__SafeFeatureErrorCount[feature] = (MSUF__SafeFeatureErrorCount[feature] or 0) + 1
            if MSUF__SafeFeatureErrorCount[feature] >= 3 then
                MSUF_DisableFeature(feature)
            end
        end

        if not MSUF__SafeCallErrorOnce[tag] then
            MSUF__SafeCallErrorOnce[tag] = true
            -- Keep it quiet; one-liner so it doesn't spam
            if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
                _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff4444MSUF EditMode error (suppressed):|r " .. tostring(tag))
            end
        end
        return nil
    end

    return r1, r2, r3, r4, r5
end

local function MSUF_EditMode_ShowStepModifierTipOnce(anchorFrame)
    -- Dezent + nur einmal pro Session. Wird nur von Popup +/- aufgerufen.
    if _G.MSUF__PopupStepperTipShown then
        return
    end
    _G.MSUF__PopupStepperTipShown = true

    local f = anchorFrame
    if not f or type(f.CreateFontString) ~= "function" then
        return
    end

    local tip = f.__msufStepperTipText
    if not tip then
        tip = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        tip:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
        tip:SetJustifyH("CENTER")
        tip:SetJustifyV("MIDDLE")
        tip:SetText("")
        tip:SetAlpha(0.75)
        f.__msufStepperTipText = tip
    end

    -- Kurzer, unaufdringlicher Hinweis (wie frher).
    tip:SetText("")
    tip:Show()

    -- Auto-hide
    if C_Timer and C_Timer.After then
        local token = (tip.__msufHideToken or 0) + 1
        tip.__msufHideToken = token
        C_Timer.After(3.0, function()
            if tip and tip.__msufHideToken == token and tip.Hide then
                tip:Hide()
            end
        end)
    end
end

local MSUF__EM_AfterSeq = 0

MSUF_SafeAfter = function(seconds, tag, fn, requireActive)
    if type(fn) ~= "function" then return end
    local mySeq = MSUF__EM_AfterSeq

    local function _shouldRun()
        if mySeq ~= MSUF__EM_AfterSeq then
            return false
        end
        if requireActive then
            local st = Edit and (Edit.State or _G.MSUF_EditState)
            if not (st and st.active) then
                return false
            end
        end
        return true
    end

    if not (C_Timer and C_Timer.After) then
        if not _shouldRun() then return end
        return MSUF_SafeCall("After:" .. tostring(tag), fn)
    end

    C_Timer.After(tonumber(seconds) or 0, function()
        if not _shouldRun() then return end
        MSUF_SafeCall("After:" .. tostring(tag), fn)
    end)
end

local function MSUF_SanitizePopupOffset(v, default)
    default = tonumber(default) or 0
    v = tonumber(v)
    if not v then return default end
    -- NaN / inf guards
    if v ~= v or v == math.huge or v == -math.huge then
        return default
    end
    -- Hard clamp (offsets should never be in the billions)
    if math.abs(v) > 10000 then
        return default
    end
    return math.floor(v + 0.5)
end

local MSUF_EDITMODE_APPLY_DEBOUNCE = 0.03

local MSUF__EditModePendingApplies = {
    unit = {},       -- [unitKey]=true
    castbar = {},    -- [unit]=true
    bossCastbar = false,
}

local MSUF__EditModeFlushSeq = 0

local MSUF__EditModePendingVisibilityDrivers = nil

local MSUF__UnitPopupApplying = false
local MSUF__UnitPopupSyncing = false
local MSUF__CastbarPopupApplying = false
local MSUF__CastbarPopupSyncing = false
local MSUF__EditModeCombatFrame
local MSUF__EditModeCombatNoticeShown = false
local MSUF__EditModeCombatWarnFrame
local MSUF__EditModeCombatWarnShownThisCombat = false

local function MSUF_EditMode_ShowCombatWarning()
    if not MSUF_UnitEditModeActive then return end
    if not (InCombatLockdown and InCombatLockdown()) then return end
    if MSUF__EditModeCombatWarnShownThisCombat then return end
    MSUF__EditModeCombatWarnShownThisCombat = true

    local msg = "|cffffd700MSUF Edit Mode:|r You are in combat - changes/movement will be applied after combat ends."
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    else
        print(msg)
    end
end

local function MSUF_EditMode_StartCombatWarningListener()
    if MSUF__EditModeCombatWarnFrame then return end
    MSUF__EditModeCombatWarnFrame = CreateFrame("Frame")
    MSUF__EditModeCombatWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    MSUF__EditModeCombatWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    MSUF__EditModeCombatWarnFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if MSUF_UnitEditModeActive then
                MSUF_EditMode_ShowCombatWarning()
            end
        else -- PLAYER_REGEN_ENABLED
            MSUF__EditModeCombatWarnShownThisCombat = false
        end
    end)

    -- If we enter Edit Mode while already in combat, warn immediately (Das klappt nicht so richtig)
    if InCombatLockdown and InCombatLockdown() and MSUF_UnitEditModeActive then
        MSUF_EditMode_ShowCombatWarning()
    end
end

local function MSUF_EditMode_StopCombatWarningListener()
    if not MSUF__EditModeCombatWarnFrame then return end
    if MSUF__EditModeCombatWarnFrame.UnregisterAllEvents then
        MSUF__EditModeCombatWarnFrame:UnregisterAllEvents()
    else
        MSUF__EditModeCombatWarnFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        MSUF__EditModeCombatWarnFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    MSUF__EditModeCombatWarnFrame:SetScript("OnEvent", nil)
    MSUF__EditModeCombatWarnFrame:Hide()
    MSUF__EditModeCombatWarnFrame = nil
    MSUF__EditModeCombatWarnShownThisCombat = false
end

local function MSUF_EditMode_HardTeardown()

    MSUF__EditModeFlushSeq = (MSUF__EditModeFlushSeq or 0) + 1

    MSUF__EM_AfterSeq = (MSUF__EM_AfterSeq or 0) + 1

    if MSUF__EditModePendingApplies then
        if MSUF__EditModePendingApplies.unit then
            for k in pairs(MSUF__EditModePendingApplies.unit) do
                MSUF__EditModePendingApplies.unit[k] = nil
            end
        end
        if MSUF__EditModePendingApplies.castbar then
            for u in pairs(MSUF__EditModePendingApplies.castbar) do
                MSUF__EditModePendingApplies.castbar[u] = nil
            end
        end
        MSUF__EditModePendingApplies.bossCastbar = false
    end
    -- Kill combat listener (but KEEP it if we have deferred SecureStateDriver work pending)
    local __keepCombatListener = (MSUF__EditModePendingVisibilityDrivers ~= nil) or ((Edit and Edit.State and Edit.State.pendingSecureCleanup) and true or false)
    if type(MSUF_EM_EnableUpdateSimpleUnitFrameHook) == "function" then
        MSUF_EM_EnableUpdateSimpleUnitFrameHook(false)
    end
    if MSUF__EditModeCombatFrame and not __keepCombatListener then
        if MSUF__EditModeCombatFrame.UnregisterAllEvents then
            MSUF__EditModeCombatFrame:UnregisterAllEvents()
        else
            MSUF__EditModeCombatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        MSUF__EditModeCombatFrame:SetScript("OnEvent", nil)
        MSUF__EditModeCombatFrame:Hide()
        MSUF__EditModeCombatFrame = nil
    end

    -- Kill combat warning listener
    MSUF_EditMode_StopCombatWarningListener()

    local nudge = _G and _G.MSUF_ArrowKeyNudgeFrame
    if nudge then
        -- Mark as hard-killed so any remaining OnUpdate gate never re-enables keyboard.
        nudge.__msufHardKill = true
        if nudge.EnableKeyboard then
            nudge:EnableKeyboard(false)
        end
        nudge.__msufKeyboardOn = false
        if nudge.Hide then
            nudge:Hide()
        end
    end
    -- Allow the combat-queue notice again next time Edit Mode is used
    MSUF__EditModeCombatNoticeShown = false
end

MSUF_EditMode_FatalDisable = function(tag, err)
    if MSUF__EditModeFatalDisabled then return end
    MSUF__EditModeFatalDisabled = true
    MSUF__EditModeFatalTag = tostring(tag or "?")
    MSUF__EditModeFatalReason = tostring(err or "unknown")

    MSUF_FastCall(function()
        MSUF_EM_SetFatalDisabled(MSUF__EditModeFatalTag, MSUF__EditModeFatalReason)
        MSUF_EM_SetActive(false, nil)

    -- Hard guarantee: boss unitframe preview must not persist past Edit Mode.
    MSUF_BossTestMode = false
        MSUF_EditModeSizing = false
    end)

    -- 2) Close popups & disable arrow nudge.
    MSUF_CloseAllPositionPopups()
    if _G and _G.MSUF_EnableArrowKeyNudge then
        _G.MSUF_EnableArrowKeyNudge(false)
    end

    -- 3) Hard-release keyboard catcher immediately (even if other teardown steps fail).
    local nudge = _G and _G.MSUF_ArrowKeyNudgeFrame
    if nudge then
        nudge.__msufHardKill = true
        if nudge.EnableKeyboard then nudge:EnableKeyboard(false) end
        if nudge.SetScript then nudge:SetScript("OnKeyDown", nil) end
        if nudge.Hide then nudge:Hide() end
        nudge.__msufKeyboardOn = false
    end

    -- 4) Hide grid if present.
    if MSUF_GridFrame and MSUF_GridFrame.Hide then
        MSUF_GridFrame:Hide()
    end

    -- 5) Stop timers/listeners/queues.
    MSUF_EditMode_HardTeardown()

    if not MSUF__EditModeFatalPrinted then
        MSUF__EditModeFatalPrinted = true
        local msg = "|cffffd700MSUF:|r Edit Mode disabled due to an error (" .. MSUF__EditModeFatalTag .. "). /reload recommended."
        if _G and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
            _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
        else
            print(msg)
        end
    end
end

local function MSUF_EditMode_EnsureCombatListener()
    if MSUF__EditModeCombatFrame then return end
    MSUF__EditModeCombatFrame = CreateFrame("Frame")
    MSUF__EditModeCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    MSUF__EditModeCombatFrame:SetScript("OnEvent", function()
        -- Unregister immediately; this is a one-shot flush.
        if MSUF__EditModeCombatFrame then
            MSUF__EditModeCombatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
            MSUF__EditModeCombatFrame:SetScript("OnEvent", nil)
            MSUF__EditModeCombatFrame = nil
        end

        -- Flush queued applies first (may teardown if Edit Mode already ended).
        if type(MSUF_EditMode_FlushPendingApplies) == "function" then
            MSUF_SafeCall("CombatFlush:PendingApplies", MSUF_EditMode_FlushPendingApplies)
        end

        -- Then flush any deferred "secure" work (visibility drivers etc.). Must be out of combat.
if Edit and Edit.Secure and Edit.Secure.Flush then
    Edit.Secure.Flush()
end

        if MSUF__EditModePendingBossPreviewResync and type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            MSUF__EditModePendingBossPreviewResync = nil
            MSUF_SafeCall("CombatFlush:BossPreviewResync", _G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
        end

-- Clear any legacy pending visibility driver flag (legacy fallback path).
MSUF__EditModePendingVisibilityDrivers = nil

if not MSUF_UnitEditModeActive then
    MSUF_EditMode_HardTeardown()
end

    end)
end

Edit.Secure = Edit.Secure or {}
do
    local S = Edit.Secure
    S._pending = S._pending or {} -- tag -> closure

    local function InCombat()
        return InCombatLockdown and InCombatLockdown()
    end

local function HasPending()
        for _ in pairs(S._pending) do
            return true
        end
        return false
    end

    function S.RunOrDefer(tag, fn, ...)
        if type(fn) ~= "function" then
            return false
        end
        tag = tostring(tag or "Secure")

        if InCombat() then
            local args = { ... }
            S._pending[tag] = function()
                return fn(unpack(args))
            end

            if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
                MSUF_EM_SetPendingSecureCleanup(true)
            end
            if type(MSUF_EditMode_EnsureCombatListener) == "function" then
                MSUF_EditMode_EnsureCombatListener()
            end
            return false
        end

        -- OOC: run immediately
        MSUF_SafeCall("Secure:" .. tag, fn, ...)
        if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
            MSUF_EM_SetPendingSecureCleanup(HasPending())
        end
        return true
    end

    -- Flush any deferred secure tasks (must be OOC).
    function S.Flush()
        if InCombat() then
            return
        end

        local had = HasPending()
        if not had then
            if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
                MSUF_EM_SetPendingSecureCleanup(false)
            end
            return
        end

        local pending = S._pending
        S._pending = {}

        for tag, thunk in pairs(pending) do
            if type(thunk) == "function" then
                MSUF_SafeCall("SecureFlush:" .. tostring(tag), thunk)
            end
        end

        if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
            MSUF_EM_SetPendingSecureCleanup(false)
        end
    end

    local P = Edit.Popups
    Edit.Popups.Specs = Edit.Popups.Specs or {}
    local function _MSUF_BoxNumber(box)
        if not box or not box.GetText then return nil end
        local t = box:GetText()
        if not t or t == "" then return nil end
        return tonumber(t)
    end

local function _MSUF_SetBoxNumber(box, v)
        if not box or not box.SetText or v == nil then return end
        box:SetText(tostring(v))
    end

    function P.ReadFields(pf, ctx, spec)
        if not pf or not spec or not spec.fields then
            return {}
        end
        ctx = ctx or {}
        local out = {}

        for _, f in ipairs(spec.fields) do
            local box = f.box and pf[f.box]

            local key = f.key
            if type(key) == "function" then
                key = key(ctx)
            end

            local conf = ctx.conf
            local cur = (conf and key) and conf[key]
            local def = _MSUF_Resolve(f.default, ctx)

            local v = _MSUF_BoxNumber(box)
            if v == nil then
                if type(f.fallback) == "function" then
                    v = f.fallback(ctx, cur, def)
                else
                    v = cur
                end
            end
            if v == nil then
                v = def
            end

            if f.sanitize == "offset" then
                v = MSUF_SanitizePopupOffset(v, (def ~= nil) and def or ((cur ~= nil) and cur or 0))
            elseif f.sanitize == "round" then
                v = tonumber(v) or ((def ~= nil) and def or 0)
                if v ~= v or v == math.huge or v == -math.huge then
                    v = (def ~= nil) and def or 0
                end
                v = math.floor(v + 0.5)
            else
                v = tonumber(v) or ((def ~= nil) and def or 0)
                if v ~= v or v == math.huge or v == -math.huge then
                    v = (def ~= nil) and def or 0
                end
            end

            if f.min ~= nil and v < f.min then v = f.min end
            if f.max ~= nil and v > f.max then v = f.max end

            local name = f.name or key or f.box
            if name then
                out[name] = v
            end

            if f.store and conf and key then
                conf[key] = v
            end

            if f.writeback ~= false then
                _MSUF_SetBoxNumber(box, v)
            end
        end

        return out
    end

    Edit.Popups.Specs.UnitFramePosition = Edit.Popups.Specs.UnitFramePosition or {
        fields = {
            { name="xVal", box="xBox", key="offsetX", sanitize="offset", default=0 , store=true},            { name="yVal", box="yBox", key="offsetY", sanitize="offset", default=0 , store=true},            { name="wVal", box="wBox", key="width",  sanitize="round",  default=function(ctx) return ctx.currentW end, min=80, max=600 , store=true},            { name="hVal", box="hBox", key="height", sanitize="round",  default=function(ctx) return ctx.currentH end, min=20, max=600 , store=true},
            { name="nameXVal",  box="nameXBox",  key="nameOffsetX",  sanitize="round", default=4 , store=true},            { name="nameYVal",  box="nameYBox",  key="nameOffsetY",  sanitize="round", default=-4 , store=true},
            { name="hpXVal",    box="hpXBox",    key="hpOffsetX",    sanitize="round", default=-4 , store=true},            { name="hpYVal",    box="hpYBox",    key="hpOffsetY",    sanitize="round", default=-4 , store=true},
            { name="powerXVal", box="powerXBox", key="powerOffsetX", sanitize="round", default=-4 , store=true},            { name="powerYVal", box="powerYBox", key="powerOffsetY", sanitize="round", default=-4 , store=true},        }
    }

    -- Castbar Position Popup (Frame offsets + size)
    Edit.Popups.Specs.CastbarFramePosition = Edit.Popups.Specs.CastbarFramePosition or {
        fields = {
            { name="xVal", box="xBox", key=function(ctx) return (ctx.prefix or "") .. "OffsetX" end, sanitize="offset", default=function(ctx) return ctx.defaultX end, store=true },
            { name="yVal", box="yBox", key=function(ctx) return (ctx.prefix or "") .. "OffsetY" end, sanitize="offset", default=function(ctx) return ctx.defaultY end, store=true },
            { name="wVal", box="wBox", key=function(ctx) return (ctx.prefix or "") .. "BarWidth" end, sanitize="round", default=function(ctx) return ctx.currentW end, min=50, max=600, store=true },
            { name="hVal", box="hBox", key=function(ctx) return (ctx.prefix or "") .. "BarHeight" end, sanitize="round", default=function(ctx) return ctx.currentH end, min=8, max=100, store=true },
        }
    }

    -- Castbar Name Text offsets
    Edit.Popups.Specs.CastbarNameOffsets = Edit.Popups.Specs.CastbarNameOffsets or {
        fields = {
            { box="castNameXBox", key=function(ctx) return (ctx.prefix or "") .. "TextOffsetX" end, sanitize="round", default=0, store=true },
            { box="castNameYBox", key=function(ctx) return (ctx.prefix or "") .. "TextOffsetY" end, sanitize="round", default=0, store=true },
        }
    }

    -- Castbar Time Text offsets
    Edit.Popups.Specs.CastbarTimeOffsets = Edit.Popups.Specs.CastbarTimeOffsets or {
    fields = {
        { box="timeXBox", key=function(ctx) return (ctx.prefix or "") .. "TimeOffsetX" end, sanitize="round",
          default=function(ctx) return ctx.defaultTimeX end, store=true },
        { box="timeYBox", key=function(ctx) return (ctx.prefix or "") .. "TimeOffsetY" end, sanitize="round",
          default=function(ctx) return ctx.defaultTimeY end, store=true },
    }
}
-- Castbar Icon offsets
    Edit.Popups.Specs.CastbarIconOffsets = Edit.Popups.Specs.CastbarIconOffsets or {
        fields = {
            { box="iconXBox", key=function(ctx) return (ctx.prefix or "") .. "IconOffsetX" end, sanitize="round", default=0, store=true },
            { box="iconYBox", key=function(ctx) return (ctx.prefix or "") .. "IconOffsetY" end, sanitize="round", default=0, store=true },
        }
    }

    -- Convenience: visibility driver refresh (calls into SecureStateDriver territory).
    function S.RequestVisibilityDrivers(active)
        local want = active and true or false
        if type(MSUF_RefreshAllUnitVisibilityDrivers) ~= "function" then
            return
        end
        S.RunOrDefer("VisibilityDrivers", MSUF_RefreshAllUnitVisibilityDrivers, want)
    end
end

function Edit.Popups.SyncFields(pf, ctx, spec)
    if not pf or not spec or not spec.fields then
        return
    end
    ctx = ctx or {}
    local conf = ctx.conf

    for _, f in ipairs(spec.fields) do
        local box = f.box and pf[f.box]
        if box and box.SetText then

            local hasFocus = (not (ctx and ctx.force)) and (box.HasFocus and box:HasFocus()) and true or false
            if not hasFocus then
                local key = f.key
                if type(key) == "function" then
                    key = key(ctx)
                end

                local cur = (conf and key) and conf[key]
                local def = _MSUF_Resolve(f.default, ctx)

                local v = cur
                if v == nil and type(f.fallback) == "function" then
                    v = f.fallback(ctx, cur, def)
                end
                if v == nil then
                    v = def
                end

                if f.sanitize == "offset" then
                    v = MSUF_SanitizePopupOffset(v, (def ~= nil) and def or ((cur ~= nil) and cur or 0))
                elseif f.sanitize == "round" then
                    v = tonumber(v) or ((def ~= nil) and def or 0)
                    if v ~= v or v == math.huge or v == -math.huge then
                        v = (def ~= nil) and def or 0
                    end
                    v = math.floor(v + 0.5)
                else
                    v = tonumber(v) or ((def ~= nil) and def or 0)
                    if v ~= v or v == math.huge or v == -math.huge then
                        v = (def ~= nil) and def or 0
                    end
                end

                if f.min ~= nil and v < f.min then v = f.min end
                if f.max ~= nil and v > f.max then v = f.max end

                box:SetText(tostring(v))
            end
        end
    end
end

local function MSUF_EditMode_RequestVisibilityDrivers(active)
    if Edit and Edit.Secure and Edit.Secure.RequestVisibilityDrivers then
        Edit.Secure.RequestVisibilityDrivers(active)
        return
    end

    local want = active and true or false
    if InCombatLockdown and InCombatLockdown() then
        MSUF__EditModePendingVisibilityDrivers = want
        if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
            MSUF_EM_SetPendingSecureCleanup(true)
        end
        if type(MSUF_EditMode_EnsureCombatListener) == "function" then
            MSUF_EditMode_EnsureCombatListener()
        end
        return
    end
    if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
        MSUF_SafeCall("EditMode:VisibilityDrivers", MSUF_RefreshAllUnitVisibilityDrivers, want)
    end
    if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
        MSUF_EM_SetPendingSecureCleanup(false)
    end
end

function MSUF_EditMode_FlushPendingApplies()
    if InCombatLockdown and InCombatLockdown() then
        MSUF_EditMode_EnsureCombatListener()
        return
    end

    -- If Edit Mode is no longer active, ensure nothing lingers.
    if not MSUF_UnitEditModeActive then
        MSUF_EditMode_HardTeardown()
        return
    end

    -- Unitframes
    if MSUF__EditModePendingApplies.unit then
        for key in pairs(MSUF__EditModePendingApplies.unit) do
            MSUF__EditModePendingApplies.unit[key] = nil
            if type(_G.MSUF_ApplyUnitframeKeyAndSync) == "function" then
                MSUF_SafeCall("Flush:UnitApply:" .. tostring(key), _G.MSUF_ApplyUnitframeKeyAndSync, key)
            end
        end
    end

    -- Castbars (player/target/focus)
    if MSUF__EditModePendingApplies.castbar then
        for unit in pairs(MSUF__EditModePendingApplies.castbar) do
            MSUF__EditModePendingApplies.castbar[unit] = nil
            if type(MSUF_ApplyCastbarUnitAndSync) == "function" then
                MSUF_SafeCall("Flush:CastbarApply:" .. tostring(unit), MSUF_ApplyCastbarUnitAndSync, unit)
            elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                MSUF_SafeCall("Flush:CastbarVisuals", _G.MSUF_UpdateCastbarVisuals)
            end
        end
    end

    -- Boss castbar preview/real
    if MSUF__EditModePendingApplies.bossCastbar then
        MSUF__EditModePendingApplies.bossCastbar = false
        if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
            MSUF_SafeCall("Flush:BossCastbarPos", _G.MSUF_ApplyBossCastbarPositionSetting)
        end
        if type(_G.MSUF_ApplyBossCastbarTimeSetting) == "function" then
            MSUF_SafeCall("Flush:BossCastbarTime", _G.MSUF_ApplyBossCastbarTimeSetting)
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            MSUF_SafeCall("Flush:BossCastbarPreview", _G.MSUF_UpdateBossCastbarPreview)
        end
        if type(MSUF_SyncCastbarPositionPopup) == "function" then
            MSUF_SafeCall("Flush:BossCastbarPopupSync", MSUF_SyncCastbarPositionPopup, "boss")
        end
    end
end

local function MSUF_EditMode_RequestFlushDebounced()
    MSUF__EditModeFlushSeq = (MSUF__EditModeFlushSeq or 0) + 1
    local mySeq = MSUF__EditModeFlushSeq

    MSUF_SafeAfter(MSUF_EDITMODE_APPLY_DEBOUNCE, "Debounce:EditModeFlush", function()
        if mySeq ~= MSUF__EditModeFlushSeq then return end
        MSUF_EditMode_FlushPendingApplies()
    end)
end

local function MSUF_EditMode_QueueNoticeOnce()
    if MSUF__EditModeCombatNoticeShown then return end
    MSUF__EditModeCombatNoticeShown = true
    print("|cffffd700MSUF:|r Your in combat changes applied after.")
end

local function MSUF_EM_CombatGuardFlush()
    if InCombatLockdown and InCombatLockdown() then
        MSUF_EditMode_EnsureCombatListener()
        MSUF_EditMode_QueueNoticeOnce()
        return true
    end
    MSUF_EditMode_RequestFlushDebounced()
    return false
end

local function MSUF_EditMode_RequestUnitApply(key)
    if not key then return end
    MSUF__EditModePendingApplies.unit[key] = true
    if MSUF_EM_CombatGuardFlush() then return end
end

local function MSUF_EditMode_RequestCastbarApply(unit)
    if not unit then return end
    MSUF__EditModePendingApplies.castbar[unit] = true
    if MSUF_EM_CombatGuardFlush() then return end
end

local function MSUF_EditMode_RequestBossCastbarApply()
    MSUF__EditModePendingApplies.bossCastbar = true
    if MSUF_EM_CombatGuardFlush() then return end
end

local floor = math.floor
local max = math.max
local min = math.min
local abs = math.abs
local format = string.format
local gsub = string.gsub

-- Shared textures/backdrops (copied from main file scope)
local MSUF_TEX_WHITE8 = "Interface\\BUTTONS\\WHITE8X8"
local MSUF_BORDER_DEFAULT = "Gray"
local MSUF_BORDER_BACKDROPS = {
    ["None"] = { edgeFile = nil, edgeSize = 0, insets = { left = 0, right = 0, top = 0, bottom = 0 } },
    ["Gray"] = { edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } },
    ["Gold"] = { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } },
}

Edit.Popups.Specs = Edit.Popups.Specs or {}

Edit.Popups.Specs.BossCastbarFramePosition = Edit.Popups.Specs.BossCastbarFramePosition or {
    fields = {
        { box="xBox", key="bossCastbarOffsetX", sanitize="offset", default=0, store=true },
        { box="yBox", key="bossCastbarOffsetY", sanitize="offset", default=0, store=true },
        { box="wBox", key="bossCastbarWidth",   sanitize="round",  default=function(ctx) return ctx.currentW end, min=50, max=999, store=true },
        { box="hBox", key="bossCastbarHeight",  sanitize="round",  default=function(ctx) return ctx.currentH end, min=8,  max=999, store=true },
    }
}

Edit.Popups.Specs.BossCastbarNameOffsets = Edit.Popups.Specs.BossCastbarNameOffsets or {
    fields = {
        { box="castNameXBox", key="bossCastTextOffsetX", sanitize="round", default=0, store=true },
        { box="castNameYBox", key="bossCastTextOffsetY", sanitize="round", default=0, store=true },
    }
}

Edit.Popups.Specs.BossCastbarTimeOffsets = Edit.Popups.Specs.BossCastbarTimeOffsets or {
    fields = {
        { box="timeXBox", key="bossCastTimeOffsetX", sanitize="round", default=0, store=true },
        { box="timeYBox", key="bossCastTimeOffsetY", sanitize="round", default=0, store=true },
    }
}

Edit.Popups.Specs.BossCastbarIconOffsets = Edit.Popups.Specs.BossCastbarIconOffsets or {
    fields = {
        { box="iconXBox", key="bossCastIconOffsetX", sanitize="round", default=0, store=true,
          fallback=function(ctx) return (ctx.conf and tonumber(ctx.conf.castbarIconOffsetX)) or 0 end },
        { box="iconYBox", key="bossCastIconOffsetY", sanitize="round", default=0, store=true,
          fallback=function(ctx) return (ctx.conf and tonumber(ctx.conf.castbarIconOffsetY)) or 0 end },
    }
}

-- Used by edit-visual refresh loops
local MSUF_MAX_BOSS_FRAMES = 5

-- Unit frame registry is exported by the main file
local UnitFrames = _G.MSUF_UnitFrames or {}

if not _G.MSUF_GetUnitLabelForKey then
    _G.MSUF_GetUnitLabelForKey = function(key)
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

MSUF_EDITMODE_UNIT_KEYS = { "player", "target", "focus", "targettarget", "pet", "boss" }
MSUF_EDITMODE_UNIT_FIELDS = { "width", "height", "offsetX", "offsetY" }
MSUF_EDITMODE_GENERAL_FIELDS = {
    "castbarPlayerOffsetX", "castbarPlayerOffsetY", "castbarPlayerBarWidth", "castbarPlayerBarHeight",
    "castbarTargetOffsetX", "castbarTargetOffsetY", "castbarTargetBarWidth", "castbarTargetBarHeight",
    "castbarFocusOffsetX",  "castbarFocusOffsetY",  "castbarFocusBarWidth",  "castbarFocusBarHeight",
    "bossCastbarOffsetX",   "bossCastbarOffsetY",   "bossCastbarWidth",      "bossCastbarHeight",
    "editModeGridStep", "editModeBgAlpha",
}

local function MSUF_CaptureEditModeSnapshot()
    MSUF_EM_EnsureDB()
    local snap = {
        general = MSUF_CaptureKeys(MSUF_DB.general or {}, MSUF_EDITMODE_GENERAL_FIELDS),
        units = {},
    }

    for i = 1, #MSUF_EDITMODE_UNIT_KEYS do
        local k = MSUF_EDITMODE_UNIT_KEYS[i]
        snap.units[k] = MSUF_CaptureKeys(MSUF_DB[k] or {}, MSUF_EDITMODE_UNIT_FIELDS)
    end
    return snap
end

local function MSUF_RestoreEditModeSnapshot(snap)
    if type(snap) ~= "table" then
        return
    end
    MSUF_EM_EnsureDB()

    MSUF_DB.general = MSUF_DB.general or {}
    if type(snap.general) == "table" then
        MSUF_RestoreKeys(MSUF_DB.general, snap.general)
    end

    if type(snap.units) == "table" then
        for i = 1, #MSUF_EDITMODE_UNIT_KEYS do
            local k = MSUF_EDITMODE_UNIT_KEYS[i]
            MSUF_DB[k] = MSUF_DB[k] or {}
            local usnap = snap.units[k]
            if type(usnap) == "table" then
                MSUF_RestoreKeys(MSUF_DB[k], usnap)
            end
        end
    end
end

function MSUF_BeginEditModeTransaction()
    if MSUF_HasTransaction and MSUF_HasTransaction("EDITMODE") then
        return
    end
    local snap = MSUF_CaptureEditModeSnapshot()
    MSUF_BeginTransaction("EDITMODE", snap, MSUF_RestoreEditModeSnapshot)
end

ns.MSUF_BeginEditModeTransaction = MSUF_BeginEditModeTransaction
ns.MSUF_CaptureEditModeSnapshot = MSUF_CaptureEditModeSnapshot
ns.MSUF_RestoreEditModeSnapshot = MSUF_RestoreEditModeSnapshot

local function MSUF_GetAnchorFrame()
    MSUF_EM_EnsureDB()
    local g = MSUF_DB.general or {}

    if g.anchorToCooldown then
        local ecv = _G["EssentialCooldownViewer"]
        if ecv then
            return ecv
        end
        return UIParent
    end

    local anchorName = g.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local f = _G[anchorName]
        if f then
            return f
        end
    end

    return UIParent
end

local function MSUF_IsInEditMode()
    -- MSUF-only Edit Mode (Blizzard Edit Mode is intentionally ignored).
    local st = (type(MSUF_EM_GetState) == "function") and MSUF_EM_GetState()
    if type(st) == "table" and st.active == true then
        return true
    end
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
        return true
    end
    return false
end
local function MSUF_MakeBlizzardOptionsMovable()
    -- IMPORTANT:
    -- Do NOT SetScript() on Blizzard-managed UIPanels (SettingsPanel / InterfaceOptionsFrame).
    -- That can taint UIParentPanelManager and cause ADDON_ACTION_BLOCKED during panel show/hide.
    -- Instead, we create a small drag-handle overlay that drives :StartMoving() on the panel.

    if InCombatLockdown and InCombatLockdown() then return end

    local frame = _G.SettingsPanel
    if not frame then
        frame = _G.InterfaceOptionsFrame or _G.VideoOptionsFrame or _G.AudioOptionsFrame
    end
    if not frame then return end

    if frame.MSUF_Movable then
        return
    end
    frame.MSUF_Movable = true

    -- Make the panel movable, but avoid touching its scripts or mouse state.
    if frame.SetMovable then frame:SetMovable(true) end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end

    -- Create a minimal drag overlay in the title/header area.
    -- Keep it narrow enough to not block close buttons/search widgets.
    local dragName = "MSUF_SettingsPanelDragHandle"
    local drag = _G[dragName]
    if not drag and CreateFrame then
        drag = CreateFrame("Frame", dragName, frame)
    end
    if not drag then return end

    drag:ClearAllPoints()
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -4)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -60, -4)
    drag:SetHeight(22)

    if drag.EnableMouse then drag:EnableMouse(true) end
    if drag.SetClampedToScreen then drag:SetClampedToScreen(false) end
    if drag.RegisterForDrag then drag:RegisterForDrag("LeftButton") end

    -- Avoid reattaching scripts if the panel is reloaded/recreated.
    if not drag.__msufDragInit then
        drag.__msufDragInit = true

        drag:SetScript("OnDragStart", function(self)
            if InCombatLockdown and InCombatLockdown() then return end
            local panel = self and self.GetParent and self:GetParent()
            if panel and panel.StartMoving then
                panel:StartMoving()
            end
        end)

        drag:SetScript("OnDragStop", function(self)
            local panel = self and self.GetParent and self:GetParent()
            if panel and panel.StopMovingOrSizing then
                panel:StopMovingOrSizing()
            end
        end)
    end
end
local function MSUF_ResetCurrentEditUnit()
    if not MSUF_CurrentEditUnitKey then
        return
    end

    if not EnsureDB or not MSUF_DB then
        return
    end

    MSUF_EM_EnsureDB()

    local key  = MSUF_CurrentEditUnitKey
    local conf = MSUF_DB[key]
    if not conf then
        return
    end

    conf.width   = nil
    conf.height  = nil
    conf.offsetX = nil
    conf.offsetY = nil

    MSUF_EnsureDB_Heavy()

    if ApplySettingsForKey then
        ApplySettingsForKey(key)
    elseif ApplyAllSettings then
        ApplyAllSettings()
        if f._msufUpdateCurrentAnchorDisplay then f._msufUpdateCurrentAnchorDisplay() end
    end

        if changedFonts and _G.MSUF_UpdateAllFonts then
            _G.MSUF_UpdateAllFonts()
        end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
local function MSUF_CreateGridFrame()
    if MSUF_GridFrame then
        return
    end

    local parent = UIParent
    local f = CreateFrame("Frame", "MSUF_EditGrid", parent)
    f:SetAllPoints(parent)
    f:SetFrameStrata("BACKGROUND")
    f:SetFrameLevel(1)
    local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOP", UIParent, "TOP", 0, -40)
    infoText:SetJustifyH("CENTER")
    infoText:SetText("")
    f.infoText = infoText

    local alpha = 0.5
    if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeBgAlpha) == "number" then
        alpha = MSUF_DB.general.editModeBgAlpha
    end

    local step = 20
    if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.editModeGridStep) == "number" then
        step = MSUF_DB.general.editModeGridStep
    end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, alpha)
    f.bg = bg

    local grid = CreateFrame("Frame", nil, f)
    grid:SetAllPoints()
    f.grid = grid
    local centerVert = f:CreateTexture(nil, "ARTWORK")
    centerVert:SetColorTexture(1, 1, 0, 0.6)  -- gelblich, gut sichtbar
    centerVert:SetPoint("TOP", f, "TOP", 0, 0)
    centerVert:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    centerVert:SetWidth(2)
    f.centerVertical = centerVert

    local centerHoriz = f:CreateTexture(nil, "ARTWORK")
    centerHoriz:SetColorTexture(1, 1, 0, 0.6)
    centerHoriz:SetPoint("LEFT", f, "LEFT", 0, 0)
    centerHoriz:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    centerHoriz:SetHeight(2)
    f.centerHorizontal = centerHoriz

    local function RebuildGrid(newStep)
        local s = math.floor(newStep or step or 20)
        if s < 8 then s = 8 end
        if s > 64 then s = 64 end

        step = s
        if MSUF_DB and MSUF_DB.general then
            MSUF_DB.general.editModeGridStep = s
        end

        local w = parent:GetWidth() or 0
        local h = parent:GetHeight() or 0

        f.gridLines = f.gridLines or {}
        local lines = f.gridLines

        for i = 1, #lines do
            lines[i]:Hide()
        end

        local idx = 1

        for x = 0, w, s do
            local tex = lines[idx]
            if not tex then
                tex = grid:CreateTexture(nil, "BACKGROUND")
                lines[idx] = tex
            end
            tex:ClearAllPoints()
            tex:SetColorTexture(1, 1, 1, 0.25)
            tex:SetPoint("TOPLEFT", grid, "TOPLEFT", x, 0)
            tex:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", x, 0)
            tex:SetWidth(1)
            tex:Show()
            idx = idx + 1
        end

        for y = 0, h, s do
            local tex = lines[idx]
            if not tex then
                tex = grid:CreateTexture(nil, "BACKGROUND")
                lines[idx] = tex
            end
            tex:ClearAllPoints()
            tex:SetColorTexture(1, 1, 1, 0.25)
            tex:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
            tex:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -y)
            tex:SetHeight(1)
            tex:Show()
            idx = idx + 1
        end

        for i = idx, #lines do
            lines[i]:Hide()
        end
    end

    RebuildGrid(step)

    local alphaSlider = CreateFrame("Slider", "MSUF_EditModeAlphaSlider", f, "OptionsSliderTemplate")
    alphaSlider:SetOrientation("HORIZONTAL")
    alphaSlider:SetSize(200, 16)
    alphaSlider:SetPoint("TOP", UIParent, "TOP", 0, -80)
    alphaSlider:SetMinMaxValues(0.1, 0.8)
    alphaSlider:SetValueStep(0.05)
    alphaSlider:SetObeyStepOnDrag(true)
    alphaSlider:SetValue(alpha)

    local aName = alphaSlider:GetName()
    _G[aName .. "Low"]:SetText("10%")
    _G[aName .. "High"]:SetText("80%")
    _G[aName .. "Text"]:SetText("Edit Mode Background")

    alphaSlider:SetScript("OnValueChanged", function(self, value)
        if value < 0.1 then
            value = 0.1
        elseif value > 0.8 then
            value = 0.8
        end

        if MSUF_DB and MSUF_DB.general then
            MSUF_DB.general.editModeBgAlpha = value
        end
        if f.bg then
            f.bg:SetColorTexture(0, 0, 0, value)
        end
    end)

    f.alphaSlider = alphaSlider

    local gridSlider = CreateFrame("Slider", "MSUF_EditModeGridSlider", f, "OptionsSliderTemplate")
    gridSlider:SetOrientation("HORIZONTAL")
    gridSlider:SetSize(200, 16)
    gridSlider:SetPoint("TOP", UIParent, "TOP", 0, -110) -- etwas unter dem Alpha-Slider
    gridSlider:SetMinMaxValues(8, 64)
    gridSlider:SetValueStep(2)
    gridSlider:SetObeyStepOnDrag(true)
    gridSlider:SetValue(step)

    local gName = gridSlider:GetName()
    _G[gName .. "Low"]:SetText("8")
    _G[gName .. "High"]:SetText("64")
    _G[gName .. "Text"]:SetText("Grid Size (px)")

    gridSlider:SetScript("OnValueChanged", function(self, value)
        RebuildGrid(value)
    end)

     f.gridSlider = gridSlider

    -- White arrow buttons + MODE toggle removed (clean Edit Mode). Keyboard arrow keys still nudge frames.

    -- Always hide the on-frame white arrow buttons in Edit Mode.

    local anchorCheck = ns.MSUF_EM_UIH.TextCheck(f, "MSUF_EditModeAnchorToCooldownCheck", "TOP", gridSlider, "BOTTOM", 0, -12, "Anchor Cooldownmanager")
    MSUF_EM_EnsureDB()
    anchorCheck:SetChecked(MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown)

    anchorCheck:SetScript("OnClick", function(self)
        MSUF_EM_EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local enabled = self:GetChecked() and true or false
        MSUF_DB.general.anchorToCooldown = enabled

        -- IMPORTANT: This toggle must be *positioning only*.
        -- Do NOT LoadAddOn() or show/hide any cooldown manager/viewer here.
        -- (Avoids side effects like enabling/disabling other modules or taint during /reload in combat.)
        ApplyAllSettings()

        if f._msufUpdateCurrentAnchorDisplay then
            f._msufUpdateCurrentAnchorDisplay()
        end
    end)

    local anchorNameLabel = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    anchorNameLabel:SetPoint("TOP", anchorCheck, "BOTTOM", 0, -6)
    anchorNameLabel:SetText("Custom anchor frame name (/fstack)")

    local anchorNameInput = CreateFrame("EditBox", "MSUF_EditModeAnchorNameInput", f, "InputBoxTemplate")
    anchorNameInput:SetSize(210, 20)
    anchorNameInput:SetPoint("TOP", anchorNameLabel, "BOTTOM", 0, -4)
    anchorNameInput:SetAutoFocus(false)
    anchorNameInput:SetMaxLetters(64)

    MSUF_EM_EnsureDB()
    local initialAnchorName = MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorName or ""
    if initialAnchorName == nil then
        initialAnchorName = ""
    end
    anchorNameInput:SetText(initialAnchorName)

    -- Read-only helper: show which anchor is currently active (Cooldown / Custom / UIParent)
    local currentAnchorFS = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    currentAnchorFS:SetPoint("TOP", anchorNameInput, "BOTTOM", 0, -6)
    currentAnchorFS:SetJustifyH("CENTER")
    currentAnchorFS:SetText("")
    f._msufCurrentAnchorFS = currentAnchorFS

    local function UpdateCurrentAnchorDisplay()
        MSUF_EM_EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local v = "UIParent"
        if g.anchorToCooldown then
            v = "Cooldown Manager"
        end
        local an = g.anchorName
        if type(an) == "string" and an ~= "" then
            v = an
        end
        currentAnchorFS:SetText("Current: " .. tostring(v))
    end

    f._msufUpdateCurrentAnchorDisplay = UpdateCurrentAnchorDisplay
    UpdateCurrentAnchorDisplay()

    local function MSUF_ApplyCustomAnchorNameFromEditBox()
        MSUF_EM_EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local txt = anchorNameInput:GetText() or ""
        txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
        if txt == "" then
            MSUF_DB.general.anchorName = nil
        else
            MSUF_DB.general.anchorName = txt
            MSUF_DB.general.anchorToCooldown = false
            if anchorCheck and anchorCheck.SetChecked then
                anchorCheck:SetChecked(false)
            end
        end
        ApplyAllSettings()
        if f._msufUpdateCurrentAnchorDisplay then f._msufUpdateCurrentAnchorDisplay() end
    end

    anchorNameInput:SetScript("OnEnterPressed", function(self)
        MSUF_ApplyCustomAnchorNameFromEditBox()
        self:ClearFocus()
    end)

    anchorNameInput:SetScript("OnEditFocusLost", function(self)
        MSUF_ApplyCustomAnchorNameFromEditBox()
    end)

    anchorNameInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        MSUF_EM_EnsureDB()
        local current = MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorName or ""
        if current == nil then
            current = ""
        end
        anchorNameInput:SetText(current)
    end)

    local bossPreviewCheck = ns.MSUF_EM_UIH.TextCheck(f, "MSUF_EditModeBossPreviewCheck", "TOP", currentAnchorFS, "BOTTOM", 0, -12, "Preview boss frames")
    bossPreviewCheck:SetChecked(MSUF_BossTestMode and true or false)

    bossPreviewCheck:SetScript("OnClick", function(self)
        MSUF_BossTestMode = self:GetChecked() and true or false

        MSUF_EditMode_RequestVisibilityDrivers(MSUF_UnitEditModeActive and true or false)
        for i = 1, MSUF_MAX_BOSS_FRAMES do
            local f = _G["MSUF_boss" .. i]
            if f then
                if MSUF_BossTestMode and not InCombatLockdown() then
                    f:Show()
                    f:SetAlpha(1)
                end
                MSUF_UFDirty(f, "EDITMODE", true)
            end
        end
    end)

    -- Aura preview toggle (Auras 2.0)
    -- Mirrors the Auras menu setting: MSUF_DB.auras2.shared.showInEditMode
    local auraPreviewCheck = ns.MSUF_EM_UIH.TextCheck(f, "MSUF_EditModeAuraPreviewCheck", "BOTTOMLEFT", bossPreviewCheck, "TOPLEFT", 0, 2, "Preview aura frames")
    local function MSUF_EM_GetAuraPreviewEnabled()
        MSUF_EM_EnsureDB()
        local s = MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.shared
        if s and s.showInEditMode == false then
            return false
        end
        return true
    end

    auraPreviewCheck:SetChecked(MSUF_EM_GetAuraPreviewEnabled())

    auraPreviewCheck:SetScript("OnShow", function(self)
        if self and self.SetChecked then
            self:SetChecked(MSUF_EM_GetAuraPreviewEnabled())
        end
    end)

    auraPreviewCheck:SetScript("OnClick", function(self)
        MSUF_EM_EnsureDB()
        if not MSUF_DB then return end
        MSUF_DB.auras2 = (type(MSUF_DB.auras2) == "table") and MSUF_DB.auras2 or {}
        MSUF_DB.auras2.shared = (type(MSUF_DB.auras2.shared) == "table") and MSUF_DB.auras2.shared or {}
        MSUF_DB.auras2.shared.showInEditMode = (self:GetChecked() and true) or false

        if type(_G.MSUF_Auras2_UpdateEditModePoll) == "function" then
            _G.MSUF_Auras2_UpdateEditModePoll()
        end

        -- Notify Auras 2.0 about the effective edit-mode state so previews/movers update immediately.
        local isActive = false
        if type(_G.IsEditModeActive) == "function" then
            local ok, v = pcall(_G.IsEditModeActive)
            isActive = ok and (v and true or false) or false
        else
            isActive = (MSUF_UnitEditModeActive and true) or false
        end

        if type(_G.MSUF_Auras2_OnAnyEditModeChanged) == "function" then
            _G.MSUF_Auras2_OnAnyEditModeChanged(isActive)
        end

        if type(_G.MSUF_Auras2_RefreshAll) == "function" then
            _G.MSUF_Auras2_RefreshAll()
        end
    end)

-- Edit Mode: unit selector row (Prev/Next + ON/OFF toggle)
-- Replaces the old per-unit ON/OFF button strip (cleaner + no clutter)
if not f._msufEditUnitSelectorBuilt then
    f._msufEditUnitSelectorBuilt = true

    local units = {
        { key="player",       label="Player" },
        { key="target",       label="Target" },
        { key="targettarget", label="ToT" },
        { key="focus",        label="Focus" },
        { key="pet",          label="Pet" },
        { key="boss",         label="Boss" },
    }

    local function GetUnitIndex(unitKey)
        for i, u in ipairs(units) do
            if u.key == unitKey then
                return i
            end
        end
        return 1
    end

local function GetUnitKeyAt(i)
        local u = units[i]
        return (u and u.key) or "player"
    end

local function GetUnitLabel(unitKey)
        for _, u in ipairs(units) do
            if u.key == unitKey then
                return u.label
            end
        end
        return tostring(unitKey or "Player")
    end

local function IsEnabled(unitKey)
        MSUF_EM_EnsureDB()
        if type(MSUF_DB) ~= "table" then return true end
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        local v = MSUF_DB[unitKey].enabled
        if v == nil then return true end
        return v and true or false
    end

local function ApplyEnabled(unitKey, enabled)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        MSUF_EM_EnsureDB()
        if type(MSUF_DB) ~= "table" then return end
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        MSUF_DB[unitKey].enabled = enabled and true or false

        if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
            MSUF_EditMode_RequestVisibilityDrivers(MSUF_UnitEditModeActive and true or false)
        end

        -- Live refresh (keep known-good Player restore pipeline)
        if unitKey == "boss" then
            for i = 1, MSUF_MAX_BOSS_FRAMES do
                local bf = _G["MSUF_boss" .. i]
                if bf then
                    MSUF_UFDirty(bf, "EDITMODE", true)
                end
            end
            if type(MSUF_UpdateBossCastbarPreview) == "function" then
                MSUF_UpdateBossCastbarPreview()
            end
        else
            if unitKey == "player" and type(_G.MSUF_ApplyUnitframeKeyAndSync) == "function" then
                _G.MSUF_ApplyUnitframeKeyAndSync(unitKey, false)
            else
                local uf = _G["MSUF_" .. unitKey]
                if uf then
                    MSUF_UFDirty(uf, "EDITMODE", true)
                end
            end
        end
    end

    local row = CreateFrame("Frame", nil, f)
    f._msufFrameEnableBtnRow = row

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", row, "LEFT", 0, 1)
    label:SetText("Edit Unit:")
    f._msufEditUnitLabel = label

    local prevBtn = ns.MSUF_EM_UIH.Button(row, nil, 24, 22, "<", "UIPanelButtonTemplate")
    if prevBtn.GetFontString and prevBtn:GetFontString() then
        prevBtn:GetFontString():SetFontObject("GameFontNormalLarge")
    end
    MSUF_EM_ForceWhiteButtonText(prevBtn)
    prevBtn:SetPoint("LEFT", label, "RIGHT", 8, -1)
    f._msufEditUnitPrevBtn = prevBtn

    local toggleBtn = ns.MSUF_EM_UIH.ButtonAt(row, nil, 240, 22, "LEFT", prevBtn, "RIGHT", 8, 0, nil, "UIPanelButtonTemplate")
    f._msufEditUnitToggleBtn = toggleBtn

    local nextBtn = ns.MSUF_EM_UIH.Button(row, nil, 24, 22, ">", "UIPanelButtonTemplate")
    if nextBtn.GetFontString and nextBtn:GetFontString() then
        nextBtn:GetFontString():SetFontObject("GameFontNormalLarge")
    end
    MSUF_EM_ForceWhiteButtonText(nextBtn)
    nextBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 8, 0)
    f._msufEditUnitNextBtn = nextBtn

    local function Refresh()
        local unitKey = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        f._msufEditUnitKey = unitKey

        local on = IsEnabled(unitKey)
        toggleBtn:SetText(GetUnitLabel(unitKey) .. ": " .. (on and "ON" or "OFF"))

        local fs = toggleBtn.GetFontString and toggleBtn:GetFontString()
        if fs then
            if on then
                fs:SetTextColor(0.2, 1.0, 0.2)
            else
                fs:SetTextColor(1.0, 0.2, 0.2)
            end
        end
    end

    -- Backwards-compatible name some older code paths may call
    f._msufSyncFrameEnableButtons = Refresh
    f._msufSyncEditUnitSelector = Refresh

    local function SelectUnit(unitKey)
        if not unitKey then return end
        f._msufEditUnitKey = unitKey
        if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(true, unitKey)
        else
            MSUF_CurrentEditUnitKey = unitKey
            if type(MSUF_UpdateEditModeVisuals) == "function" then
                MSUF_UpdateEditModeVisuals()
            end
        end
        Refresh()
    end

    prevBtn:SetScript("OnClick", function()
        local cur = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        local idx = GetUnitIndex(cur) - 1
        if idx < 1 then idx = #units end
        SelectUnit(GetUnitKeyAt(idx))
    end)

    nextBtn:SetScript("OnClick", function()
        local cur = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        local idx = GetUnitIndex(cur) + 1
        if idx > #units then idx = 1 end
        SelectUnit(GetUnitKeyAt(idx))
    end)

    toggleBtn:SetScript("OnClick", function()
        local unitKey = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        ApplyEnabled(unitKey, not IsEnabled(unitKey))
        Refresh()
    end)

    Refresh()
else
    if f._msufSyncEditUnitSelector then
        f._msufSyncEditUnitSelector()
    elseif f._msufSyncFrameEnableButtons then
        f._msufSyncFrameEnableButtons()
    end
end

local exitBtn = ns.MSUF_EM_UIH.Button(f, "MSUF_EditModeExitButton", 180, 24, nil, "UIPanelButtonTemplate")
    local _msufExitAnchor = (f._msufFrameEnableBtnRow or bossPreviewCheck)
    local _msufExitYOffset = (f._msufFrameEnableBtnRow and -18 or -62)
    local _msufActionRowYOffset = _msufExitYOffset
    local _msufActionRowXShift = 0
    exitBtn:ClearAllPoints()
    exitBtn:SetPoint("TOPRIGHT", _msufExitAnchor, "BOTTOMRIGHT", -6 + _msufActionRowXShift, _msufActionRowYOffset)
    exitBtn:SetText("Exit MSUF Edit Mode")

    MSUF_EM_ForceWhiteButtonText(exitBtn)
if not StaticPopupDialogs then StaticPopupDialogs = {} end
if not StaticPopupDialogs["MSUF_CONFIRM_CANCEL_EDITMODE"] then
    StaticPopupDialogs["MSUF_CONFIRM_CANCEL_EDITMODE"] = {
        text = "Cancel all changes made in Edit Mode?\n\nThis will restore the settings from when Edit Mode was entered.",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and type(data.doCancel) == "function" then
                data.doCancel()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local cancelBtn = ns.MSUF_EM_UIH.Button(f, "MSUF_EditModeCancelButton", 140, 22, nil, "UIPanelButtonTemplate")
cancelBtn:ClearAllPoints()
cancelBtn:SetPoint("TOP", _msufExitAnchor, "BOTTOM", 0 + _msufActionRowXShift, _msufActionRowYOffset)
cancelBtn:SetText("Cancel Changes")

MSUF_EM_ForceWhiteButtonText(cancelBtn)
cancelBtn:SetScript("OnClick", function()
    if not MSUF_UnitEditModeActive then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    MSUF_EM_SetPopupOpen(true)

    local function DoCancel()
            if type(MSUF_RollbackTransaction) == "function" and type(MSUF_HasTransaction) == "function" and MSUF_HasTransaction("EDITMODE") then
                MSUF_RollbackTransaction("EDITMODE")
                ApplyAllSettings()

                if type(MSUF_UpdateBossCastbarPreview) == "function" then
                    MSUF_UpdateBossCastbarPreview()
                end
                if type(MSUF_PositionPlayerCastbarPreview) == "function" then
                    MSUF_PositionPlayerCastbarPreview()
                end
                if type(MSUF_PositionTargetCastbarPreview) == "function" then
                    MSUF_PositionTargetCastbarPreview()
                end
                if type(MSUF_PositionFocusCastbarPreview) == "function" then
                    MSUF_PositionFocusCastbarPreview()
                end
                if type(MSUF_SyncCastbarPositionPopup) == "function" then
                    MSUF_SyncCastbarPositionPopup()
                end
                if type(MSUF_SyncUnitPositionPopup) == "function" then
                    MSUF_SyncUnitPositionPopup()
                end

                if type(MSUF_CommitTransaction) == "function" then
                    MSUF_CommitTransaction("EDITMODE")
                end
            end

            MSUF_CurrentEditUnitKey = nil

            if type(MSUF_BeginEditModeTransaction) == "function" then
                MSUF_BeginEditModeTransaction()
            end

            if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
                MSUF_SyncCastbarEditModeWithUnitEdit()
            end
            if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
                MSUF_SyncBossUnitframePreviewWithUnitEdit()
            end
            if type(MSUF_UpdateEditModeVisuals) == "function" then
                MSUF_UpdateEditModeVisuals()
            end

            if type(MSUF_SyncCastbarPositionPopup) == "function" then
                MSUF_SyncCastbarPositionPopup()
            end
            if type(MSUF_SyncUnitPositionPopup) == "function" then
                MSUF_SyncUnitPositionPopup()
            end

            print("|cffffd700MSUF:|r Changes |cff00ff00restored|r to Edit Mode start.")
    end

-- NOTE: StaticPopup is not part of our popup registry, so we must not leave popupOpen stuck TRUE.
    -- We attach a one-time OnHide hook to the shown dialog frame to reliably clear the "popupOpen" latch.
    local dlg
    if type(StaticPopup_Show) == "function" then
        dlg = StaticPopup_Show("MSUF_CONFIRM_CANCEL_EDITMODE", nil, nil, { doCancel = DoCancel })
        if dlg and dlg.HookScript and not dlg.__msufPopupOpenHooks then
            dlg.__msufPopupOpenHooks = true
            dlg:HookScript("OnShow", function() MSUF_EM_SetPopupOpen(true) end)
            dlg:HookScript("OnHide", function() MSUF_EM_SetPopupOpen(false) end)
        end
        -- If StaticPopup_Show fails for any reason, fail-open: do not block dragging.
        if not dlg then
            MSUF_EM_SetPopupOpen(false)
        end
    else
        DoCancel()
        MSUF_EM_SetPopupOpen(false)
    end
end)
exitBtn:SetScript("OnClick", function()
        if not MSUF_UnitEditModeActive then
            return
        end

        -- Always go through the deterministic Flow exit so popups/bindings/previews/secure drivers are cleaned up
        -- even when MSUF Edit Mode is running unlinked from Blizzard Edit Mode.
        if Edit and Edit.Flow and type(Edit.Flow.Exit) == "function" then
            Edit.Flow.Exit("button", { flushPending = true })
        else
            if type(MSUF_EditMode_ExitDeterministic) == "function" then
                MSUF_SafeCall("Exit:ButtonFallback", MSUF_EditMode_ExitDeterministic, "button", { flushPending = true })
            else
                MSUF_CloseAllPositionPopups()
                MSUF_EM_SetActive(false, nil)
                if _G and _G.MSUF_EnableArrowKeyNudge then
                    _G.MSUF_EnableArrowKeyNudge(false)
                end
                MSUF_EditMode_HardTeardown()
            end
        end

        print("|cffffd700MSUF:|r Edit Mode |cffff0000OFF|r.")
    end)

local resetBtn = ns.MSUF_EM_UIH.Button(f, "MSUF_EditModeResetButton", 140, 22, nil, "UIPanelButtonTemplate")
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPRIGHT", _msufExitAnchor, "BOTTOMRIGHT", -6 + _msufActionRowXShift, _msufActionRowYOffset)
    resetBtn:SetText("Reset Frame")

    -- Exit goes to the right of Reset (Reset takes the old Exit spot)
    exitBtn:ClearAllPoints()
    exitBtn:SetPoint("TOPLEFT", resetBtn, "TOPRIGHT", 12, 0)

MSUF_EM_ForceWhiteButtonText(resetBtn)

    resetBtn:SetScript("OnClick", function()
        if not MSUF_UnitEditModeActive then
            return
        end

        if not MSUF_CurrentEditUnitKey then
            if MSUF_GridFrame and MSUF_GridFrame.infoText then
                MSUF_GridFrame.infoText:SetText("Reset: Kein Frame ausgewÃ‚Â¤hlt  klicke zuerst ein Frame.")
            end
            return
        end

        if MSUF_ResetCurrentEditUnit then
            MSUF_ResetCurrentEditUnit()
        end
    end)

    f.resetButton = resetBtn

    -- Edit Mode UI layout refresh (visual only)
    -- Goal: clearer sections + boss preview toggle near Boss ON + bottom action bar.
    local function MSUF_EM_ApplyEditModeLayout()
        -- Create headers once
        if not f._msufLayoutHeaders then
            f._msufLayoutHeaders = {}
            local function MakeHeader(txt)
                local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetText(txt)
                fs:SetJustifyH("CENTER")
                return fs
            end
            f._msufLayoutHeaders.positioning = MakeHeader("Positioning")
            f._msufLayoutHeaders.overlay     = MakeHeader("Overlay")
            f._msufLayoutHeaders.frames      = MakeHeader("Frames")
        end

        local posHeader     = f._msufLayoutHeaders.positioning
        local overlayHeader = f._msufLayoutHeaders.overlay
        local framesHeader  = f._msufLayoutHeaders.frames

        local _msufCenterShiftX = 0 -- small visual nudge for symmetry (Frames block)
        -- Action row container (create once)
        if not f._msufActionRow then
            f._msufActionRow = CreateFrame("Frame", nil, f)
        end
        local actionRow = f._msufActionRow

        -- Defensive: some vars are local in this function, but keep a fallback path
        local _info = infoText or (f and f.infoText)
        if not (_info and _info.ClearAllPoints) then
            return
        end

        -- Mode button is the first main control under the header
        if modeBtn then
            modeBtn:ClearAllPoints()
            modeBtn:SetPoint("TOP", _info, "BOTTOM", 0, -14)
        end

        -- Positioning section
        posHeader:ClearAllPoints()
        posHeader:SetPoint("TOP", _info, "BOTTOM", 0, -14)

        -- Custom anchor input first; cooldown anchor toggle sits next to the input
anchorNameLabel:ClearAllPoints()
anchorNameLabel:SetPoint("TOP", posHeader, "BOTTOM", 0, -6)

anchorNameInput:ClearAllPoints()
anchorNameInput:SetPoint("TOP", anchorNameLabel, "BOTTOM", 0, -4)

anchorCheck:ClearAllPoints()
anchorCheck:SetPoint("LEFT", anchorNameInput, "RIGHT", 10, -1)

        if currentAnchorFS then
            currentAnchorFS:ClearAllPoints()
            currentAnchorFS:SetPoint("TOP", anchorNameInput, "BOTTOM", 0, -6)
        end

        -- Overlay section
        overlayHeader:ClearAllPoints()
        overlayHeader:SetPoint("TOP", (currentAnchorFS or anchorNameInput), "BOTTOM", 0, -14)

        alphaSlider:ClearAllPoints()
        alphaSlider:SetPoint("TOP", overlayHeader, "BOTTOM", 0, -26)

        gridSlider:ClearAllPoints()
        gridSlider:SetPoint("TOP", alphaSlider, "BOTTOM", 0, -26)
        if arrowsBtn then
            arrowsBtn:ClearAllPoints()
            arrowsBtn:SetPoint("TOP", gridSlider, "BOTTOM", 0, -10)
        end

        -- Frames section
        framesHeader:ClearAllPoints()
        local _afterOverlay = gridSlider
        framesHeader:SetPoint("TOP", _afterOverlay, "BOTTOM", _msufCenterShiftX, -14)

        local row = f._msufFrameEnableBtnRow
        if row then
            -- IMPORTANT: this row anchors child widgets to row:LEFT.
            -- If the row has no explicit size and is anchored by "TOP",
            -- row:LEFT effectively collapses onto its center, which can push
            -- the entire selector row off-screen depending on resolution/UI scale.
            -- Give it a deterministic size so centering stays stable.
            row:SetSize(420, 24)
            row:ClearAllPoints()
            row:SetPoint("TOP", framesHeader, "BOTTOM", _msufCenterShiftX, -10)
            row:Show()
        end

        -- Boss preview toggle next to the unit toggle button
        bossPreviewCheck:ClearAllPoints()
        bossPreviewCheck:SetScale(0.9)
        if bossPreviewCheck.text and bossPreviewCheck.text.SetText then
            bossPreviewCheck.text:SetText("Boss Preview")
        end

        local unitToggle = f._msufEditUnitToggleBtn
        local nextBtn = f._msufEditUnitNextBtn
        -- Anchor AFTER the right-arrow so the checkbox can never sit behind it.
        if nextBtn then
            bossPreviewCheck:SetPoint("LEFT", nextBtn, "RIGHT", 10, 0)
        elseif unitToggle then
            bossPreviewCheck:SetPoint("LEFT", unitToggle, "RIGHT", 24, 0)
        elseif row then
            bossPreviewCheck:SetPoint("TOP", row, "BOTTOM", 0, -6)
        else
            bossPreviewCheck:SetPoint("TOP", framesHeader, "BOTTOM", 0, -10)
        end
        bossPreviewCheck:Show()

        -- Aura preview toggle above Boss Preview (Auras 2.0)
        if auraPreviewCheck then
            auraPreviewCheck:ClearAllPoints()
            auraPreviewCheck:SetScale(0.9)
            if auraPreviewCheck.text and auraPreviewCheck.text.SetText then
                auraPreviewCheck.text:SetText("Aura Preview")
            end
            auraPreviewCheck:SetPoint("BOTTOMLEFT", bossPreviewCheck, "TOPLEFT", 0, 2)
            auraPreviewCheck:Show()
        end

        -- Actions: Cancel | Reset | Exit as one row
        local gap = 10
        local cW, rW, eW, h = 160, 150, 190, 24

        cancelBtn:SetSize(cW, h)
        resetBtn:SetSize(rW, h)
        exitBtn:SetSize(eW, h)

        actionRow:SetSize(cW + rW + eW + (gap * 2), h)
        actionRow:ClearAllPoints()
        actionRow:SetPoint("TOP", (row or framesHeader), "BOTTOM", _msufCenterShiftX, -18)
        actionRow:Show()

        cancelBtn:ClearAllPoints()
        resetBtn:ClearAllPoints()
        exitBtn:ClearAllPoints()

        cancelBtn:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
        resetBtn:SetPoint("LEFT", cancelBtn, "RIGHT", gap, 0)
        exitBtn:SetPoint("LEFT", resetBtn, "RIGHT", gap, 0)
        cancelBtn:Show(); resetBtn:Show(); exitBtn:Show()
    end

    MSUF_EM_ApplyEditModeLayout()
    f._msufApplyEditModeLayout = MSUF_EM_ApplyEditModeLayout
    f.exitButton = exitBtn

    f:Hide()
    MSUF_GridFrame = f
end
local function MSUF_UpdateEditModeInfo()
    if not MSUF_GridFrame or not MSUF_GridFrame.infoText then
        return
    end

    local textWidget = MSUF_GridFrame.infoText

    if not MSUF_UnitEditModeActive then
        textWidget:SetText("")
        if MSUF_GridFrame.modeHint then
            MSUF_GridFrame.modeHint:Hide()
        end
        return
    end

    -- Keep the top "Edit Unit" selector row (Prev/Next + ON/OFF) in sync with the active edit unit.
    if MSUF_GridFrame._msufSyncEditUnitSelector then
        MSUF_GridFrame._msufSyncEditUnitSelector()
    elseif MSUF_GridFrame._msufSyncFrameEnableButtons then
        MSUF_GridFrame._msufSyncFrameEnableButtons()
    end

    MSUF_EM_EnsureDB()

    local key = MSUF_CurrentEditUnitKey
    if not key or not MSUF_DB or not MSUF_DB[key] then
        textWidget:SetText("MSUF Edit Mode")
    else
        local conf  = MSUF_DB[key]
        local label = MSUF_GetUnitLabelForKey(key)

        local x = MSUF_SanitizePopupOffset(conf.offsetX, 0)
        local y = MSUF_SanitizePopupOffset(conf.offsetY, 0)
        -- Auto-repair corrupted offsets so the UI and DB stay sane.
        if conf.offsetX ~= x then conf.offsetX = x end
        if conf.offsetY ~= y then conf.offsetY = y end

        textWidget:SetText(string.format("Editing: %s (X: %d, Y: %d)", label, x, y))
    end

    if MSUF_GridFrame.modeHint then
        MSUF_GridFrame.modeHint:SetText("|cffffff00Drag or use Arrow keys to move. SHIFT=5 / CTRL=10 / ALT=grid step.|r")
        MSUF_GridFrame.modeHint:Show()
    end
end
local function MSUF_AttachStepperButtons(parent, editBox, onStep)
    if not parent or not editBox then return end

    -- Step logic matches Arrow-Key nudging:
    -- Default: 1px
    -- Shift:   5px
    -- Ctrl:    10px
    -- Alt:     Grid step (editModeGridStep) or 20px fallback
    local function GetStep()
        local step = 1
        if IsAltKeyDown and IsAltKeyDown() then
            if MSUF_GetCurrentGridStep then
                step = MSUF_GetCurrentGridStep()
            else
                step = 20
            end
        elseif IsControlKeyDown and IsControlKeyDown() then
            step = 10
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            step = 5
        end
        step = tonumber(step) or 1
        if step < 1 then step = 1 end
        return step
    end

local function Step(sign)
        -- One-time per session: show step-modifier hint when user first changes a popup value.
        MSUF_EditMode_ShowStepModifierTipOnce(parent)
        local txt = editBox:GetText() or ""
        local val = tonumber(txt) or 0
        local s = GetStep()
        val = val + ((sign or 0) * s)
        editBox:SetText(tostring(val))
        if editBox.SetCursorPosition and editBox.GetNumLetters then
            editBox:SetCursorPosition(editBox:GetNumLetters())
        end

        if type(onStep) == "function" then
            MSUF_SafeCall("Stepper:onStep", onStep)
        end
    end

    local minus = ns.MSUF_EM_UIH.ButtonAt(parent, nil, 16, 16, "LEFT", editBox, "RIGHT", 2, 0, "-", "UIPanelButtonTemplate")
    minus:SetScript("OnClick", function() Step(-1) end)

    local plus = ns.MSUF_EM_UIH.ButtonAt(parent, nil, 16, 16, "LEFT", minus, "RIGHT", 2, 0, "+", "UIPanelButtonTemplate")
    plus:SetScript("OnClick", function() Step(1) end)

    return minus, plus
end

-- Shared popup alignment helpers (Unitframe + Castbar popups)
-- Fixed label column width + input box size for consistent alignment.
local MSUF_POPUP_LABEL_W = 88
local MSUF_POPUP_BOX_W   = 92
local MSUF_POPUP_BOX_H   = 20

-- Returns true only for *complete* numeric strings (prevents live-apply jitter while typing '-' etc.)
local function MSUF_EM_IsCompleteNumberString(s)
    if s == nil then return false end
    s = tostring(s or '')
    -- trim whitespace
    s = s:gsub("%s+", "")
    if s == '' or s == '-' or s == '+' then
        return false
    end
    -- allow integers; allow decimals just in case (even though offsets are effectively ints)
    if s:match('^[-+]?%d+$') then
        return true
    end
    if s:match('^[-+]?%d+%.%d+$') then
        return true
    end
    return false
end

local function MSUF_PopupStyleLabel(fs)
    if not fs then return end
    fs:SetWidth(MSUF_POPUP_LABEL_W)
    fs:SetJustifyH("LEFT")
end
local function MSUF_PopupStyleBox(box)
    if not box then return end
    box:SetSize(MSUF_POPUP_BOX_W, MSUF_POPUP_BOX_H)
end

-- Compact helper: attach standard live-apply OnTextChanged handler (used by multiple popups).
local function MSUF_EM_AttachLiveApply(pf, editBox, applyFn, queueKey, requireCompleteNumber)
    if not pf or not editBox or not applyFn or not editBox.SetScript then return end
    queueKey = queueKey or "MSUF:LiveApply"
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput or not self:HasFocus() then return end
        if requireCompleteNumber then
            local t = self:GetText()
            if not MSUF_EM_IsCompleteNumberString(t) then return end
        end
        if pf._msufLiveApplyQueued then return end
        pf._msufLiveApplyQueued = true
        MSUF_SafeAfter(0, queueKey, function()
            pf._msufLiveApplyQueued = nil
            if pf:IsShown() and self:HasFocus() then
                applyFn()
            end
        end, true)
    end)
end

-- Compact helper: bind Enter/Escape handlers to multiple edit boxes (used by multiple popups).
local function MSUF_EM_BindKeyScripts(onEnter, onEscape, ...)
    for i = 1, select('#', ...) do
        local w = select(i, ...)
        if w and w.SetScript then
            if onEnter then w:SetScript('OnEnterPressed', onEnter) end
            if onEscape then w:SetScript('OnEscapePressed', onEscape) end
        end
    end
end

-- Compact helper: fast-apply wrapper used by multiple popups.
local function MSUF_EM_FastApplyOrPrint(applyFn, label)
    local ok, err = MSUF_FastCall(applyFn)
    if not ok then
    print("|cffffd700MSUF:|r " .. tostring(label or "Popup apply failed") .. ": " .. tostring(err))
    else
        local ok, err = pcall(applyFn)
        if not ok then
            print("|cffffd700MSUF:|r " .. tostring(label or "Popup apply failed") .. ": " .. tostring(err))
        end
    end
end

-- Compact helper: binds OK button + Enter/Escape handlers for a popup.
-- OK applies and closes, Enter applies without closing, Escape clicks cancel.
local function MSUF_EM_BindOkEnterHandlers(popupFrame, okBtn, cancelBtn, applyFn, label)
    if okBtn and okBtn.SetScript then
        okBtn:SetScript("OnClick", function()
            MSUF_EM_FastApplyOrPrint(applyFn, label)
            if popupFrame and popupFrame.Hide then popupFrame:Hide() end
        end)
    end

local function OnEnterPressed(self)
        MSUF_EM_FastApplyOrPrint(applyFn, label)
    end

local function OnEscapePressed(self)
        if cancelBtn and cancelBtn.Click then
            cancelBtn:Click()
        elseif popupFrame and popupFrame.Hide then
            popupFrame:Hide()
        end
    end

    return OnEnterPressed, OnEscapePressed
end

-- Compact helper: restore many fields from a prev snapshot into a config table.
local function MSUF_EM_RestoreFields(dst, src, ...)
    if not dst or not src then return end
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        dst[k] = src[k]
    end
end

local MSUF_EM_CASTBAR_PREFIX_RESTORE_SUFFIXES = {
    "OffsetX", "OffsetY", "BarWidth", "BarHeight",
    "TextOffsetX", "TextOffsetY", "ShowSpellName", "SpellNameFontSize",
    "IconOffsetX", "IconOffsetY", "ShowIcon", "IconSize",
    "TimeOffsetX", "TimeOffsetY", "TimeFontSize",
    "Detached",
}

local MSUF_EM_BOSS_CASTBAR_PREV_KEYS = {
    "bossCastbarOffsetX","bossCastbarOffsetY","bossCastbarWidth","bossCastbarHeight",
    "bossCastTextOffsetX","bossCastTextOffsetY","showBossCastName","bossCastSpellNameFontSize",
    "bossCastIconOffsetX","bossCastIconOffsetY","showBossCastIcon","bossCastIconSize",
    "bossCastTimeOffsetX","bossCastTimeOffsetY","showBossCastTime","bossCastTimeFontSize",
}

local MSUF_EM_UNIT_POPUP_PREV_KEYS = {
    "offsetX","offsetY","width","height",
    "nameOffsetX","nameOffsetY","hpOffsetX","hpOffsetY","powerOffsetX","powerOffsetY",
    "showName","showHP","showPower",
    "nameFontSize","hpFontSize","powerFontSize",
    "hpTextAnchor","powerTextAnchor","nameTextAnchor",
    "powerBarDetached","detachedPowerBarWidth","detachedPowerBarHeight",
    "detachedPowerBarOffsetX","detachedPowerBarOffsetY",
}

local function MSUF_EM_CopyKeys(dst, src, keys)
    if not dst or not src or not keys then return end
    for i = 1, #keys do dst[keys[i]] = src[keys[i]] end
end

local function MSUF_EM_RestorePrefixFields(dst, src, prefix, suffixes)
    if not dst or not src or not prefix or not suffixes then return end
    for i = 1, #suffixes do
        local k = prefix .. suffixes[i]
        dst[k] = src[k]
    end
end

local function MSUF_EM_CreateNumericRow(pf, labelText, boxName, anchorTo, relPoint, x, y, onStep, labelTemplate)
    if not pf then return end
    local label = pf:CreateFontString(nil, 'OVERLAY', labelTemplate or 'GameFontHighlightSmall')
    label:SetText(labelText or '')
    label:SetPoint('TOPLEFT', anchorTo or pf, relPoint or 'TOPLEFT', x or 0, y or 0)
    if MSUF_PopupStyleLabel then MSUF_PopupStyleLabel(label) end
    local box = CreateFrame('EditBox', boxName, pf, 'InputBoxTemplate')
    if MSUF_PopupStyleBox then MSUF_PopupStyleBox(box) end
    box:SetPoint('LEFT', label, 'RIGHT', 8, 0)
    box:SetAutoFocus(false)
    local minus, plus
    if type(MSUF_AttachStepperButtons) == 'function' and type(onStep) == 'function' then
        minus, plus = MSUF_AttachStepperButtons(pf, box, onStep)
    end
    return label, box, minus, plus
end

local function MSUF_EM_CreateNumericRowStored(pf, key, labelText, boxName, anchorTo, relPoint, x, y, onStep, opts)
    local label, box, minus, plus = MSUF_EM_CreateNumericRow(pf, labelText, boxName, anchorTo, relPoint, x, y, onStep, opts and opts.labelTemplate)

    -- Create a lightweight row anchor frame that spans the full row height (label -> stepper).
    -- This prevents overlap/clipping when rows are chained (anchor to row, not to the label line).
    local row
    if pf and label then
        row = CreateFrame("Frame", nil, pf)
        row:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 0)
        local br = plus or box or label
        row:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT", 0, 0)
    end

    if key then
        pf[key .. "Row"] = row
        pf[key .. "Label"], pf[key .. "Box"], pf[key .. "Minus"], pf[key .. "Plus"] = label, box, minus, plus
        if opts and opts.liveApply and type(MSUF_EM_AttachLiveApply) == "function" then
            MSUF_EM_AttachLiveApply(pf, box, onStep, opts.liveTag or "Popup:LiveApply", (opts.requireCompleteNumber ~= false))
        end
    end

    -- Return row first so spec builders can safely chain rows without overlap.
    return row or label, label, box, minus, plus
end

local function MSUF_EM_BuildNumericRows(pf, rows, anchorTo, relPoint, x, onStep, liveTag)
    local prev = anchorTo
    if not (pf and rows and prev) then return prev end
    for i = 1, #rows do
        local r = rows[i]
        if r then
            local opts = (r.live or r.labelTemplate) and { liveApply = r.live, liveTag = liveTag, labelTemplate = r.labelTemplate, requireCompleteNumber = r.requireCompleteNumber }
            prev = (MSUF_EM_CreateNumericRowStored(pf, r.key, r.label, r.box, prev, relPoint, x or 0, r.dy or -8, onStep, opts)) or prev
        end
    end
    return prev
end

-- Popup tooltip helper (anchors outside the popup so it never sits behind it)
local function MSUF_EM_PopupShowTooltip(popupFrame, title, warningLine)
    if not GameTooltip or not popupFrame or not UIParent then return end

    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()

    local uiW = UIParent.GetWidth and UIParent:GetWidth() or 0
    local pr  = popupFrame.GetRight and popupFrame:GetRight()
    local pl  = popupFrame.GetLeft and popupFrame:GetLeft()

    local needLeft = false
    if uiW > 0 and pr then
        needLeft = ((uiW - pr) < 260)
    end

    if needLeft then
        GameTooltip:SetPoint("TOPRIGHT", popupFrame, "TOPLEFT", -10, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", popupFrame, "TOPRIGHT", 10, 0)
    end

    GameTooltip:SetFrameStrata("TOOLTIP")
    if popupFrame.GetFrameLevel and GameTooltip.SetFrameLevel then
        GameTooltip:SetFrameLevel((popupFrame:GetFrameLevel() or 0) + 50)
    end

    GameTooltip:SetText(title or "", 1, 0.82, 0, 1, true)
    if warningLine and warningLine ~= "" then
        GameTooltip:AddLine(warningLine, 1, 0.4, 0.2, true)
    end
    GameTooltip:Show()
end

-- Small helper to attach a checkbox to the right of a numeric row (Show / Override)
local function MSUF_EM_CreateRightCheckbox(pf, name, anchorFrame, textLabel, onClick, opts)
    local cb = CreateFrame("CheckButton", name, pf, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", anchorFrame, "RIGHT", (opts and opts.dx) or 6, (opts and opts.dy) or 0)

    local t = cb.Text or (cb.GetName and _G[cb:GetName() .. "Text"])
    if t and textLabel then t:SetText(textLabel) end

    if opts and (opts.tooltipTitle or opts.tooltipLine) then
        cb:SetScript("OnEnter", function() MSUF_EM_PopupShowTooltip(pf, opts.tooltipTitle, opts.tooltipLine) end)
        cb:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    if onClick then
        cb:SetScript("OnClick", function(self)
            if opts and opts.beforeClick then
                opts.beforeClick(self)
            end
            if opts and opts.deferApply and C_Timer and C_Timer.After then
                MSUF_SafeAfter(0, opts.deferTag or "Popup:DeferredApply", function() onClick(self) end)
            else
                onClick(self)
            end
        end)
    end
    return cb
end

-- Consolidates repeated UI creation across Unit / Castbar / Auras2 popups.

Edit.Popups.UISpec = Edit.Popups.UISpec or {}
do
    local UISpec = Edit.Popups.UISpec

    UISpec.Unit = UISpec.Unit or {
        copyDropdowns = {
            size = { labelField="copySizeLabel", dropField="copySizeDrop", text="Copy size settings to:", point="BOTTOMLEFT", x=15, y=66, width=170 },
            text = { labelField="copyTextLabel", dropField="copyTextDrop", text="Copy text settings to:", point="BOTTOMLEFT", x=15, y=46, width=170 },
        },
        footer = {
            ok     = { field="okBtn",     name="$parentOK",     w=70,  h=22, point="BOTTOMRIGHT", rel="BOTTOMRIGHT", x=-10, y=10, text=OKAY },
            cancel = { field="cancelBtn", name="$parentCancel", w=70,  h=22, point="RIGHT",       relField="okBtn", relPoint="LEFT", x=-6, y=0, text=CANCEL },
            menu   = { field="menuBtn",   name="$parentMenu",   w=86,  h=22, point="BOTTOMLEFT",  rel="BOTTOMLEFT", x=10,  y=10, text="Menu" },
            stepHint = { field="stepHint", point="BOTTOM", x=0, y=40, text="Hold Shift" },
            levelBoost = 20,
            closeBoost = 25,
        },
    }

    UISpec.Castbar = UISpec.Castbar or {
        copyDropdowns = {
            size = { labelField="copySizeLabel", dropField="copySizeDrop", text="Copy size settings to:", point="BOTTOMLEFT", x=15, y=66, width=170 },
            text = { labelField="copyTextLabel", dropField="copyTextDrop", text="Copy text settings to:", point="BOTTOMLEFT", x=15, y=46, width=170 },
        },
        footer = {
            ok     = { field="okBtn",     name="$parentOK",     w=70,  h=22, point="BOTTOMRIGHT", rel="BOTTOMRIGHT", x=-10, y=10, text=OKAY },
            cancel = { field="cancelBtn", name="$parentCancel", w=70,  h=22, point="RIGHT",       relField="okBtn", relPoint="LEFT", x=-6, y=0, text=CANCEL },
            menu   = { field="menuBtn",   name="$parentMenu",   w=86,  h=22, point="BOTTOMLEFT",  rel="BOTTOMLEFT", x=10,  y=10, text="Menu" },
            levelBoost = 20,
            closeBoost = 25,
        },
    }

    UISpec.Auras2 = UISpec.Auras2 or {
        copyDropdowns = {
            aura = { labelField="copyAuraLabel", dropField="copyAuraDrop", text="Copy settings to:", point="BOTTOMLEFT", x=15, y=64, width=170, ensureFrames=true },
        },
        footer = {
            cancel = { field="cancelBtn", name="$parentCancel", w=120, h=22, point="BOTTOMLEFT",  rel="BOTTOMLEFT",  x=16,  y=16, text="Cancel" },
            ok     = { field="okayBtn",   name="$parentOkay",   w=120, h=22, point="BOTTOMRIGHT", rel="BOTTOMRIGHT", x=-16, y=16, text="Okay" },
            levelBoost = 20,
            closeBoost = 25,
        },
    }
end

local function MSUF_EM_ClearFocusOnBoxes(...)
    if not GetCurrentKeyBoardFocus then return end
    local focus = GetCurrentKeyBoardFocus()
    if not focus then return end
    for i = 1, select("#", ...) do
        local box = select(i, ...)
        if box and box == focus and box.ClearFocus then
            box:ClearFocus()
        end
    end
end

local function MSUF_EM_UI_BuildCopyDropdown(pf, spec)
    if not (pf and spec) then return nil, nil end

    if spec.ensureFrames and UIDropDownMenu_CreateFrames then
        pcall(UIDropDownMenu_CreateFrames, 1, 0)
    end

    local label = pf:CreateFontString(nil, "OVERLAY", spec.labelTemplate or "GameFontHighlightSmall")
    label:SetPoint(spec.point or "BOTTOMLEFT", pf, spec.relPoint or (spec.point or "BOTTOMLEFT"), spec.x or 0, spec.y or 0)
    label:SetText(spec.text or "")
    if MSUF_PopupStyleLabel then MSUF_PopupStyleLabel(label) end
    pf[spec.labelField] = label

    local dropName = spec.name or ("$parent" .. (spec.dropField or "Drop"))
    local drop = CreateFrame("Frame", dropName, pf, "UIDropDownMenuTemplate")
    drop:SetPoint("LEFT", label, "RIGHT", -2, -2)
    pf[spec.dropField] = drop

    if spec.width and UIDropDownMenu_SetWidth then
        UIDropDownMenu_SetWidth(drop, spec.width)
    end

    return label, drop
end

local function MSUF_EM_UI_BuildFooterButtons(pf, spec)
    if not (pf and spec) then return end

    local UIH = ns and ns.MSUF_EM_UIH

    local function MakeButton(bspec)
        if not bspec then return nil end

        local name = bspec.name or ("$parent" .. (bspec.field or "Btn"))
        local text = bspec.text
        local w, h = bspec.w or 70, bspec.h or 22
        local point = bspec.point or "BOTTOMRIGHT"

        local relFrame = pf
        local relPoint = bspec.relPoint or point

        if bspec.relField and pf[bspec.relField] then
            relFrame = pf[bspec.relField]
            relPoint = bspec.relPoint or "LEFT"
        elseif bspec.rel == "BOTTOMRIGHT" then
            relFrame = pf
            relPoint = "BOTTOMRIGHT"
        elseif bspec.rel == "BOTTOMLEFT" then
            relFrame = pf
            relPoint = "BOTTOMLEFT"
        end

        local btn
        if UIH and UIH.ButtonAt then
            btn = UIH.ButtonAt(pf, name, w, h, point, relFrame, relPoint, bspec.x or 0, bspec.y or 0, text, "UIPanelButtonTemplate")
        else
            btn = CreateFrame("Button", name, pf, "UIPanelButtonTemplate")
            btn:SetSize(w, h)
            btn:SetPoint(point, relFrame, relPoint, bspec.x or 0, bspec.y or 0)
            btn:SetText(text or "")
        end

        pf[bspec.field] = btn
        return btn
    end

    local okBtn = MakeButton(spec.ok)
    local cancelBtn = MakeButton(spec.cancel)
    local menuBtn = MakeButton(spec.menu)

    local stepHint
    if spec.stepHint then
        stepHint = pf:CreateFontString(nil, "OVERLAY", spec.stepHint.template or "GameFontDisableSmall")
        stepHint:SetPoint(spec.stepHint.point or "BOTTOM", pf, spec.stepHint.relPoint or (spec.stepHint.point or "BOTTOM"), spec.stepHint.x or 0, spec.stepHint.y or 0)
        stepHint:SetText(spec.stepHint.text or "")
        pf[spec.stepHint.field or "stepHint"] = stepHint
    end

    local __baseLevel = (pf.GetFrameLevel and pf:GetFrameLevel()) or 0
    local boost = spec.levelBoost or 20
    if okBtn and okBtn.SetFrameLevel then okBtn:SetFrameLevel(__baseLevel + boost) end
    if cancelBtn and cancelBtn.SetFrameLevel then cancelBtn:SetFrameLevel(__baseLevel + boost) end
    if menuBtn and menuBtn.SetFrameLevel then menuBtn:SetFrameLevel(__baseLevel + boost) end
    local closeBoost = spec.closeBoost or (boost + 5)
    if pf.closeBtn and pf.closeBtn.SetFrameLevel then pf.closeBtn:SetFrameLevel(__baseLevel + closeBoost) end

    return okBtn, cancelBtn, menuBtn, stepHint
end

local function MSUF_EM_UI_BuildTextBlock(pf, spec, anchorFrame, applyFn)
    -- X row
    if spec.x then
        MSUF_EM_BuildNumericRows(pf, {
            { key = spec.x.key, label = spec.x.label, box = spec.x.box, dy = spec.x.dy },
        }, anchorFrame, spec.x.point or "BOTTOMLEFT", spec.x.dx or 0, applyFn)

        if spec.show then
            local xKey = spec.x.key
            local anchor = pf[(xKey .. "Plus")] or pf[(xKey .. "Box")]
            pf[spec.show.field] = MSUF_EM_CreateRightCheckbox(
                pf, spec.show.name, anchor, spec.show.text or "Show", applyFn, spec.show.opts
            )
        end

        if spec.rows and #spec.rows > 0 then
            local xLabel = pf[(spec.x.key .. "Label")]
            local rows = {}
            for i = 1, #spec.rows do
                local r = spec.rows[i]
                rows[i] = { key = r.key, label = r.label, box = r.box, dy = r.dy }
            end
            MSUF_EM_BuildNumericRows(pf, rows, xLabel, "BOTTOMLEFT", 0, applyFn)
        end
    end

    -- Override checkbox (optional)
    if spec.override then
        local o = spec.override
        local anchor = nil
        if o.anchorPlusKey and pf[o.anchorPlusKey] then anchor = pf[o.anchorPlusKey]
        elseif o.anchorBoxKey and pf[o.anchorBoxKey] then anchor = pf[o.anchorBoxKey] end
        if not anchor and o.anchorFallbackKey and pf[o.anchorFallbackKey] then anchor = pf[o.anchorFallbackKey] end

        local onClick = applyFn
        if o.wrapApply then
            onClick = function() applyFn() end
        elseif type(o.onClick) == "function" then
            onClick = o.onClick
        end

        pf[o.field] = MSUF_EM_CreateRightCheckbox(
            pf, o.name, anchor, o.text or "Override", onClick, o.opts
        )
    end
end

-- Unit Popup: Name block (already migrated in Patch 1; kept as a small helper)
local function MSUF_EM_UI_BuildUnitPopup_Text_Name(pf, textHeader, applyFn)
    MSUF_EM_UI_BuildTextBlock(pf, {
        x = { key = "nameX", label = "Name X:", box = "$parentNameXBox", dy = -8 },
        show = { field = "nameShowCB", name = "$parentShowName", text = "Show" },
        rows = {
            { key = "nameY", label = "Name Y:", box = "$parentNameYBox", dy = -8 },
            { key = "nameSize", label = "Name Size:", box = "$parentNameSizeBox", dy = -8 },
        },
    }, textHeader, applyFn)
end

local UNIT_POPUP_TEXT_EXTRA_SPEC = {
    -- Name size override (checkbox only; rows built above)
    {
        override = {
            field = "nameOverrideCB",
            name = "$parentNameOverride",
            anchorPlusKey = "nameSizePlus",
            anchorBoxKey  = "nameSizeBox",
            wrapApply = true,
            opts = {
                tooltipTitle = "Override Name Size",
                tooltipText  = "This will allow changing the font size of Name text on this unitframe only.\n\nWarning: This may look bad with other unitframes.",
            },
        },
    },

    -- HP
    {
        x = { key = "hpX", label = "HP X:", box = "$parentHPXBox", dy = -12 },
        show = { field = "hpShowCB", name = "$parentShowHP", text = "Show" },
        rows = {
            { key = "hpY",    label = "HP Y:",    box = "$parentHPYBox",    dy = -8 },
            { key = "hpSize", label = "HP Size:", box = "$parentHPSizeBox", dy = -8 },
        },
        override = {
            field = "hpOverrideCB",
            name  = "$parentHPOverride",
            anchorPlusKey = "hpSizePlus",
            anchorBoxKey  = "hpSizeBox",
            wrapApply = true,
            opts = {
                tooltipTitle = "Override HP Size",
                tooltipText  = "This will allow changing the font size of HP text on this unitframe only.\n\nWarning: This may look bad with other unitframes.",
            },
        },
    },

    -- Power
    {
        x = { key = "powerX", label = "Power X:", box = "$parentPowerXBox", dy = -12 },
        show = { field = "powerShowCB", name = "$parentShowPower", text = "Show" },
        rows = {
            { key = "powerY",    label = "Power Y:",    box = "$parentPowerYBox",    dy = -8 },
            { key = "powerSize", label = "Power Size:", box = "$parentPowerSizeBox", dy = -8 },
        },
        override = {
            field = "powerOverrideCB",
            name  = "$parentPowerOverride",
            anchorPlusKey = "powerSizePlus",
            anchorBoxKey  = "powerSizeBox",
            wrapApply = true,
            opts = {
                tooltipTitle = "Override Power Size",
                tooltipText  = "This will allow changing the font size of Power text on this unitframe only.\n\nWarning: This may look bad with other unitframes.",
            },
        },
    },
}

local function MSUF_EM_UI_BuildUnitPopup_Text_Extras(pf, applyFn)
    -- Keep exact anchoring order: NameOverride, then HP anchored to NameSizeLabel, then Power anchored to HPSizeLabel.
    -- Name override
    MSUF_EM_UI_BuildTextBlock(pf, UNIT_POPUP_TEXT_EXTRA_SPEC[1], nil, applyFn)

    -- HP
    MSUF_EM_UI_BuildTextBlock(pf, UNIT_POPUP_TEXT_EXTRA_SPEC[2], pf.nameSizeLabel, applyFn)

    -- Power
    MSUF_EM_UI_BuildTextBlock(pf, UNIT_POPUP_TEXT_EXTRA_SPEC[3], pf.hpSizeLabel, applyFn)
end

local CASTBAR_POPUP_TEXT_SPEC = {
    -- CastName
    {
        x = { key = "castNameX", label = "Spell X:", box = "$parentCastNameXBox", dy = -8 },
        show = { field = "castNameShowCB", name = "$parentShowCastName", text = "Show" },
        rows = {
            { key = "castNameY",    label = "Spell Y:",    box = "$parentCastNameYBox",    dy = -8 },
            { key = "castNameSize", label = "Spell Size:", box = "$parentCastNameSizeBox", dy = -8 },
        },
        override = {
            field = "castNameOverrideCB",
            name  = "$parentCastNameOverride",
            anchorPlusKey = "castNameSizePlus",
            anchorBoxKey  = "castNameSizeBox",
            onClick = ApplyCastbarPopupValues, -- keep identical (no wrapper)
            opts = {
                tooltipTitle = "Override Spell Name Size",
                tooltipText  = "This will allow changing the font size of Spell Name text on this castbar only.",
                deferApply   = true,
                beforeClick  = function(cb, checked)
                    local pf2 = cb and cb:GetParent()
                                        if pf2 and pf2.SetCastbarSizeControlsEnabled then
                        pf2.SetCastbarSizeControlsEnabled(
                            pf2.castNameSizeBox,
                            pf2.castNameSizeMinus,
                            pf2.castNameSizePlus,
                            checked and true or false
                        )
                    end
                end,
            },
        },
    },

    -- Icon
    {
        x = { key = "iconX", label = "Icon X:", box = "$parentIconXBox", dy = -12 },
        show = { field = "iconShowCB", name = "$parentShowIcon", text = "Show" },
        rows = {
            { key = "iconY",    label = "Icon Y:",    box = "$parentIconYBox",    dy = -8 },
            { key = "iconSize", label = "Icon Size:", box = "$parentIconSizeBox", dy = -8 },
        },
        override = {
            field = "iconSizeOverrideCB",
            name  = "$parentIconSizeOverride",
            anchorPlusKey = "iconSizePlus",
            anchorBoxKey  = "iconSizeBox",
            onClick = ApplyCastbarPopupValues, -- keep identical
            opts = {
                tooltipTitle = "Override Icon Size",
                tooltipText  = "This will allow changing the icon size on this castbar only.",
                deferApply   = true,
                beforeClick  = function(cb, checked)
                    local pf2 = cb and cb:GetParent()
                                        if pf2 and pf2.SetCastbarSizeControlsEnabled then
                        pf2.SetCastbarSizeControlsEnabled(
                            pf2.iconSizeBox,
                            pf2.iconSizeMinus,
                            pf2.iconSizePlus,
                            checked and true or false
                        )
                    end
                end,
            },
        },
    },

    -- Time
    {
        x = { key = "timeX", label = "Time X:", box = "$parentTimeXBox", dy = -12 },
        show = { field = "timeShowCB", name = "$parentShowTime", text = "Show" },
        rows = {
            { key = "timeY",    label = "Time Y:",    box = "$parentTimeYBox",    dy = -8 },
            { key = "timeSize", label = "Time Size:", box = "$parentTimeSizeBox", dy = -8 },
        },
        override = {
            field = "timeOverrideCB",
            name  = "$parentTimeOverride",
            anchorPlusKey = "timeSizePlus",
            anchorBoxKey  = "timeSizeBox",
            onClick = ApplyCastbarPopupValues, -- keep identical
            opts = {
                tooltipTitle = "Override Time Size",
                tooltipText  = "This will allow changing the font size of Time text on this castbar only.",
            },
        },
    },
}

local function MSUF_EM_UI_BuildCastbarPopup_TextBlocks(pf, textHeader)

        -- Enable/disable castbar popup controls based on Show + Override states (match Unitframe popup UX)
        pf.UpdateEnabledStates = function()
            local pf = MSUF_CastbarPositionPopup or pf
            local UI = Edit and Edit.Popups and Edit.Popups.UI
            if not (pf and UI) then return end

            local showSpell = (pf.castNameShowCB and pf.castNameShowCB.GetChecked and pf.castNameShowCB:GetChecked()) and true or false
            local showIcon  = (pf.iconShowCB and pf.iconShowCB.GetChecked and pf.iconShowCB:GetChecked()) and true or false
            local showTime  = (pf.timeShowCB and pf.timeShowCB.GetChecked and pf.timeShowCB:GetChecked()) and true or false

            -- X/Y rows
            UI.EnableStepper(pf.castNameXBox, pf.castNameXMinus, pf.castNameXPlus, showSpell)
            UI.EnableStepper(pf.castNameYBox, pf.castNameYMinus, pf.castNameYPlus, showSpell)
            UI.EnableStepper(pf.iconXBox,     pf.iconXMinus,     pf.iconXPlus,     showIcon)
            UI.EnableStepper(pf.iconYBox,     pf.iconYMinus,     pf.iconYPlus,     showIcon)
            UI.EnableStepper(pf.timeXBox,     pf.timeXMinus,     pf.timeXPlus,     showTime)
            UI.EnableStepper(pf.timeYBox,     pf.timeYMinus,     pf.timeYPlus,     showTime)

            UI.SetLabelEnabled(pf.castNameXLabel, showSpell)
            UI.SetLabelEnabled(pf.castNameYLabel, showSpell)
            UI.SetLabelEnabled(pf.iconXLabel,     showIcon)
            UI.SetLabelEnabled(pf.iconYLabel,     showIcon)
            UI.SetLabelEnabled(pf.timeXLabel,     showTime)
            UI.SetLabelEnabled(pf.timeYLabel,     showTime)

            -- Checkboxes
            UI.SetControlEnabled(pf.castNameShowCB, true)
            UI.SetControlEnabled(pf.iconShowCB, true)
            UI.SetControlEnabled(pf.timeShowCB, true)

            UI.SetControlEnabled(pf.castNameOverrideCB, showSpell)
            UI.SetControlEnabled(pf.iconSizeOverrideCB, showIcon)
            UI.SetControlEnabled(pf.timeOverrideCB, showTime)

            local spellOverride = (pf.castNameOverrideCB and pf.castNameOverrideCB.GetChecked and pf.castNameOverrideCB:GetChecked()) and true or false
            local iconOverride  = (pf.iconSizeOverrideCB and pf.iconSizeOverrideCB.GetChecked and pf.iconSizeOverrideCB:GetChecked()) and true or false
            local timeOverride  = (pf.timeOverrideCB and pf.timeOverrideCB.GetChecked and pf.timeOverrideCB:GetChecked()) and true or false

            if pf.SetCastbarSizeControlsEnabled then
                pf.SetCastbarSizeControlsEnabled(pf.castNameSizeBox, pf.castNameSizeMinus, pf.castNameSizePlus, showSpell and spellOverride)
                pf.SetCastbarSizeControlsEnabled(pf.iconSizeBox,     pf.iconSizeMinus,     pf.iconSizePlus,     showIcon  and iconOverride)
                pf.SetCastbarSizeControlsEnabled(pf.timeSizeBox,     pf.timeSizeMinus,     pf.timeSizePlus,     showTime  and timeOverride)
            end
        end

    -- Ensure size-control toggler exists before creating override checkboxes (beforeClick uses it).
    pf.SetCastbarSizeControlsEnabled = Edit and Edit.Popups and Edit.Popups.UI and Edit.Popups.UI.SetSizeControlsEnabled

    MSUF_EM_UI_BuildTextBlock(pf, CASTBAR_POPUP_TEXT_SPEC[1], textHeader, ApplyCastbarPopupValues)
    MSUF_EM_UI_BuildTextBlock(pf, CASTBAR_POPUP_TEXT_SPEC[2], pf.castNameSizeLabel, ApplyCastbarPopupValues)
    MSUF_EM_UI_BuildTextBlock(pf, CASTBAR_POPUP_TEXT_SPEC[3], pf.iconSizeLabel, ApplyCastbarPopupValues)
end
local MSUF_POPUP_DEFAULT_BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local MSUF_POPUP_DEFAULT_BACKDROP_COLOR = { 0, 0, 0, 0.9 }

local function MSUF_InitEditPopupFrame(pf, opts)
    if not pf or not opts then return end

    local w = opts.w or 320
    local h = opts.h or 430
    pf:SetSize(w, h)

    pf:SetFrameStrata(opts.strata or "FULLSCREEN_DIALOG")
    pf:SetFrameLevel(opts.level or 500)
    pf:SetClampedToScreen(true)

    pf:SetMovable(true)
    pf:EnableMouse(true)
    pf:RegisterForDrag("LeftButton")

    if opts.smoothDrag then
        pf:SetScript("OnDragStart", function(self)
            if self:IsMovable() then
                self:SetClampedToScreen(false)
                self:StartMoving()
            end
        end)
        pf:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetClampedToScreen(true)
            local ui = UIParent
            if ui and ui.GetWidth and ui.GetHeight and self.GetLeft and self.GetBottom then
                local sw, sh = ui:GetWidth() or 0, ui:GetHeight() or 0
                local pw, ph = self:GetWidth() or 0, self:GetHeight() or 0
                if sw > 0 and sh > 0 and pw > 0 and ph > 0 then
                    local left = math.max(0, math.min(self:GetLeft() or 0, sw - pw))
                    local bottom = math.max(0, math.min(self:GetBottom() or 0, sh - ph))
                    self:ClearAllPoints()
                    self:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", left, bottom)
                end
            end
        end)
    else
        pf:SetScript("OnDragStart", function(self)
            if self:IsMovable() then
                self:StartMoving()
            end
        end)
        pf:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)
    end

    local backdrop = opts.backdrop or (opts.useDefaultBackdrop and MSUF_POPUP_DEFAULT_BACKDROP)
    if backdrop then
        pf:SetBackdrop(backdrop)
    end
    local bc = opts.backdropColor or (opts.useDefaultBackdrop and MSUF_POPUP_DEFAULT_BACKDROP_COLOR)
    if bc then
        pf:SetBackdropColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 1)
    end
end
local function MSUF_PositionPopupSmart(pf, parent, offset)
    if not pf or not parent then return end
    offset = offset or 200

    local ui = UIParent
    if not ui or not ui.GetWidth then return end

    local sw = ui:GetWidth() or 0
    local sh = ui:GetHeight() or 0
    if sw <= 0 or sh <= 0 then return end

    local l = parent:GetLeft()
    local r = parent:GetRight()
    local t = parent:GetTop()
    local b = parent:GetBottom()
    if not (l and r and t and b) then
        return
    end

    local pw = pf:GetWidth() or 260
    local ph = pf:GetHeight() or 190
    if pw <= 1 then pw = 260 end
    if ph <= 1 then ph = 190 end

    local leftSpace   = l
    local rightSpace  = sw - r
    local bottomSpace = b
    local topSpace    = sh - t

    -- Pick the direction with the most room.
    local best = "RIGHT"
    local bestVal = rightSpace

    if leftSpace > bestVal then best, bestVal = "LEFT", leftSpace end
    if topSpace > bestVal then best, bestVal = "TOP", topSpace end
    if bottomSpace > bestVal then best, bestVal = "BOTTOM", bottomSpace end

    local x, y

    if best == "RIGHT" then
        x = r + offset
        y = t - ph
    elseif best == "LEFT" then
        x = l - offset - pw
        y = t - ph
    elseif best == "TOP" then
        x = l
        y = t + offset
    else -- BOTTOM
        x = l
        y = b - offset - ph
    end

    x = MSUF_Clamp(x, 0, math.max(0, sw - pw))
    y = MSUF_Clamp(y, 0, math.max(0, sh - ph))

    pf:ClearAllPoints()
    pf:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", x, y)
    pf:SetClampedToScreen(true)
end

-- One-time cleanup: remove the big background box that can appear behind the "Copy ... settings to..." dropdowns.
-- We keep the dropdowns themselves intact; this only hides a separate container/background frame if present.
local function MSUF_EM_KillCopyDropdownGroupBG(pf, d1, d2)
    if not pf or pf._msufCopyGroupBGKilled then return end
    if not d1 or not d2 then return end
    if not (pf.GetChildren and d1.GetLeft and d2.GetLeft) then return end

    local l1, r1, t1, b1 = d1:GetLeft(), d1:GetRight(), d1:GetTop(), d1:GetBottom()
    local l2, r2, t2, b2 = d2:GetLeft(), d2:GetRight(), d2:GetTop(), d2:GetBottom()
    if not (l1 and r1 and t1 and b1 and l2 and r2 and t2 and b2) then return end

    local L = (l1 < l2) and l1 or l2
    local R = (r1 > r2) and r1 or r2
    local T = (t1 > t2) and t1 or t2
    local B = (b1 < b2) and b1 or b2

    local refLevel = (d1.GetFrameLevel and d1:GetFrameLevel()) or 0

    for _, child in ipairs({ pf:GetChildren() }) do
        if child and child ~= d1 and child ~= d2 and child.IsShown and child.Hide and child.GetLeft then
            local cl, cr, ct, cb = child:GetLeft(), child:GetRight(), child:GetTop(), child:GetBottom()
            if cl and cr and ct and cb then
                local covers = (cl <= (L + 2)) and (cr >= (R - 2)) and (ct >= (T - 2)) and (cb <= (B + 2))
                if covers then
                    local lvl = (child.GetFrameLevel and child:GetFrameLevel()) or 0
                    if lvl < refLevel then
                        child:Hide()
                        if child.EnableMouse then child:EnableMouse(false) end
                    end
                end
            end
        end
    end

    pf._msufCopyGroupBGKilled = true
end

local function MSUF_EM_EnsureCopyDropdownGroupBGKilled(pf, d1, d2)
    if not pf or pf._msufCopyGroupBGHooked then return end
    pf._msufCopyGroupBGHooked = true

    local function run()
        if not pf or (pf.IsShown and not pf:IsShown()) then return end
        MSUF_EM_KillCopyDropdownGroupBG(pf, d1, d2)
    end

    if pf.HookScript then
        pf:HookScript("OnShow", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, run)
            else
                run()
            end
        end)
    end
end

local function MSUF_OpenPositionPopup(unit, parent)
    if not MSUF_UnitEditModeActive then
        return
    end

    if not MSUF_EM_EnsureDB() then
        return
    end

    -- Ensure the header "Edit Unit" selector reflects the unit we are opening a popup for.
    do
        local key = nil
        if type(GetConfigKeyForUnit) == "function" then
            key = GetConfigKeyForUnit(unit)
        end
        if not key and type(unit) == "string" then
            if unit:match("^boss%d+$") then
                key = "boss"
            elseif unit == "targettarget" or unit == "tot" or unit == "targetoftarget" then
                key = "targettarget"
            else
                key = unit
            end
        end
        if key and type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
            _G.MSUF_SetMSUFEditModeDirect(true, key)
        elseif key then
            MSUF_CurrentEditUnitKey = key
            if MSUF_GridFrame and MSUF_GridFrame._msufSyncEditUnitSelector then
                MSUF_GridFrame._msufSyncEditUnitSelector()
            end
        end
    end

local function ApplyUnitPopupValues()
        if MSUF__UnitPopupSyncing or MSUF__UnitPopupApplying then
            return
        end

        MSUF__UnitPopupApplying = true
        local ok, err = MSUF_FastCall(function()
            if InCombatLockdown and InCombatLockdown() then
                print("|cffffd700MSUF:|r Position/GrÃ‚Â¶ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¸e kann im Kampf nicht geÃ‚Â¤ndert werden.")
                return
            end

            MSUF_EM_EnsureDB()
            local pf = MSUF_PositionPopup
            if not pf or not pf.unit or not pf.parent then
                return
            end

            local key = GetConfigKeyForUnit(pf.unit)
            local conf = key and MSUF_DB[key]
            if not conf then
                return
            end

            local currentW = conf.width  or (pf.parent:GetWidth()  or 250)
            local currentH = conf.height or (pf.parent:GetHeight() or 40)

            local vals = Edit.Popups.ReadFields(pf, { conf = conf, currentW = currentW, currentH = currentH }, Edit.Popups.Specs.UnitFramePosition)
            local xVal = vals.xVal
            local yVal = vals.yVal
            local wVal = vals.wVal
            local hVal = vals.hVal
            local nameXVal  = vals.nameXVal
            local nameYVal  = vals.nameYVal
            local hpXVal    = vals.hpXVal
            local hpYVal    = vals.hpYVal
            local powerXVal = vals.powerXVal
            local powerYVal = vals.powerYVal
            local showNameVal = (conf.showName ~= false)
            if pf.nameShowCB and pf.nameShowCB.GetChecked then
                showNameVal = (pf.nameShowCB:GetChecked() and true or false)
            end
            local showHPVal = (conf.showHP ~= false)
            if pf.hpShowCB and pf.hpShowCB.GetChecked then
                showHPVal = (pf.hpShowCB:GetChecked() and true or false)
            end
            local showPowerVal = (conf.showPower ~= false)
            if pf.powerShowCB and pf.powerShowCB.GetChecked then
                showPowerVal = (pf.powerShowCB:GetChecked() and true or false)
            end
            conf.offsetX = xVal
            conf.offsetY = yVal
            conf.width   = wVal
            conf.height  = hVal

            conf.nameOffsetX = nameXVal
            conf.nameOffsetY = nameYVal

            conf.hpOffsetX = hpXVal
            conf.hpOffsetY = hpYVal

            conf.powerOffsetX = powerXVal
            conf.powerOffsetY = powerYVal

            conf.showName = showNameVal
            conf.showHP   = showHPVal
            conf.showPower = showPowerVal

            -- Text anchors (per-unit)
            if pf._msufNameAnchorVal then
                conf.nameTextAnchor = pf._msufNameAnchorVal
            end
            if pf._msufHPAnchorVal then
                conf.hpTextAnchor = pf._msufHPAnchorVal
            end
            if pf._msufPowerAnchorVal then
                conf.powerTextAnchor = pf._msufPowerAnchorVal
            end

            -- Detached power bar (player/target/focus only)
            if pf.detachPowerBarCB and (pf.unit == "player" or pf.unit == "target" or pf.unit == "focus") then
                local wasDetached = (conf.powerBarDetached == true)
                conf.powerBarDetached = (pf.detachPowerBarCB:GetChecked() and true or false)
                if conf.powerBarDetached then
                    local dpbW = pf.dpbWBox and tonumber(pf.dpbWBox:GetText())
                    local dpbH = pf.dpbHBox and tonumber(pf.dpbHBox:GetText())
                    local dpbX = pf.dpbXBox and tonumber(pf.dpbXBox:GetText())
                    local dpbY = pf.dpbYBox and tonumber(pf.dpbYBox:GetText())
                    if dpbW then dpbW = math.floor(dpbW + 0.5); if dpbW < 20 then dpbW = 20 elseif dpbW > 800 then dpbW = 800 end; conf.detachedPowerBarWidth = dpbW end
                    if dpbH then dpbH = math.floor(dpbH + 0.5); if dpbH < 2 then dpbH = 2 elseif dpbH > 80 then dpbH = 80 end; conf.detachedPowerBarHeight = dpbH end
                    if dpbX then dpbX = math.floor(dpbX + 0.5); conf.detachedPowerBarOffsetX = dpbX end
                    if dpbY then dpbY = math.floor(dpbY + 0.5); conf.detachedPowerBarOffsetY = dpbY end
                end
            end

            if pf.UpdateEnabledStates then pf.UpdateEnabledStates() end
            -- Text size overrides (Name / HP / Power)
            local g = (MSUF_DB and MSUF_DB.general) or {}
            local baseSize       = g.fontSize or 14
            local globalNameSize = g.nameFontSize  or baseSize
            local globalHPSize   = g.hpFontSize    or baseSize
            local globalPowSize  = g.powerFontSize or baseSize

            local changedFonts = false
            local U = Edit and Edit.Popups and Edit.Popups.Util
            if U and U.ApplyOptionalOverrideNumber then
                changedFonts = U.ApplyOptionalOverrideNumber(conf, "nameFontSize",  pf.nameSizeBox,  pf.nameOverrideCB,  pf.SetTextSizeControlsEnabled, pf.nameSizeMinus,  pf.nameSizePlus,  showNameVal,  globalNameSize, 6, 48) or changedFonts
                changedFonts = U.ApplyOptionalOverrideNumber(conf, "hpFontSize",    pf.hpSizeBox,    pf.hpOverrideCB,    pf.SetTextSizeControlsEnabled, pf.hpSizeMinus,    pf.hpSizePlus,    showHPVal,    globalHPSize,   6, 48) or changedFonts
                changedFonts = U.ApplyOptionalOverrideNumber(conf, "powerFontSize", pf.powerSizeBox, pf.powerOverrideCB, pf.SetTextSizeControlsEnabled, pf.powerSizeMinus, pf.powerSizePlus, showPowerVal, globalPowSize,  6, 48) or changedFonts
            end

            if changedFonts then
                if _G.MSUF_UpdateAllFonts then
                    _G.MSUF_UpdateAllFonts()
                elseif ns and ns.MSUF_UpdateAllFonts then
                    ns.MSUF_UpdateAllFonts()
                end
            end
            if ApplySettingsForKey then
                ApplySettingsForKey(key)
            elseif ApplyAllSettings then
                ApplyAllSettings()
            end
            -- Force text re-layout when anchors may have changed
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                _G.MSUF_ForceTextLayoutForUnitKey(key)
            end

            -- Re-apply power bar layout (handles detach/embed changes)
            if type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" and pf.parent then
                _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent)
            end
            if pf.UpdateDetachSection then pf.UpdateDetachSection() end

            if MSUF_CurrentOptionsKey == key then
                local xSlider = _G["MSUF_OffsetXSlider"]
                local ySlider = _G["MSUF_OffsetYSlider"]
                local wSlider = _G["MSUF_WidthSlider"]
                local hSlider = _G["MSUF_HeightSlider"]
                local nameXSlider = _G["MSUF_NameOffsetXSlider"]
                local nameYSlider = _G["MSUF_NameOffsetYSlider"]

                if xSlider and xSlider.SetValue then xSlider:SetValue(conf.offsetX or 0) end
                if ySlider and ySlider.SetValue then ySlider:SetValue(conf.offsetY or 0) end
                if wSlider and wSlider.SetValue then wSlider:SetValue(conf.width   or wVal) end
                if hSlider and hSlider.SetValue then hSlider:SetValue(conf.height  or hVal) end
                if nameXSlider and nameXSlider.SetValue then nameXSlider:SetValue(conf.nameOffsetX or nameXVal or 0) end
                if nameYSlider and nameYSlider.SetValue then nameYSlider:SetValue(conf.nameOffsetY or nameYVal or 0) end
                local powerXSlider = _G["MSUF_PowerOffsetXSlider"]
                local powerYSlider = _G["MSUF_PowerOffsetYSlider"]
                local showPowerCB  = _G["MSUF_ShowPowerCheck"]
                if powerXSlider and powerXSlider.SetValue then powerXSlider:SetValue(conf.powerOffsetX or powerXVal or 0) end
                if powerYSlider and powerYSlider.SetValue then powerYSlider:SetValue(conf.powerOffsetY or powerYVal or 0) end
                if showPowerCB and showPowerCB.SetChecked then showPowerCB:SetChecked(conf.showPower ~= false) end
            end

            if MSUF_UpdateEditModeInfo then
                MSUF_UpdateEditModeInfo()
            end
        end)
        MSUF__UnitPopupApplying = false
        if not ok then
            error(err)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Position/GrÃ‚Â¶ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¸e kann im Kampf nicht geÃ‚Â¤ndert werden.")
        return
    end
    if not unit or not parent then
        return
    end

    MSUF_EM_EnsureDB()
    local key = GetConfigKeyForUnit(unit)
    if not key then
        return
    end

    local conf = MSUF_DB[key]
    if not conf then
        return
    end

    MSUF_CurrentEditUnitKey = key
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end

    if not MSUF_PositionPopup then
        local pf = CreateFrame("Frame", "MSUF_EditPositionPopup", UIParent, "BackdropTemplate")
        MSUF_PositionPopup = pf
        if Edit and Edit.Popups and Edit.Popups.Register then Edit.Popups.Register(pf) end

        MSUF_InitEditPopupFrame(pf, {
            w = 360,
            h = 480,
            useDefaultBackdrop = true,
        })
        MSUF_EM_AddPopupTitleAndClose(pf, "MSUF Edit")
        local frameHeader = MSUF_EM_AddSectionHeader(pf, "frameHeader", "Frame", "TOPLEFT", pf, "TOPLEFT", 16, -36)

local frameRows = {
    { key = "x", label = "Offset X:", box = "$parentXBox", dy = -6, live = true },
    { key = "y", label = "Offset Y:", box = "$parentYBox", dy = -8, live = true },
    { key = "w", label = "Width:",    box = "$parentWBox", dy = -12 },
    { key = "h", label = "Height:",   box = "$parentHBox", dy = -8 },
}
MSUF_EM_BuildNumericRows(pf, frameRows, frameHeader, "BOTTOMLEFT", 0, ApplyUnitPopupValues, "UnitPopup:LiveApply")
        local textDivider = MSUF_EM_AddDivider(pf, "textDivider", 330, "TOPLEFT", pf.hLabel, "BOTTOMLEFT", 0, -8)
        local textHeader  = MSUF_EM_AddSectionHeader(pf, "textHeader", "Text", "TOPLEFT", textDivider, "BOTTOMLEFT", 0, -8)

        -- Text offsets + per-unit font overrides (Phase 9 shrink)

        MSUF_EM_UI_BuildUnitPopup_Text_Name(pf, textHeader, ApplyUnitPopupValues)

        pf.SetTextSizeControlsEnabled = Edit.Popups.UI.SetSizeControlsEnabled

        -- Enable/disable controls based on Show + Override states
        pf.UpdateEnabledStates = function()
            local pf = MSUF_PositionPopup
            if not pf then return end

            local showName = (pf.nameShowCB and pf.nameShowCB.GetChecked and pf.nameShowCB:GetChecked()) and true or false
            local showHP   = (pf.hpShowCB   and pf.hpShowCB.GetChecked   and pf.hpShowCB:GetChecked())   and true or false
            local showPow  = (pf.powerShowCB and pf.powerShowCB.GetChecked and pf.powerShowCB:GetChecked()) and true or false

            Edit.Popups.UI.EnableStepper(pf.nameXBox, pf.nameXMinus, pf.nameXPlus, showName)
            Edit.Popups.UI.EnableStepper(pf.nameYBox, pf.nameYMinus, pf.nameYPlus, showName)
            Edit.Popups.UI.EnableStepper(pf.hpXBox, pf.hpXMinus, pf.hpXPlus, showHP)
            Edit.Popups.UI.EnableStepper(pf.hpYBox, pf.hpYMinus, pf.hpYPlus, showHP)
            Edit.Popups.UI.EnableStepper(pf.powerXBox, pf.powerXMinus, pf.powerXPlus, showPow)
            Edit.Popups.UI.EnableStepper(pf.powerYBox, pf.powerYMinus, pf.powerYPlus, showPow)

            Edit.Popups.UI.SetLabelEnabled(pf.nameXLabel, showName)
            Edit.Popups.UI.SetLabelEnabled(pf.nameYLabel, showName)
            Edit.Popups.UI.SetLabelEnabled(pf.hpXLabel, showHP)
            Edit.Popups.UI.SetLabelEnabled(pf.hpYLabel, showHP)
            Edit.Popups.UI.SetLabelEnabled(pf.powerXLabel, showPow)
            Edit.Popups.UI.SetLabelEnabled(pf.powerYLabel, showPow)

            Edit.Popups.UI.SetControlEnabled(pf.nameShowCB, true)
            Edit.Popups.UI.SetControlEnabled(pf.hpShowCB, true)
            Edit.Popups.UI.SetControlEnabled(pf.powerShowCB, true)

            Edit.Popups.UI.SetControlEnabled(pf.nameOverrideCB, showName)
            Edit.Popups.UI.SetControlEnabled(pf.hpOverrideCB, showHP)
            Edit.Popups.UI.SetControlEnabled(pf.powerOverrideCB, showPow)

            local nameOverride = (pf.nameOverrideCB and pf.nameOverrideCB.GetChecked and pf.nameOverrideCB:GetChecked()) and true or false
            local hpOverride   = (pf.hpOverrideCB and pf.hpOverrideCB.GetChecked and pf.hpOverrideCB:GetChecked()) and true or false
            local powOverride  = (pf.powerOverrideCB and pf.powerOverrideCB.GetChecked and pf.powerOverrideCB:GetChecked()) and true or false

            if pf.SetTextSizeControlsEnabled then
                pf.SetTextSizeControlsEnabled(pf.nameSizeBox, pf.nameSizeMinus, pf.nameSizePlus, showName and nameOverride)
                pf.SetTextSizeControlsEnabled(pf.hpSizeBox, pf.hpSizeMinus, pf.hpSizePlus, showHP and hpOverride)
                pf.SetTextSizeControlsEnabled(pf.powerSizeBox, pf.powerSizeMinus, pf.powerSizePlus, showPow and powOverride)
            end
        end

        MSUF_EM_UI_BuildUnitPopup_Text_Extras(pf, ApplyUnitPopupValues)

        -- â”€â”€ Text Anchor dropdowns (Name + HP + Power, per-unit) â”€â”€
        do
            local lastTextRow = pf.powerSizeLabel or pf.powerYLabel or pf.hpSizeLabel
            local anchorLabel = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            anchorLabel:SetPoint("TOPLEFT", lastTextRow, "BOTTOMLEFT", 0, -12)
            anchorLabel:SetText("Text Anchor")
            if MSUF_PopupStyleLabel then MSUF_PopupStyleLabel(anchorLabel) end
            pf.textAnchorLabel = anchorLabel

            local ANCHOR_OPTIONS = {
                { key = "RIGHT",  label = "Right" },
                { key = "LEFT",   label = "Left" },
                { key = "CENTER", label = "Center" },
            }
            local function _AnchorLabel(k)
                for _, o in ipairs(ANCHOR_OPTIONS) do if o.key == k then return o.label end end
                return "Left"
            end
            local function _PrefixedLabel(prefix, k)
                return prefix .. ": " .. _AnchorLabel(k)
            end

            -- Generic dropdown builder (no separate label; prefix baked into dropdown text)
            local function _BuildAnchorDrop(prefix, parentAnchor, parentPoint, relPoint, ox, oy, dropName, pfDropKey, stateKey, defaultVal)
                local drop = CreateFrame("Frame", dropName, pf, "UIDropDownMenuTemplate")
                drop:SetPoint(parentPoint, parentAnchor, relPoint, ox, oy)
                if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(drop, 88) end
                if ns and ns.MSUF_ExpandDropdownClickArea then ns.MSUF_ExpandDropdownClickArea(drop) end
                pf[pfDropKey] = drop

                UIDropDownMenu_Initialize(drop, function(self, level)
                    local info = UIDropDownMenu_CreateInfo()
                    local p = MSUF_PositionPopup or pf
                    local cur = p[stateKey] or defaultVal
                    for _, opt in ipairs(ANCHOR_OPTIONS) do
                        info.text = opt.label
                        info.value = opt.key
                        info.checked = (opt.key == cur)
                        info.func = function(btn)
                            p[stateKey] = btn.value
                            UIDropDownMenu_SetSelectedValue(drop, btn.value)
                            UIDropDownMenu_SetText(drop, _PrefixedLabel(prefix, btn.value))
                            ApplyUnitPopupValues()
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end)
                return drop
            end

            -- Three dropdowns in a row below the header
            local nameAncDrop = _BuildAnchorDrop(
                "Name", anchorLabel, "TOPLEFT", "BOTTOMLEFT", -16, -2,
                "$parentNameAnchorDrop", "nameAnchorDrop",
                "_msufNameAnchorVal", "LEFT")

            local hpAncDrop = _BuildAnchorDrop(
                "HP", nameAncDrop, "LEFT", "RIGHT", -28, 0,
                "$parentHPAnchorDrop", "hpAnchorDrop",
                "_msufHPAnchorVal", "RIGHT")

            local pwrAncDrop = _BuildAnchorDrop(
                "Power", hpAncDrop, "LEFT", "RIGHT", -28, 0,
                "$parentPowerAnchorDrop", "powerAnchorDrop",
                "_msufPowerAnchorVal", "RIGHT")
        end

        -- â”€â”€ Power Bar detach section (player/target/focus only) â”€â”€
        do
            local lastTextRow = pf.textAnchorLabel or pf.powerSizeLabel or pf.powerYLabel or pf.hpSizeLabel
            local pbDivider = MSUF_EM_AddDivider(pf, "pbDivider", 330, "TOPLEFT", lastTextRow, "BOTTOMLEFT", 0, -36)
            local pbHeader = MSUF_EM_AddSectionHeader(pf, "pbHeader", "Power Bar", "TOPLEFT", pbDivider, "BOTTOMLEFT", 0, -6)

            local detachCB = CreateFrame("CheckButton", "$parentDetachPowerBar", pf, "UICheckButtonTemplate")
            detachCB:SetSize(20, 20)
            detachCB:SetPoint("TOPLEFT", pbHeader, "BOTTOMLEFT", 0, -4)
            local detachText = detachCB.Text or (detachCB.GetName and _G[detachCB:GetName() .. "Text"])
            if detachText then detachText:SetText("Detach from frame") end
            pf.detachPowerBarCB = detachCB

            detachCB:SetScript("OnEnter", function()
                MSUF_EM_PopupShowTooltip(pf,
                    "Detach Power Bar",
                    "Separates the power bar from the unit frame so you can position and size it freely.")
            end)
            detachCB:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

            -- Detached power bar numeric rows (W, H, X, Y)
            local detachRows = {
                { key = "dpbW", label = "Width:",    box = "$parentDPBWBox", dy = -6 },
                { key = "dpbH", label = "Height:",   box = "$parentDPBHBox", dy = -8 },
                { key = "dpbX", label = "Offset X:", box = "$parentDPBXBox", dy = -8 },
                { key = "dpbY", label = "Offset Y:", box = "$parentDPBYBox", dy = -8 },
            }
            MSUF_EM_BuildNumericRows(pf, detachRows, detachCB, "BOTTOMLEFT", 0, ApplyUnitPopupValues)

            -- Show/hide + enable detach controls based on unit
            pf.UpdateDetachSection = function()
                local p = MSUF_PositionPopup or pf
                if not p then return end
                local unit = p.unit
                local canDetach = (unit == "player" or unit == "target" or unit == "focus")

                -- Hide entire section for non-detachable units
                local elements = { p.pbDivider, p.pbHeader, p.detachPowerBarCB,
                    p.dpbWLabel, p.dpbWBox, p.dpbWMinus, p.dpbWPlus,
                    p.dpbHLabel, p.dpbHBox, p.dpbHMinus, p.dpbHPlus,
                    p.dpbXLabel, p.dpbXBox, p.dpbXMinus, p.dpbXPlus,
                    p.dpbYLabel, p.dpbYBox, p.dpbYMinus, p.dpbYPlus }
                for _, el in ipairs(elements) do
                    if el and el.SetShown then el:SetShown(canDetach) end
                end

                -- Resize popup
                local h = 520
                if canDetach then
                    local isDetached = (p.detachPowerBarCB and p.detachPowerBarCB:GetChecked()) and true or false

                    -- Show/hide detach rows only when detached
                    local showRows = isDetached
                    local rowEls = {
                        { p.dpbWLabel, p.dpbWBox, p.dpbWMinus, p.dpbWPlus },
                        { p.dpbHLabel, p.dpbHBox, p.dpbHMinus, p.dpbHPlus },
                        { p.dpbXLabel, p.dpbXBox, p.dpbXMinus, p.dpbXPlus },
                        { p.dpbYLabel, p.dpbYBox, p.dpbYMinus, p.dpbYPlus },
                    }
                    for _, row in ipairs(rowEls) do
                        for _, el in ipairs(row) do
                            if el and el.SetShown then el:SetShown(showRows) end
                        end
                    end

                    h = h + 30  -- divider + header + checkbox
                    if showRows then h = h + 110 end  -- W/H/X/Y rows
                end
                if p.SetSize then p:SetSize(360, h) end
            end

            detachCB:SetScript("OnClick", function(self)
                if pf.UpdateDetachSection then pf.UpdateDetachSection() end
                ApplyUnitPopupValues()
            end)
        end

        local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
        local US = UISpec and UISpec.Unit

        if US and US.copyDropdowns then
            MSUF_EM_UI_BuildCopyDropdown(pf, US.copyDropdowns.size)
            MSUF_EM_UI_BuildCopyDropdown(pf, US.copyDropdowns.text)
        end
        pf.RefreshCopySizeDropdown = function()
            local p = MSUF_PositionPopup or pf
            MSUF_EM_RefreshUnitCopyDropdown(p, p.copySizeDrop, p.copySizeLabel, "Copy size settings to...", "size")
        end

        pf.RefreshCopyTextDropdown = function()
            local p = MSUF_PositionPopup or pf
            MSUF_EM_RefreshUnitCopyDropdown(p, p.copyTextDrop, p.copyTextLabel, "Copy text settings to...", "text")
        end

        local okBtn, cancelBtn, menuBtn = MSUF_EM_UI_BuildFooterButtons(pf, (US and US.footer) or nil)

        if menuBtn then
            menuBtn:SetScript("OnClick", function()
                if type(MSUF_EM_SuppressNextBlizzardExit) == "function" then MSUF_EM_SuppressNextBlizzardExit() end
                local p = MSUF_PositionPopup
                local key = p and p.MSUF_prev and p.MSUF_prev.key
                if key and type(_G.MSUF_OpenOptionsToUnitMenu) == "function" then
                    _G.MSUF_OpenOptionsToUnitMenu(key)
                end
                pf:Hide()
            end)
        end

        cancelBtn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                if MSUF_PositionPopup and MSUF_PositionPopup.Hide then MSUF_PositionPopup:Hide() end
                return
            end
            MSUF_EM_EnsureDB()
            local pf = MSUF_PositionPopup
            if pf and pf.MSUF_prev and pf.MSUF_prev.key then
                local key = pf.MSUF_prev.key
                MSUF_DB[key] = MSUF_DB[key] or {}
                local conf = MSUF_DB[key]
                MSUF_EM_CopyKeys(conf, pf.MSUF_prev, MSUF_EM_UNIT_POPUP_PREV_KEYS)
                if ApplySettingsForKey then
                    ApplySettingsForKey(key)
                elseif ApplyAllSettings then
                    ApplyAllSettings()
                end
                if _G.MSUF_UpdateAllFonts then _G.MSUF_UpdateAllFonts() end
                -- Force text layout restore on cancel (anchors may have changed)
                if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
                    _G.MSUF_ForceTextLayoutForUnitKey(key)
                end
                -- Re-apply power bar layout on cancel (restore detach state)
                if type(_G.MSUF_ApplyPowerBarEmbedLayout) == "function" and pf.parent then
                    _G.MSUF_ApplyPowerBarEmbedLayout(pf.parent)
                end
            end
            MSUF_PositionPopup:Hide()
        end)

        local OnEnterPressed, OnEscapePressed = MSUF_EM_BindOkEnterHandlers(pf, okBtn, cancelBtn, ApplyUnitPopupValues, "Popup apply failed")

        MSUF_EM_BindKeyScripts(OnEnterPressed, OnEscapePressed,
            pf.xBox, pf.yBox, pf.wBox, pf.hBox, pf.spacingBox,
            pf.nameXBox, pf.nameYBox, pf.nameSizeBox,
            pf.hpXBox, pf.hpYBox, pf.hpSizeBox,
            pf.powerXBox, pf.powerYBox, pf.powerSizeBox,
            pf.dpbWBox, pf.dpbHBox, pf.dpbXBox, pf.dpbYBox
        )
    end

    -- Dynamic popup height: taller when power bar section is visible
    do
        local pf = MSUF_PositionPopup
        if pf and pf.SetSize then
            local unit = pf.unit
            local canDetach = (unit == "player" or unit == "target" or unit == "focus")
            local isDetached = canDetach and pf.detachPowerBarCB and pf.detachPowerBarCB:GetChecked()
            local h = 520
            if canDetach then h = h + 30 end          -- divider + header + checkbox
            if isDetached then h = h + 110 end         -- W/H/X/Y rows
            pf:SetSize(360, h)
        end
    end

    local pf = MSUF_PositionPopup

    MSUF_EM_EnsureCopyDropdownGroupBGKilled(pf, pf.copySizeDrop, pf.copyTextDrop)
    local wasShown = (pf and pf.IsShown and pf:IsShown()) and true or false
    local oldUnit  = pf and pf.unit
    local oldParent = pf and pf.parent
    local needReposition = (not wasShown) or (oldUnit ~= unit) or (oldParent ~= parent)
    pf.unit   = unit
    pf.parent = parent

    local label = MSUF_GetUnitLabelForKey and MSUF_GetUnitLabelForKey(key) or unit
    pf.title:SetText(string.format("MSUF Edit  %s", label))

    local x = MSUF_SanitizePopupOffset(conf.offsetX, 0)
    local y = MSUF_SanitizePopupOffset(conf.offsetY, 0)
    -- Auto-repair corrupted offsets so the UI and DB stay sane.
    if conf.offsetX ~= x then conf.offsetX = x end
    if conf.offsetY ~= y then conf.offsetY = y end
    local w = conf.width   or (parent and parent:GetWidth()  or 250)
    local h = conf.height  or (parent and parent:GetHeight() or 40)

    pf.xBox:SetText(tostring(x))
    pf.yBox:SetText(tostring(y))
    pf.wBox:SetText(tostring(math.floor(w + 0.5)))
    pf.hBox:SetText(tostring(math.floor(h + 0.5)))
    if pf.nameXBox then pf.nameXBox:SetText(tostring(conf.nameOffsetX or 4)) end
    if pf.nameYBox then pf.nameYBox:SetText(tostring(conf.nameOffsetY or -4)) end
    if pf.nameShowCB and pf.nameShowCB.SetChecked then
        pf.nameShowCB:SetChecked(conf.showName ~= false)
    end

    -- Text size boxes + override toggles (use global sizes when no override is set)
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local baseSize       = g.fontSize or 14
    local globalNameSize = g.nameFontSize  or baseSize
    local globalHPSize   = g.hpFontSize    or baseSize
    local globalPowSize  = g.powerFontSize or baseSize

    local textOverrides = {
        { confKey = "nameFontSize",  global = globalNameSize, showKey = "showName",  box = pf.nameSizeBox,  cb = pf.nameOverrideCB,  minus = pf.nameSizeMinus,  plus = pf.nameSizePlus },
        { confKey = "hpFontSize",    global = globalHPSize,   showKey = "showHP",    box = pf.hpSizeBox,    cb = pf.hpOverrideCB,    minus = pf.hpSizeMinus,    plus = pf.hpSizePlus },
        { confKey = "powerFontSize", global = globalPowSize,  showKey = "showPower", box = pf.powerSizeBox, cb = pf.powerOverrideCB, minus = pf.powerSizeMinus, plus = pf.powerSizePlus },
    }
    for _, o in ipairs(textOverrides) do
        if o.box then o.box:SetText(tostring(conf[o.confKey] or o.global)) end
        if o.cb and o.cb.SetChecked then o.cb:SetChecked(conf[o.confKey] ~= nil) end
        if pf.SetTextSizeControlsEnabled then
            pf.SetTextSizeControlsEnabled(o.box, o.minus, o.plus, (conf[o.confKey] ~= nil) and (conf[o.showKey] ~= false))
        end
    end

    -- Sync text anchor dropdowns
    do
        local nameAnc = conf.nameTextAnchor or "LEFT"
        local hpAnc  = conf.hpTextAnchor or "RIGHT"
        local pwrAnc = conf.powerTextAnchor or "RIGHT"
        pf._msufNameAnchorVal  = nameAnc
        pf._msufHPAnchorVal    = hpAnc
        pf._msufPowerAnchorVal = pwrAnc
        local function _AncLbl(k) return k == "LEFT" and "Left" or k == "CENTER" and "Center" or "Right" end
        if pf.nameAnchorDrop then
            UIDropDownMenu_SetSelectedValue(pf.nameAnchorDrop, nameAnc)
            UIDropDownMenu_SetText(pf.nameAnchorDrop, "Name: " .. _AncLbl(nameAnc))
        end
        if pf.hpAnchorDrop then
            UIDropDownMenu_SetSelectedValue(pf.hpAnchorDrop, hpAnc)
            UIDropDownMenu_SetText(pf.hpAnchorDrop, "HP: " .. _AncLbl(hpAnc))
        end
        if pf.powerAnchorDrop then
            UIDropDownMenu_SetSelectedValue(pf.powerAnchorDrop, pwrAnc)
            UIDropDownMenu_SetText(pf.powerAnchorDrop, "Power: " .. _AncLbl(pwrAnc))
        end
    end

    if pf.RefreshCopyTextDropdown then
        pf.RefreshCopyTextDropdown()
    end
    if pf.RefreshCopySizeDropdown then
        pf.RefreshCopySizeDropdown()
    end

    if pf.hpXBox then pf.hpXBox:SetText(tostring(conf.hpOffsetX or -4)) end
    if pf.hpYBox then pf.hpYBox:SetText(tostring(conf.hpOffsetY or -4)) end
    if pf.hpShowCB and pf.hpShowCB.SetChecked then
        pf.hpShowCB:SetChecked(conf.showHP ~= false)
    end
    if pf.powerXBox then pf.powerXBox:SetText(tostring(conf.powerOffsetX or -4)) end
    if pf.powerYBox then pf.powerYBox:SetText(tostring(conf.powerOffsetY or -4)) end
    if pf.powerShowCB and pf.powerShowCB.SetChecked then
        pf.powerShowCB:SetChecked(conf.showPower ~= false)
    end
    -- Sync detached power bar controls
    if pf.detachPowerBarCB then
        local isDetachable = (unit == "player" or unit == "target" or unit == "focus")
        if isDetachable then
            pf.detachPowerBarCB:SetChecked(conf.powerBarDetached == true)
            local parentW = (parent and parent:GetWidth()) or 250
            if pf.dpbWBox then pf.dpbWBox:SetText(tostring(conf.detachedPowerBarWidth or math.floor(parentW + 0.5))) end
            if pf.dpbHBox then pf.dpbHBox:SetText(tostring(conf.detachedPowerBarHeight or 6)) end
            if pf.dpbXBox then pf.dpbXBox:SetText(tostring(conf.detachedPowerBarOffsetX or 0)) end
            if pf.dpbYBox then pf.dpbYBox:SetText(tostring(conf.detachedPowerBarOffsetY or -4)) end
        end
    end
    -- Smart open: only position when the popup is opened for a new frame.
    -- If it is already open for this unit, do NOT snap it back (user may have moved it).
    if needReposition then
        MSUF_PositionPopupSmart(pf, parent, 200)
    end
    if pf.UpdateEnabledStates then pf.UpdateEnabledStates() end
    if pf.UpdateDetachSection then pf.UpdateDetachSection() end
pf.MSUF_prev = pf.MSUF_prev or {}
pf.MSUF_prev.key = key
MSUF_EM_CopyKeys(pf.MSUF_prev, conf, MSUF_EM_UNIT_POPUP_PREV_KEYS)
    pf:Show()
end
local function MSUF_UpdateCastbarEditInfo(unit)
    if not MSUF_GridFrame or not MSUF_GridFrame.infoText then
        return
    end
    if not MSUF_UnitEditModeActive then
        return
    end

    MSUF_EM_EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local prefix = MSUF_GetCastbarPrefix(unit)
    local label  = MSUF_GetCastbarLabel(unit)
    if not prefix then
        return
    end

    local defaultX, defaultY
    if unit == "player" then
        defaultX, defaultY = 0, 5
    else
        defaultX, defaultY = 65, -15
    end

    local x = g[prefix .. "OffsetX"] or defaultX
    local y = g[prefix .. "OffsetY"] or defaultY

    local textWidget = MSUF_GridFrame.infoText
    textWidget:SetText(string.format("Editing: %s (X: %d, Y: %d)", label, x, y))

    if MSUF_GridFrame.modeHint then
        MSUF_GridFrame.modeHint:SetText("|cffffff00Drag or use Arrow keys to move. SHIFT=5 / CTRL=10 / ALT=grid step.|r")
        MSUF_GridFrame.modeHint:Show()
    end
end
local function MSUF_UpdateGridOverlay()
    if not MSUF_UnitEditModeActive then
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
            if MSUF_GridFrame.modeHint then
                MSUF_GridFrame.modeHint:Hide()
            end
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
            if MSUF_GridFrame.modeHint then
                MSUF_GridFrame.modeHint:Hide()
            end
        end
        return
    end

    if not MSUF_GridFrame then
        MSUF_CreateGridFrame()
    end

    MSUF_GridFrame:Show()

    if MSUF_GridFrame and MSUF_GridFrame._msufSyncFrameEnableButtons then
        MSUF_GridFrame._msufSyncFrameEnableButtons()
    end

    if MSUF_GridFrame.modeHint then
        MSUF_GridFrame.modeHint:Show()
    end

    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
    end
end
function MSUF_OpenCastbarPositionPopup(unit, parent)
    if not MSUF_UnitEditModeActive then
        return
    end

    if not MSUF_EM_EnsureDB() then
        return
    end
    if not unit or not parent then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Position/GrÃ‚Â¶ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¸e der Castbar kann im Kampf nicht geÃ‚Â¤ndert werden.")
        return
    end

    -- Ensure the header "Edit Unit" selector reflects the castbar unit we are editing.
    if unit and type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(true, unit)
    elseif unit then
        MSUF_CurrentEditUnitKey = unit
        if MSUF_GridFrame and MSUF_GridFrame._msufSyncEditUnitSelector then
            MSUF_GridFrame._msufSyncEditUnitSelector()
        end
    end

    ApplyCastbarPopupValues = function()
        if InCombatLockdown and InCombatLockdown() then
            if _G.MSUF_CastbarPositionPopup and _G.MSUF_CastbarPositionPopup.Hide then
                _G.MSUF_CastbarPositionPopup:Hide()
            end
            return
        end
        if MSUF__CastbarPopupSyncing or MSUF__CastbarPopupApplying then
            return
        end

        MSUF__CastbarPopupApplying = true
        local ok, err = MSUF_FastCall(function()
            MSUF_EM_EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general

            local pf = _G.MSUF_CastbarPositionPopup
            if not pf or not pf.unit or not pf.parent then
                return
            end

            local P = Edit and Edit.Popups
            local specs = P and P.Specs
            local U = P and P.Util
            if not (P and specs and U and P.ReadFields) then
                return
            end

            -- Always read the active popup context from the panel (prevents stale/old-unit writes).
            local unit = pf._msufUnitKey or pf.unit
            local parent = pf.parent

            local function GlobalCastFont()
                local baseSize = tonumber(g.fontSize) or 14
                local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
                return (globalOverride and globalOverride > 0) and globalOverride or baseSize
            end

            -- Boss Castbar (stored on g via bossCast*)
            if unit == "boss" then
                local currentW = tonumber(g.bossCastbarWidth)  or (parent and parent.GetWidth and parent:GetWidth())  or 240
                local currentH = tonumber(g.bossCastbarHeight) or (parent and parent.GetHeight and parent:GetHeight()) or 18

                -- Apply numeric fields via specs (store=true does the DB writeback)
                P.ReadFields(pf, { conf = g, currentW = currentW, currentH = currentH }, specs.BossCastbarFramePosition)
                P.ReadFields(pf, { conf = g }, specs.BossCastbarNameOffsets)
                P.ReadFields(pf, { conf = g }, specs.BossCastbarIconOffsets)
                P.ReadFields(pf, { conf = g }, specs.BossCastbarTimeOffsets)

                -- show toggles
                if pf.castNameShowCB and pf.castNameShowCB.GetChecked then
                    g.showBossCastName = pf.castNameShowCB:GetChecked() and true or false
                end
                if pf.iconShowCB and pf.iconShowCB.GetChecked then
                    g.showBossCastIcon = pf.iconShowCB:GetChecked() and true or false
                end
                if pf.timeShowCB and pf.timeShowCB.GetChecked then
                    g.showBossCastTime = pf.timeShowCB:GetChecked() and true or false
                end

                -- overrides
                local globalSize = GlobalCastFont()
                U.ApplyOptionalOverrideNumber(g, "bossCastSpellNameFontSize", pf.castNameSizeBox, pf.castNameOverrideCB,
                    pf.SetCastbarSizeControlsEnabled, pf.castNameSizeMinus, pf.castNameSizePlus, (g.showBossCastName ~= false), globalSize, 6, 72)

                U.ApplyOptionalOverrideNumber(g, "bossCastTimeFontSize", pf.timeSizeBox, pf.timeOverrideCB,
                    pf.SetCastbarSizeControlsEnabled, pf.timeSizeMinus, pf.timeSizePlus, (g.showBossCastTime ~= false), globalSize, 6, 72)

                local baseIcon = tonumber(g.bossCastbarHeight) or currentH or 18
                U.ApplyOptionalOverrideNumber(g, "bossCastIconSize", pf.iconSizeBox, pf.iconSizeOverrideCB,
                    pf.SetCastbarSizeControlsEnabled, pf.iconSizeMinus, pf.iconSizePlus, (g.showBossCastIcon ~= false), baseIcon, 6, 128)

                -- apply + resync
                if type(_G.MSUF_EditMode_RequestBossCastbarApply) == "function" then
                    _G.MSUF_EditMode_RequestBossCastbarApply()
                end

                -- Boss castbar preview is detached (UIParent anchor). Ensure it refreshes live on every popup change.
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                    _G.MSUF_UpdateBossCastbarPreview()
                end
                if type(_G.MSUF_SyncBossCastbarSliders) == "function" then
                    _G.MSUF_SyncBossCastbarSliders()
                end
                if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                    _G.MSUF_SyncCastbarPositionPopup("boss")
                end
                return
            end

            -- Player / Target / Focus Castbars (prefix keys)
            local prefix = pf._msufDbPrefix or ((type(_G.MSUF_GetCastbarPrefix) == "function") and _G.MSUF_GetCastbarPrefix(unit) or nil)
            if not prefix then
                return
            end

            local defaultX, defaultY = 0, 0
            if type(_G.MSUF_GetCastbarDefaultOffsets) == "function" then
                defaultX, defaultY = _G.MSUF_GetCastbarDefaultOffsets(unit)
            end

            local currentW = tonumber(g[prefix .. "BarWidth"])  or tonumber(g.castbarGlobalWidth)  or (parent and parent.GetWidth and parent:GetWidth())  or 200
            local currentH = tonumber(g[prefix .. "BarHeight"]) or tonumber(g.castbarGlobalHeight) or (parent and parent.GetHeight and parent:GetHeight()) or 16

            -- Apply numeric fields via specs
            P.ReadFields(pf, { conf = g, prefix = prefix, defaultX = defaultX, defaultY = defaultY, currentW = currentW, currentH = currentH }, specs.CastbarFramePosition)
            P.ReadFields(pf, { conf = g, prefix = prefix }, specs.CastbarNameOffsets)
            P.ReadFields(pf, { conf = g, prefix = prefix }, specs.CastbarIconOffsets)
            P.ReadFields(pf, { conf = g, prefix = prefix, defaultTimeX = -2, defaultTimeY = 0 }, specs.CastbarTimeOffsets)

            -- show toggles
            if pf.castNameShowCB and pf.castNameShowCB.GetChecked then
                g[prefix .. "ShowSpellName"] = pf.castNameShowCB:GetChecked() and true or false
            end
            if pf.iconShowCB and pf.iconShowCB.GetChecked then
                g[prefix .. "ShowIcon"] = pf.iconShowCB:GetChecked() and true or false
            end

            local showKey = (type(_G.MSUF_GetCastbarShowTimeKey) == "function") and _G.MSUF_GetCastbarShowTimeKey(unit)
            if showKey and pf.timeShowCB and pf.timeShowCB.GetChecked then
                g[showKey] = pf.timeShowCB:GetChecked() and true or false
            end

            -- overrides
            local globalSize = GlobalCastFont()

            U.ApplyOptionalOverrideNumber(g, prefix .. "SpellNameFontSize", pf.castNameSizeBox, pf.castNameOverrideCB,
                pf.SetCastbarSizeControlsEnabled, pf.castNameSizeMinus, pf.castNameSizePlus, (g[prefix .. "ShowSpellName"] ~= false), globalSize, 6, 48)

            U.ApplyOptionalOverrideNumber(g, prefix .. "TimeFontSize", pf.timeSizeBox, pf.timeOverrideCB,
                pf.SetCastbarSizeControlsEnabled, pf.timeSizeMinus, pf.timeSizePlus, ((showKey and g[showKey] ~= false) or true), globalSize, 6, 48)

            local baseIcon = tonumber(g[prefix .. "BarHeight"]) or tonumber(g.castbarGlobalHeight) or currentH or 16
            U.ApplyOptionalOverrideNumber(g, prefix .. "IconSize", pf.iconSizeBox, pf.iconSizeOverrideCB,
                pf.SetCastbarSizeControlsEnabled, pf.iconSizeMinus, pf.iconSizePlus, (g[prefix .. "ShowIcon"] ~= false), baseIcon, 6, 128)

            -- reanchor + visuals
            local reanchorName = (unit == "player" and "MSUF_ReanchorPlayerCastBar") or
                                 (unit == "target" and "MSUF_ReanchorTargetCastBar") or
                                 (unit == "focus"  and "MSUF_ReanchorFocusCastBar")
            local reanchorFn = reanchorName and _G[reanchorName]
            if type(reanchorFn) == "function" then
                reanchorFn()
            end

            if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                _G.MSUF_UpdateCastbarVisuals()
            end
            if type(_G.MSUF_UpdateCastbarEditInfo) == "function" then
                _G.MSUF_UpdateCastbarEditInfo(unit)
            end
            if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                _G.MSUF_SyncCastbarPositionPopup(unit)
            end
            if pf and pf.UpdateEnabledStates then pf.UpdateEnabledStates() end

            -- test mode toggles (dispatch-driven)
            local TEST_MODE_FNS = {
                player = "MSUF_SetPlayerCastbarTestMode",
                target = "MSUF_SetTargetCastbarTestMode",
                focus  = "MSUF_SetFocusCastbarTestMode",
                boss   = "MSUF_SetBossCastbarTestMode",
            }
            for tUnit, fnName in pairs(TEST_MODE_FNS) do
                local fn = _G[fnName]
                if type(fn) == "function" then
                    local popup = _G.MSUF_CastbarPositionPopup
                    local want = (unit == tUnit) and popup and popup.IsShown and popup:IsShown() and popup.unit == tUnit
                    fn(want, true)
                end
            end
        end)

        MSUF__CastbarPopupApplying = false
        if not ok then
            error(err)
        end
    end

    MSUF_EM_EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

local prefix
local defaultX, defaultY
local curX, curY, curW, curH

local function SanitizeOffset(v, default)
    v = tonumber(v) or default or 0
    if v > 2000 then
        v = default or 0
    elseif v < -2000 then
        v = default or 0
    end
    return math.floor(v + 0.5)
end

if unit == "boss" then
    defaultX, defaultY = 0, 0

    curX = SanitizeOffset(g.bossCastbarOffsetX, defaultX)
    curY = SanitizeOffset(g.bossCastbarOffsetY, defaultY)
    curW = tonumber(g.bossCastbarWidth)  or (parent:GetWidth()  or 240)
    curH = tonumber(g.bossCastbarHeight) or (parent:GetHeight() or 18)

    g.bossCastbarOffsetX = curX
    g.bossCastbarOffsetY = curY
else
    prefix = MSUF_GetCastbarPrefix(unit)
    defaultX, defaultY = MSUF_GetCastbarDefaultOffsets(unit)
    if not prefix then
        return
    end

    curX = SanitizeOffset(g[prefix .. "OffsetX"], defaultX)
    curY = SanitizeOffset(g[prefix .. "OffsetY"], defaultY)
    curW = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or (parent:GetWidth()  or 200)
    curH = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or (parent:GetHeight() or 16)

    g[prefix .. "OffsetX"] = curX
    g[prefix .. "OffsetY"] = curY
end

    if not MSUF_CastbarPositionPopup then
        local pf = CreateFrame("Frame", "MSUF_CastbarPositionPopup", UIParent, "BackdropTemplate")
        MSUF_CastbarPositionPopup = pf
        if Edit and Edit.Popups and Edit.Popups.Register then Edit.Popups.Register(pf) end
        local uw, uh = 320, 480
        MSUF_InitEditPopupFrame(pf, {
            w = uw,
            h = uh,
            useDefaultBackdrop = true,
        })
        MSUF_EM_AddPopupTitleAndClose(pf, "MSUF Edit  Castbar")
        local frameHeader = MSUF_EM_AddSectionHeader(pf, "frameHeader", "Frame", "TOPLEFT", pf, "TOPLEFT", 16, -36)

local frameRows = {
    { key = "x", label = "Offset X:", box = "$parentXBox", dy = -6 },
    { key = "y", label = "Offset Y:", box = "$parentYBox", dy = -8 },
    { key = "w", label = "Width:",    box = "$parentWBox", dy = -12 },
    { key = "h", label = "Height:",   box = "$parentHBox", dy = -8 },
}
MSUF_EM_BuildNumericRows(pf, frameRows, frameHeader, "BOTTOMLEFT", 0, ApplyCastbarPopupValues)

        -- Text section (CastName position + per-castbar font override)
        local textDivider = MSUF_EM_AddDivider(pf, "textDivider", 230, "TOPLEFT", pf.hLabel, "BOTTOMLEFT", 0, -8)
        local textHeader  = MSUF_EM_AddSectionHeader(pf, "textHeader", "Text", "TOPLEFT", textDivider, "BOTTOMLEFT", 0, -8)

        MSUF_EM_UI_BuildCastbarPopup_TextBlocks(pf, textHeader)

local function _MSUF_EM_GetFrameCenterOffsets(frame, anchorFrame)
    if not frame or not anchorFrame then return 0, 0 end
    local fx, fy = frame:GetCenter()
    local ax, ay = anchorFrame:GetCenter()
    if not fx or not fy or not ax or not ay then return 0, 0 end
    return (fx - ax), (fy - ay)
end

local function _MSUF_EM_GetBottomCenter(frame)
    if not frame then return nil end
    local l, r, b = frame:GetLeft(), frame:GetRight(), frame:GetBottom()
    if not l or not r or not b then return nil end
    return (l + r) * 0.5, b
end

local function _MSUF_EM_GetTopCenter(frame)
    if not frame then return nil end
    local l, r, t = frame:GetLeft(), frame:GetRight(), frame:GetTop()
    if not l or not r or not t then return nil end
    return (l + r) * 0.5, t
end

-- Table-driven castbar resolution (Phase 3 refactor)
local CASTBAR_GLOBALS = {
    player = "MSUF_PlayerCastbar",
    target = "MSUF_TargetCastbar",
    focus  = "MSUF_FocusCastbar",
}

local function _MSUF_EM_GetRealCastbarForUnit(unit)
    local g = CASTBAR_GLOBALS[unit]
    if g then return _G[g] end
    if unit == "boss" then
        return _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"]
    end
    return nil
end

-- Table-driven castbar reanchor dispatch
local CASTBAR_REANCHOR = {
    player = "MSUF_ReanchorPlayerCastBar",
    target = "MSUF_ReanchorTargetCastBar",
    focus  = "MSUF_ReanchorFocusCastBar",
}

local function _MSUF_EM_ReanchorCastbarForUnit(unit)
    if unit == "boss" then
        local fn = _G.MSUF_ApplyBossCastbarPositionSetting
        if type(fn) == "function" then pcall(fn) end
        fn = _G.MSUF_UpdateBossCastbarPreview
        if type(fn) == "function" then pcall(fn) end
        return
    end
    local name = CASTBAR_REANCHOR[unit]
    if name then
        local fn = _G[name]
        if type(fn) == "function" then pcall(fn) end
        return
    end
    local prefix = (type(_G.MSUF_GetCastbarPrefix) == "function") and _G.MSUF_GetCastbarPrefix(unit)
    if prefix and type(prefix) == "string" then
        local pretty = prefix:gsub("^castbar", "")
        if pretty and pretty ~= "" then
            local fn = _G["MSUF_Reanchor" .. pretty .. "CastBar"]
            if type(fn) == "function" then pcall(fn) end
        end
    end
end

-- Table-driven castbar preview fallbacks
local CASTBAR_PREVIEW_GLOBALS = {
    player = "MSUF_PlayerCastbarPreview",
    target = "MSUF_TargetCastbarPreview",
    focus  = "MSUF_FocusCastbarPreview",
}

local function _MSUF_EM_SetCastbarAnchoredToUnit(unit, anchored)
    if not unit then return end
    local g = MSUF_DB and MSUF_DB.general
    if not g then return end

    -- Keys for offset + detached state
    local detachedKey, oxKey, oyKey
    local anchorMode = "unit"

    if unit == "boss" then
        detachedKey = "bossCastbarDetached"
        oxKey = "bossCastbarOffsetX"
        oyKey = "bossCastbarOffsetY"
        anchorMode = "boss"
    else
        local prefix = _G.MSUF_GetCastbarPrefix and _G.MSUF_GetCastbarPrefix(unit)
        if not prefix then return end
        detachedKey = prefix .. "Detached"
        oxKey = prefix .. "OffsetX"
        oyKey = prefix .. "OffsetY"
        if unit == "player" then
            anchorMode = "player"
        end
    end

    local castbar = _MSUF_EM_GetRealCastbarForUnit(unit)
    if not castbar then
        local pvName = CASTBAR_PREVIEW_GLOBALS[unit]
        if pvName then
            castbar = _G[pvName]
        elseif unit == "boss" then
            castbar = _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"]
        end
    end
    if not castbar then return end

    local wantDetached = (anchored == false)
    local wasDetached = (g[detachedKey] == true)
    if wantDetached == wasDetached then return end

    local anchorFrame = UIParent

    if wantDetached then
        local dx, dy = _MSUF_EM_GetFrameCenterOffsets(castbar, anchorFrame)
        g[oxKey] = dx
        g[oyKey] = dy
        g[detachedKey] = true
    else
        local unitframe
        if anchorMode == "boss" then
            unitframe = _G.MSUF_boss1 or (UnitFrames and UnitFrames["boss1"]) or (UnitFrames and UnitFrames["boss"])
        else
            unitframe = UnitFrames and UnitFrames[unit]
        end
        if not unitframe or not unitframe.GetCenter then return end

        if anchorMode == "player" then
            local ax, ay = _MSUF_EM_GetTopCenter(unitframe)
            local bx, by = _MSUF_EM_GetBottomCenter(castbar)
            if ax and ay and bx and by then
                g[oxKey] = bx - ax
                g[oyKey] = by - ay
            end
        else
            local tlx, tly = unitframe:GetLeft(), unitframe:GetTop()
            local blx, bly = castbar:GetLeft(), castbar:GetBottom()
            if tlx and tly and blx and bly then
                g[oxKey] = blx - tlx
                local baseY = (anchorMode == "boss") and 2 or 0
                g[oyKey] = (bly - tly) - baseY
            end
        end
        g[detachedKey] = nil
    end

    _MSUF_EM_ReanchorCastbarForUnit(unit)
end

        -- Anchor-to-Unitframe toggle (per-castbar). Default ON = anchored, OFF = detached (free move).
        if not pf.anchorToUnitCB then
            pf.anchorToUnitCB = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
            pf.anchorToUnitCB:SetPoint("BOTTOMLEFT", 14, 78)
            if pf.anchorToUnitCB.Text then
                pf.anchorToUnitCB.Text:SetText("Anchor to unitframe")
            end
            pf.anchorToUnitCB:SetChecked(true)
        end
        if pf.anchorToUnitCB then
            pf.anchorToUnitCB:SetScript("OnClick", function(self)
                local p = MSUF_CastbarPositionPopup
                local unit = p and p.unit
                if not unit then
                    return
                end
                local anchored = self:GetChecked() and true or false
                _MSUF_EM_SetCastbarAnchoredToUnit(unit, anchored)
            end)
        end
        -- testModeCB is optional/legacy (some builds create it in other modules). Never assume it exists.
        if pf.testModeCB then
            pf.testModeCB:Hide()
        end

        local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
        local CS = UISpec and UISpec.Castbar

        if CS and CS.copyDropdowns then
            MSUF_EM_UI_BuildCopyDropdown(pf, CS.copyDropdowns.size)
            MSUF_EM_UI_BuildCopyDropdown(pf, CS.copyDropdowns.text)
        end

        -- Copy dropdowns (castbar) keep the exact same behavior as before (boss uses boss keys; others use castbar prefix).
        pf.RefreshCopySizeDropdown = function()
            MSUF_EM_RefreshCastbarCopyDropdown(pf, pf.copySizeDrop, pf.copySizeLabel, "Copy size settings to...", "size")
        end

        pf.RefreshCopyTextDropdown = function()
            MSUF_EM_RefreshCastbarCopyDropdown(pf, pf.copyTextDrop, pf.copyTextLabel, "Copy text settings to...", "text")
        end

        local okBtn, cancelBtn, menuBtn = MSUF_EM_UI_BuildFooterButtons(pf, (CS and CS.footer) or nil)

        if menuBtn then
            menuBtn:SetScript("OnClick", function()
                if type(MSUF_EM_SuppressNextBlizzardExit) == "function" then MSUF_EM_SuppressNextBlizzardExit() end
                local p = MSUF_CastbarPositionPopup
                local unit = p and p.unit
                if unit and type(_G.MSUF_OpenOptionsToCastbarMenu) == "function" then
                    _G.MSUF_OpenOptionsToCastbarMenu(unit)
                end
                pf:Hide()
            end)
        end

        cancelBtn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                if MSUF_CastbarPositionPopup and MSUF_CastbarPositionPopup.Hide then MSUF_CastbarPositionPopup:Hide() end
                return
            end
            MSUF_EM_EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            local pf = MSUF_CastbarPositionPopup
            if pf and pf.MSUF_prev then
                local unit = pf.MSUF_prev.unit
                if unit == "boss" then
                    MSUF_EM_CopyKeys(g, pf.MSUF_prev, MSUF_EM_BOSS_CASTBAR_PREV_KEYS)
                    MSUF_EditMode_RequestBossCastbarApply()

                    if type(MSUF_SyncBossCastbarSliders) == "function" then
                        MSUF_SyncBossCastbarSliders()
                    end
                    if MSUF_SyncCastbarPositionPopup then
                        MSUF_SyncCastbarPositionPopup("boss")
                    end
                else
                    local prefix = pf.MSUF_prev.prefix
                    if prefix then
                        MSUF_EM_RestorePrefixFields(g, pf.MSUF_prev, prefix, MSUF_EM_CASTBAR_PREFIX_RESTORE_SUFFIXES)

                        local showTimeKey = "show" .. unit:sub(1,1):upper() .. unit:sub(2) .. "CastTime"
                        g[showTimeKey] = pf.MSUF_prev[showTimeKey]
                    end

                    local reanchorFn = CASTBAR_REANCHOR[unit] and _G[CASTBAR_REANCHOR[unit]]
                    if type(reanchorFn) == "function" then reanchorFn() end

                    if MSUF_UpdateCastbarVisuals then
                        MSUF_UpdateCastbarVisuals()
                    end
                    if MSUF_UpdateCastbarEditInfo and unit ~= "boss" then
                        MSUF_UpdateCastbarEditInfo(unit)
                    end
                    if MSUF_SyncCastbarPositionPopup then
                        MSUF_SyncCastbarPositionPopup(unit)
                    end
                end
            end
            pf:Hide()
        end)

        local OnEnterPressed, OnEscapePressed = MSUF_EM_BindOkEnterHandlers(pf, okBtn, cancelBtn, ApplyCastbarPopupValues, "Castbar popup apply failed")

        MSUF_EM_BindKeyScripts(OnEnterPressed, OnEscapePressed,
            pf.xBox, pf.yBox, pf.wBox, pf.hBox, pf.spacingBox,
            pf.castNameXBox, pf.castNameYBox, pf.castNameSizeBox,
            pf.iconXBox, pf.iconYBox, pf.iconSizeBox,
            pf.timeXBox, pf.timeYBox, pf.timeSizeBox
        )
    end

    -- Ensure popup is large enough for all controls (incl. icon size overrides + copy dropdowns).
    -- Also applies when the popup already exists (created earlier in the session).
    do
        local pf = MSUF_CastbarPositionPopup
        if pf and pf.SetSize then
            pf:SetSize(360, 470)
        end
    end

    local pf = MSUF_CastbarPositionPopup

    MSUF_EM_EnsureCopyDropdownGroupBGKilled(pf, pf.copySizeDrop, pf.copyTextDrop)
    local wasShown = (pf and pf.IsShown and pf:IsShown()) and true or false
    local oldUnit  = pf and pf.unit
    local oldParent = pf and pf.parent
    local needReposition = (not wasShown) or (oldUnit ~= unit) or (oldParent ~= parent)

    -- This prevents any "context leak" when reusing the same popup across different castbars.
    pf._msufUnitKey = unit
    pf._msufDbPrefix = (unit ~= "boss") and prefix
    pf._msufContextToken = (pf._msufContextToken or 0) + 1

    -- If we are switching between castbars while the popup stays open, an edit box can retain keyboard
    -- focus which would block SyncFields() from overwriting it (intentional behavior for same-context edits).
    -- That would leave stale values from the previous castbar in the boxes and can overwrite the new
    -- castbar's DB keys on the next live apply. Clear focus and force a full Sync on context changes.
    local forceSync = (not wasShown) or (oldUnit ~= unit) or (oldParent ~= parent)
    if forceSync then
        if pf.ClearFocus then
            pf:ClearFocus()
        end
        -- Clear focus on all relevant edit boxes.
        local focusBoxes = { pf.xBox, pf.yBox, pf.wBox, pf.hBox, pf.spacingBox,
                             pf.castNameXBox, pf.castNameYBox, pf.castNameSizeBox,
                             pf.iconXBox, pf.iconYBox, pf.iconSizeBox,
                             pf.timeXBox, pf.timeYBox, pf.timeSizeBox }
        for i = 1, #focusBoxes do
            local b = focusBoxes[i]
            if b and b.ClearFocus then
                b:ClearFocus()
            end
        end
    end
    pf.unit   = unit
    pf.parent = parent

    local label
    if unit == "boss" then
        label = "Boss"
    else
        label = MSUF_GetUnitLabelForKey(GetConfigKeyForUnit(unit)) or unit
    end
    pf.title:SetText(string.format("MSUF Edit  %s Castbar", label))
    if pf.menuBtn then
        pf.menuBtn:Show()
    end

        -- Popup fields are synced by MSUF_SyncCastbarPositionPopup() (spec engine).
    -- To avoid massive copy-paste, we only ensure that all standard widgets are visible here;
    -- values/toggles are populated by the Sync call further below.
    if not pf.__msufCastbarShowKeys then
        pf.__msufCastbarShowKeys = {
            -- Frame section
            "xLabel","yLabel","wLabel","hLabel","xBox","yBox","wBox","hBox",
            "xMinus","xPlus","yMinus","yPlus","wMinus","wPlus","hMinus","hPlus",

            -- Text section
            "textDivider","textHeader",
            "castNameXLabel","castNameYLabel","castNameSizeLabel",
            "castNameShowCB","castNameOverrideCB",
            "castNameXBox","castNameYBox","castNameSizeBox",
            "castNameXMinus","castNameXPlus","castNameYMinus","castNameYPlus","castNameSizeMinus","castNameSizePlus",

            -- Icon section
            "iconXLabel","iconYLabel","iconSizeLabel",
            "iconShowCB","iconSizeOverrideCB",
            "iconXBox","iconYBox","iconSizeBox",
            "iconXMinus","iconXPlus","iconYMinus","iconYPlus","iconSizeMinus","iconSizePlus",

            -- Time section
            "timeXLabel","timeYLabel","timeSizeLabel",
            "timeShowCB","timeOverrideCB",
            "timeXBox","timeYBox","timeSizeBox",
            "timeXMinus","timeXPlus","timeYMinus","timeYPlus","timeSizeMinus","timeSizePlus",

            -- Copy helpers
            "copyTextLabel","copyTextDrop","copySizeLabel","copySizeDrop",
        }
    end

    for i = 1, #pf.__msufCastbarShowKeys do
        local w = pf[pf.__msufCastbarShowKeys[i]]
        if w and w.Show then w:Show() end
    end
    if pf.testModeCB then pf.testModeCB:Hide() end

pf.MSUF_prev = pf.MSUF_prev or {}
pf.MSUF_prev.unit = unit
if unit == "boss" then
    MSUF_EM_CopyKeys(pf.MSUF_prev, g, MSUF_EM_BOSS_CASTBAR_PREV_KEYS)
else
    pf.MSUF_prev.prefix = prefix
    if prefix then
        MSUF_EM_RestorePrefixFields(pf.MSUF_prev, g, prefix, MSUF_EM_CASTBAR_PREFIX_RESTORE_SUFFIXES)

        local showTimeKey = "show" .. unit:sub(1,1):upper() .. unit:sub(2) .. "CastTime"
        pf.MSUF_prev[showTimeKey] = g[showTimeKey]
    end
end

    -- Player castbar: run a looping dummy cast on the preview while this popup is open.
    if pf.testModeCB then
        pf.testModeCB:Hide()
    end
    -- Test mode: dispatch-driven
    local TEST_MODE_FNS = {
        player = "MSUF_SetPlayerCastbarTestMode",
        target = "MSUF_SetTargetCastbarTestMode",
        focus  = "MSUF_SetFocusCastbarTestMode",
        boss   = "MSUF_SetBossCastbarTestMode",
    }
    for tUnit, fnName in pairs(TEST_MODE_FNS) do
        local fn = _G[fnName]
        if type(fn) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == tUnit) and popup and popup.IsShown and popup:IsShown() and popup.unit == tUnit
            fn(want, true)
        end
    end

    -- Keep popup fields in sync with DB on open (and ensure player-only controls like test mode are visible immediately).
    if type(MSUF_SyncCastbarPositionPopup) == "function" then
        MSUF_SyncCastbarPositionPopup(unit, forceSync)
    end

    -- Smart open: place near the castbar frame, on the side with the most free screen space
    -- (same logic as unitframe popup). Fallback to screen center if we can't get bounds.
    -- Only position when the popup is opened for a NEW castbar frame. If already open for this unit,
    -- do NOT snap it back on click (user may have moved it).
    if needReposition then
        do
            local did = false
            if parent and parent.GetLeft then
                local l, r, t, b = parent:GetLeft(), parent:GetRight(), parent:GetTop(), parent:GetBottom()
                if l and r and t and b and type(MSUF_PositionPopupSmart) == "function" then
                    MSUF_PositionPopupSmart(pf, parent, 200)
                    did = true
                end
            end
            if not did then
                pf:ClearAllPoints()
                pf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                pf:SetClampedToScreen(true)
            end
        end
        end

    pf:Show()
    pf:Raise()
end
local function MSUF_UpdateEditModeVisuals()
    MSUF_UpdateGridOverlay()
end
function MSUF_SyncCastbarPositionPopup(unit, force)
    if MSUF__CastbarPopupApplying or MSUF__CastbarPopupSyncing then
        return
    end

    MSUF__CastbarPopupSyncing = true
    local ok = MSUF_FastCall(function()
        local pf = MSUF_CastbarPositionPopup
        if not pf or not pf:IsShown() then
            return
        end
        if pf.unit ~= unit then
            return
        end

        MSUF_EM_EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        -- Anchor-to-Unitframe toggle (player/target/focus/boss)
        if pf.anchorToUnitCB then
            if unit == "boss" then
                local detached = g.bossCastbarDetached and true or false
                pf.anchorToUnitCB:SetChecked(not detached)
                if pf.anchorToUnitCB.Text then
                    pf.anchorToUnitCB.Text:SetText("Anchor to Boss unitframe")
                end
                pf.anchorToUnitCB:Show()
            else
                local prefix = (type(_G.MSUF_GetCastbarPrefix) == "function") and _G.MSUF_GetCastbarPrefix(unit)
                if prefix then
                    local detached = g[prefix .. "Detached"] and true or false
                    pf.anchorToUnitCB:SetChecked(not detached)
                    if pf.anchorToUnitCB.Text then
                        local label = (unit == "player" and "Player") or (unit == "target" and "Target") or (unit == "focus" and "Focus") or unit
                        pf.anchorToUnitCB.Text:SetText("Anchor to " .. label .. " unitframe")
                    end
                    pf.anchorToUnitCB:Show()
                else
                    pf.anchorToUnitCB:Hide()
                end
            end
        end
        local P = Edit and Edit.Popups
        local U = P and P.Util

        local function GetGlobalCastbarFontSize()
            local baseSize = g.fontSize or 14
            local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
            return (globalOverride and globalOverride > 0) and globalOverride or baseSize
        end

        -- Boss castbar is stored on MSUF_DB.general using "bossCast*" keys.
        if unit == "boss" then
            local parent = pf.parent or UIParent
            local currentW = tonumber(g.bossCastbarWidth)  or (parent.GetWidth and parent:GetWidth())  or 240
            local currentH = tonumber(g.bossCastbarHeight) or (parent.GetHeight and parent:GetHeight()) or 18
            if P and P.SyncFields then
                local specs = (Edit and Edit.Popups and Edit.Popups.Specs)
                if specs then
                    local ctxForce = force and true or false
                    P.SyncFields(pf, { conf = g, currentW = currentW, currentH = currentH, force = ctxForce }, specs.BossCastbarFramePosition)
                    P.SyncFields(pf, { conf = g, force = ctxForce }, specs.BossCastbarNameOffsets)
                    P.SyncFields(pf, { conf = g, force = ctxForce }, specs.BossCastbarIconOffsets)
                    P.SyncFields(pf, { conf = g, force = ctxForce }, specs.BossCastbarTimeOffsets)
                end
            end

            if pf.castNameShowCB and pf.castNameShowCB.SetChecked then
                pf.castNameShowCB:SetChecked((g.showBossCastName ~= false) and true or false)
            end

            local showBossIcon = (g.showBossCastIcon == nil) and (g.castbarShowIcon ~= false) or (g.showBossCastIcon ~= false)
            if pf.iconShowCB and pf.iconShowCB.SetChecked then
                pf.iconShowCB:SetChecked(showBossIcon and true or false)
            end

            if pf.timeShowCB and pf.timeShowCB.SetChecked then
                pf.timeShowCB:SetChecked((g.showBossCastTime ~= false) and true or false)
            end

            if U and U.SyncOptionalOverrideNumber then
                local globalSize = GetGlobalCastbarFontSize()
                U.SyncOptionalOverrideNumber(g, "bossCastSpellNameFontSize", pf.castNameSizeBox, pf.castNameOverrideCB, pf.SetCastbarSizeControlsEnabled,
                    pf.castNameSizeMinus, pf.castNameSizePlus, (g.showBossCastName ~= false), globalSize)

                local baseIcon = tonumber(g.bossCastbarHeight) or currentH or 18
                U.SyncOptionalOverrideNumber(g, "bossCastIconSize", pf.iconSizeBox, pf.iconSizeOverrideCB, pf.SetCastbarSizeControlsEnabled,
                    pf.iconSizeMinus, pf.iconSizePlus, (showBossIcon ~= false), baseIcon)

                U.SyncOptionalOverrideNumber(g, "bossCastTimeFontSize", pf.timeSizeBox, pf.timeOverrideCB, pf.SetCastbarSizeControlsEnabled,
                    pf.timeSizeMinus, pf.timeSizePlus, (g.showBossCastTime ~= false), globalSize)
            end

            if pf.RefreshCopyTextDropdown then pf.RefreshCopyTextDropdown() end
            if pf.RefreshCopySizeDropdown then pf.RefreshCopySizeDropdown() end
            if pf.UpdateEnabledStates then pf.UpdateEnabledStates() end
            return
        end

        -- Player / Target / Focus (prefix keys, e.g. "playerCastbarOffsetX")
            local prefix = pf._msufDbPrefix or MSUF_GetCastbarPrefix(unit)
        local defaultX, defaultY = MSUF_GetCastbarDefaultOffsets(unit)
        if not prefix then
            return
        end

        local parent = pf.parent or UIParent
        local currentW = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or (parent.GetWidth and parent:GetWidth())  or 200
        local currentH = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or (parent.GetHeight and parent:GetHeight()) or 16

        if P and P.SyncFields then
            local ctxForce = force and true or false
            P.SyncFields(pf, { conf = g, prefix = prefix, defaultX = defaultX, defaultY = defaultY, currentW = currentW, currentH = currentH, force = ctxForce }, Edit.Popups.Specs.CastbarFramePosition)
            P.SyncFields(pf, { conf = g, prefix = prefix, force = ctxForce }, Edit.Popups.Specs.CastbarNameOffsets)
            P.SyncFields(pf, { conf = g, prefix = prefix, force = ctxForce }, Edit.Popups.Specs.CastbarIconOffsets)

            local defTX, defTY = -2, 0
            if unit ~= "player" then
                defTX = tonumber(g.castbarPlayerTimeOffsetX) or defTX
                defTY = tonumber(g.castbarPlayerTimeOffsetY) or defTY
            end
            P.SyncFields(pf, { conf = g, prefix = prefix, defaultTimeX = defTX, defaultTimeY = defTY, force = ctxForce }, Edit.Popups.Specs.CastbarTimeOffsets)
        end

        -- show toggles
        local storedShow = g[prefix .. "ShowSpellName"]
        local showSpell = (storedShow == nil) and (g.castbarShowSpellName ~= false) or (storedShow ~= false)
        if pf.castNameShowCB and pf.castNameShowCB.SetChecked then
            pf.castNameShowCB:SetChecked(showSpell and true or false)
        end

        local storedIcon = g[prefix .. "ShowIcon"]
        local showIconLocal = (storedIcon == nil) and (g.castbarShowIcon ~= false) or (storedIcon ~= false)
        if pf.iconShowCB and pf.iconShowCB.SetChecked then
            pf.iconShowCB:SetChecked(showIconLocal and true or false)
        end

        local showTime = true
        if unit == "player" then
            showTime = (g.showPlayerCastTime ~= false)
        elseif unit == "target" then
            showTime = (g.showTargetCastTime ~= false)
        elseif unit == "focus" then
            showTime = (g.showFocusCastTime ~= false)
        end
        if pf.timeShowCB and pf.timeShowCB.SetChecked then
            pf.timeShowCB:SetChecked(showTime and true or false)
        end

        if U and U.SyncOptionalOverrideNumber then
            local globalSize = GetGlobalCastbarFontSize()

            U.SyncOptionalOverrideNumber(g, prefix .. "SpellNameFontSize", pf.castNameSizeBox, pf.castNameOverrideCB, pf.SetCastbarSizeControlsEnabled,
                pf.castNameSizeMinus, pf.castNameSizePlus, showSpell, globalSize)

            local baseIcon = tonumber(g[prefix .. "BarHeight"]) or tonumber(g.castbarGlobalHeight) or currentH or 16
            U.SyncOptionalOverrideNumber(g, prefix .. "IconSize", pf.iconSizeBox, pf.iconSizeOverrideCB, pf.SetCastbarSizeControlsEnabled,
                pf.iconSizeMinus, pf.iconSizePlus, showIconLocal, baseIcon)

            U.SyncOptionalOverrideNumber(g, prefix .. "TimeFontSize", pf.timeSizeBox, pf.timeOverrideCB, pf.SetCastbarSizeControlsEnabled,
                pf.timeSizeMinus, pf.timeSizePlus, showTime, globalSize)
        end

        if pf.RefreshCopyTextDropdown then pf.RefreshCopyTextDropdown() end
        if pf.testModeCB then pf.testModeCB:Hide() end
        if pf.RefreshCopySizeDropdown then pf.RefreshCopySizeDropdown() end
        if pf.UpdateEnabledStates then pf.UpdateEnabledStates() end
    end)

    MSUF__CastbarPopupSyncing = false
    if not ok then
        return
    end
end

local function MSUF_SyncUnitPositionPopup(unit, conf)
    local pf = MSUF_PositionPopup
    if not pf or not pf:IsShown() then
        return
    end

    -- Support legacy calls with no args (e.g. Cancel/refresh).
    local popupUnit = pf.unit
    local popupKey = popupUnit and GetConfigKeyForUnit and GetConfigKeyForUnit(popupUnit) or popupUnit

    local key = unit or popupKey
    if not key then
        return
    end

    if unit and popupUnit and unit ~= popupUnit and popupKey and unit ~= popupKey then
        return
    end

    if not conf then
        MSUF_EM_EnsureDB()
        if not MSUF_DB then return end
        conf = MSUF_DB[key]
    end
    if type(conf) ~= "table" then
        return
    end

    local g = (MSUF_DB and MSUF_DB.general) or {}
    local baseSize       = g.fontSize or 14
    local globalNameSize = g.nameFontSize  or baseSize
    local globalHPSize   = g.hpFontSize    or baseSize
    local globalPowSize  = g.powerFontSize or baseSize

    local currentW = conf.width
    local currentH = conf.height
    if (not currentW or not currentH) and pf.parent then
        currentW = currentW or pf.parent:GetWidth()
        currentH = currentH or pf.parent:GetHeight()
    end

    local P = Edit and Edit.Popups
    local U = P and P.Util

    if P and P.SyncFields then
        P.SyncFields(pf, { conf = conf, currentW = currentW, currentH = currentH }, Edit.Popups.Specs.UnitFramePosition)
    end

    local showNameVal  = (conf.showName  ~= false)
    local showHPVal    = (conf.showHP    ~= false)
    local showPowerVal = (conf.showPower ~= false)

    if pf.nameShowCB and pf.nameShowCB.SetChecked then
        pf.nameShowCB:SetChecked(showNameVal and true or false)
    end
    if pf.hpShowCB and pf.hpShowCB.SetChecked then
        pf.hpShowCB:SetChecked(showHPVal and true or false)
    end
    if pf.powerShowCB and pf.powerShowCB.SetChecked then
        pf.powerShowCB:SetChecked(showPowerVal and true or false)
    end

    if U and U.SyncOptionalOverrideNumber then
        U.SyncOptionalOverrideNumber(conf, "nameFontSize",  pf.nameSizeBox,  pf.nameOverrideCB,  pf.SetTextSizeControlsEnabled, pf.nameSizeMinus,  pf.nameSizePlus,  showNameVal,  globalNameSize)
        U.SyncOptionalOverrideNumber(conf, "hpFontSize",    pf.hpSizeBox,    pf.hpOverrideCB,    pf.SetTextSizeControlsEnabled, pf.hpSizeMinus,    pf.hpSizePlus,    showHPVal,    globalHPSize)
        U.SyncOptionalOverrideNumber(conf, "powerFontSize", pf.powerSizeBox, pf.powerOverrideCB, pf.SetTextSizeControlsEnabled, pf.powerSizeMinus, pf.powerSizePlus, showPowerVal, globalPowSize)
    end
end

-- Auras 2.0 Position Popup (Target)  [helper-ready for Focus/Boss later]
-- Requirements:
--  - Drag & drop via Aura Edit Mover (in Auras 2.0 module)
--  - Popup (left/right click) for Offset X/Y + Size + Spacing

local function MSUF_A2_GetAuraPopupTitleSuffix(unitKey)
    if unitKey == 'player' then return 'Player Aura' end
    if unitKey == 'target' then return 'Target Aura' end
    if unitKey == 'focus' then return 'Focus Aura' end
    -- Boss previews will be 'Boss 1 Aura', 'Boss 2 Aura', ...
    if type(unitKey) == 'string' and unitKey:match('^boss%d+$') then
        local n = unitKey:match('^boss(%d+)$')
        if n then return ('Boss %s Aura'):format(n) end
        return 'Boss Aura'
    end
    return 'Aura'
end

-- Helper: creates the popup once, and can be reused for focus/boss later.
function _G.MSUF_A2_EnsureAuraPositionPopup()
    local pf = _G.MSUF_Auras2PositionPopup
    if pf then
        return pf
    end

    pf = CreateFrame('Frame', 'MSUF_EditAuras2PositionPopup', UIParent, 'BackdropTemplate')
    _G.MSUF_Auras2PositionPopup = pf
    if Edit and Edit.Popups and Edit.Popups.Register then Edit.Popups.Register(pf) end

    MSUF_InitEditPopupFrame(pf, {
        w = 320,
            h = 640,
        smoothDrag = true,
        useDefaultBackdrop = true,
    })

    local title = pf:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    title:SetPoint('TOP', 0, -12)
    title:SetText('MSUF Edit  Target Aura')
    pf.title = title

    -- Top-right close (acts like Cancel)
    local closeBtn = CreateFrame('Button', '$parentClose', pf, 'UIPanelCloseButton')
    closeBtn:SetPoint('TOPRIGHT', pf, 'TOPRIGHT', -6, -6)
    closeBtn:SetScript('OnClick', function()
        if pf.cancelBtn and pf.cancelBtn.Click then
            pf.cancelBtn:Click()
        else
            pf:Hide()
        end
    end)
    pf.closeBtn = closeBtn

    local frameHeader = pf:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    frameHeader:SetPoint('TOPLEFT', pf, 'TOPLEFT', 16, -36)
    frameHeader:SetText('Frame')
    frameHeader:SetTextColor(1, 0.82, 0, 1)
    pf.frameHeader = frameHeader

    local function Apply()
        if (pf and (pf._msufAuras2PopupApplying or pf._msufAuras2PopupSyncing)) or _G.MSUF__Auras2PopupApplying then return end
        if pf then pf._msufAuras2PopupApplying = true end
        _G.MSUF__Auras2PopupApplying = true

        local ok = pcall(function()
        MSUF_EM_EnsureDB()
        if not MSUF_DB or not MSUF_DB.auras2 then return end

        local unitKey = pf.unit or 'target'
        local a2db = MSUF_DB.auras2
        a2db.shared = a2db.shared or {}
        a2db.perUnit = a2db.perUnit or {}

        local isBoss = (type(unitKey) == 'string') and unitKey:match('^boss%d+$')
        if a2db.shared.bossEditTogether == nil then
            a2db.shared.bossEditTogether = true
        end
        if isBoss and pf.bossTogetherCheck and pf.bossTogetherCheck.GetChecked then
            a2db.shared.bossEditTogether = (pf.bossTogetherCheck:GetChecked() and true) or false
        end

        local applyKeys
        if isBoss and a2db.shared.bossEditTogether ~= false then
            applyKeys = { 'boss1','boss2','boss3','boss4','boss5' }
            else
            applyKeys = { unitKey }
        end

        local unitKeyEff = unitKey
        if isBoss and a2db.shared.bossEditTogether ~= false then
            unitKeyEff = 'boss1'
        end

        a2db.perUnit[unitKeyEff] = a2db.perUnit[unitKeyEff] or {}
        local uconf = a2db.perUnit[unitKeyEff]
        uconf.layout = uconf.layout or {}

        local function isDirty(key)
            local d = pf and pf._msufA2Dirty
            return d and d[key] == true
        end

        local function readNum(key, box, fallback)
            if not isDirty(key) then
                return fallback
            end
            if not box or not box.GetText then return fallback end
            local t = box:GetText()
            local n = tonumber(t)
            if n == nil then return fallback end
            return n
        end

        local curX = uconf.layout.offsetX or a2db.shared.offsetX or 0
        local curY = uconf.layout.offsetY or a2db.shared.offsetY or 0
        local curSize = uconf.layout.iconSize or a2db.shared.iconSize or 26
        local curSpacing = uconf.layout.spacing or a2db.shared.spacing or 2

        local curStackTextSize = uconf.layout.stackTextSize or a2db.shared.stackTextSize or 14
        local curCooldownTextSize = uconf.layout.cooldownTextSize or a2db.shared.cooldownTextSize or 14

            -- Buffs / Debuffs (independent offsets/sizing)
        local curBuffGroupOffX = (uconf.layout.buffGroupOffsetX ~= nil) and uconf.layout.buffGroupOffsetX or (a2db.shared.buffGroupOffsetX or 0)
        local curBuffGroupOffY = (uconf.layout.buffGroupOffsetY ~= nil) and uconf.layout.buffGroupOffsetY or (a2db.shared.buffGroupOffsetY or 0)
        local curBuffGroupSize = (uconf.layout.buffGroupIconSize ~= nil) and uconf.layout.buffGroupIconSize or (a2db.shared.buffGroupIconSize or curSize)

        local curDebuffGroupOffX = (uconf.layout.debuffGroupOffsetX ~= nil) and uconf.layout.debuffGroupOffsetX or (a2db.shared.debuffGroupOffsetX or 0)
        local curDebuffGroupOffY = (uconf.layout.debuffGroupOffsetY ~= nil) and uconf.layout.debuffGroupOffsetY or (a2db.shared.debuffGroupOffsetY or 0)
        local curDebuffGroupSize = (uconf.layout.debuffGroupIconSize ~= nil) and uconf.layout.debuffGroupIconSize or (a2db.shared.debuffGroupIconSize or curSize)

            -- Private Auras (Blizzard-rendered) independent offsets/sizing
        local curPrivOffX = (uconf.layout.privateOffsetX ~= nil) and uconf.layout.privateOffsetX or (a2db.shared.privateOffsetX or 0)
        local curPrivOffY = (uconf.layout.privateOffsetY ~= nil) and uconf.layout.privateOffsetY or (a2db.shared.privateOffsetY or 0)
        local curPrivSize = (uconf.layout.privateSize ~= nil) and uconf.layout.privateSize or (a2db.shared.privateSize or curSize)
        local haveStackOffsets = (uconf.layout.stackTextOffsetX ~= nil) or (uconf.layout.stackTextOffsetY ~= nil)
        or (a2db.shared.stackTextOffsetX ~= nil) or (a2db.shared.stackTextOffsetY ~= nil)
        local curStackOffX = (uconf.layout.stackTextOffsetX ~= nil) and uconf.layout.stackTextOffsetX or (a2db.shared.stackTextOffsetX or 0)
        local curStackOffY = (uconf.layout.stackTextOffsetY ~= nil) and uconf.layout.stackTextOffsetY or (a2db.shared.stackTextOffsetY or 0)

        local haveCooldownOffsets = (uconf.layout.cooldownTextOffsetX ~= nil) or (uconf.layout.cooldownTextOffsetY ~= nil)
        or (a2db.shared.cooldownTextOffsetX ~= nil) or (a2db.shared.cooldownTextOffsetY ~= nil)
        local curCooldownOffX = (uconf.layout.cooldownTextOffsetX ~= nil) and uconf.layout.cooldownTextOffsetX or (a2db.shared.cooldownTextOffsetX or 0)
        local curCooldownOffY = (uconf.layout.cooldownTextOffsetY ~= nil) and uconf.layout.cooldownTextOffsetY or (a2db.shared.cooldownTextOffsetY or 0)
        local x = curX
        local y = curY
        local size = curSize
        local spacing = readNum('spacing', pf.spacingBox, curSpacing)

        local stackTextSize = readNum('stackTextSize', pf.stackTextSizeBox, curStackTextSize)
        local cooldownTextSize = readNum('cooldownTextSize', pf.cooldownTextSizeBox, curCooldownTextSize)

        local buffGroupOffsetX = readNum('buffGroupOffsetX', pf.buffGroupOffsetXBox, curBuffGroupOffX)
        local buffGroupOffsetY = readNum('buffGroupOffsetY', pf.buffGroupOffsetYBox, curBuffGroupOffY)
        local buffGroupIconSize = readNum('buffGroupIconSize', pf.buffGroupIconSizeBox, curBuffGroupSize)

        local debuffGroupOffsetX = readNum('debuffGroupOffsetX', pf.debuffGroupOffsetXBox, curDebuffGroupOffX)
        local debuffGroupOffsetY = readNum('debuffGroupOffsetY', pf.debuffGroupOffsetYBox, curDebuffGroupOffY)
        local debuffGroupIconSize = readNum('debuffGroupIconSize', pf.debuffGroupIconSizeBox, curDebuffGroupSize)

        local privOffX = readNum('privateOffsetX', pf.privateOffsetXBox, curPrivOffX)
        local privOffY = readNum('privateOffsetY', pf.privateOffsetYBox, curPrivOffY)
        local privSize = readNum('privateSize', pf.privateSizeBox, curPrivSize)

            -- Private Auras preview (highlight marker) is a shared flag
        if pf.privatePreviewCheck and pf.privatePreviewCheck.GetChecked then
            a2db.shared.highlightPrivateAuras = (pf.privatePreviewCheck:GetChecked() and true) or false
        end

        local stackTextOffsetX = readNum('stackTextOffsetX', pf.stackTextOffsetXBox, curStackOffX)
        local stackTextOffsetY = readNum('stackTextOffsetY', pf.stackTextOffsetYBox, curStackOffY)

        local cooldownTextOffsetX = readNum('cooldownTextOffsetX', pf.cooldownTextOffsetXBox, curCooldownOffX)
        local cooldownTextOffsetY = readNum('cooldownTextOffsetY', pf.cooldownTextOffsetYBox, curCooldownOffY)

        stackTextOffsetX = MSUF_SanitizePopupOffset(stackTextOffsetX, 0)
        stackTextOffsetY = MSUF_SanitizePopupOffset(stackTextOffsetY, 0)

        cooldownTextOffsetX = MSUF_SanitizePopupOffset(cooldownTextOffsetX, 0)
        cooldownTextOffsetY = MSUF_SanitizePopupOffset(cooldownTextOffsetY, 0)

                -- Clamp & sanitize all numeric fields (avoid snap-back after mouse-drag).
        local OFF_LIMIT = 2000
        local function clampOff(v)
            v = tonumber(v) or 0
            if v > OFF_LIMIT then return OFF_LIMIT end
            if v < -OFF_LIMIT then return -OFF_LIMIT end
            return v
        end

        size = math.max(10, math.min(80, tonumber(size) or tonumber(iconSize) or 26))
        iconSize = size
        spacing = math.max(0, math.min(30, tonumber(spacing) or 0))

        stackTextSize = math.max(6, math.min(40, tonumber(stackTextSize) or 12))
        cooldownTextSize = math.max(6, math.min(40, tonumber(cooldownTextSize) or 12))

        buffGroupIconSize = math.max(10, math.min(80, tonumber(buffGroupIconSize) or 26))
        debuffGroupIconSize = math.max(10, math.min(80, tonumber(debuffGroupIconSize) or 26))
        privSize = math.max(10, math.min(80, tonumber(privSize) or 26))

        buffGroupOffsetX = clampOff(MSUF_SanitizePopupOffset(buffGroupOffsetX, 0))
        buffGroupOffsetY = clampOff(MSUF_SanitizePopupOffset(buffGroupOffsetY, 0))
        debuffGroupOffsetX = clampOff(MSUF_SanitizePopupOffset(debuffGroupOffsetX, 0))
        debuffGroupOffsetY = clampOff(MSUF_SanitizePopupOffset(debuffGroupOffsetY, 0))
        privOffX = clampOff(MSUF_SanitizePopupOffset(privOffX, 0))
        privOffY = clampOff(MSUF_SanitizePopupOffset(privOffY, 0))

        stackTextOffsetX = clampOff(stackTextOffsetX)
        stackTextOffsetY = clampOff(stackTextOffsetY)
        cooldownTextOffsetX = clampOff(cooldownTextOffsetX)
        cooldownTextOffsetY = clampOff(cooldownTextOffsetY)

            -- IMPORTANT: Only write offsets when they previously existed OR the user changed them.
            -- If we always clear them to nil, the popup X/Y controls appear "dead".
        local function _MSUF_A2_BoxHasText(box)
            if not box or not box.GetText then return false end
            local t = box:GetText()
            return (t ~= nil and t ~= "")
        end

            -- IMPORTANT: Only write offsets when they previously existed OR the user changed them.
            -- Also treat non-empty editboxes as "changed" (stepper buttons / programmatic SetText may not mark dirty).
        local writeStackOffsets =
        haveStackOffsets
        or isDirty('stackTextOffsetX') or isDirty('stackTextOffsetY')
        or _MSUF_A2_BoxHasText(pf.stackTextOffsetXBox) or _MSUF_A2_BoxHasText(pf.stackTextOffsetYBox)

        local writeCooldownOffsets =
        haveCooldownOffsets
        or isDirty('cooldownTextOffsetX') or isDirty('cooldownTextOffsetY')
        or _MSUF_A2_BoxHasText(pf.cooldownTextOffsetXBox) or _MSUF_A2_BoxHasText(pf.cooldownTextOffsetYBox)

        local function ApplyLayoutToUnit(k)
            a2db.perUnit[k] = a2db.perUnit[k] or {}
            local uc = a2db.perUnit[k]
            uc.layout = uc.layout or {}
            uc.overrideLayout = true
            uc.layout.offsetX   = math.floor(x + 0.5)
            uc.layout.offsetY   = math.floor(y + 0.5)
            uc.layout.iconSize  = math.floor(size + 0.5)
            uc.layout.spacing   = math.floor(spacing + 0.5)
            uc.layout.buffGroupOffsetX  = math.floor(buffGroupOffsetX + 0.5)
            uc.layout.buffGroupOffsetY  = math.floor(buffGroupOffsetY + 0.5)
            uc.layout.buffGroupIconSize = math.floor(buffGroupIconSize + 0.5)
            uc.layout.debuffGroupOffsetX  = math.floor(debuffGroupOffsetX + 0.5)
            uc.layout.debuffGroupOffsetY  = math.floor(debuffGroupOffsetY + 0.5)
            uc.layout.debuffGroupIconSize = math.floor(debuffGroupIconSize + 0.5)
            uc.layout.privateOffsetX = math.floor(privOffX + 0.5)
            uc.layout.privateOffsetY = math.floor(privOffY + 0.5)
            uc.layout.privateSize    = math.floor(privSize + 0.5)
            uc.layout.stackTextSize = math.floor(stackTextSize + 0.5)
            uc.layout.cooldownTextSize = math.floor(cooldownTextSize + 0.5)
            if writeStackOffsets then
                uc.layout.stackTextOffsetX = math.floor(stackTextOffsetX + 0.5)
                uc.layout.stackTextOffsetY = math.floor(stackTextOffsetY + 0.5)
                else
                uc.layout.stackTextOffsetX = nil
                uc.layout.stackTextOffsetY = nil
            end

            if writeCooldownOffsets then
                uc.layout.cooldownTextOffsetX = math.floor(cooldownTextOffsetX + 0.5)
                uc.layout.cooldownTextOffsetY = math.floor(cooldownTextOffsetY + 0.5)
                else
                uc.layout.cooldownTextOffsetX = nil
                uc.layout.cooldownTextOffsetY = nil
            end
    -- Keep the edit mover box derived from iconSize/spacing/perRow (no manual box overrides).
            uc.layout.width = nil
            uc.layout.height = nil
        end

        if applyKeys then
            for _, k in ipairs(applyKeys) do
                ApplyLayoutToUnit(k)
            end
            else
            ApplyLayoutToUnit(unitKey)
        end

        if type(_G.MSUF_Auras2_RefreshUnit) == 'function' then
            for _, k in ipairs(applyKeys or {unitKey}) do _G.MSUF_Auras2_RefreshUnit(k) end
                elseif type(_G.MSUF_Auras2_RefreshAll) == 'function' then
                _G.MSUF_Auras2_RefreshAll()
            end

            if type(_G.MSUF_SyncAuras2PositionPopup) == 'function' then
                _G.MSUF_SyncAuras2PositionPopup(unitKey)
            end
        end)
        _G.MSUF__Auras2PopupApplying = false
        if pf then pf._msufAuras2PopupApplying = false end
        if not ok then
            -- fail-open
        end
        end

    -- Phase 10 CLEAN: Build Auras2 numeric rows via rowspec (UI-only)
        local rows = {
        { key = "spacing", label = "Spacing:", box = "$parentSpacingBox", dy = -6, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },

        }

    -- Build the spacing row under the header (position/size are handled via mover + group overrides below)
        MSUF_EM_BuildNumericRows(pf, rows, frameHeader, "BOTTOMLEFT", 0, Apply, "Auras2Popup:LiveApply")

    -- Backwards-compatible alias used by older code in this popup (not used elsewhere)
        pf.sMinus, pf.sPlus = pf.spacingMinus, pf.spacingPlus

    -- Boss-only option: edit Boss 1-5 together (default ON)
        local bossTogether = CreateFrame('CheckButton', '$parentBossTogetherCheck', pf, 'UICheckButtonTemplate')
        bossTogether:SetPoint('TOPLEFT', (pf.spacingRow or pf.spacingLabel), 'BOTTOMLEFT', 0, -6)
        if bossTogether.text then
            bossTogether.text:SetText('Boss 1-5 edit together')
            elseif bossTogether.Text then
            bossTogether.Text:SetText('Boss 1-5 edit together')
        end
        bossTogether:Hide()
        pf.bossTogetherCheck = bossTogether

    -- Remaining rows: stacks + cooldown text sizes
        local rows2 = {
        { key = "stackTextSize", label = "Text size (Stacks):", box = "$parentStackTextSizeBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "stackTextOffsetX", label = "Stack text X:", box = "$parentStackTextOffsetXBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "stackTextOffsetY", label = "Stack text Y:", box = "$parentStackTextOffsetYBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },

        { key = "cooldownTextSize", label = "Text size (Cooldown):", box = "$parentCooldownTextSizeBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "cooldownTextOffsetX", label = "Cooldown text X:", box = "$parentCooldownTextOffsetXBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "cooldownTextOffsetY", label = "Cooldown text Y:", box = "$parentCooldownTextOffsetYBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        }

    -- Initially anchor stacks below spacing; sync code may re-anchor below bossTogetherCheck when visible
        MSUF_EM_BuildNumericRows(pf, rows2, (pf.spacingRow or pf.spacingLabel), "BOTTOMLEFT", 0, Apply, "Auras2Popup:LiveApply")

    -- Buffs / Debuffs (independent X/Y/Size)
        local bdHeader = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bdHeader:SetTextColor(1, 0.82, 0, 1)
        bdHeader:SetText("Buffs / Debuffs")
        bdHeader:SetPoint('TOPLEFT', (pf.cooldownTextOffsetYRow or pf.cooldownTextOffsetYLabel or pf.cooldownTextOffsetYBox or pf.cooldownTextSizeRow or pf.cooldownTextSizeLabel), 'BOTTOMLEFT', 0, -18)
        pf.buffDebuffHeader = bdHeader

        local rowsBD = {
        { key = "buffGroupOffsetX",  label = "Buff offset X:",   box = "$parentBuffOffsetXBox" },
        { key = "buffGroupOffsetY",  label = "Buff offset Y:",   box = "$parentBuffOffsetYBox" },
        { key = "buffGroupIconSize", label = "Buff icon size:",  box = "$parentBuffIconSizeBox" },
        { key = "debuffGroupOffsetX",  label = "Debuff offset X:",  box = "$parentDebuffOffsetXBox" },
        { key = "debuffGroupOffsetY",  label = "Debuff offset Y:",  box = "$parentDebuffOffsetYBox" },
        { key = "debuffGroupIconSize", label = "Debuff icon size:", box = "$parentDebuffIconSizeBox" },
        }
        MSUF_EM_BuildNumericRows(pf, rowsBD, bdHeader, "BOTTOMLEFT", 0, Apply, "Auras2Popup:LiveApply")

    -- Private Auras (Blizzard-rendered): independent offsets + icon size
    -- Note: This edits a2.shared.privateOffsetX/Y/privateSize (with per-unit overrides).
        local privateHeader = pf:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
        privateHeader:SetPoint('TOPLEFT', (pf.debuffGroupIconSizeRow or pf.buffDebuffHeader or pf.cooldownTextOffsetYRow or pf.cooldownTextOffsetYLabel or pf.cooldownTextOffsetYBox or pf.cooldownTextSizeRow or pf.cooldownTextSizeLabel), 'BOTTOMLEFT', 0, -20)
        privateHeader:SetText('Private Auras')
        privateHeader:SetTextColor(1, 0.82, 0, 1)
        pf.privateHeader = privateHeader

        local privatePreview = CreateFrame('CheckButton', '$parentPrivatePreviewCheck', pf, 'UICheckButtonTemplate')
        privatePreview:SetPoint('TOPLEFT', privateHeader, 'BOTTOMLEFT', 0, -6)
        if privatePreview.text then
            privatePreview.text:SetText('Preview (highlight) private auras')
            elseif privatePreview.Text then
            privatePreview.Text:SetText('Preview (highlight) private auras')
        end
        privatePreview:SetScript('OnClick', function()
            Apply()
        end)
        pf.privatePreviewCheck = privatePreview

        local rows3 = {
        { key = "privateOffsetX", label = "Private offset X:", box = "$parentPrivateOffsetXBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "privateOffsetY", label = "Private offset Y:", box = "$parentPrivateOffsetYBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "privateSize",    label = "Private icon size:", box = "$parentPrivateSizeBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        }
        MSUF_EM_BuildNumericRows(pf, rows3, privatePreview, "BOTTOMLEFT", 0, Apply, "Auras2Popup:LiveApply")

        local function OnEnterPressed(self)
            self:ClearFocus()
            Apply()
        end
        MSUF_EM_BindKeyScripts(OnEnterPressed, nil,
        pf.spacingBox,
        pf.stackTextSizeBox, pf.stackTextOffsetXBox, pf.stackTextOffsetYBox,
        pf.cooldownTextSizeBox,
        pf.cooldownTextOffsetXBox, pf.cooldownTextOffsetYBox,
        pf.buffGroupOffsetXBox, pf.buffGroupOffsetYBox, pf.buffGroupIconSizeBox,
        pf.debuffGroupOffsetXBox, pf.debuffGroupOffsetYBox, pf.debuffGroupIconSizeBox,
        pf.privateOffsetXBox, pf.privateOffsetYBox, pf.privateSizeBox
        )

        local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
        local AS = UISpec and UISpec.Auras2
        if AS and AS.copyDropdowns and AS.copyDropdowns.aura then
            MSUF_EM_UI_BuildCopyDropdown(pf, AS.copyDropdowns.aura)
        end

        local function MSUF_A2_GetAuraCopyLabel(key)
            if key == "player" then return "Player" end
            if key == "target" then return "Target" end
            if key == "focus" then return "Focus" end
            if type(key) == "string" then
                local n = key:match("^boss(%d+)$")
                if n then return ("Boss %s"):format(n) end
            end
            return tostring(key or "")
        end

        local function MSUF_A2_IsBossAuraKey(key)
            return (type(key) == "string") and key:match("^boss%d+$")
        end

        local function MSUF_A2_CopyAuraLayout(srcKey, dstKey)
            if not srcKey or not dstKey or srcKey == dstKey then return end
            MSUF_EM_EnsureDB()
            if not MSUF_DB or not MSUF_DB.auras2 then return end

            local a2db = MSUF_DB.auras2
            a2db.shared = a2db.shared or {}
            a2db.perUnit = a2db.perUnit or {}

            if a2db.shared.bossEditTogether == nil then
                a2db.shared.bossEditTogether = true
            end

    -- Use current popup checkbox if present (so user can toggle and immediately copy)
            local bossTogether = (a2db.shared.bossEditTogether ~= false)
            if pf.bossTogetherCheck and pf.bossTogetherCheck.IsShown and pf.bossTogetherCheck:IsShown() and pf.bossTogetherCheck.GetChecked then
                bossTogether = (pf.bossTogetherCheck:GetChecked() and true) or false
            end

            local srcEff = srcKey
            if MSUF_A2_IsBossAuraKey(srcKey) and bossTogether then
                srcEff = "boss1"
            end

            a2db.perUnit[srcEff] = a2db.perUnit[srcEff] or {}
            local srcConf = a2db.perUnit[srcEff]
            srcConf.layout = srcConf.layout or {}
            local srcLay = srcConf.layout

    -- compute effective source values (falls back to shared)
            local function eff(v, fallback)
                if v ~= nil then return v end
                return fallback
            end

            -- Fields to copy: { layoutKey, sharedFallback }
            -- Note: Copy does NOT copy position offsets (offsetX/offsetY)
            local COPY_FIELDS = {
                { "iconSize", 26 }, { "spacing", 2 }, { "perRow", 12 }, { "buffOffsetY", 30 },
                { "stackTextSize", 14 }, { "cooldownTextSize", 14 },
                { "buffGroupOffsetX", 0 }, { "buffGroupOffsetY", 0 }, { "buffGroupIconSize", 26 },
                { "debuffGroupOffsetX", 0 }, { "debuffGroupOffsetY", 0 }, { "debuffGroupIconSize", 26 },
                { "privateOffsetX", 0 }, { "privateOffsetY", 0 }, { "privateSize", 26 },
            }
            -- Read effective source values
            local srcVals = {}
            for _, f in ipairs(COPY_FIELDS) do
                srcVals[f[1]] = eff(srcLay[f[1]], a2db.shared[f[1]] or f[2])
            end
            -- Conditional fields (only copy if source has them)
            local sCdOffX = (srcLay.cooldownTextOffsetX ~= nil) and srcLay.cooldownTextOffsetX or a2db.shared.cooldownTextOffsetX
            local sCdOffY = (srcLay.cooldownTextOffsetY ~= nil) and srcLay.cooldownTextOffsetY or a2db.shared.cooldownTextOffsetY

            local dstKeys
            if MSUF_A2_IsBossAuraKey(dstKey) and bossTogether then
                dstKeys = { "boss1","boss2","boss3","boss4","boss5" }
            else
                dstKeys = { dstKey }
            end

            for _, k in ipairs(dstKeys) do
                a2db.perUnit[k] = a2db.perUnit[k] or {}
                local dc = a2db.perUnit[k]
                dc.layout = dc.layout or {}
                dc.overrideLayout = true
                for _, f in ipairs(COPY_FIELDS) do
                    dc.layout[f[1]] = srcVals[f[1]]
                end
                if sCdOffX ~= nil then dc.layout.cooldownTextOffsetX = sCdOffX end
                if sCdOffY ~= nil then dc.layout.cooldownTextOffsetY = sCdOffY end
                dc.layout.width = nil
                dc.layout.height = nil
                if type(_G.MSUF_Auras2_RefreshUnit) == "function" then
                    _G.MSUF_Auras2_RefreshUnit(k)
                end
            end
        end

        local function MSUF_A2_RefreshCopyAuraDropdown()
            if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then return end
            if not pf or not pf.copyAuraDrop or not pf.copyAuraLabel then return end
            pf.copyAuraLabel:Show()
            pf.copyAuraDrop:Show()

            local srcKey = pf.unit or "target"
            local bossTogether = true
            if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.shared then
                if MSUF_DB.auras2.shared.bossEditTogether == nil then
                    MSUF_DB.auras2.shared.bossEditTogether = true
                end
                bossTogether = (MSUF_DB.auras2.shared.bossEditTogether ~= false)
            end
            if pf.bossTogetherCheck and pf.bossTogetherCheck.IsShown and pf.bossTogetherCheck:IsShown() and pf.bossTogetherCheck.GetChecked then
                bossTogether = (pf.bossTogetherCheck:GetChecked() and true) or false
            end

            local allKeys = { "player","target","focus","boss1","boss2","boss3","boss4","boss5" }
            local filtered = {}
            for _, k in ipairs(allKeys) do
                if k ~= srcKey and not (MSUF_A2_IsBossAuraKey(srcKey) and bossTogether and MSUF_A2_IsBossAuraKey(k)) then
                    filtered[#filtered + 1] = k
                end
            end

            MSUF_EM_InitCopyDropdown(pf.copyAuraDrop, "Copy settings to...",
                function()
                    local items = {}
                    for _, k in ipairs(filtered) do
                        items[#items + 1] = { value = k, text = MSUF_A2_GetAuraCopyLabel(k) }
                    end
                    return items
                end,
                function(dstKey)
                    if pf._msufAuras2Apply then pf._msufAuras2Apply() end
                    MSUF_A2_CopyAuraLayout(srcKey, dstKey)
                end
            )
        end

        pf.RefreshCopyAuraDropdown = MSUF_A2_RefreshCopyAuraDropdown
        local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
        local AS = UISpec and UISpec.Auras2

        local okayBtn, cancelBtn = MSUF_EM_UI_BuildFooterButtons(pf, (AS and AS.footer) or nil)
    -- Builder returns (okBtn, cancelBtn, menuBtn). Auras2 has no menu.
        if cancelBtn then
            if MSUF_EM_ForceWhiteButtonText then MSUF_EM_ForceWhiteButtonText(cancelBtn) end
            cancelBtn:SetScript('OnClick', function()
                MSUF_EM_ClearFocusOnBoxes(
                pf.spacingBox,
                pf.stackTextSizeBox, pf.stackTextOffsetXBox, pf.stackTextOffsetYBox,
                pf.cooldownTextSizeBox, pf.cooldownTextOffsetXBox, pf.cooldownTextOffsetYBox,
                pf.buffGroupOffsetXBox, pf.buffGroupOffsetYBox, pf.buffGroupIconSizeBox,
                pf.debuffGroupOffsetXBox, pf.debuffGroupOffsetYBox, pf.debuffGroupIconSizeBox,
                pf.privateOffsetXBox, pf.privateOffsetYBox, pf.privateSizeBox
                )
                pf:Hide()
        end)
        end

        if okayBtn then
            if MSUF_EM_ForceWhiteButtonText then MSUF_EM_ForceWhiteButtonText(okayBtn) end
            okayBtn:SetScript('OnClick', function()
                Apply()
                pf:Hide()
        end)
        end
        pf.cancelBtn = cancelBtn
        pf.okayBtn = okayBtn

        pf._msufAuras2Apply = Apply

    -- Snap-safe dirty tracking: only apply fields the user actually changed.
    -- This prevents mouse-dragged movers from being overwritten by stale popup values.
        if not pf.__msufA2DirtyTracking then
            pf.__msufA2DirtyTracking = true
            pf._msufA2Dirty = pf._msufA2Dirty or {}

            local DIRTY_KEYS = {
            "spacing","stackTextSize","stackTextOffsetX","stackTextOffsetY",
            "cooldownTextSize","cooldownTextOffsetX","cooldownTextOffsetY",
            "buffGroupOffsetX","buffGroupOffsetY","buffGroupIconSize",
            "debuffGroupOffsetX","debuffGroupOffsetY","debuffGroupIconSize",
            "privateOffsetX","privateOffsetY","privateSize",
            }

            local function MarkDirty(key)
                if not pf._msufA2Dirty then pf._msufA2Dirty = {} end
                pf._msufA2Dirty[key] = true
            end

            for _, key in ipairs(DIRTY_KEYS) do
                local box = pf[key.."Box"]
                if box and box.HookScript then
                    box:HookScript("OnTextChanged", function(self, userInput)
                        if userInput and not pf._msufAuras2PopupSyncing and not pf._msufAuras2PopupApplying then
                            MarkDirty(key)
                        end
                end)
            end

            local function Wrap(btn)
                if not btn or not btn.GetScript or not btn.SetScript or btn.__msufA2DirtyWrapped then return end
                btn.__msufA2DirtyWrapped = true
                local orig = btn:GetScript("OnClick")
                btn:SetScript("OnClick", function(self, ...)
                    if not pf._msufAuras2PopupSyncing and not pf._msufAuras2PopupApplying then
                        MarkDirty(key)
                    end
                    if orig then orig(self, ...) end
            end)
        end
        Wrap(pf[key.."Minus"])
        Wrap(pf[key.."Plus"])
        end

        -- Keep popup values visually synced with mouse-drag while Edit Mode is open.
        pf:HookScript("OnShow", function(self)
            self._msufA2Dirty = {}
            if self._msufA2SyncTicker then
                self._msufA2SyncTicker:Cancel()
                self._msufA2SyncTicker = nil
            end
            if C_Timer and C_Timer.NewTicker then
                self._msufA2SyncTicker = C_Timer.NewTicker(0.15, function()
                    if not self or not self:IsShown() then return end
                    if type(_G.MSUF_SyncAuras2PositionPopup) == "function" then
                        _G.MSUF_SyncAuras2PositionPopup(self.unit)
                    end
            end)
        end
        end)

        pf:HookScript("OnHide", function(self)
            if self._msufA2SyncTicker then
                self._msufA2SyncTicker:Cancel()
                self._msufA2SyncTicker = nil
            end
        end)
    end
    -- Ensure Midnight EditMode styling is applied immediately (fixes: first-open shows default UI style)
    if pf.HookScript and not pf.__msufAuraPopupStyleHooked then
        pf.__msufAuraPopupStyleHooked = true
        pf:HookScript("OnShow", function(self)
            local Style = _G.MSUF_NS and _G.MSUF_NS.Style
            if Style and Style.SkinEditModePopupFrame then
                pcall(Style.SkinEditModePopupFrame, self)
            elseif Style and Style.ScanAndSkinEditMode then
                pcall(Style.ScanAndSkinEditMode)
            end
        end)
    end

    return pf
end

function _G.MSUF_SyncAuras2PositionPopup(unit)
    local pf = _G.MSUF_Auras2PositionPopup
    if not pf or not pf.IsShown or not pf:IsShown() then
        return
    end

    local popupUnit = pf.unit or unit
    if not popupUnit then
        return
    end
    if unit and pf.unit and unit ~= pf.unit then
        return
    end

    MSUF_EM_EnsureDB()
    if not MSUF_DB or not MSUF_DB.auras2 then
        return
    end

    if pf._msufAuras2PopupApplying or _G.MSUF__Auras2PopupApplying then
        return
    end
    pf._msufAuras2PopupSyncing = true

    local a2 = MSUF_DB.auras2
    local shared = a2.shared or {}

local isBoss = (type(popupUnit) == 'string') and popupUnit:match('^boss%d+$')
    local popupUnitEff = popupUnit
    if isBoss and shared.bossEditTogether ~= false then
        popupUnitEff = 'boss1'
    end

if shared.bossEditTogether == nil then
    shared.bossEditTogether = true
end

if pf.bossTogetherCheck then
    if isBoss then
        pf.bossTogetherCheck:Show()
        if pf.bossTogetherCheck.SetChecked then
            pf.bossTogetherCheck:SetChecked(shared.bossEditTogether ~= false)
        end
    else
        pf.bossTogetherCheck:Hide()
    end
end

-- Re-anchor the Stack Text Size row depending on boss toggle visibility
local spacingAnchor = pf.spacingRow or pf.spacingLabel
if pf.stackTextSizeLabel and spacingAnchor and pf.bossTogetherCheck then
    pf.stackTextSizeLabel:ClearAllPoints()
    if isBoss and pf.bossTogetherCheck.IsShown and pf.bossTogetherCheck:IsShown() then
        pf.stackTextSizeLabel:SetPoint('TOPLEFT', pf.bossTogetherCheck, 'BOTTOMLEFT', 0, -8)
    else
        pf.stackTextSizeLabel:SetPoint('TOPLEFT', spacingAnchor, 'BOTTOMLEFT', 0, -8)
    end
end

    local uconf = (a2.perUnit and a2.perUnit[popupUnitEff]) or {}
    local lay = uconf.layout or {}

    local iconSize = (uconf.overrideLayout and lay.iconSize ~= nil) and lay.iconSize or (shared.iconSize or 26)
    local spacing  = (uconf.overrideLayout and lay.spacing  ~= nil) and lay.spacing  or (shared.spacing  or 2)

    local stackTextSize = (uconf.overrideLayout and lay.stackTextSize ~= nil) and lay.stackTextSize or (shared.stackTextSize or 14)
    local cooldownTextSize = (uconf.overrideLayout and lay.cooldownTextSize ~= nil) and lay.cooldownTextSize or (shared.cooldownTextSize or 14)
    local cooldownTextOffsetX = (uconf.overrideLayout and lay.cooldownTextOffsetX ~= nil) and lay.cooldownTextOffsetX or (shared.cooldownTextOffsetX or 0)
    local cooldownTextOffsetY = (uconf.overrideLayout and lay.cooldownTextOffsetY ~= nil) and lay.cooldownTextOffsetY or (shared.cooldownTextOffsetY or 0)
    local stackTextOffsetX = (uconf.overrideLayout and lay.stackTextOffsetX ~= nil) and lay.stackTextOffsetX or (shared.stackTextOffsetX or 0)
    local stackTextOffsetY = (uconf.overrideLayout and lay.stackTextOffsetY ~= nil) and lay.stackTextOffsetY or (shared.stackTextOffsetY or 0)
    -- Private Auras (independent offsets/sizing)
    local privOffX = (uconf.overrideLayout and lay.privateOffsetX ~= nil) and lay.privateOffsetX or (shared.privateOffsetX or 0)
    local privOffY = (uconf.overrideLayout and lay.privateOffsetY ~= nil) and lay.privateOffsetY or (shared.privateOffsetY or 0)
    local privSize = (uconf.overrideLayout and lay.privateSize ~= nil) and lay.privateSize or (shared.privateSize or iconSize)

    -- Buffs / Debuffs (independent offsets/sizing)
    local buffGroupOffsetX = (uconf.overrideLayout and lay.buffGroupOffsetX ~= nil) and lay.buffGroupOffsetX or (shared.buffGroupOffsetX or 0)
    local buffGroupOffsetY = (uconf.overrideLayout and lay.buffGroupOffsetY ~= nil) and lay.buffGroupOffsetY or (shared.buffGroupOffsetY or 0)
    local buffGroupIconSize = (uconf.overrideLayout and lay.buffGroupIconSize ~= nil) and lay.buffGroupIconSize or (shared.buffGroupIconSize or iconSize)

    local debuffGroupOffsetX = (uconf.overrideLayout and lay.debuffGroupOffsetX ~= nil) and lay.debuffGroupOffsetX or (shared.debuffGroupOffsetX or 0)
    local debuffGroupOffsetY = (uconf.overrideLayout and lay.debuffGroupOffsetY ~= nil) and lay.debuffGroupOffsetY or (shared.debuffGroupOffsetY or 0)
    local debuffGroupIconSize = (uconf.overrideLayout and lay.debuffGroupIconSize ~= nil) and lay.debuffGroupIconSize or (shared.debuffGroupIconSize or iconSize)

    iconSize = tonumber(iconSize) or 26
    spacing  = tonumber(spacing)  or 2
    stackTextSize = tonumber(stackTextSize) or 14
    cooldownTextSize = tonumber(cooldownTextSize) or 14

    buffGroupIconSize = tonumber(buffGroupIconSize) or iconSize
    debuffGroupIconSize = tonumber(debuffGroupIconSize) or iconSize
    privSize = tonumber(privSize) or iconSize

    stackTextOffsetX = MSUF_SanitizePopupOffset(tonumber(stackTextOffsetX) or 0, 0)
    stackTextOffsetY = MSUF_SanitizePopupOffset(tonumber(stackTextOffsetY) or 0, 0)
    cooldownTextOffsetX = MSUF_SanitizePopupOffset(tonumber(cooldownTextOffsetX) or 0, 0)
    cooldownTextOffsetY = MSUF_SanitizePopupOffset(tonumber(cooldownTextOffsetY) or 0, 0)

    buffGroupOffsetX = MSUF_SanitizePopupOffset(tonumber(buffGroupOffsetX) or 0, 0)
    buffGroupOffsetY = MSUF_SanitizePopupOffset(tonumber(buffGroupOffsetY) or 0, 0)
    debuffGroupOffsetX = MSUF_SanitizePopupOffset(tonumber(debuffGroupOffsetX) or 0, 0)
    debuffGroupOffsetY = MSUF_SanitizePopupOffset(tonumber(debuffGroupOffsetY) or 0, 0)

    privOffX = MSUF_SanitizePopupOffset(tonumber(privOffX) or 0, 0)
    privOffY = MSUF_SanitizePopupOffset(tonumber(privOffY) or 0, 0)
    privSize = tonumber(privSize) or iconSize
    privSize = math.max(10, math.min(80, privSize))
    if pf.spacingBox and not pf.spacingBox:HasFocus() then
        pf.spacingBox:SetText(tostring(math.floor(spacing + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['spacing'] = nil end
    end
    if pf.stackTextSizeBox and not pf.stackTextSizeBox:HasFocus() then
        pf.stackTextSizeBox:SetText(tostring(math.floor(stackTextSize + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['stackTextSize'] = nil end
    end
    if pf.stackTextOffsetXBox and not pf.stackTextOffsetXBox:HasFocus() then
        pf.stackTextOffsetXBox:SetText(tostring(math.floor(stackTextOffsetX + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['stackTextOffsetX'] = nil end
    end
    if pf.stackTextOffsetYBox and not pf.stackTextOffsetYBox:HasFocus() then
        pf.stackTextOffsetYBox:SetText(tostring(math.floor(stackTextOffsetY + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['stackTextOffsetY'] = nil end
    end
    if pf.cooldownTextSizeBox and not pf.cooldownTextSizeBox:HasFocus() then
        pf.cooldownTextSizeBox:SetText(tostring(math.floor(cooldownTextSize + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['cooldownTextSize'] = nil end
    end

    if pf.cooldownTextOffsetXBox and not pf.cooldownTextOffsetXBox:HasFocus() then
        pf.cooldownTextOffsetXBox:SetText(tostring(math.floor(cooldownTextOffsetX + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['cooldownTextOffsetX'] = nil end
    end
    if pf.cooldownTextOffsetYBox and not pf.cooldownTextOffsetYBox:HasFocus() then
        pf.cooldownTextOffsetYBox:SetText(tostring(math.floor(cooldownTextOffsetY + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['cooldownTextOffsetY'] = nil end
    end

    if pf.buffGroupOffsetXBox and not pf.buffGroupOffsetXBox:HasFocus() then
        pf.buffGroupOffsetXBox:SetText(tostring(buffGroupOffsetX))

        if pf._msufA2Dirty then pf._msufA2Dirty['buffGroupOffsetX'] = nil end
    end
    if pf.buffGroupOffsetYBox and not pf.buffGroupOffsetYBox:HasFocus() then
        pf.buffGroupOffsetYBox:SetText(tostring(buffGroupOffsetY))

        if pf._msufA2Dirty then pf._msufA2Dirty['buffGroupOffsetY'] = nil end
    end
    if pf.buffGroupIconSizeBox and not pf.buffGroupIconSizeBox:HasFocus() then
        pf.buffGroupIconSizeBox:SetText(tostring(math.floor(buffGroupIconSize + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['buffGroupIconSize'] = nil end
    end

    if pf.debuffGroupOffsetXBox and not pf.debuffGroupOffsetXBox:HasFocus() then
        pf.debuffGroupOffsetXBox:SetText(tostring(debuffGroupOffsetX))

        if pf._msufA2Dirty then pf._msufA2Dirty['debuffGroupOffsetX'] = nil end
    end
    if pf.debuffGroupOffsetYBox and not pf.debuffGroupOffsetYBox:HasFocus() then
        pf.debuffGroupOffsetYBox:SetText(tostring(debuffGroupOffsetY))

        if pf._msufA2Dirty then pf._msufA2Dirty['debuffGroupOffsetY'] = nil end
    end
    if pf.debuffGroupIconSizeBox and not pf.debuffGroupIconSizeBox:HasFocus() then
        pf.debuffGroupIconSizeBox:SetText(tostring(math.floor(debuffGroupIconSize + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['debuffGroupIconSize'] = nil end
    end
    if pf.privateOffsetXBox and not pf.privateOffsetXBox:HasFocus() then
        pf.privateOffsetXBox:SetText(tostring(math.floor(privOffX + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['privateOffsetX'] = nil end
    end
    if pf.privateOffsetYBox and not pf.privateOffsetYBox:HasFocus() then
        pf.privateOffsetYBox:SetText(tostring(math.floor(privOffY + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['privateOffsetY'] = nil end
    end
    if pf.privateSizeBox and not pf.privateSizeBox:HasFocus() then
        pf.privateSizeBox:SetText(tostring(math.floor(privSize + 0.5)))

        if pf._msufA2Dirty then pf._msufA2Dirty['privateSize'] = nil end
    end
    if pf.privatePreviewCheck and pf.privatePreviewCheck.SetChecked then
        pf.privatePreviewCheck:SetChecked((shared.highlightPrivateAuras == true) and true or false)
    end
    if pf.RefreshCopyAuraDropdown then
        pf.RefreshCopyAuraDropdown()
    end
    pf._msufAuras2PopupSyncing = false
end

function _G.MSUF_OpenAuras2PositionPopup(unit, parent)
    -- Wired up by Auras 2.0: Target, Focus, Boss1-5 (helper is unit-agnostic).
    if not unit then
        return
    end
    if unit ~= 'player' and unit ~= 'target' and unit ~= 'focus' and not (type(unit) == 'string' and unit:match('^boss%d+$')) then
        return
    end
    if not _G.MSUF_UnitEditModeActive then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        print('|cffffd700MSUF:|r Position/GrÃ‚Â¶ÃƒÆ’Ã†â€™Ãƒâ€¦Ã‚Â¸e kann im Kampf nicht geÃ‚Â¤ndert werden.')
        return
    end

    if not MSUF_EM_EnsureDB() then
        return
    end
    if not MSUF_DB then
        return
    end

    MSUF_DB.auras2 = MSUF_DB.auras2 or {}
    local a2 = MSUF_DB.auras2
    a2.shared = a2.shared or {}
    a2.perUnit = a2.perUnit or {}
    a2.perUnit[unit] = a2.perUnit[unit] or {}
    a2.perUnit[unit].layout = a2.perUnit[unit].layout or {}

    local pf = _G.MSUF_A2_EnsureAuraPositionPopup()

    local desiredParent = parent or UIParent
    local needReposition = true
    if pf.IsShown and pf:IsShown() then
        if pf._msufLastA2Unit == unit and pf._msufLastA2Parent == desiredParent then
            needReposition = false
        end
    end

    pf.unit = unit
    pf.parent = parent
    pf._msufLastA2Unit = unit
    pf._msufLastA2Parent = desiredParent

    if pf.title and pf.title.SetText then
        local suffix = MSUF_A2_GetAuraPopupTitleSuffix(unit)
        pf.title:SetText('MSUF Edit  ' .. (suffix or 'Aura'))
    end

    if needReposition and type(MSUF_PositionPopupSmart) == 'function' then
        MSUF_PositionPopupSmart(pf, desiredParent, 200)
    end

pf:Show()

    -- Force correct popup skin even if this is the first popup opened this session.
    local Style = _G.MSUF_NS and _G.MSUF_NS.Style
    if Style and Style.SkinEditModePopupFrame then
        pcall(Style.SkinEditModePopupFrame, pf)
    elseif Style and Style.ScanAndSkinEditMode then
        pcall(Style.ScanAndSkinEditMode)
    end

    if pf.RefreshCopyAuraDropdown then
        pf.RefreshCopyAuraDropdown()
    end

    if type(_G.MSUF_SyncAuras2PositionPopup) == 'function' then
        _G.MSUF_SyncAuras2PositionPopup(unit)
    end
end

-- Arrow-key nudging (Edit Mode only)
-- Uses override bindings for UP/DOWN/LEFT/RIGHT -> click hidden direction buttons.
-- P0: Never call SetPropagateKeyboardInput(), never capture WASD, always release on Exit.
-- IMPORTANT: SetOverrideBindingClick's "clickButton" param MUST be a real mouse button name.
-- Note: Uses globals deliberately to avoid hitting the "200 locals" limit in large files.
local MSUF_EM_GetCastbarOffsetKeys -- castbar offset key helper (used by snap + arrow-key nudging)

if not _G.MSUF_EnableArrowKeyNudge then
function _G.MSUF_EnableArrowKeyNudge(enable)
        -- If a previous build created a fullscreen keyboard-catcher frame, hard-disable it.
        if _G.MSUF_ArrowKeyNudgeFrame then
            local old = _G.MSUF_ArrowKeyNudgeFrame
            if old.EnableKeyboard then old:EnableKeyboard(false) end
            if old.Hide then old:Hide() end
            old.__msufHardKill = true
        end

        -- If a previous build created the single "direction token" button, hide it (we use 4 real click buttons now).
        if _G.MSUF_ArrowKeyNudgeButton and _G.MSUF_ArrowKeyNudgeButton.Hide then
            _G.MSUF_ArrowKeyNudgeButton:Hide()
        end

        if not _G.MSUF_ArrowKeyBindOwner then
            local owner = CreateFrame("Frame", "MSUF_ArrowKeyBindOwner", UIParent)
            _G.MSUF_ArrowKeyBindOwner = owner
            owner:Hide()
            owner.__msufPendingClear = false
            owner:SetScript("OnEvent", function(self, event)
                if event == "PLAYER_REGEN_ENABLED" then
                    if self.__msufPendingClear then
                        self.__msufPendingClear = false
                        if ClearOverrideBindings then
                            ClearOverrideBindings(self)
                        end
                    end
                    if self.UnregisterEvent then
                        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    end
                end
            end)
        end

    local function GetStep()
        local step = 1
        if IsAltKeyDown and IsAltKeyDown() then
            if MSUF_GetCurrentGridStep then
                step = MSUF_GetCurrentGridStep()
            else
                step = 20
            end
        elseif IsControlKeyDown and IsControlKeyDown() then
            step = 10
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            step = 5
        end
        step = tonumber(step) or 1
        if step < 1 then step = 1 end
        return step
    end

    local function NudgeTarget(dx, dy)
        if not MSUF_UnitEditModeActive then return end
        if InCombatLockdown and InCombatLockdown() then return end
        if IsTyping and IsTyping() then return end
        if not MSUF_EM_EnsureDB() then return end
        if not MSUF_DB then return end

        -- Prefer the currently open popup (castbar > unit), otherwise current edit unit key
        local castPF = MSUF_CastbarPositionPopup
        if castPF and castPF.IsShown and castPF:IsShown() and castPF.unit then
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            local unit = tostring(castPF.unit)
            local s = GetStep()
            local ndx, ndy = dx * s, dy * s

            local xKey, yKey
            if MSUF_EM_GetCastbarOffsetKeys then
                xKey, yKey = MSUF_EM_GetCastbarOffsetKeys(unit)
            end
            if not xKey or not yKey then return end

            g[xKey] = math.floor(((tonumber(g[xKey]) or 0) + ndx) + 0.5)
            g[yKey] = math.floor(((tonumber(g[yKey]) or 0) + ndy) + 0.5)

            MSUF_EditMode_RequestCastbarApply(unit)
            if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                _G.MSUF_SyncCastbarPositionPopup(unit)
            end
            if MSUF_UpdateCastbarEditInfo then
                MSUF_UpdateCastbarEditInfo()
            end
            return
        end

        local unitPF = MSUF_PositionPopup
        local key = MSUF_CurrentEditUnitKey
        if unitPF and unitPF.IsShown and unitPF:IsShown() and unitPF.unit and GetConfigKeyForUnit then
            key = GetConfigKeyForUnit(unitPF.unit) or key
        end
        if not key then return end

        local conf = MSUF_DB[key]
        if not conf then return end

        local s = GetStep()
        local ndx, ndy = dx * s, dy * s
        conf.offsetX = math.floor(((tonumber(conf.offsetX) or 0) + ndx) + 0.5)
        conf.offsetY = math.floor(((tonumber(conf.offsetY) or 0) + ndy) + 0.5)

        MSUF_EditMode_RequestUnitApply(key)
        if type(_G.MSUF_SyncUnitPositionPopup) == "function" then
            _G.MSUF_SyncUnitPositionPopup(key, conf)
        end
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end
    end

    local function EnsureButtons()
        if _G.MSUF_ArrowKeyNudgeButtons then
            return _G.MSUF_ArrowKeyNudgeButtons
        end
        local t = {}
        _G.MSUF_ArrowKeyNudgeButtons = t
        local function Make(dir, dx, dy)
            local name = "MSUF_ArrowKeyNudgeButton_" .. dir
            local b = CreateFrame("Button", name, UIParent)
            t[dir] = b
            b:Hide()
            if b.RegisterForClicks then
                b:RegisterForClicks("AnyUp")
            end
            b:SetScript("OnClick", function()
                MSUF_SafeCall("ArrowKey:" .. dir, function()
                    NudgeTarget(dx, dy)
                end)
            end)
        end
        Make("UP", 0, 1)
        Make("DOWN", 0, -1)
        Make("LEFT", -1, 0)
        Make("RIGHT", 1, 0)
        return t
    end

        if enable then
            -- Feature disabled due to repeated errors
            if MSUF__SafeFeatureDisabled and MSUF__SafeFeatureDisabled["arrowKeys"] then
                return
            end

            local owner = _G.MSUF_ArrowKeyBindOwner
            if not owner then return end
            owner:Show()

            -- Ensure no stuck editbox focus blocks movement keys when entering Edit Mode
            MSUF_EM_ClearKeyboardFocus()

            -- Apply override bindings only out of combat. In combat we keep them as-is and nudging does nothing anyway.
            if InCombatLockdown and InCombatLockdown() then
                return
            end

            if ClearOverrideBindings then
                ClearOverrideBindings(owner)
            end

            local btns = EnsureButtons()
            if SetOverrideBindingClick and btns then
                -- clickButton MUST be a real mouse button ("LeftButton"). Direction is encoded by using 4 distinct buttons.
                SetOverrideBindingClick(owner, false, "UP", btns.UP:GetName(), "LeftButton")
                SetOverrideBindingClick(owner, false, "DOWN", btns.DOWN:GetName(), "LeftButton")
                SetOverrideBindingClick(owner, false, "LEFT", btns.LEFT:GetName(), "LeftButton")
                SetOverrideBindingClick(owner, false, "RIGHT", btns.RIGHT:GetName(), "LeftButton")
            end

            MSUF_EM_SetArrowBindingsActive(true)

            -- One-time per-session tip (if available)
            if _G.MSUF_EditMode_ShowArrowKeyTip then
                _G.MSUF_EditMode_ShowArrowKeyTip()
            end
        else
            local owner = _G.MSUF_ArrowKeyBindOwner
            if owner then
                -- Always release bindings. If in combat, defer the clear.
                if InCombatLockdown and InCombatLockdown() then
                    owner.__msufPendingClear = true
                    if owner.RegisterEvent then
                        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
                    end
                else
                    if ClearOverrideBindings then
                        ClearOverrideBindings(owner)
                    end
                end
                owner:Hide()
            end

            MSUF_EM_SetArrowBindingsActive(false)
        end
    end
end

local MSUF_BlizzardEditHooked = false

-- Popup helpers (keep open during edits, but close on Edit Mode exit)
local function MSUF_CloseAllPositionPopups()
    -- Phase 3A: if popup registry exists, prefer it (covers any future popups too).
    if Edit and Edit.Popups and type(Edit.Popups.CloseAll) == "function" then
        Edit.Popups.CloseAll()
        return
    end

    if MSUF_PositionPopup and MSUF_PositionPopup.Hide then
        MSUF_PositionPopup:Hide()
    end
    if MSUF_CastbarPositionPopup and MSUF_CastbarPositionPopup.Hide then
        MSUF_CastbarPositionPopup:Hide()
    end
    -- Tooltip Edit Mode drag preview
    if type(_G.MSUF_Tooltip_HideEditPreview) == "function" then
        _G.MSUF_Tooltip_HideEditPreview()
    end
    if GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
    end
    MSUF_EM_SetPopupOpen(false)
end

-- Phase 2 refactor: deterministic Exit/Cancel cleanup order
-- Single exit path for MSUF Edit Mode to avoid state drift / stuck popups / stuck bindings.
-- This MUST be safe in combat: secure visibility drivers are deferred by MSUF_EditMode_RequestVisibilityDrivers().
local function MSUF_EditMode_ExitDeterministic(source, opts)
    source = tostring(source or "exit")
    opts = opts or {}
    local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false

    -- Optional: apply pending changes once before exiting (ooc only by default).
    if opts.flushPending and type(MSUF_EditMode_FlushPendingApplies) == "function" then
        if (not inCombat) or opts.flushInCombat then
            MSUF_SafeCall("Exit:FlushPending:" .. source, MSUF_EditMode_FlushPendingApplies)
        end
    end

    -- Flip state first; this triggers combat-safe boss preview soft-hide via MSUF_EM_SetActive().
    MSUF_EM_SetActive(false, nil)

    -- Ensure boss castbar preview is hidden immediately (safe even in combat).
    if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
        MSUF_SafeCall("Exit:BossCastbarPreview:" .. source, _G.MSUF_UpdateBossCastbarPreview)
    end

    -- Always release arrow key override bindings on exit (deferred if in combat by the binding owner).
    if _G and _G.MSUF_EnableArrowKeyNudge then
        MSUF_SafeCall("Exit:ArrowKeysOff:" .. source, _G.MSUF_EnableArrowKeyNudge, false)
    end

    -- Clear selection + sizing flags.
    MSUF_CurrentEditUnitKey = nil
    MSUF_EditModeSizing = false

    -- Close any open popups (safe to hide frames; non-protected).
    MSUF_SafeCall("Exit:ClosePopups:" .. source, MSUF_CloseAllPositionPopups)

    -- Visibility drivers (secure): always go through combat gate.
    if type(MSUF_EditMode_RequestVisibilityDrivers) == "function" then
        MSUF_EditMode_RequestVisibilityDrivers(false)
    end

    if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
        MSUF_SafeCall("Exit:SyncCastbarEdit:" .. source, MSUF_SyncCastbarEditModeWithUnitEdit)
    end
    if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        MSUF_SafeCall("Exit:SyncBossPreview:" .. source, MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end

    if MSUF_GridFrame and MSUF_GridFrame.Hide then
        MSUF_GridFrame:Hide()
    end

    if MSUF_UpdateEditModeVisuals then
        MSUF_SafeCall("Exit:Visuals:" .. source, MSUF_UpdateEditModeVisuals)
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_SafeCall("Exit:Info:" .. source, MSUF_UpdateEditModeInfo)
    end

    -- Hard teardown last (kill timers/listeners) so Edit Mode costs ~0 after exit.
    MSUF_EditMode_HardTeardown()
end

-- BCDM Cooldown Manager handoff notice (Edit Mode)
-- Shows a prominent one-time-per-session warning when:
--   1) BetterCooldownManager is loaded
--   2) BCDM CooldownManager skinning is enabled (CooldownManager.Enable == true)
--   3) MSUF is anchored to the Blizzard Cooldown Manager (MSUF_DB.general.anchorToCooldown == true)
-- This intentionally does NOT try to move the Blizzard CDM (BCDM owns it when skinning is enabled).

local MSUF_EM_BCDMNotice_ShownThisSession = false
local MSUF_EM_BCDMNotice_PendingCombat = false
local MSUF_EM_BCDMNotice_EventFrame

local function MSUF_EM_IsBCDMAddonLoaded()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded("BetterCooldownManager") and true or false
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded("BetterCooldownManager") and true or false
    end
    return false
end

local function MSUF_EM_GetBCDMActiveProfileTable()
    local sv = _G.BCDMDB
    if type(sv) ~= "table" then
        return nil
    end

    local profileName

    -- Respect BCDM global profile mode if present
    if sv.global and sv.global.UseGlobalProfile and sv.global.GlobalProfile then
        profileName = sv.global.GlobalProfile
    end

    if not profileName and type(sv.profileKeys) == "table" then
        local name = UnitName and UnitName("player")
        local realm = GetRealmName and GetRealmName()
        if name and realm then
            local key = name .. " - " .. realm
            profileName = sv.profileKeys[key]
        end
    end

    if not profileName then
        profileName = "Default"
    end

    if type(sv.profiles) ~= "table" then
        return nil
    end

    return sv.profiles[profileName]
end

local function MSUF_EM_IsBCDMHandoffNoticeSuppressed()
    -- Persisted "never show again" toggle (stored in MSUF_DB.general).
    MSUF_EM_EnsureDB()
    local g = MSUF_DB and MSUF_DB.general
    return (type(g) == "table" and g.suppressBCDMHandoffNotice == true) and true or false
end

local function MSUF_EM_ShouldShowBCDMHandoffNotice()
    if MSUF_EM_BCDMNotice_ShownThisSession then
        return false
    end

    -- User requested: "never show again"
    if MSUF_EM_IsBCDMHandoffNoticeSuppressed() then
        return false
    end

    -- Show whenever BetterCooldownManager is loaded.
    -- Reason: BCDM can take ownership of the Blizzard Cooldown Manager positioning (even if Edit Mode shows it as movable),
    -- which can make anchored frames appear to "snap back" or not persist their position via the Blizzard manager.
    return MSUF_EM_IsBCDMAddonLoaded()
end

local function MSUF_EM_EnsureBCDMNoticePopupDialog()
    if not StaticPopupDialogs then
        return
    end
    if StaticPopupDialogs["MSUF_BCDM_CDM_HANDOFF_NOTICE"] then
        return
    end

    StaticPopupDialogs["MSUF_BCDM_CDM_HANDOFF_NOTICE"] = {
        text = [[|cffff4444BCDM detected: BetterCooldownManager controls Blizzard Cooldown Manager positioning.|r

BCDM can override Edit Mode movement / saved position for the Blizzard Cooldown Manager, so frames anchored to it may appear to "snap back".

To move the Cooldown Manager, use: |cff00ff00/bcdm|r -> Cooldown Manager -> Layout.
(Edit Mode may still let you drag it, but BCDM will apply its own X/Y.)

MSUF will keep anchoring to the Cooldown Manager.]],
        button1 = OKAY,
        button2 = "Never show again",
        OnCancel = function(self, data, reason)
            -- Only treat an explicit click on the 'Never show again' button as opt-out.
            -- (ESC/close should NOT permanently disable the notice.)
            if reason ~= "clicked" then
                return
            end
            MSUF_EM_EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general.suppressBCDMHandoffNotice = true
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

local function MSUF_EM_ShowBCDMHandoffNotice_Now()
    if MSUF_EM_BCDMNotice_ShownThisSession then
        return
    end
    if not MSUF_EM_ShouldShowBCDMHandoffNotice() then
        return
    end

    -- Avoid showing UI popups in combat; defer until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        MSUF_EM_BCDMNotice_PendingCombat = true
        if not MSUF_EM_BCDMNotice_EventFrame then
            local f = CreateFrame("Frame")
            MSUF_EM_BCDMNotice_EventFrame = f
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function()
                if not MSUF_EM_BCDMNotice_PendingCombat then
                    return
                end
                MSUF_EM_BCDMNotice_PendingCombat = false
                -- Only show if Edit Mode is still active
                if MSUF_UnitEditModeActive then
                    MSUF_SafeAfter(0, "Popup:BCDMHandoff", MSUF_EM_ShowBCDMHandoffNotice_Now)
                end
            end)
        end
        return
    end

    MSUF_EM_EnsureBCDMNoticePopupDialog()
    if StaticPopup_Show then
        MSUF_EM_BCDMNotice_ShownThisSession = true
        StaticPopup_Show("MSUF_BCDM_CDM_HANDOFF_NOTICE")
    end
end

local function MSUF_EM_ShowBCDMHandoffNoticeIfNeeded()
    if not MSUF_EM_ShouldShowBCDMHandoffNotice() then
        return
    end
    -- Defer to next tick to avoid any secure-stack weirdness during Edit Mode transitions.
    MSUF_SafeAfter(0, "Popup:BCDMHandoff", MSUF_EM_ShowBCDMHandoffNotice_Now)
end

function MSUF_SetMSUFEditModeFromBlizzard(active)
    -- Blizzard -> MSUF Edit Mode sync disabled (TEMP): MSUF runs its own standalone Edit Mode.
    do return end
    if _G and _G.MSUF_SuppressBlizzEditToMSUF then
        return
    end
    MSUF_EM_EnsureDB()
    if MSUF_DB and MSUF_DB.general and MSUF_DB.general.linkEditModes == false then
        if not active then
            -- Always close MSUF popups when Blizzard Edit Mode exits, even if modes are unlinked.
            MSUF_SafeAfter(0, "BlizzExit:ClosePopups", MSUF_CloseAllPositionPopups)
        end
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Allow a COMBAT-SAFE exit path (no SecureStateDriver calls).
        -- Entering Edit Mode in combat stays blocked.
        if active then
            return
        end
        -- active == false: continue into exit flow; visibility drivers are deferred automatically.
    end

    if active then
        if MSUF_UnitEditModeActive then
            return
        end

        MSUF_EM_SetActive(true, "player")
        MSUF_EditModeSizing = false
MSUF_EditMode_StartCombatWarningListener()
        if _G.MSUF_EnableArrowKeyNudge then _G.MSUF_EnableArrowKeyNudge(true) end
        if type(MSUF_RefreshAllUnitVisibilityDrivers)=="function" then MSUF_EditMode_RequestVisibilityDrivers(true) end
        if not MSUF_CurrentEditUnitKey then
            MSUF_CurrentEditUnitKey = "player"
        end
        MSUF_EM_GetState().unitKey = MSUF_CurrentEditUnitKey

        if type(MSUF_BeginEditModeTransaction) == "function" then
            MSUF_BeginEditModeTransaction()
        end

        if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
            MSUF_SyncCastbarEditModeWithUnitEdit()
        end
        if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            MSUF_SyncBossUnitframePreviewWithUnitEdit()
        end

        if MSUF_UpdateEditModeVisuals then
            MSUF_UpdateEditModeVisuals()
        end
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end

        -- If BetterCooldownManager is loaded, warn the user that it controls Blizzard Cooldown Manager positioning.
        MSUF_EM_ShowBCDMHandoffNoticeIfNeeded()

    else
        if not MSUF_UnitEditModeActive then
            return
        end
            -- Reset BCDM handoff notice so it shows again next time Edit Mode is entered.
            MSUF_EM_BCDMNotice_ShownThisSession = false
            MSUF_EM_BCDMNotice_PendingCombat = false

        local function _doExit()
            Edit.Flow.Exit("blizzard", { flushPending = true })
        end

        -- Taint/secure-stack guard: defer MSUF exit slightly so it runs after UIPanelManager finishes closing Blizzard Edit Mode.
        -- Use MSUF_SafeAfter so the callback can be invalidated by HardTeardown if needed.
        local delay = 0
        if _G.EditModeManagerFrame and _G.EditModeManagerFrame.IsShown and _G.EditModeManagerFrame:IsShown() then
            delay = 0.05
        end
        MSUF_SafeAfter(delay, "BlizzExit:MSUFExit", _doExit)
    end
end

-- (Snapping removed)

if type(_G.MSUF_SyncCastbarEditModeWithUnitEdit) ~= "function" then
    function _G.MSUF_SyncCastbarEditModeWithUnitEdit()
        MSUF_EM_EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then
            return
        end

        local g = MSUF_DB.general
        g.castbarPlayerPreviewEnabled = MSUF_UnitEditModeActive and true or false

        if g.castbarPlayerPreviewEnabled and type(_G.MSUF_EnsureCastbarsLoaded) == "function" then
            _G.MSUF_EnsureCastbarsLoaded("msuf_edit_mode")
        end

        if type(_G.MSUF_UpdatePlayerCastbarPreview) == "function" then
            _G.MSUF_UpdatePlayerCastbarPreview()
        end
        if type(_G.MSUF_UpdateTargetCastbarPreview) == "function" then
            _G.MSUF_UpdateTargetCastbarPreview()
        end
        if type(_G.MSUF_UpdateFocusCastbarPreview) == "function" then
            _G.MSUF_UpdateFocusCastbarPreview()
        end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
        end
    end
end

if not _G.MSUF_SetMSUFEditModeDirect then
    function _G.MSUF_SetMSUFEditModeDirect(active, unitKey)
        if InCombatLockdown and InCombatLockdown() then
            -- Entering in combat is blocked; EXIT is allowed (combat-safe), with deferred visibility driver cleanup.
            if active then
                return
            end
        end

        MSUF_EM_EnsureDB()

        if active then
            -- already active: just update selected unit if provided
            if MSUF_UnitEditModeActive then
                if unitKey then
                    MSUF_CurrentEditUnitKey = unitKey
                end
                if MSUF_UpdateEditModeVisuals then
                    MSUF_UpdateEditModeVisuals()
                end
                if MSUF_UpdateEditModeInfo then
                    MSUF_UpdateEditModeInfo()
                end
                return
            end

            MSUF_EM_SetActive(true, unitKey)
            if type(_G.MSUF_Auras2_RefreshAll) == "function" then
                _G.MSUF_Auras2_RefreshAll()
            end
MSUF_EditMode_StartCombatWarningListener()
            if _G.MSUF_EnableArrowKeyNudge then _G.MSUF_EnableArrowKeyNudge(true) end
            if unitKey then
                MSUF_CurrentEditUnitKey = unitKey
            elseif not MSUF_CurrentEditUnitKey then
                MSUF_CurrentEditUnitKey = "player"
            end
            MSUF_EM_GetState().unitKey = MSUF_CurrentEditUnitKey

            if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
                if type(MSUF_RefreshAllUnitVisibilityDrivers)=="function" then MSUF_EditMode_RequestVisibilityDrivers(true) end
            end

            if type(MSUF_BeginEditModeTransaction) == "function" then
                MSUF_BeginEditModeTransaction()
            end

            if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
                MSUF_SyncCastbarEditModeWithUnitEdit()
            end
            if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
                MSUF_SyncBossUnitframePreviewWithUnitEdit()
            end

            if MSUF_UpdateEditModeVisuals then
                MSUF_UpdateEditModeVisuals()
            end
            -- Always hide the on-frame white arrow buttons (UI cleanup).
            if MSUF_UpdateEditModeInfo then
                MSUF_UpdateEditModeInfo()
            end

            -- If BetterCooldownManager is loaded, warn the user that it controls Blizzard Cooldown Manager positioning.
            MSUF_EM_ShowBCDMHandoffNoticeIfNeeded()

        else
            if not MSUF_UnitEditModeActive then
                return
            end
            Edit.Flow.Exit("direct", { flushPending = true })
            if type(_G.MSUF_Auras2_RefreshAll) == "function" then
                _G.MSUF_Auras2_RefreshAll()
            end
        end
    end
end

if not MSUF_HookBlizzardEditMode then
MSUF_HookBlizzardEditMode = function()
    -- Disabled: Blizzard Edit Mode hooks removed (Blizzard lifecycle currently unstable).
    do return end
    if MSUF_BlizzardEditHooked then
        return
    end

    if type(hooksecurefunc) ~= "function" then
        return
    end

    local em = _G.EditModeManagerFrame
    if not em then
        return
    end

local function MSUF_EM_GetBlizzEditModeActive()
    if not em then
        return false
    end
    if type(em.IsEditModeActive) == "function" then
        local ok, v = pcall(em.IsEditModeActive, em)
        if ok then
            return v and true or false
        end
    end
    if em.editModeActive ~= nil then
        return em.editModeActive and true or false
    end
    if type(em.IsShown) == "function" then
        return em:IsShown() and true or false
    end
    return false
end

local function MSUF_EM_SyncFromBlizzardSignal(tag)
    local active = MSUF_EM_GetBlizzEditModeActive()
    if em._msufLastBlizzActive ~= nil and em._msufLastBlizzActive == active then
        return
    end
    em._msufLastBlizzActive = active

    local _fn = (Edit and Edit.Flow and Edit.Flow.SetFromBlizzard) or MSUF_SetMSUFEditModeFromBlizzard
    local callTag = "Hook:BlizzSignal:" .. tostring(tag or "unknown")

    MSUF_SafeAfter(0, callTag, function()
    MSUF_SafeCall(callTag, _fn, active)
    -- Ensure modules (Auras2 preview, etc.) see Blizzard Edit Mode transitions even when unlinked.
    MSUF_EM_NotifyAnyEditMode()
    end)
end

if not em._msufHookedShowHide and type(em.HookScript) == "function" then
    em._msufHookedShowHide = true
    em:HookScript("OnShow", function()
        MSUF_EM_SyncFromBlizzardSignal("OnShow")
    end)
    em:HookScript("OnHide", function()
        MSUF_EM_SyncFromBlizzardSignal("OnHide")
    end)
end

-- One initial sync to ensure we're aligned even if the Enter/Exit hooks change in a prepatch.
MSUF_EM_SyncFromBlizzardSignal("Initial")

    if type(em.EnterEditMode) == "function" then
        hooksecurefunc(em, "EnterEditMode", function()
            MSUF_EM_SyncFromBlizzardSignal("EnterEditMode")
        end)
    end

    if type(em.ExitEditMode) == "function" then
        hooksecurefunc(em, "ExitEditMode", function()
            -- Taint/secure-stack guard: defer sync slightly so it runs after UIPanelManager finishes closing Blizzard Edit Mode.
            MSUF_SafeAfter(0.05, "Hook:ExitEditMode", function()
            MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
            end)
        end)
    elseif type(em.OnSystemClose) == "function" then
        hooksecurefunc(em, "OnSystemClose", function()
            MSUF_SafeAfter(0.05, "Hook:ExitEditMode", function()
            MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
            end)
        end)
    end

    MSUF_BlizzardEditHooked = true
end
end

if type(MSUF_EventBus_Register) == "function" then
MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_BLIZZ_EDITMODE_HOOK", function(event)
    -- delayed hook; fail-open if anything is missing
    -- Blizzard Edit Mode hook disabled (no scheduling).
    -- Blizzard Edit Mode hook disabled (no scheduling).
end, nil, true)
else
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
    -- Blizzard Edit Mode hook disabled (no scheduling).
    -- Blizzard Edit Mode hook disabled (no scheduling).
    end)
end

_G.MSUF_GetAnchorFrame = MSUF_GetAnchorFrame
_G.MSUF_IsInEditMode = MSUF_IsInEditMode
_G.MSUF_MakeBlizzardOptionsMovable = MSUF_MakeBlizzardOptionsMovable
_G.MSUF_GetCurrentGridStep = MSUF_GetCurrentGridStep
_G.MSUF_ResetCurrentEditUnit = MSUF_ResetCurrentEditUnit
_G.MSUF_CreateGridFrame = MSUF_CreateGridFrame
_G.MSUF_UpdateEditModeInfo = MSUF_UpdateEditModeInfo
_G.MSUF_OpenPositionPopup = MSUF_OpenPositionPopup
_G.MSUF_UpdateCastbarEditInfo = MSUF_UpdateCastbarEditInfo
_G.MSUF_UpdateGridOverlay = MSUF_UpdateGridOverlay
_G.MSUF_UpdateEditModeVisuals = MSUF_UpdateEditModeVisuals
_G.MSUF_SyncUnitPositionPopup = MSUF_SyncUnitPositionPopup

MSUF_EM_CombatSafeHideBossPreviewNow = function()
    if not (InCombatLockdown and InCombatLockdown()) then
        return
    end

    local bossEnabled = true
    if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
        bossEnabled = false
    end

    local wantPreview = bossEnabled and (MSUF_UnitEditModeActive and true or false) and (MSUF_BossTestMode and true or false)
    if wantPreview then
        return
    end

    local max = _G.MSUF_MAX_BOSS_FRAMES or 5
    for i = 1, max do
        local unit = "boss" .. i
        -- Never interfere with real boss units.
        if not (UnitExists and UnitExists(unit)) then
            local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit])
            if f then
                f.__msufSoftHidden = true
                -- Soft-hide is safe in combat even for protected frames (no secure calls).
                if f.EnableMouse then f:EnableMouse(false) end
                if f.SetAlpha then f:SetAlpha(0) end
                if f.SetScale then f:SetScale(0.001) end
            end
        end
    end

    MSUF__EditModePendingBossPreviewResync = true
    -- Ensure we flush the hard-hide once combat ends.
    if type(MSUF_EditMode_EnsureCombatListener) == "function" then
        MSUF_EditMode_EnsureCombatListener()
    end
end

-- P0: Enforce boss preview soft-hide even if other updates change alpha/scale in combat
-- Some update paths may call UpdateSimpleUnitFrame() while in combat and overwrite alpha/scale.
-- If a boss preview frame was soft-hidden, re-apply the soft hide after any UpdateSimpleUnitFrame() call.

-- P1: Boss unitframe preview fake portrait (when portraitMode is enabled)
-- The main unitframe update intentionally hides boss portraits when UnitExists("bossX") is false.
-- In BossTestMode (preview), UpdateSimpleUnitFrame returns early with fake hp/name, but it doesn't
-- populate a portrait. We provide a lightweight, edit-mode-only placeholder portrait here.
local function MSUF_EM_ApplyFakeBossPortrait(frame)
    if not frame or not frame.isBoss or not frame.portrait then
        return
    end
    if not (MSUF_BossTestMode and MSUF_UnitEditModeActive) then
        return
    end

    local unit = frame.unit
    if unit and UnitExists and UnitExists(unit) then
        -- Never override a real boss unit.
        return
    end

    local conf = (MSUF_DB and MSUF_DB.boss)
    if not conf then
        return
    end

    local mode = conf.portraitMode or "OFF"
    if mode == "OFF" then
        -- If the user turned portrait off, ensure it stays hidden in preview too.
        frame.portrait:Hide()
        frame.__msufFakePortraitMode = nil
        return
    end

    -- Layout (LEFT/RIGHT) matches normal behavior.
    if type(MSUF_UpdateBossPortraitLayout) == "function" then
        MSUF_UpdateBossPortraitLayout(frame, conf)
    end

    -- Only touch the texture when needed to reduce flicker / redundant work.
    if frame.__msufFakePortraitMode ~= mode then
        frame.__msufFakePortraitMode = mode

        if SetPortraitTexture and UnitExists and UnitExists("player") then
            -- Simple: use player portrait as a stable placeholder.
            SetPortraitTexture(frame.portrait, "player")
        elseif SetPortraitToTexture then
            SetPortraitToTexture(frame.portrait, "Interface\\ICONS\\INV_Misc_QuestionMark")
        elseif frame.portrait.SetTexture then
            frame.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
        end
    end

    frame.portrait:Show()
end

MSUF_EM_EnableUpdateSimpleUnitFrameHook = function(enable)
    enable = enable and true or false

    -- Enable hook
    if enable then
        if _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked then
            return
        end
        if type(_G.UpdateSimpleUnitFrame) ~= "function" then
            return
        end

        _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked = true
        _G.MSUF_UpdateSimpleUnitFrame_Impl = _G.UpdateSimpleUnitFrame

        _G.MSUF_UpdateSimpleUnitFrame_Wrapper = function(frame, ...)
            local ok, r1, r2, r3, r4 = MSUF_FastCall(_G.MSUF_UpdateSimpleUnitFrame_Impl, frame, ...)

            -- Only do any extra work while Edit Mode is active.
            if MSUF_UnitEditModeActive then
                if frame and frame.__msufSoftHidden and (InCombatLockdown and InCombatLockdown()) then
                    local protected = (frame.IsProtected and frame:IsProtected()) and true or false
                    if not protected then
                        if frame.EnableMouse then frame:EnableMouse(false) end
                        if frame.SetAlpha then frame:SetAlpha(0) end
                        if frame.SetScale then frame:SetScale(0.001) end
                    end
                end

                -- Boss preview placeholder portrait (edit-mode only)
                if ok then
                    MSUF_EM_ApplyFakeBossPortrait(frame)
                end
            end

            if ok then
                return r1, r2, r3, r4
            end
            return nil
        end

        _G.UpdateSimpleUnitFrame = _G.MSUF_UpdateSimpleUnitFrame_Wrapper
        return
    end

    -- Disable hook (restore original)
    if not _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked then
        return
    end

    if _G.UpdateSimpleUnitFrame == _G.MSUF_UpdateSimpleUnitFrame_Wrapper and type(_G.MSUF_UpdateSimpleUnitFrame_Impl) == "function" then
        _G.UpdateSimpleUnitFrame = _G.MSUF_UpdateSimpleUnitFrame_Impl
    end

    _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked = nil
    _G.MSUF_UpdateSimpleUnitFrame_Wrapper = nil
    _G.MSUF_UpdateSimpleUnitFrame_Impl = nil
end

-- P0: Combat-safe boss unitframe preview hide
-- The boss unitframe preview ("Test Boss") is driven by MSUF_BossTestMode and uses secure visibility drivers.
-- In combat, the default implementation returns early to avoid taint, which can leave the preview visible
-- after exiting Edit Mode while still in combat.
-- Fix: When in combat AND the preview should be OFF, we do a "soft hide" (alpha/scale + mouse disable)
-- for boss frames that do NOT represent a real boss unit. After combat ends, we resync once to hard-hide.
if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" and not _G.MSUF_SyncBossUnitframePreviewWithUnitEdit_CombatSafe then
    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit_CombatSafe = true
    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit_Impl = _G.MSUF_SyncBossUnitframePreviewWithUnitEdit

    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit = function(...)
        local ok, err = MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit_Impl, ...)
        if not ok then
            if type(MSUF_EditMode_FatalDisable) == "function" then
                MSUF_EditMode_FatalDisable("BossPreviewSync", err)
            end
            return
        end

        local inCombat = (InCombatLockdown and InCombatLockdown()) and true or false
        local max = _G.MSUF_MAX_BOSS_FRAMES or 5

        if inCombat then
            -- In combat, the underlying implementation may return early to avoid taint.
            -- If the preview SHOULD be hidden (Edit Mode is off OR boss frames disabled OR test mode off),
            -- we "soft-hide" the preview frames immediately (alpha/scale/mouse) without touching secure drivers.
            local bossEnabled = true
            if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
                bossEnabled = false
            end

            local wantPreview = bossEnabled and (MSUF_UnitEditModeActive and true or false) and (MSUF_BossTestMode and true or false)
            if not wantPreview then
                for i = 1, max do
                    local unit = "boss" .. i
                    -- Never interfere with real boss units.
                    if not (UnitExists and UnitExists(unit)) then
                        local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit])
                        if f then
                            f.__msufSoftHidden = true
                local protected = (f.IsProtected and f:IsProtected()) and true or false
                if not protected then
                    if f.EnableMouse then f:EnableMouse(false) end
                    if f.SetAlpha then f:SetAlpha(0) end
                    if f.SetScale then f:SetScale(0.001) end
                end
                        end
                    end
                end

                -- Ask for one post-combat resync to hard-hide.
                MSUF__EditModePendingBossPreviewResync = true
            end
        else
            -- Restore scale for any frame we soft-hid in combat.
            for i = 1, max do
                local unit = "boss" .. i
                local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit])
                if f and f.__msufSoftHidden then
                    f.__msufSoftHidden = nil
                    if f.EnableMouse then f:EnableMouse(true) end
                    if f.SetAlpha then f:SetAlpha(1) end
                    if f.SetScale then f:SetScale(1) end
                end
            end
        end

if MSUF_BossTestMode and MSUF_UnitEditModeActive then
    for i = 1, max do
        local unit = "boss" .. i
        if not (UnitExists and UnitExists(unit)) then
            local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit])
            if f then
                MSUF_EM_ApplyFakeBossPortrait(f)
            end
        end
    end
end
    end
end

-- Entry-point wrappers (fail-open)
if type(MSUF_SetMSUFEditModeFromBlizzard) == "function" and not _G.MSUF_SetMSUFEditModeFromBlizzard_Impl then
    _G.MSUF_SetMSUFEditModeFromBlizzard_Impl = MSUF_SetMSUFEditModeFromBlizzard
    MSUF_SetMSUFEditModeFromBlizzard = function(active)
        return MSUF_SafeCall("MSUF_SetMSUFEditModeFromBlizzard", _G.MSUF_SetMSUFEditModeFromBlizzard_Impl, active)
    end
end

if type(_G.MSUF_SetMSUFEditModeDirect) == "function" and not _G.MSUF_SetMSUFEditModeDirect_Impl then
    _G.MSUF_SetMSUFEditModeDirect_Impl = _G.MSUF_SetMSUFEditModeDirect
    _G.MSUF_SetMSUFEditModeDirect = function(active, unitKey)
        return MSUF_SafeCall("MSUF_SetMSUFEditModeDirect", _G.MSUF_SetMSUFEditModeDirect_Impl, active, unitKey)
    end
end
-- Additional fail-open wrappers (popups)
if type(_G.MSUF_OpenPositionPopup) == "function" and not _G.MSUF_OpenPositionPopup_Impl then
    _G.MSUF_OpenPositionPopup_Impl = _G.MSUF_OpenPositionPopup
    _G.MSUF_OpenPositionPopup = function(...)
        return MSUF_SafeCall("Popup:OpenUnit", _G.MSUF_OpenPositionPopup_Impl, ...)
    end
end

if type(MSUF_OpenCastbarPositionPopup) == "function" and not _G.MSUF_OpenCastbarPositionPopup_Impl then
    _G.MSUF_OpenCastbarPositionPopup_Impl = MSUF_OpenCastbarPositionPopup
    MSUF_OpenCastbarPositionPopup = function(...)
        return MSUF_SafeCall("Popup:OpenCastbar", _G.MSUF_OpenCastbarPositionPopup_Impl, ...)
    end
end

-- Phase 1 exports (non-breaking): expose key entry points under _G.MSUF_Edit
do
    -- Keep the existing, backward-compatible state plumbing.
    Edit.State = MSUF_EM_GetState()
    Edit.SyncLegacyFromState = MSUF_EM_SyncLegacyFromState
    Edit.SetActive = MSUF_EM_SetActive
    Edit.SetPopupOpen = MSUF_EM_SetPopupOpen

    Edit.Transitions = Edit.Transitions or {}
    Edit.Transitions.SetMSUFEditModeDirect = _G.MSUF_SetMSUFEditModeDirect

    Edit.Arrow = Edit.Arrow or {}
    Edit.Arrow.Enable = _G.MSUF_EnableArrowKeyNudge

    Edit.Popups = Edit.Popups or {}
    Edit.Popups.OpenPositionPopup = MSUF_OpenPositionPopup
    -- Note: other popup helpers remain internal; this is just a stable entry point.

    Edit.Secure = Edit.Secure or {}
    Edit.Secure.MakeBlizzardOptionsMovable = MSUF_MakeBlizzardOptionsMovable

    -- (Wrappers only; existing globals remain unchanged.)
    Edit.Util = Edit.Util or {}
    Edit.Util.SafeCall = Edit.Util.SafeCall or MSUF_SafeCall
    Edit.Util.SafeAfter = Edit.Util.SafeAfter or MSUF_SafeAfter
    Edit.Util.ClearKeyboardFocus = Edit.Util.ClearKeyboardFocus or MSUF_EM_ClearKeyboardFocus

    Edit.Bind = Edit.Bind or {}
    Edit.Bind.EnableArrowKeyNudge = Edit.Bind.EnableArrowKeyNudge or _G.MSUF_EnableArrowKeyNudge

    Edit.Preview = Edit.Preview or {}
    Edit.Preview.HideBossSoft = Edit.Preview.HideBossSoft or MSUF_EM_CombatSafeHideBossPreviewNow
    Edit.Preview.UpdateBossCastbarPreview = Edit.Preview.UpdateBossCastbarPreview or _G.MSUF_UpdateBossCastbarPreview
    Edit.UI = Edit.UI or EM_UI
    Edit.Dock = Edit.Dock or EM_Dock
    Edit.Targets = Edit.Targets or EM_Targets

    --     Globals remain as wrappers to preserve compatibility.
    Edit.Flow = Edit.Flow or {}

    -- Capture the *real* implementations (pre-wrapper) so Flow never recurses.
    local implFromBlizzard = _G.MSUF_SetMSUFEditModeFromBlizzard_Impl or MSUF_SetMSUFEditModeFromBlizzard
    local implDirect = _G.MSUF_SetMSUFEditModeDirect_Impl or _G.MSUF_SetMSUFEditModeDirect

    -- Primary routed entry points (use the canonical SafeCall tags so fail-open works as intended).
    Edit.Flow.SetFromBlizzard = function(active)
        if not active then
            local st = MSUF_EM_GetState()
            if st and st.suppressNextBlizzardExit then
                st.suppressNextBlizzardExit = false
                return
            end
        end
        return MSUF_SafeCall("MSUF_SetMSUFEditModeFromBlizzard", implFromBlizzard, active)
    end

    Edit.Flow.SetDirect = function(active, unitKey)
        return MSUF_SafeCall("MSUF_SetMSUFEditModeDirect", implDirect, active, unitKey)
    end

    -- Convenience helpers (used by Options/commands; keeps behavior identical).
    Edit.Flow.Enter = function(unitKey)
        if Edit.Util and Edit.Util.ClearKeyboardFocus then
            Edit.Util.ClearKeyboardFocus()
        end
        return Edit.Flow.SetDirect(true, unitKey or "player")
    end

    Edit.Flow.Exit = function(source, opts)
        -- Deterministic, non-recursive exit path. Safe in and out of combat (secure work deferred).
        if not opts then opts = { flushPending = true } end
        if not MSUF_UnitEditModeActive and type(MSUF_CloseAllPositionPopups) == "function" then
            -- Failsafe: even if state drifted, ensure popups are closed.
            MSUF_CloseAllPositionPopups()
        end
        return MSUF_SafeCall("MSUF_EditMode_ExitDeterministic", MSUF_EditMode_ExitDeterministic, source or "flow", opts)
    end

    Edit.Flow.Toggle = function(unitKey)
        if MSUF_UnitEditModeActive then
            return Edit.Flow.Exit("toggle", { flushPending = true })
        end
        return Edit.Flow.Enter(unitKey)
    end

    -- Keep these direct references for internal reuse.
    Edit.Flow.ExitDeterministic = Edit.Flow.ExitDeterministic or MSUF_EditMode_ExitDeterministic
    Edit.Flow.RequestVisibilityDrivers = Edit.Flow.RequestVisibilityDrivers or MSUF_EditMode_RequestVisibilityDrivers

    -- Route the global entry points through Flow (non-breaking).
    if not _G.MSUF_EditMode_R2FlowRouted then
        _G.MSUF_EditMode_R2FlowRouted = true

        -- These wrappers ensure any external caller always hits the Flow gate.
        MSUF_SetMSUFEditModeFromBlizzard = function(active)
            return Edit.Flow.SetFromBlizzard(active)
        end

        _G.MSUF_SetMSUFEditModeDirect = function(active, unitKey)
            return Edit.Flow.SetDirect(active, unitKey)
        end

        -- Keep Transition handle aligned with the routed wrapper.
        Edit.Transitions.SetMSUFEditModeDirect = _G.MSUF_SetMSUFEditModeDirect
    end
end

