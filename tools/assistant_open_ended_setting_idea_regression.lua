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
local Registry = assert(A.Registry, "Assistant registry missing")

local function stable(value)
    if type(value) ~= "table" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for i = 1, #keys do out[#out + 1] = tostring(keys[i]) .. "=" .. stable(value[keys[i]]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local function snapshot(keys)
    local values = {}
    for i = 1, #(keys or {}) do
        local setting = assert(Registry:GetSetting(keys[i]), keys[i] .. " setting missing")
        values[keys[i]] = stable(setting.get())
    end
    return values
end

local function checkUnchanged(label, before)
    for key, value in pairs(before or {}) do
        local setting = assert(Registry:GetSetting(key), key .. " setting missing")
        assert(stable(setting.get()) == value, label .. ": unexpectedly changed " .. key)
    end
end

local cases = {
    {
        input = "change player font outline",
        contains = { "Player Font Outline - Player", "Current value:", "Player Font Outline: outline", "Player Font Outline: none" },
        unchanged = { "fontScope.player.outline" },
    },
    {
        input = "change target health color",
        contains = { "Target Health Color Scheme", "Target Health Text Color Mode", "kept everything unchanged" },
        unchanged = { "target.healthColorMode", "fontScope.target.colorHealthTextByHealth" },
    },
    {
        input = "change target castbar texture",
        contains = { "Castbar Texture - Cast Bars", "Current value:", "media name", "open the control" },
        unchanged = { "general.castbarTexture" },
    },
    {
        input = "change player portrait style",
        contains = { "Player Class Portrait Style", "Player Portrait Border", "Player Portrait Render" },
        unchanged = { "player.portraitClassStyle", "player.portraitBorderStyle", "player.portraitRender" },
    },
    {
        input = "change raid spacing",
        contains = { "Raid Spacing - Group Layout", "Current value:", "min 0", "max 20" },
        unchanged = { "gf_raid.spacing" },
    },
    {
        input = "change target castbar height",
        contains = { "Target Castbar Height - Target", "Current value:", "min 6", "max 80" },
        unchanged = { "general.castbarTargetBarHeight" },
    },
    {
        input = "change player portrait",
        contains = { "Player Portrait Position", "Player Portrait Render", "Player Portrait Border" },
        unchanged = { "player.portraitMode", "player.portraitRender", "player.portraitBorderStyle" },
    },
    {
        input = "I want to adjust player power bar anchor",
        contains = { "Player Detached Power Bar Anchors to Class Resource", "enabled", "disabled" },
        unchanged = { "player.detachedPowerBarAnchorToClassPower" },
    },
    {
        input = "change focus name font",
        contains = { "Global Font - Fonts", "Focus Font Override", "Focus Name Font Size" },
        unchanged = { "general.fontKey", "fontScope.focus.override", "focus.nameFontSize" },
    },
    {
        input = "make raid background color different",
        contains = { "Raid Backdrop Color", "Raid Dead Background Color" },
        unchanged = { "gf_raid.bgColor", "gf_raid.deadBgColor" },
    },
    {
        -- The retired Class Resources detached texture settings must not come
        -- back as suggestions; power art is owned by the Bars/unit pages now.
        -- Resolves to the shared Bars power texture the per-frame value falls
        -- back to, and asks for a value instead of writing one. It must not
        -- drift back to the Class Resources texture, which has nothing to do
        -- with a unit's power bar.
        input = "change target power bar texture",
        contains = { "Power Bar Texture" },
        notContains = { "Class Power Bar Texture", "Detached Power Bar Foreground Texture", "Detached Power Bar Background Texture" },
        unchanged = { "general.barTexture", "bars.classPowerBarTexture", "bars.powerBarTexture", "target.powerBarTexture" },
    },
    {
        input = "change target name text size",
        contains = { "Target Name Font Size - Target", "Current value:", "min 6", "max 48" },
        unchanged = { "target.nameFontSize" },
    },
    {
        input = "change player frame color",
        contains = { "Player Health Color Scheme", "Player Bar Outline Color", "Player Name Text Color Mode" },
        unchanged = { "player.healthColorMode", "barScope.player.barOutlineColor", "fontScope.player.nameColorMode" },
    },
    {
        input = "adjust target cast bar",
        contains = { "Target Cast Bar", "Target Castbar Width", "Target Castbar Height" },
        unchanged = { "general.enableTargetCastbar", "general.castbarTargetBarWidth", "general.castbarTargetBarHeight" },
    },
    {
        -- The Player page owns no plain health-bar texture (that value is
        -- global, on Bars), so the closest exact control is the Temp Max Health
        -- overlay. Answering with it and asking for a value is a near miss, not
        -- a wrong write -- what matters here is that nothing changes and the
        -- reply never drifts onto an absorb bar or a generic examples dump.
        input = "change player health texture",
        contains = { "kept it unchanged" },
        notContains = { "general Assistant examples", "Player Absorb Bar Texture -" },
        unchanged = { "general.barTexture", "barScope.player.absorbBarTexture", "player.tempMaxHealthTexture" },
    },
    {
        input = "change focus name position",
        contains = { "Focus Name Text Anchor", "Focus Name X Offset", "Focus Name Y Offset" },
        notContains = { "Focus Castbar Spell Name Position" },
        unchanged = { "focus.nameTextAnchor", "focus.nameOffsetX", "focus.nameOffsetY" },
    },
    {
        input = "change boss frame growth",
        contains = { "Boss Buff Growth", "Boss Debuff Growth" },
        unchanged = { "auras3.boss.buff.growth", "auras3.boss.debuff.growth" },
    },
    {
        input = "i want to change castbar interrupt colors",
        contains = {
            "Interruptible Cast Color", "Non-Interruptible Cast Color",
            "Interrupt Unavailable Fill Color", "Interrupt Feedback Cast Color",
        },
        unchanged = {
            "general.castbarInterruptibleColor", "general.castbarNonInterruptibleColor",
            "general.castbarInterruptUnavailableColor", "general.castbarInterruptFeedbackColor",
        },
    },
    {
        input = "i want to change target health text",
        contains = { "Target HP Text", "Target HP Font Size", "Target Health Text Color Mode", "Target HP Text Delimiter" },
        unchanged = { "target.showHP", "target.hpFontSize", "fontScope.target.colorHealthTextByHealth", "target.hpTextSeparator" },
    },
}

