-- menu_status_sample_runtime.lua <root> <client> [ownedBaseline]
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local baseline = arg[3] ~= "-" and arg[3] or nil
local mw = Open(root, flavor, { page = "uf_player", beforeCore = function(world)
    local atlasInfo = world.env.C_Texture.GetAtlasInfo
    world.env.C_Texture.GetAtlasInfo = function(atlas)
        if atlas == "UI-HUD-UnitFrame-Player-Rest-Flipbook" then return { width = 252, height = 294 } end
        return atlasInfo(atlas)
    end
    local methods = world.widgets.Methods
    function methods:SetTexture(path) self.texture, self.atlas = path, nil end
    function methods:SetAtlas(atlas) self.atlas, self.texture = atlas, nil end
end }, baseline)
local runtime = assert(mw.core.UFStatusRuntime)
if arg[4] == "budget" then
    local tex = mw.env.UIParent:CreateTexture(nil, "ARTWORK")
    local frame = { MSUFUnitKey = "player", combatStateIndicatorIcon = tex, _msufDispatchActive = true,
        _msufDispatchToken = 1, _msufUnitState = { ready = true, unit = "player", dispatchToken = 1, existsKnown = true, exists = true } }
    local status = { combat = { enabled = true, symbol = "weapon_axes_crossed" }, testMode = true }
    for _ = 1, 8 do runtime.UpdateCombat(frame, status) end
    local vm, calls = 0, 0
    debug.sethook(function(event)
        if event == "count" then vm = vm + 1
        elseif event == "call" and debug.getinfo(2, "S").what ~= "C" then calls = calls + 1 end
    end, "c", 1)
    for _ = 1, 100 do runtime.UpdateCombat(frame, status) end
    debug.sethook()
    local kb = math.huge
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 100 do runtime.UpdateCombat(frame, status) end
        kb = math.min(kb, collectgarbage("count") - before)
        collectgarbage("restart")
    end
    print(string.format("status runtime budget %s %s: %.2f VM, %.2f Lua calls/event; %.3f KiB/100 events",
        flavor, baseline and "before" or "after", vm / 100, calls / 100, kb))
    return
end
local section
for i = 1, 20 do
    local name, value = debug.getupvalue(mw.M.BuildUnitStatusSection, i)
    if name == "StatusSection" then section = value; break end
end
assert(section, "real status section owner was not reached")
local state = {}
section.PrepareIconResolvers(state, "player")
local function Texture() return mw.env.UIParent:CreateTexture(nil, "ARTWORK") end
local function Equal(a, b, label)
    assert(a.texture == b.texture and a.atlas == b.atlas, label .. " sample art differs from runtime: " .. tostring(a.texture) .. "/" .. tostring(a.atlas) .. " vs " .. tostring(b.texture) .. "/" .. tostring(b.atlas))
    local ac, bc = a.texCoord or {}, b.texCoord or {}
    for i = 1, 4 do assert(ac[i] == bc[i], label .. " sample cell differs from runtime") end
end
local general = mw.M.UnitPage.GetGeneral()
local conf = mw.M.UnitPage.GetConf("player")
local sample, live = Texture(), Texture()
-- The old page fabricated a nonexistent symbol path. Runtime rejects that saved value.
conf.combatStateIndicatorSymbol = "unknown_saved_symbol"
local combatSpec = { customIcon = "combatStateIndicatorCustomIcon", iconStyle = "combatStateIndicatorIconStyle" }
local combatEntry = { "combat", "combat", "combatStateIndicatorSymbol" }
if state.ResolvePreviewStatusIcon then
    local path, l, r, t, b, atlas = state.ResolvePreviewStatusIcon(combatSpec, combatEntry)
    if atlas then sample:SetAtlas(atlas) else sample:SetTexture(path); sample:SetTexCoord(l, r, t, b) end
else
    state.PaintPreviewStatusIcon(sample, combatSpec, combatEntry)
end
runtime.UpdateCombat({ MSUFUnitKey = "player", combatStateIndicatorIcon = live, _msufDispatchActive = true,
    _msufDispatchToken = 1, _msufUnitState = { ready = true, unit = "player", dispatchToken = 1, existsKnown = true, exists = true } },
    { combat = { enabled = true, symbol = conf.combatStateIndicatorSymbol }, testMode = true })
Equal(sample, live, "unknown symbol")
assert(type(runtime.ResolveIconSample) == "function", "runtime has no shared sample resolver")
local cardState
local buildCard = section.BuildPreviewCard
section.BuildPreviewCard = function(state, unit)
    buildCard(state, unit)
    cardState = state
end
for _, body in pairs(mw.M.cache[mw.M.activeKey].sections) do
    local entry = body._msuf2CollapsibleEntry
    if entry then entry.SetOpenImmediate(true) end
