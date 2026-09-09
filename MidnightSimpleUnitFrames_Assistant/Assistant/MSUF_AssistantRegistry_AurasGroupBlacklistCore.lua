-- Assistant group aura direct blacklist helper core.
-- Loaded before the category core; consumed by the group aura category helper factory.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.BuildGroupAuraBlacklistCore(ctx)
    if type(ctx) ~= "table" then return nil end

    local ARef = ctx.A or A
    local AuraModel = ctx.AuraModel
    local GFAuraCategoryScope = ctx.GFAuraCategoryScope
    local GFAuraCategoryLane = ctx.GFAuraCategoryLane
    local GFAuraGroup = ctx.GFAuraGroup

    if type(AuraModel) ~= "function" then return nil end
    if type(GFAuraCategoryScope) ~= "function" or type(GFAuraCategoryLane) ~= "function" then return nil end

    local function AddGFAuraBlacklistSpell(scope, lane, value)
        local Model = AuraModel()
        if not (Model and type(Model.AddGroupBlacklistSpell) == "function") then return false end
        return Model.AddGroupBlacklistSpell(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane), value)
    end

    local function RemoveGFAuraBlacklistSpell(scope, lane, value)
        local Model = AuraModel()
        if not (Model and type(Model.RemoveGroupBlacklistSpell) == "function") then return false end
        return Model.RemoveGroupBlacklistSpell(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane), value)
    end

    local function ClearGFAuraBlacklistSpells(scope, lane)
        local Model = AuraModel()
        if not (Model and type(Model.ClearGroupBlacklistSpells) == "function") then return 0 end
        return Model.ClearGroupBlacklistSpells(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane))
    end

    local function GFAuraBlacklistSummary(scope, lane)
        -- The model summary materialises <scope>.auras (renderer = "CUSTOM")
        -- even for an empty list; answer the empty case from the saved table.
        if type(GFAuraGroup) == "function" then
            local group = GFAuraGroup(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane))
            local blacklist = type(group) == "table" and group.blacklist or nil
            local spells = type(blacklist) == "table" and blacklist.spells or nil
            local hasEntry = false
            if type(spells) == "table" then
                for _, enabled in pairs(spells) do
                    if enabled == true then hasEntry = true; break end
                end
            end
            if not hasEntry then return "No blacklisted spells." end
        end
        local Model = AuraModel()
        if Model and type(Model.GroupBlacklistSummary) == "function" then
            return Model.GroupBlacklistSummary(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane))
        end
        return "The hidden spell list has no entries."
    end

    local function AddGFAuraBlacklistPreset(scope, lane, preset)
        local Model = AuraModel()
        if not (Model and type(Model.AddGroupBlacklistPresetGroup) == "function") then return 0 end
        return Model.AddGroupBlacklistPresetGroup(GFAuraCategoryScope(scope), GFAuraCategoryLane(lane), preset)
    end

    ARef.AddGroupAuraBlacklistSpell = AddGFAuraBlacklistSpell
    ARef.RemoveGroupAuraBlacklistSpell = RemoveGFAuraBlacklistSpell
    ARef.ClearGroupAuraBlacklistSpells = ClearGFAuraBlacklistSpells
    ARef.GroupAuraBlacklistSummary = GFAuraBlacklistSummary
    ARef.AddGroupAuraBlacklistPreset = AddGFAuraBlacklistPreset

    return {
        AddGFAuraBlacklistSpell = AddGFAuraBlacklistSpell,
        RemoveGFAuraBlacklistSpell = RemoveGFAuraBlacklistSpell,
        ClearGFAuraBlacklistSpells = ClearGFAuraBlacklistSpells,
        GFAuraBlacklistSummary = GFAuraBlacklistSummary,
        AddGFAuraBlacklistPreset = AddGFAuraBlacklistPreset,
    }
end
