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
        { "^what%s+affects%s+(.+)$", "explain" },
        { "^what%s+does%s+(.+)%s+affect$", "explain" },
        { "^what%s+depends%s+on%s+(.+)$", "explain" },
        { "^what%s+requires%s+(.+)$", "explain" },
        { "^what%s+is%s+required%s+for%s+(.+)$", "diagnose" },
        { "^explain%s+dependencies%s+for%s+(.+)$", "explain" },
        { "^explain%s+dependencies%s+of%s+(.+)$", "explain" },
        { "^related%s+settings%s+for%s+(.+)$", "explain" },
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

local function EdgeLabels(edges, keyField, limit)
    local out, seen = {}, {}
    for i = 1, #(edges or {}) do
        local edge = edges[i]
        local key = tostring(edge and edge[keyField] or "")
        local related = A.Registry and type(A.Registry.GetSetting) == "function" and A.Registry:GetSetting(key) or nil
        local label = tostring(related and related.label or key)
        if label ~= "" and not seen[label] then
            seen[label] = true
            out[#out + 1] = label
            if #out >= (tonumber(limit) or 6) then break end
        end
    end
    return out
end

function A.RouterTrySettingGraphShortcut(text)
    if type(A.ExplainSettingDependencies) ~= "function" then return nil end
    local norm = R.Normalize and R.Normalize(text) or tostring(text or ""):lower()
    local subject, mode = SubjectAndMode(norm)
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

    local entries = R.RegistrySettingSearchEntries(subject, norm, 8)
    local top = entries and entries[1]
    local item = top and top.item
    local setting = item and item.setting
    local key = tostring(setting and setting.key or item and (item.settingKey or item.key) or "")
    if key == "" or (tonumber(top.rawScore) or 0) < 220 then
        return {
            text = "I need the exact MSUF setting before I can explain its relationships. Name the frame and option, for example: 'why is Target Buffs disabled?'",
            status = "info",
            result = "info",
            summary = "Assistant setting relationship clarification",
        }
    end

    local explanation = mode == "diagnose" and A.DiagnoseSettingDependencies(key) or A.ExplainSettingDependencies(key)
    if type(explanation) ~= "table" then return nil end
    local lines = {
        tostring(explanation.label or item.label or key) .. " relationships",
        tostring(explanation.text or "No relationship explanation is available."),
    }
    local requires = EdgeLabels(explanation.dependencies, "to", 6)
    local affects = EdgeLabels(explanation.dependents, "from", 6)
    if #requires > 0 then lines[#lines + 1] = "Depends on: " .. table.concat(requires, ", ") .. "." end
    if #affects > 0 then lines[#lines + 1] = "Can affect: " .. table.concat(affects, ", ") .. "." end
    lines[#lines + 1] = "I only inspected current MSUF state; I did not change a setting."
    return {
        text = table.concat(lines, "\n"),
        status = "info",
        result = "info",
        summary = "Assistant setting relationship explanation",
        searchResults = R.RegistryLocationResultFollowups({ top }, 1),
    }
end
