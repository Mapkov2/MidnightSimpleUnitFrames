-- Responsibility boundaries and the complete pre-split search rows are pinned.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local base = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"
local function Read(path)
    local file = assert(io.open(path, "rb"), "missing responsibility module: " .. path)
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local partial = { MSUF2 = {}, Require = function() return function() end end }
assert(loadfile(base .. "Pages/MSUF_Menu2_Auras.lua"))("Options", partial)
assert(partial.MSUF2.AurasParts == nil, "unavailable aura providers published a partial dependency handoff")
local groups = {
    { "Pages/MSUF_Menu2_Auras", "Style", "Layout", "Blacklist", "Workspace" },
    { "Pages/MSUF_Menu2_GlobalBars", "Textures", "Shapes", "Highlights" },
    { "Pages/MSUF_Menu2_GroupIndicators", "Spells", "SpellControls" },
    { "MSUF_Menu2_Window", "Chrome", "Lifecycle" },
    { "Pages/MSUF_Menu2_AdvancedColors", "Text", "Frames", "Host" },
}
for _, group in ipairs(groups) do
    local document = group[1] == "MSUF_Menu2_Window" and "MSUF_Menu2.xml"
        or group[1]:find("GlobalBars", 1, true) and "MSUF_Menu2_AfterUnitPreview.xml" or "MSUF_Menu2_AfterGroupPreview.xml"
    local manifest, previous = Read(base .. document):gsub("\\", "/"), 0
    for index = 1, #group do
        local path = group[1] .. (index == 1 and "" or "_" .. group[index]) .. ".lua"
        local source = Read(base .. path)
        local _, lines = source:gsub("\n", "")
        assert(lines <= 1200, path .. ": " .. lines .. " lines exceed responsibility budget 1200")
        assert(not source:find("loadfile", 1, true), path .. ": runtime file loading replaced the manifest")
        local position = assert(manifest:find('file="' .. path .. '"', 1, true), path .. ": absent from load manifest")
        assert(position > previous, path .. ": responsibility modules changed load order")
        previous = position
    end
end
local function Adler(source)
    local a, b = 1, 0
    for index = 1, #source do a = (a + source:byte(index)) % 65521; b = (b + a) % 65521 end
    return b * 65536 + a
end
local hot = {
    -- Source bodies stay byte-for-byte identical; moving them adds no calls,
    -- closures or tables to their event/animation callbacks.
    { "MSUF_Menu2_Window.lua", "AnimateWindowLayout", 31766041 },
    { "MSUF_Menu2_Window.lua", "InstallWindowDragInteractions", 1014960673 },
    { "Pages/MSUF_Menu2_GroupIndicators_Spells.lua", "SpellTilePendingDragOnUpdate", 3826771942 },
    { "Pages/MSUF_Menu2_Auras_Blacklist.lua", "EnsureAuraCombatScanner", 1504377539 },
}
for _, row in ipairs(hot) do
    local source = Read(base .. row[1])
    local body = assert(source:match("(local function " .. row[2] .. "%b().-\nend)\n"), "hot callback missing: " .. row[2])
    assert(Adler(body) == row[3], "moving a module changed its hot callback: " .. row[2])
end
local indexes = {
    { "", 4319, 414937550 },
    { "_Classic", 3910, 2292682288 },
}
for _, row in ipairs(indexes) do
    local source = Read(base .. "Search/MSUF_Menu2_Search_StaticIndex_Data" .. row[1] .. ".lua")
    local blob = assert(source:match("Search%.StaticIndexBlob = %[%=+%[(.-)%]%=+%]"))
    assert(tonumber(source:match("StaticIndexRecordCount = (%d+)")) == row[2], "static search control count changed")
    assert(Adler(blob) == row[3], "static search rows changed: " .. row[1])
end
print("PASS menu page responsibilities: <=1200 lines; complete static search rows unchanged")
