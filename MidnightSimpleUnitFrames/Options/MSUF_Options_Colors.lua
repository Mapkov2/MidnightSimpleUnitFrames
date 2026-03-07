-- MSUF_Options_Colors.lua
-- Options panel for color settings (pure UX / UI).
-- All runtime Get/Set/Reset logic lives in MSUF_ColorsCore.lua
-- which loads first and exports via ns._colorsAPI.

local addonName, ns = ...
ns = ns or {}

------------------------------------------------------
-- Import core API (aliased to the same local names
-- the original monolithic file used, so zero changes
-- are needed in the panel builder body below).
------------------------------------------------------
local _API = ns._colorsAPI or {}

local PushVisualUpdates               = _API.PushVisualUpdates

local GetGlobalFontColor              = _API.GetGlobalFontColor
local SetGlobalFontColor              = _API.SetGlobalFontColor

local GetCastbarTextColor             = _API.GetCastbarTextColor
local SetCastbarTextColor             = _API.SetCastbarTextColor

local GetCastbarBorderColor           = _API.GetCastbarBorderColor
local SetCastbarBorderColor           = _API.SetCastbarBorderColor

-- NOTE: Castbar background + all Reset* functions are pulled from ns._colorsAPI
-- inside the panel builder to stay within Lua 5.1's 60-upvalue ceiling.

local GetInterruptibleCastColor       = _API.GetInterruptibleCastColor
local SetInterruptibleCastColor       = _API.SetInterruptibleCastColor
local GetNonInterruptibleCastColor    = _API.GetNonInterruptibleCastColor
local SetNonInterruptibleCastColor    = _API.SetNonInterruptibleCastColor
local GetInterruptFeedbackCastColor   = _API.GetInterruptFeedbackCastColor
local SetInterruptFeedbackCastColor   = _API.SetInterruptFeedbackCastColor

local GetPlayerCastbarOverrideEnabled = _API.GetPlayerCastbarOverrideEnabled
local SetPlayerCastbarOverrideEnabled = _API.SetPlayerCastbarOverrideEnabled
local GetPlayerCastbarOverrideMode    = _API.GetPlayerCastbarOverrideMode
local SetPlayerCastbarOverrideMode    = _API.SetPlayerCastbarOverrideMode
local GetPlayerCastbarOverrideColor   = _API.GetPlayerCastbarOverrideColor
local SetPlayerCastbarOverrideColor   = _API.SetPlayerCastbarOverrideColor

local CLASS_TOKENS                    = _API.CLASS_TOKENS
local GetClassColor                   = _API.GetClassColor
local SetClassColor                   = _API.SetClassColor

local GetClassBarBgColor              = _API.GetClassBarBgColor
local SetClassBarBgColor              = _API.SetClassBarBgColor

local GetBarBgMatchHP                 = _API.GetBarBgMatchHP
local SetBarBgMatchHP                 = _API.SetBarBgMatchHP

local GetNPCColor                     = _API.GetNPCColor
local SetNPCColor                     = _API.SetNPCColor

local GetPetFrameColor                = _API.GetPetFrameColor
local SetPetFrameColor                = _API.SetPetFrameColor

local GetAbsorbOverlayColor           = _API.GetAbsorbOverlayColor
local SetAbsorbOverlayColor           = _API.SetAbsorbOverlayColor
local GetHealAbsorbOverlayColor       = _API.GetHealAbsorbOverlayColor
local SetHealAbsorbOverlayColor       = _API.SetHealAbsorbOverlayColor

local GetPowerBarBackgroundColor      = _API.GetPowerBarBackgroundColor
local SetPowerBarBackgroundColor      = _API.SetPowerBarBackgroundColor

local GetAggroBorderColor             = _API.GetAggroBorderColor
local SetAggroBorderColor             = _API.SetAggroBorderColor

local GetPowerBarBackgroundMatchHP    = _API.GetPowerBarBackgroundMatchHP
local SetPowerBarBackgroundMatchHP    = _API.SetPowerBarBackgroundMatchHP

_API = nil  -- not needed after alias init; avoid accidental upvalue capture

------------------------------------------------------
-- Local shortcuts (UI framework)
------------------------------------------------------
local CreateFrame                  = CreateFrame
local Settings                     = Settings
local ColorPickerFrame             = ColorPickerFrame
local InterfaceOptions_AddCategory = InterfaceOptions_AddCategory

local UIDropDownMenu_CreateInfo      = UIDropDownMenu_CreateInfo
local UIDropDownMenu_SetWidth       = UIDropDownMenu_SetWidth
local UIDropDownMenu_Initialize     = UIDropDownMenu_Initialize
local UIDropDownMenu_SetSelectedValue = UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_AddButton      = UIDropDownMenu_AddButton

local EnsureDB                     = _G.EnsureDB
local RAID_CLASS_COLORS            = RAID_CLASS_COLORS
local C_Timer                      = C_Timer

local function MSUF_ExpandDropdownClickArea(dropdown)
    if not dropdown or dropdown._msufClickAreaExpanded then return end

    local btn = dropdown.Button
    if not btn and dropdown.GetName then
        local nm = dropdown:GetName()
        if nm then btn = _G[nm .. "Button"] end
    end
    if not btn or not btn.SetHitRectInsets then return end

    btn:SetHitRectInsets(-260, 0, -8, -8)
    dropdown._msufClickAreaExpanded = true
end


