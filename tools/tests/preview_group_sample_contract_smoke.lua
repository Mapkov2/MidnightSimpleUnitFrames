-- preview_group_sample_contract_smoke.lua <repoRoot> <flavor> [budget|portrait|status|inheritance] [baselineDir]
-- A scene repaint must retain what Options requested, without Options repainting its regions.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor, mode = arg[2] or "Mainline", arg[3]
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "gf_layout", beforeCore = function(world)
    -- Native texture/atlas setters replace each other; the permissive shared stubs retain both.
    local methods = world.widgets.Methods
    function methods:SetTexture(texture) self.texture, self.atlas = texture, nil end
    function methods:SetAtlas(atlas) self.atlas, self.texture = atlas, atlas and ("atlas:" .. atlas) end
    world.env.CLASS_ICON_TCOORDS = {}
    for i, class in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE",
        "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER" }) do
        world.env.CLASS_ICON_TCOORDS[class] = { (i - 1) / 13, i / 13, 0, 1 }
    end
    -- Optional causal replay of the two original owners; every other graph file stays current.
    if not arg[4] then return end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local name = path:match("([^/\\]+)$")
        local replay = mode == "inheritance" and name == "MSUF_Menu2_Preview_Scenes.lua"
            or mode ~= "inheritance" and (name == "MSUF_UF_Group_Preview.lua" or name == "MSUF_Menu2_GroupPreview_Render.lua")
        if replay then
            local chunk = assert(loadfile(arg[4] .. "/" .. name))
            setfenv(chunk, self.env)
            local ok, message = pcall(chunk, addon, namespace)
            return ok, message
        end
        return load(self, path, addon, namespace)
    end
end, beforeOptions = function(world)
    world.core.Require("MSUF_EnsureDB", "preview sample test")(true)
    world.env.SetPortraitTexture = function(texture) texture:SetTexture("sample-player-bust") end

end })
local M, env = mw.M, mw.env
local conf = mw.core.GF.GetConf("party")
    conf.enabled, conf.portraitMode, conf.portraitRender = true, "LEFT", "2D"
    for _, key in ipairs({ "levelText", "roleIcon", "raidMarker", "leaderIcon", "assistIcon", "readyCheckIcon",
        "summonIcon", "resurrectIcon", "pvpIcon", "phaseIcon", "statusText", "statusGhostText", "statusAFKText",
        "statusAFKTimerText", "statusDNDText", "showGroupNumber" }) do conf[key] = true end
    mw.core.GF.InvalidateCompiledSpecs("party")
M.gfScope = "party"
local box = M.GroupPreview.CreateNative(env.UIParent, { width = 760, key = "gf_layout" })
box:Show()
box._stage:SetSize(600, 220)
box:Refresh("SETTINGS")
local frame = assert(box._msufGFRenderState.mock._cell)
local rootScene = assert(box._scene)
local group = assert(rootScene.groups.party)
if mode == "budget" then
    box._animationEnabled, box._animationElapsed = true, 0.5
    box:Refresh("SETTINGS")
    for _ = 1, 4 do assert(box:RefreshAnimation()) end
    local instructions, calls = 0, 0
    debug.sethook(function(event)
        if event == "count" then instructions = instructions + 1
        elseif event == "call" and debug.getinfo(2, "S").what ~= "C" then calls = calls + 1 end
    end, "c", 1)
    for _ = 1, 3 do assert(box:RefreshAnimation()) end
    debug.sethook()
    -- Original owners on the identical scene: 45,152 VM instructions and 2,836 Lua calls per tick.
    assert(instructions <= 45152 * 3, "group animation instruction budget regressed")
    assert(calls <= 2836 * 3, "group animation call budget regressed")
    print(string.format("preview_group_sample_contract budget %s: %.0f VM/tick, %.0f Lua calls/tick", flavor,
        instructions / 3, calls / 3))
    return
end
local fields = { "roleIcon", "leaderIcon", "assistIcon", "raidTargetIcon", "readyCheckIcon", "summonIcon",
    "incomingResIndicatorIcon", "pvpIndicatorIcon", "phaseIcon", "raidGroupNameText", "levelText",
    "_msufScene_statusText", "_msufScene_statusGhostText", "_msufScene_statusAFKText", "_msufScene_statusDNDText",
    "statusAFKTimerText" }
local function Snapshot(region)
    return { shown = region:IsShown(), texture = region.GetTexture and region:GetTexture(), atlas = region.GetAtlas and region:GetAtlas(),
        text = region.GetText and region:GetText(), coords = region.GetTexCoord and { region:GetTexCoord() } }
end
local expected = {}
for _, field in ipairs(fields) do if frame[field] then expected[field] = Snapshot(frame[field]) end end
local portrait = assert(frame.portrait)
local texture, portraitState = portrait:GetTexture(), Snapshot(portrait)
assert(frame.MSUFSpec.portrait and frame.MSUFSpec.portrait.enabled, "private menu spec lost inherited portrait configuration")
assert(texture == "sample-player-bust", "menu scene lost the configured native portrait")
M.PreviewHelpers.RestoreGroupSceneHandles(box, true)
group.sample.class = group.sample.class == "MAGE" and "ROGUE" or "MAGE"
group:RefreshData()
group:Refresh({ immediate = true })
if mode ~= "status" then
    assert(portrait:GetTexture() == texture, "scene repaint discarded the owner's portrait sample")
    local coords = { portrait:GetTexCoord() }
    for i, value in ipairs(portraitState.coords) do assert(coords[i] == value, "portrait coordinates changed on scene repaint") end
