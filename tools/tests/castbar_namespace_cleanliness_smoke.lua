local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local failures = {}
local function Read(path)
    local f = assert(io.open(root .. "/" .. path, "rb"))
    local s = f:read("*a") f:close() return s
end
local files = {
    "MidnightSimpleUnitFrames/Castbars/MSUF_CastbarAnchors.lua",
    "MidnightSimpleUnitFrames/Castbars/MSUF_FocusKickIcon.lua",
    "MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Compat.lua",
    "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua",
    "MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Castbar.lua",
}
for _, path in ipairs(files) do
    local s = Read(path)
    for left, right in s:gmatch("([%w_%.]+) = ([%w_%.]+)[\r\n]") do
        if left == right and left:find("Anchors.", 1, true) then
            failures[#failures + 1] = path .. ": self-assignment " .. left
        end
    end
    if s:find("Frames.focus%s+or Frames.focus") or s:find('(MSUF.Castbars.Frames.Get%([^)]+%)) or %1') then
        failures[#failures + 1] = path .. ": repeated operand"
    end
end
local fixture = assert(loadfile(root .. "/tools/tests/castbar_namespace_fixture.lua"))()
local env = {}
local ns = { Castbars = setmetatable({}, { __index = function(t, k)
    local module = { Get = function() return {} end }
    t[k] = module return module
end }) }
ns.Castbars.Previews.SetupBossCastbarPreviewEditMode = function() end
fixture.Bind(ns, env)
if env.MSUF_SetupBossCastbarPreviewEditMode ~= nil then
    failures[#failures + 1] = "fixture re-exported a removed global"
end
local _, inventoryRows = Read("tools/feature_inventory_allowlist.json"):gsub("group.field.hidemythicgroupsfivetoeight", "")
if inventoryRows ~= 1 then failures[#failures + 1] = "duplicate Mythic inventory row" end
if Read("MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua"):find("if not Config.textureRevision", 1, true) then
    failures[#failures + 1] = "dead revision initializer"
end
for _, why in ipairs(failures) do print(why) end
assert(#failures == 0, "namespace cleanup incomplete")
print("castbar_namespace_cleanliness_smoke: ok")
