-- Custom-container spell lists, priorities, reminders, and preview choices.
-- This is menu-only editing: native rendering consumes prepared runtime config.
-- Keep item IDs distinct from bare spell IDs and preserve explicit keep/custom
-- choices when normalizing the curated Player Defensive and Target DoT lists.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local Factories = MSUF.Auras3MenuModelFactories
if not Factories then
    Factories = {}
    MSUF.Auras3MenuModelFactories = Factories
end

function Factories.CustomSpells(A3, Model, Schema, Common)
    local type = type
    local tonumber = tonumber
    local tostring = tostring
    local pairs = pairs
    local next = next
    local math_floor = math.floor
    local table_sort = table.sort
    local UnitClass = _G.UnitClass
    local CUSTOM_CONTAINER_MAX = Schema.CUSTOM_CONTAINER_MAX
    local PLAYER_DEFENSIVE_CONTAINER_INDEX = Schema.PLAYER_DEFENSIVE_CONTAINER_INDEX
    local TARGET_DOT_CONTAINER_INDEX = Schema.TARGET_DOT_CONTAINER_INDEX
    local ClampNumber = Common.ClampNumber
    local NormalizeScope = Common.NormalizeScope
    local SpellIDFromInput = Common.SpellIDFromInput
    local SpellInfo = Common.SpellInfo

    --- Item input for Buff Reminder slots. Only an explicit item link or an
    --- `item:<id>` token counts: a bare number stays a Spell ID so the existing
    --- whitelist behaviour cannot change under anyone.
    local function ItemIDFromInput(value)
        value = tostring(value or "")
        local itemID = tonumber(value:match("|Hitem:(%d+)") or value:match("item:(%d+)"))
        if not itemID or itemID <= 0 then return nil end
        return math_floor(itemID + 0.5)
    end

    --- Strip an item link/token so the remaining text can still be read as a
    --- Spell ID. This is what lets one input line bind an item to a specific
    --- aura ("461257 [Feast]") when the item's own use-spell is not the buff.
    local function StripItemInput(value)
        value = tostring(value or "")
        value = value:gsub("|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r", " ")
        value = value:gsub("|Hitem:.-|h.-|h", " ")
        value = value:gsub("item:[%d:%-]+", " ")
        return (value:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    function Model.ItemInfo(itemID)
        itemID = tonumber(itemID)
        if not itemID then return nil end
        local CI = _G.C_Item
        local name, icon, spellID
        if type(CI) == "table" then
            if type(CI.GetItemNameByID) == "function" then name = CI.GetItemNameByID(itemID) end
            if type(CI.GetItemIconByID) == "function" then icon = CI.GetItemIconByID(itemID) end
            if type(CI.GetItemSpell) == "function" then
                local _, id = CI.GetItemSpell(itemID)
                spellID = tonumber(id)
            end
        end
        return itemID, name, icon, spellID
    end

    --- What a click on a Buff Reminder slot will actually do. A bound item always
    --- wins; otherwise the click only does something if the player really knows
    --- the tracked spell. Cold path only -- the runtime binding never consults
    --- this, it exists so the list can tell the user which rows are dead.
    function Model.ReminderClickAction(spellID, itemID)
        if tonumber(itemID) then return "item" end
        spellID = tonumber(spellID)
        if not spellID then return nil end
        local book = _G.C_SpellBook
        if type(book) == "table" and type(book.IsSpellKnown) == "function"
            and book.IsSpellKnown(spellID) == true then return "spell" end
        if type(_G.IsPlayerSpell) == "function" and _G.IsPlayerSpell(spellID) == true then
            return "spell"
        end
        return nil
    end

    --- Rows the self-cast filter must never hide. There is no API that says which
    --- class owns a spell, so a flask buff and another class's ability look
    --- identical to IsSpellKnown: both are simply "not mine". A bound item settles
    --- it automatically; everything else is this explicit keep list.
    local function CustomContainerKeepSpells(item, create)
        local map = type(item) == "table" and item.reminderKeepSpells or nil
        if map or create ~= true or type(item) ~= "table" then return map end
        map = {}
        item.reminderKeepSpells = map
        return map
    end

    function Model.IsCustomContainerKeepSpell(unit, index, spellID)
        local item = Model.CustomContainer(unit, index, false)
        local map = CustomContainerKeepSpells(item, false)
        return map ~= nil and map[tonumber(spellID) or -1] == true
    end

    function Model.ToggleCustomContainerKeepSpell(unit, index, spellID, value)
        spellID = tonumber(spellID)
        local item = Model.CustomContainer(unit, index, true)
        if not (spellID and item) then return false, "invalid" end
        local map = CustomContainerKeepSpells(item, true)
        local next = value
        if next == nil then next = map[spellID] ~= true end
        next = next == true or nil
        if map[spellID] == next then return false, "unchanged" end
        map[spellID] = next
        return true
    end

    local function CustomContainerReminderItems(item, create)
        local map = type(item) == "table" and item.reminderItems or nil
        if map or create ~= true or type(item) ~= "table" then return map end
        map = {}
        item.reminderItems = map
        return map
    end
    Model.CustomContainerReminderItems = CustomContainerReminderItems

    local function CustomContainerSpellSet(item)
        local set = {}
        local raw = item and item.spellIDs
        if type(raw) == "string" then
            for token in raw:gmatch("%d+") do
                local spellID = tonumber(token)
                if spellID and spellID > 0 then set[math_floor(spellID)] = true end
            end
        elseif type(raw) == "table" then
            for key, enabled in pairs(raw) do
                local spellID = tonumber((type(enabled) == "number" or type(enabled) == "string") and enabled or key)
                if enabled ~= false and spellID and spellID > 0 then set[math_floor(spellID)] = true end
            end
        end
        return set
    end

    local function WriteCustomContainerSpellSet(item, set)
        local ids = {}
        for spellID, enabled in pairs(set or {}) do
            if enabled == true then ids[#ids + 1] = tonumber(spellID) end
        end
        table_sort(ids)
        for i = 1, #ids do ids[i] = tostring(ids[i]) end
        item.spellIDs = table.concat(ids, ", ")
    end

    local function ReconcileCustomContainerSpellPriority(item, create)
        local set = CustomContainerSpellSet(item)
        local raw = item and item.prioritySpellIDs
        local ordered, seen = {}, {}
        local function Add(value)
            local spellID = tonumber(value)
            if spellID then spellID = math_floor(spellID + 0.5) end
            if spellID and spellID > 0 and set[spellID] == true and not seen[spellID] then
                seen[spellID] = true
                ordered[#ordered + 1] = spellID
            end
        end
        if type(raw) == "string" then
            for token in raw:gmatch("%d+") do Add(token) end
        elseif type(raw) == "table" then
            for i = 1, #raw do Add(raw[i]) end
            for key, value in pairs(raw) do
                if type(key) ~= "number" or key < 1 or key > #raw or key % 1 ~= 0 then
                    Add((type(value) == "number" or type(value) == "string") and value or key)
                end
            end
        end
        if create == true then
            local missing = {}
            for spellID in pairs(set) do
                if not seen[spellID] then
                    local _, name = SpellInfo(spellID)
                    missing[#missing + 1] = {
                        spellID = spellID,
                        key = tostring(name or ""):lower() .. "\030" .. tostring(spellID),
                    }
                end
            end
            table_sort(missing, function(a, b) return a.key < b.key end)
            for i = 1, #missing do ordered[#ordered + 1] = missing[i].spellID end
        end
        if create == true or raw ~= nil then item.prioritySpellIDs = ordered end
        return ordered
    end

    function Model.EnableCustomContainerSpellPriority(unit, index)
        local item = Model.CustomContainer(unit, index, true)
        if not item then return false end
        ReconcileCustomContainerSpellPriority(item, true)
        item.placed = type(item.placed) == "table" and item.placed or {}
        item.placed.sortMethod = "CUSTOM_PRIORITY"
        item.placed.sortReverse = false
        return true
    end

    function Model.MoveCustomContainerSpell(unit, index, value, direction)
        local spellID = SpellIDFromInput(value)
        local item = Model.CustomContainer(unit, index, true)
        if not (spellID and item) then return false, "invalid" end
        local ordered = ReconcileCustomContainerSpellPriority(item, true)
        local from
        for i = 1, #ordered do
            if ordered[i] == spellID then from = i; break end
        end
        direction = tonumber(direction) or 0
        local to = from and (direction < 0 and from - 1 or direction > 0 and from + 1 or from)
        if not (from and to and to >= 1 and to <= #ordered and to ~= from) then return false, "unchanged" end
        ordered[from], ordered[to] = ordered[to], ordered[from]
        item.prioritySpellIDs = ordered
        return true
    end

    function Model.MoveCustomContainerSpellToIndex(unit, index, value, targetIndex)
        local spellID = SpellIDFromInput(value)
        local item = Model.CustomContainer(unit, index, true)
        if not (spellID and item) then return false, "invalid" end
        local ordered = ReconcileCustomContainerSpellPriority(item, true)
        local from
        for i = 1, #ordered do
            if ordered[i] == spellID then from = i; break end
        end
        local to = math_floor(tonumber(targetIndex) or 0)
        if not from or to < 1 or to > #ordered or to == from then return false, "unchanged" end
        table.remove(ordered, from)
        table.insert(ordered, to, spellID)
        item.prioritySpellIDs = ordered
        return true
    end

    function Model.AddCustomContainerSpell(unit, index, value, allowCustomID)
        unit = NormalizeScope(unit)
        if unit == "shared" then unit = "player" end
        -- An item may accompany a Spell ID (bind that item to that aura) or
        -- stand alone (track whatever aura the item's own use-spell applies).
        local itemID = ItemIDFromInput(value)
        local spellID = SpellIDFromInput(itemID and StripItemInput(value) or value)
        local itemSpellID
        if itemID then
            local _, _, _, resolved = Model.ItemInfo(itemID)
            itemSpellID = resolved
            spellID = spellID or resolved
        end
        local item = Model.CustomContainer(unit, index, true)
        if not (spellID and item) then
            -- An item whose use-effect is not a spell (or is not cached yet)
            -- gives nothing to track, so refuse instead of adding a dead row.
            return false, itemID and not itemSpellID and "item-no-aura" or "invalid"
        end
        if itemID then CustomContainerReminderItems(item, true)[spellID] = itemID end
        if unit == "player" and index == PLAYER_DEFENSIVE_CONTAINER_INDEX
            and Model.IsPlayerDefensiveSpell(spellID)
            and type(Model.SetPlayerDefensiveSpellEnabled) == "function"
        then
            return Model.SetPlayerDefensiveSpellEnabled(unit, spellID, true)
        end
        local customTargetDot = unit ~= "player" and index == TARGET_DOT_CONTAINER_INDEX
            and not Model.IsTargetDotSpell(spellID)
        if customTargetDot and allowCustomID ~= true then return false, "not-dot" end
        local set = CustomContainerSpellSet(item)
        if set[spellID] == true then
            if customTargetDot then
                item.customSpellIDs = type(item.customSpellIDs) == "table" and item.customSpellIDs or {}
                if item.customSpellIDs[spellID] ~= true then
                    item.customSpellIDs[spellID] = true
                    return true
                end
            end
            return false, "unchanged"
        end
        local count = 0
        for _, enabled in pairs(set) do if enabled == true then count = count + 1 end end
        if count >= 40 then return false, "full" end
        if customTargetDot then
            item.customSpellIDs = type(item.customSpellIDs) == "table" and item.customSpellIDs or {}
            item.customSpellIDs[spellID] = true
        end
        set[spellID] = true
        WriteCustomContainerSpellSet(item, set)
        if item.prioritySpellIDs ~= nil then ReconcileCustomContainerSpellPriority(item, true) end
        return true
    end

    function Model.RemoveCustomContainerSpell(unit, index, value)
        local spellID = SpellIDFromInput(value)
        local item = Model.CustomContainer(unit, index, true)
        if not (spellID and item) then return false, "invalid" end
        local set = CustomContainerSpellSet(item)
        if set[spellID] ~= true then return false, "unchanged" end
        set[spellID] = nil
        if type(item.customSpellIDs) == "table" then item.customSpellIDs[spellID] = nil end
        local reminderItems = CustomContainerReminderItems(item, false)
        if reminderItems then reminderItems[spellID] = nil end
        local keepSpells = CustomContainerKeepSpells(item, false)
        if keepSpells then keepSpells[spellID] = nil end
        WriteCustomContainerSpellSet(item, set)
        if item.prioritySpellIDs ~= nil then ReconcileCustomContainerSpellPriority(item, false) end
        return true
    end

    function Model.ClearCustomContainerSpells(unit, index)
        local item = Model.CustomContainer(unit, index, true)
        if not item then return 0 end
        local count = 0
        for _, enabled in pairs(CustomContainerSpellSet(item)) do
            if enabled == true then count = count + 1 end
        end
        if count > 0 then WriteCustomContainerSpellSet(item, {}) end
        item.customSpellIDs = nil
        item.prioritySpellIDs = nil
        item.reminderItems = nil
        item.reminderKeepSpells = nil
        return count
    end

    --- Bind the consumable that a weapon-enchant reminder offers on click. A bare
    --- number is an item ID here: unlike the whitelist, this field has no spell
    --- meaning to be ambiguous with.
    function Model.SetCustomContainerReminderEnchantItem(unit, index, value)
        local item = Model.CustomContainer(unit, index, true)
        if not item then return false, "invalid" end
        local text = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            if item.reminderEnchantItem == nil then return false, "unchanged" end
            item.reminderEnchantItem = nil
            return true
        end
        local itemID = ItemIDFromInput(text) or tonumber(text:match("^(%d+)$"))
        if not itemID then return false, "invalid" end
        itemID = math_floor(itemID + 0.5)
        if item.reminderEnchantItem == itemID then return false, "unchanged" end
        item.reminderEnchantItem = itemID
        return true
    end

    function Model.CustomContainerReminderEnchantItem(unit, index)
        local item = Model.CustomContainer(unit, index, false)
        local itemID = item and tonumber(item.reminderEnchantItem) or nil
        if not itemID then return nil end
        local _, name, icon = Model.ItemInfo(itemID)
        return itemID, name, icon
    end

    function Model.CustomContainerSpellEntries(unit, index)
        local item = Model.CustomContainer(unit, index, false)
        local customSpellIDs = type(item and item.customSpellIDs) == "table" and item.customSpellIDs or nil
        local out, bySpellID = {}, {}
        local reminderItems = CustomContainerReminderItems(item, false)
        local keepSpells = CustomContainerKeepSpells(item, false)
        for spellID in pairs(CustomContainerSpellSet(item)) do
            local id, name, icon = SpellInfo(spellID)
            id = id or spellID
            -- A bound item owns the row's face: the reminder placeholder and the
            -- click both use the item, so the list has to show the same thing.
            local itemID = reminderItems and tonumber(reminderItems[id]) or nil
            local itemName, itemIcon
            if itemID then
                local _, resolvedName, resolvedIcon = Model.ItemInfo(itemID)
                itemName, itemIcon = resolvedName, resolvedIcon
                if resolvedIcon then icon = resolvedIcon end
            end
            local entry = {
                value = tostring(id), spellID = id, icon = icon,
                itemID = itemID, itemName = itemName, itemIcon = itemIcon,
                text = (type(itemName) == "string" and itemName ~= "" and itemName
                    or (type(name) == "string" and name ~= "" and name or "Spell"))
                    .. " (#" .. tostring(id) .. ")",
                customID = customSpellIDs and customSpellIDs[id] == true or false,
                clickAction = Model.ReminderClickAction(id, itemID),
                -- A bound item already proves the row is not class bound.
                keep = itemID ~= nil or (keepSpells ~= nil and keepSpells[id] == true),
                keepExplicit = keepSpells ~= nil and keepSpells[id] == true,
            }
            out[#out + 1] = entry
            bySpellID[id] = entry
        end
        table_sort(out, function(a, b) return tostring(a.text) < tostring(b.text) end)
        local priority = ReconcileCustomContainerSpellPriority(item, false)
        if #priority > 0 then
            local prioritized, used = {}, {}
            for i = 1, #priority do
                local entry = bySpellID[priority[i]]
                if entry then prioritized[#prioritized + 1] = entry; used[entry] = true end
            end
            for i = 1, #out do
                if not used[out[i]] then prioritized[#prioritized + 1] = out[i] end
            end
            out = prioritized
        end
        for i = 1, #out do out[i].priority = i end
        return out
    end

    --- Entries the runtime would actually track for a custom container, for 1:1
    --- previews. The target-dot container mirrors the runtime include filter: only
    --- curated dot IDs plus explicitly allowed custom IDs survive. Empty means
    --- empty - previews outside edit mode render nothing for this container.
    local function AppendReminderEnchantPreviewEntries(unit, index, entries)
        if unit ~= "player" or index >= PLAYER_DEFENSIVE_CONTAINER_INDEX then return entries end
        local item = Model.CustomContainer(unit, index, false)
        local placed = type(item and item.placed) == "table" and item.placed or nil
        if not (item and placed and placed.reminderEnabled == true) then return entries end
        local cap = math_floor(ClampNumber(placed.max, 8, 0, 40))
        if #entries >= cap then return entries end

        local itemID, itemName, icon = Model.CustomContainerReminderEnchantItem(unit, index)
        icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        local function Append(enabled, token, label)
            if enabled ~= true or #entries >= cap then return end
            entries[#entries + 1] = {
                value = "enchant:" .. token,
                enchantSlot = token,
                itemID = itemID,
                itemName = itemName,
                itemIcon = icon,
                icon = icon,
                text = label .. (itemName and (" - " .. itemName) or ""),
                clickAction = itemID and ("item:" .. tostring(itemID)) or nil,
                keep = true,
            }
        end
        Append(item.reminderEnchantMainHand, "MAINHAND", "Main Hand")
        Append(item.reminderEnchantOffHand, "OFFHAND", "Off Hand")
        return entries
    end

    function Model.CustomContainerPreviewEntries(unit, index)
        unit = NormalizeScope(unit)
        if unit == "shared" then unit = "player" end
        index = math_floor(ClampNumber(index, 1, 1, CUSTOM_CONTAINER_MAX))
        local entries = Model.CustomContainerSpellEntries(unit, index)
        entries = AppendReminderEnchantPreviewEntries(unit, index, entries)
        if unit == "player" and index == PLAYER_DEFENSIVE_CONTAINER_INDEX then
            local out, seen = {}, {}
            local builtins = type(Model.PlayerDefensivePreviewEntries) == "function"
                and Model.PlayerDefensivePreviewEntries() or {}
            for i = 1, #builtins do
                local entry = builtins[i]
                if entry and entry.spellID then
                    seen[entry.spellID] = true
                    out[#out + 1] = entry
                end
            end
            for i = 1, #entries do
                local entry = entries[i]
                if entry and entry.spellID and not seen[entry.spellID] then
                    seen[entry.spellID] = true
                    out[#out + 1] = entry
                end
            end
            return out
        end
        if index ~= TARGET_DOT_CONTAINER_INDEX or #entries == 0 then return entries end
        local out = {}
        for i = 1, #entries do
            local entry = entries[i]
            if entry.customID == true or Model.IsTargetDotSpell(entry.spellID) then
                out[#out + 1] = entry
            end
        end
        return out
    end

    local TARGET_DOT_CLASS_ORDER = {
        "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
        "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
    }
    local TARGET_DOT_CLASS_LABELS = {
        DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter", DRUID = "Druid",
        EVOKER = "Evoker", HUNTER = "Hunter", MAGE = "Mage", MONK = "Monk",
        PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue", SHAMAN = "Shaman",
        WARLOCK = "Warlock", WARRIOR = "Warrior",
    }

    local function TargetDotLookup()
        local lookup = A3._targetDotLookup
        if lookup then return lookup end
        lookup = {}
        for _, spells in pairs(A3.TargetDotData or {}) do
            for i = 1, #spells do lookup[tonumber(spells[i][1])] = true end
        end
        A3._targetDotLookup = lookup
        return lookup
    end

    function Model.IsTargetDotSpell(value)
        local spellID = SpellIDFromInput(value)
        return spellID and TargetDotLookup()[spellID] == true or false
    end

    function Model.TargetDotValues()
        local values = {}
        local playerClass
        if type(UnitClass) == "function" then local _; _, playerClass = UnitClass("player") end
        local order = {}
        if playerClass and A3.TargetDotData and A3.TargetDotData[playerClass] then order[#order + 1] = playerClass end
        for i = 1, #TARGET_DOT_CLASS_ORDER do
            local class = TARGET_DOT_CLASS_ORDER[i]
            if class ~= playerClass then order[#order + 1] = class end
        end
        for i = 1, #order do
            local class = order[i]
            local spells = A3.TargetDotData and A3.TargetDotData[class]
            if type(spells) == "table" and #spells > 0 then
                values[#values + 1] = { text = TARGET_DOT_CLASS_LABELS[class] or class, header = true, disabled = true, translate = false }
                for j = 1, #spells do
                    local spellID, fallback = tonumber(spells[j][1]), spells[j][2]
                    local id, name, icon = SpellInfo(spellID)
                    values[#values + 1] = {
                        value = tostring(id or spellID), spellID = id or spellID, icon = icon,
                        text = (type(name) == "string" and name ~= "" and name or fallback or "Spell") .. " (#" .. tostring(id or spellID) .. ")",
                        class = class,
                    }
                end
            end
        end
        return values
    end

    local function PlayerDefensiveLookup()
        local lookup = A3._playerDefensiveLookup
        if lookup then return lookup end
        lookup = {}
        for _, spells in pairs(A3.PlayerDefensiveData or {}) do
            for i = 1, #spells do lookup[tonumber(spells[i][1])] = true end
        end
        A3._playerDefensiveLookup = lookup
        return lookup
    end

    function Model.IsPlayerDefensiveSpell(value)
        local spellID = SpellIDFromInput(value)
        return spellID and PlayerDefensiveLookup()[spellID] == true or false
    end

    local function PlayerClassToken()
        if type(UnitClass) == "function" then
            local _, class = UnitClass("player")
            if type(class) == "string" and class ~= "" then return class end
        end
    end

    local function DefensiveEntry(spellID, fallback, class)
        local id, name, icon = SpellInfo(spellID)
        id = id or spellID
        return {
            value = tostring(id), spellID = id, icon = icon,
            text = (type(name) == "string" and name ~= "" and name or fallback or "Spell")
                .. " (#" .. tostring(id) .. ")",
            class = class,
            predefined = true,
        }
    end

    local function PlayerDefensiveDisabledSet(unit, create)
        local item = Model.CustomContainer(unit or "player", PLAYER_DEFENSIVE_CONTAINER_INDEX, create == true)
        if not item then return nil end
        local disabled = item.disabledPredefinedSpellIDs
        if type(disabled) ~= "table" and create == true then
            disabled = {}
            item.disabledPredefinedSpellIDs = disabled
        end
        return type(disabled) == "table" and disabled or nil
    end

    function Model.PlayerDefensiveSpellEnabled(unit, value)
        local spellID = SpellIDFromInput(value)
        if not (spellID and PlayerDefensiveLookup()[spellID] == true) then return false end
        local disabled = PlayerDefensiveDisabledSet(unit, false)
        return not (disabled and (disabled[spellID] == true or disabled[tostring(spellID)] == true))
    end

    function Model.SetPlayerDefensiveSpellEnabled(unit, value, enabled)
        local spellID = SpellIDFromInput(value)
        if not (spellID and PlayerDefensiveLookup()[spellID] == true) then return false, "invalid" end
        local disabled = PlayerDefensiveDisabledSet(unit, true)
        local wasEnabled = not (disabled[spellID] == true or disabled[tostring(spellID)] == true)
        enabled = enabled == true
        if wasEnabled == enabled then return false, "unchanged" end
        if enabled then
            disabled[spellID] = nil
        else
            disabled[spellID] = true
        end
        disabled[tostring(spellID)] = nil
        return true
    end

    function Model.PlayerDefensiveClassEntries(includeDisabled)
        local class = PlayerClassToken()
        local spells = class and A3.PlayerDefensiveData and A3.PlayerDefensiveData[class]
        local out = {}
        if type(spells) ~= "table" then return out end
        for i = 1, #spells do
            local entry = DefensiveEntry(tonumber(spells[i][1]), spells[i][2], class)
            entry.enabled = Model.PlayerDefensiveSpellEnabled("player", entry.spellID)
            if includeDisabled == true or entry.enabled then out[#out + 1] = entry end
        end
        return out
    end

    function Model.PlayerDefensiveValues()
        local values, playerClass, order = {}, PlayerClassToken(), {}
        if playerClass and A3.PlayerDefensiveData and A3.PlayerDefensiveData[playerClass] then
            order[#order + 1] = playerClass
        end
        for i = 1, #TARGET_DOT_CLASS_ORDER do
            local class = TARGET_DOT_CLASS_ORDER[i]
            if class ~= playerClass then order[#order + 1] = class end
        end
        for i = 1, #order do
            local class = order[i]
            local spells = A3.PlayerDefensiveData and A3.PlayerDefensiveData[class]
            if type(spells) == "table" and #spells > 0 then
                values[#values + 1] = {
                    text = TARGET_DOT_CLASS_LABELS[class] or class,
                    header = true, disabled = true, translate = false,
                }
                for j = 1, #spells do
                    values[#values + 1] = DefensiveEntry(tonumber(spells[j][1]), spells[j][2], class)
                end
            end
        end
        return values
    end

    function Model.PlayerDefensivePreviewEntries()
        return Model.PlayerDefensiveClassEntries(false)
    end

end
