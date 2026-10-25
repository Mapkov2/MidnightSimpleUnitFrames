-- Remaining scalar writes use declared schema policies rather than copied paths.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local base = "MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local policies = {
    ["Pages/MSUF_Menu2_GroupAuras.lua"] = { "J5.GroupAuras.AutoBlacklist" },
    ["Pages/MSUF_Menu2_GlobalBars_Shapes.lua"] = { "J5.GlobalBars.OutlineTexture" },
    ["Pages/MSUF_Menu2_AdvancedClassPower_Layout.lua"] = {
        "J5.ClassPower.SourceToggle", "J5.ClassPower.Alpha", "J5.ClassPower.NilDropdown" },
    ["MSUF_Menu2_ControlSchema.lua"] = { "J5.Schema.Selected" },
}
local frozen = assert(loadfile(root .. "/tools/tests/menu_schema_setter_legacy.lua"))()
for path, ids in pairs(policies) do
    local source = Read(base .. path)
    for _, id in ipairs(ids) do
        assert(source:find("--[[schema setter: " .. id .. "]]", 1, true), "remaining hand-written scalar setter: " .. id)
        assert(frozen[id] and frozen[id].path == base .. path, "missing frozen scalar differential: " .. id)
    end
end
local count = 0
for id, fixture in pairs(frozen) do
    if id:match("^J5%.") then
        assert(Read(fixture.path):find("--[[schema setter: " .. id .. "]]", 1, true), "lost derived policy: " .. id)
        count = count + 1
    end
end
assert(count >= 75, "missing positional container or history-owned scalar conversions")
local ignored = { GlobalFonts = true, UnitText = true, GroupBars = true, UnitSectionShared = true, ColorPainter = true }
local manifest, seen, hand = Read("tools/module-manifest.json"), {}, 0
for path in manifest:gmatch('"path": "([^"\n]+%.lua)"') do
    local page = path:match("^MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_(.+)%.lua$")
    if page and not ignored[page] and not seen[path] then
        seen[path] = true
        local _, found = Read(path):gsub("%f[%a]set%s*=%s*function%f[%W]", "")
        hand = hand + found
    end
end
assert(hand <= 110, "remaining J5 hand setter count grew: " .. hand .. " (budget 110; baseline 116)")
print("PASS remaining scalar writes: " .. count .. " frozen policies; owned hand setters 116 -> " .. hand)
-- A native owner may normalize away non-search metadata. It must preserve
-- the declaration's physical companion writes when re-owning the same widget.
local namespace = { MSUF2 = { Widgets = {} }, CPBuilders = { ExtraAuraDefaults = {} } }
assert(loadfile(arg[2] or root .. "/" .. base .. "MSUF_Menu2_ControlSchema.lua"))("Options", namespace)
local schema = namespace.MSUF2.ControlSchema
local widget = {
    _msuf2RuntimeControlRecord = { controlId = "companion.owner", kind = "color", label = "Color" },
    _msuf2SearchMeta = {},
    _msuf2CommandAction = { get = function() return 0 end, set = function() end },
}
schema.Custom(widget, { id = "companion.owner", kind = "color", scope = "colors", applyDomain = "colors",
    setting = "general.foreground", meta = { companionWrites = { "general.background" } },
    customSetReason = "Writes the foreground and initializes its sibling map." })
schema.Owned(widget, "colors", "colors")
assert(schema.MatchesWrite(widget._msuf2ControlSchema, "general.background"), "native ownership lost companion writes")
print("PASS companion write contract survives native metadata normalization")
