--- Shell/MSUF_GameMenu.lua
--- Adds a lightweight MSUF entry to Blizzard's Escape/Game Menu.

local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local _G = _G
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local UI = MSUF.UI or _G.MSUF_UI
local function Space(role, fallback)
    return UI and UI.Space and UI.Space(role, fallback) or fallback
end

local BUTTON_NAME = "MSUF_GameMenuButton"
local BUTTON_LABEL = "MSUF"
local ICON_PATH = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\MSUF_MinimapIcon.tga"
local ICON_SIZE = 20
local ICON_GAP = Space("sm", 8)
local BODY_OFFSET_Y = Space("md", 12)
local EXIT_OFFSET_Y = -Space("xxl", 32) + Space("xs", 4)
local HEIGHT_PADDING = Space("md", 12)
local ELLESMERE_BUTTON_KEEP = { "MSUFGameMenuIcon" }

local exitLabels = {}
local runtimeEnabled = false
local positionGeneration = 0
local initFrame
local HookGameMenu
local ellesmereSkin

local function ApplyEllesmereSkin(button)
    if not (ellesmereSkin and button) then return end
    ellesmereSkin.Button(button, ELLESMERE_BUTTON_KEEP)
    ellesmereSkin.Font(button:GetFontString())
    ellesmereSkin.WhiteButtonLabel(button)
end

local function AddExitLabel(text)
    if type(text) == "string" and text ~= "" then
        exitLabels[text] = true
    end
end

local function RefreshExitLabels()
    AddExitLabel(_G.LOGOUT)
    AddExitLabel(_G.LOG_OUT)
    AddExitLabel(_G.EXIT_GAME)
    AddExitLabel(_G.RETURN_TO_GAME)
end

local function IsExitButtonText(text)
    RefreshExitLabels()
    return type(text) == "string" and exitLabels[text] == true
end

local function IsMacroButtonText(text)
    return type(text) == "string" and type(_G.MACROS) == "string" and text == _G.MACROS
end

local function GetGeneralDB()
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    if type(db.general) ~= "table" then
        db.general = {}
    end
    return db.general
end

local function IsGameMenuButtonEnabled()
    local g = GetGeneralDB()
    if not g then return true end
    if g.showGameMenuButton == nil then
        g.showGameMenuButton = true
    end
    return g.showGameMenuButton ~= false
end

local function SetButtonLabel(button, styleSource)
    if not button then return end

    button:SetText(BUTTON_LABEL)

    local width = button.GetWidth and button:GetWidth()
    local fontString = button.GetFontString and button:GetFontString()
    local sourceFontString = styleSource and styleSource.GetFontString and styleSource:GetFontString()
    if fontString and sourceFontString then
        fontString:SetFont(sourceFontString:GetFont())
    end
    if fontString and type(fontString.SetShadowOffset) == "function" then
        fontString:SetShadowOffset(1, -1)
    end
    if fontString and type(fontString.SetShadowColor) == "function" then
        fontString:SetShadowColor(0, 0, 0, 0.75)
    end

    local textWidth = 32
    if fontString and type(fontString.GetStringWidth) == "function" then
        textWidth = fontString:GetStringWidth()
    end
    local groupOffset = (ICON_SIZE + ICON_GAP) * 0.5

    if fontString and type(fontString.ClearAllPoints) == "function" and type(fontString.SetPoint) == "function" then
        fontString:ClearAllPoints()
        fontString:SetPoint("CENTER", button, "CENTER", groupOffset, 0)
    end

    if not button.MSUFGameMenuIcon and type(button.CreateTexture) == "function" then
        local icon = button:CreateTexture(nil, "ARTWORK", nil, 1)
        icon:SetTexture(ICON_PATH)
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.MSUFGameMenuIcon = icon
    end

    local icon = button.MSUFGameMenuIcon
    if icon and fontString and type(icon.ClearAllPoints) == "function" and type(icon.SetPoint) == "function" then
        icon:ClearAllPoints()
        icon:SetPoint("RIGHT", fontString, "LEFT", -ICON_GAP, 0)
        icon:Show()
    end

    if not width or width <= 0 or not fontString or type(fontString.GetStringWidth) ~= "function" then
        return
    end

    local totalWidth = textWidth + ICON_SIZE + ICON_GAP
    if totalWidth > width - 8 and icon then
        icon:Hide()
        fontString:ClearAllPoints()
        fontString:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
end

