local addonName, ns = ...
ns = ns or {}

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


local function MSUF_ResetDropdownListScroll(listFrame)
    if not listFrame or not listFrame._msufScrollActive then return end

    local listName = listFrame.GetName and listFrame:GetName() or nil
    if listName then
        local numButtons = tonumber(listFrame.numButtons) or 0
        for i = 1, numButtons do
            local btn = _G[listName .. "Button" .. i]
            if btn then
                if btn._msufBasePoint and btn.ClearAllPoints and btn.SetPoint then
                    btn:ClearAllPoints()
                    btn:SetPoint(
                        btn._msufBasePoint,
                        listFrame,
                        btn._msufBaseRelPoint or btn._msufBasePoint,
                        btn._msufBaseX or 0,
                        btn._msufBaseY or 0
                    )
                end
                if btn.Show then btn:Show() end
                btn._msufHiddenByMSUF = nil
            end
        end
    end

    listFrame._msufScrollActive = nil
    listFrame._msufScrollMaxVisible = nil
    listFrame._msufScrollButtonStep = nil
    listFrame._msufScrollDir = nil

    if listFrame.SetClipsChildren then
        listFrame:SetClipsChildren(false)
    end

    local sb = listFrame._msufScrollBar
    if sb then
        sb:Hide()
        -- DropDownList1 is global/reused: ensure we never run the template's SecureScrollTemplates handler.
        if sb.SetScript then sb:SetScript("OnValueChanged", nil) end
        if sb.SetValue then sb:SetValue(0) end
    end
end

local function MSUF_ApplyDropdownListScroll(listFrame, maxVisible)
    if not listFrame or not listFrame.IsShown or not listFrame:IsShown() then return end

    local numButtons = tonumber(listFrame.numButtons) or 0
    maxVisible = tonumber(maxVisible) or 12
    if numButtons <= maxVisible or maxVisible < 2 then
        MSUF_ResetDropdownListScroll(listFrame)
        return
    end

    -- Determine per-row step by measuring the first two button anchors (supports
    -- client changes to UIDROPDOWNMENU_BUTTON_HEIGHT).
    local listName = listFrame.GetName and listFrame:GetName() or nil
    local b1 = listName and _G[listName .. "Button1"] or nil
    local b2 = listName and _G[listName .. "Button2"] or nil

    local step = tonumber(_G.UIDROPDOWNMENU_BUTTON_HEIGHT) or 16
    local dir = -1 -- default: rows go downward (y decreases)
    if b1 and b2 and b1.GetPoint and b2.GetPoint then
        local _, _, _, _, y1 = b1:GetPoint(1)
        local _, _, _, _, y2 = b2:GetPoint(1)
        if type(y1) == "number" and type(y2) == "number" and y1 ~= y2 then
            step = (y1 > y2) and (y1 - y2) or (y2 - y1)
            dir = (y2 < y1) and -1 or 1
        end
    end

    local border = tonumber(_G.UIDROPDOWNMENU_BORDER_HEIGHT) or 15
    local desiredHeight = (maxVisible * step) + (border * 2) + 6 -- small padding so last row doesn't kiss the edge

    listFrame._msufScrollActive = true
    listFrame._msufScrollMaxVisible = maxVisible
    listFrame._msufScrollButtonStep = step
    listFrame._msufScrollDir = dir

    -- IMPORTANT: do NOT clip children here. We "window" by showing only visible buttons instead.
    if listFrame.SetClipsChildren then
        listFrame:SetClipsChildren(false)
    end
    listFrame:SetHeight(desiredHeight)

    -- Create a scrollbar once per listFrame (DropDownList1 is global/reused).
    local sb = listFrame._msufScrollBar
    if not sb and type(_G.CreateFrame) == "function" then
        sb = _G.CreateFrame("Slider", nil, listFrame, "UIPanelScrollBarTemplate")
        sb:SetWidth(16)
        sb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -6, -18)
        sb:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, 18)
        sb:SetMinMaxValues(0, 0)

        -- CRITICAL: UIPanelScrollBarTemplate ships with a default handler that expects
        -- sb.scrollFrame:SetVerticalScroll(). DropDownList1 is NOT a scrollFrame → nil crash.
        sb.scrollFrame = nil
        if sb.SetScript then sb:SetScript("OnValueChanged", nil) end

        sb:SetValue(0)
        sb:Hide()
        listFrame._msufScrollBar = sb

        -- Mouse wheel scrolling on the dropdown list.
        listFrame:EnableMouseWheel(true)
        listFrame:HookScript("OnMouseWheel", function(_, delta)
            if not listFrame._msufScrollActive then return end
            local s = listFrame._msufScrollBar
            if not s or not s.IsShown or not s:IsShown() then return end
            local cur = tonumber(s:GetValue()) or 0
            local minV, maxV = s:GetMinMaxValues()
            local nextV = cur - (delta * 1) -- one row per wheel notch (no skipping)
            if nextV < minV then nextV = minV end
            if nextV > maxV then nextV = maxV end
            s:SetValue(nextV)
        end)

        -- Cleanup when the dropdown closes (important because DropDownList1 is reused).
        listFrame:HookScript("OnHide", function()
            MSUF_ResetDropdownListScroll(listFrame)
        end)
    end

    if not sb then
        return
    end

    local maxOffset = numButtons - maxVisible
    if maxOffset < 0 then maxOffset = 0 end

    sb:SetMinMaxValues(0, maxOffset)
    sb:SetValueStep(1)
    sb:SetStepsPerPage(maxVisible - 1)

    -- Capture base anchors for this open (x/y can differ between dropdown styles).
    local topPoint, topRelPoint, topX, topY
    if listName then
        for i = 1, numButtons do
            local btn = _G[listName .. "Button" .. i]
            if btn and btn.GetPoint then
                local p, _, rp, x, y = btn:GetPoint(1)
                btn._msufBasePoint = p
                btn._msufBaseRelPoint = rp
                btn._msufBaseX = x
                btn._msufBaseY = y
                if i == 1 then
                    topPoint = p
                    topRelPoint = rp or p
                    topX = x or 0
                    topY = y or 0
                end
            end
        end
    end

    local function ApplyOffset(offset)
        offset = tonumber(offset) or 0
        offset = math.floor(offset + 0.5)
        if offset < 0 then offset = 0 end
        if offset > maxOffset then offset = maxOffset end

        if not listName or not topPoint then return end

        for i = 1, numButtons do
            local btn = _G[listName .. "Button" .. i]
            if btn and btn.ClearAllPoints and btn.SetPoint then
                local visIndex = i - offset
                if visIndex < 1 or visIndex > maxVisible then
                    if btn.Hide then btn:Hide() end
                    btn._msufHiddenByMSUF = true
                else
                    if btn.Show then btn:Show() end
                    btn._msufHiddenByMSUF = nil
                    btn:ClearAllPoints()
                    local y = topY + ((visIndex - 1) * step * dir)
                    btn:SetPoint(topPoint, listFrame, topRelPoint, topX, y)
                end
            end
        end
    end

    if sb.SetScript then
        sb:SetScript("OnValueChanged", function(_, value)
            if not listFrame._msufScrollActive then return end
            ApplyOffset(value)
        end)
    end

    sb:SetValue(0)
    sb:Show()

    ApplyOffset(0)
end

-- Bar texture dropdown list preview: keep the right-side swatch small so it doesn't cover the dropdown area.
-- Bar texture dropdown list preview: keep the swatch on the LEFT and only in the "middle" area,
-- so it never covers the dropdown's right edge / scrollbar.
local function MSUF_TweakBarTextureDropdownList(listFrame)
    if not listFrame or not listFrame.dropdown then return end
    local dd = listFrame.dropdown
    if not dd or not dd._msufTweakBarTexturePreview then return end

    local listName = listFrame.GetName and listFrame:GetName() or nil
    if not listName then return end

    local numButtons = tonumber(listFrame.numButtons) or 0
    if numButtons < 1 then return end

    local iconW, iconH = 80, 12

    -- Use the dropdown list's reported width. maxWidth exists on DropDownList1 in modern clients.
    local listW = tonumber(listFrame.maxWidth) or (listFrame.GetWidth and listFrame:GetWidth()) or 195
    -- Center the preview bar in the left half (matches your screenshot).
    local leftX = math.floor((listW * 0.62) - (iconW * 0.5) + 0.5)
    if leftX < 60 then leftX = 60 end

    for i = 1, numButtons do
        local btn = _G[listName .. "Button" .. i]
        if btn and btn.GetName then
            local btnName = btn:GetName()
            local icon = btn.Icon or (btnName and _G[btnName .. "Icon"]) or btn.icon
            if icon and icon.GetTexture and icon.ClearAllPoints and icon.SetPoint and icon.SetSize then
                local tex = icon:GetTexture()
                if tex then
                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", btn, "LEFT", leftX, 0)
                    icon:SetSize(iconW, iconH)
                    if icon.SetTexCoord then
                        icon:SetTexCoord(0, 0.85, 0, 1)
                    end
                end
            end
        end
    end
end

local function MSUF_EnsureDropdownScrollHook()
    if ns and ns.__msufScrollDropdownHooked then return end
    if ns then ns.__msufScrollDropdownHooked = true end

    if type(_G.hooksecurefunc) ~= "function" then return end

    _G.hooksecurefunc("ToggleDropDownMenu", function(level, value, dropDownFrame)
        local lvl = tonumber(level) or 1
        local listFrame = _G["DropDownList" .. lvl]
        if not listFrame then return end

        -- If MSUF scroll was active but we're opening a different menu now, reset.
        if listFrame._msufScrollActive and (not dropDownFrame or listFrame.dropdown ~= dropDownFrame or not dropDownFrame._msufScrollMaxVisible) then
            MSUF_ResetDropdownListScroll(listFrame)
        end

        if not dropDownFrame or not dropDownFrame._msufScrollMaxVisible then return end
        if listFrame.dropdown ~= dropDownFrame then return end

        MSUF_ApplyDropdownListScroll(listFrame, dropDownFrame._msufScrollMaxVisible)
        MSUF_TweakBarTextureDropdownList(listFrame)
    end)
end

local function MSUF_MakeDropdownScrollable(dropdown, maxVisible)
    if not dropdown then return end
    dropdown._msufScrollMaxVisible = tonumber(maxVisible) or 12
    MSUF_EnsureDropdownScrollHook()
end

-- Expand the clickable area of a Blizzard UIDropDownMenu so the whole dropdown "box" is clickable,
-- not just the small arrow button. We do this by expanding the Button hit-rect to the dropdown size.
local function MSUF_ExpandDropdownClickArea(dropdown)
    if not dropdown or dropdown.__msufExpandedClickArea then return end
    dropdown.__msufExpandedClickArea = true

    local function Apply()
        local name = dropdown.GetName and dropdown:GetName()
        local btn = dropdown.Button or (name and _G[name .. "Button"])
        if not btn then return end

        local dw = tonumber(dropdown:GetWidth()) or 0
        local dh = tonumber(dropdown:GetHeight()) or 0
        local bw = tonumber(btn:GetWidth()) or 0
        local bh = tonumber(btn:GetHeight()) or 0

        -- Defer until we have real sizes (happens after layout/scale is applied).
        if dw <= 1 or dh <= 1 or bw <= 1 or bh <= 1 then
            if _G.C_Timer and type(_G.C_Timer.After) == "function" then
                _G.C_Timer.After(0, Apply)
            end
            return
        end

        local extendLeft = math.max(0, dw - bw)
        local extendTop  = math.max(0, (dh - bh) / 2)

        -- Negative insets expand the hit rect.
        btn:SetHitRectInsets(-extendLeft - 2, -2, -extendTop - 2, -extendTop - 2)
    end

    dropdown:HookScript("OnShow", Apply)
    dropdown:HookScript("OnSizeChanged", Apply)

    local name = dropdown.GetName and dropdown:GetName()
    local btn = dropdown.Button or (name and _G[name .. "Button"])
    if btn and btn.HookScript then
        btn:HookScript("OnSizeChanged", Apply)
    end

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Apply)
    else
        Apply()
    end
end

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
    if not bar then return end
    bar:Hide()
    if bar.SetAlpha then bar:SetAlpha(0) end
    if bar.SetHeight then bar:SetHeight(0.1) end
    -- Prevent any later code from showing it again
    bar.Show = function() end
    bar.SetShown = function() end
end

-- Call into main/module font refresh (main chunk may keep this local; main exports MSUF_UpdateAllFonts)
local function MSUF_CallUpdateAllFonts()
    local fn
    if _G then
        fn = _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts
    end
    if (not fn) and ns and ns.MSUF_UpdateAllFonts then
        fn = ns.MSUF_UpdateAllFonts
    end
    if type(fn) == "function" then
        return fn()
    end
end

-- Local number parser (Options chunk can’t rely on main-file locals)
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
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

    -- Root (AddOns list) panel: lightweight launcher with two buttons.
    local launcher = (_G and _G.MSUF_LauncherPanel) or CreateFrame("Frame")
    if _G then _G.MSUF_LauncherPanel = launcher end
    launcher.name = "Midnight Simple Unit Frames"

    -- Legacy Options panel (heavy UI, built on first open).
    local p = (_G and _G.MSUF_OptionsPanel) or CreateFrame("Frame")
    if _G then _G.MSUF_OptionsPanel = p end
    p.name = "Legacy Settings"
    p.parent = launcher.name

    -- Register the main category now (cheap) so Settings.OpenToCategory works immediately.
    local rootCat = (_G and _G.MSUF_SettingsCategory) or nil
    if not rootCat then
        local cat = Settings.RegisterCanvasLayoutCategory(launcher, launcher.name)
        Settings.RegisterAddOnCategory(cat)
        rootCat = cat
        if _G then _G.MSUF_SettingsCategory = cat end
    end

    MSUF_SettingsCategory = rootCat
    if ns then
        ns.MSUF_MainCategory = rootCat
    end

    -- Register sub-categories lazily too (their register functions are patched to build on first open).
    if ns and ns.MSUF_RegisterGameplayOptions then
        ns.MSUF_RegisterGameplayOptions(rootCat)
    end
    if ns and ns.MSUF_RegisterColorsOptions then
        ns.MSUF_RegisterColorsOptions(rootCat)
    end
    if ns and ns.MSUF_RegisterAurasOptions then
        ns.MSUF_RegisterAurasOptions(rootCat)
    end
    if ns and ns.MSUF_RegisterBossCastbarOptions then
        ns.MSUF_RegisterBossCastbarOptions(rootCat)
    end

    -- Ensure Legacy subcategory exists (keeps the old Settings UI accessible).
    if Settings and Settings.RegisterCanvasLayoutSubcategory and rootCat then
        if not (_G and _G.MSUF_LegacyCategory) then
            local legacyCat = Settings.RegisterCanvasLayoutSubcategory(rootCat, p, p.name)
            Settings.RegisterAddOnCategory(legacyCat)
            if _G then _G.MSUF_LegacyCategory = legacyCat end
        end
    end

    -- Build the launcher UI (title + short help + 2 buttons) on-demand when the panel is shown.

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
            end)
        end

        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00MSUF:|r Cannot open settings while in combat. Will open after combat.")
        elseif print then
            print("MSUF: Cannot open settings while in combat. Will open after combat.")
        end
        return
    end

    fn()
end

    local function MSUF_BuildLauncherUI()
        if launcher.__MSUF_LauncherBuilt then return end
        launcher.__MSUF_LauncherBuilt = true

        local title = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        launcher.__MSUF_LauncherTitle = title
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Midnight Simple Unit Frames")

        local desc = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        launcher.__MSUF_LauncherDesc = desc
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        desc:SetJustifyH("LEFT")
        desc:SetJustifyV("TOP")
        desc:SetText("Choose which settings UI to open:\n\n• Slash / Flash Menu: the new standalone MSUF UI (recommended).\n• Legacy Settings: the old Blizzard Settings panel kept for compatibility.")

        local w = launcher.GetWidth and launcher:GetWidth() or 0
        if w and w > 0 then
            desc:SetWidth(math.max(420, w - 40))
        else
            desc:SetWidth(600)
        end

        local btnSlash = CreateFrame("Button", nil, launcher, "UIPanelButtonTemplate")
        launcher.__MSUF_LauncherBtnSlash = btnSlash
        btnSlash:SetSize(260, 32)
        btnSlash:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
        btnSlash:SetText("Open Slash / Flash Menu")
        btnSlash:SetScript("OnClick", function()
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

        local btnLegacy = CreateFrame("Button", nil, launcher, "UIPanelButtonTemplate")
        launcher.__MSUF_LauncherBtnLegacy = btnLegacy
        btnLegacy:SetSize(260, 32)
        btnLegacy:SetPoint("TOPLEFT", btnSlash, "BOTTOMLEFT", 0, -10)
        btnLegacy:SetText("Open Legacy Settings")
        btnLegacy:SetScript("OnClick", function()
        MSUF_RunAfterCombat(function()
            -- Ensure categories exist (safe if already registered)
            if _G and type(_G.MSUF_RegisterOptionsCategoryLazy) == "function" then
                _G.MSUF_RegisterOptionsCategoryLazy()
            end

            local legacyCat = _G and _G.MSUF_LegacyCategory
            if Settings and Settings.OpenToCategory and legacyCat and legacyCat.GetID then
                Settings.OpenToCategory(legacyCat:GetID())
                return
            end

            if InterfaceOptionsFrame_OpenToCategory and _G and _G.MSUF_OptionsPanel then
                InterfaceOptionsFrame_OpenToCategory(_G.MSUF_OptionsPanel)
                return
            end
        end)
        end)

        local note = launcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", btnLegacy, "BOTTOMLEFT", 2, -10)
        note:SetJustifyH("LEFT")
        note:SetText("Tip: /msuf opens the Flash menu.")
    end

    if not launcher.__MSUF_LauncherOnShowHooked then
        launcher.__MSUF_LauncherOnShowHooked = true
        launcher:SetScript("OnShow", function(self)
            if not self.__MSUF_LauncherBuilt then
                MSUF_BuildLauncherUI()
            end
            local d = self.__MSUF_LauncherDesc
            if d and d.SetWidth then
                local w = self.GetWidth and self:GetWidth() or 0
                if w and w > 0 then
                    d:SetWidth(math.max(420, w - 40))
                end
            end
        end)
        launcher:SetScript("OnSizeChanged", function(self)
            local d = self.__MSUF_LauncherDesc
            if d and d.SetWidth then
                local w = self.GetWidth and self:GetWidth() or 0
                if w and w > 0 then
                    d:SetWidth(math.max(420, w - 40))
                end
            end
        end)
    end

    -- Build now too (some containers show the panel without firing OnShow the first time)
    MSUF_BuildLauncherUI()

    -- First open of the Legacy panel builds the full Options UI.
    if not p.__MSUF_LazyBuildHooked then
        p.__MSUF_LazyBuildHooked = true
        p:SetScript("OnShow", function(self)
            if self.__MSUF_FullBuilt then
                if self.LoadFromDB then self:LoadFromDB() end
                return
            end
            if type(CreateOptionsPanel) == "function" then
                CreateOptionsPanel()
            end
        end)
    end
end

function CreateOptionsPanel()
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end

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
    if unitKey == "tot" then return "targettarget" end
    if type(unitKey) == "string" and unitKey:match("^boss%d+$") then return "boss" end
    return unitKey
end

local function MSUF_Options_IsUrgentUnitKey(unitKey)
    return (unitKey == "target" or unitKey == "targettarget" or unitKey == "focus")
end

local function MSUF_Options_RequestLayoutForKey(unitKey, reason, urgent)
    unitKey = MSUF_Options_NormalizeUnitKey(unitKey)
    if type(unitKey) ~= "string" then return false end

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

local function MSUF_UpdatePowerBarHeightFromEdit(editBox)
    if not editBox or not editBox.GetText then return end

    local text = editBox:GetText()
    local v = MSUF_GetNumber(text, 3, 3, 50)

    editBox:SetText(tostring(v))

    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.powerBarHeight = v

    if _G.MSUF_UnitFrames then
        units = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
        for _, key in ipairs(units) do
            f = _G.MSUF_UnitFrames[key]
            if f and f.targetPowerBar then
                f.targetPowerBar:SetHeight(v)
                if type(_G.MSUF_ApplyPowerBarEmbedLayout) == 'function' then
                    _G.MSUF_ApplyPowerBarEmbedLayout(f)
                end
            end
        end
    end

    ApplyAllSettings()
end

panel = (_G and _G.MSUF_OptionsPanel) or CreateFrame("Frame")
    _G.MSUF_OptionsPanel = panel
    panel.name = "Midnight Simple Unit Frames"

    title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames (Beta Version)")

    sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    -- Keep this subtitle short (avoid wrapping into the navigation rows) and avoid ALL-CAPS.
    sub:SetText("Thank you for using MSUF.")

    local searchLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetText("")
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

    frameGroup = CreateFrame("Frame", nil, panel)
    frameGroup:SetAllPoints()

    fontGroup = CreateFrame("Frame", nil, panel)
    fontGroup:SetAllPoints()

    auraGroup = CreateFrame("Frame", nil, panel)
    auraGroup:SetAllPoints()

    castbarGroup = CreateFrame("Frame", nil, panel)
    castbarGroup:SetAllPoints()

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

    barGroup = CreateFrame("Frame", nil, panel)
    barGroup:SetAllPoints()

    miscGroup = CreateFrame("Frame", nil, panel)
    miscGroup:SetAllPoints()

    profileGroup = CreateFrame("Frame", nil, panel)
    profileGroup:SetAllPoints()

    local currentKey = "player"
    local currentTabKey = "frames"
    local UNIT_FRAME_KEYS = { player=true, target=true, targettarget=true, focus=true, pet=true, boss=true }
    local buttons = {}
    local editModeButton

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
        if currentTabKey == "fonts" then
            frameGroup:Hide()
            fontGroup:Show()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "bars" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Show()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "auras" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Show()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "castbar" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Show()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "misc" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Show()
            profileGroup:Hide()
        elseif currentTabKey == "profiles" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Show()
        else
            frameGroup:Show()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()

            -- Player-only layout: hide the old right-column offset sliders and show the compact group.
            local isUnitFrame = (UNIT_FRAME_KEYS[currentKey] == true)

            if panel and panel.playerTextLayoutGroup then
                panel.playerTextLayoutGroup:SetShown(isUnitFrame)
            end
            if panel and panel.playerBasicsBox then
                panel.playerBasicsBox:SetShown(isUnitFrame)
            end
            if panel and panel.playerSizeBox then
                panel.playerSizeBox:SetShown(isUnitFrame)
            end
        end
        if editModeButton then
            -- Show the shared bottom-left Edit Mode button in:
            -- * Frames tab (unit frames)
            -- * Castbar tab (castbar edit mode)
            if currentTabKey == "castbar" then
                editModeButton:Show()
            elseif currentTabKey == "frames" and (
                currentKey == "player"
                or currentKey == "target"
                or currentKey == "targettarget"
                or currentKey == "focus"
                or currentKey == "boss"
                or currentKey == "pet"
            ) then
                editModeButton:Show()
            else
                editModeButton:Hide()
            end
        end

    end

    local function IsTabKey(k)
        return k == "bars" or k == "fonts" or k == "auras" or k == "castbar" or k == "misc" or k == "profiles"
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
            if buttons[currentKey] and buttons[currentKey].Disable then
                buttons[currentKey]:Disable()
            end
        else
            if buttons[currentTabKey] and buttons[currentTabKey].Disable then
                buttons[currentTabKey]:Disable()
            end
        end

        UpdateGroupVisibility()
    end

    function MSUF_GetTabButtonHelpers(requestedPanel)
        if requestedPanel == panel then
            return buttons, SetCurrentKey
        end
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
            barGroup          = barGroup,
            miscGroup         = miscGroup,
            profileGroup      = profileGroup,
            buttons           = buttons,
            getCurrentKey     = function() return (currentTabKey == "frames" and currentKey) or currentTabKey end,
            setCurrentKey     = SetCurrentKey,
        })
    end
    local function MSUF_SkinMidnightTabButton(btn)
        if not btn then return end

        local GOLD_R, GOLD_G, GOLD_B = 1.00, 0.82, 0.00

        local function EnsureActiveLine(self)
            if self.__msufActiveLine then return end
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
            hooksecurefunc(btn, "Disable", function(self) ApplyState(self, true) end)
            hooksecurefunc(btn, "Enable", function(self) ApplyState(self, false) end)
            btn:HookScript("OnShow", function(self) ApplyState(self, self.IsEnabled and (not self:IsEnabled()) or false) end)
        end

        ApplyState(btn, btn.IsEnabled and (not btn:IsEnabled()) or false)
    end

    -- Flat midnight-style button for small action buttons (Focus Kick / Castbar Edit Mode, etc.)
    -- Keeps the dark look without the sticky blue highlight.
    local function MSUF_SkinMidnightActionButton(btn, opts)
        if not btn or btn.__msufMidnightActionSkinned then return end
        btn.__msufMidnightActionSkinned = true

        opts = opts or {}
        local r, g, b, a = (opts.r or 0.06), (opts.g or 0.06), (opts.b or 0.06), (opts.a or 0.92)

        local function SetRegionColor(self, rr, gg, bb, aa)
            local name = self.GetName and self:GetName()
            local left  = self.Left  or (name and _G[name .. "Left"]) or nil
            local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
            local right = self.Right or (name and _G[name .. "Right"]) or nil

            if left then left:SetTexture("Interface\\Buttons\\WHITE8x8"); left:SetVertexColor(rr, gg, bb, aa or 1) end
            if mid then mid:SetTexture("Interface\\Buttons\\WHITE8x8"); mid:SetVertexColor(rr, gg, bb, aa or 1) end
            if right then right:SetTexture("Interface\\Buttons\\WHITE8x8"); right:SetVertexColor(rr, gg, bb, aa or 1) end

            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then
                nt:SetTexture("Interface\\Buttons\\WHITE8x8")
                nt:SetVertexColor(rr, gg, bb, aa or 1)
                nt:SetTexCoord(0, 1, 0, 1)
            end
        end

        SetRegionColor(btn, r, g, b, a)

        -- Subtle overlays; avoid calling SetHighlightTexture/SetPushedTexture directly (can error on some builds).
        do
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
            if hl then
                hl:SetTexture("Interface/Buttons/WHITE8x8")
                hl:SetVertexColor(1, 1, 1, 0) -- fully transparent
                hl:SetTexCoord(0, 1, 0, 1)
                hl:SetAllPoints(btn)
            end

            local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
            if pt then
                pt:SetTexture("Interface/Buttons/WHITE8x8")
                pt:SetVertexColor(1, 1, 1, 0.06) -- tiny pressed tint
                pt:SetTexCoord(0, 1, 0, 1)
                pt:SetAllPoints(btn)
            end
        end

        local fs = btn.GetFontString and btn:GetFontString() or nil
        if fs and fs.SetTextColor then
            local tr = (opts.textR ~= nil) and opts.textR or 0.92
            local tg = (opts.textG ~= nil) and opts.textG or 0.92
            local tb = (opts.textB ~= nil) and opts.textB or 0.92
            fs:SetTextColor(tr, tg, tb)
        end
    end

    local function CreateUnitButton(key, xOffset, yOffset)
        b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(90, 22)
        MSUF_SkinMidnightTabButton(b)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (xOffset or 0), yOffset or -50)
        b:SetText(GetLabelForKey(key))
        b:SetScript("OnClick", function()
            SetCurrentKey(key)
            panel:LoadFromDB()
        end)
        buttons[key] = b
    end

    CreateUnitButton("player",        0,   -50)
    CreateUnitButton("target",      100,   -50)
    CreateUnitButton("targettarget",200,   -50)
    CreateUnitButton("focus",       300,   -50)
    CreateUnitButton("boss",        400,   -50)
    CreateUnitButton("pet",         500,   -50)

    CreateUnitButton("bars",          0,   -80)
    CreateUnitButton("fonts",       100,   -80)
    CreateUnitButton("auras",       200,   -80)
    CreateUnitButton("castbar",     300,   -80)
    CreateUnitButton("misc",        400,   -80)
    CreateUnitButton("profiles",    500,   -80)

    editModeButton = CreateFrame("Button", "MSUF_EditModeButton", panel, "UIPanelButtonTemplate")
    editModeButton:SetSize(160, 32)  -- fairly large
    editModeButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
    editModeButton:SetText("Edit Mode")

    editHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editHint:SetPoint("LEFT", editModeButton, "RIGHT", 12, 0)
    editHint:SetJustifyH("LEFT")
    -- Quick hint: we now do frame ON/OFF + layout in MSUF Edit Mode (stable + secure).
    editHint:SetText("")
    editHint:Hide()
    snapCheck = CreateFrame("CheckButton", "MSUF_EditModeSnapCheck", panel, "UICheckButtonTemplate")
    snapCheck:SetPoint("LEFT", editHint, "RIGHT", 16, 0)

    snapText = _G["MSUF_EditModeSnapCheckText"]
    if snapText then
        snapText:SetText("Snap to grid")
    end
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
if emFont then
    emFont:SetFontObject("GameFontNormalLarge")
end
    function MSUF_SyncCastbarEditModeWithUnitEdit()
    if not MSUF_DB or not MSUF_DB.general then
        return
    end

    local g = MSUF_DB.general

    g.castbarPlayerPreviewEnabled = MSUF_UnitEditModeActive and true or false

    local function RefreshAll()
        if MSUF_UpdatePlayerCastbarPreview then
            MSUF_UpdatePlayerCastbarPreview()
        end

        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
            _G.MSUF_UpdateBossCastbarPreview()
        end
        if type(MSUF_SetupBossCastbarPreviewEditMode) == "function" then
            MSUF_SetupBossCastbarPreviewEditMode()
        end
    end

    RefreshAll()

    if g.castbarPlayerPreviewEnabled and C_Timer and C_Timer.After then
        C_Timer.After(0, RefreshAll)
    end
end

