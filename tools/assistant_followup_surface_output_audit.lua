_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local smoke = "tools/assistant_dashboard_smoke.lua"
if not exists(smoke) then smoke = "../../tools/assistant_dashboard_smoke.lua" end
dofile(smoke)

local A = assert(_G.MSUF_NS and _G.MSUF_NS.Assistant, "Assistant missing after dashboard smoke")
local M = assert(_G.MSUF_NS.MSUF2, "Menu namespace missing after dashboard smoke")

local germanTerms = {
    "zeige", "anzeigen", "oeffne", "waehle", "einstellungen", "assistent",
    "zurueck", "rueck", "nicht", "keine", "abbrechen", "anwenden",
    "ausfuehren", "loeschen", "kopiere", "verschiebe", "groesse",
    "nenn", "nenne", "de", "gruppenlayout", "sonderbereich",
}

local rawPhrases = {
    "copy from profile default",
    "nenn es raid kopie",
    "zu raid neu",
    "zeige castbar einstellungen",
    "target cast bar hoehe 24",
    "target cast bar hoehe 25",
    "target cast bar hoehe 24 und focus cast bar hoehe 20",
    "abbrechen",
}

local function normalizedWords(text)
    return " " .. tostring(text or ""):lower():gsub("[%p%c]", " "):gsub("%s+", " ") .. " "
end

local function assertEnglishOutput(label, output)
    local haystack = normalizedWords(output)
    for _, term in ipairs(germanTerms) do
        assert(not haystack:find(" " .. term .. " ", 1, true), label .. ": output contains German visible term " .. term .. ": " .. tostring(output))
    end
    local lower = tostring(output or ""):lower()
    for _, phrase in ipairs(rawPhrases) do
        assert(not lower:find(phrase, 1, true), label .. ": output repeated raw phrase " .. phrase .. ": " .. tostring(output))
    end
end

local function closePanel()
    if type(A.CloseLargeTextPanel) == "function" then A.CloseLargeTextPanel() else A.largeTextPanel = nil end
end

local function resetTransient()
    closePanel()
    A.pendingChoices = nil
    A.pendingResults = nil
    A.pendingSelectedResult = nil
    A.pendingConfirmation = nil
    A.lastAssistantHelpContext = nil
    local ctx = A.GetContext and A.GetContext() or nil
    if type(ctx) == "table" then
        ctx.pendingChoices = nil
        ctx.pendingResults = nil
        ctx.pendingSelectedResult = nil
        ctx.pendingConfirmation = nil
    end
    if type(A.ClearPendingFlow) == "function" then A.ClearPendingFlow() end
end

local function submit(input, expectedStatus, contains)
    local result = A.Submit(input)
    assert(type(result) == "table", input .. ": missing result")
    local status = result.status or result.result
    assert(status == expectedStatus, input .. ": expected " .. tostring(expectedStatus) .. ", got " .. tostring(status) .. ": " .. tostring(result.text or ""))
    assertEnglishOutput(input, result.text or "")
    if contains then
        assert(tostring(result.text or ""):find(contains, 1, true), input .. ": missing text " .. tostring(contains) .. ": " .. tostring(result.text or ""))
    end
    return result
end

local function assertNoPendingChoices(label)
    local ctx = A.GetContext and A.GetContext() or nil
    assert(A.pendingChoices == nil, label .. ": stale root pending choices")
    assert(not (type(ctx) == "table" and ctx.pendingChoices ~= nil), label .. ": stale context pending choices")
end

resetTransient()
submit("copy from profile Default", "info", "What do you want me to call the copy")
submit("call it ''", "confirmation_needed", "Say 'cancel' or 'never mind' to stop.")
assert(A.Workflow.PendingFlow() and A.Workflow.PendingFlow().kind == "profileCopyDestination", "empty quoted copy name cleared the pending profile-copy flow")
assert(A.pendingConfirmation == nil, "empty quoted copy name created a confirmation")
submit("nenn es Raid Kopie", "confirmation_needed", "Copy profile Default to Raid Kopie")
submit("cancel", "applied", "Cancelled.")

