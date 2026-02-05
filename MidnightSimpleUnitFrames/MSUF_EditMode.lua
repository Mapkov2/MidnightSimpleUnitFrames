--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua"); local addonName, ns = ...
ns = ns or {}
_G.MSUF_NS = _G.MSUF_NS or ns

-- Forward declarations (needed by early popup helpers)
local MSUF_EDITMODE_UNIT_KEYS, MSUF_EDITMODE_UNIT_FIELDS, MSUF_EDITMODE_GENERAL_FIELDS
-- Forward declare: needed so Castbar popup spec tables and builders capture the correct function.
-- Fixes dead Show/Override checkboxes (OnClick=nil) and makes overrides apply instantly.
local ApplyCastbarPopupValues



-- ------------------------------------------------------------
-- This needs to be refactored - Way to much spagetti code here. 
-- ------------------------------------------------------------
local function MSUF_UFDirty(frame, reason, urgent) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:16:6");
    if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:16:6"); return end
    local md = _G.MSUF_UFCore_MarkDirty
    if type(md) == "function" then
        md(frame, nil, urgent, reason)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:16:6"); return
    end
    -- Fallback for older builds (should be unused once UFCore is present)
    local upd = _G.UpdateSimpleUnitFrame
    if type(upd) == "function" then
        upd(frame)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UFDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:16:6"); end

-- Load-order safety: EnsureDB may not be available at the moment Edit Mode code runs (prepatch/load timing).
-- Always guard DB initialization so missing globals don't break Edit Mode entry points.
local function MSUF_EM_EnsureDB() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:32:6");
    if _G.MSUF_DB then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:32:6"); return true
    end
    local fn = _G.EnsureDB
    if type(fn) == "function" then
        fn()
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:32:6", (_G.MSUF_DB ~= nil))
    end
    if ns and type(ns.EnsureDB) == "function" then
        ns.EnsureDB()
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:32:6", (_G.MSUF_DB ~= nil))
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:32:6"); return false
end

-- -------------------------------------------
-- Edit Mode namespace (Phase 1 refactor scaffold)
-- -------------------------------------------
_G.MSUF_Edit = _G.MSUF_Edit or {}
local Edit = _G.MSUF_Edit
Edit.VERSION = Edit.VERSION or "v10_refactor_phase1"
Edit.Modules = Edit.Modules or {}

-- R1: Internal sub-modules (single-file, no behavior change)
Edit.Util   = Edit.Util   or {}
Edit.Bind   = Edit.Bind   or {}
Edit.Preview= Edit.Preview or {}
Edit.Flow   = Edit.Flow   or {}

-- R2: Additional internal modules for maintainability (single-file)
Edit.UI      = Edit.UI      or {}
Edit.Dock    = Edit.Dock    or {}
Edit.Targets = Edit.Targets or {}

-- Local aliases (avoid repeated global table lookups)
local EM_UI      = Edit.UI
local EM_Dock    = Edit.Dock
local EM_Targets = Edit.Targets

-- -------------------------------------------
-- Safeguard helpers (fail-open, taint-safe-ish)
-- -------------------------------------------
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
-- -------------------------------------------
-- -------------------------------------------
local function MSUF_EM_GetState() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:92:6");
    -- Single source of truth: Edit.State (mirrored to _G.MSUF_EditState for backward compatibility)
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:92:6"); return st
end

local function MSUF_EM_SyncLegacyFromState() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SyncLegacyFromState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:116:6");
    local st = MSUF_EM_GetState()
    MSUF_UnitEditModeActive = st.active and true or false
    MSUF_CurrentEditUnitKey = st.unitKey
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SyncLegacyFromState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:116:6"); end

-- -------------------------------------------
-- Any-EditMode listeners (enter/exit notifications)
-- Modules can subscribe to avoid their own polling (e.g. Auras edit-mode previews).
-- -------------------------------------------
if not _G.MSUF_AnyEditModeListeners then
    _G.MSUF_AnyEditModeListeners = {}
end

if not _G.MSUF_RegisterAnyEditModeListener then
    function _G.MSUF_RegisterAnyEditModeListener(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_RegisterAnyEditModeListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:131:4");
        if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_RegisterAnyEditModeListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:131:4"); return end
        local t = _G.MSUF_AnyEditModeListeners
        t[#t + 1] = fn
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_RegisterAnyEditModeListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:131:4"); end
end

-- Any-EditMode state = (MSUF Edit Mode) OR (Blizzard Edit Mode)
-- This is used by modules (Auras2 previews, etc.) to reliably start/stop preview visuals
-- even when MSUF Edit Mode is running unlinked from Blizzard Edit Mode.
local function MSUF_EM_IsBlizzardEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_IsBlizzardEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:141:6");
    -- Blizzard Edit Mode integration disabled (TEMP/Hotfix):
    -- Blizzard started transiently showing EditModeManagerFrame during reload/zone transitions,
    -- which can incorrectly force MSUF Edit Mode to open. We now treat Blizzard Edit Mode as unrelated.
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsBlizzardEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:141:6"); return false
end


local function MSUF_EM_GetAnyEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetAnyEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:149:6");
    local st = MSUF_EM_GetState()
    if type(st) == "table" and st.active == true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetAnyEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:149:6"); return true
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetAnyEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:149:6", MSUF_EM_IsBlizzardEditModeActive())
end

-- Seed baseline so listeners only fire on transitions.
local MSUF_EM_LastAnyEditMode = MSUF_EM_GetAnyEditModeActive()

local function MSUF_EM_NotifyAnyEditMode(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_NotifyAnyEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:160:6");
    if active == nil then
        active = MSUF_EM_GetAnyEditModeActive()
    end

    active = active and true or false
    if MSUF_EM_LastAnyEditMode == active then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_NotifyAnyEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:160:6"); return
    end
    MSUF_EM_LastAnyEditMode = active

    local t = _G.MSUF_AnyEditModeListeners
    if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_NotifyAnyEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:160:6"); return end

    -- Avoid hard dependency on MSUF_FastCall during very early load edge cases
    local call = (type(MSUF_FastCall) == "function") and MSUF_FastCall or function(f, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:175:74"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:175:74", f(...)) end

    for i = 1, #t do
        local fn = t[i]
        if type(fn) == "function" then
            call(fn, active)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_NotifyAnyEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:160:6"); end


local function MSUF_EM_ClearKeyboardFocus() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ClearKeyboardFocus file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:186:6");

    if ChatEdit_DeactivateChat then
        if ChatEdit_GetActiveWindow then
            local eb = ChatEdit_GetActiveWindow()
            if eb then
                MSUF_FastCall(ChatEdit_DeactivateChat, eb)
            end
        end
    end
    -- Clear any active editbox focus
    if GetCurrentKeyBoardFocus then
        local f = GetCurrentKeyBoardFocus()
        if f and f.ClearFocus then
            MSUF_FastCall(f.ClearFocus, f)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ClearKeyboardFocus file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:186:6"); end

local MSUF_EM_EnableUpdateSimpleUnitFrameHook 

local function MSUF_EM_SetActive(active, unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:207:6");
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
            MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit)
        else
            -- Legacy fallback: best-effort hide (OOC only). In combat, rely on soft-hide gate.
            if InCombatLockdown and InCombatLockdown() then
                if MSUF_EM_CombatSafeHideBossPreviewNow then
                    MSUF_FastCall(MSUF_EM_CombatSafeHideBossPreviewNow)
                end
            else
                local max = _G.MSUF_MAX_BOSS_FRAMES or 5
                for i = 1, max do
                    local unit = "boss" .. i
                    local f = _G["MSUF_" .. unit] or _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames[unit])
                    if f and f.Hide then
                        MSUF_FastCall(f.Hide, f)
                    end
                end
            end
        end

        -- Also guarantee boss castbar preview is torn down on deactivation (keeps systems consistent).
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview)
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
        MSUF_FastCall(MSUF_EM_ClearKeyboardFocus)
    end
    if not st.active and MSUF_EM_CombatSafeHideBossPreviewNow then
        MSUF_FastCall(MSUF_EM_CombatSafeHideBossPreviewNow)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:207:6"); end

local function MSUF_EM_SetPopupOpen(open) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetPopupOpen file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:272:6");
    local st = MSUF_EM_GetState()
    st.popupOpen = open and true or false
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetPopupOpen file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:272:6"); end

local function MSUF_EM_SetArrowBindingsActive(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetArrowBindingsActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:277:6");
    local st = MSUF_EM_GetState()
    st.arrowBindingsActive = active and true or false
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetArrowBindingsActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:277:6"); end

local function MSUF_EM_SetPendingSecureCleanup(pending) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetPendingSecureCleanup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:282:6");
    local st = MSUF_EM_GetState()
    st.pendingSecureCleanup = pending and true or false
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetPendingSecureCleanup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:282:6"); end

local function MSUF_EM_SetFatalDisabled(tag, reason) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetFatalDisabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:287:6");
    local st = MSUF_EM_GetState()
    st.fatalDisabled = true
    st.fatalTag = tostring(tag or "?")
    st.fatalReason = tostring(reason or "unknown")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetFatalDisabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:287:6"); end

local function MSUF_EM_ForceWhiteButtonText(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ForceWhiteButtonText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:294:6");
    if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ForceWhiteButtonText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:294:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ForceWhiteButtonText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:294:6"); end

do
    local UIH = (ns and ns.MSUF_EM_UIH) or {}
    if ns then ns.MSUF_EM_UIH = UIH end

    local CreateFrame = CreateFrame

    function UIH.Button(parent, name, w, h, text, template) Perfy_Trace(Perfy_GetTime(), "Enter", "UIH.Button file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:320:4");
        local b = CreateFrame("Button", name, parent, template or "UIPanelButtonTemplate")
        if w and h then b:SetSize(w, h) end
        if text ~= nil and b.SetText then b:SetText(text) end
        if type(MSUF_EM_ForceWhiteButtonText) == "function" then
            MSUF_EM_ForceWhiteButtonText(b)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "UIH.Button file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:320:4"); return b
    end

    function UIH.ButtonAt(parent, name, w, h, point, rel, relPoint, x, y, text, template) Perfy_Trace(Perfy_GetTime(), "Enter", "UIH.ButtonAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:330:4");
        local b = UIH.Button(parent, name, w, h, text, template)
        if point and rel then b:SetPoint(point, rel, relPoint or point, x or 0, y or 0)
        elseif point then b:SetPoint(point, x or 0, y or 0) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "UIH.ButtonAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:330:4"); return b
    end

    -- Creates the same checkbox label style we used previously (GameFontHighlightSmall + manual anchor).
    function UIH.TextCheck(parent, name, point, rel, relPoint, x, y, text, onClick, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "UIH.TextCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:338:4");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "UIH.TextCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:338:4"); return cb
    end
end

function MSUF_EM_DropdownPreset(drop, width, placeholder) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_DropdownPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:358:0");
    if not drop then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_DropdownPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:358:0"); return end
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(drop, width or 150) end
    if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(drop, "LEFT") end
    if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, placeholder or "") end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_DropdownPreset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:358:0"); end

function MSUF_EM_BuildCopyItems(list, srcValue, labelFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_BuildCopyItems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:365:0");
    if not list then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_BuildCopyItems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:365:0"); return nil end
    local out = {}
    for i = 1, #list do
        local v = list[i]
        if v ~= srcValue then
            out[#out + 1] = { value = v, text = labelFn and labelFn(v) or tostring(v) }
        end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_BuildCopyItems file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:365:0"); return out
end

function MSUF_EM_InitCopyDropdown(drop, placeholder, itemsProvider, onPick) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_InitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:377:0");
    if not drop or not UIDropDownMenu_Initialize or not UIDropDownMenu_CreateInfo or not UIDropDownMenu_AddButton then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_InitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:377:0"); return end
    MSUF_EM_DropdownPreset(drop, 150, placeholder)

    UIDropDownMenu_Initialize(drop, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:381:36");
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true

        local items = itemsProvider and itemsProvider()
        if not items then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:381:36"); return end

        for i = 1, #items do
            local item = items[i]
            local value = item and item.value
            local label = (item and item.text) or (value ~= nil and tostring(value)) or ""

            info.text = label
            info.func = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:394:24");
                if onPick then onPick(value, item) end
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(drop, label) end
                if CloseDropDownMenus then CloseDropDownMenus() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:394:24"); end
            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:381:36"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_InitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:377:0"); end

function MSUF_EM_GetCastbarCopyUnits(srcUnit) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetCastbarCopyUnits file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:404:0");
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetCastbarCopyUnits file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:404:0", (srcUnit == "boss") and { "player", "target", "focus" } or { "player", "target", "focus", "boss" })
end

local function MSUF_EM_CopyCastbarSizeSettings(srcUnit, dstUnit) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CopyCastbarSizeSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:408:6");
    if not srcUnit or not dstUnit or srcUnit == dstUnit then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyCastbarSizeSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:408:6"); return end
    if type(MSUF_EM_EnsureDB) == "function" then MSUF_EM_EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local function read(u) Perfy_Trace(Perfy_GetTime(), "Enter", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:415:10");
        if u == "boss" then
            return Perfy_Trace_Passthrough("Leave", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:415:10", tonumber(g.bossCastbarWidth), tonumber(g.bossCastbarHeight))
        end
        local p = type(MSUF_GetCastbarPrefix) == "function" and MSUF_GetCastbarPrefix(u) or nil
        if not p then Perfy_Trace(Perfy_GetTime(), "Leave", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:415:10"); return nil end
        return Perfy_Trace_Passthrough("Leave", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:415:10", tonumber(g[p .. "BarWidth"]), tonumber(g[p .. "BarHeight"]))
    end

    local function write(u, w, h) Perfy_Trace(Perfy_GetTime(), "Enter", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:424:10");
        if w == nil and h == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:424:10"); return end
        if u == "boss" then
            if w ~= nil then g.bossCastbarWidth = w end
            if h ~= nil then g.bossCastbarHeight = h end
            Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:424:10"); return
        end
        local p = type(MSUF_GetCastbarPrefix) == "function" and MSUF_GetCastbarPrefix(u) or nil
        if not p then Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:424:10"); return end
        if w ~= nil then g[p .. "BarWidth"] = w end
        if h ~= nil then g[p .. "BarHeight"] = h end
    Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:424:10"); end

    local w, h = read(srcUnit)
    if w == nil and h == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyCastbarSizeSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:408:6"); return end
    write(dstUnit, w, h)

    if type(MSUF_ApplyCastbarUnitAndSync) == "function" then
        if type(MSUF_SafeCall) == "function" then
            MSUF_SafeCall("CopyCastbarSize:Apply", MSUF_ApplyCastbarUnitAndSync, dstUnit)
        else
            MSUF_ApplyCastbarUnitAndSync(dstUnit)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyCastbarSizeSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:408:6"); end

local function MSUF_EM_CopyCastbarTextSettings(srcUnit, dstUnit) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CopyCastbarTextSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:450:6");
    if not srcUnit or not dstUnit or srcUnit == dstUnit then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyCastbarTextSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:450:6"); return end
    if type(MSUF_EM_EnsureDB) == "function" then MSUF_EM_EnsureDB() end
    MSUF_DB = MSUF_DB or {}
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

    local function read(u) Perfy_Trace(Perfy_GetTime(), "Enter", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:457:10");
        if u == "boss" then
            return Perfy_Trace_Passthrough("Leave", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:457:10", {
                textX    = g.bossCastTextOffsetX,
                textY    = g.bossCastTextOffsetY,
                showName = g.showBossCastName,
                nameSize = g.bossCastSpellNameFontSize,

                iconX    = g.bossCastIconOffsetX,
                iconY    = g.bossCastIconOffsetY,
                showIcon = g.showBossCastIcon,
                iconSize = g.bossCastIconSize,

                timeX    = g.bossCastTimeOffsetX,
                timeY    = g.bossCastTimeOffsetY,
                showTime = g.showBossCastTime,
                timeSize = g.bossCastTimeFontSize,
            })
        end

        local p = type(MSUF_GetCastbarPrefix) == "function" and MSUF_GetCastbarPrefix(u) or nil
        if not p then Perfy_Trace(Perfy_GetTime(), "Leave", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:457:10"); return nil end
        local showKey = type(MSUF_GetCastbarShowTimeKey) == "function" and MSUF_GetCastbarShowTimeKey(u) or nil

        return Perfy_Trace_Passthrough("Leave", "read file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:457:10", {
            textX    = g[p .. "TextOffsetX"],
            textY    = g[p .. "TextOffsetY"],
            showName = g[p .. "ShowSpellName"],
            nameSize = g[p .. "SpellNameFontSize"],

            iconX    = g[p .. "IconOffsetX"],
            iconY    = g[p .. "IconOffsetY"],
            showIcon = g[p .. "ShowIcon"],
            iconSize = g[p .. "IconSize"],

            timeX    = g[p .. "TimeOffsetX"],
            timeY    = g[p .. "TimeOffsetY"],
            showTime = showKey and g[showKey] or nil,
            timeSize = g[p .. "TimeFontSize"],
        })
    end

    local function write(u, t) Perfy_Trace(Perfy_GetTime(), "Enter", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:499:10");
        if not t then Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:499:10"); return end
        if u == "boss" then
            g.bossCastTextOffsetX = t.textX
            g.bossCastTextOffsetY = t.textY
            g.showBossCastName = t.showName
            g.bossCastSpellNameFontSize = t.nameSize

            g.bossCastIconOffsetX = t.iconX
            g.bossCastIconOffsetY = t.iconY
            g.showBossCastIcon = t.showIcon
            g.bossCastIconSize = t.iconSize

            g.bossCastTimeOffsetX = t.timeX
            g.bossCastTimeOffsetY = t.timeY
            g.showBossCastTime = t.showTime
            g.bossCastTimeFontSize = t.timeSize
            Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:499:10"); return
        end

        local p = type(MSUF_GetCastbarPrefix) == "function" and MSUF_GetCastbarPrefix(u) or nil
        if not p then Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:499:10"); return end

        g[p .. "TextOffsetX"]       = t.textX
        g[p .. "TextOffsetY"]       = t.textY
        g[p .. "ShowSpellName"]     = t.showName
        g[p .. "SpellNameFontSize"] = t.nameSize

        g[p .. "IconOffsetX"] = t.iconX
        g[p .. "IconOffsetY"] = t.iconY
        g[p .. "ShowIcon"]    = t.showIcon
        g[p .. "IconSize"]    = t.iconSize

        g[p .. "TimeOffsetX"]  = t.timeX
        g[p .. "TimeOffsetY"]  = t.timeY
        g[p .. "TimeFontSize"] = t.timeSize

        local showKey = type(MSUF_GetCastbarShowTimeKey) == "function" and MSUF_GetCastbarShowTimeKey(u) or nil
        if showKey then
            g[showKey] = t.showTime
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "write file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:499:10"); end

    local src = read(srcUnit)
    if not src then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyCastbarTextSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:450:6"); return end
    write(dstUnit, src)

    if type(MSUF_ApplyCastbarUnitAndSync) == "function" then
        if type(MSUF_SafeCall) == "function" then
            MSUF_SafeCall("CopyCastbarText:Apply", MSUF_ApplyCastbarUnitAndSync, dstUnit)
        else
            MSUF_ApplyCastbarUnitAndSync(dstUnit)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyCastbarTextSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:450:6"); end

local function MSUF_EM_RefreshCastbarCopyDropdown(pf, drop, label, placeholder, mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_RefreshCastbarCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:555:6");
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshCastbarCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:555:6"); return end
    if not pf or not drop or not label then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshCastbarCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:555:6"); return end

    local srcUnit = pf.unit
    label:Show()
    drop:Show()

    local labelFn = (type(MSUF_GetCastbarLabel) == "function") and MSUF_GetCastbarLabel or function(u) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:563:91"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:563:91", tostring(u)) end
    local onPick = function(dstUnit) Perfy_Trace(Perfy_GetTime(), "Enter", "onPick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:564:19");
        if mode == "size" then
            MSUF_EM_CopyCastbarSizeSettings(srcUnit, dstUnit)
        else
            MSUF_EM_CopyCastbarTextSettings(srcUnit, dstUnit)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "onPick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:564:19"); end

    MSUF_EM_InitCopyDropdown(drop, placeholder,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:573:8");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:573:8", MSUF_EM_BuildCopyItems(MSUF_EM_GetCastbarCopyUnits(srcUnit), srcUnit, labelFn))
        end,
        function(dstUnit) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:576:8"); onPick(dstUnit) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:576:8"); end
    )
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshCastbarCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:555:6"); end



local MSUF_EM_UNIT_COPY_ALLOWED = { player=true, target=true, targettarget=true, focus=true, boss=true }

local function MSUF_EM_CopyUnitSettings(srcKey, dstKey, mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:584:6");
    if not srcKey or not dstKey or srcKey == dstKey then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:584:6"); return end
    MSUF_EM_EnsureDB()
    if not MSUF_DB then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:584:6"); return end
    MSUF_DB[srcKey] = MSUF_DB[srcKey] or {}
    MSUF_DB[dstKey] = MSUF_DB[dstKey] or {}

    local src, dst = MSUF_DB[srcKey], MSUF_DB[dstKey]

    local function ForceApplyDestination(changedFonts) Perfy_Trace(Perfy_GetTime(), "Enter", "ForceApplyDestination file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:593:10");
        local st = (type(MSUF_EM_GetState) == "function") and MSUF_EM_GetState() or nil
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
            -- Worst-case fallback: user action, so a heavier refresh is acceptable.
            _G.MSUF_ApplyAllSettings_Immediate()
        end

        if st then st.popupOpen = wasOpen end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ForceApplyDestination file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:593:10"); end

    if mode == "size" then
        dst.width, dst.height = src.width, src.height
        ForceApplyDestination(false)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:584:6"); return
    end

    dst.showName, dst.showHP, dst.showPower = src.showName, src.showHP, src.showPower
    dst.nameOffsetX, dst.nameOffsetY = src.nameOffsetX, src.nameOffsetY
    dst.hpOffsetX, dst.hpOffsetY = src.hpOffsetX, src.hpOffsetY
    dst.powerOffsetX, dst.powerOffsetY = src.powerOffsetX, src.powerOffsetY
    dst.nameFontSize, dst.hpFontSize, dst.powerFontSize = src.nameFontSize, src.hpFontSize, src.powerFontSize

    ForceApplyDestination(true)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CopyUnitSettings file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:584:6"); end

local function MSUF_EM_GetUnitPopupSrcKey(pf) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetUnitPopupSrcKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:637:6");
    pf = pf or MSUF_PositionPopup
    local unit = pf and pf.unit
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetUnitPopupSrcKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:637:6", (unit and type(GetConfigKeyForUnit) == "function" and GetConfigKeyForUnit(unit)) or MSUF_CurrentEditUnitKey)
end

local function MSUF_EM_RefreshUnitCopyDropdown(pf, drop, label, placeholder, mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_RefreshUnitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:643:6");
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshUnitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:643:6"); return end
    if not pf or not drop or not label then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshUnitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:643:6"); return end

    local srcKey = MSUF_EM_GetUnitPopupSrcKey(pf)
    if not srcKey or not MSUF_EM_UNIT_COPY_ALLOWED[srcKey] then
        label:Hide(); drop:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshUnitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:643:6"); return
    end

    label:Show(); drop:Show()

    local labelFn = (type(MSUF_GetUnitLabelForKey) == "function") and MSUF_GetUnitLabelForKey or function(k) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:655:97"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:655:97", tostring(k)) end
    MSUF_EM_InitCopyDropdown(drop, placeholder,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:657:8");
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:657:8", MSUF_EM_BuildCopyItems(MSUF_EDITMODE_UNIT_KEYS, srcKey, labelFn))
        end,
        function(dstKey) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:660:8"); MSUF_EM_CopyUnitSettings(srcKey, dstKey, mode) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:660:8"); end
    )
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshUnitCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:643:6"); end


function MSUF_EM_AddPopupTitleAndClose(pf, titleText) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_AddPopupTitleAndClose file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:665:0");
    if not pf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AddPopupTitleAndClose file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:665:0"); return end

    local title = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(titleText or "MSUF Edit")
    pf.title = title

    local closeBtn = (ns and ns.MSUF_EM_UIH and ns.MSUF_EM_UIH.ButtonAt) and ns.MSUF_EM_UIH.ButtonAt(
        pf, "$parentClose", nil, nil, "TOPRIGHT", pf, "TOPRIGHT", -6, -6, nil, "UIPanelCloseButton"
    ) or nil

    if closeBtn then
        closeBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:678:38");
            if pf.cancelBtn and pf.cancelBtn.Click then
                pf.cancelBtn:Click()
            else
                pf:Hide()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:678:38"); end)
        pf.closeBtn = closeBtn
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AddPopupTitleAndClose file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:665:0"); end

function MSUF_EM_AddSectionHeader(pf, key, text, point, rel, relPoint, x, y) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_AddSectionHeader file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:689:0");
    if not pf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AddSectionHeader file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:689:0"); return nil end
    local fs = pf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint(point or "TOPLEFT", rel or pf, relPoint or (point or "TOPLEFT"), x or 0, y or 0)
    fs:SetText(text or "")
    fs:SetTextColor(1, 0.82, 0, 1)
    if key then pf[key] = fs end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AddSectionHeader file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:689:0"); return fs
end

function MSUF_EM_AddDivider(pf, key, width, point, rel, relPoint, x, y) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_AddDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:699:0");
    if not pf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AddDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:699:0"); return nil end
    local tex = pf:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(1, 1, 1, 0.12)
    tex:SetHeight(1)
    tex:SetWidth(width or 230)
    tex:SetPoint(point or "TOPLEFT", rel or pf, relPoint or (point or "TOPLEFT"), x or 0, y or 0)
    if key then pf[key] = tex end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AddDivider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:699:0"); return tex
end



local function MSUF_EM_GetGeneralDB() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetGeneralDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:712:6");
    MSUF_EM_EnsureDB()

    if not MSUF_DB then
        Edit.Util._fallbackGeneralDB = Edit.Util._fallbackGeneralDB or {}
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetGeneralDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:712:6", Edit.Util._fallbackGeneralDB)
    end

    MSUF_DB.general = MSUF_DB.general or {}
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetGeneralDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:712:6", MSUF_DB.general)
end


-- ------------------------------------------------------------
-- Snap (removed)
-- The snapping feature (grid/frames docking) has been fully removed.
-- Keep no-op compatibility stubs to avoid nil errors from legacy callsites.
-- ------------------------------------------------------------
local function MSUF_EM_GetSnapConfig() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetSnapConfig file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:730:6");
    local g = MSUF_EM_GetGeneralDB()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetSnapConfig file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:730:6"); return g, false, "grid", false, false
end

local function MSUF_EM_SetSnapEnabled(_enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetSnapEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:735:6"); Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetSnapEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:735:6"); end
local function MSUF_EM_SetSnapMode(_mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetSnapMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:736:6"); Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetSnapMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:736:6"); end

Edit.Util.GetSnapConfig  = MSUF_EM_GetSnapConfig
Edit.Util.SetSnapEnabled = MSUF_EM_SetSnapEnabled
Edit.Util.SetSnapMode    = MSUF_EM_SetSnapMode

local function MSUF_EM_SuppressNextBlizzardExit() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SuppressNextBlizzardExit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:742:6");

    local st = MSUF_EM_GetState()
    st.suppressNextBlizzardExit = true

    local function Clear() Perfy_Trace(Perfy_GetTime(), "Enter", "Clear file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:747:10");
        local s = MSUF_EM_GetState()
        s.suppressNextBlizzardExit = false
    Perfy_Trace(Perfy_GetTime(), "Leave", "Clear file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:747:10"); end

    if type(MSUF_SafeAfter) == "function" then
        MSUF_SafeAfter(0.6, "MSUF_EM_ClearSuppressBlizzExit", Clear)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.6, Clear)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SuppressNextBlizzardExit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:742:6"); end


Edit.Popups = Edit.Popups or {}


local function _MSUF_Resolve_impl(v, ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_Resolve_impl file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:763:6");
    if type(v) == "function" then
        return Perfy_Trace_Passthrough("Leave", "_MSUF_Resolve_impl file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:763:6", v(ctx))
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_Resolve_impl file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:763:6"); return v
end

if type(_G) == "table" and type(_G._MSUF_Resolve) ~= "function" then
    _G._MSUF_Resolve = _MSUF_Resolve_impl
end

local _MSUF_Resolve = _MSUF_Resolve_impl

do
    local P = Edit.Popups
    P._frames = P._frames or setmetatable({}, { __mode = "k" })

    local function AnyOpen() Perfy_Trace(Perfy_GetTime(), "Enter", "AnyOpen file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:780:10");
        for f in pairs(P._frames) do
            if f and f.IsShown and f:IsShown() then
                Perfy_Trace(Perfy_GetTime(), "Leave", "AnyOpen file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:780:10"); return true
            end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "AnyOpen file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:780:10"); return false
    end
    P.AnyOpen = AnyOpen

    function P.Register(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "P.Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:790:4");
        if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "P.Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:790:4"); return end
        P._frames[frame] = true

        if frame.HookScript and not frame.__msufPopupReg then
            frame.__msufPopupReg = true
            frame:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:796:39");
                MSUF_EM_SetPopupOpen(true)
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:796:39"); end)
            frame:HookScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:799:39");
                if not AnyOpen() then
                    MSUF_EM_SetPopupOpen(false)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:799:39"); end)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "P.Register file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:790:4"); end

    function P.CloseAll() Perfy_Trace(Perfy_GetTime(), "Enter", "P.CloseAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:807:4");
        for f in pairs(P._frames) do
            if f and f.Hide then
                MSUF_FastCall(f.Hide, f)
            end
        end
        if GameTooltip and GameTooltip.Hide then
            MSUF_FastCall(GameTooltip.Hide, GameTooltip)
        end
        MSUF_EM_SetPopupOpen(false)
    Perfy_Trace(Perfy_GetTime(), "Leave", "P.CloseAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:807:4"); end
end


Edit.Popups.UI = Edit.Popups.UI or {}
do
    local UI = Edit.Popups.UI

    function UI.SetLabelEnabled(fs, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "UI.SetLabelEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:825:4");
        if not fs or not fs.SetTextColor then Perfy_Trace(Perfy_GetTime(), "Leave", "UI.SetLabelEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:825:4"); return end
        if enabled then
            fs:SetTextColor(1, 1, 1, 0.95)
        else
            fs:SetTextColor(0.55, 0.55, 0.55, 0.9)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "UI.SetLabelEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:825:4"); end

    function UI.SetControlEnabled(w, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "UI.SetControlEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:834:4");
        if not w then Perfy_Trace(Perfy_GetTime(), "Leave", "UI.SetControlEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:834:4"); return end

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
            MSUF_FastCall(w.ClearFocus, w)
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "UI.SetControlEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:834:4"); end

    function UI.EnableStepper(btnMinus, btnPlus, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "UI.EnableStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:867:4");
        UI.SetControlEnabled(btnMinus, enabled)
        UI.SetControlEnabled(btnPlus, enabled)
    Perfy_Trace(Perfy_GetTime(), "Leave", "UI.EnableStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:867:4"); end

    function UI.SetSizeControlsEnabled(box, minusBtn, plusBtn, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "UI.SetSizeControlsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:872:4");
        UI.SetControlEnabled(box, enabled)
        UI.EnableStepper(minusBtn, plusBtn, enabled)
    Perfy_Trace(Perfy_GetTime(), "Leave", "UI.SetSizeControlsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:872:4"); end
end

Edit.Popups.Util = Edit.Popups.Util or {}
do
    local U = Edit.Popups.Util

    local function ClampNumber(v, minV, maxV) Perfy_Trace(Perfy_GetTime(), "Enter", "ClampNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:882:10");
        v = tonumber(v)
        if not v then Perfy_Trace(Perfy_GetTime(), "Leave", "ClampNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:882:10"); return nil end
        v = math.floor(v + 0.5)
        if minV and v < minV then v = minV end
        if maxV and v > maxV then v = maxV end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ClampNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:882:10"); return v
    end

    function U.ReadOverrideChecked(cb, fallback) Perfy_Trace(Perfy_GetTime(), "Enter", "U.ReadOverrideChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:891:4");
        if cb and cb.GetChecked then
            local ok, val = pcall(cb.GetChecked, cb)
            if ok then
                return Perfy_Trace_Passthrough("Leave", "U.ReadOverrideChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:891:4", (val and true or false))
            end
        end
        return Perfy_Trace_Passthrough("Leave", "U.ReadOverrideChecked file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:891:4", (fallback and true or false))
    end

    function U.ApplyOptionalOverrideNumber(conf, fieldKey, box, overrideCB, enableFn, minusBtn, plusBtn, enabledGate, baseValue, minV, maxV) Perfy_Trace(Perfy_GetTime(), "Enter", "U.ApplyOptionalOverrideNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:901:4");
        if type(conf) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "U.ApplyOptionalOverrideNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:901:4"); return false end

        local old = conf[fieldKey]
        local want = (old ~= nil)
        want = U.ReadOverrideChecked(overrideCB, want)

        if enableFn then
            enableFn(box, minusBtn, plusBtn, (want and (enabledGate ~= false)))
        end

        if want then
            local raw = (box and box.GetText and box:GetText()) or nil
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

        return Perfy_Trace_Passthrough("Leave", "U.ApplyOptionalOverrideNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:901:4", (old ~= conf[fieldKey]))
    end

    function U.SyncOptionalOverrideNumber(conf, fieldKey, box, overrideCB, enableFn, minusBtn, plusBtn, enabledGate, baseValue) Perfy_Trace(Perfy_GetTime(), "Enter", "U.SyncOptionalOverrideNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:929:4");
        if type(conf) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "U.SyncOptionalOverrideNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:929:4"); return end

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
    Perfy_Trace(Perfy_GetTime(), "Leave", "U.SyncOptionalOverrideNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:929:4"); end
