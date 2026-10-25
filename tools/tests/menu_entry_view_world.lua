-- Optional owned-source overlay on a supplied, immutable full-graph baseline.
-- Other lanes' half-written source/manifest changes cannot affect this replay.
local owned = {}
for _, file in ipairs({ "MSUF_Menu2_TextQuickSettings.lua", "MSUF_Menu2_PageLifecycle.lua",
    "Preview/MSUF_Menu2_UnitPreview_View_Handles.lua", "Preview/MSUF_Menu2_GroupPreview_Native.lua",
    "Preview/MSUF_Menu2_UnitPreview_Render.lua", "Preview/MSUF_Menu2_UnitPreview_Model.lua",
    "Pages/MSUF_Menu2_GlobalFonts.lua" }) do
    owned["/MidnightSimpleUnitFrames_Options/Shell/Menu2/" .. file] = true
end
local l3Owned = {
    ["/MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Focus.lua"] = true,
    ["/MidnightSimpleUnitFrames/Shell/UI/MSUF_EditPopupUI.lua"] = true,
    ["/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PageLifecycle.lua"] = true,
    ["/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Window_PageEntry.lua"] = true,
    ["/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Layout.lua"] = true,
}
return function(root, flavor, options)
    local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
    local overlay = os.getenv("MSUF_K4_TEST_SOURCE_ROOT")
    if overlay then overlay = overlay:gsub("\\", "/"):gsub("/$", "") end
    local l3Overlay = os.getenv("MSUF_L3_TEST_SOURCE_ROOT")
    if l3Overlay then l3Overlay = l3Overlay:gsub("\\", "/"):gsub("/$", "") end
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
        if overlay or l3Overlay then
            world._l3OverlayLoads = 0
            local load = world.LoadFile
            function world:LoadFile(path, addon, ns)
                local relative = path:sub(#world.root + 1)
                if l3Overlay and l3Owned[relative] then self._l3OverlayLoads = self._l3OverlayLoads + 1 end
                local source = l3Overlay and l3Owned[relative] and (l3Overlay .. relative)
                    or (overlay and owned[relative] and (overlay .. relative)) or path
                return load(self, source, addon, ns)
            end
        end
    end
    local mw = MW.Open(root, flavor, options)
    if l3Overlay then assert(mw.world._l3OverlayLoads == 5, "L3 source overlay did not replace every owned source") end
    return mw
end