function MSUF_SyncBossUnitframePreviewWithUnitEdit()
    -- Boss preview/test frames:
    -- - Active only during MSUF Edit Mode
    -- - Requires Boss unitframe enabled
    -- - Optional user toggle via MSUF_EditModeBossPreviewCheck (if present)

    if type(EnsureDB) == "function" then
        EnsureDB()
    end

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
            if MSUF_DB.general.bossPreviewEnabled == nil then
                MSUF_DB.general.bossPreviewEnabled = true
            end
            bossPreviewEnabled = MSUF_DB.general.bossPreviewEnabled and true or false
        end
    end

    local active = (editActive and bossEnabled and bossPreviewEnabled) and true or false

    -- Boss Test Mode is the internal switch that force-shows boss frames for editing.
    MSUF_BossTestMode = active

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    -- Refresh secure visibility drivers so a previous "hide" state does not stick.
    if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then
        MSUF_RefreshAllUnitVisibilityDrivers(editActive)
    end

    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames["boss" .. i])
        if f then
            -- Update first (may hide if unit doesn't exist), then force-show if active.
            if type(UpdateSimpleUnitFrame) == "function" then
                UpdateSimpleUnitFrame(f)
            end

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
                    if UnitExists and not UnitExists(unit) then
                        f:Hide()
                    end
                end
            end
        end
    end
end

-- Toggle Castbar Edit Mode from the shared bottom-left Edit Mode button (Castbar tab).
-- NOTE: We are NOT deleting Castbar Edit Mode itself; we only remove the extra button inside the Castbar menu.
-- The shared Edit Mode button now drives the full flow: enable MSUF Edit Mode + enable castbar previews + start test casts.
local function MSUF_ToggleCastbarEditModeFromOptions()
    if type(EnsureDB) == "function" then
        EnsureDB()
    end
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
        if wantActive and type(MSUF_BeginEditModeTransaction) == "function" then
            MSUF_BeginEditModeTransaction()
        end
    end

    -- Ensure castbar previews follow Edit Mode.
    if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
        MSUF_SyncCastbarEditModeWithUnitEdit()
    end

    -- Start/stop dummy casts on previews so changes are visible.
    local fns = {
        "MSUF_SetPlayerCastbarTestMode",
        "MSUF_SetTargetCastbarTestMode",
        "MSUF_SetFocusCastbarTestMode",
        "MSUF_SetBossCastbarTestMode",
    }
    for _, fnName in ipairs(fns) do
        local fn = _G[fnName]
        if type(fn) == "function" then
            pcall(fn, wantActive)
        end
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

        if wantActive and type(MSUF_BeginEditModeTransaction) == "function" then
            MSUF_BeginEditModeTransaction()
        end
        if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
            MSUF_SyncCastbarEditModeWithUnitEdit()
        end
        if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then
            MSUF_SyncBossUnitframePreviewWithUnitEdit()
        end
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

                        print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cff00ff00ON|r – drag the " .. label .. " frame with the left mouse button or use the arrow buttons.")
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
        if not slider or slider.MSUFStyled then return end
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
            if self.MSUFTrack then
                self.MSUFTrack:SetColorTexture(0.20, 0.20, 0.20, 1)
            end
        end)

        slider:HookScript("OnLeave", function(self)
            if self.MSUFTrack then
                self.MSUFTrack:SetColorTexture(0.06, 0.06, 0.06, 1)
            end
        end)
    end

local function MSUF_StyleSmallButton(button, isPlus)
    if not button or button.MSUFStyled then return end
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
        if hasNew then
            return
        end

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
            if not AnyDirOn(g) then
                g[dbKey] = true
            end

            -- Keep legacy key around as "last touched" for older builds/tools.
            g.gradientDirection = dirKey

            if pad.SyncFromDB then pad:SyncFromDB() end
            if type(ApplyAllSettings) == "function" then
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

            if btn._msufSel then
                btn._msufSel:SetShown(isOn)
            end
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

        local enabled = (g.enableGradient ~= false)
        self:SetEnabledVisual(enabled)
    end

    pad:SyncFromDB()
    return pad
end

local function MSUF_StyleDPadButton(button, label)
    if not button or button.MSUF_StyledDPad then return end
    button.MSUF_StyledDPad = true

    button:SetSize(20, 20)

    local ntex = button:CreateTexture(nil, "BACKGROUND")
    ntex:SetTexture(MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8")
    ntex:SetAllPoints(button)
    ntex:SetVertexColor(0, 0, 0, 0.55)
    button:SetNormalTexture(ntex)

    local ptex = button:CreateTexture(nil, "BACKGROUND")
    ptex:SetTexture(MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8")
    ptex:SetAllPoints(button)
    ptex:SetVertexColor(0.25, 0.25, 0.25, 0.75)
    button:SetPushedTexture(ptex)

    local htex = button:CreateTexture(nil, "HIGHLIGHT")
    htex:SetTexture(MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8")
    htex:SetAllPoints(button)
    htex:SetVertexColor(1, 1, 1, 0.08)
    button:SetHighlightTexture(htex)

    local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetAllPoints(button)
    border:SetBackdrop({ edgeFile = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    border:SetBackdropBorderColor(1, 1, 1, 0.14)
    button._msufBorder = border

    local t = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("CENTER", button, "CENTER", 0, -1)
    t:SetText(label or "")
    button.text = t

    function button:MSUF_SetSelected(selected)
        if self._msufBorder then
            if selected then
                self._msufBorder:SetBackdropBorderColor(1, 0.82, 0.0, 0.85)
            else
                self._msufBorder:SetBackdropBorderColor(1, 1, 1, 0.14)
            end
        end
    end
end

local function CreateLabeledSlider(name, label, parent, minVal, maxVal, step, x, y)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")

    local extraY = 0
    if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then
        extraY = -40
    end

    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + extraY)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider.minVal = minVal
    slider.maxVal = maxVal
    slider.step   = step

    local low  = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]

    if low  then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(label or "")     end

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
            if slider.step and slider.step >= 1 then
                cur = math.floor(cur + 0.5)
            end
            eb:SetText(tostring(cur))
            return
        end

        if val < slider.minVal then val = slider.minVal end
        if val > slider.maxVal then val = slider.maxVal end
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
        if slider.step and slider.step >= 1 then
            cur = math.floor(cur + 0.5)
        end
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
        slider:SetValue(nv)
    end)

    MSUF_StyleSmallButton(plus, true) -- Midnight plus

    slider:SetScript("OnValueChanged", function(self, value)
        if self.MSUF_SkipCallback then return end
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
            if cur ~= formatted then
                self.editBox:SetText(formatted)
            end
        end

        if self.onValueChanged then
            self.onValueChanged(self, value)
        end
    end)

    MSUF_StyleSlider(slider)

    return slider
end

-- Show/Hide a labeled slider AND its attached editbox/plus/minus + template texts.
-- Needed because our sliders' editboxes/buttons are parented to the container, not the slider itself.
function MSUF_SetSliderVisibility(slider, show)
    if not slider then return end

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
    if not slider then return end

    local name = (slider.GetName and slider:GetName())
    local label = (name and _G and _G[name .. "Text"]) or slider.label or slider.Text or slider.text
    local low  = (name and _G and _G[name .. "Low"])  or nil
    local high = (name and _G and _G[name .. "High"]) or nil

    local function SetBtnEnabled(btn, en)
        if not btn then return end
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

-- Set a labeled slider's value WITHOUT triggering side-effects, while still updating its numeric editbox.
-- Needed because CreateLabeledSlider only syncs the editbox via OnValueChanged, which we often skip during panel sync.
local function MSUF_SetLabeledSliderValue(slider, value)
    if not slider then return end
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
    if not dropdown then return end

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

-- Compact +/- stepper with an input box (used for text offsets).
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
        if f.step and f.step >= 1 then
            v = math.floor(v + 0.5)
        end
        return v
    end

    function f:SetValue(v, fromUser)
        v = Clamp(v)
        f.value = v

        if f.editBox and not f.editBox:HasFocus() then
            -- Always show 0 properly.
            f.editBox:SetText(tostring(v))
        end

        if fromUser and f.onValueChanged then
            f.onValueChanged(f, v)
        end
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
        if f.editBox and not f.editBox:HasFocus() then
            f.editBox:SetText(tostring(f.value or 0))
        end
    end)

    return f
end

local function MSUF_StyleToggleText(cb)
        if not cb or cb.__msufToggleTextStyled then return end
        cb.__msufToggleTextStyled = true

        local fs = cb.text or cb.Text
        if (not fs) and cb.GetName and cb:GetName() and _G then
            fs = _G[cb:GetName() .. 'Text']
        end
        if not (fs and fs.SetTextColor) then return end

        cb.__msufToggleFS = fs

        local function Update()
            if cb.IsEnabled and (not cb:IsEnabled()) then
                fs:SetTextColor(0.35, 0.35, 0.35)
            else
                if cb.GetChecked and cb:GetChecked() then
                    fs:SetTextColor(1, 1, 1)
                else
                    fs:SetTextColor(0.55, 0.55, 0.55)
                end
            end
        end

        cb.__msufToggleUpdate = Update
        cb:HookScript('OnShow', Update)
        cb:HookScript('OnClick', Update)
        pcall(hooksecurefunc, cb, 'SetChecked', function() Update() end)
        pcall(hooksecurefunc, cb, 'SetEnabled', function() Update() end)
        Update()
    end

    -- ---------------------------------------------------------------------
    -- Checkmark skin: replace Blizzard yellow tick with MSUF tick textures
    -- Uses alpha-texture ticks so they match MSUF theme and can be tinted.
    -- ---------------------------------------------------------------------
    local _msufAddonName = (type(addonName) == 'string' and addonName ~= '' and addonName) or 'MidnightSimpleUnitFrames'
    local MSUF_CHECK_TEX_THIN = 'Interface/AddOns/' .. _msufAddonName .. '/Media/msuf_check_tick_thin.tga'
    local MSUF_CHECK_TEX_BOLD = 'Interface/AddOns/' .. _msufAddonName .. '/Media/msuf_check_tick_bold.tga'

    local function MSUF_StyleCheckmark(cb)
        if not cb or cb.__msufCheckmarkStyled then return end
        cb.__msufCheckmarkStyled = true

        local check = (cb.GetCheckedTexture and cb:GetCheckedTexture())
        if (not check) and cb.GetName and cb:GetName() and _G then
            check = _G[cb:GetName() .. 'Check']
        end
        if not (check and check.SetTexture) then return end

        local h = (cb.GetHeight and cb:GetHeight()) or 24
        local tex = (h >= 24) and MSUF_CHECK_TEX_BOLD or MSUF_CHECK_TEX_THIN

        check:SetTexture(tex)
        check:SetTexCoord(0, 1, 0, 1)
        if check.SetBlendMode then check:SetBlendMode('BLEND') end

        -- Keep it centered inside the box and slightly smaller than the button.
        if check.ClearAllPoints then
            check:ClearAllPoints()
            check:SetPoint('CENTER', cb, 'CENTER', 0, 0)
        end
        if check.SetSize then
            local s = math.floor((h * 0.72) + 0.5)
            if s < 12 then s = 12 end
            check:SetSize(s, s)
        end

        -- Some templates may call SetCheckedTexture later; lock our style.
        if cb.HookScript and not cb.__msufCheckmarkHooked then
            cb.__msufCheckmarkHooked = true
            local function Reapply()
                if cb.__msufCheckmarkReapplying then return end
                cb.__msufCheckmarkReapplying = true
                local c = (cb.GetCheckedTexture and cb:GetCheckedTexture()) or check
                if c and c.SetTexture then
                    local hh = (cb.GetHeight and cb:GetHeight()) or h
                    local tt = (hh >= 24) and MSUF_CHECK_TEX_BOLD or MSUF_CHECK_TEX_THIN
                    c:SetTexture(tt)
                    if c.SetBlendMode then c:SetBlendMode('BLEND') end
                    if c.ClearAllPoints then
                        c:ClearAllPoints()
                        c:SetPoint('CENTER', cb, 'CENTER', 0, 0)
                    end
                    if c.SetSize then
                        local ss = math.floor((hh * 0.72) + 0.5)
                        if ss < 12 then ss = 12 end
                        c:SetSize(ss, ss)
                    end
                end
                cb.__msufCheckmarkReapplying = nil
            end
            cb:HookScript('OnShow', Reapply)
            cb:HookScript('OnSizeChanged', Reapply)
        end
    end
    local function MSUF_StyleAllToggles(root)
        if not root or not root.GetChildren then return end
        local children = { root:GetChildren() }
        for i = 1, #children do
            local c = children[i]
            if c and c.GetObjectType and c:GetObjectType() == 'CheckButton' then
                MSUF_StyleToggleText(c)
                MSUF_StyleCheckmark(c)
            end
            if c and c.GetChildren then
                MSUF_StyleAllToggles(c)
            end
        end
    end

    local function CreateLabeledCheckButton(name, label, parent, x, y)
        local cb = CreateFrame('CheckButton', name, parent, 'UICheckButtonTemplate')

        local extraY = 0
        if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then
            extraY = -40
        end

        cb:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y + extraY)
        cb.text = _G[name .. 'Text']
        if cb.text then
            cb.text:SetText(label)
        end
        MSUF_StyleToggleText(cb)
        MSUF_StyleCheckmark(cb)
        return cb
    end

    -- Player options UI is implemented in Options\MSUF_Options_Player.lua (refactored out of Options Core).
    if ns and ns.MSUF_Options_Player_Build then
        ns.MSUF_Options_Player_Build(panel, frameGroup, {
            texWhite = MSUF_TEX_WHITE8,
            CreateLabeledSlider = CreateLabeledSlider,
            CreateAxisStepper   = CreateAxisStepper,
        })

    -- Re-anchor boss-only controls into the boxed unitframe UI (so they don't float around)
    -- (removed) old boss portrait reposition block
    if bossSpacingSlider and panel and panel.playerSizeBox then
        bossSpacingSlider:ClearAllPoints()
        bossSpacingSlider:SetPoint("TOPLEFT", panel.playerSizeBox, "BOTTOMLEFT", 12, -32)
    end
    end

    StaticPopupDialogs["MSUF_CONFIRM_RESET_PROFILE"] = {
        text = "Reset all font size overrides?\n\nThis clears per-unit overrides for Name/Health/Power AND per-castbar overrides for Cast Name/Time so everything inherits the global defaults.",
            button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                MSUF_ResetProfile(data.name)

                if data.panel.LoadFromDB then
                    data.panel:LoadFromDB()
                end
                if data.panel.UpdateProfileUI then
                    data.panel:UpdateProfileUI(data.name)
                end
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["MSUF_CONFIRM_DELETE_PROFILE"] = {
        text = "Are you sure you want to delete '%s'?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data)
            if data and data.name and data.panel then
                MSUF_DeleteProfile(data.name)
                data.panel:UpdateProfileUI(MSUF_ActiveProfile)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
      profileTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    profileTitle:SetPoint("TOPLEFT", profileGroup, "TOPLEFT", 16, -140)
    profileTitle:SetText("Profiles")
resetBtn = CreateFrame("Button", "MSUF_ProfileResetButton", profileGroup, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 24)
resetBtn:SetPoint("TOPLEFT", profileTitle, "BOTTOMLEFT", 0, -10)
resetBtn:SetText("Reset profile")
resetBtn:SetScript("OnClick", function()
    if not MSUF_ActiveProfile then
        print("|cffff0000MSUF:|r No active profile selected to reset.")
        return
    end
    local name = MSUF_ActiveProfile
    StaticPopup_Show(
        "MSUF_CONFIRM_RESET_PROFILE",
        name,
        nil,
        { name = name, panel = panel }
    )
end)

deleteBtn = CreateFrame("Button", "MSUF_ProfileDeleteButton", profileGroup, "UIPanelButtonTemplate")
deleteBtn:SetSize(140, 24)
deleteBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
deleteBtn:SetText("Delete profile")

-- Keep the label for internal updates, but hide it so it never overlaps the buttons.
currentProfileLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
currentProfileLabel:Hide()

if MSUF_SkinMidnightActionButton then
    MSUF_SkinMidnightActionButton(resetBtn, { textR = 1, textG = 0.85, textB = 0.1 })
    MSUF_SkinMidnightActionButton(deleteBtn, { textR = 1, textG = 0.85, textB = 0.1 })
end

    helpText = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
    helpText:SetWidth(540)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("Profiles are global. Each character selects one active profile. Create a new profile on the left or select an existing one on the right.")

    newLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    newLabel:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -14)
    newLabel:SetText("New")

    existingLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    existingLabel:SetPoint("LEFT", newLabel, "LEFT", 260, 0)
    existingLabel:SetText("Existing profiles")

    newEditBox = CreateFrame("EditBox", "MSUF_ProfileNewEdit", profileGroup, "InputBoxTemplate")
    newEditBox:SetSize(220, 20)
    newEditBox:SetAutoFocus(false)
    newEditBox:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -4)

    profileDrop = CreateFrame("Frame", "MSUF_ProfileDropdown", profileGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(profileDrop)
    profileDrop:SetPoint("TOPLEFT", existingLabel, "BOTTOMLEFT", -16, -4)

    local function MSUF_ProfileDropdown_Initialize(self, level)
        if not level then return end
        profiles = MSUF_GetAllProfiles()
        for _, name in ipairs(profiles) do
            info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.func = function(btn)
                UIDropDownMenu_SetSelectedValue(self, btn.value)
                UIDropDownMenu_SetText(self, btn.value)
                MSUF_SwitchProfile(btn.value)
                currentProfileLabel:SetText("Current profile: " .. btn.value)
            end
            info.checked = (name == MSUF_ActiveProfile)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(profileDrop, MSUF_ProfileDropdown_Initialize)
    UIDropDownMenu_SetWidth(profileDrop, 180)
    UIDropDownMenu_SetText(profileDrop, MSUF_ActiveProfile or "Default")

    function panel:UpdateProfileUI(currentName)
        name = currentName or MSUF_ActiveProfile or "Default"
        currentProfileLabel:SetText("Current profile: " .. name)
        UIDropDownMenu_SetSelectedValue(profileDrop, name)
        UIDropDownMenu_SetText(profileDrop, name)
    end

    newEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        name = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            MSUF_CreateProfile(name)
            MSUF_SwitchProfile(name)
            self:SetText("")
            panel:UpdateProfileUI(name)
        end
    end)

deleteBtn:SetScript("OnClick", function()
    if not MSUF_ActiveProfile then
        return
    end

    name = MSUF_ActiveProfile

    if name == "Default" then
        print("|cffff0000MSUF:|r Das 'Default'-Thanks for testing and reporting bugs no you can not delete Default'.")
        return
    end

    StaticPopup_Show(
        "MSUF_CONFIRM_DELETE_PROFILE",
        name,       -- ersetzt %s im Text
        nil,
        {
            name  = name,   -- geht an data.name im Popup
            panel = panel,  -- geht an data.panel -> für UpdateProfileUI
        }
    )
end)

    profileLine = profileGroup:CreateTexture(nil, "ARTWORK")
    profileLine:SetColorTexture(1, 1, 1, 0.18)
    profileLine:SetPoint("TOPLEFT", newEditBox, "BOTTOMLEFT", 0, -20)
    profileLine:SetSize(540, 1)

    importTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importTitle:SetPoint("TOPLEFT", profileLine, "BOTTOMLEFT", 0, -10)
    importTitle:SetText("Profile export / import")


    local function MSUF_CreateSimpleDialog(frameName, titleText, w, h)
        local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetSize(w or 520, h or 96)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.92)

        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText(titleText or "")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() f:Hide() end)

        f:Hide()
        return f, title
    end

    -- Ctrl+C copy popup
    local copyPopup, copyTitle, copyEdit
    local function MSUF_ShowCopyPopup(str)
        if not copyPopup then
            copyPopup, copyTitle = MSUF_CreateSimpleDialog("MSUF_ProfileCopyPopup", "Ctrl+C to copy", 560, 96)

            copyEdit = CreateFrame("EditBox", nil, copyPopup, "InputBoxTemplate")
            copyEdit:SetAutoFocus(true)
            copyEdit:SetSize(500, 22)
            copyEdit:SetPoint("TOP", copyPopup, "TOP", 0, -36)
            copyEdit:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                copyPopup:Hide()
            end)

            local done = CreateFrame("Button", nil, copyPopup, "UIPanelButtonTemplate")
            done:SetSize(90, 22)
            done:SetPoint("BOTTOM", 0, 10)
            done:SetText("Done")
            done:SetScript("OnClick", function() copyPopup:Hide() end)

            if MSUF_SkinMidnightActionButton then
                MSUF_SkinMidnightActionButton(done, { textR = 1, textG = 0.85, textB = 0.1 })
            end

            copyPopup:SetScript("OnShow", function()
                if copyEdit then
                    copyEdit:HighlightText()
                end
            end)
        end

        copyEdit:SetText(str or "")
        copyEdit:HighlightText()
        copyPopup:Show()
        copyEdit:SetFocus()
    end

    -- Ctrl+V paste popup (new/legacy)
    local importPopup, importTitleFS, importEdit, importDoBtn
    local function MSUF_ShowImportPopup(mode)
        mode = (mode == "legacy") and "legacy" or "new"

        if not importPopup then
            importPopup, importTitleFS = MSUF_CreateSimpleDialog("MSUF_ProfileImportPopup", "Ctrl+V to paste", 560, 110)

            importEdit = CreateFrame("EditBox", nil, importPopup, "InputBoxTemplate")
            importEdit:SetAutoFocus(true)
            importEdit:SetSize(500, 22)
            importEdit:SetPoint("TOP", importPopup, "TOP", 0, -36)
            importEdit:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                importPopup:Hide()
            end)

            importDoBtn = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            importDoBtn:SetSize(110, 22)
            importDoBtn:SetPoint("BOTTOM", importPopup, "BOTTOM", -60, 10)
            importDoBtn:SetText("Import")

            local cancel = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            cancel:SetSize(110, 22)
            cancel:SetPoint("LEFT", importDoBtn, "RIGHT", 10, 0)
            cancel:SetText("Cancel")
            cancel:SetScript("OnClick", function() importPopup:Hide() end)

            if MSUF_SkinMidnightActionButton then
                MSUF_SkinMidnightActionButton(importDoBtn, { textR = 1, textG = 0.85, textB = 0.1 })
                MSUF_SkinMidnightActionButton(cancel,     { textR = 1, textG = 0.85, textB = 0.1 })
            end

            local function runImport()
                local str = (importEdit and importEdit.GetText) and (importEdit:GetText() or "") or ""

                local Importer
                if importPopup._msufMode == "legacy" then
                    Importer = _G.MSUF_ImportLegacyFromString or (ns and ns.MSUF_ImportLegacyFromString)
                else
                    Importer = _G.MSUF_ImportFromString or (ns and ns.MSUF_ImportFromString)
                end

                if type(Importer) ~= "function" then
                    print("|cffff0000MSUF:|r Import failed: importer missing.")
                    return
                end

                Importer(str)

                if ApplyAllSettings then
                    ApplyAllSettings()
                end
                MSUF_CallUpdateAllFonts()
                if panel and panel.LoadFromDB then
                    panel:LoadFromDB()
                end
                if panel and panel.UpdateProfileUI then
                    panel:UpdateProfileUI(MSUF_ActiveProfile)
                end

                importPopup:Hide()
            end

            importDoBtn:SetScript("OnClick", runImport)
            importEdit:SetScript("OnEnterPressed", function() runImport() end)
        end

        importPopup._msufMode = mode
        if importTitleFS then
            if mode == "legacy" then
                importTitleFS:SetText("Ctrl+V to paste (Legacy Import)")
            else
                importTitleFS:SetText("Ctrl+V to paste")
            end
        end

        importEdit:SetText("")
        importPopup:Show()
        importEdit:SetFocus()
    end

    -- Buttons (clean panel, no giant box)
    importBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    importBtn:SetSize(110, 22)
    importBtn:SetPoint("TOPLEFT", importTitle, "BOTTOMLEFT", 0, -12)
    importBtn:SetText("Import")

    exportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    exportBtn:SetSize(110, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    exportBtn:SetText("Export")

    legacyImportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    legacyImportBtn:SetSize(120, 22)
    legacyImportBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    legacyImportBtn:SetText("Legacy Import")

    if MSUF_SkinMidnightActionButton then
        MSUF_SkinMidnightActionButton(importBtn,       { textR = 1, textG = 0.85, textB = 0.1 })
        MSUF_SkinMidnightActionButton(exportBtn,       { textR = 1, textG = 0.85, textB = 0.1 })
        MSUF_SkinMidnightActionButton(legacyImportBtn, { textR = 1, textG = 0.85, textB = 0.1 })
    end

    importBtn:SetScript("OnClick", function() MSUF_ShowImportPopup("new") end)
    legacyImportBtn:SetScript("OnClick", function() MSUF_ShowImportPopup("legacy") end)

    -----------------------------------------------------------------
    -- Export picker (Platynator-style)
    -----------------------------------------------------------------
    local exportPopup
    local function MSUF_ShowExportPicker()
        if exportPopup and exportPopup:IsShown() then
            exportPopup:Hide()
            return
        end

        if not exportPopup then
            exportPopup = CreateFrame("Frame", "MSUF_ProfileExportPicker", UIParent, "BackdropTemplate")
            exportPopup:SetFrameStrata("DIALOG")
            exportPopup:SetClampedToScreen(true)
            exportPopup:SetSize(420, 86)
            exportPopup:SetPoint("CENTER")
            exportPopup:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            exportPopup:SetBackdropColor(0, 0, 0, 0.92)

            local title = exportPopup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            title:SetPoint("TOP", 0, -8)
            title:SetText("What to export?")

            local close = CreateFrame("Button", nil, exportPopup, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", -2, -2)
            close:SetScript("OnClick", function() exportPopup:Hide() end)

            local function makeBtn(text)
                local b = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
                b:SetSize(120, 22)
                b:SetText(text)
                if MSUF_SkinMidnightActionButton then
                    MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 })
                end
                return b
            end

            exportPopup.btnUnit = makeBtn("Unitframes")
            exportPopup.btnCast = makeBtn("Castbars")
            exportPopup.btnCol  = makeBtn("Colors")
            exportPopup.btnGame = makeBtn("Gameplay")
            exportPopup.btnAll  = makeBtn("Everything")

            exportPopup.btnUnit:SetPoint("BOTTOMLEFT", 10, 10)
            exportPopup.btnCast:SetPoint("LEFT", exportPopup.btnUnit, "RIGHT", 8, 0)
            exportPopup.btnCol:SetPoint("LEFT", exportPopup.btnCast, "RIGHT", 8, 0)
            exportPopup.btnGame:SetPoint("TOPLEFT", exportPopup.btnUnit, "TOPLEFT", 0, 26)
            exportPopup.btnAll:SetPoint("LEFT", exportPopup.btnGame, "RIGHT", 8, 0)

            local function doExport(kind)
                local Exporter = _G.MSUF_ExportSelectionToString or (ns and ns.MSUF_ExportSelectionToString)
                if type(Exporter) ~= "function" then
                    print("|cffff0000MSUF:|r Export failed: exporter missing (MSUF_ExportSelectionToString).")
                    exportPopup:Hide()
                    return
                end

                local str = Exporter(kind)
                MSUF_ShowCopyPopup(str or "")
                exportPopup:Hide()
                print("|cff00ff00MSUF:|r Exported " .. tostring(kind) .. " settings.")
            end

            exportPopup.btnUnit:SetScript("OnClick", function() doExport("unitframe") end)
            exportPopup.btnCast:SetScript("OnClick", function() doExport("castbar") end)
            exportPopup.btnCol:SetScript("OnClick", function() doExport("colors") end)
            exportPopup.btnGame:SetScript("OnClick", function() doExport("gameplay") end)
            exportPopup.btnAll:SetScript("OnClick", function() doExport("all") end)
        end

        exportPopup:Show()
    end

    exportBtn:SetScript("OnClick", MSUF_ShowExportPicker)
    fontTitle = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fontTitle:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)

globalFontHeader = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
globalFontHeader:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)
globalFontHeader:SetText("Global font")

globalFontLine = fontGroup:CreateTexture(nil, "ARTWORK")
globalFontLine:SetColorTexture(1, 1, 1, 0.2)
globalFontLine:SetSize(220, 1)
globalFontLine:SetPoint("TOPLEFT", globalFontHeader, "BOTTOMLEFT", 0, -4)

fontColorHeader = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
fontColorHeader:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 276, -140)
fontColorHeader:SetText("Font color & style")

fontColorLine = fontGroup:CreateTexture(nil, "ARTWORK")
fontColorLine:SetColorTexture(1, 1, 1, 0.2)
fontColorLine:SetSize(260, 1)
fontColorLine:SetPoint("TOPLEFT", fontColorHeader, "BOTTOMLEFT", 0, -4)

fontDrop = CreateFrame("Frame", "MSUF_FontDropdown", fontGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(fontDrop)
fontDrop:SetPoint("TOPLEFT", globalFontLine, "BOTTOMLEFT", -16, -8)

    fontChoices = {}

    local function MSUF_RebuildFontChoices()
        fontChoices = {}

        local internal = (_G.MSUF_FONT_LIST or FONT_LIST or {})
        for _, info in ipairs(internal) do
            table.insert(fontChoices, {
                key   = info.key,   -- e.g. "FRIZQT" / "EXPRESSWAY"
                label = info.name,  -- dropdown label
                path  = info.path,  -- file path for internal fonts (may be nil)
            })
        end

        local LSM = MSUF_GetLSM()
        if LSM then
            -- Make sure internal / Blizzard fonts are also resolvable via LibSharedMedia.
            -- IMPORTANT: LSM:Fetch("font", key) will *always* return the library default if the key isn't registered,
            -- which makes Blizzard's built-in keys (FRIZQT/ARIALN/MORPHEUS/SKURRI) look "dead".
            -- Use noDefault=true when checking existence, then register the built-ins if missing.
            if LSM.Register then
                for _, data in ipairs(fontChoices) do
                    local k  = data.key
                    local fp = data.path
                    if k and k ~= "" and fp and fp ~= "" then
                        local existing
                        if LSM.Fetch then
                            local okFetch, val = pcall(LSM.Fetch, LSM, "font", k, true) -- noDefault=true
                            if okFetch then existing = val end
                        end

                        if not existing then
                            pcall(LSM.Register, LSM, "font", k, fp)
                        end
                    end
                end
            end

            names = LSM:List("font")
            table.sort(names)

            used = {}
            for _, e in ipairs(fontChoices) do
                used[e.key] = true   -- dedupe by KEY
            end

            for _, name in ipairs(names) do
                if not used[name] then
                    table.insert(fontChoices, {
                        key   = name,  -- key that LSM:Fetch expects
                        label = name,
                    })
                    used[name] = true
                end
            end
        end
    end

local function FontDropdown_Initialize(self, level)
    EnsureDB()

    if not fontChoices or #fontChoices == 0 then
        MSUF_RebuildFontChoices()
    end

    info = UIDropDownMenu_CreateInfo()
    local fontKey = MSUF_DB.general.fontKey

    for _, data in ipairs(fontChoices) do
        local thisKey   = data.key
        local thisLabel = data.label

        info.text       = thisLabel
        info.value      = thisKey

        local _fp = _G.MSUF_GetFontPreviewObject or MSUF_GetFontPreviewObject or (ns and ns.MSUF_GetFontPreviewObject)
        if _fp then
            info.fontObject = _fp(thisKey)
        else
            info.fontObject = GameFontHighlightSmall
        end

        info.func = function()
            EnsureDB()
            MSUF_DB.general.fontKey = thisKey

            UIDropDownMenu_SetSelectedValue(fontDrop, thisKey)
            UIDropDownMenu_SetText(fontDrop, thisLabel)

            MSUF_CallUpdateAllFonts()

            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    MSUF_CallUpdateAllFonts()
                end)
            end
        end

        info.checked = (fontKey == thisKey)
        UIDropDownMenu_AddButton(info, level)
    end
