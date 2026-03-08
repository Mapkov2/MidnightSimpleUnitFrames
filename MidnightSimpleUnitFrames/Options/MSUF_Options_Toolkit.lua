-- ---------------------------------------------------------------------------
-- MSUF_Options_Toolkit.lua
-- Shared UI helper functions used by multiple Options split modules.
-- Loads BEFORE MSUF_Options_Core.lua in the TOC.
-- Zero feature regression: same helpers, same signatures, same behaviors.
-- ---------------------------------------------------------------------------
local addonName, addonNS = ...
ns = (_G and _G.MSUF_NS) or addonNS or ns or {}
if _G then _G.MSUF_NS = ns end

-- ---------------------------------------------------------------------------
-- Localization helper (keys are English UI strings; fallback = key)
-- ---------------------------------------------------------------------------
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end

-- ============================================================
-- Options UI helpers (shared across all Options split modules)
-- ============================================================
local function MSUF_AttachTooltip(widget, titleText, bodyText)
    if not widget or (not titleText and not bodyText) then  return end
    widget:HookScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if titleText then GameTooltip:SetText(titleText, 1, 1, 1) end
            if bodyText then GameTooltip:AddLine(bodyText, 0.9, 0.9, 0.9, true) end
            GameTooltip:Show()
        end
     end)
    widget:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
     end)
 end
local function UI_Text(parent, textValue, template)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    fs:SetText(textValue or "")
     return fs
end
local function UI_Btn(parent, name, label, onClick, w, h)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 140, h or 24)
    b:SetText(label or "")
    if onClick then b:SetScript("OnClick", onClick) end
     return b
end
-- ============================================================
-- Button row builder (used by Profiles, potentially others)
-- ============================================================
-- Builds a single horizontal row of buttons and returns (rowFrame, buttonsById).
-- defs: { {id="reset", name="MyBtn", text="Reset", w=140, h=24, onClick=function() end }, ... }
local function MSUF_BuildButtonRowList(parent, anchor, gap, defs)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(1, 1)
    local buttons = {}
    local last
    gap = tonumber(gap) or 8
    for i = 1, #defs do
        local d = defs[i]
        local id = d.id or ("b" .. i)
        local btn = UI_Btn(parent, d.name, d.text, d.onClick, d.w, d.h)
        buttons[id] = btn
        if not last then
            btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(tonumber(d.y) or 10))
        else
            btn:SetPoint("LEFT", last, "RIGHT", gap, 0)
        end
        last = btn
    end
    -- Size row to cover the buttons (best-effort)
    if last and last.GetRight and defs[1] and buttons[defs[1].id or "b1"] then
        local first = buttons[defs[1].id or "b1"]
        row:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
        row:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
    end
     return row, buttons
end
-- ============================================================
-- Dropdown scroll system (scrollable dropdown menus)
-- ============================================================
local function MSUF_ResetDropdownListScroll(listFrame)
    if not listFrame or not listFrame._msufScrollActive then  return end
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
                        btn._msufRelPoint or "TOPLEFT",
                        btn._msufOffsX or 0,
                        btn._msufOffsY or 0
                    )
                end
                if btn.Show then btn:Show() end
            end
        end
    end
    listFrame._msufScrollActive = false
    listFrame._msufScrollOffset = 0
    if listFrame._msufScrollBar and listFrame._msufScrollBar.Hide then listFrame._msufScrollBar:Hide() end
    -- Restore original height
    if listFrame._msufOrigHeight and listFrame.SetHeight then
        listFrame:SetHeight(listFrame._msufOrigHeight)
    end
 end
