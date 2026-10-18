-- Finite real-consumer aura parity: legacy observations plus the reviewed native unit-scene migration.
local root,flavor=assert(arg[1]),assert(arg[2])
root=root:gsub("\\", "/"):gsub("/$", "")
local World=assert(loadfile(root.."/tools/tests/client_world.lua"))()
local w=World.New(root,flavor)
w.env.MAX_BOSS_FRAMES=5
w:Boot()
assert(not w:FirstFailure(),"original graph boot failed")
w.env.MSUF_EnsureDB(true)
local seen,found={},{}
local function Visit(fn)
    if type(fn)~="function" or seen[fn] then return end
    seen[fn]=true
    for i=1,60 do
        local name,child=debug.getupvalue(fn,i)
        if not name then break end
        if name=="RenderPreviewIcon" or name=="CreateAuraPreviewIcon" or name=="ReadMiniAuraPreviewConfig" then found[name]=child end
        if type(child)=="function" then Visit(child) end
    end
end
Visit(w.core.MSUF2.AurasPage.BuildAuraStylePreviewWorkbench)
assert(found.RenderPreviewIcon and found.CreateAuraPreviewIcon and found.ReadMiniAuraPreviewConfig)
local function Copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,child in pairs(value) do result[key]=Copy(child) end
    return result
end
local function Keys(value)
    local keys={}
    for key in pairs(value) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    return keys
