-- Assistant ClassPower preview registry.
-- Isolates preview aliases and menu state from saved class-resource settings.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local C = A.RegistryCore
if type(C) ~= "table" then return end

local Registry = C.Registry
local CallGlobal = C.CallGlobal

local ClassPowerData = A.ClassPowerRegistryData
if type(ClassPowerData) ~= "table" then return end

local CLASS_POWER_PREVIEW_VALUES = ClassPowerData.CLASS_POWER_PREVIEW_VALUES or {}
local CLASS_POWER_PREVIEW_LABELS = ClassPowerData.CLASS_POWER_PREVIEW_LABELS or {}
local CLASS_POWER_PREVIEW_ALIASES = ClassPowerData.CLASS_POWER_PREVIEW_ALIASES or {}

local function ClassPowerPreviewValueAliases()
    local aliases = {}
    for i = 1, #CLASS_POWER_PREVIEW_VALUES do
        local key = CLASS_POWER_PREVIEW_VALUES[i]
        aliases[key] = key
        aliases[(CLASS_POWER_PREVIEW_LABELS[key] or key):lower()] = key
        aliases[(CLASS_POWER_PREVIEW_LABELS[key] or key):lower():gsub("%s*%-%s*", " ")] = key
        aliases[key:gsub("_", " ")] = key
    end
    for alias, key in pairs(CLASS_POWER_PREVIEW_ALIASES) do aliases[alias] = key end
    return aliases
end

local function ClassPowerPreviewExactAliases()
    local out = {
        "class resource preview resource",
        "class resource preview",
        "class resources preview",
        "class power preview resource",
        "class power preview",
        "preview class resource",
        "preview class resources",
        "preview class power",
        "preview class bar",
        "preview resource",
        "resource preview",
        "set class resource preview",
        "set class resources preview",
        "set preview resource",
    }
    local seen = {}
    for i = 1, #out do seen[out[i]] = true end
    local aliases = ClassPowerPreviewValueAliases()
    for alias in pairs(aliases) do
        alias = tostring(alias or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if alias ~= "" then
            local variants = {
                "preview " .. alias,
                "preview " .. alias .. " class resource",
                "preview " .. alias .. " class resources",
                "show " .. alias .. " class resource preview",
            }
            for i = 1, #variants do
                local value = variants[i]
                if not seen[value] then
                    seen[value] = true
                    out[#out + 1] = value
                end
            end
        end
    end
    return out
end

local function NormalizeClassPowerPreviewKey(key)
    key = tostring(key or "rogue_combo")
    for i = 1, #CLASS_POWER_PREVIEW_VALUES do
        if CLASS_POWER_PREVIEW_VALUES[i] == key then return key end
    end
    return "rogue_combo"
end

local function ClassPowerPreviewActionTextHas(compact, hay, terms)
    for i = 1, #(terms or {}) do
        local term = tostring(terms[i] or ""):lower()
        local compactTerm = term:gsub("[^%w]+", "")
        if compactTerm ~= "" and compact:find(compactTerm, 1, true) then return true end
        local phrase = term:gsub("[^%w]+", " ")
        phrase = phrase:gsub("^%s+", ""):gsub("%s+$", "")
        if phrase ~= "" and hay:find(" " .. phrase .. " ", 1, true) then return true end
    end
    return false
end

local function ParseClassPowerPreviewAnimationAliasArgs(text)
    local lower = tostring(text or ""):lower()
    local compact = lower:gsub("[^%w]+", "")
    local hay = " " .. lower:gsub("[^%w]+", " ") .. " "
    local value
    if ClassPowerPreviewActionTextHas(compact, hay, { "toggle", "switch", "umschalten" }) then
        value = nil
    elseif ClassPowerPreviewActionTextHas(compact, hay, { "stop", "pause", "off", "disable", "turn off" }) then
        value = false
    elseif ClassPowerPreviewActionTextHas(compact, hay, { "start", "play", "animate", "on", "enable", "turn on" }) then
        value = true
    end
    return { value = value }, {
        label = "Animate class resource preview",
        summary = "Changes the Class Resources inline preview animation.",
    }
end

local function RefreshClassPowerPreview()
    if M and type(M.RequestGeneralApply) == "function" then
        M.RequestGeneralApply("MSUF_ASSISTANT_CLASSPOWER_PREVIEW", { preview = true, applyAll = false, notify = false })
    elseif type(CallGlobal) == "function" then
        CallGlobal("MSUF_UFPreview_RequestRefresh", "MSUF_ASSISTANT_CLASSPOWER_PREVIEW")
    end
    local preview = M and M._msuf2ClassPowerInlinePreview
    if preview and type(preview.Refresh) == "function" then preview:Refresh() end
end

Registry:RegisterSetting({
    key = "menu.classPowerPreviewResource",
    label = "Class Resource Preview Resource",
    category = "Class Resources / Preview",
    unit = "global",
    frameType = "classPower",
    attribute = "classPowerPreviewResource",
    type = "enum",
    aliases = {
        "class resource preview resource",
        "class resource preview",
        "preview class resource",
        "preview class resources",
        "class power preview resource",
        "class power preview",
        "preview class power",
        "preview class bar",
        "preview resource",
        "resource preview",
    },
    exactAliases = ClassPowerPreviewExactAliases(),
    values = CLASS_POWER_PREVIEW_VALUES,
    valueAliases = ClassPowerPreviewValueAliases(),
    get = function()
        if M and type(M.GetClassPowerPreviewSpecKey) == "function" then return M.GetClassPowerPreviewSpecKey() end
        return NormalizeClassPowerPreviewKey(M and M._msuf2ClassPowerPreviewSpecKey)
    end,
    set = function(value)
        value = NormalizeClassPowerPreviewKey(value)
        if M and type(M.SetClassPowerPreviewSpecKey) == "function" then
            M.SetClassPowerPreviewSpecKey(value)
        elseif M then
            M._msuf2ClassPowerPreviewSpecKey = value
        end
    end,
    apply = RefreshClassPowerPreview,
    combatSafe = true,
    description = "Selects the Class Resources page preview without changing saved class-resource settings.",
})

A.ClassPowerRegistry = A.ClassPowerRegistry or {}
A.ClassPowerRegistry.Actions = {
    M = M,
    Registry = Registry,
    ParseClassPowerPreviewAnimationAliasArgs = ParseClassPowerPreviewAnimationAliasArgs,
}
