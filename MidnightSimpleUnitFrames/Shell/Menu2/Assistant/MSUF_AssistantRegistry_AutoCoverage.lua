-- Assistant auto-coverage fallback registration.
--
-- Closes the raw-coverage gap mechanically: every scalar DB key that no
-- hand-written registry entry reaches gets a generated English setting with a
-- label and aliases derived from the key name, direct get/set into the DB, and
-- the broadest safe apply for its scope. Hand-written entries always win
-- (RegisterSetting dedupes by key; the covered-set check also honors
-- unit+attribute), so this layer only ever fills holes.
--
-- Generated entries are marked `generated = true` so the coverage audit,
-- knowledge dump, and future curation passes can tell them apart. They are the
-- floor, not the ceiling: /msufcoverage stubs <scope> still produces proper
-- stubs when a key deserves curated aliases and a precise apply.
--
-- Runs once at PLAYER_LOGIN (DB seeded, all domains registered) and again on
-- demand via /msufcoverage fill (e.g. after a profile import materializes new
-- keys). Re-running is idempotent.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Auto = A.AutoCoverage or {}
A.AutoCoverage = Auto

local UNIT_SCOPES = {
    player = true, target = true, targettarget = true, focustarget = true,
    focus = true, pet = true, boss = true,
}
local GROUP_SCOPES = { gf_party = "party", gf_raid = "raid", gf_mythicraid = "mythicraid" }
local FLAT_SCOPES = { general = true, bars = true, gameplay = true }

local function LabelFromKey(key)
    local label = key:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):gsub("_", " ")
    return (label:gsub("^%l", string.upper))
end

local function ScopeLabel(scope)
    local RC = A.RegistryCore
    local labels = RC and RC.UNIT_LABELS or {}
    if GROUP_SCOPES[scope] then return labels[GROUP_SCOPES[scope]] or LabelFromKey(GROUP_SCOPES[scope]) end
    return labels[scope] or LabelFromKey(scope)
end

local function ScopeApply(scope, key)
    local RC = A.RegistryCore
    if not RC then return function() end end
    if UNIT_SCOPES[scope] and type(RC.ApplyUnit) == "function" then
        local reason = "MSUF_ASSISTANT_AUTO_" .. key
        return function() RC.ApplyUnit(scope, reason, { preview = true }) end
    end
    if GROUP_SCOPES[scope] and type(RC.ApplyGroup) == "function" then
        local groupScope = GROUP_SCOPES[scope]
        return function() RC.ApplyGroup(groupScope, "visual") end
    end
    local flat = {
        general = RC.ApplyGeneral,
        bars = RC.ApplyBars,
        gameplay = RC.ApplyGameplay,
    }
    local fn = flat[scope]
    if type(fn) == "function" then
        local reason = "MSUF_ASSISTANT_AUTO_" .. key
        return function() fn(reason) end
    end
    return function()
        local refresh = _G.MSUF_RefreshAllFrames
        if type(refresh) == "function" then refresh() end
    end
end

local function ScopeTable(scope, create)
    local db = _G.MSUF_DB
    if type(db) ~= "table" then return nil end
    local tbl = db[scope]
    if type(tbl) ~= "table" and create then
        tbl = {}
        db[scope] = tbl
    end
    return type(tbl) == "table" and tbl or nil
end

local function ManifestDefaults()
    local manifest = A.AutoCoverageManifest
    if type(manifest) ~= "table" then return nil end
    if type(manifest.defaults) == "table" then return manifest.defaults end
    return manifest
end

local function BuildSpec(scope, key, value, fromManifest)
    local valueType = type(value)
    local label = LabelFromKey(key)
    local scopeLabel = ScopeLabel(scope)
    local fullLabel = scopeLabel .. " " .. label
    local aliasBase = label:lower()
    local aliases = { aliasBase, fullLabel:lower() }
    local unit = UNIT_SCOPES[scope] and scope or GROUP_SCOPES[scope] or nil
    local spec = {
        key = scope .. "." .. key,
        label = fullLabel,
        category = scopeLabel .. " / Auto (generated)",
        unit = unit,
        frameType = GROUP_SCOPES[scope] and "group" or (UNIT_SCOPES[scope] and "unitframe" or scope),
        attribute = key,
        aliases = aliases,
        generated = true,
        manifestDefault = fromManifest and value or nil,
        combatSafe = false,
        apply = ScopeApply(scope, key),
        description = fromManifest
            and ("Auto-generated from the default manifest; controls '" .. key .. "' directly.")
            or ("Auto-generated from saved settings; controls '" .. key .. "' directly."),
    }
    if valueType == "boolean" then
        spec.type = "boolean"
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v = tbl and tbl[key]
            if v == nil then return value and true or false end
            return v and true or false
        end
        spec.set = function(v)
            local tbl = ScopeTable(scope, true)
            if tbl then tbl[key] = v and true or false end
        end
    elseif valueType == "number" then
        spec.type = "number"
        if value >= 0 and value <= 1 then
            spec.min, spec.max, spec.step, spec.percent = 0, 1, 0.05, true
        else
            spec.step = 1
        end
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v = tbl and tonumber(tbl[key])
            if v == nil then return value end
            return v
        end
        spec.set = function(v)
            v = tonumber(v)
            if v == nil then return end
            if spec.min and v < spec.min then v = spec.min end
            if spec.max and v > spec.max then v = spec.max end
            local tbl = ScopeTable(scope, true)
            if tbl then tbl[key] = v end
        end
    else
        spec.type = "string"
        spec.get = function()
            local tbl = ScopeTable(scope)
            local v = tbl and tbl[key]
            if v == nil then return value end
            return tostring(v)
        end
        spec.set = function(v)
            local tbl = ScopeTable(scope, true)
            if tbl then tbl[key] = tostring(v) end
        end
    end
    return spec