end
    UIDropDownMenu_Initialize(fontDrop, FontDropdown_Initialize)
    UIDropDownMenu_SetWidth(fontDrop, 180)

		-- If LibSharedMedia is unavailable, keep this dropdown non-interactive to avoid invalid DB selections.
		if not MSUF_GetLSM() then
			UIDropDownMenu_DisableDropDown(fontDrop)
		end

    fontDrop._msufButtonWidth = 180
    MSUF_MakeDropdownScrollable(fontDrop, 12)
    do
        local fontKey2 = MSUF_DB.general.fontKey
        local currentLabel = fontKey2
        for _, data in ipairs(fontChoices) do
            if data.key == fontKey2 then
                currentLabel = data.label
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(fontDrop, fontKey2)
        UIDropDownMenu_SetText(fontDrop, currentLabel)
    end
MSUF_COLOR_LIST = {
    { key = "white",     r=1,   g=1,   b=1,   label="White" },
    { key = "black",     r=0,   g=0,   b=0,   label="Black" },
    { key = "red",       r=1,   g=0,   b=0,   label="Red" },
    { key = "green",     r=0,   g=1,   b=0,   label="Green" },
    { key = "blue",      r=0,   g=0,   b=1,   label="Blue" },
    { key = "yellow",    r=1,   g=1,   b=0,   label="Yellow" },
    { key = "cyan",      r=0,   g=1,   b=1,   label="Cyan" },
    { key = "magenta",   r=1,   g=0,   b=1,   label="Magenta" },
    { key = "orange",    r=1,   g=0.5, b=0,   label="Orange" },
    { key = "purple",    r=0.6, g=0,   b=0.8, label="Purple" },
    { key = "pink",      r=1,   g=0.6, b=0.8, label="Pink" },
    { key = "turquoise", r=0,   g=0.9, b=0.8, label="Turquoise" },
    { key = "grey",      r=0.5, g=0.5, b=0.5, label="Grey" },
    { key = "brown",     r=0.6, g=0.3, b=0.1, label="Brown" },
    { key = "gold",      r=1,   g=0.85,b=0.1, label="Gold" },
}

        boldCheck = CreateFrame("CheckButton", "MSUF_BoldTextCheck", fontGroup, "UICheckButtonTemplate")
    boldCheck:SetPoint("TOPLEFT", fontColorLine, "BOTTOMLEFT", 0, -12)
    boldCheck.text = _G["MSUF_BoldTextCheckText"]
    boldCheck.text:SetText("Use bold text (THICKOUTLINE)")

    noOutlineCheck = CreateFrame("CheckButton", "MSUF_NoOutlineCheck", fontGroup, "UICheckButtonTemplate")
    noOutlineCheck:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 0, -4)
    noOutlineCheck.text = _G["MSUF_NoOutlineCheckText"]
    noOutlineCheck.text:SetText("Disable black outline around text")

    nameClassColorCheck = CreateFrame("CheckButton", "MSUF_NameClassColorCheck", fontGroup, "UICheckButtonTemplate")
    nameClassColorCheck:SetPoint("TOPLEFT", noOutlineCheck, "BOTTOMLEFT", 0, -4)
    nameClassColorCheck.text = _G["MSUF_NameClassColorCheckText"]
    nameClassColorCheck.text:SetText("Color player names by class")

    npcNameRedCheck = CreateFrame("CheckButton", "MSUF_NPCNameRedCheck", fontGroup, "UICheckButtonTemplate")
    npcNameRedCheck:SetPoint("TOPLEFT", nameClassColorCheck, "BOTTOMLEFT", 0, -4)
    npcNameRedCheck.text = _G["MSUF_NPCNameRedCheckText"]
    npcNameRedCheck.text:SetText("Color NPC/boss names using NPC colors")

    shortenNamesCheck = CreateFrame("CheckButton", "MSUF_ShortenNamesCheck", fontGroup, "UICheckButtonTemplate")
    shortenNamesCheck:SetPoint("TOPLEFT", npcNameRedCheck, "BOTTOMLEFT", 0, -4)
    shortenNamesCheck.text = _G["MSUF_ShortenNamesCheckText"]
    shortenNamesCheck.text:SetText("Shorten unit names (except Player)")

    -- Name shortening direction (secret-safe viewport clip)
    local shortenNameClipSideLabel = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    shortenNameClipSideLabel:SetPoint("TOPLEFT", shortenNamesCheck, "BOTTOMLEFT", 16, -12)
    shortenNameClipSideLabel:SetText("Truncation style")

    local shortenNameClipSideDrop = CreateFrame("Frame", "MSUF_ShortenNameClipSideDrop", fontGroup, "UIDropDownMenuTemplate")
    if MSUF_ExpandDropdownClickArea then MSUF_ExpandDropdownClickArea(shortenNameClipSideDrop) end
    shortenNameClipSideDrop:SetPoint("TOPLEFT", shortenNameClipSideLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(shortenNameClipSideDrop, 180)

    local function MSUF_GetShortenClipSideLabel(value)
        if value == "RIGHT" then
            return "Keep start (show first letters)"
        end
        return "Keep end (show last letters)"
    end

    local function MSUF_UpdateShortenMaskLabel()
        local side = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.shortenNameClipSide) or "LEFT"
        local shortenEnabled = (MSUF_DB and MSUF_DB.shortenNames) and true or false
        local t = _G["MSUF_ShortenNameFrontMaskSliderText"]
        if t and t.SetText then
            if not shortenEnabled then
                t:SetText("Reserved space")
            elseif side == "RIGHT" then
                t:SetText("Reserved space (unused)")
            else
                t:SetText("Reserved space (left)")
            end
        end

        -- Legacy mode uses pure FontString width clipping (no viewport inset), so mask is irrelevant.
        if shortenNameFrontMaskSlider and shortenNameFrontMaskSlider.Enable and shortenNameFrontMaskSlider.Disable then
            if not shortenEnabled then
                shortenNameFrontMaskSlider:Disable()
            elseif side == "RIGHT" then
                shortenNameFrontMaskSlider:Disable()
            else
                shortenNameFrontMaskSlider:Enable()
            end
        end
    end

    local function MSUF_ShortenClipSide_OnSelect(value)
        EnsureDB()
        MSUF_DB.general.shortenNameClipSide = value
        UIDropDownMenu_SetSelectedValue(shortenNameClipSideDrop, value)
        UIDropDownMenu_SetText(shortenNameClipSideDrop, MSUF_GetShortenClipSideLabel(value))
        MSUF_UpdateShortenMaskLabel()

        if MSUF_DB.shortenNames then
            if MSUF_CallUpdateAllFonts then MSUF_CallUpdateAllFonts() end
            if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
        end
    end

    UIDropDownMenu_Initialize(shortenNameClipSideDrop, function(self, level)
        if not level then return end
        EnsureDB()
        local g = MSUF_DB.general or {}
        local current = g.shortenNameClipSide or "LEFT"

        local function AddOption(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = function()
                MSUF_ShortenClipSide_OnSelect(value)
            end
            info.checked = (current == value)
            UIDropDownMenu_AddButton(info, level)
        end

        AddOption("Keep end (show last letters)", "LEFT")
        AddOption("Keep start (show first letters)", "RIGHT")
    end)

    shortenNameClipSideDrop:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local current = g.shortenNameClipSide or "LEFT"
        UIDropDownMenu_SetSelectedValue(self, current)
        UIDropDownMenu_SetText(self, MSUF_GetShortenClipSideLabel(current))
        MSUF_UpdateShortenMaskLabel()
    end)

-- R41z0r-style name shortening control (secret-safe: width clipping only)
shortenNameMaxCharsSlider = CreateFrame("Slider", "MSUF_ShortenNameMaxCharsSlider", fontGroup, "OptionsSliderTemplate")
shortenNameMaxCharsSlider:SetWidth(180)
shortenNameMaxCharsSlider:SetMinMaxValues(6, 30)
shortenNameMaxCharsSlider:SetValueStep(1)
shortenNameMaxCharsSlider:SetObeyStepOnDrag(true)
shortenNameMaxCharsSlider:SetPoint("TOPLEFT", shortenNameClipSideDrop, "BOTTOMLEFT", 16, -18)

_G["MSUF_ShortenNameMaxCharsSliderLow"]:SetText("6")
_G["MSUF_ShortenNameMaxCharsSliderHigh"]:SetText("30")
_G["MSUF_ShortenNameMaxCharsSliderText"]:SetText("Max name length")

if MSUF_StyleSlider then
    MSUF_StyleSlider(shortenNameMaxCharsSlider)
end

-- Front mask (px): secret-safe viewport inset using a clipping frame (no overlay color)
shortenNameFrontMaskSlider = CreateFrame("Slider", "MSUF_ShortenNameFrontMaskSlider", fontGroup, "OptionsSliderTemplate")
shortenNameFrontMaskSlider:SetWidth(180)
shortenNameFrontMaskSlider:SetMinMaxValues(0, 40)
shortenNameFrontMaskSlider:SetValueStep(1)
shortenNameFrontMaskSlider:SetObeyStepOnDrag(true)
	shortenNameFrontMaskSlider:SetPoint("TOPLEFT", shortenNameMaxCharsSlider, "BOTTOMLEFT", 0, -28)

_G["MSUF_ShortenNameFrontMaskSliderLow"]:SetText("0")
_G["MSUF_ShortenNameFrontMaskSliderHigh"]:SetText("40")
_G["MSUF_ShortenNameFrontMaskSliderText"]:SetText("Reserved space")

if MSUF_StyleSlider then
    MSUF_StyleSlider(shortenNameFrontMaskSlider)
end

-- Info icon (click the "i" to show details)
local msufShortenInfoBtn = CreateFrame("Button", "MSUF_ShortenNameInfoButton", fontGroup)
msufShortenInfoBtn:SetSize(16, 16)
msufShortenInfoBtn:SetPoint("TOPLEFT", shortenNameFrontMaskSlider, "BOTTOMLEFT", 0, -10)
msufShortenInfoBtn:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
msufShortenInfoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
msufShortenInfoBtn:SetHitRectInsets(-4, -4, -4, -4)

msufShortenInfoBtn:SetScript("OnClick", function(self)
    if GameTooltip:IsOwned(self) and GameTooltip:IsShown() then
        GameTooltip:Hide()
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- GameTooltip:SetText signature differs across client versions.
    -- Keep it ultra-safe (no optional color/alpha params), use AddLine for colored/wrapped text.
    GameTooltip:SetText("Name Shortening")
    EnsureDB()
    local side = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.shortenNameClipSide) or "LEFT"
    if side == "RIGHT" then
        GameTooltip:AddLine("Keep start: shows the first letters (clips the end).", 1, 1, 1, true)
        GameTooltip:AddLine("Legacy clean mode uses plain FontString width clipping.", 0.95, 0.95, 0.95, true)
    else
        GameTooltip:AddLine("Keep end: shows the last letters (clips the beginning).", 1, 1, 1, true)
        GameTooltip:AddLine("Reserved space protects the clipped edge (avoids overlaps).", 0.95, 0.95, 0.95, true)
    end
    GameTooltip:Show()
end)


    textBackdropCheck = CreateFrame("CheckButton", "MSUF_TextBackdropCheck", fontGroup, "UICheckButtonTemplate")
    textBackdropCheck:SetPoint("TOPLEFT", shortenNameFrontMaskSlider, "BOTTOMLEFT", 0, -4)
    textBackdropCheck.text = _G["MSUF_TextBackdropCheckText"]
    textBackdropCheck.text:SetText("Add text shadow (backdrop)")

    EnsureDB()
    boldCheck:SetChecked(MSUF_DB.general.boldText and true or false)
    noOutlineCheck:SetChecked(MSUF_DB.general.noOutline and true or false)  -- NEW
    nameClassColorCheck:SetChecked(MSUF_DB.general.nameClassColor and true or false)
    npcNameRedCheck:SetChecked(MSUF_DB.general.npcNameRed and true or false)

local g = MSUF_DB.general
if g.shortenNameMaxChars == nil then g.shortenNameMaxChars = 6 end
g.shortenNameMaxChars = tonumber(g.shortenNameMaxChars) or 6
if g.shortenNameMaxChars < 4 then g.shortenNameMaxChars = 4 end
if g.shortenNameMaxChars > 40 then g.shortenNameMaxChars = 40 end

if g.shortenNameFrontMaskPx == nil then g.shortenNameFrontMaskPx = 8 end
g.shortenNameFrontMaskPx = tonumber(g.shortenNameFrontMaskPx) or 8
if g.shortenNameFrontMaskPx < 0 then g.shortenNameFrontMaskPx = 0 end
if g.shortenNameFrontMaskPx > 40 then g.shortenNameFrontMaskPx = 40 end

if g.shortenNameClipSide == nil then g.shortenNameClipSide = "LEFT" end
if g.shortenNameShowDots == nil then g.shortenNameShowDots = true end

if shortenNameMaxCharsSlider then shortenNameMaxCharsSlider:SetValue(g.shortenNameMaxChars) end
if shortenNameFrontMaskSlider then shortenNameFrontMaskSlider:SetValue(g.shortenNameFrontMaskPx) end
shortenNamesCheck:SetChecked(MSUF_DB.shortenNames and true or false)

if shortenNameClipSideDrop then
    UIDropDownMenu_SetSelectedValue(shortenNameClipSideDrop, g.shortenNameClipSide)
    UIDropDownMenu_SetText(shortenNameClipSideDrop, MSUF_GetShortenClipSideLabel(g.shortenNameClipSide))
    MSUF_UpdateShortenMaskLabel()
end

local enabled = (MSUF_DB.shortenNames and true or false)
if shortenNameMaxCharsSlider then
    if enabled then shortenNameMaxCharsSlider:Enable() else shortenNameMaxCharsSlider:Disable() end
end
if shortenNameFrontMaskSlider then
    if enabled then shortenNameFrontMaskSlider:Enable() else shortenNameFrontMaskSlider:Disable() end
end
if shortenNameClipSideDrop and MSUF_SetDropDownEnabled then
    MSUF_SetDropDownEnabled(shortenNameClipSideDrop, shortenNameClipSideLabel, enabled)
end
    textBackdropCheck:SetChecked(MSUF_DB.general.textBackdrop and true or false)

    boldCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.boldText = self:GetChecked() and true or false
        MSUF_CallUpdateAllFonts()
    end)
    noOutlineCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.noOutline = self:GetChecked() and true or false
        MSUF_CallUpdateAllFonts()
    end)

    nameClassColorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.nameClassColor = self:GetChecked() and true or false

        MSUF_CallUpdateAllFonts()

        if ns.MSUF_RefreshAllFrames then
            ns.MSUF_RefreshAllFrames()
        end
    end)

    npcNameRedCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.npcNameRed = self:GetChecked() and true or false

        MSUF_CallUpdateAllFonts()
        if ns.MSUF_RefreshAllFrames then
            ns.MSUF_RefreshAllFrames()
        end
    end)

shortenNamesCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.shortenNames = self:GetChecked() and true or false

    if shortenNameMaxCharsSlider then
        if MSUF_DB.shortenNames then
            shortenNameMaxCharsSlider:Enable()
        else
            shortenNameMaxCharsSlider:Disable()
        end
    end
    if shortenNameFrontMaskSlider then
        if MSUF_DB.shortenNames then
            shortenNameFrontMaskSlider:Enable()
        else
            shortenNameFrontMaskSlider:Disable()
        end
    end

    if shortenNameClipSideDrop and MSUF_SetDropDownEnabled then
        MSUF_SetDropDownEnabled(shortenNameClipSideDrop, shortenNameClipSideLabel, MSUF_DB.shortenNames)
        MSUF_UpdateShortenMaskLabel()
    end

    MSUF_Options_RequestLayoutAll("SHORTEN_NAMES")
    if MSUF_CallUpdateAllFonts then
        MSUF_CallUpdateAllFonts()
    end
    if ns and ns.MSUF_RefreshAllFrames then
        ns.MSUF_RefreshAllFrames()
    end
end)

if shortenNameMaxCharsSlider then
    shortenNameMaxCharsSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        value = math.floor((tonumber(value) or 16) + 0.5)
        MSUF_DB.general.shortenNameMaxChars = value

        if MSUF_DB.shortenNames then
            if MSUF_CallUpdateAllFonts then
                MSUF_CallUpdateAllFonts()
            end
            if ns and ns.MSUF_RefreshAllFrames then
                ns.MSUF_RefreshAllFrames()
            end
        end
    end)
end

if shortenNameFrontMaskSlider then
    shortenNameFrontMaskSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        value = math.floor((tonumber(value) or 0) + 0.5)
        if value < 0 then value = 0 end
        if value > 40 then value = 40 end
        MSUF_DB.general.shortenNameFrontMaskPx = value

        if MSUF_DB.shortenNames then
            if MSUF_CallUpdateAllFonts then
                MSUF_CallUpdateAllFonts()
            end
            if ns and ns.MSUF_RefreshAllFrames then
                ns.MSUF_RefreshAllFrames()
            end
        end
    end)
