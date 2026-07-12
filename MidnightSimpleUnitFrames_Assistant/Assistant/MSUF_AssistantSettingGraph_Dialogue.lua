--- Read-only natural-language bridge for the setting dependency graph.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
local A = MSUF.Assistant or {}
MSUF.Assistant, M.Assistant = A, A
local R = A.RouterPrivate or {}
A.RouterPrivate = R

local function SubjectAndMode(norm)
    local patterns = {
        { "^what%s+settings%s+depend%s+on%s+(.+)$", "explain" },
        { "^which%s+settings%s+depend%s+on%s+(.+)$", "explain" },
        { "^what%s+settings%s+does%s+(.+)%s+depend%s+on$", "explain" },
        { "^what%s+does%s+(.+)%s+depend%s+on$", "explain" },
        { "^what%s+changes%s+if%s+i%s+disable%s+(.+)$", "explain" },
        { "^what%s+happens%s+if%s+i%s+turn%s+off%s+(.+)$", "explain" },
        { "^what%s+happens%s+if%s+we%s+turn%s+off%s+(.+)$", "explain" },
        { "^what%s+happens%s+if%s+i%s+disable%s+(.+)$", "explain" },
        { "^what%s+breaks%s+if%s+i%s+turn%s+off%s+(.+)$", "explain" },
        { "^what%s+breaks%s+if%s+i%s+disable%s+(.+)$", "explain" },
        { "^what%s+breaks%s+if%s+(.+)%s+is%s+off$", "explain" },
        { "^what%s+stops%s+working%s+if%s+i%s+disable%s+(.+)$", "explain" },
        { "^what%s+affects%s+(.+)$", "explain" },
        { "^what%s+does%s+(.+)%s+affect$", "explain" },
        { "^what%s+depends%s+on%s+(.+)$", "explain" },
        { "^what%s+requires%s+(.+)$", "explain" },
        { "^what%s+is%s+required%s+for%s+(.+)$", "diagnose" },
        { "^explain%s+dependencies%s+for%s+(.+)$", "explain" },
        { "^explain%s+dependencies%s+of%s+(.+)$", "explain" },
        { "^explain%s+(.+)%s+dependencies$", "explain" },
        { "^show%s+dependencies%s+for%s+(.+)$", "explain" },
        { "^show%s+dependencies%s+of%s+(.+)$", "explain" },
        { "^related%s+settings%s+for%s+(.+)$", "explain" },
        { "^show%s+related%s+settings%s+for%s+(.+)$", "explain" },
        { "^list%s+related%s+settings%s+for%s+(.+)$", "explain" },
        { "^show%s+relationships%s+for%s+(.+)$", "explain" },
        { "^explain%s+relationships%s+for%s+(.+)$", "explain" },
        { "^show%s+connections%s+for%s+(.+)$", "explain" },
        { "^what%s+is%s+related%s+to%s+(.+)$", "explain" },
        { "^how%s+is%s+(.+)%s+connected%s+to%s+other%s+settings$", "explain" },
        { "^how%s+is%s+(.+)%s+connected$", "explain" },
        { "^why%s+is%s+(.+)%s+disabled$", "diagnose" },
        { "^why%s+is%s+(.+)%s+hidden$", "diagnose" },
        { "^why%s+is%s+(.+)%s+unavailable$", "diagnose" },
        { "^why%s+cant%s+i%s+change%s+(.+)$", "diagnose" },
        { "^why%s+can't%s+i%s+change%s+(.+)$", "diagnose" },
        { "^warum%s+ist%s+(.+)%s+deaktiviert$", "diagnose" },
        { "^warum%s+ist%s+(.+)%s+versteckt$", "diagnose" },
        { "^warum%s+kann%s+ich%s+(.+)%s+nicht%s+aendern$", "diagnose" },
        { "^was%s+beeinflusst%s+(.+)$", "explain" },
        { "^was%s+haengt%s+von%s+(.+)%s+ab$", "explain" },
        { "^welche%s+einstellungen%s+haengen%s+mit%s+(.+)%s+zusammen$", "explain" },
    }
    for i = 1, #patterns do
        local subject = norm:match(patterns[i][1])
        if subject and subject ~= "" then return subject, patterns[i][2] end
    end
    return nil
