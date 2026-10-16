-- Trusted launch boundary for the immutable historical observer's cmd envelope.
local Launch = {}
function Launch.Adapt(popen, python, root, source, base, windows)
    for _, value in ipairs({ python, root, source, base }) do
        assert(not value:find('["%%\r\n]'), "unsafe historical authentication argument")
        assert(windows or not value:find('[$`\\]'), "unsafe historical POSIX authentication argument")
    end
    assert(#base == 40 and base:match("^[0-9a-f]+$"), "exact historical authentication base required")
    local inner = '"' .. python .. '" "' .. root .. '/tools/tests/menu_section_capture.py" --check-source --source "'
        .. source .. '" --base ' .. base
    local expected = '"' .. inner .. '"'
    local isolated = '"' .. python .. '" -I -S "' .. root .. '/tools/tests/menu_section_capture.py" --check-source --source "'
        .. source .. '" --base ' .. base
    return function(command, mode)
        assert(command == expected and mode == "r", "unexpected historical authentication command")
        return popen(windows and ('"' .. isolated .. '"') or isolated, mode)
    end
end
function Launch.Run(script, root, client, capture)
    root = root:gsub("\\", "/"):gsub("/$", "")
    script = script:gsub("\\", "/")
    local area = script:match("/tools/tests/menu_([a-z_]+)_inventory_smoke%.lua$")
    local areas = { pvp_trinket=true, dispel_overlay=true, dispel_symbol=true, unit_visibility=true,
        boss_arena_layout=true, boss_target_highlight=true }
    assert(areas[area] and script == root .. "/tools/tests/menu_" .. area .. "_inventory_smoke.lua",
        "only the authenticated historical observer entry is allowed")
    assert(capture == "--capture", "historical launcher requires genuine capture")
    local python = assert(os.getenv("MSUF_SECTION_CAPTURE_PYTHON"), "authenticated Python required")
    local source = assert(os.getenv("MSUF_SECTION_SOURCE_ROOT"), "authentic source required"):gsub("\\", "/"):gsub("/$", "")
    local base = assert(os.getenv("MSUF_SECTION_CAPTURE_BASE"), "authentic historical base required")
    io.popen = Launch.Adapt(io.popen, python, root, source, base, package.config:sub(1, 1) == "\\")
    arg = { root, client, capture }
    return assert(loadfile(script))()
end
if arg and arg[0] and arg[0]:gsub("\\", "/"):match("/menu_section_replay_launcher%.lua$") then
    Launch.Run(unpack(arg))
end
return Launch