end
local function Serialize(value)
    local kind=type(value)
    if kind=="string" then return string.format("%q",value) end
    if kind=="number" or kind=="boolean" then return tostring(value) end
    if kind=="nil" then return "nil" end
    assert(kind=="table",kind)
    local parts={"{"}
    for _,key in ipairs(Keys(value)) do parts[#parts+1]="["..Serialize(key).."]="..Serialize(value[key]).."," end
    parts[#parts+1]="}"
    return table.concat(parts)
end
local OMIT={ __env=true,parent=true,children=true,regions=true,masks=true,scripts=true,events=true,attributes=true }
local function Snapshot(icon)
    local labels,objects={[icon]="icon"},{icon}
    local function Descendant(region)
        local current=region
        for _=1,15 do
            if current==icon then return true end
            current=type(current)=="table" and rawget(current,"parent") or nil
            if not current then return false end
        end
        return false
    end
    local function Discover(value,path,depth)
        if type(value)~="table" or depth>8 then return end
        if rawget(value,"objectType") then
            if not Descendant(value) or labels[value] then return end
            labels[value]=path
            objects[#objects+1]=value
        end
        for _,key in ipairs(Keys(value)) do
            if not OMIT[key] and key~="points" and type(value[key])=="table" then Discover(value[key],path.."."..tostring(key),depth+1) end
        end
    end
    for _,key in ipairs(Keys(icon)) do
        if not OMIT[key] and type(icon[key])=="table" then Discover(icon[key],"icon."..tostring(key),1) end
    end
    local function Plain(value,depth)
        local kind=type(value)
        if kind=="function" or kind=="userdata" then return nil end
        if kind~="table" then return value end
        if rawget(value,"objectType") then return labels[value] or (value==w.env.UIParent and "UIParent" or "external-region") end
        if depth>5 then return "depth-limit" end
        local result={}
        for key,child in pairs(value) do
            if type(key)=="string" or type(key)=="number" then result[key]=Plain(child,depth+1) end
        end
        return result
    end
    local result={}
    for _,object in ipairs(objects) do
        local fields={}
        for key,value in pairs(object) do
            if type(key)=="string" and key:sub(1,1)~="_" and not OMIT[key] then fields[key]=Plain(value,1) end
        end
        local current,visible=object,true
        for _=1,15 do
            if not current then break end
            if current.shown==false then visible=false end
            current=rawget(current,"parent")
        end
        fields.ancestorVisible=visible
        result[labels[object]]=fields
    end
    return result
end

-- The discovery walks the shipped closures; no replacement painter or expected candidate output.
local ownership={
 unit="MSUF_Menu2_UnitPreview_Auras.lua", mini="MSUF_Menu2_Auras_Preview.lua",
 groupMenu="MSUF_Menu2_GroupPreview_Render.lua", groupCore="MSUF_UF_Group_Preview.lua",
 edit="MSUF_Auras3_EditMode_Preview.lua", effects="MSUF_Auras3_Runtime_EffectPreview.lua",
}
local bySurface,seenFn,seenTables={},{},{}
for key in pairs(ownership) do bySurface[key]={} end
local function Remember(name,fn)
 local source=debug.getinfo(fn,"S").source
 for key,filename in pairs(ownership) do if source:sub(-#filename)==filename then bySurface[key][name]=fn end end
end
local WalkFunction,WalkTable
WalkFunction=function(fn,name,depth)
 if type(fn)~="function" or seenFn[fn] or depth>18 then return end
 seenFn[fn]=true;Remember(name,fn)
 for index=1,60 do
  local childName,child=debug.getupvalue(fn,index)
  if not childName then break end
  if type(child)=="function" then WalkFunction(child,childName,depth+1)
  elseif type(child)=="table" and not rawget(child,"objectType") and childName~="_G" and childName~="env" then WalkTable(child,depth+1) end
 end
end
WalkTable=function(tbl,depth)
 if seenTables[tbl] or depth>12 or rawget(tbl,"objectType") then return end
 seenTables[tbl]=true
 for key,value in pairs(tbl) do
  if type(value)=="function" then WalkFunction(value,tostring(key),depth+1) end
 end
end
local c=w.core
for _,tableRoot in pairs({c.UFPreviewAuras,c.MSUF2.AurasPage,c.MSUF2.GroupPreviewRender,c.GF,c.MSUF_Auras3.EditMode,c.MSUF_Auras3.Runtime and c.MSUF_Auras3.Runtime.EffectPreview or {}}) do if type(tableRoot)=="table" then WalkTable(tableRoot,0) end end

if not bySurface.groupMenu.PlaceAuraPreviewText then
 bySurface.groupMenu.PlaceAuraPreviewText=assert(c.MSUF_Auras3.MockAuraPainter).PlaceText
end
if not bySurface.mini.PlaceAuraPreviewText then
    -- RenderPreviewIcon passes this literal mini flag to the shared painter.
    local actual = assert(c.MSUF_Auras3.MockAuraPainter).PlaceText
    bySurface.mini.PlaceAuraPreviewText = function(fs, icon, anchor, x, y)
        return actual(fs, icon, anchor, x, y, "WORKBENCH")
    end
end

local fixture = assert(loadfile(root .. "/tools/tests/fixtures/aura-mock-painter-1400.lua"))()
local expected = assert(fixture.expected[flavor])
local cases, checked = 0, {}
local function Digest(bytes)
    local first, second = 0, 0
    for i = 1, #bytes do
        local byte = bytes:byte(i)
        first = (first * 131 + byte) % 2147483647
        second = (second * 65599 + byte) % 2147483629
    end
    return string.format("%d:%.0f:%.0f", #bytes, first, second)
end
local function Emit(label, region)
    local actual = Digest(Serialize(Snapshot(region)))
    assert(actual == expected[label], label .. ": painter state differs from the frozen legacy output")
    assert(not checked[label], label .. ": repeated case")
    checked[label], cases = true, cases + 1
end
local variants={
 {name="default"},
 {name="reverse",cooldownSwipeReverse=true},
 {name="bar-only",showDurationBar=true,durationBarDisplay="BAR_ONLY"},
 {name="bar-top",showDurationBar=true,durationBarDisplay="OVERLAY",durationBarPosition="TOP",durationBarDirection="ELAPSED"},
 {name="text-hidden",showStacks=false,showTimers=false,showStackCount=false,showCooldownText=false,showSwipe=false,showCooldownSwipe=false},
 {name="shape",iconShape="CIRCLE",iconZoom=150},
 {name="border",debuffBorderMode="BORDER",debuffTypeBorderMode="BORDER",showAuraBorder=true},
 {name="symbol",debuffBorderMode="SYMBOL",debuffTypeBorderMode="SYMBOL",showAuraBorder=true,showAuraSymbol=true},
}
local parent=w.env.CreateFrame("Frame",nil,w.env.UIParent)
parent:SetSize(400,200);parent:Show()
for _,variant in ipairs(variants) do
 local cfg=found.ReadMiniAuraPreviewConfig("player",{previewLane="debuff"})
 for key,value in pairs(variant) do if key~="name" then cfg[key]=value end end
 local mini=found.CreateAuraPreviewIcon(parent)
 found.RenderPreviewIcon(mini,2,cfg,false,true,{})
 Emit("mini/"..variant.name,mini)
 local group=w.env.CreateFrame("Frame",nil,parent)
 local edit=bySurface.edit.EnsureIcon(group,1)
 bySurface.edit.ApplyPreviewIconText(edit,"player",cfg,1)
 bySurface.edit.ApplyPreviewAuraAnimation(group,"debuff",1,cfg,0.73)
 Emit("edit/"..variant.name,edit)
 local lane={size=24,iconZoom=100,initialAnchor="TOPLEFT",perRow=3,xSign=1,ySign=-1,showCooldownSwipe=true,showCooldownText=true,showStacks=true}
 for key,value in pairs(variant) do if key~="name" then lane[key]=value end end
 local visual=bySurface.groupCore.EnsureAuraPreview(parent,"painter",1)
 bySurface.groupCore.ApplyFrameAuraPreview(parent,"party",visual,lane,{textures={135987,136116}},1,1,parent)
 Emit("groupCore/"..variant.name,visual)
 -- The unit consumer now paints native scene regions, including its pooled identities.
 local rootScene = c.GF.NewPreviewScene(parent)
 local scene = rootScene:Unit("player")
 local frame = scene:Frame()
 local host = bySurface.groupCore.EnsureFrameAuraLaneHost(frame, "debuff")
 host:SetSize(200,80);host:Show()
 local function UnitPaint(count)
  for i=1,count do
   local icon=bySurface.groupCore.EnsureAuraPreview(frame,i,"_msufGFFrameAuraPreviews")
   bySurface.groupCore.ApplyFrameAuraPreview(frame,"unit",icon,lane,{key="debuff",textures={135987,136116}},i-1,i,host)
  end
  for i=count+1,#frame._msufGFFrameAuraPreviews do bySurface.groupCore.HideFrameAuraPreview(frame._msufGFFrameAuraPreviews[i]) end
  c.GF.AnimateUnitFrameAuras(frame,nil)
 end
 UnitPaint(2)
 frame:Show()
 Emit("unit/"..variant.name,frame)
 local first=frame._msufGFFrameAuraPreviews[1]
 UnitPaint(1)
 assert(first==frame._msufGFFrameAuraPreviews[1],"unit pool identity")
 Emit("unit-reuse/"..variant.name,frame)
 rootScene:Release()
end
local parent=w.env.CreateFrame("Frame",nil,w.env.UIParent);parent:SetSize(40,30);parent:Show()
for _,anchor in ipairs({"TOPLEFT","TOP","TOPRIGHT","LEFT","CENTER","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT","invalid"}) do
 local fs=parent:CreateFontString(nil,"OVERLAY")
 bySurface.groupMenu.PlaceAuraPreviewText(fs,parent,anchor,0,-2)
 Emit("groupText/"..anchor,fs)
 local mini=found.CreateAuraPreviewIcon(parent)
 bySurface.mini.PlaceAuraPreviewText(mini.timer,mini,anchor,0,-2)
 Emit("miniText/"..anchor,mini)
end
local Painter=assert(w.core.MSUF_Auras3.MockAuraPainter)
for _,reverse in ipairs({false,true}) do
 local icon=found.CreateAuraPreviewIcon(parent)
 Painter.Swipe(icon.swipe,icon,24,18,0.19,reverse)
 Painter.DurationBar(icon.durationBar,icon,{durationBarHeight=2.5,durationBarPosition="TOP",durationBarDirection="ELAPSED"},24,18,{remainingFrac=.19,elapsedFrac=.81})
 Emit("menuPainter/"..tostring(reverse),icon)
end

local variants={
 {name="default"},
 {name="geometry",size=37,heightPercent=65,iconZoom=145,alpha=.63},
 {name="bar-only",showDurationBar=true,durationBarDisplay="BAR_ONLY",durationBarPosition="TOP",durationBarHeight=5},
 {name="elapsed",showDurationBar=true,durationBarDisplay="OVERLAY",durationBarDirection="ELAPSED"},
 {name="solid-shadow",styleBorderEnabled=true,styleBorderThickness=3,styleBorderColor={.2,.4,.6,.8},styleShadowEnabled=true,styleShadowSize=7,styleShadowColor={.8,.3,.1,.4}},
 {name="inner-style",styleBorderEnabled=true,styleBorderStyle="BORDER:BLIZZARD",styleBorderThickness=3,styleShadowEnabled=true},
}
for _,shape in ipairs({"RECTANGLE","CIRCLE","ROUNDED","DIAMOND","HEXAGON","STAR","BLIZZARD"}) do variants[#variants+1]={name="shape-"..shape,iconShape=shape} end
for _,scope in ipairs({"player","party"}) do
 for _,variant in ipairs(variants) do
  local cfg=found.ReadMiniAuraPreviewConfig(scope,"debuff",400,160)
  for key,value in pairs(variant) do if key~="name" then cfg[key]=Copy(value) end end
  local icon=found.CreateAuraPreviewIcon(w.env.UIParent)
  found.RenderPreviewIcon(icon,1,cfg,false,true,{})
  Emit("style/"..scope.."/"..variant.name,icon)
 end
end
-- Re-resolving global font settings may replace general between the paired
-- texts. Both the original renderer and replacement must use that new table.
local cfg=found.ReadMiniAuraPreviewConfig("player","debuff",400,160)
local original=w.env.MSUF_GetGlobalFontSettings
local safe = w.env.MSUF_ResolveSafeFontPath
local fontKeys = {}
w.env.MSUF_ResolveSafeFontPath = function(path, size, flags, key)
    fontKeys[#fontKeys + 1] = key or false
    return safe(path, size, flags, key)
end
local general=w.env.MSUF_DB.general
local calls=0
w.env.MSUF_GetGlobalFontSettings=function(...)
 calls=calls+1
 if calls==2 then
  local replacement=Copy(general);replacement.fontKey="__painter_absent_font";w.env.MSUF_DB.general=replacement
 end
 return original(...)
end
local icon=found.CreateAuraPreviewIcon(w.env.UIParent)
found.RenderPreviewIcon(icon,1,cfg,false,true,{})
assert(calls==2,"paired global font hooks changed")
assert(fontKeys[2] == "__painter_absent_font", "font-context identity switch was ignored")
Emit("style/font-context-switch",icon)
w.env.MSUF_GetGlobalFontSettings=original;w.env.MSUF_DB.general=general
w.env.MSUF_ResolveSafeFontPath = safe

for label in pairs(expected) do assert(checked[label], "missing case " .. label) end
assert(cases == 89, "finite case inventory")
local A3 = c.MSUF_Auras3
local painter = assert(A3.MockAuraPainter)
assert(w.core.MSUF2.PreviewHelpers.PaintPreviewAuraSwipe == nil and w.core.MSUF2.PreviewHelpers.PaintPreviewDurationBar == nil,
    "the menu helpers must not keep a second route to the painters")
assert(A3.LayoutPreviewDurationBar == nil, "the Edit Mode module must not publish a second duration bar route")
-- The preview configuration reader answers the same in and out of combat.
local normal = Serialize(A3.MenuModel.ReadPreviewConfig("player"))
w:EnterCombat()
local combat = Serialize(A3.MenuModel.ReadPreviewConfig("player"))
w:LeaveCombat()
assert(normal == combat, "combat changed the preview model configuration")
assert(A3.MockAuraPainter.ResolveConfig == nil, "the painter must not own configuration reads")
-- A warmed repaint creates no frame or native region; each caller retains
-- its pool, and shrink/re-expand preserves the original icon objects.
local frames = #w.widgets.frames
local cfg = found.ReadMiniAuraPreviewConfig("player", {previewLane="debuff"})
local icon = found.CreateAuraPreviewIcon(parent)
found.RenderPreviewIcon(icon, 2, cfg, false, true, {})
local after = #w.widgets.frames
for i = 1, 8 do found.RenderPreviewIcon(icon, 2, cfg, false, true, {}) end
assert(#w.widgets.frames == after and after > frames, "repaint recreated native objects")
local host=w.env.CreateFrame("Frame",nil,w.env.UIParent)
host:SetSize(200,80);host:Show()
local descriptor={textures={135987,136116}}
local lane={size=24,iconZoom=100,initialAnchor="TOPLEFT",perRow=3,xSign=1,ySign=-1,
 showCooldownSwipe=false,showCooldownText=false,showStacks=false,showDurationBar=false}
local visual=bySurface.groupCore.EnsureAuraPreview(host,1,"_painterPool")
local function Paint()
 return bySurface.groupCore.ApplyFrameAuraPreview(host,"party",visual,lane,descriptor,1,1,host)
end
Paint()
assert(not visual._swipe and not visual._durationBar and not visual._timer and not visual._stack,"disabled regions created eagerly")
lane.showCooldownSwipe,lane.showCooldownText,lane.showStacks,lane.showDurationBar=true,true,true,true
lane.durationBarPosition="TOP";lane.showAuraBorder=true;lane.iconShape="RECTANGLE"
Paint()
local swipe,bar,timer,stack,border=visual._swipe,visual._durationBar,visual._timer,visual._stack,visual._dispelBorder
assert(swipe.drawLayer=="OVERLAY" and swipe.drawSublevel==1,"core swipe layer changed")
assert(swipe.points[2].y==24*.42,"core vertical42percent changed")
assert(bar.drawLayer=="OVERLAY" and bar.drawSublevel==2,"core duration layer changed")
assert(bar.vertexColor[4]==1,"core opaque bar changed")
timer:SetJustifyH("LEFT");timer:SetJustifyV("BOTTOM")
Paint()
assert(timer.justifyH=="LEFT" and timer.justifyV=="BOTTOM","core text justification overwritten")
local frames,regions=#w.widgets.frames,#visual.regions
for i=1,4 do Paint() end
assert(visual==bySurface.groupCore.EnsureAuraPreview(host,1,"_painterPool"),"core pool identity changed")
assert(#w.widgets.frames==frames and #visual.regions==regions and visual._swipe==swipe and visual._durationBar==bar and visual._timer==timer and visual._stack==stack and visual._dispelBorder==border,"core lazy region identity changed")

print("PASS aura mock painter " .. flavor .. ": 89 frozen painter states; real provider, combat fallback and private pools")
