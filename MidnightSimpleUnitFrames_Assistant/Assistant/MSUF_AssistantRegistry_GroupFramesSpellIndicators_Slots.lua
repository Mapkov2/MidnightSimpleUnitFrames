-- Assistant GroupFrames spell/corner indicator slot helpers.
-- Loaded before the spell indicator core builds its helper context.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.BuildSpellIndicatorSlotHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local Assistant = ctx.A or A
    local GroupDB = ctx.GroupDB
    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local CI_SLOTS = ctx.CI_SLOTS or {}

    if type(GroupDB) ~= "function" or type(AddAliasesForUnit) ~= "function" then return nil end

    local function LookupKey(value)
        return tostring(value or ""):lower():gsub("[^%w]+", "")
    end

    local function CustomConfig(scope, slotKey, create)
        local conf = GroupDB(scope)
        local key = "ciCustom" .. tostring(slotKey or "")
        if create and type(conf[key]) ~= "table" then conf[key] = { spells = "", mode = "present", filter = "HELPFUL|PLAYER", r = 0.40, g = 1.00, b = 0.40 } end
        return type(conf[key]) == "table" and conf[key] or nil
    end

    local function ActivateCustom(scope, slotKey)
        GroupDB(scope)["ciSlot" .. tostring(slotKey or "")] = "custom"
    end

    local SLOT_LOOKUP = {}
    for i = 1, #CI_SLOTS do
        local slot = CI_SLOTS[i]
        SLOT_LOOKUP[LookupKey(slot.key)] = slot
        SLOT_LOOKUP[LookupKey(slot.label)] = slot
        for j = 1, #(slot.terms or {}) do SLOT_LOOKUP[LookupKey(slot.terms[j])] = slot end
    end

    local function ResolveSlot(value)
        local compact = LookupKey(value)
        if SLOT_LOOKUP[compact] then return SLOT_LOOKUP[compact] end
        for key, slot in pairs(SLOT_LOOKUP) do if #key >= 3 and compact:find(key, 1, true) then return slot end end
        return nil
    end

    Assistant.ResolveGroupCornerSlot = ResolveSlot

    local SLOT_SUFFIX_ALIASES = {
        ["indicator"] = { "indikator", "ecken indikator" },
        ["category"] = { "kategorie", "typ" },
        ["custom spells"] = { "zauber", "zauber ids", "spell ids", "custom zauber" },
        ["custom spell ids"] = { "zauber ids", "zauber id", "custom zauber ids" },
        ["spell ids"] = { "zauber ids", "zauber id" },
        ["custom mode"] = { "modus", "custom modus" },
        ["custom when"] = { "wenn", "anzeige wenn" },
        ["custom filter"] = { "filter", "custom filter", "aura filter" },
        ["custom aura filter"] = { "aura filter", "filter" },
        ["custom color"] = { "farbe", "custom farbe" },
        ["spell color"] = { "zauber farbe", "zauberfarbe" },
    }

    local function AddSlotAliases(out, scope, slot, suffix)
        local suffixes = { suffix }
        if suffix and SLOT_SUFFIX_ALIASES[suffix] then
            for i = 1, #SLOT_SUFFIX_ALIASES[suffix] do suffixes[#suffixes + 1] = SLOT_SUFFIX_ALIASES[suffix][i] end
        end
        for i = 1, #(slot.terms or {}) do
            local term = slot.terms[i]
            if suffix then
                for j = 1, #suffixes do
                    local s = suffixes[j]
                    AddAliasesForUnit(out, scope, term .. " " .. s)
                    AddAliasesForUnit(out, scope, s .. " " .. term)
                end
            else
                AddAliasesForUnit(out, scope, term)
            end
        end
    end

    return {
        CustomConfig = CustomConfig,
        ActivateCustom = ActivateCustom,
        ResolveSlot = ResolveSlot,
        AddSlotAliases = AddSlotAliases,
    }
end
