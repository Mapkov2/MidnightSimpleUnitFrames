-- Aura blacklist summary assistant action registration.
-- Loaded before MSUF_AssistantRegistry_AurasActions_Blacklist.lua; the main blacklist registry preserves action order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

function A.AurasRegistry.RegisterBlacklistSummaryAction(ctx)
    if type(ctx) ~= "table" then return end

    local Registry = ctx.Registry
    local AuraModel = ctx.AuraModel
    local AuraScopeLabel = ctx.AuraScopeLabel
    local ParseAuraBlacklistSummaryAliasArgs = ctx.ParseAuraBlacklistSummaryAliasArgs

    if not (Registry and type(Registry.RegisterAction) == "function") then return end
    if type(AuraModel) ~= "function" or type(AuraScopeLabel) ~= "function" then return end
    if type(ParseAuraBlacklistSummaryAliasArgs) ~= "function" then return end

    Registry:RegisterAction({
        key = "aura_blacklist_summary",
        label = "Show Hidden Aura Spells",
        type = "auras",
        combatSafe = true,
        aliases = {
            "show aura blacklist", "list aura blacklist", "aura blacklist summary",
            "zeige aura blacklist", "anzeigen aura blacklist", "liste aura blacklist", "aura blacklist anzeigen",
            "current aura blacklist", "what is aura blacklist",
            "show player aura blacklist", "show target aura blacklist", "show focus aura blacklist", "show boss aura blacklist",
            "zeige player aura blacklist", "zeige target aura blacklist", "zeige focus aura blacklist", "zeige boss aura blacklist",
            "player aura blacklist anzeigen", "target aura blacklist anzeigen", "focus aura blacklist anzeigen", "boss aura blacklist anzeigen",
            "show current player aura blacklist", "show current target aura blacklist",
            "show current focus aura blacklist", "show current boss aura blacklist",
            "list player aura blacklist", "list target aura blacklist", "list focus aura blacklist", "list boss aura blacklist",
            "current player aura blacklist", "current target aura blacklist",
            "current focus aura blacklist", "current boss aura blacklist",
            "what is player aura blacklist", "what is target aura blacklist",
            "what is focus aura blacklist", "what is boss aura blacklist",
            "player aura blacklist summary", "target aura blacklist summary",
            "focus aura blacklist summary", "boss aura blacklist summary",
        },
        parseAliasArgs = ParseAuraBlacklistSummaryAliasArgs,
        run = function(args)
            local Model = AuraModel()
            if not (Model and type(Model.BlacklistSummary) == "function") then return false, "Open Aura Filters first so I can show the hidden-aura list." end
            local scope = args and args.scope
            if scope ~= "player" and scope ~= "target" and scope ~= "focus" and scope ~= "boss" then
                return false, "Choose Player, Target, Focus, or Boss so I know which native hidden-aura list to show."
            end
            local lane = args and args.lane or "both"
            if lane == "buff" or lane == "debuff" then
                return true, AuraScopeLabel(scope) .. " " .. lane .. " blacklist:\n" .. tostring(Model.BlacklistSummary(scope, lane))
            end
            return true, AuraScopeLabel(scope) .. " buff blacklist:\n" .. tostring(Model.BlacklistSummary(scope, "buff"))
                .. "\n\n" .. AuraScopeLabel(scope) .. " debuff blacklist:\n" .. tostring(Model.BlacklistSummary(scope, "debuff"))
        end,
    })
end
