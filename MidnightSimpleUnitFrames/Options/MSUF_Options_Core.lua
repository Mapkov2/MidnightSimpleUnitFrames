local addonName, ns = ...
ns = ns or {}
if _G then _G.MSUF_NS = ns end
-- Slash-menu-only: the Slash Menu is the only options UI. Blizzard Settings shows only a lightweight launcher.
if _G then _G.MSUF_SLASHMENU_ONLY = true end

-- L table setup (canonical location; Toolkit also guards this)
ns.L = ns.L or (_G and _G.MSUF_L) or {}
if not getmetatable(ns.L) then setmetatable(ns.L, { __index = function(t, k) return k end }) end
local TR = ns.TR or function(v) if type(v) ~= "string" then return v end; return ns.L[v] or v end

-- ---------------------------------------------------------------------------
-- Deferred Options Init System (Ellesmere-inspired)
--
-- Options files register heavy initialization via ns.MSUF_Options_DeferInit(fn).
-- All registered closures execute on the first ns.MSUF_Options_EnsureLoaded()
-- call, which fires when CreateOptionsPanel() runs for the first time.
--
-- This means ~18K lines of Options Lua across all files only execute their
-- heavy widget-building code on first panel open — zero overhead at login
-- beyond the unavoidable file parse.
--
-- Usage in split-out Options files (e.g. MSUF_Options_Auras.lua):
--
--   local addonName, ns = ...
--   ns = ns or {}
--   ns.MSUF_Options_DeferInit(function()
--       -- 2789 lines of heavy aura options UI code
--       function ns.MSUF_RegisterAurasOptions(rootCat) ... end
--   end)
--
-- The closure body is NOT executed at login; it runs only when the user
-- opens the MSUF options panel for the first time.
-- ---------------------------------------------------------------------------
do
    -- Guard: another file in the suite may have already installed the system.
    if not ns._optionsDeferredInits then
        ns._optionsDeferredInits = {}
        ns._optionsDeferredLoaded = false
    end

    if not ns.MSUF_Options_DeferInit then
        --- Register a function to run on first options-panel open.
        --- If EnsureLoaded has already fired (late-loaded file), executes immediately.
        function ns.MSUF_Options_DeferInit(fn)
            if type(fn) ~= "function" then return end
            if ns._optionsDeferredLoaded then
                fn()
            else
                local t = ns._optionsDeferredInits
                t[#t + 1] = fn
            end
        end
    end

    if not ns.MSUF_Options_EnsureLoaded then
        --- Execute all registered deferred inits (idempotent).
        function ns.MSUF_Options_EnsureLoaded()
            if ns._optionsDeferredLoaded then return end
            ns._optionsDeferredLoaded = true
            local inits = ns._optionsDeferredInits
            for i = 1, #inits do
                inits[i]()
                inits[i] = nil          -- release reference for GC
            end
        end
    end

    -- Export to _G so split-out Options files that use _G.MSUF_NS can access it
    -- without depending on the vararg `ns` (e.g. MSUF_Options_ClassPower.lua).
    if _G then
        _G.MSUF_Options_DeferInit    = _G.MSUF_Options_DeferInit    or ns.MSUF_Options_DeferInit
        _G.MSUF_Options_EnsureLoaded = _G.MSUF_Options_EnsureLoaded or ns.MSUF_Options_EnsureLoaded
    end
end

-- File-scope locals (avoid accidental globals; safe for split modules)
local panel, title, sub
local searchBox
local frameGroup, frameGroupHost, fontGroup, auraGroup, castbarGroup, castbarGroupHost
local barGroup, barGroupHost
local classPowerGroup, classPowerGroupHost
local MSUF_BarsApplyGradient -- forward decl; see MSUF_Options_Bars.lua (exports to _G)
-- ---------------------------------------------------------------------------
-- Gradient changes apply live (no reload required).
-- Keep a no-op stub so any stale call-sites (older builds) don't nil-error.
-- ---------------------------------------------------------------------------
local function MSUF_Options_ShowGradientReloadPopup() end -- no-op stub (live apply, backward compat)
-- ---------------------------------------------------------------------------
-- Transition helpers (optional, graceful fallback to instant Show/Hide)
-- ---------------------------------------------------------------------------
local function _T() return ns.MSUF_Transitions end
local function _TFadeIn(f, d)
    local T = _T()
    if T and T.FadeIn then T.FadeIn(f, d) else if f and f.Show then f:Show() end end
end
local TRANS_TAB = 0.10
local function MSUF_ScheduleReloadRecommend()   end       -- no-op stub (backward compat)
local castbarEnemyGroup, castbarTargetGroup, castbarFocusGroup, castbarBossGroup, castbarPlayerGroup
local barGroupHost, barGroup, miscGroup, profileGroup
-- ---------------------------------------------------------------------------
-- Bars menu: scroll container (same UIPanelScrollFrameTemplate method as Auras/Gameplay/Colors)
-- ---------------------------------------------------------------------------
local function MSUF_BarsMenu_QueueScrollUpdate()
    local host = barGroupHost
    local scroll = (_G and _G.MSUF_BarsMenuScrollFrame) or (host and host._msufBarsScroll) or nil
    local child  = (_G and _G.MSUF_BarsMenuScrollChild) or (host and host._msufBarsScrollChild) or nil
    if not (scroll and child and child.SetHeight and child.GetTop and child.GetBottom) then return end

    local anchor = _G and (_G.MSUF_BarsMenuPanelRight or _G.MSUF_BarsMenuPanelLeft) or nil
    if not (anchor and anchor.GetBottom) then anchor = barGroup end
    if not (anchor and anchor.GetBottom) then return end

    if host then
        if host._msufBarsScrollQueued then return end
        host._msufBarsScrollQueued = true
    end

    local function run()
        if host then host._msufBarsScrollQueued = false end
        if not (scroll and child and anchor) then return end
        local top = child:GetTop()
        local bottom = anchor:GetBottom()
        if not (top and bottom) then return end

        local h = math.ceil((top - bottom) + 24)
        if h < 500 then h = 500 end
        child:SetHeight(h)

        local w = scroll:GetWidth()
        if w and w > 1 then child:SetWidth(w) end

        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        if _G and _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, run)
    else
        run()
    end
end

-- ---------------------------------------------------------------------------
-- Frames menu: scroll container (same pattern as Bars menu above)
-- ---------------------------------------------------------------------------
local function MSUF_FramesMenu_QueueScrollUpdate()
    local host = frameGroupHost
    if not host then return end
    local scroll = host._msufFramesScroll
    local child  = host._msufFramesScrollChild
    if not (scroll and child and child.SetHeight) then return end

    if host._msufFramesScrollQueued then return end
    host._msufFramesScrollQueued = true

    local function run()
        host._msufFramesScrollQueued = false
        if not (scroll and child) then return end

        -- Measure from scroll child top to the lowest visible group box bottom.
        local top = child.GetTop and child:GetTop()
        if not top then return end

        local lowest = top
        local content = host._msufFramesContent
        if content then
            local regions = { content:GetChildren() }
            for i = 1, #regions do
                local r = regions[i]
                if r and r.IsShown and r:IsShown() and r.GetBottom then
                    local b = r:GetBottom()
                    if b and b < lowest then lowest = b end
                end
            end
        end

        local h = math.ceil((top - lowest) + 32)
        if h < 500 then h = 500 end
        child:SetHeight(h)

        local w = scroll:GetWidth()
        if w and w > 1 then child:SetWidth(w) end

        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        if _G and _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, run)
    else
        run()
    end
end

-- ---------------------------------------------------------------------------
-- Castbar menu: scroll container (same pattern as Frames/Bars menus)
-- ---------------------------------------------------------------------------
local function MSUF_CastbarMenu_QueueScrollUpdate()
    local host = castbarGroupHost
    if not host then return end
    local scroll = host._msufCastbarScroll
    local child  = host._msufCastbarScrollChild
    if not (scroll and child and child.SetHeight) then return end

    if host._msufCastbarScrollQueued then return end
    host._msufCastbarScrollQueued = true

    local function run()
        host._msufCastbarScrollQueued = false
        if not (scroll and child) then return end

        local top = child.GetTop and child:GetTop()
        if not top then return end

        local lowest = top
        local content = host._msufCastbarContent
        if content then
            local regions = { content:GetChildren() }
            for i = 1, #regions do
                local r = regions[i]
                if r and r.IsShown and r:IsShown() and r.GetBottom then
                    local b = r:GetBottom()
                    if b and b < lowest then lowest = b end
                end
            end
        end

        local h = math.ceil((top - lowest) + 32)
        if h < 500 then h = 500 end
        child:SetHeight(h)

        local w = scroll:GetWidth()
        if w and w > 1 then child:SetWidth(w) end

        if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
        if _G and _G.UIPanelScrollFrame_Update then _G.UIPanelScrollFrame_Update(scroll) end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, run)
    else
        run()
    end
end

-- SharedMedia helper (LSM is initialized in MSUF_Libs.lua)
local function MSUF_GetLSM()
    return (ns and ns.LSM) or _G.MSUF_LSM
end
-- Ensure the Castbars LoD addon is loaded before calling castbar functions.
local function MSUF_EnsureCastbars()
    if type(_G.MSUF_EnsureAddonLoaded) == "function" then
        _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
         return
    end
    -- Fallback (older clients)
    if _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then
        pcall(_G.C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
    elseif type(_G.LoadAddOn) == "function" then
        pcall(_G.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
    end
 end
-- ============================================================
-- Toolkit imports (defined in MSUF_Options_Toolkit.lua, loaded before Core)
-- ============================================================
local MSUF_AttachTooltip          = ns.MSUF_AttachTooltip
local UI_Text                     = ns.MSUF_UI_Text
local UI_Btn                      = ns.MSUF_UI_Btn
local MSUF_BuildButtonRowList     = ns.MSUF_BuildButtonRowList
-- Old dropdown helpers (MakeDropdownScrollable, ExpandDropdownClickArea, InitSimpleDropdown,
-- SyncSimpleDropdown) are now provided by Toolkit or Widgets.lua. Core no longer uses them directly.
-- Options Core (extracted from MidnightSimpleUnitFrames.lua)
-- NOTE: This file is intentionally self-contained for math/string locals to avoid relying on main-file locals.
local floor  = math.floor
local max    = math.max
local min    = math.min
local format = string.format
local UIParent = UIParent
local CreateFrame = CreateFrame
local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local MSUF_MAX_BOSS_FRAMES = 5
-- Hard-disable the always-visible menu preview bars (texture previews under dropdowns).
-- We keep the dropdowns fully functional; we just never show the extra StatusBar previews.
local function MSUF_KillMenuPreviewBar(bar)
    if not bar then  return end
    bar:Hide()
    if bar.SetAlpha then bar:SetAlpha(0) end
    if bar.SetHeight then bar:SetHeight(0.1) end
    -- Prevent any later code from showing it again
    bar.Show = function()   end
    bar.SetShown = function()   end
 end
-- Call into main/module font refresh (main chunk may keep this local; main exports MSUF_UpdateAllFonts)
local function MSUF_CallUpdateAllFonts()
    local fn
    if _G then fn = _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts end
    if (not fn) and ns and ns.MSUF_UpdateAllFonts then
        fn = ns.MSUF_UpdateAllFonts
    end
    if type(fn) == "function" then return fn() end
 end
-- Local number parser (Options chunk cant rely on main-file locals)
local function MSUF_GetNumber(text, default, minVal, maxVal)
    local n = tonumber(text)
    if n == nil then n = default end
    if n == nil then n = 0 end
    n = floor(n + 0.5)
    if minVal ~= nil and n < minVal then n = minVal end
    if maxVal ~= nil and n > maxVal then n = maxVal end
     return n
end
-- Register the MSUF Settings category at login, but build the heavy UI only when the panel is first opened.
-- This greatly reduces addon load/login CPU (no more building thousands of UI widgets during PLAYER_LOGIN).
function MSUF_RegisterOptionsCategoryLazy()
    -- Slash-menu-only build: Blizzard Settings shows a lightweight launcher panel only.
    -- The legacy multi-panel Settings UI is intentionally not registered anymore.
    if _G then _G.MSUF_SLASHMENU_ONLY = true end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then  return end
    -- Root (AddOns list) panel: lightweight launcher with a single button.
    local launcher = (_G and _G.MSUF_LauncherPanel) or CreateFrame("Frame")
    if _G then _G.MSUF_LauncherPanel = launcher end
    launcher.name = "Midnight Simple Unit Frames"
    -- Register the main category now (cheap) so users can find MSUF in Blizzard Settings.
    local rootCat = (_G and _G.MSUF_SettingsCategory) or nil
    if not rootCat then
        local cat = Settings.RegisterCanvasLayoutCategory(launcher, launcher.name)
        Settings.RegisterAddOnCategory(cat)
        rootCat = cat
        if _G then _G.MSUF_SettingsCategory = cat end
    end
    MSUF_SettingsCategory = rootCat
    if ns then ns.MSUF_MainCategory = rootCat end
    -- Combat-safe opener: avoid blocked actions/taint by deferring UI opens until after combat.
    local function MSUF_RunAfterCombat(fn)
        if InCombatLockdown and InCombatLockdown() then
            if _G then _G.MSUF_PendingOpenAfterCombat = fn end
            local f = _G and _G.MSUF_CombatDeferFrame
            if not f then
                f = CreateFrame("Frame")
                if _G then _G.MSUF_CombatDeferFrame = f end
                f:RegisterEvent("PLAYER_REGEN_ENABLED")
                f:SetScript("OnEvent", function(self)
                    local pending = _G and _G.MSUF_PendingOpenAfterCombat
                    if pending then
                        _G.MSUF_PendingOpenAfterCombat = nil
                        pending()
                    end
                    -- Zero combat overhead: unregister when nothing is pending
                    if not (_G and _G.MSUF_PendingOpenAfterCombat) then
                        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                        self:SetScript("OnEvent", nil)
                        if _G then _G.MSUF_CombatDeferFrame = nil end
                    end
                 end)
            end
            if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00MSUF:|r Cannot open the menu while in combat. Will open after combat.")
            elseif print then
                print("MSUF: Cannot open the menu while in combat. Will open after combat.")
            end
             return
        end
        fn()
     end
    local function MSUF_BuildLauncherUI()
        if launcher.__MSUF_LauncherBuilt then  return end
        launcher.__MSUF_LauncherBuilt = true
        local title = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        launcher.__MSUF_LauncherTitle = title
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(TR("Midnight Simple Unit Frames"))
        local desc = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        launcher.__MSUF_LauncherDesc = desc
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        desc:SetJustifyH("LEFT")
        desc:SetJustifyV("TOP")
        desc:SetText(TR("MSUF is configured via the in-game MSUF menu.\n\nUse the button below (or /msuf) to open it."))
        local w = launcher.GetWidth and launcher:GetWidth() or 0
        if w and w > 0 then
            desc:SetWidth(math.max(420, w - 40))
        else
            desc:SetWidth(600)
        end
        local btn = CreateFrame("Button", nil, launcher, "UIPanelButtonTemplate")
        launcher.__MSUF_LauncherBtnOpen = btn
        btn:SetSize(260, 32)
        btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
        btn:SetText(TR("Open MSUF Menu"))
        btn:SetScript("OnClick", function()
            MSUF_RunAfterCombat(function()
                if _G and type(_G.MSUF_OpenPage) == "function" then
                    _G.MSUF_OpenPage("home")
                elseif _G and type(_G.MSUF_OpenOptionsMenu) == "function" then
                    _G.MSUF_OpenOptionsMenu()
                elseif _G and type(_G.MSUF_ShowStandaloneOptionsWindow) == "function" then
                    _G.MSUF_ShowStandaloneOptionsWindow("home")
                end
             end)
         end)
        local note = launcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -10)
        note:SetJustifyH("LEFT")
        note:SetText(TR("Tip: /msuf opens the menu."))
     end
    if not launcher.__MSUF_LauncherOnShowHooked then
        launcher.__MSUF_LauncherOnShowHooked = true
        launcher:SetScript("OnShow", function(self)
            if not self.__MSUF_LauncherBuilt then MSUF_BuildLauncherUI() end
            local d = self.__MSUF_LauncherDesc
            if d and d.SetWidth then
                local w = self.GetWidth and self:GetWidth() or 0
                if w and w > 0 then d:SetWidth(math.max(420, w - 40)) end
            end
         end)
        launcher:SetScript("OnSizeChanged", function(self)
            local d = self.__MSUF_LauncherDesc
            if d and d.SetWidth then
                local w = self.GetWidth and self:GetWidth() or 0
                if w and w > 0 then d:SetWidth(math.max(420, w - 40)) end
            end
         end)
    end
    -- Build now too (some containers show the panel without firing OnShow the first time)
    MSUF_BuildLauncherUI()
 end
-- Forward declarations (Lua resolves unknown locals in functions as GLOBALS at compile time).
-- CreateOptionsPanel() references these helpers later, so they must be declared first.
local CreateLabeledSlider
local MSUF_SetLabeledSliderValue
function CreateOptionsPanel()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then  return end
    -- Run all deferred inits from split-out Options files (idempotent; zero cost after first call).
    ns.MSUF_Options_EnsureLoaded()
    -- If the panel was already fully built, just refresh it.
    if _G and _G.MSUF_OptionsPanel and _G.MSUF_OptionsPanel.__MSUF_FullBuilt then
        local p = _G.MSUF_OptionsPanel
        if p.LoadFromDB then p:LoadFromDB() end
         return p
    end
    EnsureDB()
    local searchBox
-- One-Flush + No-Layout-In-Runtime policy:
-- Options that affect layout should request a UFCore layout flush (DIRTY_LAYOUT) instead of forcing full updates.
local function MSUF_Options_NormalizeUnitKey(unitKey)
    if unitKey == "tot" then  return "targettarget" end
    if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unitKey) then  return "boss" end
     return unitKey