end

local function ActiveRelationshipChoice()
    local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
    local choice = type(ctx) == "table" and ctx.relationshipChoice or nil
    local currentTurn = tonumber(ctx and (ctx.turnSerial or ctx.lastTurnSerial)) or 0
    if type(choice) == "table" and currentTurn > (tonumber(choice.turn) or 0) + 1 then
        ctx.relationshipChoice = nil
        choice = nil
    end
    return choice, ctx, currentTurn
end

function A.RouterLooksLikeExplicitSettingRelationshipRequest(text)
    local norm = R.Normalize and R.Normalize(text) or tostring(text or ""):lower()
    local choice = ActiveRelationshipChoice()
    local choiceIndex = tonumber(norm:match("^(%d+)$") or norm:match("^option%s+(%d+)$")
        or norm:match("^result%s+(%d+)$") or norm:match("^choice%s+(%d+)$"))
    return SubjectAndMode(norm) ~= nil
        or (choiceIndex ~= nil and type(choice) == "table" and type(choice.keys) == "table" and choice.keys[choiceIndex] ~= nil)
        or norm == "more related settings" or norm == "show more related settings"
        or norm == "next related settings" or norm == "more relationships"
        or norm == "show more relationships"
end

local function DirectScopeRootItem(subject)
    if type(R.RegistrySettingItemForKey) ~= "function" then return nil end
    local norm = R.Normalize and R.Normalize(subject) or tostring(subject or ""):lower()
    norm = norm:gsub("^the%s+", ""):gsub("%s+setting$", ""):gsub("%s+toggle$", "")
    local roots = {
        ["player"] = "player.enabled", ["player frame"] = "player.enabled", ["player frame enabled"] = "player.enabled", ["player unit frame"] = "player.enabled", ["player unit frame enabled"] = "player.enabled", ["my frame"] = "player.enabled", ["self frame"] = "player.enabled",
        ["target"] = "target.enabled", ["target frame"] = "target.enabled", ["target frame enabled"] = "target.enabled", ["target unit frame"] = "target.enabled", ["target unit frame enabled"] = "target.enabled",
        ["focus"] = "focus.enabled", ["focus frame"] = "focus.enabled", ["focus frame enabled"] = "focus.enabled", ["focus unit frame"] = "focus.enabled", ["focus unit frame enabled"] = "focus.enabled",
        ["pet"] = "pet.enabled", ["pet frame"] = "pet.enabled", ["pet frame enabled"] = "pet.enabled", ["pet unit frame"] = "pet.enabled", ["pet unit frame enabled"] = "pet.enabled",
        ["boss"] = "boss.enabled", ["boss frame"] = "boss.enabled", ["boss frames"] = "boss.enabled", ["boss frame enabled"] = "boss.enabled", ["boss unit frame"] = "boss.enabled", ["boss unit frames"] = "boss.enabled",
        ["target of target"] = "targettarget.enabled", ["target of target frame"] = "targettarget.enabled", ["target of target frame enabled"] = "targettarget.enabled",
        ["focus target"] = "focustarget.enabled", ["focus target frame"] = "focustarget.enabled", ["focus target frame enabled"] = "focustarget.enabled",
        ["targettarget"] = "targettarget.enabled", ["targettarget frame"] = "targettarget.enabled", ["targettarget frame enabled"] = "targettarget.enabled",
        ["focustarget"] = "focustarget.enabled", ["focustarget frame"] = "focustarget.enabled", ["focustarget frame enabled"] = "focustarget.enabled",
        ["party"] = "gf_party.enabled", ["party frame"] = "gf_party.enabled", ["party frames"] = "gf_party.enabled", ["party frames enabled"] = "gf_party.enabled",
        ["raid"] = "gf_raid.enabled", ["raid frame"] = "gf_raid.enabled", ["raid frames"] = "gf_raid.enabled", ["raid frames enabled"] = "gf_raid.enabled",
        ["mythic raid"] = "gf_mythicraid.enabled", ["mythic raid frame"] = "gf_mythicraid.enabled", ["mythic raid frames"] = "gf_mythicraid.enabled", ["mythic raid frames enabled"] = "gf_mythicraid.enabled",
        ["mythicraid"] = "gf_mythicraid.enabled", ["mythicraid frame"] = "gf_mythicraid.enabled", ["mythicraid frames"] = "gf_mythicraid.enabled",
    }
    local key = roots[norm]
    return key and R.RegistrySettingItemForKey(key) or nil