local function MSUF_ConfirmColorReset(label, doReset)
    if type(doReset) ~= "function" then return end

    local KEY = "MSUF_CONFIRM_COLOR_RESET"
    _G.MSUF__ColorResetConfirm = _G.MSUF__ColorResetConfirm or {}
    local st = _G.MSUF__ColorResetConfirm
    st.fn = doReset

    if not StaticPopupDialogs[KEY] then
        StaticPopupDialogs[KEY] = {
            text = "",
            button1 = OKAY,
            button2 = CANCEL,
            OnAccept = function()
                local state = _G.MSUF__ColorResetConfirm
                local fn = state and state.fn
                if fn then
                    state.fn = nil
                    fn()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    StaticPopupDialogs[KEY].text = "Reset " .. tostring(label) .. " color settings?\n\nThis cannot be undone."
    StaticPopup_Show(KEY)
end


-- Helper: ColorPicker wrapper
------------------------------------------------------
local function OpenColorPicker(initialR, initialG, initialB, callback)
    if not ColorPickerFrame or type(callback) ~= "function" then return end

    -- Snapshot the color as it was BEFORE opening the picker.
    -- We use this for proper Cancel behavior (revert live swatch changes).
    local startR = tonumber(initialR) or 1
    local startG = tonumber(initialG) or 1
    local startB = tonumber(initialB) or 1

    if ColorPickerFrame.SetupColorPickerAndShow then
        -- modern API
        local info = {
            r          = startR,
            g          = startG,
            b          = startB,
            opacity    = 1,
            hasOpacity = false,

            -- Called when the user changes the color (live preview).
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                callback(r, g, b)
            end,

            -- Called when the user presses Cancel.
            cancelFunc = function(previousValues)
                if type(previousValues) == "table" then
                    callback(previousValues.r or startR, previousValues.g or startG, previousValues.b or startB)
                else
                    callback(startR, startG, startB)
                end
            end,
        }

        -- Some builds use previousValues for Cancel; harmless if ignored.
        info.previousValues = { r = startR, g = startG, b = startB, opacity = 1 }

        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- fallback
        local function OnColorChanged()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            callback(r, g, b)
        end

        ColorPickerFrame.func        = OnColorChanged
        ColorPickerFrame.cancelFunc  = function(previousValues)
            if type(previousValues) == "table" then
                callback(previousValues.r or startR, previousValues.g or startG, previousValues.b or startB)
            else
                callback(startR, startG, startB)
            end
        end
        ColorPickerFrame.previousValues = { r = startR, g = startG, b = startB }

        ColorPickerFrame.hasOpacity  = false
        ColorPickerFrame:SetColorRGB(startR, startG, startB)
        ColorPickerFrame:Show()
    end
end

-- Public: register Colors options panel (with scrolling)
------------------------------------------------------
function ns.MSUF_RegisterColorsOptions_Full(parentCategory)
    --------------------------------------------------
    -- Root panel & scroll container
    --------------------------------------------------
    local panel = (_G and _G.MSUF_ColorsPanel) or CreateFrame("Frame", "MSUF_ColorsPanel", UIParent)
    panel.name = "Colors"

    if panel.__MSUF_ColorsBuilt then
        return panel
    end

    -- Pulled inside the function body (not file-scope) to stay under the 60-upvalue ceiling.
    local _api = ns._colorsAPI or {}
    local GetCastbarBackgroundColor   = _api.GetCastbarBackgroundColor
    local SetCastbarBackgroundColor   = _api.SetCastbarBackgroundColor
    local ResetCastbarBackgroundColor = _api.ResetCastbarBackgroundColor
    local ResetGlobalFontToPalette    = _api.ResetGlobalFontToPalette
    local ResetCastbarTextColorToGlobal = _api.ResetCastbarTextColorToGlobal
    local ResetCastbarBorderColor     = _api.ResetCastbarBorderColor
    local ResetAllClassColors         = _api.ResetAllClassColors
    local ResetClassBarBgColor        = _api.ResetClassBarBgColor
    local ResetAllNPCColors           = _api.ResetAllNPCColors

    local scrollFrame = CreateFrame("ScrollFrame", "MSUF_ColorsScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 0)

    local content = CreateFrame("Frame", "MSUF_ColorsScrollChild", scrollFrame)
    content:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    content:SetWidth(640)
    content:SetHeight(600)

    scrollFrame:SetScrollChild(content)

    -- Func table to avoid 200-local limit (store helper funcs + persistent UI refs as fields, not locals)
    local F = panel.__MSUF_ColorsFuncs
    if not F then
        F = {}
        panel.__MSUF_ColorsFuncs = F
    end

    local S = panel.__MSUF_ColorsState
    if not S then
        S = {
            classSwatches = {}, -- token -> texture
            classLabels = {},   -- token -> FontString
            barAppearanceRefreshing = false,
        }
        panel.__MSUF_ColorsState = S
    else
        S.classSwatches = S.classSwatches or {}
        S.classLabels = S.classLabels or {}
        if S.barAppearanceRefreshing == nil then
            S.barAppearanceRefreshing = false
        end
    end

    --------------------------------------------------
    -- Helper: section divider (like Gameplay tab)
    --------------------------------------------------
    F.CreateHeaderDividerAbove = function(header)
        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.15)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", header, "TOPLEFT", 0, 8)
        line:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        return line
    end


--------------------------------------------------
-- Helper: toggle greyout (like main menu)
-- When a feature toggle is OFF, it should look disabled (greyed),
-- but remain clickable.
--------------------------------------------------
F.ApplyToggleGreyout = function(checkBtn, isOn)
    if not checkBtn then return end
    local on = isOn
    if on == nil and checkBtn.GetChecked then
        on = (checkBtn:GetChecked() == true)
    end
    local a = on and 1 or 0.35
    if checkBtn.SetAlpha then checkBtn:SetAlpha(a) end
    if checkBtn.text and checkBtn.text.SetAlpha then
        checkBtn.text:SetAlpha(a)
    end
end

    --------------------------------------------------
    --------------------------------------------------
-- Contrast helper for class labels
--------------------------------------------------
F.SetLabelContrast = function(label, r, g, b)
    if not label then return end
    -- Intentionally keep labels readable and consistent:
    -- Always white text with a black shadow (avoid automatic black text on bright colors).
    label:SetTextColor(1, 1, 1)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
end

    --------------------------------------------------
    -- Title + description
    --------------------------------------------------
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames - Colors")

    local subText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subText:SetWidth(600)
    subText:SetJustifyH("LEFT")
    subText:SetText("Configure global colors such as the global font color, per-class bar colors, and NPC reaction colors.")

    --------------------------------------------------

    --------------------------------------------------
    -- Global font color
    --------------------------------------------------
    local fontLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -24)
    fontLabel:SetText("Global font color")
    F.CreateHeaderDividerAbove(fontLabel)

    local fontSwatch = CreateFrame("Button", "MSUF_Colors_FontSwatchButton", content)
    fontSwatch:SetSize(32, 16)
    fontSwatch:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -8)

    S.fontSwatchTex = fontSwatch:CreateTexture(nil, "ARTWORK")
    S.fontSwatchTex:SetAllPoints()

    fontSwatch:SetScript("OnClick", function()
        local r, g, b = GetGlobalFontColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetGlobalFontColor(nr, ng, nb)
            S.fontSwatchTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    local fontResetBtn = CreateFrame("Button", "MSUF_Colors_FontResetButton", content, "UIPanelButtonTemplate")
    fontResetBtn:SetSize(140, 22)
    fontResetBtn:SetPoint("TOPLEFT", fontSwatch, "BOTTOMLEFT", 0, -8)
    fontResetBtn:SetText("Use font palette")
    fontResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("font palette", function()
                    ResetGlobalFontToPalette()
                    local r, g, b = GetGlobalFontColor()
                    S.fontSwatchTex:SetColorTexture(r, g, b)
        end)
    end)

    --------------------------------------------------
    -- Class bar colors (5 / 5 / 3, Klassennamen auf den Bars)
    --------------------------------------------------
    local classHeader = content:CreateFontString("MSUF_Colors_ClassHeader", "ARTWORK", "GameFontNormal")
    classHeader:SetPoint("TOPLEFT", fontResetBtn, "BOTTOMLEFT", 0, -32)
    classHeader:SetText("Class bar colors")
    F.CreateHeaderDividerAbove(classHeader)

    local classSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    classSub:SetPoint("TOPLEFT", classHeader, "BOTTOMLEFT", 0, -4)
    classSub:SetWidth(600)
    classSub:SetJustifyH("LEFT")
    classSub:SetText("Choose an override bar color per class.")

    local startY    = -36
    local rowHeight = 22
    local colWidth  = 110   -- Platz pro Spalte
    local barOffset = 30    -- Abstand innerhalb der Spalte bis zum Balken

    local rowSizes   = { 5, 5, 3 }   -- 5 / 5 / 3 = 13 Klassen
    local rowCount   = #rowSizes
    local classIndex = 1

    for rowIndex, rowSize in ipairs(rowSizes) do
        for colIndex = 1, rowSize do
            local token = CLASS_TOKENS[classIndex]
            if not token then break end
            classIndex = classIndex + 1

            local lower = token:lower()
            local className
            if lower == "deathknight" then
                className = "DK"
            elseif lower == "demonhunter" then
                className = "DH"
            else
                className = lower:sub(1, 1):upper() .. lower:sub(2)
            end

            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]

            local xOffset = (colIndex - 1) * colWidth
            local yOffset = startY - (rowIndex - 1) * rowHeight

            -- Bar an fester Position je Spalte
            local rowSwatch = CreateFrame("Button", nil, content)
            rowSwatch:SetSize(80, 16)
            rowSwatch:SetPoint("TOPLEFT", classSub, "BOTTOMLEFT", xOffset + barOffset, yOffset)

            local rowTex = rowSwatch:CreateTexture(nil, "ARTWORK")
            rowTex:SetAllPoints()
            if c then
                rowTex:SetColorTexture(c.r, c.g, c.b)
            else
                rowTex:SetColorTexture(1, 1, 1)
            end

            -- Klassename direkt auf die Bar
            local label = rowSwatch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("CENTER", rowSwatch, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetText(className)

            local r, g, b = GetClassColor(token)
            F.SetLabelContrast(label, r, g, b)

            S.classSwatches[token] = rowTex
            S.classLabels[token]   = label

            rowSwatch:SetScript("OnClick", function()
                local cr, cg, cb = GetClassColor(token)
                OpenColorPicker(cr, cg, cb, function(nr, ng, nb)
                    SetClassColor(token, nr, ng, nb)
                    rowTex:SetColorTexture(nr, ng, nb)
                    F.SetLabelContrast(label, nr, ng, nb)
                end)
            end)
        end
    end

    local resetOffsetY = startY - rowCount * rowHeight - 16

    local resetClassBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetClassBtn:SetSize(180, 22)
    resetClassBtn:SetPoint("TOPLEFT", classSub, "BOTTOMLEFT", 0, resetOffsetY)
    resetClassBtn:SetText("Reset all class colors")
    resetClassBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("class", function()
                    ResetAllClassColors()
                    for _, token in ipairs(CLASS_TOKENS) do
                        local tex   = S.classSwatches[token]
                        local label = S.classLabels[token]
                        if tex then
                            local r, g, b = GetClassColor(token)
                            tex:SetColorTexture(r, g, b)
                            F.SetLabelContrast(label, r, g, b)
                        end
                    end
        end)
    end)

    --------------------------------------------------
    -- Bar background tint (universal)
    --------------------------------------------------
    local classBgHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    classBgHeader:SetPoint("TOPLEFT", resetClassBtn, "BOTTOMLEFT", 0, -32)
    classBgHeader:SetText("Bar background tint")
    F.CreateHeaderDividerAbove(classBgHeader)

    local classBgSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    classBgSub:SetPoint("TOPLEFT", classBgHeader, "BOTTOMLEFT", 0, -4)
    classBgSub:SetWidth(600)
    classBgSub:SetJustifyH("LEFT")
    classBgSub:SetText("Tint applied to the bar background in *all* bar modes. (Dark Mode uses this tint too.)")

    local classBgSwatch = CreateFrame("Button", "MSUF_Colors_ClassBarBgSwatch", content)
    classBgSwatch:SetSize(80, 16)
    classBgSwatch:SetPoint("TOPLEFT", classBgSub, "BOTTOMLEFT", 0, -8)

    S.classBgSwatchTex = classBgSwatch:CreateTexture(nil, "ARTWORK")
    S.classBgSwatchTex:SetAllPoints()

    classBgSwatch:SetScript("OnClick", function()
        local r, g, b = GetClassBarBgColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetClassBarBgColor(nr, ng, nb)
            S.classBgSwatchTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    local classBgResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    classBgResetBtn:SetSize(140, 22)
    classBgResetBtn:SetPoint("TOPLEFT", classBgSwatch, "BOTTOMLEFT", 0, -8)
    classBgResetBtn:SetText("Reset to black")
    classBgResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("class bar background", function()
                    ResetClassBarBgColor()
                    local r, g, b = GetClassBarBgColor()
                    S.classBgSwatchTex:SetColorTexture(r, g, b)
        end)
    end)

    -- Optional toggle: match background tint to the current HP bar color
    -- (so users don't need to pick a separate tint color)
    S.classBgMatchCheck = CreateFrame("CheckButton", "MSUF_Colors_BarBgMatchHP", content, "UICheckButtonTemplate")
    S.classBgMatchCheck:SetPoint("LEFT", classBgSwatch, "RIGHT", 14, 0)
    if not S.classBgMatchCheck.text then
        S.classBgMatchCheck.text = S.classBgMatchCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        S.classBgMatchCheck.text:SetPoint("LEFT", S.classBgMatchCheck, "RIGHT", 2, 0)
    end
    S.classBgMatchCheck.text:SetText("Match HP")

    local function UpdateClassBgMatchState()
        local match = GetBarBgMatchHP()
        S.classBgMatchCheck:SetChecked(match)
        if classBgSwatch and classBgSwatch.EnableMouse then
            classBgSwatch:EnableMouse(not match)
        end
        if classBgSwatch and classBgSwatch.SetAlpha then
            classBgSwatch:SetAlpha(match and 0.5 or 1)
        end
        if classBgResetBtn and classBgResetBtn.SetEnabled then
            classBgResetBtn:SetEnabled(not match)
        end
    end

    S.classBgMatchCheck:SetScript("OnClick", function(btn)
        SetBarBgMatchHP(btn:GetChecked())
        UpdateClassBgMatchState()
    end)

    -- Initial state
    UpdateClassBgMatchState()

    -- Toggle: use tint color directly in Dark Mode (bypass brightness dimming).
    -- Allows fully custom background colors (including white) in Dark Mode.
    -- NOTE: All references stored on F to avoid adding locals (Lua 5.1 200-local limit).
    F._darkBgCustomCheck = CreateFrame("CheckButton", "MSUF_Colors_DarkBgCustomColor", content, "UICheckButtonTemplate")
    F._darkBgCustomCheck:SetPoint("TOPLEFT", classBgResetBtn, "BOTTOMLEFT", -4, -4)
    if not F._darkBgCustomCheck.text then
        F._darkBgCustomCheck.text = F._darkBgCustomCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        F._darkBgCustomCheck.text:SetPoint("LEFT", F._darkBgCustomCheck, "RIGHT", 2, 0)
    end
    F._darkBgCustomCheck.text:SetText("Custom color in Dark Mode")

    F.UpdateDarkBgCustomControls = function()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
            mode = (g.useClassColors and "class") or "dark"
        end
        local isDark = (mode == "dark")
        local a = isDark and 1 or 0.35
        F._darkBgCustomCheck:SetChecked(g.darkBgCustomColor and true or false)
        if F._darkBgCustomCheck.Enable and F._darkBgCustomCheck.Disable then
            if isDark then F._darkBgCustomCheck:Enable() else F._darkBgCustomCheck:Disable() end
        end
        F._darkBgCustomCheck:SetAlpha(a)
        if F._darkBgCustomCheck.text then F._darkBgCustomCheck.text:SetAlpha(a) end
    end

    F._darkBgCustomCheck:SetScript("OnClick", function(btn)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.darkBgCustomColor = btn:GetChecked() and true or false
        PushVisualUpdates()
        F.UpdateDarkBgCustomControls()
    end)

    F.UpdateDarkBgCustomControls()


    --------------------------------------------------
    -- Bar appearance (moved from Bars menu)
    --------------------------------------------------
    local barAppHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barAppHeader:SetPoint("TOPLEFT", F._darkBgCustomCheck, "BOTTOMLEFT", 4, -22)
    barAppHeader:SetText("Bar appearance")
    F.CreateHeaderDividerAbove(barAppHeader)

    local barModeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barModeLabel:SetPoint("TOPLEFT", barAppHeader, "BOTTOMLEFT", 0, -10)
    barModeLabel:SetText("Bar mode")

    local barModeOptions = {
        { key = "dark",    label = "Dark Mode (dark black bars)" },
        { key = "class",   label = "Class Color Mode (color HP bars)" },
        { key = "unified", label = "Unified Color Mode (one color for all frames)" },
    }

    S.barModeDrop = CreateFrame("Frame", "MSUF_Colors_BarModeDropdown", content, "UIDropDownMenuTemplate")
    S.barModeDrop:SetPoint("TOPLEFT", barModeLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(S.barModeDrop, 240)
    MSUF_ExpandDropdownClickArea(S.barModeDrop)

    F.BarModeDropdown_Initialize = function(self, level)
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local current = g.barMode
        if current ~= "dark" and current ~= "class" and current ~= "unified" then
            current = (g.useClassColors and "class") or "dark"
        end

        for _, opt in ipairs(barModeOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.label
            info.value = opt.key
            info.func  = function(btn)
                if S.barAppearanceRefreshing then return end
                EnsureDB()
                if not MSUF_DB.general then MSUF_DB.general = {} end
                local mode = btn.value
                MSUF_DB.general.barMode = mode

                -- Keep legacy booleans in sync
                if mode == "dark" then
                    MSUF_DB.general.darkMode       = true
                    MSUF_DB.general.useClassColors = false
                elseif mode == "class" then
                    MSUF_DB.general.darkMode       = false
                    MSUF_DB.general.useClassColors = true
                else -- unified
                    MSUF_DB.general.darkMode       = false
                    MSUF_DB.general.useClassColors = false
                end

                UIDropDownMenu_SetSelectedValue(S.barModeDrop, mode)
                UIDropDownMenu_SetText(S.barModeDrop, opt.label)

                if F.UpdateDarkBarControls then F.UpdateDarkBarControls() end
                if F.UpdateDarkBgCustomControls then F.UpdateDarkBgCustomControls() end
                if F.UpdateUnifiedBarControls then F.UpdateUnifiedBarControls() end
                PushVisualUpdates()
            end
            info.checked = (opt.key == current)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(S.barModeDrop, F.BarModeDropdown_Initialize)


    -- Unified bar color (only used when Bar mode == "unified")
    local unifiedLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unifiedLabel:SetPoint("TOPLEFT", S.barModeDrop, "BOTTOMLEFT", 16, -18)
    unifiedLabel:SetText("Unified bar color")

    local unifiedSwatch = CreateFrame("Button", "MSUF_Colors_UnifiedBarSwatch", content)
    unifiedSwatch:SetSize(240, 16)
    unifiedSwatch:SetPoint("TOPLEFT", unifiedLabel, "BOTTOMLEFT", 0, -8)

    local unifiedTex = unifiedSwatch:CreateTexture(nil, "ARTWORK")
    unifiedTex:SetAllPoints()

    local unifiedResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    unifiedResetBtn:SetSize(140, 22)
    unifiedResetBtn:SetPoint("TOPLEFT", unifiedSwatch, "BOTTOMLEFT", 0, -8)
    unifiedResetBtn:SetText("Reset to default")

    local function MSUF_GetUnifiedBarColor()
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local r, gg, b = g.unifiedBarR, g.unifiedBarG, g.unifiedBarB
        if type(r) ~= "number" or type(gg) ~= "number" or type(b) ~= "number" then
            -- Reasonable default (slightly desaturated cyan)
            r, gg, b = 0.10, 0.60, 0.90
        end
        if r < 0 then r = 0 elseif r > 1 then r = 1 end
        if gg < 0 then gg = 0 elseif gg > 1 then gg = 1 end
        if b < 0 then b = 0 elseif b > 1 then b = 1 end
        return r, gg, b
    end

    local function MSUF_SetUnifiedBarColor(r, gg, b)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.unifiedBarR = r
        MSUF_DB.general.unifiedBarG = gg
        MSUF_DB.general.unifiedBarB = b
    end

    local function MSUF_ResetUnifiedBarColor()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.unifiedBarR = 0.10
        MSUF_DB.general.unifiedBarG = 0.60
        MSUF_DB.general.unifiedBarB = 0.90
    end

    unifiedSwatch:SetScript("OnClick", function()
        local r, gg, b = MSUF_GetUnifiedBarColor()
        OpenColorPicker(r, gg, b, function(nr, ng, nb)
            MSUF_SetUnifiedBarColor(nr, ng, nb)
            unifiedTex:SetColorTexture(nr, ng, nb)
            PushVisualUpdates()
        end)
    end)

    unifiedResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("bar", function()
                    MSUF_ResetUnifiedBarColor()
                    local r, gg, b = MSUF_GetUnifiedBarColor()
                    unifiedTex:SetColorTexture(r, gg, b)
                    PushVisualUpdates()
        end)
    end)

    local function UpdateUnifiedBarControls()
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}
        local mode = g.barMode
        if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
            mode = (g.useClassColors and "class") or "dark"
        end
        local enabled = (mode == "unified")
        local a = enabled and 1 or 0.35

        unifiedLabel:SetAlpha(a)
        unifiedSwatch:SetAlpha(a)
        unifiedResetBtn:SetAlpha(a)
        unifiedSwatch:EnableMouse(enabled and true or false)
        unifiedResetBtn:SetEnabled(enabled and true or false)
    end

    -- Init swatch + state
    do
        local r, gg, b = MSUF_GetUnifiedBarColor()
        unifiedTex:SetColorTexture(r, gg, b)
        UpdateUnifiedBarControls()
        -- Expose updater so dropdown selection can refresh both sets
        F.UpdateUnifiedBarControls = UpdateUnifiedBarControls
    end
local darkToneLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
darkToneLabel:SetPoint("TOPLEFT", unifiedResetBtn, "BOTTOMLEFT", 0, -18)
darkToneLabel:SetText("Dark mode bar color")

    S.darkToneLabelFS = darkToneLabel

-- Continuous gray "picker" bar (ColorPicker-style, but HORIZONTAL)
-- NOTE: We intentionally implement this as a plain Frame (NOT a Slider).
-- Some Midnight/Beta builds / skin passes can reskin Slider widgets into the vertical "eye" slider.
-- A plain Frame with our own drag logic is stable and guarantees the requested horizontal behavior.

-- Hide any legacy widget that might still exist from older builds (defensive; no errors if nil)
do
    local legacy = _G["MSUF_Colors_DarkToneSlider"]
    if legacy and legacy.Hide and legacy ~= S.darkToneSlider then
        legacy:Hide()
    end
end

S.darkToneSlider = CreateFrame("Frame", "MSUF_Colors_DarkToneSlider", content)
S.darkToneSlider:SetSize(240, 14)
S.darkToneSlider:SetPoint("TOPLEFT", darkToneLabel, "BOTTOMLEFT", 0, -10)
S.darkToneSlider:EnableMouse(true)

local darkToneBG = S.darkToneSlider:CreateTexture(nil, "BACKGROUND")
darkToneBG:SetAllPoints()
darkToneBG:SetColorTexture(1, 1, 1, 1)

-- black (left) -> white (right)  (so moving toward white makes the bar LIGHTER)
do
    local ok = false
    if darkToneBG.SetGradientAlpha then
        ok = pcall(function()
            darkToneBG:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 1,  1, 1, 1, 1)
        end)
    elseif darkToneBG.SetGradient and CreateColor then
        ok = pcall(function()
            darkToneBG:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 1), CreateColor(1, 1, 1, 1))
        end)
    end
    if not ok then
        -- fallback: readable neutral background (no crash)
        darkToneBG:SetColorTexture(0.65, 0.65, 0.65, 1)
    end
end

-- Border (subtle)
if S.darkToneSlider.SetBackdrop then
    S.darkToneSlider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    S.darkToneSlider:SetBackdropColor(0, 0, 0, 0)
    S.darkToneSlider:SetBackdropBorderColor(0, 0, 0, 0.55)
end

local knob = S.darkToneSlider:CreateTexture(nil, "OVERLAY")
knob:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
knob:SetSize(16, 16)

F.ClampPct = function(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 end
    if v > 100 then v = 100 end
    return math.floor(v + 0.5)
end

F.PositionKnob = function(pct)
    if not knob then return end
    local w = S.darkToneSlider:GetWidth() or 1
    local x = (pct / 100) * w
    knob:ClearAllPoints()
    knob:SetPoint("CENTER", S.darkToneSlider, "LEFT", x, 0)
end

-- Provide a minimal "Slider-like" API for existing refresh/disable logic
function S.darkToneSlider:SetValue(pct)
    pct = F.ClampPct(pct)
    F.PositionKnob(pct)
end
function S.darkToneSlider:SetEnabled(enabled)
    self:EnableMouse(enabled and true or false)
end

S.darkToneValueText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
S.darkToneValueText:SetPoint("LEFT", S.darkToneSlider, "RIGHT", 10, 0)
S.darkToneValueText:SetText("0%  (#000000)")

F.UpdateDarkToneValueText = function(pct)
    local v = (pct or 0) / 100
    local c = math.floor(v * 255 + 0.5)
    if c < 0 then c = 0 end
    if c > 255 then c = 255 end
    if S.darkToneValueText then
        S.darkToneValueText:SetText(string.format("%d%%  (#%02X%02X%02X)", pct or 0, c, c, c))
    end
end

local _lastAppliedPct = -1
F.ApplyPct = function(pct, fromUser)
    pct = F.ClampPct(pct)

    -- Always keep the knob + label in sync, even if we early-return.
    F.PositionKnob(pct)
    if F.UpdateDarkToneValueText then F.UpdateDarkToneValueText(pct) end

    if pct == _lastAppliedPct then
        return
    end
    _lastAppliedPct = pct

    if fromUser then
        if S.barAppearanceRefreshing then return end
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        -- 0 = black, 1 = white
        MSUF_DB.general.darkBarGray = pct / 100
        MSUF_DB.general.darkBarTone = nil
        PushVisualUpdates()
    end
end

F.GetPctFromCursor = function()
    local cx = (GetCursorPosition())
    local scale = S.darkToneSlider:GetEffectiveScale() or 1
    cx = cx / scale
    local left = S.darkToneSlider:GetLeft() or 0
    local w = S.darkToneSlider:GetWidth() or 1
    return ((cx - left) / w) * 100
end

F.StopDrag = function(self)
    self.__msufDragging = nil
    self:SetScript("OnUpdate", nil)
end

S.darkToneSlider:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.__msufDragging = true
    F.ApplyPct(F.GetPctFromCursor(), true)
    self:SetScript("OnUpdate", function()
        if not self.__msufDragging then return end
        F.ApplyPct(F.GetPctFromCursor(), true)
    end)
end)
S.darkToneSlider:SetScript("OnMouseUp", F.StopDrag)
S.darkToneSlider:SetScript("OnHide", F.StopDrag)


-- Enable/disable dark-mode-only controls when bar mode is not "dark"
F.UpdateDarkBarControls = function()
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local mode = g.barMode
    if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
        mode = (g.useClassColors and "class") or "dark"
    end
    local enabled = (mode == "dark")

    local a = enabled and 1 or 0.35

    if S.darkToneLabelFS then S.darkToneLabelFS:SetAlpha(a) end
    if S.darkToneSlider then
        if S.darkToneSlider.SetEnabled then S.darkToneSlider:SetEnabled(enabled) end
        S.darkToneSlider:SetAlpha(a)
    end
    if S.darkToneValueText then S.darkToneValueText:SetAlpha(a) end
end

if F.UpdateDarkBarControls then
    F.UpdateDarkBarControls()
