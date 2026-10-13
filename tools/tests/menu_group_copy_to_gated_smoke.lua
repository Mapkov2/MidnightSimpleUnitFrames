-- menu_group_copy_to_gated_smoke.lua <repoRoot> <flavor>
--
-- Group page Copy To (MSUF_Menu2_Group.lua CopyGroupSettings):
--   1. The Highlight & Aggro category copies the scope's Custom settings flag
--      (hlOverride). Every Bars value that flag gates (heal prediction, absorb,
--      outline thickness, highlight border, gradients) has to travel with it, or
--      the destination keeps its own seeded values: a Raid scope whose heal
--      prediction was inherited-off from the global switch started predicting
--      heals the moment Party's Custom flag arrived.
--   2. A source without the Custom flag leaves the destination's stored Bars
--      values alone, and the texture values stay with the Health & Bars category.
--   3. Copy To never flips the frame provider: enabled and blizzardFallbackMode
--      switch a header on or off and need the reload prompt, so they are set per
--      scope on the page (SetFrameProvider), not copied.
-- Every section runs on its own; all failures are listed together.
-- Plain Lua 5.1 with the repo root and a flavor as arguments.

local testRoot = assert(debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])"))
local h = assert(loadfile(testRoot .. "bh3_menu_page_fixture.lua"))()
local M, GF, GP = h.M, h.MSUF.GF, h.M.GroupPage
local env = h.env