end
local function MSUF_GetFeatureForTag(tag) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetFeatureForTag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:948:6");
    tag = tostring(tag or "")
    -- Arrow-key nudging
    if tag:find("^ArrowKey:") then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetFeatureForTag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:948:6"); return "arrowKeys"
    end
    -- Boss preview sync/update (non-critical to keep the rest of Edit Mode usable)
    if tag == "Flush:BossCastbarPreview" or tag == "Flush:BossCastbarPopupSync" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetFeatureForTag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:948:6"); return "bossPreview"
    end
    -- Popup helper features
    if tag == "Stepper:onStep" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetFeatureForTag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:948:6"); return "popupSteppers"
    end
    if tag == "CopyCastbarSize:Apply" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetFeatureForTag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:948:6"); return "popupCopyCastbarSize"
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetFeatureForTag file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:948:6"); return nil
end

local function MSUF_DisableFeature(feature) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_DisableFeature file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:968:6");
    if not feature or MSUF__SafeFeatureDisabled[feature] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DisableFeature file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:968:6"); return
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
            MSUF_FastCall(_G.MSUF_EnableArrowKeyNudge, false)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_DisableFeature file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:968:6"); end

MSUF_SafeCall = function(tag, fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:988:16");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:988:16"); return nil end

    local feature = MSUF_GetFeatureForTag(tag)
    if feature and MSUF__SafeFeatureDisabled[feature] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:988:16"); return nil
    end

    local t = tostring(tag or "")
    if MSUF__EditModeFatalDisabled then
        if t == "MSUF_SetMSUFEditModeDirect" or t == "MSUF_SetMSUFEditModeFromBlizzard" or t:find("^Popup:") or t:find("^Hook:") or t:find("^Flush:UnitApply:") or t:find("^Flush:CastbarApply:") or t == "Flush:CastbarVisuals" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:988:16"); return nil
        end
    end

    local args = { ... }
    local ok, r1, r2, r3, r4, r5 = xpcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1004:42");
        return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1004:42", fn(unpack(args)))
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:988:16"); return nil
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeCall file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:988:16"); return r1, r2, r3, r4, r5
end

local function MSUF_EditMode_ShowStepModifierTipOnce(anchorFrame) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_ShowStepModifierTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1040:6");
    -- Dezent + nur einmal pro Session. Wird nur von Popup +/- aufgerufen.
    if _G.MSUF__PopupStepperTipShown then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowStepModifierTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1040:6"); return
    end
    _G.MSUF__PopupStepperTipShown = true

    local f = anchorFrame
    if not f or type(f.CreateFontString) ~= "function" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowStepModifierTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1040:6"); return
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

    -- Kurzer, unaufdringlicher Hinweis (wie früher).
    tip:SetText("")
    tip:Show()

    -- Auto-hide
    if C_Timer and C_Timer.After then
        local token = (tip.__msufHideToken or 0) + 1
        tip.__msufHideToken = token
        C_Timer.After(3.0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1071:27");
            if tip and tip.__msufHideToken == token and tip.Hide then
                tip:Hide()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1071:27"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowStepModifierTipOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1040:6"); end

local MSUF__EM_AfterSeq = 0

MSUF_SafeAfter = function(seconds, tag, fn, requireActive) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SafeAfter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1081:17");
    if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeAfter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1081:17"); return end
    local mySeq = MSUF__EM_AfterSeq

    local function _shouldRun() Perfy_Trace(Perfy_GetTime(), "Enter", "_shouldRun file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1085:10");
        if mySeq ~= MSUF__EM_AfterSeq then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_shouldRun file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1085:10"); return false
        end
        if requireActive then
            local st = Edit and (Edit.State or _G.MSUF_EditState)
            if not (st and st.active) then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_shouldRun file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1085:10"); return false
            end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_shouldRun file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1085:10"); return true
    end

    if not (C_Timer and C_Timer.After) then
        if not _shouldRun() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeAfter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1081:17"); return end
        return Perfy_Trace_Passthrough("Leave", "MSUF_SafeAfter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1081:17", MSUF_SafeCall("After:" .. tostring(tag), fn))
    end

    C_Timer.After(tonumber(seconds) or 0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1103:42");
        if not _shouldRun() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1103:42"); return end
        MSUF_SafeCall("After:" .. tostring(tag), fn)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1103:42"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SafeAfter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1081:17"); end


local function MSUF_SanitizePopupOffset(v, default) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SanitizePopupOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1110:6");
    default = tonumber(default) or 0
    v = tonumber(v)
    if not v then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SanitizePopupOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1110:6"); return default end
    -- NaN / inf guards
    if v ~= v or v == math.huge or v == -math.huge then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SanitizePopupOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1110:6"); return default
    end
    -- Hard clamp (offsets should never be in the billions)
    if math.abs(v) > 10000 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SanitizePopupOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1110:6"); return default
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_SanitizePopupOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1110:6", math.floor(v + 0.5))
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

local function MSUF_EditMode_ShowCombatWarning() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_ShowCombatWarning file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1149:6");
    if not MSUF_UnitEditModeActive then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowCombatWarning file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1149:6"); return end
    if not (InCombatLockdown and InCombatLockdown()) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowCombatWarning file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1149:6"); return end
    if MSUF__EditModeCombatWarnShownThisCombat then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowCombatWarning file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1149:6"); return end
    MSUF__EditModeCombatWarnShownThisCombat = true

    local msg = "|cffffd700MSUF Edit Mode:|r You are in combat - changes/movement will be applied after combat ends."
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
    else
        print(msg)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ShowCombatWarning file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1149:6"); end

local function MSUF_EditMode_StartCombatWarningListener() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_StartCombatWarningListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1163:6");
    if MSUF__EditModeCombatWarnFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_StartCombatWarningListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1163:6"); return end
    MSUF__EditModeCombatWarnFrame = CreateFrame("Frame")
    MSUF__EditModeCombatWarnFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    MSUF__EditModeCombatWarnFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    MSUF__EditModeCombatWarnFrame:SetScript("OnEvent", function(_, event) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1168:55");
        if event == "PLAYER_REGEN_DISABLED" then
            if MSUF_UnitEditModeActive then
                MSUF_EditMode_ShowCombatWarning()
            end
        else -- PLAYER_REGEN_ENABLED
            MSUF__EditModeCombatWarnShownThisCombat = false
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1168:55"); end)

    -- If we enter Edit Mode while already in combat, warn immediately (Das klappt nicht so richtig)
    if InCombatLockdown and InCombatLockdown() and MSUF_UnitEditModeActive then
        MSUF_EditMode_ShowCombatWarning()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_StartCombatWarningListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1163:6"); end

local function MSUF_EditMode_StopCombatWarningListener() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_StopCombatWarningListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1184:6");
    if not MSUF__EditModeCombatWarnFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_StopCombatWarningListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1184:6"); return end
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_StopCombatWarningListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1184:6"); end


local function MSUF_EditMode_HardTeardown() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_HardTeardown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1199:6");

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
            MSUF_FastCall(nudge.EnableKeyboard, nudge, false)
        end
        nudge.__msufKeyboardOn = false
        if nudge.Hide then
            MSUF_FastCall(nudge.Hide, nudge)
        end
    end
    -- Allow the combat-queue notice again next time Edit Mode is used
    MSUF__EditModeCombatNoticeShown = false
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_HardTeardown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1199:6"); end

MSUF_EditMode_FatalDisable = function(tag, err) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_FatalDisable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1254:29");
    if MSUF__EditModeFatalDisabled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_FatalDisable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1254:29"); return end
    MSUF__EditModeFatalDisabled = true
    MSUF__EditModeFatalTag = tostring(tag or "?")
    MSUF__EditModeFatalReason = tostring(err or "unknown")


    MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1261:18");
        MSUF_EM_SetFatalDisabled(MSUF__EditModeFatalTag, MSUF__EditModeFatalReason)
        MSUF_EM_SetActive(false, nil)

    -- Hard guarantee: boss unitframe preview must not persist past Edit Mode.
    MSUF_BossTestMode = false
        MSUF_EditModeSizing = false
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1261:18"); end)

    -- 2) Close popups & disable arrow nudge.
    if type(MSUF_CloseAllPositionPopups) == "function" then
        MSUF_FastCall(MSUF_CloseAllPositionPopups)
    end
    if _G and _G.MSUF_EnableArrowKeyNudge then
        MSUF_FastCall(_G.MSUF_EnableArrowKeyNudge, false)
    end

    -- 3) Hard-release keyboard catcher immediately (even if other teardown steps fail).
    local nudge = _G and _G.MSUF_ArrowKeyNudgeFrame
    if nudge then
        nudge.__msufHardKill = true
        if nudge.EnableKeyboard then MSUF_FastCall(nudge.EnableKeyboard, nudge, false) end
        if nudge.SetScript then MSUF_FastCall(nudge.SetScript, nudge, "OnKeyDown", nil) end
        if nudge.Hide then MSUF_FastCall(nudge.Hide, nudge) end
        nudge.__msufKeyboardOn = false
    end

    -- 4) Hide grid if present.
    if MSUF_GridFrame and MSUF_GridFrame.Hide then
        MSUF_FastCall(MSUF_GridFrame.Hide, MSUF_GridFrame)
    end

    -- 5) Stop timers/listeners/queues.
    MSUF_FastCall(MSUF_EditMode_HardTeardown)

    if not MSUF__EditModeFatalPrinted then
        MSUF__EditModeFatalPrinted = true
        local msg = "|cffffd700MSUF:|r Edit Mode disabled due to an error (" .. MSUF__EditModeFatalTag .. "). /reload recommended."
        if _G and _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
            _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
        else
            print(msg)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_FatalDisable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1254:29"); end

local function MSUF_EditMode_EnsureCombatListener() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_EnsureCombatListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1307:6");
    if MSUF__EditModeCombatFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_EnsureCombatListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1307:6"); return end
    MSUF__EditModeCombatFrame = CreateFrame("Frame")
    MSUF__EditModeCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    MSUF__EditModeCombatFrame:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1311:51");
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1311:51"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_EnsureCombatListener file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1307:6"); end

Edit.Secure = Edit.Secure or {}
do
    local S = Edit.Secure
    S._pending = S._pending or {} -- tag -> closure

    local function InCombat() Perfy_Trace(Perfy_GetTime(), "Enter", "InCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1349:10");
        return Perfy_Trace_Passthrough("Leave", "InCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1349:10", InCombatLockdown and InCombatLockdown())
    end

    local function HasPending() Perfy_Trace(Perfy_GetTime(), "Enter", "HasPending file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1353:10");
        for _ in pairs(S._pending) do
            Perfy_Trace(Perfy_GetTime(), "Leave", "HasPending file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1353:10"); return true
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "HasPending file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1353:10"); return false
    end

    function S.RunOrDefer(tag, fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "S.RunOrDefer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1360:4");
        if type(fn) ~= "function" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "S.RunOrDefer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1360:4"); return false
        end
        tag = tostring(tag or "Secure")

        if InCombat() then
            local args = { ... }
            S._pending[tag] = function() Perfy_Trace(Perfy_GetTime(), "Enter", "_pending.? file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1368:30");
                return Perfy_Trace_Passthrough("Leave", "_pending.? file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1368:30", fn(unpack(args)))
            end

            if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
                MSUF_EM_SetPendingSecureCleanup(true)
            end
            if type(MSUF_EditMode_EnsureCombatListener) == "function" then
                MSUF_EditMode_EnsureCombatListener()
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "S.RunOrDefer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1360:4"); return false
        end

        -- OOC: run immediately
        MSUF_SafeCall("Secure:" .. tag, fn, ...)
        if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
            MSUF_EM_SetPendingSecureCleanup(HasPending())
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "S.RunOrDefer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1360:4"); return true
    end

    -- Flush any deferred secure tasks (must be OOC).
    function S.Flush() Perfy_Trace(Perfy_GetTime(), "Enter", "S.Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1390:4");
        if InCombat() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "S.Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1390:4"); return
        end

        local had = HasPending()
        if not had then
            if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
                MSUF_EM_SetPendingSecureCleanup(false)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "S.Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1390:4"); return
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "S.Flush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1390:4"); end


    local P = Edit.Popups
    Edit.Popups.Specs = Edit.Popups.Specs or {}
    local function _MSUF_BoxNumber(box) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1420:10");
        if not box or not box.GetText then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1420:10"); return nil end
        local t = box:GetText()
        if not t or t == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1420:10"); return nil end
        return Perfy_Trace_Passthrough("Leave", "_MSUF_BoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1420:10", tonumber(t))
    end

    local function _MSUF_SetBoxNumber(box, v) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SetBoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1427:10");
        if not box or not box.SetText or v == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetBoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1427:10"); return end
        box:SetText(tostring(v))
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SetBoxNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1427:10"); end

    function P.ReadFields(pf, ctx, spec) Perfy_Trace(Perfy_GetTime(), "Enter", "P.ReadFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1432:4");
        if not pf or not spec or not spec.fields then
            return Perfy_Trace_Passthrough("Leave", "P.ReadFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1432:4", {})
        end
        ctx = ctx or {}
        local out = {}

        for _, f in ipairs(spec.fields) do
            local box = f.box and pf[f.box] or nil

            local key = f.key
            if type(key) == "function" then
                key = key(ctx)
            end

            local conf = ctx.conf
            local cur = (conf and key) and conf[key] or nil
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

        Perfy_Trace(Perfy_GetTime(), "Leave", "P.ReadFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1432:4"); return out
    end

    Edit.Popups.Specs.UnitFramePosition = Edit.Popups.Specs.UnitFramePosition or {
        fields = {
            { name="xVal", box="xBox", key="offsetX", sanitize="offset", default=0 , store=true},            { name="yVal", box="yBox", key="offsetY", sanitize="offset", default=0 , store=true},            { name="wVal", box="wBox", key="width",  sanitize="round",  default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1500:274"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1500:274", ctx.currentW) end, min=80, max=600 , store=true},            { name="hVal", box="hBox", key="height", sanitize="round",  default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1500:423"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1500:423", ctx.currentH) end, min=20, max=600 , store=true},
            { name="nameXVal",  box="nameXBox",  key="nameOffsetX",  sanitize="round", default=4 , store=true},            { name="nameYVal",  box="nameYBox",  key="nameOffsetY",  sanitize="round", default=-4 , store=true},
            { name="hpXVal",    box="hpXBox",    key="hpOffsetX",    sanitize="round", default=-4 , store=true},            { name="hpYVal",    box="hpYBox",    key="hpOffsetY",    sanitize="round", default=-4 , store=true},
            { name="powerXVal", box="powerXBox", key="powerOffsetX", sanitize="round", default=-4 , store=true},            { name="powerYVal", box="powerYBox", key="powerOffsetY", sanitize="round", default=-4 , store=true},        }
    }

    -- Castbar Position Popup (Frame offsets + size)
    Edit.Popups.Specs.CastbarFramePosition = Edit.Popups.Specs.CastbarFramePosition or {
        fields = {
            { name="xVal", box="xBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1509:43"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1509:43", (ctx.prefix or "") .. "OffsetX") end, sanitize="offset", default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1509:128"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1509:128", ctx.defaultX) end, store=true },
            { name="yVal", box="yBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1510:43"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1510:43", (ctx.prefix or "") .. "OffsetY") end, sanitize="offset", default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1510:128"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1510:128", ctx.defaultY) end, store=true },
            { name="wVal", box="wBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1511:43"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1511:43", (ctx.prefix or "") .. "BarWidth") end, sanitize="round", default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1511:128"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1511:128", ctx.currentW) end, min=50, max=600, store=true },
            { name="hVal", box="hBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1512:43"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1512:43", (ctx.prefix or "") .. "BarHeight") end, sanitize="round", default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1512:129"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1512:129", ctx.currentH) end, min=8, max=100, store=true },
        }
    }

    -- Castbar Name Text offsets
    Edit.Popups.Specs.CastbarNameOffsets = Edit.Popups.Specs.CastbarNameOffsets or {
        fields = {
            { box="castNameXBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1519:38"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1519:38", (ctx.prefix or "") .. "TextOffsetX") end, sanitize="round", default=0, store=true },
            { box="castNameYBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1520:38"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1520:38", (ctx.prefix or "") .. "TextOffsetY") end, sanitize="round", default=0, store=true },
        }
    }

    -- Castbar Time Text offsets
    Edit.Popups.Specs.CastbarTimeOffsets = Edit.Popups.Specs.CastbarTimeOffsets or {
    fields = {
        { box="timeXBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1527:30"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1527:30", (ctx.prefix or "") .. "TimeOffsetX") end, sanitize="round",
          default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1528:18"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1528:18", ctx.defaultTimeX) end, store=true },
        { box="timeYBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1529:30"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1529:30", (ctx.prefix or "") .. "TimeOffsetY") end, sanitize="round",
          default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1530:18"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1530:18", ctx.defaultTimeY) end, store=true },
    }
}
-- Castbar Icon offsets
    Edit.Popups.Specs.CastbarIconOffsets = Edit.Popups.Specs.CastbarIconOffsets or {
        fields = {
            { box="iconXBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1536:34"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1536:34", (ctx.prefix or "") .. "IconOffsetX") end, sanitize="round", default=0, store=true },
            { box="iconYBox", key=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1537:34"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1537:34", (ctx.prefix or "") .. "IconOffsetY") end, sanitize="round", default=0, store=true },
        }
    }

    -- Convenience: visibility driver refresh (calls into SecureStateDriver territory).
    function S.RequestVisibilityDrivers(active) Perfy_Trace(Perfy_GetTime(), "Enter", "S.RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1542:4");
        local want = active and true or false
        if type(MSUF_RefreshAllUnitVisibilityDrivers) ~= "function" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "S.RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1542:4"); return
        end
        S.RunOrDefer("VisibilityDrivers", MSUF_RefreshAllUnitVisibilityDrivers, want)
    Perfy_Trace(Perfy_GetTime(), "Leave", "S.RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1542:4"); end
end


function Edit.Popups.SyncFields(pf, ctx, spec) Perfy_Trace(Perfy_GetTime(), "Enter", "Popups.SyncFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1552:0");
    if not pf or not spec or not spec.fields then
        Perfy_Trace(Perfy_GetTime(), "Leave", "Popups.SyncFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1552:0"); return
    end
    ctx = ctx or {}
    local conf = ctx.conf

    for _, f in ipairs(spec.fields) do
        local box = f.box and pf[f.box] or nil
        if box and box.SetText then

            local hasFocus = (not (ctx and ctx.force)) and (box.HasFocus and box:HasFocus()) and true or false
            if not hasFocus then
                local key = f.key
                if type(key) == "function" then
                    key = key(ctx)
                end

                local cur = (conf and key) and conf[key] or nil
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
Perfy_Trace(Perfy_GetTime(), "Leave", "Popups.SyncFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1552:0"); end

local function MSUF_EditMode_RequestVisibilityDrivers(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1605:6");
    if Edit and Edit.Secure and Edit.Secure.RequestVisibilityDrivers then
        Edit.Secure.RequestVisibilityDrivers(active)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1605:6"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1605:6"); return
    end
    if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
        MSUF_SafeCall("EditMode:VisibilityDrivers", MSUF_RefreshAllUnitVisibilityDrivers, want)
    end
    if type(MSUF_EM_SetPendingSecureCleanup) == "function" then
        MSUF_EM_SetPendingSecureCleanup(false)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestVisibilityDrivers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1605:6"); end

function MSUF_EditMode_FlushPendingApplies() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_FlushPendingApplies file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1631:0");
    if InCombatLockdown and InCombatLockdown() then
        MSUF_EditMode_EnsureCombatListener()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_FlushPendingApplies file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1631:0"); return
    end

    -- If Edit Mode is no longer active, ensure nothing lingers.
    if not MSUF_UnitEditModeActive then
        MSUF_EditMode_HardTeardown()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_FlushPendingApplies file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1631:0"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_FlushPendingApplies file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1631:0"); end

local function MSUF_EditMode_RequestFlushDebounced() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_RequestFlushDebounced file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1683:6");
    MSUF__EditModeFlushSeq = (MSUF__EditModeFlushSeq or 0) + 1
    local mySeq = MSUF__EditModeFlushSeq

    MSUF_SafeAfter(MSUF_EDITMODE_APPLY_DEBOUNCE, "Debounce:EditModeFlush", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1687:75");
        if mySeq ~= MSUF__EditModeFlushSeq then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1687:75"); return end
        MSUF_EditMode_FlushPendingApplies()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1687:75"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestFlushDebounced file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1683:6"); end

local function MSUF_EditMode_QueueNoticeOnce() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_QueueNoticeOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1693:6");
    if MSUF__EditModeCombatNoticeShown then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_QueueNoticeOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1693:6"); return end
    MSUF__EditModeCombatNoticeShown = true
    print("|cffffd700MSUF:|r Änderungen werden im Kampf gepuffert und nach Kampfende angewendet.")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_QueueNoticeOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1693:6"); end

local function MSUF_EM_CombatGuardFlush() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CombatGuardFlush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1699:6");
    if InCombatLockdown and InCombatLockdown() then
        MSUF_EditMode_EnsureCombatListener()
        MSUF_EditMode_QueueNoticeOnce()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CombatGuardFlush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1699:6"); return true
    end
    MSUF_EditMode_RequestFlushDebounced()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CombatGuardFlush file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1699:6"); return false
end


local function MSUF_EditMode_RequestUnitApply(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_RequestUnitApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1710:6");
    if not key then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestUnitApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1710:6"); return end
    MSUF__EditModePendingApplies.unit[key] = true
    if MSUF_EM_CombatGuardFlush() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestUnitApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1710:6"); return end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestUnitApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1710:6"); end

local function MSUF_EditMode_RequestCastbarApply(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_RequestCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1716:6");
    if not unit then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1716:6"); return end
    MSUF__EditModePendingApplies.castbar[unit] = true
    if MSUF_EM_CombatGuardFlush() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1716:6"); return end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1716:6"); end

local function MSUF_EditMode_RequestBossCastbarApply() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_RequestBossCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1722:6");
    MSUF__EditModePendingApplies.bossCastbar = true
    if MSUF_EM_CombatGuardFlush() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestBossCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1722:6"); return end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_RequestBossCastbarApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1722:6"); end


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
        { box="wBox", key="bossCastbarWidth",   sanitize="round",  default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1751:75"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1751:75", ctx.currentW) end, min=50, max=999, store=true },
        { box="hBox", key="bossCastbarHeight",  sanitize="round",  default=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1752:75"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1752:75", ctx.currentH) end, min=8,  max=999, store=true },
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
          fallback=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1773:19"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1773:19", (ctx.conf and tonumber(ctx.conf.castbarIconOffsetX)) or 0) end },
        { box="iconYBox", key="bossCastIconOffsetY", sanitize="round", default=0, store=true,
          fallback=function(ctx) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1775:19"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1775:19", (ctx.conf and tonumber(ctx.conf.castbarIconOffsetY)) or 0) end },
    }
}

