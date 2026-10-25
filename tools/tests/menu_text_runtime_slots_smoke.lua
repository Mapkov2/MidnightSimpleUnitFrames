-- menu_text_runtime_slots_smoke.lua <root> <flavor> [original-source-root]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MW.Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    if not arg[3] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if path:match("MSUF_Menu2_UnitText.lua$") or path:match("MSUF_Menu2_GroupBars.lua$")
            or path:match("MSUF_Menu2_UnitSectionShared.lua$") then path = arg[3] .. path:sub(#root + 1) end
        return load(self, path, addon, ns)
    end
end })
local function Expand()
    for _, section in pairs(mw.M.cache[mw.M.activeKey].sections) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
end
local function Previews()
    local result = {}
    for _, frame in ipairs(mw.world.widgets.frames) do
        for _, region in ipairs(frame.regions or {}) do
            local schema = region._msuf2ControlSchema
            if schema and tostring(schema.id):match("%.preview$") and region.GetText then result[#result + 1] = region end
        end
    end
    return result
end
Expand()
mw:Select("gf_layout")
Expand()
local previews = Previews()
assert(#previews >= 4, "unit/group text previews did not build")
local slotCalls, text = 0, mw.core.UFText
local update = text.UpdateTextSlots
text.UpdateTextSlots = function(slots, count, ...)
    slotCalls = slotCalls + count
    for i = 1, count do slots[i].fs:SetText("RUNTIME-SLOT") end
end
mw.M.RunEntryRefreshers(mw.M.cache.gf_layout, { force = true })
mw:Select("uf_player")
mw.M.RunEntryRefreshers(mw.M.cache.uf_player, { force = true })
local painted = 0
for _, value in ipairs(previews) do
    if tostring(value:GetText()):find("RUNTIME-SLOT", 1, true) then painted = painted + 1 end
end
assert(painted >= 4 and slotCalls >= 4, "menu text samples bypassed runtime text slots")
text.UpdateTextSlots = update
local shared = mw.M.UnitSectionsShared
local value = mw.env.UIParent:CreateFontString()
local modes = { { "CURPERCENT", false, false }, { "ABSORB", false, true }, { "DEFICIT", true, false } }
shared.PaintTextPreview(value, modes, { delimiter = " / ", decimals = true, short = false })
local first = value:GetText()
assert(first:find("63.0%%") and not first:find("63.4%%"), "fraction and value sample disagree")
assert(first:find("INV_Shield_06", 1, true), "absorb icon was lost")
shared.PaintTextPreview(value, modes, { delimiter = " / ", decimals = true, short = false })
assert(value:GetText() == first, "retained text slot cache returned the previous summary")
shared.PaintTextPreview(value, { { "NONE" }, { "NONE" }, { "NONE" } }, {})
assert(value:GetText() == "(none)", "empty slots retained text")
print("menu_text_runtime_slots_smoke " .. flavor .. ": unit/group samples use runtime writers")
