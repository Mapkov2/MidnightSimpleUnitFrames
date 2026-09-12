local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Auras page: compact Custom Aura workspace.
-- Owns M.BuildAuras3CompactCustomWorkspace, the one-tool-at-a-time editor for
-- Custom 1-3, Defensive Buffs and Dots on target inside UnitFrame > Auras. Split
-- It binds AuraSettings/AuraControls directly and is called lazily from the
-- unit Auras section.
local AurasPage = M.AurasPage
if type(AurasPage) ~= "table" then return end
local W = M.Widgets
local T = M.Theme
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local VTP = M.ValueTextPairs
local CreateFrame = _G.CreateFrame
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local tonumber, tostring, type, pairs = tonumber, tostring, type, pairs
local BindSwitch, BindSlider = M.BindSwitchAt, M.BindSliderAt
local BindDropdown, BindTextInput = M.BindDropdownAt, M.BindTextInputAt
local AURA_COOLDOWN_COLOR_REFERENCES, AURA_SHARED_COLOR_NOTE = M.AuraSettings.AURA_COOLDOWN_COLOR_REFERENCES, M.AuraSettings.AURA_SHARED_COLOR_NOTE
local AURA_SORT_DIRECTION_VALUES, ActionButton = M.AuraSettings.AURA_SORT_DIRECTION_VALUES, M.AuraControls.ActionButton
local AddAuraTooltipHelp, AddTooltip, AnchorLabel = M.AuraControls.AddAuraTooltipHelp, M.AuraControls.AddTooltip, M.AuraSettings.AnchorLabel
local ApplyUnit, AuraCatalogToken, AuraControlMeta = M.AuraControls.ApplyUnit, M.AuraControls.AuraCatalogToken, M.AuraControls.AuraControlMeta
local AuraControlMetaAtVisiblePath, AuraSortMethodValues = M.AuraControls.AuraControlMetaAtVisiblePath, M.AuraSettings.AuraSortMethodValues
local COOLDOWN_SWIPE_DIRECTION_VALUES, CUSTOM_FRAME_EFFECTS = M.AuraSettings.COOLDOWN_SWIPE_DIRECTION_VALUES, M.AuraSettings.CUSTOM_FRAME_EFFECTS
local ChoiceLabel, ConfigureAuraSpellPriorityDrag = M.AuraSettings.ChoiceLabel, M.AuraControls.ConfigureAuraSpellPriorityDrag
local ConfigureMaxDurationSlider, DEBUFF_TYPE_BORDER_MODE_VALUES = M.AuraControls.ConfigureMaxDurationSlider, M.AuraSettings.DEBUFF_TYPE_BORDER_MODE_VALUES
local DURATION_BAR_DIRECTION_VALUES, DURATION_BAR_DISPLAY_VALUES = M.AuraSettings.DURATION_BAR_DIRECTION_VALUES, M.AuraSettings.DURATION_BAR_DISPLAY_VALUES
local DURATION_BAR_POSITION_VALUES, MatchSuffix = M.AuraSettings.DURATION_BAR_POSITION_VALUES, M.AuraSettings.MatchSuffix
local NATIVE_EXACT_AURA_FILTERS_TEXT, NormalizeAuraSortMethodForLane = M.AuraSettings.NATIVE_EXACT_AURA_FILTERS_TEXT, M.AuraSettings.NormalizeAuraSortMethodForLane
local QueueAurasPageRefresh, Rebuild, RegisterAuraControl = M.AuraControls.QueueAurasPageRefresh, M.AuraControls.Rebuild, M.AuraControls.RegisterAuraControl
local RegisterAuraTextAction, Round, Tr = M.AuraControls.RegisterAuraTextAction, M.AuraSettings.Round, M.AuraSettings.Tr
local function CustomStyleSectionId(index, suffix)
    return "aura_style_custom_" .. tostring(index or 1) .. "_" .. tostring(suffix or "section")