local failures = {}
local function Section(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
local function Check(condition, message)
    if not condition then error(message, 0) end
end

GF.EnsureDB()
GF.InvalidateConfCache(true)
local db = env.MSUF_DB
local source, target = GF.GetConf("party"), GF.GetConf("raid")

-- Every value the compiled group config reads behind hlOverride: source value, destination's own seeded value.
local GATED = {
    { "healPredEnabled", false, true }, { "enableAbsorbBar", false, true }, { "absorbBarHeight", 5, 0 },
    { "barOutlineThickness", 4, 1 }, { "highlightBorderThickness", 3, 1 },
    { "absorbBarTexture", "party-absorb", "raid-absorb" }, { "healAbsorbBarTexture", "party-heal-absorb", "raid-heal-absorb" },
}
-- The values the scope's gradient owns: the marks of gradientOverrideKeys name them.
local GRADIENT = {
    { "enableGradient", true, false }, { "enablePowerGradient", true, false },
    { "gradientStrength", 0.3, 0.45 }, { "powerGradientStrength", 0.2, 0.45 },
    { "gradientDirection", "LEFT", "RIGHT" }, { "powerGradientDirection", "UP", "RIGHT" },
    { "gradientDirLeft", true, false }, { "gradientDirRight", false, true },
    { "gradientDirUp", true, false }, { "gradientDirDown", true, false },
    { "powerGradientDirLeft", true, false }, { "powerGradientDirRight", false, true },
    { "powerGradientDirUp", true, false }, { "powerGradientDirDown", true, false },
    { "healthBarGradientColorR", 0.9, 0.1 }, { "healthBarGradientColorG", 0.8, 0.1 }, { "healthBarGradientColorB", 0.7, 0.1 },
    { "powerBarGradientColorR", 0.6, 0.1 }, { "powerBarGradientColorG", 0.5, 0.1 }, { "powerBarGradientColorB", 0.4, 0.1 },
}

Section("Custom flag carries the values it gates", function()
    db.general.healPredEnabled = false
    db.general.showSelfHealPrediction = false
    source.hlOverride = true
    source.gradientOverride, source.gradientOverrideVersion = true, 2
    source.gradientOverrideKeys = {}
    for _, row in ipairs(GATED) do source[row[1]], target[row[1]] = row[2], row[3] end
    for _, row in ipairs(GRADIENT) do
        source[row[1]], target[row[1]] = row[2], row[3]
        source.gradientOverrideKeys[row[1]] = true
    end
    source.barTexture = "party-texture"
    target.hlOverride = false
    target.barTexture = "raid-texture"
    Check(GF.IsHealPredictionEnabled("raid") == false, "fixture: a raid scope without Custom settings must follow the global switch")
    Check(GP.CopyGroupSettings("party", "raid", { highlight = true }), "the highlight copy was refused")
    Check(target.hlOverride == true, "the Custom settings flag did not travel")
    Check(GF.IsHealPredictionEnabled("raid") == false, "Raid predicts heals although the global switch and the source are off")
    local missing = {}
    for _, row in ipairs(GATED) do
        if target[row[1]] ~= row[2] then missing[#missing + 1] = row[1] end
    end
    for _, row in ipairs(GRADIENT) do
        if target[row[1]] ~= row[2] then missing[#missing + 1] = row[1] end
    end
    Check(#missing == 0, "these gated values stayed on the destination's own value: " .. table.concat(missing, ", "))
    Check(target.gradientOverride == true and target.gradientOverrideVersion == 2
        and type(target.gradientOverrideKeys) == "table", "the gradient ownership marks did not travel")
    for _, row in ipairs(GRADIENT) do
        if target.gradientOverrideKeys[row[1]] ~= true then missing[#missing + 1] = row[1] end
    end
    Check(#missing == 0, "these gradient marks did not travel: " .. table.concat(missing, ", "))
    Check(target.gradientOverrideKeys ~= source.gradientOverrideKeys, "the gradient ownership table is shared between scopes")
    Check(target.barTexture == "raid-texture", "the highlight copy changed the texture, which belongs to Health & Bars")
end)

Section("Only the values the gradient marks name travel", function()
    source.hlOverride = true
    source.gradientOverride, source.gradientOverrideVersion = true, 2
    source.gradientOverrideKeys = { enableGradient = true }
    source.enableGradient, target.enableGradient = true, false
    -- Stored on the source but not owned by its gradient, and not a Bars scope key.
    source.healthBarGradientColorB, target.healthBarGradientColorB = 0.8, 0.1
    Check(GP.CopyGroupSettings("party", "raid", { highlight = true }), "the highlight copy was refused")
    Check(target.enableGradient == true, "the marked gradient value did not travel")
    Check(target.healthBarGradientColorB == 0.1, "an unmarked gradient value travelled with the copy")
end)

Section("A source without Custom settings keeps the destination values", function()
    source.hlOverride = false
    target.hlOverride = true
    target.healPredEnabled = true
    target.barOutlineThickness = 6
    Check(GP.CopyGroupSettings("party", "raid", { highlight = true }), "the highlight copy was refused")
    Check(target.hlOverride == false, "the source's cleared flag did not travel")
    Check(target.healPredEnabled == true and target.barOutlineThickness == 6,
        "a source without Custom settings overwrote the destination's stored Bars values")
end)

Section("Copy To does not switch headers on or off", function()
    source.enabled, source.blizzardFallbackMode = true, "BLIZZARD"
    target.enabled, target.blizzardFallbackMode = false, "OFF"
    Check(GP.CopyGroupSettings("party", "raid", { general = true }), "the basics copy was refused")
    Check(target.enabled == false, "Copy To enabled a group frame scope without the reload prompt")
    Check(target.blizzardFallbackMode == "OFF", "Copy To changed the Blizzard frame fallback without the reload prompt")
    target.enabled = true
    source.enabled = false
    Check(GP.CopyGroupSettings("party", "raid", { general = true }), "the basics copy was refused")
    Check(target.enabled == true, "Copy To disabled a group frame scope without the reload prompt")
end)

if #failures > 0 then
    error("menu_group_copy_to_gated_smoke (" .. tostring(arg[2]) .. "): " .. #failures .. " section(s) failed\n  "
        .. table.concat(failures, "\n  "), 0)
end
print("group copy to: PASS")
