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

-- Surge window) and their size sliders run on Midnight only (MSUF_CP_ExtraAuras.lua).
-- Regeneration pause and return pulse run where the runtime draws them: Classic Era,
-- TBC and WoW Forever with the native duration API (MSUF_CP_ManaExtras.lua).
local CLIENT=MSUF.Client or {}
local EXTRA_AURAS=CLIENT.IsRetail==true and not CLIENT.IsForever
local function ExtraAuras() return EXTRA_AURAS end
local function RegenTimers()
    local supported=MSUF.CPBuilders and MSUF.CPBuilders.ManaRegenTimersSupported
    return type(supported)=="function" and supported()==true
end
-- Mark power types the client can have. Class resources and the Midnight-only powers
-- follow MSUF.Client.SupportsClassResource (Runic Power: Runes
-- Astral Power: ASTRAL_POWER).
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
    } end,colors={"ignorePainColor","arcaneWindowColor","arcaneWindowSoulColor","arcaneWindowWarnColor"}},
    {wanted=RegenTimers,specs=function() return {
        {"manaRegenPause","toggle","Regeneration pause after spending","manaRegenPause",false},
        {"manaGainPulse","toggle","Mana return pulse","manaGainPulse",false},
    } end,colors={"manaRegenPauseColor","manaGainPulseColor"}},
    {wanted=ExtraAuras,specs=function() return {
        {"resourceExtraWidth","slider","Resource bar width",40,1000,1,280,"resourceExtraWidth",220},
        {"resourceExtraHeight","slider","Resource bar height",2,30,1,280,"resourceExtraHeight",8},
        {"resourceExtraOffsetX","slider","Resource bar X offset",-1000,1000,1,280,"resourceExtraOffsetX",0},
        {"resourceExtraOffsetY","slider","Resource bar Y offset",-1000,1000,1,280,"resourceExtraOffsetY",-18},
    } end,colors={}},
}
-- Setting keys of every client-only extra and of its color (Colors page,
-- BuildColors), and those this client builds.
function ResourceExtras.ClientOnlySettings()
    local all,built={},{}
    for _,group in ipairs(CLIENT_EXTRAS) do
        local wanted=group.wanted()
        for _,spec in ipairs(group.specs()) do
            all["bars."..spec[1]]=true
            if wanted then built["bars."..spec[1]]=true end
        end
        for _,key in ipairs(group.colors) do
            all["bars."..key]=true
            if wanted then built["bars."..key]=true end
        end
    end
    return all,built