end

    --------------------------------------------------
    -- Unitframe Colors + Bar Colors (two-column layout)
    --------------------------------------------------
    local leftHeaderX   = 0
    local rightHeaderX  = 420

    local rowH          = 22
    local startY        = -8

    -- Left block: Unitframe Colors
    local unitHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    unitHeader:SetPoint("TOPLEFT", S.darkToneSlider, "BOTTOMLEFT", leftHeaderX, -48)
    unitHeader:SetText("Unitframe Colors")
    F.CreateHeaderDividerAbove(unitHeader)

    local unitLabelX    = 0
    local unitBarX      = 220
    local unitBarW      = 120

    -- Friendly
    local friendlyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    friendlyLabel:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitLabelX, startY)
    friendlyLabel:SetJustifyH("LEFT")
    friendlyLabel:SetText("Friendly NPC Color")

    local npcFriendlySwatch = CreateFrame("Button", "MSUF_Colors_NPCFriendlySwatch", content)
    npcFriendlySwatch:SetSize(unitBarW, 16)
    npcFriendlySwatch:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitBarX, startY)

    S.npcFriendlyTex = npcFriendlySwatch:CreateTexture(nil, "ARTWORK")
    S.npcFriendlyTex:SetAllPoints()

    npcFriendlySwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("friendly")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("friendly", nr, ng, nb)
            S.npcFriendlyTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Neutral
    local neutralLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    neutralLabel:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitLabelX, startY - rowH)
    neutralLabel:SetJustifyH("LEFT")
    neutralLabel:SetText("Neutral NPC Color")

    local npcNeutralSwatch = CreateFrame("Button", "MSUF_Colors_NPCNeutralSwatch", content)
    npcNeutralSwatch:SetSize(unitBarW, 16)
    npcNeutralSwatch:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitBarX, startY - rowH)

    S.npcNeutralTex = npcNeutralSwatch:CreateTexture(nil, "ARTWORK")
    S.npcNeutralTex:SetAllPoints()

    npcNeutralSwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("neutral")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("neutral", nr, ng, nb)
            S.npcNeutralTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Enemy
    local enemyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    enemyLabel:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitLabelX, startY - 2 * rowH)
    enemyLabel:SetJustifyH("LEFT")
    enemyLabel:SetText("Enemy NPC Color")

    local npcEnemySwatch = CreateFrame("Button", "MSUF_Colors_NPCEnemySwatch", content)
    npcEnemySwatch:SetSize(unitBarW, 16)
    npcEnemySwatch:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitBarX, startY - 2 * rowH)

    S.npcEnemyTex = npcEnemySwatch:CreateTexture(nil, "ARTWORK")
    S.npcEnemyTex:SetAllPoints()

    npcEnemySwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("enemy")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("enemy", nr, ng, nb)
            S.npcEnemyTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Dead
    local deadLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    deadLabel:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitLabelX, startY - 3 * rowH)
    deadLabel:SetJustifyH("LEFT")
    deadLabel:SetText("Dead NPC Color")

    local npcDeadSwatch = CreateFrame("Button", "MSUF_Colors_NPCDeadSwatch", content)
    npcDeadSwatch:SetSize(unitBarW, 16)
    npcDeadSwatch:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitBarX, startY - 3 * rowH)

    S.npcDeadTex = npcDeadSwatch:CreateTexture(nil, "ARTWORK")
    S.npcDeadTex:SetAllPoints()

    npcDeadSwatch:SetScript("OnClick", function()
        local r, g, b = GetNPCColor("dead")
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNPCColor("dead", nr, ng, nb)
            S.npcDeadTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    -- Pet frame
    local petLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    petLabel:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitLabelX, startY - 4 * rowH)
    petLabel:SetJustifyH("LEFT")
    petLabel:SetText("Pet Frame Color")

    local petFrameSwatch = CreateFrame("Button", "MSUF_Colors_PetFrameSwatch", content)
    petFrameSwatch:SetSize(unitBarW, 16)
    petFrameSwatch:SetPoint("TOPLEFT", unitHeader, "BOTTOMLEFT", unitBarX, startY - 4 * rowH)

    S.petFrameTex = petFrameSwatch:CreateTexture(nil, "ARTWORK")
    S.petFrameTex:SetAllPoints()
    do
        local pr, pg, pb = GetPetFrameColor()
        S.petFrameTex:SetColorTexture(pr, pg, pb)
    end

    petFrameSwatch:SetScript("OnClick", function()
        local r, g, b = GetPetFrameColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPetFrameColor(nr, ng, nb)
            if S.petFrameTex then
                S.petFrameTex:SetColorTexture(nr, ng, nb)
            end
        end)
    end)


    -- Right block: Bar Colors
    local barHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    barHeader:SetPoint("TOPLEFT", S.darkToneSlider, "BOTTOMLEFT", rightHeaderX, -48)
    barHeader:SetText("Bar Colors")
    F.CreateHeaderDividerAbove(barHeader)

    local barLabelX     = 0
    local barSwatchX    = 210
    local barSwatchW    = 120

    -- Absorb overlay
    local absorbLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    absorbLabel:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barLabelX, startY)
    absorbLabel:SetJustifyH("LEFT")
    absorbLabel:SetText("Absorb Bar Color")

    local absorbSwatch = CreateFrame("Button", "MSUF_Colors_AbsorbOverlaySwatch", content)
    absorbSwatch:SetSize(barSwatchW, 16)
    absorbSwatch:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barSwatchX, startY)

    panel.__MSUF_ExtraColorAbsorbTex = absorbSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorAbsorbTex:SetAllPoints()
    panel.__MSUF_ExtraColorAbsorbTex:SetColorTexture(GetAbsorbOverlayColor())

    absorbSwatch:SetScript("OnClick", function()
        local r, g, b = GetAbsorbOverlayColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetAbsorbOverlayColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorAbsorbTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    -- Heal-Absorb overlay
    local healAbsorbLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    healAbsorbLabel:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barLabelX, startY - rowH)
    healAbsorbLabel:SetJustifyH("LEFT")
    healAbsorbLabel:SetText("Heal-Absorb Bar Color")

    local healAbsorbSwatch = CreateFrame("Button", "MSUF_Colors_HealAbsorbOverlaySwatch", content)
    healAbsorbSwatch:SetSize(barSwatchW, 16)
    healAbsorbSwatch:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barSwatchX, startY - rowH)

    panel.__MSUF_ExtraColorHealAbsorbTex = healAbsorbSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorHealAbsorbTex:SetAllPoints()
    panel.__MSUF_ExtraColorHealAbsorbTex:SetColorTexture(GetHealAbsorbOverlayColor())

    healAbsorbSwatch:SetScript("OnClick", function()
        local r, g, b = GetHealAbsorbOverlayColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetHealAbsorbOverlayColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorHealAbsorbTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    -- Power bar background
    local powerBgLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    powerBgLabel:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barLabelX, startY - 2 * rowH)
    powerBgLabel:SetJustifyH("LEFT")
    powerBgLabel:SetText("Power Bar Background Color")

    local powerBgSwatch = CreateFrame("Button", "MSUF_Colors_PowerBarBackgroundSwatch", content)
    panel.__MSUF_ExtraColorPowerBgSwatch = powerBgSwatch
    powerBgSwatch:SetSize(barSwatchW, 16)
    powerBgSwatch:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barSwatchX, startY - 2 * rowH)

    panel.__MSUF_ExtraColorPowerBgTex = powerBgSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorPowerBgTex:SetAllPoints()
    panel.__MSUF_ExtraColorPowerBgTex:SetColorTexture(GetPowerBarBackgroundColor())

    powerBgSwatch:SetScript("OnClick", function()
        local r, g, b = GetPowerBarBackgroundColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPowerBarBackgroundColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorPowerBgTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    panel.__MSUF_ExtraColorPowerBgMatchCheck = panel.__MSUF_ExtraColorPowerBgMatchCheck or CreateFrame("CheckButton", "MSUF_Colors_PowerBarBgMatchHP", content, "UICheckButtonTemplate")
    panel.__MSUF_ExtraColorPowerBgMatchCheck:ClearAllPoints()
    panel.__MSUF_ExtraColorPowerBgMatchCheck:SetPoint("LEFT", powerBgSwatch, "RIGHT", 14, 0)
    if not panel.__MSUF_ExtraColorPowerBgMatchCheck.text then
        panel.__MSUF_ExtraColorPowerBgMatchCheck.text = panel.__MSUF_ExtraColorPowerBgMatchCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        panel.__MSUF_ExtraColorPowerBgMatchCheck.text:SetPoint("LEFT", panel.__MSUF_ExtraColorPowerBgMatchCheck, "RIGHT", 2, 0)
    end
    panel.__MSUF_ExtraColorPowerBgMatchCheck.text:SetText("Match HP")
    panel.__MSUF_ExtraColorPowerBgMatchCheck:SetChecked(GetPowerBarBackgroundMatchHP())
    panel.__MSUF_ExtraColorPowerBgMatchCheck:SetScript("OnClick", function(btn)
        SetPowerBarBackgroundMatchHP(btn:GetChecked())
        if powerBgSwatch and powerBgSwatch.EnableMouse then
            powerBgSwatch:EnableMouse(not btn:GetChecked())
        end
        if powerBgSwatch and powerBgSwatch.SetAlpha then
            powerBgSwatch:SetAlpha(btn:GetChecked() and 0.35 or 1)
        end
    end)

    if GetPowerBarBackgroundMatchHP() then
        if powerBgSwatch and powerBgSwatch.EnableMouse then
            powerBgSwatch:EnableMouse(false)
        end
        if powerBgSwatch and powerBgSwatch.SetAlpha then
            powerBgSwatch:SetAlpha(0.35)
        end
    else
        if powerBgSwatch and powerBgSwatch.EnableMouse then
            powerBgSwatch:EnableMouse(true)
        end
        if powerBgSwatch and powerBgSwatch.SetAlpha then
            powerBgSwatch:SetAlpha(1)
        end
    end

    -- Aggro border (outline indicator)
    local aggroLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    aggroLabel:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barLabelX, startY - 3 * rowH)
    aggroLabel:SetJustifyH("LEFT")
    aggroLabel:SetText("Aggro Border Color")

    local aggroSwatch = CreateFrame("Button", "MSUF_Colors_AggroBorderSwatch", content)
    aggroSwatch:SetSize(barSwatchW, 16)
    aggroSwatch:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barSwatchX, startY - 3 * rowH)

    panel.__MSUF_ExtraColorAggroBorderTex = aggroSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorAggroBorderTex:SetAllPoints()
    panel.__MSUF_ExtraColorAggroBorderTex:SetColorTexture(GetAggroBorderColor())

    aggroSwatch:SetScript("OnClick", function()
        local r, g, b = GetAggroBorderColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetAggroBorderColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorAggroBorderTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    
    -- Local helpers: Dispel border (outline indicator) color
    -- Keep these inside the panel builder to avoid hitting WoW's 60-upvalue limit.
    local function GetDispelBorderColor()
        local defR, defG, defB = 0.25, 0.75, 1.00
        if EnsureDB and MSUF_DB then
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            local r = g.dispelBorderColorR
            local gg = g.dispelBorderColorG
            local b = g.dispelBorderColorB
            if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
                return r, gg, b
            end
        end
        return defR, defG, defB
    end

    local function SetDispelBorderColor(r, g, b)
        if not EnsureDB or not MSUF_DB then return end
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local gen = MSUF_DB.general
        gen.dispelBorderColorR = r
        gen.dispelBorderColorG = g
        gen.dispelBorderColorB = b
        PushVisualUpdates()
    end

-- Dispel border (outline indicator)
    local dispelLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dispelLabel:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barLabelX, startY - 4 * rowH)
    dispelLabel:SetJustifyH("LEFT")
    dispelLabel:SetText("Dispel Border Color")

    local dispelSwatch = CreateFrame("Button", "MSUF_Colors_DispelBorderSwatch", content)
    dispelSwatch:SetSize(barSwatchW, 16)
    dispelSwatch:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barSwatchX, startY - 4 * rowH)

    panel.__MSUF_ExtraColorDispelBorderTex = dispelSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorDispelBorderTex:SetAllPoints()
    panel.__MSUF_ExtraColorDispelBorderTex:SetColorTexture(GetDispelBorderColor())

    dispelSwatch:SetScript("OnClick", function()
        local r, g, b = GetDispelBorderColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetDispelBorderColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorDispelBorderTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

-- Purge border (outline indicator for purgeable/spellstealable buffs)
    local function GetPurgeBorderColor()
        local defR, defG, defB = 1.00, 0.85, 0.00
        if EnsureDB and MSUF_DB then
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general
            local r = g.purgeBorderColorR
            local gg = g.purgeBorderColorG
            local b = g.purgeBorderColorB
            if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
                return r, gg, b
            end
        end
        return defR, defG, defB
    end

    local function SetPurgeBorderColor(r, g, b)
        if not EnsureDB or not MSUF_DB then return end
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local gen = MSUF_DB.general
        gen.purgeBorderColorR = r
        gen.purgeBorderColorG = g
        gen.purgeBorderColorB = b
        PushVisualUpdates()
    end

    local purgeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    purgeLabel:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barLabelX, startY - 5 * rowH)
    purgeLabel:SetJustifyH("LEFT")
    purgeLabel:SetText("Purge Border Color")

    local purgeSwatch = CreateFrame("Button", "MSUF_Colors_PurgeBorderSwatch", content)
    purgeSwatch:SetSize(barSwatchW, 16)
    purgeSwatch:SetPoint("TOPLEFT", barHeader, "BOTTOMLEFT", barSwatchX, startY - 5 * rowH)

    panel.__MSUF_ExtraColorPurgeBorderTex = purgeSwatch:CreateTexture(nil, "ARTWORK")
    panel.__MSUF_ExtraColorPurgeBorderTex:SetAllPoints()
    panel.__MSUF_ExtraColorPurgeBorderTex:SetColorTexture(GetPurgeBorderColor())

    purgeSwatch:SetScript("OnClick", function()
        local r, g, b = GetPurgeBorderColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPurgeBorderColor(nr, ng, nb)
            local tex = panel.__MSUF_ExtraColorPurgeBorderTex
            if tex then tex:SetColorTexture(nr, ng, nb) end
        end)
    end)

    -- Reset (kept for 0-regression; affects both columns)
    local npcResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    npcResetBtn:SetSize(160, 22)
    npcResetBtn:SetPoint("TOPLEFT", petLabel, "BOTTOMLEFT", 0, -12)
    npcResetBtn:SetText("Reset Extra Color")
    npcResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("unitframe + bar", function()
                    if EnsureDB and MSUF_DB then
                        EnsureDB()
                        MSUF_DB.npcColors = nil
            
                        MSUF_DB.general = MSUF_DB.general or {}
                        local gen = MSUF_DB.general
                        gen.absorbBarColorR, gen.absorbBarColorG, gen.absorbBarColorB = nil, nil, nil
                        gen.healAbsorbBarColorR, gen.healAbsorbBarColorG, gen.healAbsorbBarColorB = nil, nil, nil
                        gen.powerBarBgColorR, gen.powerBarBgColorG, gen.powerBarBgColorB = nil, nil, nil
                        gen.aggroBorderColorR, gen.aggroBorderColorG, gen.aggroBorderColorB = nil, nil, nil
                        gen.dispelBorderColorR, gen.dispelBorderColorG, gen.dispelBorderColorB = nil, nil, nil
                        gen.purgeBorderColorR, gen.purgeBorderColorG, gen.purgeBorderColorB = nil, nil, nil
            
                        gen.powerBarBgMatchHPColor = nil
                        MSUF_DB.bars = MSUF_DB.bars or {}
                        MSUF_DB.bars.powerBarBgMatchBarColor = nil
            
                        PushVisualUpdates()
                    end
            
                    if S.npcFriendlyTex then
                        local fr, fg, fb = GetNPCColor("friendly")
                        S.npcFriendlyTex:SetColorTexture(fr, fg, fb)
                    end
                    if S.npcNeutralTex then
                        local nr, ng, nb = GetNPCColor("neutral")
                        S.npcNeutralTex:SetColorTexture(nr, ng, nb)
                    end
                    if S.npcEnemyTex then
                        local er, eg, eb = GetNPCColor("enemy")
                        S.npcEnemyTex:SetColorTexture(er, eg, eb)
                    end
                    if S.npcDeadTex then
                        local dr, dg, db = GetNPCColor("dead")
                        S.npcDeadTex:SetColorTexture(dr, dg, db)
                    end
                    if S.petFrameTex then
                        local pr, pg, pb = GetPetFrameColor()
                        S.petFrameTex:SetColorTexture(pr, pg, pb)
                    end
                    local aTex = panel.__MSUF_ExtraColorAbsorbTex
                    if aTex then
                        aTex:SetColorTexture(GetAbsorbOverlayColor())
                    end
                    local hTex = panel.__MSUF_ExtraColorHealAbsorbTex
                    if hTex then
                        hTex:SetColorTexture(GetHealAbsorbOverlayColor())
                    end
                    local pTex = panel.__MSUF_ExtraColorPowerBgTex
                    if pTex then
                        pTex:SetColorTexture(GetPowerBarBackgroundColor())
                    end

                    local dTex = panel.__MSUF_ExtraColorDispelBorderTex
                    if dTex then
                        dTex:SetColorTexture(GetDispelBorderColor())
                    end
                    local agTex = panel.__MSUF_ExtraColorAggroBorderTex
                    if agTex then
                        agTex:SetColorTexture(GetAggroBorderColor())
                    end
            
                    if panel.__MSUF_ExtraColorPowerBgMatchCheck then
                        panel.__MSUF_ExtraColorPowerBgMatchCheck:SetChecked(false)
                    end
                    if panel.__MSUF_ExtraColorPowerBgSwatch and panel.__MSUF_ExtraColorPowerBgSwatch.EnableMouse then
                        panel.__MSUF_ExtraColorPowerBgSwatch:EnableMouse(true)
                    end
                    if panel.__MSUF_ExtraColorPowerBgSwatch and panel.__MSUF_ExtraColorPowerBgSwatch.SetAlpha then
                        panel.__MSUF_ExtraColorPowerBgSwatch:SetAlpha(1)
                    end
        end)
    end)

    S.lastControl = npcResetBtn

    --------------------------------------------------
    -- Castbar colors
    --------------------------------------------------
    local castbarHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarHeader:SetPoint("TOPLEFT", npcResetBtn, "BOTTOMLEFT", 0, -32)
    castbarHeader:SetText("Castbar colors")
    F.CreateHeaderDividerAbove(castbarHeader)

    local castbarSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarSub:SetPoint("TOPLEFT", castbarHeader, "BOTTOMLEFT", 0, -4)
    castbarSub:SetWidth(600)
    castbarSub:SetJustifyH("LEFT")
    castbarSub:SetText("Configure colors for interruptible, non-interruptible and interrupt feedback castbars.")

    --------------------------------------------------
    -- Castbar dropdowns
    --------------------------------------------------
    -- Interruptible cast color (custom Color Picker)
    local interruptibleColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    interruptibleColorLabel:SetPoint("TOPLEFT", castbarSub, "BOTTOMLEFT", 0, -12)
    interruptibleColorLabel:SetText("Interruptible cast color")

    local interruptibleSwatch = CreateFrame("Button", "MSUF_Colors_InterruptibleCastColorSwatch", content)
    interruptibleSwatch:SetSize(32, 16)
    interruptibleSwatch:SetPoint("TOPLEFT", interruptibleColorLabel, "BOTTOMLEFT", 0, -8)

    S.interruptibleTex = interruptibleSwatch:CreateTexture(nil, "ARTWORK")
    S.interruptibleTex:SetAllPoints()

    interruptibleSwatch:SetScript("OnClick", function()
        local r, g, b = GetInterruptibleCastColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetInterruptibleCastColor(nr, ng, nb)
            S.interruptibleTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetInterruptibleCastColor()
        S.interruptibleTex:SetColorTexture(r, g, b)
    end

    local nonInterruptibleColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    nonInterruptibleColorLabel:SetPoint("TOPLEFT", interruptibleColorLabel, "BOTTOMLEFT", 0, -32)
    nonInterruptibleColorLabel:SetText("Non-interruptible cast color")

    local nonInterruptibleSwatch = CreateFrame("Button", "MSUF_Colors_NonInterruptibleCastColorSwatch", content)
    nonInterruptibleSwatch:SetSize(32, 16)
    nonInterruptibleSwatch:SetPoint("TOPLEFT", nonInterruptibleColorLabel, "BOTTOMLEFT", 0, -8)

    S.nonInterruptibleTex = nonInterruptibleSwatch:CreateTexture(nil, "ARTWORK")
    S.nonInterruptibleTex:SetAllPoints()

    nonInterruptibleSwatch:SetScript("OnClick", function()
        local r, g, b = GetNonInterruptibleCastColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetNonInterruptibleCastColor(nr, ng, nb)
            S.nonInterruptibleTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetNonInterruptibleCastColor()
        S.nonInterruptibleTex:SetColorTexture(r, g, b)
    end

-- Interrupt color (all castbars)
    local interruptFeedbackColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    interruptFeedbackColorLabel:SetPoint("TOPLEFT", nonInterruptibleColorLabel, "BOTTOMLEFT", 0, -32)
    interruptFeedbackColorLabel:SetText("Interrupt color (all castbars)")

    local interruptFeedbackSwatch = CreateFrame("Button", "MSUF_Colors_InterruptFeedbackColorSwatch", content)
    interruptFeedbackSwatch:SetSize(32, 16)
    interruptFeedbackSwatch:SetPoint("TOPLEFT", interruptFeedbackColorLabel, "BOTTOMLEFT", 0, -8)

    S.interruptFeedbackTex = interruptFeedbackSwatch:CreateTexture(nil, "ARTWORK")
    S.interruptFeedbackTex:SetAllPoints()

    interruptFeedbackSwatch:SetScript("OnClick", function()
        local r, g, b = GetInterruptFeedbackCastColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetInterruptFeedbackCastColor(nr, ng, nb)
            S.interruptFeedbackTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetInterruptFeedbackCastColor()
        S.interruptFeedbackTex:SetColorTexture(r, g, b)
    end

    -- Castbar text color (custom RGB; right-click to reset to Global font color)
    local castbarTextColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTextColorLabel:SetPoint("TOPLEFT", castbarSub, "BOTTOMLEFT", 360, -12)
    castbarTextColorLabel:SetText("Castbar text color")

    local castbarTextSwatch = CreateFrame("Button", "MSUF_Colors_CastbarTextColorSwatch", content)
    castbarTextSwatch:SetSize(32, 16)
    castbarTextSwatch:SetPoint("TOPLEFT", castbarTextColorLabel, "BOTTOMLEFT", 0, -8)

    local castbarTextTex = castbarTextSwatch:CreateTexture(nil, "ARTWORK")
    castbarTextTex:SetAllPoints()

    castbarTextSwatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    castbarTextSwatch:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then
            ResetCastbarTextColorToGlobal()
            local rr, gg, bb = GetCastbarTextColor()
            castbarTextTex:SetColorTexture(rr, gg, bb)
            return
        end

        local r, g, b = GetCastbarTextColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetCastbarTextColor(nr, ng, nb)
            castbarTextTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = GetCastbarTextColor()
        castbarTextTex:SetColorTexture(r, g, b)
    end


-- Castbar border color (Outline; right-click to reset)
local castbarBorderColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
castbarBorderColorLabel:SetPoint("TOPLEFT", castbarTextSwatch, "BOTTOMLEFT", 0, -18)
castbarBorderColorLabel:SetText("Castbar border color")

local castbarBorderSwatch = CreateFrame("Button", "MSUF_Colors_CastbarBorderColorSwatch", content)
castbarBorderSwatch:SetSize(32, 16)
castbarBorderSwatch:SetPoint("TOPLEFT", castbarBorderColorLabel, "BOTTOMLEFT", 0, -8)

local castbarBorderTex = castbarBorderSwatch:CreateTexture(nil, "ARTWORK")
castbarBorderTex:SetAllPoints()

castbarBorderSwatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
castbarBorderSwatch:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
        ResetCastbarBorderColor()
        local rr, gg, bb = GetCastbarBorderColor()
        castbarBorderTex:SetColorTexture(rr, gg, bb)
        return
    end

    local r, g, b = GetCastbarBorderColor()
    OpenColorPicker(r, g, b, function(nr, ng, nb)
        SetCastbarBorderColor(nr, ng, nb, 1)
        castbarBorderTex:SetColorTexture(nr, ng, nb)
    end)
end)

do
    local r, g, b = GetCastbarBorderColor()
    castbarBorderTex:SetColorTexture(r, g, b)
end

-- Castbar background color (right-click to reset)
local castbarBgColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
castbarBgColorLabel:SetPoint("TOPLEFT", castbarBorderSwatch, "BOTTOMLEFT", 0, -18)
castbarBgColorLabel:SetText("Castbar background color")

local castbarBgSwatch = CreateFrame("Button", "MSUF_Colors_CastbarBgColorSwatch", content)
castbarBgSwatch:SetSize(32, 16)
castbarBgSwatch:SetPoint("TOPLEFT", castbarBgColorLabel, "BOTTOMLEFT", 0, -8)

local castbarBgTex = castbarBgSwatch:CreateTexture(nil, "ARTWORK")
castbarBgTex:SetAllPoints()
S.castbarBgTex = castbarBgTex

castbarBgSwatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
castbarBgSwatch:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
        ResetCastbarBackgroundColor()
        local rr, gg, bb = GetCastbarBackgroundColor()
        castbarBgTex:SetColorTexture(rr, gg, bb)
        return
    end

    local r, g, b = GetCastbarBackgroundColor()
    OpenColorPicker(r, g, b, function(nr, ng, nb)
        SetCastbarBackgroundColor(nr, ng, nb, 1)
        castbarBgTex:SetColorTexture(nr, ng, nb)
    end)
end)

do
    local r, g, b = GetCastbarBackgroundColor()
    castbarBgTex:SetColorTexture(r, g, b)
end



    --------------------------------------------------
    -- Player castbar override (normal casts/channels)
    --------------------------------------------------
    local playerOverrideHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    playerOverrideHeader:SetPoint("TOPLEFT", interruptFeedbackSwatch, "BOTTOMLEFT", 0, -26)
    playerOverrideHeader:SetText("Player castbar override")

    local playerOverrideSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    playerOverrideSub:SetPoint("TOPLEFT", playerOverrideHeader, "BOTTOMLEFT", 0, -4)
    playerOverrideSub:SetWidth(600)
    playerOverrideSub:SetJustifyH("LEFT")
    playerOverrideSub:SetText("Optional: forces the Player castbar to use Class or Custom color during normal casts. Interrupt feedback still uses 'Interrupt color (all castbars)'.")

    local playerOverrideEnable = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    playerOverrideEnable:SetPoint("TOPLEFT", playerOverrideSub, "BOTTOMLEFT", 0, -10)
    playerOverrideEnable.text:SetText("Enable Player override")

    local modeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    modeLabel:SetPoint("TOPLEFT", playerOverrideEnable, "BOTTOMLEFT", 0, -10)
    modeLabel:SetText("Mode:")

    local classModeCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    classModeCheck:SetPoint("LEFT", modeLabel, "RIGHT", 12, 0)
    classModeCheck.text:SetText("Class color")

    local customModeCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    customModeCheck:SetPoint("LEFT", classModeCheck, "RIGHT", 70, 0)
    customModeCheck.text:SetText("Custom color")

    local customColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    customColorLabel:SetPoint("LEFT", customModeCheck.text, "RIGHT", 18, 0)
    customColorLabel:SetText("Color:")

    local playerOverrideSwatch = CreateFrame("Button", "MSUF_Colors_PlayerCastbarOverrideSwatch", content)
    playerOverrideSwatch:SetSize(32, 16)
    playerOverrideSwatch:SetPoint("LEFT", customColorLabel, "RIGHT", 8, -1)

    local playerOverrideTex = playerOverrideSwatch:CreateTexture(nil, "ARTWORK")
    playerOverrideTex:SetAllPoints()

    F.UpdatePlayerOverrideControls = function()
        local enabled = GetPlayerCastbarOverrideEnabled()
        local mode = GetPlayerCastbarOverrideMode()

        playerOverrideEnable:SetChecked(enabled)
        F.ApplyToggleGreyout(playerOverrideEnable, enabled)

        classModeCheck:SetChecked(mode == "CLASS")
        customModeCheck:SetChecked(mode == "CUSTOM")

        -- Grey-out OFF state (like main menu): unchecked choice looks disabled but is still clickable.
        if enabled then
            F.ApplyToggleGreyout(classModeCheck, mode == "CLASS")
            F.ApplyToggleGreyout(customModeCheck, mode == "CUSTOM")
        else
            F.ApplyToggleGreyout(classModeCheck, false)
            F.ApplyToggleGreyout(customModeCheck, false)
        end

        if modeLabel then modeLabel:SetAlpha(enabled and 1 or 0.35) end

        classModeCheck:SetEnabled(enabled)
        customModeCheck:SetEnabled(enabled)

        local showCustom = enabled and (mode == "CUSTOM")
        customColorLabel:SetAlpha(showCustom and 1 or 0.35)
        playerOverrideSwatch:SetAlpha(showCustom and 1 or 0.35)
        playerOverrideSwatch:EnableMouse(showCustom)

        local r, g, b = GetPlayerCastbarOverrideColor()
        playerOverrideTex:SetColorTexture(r, g, b)
    end

    playerOverrideEnable:SetScript("OnClick", function(self)
        SetPlayerCastbarOverrideEnabled(self:GetChecked() == true)
        F.UpdatePlayerOverrideControls()
    end)

    classModeCheck:SetScript("OnClick", function()
        if not GetPlayerCastbarOverrideEnabled() then return end
        SetPlayerCastbarOverrideMode("CLASS")
        F.UpdatePlayerOverrideControls()
    end)

    customModeCheck:SetScript("OnClick", function()
        if not GetPlayerCastbarOverrideEnabled() then return end
        SetPlayerCastbarOverrideMode("CUSTOM")
        F.UpdatePlayerOverrideControls()
    end)

    playerOverrideSwatch:SetScript("OnClick", function()
        if not (GetPlayerCastbarOverrideEnabled() and GetPlayerCastbarOverrideMode() == "CUSTOM") then return end
        local r, g, b = GetPlayerCastbarOverrideColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            SetPlayerCastbarOverrideColor(nr, ng, nb)
            playerOverrideTex:SetColorTexture(nr, ng, nb)
        end)
    end)

    F.UpdatePlayerOverrideControls()

    local playerOverrideAnchor = playerOverrideSwatch

    -- Reset button for castbar colors
    local resetCastbarColorsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetCastbarColorsBtn:SetSize(160, 22)
    resetCastbarColorsBtn:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -10)
    resetCastbarColorsBtn:SetText("Reset castbar colors")

    resetCastbarColorsBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("castbar", function()
                    EnsureDB()
                    local g = MSUF_DB and MSUF_DB.general
                    if not g then return end
            
                    -- Interruptible defaults
                    g.castbarInterruptibleR = nil
                    g.castbarInterruptibleG = nil
                    g.castbarInterruptibleB = nil
                    g.castbarInterruptibleColor = "turquoise"
            
                    -- Non-interruptible defaults
                    g.castbarNonInterruptibleR = nil
                    g.castbarNonInterruptibleG = nil
                    g.castbarNonInterruptibleB = nil
                    g.castbarNonInterruptibleColor = "red"
            
                    -- Interrupt feedback defaults
                    g.castbarInterruptR = nil
                    g.castbarInterruptG = nil
                    g.castbarInterruptB = nil
                    g.castbarInterruptColor = "red"
            
                    -- Player override defaults
                    g.playerCastbarOverrideEnabled = false
                    g.playerCastbarOverrideMode = "CLASS"
                    g.playerCastbarOverrideR = 1
                    g.playerCastbarOverrideG = 1
                    g.playerCastbarOverrideB = 1

                    -- Castbar background defaults
                    g.castbarBgR = nil
                    g.castbarBgG = nil
                    g.castbarBgB = nil
                    g.castbarBgA = nil
            
                    -- Update swatches in the Colors panel
                    if S.interruptibleTex then
                        local r1, g1, b1 = GetInterruptibleCastColor()
                        S.interruptibleTex:SetColorTexture(r1, g1, b1)
                    end
                    if S.nonInterruptibleTex then
                        local r2, g2, b2 = GetNonInterruptibleCastColor()
                        S.nonInterruptibleTex:SetColorTexture(r2, g2, b2)
                    end
                    if S.interruptFeedbackTex then
                        local r3, g3, b3 = GetInterruptFeedbackCastColor()
                        S.interruptFeedbackTex:SetColorTexture(r3, g3, b3)
                    end
                    if S.castbarBgTex then
                        local rb, gb, bb = GetCastbarBackgroundColor()
                        S.castbarBgTex:SetColorTexture(rb, gb, bb)
                    end
            
                    if F.UpdatePlayerOverrideControls then
                        F.UpdatePlayerOverrideControls()
                    end
            
                    -- Update override swatch + toggles
                    if playerOverrideTex then
                        local r4, g4, b4 = GetPlayerCastbarOverrideColor()
                        playerOverrideTex:SetColorTexture(r4, g4, b4)
                    end
                    if F.UpdatePlayerOverrideControls then
                        F.UpdatePlayerOverrideControls()
                    end
            
                    -- Push visuals to active castbars if the helper exists
                    if ns.MSUF_UpdateCastbarVisuals then
                        ns.MSUF_UpdateCastbarVisuals()
                    end
            
                    if PushVisualUpdates then
                        PushVisualUpdates()
                    end
        end)
    end)

    S.lastControl = resetCastbarColorsBtn
    

    --------------------------------------------------
    -- Mouseover highlight
    --------------------------------------------------
    local mouseoverHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    mouseoverHeader:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -64)
    mouseoverHeader:SetText("Mouseover highlight")
    F.CreateHeaderDividerAbove(mouseoverHeader)

    local mouseoverSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    mouseoverSub:SetPoint("TOPLEFT", mouseoverHeader, "BOTTOMLEFT", 0, -4)
    mouseoverSub:SetWidth(600)
    mouseoverSub:SetJustifyH("LEFT")
    mouseoverSub:SetText("Configure the mouseover highlight border that appears when you hover MSUF unitframes.")

    -- Enable/disable mouseover highlight
    S.highlightEnableCheck = CreateFrame("CheckButton", "MSUF_Colors_HighlightEnableCheck", content, "UICheckButtonTemplate")
    S.highlightEnableCheck:SetPoint("TOPLEFT", mouseoverSub, "BOTTOMLEFT", 0, -12)

    if not S.highlightEnableCheck.text then
        S.highlightEnableCheck.text = S.highlightEnableCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        S.highlightEnableCheck.text:SetPoint("LEFT", S.highlightEnableCheck, "RIGHT", 2, 0)
    end
    S.highlightEnableCheck.text:SetText("Enable mouseover highlight")

    local highlightColorLabel
    local highlightColorSwatch

    F.UpdateHighlightControls = function()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local enabled = (MSUF_DB.general.highlightEnabled ~= false)

        if S.highlightEnableCheck then
            S.highlightEnableCheck:SetChecked(enabled)
            F.ApplyToggleGreyout(S.highlightEnableCheck, enabled)
        end

        local a = enabled and 1 or 0.35
        if highlightColorLabel then highlightColorLabel:SetAlpha(a) end
        if highlightColorSwatch then
            highlightColorSwatch:SetAlpha(a)
            highlightColorSwatch:EnableMouse(enabled)
        end
        if S.highlightColorTex then S.highlightColorTex:SetAlpha(a) end
    end

    S.highlightEnableCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.highlightEnabled = self:GetChecked() and true or false
        if F.UpdateHighlightControls then F.UpdateHighlightControls() end
        if UpdateAllHighlightColors then
            UpdateAllHighlightColors()
        end
        if ns and ns.MSUF_FixMouseoverHighlightBindings then
            ns.MSUF_FixMouseoverHighlightBindings()
        end
    end)

    -- Mouseover highlight color (Colorpicker)
    highlightColorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    highlightColorLabel:SetPoint("TOPLEFT", S.highlightEnableCheck, "BOTTOMLEFT", 0, -12)
    highlightColorLabel:SetText("Mouseover highlight color")

    highlightColorSwatch = CreateFrame("Button", "MSUF_Colors_HighlightColorSwatch", content)
    highlightColorSwatch:SetSize(32, 16)
    highlightColorSwatch:SetPoint("TOPLEFT", highlightColorLabel, "BOTTOMLEFT", 0, -8)

    S.highlightColorTex = highlightColorSwatch:CreateTexture(nil, "ARTWORK")
    S.highlightColorTex:SetAllPoints()

    F.GetHighlightColor = function()
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general

        if type(g.highlightColor) == "table" and g.highlightColor[1] and g.highlightColor[2] and g.highlightColor[3] then
            return g.highlightColor[1], g.highlightColor[2], g.highlightColor[3]
        end

        local key = (type(g.highlightColor) == "string" and g.highlightColor:lower()) or "white"
        local colors = MSUF_FONT_COLORS

        if colors and colors[key] then
            local c = colors[key]
            return c[1], c[2], c[3]
        end

        if colors and colors.white then
            local c = colors.white
            return c[1], c[2], c[3]
        end

        return 1, 1, 1
    end

    F.SetHighlightColor = function(r, g, b)
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local gdb = MSUF_DB.general

        gdb.highlightColor = { r, g, b }

        if S.highlightColorTex then
            S.highlightColorTex:SetColorTexture(r, g, b)
        end

        if UpdateAllHighlightColors then
            UpdateAllHighlightColors()
        end
        if ns and ns.MSUF_FixMouseoverHighlightBindings then
            ns.MSUF_FixMouseoverHighlightBindings()
        end
    end

    highlightColorSwatch:SetScript("OnClick", function()
        local r, g, b = F.GetHighlightColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            F.SetHighlightColor(nr, ng, nb)
        end)
    end)

    do
        local r, g, b = F.GetHighlightColor()
        S.highlightColorTex:SetColorTexture(r, g, b)
    end

    if F.UpdateHighlightControls then F.UpdateHighlightControls() end

    -- Mouseover highlight is now the lowest control for dynamic height
    S.lastControl = highlightColorSwatch