end
local function MSUF_Options_IsUrgentUnitKey(unitKey)
    return (unitKey == "target" or unitKey == "targettarget" or unitKey == "focus")
end
local function MSUF_Options_RequestLayoutForKey(unitKey, reason, urgent)
    unitKey = MSUF_Options_NormalizeUnitKey(unitKey)
    if type(unitKey) ~= "string" then  return false end
    local fn = _G and _G.MSUF_UFCore_RequestLayoutForUnit
    if type(fn) == "function" then
        if urgent == nil then urgent = MSUF_Options_IsUrgentUnitKey(unitKey) end
        -- Signature is flexible (extra args are ignored safely).
        pcall(fn, unitKey, reason or "OPTIONS", urgent)
         return true
    end
    -- Fallback path for older cores
    if type(ApplySettingsForKey) == "function" then
        pcall(ApplySettingsForKey, unitKey)
         return true
    end
    if type(ApplyAllSettings) == "function" then
        pcall(ApplyAllSettings)
         return true
    end
     return false
end
local function MSUF_Options_RequestLayoutAll(reason)
    local keys = { "player", "target", "focus", "targettarget", "pet", "boss" }
    for _, k in ipairs(keys) do
        MSUF_Options_RequestLayoutForKey(k, reason or "OPTIONS_ALL", MSUF_Options_IsUrgentUnitKey(k))
    end
 end
-- Export for split modules (Fonts/Misc/etc.) so they can request a layout refresh without relying on Core locals.
if ns and not ns.MSUF_Options_RequestLayoutAll then ns.MSUF_Options_RequestLayoutAll = MSUF_Options_RequestLayoutAll end
local function MSUF_UpdatePowerBarHeightFromEdit(editBox)
    if not editBox or not editBox.GetText then  return end
    local text = editBox:GetText()
    local v = MSUF_GetNumber(text, 3, 3, 50)
    editBox:SetText(tostring(v))
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.powerBarHeight = v
    if _G.MSUF_UnitFrames then
        local units = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
        for _, key in ipairs(units) do
            local f = _G.MSUF_UnitFrames[key]
            if f and f.targetPowerBar then
                f.targetPowerBar:SetHeight(v)
                if type(_G.MSUF_ApplyPowerBarEmbedLayout) == 'function' then _G.MSUF_ApplyPowerBarEmbedLayout(f) end
            end
        end
    end
    ApplyAllSettings()
 end
local function MSUF_UpdatePowerBarBorderSizeFromEdit(editBox)
    if not editBox or not editBox.GetText then  return end
    local text = editBox:GetText()
    local v = MSUF_GetNumber(text, 1, 1, 10)
    editBox:SetText(tostring(v))
    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.powerBarBorderSize = v
    if type(_G.MSUF_ApplyPowerBarBorder_All) == 'function' then
        _G.MSUF_ApplyPowerBarBorder_All()
    else
        ApplyAllSettings()
    end
 end
