-- Assistant GroupFrames spell indicator action registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSpellIndicators.lua; the main registry passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterSpellIndicatorActions(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local UNIT_LABELS = ctx.UNIT_LABELS or {}
    local CI_SLOTS = ctx.CI_SLOTS or {}
    local Scope = ctx.Scope
    local GroupDB = ctx.GroupDB
    local ApplyGroup = ctx.ApplyGroup
    local ResolveSpec = ctx.ResolveSpec
    local ResolveAura = ctx.ResolveAura
    local ResolveSlot = ctx.ResolveSlot
    local SpellEntry = ctx.SpellEntry
    local SpecDisplay = ctx.SpecDisplay
    local SpellRuntime = ctx.SpellRuntime
    local SpellDB = ctx.SpellDB
    local EnsureSpec = ctx.EnsureSpec
    local ApplySpell = ctx.ApplySpell
    local CopyTable = ctx.CopyTable
    local ClampNumber = ctx.ClampNumber
    local Clamp01 = ctx.Clamp01
    local Placed = ctx.Placed
    local FrameEffect = ctx.FrameEffect

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(Scope) ~= "function" or type(GroupDB) ~= "function" or type(ApplyGroup) ~= "function" then return end
    if type(ResolveSpec) ~= "function" or type(ResolveAura) ~= "function" or type(SpecDisplay) ~= "function" then return end
    if type(SpellEntry) ~= "function" or type(SpellRuntime) ~= "function" or type(SpellDB) ~= "function" then return end
    if type(EnsureSpec) ~= "function" or type(ApplySpell) ~= "function" or type(CopyTable) ~= "function" then return end
    if type(ClampNumber) ~= "function" or type(Clamp01) ~= "function" then return end
    if type(Placed) ~= "function" or type(FrameEffect) ~= "function" or type(ResolveSlot) ~= "function" then return end

    local function GroupLabel(scope)
        if A and type(A.DisplayGroupLabel) == "function" then return A.DisplayGroupLabel(scope) end
        local label = UNIT_LABELS[scope]
        if label ~= nil and tostring(label) ~= "" then return tostring(label) end
        if scope == "mythicraid" then return "Mythic Raid" end
        if scope == "raid" then return "Raid" end
        return "Party"
    end

    local BuildSpellIndicatorActionHelpers = A.GroupFramesRegistry and A.GroupFramesRegistry.BuildSpellIndicatorActionHelpers
    local ActionHelpers = type(BuildSpellIndicatorActionHelpers) == "function" and BuildSpellIndicatorActionHelpers({
        Scope = Scope,
        ResolveSpec = ResolveSpec,
        ResolveAura = ResolveAura,
        SpellEntry = SpellEntry,
        ApplySpell = ApplySpell,
        ClampNumber = ClampNumber,
        Clamp01 = Clamp01,
        Placed = Placed,
        FrameEffect = FrameEffect,
    }) or nil
    if type(ActionHelpers) ~= "table" then return end
    local ActionTarget = ActionHelpers.ActionTarget
    local SetSpellField = ActionHelpers.SetSpellField
    if type(ActionTarget) ~= "function" or type(SetSpellField) ~= "function" then return end

    Registry:RegisterAction({
        key = "clear_group_custom_anchor",
        label = "Clear Group Custom Anchor",
        type = "reset",
        combatSafe = false,
        captureSnapshot = true,
        aliases = { "clear group custom anchor", "clear group custom anchor frame", "reset group custom anchor", "remove group custom anchor" },
        run = function(args)
            local scope = Scope(args and args.scope)
            GroupDB(scope).anchorToFrame = nil
            ApplyGroup(scope, "rebuild")
            return true, "Done. Cleared " .. GroupLabel(scope) .. " custom anchor."
        end,
    })

    Registry:RegisterAction({
        key = "set_group_spell_indicator_aura",
        label = "Set Group Spell Indicator Aura",
        page = "gf_auras",
        type = "configure",
        combatSafe = false,
        captureSnapshot = true,
        description = "Configures one tracked Group Spell Indicator aura entry, including enable state, own-aura filtering, placed indicator type, anchor, size, offsets, bar width, growth, smooth bar fill, movable bar timer text, cooldown text, frame effect, color, opacity, thickness, and priority.",
        aliases = {
            "configure group spell indicator", "edit group spell indicator", "set group spell indicator",
            "set group tracked spell", "configure tracked spell", "edit tracked spell",
            "group spell indicator enabled", "group spell indicator own aura", "group spell indicator only own",
            "group spell indicator type", "group spell indicator placed type", "group spell indicator anchor",
            "group spell indicator size", "group spell indicator x offset", "group spell indicator y offset",
            "group spell indicator bar width", "group spell indicator growth", "group spell indicator cooldown",
            "group spell indicator cooldown swipe", "group spell indicator cooldown size",
            "group spell indicator smooth bar fill", "group spell indicator bar timer",
            "group spell indicator timer anchor", "group spell indicator timer x", "group spell indicator timer y",
            "group spell indicator frame effect", "group spell indicator frame priority",
            "group spell indicator tint alpha", "group spell indicator opacity", "group spell indicator thickness",
            "group spell indicator color", "party spell indicator anchor", "raid spell indicator anchor",
            "mythic raid spell indicator anchor", "party spell indicator growth", "raid spell indicator growth",
            "mythic raid spell indicator growth", "party spell indicator size", "raid spell indicator size",
            "mythic raid spell indicator size",
        },
        run = function(args)
            local scope, specKey, auraName, display = ActionTarget(args)
            if not specKey then return false, "Which spell-indicator spec do you want me to use? Examples: Holy Paladin or Restoration Druid." end
            if not auraName then return false, "Which spell indicator aura do you want me to use for " .. SpecDisplay(specKey) .. "?" end
            if not SetSpellField(scope, specKey, auraName, args and args.field, args and args.value) then return false, "I can open that spell indicator, but that part is not editable here yet." end
            return true, "Done. " .. GroupLabel(scope) .. " " .. SpecDisplay(specKey) .. " " .. tostring(display or auraName) .. " spell indicator updated."
        end,
    })

    Registry:RegisterAction({
        key = "reset_group_spell_indicator_aura",
        label = "Reset Group Spell Indicator Aura",
        page = "gf_auras",
        type = "reset",
        combatSafe = false,
        captureSnapshot = true,
        description = "Resets one tracked Group Spell Indicator aura entry back to its default setup for the selected spec.",
        aliases = {
            "reset group spell indicator", "reset group tracked spell", "reset tracked spell indicator",
            "clear group spell indicator aura", "restore group spell indicator aura",
            "reset party spell indicator", "reset raid spell indicator", "reset mythic raid spell indicator",
        },
        run = function(args)
            local scope, specKey, auraName, display = ActionTarget(args)
            if not specKey then return false, "Which spell-indicator spec do you want me to reset?" end
            if not auraName then return false, "Which spell indicator aura do you want me to use for " .. SpecDisplay(specKey) .. "?" end
            local _, specCfg = SpellEntry(scope, specKey, auraName, true)
            local defaults = SpellRuntime() and SpellRuntime().SpecDefaults and SpellRuntime().SpecDefaults[specKey]
            specCfg[auraName] = type(defaults) == "table" and type(defaults[auraName]) == "table" and CopyTable(defaults[auraName]) or nil
            ApplySpell(scope)
            return true, "Done. Reset " .. GroupLabel(scope) .. " " .. SpecDisplay(specKey) .. " " .. tostring(display or auraName) .. " spell indicator."
        end,
    })

    Registry:RegisterAction({
        key = "set_group_spell_indicator_multi_spec",
        label = "Set Group Spell Indicator Multi-Spec Entry",
        page = "gf_auras",
        type = "configure",
        combatSafe = false,
        captureSnapshot = true,
        description = "Adds or removes one specialization from Group Spell Indicator Multi-Spec tracking.",
        aliases = {
            "track group spell indicator spec", "group spell indicator multi spec",
            "group spell indicator multi-spec", "group tracked spell multi spec",
            "party spell indicator multi spec", "raid spell indicator multi spec",
            "mythic raid spell indicator multi spec",
        },
        run = function(args)
            local scope, specKey = Scope(args and args.scope), ResolveSpec(args and args.spec)
            if not specKey or specKey == "auto" or specKey == "multi" then return false, "Which specific spell-indicator spec do you want me to track in Multi-Spec mode?" end
            local si = SpellDB(scope)
            si.spec = "multi"
            si.multiSpecs = type(si.multiSpecs) == "table" and si.multiSpecs or {}
            si.multiSpecs[specKey] = args and args.value and true or nil
            EnsureSpec(scope, specKey)
            ApplySpell(scope)
            return true, "Done. " .. GroupLabel(scope) .. " Multi-Spec tracking for " .. SpecDisplay(specKey) .. " " .. ((args and args.value) and "enabled." or "disabled.")
        end,
    })

    Registry:RegisterAction({
        key = "move_group_spell_indicator_order",
        label = "Move Group Spell Indicator Order",
        page = "gf_auras",
        type = "configure",
        combatSafe = false,
        captureSnapshot = true,
        description = "Moves one tracked Group Spell Indicator aura to another position in that spec's ordered spell list.",
        aliases = {
            "move group spell indicator", "reorder group spell indicator",
            "move group tracked spell", "reorder group tracked spell",
            "party spell indicator order", "raid spell indicator order",
            "mythic raid spell indicator order",
        },
        run = function(args)
            local scope, specKey, auraName, display = ActionTarget(args)
            if not specKey then return false, "Which spell-indicator spec do you want me to reorder?" end
            if not auraName then return false, "Which spell indicator aura do you want me to use for " .. SpecDisplay(specKey) .. "?" end
            EnsureSpec(scope, specKey)
            local trackable = SpellRuntime() and SpellRuntime().TrackableAuras and SpellRuntime().TrackableAuras[specKey]
            if type(trackable) ~= "table" or #trackable == 0 then return false, "That spell-indicator spec has no ordered spell list." end
            local si = SpellDB(scope)
            si.sortOrder = type(si.sortOrder) == "table" and si.sortOrder or {}
            local order = si.sortOrder[specKey]
            if type(order) ~= "table" or #order == 0 then
                order = {}
                for i = 1, #trackable do order[#order + 1] = trackable[i].name end
                si.sortOrder[specKey] = order
            end
            local from
            for i = 1, #order do if order[i] == auraName then from = i; break end end
            if not from then return false, "I don't see that aura in the spell indicator order." end
            local target = tonumber(args and args.position) or from
            if target < 1 then target = 1 end
            if target > #order then target = #order end
            table.remove(order, from)
            if target > from then target = target - 1 end
            table.insert(order, target, auraName)
            ApplySpell(scope)
            return true, "Done. Moved " .. tostring(display or auraName) .. " to spell indicator slot " .. tostring(target) .. "."
        end,
    })

    local RegisterSpellIndicatorCornerResetActions = A.GroupFramesRegistry and A.GroupFramesRegistry.RegisterSpellIndicatorCornerResetActions
    if type(RegisterSpellIndicatorCornerResetActions) == "function" then
        RegisterSpellIndicatorCornerResetActions(ctx)
    end
end
