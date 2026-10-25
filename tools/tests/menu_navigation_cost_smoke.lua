-- Menu navigation through the real world, including NavRail -> ButtonClickProxy.
-- <root> [flavor] [report] [optional Options-only source overlay]
-- Reuse native setter storage as in menu_preview_repaint_budget_smoke; count all
-- widget method calls. Full first builds include fixture allocations. No Suite
-- skin is loaded here, and these VM counts include the simulated native methods.
local root = assert(arg[1]):gsub('\\', '/'):gsub('/$', '')
local overlay = arg[4]
local flavor, report = arg[2] or 'Mainline', arg[3] == 'report'
local MW = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local natives, ticks, frames = 0, 0, 0
local coldLoad
local function Tick() ticks = ticks + 1 end
local function Measure(label, fn, n)
    collectgarbage('collect'); collectgarbage('stop')
    local kb, beforeNative, beforeFrames = collectgarbage('count'), natives, frames
    ticks = 0
    debug.sethook(Tick, '', 100)
    for i = 1, n or 1 do fn() end
    debug.sethook()
    local delta = collectgarbage('count') - kb
    collectgarbage('restart')
    return { vm = ticks * 100 / (n or 1), kb = delta / (n or 1),
        native = (natives-beforeNative)/(n or 1), frames = (frames-beforeFrames)/(n or 1) }
end
local function Reuse(self, field, a,b,c,d)
    local t = rawget(self,field)
    if not t then t={}; rawset(self,field,t) end
    t[1],t[2],t[3],t[4]=a,b,c,d