-- Used by edit-visual refresh loops
local MSUF_MAX_BOSS_FRAMES = 5

-- Unit frame registry is exported by the main file
local UnitFrames = _G.MSUF_UnitFrames or {}

-- ------------------------------------------------------------
-- Edit Mode: White Arrow (nudge buttons) visibility toggle
-- ------------------------------------------------------------
local function MSUF_EM_GetHideWhiteArrows() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetHideWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1788:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetHideWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1788:6", (MSUF_DB and MSUF_DB.general and MSUF_DB.general.editModeHideWhiteArrows) and true or false)
end

local function MSUF_EM_SetHideWhiteArrows(hide) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SetHideWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1792:6");
    if not MSUF_DB then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetHideWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1792:6"); return end
    MSUF_DB.general = MSUF_DB.general or {}
    MSUF_DB.general.editModeHideWhiteArrows = hide and true or false
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SetHideWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1792:6"); end

local function MSUF_EM_HideArrowButtonsOnFrame(fr) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_HideArrowButtonsOnFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1798:6");
    if not fr then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_HideArrowButtonsOnFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1798:6"); return end
    if fr.MSUF_ArrowLeft  and fr.MSUF_ArrowLeft.Hide  then fr.MSUF_ArrowLeft:Hide()  end
    if fr.MSUF_ArrowRight and fr.MSUF_ArrowRight.Hide then fr.MSUF_ArrowRight:Hide() end
    if fr.MSUF_ArrowUp    and fr.MSUF_ArrowUp.Hide    then fr.MSUF_ArrowUp:Hide()    end
    if fr.MSUF_ArrowDown  and fr.MSUF_ArrowDown.Hide  then fr.MSUF_ArrowDown:Hide()  end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_HideArrowButtonsOnFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1798:6"); end

-- Wrap UpdateEditArrows once so any future calls also respect the hide toggle.
local function MSUF_EM_WrapUpdateEditArrows(fr) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_WrapUpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1807:6");
    if not fr or type(fr) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_WrapUpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1807:6"); return end
    if fr.__MSUF_EM_OrigUpdateEditArrows then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_WrapUpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1807:6"); return end
    if type(fr.UpdateEditArrows) ~= "function" then
        -- No method yet; just apply hiding if needed.
        if MSUF_EM_GetHideWhiteArrows() then
            MSUF_EM_HideArrowButtonsOnFrame(fr)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_WrapUpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1807:6"); return
    end

    fr.__MSUF_EM_OrigUpdateEditArrows = fr.UpdateEditArrows
    fr.UpdateEditArrows = function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "fr.UpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1819:26");
        -- Call original first (it handles combat + edit mode active state).
        local origFn = rawget(self, "__MSUF_EM_OrigUpdateEditArrows")
        if type(origFn) == "function" then
            origFn(self, ...)
        end

        -- Force-hide if the user toggled arrows off.
        if MSUF_EM_GetHideWhiteArrows() then
            MSUF_EM_HideArrowButtonsOnFrame(self)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "fr.UpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1819:26"); end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_WrapUpdateEditArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1807:6"); end

local function MSUF_EM_RefreshWhiteArrows() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_RefreshWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1833:6");
    -- Unitframes
    if type(UnitFrames) == "table" then
        for _, fr in pairs(UnitFrames) do
            if fr then
                MSUF_EM_WrapUpdateEditArrows(fr)
                if fr.UpdateEditArrows then fr:UpdateEditArrows() end
            end
        end
    end

    -- Castbar previews (if they use arrows too)
    local p = _G.MSUF_PlayerCastbarPreview
    if p then MSUF_EM_WrapUpdateEditArrows(p); if p.UpdateEditArrows then p:UpdateEditArrows() end end
    local t = _G.MSUF_TargetCastbarPreview
    if t then MSUF_EM_WrapUpdateEditArrows(t); if t.UpdateEditArrows then t:UpdateEditArrows() end end
    local f = _G.MSUF_FocusCastbarPreview
    if f then MSUF_EM_WrapUpdateEditArrows(f); if f.UpdateEditArrows then f:UpdateEditArrows() end end
    local b = _G.MSUF_BossCastbarPreview
    if b then MSUF_EM_WrapUpdateEditArrows(b); if b.UpdateEditArrows then b:UpdateEditArrows() end end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RefreshWhiteArrows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1833:6"); end

-- fallback for MSUF_GetUnitLabelForKey (exported by main in normal builds)
if not _G.MSUF_GetUnitLabelForKey then
    _G.MSUF_GetUnitLabelForKey = function(key) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33");
        if key == "player" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); return "Player"
        elseif key == "target" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); return "Target"
        elseif key == "targettarget" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); return "Target of Target"
        elseif key == "focus" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); return "Focus"
        elseif key == "pet" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); return "Pet"
        elseif key == "boss" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); return "Boss"
        else
            return Perfy_Trace_Passthrough("Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33", key or "Unknown")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_GetUnitLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1857:33"); end
end

local function GetConfigKeyForUnit(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "GetConfigKeyForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1876:6");
    if unit == "player"
        or unit == "target"
        or unit == "focus"
        or unit == "targettarget"
        or unit == "pet"
    then
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetConfigKeyForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1876:6"); return unit
    elseif unit and unit:match("^boss%d+$") then
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetConfigKeyForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1876:6"); return "boss"
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "GetConfigKeyForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1876:6"); return nil
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

local function MSUF_CaptureEditModeSnapshot() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CaptureEditModeSnapshot file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1901:6");
    MSUF_EM_EnsureDB()
    local snap = {
        general = MSUF_CaptureKeys(MSUF_DB.general or {}, MSUF_EDITMODE_GENERAL_FIELDS),
        units = {},
    }

    for i = 1, #MSUF_EDITMODE_UNIT_KEYS do
        local k = MSUF_EDITMODE_UNIT_KEYS[i]
        snap.units[k] = MSUF_CaptureKeys(MSUF_DB[k] or {}, MSUF_EDITMODE_UNIT_FIELDS)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CaptureEditModeSnapshot file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1901:6"); return snap
end

local function MSUF_RestoreEditModeSnapshot(snap) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RestoreEditModeSnapshot file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1915:6");
    if type(snap) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RestoreEditModeSnapshot file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1915:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RestoreEditModeSnapshot file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1915:6"); end

function MSUF_BeginEditModeTransaction() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BeginEditModeTransaction file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1938:0");
    if MSUF_HasTransaction and MSUF_HasTransaction("EDITMODE") then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BeginEditModeTransaction file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1938:0"); return
    end
    local snap = MSUF_CaptureEditModeSnapshot()
    MSUF_BeginTransaction("EDITMODE", snap, MSUF_RestoreEditModeSnapshot)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BeginEditModeTransaction file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1938:0"); end

ns.MSUF_BeginEditModeTransaction = MSUF_BeginEditModeTransaction
ns.MSUF_CaptureEditModeSnapshot = MSUF_CaptureEditModeSnapshot
ns.MSUF_RestoreEditModeSnapshot = MSUF_RestoreEditModeSnapshot

local function MSUF_GetAnchorFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1950:6");
    MSUF_EM_EnsureDB()
    local g = MSUF_DB.general or {}

    if g.anchorToCooldown then
        local ecv = _G["EssentialCooldownViewer"]
        if ecv then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1950:6"); return ecv
        end
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1950:6", UIParent)
    end

    local anchorName = g.anchorName
    if anchorName and anchorName ~= "" and anchorName ~= "EssentialCooldownViewer" then
        local f = _G[anchorName]
        if f then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1950:6"); return f
        end
    end

    return Perfy_Trace_Passthrough("Leave", "MSUF_GetAnchorFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1950:6", UIParent)
end

local function MSUF_IsInEditMode() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_IsInEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1973:6");
    -- MSUF-only Edit Mode (Blizzard Edit Mode is intentionally ignored).
    local st = (type(MSUF_EM_GetState) == "function") and MSUF_EM_GetState() or nil
    if type(st) == "table" and st.active == true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsInEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1973:6"); return true
    end
    if rawget(_G, "MSUF_UnitEditModeActive") == true then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsInEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1973:6"); return true
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_IsInEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1973:6"); return false
end
local function MSUF_MakeBlizzardOptionsMovable() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_MakeBlizzardOptionsMovable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1984:6");
    -- IMPORTANT:
    -- Do NOT SetScript() on Blizzard-managed UIPanels (SettingsPanel / InterfaceOptionsFrame).
    -- That can taint UIParentPanelManager and cause ADDON_ACTION_BLOCKED during panel show/hide.
    -- Instead, we create a small drag-handle overlay that drives :StartMoving() on the panel.

    if InCombatLockdown and InCombatLockdown() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeBlizzardOptionsMovable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1984:6"); return end

    local frame = _G.SettingsPanel
    if not frame then
        frame = _G.InterfaceOptionsFrame or _G.VideoOptionsFrame or _G.AudioOptionsFrame
    end
    if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeBlizzardOptionsMovable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1984:6"); return end

    if frame.MSUF_Movable then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeBlizzardOptionsMovable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1984:6"); return
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
    if not drag then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeBlizzardOptionsMovable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1984:6"); return end

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

        drag:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2029:38");
            if InCombatLockdown and InCombatLockdown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2029:38"); return end
            local panel = self and self.GetParent and self:GetParent()
            if panel and panel.StartMoving then
                panel:StartMoving()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2029:38"); end)

        drag:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2037:37");
            local panel = self and self.GetParent and self:GetParent()
            if panel and panel.StopMovingOrSizing then
                panel:StopMovingOrSizing()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2037:37"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeBlizzardOptionsMovable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:1984:6"); end
local function MSUF_ResetCurrentEditUnit() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ResetCurrentEditUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2045:6");
    if not MSUF_CurrentEditUnitKey then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetCurrentEditUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2045:6"); return
    end

    if not EnsureDB or not MSUF_DB then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetCurrentEditUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2045:6"); return
    end

    MSUF_EM_EnsureDB()

    local key  = MSUF_CurrentEditUnitKey
    local conf = MSUF_DB[key]
    if not conf then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetCurrentEditUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2045:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetCurrentEditUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2045:6"); end
local function MSUF_CreateGridFrame() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CreateGridFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2083:6");
    if MSUF_GridFrame then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateGridFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2083:6"); return
    end

    if EnsureDB then
        MSUF_EM_EnsureDB()
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

    local function RebuildGrid(newStep) Perfy_Trace(Perfy_GetTime(), "Enter", "RebuildGrid file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2135:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "RebuildGrid file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2135:10"); end

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

    alphaSlider:SetScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2208:44");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2208:44"); end)

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

    gridSlider:SetScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2239:43");
        RebuildGrid(value)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2239:43"); end)

     f.gridSlider = gridSlider

    -- White arrows toggle (hides nudge arrows around frames)
    local arrowsBtn = ns.MSUF_EM_UIH.ButtonAt(f, "MSUF_EditModeWhiteArrowsToggle", 110, 22, "TOP", gridSlider, "BOTTOM", 0, -8, nil, "UIPanelButtonTemplate")

    local function UpdateArrowsUI() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateArrowsUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2248:10");
        local hideArrows = MSUF_EM_GetHideWhiteArrows()
        arrowsBtn:SetText(hideArrows and "Arrows: OFF" or "Arrows: ON")

        local fs = arrowsBtn:GetFontString()
        if fs and fs.SetTextColor then
            if hideArrows then
                fs:SetTextColor(0.70, 0.70, 0.70, 1)
            else
                fs:SetTextColor(0.20, 1.00, 0.20, 1)
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateArrowsUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2248:10"); end

    if arrowsBtn.HookScript then
        arrowsBtn:HookScript("OnEnter", UpdateArrowsUI)
        arrowsBtn:HookScript("OnLeave", UpdateArrowsUI)
    end

    arrowsBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2267:35");
        MSUF_EM_SetHideWhiteArrows(not MSUF_EM_GetHideWhiteArrows())
        UpdateArrowsUI()
        -- Apply immediately (unitframes + castbar previews)
        MSUF_EM_RefreshWhiteArrows()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2267:35"); end)

    UpdateArrowsUI()

    local modeBtn = ns.MSUF_EM_UIH.ButtonAt(f, "MSUF_EditModeModeButton", 210, 30, "TOP", arrowsBtn, "BOTTOM", 0, -12, nil, "UIPanelButtonTemplate")
    local modeFS = modeBtn:GetFontString()
    if modeFS then
        local font, _, flags = modeFS:GetFont()
        modeFS:SetFont(font, 14, flags or "")
    end

    local function UpdateModeButtonVisual() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateModeButtonVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2283:10");
        if MSUF_EditModeSizing then
            modeBtn:SetText("MODE: SIZE")
        else
            modeBtn:SetText("MODE: POSITION")
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateModeButtonVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2283:10"); end

    modeBtn:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2291:33");
        MSUF_EditModeSizing = not MSUF_EditModeSizing
        UpdateModeButtonVisual()
        if MSUF_UpdateEditModeInfo then
            MSUF_UpdateEditModeInfo()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2291:33"); end)

    UpdateModeButtonVisual()

    local anchorCheck = ns.MSUF_EM_UIH.TextCheck(f, "MSUF_EditModeAnchorToCooldownCheck", "TOP", modeBtn, "BOTTOM", 0, -8, "Anchor Cooldownmanager")
    MSUF_EM_EnsureDB()
    anchorCheck:SetChecked(MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorToCooldown)

    anchorCheck:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2305:37");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2305:37"); end)

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

    local function UpdateCurrentAnchorDisplay() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateCurrentAnchorDisplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2345:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateCurrentAnchorDisplay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2345:10"); end

    f._msufUpdateCurrentAnchorDisplay = UpdateCurrentAnchorDisplay
    UpdateCurrentAnchorDisplay()

    local function MSUF_ApplyCustomAnchorNameFromEditBox() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyCustomAnchorNameFromEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2362:10");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyCustomAnchorNameFromEditBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2362:10"); end

    anchorNameInput:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2380:48");
        MSUF_ApplyCustomAnchorNameFromEditBox()
        self:ClearFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2380:48"); end)

    anchorNameInput:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2385:49");
        MSUF_ApplyCustomAnchorNameFromEditBox()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2385:49"); end)

    anchorNameInput:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2389:49");
        self:ClearFocus()
        MSUF_EM_EnsureDB()
        local current = MSUF_DB and MSUF_DB.general and MSUF_DB.general.anchorName or ""
        if current == nil then
            current = ""
        end
        anchorNameInput:SetText(current)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2389:49"); end)

    local bossPreviewCheck = ns.MSUF_EM_UIH.TextCheck(f, "MSUF_EditModeBossPreviewCheck", "TOP", currentAnchorFS, "BOTTOM", 0, -12, "Preview boss frames")
    bossPreviewCheck:SetChecked(MSUF_BossTestMode and true or false)

    bossPreviewCheck:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2402:42");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2402:42"); end)

    -- Aura preview toggle (Auras 2.0)
    -- Mirrors the Auras menu setting: MSUF_DB.auras2.shared.showInEditMode
    local auraPreviewCheck = ns.MSUF_EM_UIH.TextCheck(f, "MSUF_EditModeAuraPreviewCheck", "BOTTOMLEFT", bossPreviewCheck, "TOPLEFT", 0, 2, "Preview aura frames")
    local function MSUF_EM_GetAuraPreviewEnabled() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetAuraPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2421:10");
        MSUF_EM_EnsureDB()
        local s = MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.shared
        if s and s.showInEditMode == false then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetAuraPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2421:10"); return false
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetAuraPreviewEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2421:10"); return true
    end

    auraPreviewCheck:SetChecked(MSUF_EM_GetAuraPreviewEnabled())

    auraPreviewCheck:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2432:41");
        if self and self.SetChecked then
            self:SetChecked(MSUF_EM_GetAuraPreviewEnabled())
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2432:41"); end)

    auraPreviewCheck:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2438:42");
        MSUF_EM_EnsureDB()
        if not MSUF_DB then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2438:42"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2438:42"); end)

    -- ------------------------------------------------------------
    -- ------------------------------------------------------------
-- ------------------------------------------------------------
-- Edit Mode: unit selector row (Prev/Next + ON/OFF toggle)
-- Replaces the old per-unit ON/OFF button strip (cleaner + no clutter)
-- ------------------------------------------------------------
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

    local function GetUnitIndex(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "GetUnitIndex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2485:10");
        for i, u in ipairs(units) do
            if u.key == unitKey then
                Perfy_Trace(Perfy_GetTime(), "Leave", "GetUnitIndex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2485:10"); return i
            end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetUnitIndex file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2485:10"); return 1
    end

    local function GetUnitKeyAt(i) Perfy_Trace(Perfy_GetTime(), "Enter", "GetUnitKeyAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2494:10");
        local u = units[i]
        return Perfy_Trace_Passthrough("Leave", "GetUnitKeyAt file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2494:10", (u and u.key) or "player")
    end

    local function GetUnitLabel(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "GetUnitLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2499:10");
        for _, u in ipairs(units) do
            if u.key == unitKey then
                return Perfy_Trace_Passthrough("Leave", "GetUnitLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2499:10", u.label)
            end
        end
        return Perfy_Trace_Passthrough("Leave", "GetUnitLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2499:10", tostring(unitKey or "Player"))
    end

    local function IsEnabled(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2508:10");
        MSUF_EM_EnsureDB()
        if type(MSUF_DB) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2508:10"); return true end
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        local v = MSUF_DB[unitKey].enabled
        if v == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2508:10"); return true end
        return Perfy_Trace_Passthrough("Leave", "IsEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2508:10", v and true or false)
    end

    local function ApplyEnabled(unitKey, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2517:10");
        if InCombatLockdown and InCombatLockdown() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2517:10"); return
        end
        MSUF_EM_EnsureDB()
        if type(MSUF_DB) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2517:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2517:10"); end

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

    local function Refresh() Perfy_Trace(Perfy_GetTime(), "Enter", "Refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2580:10");
        local unitKey = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        f._msufEditUnitKey = unitKey

        local on = IsEnabled(unitKey)
        toggleBtn:SetText(GetUnitLabel(unitKey) .. ": " .. (on and "ON" or "OFF"))

        local fs = toggleBtn.GetFontString and toggleBtn:GetFontString() or nil
        if fs then
            if on then
                fs:SetTextColor(0.2, 1.0, 0.2)
            else
                fs:SetTextColor(1.0, 0.2, 0.2)
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Refresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2580:10"); end

    -- Backwards-compatible name some older code paths may call
    f._msufSyncFrameEnableButtons = Refresh
    f._msufSyncEditUnitSelector = Refresh

    local function SelectUnit(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "SelectUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2601:10");
        if not unitKey then Perfy_Trace(Perfy_GetTime(), "Leave", "SelectUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2601:10"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "SelectUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2601:10"); end

    prevBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2615:33");
        local cur = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        local idx = GetUnitIndex(cur) - 1
        if idx < 1 then idx = #units end
        SelectUnit(GetUnitKeyAt(idx))
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2615:33"); end)

    nextBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2622:33");
        local cur = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        local idx = GetUnitIndex(cur) + 1
        if idx > #units then idx = 1 end
        SelectUnit(GetUnitKeyAt(idx))
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2622:33"); end)

    toggleBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2629:35");
        local unitKey = MSUF_CurrentEditUnitKey or f._msufEditUnitKey or "player"
        ApplyEnabled(unitKey, not IsEnabled(unitKey))
        Refresh()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2629:35"); end)

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
        OnAccept = function(self, data) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2660:19");
            if data and type(data.doCancel) == "function" then
                data.doCancel()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2660:19"); end,
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
cancelBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2678:31");
    if not MSUF_UnitEditModeActive then
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2678:31"); return
    end
    if InCombatLockdown and InCombatLockdown() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2678:31"); return
    end
    MSUF_EM_SetPopupOpen(true)

    local function DoCancel() Perfy_Trace(Perfy_GetTime(), "Enter", "DoCancel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2687:10");
            if type(MSUF_RollbackTransaction) == "function" and type(MSUF_HasTransaction) == "function" and MSUF_HasTransaction("EDITMODE") then
                MSUF_RollbackTransaction("EDITMODE")
                if type(ApplyAllSettings) == "function" then
                    ApplyAllSettings()
                end

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
    Perfy_Trace(Perfy_GetTime(), "Leave", "DoCancel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2687:10"); end

-- NOTE: StaticPopup is not part of our popup registry, so we must not leave popupOpen stuck TRUE.
    -- We attach a one-time OnHide hook to the shown dialog frame to reliably clear the "popupOpen" latch.
    local dlg
    if type(StaticPopup_Show) == "function" then
        dlg = StaticPopup_Show("MSUF_CONFIRM_CANCEL_EDITMODE", nil, nil, { doCancel = DoCancel })
        if dlg and dlg.HookScript and not dlg.__msufPopupOpenHooks then
            dlg.__msufPopupOpenHooks = true
            dlg:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2751:37"); MSUF_EM_SetPopupOpen(true) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2751:37"); end)
            dlg:HookScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2752:37"); MSUF_EM_SetPopupOpen(false) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2752:37"); end)
        end
        -- If StaticPopup_Show fails for any reason, fail-open: do not block dragging.
        if not dlg then
            MSUF_EM_SetPopupOpen(false)
        end
    else
        DoCancel()
        MSUF_EM_SetPopupOpen(false)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2678:31"); end)
exitBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2763:29");
        if not MSUF_UnitEditModeActive then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2763:29"); return
        end

        -- Always go through the deterministic Flow exit so popups/bindings/previews/secure drivers are cleaned up
        -- even when MSUF Edit Mode is running unlinked from Blizzard Edit Mode.
        if Edit and Edit.Flow and type(Edit.Flow.Exit) == "function" then
            Edit.Flow.Exit("button", { flushPending = true })
        else
            -- Fallback: attempt deterministic exit directly (should not happen).
            if type(MSUF_EditMode_ExitDeterministic) == "function" then
                MSUF_SafeCall("Exit:ButtonFallback", MSUF_EditMode_ExitDeterministic, "button", { flushPending = true })
            else
                if type(MSUF_CloseAllPositionPopups) == "function" then
                    MSUF_FastCall(MSUF_CloseAllPositionPopups)
                end
                MSUF_EM_SetActive(false, nil)
                if _G and _G.MSUF_EnableArrowKeyNudge then
                    MSUF_FastCall(_G.MSUF_EnableArrowKeyNudge, false)
                end
                MSUF_EditMode_HardTeardown()
            end
        end

        print("|cffffd700MSUF:|r Edit Mode |cffff0000OFF|r.")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2763:29"); end)

