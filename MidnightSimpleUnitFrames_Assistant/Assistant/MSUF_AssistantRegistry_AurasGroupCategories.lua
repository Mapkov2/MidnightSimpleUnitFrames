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

    local function AddAlias(out, value)
        if type(value) == "string" and value ~= "" then out[#out + 1] = value end
    end

    local function AddGroupNoTimerAliases(out, scope, laneInfo)
        local lanePlural = laneInfo.plural:lower()
        local scopes = scope == "raid" and { "raid", "mythic raid" } or { "party" }
        for i = 1, #scopes do
            local scopeName = scopes[i]
            AddAlias(out, scopeName .. " " .. lanePlural .. " with no timer")
            AddAlias(out, scopeName .. " " .. lanePlural .. " without a timer")
            AddAlias(out, scopeName .. " " .. lanePlural .. " without timers")
            AddAlias(out, scopeName .. " " .. lanePlural .. " that have no timer")
            AddAlias(out, scopeName .. " " .. lanePlural .. " with no duration")
            AddAlias(out, scopeName .. " " .. lanePlural .. " without a duration")
            AddAlias(out, scopeName .. " permanent " .. lanePlural)
            AddAlias(out, "hide permanent " .. scopeName .. " " .. lanePlural)
        end
    end

    for _, scope in ipairs(GF_AURA_CATEGORY_SCOPES) do
        for _, laneInfo in ipairs(AURA_LANES) do
            local lane = laneInfo.key
            if type(AuraModel) == "function" then
                local settingScope, settingLane = scope, lane
                local aliases = {}
                AddAliasesForUnit(aliases, settingScope, "hide permanent " .. laneInfo.plural:lower())
                AddAliasesForUnit(aliases, settingScope, "hide permanent auras for " .. laneInfo.plural:lower())
                AddGroupNoTimerAliases(aliases, settingScope, laneInfo)
                Registry:RegisterSetting({
                    key = "gf_" .. settingScope .. ".auras." .. settingLane .. ".blacklist.hidePermanent",
                    label = GFAuraCategoryScopeLabel(settingScope) .. " " .. GFAuraCategoryLaneLabel(settingLane) .. " Hide Permanent Auras",
                    category = GFAuraCategoryScopeLabel(settingScope) .. " / Group Auras",
                    page = "gf_auras",
                    description = settingScope == "raid"
                        and ("Hides Raid and Mythic Raid " .. laneInfo.plural .. " that have no finite duration (also called permanent or no-timer auras). The Auras menu owns this as one aggregate Raid / Mythic Raid rule. It does not disable the lane or change its native Filter choice.")
                        or ("Hides Party " .. laneInfo.plural .. " that have no finite duration (also called permanent or no-timer auras). It does not disable the lane or change its native Filter choice."),
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
                    -- settingScope is the bare scope ("party"/"raid"); the "gf_"
                    -- prefix is added when the key is built. Comparing against
                    -- "gf_party" never matched, so every scope got "raid" wording
                    -- and Party collided with Raid on the same alias -- two hits,
                    -- which FullPhraseMatch rejects rather than guess between.
                    local shortScope = tostring(settingScope)
                    local exactAliases = {}
                    local function AddExact(candidate)
                        candidate = tostring(candidate or ""):lower()
                        local count = 0
                        for _ in candidate:gsub("[^%w]+", " "):gmatch("%S+") do count = count + 1 end
                        if count >= 3 and count <= 8 then exactAliases[#exactAliases + 1] = candidate end
                    end
                    AddExact(shortScope .. " " .. GFAuraCategoryLaneLabel(lane) .. " hidden category " .. label)
                    AddExact(shortScope .. " hidden category " .. label)
                    Registry:RegisterSetting({
                        key = "gf_" .. settingScope .. ".auras." .. settingLane .. ".blacklistCats." .. tostring(settingCatKey),
                        label = GFAuraCategoryScopeLabel(settingScope) .. " " .. GFAuraCategoryLaneLabel(settingLane) .. " Hidden Category " .. label,
                        category = GFAuraCategoryScopeLabel(settingScope) .. " / Group Auras",
                        unit = settingScope,
                        frameType = "groupAura",
                        attribute = "gfAura" .. GFAuraCategoryLaneLabel(settingLane) .. "CategoryBlacklist",
                        type = "boolean",
                        aliases = aliases,
                        exactAliases = exactAliases,
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