end
function ResourceExtras.Specs()
    local specs={
        {"manaUpcomingCost","toggle","Mana spend preview","manaUpcomingCost",false},
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
    return specs
end
local GROUPS = {
    { key="pain", id="classpower_resource_pain", title="Ignore Pain", wanted=ExtraAuras,
        master="showIgnorePain", keys={"showIgnorePain","ignorePainTimeMarker"} },
    { key="arcane", id="classpower_resource_arcane", title="Arcane Window", wanted=ExtraAuras, master="showArcaneWindow",
        keys={"showArcaneWindow","arcaneWindowText","arcaneWindowTextFrom","arcaneWindowWarnSeconds","arcaneWindowWarnLastGCD"} },
    { key="mana", id="classpower_resource_extras", title="Mana", keys={"manaUpcomingCost","manaRegenPause","manaGainPulse"} },
    { key="layout", id="classpower_resource_layout", title="Size and position", wanted=ExtraAuras,
        keys={"resourceExtraWidth","resourceExtraHeight","resourceExtraOffsetX","resourceExtraOffsetY"} },
}
local COLOR_SPECS = {
    {"ignorePainColor","Ignore Pain",.45,.7,1,"pain",ExtraAuras},
    {"arcaneWindowColor","Arcane window bar",.66,.42,1,"arcane",ExtraAuras},
    {"arcaneWindowSoulColor","Arcane Soul phase bar",.92,.4,.86,"arcane",ExtraAuras},
    {"arcaneWindowWarnColor","Arcane window warning text",1,.78,.25,"arcane",ExtraAuras},
    {"manaRegenPauseColor","Regeneration pause after spending",1,.65,.2,"mana",RegenTimers},
    {"manaGainPulseColor","Mana return pulse",.3,1,.7,"mana",RegenTimers},
    {"manaCostColor","Mana spend preview",.7,.7,1,"mana"},
}
local function ColorSpecs(group)
    local specs={}
    for _,spec in ipairs(COLOR_SPECS) do
        if (not group or spec[6]==group) and (not spec[7] or spec[7]()) then specs[#specs+1]=spec end
    end
    return specs
end
-- Cold metadata shared by lazy-page resets and the Colors page. Reading these
-- keys must never materialize controls or allocate preview frames.
function ResourceExtras.ColorKeys()
    local keys={}
    for _,spec in ipairs(ColorSpecs()) do keys[spec[1]]=true end
    return keys
end
function ResourceExtras.SettingKeys()
    local keys={ ["bars.resourceMarks"]=true }
    for _,spec in ipairs(ResourceExtras.Specs()) do keys["bars."..spec[1]]=true end
    for key in pairs(ResourceExtras.ColorKeys()) do keys["bars."..key]=true end
    return keys
end

local function ColorRGB(Bars,spec)
    local color=Bars()[spec[1]]
    if color then return color[1],color[2],color[3] end
    return spec[3],spec[4],spec[5]
end
function ResourceExtras.ColorTargets(Bars,Apply,group)
    local targets={}
    for _,spec in ipairs(ColorSpecs(group)) do
        local key=spec[1]
        targets[#targets+1]={label=spec[2], getRGB=function() return ColorRGB(Bars,spec) end,
            setRGB=function(r,g,b)
                Bars()[key]={r,g,b}
                Apply()
            end,
            captureState=function() return {color=AP.DeepCopyTable(Bars()[key])} end,
            restoreState=function(state)
                Bars()[key]=AP.DeepCopyTable(state.color)
                Apply()
            end}
    end
    return targets
end
local function GroupSpecs(group)
    local byKey,specs={},{}
    for _,spec in ipairs(ResourceExtras.Specs()) do byKey[spec[1]]=spec end
    for _,key in ipairs(group.keys) do if byKey[key] and key~=group.master then specs[#specs+1]=byKey[key] end end
    return specs,byKey[group.master]
end
local function Geometry(page,count)
    local cardW=math.min(650,page.width-28)
    local columns=page.width>=680 and 2 or 1
    local controlW=math.min(360,math.floor((cardW-36-(columns-1)*20)/columns))
    local rows=math.ceil(count/columns)
    return cardW,controlW,columns,126+rows*58
end
local function FocusExample(page,group)
    local effect=group.key=="mana" and "cost" or group.key
    if effect=="layout" then return end
    M.ResourceExtrasPreview.Select(effect)
    M.ResourceExtrasPreview.UpdateHeader(page.ctx,page.workspace.selected)
    M.RequestRefresh(page.ctx,"resource-extra-section")
end
local function ReserveColorAction(entry,shortcut)
    if not shortcut then return end
    shortcut:ClearAllPoints()
    shortcut:SetPoint("RIGHT",entry.header,"RIGHT",-10,0)
    M.ReserveSectionActions(entry,shortcut,44)
    entry._msuf2RefreshLayout()
    if entry.featureSwitch and not entry._msuf2UXSummary then
        entry.featureSwitch:ClearAllPoints()
        entry.featureSwitch:SetPoint("RIGHT",entry.header,"RIGHT",-14-(entry._msuf2ColorSwatchReserve or 0),0)
    end
end
local function Header(page,section,group,Bars,Apply)
    if section._msuf2ResourceExtraHeader then return end
    section._msuf2ResourceExtraHeader=true
    local _,master=GroupSpecs(group)
    if master then
        local toggle=W.SectionSwitch(section,master[3])
        M.ClassPowerWorkspace.BindBoolWidget(page.ctx,toggle,function() return Bars()[group.master]==true end,
            function(value)
                Bars()[group.master]=value and true or false
                FocusExample(page,group)
                Apply()
            end,Meta(group.master,group.master))
    end
    local entry=section._msuf2CollapsibleEntry
    if entry and group.key~="layout" then
        local shortcut=W.AttachContextColorShortcut(entry.header,{title=group.title,
            getTargets=function() return ResourceExtras.ColorTargets(Bars,Apply,group.key) end,
            historySource="menu:resource-extras-"..group.key})
        ReserveColorAction(entry,shortcut)
    end
    if entry then entry.header:HookScript("OnClick",function() if entry.open then FocusExample(page,group) end end) end
end
local function BuildGroup(page,group,Bars,Apply)
    local specs=GroupSpecs(group)
    local cardW,controlW,columns,height=Geometry(page,#specs)
    local section=page.b:CollapsibleSection(group.id,group.title,height,false)
    Header(page,section,group,Bars,Apply)
    W.ControlCard(section,group.key=="layout" and "Size and position" or "Settings",nil,14,-38,cardW,height-58)
    local applyIndex = { toggle = 6, slider = 10, dropdown = 8 }
    for _,spec in ipairs(specs) do
        local key = spec[1]
        spec.meta=Meta(key,key)
        spec[applyIndex[spec[2]]] = function()
            M.ResourceExtrasPreview.FocusKey(key)
            M.ResourceExtrasPreview.UpdateHeader(page.ctx, page.workspace.selected)
            Apply()
            M.RequestRefresh(page.ctx, "resource-extra-setting")
        end
    end
    local controls=page:Controls(section,Bars,Apply,"resource_extras",specs)
    for i,spec in ipairs(specs) do
        local column=(i-1)%columns
        local width=spec[2]=="toggle" and controlW-36 or controlW
        W.MoveWidget(controls[spec[1]],section,32+column*(controlW+20),-92-math.floor((i-1)/columns)*58,width,"LEFT")
    end
end
function ResourceExtras.BuildSections(page,Bars,Apply)
    for _,group in ipairs(GROUPS) do
        if not group.wanted or group.wanted() then
            local count=#GroupSpecs(group)
            page:LazySection(group.id,group.title,function() return select(4,Geometry(page,count)) end,
                function() BuildGroup(page,group,Bars,Apply) end,
                function(_,section) Header(page,section,group,Bars,Apply) end)
        end
    end
end
local selectedMark=1
local EMPTY_MARKS={}
function ResourceExtras.MarkRules(Bars) return Bars().resourceMarks or EMPTY_MARKS end
local function MarkIndex(Bars)
    selectedMark=math.max(1,math.min(selectedMark,#ResourceExtras.MarkRules(Bars)))
    return selectedMark
end
function ResourceExtras.MarkRule(Bars) return ResourceExtras.MarkRules(Bars)[MarkIndex(Bars)] end
local function MarkValues(Bars)
    local values={}
    for i=1,#ResourceExtras.MarkRules(Bars) do values[i]={value=i,text=tostring(i)} end
    if #values==0 then values[1]={value=1,text="No resource marks"} end
    return values
end
local function MarkColorTarget(Bars,Apply)
    local rule=ResourceExtras.MarkRule(Bars)
    if not rule then return {} end
    return {{label="Mark and threshold color",getRGB=function()
            local color=rule.color or {1,1,1}
            return unpack(color)
        end,
        setRGB=function(r,g,b)
            rule.color={r,g,b}
            Apply()
        end,
        captureState=function() return {color=AP.DeepCopyTable(rule.color)} end,
        restoreState=function(state)
            rule.color=AP.DeepCopyTable(state.color)
            Apply()
        end}}
end

-- Percent marks span 0-100; absolute marks retain the wide raw-power range.
local function ValueMax(rule) return rule and rule.mode=="ABSOLUTE" and 10000000 or 100 end
-- A readable player power maximum, or 0 while it is restricted or unavailable.
local function PowerMax(power)
    if type(power)=="string" then power=Enum.PowerType[(power:lower():gsub("^%l",string.upper):gsub("_(%l)",string.upper))] end
    local maximum=type(power)=="number" and UnitPowerMax("player",power)
    if (issecretvalue and issecretvalue(maximum)) or type(maximum)~="number" then return 0 end
    return maximum
end
-- The value slider's range. The runtime places an absolute mark at value /
-- UnitPowerMax of the power it sits on and shows it only up to that maximum,
-- so the slider spans this character's maximum of that power: the named one,
-- else what the chosen bar shows (the Player bar's power, mana, the class
-- resource the runtime resolves). 0-100 when it cannot be read. A saved
-- value above the maximum widens the range and is never cut.
local function SliderMax(rule)
    if not (rule and rule.mode=="ABSOLUTE") then return 100 end
    local maximum=0
    if rule.resource and rule.resource~="ALL" then
        maximum=PowerMax(rule.resource)
    elseif rule.target=="ALTMANA" then
        maximum=PowerMax("MANA")
    elseif rule.target=="CLASS" then
        -- The class resource bar's own resolver (MSUF_CP_Controller.lua):
        -- a Death Knight's bar shows runes, not Runic Power. Marks never sit
        -- on an aura-driven resource (MSUF_CP_ResourceMarks Target).
        local resolve=MSUF.CPBuilders and MSUF.CPBuilders.ClassPowerType
        if resolve then
            local power,_,aura=resolve()
            if not aura and type(power)=="number" then maximum=PowerMax(power) end
        end
    else
        -- What the Player bar shows (MSUF_CP_ResourceMarks DisplayedPower).
        local helpers,power=M.PreviewHelpers,UnitPowerType("player")
        if helpers and helpers.PlayerManaSourceActive and helpers.PlayerManaSourceActive(M.EnsureDB().player) then
            power="MANA"
        elseif issecretvalue and issecretvalue(power) then
            power=nil
        end
        maximum=PowerMax(power)
    end
    if maximum<=0 then maximum=100 end
    local stored=tonumber(rule.value)
    return stored and stored>maximum and math.min(ValueMax(rule),stored) or maximum
end
function ResourceExtras.BuildMarks(page,Bars,Apply)
    local ctx=page.ctx
    local applyRuntime = Apply
    Apply = function()
        M.ResourceExtrasPreview.Select("marks")
        M.ResourceExtrasPreview.UpdateHeader(ctx, page.workspace.selected)
        applyRuntime()
    end
    local height=ResourceExtras.MarksHeight(page)
    local section=page.b:CollapsibleSection("classpower_resource_marks","Resource marks and thresholds",height,false)
    local cardW,controlW,columns=Geometry(page,8)
    W.ControlCard(section,"Resource mark",nil,14,-38,cardW,154)
    W.ControlCard(section,"Settings",nil,14,-212,cardW,height-232)
    local function Rules() return ResourceExtras.MarkRules(Bars) end
    local function Rule() return ResourceExtras.MarkRule(Bars) end
    local entry=section._msuf2CollapsibleEntry
    if entry then
        local shortcut=W.AttachContextColorShortcut(entry.header,{title="Mark and threshold color",
            getTargets=function() return MarkColorTarget(Bars,Apply) end,isRelevant=function() return Rule()~=nil end,
            historySource="menu:resource-mark-color"})
        ReserveColorAction(entry,shortcut)
    end
    local function Refresh()
        M.ResourceExtrasPreview.Select("marks")
        M.ResourceExtrasPreview.UpdateHeader(ctx, page.workspace.selected)
        if M.RequestRefresh then M.RequestRefresh(ctx,"resource-marks") end
    end
    local function Write(key,value)
        local rule=Rule()
        if rule then
            rule[key]=value
            local stored=tonumber(rule.value)
            if stored and (key=="value" or key=="mode") then rule.value=math.max(0,math.min(ValueMax(rule),stored)) end
            Apply()

-- A new mode, bar or power changes the value range; a new mode may
            -- also have clamped the value.
            if key=="mode" or key=="target" or key=="resource" then Refresh() end
        end
    end
    local selector=W.Dropdown(section,"Resource mark",function() return MarkValues(Bars) end,280)
    W.MoveWidget(selector,section,32,-92,controlW,"LEFT")
    M.ClassPowerWorkspace.BindDropdownWidget(ctx,selector,function() return MarkIndex(Bars) end,function(value)
        selectedMark=value
        Refresh()
    end,
            Meta("marks.select",nil,"ephemeral"))
    local function Button(label,x,path,callback)
        local button=M.Theme.Button(section,label,130,26,{history=true})
        button:SetPoint("TOPLEFT",section,"TOPLEFT",x,-146)
        button:SetScript("OnClick",callback)
        AP.RegisterControl(button,Meta(path,nil,"action"),label,"button")
    end
    Button("Add resource mark",32,"marks.add",function()
        local b=Bars()
        if not b.resourceMarks then
            b.resourceMarks={}
        end
        local rules=b.resourceMarks
        rules[#rules+1]={target="PLAYER",resource="ALL",mode="PERCENT",value=50,width=2,color={1,1,1},mark=true}
        selectedMark=#rules
        Apply()
        Refresh()
    end)
    Button("Remove resource mark",172,"marks.remove",function()
        if Rule() then
            table.remove(Rules(),selectedMark)
            selectedMark=math.max(1,math.min(selectedMark,#Rules()))
            Apply()
            Refresh()
        end
    end)
    local fieldIndex=0
    local function Position(widget)
        fieldIndex=fieldIndex+1
        local column=columns==2 and fieldIndex>5 and 1 or 0
        local row=column==1 and fieldIndex-6 or fieldIndex-1
        local width=widget._msuf2ControlKind=="toggle" and controlW-36 or controlW
        W.MoveWidget(widget,section,32+column*(controlW+20),-268-row*58,width,"LEFT")
    end
    local function Drop(key,label,values,default)
        local widget=W.Dropdown(section,label,values,280)
        Position(widget)
        M.ClassPowerWorkspace.BindDropdownWidget(ctx,widget,function() local rule=Rule()
            return rule and rule[key] or default end,
            function(value) Write(key,value) end,Meta("marks."..key))
    end
    Drop("target","Resource bar",{{value="PLAYER",text="Player power"},{value="CLASS",text="Class resource"},
        {value="ALTMANA",text="Alternative mana"}},"PLAYER")
    Drop("resource","Power type",PowerTypeValues(),"ALL")
    Drop("mode","Value mode",{{value="PERCENT",text="Percent"},{value="ABSOLUTE",text="Absolute value"}},"PERCENT")
    for _,spec in ipairs({{"value","Resource value",0,10000000,1,50},{"width","Mark width",1,20,1,2}}) do
        local key=spec[1]
        local widget=W.Slider(section,spec[2],spec[3],spec[4],spec[5],280)
        Position(widget)
        if key=="value" then
            -- Registered before the value binding, so the range is set before the value.
            M.TrackRefresh(ctx,function()
                widget._msuf2Refreshing=true
                widget:SetMinMaxValues(0,SliderMax(Rule()))
                widget._msuf2Refreshing=nil
            end)
        end
        M.ClassPowerWorkspace.BindNumberWidget(ctx,widget,function() local rule=Rule()
            return rule and rule[key] or spec[6] end,
            function(value) Write(key,value) end,spec[6],Meta("marks."..key))
    end
    for _,spec in ipairs({{"mark","Show resource mark",true},{"threshold","Change color at threshold",false}}) do
        local key=spec[1]
        local widget=W.Toggle(section,spec[2])
        Position(widget)
        M.ClassPowerWorkspace.BindBoolWidget(ctx,widget,function()
            local rule=Rule()
            return rule and rule[key]~=false and (key=="mark" or rule[key]==true) or false
        end,
            function(value) Write(key,value) end,Meta("marks."..key))
    end
    Drop("direction","Threshold direction",{{value="ABOVE",text="At or above"},{value="BELOW",text="Below"}},"ABOVE")
end
function ResourceExtras.MarksHeight(page) return page.width>=680 and 612 or 786 end
local function BuildMarkColors(ctx,b,Bars,ColorValueAt,Apply)
    local section=b:CollapsibleSection("colors_resource_marks","Resource marks and thresholds",154,false)
    local selector=W.Dropdown(section,"Resource mark",function() return MarkValues(Bars) end,260)
    W.MoveWidget(selector,section,24,-42,260,"LEFT")
    local function ColorMeta(path,kind)
        return M.ControlMeta("colors","advanced","resource_extras.marks."..path,kind or "setting",{searchSettingKeys={"bars.resourceMarks"}})
    end
    M.ClassPowerWorkspace.BindDropdownWidget(ctx,selector,function() return MarkIndex(Bars) end,function(value)
        selectedMark=value
        M.RequestRefresh(ctx,"resource-mark-color-selection")
    end,ColorMeta("select","ephemeral"))
    local color=ColorValueAt(ctx,section,"Mark and threshold color",24,-100,
        function()
            local rule=ResourceExtras.MarkRule(Bars)
            local c=rule and rule.color or {1,1,1}
            return unpack(c)
        end,
        function(r,g,blue)
            local rule=ResourceExtras.MarkRule(Bars)
            if rule then
                rule.color={r,g,blue}
                Apply()
            end
        end,
        200,44,ColorMeta("color"))
    M.TrackRefresh(ctx,function() AP.SetControlEnabled(color,ResourceExtras.MarkRule(Bars)~=nil) end)
end
function ResourceExtras.BuildColors(ctx,b,Bars,ColorValueAt,Apply)
    local specs=ColorSpecs()
    local section=b:CollapsibleSection("colors_resource_extras","Additional resource colors",64+#specs*38,false)
    for i,spec in ipairs(specs) do
        local key=spec[1]
        ColorValueAt(ctx,section,spec[2],24,-40-(i-1)*38,
            function() return ColorRGB(Bars,spec) end,
            function(r,g,blue)
                Bars()[key]={r,g,blue}
                Apply()
            end,200,44,
            M.ControlMeta("colors","advanced","resource_extras."..key,"setting",{settingKey="bars."..key}))
    end
    BuildMarkColors(ctx,b,Bars,ColorValueAt,Apply)
end