local resetBtn = ns.MSUF_EM_UIH.Button(f, "MSUF_EditModeResetButton", 140, 22, nil, "UIPanelButtonTemplate")
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPRIGHT", _msufExitAnchor, "BOTTOMRIGHT", -6 + _msufActionRowXShift, _msufActionRowYOffset)
    resetBtn:SetText("Reset Frame")

    -- Exit goes to the right of Reset (Reset takes the old Exit spot)
    exitBtn:ClearAllPoints()
    exitBtn:SetPoint("TOPLEFT", resetBtn, "TOPRIGHT", 12, 0)

MSUF_EM_ForceWhiteButtonText(resetBtn)

    resetBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2802:34");
        if not MSUF_UnitEditModeActive then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2802:34"); return
        end

        if not MSUF_CurrentEditUnitKey then
            if MSUF_GridFrame and MSUF_GridFrame.infoText then
                MSUF_GridFrame.infoText:SetText("Reset: Kein Frame ausgewählt – klicke zuerst ein Frame.")
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2802:34"); return
        end

        if MSUF_ResetCurrentEditUnit then
            MSUF_ResetCurrentEditUnit()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2802:34"); end)

    f.resetButton = resetBtn

    -- ------------------------------------------------------------
    -- Edit Mode UI layout refresh (visual only)
    -- Goal: clearer sections + boss preview toggle near Boss ON + bottom action bar.
    -- ------------------------------------------------------------
    local function MSUF_EM_ApplyEditModeLayout() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ApplyEditModeLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2825:10");
        -- Create headers once
        if not f._msufLayoutHeaders then
            f._msufLayoutHeaders = {}
            local function MakeHeader(txt) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeHeader file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2829:18");
                local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetText(txt)
                fs:SetJustifyH("CENTER")
                Perfy_Trace(Perfy_GetTime(), "Leave", "MakeHeader file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2829:18"); return fs
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyEditModeLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2825:10"); return
        end

        -- Mode button is the first main control under the header
        if modeBtn then
            modeBtn:ClearAllPoints()
            modeBtn:SetPoint("TOP", _info, "BOTTOM", 0, -14)
        end

        -- Positioning section
        posHeader:ClearAllPoints()
        posHeader:SetPoint("TOP", modeBtn or _info, "BOTTOM", 0, -10)

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
        framesHeader:SetPoint("TOP", arrowsBtn, "BOTTOM", _msufCenterShiftX, -14)

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
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyEditModeLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2825:10"); end

    MSUF_EM_ApplyEditModeLayout()
    f._msufApplyEditModeLayout = MSUF_EM_ApplyEditModeLayout
    f.exitButton = exitBtn

    f:Hide()
    MSUF_GridFrame = f
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateGridFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2083:6"); end
local function MSUF_UpdateEditModeInfo() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdateEditModeInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2977:6");
    if not MSUF_GridFrame or not MSUF_GridFrame.infoText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateEditModeInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2977:6"); return
    end

    local textWidget = MSUF_GridFrame.infoText

    if not MSUF_UnitEditModeActive then
        textWidget:SetText("")
        if MSUF_GridFrame.modeHint then
            MSUF_GridFrame.modeHint:Hide()
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateEditModeInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2977:6"); return
    end

    -- Keep the top "Edit Unit" selector row (Prev/Next + ON/OFF) in sync with the active edit unit.
    if MSUF_GridFrame._msufSyncEditUnitSelector then
        MSUF_GridFrame._msufSyncEditUnitSelector()
    elseif MSUF_GridFrame._msufSyncFrameEnableButtons then
        MSUF_GridFrame._msufSyncFrameEnableButtons()
    end


    MSUF_EM_EnsureDB()

    local key = MSUF_CurrentEditUnitKey
    if not key or not MSUF_DB[key] then
        if MSUF_EditModeSizing then
            textWidget:SetText("MSUF Edit Mode – MODE: SIZE")
        else
            textWidget:SetText("MSUF Edit Mode – MODE: POSITION")
        end

        if MSUF_GridFrame.modeHint then
            if MSUF_EditModeSizing then
                MSUF_GridFrame.modeHint:SetText("|cff00ff00MODE: SIZE – drag & arrows change frame SIZE.|r\n|cffaaaaaaHold SHIFT (5) / CTRL (10) / ALT (grid) for bigger steps.|r")
            else
                MSUF_GridFrame.modeHint:SetText("|cffffff00MODE: POSITION – drag & arrows move frames. Click MODE for SIZE.|r\n|cffaaaaaaHold SHIFT (5) / CTRL (10) / ALT (grid) for bigger steps.|r")
            end
            MSUF_GridFrame.modeHint:Show()
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateEditModeInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2977:6"); return
    end

    local conf  = MSUF_DB[key]
    local label = MSUF_GetUnitLabelForKey(key)

    if MSUF_EditModeSizing then
        local w = conf.width or 0
        local h = conf.height or 0
        textWidget:SetText(string.format("Sizing: %s (W: %d, H: %d)", label, w, h))
    else

    local x = MSUF_SanitizePopupOffset(conf.offsetX, 0)
    local y = MSUF_SanitizePopupOffset(conf.offsetY, 0)
    -- Auto-repair corrupted offsets so the UI and DB stay sane.
    if conf.offsetX ~= x then conf.offsetX = x end
    if conf.offsetY ~= y then conf.offsetY = y end
        textWidget:SetText(string.format("Editing: %s (X: %d, Y: %d)", label, x, y))
    end

    if MSUF_GridFrame.modeHint then
        if MSUF_EditModeSizing then
            MSUF_GridFrame.modeHint:SetText("|cff00ff00MODE: SIZE – drag & arrows change frame SIZE.|r\n|cffaaaaaaHold SHIFT (5) / CTRL (10) / ALT (grid) for bigger steps.|r")
        else
            MSUF_GridFrame.modeHint:SetText("|cffffff00MODE: POSITION – drag & arrows move frames. Click MODE for SIZE.|r\n|cffaaaaaaHold SHIFT (5) / CTRL (10) / ALT (grid) for bigger steps.|r")
        end
        MSUF_GridFrame.modeHint:Show()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateEditModeInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:2977:6"); end
local function MSUF_AttachStepperButtons(parent, editBox, onStep) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_AttachStepperButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3047:6");
    if not parent or not editBox then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AttachStepperButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3047:6"); return end

    -- Step logic matches Arrow-Key nudging:
    -- Default: 1px
    -- Shift:   5px
    -- Ctrl:    10px
    -- Alt:     Grid step (editModeGridStep) or 20px fallback
    local function GetStep() Perfy_Trace(Perfy_GetTime(), "Enter", "GetStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3055:10");
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3055:10"); return step
    end

    local function Step(sign) Perfy_Trace(Perfy_GetTime(), "Enter", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3073:10");
        -- One-time per session: show step-modifier hint when user first changes a popup value.
        MSUF_FastCall(MSUF_EditMode_ShowStepModifierTipOnce, parent)
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "Step file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3073:10"); end

    local minus = ns.MSUF_EM_UIH.ButtonAt(parent, nil, 16, 16, "LEFT", editBox, "RIGHT", 2, 0, "-", "UIPanelButtonTemplate")
    minus:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3091:31"); Step(-1) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3091:31"); end)

    local plus = ns.MSUF_EM_UIH.ButtonAt(parent, nil, 16, 16, "LEFT", minus, "RIGHT", 2, 0, "+", "UIPanelButtonTemplate")
    plus:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3094:30"); Step(1) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3094:30"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AttachStepperButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3047:6"); return minus, plus
end

-- Shared popup alignment helpers (Unitframe + Castbar popups)
-- Fixed label column width + input box size for consistent alignment.
local MSUF_POPUP_LABEL_W = 88
local MSUF_POPUP_BOX_W   = 92
local MSUF_POPUP_BOX_H   = 20

-- Returns true only for *complete* numeric strings (prevents live-apply jitter while typing '-' etc.)
local function MSUF_EM_IsCompleteNumberString(s) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_IsCompleteNumberString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3106:6");
    if s == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsCompleteNumberString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3106:6"); return false end
    s = tostring(s or '')
    -- trim whitespace
    s = s:gsub("%s+", "")
    if s == '' or s == '-' or s == '+' then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsCompleteNumberString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3106:6"); return false
    end
    -- allow integers; allow decimals just in case (even though offsets are effectively ints)
    if s:match('^[-+]?%d+$') then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsCompleteNumberString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3106:6"); return true
    end
    if s:match('^[-+]?%d+%.%d+$') then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsCompleteNumberString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3106:6"); return true
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsCompleteNumberString file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3106:6"); return false
end

local function MSUF_PopupStyleLabel(fs) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_PopupStyleLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3124:6");
    if not fs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PopupStyleLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3124:6"); return end
    fs:SetWidth(MSUF_POPUP_LABEL_W)
    fs:SetJustifyH("LEFT")
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PopupStyleLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3124:6"); end
local function MSUF_PopupStyleBox(box) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_PopupStyleBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3129:6");
    if not box then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PopupStyleBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3129:6"); return end
    box:SetSize(MSUF_POPUP_BOX_W, MSUF_POPUP_BOX_H)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PopupStyleBox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3129:6"); end

-- Compact helper: attach standard live-apply OnTextChanged handler (used by multiple popups).
local function MSUF_EM_AttachLiveApply(pf, editBox, applyFn, queueKey, requireCompleteNumber) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_AttachLiveApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3135:6");
    if not pf or not editBox or not applyFn or not editBox.SetScript then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AttachLiveApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3135:6"); return end
    queueKey = queueKey or "MSUF:LiveApply"
    editBox:SetScript("OnTextChanged", function(self, userInput) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3138:39");
        if not userInput or not self:HasFocus() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3138:39"); return end
        if requireCompleteNumber then
            local t = self:GetText()
            if not MSUF_EM_IsCompleteNumberString(t) then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3138:39"); return end
        end
        if pf._msufLiveApplyQueued then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3138:39"); return end
        pf._msufLiveApplyQueued = true
        if type(MSUF_SafeAfter) == "function" then
            MSUF_SafeAfter(0, queueKey, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3147:40");
                pf._msufLiveApplyQueued = nil
                if pf:IsShown() and self:HasFocus() then
                    applyFn()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3147:40"); end, true)
        else
            pf._msufLiveApplyQueued = nil
            applyFn()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3138:39"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_AttachLiveApply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3135:6"); end

-- Compact helper: bind Enter/Escape handlers to multiple edit boxes (used by multiple popups).
local function MSUF_EM_BindKeyScripts(onEnter, onEscape, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_BindKeyScripts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3161:6");
    for i = 1, select('#', ...) do
        local w = select(i, ...)
        if w and w.SetScript then
            if onEnter then w:SetScript('OnEnterPressed', onEnter) end
            if onEscape then w:SetScript('OnEscapePressed', onEscape) end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_BindKeyScripts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3161:6"); end

-- Compact helper: fast-apply wrapper used by multiple popups.
local function MSUF_EM_FastApplyOrPrint(applyFn, label) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_FastApplyOrPrint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3172:6");
    if type(MSUF_FastCall) == "function" then
        local ok, err = MSUF_FastCall(applyFn)
        if not ok then
            print("|cffffd700MSUF:|r " .. tostring(label or "Popup apply failed") .. ": " .. tostring(err))
        end
    else
        local ok, err = pcall(applyFn)
        if not ok then
            print("|cffffd700MSUF:|r " .. tostring(label or "Popup apply failed") .. ": " .. tostring(err))
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_FastApplyOrPrint file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3172:6"); end

-- Compact helper: binds OK button + Enter/Escape handlers for a popup.
-- OK applies and closes, Enter applies without closing, Escape clicks cancel.
local function MSUF_EM_BindOkEnterHandlers(popupFrame, okBtn, cancelBtn, applyFn, label) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_BindOkEnterHandlers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3188:6");
    if okBtn and okBtn.SetScript then
        okBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3190:35");
            MSUF_EM_FastApplyOrPrint(applyFn, label)
            if popupFrame and popupFrame.Hide then popupFrame:Hide() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3190:35"); end)
    end

    local function OnEnterPressed(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnEnterPressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3196:10");
        MSUF_EM_FastApplyOrPrint(applyFn, label)
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnEnterPressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3196:10"); end
    local function OnEscapePressed(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnEscapePressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3199:10");
        if cancelBtn and cancelBtn.Click then
            cancelBtn:Click()
        elseif popupFrame and popupFrame.Hide then
            popupFrame:Hide()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnEscapePressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3199:10"); end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_BindOkEnterHandlers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3188:6"); return OnEnterPressed, OnEscapePressed
end


-- Compact helper: restore many fields from a prev snapshot into a config table.
local function MSUF_EM_RestoreFields(dst, src, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_RestoreFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3212:6");
    if not dst or not src then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RestoreFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3212:6"); return end
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        dst[k] = src[k]
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RestoreFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3212:6"); end

local MSUF_EM_CASTBAR_PREFIX_RESTORE_SUFFIXES = {
    "OffsetX", "OffsetY", "BarWidth", "BarHeight",
    "TextOffsetX", "TextOffsetY", "ShowSpellName", "SpellNameFontSize",
    "IconOffsetX", "IconOffsetY", "ShowIcon",
    "TimeOffsetX", "TimeOffsetY", "TimeFontSize",
    "Detached",
}

local function MSUF_EM_RestorePrefixFields(dst, src, prefix, suffixes) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_RestorePrefixFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3228:6");
    if not dst or not src or not prefix or not suffixes then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RestorePrefixFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3228:6"); return end
    for i = 1, #suffixes do
        local k = prefix .. suffixes[i]
        dst[k] = src[k]
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_RestorePrefixFields file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3228:6"); end

local function MSUF_EM_CreateNumericRow(pf, labelText, boxName, anchorTo, relPoint, x, y, onStep, labelTemplate) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CreateNumericRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3236:6");
    if not pf then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CreateNumericRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3236:6"); return end
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CreateNumericRow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3236:6"); return label, box, minus, plus
end

local function MSUF_EM_CreateNumericRowStored(pf, key, labelText, boxName, anchorTo, relPoint, x, y, onStep, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CreateNumericRowStored file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3253:6");
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
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_CreateNumericRowStored file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3253:6", row or label, label, box, minus, plus)
end

local function MSUF_EM_BuildNumericRows(pf, rows, anchorTo, relPoint, x, onStep, liveTag) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_BuildNumericRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3278:6");
    local prev = anchorTo
    if not (pf and rows and prev) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_BuildNumericRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3278:6"); return prev end
    for i = 1, #rows do
        local r = rows[i]
        if r then
            local opts = (r.live or r.labelTemplate) and { liveApply = r.live, liveTag = liveTag, labelTemplate = r.labelTemplate, requireCompleteNumber = r.requireCompleteNumber } or nil
            prev = (MSUF_EM_CreateNumericRowStored(pf, r.key, r.label, r.box, prev, relPoint, x or 0, r.dy or -8, onStep, opts)) or prev
        end
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_BuildNumericRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3278:6"); return prev
end

-- Popup tooltip helper (anchors outside the popup so it never sits behind it)
local function MSUF_EM_PopupShowTooltip(popupFrame, title, warningLine) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_PopupShowTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3292:6");
    if not GameTooltip or not popupFrame or not UIParent then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_PopupShowTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3292:6"); return end

    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()

    local uiW = UIParent.GetWidth and UIParent:GetWidth() or 0
    local pr  = popupFrame.GetRight and popupFrame:GetRight() or nil
    local pl  = popupFrame.GetLeft and popupFrame:GetLeft() or nil

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_PopupShowTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3292:6"); end

-- Small helper to attach a checkbox to the right of a numeric row (Show / Override)
local function MSUF_EM_CreateRightCheckbox(pf, name, anchorFrame, textLabel, onClick, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CreateRightCheckbox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3326:6");
    local cb = CreateFrame("CheckButton", name, pf, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("LEFT", anchorFrame, "RIGHT", (opts and opts.dx) or 6, (opts and opts.dy) or 0)

    local t = cb.Text or (cb.GetName and _G[cb:GetName() .. "Text"])
    if t and textLabel then t:SetText(textLabel) end

    if opts and (opts.tooltipTitle or opts.tooltipLine) then
        cb:SetScript("OnEnter", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3335:32"); MSUF_EM_PopupShowTooltip(pf, opts.tooltipTitle, opts.tooltipLine) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3335:32"); end)
        cb:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3336:32"); if GameTooltip then GameTooltip:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3336:32"); end)
    end

    if onClick then
        cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3340:32");
            if opts and opts.beforeClick then
                opts.beforeClick(self)
            end
            if opts and opts.deferApply and C_Timer and C_Timer.After then
                MSUF_SafeAfter(0, opts.deferTag or "Popup:DeferredApply", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3345:74"); onClick(self) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3345:74"); end)
            else
                onClick(self)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3340:32"); end)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CreateRightCheckbox file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3326:6"); return cb
end

-- ---------------------------------------------------------------------------
-- Shared "spec-driven" builders for popup footer + copy dropdowns
-- Consolidates repeated UI creation across Unit / Castbar / Auras2 popups.
-- ---------------------------------------------------------------------------

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

local function MSUF_EM_ClearFocusOnBoxes(...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ClearFocusOnBoxes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3405:6");
    if not GetCurrentKeyBoardFocus then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ClearFocusOnBoxes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3405:6"); return end
    local focus = GetCurrentKeyBoardFocus()
    if not focus then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ClearFocusOnBoxes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3405:6"); return end
    for i = 1, select("#", ...) do
        local box = select(i, ...)
        if box and box == focus and box.ClearFocus then
            MSUF_FastCall(box.ClearFocus, box)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ClearFocusOnBoxes file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3405:6"); end

local function MSUF_EM_UI_BuildCopyDropdown(pf, spec) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_UI_BuildCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3417:6");
    if not (pf and spec) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3417:6"); return nil, nil end

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

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildCopyDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3417:6"); return label, drop
end

local function MSUF_EM_UI_BuildFooterButtons(pf, spec) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_UI_BuildFooterButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3442:6");
    if not (pf and spec) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildFooterButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3442:6"); return end

    local UIH = ns and ns.MSUF_EM_UIH

    local function MakeButton(bspec) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3447:10");
        if not bspec then Perfy_Trace(Perfy_GetTime(), "Leave", "MakeButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3447:10"); return nil end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MakeButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3447:10"); return btn
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildFooterButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3442:6"); return okBtn, cancelBtn, menuBtn, stepHint
end



local function MSUF_EM_UI_BuildTextBlock(pf, spec, anchorFrame, applyFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_UI_BuildTextBlock file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3508:6");
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
            onClick = function() Perfy_Trace(Perfy_GetTime(), "Enter", "onClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3544:22"); applyFn() Perfy_Trace(Perfy_GetTime(), "Leave", "onClick file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3544:22"); end
        elseif type(o.onClick) == "function" then
            onClick = o.onClick
        end

        pf[o.field] = MSUF_EM_CreateRightCheckbox(
            pf, o.name, anchor, o.text or "Override", onClick, o.opts
        )
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildTextBlock file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3508:6"); end

-- Unit Popup: Name block (already migrated in Patch 1; kept as a small helper)
local function MSUF_EM_UI_BuildUnitPopup_Text_Name(pf, textHeader, applyFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_UI_BuildUnitPopup_Text_Name file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3556:6");
    MSUF_EM_UI_BuildTextBlock(pf, {
        x = { key = "nameX", label = "Name X:", box = "$parentNameXBox", dy = -8 },
        show = { field = "nameShowCB", name = "$parentShowName", text = "Show" },
        rows = {
            { key = "nameY", label = "Name Y:", box = "$parentNameYBox", dy = -8 },
            { key = "nameSize", label = "Name Size:", box = "$parentNameSizeBox", dy = -8 },
        },
    }, textHeader, applyFn)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildUnitPopup_Text_Name file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3556:6"); end

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

local function MSUF_EM_UI_BuildUnitPopup_Text_Extras(pf, applyFn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_UI_BuildUnitPopup_Text_Extras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3626:6");
    -- Keep exact anchoring order: NameOverride, then HP anchored to NameSizeLabel, then Power anchored to HPSizeLabel.
    -- Name override
    MSUF_EM_UI_BuildTextBlock(pf, UNIT_POPUP_TEXT_EXTRA_SPEC[1], nil, applyFn)

    -- HP
    MSUF_EM_UI_BuildTextBlock(pf, UNIT_POPUP_TEXT_EXTRA_SPEC[2], pf.nameSizeLabel, applyFn)

    -- Power
    MSUF_EM_UI_BuildTextBlock(pf, UNIT_POPUP_TEXT_EXTRA_SPEC[3], pf.hpSizeLabel, applyFn)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildUnitPopup_Text_Extras file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3626:6"); end

-- Castbar Popup: spec-driven Text blocks (CastName / Icon / Time)
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
                beforeClick  = function(cb, checked) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3658:31");
                    local pf2 = cb and cb:GetParent()
                                        if pf2 and pf2.SetCastbarSizeControlsEnabled then
                        pf2.SetCastbarSizeControlsEnabled(
                            pf2.castNameSizeBox,
                            pf2.castNameSizeMinus,
                            pf2.castNameSizePlus,
                            checked and true or false
                        )
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3658:31"); end,
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
                beforeClick  = function(cb, checked) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3691:31");
                    local pf2 = cb and cb:GetParent()
                                        if pf2 and pf2.SetCastbarSizeControlsEnabled then
                        pf2.SetCastbarSizeControlsEnabled(
                            pf2.iconSizeBox,
                            pf2.iconSizeMinus,
                            pf2.iconSizePlus,
                            checked and true or false
                        )
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3691:31"); end,
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

local function MSUF_EM_UI_BuildCastbarPopup_TextBlocks(pf, textHeader) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_UI_BuildCastbarPopup_TextBlocks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3728:6");

        -- Enable/disable castbar popup controls based on Show + Override states (match Unitframe popup UX)
        pf.UpdateEnabledStates = function() Perfy_Trace(Perfy_GetTime(), "Enter", "pf.UpdateEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3731:33");
            local pf = MSUF_CastbarPositionPopup or pf
            local UI = Edit and Edit.Popups and Edit.Popups.UI
            if not (pf and UI) then Perfy_Trace(Perfy_GetTime(), "Leave", "pf.UpdateEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3731:33"); return end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "pf.UpdateEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3731:33"); end

    -- Ensure size-control toggler exists before creating override checkboxes (beforeClick uses it).
    pf.SetCastbarSizeControlsEnabled = Edit and Edit.Popups and Edit.Popups.UI and Edit.Popups.UI.SetSizeControlsEnabled

    MSUF_EM_UI_BuildTextBlock(pf, CASTBAR_POPUP_TEXT_SPEC[1], textHeader, ApplyCastbarPopupValues)
    MSUF_EM_UI_BuildTextBlock(pf, CASTBAR_POPUP_TEXT_SPEC[2], pf.castNameSizeLabel, ApplyCastbarPopupValues)
    MSUF_EM_UI_BuildTextBlock(pf, CASTBAR_POPUP_TEXT_SPEC[3], pf.iconSizeLabel, ApplyCastbarPopupValues)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_UI_BuildCastbarPopup_TextBlocks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3728:6"); end
local function MSUF_InitEditPopupFrame
(pf, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_InitEditPopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3782:6");
    if not pf or not opts then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitEditPopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3782:6"); return end

    local w = opts.w or 320
    local h = opts.h or 430
    pf:SetSize(w, h)

    pf:SetFrameStrata(opts.strata or "FULLSCREEN_DIALOG")
    pf:SetFrameLevel(opts.level or 500)
    pf:SetClampedToScreen(true)

    pf:SetMovable(true)
    pf:EnableMouse(true)
    pf:RegisterForDrag("LeftButton")

    pf:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3798:32");
        if self:IsMovable() then
            self:StartMoving()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3798:32"); end)
    pf:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3803:31");
        self:StopMovingOrSizing()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3803:31"); end)

    if opts.backdrop then
        pf:SetBackdrop(opts.backdrop)
    end
    if opts.backdropColor then
        local r, g, b, a = opts.backdropColor[1], opts.backdropColor[2], opts.backdropColor[3], opts.backdropColor[4]
        pf:SetBackdropColor(r or 0, g or 0, b or 0, a or 1)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitEditPopupFrame file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3782:6"); end
local function MSUF_PositionPopupSmart(pf, parent, offset) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_PositionPopupSmart file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3815:6");
    if not pf or not parent then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PositionPopupSmart file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3815:6"); return end
    offset = offset or 200

    local ui = UIParent
    if not ui or not ui.GetWidth then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PositionPopupSmart file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3815:6"); return end

    local sw = ui:GetWidth() or 0
    local sh = ui:GetHeight() or 0
    if sw <= 0 or sh <= 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PositionPopupSmart file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3815:6"); return end

    local l = parent:GetLeft()
    local r = parent:GetRight()
    local t = parent:GetTop()
    local b = parent:GetBottom()
    if not (l and r and t and b) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PositionPopupSmart file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3815:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_PositionPopupSmart file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3815:6"); end

-- One-time cleanup: remove the big background box that can appear behind the "Copy ... settings to..." dropdowns.
-- We keep the dropdowns themselves intact; this only hides a separate container/background frame if present.
local function MSUF_EM_KillCopyDropdownGroupBG(pf, d1, d2) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_KillCopyDropdownGroupBG file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3878:6");
    if not pf or pf._msufCopyGroupBGKilled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_KillCopyDropdownGroupBG file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3878:6"); return end
    if not d1 or not d2 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_KillCopyDropdownGroupBG file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3878:6"); return end
    if not (pf.GetChildren and d1.GetLeft and d2.GetLeft) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_KillCopyDropdownGroupBG file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3878:6"); return end

    local l1, r1, t1, b1 = d1:GetLeft(), d1:GetRight(), d1:GetTop(), d1:GetBottom()
    local l2, r2, t2, b2 = d2:GetLeft(), d2:GetRight(), d2:GetTop(), d2:GetBottom()
    if not (l1 and r1 and t1 and b1 and l2 and r2 and t2 and b2) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_KillCopyDropdownGroupBG file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3878:6"); return end

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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_KillCopyDropdownGroupBG file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3878:6"); end

local function MSUF_EM_EnsureCopyDropdownGroupBGKilled(pf, d1, d2) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_EnsureCopyDropdownGroupBGKilled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3913:6");
    if not pf or pf._msufCopyGroupBGHooked then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureCopyDropdownGroupBGKilled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3913:6"); return end
    pf._msufCopyGroupBGHooked = true

    local function run() Perfy_Trace(Perfy_GetTime(), "Enter", "run file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3917:10");
        if not pf or (pf.IsShown and not pf:IsShown()) then Perfy_Trace(Perfy_GetTime(), "Leave", "run file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3917:10"); return end
        MSUF_EM_KillCopyDropdownGroupBG(pf, d1, d2)
    Perfy_Trace(Perfy_GetTime(), "Leave", "run file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3917:10"); end

    if pf.HookScript then
        pf:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3923:32");
            if C_Timer and C_Timer.After then
                C_Timer.After(0, run)
            else
                run()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3923:32"); end)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureCopyDropdownGroupBGKilled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3913:6"); end


local function MSUF_OpenPositionPopup(unit, parent) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6");
    if not MSUF_UnitEditModeActive then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); return
    end

    if not MSUF_EM_EnsureDB() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); return
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

    local function ApplyUnitPopupValues() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyUnitPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3968:10");
        if MSUF__UnitPopupSyncing or MSUF__UnitPopupApplying then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyUnitPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3968:10"); return
        end

        MSUF__UnitPopupApplying = true
        local ok, err = MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3974:38");
            if InCombatLockdown and InCombatLockdown() then
                print("|cffffd700MSUF:|r Position/Größe kann im Kampf nicht geändert werden.")
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3974:38"); return
            end

            MSUF_EM_EnsureDB()
            local pf = MSUF_PositionPopup
            if not pf or not pf.unit or not pf.parent then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3974:38"); return
            end

            local key = GetConfigKeyForUnit(pf.unit)
            local conf = key and MSUF_DB[key]
            if not conf then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3974:38"); return
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3974:38"); end)
        MSUF__UnitPopupApplying = false
        if not ok then
            error(err)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyUnitPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3968:10"); end

    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Position/Größe kann im Kampf nicht geändert werden.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); return
    end
    if not unit or not parent then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); return
    end

    MSUF_EM_EnsureDB()
    local key = GetConfigKeyForUnit(unit)
    if not key then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); return
    end

    local conf = MSUF_DB[key]
    if not conf then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); return
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
            w = 320,
            h = 480,
            backdrop = {
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            },
            backdropColor = { 0, 0, 0, 0.9 },
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
        local textDivider = MSUF_EM_AddDivider(pf, "textDivider", 290, "TOPLEFT", pf.hLabel, "BOTTOMLEFT", 0, -8)
        local textHeader  = MSUF_EM_AddSectionHeader(pf, "textHeader", "Text", "TOPLEFT", textDivider, "BOTTOMLEFT", 0, -8)


        
        -- Text offsets + per-unit font overrides (Phase 9 shrink)

                -- Name (spec-driven)
        MSUF_EM_UI_BuildUnitPopup_Text_Name(pf, textHeader, ApplyUnitPopupValues)

        pf.SetTextSizeControlsEnabled = Edit.Popups.UI.SetSizeControlsEnabled

        -- Enable/disable controls based on Show + Override states
        pf.UpdateEnabledStates = function() Perfy_Trace(Perfy_GetTime(), "Enter", "pf.UpdateEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4161:33");
            local pf = MSUF_PositionPopup
            if not pf then Perfy_Trace(Perfy_GetTime(), "Leave", "pf.UpdateEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4161:33"); return end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "pf.UpdateEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4161:33"); end

                -- Text blocks after Name (spec-driven; no behavior change)
        MSUF_EM_UI_BuildUnitPopup_Text_Extras(pf, ApplyUnitPopupValues)

