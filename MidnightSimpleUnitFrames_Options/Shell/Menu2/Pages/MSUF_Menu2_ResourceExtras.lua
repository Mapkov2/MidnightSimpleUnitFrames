local _,MSUF=...
local M=MSUF.MSUF2
local W,AP=M.Widgets,M.AdvancedPage
local ResourceExtras={}
M.ResourceExtrasPage=ResourceExtras
local function Meta(path,key,kind)
    return M.ControlMeta("classpower","advanced","resource_extras."..path,kind or "setting",
        M.ClassPowerWorkspace.Decorate(key and {settingKey="bars."..key} or {searchSettingKeys={"bars.resourceMarks"}},
            "resource_extras."..path))
end
-- Client gates for the extras: the native duration bars (Ignore Pain, the Arcane
-- Surge window) and their size sliders run on Midnight only (MSUF_CP_ExtraAuras.lua);
-- the regeneration pause and return pulse where the runtime draws them, Classic Era,
-- TBC and WoW Forever with the native duration API (MSUF_CP_ManaExtras.lua).
local CLIENT=MSUF.Client or {}
local EXTRA_AURAS=CLIENT.IsRetail==true and not CLIENT.IsForever
local function ExtraAuras() return EXTRA_AURAS end
local function RegenTimers()
    local supported=MSUF.CPBuilders and MSUF.CPBuilders.ManaRegenTimersSupported
    return type(supported)=="function" and supported()==true
end
-- Mark power types the client can have. Class resources and the Midnight-only powers
-- follow MSUF.Client.SupportsClassResource (Runic Power: Runes; Astral Power: ASTRAL_POWER).
local POWER_TYPES={{"MANA","Mana"},{"ENERGY","Energy"},{"RAGE","Rage"},{"FOCUS","Focus"},
    {"RUNIC_POWER","Runic Power","RUNES"},{"COMBO_POINTS","Combo Points","COMBO_POINTS"},
    {"HOLY_POWER","Holy Power","HOLY_POWER"},{"CHI","Chi","CHI"},{"SOUL_SHARDS","Soul Shards","SOUL_SHARDS"},
    {"ARCANE_CHARGES","Arcane Charges","ARCANE_CHARGES"},{"ESSENCE","Essence","ESSENCE"},
    {"INSANITY","Insanity","INSANITY"},{"MAELSTROM","Maelstrom","MAELSTROM"},{"LUNAR_POWER","Astral Power","ASTRAL_POWER"}}