panel = (_G and _G.MSUF_OptionsPanel) or CreateFrame("Frame")
    _G.MSUF_OptionsPanel = panel
    panel.name = "Midnight Simple Unit Frames"
    title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(TR("Midnight Simple Unit Frames (Beta Version)"))
    sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    -- Keep this subtitle short (avoid wrapping into the navigation rows) and avoid ALL-CAPS.
    sub:SetText(TR("Thank you for using MSUF."))
    local searchLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetText(TR(""))
    searchLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -260, -24)
    searchBox = CreateFrame("EditBox", "MSUF_OptionsSearchBox", panel, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    if ns then
        ns.MSUF_MainSearchBox = searchBox
        ns.MSUF_SearchAnchor  = searchBox
    end
    if (_G and _G.MSUF_SLASHMENU_ONLY) then
        -- When hosted by the Slash Menu, do not render legacy header/search UI.
        if title and title.Hide then title:Hide() end
        if sub and sub.Hide then sub:Hide() end
        if searchLabel and searchLabel.Hide then searchLabel:Hide() end
        if searchBox and searchBox.Hide then searchBox:Hide() end
    end
    -- Frames menu: scrollable host (same pattern as Bars menu).
    frameGroupHost = CreateFrame("Frame", "MSUF_FramesMenuHost", panel)
    frameGroupHost:SetAllPoints()

    local framesScroll = CreateFrame("ScrollFrame", "MSUF_FramesMenuScrollFrame", frameGroupHost, "UIPanelScrollFrameTemplate")
    framesScroll:SetPoint("TOPLEFT", frameGroupHost, "TOPLEFT", 0, -110)
    framesScroll:SetPoint("BOTTOMRIGHT", frameGroupHost, "BOTTOMRIGHT", -36, 16)

    local framesScrollChild = CreateFrame("Frame", "MSUF_FramesMenuScrollChild", framesScroll)
    framesScrollChild:SetSize(1, 1)
    framesScroll:SetScrollChild(framesScrollChild)

    -- Content root: same offsets as before; no layout regression.
    frameGroup = CreateFrame("Frame", "MSUF_FramesMenuContent", framesScrollChild)
    frameGroup:SetPoint("TOPLEFT", framesScrollChild, "TOPLEFT", 0, 110)
    frameGroup:SetSize(760, 1200)

    -- Cache for the height updater + resize hooks.
    frameGroupHost._msufFramesScroll      = framesScroll
    frameGroupHost._msufFramesScrollChild = framesScrollChild
    frameGroupHost._msufFramesContent     = frameGroup
    if frameGroupHost.HookScript then
        frameGroupHost:HookScript("OnShow", MSUF_FramesMenu_QueueScrollUpdate)
        frameGroupHost:HookScript("OnSizeChanged", MSUF_FramesMenu_QueueScrollUpdate)
    end
    fontGroup = CreateFrame("Frame", nil, panel)
    fontGroup:SetAllPoints()
    auraGroup = CreateFrame("Frame", nil, panel)
    auraGroup:SetAllPoints()
    -- Castbar menu: scrollable host (same pattern as Frames/Bars menus).
    castbarGroupHost = CreateFrame("Frame", "MSUF_CastbarMenuHost", panel)
    castbarGroupHost:SetAllPoints()

    local castbarScroll = CreateFrame("ScrollFrame", "MSUF_CastbarMenuScrollFrame", castbarGroupHost, "UIPanelScrollFrameTemplate")
    castbarScroll:SetPoint("TOPLEFT", castbarGroupHost, "TOPLEFT", 0, -110)
    castbarScroll:SetPoint("BOTTOMRIGHT", castbarGroupHost, "BOTTOMRIGHT", -36, 16)

    local castbarScrollChild = CreateFrame("Frame", "MSUF_CastbarMenuScrollChild", castbarScroll)
    castbarScrollChild:SetSize(1, 1)
    castbarScroll:SetScrollChild(castbarScrollChild)

    -- Content root: same offsets as before; no layout regression.
    castbarGroup = CreateFrame("Frame", "MSUF_CastbarMenuContent", castbarScrollChild)
    castbarGroup:SetPoint("TOPLEFT", castbarScrollChild, "TOPLEFT", 0, 110)
    castbarGroup:SetSize(760, 1200)

    -- Cache for the height updater + resize hooks.
    castbarGroupHost._msufCastbarScroll      = castbarScroll
    castbarGroupHost._msufCastbarScrollChild = castbarScrollChild
    castbarGroupHost._msufCastbarContent     = castbarGroup
    if castbarGroupHost.HookScript then
        castbarGroupHost:HookScript("OnShow", MSUF_CastbarMenu_QueueScrollUpdate)
        castbarGroupHost:HookScript("OnSizeChanged", MSUF_CastbarMenu_QueueScrollUpdate)
    end
    local function MSUF_HideLegacyCastbarEditButton()
        local names = {
            'MSUF_CastbarEditModeButton',
            'MSUF_CastbarEditButton',
            'MSUF_CastbarEditMode',
            'MSUF_CastbarEdit',
            'MSUF_CastbarPlayerPreviewCheck',
        }
        for _, n in ipairs(names) do
            local obj = _G[n]
            if obj and obj.Hide then
                obj:Hide()
                if obj.EnableMouse then obj:EnableMouse(false) end
                if obj.SetEnabled then obj:SetEnabled(false) end
            end
        end
     end
    castbarGroup:HookScript('OnShow', function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, MSUF_HideLegacyCastbarEditButton)
        else
            MSUF_HideLegacyCastbarEditButton()
        end
     end)
    castbarEnemyGroup = CreateFrame("Frame", "MSUF_CastbarEnemyGroup", castbarGroup)
    castbarEnemyGroup:SetAllPoints()
    castbarTargetGroup = CreateFrame("Frame", "MSUF_CastbarTargetGroup", castbarGroup)
    castbarTargetGroup:SetAllPoints()
    castbarTargetGroup:Hide()
    castbarFocusGroup = CreateFrame("Frame", "MSUF_CastbarFocusGroup", castbarGroup)
    castbarFocusGroup:SetAllPoints()
    castbarFocusGroup:Hide()
    castbarBossGroup = CreateFrame("Frame", "MSUF_CastbarBossGroup", castbarGroup)
    castbarBossGroup:SetAllPoints()
    castbarBossGroup:Hide()
    castbarPlayerGroup = CreateFrame("Frame", "MSUF_CastbarPlayerGroup", castbarGroup)
    castbarPlayerGroup:SetAllPoints()
    castbarPlayerGroup:Hide()
    -- Bars menu: make it scrollable like Auras/Gameplay/Colors (UIPanelScrollFrameTemplate).
    -- We keep the existing absolute Y offsets by placing an inner content root 110px ABOVE the scroll child.
    barGroupHost = CreateFrame("Frame", "MSUF_BarsMenuHost", panel)
    barGroupHost:SetAllPoints()

    local barsScroll = CreateFrame("ScrollFrame", "MSUF_BarsMenuScrollFrame", barGroupHost, "UIPanelScrollFrameTemplate")
    barsScroll:SetPoint("TOPLEFT", barGroupHost, "TOPLEFT", 0, -110)
    barsScroll:SetPoint("BOTTOMRIGHT", barGroupHost, "BOTTOMRIGHT", -36, 16)

    local barsScrollChild = CreateFrame("Frame", "MSUF_BarsMenuScrollChild", barsScroll)
    barsScrollChild:SetSize(1, 1)
    barsScroll:SetScrollChild(barsScrollChild)

    -- Inner root used by ALL bars widgets (same offsets as before; no layout regression).
    barGroup = CreateFrame("Frame", "MSUF_BarsMenuContent", barsScrollChild)
    barGroup:SetPoint("TOPLEFT", barsScrollChild, "TOPLEFT", 0, 110)
    barGroup:SetSize(760, 1200)

    -- Cache for the height updater + attach cold-path resize hooks.
    barGroupHost._msufBarsScroll = barsScroll
    barGroupHost._msufBarsScrollChild = barsScrollChild
    if barGroupHost.HookScript then
        barGroupHost:HookScript("OnShow", MSUF_BarsMenu_QueueScrollUpdate)
        barGroupHost:HookScript("OnSizeChanged", MSUF_BarsMenu_QueueScrollUpdate)
    end

    -- Class Resources menu: dedicated tab (no Bars content).
    classPowerGroupHost = CreateFrame("Frame", "MSUF_ClassPowerMenuHost", panel)
    classPowerGroupHost:SetAllPoints()

    local cpScroll = CreateFrame("ScrollFrame", "MSUF_ClassPowerMenuScrollFrame", classPowerGroupHost, "UIPanelScrollFrameTemplate")
    cpScroll:SetPoint("TOPLEFT", classPowerGroupHost, "TOPLEFT", 0, -110)
    cpScroll:SetPoint("BOTTOMRIGHT", classPowerGroupHost, "BOTTOMRIGHT", -36, 16)

    local cpScrollChild = CreateFrame("Frame", "MSUF_ClassPowerMenuScrollChild", cpScroll)
    cpScrollChild:SetSize(1, 1)
    cpScroll:SetScrollChild(cpScrollChild)

    classPowerGroup = CreateFrame("Frame", "MSUF_ClassPowerMenuContent", cpScrollChild)
    -- NOTE: Unlike the legacy Bars layout, the Class Resources page is built
    -- with a normal top-aligned header. Do NOT apply the +110px "legacy offset"
    -- compensation here, or the first headers get pushed above the scroll view
    -- and appear clipped.
    classPowerGroup:SetPoint("TOPLEFT", cpScrollChild, "TOPLEFT", 0, 0)
    classPowerGroup:SetSize(760, 900)

    -- Dummy anchor panels (hidden) used by MSUF_Options_ClassPower to size/anchor cpPanel.
    do
        local lp = CreateFrame("Frame", "MSUF_ClassPowerMenuPanelLeft", classPowerGroup)
        lp:SetSize(330, 1)
        lp:SetPoint("TOPLEFT", classPowerGroup, "TOPLEFT", 0, -20)
        lp:Hide()
        local rp = CreateFrame("Frame", "MSUF_ClassPowerMenuPanelRight", classPowerGroup)
        rp:SetSize(320, 1)
        rp:SetPoint("TOPLEFT", lp, "TOPRIGHT", 0, 0)
        rp:Hide()
    end

    classPowerGroupHost._msufClassPowerScroll = cpScroll
    classPowerGroupHost._msufClassPowerScrollChild = cpScrollChild
    if classPowerGroupHost.HookScript then
        classPowerGroupHost:HookScript("OnShow", function()
            if cpScroll and cpScroll.SetVerticalScroll then cpScroll:SetVerticalScroll(0) end
            if type(_G.MSUF_EnsureClassPowerMenuBuilt) == "function" then
                pcall(_G.MSUF_EnsureClassPowerMenuBuilt)
            end
        end)
    end
    miscGroup = CreateFrame("Frame", nil, panel)
    miscGroup:SetAllPoints()
    profileGroup = CreateFrame("Frame", nil, panel)
    profileGroup:SetAllPoints()
    local currentKey = "player"
    local currentTabKey = "frames"
    local UNIT_FRAME_KEYS = { player=true, target=true, targettarget=true, focus=true, pet=true, boss=true }
    local buttons = {}
    local editModeButton
    local __MSUF_SLASH_ONLY = (_G and _G.MSUF_SLASHMENU_ONLY) and true or false
    local function GetLabelForKey(key)
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
             return "Boss Frames"
        elseif key == "bars" then
             return "Bars"
        elseif key == "classpower" then
             return "Class Resources"
        elseif key == "fonts" then
             return "Fonts"
        elseif key == "auras" then
             return "Auras"
        elseif key == "castbar" then
             return "Castbar"
        elseif key == "misc" then
             return "Miscellaneous"
        elseif key == "profiles" then
             return "Profiles"
        end
         return key
    end
    local function UpdateGroupVisibility()
        -- Hide all instantly, then FadeIn the active group
        frameGroupHost:Hide()
        fontGroup:Hide()
        auraGroup:Hide()
        castbarGroupHost:Hide()
        barGroupHost:Hide()
        if classPowerGroupHost then classPowerGroupHost:Hide() end
        miscGroup:Hide()
        profileGroup:Hide()
        if currentTabKey == "fonts" then
            _TFadeIn(fontGroup, TRANS_TAB)
        elseif currentTabKey == "bars" then
            _TFadeIn(barGroupHost, TRANS_TAB)
        elseif currentTabKey == "classpower" then
            _TFadeIn(classPowerGroupHost, TRANS_TAB)
        elseif currentTabKey == "auras" then
            _TFadeIn(auraGroup, TRANS_TAB)
        elseif currentTabKey == "castbar" then
            -- Reset scroll to top when switching to castbar tab.
            local cbScroll = castbarGroupHost._msufCastbarScroll
            if cbScroll and cbScroll.SetVerticalScroll then
                cbScroll:SetVerticalScroll(0)
            end
            _TFadeIn(castbarGroupHost, TRANS_TAB)
            MSUF_CastbarMenu_QueueScrollUpdate()
        elseif currentTabKey == "misc" then
            _TFadeIn(miscGroup, TRANS_TAB)
        elseif currentTabKey == "profiles" then
            _TFadeIn(profileGroup, TRANS_TAB)
        else
            -- Reset scroll to top when switching unit tabs.
            local frScroll = frameGroupHost._msufFramesScroll
            if frScroll and frScroll.SetVerticalScroll then
                frScroll:SetVerticalScroll(0)
            end
            _TFadeIn(frameGroupHost, TRANS_TAB)
            -- Player-only layout: hide the old right-column offset sliders and show the compact group.
            local isUnitFrame = (UNIT_FRAME_KEYS[currentKey] == true)
            if panel and panel.playerTextLayoutGroup then panel.playerTextLayoutGroup:SetShown(isUnitFrame) end
            if panel and panel.playerBasicsBox then
                panel.playerBasicsBox:SetShown(isUnitFrame)
            end
            if panel and panel.playerCastbarBox then panel.playerCastbarBox:SetShown(isUnitFrame) end
            if panel and panel.playerLoadCondBox then panel.playerLoadCondBox:SetShown(isUnitFrame) end
            if panel and panel.playerSizeBox then panel.playerSizeBox:SetShown(isUnitFrame) end
            if panel and panel.unitAnchorGroup then panel.unitAnchorGroup:SetShown(isUnitFrame) end
            -- Recalculate scroll height after layout changes.
            MSUF_FramesMenu_QueueScrollUpdate()
        end
        if editModeButton then
            -- Show the shared bottom-left Edit Mode button in:
            -- * Frames tab (unit frames) — inside scroll content
            -- * Castbar tab (castbar edit mode) — fixed at panel bottom
            if currentTabKey == "castbar" then
                -- Place inside castbar scroll content below the menu panel.
                editModeButton:SetParent(castbarGroup)
                editModeButton:ClearAllPoints()
                local cbPanel = _G["MSUF_CastbarMenuPanel"]
                if cbPanel then
                    editModeButton:SetPoint("TOPLEFT", cbPanel, "BOTTOMLEFT", 0, -12)
                else
                    editModeButton:SetPoint("BOTTOMLEFT", castbarGroup, "BOTTOMLEFT", 16, 16)
                end
                editModeButton:Show()
            elseif currentTabKey == "frames" and (
                currentKey == "player"
                or currentKey == "target"
                or currentKey == "targettarget"
                or currentKey == "focus"
                or currentKey == "boss"
                or currentKey == "pet"
            ) then
                editModeButton:SetParent(frameGroup)
                editModeButton:ClearAllPoints()
                local anchorBox = panel and (panel._msufBottomAnchor or panel.unitAnchorGroup or panel.playerSizeBox)
                if anchorBox then
                    editModeButton:SetPoint("TOPRIGHT", anchorBox, "BOTTOMRIGHT", 0, -18)
                else
                    editModeButton:SetPoint("BOTTOMLEFT", frameGroup, "BOTTOMLEFT", 16, 16)
                end
                editModeButton:Show()
            else
                editModeButton:Hide()
            end
        end
     end
    local function IsTabKey(k)
        return k == "bars" or k == "classpower" or k == "fonts" or k == "auras" or k == "castbar" or k == "misc" or k == "profiles"
    end
    local function SetCurrentKey(newKey)
        if IsTabKey(newKey) then
            currentTabKey = newKey
        else
            currentKey = newKey
            currentTabKey = "frames"
        end
        MSUF_CurrentOptionsKey = currentKey
        MSUF_CurrentOptionsTabKey = currentTabKey
        for k, b in pairs(buttons) do
            if b and b.Enable then b:Enable() end
        end
        -- Only one navigation button should be in the 'selected' (disabled) state:
        -- * Frames tab: the selected unit button (Player/Target/ToT/Focus/Boss/Pet)
        -- * Other tabs: the selected tab button (Bars/Fonts/Auras/Castbar/Misc/Profiles)
        -- This prevents the visual bug where two buttons look selected when switching rows quickly.
        if currentTabKey == "frames" then
            if buttons[currentKey] and buttons[currentKey].Disable then buttons[currentKey]:Disable() end
        else
            if buttons[currentTabKey] and buttons[currentTabKey].Disable then buttons[currentTabKey]:Disable() end
        end
        UpdateGroupVisibility()
     end
    function MSUF_GetTabButtonHelpers(requestedPanel)
        if requestedPanel == panel then  return buttons, SetCurrentKey end
     end
    if ns and ns.MSUF_InitSearchModule then
        ns.MSUF_InitSearchModule({
            panel             = panel,
            searchBox         = searchBox,
            frameGroup        = frameGroup,
            fontGroup         = fontGroup,
            auraGroup         = auraGroup,
            castbarGroup      = castbarGroup,
            castbarEnemyGroup = castbarEnemyGroup,
            castbarTargetGroup= castbarTargetGroup,
            castbarFocusGroup = castbarFocusGroup,
            castbarBossGroup  = castbarBossGroup,
            castbarPlayerGroup= castbarPlayerGroup,
            barGroup          = barGroupHost,
            miscGroup         = miscGroup,
            profileGroup      = profileGroup,
            buttons           = buttons,
            getCurrentKey     = function()  return (currentTabKey == "frames" and currentKey) or currentTabKey end,
            setCurrentKey     = SetCurrentKey,
        })
    end
    local function MSUF_SkinMidnightTabButton(btn)
        if not btn then  return end
        local GOLD_R, GOLD_G, GOLD_B = 1.00, 0.82, 0.00
        local function EnsureActiveLine(self)
            if self.__msufActiveLine then  return end
            local line = self:CreateTexture(nil, "OVERLAY")
            line:SetTexture("Interface/Buttons/WHITE8x8")
            line:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.95)
            line:SetHeight(2)
            line:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 2, 1)
            line:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -2, 1)
            line:Hide()
            self.__msufActiveLine = line
         end
        local function SetRegionColor(self, r, g, b, a)
            local name = self.GetName and self:GetName()
            local left  = self.Left  or (name and _G[name .. "Left"])   or nil
            local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
            local right = self.Right or (name and _G[name .. "Right"])  or nil
            if left then left:SetTexture("Interface\\Buttons\\WHITE8x8"); left:SetVertexColor(r, g, b, a or 1) end
            if mid  then mid:SetTexture("Interface\\Buttons\\WHITE8x8");  mid:SetVertexColor(r, g, b, a or 1) end
            if right then right:SetTexture("Interface\\Buttons\\WHITE8x8"); right:SetVertexColor(r, g, b, a or 1) end
            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then
                nt:SetTexture("Interface\\Buttons\\WHITE8x8")
                nt:SetVertexColor(r, g, b, a or 1)
                nt:SetTexCoord(0, 1, 0, 1)
            end
         end
        local function ApplyState(self, selected)
            -- Always keep the background neutral black; highlight selection via gold text + a thin gold underline.
            SetRegionColor(self, 0.02, 0.02, 0.02, 0.92)
            EnsureActiveLine(self)
            local fs = self.GetFontString and self:GetFontString() or nil
            if fs then
                if selected then
                    fs:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
                else
                    fs:SetTextColor(0.92, 0.92, 0.92)
                end
                fs:SetShadowColor(0, 0, 0, 0.65)
                fs:SetShadowOffset(1, -1)
            end
            if self.__msufActiveLine then
                if selected then self.__msufActiveLine:Show() else self.__msufActiveLine:Hide() end
            end
         end
        -- Avoid SetHighlightTexture / SetPushedTexture calls (can error on some builds). Instead, neutralize existing regions.
        do
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
            if hl then
                hl:SetTexture("Interface/Buttons/WHITE8x8")
                hl:SetVertexColor(1, 1, 1, 0)
                hl:SetAllPoints(btn)
            end
            local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
            if pt then
                pt:SetTexture("Interface/Buttons/WHITE8x8")
                pt:SetVertexColor(1, 1, 1, 0)
                pt:SetAllPoints(btn)
            end
        end
        if not btn.__msufMidnightTabSkinned then
            btn.__msufMidnightTabSkinned = true
            hooksecurefunc(btn, "Disable", function(self)  ApplyState(self, true)  end)
            hooksecurefunc(btn, "Enable", function(self)  ApplyState(self, false)  end)
            btn:HookScript("OnShow", function(self)  ApplyState(self, self.IsEnabled and (not self:IsEnabled()) or false)  end)
        end
        ApplyState(btn, btn.IsEnabled and (not btn:IsEnabled()) or false)
     end
    -- Flat midnight-style button for small action buttons (Focus Kick / Castbar Edit Mode, etc.)
    -- Keeps the dark look without the sticky blue highlight.
    local function MSUF_SkinMidnightActionButton(btn, opts)
        if not btn then  return end
        -- Prevent the SlashMenu mirror skin from overriding Options action buttons.
        btn._msufNoSlashSkin = true
        btn.__msufMidnightActionSkinned = true

        if type(_G.MSUF_ForceShowUIPanelButtonPieces) == "function" then
            pcall(_G.MSUF_ForceShowUIPanelButtonPieces, btn)
        end

        opts = opts or {}
        local r, g, b, a = (opts.r or 0.06), (opts.g or 0.06), (opts.b or 0.06), (opts.a or 0.92)

        local function SetRegionColor(self, rr, gg, bb, aa)
            local name = self.GetName and self:GetName()
            local left  = self.Left  or (name and _G[name .. "Left"]) or nil
            local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
            local right = self.Right or (name and _G[name .. "Right"]) or nil

            local function Paint(t)
                if not t then return end
                if t.SetTexture then t:SetTexture("Interface\\Buttons\\WHITE8x8") end
                if t.SetVertexColor then t:SetVertexColor(rr, gg, bb, aa or 1) end
                if t.SetAlpha then t:SetAlpha(1) end
                if t.Show then t:Show() end
            end

            Paint(left); Paint(mid); Paint(right)

            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then
                if nt.SetTexture then nt:SetTexture("Interface\\Buttons\\WHITE8x8") end
                if nt.SetVertexColor then nt:SetVertexColor(rr, gg, bb, aa or 1) end
                if nt.SetTexCoord then nt:SetTexCoord(0, 1, 0, 1) end
                if nt.SetAlpha then nt:SetAlpha(1) end
                if nt.Show then nt:Show() end
            end
        end

        SetRegionColor(btn, r, g, b, a)

        -- Pushed texture: tiny tint so the click feedback is visible.
        local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
        if pt then
            pt:SetTexture("Interface/Buttons/WHITE8x8")
            pt:SetVertexColor(1, 1, 1, 0.06)
            pt:SetTexCoord(0, 1, 0, 1)
            pt:SetAllPoints(btn)
            pt:Show()
        end

        -- Highlight texture: keep it effectively invisible (we handle hover elsewhere).
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
        if hl then
            hl:SetTexture("Interface/Buttons/WHITE8x8")
            hl:SetVertexColor(1, 1, 1, 0)
            hl:SetTexCoord(0, 1, 0, 1)
            hl:SetAllPoints(btn)
            hl:Show()
        end

        local fs = btn.GetFontString and btn:GetFontString() or nil
        if fs and fs.SetTextColor then
            local tr = (opts.textR ~= nil) and opts.textR or 0.92
            local tg = (opts.textG ~= nil) and opts.textG or 0.92
            local tb = (opts.textB ~= nil) and opts.textB or 0.92
            fs:SetTextColor(tr, tg, tb)
            if fs.SetAlpha then fs:SetAlpha(1) end
            if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
            if fs.Show then fs:Show() end
        end

        if btn.SetAlpha then btn:SetAlpha(1) end
     end

    -- Legacy top navigation strip removed.
    -- Navigation is driven exclusively by the Slash/Flash menu.
    -- We keep SetCurrentKey() + MSUF_GetTabButtonHelpers() so the slash menu can switch
    -- the visible option group without requiring any legacy buttons.
    editModeButton = CreateFrame("Button", "MSUF_EditModeButton", panel, "UIPanelButtonTemplate")
    editModeButton:SetSize(160, 32)  -- fairly large
    editModeButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
    editModeButton:SetText(TR("Edit Mode"))
    editHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editHint:SetPoint("LEFT", editModeButton, "RIGHT", 12, 0)
    editHint:SetJustifyH("LEFT")
    -- Quick hint: we now do frame ON/OFF + layout in MSUF Edit Mode (stable + secure).
    editHint:SetText(TR(""))
    editHint:Hide()
    snapCheck = CreateFrame("CheckButton", "MSUF_EditModeSnapCheck", panel, "UICheckButtonTemplate")
    snapCheck:SetPoint("LEFT", editHint, "RIGHT", 16, 0)
    snapText = _G["MSUF_EditModeSnapCheckText"]
    if snapText then snapText:SetText(TR("Snap to grid")) end
    snapCheck.text = snapText
    EnsureDB()
    g = MSUF_DB.general or {}
    snapCheck:SetChecked(g.editModeSnapToGrid ~= false)
    snapCheck:SetScript("OnClick", function(self)
        EnsureDB()
        gg = MSUF_DB.general
        gg.editModeSnapToGrid = self:GetChecked() and true or false
     end)
    snapCheck:Hide()
