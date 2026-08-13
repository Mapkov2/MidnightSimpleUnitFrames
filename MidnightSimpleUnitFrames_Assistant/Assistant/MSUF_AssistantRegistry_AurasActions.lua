local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

-- Auras assistant action domain.
local ctx = A.AurasRegistry and A.AurasRegistry.Actions
if type(ctx) ~= "table" then return end

local Registry = ctx.Registry
A = ctx.A or A
M = ctx.M or M
local AuraScopeFromArg = ctx.AuraScopeFromArg
local AuraScopeLabel = ctx.AuraScopeLabel
local AuraModel = ctx.AuraModel
local ApplyAura = ctx.ApplyAura

if not (Registry and type(Registry.RegisterAction) == "function") then return end
if type(AuraScopeFromArg) ~= "function" or type(AuraScopeLabel) ~= "function" then return end
if type(AuraModel) ~= "function" or type(ApplyAura) ~= "function" then return end
local BuildActionParsers = A.AurasRegistry and A.AurasRegistry.BuildActionParsers
local ActionParsers = type(BuildActionParsers) == "function" and BuildActionParsers({
    A = A,
    M = M,
    AuraScopeFromArg = AuraScopeFromArg,
}) or nil
if type(ActionParsers) ~= "table" then return end

local ParseAuraBlacklistAddSpellAliasArgs = ActionParsers.ParseAuraBlacklistAddSpellAliasArgs
local ParseAuraBlacklistRemoveSpellAliasArgs = ActionParsers.ParseAuraBlacklistRemoveSpellAliasArgs
local ParseAuraBlacklistClearAliasArgs = ActionParsers.ParseAuraBlacklistClearAliasArgs
local ParseAuraBlacklistPresetAliasArgs = ActionParsers.ParseAuraBlacklistPresetAliasArgs
local ParseAuraBlacklistSummaryAliasArgs = ActionParsers.ParseAuraBlacklistSummaryAliasArgs
local ParseAuraCustomWhitelistAddAliasArgs = ActionParsers.ParseAuraCustomWhitelistAddAliasArgs
local ParseAuraCustomWhitelistRemoveAliasArgs = ActionParsers.ParseAuraCustomWhitelistRemoveAliasArgs
local ParseAuraCustomWhitelistClearAliasArgs = ActionParsers.ParseAuraCustomWhitelistClearAliasArgs
local ParseAuraCustomWhitelistSummaryAliasArgs = ActionParsers.ParseAuraCustomWhitelistSummaryAliasArgs
Registry:RegisterAction({
    key = "reset_aura_custom_container",
    label = "Reset Custom Aura Container",
    description = "Returns one unit-frame Custom Aura container to its defaults, including its whitelist, filters, layout, and appearance.",
    page = "auras3",
    type = "reset",
    combatSafe = false,
    confirmRequired = true,
    aliases = {
        "reset custom aura container", "reset custom aura", "reset custom aura slot",
    },
    parseAliasArgs = function(text)
        local normalized = tostring(text or ""):lower()
        if not normalized:find("reset", 1, true)
            or not normalized:find("custom", 1, true)
            or not normalized:find("aura", 1, true)
        then
            return false
        end
        local parsed = {}
        for _, scope in ipairs({ "player", "target", "focus", "boss" }) do
            if normalized:find("%f[%a]" .. scope .. "%f[%A]") then
                parsed.scope = scope
                break
            end
        end
        parsed.index = tonumber(normalized:match("custom%s+aura%s*([123])")
            or normalized:match("container%s*([123])")
            or normalized:match("slot%s*([123])"))
        return parsed, { summary = "Resets one unit-frame Custom Aura container to its defaults." }
    end,
    run = function(args)
        local scope = tostring(args and args.scope or ""):lower()
        if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then
            return false, "Choose Player, Target, Focus, or Boss so I know which Custom Aura container to reset."
        end

        local model = AuraModel()
        if not (model and type(model.ResetCustomContainer) == "function") then
            return false, "Custom Aura containers are not available in the current context."
        end

        local index = tonumber(args and args.index)
        local maxIndex = type(model.CustomContainerMax) == "function" and tonumber(model.CustomContainerMax()) or 3
        maxIndex = maxIndex or 3
        if not index or index % 1 ~= 0 or index < 1 or index > maxIndex then
            return false, "Choose a Custom Aura container from 1 to " .. tostring(maxIndex) .. "."
        end

        model.ResetCustomContainer(scope, index)
        ApplyAura(scope, "MSUF_ASSISTANT_AURA_CUSTOM_CONTAINER_RESET")
        local pageKey = "uf_" .. scope
        local rebuildCurrentPage = M.activeKey == pageKey and type(M.SelectPage) == "function"
        if type(M.InvalidatePage) == "function" then M.InvalidatePage(pageKey) end
        if rebuildCurrentPage then
            M.activeKey = nil
            M.SelectPage(pageKey)
        elseif type(M.Refresh) == "function" then
            M.Refresh()
        end
        return true, "Done. Reset " .. AuraScopeLabel(scope) .. " Custom Aura " .. tostring(index) .. "."
    end,
})

local RegisterBlacklistActions = A.AurasRegistry and A.AurasRegistry.RegisterBlacklistActions
if type(RegisterBlacklistActions) == "function" then
    RegisterBlacklistActions({
        Registry = Registry,
        AuraModel = AuraModel,
        ApplyAura = ApplyAura,
        AuraScopeLabel = AuraScopeLabel,
        ParseAuraBlacklistAddSpellAliasArgs = ParseAuraBlacklistAddSpellAliasArgs,
        ParseAuraBlacklistRemoveSpellAliasArgs = ParseAuraBlacklistRemoveSpellAliasArgs,
        ParseAuraBlacklistClearAliasArgs = ParseAuraBlacklistClearAliasArgs,
        ParseAuraBlacklistPresetAliasArgs = ParseAuraBlacklistPresetAliasArgs,
        ParseAuraBlacklistSummaryAliasArgs = ParseAuraBlacklistSummaryAliasArgs,
        ParseAuraCustomWhitelistAddAliasArgs = ParseAuraCustomWhitelistAddAliasArgs,
        ParseAuraCustomWhitelistRemoveAliasArgs = ParseAuraCustomWhitelistRemoveAliasArgs,
        ParseAuraCustomWhitelistClearAliasArgs = ParseAuraCustomWhitelistClearAliasArgs,
        ParseAuraCustomWhitelistSummaryAliasArgs = ParseAuraCustomWhitelistSummaryAliasArgs,
    })
end