end

    textBackdropCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.textBackdrop = self:GetChecked() and true or false
        MSUF_CallUpdateAllFonts()
    end)

    textSizeHeader = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    textSizeHeader:ClearAllPoints()
    -- Text size defaults belong under the Global font dropdown (left column)
    -- so the right column (style checkboxes) stays clean and non-overlapping.
    textSizeHeader:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 16, -26)
    textSizeHeader:SetText("Text sizes")

    textSizeLine = fontGroup:CreateTexture(nil, "ARTWORK")
    textSizeLine:SetColorTexture(1, 1, 1, 0.2)
    textSizeLine:SetSize(260, 1)
    textSizeLine:ClearAllPoints()
    textSizeLine:SetPoint("TOPLEFT", textSizeHeader, "BOTTOMLEFT", 0, -4)

    -- These sliders are GLOBAL defaults. Unitframes inherit them unless they override locally.
    local textSizeHelp = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    textSizeHelp:SetPoint("TOPLEFT", textSizeLine, "BOTTOMLEFT", 0, -6)
    textSizeHelp:SetWidth(260)
    textSizeHelp:SetJustifyH("LEFT")
    textSizeHelp:SetText("Global defaults. Frames inherit unless overridden in Unitframes > Text.")

    local function MSUF_ListFontOverrides(confField)
        EnsureDB()
        local out = {}
        local keys = { "player", "target", "targettarget", "focus", "pet", "boss" }
        local pretty = { player="Player", target="Target", targettarget="ToT", focus="Focus", pet="Pet", boss="Boss" }
        for _, k in ipairs(keys) do
            local c = MSUF_DB[k]
            if c and c[confField] ~= nil then
                out[#out + 1] = pretty[k] or k
            end
        end
        return out
    end

    -- Compact one-row layout for text size defaults (Global).
    -- Unitframes inherit these values unless they override locally.
    local function MSUF_CompactTextSizeSlider(slider, shortLabel)
        if not slider then return end

        -- Keep the whole control compact so we can fit multiple columns on one row.
        slider:SetWidth(110)

        local n = slider.GetName and slider:GetName()
        if n then
            local low  = _G[n .. "Low"]
            local high = _G[n .. "High"]
            local text = _G[n .. "Text"]

            -- Low/High labels cost too much horizontal space in a 4-column row.
            if low  then low:Hide()  end
            if high then high:Hide() end

            if text then
                if shortLabel then text:SetText(shortLabel) end
                text:ClearAllPoints()
                text:SetPoint("BOTTOM", slider, "TOP", 0, 6)
                text:SetJustifyH("CENTER")
            end
        end

        if slider.editBox then
            slider.editBox:SetSize(44, 18)
            slider.editBox:ClearAllPoints()
            slider.editBox:SetPoint("TOP", slider, "BOTTOM", 0, -8)
        end

        if slider.minusButton then
            slider.minusButton:SetSize(18, 18)
            if slider.minusButton.text then
                slider.minusButton.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            end
        end

        if slider.plusButton then
            slider.plusButton:SetSize(18, 18)
            if slider.plusButton.text then
                slider.plusButton.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            end
        end
    end

    local function MSUF_FormatOverrideSummary(list)
        if not list or #list == 0 then
            return "Overrides: -", nil
        end
        if #list == 1 then
            return "Overrides: " .. list[1], list[1]
        end
        return "Overrides: " .. list[1] .. " +" .. tostring(#list - 1), table.concat(list, ", ")
    end

    local function MSUF_ApplyOverrideTooltip(fs)
        if not fs then return end
        fs:EnableMouse(true)
        fs:SetScript("OnEnter", function(self)
            if self.MSUF_FullOverrideList and self.MSUF_FullOverrideList ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Overrides", 1, 0.9, 0.4)
                GameTooltip:AddLine(self.MSUF_FullOverrideList, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        fs:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
    end

    -- Two rows: (Name | HP) then (Power | Castbar)
    local colGap = 30

    -- Name
    nameFontSizeSlider = CreateLabeledSlider(
        "MSUF_NameFontSizeSlider", "Name", fontGroup,
        8, 32, 1,
        16, -250 -- will be repositioned below
    )
    nameFontSizeSlider:ClearAllPoints()
    nameFontSizeSlider:SetPoint("TOPLEFT", textSizeHelp, "BOTTOMLEFT", 0, -16)
    MSUF_CompactTextSizeSlider(nameFontSizeSlider, "Name")

    nameFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.nameFontSize = math.floor(value + 0.5)
        MSUF_CallUpdateAllFonts()
    end

    local nameFontOverrideInfo = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    nameFontOverrideInfo:SetPoint("TOP", nameFontSizeSlider.editBox, "BOTTOM", 0, -2)
    nameFontOverrideInfo:SetWidth(120)
    nameFontOverrideInfo:SetJustifyH("CENTER")
    nameFontOverrideInfo:SetText("")
    MSUF_ApplyOverrideTooltip(nameFontOverrideInfo)

    -- HP
    hpFontSizeSlider = CreateLabeledSlider(
        "MSUF_HealthFontSizeSlider", "Health", fontGroup,
        8, 32, 1,
        16, -320 -- will be repositioned below
    )
    hpFontSizeSlider:ClearAllPoints()
    hpFontSizeSlider:SetPoint("TOPLEFT", nameFontSizeSlider, "TOPRIGHT", colGap, 0)
    MSUF_CompactTextSizeSlider(hpFontSizeSlider, "HP")

    hpFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.hpFontSize = math.floor(value + 0.5)
        MSUF_CallUpdateAllFonts()
    end

    local hpFontOverrideInfo = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hpFontOverrideInfo:SetPoint("TOP", hpFontSizeSlider.editBox, "BOTTOM", 0, -2)
    hpFontOverrideInfo:SetWidth(120)
    hpFontOverrideInfo:SetJustifyH("CENTER")
    hpFontOverrideInfo:SetText("")
    MSUF_ApplyOverrideTooltip(hpFontOverrideInfo)

    -- Power
    powerFontSizeSlider = CreateLabeledSlider(
        "MSUF_PowerFontSizeSlider", "Power", fontGroup,
        8, 32, 1,
        16, -390 -- will be repositioned below
    )
    powerFontSizeSlider:ClearAllPoints()
    powerFontSizeSlider:SetPoint("TOPLEFT", nameFontSizeSlider, "BOTTOMLEFT", 0, -84)
    MSUF_CompactTextSizeSlider(powerFontSizeSlider, "Power")

    powerFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.powerFontSize = math.floor(value + 0.5)
        MSUF_CallUpdateAllFonts()
    end

    local powerFontOverrideInfo = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    powerFontOverrideInfo:SetPoint("TOP", powerFontSizeSlider.editBox, "BOTTOM", 0, -2)
    powerFontOverrideInfo:SetWidth(120)
    powerFontOverrideInfo:SetJustifyH("CENTER")
    powerFontOverrideInfo:SetText("")
    MSUF_ApplyOverrideTooltip(powerFontOverrideInfo)

    -- Castbar spell name (global, no per-unit override)
    castbarSpellNameFontSizeSlider = CreateLabeledSlider(
        "MSUF_CastbarSpellNameFontSizeSlider",
        "Castbar",
        fontGroup,
        0, 30, 1,
        16, -460 -- will be repositioned below
    )
    castbarSpellNameFontSizeSlider:ClearAllPoints()
    castbarSpellNameFontSizeSlider:SetPoint("TOPLEFT", powerFontSizeSlider, "TOPRIGHT", colGap, 0)
    MSUF_CompactTextSizeSlider(castbarSpellNameFontSizeSlider, "Castbar")

    castbarSpellNameFontSizeSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.general.castbarSpellNameFontSize = value
        MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
    end

    -- Reset button (placed at the bottom of the block so it doesn't clutter the sliders)
    local resetFontOverridesBtn = CreateFrame("Button", "MSUF_ResetFontOverridesBtn", fontGroup, "UIPanelButtonTemplate")
    resetFontOverridesBtn:SetSize(240, 20)
    resetFontOverridesBtn:SetPoint("TOPLEFT", powerFontOverrideInfo, "BOTTOMLEFT", -10, -14)
    resetFontOverridesBtn:SetText("Reset overrides")
    resetFontOverridesBtn.tooltipText = "Clears per-unit Name/Health/Power and per-castbar Cast Name/Time font size overrides so everything inherits the global defaults again."

    if not StaticPopupDialogs["MSUF_RESET_FONT_OVERRIDES"] then
        StaticPopupDialogs["MSUF_RESET_FONT_OVERRIDES"] = {
            text = "Reset all font size overrides?\n\nThis clears per-unit overrides for Name/Health/Power AND per-castbar overrides for Cast Name/Time so everything inherits the global defaults.",
            button1 = YES,
            button2 = NO,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                EnsureDB()
                local keys = { "player", "target", "targettarget", "focus", "pet", "boss" }
                for _, k in ipairs(keys) do
                    local c = MSUF_DB[k]
                    if c then
                        c.nameFontSize = nil
                        c.hpFontSize = nil
                        c.powerFontSize = nil
                    end
                end
                -- Also clear per-castbar font size overrides (Cast Name / Cast Time)
                MSUF_DB.general = MSUF_DB.general or {}
                local gg = MSUF_DB.general
                local castUnits = { "player", "target", "focus" }
                for _, u in ipairs(castUnits) do
                    local pfx = (type(MSUF_GetCastbarPrefix) == "function") and MSUF_GetCastbarPrefix(u) or nil
                    if pfx then
                        gg[pfx .. "SpellNameFontSize"] = nil
                        gg[pfx .. "TimeFontSize"] = nil
                    end
                end
                gg.bossCastSpellNameFontSize = nil
                gg.bossCastTimeFontSize = nil
                MSUF_CallUpdateAllFonts()
                if ns and ns.MSUF_RefreshAllFrames then
                    ns.MSUF_RefreshAllFrames()
                end
                if type(MSUF_UpdateCastbarVisuals) == "function" then
                    MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
                end
            end,
        }
    end

    resetFontOverridesBtn:SetScript("OnClick", function()
        StaticPopup_Show("MSUF_RESET_FONT_OVERRIDES")
    end)

    local function MSUF_UpdateGlobalTextSizeOverrideInfo()
        local list, summary, full

        -- Name
        list = MSUF_ListFontOverrides("nameFontSize")
        if nameFontOverrideInfo then
            summary, full = MSUF_FormatOverrideSummary(list)
            nameFontOverrideInfo:SetText(summary)
            nameFontOverrideInfo.MSUF_FullOverrideList = full or ""
        end

        -- HP
        list = MSUF_ListFontOverrides("hpFontSize")
        if hpFontOverrideInfo then
            summary, full = MSUF_FormatOverrideSummary(list)
            hpFontOverrideInfo:SetText(summary)
            hpFontOverrideInfo.MSUF_FullOverrideList = full or ""
        end

        -- Power
        list = MSUF_ListFontOverrides("powerFontSize")
        if powerFontOverrideInfo then
            summary, full = MSUF_FormatOverrideSummary(list)
            powerFontOverrideInfo:SetText(summary)
            powerFontOverrideInfo.MSUF_FullOverrideList = full or ""
        end
    end

    fontGroup:HookScript("OnShow", MSUF_UpdateGlobalTextSizeOverrideInfo)
    resetFontOverridesBtn:HookScript("OnClick", function()
        C_Timer.After(0, MSUF_UpdateGlobalTextSizeOverrideInfo)
    end)

    MSUF_UpdateGlobalTextSizeOverrideInfo()

    -- MSUF_FONT_MENU_BOXED_LAYOUT: Modern boxed layout for Fonts tab (no preview yet)
    do
        if not _G["MSUF_FontsMenuPanelLeft"] then
            local whiteTex = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"

            -- Explicitly hide legacy Misc labels/lines so nothing bleeds through the boxed layout
            if miscLeftHeader then miscLeftHeader:Hide() end
            if miscLeftLine then miscLeftLine:Hide() end
            if miscRightHeader then miscRightHeader:Hide() end
            if miscRightLine then miscRightLine:Hide() end
            if indicatorsLabel then indicatorsLabel:Hide() end
            if indicatorsLine then indicatorsLine:Hide() end
            if resIndicatorPosLabel then resIndicatorPosLabel:Hide() end

            local function SetupPanel(panel, titleText)
                if (not panel.SetBackdrop) and BackdropTemplateMixin and Mixin then
                    Mixin(panel, BackdropTemplateMixin)
                end
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
                panel:SetFrameLevel(fontGroup:GetFrameLevel() + 1)

                panel.MSUF_Title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
                panel.MSUF_Title:SetText(titleText)
                panel.MSUF_Title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -12)

                panel.MSUF_Line = panel:CreateTexture(nil, "ARTWORK")
                panel.MSUF_Line:SetColorTexture(1, 1, 1, 0.18)
                panel.MSUF_Line:SetHeight(1)
                panel.MSUF_Line:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -34)
                panel.MSUF_Line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -34)
            end

            local function CreateSectionHeader(panel, globalKey, text)
                local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                fs:SetText(text)
                fs:SetTextColor(1, 0.82, 0, 1)
                _G[globalKey] = fs
                return fs
            end

            local left = CreateFrame("Frame", "MSUF_FontsMenuPanelLeft", fontGroup, "BackdropTemplate")
            -- Slightly taller so the added Name Shortening controls fit cleanly without the panel backdrop ending early.
            left:SetSize(320, 560)
            left:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 0, -110)
            SetupPanel(left, "Font Settings")

            local right = CreateFrame("Frame", "MSUF_FontsMenuPanelRight", fontGroup, "BackdropTemplate")
            -- Taller to accommodate the new Name Shortening mode dropdown + sliders (prevents the right panel border from clipping).
            right:SetSize(320, 560)
            right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)
            SetupPanel(right, "Font color & style")

            CreateSectionHeader(left, "MSUF_FontsMenuSection_Global", "Global font")
            CreateSectionHeader(left, "MSUF_FontsMenuSection_Sizes", "Text sizes")

            CreateSectionHeader(right, "MSUF_FontsMenuSection_Style", "Text style")
            CreateSectionHeader(right, "MSUF_FontsMenuSection_Colors", "Name colors")
            CreateSectionHeader(right, "MSUF_FontsMenuSection_Names", "Name display")
        end

        local left = _G["MSUF_FontsMenuPanelLeft"]
        local right = _G["MSUF_FontsMenuPanelRight"]

        local secGlobal = _G["MSUF_FontsMenuSection_Global"]
        local secSizes = _G["MSUF_FontsMenuSection_Sizes"]

        local secStyle = _G["MSUF_FontsMenuSection_Style"]
        local secColors = _G["MSUF_FontsMenuSection_Colors"]
        local secNames = _G["MSUF_FontsMenuSection_Names"]

        -- Ensure positions (in case menu is rebuilt)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 0, -110)

        right:ClearAllPoints()
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)

        -- Hide legacy headers/lines (replaced by boxed layout)
        if fontTitle then fontTitle:Hide() end
        if globalFontHeader then globalFontHeader:Hide() end
        if globalFontLine then globalFontLine:Hide() end
        if textSizeHeader then textSizeHeader:Hide() end
        if textSizeLine then textSizeLine:Hide() end
        if fontColorHeader then fontColorHeader:Hide() end
        if fontColorLine then fontColorLine:Hide() end

        -- Left panel: Global font
        secGlobal:ClearAllPoints()
        secGlobal:SetPoint("TOPLEFT", left, "TOPLEFT", 14, -44)

        fontDrop:ClearAllPoints()
        fontDrop:SetPoint("TOPLEFT", secGlobal, "BOTTOMLEFT", -14, -8)
        UIDropDownMenu_SetWidth(fontDrop, 260)
        fontDrop._msufButtonWidth = 260
        fontDrop:SetWidth(260)

        -- Left panel: Text sizes
        secSizes:ClearAllPoints()
        secSizes:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 14, -18)

        textSizeHelp:ClearAllPoints()
        textSizeHelp:SetPoint("TOPLEFT", secSizes, "BOTTOMLEFT", 0, -4)
        textSizeHelp:SetWidth(290)

        local colGap = 30

        nameFontSizeSlider:ClearAllPoints()
        nameFontSizeSlider:SetPoint("TOPLEFT", textSizeHelp, "BOTTOMLEFT", 0, -18)

        hpFontSizeSlider:ClearAllPoints()
        hpFontSizeSlider:SetPoint("TOPLEFT", nameFontSizeSlider, "TOPRIGHT", colGap, 0)

        powerFontSizeSlider:ClearAllPoints()
        powerFontSizeSlider:SetPoint("TOPLEFT", nameFontSizeSlider, "BOTTOMLEFT", 0, -84)

        castbarSpellNameFontSizeSlider:ClearAllPoints()
        castbarSpellNameFontSizeSlider:SetPoint("TOPLEFT", powerFontSizeSlider, "TOPRIGHT", colGap, 0)
        resetFontOverridesBtn:ClearAllPoints()
        resetFontOverridesBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 14, 14)
        resetFontOverridesBtn:SetWidth(280)

        -- Right panel: Text style
        secStyle:ClearAllPoints()
        secStyle:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -44)

        boldCheck:ClearAllPoints()
        boldCheck:SetPoint("TOPLEFT", secStyle, "BOTTOMLEFT", -2, -8)

        noOutlineCheck:ClearAllPoints()
        noOutlineCheck:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 0, -10)

        textBackdropCheck:ClearAllPoints()
        textBackdropCheck:SetPoint("TOPLEFT", noOutlineCheck, "BOTTOMLEFT", 0, -10)

        -- Right panel: Name colors
        secColors:ClearAllPoints()
        secColors:SetPoint("TOPLEFT", textBackdropCheck, "BOTTOMLEFT", 2, -18)

        -- Divider line under "Name colors"
        local colorsLine = right.MSUF_SectionLine_Colors
        if not colorsLine then
            colorsLine = right:CreateTexture(nil, "ARTWORK")
            right.MSUF_SectionLine_Colors = colorsLine
            colorsLine:SetColorTexture(1, 1, 1, 0.20)
            colorsLine:SetHeight(1)
        end
        colorsLine:ClearAllPoints()
        colorsLine:SetPoint("TOPLEFT", secColors, "BOTTOMLEFT", -16, -4)
        colorsLine:SetWidth(286)

        nameClassColorCheck:ClearAllPoints()
        nameClassColorCheck:SetPoint("TOPLEFT", colorsLine, "BOTTOMLEFT", 14, -8)

        npcNameRedCheck:ClearAllPoints()
        npcNameRedCheck:SetPoint("TOPLEFT", nameClassColorCheck, "BOTTOMLEFT", 0, -10)

        -- Right panel: Name formatting
        secNames:ClearAllPoints()
        secNames:SetPoint("TOPLEFT", npcNameRedCheck, "BOTTOMLEFT", 2, -18)

        -- Divider line under "Name formatting"
        local namesLine = right.MSUF_SectionLine_Names
        if not namesLine then
            namesLine = right:CreateTexture(nil, "ARTWORK")
            right.MSUF_SectionLine_Names = namesLine
            namesLine:SetColorTexture(1, 1, 1, 0.20)
            namesLine:SetHeight(1)
        end
        namesLine:ClearAllPoints()
        namesLine:SetPoint("TOPLEFT", secNames, "BOTTOMLEFT", -16, -4)
        namesLine:SetWidth(286)

        shortenNamesCheck:ClearAllPoints()
        shortenNamesCheck:SetPoint("TOPLEFT", namesLine, "BOTTOMLEFT", 14, -8)


        -- Keep the new Name Shortening controls inside the boxed right panel (avoid bottom clipping)
        if shortenNameClipSideLabel and shortenNameClipSideLabel.ClearAllPoints then
            shortenNameClipSideLabel:ClearAllPoints()
            shortenNameClipSideLabel:SetPoint("TOPLEFT", shortenNamesCheck, "BOTTOMLEFT", 16, -10)
        end
        if shortenNameClipSideDrop and shortenNameClipSideDrop.ClearAllPoints then
            shortenNameClipSideDrop:ClearAllPoints()
            shortenNameClipSideDrop:SetPoint("TOPLEFT", shortenNameClipSideLabel, "BOTTOMLEFT", -16, -2)
            UIDropDownMenu_SetWidth(shortenNameClipSideDrop, 180)
            shortenNameClipSideDrop._msufButtonWidth = 180
        end
        if shortenNameMaxCharsSlider and shortenNameMaxCharsSlider.ClearAllPoints then
            shortenNameMaxCharsSlider:ClearAllPoints()
            shortenNameMaxCharsSlider:SetPoint("TOPLEFT", shortenNameClipSideDrop, "BOTTOMLEFT", 16, -12)
        end
        if shortenNameFrontMaskSlider and shortenNameFrontMaskSlider.ClearAllPoints then
            shortenNameFrontMaskSlider:ClearAllPoints()
            shortenNameFrontMaskSlider:SetPoint("TOPLEFT", shortenNameMaxCharsSlider, "BOTTOMLEFT", 0, -20)
        end
        local infoBtn = _G and _G["MSUF_ShortenNameInfoButton"]
        if infoBtn and infoBtn.ClearAllPoints and shortenNameFrontMaskSlider then
            infoBtn:ClearAllPoints()
            infoBtn:SetPoint("TOPLEFT", shortenNameFrontMaskSlider, "BOTTOMLEFT", 0, -6)
        end
    end

    miscTitle = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    miscTitle:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -120)
    miscLeftHeader = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    miscLeftHeader:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -160)
    miscLeftHeader:SetText("Mouseover & updates")

    miscLeftLine = miscGroup:CreateTexture(nil, "ARTWORK")
    miscLeftLine:SetColorTexture(1, 1, 1, 0.2)
    miscLeftLine:SetSize(320, 1)
    miscLeftLine:SetPoint("TOPLEFT", miscLeftHeader, "BOTTOMLEFT", -16, -4)

    miscRightHeader = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    miscRightHeader:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 420, -160)
    miscRightHeader:SetText("Unit info panel")

    miscRightLine = miscGroup:CreateTexture(nil, "ARTWORK")
    miscRightLine:SetColorTexture(1, 1, 1, 0.2)
    miscRightLine:SetSize(260, 1)
    miscRightLine:SetPoint("TOPLEFT", miscRightHeader, "BOTTOMLEFT", -16, -4)

    linkEditModesCheck = CreateFrame("CheckButton", "MSUF_LinkEditModesCheck", miscGroup, "InterfaceOptionsCheckButtonTemplate")
    linkEditModesCheck:SetPoint("TOPLEFT", miscLeftLine, "BOTTOMLEFT", 16, -18)
    _G[linkEditModesCheck:GetName() .. "Text"]:SetText("Link Edit Mode Button")
    linkEditModesCheck.tooltipText = "When enabled (default), MSUF Edit Mode is linked with Blizzard Edit Mode. Disable if you want them separate or if Blizzard Edit Mode causes UI errors."
    linkEditModesCheck:SetScript("OnShow", function(self)
        if type(EnsureDB) == "function" then EnsureDB() end
        local enabled = true
        if MSUF_DB and MSUF_DB.general and MSUF_DB.general.linkEditModes == false then
            enabled = false
        end
        self:SetChecked(enabled)
    end)
    linkEditModesCheck:SetScript("OnClick", function(self)
        if type(EnsureDB) == "function" then EnsureDB() end
        if not MSUF_DB then MSUF_DB = {} end
        if not MSUF_DB.general then MSUF_DB.general = {} end
        MSUF_DB.general.linkEditModes = self:GetChecked() and true or false
    end)

    updateThrottleLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    updateThrottleLabel:SetPoint("TOPLEFT", linkEditModesCheck, "BOTTOMLEFT", 0, -18)
    updateThrottleLabel:SetText("Unit update interval (seconds)")

    updateThrottleSlider = CreateFrame("Slider", "MSUF_UpdateIntervalSlider", miscGroup, "OptionsSliderTemplate")
    updateThrottleSlider:SetPoint("TOPLEFT", updateThrottleLabel, "BOTTOMLEFT", 0, -8)
    updateThrottleSlider:SetMinMaxValues(0.01, 0.30)
    updateThrottleSlider:SetValueStep(0.01)
    updateThrottleSlider:SetObeyStepOnDrag(true)
    updateThrottleSlider:SetWidth(200)

    _G[updateThrottleSlider:GetName() .. "Low"]:SetText("0.01")
    _G[updateThrottleSlider:GetName() .. "High"]:SetText("0.30")

    updateThrottleSlider:SetScript("OnShow", function(self)
        EnsureDB()
        v = MSUF_DB.general and MSUF_DB.general.frameUpdateInterval or MSUF_FrameUpdateInterval or 0.05
        if type(v) ~= "number" then v = 0.05 end
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        self:SetValue(v)
    end)

    updateThrottleSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        v = tonumber(value) or 0.05
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        MSUF_DB.general.frameUpdateInterval = v
        MSUF_FrameUpdateInterval = v
    end)

    MSUF_CastbarUpdateLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    MSUF_CastbarUpdateLabel:SetPoint("TOPLEFT", updateThrottleLabel, "BOTTOMLEFT", 0, -40)
    MSUF_CastbarUpdateLabel:SetText("Castbar update")

    MSUF_CastbarUpdateIntervalSlider = CreateFrame("Slider", "MSUF_CastbarUpdateIntervalSlider", miscGroup, "OptionsSliderTemplate")
    MSUF_CastbarUpdateIntervalSlider:SetPoint("TOPLEFT", MSUF_CastbarUpdateLabel, "BOTTOMLEFT", 0, -8)
    MSUF_CastbarUpdateIntervalSlider:SetMinMaxValues(0.01, 0.30)
    MSUF_CastbarUpdateIntervalSlider:SetValueStep(0.01)
    MSUF_CastbarUpdateIntervalSlider:SetObeyStepOnDrag(true)
    MSUF_CastbarUpdateIntervalSlider:SetWidth(200)
    _G[MSUF_CastbarUpdateIntervalSlider:GetName() .. "Low"]:SetText("0.01")
    _G[MSUF_CastbarUpdateIntervalSlider:GetName() .. "High"]:SetText("0.30")

    MSUF_CastbarUpdateIntervalSlider:SetScript("OnShow", function(self)
        EnsureDB()
        v = MSUF_DB.general and MSUF_DB.general.castbarUpdateInterval or MSUF_CastbarUpdateInterval or 0.02
        self:SetValue(v)
        _G[self:GetName() .. "Text"]:SetText(string.format("%.2f", v))
    end)

    MSUF_CastbarUpdateIntervalSlider:SetScript("OnValueChanged", function(self, value)
        EnsureDB()
        v = tonumber(value) or 0.02
        if v < 0.01 then v = 0.01 elseif v > 0.30 then v = 0.30 end
        MSUF_DB.general.castbarUpdateInterval = v
        MSUF_CastbarUpdateInterval = v
        _G[self:GetName() .. "Text"]:SetText(string.format("%.2f", v))
    end)

    -- Indicators
    local indicatorsLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    indicatorsLabel:SetPoint("TOPLEFT", MSUF_CastbarUpdateIntervalSlider, "BOTTOMLEFT", 0, -22)
    indicatorsLabel:SetText("Indicators")
    -- Hidden: boxed misc layout defines its own "Indicators" header.
    indicatorsLabel:Hide()

    local indicatorsLine = miscGroup:CreateTexture(nil, "ARTWORK")
    indicatorsLine:SetColorTexture(1, 0.82, 0, 1)
    indicatorsLine:SetHeight(1)
    indicatorsLine:SetPoint("TOPLEFT", indicatorsLabel, "BOTTOMLEFT", -16, -4)
    indicatorsLine:SetPoint("RIGHT", miscGroup, "RIGHT", -16, 0)
    -- Hidden: boxed misc layout already separates sections via boxed panels.
    indicatorsLine:Hide()

    local resIndicatorCheck = CreateFrame("CheckButton", "MSUF_IncomingResIndicatorCheck", miscGroup, "UICheckButtonTemplate")
    resIndicatorCheck:SetPoint("TOPLEFT", indicatorsLine, "BOTTOMLEFT", 16, -10)
    resIndicatorCheck.text = resIndicatorCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    resIndicatorCheck.text:SetPoint("LEFT", resIndicatorCheck, "RIGHT", 2, 0)
    resIndicatorCheck.text:SetText("Incoming resurrection indicator")

    resIndicatorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.showIncomingResIndicator = self:GetChecked() and true or false
        if _G.MSUF_UnitFrames then
            local pf = _G.MSUF_UnitFrames.player
            local tf = _G.MSUF_UnitFrames.target
            if pf and UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(pf) end
            if tf and UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(tf) end
        end
    end)

    resIndicatorCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        self:SetChecked(g.showIncomingResIndicator ~= false)
    end)

    local resIndicatorPosLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    resIndicatorPosLabel:SetPoint("TOPLEFT", resIndicatorCheck, "BOTTOMLEFT", 0, -14)
    resIndicatorPosLabel:SetText("Incoming resurrection position")

    local resIndicatorPosDrop = CreateFrame("Frame", "MSUF_IncomingResIndicatorPosDrop", miscGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(resIndicatorPosDrop)
    resIndicatorPosDrop:SetPoint("TOPLEFT", resIndicatorPosLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(resIndicatorPosDrop, 180)

    local function ResIndicatorPos_OnClick(self)
        EnsureDB()
        MSUF_DB.general.incomingResIndicatorPos = self.value
        UIDropDownMenu_SetSelectedValue(resIndicatorPosDrop, self.value)
        UIDropDownMenu_SetText(resIndicatorPosDrop, self.text)

        if _G.MSUF_UnitFrames then
            local pf = _G.MSUF_UnitFrames.player
            local tf = _G.MSUF_UnitFrames.target
            if pf and UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(pf) end
            if tf and UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(tf) end
        end
    end

    UIDropDownMenu_Initialize(resIndicatorPosDrop, function(self, level)
        if not level then return end
        EnsureDB()
        local g = MSUF_DB.general or {}
        local current = g.incomingResIndicatorPos or "TOPRIGHT"

        local function AddOption(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = function(btn)
                btn.text = text
                btn.value = value
                ResIndicatorPos_OnClick(btn)
            end
            info.checked = (current == value)
            UIDropDownMenu_AddButton(info, level)
        end

        AddOption("Top left", "TOPLEFT")
        AddOption("Top right", "TOPRIGHT")
        AddOption("Bottom left", "BOTTOMLEFT")
        AddOption("Bottom right", "BOTTOMRIGHT")
    end)

    resIndicatorPosDrop:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local current = g.incomingResIndicatorPos or "TOPRIGHT"
        local label = "Top right"
        if current == "TOPLEFT" then label = "Top left"
        elseif current == "BOTTOMLEFT" then label = "Bottom left"
        elseif current == "BOTTOMRIGHT" then label = "Bottom right" end
        UIDropDownMenu_SetSelectedValue(self, current)
        UIDropDownMenu_SetText(self, label)
    end)

infoTooltipDisableCheck = CreateFrame("CheckButton", "MSUF_InfoTooltipDisableCheck", miscGroup, "UICheckButtonTemplate")
infoTooltipDisableCheck:SetPoint("TOPLEFT", miscRightLine, "BOTTOMLEFT", 16, -16)

infoTooltipDisableCheck.text = infoTooltipDisableCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoTooltipDisableCheck.text:SetPoint("LEFT", infoTooltipDisableCheck, "RIGHT", 2, 0)
infoTooltipDisableCheck.text:SetText("Disable MSUF unit info panel tooltips")

    infoTooltipDisableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.disableUnitInfoTooltips = self:GetChecked() and true or false
    end)

    infoTooltipDisableCheck:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        self:SetChecked(g.disableUnitInfoTooltips and true or false)
    end)

    infoTooltipPosLabel = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    infoTooltipPosLabel:SetPoint("TOPLEFT", infoTooltipDisableCheck, "BOTTOMLEFT", 0, -16)
    infoTooltipPosLabel:SetText("MSUF unit info panel position")

    infoTooltipPosDrop = CreateFrame("Frame", "MSUF_InfoTooltipPosDropdown", miscGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(infoTooltipPosDrop)
    infoTooltipPosDrop:SetPoint("TOPLEFT", infoTooltipPosLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(infoTooltipPosDrop, 180)

    local function InfoTooltipPosDropdown_OnClick(self)
        EnsureDB()
        UIDropDownMenu_SetSelectedValue(infoTooltipPosDrop, self.value)
        MSUF_DB.general.unitInfoTooltipStyle = self.value
    end

    local function InfoTooltipPosDropdown_Initialize(self, level)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.unitInfoTooltipStyle or "classic"

        info = UIDropDownMenu_CreateInfo()
        info.func = InfoTooltipPosDropdown_OnClick

        info.text = "Blizzard Classic"
        info.value = "classic"
        info.checked = (current == "classic")
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.func = InfoTooltipPosDropdown_OnClick
        info.text = "Modern (under cursor)"
        info.value = "modern"
        info.checked = (current == "modern")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(infoTooltipPosDrop, InfoTooltipPosDropdown_Initialize)

    infoTooltipPosDrop:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.unitInfoTooltipStyle or "classic"
        UIDropDownMenu_SetSelectedValue(self, current)
        if current == "modern" then
            UIDropDownMenu_SetText(self, "Modern (under cursor)")
        else
            UIDropDownMenu_SetText(self, "Blizzard Classic")
        end
    end)

    blizzUFCheck = CreateFrame("CheckButton", "MSUF_DisableBlizzUFCheck", miscGroup, "UICheckButtonTemplate")
    blizzUFCheck:SetPoint("TOPLEFT", infoTooltipPosDrop, "BOTTOMLEFT", 16, -24)

    blizzUFCheck.text = blizzUFCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    blizzUFCheck.text:SetPoint("LEFT", blizzUFCheck, "RIGHT",0, 0)
    blizzUFCheck.text:SetText("Disable Blizzard unitframes")

    blizzUFCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.disableBlizzardUnitFrames = self:GetChecked() and true or false
        print("|cffffd700MSUF:|r Changing Blizzard unitframes visibility requires a /reload.")
    end)

    -- Hard-hide Blizzard PlayerFrame (compatibility OFF; may break addons that parent resource bars to PlayerFrame)
    if not StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] then
        StaticPopupDialogs["MSUF_RELOAD_PLAYERFRAME_HIDE_MODE"] = {
            text = "This changes how MSUF hides the Blizzard PlayerFrame.\n\nOFF: Compatibility mode (keeps PlayerFrame alive as hidden parent for resource bar addons).\nON: Hard-hide mode (fully hides PlayerFrame; may break some resource bar addons).\n\nA UI reload is required.",
            button1 = RELOADUI,
            button2 = CANCEL,
            OnAccept = function() ReloadUI() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    local hardKillPFCheck = CreateFrame("CheckButton", "MSUF_HardKillPlayerFrameCheck", miscGroup, "UICheckButtonTemplate")
    hardKillPFCheck:SetPoint("TOPLEFT", blizzUFCheck, "BOTTOMLEFT", 0, -10)

    hardKillPFCheck.text = hardKillPFCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hardKillPFCheck.text:SetPoint("LEFT", hardKillPFCheck, "RIGHT", 0, 0)
    hardKillPFCheck.text:SetText("Fully Hide Blizzard PlayerFrame - Turn off for resource bar compatibility")

    if MSUF_StyleToggleText then MSUF_StyleToggleText(hardKillPFCheck) end
    if MSUF_StyleCheckmark then MSUF_StyleCheckmark(hardKillPFCheck) end

    hardKillPFCheck:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide Blizzard PlayerFrame (Turn off for other addon compatibility)", 1, 0.9, 0.4)
        GameTooltip:AddLine("OFF: Keeps PlayerFrame alive as a hidden parent.", 0.95, 0.95, 0.95, true)
        GameTooltip:AddLine("ON: Fully hides PlayerFrame (may break some resource bar addons).", 1, 0.82, 0.2, true)
        GameTooltip:AddLine("Requires a UI reload.", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    hardKillPFCheck:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    hardKillPFCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.hardKillBlizzardPlayerFrame = self:GetChecked() and true or false
        StaticPopup_Show("MSUF_RELOAD_PLAYERFRAME_HIDE_MODE")
    end)

    hardKillPFCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        self:SetChecked(g.hardKillBlizzardPlayerFrame == true)

        local enabled = (g.disableBlizzardUnitFrames ~= false)
        if self.SetEnabled then self:SetEnabled(enabled) end
        self:SetAlpha(enabled and 1 or 0.4)
    end)

    blizzUFCheck:SetScript("OnShow", function(self)
        EnsureDB()
        g = MSUF_DB.general or {}
        self:SetChecked(g.disableBlizzardUnitFrames ~= false)
    end)

    -- Minimap icon toggle (backend in MidnightSimpleUnitFrames_MinimapButton.lua)
    minimapIconCheck = CreateFrame("CheckButton", "MSUF_MinimapIconCheck", miscGroup, "InterfaceOptionsCheckButtonTemplate")
    -- Extra vertical spacing to avoid overlapping the PlayerFrame hide-mode toggle.
    minimapIconCheck:SetPoint("TOPLEFT", hardKillPFCheck, "BOTTOMLEFT", 0, -12)
    if minimapIconCheck.Text then
        minimapIconCheck.Text:SetText("Show MSUF minimap icon")
    elseif minimapIconCheck.text and minimapIconCheck.text.SetText then
        minimapIconCheck.text:SetText("Show MSUF minimap icon")
    end

    minimapIconCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local enabled = self:GetChecked() and true or false
        MSUF_DB.general.showMinimapIcon = enabled

        if _G.MSUF_SetMinimapIconEnabled then
            _G.MSUF_SetMinimapIconEnabled(enabled)
        else
            -- Safe fallback if the minimap icon file (LDB/LibDBIcon) isn't loaded yet.
            MSUF_DB.general.minimapIconDB = MSUF_DB.general.minimapIconDB or {}
            MSUF_DB.general.minimapIconDB.hide = (not enabled) and true or false
        end
    end)

    minimapIconCheck:SetScript("OnShow", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local enabled = (g.showMinimapIcon ~= false)
        self:SetChecked(enabled and true or false)
    end)




    -- Misc menu style: boxed layout (to match Bars/Fonts)
    do
        if miscGroup and not miscGroup._msufMiscBoxedLayoutV1 then
            miscGroup._msufMiscBoxedLayoutV1 = true

            -- Hide old headers/lines/labels that were anchored directly to miscGroup
            local hideText = {
                ["Mouseover & updates"] = true,
                ["Unit info panel"] = true,
                ["Indicators"] = true,
                ["Unit update interval (seconds)"] = true,
                ["Castbar update"] = true,
                ["Unit info panel position"] = true,
                ["MSUF unit info panel position"] = true,
                ["Disable MSUF unit info panel tooltips"] = true,
                ["Disable Blizzard unitframes"] = true,
                ["Incoming resurrection indicator ()"] = true,
                ["Incoming resurrection position"] = true,
            }

            for i = 1, miscGroup:GetNumRegions() do
                local r = select(i, miscGroup:GetRegions())
                if r and r.IsObjectType then
                    if r:IsObjectType("FontString") then
                        local t = r:GetText()
                        if t and hideText[t] then
                            r:Hide()
                        end
                    elseif r:IsObjectType("Texture") then
                        -- Likely old divider lines
                        local w, h = r:GetSize()
                        local a = r:GetAlpha()
                        if h and h <= 2 and w and w >= 200 then
                            r:Hide()
                        end
                    end
                end
            end

            -- Panel helpers (same as Bars boxed layout)
            local function SetupPanel(panel, titleText)
                -- Some frames may be created without BackdropTemplate; mix it in at runtime.
                if (not panel.SetBackdrop) and BackdropTemplateMixin and Mixin then
                    Mixin(panel, BackdropTemplateMixin)
                end
                if panel.SetBackdrop then
                    panel:SetBackdrop({
                        bgFile = "Interface\\Buttons\\WHITE8x8",
                        edgeFile = "Interface\\Buttons\\WHITE8x8",
                        edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 },
                    })
                    panel:SetBackdropColor(0, 0, 0, 0.20)
                    panel:SetBackdropBorderColor(1, 1, 1, 0.12)
                end

                local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                header:SetText(titleText or "")
                header:SetTextColor(1, 0.82, 0)
                header:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -14)

                local line = panel:CreateTexture(nil, "ARTWORK")
                line:SetColorTexture(1, 1, 1, 0.08)
                line:SetHeight(1)
                line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
                line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)

                panel._msufHeader = header
                panel._msufHeaderLine = line
                return header, line
            end

            local function MakeLabel(parent, text, anchor, rel, x, y)
                local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                fs:SetText(text or "")
                fs:SetTextColor(1, 0.82, 0)
                if anchor and rel then
                    fs:SetPoint(anchor, rel, x or 0, y or 0)
                end
                return fs
            end

            -- Normalize all Misc toggles to the same checkbox size and label alignment.
            -- Reference size = "Disable Blizzard unitframes" (blizzUFDisable). This avoids
            -- mixed templates producing different checkbox box sizes (and prevents clipping).
            local function MSUF_GetMiscToggleTargetSize()
                local w, h
                local ref = _G.MSUF_DisableBlizzUFCheck
                if ref and ref.GetSize then
                    w, h = ref:GetSize()
                end
                if type(w) ~= "number" or w <= 0 then w = 24 end
                if type(h) ~= "number" or h <= 0 then h = 24 end
                return w, h
            end

            local function MSUF_GetMiscToggleTargetFont()
                local ref = _G.MSUF_DisableBlizzUFCheck
                local rfs = ref and (ref.text or ref.Text)
                if (not rfs) and ref and ref.GetName and ref:GetName() and _G then
                    rfs = _G[ref:GetName() .. "Text"]
                end
                if rfs and rfs.GetFont then
                    local font, size, flags = rfs:GetFont()
                    if font and size then
                        return font, size, flags
                    end
                end
                if rfs and rfs.GetFontObject then
                    return nil, nil, nil, rfs:GetFontObject()
                end
            end

            local function StyleCheckbox(cb)
                if not cb then return end

                -- Match checkbox size.
                local tw, th = MSUF_GetMiscToggleTargetSize()
                if cb.SetSize then
                    cb:SetSize(tw, th)
                elseif cb.SetHeight then
                    cb:SetHeight(th)
                end

                -- Expand click area slightly to the right.
                if cb.SetHitRectInsets then
                    cb:SetHitRectInsets(0, -10, 0, 0)
                end

                -- Normalize label placement (avoid template differences).
                local fs = cb.text or cb.Text
                if (not fs) and cb.GetName and cb:GetName() and _G then
                    fs = _G[cb:GetName() .. "Text"]
                end
                if fs and fs.ClearAllPoints and fs.SetPoint then
                    fs:ClearAllPoints()
                    fs:SetPoint("LEFT", cb, "RIGHT", 0, 0)
                end

                -- Match label font (some templates default to smaller font objects).
                local font, size, flags, fo = MSUF_GetMiscToggleTargetFont()
                if fs then
                    if font and size and fs.SetFont then
                        fs:SetFont(font, size, flags)
                    elseif fo and fs.SetFontObject then
                        fs:SetFontObject(fo)
                    end
                end
            end

            -- Create panels
            local leftPanel = CreateFrame("Frame", nil, miscGroup, "BackdropTemplate")
            leftPanel:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 0, -110)
            leftPanel:SetSize(330, 330)
            SetupPanel(leftPanel, "Updates")

            local rightPanel = CreateFrame("Frame", nil, miscGroup, "BackdropTemplate")
            rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
            rightPanel:SetSize(330, 330)
            SetupPanel(rightPanel, "Unit info panel")
            -- Panel width helpers (avoid nil math when adding divider lines)
            local leftW  = 330
            local rightW = 330

            -- Section divider between top blocks and Indicators (matches other menus)
  local sectionDivider = miscGroup:CreateTexture(nil, "ARTWORK")
  sectionDivider:SetColorTexture(1, 1, 1, 0.10)
  sectionDivider:SetHeight(1)
  sectionDivider:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -8)
  sectionDivider:SetPoint("TOPRIGHT", rightPanel, "BOTTOMRIGHT", 0, -8)
  -- Box borders already separate sections; remove this extra horizontal line.
  sectionDivider:Hide()

