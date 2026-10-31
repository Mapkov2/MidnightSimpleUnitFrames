-- Group target highlighting belongs to the selected Group Frames scope.
-- Optional arg3 replays the pre-relocation page sources for a negative control.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end }, arg[3])
local M, core = mw.M, mw.core
local scopes, allScopes = { "party", "raid" }, { "party", "raid", "mythicraid" }
if M.SupportsFrameScope("mythicraid") then scopes[#scopes + 1] = "mythicraid" end
if core.Client.IsForever then assert(#scopes == 2, "Forever must not offer Mythic Raid") end
local checks = 0
local function Check(value, reason)
    checks = checks + 1
    assert(value, reason .. "\n" .. table.concat(mw.world.reported, "\n"))
end
local function Settle()
    mw:RunTimers()
    M.Theme.StopAllMenuAnimations()
end
local function TargetControls(page)
    local rows = {}
    for _, widget in ipairs(M.cache[page].searchWidgets or {}) do
        local spec = widget._msuf2ControlSchema
        local setting = spec and spec.setting
        local paths = type(setting) == "string" and { setting } or type(setting) == "table" and setting.keys or {}
        for _, path in ipairs(paths) do
            if path:match("^gf_[^.]+%.targetIndicator$") then rows[#rows + 1] = widget; break end
        end
    end
    return rows
end
local function Select(scope)
    M.SetMenuStateValue("gfScope", scope)
    Check(mw:Select("gf_indicators") ~= false, "Group Frames indicators page did not open")
    Settle()
    Check(M.GroupPage.CurrentScope() == scope, "requested supported group scope was lost")
    local rows = TargetControls("gf_indicators")
    Check(#rows == 1, "Group Frames must expose exactly one selected-scope target switch")
    Check(M.ControlSchema.ResolvePath(rows[1]._msuf2ControlSchema) == "gf_" .. scope .. ".targetIndicator",
        "group target switch resolved to another scope")
    return rows[1]
end
-- Match the canonical menu-reset fixture: retain the clean booted factory profile.
core.GF.EnsureDB()
local factory = assert(core.ProfileFields.CopySnapshot(M.EnsureDB()))
core.MSUF_CreateFactoryDefaultProfile = function() return assert(core.ProfileFields.CopySnapshot(factory)) end
for _, scope in ipairs(allScopes) do
    local conf = core.GF.GetConf(scope)
    conf.targetIndicator, conf.targetR = nil, 0.193
end
for _, scope in ipairs(scopes) do
    local toggle = Select(scope)
    Check(toggle:GetChecked() == true, "unset group target setting must default to on")
    for _, other in ipairs(allScopes) do core.GF.GetConf(other).targetIndicator = true end
    toggle:Click()
    Settle()
    Check(core.GF.GetConf(scope).targetIndicator == false, "click did not persist explicit false")
    for _, other in ipairs(allScopes) do
        if other ~= scope then Check(core.GF.GetConf(other).targetIndicator == true, "click changed another scope") end
        Check(core.GF.GetConf(other).targetR == 0.193, "target switch changed the shared color settings")
    end
    Check(mw:Select("opt_misc") ~= false, "QoL page did not open")
    Settle()
    Check(#TargetControls("opt_misc") == 0, "QoL still contains group target switches")
    toggle = Select(scope)
    Check(toggle:GetChecked() == false, "reopening lost the explicit false setting")
    toggle:Click()
    Settle()
    Check(core.GF.GetConf(scope).targetIndicator == true and toggle:GetChecked() == true,
        "click did not restore the selected scope to true")
    core.GF.GetConf(scope).enabled = false
    M.InvalidatePage("gf_indicators")
    toggle = Select(scope)
    Check(toggle:IsEnabled() ~= false, "disabled group frames prevent configuring target highlighting")
    toggle:Click()
    Check(core.GF.GetConf(scope).targetIndicator == false, "disabled frame scope switch did not write")
end
-- Exercise the real page-reset commands, not the reset helper implementation.
for _, scope in ipairs(allScopes) do core.GF.GetConf(scope).targetIndicator = false end
M.EnsureDB().general.highlightEnabled = false
Check(M.ResetPageToDefaults("opt_misc") == true, "QoL reset failed")
Settle()
Check(M.EnsureDB().general.highlightEnabled ~= false, "QoL reset stopped resetting its own mouseover control")
for _, scope in ipairs(allScopes) do
    Check(core.GF.GetConf(scope).targetIndicator == false, "QoL reset changed a group target setting")
    Check(core.GF.GetConf(scope).targetR == 0.193, "QoL reset changed group target color")
end
Check(M.ResetPageToDefaults("gf_indicators") == true, "Group Frames reset failed")
Settle()
for _, scope in ipairs(allScopes) do
    Check(core.GF.GetConf(scope).targetIndicator ~= false, "Group Frames reset no longer restores every group scope")
end
-- Search uses the normal page keyword catalog and routes into the real page.
local api = M.Search._CoreAPI
for _, query in ipairs({ "group targets", "gruppenziel", "target highlight" }) do
    api.RunSearchInputQuery(query, false)
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then break end
        mw:RunTimers(1000)
    end
    local wanted
    for _, record in ipairs(api.SearchPages(query)) do
        if record.key == "gf_indicators" then wanted = record; break end
    end
    Check(wanted ~= nil, "group target query did not find Group Frames: " .. query)
    Check(api.OpenSearchTarget(wanted.key, query, wanted.label, nil, wanted.route, wanted.exactTarget) ~= false,
        "group target search result did not navigate")
    Settle()
    Check(M.activeKey == "gf_indicators", "group target search routed outside Group Frames")
    Check(#TargetControls("gf_indicators") == 1, "search navigation duplicated the selected target switch")
end
Check(M.ALIASES.target == "uf_target", "group target search replaced the existing Target frame shortcut")
print("menu_group_target_owner_smoke: " .. flavor .. " passed (" .. checks .. " checks)")
