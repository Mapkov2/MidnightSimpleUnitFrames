-- Group Spell Icons must hand Forever's friendly Weakened Soul slot to the
-- native property filters, including for previously saved custom ID entries.
local root, flavor = assert(arg[1]):gsub("/$", ""), arg[2] or "Forever"
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.MAX_BOSS_FRAMES = 5
    world.env.C_Spell = setmetatable({ GetSpellName = function() return "" end }, { __index = world.env.C_Spell })
end })
local GF, SI = h.GF, h.GF.SpellIndicators
local runtime = h.core.MSUF_Auras3.SpellIndicators
local isForever = flavor == "Forever"
local specKey = isForever and "ClassicPriest" or "DisciplinePriest"
local id = 6788

local function Compile(unit, scope, auraName, entry)
    local conf = { spellIndicators = { enabled = true, spec = specKey,
        specs = { [specKey] = { [auraName] = entry } } } }
    local compiled = GF.CompileSpellIndicators(conf, scope)
    for _, item in ipairs(compiled.items) do
        if item.auraName == auraName then
            local slots = runtime.CompileSlots(unit, { enabled = true, items = { item } })
            return assert(slots.slots[1], "spell lost its native slot")
        end
    end
end

local function CheckProperties(slot, own)
    local filters = assert(slot.candidateFilters)
    assert(filters.includeSpellIDs == nil, "friendly harmful exact-ID filter rejects Weakened Soul")
    assert(filters.maxDuration == 15.5 and filters.isBossOrRoleAura == false)
    assert(filters.excludeDispelTypes.Magic and filters.excludeDispelTypes.Poison)
    assert(filters.canApplyAura == nil, "native filter must not require canApplyAura")
    assert(slot.identityCandidateMode == nil, "slot is hidden on friendly units")
    assert(slot.visual == "icon" and slot.showCooldownSwipe == true)
    if own then
        assert(slot.nativeFilter:find("|PLAYER", 1, true))
        assert(filters.isFromPlayerOrPlayerPet == nil)
    else
        assert(not slot.nativeFilter:find("|PLAYER", 1, true))
        assert(filters.isFromPlayerOrPlayerPet == true)
    end
end

if isForever then
    local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local menu = MenuWorld.Open(root, flavor, { page = "gf_auras", world = h.world })
    local M, page = menu.M, menu.M.GroupPage
    local entry = assert(M.cache.gf_auras)
    assert(entry.sections.si)._msuf2CollapsibleEntry.SetOpenImmediate(true)
    menu:RunTimers()
    local duplicateToggle
    for _, widget in ipairs(entry.searchWidgets) do
        local schema = widget._msuf2ControlSchema
        if schema and schema.id:match("spell%.selected%.auto_blacklist$") then duplicateToggle = widget end
    end
    assert(duplicateToggle, "duplicate icon control is missing")
    for _, scope in ipairs({ "party", "raid" }) do
        local conf = page.Conf(scope)
        conf.enabled = true
        conf.spellIndicators = { enabled = true, spec = specKey, specs = {} }
        local selected
        for _, option in ipairs(page.SpellAuraValues(scope)) do
            if option.value == "WeakenedSoul" then selected = option end
        end
        assert(selected and selected.text == "Weakened Soul", scope .. " picker has no readable Weakened Soul label")
        page.SetCurrentSpellAura(scope, "WeakenedSoul")
        assert(page.CurrentSpellAura(scope) == "WeakenedSoul")
        local saved = assert(page.CurrentSpellConfig(scope, true))
        assert(saved.enabled == false and saved.onlyOwn == false, scope .. " first enable must support other priests")
        saved.enabled, saved.autoBlacklist = true, true
        local renew = conf.spellIndicators.specs[specKey].Renew or {}
        renew.enabled, renew.autoBlacklist = true, true
        conf.spellIndicators.specs[specKey].Renew = renew
        conf.spellIndicators.specs[specKey]["6788"] = { enabled = true, autoBlacklist = true, custom = true, spells = "6788" }
        M.SetMenuStateValue("gfScope", scope)
        M.Refresh()
        assert(not duplicateToggle:IsEnabled() and not duplicateToggle:GetChecked(),
            scope .. " Weakened Soul leaves duplicate suppression available")
        local reason = M.Widgets.DisabledReasonText(duplicateToggle)
        local hover = duplicateToggle._msuf2LabelHit or duplicateToggle
        assert(reason and reason:find("workaround", 1, true) and hover._msuf2MouseEnabledStateApplied,
            scope .. " disabled duplicate control has no hover explanation")
        local env, tooltipLine = menu.world.env
        local previousTip = env.GameTooltip
        local function Noop() end
        env.GameTooltip = { SetOwner = Noop, SetText = Noop, Show = Noop, Hide = Noop,
            AddLine = function(_, line) tooltipLine = line end }
        hover:GetScript("OnEnter")(hover)
        hover:GetScript("OnLeave")(hover)
        env.GameTooltip = previousTip
        assert(tooltipLine == reason, scope .. " disabled control did not show its explanation")

        GF.InvalidateCompiledSpecs(scope)
        local blacklist = assert(GF.GetCompiledSpec(scope).auras.buffBlacklistHash)
        assert(not blacklist[id] and blacklist[139], scope .. " ignored duplicate setting leaked into the buff filter")

        page.SetCurrentSpellAura(scope, "Renew")
        M.Refresh()
        assert(duplicateToggle:IsEnabled() and duplicateToggle:GetChecked()
            and not M.Widgets.DisabledReasonText(duplicateToggle), scope .. " switching spells did not restore duplicate suppression")
    end
    assert(SI.SpellIDs[specKey].WeakenedSoul == id, "Weakened Soul absent from the Forever spell picker registry")
    local found
    for _, spell in ipairs(SI.TrackableAuras[specKey]) do
        if spell.name == "WeakenedSoul" then found = spell end
    end
    assert(found and found.display ~= "", "Weakened Soul absent from the spell picker")
    assert(not Compile("party1", "party", "WeakenedSoul", nil), "preset is opt-in")
    local party = assert(Compile("party1", "party", "WeakenedSoul", { enabled = true }))
    local raid = assert(Compile("raid40", "raid", "WeakenedSoul", { enabled = true, onlyOwn = true }))
    CheckProperties(party, false)
    CheckProperties(raid, true)
    assert(party.candidateFilterSignature ~= raid.candidateFilterSignature, "caster toggle cannot refresh candidates")
end

local function Custom(spells)
    return { enabled = true, custom = true, spells = spells, placed = { type = "icon" } }
end
local previous = assert(Compile("party1", "party", "6788", Custom("6788")))
if isForever then
    CheckProperties(previous, false)
else
    assert(previous.nativeFilter == "HELPFUL" and previous.candidateFilters.includeSpellIDs[id])
end
local mixed = assert(Compile("party1", "party", "6788", Custom("6788,139")))
assert(mixed.nativeFilter == "HELPFUL" and mixed.candidateFilters.includeSpellIDs[id]
    and mixed.candidateFilters.includeSpellIDs[139], "do not broaden multi-spell custom filters")
print("forever_weakened_soul_spell_icons_smoke " .. flavor .. ": passed")
