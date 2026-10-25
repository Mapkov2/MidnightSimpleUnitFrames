-- Optional owned-source overlay on a supplied, immutable full-graph baseline.
-- Other lanes' half-written source/manifest changes cannot affect this replay.
local owned = {}
for _, file in ipairs({ "MSUF_Menu2_TextQuickSettings.lua", "MSUF_Menu2_PageLifecycle.lua",
    "Preview/MSUF_Menu2_UnitPreview_View_Handles.lua", "Preview/MSUF_Menu2_GroupPreview_Native.lua",
    "Preview/MSUF_Menu2_UnitPreview_Render.lua", "Preview/MSUF_Menu2_UnitPreview_Model.lua",
    "Pages/MSUF_Menu2_GlobalFonts.lua" }) do
    owned["/MidnightSimpleUnitFrames_Options/Shell/Menu2/" .. file] = true
end
return function(root, flavor, options)
    local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local overlay = os.getenv("MSUF_K4_TEST_SOURCE_ROOT")
    if overlay then overlay = overlay:gsub("\\", "/"):gsub("/$", "") end
    local beforeCore = options.beforeCore
    options.beforeCore = function(world)
        -- WoW publishes named frames in _G. The base widget fixture only
        -- stores their names, which otherwise recreates secure nudge buttons.
        local create = world.env.CreateFrame
        world.env.CreateFrame = function(kind, name, parent, template)
            local frame = create(kind, name, parent, template)
            if name then world.env[name] = frame end
            return frame
        end
        if beforeCore then beforeCore(world) end
        if overlay then
            local load = world.LoadFile
            function world:LoadFile(path, addon, ns)
                local relative = path:sub(#root + 1)
                return load(self, owned[relative] and (overlay .. relative) or path, addon, ns)
            end
        end
    end
    return MW.Open(root, flavor, options)
end