end

local function DirectGroupRootEntries(subject)
    local norm = R.Normalize and R.Normalize(subject) or tostring(subject or ""):lower()
    norm = norm:gsub("^the%s+", ""):gsub("%s+enabled$", "")
    if norm ~= "group" and norm ~= "group frame" and norm ~= "group frames" then return nil end
    local entries = {}
    for _, key in ipairs({ "gf_party.enabled", "gf_raid.enabled", "gf_mythicraid.enabled" }) do
        local item = type(R.RegistrySettingItemForKey) == "function" and R.RegistrySettingItemForKey(key) or nil
        if item then entries[#entries + 1] = { item = item, score = 10000, rawScore = 10000 } end
    end
    return #entries > 0 and entries or nil
end

local RUNTIME_DEPENDENCY_KINDS = {
    enablement = true,
    visibility = true,
    availability = true,
    requires = true,
}

local function EdgeItems(sources, kinds, limit)
    local labels, keys, seen, total = {}, {}, {}, 0
    limit = tonumber(limit) or 6
    for _, source in ipairs(sources or {}) do
        for i = 1, #(source.edges or {}) do
            local edge = source.edges[i]
            if not kinds or kinds[tostring(edge and edge.kind or "")] then
                local key = tostring(edge and edge[source.keyField] or "")
                local related = A.Registry and type(A.Registry.GetSetting) == "function" and A.Registry:GetSetting(key) or nil
                local label = tostring(related and related.label or key)
                if key ~= "" and label ~= "" and not seen[key] then
                    seen[key] = true
                    total = total + 1
                    if #labels < limit then
                        labels[#labels + 1] = label
                        keys[#keys + 1] = key
                    end
                end
            end
        end
    end
    return labels, keys, total
end

local RELATION_CATEGORY_LABELS = {
    requires = "Depends on", affects = "Can affect", inherits = "Inherits from",
    inheritedBy = "Shared with", overrideControls = "Override control",
    controlsOverrides = "Controls overrides for", conflicts = "Conflicts with",
    related = "Related options in the same MSUF section",
}

local function RelationshipCategoryItems(explanation, category, limit)
    local dependencies = explanation and explanation.dependencies or {}
    local dependents = explanation and explanation.dependents or {}
    if category == "requires" then
        return EdgeItems({ { edges = dependencies, keyField = "to" } }, RUNTIME_DEPENDENCY_KINDS, limit)
    elseif category == "affects" then
        return EdgeItems({ { edges = dependents, keyField = "from" } }, RUNTIME_DEPENDENCY_KINDS, limit)
    elseif category == "inherits" then
        return EdgeItems({ { edges = dependencies, keyField = "to" } }, { inheritance = true }, limit)
    elseif category == "inheritedBy" then
        return EdgeItems({ { edges = dependents, keyField = "from" } }, { inheritance = true }, limit)
    elseif category == "overrideControls" then
        return EdgeItems({ { edges = dependencies, keyField = "to" } }, { override = true }, limit)
    elseif category == "controlsOverrides" then
        return EdgeItems({ { edges = dependents, keyField = "from" } }, { override = true }, limit)
    elseif category == "conflicts" then
        return EdgeItems({
            { edges = dependencies, keyField = "to" },
            { edges = dependents, keyField = "from" },
        }, { conflict = true }, limit)
    elseif category == "related" then
        return EdgeItems({
            { edges = dependencies, keyField = "to" },
            { edges = dependents, keyField = "from" },
        }, { association = true }, limit)
    end
    return {}, {}, 0
end

local function RelationshipMoreReply(norm)
    if not (norm == "more related settings" or norm == "show more related settings"
        or norm == "next related settings" or norm == "more relationships"
        or norm == "show more relationships")
    then
        return nil
    end
    local ctx = type(A.GetContext) == "function" and A.GetContext() or nil
    local browser = type(ctx) == "table" and ctx.relationshipBrowser or nil
    if type(browser) ~= "table" then return nil end
    local key, category = tostring(browser.key or ""), tostring(browser.category or "")
    local explanation = type(A.ExplainSettingDependencies) == "function" and A.ExplainSettingDependencies(key) or nil
    if type(explanation) ~= "table" then return nil end
    local labels, keys, total = RelationshipCategoryItems(explanation, category, math.huge)
    local first = math.max(1, tonumber(browser.nextOffset) or 1)
    if first > total then
        ctx.relationshipBrowser = nil
        return {
            text = "That was the end of the " .. tostring(RELATION_CATEGORY_LABELS[category] or "related") .. " settings list.",
            status = "info",
            summary = "Assistant relationship pagination complete",
        }
    end
    local last = math.min(total, first + 7)
    local lines = {
        tostring(explanation.label or key) .. " — " .. tostring(RELATION_CATEGORY_LABELS[category] or "Related") .. " settings",
        tostring(first) .. "-" .. tostring(last) .. " of " .. tostring(total),
    }
    local followups = {}
    for index = first, last do
        local pageIndex = index - first + 1
        lines[#lines + 1] = tostring(pageIndex) .. ". " .. tostring(labels[index] or keys[index])
        local item = type(R.RegistrySettingItemForKey) == "function" and R.RegistrySettingItemForKey(keys[index]) or nil
        if item then followups[#followups + 1] = { item = item } end
    end
    lines[#lines + 1] = "Reply with a number from this page to open or explain that setting."
    browser.nextOffset = last + 1
    if last < total then
        lines[#lines + 1] = "Say 'more related settings' for the next page."
    else
        lines[#lines + 1] = "That is the end of this relationship list."
    end
    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant paginated setting relationships",
        searchResults = R.RegistryLocationResultFollowups(followups, #followups),
    }
end

function A.RouterTrySettingGraphShortcut(text)
    if type(A.ExplainSettingDependencies) ~= "function" then return nil end
    local norm = R.Normalize and R.Normalize(text) or tostring(text or ""):lower()
    local moreReply = RelationshipMoreReply(norm)
    if moreReply then return moreReply end
    local relationshipChoice, ctx, currentTurn = ActiveRelationshipChoice()
    local choiceIndex = tonumber(norm:match("^(%d+)$") or norm:match("^option%s+(%d+)$")
        or norm:match("^result%s+(%d+)$") or norm:match("^choice%s+(%d+)$"))
    local selectedChoiceKey = choiceIndex and type(relationshipChoice) == "table"
        and type(relationshipChoice.keys) == "table" and relationshipChoice.keys[choiceIndex] or nil
    local subject, mode = SubjectAndMode(norm)
    if selectedChoiceKey then
        subject = selectedChoiceKey
        mode = tostring(relationshipChoice.mode or "explain")
        ctx.relationshipChoice = nil
    end
    if not subject then return nil end
    if (norm:match("%s+hidden$") or norm:match("%s+versteckt$"))
        and not (R.ContainsAny and R.ContainsAny(subject, {
            "setting", "option", "control", "toggle", "checkbox", "slider", "dropdown", "button",
            "einstellung", "option", "steuerung", "schalter", "regler", "auswahl", "knopf",
        }))
    then
        -- "Why is Target Cast Bar hidden?" describes runtime visibility and
        -- belongs to the diagnostic specialists. Graph diagnosis is for a
        -- hidden menu control/setting and must not pre-empt that answer.
        return nil
    end
    if not (R.RegistrySettingSearchEntries and R.RegistryLocationResultFollowups) then return nil end

    local selectedItem = selectedChoiceKey and type(R.RegistrySettingItemForKey) == "function"
        and R.RegistrySettingItemForKey(selectedChoiceKey) or nil
    local directItems = not selectedItem and DirectGroupRootEntries(subject) or nil
    local directItem = not selectedItem and not directItems and DirectScopeRootItem(subject) or nil
    local entries = selectedItem and { { item = selectedItem, score = 10000, rawScore = 10000 } }
        or directItems or (directItem and { { item = directItem, score = 10000, rawScore = 10000 } })
        or R.RegistrySettingSearchEntries(subject, norm, 8)
    local top = entries and entries[1]
    local item = top and top.item
    local setting = item and item.setting
    local key = tostring(setting and setting.key or item and (item.settingKey or item.key) or "")
    local topScore = tonumber(top and (top.score or top.rawScore)) or 0
    local nextScore = tonumber(entries and entries[2] and (entries[2].score or entries[2].rawScore))
    local uncertainTie = nextScore ~= nil and (topScore - nextScore) < 40
    if key == "" or (tonumber(top.rawScore) or 0) < 220 or uncertainTie then
        local visible = math.min(3, #(entries or {}))
        if visible > 0 then
            local lines = { "I'm not confident which MSUF setting you mean. Pick the closest option:" }
            for i = 1, visible do
                lines[#lines + 1] = tostring(i) .. ". " .. tostring(entries[i].item and entries[i].item.label or "MSUF setting")
            end
            lines[#lines + 1] = "Reply with its number. I will explain it without changing anything."
            if type(ctx) == "table" then
                local keys = {}
                for i = 1, visible do
                    local candidate = entries[i] and entries[i].item
                    keys[i] = candidate and (candidate.settingKey or candidate.key or (candidate.setting and candidate.setting.key)) or nil
                end
                ctx.relationshipChoice = { mode = mode, keys = keys, turn = currentTurn }
            end
            return {
                text = table.concat(lines, "\n"),
                status = "ambiguous",
                result = "ambiguous",
                summary = "Assistant setting relationship choices",
                searchResults = R.RegistryLocationResultFollowups(entries, visible),
            }
        end
        return {
            text = "I need the exact MSUF setting before I can explain its relationships. Name the frame and option, for example: 'why is Target Buffs disabled?' You can also ask me to list the settings on the current page.",
            status = "info",
            result = "info",
            summary = "Assistant setting relationship clarification",
        }
    end

    local explanation = mode == "diagnose" and A.DiagnoseSettingDependencies(key) or A.ExplainSettingDependencies(key)
    if type(explanation) ~= "table" then return nil end
    if type(ctx) == "table" then ctx.relationshipChoice = nil end
    local lines = {
        tostring(explanation.label or item.label or key) .. " relationships",
        tostring(explanation.text or "No relationship explanation is available."),
    }
    local dependencies = explanation.dependencies or {}
    local dependents = explanation.dependents or {}
    local requires, requireKeys, requiresTotal = EdgeItems({ { edges = dependencies, keyField = "to" } }, RUNTIME_DEPENDENCY_KINDS, 6)
    local affects, affectKeys, affectsTotal = EdgeItems({ { edges = dependents, keyField = "from" } }, RUNTIME_DEPENDENCY_KINDS, 6)
    local inherits, inheritKeys, inheritsTotal = EdgeItems({ { edges = dependencies, keyField = "to" } }, { inheritance = true }, 6)
    local inheritedBy, inheritedByKeys, inheritedByTotal = EdgeItems({ { edges = dependents, keyField = "from" } }, { inheritance = true }, 6)
    local overrideControls, overrideKeys, overrideControlsTotal = EdgeItems({ { edges = dependencies, keyField = "to" } }, { override = true }, 6)
    local controlsOverrides, controlsOverrideKeys, controlsOverridesTotal = EdgeItems({ { edges = dependents, keyField = "from" } }, { override = true }, 6)
    local conflicts, conflictKeys, conflictsTotal = EdgeItems({
        { edges = dependencies, keyField = "to" },
        { edges = dependents, keyField = "from" },
    }, { conflict = true }, 6)
    local related, relatedKeys, relatedTotal = EdgeItems({
        { edges = dependencies, keyField = "to" },
        { edges = dependents, keyField = "from" },
    }, { association = true }, 6)
    local overflow
    local function AddRelationLine(category, values, total)
        if #values == 0 then return end
        local label = RELATION_CATEGORY_LABELS[category]
        local line = tostring(label) .. ": " .. table.concat(values, ", ") .. "."
        if total > #values then
            line = line .. " Showing " .. tostring(#values) .. " of " .. tostring(total) .. "."
            overflow = overflow or { category = category, total = total, nextOffset = #values + 1 }
        end
        lines[#lines + 1] = line
    end
    AddRelationLine("requires", requires, requiresTotal)
    AddRelationLine("affects", affects, affectsTotal)
    AddRelationLine("inherits", inherits, inheritsTotal)
    AddRelationLine("inheritedBy", inheritedBy, inheritedByTotal)
    AddRelationLine("overrideControls", overrideControls, overrideControlsTotal)
    AddRelationLine("controlsOverrides", controlsOverrides, controlsOverridesTotal)
    AddRelationLine("conflicts", conflicts, conflictsTotal)
    AddRelationLine("related", related, relatedTotal)
    if type(ctx) == "table" then
        if overflow then
            overflow.key = key
            ctx.relationshipBrowser = overflow
            lines[#lines + 1] = "Say 'more related settings' to page through the remaining "
                .. tostring(RELATION_CATEGORY_LABELS[overflow.category] or "related") .. " options."
        else
            ctx.relationshipBrowser = nil
        end
    end
    if #requires == 0 and #affects == 0 and #inherits == 0 and #inheritedBy == 0
        and #overrideControls == 0 and #controlsOverrides == 0 and #conflicts == 0 and #related == 0
    then
        lines[#lines + 1] = "No other registered MSUF setting directly controls this option."
    end
    lines[#lines + 1] = "I only inspected current MSUF state; I did not change a setting."

    local followupEntries = { { item = item } }
    local followupSeen = { [key] = true }
    local function AddFollowups(keys)
        for _, relatedKey in ipairs(keys or {}) do
            if #followupEntries >= 5 then return end
            if not followupSeen[relatedKey] and type(R.RegistrySettingItemForKey) == "function" then
                local relatedItem = R.RegistrySettingItemForKey(relatedKey)
                if relatedItem then
                    followupSeen[relatedKey] = true
                    followupEntries[#followupEntries + 1] = { item = relatedItem }
                end
            end
        end
    end
    AddFollowups(requireKeys)
    AddFollowups(affectKeys)
    AddFollowups(inheritKeys)
    AddFollowups(inheritedByKeys)
    AddFollowups(overrideKeys)
    AddFollowups(controlsOverrideKeys)
    AddFollowups(conflictKeys)
    AddFollowups(relatedKeys)
    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant setting relationship explanation",
        searchResults = R.RegistryLocationResultFollowups(followupEntries, #followupEntries),
    }
end