end
mw:RunTimers()
section.BuildPreviewCard = buildCard
assert(cardState and cardState.RefreshIconPreviewStrip, "actual lazy status card did not build")
local stripCalls, paintStrip = 0, runtime.PaintIconSample
runtime.PaintIconSample = function(...) stripCalls = stripCalls + 1; return paintStrip(...) end
cardState.RefreshIconPreviewStrip({ value = "statusCombat", customIcon = "combatStateIndicatorCustomIcon" }, true)
cardState.RefreshIconPreviewStrip({ value = "eliteicon", customIcon = "eliteIconCustomIcon" }, true)
runtime.PaintIconSample = paintStrip
assert(stripCalls >= 5, "unit strip bypasses runtime sample output")
-- Use the real compiler, including sparse/legacy profile inheritance and intentionally ignored keys.
local compiled = { nameFontSize = 14 }
local function CheckCompiled(spec, entry, label)
    mw.core.UF.Config.Status.CompileUnit(compiled, conf, general, "player")
    local a, b = Texture(), Texture()
    state.PaintPreviewStatusIcon(a, spec, entry)
    runtime.PaintIconSample(b, compiled.status[entry[1]], compiled.status, entry[1], entry[2])
    Equal(a, b, label)
end
conf.combatStateIndicatorSymbol, conf.statusIconsUseMidnightStyle = "weapon_axes_crossed", true
general.statusIconsUseMidnightStyle = false
CheckCompiled(combatSpec, combatEntry, "unit Midnight override")
conf.combatStateIndicatorSymbol, conf.combatStateIndicatorIconStyle = "DEFAULT", "UXPRO"
CheckCompiled(combatSpec, combatEntry, "runtime-ignored combat style")
conf.restedStateIndicatorSymbol, general.restedStateIndicatorSymbol = nil, nil
conf.restingStateIndicatorSymbol = "rested_zzz_compact"
CheckCompiled({ iconStyle = "restedStateIndicatorIconStyle", customIcon = "restedStateIndicatorCustomIcon" },
    { "resting", "resting", "restedStateIndicatorSymbol" }, "legacy resting symbol")
conf.restingStateIndicatorSymbol, general.restingStateIndicatorSymbol = nil, nil
CheckCompiled({}, { "resting", "resting" }, "sparse animated resting default")
assert(conf.restedStateIndicatorSymbol == nil and conf.restingStateIndicatorSymbol == nil, "sample seeded a sparse profile")
-- Resolving assets must never run the full compiler's stateful context/palette branches.
local context, palette = mw.core.UF.PVPIndicatorContextActive, mw.core.UF.Shared.ResolveLevelDifficultyColors
mw.core.UF.PVPIndicatorContextActive = function() error("sample initialized live PvP context") end
mw.core.UF.Shared.ResolveLevelDifficultyColors = function() error("sample overwrote live difficulty palette") end
local readOnlyConfig, readOnlyStatus = {}, {}
runtime.ResolveUnitIconSampleConfig(readOnlyConfig, readOnlyStatus, conf, general, "combat")
mw.core.UF.PVPIndicatorContextActive, mw.core.UF.Shared.ResolveLevelDifficultyColors = context, palette
assert(readOnlyStatus.useMidnight == true, "unit Midnight projection ignored explicit override")
conf.statusIconsUseMidnightStyle, general.statusIconsUseMidnightStyle = false, true
CheckCompiled(combatSpec, combatEntry, "explicit false Midnight override")
-- Custom paths, packs, atlas fallback, and the elite star all pass through the live painters.
for _, entry in ipairs({ { "leader" }, { "assist" }, { "raidMarker", 8 }, { "elite", "RARE" }, { "combat", "combat" },
    { "resting", "resting" }, { "incomingRes", "resurrect" }, { "pvp", "FFA" }, { "role", "TANK" },
    { "readyCheck", "ready" }, { "summon", 2 }, { "phase", "phase" } }) do
    local paint = assert(runtime.ResolveIconSample(entry[1]))
    local cfg = { customIcon = "sample/custom", style = "BLIZZARD" }
    local status = { useMidnight = false }
    assert(runtime.PaintIconSample(sample, cfg, status, entry[1], entry[2]) ~= false)
    assert(sample.texture == cfg.customIcon, entry[1] .. " lost its custom icon")
    assert(runtime.ResolveIconSample(entry[1]) == paint, "sample resolver did not return a stable runtime painter")
end
-- Real group page refresh invokes the same owner, with read-only scalar sample inputs.
local icons = mw.M.GroupIndicatorsParts.StatusIcons
local holders = { mw.env.CreateFrame("Frame", nil, mw.env.UIParent) }
holders[1].tex = Texture()
local groupState = { iconPreviewStrip = mw.env.CreateFrame("Frame", nil, mw.env.UIParent),
    iconPreviewLabel = mw.env.CreateFrame("Frame", nil, mw.env.UIParent), iconPreviewTextures = holders }
local calls, paint = 0, runtime.PaintIconSample
runtime.PaintIconSample = function(...) calls = calls + 1; return paint(...) end
icons.RefreshIconPreviewStrip(groupState, { value = "leaderIcon", customIcon = "leaderIconCustomIcon" }, true)
runtime.PaintIconSample = paint
assert(calls == 1, "group strip bypasses runtime sample output")
assert(general == mw.M.UnitPage.GetGeneral(), "sample replaced the profile")
print("PASS status samples " .. flavor .. ": compiled sparse/legacy parity; read-only projection; real unit/group strips")