for i = 1, #cases do
    local case = cases[i]
    A.StartNewTask()
    local before = snapshot(case.unchanged)
    local result = A.Submit(case.input)
    assert((result.status or result.result) == "ambiguous",
        case.input .. ": expected a safe clarification, got " .. tostring(result.status or result.result) .. "; " .. tostring(result.text))
    local output = tostring(result.text or "")
    for j = 1, #(case.contains or {}) do
        assert(output:find(case.contains[j], 1, true), case.input .. ": missing " .. case.contains[j] .. "; " .. output)
    end
    for j = 1, #(case.notContains or {}) do
        assert(not output:find(case.notContains[j], 1, true), case.input .. ": unexpected " .. case.notContains[j] .. "; " .. output)
    end
    for _, jargon in ipairs({ "[enum]", "[string]", "[number]", "[boolean]", "[color]", "enum setting", "string setting" }) do
        assert(not output:find(jargon, 1, true), case.input .. ": exposed registry jargon " .. jargon .. "; " .. output)
    end
    assert(not output:find("Show general Assistant examples", 1, true), case.input .. ": fell back to generic examples")
    checkUnchanged(case.input, before)
end

local function explicit(key, beforeValue, input, expectedValue)
    local setting = assert(Registry:GetSetting(key), key .. " setting missing")
    local restore = setting.get()
    setting.set(beforeValue)
    A.StartNewTask()
    local result = A.Submit(input)
    local status = result.status or result.result
    assert(status == "applied" or status == "unchanged", input .. ": concrete value was intercepted; " .. tostring(result.text))
    assert(stable(setting.get()) == stable(expectedValue), input .. ": concrete value changed the wrong setting/value")
    setting.set(restore)
end

