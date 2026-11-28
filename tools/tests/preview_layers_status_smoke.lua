-- Real preview layer clicks, visible content and status samples in the shipped menu.
local root, flavor, mode = assert(arg[1]):gsub('\\','/'), arg[2] or 'Mainline', arg[3] or 'unit_layers'
local MenuWorld = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local mw = MenuWorld.Open(root, flavor, { page = 'uf_player', clientScriptBindings = true,
    nativeButtonLifecycle = true, tocMetadata = true, beforeCore = function(world)
        MenuWorld.InstallNativeUnitInputs(world)
        local methods = world.widgets.Methods
        methods.GetLeft = function(r) return r.left or 0 end
        methods.GetBottom = function(r) return r.bottom or 0 end
        methods.GetRect = function(r) return r:GetLeft(), r:GetBottom(), math.max(1, r:GetWidth()), math.max(1, r:GetHeight()) end
        world.env.IsShiftKeyDown = function() return false end
        world.env.IsControlKeyDown = function() return false end
        world.env.GetCurrentKeyBoardFocus = function() return nil end
        if arg[4] then
            local load = world.LoadFile
            function world:LoadFile(path, addon, ns)
                if path:match('/MSUF_Menu2_Preview_Dock%.lua$') then path = arg[4] end
                return load(self, path, addon, ns)
            end
        end
    end })