resetTransient()
submit("rename profile Raid", "info", "What should the new name be")
submit("to ''", "confirmation_needed", "Say 'cancel' or 'never mind' to stop.")
assert(A.Workflow.PendingFlow() and A.Workflow.PendingFlow().kind == "profileRenameDestination", "empty quoted rename name cleared the pending profile-rename flow")
assert(A.pendingConfirmation == nil, "empty quoted rename name created a confirmation")
submit("zu Raid Neu", "confirmation_needed", "Rename profile Raid to Raid Neu")
submit("cancel", "applied", "Cancelled.")

resetTransient()
_G.MSUF_DB.player.showName = true
submit("spieler name aus", "applied", "I changed Player Name")
submit("zeige castbar einstellungen", "ambiguous", "I found multiple matches")
submit("undo", "applied", "Reverted")

resetTransient()
_G.MSUF_DB.target.castbarHeight = 18
submit("target cast bar hoehe 25", "applied", "Target Castbar Height")
submit("reset profile", "confirmation_needed", "Reset active profile")
submit("undo", "applied", "Reverted")

resetTransient()
_G.MSUF_DB.target.castbarHeight = 18
_G.MSUF_DB.focus.castbarHeight = 18
submit("target cast bar hoehe 24 und focus cast bar hoehe 20", "applied", "2 MSUF options")
submit("undo", "applied", "Reverted")

resetTransient()
submit("copy party to raid", "applied", "Party group-frame options to Raid")
submit("undo", "applied", "Reverted")

