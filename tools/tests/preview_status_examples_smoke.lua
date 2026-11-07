-- Status examples use private scene configuration and never enable live PvP artwork.
local root, flavor = assert(arg[1]):gsub('\\','/'), arg[2] or 'Mainline'
local MenuWorld = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local flagged, warMode = false, false
local mw = MenuWorld.Open(root, flavor, { page = 'uf_target', clientScriptBindings = true,
    tocMetadata = true, beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        local unitExists = world.env.UnitExists
        world.env.UnitExists = function(unit) return unit == "player" or unitExists(unit) end
        world.env.UnitIsPVP = function(unit) return unit == "player" and flagged end
        world.env.C_PvP = {
            IsWarModeDesired = function() return warMode end,
            IsWarModeActive = function() return warMode end,
        }
    end })
local M, U, UF, GF = mw.M, mw.core.UFPreview, mw.core.UF, mw.core.GF
local failures, checks = {}, 0
local function check(value, why)
    checks = checks + 1
    if not value then failures[#failures + 1] = why; print('FAIL ' .. why) end
end
local function settle() mw:RunTimers(20000); M.Theme.StopAllMenuAnimations() end
local function shown(r) return r and r:IsShown() == true and (not r.GetAlpha or r:GetAlpha() > 0) end
local function gated(pvp) return pvp and (pvp.enabled == false or pvp.contextGated == true) end
settle()
check(not UF.PVPIndicatorContextActive(), 'fixture must be outside PvP context')
local cfg = M.EnsureDB().target
for _, key in ipairs({ 'showLeaderIcon', 'showEliteIcon', 'showRaidGroupInName', 'showPvpIndicator' }) do cfg[key] = true end
local live = assert(UF.Config.CompileSpec('target'))
local beforeEnabled, beforeGate = live.status.pvp.enabled, live.status.pvp.contextGated
check(gated(live.status.pvp), 'configured live unit PvP remains gated outside context')
U.SetStatusPreviewMode('all'); U.active:RequestRefresh('SETTINGS'); settle()
local box, frame = U.active, U.active.mock._body
local fields = { 'leaderIcon', 'assistIcon', 'eliteIcon', 'raidGroupNameText', 'pvpIndicatorIcon' }
for _, field in ipairs(fields) do check(shown(frame[field]), 'all target examples includes ' .. field) end
box._animationEnabled = true; box:RequestRefresh('SETTINGS'); settle()
for _, time in ipairs({ 0.3, 1.7, 4.2 }) do
    box._animationElapsed = time
    check(U.RefreshAnimation(box) ~= false, 'unit animation accepted')
    for _, field in ipairs(fields) do check(shown(frame[field]), 'all target animated example includes ' .. field) end
end
box._animationEnabled = nil
check(live.status.pvp.enabled == beforeEnabled and live.status.pvp.contextGated == beforeGate,
    'unit preview did not mutate the independent live spec')
local liveAfter = UF.Config.CompileSpec('target')
check(gated(liveAfter.status.pvp), 'live unit recompile stays context-gated after preview')
check(frame.MSUFSpec.status ~= live.status and frame.MSUFSpec.status.pvp ~= live.status.pvp,
    'unit preview owns independent status and PvP tables')
cfg.showPvpIndicator = false; box:RequestRefresh('SETTINGS'); settle()
check(not shown(frame.pvpIndicatorIcon), 'unit disabled PvP stays hidden in all')
check(frame.MSUFSpec.status.pvp.enabled == false, 'unit private PvP flag respects disabled setting')
assert(mw:Select('gf_layout') ~= false); settle(); M.gfScope = 'party'; GF.EnsureDB()
local conf = GF.GetConf('party')
conf.enabled, conf.pvpIcon = true, true
GF.InvalidateCompiledSpecs('party')
local base = GF.CompileSpec('party')
local basePvP, baseEnabled, baseGate = base.status.pvp, base.status.pvp.enabled, base.status.pvp.contextGated
check(gated(basePvP), 'configured live group PvP remains gated outside context')
M.SetMenuStateValue('gfStatusPreviewMode', 'all')
local group = M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = 'gf_layout' })
group:Show(); group._stage:SetSize(600, 220); group:Refresh('SETTINGS'); settle()
local cell = group._msufGFRenderState.mock._cell
check(shown(cell.pvpIndicatorIcon), 'all group examples includes out-of-context PvP')
check(cell.MSUFSpec.status ~= base.status and cell.MSUFSpec.status.pvp ~= basePvP,
    'group preview owns independent status and PvP overlays')
group._animationEnabled = true; group:Refresh('SETTINGS'); settle()
for _, time in ipairs({ 0.3, 1.7, 4.2 }) do
    group._animationElapsed = time
    check(group:RefreshAnimation() ~= false, 'group animation accepted')
    check(shown(cell.pvpIndicatorIcon), 'all group animated example includes out-of-context PvP')
end
group._animationEnabled = nil
check(base.status.pvp == basePvP and basePvP.enabled == baseEnabled and basePvP.contextGated == baseGate,
    'group preview did not mutate the shared live status/PvP spec')