emFont = editModeButton:GetFontString()
if emFont then emFont:SetFontObject("GameFontNormalLarge") end
    -- Ensure this action button is immune to SlashMenu mirror reskin passes.
    MSUF_SkinMidnightActionButton(editModeButton)
    function MSUF_SyncCastbarEditModeWithUnitEdit()
    if not MSUF_DB or not MSUF_DB.general then  return end
    local g = MSUF_DB.general
    g.castbarPlayerPreviewEnabled = MSUF_UnitEditModeActive and true or false
    local function RefreshAll()
        if MSUF_UpdatePlayerCastbarPreview then MSUF_UpdatePlayerCastbarPreview() end
        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
        if type(MSUF_SetupBossCastbarPreviewEditMode) == "function" then
            MSUF_SetupBossCastbarPreviewEditMode()
        end
     end
    RefreshAll()
    if g.castbarPlayerPreviewEnabled and C_Timer and C_Timer.After then C_Timer.After(0, RefreshAll) end
 end
function MSUF_SyncBossUnitframePreviewWithUnitEdit()
    -- Boss preview/test frames:
    -- - Active only during MSUF Edit Mode
    -- - Requires Boss unitframe enabled
    -- - Optional user toggle via MSUF_EditModeBossPreviewCheck (if present)
    if type(EnsureDB) == "function" then EnsureDB() end
    local bossConf = (type(MSUF_DB) == "table" and MSUF_DB.boss) or nil
    local bossEnabled = (not bossConf) or (bossConf.enabled ~= false)
    local editActive = (MSUF_UnitEditModeActive and true or false)
    -- Read preview toggle (checkbox created in MSUF_EditMode.lua).
    -- If it does not exist (older layouts), fall back to a DB flag (default true).
    local bossPreviewEnabled = true
    local chk = _G["MSUF_EditModeBossPreviewCheck"]
    if chk and chk.GetChecked then
        bossPreviewEnabled = chk:GetChecked() and true or false
        if chk.Show then chk:Show() end
        if chk.Enable then chk:Enable() end
    else
        if type(MSUF_DB) == "table" then
            MSUF_DB.general = MSUF_DB.general or {}
            if MSUF_DB.general.bossPreviewEnabled == nil then MSUF_DB.general.bossPreviewEnabled = true end
            bossPreviewEnabled = MSUF_DB.general.bossPreviewEnabled and true or false
        end
    end
    local active = (editActive and bossEnabled and bossPreviewEnabled) and true or false
    -- Boss Test Mode is the internal switch that force-shows boss frames for editing.
    MSUF_BossTestMode = active
    if InCombatLockdown and InCombatLockdown() then  return end
    -- Refresh secure visibility drivers so a previous "hide" state does not stick.
    if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then MSUF_RefreshAllUnitVisibilityDrivers(editActive) end
    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames["boss" .. i])
        if f then
            -- Update first (may hide if unit doesn't exist), then force-show if active.
            if type(UpdateSimpleUnitFrame) == "function" then UpdateSimpleUnitFrame(f) end
            if active then
                f:Show()
                if f.SetAlpha then f:SetAlpha(1) end
                if f.EnableMouse then f:EnableMouse(true) end
            else
                -- If boss frames are disabled, ALWAYS hide them (even in Edit Mode).
                if not bossEnabled then
                    f:Hide()
                    if f.SetAlpha then f:SetAlpha(0) end
                    if f.EnableMouse then f:EnableMouse(false) end
                else
                    -- Preview disabled or Edit Mode off: show only when a real boss unit exists.
                    local unit = "boss" .. i
                    if UnitExists and not UnitExists(unit) then f:Hide() end
                end
            end
        end
    end
 end
-- Toggle Castbar Edit Mode from the shared bottom-left Edit Mode button (Castbar tab).
-- NOTE: We are NOT deleting Castbar Edit Mode itself; we only remove the extra button inside the Castbar menu.
-- The shared Edit Mode button now drives the full flow: enable MSUF Edit Mode + enable castbar previews + start test casts.
local function MSUF_ToggleCastbarEditModeFromOptions()
    if type(EnsureDB) == "function" then EnsureDB() end
    if not MSUF_DB or not MSUF_DB.general then
         return
    end
    local wantActive = not (MSUF_UnitEditModeActive and true or false)
    -- Start/stop MSUF Edit Mode. We intentionally use a known-good unitKey (player) to avoid unknown-key paths.
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        local keyForDirect = (MSUF_CurrentEditUnitKey and MSUF_CurrentEditUnitKey ~= "") and MSUF_CurrentEditUnitKey or "player"
        _G.MSUF_SetMSUFEditModeDirect(wantActive, keyForDirect)
    else
        MSUF_UnitEditModeActive = wantActive and true or false
        MSUF_CurrentEditUnitKey = wantActive and (MSUF_CurrentEditUnitKey or "player") or nil
        if wantActive and type(MSUF_BeginEditModeTransaction) == "function" then MSUF_BeginEditModeTransaction() end
    end
    -- Ensure castbar previews follow Edit Mode.
    if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then MSUF_SyncCastbarEditModeWithUnitEdit() end
    -- Start/stop dummy casts on previews so changes are visible.
    local fns = {
        "MSUF_SetPlayerCastbarTestMode",
        "MSUF_SetTargetCastbarTestMode",
        "MSUF_SetFocusCastbarTestMode",
        "MSUF_SetBossCastbarTestMode",
    }
    for _, fnName in ipairs(fns) do
        local fn = _G[fnName]
        if type(fn) == "function" then pcall(fn, wantActive) end
    end
    -- Close Settings so the user can drag without UI overlap (same behaviour as unit Edit Mode).
    if wantActive then
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
            if HideUIPanel then HideUIPanel(SettingsPanel) else SettingsPanel:Hide() end
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame.IsShown and InterfaceOptionsFrame:IsShown() then
            if HideUIPanel then HideUIPanel(InterfaceOptionsFrame) else InterfaceOptionsFrame:Hide() end
        elseif VideoOptionsFrame and VideoOptionsFrame.IsShown and VideoOptionsFrame:IsShown() then
            if HideUIPanel then HideUIPanel(VideoOptionsFrame) else VideoOptionsFrame:Hide() end
        elseif AudioOptionsFrame and AudioOptionsFrame.IsShown and AudioOptionsFrame:IsShown() then
            if HideUIPanel then HideUIPanel(AudioOptionsFrame) else AudioOptionsFrame:Hide() end
        end
    end
 end
editModeButton:SetScript("OnClick", function()
    -- Castbar tab uses the shared Edit Mode button to toggle Castbar Edit Mode (castbar previews),
    -- instead of having a separate Castbar Edit Mode button inside the Castbar menu.
    if currentTabKey == "castbar" then
        MSUF_ToggleCastbarEditModeFromOptions()
         return
    end
    movableKeys = {
        player       = true,
        target       = true,
        targettarget = true,
        focus        = true,
        pet          = true,
        boss         = true,
    }
    if not movableKeys[currentKey] then
        print("|cffffd700MSUF:|r Edit Mode only works for unit tabs (Player/Target/ToT/Focus/Pet/Boss). Please select one of those tabs.")
         return
    end
    local wantActive = not (MSUF_UnitEditModeActive and true or false)
    -- Always start/stop MSUF Edit Mode directly (even when Blizzard linking is OFF)
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(wantActive, currentKey)
    else
        -- fallback (shouldn't happen): old toggle behavior
        MSUF_UnitEditModeActive = wantActive
        MSUF_CurrentEditUnitKey = wantActive and currentKey or nil
        if wantActive and type(MSUF_BeginEditModeTransaction) == "function" then MSUF_BeginEditModeTransaction() end
        if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
            MSUF_SyncCastbarEditModeWithUnitEdit()
        end
        if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then MSUF_SyncBossUnitframePreviewWithUnitEdit() end
    end
    -- IMPORTANT: Do NOT try to programmatically toggle Blizzard Edit Mode from addon UI.
    -- In Midnight/Beta this can taint the EditMode exit path (ClearTarget) and break Edit Mode until /reload.
    -- We only sync MSUF <- Blizzard via MSUF_HookBlizzardEditMode (Blizzard controls itself).
    label = GetLabelForKey(currentKey) or currentKey
    if MSUF_UnitEditModeActive then
        if SettingsPanel and SettingsPanel:IsShown() then
            if HideUIPanel then
                HideUIPanel(SettingsPanel)
            else
                SettingsPanel:Hide()
            end
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(InterfaceOptionsFrame)
            else
                InterfaceOptionsFrame:Hide()
            end
        elseif VideoOptionsFrame and VideoOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(VideoOptionsFrame)
            else
                VideoOptionsFrame:Hide()
            end
        elseif AudioOptionsFrame and AudioOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(AudioOptionsFrame)
            else
                AudioOptionsFrame:Hide()
            end
        end
                        print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cff00ff00ON|r  drag the " .. label .. " frame with the left mouse button or use the arrow buttons.")
        else
            print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cffff0000OFF|r.")
        end
   if MSUF_UpdateEditModeVisuals then
            MSUF_UpdateEditModeVisuals()
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
        end
     end)
    local function MSUF_StyleSlider(slider)
        if not slider or slider.MSUFStyled then  return end
        slider.MSUFStyled = true
        slider:SetHeight(14)
        track = slider:CreateTexture(nil, "BACKGROUND")
        slider.MSUFTrack = track
        track:SetColorTexture(0.06, 0.06, 0.06, 1)
        track:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -3)
        track:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 3)
        thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            thumb:SetSize(10, 18)
        end
        slider:HookScript("OnEnter", function(self)
            if self.MSUFTrack then self.MSUFTrack:SetColorTexture(0.20, 0.20, 0.20, 1) end
         end)
        slider:HookScript("OnLeave", function(self)
            if self.MSUFTrack then self.MSUFTrack:SetColorTexture(0.06, 0.06, 0.06, 1) end
         end)
     end
