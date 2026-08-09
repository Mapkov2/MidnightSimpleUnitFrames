-- Assistant Auras shared setting registry.
-- Keeps shared aura overrides and layout metadata out of the main Auras registry;
-- reminder metadata is split into MSUF_AssistantRegistry_Auras_Shared_Reminders.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterSharedSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_UNITS = ctx.AURA_UNITS or {}
    local AURA_SCOPE_OVERRIDE_SPECS = ctx.AURA_SCOPE_OVERRIDE_SPECS or {}
    local AURA_SHARED_BOOLEAN_SPECS = ctx.AURA_SHARED_BOOLEAN_SPECS or {}
    local AURA_GROWTH_VALUES = ctx.AURA_GROWTH_VALUES or {}
    local AURA_GROWTH_ALIASES = ctx.AURA_GROWTH_ALIASES or {}
    local AURA_ROW_WRAP_VALUES = ctx.AURA_ROW_WRAP_VALUES or {}
    local AURA_ROW_WRAP_ALIASES = ctx.AURA_ROW_WRAP_ALIASES or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AuraScopeLabel = ctx.AuraScopeLabel
    local AuraOverrideBool = ctx.AuraOverrideBool
    local SetAuraOverrideBool = ctx.SetAuraOverrideBool
    local RegisterAuraScopeBoolean = ctx.RegisterAuraScopeBoolean
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraModel = ctx.AuraModel
    local AuraSharedString = ctx.AuraSharedString
    local SetAuraSharedString = ctx.SetAuraSharedString
    local AuraReadLaneStyleBool = ctx.AuraReadLaneStyleBool
    local AuraWriteLaneStyleBool = ctx.AuraWriteLaneStyleBool
    local ApplyAura = ctx.ApplyAura

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AuraScopeLabel) ~= "function" then return end
    if type(AuraOverrideBool) ~= "function" or type(SetAuraOverrideBool) ~= "function" then return end
    if type(RegisterAuraScopeBoolean) ~= "function" or type(AuraReadNumber) ~= "function" then return end
    if type(AuraWriteNumber) ~= "function" or type(AuraSharedString) ~= "function" then return end
    if type(SetAuraSharedString) ~= "function" or type(ApplyAura) ~= "function" then return end
    if type(AuraReadLaneStyleBool) ~= "function" or type(AuraWriteLaneStyleBool) ~= "function" then return end

    for _, scope in ipairs(AURA_UNITS) do
        for _, spec in ipairs(AURA_SCOPE_OVERRIDE_SPECS) do
            local settingScope, settingKey, exactAliases = scope, spec.key, {}
            local aliases = {}
            for i = 1, #spec.aliases do
                exactAliases[#exactAliases + 1] = settingScope .. " " .. spec.aliases[i]
                exactAliases[#exactAliases + 1] = settingScope .. " aura " .. spec.aliases[i]:gsub("^aura%s+", "")
                exactAliases[#exactAliases + 1] = settingScope .. " auras " .. spec.aliases[i]:gsub("^aura%s+", "")
                AddAliasesForAuraScope(aliases, settingScope, spec.aliases[i])
            end
            Registry:RegisterSetting({
                key = "auras3." .. settingScope .. "." .. settingKey,
                label = AuraScopeLabel(settingScope) .. " " .. spec.label,
                category = AuraScopeLabel(settingScope) .. " / Auras",
                unit = settingScope,
                frameType = "aura",
                attribute = "aura" .. settingKey:gsub("^%l", string.upper),
                type = "boolean",
                aliases = aliases,
                exactAliases = exactAliases,
                get = function() return AuraOverrideBool(settingScope, settingKey) end,
                set = function(value) SetAuraOverrideBool(settingScope, settingKey, value) end,
                apply = function() ApplyAura(settingScope, "MSUF_ASSISTANT_AURA_OVERRIDE") end,
                combatSafe = false,
            })
        end
    end

    local canonicalLaneBool = {
        showTooltip = "showTooltip",
        -- The Auras2 name described the reverse cooldown swipe. Preserve the
        -- Assistant phrase, but write the two Auras3 lane-owned fields.
        cooldownSwipeDarkenOnLoss = "cooldownSwipeReverse",
    }

    local function RegisterSharedBooleanSpec(spec)
        local aliases = {}
        for i = 1, #(spec.aliases or {}) do
            aliases[#aliases + 1] = spec.aliases[i]
            AddAliasesForAuraScope(aliases, "shared", spec.aliases[i])
        end
        local laneKey = canonicalLaneBool[spec.attr]
        local read, write
        if spec.attr == "useDebuffTypeBorders" then
            read = function()
                local Model = type(AuraModel) == "function" and AuraModel() or nil
                if Model and type(Model.ReadDebuffTypeBorderMode) == "function" then
                    return Model.ReadDebuffTypeBorderMode("shared") ~= "OFF"
                end
                return AuraReadLaneStyleBool("shared", "debuff", "useDebuffTypeBorders", spec.defaultValue)
            end
            write = function(value)
                local Model = type(AuraModel) == "function" and AuraModel() or nil
                if Model and type(Model.WriteDebuffTypeBorderMode) == "function" then
                    Model.WriteDebuffTypeBorderMode("shared", value and "BORDER" or "OFF")
                    return
                end
                AuraWriteLaneStyleBool("shared", "debuff", "useDebuffTypeBorders", value)
            end
        elseif laneKey then
            read = function()
                return AuraReadLaneStyleBool("shared", "buff", laneKey, spec.defaultValue)
            end
            write = function(value)
                AuraWriteLaneStyleBool("shared", "buff", laneKey, value)
                AuraWriteLaneStyleBool("shared", "debuff", laneKey, value)
            end
        end
        RegisterAuraScopeBoolean("shared", spec.attr, spec.label, spec.defaultValue, aliases, read, write, nil, spec.aliases)
    end

    for _, spec in ipairs(AURA_SHARED_BOOLEAN_SPECS) do
        RegisterSharedBooleanSpec(spec)
    end

    local RegisterSharedReminderCoreSettings = A.AurasRegistry and A.AurasRegistry.RegisterSharedReminderCoreSettings
    if type(RegisterSharedReminderCoreSettings) == "function" then
        RegisterSharedReminderCoreSettings(ctx)
    end

    local RegisterSharedLayoutSettings = A.AurasRegistry and A.AurasRegistry.RegisterSharedLayoutSettings
    if type(RegisterSharedLayoutSettings) == "function" then
        RegisterSharedLayoutSettings(ctx)
    end

    local RegisterSharedReminderToggleSettings = A.AurasRegistry and A.AurasRegistry.RegisterSharedReminderToggleSettings
    if type(RegisterSharedReminderToggleSettings) == "function" then
        RegisterSharedReminderToggleSettings(ctx)
    end
end