explicit("fontScope.player.outline", "OUTLINE", "change player font outline to none", "NONE")
explicit("player.portraitRender", "CLASS", "change player portrait to 2D", "2D")
explicit("target.portraitMode", "OFF", "change target portrait position to right", "RIGHT")
explicit("general.castbarTexture", "Flat", "change target castbar texture to Blizzard", "Blizzard")
explicit("gf_party.growth", "DOWN", "change party frame growth direction to up", "UP")
explicit("gf_raid.spacing", 1, "change raid spacing to 5", 5)

A.StartNewTask()
local textureBefore = stable(Registry:GetSetting("general.barTexture").get())
local unresolvedMedia = A.Submit("change health texture to Smooth")
assert((unresolvedMedia.status or unresolvedMedia.result) == "ambiguous", "unmapped media value did not fail closed")
-- Known near miss: "health texture" collides with the per-frame Temp Max Health
-- overlay labels, so the reply offers those controls to choose from instead of
-- naming the Bars page. What this gate protects is the safety half -- it stays
-- a read-only choice, never a guess, and never the generic examples dump.
assert(tostring(unresolvedMedia.text):find("Pick the control you meant", 1, true)
        or tostring(unresolvedMedia.text):find("Best place to check: Bars", 1, true),
    "unmapped media value lost its specific page fallback")
assert(not tostring(unresolvedMedia.text):find("general Assistant examples", 1, true), "unmapped media value fell back to general examples")
assert(stable(Registry:GetSetting("general.barTexture").get()) == textureBefore, "unmapped health texture changed the global bar texture")

A.StartNewTask()
local outline = Registry:GetSetting("fontScope.player.outline")
local outlineBefore = outline.get()
outline.set("OUTLINE")
local choice = A.Submit("change player font outline")
assert((choice.status or choice.result) == "ambiguous" and type(A.pendingChoices) == "table", "enum choices were not retained")
local noneIndex
for i = 1, #A.pendingChoices do if A.pendingChoices[i].value == "NONE" then noneIndex = i end end
assert(noneIndex, "font outline choices omitted None")
local selected = A.Submit(tostring(noneIndex))
assert((selected.status or selected.result) == "applied" and outline.get() == "NONE", "numbered enum choice did not apply")
outline.set(outlineBefore)

local R = assert(A.RouterPrivate)
local originalKnowledgeSearch = assert(A.Knowledge and A.Knowledge.Search)
A.Knowledge.Search = function() return nil end
R._openEndedSettingCache = nil
local coldEntries, searchCold = R.RegistrySettingSearchEntries("frobnicator bar", "frobnicator bar", 4)
assert(coldEntries == nil and searchCold == true, "cold Knowledge sentinel was collapsed into an empty search")
local coldAnalysis = assert(R.OpenEndedSettingAnalysis("I want to adjust frobnicator bar"),
    "cold open-ended page fallback was lost")
assert(coldAnalysis.searchCold == true, "cold open-ended analysis lost its index state")
assert(R._openEndedSettingCache == nil,
    "cold open-ended analysis poisoned the same-query cache before the Knowledge index was ready")
A.Knowledge.Search = originalKnowledgeSearch

R._openEndedSettingCache = nil
local retryPrompt = "change player font outline to none"
local retryAnalysis = assert(R.OpenEndedSettingAnalysis(retryPrompt), "explicit retry analysis missing")
local routed, routeError = pcall(R.TryOpenEndedSettingIdea, retryPrompt, function() error("synthetic Core failure") end)
assert(not routed and tostring(routeError):find("synthetic Core failure", 1, true), "synthetic Core failure was swallowed")
assert(type(R._openEndedSettingCache) == "table" and R._openEndedSettingCache.analysis == retryAnalysis,
    "Core failure left the same-query fail-close cache disabled")

R._openEndedSettingCache = { text = "temporary", analysis = {} }
A.ClearRouterTransientCaches()
assert(R._openEndedSettingCache == nil, "open-ended analysis cache survived lifecycle cleanup")

io.write("assistant_open_ended_setting_idea_regression: ok cases=" .. tostring(#cases) .. "\n")