local function MSUF_StyleSmallButton(button, isPlus)
    if not button or button.MSUFStyled then  return end
    button.MSUFStyled = true
    button:SetSize(20, 20)
    normal = button:CreateTexture(nil, "BACKGROUND")
    normal:SetAllPoints()
    normal:SetTexture(MSUF_TEX_WHITE8)
    normal:SetVertexColor(0, 0, 0, 0.9) -- fast schwarz
    button:SetNormalTexture(normal)
    pushed = button:CreateTexture(nil, "BACKGROUND")
    pushed:SetAllPoints()
    pushed:SetTexture(MSUF_TEX_WHITE8)
    pushed:SetVertexColor(0.7, 0.55, 0.15, 0.95) -- dunkles Gold beim Klick
    button:SetPushedTexture(pushed)
    highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(MSUF_TEX_WHITE8)
    highlight:SetVertexColor(1, 0.9, 0.4, 0.25) -- goldener Hover
    button:SetHighlightTexture(highlight)
    border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetAllPoints()
    button._msufBorder = border
border:SetBackdrop({
    edgeFile = MSUF_TEX_WHITE8,
    edgeSize = 1,
})
    border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetTextColor(1, 0.9, 0.4) -- Gold
    fs:SetText(isPlus and "+" or "-")
    button.text = fs
 end
-- Gradient direction selector (D-pad style)
-- Multi-direction: active arrows are gold; you can combine multiple directions.
-- Stored in MSUF_DB.general.gradientDirLeft/Right/Up/Down (booleans).
-- Legacy: MSUF_DB.general.gradientDirection ("RIGHT"/"LEFT"/"UP"/"DOWN") is auto-migrated.
local function MSUF_CreateGradientDirectionPad(parent)
    local pad = CreateFrame("Frame", "MSUF_GradientDirectionPad", parent, "BackdropTemplate")
    pad:SetSize(82, 66)
    pad:SetBackdrop({
        bgFile = MSUF_TEX_WHITE8,
        edgeFile = MSUF_TEX_WHITE8,
        edgeSize = 1,
    })
    pad:SetBackdropColor(0, 0, 0, 0.25)
    pad:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    pad.buttons = {}
    local function AnyDirOn(g)
        return (g.gradientDirLeft == true) or (g.gradientDirRight == true) or (g.gradientDirUp == true) or (g.gradientDirDown == true)
    end
    local function MigrateLegacyIfNeeded(g)
        -- If none of the new flags exist yet, migrate from the old single-direction key.
        local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
        if hasNew then  return end
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
    local function MakeDirButton(dirKey, glyph, dbKey)
        local b = CreateFrame("Button", nil, pad)
        MSUF_StyleSmallButton(b, true)
        -- Slightly larger for clarity
        b:SetSize(22, 22)
        if b.text then
            b.text:SetText(glyph)
            -- Default state; SyncFromDB() will apply per-button active/inactive visuals.
            b.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            b.text:SetTextColor(0.35, 0.35, 0.35, 1)
        end
        -- Subtle (non-gold) background highlight for active state (arrow is the main indicator).
        local sel = b:CreateTexture(nil, "ARTWORK")
        sel:SetAllPoints()
        sel:SetTexture(MSUF_TEX_WHITE8)
        sel:SetVertexColor(1, 1, 1, 0.12)
        sel:Hide()
        b._msufSel = sel
        -- Extra clarity: soft neutral glow behind the active arrow (not gold).
        local glow = b:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("CENTER")
        glow:SetSize(18, 18)
        glow:SetTexture(MSUF_TEX_WHITE8)
        glow:SetVertexColor(1, 1, 1, 0.10)
        glow:Hide()
        b._msufGlow = glow
        b._msufDBKey = dbKey
        b._msufDirKey = dirKey
        b:SetScript("OnClick", function()
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            MigrateLegacyIfNeeded(g)
            -- Toggle this direction
            g[dbKey] = not (g[dbKey] == true)
            -- Ensure at least one direction remains active
            if not AnyDirOn(g) then g[dbKey] = true end
            -- Keep legacy key around as "last touched" for older builds/tools.
            g.gradientDirection = dirKey
            if pad.SyncFromDB then pad:SyncFromDB() end
            -- Apply gradient changes live (HP + Power, throttle-safe).
            if type(MSUF_BarsApplyGradient) == "function" then
                MSUF_BarsApplyGradient()
            elseif type(_G.MSUF_BarsApplyGradient) == "function" then
                _G.MSUF_BarsApplyGradient()
            elseif type(ApplyAllSettings) == "function" then
                ApplyAllSettings()
            end
         end)
        pad.buttons[dirKey] = b
         return b
    end
    local bUp    = MakeDirButton("UP",    "^", "gradientDirUp")
    local bDown  = MakeDirButton("DOWN",  "v", "gradientDirDown")
    local bLeft  = MakeDirButton("LEFT",  "<", "gradientDirLeft")
    local bRight = MakeDirButton("RIGHT", ">", "gradientDirRight")
    -- Layout (D-pad)
    bUp:SetPoint("CENTER", pad, "CENTER", 0, 20)
    bDown:SetPoint("CENTER", pad, "CENTER", 0, -20)
    bLeft:SetPoint("CENTER", pad, "CENTER", -20, 0)
    bRight:SetPoint("CENTER", pad, "CENTER", 20, 0)
    -- Center dot (cosmetic)
    local dot = pad:CreateTexture(nil, "ARTWORK")
    dot:SetSize(9, 9)
    dot:SetPoint("CENTER")
    dot:SetTexture(MSUF_TEX_WHITE8)
    dot:SetVertexColor(0.7, 0.7, 0.7, 0.25)
    pad._msufDot = dot
    function pad:SetEnabledVisual(enabled)
        for _, btn in pairs(self.buttons) do
            if enabled then
                btn:Enable()
                btn:SetAlpha(1)
            else
                btn:Disable()
                btn:SetAlpha(0.35)
            end
        end
        self:SetAlpha(enabled and 1 or 0.55)
     end
    function pad:SyncFromDB()
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        MigrateLegacyIfNeeded(g)
        -- Normalize nils
        if g.gradientDirLeft == nil then g.gradientDirLeft = false end
        if g.gradientDirRight == nil then g.gradientDirRight = false end
        if g.gradientDirUp == nil then g.gradientDirUp = false end
        if g.gradientDirDown == nil then g.gradientDirDown = false end
        if not AnyDirOn(g) then
            g.gradientDirRight = true
            g.gradientDirection = "RIGHT"
        end
        local activeMap = {
            UP = (g.gradientDirUp == true),
            DOWN = (g.gradientDirDown == true),
            LEFT = (g.gradientDirLeft == true),
            RIGHT = (g.gradientDirRight == true),
        }
        for k, btn in pairs(self.buttons) do
            local isOn = (activeMap[k] == true)
            if btn._msufSel then btn._msufSel:SetShown(isOn) end
            if btn._msufGlow then
                btn._msufGlow:SetShown(isOn)
            end
            -- Keep only the arrow gold, but make the state unmistakable:
            -- darker inactive arrows + slightly brighter neutral border for active ones.
            if btn._msufBorder then
                if isOn then
                    btn._msufBorder:SetBackdropBorderColor(0.70, 0.70, 0.70, 1)
                else
                    btn._msufBorder:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
                end
            end
            if btn.text then
                if isOn then
                    btn.text:SetTextColor(1, 0.9, 0.4, 1) -- gold
                    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
                else
                    btn.text:SetTextColor(0.35, 0.35, 0.35, 1)
                    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                end
            end
        end
        -- Enable the D-pad when *either* gradient is enabled.
        -- Bugfix: previously this was gated only by HP gradient (enableGradient), which made
        -- the power-gradient controller unusable when HP gradient was turned off.
        local enabled = ((g.enableGradient ~= false) or (g.enablePowerGradient ~= false))
        self:SetEnabledVisual(enabled)
     end
    pad:SyncFromDB()
     return pad
end
CreateLabeledSlider = function(name, label, parent, minVal, maxVal, step, x, y)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    local extraY = 0
    if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then extraY = -40 end
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + extraY)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    -- Mark user interaction so we only recommend reload for real user changes (not DB sync).
    slider:HookScript("OnMouseDown", function(self)
        self._msufUserChange = true
     end)
    slider.minVal = minVal
    slider.maxVal = maxVal
    slider.step   = step
    local low  = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]
    if low  then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(TR(label or ""))     end
    local eb = CreateFrame("EditBox", name .. "Input", parent, "InputBoxTemplate")
    eb:SetSize(60, 18)
    eb:SetAutoFocus(false)
    eb:SetPoint("TOP", slider, "BOTTOM", 0, -6) -- more spacing
    eb:SetJustifyH("CENTER")
    slider.editBox = eb
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(1, 1, 1, 1)
    slider.editBox = eb
    local function ApplyEditBoxValue()
        local txt = eb:GetText()
        local val = tonumber(txt)
        if not val then
            local cur = slider:GetValue() or minVal
            if slider.step and slider.step >= 1 then cur = math.floor(cur + 0.5) end
            eb:SetText(tostring(cur))
             return
        end
        if val < slider.minVal then val = slider.minVal end
        if val > slider.maxVal then val = slider.maxVal end
        slider._msufUserChange = true
        slider:SetValue(val)
     end
    eb:SetScript("OnEnterPressed", function(self)
        ApplyEditBoxValue()
        self:ClearFocus()
     end)
    eb:SetScript("OnEditFocusLost", function(self)
        ApplyEditBoxValue()
     end)
    eb:SetScript("OnEscapePressed", function(self)
        local cur = slider:GetValue() or minVal
        if slider.step and slider.step >= 1 then cur = math.floor(cur + 0.5) end
        self:SetText(tostring(cur))
        self:ClearFocus()
     end)
    local minus = CreateFrame("Button", name .. "Minus", parent)
    minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
    slider.minusButton = minus
    minus:SetScript("OnClick", function()
        local cur = slider:GetValue()
        local st  = slider.step or 1
        local nv  = cur - st
        if nv < slider.minVal then nv = slider.minVal end
        slider._msufUserChange = true
        slider:SetValue(nv)
     end)
    MSUF_StyleSmallButton(minus, false) -- Midnight minus
    local plus = CreateFrame("Button", name .. "Plus", parent)
    plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    slider.plusButton = plus
    plus:SetScript("OnClick", function()
        local cur = slider:GetValue()
        local st  = slider.step or 1
        local nv  = cur + st
        if nv > slider.maxVal then nv = slider.maxVal end
        slider._msufUserChange = true
        slider:SetValue(nv)
     end)
    MSUF_StyleSmallButton(plus, true) -- Midnight plus
    slider:SetScript("OnValueChanged", function(self, value)
        if self.MSUF_SkipCallback then  return end
        local step = self.step or 1
        local formatted
        if step >= 1 then
            value     = math.floor(value + 0.5)
            formatted = tostring(value)
        else
            local precision  = 2
            local multiplier = 10 ^ precision
            value     = math.floor(value * multiplier + 0.5) / multiplier
            formatted = string.format("%." .. precision .. "f", value)
        end
        if self.editBox and not self.editBox:HasFocus() then
            local cur = self.editBox:GetText()
            if cur ~= formatted then self.editBox:SetText(formatted) end
        end
        if self.onValueChanged then self.onValueChanged(self, value) end
        if self._msufUserChange then
            self._msufUserChange = nil
            MSUF_ScheduleReloadRecommend()
        end
     end)
    MSUF_StyleSlider(slider)
     
    -- Search helper: register slider label for menu search (no overhead outside menu).
    if type(_G.MSUF_Search_RegisterSlider) == "function" and type(name) == "string" and type(label) == "string" then
        _G.MSUF_Search_RegisterSlider(name, label)
    end

