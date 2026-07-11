-- Assistant group aura category blacklist setting registry.
-- Loaded before MSUF_AssistantRegistry_AurasGroupSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local A = MSUF.Assistant or {}
MSUF.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterGroupAuraCategorySettings(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AuraModel = ctx.AuraModel
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local GFAuraCategoryValues = ctx.GFAuraCategoryValues
    local GFAuraCategoryLabel = ctx.GFAuraCategoryLabel
    local GFAuraCategoryScopeLabel = ctx.GFAuraCategoryScopeLabel
    local GFAuraCategoryLaneLabel = ctx.GFAuraCategoryLaneLabel
    local ReadGFAuraCategorySetting = ctx.ReadGFAuraCategorySetting
    local WriteGFAuraCategoryState = ctx.WriteGFAuraCategoryState
    local SameGFAuraCategoryState = ctx.SameGFAuraCategoryState
    local ApplyGFAuraCategory = ctx.ApplyGFAuraCategory

    if not (Registry and type(Registry.RegisterSetting) == "function") then return end
    if type(AddAliasesForUnit) ~= "function" or type(GFAuraCategoryValues) ~= "function" then return end
    if type(GFAuraCategoryLabel) ~= "function" or type(GFAuraCategoryScopeLabel) ~= "function" then return end
    if type(GFAuraCategoryLaneLabel) ~= "function" then return end
    if type(ReadGFAuraCategorySetting) ~= "function" or type(WriteGFAuraCategoryState) ~= "function" then return end
    if type(SameGFAuraCategoryState) ~= "function" or type(ApplyGFAuraCategory) ~= "function" then return end

    local registerMutableLegacyCategorySettings = true
    if not registerMutableLegacyCategorySettings then
        -- The native 12.1 group aura backend does not consume addon category
        -- blacklist data. Keep this legacy data out of generic setting mutation.
        return
    end

    local GF_AURA_CATEGORY_SCOPES = ctx.GF_AURA_CATEGORY_SCOPES or {}
    local AURA_LANES = ctx.AURA_LANES or {}
    local categories = GFAuraCategoryValues()

    for _, scope in ipairs(GF_AURA_CATEGORY_SCOPES) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            if type(AuraModel) == "function" then
                local settingScope, settingLane = scope, lane
                local aliases = {}
                AddAliasesForUnit(aliases, settingScope, "hide permanent " .. laneInfo.plural:lower())
                AddAliasesForUnit(aliases, settingScope, "hide permanent auras for " .. laneInfo.plural:lower())
                Registry:RegisterSetting({
                    key = "gf_" .. settingScope .. ".auras." .. settingLane .. ".blacklist.hidePermanent",
                    label = GFAuraCategoryScopeLabel(settingScope) .. " " .. GFAuraCategoryLaneLabel(settingLane) .. " Hide Permanent Auras",
                    category = GFAuraCategoryScopeLabel(settingScope) .. " / Group Auras",
                    unit = settingScope,
                    frameType = "groupAura",
                    attribute = "gfAura" .. GFAuraCategoryLaneLabel(settingLane) .. "BlacklistHidePermanent",
                    type = "boolean",
                    aliases = aliases,
                    get = function()
                        local Model = AuraModel()
                        return Model and Model.ReadGroupBlacklistHidePermanent(settingScope, settingLane) == true or false
                    end,
                    set = function(value)
                        local Model = AuraModel()
                        if Model then Model.WriteGroupBlacklistHidePermanent(settingScope, settingLane, value == true) end
                    end,
                    apply = function() ApplyGFAuraCategory(settingScope) end,
                    combatSafe = false,
                })
            end
            for i = 1, #categories do
                local cat = categories[i]
                local catKey = cat and (cat.key or cat.value)
                if catKey then
                    local settingScope, settingLane, settingCatKey = scope, lane, catKey
                    local label = GFAuraCategoryLabel(catKey)
                    local aliases = {}
                    AddAliasesForUnit(aliases, scope, laneInfo.plural:lower() .. " category blacklist " .. label)
                    AddAliasesForUnit(aliases, scope, laneInfo.plural:lower() .. " public category blacklist " .. label)
                    AddAliasesForUnit(aliases, scope, "blacklist " .. label .. " " .. laneInfo.plural:lower() .. " category")
                    Registry:RegisterSetting({
                        key = "gf_" .. settingScope .. ".auras." .. settingLane .. ".blacklistCats." .. tostring(settingCatKey),
                        label = GFAuraCategoryScopeLabel(settingScope) .. " " .. GFAuraCategoryLaneLabel(settingLane) .. " Hidden Category " .. label,
                        category = GFAuraCategoryScopeLabel(settingScope) .. " / Group Auras",
                        unit = settingScope,
                        frameType = "groupAura",
                        attribute = "gfAura" .. GFAuraCategoryLaneLabel(settingLane) .. "CategoryBlacklist",
                        type = "boolean",
                        aliases = aliases,
                        get = function() return ReadGFAuraCategorySetting(settingScope, settingLane, settingCatKey) end,
                        set = function(value) WriteGFAuraCategoryState(settingScope, settingLane, settingCatKey, value) end,
                        sameValue = SameGFAuraCategoryState,
                        apply = function() ApplyGFAuraCategory(settingScope) end,
                        combatSafe = false,
                    })
                end
            end
        end
    end
end
