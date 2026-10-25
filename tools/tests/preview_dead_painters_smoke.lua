-- preview_dead_painters_smoke.lua <root> <flavor> [budget]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local tests = arg[0]:gsub("\\", "/"):match("^(.*)/") or "."
local Open = assert(loadfile(tests .. "/menu_entry_view_world.lua"))()
local mw = Open(root, flavor, { page = "uf_player" })
local preview = assert(mw.core.UFPreview)
if arg[3] == "budget" then
    local box = assert(preview.active)
    box._animationEnabled, box._animationElapsed = true, .5
    local function Measure(fn)
        for _ = 1, 3 do fn() end
        local instructions, calls = 0, 0
        debug.sethook(function(event)
            if event == "count" then instructions = instructions + 1
            elseif event == "call" and debug.getinfo(2, "S").what ~= "C" then calls = calls + 1 end
        end, "c", 1)
        for _ = 1, 3 do fn() end
        debug.sethook()
        return instructions / 3, calls / 3
    end
    local refreshVM, refreshCalls = Measure(function() preview.Refresh(box, "BUDGET") end)
    local tickVM, tickCalls = Measure(function() assert(preview.RefreshAnimation(box)) end)
    print(string.format("preview_dead_painters budget %s: refresh %.0f VM / %.0f Lua calls; tick %.0f VM / %.0f Lua calls",
        flavor, refreshVM, refreshCalls, tickVM, tickCalls))
    return
end
local remaining = {}
for name, painter in pairs({ SetTex = preview.Model.SetTex, MakeFS = preview.Model.MakeFS,
    textureDependency = preview.RefreshDeps.SetTex, ApplyPreviewFont = preview.RefreshDeps.ApplyPreviewFont }) do
    if painter ~= nil then remaining[#remaining + 1] = name end
end
assert(#remaining == 0, "retired painters remain: " .. table.concat(remaining, ", "))
assert(preview.active and preview.active._msufPreviewScene.complete, "live scene preview did not render")
mw.M.HideSlashMenuAndMinibar(mw.win)
assert(mw.M.Open("uf_player") ~= false)
mw:RunTimers()
assert(preview.active._msufPreviewScene.complete, "live scene preview did not resume")
print("preview_dead_painters_smoke " .. flavor .. ": retired family absent; scene renders and resumes")