return slider
end
-- Show/Hide a labeled slider AND its attached editbox/plus/minus + template texts.
-- Needed because our sliders' editboxes/buttons are parented to the container, not the slider itself.
function MSUF_SetSliderVisibility(slider, show)
    if not slider then  return end
    if show then slider:Show() else slider:Hide() end
    if slider.editBox then slider.editBox:SetShown(show) end
    if slider.minusButton then slider.minusButton:SetShown(show) end
    if slider.plusButton then slider.plusButton:SetShown(show) end
    local n = slider.GetName and slider:GetName()
    if n then
        local low  = _G[n .. "Low"]
        local high = _G[n .. "High"]
        local text = _G[n .. "Text"]
        if low  then low:SetShown(show)  end
        if high then high:SetShown(show) end
        if text then text:SetShown(show) end
    end
 end
-- Enable/disable helper for labeled sliders (slider + editbox + +/- buttons + template label texts)
local function MSUF_SetLabeledSliderEnabled(slider, enabled)
    if not slider then  return end
    local name = (slider.GetName and slider:GetName())
    local label = (name and _G and _G[name .. "Text"]) or slider.label or slider.Text or slider.text
    local low  = (name and _G and _G[name .. "Low"])  or nil
    local high = (name and _G and _G[name .. "High"]) or nil
    local function SetBtnEnabled(btn, en)
        if not btn then  return end
        if btn.SetEnabled then btn:SetEnabled(en) end
        if en then
            if btn.Enable then btn:Enable() end
        else
            if btn.Disable then btn:Disable() end
        end
     end
    local function SetFSColor(fs, r, g, b)
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
     end
    if enabled then
        if slider.Enable then slider:Enable() end
        if slider.editBox and slider.editBox.Enable then slider.editBox:Enable() end
        SetBtnEnabled(slider.minusButton, true)
        SetBtnEnabled(slider.plusButton, true)
        SetFSColor(label, 1, 1, 1)
        SetFSColor(low, 0.7, 0.7, 0.7)
        SetFSColor(high, 0.7, 0.7, 0.7)
        if slider.editBox and slider.editBox.SetTextColor then slider.editBox:SetTextColor(1, 1, 1) end
        slider:SetAlpha(1)
    else
        if slider.Disable then slider:Disable() end
        if slider.editBox and slider.editBox.Disable then slider.editBox:Disable() end
        SetBtnEnabled(slider.minusButton, false)
        SetBtnEnabled(slider.plusButton, false)
        SetFSColor(label, 0.35, 0.35, 0.35)
        SetFSColor(low, 0.35, 0.35, 0.35)
        SetFSColor(high, 0.35, 0.35, 0.35)
        if slider.editBox and slider.editBox.SetTextColor then slider.editBox:SetTextColor(0.55, 0.55, 0.55) end
        slider:SetAlpha(0.55)
    end
 end
if ns and not ns.MSUF_SetLabeledSliderEnabled then ns.MSUF_SetLabeledSliderEnabled = MSUF_SetLabeledSliderEnabled end
-- Set a labeled slider's value WITHOUT triggering side-effects, while still updating its numeric editbox.
-- Needed because CreateLabeledSlider only syncs the editbox via OnValueChanged, which we often skip during panel sync.
MSUF_SetLabeledSliderValue = function(slider, value)
    if not slider then  return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = nil
    if slider.editBox and slider.editBox.SetText and (not slider.editBox:HasFocus()) then
        local cur = slider:GetValue()
        local step = slider.step or 1
        local formatted
        if step >= 1 then
            cur = math.floor((tonumber(cur) or 0) + 0.5)
            formatted = tostring(cur)
        else
            formatted = string.format("%.2f", tonumber(cur) or 0)
        end
        slider.editBox:SetText(formatted)
    end
 end
-- Enable/disable helper for UIDropDownMenu (with separate label fontstring)
local function MSUF_SetDropDownEnabled(dropdown, labelFS, enabled)
    if not dropdown then  return end
    local name = (dropdown.GetName and dropdown:GetName())
    local ddText = (name and _G and _G[name .. "Text"]) or dropdown.Text
    local function SetFSColor(fs, r, g, b)
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
     end
    if enabled then
        if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(dropdown) end
        dropdown:SetAlpha(1)
        SetFSColor(labelFS, 1, 1, 1)
        SetFSColor(ddText, 1, 1, 1)
    else
        if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(dropdown) end
        dropdown:SetAlpha(0.55)
        SetFSColor(labelFS, 0.35, 0.35, 0.35)
        SetFSColor(ddText, 0.55, 0.55, 0.55)
    end
 end
-- Enable/disable helper for CheckButtons (with optional label fontstring)
local function MSUF_SetCheckboxEnabled(cb, enabled)
    if not cb then  return end
    local label = cb.Text or cb.text
    local function SetFSColor(fs, r, g, b)
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
     end
    if enabled then
        if cb.SetEnabled then cb:SetEnabled(true) end
        cb:SetAlpha(1)
        SetFSColor(label, 1, 1, 1)
    else
        if cb.SetEnabled then cb:SetEnabled(false) end
        cb:SetAlpha(0.55)
        SetFSColor(label, 0.55, 0.55, 0.55)
    end
 end
if _G and not _G.MSUF_Options_Apply then
    local function Call(fn, ...)  if type(fn) == "function" then return fn(...) end  end
    local function CastbarVisuals()  Call(_G.MSUF_EnsureCastbars); Call(_G.MSUF_UpdateCastbarVisuals)  end
    local A = {
        castbars = CastbarVisuals, castbarVisuals = CastbarVisuals,
        castbarFillDirection = function()  Call(_G.MSUF_UpdateCastbarFillDirection)  end,
        castbarTicks = function()  if type(_G.MSUF_UpdateCastbarChannelTicks) == "function" then _G.MSUF_UpdateCastbarChannelTicks() else CastbarVisuals() end  end,
        castbarGlow = function()  if type(_G.MSUF_UpdateCastbarGlowEffect) == "function" then _G.MSUF_UpdateCastbarGlowEffect() else CastbarVisuals() end  end,
        castbarLatency = function()  if type(_G.MSUF_UpdateCastbarLatencyIndicator) == "function" then _G.MSUF_UpdateCastbarLatencyIndicator() else CastbarVisuals() end  end,
    }
    A.all = function()  if type(ApplyAllSettings) == "function" then ApplyAllSettings() elseif type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then _G.MSUF_ApplyAllSettings_Immediate() end  end
    function _G.MSUF_Options_Apply(kind, ...)  return Call(A[kind] or A.all, ...) end
    if ns and not ns.MSUF_Options_Apply then ns.MSUF_Options_Apply = _G.MSUF_Options_Apply end