local function MSUF_ApplyDropdownListScroll(listFrame, maxVisible)
    if not listFrame then  return end
    local listName = listFrame.GetName and listFrame:GetName() or nil
    if not listName then  return end

    maxVisible = maxVisible or 12

    -- Count visible items: can vary per open (e.g. SharedMedia lists have many, scope lists have few).
    -- Step height is best read from the first button; fall back to the Blizzard global if missing
    -- (client changes to UIDROPDOWNMENU_BUTTON_HEIGHT).
    local totalVisible = 0
    local step = tonumber(_G.UIDROPDOWNMENU_BUTTON_HEIGHT) or 16
    do
        local firstBtn = _G[listName .. "Button1"]
        if firstBtn and firstBtn.GetHeight then
            local h = firstBtn:GetHeight()
            if h and h > 1 then step = h end
        end
    end
    local numButtons = tonumber(listFrame.numButtons) or 0
    for i = 1, numButtons do
        local btn = _G[listName .. "Button" .. i]
        if btn and btn.IsShown and btn:IsShown() then totalVisible = totalVisible + 1 end
    end

    local border = tonumber(_G.UIDROPDOWNMENU_BORDER_HEIGHT) or 15

    if totalVisible <= maxVisible then
        MSUF_ResetDropdownListScroll(listFrame)
         return
    end

    -- Ensure the scrollbar frame exists (create once, reuse)
    local sb = listFrame._msufScrollBar
    if not sb then
        sb = _G.CreateFrame("Slider", nil, listFrame, "UIPanelScrollBarTemplate")
        sb:SetWidth(16)
        sb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -8, -(border + 2))
        sb:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -8, (border + 2))
        sb:SetValueStep(1)
        sb:SetObeyStepOnDrag(true)
        sb._msufListFrame = listFrame
        sb._msufMaxVisible = maxVisible
        sb:SetScript("OnValueChanged", function(self, value)
            local lf = self._msufListFrame
            if not lf then  return end
            local offset = math.floor(value + 0.5)
            lf._msufScrollOffset = offset
            local ln = lf.GetName and lf:GetName() or nil
            if not ln then  return end
            local nb = tonumber(lf.numButtons) or 0
            local st = self._msufStep or step
            local mv = self._msufMaxVisible or maxVisible
            for i = 1, nb do
                local btn = _G[ln .. "Button" .. i]
                if btn then
                    if i > offset and i <= (offset + mv) then
                        local visIdx = i - offset
                        if btn.ClearAllPoints and btn.SetPoint then
                            btn:ClearAllPoints()
                            btn:SetPoint(
                                "TOPLEFT",
                                lf,
                                "TOPLEFT",
                                btn._msufOffsX or 17,
                                -((visIdx - 1) * st + (tonumber(_G.UIDROPDOWNMENU_BORDER_HEIGHT) or 15))
                            )
                        end
                        if btn.Show then btn:Show() end
                    else
                        if btn.Hide then btn:Hide() end
                    end
                end
            end
         end)
        listFrame._msufScrollBar = sb
    end

    -- Save original positions once (before we start moving buttons around)
    for i = 1, numButtons do
        local btn = _G[listName .. "Button" .. i]
        if btn and not btn._msufBasePoint then
            local point, relativeTo, relativePoint, xOfs, yOfs = btn:GetPoint(1)
            btn._msufBasePoint = point or "TOPLEFT"
            btn._msufRelPoint  = relativePoint or "TOPLEFT"
            btn._msufOffsX     = xOfs or 17
            btn._msufOffsY     = yOfs or 0
        end
    end

    -- Shrink the list frame to maxVisible height
    local newH = maxVisible * step + border * 2
    if not listFrame._msufOrigHeight then
        listFrame._msufOrigHeight = listFrame.GetHeight and listFrame:GetHeight() or newH
    end
    listFrame:SetHeight(newH)
    listFrame._msufScrollActive = true
    listFrame._msufScrollOffset = 0

    sb._msufStep = step
    sb._msufMaxVisible = maxVisible
    sb:SetMinMaxValues(0, totalVisible - maxVisible)
    sb:SetValue(0)
    sb:Show()
end
-- Tweak bar-texture dropdown button widths (so they never cover the scrollbar)
local function MSUF_TweakBarTextureDropdownList(listFrame)
    if not listFrame then  return end
    local listName = listFrame.GetName and listFrame:GetName() or nil
    if not listName then  return end
    -- Identify the dropdown that owns this list (walk up via UIDROPDOWNMENU_OPEN_MENU or parentLevel).
    -- We only want to tweak dropdowns that have the _msufTweakBarTexturePreview flag.
    local owner = _G.UIDROPDOWNMENU_OPEN_MENU
    if not owner then  return end
    if type(owner) == "string" then owner = _G[owner] end
    if not (owner and owner._msufTweakBarTexturePreview) then  return end
    -- Desired button width: owner-configured or 180 (so the scrollbar never overlaps the right edge).
    local bw = owner._msufButtonWidth or 180
    local numButtons = tonumber(listFrame.numButtons) or 0
    for i = 1, numButtons do
        local btn = _G[listName .. "Button" .. i]
        if btn and btn.SetWidth then
            btn:SetWidth(bw)
        end
    end
    -- Prevent the list background from being wider than needed.
    if listFrame.SetWidth then listFrame:SetWidth(bw + 55) end
 end
local function MSUF_EnsureDropdownScrollHook()
    if _G._msufDropdownScrollHooked then  return end
    _G._msufDropdownScrollHooked = true
    _G.hooksecurefunc("ToggleDropDownMenu", function(level, value, dropDownFrame)
        level = level or 1
        if level ~= 1 then  return end
        local listFrame = _G["DropDownList1"]
        local sp = _G.SettingsPanel or _G.InterfaceOptionsFrame
        if not listFrame then  return end
        -- Only apply to MSUF's own options panels
        if dropDownFrame and dropDownFrame.GetParent then
            -- We purposely don't check; just always try to apply to avoid missing edge cases.
        end
        MSUF_TweakBarTextureDropdownList(listFrame)
        if not dropDownFrame then  return end
        local maxV = dropDownFrame._msufMaxScrollVisible
        if maxV then
            MSUF_ApplyDropdownListScroll(listFrame, maxV)
        else
            MSUF_ResetDropdownListScroll(listFrame)
        end
     end)