-- Copy dropdowns + footer (spec-driven; no behavior change)
        local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
        local US = UISpec and UISpec.Unit

        if US and US.copyDropdowns then
            MSUF_EM_UI_BuildCopyDropdown(pf, US.copyDropdowns.size)
            MSUF_EM_UI_BuildCopyDropdown(pf, US.copyDropdowns.text)
        end
        pf.RefreshCopySizeDropdown = function() Perfy_Trace(Perfy_GetTime(), "Enter", "pf.RefreshCopySizeDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4213:37");
            local p = MSUF_PositionPopup or pf
            MSUF_EM_RefreshUnitCopyDropdown(p, p.copySizeDrop, p.copySizeLabel, "Copy size settings to...", "size")
        Perfy_Trace(Perfy_GetTime(), "Leave", "pf.RefreshCopySizeDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4213:37"); end

        pf.RefreshCopyTextDropdown = function() Perfy_Trace(Perfy_GetTime(), "Enter", "pf.RefreshCopyTextDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4218:37");
            local p = MSUF_PositionPopup or pf
            MSUF_EM_RefreshUnitCopyDropdown(p, p.copyTextDrop, p.copyTextLabel, "Copy text settings to...", "text")
        Perfy_Trace(Perfy_GetTime(), "Leave", "pf.RefreshCopyTextDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4218:37"); end

        local okBtn, cancelBtn, menuBtn = MSUF_EM_UI_BuildFooterButtons(pf, (US and US.footer) or nil)

        if menuBtn then
            menuBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4226:41");
                if type(MSUF_EM_SuppressNextBlizzardExit) == "function" then MSUF_EM_SuppressNextBlizzardExit() end
                local p = MSUF_PositionPopup
                local key = p and p.MSUF_prev and p.MSUF_prev.key
                if key and type(_G.MSUF_OpenOptionsToUnitMenu) == "function" then
                    _G.MSUF_OpenOptionsToUnitMenu(key)
                end
                pf:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4226:41"); end)
        end

        cancelBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4237:39");
            if InCombatLockdown and InCombatLockdown() then
                if MSUF_PositionPopup and MSUF_PositionPopup.Hide then MSUF_PositionPopup:Hide() end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4237:39"); return
            end
            MSUF_EM_EnsureDB()
            local pf = MSUF_PositionPopup
            if pf and pf.MSUF_prev and pf.MSUF_prev.key then
                local key = pf.MSUF_prev.key
                MSUF_DB[key] = MSUF_DB[key] or {}
                local conf = MSUF_DB[key]
                MSUF_EM_RestoreFields(conf, pf.MSUF_prev,
                    "offsetX","offsetY","width","height",
                    "nameOffsetX","nameOffsetY","hpOffsetX","hpOffsetY","powerOffsetX","powerOffsetY",
                    "showName","showHP","showPower",
                    "nameFontSize","hpFontSize","powerFontSize"
                )
                if ApplySettingsForKey then
                    ApplySettingsForKey(key)
                elseif ApplyAllSettings then
                    ApplyAllSettings()
                end
                if _G.MSUF_UpdateAllFonts then _G.MSUF_UpdateAllFonts() end
            end
            MSUF_PositionPopup:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4237:39"); end)

        local OnEnterPressed, OnEscapePressed = MSUF_EM_BindOkEnterHandlers(pf, okBtn, cancelBtn, ApplyUnitPopupValues, "Popup apply failed")

        MSUF_EM_BindKeyScripts(OnEnterPressed, OnEscapePressed,
            pf.xBox, pf.yBox, pf.wBox, pf.hBox, pf.spacingBox,
            pf.nameXBox, pf.nameYBox, pf.nameSizeBox,
            pf.hpXBox, pf.hpYBox, pf.hpSizeBox,
            pf.powerXBox, pf.powerYBox, pf.powerSizeBox
        )
    end

    -- Ensure popup is large enough for all controls (e.g. power icon size override).
    -- Also applies when the popup already exists (created earlier in the session).
    do
        local pf = MSUF_PositionPopup
        if pf and pf.SetSize then
            pf:SetSize(320, 470)

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
    pf.title:SetText(string.format("MSUF Edit – %s", label))

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

    if pf.nameSizeBox then
        pf.nameSizeBox:SetText(tostring((conf.nameFontSize) or globalNameSize))
    end
    if pf.nameOverrideCB and pf.nameOverrideCB.SetChecked then
        pf.nameOverrideCB:SetChecked(conf.nameFontSize ~= nil)
    end
    if pf.SetTextSizeControlsEnabled then
        pf.SetTextSizeControlsEnabled(pf.nameSizeBox, pf.nameSizeMinus, pf.nameSizePlus, (conf.nameFontSize ~= nil) and (conf.showName ~= false))
    end

    if pf.hpSizeBox then
        pf.hpSizeBox:SetText(tostring((conf.hpFontSize) or globalHPSize))
    end
    if pf.hpOverrideCB and pf.hpOverrideCB.SetChecked then
        pf.hpOverrideCB:SetChecked(conf.hpFontSize ~= nil)
    end
    if pf.SetTextSizeControlsEnabled then
        pf.SetTextSizeControlsEnabled(pf.hpSizeBox, pf.hpSizeMinus, pf.hpSizePlus, (conf.hpFontSize ~= nil) and (conf.showHP ~= false))
    end

    if pf.powerSizeBox then
        pf.powerSizeBox:SetText(tostring((conf.powerFontSize) or globalPowSize))
    end
    if pf.powerOverrideCB and pf.powerOverrideCB.SetChecked then
        pf.powerOverrideCB:SetChecked(conf.powerFontSize ~= nil)
    end
    if pf.SetTextSizeControlsEnabled then
        pf.SetTextSizeControlsEnabled(pf.powerSizeBox, pf.powerSizeMinus, pf.powerSizePlus, (conf.powerFontSize ~= nil) and (conf.showPower ~= false))
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
    -- Smart open: only position when the popup is opened for a new frame.
    -- If it is already open for this unit, do NOT snap it back (user may have moved it).
    if needReposition then
        MSUF_PositionPopupSmart(pf, parent, 200)
    end
    if pf.UpdateEnabledStates then pf.UpdateEnabledStates() end
pf.MSUF_prev = pf.MSUF_prev or {}
pf.MSUF_prev.key = key
pf.MSUF_prev.offsetX = conf.offsetX
pf.MSUF_prev.offsetY = conf.offsetY
pf.MSUF_prev.width   = conf.width
pf.MSUF_prev.height  = conf.height
pf.MSUF_prev.nameOffsetX = conf.nameOffsetX
pf.MSUF_prev.nameOffsetY = conf.nameOffsetY
pf.MSUF_prev.showName = conf.showName

pf.MSUF_prev.hpOffsetX = conf.hpOffsetX
pf.MSUF_prev.hpOffsetY = conf.hpOffsetY
pf.MSUF_prev.showHP    = conf.showHP
pf.MSUF_prev.powerOffsetX = conf.powerOffsetX
pf.MSUF_prev.powerOffsetY = conf.powerOffsetY
pf.MSUF_prev.showPower    = conf.showPower
pf.MSUF_prev.nameFontSize  = conf.nameFontSize
pf.MSUF_prev.hpFontSize    = conf.hpFontSize
pf.MSUF_prev.powerFontSize = conf.powerFontSize
    pf:Show()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:3934:6"); end
local function MSUF_UpdateCastbarEditInfo(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdateCastbarEditInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4396:6");
    if not MSUF_GridFrame or not MSUF_GridFrame.infoText then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCastbarEditInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4396:6"); return
    end
    if not MSUF_UnitEditModeActive then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCastbarEditInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4396:6"); return
    end

    MSUF_EM_EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    local prefix = MSUF_GetCastbarPrefix(unit)
    local label  = MSUF_GetCastbarLabel(unit)
    if not prefix then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCastbarEditInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4396:6"); return
    end

    local textWidget = MSUF_GridFrame.infoText

    if MSUF_EditModeSizing then
        local w = g[prefix .. "BarWidth"]  or g.castbarGlobalWidth  or 0
        local h = g[prefix .. "BarHeight"] or g.castbarGlobalHeight or 0
        textWidget:SetText(string.format("Sizing: %s (W: %d, H: %d)", label, w, h))
    else
        local defaultX, defaultY
        if unit == "player" then
            defaultX, defaultY = 0, 5
        else
            defaultX, defaultY = 65, -15
        end

        local x = g[prefix .. "OffsetX"] or defaultX
        local y = g[prefix .. "OffsetY"] or defaultY
        textWidget:SetText(string.format("Editing: %s (X: %d, Y: %d)", label, x, y))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateCastbarEditInfo file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4396:6"); end
local function MSUF_UpdateGridOverlay() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdateGridOverlay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4432:6");
    if not MSUF_UnitEditModeActive then
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
            if MSUF_GridFrame.modeHint then
                MSUF_GridFrame.modeHint:Hide()
            end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateGridOverlay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4432:6"); return
    end

    if InCombatLockdown and InCombatLockdown() then
        if MSUF_GridFrame then
            MSUF_GridFrame:Hide()
            if MSUF_GridFrame.modeHint then
                MSUF_GridFrame.modeHint:Hide()
            end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateGridOverlay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4432:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateGridOverlay file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4432:6"); end
function MSUF_OpenCastbarPositionPopup(unit, parent) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0");
    if not MSUF_UnitEditModeActive then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0"); return
    end

    if not MSUF_EM_EnsureDB() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0"); return
    end
    if not unit or not parent then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0"); return
    end
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffd700MSUF:|r Position/Größe der Castbar kann im Kampf nicht geändert werden.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0"); return
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


    ApplyCastbarPopupValues = function() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyCastbarPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4498:30");
        if InCombatLockdown and InCombatLockdown() then
            if _G.MSUF_CastbarPositionPopup and _G.MSUF_CastbarPositionPopup.Hide then
                _G.MSUF_CastbarPositionPopup:Hide()
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyCastbarPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4498:30"); return
        end
        if MSUF__CastbarPopupSyncing or MSUF__CastbarPopupApplying then
            Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyCastbarPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4498:30"); return
        end

        MSUF__CastbarPopupApplying = true
        local ok, err = MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4510:38");
            MSUF_EM_EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general

            local pf = _G.MSUF_CastbarPositionPopup
            if not pf or not pf.unit or not pf.parent then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4510:38"); return
            end

            local P = Edit and Edit.Popups
            local specs = P and P.Specs
            local U = P and P.Util
            if not (P and specs and U and P.ReadFields) then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4510:38"); return
            end

            -- Always read the active popup context from the panel (prevents stale/old-unit writes).
            local unit = pf._msufUnitKey or pf.unit
            local parent = pf.parent

            local function GlobalCastFont() Perfy_Trace(Perfy_GetTime(), "Enter", "GlobalCastFont file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4531:18");
                local baseSize = tonumber(g.fontSize) or 14
                local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
                return Perfy_Trace_Passthrough("Leave", "GlobalCastFont file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4531:18", (globalOverride and globalOverride > 0) and globalOverride or baseSize)
            end

            -- ---------------------------------------
            -- Boss Castbar (stored on g via bossCast*)
            -- ---------------------------------------
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
                    MSUF_FastCall(_G.MSUF_UpdateBossCastbarPreview)
                end
                if type(_G.MSUF_SyncBossCastbarSliders) == "function" then
                    _G.MSUF_SyncBossCastbarSliders()
                end
                if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                    _G.MSUF_SyncCastbarPositionPopup("boss")
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4510:38"); return
            end

            -- ---------------------------------------
            -- Player / Target / Focus Castbars (prefix keys)
            -- ---------------------------------------
            local prefix = pf._msufDbPrefix or ((type(_G.MSUF_GetCastbarPrefix) == "function") and _G.MSUF_GetCastbarPrefix(unit) or nil)
            if not prefix then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4510:38"); return
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

            local showKey = (type(_G.MSUF_GetCastbarShowTimeKey) == "function") and _G.MSUF_GetCastbarShowTimeKey(unit) or nil
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

            -- test mode toggles (unchanged behavior)
            if type(_G.MSUF_SetPlayerCastbarTestMode) == "function" then
                local popup = _G.MSUF_CastbarPositionPopup
                local want = (unit == "player") and popup and popup.IsShown and popup:IsShown() and popup.unit == "player"
                _G.MSUF_SetPlayerCastbarTestMode(want, true)
            end
            if type(_G.MSUF_SetTargetCastbarTestMode) == "function" then
                local popup = _G.MSUF_CastbarPositionPopup
                local want = (unit == "target") and popup and popup.IsShown and popup:IsShown() and popup.unit == "target"
                _G.MSUF_SetTargetCastbarTestMode(want, true)
            end
            if type(_G.MSUF_SetFocusCastbarTestMode) == "function" then
                local popup = _G.MSUF_CastbarPositionPopup
                local want = (unit == "focus") and popup and popup.IsShown and popup:IsShown() and popup.unit == "focus"
                _G.MSUF_SetFocusCastbarTestMode(want, true)
            end
            if type(_G.MSUF_SetBossCastbarTestMode) == "function" then
                local popup = _G.MSUF_CastbarPositionPopup
                local want = (unit == "boss") and popup and popup.IsShown and popup:IsShown() and popup.unit == "boss"
                _G.MSUF_SetBossCastbarTestMode(want, true)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4510:38"); end)

        MSUF__CastbarPopupApplying = false
        if not ok then
            error(err)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyCastbarPopupValues file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4498:30"); end

    MSUF_EM_EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general

local prefix
local defaultX, defaultY
local curX, curY, curW, curH

local function SanitizeOffset(v, default) Perfy_Trace(Perfy_GetTime(), "Enter", "SanitizeOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4696:6");
    v = tonumber(v) or default or 0
    if v > 2000 then
        v = default or 0
    elseif v < -2000 then
        v = default or 0
    end
    return Perfy_Trace_Passthrough("Leave", "SanitizeOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4696:6", math.floor(v + 0.5))
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0"); return
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
            backdrop = {
                bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile     = true,
                tileSize = 32,
                edgeSize = 16,
                insets   = { left = 4, right = 4, top = 4, bottom = 4 },
            },
            backdropColor = { 0, 0, 0, 0.9 },
        })
        MSUF_EM_AddPopupTitleAndClose(pf, "MSUF Edit – Castbar")
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



                -- Castbar Text blocks (spec-driven; no behavior change)
        MSUF_EM_UI_BuildCastbarPopup_TextBlocks(pf, textHeader)

local function _MSUF_EM_GetFrameCenterOffsets(frame, anchorFrame) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EM_GetFrameCenterOffsets file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4772:6");
            if not frame or not anchorFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetFrameCenterOffsets file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4772:6"); return 0, 0 end
            local fx, fy = frame:GetCenter()
            local ax, ay = anchorFrame:GetCenter()
            if not fx or not fy or not ax or not ay then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetFrameCenterOffsets file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4772:6"); return 0, 0 end
            return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetFrameCenterOffsets file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4772:6", (fx - ax), (fy - ay))
        end


        local function _MSUF_EM_GetBottomCenter(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EM_GetBottomCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4781:14");
            if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetBottomCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4781:14"); return nil end
            local l, r, b = frame:GetLeft(), frame:GetRight(), frame:GetBottom()
            if not l or not r or not b then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetBottomCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4781:14"); return nil end
            return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetBottomCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4781:14", (l + r) * 0.5, b)
        end


        local function _MSUF_EM_GetTopCenter(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EM_GetTopCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4789:14");
            if not frame then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetTopCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4789:14"); return nil end
            local l, r, t = frame:GetLeft(), frame:GetRight(), frame:GetTop()
            if not l or not r or not t then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetTopCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4789:14"); return nil end
            return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetTopCenter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4789:14", (l + r) * 0.5, t)
        end        local function _MSUF_EM_GetRealCastbarForUnit(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EM_GetRealCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4794:25");
            if unit == "player" then return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetRealCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4794:25", _G.MSUF_PlayerCastbar) end
            if unit == "target" then return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetRealCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4794:25", _G.MSUF_TargetCastbar) end
            if unit == "focus" then return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetRealCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4794:25", _G.MSUF_FocusCastbar) end
            if unit == "boss" then
                -- There are multiple boss castbars; for offset conversions we use boss preview #1 when available.
                return Perfy_Trace_Passthrough("Leave", "_MSUF_EM_GetRealCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4794:25", _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"] or nil)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_GetRealCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4794:25"); return nil
        end        local function _MSUF_EM_ReanchorCastbarForUnit(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EM_ReanchorCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4803:25");

            if unit == "boss" then
                if type(_G.MSUF_ApplyBossCastbarPositionSetting) == "function" then
                    pcall(_G.MSUF_ApplyBossCastbarPositionSetting)
                end
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                    pcall(_G.MSUF_UpdateBossCastbarPreview)
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_ReanchorCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4803:25"); return
            end

            if unit == "player" then
                if type(_G.MSUF_ReanchorPlayerCastBar) == "function" then
                    pcall(_G.MSUF_ReanchorPlayerCastBar)
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_ReanchorCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4803:25"); return
            end

            if unit == "target" then
                if type(_G.MSUF_ReanchorTargetCastBar) == "function" then
                    pcall(_G.MSUF_ReanchorTargetCastBar)
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_ReanchorCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4803:25"); return
            end

            if unit == "focus" then
                if type(_G.MSUF_ReanchorFocusCastBar) == "function" then
                    pcall(_G.MSUF_ReanchorFocusCastBar)
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_ReanchorCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4803:25"); return
            end

            -- Fallback: try using prefix-based reanchor name (legacy support)
            local prefix = (type(_G.MSUF_GetCastbarPrefix) == "function") and _G.MSUF_GetCastbarPrefix(unit) or nil
            if prefix and type(prefix) == "string" then
                local pretty = prefix:gsub("^castbar", "")
                if pretty and pretty ~= "" then
                    local fn = _G["MSUF_Reanchor" .. pretty .. "CastBar"]
                    if type(fn) == "function" then
                        pcall(fn)
                    end
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_ReanchorCastbarForUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4803:25"); end

        local function _MSUF_EM_SetCastbarAnchoredToUnit(unit, anchored) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14");
            if not unit then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); return end

            local g = MSUF_DB and MSUF_DB.general
            if not g then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); return end

            -- Keys for offset + detached state
            local detachedKey, oxKey, oyKey
            local anchorMode = "unit" -- or "player" (special) / "boss"

            if unit == "boss" then
                detachedKey = "bossCastbarDetached"
                oxKey = "bossCastbarOffsetX"
                oyKey = "bossCastbarOffsetY"
                anchorMode = "boss"
            else
                local prefix = _G.MSUF_GetCastbarPrefix and _G.MSUF_GetCastbarPrefix(unit)
                if not prefix then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); return end
                detachedKey = prefix .. "Detached"
                oxKey = prefix .. "OffsetX"
                oyKey = prefix .. "OffsetY"
                if unit == "player" then
                    anchorMode = "player"
                end
            end

            local castbar = _MSUF_EM_GetRealCastbarForUnit(unit)
            if not castbar then
                -- Best-effort fallback to previews in Edit Mode
                if unit == "player" then castbar = _G.MSUF_PlayerCastbarPreview
                elseif unit == "target" then castbar = _G.MSUF_TargetCastbarPreview
                elseif unit == "focus" then castbar = _G.MSUF_FocusCastbarPreview
                elseif unit == "boss" then castbar = _G.MSUF_BossCastbarPreview or _G["MSUF_BossCastbarPreview1"] end
            end
            if not castbar then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); return end

            local wantDetached = (anchored == false)
            local wasDetached = (g[detachedKey] == true)
            if wantDetached == wasDetached then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); return
            end

            -- Always detach to UIParent (per your request)
            local anchorFrame = UIParent

            if wantDetached then
                -- Convert current position to CENTER offsets relative to UIParent
                local dx, dy = _MSUF_EM_GetFrameCenterOffsets(castbar, anchorFrame)
                g[oxKey] = dx
                g[oyKey] = dy
                g[detachedKey] = true
            else
                -- Convert current position back to offsets relative to the owning unitframe
                local unitframe
                if anchorMode == "boss" then
                    unitframe = _G.MSUF_boss1 or (UnitFrames and UnitFrames["boss1"]) or (UnitFrames and UnitFrames["boss"]) or nil
                else
                    unitframe = UnitFrames and UnitFrames[unit]
                end
                if not unitframe or not unitframe.GetCenter then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); return
                end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_EM_SetCastbarAnchoredToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4849:14"); end

        -- Anchor-to-Unitframe toggle (per-castbar). Default ON = anchored, OFF = detached (free move).
        -- (Restored for spec-driven popup builder; some refactor paths omitted this control.)
        if not pf.anchorToUnitCB then
            pf.anchorToUnitCB = CreateFrame("CheckButton", nil, pf, "UICheckButtonTemplate")
            pf.anchorToUnitCB:SetPoint("BOTTOMLEFT", 14, 78)
            if pf.anchorToUnitCB.Text then
                pf.anchorToUnitCB.Text:SetText("Anchor to unitframe")
            end
            pf.anchorToUnitCB:SetChecked(true)
        end
        if pf.anchorToUnitCB then
            pf.anchorToUnitCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4946:51");
                local p = MSUF_CastbarPositionPopup
                local unit = p and p.unit
                if not unit then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4946:51"); return
                end
                local anchored = self:GetChecked() and true or false
                _MSUF_EM_SetCastbarAnchoredToUnit(unit, anchored)
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4946:51"); end)
        end
        -- testModeCB is optional/legacy (some builds create it in other modules). Never assume it exists.
        if pf.testModeCB then
            pf.testModeCB:Hide()
        end

        -- Copy dropdowns + footer (spec-driven; no behavior change)
        local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
        local CS = UISpec and UISpec.Castbar

        if CS and CS.copyDropdowns then
            MSUF_EM_UI_BuildCopyDropdown(pf, CS.copyDropdowns.size)
            MSUF_EM_UI_BuildCopyDropdown(pf, CS.copyDropdowns.text)
        end

        -- Copy dropdowns (castbar) keep the exact same behavior as before (boss uses boss keys; others use castbar prefix).
        pf.RefreshCopySizeDropdown = function() Perfy_Trace(Perfy_GetTime(), "Enter", "pf.RefreshCopySizeDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4971:37");
            MSUF_EM_RefreshCastbarCopyDropdown(pf, pf.copySizeDrop, pf.copySizeLabel, "Copy size settings to...", "size")
        Perfy_Trace(Perfy_GetTime(), "Leave", "pf.RefreshCopySizeDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4971:37"); end

        pf.RefreshCopyTextDropdown = function() Perfy_Trace(Perfy_GetTime(), "Enter", "pf.RefreshCopyTextDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4975:37");
            MSUF_EM_RefreshCastbarCopyDropdown(pf, pf.copyTextDrop, pf.copyTextLabel, "Copy text settings to...", "text")
        Perfy_Trace(Perfy_GetTime(), "Leave", "pf.RefreshCopyTextDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4975:37"); end

        local okBtn, cancelBtn, menuBtn = MSUF_EM_UI_BuildFooterButtons(pf, (CS and CS.footer) or nil)

        if menuBtn then
            menuBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4982:41");
                if type(MSUF_EM_SuppressNextBlizzardExit) == "function" then MSUF_EM_SuppressNextBlizzardExit() end
                local p = MSUF_CastbarPositionPopup
                local unit = p and p.unit
                if unit and type(_G.MSUF_OpenOptionsToCastbarMenu) == "function" then
                    _G.MSUF_OpenOptionsToCastbarMenu(unit)
                end
                pf:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4982:41"); end)
        end

        cancelBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4993:39");
            if InCombatLockdown and InCombatLockdown() then
                if MSUF_CastbarPositionPopup and MSUF_CastbarPositionPopup.Hide then MSUF_CastbarPositionPopup:Hide() end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4993:39"); return
            end
            MSUF_EM_EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            local pf = MSUF_CastbarPositionPopup
            if pf and pf.MSUF_prev then
                local unit = pf.MSUF_prev.unit
                if unit == "boss" then
                    MSUF_EM_RestoreFields(g, pf.MSUF_prev,
                        "bossCastbarOffsetX","bossCastbarOffsetY","bossCastbarWidth","bossCastbarHeight",
                        "bossCastTextOffsetX","bossCastTextOffsetY","showBossCastName","bossCastSpellNameFontSize",
                        "bossCastIconOffsetX","bossCastIconOffsetY","showBossCastIcon",
                        "bossCastTimeOffsetX","bossCastTimeOffsetY","showBossCastTime","bossCastTimeFontSize"
                    )
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

                        if unit == "player" then
                            g.showPlayerCastTime = pf.MSUF_prev.showPlayerCastTime
                        elseif unit == "target" then
                            g.showTargetCastTime = pf.MSUF_prev.showTargetCastTime
                        elseif unit == "focus" then
                            g.showFocusCastTime = pf.MSUF_prev.showFocusCastTime
                        end

                    end

                    local reanchorName = (unit == "player" and "MSUF_ReanchorPlayerCastBar") or (unit == "target" and "MSUF_ReanchorTargetCastBar") or (unit == "focus" and "MSUF_ReanchorFocusCastBar")
                    local reanchorFn = reanchorName and _G[reanchorName]
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4993:39"); end)

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
            pf:SetSize(320, 470)

        end
    end

    local pf = MSUF_CastbarPositionPopup

    MSUF_EM_EnsureCopyDropdownGroupBGKilled(pf, pf.copySizeDrop, pf.copyTextDrop)
    local wasShown = (pf and pf.IsShown and pf:IsShown()) and true or false
    local oldUnit  = pf and pf.unit
    local oldParent = pf and pf.parent
    local needReposition = (not wasShown) or (oldUnit ~= unit) or (oldParent ~= parent)

    -- Popup active context (single source of truth): always overwrite on open/switch.
    -- This prevents any "context leak" when reusing the same popup across different castbars.
    pf._msufUnitKey = unit
    pf._msufDbPrefix = (unit ~= "boss") and prefix or nil
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
    pf.title:SetText(string.format("MSUF Edit – %s Castbar", label))
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
    pf.MSUF_prev.bossCastbarOffsetX = g.bossCastbarOffsetX
    pf.MSUF_prev.bossCastbarOffsetY = g.bossCastbarOffsetY
    pf.MSUF_prev.bossCastbarWidth   = g.bossCastbarWidth
    pf.MSUF_prev.bossCastbarHeight  = g.bossCastbarHeight

    -- Step 1 (Boss) text controls
    pf.MSUF_prev.bossCastTextOffsetX = g.bossCastTextOffsetX
    pf.MSUF_prev.bossCastTextOffsetY = g.bossCastTextOffsetY
    pf.MSUF_prev.showBossCastName = g.showBossCastName
    pf.MSUF_prev.bossCastSpellNameFontSize = g.bossCastSpellNameFontSize

    -- Step 2 (Boss) icon controls
    pf.MSUF_prev.bossCastIconOffsetX = g.bossCastIconOffsetX
    pf.MSUF_prev.bossCastIconOffsetY = g.bossCastIconOffsetY
    pf.MSUF_prev.showBossCastIcon = g.showBossCastIcon
    pf.MSUF_prev.bossCastIconSize = g.bossCastIconSize

    -- Step 3 (Boss) cast time controls
    pf.MSUF_prev.bossCastTimeOffsetX = g.bossCastTimeOffsetX
    pf.MSUF_prev.bossCastTimeOffsetY = g.bossCastTimeOffsetY
    pf.MSUF_prev.showBossCastTime = g.showBossCastTime
    pf.MSUF_prev.bossCastTimeFontSize = g.bossCastTimeFontSize
