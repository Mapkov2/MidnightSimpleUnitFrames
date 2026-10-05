-- castbar_preview_sample_locale_smoke.lua <repoRoot>
--
-- The castbar previews paint sample texts through MSUF.Translate: the spell
-- names (Castbars/MSUF_CastbarPreviews.lua PREVIEW_LABELS, the boss and arena
-- descriptors' label) and the sample cast targets (targetLabel). A sample the
-- language packs do not know stays English next to translated text, which the
-- key coverage smoke cannot see because the keys reach Translate as variables.
-- Every sample is read from the shipped sources and must have a translation of
-- its own in every non-English pack, run through the real localization core.
--
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local CASTBARS = "MidnightSimpleUnitFrames/Castbars/"
local LOCALES = "MidnightSimpleUnitFrames/Locales/"

local function Read(path)
    local handle = assert(io.open(repo .. "/" .. path, "rb"), "cannot open " .. path)
    local text = handle:read("*a")
    handle:close()
    return (text:gsub("\r\n", "\n"))
end

-- The sample texts, from the sources that hand them to Translate.
local samples, order = {}, {}
local function Add(text, where)
    if not samples[text] then
        samples[text] = where
        order[#order + 1] = text
    end
end
for _, file in ipairs({ "MSUF_BossCastbars_Preview.lua", "MSUF_ArenaCastbars_Preview.lua" }) do
    local source = Read(CASTBARS .. file)
    for field, text in source:gmatch("\n%s*(%a+)%s*=%s*\"([^\"]+)\"") do
        if field == "label" or field == "targetLabel" then Add(text, file .. " " .. field) end
    end
end
local labels = assert(Read(CASTBARS .. "MSUF_CastbarPreviews.lua"):match("local PREVIEW_LABELS = (%b{})"),
    "MSUF_CastbarPreviews.lua lost its PREVIEW_LABELS table")
for unit, text in labels:gmatch("(%a+)%s*=%s*\"([^\"]+)\"") do Add(text, "PREVIEW_LABELS." .. unit) end
for _, required in ipairs({ "Celestial Ruin", "Greater Pyroblast", "Cleave Training Dummy", "Arena Ally" }) do
    assert(samples[required], "the sample scan no longer finds " .. required)
end

--- Run one pack as the client does and return its finished L table.
local function LoadPack(locale)
    _G.GetLocale = function() return locale end
    _G.CreateFrame = nil
    local namespace = {}
    _G.MSUF_NS, _G.MSUF = namespace, namespace
    assert(loadfile(repo .. "/" .. LOCALES .. "MSUF_Localization.lua"))("MidnightSimpleUnitFrames", namespace)
    assert(loadfile(repo .. "/" .. LOCALES .. locale .. ".lua"))("MidnightSimpleUnitFrames", namespace)
    assert(namespace.FinalizeLocale() == locale, locale .. ": the core selected another pack")
    return namespace.L, namespace.SUPPORTED_LOCALES
end

local _, supported = LoadPack("enUS")
local failures, checked = {}, 0
for locale in pairs(supported) do
    if locale ~= "enUS" and locale ~= "enGB" then
        checked = checked + 1
        local L = LoadPack(locale)
        for _, text in ipairs(order) do
            local translated = rawget(L, text)
            if type(translated) ~= "string" or translated == "" or translated == text then
                failures[#failures + 1] = locale .. ": " .. text .. " (" .. samples[text] .. ")"
            end
        end
    end
end
assert(checked == 10, "expected 10 non-English packs, found " .. checked)
table.sort(failures)
if #failures > 0 then
    error("castbar preview samples without a translation:\n  " .. table.concat(failures, "\n  "), 0)
end
print("castbar_preview_sample_locale_smoke: ok (" .. #order .. " samples, " .. checked .. " packs)")
