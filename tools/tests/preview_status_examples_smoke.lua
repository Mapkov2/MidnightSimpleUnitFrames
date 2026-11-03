-- Status examples use private scene configuration and never enable live PvP artwork.
local root, flavor = assert(arg[1]):gsub('\\','/'), arg[2] or 'Mainline'
local MenuWorld = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local mw = MenuWorld.Open(root, flavor, { page = 'uf_target', clientScriptBindings = true,
    tocMetadata = true, beforeCore = MenuWorld.InstallNativeUnitInputs })
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
print(string.format('status examples %s: %d checks, %d failures', flavor, checks, #failures))
assert(#failures == 0, table.concat(failures, '\n'))