local function OpenMSUFOptions()
    local gameMenu = _G.GameMenuFrame
    if gameMenu then
        if type(_G.HideUIPanel) == "function" then
            _G.HideUIPanel(gameMenu)
        else
            gameMenu:Hide()
        end
    end

    if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        _G.MSUF_OpenStandaloneOptionsWindow()
        return
    end
    if type(_G.MSUF_ShowStandaloneOptionsWindow) == "function" then
        _G.MSUF_ShowStandaloneOptionsWindow()
        return
    end
    if type(_G.MSUF_OpenOptionsMenu) == "function" then
        _G.MSUF_OpenOptionsMenu()
        return
    end
    if _G.SlashCmdList and type(_G.SlashCmdList["MSUF2OPTIONS"]) == "function" then
        _G.SlashCmdList["MSUF2OPTIONS"]("")
        return
    end
    if _G.SlashCmdList and type(_G.SlashCmdList["MSUFOPTIONS"]) == "function" then
        _G.SlashCmdList["MSUFOPTIONS"]("")
        return
    end
    if _G.SlashCmdList and type(_G.SlashCmdList["MIDNIGHTSUF"]) == "function" then
        _G.SlashCmdList["MIDNIGHTSUF"]("")
    end
end

local function EnsureButton()
    local gameMenu = _G.GameMenuFrame
    if not gameMenu or not CreateFrame then return nil end

    local button = gameMenu.MSUF or _G[BUTTON_NAME]
    if button then
        gameMenu.MSUF = button
        return button
    end

    local getTemplateInfo = _G.C_XMLUtil and _G.C_XMLUtil.GetTemplateInfo
    local buttonTemplate = gameMenu.buttonTemplate
    if not (getTemplateInfo and buttonTemplate and getTemplateInfo(buttonTemplate)) then
        buttonTemplate = "UIPanelButtonTemplate"
    end
    button = CreateFrame("Button", BUTTON_NAME, gameMenu, buttonTemplate)
    if not button then return nil end

    SetButtonLabel(button)
    button:SetScript("OnClick", OpenMSUFOptions)
    button:Hide()

    gameMenu.MSUF = button
    return button
end

local ellesmere = _G.EllesmereUI
if ellesmere and type(ellesmere.RegisterSkin) == "function" then
    ellesmere.RegisterSkin(tostring(addonName or "MidnightSimpleUnitFrames"), function(skin)
        ellesmereSkin = skin
        ApplyEllesmereSkin(_G[BUTTON_NAME])
    end)
end

local function GetPointSnapshot(button)
    local point, relativeTo, relativePoint, offsetX, offsetY = button:GetPoint(1)
    if not point then return nil end
    return {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        offsetX = offsetX or 0,
        offsetY = offsetY or 0,
    }
end

local function IsSamePointWithOffset(current, original, offsetY)
    if not current or not original then return false end
    if current.point ~= original.point then return false end
    if current.relativeTo ~= original.relativeTo then return false end
    if current.relativePoint ~= original.relativePoint then return false end
    if math.abs((current.offsetX or 0) - (original.offsetX or 0)) > 0.01 then return false end
    return math.abs((current.offsetY or 0) - ((original.offsetY or 0) + offsetY)) <= 0.01
end

local function ApplyButtonOffset(button, offsetY, text)
    local current = GetPointSnapshot(button)
    if not current then return false end

    local original = button.MSUFGameMenuOriginalPoint
    local lastOffset = button.MSUFGameMenuLastOffsetY or 0
    if not IsSamePointWithOffset(current, original, lastOffset) then
        original = current
        button.MSUFGameMenuOriginalPoint = original
    end

    button.MSUFGameMenuLastOffsetY = offsetY
    button.MSUFGameMenuLastText = text
    button:ClearAllPoints()
    button:SetPoint(
        original.point,
        original.relativeTo,
        original.relativePoint,
        original.offsetX,
        original.offsetY + offsetY
    )
    return true
end

