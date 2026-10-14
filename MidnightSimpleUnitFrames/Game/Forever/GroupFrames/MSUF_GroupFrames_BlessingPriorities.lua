-- Ordered blessing choices share the existing coverage event route and state.
-- No aura reads, timers or frame callbacks belong to this policy module.
local _, MSUF = ...
local IS_FOREVER = MSUF.Client.IsForever == true
if not IS_FOREVER then return end
local B = {}
MSUF.GF.BlessingPriorities = B
-- Read-only fallbacks keep old profiles unchanged until an option is edited.
local DEFAULTS = {
    buffCoverageBlessingPriorities = false,
    buffCoverageBlessingTank1 = 3,
    buffCoverageBlessingTank2 = 0,
    buffCoverageBlessingTank3 = 0,
    buffCoverageBlessingHealer1 = 2,
    buffCoverageBlessingHealer2 = 0,
    buffCoverageBlessingHealer3 = 0,
    buffCoverageBlessingDPS1 = 4,
    buffCoverageBlessingDPS2 = 0,
    buffCoverageBlessingDPS3 = 0,
    buffCoverageBlessingWARRIOR = 0,
    buffCoverageBlessingPALADIN = 0,
    buffCoverageBlessingHUNTER = 0,
    buffCoverageBlessingROGUE = 0,
    buffCoverageBlessingPRIEST = 0,
    buffCoverageBlessingSHAMAN = 0,
    buffCoverageBlessingMAGE = 0,
    buffCoverageBlessingWARLOCK = 0,
    buffCoverageBlessingDRUID = 0,
}
B.Defaults = DEFAULTS
-- Rank IDs already established by the Forever buff-coverage catalog. Unknown
-- variants retain the legacy any-blessing behavior, never a guessed family.
local SPELLS = {
    { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 },
    { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 },
    { 20217, 25898, 1213408 }, { 1038, 25895 }, { 19977, 19978, 19979, 25890, 26650 }, { 20911, 25899 },
}
local bySpell, known, textures, readable, observed = {}, {}, {}, {}, {}
for family = 1, #SPELLS do
    for _, spell in ipairs(SPELLS[family]) do bySpell[spell] = family end
end
local ROLE_FIELDS = {}
for role, suffix in pairs({ TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }) do
    ROLE_FIELDS[role] = {}
    for i = 1, 3 do ROLE_FIELDS[role][i] = "buffCoverageBlessing" .. suffix .. i end
end
local CLASS_FIELDS = {}
for _, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    CLASS_FIELDS[class] = "buffCoverageBlessing" .. class
end
local SCOPES = { "party", "raid" }
function B.Sync()
    local enabled = false
    for _, scope in ipairs(SCOPES) do
        local conf = MSUF.GF.GetConf(scope)
        if conf and conf.buffCoverageEnabled and conf.buffCoverageBlessingPriorities then enabled = true end
    end
    local changed = enabled ~= B.enabled
    B.enabled = enabled
    return changed
end
local function Secret(value) return issecretvalue and issecretvalue(value) == true end

function B.Init(state)
    state.blessings, state.blessingInstances = { 0, 0, 0, 0, 0, 0 }, {}
end
function B.Reset(state)
    for i = 1, #SPELLS do state.blessings[i] = 0 end
    wipe(state.blessingInstances)
end
function B.Add(state, spell, instance)
    if not B.enabled then return false end
    local family = bySpell[spell]
    if not family or instance == nil or state.blessingInstances[instance] then return false end
    state.blessingInstances[instance] = family
    state.blessings[family] = state.blessings[family] + 1
    return state.blessings[family] == 1
end
function B.Remove(state, instance)
    if not B.enabled then return false end
    local family = state.blessingInstances[instance]
    if not family then return false end
    state.blessingInstances[instance] = nil
    state.blessings[family] = math.max(0, state.blessings[family] - 1)
    return state.blessings[family] == 0
end

-- Learn/spellbook and roster refreshes are cold. Availability is computed once
-- there, never while painting a member or processing UNIT_AURA.
function B.RefreshKnown()
    if not B.enabled then return end
    local _, class = UnitClass("player")
    B.playerPaladin = not Secret(class) and class == "PALADIN"
    local book = C_SpellBook
    local secrets, levels = C_Secrets, Enum and Enum.SecrecyLevel
    local classify = secrets and secrets.GetSpellAuraSecrecy
    for family, spells in ipairs(SPELLS) do
        readable[family] = classify ~= nil and levels ~= nil
        for _, spell in ipairs(spells) do
            if not classify or not levels or classify(spell) ~= levels.NeverSecret then readable[family] = false end
        end
    end
    for family, spells in ipairs(SPELLS) do
        known[family] = not B.playerPaladin
        if B.playerPaladin and book and book.FindSpellBookSlotForSpell then
            for _, spell in ipairs(spells) do
                local slot = book.FindSpellBookSlotForSpell(spell, true, false)
                if not Secret(slot) and type(slot) == "number" and slot > 0 then
                    known[family] = true
                    break
                end
            end
        end
    end
end

local function Choice(value)
    return type(value) == "number" and value >= 1 and value <= #SPELLS and value == math.floor(value) and value or nil
end
function B.Desired(conf, role, class)
    local classField = class and CLASS_FIELDS[class]
    local override = classField and Choice(conf[classField])
    if override then return known[override] and override or nil end
    local fields = ROLE_FIELDS[role] or ROLE_FIELDS.DAMAGER
    for i = 1, 3 do
        local value = conf[fields[i]]
        if value == nil then value = DEFAULTS[fields[i]] end
        local family = Choice(value)
        if family and known[family] then return family end
    end
end
-- One reused presence buffer for the existing restricted read. A seen family
-- can arrive; a loss is proven only if every rank of that family is NeverSecret.
function B.BeginReadable()
    for i = 1, #SPELLS do observed[i] = false end
end
function B.SeeReadable(spell)
    local family = bySpell[spell]
    if family then observed[family] = true end
end
function B.ApplyReadable(state)
    local changed = false
    for family = 1, #SPELLS do
        local count = state.blessings[family]
        if observed[family] and count == 0 then
            state.blessings[family], changed = 1, true
        elseif readable[family] and not observed[family] and count > 0 then
            state.blessings[family], changed = 0, true
        end
    end
    return changed
end
function B.Missing(state, family)
    return family ~= nil and state.blessings[family] == 0
end
function B.Texture(family)
    if textures[family] == nil then
        local api = C_Spell
        local value = api and api.GetSpellTexture and api.GetSpellTexture(SPELLS[family][1])
        textures[family] = not Secret(value) and value or false
    end
    return textures[family] or "Interface\\Icons\\INV_Misc_QuestionMark"
end
