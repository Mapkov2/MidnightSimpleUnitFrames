local root,flavor=assert(arg[1]),arg[2] or "Forever"
local w=assert(loadfile(root.."/tools/tests/client_world.lua"))().New(root,flavor):Boot()
local failure=w:FirstFailure(); assert(not failure,failure and failure.message)
local e,n=w.env,w.core
local M=n.MSUF2
local methods=w.widgets.Methods
local function Store(key) return function(self,v) self[key]=v end end
local function Get(key) return function(self) return self[key] end end
for name,fn in pairs({SetChecked=Store("checked"),GetChecked=Get("checked"),SetValueStep=Store("step"),
    SetAutoFocus=function() end,SetNumeric=function() end,SetMaxLetters=function() end,SetTextInsets=function() end,
    ClearFocus=function() end,HasFocus=function() return false end,SetCursorPosition=function() end,HighlightText=function() end,
    SetScrollChild=Store("scrollChild"),GetScrollChild=Get("scrollChild"),SetVerticalScroll=Store("verticalScroll"),
    GetVerticalScroll=function(self) return self.verticalScroll or 0 end,GetVerticalScrollRange=function() return 0 end}) do methods[name]=fn end
e.MSUF_EnsureDB(true)
e.MSUF_ActiveProfile="Default"
e.MSUF_GlobalDB={profiles={Default=e.MSUF_DB,Other={general={},player={width=222}}},char={},global={}}
local V,S=n.ProfileVariants,n.ProfileSync
n.ProfileRuntime.Apply=function() V.ResolveCurrent() end
assert(V.Replace(e.MSUF_DB,{version=1,entries={{name="Dungeon",patch={}}}}))
assert(S.Replace({{name="Shared",members={Default=true,Other=true},modules={unitframes=true}}}))
local W=M.Widgets
local inputs,buttons,bindings={},{},{}
local text=W.TextInput
W.TextInput=function(parent,label,...)
    local widget=text(parent,label,...); inputs[label]=widget; return widget
end
local button=M.Theme.Button
M.Theme.Button=function(parent,label,...)
    local widget=button(parent,label,...); buttons[label]=widget; return widget
end
local dropdown=W.Dropdown
W.Dropdown=function(parent,label,...)
    local widget=dropdown(parent,label,...); widget.testLabel=label; return widget
end
for _,kind in ipairs({"BindDropdownWidget","BindBoolWidget"}) do
    local original=M[kind]
    M[kind]=function(ctx,widget,get,set,meta)
        if widget.testLabel then bindings[widget.testLabel]={get=get,set=set,widget=widget} end
        return original(ctx,widget,get,set,meta)
    end
end
M.scrollChild=e.CreateFrame("Frame")
M.GetContentMetrics=function() return 900,800 end
M.BuildPageEntry("profiles",true)
local function Click(label) local b=assert(buttons[label],label.." missing"); return assert(b:GetScript("OnClick"))(b) end
assert(inputs["New variant name"] and inputs["Find a setting to exclude"] and buttons["Copy shared modules now"])
assert(bindings.Where,"context selector missing")
bindings.Where.set("party")
Click("Save conditions")
assert(V.Find(e.MSUF_DB,"Dungeon").conditions.context=="party","condition saved through real menu")
Click("Edit variant values")
assert(V.IsRecording() and buttons["Cancel variant editing"],"recording opens persistent editor bar")
e.MSUF_DB.player.width=321
Click("Save variant values")
assert(not V.IsRecording() and #V.Find(e.MSUF_DB,"Dungeon").patch>0,"normal page settings recorded")
local source=assert(io.open(root.."/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_ProfileSync.lua","rb")):read("*a")
assert(not source:find("OnUpdate",1,true),"field search must not poll")
print("profile_variants_menu_smoke: OK ("..flavor..")")