--------------------------------------------------
-- Gameplay (Combat state text colors)
--------------------------------------------------
local gameplayHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
gameplayHeader:SetPoint("TOPLEFT", highlightColorSwatch, "BOTTOMLEFT", 0, -44)
gameplayHeader:SetText("Gameplay")
F.CreateHeaderDividerAbove(gameplayHeader)

local gameplaySub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
gameplaySub:SetPoint("TOPLEFT", gameplayHeader, "BOTTOMLEFT", 0, -4)
gameplaySub:SetWidth(600)
gameplaySub:SetJustifyH("LEFT")
gameplaySub:SetText("Configure colors used by Gameplay overlays (Combat Timer, Combat Enter/Leave text, Crosshair range).")

local combatTimerLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
combatTimerLabel:SetPoint("TOPLEFT", gameplaySub, "BOTTOMLEFT", 0, -12)
combatTimerLabel:SetText("Combat timer text color")

-- Shown when the corresponding Gameplay option is disabled
local combatTimerOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
combatTimerOffText:SetPoint("LEFT", combatTimerLabel, "RIGHT", 10, 0)
combatTimerOffText:SetText("Turned Off in Gameplay")
combatTimerOffText:Hide()

local combatTimerSwatch = CreateFrame("Button", "MSUF_Colors_CombatTimerColorSwatch", content)
combatTimerSwatch:SetSize(32, 16)
combatTimerSwatch:SetPoint("TOPLEFT", combatTimerLabel, "BOTTOMLEFT", 0, -8)
local combatTimerTex = combatTimerSwatch:CreateTexture(nil, "ARTWORK")
combatTimerTex:SetAllPoints()

local combatEnterLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
combatEnterLabel:SetPoint("TOPLEFT", combatTimerSwatch, "BOTTOMLEFT", 0, -12)
combatEnterLabel:SetText("Combat Enter text color")

-- Shown when Combat Enter/Leave text is disabled in Gameplay
local combatStateOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
combatStateOffText:SetPoint("LEFT", combatEnterLabel, "RIGHT", 10, 0)
combatStateOffText:SetText("Turned Off in Gameplay")
combatStateOffText:Hide()

local combatEnterSwatch = CreateFrame("Button", "MSUF_Colors_CombatEnterColorSwatch", content)
combatEnterSwatch:SetSize(32, 16)
combatEnterSwatch:SetPoint("TOPLEFT", combatEnterLabel, "BOTTOMLEFT", 0, -8)
local combatEnterTex = combatEnterSwatch:CreateTexture(nil, "ARTWORK")
combatEnterTex:SetAllPoints()

local combatLeaveLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
combatLeaveLabel:SetPoint("TOPLEFT", combatEnterSwatch, "BOTTOMLEFT", 0, -12)
combatLeaveLabel:SetText("Combat Leave text color")

local combatLeaveSwatch = CreateFrame("Button", "MSUF_Colors_CombatLeaveColorSwatch", content)
combatLeaveSwatch:SetSize(32, 16)
combatLeaveSwatch:SetPoint("TOPLEFT", combatLeaveLabel, "BOTTOMLEFT", 0, -8)
local combatLeaveTex = combatLeaveSwatch:CreateTexture(nil, "ARTWORK")
combatLeaveTex:SetAllPoints()

local combatColorSyncCheck = CreateFrame("CheckButton", "MSUF_Colors_CombatStateColorSyncCheck", content, "UICheckButtonTemplate")
combatColorSyncCheck:SetPoint("LEFT", combatLeaveLabel, "RIGHT", 16, 0)

if not combatColorSyncCheck.text then
    combatColorSyncCheck.text = combatColorSyncCheck:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    combatColorSyncCheck.text:SetPoint("LEFT", combatColorSyncCheck, "RIGHT", 2, 0)
end
combatColorSyncCheck.text:SetText("Sync")

-- Forward refs so UpdateGameplay* can grey/disable Reset buttons
local combatTimerResetBtn
local combatStateResetBtn
local crosshairResetBtn

F.EnsureGameplayDB = function()
    EnsureDB()
    MSUF_DB.gameplay = MSUF_DB.gameplay or {}
    local g = MSUF_DB.gameplay
    if type(g.combatTimerColor) ~= "table" then
        -- Default matches legacy (white timer text).
        g.combatTimerColor = { 1, 1, 1 }
    end
    if type(g.combatStateEnterColor) ~= "table" then
        g.combatStateEnterColor = { 1, 1, 1 }
    end
    if type(g.combatStateLeaveColor) ~= "table" then
        g.combatStateLeaveColor = { 0.7, 0.7, 0.7 }
    end
    if g.combatStateColorSync == nil then
        g.combatStateColorSync = false
    end
    -- Crosshair range colors (Gameplay crosshair)
    if type(g.crosshairInRangeColor) ~= "table" then
        g.crosshairInRangeColor = { 0, 1, 0 } -- default green
    end
    if type(g.crosshairOutRangeColor) ~= "table" then
        g.crosshairOutRangeColor = { 1, 0, 0 } -- default red
    end
    -- Player Totems (Shaman) text color (Gameplay: Totem tracker)
    if type(g.playerTotemsTextColor) ~= "table" then
        g.playerTotemsTextColor = { 1, 1, 1 }
    end
    return g
end


-- Read Gameplay toggles from SavedVariables (Gameplay module defaults are FALSE).
F.IsGameplayToggleEnabled = function(key)
    EnsureDB()
    local gdb = (MSUF_DB and MSUF_DB.gameplay) or {}
    return (gdb[key] == true)
end

F.SetFSAlpha = function(fs, enabled)
    if fs and fs.SetAlpha then
        fs:SetAlpha(enabled and 1 or 0.35)
    end
end

F.SetSwatchEnabled = function(btn, enabled)
    if not btn then return end
    if btn.EnableMouse then btn:EnableMouse(enabled and true or false) end
    if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.35) end
end

F.SetButtonEnabled = function(btn, enabled)
    if not btn then return end
    if btn.Enable and btn.Disable then
        if enabled then btn:Enable() else btn:Disable() end
    elseif btn.SetEnabled then
        btn:SetEnabled(enabled and true or false)
    end
    if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.35) end
end

F.GetCombatTimerColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.combatTimerColor
    return (t and t[1]) or 1, (t and t[2]) or 1, (t and t[3]) or 1
end

F.GetCombatStateEnterColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.combatStateEnterColor
    return (t and t[1]) or 1, (t and t[2]) or 1, (t and t[3]) or 1
end

F.GetCombatStateLeaveColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.combatStateLeaveColor
    return (t and t[1]) or 0.7, (t and t[2]) or 0.7, (t and t[3]) or 0.7
end

F.GetCrosshairInRangeColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.crosshairInRangeColor
    return (t and t[1]) or 0, (t and t[2]) or 1, (t and t[3]) or 0
end

F.GetCrosshairOutRangeColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.crosshairOutRangeColor
    return (t and t[1]) or 1, (t and t[2]) or 0, (t and t[3]) or 0
end

F.UpdateGameplayCombatColorControls = function()
    local g = F.EnsureGameplayDB()

    -- Feature toggles live in the Gameplay menu; if a feature is OFF there,
    -- the corresponding color controls are greyed out here to avoid confusion.
    local timerOn = F.IsGameplayToggleEnabled("enableCombatTimer")
    local stateOn = F.IsGameplayToggleEnabled("enableCombatStateText")

    if combatTimerOffText then combatTimerOffText:SetShown(not timerOn) end
    if combatStateOffText then combatStateOffText:SetShown(not stateOn) end

    -- Combat Timer swatch
    F.SetFSAlpha(combatTimerLabel, timerOn)
    F.SetSwatchEnabled(combatTimerSwatch, timerOn)
    F.SetButtonEnabled(combatTimerResetBtn, timerOn)

    local tr, tg, tb = F.GetCombatTimerColor()
    if combatTimerTex then
        combatTimerTex:SetColorTexture(tr, tg, tb)
        combatTimerTex:SetAlpha(timerOn and 1 or 0.35)
    end

    -- Combat Enter/Leave swatches
    F.SetFSAlpha(combatEnterLabel, stateOn)
    F.SetSwatchEnabled(combatEnterSwatch, stateOn)
    F.SetButtonEnabled(combatStateResetBtn, stateOn)

    local er, eg, eb = F.GetCombatStateEnterColor()
    local lr, lg, lb = F.GetCombatStateLeaveColor()

    if g.combatStateColorSync then
        lr, lg, lb = er, eg, eb
    end

    if combatEnterTex then
        combatEnterTex:SetColorTexture(er, eg, eb)
        combatEnterTex:SetAlpha(stateOn and 1 or 0.35)
    end

    if combatColorSyncCheck then
        combatColorSyncCheck:SetChecked(g.combatStateColorSync and true or false)
        if stateOn and combatColorSyncCheck.Enable then
            combatColorSyncCheck:Enable()
        elseif combatColorSyncCheck.Disable then
            combatColorSyncCheck:Disable()
        end
        F.ApplyToggleGreyout(combatColorSyncCheck, stateOn)
    end

    -- Leave color is disabled when Sync is enabled (and also when the feature itself is off).
    local leaveEnabled = stateOn and (not g.combatStateColorSync)
    local a = leaveEnabled and 1 or 0.35

    if combatLeaveLabel then combatLeaveLabel:SetAlpha(a) end
    if combatLeaveSwatch then
        combatLeaveSwatch:SetAlpha(a)
        combatLeaveSwatch:EnableMouse(leaveEnabled)
    end
    if combatLeaveTex then
        combatLeaveTex:SetColorTexture(lr, lg, lb)
        combatLeaveTex:SetAlpha(a)
    end
end

F.SetCombatTimerColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.combatTimerColor = { r, gCol, bCol }
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.SetCombatStateEnterColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.combatStateEnterColor = { r, gCol, bCol }
    if g.combatStateColorSync then
        g.combatStateLeaveColor = { r, gCol, bCol }
    end
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.SetCombatStateLeaveColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    if g.combatStateColorSync then
        return
    end
    g.combatStateLeaveColor = { r, gCol, bCol }
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end


-- Reset buttons (Gameplay colors)
F.ResetGameplayCombatTimerColor = function()
    local g = F.EnsureGameplayDB()
    g.combatTimerColor = { 1, 1, 1 }
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.ResetGameplayCombatStateColors = function()
    local g = F.EnsureGameplayDB()
    g.combatStateEnterColor = { 1, 1, 1 }
    if g.combatStateColorSync then
        g.combatStateLeaveColor = { 1, 1, 1 }
    else
        g.combatStateLeaveColor = { 0.7, 0.7, 0.7 }
    end
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

combatTimerResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
combatTimerResetBtn:SetSize(110, 22)
combatTimerResetBtn:SetPoint("LEFT", combatTimerSwatch, "RIGHT", 12, 0)
combatTimerResetBtn:SetText("Reset")
combatTimerResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("combat timer colors", function()
                F.ResetGameplayCombatTimerColor()
        end)
    end)

combatStateResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
combatStateResetBtn:SetSize(110, 22)
combatStateResetBtn:SetPoint("LEFT", combatEnterSwatch, "RIGHT", 12, 0)
combatStateResetBtn:SetText("Reset")
combatStateResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("combat state colors", function()
                F.ResetGameplayCombatStateColors()
        end)
    end)

combatTimerSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCombatTimerColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCombatTimerColor(nr, ng, nb)
    end)
end)

combatEnterSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCombatStateEnterColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCombatStateEnterColor(nr, ng, nb)
    end)
end)

combatLeaveSwatch:SetScript("OnClick", function()
    local g = F.EnsureGameplayDB()
    if g.combatStateColorSync then
        return
    end
    local r, gCol, bCol = F.GetCombatStateLeaveColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCombatStateLeaveColor(nr, ng, nb)
    end)
end)

combatColorSyncCheck:SetScript("OnClick", function(self)
    local g = F.EnsureGameplayDB()
    g.combatStateColorSync = self:GetChecked() and true or false
    if g.combatStateColorSync then
        local r, gCol, bCol = F.GetCombatStateEnterColor()
        g.combatStateLeaveColor = { r, gCol, bCol }
    end
    F.UpdateGameplayCombatColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end)


-- Crosshair range colors (Gameplay)
local crosshairInLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
crosshairInLabel:SetPoint("TOPLEFT", combatLeaveSwatch, "BOTTOMLEFT", 0, -18)
crosshairInLabel:SetText("Crosshair in-range color")

-- Shown when Crosshair melee-range coloring is disabled in Gameplay
local crosshairOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
crosshairOffText:SetPoint("LEFT", crosshairInLabel, "RIGHT", 10, 0)
crosshairOffText:SetText("Turned Off in Gameplay")
crosshairOffText:Hide()

local crosshairInSwatch = CreateFrame("Button", "MSUF_Colors_CrosshairInRangeColorSwatch", content)
crosshairInSwatch:SetSize(32, 16)
crosshairInSwatch:SetPoint("TOPLEFT", crosshairInLabel, "BOTTOMLEFT", 0, -8)
local crosshairInTex = crosshairInSwatch:CreateTexture(nil, "ARTWORK")
crosshairInTex:SetAllPoints()

local crosshairOutLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
crosshairOutLabel:SetPoint("TOPLEFT", crosshairInSwatch, "BOTTOMLEFT", 0, -12)
crosshairOutLabel:SetText("Crosshair out-of-range color")

local crosshairOutSwatch = CreateFrame("Button", "MSUF_Colors_CrosshairOutRangeColorSwatch", content)
crosshairOutSwatch:SetSize(32, 16)
crosshairOutSwatch:SetPoint("TOPLEFT", crosshairOutLabel, "BOTTOMLEFT", 0, -8)
local crosshairOutTex = crosshairOutSwatch:CreateTexture(nil, "ARTWORK")
crosshairOutTex:SetAllPoints()