local function ForEachGameMenuButton(callback)
    local gameMenu = _G.GameMenuFrame
    if not gameMenu then return false end

    local pool = gameMenu.buttonPool
    if pool and type(pool.EnumerateActive) == "function" then
        for button in pool:EnumerateActive() do
            if button and button ~= gameMenu.MSUF and type(button.GetText) == "function" then
                callback(button)
            end
        end
        return true
    end

    local customButton = gameMenu.MSUF
    local children = { gameMenu:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child ~= customButton and type(child.GetText) == "function" then
            callback(child)
        end
    end
    return true
end

local function GetBaseGameMenuHeight(gameMenu)
    local height = gameMenu:GetHeight() or 0
    local adjustedHeight = gameMenu.MSUFAdjustedHeight
    local addedHeight = gameMenu.MSUFAddedHeight or 0
    if adjustedHeight and math.abs(height - adjustedHeight) <= 0.01 then
        return height - addedHeight
    end
    return height
end

local function RestoreButtonOffset(button)
    local original = button and button.MSUFGameMenuOriginalPoint
    if not original then return false end

    local current = GetPointSnapshot(button)
    local lastOffset = button.MSUFGameMenuLastOffsetY or 0
    if current and IsSamePointWithOffset(current, original, lastOffset) then
        button:ClearAllPoints()
        button:SetPoint(
            original.point,
            original.relativeTo,
            original.relativePoint,
            original.offsetX,
            original.offsetY
        )
    end

    button.MSUFGameMenuOriginalPoint = nil
    button.MSUFGameMenuLastOffsetY = nil
    button.MSUFGameMenuLastText = nil
    return true
end

local function RestoreGameMenuLayout()
    local gameMenu = _G.GameMenuFrame
    if not gameMenu then return end

    local baseHeight = GetBaseGameMenuHeight(gameMenu)
    ForEachGameMenuButton(RestoreButtonOffset)

    local button = gameMenu.MSUF
    if button then
        button:Hide()
    end

    if gameMenu.MSUFAdjustedHeight then
        gameMenu:SetHeight(baseHeight)
        gameMenu.MSUFAdjustedHeight = nil
        gameMenu.MSUFAddedHeight = nil
    end
end

local function PositionGameMenuButton()
    local gameMenu = _G.GameMenuFrame
    if not gameMenu then return end

    if not IsGameMenuButtonEnabled() then
        RestoreGameMenuLayout()
        return
    end

    local button = EnsureButton()
    if not button then return end

    local baseHeight = GetBaseGameMenuHeight(gameMenu)
    local anchorButton
    local macroButton

    ForEachGameMenuButton(function(menuButton)
        local text = menuButton:GetText()
        if type(text) ~= "string" or text == "" then return end

        if IsExitButtonText(text) then
            ApplyButtonOffset(menuButton, EXIT_OFFSET_Y, text)
        else
            if IsMacroButtonText(text) then
                macroButton = menuButton
            end
            anchorButton = menuButton
            ApplyButtonOffset(menuButton, BODY_OFFSET_Y, text)
        end
    end)

    anchorButton = macroButton or anchorButton
    if not anchorButton then
        button:Hide()
        if gameMenu.MSUFAdjustedHeight then
            gameMenu:SetHeight(baseHeight)
            gameMenu.MSUFAdjustedHeight = nil
            gameMenu.MSUFAddedHeight = nil
        end
        return
    end

    local anchorWidth, anchorHeight = anchorButton:GetSize()
    local skinInset = ellesmereSkin and 2 or 0
    button:SetSize(math.max(1, anchorWidth - skinInset * 2), math.max(1, anchorHeight - skinInset * 2))

    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", anchorButton, "BOTTOMLEFT", skinInset, -skinInset)
    button:SetPoint("TOPRIGHT", anchorButton, "BOTTOMRIGHT", -skinInset, -skinInset)
    SetButtonLabel(button, anchorButton)
    ApplyEllesmereSkin(button)
    button:Show()

    local addedHeight = anchorHeight + HEIGHT_PADDING
    local adjustedHeight = baseHeight + addedHeight
    gameMenu.MSUFAddedHeight = addedHeight
    gameMenu.MSUFAdjustedHeight = adjustedHeight
    gameMenu:SetHeight(adjustedHeight)
end

local function QueuePositionGameMenuButton()
    if not runtimeEnabled then return end
    local generation = positionGeneration
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if runtimeEnabled and generation == positionGeneration then PositionGameMenuButton() end
        end)
    else
        PositionGameMenuButton()
    end
end

local function SetGameMenuButtonEnabled(enabled)
    local g = GetGeneralDB()
    if g then
        g.showGameMenuButton = enabled and true or false
    end

    runtimeEnabled = enabled and true or false
    positionGeneration = positionGeneration + 1
    if enabled then
        if not HookGameMenu() and initFrame then initFrame:RegisterEvent("ADDON_LOADED") end
        QueuePositionGameMenuButton()
    else
        if initFrame then initFrame:UnregisterAllEvents() end
        RestoreGameMenuLayout()
    end
end

HookGameMenu = function()
    if not runtimeEnabled then return false end
    local gameMenu = _G.GameMenuFrame
    if not gameMenu then return false end
    if gameMenu.MSUFGameMenuHooked then return true end

    EnsureButton()
    gameMenu:HookScript("OnShow", function()
        if runtimeEnabled then QueuePositionGameMenuButton() end
    end)
    gameMenu.MSUFGameMenuHooked = true
    return true
end

initFrame = CreateFrame("Frame")
runtimeEnabled = IsGameMenuButtonEnabled()
if runtimeEnabled then
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:RegisterEvent("ADDON_LOADED")
end
initFrame:SetScript("OnEvent", function(self)
    if HookGameMenu() then
        self:UnregisterEvent("PLAYER_LOGIN")
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end)

ExportPublic("MSUF_PositionGameMenuButton", PositionGameMenuButton)
ExportPublic("MSUF_SetGameMenuButtonEnabled", SetGameMenuButtonEnabled)
