-- Assistant RegistryCore registry methods.
-- Keeps setting/action storage and query indexing separate from DB/apply helpers.
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
if type(Registry) ~= "table" then return end

local AddSettingToFindIndex

function Registry:RegisterSetting(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return nil end
    if self.settingsByKey[spec.key] then return self.settingsByKey[spec.key] end
    spec.aliases = type(spec.aliases) == "table" and spec.aliases or {}
    self.settings[#self.settings + 1] = spec
    self.settingsByKey[spec.key] = spec
    if type(self._findSettingsIndex) == "table"
        and tonumber(self._findSettingsIndexCount) == (#self.settings - 1)
        and type(AddSettingToFindIndex) == "function" then
        AddSettingToFindIndex(self._findSettingsIndex, spec)
        self._findSettingsIndexCount = #self.settings
    end
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    return spec
end

function Registry:GetSetting(key)
    return self.settingsByKey[key]
end

function Registry:AllSettings()
    return self.settings
end

local function AddFindIndex(index, bucket, key, setting)
    key = tostring(key or "")
    if key == "" then return end
    local byKey = index[bucket]
    byKey[key] = byKey[key] or {}
    byKey[key][#byKey[key] + 1] = setting
end

AddSettingToFindIndex = function(index, setting)
    if type(index) ~= "table" or type(setting) ~= "table" then return end
    AddFindIndex(index, "byUnit", setting.unit, setting)
    AddFindIndex(index, "byFrameType", setting.frameType, setting)
    AddFindIndex(index, "byAttribute", setting.attribute, setting)
    AddFindIndex(index, "byType", setting.type, setting)
end

function Registry:BuildFindSettingsIndex()
    local existing = self._findSettingsIndex
    local indexedCount = tonumber(self._findSettingsIndexCount) or 0
    local settingsCount = #self.settings
    if type(existing) == "table" and indexedCount > 0 and indexedCount <= settingsCount then
        for i = indexedCount + 1, settingsCount do
            AddSettingToFindIndex(existing, self.settings[i])
        end
        self._findSettingsIndexCount = settingsCount
        return existing
    end
    local index = {
        byUnit = {},
        byFrameType = {},
        byAttribute = {},
        byType = {},
    }
    for i = 1, #self.settings do
        AddSettingToFindIndex(index, self.settings[i])
    end
    self._findSettingsIndex = index
    self._findSettingsIndexCount = #self.settings
    return index
end

function Registry:FindSettingsCandidateList(filter, unitSet)
    local index = self._findSettingsIndex
    if not index or self._findSettingsIndexCount ~= #self.settings then
        index = self:BuildFindSettingsIndex()
    end
    local best
    local function consider(list)
        if type(list) == "table" and (not best or #list < #best) then best = list end
    end
    if type(filter.unit) == "string" then
        consider(index.byUnit[filter.unit])
    elseif type(filter.units) == "table" and #filter.units == 1 then
        consider(index.byUnit[filter.units[1]])
    end
    if filter.frameType then consider(index.byFrameType[filter.frameType]) end
    if filter.attribute then consider(index.byAttribute[filter.attribute]) end
    if filter.type then consider(index.byType[filter.type]) end
    return best or self.settings
end

function Registry:FindSettings(filter)
    filter = filter or {}
    local out = {}
    local unitSet
    if type(filter.units) == "table" then
        unitSet = {}
        for i = 1, #filter.units do unitSet[filter.units[i]] = true end
    elseif type(filter.unit) == "string" then
        unitSet = { [filter.unit] = true }
    end
    local candidates = self:FindSettingsCandidateList(filter, unitSet)
    for i = 1, #candidates do
        local setting = candidates[i]
        local ok = true
        if unitSet and not unitSet[setting.unit] then ok = false end
        if ok and filter.frameType and setting.frameType ~= filter.frameType then ok = false end
        if ok and filter.attribute and setting.attribute ~= filter.attribute then ok = false end
        if ok and filter.type and setting.type ~= filter.type then ok = false end
        if ok then out[#out + 1] = setting end
    end
    return out
end

function Registry:RegisterAction(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == "" then return nil end
    if self.actionsByKey[spec.key] then return self.actionsByKey[spec.key] end
    spec.aliases = type(spec.aliases) == "table" and spec.aliases or {}
    self.actions[#self.actions + 1] = spec
    self.actionsByKey[spec.key] = spec
    if A.Knowledge and type(A.Knowledge.MarkDirty) == "function" then A.Knowledge.MarkDirty() end
    return spec
end

function Registry:GetAction(key)
    return self.actionsByKey[key]
end

function Registry:AllActions()
    return self.actions
end

function Registry:RegisterTodo(text)
    self.todos[#self.todos + 1] = tostring(text or "")
end

function Registry:GetTodos()
    return self.todos
end