end
local CUSTOM_AURA_TYPES = VTP "BUFF=Buff|DEBUFF=Debuff"
-- Reminder is the container's operating mode, not a styling detail: it turns
-- a compacting list into one fixed slot per whitelisted entry. It belongs
-- next to Aura type, where the other structural decision already lives.
local CUSTOM_DISPLAY_MODES = VTP "active=Only active auras|reminder=Fixed slots (reminder)"
-- Every tool builder below receives the workspace record C and re-establishes the
-- same local names the inline body used; a builder returns true when its tool
-- matched, so the dispatcher keeps the original first-match order.
local function BuildCustomDefensivesTool(C)
    local ctx, b, unit, index, tool, customActionPath, isPlayerDefensives, Apply = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.isPlayerDefensives, C.Apply
    if tool == "defensives" and isPlayerDefensives then
        local section = b:Section("Defensive Buffs", 560)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local predefined = type(Model.PlayerDefensiveClassEntries) == "function"
            and Model.PlayerDefensiveClassEntries(true) or {}
        local predefinedStatus = W.Text(section, "", 24, -34, inner, T.colors.accent)
        local searchValue = ""
        local RefreshPredefined
        local refreshCustom
        local searchInput = BindTextInput(ctx, section, "Search", 24, -58, inner,
            function() return searchValue end,
            function(value)
                searchValue = tostring(value or "")
                if RefreshPredefined then RefreshPredefined() end
                if refreshCustom then refreshCustom() end
            end,
            true, AuraControlMeta(ctx, "custom-container.player-defensives.search", "ephemeral"))
        if searchInput and searchInput.HookScript then
            searchInput:HookScript("OnTextChanged", function(self)
                searchValue = self.GetText and tostring(self:GetText() or "") or ""
                if RefreshPredefined then RefreshPredefined() end
                if refreshCustom then refreshCustom() end
            end)
        end
        local predefinedScroll = CreateFrame("ScrollFrame", nil, section)
        predefinedScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -108)
        predefinedScroll:SetSize(inner - 20, 184)
        local predefinedChild = CreateFrame("Frame", nil, predefinedScroll)
        predefinedChild:SetSize(inner - 44, max(184, #predefined * 30))
        predefinedScroll:SetScrollChild(predefinedChild)
        M._StyleNestedAuraScrollFrame(predefinedScroll, section, 30)
        local predefinedSwitches = {}
        local predefinedIcons = {}
        RefreshPredefined = function()
            local enabledCount = 0
            local visibleCount = 0
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            for i = 1, #predefined do
                local entry = predefined[i]
                local enabled = Model.PlayerDefensiveSpellEnabled(unit, entry.spellID)
                if enabled then enabledCount = enabledCount + 1 end
                local switch = predefinedSwitches[i]
                if switch then switch:SetChecked(enabled) end
                local icon = predefinedIcons[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                local shown = query == "" or haystack:find(query, 1, true) ~= nil
                if shown then
                    local y = -(visibleCount * 30)
                    visibleCount = visibleCount + 1
                    if icon then
                        icon:ClearAllPoints()
                        icon:SetPoint("TOPLEFT", predefinedChild, "TOPLEFT", 0, y)
                    end
                    if switch then
                        switch:ClearAllPoints()
                        switch:SetPoint("TOPLEFT", predefinedChild, "TOPLEFT", 30, y - 1)
                    end
                end
                if icon then icon:SetShown(shown) end
                if switch then switch:SetShown(shown) end
            end
            predefinedStatus:SetText(M.Format("%d / %d predefined enabled", enabledCount, #predefined)
                .. MatchSuffix(query, visibleCount))
            predefinedChild:SetHeight(max(184, visibleCount * 30))
        end
        for i = 1, #predefined do
            local entry = predefined[i]
            local spellID = entry.spellID
            local icon = predefinedChild:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", predefinedChild, "TOPLEFT", 0, -((i - 1) * 30))
            icon:SetSize(22, 22)
            icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            predefinedIcons[i] = icon
            local switch = W.SwitchAt(predefinedChild, entry.text or tostring(spellID),
                30, -((i - 1) * 30) - 1, inner - 104)
            switch:SetScript("OnClick", function(self)
                local changed = Model.SetPlayerDefensiveSpellEnabled(unit, spellID, self:GetChecked())
                if changed then Apply("AURAS3_PLAYER_DEFENSIVE_PREDEFINED_TOGGLE", true) end
                RefreshPredefined()
            end)
            AddTooltip(switch, entry.text or tostring(spellID),
                "Track this predefined defensive buff. The setting applies to both the defensive bar and the optional portrait icon.")
            predefinedSwitches[i] = switch
        end
        M.TrackRefresh(ctx, RefreshPredefined)
        local customInputValue = ""
        local customInput = BindTextInput(ctx, section, "Track a buff - Spell ID, link, or name", 24, -322, max(140, inner - 132),
            function() return customInputValue end,
            function(value) customInputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.player-defensives.custom-id", "ephemeral"))
        local addCustom = ActionButton(section, "Add buff", 108)
        addCustom:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -344)
        addCustom:SetScript("OnClick", function()
            local value = customInput and customInput.GetText and customInput:GetText() or customInputValue
            local changed = Model.AddCustomContainerSpell(unit, index, value, true)
            if changed then
                if customInput and customInput.SetText then customInput:SetText("") end
                customInputValue = ""
                Apply("AURAS3_PLAYER_DEFENSIVE_CUSTOM_ADD", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, addCustom, customInput, "Add buff",
            customActionPath .. ".defensives.custom-id.add", {
                actionKey = "aura_custom_whitelist_add_spell",
                actionFixedArgs = { scope = unit, index = index },
                actionInputArg = "value",
            })
        AddTooltip(customInput, "Exact aura tracking",
            "Enter a Spell ID, paste a spell link, or type a spell name. The visible helpful aura is matched even when its buff ID differs from the cast Spell ID.")
        local status = W.Text(section, "", 24, -392, inner, T.colors.accent)
        local empty = W.Text(section, "No custom buffs added.", 24, -442, inner, T.colors.muted)
        local listScroll = CreateFrame("ScrollFrame", nil, section)
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -418)
        listScroll:SetSize(inner - 20, 118)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 104)
        listScroll:SetScrollChild(listChild)
        M._StyleNestedAuraScrollFrame(listScroll, section, 32)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Button", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 24))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 24))
            row:SetHeight(20)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row, "LEFT", 3, 0)
            row.icon:SetSize(17, 17)
            row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row:SetScript("OnClick", function(self)
                if self._spellID and Model.RemoveCustomContainerSpell(unit, index, self._spellID) then
                    Apply("AURAS3_PLAYER_DEFENSIVE_CUSTOM_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            rows[i] = row
            return row
        end
        refreshCustom = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local enabledPredefined = type(Model.PlayerDefensivePreviewEntries) == "function"
                and #Model.PlayerDefensivePreviewEntries() or 0
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            status:SetText(M.Format("%d predefined enabled · %d custom · click a custom entry to remove",
                enabledPredefined, #entries) .. MatchSuffix(query, #visible))
            empty:SetText(#entries == 0 and Tr("No custom buffs added.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(118, #visible * 24))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.text:SetText(entry.text or tostring(entry.spellID))
                    RegisterAuraControl(ctx, row, entry.text or tostring(entry.spellID), "button",
                        customActionPath .. ".defensives.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    row:Show()
                elseif row then row._spellID = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshCustom)
        return true
    end
end

local function BuildCustomDotsTool(C)
    local ctx, b, unit, index, tool, customActionPath, isTargetDots, item, Apply = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.isTargetDots, C.item, C.Apply
    if tool == "dots" and isTargetDots then
        local section = b:Section("Dots on target", 430)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local values = type(Model.TargetDotValues) == "function" and Model.TargetDotValues() or {}
        local selected
        for i = 1, #values do
            if values[i].value then selected = values[i].value; break end
        end
        local dropdown = BindDropdown(ctx, section, "DoT", 24, -34, values, max(140, inner - 132),
            function() return selected end,
            function(value) selected = value end,
            AuraControlMeta(ctx, "custom-container.target-dots.selection", "ephemeral"))
        local add = ActionButton(section, "Track DoT", 108)
        add:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -56)
        add:SetScript("OnClick", function()
            local changed = selected and Model.AddCustomContainerSpell(unit, index, selected)
            if changed then Apply("AURAS3_TARGET_DOT_ADD", true); Rebuild(ctx) end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, {
            SetText = function(_, value) selected = value end,
        }, "Track DoT", customActionPath .. ".dots.add", {
            actionKey = "aura_custom_whitelist_add_spell",
            actionFixedArgs = { scope = unit, index = index },
            actionInputArg = "value",
        })
        AddTooltip(dropdown, "Target DoT", "Curated Retail 12.0+ and 12.1 DoT auras. Tracking is restricted to this UnitFrame's unit and your own aura source; Boss settings bind separately to boss1 through boss5.")
        local customInputValue = ""
        local customInput = BindTextInput(ctx, section, "Custom Spell ID", 24, -94, max(140, inner - 132),
            function() return customInputValue end,
            function(value) customInputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.target-dots.custom-id", "ephemeral"))
        local addCustom = ActionButton(section, "Add Custom ID", 108)
        addCustom:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -116)
        addCustom:SetScript("OnClick", function()
            local value = customInput and customInput.GetText and customInput:GetText() or customInputValue
            local changed = Model.AddCustomContainerSpell(unit, index, value, true)
            if changed then
                if customInput and customInput.SetText then customInput:SetText("") end
                customInputValue = ""
                Apply("AURAS3_TARGET_DOT_CUSTOM_ADD", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, addCustom, customInput, "Add Custom ID", customActionPath .. ".dots.custom-id.add", {
            actionKey = "aura_custom_whitelist_add_spell",
            actionFixedArgs = { scope = unit, index = index },
            actionInputArg = "value",
        })
        AddTooltip(customInput, "Custom Spell ID",
            "Adds an exact harmful aura ID that is missing from the curated list. The aura is still restricted to your current target and your own aura source.")
        local status = W.Text(section, "", 24, -162, inner, T.colors.accent)
        local searchValue = ""
        local refreshList
        local searchInput = BindTextInput(ctx, section, "Search", 24, -186, inner,
            function() return searchValue end,
            function(value)
                searchValue = tostring(value or "")
                if refreshList then refreshList() end
            end,
            true, AuraControlMeta(ctx, "custom-container.target-dots.search", "ephemeral"))
        if searchInput and searchInput.HookScript then
            searchInput:HookScript("OnTextChanged", function(self)
                searchValue = self.GetText and tostring(self:GetText() or "") or ""
                if refreshList then refreshList() end
            end)
        end
        local empty = W.Text(section, "No DoT selected. Choose one above or add a custom Spell ID.", 24, -288, inner, T.colors.muted)
        local listScroll = CreateFrame("ScrollFrame", nil, section)
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -236)
        listScroll:SetSize(inner - 20, 164)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 164)
        listScroll:SetScrollChild(listChild)
        M._StyleNestedAuraScrollFrame(listScroll, section, 32)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Frame", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 34))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 34))
            row:SetHeight(30)
            if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
            row.rank = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
            row.rank:SetPoint("LEFT", row, "LEFT", 7, 0)
            row.rank:SetWidth(24)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
            row.icon:SetSize(20, 20)
            row.text = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            row.up = ActionButton(row, "Up", 38)
            row.up:SetPoint("RIGHT", row, "RIGHT", -84, 0)
            row.down = ActionButton(row, "Down", 48)
            row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
            row.remove = ActionButton(row, "X", 30, "danger")
            row.remove:SetPoint("LEFT", row.down, "RIGHT", 3, 0)
            row.text:SetPoint("RIGHT", row.up, "LEFT", -8, 0)
            row.up:SetScript("OnClick", function()
                if row._spellID and Model.MoveCustomContainerSpell(unit, index, row._spellID, -1) then
                    Apply("AURAS3_TARGET_DOT_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            row.down:SetScript("OnClick", function()
                if row._spellID and Model.MoveCustomContainerSpell(unit, index, row._spellID, 1) then
                    Apply("AURAS3_TARGET_DOT_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            row.remove:SetScript("OnClick", function()
                if row._spellID and Model.RemoveCustomContainerSpell(unit, index, row._spellID) then
                    Apply("AURAS3_TARGET_DOT_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            AddTooltip(row.up, "Move up", "Raises this DoT in the fixed priority order.")
            AddTooltip(row.down, "Move down", "Lowers this DoT in the fixed priority order.")
            AddTooltip(row.remove, "Remove DoT", "Stops tracking this DoT.")
            AddTooltip(row, "Drag to reorder", "Drag this row to a new position. Reordering activates Custom Priority.")
            ConfigureAuraSpellPriorityDrag(row, row, listChild, 34, function(spellID, target)
                if Model.MoveCustomContainerSpellToIndex(unit, index, spellID, target) then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                    Apply("AURAS3_TARGET_DOT_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            rows[i] = row
            return row
        end
        refreshList = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            local customPriority = tostring(item.placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
            status:SetText(M.Format("%d tracked DoTs", #entries)
                .. (customPriority and query ~= "" and Tr(" - clear Search to reorder")
                    or customPriority and Tr(" - dynamic priority active")
                    or Tr(" - drag to set Custom Priority"))
                .. MatchSuffix(query, #visible))
            empty:SetText(#entries == 0 and Tr("No DoT selected. Choose one above or add a custom Spell ID.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(164, #visible * 34))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.rank:SetText("#" .. tostring(entry.priority or i))
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.text:SetText(entry.text or tostring(entry.spellID))
                    RegisterAuraControl(ctx, row.remove, "Remove " .. (entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    RegisterAuraControl(ctx, row.up, "Raise " .. (entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".up", "action")
                    RegisterAuraControl(ctx, row.down, "Lower " .. (entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".down", "action")
                    if type(W.SetControlsEnabled) == "function" then
                        W.SetControlsEnabled({ row.up }, customPriority and query == "" and (entry.priority or i) > 1)
                        W.SetControlsEnabled({ row.down }, customPriority and query == "" and (entry.priority or i) < #entries)
                    end
                    row._entryCount = #entries
                    row._displayIndex = i
                    row._dragEnabled = query == "" and #entries > 1
                    row:Show()
                elseif row then row._spellID = nil; row._displayIndex = nil; row._dragEnabled = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshList)
        return true
    end
end

local function BuildCustomWhitelistEnchants(C)
    local ctx, b, unit, index, customActionPath, item, Apply, Grid = C.ctx, C.b, C.unit, C.index, C.customActionPath, C.item, C.Apply, C.Grid
    if unit == "player" then
        local ench = b:CollapsibleSection("aura_reminder_enchants_" .. tostring(index),
            "Weapon enchants", 284, false)
        local ew = ench._msuf2Width or b.width or 720
        local eInner = ew - 48
        local ecol, egap = Grid(ew, 2)
        local enchantMain = BindSwitch(ctx, ench, "Track the Main Hand enchant", 24, -46, ecol,
            function() return item.reminderEnchantMainHand == true end,
            function(value)
                item.reminderEnchantMainHand = value == true
                Apply("AURAS3_CUSTOM_REMINDER_ENCHANT", true)
                Rebuild(ctx)
            end,
            AuraControlMeta(ctx, "custom-container.reminder.enchant-main-hand"))
        AddTooltip(enchantMain, "Track the Main Hand enchant",
            "Adds a reminder slot for the temporary enchant on your main hand - a weapon oil, a stone or a weapon-applied poison. Unlike an aura this state is plainly readable, so the icon lights up while the enchant runs and dims when it is gone, in every kind of content.")
        local enchantOff = BindSwitch(ctx, ench, "Track the Off Hand enchant", 24 + ecol + egap, -46, ecol,
            function() return item.reminderEnchantOffHand == true end,
            function(value)
                item.reminderEnchantOffHand = value == true
                Apply("AURAS3_CUSTOM_REMINDER_ENCHANT", true)
                Rebuild(ctx)
            end,
            AuraControlMeta(ctx, "custom-container.reminder.enchant-off-hand"))
        AddTooltip(enchantOff, "Track the Off Hand enchant",
            "Same slot for your off hand. Both hands share the consumable set below, which is what you normally want.")
        local enchantInputValue = ""
        local enchantInputW = max(140, min(floor(eInner * 0.62), eInner - 132))
        local enchantInput = BindTextInput(ctx, ench, "Oil or stone - item link or ID", 24, -96, enchantInputW,
            function() return enchantInputValue end,
            function(value) enchantInputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.reminder.enchant-item", "ephemeral"))
        local enchantSet = ActionButton(ench, "Bind item", 118, "primary")
        enchantSet:SetPoint("TOPLEFT", ench, "TOPLEFT", 36 + enchantInputW, -120)
        enchantSet:SetScript("OnClick", function()
            local value = enchantInput and enchantInput.GetText and enchantInput:GetText() or enchantInputValue
            local changed = Model.SetCustomContainerReminderEnchantItem(unit, index, value)
            if changed then
                if enchantInput and enchantInput.SetText then enchantInput:SetText("") end
                enchantInputValue = ""
                Apply("AURAS3_CUSTOM_REMINDER_ENCHANT_ITEM", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, enchantSet, enchantInput, "Bind item",
            customActionPath .. ".reminder.enchant-item.set", {
                actionKey = "aura_custom_reminder_enchant_item",
                actionFixedArgs = { scope = unit, index = index }, actionInputArg = "value",
            })
        AddTooltip(enchantInput, "Oil or stone",
            "Paste the consumable these slots should offer on click. A weapon enchant cannot be cast, so only an item makes them clickable. Leave it empty to keep them as pure indicators.")
        local enchantDuration = BindSlider(ctx, ench, "Enchant duration (minutes)", 24, -160,
            5, 240, 5, eInner,
            function() return tonumber(item.reminderEnchantDurationMinutes) or 60 end,
            function(value)
                item.reminderEnchantDurationMinutes = tonumber(value) or 60
                Apply("AURAS3_CUSTOM_REMINDER_ENCHANT_DURATION", true)
            end,
            AuraControlMeta(ctx, "custom-container.reminder.enchant-duration"))
        AddTooltip(enchantDuration, "Weapon enchant duration",
            "Sets the swipe's full duration because Blizzard exposes only the remaining time. Oils normally use 60 minutes. Change this for stones or poisons with a different duration.")
        local enchantStatus = W.Text(ench, "", 24, -226, eInner, T.colors.muted)
        M.TrackRefresh(ctx, function()
            local reminder = item.placed.reminderEnabled == true
            local tracked = (item.reminderEnchantMainHand == true and 1 or 0)
                + (item.reminderEnchantOffHand == true and 1 or 0)
            local itemID, itemName = Model.CustomContainerReminderEnchantItem(unit, index)
            if type(W.SetControlsEnabled) == "function" then
                W.SetControlsEnabled({ enchantMain, enchantOff }, reminder)
                W.SetControlsEnabled({ enchantInput, enchantSet, enchantDuration }, reminder and tracked > 0)
            end
            if not reminder then
                enchantStatus:SetText(Tr("Needs Display set to Fixed slots in Setup · enchants have no aura to show otherwise."))
            elseif tracked == 0 then
                enchantStatus:SetText(Tr("No weapon slot tracked."))
            elseif itemID then
                enchantStatus:SetText(M.Format("Click uses %s.", tostring(itemName or ("item:" .. tostring(itemID)))))
            else
                enchantStatus:SetText(Tr("No item bound · these slots only indicate."))
            end
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(ench, {{
                    text = tracked > 0 and M.Format("%d tracked", tracked) or Tr("Off"),
                    kind = tracked > 0 and "accent" or "muted", showWhenClosed = true,
                }})
            end
        end)
    end
end

local function BuildCustomWhitelistTool(C)
    local ctx, b, unit, index, tool, customActionPath, containerLabel, item, Apply = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.containerLabel, C.item, C.Apply
    if tool == "whitelist" then
        local section = b:Section(containerLabel .. " Whitelist", 430)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local auraType = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
        local auraNoun = auraType == "DEBUFF" and "debuff" or "buff"
        local auraPlural = auraNoun .. "s"
        -- Whole sentences per lane: inserting the noun with %s breaks declension in
        -- German and Russian. `auraNoun` itself stays raw - it feeds Assistant action ids.
        local isDebuff = auraType == "DEBUFF"
        local addLabel = isDebuff and Tr("Add debuff") or Tr("Add buff")
        local trackHint = isDebuff and Tr("Add a debuff - Spell ID, spell link or item link")
            or Tr("Add a buff - Spell ID, spell link or item link")
        local addBody = isDebuff and Tr("Adds this exact debuff to the custom container.")
            or Tr("Adds this exact buff to the custom container.")
        local removeBody = isDebuff and Tr("Stops tracking this debuff in the custom container.")
            or Tr("Stops tracking this buff in the custom container.")
        W.Text(section, auraType, 24, -36, 58, T.colors.accent)
        W.Text(section, Tr(NATIVE_EXACT_AURA_FILTERS_TEXT), 88, -36, inner - 64, T.colors.muted)
        local inputValue = ""
        local inputW = max(140, min(floor(inner * 0.62), inner - 120))
        local input = BindTextInput(ctx, section, trackHint, 24, -76, inputW,
            function() return inputValue end, function(value) inputValue = value or "" end,
            false, AuraControlMeta(ctx, "custom-container.whitelist.input", "ephemeral"))
        local add = ActionButton(section, addLabel, 108, "primary")
        add:SetPoint("TOPLEFT", section, "TOPLEFT", 36 + inputW, -100)
        add:SetScript("OnClick", function()
            local value = input and input.GetText and input:GetText() or inputValue
            local changed = Model.AddCustomContainerSpell(unit, index, value)
            if changed then
                if input and input.SetText then input:SetText("") end
                inputValue = ""
                Apply("AURAS3_CUSTOM_WHITELIST_ADD", true)
                Rebuild(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, input, "Add " .. auraNoun, customActionPath .. ".whitelist.add", {
            actionKey = "aura_custom_whitelist_add_spell", actionFixedArgs = { scope = unit, index = index }, actionInputArg = "value",
        })
        AddTooltip(input, "Exact aura tracking",
            "Enter a Spell ID, paste a spell link, or type a spell name. This whitelist tracks exact Spell IDs. Paste an item link instead to track the buff that item applies and offer the item itself on click - flasks, runes, stones and potions all work that way. If the item's buff differs from its use effect, put both on one line: the Spell ID decides what is tracked, the item what a click uses.")
        AddTooltip(add, addLabel, addBody)
        local status = W.Text(section, "", 24, -136, floor(inner * 0.52), T.colors.accent)
        local empty = W.Text(section, "No spells tracked. Add up to 40 exact SpellIDs.",
            24, -238, inner, T.colors.muted)
        local searchValue = ""
        local refreshList
        local searchInput = BindTextInput(ctx, section, "Search", 24, -164, inner,
            function() return searchValue end,
            function(value)
                searchValue = tostring(value or "")
                if refreshList then refreshList() end
            end,
            true, AuraControlMeta(ctx, "custom-container.whitelist.search", "ephemeral"))
        if searchInput and searchInput.HookScript then
            searchInput:HookScript("OnTextChanged", function(self)
                searchValue = self.GetText and tostring(self:GetText() or "") or ""
                if refreshList then refreshList() end
            end)
        end
        local listScroll = CreateFrame("ScrollFrame", nil, section)
        listScroll:SetPoint("TOPLEFT", section, "TOPLEFT", 24, -214)
        listScroll:SetSize(inner - 20, 190)
        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(inner - 44, 190)
        listScroll:SetScrollChild(listChild)
        M._StyleNestedAuraScrollFrame(listScroll, section, 44)
        local rows = {}
        local function EnsureRow(i)
            local row = rows[i]
            if row then return row end
            row = CreateFrame("Frame", nil, listChild)
            row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 44))
            row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 44))
            row:SetHeight(40)
            if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
            row.rank = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
            row.rank:SetPoint("LEFT", row, "LEFT", 7, 0)
            row.rank:SetWidth(24)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("LEFT", row.rank, "RIGHT", 3, 0)
            row.icon:SetSize(28, 28)
            row.name = T.Font(row, "GameFontHighlightSmall", "", T.colors.text)
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 9, -1)
            row.id = T.Font(row, "GameFontDisableSmall", "", T.colors.muted)
            row.id:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 9, 1)
            row.remove = ActionButton(row, "Remove", 80)
            row.remove:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            -- Two static buttons instead of one relabelled one: the styled
            -- action button has no guaranteed text setter, and a fixed label
            -- always states what the click will do.
            row.keepOn = ActionButton(row, "Always show", 96)
            row.keepOn:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
            row.keepOff = ActionButton(row, "Filter again", 96)
            row.keepOff:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
            row.keepOn:Hide()
            row.keepOff:Hide()
            row.keepOn:SetScript("OnClick", function()
                if row._spellID and Model.ToggleCustomContainerKeepSpell(unit, index, row._spellID, true) then
                    Apply("AURAS3_CUSTOM_REMINDER_KEEP", true)
                    Rebuild(ctx)
                end
            end)
            row.keepOff:SetScript("OnClick", function()
                if row._spellID and Model.ToggleCustomContainerKeepSpell(unit, index, row._spellID, false) then
                    Apply("AURAS3_CUSTOM_REMINDER_KEEP", true)
                    Rebuild(ctx)
                end
            end)
            AddTooltip(row.keepOn, "Always show",
                "Pins this entry so the self-cast filter never hides it. Use it for anything that is not a class ability - a flask, food, a rune, a buff someone else casts on you. MSUF cannot tell those apart from another class's spell on its own: nothing reports which class owns a Spell ID.")
            AddTooltip(row.keepOff, "Filter again",
                "Lets the self-cast filter decide about this entry again. It will be hidden on characters that cannot cast it.")
            row.name:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
            -- The second line carries the Spell ID and what a click does, so it
            -- needs the same right edge as the name. Without it the text runs
            -- straight under the Remove button on a narrow menu.
            row.id:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
            row.id:SetJustifyH("LEFT")
            row.id:SetWordWrap(false)
            row.remove:SetScript("OnClick", function()
                if row._spellID and Model.RemoveCustomContainerSpell(unit, index, row._spellID) then
                    Apply("AURAS3_CUSTOM_WHITELIST_REMOVE", true)
                    Rebuild(ctx)
                end
            end)
            AddTooltip(row.remove, "Remove from whitelist", removeBody)
            AddTooltip(row, "Drag to reorder", "Drag this row to a new position. Reordering activates Custom Priority.")
            ConfigureAuraSpellPriorityDrag(row, row, listChild, 44, function(spellID, target)
                if Model.MoveCustomContainerSpellToIndex(unit, index, spellID, target) then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                    Apply("AURAS3_CUSTOM_PRIORITY", true)
                    Rebuild(ctx)
                end
            end)
            rows[i] = row
            return row
        end
        refreshList = function()
            local entries = Model.CustomContainerSpellEntries(unit, index)
            local query = tostring(searchValue or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            local customPriority = tostring(item.placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
            local visible = {}
            for i = 1, #entries do
                local entry = entries[i]
                local haystack = (tostring(entry.text or "") .. " " .. tostring(entry.spellID or "")):lower()
                if query == "" or haystack:find(query, 1, true) then visible[#visible + 1] = entry end
            end
            status:SetText(tostring("Tracked ") .. auraPlural .. " (" .. tostring(#entries) .. " of 40)"
                .. (customPriority and query ~= "" and Tr(" - clear Search to reorder")
                    or customPriority and Tr(" - dynamic priority active")
                    or Tr(" - drag to set Custom Priority"))
                .. MatchSuffix(query, #visible))
            empty:SetText(#entries == 0 and Tr("No spells tracked. Add up to 40 exact SpellIDs.")
                or M.Format(Tr("No results for \"%s\"."), query))
            empty:SetShown(#visible == 0)
            listScroll:SetShown(#visible > 0)
            listChild:SetHeight(max(190, #visible * 44))
            for i = 1, max(#rows, #visible) do
                local row, entry = rows[i], visible[i]
                if entry then
                    row = EnsureRow(i)
                    row._spellID = entry.spellID
                    row.rank:SetText("#" .. tostring(entry.priority or i))
                    row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local name = tostring(entry.text or entry.spellID or "Spell"):gsub("%s*%(#%d+%)$", "")
                    row.name:SetText(name)
                    -- Say plainly what a click on this row will do. A tracked
                    -- aura the player cannot apply has no click action, and a
                    -- silently dead button is worse than a visible hint.
                    local clickNote = entry.clickAction == "item" and Tr("Click uses this item")
                        or entry.clickAction == "spell" and Tr("Click casts this")
                        or Tr("No click action \194\183 paste an item")
                    -- The self-cast filter is the only thing that can make a
                    -- whitelisted row disappear, so the row has to say so itself
                    -- rather than letting it vanish without explanation.
                    local filtering = item.placed.reminderEnabled == true
                        and item.placed.reminderOnlyCastable == true
                    local exempt = entry.keep == true
                    local stateNote = ""
                    if filtering and exempt then
                        stateNote = " \194\183 " .. Tr("always shown")
                    elseif filtering and not entry.clickAction then
                        stateNote = " \194\183 " .. Tr("hidden on this character")
                    end
                    row.id:SetText(tostring("Spell ID ") .. tostring(entry.spellID)
                        .. " \194\183 " .. clickNote .. stateNote)
                    -- Only offered where it changes anything: with the filter off,
                    -- or on a row a bound item already protects, it is noise.
                    local offerKeep = filtering and entry.itemID == nil
                    row.keepOn:SetShown(offerKeep and not entry.keepExplicit)
                    row.keepOff:SetShown(offerKeep and entry.keepExplicit == true)
                    if offerKeep then
                        row.name:SetPoint("RIGHT", row.keepOn, "LEFT", -8, 0)
                        row.id:SetPoint("RIGHT", row.keepOn, "LEFT", -8, 0)
                    else
                        row.name:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
                        row.id:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
                    end
                    RegisterAuraControl(ctx, row.remove, "Remove " .. name, "button",
                        customActionPath .. ".whitelist.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    row._entryCount = #entries
                    row._displayIndex = i
                    row._dragEnabled = query == "" and #entries > 1
                    row:Show()
                elseif row then row._spellID = nil; row._displayIndex = nil; row._dragEnabled = nil; row:Hide() end
            end
        end
        M.TrackRefresh(ctx, refreshList)

        -- Temporary weapon enchants are not auras at all -- Blizzard keeps them
        -- out of aura parsing, groups and slots -- so they cannot ride the list
        -- above. They still belong on this tab: "what is tracked" should be one
        -- question with one answer, not two places to look.
        BuildCustomWhitelistEnchants(C)
        return true
    end
end

local function BuildCustomFiltersTool(C)
    local ctx, b, tool, isPlayerDefensives, isTargetDots, containerLabel, item, Apply, Grid = C.ctx, C.b, C.tool, C.isPlayerDefensives, C.isTargetDots, C.containerLabel, C.item, C.Apply, C.Grid
    local WriteMaxDuration = function(value)
item.filters.maxDuration = Round(min(180, max(0, tonumber(value) or 0)))
                Apply("AURAS3_CUSTOM_MAX_DURATION", true)
end

    if tool == "filters" then
        if isPlayerDefensives or isTargetDots then
            local section = b:Section(containerLabel .. " Filters", 160)
            local w = section._msuf2Width or b.width or 720
            local inner = w - 48
            local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24, -40, inner,
                function() return item.filters.hidePermanent == true end,
                function(value)
                    item.filters.hidePermanent = value == true
                    Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true)
                end,
                AuraControlMeta(ctx, "custom-container.filters.hide-permanent"))
            AddTooltip(hidePermanent, "Hide permanent auras",
                "Always excludes auras without a duration.")
            local maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration",
                24, -92, 0, 180, 1, inner,
                function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
                WriteMaxDuration,
                AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {
                    assistantDisposition = "compound",
                    assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
                })))
            M.TrackRefresh(ctx, function()
                W.SetControlEnabled(hidePermanent, true)
                W.SetControlEnabled(maxDuration, true)
            end)
            return true
        end
        local specs = item.auraType == "DEBUFF" and {
            { "Only mine", "onlyMine" }, { "Raid", "raid" }, { "Raid combat", "raidInCombat" }, { "Nameplate-only", "includeNameplateOnly" },
            { "Removable by group", "includeDispellable" }, { "Any removable type", "dispellableAny" },
            { "Important", "onlyImportant" }, { "Crowd control", "crowdControl" },
        } or {
            { "Only mine", "onlyMine" }, { "Important", "onlyImportant" }, { "Raid", "raid" }, { "Raid combat", "raidInCombat" }, { "Nameplate-only", "includeNameplateOnly" },
            { "Removable by group", "includeDispellable" }, { "Any removable type", "dispellableAny" },
            { "Cancelable", "cancelable", { "notCancelable" } }, { "Not cancelable", "notCancelable", { "cancelable" } },
            { "External defensive", "externalDefensive" }, { "Big defensive", "bigDefensive" },
        }
        local optionRows = max(1, ceil(#specs / 4))
        local section = b:Section(containerLabel .. " Filters", 160 + optionRows * 32)
        local w = section._msuf2Width or b.width or 720
        local colW, gap = Grid(w, 4)
        local controls = {}
        local master = BindSwitch(ctx, section, "Enable filters", 24, -40, colW,
            function() return item.filters.enabled ~= false end,
            function(value) item.filters.enabled = value == true; Apply("AURAS3_CUSTOM_FILTER_ENABLE") end,
            AuraControlMeta(ctx, "custom-container.filters.enabled"))
        local hidePermanent = BindSwitch(ctx, section, "Hide permanent", 24 + colW + gap, -40, colW,
            function() return item.filters.hidePermanent == true end,
            function(value) item.filters.hidePermanent = value == true; Apply("AURAS3_CUSTOM_HIDE_PERMANENT", true) end,
            AuraControlMeta(ctx, "custom-container.filters.hide-permanent"))
        AddTooltip(hidePermanent, "Hide permanent auras", "Always excludes auras without a duration. It remains active when token filters are disabled.")
        for i = 1, #specs do
            local spec = specs[i]
            local col = (i - 1) % 4
            local row = floor((i - 1) / 4)
            local control = BindSwitch(ctx, section, spec[1], 24 + col * (colW + gap), -76 - row * 32, colW,
                function()
                    if spec[2] == "raid" and item.filters.exclusive == "raid" then return true end
                    return item.filters[spec[2]] == true
                end,
                function(value)
                    if spec[2] == "raid" then item.filters.exclusive = nil end
                    item.filters[spec[2]] = value == true
                    if value == true and spec[3] then for j = 1, #spec[3] do item.filters[spec[3][j]] = false end end
                    Apply("AURAS3_CUSTOM_FILTER")
                    if spec[3] then QueueAurasPageRefresh(ctx, "custom-filter-conflict") end
                end,
                AuraControlMeta(ctx, "custom-container.filters." .. AuraCatalogToken(spec[2])))
            controls[#controls + 1] = control
        end
        local maxDuration = ConfigureMaxDurationSlider(BindSlider(ctx, section, "Maximum duration", 24,
            -76 - optionRows * 32, 0, 180, 1, w - 48,
            function() return min(180, max(0, tonumber(item.filters.maxDuration) or 0)) end,
            WriteMaxDuration,
            AuraControlMeta(ctx, "custom-container.filters.max-duration", nil, {
                assistantDisposition = "compound",
                assistantDispositionReason = "The native candidate-filter duration limit has no Assistant setting contract yet.",
            })))
        M.TrackRefresh(ctx, function()
            W.SetControlEnabled(master, true)
            W.SetControlEnabled(hidePermanent, true)
            W.SetControlEnabled(maxDuration, true)
            W.SetControlsEnabled(controls, item.filters.enabled ~= false)
        end)
        return true
    end
end

local function BuildCustomLayoutTool(C)
    local ctx, b, unit, tool, containerLabel, item, Apply, Grid = C.ctx, C.b, C.unit, C.tool, C.containerLabel, C.item, C.Apply, C.Grid
    if tool == "layout" then
        local layoutTitle = M.Format("%s Layout", Tr(containerLabel))
        local section = b:Section(layoutTitle, 190)
        M.AttachAuraFontsAndColors(section, layoutTitle, unit)
        local w = section._msuf2Width or b.width or 720
        local col3, gap3 = Grid(w, 3)
        BindDropdown(ctx, section, "Anchor", 24, -34, Model.AuraAnchorValues(), col3,
            function() return item.placed.anchor or "TOPRIGHT" end,
            function(value) item.placed.anchor = value or "TOPRIGHT"; Apply("AURAS3_CUSTOM_ANCHOR") end,
            AuraControlMeta(ctx, "custom-container.layout.anchor"))
        BindDropdown(ctx, section, "Growth", 24 + col3 + gap3, -34, Model.LaneGrowthValues(), col3,
            function() return item.placed.growth or "LEFTDOWN" end,
            function(value) item.placed.growth = value or "LEFTDOWN"; Apply("AURAS3_CUSTOM_GROWTH", true) end,
            AuraControlMeta(ctx, "custom-container.layout.growth"))
        local col4, gap4 = Grid(w, 4)
        local values = {
            { "Max", "max", 0, 40, 8 }, { "Size", "size", 8, 128, 24 },
            { "Per row", "perRow", 1, 20, 4 }, { "Gap", "spacing", 0, 24, 2 }, { "Layer (0-30)", "layer", 0, 30, 9 },
        }
        local perRowControl
        for i = 1, #values do
            local spec = values[i]
            local row = i <= 4 and 0 or 1
            local col = row == 0 and (i - 1) or (i - 5)
            local assistantContract
            if spec[2] == "layer" then
                local layerSettingKeys = {}
                for customIndex = 1, 4 do
                    layerSettingKeys[#layerSettingKeys + 1] =
                        "auras3." .. tostring(unit) .. ".custom" .. tostring(customIndex) .. ".layer"
                end
                assistantContract = {
                    assistantDisposition = "dynamic",
                    assistantDispositionReason = "Layer targets the selected unit Custom Aura container.",
                    assistantSettingKeys = layerSettingKeys,
                }
            end
            local control = BindSlider(ctx, section, spec[1], 24 + col * (col4 + gap4), row == 0 and -92 or -146, spec[3], spec[4], 1, col4,
                function() return tonumber(spec[2] == "layer" and item.layer or item.placed[spec[2]]) or spec[5] end,
                function(value)
                    if spec[2] == "layer" then item.layer = floor(tonumber(value) or spec[5]) else item.placed[spec[2]] = tonumber(value) or spec[5] end
                    Apply("AURAS3_CUSTOM_" .. spec[2]:upper())
                end,
                AuraControlMeta(ctx, "custom-container.layout." .. AuraCatalogToken(spec[2]), nil, assistantContract))
            if spec[2] == "perRow" then perRowControl = control end
        end
        M.TrackRefresh(ctx, function()
            local growth = tostring(item.placed.growth or "LEFTDOWN"):upper()
            W.SetControlEnabled(perRowControl, growth ~= "UP" and growth ~= "DOWN")
        end)
        W.Text(section, "Position is controlled by the colored aura handle in Preview.", 24 + col4 + gap4, -154, col4 * 3 + gap4 * 2, T.colors.muted)
        return true
    end
end

local function BuildCustomAppearancePandemic(C, StyleGrid)
    local ctx, b, index, isTargetDots, Apply = C.ctx, C.b, C.index, C.isTargetDots, C.Apply
    local item = C.styleItem
    local pandemic
    if isTargetDots then
        pandemic = b:CollapsibleSection(CustomStyleSectionId(index, "pandemic"), "Pandemic Warning & Style", 248, false)
        local pandemicCol, pandemicX, PandemicNumber = StyleGrid(pandemic)
        local pandemicControls = {}
        local pandemicWarning = W.Text(pandemic,
            "PERFORMANCE WARNING (12.1): Blizzard can run an OnUpdate every frame on each visible aura button for the full aura while it has a calculated pandemic window, not only while the warning is shown. Enable only if you accept this potentially high combat cost.",
            24, -96, (pandemic._msuf2Width or b.width or 720) - 48, { 1.00, 0.38, 0.18, 1 })
        if pandemicWarning.SetWordWrap then pandemicWarning:SetWordWrap(true) end
        local RefreshPandemicState
        local pandemicToggle = BindSwitch(ctx, pandemic, "Show Pandemic State", pandemicX(1), -42,
            pandemicCol, function() return item.placed.pandemicEnabled == true end,
            function(value)
                item.placed.pandemicEnabled = value == true
                Apply("AURAS3_TARGET_DOT_PANDEMIC", true)
                if RefreshPandemicState then RefreshPandemicState() end
            end,
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.enabled"))
        AddTooltip(pandemicToggle, "12.1 Pandemic state",
            "Disabled by default. Blizzard's native implementation enables a per-frame OnUpdate for each visible aura button as soon as that aura has a calculated pandemic window; this can begin before the warning becomes visible.")
        pandemicControls[#pandemicControls + 1] = BindDropdown(ctx, pandemic, "Style", pandemicX(2), -42,
            M.AURA_PANDEMIC_STYLE_VALUES, pandemicCol,
            function() return item.placed.pandemicStyle or "BORDER" end,
            function(value) item.placed.pandemicStyle = value or "BORDER"; Apply("AURAS3_TARGET_DOT_PANDEMIC_STYLE", true) end,
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.style"))
        pandemicControls[#pandemicControls + 1] = BindDropdown(ctx, pandemic, "Blend", pandemicX(3), -42,
            M.AURA_PANDEMIC_BLEND_VALUES, pandemicCol,
            function() return item.placed.pandemicBlend or "ADD" end,
            function(value) item.placed.pandemicBlend = value == "BLEND" and "BLEND" or "ADD"; Apply("AURAS3_TARGET_DOT_PANDEMIC_BLEND", true) end,
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.blend"))
        -- The ::: shortcut is the section's only visible way into the color picker,
        -- so this swatch is never laid out. It still exists and stays bound: it is
        -- the control the Assistant and menu search resolve for this setting, and
        -- unlike the status text colors there is no Colors page surface carrying a
        -- per-custom-container pandemic color to fall back to.
        -- Attached before M.BindColor so the explicit shortcut owns the section:
        -- a shortcut generated by BindColor would be replaced by later color
        -- controls, and it could not serve as a stable search anchor.
        -- Deliberately kept out of pandemicControls: a disabled owner drops out of
        -- the shortcut's relevance check, which would make the ::: come and go with
        -- the toggle instead of staying put.
        local pandemicColor = W.Color(pandemic, "Color")
        pandemicColor._msuf2ContextColorAllowDisabled = true
        W.SetControlShown(pandemicColor, false)
        local pandemicColorShortcut
        if W.AttachContextColorShortcut then
            pandemicColorShortcut = W.AttachContextColorShortcut(pandemic, {
                historyLabel = "Pandemic color",
                historySource = "menu:custom-auras-pandemic-color",
                getTargets = function() return { pandemicColor } end,
            })
        end
        local pandemicColorMeta = AuraControlMeta(ctx, "custom-container.appearance.pandemic.color")
        -- Search must land on the shortcut; highlighting the hidden swatch would
        -- point the player at nothing.
        pandemicColorMeta.anchor = pandemicColorShortcut or nil
        M.BindColor(ctx, pandemicColor,
            function()
                local color = item.placed.pandemicColor or { 1, 0.24, 0.08 }
                return color[1] or 1, color[2] or 0.24, color[3] or 0.08
            end,
            function(r, g, blue)
                item.placed.pandemicColor = { r, g, blue }
                Apply("AURAS3_TARGET_DOT_PANDEMIC_COLOR", true)
            end,
            pandemicColorMeta)
        pandemicControls[#pandemicControls + 1] = PandemicNumber("Thickness", 1, -174, 1, 12,
            "pandemicThickness", 2)
        pandemicControls[#pandemicControls + 1] = PandemicNumber("Padding", 2, -174, -8, 16,
            "pandemicPadding", 1)
        pandemicControls[#pandemicControls + 1] = BindSlider(ctx, pandemic, "Border Opacity", pandemicX(3), -174,
            5, 100, 5, pandemicCol,
            function() return floor(((tonumber(item.placed.pandemicBorderAlpha) or 1) * 100) + 0.5) end,
            function(value) item.placed.pandemicBorderAlpha = (tonumber(value) or 100) / 100; Apply("AURAS3_TARGET_DOT_PANDEMIC_BORDER_ALPHA", true) end,
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.border-opacity"))
        pandemicControls[#pandemicControls + 1] = BindSlider(ctx, pandemic, "Tint Opacity", pandemicX(4), -174,
            5, 100, 5, pandemicCol,
            function() return floor(((tonumber(item.placed.pandemicTintAlpha) or 0.22) * 100) + 0.5) end,
            function(value) item.placed.pandemicTintAlpha = (tonumber(value) or 22) / 100; Apply("AURAS3_TARGET_DOT_PANDEMIC_TINT_ALPHA", true) end,
            AuraControlMeta(ctx, "custom-container.appearance.pandemic.tint-opacity"))
        RefreshPandemicState = function()
            local enabled = item.placed.pandemicEnabled == true
            W.SetControlsEnabled(pandemicControls, enabled)
            pandemicWarning:SetShown(enabled)
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(pandemic, { {
                    text = enabled and M.Format("On / %s", ChoiceLabel(M.AURA_PANDEMIC_STYLE_VALUES,
                        item.placed.pandemicStyle or "BORDER", "Border")) or Tr("Off"),
                    kind = enabled and "accent" or "muted", showWhenClosed = true,
                } })
            end
        end
        M.TrackRefresh(ctx, RefreshPandemicState)
        RefreshPandemicState()
    end
end

local function BuildCustomAppearanceTool(C)
    local ctx, b, unit, index, tool, isTargetDots, containerLabel, styleItem, Apply, Grid = C.ctx, C.b, C.unit, C.index, C.tool, C.isTargetDots, C.containerLabel, C.styleItem, C.Apply, C.Grid
    if tool == "appearance" then
        -- Every Custom container, including Player Defensives and Dots on
        -- Target, binds visual controls to this UnitFrame-owned record.
        local item = styleItem
        -- One accordion sub-section per topic, mirroring the Buff/Debuff lane
        -- style sections. Assistant semantic paths keep the historical
        -- "appearance" segment so the generated control schema stays stable.
        local function StyleGrid(section)
            local w = section._msuf2Width or b.width or 720
            local col4, gap = Grid(w, 4)
            local function X(col) return 24 + (col - 1) * (col4 + gap) end
            local function Number(label, col, y, minValue, maxValue, key, fallback, afterSet)
                return BindSlider(ctx, section, label, X(col), y, minValue, maxValue, 1, col4,
                    function() return tonumber(item.placed[key]) or fallback end,
                    function(value)
                        item.placed[key] = tonumber(value) or fallback
                        Apply("AURAS3_CUSTOM_APPEARANCE_" .. key:upper())
                        if type(afterSet) == "function" then afterSet() end
                    end,
                    AuraControlMeta(ctx, "custom-container.appearance." .. AuraCatalogToken(key)))
            end
            return col4, X, Number
        end
        local function GateControls(readEnabled, controls)
            M.TrackRefresh(ctx, function() W.SetControlsEnabled(controls, readEnabled()) end)
        end

        local harmfulContainer = isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF"
        local frameBasics = b:CollapsibleSection(CustomStyleSectionId(index, "frame_basics"), "Frame Basics", 220, true)
        local frameBasicsWidth = frameBasics._msuf2Width or b.width or 720
        local frameBasicsGap = 10
        local frameBasicsCol = max(180, floor((frameBasicsWidth - 48 - frameBasicsGap) / 2))
        local frameBasicsRightX = 24 + frameBasicsCol + frameBasicsGap
        BindSlider(ctx, frameBasics, "Icon Zoom (%)", 24, -48, 100, 200, 1, frameBasicsCol,
            function() return tonumber(item.placed.iconZoom) or 100 end,
            function(value)
                item.placed.iconZoom = tonumber(value) or 100
                Apply("AURAS3_CUSTOM_APPEARANCE_ICONZOOM")
            end,
            AuraControlMeta(ctx, "custom-container.appearance.icon-zoom"))
        AddAuraTooltipHelp(BindSwitch(ctx, frameBasics, "Tooltip", frameBasicsRightX, -48, frameBasicsCol,
            function() return item.placed.showTooltip ~= false end,
            function(value) item.placed.showTooltip = value == true; Apply("AURAS3_CUSTOM_TOOLTIP") end,
            AuraControlMeta(ctx, "custom-container.appearance.tooltip")))
        BindSlider(ctx, frameBasics, "Opacity", 24, -106, 10, 100, 5, frameBasicsCol,
            function() return floor(((tonumber(item.placed.alpha) or 1) * 100) + 0.5) end,
            function(value) item.placed.alpha = (tonumber(value) or 100) / 100; Apply("AURAS3_CUSTOM_ALPHA") end,
            AuraControlMeta(ctx, "custom-container.appearance.opacity"))
        BindSlider(ctx, frameBasics, "Lane Padding", 24, -164, 0, 16, 1, frameBasicsCol,
            function() return tonumber(item.placed.stylePadding) or 0 end,
            function(value) item.placed.stylePadding = tonumber(value) or 0; Apply("AURAS3_CUSTOM_STYLE_PADDING") end,
            AuraControlMeta(ctx, "custom-container.appearance.style-padding"))
        if harmfulContainer then
            BindDropdown(ctx, frameBasics, "Dispel-type Border", frameBasicsRightX, -106,
                DEBUFF_TYPE_BORDER_MODE_VALUES, frameBasicsCol,
                function() return item.placed.debuffTypeBorderMode or "OFF" end,
                function(value) item.placed.debuffTypeBorderMode = value or "OFF"; Apply("AURAS3_CUSTOM_DEBUFF_TYPE_BORDER") end,
                AuraControlMeta(ctx, "custom-container.appearance.dispel-type-border"))
        end

        BuildCustomAppearancePandemic(C, StyleGrid)

        local stack = b:CollapsibleSection(CustomStyleSectionId(index, "stack"), "Stack Count", 130, false)
        local stackCol, stackX, StackNumber = StyleGrid(stack)
        BindSwitch(ctx, stack, "Stack count", stackX(1), -42, stackCol, function() return item.placed.showStacks ~= false end,
            function(value) item.placed.showStacks = value == true; Apply("AURAS3_CUSTOM_STACKS") end,
            AuraControlMeta(ctx, "custom-container.appearance.stack-count"))
        GateControls(function() return item.placed.showStacks ~= false end, {
            StackNumber("Stack size", 1, -76, 6, 40, "stackSize", 14),
            BindDropdown(ctx, stack, "Stack anchor", stackX(2), -76, Model.AuraAnchorValues(), stackCol,
                function() return item.placed.stackAnchor or "BOTTOMRIGHT" end,
                function(value) item.placed.stackAnchor = value or "BOTTOMRIGHT"; Apply("AURAS3_CUSTOM_STACK_ANCHOR") end,
                AuraControlMeta(ctx, "custom-container.appearance.stack-anchor")),
            StackNumber("Stack X", 3, -76, -40, 40, "stackX", 0),
            StackNumber("Stack Y", 4, -76, -40, 40, "stackY", 0),
        })

        local cooldown = b:CollapsibleSection(CustomStyleSectionId(index, "cooldown"), "Cooldown Text", 184, true)
        if W.AttachContextColorShortcut then
            W.AttachContextColorShortcut(cooldown, {
                title = containerLabel .. " Cooldown Text Settings",
                historyLabel = "Custom aura cooldown text color",
                historySource = "menu:custom-auras-cooldown-text-color",
                scopeTag = "Shared",
                note = AURA_SHARED_COLOR_NOTE,
                textSettings = {
                    scope = "shared",
                    unit = unit,
                    kind = "aura",
                    colorReferences = AURA_COOLDOWN_COLOR_REFERENCES,
                    colorTitle = containerLabel .. " Cooldown Colors",
                    subtitle = "Custom aura text follows the shared Fonts settings.",
                    capabilities = {
                        opacity = false, baseline = false,
                        shadowAlpha = false, shadowDistance = false,
                    },
                },
            })
        end
        local cdCol, cdX, CdNumber = StyleGrid(cooldown)
        BindSwitch(ctx, cooldown, "Cooldown text", cdX(1), -42, cdCol, function() return item.placed.showCooldown ~= false end,
            function(value) item.placed.showCooldown = value == true; Apply("AURAS3_CUSTOM_COOLDOWN") end,
            AuraControlMeta(ctx, "custom-container.appearance.cooldown-text"))
        BindSwitch(ctx, cooldown, "Cooldown swipe", cdX(2), -42, cdCol, function() return item.placed.showCooldownSwipe ~= false end,
            function(value) item.placed.showCooldownSwipe = value == true; Apply("AURAS3_CUSTOM_SWIPE") end,
            AuraControlMeta(ctx, "custom-container.appearance.cooldown-swipe"))
        local customDecimal = CdNumber("Decimals below sec", 4, -76, 0, 30, "cooldownDecimalSeconds", 3)
        AddTooltip(customDecimal, "Cooldown text format",
            "Remaining time below this value uses one decimal place. Timers show unitless seconds below 1 minute and localized minutes above it. Set 0 for whole seconds only.")
        GateControls(function() return item.placed.showCooldown ~= false end, {
            CdNumber("Cooldown size", 1, -76, 6, 40, "cooldownSize", 14),
            BindDropdown(ctx, cooldown, "Cooldown anchor", cdX(3), -76, Model.AuraAnchorValues(), cdCol,
                function() return item.placed.cooldownAnchor or "CENTER" end,
                function(value) item.placed.cooldownAnchor = value or "CENTER"; Apply("AURAS3_CUSTOM_COOLDOWN_ANCHOR") end,
                AuraControlMeta(ctx, "custom-container.appearance.cooldown-anchor")),
            customDecimal,
            CdNumber("Cooldown X", 1, -130, -40, 40, "cooldownX", 0),
            CdNumber("Cooldown Y", 2, -130, -40, 40, "cooldownY", 0),
        })
        GateControls(function() return item.placed.showCooldownSwipe ~= false end, {
            BindDropdown(ctx, cooldown, "Swipe", cdX(2), -76, COOLDOWN_SWIPE_DIRECTION_VALUES, cdCol,
                function() return item.placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL" end,
                function(value) item.placed.cooldownSwipeReverse = value == "REVERSE"; Apply("AURAS3_CUSTOM_SWIPE_DIRECTION") end,
                AuraControlMeta(ctx, "custom-container.appearance.swipe-direction")),
        })

        local durationBar = b:CollapsibleSection(CustomStyleSectionId(index, "duration_bar"), "Duration Bar", 156, false)
        local barCol, barX, BarNumber = StyleGrid(durationBar)
        local durationBarControls, durationBarSwitch
        local durationBarNote = W.Text(durationBar, "", 24, -116, (durationBar._msuf2Width or b.width or 720) - 48, T.colors.muted)
        local function RefreshCustomDurationBarState()
            local placed = item.placed
            -- Fixed aura slots and Oil placeholders can show cooldown text/swipe,
            -- but neither owns the AuraButton duration-bar surface this group drives.
            local reminder = placed.reminderEnabled == true
            local enabled = placed.showDurationBar == true and not reminder
            if durationBarSwitch then W.SetControlEnabled(durationBarSwitch, not reminder) end
            if durationBarControls then W.SetControlsEnabled(durationBarControls, enabled) end
            durationBarNote:SetText(reminder
                and Tr("Reminder slots do not draw a duration bar.") or "")
            if W.SetCollapsibleBadges then
                W.SetCollapsibleBadges(durationBar, {{
                    text = reminder and Tr("Unavailable")
                        or (enabled and (tostring(Round(tonumber(placed.durationBarHeight) or 2)) .. "px / " .. ChoiceLabel(DURATION_BAR_DISPLAY_VALUES, placed.durationBarDisplay or "BAR_ONLY", "Bar Only") .. " / " .. ChoiceLabel(DURATION_BAR_POSITION_VALUES, placed.durationBarPosition or "BOTTOM", "Bottom")) or "Off"),
                    kind = enabled and "accent" or "muted", showWhenClosed = true,
                }})
            end
        end
        M.TrackRefresh(ctx, RefreshCustomDurationBarState)
        durationBarSwitch = BindSwitch(ctx, durationBar, "Duration bar", barX(1), -42, barCol, function() return item.placed.showDurationBar == true end,
            function(value)
                item.placed.showDurationBar = value == true
                Apply("AURAS3_CUSTOM_DURATION_BAR")
                RefreshCustomDurationBarState()
            end,
            AuraControlMeta(ctx, "custom-container.appearance.duration-bar"))
        durationBarControls = {
            BarNumber("Bar height", 1, -76, 1, 16, "durationBarHeight", 2, RefreshCustomDurationBarState),
            BindDropdown(ctx, durationBar, "Bar display", barX(2), -76, DURATION_BAR_DISPLAY_VALUES, barCol,
                function() return item.placed.durationBarDisplay or "BAR_ONLY" end,
                function(value)
                    item.placed.durationBarDisplay = value or "BAR_ONLY"
                    Apply("AURAS3_CUSTOM_DURATION_DISPLAY")
                    RefreshCustomDurationBarState()
                end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-display")),
            BindDropdown(ctx, durationBar, "Bar position", barX(3), -76, DURATION_BAR_POSITION_VALUES, barCol,
                function() return item.placed.durationBarPosition or "BOTTOM" end,
                function(value)
                    item.placed.durationBarPosition = value or "BOTTOM"
                    Apply("AURAS3_CUSTOM_DURATION_POSITION")
                    RefreshCustomDurationBarState()
                end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-position")),
            BindDropdown(ctx, durationBar, "Bar fill", barX(4), -76, DURATION_BAR_DIRECTION_VALUES, barCol,
                function() return item.placed.durationBarDirection or "REMAINING" end,
                function(value)
                    item.placed.durationBarDirection = value or "REMAINING"
                    Apply("AURAS3_CUSTOM_DURATION_DIRECTION")
                    RefreshCustomDurationBarState()
                end,
                AuraControlMeta(ctx, "custom-container.appearance.duration-direction")),
        }

        if W.SetCollapsibleBadges then
            local ToggleBadge = W.ToggleBadge
            M.TrackRefresh(ctx, function()
                local placed = item.placed
                local zoom = Round(tonumber(placed.iconZoom) or 100)
                local opacity = floor(((tonumber(placed.alpha) or 1) * 100) + 0.5)
                local frameBasicsBadges = {
                    { text = M.Format("Zoom %d%%", zoom), kind = "info", showWhenClosed = true },
                    ToggleBadge("Tooltip", placed.showTooltip ~= false),
                }
                if opacity < 100 then
                    frameBasicsBadges[#frameBasicsBadges + 1] = { text = M.Format("Opacity %d%%", opacity), kind = "info", showWhenClosed = true }
                end
                if harmfulContainer then
                    local borderMode = tostring(placed.debuffTypeBorderMode or "OFF"):upper()
                    frameBasicsBadges[#frameBasicsBadges + 1] = {
                        text = "Border " .. ChoiceLabel(DEBUFF_TYPE_BORDER_MODE_VALUES, borderMode, borderMode),
                        kind = borderMode == "OFF" and "muted" or "accent", showWhenClosed = true,
                    }
                end
                W.SetCollapsibleBadges(frameBasics, frameBasicsBadges)

                local stackEnabled = placed.showStacks ~= false
                W.SetCollapsibleBadges(stack, {{
                    text = stackEnabled and (tostring(Round(tonumber(placed.stackSize) or 14)) .. "px / " .. AnchorLabel(placed.stackAnchor or "BOTTOMRIGHT")) or "Off",
                    kind = stackEnabled and "accent" or "muted", showWhenClosed = true,
                }})

                local cooldownEnabled = placed.showCooldown ~= false
                local decimal = Round(tonumber(placed.cooldownDecimalSeconds) or 3)
                W.SetCollapsibleBadges(cooldown, {
                    { text = cooldownEnabled and (tostring(Round(tonumber(placed.cooldownSize) or 14)) .. "px / " .. AnchorLabel(placed.cooldownAnchor or "CENTER") .. " / " .. ChoiceLabel(COOLDOWN_SWIPE_DIRECTION_VALUES, placed.cooldownSwipeReverse == true and "REVERSE" or "NORMAL", "Normal")) or "Off", kind = cooldownEnabled and "accent" or "muted", showWhenClosed = true },
                    { text = decimal > 0 and M.Format("Decimals below %ds", decimal) or Tr("Whole seconds"), kind = "info", showWhenClosed = true },
                })

                RefreshCustomDurationBarState()
            end)
        end
        return true
    end
end

local function BuildCustomEffectTool(C)
    local ctx, b, index, tool, isTargetDots, styleItem, Apply, Grid = C.ctx, C.b, C.index, C.tool, C.isTargetDots, C.styleItem, C.Apply, C.Grid
    if tool == "effect" then
        local item = styleItem
        local section = b:CollapsibleSection(CustomStyleSectionId(index, "full_frame"), "Full-Frame Effect", 210, false)
        local w = section._msuf2Width or b.width or 720
        local col3, gap = Grid(w, 3)
        BindDropdown(ctx, section, "Effect", 24, -34, CUSTOM_FRAME_EFFECTS, w - 48,
            function() return item.frame.type or "none" end,
            function(value) item.frame.type = value or "none"; Apply("AURAS3_CUSTOM_EFFECT") end,
            AuraControlMeta(ctx, "custom-container.effect.type"))
        local color = W.Color(section, "Color")
        M.BindColor(ctx, color,
            function() local c = item.frame.color; return c[1] or 0.69, c[2] or 0.50, c[3] or 0.88 end,
            function(r, g, blue) local a = item.frame.color[4] or 0.8; item.frame.color = { r, g, blue, a }; Apply("AURAS3_CUSTOM_EFFECT_COLOR") end,
            AuraControlMeta(ctx, "custom-container.effect.color"))
        color:Hide()
        if color._msuf2Title then
            color._msuf2Title:Hide()
            color._msuf2Title._msuf2AlwaysHidden = true
        end
        BindSlider(ctx, section, "Opacity", 24, -96, 5, 100, 5, col3,
            function() return floor(((item.frame.color[4] or 0.8) * 100) + 0.5) end,
            function(value) item.frame.color[4] = (tonumber(value) or 80) / 100; item.frame.tintAlpha = item.frame.color[4]; Apply("AURAS3_CUSTOM_EFFECT_ALPHA") end,
            AuraControlMeta(ctx, "custom-container.effect.opacity"))
        BindSlider(ctx, section, "Layer (0-30)", 24 + col3 + gap, -96, 0, 30, 1, col3,
            function() return tonumber(item.frame.layer) or 0 end,
            function(value) item.frame.layer = floor(tonumber(value) or 0); Apply("AURAS3_CUSTOM_EFFECT_LAYER") end,
            AuraControlMeta(ctx, "custom-container.effect.layer"))
        BindSlider(ctx, section, "Thickness", 24 + 2 * (col3 + gap), -96, 1, 16, 1, col3,
            function() return tonumber(item.frame.thickness) or 2 end,
            function(value) item.frame.thickness = tonumber(value) or 2; Apply("AURAS3_CUSTOM_EFFECT_THICKNESS") end,
            AuraControlMeta(ctx, "custom-container.effect.thickness"))
        BindSlider(ctx, section, "Priority", 24, -150, 1, 10, 1, col3,
            function() return tonumber(item.frame.priority) or 5 end,
            function(value) item.frame.priority = tonumber(value) or 5; Apply("AURAS3_CUSTOM_EFFECT_PRIORITY") end,
            AuraControlMeta(ctx, "custom-container.effect.priority"))
        if isTargetDots then
            local pandemicOnly = BindSwitch(ctx, section, "Only during Pandemic window", 24 + col3 + gap, -150,
                col3 * 2 + gap, function() return item.frame.onlyInPandemicWindow == true end,
                function(value)
                    item.frame.onlyInPandemicWindow = value == true
                    Apply("AURAS3_TARGET_DOT_EFFECT_PANDEMIC_ONLY", true)
                end,
                AuraControlMeta(ctx, "custom-container.effect.only-during-pandemic-window"))
            AddTooltip(pandemicOnly, "Pandemic-only Full-Frame effect",
                "Shows this effect only while a tracked DoT is in its native Pandemic window. Multiple DoTs in Pandemic can intensify the same effect. Blizzard may run an OnUpdate on each visible aura button while its Pandemic timing is available.")
        end
        if W.SetCollapsibleBadges then
            M.TrackRefresh(ctx, function()
                local effectType = tostring(item.frame.type or "none")
                local badges = {{
                    text = ChoiceLabel(CUSTOM_FRAME_EFFECTS, effectType, effectType),
                    kind = effectType == "none" and "muted" or "accent", showWhenClosed = true,
                }}
                if isTargetDots and item.frame.onlyInPandemicWindow == true then
                    badges[#badges + 1] = { text = "Pandemic only", kind = "info", showWhenClosed = true }
                end
                W.SetCollapsibleBadges(section, badges)
            end)
        end
        return true
    end
end

local function BuildCustomBehaviorTool(C)
    local ctx, b, unit, index, tool, customActionPath, isPlayerDefensives, isTargetDots, item, Apply = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.isPlayerDefensives, C.isTargetDots, C.item, C.Apply
    if tool == "behavior" then
        local sortLane = (isTargetDots or tostring(item.auraType or "BUFF"):upper() == "DEBUFF") and "debuff" or "buff"
        local supportsCustomPriority = not isPlayerDefensives
        local section = b:Section("Ordering", 190)
        local w = section._msuf2Width or b.width or 720
        -- Keep every custom container's identity separate. Exact-ID custom
        -- containers can each persist their own CUSTOM_PRIORITY or ordinary
        -- sort mode without sharing a lane preset.
        local orderingPath = customActionPath .. ".ordering"
        local visibleOrderingPath = isTargetDots and "custom-container.dots-on-target.ordering"
            or (isPlayerDefensives and "custom-container.defensive-buffs.ordering" or orderingPath)
        local sortMethod = BindDropdown(ctx, section, "Sort By", 24, -48, AuraSortMethodValues(sortLane, supportsCustomPriority), w - 48,
            function() return NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod, supportsCustomPriority) end,
            function(value)
                if supportsCustomPriority and value == "CUSTOM_PRIORITY"
                    and type(Model.EnableCustomContainerSpellPriority) == "function" then
                    Model.EnableCustomContainerSpellPriority(unit, index)
                else
                    item.placed.sortMethod = value or "DEFAULT"
                end
                Apply("AURAS3_CUSTOM_SORT_METHOD", supportsCustomPriority)
            end,
            AuraControlMetaAtVisiblePath(ctx,
                orderingPath .. "." .. sortLane .. "-sort-method",
                visibleOrderingPath .. "." .. sortLane .. "-sort-method"))
        AddTooltip(sortMethod, "Aura sorting", supportsCustomPriority
            and "Custom Priority packs active tracked auras into the configured order. Inactive entries leave no gap; drag the spell rows in Setup to change their priority."
            or "Only relevant sorting methods are shown for buffs and debuffs.")
        local sortDirection = BindDropdown(ctx, section, "Order", 24, -104, AURA_SORT_DIRECTION_VALUES, w - 48,
            function() return item.placed.sortReverse == true and "REVERSE" or "NORMAL" end,
            function(value) item.placed.sortReverse = value == "REVERSE"; Apply("AURAS3_CUSTOM_SORT_DIRECTION") end,
            AuraControlMetaAtVisiblePath(ctx,
                orderingPath .. ".sort-direction",
                visibleOrderingPath .. ".sort-direction"))
        AddTooltip(sortDirection, "Aura sort order", "Reversed flips the complete priority order.")
        -- Fixed reminder slots take their order from the Whitelist, so nothing
        -- on this tab can influence them. Leaving the controls live would let
        -- the page promise something the runtime ignores.
        local orderingNote = W.Text(section, "", 24, -156, w - 48, T.colors.muted)
        M.TrackRefresh(ctx, function()
            local reminder = item.placed.reminderEnabled == true
            if type(W.SetControlsEnabled) == "function" then
                W.SetControlsEnabled({ sortMethod }, not reminder)
                W.SetControlsEnabled({ sortDirection }, not reminder
                    and (not supportsCustomPriority
                        or NormalizeAuraSortMethodForLane(sortLane, item.placed.sortMethod, supportsCustomPriority) ~= "CUSTOM_PRIORITY"))
            end
            orderingNote:SetText(reminder
                and Tr("Sorting is off while this container shows fixed reminder slots \194\183 their order comes from the Whitelist.")
                or "")
        end)
        return true
    end
end

local function BuildCustomDefensivesSetup(C)
    local ctx, b, unit, index, customActionPath, isPlayerDefensives, item, Apply = C.ctx, C.b, C.unit, C.index, C.customActionPath, C.isPlayerDefensives, C.item, C.Apply
    if isPlayerDefensives then
        local section = b:Section("Defensive Buffs Setup", 390)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local enabled = BindSwitch(ctx, section, "Enabled", 24, -48, 112,
            function() return item.enabled == true end,
            function(value)
                item.enabled = value == true
                Apply("AURAS3_PLAYER_DEFENSIVES_ENABLE", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.enabled"))
        AddTooltip(enabled, "Enable defensive buffs",
            "Core feature enabled by default for new profiles and once for existing profiles. It works as a normal defensive buff bar without an enabled portrait. Turn this off to disable both bar and portrait-position display.")
        local portrait = BindSwitch(ctx, section, "Show buffs at portrait position", 24, -86, 280,
            function() return item.portraitIcon == true end,
            function(value)
                item.portraitIcon = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-icon"))
        AddTooltip(portrait, "Show buffs at portrait position",
            "Optional presentation mode; the Defensive Buffs feature itself does not require a portrait. With an enabled portrait, the first icon occupies it. When the portrait is off, enable the position option below to keep the icons there; otherwise MSUF safely falls back to the normal defensive bar.")
        local portraitMax = BindSlider(ctx, section, "Max portrait icons", 24, -128, 1, 8, 1, inner,
            function() return tonumber(item.portraitMaxIcons) or 1 end,
            function(value)
                item.portraitMaxIcons = max(1, min(8, floor((tonumber(value) or 1) + 0.5)))
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT_MAX", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-max-icons"))
        AddTooltip(portraitMax, "Max portrait icons",
            "Limits the number of simultaneous defensive icons at the portrait from 1 to 8. Existing profiles remain at 1 until this value is changed.")
        local cooldownText = BindSwitch(ctx, section, "Show cooldown text on portrait", 24, -198, 280,
            function() return item.portraitCooldownText ~= false end,
            function(value)
                item.portraitCooldownText = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT_COOLDOWN", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-cooldown-text"))
        AddTooltip(cooldownText, "Show cooldown text on portrait",
            "Shows the active defensive buff's remaining duration over its portrait icon. Blizzard updates the text natively.")
        local positionOnly = BindSwitch(ctx, section, "Use portrait position while portrait is off", 24, -236, 326,
            function() return item.portraitPositionWhenDisabled == true end,
            function(value)
                item.portraitPositionWhenDisabled = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_PORTRAIT_POSITION", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.portrait-position-when-disabled"))
        AddTooltip(positionOnly, "Use portrait position while portrait is off",
            "Keeps the configured portrait size and position as an invisible anchor so the defensive icon can remain there while the portrait itself is disabled.")
        local autoBlacklist = BindSwitch(ctx, section, "Auto-blacklist from player buffs", 24, -274, 280,
            function() return item.autoBlacklistPlayerBuffs ~= false end,
            function(value)
                item.autoBlacklistPlayerBuffs = value == true
                Apply("AURAS3_PLAYER_DEFENSIVE_AUTO_BLACKLIST", true)
            end,
            AuraControlMeta(ctx, "custom-container.player-defensives.auto-blacklist"))
        AddTooltip(autoBlacklist, "Auto-blacklist from player buffs",
            "While the defensive bar or portrait icon is enabled, hides every enabled tracked defensive from the normal player Buffs lane. Disabled defensive entries remain visible there.")
        local reset = ActionButton(section, "Reset", 88)
        reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -42)
        reset:SetScript("OnClick", function()
            Model.ResetCustomContainer(unit, index)
            Apply("AURAS3_PLAYER_DEFENSIVES_RESET", true)
            Rebuild(ctx)
        end)
        RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
            actionKey = "reset_aura_custom_container", actionFixedArgs = { scope = unit, index = index },
        })
        local predefined = type(Model.PlayerDefensivePreviewEntries) == "function"
            and #Model.PlayerDefensivePreviewEntries() or 0
        local predefinedTotal = type(Model.PlayerDefensiveClassEntries) == "function"
            and #Model.PlayerDefensiveClassEntries(true) or predefined
        local custom = #Model.CustomContainerSpellEntries(unit, index)
        -- The 12.1 native aura buttons render their icon unmaskable; shaping
        -- was attempted exhaustively and reverted (2026-07-31). Keep users
        -- informed instead of letting them hunt for a shape option.
        W.Text(section, "Aura Style > Defensive Buffs can follow the frame portrait shape.", 24, -312, inner, T.colors.muted)
        W.Text(section, M.Format("Source: player buffs · %d / %d predefined enabled · %d custom · passive talent procs included",
        predefined, predefinedTotal, custom), 24, -344, inner, T.colors.muted)
        return true
    end
end

local function BuildCustomDotsSetup(C)
    local ctx, b, unit, index, customActionPath, isTargetDots, item, Apply = C.ctx, C.b, C.unit, C.index, C.customActionPath, C.isTargetDots, C.item, C.Apply
    if isTargetDots then
        local section = b:Section("Dots on target Setup", 410)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local enabled = BindSwitch(ctx, section, "Enabled", 24, -48, 112,
            function() return item.enabled == true end,
            function(value) item.enabled = value == true; Apply("AURAS3_TARGET_DOTS_ENABLE", true) end,
            AuraControlMeta(ctx, "custom-container.target-dots.enabled"))
        AddTooltip(enabled, "Enable tracked DoTs",
            "Tracks your selected harmful auras on this UnitFrame's unit. Boss frames use their own boss1 through boss5 unit token.")
        local portrait = BindSwitch(ctx, section, "Show DoTs at portrait position", 24, -86, 280,
            function() return item.portraitIcon == true end,
            function(value)
                item.portraitIcon = value == true
                Apply("AURAS3_TARGET_DOTS_PORTRAIT", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-icon"))
        AddTooltip(portrait, "Show DoTs at portrait position",
            "Replaces the normal DoT lane with portrait-sized icons. The first icon exactly follows this frame's portrait width, height, and shape.")
        local portraitMax = BindSlider(ctx, section, "Max portrait icons", 24, -128, 1, 8, 1, inner,
            function() return tonumber(item.portraitMaxIcons) or 1 end,
            function(value)
                item.portraitMaxIcons = max(1, min(8, floor((tonumber(value) or 1) + 0.5)))
                Apply("AURAS3_TARGET_DOTS_PORTRAIT_MAX", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-max-icons"))
        AddTooltip(portraitMax, "Max portrait icons",
            "Limits simultaneous DoT icons at the portrait from 1 to 8. Additional icons grow outward using this DoT lane's configured Growth direction.")
        local cooldownText = BindSwitch(ctx, section, "Show cooldown text on portrait", 24, -198, 280,
            function() return item.portraitCooldownText ~= false end,
            function(value)
                item.portraitCooldownText = value == true
                Apply("AURAS3_TARGET_DOTS_PORTRAIT_COOLDOWN", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-cooldown-text"))
        AddTooltip(cooldownText, "Show cooldown text on portrait",
            "Shows the tracked DoT's remaining duration over its portrait icon. Blizzard updates the duration natively.")
        local positionOnly = BindSwitch(ctx, section, "Use portrait position while portrait is off", 24, -236, 326,
            function() return item.portraitPositionWhenDisabled == true end,
            function(value)
                item.portraitPositionWhenDisabled = value == true
                Apply("AURAS3_TARGET_DOTS_PORTRAIT_POSITION", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.portrait-position-when-disabled"))
        AddTooltip(positionOnly, "Use portrait position while portrait is off",
            "Keeps the configured portrait size, position, and shape as an invisible anchor for tracked DoTs while the portrait itself is disabled.")
        local autoBlacklist = BindSwitch(ctx, section, "Auto-blacklist from Debuffs", 24, -274, 280,
            function() return item.autoBlacklistDebuffs ~= false end,
            function(value)
                item.autoBlacklistDebuffs = value == true
                Apply("AURAS3_TARGET_DOTS_AUTO_BLACKLIST", true)
            end,
            AuraControlMeta(ctx, "custom-container.target-dots.auto-blacklist-debuffs"))
        AddTooltip(autoBlacklist, "Auto-blacklist from Debuffs",
            "Hides this scope's selected DoT Spell IDs from the same UnitFrame's normal Debuff container while Dots on target is enabled. Blizzard's blacklist is SpellID-based, so the same spell cast by another player is hidden there too.")
        local reset = ActionButton(section, "Reset", 88)
        reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -42)
        reset:SetScript("OnClick", function() Model.ResetCustomContainer(unit, index); Apply("AURAS3_TARGET_DOTS_RESET", true); Rebuild(ctx) end)
        RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
            actionKey = "reset_aura_custom_container", actionFixedArgs = { scope = unit, index = index },
        })
        local count = #Model.CustomContainerSpellEntries(unit, index)
        W.Text(section, M.Format("Source: this UnitFrame · Ownership: only mine · Harmful DoTs only · %d selected", count), 24, -324, inner, T.colors.muted)
        W.Text(section, "Display: " .. (item.portraitIcon == true and "portrait position" or "normal DoT lane"), 24, -356, inner, T.colors.muted)
        return true
    end
end

local function BuildCustomContainerSetup(C)
    local ctx, b, unit, index, customActionPath, containerLabel, item, Apply, Grid = C.ctx, C.b, C.unit, C.index, C.customActionPath, C.containerLabel, C.item, C.Apply, C.Grid
    local setupW = b.width or 720
    local compactSetup = setupW < 680
    local section = b:Section(containerLabel .. " Setup", compactSetup and 262 or 210)
    local w = section._msuf2Width or setupW
    local inner = w - 48
    local enabled = BindSwitch(ctx, section, "Enabled", 24, compactSetup and -52 or -62, 106,
        function() return item.enabled == true end,
        function(value) item.enabled = value == true; Apply("AURAS3_CUSTOM_CONTAINER_ENABLE") end,
        AuraControlMeta(ctx, "custom-container.setup.enabled"))
    local resetW = 88
    local reset = ActionButton(section, "Reset", resetW)
    reset:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, compactSetup and -46 or -56)
    reset:SetScript("OnClick", function() Model.ResetCustomContainer(unit, index); Apply("AURAS3_CUSTOM_CONTAINER_RESET", true); Rebuild(ctx) end)
    RegisterAuraControl(ctx, reset, "Reset", "button", customActionPath .. ".setup.reset", "action", {
        actionKey = "reset_aura_custom_container",
        actionFixedArgs = { scope = unit, index = index },
    })

    local fieldX = compactSetup and 24 or 140
    local fieldY = compactSetup and -82 or -34
    local fieldRight = compactSetup and (w - 24) or (w - 24 - resetW - 12)
    local fieldGap = 12
    local fieldSpace = max(0, fieldRight - fieldX - fieldGap)
    local typeW = compactSetup and max(140, floor(fieldSpace * 0.34))
        or max(150, min(max(170, floor(inner * 0.18)), fieldSpace - 200))
    local nameW = compactSetup and max(120, fieldSpace - typeW)
        or max(120, min(max(260, floor(inner * 0.42)), fieldSpace - typeW))
    BindTextInput(ctx, section, "Container name", fieldX, fieldY, nameW,
        function() return item.name or ("Custom " .. tostring(index)) end,
        function(value) item.name = value ~= "" and value or ("Custom " .. tostring(index)); Apply("AURAS3_CUSTOM_CONTAINER_NAME") end,
        false, AuraControlMeta(ctx, "custom-container.setup.name"))
    BindDropdown(ctx, section, "Aura type", fieldX + nameW + fieldGap, fieldY, CUSTOM_AURA_TYPES, typeW,
        function() return item.auraType == "DEBUFF" and "DEBUFF" or "BUFF" end,
        function(value)
            local nextType = value == "DEBUFF" and "DEBUFF" or "BUFF"
            local prevType = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
            -- A duration ceiling configured for one aura type must not survive
            -- the switch: since 6.09 it compiles for every lane and would
            -- silently hide long or permanent auras of the other type.
            if nextType ~= prevType and type(item.filters) == "table" then
                item.filters.maxDuration = nil
            end
            item.auraType = nextType
            Apply("AURAS3_CUSTOM_CONTAINER_TYPE", true)
            Rebuild(ctx)
        end,
        AuraControlMeta(ctx, "custom-container.setup.aura-type"))
    local modeY = (compactSetup and -82 or -34) - 70
    BindDropdown(ctx, section, "Display", 24, modeY, CUSTOM_DISPLAY_MODES, max(200, min(320, floor(inner * 0.42))),
        function() return item.placed.reminderEnabled == true and "reminder" or "active" end,
        function(value)
            item.placed.reminderEnabled = value == "reminder"
            Apply("AURAS3_CUSTOM_REMINDER", true)
            Rebuild(ctx)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.enabled"))
    local modeNote = W.Text(section, "", 24, modeY - 44, inner, T.colors.muted)
    local count = #Model.CustomContainerSpellEntries(unit, index)
    W.Text(section, count == 1 and Tr("1 whitelisted spell · style remains live in Menu Preview and Edit Mode.")
        or M.Format("%d whitelisted spells · style remains live in Menu Preview and Edit Mode.", count), 24, modeY - 66, inner, T.colors.muted)
    M.TrackRefresh(ctx, function()
        modeNote:SetText(item.placed.reminderEnabled == true
            and Tr("Every whitelisted entry keeps its own place. A dimmed icon means that entry is missing.")
            or Tr("Only auras that are currently active are shown, packed together."))
    end)

    -- Buff Reminder. Exact Spell ID whitelists are the only aura source that
    -- can carry one fixed slot per spell, so the mode belongs to Custom 1-3.
    -- It is never state driven: MSUF cannot read whether an aura is present
    -- on 12.1, so the placeholder is simply drawn beneath the native icon.
    local reminderSection = b:CollapsibleSection("aura_reminder_custom_" .. tostring(index),
        "Buff Reminder", 258, false)
    local rw = reminderSection._msuf2Width or setupW
    local rInner = rw - 48
    local rcol, rgap = Grid(rw, 2)
    -- The mode itself lives in Setup next to Aura type; this section owns only
    -- how the reminder looks and what a click on it does.
    local reminderAlpha = BindSlider(ctx, reminderSection, "Placeholder opacity", 24, -46, 10, 100, 5, rcol,
        function() return floor(((tonumber(item.placed.reminderAlpha) or 0.45) * 100) + 0.5) end,
        function(value)
            item.placed.reminderAlpha = max(0.1, min(1, (tonumber(value) or 45) / 100))
            Apply("AURAS3_CUSTOM_REMINDER_ALPHA", true)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.opacity"))
    AddTooltip(reminderAlpha, "Placeholder opacity",
        "How strongly a missing aura's placeholder is drawn. Lower values keep the frame calm; the running aura always covers it completely either way.")
    local reminderDesaturate = BindSwitch(ctx, reminderSection, "Grey out placeholders", 24 + rcol + rgap, -46, rcol,
        function() return item.placed.reminderDesaturate ~= false end,
        function(value)
            item.placed.reminderDesaturate = value == true
            Apply("AURAS3_CUSTOM_REMINDER_DESATURATE", true)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.desaturate"))
    AddTooltip(reminderDesaturate, "Grey out placeholders",
        "Draws the placeholder without colour so a missing aura reads at a glance. Turn this off to keep the spell's own colours and separate the two states by opacity or tint alone.")
    local reminderColor = W.Color(reminderSection, "Placeholder tint")
    M.BindColor(ctx, reminderColor,
        function()
            local c = type(item.placed.reminderColor) == "table" and item.placed.reminderColor or nil
            return c and c[1] or 1, c and c[2] or 1, c and c[3] or 1
        end,
        function(r, g, blue)
            item.placed.reminderColor = { r, g, blue }
            Apply("AURAS3_CUSTOM_REMINDER_COLOR", true)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.color"))
    reminderColor:Hide()
    if reminderColor._msuf2Title then
        reminderColor._msuf2Title:Hide()
        reminderColor._msuf2Title._msuf2AlwaysHidden = true
    end
    local reminderClick = BindSwitch(ctx, reminderSection, "Click the icon to cast the spell", 24, -96, rInner,
        function() return item.placed.reminderClickCast ~= false end,
        function(value)
            item.placed.reminderClickCast = value == true
            Apply("AURAS3_CUSTOM_REMINDER_CLICK_CAST", true)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.click-cast"))
    AddTooltip(reminderClick, "Click the icon to cast the spell",
        "Turns every reminder slot into a cast button: clicking it casts that slot's spell at this frame's unit, whether the aura is missing or already running, so re-applying a poison or flask works. The binding is written once outside combat and never changes afterwards, so this costs no timer, no event and no aura read. Only spells work; food, flasks and other items cannot be triggered this way.")
    -- One whitelist for every character: with this on, a Mage's reminder row
    -- keeps Arcane Intellect and drops the Rogue poisons from the same profile.
    -- Rows with a bound item stay either way -- an item is class agnostic.
    local reminderSelfOnly = BindSwitch(ctx, reminderSection, "Only show what I can apply myself", 24, -142, rInner,
        function() return item.placed.reminderOnlyCastable == true end,
        function(value)
            item.placed.reminderOnlyCastable = value == true
            Apply("AURAS3_CUSTOM_REMINDER_SELF_ONLY", true)
        end,
        AuraControlMeta(ctx, "custom-container.reminder.only-castable"))
    AddTooltip(reminderSelfOnly, "Only show what I can apply myself",
        "Hides every whitelisted spell this character cannot cast, without leaving a gap. One whitelist can then serve all your characters: the Mage keeps Arcane Intellect, the Rogue keeps the poisons. Nothing reports which class owns a Spell ID, so a flask buff looks exactly like a foreign class ability here - protect those with a bound item, or with Always show on the row in the Whitelist. MSUF re-checks this only when your spellbook or talents actually change, never during combat.")
    local reminderStatus = W.Text(reminderSection, "", 24, -190, rInner, T.colors.muted)
    M.TrackRefresh(ctx, function()
        W.SetControlEnabled(enabled, true)
        local on = item.placed.reminderEnabled == true
        if type(W.SetControlsEnabled) == "function" then
            W.SetControlsEnabled({ reminderAlpha, reminderDesaturate, reminderClick, reminderSelfOnly }, on)
        end
        local cap = max(0, floor(tonumber(item.placed.max) or 8))
        local allEntries = Model.CustomContainerSpellEntries(unit, index)
        -- A filtered row is not a slot, so it must not be counted as one.
        local selfOnly = item.placed.reminderOnlyCastable == true
        local hidden, slots = 0, 0
        for i = 1, #allEntries do
            local entry = allEntries[i]
            if selfOnly and not entry.clickAction and entry.keep ~= true then
                hidden = hidden + 1
            elseif slots < cap then
                slots = slots + 1
            end
        end
        if unit == "player" then
            if item.reminderEnchantMainHand == true and slots < cap then slots = slots + 1 end
            if item.reminderEnchantOffHand == true and slots < cap then slots = slots + 1 end
        end
        -- One line, three facts: how many slots, how many of them react to a
        -- click, and where their order comes from.
        if not on then
            reminderStatus:SetText(Tr("Off · switch Display to Fixed slots in Setup to use this."))
        else
            local clickable, counted = 0, 0
            for i = 1, #allEntries do
                local entry = allEntries[i]
                if not (selfOnly and not entry.clickAction and entry.keep ~= true) and counted < cap then
                    counted = counted + 1
                    if entry.clickAction then clickable = clickable + 1 end
                end
            end
            if unit == "player" then
                local hasItem = Model.CustomContainerReminderEnchantItem(unit, index) ~= nil
                if item.reminderEnchantMainHand == true and counted < cap then
                    counted = counted + 1
                    if hasItem then clickable = clickable + 1 end
                end
                if item.reminderEnchantOffHand == true and counted < cap then
                    counted = counted + 1
                    if hasItem then clickable = clickable + 1 end
                end
            end
            local base = item.placed.reminderClickCast == false
                and M.Format("%d fixed slots · order comes from the Whitelist.", slots)
                or M.Format("%d fixed slots · %d clickable · order comes from the Whitelist.",
                    slots, clickable)
            -- Say it out loud when the filter is swallowing rows, otherwise a
            -- whitelisted entry would just be missing with no explanation.
            if hidden > 0 then
                base = base .. " " .. M.Format("%d hidden: not castable by this character.", hidden)
            end
            reminderStatus:SetText(base)
        end
        if W.SetCollapsibleBadges then
            local badges = {{
                text = on and Tr("Reminder on") or Tr("Reminder off"),
                kind = on and "accent" or "muted", showWhenClosed = true,
            }}
            if on and item.placed.reminderClickCast ~= false then
                badges[#badges + 1] = { text = Tr("Click-cast"), kind = "info", showWhenClosed = true }
            end
            W.SetCollapsibleBadges(reminderSection, badges)
        end
    end)
end

--- Compact, task-focused Custom Aura editor used inside UnitFrame > Auras.
--- Only one tool is rendered at a time; all values still write to the same
--- native Custom Container record consumed by runtime and previews.
function M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, tool)
    index = max(1, min(type(Model.CustomContainerMax) == "function" and Model.CustomContainerMax() or 3, tonumber(index) or 1))
    -- The selected Custom Aura index is part of an action's executable
    -- identity.  Reusing one path for Custom 1/2/3 made the generated schema
    -- collapse three different fixed argument contracts into one action.
    local customActionPath = "custom-container.custom" .. tostring(index)
    local isPlayerDefensives = unit == "player" and index == 4
    local isTargetDots = unit ~= "player" and index == 4
    local containerLabel = isPlayerDefensives and "Defensive Buffs"
        or (isTargetDots and "Dots on target" or ("Custom " .. tostring(index)))
    local item = Model.CustomContainer(unit, index, true)
    if not item then return end
    item.filters = type(item.filters) == "table" and item.filters or {}
    item.placed = type(item.placed) == "table" and item.placed or {}
    item.frame = type(item.frame) == "table" and item.frame or { type = "none", color = { 0.69, 0.50, 0.88, 0.8 }, priority = 5, thickness = 2, layer = 0, strata = "AUTO" }
    if type(item.frame.color) ~= "table" then item.frame.color = { 0.69, 0.50, 0.88, 0.8 } end
    local styleItem = item
    local function Apply(reason, rebuild)
        ApplyUnit(ctx, unit, reason or "AURAS3_CUSTOM_CONTAINER", rebuild == true)
        if type(ctx._auraAppearancePreviewRefresh) == "function" then ctx._auraAppearancePreviewRefresh() end
    end
    local function Grid(w, count, gap)
        gap = gap or 10
        return floor(((w - 48) - gap * (count - 1)) / count), gap
    end
    local C = {
        ctx = ctx, b = b, unit = unit, index = index, tool = tool,
        customActionPath = customActionPath, isPlayerDefensives = isPlayerDefensives,
        isTargetDots = isTargetDots, containerLabel = containerLabel,
        item = item, styleItem = styleItem, Apply = Apply, Grid = Grid,
    }

    -- Every UnitFrame-local Custom Aura exposes the same rich styling
    -- accordions, tailored to its aura type. Dots additionally expose Pandemic;
    -- all containers retain their Full-Frame effect controls.
    if tool == "style" then
        M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, "appearance")
        M.BuildAuras3CompactCustomWorkspace(ctx, b, unit, index, "effect")
        return
    end

    if BuildCustomDefensivesTool(C) then return end
    if BuildCustomDotsTool(C) then return end
    if BuildCustomWhitelistTool(C) then return end
    if BuildCustomFiltersTool(C) then return end
    if BuildCustomLayoutTool(C) then return end
    if BuildCustomAppearanceTool(C) then return end
    if BuildCustomEffectTool(C) then return end
    if BuildCustomBehaviorTool(C) then return end
    if BuildCustomDefensivesSetup(C) then return end
    if BuildCustomDotsSetup(C) then return end
    BuildCustomContainerSetup(C)
end