end

local function SortedKeys(map)
    local out = {}
    if type(map) ~= "table" then return out end
    for key in pairs(map) do
        out[#out + 1] = key
    end
    table.sort(out)
    return out
end

local function LuaString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub("\r", "\\r"):gsub("\n", "\\n"):gsub('"', '\\"')
    return '"' .. value .. '"'
end

local function LuaKey(key)
    key = tostring(key or "")
    if key:match("^[%a_][%w_]*$") then return key end
    return "[" .. LuaString(key) .. "]"
end

local function LuaValue(value)
    local valueType = type(value)
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType == "number" then return tostring(value) end
    return LuaString(value)
end

local function AllManifestScopes()
    local scopes = {}
    for scope in pairs(UNIT_SCOPES) do scopes[#scopes + 1] = scope end
    for scope in pairs(GROUP_SCOPES) do scopes[#scopes + 1] = scope end
    for scope in pairs(FLAT_SCOPES) do scopes[#scopes + 1] = scope end
    table.sort(scopes)
    return scopes
end

function Auto.BuildManifestText()
    local Audit = A.CoverageAudit
    local lines = {
        "-- Paste into MSUF_AssistantRegistry_AutoCoverage_Manifest.lua.",
        "-- Source: freshly seeded profile DB scalar keys.",
        "Manifest.defaults = {",
    }
    local scopes = AllManifestScopes()
    local total = 0
    for i = 1, #scopes do
        local scope = scopes[i]
        local tbl = ScopeTable(scope)
        local keys = SortedKeys(tbl)
        local wroteScope = false
        for k = 1, #keys do
            local key = keys[k]
            local value = tbl[key]
            local valueType = type(value)
            local ignored = Audit and type(Audit.IsIgnored) == "function" and Audit.IsIgnored(scope, key)
            if type(key) == "string"
                and not ignored
                and (valueType == "boolean" or valueType == "number" or valueType == "string")
            then
                if not wroteScope then
                    lines[#lines + 1] = "    " .. LuaKey(scope) .. " = {"
                    wroteScope = true
                end
                lines[#lines + 1] = "        " .. LuaKey(key) .. " = " .. LuaValue(value) .. ","
                total = total + 1
            end
        end
        if wroteScope then lines[#lines + 1] = "    }," end
    end
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    lines[#lines + 1] = ("-- scalar defaults: %d"):format(total)
    return table.concat(lines, "\n"), total
end

function Auto.StoreManifestExport(text, total)
    local gdb = _G.MSUF_GlobalDB
    if type(gdb) ~= "table" then return end
    gdb.assistantAutoCoverageManifest = {
        time = date("%Y-%m-%d %H:%M:%S"),
        total = tonumber(total) or 0,
        text = tostring(text or ""),
    }
end

--- Registers generated settings for every uncovered scalar DB key.
--- Returns the number of settings added (0 when everything is covered or
--- prerequisites are missing). Safe to call repeatedly.
function Auto.Fill()
    local Registry = A.Registry
    if not (Registry and type(Registry.RegisterSetting) == "function") then return 0 end
    local Audit = A.CoverageAudit
    if not (Audit and type(Audit.BuildCoveredSets) == "function") then return 0 end
    local covered = Audit.BuildCoveredSets()
    local added = 0
    local function RegisterGenerated(scope, key, value, coveredSet, fromManifest)
        local valueType = type(value)
        if type(key) == "string"
            and key:sub(1, 1) ~= "_"
            and not coveredSet[key]
            and not Audit.IsIgnored(scope, key)
            and (valueType == "boolean" or valueType == "number" or valueType == "string")
        then
            local fullKey = scope .. "." .. key
            local existing = type(Registry.GetSetting) == "function" and Registry:GetSetting(fullKey) or nil
            if existing then
                coveredSet[key] = existing
                return
            end
            local registered = Registry:RegisterSetting(BuildSpec(scope, key, value, fromManifest))
            if registered then
                coveredSet[key] = registered
                added = added + 1
            end
        end
    end

    local function FillScope(scope)
        local tbl = ScopeTable(scope)
        if not tbl then return end
        local coveredSet = covered[scope] or {}
        covered[scope] = coveredSet
        for key, value in pairs(tbl) do
            RegisterGenerated(scope, key, value, coveredSet, false)
        end
    end

    local function FillManifestScope(scope)
        local manifest = ManifestDefaults()
        local manifestScope = type(manifest) == "table" and manifest[scope] or nil
        if type(manifestScope) ~= "table" then return end
        local live = ScopeTable(scope)
        local coveredSet = covered[scope] or {}
        covered[scope] = coveredSet
        for key, value in pairs(manifestScope) do
            if not (type(live) == "table" and live[key] ~= nil) then
                RegisterGenerated(scope, key, value, coveredSet, true)
            end
        end
    end
    for scope in pairs(UNIT_SCOPES) do FillScope(scope) end
    for scope in pairs(GROUP_SCOPES) do FillScope(scope) end
    for scope in pairs(FLAT_SCOPES) do FillScope(scope) end
    for scope in pairs(UNIT_SCOPES) do FillManifestScope(scope) end
    for scope in pairs(GROUP_SCOPES) do FillManifestScope(scope) end
    for scope in pairs(FLAT_SCOPES) do FillManifestScope(scope) end
    Auto.lastFillCount = added
    return added
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Defer one frame so any login-time default seeding finishes first.
    if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function() Auto.Fill() end)
    else
        Auto.Fill()
    end
end)