F.UpdateGameplayCrosshairColorControls = function()
        
    -- Crosshair range colors only matter when:
    --  1) Crosshair is enabled
    --  2) Melee-range coloring is enabled
    local crosshairOn = F.IsGameplayToggleEnabled("enableCombatCrosshair") and F.IsGameplayToggleEnabled("enableCombatCrosshairMeleeRangeColor")

    if crosshairOffText then crosshairOffText:SetShown(not crosshairOn) end

    F.SetFSAlpha(crosshairInLabel, crosshairOn)
    F.SetFSAlpha(crosshairOutLabel, crosshairOn)
    F.SetSwatchEnabled(crosshairInSwatch, crosshairOn)
    F.SetSwatchEnabled(crosshairOutSwatch, crosshairOn)
    F.SetButtonEnabled(crosshairResetBtn, crosshairOn)

    local ir, ig, ib = F.GetCrosshairInRangeColor()
    local or_, og, ob = F.GetCrosshairOutRangeColor()

    if crosshairInTex then
        crosshairInTex:SetColorTexture(ir, ig, ib)
        crosshairInTex:SetAlpha(crosshairOn and 1 or 0.35)
    end
    if crosshairOutTex then
        crosshairOutTex:SetColorTexture(or_, og, ob)
        crosshairOutTex:SetAlpha(crosshairOn and 1 or 0.35)
    end
end

F.SetCrosshairInRangeColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.crosshairInRangeColor = { r, gCol, bCol }
    F.UpdateGameplayCrosshairColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.SetCrosshairOutRangeColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.crosshairOutRangeColor = { r, gCol, bCol }
    F.UpdateGameplayCrosshairColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end


-- Reset buttons (Crosshair range colors)
F.ResetGameplayCrosshairColors = function()
    local g = F.EnsureGameplayDB()
    g.crosshairInRangeColor = { 0, 1, 0 }
    g.crosshairOutRangeColor = { 1, 0, 0 }
    F.UpdateGameplayCrosshairColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

crosshairResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
crosshairResetBtn:SetSize(110, 22)
crosshairResetBtn:SetPoint("LEFT", crosshairInSwatch, "RIGHT", 12, 0)
crosshairResetBtn:SetText("Reset")
crosshairResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("crosshair range colors", function()
                F.ResetGameplayCrosshairColors()
        end)
    end)

crosshairInSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCrosshairInRangeColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCrosshairInRangeColor(nr, ng, nb)
    end)
end)

crosshairOutSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetCrosshairOutRangeColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetCrosshairOutRangeColor(nr, ng, nb)
    end)
end)



-- Player Totems text color (Gameplay: Shaman Totem tracker)
local totemTextLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
totemTextLabel:SetPoint("TOPLEFT", crosshairOutSwatch, "BOTTOMLEFT", 0, -18)
totemTextLabel:SetText("Totem tracker text color")

local totemTextOffText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
totemTextOffText:SetPoint("LEFT", totemTextLabel, "RIGHT", 10, 0)
totemTextOffText:SetText("Turned Off in Gameplay")
totemTextOffText:Hide()

local totemTextSwatch = CreateFrame("Button", "MSUF_Colors_PlayerTotemsTextColorSwatch", content)
totemTextSwatch:SetSize(32, 16)
totemTextSwatch:SetPoint("TOPLEFT", totemTextLabel, "BOTTOMLEFT", 0, -8)
local totemTextTex = totemTextSwatch:CreateTexture(nil, "ARTWORK")
totemTextTex:SetAllPoints()

local totemTextResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
totemTextResetBtn:SetSize(110, 22)
totemTextResetBtn:SetPoint("LEFT", totemTextSwatch, "RIGHT", 12, 0)
totemTextResetBtn:SetText("Reset")

F.GetPlayerTotemsTextColor = function()
    local g = F.EnsureGameplayDB()
    local t = g.playerTotemsTextColor
    return (t and t[1]) or 1, (t and t[2]) or 1, (t and t[3]) or 1
end

F.UpdateGameplayTotemColorControls = function()
    -- Totem text color only matters when the Totem tracker is enabled AND the cooldown text is enabled.
    local totemsOn = F.IsGameplayToggleEnabled("enablePlayerTotems") and F.IsGameplayToggleEnabled("playerTotemsShowText")
    if totemTextOffText then totemTextOffText:SetShown(not totemsOn) end

    F.SetFSAlpha(totemTextLabel, totemsOn)
    F.SetSwatchEnabled(totemTextSwatch, totemsOn)
    F.SetButtonEnabled(totemTextResetBtn, totemsOn)

    local r, gCol, bCol = F.GetPlayerTotemsTextColor()
    if totemTextTex then
        totemTextTex:SetColorTexture(r, gCol, bCol)
        totemTextTex:SetAlpha(totemsOn and 1 or 0.35)
    end
end

F.SetPlayerTotemsTextColor = function(r, gCol, bCol)
    local g = F.EnsureGameplayDB()
    g.playerTotemsTextColor = { r, gCol, bCol }
    F.UpdateGameplayTotemColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

F.ResetGameplayTotemTextColor = function()
    local g = F.EnsureGameplayDB()
    g.playerTotemsTextColor = { 1, 1, 1 }
    F.UpdateGameplayTotemColorControls()
    if PushVisualUpdates then PushVisualUpdates() end
    if ns and ns.MSUF_RequestGameplayApply then
        ns.MSUF_RequestGameplayApply()
    end
end

totemTextResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("totem text colors", function()
                F.ResetGameplayTotemTextColor()
        end)
    end)

totemTextSwatch:SetScript("OnClick", function()
    local r, gCol, bCol = F.GetPlayerTotemsTextColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetPlayerTotemsTextColor(nr, ng, nb)
    end)
end)

-- Initialize swatches + enable states
F.UpdateGameplayCombatColorControls()
F.UpdateGameplayCrosshairColorControls()
F.UpdateGameplayTotemColorControls()

-- Gameplay section is now the lowest control for dynamic height
S.lastControl = totemTextSwatch


--------------------------------------------------
-- Power colors (Unitframe power bar)
--------------------------------------------------
local powerHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
powerHeader:SetPoint("TOPLEFT", totemTextSwatch, "BOTTOMLEFT", 0, -44)
powerHeader:SetText("Power bar colors")
F.CreateHeaderDividerAbove(powerHeader)

local powerSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
powerSub:SetPoint("TOPLEFT", powerHeader, "BOTTOMLEFT", 0, -4)
powerSub:SetWidth(600)
powerSub:SetJustifyH("LEFT")
powerSub:SetText("Configure custom colors for power resources used by MSUF power bars.")

local powerTypeDrop = CreateFrame("Frame", "MSUF_Colors_PowerTypeDropdown", content, "UIDropDownMenuTemplate")
powerTypeDrop:SetPoint("TOPLEFT", powerSub, "BOTTOMLEFT", -16, -8)
UIDropDownMenu_SetWidth(powerTypeDrop, 220)
MSUF_ExpandDropdownClickArea(powerTypeDrop)

local powerColorSwatch = CreateFrame("Button", "MSUF_Colors_PowerColorSwatch", content)
powerColorSwatch:SetSize(32, 16)
powerColorSwatch:SetPoint("LEFT", powerTypeDrop, "RIGHT", 18, 2)
local powerColorTex = powerColorSwatch:CreateTexture(nil, "ARTWORK")
powerColorTex:SetAllPoints()

local powerColorResetBtn = CreateFrame("Button", "MSUF_Colors_PowerColorResetBtn", content, "UIPanelButtonTemplate")
powerColorResetBtn:SetText("Reset")
powerColorResetBtn:SetSize(70, 18)
powerColorResetBtn:SetPoint("LEFT", powerColorSwatch, "RIGHT", 10, 0)

-- Common power tokens (keep simple, but cover modern classes)
local POWER_TOKEN_OPTIONS = {
    { token = "MANA",        label = "Mana" },
    { token = "RAGE",        label = "Rage" },
    { token = "ENERGY",      label = "Energy" },
    { token = "FOCUS",       label = "Focus" },
    { token = "RUNIC_POWER", label = "Runic Power" },
    { token = "INSANITY",    label = "Insanity" },
    { token = "FURY",        label = "Fury" },
    { token = "PAIN",        label = "Pain" },
    { token = "ESSENCE",     label = "Essence" },
}

F.EnsurePowerColorsDB = function()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if type(g.powerColorOverrides) ~= "table" then
        g.powerColorOverrides = {}
    end
    return g
end

F.GetDefaultPowerColorForToken = function(token)
    local col = (PowerBarColor and token and PowerBarColor[token]) or nil
    if type(col) == "table" then
        local r = col.r or col[1]
        local g = col.g or col[2]
        local b = col.b or col[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return 0.8, 0.8, 0.8
end

F.GetEffectivePowerColorForToken = function(token)
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local ov = g and g.powerColorOverrides
    local t = (type(ov) == "table" and token) and ov[token] or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, true
        end
    end
    local dr, dg, db = F.GetDefaultPowerColorForToken(token)
    return dr, dg, db, false
end

F.UpdatePowerColorControls = function()
    local token = powerTypeDrop._msufSelectedToken or "MANA"
    local r, gCol, bCol, hasOverride = F.GetEffectivePowerColorForToken(token)
    if powerColorTex then
        powerColorTex:SetColorTexture(r, gCol, bCol)
    end
    if powerColorResetBtn then
        powerColorResetBtn:SetEnabled(hasOverride)
        powerColorResetBtn:SetAlpha(hasOverride and 1 or 0.35)
    end
end

F.PowerTypeDropdown_Initialize = function(self, level)
    local selected = powerTypeDrop._msufSelectedToken or "MANA"
    for _, opt in ipairs(POWER_TOKEN_OPTIONS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text  = opt.label
        info.value = opt.token
        info.func  = function()
            powerTypeDrop._msufSelectedToken = opt.token
            UIDropDownMenu_SetSelectedValue(powerTypeDrop, opt.token)
            UIDropDownMenu_SetText(powerTypeDrop, opt.label)
            F.UpdatePowerColorControls()
        end
        info.checked = (opt.token == selected)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(powerTypeDrop, F.PowerTypeDropdown_Initialize)
powerTypeDrop._msufSelectedToken = powerTypeDrop._msufSelectedToken or "MANA"
UIDropDownMenu_SetSelectedValue(powerTypeDrop, powerTypeDrop._msufSelectedToken)
-- Set initial text
do
    local txtLabel = "Mana"
    for _, opt in ipairs(POWER_TOKEN_OPTIONS) do
        if opt.token == powerTypeDrop._msufSelectedToken then
            txtLabel = opt.label
            break
        end
    end
    UIDropDownMenu_SetText(powerTypeDrop, txtLabel)
end

powerColorSwatch:SetScript("OnClick", function()
    local token = powerTypeDrop._msufSelectedToken or "MANA"
    local r, gCol, bCol = F.GetEffectivePowerColorForToken(token)
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        local g = F.EnsurePowerColorsDB()
        g.powerColorOverrides[token] = { nr, ng, nb }
        F.UpdatePowerColorControls()
        PushVisualUpdates()
    end)
end)

powerColorResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("power colors", function()
                local token = powerTypeDrop._msufSelectedToken or "MANA"
                F.EnsurePowerColorsDB()
                if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.powerColorOverrides) == "table" then
                    MSUF_DB.general.powerColorOverrides[token] = nil
                end
                F.UpdatePowerColorControls()
                PushVisualUpdates()
        end)
    end)

F.UpdatePowerColorControls()

-- Power colors is now the lowest control for dynamic height
S.lastControl = powerColorResetBtn


--------------------------------------------------
-- Class Power colors (Combo Points, Holy Power, etc.)
--------------------------------------------------
local cpColHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
cpColHeader:SetPoint("TOPLEFT", powerTypeDrop, "BOTTOMLEFT", 16, -34)
cpColHeader:SetText("Class Power colors")
F.CreateHeaderDividerAbove(cpColHeader)

local cpColSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
cpColSub:SetPoint("TOPLEFT", cpColHeader, "BOTTOMLEFT", 0, -4)
cpColSub:SetWidth(600)
cpColSub:SetJustifyH("LEFT")
cpColSub:SetText("Configure colors for secondary resource bars: Combo Points, Holy Power, Soul Shards, Chi, Runes, Arcane Charges, Essence, Soul Fragments (DH), Maelstrom (Enh/Ele), Stagger (BrM), Insanity (Shadow), Whirlwind (Fury), Tip of the Spear (SV), Ebon Might (Aug), Eclipse + Prediction (Balance).")

local cpColTypeDrop = CreateFrame("Frame", "MSUF_Colors_ClassPowerTypeDropdown", content, "UIDropDownMenuTemplate")
cpColTypeDrop:SetPoint("TOPLEFT", cpColSub, "BOTTOMLEFT", -16, -8)
UIDropDownMenu_SetWidth(cpColTypeDrop, 260)
MSUF_ExpandDropdownClickArea(cpColTypeDrop)

local cpColSwatch = CreateFrame("Button", "MSUF_Colors_ClassPowerColorSwatch", content)
cpColSwatch:SetSize(32, 16)
cpColSwatch:SetPoint("LEFT", cpColTypeDrop, "RIGHT", 18, 2)
local cpColTex = cpColSwatch:CreateTexture(nil, "ARTWORK")
cpColTex:SetAllPoints()

local cpColResetBtn = CreateFrame("Button", "MSUF_Colors_ClassPowerColorResetBtn", content, "UIPanelButtonTemplate")
cpColResetBtn:SetText("Reset")
cpColResetBtn:SetSize(70, 18)
cpColResetBtn:SetPoint("LEFT", cpColSwatch, "RIGHT", 10, 0)

local cpColBgLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
cpColBgLabel:SetPoint("TOPLEFT", cpColTypeDrop, "BOTTOMLEFT", 16, -24)
cpColBgLabel:SetText("Background")

local cpColBgSwatch = CreateFrame("Button", "MSUF_Colors_ClassPowerBgColorSwatch", content)
cpColBgSwatch:SetSize(32, 16)
cpColBgSwatch:SetPoint("LEFT", cpColBgLabel, "RIGHT", 10, 0)
local cpColBgTex = cpColBgSwatch:CreateTexture(nil, "ARTWORK")
cpColBgTex:SetAllPoints()

local cpColBgResetBtn = CreateFrame("Button", "MSUF_Colors_ClassPowerBgColorResetBtn", content, "UIPanelButtonTemplate")
cpColBgResetBtn:SetText("Reset")
cpColBgResetBtn:SetSize(70, 18)
cpColBgResetBtn:SetPoint("LEFT", cpColBgSwatch, "RIGHT", 10, 0)

-- Class power token options (secondary resources)
local CP_TOKEN_OPTIONS = {
    -- ── Standard segmented ──
    { token = "COMBO_POINTS",   label = "Combo Points" },
    { token = "HOLY_POWER",     label = "Holy Power" },
    { token = "SOUL_SHARDS",    label = "Soul Shards" },
    { token = "CHI",            label = "Chi" },
    { token = "ARCANE_CHARGES", label = "Arcane Charges" },
    { token = "RUNES",          label = "Runes" },
    { token = "ESSENCE",        label = "Essence" },
    { token = "CHARGED",        label = "Empowered (Charged)" },
    -- ── New: aura-based class powers ──
    { token = "SOUL_FRAGMENTS",      label = "Soul Fragments (DH)" },
    { token = "SOUL_FRAGMENTS_META", label = "Soul Fragments \124cFF9933EE(Void Meta)\124r" },
    { token = "MAELSTROM",           label = "Maelstrom Weapon (Enh)" },
    { token = "MAELSTROM_ABOVE_5",  label = "Maelstrom Weapon \124cFFFF8000(5+ Spender Ready)\124r" },
    -- ── Balance Druid: Astral Power + Eclipse ──
    { token = "ASTRAL_POWER",   label = "Astral Power (Balance)" },
    { token = "AP_PREDICTION",  label = "Astral Power \124cFF7799CC(Prediction Overlay)\124r" },
    { token = "ECLIPSE_SOLAR",  label = "Eclipse \124cFFD18F3F(Solar)\124r" },
    { token = "ECLIPSE_LUNAR",  label = "Eclipse \124cFF697ED1(Lunar)\124r" },
    { token = "ECLIPSE_CA",     label = "Eclipse \124cFF4DFF6D(Celestial Alignment)\124r" },
    -- ── Stagger (Brewmaster Monk) ──
    { token = "STAGGER_GREEN",  label = "Stagger \124cFF85FF85(Light)\124r" },
    { token = "STAGGER_YELLOW", label = "Stagger \124cFFFFFAB8(Moderate)\124r" },
    { token = "STAGGER_RED",    label = "Stagger \124cFFFF6B6B(Heavy)\124r" },
    -- ── DH Vengeance ──
    { token = "SOUL_FRAGMENTS_VENG", label = "Soul Fragments \124cFF570B76(Vengeance)\124r" },
    -- ── Continuous bars ──
    { token = "INSANITY",       label = "Insanity (Shadow)" },
    { token = "MAELSTROM_POWER", label = "Maelstrom Power (Ele)" },
    -- ── Spell Trackers ──
    { token = "WHIRLWIND",      label = "Whirlwind (Fury)" },
    { token = "TIP_OF_THE_SPEAR", label = "Tip of the Spear (SV)" },
    -- ── Timer Bar ──
    { token = "EBON_MIGHT",     label = "Ebon Might (Aug)" },
    -- ── Text ──
    { token = "RESOURCE_TEXT",  label = "Resource Text" },
}

F.EnsureClassPowerColorsDB = function()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if type(g.classPowerColorOverrides) ~= "table" then
        g.classPowerColorOverrides = {}
    end
    if type(g.classPowerBgColorOverrides) ~= "table" then
        g.classPowerBgColorOverrides = {}
    end
    return g
end

