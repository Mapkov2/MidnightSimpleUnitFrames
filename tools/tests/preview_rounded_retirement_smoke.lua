-- preview_rounded_retirement_smoke.lua <root> [original-source-root]
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, "Mainline", { page = "home", beforeCore = function(world)
    if not arg[2] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_Preview_Rendering.lua$") then path = arg[2] .. path:sub(#root + 1) end
        return load(self, path, addon, ns)
    end
end })
local h = mw.M.PreviewHelpers
for _, key in ipairs({ "ResolveRoundedMedia", "ResolveFrameBarMedia", "ApplyRoundedMediaSlice", "MaskOwner",
    "EnsureRoundedMask", "SetMask", "ClearMasks", "EnsureRoundedVisuals", "ForEachRoundedEdge",
    "SetRoundedEdgeStackShown", "ApplyRoundedEdgeStack", "BaseEdgeColor" }) do
    assert(h[key] == nil, "retired renderer remains loaded: " .. key)
end
assert(h.SnapOff and h.LayoutEdgeLines and h.SetEdgeLinesShown and h.ClampEdgeSize, "bounds helpers were removed")
local frame = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
assert(h.LayoutEdgeLines(frame, 2))
for _, key in ipairs({ "top", "bottom", "left", "right" }) do assert(frame._lines[key]:IsShown()) end
h.SetEdgeLinesShown(frame, false)
for _, line in pairs(frame._lines) do assert(not line:IsShown()) end
print("preview_rounded_retirement_smoke: dead family absent; bounds draw and hide")
