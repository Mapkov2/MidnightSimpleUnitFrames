-- Key binding labels follow the menu language (review F18). They were
-- translated while the Keybinds file loaded, before the saved locale was
-- finalized, so every client showed them in English.
-- Usage: lua tools/tests/keybind_labels_locale_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local namespace = {}
GetLocale = function() return "deDE" end
CreateFrame = nil
_G.MSUF_NS, _G.MSUF = namespace, namespace
namespace.ExportPublic = function(name, value) _G[name] = value end
local function Load(path) assert(loadfile(repo .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", namespace) end
Load("Locales/MSUF_Localization.lua")
Load("Locales/enUS.lua")
Load("Locales/deDE.lua")
CreateFrame = function() return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end } end
Load("Kernel/MSUF_Keybinds.lua")
namespace.FinalizeLocale()
local function Expected(key)
    local value = namespace.Translate(key)
    assert(value ~= key, "the German pack has no translation for " .. key)
    return value
end
assert(BINDING_NAME_MSUF_VARIANT_1 == Expected("Toggle profile variant %d"):format(1),
    "the variant binding label stayed English: " .. tostring(BINDING_NAME_MSUF_VARIANT_1))
assert(BINDING_NAME_MSUF_VARIANT_8 == Expected("Toggle profile variant %d"):format(8), "the eighth variant label is wrong")
assert(BINDING_NAME_MSUF_PRIORITY_TOGGLE == Expected("Pin or unpin hovered group member"),
    "the priority binding label stayed English: " .. tostring(BINDING_NAME_MSUF_PRIORITY_TOGGLE))
print("keybind_labels_locale_smoke: OK")
