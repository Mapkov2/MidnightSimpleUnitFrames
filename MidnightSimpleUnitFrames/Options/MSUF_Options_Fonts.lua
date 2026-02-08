-- Cumulative / no feature regression goal: same widgets, same DB keys, same behaviors.
-- This file replaces the previous generated split and builds the boxed Fonts UI directly.
local addonName, addonNS = ...
-- Unify ns across split option modules and Options_Core (some builds use global ns).
ns = (_G and _G.MSUF_NS) or addonNS or ns or {}
if _G then _G.MSUF_NS = ns end
function ns.MSUF_Options_Fonts_Build(panel, fontGroup)
    if not panel or not fontGroup then  return end
    -- ---------------------------------------------------------------------
    -- Compat helpers (never assume globals exist when the panel is split)
    -- ---------------------------------------------------------------------
    local function EnsureDB()
        local fn = _G and _G.EnsureDB
        if type(fn) == "function" then return fn() end
        local fn2 = (ns and ns.MSUF_UnitframeCore and ns.MSUF_UnitframeCore.UFCore_EnsureDBOnce)
            or (_G and _G.UFCore_EnsureDBOnce)
        if type(fn2) == "function" then pcall(fn2) end
     end
    local CreateLabeledSlider = (ns and (ns.MSUF_CreateLabeledSlider or ns.CreateLabeledSlider)) or _G.CreateLabeledSlider
    local MSUF_ExpandDropdownClickArea = (ns and ns.MSUF_ExpandDropdownClickArea) or _G.MSUF_ExpandDropdownClickArea
    local MSUF_MakeDropdownScrollable = (ns and ns.MSUF_MakeDropdownScrollable) or (_G and _G.MSUF_MakeDropdownScrollable)
    local MSUF_SetDropDownEnabled = (ns and ns.MSUF_SetDropDownEnabled) or (_G and _G.MSUF_SetDropDownEnabled)
    local MSUF_StyleSlider = (ns and ns.MSUF_StyleSlider) or (_G and _G.MSUF_StyleSlider)
    if type(CreateLabeledSlider) ~= "function" then
        local warn = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)
        warn:SetText("MSUF: Fonts builder missing CreateLabeledSlider (Core export).")
         return
    end
    if type(MSUF_ExpandDropdownClickArea) ~= "function" then MSUF_ExpandDropdownClickArea = function()   end end
    if type(MSUF_MakeDropdownScrollable) ~= "function" then MSUF_MakeDropdownScrollable = function()   end end
    local function MSUF_GetLSM_Compat()
        local fn = (ns and ns.MSUF_GetLSM) or (_G and _G.MSUF_GetLSM)
        if type(fn) == "function" then
            local ok, lib = pcall(fn)
            if ok then  return lib end
        end
        if _G and _G.LibStub then
            local ok, lib = pcall(_G.LibStub, "LibSharedMedia-3.0", true)
            if ok then  return lib end
        end
         return nil
    end
    local function MSUF_CallUpdateAllFonts()
        local fn = _G and (_G.MSUF_UpdateAllFonts_Immediate or _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts)
        if (not fn) and ns and ns.MSUF_UpdateAllFonts then fn = ns.MSUF_UpdateAllFonts end
        if type(fn) == "function" then fn() end
     end
    local function MSUF_Options_RequestLayoutAll_Compat(reason)
        local fn = (ns and ns.MSUF_Options_RequestLayoutAll) or (_G and _G.MSUF_Options_RequestLayoutAll)
        if type(fn) == "function" then return fn(reason) end
        local req = _G and _G.MSUF_UFCore_RequestLayoutForUnit
        if type(req) == "function" then
            for _, k in ipairs({ "player", "target", "focus", "targettarget", "pet", "boss" }) do
                pcall(req, k, reason or "OPTIONS_ALL", (k == "target" or k == "focus" or k == "targettarget"))
            end
             return
        end
        if type(_G.ApplyAllSettings) == "function" then pcall(_G.ApplyAllSettings) end
     end
    local function MSUF_EnsureCastbars_Compat()
        local fn = (ns and ns.MSUF_EnsureCastbars) or (_G and _G.MSUF_EnsureCastbars)
        if type(fn) == "function" then pcall(fn);  return end
        local ensureAddon = _G and _G.MSUF_EnsureAddonLoaded
        if type(ensureAddon) == "function" then pcall(ensureAddon, "MidnightSimpleUnitFrames_Castbars");  return end
        if _G and _G.LoadAddOn then pcall(_G.LoadAddOn, "MidnightSimpleUnitFrames_Castbars") end
     end
    -- ---------------------------------------------------------------------
    -- Tiny UI factory (spec-driven)
    -- ---------------------------------------------------------------------
    local WHITE8 = _G.MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"
    local function EnsureBackdrop(frame)
        if (not frame.SetBackdrop) and BackdropTemplateMixin and Mixin then
            Mixin(frame, BackdropTemplateMixin)
        end
        if frame.SetBackdrop then
            frame:SetBackdrop({
                bgFile = WHITE8,
                edgeFile = WHITE8,
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            frame:SetBackdropColor(0, 0, 0, 0.35)
            frame:SetBackdropBorderColor(1, 1, 1, 0.25)
        end
     end
    local function MakeBox(name, titleText)
        local box = _G[name]
        if not box then
            box = CreateFrame("Frame", name, fontGroup, "BackdropTemplate")
            EnsureBackdrop(box)
            box:SetFrameLevel(fontGroup:GetFrameLevel() + 1)
            box.MSUF_Title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            box.MSUF_Title:SetPoint("TOPLEFT", box, "TOPLEFT", 14, -12)
            box.MSUF_Title:SetText(titleText)
            box.MSUF_Line = box:CreateTexture(nil, "ARTWORK")
            box.MSUF_Line:SetColorTexture(1, 1, 1, 0.18)
            box.MSUF_Line:SetHeight(1)
            box.MSUF_Line:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -34)
            box.MSUF_Line:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -34)
        end
         return box
    end
    local function MakeSectionHeader(parent, globalKey, text)
        local fs = _G[globalKey]
        if not fs then
            fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            _G[globalKey] = fs
        end
        fs:SetText(text)
        fs:SetTextColor(1, 0.82, 0, 1)
         return fs
    end
    local function MakeCheck(name, parent, label, tooltip)
        local cb = _G[name]
        if not cb then
            cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
            cb.text = _G[name .. "Text"]
            if cb.text then cb.text:SetText(label) end
            if tooltip then cb.tooltipText = tooltip end
        end
         return cb
    end
    local function MakeDropdown(name, parent, width)
        local dd = _G[name]
        if not dd then
            dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
            MSUF_ExpandDropdownClickArea(dd)
            UIDropDownMenu_SetWidth(dd, width or 180)
            dd._msufButtonWidth = width or 180
            if width then dd:SetWidth(width) end
        end
         return dd
    end
    local function MakeHelp(parent, name, text, width)
        local fs = parent[name]
        if not fs then
            fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            parent[name] = fs
            fs:SetJustifyH("LEFT")
        end
        fs:SetWidth(width or 260)
        fs:SetText(text or "")
         return fs
    end
    local function CompactTextSizeSlider(slider, shortLabel)
        if not slider then  return end
        slider:SetWidth(110)
        local n = slider.GetName and slider:GetName()
        if n then
            local low  = _G[n .. "Low"]
            local high = _G[n .. "High"]
            local text = _G[n .. "Text"]
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
        if slider.minusButton then slider.minusButton:SetSize(18, 18) end
        if slider.plusButton then slider.plusButton:SetSize(18, 18) end
     end
    local function MakeOverrideInfo(parent, name)
        local fs = parent[name]
        if not fs then
            fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            parent[name] = fs
            fs:SetWidth(120)
            fs:SetJustifyH("CENTER")
            fs:SetText("")
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
         return fs
    end
    local function FormatOverrideSummary(list)
        if not list or #list == 0 then  return "Overrides: -", nil end
        if #list == 1 then return "Overrides: " .. list[1], list[1] end
        return "Overrides: " .. list[1] .. " +" .. tostring(#list - 1), table.concat(list, ", ")
    end
    local function ListFontOverrides(confField)
        EnsureDB()
        local out = {}
        local keys = { "player", "target", "targettarget", "focus", "pet", "boss" }
        local pretty = { player="Player", target="Target", targettarget="ToT", focus="Focus", pet="Pet", boss="Boss" }
        for _, k in ipairs(keys) do
            local c = MSUF_DB and MSUF_DB[k]
            if c and c[confField] ~= nil then out[#out + 1] = pretty[k] or k end
        end
         return out
    end
    -- ---------------------------------------------------------------------
    -- Build static layout (boxed)
    -- ---------------------------------------------------------------------
    EnsureDB()
    local left = MakeBox("MSUF_FontsMenuPanelLeft", "Font Settings")
    left:SetSize(320, 560)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 0, -110)
    local right = MakeBox("MSUF_FontsMenuPanelRight", "Font color & style")
    right:SetSize(320, 560)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 14, 0)
    -- Section headers
    local secGlobal = MakeSectionHeader(left, "MSUF_FontsMenuSection_Global", "Global font")
    local secSizes  = MakeSectionHeader(left, "MSUF_FontsMenuSection_Sizes", "Text sizes")
    local secStyle  = MakeSectionHeader(right, "MSUF_FontsMenuSection_Style", "Text style")
    local secColors = MakeSectionHeader(right, "MSUF_FontsMenuSection_Colors", "Name colors")
    local secNames  = MakeSectionHeader(right, "MSUF_FontsMenuSection_Names", "Name display")
    secGlobal:ClearAllPoints(); secGlobal:SetPoint("TOPLEFT", left, "TOPLEFT", 14, -44)
    secSizes:ClearAllPoints();  -- anchored later (after dropdown)
    secStyle:ClearAllPoints();  secStyle:SetPoint("TOPLEFT", right, "TOPLEFT", 14, -44)
    secColors:ClearAllPoints(); -- anchored later
    secNames:ClearAllPoints();  -- anchored later
    -- ---------------------------------------------------------------------
    -- Widgets spec
    -- ---------------------------------------------------------------------
    -- Font dropdown (Global)
    local fontDrop = MakeDropdown("MSUF_FontDropdown", left, 260)
    fontDrop:ClearAllPoints()
    fontDrop:SetPoint("TOPLEFT", secGlobal, "BOTTOMLEFT", -14, -8)
    MSUF_MakeDropdownScrollable(fontDrop, 12)
    -- Build choices: internal list + LibSharedMedia fonts (deduped).
    local fontChoices = {}
    local function RebuildFontChoices()
        fontChoices = {}
        local internal = (_G.MSUF_FONT_LIST or _G.FONT_LIST or {})
        for _, info in ipairs(internal) do
            fontChoices[#fontChoices + 1] = {
                key   = info.key,
                label = info.name,
                path  = info.path,
            }
        end
        local LSM = MSUF_GetLSM_Compat()
        if LSM then
            -- Register built-ins if they exist and aren't registered (noDefault check).
            if LSM.Register then
                for _, data in ipairs(fontChoices) do
                    local k, fp = data.key, data.path
                    if k and k ~= "" and fp and fp ~= "" then
                        local existing
                        if LSM.Fetch then
                            local okFetch, val = pcall(LSM.Fetch, LSM, "font", k, true) -- noDefault=true
                            if okFetch then existing = val end
                        end
                        if not existing then pcall(LSM.Register, LSM, "font", k, fp) end
                    end
                end
            end
            local names = LSM:List("font")
            table.sort(names)
            local used = {}
            for _, e in ipairs(fontChoices) do used[e.key] = true end
            for _, name in ipairs(names) do
                if not used[name] then
                    fontChoices[#fontChoices + 1] = { key = name, label = name }
                    used[name] = true
                end
            end
        end
     end
    local function SetFontDropdownText(key)
        local label = key
        for _, data in ipairs(fontChoices) do
            if data.key == key then label = data.label; break end
        end
        UIDropDownMenu_SetSelectedValue(fontDrop, key)
        UIDropDownMenu_SetText(fontDrop, label)
     end
    local function FontDropdown_Initialize(self, level)
        if not level then  return end
        EnsureDB()
        if (not fontChoices) or (#fontChoices == 0) then RebuildFontChoices() end
        local info = UIDropDownMenu_CreateInfo()
        local currentKey = (MSUF_DB and MSUF_DB.general and MSUF_DB.general.fontKey) or nil
        for _, data in ipairs(fontChoices) do
            local thisKey, thisLabel = data.key, data.label
            info.text  = thisLabel
            info.value = thisKey
            local fp = _G.MSUF_GetFontPreviewObject or _G.MSUF_GetFontPreviewObject or (ns and ns.MSUF_GetFontPreviewObject)
            if fp then
                info.fontObject = fp(thisKey)
            else
                info.fontObject = GameFontHighlightSmall
            end
            info.func = function()
                EnsureDB()
                MSUF_DB.general.fontKey = thisKey
                SetFontDropdownText(thisKey)
                MSUF_CallUpdateAllFonts()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, MSUF_CallUpdateAllFonts)
                end
             end
            info.checked = (currentKey == thisKey)
            UIDropDownMenu_AddButton(info, level)
        end
     end
    UIDropDownMenu_Initialize(fontDrop, FontDropdown_Initialize)
    -- Force an initial rebuild so SetText finds a label on first open.
    RebuildFontChoices()
    SetFontDropdownText((MSUF_DB and MSUF_DB.general and MSUF_DB.general.fontKey) or (fontChoices[1] and fontChoices[1].key) or "FRIZQT")
    -- Global "Text sizes" block
    secSizes:SetPoint("TOPLEFT", fontDrop, "BOTTOMLEFT", 14, -18)
    local textSizeHelp = MakeHelp(left, "MSUF_TextSizeHelp", "Global defaults. Frames inherit unless overridden in Unitframes > Text.", 290)
    textSizeHelp:ClearAllPoints()
    textSizeHelp:SetPoint("TOPLEFT", secSizes, "BOTTOMLEFT", 0, -4)
    local colGap = 30
    local nameFontSizeSlider = _G["MSUF_NameFontSizeSlider"] or CreateLabeledSlider("MSUF_NameFontSizeSlider", "Name", left, 8, 32, 1, 16, -250)
    local hpFontSizeSlider   = _G["MSUF_HealthFontSizeSlider"] or CreateLabeledSlider("MSUF_HealthFontSizeSlider", "Health", left, 8, 32, 1, 16, -320)
    local powerFontSizeSlider= _G["MSUF_PowerFontSizeSlider"] or CreateLabeledSlider("MSUF_PowerFontSizeSlider", "Power", left, 8, 32, 1, 16, -390)
    local castbarSpellNameFontSizeSlider = _G["MSUF_CastbarSpellNameFontSizeSlider"] or CreateLabeledSlider("MSUF_CastbarSpellNameFontSizeSlider", "Castbar", left, 0, 30, 1, 16, -460)
    -- Position sliders in 2x2 grid
    nameFontSizeSlider:ClearAllPoints()
    nameFontSizeSlider:SetPoint("TOPLEFT", textSizeHelp, "BOTTOMLEFT", 0, -18)
    hpFontSizeSlider:ClearAllPoints()
    hpFontSizeSlider:SetPoint("TOPLEFT", nameFontSizeSlider, "TOPRIGHT", colGap, 0)
    powerFontSizeSlider:ClearAllPoints()
    powerFontSizeSlider:SetPoint("TOPLEFT", nameFontSizeSlider, "BOTTOMLEFT", 0, -84)
    castbarSpellNameFontSizeSlider:ClearAllPoints()
    castbarSpellNameFontSizeSlider:SetPoint("TOPLEFT", powerFontSizeSlider, "TOPRIGHT", colGap, 0)
    CompactTextSizeSlider(nameFontSizeSlider, "Name")
    CompactTextSizeSlider(hpFontSizeSlider, "HP")
    CompactTextSizeSlider(powerFontSizeSlider, "Power")
    CompactTextSizeSlider(castbarSpellNameFontSizeSlider, "Castbar")
    -- Override info lines (Name/HP/Power only)
    local nameOverrideInfo  = MakeOverrideInfo(left, "MSUF_NameFontOverrideInfo")
    local hpOverrideInfo    = MakeOverrideInfo(left, "MSUF_HpFontOverrideInfo")
    local powerOverrideInfo = MakeOverrideInfo(left, "MSUF_PowerFontOverrideInfo")
    nameOverrideInfo:ClearAllPoints()
    nameOverrideInfo:SetPoint("TOP", nameFontSizeSlider.editBox, "BOTTOM", 0, -2)
    hpOverrideInfo:ClearAllPoints()
    hpOverrideInfo:SetPoint("TOP", hpFontSizeSlider.editBox, "BOTTOM", 0, -2)
    powerOverrideInfo:ClearAllPoints()
    powerOverrideInfo:SetPoint("TOP", powerFontSizeSlider.editBox, "BOTTOM", 0, -2)
    -- Slider handlers (global values)
    nameFontSizeSlider.onValueChanged = function(_, value)
        EnsureDB()
        MSUF_DB.general.nameFontSize = math.floor((tonumber(value) or 12) + 0.5)
        MSUF_CallUpdateAllFonts()
     end
    hpFontSizeSlider.onValueChanged = function(_, value)
        EnsureDB()
        MSUF_DB.general.hpFontSize = math.floor((tonumber(value) or 12) + 0.5)
        MSUF_CallUpdateAllFonts()
     end
    powerFontSizeSlider.onValueChanged = function(_, value)
        EnsureDB()
        MSUF_DB.general.powerFontSize = math.floor((tonumber(value) or 12) + 0.5)
        MSUF_CallUpdateAllFonts()
     end
    castbarSpellNameFontSizeSlider.onValueChanged = function(_, value)
        EnsureDB()
        MSUF_DB.general.castbarSpellNameFontSize = tonumber(value) or 12
        MSUF_EnsureCastbars_Compat()
        if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
     end
    -- Reset overrides (same popup semantics)
    local resetBtn = _G["MSUF_ResetFontOverridesBtn"]
    if not resetBtn then
        resetBtn = CreateFrame("Button", "MSUF_ResetFontOverridesBtn", left, "UIPanelButtonTemplate")
        resetBtn:SetSize(280, 20)
        resetBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 14, 14)
        resetBtn:SetText("Reset overrides")
        resetBtn.tooltipText = "Clears per-unit Name/Health/Power and per-castbar Cast Name/Time font size overrides so everything inherits the global defaults again."
    else
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 14, 14)
        resetBtn:SetWidth(280)
    end
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
                -- Clear per-castbar font size overrides (Cast Name / Cast Time)
                MSUF_DB.general = MSUF_DB.general or {}
                local gg = MSUF_DB.general
                local castUnits = { "player", "target", "focus" }
                for _, u in ipairs(castUnits) do
                    local pfx = (type(_G.MSUF_GetCastbarPrefix) == "function") and _G.MSUF_GetCastbarPrefix(u) or nil
                    if pfx then
                        gg[pfx .. "SpellNameFontSize"] = nil
                        gg[pfx .. "TimeFontSize"] = nil
                    end
                end
                gg.bossCastSpellNameFontSize = nil
                gg.bossCastTimeFontSize = nil
                MSUF_CallUpdateAllFonts()
                if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
                MSUF_EnsureCastbars_Compat()
                if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
             end,
        }
    end
    resetBtn:SetScript("OnClick", function()
            StaticPopup_Show("MSUF_RESET_FONT_OVERRIDES")
         end)
    -- Override info updater
    local function UpdateOverrideInfo()
        local list, summary, full
        list = ListFontOverrides("nameFontSize")
        summary, full = FormatOverrideSummary(list)
        nameOverrideInfo:SetText(summary)
        nameOverrideInfo.MSUF_FullOverrideList = full or ""
        list = ListFontOverrides("hpFontSize")
        summary, full = FormatOverrideSummary(list)
        hpOverrideInfo:SetText(summary)
        hpOverrideInfo.MSUF_FullOverrideList = full or ""
        list = ListFontOverrides("powerFontSize")
        summary, full = FormatOverrideSummary(list)
        powerOverrideInfo:SetText(summary)
        powerOverrideInfo.MSUF_FullOverrideList = full or ""
     end
    -- Hook once (safe)
    if not left._msufFontsOnShowHooked then
        left._msufFontsOnShowHooked = true
        left:SetScript("OnShow", function()
            EnsureDB()
            UpdateOverrideInfo()
         end)
    end
    UpdateOverrideInfo()
    -- ---------------------------------------------------------------------
    -- Right column: checkboxes + name shortening
    -- ---------------------------------------------------------------------
    local boldCheck = MakeCheck("MSUF_BoldTextCheck", right, "Use bold text (THICKOUTLINE)")
    local noOutlineCheck = MakeCheck("MSUF_NoOutlineCheck", right, "Disable black outline around text")
    local textBackdropCheck = MakeCheck("MSUF_TextBackdropCheck", right, "Add text shadow (backdrop)")
    boldCheck:ClearAllPoints()
    boldCheck:SetPoint("TOPLEFT", secStyle, "BOTTOMLEFT", -2, -8)
    noOutlineCheck:ClearAllPoints()
    noOutlineCheck:SetPoint("TOPLEFT", boldCheck, "BOTTOMLEFT", 0, -10)
    textBackdropCheck:ClearAllPoints()
    textBackdropCheck:SetPoint("TOPLEFT", noOutlineCheck, "BOTTOMLEFT", 0, -10)
    -- Divider line under "Name colors"
    local colorsLine = right.MSUF_SectionLine_Colors
    if not colorsLine then
        colorsLine = right:CreateTexture(nil, "ARTWORK")
        right.MSUF_SectionLine_Colors = colorsLine
        colorsLine:SetColorTexture(1, 1, 1, 0.20)
        colorsLine:SetHeight(1)
    end
    secColors:SetPoint("TOPLEFT", textBackdropCheck, "BOTTOMLEFT", 2, -18)
    colorsLine:ClearAllPoints()
    colorsLine:SetPoint("TOPLEFT", secColors, "BOTTOMLEFT", -16, -4)
    colorsLine:SetWidth(286)
    local nameClassColorCheck = MakeCheck("MSUF_NameClassColorCheck", right, "Color player names by class")
    local npcNameRedCheck = MakeCheck("MSUF_NPCNameRedCheck", right, "Color NPC/boss names using NPC colors")
    local powerTextColorByTypeCheck = MakeCheck("MSUF_PowerTextColorByTypeCheck", right, "Color power text by power type")
    nameClassColorCheck:ClearAllPoints()
    nameClassColorCheck:SetPoint("TOPLEFT", colorsLine, "BOTTOMLEFT", 14, -8)
    npcNameRedCheck:ClearAllPoints()
    npcNameRedCheck:SetPoint("TOPLEFT", nameClassColorCheck, "BOTTOMLEFT", 0, -10)
    powerTextColorByTypeCheck:ClearAllPoints()
    powerTextColorByTypeCheck:SetPoint("TOPLEFT", npcNameRedCheck, "BOTTOMLEFT", 0, -10)
    -- Divider line under "Name display"
    local namesLine = right.MSUF_SectionLine_Names
    if not namesLine then
        namesLine = right:CreateTexture(nil, "ARTWORK")
        right.MSUF_SectionLine_Names = namesLine
        namesLine:SetColorTexture(1, 1, 1, 0.20)
        namesLine:SetHeight(1)
    end
    secNames:SetPoint("TOPLEFT", powerTextColorByTypeCheck, "BOTTOMLEFT", 2, -18)
    namesLine:ClearAllPoints()
    namesLine:SetPoint("TOPLEFT", secNames, "BOTTOMLEFT", -16, -4)
    namesLine:SetWidth(286)
    local shortenNamesCheck = MakeCheck("MSUF_ShortenNamesCheck", right, "Shorten unit names (except Player)")
    shortenNamesCheck:ClearAllPoints()
    shortenNamesCheck:SetPoint("TOPLEFT", namesLine, "BOTTOMLEFT", 14, -8)
    -- Truncation style dropdown
    local shortenNameClipSideLabel = right.MSUF_ShortenNameClipSideLabel
    if not shortenNameClipSideLabel then
        shortenNameClipSideLabel = right:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        right.MSUF_ShortenNameClipSideLabel = shortenNameClipSideLabel
        shortenNameClipSideLabel:SetText("Truncation style")
    end
    shortenNameClipSideLabel:ClearAllPoints()
    shortenNameClipSideLabel:SetPoint("TOPLEFT", shortenNamesCheck, "BOTTOMLEFT", 16, -10)
    local shortenNameClipSideDrop = MakeDropdown("MSUF_ShortenNameClipSideDrop", right, 180)
    shortenNameClipSideDrop:ClearAllPoints()
    shortenNameClipSideDrop:SetPoint("TOPLEFT", shortenNameClipSideLabel, "BOTTOMLEFT", -16, -2)
    local function GetClipSideLabel(value)
        if value == "RIGHT" then  return "Keep start (show first letters)" end
         return "Keep end (show last letters)"
    end
    -- Sliders (use OptionsSliderTemplate for the two legacy controls)
    local shortenNameMaxCharsSlider = _G["MSUF_ShortenNameMaxCharsSlider"]
    if not shortenNameMaxCharsSlider then
        shortenNameMaxCharsSlider = CreateFrame("Slider", "MSUF_ShortenNameMaxCharsSlider", right, "OptionsSliderTemplate")
        shortenNameMaxCharsSlider:SetWidth(180)
        shortenNameMaxCharsSlider:SetMinMaxValues(6, 30)
        shortenNameMaxCharsSlider:SetValueStep(1)
        shortenNameMaxCharsSlider:SetObeyStepOnDrag(true)
        if MSUF_StyleSlider then MSUF_StyleSlider(shortenNameMaxCharsSlider) end
        _G["MSUF_ShortenNameMaxCharsSliderLow"]:SetText("6")
        _G["MSUF_ShortenNameMaxCharsSliderHigh"]:SetText("30")
        _G["MSUF_ShortenNameMaxCharsSliderText"]:SetText("Max name length")
    end
    shortenNameMaxCharsSlider:ClearAllPoints()
    shortenNameMaxCharsSlider:SetPoint("TOPLEFT", shortenNameClipSideDrop, "BOTTOMLEFT", 16, -12)
    local shortenNameFrontMaskSlider = _G["MSUF_ShortenNameFrontMaskSlider"]
    if not shortenNameFrontMaskSlider then
        shortenNameFrontMaskSlider = CreateFrame("Slider", "MSUF_ShortenNameFrontMaskSlider", right, "OptionsSliderTemplate")
        shortenNameFrontMaskSlider:SetWidth(180)
        shortenNameFrontMaskSlider:SetMinMaxValues(0, 40)
        shortenNameFrontMaskSlider:SetValueStep(1)
        shortenNameFrontMaskSlider:SetObeyStepOnDrag(true)
        if MSUF_StyleSlider then MSUF_StyleSlider(shortenNameFrontMaskSlider) end
        _G["MSUF_ShortenNameFrontMaskSliderLow"]:SetText("0")
        _G["MSUF_ShortenNameFrontMaskSliderHigh"]:SetText("40")
        _G["MSUF_ShortenNameFrontMaskSliderText"]:SetText("Reserved space")
    end
    shortenNameFrontMaskSlider:ClearAllPoints()
    shortenNameFrontMaskSlider:SetPoint("TOPLEFT", shortenNameMaxCharsSlider, "BOTTOMLEFT", 0, -20)
    -- Info button
    local infoBtn = _G["MSUF_ShortenNameInfoButton"]
    if not infoBtn then
        infoBtn = CreateFrame("Button", "MSUF_ShortenNameInfoButton", right)
        infoBtn:SetSize(16, 16)
        infoBtn:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
        infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        infoBtn:SetHitRectInsets(-4, -4, -4, -4)
        infoBtn:SetScript("OnClick", function(self)
            if GameTooltip:IsOwned(self) and GameTooltip:IsShown() then
                GameTooltip:Hide()
                 return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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
    end
    infoBtn:ClearAllPoints()
    infoBtn:SetPoint("TOPLEFT", shortenNameFrontMaskSlider, "BOTTOMLEFT", 0, -6)
    -- ---------------------------------------------------------------------
    -- DB load/apply + scripts (single place, spec-driven)
    -- ---------------------------------------------------------------------
    local function ClampInt(v, lo, hi, fallback)
        v = tonumber(v)
        if v == nil then v = fallback end
        v = math.floor(v + 0.5)
        if lo and v < lo then v = lo end
        if hi and v > hi then v = hi end
         return v
    end
    local function UpdateShortenMaskLabel()
        local g = MSUF_DB and MSUF_DB.general or {}
        local side = g.shortenNameClipSide or "LEFT"
        local shortenEnabled = (MSUF_DB and MSUF_DB.shortenNames) and true or false
        local t = _G["MSUF_ShortenNameFrontMaskSliderText"]
        if t and t.SetText then
            if (not shortenEnabled) then
                t:SetText("Reserved space")
            elseif side == "RIGHT" then
                t:SetText("Reserved space (unused)")
            else
                t:SetText("Reserved space (left)")
            end
        end
        if shortenNameFrontMaskSlider and shortenNameFrontMaskSlider.Enable and shortenNameFrontMaskSlider.Disable then
            if (not shortenEnabled) or (side == "RIGHT") then
                shortenNameFrontMaskSlider:Disable()
            else
                shortenNameFrontMaskSlider:Enable()
            end
        end
     end
    local function ApplyFromDB()
        EnsureDB()
        if not MSUF_DB or not MSUF_DB.general then  return end
        local g = MSUF_DB.general
        -- defaults (keep same semantics as previous file)
        if g.shortenNameMaxChars == nil then g.shortenNameMaxChars = 6 end
        if g.shortenNameFrontMaskPx == nil then g.shortenNameFrontMaskPx = 8 end
        if g.shortenNameClipSide == nil then g.shortenNameClipSide = "LEFT" end
        if g.shortenNameShowDots == nil then g.shortenNameShowDots = true end
        g.shortenNameMaxChars = ClampInt(g.shortenNameMaxChars, 4, 40, 6)
        g.shortenNameFrontMaskPx = ClampInt(g.shortenNameFrontMaskPx, 0, 40, 8)
        boldCheck:SetChecked(g.boldText and true or false)
        noOutlineCheck:SetChecked(g.noOutline and true or false)
        textBackdropCheck:SetChecked(g.textBackdrop and true or false)
        nameClassColorCheck:SetChecked(g.nameClassColor and true or false)
        npcNameRedCheck:SetChecked(g.npcNameRed and true or false)
        powerTextColorByTypeCheck:SetChecked(g.colorPowerTextByType and true or false)
        shortenNamesCheck:SetChecked(MSUF_DB.shortenNames and true or false)
        shortenNameMaxCharsSlider:SetValue(g.shortenNameMaxChars)
        shortenNameFrontMaskSlider:SetValue(g.shortenNameFrontMaskPx)
        UIDropDownMenu_SetSelectedValue(shortenNameClipSideDrop, g.shortenNameClipSide)
        UIDropDownMenu_SetText(shortenNameClipSideDrop, GetClipSideLabel(g.shortenNameClipSide))
        UpdateShortenMaskLabel()
        local enabled = (MSUF_DB.shortenNames and true or false)
        if enabled then shortenNameMaxCharsSlider:Enable() else shortenNameMaxCharsSlider:Disable() end
        if enabled then shortenNameFrontMaskSlider:Enable() else shortenNameFrontMaskSlider:Disable() end
        if MSUF_SetDropDownEnabled then MSUF_SetDropDownEnabled(shortenNameClipSideDrop, shortenNameClipSideLabel, enabled) end
        -- global size sliders (keep current values)
        if g.nameFontSize ~= nil and nameFontSizeSlider.SetValue then nameFontSizeSlider:SetValue(g.nameFontSize) end
        if g.hpFontSize ~= nil and hpFontSizeSlider.SetValue then hpFontSizeSlider:SetValue(g.hpFontSize) end
        if g.powerFontSize ~= nil and powerFontSizeSlider.SetValue then powerFontSizeSlider:SetValue(g.powerFontSize) end
        if g.castbarSpellNameFontSize ~= nil and castbarSpellNameFontSizeSlider.SetValue then castbarSpellNameFontSizeSlider:SetValue(g.castbarSpellNameFontSize) end
     end
    -- Dropdown: truncation style
    UIDropDownMenu_Initialize(shortenNameClipSideDrop, function(self, level)
        if not level then  return end
        EnsureDB()
        local current = (MSUF_DB.general and MSUF_DB.general.shortenNameClipSide) or "LEFT"
        local function AddOption(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = function()
                EnsureDB()
                MSUF_DB.general.shortenNameClipSide = value
                UIDropDownMenu_SetSelectedValue(shortenNameClipSideDrop, value)
                UIDropDownMenu_SetText(shortenNameClipSideDrop, GetClipSideLabel(value))
                UpdateShortenMaskLabel()
                if MSUF_DB.shortenNames then
                    MSUF_CallUpdateAllFonts()
                    if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
                end
             end
            info.checked = (current == value)
            UIDropDownMenu_AddButton(info, level)
         end
        AddOption("Keep end (show last letters)", "LEFT")
        AddOption("Keep start (show first letters)", "RIGHT")
     end)
    -- Scripts (checkboxes)
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
    textBackdropCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.textBackdrop = self:GetChecked() and true or false
        MSUF_CallUpdateAllFonts()
     end)
    nameClassColorCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.nameClassColor = self:GetChecked() and true or false
        if type(_G.MSUF_RefreshAllIdentityColors) == "function" then _G.MSUF_RefreshAllIdentityColors() end
     end)
    npcNameRedCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.npcNameRed = self:GetChecked() and true or false
        if type(_G.MSUF_RefreshAllIdentityColors) == "function" then _G.MSUF_RefreshAllIdentityColors() end
     end)
    powerTextColorByTypeCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.general.colorPowerTextByType = self:GetChecked() and true or false
        if type(_G.MSUF_RefreshAllPowerTextColors) == "function" then _G.MSUF_RefreshAllPowerTextColors() end
        MSUF_CallUpdateAllFonts()
     end)
    shortenNamesCheck:SetScript("OnClick", function(self)
        EnsureDB()
        MSUF_DB.shortenNames = self:GetChecked() and true or false
        local enabled = (MSUF_DB.shortenNames and true or false)
        if enabled then shortenNameMaxCharsSlider:Enable() else shortenNameMaxCharsSlider:Disable() end
        if enabled then shortenNameFrontMaskSlider:Enable() else shortenNameFrontMaskSlider:Disable() end
        if MSUF_SetDropDownEnabled then MSUF_SetDropDownEnabled(shortenNameClipSideDrop, shortenNameClipSideLabel, enabled) end
        UpdateShortenMaskLabel()
        MSUF_Options_RequestLayoutAll_Compat("SHORTEN_NAMES")
        MSUF_CallUpdateAllFonts()
        if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
     end)
    shortenNameMaxCharsSlider:SetScript("OnValueChanged", function(_, value)
        EnsureDB()
        value = ClampInt(value, 4, 40, 16)
        MSUF_DB.general.shortenNameMaxChars = value
        if MSUF_DB.shortenNames then
            MSUF_CallUpdateAllFonts()
            if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
        end
     end)
    shortenNameFrontMaskSlider:SetScript("OnValueChanged", function(_, value)
        EnsureDB()
        value = ClampInt(value, 0, 40, 8)
        MSUF_DB.general.shortenNameFrontMaskPx = value
        if MSUF_DB.shortenNames then
            MSUF_CallUpdateAllFonts()
            if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
        end
     end)
    -- ---------------------------------------------------------------------
    -- Shared color list (kept for backward compat with Core/other panels)
    -- ---------------------------------------------------------------------
    local colorList = {
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
    panel.__MSUF_COLOR_LIST = colorList
    _G.MSUF_COLOR_LIST = colorList
    -- Final: apply DB state (idempotent)
    ApplyFromDB()
    -- Expose choices for any Core load/rebuild logic
    panel.__MSUF_FontChoices = fontChoices
    panel.__MSUF_RebuildFontChoices = RebuildFontChoices
    -- Expose key widgets for other modules (kept for backward compat)
    panel.fontDrop = fontDrop
    panel.nameFontSizeSlider = nameFontSizeSlider
    panel.hpFontSizeSlider = hpFontSizeSlider
    panel.powerFontSizeSlider = powerFontSizeSlider
    panel.castbarSpellNameFontSizeSlider = castbarSpellNameFontSizeSlider
    panel.boldCheck = boldCheck
    panel.noOutlineCheck = noOutlineCheck
    panel.textBackdropCheck = textBackdropCheck
    panel.nameClassColorCheck = nameClassColorCheck
    panel.npcNameRedCheck = npcNameRedCheck
    panel.powerTextColorByTypeCheck = powerTextColorByTypeCheck
    panel.shortenNamesCheck = shortenNamesCheck
    panel.shortenNameClipSideDrop = shortenNameClipSideDrop
    panel.shortenNameMaxCharsSlider = shortenNameMaxCharsSlider
    panel.shortenNameFrontMaskSlider = shortenNameFrontMaskSlider
 end