local bottomPanel = CreateFrame("Frame", nil, miscGroup, "BackdropTemplate")
            bottomPanel:SetPoint("TOPLEFT", leftPanel, "BOTTOMLEFT", 0, -16)
            bottomPanel:SetPoint("TOPRIGHT", rightPanel, "BOTTOMRIGHT", 0, -16)
            bottomPanel:SetHeight(180)
            SetupPanel(bottomPanel, "Indicators")

  -- Misc menu should be clean (no extra boxed borders; use only header lines + dividers)
  local function ClearPanelBackdrop(p)
    if p and p.SetBackdropColor then
      p:SetBackdropColor(0, 0, 0, 0)
      p:SetBackdropBorderColor(0, 0, 0, 0)
    end
  end
  ClearPanelBackdrop(leftPanel)
  ClearPanelBackdrop(rightPanel)
  ClearPanelBackdrop(bottomPanel)

            -- Vertical divider inside indicators panel

  -- Shared center divider (matches top + bottom columns)
  local centerDivider = miscGroup:CreateTexture(nil, "ARTWORK")
  centerDivider:SetColorTexture(1, 1, 1, 0.10)
  centerDivider:SetWidth(1)
  centerDivider:SetPoint("TOP", leftPanel, "TOPRIGHT", 0, -46)
  centerDivider:SetPoint("BOTTOM", bottomPanel, "BOTTOMLEFT", leftW, 12)

            -- Grab existing widgets
            local linkCheck = _G.MSUF_LinkEditModesCheck
            local updateSlider = _G.MSUF_UpdateIntervalSlider
            local castbarUpdateSlider = _G.MSUF_CastbarUpdateIntervalSlider


            -- UFCore spike-cap tuning (advanced)
            local ufcoreBudgetSlider = _G.MSUF_UFCoreFlushBudgetSlider
            if not ufcoreBudgetSlider then
                ufcoreBudgetSlider = CreateFrame("Slider", "MSUF_UFCoreFlushBudgetSlider", miscGroup, "OptionsSliderTemplate")
                ufcoreBudgetSlider:SetMinMaxValues(0.5, 5.0)
                ufcoreBudgetSlider:SetValueStep(0.1)
                ufcoreBudgetSlider:SetObeyStepOnDrag(true)
                ufcoreBudgetSlider:SetWidth(200)
                _G[ufcoreBudgetSlider:GetName() .. "Low"]:SetText("0.5")
                _G[ufcoreBudgetSlider:GetName() .. "High"]:SetText("5.0")
                ufcoreBudgetSlider.tooltipText = "Limits UFCore work per frame (ms). Lower = smoother (less spikes), higher = more immediate updates."

                ufcoreBudgetSlider:SetScript("OnShow", function(self)
                    if EnsureDB then EnsureDB() end
                    local g = (MSUF_DB and MSUF_DB.general) or {}
                    local v = g.ufcoreFlushBudgetMs
                    if type(v) ~= "number" then v = 2.0 end
                    if v < 0.5 then v = 0.5 elseif v > 5.0 then v = 5.0 end
                    self:SetValue(v)
                    _G[self:GetName() .. "Text"]:SetText(string.format("%.1f ms", v))
                end)

                ufcoreBudgetSlider:SetScript("OnValueChanged", function(self, value)
                    if EnsureDB then EnsureDB() end
                    local v = tonumber(value) or 2.0
                    if v < 0.5 then v = 0.5 elseif v > 5.0 then v = 5.0 end
                    MSUF_DB.general.ufcoreFlushBudgetMs = v
                    _G[self:GetName() .. "Text"]:SetText(string.format("%.1f ms", v))
                end)
            end

            local ufcoreUrgentSlider = _G.MSUF_UFCoreUrgentCapSlider
            if not ufcoreUrgentSlider then
                ufcoreUrgentSlider = CreateFrame("Slider", "MSUF_UFCoreUrgentCapSlider", miscGroup, "OptionsSliderTemplate")
                ufcoreUrgentSlider:SetMinMaxValues(1, 50)
                ufcoreUrgentSlider:SetValueStep(1)
                ufcoreUrgentSlider:SetObeyStepOnDrag(true)
                ufcoreUrgentSlider:SetWidth(200)
                _G[ufcoreUrgentSlider:GetName() .. "Low"]:SetText("1")
                _G[ufcoreUrgentSlider:GetName() .. "High"]:SetText("50")
                ufcoreUrgentSlider.tooltipText = "Caps urgent unit updates per flush. Lower = smaller spikes, higher = faster catch-up."

                ufcoreUrgentSlider:SetScript("OnShow", function(self)
                    if EnsureDB then EnsureDB() end
                    local g = (MSUF_DB and MSUF_DB.general) or {}
                    local v = g.ufcoreUrgentMaxPerFlush
                    if type(v) ~= "number" then v = 10 end
                    v = math.floor(v + 0.5)
                    if v < 1 then v = 1 elseif v > 50 then v = 50 end
                    self:SetValue(v)
                    _G[self:GetName() .. "Text"]:SetText(tostring(v))
                end)

                ufcoreUrgentSlider:SetScript("OnValueChanged", function(self, value)
                    if EnsureDB then EnsureDB() end
                    local v = tonumber(value) or 10
                    v = math.floor(v + 0.5)
                    if v < 1 then v = 1 elseif v > 50 then v = 50 end
                    MSUF_DB.general.ufcoreUrgentMaxPerFlush = v
                    _G[self:GetName() .. "Text"]:SetText(tostring(v))
                end)
            end

            local infoTooltipDisable = _G.MSUF_InfoTooltipDisableCheck
            local infoTooltipPosDrop = _G.MSUF_InfoTooltipPosDropdown
            local blizzUFDisable = _G.MSUF_DisableBlizzUFCheck
            local minimapIconCheck = _G.MSUF_MinimapIconCheck

            local resCheck = _G.MSUF_IncomingResIndicatorCheck
            local resPosDrop = _G.MSUF_IncomingResIndicatorPosDrop
            -- LEFT: Updates
            -- Link Edit Mode Button is now placed under the Blizzard frames section (right column)

            if updateSlider then
                updateSlider:ClearAllPoints()
                updateSlider:SetParent(leftPanel)

                local lbl = MakeLabel(leftPanel, "Unit update interval (seconds)", "TOPLEFT", leftPanel, 14, -50)
                updateSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                updateSlider:SetWidth(270)
            end

            if castbarUpdateSlider then
                castbarUpdateSlider:ClearAllPoints()
                castbarUpdateSlider:SetParent(leftPanel)

                local rel = updateSlider or leftPanel
                local lbl = MakeLabel(leftPanel, "Castbar update", "TOPLEFT", rel, (rel == leftPanel and 14) or 0, (rel == leftPanel and -130) or -36)
                if rel ~= leftPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                castbarUpdateSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                castbarUpdateSlider:SetWidth(270)
            end

            if ufcoreBudgetSlider then
                ufcoreBudgetSlider:ClearAllPoints()
                ufcoreBudgetSlider:SetParent(leftPanel)

                local rel = castbarUpdateSlider or updateSlider or leftPanel
                local lbl = MakeLabel(leftPanel, "UFCore flush budget", "TOPLEFT", rel, (rel == leftPanel and 14) or 0, (rel == leftPanel and -130) or -36)
                if rel ~= leftPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                ufcoreBudgetSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                ufcoreBudgetSlider:SetWidth(270)
            end

            if ufcoreUrgentSlider then
                ufcoreUrgentSlider:ClearAllPoints()
                ufcoreUrgentSlider:SetParent(leftPanel)

                local rel = ufcoreBudgetSlider or castbarUpdateSlider or updateSlider or leftPanel
                local lbl = MakeLabel(leftPanel, "UFCore urgent cap", "TOPLEFT", rel, (rel == leftPanel and 14) or 0, (rel == leftPanel and -130) or -36)
                if rel ~= leftPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                ufcoreUrgentSlider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -10)
                ufcoreUrgentSlider:SetWidth(270)
            end

            -- RIGHT: Unit info panel
            if infoTooltipDisable then
                infoTooltipDisable:ClearAllPoints()
                infoTooltipDisable:SetParent(rightPanel)
                infoTooltipDisable:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 14, -50)
                StyleCheckbox(infoTooltipDisable)
            end

            if infoTooltipPosDrop then
                infoTooltipPosDrop:ClearAllPoints()
                infoTooltipPosDrop:SetParent(rightPanel)

                local rel = infoTooltipDisable or rightPanel
                local lbl = MakeLabel(rightPanel, "MSUF unit info panel position", "TOPLEFT", rel, 0, (rel == rightPanel and -50) or -28)
                if rel ~= rightPanel then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -16)
                end
                infoTooltipPosDrop:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -16, -8)
            end

            if blizzUFDisable then
                blizzUFDisable:ClearAllPoints()
                blizzUFDisable:SetParent(rightPanel)

                local rel = infoTooltipPosDrop or infoTooltipDisable or rightPanel
                -- Subheader + divider line (style-only; wiring comes later)
                if not rightPanel._msufBlizzHeader then
                    rightPanel._msufBlizzHeader = MakeLabel(rightPanel, "Blizzard frames", "TOPLEFT", rel, 0, -35)
                    rightPanel._msufBlizzLine = rightPanel:CreateTexture(nil, "OVERLAY")
                    rightPanel._msufBlizzLine:SetColorTexture(1, 1, 1, 0.10)
                    rightPanel._msufBlizzLine:SetHeight(1)
                    rightPanel._msufBlizzLine:SetPoint("TOPLEFT", rightPanel._msufBlizzHeader, "BOTTOMLEFT", 0, -6)
                    rightPanel._msufBlizzLine:SetWidth(rightW - 28)
                else
                    rightPanel._msufBlizzHeader:ClearAllPoints()
                    rightPanel._msufBlizzHeader:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -26)
                    rightPanel._msufBlizzLine:ClearAllPoints()
                    rightPanel._msufBlizzLine:SetPoint("TOPLEFT", rightPanel._msufBlizzHeader, "BOTTOMLEFT", 0, -6)
                    rightPanel._msufBlizzLine:SetWidth(rightW - 28)
                end

                blizzUFDisable:SetPoint("TOPLEFT", rightPanel._msufBlizzLine, "BOTTOMLEFT", 0, -10)
                StyleCheckbox(blizzUFDisable)
            end

if minimapIconCheck then
    minimapIconCheck:ClearAllPoints()
    minimapIconCheck:SetParent(rightPanel)

    -- PlayerFrame hide-mode toggle belongs in the Blizzard frames section.
    -- Anchor minimap toggle underneath it with a little extra spacing to avoid overlap.
    if hardKillPFCheck then
        hardKillPFCheck:ClearAllPoints()
        hardKillPFCheck:SetParent(rightPanel)

        if blizzUFDisable then
            hardKillPFCheck:SetPoint("TOPLEFT", blizzUFDisable, "BOTTOMLEFT", 0, -10)
        else
            local rel = rightPanel._msufBlizzLine or rightPanel
            hardKillPFCheck:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -10)
        end
        StyleCheckbox(hardKillPFCheck)
    end

    local anchor = hardKillPFCheck or blizzUFDisable or (rightPanel._msufBlizzLine or rightPanel)
    minimapIconCheck:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    StyleCheckbox(minimapIconCheck)

    -- Place Link Edit Mode Button under the minimap icon toggle (fits nicer here)
    if linkCheck then
        linkCheck:ClearAllPoints()
        linkCheck:SetParent(rightPanel)
        linkCheck:SetPoint("TOPLEFT", minimapIconCheck, "BOTTOMLEFT", 0, -12)
        StyleCheckbox(linkCheck)
    end


end

            -- BOTTOM: Indicators
            local leftX = 14
            local rightX = 14

            -- Left column: Incoming resurrection
            local leftAnchor = bottomPanel
            local leftHeader = MakeLabel(bottomPanel, "Incoming resurrection", "TOPLEFT", bottomPanel, leftX, -34)
            local leftLine = bottomPanel:CreateTexture(nil, "ARTWORK")
            leftLine:SetColorTexture(1, 1, 1, 0.10)
            leftLine:SetHeight(1)
            leftLine:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -8)
            leftLine:SetPoint("TOPRIGHT", bottomPanel, "TOPLEFT", leftW - 14, -42)

            if resCheck then
                resCheck:ClearAllPoints()
                resCheck:SetParent(bottomPanel)
                resCheck:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -10)
                StyleCheckbox(resCheck)
            end

            if resPosDrop then
                resPosDrop:ClearAllPoints()
                resPosDrop:SetParent(bottomPanel)

                local rel = resCheck or leftHeader
                local lbl = MakeLabel(bottomPanel, "Incoming resurrection position", "TOPLEFT", rel, 0, -18)
                if rel ~= leftHeader then
                    lbl:ClearAllPoints()
                    lbl:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, -10)
                end
                resPosDrop:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -16, -8)
            end

            -- Right column: Status indicators (placeholders, wiring later)
            local rightHeader = MakeLabel(bottomPanel, "Status indicators", "TOPLEFT", bottomPanel, leftW + 14, -34)
            rightHeader:ClearAllPoints()
            rightHeader:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", leftW + 14, -34)
            local rightLine = bottomPanel:CreateTexture(nil, "ARTWORK")
            rightLine:SetColorTexture(1, 1, 1, 0.10)
            rightLine:SetHeight(1)
            rightLine:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, -8)
            rightLine:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", -14, -42)

            local function GetStatusDB()
                EnsureDB()
                MSUF_DB.general = MSUF_DB.general or {}
                MSUF_DB.general.statusIndicators = MSUF_DB.general.statusIndicators or {}
                return MSUF_DB.general.statusIndicators
            end

            local function MakeStatusCB(key, label, yOff)
                local cb = CreateFrame("CheckButton", nil, bottomPanel, "InterfaceOptionsCheckButtonTemplate")
                cb:SetPoint("TOPLEFT", rightHeader, "BOTTOMLEFT", 0, yOff)
                cb.Text:SetText(label)
                StyleCheckbox(cb)

                cb:SetScript("OnShow", function(self)
                    local db = GetStatusDB()
                    local v = db[key]
                    if v == nil then v = false end
                    self:SetChecked(v)
                end)

                cb:SetScript("OnClick", function(self)
                    local db = GetStatusDB()
                    db[key] = self:GetChecked() and true or false
                    if _G.MSUF_RefreshStatusIndicators then
                        _G.MSUF_RefreshStatusIndicators()
                    end
                end)

                return cb
            end

            -- Space checkboxes based on the actual checkbox height to prevent overlap/clipping.
            local _, th = MSUF_GetMiscToggleTargetSize()
            local step = (type(th) == "number" and th > 0) and (th + 6) or 30
            local y0 = -10
            local cbAFK   = MakeStatusCB("showAFK",   "Show AFK",   y0)
            local cbDND   = MakeStatusCB("showDND",   "Show DND",   y0 - step)
            local cbDead  = MakeStatusCB("showDead",  "Show Dead",  y0 - (step * 2))
            local cbGhost = MakeStatusCB("showGhost", "Show Ghost", y0 - (step * 3))

            bottomPanel._msufStatusCBs = { cbAFK, cbDND, cbDead, cbGhost }
        end
    end

local function MSUF_PlayerCastbar_HideIfNoLongerCasting(timer)
    self = timer and timer.msuCastbarFrame
    if not self or not self.unit then
        return
    end

    castName = UnitCastingInfo(self.unit)
    chanName = UnitChannelInfo(self.unit)

    if castName or chanName then
        if MSUF_PlayerCastbar_Cast then
            MSUF_PlayerCastbar_Cast(self)
        end
        return
    end

    self:SetScript("OnUpdate", nil)
    if self.timeText then
        MSUF_SetTextIfChanged(self.timeText, "")
    end
    if MSUF_UnregisterCastbar then MSUF_UnregisterCastbar(self) end
    self:Hide()
end
    castbarTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    castbarTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -120)

-- Castbar submenu trimmed (UI cleanup):
-- Removed: BACK, Player, Target, Boss subpages
-- Kept: Focus Kick options (toggle via button) + Castbar Edit Mode button
castbarFocusButton = CreateFrame("Button", "MSUF_CastbarFocusButton", castbarGroup, "UIPanelButtonTemplate")
castbarFocusButton:SetSize(120, 22)
castbarFocusButton:ClearAllPoints()
castbarFocusButton:SetPoint("TOPLEFT", castbarGroup, "TOPLEFT", 16, -150)
castbarFocusButton:SetText("Focus Kick")
if MSUF_SkinMidnightActionButton then
    MSUF_SkinMidnightActionButton(castbarFocusButton)
elseif MSUF_SkinMidnightTabButton then
    -- fallback: keep it in the same family as our tabs
    MSUF_SkinMidnightTabButton(castbarFocusButton)
end
local fkfs = castbarFocusButton.GetFontString and castbarFocusButton:GetFontString() or nil
if fkfs and fkfs.SetTextColor then
    fkfs:SetTextColor(1, 0.82, 0)
end

function MSUF_SetActiveCastbarSubPage(page)
    if castbarEnemyGroup then castbarEnemyGroup:Hide() end
    if castbarPlayerGroup then castbarPlayerGroup:Hide() end
    if castbarTargetGroup then castbarTargetGroup:Hide() end
    if castbarBossGroup then castbarBossGroup:Hide() end
    if castbarFocusGroup then castbarFocusGroup:Hide() end

    if page == "focus" then
        if castbarFocusGroup then castbarFocusGroup:Show() end
    else
        if castbarEnemyGroup then castbarEnemyGroup:Show() end
    end
end

_G.MSUF_SetActiveCastbarSubPage = MSUF_SetActiveCastbarSubPage

-- Default: show general castbar options
MSUF_SetActiveCastbarSubPage("enemy")

-- Toggle focus kick options without needing a BACK button
castbarFocusButton:SetScript("OnClick", function()
    if castbarFocusGroup and castbarFocusGroup:IsShown() then
        MSUF_SetActiveCastbarSubPage("enemy")
    else
        MSUF_SetActiveCastbarSubPage("focus")
    end
end)

    if not _G["MSUF_FocusKickHeaderRight"] then
        local fkHeader = castbarFocusGroup:CreateFontString("MSUF_FocusKickHeaderRight", "ARTWORK", "GameFontNormal")
        fkHeader:SetPoint("TOPLEFT", castbarFocusGroup, "TOPLEFT", 300, -220)
        fkHeader:SetText("Focus Kick Icon")
    end

    if MSUF_InitFocusKickIconOptions then
        MSUF_InitFocusKickIconOptions()
    end

    castbarGeneralTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarGeneralTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -170)

    castbarGeneralLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarGeneralLine:SetColorTexture(1, 1, 1, 0.15)
    castbarGeneralLine:SetHeight(1)
    castbarGeneralLine:SetPoint("TOPLEFT", castbarGeneralTitle, "BOTTOMLEFT", 0, -4)
    castbarGeneralLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)

    castbarInterruptShakeCheck = CreateLabeledCheckButton(
        "MSUF_CastbarInterruptShakeCheck",
        "Shake on interrupt",
        castbarEnemyGroup,
        16, -200
    )

local function MSUF_SyncCastbarsTabToggles()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}

    -- Shake on interrupt
    local shakeEnabled = (g.castbarInterruptShake == true)
    if castbarInterruptShakeCheck then
        castbarInterruptShakeCheck:SetChecked(shakeEnabled)
    end
    if castbarShakeIntensitySlider then
        local v = tonumber(g.castbarShakeStrength)
        if type(v) ~= "number" then v = 8 end
        if v < 0 then v = 0 elseif v > 30 then v = 30 end
                MSUF_SetLabeledSliderValue(castbarShakeIntensitySlider, v)
        MSUF_SetLabeledSliderEnabled(castbarShakeIntensitySlider, shakeEnabled)
    end

    -- Unified fill direction
    local unifiedDir = (g.castbarUnifiedDirection == true)
    if castbarUnifiedDirCheck then
        castbarUnifiedDirCheck:SetChecked(unifiedDir)
    end
    if castbarFillDirDrop then
        local dir = g.castbarFillDirection or "RTL"
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, dir) end
        if UIDropDownMenu_SetText then
            if dir == "LTR" then
                UIDropDownMenu_SetText(castbarFillDirDrop, "Left to right")
            else
                UIDropDownMenu_SetText(castbarFillDirDrop, "Right to left (default)")
            end
        end
        -- NOTE: "Always use fill direction" is independent from the dropdown. Keep dropdown active at all times.
        MSUF_SetDropDownEnabled(castbarFillDirDrop, castbarFillDirLabel, true)
    end

    -- Channel tick lines (5) for channeled casts
    local channelTicks = (g.castbarShowChannelTicks ~= false)
    if castbarChannelTicksCheck then
        castbarChannelTicksCheck:SetChecked(channelTicks)
    end

    -- Castbar glow / spark (Blizzard-style)
    local glowEnabled = (g.castbarShowGlow ~= false)
    if castbarGlowCheck then
        castbarGlowCheck:SetChecked(glowEnabled)
    end

    -- Latency indicator
    local latencyEnabled = (g.castbarShowLatency ~= false)
    if castbarLatencyCheck then
        castbarLatencyCheck:SetChecked(latencyEnabled)
    end

    -- Empowered (master) gate
    local empEnabled = (g.empowerColorStages ~= false)
    if empowerColorStagesCheck then
        empowerColorStagesCheck:SetChecked(empEnabled)
    end

    if empowerStageBlinkCheck then
        empowerStageBlinkCheck:SetEnabled(empEnabled)
        empowerStageBlinkCheck:SetChecked(empEnabled and (g.empowerStageBlink ~= false) or false)
    end

    local blinkEnabled = empEnabled and (g.empowerStageBlink ~= false)
    if empowerStageBlinkTimeSlider then
        local v = tonumber(g.empowerStageBlinkTime)
        if type(v) ~= "number" then v = 0.25 end
        if v < 0.05 then v = 0.05 elseif v > 1.0 then v = 1.0 end
                MSUF_SetLabeledSliderValue(empowerStageBlinkTimeSlider, v)
        MSUF_SetLabeledSliderEnabled(empowerStageBlinkTimeSlider, blinkEnabled)
    end
end

if castbarGroup and castbarGroup.HookScript then
    castbarGroup:HookScript("OnShow", MSUF_SyncCastbarsTabToggles)
end
if castbarEnemyGroup and castbarEnemyGroup.HookScript then
    castbarEnemyGroup:HookScript("OnShow", MSUF_SyncCastbarsTabToggles)
end

    castbarInterruptShakeCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.castbarInterruptShake = self:GetChecked() and true or false
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)
    castbarShakeIntensitySlider = CreateLabeledSlider(
        "MSUF_CastbarShakeIntensitySlider",
        "Shake intensity",
        castbarEnemyGroup,
        0, 30, 1,         -- 0–30 strength
        175, -200          -- Next to the toggles
    )
    castbarShakeIntensitySlider.onValueChanged = function(self, value)
        if self and self.MSUF_SkipCallback then return end
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarShakeStrength = math.floor(value + 0.5)
    end

local castbarTextureDrop

local LSM = MSUF_GetLSM()
if LSM then
    castbarTextureLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTextureLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureLabel:SetText("Castbar texture (SharedMedia)")

    castbarTextureDrop = CreateFrame("Frame", "MSUF_CastbarTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(castbarTextureDrop)
    castbarTextureDrop:SetPoint("TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(castbarTextureDrop, 180)
    castbarTextureDrop._msufButtonWidth = 180
    castbarTextureDrop._msufTweakBarTexturePreview = true
    MSUF_MakeDropdownScrollable(castbarTextureDrop, 12)

    castbarTexturePreview = CreateFrame("StatusBar", nil, castbarEnemyGroup)
    castbarTexturePreview:SetSize(180, 10)
    castbarTexturePreview:SetPoint("TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
    castbarTexturePreview:SetMinMaxValues(0, 1)
    castbarTexturePreview:SetValue(1)
    castbarTexturePreview:Hide()
    MSUF_KillMenuPreviewBar(castbarTexturePreview)
    local function CastbarTexturePreview_Update(texName)
        local texPath

        local LSM = MSUF_GetLSM()
        if LSM and texName and texName ~= "" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", texName)
            if ok and tex then
                texPath = tex
            end
        end

        if not texPath and MSUF_GetCastbarTexture then
            texPath = MSUF_GetCastbarTexture()
        end

        if not texPath then
            texPath = "Interface\\TARGETINGFRAME\\UI-StatusBar"
        end

        castbarTexturePreview:SetStatusBarTexture(texPath)
    end

    local function CastbarTextureDropdown_Initialize(self, level)
        EnsureDB()
        info = UIDropDownMenu_CreateInfo()
        current = MSUF_DB.general.castbarTexture

        local LSM = MSUF_GetLSM()
        if LSM then
            list = LSM:List("statusbar") or {}
            table.sort(list, function(a, b) return a:lower() < b:lower() end)

                        for _, name in ipairs(list) do
                info.text  = name
                info.value = name

                -- small texture swatch on the left
                local swatchTex = nil
                local LSM2 = MSUF_GetLSM()
                if LSM2 then
                    local ok2, tex2 = pcall(LSM2.Fetch, LSM2, "statusbar", name)
                    if ok2 and tex2 then swatchTex = tex2 end
                end
                if swatchTex then
                    info.icon = swatchTex
                    info.iconInfo = {
                        tCoordLeft = 0, tCoordRight = 0.85,
                        tCoordTop  = 0, tCoordBottom = 1,
                        iconWidth  = 80,
                        iconHeight = 12,
                    }
                else
                    info.icon = nil
                    info.iconInfo = nil
                end

                info.func  = function(btn)
                    EnsureDB()
                    MSUF_DB.general.castbarTexture = btn.value
                    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, btn.value)
                    UIDropDownMenu_SetText(castbarTextureDrop, btn.value)

                    if MSUF_UpdateCastbarTextures then
                        MSUF_UpdateCastbarTextures()
                    end
                    if MSUF_UpdateCastbarVisuals then
                        MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
                    end

                    if CastbarTexturePreview_Update then
                        CastbarTexturePreview_Update(btn.value)
                    end
                end

                info.checked = (name == current)
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end

      UIDropDownMenu_Initialize(castbarTextureDrop, CastbarTextureDropdown_Initialize)

    EnsureDB()
    local texKey = MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarTexture

    if type(texKey) ~= "string" or texKey == "" then
        texKey = "Blizzard"
        MSUF_DB.general.castbarTexture = texKey
    end

    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, texKey)
    UIDropDownMenu_SetText(castbarTextureDrop, texKey)

    CastbarTexturePreview_Update(texKey)
else

    castbarTextureInfo = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarTextureInfo:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureInfo:SetWidth(320)
    castbarTextureInfo:SetJustifyH("LEFT")
    castbarTextureInfo:SetText("Install the addon 'SharedMedia' (LibSharedMedia-3.0) to select castbar textures. Without it, the default UI castbar texture is used.")
end

    castbarTexColorTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTexColorTitle:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 250)
    castbarTexColorTitle:SetText("Texture and Empowered Cast")

    castbarTexColorLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarTexColorLine:SetColorTexture(1, 1, 1, 0.15)  -- gleiche Farbe wie "General"
    castbarTexColorLine:SetHeight(1)
    castbarTexColorLine:SetPoint("TOPLEFT", castbarTexColorTitle, "BOTTOMLEFT", 0, -4)
    castbarTexColorLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)

    castbarFillDirLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarFillDirLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 160)
    castbarFillDirLabel:SetText("Castbar fill direction")

    castbarUnifiedDirCheck = CreateLabeledCheckButton(
        "MSUF_CastbarUnifiedDirectionCheck",
        "Always use fill direction for all casts",
        castbarEnemyGroup,
        16, 185
    )
    castbarUnifiedDirCheck:ClearAllPoints()
    castbarUnifiedDirCheck:SetPoint("BOTTOMLEFT", castbarFillDirLabel, "TOPLEFT", 0, 4)
    castbarUnifiedDirCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.castbarUnifiedDirection = self:GetChecked() and true or false
        if MSUF_UpdateCastbarFillDirection then
            MSUF_UpdateCastbarFillDirection()
        end
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)
    castbarUnifiedDirCheck:SetScript("OnShow", function(self)
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)

    castbarFillDirDrop = CreateFrame("Frame", "MSUF_CastbarFillDirectionDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(castbarFillDirDrop)
    castbarFillDirDrop:SetPoint("TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(castbarFillDirDrop, 180)

    local function CastbarFillDirDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        g = MSUF_DB.general or {}
        current = g.castbarFillDirection or "RTL"

        items = {
            { key = "RTL", text = "Right to left (default)" },
            { key = "LTR", text = "Left to right" },
        }

        for _, item in ipairs(items) do
            info.text = item.text
            info.value = item.key
            info.func = function()
                EnsureDB()
                MSUF_DB.general.castbarFillDirection = item.key
                UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, item.key)
                if UIDropDownMenu_SetText then UIDropDownMenu_SetText(castbarFillDirDrop, item.text) end
                if MSUF_UpdateCastbarFillDirection then
                    MSUF_UpdateCastbarFillDirection()
                end
                if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
            end
            info.checked = (current == item.key)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(castbarFillDirDrop, CastbarFillDirDropdown_Initialize)

    EnsureDB()
    if MSUF_DB and MSUF_DB.general then
        dir = MSUF_DB.general.castbarFillDirection or "RTL"
        UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, dir)
    end

    -- Channeled casts: show 5 tick lines
    castbarChannelTicksCheck = CreateLabeledCheckButton(
        "MSUF_CastbarChannelTicksCheck",
        "Show channel tick lines (5)",
        castbarEnemyGroup,
        16, 0
    )
    if castbarChannelTicksCheck and castbarFillDirDrop then
        castbarChannelTicksCheck:ClearAllPoints()
        -- Dropdown has a -16 left padding; offset back so checkbox lines up with the other controls
        castbarChannelTicksCheck:SetPoint("TOPLEFT", castbarFillDirDrop, "BOTTOMLEFT", 16, -10)
    end
    castbarChannelTicksCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarShowChannelTicks = self:GetChecked() and true or false

        if type(_G.MSUF_UpdateCastbarChannelTicks) == "function" then
            _G.MSUF_UpdateCastbarChannelTicks()
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            if type(_G.MSUF_EnsureCastbars) == "function" then _G.MSUF_EnsureCastbars() end
            _G.MSUF_UpdateCastbarVisuals()
        end

        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)
    castbarChannelTicksCheck:SetScript("OnShow", function(self)
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)

    -- Castbar glow / spark (Blizzard-style)
    castbarGlowCheck = CreateLabeledCheckButton(
        "MSUF_CastbarGlowCheck",
        "Show castbar glow effect",
        castbarEnemyGroup,
        16, 0
    )
    -- positioned by the Castbar menu layout panel below (Style column)
    castbarGlowCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarShowGlow = self:GetChecked() and true or false

        if type(_G.MSUF_UpdateCastbarGlowEffect) == "function" then
            _G.MSUF_UpdateCastbarGlowEffect()
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            if type(_G.MSUF_EnsureCastbars) == "function" then _G.MSUF_EnsureCastbars() end
            _G.MSUF_UpdateCastbarVisuals()
        end

        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)
    castbarGlowCheck:SetScript("OnShow", function(self)
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)

    -- Latency indicator (end-of-cast spell queue / net latency zone)
    castbarLatencyCheck = CreateLabeledCheckButton(
        "MSUF_CastbarLatencyCheck",
        "Show latency indicator",
        castbarEnemyGroup,
        16, 0
    )
    -- positioned by the Castbar menu layout panel below (Style column)
    castbarLatencyCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarShowLatency = self:GetChecked() and true or false

        if type(_G.MSUF_UpdateCastbarLatencyIndicator) == "function" then
            _G.MSUF_UpdateCastbarLatencyIndicator()
        elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
            if type(_G.MSUF_EnsureCastbars) == "function" then _G.MSUF_EnsureCastbars() end
            _G.MSUF_UpdateCastbarVisuals()
        end

        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)
    castbarLatencyCheck:SetScript("OnShow", function(self)
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)

    empowerColorStagesCheck = CreateLabeledCheckButton(
        "MSUF_EmpowerColorStagesCheck",
        "Add color to stages (Empowered casts)",
        castbarEnemyGroup,
        16, 130
    )
    empowerColorStagesCheck:ClearAllPoints()
    empowerColorStagesCheck:SetPoint("TOPLEFT", castbarUnifiedDirCheck, "TOPLEFT", 300, 0)
    empowerColorStagesCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.empowerColorStages = self:GetChecked() and true or false
        if MSUF_UpdateCastbarVisuals then
            MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
        end
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)
    empowerColorStagesCheck:SetScript("OnShow", function(self)
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    end)

