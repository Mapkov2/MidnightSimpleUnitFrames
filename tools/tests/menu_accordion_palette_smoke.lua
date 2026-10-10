-- Real lazy sections must keep the selected menu palette after first use.
local root, flavor, preset = assert(arg[1]), assert(arg[2]), assert(arg[3])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, {
    page = "home", clientScriptBindings = true,
    beforeOptions = function(world)
        world.env.MSUF_EnsureDB()
        world.env.MSUF_DB.general.menuAppearancePreset = preset
        for _, scope in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
            world.env.MSUF_DB[scope].enabled = true
        end
    end,
})
local M, T = mw.M, mw.M.Theme
-- This probe exercises menu bindings; the shared world omits native health data.
mw.env.MSUF_UFCore_NotifyConfigChanged = function() return true end
local failures, checks = {}, 0
local function Check(ok, message)
    checks = checks + 1
    if not ok then failures[#failures + 1] = message end
end
local function Same(actual, expected)
    for i = 1, 4 do
        if math.abs((actual[i] or 1) - (expected[i] or 1)) > 0.000001 then return false end
    end
    return true
end
local function Label(entry, phase)
    local disabled = entry.sectionId == "general" and entry.pageKey == "gf_layout"
        and mw.env.MSUF_DB["gf_" .. M.gfScope].enabled == false
        or entry.sectionId == "frame_basics" and mw.env.MSUF_DB.player.enabled == false
    local expected = disabled and T.colors.disabled
        or (T.fontRoleColors and T.fontRoleColors.accordion or T.colors.text)
    local actual = { entry.label:GetTextColor() }
    Check(Same(actual, expected), entry.pageKey .. "/" .. entry.sectionId .. " " .. phase
        .. ": title lost palette: " .. table.concat(actual, ","))
end
local function Exercise(entry)
    entry.SetOpenImmediate(false)
    local before = { entry.headerBg.middle:GetVertexColor() }
    Label(entry, "cold")
    -- The real click and OnShow path builds lazy content and runs its refreshers.
    for cycle = 1, 3 do
        entry.header:Click("LeftButton")
        mw:RunTimers()
        Check(entry.open == true, entry.sectionId .. ": click did not open")
        Label(entry, "open")
        local highlight = entry.headerOpenHighlight
        Check(highlight and highlight.middle:IsShown(), entry.sectionId .. ": open highlight missing")
        MenuWorld.FireScript(entry.header, "OnEnter")
        MenuWorld.FireScript(entry.header, "OnLeave")
        entry.header:Click("LeftButton")
        mw:RunTimers()
        Check(entry.open == false, entry.sectionId .. ": click did not close")
        Label(entry, "closed")
        if preset ~= "midnight" then
            Check(Same({ entry.headerBg.middle:GetVertexColor() }, before),
                entry.sectionId .. ": closed surface changed after lazy build")
        end
        Check(not highlight.middle:IsShown() and entry.headerBg.middle:GetAlpha() == 1,
            entry.sectionId .. ": closing did not restore the base surface")
        local regionCount = #entry.header.regions
        MenuWorld.FireScript(entry.header, "OnEnter")
        MenuWorld.FireScript(entry.header, "OnLeave")
        Check(#entry.header.regions == regionCount, entry.sectionId .. ": hover allocated art")
    end
end
local function DisabledBasics(body)
    local entry = body._msuf2CollapsibleEntry
    local switch = assert(entry.featureSwitch, "Basics feature switch missing")
    switch:Click("LeftButton")
    mw:RunTimers()
    Check(switch:GetChecked() == false, "Basics did not enter disabled state")
    Exercise(entry)
    switch:Click("LeftButton")
    mw:RunTimers()
    Check(switch:GetChecked() == true, "Basics did not leave disabled state")
    Exercise(entry)
end
Check(T.menuAppearancePreset == preset, "fixture did not select the requested appearance")
mw.env.GameTooltip.SetOwner = function() end
mw.env.GameTooltip.AddLine = function() end
mw:Select("gf_layout")
for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    if M.SupportsFrameScope(scope) then
    local selector
    for _, frame in ipairs(mw.world.widgets.frames) do
        if frame._msuf2GuidedSelectScope then selector = frame end
    end
    assert(selector, "group scope selector missing")._msuf2GuidedSelectScope(scope)
    mw:RunTimers()
    Check(M.gfScope == scope, "group scope selector did not select " .. scope)
    local sections = assert(M.cache.gf_layout and M.cache.gf_layout.sections, "group layout missing")
    for _, id in ipairs({ "general", "anchor", "scaling", "portrait", "text", "power", "range", "transparency", "layout_advanced", "sorting" }) do
        Exercise(assert(sections[id], scope .. ": " .. id .. " missing")._msuf2CollapsibleEntry)
    end
    DisabledBasics(sections.general)
    end
end
mw:Select("uf_player")
local unit = assert(M.cache.uf_player.sections)
for _, id in ipairs({ "frame_basics", "portrait", "text", "status_icons" }) do
    if unit[id] then Exercise(unit[id]._msuf2CollapsibleEntry) end
end
local basics = assert(unit.frame_basics)._msuf2CollapsibleEntry
if preset ~= "midnight" then
    local color = { basics.headerBg.middle:GetVertexColor() }
    Check(Same({ color[1], color[2], color[3] }, { T.colors.coreSurface[1], T.colors.coreSurface[2], T.colors.coreSurface[3] }),
        "unit Basics did not use the selected preset surface")
end
DisabledBasics(unit.frame_basics)
-- Semantic status overrides still win, and a later neutral status restores the role.
local entry = assert(unit.portrait)._msuf2CollapsibleEntry
local warning = { 0.72, 0.41, 0.12, 1 }
M.UnitSectionsShared.SetSectionHeaderStatus(unit.portrait, { labelColor = warning, bg = warning })
Check(Same({ entry.label:GetTextColor() }, warning), "explicit warning title was overwritten")
Check(Same({ entry.headerBg.middle:GetVertexColor() }, warning), "explicit warning surface was overwritten")
M.UnitSectionsShared.SetSectionHeaderStatus(unit.portrait)
Label(entry, "status cleared")
if #failures > 0 then error(table.concat(failures, "\n")) end
print("menu_accordion_palette_smoke " .. flavor .. " " .. preset .. ": " .. checks .. " checks passed")
