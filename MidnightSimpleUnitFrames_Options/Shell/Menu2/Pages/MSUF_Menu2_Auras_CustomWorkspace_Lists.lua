-- Custom Aura lists tools; retains the shared per-build container context.
local _, MSUF = ...
local M = MSUF.MSUF2
local Parts = M.CustomAuraWorkspaceParts
local HideInlineSwatch = Parts.HideInlineSwatch
local PixelLayoutRegion = Parts.PixelLayoutRegion
local W = Parts.W
local T = Parts.T
local Model = Parts.Model
local AurasPage = Parts.AurasPage
local CreateFrame = Parts.CreateFrame
local floor = Parts.floor
local max = Parts.max
local min = Parts.min
local tonumber = Parts.tonumber
local tostring = Parts.tostring
local type = Parts.type
local BindSwitch = Parts.BindSwitch
local BindSlider = Parts.BindSlider
local BindDropdown = Parts.BindDropdown
local ActionButton = Parts.ActionButton
local AddTooltip = Parts.AddTooltip
local AuraCatalogToken = Parts.AuraCatalogToken
local AuraControlMeta = Parts.AuraControlMeta
local FilterSpellEntries = Parts.FilterSpellEntries
local MatchSuffix = Parts.MatchSuffix
local NATIVE_EXACT_AURA_FILTERS_TEXT = Parts.NATIVE_EXACT_AURA_FILTERS_TEXT
local Rebuild = Parts.Rebuild
local Repaint = Parts.Repaint
local RegisterAuraControl = Parts.RegisterAuraControl
local RegisterAuraTextAction = Parts.RegisterAuraTextAction
local Tr = Parts.Tr
local REMINDERS_AVAILABLE = Parts.REMINDERS_AVAILABLE
local TRANSLATED_TITLE = Parts.TRANSLATED_TITLE
local ContainerTitle = Parts.ContainerTitle
local BindListSearch = Parts.BindListSearch
local BindInputAction = Parts.BindInputAction
local AddSpellRoute = Parts.AddSpellRoute
local ListScroll = Parts.ListScroll
local RowAction = Parts.RowAction
local RowPriorityDrag = Parts.RowPriorityDrag