empowerStageBlinkCheck = CreateLabeledCheckButton(
    "MSUF_EmpowerStageBlinkCheck",
    "Add stage blink (Empowered casts)",
    castbarEnemyGroup,
    16, 130
)
empowerStageBlinkCheck:ClearAllPoints()
empowerStageBlinkCheck:SetPoint("TOPLEFT", empowerColorStagesCheck, "BOTTOMLEFT", 0, -10)

empowerStageBlinkCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.general.empowerStageBlink = self:GetChecked() and true or false
    if MSUF_UpdateCastbarVisuals then
        MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
    end
    if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
end)

empowerStageBlinkCheck:SetScript("OnShow", function(self)
    if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
end)

empowerStageBlinkTimeSlider = CreateLabeledSlider(
    "MSUF_EmpowerStageBlinkTimeSlider",
    "Stage blink time (sec)",
    castbarEnemyGroup,
    0.05, 1.00, 0.01,
    16, 130
)
empowerStageBlinkTimeSlider:ClearAllPoints()
empowerStageBlinkTimeSlider:SetPoint("TOPLEFT", empowerStageBlinkCheck, "BOTTOMLEFT", 0, -26)
empowerStageBlinkTimeSlider:SetWidth(260)
empowerStageBlinkTimeSlider.onValueChanged = function(self, value)
    if self and self.MSUF_SkipCallback then return end
    EnsureDB()
    if not MSUF_DB.general then MSUF_DB.general = {} end
    MSUF_DB.general.empowerStageBlinkTime = value
end

empowerStageBlinkTimeSlider:SetScript("OnShow", function(self)
    if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
end)

    -- Castbar menu mockup layout (Behavior / Style / Empowered)
    do
        -- Panel
        local panel = _G["MSUF_CastbarMenuPanel"]
        if not panel then
            panel = CreateFrame("Frame", "MSUF_CastbarMenuPanel", castbarEnemyGroup, "BackdropTemplate")
            panel:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -175)
            -- Make the panel taller so controls don't overlap (more room for right column + empowered section)
            panel:SetPoint("BOTTOMRIGHT", castbarEnemyGroup, "BOTTOMRIGHT", -16, 60)
            panel:EnableMouse(false)

            local tex = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"
            panel:SetBackdrop({
                bgFile   = tex,
                edgeFile = tex,
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.20)
            panel:SetBackdropBorderColor(1, 1, 1, 0.15)

            -- Split lines
            local vLine = panel:CreateTexture(nil, "ARTWORK")
            vLine:SetColorTexture(1, 1, 1, 0.12)
            vLine:SetWidth(1)
            vLine:SetPoint("TOP", panel, "TOP", 0, -16)
            vLine:SetPoint("BOTTOM", panel, "BOTTOM", 0, 120)

            local hLine = panel:CreateTexture(nil, "ARTWORK")
            hLine:SetColorTexture(1, 1, 1, 0.12)
            hLine:SetHeight(1)
            hLine:SetPoint("LEFT", panel, "LEFT", 16, 0)
            hLine:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
            hLine:SetPoint("BOTTOM", panel, "BOTTOM", 0, 120)

            -- Columns + empowered area (anchor helpers)
            local leftCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelLeft", panel)
            leftCol:EnableMouse(false)
            leftCol:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
            leftCol:SetPoint("RIGHT", vLine, "LEFT", -16, 0)
            leftCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)

            local rightCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelRight", panel)
            rightCol:EnableMouse(false)
            rightCol:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16)
            rightCol:SetPoint("LEFT", vLine, "RIGHT", 16, 0)
            rightCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)

            local emp = CreateFrame("Frame", "MSUF_CastbarMenuPanelEmpowered", panel)
            emp:EnableMouse(false)
            emp:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12)
            emp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12)
            emp:SetPoint("TOP", hLine, "BOTTOM", 0, -12)

            -- Headers
            local behaviorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            behaviorHeader:SetPoint("TOP", leftCol, "TOP", 0, 8)
            behaviorHeader:SetText("Behavior")

            local styleHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            styleHeader:SetPoint("TOP", rightCol, "TOP", 0, 8)
            styleHeader:SetText("Style")

            local empHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            empHeader:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, 0)
            empHeader:SetText("Empowered casts")
        end

        local leftCol  = _G["MSUF_CastbarMenuPanelLeft"]
        local rightCol = _G["MSUF_CastbarMenuPanelRight"]
        local emp      = _G["MSUF_CastbarMenuPanelEmpowered"]

        -- Hide old section titles/lines (we use the new panel headers)
        if castbarGeneralTitle then castbarGeneralTitle:Hide() end
        if castbarGeneralLine then castbarGeneralLine:Hide() end
        if castbarTexColorTitle then castbarTexColorTitle:Hide() end
        if castbarTexColorLine then castbarTexColorLine:Hide() end

        -- Behavior (left)
        if castbarInterruptShakeCheck and leftCol then
            castbarInterruptShakeCheck:ClearAllPoints()
            castbarInterruptShakeCheck:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -20)
        end
        if castbarShakeIntensitySlider and leftCol then
            castbarShakeIntensitySlider:ClearAllPoints()
            castbarShakeIntensitySlider:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -55)
            castbarShakeIntensitySlider:SetWidth(260)
        end

        if castbarUnifiedDirCheck and leftCol then
            castbarUnifiedDirCheck:ClearAllPoints()
            castbarUnifiedDirCheck:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, -115)
        end
        if castbarFillDirLabel and castbarUnifiedDirCheck then
            castbarFillDirLabel:ClearAllPoints()
            castbarFillDirLabel:SetPoint("TOPLEFT", castbarUnifiedDirCheck, "BOTTOMLEFT", 0, -14)
        end
        if castbarFillDirDrop and castbarFillDirLabel then
            castbarFillDirDrop:ClearAllPoints()
            castbarFillDirDrop:SetPoint("TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
        end

        if castbarChannelTicksCheck and castbarFillDirDrop then
            castbarChannelTicksCheck:ClearAllPoints()
            -- keep alignment with dropdown padding (-16) by offsetting back +16
            castbarChannelTicksCheck:SetPoint("TOPLEFT", castbarFillDirDrop, "BOTTOMLEFT", 16, -10)
        end

        -- Style (right)
        if castbarTextureLabel and rightCol then
            castbarTextureLabel:ClearAllPoints()
            castbarTextureLabel:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -20)
            castbarTextureLabel:SetText("Castbar texture")
        end
        if castbarTextureDrop and castbarTextureLabel then
            castbarTextureDrop:ClearAllPoints()
            castbarTextureDrop:SetPoint("TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
        end
        if castbarTexturePreview and castbarTextureDrop then
            castbarTexturePreview:ClearAllPoints()
            castbarTexturePreview:SetPoint("TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
        end
        if castbarTextureInfo and rightCol then
            castbarTextureInfo:ClearAllPoints()
            castbarTextureInfo:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -20)
            castbarTextureInfo:SetWidth(320)
        end

        -- Placeholders (disabled for now)
        if rightCol and not _G["MSUF_CastbarBackgroundTextureLabel"] then

local bgLabel = rightCol:CreateFontString("MSUF_CastbarBackgroundTextureLabel", "ARTWORK", "GameFontNormal")
bgLabel:SetText("Castbar background texture")

local bgDrop = CreateFrame("Frame", "MSUF_CastbarBackgroundTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(bgDrop)
UIDropDownMenu_SetWidth(bgDrop, 180)
bgDrop._msufButtonWidth = 180
bgDrop._msufTweakBarTexturePreview = true
if type(MSUF_MakeDropdownScrollable) == "function" then
    MSUF_MakeDropdownScrollable(bgDrop, 12)
end

local function BgPreview_Update(key)
    local texPath
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        texPath = _G.MSUF_ResolveStatusbarTextureKey(key)
    end
    if not texPath or texPath == "" then
        texPath = "Interface\\TargetingFrame\\UI-StatusBar"
    end

    local prev = _G.MSUF_CastbarBackgroundTexturePreview
    if not prev then
        prev = CreateFrame("StatusBar", "MSUF_CastbarBackgroundTexturePreview", castbarEnemyGroup)
        prev:SetMinMaxValues(0, 1)
        prev:SetValue(1)
        prev:SetSize(180, 10)
        _G.MSUF_CastbarBackgroundTexturePreview = prev
    end
    prev:SetParent(castbarEnemyGroup)
    prev:SetStatusBarTexture(texPath)
    prev:Hide()
    MSUF_KillMenuPreviewBar(prev)
    return prev
end

local function BgDrop_Init(self, level)
    EnsureDB()
    local info = UIDropDownMenu_CreateInfo()
    local g2 = (MSUF_DB and MSUF_DB.general) or {}

    local current = g2.castbarBackgroundTexture
    if type(current) ~= "string" or current == "" then
        current = g2.castbarTexture
    end
    if type(current) ~= "string" or current == "" then
        current = "Blizzard"
    end

    local function AddEntry(name, value)
        info.text = name
        info.value = value

        local swatchTex
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
            swatchTex = _G.MSUF_ResolveStatusbarTextureKey(value)
        end
        if swatchTex then
            info.icon = swatchTex
            info.iconInfo = {
                tCoordLeft = 0, tCoordRight = 0.85,
                tCoordTop  = 0, tCoordBottom = 1,
                iconWidth  = 80,
                iconHeight = 12,
            }
        else
            info.icon = nil
            info.iconInfo = nil
        end

        info.func = function(btn)
            EnsureDB()
            MSUF_DB.general.castbarBackgroundTexture = btn.value
            UIDropDownMenu_SetSelectedValue(bgDrop, btn.value)
            UIDropDownMenu_SetText(bgDrop, btn.value)

            if type(MSUF_UpdateCastbarTextures) == "function" then
                MSUF_UpdateCastbarTextures()
            end
            if type(MSUF_UpdateCastbarVisuals) == "function" then
                MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                pcall(_G.MSUF_UpdateBossCastbarPreview)
            end

            local prev = BgPreview_Update(btn.value)
            if prev then
                prev:ClearAllPoints()
                prev:SetPoint("TOPLEFT", bgDrop, "BOTTOMLEFT", 20, -6)
            end
        end

        info.checked = (value == current)
        info.notCheckable = false
        UIDropDownMenu_AddButton(info, level)
    end

    local LSM = MSUF_GetLSM()
    if LSM and type(LSM.List) == "function" then
        local list = LSM:List("statusbar") or {}
        table.sort(list, function(a, b) return a:lower() < b:lower() end)
        for _, name in ipairs(list) do
            AddEntry(name, name)
        end
    else
        -- No SharedMedia: show built-in always-available textures
        local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES or {}
        local ordered = {
            "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills",
            "Outline", "TooltipBorder", "DialogBG", "Parchment",
        }
        local seen = {}
        for _, k in ipairs(ordered) do
            if builtins[k] then
                seen[k] = true
                AddEntry(k, k)
            end
        end
        for k in pairs(builtins) do
            if not seen[k] then
                AddEntry(k, k)
            end
        end
    end
end

UIDropDownMenu_Initialize(bgDrop, BgDrop_Init)

EnsureDB()
local g3 = (MSUF_DB and MSUF_DB.general) or {}
local sel = g3.castbarBackgroundTexture
if type(sel) ~= "string" or sel == "" then
    sel = g3.castbarTexture
end
if type(sel) ~= "string" or sel == "" then
    sel = "Blizzard"
end
g3.castbarBackgroundTexture = sel

UIDropDownMenu_SetSelectedValue(bgDrop, sel)
UIDropDownMenu_SetText(bgDrop, sel)

local prev = BgPreview_Update(sel)
if prev then
    prev:ClearAllPoints()
    prev:SetPoint("TOPLEFT", bgDrop, "BOTTOMLEFT", 20, -6)
end
            local outlineSlider = CreateLabeledSlider(
                "MSUF_CastbarOutlineThicknessSlider",
                "Outline thickness",
                castbarEnemyGroup,
                0, 6, 1,
                0, 0
            )
            outlineSlider:SetAlpha(1)
            outlineSlider.onValueChanged = function(self, value)
                EnsureDB()
                local g = (MSUF_DB and MSUF_DB.general) or {}
                g.castbarOutlineThickness = tonumber(value) or 0

                if type(_G.MSUF_UpdateCastbarVisuals) == "function" then
                    MSUF_EnsureCastbars(); if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
                end
                if type(_G.MSUF_ApplyCastbarOutlineToAll) == "function" then
                    _G.MSUF_ApplyCastbarOutlineToAll(true)
                end
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                    _G.MSUF_UpdateBossCastbarPreview()
                end
            end

            do
                EnsureDB()
                local g = (MSUF_DB and MSUF_DB.general) or {}
                local t = tonumber(g.castbarOutlineThickness)
                if t == nil then t = 1 end
                t = math.floor(t + 0.5)
                if t < 0 then t = 0 end
                if t > 6 then t = 6 end

                                MSUF_SetLabeledSliderValue(outlineSlider, t)
            end

            -- Position placeholders under the texture dropdown (or under info text if LSM missing)
            bgLabel:ClearAllPoints()
            bgLabel:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -95)
            bgDrop:ClearAllPoints()
            bgDrop:SetPoint("TOPLEFT", bgLabel, "BOTTOMLEFT", -16, -4)
            outlineSlider:ClearAllPoints()
            outlineSlider:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -155)
            outlineSlider:SetWidth(260)
        end

        -- Glow effect belongs to Style (right column)
        do
            local outlineSlider = _G["MSUF_CastbarOutlineThicknessSlider"]
            if castbarGlowCheck and rightCol then
                castbarGlowCheck:ClearAllPoints()
                if outlineSlider then
                    castbarGlowCheck:SetPoint("TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -18)
                else
                    castbarGlowCheck:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -210)
                end
            end
        end

        -- Latency indicator belongs to Style (right column)
        do
            if castbarLatencyCheck and rightCol then
                castbarLatencyCheck:ClearAllPoints()
                if castbarGlowCheck then
                    castbarLatencyCheck:SetPoint("TOPLEFT", castbarGlowCheck, "BOTTOMLEFT", 0, -8)
                else
                    local outlineSlider = _G["MSUF_CastbarOutlineThicknessSlider"]
                    if outlineSlider then
                        castbarLatencyCheck:SetPoint("TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -18)
                    else
                        castbarLatencyCheck:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -230)
                    end
                end
            end
        end

        -- Empowered (bottom)
        if empowerColorStagesCheck and emp then
            empowerColorStagesCheck:ClearAllPoints()
            empowerColorStagesCheck:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, -22)
        end
        if empowerStageBlinkCheck and empowerColorStagesCheck then
            empowerStageBlinkCheck:ClearAllPoints()
            empowerStageBlinkCheck:SetPoint("TOPLEFT", empowerColorStagesCheck, "BOTTOMLEFT", 0, -10)
        end
        if empowerStageBlinkTimeSlider and emp then
            empowerStageBlinkTimeSlider:ClearAllPoints()
            empowerStageBlinkTimeSlider:SetPoint("TOPLEFT", emp, "TOPLEFT", 300, -24)
            empowerStageBlinkTimeSlider:SetWidth(260)
        end
    end

-- Auras tab (legacy menu removed in Patch 6D Step 2)
-- Keep only a shortcut button that opens the dedicated Auras 2.0 Settings category.
do
    local function SetupPanel(panel, titleText)
        if (not panel.SetBackdrop) and BackdropTemplateMixin and Mixin then
            Mixin(panel, BackdropTemplateMixin)
        end
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
        note:SetText("Auras are handled by the dedicated |cffffd200Auras 2.0|r menu.\n\nThis tab is now only a shortcut.")

        local btn = CreateFrame("Button", "MSUF_OpenAuras2FromAurasTabButton", p, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
        btn:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -12)
        btn:SetHeight(24)
        btn:SetText("Open Auras 2.0")

        local err = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        err:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
        err:SetWidth(p:GetWidth() - 28)
        err:SetJustifyH("LEFT")
        err:SetTextColor(1, 0.25, 0.25, 1)
        err:SetText("")
        err:Hide()

        btn:SetScript("OnClick", function()
            err:Hide()

            -- Ensure the Auras 2.0 Settings category is registered.
            local parent = _G.MSUF_SettingsCategory or MSUF_SettingsCategory or (ns and ns.MSUF_MainCategory)
            if (not _G.MSUF_AurasCategory) and ns and ns.MSUF_RegisterAurasOptions and parent then
                ns.MSUF_RegisterAurasOptions(parent)
            end

            local cat = _G.MSUF_AurasCategory or (ns and ns.MSUF_AurasCategory)
            if cat then
                local id = cat
                if type(cat) == "table" then
                    id = cat.ID
                end
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

            err:SetText("Could not open the Auras 2.0 menu.\nPlease make sure MSUF options are registered and try again.")
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

BAR_DROPDOWN_WIDTH = 260
    barsTitle = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    barsTitle:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -120)
    barsTitle:SetText("Bar appearance")

-- Absorb display (moved from Misc -> Bar appearance; replaces Bar mode which is now in Colors)
absorbDisplayLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbDisplayLabel:SetPoint("TOPLEFT", barsTitle, "BOTTOMLEFT", 0, -8)
absorbDisplayLabel:SetText("Absorb display")

absorbDisplayDrop = CreateFrame("Frame", "MSUF_AbsorbDisplayDrop", barGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(absorbDisplayDrop)
absorbDisplayDrop:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbDisplayDrop, BAR_DROPDOWN_WIDTH)

UIDropDownMenu_Initialize(absorbDisplayDrop, function(self, level)
    if not level then return end
    EnsureDB()
    local g = MSUF_DB.general or {}

    local function GetCurrentMode()
        local barOn  = (g.enableAbsorbBar ~= false)
        local textOn = (g.showTotalAbsorbAmount == true)

        if (not barOn) and (not textOn) then
            return 1 -- off
        elseif barOn and (not textOn) then
            return 2 -- bar
        elseif barOn and textOn then
            return 3 -- bar + text
        else
            return 4 -- text only
        end
    end

    local current = GetCurrentMode()

    local function ApplyAndRefresh()
        -- Force a live refresh without needing /reload
        if _G.MSUF_UnitFrames then
            for _, frame in pairs(_G.MSUF_UnitFrames) do
                if frame and frame.unit then
                    local maxHP = UnitHealthMax(frame.unit)
                    if frame.absorbBar and _G.MSUF_UpdateAbsorbBar then
                        _G.MSUF_UpdateAbsorbBar(frame, frame.unit, maxHP)
                    end
                    if UpdateSimpleUnitFrame then
                        UpdateSimpleUnitFrame(frame)
                    end
                end
            end
        end
    end

    local function AddOption(text, value, barOn, textOn)
        local info = UIDropDownMenu_CreateInfo()
        info.text  = text
        info.value = value
        info.func  = function()
            EnsureDB()
            local g2 = MSUF_DB.general or {}

            g2.enableAbsorbBar       = barOn
            g2.showTotalAbsorbAmount = textOn

            -- Classic mode set only; no percent / combined logic here.
            g2.absorbTextMode = nil

            UIDropDownMenu_SetSelectedValue(absorbDisplayDrop, value)
            UIDropDownMenu_SetText(absorbDisplayDrop, text)
            ApplyAndRefresh()
        end
        info.checked = (value == current)
        UIDropDownMenu_AddButton(info, level)
    end

    AddOption('Absorb off',        1, false, false)
    AddOption('Absorb bar',        2, true,  false)
    AddOption('Absorb bar + text', 3, true,  true)
    AddOption('Absorb text only',  4, false, true)
end)

absorbDisplayDrop:SetScript('OnShow', function(self)
    EnsureDB()
    local g = MSUF_DB.general or {}

    local barOn  = (g.enableAbsorbBar ~= false)
    local textOn = (g.showTotalAbsorbAmount == true)

    local mode, text
    if (not barOn) and (not textOn) then
        mode, text = 1, 'Absorb off'
    elseif barOn and (not textOn) then
        mode, text = 2, 'Absorb bar'
    elseif barOn and textOn then
        mode, text = 3, 'Absorb bar + text'
    else
        mode, text = 4, 'Absorb text only'
    end

    UIDropDownMenu_SetSelectedValue(self, mode)
    UIDropDownMenu_SetText(self, text)
end)


-- Absorb anchoring (which side positive absorb / heal-absorb start on)
absorbAnchorLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbAnchorLabel:SetPoint("TOPLEFT", absorbDisplayDrop, "BOTTOMLEFT", 16, -8)
absorbAnchorLabel:SetText("Absorb bar anchoring")

