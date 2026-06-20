-- Assistant Auras shared reminder setting registry.
-- Loaded before the Auras setting installer; this is cold Assistant metadata only.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

local function AuraSharedAliases(AddAliasesForAuraScope, ...)
    local aliases = {}
    for i = 1, select("#", ...) do
        local alias = select(i, ...)
        aliases[#aliases + 1] = alias
        AddAliasesForAuraScope(aliases, "shared", alias)
    end
    return aliases
end

function A.AurasRegistry.RegisterSharedReminderCoreSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AuraSharedBool = ctx.AuraSharedBool
    local SetAuraSharedBool = ctx.SetAuraSharedBool
    local AuraReadNumber = ctx.AuraReadNumber
    local AuraWriteNumber = ctx.AuraWriteNumber
    local AuraSharedString = ctx.AuraSharedString
    local SetAuraSharedString = ctx.SetAuraSharedString
    local ApplyAuraReminders = ctx.ApplyAuraReminders

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" then return end
    if type(AuraSharedBool) ~= "function" or type(SetAuraSharedBool) ~= "function" then return end
    if type(AuraReadNumber) ~= "function" or type(AuraWriteNumber) ~= "function" then return end
    if type(AuraSharedString) ~= "function" or type(SetAuraSharedString) ~= "function" then return end
    if type(ApplyAuraReminders) ~= "function" then return end

    local reminderMasterExactAliases = { "buff reminders", "aura reminders", "show buff reminders", "enable buff reminders" }
    Registry:RegisterSetting({
        key = "auras3.shared.showReminders",
        label = "Shared Buff Reminders",
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "auraShowReminders",
        type = "boolean",
        aliases = AuraSharedAliases(AddAliasesForAuraScope, "buff reminders", "aura reminders", "show buff reminders", "enable buff reminders"),
        exactAliases = reminderMasterExactAliases,
        get = function() return AuraSharedBool("showReminders", true) end,
        set = function(value) SetAuraSharedBool("showReminders", value) end,
        apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDERS") end,
        combatSafe = false,
    })

    local reminderThresholdExactAliases = { "buff reminder expiry warning", "buff reminder threshold", "reminder expiry warning", "reminder threshold" }
    Registry:RegisterSetting({
        key = "auras3.shared.reminderThreshold",
        label = "Shared Buff Reminder Expiry Warning",
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "auraReminderThreshold",
        type = "number",
        aliases = AuraSharedAliases(AddAliasesForAuraScope, "buff reminder expiry warning", "buff reminder threshold", "reminder expiry warning", "reminder threshold"),
        exactAliases = reminderThresholdExactAliases,
        min = 0,
        max = 600,
        step = 5,
        get = function() return AuraReadNumber("shared", "reminderThreshold", 0, 0, 600) end,
        set = function(value) AuraWriteNumber("shared", "reminderThreshold", value, 0, 600) end,
        apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDER_THRESHOLD") end,
        combatSafe = false,
    })

    local reminderGrowthExactAliases = { "buff reminder grow direction", "buff reminder growth", "reminder grow direction", "reminder growth" }
    Registry:RegisterSetting({
        key = "auras3.shared.reminderGrowth",
        label = "Shared Buff Reminder Grow Direction",
        category = "Shared / Auras",
        unit = "shared",
        frameType = "aura",
        attribute = "auraReminderGrowth",
        type = "enum",
        aliases = AuraSharedAliases(AddAliasesForAuraScope, "buff reminder grow direction", "buff reminder growth", "reminder grow direction", "reminder growth"),
        exactAliases = reminderGrowthExactAliases,
        values = { "RIGHT", "LEFT", "UP", "DOWN" },
        valueAliases = {
            right = "RIGHT",
            rechts = "RIGHT",
            left = "LEFT",
            links = "LEFT",
            up = "UP",
            hoch = "UP",
            down = "DOWN",
            runter = "DOWN",
        },
        get = function()
            return AuraSharedString("reminderGrowth", "RIGHT", { RIGHT = true, LEFT = true, UP = true, DOWN = true })
        end,
        set = function(value)
            SetAuraSharedString("reminderGrowth", value, "RIGHT", { RIGHT = true, LEFT = true, UP = true, DOWN = true })
        end,
        apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDER_GROWTH") end,
        combatSafe = false,
    })
end

function A.AurasRegistry.RegisterSharedReminderToggleSettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AURA_REMINDER_SPECS = ctx.AURA_REMINDER_SPECS or {}
    local AddAliasesForAuraScope = ctx.AddAliasesForAuraScope
    local AuraSharedTable = ctx.AuraSharedTable
    local ApplyAuraReminders = ctx.ApplyAuraReminders

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForAuraScope) ~= "function" or type(AuraSharedTable) ~= "function" then return end
    if type(ApplyAuraReminders) ~= "function" then return end

    for _, spec in ipairs(AURA_REMINDER_SPECS) do
        local reminderKey, reminderLabel = spec.key, spec.label
        local aliases = {}
        for i = 1, #spec.aliases do
            aliases[#aliases + 1] = spec.aliases[i]
            AddAliasesForAuraScope(aliases, "shared", spec.aliases[i])
        end
        Registry:RegisterSetting({
            key = "auras3.shared.reminders." .. reminderKey,
            label = "Shared " .. reminderLabel .. " Reminder",
            category = "Shared / Auras",
            unit = "shared",
            frameType = "aura",
            attribute = "auraReminder" .. reminderKey,
            type = "boolean",
            aliases = aliases,
            exactAliases = spec.aliases,
            get = function()
                local reminders = AuraSharedTable("reminders")
                local value = reminders[reminderKey]
                if value == nil then return true end
                return value == true
            end,
            set = function(value)
                AuraSharedTable("reminders")[reminderKey] = value == true
            end,
            apply = function() ApplyAuraReminders("MSUF_ASSISTANT_AURA_REMINDER_TOGGLE") end,
            combatSafe = false,
        })
    end
end