end
-- Step 5: unify bool binders (General + table.key paths) to remove duplicated OnClick boilerplate.
-- Behavior-neutral: keeps DB keys and apply/sync callbacks identical.
if _G and not _G.MSUF_Options_BindDBBoolCheck then
-- Nested DB path setter (supports "a.b.c" paths). Kept local to avoid global clutter.
local function _MSUF_DBSetPath(path, value)
    if type(MSUF_DB) ~= "table" or type(path) ~= "string" then  return end
    local t = MSUF_DB
    local parts = {}
    for token in string.gmatch(path, "[^%.]+") do
        parts[#parts + 1] = token
    end
    if #parts == 0 then  return end
    for i = 1, #parts - 1 do
        local k = parts[i]
        if type(t[k]) ~= "table" then t[k] = {} end
        t = t[k]
    end
    t[parts[#parts]] = value
 end
    function _G.MSUF_Options_BindDBBoolCheck(cb, dbPath, applyFn, syncFn, onShow)
        if not cb or type(dbPath) ~= "string" then  return end
        cb:SetScript("OnClick", function(self)
            if type(EnsureDB) == "function" then EnsureDB() end
            if type(MSUF_DB) ~= "table" then  return end
            local v = self:GetChecked() and true or false
                        _MSUF_DBSetPath(dbPath, v)
            -- Force the widget's visual state to match the new value.
            -- Some custom checkbox templates / skins don't auto-toggle reliably.
            if self.SetChecked then self:SetChecked(v) end
            if type(applyFn) == "function" then applyFn(v, self)
            elseif type(applyFn) == "string" and _G and type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply(applyFn, v, self) end
            if type(syncFn)  == "function" then syncFn() end
         end)
        if onShow and cb.HookScript then
            cb:HookScript("OnShow", function()
                if type(syncFn) == "function" then syncFn() end
             end)
        end
     end
end
-- Step 5: backwards-compatible wrapper used by older call sites (writes to MSUF_DB.general.<dbKey>)
if _G and not _G.MSUF_Options_BindGeneralBoolCheck then
    function _G.MSUF_Options_BindGeneralBoolCheck(cb, dbKey, applyFn, syncFn, onShow)
        if not cb or type(dbKey) ~= "string" then  return end
        if _G and _G.MSUF_Options_BindDBBoolCheck then
            return _G.MSUF_Options_BindDBBoolCheck(cb, "general." .. dbKey, applyFn, syncFn, onShow)
        end
     end
end
-- Step 18: unify number sliders (General DB) to reduce per-slider boilerplate.
-- Uses CreateLabeledSlider's `slider.onValueChanged` hook (not SetScript) so it stays compatible.
if _G and not _G.MSUF_Options_BindGeneralNumberSlider then
    local function _MSUF_ClampNum(v, minV, maxV, asInt, def)
        v = tonumber(v)
        if v == nil then v = tonumber(def) end
        if v == nil then v = 0 end
        if asInt then v = math.floor(v + 0.5) end
        if minV ~= nil and v < minV then v = minV end
        if maxV ~= nil and v > maxV then v = maxV end
         return v
    end
    function _G.MSUF_Options_BindGeneralNumberSlider(slider, dbKey, opts)
        if not slider or type(dbKey) ~= "string" then  return end
        opts = opts or {}
        local def  = opts.def
        local minV = opts.min
        local maxV = opts.max
        local asInt = (opts.int == true)
        local applyFn = opts.apply
        local syncFn  = opts.sync
        local function Apply(v, self)
            if type(applyFn) == "function" then
                applyFn(v, self)
            elseif type(applyFn) == "string" and _G and type(_G.MSUF_Options_Apply) == "function" then
                _G.MSUF_Options_Apply(applyFn, v, self)
            end
         end
        slider.onValueChanged = function(self, value)
            if self and self.MSUF_SkipCallback then  return end
            if type(EnsureDB) == "function" then EnsureDB() end
            if type(MSUF_DB) ~= "table" then  return end
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            local v = _MSUF_ClampNum(value, minV, maxV, asInt, def)
            g[dbKey] = v
            -- If clamped, snap slider/editbox back without firing callbacks.
            if type(value) == "number" and v ~= value and type(MSUF_SetLabeledSliderValue) == "function" then
                MSUF_SetLabeledSliderValue(self, v)
            end
            Apply(v, self)
            if type(syncFn) == "function" then syncFn() end
         end
        -- Initial clamp + sync to UI (no apply)
        if type(EnsureDB) == "function" then EnsureDB() end
        if type(MSUF_DB) ~= "table" then  return end
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        local v0 = _MSUF_ClampNum(g[dbKey], minV, maxV, asInt, def)
        g[dbKey] = v0
        if type(MSUF_SetLabeledSliderValue) == "function" then
            MSUF_SetLabeledSliderValue(slider, v0)
        else
            slider.MSUF_SkipCallback = true
            slider:SetValue(v0)
            slider.MSUF_SkipCallback = nil
        end
     end
end
-- Export key UI helpers for split option modules
-- for split option modules (loaded before this file in the TOC).
if ns then
    ns.MSUF_CreateLabeledSlider = CreateLabeledSlider
    ns.MSUF_SetLabeledSliderValue = MSUF_SetLabeledSliderValue
end
--[[
    Split-module exports (very small, very safe)
    True file-splits (Misc/Fonts/)
    MUST NOT depend on Core file-scope locals.
    We therefore export a small, stable helper surface via `ns.*`.
    Idempotent and intentionally behavior-neutral.
]]
local function MSUF_ExportSplitHelpers()
    if not ns then  return end
    -- Core helpers commonly needed by split modules.
    if not ns.MSUF_GetLSM and type(MSUF_GetLSM) == "function" then ns.MSUF_GetLSM = MSUF_GetLSM end
    if not ns.MSUF_EnsureCastbars and type(MSUF_EnsureCastbars) == "function" then ns.MSUF_EnsureCastbars = MSUF_EnsureCastbars end
    if not ns.MSUF_SetDropDownEnabled and type(MSUF_SetDropDownEnabled) == "function" then ns.MSUF_SetDropDownEnabled = MSUF_SetDropDownEnabled end
    if not ns.MSUF_StyleSlider and type(MSUF_StyleSlider) == "function" then ns.MSUF_StyleSlider = MSUF_StyleSlider end
    if not ns.MSUF_SkinMidnightActionButton and type(MSUF_SkinMidnightActionButton) == "function" then ns.MSUF_SkinMidnightActionButton = MSUF_SkinMidnightActionButton end
    if not ns.MSUF_CallUpdateAllFonts and type(MSUF_CallUpdateAllFonts) == "function" then ns.MSUF_CallUpdateAllFonts = MSUF_CallUpdateAllFonts end
    if not ns.MSUF_Options_RequestLayoutAll and type(MSUF_Options_RequestLayoutAll) == "function" then ns.MSUF_Options_RequestLayoutAll = MSUF_Options_RequestLayoutAll end
    if not ns.MSUF_CreateLabeledSlider and type(CreateLabeledSlider) == "function" then ns.MSUF_CreateLabeledSlider = CreateLabeledSlider end
    if not ns.MSUF_SetLabeledSliderValue and type(MSUF_SetLabeledSliderValue) == "function" then ns.MSUF_SetLabeledSliderValue = MSUF_SetLabeledSliderValue end
 end
MSUF_ExportSplitHelpers()
-- ---------------------------------------------------------------------------
-- Step 6: Compatibility layer (keep old function names alive as thin wrappers)
-- Goal: zero regression for older split modules / external integrations.
--  - Keep names on `ns.*` and `_G.*`
--  - Do NOT change behavior; only forward to the new implementations.
-- ---------------------------------------------------------------------------
local function MSUF_InstallCompatWrappers()
    if not _G then  return end
    -- Also offer a non-prefixed alias for legacy call sites.
    if type(_G.CreateLabeledSlider) ~= "function" and type(CreateLabeledSlider) == "function" then
        _G.CreateLabeledSlider = function(...)  return CreateLabeledSlider(...) end
    end
    -- Some older modules probe ns.CreateLabeledSlider instead of ns.MSUF_CreateLabeledSlider.
    if ns and type(ns.CreateLabeledSlider) ~= "function" and type(ns.MSUF_CreateLabeledSlider) == "function" then
        ns.CreateLabeledSlider = ns.MSUF_CreateLabeledSlider
    end
    -- Export helpers as globals (only if absent) to avoid collisions with other addons.
    local function ExportFn(name, fn)
        if type(fn) ~= "function" then  return end
        if type(_G[name]) ~= "function" then _G[name] = fn end
     end
    ExportFn("MSUF_GetLSM", (ns and ns.MSUF_GetLSM) or MSUF_GetLSM)
    ExportFn("MSUF_EnsureCastbars", (ns and ns.MSUF_EnsureCastbars) or MSUF_EnsureCastbars)
    ExportFn("MSUF_SetDropDownEnabled", (ns and ns.MSUF_SetDropDownEnabled) or MSUF_SetDropDownEnabled)
    ExportFn("MSUF_StyleSlider", (ns and ns.MSUF_StyleSlider) or MSUF_StyleSlider)
    ExportFn("MSUF_SkinMidnightActionButton", (ns and ns.MSUF_SkinMidnightActionButton) or MSUF_SkinMidnightActionButton)
    ExportFn("MSUF_StyleSmallButton", MSUF_StyleSmallButton)
    ExportFn("MSUF_Options_RequestLayoutAll", (ns and ns.MSUF_Options_RequestLayoutAll) or MSUF_Options_RequestLayoutAll)
    ExportFn("MSUF_CallUpdateAllFonts", (ns and ns.MSUF_CallUpdateAllFonts) or MSUF_CallUpdateAllFonts)
    ExportFn("MSUF_KillMenuPreviewBar", MSUF_KillMenuPreviewBar)
    -- Keep the known-good bar-texture exports if present (v101 baseline).
    -- We don't overwrite them here; Step 5 and earlier already installed them.
 end
MSUF_InstallCompatWrappers()
-- Compact +/- stepper with an input box (used for text offse with an input box (used for text offsets).
local MSUF_AxisStepperCounter = 0
function CreateAxisStepper(name, shortLabel, parent, x, y, minVal, maxVal, step)
    if not name then
        MSUF_AxisStepperCounter = (MSUF_AxisStepperCounter or 0) + 1
        name = "MSUF_AxisStepper" .. MSUF_AxisStepperCounter
    end
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(140, 32)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f.minVal = minVal or -999
    f.maxVal = maxVal or  999
    f.step   = step   or  1
    f.value  = 0
    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    lbl:SetText(shortLabel or "")
    f.label = lbl
    local eb = CreateFrame("EditBox", name .. "Input", f, "InputBoxTemplate")
    eb:SetSize(60, 18)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -14)
    -- Force visible numbers (Midnight UI sometimes ends up with no font object on unnamed EditBoxes).
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(1, 1, 1, 1)
    f.editBox = eb
    local minus = CreateFrame("Button", name .. "Minus", f)
    minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
    MSUF_StyleSmallButton(minus, false)
    f.minusButton = minus
    local plus = CreateFrame("Button", name .. "Plus", f)
    plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    MSUF_StyleSmallButton(plus, true)
    f.plusButton = plus
    local function Clamp(v)
        v = tonumber(v) or 0
        if v < f.minVal then v = f.minVal end
        if v > f.maxVal then v = f.maxVal end
        if f.step and f.step >= 1 then v = math.floor(v + 0.5) end
         return v
    end
    function f:SetValue(v, fromUser)
        v = Clamp(v)
        f.value = v
        if f.editBox and not f.editBox:HasFocus() then
            -- Always show 0 properly.
            f.editBox:SetText(tostring(v))
        end
        if fromUser and f.onValueChanged then f.onValueChanged(f, v) end
     end
    function f:GetValue()
        return f.value or 0
    end
    local function ApplyEdit()
        local v = Clamp(eb:GetText())
        f:SetValue(v, true)
     end
    eb:SetScript("OnEnterPressed", function(self)
        ApplyEdit()
        self:ClearFocus()
     end)
    eb:SetScript("OnEditFocusLost", function()
        ApplyEdit()
     end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(f.value or 0))
        self:ClearFocus()
     end)
    minus:SetScript("OnClick", function()
        f:SetValue((f.value or 0) - (f.step or 1), true)
     end)
    plus:SetScript("OnClick", function()
        f:SetValue((f.value or 0) + (f.step or 1), true)
     end)
    -- init
    f:SetValue(0, false)
    f:SetScript("OnShow", function()
        if f.editBox and not f.editBox:HasFocus() then f.editBox:SetText(tostring(f.value or 0)) end
     end)
     return f
end
    -- Style functions now provided by Toolkit (MSUF_Options_Toolkit.lua)
    local MSUF_StyleToggleText = _G.MSUF_StyleToggleText or function() end
    local MSUF_StyleCheckmark  = _G.MSUF_StyleCheckmark or function() end
    local function MSUF_StyleAllToggles(root)
        if not root or not root.GetChildren then return end
        for _, c in ipairs({ root:GetChildren() }) do
            if c and c.GetObjectType and c:GetObjectType() == "CheckButton" then
                MSUF_StyleToggleText(c); MSUF_StyleCheckmark(c)
            end
            if c and c.GetChildren then MSUF_StyleAllToggles(c) end
        end
    end
    local function CreateLabeledCheckButton(name, label, parent, x, y, maxTextWidth)
        local cb = CreateFrame('CheckButton', name, parent, 'UICheckButtonTemplate')
        local extraY = 0
        if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then extraY = -40 end
        cb:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y + extraY)
        cb.text = _G[name .. 'Text']
        if cb.text then cb.text:SetText(TR(label or "")) end
        MSUF_StyleToggleText(cb)
        MSUF_StyleCheckmark(cb)
        if maxTextWidth and _G.MSUF_ClampCheckboxText then
            _G.MSUF_ClampCheckboxText(cb, maxTextWidth)
        end
         return cb
    end
    -- Player options UI is implemented in Options\MSUF_Options_Player.lua (refactored out of Options Core).
    if ns and ns.MSUF_Options_Player_Build then
        ns.MSUF_Options_Player_Build(panel, frameGroup, {
            texWhite = MSUF_TEX_WHITE8,
            CreateLabeledSlider = CreateLabeledSlider,
            CreateAxisStepper   = CreateAxisStepper,
        })
    -- Store scroll updater on panel so Options_Player layout functions can trigger it.
    panel._msufFramesScrollUpdate = MSUF_FramesMenu_QueueScrollUpdate
    -- Re-anchor boss-only controls into the boxed unitframe UI (so they don't float around)
    -- (removed) old boss portrait reposition block
    if bossSpacingSlider and panel and panel.playerSizeBox then
        bossSpacingSlider:ClearAllPoints()
        bossSpacingSlider:SetPoint("TOPLEFT", panel.playerSizeBox, "BOTTOMLEFT", 12, -32)
    end
    end
    -- Profiles tab (split to Options/MSUF_Options_Profiles.lua)
    if ns and ns.MSUF_Options_Profiles_Build then
        ns.MSUF_Options_Profiles_Build(panel, profileGroup, {
            MSUF_BuildButtonRowList = MSUF_BuildButtonRowList,
        })
    else
        local warn5 = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn5:SetPoint("TOPLEFT", profileGroup, "TOPLEFT", 16, -140)
        warn5:SetText(TR("MSUF: Profiles module missing (MSUF_Options_Profiles.lua)."))
    end
    -- Fonts tab split (Options/MSUF_Options_Fonts.lua)
    if ns and ns.MSUF_Options_Fonts_Build then
        ns.MSUF_Options_Fonts_Build(panel, fontGroup)
    else
        local warn = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)
        warn:SetText(TR("MSUF: Fonts module missing (MSUF_Options_Fonts.lua)."))
    end
    -- Misc tab split (Options/MSUF_Options_Misc.lua)
    if ns and ns.MSUF_Options_Misc_Build then
        ns.MSUF_Options_Misc_Build(panel, miscGroup)
    else
        local warn2 = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn2:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -140)
        warn2:SetText(TR("MSUF: Misc module missing (MSUF_Options_Misc.lua)."))
    end
    -- Castbar tab (split to Options/MSUF_Options_Castbars.lua)
    if ns and ns.MSUF_Options_Castbar_Build then
        ns.MSUF_Options_Castbar_Build(panel, castbarGroupHost, castbarGroup, castbarEnemyGroup, castbarFocusGroup, castbarPlayerGroup, castbarTargetGroup, castbarBossGroup, {
            CreateLabeledCheckButton    = CreateLabeledCheckButton,
            CreateLabeledSlider         = CreateLabeledSlider,
            MSUF_SetLabeledSliderValue  = MSUF_SetLabeledSliderValue,
            MSUF_SetLabeledSliderEnabled = MSUF_SetLabeledSliderEnabled,
        })
    else
        local warn3 = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn3:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -140)
        warn3:SetText(TR("MSUF: Castbar module missing (MSUF_Options_Castbars.lua)."))
    end
-- Auras tab (legacy menu removed in Patch 6D Step 2)
-- Keep only a shortcut button that opens the dedicated Auras 2.0 Settings category.
do
    local function SetupPanel(panel, titleText)
        if (not panel.SetBackdrop) and BackdropTemplateMixin and Mixin then Mixin(panel, BackdropTemplateMixin) end
        if panel.SetBackdrop then
            panel:SetBackdrop({
                bgFile = whiteTex,
                edgeFile = whiteTex,
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.35)
            panel:SetBackdropBorderColor(1, 1, 1, 0.25)
        end
        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -10)
        title:SetText(titleText or "")
        title:SetTextColor(1, 0.82, 0, 1)
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.18)
        line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)
        line:SetHeight(1)
        panel._msufHeaderTitle = title
        panel._msufHeaderLine = line
     end
    local p = _G["MSUF_AurasMenuRedirectPanel"]
    if not p then
        p = CreateFrame("Frame", "MSUF_AurasMenuRedirectPanel", auraGroup, "BackdropTemplate")
        p:SetSize(520, 150)
        p:SetPoint("TOPLEFT", auraGroup, "TOPLEFT", 16, -110)
        SetupPanel(p, "Auras")
        local note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", p._msufHeaderLine, "BOTTOMLEFT", 0, -10)
        note:SetWidth(p:GetWidth() - 28)
        note:SetJustifyH("LEFT")
        note:SetText(TR("Auras are handled by the dedicated |cffffd200Auras 2.0|r menu.\n\nThis tab is now only a shortcut."))
        local btn = CreateFrame("Button", "MSUF_OpenAuras2FromAurasTabButton", p, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
        btn:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -12)
        btn:SetHeight(24)
        btn:SetText(TR("Open Auras 2.0"))
        local err = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        err:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
        err:SetWidth(p:GetWidth() - 28)
        err:SetJustifyH("LEFT")
        err:SetTextColor(1, 0.25, 0.25, 1)
        err:SetText(TR(""))
        err:Hide()
        btn:SetScript("OnClick", function()
            err:Hide()
            -- Ensure the Auras 2.0 Settings category is registered.
            local parent = _G.MSUF_SettingsCategory or MSUF_SettingsCategory or (ns and ns.MSUF_MainCategory)
            if (not _G.MSUF_AurasCategory) and ns and ns.MSUF_RegisterAurasOptions and parent then ns.MSUF_RegisterAurasOptions(parent) end
            local cat = _G.MSUF_AurasCategory or (ns and ns.MSUF_AurasCategory)
            if cat then
                local id = cat
                if type(cat) == "table" then id = cat.ID end
                id = tonumber(id)
                if id then
                    if Settings and Settings.OpenToCategory then
                        pcall(Settings.OpenToCategory, id)
                         return
                    end
                    if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
                        pcall(C_SettingsUtil.OpenSettingsPanel, id, nil)
                         return
                    end
                end
            end
            err:SetText(TR("Could not open the Auras 2.0 menu.\nPlease make sure MSUF options are registered and try again."))
            err:Show()
         end)
        p._msufNote = note
        p._msufBtn  = btn
        p._msufErr  = err
        _G["MSUF_AurasMenuRedirectPanel"] = p
    else
        p:Show()
        if p.SetAlpha then p:SetAlpha(1) end
    end