else
    pf.MSUF_prev.prefix = prefix
    if prefix then
        pf.MSUF_prev[prefix .. "OffsetX"]   = g[prefix .. "OffsetX"]
        pf.MSUF_prev[prefix .. "OffsetY"]   = g[prefix .. "OffsetY"]
        pf.MSUF_prev[prefix .. "BarWidth"]  = g[prefix .. "BarWidth"]
        pf.MSUF_prev[prefix .. "BarHeight"] = g[prefix .. "BarHeight"]
        pf.MSUF_prev[prefix .. "Detached"] = g[prefix .. "Detached"]
        pf.MSUF_prev[prefix .. "TextOffsetX"] = g[prefix .. "TextOffsetX"]
        pf.MSUF_prev[prefix .. "TextOffsetY"] = g[prefix .. "TextOffsetY"]
        pf.MSUF_prev[prefix .. "ShowSpellName"] = g[prefix .. "ShowSpellName"]
        pf.MSUF_prev[prefix .. "SpellNameFontSize"] = g[prefix .. "SpellNameFontSize"]

        pf.MSUF_prev[prefix .. "IconOffsetX"] = g[prefix .. "IconOffsetX"]
        pf.MSUF_prev[prefix .. "IconOffsetY"] = g[prefix .. "IconOffsetY"]
        pf.MSUF_prev[prefix .. "ShowIcon"] = g[prefix .. "ShowIcon"]
        pf.MSUF_prev[prefix .. "IconSize"] = g[prefix .. "IconSize"]

        pf.MSUF_prev[prefix .. "TimeOffsetX"] = g[prefix .. "TimeOffsetX"]
        pf.MSUF_prev[prefix .. "TimeOffsetY"] = g[prefix .. "TimeOffsetY"]
        pf.MSUF_prev[prefix .. "TimeFontSize"] = g[prefix .. "TimeFontSize"]

        if unit == "player" then
            pf.MSUF_prev.showPlayerCastTime = g.showPlayerCastTime
        elseif unit == "target" then
            pf.MSUF_prev.showTargetCastTime = g.showTargetCastTime
        elseif unit == "focus" then
            pf.MSUF_prev.showFocusCastTime = g.showFocusCastTime
        end

    end
end

    -- Player castbar: run a looping dummy cast on the preview while this popup is open.
    if pf.testModeCB then
        pf.testModeCB:Hide()
    end
    if type(_G.MSUF_SetPlayerCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "player") and popup and popup.IsShown and popup:IsShown() and popup.unit == "player"
            _G.MSUF_SetPlayerCastbarTestMode(want, true)
        end
    if type(_G.MSUF_SetTargetCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "target") and popup and popup.IsShown and popup:IsShown() and popup.unit == "target"
            _G.MSUF_SetTargetCastbarTestMode(want, true)
        end
    if type(_G.MSUF_SetFocusCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "focus") and popup and popup.IsShown and popup:IsShown() and popup.unit == "focus"
            _G.MSUF_SetFocusCastbarTestMode(want, true)
        end
        if type(_G.MSUF_SetBossCastbarTestMode) == "function" then
            local popup = _G.MSUF_CastbarPositionPopup
            local want = (unit == "boss") and popup and popup.IsShown and popup:IsShown() and popup.unit == "boss"
            _G.MSUF_SetBossCastbarTestMode(want, true)
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:4471:0"); end
local function MSUF_UpdateEditModeVisuals() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdateEditModeVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5274:6");
    if not UnitFrames then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateEditModeVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5274:6"); return end

    local pf = UnitFrames["player"]
    if pf and pf.UpdateEditArrows then
        pf:UpdateEditArrows()
    end

    local tf = UnitFrames["target"]
    if tf and tf.UpdateEditArrows then
        tf:UpdateEditArrows()
    end

    local ff = UnitFrames["focus"]
    if ff and ff.UpdateEditArrows then
        ff:UpdateEditArrows()
    end

    local pet = UnitFrames["pet"]
    if pet and pet.UpdateEditArrows then
        pet:UpdateEditArrows()
    end

    local tot = UnitFrames["targettarget"]
    if tot and tot.UpdateEditArrows then
        tot:UpdateEditArrows()
    end

    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local bf = UnitFrames["boss" .. i]
        if bf and bf.UpdateEditArrows then
            bf:UpdateEditArrows()
        end
    end

    MSUF_UpdateGridOverlay()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdateEditModeVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5274:6"); end
function MSUF_SyncCastbarPositionPopup(unit, force) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5311:0");
    if MSUF__CastbarPopupApplying or MSUF__CastbarPopupSyncing then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5311:0"); return
    end

    MSUF__CastbarPopupSyncing = true
    local ok = MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5317:29");
        local pf = MSUF_CastbarPositionPopup
        if not pf or not pf:IsShown() then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5317:29"); return
        end
        if pf.unit ~= unit then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5317:29"); return
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

        local function GetGlobalCastbarFontSize() Perfy_Trace(Perfy_GetTime(), "Enter", "GetGlobalCastbarFontSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5359:14");
            local baseSize = g.fontSize or 14
            local globalOverride = tonumber(g.castbarSpellNameFontSize) or 0
            return Perfy_Trace_Passthrough("Leave", "GetGlobalCastbarFontSize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5359:14", (globalOverride and globalOverride > 0) and globalOverride or baseSize)
        end

        -- Boss castbar is stored on MSUF_DB.general using "bossCast*" keys.
        if unit == "boss" then
            local parent = pf.parent or UIParent
            local currentW = tonumber(g.bossCastbarWidth)  or (parent.GetWidth and parent:GetWidth())  or 240
            local currentH = tonumber(g.bossCastbarHeight) or (parent.GetHeight and parent:GetHeight()) or 18
            if P and P.SyncFields then
                local specs = (Edit and Edit.Popups and Edit.Popups.Specs) or nil
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5317:29"); return
        end

        -- Player / Target / Focus (prefix keys, e.g. "playerCastbarOffsetX")
            local prefix = pf._msufDbPrefix or MSUF_GetCastbarPrefix(unit)
        local defaultX, defaultY = MSUF_GetCastbarDefaultOffsets(unit)
        if not prefix then
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5317:29"); return
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5317:29"); end)

    MSUF__CastbarPopupSyncing = false
    if not ok then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5311:0"); return
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5311:0"); end

local function MSUF_SyncUnitPositionPopup(unit, conf) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6");
    local pf = MSUF_PositionPopup
    if not pf or not pf:IsShown() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6"); return
    end

    -- Support legacy calls with no args (e.g. Cancel/refresh).
    local popupUnit = pf.unit
    local popupKey = popupUnit and GetConfigKeyForUnit and GetConfigKeyForUnit(popupUnit) or popupUnit

    local key = unit or popupKey
    if not key then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6"); return
    end

    if unit and popupUnit and unit ~= popupUnit and popupKey and unit ~= popupKey then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6"); return
    end

    if not conf then
        MSUF_EM_EnsureDB()
        if not MSUF_DB then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6"); return end
        conf = MSUF_DB[key]
    end
    if type(conf) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncUnitPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5489:6"); end


-- ---------------------------------------------------------

-- Auras 2.0 Position Popup (Target)  [helper-ready for Focus/Boss later]
-- Requirements:
--  - Drag & drop via Aura Edit Mover (in Auras 2.0 module)
--  - Popup (left/right click) for Offset X/Y + Size + Spacing
-- ---------------------------------------------------------

local function MSUF_A2_GetAuraPopupTitleSuffix(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6");
    if unitKey == 'player' then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6"); return 'Player Aura' end
    if unitKey == 'target' then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6"); return 'Target Aura' end
    if unitKey == 'focus' then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6"); return 'Focus Aura' end
    -- Boss previews will be 'Boss 1 Aura', 'Boss 2 Aura', ...
    if type(unitKey) == 'string' and unitKey:match('^boss%d+$') then
        local n = unitKey:match('^boss(%d+)$')
        if n then return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6", ('Boss %s Aura'):format(n)) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6"); return 'Boss Aura'
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraPopupTitleSuffix file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5567:6"); return 'Aura'
end

-- Helper: creates the popup once, and can be reused for focus/boss later.
function _G.MSUF_A2_EnsureAuraPositionPopup() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_A2_EnsureAuraPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5581:0");
    local pf = _G.MSUF_Auras2PositionPopup
    if pf then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_A2_EnsureAuraPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5581:0"); return pf
    end

    pf = CreateFrame('Frame', 'MSUF_EditAuras2PositionPopup', UIParent, 'BackdropTemplate')
    _G.MSUF_Auras2PositionPopup = pf
    if Edit and Edit.Popups and Edit.Popups.Register then Edit.Popups.Register(pf) end

    MSUF_InitEditPopupFrame(pf, {
        w = 320,
	        h = 640,
        backdrop = {
            bgFile   = 'Interface\\DialogFrame\\UI-DialogBox-Background-Dark',
            edgeFile = 'Interface\\DialogFrame\\UI-DialogBox-Border',
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        },
        backdropColor = { 0, 0, 0, 0.9 },
    })

	    -- Smooth drag: clamped frames can feel "5 FPS" while moving on some clients.
	    -- Fix: temporarily disable clamp during drag, then hard-clamp on drag stop.
	    pf:SetScript("OnDragStart", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5605:33");
	        if self:IsMovable() then
	            self:SetClampedToScreen(false)
	            self:StartMoving()
	        end
	    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5605:33"); end)
	    pf:SetScript("OnDragStop", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5611:32");
	        self:StopMovingOrSizing()
	        self:SetClampedToScreen(true)
	        -- Hard clamp to screen after move (prevents ending off-screen)
	        local ui = UIParent
	        if ui and ui.GetWidth and ui.GetHeight and self.GetLeft and self.GetBottom then
	            local sw, sh = ui:GetWidth() or 0, ui:GetHeight() or 0
	            local pw, ph = self:GetWidth() or 0, self:GetHeight() or 0
	            if sw > 0 and sh > 0 and pw > 0 and ph > 0 then
	                local left = self:GetLeft() or 0
	                local bottom = self:GetBottom() or 0
	                left = math.max(0, math.min(left, sw - pw))
	                bottom = math.max(0, math.min(bottom, sh - ph))
	                self:ClearAllPoints()
	                self:SetPoint("BOTTOMLEFT", ui, "BOTTOMLEFT", left, bottom)
	            end
	        end
	    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5611:32"); end)

    local title = pf:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
    title:SetPoint('TOP', 0, -12)
    title:SetText('MSUF Edit – Target Aura')
    pf.title = title

    -- Top-right close (acts like Cancel)
    local closeBtn = CreateFrame('Button', '$parentClose', pf, 'UIPanelCloseButton')
    closeBtn:SetPoint('TOPRIGHT', pf, 'TOPRIGHT', -6, -6)
    closeBtn:SetScript('OnClick', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5638:34");
        if pf.cancelBtn and pf.cancelBtn.Click then
            pf.cancelBtn:Click()
        else
            pf:Hide()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5638:34"); end)
    pf.closeBtn = closeBtn

    local frameHeader = pf:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    frameHeader:SetPoint('TOPLEFT', pf, 'TOPLEFT', 16, -36)
    frameHeader:SetText('Frame')
    frameHeader:SetTextColor(1, 0.82, 0, 1)
    pf.frameHeader = frameHeader

    local function Apply() Perfy_Trace(Perfy_GetTime(), "Enter", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5653:10");
        if (pf and (pf._msufAuras2PopupApplying or pf._msufAuras2PopupSyncing)) or _G.MSUF__Auras2PopupApplying then Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5653:10"); return end
        if pf then pf._msufAuras2PopupApplying = true end
        _G.MSUF__Auras2PopupApplying = true

        local ok = pcall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5658:25");
            MSUF_EM_EnsureDB()
            if not MSUF_DB or not MSUF_DB.auras2 then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5658:25"); return end

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

            local function isDirty(key) Perfy_Trace(Perfy_GetTime(), "Enter", "isDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5691:18");
                local d = pf and pf._msufA2Dirty
                return Perfy_Trace_Passthrough("Leave", "isDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5691:18", d and d[key] == true)
            end

            local function readNum(key, box, fallback) Perfy_Trace(Perfy_GetTime(), "Enter", "readNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5696:18");
                if not isDirty(key) then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "readNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5696:18"); return fallback
                end
                if not box or not box.GetText then Perfy_Trace(Perfy_GetTime(), "Leave", "readNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5696:18"); return fallback end
                local t = box:GetText()
                local n = tonumber(t)
                if n == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "readNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5696:18"); return fallback end
                Perfy_Trace(Perfy_GetTime(), "Leave", "readNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5696:18"); return n
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

            buffGroupOffsetX = MSUF_SanitizePopupOffset(buffGroupOffsetX, 0)
            buffGroupOffsetY = MSUF_SanitizePopupOffset(buffGroupOffsetY, 0)
            debuffGroupOffsetX = MSUF_SanitizePopupOffset(debuffGroupOffsetX, 0)
            debuffGroupOffsetY = MSUF_SanitizePopupOffset(debuffGroupOffsetY, 0)

            privOffX = MSUF_SanitizePopupOffset(privOffX, 0)
            privOffY = MSUF_SanitizePopupOffset(privOffY, 0)

                -- Clamp & sanitize all numeric fields (avoid snap-back after mouse-drag).
            local OFF_LIMIT = 2000
            local function clampOff(v) Perfy_Trace(Perfy_GetTime(), "Enter", "clampOff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5787:18");
                v = tonumber(v) or 0
                if v > OFF_LIMIT then Perfy_Trace(Perfy_GetTime(), "Leave", "clampOff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5787:18"); return OFF_LIMIT end
                if v < -OFF_LIMIT then return Perfy_Trace_Passthrough("Leave", "clampOff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5787:18", -OFF_LIMIT) end
                Perfy_Trace(Perfy_GetTime(), "Leave", "clampOff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5787:18"); return v
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

local function ApplyLayoutToUnit(k) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyLayoutToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5817:6");
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
Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyLayoutToUnit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5817:6"); end

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
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5658:25"); end)
        _G.MSUF__Auras2PopupApplying = false
        if pf then pf._msufAuras2PopupApplying = false end
        if not ok then
            -- fail-open
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5653:10"); end

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

    
    -- -------------------------------------------------------------------
    -- Buffs / Debuffs (independent X/Y/Size)
    -- -------------------------------------------------------------------
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

-- -------------------------------------------------------------------
    -- Private Auras (Blizzard-rendered): independent offsets + icon size
    -- Note: This edits a2.shared.privateOffsetX/Y/privateSize (with per-unit overrides).
    -- -------------------------------------------------------------------
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
    privatePreview:SetScript('OnClick', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5956:40");
        Apply()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5956:40"); end)
    pf.privatePreviewCheck = privatePreview

    local rows3 = {
        { key = "privateOffsetX", label = "Private offset X:", box = "$parentPrivateOffsetXBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "privateOffsetY", label = "Private offset Y:", box = "$parentPrivateOffsetYBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
        { key = "privateSize",    label = "Private icon size:", box = "$parentPrivateSizeBox", dy = -8, live = true, labelTemplate = "GameFontHighlightSmall", requireCompleteNumber = false },
    }
    MSUF_EM_BuildNumericRows(pf, rows3, privatePreview, "BOTTOMLEFT", 0, Apply, "Auras2Popup:LiveApply")

local function OnEnterPressed(self) Perfy_Trace(Perfy_GetTime(), "Enter", "OnEnterPressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5968:6");
        self:ClearFocus()
        Apply()
    Perfy_Trace(Perfy_GetTime(), "Leave", "OnEnterPressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5968:6"); end
    MSUF_EM_BindKeyScripts(OnEnterPressed, nil,
        pf.spacingBox,
        pf.stackTextSizeBox, pf.stackTextOffsetXBox, pf.stackTextOffsetYBox,
        pf.cooldownTextSizeBox,
        pf.cooldownTextOffsetXBox, pf.cooldownTextOffsetYBox,
        pf.buffGroupOffsetXBox, pf.buffGroupOffsetYBox, pf.buffGroupIconSizeBox,
        pf.debuffGroupOffsetXBox, pf.debuffGroupOffsetYBox, pf.debuffGroupIconSizeBox,
        pf.privateOffsetXBox, pf.privateOffsetYBox, pf.privateSizeBox
    )

-- Copy Settings Dropdown (spec-driven; no behavior change)
local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
local AS = UISpec and UISpec.Auras2
if AS and AS.copyDropdowns and AS.copyDropdowns.aura then
    MSUF_EM_UI_BuildCopyDropdown(pf, AS.copyDropdowns.aura)
end

local function MSUF_A2_GetAuraCopyLabel(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_GetAuraCopyLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5989:6");
    if key == "player" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraCopyLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5989:6"); return "Player" end
    if key == "target" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraCopyLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5989:6"); return "Target" end
    if key == "focus" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_GetAuraCopyLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5989:6"); return "Focus" end
    if type(key) == "string" then
        local n = key:match("^boss(%d+)$")
        if n then return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetAuraCopyLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5989:6", ("Boss %s"):format(n)) end
    end
    return Perfy_Trace_Passthrough("Leave", "MSUF_A2_GetAuraCopyLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5989:6", tostring(key or ""))
end

local function MSUF_A2_IsBossAuraKey(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_IsBossAuraKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6000:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_A2_IsBossAuraKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6000:6", (type(key) == "string") and key:match("^boss%d+$"))
end

local function MSUF_A2_CopyAuraLayout(srcKey, dstKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_CopyAuraLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6004:6");
    if not srcKey or not dstKey or srcKey == dstKey then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CopyAuraLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6004:6"); return end
    MSUF_EM_EnsureDB()
    if not MSUF_DB or not MSUF_DB.auras2 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CopyAuraLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6004:6"); return end

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
    local function eff(v, fallback) Perfy_Trace(Perfy_GetTime(), "Enter", "eff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6034:10");
        if v ~= nil then Perfy_Trace(Perfy_GetTime(), "Leave", "eff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6034:10"); return v end
        Perfy_Trace(Perfy_GetTime(), "Leave", "eff file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6034:10"); return fallback
    end

    local sOffX = eff(srcLay.offsetX, a2db.shared.offsetX or 0)
    local sOffY = eff(srcLay.offsetY, a2db.shared.offsetY or 0)
    local sSize = eff(srcLay.iconSize, a2db.shared.iconSize or 26)
    local sSpac = eff(srcLay.spacing,  a2db.shared.spacing or 2)
    local sPerR = eff(srcLay.perRow,   a2db.shared.perRow or 12)
    local sBuffY= eff(srcLay.buffOffsetY, a2db.shared.buffOffsetY or 30)
    local sStSz = eff(srcLay.stackTextSize, a2db.shared.stackTextSize or 14)
    local sCdSz = eff(srcLay.cooldownTextSize, a2db.shared.cooldownTextSize or 14)

    local sCdOffX = (srcLay.cooldownTextOffsetX ~= nil) and srcLay.cooldownTextOffsetX or a2db.shared.cooldownTextOffsetX
    local sCdOffY = (srcLay.cooldownTextOffsetY ~= nil) and srcLay.cooldownTextOffsetY or a2db.shared.cooldownTextOffsetY
    local sPrivOffX = eff(srcLay.privateOffsetX, a2db.shared.privateOffsetX or 0)
    local sPrivOffY = eff(srcLay.privateOffsetY, a2db.shared.privateOffsetY or 0)
    local sPrivSize = eff(srcLay.privateSize, a2db.shared.privateSize or sSize)

    local sBuffGroupOffX = eff(srcLay.buffGroupOffsetX, a2db.shared.buffGroupOffsetX or 0)
    local sBuffGroupOffY = eff(srcLay.buffGroupOffsetY, a2db.shared.buffGroupOffsetY or 0)
    local sBuffGroupSize = eff(srcLay.buffGroupIconSize, a2db.shared.buffGroupIconSize or sSize)

    local sDebuffGroupOffX = eff(srcLay.debuffGroupOffsetX, a2db.shared.debuffGroupOffsetX or 0)
    local sDebuffGroupOffY = eff(srcLay.debuffGroupOffsetY, a2db.shared.debuffGroupOffsetY or 0)
    local sDebuffGroupSize = eff(srcLay.debuffGroupIconSize, a2db.shared.debuffGroupIconSize or sSize)
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
        -- Note: Copy size settings should not copy position offsets (Offset X/Y)
        dc.layout.iconSize = sSize
        dc.layout.spacing = sSpac
        dc.layout.perRow = sPerR
        dc.layout.buffOffsetY = sBuffY
        dc.layout.stackTextSize = sStSz
        dc.layout.cooldownTextSize = sCdSz

        dc.layout.buffGroupOffsetX = sBuffGroupOffX
        dc.layout.buffGroupOffsetY = sBuffGroupOffY
        dc.layout.buffGroupIconSize = sBuffGroupSize
        dc.layout.debuffGroupOffsetX = sDebuffGroupOffX
        dc.layout.debuffGroupOffsetY = sDebuffGroupOffY
        dc.layout.debuffGroupIconSize = sDebuffGroupSize


        dc.layout.privateOffsetX = sPrivOffX
        dc.layout.privateOffsetY = sPrivOffY
        dc.layout.privateSize    = sPrivSize
        if sCdOffX ~= nil then dc.layout.cooldownTextOffsetX = sCdOffX end
        if sCdOffY ~= nil then dc.layout.cooldownTextOffsetY = sCdOffY end
        -- keep width/height unused in Auras2 (derived)
        dc.layout.width = nil
        dc.layout.height = nil

        if type(_G.MSUF_Auras2_RefreshUnit) == "function" then
            _G.MSUF_Auras2_RefreshUnit(k)
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_CopyAuraLayout file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6004:6"); end

local function MSUF_A2_RefreshCopyAuraDropdown() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_A2_RefreshCopyAuraDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6104:6");
    if not UIDropDownMenu_Initialize or not UIDropDownMenu_SetText then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_RefreshCopyAuraDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6104:6"); return end
    if not pf or not pf.copyAuraDrop or not pf.copyAuraLabel then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_RefreshCopyAuraDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6104:6"); return end

    local srcKey = pf.unit or "target"

    local a2sharedTogether = true
    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.shared then
        if MSUF_DB.auras2.shared.bossEditTogether == nil then
            MSUF_DB.auras2.shared.bossEditTogether = true
        end
        a2sharedTogether = (MSUF_DB.auras2.shared.bossEditTogether ~= false)
    end
    if pf.bossTogetherCheck and pf.bossTogetherCheck.IsShown and pf.bossTogetherCheck:IsShown() and pf.bossTogetherCheck.GetChecked then
        a2sharedTogether = (pf.bossTogetherCheck:GetChecked() and true) or false
    end

    pf.copyAuraLabel:Show()
    pf.copyAuraDrop:Show()

    local placeholder = "Copy settings to..."
    UIDropDownMenu_SetWidth(pf.copyAuraDrop, 170)
    UIDropDownMenu_JustifyText(pf.copyAuraDrop, "LEFT")
    UIDropDownMenu_SetText(pf.copyAuraDrop, placeholder)

    local allKeys = { "player","target","focus","boss1","boss2","boss3","boss4","boss5" }

    UIDropDownMenu_Initialize(pf.copyAuraDrop, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6131:47");
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true

        for _, dstKey in ipairs(allKeys) do
            local skip = (dstKey == srcKey)
            -- If source is boss and we edit together, skipping all bosses avoids confusion.
            if not skip and MSUF_A2_IsBossAuraKey(srcKey) and a2sharedTogether then
                if MSUF_A2_IsBossAuraKey(dstKey) then
                    skip = true
                end
            end
            if not skip then
                info.text = MSUF_A2_GetAuraCopyLabel(dstKey)
                info.func = function() Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6145:28");
                    -- Commit current popup values first so we copy the latest numbers.
                    if pf._msufAuras2Apply then
                        pf._msufAuras2Apply()
                    end
                    MSUF_A2_CopyAuraLayout(srcKey, dstKey)
                    UIDropDownMenu_SetText(pf.copyAuraDrop, placeholder)
                Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6145:28"); end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6131:47"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_A2_RefreshCopyAuraDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6104:6"); end

pf.RefreshCopyAuraDropdown = MSUF_A2_RefreshCopyAuraDropdown
    -- Bottom buttons (spec-driven; behavior unchanged)
    local UISpec = Edit and Edit.Popups and Edit.Popups.UISpec
    local AS = UISpec and UISpec.Auras2

    local okayBtn, cancelBtn = MSUF_EM_UI_BuildFooterButtons(pf, (AS and AS.footer) or nil)
    -- Builder returns (okBtn, cancelBtn, menuBtn). Auras2 has no menu.
    if cancelBtn then
        if MSUF_EM_ForceWhiteButtonText then MSUF_EM_ForceWhiteButtonText(cancelBtn) end
        cancelBtn:SetScript('OnClick', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6168:39");
            MSUF_EM_ClearFocusOnBoxes(
                pf.spacingBox,
                pf.stackTextSizeBox, pf.stackTextOffsetXBox, pf.stackTextOffsetYBox,
                pf.cooldownTextSizeBox, pf.cooldownTextOffsetXBox, pf.cooldownTextOffsetYBox,
                pf.buffGroupOffsetXBox, pf.buffGroupOffsetYBox, pf.buffGroupIconSizeBox,
                pf.debuffGroupOffsetXBox, pf.debuffGroupOffsetYBox, pf.debuffGroupIconSizeBox,
                pf.privateOffsetXBox, pf.privateOffsetYBox, pf.privateSizeBox
            )
            pf:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6168:39"); end)
    end

    if okayBtn then
        if MSUF_EM_ForceWhiteButtonText then MSUF_EM_ForceWhiteButtonText(okayBtn) end
        okayBtn:SetScript('OnClick', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6183:37");
            Apply()
            pf:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6183:37"); end)
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

        local function MarkDirty(key) Perfy_Trace(Perfy_GetTime(), "Enter", "MarkDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6207:14");
            if not pf._msufA2Dirty then pf._msufA2Dirty = {} end
            pf._msufA2Dirty[key] = true
        Perfy_Trace(Perfy_GetTime(), "Leave", "MarkDirty file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6207:14"); end

        for _, key in ipairs(DIRTY_KEYS) do
            local box = pf[key.."Box"]
            if box and box.HookScript then
                box:HookScript("OnTextChanged", function(self, userInput) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6215:48");
                    if userInput and not pf._msufAuras2PopupSyncing and not pf._msufAuras2PopupApplying then
                        MarkDirty(key)
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6215:48"); end)
            end

            local function Wrap(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "Wrap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6222:18");
                if not btn or not btn.GetScript or not btn.SetScript or btn.__msufA2DirtyWrapped then Perfy_Trace(Perfy_GetTime(), "Leave", "Wrap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6222:18"); return end
                btn.__msufA2DirtyWrapped = true
                local orig = btn:GetScript("OnClick")
                btn:SetScript("OnClick", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6226:41");
                    if not pf._msufAuras2PopupSyncing and not pf._msufAuras2PopupApplying then
                        MarkDirty(key)
                    end
                    if orig then orig(self, ...) end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6226:41"); end)
            Perfy_Trace(Perfy_GetTime(), "Leave", "Wrap file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6222:18"); end
            Wrap(pf[key.."Minus"])
            Wrap(pf[key.."Plus"])
        end

        -- Keep popup values visually synced with mouse-drag while Edit Mode is open.
        pf:HookScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6238:32");
            self._msufA2Dirty = {}
            if self._msufA2SyncTicker then
                self._msufA2SyncTicker:Cancel()
                self._msufA2SyncTicker = nil
            end
            if C_Timer and C_Timer.NewTicker then
                self._msufA2SyncTicker = C_Timer.NewTicker(0.15, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6245:65");
                    if not self or not self:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6245:65"); return end
                    if type(_G.MSUF_SyncAuras2PositionPopup) == "function" then
                        _G.MSUF_SyncAuras2PositionPopup(self.unit)
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6245:65"); end)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6238:32"); end)

        pf:HookScript("OnHide", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6254:32");
            if self._msufA2SyncTicker then
                self._msufA2SyncTicker:Cancel()
                self._msufA2SyncTicker = nil
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6254:32"); end)
    end
    -- Ensure Midnight EditMode styling is applied immediately (fixes: first-open shows default UI style)
    if pf.HookScript and not pf.__msufAuraPopupStyleHooked then
        pf.__msufAuraPopupStyleHooked = true
        pf:HookScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6264:32");
            local Style = _G.MSUF_NS and _G.MSUF_NS.Style
            if Style and Style.SkinEditModePopupFrame then
                pcall(Style.SkinEditModePopupFrame, self)
            elseif Style and Style.ScanAndSkinEditMode then
                pcall(Style.ScanAndSkinEditMode)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6264:32"); end)
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_A2_EnsureAuraPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:5581:0"); return pf
end

function _G.MSUF_SyncAuras2PositionPopup(unit) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0");
    local pf = _G.MSUF_Auras2PositionPopup
    if not pf or not pf.IsShown or not pf:IsShown() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0"); return
    end

    local popupUnit = pf.unit or unit
    if not popupUnit then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0"); return
    end
    if unit and pf.unit and unit ~= pf.unit then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0"); return
    end

    MSUF_EM_EnsureDB()
    if not MSUF_DB or not MSUF_DB.auras2 then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0"); return
    end

    if pf._msufAuras2PopupApplying or _G.MSUF__Auras2PopupApplying then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0"); return
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6277:0"); end

function _G.MSUF_OpenAuras2PositionPopup(unit, parent) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0");
    -- Wired up by Auras 2.0: Target, Focus, Boss1-5 (helper is unit-agnostic).
    if not unit then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); return
    end
    if unit ~= 'player' and unit ~= 'target' and unit ~= 'focus' and not (type(unit) == 'string' and unit:match('^boss%d+$')) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); return
    end
    if not _G.MSUF_UnitEditModeActive then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); return
    end
    if InCombatLockdown and InCombatLockdown() then
        print('|cffffd700MSUF:|r Position/Größe kann im Kampf nicht geändert werden.')
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); return
    end

    if not MSUF_EM_EnsureDB() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); return
    end
    if not MSUF_DB then
        Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); return
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
        pf.title:SetText('MSUF Edit – ' .. (suffix or 'Aura'))
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
Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_OpenAuras2PositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6480:0"); end

-- ---------------------------------------------------------
-- Arrow-key nudging (Edit Mode only)
-- ---------------------------------------------------------
-- P0 goals:
--  1) Never call SetPropagateKeyboardInput() (can be protected / causes ADDON_ACTION_BLOCKED)
--  2) Never capture WASD or "all keyboard" (user must be able to move in Edit Mode)
--  3) Only bind Arrow keys while MSUF Edit Mode is active, and always release on Exit/Cancel
--
-- Implementation: override bindings for UP/DOWN/LEFT/RIGHT -> a lightweight button click.
-- This avoids a fullscreen keyboard-catcher frame entirely and keeps movement keys working.
--
-- Note: Uses globals deliberately to avoid hitting the "200 locals" limit in large files.

-- ---------------------------------------------------------
-- Arrow-key nudging (Edit Mode only)
-- ---------------------------------------------------------
-- P0 goals:
--  1) Never call SetPropagateKeyboardInput() (can be protected / causes ADDON_ACTION_BLOCKED)
--  2) Never capture WASD or "all keyboard" (user must be able to move in Edit Mode)
--  3) Only bind Arrow keys while MSUF Edit Mode is active, and always release on Exit/Cancel
--
-- Implementation: Override bindings for UP/DOWN/LEFT/RIGHT -> click hidden direction buttons.
-- IMPORTANT: SetOverrideBindingClick's "clickButton" parameter MUST be a real mouse button name
-- ("LeftButton", "RightButton", ...). Using "UP"/"DOWN" there breaks the click entirely.
--
-- Note: Uses globals deliberately to avoid hitting the "200 locals" limit in large files.
local MSUF_EM_GetCastbarOffsetKeys -- castbar offset key helper (used by snap + arrow-key nudging)

