local _,MSUF=...
local M=MSUF.MSUF2
local W,AP=M.Widgets,M.AdvancedPage
local Schema=M.ControlSchema
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
local CLIENT=MSUF.Client
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
        {key="showIgnorePain",kind="toggle",labelKey="Ignore Pain duration"},
        {key="ignorePainTimeMarker",kind="toggle",labelKey="Ignore Pain time marker"},
        {key="showArcaneWindow",kind="toggle",labelKey="Arcane Surge window timer"},
        {key="arcaneWindowText",kind="dropdown",labelKey="Arcane window text",values={{value="seconds",text="Seconds left"},
            {value="gcds",text="Global cooldowns you can still start"},{value="both",text="Seconds and global cooldowns"}},
            },
        {key="arcaneWindowTextFrom",kind="slider",labelKey="Show the time from (seconds left, 0 = always)",range={0,15,1}},
        {key="arcaneWindowWarnSeconds",kind="slider",labelKey="Arcane window warning (seconds)",range={0,10,1}},
        {key="arcaneWindowWarnLastGCD",kind="toggle",labelKey="Warn during the last global cooldown"},
    } end,colors={"ignorePainColor","arcaneWindowColor","arcaneWindowSoulColor","arcaneWindowWarnColor"}},
    {wanted=RegenTimers,specs=function() return {
        {key="manaRegenPause",kind="toggle",labelKey="Regeneration pause after spending"},
        {key="manaGainPulse",kind="toggle",labelKey="Mana return pulse"},
    } end,colors={"manaRegenPauseColor","manaGainPulseColor"}},
    {wanted=ExtraAuras,specs=function() return {
        {key="resourceExtraWidth",kind="slider",labelKey="Resource bar width",range={40,1000,1}},
        {key="resourceExtraHeight",kind="slider",labelKey="Resource bar height",range={2,30,1}},
        {key="resourceExtraOffsetX",kind="slider",labelKey="Resource bar X offset",range={-1000,1000,1}},
        {key="resourceExtraOffsetY",kind="slider",labelKey="Resource bar Y offset",range={-1000,1000,1}},
    } end,colors={}},
}
-- Setting keys of every client-only extra and of its color (Colors page,
-- BuildColors), and those this client builds.
function ResourceExtras.ClientOnlySettings()
    local all,built={},{}
    for _,group in ipairs(CLIENT_EXTRAS) do
        local wanted=group.wanted()
        for _,spec in ipairs(group.specs()) do
            all["bars."..spec.key]=true
            if wanted then built["bars."..spec.key]=true end
        end
        for _,key in ipairs(group.colors) do
            all["bars."..key]=true
            if wanted then built["bars."..key]=true end
        end
    end
    return all,built