local function PowerTypeValues()
    local out,supports={{value="ALL",text="Any power type"}},CLIENT.SupportsClassResource
    for _,item in ipairs(POWER_TYPES) do
        if not item[3] or type(supports)~="function" or supports(item[3]) then out[#out+1]={value=item[1],text=item[2]} end
    end
    return out
end
-- Resource extras only some clients have, each list with the gate of the runtime
-- that draws it. The page builds the lists the running client wants and search
-- drops the static rows of the others (R.ClientOnlySettings in
-- StaticRowsWithoutClientSupport), so no other file repeats this client split.
local CLIENT_EXTRAS={
    {wanted=ExtraAuras,specs=function() return {
        {"showIgnorePain","toggle","Ignore Pain duration","showIgnorePain",false},
        {"ignorePainTimeMarker","toggle","Ignore Pain time marker","ignorePainTimeMarker",true},
        {"showArcaneWindow","toggle","Arcane Surge window timer","showArcaneWindow",false},
        {"arcaneWindowText","dropdown","Arcane window text",{{value="seconds",text="Seconds left"},
            {value="gcds",text="Global cooldowns you can still start"},{value="both",text="Seconds and global cooldowns"}},
            280,"arcaneWindowText","seconds"},
        {"arcaneWindowTextFrom","slider","Show the time from (seconds left, 0 = always)",0,15,1,280,"arcaneWindowTextFrom",0},
        {"arcaneWindowWarnSeconds","slider","Arcane window warning (seconds)",0,10,1,280,"arcaneWindowWarnSeconds",3},
        {"arcaneWindowWarnLastGCD","toggle","Warn during the last global cooldown","arcaneWindowWarnLastGCD",false},
    } end},
    {wanted=RegenTimers,specs=function() return {
        {"manaRegenPause","toggle","Regeneration pause after spending","manaRegenPause",false},
        {"manaGainPulse","toggle","Mana return pulse","manaGainPulse",false},
    } end},
}
-- Setting keys of every client-only extra, and those this client builds.
function ResourceExtras.ClientOnlySettings()
    local all,built={},{}
    for _,group in ipairs(CLIENT_EXTRAS) do
        local wanted=group.wanted()
        for _,spec in ipairs(group.specs()) do
            all["bars."..spec[1]]=true
            if wanted then built["bars."..spec[1]]=true end
        end
    end
    return all,built
end
function ResourceExtras.Specs()
    local specs={
        {"manaUpcomingCost","toggle","Mana spend preview","manaUpcomingCost",false},
        {"resourceExtraWidth","slider","Resource bar width",40,1000,1,280,"resourceExtraWidth",220},
        {"resourceExtraHeight","slider","Resource bar height",2,30,1,280,"resourceExtraHeight",8},
        {"resourceExtraOffsetX","slider","Resource bar X offset",-1000,1000,1,280,"resourceExtraOffsetX",0},
        {"resourceExtraOffsetY","slider","Resource bar Y offset",-1000,1000,1,280,"resourceExtraOffsetY",-18},
    }
    local own={}
    for _,group in ipairs(CLIENT_EXTRAS) do
        if group.wanted() then
            for _,spec in ipairs(group.specs()) do own[#own+1]=spec end
        end
    end
    for i,spec in ipairs(own) do
        table.insert(specs,i,spec)
    end
    if not EXTRA_AURAS then
        for i=#specs,1,-1 do if specs[i][1]:find("^resourceExtra") then table.remove(specs,i) end end
    end
    return specs
end
function ResourceExtras.Height() return 120+#ResourceExtras.Specs()*54 end
function ResourceExtras.Build(page,Bars,Apply)
    local specs=ResourceExtras.Specs()
    local section=page.b:CollapsibleSection("classpower_resource_extras","Additional resources",120+#specs*54,false)
    for _,spec in ipairs(specs) do spec.meta=Meta(spec[1],spec[1]) end
    local controls=page:Controls(section,Bars,Apply,"resource_extras",specs)
    for i,spec in ipairs(specs) do W.MoveWidget(controls[spec[1]],section,24,-40-(i-1)*54,280) end
end
function ResourceExtras.BuildMarks(page,Bars,Apply)
    local ctx=page.ctx
    local section=page.b:CollapsibleSection("classpower_resource_marks","Resource marks and thresholds",690,false)
    local selected=1
    local empty={}
    local function Rules() return Bars().resourceMarks or empty end
    local function Rule() return Rules()[selected] end
    local function Refresh() if M.RequestRefresh then M.RequestRefresh(ctx,"resource-marks") end end
    local function Write(key,value)
        local rule=Rule()
        if rule then
            rule[key]=value
            Apply()
        end
    end
    local function Values()
        local out={}
        for i=1,#Rules() do out[i]={value=i,text=tostring(i)} end
        if #out==0 then out[1]={value=1,text="No resource marks"} end
        return out
    end
    local selector=W.Dropdown(section,"Resource mark",Values,280)
    W.MoveWidget(selector,section,24,-40,280)
    M.ClassPowerWorkspace.BindDropdownWidget(ctx,selector,function() return selected end,function(value) selected=value;Refresh() end,
            Meta("marks.select",nil,"ephemeral"))
    local function Button(label,x,path,callback)
        local button=M.Theme.Button(section,label,130,26,{history=true})
        button:SetPoint("TOPLEFT",section,"TOPLEFT",x,-98)
        button:SetScript("OnClick",callback)
        AP.RegisterControl(button,Meta(path,nil,"action"),label,"button")
    end
    Button("Add resource mark",24,"marks.add",function()
        local b=Bars()
        if not b.resourceMarks then
            b.resourceMarks={}
        end
        local rules=b.resourceMarks
        rules[#rules+1]={target="PLAYER",resource="ALL",mode="PERCENT",value=50,width=2,color={1,1,1},mark=true}
        selected=#rules
        Apply()
        Refresh()
    end)
    Button("Remove resource mark",164,"marks.remove",function()
        if Rule() then
            table.remove(Rules(),selected)
            selected=math.max(1,math.min(selected,#Rules()))
            Apply()
            Refresh()
        end
    end)
    local y=-154
    local function Drop(key,label,values,default)
        local widget=W.Dropdown(section,label,values,280)
        W.MoveWidget(widget,section,24,y,280)
        y=y-54
        M.ClassPowerWorkspace.BindDropdownWidget(ctx,widget,function() local rule=Rule();return rule and rule[key] or default end,
            function(value) Write(key,value) end,Meta("marks."..key))
    end
    Drop("target","Resource bar",{{value="PLAYER",text="Player power"},{value="CLASS",text="Class resource"},
        {value="ALTMANA",text="Alternative mana"}},"PLAYER")
    Drop("resource","Power type",PowerTypeValues(),"ALL")
    Drop("mode","Value mode",{{value="PERCENT",text="Percent"},{value="ABSOLUTE",text="Absolute value"}},"PERCENT")
    for _,spec in ipairs({{"value","Resource value",0,10000000,1,50},{"width","Mark width",1,20,1,2}}) do
        local key=spec[1]
        local widget=W.Slider(section,spec[2],spec[3],spec[4],spec[5],280)
        W.MoveWidget(widget,section,24,y,280)
        y=y-54
        M.ClassPowerWorkspace.BindNumberWidget(ctx,widget,function() local rule=Rule();return rule and rule[key] or spec[6] end,
            function(value) Write(key,value) end,spec[6],Meta("marks."..key))
    end
    for _,spec in ipairs({{"mark","Show resource mark",true},{"threshold","Change color at threshold",false}}) do
        local key=spec[1]
        local widget=W.Toggle(section,spec[2])
        W.MoveWidget(widget,section,24,y,280)
        y=y-38
        M.ClassPowerWorkspace.BindBoolWidget(ctx,widget,function()
            local rule=Rule()
            return rule and rule[key]~=false and (key=="mark" or rule[key]==true) or false
        end,
            function(value) Write(key,value) end,Meta("marks."..key))
    end
    Drop("direction","Threshold direction",{{value="ABOVE",text="At or above"},{value="BELOW",text="Below"}},"ABOVE")
    local color=W.Color(section,"Mark and threshold color")
    W.MoveWidget(color,section,24,y,280)
    M.ClassPowerWorkspace.BindColor(ctx,color,function() local rule=Rule();local c=rule and rule.color or {1,1,1};return c[1],c[2],c[3] end,
        function(r,g,b) Write("color",{r,g,b}) end,Meta("marks.color"))
end
function ResourceExtras.BuildColors(ctx,b,Bars,ColorValueAt,Apply)
    local regen=RegenTimers()
    local specs={{"ignorePainColor","Ignore Pain",.45,.7,1,EXTRA_AURAS},{"arcaneWindowColor","Arcane window bar",.66,.42,1,EXTRA_AURAS},
        {"arcaneWindowSoulColor","Arcane Soul phase bar",.92,.4,.86,EXTRA_AURAS},
        {"arcaneWindowWarnColor","Arcane window warning text",1,.78,.25,EXTRA_AURAS},
        {"manaRegenPauseColor","Regeneration pause after spending",1,.65,.2,regen},{"manaGainPulseColor","Mana return pulse",.3,1,.7,regen},
        {"manaCostColor","Mana spend preview",.7,.7,1,true}}
    for i=#specs,1,-1 do if not specs[i][6] then table.remove(specs,i) end end
    local section=b:CollapsibleSection("colors_resource_extras","Additional resource colors",64+#specs*38,false)
    for i,spec in ipairs(specs) do
        local key=spec[1]
        ColorValueAt(ctx,section,spec[2],24,-40-(i-1)*38,
            function() local c=Bars()[key];if c then return c[1],c[2],c[3] end;return spec[3],spec[4],spec[5] end,
            function(r,g,blue) Bars()[key]={r,g,blue};Apply() end,200,44,
            M.ControlMeta("colors","advanced","resource_extras."..key,"setting",{settingKey="bars."..key}))
    end
end