if not _G.MSUF_EnableArrowKeyNudge then
function _G.MSUF_EnableArrowKeyNudge(enable) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_EnableArrowKeyNudge file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6582:0");
        -- If a previous build created a fullscreen keyboard-catcher frame, hard-disable it.
        if _G.MSUF_ArrowKeyNudgeFrame then
            local old = _G.MSUF_ArrowKeyNudgeFrame
            if old.EnableKeyboard then MSUF_FastCall(old.EnableKeyboard, old, false) end
            if old.Hide then MSUF_FastCall(old.Hide, old) end
            old.__msufHardKill = true
        end

        -- If a previous build created the single "direction token" button, hide it (we use 4 real click buttons now).
        if _G.MSUF_ArrowKeyNudgeButton and _G.MSUF_ArrowKeyNudgeButton.Hide then
            MSUF_FastCall(_G.MSUF_ArrowKeyNudgeButton.Hide, _G.MSUF_ArrowKeyNudgeButton)
        end

        if not _G.MSUF_ArrowKeyBindOwner then
            local owner = CreateFrame("Frame", "MSUF_ArrowKeyBindOwner", UIParent)
            _G.MSUF_ArrowKeyBindOwner = owner
            owner:Hide()
            owner.__msufPendingClear = false
            owner:SetScript("OnEvent", function(self, event) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6601:39");
                if event == "PLAYER_REGEN_ENABLED" then
                    if self.__msufPendingClear then
                        self.__msufPendingClear = false
                        if ClearOverrideBindings then
                            MSUF_FastCall(ClearOverrideBindings, self)
                        end
                    end
                    if self.UnregisterEvent then
                        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    end
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6601:39"); end)
        end

        local function GetStep() Perfy_Trace(Perfy_GetTime(), "Enter", "GetStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6616:14");
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
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetStep file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6616:14"); return step
        end

        local function NudgeTarget(dx, dy) Perfy_Trace(Perfy_GetTime(), "Enter", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14");
            if not MSUF_UnitEditModeActive then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end
            if InCombatLockdown and InCombatLockdown() then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end
            if IsTyping and IsTyping() then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end
            if not MSUF_EM_EnsureDB() then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end

            if not MSUF_DB then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end

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
                if not xKey or not yKey then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return
                end

                g[xKey] = math.floor(((tonumber(g[xKey]) or 0) + ndx) + 0.5)
                g[yKey] = math.floor(((tonumber(g[yKey]) or 0) + ndy) + 0.5)

                MSUF_EditMode_RequestCastbarApply(unit)

                if type(_G.MSUF_SyncCastbarPositionPopup) == "function" then
                    _G.MSUF_SyncCastbarPositionPopup(unit)
                end

                if MSUF_UpdateCastbarEditInfo then
                    MSUF_UpdateCastbarEditInfo()
                end
                Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return
            end

            local unitPF = MSUF_PositionPopup
            local key = MSUF_CurrentEditUnitKey
            if unitPF and unitPF.IsShown and unitPF:IsShown() and unitPF.unit and GetConfigKeyForUnit then
                key = GetConfigKeyForUnit(unitPF.unit) or key
            end
            if not key then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end

            local conf = MSUF_DB[key]
            if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); return end

            local s = GetStep()
            local ndx, ndy = dx * s, dy * s

            conf.offsetX = math.floor(((tonumber(conf.offsetX) or 0) + ndx) + 0.5)
            conf.offsetY = math.floor(((tonumber(conf.offsetY) or 0) + ndy) + 0.5)

            -- Important: use the known-good apply path so Player can't get stuck hidden after toggles
            MSUF_EditMode_RequestUnitApply(key)

            -- Keep popup fields in sync (prevents snap-back when Apply runs later)
            if type(_G.MSUF_SyncUnitPositionPopup) == "function" then
                _G.MSUF_SyncUnitPositionPopup(key, conf)
            end

            if MSUF_UpdateEditModeInfo then
                MSUF_UpdateEditModeInfo()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "NudgeTarget file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6634:14"); end

        local function EnsureButtons() Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6704:14");
            if _G.MSUF_ArrowKeyNudgeButtons then
                return Perfy_Trace_Passthrough("Leave", "EnsureButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6704:14", _G.MSUF_ArrowKeyNudgeButtons)
            end

            local t = {}
            _G.MSUF_ArrowKeyNudgeButtons = t

            local function Make(dir, dx, dy) Perfy_Trace(Perfy_GetTime(), "Enter", "Make file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6712:18");
                local name = "MSUF_ArrowKeyNudgeButton_" .. dir
                local b = CreateFrame("Button", name, UIParent)
                t[dir] = b
                b:Hide()
                if b.RegisterForClicks then
                    b:RegisterForClicks("AnyUp")
                end
                b:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6720:39");
                    MSUF_SafeCall("ArrowKey:" .. dir, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6721:54");
                        NudgeTarget(dx, dy)
                    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6721:54"); end)
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6720:39"); end)
            Perfy_Trace(Perfy_GetTime(), "Leave", "Make file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6712:18"); end

            Make("UP", 0, 1)
            Make("DOWN", 0, -1)
            Make("LEFT", -1, 0)
            Make("RIGHT", 1, 0)

            Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureButtons file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6704:14"); return t
        end

        if enable then
            -- Feature disabled due to repeated errors
            if MSUF__SafeFeatureDisabled and MSUF__SafeFeatureDisabled["arrowKeys"] then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_EnableArrowKeyNudge file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6582:0"); return
            end

            local owner = _G.MSUF_ArrowKeyBindOwner
            if not owner then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_EnableArrowKeyNudge file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6582:0"); return end
            owner:Show()

            -- Ensure no stuck editbox focus blocks movement keys when entering Edit Mode
            MSUF_FastCall(MSUF_EM_ClearKeyboardFocus)

            -- Apply override bindings only out of combat. In combat we keep them as-is and nudging does nothing anyway.
            if InCombatLockdown and InCombatLockdown() then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_EnableArrowKeyNudge file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6582:0"); return
            end

            if ClearOverrideBindings then
                MSUF_FastCall(ClearOverrideBindings, owner)
            end

            local btns = EnsureButtons()
            if SetOverrideBindingClick and btns then
                -- clickButton MUST be a real mouse button ("LeftButton"). Direction is encoded by using 4 distinct buttons.
                MSUF_FastCall(SetOverrideBindingClick, owner, false, "UP", btns.UP:GetName(), "LeftButton")
                MSUF_FastCall(SetOverrideBindingClick, owner, false, "DOWN", btns.DOWN:GetName(), "LeftButton")
                MSUF_FastCall(SetOverrideBindingClick, owner, false, "LEFT", btns.LEFT:GetName(), "LeftButton")
                MSUF_FastCall(SetOverrideBindingClick, owner, false, "RIGHT", btns.RIGHT:GetName(), "LeftButton")
            end

            MSUF_EM_SetArrowBindingsActive(true)

            -- One-time per-session tip (if available)
            if _G.MSUF_EditMode_ShowArrowKeyTip then
                MSUF_FastCall(_G.MSUF_EditMode_ShowArrowKeyTip)
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
                        MSUF_FastCall(ClearOverrideBindings, owner)
                    end
                end
                owner:Hide()
            end

            MSUF_EM_SetArrowBindingsActive(false)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_EnableArrowKeyNudge file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6582:0"); end
end

local MSUF_BlizzardEditHooked = false

local MSUF_BlizzardEditHooked = false

-- ---------------------------------------------------------
-- Popup helpers (keep open during edits, but close on Edit Mode exit)
-- ---------------------------------------------------------
local function MSUF_CloseAllPositionPopups() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CloseAllPositionPopups file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6801:6");
    -- Phase 3A: if popup registry exists, prefer it (covers any future popups too).
    if Edit and Edit.Popups and type(Edit.Popups.CloseAll) == "function" then
        Edit.Popups.CloseAll()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CloseAllPositionPopups file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6801:6"); return
    end

    -- Fallback: legacy known popups.
    if MSUF_PositionPopup and MSUF_PositionPopup.Hide then
        MSUF_PositionPopup:Hide()
    end
    if MSUF_CastbarPositionPopup and MSUF_CastbarPositionPopup.Hide then
        MSUF_CastbarPositionPopup:Hide()
    end
    if GameTooltip and GameTooltip.Hide then
        GameTooltip:Hide()
    end
    MSUF_EM_SetPopupOpen(false)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CloseAllPositionPopups file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6801:6"); end

-- ---------------------------------------------------------
-- Phase 2 refactor: deterministic Exit/Cancel cleanup order
-- ---------------------------------------------------------
-- Single exit path for MSUF Edit Mode to avoid state drift / stuck popups / stuck bindings.
-- This MUST be safe in combat: secure visibility drivers are deferred by MSUF_EditMode_RequestVisibilityDrivers().
local function MSUF_EditMode_ExitDeterministic(source, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EditMode_ExitDeterministic file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6826:6");
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

    -- Best-effort: sync other edit-mode visuals.
    if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
        MSUF_SafeCall("Exit:SyncCastbarEdit:" .. source, MSUF_SyncCastbarEditModeWithUnitEdit)
    end
    if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
        MSUF_SafeCall("Exit:SyncBossPreview:" .. source, MSUF_SyncBossUnitframePreviewWithUnitEdit)
    end

    if MSUF_GridFrame and MSUF_GridFrame.Hide then
        MSUF_FastCall(MSUF_GridFrame.Hide, MSUF_GridFrame)
    end

    if MSUF_UpdateEditModeVisuals then
        MSUF_SafeCall("Exit:Visuals:" .. source, MSUF_UpdateEditModeVisuals)
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_SafeCall("Exit:Info:" .. source, MSUF_UpdateEditModeInfo)
    end

    -- Hard teardown last (kill timers/listeners) so Edit Mode costs ~0 after exit.
    MSUF_EditMode_HardTeardown()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EditMode_ExitDeterministic file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6826:6"); end


-- ------------------------------------------------------------
-- BCDM Cooldown Manager handoff notice (Edit Mode)
-- Shows a prominent one-time-per-session warning when:
--   1) BetterCooldownManager is loaded
--   2) BCDM CooldownManager skinning is enabled (CooldownManager.Enable == true)
--   3) MSUF is anchored to the Blizzard Cooldown Manager (MSUF_DB.general.anchorToCooldown == true)
-- This intentionally does NOT try to move the Blizzard CDM (BCDM owns it when skinning is enabled).
-- ------------------------------------------------------------

local MSUF_EM_BCDMNotice_ShownThisSession = false
local MSUF_EM_BCDMNotice_PendingCombat = false
local MSUF_EM_BCDMNotice_EventFrame

local function MSUF_EM_IsBCDMAddonLoaded() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_IsBCDMAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6900:6");
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_IsBCDMAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6900:6", C_AddOns.IsAddOnLoaded("BetterCooldownManager") and true or false)
    end
    if type(IsAddOnLoaded) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_IsBCDMAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6900:6", IsAddOnLoaded("BetterCooldownManager") and true or false)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_IsBCDMAddonLoaded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6900:6"); return false
end

local function MSUF_EM_GetBCDMActiveProfileTable() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetBCDMActiveProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6910:6");
    local sv = _G.BCDMDB
    if type(sv) ~= "table" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetBCDMActiveProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6910:6"); return nil
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
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetBCDMActiveProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6910:6"); return nil
    end

    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetBCDMActiveProfileTable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6910:6", sv.profiles[profileName])
end

local function MSUF_EM_IsBCDMHandoffNoticeSuppressed() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_IsBCDMHandoffNoticeSuppressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6943:6");
    -- Persisted "never show again" toggle (stored in MSUF_DB.general).
    MSUF_EM_EnsureDB()
    local g = MSUF_DB and MSUF_DB.general
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_IsBCDMHandoffNoticeSuppressed file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6943:6", (type(g) == "table" and g.suppressBCDMHandoffNotice == true) and true or false)
end

local function MSUF_EM_ShouldShowBCDMHandoffNotice() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ShouldShowBCDMHandoffNotice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6950:6");
    if MSUF_EM_BCDMNotice_ShownThisSession then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShouldShowBCDMHandoffNotice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6950:6"); return false
    end

    -- User requested: "never show again"
    if MSUF_EM_IsBCDMHandoffNoticeSuppressed() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShouldShowBCDMHandoffNotice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6950:6"); return false
    end

    -- Show whenever BetterCooldownManager is loaded.
    -- Reason: BCDM can take ownership of the Blizzard Cooldown Manager positioning (even if Edit Mode shows it as movable),
    -- which can make anchored frames appear to "snap back" or not persist their position via the Blizzard manager.
    return Perfy_Trace_Passthrough("Leave", "MSUF_EM_ShouldShowBCDMHandoffNotice file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6950:6", MSUF_EM_IsBCDMAddonLoaded())
end

local function MSUF_EM_EnsureBCDMNoticePopupDialog() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_EnsureBCDMNoticePopupDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6966:6");
    if not StaticPopupDialogs then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureBCDMNoticePopupDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6966:6"); return
    end
    if StaticPopupDialogs["MSUF_BCDM_CDM_HANDOFF_NOTICE"] then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureBCDMNoticePopupDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6966:6"); return
    end

    StaticPopupDialogs["MSUF_BCDM_CDM_HANDOFF_NOTICE"] = {
        text = [[|cffff4444BCDM detected: BetterCooldownManager controls Blizzard Cooldown Manager positioning.|r

BCDM can override Edit Mode movement / saved position for the Blizzard Cooldown Manager, so frames anchored to it may appear to "snap back".

To move the Cooldown Manager, use: |cff00ff00/bcdm|r -> Cooldown Manager -> Layout.
(Edit Mode may still let you drag it, but BCDM will apply its own X/Y.)

MSUF will keep anchoring to the Cooldown Manager.]],
        button1 = OKAY,
        button2 = "Never show again",
        OnCancel = function(self, data, reason) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6985:19");
            -- Only treat an explicit click on the 'Never show again' button as opt-out.
            -- (ESC/close should NOT permanently disable the notice.)
            if reason ~= "clicked" then
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6985:19"); return
            end
            MSUF_EM_EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general.suppressBCDMHandoffNotice = true
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6985:19"); end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnsureBCDMNoticePopupDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:6966:6"); end

local function MSUF_EM_ShowBCDMHandoffNotice_Now() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ShowBCDMHandoffNotice_Now file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7002:6");
    if MSUF_EM_BCDMNotice_ShownThisSession then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShowBCDMHandoffNotice_Now file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7002:6"); return
    end
    if not MSUF_EM_ShouldShowBCDMHandoffNotice() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShowBCDMHandoffNotice_Now file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7002:6"); return
    end

    -- Avoid showing UI popups in combat; defer until combat ends.
    if InCombatLockdown and InCombatLockdown() then
        MSUF_EM_BCDMNotice_PendingCombat = true
        if not MSUF_EM_BCDMNotice_EventFrame then
            local f = CreateFrame("Frame")
            MSUF_EM_BCDMNotice_EventFrame = f
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7017:35");
                if not MSUF_EM_BCDMNotice_PendingCombat then
                    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7017:35"); return
                end
                MSUF_EM_BCDMNotice_PendingCombat = false
                -- Only show if Edit Mode is still active
                if MSUF_UnitEditModeActive then
                    if type(MSUF_SafeAfter) == "function" then
                        MSUF_SafeAfter(0, "Popup:BCDMHandoff", MSUF_EM_ShowBCDMHandoffNotice_Now)
                    else
                        C_Timer.After(0, MSUF_EM_ShowBCDMHandoffNotice_Now)
                    end
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7017:35"); end)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShowBCDMHandoffNotice_Now file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7002:6"); return
    end

    MSUF_EM_EnsureBCDMNoticePopupDialog()
    if StaticPopup_Show then
        MSUF_EM_BCDMNotice_ShownThisSession = true
        StaticPopup_Show("MSUF_BCDM_CDM_HANDOFF_NOTICE")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShowBCDMHandoffNotice_Now file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7002:6"); end