local M, U = mw.M, mw.core.UFPreview
local failures, checks = {}, 0
local function check(condition, label)
    checks = checks + 1
    if not condition then failures[#failures + 1] = label; print('FAIL ' .. label) end
end
local function settle() mw:RunTimers(20000); M.Theme.StopAllMenuAnimations() end
local function gray(color) return color and color[1] == color[2] and color[2] == color[3] end
local function exerciseDisabledPaint()
    local H, T = M.PreviewHelpers, M.Theme
    local parent = mw.env.CreateFrame('Frame', nil, mw.env.UIParent)
    local owner = { layerAvailable = { clock = false }, layerVisibility = { clock = true } }
    local opened = 0
    local opts = H.LayerChipButtonOpts(M.Tr, T.colors, H.PreviewChromePalette(T), {
        IsOn = function() return owner.layerVisibility.clock end,
        OnEnter = function() end,
        OnClick = function()
            if not owner.layerAvailable.clock then opened = opened + 1 end
        end,
    })
    local button = H.CreateLayerButton(parent, owner, { key = 'clock', label = 'Clock', color = { .2, .6, 1 } }, 1, 95, opts)
    owner.layerButtons = { button }
    local function checkGray(label)
        check(gray(button.bg.vertexColor) and gray(button.bar.vertexColor) and gray(button.fs.textColor), label)
    end
    checkGray('disabled preview layer removes all accent colors even with a visible sample')
    button:GetScript('OnEnter')(button)
    H.RefreshSelectedLayerButtons(owner, { _previewLayerKey = 'clock' })
    checkGray('hover on a disabled layer does not restore the accent')
    button:Click('LeftButton')
    check(opened == 1, 'disabled preview layer keeps its settings action')
    owner.layerAvailable.clock, owner.layerVisibility.clock = true, false
    button:Refresh(); settle()
    checkGray('a preview-only hidden layer remains gray while hovered')
    owner.layerVisibility.clock = true
    button:Refresh(); settle()
    check(not gray(button.bar.vertexColor), 'enabled preview layer restores its accent')
    local action = T.Button(parent, 'Open settings', 120, 24)
    action:SetActive(true)
    action:SetEnabled(false)
    check(gray(action._msuf2Label.textColor), 'disabled action uses the neutral label color')
    local switch = M.Widgets.SwitchAt(parent, 'Enable', 16, -40, 100)
    switch:SetChecked(true)
    M.Widgets.SetControlEnabled(switch, false)
    check(switch:GetChecked() and gray(switch._msuf2SwitchFill.vertexColor) and gray(switch._msuf2SwitchEdge.vertexColor),
        'a disabled checked switch keeps its value and loses the accent')
    check(M.OnOffBadge(false).kind == 'disabled' and M.OnOffBadge(true).kind == 'ok', 'off status uses the disabled badge style')
end
local function shown(region)
    if not region or region:IsShown() ~= true then return false end
    if region.GetAlpha and region:GetAlpha() <= 0 then return false end
    if region.GetObjectType and region:GetObjectType() == 'FontString' then
        local text = region:GetText()
        if text == nil or text == '' then return false end
    end
    return true
end
local function unitSetup()
    local db = M.EnsureDB()
    for _, key in ipairs({ 'showName', 'showRaidMarker', 'showLeaderIcon', 'showLevelIndicator',
        'showCombatStateIndicator', 'showRestingIndicator', 'showIncomingResIndicator' }) do db.player[key] = true end
    db.player.portraitMode, db.player.texLayerEnabled = 'LEFT', true
    db.bars.showClassPower = true
    U.active:RequestRefresh('SETTINGS'); settle()
    return U.active, db.player
end
local function checkTargetAuraPadding()
    local model = mw.core.MSUF_Auras3.MenuModel
    local db = M.EnsureDB()
    db.target.hlOverride = false
    model.SetUnitEnabled('target', true)
    for _, kind in ipairs({ 'buff', 'debuff' }) do
        model.SetGroupShown('target', kind, true)
        model.WriteNumber('target', kind .. 'GroupOffsetX', -4, -4096, 4096)
        model.WriteNumber('target', kind .. 'GroupOffsetY', 29, -4096, 4096)
        model.WriteValue('target', kind .. 'Anchor', kind == 'buff' and 'TOPLEFT' or 'TOPRIGHT')
    end
    assert(mw:Select('uf_target') ~= false)
    settle()
    local box = assert(U.active)
    box._manualZoom = 4
    box.layerVisibility.buff, box.layerVisibility.debuff = true, true
    for _, case in ipairs({ {0, 0}, {2, 0}, {0, 3}, {2, 3} }) do
        local thickness, padding = case[1], case[2]
        db.bars.showBarBorder, db.bars.barOutlineThickness = true, thickness
        model.WriteNumber('target', 'buffStylePadding', padding, 0, 16)
        model.WriteNumber('target', 'debuffStylePadding', padding, 0, 16)
        mw.core.UF.Config.RefreshUnit('target')
        U.Refresh(box, 'SETTINGS')
        local body = box.mock._body
        local outline = body.MSUFSpec.border
        local label = ' at outline ' .. thickness .. ', padding ' .. padding
        check((outline.enabled == true) == (thickness > 0) and (thickness == 0 or outline.thickness == thickness),
            'preview uses the requested outline' .. label)
        local seen = {}
        for _, icon in ipairs(body._msufGFFrameAuraPreviews or {}) do
            local kind = icon._sceneAuraKind
            local host = body._msufGFFrameAuraPreviewHosts and body._msufGFFrameAuraPreviewHosts[kind]
            if shown(icon) and host == icon._sceneAuraLayoutHost and icon._sceneAuraIndex == 1 then
                local lane = icon._sceneAuraLane
                local padX, padY = mw.core.MSUF_Auras3.PaddingInset(lane.initialAnchor, padding)
                local _, relative, _, x, y = icon:GetPoint(1)
                local _, owner, _, anchorX, anchorY = host:GetPoint(1)
                local reflow = icon._msufPreviewAuraReflow
                check(lane.padding == padding and relative == host and x == padX and y == padY,
                    kind .. ' preview applies padding once' .. label)
                check(reflow and reflow.x == padX and reflow.y == padY,
                    kind .. ' reflow uses the same inset' .. label)
                check(owner == body and anchorX == -4 and anchorY == 29,
                    kind .. ' preview retains profile offsets' .. label)
                seen[kind] = true
            end
        end
        check(seen.buff and seen.debuff, 'target buff and debuff samples exist' .. label)
    end
end
local function groupSetup()
    assert(mw:Select('gf_layout') ~= false); settle()
    M.gfScope = 'party'; mw.core.GF.EnsureDB()
    local conf = mw.core.GF.GetConf('party')
    conf.enabled, conf.portraitMode, conf.portraitRender = true, 'LEFT', 'CLASS'
    for _, key in ipairs({ 'showName', 'showHPText', 'showPowerText', 'showPower', 'roleIcon', 'leaderIcon',
        'raidMarker', 'readyCheckIcon', 'summonIcon' }) do conf[key] = true end
    mw.core.GF.InvalidateCompiledSpecs('party')
    local box = M.GroupPreview.CreateNative(mw.env.UIParent, { width = 760, key = 'gf_layout' })
    box:Show(); box._stage:SetSize(600,220); box:Refresh('SETTINGS'); settle()
    return box, conf
end
local function unitRegions(box, key)
    local body, result = box.mock._body, {}
    local fields = {
        nameText = { 'nameText', 'totInlineSep', 'totInlineText' },
        hpText = { 'hpTextLeft', 'hpTextCenter', 'hpText' },
        powerText = { 'powerTextLeft', 'powerTextCenter', 'powerText' },
        power = { 'targetPowerBar', 'powerBarBG' }, portrait = { 'MSUFPortraitHolder' },
        dispelOverlay = { '_msufSceneDispelOverlay' }, dispelSymbol = { '_msufSceneDispelSymbol' },
    }
    for _, field in ipairs(fields[key] or {}) do if body[field] then result[#result + 1] = body[field] end end
    if key == 'status' then for _, region in pairs(box.mock.icons) do if region then result[#result + 1] = region end end end
    if key == 'texLayer' then for _, region in pairs(body._msufTexLayers or {}) do result[#result + 1] = region end end
    if key == 'classPower' then result[#result + 1] = box.mock.classPower end
    if key == 'castbar' then result[#result + 1] = box.mock.cast end
    if key == 'bounds' then result[#result + 1] = box.mock.bounds end
    if key == 'buff' or key == 'debuff' or key == 'auras' then
        for lane, region in pairs(body._msufGFFrameAuraPreviewHosts or {}) do
            if lane == key or (key == 'auras' and lane ~= 'buff' and lane ~= 'debuff') then result[#result + 1] = region end
        end
    end
    return result
end
local function groupRegions(box, key)
    local body, result = box._msufGFRenderState.mock._cell, {}
    local fields = { text = { 'nameText', 'hpText', 'hpTextLeft', 'hpTextCenter', 'powerText', 'powerTextLeft', 'powerTextCenter' },
        power = { 'targetPowerBar' }, portrait = { 'MSUFPortraitHolder' },
        status = { 'roleIcon', 'leaderIcon', 'assistIcon', 'raidTargetIcon', 'readyCheckIcon', 'summonIcon',
            'incomingResIndicatorIcon', 'pvpIndicatorIcon', 'phaseIcon', 'raidGroupNameText', 'levelText',
            '_msufScene_statusText', '_msufScene_statusGhostText', '_msufScene_statusAFKText', '_msufScene_statusDNDText', 'statusAFKTimerText' } }
    for _, field in ipairs(fields[key] or {}) do if body[field] then result[#result + 1] = body[field] end end
    return result
end
local function animate(box, refresh, tick)
    box._animationEnabled = true
    refresh('SETTINGS'); settle()
    for _, elapsed in ipairs({ 0.5, 1.7, 4.1 }) do
        box._animationElapsed = elapsed
        check(tick(box) ~= false, 'animation tick accepted')
    end
    box._animationEnabled = nil
    refresh('SETTINGS'); settle()
end
local function exerciseLayers(box, buttons, visible, available, keyOf, refresh, regionList, tick)
    for _, button in ipairs(buttons) do
        local key = keyOf(button)
        if available[key] == false then print('UNAVAILABLE ' .. key)
        else
            if visible[key] == false then button:Click('LeftButton'); settle() end
            check(visible[key] ~= false, key .. ' initial ON')
            local before = {}
            for _, region in ipairs(regionList(box, key)) do if shown(region) then before[#before + 1] = region end end
            local function expectVisual(on, phase)
                for i, region in ipairs(before) do check(shown(region) == on, key .. ' visual ' .. i .. ' ' .. phase) end
            end
            for pass = 1, 2 do
                button:Click('LeftButton'); settle()
                check(visible[key] == false, key .. ' OFF click ' .. pass)
                refresh('SETTINGS'); settle()
                check(visible[key] == false, key .. ' stays OFF after refresh ' .. pass)
                check(available[key] ~= false, key .. ' stays available while preview-hidden ' .. pass)
                expectVisual(false, 'OFF after refresh ' .. pass)
                animate(box, refresh, tick)
                expectVisual(false, 'OFF after animation ' .. pass)
                button:Click('LeftButton'); settle()
                check(visible[key] ~= false, key .. ' ON click ' .. pass)
                refresh('SETTINGS'); settle()
                check(visible[key] ~= false, key .. ' stays ON after refresh ' .. pass)
                expectVisual(true, 'ON after refresh ' .. pass)
                animate(box, refresh, tick)
                expectVisual(true, 'ON after animation ' .. pass)
                -- Restore this in-memory fixture to avoid cascading failures from disabled-chip navigation.
                visible[key] = true; refresh('SETTINGS'); settle()
            end
        end
    end
end
settle()
if mode == 'unit_layers' then
    exerciseDisabledPaint()
    local box = unitSetup()
    U.SetStatusPreviewMode('all'); settle()
    exerciseLayers(box, box.layerButtons, box.layerVisibility, box.layerAvailable,
        function(b) return b.key end, function(reason) box:RequestRefresh(reason) end, unitRegions, U.RefreshAnimation)
    if mw.core.Client.IsRetail then checkTargetAuraPadding() end
elseif mode == 'group_layers' then
    local box = groupSetup()
    M.SetMenuStateValue('gfStatusPreviewMode', 'all'); box:Refresh('SETTINGS'); settle()
    exerciseLayers(box, box._layerButtons, M.gfPreviewLayerVisible, box._layerAvailable,
        function(b) return b._layerKey end, function(reason) box:Refresh(reason) end, groupRegions, function(b) return b:RefreshAnimation() end)
elseif mode == 'unit_status' then
    local box, conf = unitSetup()
    local body = box.mock._body
    local fields = { 'raidTargetIcon', 'leaderIcon', 'assistIcon', 'levelText', 'combatStateIndicatorIcon', 'restingIndicatorIcon', 'incomingResIndicatorIcon' }
    check(U.GetStatusPreviewMode() == 'all', 'unit default status mode is all')
    for _, field in ipairs(fields) do check(shown(body[field]), 'unit default enabled status visible: ' .. field) end
    U.SelectStatusIcon('leader'); U.SetStatusPreviewMode('current'); settle()
    check(shown(body.leaderIcon), 'unit explicit current keeps selected leader')
    check(not shown(body.raidTargetIcon), 'unit explicit current hides other status')
    U.SetStatusPreviewMode('all'); settle()
    for _, field in ipairs(fields) do check(shown(body[field]), 'unit explicit all visible: ' .. field) end
    animate(box, function(reason) box:RequestRefresh(reason) end, function(b)
        local ok = U.RefreshAnimation(b)
        for _, field in ipairs(fields) do check(shown(body[field]), 'unit all persists through animation: ' .. field) end
        return ok
    end)
    conf.showIncomingResIndicator = false; box:RequestRefresh('SETTINGS'); settle()
    check(not shown(body.incomingResIndicatorIcon), 'unit all respects disabled status configuration')
    animate(box, function(reason) box:RequestRefresh(reason) end, function(b)
        local ok = U.RefreshAnimation(b)
        check(not shown(body.incomingResIndicatorIcon), 'unit disabled status stays hidden through animation')
        return ok
    end)
    local statusChip
    for _, button in ipairs(box.layerButtons) do if button.key == 'status' then statusChip = button end end
    statusChip:Click('LeftButton'); settle()
    for _, field in ipairs(fields) do check(not shown(body[field]), 'unit status chip OFF hides: ' .. field) end
    statusChip:Click('LeftButton'); settle()
    check(shown(body.leaderIcon), 'unit status chip ON restores configured status')
elseif mode == 'group_status' then
    local box, conf = groupSetup()
    local body = box._msufGFRenderState.mock._cell
    local fields = { 'roleIcon', 'leaderIcon', 'raidTargetIcon', 'readyCheckIcon', 'summonIcon' }
    check(M.gfStatusPreviewMode == 'all', 'group default status mode is all')
    for _, field in ipairs(fields) do check(shown(body[field]), 'group default enabled status visible: ' .. field) end
    M.SetMenuStateValue('gfStatusPreviewMode', 'current'); M.gfStatusIconSelection = 'leaderIcon'; box:Refresh('SETTINGS'); settle()
    check(shown(body.leaderIcon), 'group explicit current keeps selected leader')
    check(not shown(body.raidTargetIcon), 'group explicit current hides other status')
    M.SetMenuStateValue('gfStatusPreviewMode', 'all'); box:Refresh('SETTINGS'); settle()
    for _, field in ipairs(fields) do check(shown(body[field]), 'group explicit all visible: ' .. field) end
    animate(box, function(reason) box:Refresh(reason) end, function(b)
        local ok = b:RefreshAnimation()
        for _, field in ipairs(fields) do check(shown(body[field]), 'group all persists through animation: ' .. field) end
        return ok
    end)
    conf.summonIcon = false; mw.core.GF.InvalidateCompiledSpecs('party'); box:Refresh('SETTINGS'); settle()
    check(not shown(body.summonIcon), 'group all respects disabled status configuration')
    animate(box, function(reason) box:Refresh(reason) end, function(b)
        local ok = b:RefreshAnimation()
        check(not shown(body.summonIcon), 'group disabled status stays hidden through animation')
        return ok
    end)
    local statusChip
    for _, button in ipairs(box._layerButtons) do if button._layerKey == 'status' then statusChip = button end end
    statusChip:Click('LeftButton'); settle()
    for _, field in ipairs(fields) do check(not shown(body[field]), 'group status chip OFF hides: ' .. field) end
    statusChip:Click('LeftButton'); settle()
    check(shown(body.leaderIcon), 'group status chip ON restores configured status')
else error('unknown mode ' .. tostring(mode)) end
print(string.format('preview layers/status %s %s: %d checks, %d failures', flavor, mode, checks, #failures))
assert(#failures == 0, table.concat(failures, '\n'))