end
if mode ~= "portrait" then
    for field, state in pairs(expected) do
        local actual = Snapshot(assert(frame[field]))
        assert(actual.shown == state.shown, field .. " visibility changed on scene repaint")
        assert(actual.texture == state.texture, field .. " texture changed on scene repaint")
        assert(actual.text == state.text, field .. " text changed on scene repaint")
        for i, value in ipairs(state.coords or {}) do assert(actual.coords[i] == value, field .. " coordinates changed on scene repaint") end
    end
end
-- Sample and layer changes must be consumed by the scene even without an Options refresh.
if mode == nil then
    local sample = assert(group.sample)
    assert(sample.portrait and sample.statusRegions, "missing explicit scene sample contract")
    -- The renderer may move/adopt these visuals, but only the engine may paint them.
    for _, field in ipairs(fields) do
        local region = frame[field]
        if region then
            for _, method in ipairs({ "SetText", "SetTexture", "SetTexCoord", "SetShown" }) do
                local native = region[method]
                if native then region[method] = function(self, ...)
                    local source = debug.getinfo(2, "S").source
                    assert(not source:find("MSUF_Menu2_GroupPreview_Render.lua", 1, true), "Options repainted " .. field)
                    return native(self, ...)
                end end
            end
        end
    end
    for _, field in ipairs({ "portrait", "MSUFPortraitHolder" }) do
        local region = frame[field]
        for _, method in ipairs({ "SetTexture", "SetTexCoord", "SetShown" }) do
            local native = region[method]
            region[method] = function(self, ...)
                local source = debug.getinfo(2, "S").source
                assert(not source:find("MSUF_Menu2_GroupPreview_Render.lua", 1, true), "Options repainted " .. field)
                return native(self, ...)
            end
        end
    end
    box:Refresh("SETTINGS")
    sample.portrait.texture = "replacement-bust"
    group:RefreshData()
    assert(portrait:GetTexture() == "replacement-bust", "changed portrait sample was ignored")
    group:SetLayerFilter({ portrait = false, status = false })
    assert(not frame.MSUFPortraitHolder:IsShown(), "portrait layer ignored")
    for _, field in ipairs(fields) do if frame[field] then assert(not frame[field]:IsShown(), field .. " status layer ignored") end end
    group:SetLayerFilter({})
    assert(frame.MSUFPortraitHolder:IsShown(), "portrait did not restore")
    rootScene:Deactivate()
    assert(not group:IsActive(), "closed scene stayed active")
    rootScene:Activate()
    assert(portrait:GetTexture() == "replacement-bust", "reopen discarded sample")
    -- Cast, class and native portrait transitions reuse the same engine texture.
    sample.portrait.texture, sample.portrait.l, sample.portrait.r = "cast-spell", 0.08, 0.92
    sample.portrait.t, sample.portrait.b = 0.08, 0.92
    rootScene:SetClock(0.8)
    assert(portrait:GetTexture() == "cast-spell", "clock repaint lost cast icon")
    local l, r = portrait:GetTexCoord()
    assert(l == 0.08 and r == 0.92, "cast icon crop was lost")
    sample.portrait.texture = nil
    group:Refresh({ immediate = true })
    assert(portrait:GetTexture() ~= "cast-spell", "class portrait retained cast icon")
    sample.portrait.texture = "native-return"
    sample.portrait.l, sample.portrait.r, sample.portrait.t, sample.portrait.b = 0, 1, 0, 1
    group:RefreshData()
    assert(portrait:GetTexture() == "native-return", "native portrait did not restore")
    conf.portraitRender, conf.portraitCastSpellIcon = "CLASS", true
    mw.core.GF.InvalidateCompiledSpecs("party")
    box._animationEnabled, box._animationElapsed = true, 0.4
    box:Refresh("SETTINGS")
    local cast = assert(group.sample.portrait.texture, "fixture has no cast icon")
    assert(frame.MSUFSpec.portrait.render == "CLASS" and frame._msufPortraitRuntimeCfg.render == "2D",
        "cast example did not use a private portrait view")
    assert(portrait:GetTexture() == cast and conf.portraitRender == "CLASS", "CLASS cast sample changed saved configuration")
    assert(frame._msufPortraitRuntimeCfg.panOffsetX == 0 and frame._msufPortraitRuntimeCfg.panOffsetY == 0,
        "CLASS cast sample changed image geometry")
    box._animationElapsed = 4.7
    assert(box:RefreshAnimation())
    assert(portrait:GetTexture() == group.sample.portrait.texture, "animated CLASS cast icon drifted")
    box._animationEnabled = nil
    box:Refresh("SETTINGS")
    assert(frame._msufPortraitRuntimeCfg.render == "CLASS" and portrait:GetTexture() ~= cast,
        "CLASS art did not restore after animation stopped")
end
print("preview_group_sample_contract_smoke: PASS " .. flavor .. " " .. (mode or "all"))