check(gated(GF.CompileSpec('party').status.pvp), 'live group recompile stays context-gated after preview')
conf.pvpIcon = false; GF.InvalidateCompiledSpecs('party'); group:Refresh('SETTINGS'); settle()
check(not shown(cell.pvpIndicatorIcon), 'group disabled PvP stays hidden in all')
check(cell.MSUFSpec.status.pvp.enabled == false, 'group private PvP flag respects disabled setting')
-- Apply the option while the player's live flag is already set, then exercise
-- the native unit event on the same frame without a spec refresh.
do
    local db = M.EnsureDB()
    local saved = db.player.showPvpIndicator
    local player = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
    player.MSUFUnitKey = "player"
    local prior = UF.frames.player
    local index = #UF.frameList + 1
    UF.frames.player, UF.frameList[index] = player, player
    db.player.showPvpIndicator = false
    UF.Config.RefreshUnit("player")
    UF.ApplySpec(player, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })

    M.unitStatusSelection = M.unitStatusSelection or {}
    M.unitStatusSelection.player = "statusPvp"
    assert(mw:Select("uf_player") ~= false)
    for _, body in pairs(M.cache.uf_player.sections) do
        local entry = body._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    settle()
    local toggle
    for _, widget in ipairs(mw.world.widgets.frames) do
        local contract = widget._msuf2ExactTargetContracts
        if contract and contract.unitStatus and contract.unitStatus.statusPvp == "player.showPvpIndicator" then
            toggle = widget
            break
        end
    end
    assert(toggle, "missing player PvP indicator switch")

    flagged = true
    if flavor == "Mainline" then
        warMode = true
        mw.world:FireEvent("WAR_MODE_STATUS_UPDATE", true)
    end
    mw.world:FireEvent("UNIT_FACTION", "player")
    check(not shown(player.pvpIndicatorIcon), "disabled option must hide the PvP icon")
    toggle:Click("LeftButton")
    local icon = player.pvpIndicatorIcon
    check(db.player.showPvpIndicator == true and shown(icon),
        "enabling the option while flagged must show the player PvP icon immediately")
    toggle:Click("LeftButton")
    check(db.player.showPvpIndicator == false and not shown(icon),
        "disabling the option must hide the icon while the player is still flagged")
    toggle:Click("LeftButton")
    check(shown(icon), "re-enabling the option must show the icon while still flagged")

    flagged = false
    mw.world:FireEvent("PVP_TIMER_UPDATE", "player")
    check(not shown(icon), "the player icon must hide when the native PvP timer event clears the flag")
    mw.world.widgets:SetCombat(true)
    flagged = true
    mw.world:FireEvent("UNIT_FACTION", "player")
    check(icon and icon:IsShown(), "UNIT_FACTION must show the player PvP icon immediately in combat")
    mw.world.widgets:SetCombat(false)
    if flavor == "Forever" then
        flagged = false
        mw.world:FireEvent("PLAYER_PVP_FLAG_CHANGED", false)
        check(not shown(icon), "the native Forever flag event must hide the player icon")
        flagged = true
        mw.world:FireEvent("PLAYER_PVP_FLAG_CHANGED", true)
        check(shown(icon), "the native Forever flag event must show the player icon")
    elseif flavor == "Mainline" then
        check(shown(icon), "War Mode on must show the actual PvP flag")
        mw.world:FireEvent("WAR_MODE_STATUS_UPDATE", false)
        check(not shown(icon), "War Mode off must hide the icon even while WoW still reports PvP")
        warMode = false
        mw.world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        mw.world:FireEvent("UNIT_FACTION", "player")
        mw.world:FireEvent("PVP_TIMER_UPDATE", "player")
        check(not shown(icon), "later flag events must not restore the disabled War Mode icon")

        local reloaded = mw.env.CreateFrame("Button", nil, mw.env.UIParent)
        reloaded.MSUFUnitKey = "player"
        UF.InvalidatePVPIndicatorContext()
        UF.Config.RefreshUnit("player")
        UF.ApplySpec(reloaded, UF.Config.GetSpec("player"), nil, { StatusIndicators = true, PVPIndicator = true })
        check(db.player.showPvpIndicator and not shown(reloaded.pvpIndicatorIcon),
            "with the option enabled, a fresh frame after reload must hide residual War Mode PvP")

        warMode, flagged = true, false
        mw.world:FireEvent("WAR_MODE_STATUS_UPDATE", true)
        check(not shown(icon), "War Mode on must wait for an actual PvP flag")
        flagged = true
        mw.world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        check(shown(icon), "the icon must show when Blizzard confirms the flag in an already open context")
        warMode = false
        mw.world:FireEvent("PLAYER_FLAGS_CHANGED", "player")
        check(not shown(icon), "the icon must follow a confirmed War Mode disable")
    end
    db.player.showPvpIndicator = saved
    UF.frames.player = prior
    table.remove(UF.frameList, index)
end

print(string.format('status examples %s: %d checks, %d failures', flavor, checks, #failures))
assert(#failures == 0, table.concat(failures, '\n'))
