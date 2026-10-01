local root = assert(arg[1])
local World = assert(loadfile(root .. '/tools/tests/client_world.lua'))()
for _, flavor in ipairs({'Mainline', 'Forever', 'Vanilla', 'TBC', 'Mists'}) do
    local world = World.New(root, flavor)
    world:Boot()
    assert(not world:FirstFailure(), flavor .. ': client boot failed')
    local M, GF = world.core.MSUF2, world.core.GF
    world.env.MAX_BOSS_FRAMES = 5
    world.env.PET, world.env.TARGET, world.env.HEALER, world.env.BOSS = 'Pet','Target','Healer','Boss'
    local methods = world.widgets.Methods
    for _, name in ipairs({'EnableKeyboard','SetAutoFocus','SetNumeric','SetMaxLetters','SetTextInsets','ClearFocus','SetCursorPosition','HighlightText','SetPropagateKeyboardInput','SetPropagateMouseWheel','SetValueStep','SetObeyStepOnDrag'}) do
        methods[name] = methods[name] or function() end
    end
    methods.GetFont = methods.GetFont or function() return 'Fonts\\FRIZQT__.TTF', 12, 'OUTLINE' end
    methods.SetChecked = function(self, value) self.checked=value end
    methods.GetChecked = function(self) return self.checked end
    methods.GetValue = function(self) return self.value or self.minimum or 0 end
    M.gfScope = 'raid'
    world.env.MSUF_EnsureDB(true)
    world.env.MSUF_ActiveProfile = 'Default'
    world.env.MSUF_GlobalDB = {profiles={Default=world.env.MSUF_DB},char={},global={}}
    GF.EnsureDB()
    local conf = GF.GetConf('raid')
    conf.enabled, conf.petsEnabled = true, false
    conf.offsetX, conf.offsetY, conf.petsX, conf.petsY = -975, 591, 0, -220
    local box = M.GroupPreview.CreateNative(world.env.UIParent, {width=760,key='gf_layout'})
    box:Show()
    box._stage:SetSize(600,100)
    box._msuf2ZoomLockDefaultPending = true
    box:Refresh('SETTINGS')
    assert(box._manualZoom, flavor .. ': actual initial default lock missing')
    -- Actual settings binding invokes the same write/refresh owners as the menu.
    local ctx = {key='gf_layout',refreshers={}}
    ctx.entry = {key='gf_layout',refreshers=ctx.refreshers,frame=world.env.UIParent}
    M.activeKey = 'gf_layout'
    M.cache = M.cache or {}; M.cache.gf_layout = ctx.entry
    -- Match the page builder's ownership registration so the real ApplyService
    -- can refresh sliders as well as the explicit toggle context refresh.
    box._msufGFNativePreviewPageKey = 'gf_layout'
    M._gfNativePreviews = {box}
    M.TrackRefresh(ctx, function() box:Refresh('SETTINGS') end)
    local toggle = M.Widgets.ToggleAt(world.env.UIParent, 'Enable', 0, 0, 100)
    M.GroupPage.BindScopeToggle(ctx, toggle, 'petsEnabled', false, 'rebuild')
    toggle:SetChecked(true)
    assert(toggle:GetScript('OnClick'))(toggle)
    world.widgets:RunTimers(100)
    assert(GF.GetConf('raid').petsEnabled == true, flavor .. ': actual toggle write failed')
    local function BoundsVisible()
        local sample = assert(box._additionalPreviewRoots.pets)
        assert(sample:IsShown(), flavor .. ': pet root hidden')
        local _,_,_,mx,my = box._mock:GetPoint()
        assert(mx>=-1 and mx+box._mock:GetWidth()<=box._stage:GetWidth()+1, flavor..': main group clipped horizontally')
        assert(my<=1 and my-box._mock:GetHeight()>=-box._stage:GetHeight()-1, flavor..': main group clipped vertically')
        local _,_,_,sx,sy = sample:GetPoint()
        local x,y = mx + box._mock:GetWidth()/2 + sx, my - box._mock:GetHeight()/2 + sy
        assert(x-sample:GetWidth()/2 >= -1 and x+sample:GetWidth()/2 <= box._stage:GetWidth()+1, flavor .. ': pets outside horizontal canvas')
        assert(y+sample:GetHeight()/2 <= 1 and y-sample:GetHeight()/2 >= -box._stage:GetHeight()-1, flavor .. ': pets outside vertical canvas')
        local holder
        for _, child in ipairs({sample:GetChildren()}) do if rawget(child,'buttons') then holder=child end end
        assert(holder and #holder.buttons==3, flavor .. ': actual shared pet renderer absent')
    end
    BoundsVisible()
    local cap = M.GroupPage.ScopeSlider(ctx, world.env.UIParent, 'Maximum pets', 1, 40, 1, 220,
        'petsMaxCount', 40, 'rebuild', 0, 0, 220, 'LEFT')
    cap:GetScript('OnValueChanged')(cap, 1)
    world.widgets:RunTimers(100)
    assert(GF.GetConf('raid').petsMaxCount == 1, flavor .. ': Pet cap slider did not save')
    local visiblePets = 0
    for _, holder in ipairs({box._additionalPreviewRoots.pets:GetChildren()}) do
        for _, button in ipairs(rawget(holder, 'buttons') or {}) do
            if button:IsShown() then visiblePets = visiblePets + 1 end
        end
    end
    assert(visiblePets == 1 and box._mock:IsShown(), flavor .. ': Pet cap slider did not refresh shared preview')
    cap:GetScript('OnValueChanged')(cap, 40)
    world.widgets:RunTimers(100)
    BoundsVisible()
    local overview = box._mockScale
    assert(overview >= .75, flavor .. ': compact shared scene is unnecessarily tiny')
    assert(conf.offsetX==-975 and conf.offsetY==591 and conf.petsX==0 and conf.petsY==-220,
        flavor .. ': menu projection changed runtime positions')
    M.OnCollapsibleSectionStateChanged('gf_layout','group_pets',true,{})
    box:Refresh('SETTINGS')
    BoundsVisible()
    assert(box._mockScale == overview, flavor .. ': accordion displaced the shared scene')
    box._manualZoom = .7
    box:Refresh('SETTINGS')
    assert(box._manualZoom==.7, flavor .. ': refresh lost deliberate zoom')
    M.OnCollapsibleSectionStateChanged('gf_layout','name_bar',true,{})
    box:Refresh('SETTINGS')
    assert(box._manualZoom==.7, flavor .. ': normal accordion reset deliberate zoom')
    M.OnCollapsibleSectionStateChanged('gf_layout','group_pets',false,{})
    assert(box._manualZoom==.7, flavor .. ': unrelated close reset zoom')
    M.OnCollapsibleSectionStateChanged('gf_layout','name_bar',false,{})
    box._manualZoom=nil
    box:Refresh('SETTINGS')
    BoundsVisible()
    box._stage:SetSize(1200,800)
    box:Refresh('SETTINGS')
    BoundsVisible()
    box:Hide()
    local onHide=box:GetScript('OnHide'); if onHide then onHide(box) end
    assert(not box._additionalPreviewRoots.pets:IsShown(), flavor .. ': hide retained pets')
    print(flavor .. ': actual Native/default-lock/toggle/accordion/fit PASS')
end