absorbAnchorDrop = CreateFrame("Frame", "MSUF_AbsorbAnchorDrop", barGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(absorbAnchorDrop)
absorbAnchorDrop:SetPoint("TOPLEFT", absorbAnchorLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbAnchorDrop, BAR_DROPDOWN_WIDTH)

UIDropDownMenu_Initialize(absorbAnchorDrop, function(self, level)
    if not level then return end
    EnsureDB()
    local g = MSUF_DB.general or {}

    local current = tonumber(g.absorbAnchorMode) or 2

    local function ApplyAndRefresh()
        if _G.MSUF_UnitFrames then
            for _, frame in pairs(_G.MSUF_UnitFrames) do
                if frame then
                    if type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
                        _G.MSUF_ApplyAbsorbAnchorMode(frame)
                    end
                    if UpdateSimpleUnitFrame and frame.unit then
                        UpdateSimpleUnitFrame(frame)
                    end
                end
            end
        end
    end

    local function AddOption(text, value)
        local info = UIDropDownMenu_CreateInfo()
        info.text  = text
        info.value = value
        info.func  = function()
            EnsureDB()
            local g2 = MSUF_DB.general or {}
            g2.absorbAnchorMode = value
            UIDropDownMenu_SetSelectedValue(absorbAnchorDrop, value)
            UIDropDownMenu_SetText(absorbAnchorDrop, text)
            ApplyAndRefresh()
        end
        info.checked = (value == current)
        UIDropDownMenu_AddButton(info, level)
    end

    AddOption("Left: Absorb | Right: Heal-Absorb", 1)
    AddOption("Right: Absorb | Left: Heal-Absorb", 2)
end)

absorbAnchorDrop:SetScript('OnShow', function(self)
    EnsureDB()
    local g = MSUF_DB.general or {}
    local mode = tonumber(g.absorbAnchorMode) or 2
    local text = (mode == 1) and "Left: Absorb | Right: Heal-Absorb" or "Right: Absorb | Left: Heal-Absorb"
    UIDropDownMenu_SetSelectedValue(self, mode)
    UIDropDownMenu_SetText(self, text)
end)
gradientCheck = CreateLabeledCheckButton(
        "MSUF_GradientEnableCheck",
        "Enable HP bar gradient",
        barGroup,
        16, -260
    )

    -- D-pad style direction selector (replaces the old strength bar in the UI)
    gradientDirPad = MSUF_CreateGradientDirectionPad(barGroup)

    -- Keep the legacy strength slider for backwards-compatible DB values,
    -- but hide it from the UI (user requested "bar weg").
    gradientSlider = CreateLabeledSlider("MSUF_GradientStrengthSlider", "",
        barGroup,
        0, 100, 5,
        16, -300
    )
    if gradientSlider then
        gradientSlider:Hide()
        if gradientSlider.editBox then gradientSlider.editBox:Hide() end
        if gradientSlider.minusButton then gradientSlider.minusButton:Hide() end
        if gradientSlider.plusButton then gradientSlider.plusButton:Hide() end
    end

    targetPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_TargetPowerBarCheck",
        "Show power bar on target frame",
        barGroup,
        260, -260
    )

    bossPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_BossPowerBarCheck",
        "Show power bar on boss frames",
        barGroup,
        260, -290
    )

    playerPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_PlayerPowerBarCheck",
        "Show power bar on player frames",
        barGroup,
        260, -320
    )

    focusPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_FocusPowerBarCheck",
        "Show power bar on focus",
        barGroup,
        260, -350
    )

    powerBarHeightLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -4)
    powerBarHeightLabel:SetText("Power bar height")

    powerBarHeightEdit = CreateFrame("EditBox", "MSUF_PowerBarHeightEdit", barGroup, "InputBoxTemplate")
    powerBarHeightEdit:SetSize(40, 20)
    powerBarHeightEdit:SetAutoFocus(false)
    powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 4, 0)
    powerBarHeightEdit:SetTextInsets(4, 4, 2, 2)

    powerBarEmbedCheck = CreateLabeledCheckButton(
        "MSUF_PowerBarEmbedCheck",
        "Embed power bar into health bar",
        barGroup,
        260, -380
    )

    hpModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hpModeLabel:SetPoint("TOPLEFT", powerBarEmbedCheck or powerBarHeightLabel, "BOTTOMLEFT", 0, -16)
    hpModeLabel:SetText("Textmode HP / Power")
    -- Make this header white (requested UX): the dropdown items remain normal.
    hpModeLabel:SetTextColor(1, 1, 1, 1)

    hpModeDrop = CreateFrame("Frame", "MSUF_HPTextModeDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(hpModeDrop)
    hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)

    hpModeOptions = {
        { key = "FULL_ONLY",          label = "Full value only" },
        { key = "FULL_PLUS_PERCENT",  label = "Full value + %" },
        { key = "PERCENT_PLUS_FULL",  label = "% + Full value" },
        { key = "PERCENT_ONLY",       label = "Only %" },
    }

    local function HPModeDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        current = MSUF_DB.general.hpTextMode or "FULL_PLUS_PERCENT"

        for _, opt in ipairs(hpModeOptions) do
            info.text  = opt.label
            info.value = opt.key
            info.func  = function(btn)
                EnsureDB()
                MSUF_DB.general.hpTextMode = btn.value

                UIDropDownMenu_SetSelectedValue(hpModeDrop, btn.value)
                UIDropDownMenu_SetText(hpModeDrop, opt.label)

                ApplyAllSettings()

                if type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then
                    _G.MSUF_Options_RefreshHPSpacerControls()
                end
            end
            info.checked = (opt.key == current)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(hpModeDrop, HPModeDropdown_Initialize)
    UIDropDownMenu_SetWidth(hpModeDrop, BAR_DROPDOWN_WIDTH)

    do
        EnsureDB()
        current = MSUF_DB.general.hpTextMode or "FULL_PLUS_PERCENT"
        labelText = "Full value + %"
        for _, opt in ipairs(hpModeOptions) do
            if opt.key == current then
                labelText = opt.label
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(hpModeDrop, current)
        UIDropDownMenu_SetText(hpModeDrop, labelText)
    end

    powerModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerModeLabel:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", 0, -16)
    powerModeLabel:SetText("Power text mode")

    powerModeDrop = CreateFrame("Frame", "MSUF_PowerTextModeDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(powerModeDrop)
    powerModeDrop:SetPoint("TOPLEFT", powerModeLabel, "BOTTOMLEFT", -16, -16)

    powerModeOptions = {
        { key = "FULL_SLASH_MAX",     label = "Current / Max" },
        { key = "FULL_ONLY",          label = "Full value only" },
        { key = "FULL_PLUS_PERCENT",  label = "Full value + %" },
        { key = "PERCENT_PLUS_FULL",  label = "% + Full value" },
        { key = "PERCENT_ONLY",       label = "Only %" },
    }

    local function PowerModeDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        local currentMode = MSUF_DB.general.powerTextMode or "FULL_SLASH_MAX"

        for _, opt in ipairs(powerModeOptions) do
            info.text  = opt.label
            info.value = opt.key
            info.func  = function(btn)
                EnsureDB()
                MSUF_DB.general.powerTextMode = btn.value

                UIDropDownMenu_SetSelectedValue(powerModeDrop, btn.value)
                UIDropDownMenu_SetText(powerModeDrop, opt.label)

                ApplyAllSettings()
            end
            info.checked = (opt.key == currentMode)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(powerModeDrop, PowerModeDropdown_Initialize)
    UIDropDownMenu_SetWidth(powerModeDrop, BAR_DROPDOWN_WIDTH)

    do
        EnsureDB()
        local currentMode = MSUF_DB.general.powerTextMode or "FULL_SLASH_MAX"
        local labelTextMode = "Current / Max"
        for _, opt in ipairs(powerModeOptions) do
            if opt.key == currentMode then
                labelTextMode = opt.label
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(powerModeDrop, currentMode)
        UIDropDownMenu_SetText(powerModeDrop, labelTextMode)
    end

    -- Text separators (HP + Power)
    sepHeader = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sepHeader:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 16, -12)
    sepHeader:SetText("Text Separators")
    hpSepLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    -- Extra spacing from the header (prevents cramped look)
    hpSepLabel:SetPoint("TOPLEFT", sepHeader, "BOTTOMLEFT", 0, -10)
    hpSepLabel:SetText("Health (HP)")
    hpSepDrop = CreateFrame("Frame", "MSUF_HPTextSeparatorDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(hpSepDrop)
    -- Both dropdowns sit slightly lower (5px) for nicer vertical balance.
    hpSepDrop:SetPoint("TOPLEFT", hpSepLabel, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(hpSepDrop, 80)

    -- In the Flash/Slash menu container, UIDropDownMenu can anchor incorrectly.
    -- Force the dropdown list to open anchored under this dropdown.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(hpSepDrop, 0, 0, "TOPLEFT", hpSepDrop, "BOTTOMLEFT")
    else
        hpSepDrop.xOffset = 0
        hpSepDrop.yOffset = 0
        hpSepDrop.point = "TOPLEFT"
        hpSepDrop.relativeTo = hpSepDrop
        hpSepDrop.relativePoint = "BOTTOMLEFT"
    end

    local hpSepOptions = {
        { key = "",  label = " "  }, -- empty → looks blank, just space between values
        { key = "-", label = "-" },
        { key = "/", label = "/" },
        { key = "\\", label = "\\" },
        { key = "|", label = "|" },
    }

    local function HPSeparatorDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        local g = MSUF_DB.general or {}
        local currentSep = g.hpTextSeparator
        if currentSep == nil then
            currentSep = ""
        end

        for _, opt in ipairs(hpSepOptions) do
            local thisKey   = opt.key
            local thisLabel = opt.label

            info.text  = (thisKey == "" and "Space / none" or thisLabel)
            info.value = thisKey
            info.func  = function(btn)
                EnsureDB()
                local g2 = MSUF_DB.general or {}
                g2.hpTextSeparator = thisKey

                UIDropDownMenu_SetSelectedValue(hpSepDrop, thisKey)
                UIDropDownMenu_SetText(hpSepDrop, thisLabel)
                ApplyAllSettings()
            end
            info.checked = (thisKey == currentSep)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(hpSepDrop, HPSeparatorDropdown_Initialize)

    do
        EnsureDB()
        local g = MSUF_DB.general or {}
        local currentSep = g.hpTextSeparator
        if currentSep == nil then
            currentSep = ""
        end

        local displayLabel = " "
        for _, opt in ipairs(hpSepOptions) do
            if opt.key == currentSep then
                displayLabel = opt.label
                break
            end
        end

        UIDropDownMenu_SetSelectedValue(hpSepDrop, currentSep)
        UIDropDownMenu_SetText(hpSepDrop, displayLabel)
    end

    -- Power separator (separate from HP separator; falls back to HP separator if unset for backward compatibility)
    powerSepLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerSepLabel:SetPoint("LEFT", hpSepLabel, "RIGHT", 120, 0)
    powerSepLabel:SetText("Power")
    powerSepDrop = CreateFrame("Frame", "MSUF_PowerTextSeparatorDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(powerSepDrop)
    powerSepDrop:SetPoint("TOPLEFT", powerSepLabel, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(powerSepDrop, 80)

    -- Same anchor fix for the power separator dropdown.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(powerSepDrop, 0, 0, "TOPLEFT", powerSepDrop, "BOTTOMLEFT")
    else
        powerSepDrop.xOffset = 0
        powerSepDrop.yOffset = 0
        powerSepDrop.point = "TOPLEFT"
        powerSepDrop.relativeTo = powerSepDrop
        powerSepDrop.relativePoint = "BOTTOMLEFT"
    end

    local function PowerSeparatorDropdown_Initialize(self, level)
        info = UIDropDownMenu_CreateInfo()
        EnsureDB()
        local g = MSUF_DB.general or {}
        local currentSep = g.powerTextSeparator
        if currentSep == nil then
            currentSep = g.hpTextSeparator
        end
        if currentSep == nil then
            currentSep = ""
        end

        for _, opt in ipairs(hpSepOptions) do
            local thisKey   = opt.key
            local thisLabel = opt.label

            info.text  = (thisKey == "" and "Space / none" or thisLabel)
            info.value = thisKey
            info.func  = function(btn)
                EnsureDB()
                local g2 = MSUF_DB.general or {}
                g2.powerTextSeparator = thisKey

                UIDropDownMenu_SetSelectedValue(powerSepDrop, thisKey)
                UIDropDownMenu_SetText(powerSepDrop, thisLabel)
                ApplyAllSettings()
            end
            info.checked = (thisKey == currentSep)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(powerSepDrop, PowerSeparatorDropdown_Initialize)

    do
        EnsureDB()
        local g = MSUF_DB.general or {}
        local currentSep = g.powerTextSeparator
        if currentSep == nil then
            currentSep = g.hpTextSeparator
        end
        if currentSep == nil then
            currentSep = ""
        end

        local displayLabel = " "
        for _, opt in ipairs(hpSepOptions) do
            if opt.key == currentSep then
                displayLabel = opt.label
                break
            end
        end

        UIDropDownMenu_SetSelectedValue(powerSepDrop, currentSep)
        UIDropDownMenu_SetText(powerSepDrop, displayLabel)
    end
    -- HP % Spacer (split FULL value + % into two text anchors)
    -- Per-unit settings are stored on MSUF_DB[unitKey].hpTextSpacerEnabled / hpTextSpacerX.
    -- The Bars menu shows the settings for the *last clicked* MSUF unitframe (stored as a UI selection
    -- in MSUF_DB.general.hpSpacerSelectedUnitKey).
-- Selected unitframe indicator + info icon (selection is done by clicking the unitframe itself).
hpSpacerSelectedLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hpSpacerSelectedLabel:ClearAllPoints()
hpSpacerSelectedLabel:SetPoint("TOPLEFT", hpSepDrop, "BOTTOMLEFT", 16, -8)
hpSpacerSelectedLabel:SetTextColor(1, 0.82, 0, 1)
hpSpacerSelectedLabel:SetText("Selected: Player")

hpSpacerInfoButton = CreateFrame("Button", "MSUF_HPSpacerInfoButton", barGroup)
hpSpacerInfoButton:SetSize(14, 14)
hpSpacerInfoButton:ClearAllPoints()
hpSpacerInfoButton:SetPoint("LEFT", hpSpacerSelectedLabel, "RIGHT", 4, 0)
do
    local t = hpSpacerInfoButton:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(hpSpacerInfoButton)
    t:SetTexture("Interface\FriendsFrame\InformationIcon")
    hpSpacerInfoButton._msufTex = t
end
hpSpacerInfoButton:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("HP Spacer", 1, 1, 1)
    GameTooltip:AddLine("Click a MSUF unitframe (Player/Target/Focus/ToT/Pet/Boss) to choose which unit these spacer settings apply to.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Works only when 'Textmode HP' is set to 'Full value + %' (or '% + Full value').", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Splits Full value (right) and % (left) so you can place them at opposite ends.", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
end)
hpSpacerInfoButton:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
end)

hpSpacerCheck = CreateFrame("CheckButton", "MSUF_HPTextSpacerCheck", barGroup, "UICheckButtonTemplate")
hpSpacerCheck:ClearAllPoints()
hpSpacerCheck:SetPoint("TOPLEFT", hpSpacerSelectedLabel, "BOTTOMLEFT", 0, -4)
hpSpacerCheck.text = _G["MSUF_HPTextSpacerCheckText"]
if hpSpacerCheck.text then
    hpSpacerCheck.text:SetText("Spacer on/off")
end
MSUF_StyleToggleText(hpSpacerCheck)
MSUF_StyleCheckmark(hpSpacerCheck)

-- Slider (kept in the box; placed low enough to avoid overlaps)
hpSpacerSlider = CreateLabeledSlider("MSUF_HPTextSpacerSlider", "HP Spacer (X)", barGroup, 0, 1000, 1, 16, -200)
hpSpacerSlider:ClearAllPoints()
hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -18)
if hpSpacerSlider.SetWidth then
    hpSpacerSlider:SetWidth(260)
end

    local function _MSUF_HPSpacer_GetSelectedUnitKey()
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

    local function _MSUF_HPSpacer_GetUnitDB()
        local unitKey = _MSUF_HPSpacer_GetSelectedUnitKey()
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        return unitKey, MSUF_DB[unitKey]
    end

    local function RefreshHPSpacerControls()
        EnsureDB()
        local unitKey, u = _MSUF_HPSpacer_GetUnitDB()

        local g0 = MSUF_DB.general or {}
        local hpMode = g0.hpTextMode or "FULL_PLUS_PERCENT"
        local modeAllowsSpacer = (hpMode == "FULL_PLUS_PERCENT" or hpMode == "PERCENT_PLUS_FULL")

        if hpSpacerSelectedLabel and hpSpacerSelectedLabel.SetText then
            local nice = unitKey
            if nice == "player" then nice = "Player"
            elseif nice == "target" then nice = "Target"
            elseif nice == "focus" then nice = "Focus"
            elseif nice == "targettarget" then nice = "ToT"
            elseif nice == "pet" then nice = "Pet"
            elseif nice == "boss" then nice = "Boss"
            end
            hpSpacerSelectedLabel:SetText("Selected: " .. tostring(nice))
        end

        local on = (u.hpTextSpacerEnabled == true)
        if hpSpacerCheck and hpSpacerCheck.SetChecked then
            hpSpacerCheck:SetChecked(on)
        end
        if hpSpacerCheck and hpSpacerCheck.SetEnabled then
            hpSpacerCheck:SetEnabled(modeAllowsSpacer)
        end
        if hpSpacerCheck then
            hpSpacerCheck:SetAlpha(modeAllowsSpacer and 1 or 0.45)
            if hpSpacerCheck.text and hpSpacerCheck.text.SetTextColor then
                local c = modeAllowsSpacer and 1 or 0.5
                hpSpacerCheck.text:SetTextColor(c, c, c, 1)
            end
        end

        local maxV = 1000
        if type(_G.MSUF_GetHPSpacerMaxForUnitKey) == "function" then
            local mv = _G.MSUF_GetHPSpacerMaxForUnitKey(unitKey)
            if type(mv) == "number" and mv > 0 then
                maxV = math.floor(mv + 0.5)
            end
        end
        if maxV < 0 then maxV = 0 end
        if maxV > 2000 then maxV = 2000 end

        if hpSpacerSlider and hpSpacerSlider.SetMinMaxValues then
            hpSpacerSlider._msufIgnoreChange = true
            hpSpacerSlider:SetMinMaxValues(0, maxV)
            hpSpacerSlider.minVal = 0
            hpSpacerSlider.maxVal = maxV
            if _G[hpSpacerSlider:GetName() .. "High"] then
                _G[hpSpacerSlider:GetName() .. "High"]:SetText(tostring(maxV))
            end
            if _G[hpSpacerSlider:GetName() .. "Low"] then
                _G[hpSpacerSlider:GetName() .. "Low"]:SetText("0")
            end

            local v = tonumber(u.hpTextSpacerX) or 0
            if v < 0 then v = 0 end
            if v > maxV then v = maxV end
            u.hpTextSpacerX = v

            hpSpacerSlider:SetValue(v)
            hpSpacerSlider._msufIgnoreChange = false

            if hpSpacerSlider.editBox and not hpSpacerSlider.editBox:HasFocus() then
                hpSpacerSlider.editBox:SetText(tostring(math.floor((v or 0) + 0.5)))
            end

            local sliderEnabled = (modeAllowsSpacer and on)

            if hpSpacerSlider.SetEnabled then
                hpSpacerSlider:SetEnabled(sliderEnabled)
            end
            if hpSpacerSlider.editBox and hpSpacerSlider.editBox.SetEnabled then
                hpSpacerSlider.editBox:SetEnabled(sliderEnabled)
            end
            if hpSpacerSlider.minusButton and hpSpacerSlider.minusButton.SetEnabled then
                hpSpacerSlider.minusButton:SetEnabled(sliderEnabled)
            end
            if hpSpacerSlider.plusButton and hpSpacerSlider.plusButton.SetEnabled then
                hpSpacerSlider.plusButton:SetEnabled(sliderEnabled)
            end
            if hpSpacerSlider then
                hpSpacerSlider:SetAlpha(sliderEnabled and 1 or 0.45)
            end
        end
    end

    hpSpacerCheck:SetScript("OnClick", function(self)
        EnsureDB()
        local g = MSUF_DB.general or {}
        local hpMode = g.hpTextMode or "FULL_PLUS_PERCENT"
        if hpMode ~= "FULL_PLUS_PERCENT" and hpMode ~= "PERCENT_PLUS_FULL" then
            -- Spacer only works in Full+% mode; keep stored values but don't change while disabled.
            RefreshHPSpacerControls()
            return
        end
        local _, u = _MSUF_HPSpacer_GetUnitDB()
        u.hpTextSpacerEnabled = self:GetChecked() and true or false
        RefreshHPSpacerControls()
        local unitKey = _MSUF_HPSpacer_GetSelectedUnitKey()
        MSUF_Options_RequestLayoutForKey(unitKey, "HP_SPACER_TOGGLE")
        if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
            _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
        end
    end)

    hpSpacerSlider:SetScript("OnValueChanged", function(self, value)
        if not self or not self.GetValue then return end
        if self._msufIgnoreChange then return end

        EnsureDB()
        local unitKey, u = _MSUF_HPSpacer_GetUnitDB()

        local v = tonumber(value) or 0
        if v < 0 then v = 0 end
        local maxV = tonumber(self.maxVal) or 1000
        if v > maxV then v = maxV end

        u.hpTextSpacerX = v

        if self.editBox and not self.editBox:HasFocus() then
            self.editBox:SetText(tostring(math.floor(v + 0.5)))
        end
        MSUF_Options_RequestLayoutForKey(unitKey, "HP_SPACER_X")
        if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then
            _G.MSUF_ForceTextLayoutForUnitKey(unitKey)
        end
    end)

    RefreshHPSpacerControls()

    -- Let the main file refresh this UI when the user clicks a unitframe.
    _G.MSUF_Options_RefreshHPSpacerControls = RefreshHPSpacerControls

local barTextureDrop
        local barBgTextureDrop

        -- Shared helper used by both bar texture dropdowns (foreground + background)
        local function MSUF_TryApplyBarTextureLive()
            if type(ApplyAllSettings) == "function" then
                ApplyAllSettings()
            end

            if type(_G.MSUF_UpdateAllBarTextures) == "function" then
                _G.MSUF_UpdateAllBarTextures()
            elseif type(_G.UpdateAllBarTextures) == "function" then
                _G.UpdateAllBarTextures()
            elseif type(_G.MSUF_UpdateAllUnitFrames) == "function" then
                _G.MSUF_UpdateAllUnitFrames()
            elseif type(_G.MSUF_RefreshAllUnitFrames) == "function" then
                _G.MSUF_RefreshAllUnitFrames()
            end
        end

        _G.MSUF_TryApplyBarTextureLive = MSUF_TryApplyBarTextureLive

        local function MSUF_AddDropdownSeparator(level)
            local sep = UIDropDownMenu_CreateInfo()
            sep.text = " "
            sep.isTitle = true
            sep.notCheckable = true
            sep.disabled = true
            UIDropDownMenu_AddButton(sep, level)
        end

        do
            barTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            barTextureLabel:SetPoint("TOPLEFT", absorbDisplayDrop, "BOTTOMLEFT", 16, -23)
            barTextureLabel:SetText("Bar texture (SharedMedia)")

            barTextureDrop = CreateFrame("Frame", "MSUF_BarTextureDropdown", barGroup, "UIDropDownMenuTemplate")
            MSUF_ExpandDropdownClickArea(barTextureDrop)
            barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)
            UIDropDownMenu_SetWidth(barTextureDrop, BAR_DROPDOWN_WIDTH)
			-- If LibSharedMedia is unavailable, keep this dropdown non-interactive to avoid invalid DB selections.
			if not MSUF_GetLSM() then
				UIDropDownMenu_DisableDropDown(barTextureDrop)
			end

            barTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
            barTextureDrop._msufTweakBarTexturePreview = true
            MSUF_MakeDropdownScrollable(barTextureDrop, 12)

            local barTexturePreview = _G.MSUF_BarTexturePreview
            if not barTexturePreview then
                barTexturePreview = CreateFrame("StatusBar", "MSUF_BarTexturePreview", barGroup)
            end
            barTexturePreview:SetParent(barGroup)
            barTexturePreview:SetSize(BAR_DROPDOWN_WIDTH, 10)
            barTexturePreview:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 20, -6)
            barTexturePreview:SetMinMaxValues(0, 1)
            barTexturePreview:SetValue(1)

            barTexturePreview:Hide()
            MSUF_KillMenuPreviewBar(barTexturePreview)
            barTextureInfo = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            barTextureInfo:SetPoint("TOPLEFT", barTexturePreview, "BOTTOMLEFT", 0, -6)
            barTextureInfo:SetText('Install "SharedMedia" (LibSharedMedia-3.0) to unlock more bar textures. Without it, the default Blizzard texture is used.')

            local function BarTexturePreview_Update(texName)
                -- Prefer the global resolver (covers both built-ins and SharedMedia keys).
                if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
                    local resolved = _G.MSUF_ResolveStatusbarTextureKey(texName)
                    if resolved then
                        barTexturePreview:SetStatusBarTexture(resolved)
                        return
                    end
                end

                local LSM = MSUF_GetLSM()
                if LSM and type(LSM.Fetch) == "function" then
                    local tex = LSM:Fetch("statusbar", texName, true)
                    if tex then
                        barTexturePreview:SetStatusBarTexture(tex)
                        return
                    end
                end

                -- Hard fallback
                barTexturePreview:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            end

            local function BarTextureDropdown_Initialize(self, level)
                EnsureDB()
                info = UIDropDownMenu_CreateInfo()
                current = (MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard"

                local LSM = MSUF_GetLSM()
                local list
                if LSM and type(LSM.List) == "function" then
                    list = LSM:List("statusbar")
                else
                    -- Fallback list if SharedMedia isn't available.
                    list = {
                        "Blizzard",
                        "Flat",
                        "RaidHP",
                        "RaidPower",
                        "Skills",
                        "Outline",
                        "TooltipBorder",
                        "DialogBG",
                        "Parchment",
                    }
                end
                if type(list) ~= "table" or #list == 0 then
                    list = { "Blizzard" }
                end

                table.sort(list, function(a, b)
                    a = tostring(a or "")
                    b = tostring(b or "")
                    return a:lower() < b:lower()
                end)

                for _, name in ipairs(list) do
                    info.text = name
                    info.value = name
                    info.func = function(btn)
                        EnsureDB()
                        MSUF_DB.general = MSUF_DB.general or {}
                        MSUF_DB.general.barTexture = btn.value
                        BarTexturePreview_Update(btn.value)
                        MSUF_TryApplyBarTextureLive()
                        UIDropDownMenu_SetSelectedValue(barTextureDrop, btn.value)
                        UIDropDownMenu_SetText(barTextureDrop, btn.value)
                    end
                    info.checked = (name == current)

                    local swatchTex
                    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
                        swatchTex = _G.MSUF_ResolveStatusbarTextureKey(name)
                    elseif LSM and type(LSM.Fetch) == "function" then
                        swatchTex = LSM:Fetch("statusbar", name, true)
                    end

                    if swatchTex then
                        info.icon = swatchTex
                        info.iconInfo = {
                            tCoordLeft = 0,
                            tCoordRight = 0.85,
                            tCoordTop = 0,
                            tCoordBottom = 1,
                            iconWidth = 80,
                            iconHeight = 12,
                        }
                    else
                        info.icon = nil
                        info.iconInfo = nil
                    end

                    UIDropDownMenu_AddButton(info, level)
                end
            end

            UIDropDownMenu_Initialize(barTextureDrop, BarTextureDropdown_Initialize)

            EnsureDB()
            local initTex = (MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard"
            UIDropDownMenu_SetSelectedValue(barTextureDrop, initTex)
            UIDropDownMenu_SetText(barTextureDrop, initTex)
            BarTexturePreview_Update(initTex)

            if MSUF_GetLSM() then
                barTextureInfo:Hide()
            else
                barTextureInfo:Show()
            end
        end

        do -- Bar background texture dropdown
            barBgTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            barBgTextureLabel:SetPoint("TOPLEFT", _G.MSUF_BarTexturePreview, "BOTTOMLEFT", -20, -40)
            barBgTextureLabel:SetText("Bar background texture")

            barBgTextureDrop = CreateFrame("Frame", "MSUF_BarBackgroundTextureDropdown", barGroup, "UIDropDownMenuTemplate")
            MSUF_ExpandDropdownClickArea(barBgTextureDrop)
            barBgTextureDrop:SetPoint("TOPLEFT", barBgTextureLabel, "BOTTOMLEFT", -16, -4)
            UIDropDownMenu_SetWidth(barBgTextureDrop, BAR_DROPDOWN_WIDTH)
			-- If LibSharedMedia is unavailable, keep this dropdown non-interactive to avoid invalid DB selections.
			if not MSUF_GetLSM() then
				UIDropDownMenu_DisableDropDown(barBgTextureDrop)
			end

            barBgTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
            barBgTextureDrop._msufTweakBarTexturePreview = true
            MSUF_MakeDropdownScrollable(barBgTextureDrop, 12)

            local function BarBgTextureDropdown_Initialize(self, level)
                EnsureDB()
                info = UIDropDownMenu_CreateInfo()
                local g = (MSUF_DB and MSUF_DB.general) or {}
                local currentBg = g.barBackgroundTexture

                -- Special: empty value means "use the same texture as the foreground".
                info.text = "Use foreground texture"
                info.value = ""
                info.func = function(btn)
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barBackgroundTexture = ""
                    MSUF_TryApplyBarTextureLive()
                    UIDropDownMenu_SetSelectedValue(barBgTextureDrop, "")
                    UIDropDownMenu_SetText(barBgTextureDrop, "Use foreground texture")
                end
                info.checked = (currentBg == nil or currentBg == "")
                info.notCheckable = nil
                UIDropDownMenu_AddButton(info, level)

                MSUF_AddDropdownSeparator(level)

                local LSM = MSUF_GetLSM()
                local list
                if LSM and type(LSM.List) == "function" then
                    list = LSM:List("statusbar")
                else
                    list = {
                        "Blizzard",
                        "Flat",
                        "RaidHP",
                        "RaidPower",
                        "Skills",
                        "Outline",
                        "TooltipBorder",
                        "DialogBG",
                        "Parchment",
                    }
                end
                if type(list) ~= "table" or #list == 0 then
                    list = { "Blizzard" }
                end

                table.sort(list, function(a, b)
                    a = tostring(a or "")
                    b = tostring(b or "")
                    return a:lower() < b:lower()
                end)

                for _, name in ipairs(list) do
                    info.text = name
                    info.value = name
                    info.func = function(btn)
                        EnsureDB()
                        MSUF_DB.general = MSUF_DB.general or {}
                        MSUF_DB.general.barBackgroundTexture = btn.value
                        MSUF_TryApplyBarTextureLive()
                        UIDropDownMenu_SetSelectedValue(barBgTextureDrop, btn.value)
                        UIDropDownMenu_SetText(barBgTextureDrop, btn.value)
                    end
                    info.checked = (name == currentBg)

                    local swatchTex
                    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
                        swatchTex = _G.MSUF_ResolveStatusbarTextureKey(name)
                    elseif LSM and type(LSM.Fetch) == "function" then
                        swatchTex = LSM:Fetch("statusbar", name, true)
                    end

                    if swatchTex then
                        info.icon = swatchTex
                        info.iconInfo = {
                            tCoordLeft = 0,
                            tCoordRight = 0.85,
                            tCoordTop = 0,
                            tCoordBottom = 1,
                            iconWidth = 80,
                            iconHeight = 12,
                        }
                    else
                        info.icon = nil
                        info.iconInfo = nil
                    end

                    UIDropDownMenu_AddButton(info, level)
                end
            end

            UIDropDownMenu_Initialize(barBgTextureDrop, BarBgTextureDropdown_Initialize)

            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            local initBg = g.barBackgroundTexture
            if initBg == nil or initBg == "" then
                UIDropDownMenu_SetSelectedValue(barBgTextureDrop, "")
                UIDropDownMenu_SetText(barBgTextureDrop, "Use foreground texture")
            else
                UIDropDownMenu_SetSelectedValue(barBgTextureDrop, initBg)
                UIDropDownMenu_SetText(barBgTextureDrop, initBg)
            end
        end

        local function MSUF_UpdateBarTextureDropdown()
            EnsureDB()


			-- Keep dropdown interactivity in sync with LibSharedMedia availability.
			local _lsm = MSUF_GetLSM()
			if _lsm and type(_G.UIDropDownMenu_EnableDropDown) == "function" then
				UIDropDownMenu_EnableDropDown(barTextureDrop)
				UIDropDownMenu_EnableDropDown(barBgTextureDrop)
			elseif not _lsm and type(_G.UIDropDownMenu_DisableDropDown) == "function" then
				UIDropDownMenu_DisableDropDown(barTextureDrop)
				UIDropDownMenu_DisableDropDown(barBgTextureDrop)
			end

            if type(UIDropDownMenu_SetWidth) == "function" then
                UIDropDownMenu_SetWidth(barTextureDrop, 260)
                UIDropDownMenu_SetWidth(barBgTextureDrop, 260)
            end

            local initTex = (MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard"
            UIDropDownMenu_SetSelectedValue(barTextureDrop, initTex)
            UIDropDownMenu_SetText(barTextureDrop, initTex)

            local initBg = (MSUF_DB.general and MSUF_DB.general.barBackgroundTexture) or ""
            if initBg == nil or initBg == "" then
                UIDropDownMenu_SetSelectedValue(barBgTextureDrop, "")
                UIDropDownMenu_SetText(barBgTextureDrop, "Use foreground texture")
            else
                UIDropDownMenu_SetSelectedValue(barBgTextureDrop, initBg)
                UIDropDownMenu_SetText(barBgTextureDrop, initBg)
            end
        end

-- Unitframe bar outline (replaces legacy border toggle + border style dropdown)
-- 0 = disabled, 1..6 = thickness in pixels (expands OUTSIDE the HP bar like castbar outline)
barOutlineThicknessSlider = CreateLabeledSlider(
    "MSUF_BarOutlineThicknessSlider",
    "Outline thickness",
    barGroup,
    0, 6, 1,
    16, -350
)
-- Initialize the numeric box to the saved value immediately (otherwise it stays empty until changed).
do
    EnsureDB()
    local bars = (MSUF_DB and MSUF_DB.bars) or {}
    local t = tonumber(bars.barOutlineThickness)
    if type(t) ~= "number" then t = 1 end
    t = math.floor(t + 0.5)
    if t < 0 then t = 0 elseif t > 6 then t = 6 end
    MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t)
end

-- Bars menu style: boxed layout like the new Castbar/Focus Kick menus
-- (Two framed columns: Bar appearance / Power Bar Settings)
do
    -- Create panels once
    if not _G["MSUF_BarsMenuPanelLeft"] then
        local function SetupPanel(panel)
            panel:SetBackdrop({
                bgFile   = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
                edgeFile = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.20)
            panel:SetBackdropBorderColor(1, 1, 1, 0.15)
        end

        local leftPanel = CreateFrame("Frame", "MSUF_BarsMenuPanelLeft", barGroup, "BackdropTemplate")
        leftPanel:SetSize(330, 610)
        leftPanel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -110)
        SetupPanel(leftPanel)

        local rightPanel = CreateFrame("Frame", "MSUF_BarsMenuPanelRight", barGroup, "BackdropTemplate")
        rightPanel:SetSize(320, 610)
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
        SetupPanel(rightPanel)

        local leftHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        leftHeader:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 16, -12)
        leftHeader:SetText("Bar appearance")

        local rightHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        rightHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -12)
        rightHeader:SetText("Power Bar Settings")

        -- Section labels in left panel
        local absorbHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        absorbHeader:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -18)
        absorbHeader:SetText("Absorb Display")
        _G.MSUF_BarsMenuAbsorbHeader = absorbHeader

        local texHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        texHeader:SetText("Bar texture (SharedMedia)")
        _G.MSUF_BarsMenuTexturesHeader = texHeader

        local gradHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        gradHeader:SetText("Gradient Options")
        _G.MSUF_BarsMenuGradientHeader = gradHeader

        -- Section label in right panel
        local borderHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        borderHeader:SetText("Border & Text Options")
        _G.MSUF_BarsMenuBorderHeader = borderHeader

        -- Inline-dropdown helper
        -- Label sits on the left; value text can be RIGHT-aligned (default)
        -- or CENTERed (used for SharedMedia texture dropdowns so the chosen
        -- texture name is more readable).
        local function MakeInlineDropdown(drop, labelText, labelOffsetX, valueAlign)
            labelOffsetX = (labelOffsetX ~= nil) and labelOffsetX or 28
            valueAlign = valueAlign or "RIGHT"
            if not drop or not labelText then return end
            local name = drop:GetName()
            if not name then return end

            local txt = _G[name .. "Text"]
            if txt then
                txt:ClearAllPoints()
                if valueAlign == "CENTER" then
                    -- Centered value: keep it away from the arrow on the right.
                    txt:SetPoint("CENTER", drop, "CENTER", 18, 2)
                    txt:SetWidth(170)
                    txt:SetJustifyH("CENTER")
                    if txt.SetWordWrap then txt:SetWordWrap(false) end
                else
                    -- Right-aligned value.
                    -- Give the value text a real width so it doesn't collapse into 2-3 chars.
                    txt:SetPoint("LEFT",  drop, "LEFT", 120, 2)
                    txt:SetPoint("RIGHT", drop, "RIGHT", -30, 2)
                    txt:SetJustifyH("RIGHT")
                end
                if txt.SetFontObject then
                    txt:SetFontObject("GameFontNormalSmall")
                end
                txt:SetTextColor(0.95, 0.95, 0.95, 1)
            end

            if not drop._msufInlineLabel then
                local lab = drop:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                lab:SetPoint("LEFT", drop, "LEFT", labelOffsetX, 2)
                lab:SetTextColor(0.85, 0.85, 0.85, 1)
                if labelOffsetX and labelOffsetX ~= 28 then
                    lab:SetWidth(90)
                    lab:SetJustifyH("CENTER")
                else
                    lab:SetWidth(0)
                    lab:SetJustifyH("LEFT")
                end
                drop._msufInlineLabel = lab
            end
            drop._msufInlineLabel:SetText(labelText)
        end

        _G.MSUF_BarsMenu_MakeInlineDropdown = MakeInlineDropdown
    end

    local leftPanel  = _G["MSUF_BarsMenuPanelLeft"]
    local rightPanel = _G["MSUF_BarsMenuPanelRight"]

    -- Enforce layout (so tweaks apply even if panels already exist)
    if leftPanel then
        leftPanel:ClearAllPoints()
        leftPanel:SetSize(330, 610)
        leftPanel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -110)
    end
    if rightPanel and leftPanel then
        rightPanel:ClearAllPoints()
        rightPanel:SetSize(320, 610)
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    end

    -- Hide old title if still around
    if barsTitle then barsTitle:Hide() end

    -- Absorb section
    if absorbDisplayLabel and _G.MSUF_BarsMenuAbsorbHeader then
        absorbDisplayLabel:ClearAllPoints()
        absorbDisplayLabel:SetPoint("TOPLEFT", _G.MSUF_BarsMenuAbsorbHeader, "TOPLEFT", 0, 0)
        absorbDisplayLabel:SetText("Absorb Display")
    end
    -- Divider line under "Absorb Display"
    local absorbLine = leftPanel and leftPanel.MSUF_SectionLine_Absorb
    if leftPanel then
        if not absorbLine then
            absorbLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Absorb = absorbLine
            absorbLine:SetColorTexture(1, 1, 1, 0.20)
            absorbLine:SetHeight(1)
        end
        absorbLine:ClearAllPoints()
        if absorbDisplayLabel then
            absorbLine:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
            absorbLine:SetWidth(296)
            absorbLine:Show()
        else
            absorbLine:Hide()
        end
    end

    if absorbDisplayDrop and absorbDisplayLabel then
        absorbDisplayDrop:ClearAllPoints()
        if absorbLine and absorbLine:IsShown() then
            absorbDisplayDrop:SetPoint("TOPLEFT", absorbLine, "BOTTOMLEFT", 0, -6)
        else
            absorbDisplayDrop:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
        end
        UIDropDownMenu_SetWidth(absorbDisplayDrop, 260)
    end