end
    -- Bars tab (split to Options/MSUF_Options_Bars.lua)
    if ns and ns.MSUF_Options_Bars_Build then
        ns.MSUF_Options_Bars_Build(panel, barGroup, barGroupHost, {
            CreateLabeledCheckButton             = CreateLabeledCheckButton,
            CreateLabeledSlider                  = CreateLabeledSlider,
            MSUF_SetLabeledSliderValue           = MSUF_SetLabeledSliderValue,
            MSUF_SetLabeledSliderEnabled         = MSUF_SetLabeledSliderEnabled,
            MSUF_SetCheckboxEnabled              = MSUF_SetCheckboxEnabled,
            MSUF_StyleCheckmark                  = MSUF_StyleCheckmark,
            MSUF_StyleToggleText                 = MSUF_StyleToggleText,
            MSUF_Options_RequestLayoutForKey     = MSUF_Options_RequestLayoutForKey,
            MSUF_CreateGradientDirectionPad      = MSUF_CreateGradientDirectionPad,
            MSUF_BarsMenu_QueueScrollUpdate      = MSUF_BarsMenu_QueueScrollUpdate,
            MSUF_UpdatePowerBarBorderSizeFromEdit = MSUF_UpdatePowerBarBorderSizeFromEdit,
            MSUF_UpdatePowerBarHeightFromEdit     = MSUF_UpdatePowerBarHeightFromEdit,
        })
    else
        local warn4 = barGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn4:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -140)
        warn4:SetText(TR("MSUF: Bars module missing (MSUF_Options_Bars.lua)."))
    end
    panel.anchorEdit                 = anchorEdit
	panel.fontDrop      = panel.fontDrop      or fontDrop
	panel.fontColorDrop = panel.fontColorDrop or fontColorDrop
	panel.nameFontSizeSlider  = panel.nameFontSizeSlider  or nameFontSizeSlider
	panel.hpFontSizeSlider    = panel.hpFontSizeSlider    or hpFontSizeSlider
	panel.powerFontSizeSlider = panel.powerFontSizeSlider or powerFontSizeSlider
	panel.shortenNameClipSideDrop = panel.shortenNameClipSideDrop or shortenNameClipSideDrop
	panel.highlightEnableCheck = panel.highlightEnableCheck or highlightEnableCheck
	panel.highlightColorDrop   = panel.highlightColorDrop   or highlightColorDrop
	panel.castbarSpellNameFontSizeSlider = panel.castbarSpellNameFontSizeSlider or castbarSpellNameFontSizeSlider
    -- Bars/Castbar panel fields are set by their respective Build functions.
    function panel:LoadFromDB()
        EnsureDB()
        g = MSUF_DB.general or {}
        bars = MSUF_DB.bars    or {}
        -- Core-managed widget refs (NOT in any refactored tab file)
        anchorEdit = self.anchorEdit
        anchorCheck = self.anchorCheck
        fontDrop = self.fontDrop
        fontColorDrop = self.fontColorDrop
        nameFontSizeSlider = self.nameFontSizeSlider
        hpFontSizeSlider = self.hpFontSizeSlider
        powerFontSizeSlider = self.powerFontSizeSlider
        highlightEnableCheck = self.highlightEnableCheck
        highlightColorDrop = self.highlightColorDrop
        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        bossSpacingSlider = self.bossSpacingSlider
        -- Bars-tab widgets are now self-syncing (SyncAll on OnShow) — no sync needed here.
        -- Deferred hook: if slash menu window was created after panel build, hook it now.
        do
            local sw = _G.MSUF_StandaloneOptionsWindow
            if sw and not sw.__MSUF_TestCleanupHooked and type(_G.MSUF_TestCleanup_Deferred) == "function" then
                sw.__MSUF_TestCleanupHooked = true
                sw:HookScript("OnHide", _G.MSUF_TestCleanup_Deferred)
            end
        end
        if anchorEdit then anchorEdit:SetText(g.anchorName or "UIParent") end
        if anchorCheck then
            anchorCheck:SetChecked(g.anchorToCooldown and true or false)
        end
        if fontDrop and g.fontKey then
            local fontChoicesLocal = self.__MSUF_FontChoices
            local rebuild = self.__MSUF_RebuildFontChoices
            if (not fontChoicesLocal or #fontChoicesLocal == 0) and type(rebuild) == "function" then
                rebuild(self)
                fontChoicesLocal = self.__MSUF_FontChoices
            end
            UIDropDownMenu_SetSelectedValue(fontDrop, g.fontKey)
            local label = g.fontKey
            if fontChoicesLocal then
                for _, data in ipairs(fontChoicesLocal) do
                    if data.key == g.fontKey then
                        label = data.label
                        break
                    end
                end
            end
            UIDropDownMenu_SetText(fontDrop, label)
        end
        if nameFontSizeSlider then nameFontSizeSlider:SetValue(g.nameFontSize or g.fontSize or 14) end
        if hpFontSizeSlider then
            hpFontSizeSlider:SetValue(g.hpFontSize or g.fontSize or 14)
        end
        if powerFontSizeSlider then powerFontSizeSlider:SetValue(g.powerFontSize or g.fontSize or 14) end
        if castbarSpellNameFontSizeSlider then
            -- Castbar font size (0 = inherit/auto). Must be set here so the editbox shows the saved value immediately.
            castbarSpellNameFontSizeSlider:SetValue(g.castbarSpellNameFontSize or 0)
        end
        if highlightEnableCheck then highlightEnableCheck:SetChecked(g.highlightEnabled ~= false) end
        if highlightColorDrop then
            local colorKey = g.highlightColor
            if type(colorKey) ~= "string" or not MSUF_FONT_COLORS[colorKey] then
                colorKey = "white"
                g.highlightColor = colorKey
            end
            UIDropDownMenu_SetSelectedValue(highlightColorDrop, colorKey)
            local label = colorKey
            local colorList = (panel and panel.__MSUF_COLOR_LIST) or _G.MSUF_COLOR_LIST
            if colorList then
                for _, opt in ipairs(colorList) do
                    if opt.key == colorKey then
                        label = opt.label
                        break
                    end
                end
            end
            UIDropDownMenu_SetText(highlightColorDrop, label)
        end
if bossSpacingSlider then
    if currentKey == "boss" then
        bossSpacingSlider:Show()
        if bossSpacingSlider.editBox then bossSpacingSlider.editBox:Show() end
    else
        bossSpacingSlider:Hide()
        if bossSpacingSlider.editBox then bossSpacingSlider.editBox:Hide() end
    end
end
        if currentTabKey == "fonts" or currentTabKey == "bars" or currentTabKey == "misc" or currentTabKey == "profiles" then  return end
        conf = MSUF_DB[currentKey]
        if not conf then  return end
        if bossSpacingSlider and currentKey == "boss" then bossSpacingSlider:SetValue(conf.spacing or -36) end
if panel.bossPortraitDrop and panel.bossPortraitLabel then
    if currentKey == "boss" then
        panel.bossPortraitDrop:Show()
        panel.bossPortraitLabel:Show()
        local mode = conf.portraitMode or "OFF"
        UIDropDownMenu_SetSelectedValue(panel.bossPortraitDrop, mode)
        local textLabel = "Portrait Off"
        if mode == "LEFT" then
            textLabel = "Portrait Left"
        elseif mode == "RIGHT" then
            textLabel = "Portrait Right"
        end
        UIDropDownMenu_SetText(panel.bossPortraitDrop, textLabel)
    else
        panel.bossPortraitDrop:Hide()
        panel.bossPortraitLabel:Hide()
    end
end
        local function GetOffsetValue(v, default)
            if v == nil then  return default end
             return v
        end
        -- Player-only: mirror values into the compact stepper UI.
        if ns and ns.MSUF_Options_Player_ApplyFromDB then ns.MSUF_Options_Player_ApplyFromDB(self, currentKey, conf, g, GetOffsetValue) end
         end
    -- Player-only compact Text layout handlers are installed by Options\MSUF_Options_Player.lua
    if ns and ns.MSUF_Options_Player_InstallHandlers then
        ns.MSUF_Options_Player_InstallHandlers(panel, {
            getTabKey = function()   return currentTabKey end,
            getKey    = function()   return currentKey end,
            EnsureDB  = EnsureDB,
            ApplySettingsForKey = ApplySettingsForKey,
            CallUpdateAllFonts  = MSUF_CallUpdateAllFonts,
        })
    end
    -- Style all toggle labels: checked = white, unchecked = grey
    if MSUF_StyleAllToggles then MSUF_StyleAllToggles(panel) end
    panel.__MSUF_FullBuilt = true
    -- Ensure aggro/dispel/purge test modes persist while the user navigates
    -- between menu tabs (Bars Ã¢â€ â€ Colors), but clear when the slash menu closes.
    if not panel.__MSUF_AggroTestHooked then
        panel.__MSUF_AggroTestHooked = true
        local function _ClearAllTestModes()
            if type(_G.MSUF_SetAggroBorderTestMode) == "function" then
                _G.MSUF_SetAggroBorderTestMode(false)
            end
            if type(_G.MSUF_SetDispelBorderTestMode) == "function" then
                _G.MSUF_SetDispelBorderTestMode(false)
            end
            if type(_G.MSUF_SetPurgeBorderTestMode) == "function" then
                _G.MSUF_SetPurgeBorderTestMode(false)
            end
            if panel.aggroTestCheck then panel.aggroTestCheck:SetChecked(false) end
            if panel.dispelTestCheck then panel.dispelTestCheck:SetChecked(false) end
            if panel.purgeTestCheck then panel.purgeTestCheck:SetChecked(false) end
        end
        -- Standalone slash menu window (/msuf)
        local slashWin = _G.MSUF_StandaloneOptionsWindow
        if slashWin and not slashWin.__MSUF_TestCleanupHooked then
            slashWin.__MSUF_TestCleanupHooked = true
            slashWin:HookScript("OnHide", _ClearAllTestModes)
        end
        -- If slash window is created later, hook it on next Show.
        if not slashWin then
            _G.MSUF_TestCleanup_Deferred = _ClearAllTestModes
        end
    end

SetCurrentKey("player")
panel:LoadFromDB()
MSUF_CallUpdateAllFonts()
    if not (_G and _G.MSUF_SLASHMENU_ONLY) then
    -- Ensure root category exists (launcher). Never re-register the root against the heavy Legacy panel.
    local rootCat = (_G and _G.MSUF_SettingsCategory) or MSUF_SettingsCategory
    if not rootCat and Settings and Settings.RegisterCanvasLayoutCategory then
        -- Emergency fallback (should normally be created by MSUF_RegisterOptionsCategoryLazy)
        local launcher = (_G and _G.MSUF_LauncherPanel) or CreateFrame("Frame")
        if _G then _G.MSUF_LauncherPanel = launcher end
        launcher.name = "Midnight Simple Unit Frames"
        rootCat = Settings.RegisterCanvasLayoutCategory(launcher, launcher.name)
        Settings.RegisterAddOnCategory(rootCat)
        if _G then _G.MSUF_SettingsCategory = rootCat end
    end
    MSUF_SettingsCategory = rootCat
    if ns then ns.MSUF_MainCategory = rootCat end
    -- Ensure Legacy subcategory exists for this heavy panel.
    if Settings and Settings.RegisterCanvasLayoutSubcategory and rootCat then
        if not (_G and _G.MSUF_LegacyCategory) then
            local legacyCat = Settings.RegisterCanvasLayoutSubcategory(rootCat, panel, (panel.name or "Legacy"))
            Settings.RegisterAddOnCategory(legacyCat)
            if _G then _G.MSUF_LegacyCategory = legacyCat end
        end
    end
    -- Sub-categories are safe to (re)register; patched versions build lazily on first open.
    if ns and ns.MSUF_RegisterGameplayOptions then ns.MSUF_RegisterGameplayOptions(rootCat) end
    if ns and ns.MSUF_RegisterColorsOptions then ns.MSUF_RegisterColorsOptions(rootCat) end
    if ns and ns.MSUF_RegisterAurasOptions then ns.MSUF_RegisterAurasOptions(rootCat) end
    if ns and ns.MSUF_RegisterBossCastbarOptions then ns.MSUF_RegisterBossCastbarOptions(rootCat) end
end
     return panel
end
if panel and panel.LoadFromDB and not panel.__MSUF_OnShowHooked then
    panel.__MSUF_OnShowHooked = true
    panel:SetScript("OnShow", function(self)
        if self.LoadFromDB then self:LoadFromDB() end
     end)
end
if _G and not _G.__MSUF_LauncherAutoRegistered then
    _G.__MSUF_LauncherAutoRegistered = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if type(MSUF_RegisterOptionsCategoryLazy) == "function" then MSUF_RegisterOptionsCategoryLazy() end
         end)
    else
        if type(MSUF_RegisterOptionsCategoryLazy) == "function" then MSUF_RegisterOptionsCategoryLazy() end
    end
end