end
function ResourceExtras.Specs()
    local specs={}
    for _,group in ipairs(CLIENT_EXTRAS) do
        if group.wanted() then
            for _,spec in ipairs(group.specs()) do specs[#specs+1]=spec end
        end
    end
    specs[#specs+1]={key="manaUpcomingCost",kind="toggle",labelKey="Mana spend preview"}
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
    for _,spec in ipairs(ResourceExtras.Specs()) do keys["bars."..spec.key]=true end
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
    for _,spec in ipairs(ResourceExtras.Specs()) do byKey[spec.key]=spec end
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
-- Resource controls retain the workspace binder's current selection and refresh policy.
local ROW_OPTIONS = { bind = function(ctx, widget, row, kind)
    local spec = { id=row.meta.controlId, kind=kind, key=row[2], labelKey=row[4][1], meta=row.meta,
        settingPath=row.meta.settingKey, scope=row.scope or "bars", applyDomain=row.domain or "resourceExtras",
        setting=row.setting, source=row.source, apply=row.apply, get=row.get, set = row.set, write = row.write,
            customSetReason = row.customSetReason or "Resolves a resource mark and updates its dependent mode or threshold fields.", workspace="classpower",
        defaultSource=function() return row[3] end }
    if kind=="slider" then spec.range={row[4][2],row[4][3],row[4][4]} end
    if kind=="dropdown" then spec.values=row[4][2] end
    Schema.Bind(ctx,widget,spec)
end }
local function SettingRow(spec,Bars,Apply,width)
    local args={spec.labelKey}
    if spec.range then args={spec.labelKey,spec.range[1],spec.range[2],spec.range[3],width}
    elseif spec.values then args={spec.labelKey,spec.values,width} end
    return {spec.kind=="toggle" and "flowToggle" or spec.kind,spec.key,Schema.Default("bars",spec.key),args,
        meta=Meta(spec.key,spec.key),source=Bars,apply=Apply}
end
local function Header(page,section,group,Bars,Apply)
    if section._msuf2ResourceExtraHeader then return end
    section._msuf2ResourceExtraHeader=true
    Schema.Section(section,"bars")
    local _,master=GroupSpecs(group)
    if master then
        local row=SettingRow(master,Bars,Apply)
        row.get=function() return Bars()[group.master]==true end
        row.customSetReason = "Executes the existing composite command, conversion or selection-dependent policy."
    row.write = {
        source = Bars, boolean = true,
        after = function() FocusExample(page, group) Apply() end
    } --[[schema setter: H4.ResourceExtras.1]]
        row[1]="sectionSwitch"
        Schema.Build(page.ctx,section,{row},ROW_OPTIONS)
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
    Schema.Section(section,"bars")
    Header(page,section,group,Bars,Apply)
    local rows={{"card",group.id..".settings",nil,
        {group.key=="layout" and "Size and position" or "Settings",nil,14,-38,cardW,height-58},scope="bars",domain="layout"}}
    for i,spec in ipairs(specs) do
        local key=spec.key
        local row=SettingRow(spec,Bars,function()
            M.ResourceExtrasPreview.FocusKey(key)
            M.ResourceExtrasPreview.UpdateHeader(page.ctx,page.workspace.selected)
            Apply()
            M.RequestRefresh(page.ctx,"resource-extra-setting")
        end,controlW)
        if spec.kind=="slider" then row.meta.step,row.meta.roundStep=spec.range[3],true end
        row[5]={32+(i-1)%columns*(controlW+20),-92-math.floor((i-1)/columns)*58,
            spec.kind=="toggle" and controlW-36 or controlW,"LEFT"}
        rows[#rows+1]=row
    end
    Schema.Build(page.ctx,section,rows,ROW_OPTIONS)
end
function ResourceExtras.BuildSections(page,Bars,Apply)
    Schema.Section(page.ctx.entry.sections.classpower_resource_visibility,"bars")
    local lazySection=page.LazySection
    function page:LazySection(id,title,height,method,prepareShell)
        if id~="classpower_resource_marks" then return lazySection(self,id,title,height,method,prepareShell) end
        return lazySection(self,id,title,height,method,function(ctx,section,unit,spec)
            Schema.Section(section,"resourceMarks")
            if prepareShell then return prepareShell(ctx,section,unit,spec) end
        end)
    end
    local header=page.ctx._resourceExtraHeader
    Schema.Owned(header.effect,"resourceExtras","previewNavigation")
    Schema.Owned(header.state,"resourceExtras","previewNavigation")
    -- The existing ClassPower owner builds this borrowed lazy section later.
    -- Declare its two exact controls after that build without replacing any binding.
    local buildVisibility=page.BuildResourceVisibility
    function page:BuildResourceVisibility(id,...)
        buildVisibility(self,id,...)
        if id=="classpower_resource_visibility" then
            local prefix="menu2.classpower.advanced.resource.extras.visibility."
            local independent=M.RuntimeControlCatalog.Get(prefix.."independent").widget
            local ooc=M.RuntimeControlCatalog.Get(prefix.."out.of.combat").widget
            Schema.Owned(independent,"bars","resourceVisibility")
            Schema.Owned(ooc,"bars","resourceVisibility")
            independent._msuf2ControlSchema.settingPath="bars.resourceExtraIndependentVisibility"
            ooc._msuf2ControlSchema.settingPath="bars.resourceExtraHideOOC"
        end
    end
    for _,group in ipairs(GROUPS) do
        if not group.wanted or group.wanted() then
            local count=#GroupSpecs(group)
            page:LazySection(group.id,group.title,function() return select(4,Geometry(page,count)) end,
                function() BuildGroup(page,group,Bars,Apply) end,
                function(_,section) Header(page,section,group,Bars,Apply) end)
        end
    end
end
local MARK_DEFAULTS=Schema.MarkDefaults
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
            local color=rule.color or MARK_DEFAULTS.color
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
    Schema.Section(section,"resourceMarks")
    local cardW,controlW,columns=Geometry(page,8)
    Schema.Build(ctx,section,{
        {"card","resourceMarks.mark",nil,{"Resource mark",nil,14,-38,cardW,154},scope="resourceMarks",domain="layout"},
        {"card","resourceMarks.settings",nil,{"Settings",nil,14,-212,cardW,height-232},scope="resourceMarks",domain="layout"},
    })
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
    Schema.Build(ctx,section,{
        {"dropdown","select",nil,{"Resource mark",function() return MarkValues(Bars) end,280},{32,-92,controlW,"LEFT"},
            meta=Meta("marks.select",nil,"ephemeral"),scope="resourceMarks",domain="navigation",
            get=function() return MarkIndex(Bars) end,
                customSetReason = "Changes editor selection or input state rather than a fixed profile field.",
                set=function(value) selectedMark=value Refresh() end},
    },ROW_OPTIONS)

    local function Button(label,x,path,callback)
        local button=M.Theme.Button(section,label,130,26,{history=true})
        button:SetPoint("TOPLEFT",section,"TOPLEFT",x,-146)
        button:SetScript("OnClick",callback)
        local meta=Meta(path,"resourceMarks","action")
        AP.RegisterControl(button,meta,label,"button")
        local action=Schema.ButtonAction(button)
        Schema.Custom(button,{id=meta.controlId,kind="button",labelKey=label,scope="resourceMarks",
            applyDomain="resourceExtras",settingPath=meta.settingKey,meta=meta,owner=button,
            customSetReason="Adds or removes a resource mark and maintains the selected list entry.",set=action,action=action})
    end
    Button("Add resource mark",32,"marks.add",function()
        local b=Bars()
        if not b.resourceMarks then
            b.resourceMarks={}
        end
        local rules=b.resourceMarks
        rules[#rules+1]=AP.DeepCopyTable(MARK_DEFAULTS)
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
    local rows={
        {"dropdown","target","PLAYER",{"Resource bar",{{value="PLAYER",text="Player power"},
            {value="CLASS",text="Class resource"},{value="ALTMANA",text="Alternative mana"}},280}},
        {"dropdown","resource","ALL",{"Power type",PowerTypeValues(),280}},
        {"dropdown","mode","PERCENT",{"Value mode",{{value="PERCENT",text="Percent"},
            {value="ABSOLUTE",text="Absolute value"}},280}},
        {"slider","value",MARK_DEFAULTS.value,{"Resource value",0,10000000,1,280}},
        {"slider","width",MARK_DEFAULTS.width,{"Mark width",1,20,1,280}},
        {"flowToggle","mark",MARK_DEFAULTS.mark,{"Show resource mark"}},
        {"flowToggle","threshold",MARK_DEFAULTS.threshold,{"Change color at threshold"}},
        {"dropdown","direction","ABOVE",{"Threshold direction",{{value="ABOVE",text="At or above"},
            {value="BELOW",text="Below"}},280}},
    }
    for i,row in ipairs(rows) do
        local key=row[2]
        row.meta,row.scope=Meta("marks."..key),"resourceMarks"
        local paths={"bars.resourceMarks.{selected}."..key}
        if key=="mode" then paths[#paths+1]="bars.resourceMarks.{selected}.value" end
        row.setting=Schema.Record(paths)
        row.setting.resolve=function() return "bars.resourceMarks."..tostring(MarkIndex(Bars)).."."..key end
        row.get=function()
            local rule=Rule()
            if row[1]=="flowToggle" then
                return rule and rule[key]~=false and (key=="mark" or rule[key]==true) or false
            end
            return rule and rule[key] or row[3]
        end
        if key=="mode" then
            row.customSetReason="Changes the value mode and clamps the stored resource value."
            row.set=function(value) Write(key,value) end
        else
            row.write={source=Rule,requireRecord=true,
                convert=key=="value" and function(value)
                    local stored=tonumber(value)
                    return stored and math.max(0,math.min(ValueMax(Rule()),stored)) or value
                end or nil,
                after=function()
                    Apply()
                    if key=="target" or key=="resource" then Refresh() end
                end
            } --[[schema setter: H4.ResourceExtras.3]]
        end
        if key=="value" then
            row.beforeBind=function(widget)
                M.TrackRefresh(ctx,function()
                    widget._msuf2Refreshing=true
                    widget:SetMinMaxValues(0,SliderMax(Rule()))
                    widget._msuf2Refreshing=nil
                end)
            end
        end
        local column=columns==2 and i>5 and 1 or 0
        local index=column==1 and i-6 or i-1
        row[5]={32+column*(controlW+20),-268-index*58,row[1]=="flowToggle" and controlW-36 or controlW,"LEFT"}
    end
    Schema.Build(ctx,section,rows,ROW_OPTIONS)
end
function ResourceExtras.MarksHeight(page) return page.width>=680 and 612 or 786 end
local function BuildMarkColors(ctx,b,Bars,ColorValueAt,Apply)
    local section=b:CollapsibleSection("colors_resource_marks","Resource marks and thresholds",154,false)
    Schema.Section(section,"resourceMarks")
    local function ColorMeta(path,kind)
        return M.ControlMeta("colors","advanced","resource_extras.marks."..path,kind or "setting",{searchSettingKeys={"bars.resourceMarks"}})
    end
    Schema.Build(ctx,section,{
        {"dropdown","select",nil,{"Resource mark",function() return MarkValues(Bars) end,260},{24,-42,260,"LEFT"},
            meta=ColorMeta("select","ephemeral"),scope="resourceMarks",domain="navigation",
            get=function() return MarkIndex(Bars) end,
                customSetReason = "Changes editor selection or input state rather than a fixed profile field.", set=function(value)
                selectedMark=value
                M.RequestRefresh(ctx,"resource-mark-color-selection")
            end},
    },ROW_OPTIONS)
    local color=ColorValueAt(ctx,section,"Mark and threshold color",24,-100,
        function()
            local rule=ResourceExtras.MarkRule(Bars)
            local c=rule and rule.color or MARK_DEFAULTS.color
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
    Schema.Owned(color,"resourceMarks","resourceExtras")
    M.TrackRefresh(ctx,function() AP.SetControlEnabled(color,ResourceExtras.MarkRule(Bars)~=nil) end)
end
function ResourceExtras.BuildColors(ctx,b,Bars,ColorValueAt,Apply)
    local specs=ColorSpecs()
    local section=b:CollapsibleSection("colors_resource_extras","Additional resource colors",64+#specs*38,false)
    Schema.Section(section,"bars")
    for i,spec in ipairs(specs) do
        local key=spec[1]
        local color=ColorValueAt(ctx,section,spec[2],24,-40-(i-1)*38,
            function() return ColorRGB(Bars,spec) end,
            function(r,g,blue)
                Bars()[key]={r,g,blue}
                Apply()
            end,200,44,
            M.ControlMeta("colors","advanced","resource_extras."..key,"setting",{settingKey="bars."..key}))
        Schema.Owned(color,"bars","resourceExtras")
    end
    BuildMarkColors(ctx,b,Bars,ColorValueAt,Apply)
end