F.GetDefaultClassPowerColor = function(token)
    -- Charged/empowered has a built-in default (not in PowerBarColor)
    if token == "CHARGED" then
        return 0.60, 0.20, 0.80  -- MidnightRogueBars purple
    end
    -- Resource text: default = global font color from MSUF settings
    if token == "RESOURCE_TEXT" then
        if type(_G.MSUF_GetGlobalFontSettings) == "function" then
            local _, _, fr, fg, fb = _G.MSUF_GetGlobalFontSettings()
            if type(fr) == "number" then return fr, fg, fb end
        end
        return 1, 1, 1
    end
    -- DH Devourer: Soul Fragments (normal green)
    if token == "SOUL_FRAGMENTS" then
        return 0.00, 0.80, 0.00
    end
    -- DH Devourer: Void Metamorphosis purple
    if token == "SOUL_FRAGMENTS_META" then
        return 0.60, 0.20, 0.93
    end
    -- Enhancement Shaman: Maelstrom Weapon (use Maelstrom power bar color)
    if token == "MAELSTROM" then
        local col = PowerBarColor and PowerBarColor["MAELSTROM"]
        if type(col) == "table" then
            local r = col.r or col[1]
            local g = col.g or col[2]
            local b = col.b or col[3]
            if type(r) == "number" then return r, g, b end
        end
        return 0.00, 0.50, 1.00  -- blue fallback
    end
    -- Enhancement Shaman: Maelstrom Weapon 5+ stacks (spender empowered threshold)
    if token == "MAELSTROM_ABOVE_5" then return 1.00, 0.50, 0.00 end
    -- Balance Druid: Astral Power (Blizzard LunarPower blue)
    if token == "ASTRAL_POWER" then
        local col = PowerBarColor and PowerBarColor["LUNAR_POWER"]
        if type(col) == "table" then
            local r = col.r or col[1]
            local g = col.g or col[2]
            local b = col.b or col[3]
            if type(r) == "number" then return r, g, b end
        end
        return 0.30, 0.52, 0.90  -- MCR default
    end
    -- Balance Druid: Prediction overlay (inherits Astral Power default)
    if token == "AP_PREDICTION" then
        local col = PowerBarColor and PowerBarColor["LUNAR_POWER"]
        if type(col) == "table" then
            local r = col.r or col[1]
            local g = col.g or col[2]
            local b = col.b or col[3]
            if type(r) == "number" then return r, g, b end
        end
        return 0.30, 0.52, 0.90  -- same as Astral Power
    end
    -- Balance Druid: Eclipse colors (MCR/Shrom defaults)
    if token == "ECLIPSE_SOLAR" then return 0.82, 0.56, 0.25 end
    if token == "ECLIPSE_LUNAR" then return 0.41, 0.49, 0.82 end
    if token == "ECLIPSE_CA"    then return 0.30, 1.00, 0.43 end
    -- Stagger: Brewmaster Monk (oUF threshold colors)
    if token == "STAGGER_GREEN" then
        return 0.52, 1.00, 0.52
    end
    if token == "STAGGER_YELLOW" then
        return 1.00, 0.98, 0.72
    end
    if token == "STAGGER_RED" then
        return 1.00, 0.42, 0.42
    end
    -- DH Vengeance: Soul Fragments (MCR default — dark purple)
    if token == "SOUL_FRAGMENTS_VENG" then return 0.34, 0.06, 0.46 end
    -- Shadow Priest: Insanity (Blizzard PowerBarColor or MCR default)
    if token == "INSANITY" then
        local col = PowerBarColor and PowerBarColor["INSANITY"]
        if type(col) == "table" then
            local r = col.r or col[1]
            local g = col.g or col[2]
            local b = col.b or col[3]
            if type(r) == "number" then return r, g, b end
        end
        return 0.44, 0.00, 0.74  -- MCR default purple
    end
    -- Ele Shaman: Maelstrom Power (Blizzard PowerBarColor or MCR default)
    if token == "MAELSTROM_POWER" then
        local col = PowerBarColor and PowerBarColor["MAELSTROM"]
        if type(col) == "table" then
            local r = col.r or col[1]
            local g = col.g or col[2]
            local b = col.b or col[3]
            if type(r) == "number" then return r, g, b end
        end
        return 0.00, 0.50, 1.00  -- MCR default blue
    end
    -- Warrior Fury: Whirlwind (MCR default — green)
    if token == "WHIRLWIND" then return 0.20, 0.80, 0.20 end
    -- Hunter SV: Tip of the Spear (MCR default — lime-green)
    if token == "TIP_OF_THE_SPEAR" then return 0.60, 0.80, 0.20 end
    -- Evoker Aug: Ebon Might (MCR default — teal)
    if token == "EBON_MIGHT" then return 0.40, 0.80, 0.60 end
    -- Look up in PowerBarColor
    local col = (PowerBarColor and token and PowerBarColor[token]) or nil
    if type(col) == "table" then
        local r = col.r or col[1]
        local g = col.g or col[2]
        local b = col.b or col[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return 0.8, 0.8, 0.8
end

F.GetEffectiveClassPowerColor = function(token)
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local ov = g and g.classPowerColorOverrides
    local t = (type(ov) == "table" and token) and ov[token] or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, true
        end
    end
    local dr, dg, db = F.GetDefaultClassPowerColor(token)
    return dr, dg, db, false
end

F.GetEffectiveClassPowerBgColor = function(token)
    local g = (MSUF_DB and MSUF_DB.general) or nil
    local ov = g and g.classPowerBgColorOverrides
    local t = (type(ov) == "table" and token) and ov[token] or nil
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, true
        end
    end
    return 0, 0, 0, false
end

F.UpdateClassPowerColorControls = function()
    local token = cpColTypeDrop._msufSelectedToken or "COMBO_POINTS"
    local r, gCol, bCol, hasOverride = F.GetEffectiveClassPowerColor(token)
    if cpColTex then
        cpColTex:SetColorTexture(r, gCol, bCol)
    end
    if cpColResetBtn then
        cpColResetBtn:SetEnabled(hasOverride)
        cpColResetBtn:SetAlpha(hasOverride and 1 or 0.35)
    end
    local br, bg, bb, hasBgOverride = F.GetEffectiveClassPowerBgColor(token)
    if cpColBgTex then
        cpColBgTex:SetColorTexture(br, bg, bb)
    end
    if cpColBgResetBtn then
        cpColBgResetBtn:SetEnabled(hasBgOverride)
        cpColBgResetBtn:SetAlpha(hasBgOverride and 1 or 0.35)
    end
end

F.ClassPowerTypeDropdown_Init = function(self, level)
    local selected = cpColTypeDrop._msufSelectedToken or "COMBO_POINTS"
    for _, opt in ipairs(CP_TOKEN_OPTIONS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text  = opt.label
        info.value = opt.token
        info.func  = function()
            cpColTypeDrop._msufSelectedToken = opt.token
            UIDropDownMenu_SetSelectedValue(cpColTypeDrop, opt.token)
            UIDropDownMenu_SetText(cpColTypeDrop, opt.label)
            F.UpdateClassPowerColorControls()
        end
        info.checked = (opt.token == selected)
        UIDropDownMenu_AddButton(info, level)
    end
end

UIDropDownMenu_Initialize(cpColTypeDrop, F.ClassPowerTypeDropdown_Init)
cpColTypeDrop._msufSelectedToken = "COMBO_POINTS"
UIDropDownMenu_SetSelectedValue(cpColTypeDrop, "COMBO_POINTS")
UIDropDownMenu_SetText(cpColTypeDrop, "Combo Points")

cpColSwatch:SetScript("OnClick", function()
    local token = cpColTypeDrop._msufSelectedToken or "COMBO_POINTS"
    local r, gCol, bCol = F.GetEffectiveClassPowerColor(token)
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        local g = F.EnsureClassPowerColorsDB()
        g.classPowerColorOverrides[token] = { nr, ng, nb }
        F.UpdateClassPowerColorControls()
        -- Live refresh class power bars
        if type(_G.MSUF_ClassPower_InvalidateColors) == "function" then
            _G.MSUF_ClassPower_InvalidateColors()
        end
        PushVisualUpdates()
    end)
end)

cpColResetBtn:SetScript("OnClick", function()
    MSUF_ConfirmColorReset("class power color", function()
        local token = cpColTypeDrop._msufSelectedToken or "COMBO_POINTS"
        F.EnsureClassPowerColorsDB()
        if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.classPowerColorOverrides) == "table" then
            MSUF_DB.general.classPowerColorOverrides[token] = nil
        end
        F.UpdateClassPowerColorControls()
        if type(_G.MSUF_ClassPower_InvalidateColors) == "function" then
            _G.MSUF_ClassPower_InvalidateColors()
        end
        PushVisualUpdates()
    end)
end)

cpColBgSwatch:SetScript("OnClick", function()
    local token = cpColTypeDrop._msufSelectedToken or "COMBO_POINTS"
    local r, gCol, bCol = F.GetEffectiveClassPowerBgColor(token)
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        local g = F.EnsureClassPowerColorsDB()
        g.classPowerBgColorOverrides[token] = { nr, ng, nb }
        F.UpdateClassPowerColorControls()
        if type(_G.MSUF_ClassPower_InvalidateColors) == "function" then
            _G.MSUF_ClassPower_InvalidateColors()
        end
        PushVisualUpdates()
    end)
end)

cpColBgResetBtn:SetScript("OnClick", function()
    MSUF_ConfirmColorReset("class power background color", function()
        local token = cpColTypeDrop._msufSelectedToken or "COMBO_POINTS"
        F.EnsureClassPowerColorsDB()
        if MSUF_DB and MSUF_DB.general and type(MSUF_DB.general.classPowerBgColorOverrides) == "table" then
            MSUF_DB.general.classPowerBgColorOverrides[token] = nil
        end
        F.UpdateClassPowerColorControls()
        if type(_G.MSUF_ClassPower_InvalidateColors) == "function" then
            _G.MSUF_ClassPower_InvalidateColors()
        end
        PushVisualUpdates()
    end)
end)

F.UpdateClassPowerColorControls()

S.lastControl = cpColBgResetBtn


--------------------------------------------------
-- Auras (Auras 2.0)
--------------------------------------------------
local aurasHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
aurasHeader:SetPoint("TOPLEFT", cpColBgLabel, "BOTTOMLEFT", 0, -34)
aurasHeader:SetText("Auras")
F.CreateHeaderDividerAbove(aurasHeader)

local aurasSub = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
aurasSub:SetPoint("TOPLEFT", aurasHeader, "BOTTOMLEFT", 0, -4)
aurasSub:SetWidth(600)
aurasSub:SetJustifyH("LEFT")
aurasSub:SetText("Configure colors used by Auras 2.0 (own highlight borders, advanced filter borders) and stack count text.")

local auraBuffLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraBuffLabel:SetPoint("TOPLEFT", aurasSub, "BOTTOMLEFT", 0, -12)
auraBuffLabel:SetText("Own buff highlight color")

local auraBuffSwatch = CreateFrame("Button", "MSUF_Colors_AuraOwnBuffHighlightSwatch", content)
auraBuffSwatch:SetSize(32, 16)
auraBuffSwatch:SetPoint("TOPLEFT", auraBuffLabel, "BOTTOMLEFT", 0, -8)
local auraBuffTex = auraBuffSwatch:CreateTexture(nil, "ARTWORK")
auraBuffTex:SetAllPoints()

local auraDebuffLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraDebuffLabel:SetPoint("TOPLEFT", auraBuffSwatch, "BOTTOMLEFT", 0, -12)
auraDebuffLabel:SetText("Own debuff highlight color")

local auraDebuffSwatch = CreateFrame("Button", "MSUF_Colors_AuraOwnDebuffHighlightSwatch", content)
auraDebuffSwatch:SetSize(32, 16)
auraDebuffSwatch:SetPoint("TOPLEFT", auraDebuffLabel, "BOTTOMLEFT", 0, -8)
local auraDebuffTex = auraDebuffSwatch:CreateTexture(nil, "ARTWORK")
auraDebuffTex:SetAllPoints()

local auraStacksLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraStacksLabel:SetPoint("TOPLEFT", auraDebuffSwatch, "BOTTOMLEFT", 0, -12)
auraStacksLabel:SetText("Stack count text color")

local auraStacksSwatch = CreateFrame("Button", "MSUF_Colors_AuraStackCountSwatch", content)
auraStacksSwatch:SetSize(32, 16)
auraStacksSwatch:SetPoint("TOPLEFT", auraStacksLabel, "BOTTOMLEFT", 0, -8)
local auraStacksTex = auraStacksSwatch:CreateTexture(nil, "ARTWORK")
auraStacksTex:SetAllPoints()

local auraResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
auraResetBtn:SetSize(110, 22)
auraResetBtn:SetPoint("LEFT", auraStacksSwatch, "RIGHT", 12, 0)
auraResetBtn:SetText("Reset")



-- Aura cooldown text colors (DurationObject step curve)
local auraCDSafeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraCDSafeLabel:SetPoint("TOPLEFT", aurasSub, "BOTTOMLEFT", 360, -12)
auraCDSafeLabel:SetText("Cooldown text: Safe")

local auraCDSafeSwatch = CreateFrame("Button", "MSUF_Colors_AuraCooldownSafeSwatch", content)
auraCDSafeSwatch:SetSize(32, 16)
auraCDSafeSwatch:SetPoint("TOPLEFT", auraCDSafeLabel, "BOTTOMLEFT", 0, -8)
local auraCDSafeTex = auraCDSafeSwatch:CreateTexture(nil, "ARTWORK")
auraCDSafeTex:SetAllPoints()

local auraCDWarnLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraCDWarnLabel:SetPoint("TOPLEFT", auraCDSafeLabel, "BOTTOMLEFT", 0, -32)
auraCDWarnLabel:SetText("Cooldown text: Warning")

local auraCDWarnSwatch = CreateFrame("Button", "MSUF_Colors_AuraCooldownWarningSwatch", content)
auraCDWarnSwatch:SetSize(32, 16)
auraCDWarnSwatch:SetPoint("TOPLEFT", auraCDWarnLabel, "BOTTOMLEFT", 0, -8)
local auraCDWarnTex = auraCDWarnSwatch:CreateTexture(nil, "ARTWORK")
auraCDWarnTex:SetAllPoints()

local auraCDUrgentLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
auraCDUrgentLabel:SetPoint("TOPLEFT", auraCDWarnLabel, "BOTTOMLEFT", 0, -32)
auraCDUrgentLabel:SetText("Cooldown text: Urgent")

local auraCDUrgentSwatch = CreateFrame("Button", "MSUF_Colors_AuraCooldownUrgentSwatch", content)
auraCDUrgentSwatch:SetSize(32, 16)
auraCDUrgentSwatch:SetPoint("TOPLEFT", auraCDUrgentLabel, "BOTTOMLEFT", 0, -8)
local auraCDUrgentTex = auraCDUrgentSwatch:CreateTexture(nil, "ARTWORK")
auraCDUrgentTex:SetAllPoints()

local auraCDResetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
auraCDResetBtn:SetSize(110, 22)
auraCDResetBtn:SetPoint("LEFT", auraCDUrgentSwatch, "RIGHT", 12, 0)
auraCDResetBtn:SetText("Reset")

F.EnsureAurasColorsDB = function()
    EnsureDB()
    MSUF_DB.general = MSUF_DB.general or {}
    local g = MSUF_DB.general
    if type(g.aurasOwnBuffHighlightColor) ~= "table" then
        g.aurasOwnBuffHighlightColor = { 1.0, 0.85, 0.2 } -- legacy gold
    end
    if type(g.aurasOwnDebuffHighlightColor) ~= "table" then
        g.aurasOwnDebuffHighlightColor = { 1.0, 0.85, 0.2 } -- legacy gold
    end
    if type(g.aurasStackCountColor) ~= "table" then
        g.aurasStackCountColor = { 1, 1, 1 } -- white
    end
    if type(g.aurasCooldownTextWarningColor) ~= "table" then
        g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 } -- warning (yellow)
    end
    if type(g.aurasCooldownTextUrgentColor) ~= "table" then
        g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 } -- urgent (orange/red)
    end
    return g
end

F.GetAurasOwnBuffHighlightColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasOwnBuffHighlightColor
    return t[1] or 1.0, t[2] or 0.85, t[3] or 0.2
end

F.GetAurasOwnDebuffHighlightColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasOwnDebuffHighlightColor
    return t[1] or 1.0, t[2] or 0.85, t[3] or 0.2
end

F.GetAurasStackCountColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasStackCountColor
    return t[1] or 1, t[2] or 1, t[3] or 1
end


F.GetAurasCooldownTextSafeColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasCooldownTextSafeColor
    if type(t) == "table" then
        local r = t[1] or t.r
        local gg = t[2] or t.g
        local b = t[3] or t.b
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b
        end
    end
    return GetGlobalFontColor()
end

F.GetAurasCooldownTextWarningColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasCooldownTextWarningColor
    return (t[1] or 1.00), (t[2] or 0.85), (t[3] or 0.20)
end

F.GetAurasCooldownTextUrgentColor = function()
    local g = F.EnsureAurasColorsDB()
    local t = g.aurasCooldownTextUrgentColor
    return (t[1] or 1.00), (t[2] or 0.55), (t[3] or 0.10)
end