end
local function Install(world)
    world.env.IsControlKeyDown = function() return false end
    world.env.IsShiftKeyDown = function() return false end
    if overlay and overlay ~= '-' then
        local load = world.LoadFile
        function world:LoadFile(path, addon, ns)
            local suffix = path:sub(#root+1)
            if suffix:find('/MidnightSimpleUnitFrames_Options/',1,true) == 1 then path = overlay .. suffix end
            return load(self,path,addon,ns)
        end
    end
    local create=world.env.CreateFrame
    world.env.CreateFrame=function(kind,name,parent,template)
        frames=frames+1
        local frame=create(kind,name,parent,template)
        if name then world.env[name]=frame end
        if name == "MSUF2_Window" or name == "MSUF2_MinimizedWindow" then MW.FireVisibilityScripts(frame) end
        return frame
    end
end
local function NativeMethods(world)
    local methods=world.widgets.Methods
    for name,field in pairs({SetVertexColor='vertexColor',SetTexCoord='texCoord',SetBackdropColor='backdropColor',
        SetBackdropBorderColor='backdropBorderColor',SetStatusBarColor='statusBarColor',SetTextColor='textColor',
        SetShadowColor='shadowColor'}) do
        methods[name]=function(self,a,b,c,d) Reuse(self,field,a,b,c,d) end
    end
    methods.SetColorTexture=function(self,a,b,c,d)
        self.texture=nil; Reuse(self,'colorTexture',a,b,c,d); Reuse(self,'vertexColor',a,b,c,d)
    end
    methods.SetShadowOffset=function(self,x,y) Reuse(self,'shadowOffset',x,y) end
    methods.SetGradient=function(self,o,a,b)
        local t=rawget(self,'gradient'); if not t then t={}; self.gradient=t end
        t.orientation,t.from,t.to=o,a,b
    end
    methods.SetPoint=function(self,point,relativeTo,relativePoint,x,y)
        if type(relativeTo)=='number' then
            relativeTo,relativePoint,x,y=self.parent,point,relativeTo,relativePoint
        elseif type(relativeTo)=='string' then
            relativeTo=assert(world.env[relativeTo], 'unknown named anchor '..relativeTo)
        end
        local pool=rawget(self,'_pp'); if not pool then pool={}; self._pp=pool end
        local n=#self.points+1
        for i=1,#self.points do if self.points[i].point==point then n=i; break end end
        local e=pool[n]; if not e then e={}; pool[n]=e end
        e.point,e.relativeTo,e.relativePoint,e.x,e.y=point,relativeTo or self.parent,relativePoint or point,x or 0,y or 0
        self.points[n]=e
    end
    for name,fn in pairs(methods) do
        if type(fn)=='function' then methods[name]=function(...) natives=natives+1; return fn(...) end end
    end
    local loaded = false
    local loadGraph = world.LoadGraph
    world.env.C_AddOns.IsAddOnLoaded = function(addon)
        local ready = addon == "MidnightSimpleUnitFrames_Options" and loaded
        return ready, ready
    end
    world.env.C_AddOns.LoadAddOn = function(addon)
        assert(addon == "MidnightSimpleUnitFrames_Options", "unexpected demand load " .. tostring(addon))
        assert(not loaded, "Options loaded twice")
        loadGraph(world, addon, world.optionsPaths, world.options)
        local failure = world:FirstFailure()
        assert(not failure, failure and failure.message)
        loaded = true
        world.core.MSUF2.ApplyService.Flush = function() return true end
        return true
    end
    world.core.Require("MSUF_EnsureDB", "menu_navigation_cost_smoke")(true)
    assert(loadfile(root .. "/tools/tests/unit_scene_region_fixture.lua"))().Install(world.core)
    coldLoad = Measure("cold-keybind-load", world.env.MSUF_Keybind_ToggleOptions)
    assert(loaded and world.core.OptionsLODReady, "keybind did not demand-load Options")
    assert(not world.core.MSUF2.frame, "cold keybind built the window before its deferred open")
    -- MenuWorld's following automatic Options load is already satisfied by the
    -- real keybind -> OptionsLoader -> LoadAddOn boundary just measured.
    function world:LoadGraph(addon, paths, ns)
        if addon ~= "MidnightSimpleUnitFrames_Options" then return loadGraph(self, addon, paths, ns) end
    end
end

local mw=MW.Open(root,flavor,{open=false,clientScriptBindings=true,beforeCore=Install,beforeOptions=NativeMethods})
local M=mw.M
-- The fixture defaults to no addons loaded; this world has just loaded Options.
mw.env.C_AddOns.IsAddOnLoaded=function() return true,true end
local function Settle() mw:RunTimers(); M.Theme.StopAllMenuAnimations() end
local function Record(label, result)
    if report then
        print(string.format('%s VM=%.0f KB=%.3f native=%.0f frames=%.0f', label,
            result.vm, result.kb, result.native, result.frames))
    end
    return result
end
Record('cold-keybind-load',coldLoad)
Record('first-open',Measure('first-open',Settle))
assert(M.frame and M.frame:IsShown(), 'deferred first open did not show the window')
assert(not M.Search.StaticIndex.IsDecoded(), 'opening decoded the hidden search index')
for key in pairs(M.cache) do assert(key=='home','opening built hidden page '..key) end
mw.win=M.frame; MW.FireVisibilityScripts(mw.win)
if M.minimizedBar then MW.FireVisibilityScripts(M.minimizedBar) end
local pages={'opt_colors','opt_bars','opt_misc','uf_player','gf_layout','gf_auras','classpower',
    'opt_fonts','opt_castbar','gf_bars','gf_indicators','auras3_styling'}
local function Click(key)
    M.navLastPageForPrimary[key]=key
    local b=M.navButtons[key]
    if b then b:Click() else M.SelectPage(key) end
    assert(M.activeKey==key, 'wrong page '..key..' got '..tostring(M.activeKey))
end
for _,key in ipairs(pages) do
    Record('first-'..key,Measure(key,function() Click(key); Settle() end))
    Click('home'); Settle()
end
-- Two allocation windows, minimum: collecting may shrink Lua's string table.
local function WarmMeasure(label, fn)
    for i=1,3 do fn() end
    local a,b=Measure(label,fn,10),Measure(label,fn,10)
    assert(a.frames==0 and b.frames==0,label..' created frames after warm-up')
    if b.kb<a.kb then a=b end
    return Record(label,a)
end
-- Preparation is outside the sampled interval, so each row is one direction.
local function PreparedMeasure(fn, prepare)
    collectgarbage('collect'); collectgarbage('stop')
    local vm, kb, nc, fc = 0, 0, 0, 0
    for i = 1, 10 do
        prepare()
        local beforeKB, beforeNative, beforeFrames = collectgarbage('count'), natives, frames
        ticks = 0
        debug.sethook(Tick, '', 100)
        fn()
        debug.sethook()
        vm, kb = vm + ticks * 100, kb + collectgarbage('count') - beforeKB
        nc, fc = nc + natives - beforeNative, fc + frames - beforeFrames
    end
    collectgarbage('restart')
    return { vm = vm / 10, kb = kb / 10, native = nc / 10, frames = fc / 10 }
end
local function WarmPrepared(label, fn, prepare)
    for i = 1, 3 do prepare(); fn() end
    local a, b = PreparedMeasure(fn, prepare), PreparedMeasure(fn, prepare)
    assert(a.frames == 0 and b.frames == 0, label .. ' created frames after warm-up')
    if b.kb < a.kb then a = b end
    return Record(label, a)
end
local results={}
for _,key in ipairs(pages) do
    results[key]=WarmMeasure('warm-'..key..'-home',function() Click(key); Settle(); Click('home'); Settle() end)
end
local function Reopen()
    mw.env.MSUF_Keybind_ToggleOptions(); Settle()
    mw.env.MSUF_Keybind_ToggleOptions(); Settle()
    assert(mw.win:IsShown())
end
WarmMeasure('close-open-home',Reopen)
for _, key in ipairs(pages) do
    WarmPrepared('switch-home-to-' .. key, function() Click(key); Settle() end, function() Click('home'); Settle() end)
end
Click('home'); Settle()
WarmPrepared('warm-open-home', function() mw.env.MSUF_Keybind_ToggleOptions(); Settle() end,
    function() mw.env.MSUF_Keybind_ToggleOptions(); Settle() end)
-- These are round trips, with real deferred preview work and simulated
-- widget-method calls included. They do not establish a client millisecond target.
-- 343bd63d4, native same-point replacement: Misc 68,430 VM / 14.626 KB /
-- 1,231 widget calls; Colors 782,880 VM / 186.837 KB / 10,928 widget calls. Guard the removed repeated work. The remaining
-- preview/history allocations are explicitly not a zero-allocation claim.
if flavor=='Mainline' then
    assert(results.opt_misc.vm<68000 and results.opt_misc.kb<14,'cached Misc navigation regressed')
    assert(results.opt_colors.kb<80,'cached Colors target rebinding regressed')
end
print('menu_navigation_cost_smoke: ok '..flavor)
