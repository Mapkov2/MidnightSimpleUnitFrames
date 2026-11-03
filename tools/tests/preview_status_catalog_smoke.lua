-- Every client-applicable Unit status row is sampled from the runtime catalog.
local root, flavor = assert(arg[1]):gsub('\\','/'), arg[2] or 'Mainline'
local MenuWorld = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local mw = MenuWorld.Open(root, flavor, { page = 'uf_player', clientScriptBindings = true,
    tocMetadata = true, beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        -- PetXP intentionally refuses to load without the actual client API.
        world.env.GetPetExperience = function() return 68, 100 end
        world.env.HasPetUI = function() return true, true end
    end })
local M, U = mw.M, mw.core.UFPreview
local failures, checks, rows = {}, 0, 0
local function check(value, why)
    checks = checks + 1
    if not value then failures[#failures + 1] = why; print('FAIL ' .. why) end
end
local function settle() mw:RunTimers(20000); M.Theme.StopAllMenuAnimations() end
local function shown(region)
    if not region or region:IsShown() ~= true then return false end
    if region.GetAlpha and region:GetAlpha() <= 0 then return false end
    if region.GetObjectType and region:GetObjectType() == 'FontString' then
        local text = region:GetText()
        if text == nil or text == '' then return false end
    end
    return true
end
local function visual(box, spec)
    if spec.id == 'statusThreat' then return box.mock._body.threatIndicatorText end
    if spec.id == 'statusPetHappiness' then return box.mock._body.petHappinessIndicatorIcon end
    return box.mock.icons[spec.id]
end
settle(); U.SetStatusPreviewMode('all')
for _, unit in ipairs({ 'player', 'target', 'pet', 'boss' }) do
    if mw.core.Client.SupportsUnit(unit == 'boss' and 'boss1' or unit) then
        assert(mw:Select('uf_' .. unit) ~= false); settle()
        local conf, applicable = M.EnsureDB()[unit], {}
        conf.showRaidGroupInName = false
        for _, spec in ipairs(mw.core.UFPreviewSpecs.StatusPreview) do
            if not spec.allowed or spec.allowed(unit) then
                conf[spec.show] = true
                applicable[#applicable + 1] = spec
                rows = rows + 1
            end
        end
        local box = U.active
        box:RequestRefresh('SETTINGS'); settle()
        for _, spec in ipairs(applicable) do
            check(shown(visual(box, spec)), unit .. ':' .. spec.id .. ' configured all sample shown')
        end
        box._animationEnabled = true; box:RequestRefresh('SETTINGS'); settle()
        for _, elapsed in ipairs({ 0.4, 3.2 }) do
            box._animationElapsed = elapsed
            check(U.RefreshAnimation(box) ~= false, unit .. ' animation accepted')
            for _, spec in ipairs(applicable) do
                check(shown(visual(box, spec)), unit .. ':' .. spec.id .. ' all sample survives animation')
            end
        end
        box._animationEnabled = nil
        for _, spec in ipairs(applicable) do conf[spec.show] = false end
        box:RequestRefresh('SETTINGS'); settle()
        for _, spec in ipairs(applicable) do
            check(not shown(visual(box, spec)), unit .. ':' .. spec.id .. ' disabled setting stays hidden')
            check(not box.statusHandles[spec.id]:IsShown(), unit .. ':' .. spec.id .. ' disabled handle stays hidden')
        end
        check(box.layerAvailable.status == false, unit .. ' empty status layer is unavailable')
        for _, spec in ipairs(applicable) do conf[spec.show] = true end
        box:RequestRefresh('SETTINGS'); settle()
        for _, spec in ipairs(applicable) do
            check(shown(visual(box, spec)), unit .. ':' .. spec.id .. ' reenabled setting restores sample')
        end
    end
end
print(string.format('status catalog %s: %d applicable rows, %d checks, %d failures', flavor, rows, checks, #failures))
assert(#failures == 0, table.concat(failures, '\n'))
