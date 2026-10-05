-- classic_toc_notes_smoke.lua <repoRoot>
--
-- The AddOn list shows each TOC's Notes line. The TBC and Mists core and
-- Options TOCs still called the release a "Classic prototype" on a 6.5 beta
-- (red without the fix). Every shipped core and Options TOC of every client in
-- tools/classic-client-matrix.tsv has one Notes line, and none of them says
-- prototype.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local _, order = World.Clients(root)
local checked = 0
for _, suffix in ipairs(order) do
    for _, toc in ipairs({ World.CoreTOC(suffix), World.OptionsTOC(suffix) }) do
        local text = World.Read(root .. "/" .. toc)
        local notes = {}
        for line in text:gmatch("[^\n]+") do
            local value = line:match("^## Notes:%s*(.-)%s*$")
            if value then notes[#notes + 1] = value end
        end
        assert(#notes == 1, toc .. ": expected one Notes line, found " .. #notes)
        assert(notes[1] ~= "" and not notes[1]:lower():find("prototype", 1, true),
            toc .. ": the AddOn list note still reads '" .. notes[1] .. "'")
        checked = checked + 1
    end
end
assert(checked >= 8, "only " .. checked .. " TOCs checked")
print("classic_toc_notes_smoke: ok (" .. checked .. " TOCs)")