end
local function MSUF_MakeDropdownScrollable(dropdown, maxVisible)
    if not dropdown then  return end
    dropdown._msufMaxScrollVisible = maxVisible or 12
    MSUF_EnsureDropdownScrollHook()
 end
-- Expand the clickable area of a Blizzard UIDropDownMenu so the whole dropdown "box" is clickable,
-- not just the tiny right-edge arrow button.
local function MSUF_ExpandDropdownClickArea(dropdown)
    if not dropdown then  return end
    -- The "Button" child is the clickable trigger. We expand its hit area to cover the whole dropdown.
    local name = dropdown.GetName and dropdown:GetName()
    local btn = dropdown.Button or (name and _G[name .. "Button"])
    if not btn then  return end
    local function Apply()
        local w = dropdown.GetWidth and dropdown:GetWidth()
        if not (w and w > 1) then  return end
        -- Shift the hit rect left by the dropdown width minus the button width (~24px),
        -- plus a small buffer so the entire visible dropdown area is clickable.
        local bw = btn.GetWidth and btn:GetWidth() or 24
        local extra = w - bw + 8
        if extra > 0 then
            btn:SetHitRectInsets(-extra, 0, 0, 0)
        end
     end
    -- Apply on key events where the dropdown may have been resized.
    dropdown:HookScript("OnShow", Apply)
    dropdown:HookScript("OnSizeChanged", Apply)
    local name = dropdown.GetName and dropdown:GetName()
    local btn = dropdown.Button or (name and _G[name .. "Button"])
    if btn and btn.HookScript then btn:HookScript("OnSizeChanged", Apply) end
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Apply)
    else
        Apply()
    end
 end
-- ============================================================
-- Simple "enum" dropdown helper
-- ============================================================
local function MSUF_InitSimpleDropdown(dropdown, options, getCurrentKey, setCurrentKey, onSelect, width)
    if not dropdown then  return end
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local cur = (getCurrentKey and getCurrentKey()) or nil
        for _, opt in ipairs(options or {}) do
            info.text = opt.menuText or opt.label
            info.value = opt.key
            info.checked = (opt.key == cur)
            info.func = function(btn)
                if setCurrentKey then setCurrentKey(btn.value) end
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, opt.label)
                if type(onSelect) == "function" then onSelect(btn.value, opt)
                elseif type(onSelect) == "string" and _G and type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply(onSelect, btn.value, opt) end
             end
            UIDropDownMenu_AddButton(info, level)
        end
     end)
    if width then UIDropDownMenu_SetWidth(dropdown, width) end
    local cur = (getCurrentKey and getCurrentKey()) or nil
    local labelText = (options and options[1] and options[1].label) or ""
    for _, opt in ipairs(options or {}) do
        if opt.key == cur then labelText = opt.label break end
    end
    UIDropDownMenu_SetSelectedValue(dropdown, cur)
    UIDropDownMenu_SetText(dropdown, labelText)
 end
-- Keep dropdown text/selected value in sync (e.g. when reopening panels)
local function MSUF_SyncSimpleDropdown(dropdown, options, getCurrentKey)
    if not dropdown or not options or not getCurrentKey then  return end
    local cur = getCurrentKey()
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dropdown, cur) end
    for _, opt in ipairs(options) do
        if opt.key == cur then
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, opt.label) end
            break
        end
    end
 end

-- ============================================================
-- Export to ns.* and _G (split modules resolve from ns; legacy from _G)
-- ============================================================
ns.MSUF_AttachTooltip          = ns.MSUF_AttachTooltip          or MSUF_AttachTooltip
ns.MSUF_UI_Text                = ns.MSUF_UI_Text                or UI_Text
ns.MSUF_UI_Btn                 = ns.MSUF_UI_Btn                 or UI_Btn
ns.MSUF_BuildButtonRowList     = ns.MSUF_BuildButtonRowList     or MSUF_BuildButtonRowList
ns.MSUF_MakeDropdownScrollable = ns.MSUF_MakeDropdownScrollable or MSUF_MakeDropdownScrollable
ns.MSUF_ExpandDropdownClickArea = ns.MSUF_ExpandDropdownClickArea or MSUF_ExpandDropdownClickArea
ns.MSUF_InitSimpleDropdown     = ns.MSUF_InitSimpleDropdown     or MSUF_InitSimpleDropdown
ns.MSUF_SyncSimpleDropdown     = ns.MSUF_SyncSimpleDropdown     or MSUF_SyncSimpleDropdown
-- _G exports (backward compat for ClassPower and other modules that probe _G)
if _G then
    _G.MSUF_InitSimpleDropdown  = _G.MSUF_InitSimpleDropdown  or MSUF_InitSimpleDropdown
    _G.MSUF_SyncSimpleDropdown  = _G.MSUF_SyncSimpleDropdown  or MSUF_SyncSimpleDropdown
end