local function MSUF_EM_ShowBCDMHandoffNoticeIfNeeded() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ShowBCDMHandoffNoticeIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7042:6");
    if not MSUF_EM_ShouldShowBCDMHandoffNotice() then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShowBCDMHandoffNoticeIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7042:6"); return
    end
    -- Defer to next tick to avoid any secure-stack weirdness during Edit Mode transitions.
    if type(MSUF_SafeAfter) == "function" then
        MSUF_SafeAfter(0, "Popup:BCDMHandoff", MSUF_EM_ShowBCDMHandoffNotice_Now)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0, MSUF_EM_ShowBCDMHandoffNotice_Now)
    else
        MSUF_EM_ShowBCDMHandoffNotice_Now()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ShowBCDMHandoffNoticeIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7042:6"); end

function MSUF_SetMSUFEditModeFromBlizzard(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0");
    -- Blizzard -> MSUF Edit Mode sync disabled (TEMP): MSUF runs its own standalone Edit Mode.
    do Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); return end
    if _G and _G.MSUF_SuppressBlizzEditToMSUF then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); return
    end
    MSUF_EM_EnsureDB()
    if MSUF_DB and MSUF_DB.general and MSUF_DB.general.linkEditModes == false then
        if not active then
            -- Always close MSUF popups when Blizzard Edit Mode exits, even if modes are unlinked.
            if type(MSUF_SafeAfter) == "function" then
            MSUF_SafeAfter(0, "BlizzExit:ClosePopups", MSUF_CloseAllPositionPopups)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7069:29"); MSUF_FastCall(MSUF_CloseAllPositionPopups) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7069:29"); end)
        else
            MSUF_CloseAllPositionPopups()
        end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); return
    end
    if InCombatLockdown and InCombatLockdown() then
        -- Allow a COMBAT-SAFE exit path (no SecureStateDriver calls).
        -- Entering Edit Mode in combat stays blocked.
        if active then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); return
        end
        -- active == false: continue into exit flow; visibility drivers are deferred automatically.
    end

    if active then
        if MSUF_UnitEditModeActive then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); return
        end

        MSUF_EM_SetActive(true, "player")
MSUF_EditMode_StartCombatWarningListener()
        if _G.MSUF_EnableArrowKeyNudge then _G.MSUF_EnableArrowKeyNudge(true) end
        if type(MSUF_RefreshAllUnitVisibilityDrivers)=="function" then MSUF_EditMode_RequestVisibilityDrivers(true) end
        if not MSUF_CurrentEditUnitKey then
            MSUF_CurrentEditUnitKey = "player"
        end
        MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7097:22"); MSUF_EM_GetState().unitKey = MSUF_CurrentEditUnitKey Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7097:22"); end)

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
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); return
        end
            -- Reset BCDM handoff notice so it shows again next time Edit Mode is entered.
            MSUF_EM_BCDMNotice_ShownThisSession = false
            MSUF_EM_BCDMNotice_PendingCombat = false

        local function _doExit() Perfy_Trace(Perfy_GetTime(), "Enter", "_doExit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7128:14");
            Edit.Flow.Exit("blizzard", { flushPending = true })
        Perfy_Trace(Perfy_GetTime(), "Leave", "_doExit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7128:14"); end

        -- Taint/secure-stack guard: defer MSUF exit slightly so it runs after UIPanelManager finishes closing Blizzard Edit Mode.
        -- Use MSUF_SafeAfter so the callback can be invalidated by HardTeardown if needed.
        local delay = 0
        if _G.EditModeManagerFrame and _G.EditModeManagerFrame.IsShown and _G.EditModeManagerFrame:IsShown() then
            delay = 0.05
        end
        if type(MSUF_SafeAfter) == "function" then
            MSUF_SafeAfter(delay, "BlizzExit:MSUFExit", _doExit)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(delay, _doExit)
        else
            _doExit()
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7056:0"); end

-- (Snapping removed)

if type(_G.MSUF_SyncCastbarEditModeWithUnitEdit) ~= "function" then
    function _G.MSUF_SyncCastbarEditModeWithUnitEdit() Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SyncCastbarEditModeWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7151:4");
        if type(MSUF_EM_EnsureDB) == "function" then
            MSUF_EM_EnsureDB()
        end
        if not MSUF_DB or not MSUF_DB.general then
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncCastbarEditModeWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7151:4"); return
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncCastbarEditModeWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7151:4"); end
end

if not _G.MSUF_SetMSUFEditModeDirect then
    function _G.MSUF_SetMSUFEditModeDirect(active, unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7182:4");
        if InCombatLockdown and InCombatLockdown() then
            -- Entering in combat is blocked; EXIT is allowed (combat-safe), with deferred visibility driver cleanup.
            if active then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7182:4"); return
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
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7182:4"); return
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
            MSUF_FastCall(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7218:26"); MSUF_EM_GetState().unitKey = MSUF_CurrentEditUnitKey Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7218:26"); end)

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
            -- Respect "hide white arrows" toggle immediately on enter.
            MSUF_EM_RefreshWhiteArrows()
            if MSUF_UpdateEditModeInfo then
                MSUF_UpdateEditModeInfo()
            end

            -- If BetterCooldownManager is loaded, warn the user that it controls Blizzard Cooldown Manager positioning.
            MSUF_EM_ShowBCDMHandoffNoticeIfNeeded()

        else
            if not MSUF_UnitEditModeActive then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7182:4"); return
            end
            Edit.Flow.Exit("direct", { flushPending = true })
            if type(_G.MSUF_Auras2_RefreshAll) == "function" then
                _G.MSUF_Auras2_RefreshAll()
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7182:4"); end
end

if not MSUF_HookBlizzardEditMode then
MSUF_HookBlizzardEditMode = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_HookBlizzardEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7260:28");
    -- Disabled: Blizzard Edit Mode hooks removed (Blizzard lifecycle currently unstable).
    do Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_HookBlizzardEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7260:28"); return end
    if MSUF_BlizzardEditHooked then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_HookBlizzardEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7260:28"); return
    end

    if type(hooksecurefunc) ~= "function" then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_HookBlizzardEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7260:28"); return
    end

    local em = _G.EditModeManagerFrame
    if not em then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_HookBlizzardEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7260:28"); return
    end

local function MSUF_EM_GetBlizzEditModeActive() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_GetBlizzEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7276:6");
    if not em then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetBlizzEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7276:6"); return false
    end
    if type(em.IsEditModeActive) == "function" then
        local ok, v = pcall(em.IsEditModeActive, em)
        if ok then
            return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetBlizzEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7276:6", v and true or false)
        end
    end
    if em.editModeActive ~= nil then
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetBlizzEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7276:6", em.editModeActive and true or false)
    end
    if type(em.IsShown) == "function" then
        return Perfy_Trace_Passthrough("Leave", "MSUF_EM_GetBlizzEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7276:6", em:IsShown() and true or false)
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_GetBlizzEditModeActive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7276:6"); return false
end

local function MSUF_EM_SyncFromBlizzardSignal(tag) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_SyncFromBlizzardSignal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7295:6");
    local active = MSUF_EM_GetBlizzEditModeActive()
    if em._msufLastBlizzActive ~= nil and em._msufLastBlizzActive == active then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SyncFromBlizzardSignal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7295:6"); return
    end
    em._msufLastBlizzActive = active

    local _fn = (Edit and Edit.Flow and Edit.Flow.SetFromBlizzard) or MSUF_SetMSUFEditModeFromBlizzard
    local callTag = "Hook:BlizzSignal:" .. tostring(tag or "unknown")

    if type(MSUF_SafeAfter) == "function" then
        MSUF_SafeAfter(0, callTag, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7306:35");
            MSUF_SafeCall(callTag, _fn, active)
            -- Ensure modules (Auras2 preview, etc.) see Blizzard Edit Mode transitions even when unlinked.
            MSUF_EM_NotifyAnyEditMode()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7306:35"); end)
    else
        MSUF_SafeCall(callTag, _fn, active)
        MSUF_EM_NotifyAnyEditMode()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_SyncFromBlizzardSignal file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7295:6"); end

if not em._msufHookedShowHide and type(em.HookScript) == "function" then
    em._msufHookedShowHide = true
    em:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7319:28");
        MSUF_EM_SyncFromBlizzardSignal("OnShow")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7319:28"); end)
    em:HookScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7322:28");
        MSUF_EM_SyncFromBlizzardSignal("OnHide")
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7322:28"); end)
end

-- One initial sync to ensure we're aligned even if the Enter/Exit hooks change in a prepatch.
MSUF_EM_SyncFromBlizzardSignal("Initial")

    if type(em.EnterEditMode) == "function" then
        hooksecurefunc(em, "EnterEditMode", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7331:44");
            MSUF_EM_SyncFromBlizzardSignal("EnterEditMode")
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7331:44"); end)
    end

    if type(em.ExitEditMode) == "function" then
        hooksecurefunc(em, "ExitEditMode", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7337:43");
            -- Taint/secure-stack guard: defer sync slightly so it runs after UIPanelManager finishes closing Blizzard Edit Mode.
            if type(MSUF_SafeAfter) == "function" then
                MSUF_SafeAfter(0.05, "Hook:ExitEditMode", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7340:58");
                    MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7340:58"); end)
            elseif C_Timer and C_Timer.After then
                C_Timer.After(0.05, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7344:36");
                    MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7344:36"); end)
            else
                MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7337:43"); end)
    elseif type(em.OnSystemClose) == "function" then
        hooksecurefunc(em, "OnSystemClose", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7352:44");
            if type(MSUF_SafeAfter) == "function" then
                MSUF_SafeAfter(0.05, "Hook:ExitEditMode", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7354:58");
                    MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7354:58"); end)
            elseif C_Timer and C_Timer.After then
                C_Timer.After(0.05, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7358:36");
                    MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7358:36"); end)
            else
                MSUF_EM_SyncFromBlizzardSignal("ExitEditMode")
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7352:44"); end)
    end

    MSUF_BlizzardEditHooked = true
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_HookBlizzardEditMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7260:28"); end
end

if type(MSUF_EventBus_Register) == "function" then
MSUF_EventBus_Register("PLAYER_LOGIN", "MSUF_BLIZZ_EDITMODE_HOOK", function(event) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7372:67");
    -- delayed hook; fail-open if anything is missing
    -- Blizzard Edit Mode hook disabled (no scheduling).
    -- Blizzard Edit Mode hook disabled (no scheduling).
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7372:67"); end, nil, true)
else
    -- Fallback: no EventBus available (load-order / standalone testing)
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7381:27");
    -- Blizzard Edit Mode hook disabled (no scheduling).
    -- Blizzard Edit Mode hook disabled (no scheduling).
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7381:27"); end)
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


MSUF_EM_CombatSafeHideBossPreviewNow = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_CombatSafeHideBossPreviewNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7402:39");
    if not (InCombatLockdown and InCombatLockdown()) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CombatSafeHideBossPreviewNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7402:39"); return
    end

    local bossEnabled = true
    if MSUF_DB and MSUF_DB.boss and MSUF_DB.boss.enabled == false then
        bossEnabled = false
    end

    local wantPreview = bossEnabled and (MSUF_UnitEditModeActive and true or false) and (MSUF_BossTestMode and true or false)
    if wantPreview then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CombatSafeHideBossPreviewNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7402:39"); return
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
                if f.EnableMouse then MSUF_FastCall(f.EnableMouse, f, false) end
                if f.SetAlpha then MSUF_FastCall(f.SetAlpha, f, 0) end
                if f.SetScale then MSUF_FastCall(f.SetScale, f, 0.001) end
            end
        end
    end

    MSUF__EditModePendingBossPreviewResync = true
    -- Ensure we flush the hard-hide once combat ends.
    if type(MSUF_EditMode_EnsureCombatListener) == "function" then
        MSUF_EditMode_EnsureCombatListener()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_CombatSafeHideBossPreviewNow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7402:39"); end

-- ---------------------------------------------------------
-- P0: Enforce boss preview soft-hide even if other updates change alpha/scale in combat
-- ---------------------------------------------------------
-- Some update paths may call UpdateSimpleUnitFrame() while in combat and overwrite alpha/scale.
-- If a boss preview frame was soft-hidden, re-apply the soft hide after any UpdateSimpleUnitFrame() call.

-- ---------------------------------------------------------
-- P1: Boss unitframe preview fake portrait (when portraitMode is enabled)
-- ---------------------------------------------------------
-- The main unitframe update intentionally hides boss portraits when UnitExists("bossX") is false.
-- In BossTestMode (preview), UpdateSimpleUnitFrame returns early with fake hp/name, but it doesn't
-- populate a portrait. We provide a lightweight, edit-mode-only placeholder portrait here.
local function MSUF_EM_ApplyFakeBossPortrait(frame) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6");
    if not frame or not frame.isBoss or not frame.portrait then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6"); return
    end
    if not (MSUF_BossTestMode and MSUF_UnitEditModeActive) then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6"); return
    end

    local unit = frame.unit
    if unit and UnitExists and UnitExists(unit) then
        -- Never override a real boss unit.
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6"); return
    end

    local conf = (MSUF_DB and MSUF_DB.boss) or nil
    if not conf then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6"); return
    end

    local mode = conf.portraitMode or "OFF"
    if mode == "OFF" then
        -- If the user turned portrait off, ensure it stays hidden in preview too.
        if frame.portrait.Hide then MSUF_FastCall(frame.portrait.Hide, frame.portrait) end
        frame.__msufFakePortraitMode = nil
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6"); return
    end

    -- Layout (LEFT/RIGHT) matches normal behavior.
    if type(MSUF_UpdateBossPortraitLayout) == "function" then
        MSUF_FastCall(MSUF_UpdateBossPortraitLayout, frame, conf)
    end

    -- Only touch the texture when needed to reduce flicker / redundant work.
    if frame.__msufFakePortraitMode ~= mode then
        frame.__msufFakePortraitMode = mode

        if SetPortraitTexture and UnitExists and UnitExists("player") then
            -- Simple: use player portrait as a stable placeholder.
            MSUF_FastCall(SetPortraitTexture, frame.portrait, "player")
        elseif SetPortraitToTexture then
            MSUF_FastCall(SetPortraitToTexture, frame.portrait, "Interface\\ICONS\\INV_Misc_QuestionMark")
        elseif frame.portrait.SetTexture then
            MSUF_FastCall(frame.portrait.SetTexture, frame.portrait, "Interface\\ICONS\\INV_Misc_QuestionMark")
        end
    end

    if frame.portrait.Show then
        MSUF_FastCall(frame.portrait.Show, frame.portrait)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_ApplyFakeBossPortrait file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7452:6"); end


MSUF_EM_EnableUpdateSimpleUnitFrameHook = function(enable) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EM_EnableUpdateSimpleUnitFrameHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7504:42");
    enable = enable and true or false

    -- Enable hook
    if enable then
        if _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnableUpdateSimpleUnitFrameHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7504:42"); return
        end
        if type(_G.UpdateSimpleUnitFrame) ~= "function" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnableUpdateSimpleUnitFrameHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7504:42"); return
        end

        _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked = true
        _G.MSUF_UpdateSimpleUnitFrame_Impl = _G.UpdateSimpleUnitFrame

        _G.MSUF_UpdateSimpleUnitFrame_Wrapper = function(frame, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_UpdateSimpleUnitFrame_Wrapper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7519:48");
            local ok, r1, r2, r3, r4 = MSUF_FastCall(_G.MSUF_UpdateSimpleUnitFrame_Impl, frame, ...)

            -- Only do any extra work while Edit Mode is active.
            if MSUF_UnitEditModeActive then
                -- Combat soft-hide enforcement (best-effort, skipped for protected frames).
                if frame and frame.__msufSoftHidden and (InCombatLockdown and InCombatLockdown()) then
                    local protected = (frame.IsProtected and frame:IsProtected()) and true or false
                    if not protected then
                        if frame.EnableMouse then MSUF_FastCall(frame.EnableMouse, frame, false) end
                        if frame.SetAlpha then MSUF_FastCall(frame.SetAlpha, frame, 0) end
                        if frame.SetScale then MSUF_FastCall(frame.SetScale, frame, 0.001) end
                    end
                end

                -- Boss preview placeholder portrait (edit-mode only)
                if ok then
                    MSUF_EM_ApplyFakeBossPortrait(frame)
                end
            end

            if ok then
                Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_UpdateSimpleUnitFrame_Wrapper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7519:48"); return r1, r2, r3, r4
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_UpdateSimpleUnitFrame_Wrapper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7519:48"); return nil
        end

        _G.UpdateSimpleUnitFrame = _G.MSUF_UpdateSimpleUnitFrame_Wrapper
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnableUpdateSimpleUnitFrameHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7504:42"); return
    end

    -- Disable hook (restore original)
    if not _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnableUpdateSimpleUnitFrameHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7504:42"); return
    end

    if _G.UpdateSimpleUnitFrame == _G.MSUF_UpdateSimpleUnitFrame_Wrapper and type(_G.MSUF_UpdateSimpleUnitFrame_Impl) == "function" then
        _G.UpdateSimpleUnitFrame = _G.MSUF_UpdateSimpleUnitFrame_Impl
    end

    _G.MSUF_UpdateSimpleUnitFrame_MSUFHooked = nil
    _G.MSUF_UpdateSimpleUnitFrame_Wrapper = nil
    _G.MSUF_UpdateSimpleUnitFrame_Impl = nil
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EM_EnableUpdateSimpleUnitFrameHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7504:42"); end

-- P0: Combat-safe boss unitframe preview hide
-- ---------------------------------------------------------
-- The boss unitframe preview ("Test Boss") is driven by MSUF_BossTestMode and uses secure visibility drivers.
-- In combat, the default implementation returns early to avoid taint, which can leave the preview visible
-- after exiting Edit Mode while still in combat.
--
-- Fix: When in combat AND the preview should be OFF, we do a "soft hide" (alpha/scale + mouse disable)
-- for boss frames that do NOT represent a real boss unit. After combat ends, we resync once to hard-hide.
if type(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" and not _G.MSUF_SyncBossUnitframePreviewWithUnitEdit_CombatSafe then
    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit_CombatSafe = true
    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit_Impl = _G.MSUF_SyncBossUnitframePreviewWithUnitEdit

    _G.MSUF_SyncBossUnitframePreviewWithUnitEdit = function(...) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SyncBossUnitframePreviewWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7576:51");
        local ok, err = MSUF_FastCall(_G.MSUF_SyncBossUnitframePreviewWithUnitEdit_Impl, ...)
        if not ok then
            if type(MSUF_EditMode_FatalDisable) == "function" then
                MSUF_EditMode_FatalDisable("BossPreviewSync", err)
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncBossUnitframePreviewWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7576:51"); return
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
                    if f.EnableMouse then MSUF_FastCall(f.EnableMouse, f, false) end
                    if f.SetAlpha then MSUF_FastCall(f.SetAlpha, f, 0) end
                    if f.SetScale then MSUF_FastCall(f.SetScale, f, 0.001) end
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
                    if f.EnableMouse then MSUF_FastCall(f.EnableMouse, f, true) end
                    if f.SetAlpha then MSUF_FastCall(f.SetAlpha, f, 1) end
                    if f.SetScale then MSUF_FastCall(f.SetScale, f, 1) end
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

    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_SyncBossUnitframePreviewWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7576:51"); end
end

-- -------------------------------------------
-- Entry-point wrappers (fail-open)
-- -------------------------------------------
if type(MSUF_SetMSUFEditModeFromBlizzard) == "function" and not _G.MSUF_SetMSUFEditModeFromBlizzard_Impl then
    _G.MSUF_SetMSUFEditModeFromBlizzard_Impl = MSUF_SetMSUFEditModeFromBlizzard
    MSUF_SetMSUFEditModeFromBlizzard = function(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7653:39");
        return Perfy_Trace_Passthrough("Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7653:39", MSUF_SafeCall("MSUF_SetMSUFEditModeFromBlizzard", _G.MSUF_SetMSUFEditModeFromBlizzard_Impl, active))
    end
end

if type(_G.MSUF_SetMSUFEditModeDirect) == "function" and not _G.MSUF_SetMSUFEditModeDirect_Impl then
    _G.MSUF_SetMSUFEditModeDirect_Impl = _G.MSUF_SetMSUFEditModeDirect
    _G.MSUF_SetMSUFEditModeDirect = function(active, unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7660:36");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7660:36", MSUF_SafeCall("MSUF_SetMSUFEditModeDirect", _G.MSUF_SetMSUFEditModeDirect_Impl, active, unitKey))
    end
end
-- -------------------------------------------
-- Additional fail-open wrappers (popups)
-- -------------------------------------------
if type(_G.MSUF_OpenPositionPopup) == "function" and not _G.MSUF_OpenPositionPopup_Impl then
    _G.MSUF_OpenPositionPopup_Impl = _G.MSUF_OpenPositionPopup
    _G.MSUF_OpenPositionPopup = function(...) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7669:32");
        return Perfy_Trace_Passthrough("Leave", "_G.MSUF_OpenPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7669:32", MSUF_SafeCall("Popup:OpenUnit", _G.MSUF_OpenPositionPopup_Impl, ...))
    end
end

if type(MSUF_OpenCastbarPositionPopup) == "function" and not _G.MSUF_OpenCastbarPositionPopup_Impl then
    _G.MSUF_OpenCastbarPositionPopup_Impl = MSUF_OpenCastbarPositionPopup
    MSUF_OpenCastbarPositionPopup = function(...) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7676:36");
        return Perfy_Trace_Passthrough("Leave", "MSUF_OpenCastbarPositionPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7676:36", MSUF_SafeCall("Popup:OpenCastbar", _G.MSUF_OpenCastbarPositionPopup_Impl, ...))
    end
end

-- -------------------------------------------
-- Phase 1 exports (non-breaking): expose key entry points under _G.MSUF_Edit
-- -------------------------------------------
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

    -- R1: Consolidated, stable "single-file modules" API surface
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

    -- ---------------------------------------------------------
    -- R2: Bundle ALL external edit-mode entry points behind Edit.Flow.
    --     Globals remain as wrappers to preserve compatibility.
    -- ---------------------------------------------------------
    Edit.Flow = Edit.Flow or {}

    -- Capture the *real* implementations (pre-wrapper) so Flow never recurses.
    local implFromBlizzard = _G.MSUF_SetMSUFEditModeFromBlizzard_Impl or MSUF_SetMSUFEditModeFromBlizzard
    local implDirect = _G.MSUF_SetMSUFEditModeDirect_Impl or _G.MSUF_SetMSUFEditModeDirect

    -- Primary routed entry points (use the canonical SafeCall tags so fail-open works as intended).
    Edit.Flow.SetFromBlizzard = function(active) Perfy_Trace(Perfy_GetTime(), "Enter", "Flow.SetFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7732:32");
        if not active then
            local st = MSUF_EM_GetState()
            if st and st.suppressNextBlizzardExit then
                st.suppressNextBlizzardExit = false
                Perfy_Trace(Perfy_GetTime(), "Leave", "Flow.SetFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7732:32"); return
            end
        end
        return Perfy_Trace_Passthrough("Leave", "Flow.SetFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7732:32", MSUF_SafeCall("MSUF_SetMSUFEditModeFromBlizzard", implFromBlizzard, active))
    end

    Edit.Flow.SetDirect = function(active, unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "Flow.SetDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7743:26");
        return Perfy_Trace_Passthrough("Leave", "Flow.SetDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7743:26", MSUF_SafeCall("MSUF_SetMSUFEditModeDirect", implDirect, active, unitKey))
    end

    -- Convenience helpers (used by Options/commands; keeps behavior identical).
    Edit.Flow.Enter = function(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "Flow.Enter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7748:22");
        if Edit.Util and Edit.Util.ClearKeyboardFocus then
            Edit.Util.ClearKeyboardFocus()
        end
        return Perfy_Trace_Passthrough("Leave", "Flow.Enter file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7748:22", Edit.Flow.SetDirect(true, unitKey or "player"))
    end

    Edit.Flow.Exit = function(source, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "Flow.Exit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7755:21");
        -- Deterministic, non-recursive exit path. Safe in and out of combat (secure work deferred).
        if not opts then opts = { flushPending = true } end
        if not MSUF_UnitEditModeActive and type(MSUF_CloseAllPositionPopups) == "function" then
            -- Failsafe: even if state drifted, ensure popups are closed.
            MSUF_CloseAllPositionPopups()
        end
        return Perfy_Trace_Passthrough("Leave", "Flow.Exit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7755:21", MSUF_SafeCall("MSUF_EditMode_ExitDeterministic", MSUF_EditMode_ExitDeterministic, source or "flow", opts))
    end

    Edit.Flow.Toggle = function(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "Flow.Toggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7765:23");
        if MSUF_UnitEditModeActive then
            return Perfy_Trace_Passthrough("Leave", "Flow.Toggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7765:23", Edit.Flow.Exit("toggle", { flushPending = true }))
        end
        return Perfy_Trace_Passthrough("Leave", "Flow.Toggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7765:23", Edit.Flow.Enter(unitKey))
    end

    -- Keep these direct references for internal reuse.
    Edit.Flow.ExitDeterministic = Edit.Flow.ExitDeterministic or MSUF_EditMode_ExitDeterministic
    Edit.Flow.RequestVisibilityDrivers = Edit.Flow.RequestVisibilityDrivers or MSUF_EditMode_RequestVisibilityDrivers

    -- Route the global entry points through Flow (non-breaking).
    if not _G.MSUF_EditMode_R2FlowRouted then
        _G.MSUF_EditMode_R2FlowRouted = true

        -- These wrappers ensure any external caller always hits the Flow gate.
        MSUF_SetMSUFEditModeFromBlizzard = function(active) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7781:43");
            return Perfy_Trace_Passthrough("Leave", "MSUF_SetMSUFEditModeFromBlizzard file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7781:43", Edit.Flow.SetFromBlizzard(active))
        end

        _G.MSUF_SetMSUFEditModeDirect = function(active, unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7785:40");
            return Perfy_Trace_Passthrough("Leave", "_G.MSUF_SetMSUFEditModeDirect file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua:7785:40", Edit.Flow.SetDirect(active, unitKey))
        end

        -- Keep Transition handle aligned with the routed wrapper.
        Edit.Transitions.SetMSUFEditModeDirect = _G.MSUF_SetMSUFEditModeDirect
    end
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\MSUF_EditMode.lua");