-- Textures section (foreground + background)
    local texHeader = _G.MSUF_BarsMenuTexturesHeader
    if texHeader and (absorbAnchorDrop or absorbDisplayDrop) and leftPanel then
        texHeader:ClearAllPoints()
        local _absAnchor = absorbAnchorDrop or absorbDisplayDrop
        texHeader:SetPoint("TOPLEFT", _absAnchor, "BOTTOMLEFT", 16, -18)
    end

    if barTextureLabel and texHeader then
        barTextureLabel:ClearAllPoints()
        barTextureLabel:SetPoint("TOPLEFT", texHeader, "TOPLEFT", 0, 0)
        barTextureLabel:SetText("Bar texture (SharedMedia)")
    end

    -- Divider line under "Bar texture (SharedMedia)"
    local texturesLine = leftPanel and leftPanel.MSUF_SectionLine_Textures
    if leftPanel then
        if not texturesLine then
            texturesLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Textures = texturesLine
            texturesLine:SetColorTexture(1, 1, 1, 0.20)
            texturesLine:SetHeight(1)
        end
        texturesLine:ClearAllPoints()
        if barTextureLabel then
            texturesLine:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)
            texturesLine:SetWidth(296)
            texturesLine:Show()
        else
            texturesLine:Hide()
        end
    end

    if barTextureDrop and barTextureLabel then
        barTextureDrop:ClearAllPoints()
        if texturesLine and texturesLine:IsShown() then
            barTextureDrop:SetPoint("TOPLEFT", texturesLine, "BOTTOMLEFT", 0, -6)
        else
            barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -6)
        end
        UIDropDownMenu_SetWidth(barTextureDrop, 260)
        if _G.MSUF_BarsMenu_MakeInlineDropdown then
            -- Keep label on the left, show the selected texture name centered.
            _G.MSUF_BarsMenu_MakeInlineDropdown(barTextureDrop, "Foreground", nil, "CENTER")
        end
    end

    if barBgTextureLabel and barTextureDrop then
        barBgTextureLabel:ClearAllPoints()
        barBgTextureLabel:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 16, -12)
        barBgTextureLabel:SetText("") -- hidden; we use inline label
        barBgTextureLabel:Hide()
    end

    if barBgTextureDrop and barTextureDrop then
        barBgTextureDrop:ClearAllPoints()
        barBgTextureDrop:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 0, -20)
        UIDropDownMenu_SetWidth(barBgTextureDrop, 260)
        if _G.MSUF_BarsMenu_MakeInlineDropdown then
            -- Keep label on the left, show the selected texture name centered.
            _G.MSUF_BarsMenu_MakeInlineDropdown(barBgTextureDrop, "Background", nil, "CENTER")
        end
    end

    -- If the bar texture preview exists (LSM mode), hide it (mockup-style)
    if _G.MSUF_BarTexturePreview then
        _G.MSUF_BarTexturePreview:Hide()
    end

    if barTextureInfo then
        barTextureInfo:Hide()
    end

    -- Gradient section
    local gradHeader = _G.MSUF_BarsMenuGradientHeader
    local gradAnchor = barBgTextureDrop or barTextureDrop or absorbDisplayDrop
    if gradHeader and gradAnchor then
        gradHeader:ClearAllPoints()
        gradHeader:SetPoint("TOPLEFT", gradAnchor, "BOTTOMLEFT", 16, -18)
        gradHeader:Show()
    end

    -- Divider line under "Gradient Options"
    local gradLine = leftPanel and leftPanel.MSUF_SectionLine_Gradient
    if leftPanel then
        if not gradLine then
            gradLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Gradient = gradLine
            gradLine:SetColorTexture(1, 1, 1, 0.20)
            gradLine:SetHeight(1)
        end
        gradLine:ClearAllPoints()
        if gradHeader then
            gradLine:SetPoint("TOPLEFT", gradHeader, "BOTTOMLEFT", -16, -4)
            gradLine:SetWidth(296)
            gradLine:Show()
        else
            gradLine:Hide()
        end
    end

    if gradientCheck and gradHeader then
        gradientCheck:ClearAllPoints()
        if gradLine and gradLine:IsShown() then
            gradientCheck:SetPoint("TOPLEFT", gradLine, "BOTTOMLEFT", 16, -14)
        else
            gradientCheck:SetPoint("TOPLEFT", gradHeader, "BOTTOMLEFT", 0, -18)
        end
    end

if gradientDirPad and gradientCheck then
        gradientDirPad:ClearAllPoints()
        -- Fixed X so long labels can't push the pad into the right column.
        gradientDirPad:SetPoint("TOPLEFT", gradientCheck, "TOPLEFT", 196, -3)
        gradientDirPad:Show()
    end

    -- Keep legacy slider hidden ("bar weg")
    if gradientSlider then
        gradientSlider:Hide()
        if gradientSlider.editBox then gradientSlider.editBox:Hide() end
        if gradientSlider.minusButton then gradientSlider.minusButton:Hide() end
        if gradientSlider.plusButton then gradientSlider.plusButton:Hide() end
    end

    -- Right panel: power bar settings
    if targetPowerBarCheck and rightPanel then
        targetPowerBarCheck:ClearAllPoints()
        targetPowerBarCheck:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -50)
    end
    if bossPowerBarCheck and targetPowerBarCheck then
        bossPowerBarCheck:ClearAllPoints()
        bossPowerBarCheck:SetPoint("TOPLEFT", targetPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if playerPowerBarCheck and bossPowerBarCheck then
        playerPowerBarCheck:ClearAllPoints()
        playerPowerBarCheck:SetPoint("TOPLEFT", bossPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if focusPowerBarCheck and playerPowerBarCheck then
        focusPowerBarCheck:ClearAllPoints()
        focusPowerBarCheck:SetPoint("TOPLEFT", playerPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end

    if powerBarHeightLabel and focusPowerBarCheck then
        powerBarHeightLabel:ClearAllPoints()
        powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -18)
    end
    if powerBarHeightEdit and powerBarHeightLabel then
        powerBarHeightEdit:ClearAllPoints()
        powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 10, 0)
    end


    if powerBarEmbedCheck and powerBarHeightLabel then
        powerBarEmbedCheck:ClearAllPoints()
        powerBarEmbedCheck:SetPoint("TOPLEFT", powerBarHeightLabel, "BOTTOMLEFT", 0, -10)
    end
-- Bar outline thickness: render as a section TITLE (like "Gradient Options")
-- and place the slider under a divider line (hide the slider's own title text).
if _G.MSUF_BarsMenuBorderHeader then
    _G.MSUF_BarsMenuBorderHeader:Hide()
end

local outlineAnchor = gradientCheck or gradLine or gradHeader
local outlineHeader = leftPanel and leftPanel.MSUF_SectionHeader_Outline
if leftPanel and not outlineHeader then
    outlineHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    leftPanel.MSUF_SectionHeader_Outline = outlineHeader
    outlineHeader:SetText("Outline thickness")
end

if outlineHeader and outlineAnchor then
    outlineHeader:ClearAllPoints()
    if gradientDirPad and gradientCheck then
        -- Align section to the left edge, but place it BELOW the pad (pad is taller than the checkbox row).
        outlineHeader:SetPoint("TOPLEFT", gradientDirPad, "BOTTOMLEFT", -196, -18)
    else
        outlineHeader:SetPoint("TOPLEFT", outlineAnchor, "BOTTOMLEFT", 0, -18)
    end
    outlineHeader:Show()
end

local outlineLine = leftPanel and leftPanel.MSUF_SectionLine_Outline
if leftPanel then
    if not outlineLine then
        outlineLine = leftPanel:CreateTexture(nil, "ARTWORK")
        leftPanel.MSUF_SectionLine_Outline = outlineLine
        outlineLine:SetColorTexture(1, 1, 1, 0.20)
        outlineLine:SetHeight(1)
    end

    outlineLine:ClearAllPoints()
    if outlineHeader then
        outlineLine:SetPoint("TOPLEFT", outlineHeader, "BOTTOMLEFT", -16, -4)
        outlineLine:SetWidth(296)
        outlineLine:Show()
    else
        outlineLine:Hide()
    end
end

if barOutlineThicknessSlider and outlineLine and outlineLine:IsShown() then
    barOutlineThicknessSlider:ClearAllPoints()
    barOutlineThicknessSlider:SetPoint("TOPLEFT", outlineLine, "BOTTOMLEFT", 16, -14)
    barOutlineThicknessSlider:SetWidth(280)

    -- Hide the slider's built-in title text; we use the section header above.
    local sName = barOutlineThicknessSlider.GetName and barOutlineThicknessSlider:GetName()
    if sName and _G then
        local t = _G[sName .. "Text"]
        if t then
            t:SetText("")
            t:Hide()
        end
    end
end

-- Right panel: text modes start under power bar height

    if hpModeLabel then
        hpModeLabel:ClearAllPoints()
        if powerBarEmbedCheck then
            hpModeLabel:SetPoint("TOPLEFT", powerBarEmbedCheck, "BOTTOMLEFT", 0, -28)
        elseif powerBarHeightLabel then
            hpModeLabel:SetPoint("TOPLEFT", powerBarHeightLabel, "BOTTOMLEFT", 0, -28)
        end
    end

    local textModesLine
    if rightPanel then
        if not rightPanel.MSUF_SectionLine_TextModes then
            local ln = rightPanel:CreateTexture(nil, "ARTWORK")
            rightPanel.MSUF_SectionLine_TextModes = ln
            ln:SetColorTexture(1, 1, 1, 0.20)
            ln:SetHeight(1)
        end
        textModesLine = rightPanel.MSUF_SectionLine_TextModes
    end

    if textModesLine and hpModeLabel then
        textModesLine:ClearAllPoints()
        textModesLine:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)
        textModesLine:SetWidth(286)
        textModesLine:Show()
    elseif textModesLine then
        textModesLine:Hide()
    end

    if hpModeDrop and hpModeLabel then
        hpModeDrop:ClearAllPoints()
        if textModesLine and textModesLine:IsShown() then
            hpModeDrop:SetPoint("TOPLEFT", textModesLine, "BOTTOMLEFT", 0, -6)
        else
            hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -6)
        end
        UIDropDownMenu_SetWidth(hpModeDrop, 260)
    end
    -- Keep Text Separators block stable on resize (no regressions)
    if sepHeader and powerModeDrop then
        sepHeader:ClearAllPoints()
        sepHeader:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 16, -12)
    end
    if hpSepLabel and sepHeader then
        hpSepLabel:ClearAllPoints()
        hpSepLabel:SetPoint("TOPLEFT", sepHeader, "BOTTOMLEFT", 0, -10)
    end
    if powerSepLabel and hpSepLabel then
        powerSepLabel:ClearAllPoints()
        powerSepLabel:SetPoint("LEFT", hpSepLabel, "RIGHT", 120, 0)
    end
    if hpSepDrop and hpSepLabel then
        hpSepDrop:ClearAllPoints()
        -- Move both separator dropdowns down by 7px (relative to the prior -9 offset)
        hpSepDrop:SetPoint("TOPLEFT", hpSepLabel, "BOTTOMLEFT", -16, -16)
    end
    if powerSepDrop and powerSepLabel then
        powerSepDrop:ClearAllPoints()
        powerSepDrop:SetPoint("TOPLEFT", powerSepLabel, "BOTTOMLEFT", -16, -16)
    end
    if hpSpacerCheck and hpSepDrop then
        hpSpacerCheck:ClearAllPoints()
        hpSpacerCheck:SetPoint("TOPLEFT", hpSepDrop, "BOTTOMLEFT", 16, -14)
    end
    if hpSpacerSlider and hpSpacerCheck then
        hpSpacerSlider:ClearAllPoints()
        hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -30)
        if hpSpacerSlider.SetWidth then hpSpacerSlider:SetWidth(260) end
    end
end

-- Keep the Bars tab toggles/controls visually in sync (same behavior as Fonts/Misc toggles)
local function MSUF_SyncBarsTabToggles()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local b = (MSUF_DB and MSUF_DB.bars) or {}

    local function SafeToggleUpdate(cb)
        if cb and cb.__msufToggleUpdate then
            pcall(cb.__msufToggleUpdate)
        end
    end

    local gradEnabled = (g.enableGradient == true)
    if gradientCheck then
        gradientCheck:SetChecked(gradEnabled)
        SafeToggleUpdate(gradientCheck)
    end

    if gradientDirPad then
        if gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
        if gradientDirPad.SetEnabledVisual then gradientDirPad:SetEnabledVisual(gradEnabled) end
    end

    if gradientSlider then
        local strength = tonumber(g.gradientStrength)
        if type(strength) ~= 'number' then strength = 0.45 end
        if strength < 0 then strength = 0 elseif strength > 1 then strength = 1 end
                MSUF_SetLabeledSliderValue(gradientSlider, strength * 100)
        MSUF_SetLabeledSliderEnabled(gradientSlider, gradEnabled)
    end

    -- Bar outline thickness (0..6) should always show the current value in the editbox on open.
    if barOutlineThicknessSlider then
        local t = tonumber(b.barOutlineThickness)
        if type(t) ~= "number" then t = 1 end
        t = math.floor(t + 0.5)
        if t < 0 then t = 0 elseif t > 6 then t = 6 end
        MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t)
        MSUF_SetLabeledSliderEnabled(barOutlineThicknessSlider, true)
    end

    if targetPowerBarCheck then
        targetPowerBarCheck:SetChecked(b.showTargetPowerBar and true or false)
        SafeToggleUpdate(targetPowerBarCheck)
    end
    if bossPowerBarCheck then
        bossPowerBarCheck:SetChecked(b.showBossPowerBar and true or false)
        SafeToggleUpdate(bossPowerBarCheck)
    end
    if playerPowerBarCheck then
        playerPowerBarCheck:SetChecked(b.showPlayerPowerBar and true or false)
        SafeToggleUpdate(playerPowerBarCheck)
    end
    if focusPowerBarCheck then
        focusPowerBarCheck:SetChecked(b.showFocusPowerBar and true or false)
        SafeToggleUpdate(focusPowerBarCheck)
    end

    if powerBarEmbedCheck then
        powerBarEmbedCheck:SetChecked(b.embedPowerBarIntoHealth and true or false)
        SafeToggleUpdate(powerBarEmbedCheck)
    end

    -- Power bar height: show the current value + disable if NO powerbars are enabled anywhere.
    if powerBarHeightEdit then
        local v = tonumber(b.powerBarHeight)
        if type(v) ~= 'number' then v = 3 end
        if v < 3 then v = 3 elseif v > 50 then v = 50 end
        if (not powerBarHeightEdit.HasFocus) or (not powerBarHeightEdit:HasFocus()) then
            powerBarHeightEdit:SetText(tostring(v))
        end
    end

    local anyPBEnabled = true
    if (b.showTargetPowerBar == false) and (b.showBossPowerBar == false) and (b.showPlayerPowerBar == false) and (b.showFocusPowerBar == false) then
        anyPBEnabled = false
    end

    if powerBarHeightLabel and powerBarHeightLabel.SetTextColor then
        if anyPBEnabled then
            powerBarHeightLabel:SetTextColor(1, 1, 1, 1)
        else
            powerBarHeightLabel:SetTextColor(0.35, 0.35, 0.35, 1)
        end
    end

    if powerBarHeightEdit then
        if anyPBEnabled then
            if powerBarHeightEdit.Enable then powerBarHeightEdit:Enable() end
            if powerBarHeightEdit.SetEnabled then powerBarHeightEdit:SetEnabled(true) end
            if powerBarHeightEdit.EnableMouse then powerBarHeightEdit:EnableMouse(true) end
            if powerBarHeightEdit.SetTextColor then powerBarHeightEdit:SetTextColor(1, 1, 1) end
            powerBarHeightEdit:SetAlpha(1)
        else
            if powerBarHeightEdit.Disable then powerBarHeightEdit:Disable() end
            if powerBarHeightEdit.SetEnabled then powerBarHeightEdit:SetEnabled(false) end
            if powerBarHeightEdit.EnableMouse then powerBarHeightEdit:EnableMouse(false) end
            if powerBarHeightEdit.ClearFocus then powerBarHeightEdit:ClearFocus() end
            if powerBarHeightEdit.SetTextColor then powerBarHeightEdit:SetTextColor(0.55, 0.55, 0.55) end
            powerBarHeightEdit:SetAlpha(0.55)
        end
    end

    if powerBarEmbedCheck then
        if anyPBEnabled then
            if powerBarEmbedCheck.Enable then powerBarEmbedCheck:Enable() end
            if powerBarEmbedCheck.SetEnabled then powerBarEmbedCheck:SetEnabled(true) end
            if powerBarEmbedCheck.EnableMouse then powerBarEmbedCheck:EnableMouse(true) end
            powerBarEmbedCheck:SetAlpha(1)
        else
            if powerBarEmbedCheck.Disable then powerBarEmbedCheck:Disable() end
            if powerBarEmbedCheck.SetEnabled then powerBarEmbedCheck:SetEnabled(false) end
            if powerBarEmbedCheck.EnableMouse then powerBarEmbedCheck:EnableMouse(false) end
            powerBarEmbedCheck:SetAlpha(0.55)
        end
    end
end

if barGroup and barGroup.HookScript then
    barGroup:HookScript('OnShow', MSUF_SyncBarsTabToggles)
end

gradientCheck:SetScript("OnClick", function(self)
    EnsureDB()
    MSUF_DB.general.enableGradient = self:GetChecked() and true or false
    if gradientDirPad and gradientDirPad.SyncFromDB then
        gradientDirPad:SyncFromDB()
    end
    ApplyAllSettings()
    if MSUF_SyncBarsTabToggles then MSUF_SyncBarsTabToggles() end
end)

gradientSlider.onValueChanged = function(self, value)
    if self and self.MSUF_SkipCallback then return end
    EnsureDB()
    MSUF_DB.general.gradientStrength = (value or 0) / 100
    ApplyAllSettings()
end

if barOutlineThicknessSlider then
    barOutlineThicknessSlider.onValueChanged = function(self, value)
        EnsureDB()
        MSUF_DB.bars = MSUF_DB.bars or {}
        local v = tonumber(value) or 0
        -- keep it integer + clamp
        v = math.floor(v + 0.5)
        if v < 0 then v = 0 end
        if v > 6 then v = 6 end
        MSUF_DB.bars.barOutlineThickness = v
        ApplyAllSettings()
    end
end

    if targetPowerBarCheck then
        targetPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showTargetPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
            if MSUF_SyncBarsTabToggles then MSUF_SyncBarsTabToggles() end
        end)
    end

    if bossPowerBarCheck then
        bossPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showBossPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
            if MSUF_SyncBarsTabToggles then MSUF_SyncBarsTabToggles() end
        end)
    end

    if playerPowerBarCheck then
        playerPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showPlayerPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
            if MSUF_SyncBarsTabToggles then MSUF_SyncBarsTabToggles() end
        end)
    end

    if focusPowerBarCheck then
        focusPowerBarCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.showFocusPowerBar = self:GetChecked() and true or false
            ApplyAllSettings()
            if MSUF_SyncBarsTabToggles then MSUF_SyncBarsTabToggles() end
        end)
    end

    if powerBarEmbedCheck then
        powerBarEmbedCheck:SetScript("OnClick", function(self)
            EnsureDB()
            MSUF_DB.bars = MSUF_DB.bars or {}
            MSUF_DB.bars.embedPowerBarIntoHealth = self:GetChecked() and true or false
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == 'function' then
                _G.MSUF_ApplyPowerBarEmbedLayout_All()
            end
            ApplyAllSettings()
            if MSUF_SyncBarsTabToggles then MSUF_SyncBarsTabToggles() end
        end)
    end

    if powerBarHeightEdit then
        powerBarHeightEdit:SetScript("OnEnterPressed", function(self)
            MSUF_UpdatePowerBarHeightFromEdit(self)
            self:ClearFocus()
        end)
        powerBarHeightEdit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        powerBarHeightEdit:SetScript("OnEditFocusLost", function(self)
            MSUF_UpdatePowerBarHeightFromEdit(self)
        end)
    end

    panel.anchorEdit                 = anchorEdit

    panel.fontDrop                   = fontDrop
    panel.fontColorDrop              = fontColorDrop

    panel.nameFontSizeSlider         = nameFontSizeSlider
    panel.hpFontSizeSlider           = hpFontSizeSlider
    panel.powerFontSizeSlider        = powerFontSizeSlider
    panel.fontSizeSlider             = fontSizeSlider  -- falls vorhanden, sonst einfach nil

    panel.boldCheck                  = boldCheck
    panel.nameClassColorCheck        = nameClassColorCheck
    panel.npcNameRedCheck            = npcNameRedCheck
    panel.shortenNamesCheck          = shortenNamesCheck
    panel.shortenNameClipSideDrop   = shortenNameClipSideDrop
    panel.textBackdropCheck          = textBackdropCheck

    panel.highlightEnableCheck       = highlightEnableCheck
    panel.highlightColorDrop         = highlightColorDrop

    panel.castbarSpellNameFontSizeSlider = castbarSpellNameFontSizeSlider
 panel.castbarShakeIntensitySlider   = castbarShakeIntensitySlider

    panel.gradientCheck              = gradientCheck
    panel.gradientSlider             = gradientSlider
    panel.gradientDirPad             = gradientDirPad or _G["MSUF_GradientDirectionPad"]

    panel.targetPowerBarCheck        = targetPowerBarCheck
    panel.bossPowerBarCheck          = bossPowerBarCheck
    panel.playerPowerBarCheck        = playerPowerBarCheck
    panel.focusPowerBarCheck         = focusPowerBarCheck
    panel.powerBarHeightEdit         = powerBarHeightEdit
    panel.powerBarEmbedCheck         = powerBarEmbedCheck

    panel.hpModeDrop                 = hpModeDrop
panel.barTextureDrop             = barTextureDrop
    panel.barOutlineThicknessSlider = barOutlineThicknessSlider

panel.frameWidthSlider   = frameWidthSlider
panel.frameHeightSlider  = frameHeightSlider
panel.frameScaleSlider   = frameScaleSlider
panel.showPowerCheck     = showPowerCheck

panel.fontSizeSlider     = fontSizeSlider
panel.updateThrottleSlider = updateThrottleSlider
panel.powerBarHeightSlider = powerBarHeightSlider
panel.infoTooltipDisableCheck = infoTooltipDisableCheck

    function panel:LoadFromDB()
        EnsureDB()

        g = MSUF_DB.general or {}
        bars = MSUF_DB.bars    or {}

        anchorEdit = self.anchorEdit
        anchorCheck = self.anchorCheck

        fontDrop = self.fontDrop
        fontColorDrop = self.fontColorDrop

        nameFontSizeSlider = self.nameFontSizeSlider
        hpFontSizeSlider = self.hpFontSizeSlider
        powerFontSizeSlider = self.powerFontSizeSlider
        fontSizeSlider = self.fontSizeSlider
        boldCheck = self.boldCheck
        nameClassColorCheck = self.nameClassColorCheck
        npcNameRedCheck = self.npcNameRedCheck
        shortenNamesCheck = self.shortenNamesCheck
        textBackdropCheck = self.textBackdropCheck

        highlightEnableCheck = self.highlightEnableCheck
        highlightColorDrop = self.highlightColorDrop

        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        castbarShakeIntensitySlider = self.castbarShakeIntensitySlider

        gradientCheck = self.gradientCheck
        gradientSlider = self.gradientSlider
        gradientDirPad = self.gradientDirPad

        targetPowerBarCheck = self.targetPowerBarCheck
        bossPowerBarCheck = self.bossPowerBarCheck
        playerPowerBarCheck = self.playerPowerBarCheck
        focusPowerBarCheck = self.focusPowerBarCheck
        powerBarHeightEdit = self.powerBarHeightEdit

        hpModeDrop = self.hpModeDrop
        barOutlineThicknessSlider = self.barOutlineThicknessSlider
        bossSpacingSlider = self.bossSpacingSlider
        if anchorEdit then
            anchorEdit:SetText(g.anchorName or "UIParent")
        end
        if anchorCheck then
            anchorCheck:SetChecked(g.anchorToCooldown and true or false)
        end

        if fontDrop and g.fontKey then
            if (not fontChoices or #fontChoices == 0) and MSUF_RebuildFontChoices then
                MSUF_RebuildFontChoices()
            end

            UIDropDownMenu_SetSelectedValue(fontDrop, g.fontKey)

            local label = g.fontKey
            if fontChoices then
                for _, data in ipairs(fontChoices) do
                    if data.key == g.fontKey then
                        label = data.label
                        break
                    end
                end
            end

            UIDropDownMenu_SetText(fontDrop, label)
        end
        if fontDrop and g.fontKey then
            if (not fontChoices or #fontChoices == 0) and MSUF_RebuildFontChoices then
                MSUF_RebuildFontChoices()
            end

            UIDropDownMenu_SetSelectedValue(fontDrop, g.fontKey)

            local label = g.fontKey
            if fontChoices then
                for _, data in ipairs(fontChoices) do
                    if data.key == g.fontKey then
                        label = data.label
                        break
                    end
                end
            end

            UIDropDownMenu_SetText(fontDrop, label)
        end

        if nameFontSizeSlider then
            nameFontSizeSlider:SetValue(g.nameFontSize or g.fontSize or 14)
        end
        if hpFontSizeSlider then
            hpFontSizeSlider:SetValue(g.hpFontSize or g.fontSize or 14)
        end
        if powerFontSizeSlider then
            powerFontSizeSlider:SetValue(g.powerFontSize or g.fontSize or 14)
        end
        if castbarSpellNameFontSizeSlider then
            -- Castbar font size (0 = inherit/auto). Must be set here so the editbox shows the saved value immediately.
            castbarSpellNameFontSizeSlider:SetValue(g.castbarSpellNameFontSize or 0)
        end
        if fontSizeSlider then
            fontSizeSlider:SetValue(g.fontSize or 14)
        end

        if highlightEnableCheck then
            highlightEnableCheck:SetChecked(g.highlightEnabled ~= false)
        end

        if highlightColorDrop then
            local colorKey = g.highlightColor
            if type(colorKey) ~= "string" or not MSUF_FONT_COLORS[colorKey] then
                colorKey = "white"
                g.highlightColor = colorKey
            end

            UIDropDownMenu_SetSelectedValue(highlightColorDrop, colorKey)

            local label = colorKey
            if MSUF_COLOR_LIST then
                for _, opt in ipairs(MSUF_COLOR_LIST) do
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
        if bossSpacingSlider.editBox then
            bossSpacingSlider.editBox:Show()
        end
    else
        bossSpacingSlider:Hide()
        if bossSpacingSlider.editBox then
            bossSpacingSlider.editBox:Hide()
        end
    end
end

        if currentTabKey == "fonts" or currentTabKey == "bars" or currentTabKey == "misc" or currentTabKey == "profiles" then
            return
        end

        conf = MSUF_DB[currentKey]
        if not conf then return end

        if bossSpacingSlider and currentKey == "boss" then
            bossSpacingSlider:SetValue(conf.spacing or -36)
        end

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
            if v == nil then
                return default
            end
            return v
        end

        -- Player-only: mirror values into the compact stepper UI.
        if ns and ns.MSUF_Options_Player_ApplyFromDB then
            ns.MSUF_Options_Player_ApplyFromDB(self, currentKey, conf, g, GetOffsetValue)
        end
        end
    -- Player-only compact Text layout handlers are installed by Options\MSUF_Options_Player.lua
    if ns and ns.MSUF_Options_Player_InstallHandlers then
        ns.MSUF_Options_Player_InstallHandlers(panel, {
            getTabKey = function() return currentTabKey end,
            getKey    = function() return currentKey end,
            EnsureDB  = EnsureDB,
            ApplySettingsForKey = ApplySettingsForKey,
            CallUpdateAllFonts  = MSUF_CallUpdateAllFonts,
        })
    end

    -- Style all toggle labels: checked = white, unchecked = grey
    if MSUF_StyleAllToggles then
        MSUF_StyleAllToggles(panel)
    end
    panel.__MSUF_FullBuilt = true

SetCurrentKey("player")
panel:LoadFromDB()
MSUF_CallUpdateAllFonts()

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
if ns then
    ns.MSUF_MainCategory = rootCat
end

-- Ensure Legacy subcategory exists for this heavy panel.
if Settings and Settings.RegisterCanvasLayoutSubcategory and rootCat then
    if not (_G and _G.MSUF_LegacyCategory) then
        local legacyCat = Settings.RegisterCanvasLayoutSubcategory(rootCat, panel, (panel.name or "Legacy"))
        Settings.RegisterAddOnCategory(legacyCat)
        if _G then _G.MSUF_LegacyCategory = legacyCat end
    end
end

-- Sub-categories are safe to (re)register; patched versions build lazily on first open.
if ns and ns.MSUF_RegisterGameplayOptions then
    ns.MSUF_RegisterGameplayOptions(rootCat)
end

if ns and ns.MSUF_RegisterColorsOptions then
    ns.MSUF_RegisterColorsOptions(rootCat)
end

if ns and ns.MSUF_RegisterAurasOptions then
    ns.MSUF_RegisterAurasOptions(rootCat)
end

if ns and ns.MSUF_RegisterBossCastbarOptions then
    ns.MSUF_RegisterBossCastbarOptions(rootCat)
end
end

if panel and panel.LoadFromDB and not panel.__MSUF_OnShowHooked then
    panel.__MSUF_OnShowHooked = true
    panel:SetScript("OnShow", function(self)
        if self.LoadFromDB then
            self:LoadFromDB()
        end
    end)
end


if _G and not _G.__MSUF_LauncherAutoRegistered then
    _G.__MSUF_LauncherAutoRegistered = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if type(MSUF_RegisterOptionsCategoryLazy) == "function" then
                MSUF_RegisterOptionsCategoryLazy()
            end
        end)
    else
        if type(MSUF_RegisterOptionsCategoryLazy) == "function" then
            MSUF_RegisterOptionsCategoryLazy()
        end
    end
end