--- A Custom Priority spell list (Dots on target, or the Whitelist when
--- L.whitelist is set). Rows are built on demand by L.newRow(C, L, i); the
--- returned painter repaints the status line, the empty or no-result text and
--- every row. It runs on each search keystroke, so the status text and both
--- row kinds are painted inline, the kind chosen when the list is built.
local function PriorityList(C, L)
    local rows = {}
    local whitelist, isDebuff = L.whitelist == true, L.isDebuff == true
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = L.newRow(C, L, i)
        rows[i] = row
        return row
    end
    return function()
        local ctx, customActionPath, item = C.ctx, C.customActionPath, C.item
        local entries = Model.CustomContainerSpellEntries(C.unit, C.index)
        local query, visible = FilterSpellEntries(entries, L.search.value)
        local customPriority = tostring(item.placed.sortMethod or ""):upper() == "CUSTOM_PRIORITY"
        -- Whole sentence per lane: the noun cannot be joined to a fragment, so each
        -- language orders and inflects the label itself.
        local statusText
        if whitelist then
            statusText = M.Format(isDebuff and "Tracked debuffs (%d of 40)" or "Tracked buffs (%d of 40)", #entries)
        else
            statusText = M.Format("%d tracked DoTs", #entries)
        end
        T.SetTranslatedText(L.status, statusText
            .. (customPriority and query ~= "" and Tr(" - clear Search to reorder")
                or customPriority and Tr(" - dynamic priority active")
                or Tr(" - drag to set Custom Priority"))
            .. MatchSuffix(query, #visible))
        T.SetTranslatedText(L.empty, #entries == 0 and Tr(L.emptyText)
            or M.Format("No results for \"%s\".", query))
        L.empty:SetShown(#visible == 0)
        L.listScroll:SetShown(#visible > 0)
        L.listChild:SetHeight(max(L.minHeight, #visible * L.rowHeight))
        for i = 1, max(#rows, #visible) do
            local row, entry = rows[i], visible[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.spellID
                T.SetTranslatedText(row.rank, "#" .. tostring(entry.priority or i))
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if whitelist then
                    local name = tostring(entry.text or entry.spellID or "Spell"):gsub("%s*%(#%d+%)$", "")
                    T.SetTranslatedText(row.name, name)
                    -- Say plainly what a click on this row will do. A tracked
                    -- aura the player cannot apply has no click action, and a
                    -- silently dead button is worse than a visible hint.
                    local clickNote = not REMINDERS_AVAILABLE and Tr("Reminder clicks are unavailable on Classic")
                        or entry.clickAction == "item" and Tr("Click uses this item")
                        or entry.clickAction == "spell" and Tr("Click casts this")
                        or Tr("No click action \194\183 paste an item")
                    -- The self-cast filter is the only thing that can make a
                    -- whitelisted row disappear, so the row has to say so itself
                    -- rather than letting it vanish without explanation.
                    local filtering = REMINDERS_AVAILABLE and item.placed.reminderEnabled == true
                        and item.placed.reminderOnlyCastable == true
                    local exempt = entry.keep == true
                    local stateNote = ""
                    if filtering and exempt then
                        stateNote = " \194\183 " .. Tr("always shown")
                    elseif filtering and not entry.clickAction then
                        stateNote = " \194\183 " .. Tr("hidden on this character")
                    end
                    T.SetTranslatedText(row.id, M.Format("Spell ID %s", tostring(entry.spellID))
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
                    RegisterAuraControl(ctx, row.remove, M.Format("Remove %s", name), "button",
                        customActionPath .. ".whitelist.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                else
                    T.SetTranslatedText(row.text, entry.text or tostring(entry.spellID))
                    RegisterAuraControl(ctx, row.remove, M.Format("Remove %s", entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                    RegisterAuraControl(ctx, row.up, M.Format("Raise %s", entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".up", "action")
                    RegisterAuraControl(ctx, row.down, M.Format("Lower %s", entry.text or tostring(entry.spellID)), "button",
                        customActionPath .. ".dots.entry." .. AuraCatalogToken(entry.spellID) .. ".down", "action")
                    if W.SetControlsEnabled then
                        W.SetControlsEnabled({ row.up }, customPriority and query == "" and (entry.priority or i) > 1)
                        W.SetControlsEnabled({ row.down }, customPriority and query == "" and (entry.priority or i) < #entries)
                    end
                end
                row._entryCount = #entries
                row._displayIndex = i
                row._dragEnabled = query == "" and #entries > 1
                row:Show()
            elseif row then
                row._spellID = nil
                row._displayIndex = nil
                row._dragEnabled = nil
                row:Hide()
            end
        end
    end
end
--- The section's ::: shortcut is the only visible entry to this color, so the
--- bound inline swatch and its title stay hidden.
--- The predefined class defensives of Player Defensives: one switch per spell
--- in a scroll list filtered by the Search text. Returns the list's painter.
local function BuildPredefinedDefensives(C, section, inner, predefined, predefinedStatus, search)
    local unit, Apply = C.unit, C.Apply
    local _, predefinedChild = ListScroll(section, -108, inner, 184, max(184, #predefined * 30), 30)
    local predefinedSwitches = {}
    local predefinedIcons = {}
    local function RefreshPredefined()
        local enabledCount = 0
        local visibleCount = 0
        local query = tostring(search.value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
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
        T.SetTranslatedText(predefinedStatus, M.Format("%d / %d predefined enabled", enabledCount, #predefined)
            .. MatchSuffix(query, visibleCount))
        predefinedChild:SetHeight(max(184, visibleCount * 30))
    end
    for i = 1, #predefined do
        local entry = predefined[i]
        local spellID = entry.spellID
        local icon = PixelLayoutRegion(predefinedChild:CreateTexture(nil, "ARTWORK"))
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
    return RefreshPredefined
end
--- The custom buffs added to Player Defensives: a click on a row removes it.
--- Returns the list's painter.
local function BuildCustomDefensiveList(C, section, inner, search)
    local ctx, unit, index, customActionPath, Apply = C.ctx, C.unit, C.index, C.customActionPath, C.Apply
    local status = W.Text(section, "", 24, -392, inner, T.colors.accent)
    local empty = W.Text(section, "No custom buffs added.", 24, -442, inner, T.colors.muted)
    local listScroll, listChild = ListScroll(section, -418, inner, 118, 104, 32)
    local rows = {}
    local function EnsureRow(i)
        local row = rows[i]
        if row then return row end
        row = M.AuraControls.CompactSpellRow(listChild, i, function(self)
            if self._spellID and Model.RemoveCustomContainerSpell(unit, index, self._spellID) then
                Apply("AURAS3_PLAYER_DEFENSIVE_CUSTOM_REMOVE", true)
                Repaint(ctx)
            end
        end)
        rows[i] = row
        return row
    end
    return function()
        local entries = Model.CustomContainerSpellEntries(unit, index)
        local enabledPredefined = Model.PlayerDefensivePreviewEntries
            and #Model.PlayerDefensivePreviewEntries() or 0
        local query, visible = FilterSpellEntries(entries, search.value)
        T.SetTranslatedText(status, M.Format("%d predefined enabled · %d custom · click a custom entry to remove",
            enabledPredefined, #entries) .. MatchSuffix(query, #visible))
        T.SetTranslatedText(empty, #entries == 0 and Tr("No custom buffs added.")
            or M.Format("No results for \"%s\".", query))
        empty:SetShown(#visible == 0)
        listScroll:SetShown(#visible > 0)
        listChild:SetHeight(max(118, #visible * 24))
        for i = 1, max(#rows, #visible) do
            local row, entry = rows[i], visible[i]
            if entry then
                row = EnsureRow(i)
                row._spellID = entry.spellID
                row.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                T.SetTranslatedText(row.text, entry.text or tostring(entry.spellID))
                RegisterAuraControl(ctx, row, entry.text or tostring(entry.spellID), "button",
                    customActionPath .. ".defensives.entry." .. AuraCatalogToken(entry.spellID) .. ".remove", "action")
                row:Show()
            elseif row then
                row._spellID = nil
                row:Hide()
            end
        end
    end
end
-- Every tool builder below receives the workspace record C and re-establishes the
-- same local names the inline body used; a builder returns true when its tool
-- matched, so the dispatcher keeps the original first-match order.
local function BuildCustomDefensivesTool(C)
    local ctx, b, unit, index, tool, customActionPath, isPlayerDefensives = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.isPlayerDefensives
    if tool == "defensives" and isPlayerDefensives then
        local section = b:Section("Defensive Buffs", 560)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local predefined = Model.PlayerDefensiveClassEntries
            and Model.PlayerDefensiveClassEntries(true) or {}
        local predefinedStatus = W.Text(section, "", 24, -34, inner, T.colors.accent)
        local lists = {}
        local search = BindListSearch(ctx, section, -58, inner, "custom-container.player-defensives.search", function()
            if lists.predefined then lists.predefined() end
            if lists.custom then lists.custom() end
        end)
        lists.predefined = BuildPredefinedDefensives(C, section, inner, predefined, predefinedStatus, search)
        M.TrackRefresh(ctx, lists.predefined)
        local customInput = BindInputAction(C, section, {
            label = "Track a buff - Spell ID, link, or name", y = -322, width = max(140, inner - 132),
            path = "custom-container.player-defensives.custom-id",
            button = "Add buff", buttonWidth = 108, point = "TOPRIGHT", x = -24, buttonY = -344,
            submit = function(value) return Model.AddCustomContainerSpell(unit, index, value, true) end,
            reason = "AURAS3_PLAYER_DEFENSIVE_CUSTOM_ADD",
            actionPath = customActionPath .. ".defensives.custom-id.add", route = AddSpellRoute(C),
        })
        AddTooltip(customInput, "Exact aura tracking",
            "Enter a Spell ID, paste a spell link, or type a spell name. The visible helpful aura is matched even when its buff ID differs from the cast "
                .. "Spell ID.")
        lists.custom = BuildCustomDefensiveList(C, section, inner, search)
        M.TrackRefresh(ctx, lists.custom)
        return true
    end
end

--- Row i of the Dots on target list: rank, icon, name, Up/Down/X and drag.
local function NewDotRow(C, L, i)
    local unit, index, listChild = C.unit, C.index, L.listChild
    local row = PixelLayoutRegion(CreateFrame("Frame", nil, listChild))
    row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -((i - 1) * 34))
    row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -((i - 1) * 34))
    row:SetHeight(30)
    if T.ApplyBackdrop then T.ApplyBackdrop(row, T.colors.panel2, T.colors.cardBorder or T.colors.borderSoft) end
    row.rank = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
    row.rank:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.rank:SetWidth(24)
    row.icon = PixelLayoutRegion(row:CreateTexture(nil, "ARTWORK"))
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
    RowAction(C, row, row.up, "AURAS3_TARGET_DOT_PRIORITY",
        function(spellID) return Model.MoveCustomContainerSpell(unit, index, spellID, -1) end)
    RowAction(C, row, row.down, "AURAS3_TARGET_DOT_PRIORITY",
        function(spellID) return Model.MoveCustomContainerSpell(unit, index, spellID, 1) end)
    RowAction(C, row, row.remove, "AURAS3_TARGET_DOT_REMOVE",
        function(spellID) return Model.RemoveCustomContainerSpell(unit, index, spellID) end)
    AddTooltip(row.up, "Move up", "Raises this DoT in the fixed priority order.")
    AddTooltip(row.down, "Move down", "Lowers this DoT in the fixed priority order.")
    AddTooltip(row.remove, "Remove DoT", "Stops tracking this DoT.")
    RowPriorityDrag(C, row, listChild, 34, "AURAS3_TARGET_DOT_PRIORITY")
    return row
end
--- A Dots on target row's name, its three search actions and Up/Down state.
local function BuildCustomDotsTool(C)
    local ctx, b, unit, index, tool, customActionPath, isTargetDots, Apply = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.isTargetDots, C.Apply
    if tool == "dots" and isTargetDots then
        local section = b:Section("Dots on target", 430)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local values = Model.TargetDotValues and Model.TargetDotValues() or {}
        local selected
        for i = 1, #values do
            if values[i].value then
                selected = values[i].value
                break
            end
        end
        local dropdown = BindDropdown(ctx, section, "DoT", 24, -34, values, max(140, inner - 132),
            function() return selected end,
            function(value) selected = value end,
            AuraControlMeta(ctx, "custom-container.target-dots.selection", "ephemeral"))
        local add = ActionButton(section, "Track DoT", 108)
        add:SetPoint("TOPRIGHT", section, "TOPRIGHT", -24, -56)
        add:SetScript("OnClick", function()
            local changed = selected and Model.AddCustomContainerSpell(unit, index, selected)
            if changed then
                Apply("AURAS3_TARGET_DOT_ADD", true)
                Repaint(ctx)
            end
            return changed and true or false
        end)
        RegisterAuraTextAction(ctx, add, {
            SetText = function(_, value) selected = value end,
        }, "Track DoT", customActionPath .. ".dots.add", AddSpellRoute(C))
        -- Only Midnight lists the curated Retail 12.x DoTs; Classic Era, TBC, Mists and
        -- WoW Forever load their own client's DoT data (Game/<client>/Auras).
        local client = MSUF.Client
        AddTooltip(dropdown, "Target DoT", (not client or (client.IsRetail == true and not client.IsForever))
            and "Curated Retail 12.0+ and 12.1 DoT auras. Tracking is restricted to this UnitFrame's unit and your own aura source; Boss settings bind "
                .. "separately to boss1 through boss5."
            or "Curated DoT auras for this game version. Tracking is restricted to this UnitFrame's unit and your own aura source; Boss settings bind "
                .. "separately to boss1 through boss5.")
        local customInput = BindInputAction(C, section, {
            label = "Custom Spell ID", y = -94, width = max(140, inner - 132),
            path = "custom-container.target-dots.custom-id",
            button = "Add Custom ID", buttonWidth = 108, point = "TOPRIGHT", x = -24, buttonY = -116,
            submit = function(value) return Model.AddCustomContainerSpell(unit, index, value, true) end,
            reason = "AURAS3_TARGET_DOT_CUSTOM_ADD",
            actionPath = customActionPath .. ".dots.custom-id.add", route = AddSpellRoute(C),
        })
        AddTooltip(customInput, "Custom Spell ID",
            "Adds an exact harmful aura ID that is missing from the curated list. The aura is still restricted to your current target and your own aura "
                .. "source.")
        local status = W.Text(section, "", 24, -162, inner, T.colors.accent)
        local refreshList
        local search = BindListSearch(ctx, section, -186, inner, "custom-container.target-dots.search",
            function() if refreshList then refreshList() end end)
        local empty = W.Text(section, "No DoT selected. Choose one above or add a custom Spell ID.", 24, -288, inner, T.colors.muted)
        local listScroll, listChild = ListScroll(section, -236, inner, 164, 164, 32)
        refreshList = PriorityList(C, {
            search = search, status = status, empty = empty, listScroll = listScroll, listChild = listChild,
            emptyText = "No DoT selected. Choose one above or add a custom Spell ID.",
            minHeight = 164, rowHeight = 34, newRow = NewDotRow,
        })
        M.TrackRefresh(ctx, refreshList)
        return true
    end
end

local function BuildCustomWhitelistEnchants(C)
    local ctx, b, unit, index, customActionPath, item, Apply, Grid = C.ctx, C.b, C.unit, C.index, C.customActionPath, C.item, C.Apply, C.Grid
    if unit == "player" then
        local ench = AurasPage.Section(b, "aura_reminder_enchants_" .. tostring(index),
            "Weapon enchants", 284, false)
        local ew = ench._msuf2Width or b.width or 720
        local eInner = ew - 48
        local ecol, egap = Grid(ew, 2)
        -- One weapon slot: its reminder switch writes the record key and repaints.
        local function HandSwitch(label, x, key, path)
            return BindSwitch(ctx, ench, label, x, -46, ecol,
                function() return item[key] == true end,
                { write = { container = C, source = function() return item end, strictBoolean = true,
                    after = function() Apply("AURAS3_CUSTOM_REMINDER_ENCHANT", true) Repaint(ctx) end
                } --[[schema setter: J5.CustomLists.Enchant]] },
                AuraControlMeta(ctx, path))
        end
        local enchantMain = HandSwitch("Track the Main Hand enchant", 24, "reminderEnchantMainHand",
            "custom-container.reminder.enchant-main-hand")
        AddTooltip(enchantMain, "Track the Main Hand enchant",
            "Adds a reminder slot for the temporary enchant on your main hand - a weapon oil, a stone or a weapon-applied poison. Unlike an aura this state "
                .. "is plainly readable, so the icon lights up while the enchant runs and dims when it is gone, in every kind of content.")
        local enchantOff = HandSwitch("Track the Off Hand enchant", 24 + ecol + egap, "reminderEnchantOffHand",
            "custom-container.reminder.enchant-off-hand")
        AddTooltip(enchantOff, "Track the Off Hand enchant",
            "Same slot for your off hand. Both hands share the consumable set below, which is what you normally want.")
        local enchantInputW = max(140, min(floor(eInner * 0.62), eInner - 132))
        local enchantInput, enchantSet = BindInputAction(C, ench, {
            label = "Oil or stone - item link or ID", y = -96, width = enchantInputW,
            path = "custom-container.reminder.enchant-item",
            button = "Bind item", buttonWidth = 118, role = "primary",
            point = "TOPLEFT", x = 36 + enchantInputW, buttonY = -120,
            submit = function(value) return Model.SetCustomContainerReminderEnchantItem(unit, index, value) end,
            reason = "AURAS3_CUSTOM_REMINDER_ENCHANT_ITEM",
            actionPath = customActionPath .. ".reminder.enchant-item.set", route = {
                actionKey = "aura_custom_reminder_enchant_item",
                actionFixedArgs = { scope = unit, index = index }, actionInputArg = "value",
            },
        })
        AddTooltip(enchantInput, "Oil or stone",
            "Paste the consumable these slots should offer on click. A weapon enchant cannot be cast, so only an item makes them clickable. Leave it empty to "
                .. "keep them as pure indicators.")
        local enchantDuration = BindSlider(ctx, ench, "Enchant duration (minutes)", 24, -160,
            5, 240, 5, eInner,
            function() return tonumber(item.reminderEnchantDurationMinutes) or 60 end,
            { write = { container = C, source = function() return item end,
                numberDefault = 60, after = function() Apply("AURAS3_CUSTOM_REMINDER_ENCHANT_DURATION", true) end
            } --[[schema setter: J5.CustomLists.1]] },
            AuraControlMeta(ctx, "custom-container.reminder.enchant-duration"))
        AddTooltip(enchantDuration, "Weapon enchant duration",
            "Sets the swipe's full duration because Blizzard exposes only the remaining time. Oils normally use 60 minutes. Change this for stones or poisons "
                .. "with a different duration.")
        local enchantStatus = W.Text(ench, "", 24, -226, eInner, T.colors.muted)
        M.TrackRefresh(ctx, function()
            local reminder = REMINDERS_AVAILABLE and item.placed.reminderEnabled == true
            local tracked = (item.reminderEnchantMainHand == true and 1 or 0)
                + (item.reminderEnchantOffHand == true and 1 or 0)
            local itemID, itemName = Model.CustomContainerReminderEnchantItem(unit, index)
            if W.SetControlsEnabled then
                W.SetControlsEnabled({ enchantMain, enchantOff }, reminder)
                W.SetControlsEnabled({ enchantInput, enchantSet, enchantDuration }, reminder and tracked > 0)
            end
            if not REMINDERS_AVAILABLE then
                enchantStatus:SetText("Custom enchant reminders are unavailable on Classic. The normal player buff lane still shows weapon enchants.")
            elseif not reminder then
                enchantStatus:SetText("Needs Display set to Fixed slots in Setup · enchants have no aura to show otherwise.")
            elseif tracked == 0 then
                enchantStatus:SetText("No weapon slot tracked.")
            elseif itemID then
                T.SetTranslatedText(enchantStatus, M.Format("Click uses %s.", tostring(itemName or ("item:" .. tostring(itemID)))))
            else
                enchantStatus:SetText("No item bound · these slots only indicate.")
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

--- Row i of the Whitelist: rank, icon, name and Spell ID lines, the keep
--- switch pair, Remove and drag.
local function NewWhitelistRow(C, L, i)
    local unit, index = C.unit, C.index
    local row = M.AuraControls.SpellListRow(L.listChild, i)
    row.rank = T.Font(row, "GameFontDisableSmall", "", T.colors.accent)
    row.rank:SetPoint("LEFT", row, "LEFT", 7, 0)
    row.rank:SetWidth(24)
    M.AuraControls.SpellListRowLabels(row, row.rank, "RIGHT", 3)
    -- Two static buttons instead of one relabelled one: the styled
    -- action button has no guaranteed text setter, and a fixed label
    -- always states what the click will do.
    row.keepOn = ActionButton(row, "Always show", 96)
    row.keepOn:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.keepOff = ActionButton(row, "Filter again", 96)
    row.keepOff:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.keepOn:Hide()
    row.keepOff:Hide()
    RowAction(C, row, row.keepOn, "AURAS3_CUSTOM_REMINDER_KEEP",
        function(spellID) return Model.ToggleCustomContainerKeepSpell(unit, index, spellID, true) end)
    RowAction(C, row, row.keepOff, "AURAS3_CUSTOM_REMINDER_KEEP",
        function(spellID) return Model.ToggleCustomContainerKeepSpell(unit, index, spellID, false) end)
    AddTooltip(row.keepOn, "Always show",
        "Pins this entry so the self-cast filter never hides it. Use it for anything that is not a class ability - a flask, food, a rune, a buff someone else "
            .. "casts on you. MSUF cannot tell those apart from another class's spell on its own: nothing reports which class owns a Spell ID.")
    AddTooltip(row.keepOff, "Filter again",
        "Lets the self-cast filter decide about this entry again. It will be hidden on characters that cannot cast it.")
    row.name:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    -- The second line carries the Spell ID and what a click does, so it
    -- needs the same right edge as the name. Without it the text runs
    -- straight under the Remove button on a narrow menu.
    row.id:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    row.id:SetJustifyH("LEFT")
    row.id:SetWordWrap(false)
    RowAction(C, row, row.remove, "AURAS3_CUSTOM_WHITELIST_REMOVE",
        function(spellID) return Model.RemoveCustomContainerSpell(unit, index, spellID) end)
    AddTooltip(row.remove, "Remove from whitelist", L.removeBody)
    RowPriorityDrag(C, row, L.listChild, 44, "AURAS3_CUSTOM_PRIORITY")
    return row
end
--- A Whitelist row's name, its click and filter notes, the keep switch pair
--- and its Remove search action.
local function BuildCustomWhitelistTool(C)
    local ctx, b, unit, index, tool, customActionPath, item = C.ctx, C.b, C.unit, C.index, C.tool, C.customActionPath, C.item
    if tool == "whitelist" then
        local section = b:Section(M.Format("%s Whitelist", ContainerTitle(C)), 430, TRANSLATED_TITLE)
        local w = section._msuf2Width or b.width or 720
        local inner = w - 48
        local auraType = item.auraType == "DEBUFF" and "DEBUFF" or "BUFF"
        local auraNoun = auraType == "DEBUFF" and "debuff" or "buff"
        -- Whole sentences per lane: inserting the noun with %s breaks declension in
        -- German and Russian. `auraNoun` itself stays raw - it feeds Search action ids.
        local isDebuff = auraType == "DEBUFF"
        -- Raw keys: the button, input, search action and tooltips translate them.
        local addLabel = isDebuff and "Add debuff" or "Add buff"
        local trackHint = isDebuff and "Add a debuff - Spell ID, spell link or item link"
            or "Add a buff - Spell ID, spell link or item link"
        local addBody = isDebuff and "Adds this exact debuff to the custom container."
            or "Adds this exact buff to the custom container."
        local removeBody = isDebuff and "Stops tracking this debuff in the custom container."
            or "Stops tracking this buff in the custom container."
        W.Text(section, auraType, 24, -36, 58, T.colors.accent)
        W.Text(section, NATIVE_EXACT_AURA_FILTERS_TEXT, 88, -36, inner - 64, T.colors.muted)
        local inputW = max(140, min(floor(inner * 0.62), inner - 120))
        local input, add = BindInputAction(C, section, {
            label = trackHint, y = -76, width = inputW, path = "custom-container.whitelist.input",
            button = addLabel, buttonWidth = 108, role = "primary", point = "TOPLEFT", x = 36 + inputW, buttonY = -100,
            submit = function(value) return Model.AddCustomContainerSpell(unit, index, value) end,
            reason = "AURAS3_CUSTOM_WHITELIST_ADD",
            actionPath = customActionPath .. ".whitelist.add", route = AddSpellRoute(C),
        })
        AddTooltip(input, "Exact aura tracking",
            "Enter a Spell ID, paste a spell link, or type a spell name. This whitelist tracks exact Spell IDs. Paste an item link instead to track the buff "
                .. "that item applies and offer the item itself on click - flasks, runes, stones and potions all work that way. If the item's buff differs "
                .. "from its use effect, put both on one line: the Spell ID decides what is tracked, the item what a click uses.")
        AddTooltip(add, addLabel, addBody)
        local status = W.Text(section, "", 24, -136, floor(inner * 0.52), T.colors.accent)
        local empty = W.Text(section, "No spells tracked. Add up to 40 exact SpellIDs.",
            24, -238, inner, T.colors.muted)
        local refreshList
        local search = BindListSearch(ctx, section, -164, inner, "custom-container.whitelist.search",
            function() if refreshList then refreshList() end end)
        local listScroll, listChild = M.AuraControls.SpellListScroll(section, -214, inner, 190)
        refreshList = PriorityList(C, {
            search = search, status = status, empty = empty, listScroll = listScroll, listChild = listChild,
            whitelist = true, isDebuff = isDebuff,
            emptyText = "No spells tracked. Add up to 40 exact SpellIDs.",
            minHeight = 190, rowHeight = 44, removeBody = removeBody,
            newRow = NewWhitelistRow,
        })
        M.TrackRefresh(ctx, refreshList)

        -- Temporary weapon enchants are not auras at all -- Blizzard keeps them
        -- out of aura parsing, groups and slots -- so they cannot ride the list
        -- above. They still belong on this tab: "what is tracked" should be one
        -- question with one answer, not two places to look.
        BuildCustomWhitelistEnchants(C)
        return true
    end
end


Parts.BuildCustomDefensivesTool = BuildCustomDefensivesTool

Parts.BuildCustomDotsTool = BuildCustomDotsTool

Parts.BuildCustomWhitelistTool = BuildCustomWhitelistTool