-- Load the native Menu2 group-copy contract in isolation. The dashboard smoke
-- intentionally does not load Menu2 pages, so relying on its M.GroupPage would
-- only exercise the Assistant fallback and leave native/fallback drift hidden.
local function loadNativeGroupCopyContract()
    local function wordList(text)
        local out = {}
        for value in tostring(text or ""):gmatch("%S+") do out[#out + 1] = value end
        return out
    end
    local function assign(target, ...)
        target = target or {}
        for i = 1, select("#", ...) do
            local source = select(i, ...)
            if type(source) == "table" then
                for key, value in pairs(source) do target[key] = value end
            end
        end
        return target
    end
    local function deepCopy(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local out = {}
        seen[value] = out
        for key, entry in pairs(value) do out[deepCopy(key, seen)] = deepCopy(entry, seen) end
        return out
    end
    local nativeDB = { gf_party = {}, gf_raid = {}, gf_mythicraid = {} }
    local nativeM = {
        Widgets = {}, Theme = {}, ControlGates = {}, UnitSectionsShared = {},
        GROUP_SPEC_TABLE_KEYS = [[SCOPE_VALUES GROWTH_VALUES BLIZZARD_FALLBACK_VALUES HEALTH_MODES TEXT_MODES DELIMITER_VALUES ANCHORS AURA_ANCHORS SORT_MODES GF_BAR_MODES GF_ANCHOR_TO GF_ANCHOR_POINTS STATUS_ICON_ANCHORS GF_STATUS_ICON_SPECS GF_STATUS_ICON_VALUES PLACED_INDICATOR_TYPES FRAME_EFFECT_TYPES ICON_EFFECT_TYPES SPELL_GROWTH_VALUES CI_SLOT_VALUES CI_SLOT_DEFAULTS DISPEL_OVERLAY_STYLES DEBUFF_STRIPE_EDGES]],
        ApplyService = {
            RequestGroup = function() return true end,
            RequestGroupDirtyMask = function() return true end,
        },
        EnsureDB = function() return nativeDB end,
        DeepCopy = deepCopy,
        Assign = assign,
        WordList = wordList,
        KeySetFromWords = function(text)
            local out = {}
            for _, key in ipairs(wordList(text)) do out[key] = true end
            return out
        end,
        ValueTextList = function(...)
            local out = {}
            for i = 1, select("#", ...), 2 do
                out[#out + 1] = { value = select(i, ...), text = select(i + 1, ...) }
            end
            return out
        end,
        ValueTextPairs = function(text)
            local out = {}
            for row in tostring(text or ""):gmatch("[^|]+") do
                local value, label = row:match("^(.-)=(.*)$")
                out[#out + 1] = { value = value, text = label }
            end
            return out
        end,
        PipeRows = function(text)
            local rows = {}
            for line in tostring(text or ""):gmatch("[^\r\n]+") do
                line = line:match("^%s*(.-)%s*$")
                if line ~= "" then
                    local columns = {}
                    for value in (line .. "|"):gmatch("(.-)|") do columns[#columns + 1] = value end
                    rows[#rows + 1] = columns
                end
            end
            return rows
        end,
    }
    nativeM.PickDefaults = function(source, keys)
        local values = {}
        for _, key in ipairs(wordList(keys)) do values[#values + 1] = source[key] or {} end
        return (table.unpack or unpack)(values)
    end
    nativeM.CopyFieldsFromSpecs = function(specs, values, seed, props)
        local out = type(seed) == "table" and seed or wordList(seed)
        for value in tostring(values or ""):gmatch("%S+") do
            for i = 1, #(specs or {}) do
                local spec = specs[i]
                if spec.value == value then
                    for prop in tostring(spec.copyProps or props):gmatch("%S+") do
                        local key = spec[prop]
                        if key then out[#out + 1] = key end
                    end
                    break
                end
            end
        end
        return out
    end

    local nativeNS = { MSUF2 = nativeM }
    local specsPath = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_GroupSpecs.lua"
    local groupPath = "MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_Group.lua"
    if not exists(specsPath) then
        specsPath = "../../" .. specsPath
        groupPath = "../../" .. groupPath
    end
    assert(loadfile(specsPath))("MSUF", nativeNS)
    assert(loadfile(groupPath))("MSUF", nativeNS)
    return assert(nativeM.GroupPage, "isolated native group page missing"), nativeDB
end

local function getUpvalue(fn, wanted)
    for i = 1, 64 do
        local name, value = debug.getupvalue(fn, i)
        if not name then break end
        if name == wanted then return value end
    end
end

local nativeGroupPage, nativeGroupDB = loadNativeGroupCopyContract()
local nativeGroupCopyCategories = assert(nativeGroupPage.GF_COPY_CATEGORIES,
    "native group copy categories missing")
local copyGroupAction = assert(A.Registry:GetAction("copy_group"), "copy_group action missing")
local fallbackCopyFn = assert(getUpvalue(copyGroupAction.run, "CopyGroupSettingsFallback"),
    "Assistant group copy fallback helper missing")
local runtimeFallbackCategories = assert(getUpvalue(fallbackCopyFn, "GROUP_COPY_CATEGORIES"),
    "Assistant group copy runtime categories missing")
local fallbackGroupCopyCategories = assert(A.DashboardRegistry
    and A.DashboardRegistry.CopyCategoryFallbacks
    and A.DashboardRegistry.CopyCategoryFallbacks.group,
    "Assistant group copy category fallbacks missing")
local expectedGroupCopyCategoryKeys = {
    "general", "health", "dispel", "text", "font", "range",
    "indicators", "auras", "highlight", "dstripe", "features",
}
for i = 1, #expectedGroupCopyCategoryKeys do
    local expected = expectedGroupCopyCategoryKeys[i]
    assert(nativeGroupCopyCategories[i] and nativeGroupCopyCategories[i].key == expected,
        "native group copy category drift at " .. tostring(i))
    assert(runtimeFallbackCategories[i] and runtimeFallbackCategories[i].key == expected,
        "Assistant runtime group copy category drift at " .. tostring(i))
    assert(fallbackGroupCopyCategories[i] and fallbackGroupCopyCategories[i].key == expected,
        "Assistant group copy category drift at " .. tostring(i))
end
assert(#nativeGroupCopyCategories == #expectedGroupCopyCategoryKeys,
    "native group copy category count drift")
assert(#runtimeFallbackCategories == #expectedGroupCopyCategoryKeys,
    "Assistant runtime group copy category count drift")
assert(#fallbackGroupCopyCategories == #expectedGroupCopyCategoryKeys,
    "Assistant group copy category count drift")

local function assertSameFieldList(category, field)
    local nativeValues = nativeGroupCopyCategories[category][field] or {}
    local fallbackValues = runtimeFallbackCategories[category][field] or {}
    local nativeSet, fallbackSet = {}, {}
    for i = 1, #nativeValues do nativeSet[nativeValues[i]] = true end
    for i = 1, #fallbackValues do fallbackSet[fallbackValues[i]] = true end
    for key in pairs(nativeSet) do
        assert(fallbackSet[key], "Assistant group copy category omitted native " .. field .. " field " .. key)
    end
    for key in pairs(fallbackSet) do
        assert(nativeSet[key], "Assistant group copy category added non-native " .. field .. " field " .. key)
    end
end
for category = 1, #nativeGroupCopyCategories do
    assertSameFieldList(category, "keys")
    assertSameFieldList(category, "prefix")
    assertSameFieldList(category, "tables")
end

-- Native Health & Bars cannot cross ownership into Dispel Overlay, Debuff
-- Stripe, or shared colors; explicit Dispel Overlay can copy all six fields.
local nativeParty, nativeRaid = nativeGroupDB.gf_party, nativeGroupDB.gf_raid
nativeParty.powerHeight, nativeRaid.powerHeight = 9, 3
nativeParty.hpBarAlpha, nativeRaid.hpBarAlpha = 0.82, 0.31
nativeParty.bgR, nativeRaid.bgR = 0.91, 0.12
nativeParty.dispelOverlayAlpha, nativeRaid.dispelOverlayAlpha = 0.77, 0.22
nativeParty.debuffStripeHeight, nativeRaid.debuffStripeHeight = 7, 2
assert(nativeGroupPage.CopyGroupSettings("party", "raid", { health = true }),
    "native Health & Bars copy failed")
assert(nativeRaid.powerHeight == 9 and nativeRaid.hpBarAlpha == 0.82,
    "native Health & Bars omitted reviewed fields")
assert(nativeRaid.bgR == 0.12 and nativeRaid.dispelOverlayAlpha == 0.22
    and nativeRaid.debuffStripeHeight == 2,
    "native Health & Bars crossed a copy-category ownership boundary")
assert(nativeGroupPage.CopyGroupSettings("party", "raid", { dispel = true }),
    "native Dispel Overlay copy failed")
assert(nativeRaid.dispelOverlayAlpha == 0.77 and nativeRaid.powerHeight == 9
    and nativeRaid.debuffStripeHeight == 2,
    "native Dispel Overlay copied the wrong field set")

-- A Health & Bars transaction copies its own opacity/resource controls, but
-- cannot leak into the separately-owned Dispel Overlay or Debuff Stripe.
resetTransient()
local partyGroup = assert(_G.MSUF_DB.gf_party, "Party group config missing")
local raidGroup = assert(_G.MSUF_DB.gf_raid, "Raid group config missing")
partyGroup.powerHeight = 9
partyGroup.hpBarAlpha = 0.82
partyGroup.bgR = 0.91
partyGroup.dispelOverlayEnabled = true
partyGroup.dispelOverlayAlpha = 0.77
partyGroup.debuffStripeHeight = 7
raidGroup.powerHeight = 3
raidGroup.hpBarAlpha = 0.31
raidGroup.bgR = 0.12
raidGroup.dispelOverlayEnabled = false
raidGroup.dispelOverlayAlpha = 0.22
raidGroup.debuffStripeHeight = 2
submit("copy party health bars to raid", "applied", "Party group-frame options to Raid")
assert(raidGroup.powerHeight == 9 and raidGroup.hpBarAlpha == 0.82,
    "Health & Bars did not copy its reviewed controls")
assert(raidGroup.bgR == 0.12, "Health & Bars copied a native-excluded shared background color")
assert(raidGroup.dispelOverlayEnabled == false and raidGroup.dispelOverlayAlpha == 0.22,
    "Health & Bars leaked into Dispel Overlay")
assert(raidGroup.debuffStripeHeight == 2, "Health & Bars leaked into Debuff Stripe")
submit("undo", "applied", "Reverted")
assert(raidGroup.powerHeight == 3 and raidGroup.hpBarAlpha == 0.31,
    "Health & Bars transaction undo restored the wrong values")

-- Explicit Dispel Overlay copies all overlay fields and nothing from health,
-- border/highlight, shared colors, or Debuff Stripe.
resetTransient()
partyGroup.dispelOverlayEnabled = true
partyGroup.dispelOverlayStyle = "TOP"
partyGroup.dispelOverlayOnHealth = false
partyGroup.dispelOverlayAlpha = 0.77
partyGroup.dispelOverlayTrigger = "ANY_DEBUFF"
partyGroup.dispelOverlayStrata = "HIGH"
partyGroup.dispelEnabled = true
raidGroup.dispelOverlayEnabled = false
raidGroup.dispelOverlayStyle = "FULL"
raidGroup.dispelOverlayOnHealth = true
raidGroup.dispelOverlayAlpha = 0.22
raidGroup.dispelOverlayTrigger = "BORDER"
raidGroup.dispelOverlayStrata = "AUTO"
raidGroup.dispelEnabled = false
raidGroup.powerHeight = 3
raidGroup.bgR = 0.12
raidGroup.debuffStripeHeight = 2
submit("copy party dispel overlay to raid", "applied", "Party group-frame options to Raid")
assert(raidGroup.dispelOverlayEnabled == true
    and raidGroup.dispelOverlayStyle == "TOP"
    and raidGroup.dispelOverlayOnHealth == false
    and raidGroup.dispelOverlayAlpha == 0.77
    and raidGroup.dispelOverlayTrigger == "ANY_DEBUFF"
    and raidGroup.dispelOverlayStrata == "HIGH",
    "explicit Dispel Overlay copy omitted reviewed overlay controls")
assert(raidGroup.powerHeight == 3 and raidGroup.bgR == 0.12,
    "explicit Dispel Overlay copy leaked into health/shared colors")
assert(raidGroup.dispelEnabled == false, "explicit Dispel Overlay copy leaked into highlight borders")
assert(raidGroup.debuffStripeHeight == 2, "explicit Dispel Overlay copy leaked into Debuff Stripe")
submit("undo", "applied", "Reverted")
assert(raidGroup.dispelOverlayEnabled == false and raidGroup.dispelOverlayAlpha == 0.22,
    "Dispel Overlay transaction undo restored the wrong values")

-- Exercise the Assistant fallback directly as well as through Submit above.
local dashboardGroupPage = M.GroupPage
M.GroupPage = nil
raidGroup.powerHeight = 3
raidGroup.hpBarAlpha = 0.31
raidGroup.bgR = 0.12
raidGroup.dispelOverlayAlpha = 0.22
local fallbackOk = copyGroupAction.run({
    source = "party", targets = { "raid" }, scopes = { health = true },
})
assert(fallbackOk == true, "Assistant fallback Health & Bars copy failed")
assert(raidGroup.powerHeight == 9 and raidGroup.hpBarAlpha == 0.82,
    "Assistant fallback Health & Bars field set differs from native")
assert(raidGroup.bgR == 0.12 and raidGroup.dispelOverlayAlpha == 0.22,
    "Assistant fallback Health & Bars crossed a native ownership boundary")
raidGroup.powerHeight = 3
raidGroup.dispelOverlayAlpha = 0.22
fallbackOk = copyGroupAction.run({
    source = "party", targets = { "raid" }, scopes = { dispel = true },
})
assert(fallbackOk == true and raidGroup.dispelOverlayAlpha == 0.77,
    "Assistant fallback explicit Dispel Overlay copy failed")
assert(raidGroup.powerHeight == 3, "Assistant fallback Dispel Overlay leaked into health")
M.GroupPage = dashboardGroupPage

resetTransient()
submit("reset profile", "confirmation_needed", "Reset active profile")
submit("abbrechen", "failed", "Cancelled.")

resetTransient()
_G.MSUF_DB.target.showBuffs = false
M.activeKey = "auras3"
submit("target buffs not shown", "info", "Suggested fixes")
submit("what can i do on this page", "info", "Assistant help for Auras:")
assert(_G.MSUF_DB.target.showBuffs == false, "fresh page-help question should not apply the pending aura fix")
assertNoPendingChoices("fresh page-help question")

resetTransient()
_G.MSUF_DB.target.showBuffs = false
submit("target buffs not shown", "info", "Suggested fixes")
submit("dispellable debuffs are hard to see", "info", "Dispel visibility help")
assert(_G.MSUF_DB.target.showBuffs == false, "fresh signal question should not apply the pending aura fix")
assertNoPendingChoices("fresh signal question")

resetTransient()
_G.MSUF_DB.target.showBuffs = false
submit("target buffs not shown", "info", "Suggested fixes")
submit("what are class resources", "info", "Class Resources help")
assert(_G.MSUF_DB.target.showBuffs == false, "fresh knowledge question should not apply the pending aura fix")
assertNoPendingChoices("fresh knowledge question")

resetTransient()
submit("make my raid frames easier to read", "info", "Group frame readability help")
submit("what should i change first", "info", "least destructive visible setting")
submit("open that", "navigated", "Opened Group Layout")
submit("show examples", "info", "set raid scale")
submit("make it smaller", "info", "Name the exact MSUF area")

resetTransient()
submit("what should i change first", "info", "native MSUF guided setup")

resetTransient()
submit("make target buffs easier to read", "info", "Aura readability help")
submit("what should i change first", "info", "Aura readability help")
submit("open that", "navigated", "Opened Target and focused Aura Buffs")
submit("make target buffs size 30", "applied", "Target Buff Icon Size")

resetTransient()
_G.MSUF_DB.auras3.target = _G.MSUF_DB.auras3.target or {}
_G.MSUF_DB.auras3.target.buff = { size = 26 }
_G.MSUF_DB.auras3.target.debuff = { size = 26 }
submit("make target buffs bigger", "applied", "Target Buff Icon Size")
submit("same for debuffs", "applied", "Target Debuff Icon Size")

resetTransient()
_G.MSUF_DB.target.portraitMode = "OFF"
_G.MSUF_DB.focus.portraitMode = "OFF"
submit("turn off target portrait", "unchanged", "Already set. Target Portrait Position is already off.")
local unchangedReport = submit("what did you change", "info", "Target Portrait Position was already off.")
assert(not tostring(unchangedReport.text or ""):find("undo", 1, true), "unchanged last-change report should not offer undo: " .. tostring(unchangedReport.text or ""))
submit("same for focus", "unchanged", "Already set. Focus Portrait Position is already off.")

resetTransient()
A.SetPendingResults({
    { kind = "action", actionKey = "support_links_summary", label = "Show Support Links", page = "gf_layout", pageLabel = "DE Gruppenlayout" },
})
submit("explain result 1", "info", "Page: Group Layout")

resetTransient()
A.SetPendingResults({
    { kind = "action", actionKey = "support_links_summary", label = "Show Support Links", pageLabel = "DE Sonderbereich" },
})
submit("why result 1", "info", "on Assistant")

resetTransient()
local openPage = assert(A.Registry and A.Registry.GetAction and A.Registry:GetAction("open_page"), "open_page action missing")
A.pendingChoices = {
    { action = openPage, actionKey = "open_page", args = { page = "gf_layout", label = "DE Gruppenlayout" }, label = "Open Group Layout" },
}
submit("explain option 1", "info", "Page: Group Layout")

io.write("assistant_followup_surface_output_audit: ok cases=36\n")