F.PushAuras2ColorRefresh = function()
    if type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
    if PushVisualUpdates then
        PushVisualUpdates()
    end
end

-- Live recolor helper for Aura cooldown text (preview + active icons)
F.ForceAurasCooldownTextRecolor = function()
    if type(_G.MSUF_A2_ForceCooldownTextRecolor) == 'function' then
        _G.MSUF_A2_ForceCooldownTextRecolor()
    end
end

F.UpdateAurasColorControls = function()
    local br, bg, bb = F.GetAurasOwnBuffHighlightColor()
    local dr, dg, db = F.GetAurasOwnDebuffHighlightColor()
    local sr, sg, sb = F.GetAurasStackCountColor()
    local cr, cg, cb = F.GetAurasCooldownTextSafeColor()
    local wr, wg, wb = F.GetAurasCooldownTextWarningColor()
    local ur, ug, ub = F.GetAurasCooldownTextUrgentColor()
    if auraBuffTex then auraBuffTex:SetColorTexture(br, bg, bb) end
    if auraDebuffTex then auraDebuffTex:SetColorTexture(dr, dg, db) end
    if auraStacksTex then auraStacksTex:SetColorTexture(sr, sg, sb) end
    if auraCDSafeTex then auraCDSafeTex:SetColorTexture(cr, cg, cb) end
    if auraCDWarnTex then auraCDWarnTex:SetColorTexture(wr, wg, wb) end
    if auraCDUrgentTex then auraCDUrgentTex:SetColorTexture(ur, ug, ub) end


    -- Bucket-coloring master toggle: when disabled, only Safe should be configurable.
    EnsureDB()
    local gg = (MSUF_DB and MSUF_DB.general) or nil
    local bucketsEnabled = not (gg and gg.aurasCooldownTextUseBuckets == false)
    local a = bucketsEnabled and 1 or 0.35

    if auraCDWarnSwatch then
        auraCDWarnSwatch:EnableMouse(bucketsEnabled)
        auraCDWarnSwatch:SetAlpha(a)
    end
    if auraCDWarnLabel then
        auraCDWarnLabel:SetAlpha(a)
    end

    if auraCDUrgentSwatch then
        auraCDUrgentSwatch:EnableMouse(bucketsEnabled)
        auraCDUrgentSwatch:SetAlpha(a)
    end
    if auraCDUrgentLabel then
        auraCDUrgentLabel:SetAlpha(a)
    end
end

F.SetAurasOwnBuffHighlightColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasOwnBuffHighlightColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end

F.SetAurasOwnDebuffHighlightColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasOwnDebuffHighlightColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end

F.SetAurasStackCountColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasStackCountColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    F.PushAuras2ColorRefresh()
end


F.SetAurasCooldownTextSafeColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    if r == nil or gCol == nil or bCol == nil then
        g.aurasCooldownTextSafeColor = nil -- fallback to Global font color
    else
        g.aurasCooldownTextSafeColor = { r, gCol, bCol }
    end
    F.UpdateAurasColorControls()
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.PushAuras2ColorRefresh()
end

F.SetAurasCooldownTextWarningColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasCooldownTextWarningColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.PushAuras2ColorRefresh()
end

F.SetAurasCooldownTextUrgentColor = function(r, gCol, bCol)
    local g = F.EnsureAurasColorsDB()
    g.aurasCooldownTextUrgentColor = { r, gCol, bCol }
    F.UpdateAurasColorControls()
    if _G.MSUF_A2_InvalidateCooldownTextCurve then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end
    F.ForceAurasCooldownTextRecolor()
    F.PushAuras2ColorRefresh()
end

auraBuffSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasOwnBuffHighlightColor(1.0, 0.85, 0.2)
        return
    end
    local r, gCol, bCol = F.GetAurasOwnBuffHighlightColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasOwnBuffHighlightColor(nr, ng, nb)
    end)
end)

auraDebuffSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasOwnDebuffHighlightColor(1.0, 0.85, 0.2)
        return
    end
    local r, gCol, bCol = F.GetAurasOwnDebuffHighlightColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasOwnDebuffHighlightColor(nr, ng, nb)
    end)
end)

auraStacksSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasStackCountColor(1, 1, 1)
        return
    end
    local r, gCol, bCol = F.GetAurasStackCountColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasStackCountColor(nr, ng, nb)
    end)
end)

auraCDSafeSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasCooldownTextSafeColor(nil, nil, nil) -- reset to Global font color
        return
    end
    local r, gCol, bCol = F.GetAurasCooldownTextSafeColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasCooldownTextSafeColor(nr, ng, nb)
    end)
end)

auraCDWarnSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasCooldownTextWarningColor(1.00, 0.85, 0.20)
        return
    end
    local r, gCol, bCol = F.GetAurasCooldownTextWarningColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasCooldownTextWarningColor(nr, ng, nb)
    end)
end)

auraCDUrgentSwatch:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then
        F.SetAurasCooldownTextUrgentColor(1.00, 0.55, 0.10)
        return
    end
    local r, gCol, bCol = F.GetAurasCooldownTextUrgentColor()
    OpenColorPicker(r, gCol, bCol, function(nr, ng, nb)
        F.SetAurasCooldownTextUrgentColor(nr, ng, nb)
    end)
end)

auraCDResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("aura cooldown colors", function()
                F.EnsureAurasColorsDB()
                MSUF_DB.general.aurasCooldownTextSafeColor = nil
                MSUF_DB.general.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
                MSUF_DB.general.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
                if _G.MSUF_A2_InvalidateCooldownTextCurve then
                    _G.MSUF_A2_InvalidateCooldownTextCurve()
                end
                F.ForceAurasCooldownTextRecolor()
                F.UpdateAurasColorControls()
                F.PushAuras2ColorRefresh()
        end)
    end)


auraResetBtn:SetScript("OnClick", function()
        MSUF_ConfirmColorReset("aura colors", function()
                F.EnsureAurasColorsDB()
                MSUF_DB.general.aurasOwnBuffHighlightColor = { 1.0, 0.85, 0.2 }
                MSUF_DB.general.aurasOwnDebuffHighlightColor = { 1.0, 0.85, 0.2 }
                MSUF_DB.general.aurasStackCountColor = { 1, 1, 1 }
                MSUF_DB.general.aurasCooldownTextSafeColor = nil
                MSUF_DB.general.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
                MSUF_DB.general.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
                if _G.MSUF_A2_InvalidateCooldownTextCurve then
                    _G.MSUF_A2_InvalidateCooldownTextCurve()
                end
                F.ForceAurasCooldownTextRecolor()
                F.UpdateAurasColorControls()
                F.PushAuras2ColorRefresh()
        end)
    end)

F.UpdateAurasColorControls()

-- Auras section is now the lowest control for dynamic height
S.lastControl = auraCDUrgentSwatch

    --------------------------------------------------
    -- F.Refresh function
    --------------------------------------------------
    F.Refresh = function()
        -- Global font
        local fr, fg, fb = GetGlobalFontColor()
        if S.fontSwatchTex then
            S.fontSwatchTex:SetColorTexture(fr, fg, fb)
        end

        -- Class colors + Label-Kontrast
        for _, token in ipairs(CLASS_TOKENS) do
            local tex   = S.classSwatches[token]
            local label = S.classLabels[token]
            if tex then
                local r, g, b = GetClassColor(token)
                tex:SetColorTexture(r, g, b)
                F.SetLabelContrast(label, r, g, b)
            end
        end

        -- Class bar background
        if S.classBgSwatchTex then
            local br, bg, bb = GetClassBarBgColor()
            S.classBgSwatchTex:SetColorTexture(br, bg, bb)
        end

        -- Bar background tint: optional Match-HP behavior (makes swatch read-only)
        if S.classBgMatchCheck then
            local match = GetBarBgMatchHP()
            S.classBgMatchCheck:SetChecked(match)
            if _G.MSUF_Colors_ClassBarBgSwatch and _G.MSUF_Colors_ClassBarBgSwatch.EnableMouse then
                _G.MSUF_Colors_ClassBarBgSwatch:EnableMouse(not match)
                _G.MSUF_Colors_ClassBarBgSwatch:SetAlpha(match and 0.5 or 1)
            end
            if classBgResetBtn and classBgResetBtn.SetEnabled then
                classBgResetBtn:SetEnabled(not match)
            end
        end


        -- Gameplay combat state colors
        if F.UpdateGameplayCombatColorControls then
            F.UpdateGameplayCombatColorControls()
        end

        -- Gameplay crosshair range colors
        if F.UpdateGameplayCrosshairColorControls then
            F.UpdateGameplayCrosshairColorControls()
        end

        

        -- Power bar colors
        if F.UpdatePowerColorControls then
            F.UpdatePowerColorControls()
        end

        -- Class power colors (CP, DH, Stagger, etc.)
        if F.UpdateClassPowerColorControls then
            F.UpdateClassPowerColorControls()
        end

        -- Auras colors
        if F.UpdateAurasColorControls then
            F.UpdateAurasColorControls()
        end
-- Bar appearance (moved from Bars menu)
        if S.barModeDrop or S.darkToneSlider then
            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            S.barAppearanceRefreshing = true

            -- Refresh unified swatch color (in case profile changed)
            if _G.MSUF_Colors_UnifiedBarSwatch and _G.MSUF_Colors_UnifiedBarSwatch.GetRegions then
                local r, gg, b = (function()
                    local rr, ggg, bb = g.unifiedBarR, g.unifiedBarG, g.unifiedBarB
                    if type(rr) ~= "number" or type(ggg) ~= "number" or type(bb) ~= "number" then
                        rr, ggg, bb = 0.10, 0.60, 0.90
                    end
                    if rr < 0 then rr = 0 elseif rr > 1 then rr = 1 end
                    if ggg < 0 then ggg = 0 elseif ggg > 1 then ggg = 1 end
                    if bb < 0 then bb = 0 elseif bb > 1 then bb = 1 end
                    return rr, ggg, bb
                end)()
                if unifiedTex and unifiedTex.SetColorTexture then
                    unifiedTex:SetColorTexture(r, gg, b)
                end
            end

            if S.barModeDrop then
                local mode = g.barMode
                if mode ~= "dark" and mode ~= "class" and mode ~= "unified" then
                    mode = (g.useClassColors and "class") or "dark"
                    g.barMode = mode
                end
                local label = "Dark Mode (dark black bars)"
                if mode == "class" then
                    label = "Class Color Mode (color HP bars)"
                elseif mode == "unified" then
                    label = "Unified Color Mode (one color for all frames)"
                end
                UIDropDownMenu_SetSelectedValue(S.barModeDrop, mode)
                UIDropDownMenu_SetText(S.barModeDrop, label)
            end
if S.darkToneSlider then
    local pct
    if type(g.darkBarGray) == "number" then
        pct = math.floor(g.darkBarGray * 100 + 0.5)
    else
        local toneKey = g.darkBarTone
        if type(toneKey) ~= "string" or toneKey == "" then
            toneKey = "black"
        end
        if toneKey == "darkgray" then
            pct = 25
        elseif toneKey == "softgray" then
            pct = 45
        else
            pct = 0
        end
    end
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    S.darkToneSlider:SetValue(pct)
    if F.UpdateDarkToneValueText then
        F.UpdateDarkToneValueText(pct)
    end
end

            if F.UpdateDarkBarControls then F.UpdateDarkBarControls() end
            if F.UpdateDarkBgCustomControls then F.UpdateDarkBgCustomControls() end
            if F.UpdateUnifiedBarControls then F.UpdateUnifiedBarControls() end
            S.barAppearanceRefreshing = false
        end

        -- NPC colors
        if S.npcFriendlyTex then
            local r1, g1, b1 = GetNPCColor("friendly")
            S.npcFriendlyTex:SetColorTexture(r1, g1, b1)
        end
        if S.npcNeutralTex then
            local r2, g2, b2 = GetNPCColor("neutral")
            S.npcNeutralTex:SetColorTexture(r2, g2, b2)
        end
        if S.npcEnemyTex then
            local r3, g3, b3 = GetNPCColor("enemy")
            S.npcEnemyTex:SetColorTexture(r3, g3, b3)
        end
        if S.npcDeadTex then
            local r4, g4, b4 = GetNPCColor("dead")
            S.npcDeadTex:SetColorTexture(r4, g4, b4)
        end
        if S.petFrameTex then
            local pr, pg, pb = GetPetFrameColor()
            S.petFrameTex:SetColorTexture(pr, pg, pb)
        end

           -- Castbar colors
        if S.interruptibleTex or S.nonInterruptibleTex or S.interruptFeedbackTex then
            if S.interruptibleTex then
                local r, g2, b2 = GetInterruptibleCastColor()
                S.interruptibleTex:SetColorTexture(r, g2, b2)
            end
            if S.nonInterruptibleTex then
                local r, g2, b2 = GetNonInterruptibleCastColor()
                S.nonInterruptibleTex:SetColorTexture(r, g2, b2)
            end
            if S.interruptFeedbackTex then
                local r, g2, b2 = GetInterruptFeedbackCastColor()
                S.interruptFeedbackTex:SetColorTexture(r, g2, b2)
            end
        end
        -- Castbar background color
        if S.castbarBgTex then
            local r, g2, b2 = GetCastbarBackgroundColor()
            S.castbarBgTex:SetColorTexture(r, g2, b2)
        end
        -- Mouseover highlight (enable + colorpicker)
        if S.highlightEnableCheck or S.highlightColorTex then
            if F.UpdateHighlightControls then
                F.UpdateHighlightControls()
            else
                EnsureDB()
                local g = MSUF_DB.general or {}
                if S.highlightEnableCheck then
                    S.highlightEnableCheck:SetChecked(g.highlightEnabled ~= false)
                end
            end
            if S.highlightColorTex then
                local hr, hg, hb = F.GetHighlightColor()
                S.highlightColorTex:SetColorTexture(hr, hg, hb)
            end
        end
end

    --------------------------------------------------
    -- Dynamic content height
    --------------------------------------------------
    F.UpdateContentHeight = function()
        local minHeight = 400
        if not S.lastControl then
            content:SetHeight(minHeight)
            return
        end

        local bottom = S.lastControl:GetBottom()
        local top    = content:GetTop()
        if not bottom or not top then
            content:SetHeight(minHeight)
            return
        end

        local padding = 40
        local height  = top - bottom + padding
        if height < minHeight then
            height = minHeight
        end
        content:SetHeight(height)
    end

    --------------------------------------------------
    -- Register as sub-category under the main MSUF panel
    -- NOTE: Slash-menu-only mode must NOT register any Blizzard settings / interface options categories.
    --------------------------------------------------
    if not (_G and _G.MSUF_SLASHMENU_ONLY) then
        if (not panel.__MSUF_SettingsRegistered) and Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
            local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
            Settings.RegisterAddOnCategory(subcategory)
            panel.__MSUF_SettingsRegistered = true
            ns.MSUF_ColorsCategory = subcategory
        elseif InterfaceOptions_AddCategory then
            panel.parent = "Midnight Simple Unit Frames"
            InterfaceOptions_AddCategory(panel)
        end
    end

    panel:SetScript("OnShow", function()
        if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end
        F.Refresh()
        F.UpdateContentHeight()
    end)

    -- Initial refresh
    F.Refresh()
    F.UpdateContentHeight()

    if _G.MSUF_StyleAllToggles then _G.MSUF_StyleAllToggles(panel) end

    panel.__MSUF_ColorsBuilt = true
    return panel
end


-- Lightweight wrapper: register the category at login, but build the heavy UI only when opened.
function ns.MSUF_RegisterColorsOptions(parentCategory)
    if _G and _G.MSUF_SLASHMENU_ONLY then
        -- Slash-menu-only: never register Colors as a Blizzard Settings/Interface Options category.
        -- The Slash Menu is the only configuration UI.
        return
    end
    if not Settings or not Settings.RegisterCanvasLayoutSubcategory or not parentCategory then
        return ns.MSUF_RegisterColorsOptions_Full(parentCategory)
    end

    local panel = (_G and _G.MSUF_ColorsPanel) or CreateFrame("Frame", "MSUF_ColorsPanel", UIParent)
    panel.name = "Colors"

    -- IMPORTANT: Panels created with UIParent are shown by default.
    -- If we rely on OnShow for first-time build, we must ensure the panel starts hidden,
    -- otherwise the first Settings click may not fire OnShow.
    if not panel.__MSUF_ForceHidden then
        panel.__MSUF_ForceHidden = true
        panel:Hide()
    end

    if not panel.__MSUF_SettingsRegistered then
        local subcategory = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
        Settings.RegisterAddOnCategory(subcategory)
        ns.MSUF_ColorsCategory = subcategory
        panel.__MSUF_SettingsRegistered = true
    end

    if panel.__MSUF_ColorsBuilt then
        return panel
    end

    if not panel.__MSUF_LazyBuildHooked then
        panel.__MSUF_LazyBuildHooked = true

        panel:HookScript("OnShow", function()
            if panel.__MSUF_ColorsBuilt or panel.__MSUF_ColorsBuilding then
                return
            end
            panel.__MSUF_ColorsBuilding = true

            -- Build immediately (no C_Timer.After(0)): avoids "needs second click" issues.
            ns.MSUF_RegisterColorsOptions_Full(parentCategory)

            panel.__MSUF_ColorsBuilding = nil
        end)
    end

    return panel
end
