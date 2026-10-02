local _,MSUF=...
local M=MSUF.MSUF2
local W,T,AP=M.Widgets,M.Theme,M.AdvancedPage
local F,V=MSUF.ProfileFields,MSUF.ProfileVariants
local P={}; M.ProfileVariantPage=P
local selected,fieldID,editorBar
-- A saved schema that fails validation (a newer import, too many variants, a
-- tightened rule) must never look empty: the page names the error and every write
-- refuses with it, so the next Create or Delete cannot replace the saved variants.
local function Schema()
    local saved=M.EnsureDB().profileVariants
    local clean,err=V.Validate(saved)
    if clean then return clean end
    if saved==nil then return {version=1,entries={}} end
    return nil,err or "invalid profile variants"
end
local function Entry(schema)
    for _,entry in ipairs(schema.entries) do if entry.name==selected then return entry end end
end
function P.Meta(section,path)
    return M.ProfileSearch.Meta(path, AP.ControlMeta("profiles",section,path,"ephemeral"))
end
function P.Refresh(ctx)
    M.ProfileSearch.Refresh()
    P.EditorBar(ctx)
    if M.RebuildPageKeepingScroll and M.RebuildPageKeepingScroll("profiles") then return end
    if M.InvalidatePage then M.InvalidatePage("profiles") end
    if M.RequestRefresh then M.RequestRefresh(ctx,"profile-variants") end
end
function P.EditorBar(ctx)
    if not V.IsRecording() then if editorBar then editorBar:Hide() end; return end
    if not editorBar then
        editorBar=T.Panel(UIParent)
        editorBar:SetSize(460,86)
        editorBar:SetPoint("BOTTOM",UIParent,"BOTTOM",0,140)
        editorBar:SetFrameStrata("DIALOG")
        editorBar.title=W.Text(editorBar,"",16,-14,428,T.colors.text)
        local save=T.Button(editorBar,"Save variant values",206,26)
        save:SetPoint("TOPLEFT",editorBar,"TOPLEFT",16,-46)
        save:SetScript("OnClick",function() P.Result(editorBar.ctx,V.SaveRecording()) end)
        local cancel=T.Button(editorBar,"Cancel variant editing",206,26)
        cancel:SetPoint("TOPRIGHT",editorBar,"TOPRIGHT",-16,-46)
        cancel:SetScript("OnClick",function()
            if InCombatLockdown() then return end
            P.Result(editorBar.ctx,V.CancelRecording())
        end)
    end
    editorBar.ctx=ctx
    T.SetTranslatedText(editorBar.title,M.Format("Editing profile variant: %s",V.RecordingName()))
    editorBar:Show()
end
function P.Result(ctx,ok,err)
    if not ok then
        if M.ShowStatusFeedback then M.ShowStatusFeedback(tostring(err or "Action unavailable"),"danger",4) end
        return false
    end
    if M.ClearHistory then M.ClearHistory() end
    P.Refresh(ctx)
    return true
end
function P.FieldLabel(path)
    local parts={}
    for i,key in ipairs(path) do
        local text=tostring(key):gsub("(%l)(%u)","%1 %2"):gsub("_"," ")
        parts[i]=M.Tr(text:sub(1,1):upper()..text:sub(2))
    end
    return table.concat(parts," / ")
end
local function Put(ctx,schema) return P.Result(ctx,V.Replace(M.EnsureDB(),schema)) end
function P.Button(state,section,label,path,x,y,fn,width)
    local button=state.ProfileButton(section,label,function()
        if state.ConfigLocked() then return end
        return fn()
    end,false,path,false,nil,nil,nil,width or 180)
    button:SetPoint("TOPLEFT",section,"TOPLEFT",x,y)
    local sectionKey=path:match("^sync%.") and "profiles_sync" or "profiles_variants"
    AP.RegisterControl(button,P.Meta(sectionKey,path),label,"button")
    return button
end
function P.Drop(state,section,label,path,values,get,set,x,y,width)
    local drop=W.Dropdown(section,label,values,width or 250)
    W.MoveWidget(drop,section,x,y,width or 250)
    local sectionKey=path:match("^sync%.") and "profiles_sync" or "profiles_variants"
    local meta=P.Meta(sectionKey,path)
    M.BindDropdownWidget(state.ctx,drop,get,set,meta)
    AP.RegisterControl(drop,meta,label,"dropdown",values)
    return drop
end
function P.BindBool(ctx,widget,get,set,meta)
    M.BindBoolWidget(ctx,widget,get,set,meta)
    AP.RegisterControl(widget,meta,widget._msuf2SearchText or widget._msuf2SearchTitle,"toggle")
    return widget
end
local function VariantValues()
    local out,schema={{value="",text="Choose a variant"}},Schema()
    for _,entry in ipairs(schema and schema.entries or {}) do out[#out+1]={value=entry.name,text=entry.name} end
    return out
end
local function Conditions(state,section,entry,schema,width,specs)
    local c=entry.conditions
    local left,right=20,30+width
    P.Drop(state,section,"Where","variant.condition.context",{
        {value="any",text="Anywhere"},{value="party",text="Dungeon"},{value="raid",text="Raid"},
        {value="arena",text="Arena"},{value="pvp",text="Battleground"},{value="solo",text="Solo outdoors"},
        {value="world",text="Grouped outdoors"},
    },function() return c.context or "any" end,function(value) c.context=value~="any" and value or nil end,left,-270,width)
    P.Drop(state,section,"Dark Mode condition","variant.condition.dark",{
        {value="any",text="Any state"},{value="on",text="Dark Mode on"},{value="off",text="Dark Mode off"},
    },function() return c.dark==nil and "any" or c.dark and "on" or "off" end,function(value)
        if value=="any" then c.dark=nil else c.dark=value=="on" end
    end,right,-270,width)
    local hotkeys={{value=0,text="Automatic"}}
    for i=1,8 do hotkeys[#hotkeys+1]={value=i,text=M.Format("Hotkey slot %d",i)} end
    P.Drop(state,section,"Activation","variant.condition.hotkey",hotkeys,
        function() return entry.hotkey or 0 end,function(value)
            entry.hotkey=value~=0 and value or nil; c.manual=value~=0
        end,left,-350,width)
    local enabled=W.SwitchAt(section,"Enable variant",right,-350,width)
    P.BindBool(state.ctx,enabled,function() return entry.enabled~=false end,
        function(value) entry.enabled=value==true end,P.Meta("profiles_variants","variant.enabled"))
    W.Text(section,"Specializations: none selected means all. Matching conditions are combined; later variants take priority.",
        20,-414,state.contentW-40,T.colors.muted)
    c.specs=c.specs or {}
    for i,spec in ipairs(specs) do
        local id=tostring(spec.id)
        local toggle=W.SwitchAt(section,spec.name,20+((i-1)%2)*(width+10),-454-math.floor((i-1)/2)*32,width)
        P.BindBool(state.ctx,toggle,function() return c.specs[id]==true end,
            function(value) c.specs[id]=value and true or nil end,P.Meta("profiles_variants","variant.spec."..i))
    end
    return -464-math.ceil(#specs/2)*32
end
function P.Build(state,specs)
    if not V then return end
    local ctx=state.ctx
    P.EditorBar(ctx)
    local schema,schemaError=Schema()
    local entry=schema and Entry(schema)
    if schema and not entry and schema.entries[1] then selected=schema.entries[1].name; entry=schema.entries[1] end
    M.ProfileSearch.Selecting("variant",selected)
    local width=math.max(180,math.floor((state.contentW-50)/2))
    local section=state.b:CollapsibleSection("profiles_variants","Profile variants",entry and (850+math.ceil(#specs/2)*32) or 250,true)
    W.Text(section,"Override individual settings or layouts for several specializations, a location or a hotkey. The base profile stays intact.",
        20,-40,state.contentW-40,T.colors.muted)
    if schemaError then
        W.Text(section,M.Format("The saved profile variants cannot be read (%s). They are kept unchanged, and editing them here is blocked.",
            M.Tr(schemaError)),20,-62,state.contentW-40,T.colors.danger or T.colors.muted)
    end
    P.Drop(state,section,"Variant","variant.select",VariantValues,function() return selected or "" end,
        function(value) selected=value; fieldID=nil; P.Refresh(ctx) end,20,-98,width)
    local input=W.TextInput(section,"New variant name",width)
    W.MoveWidget(input,section,30+width,-98,width)
    AP.RegisterControl(input,P.Meta("profiles_variants","variant.name"),"New variant name","editbox")
    P.Button(state,section,"Create variant","variant.create",30+width,-168,function()
        local name=tostring(input:GetText() or ""):match("^%s*(.-)%s*$")
        local current,err=Schema()
        if not current then return P.Result(ctx,false,err) end
        current.entries[#current.entries+1]={name=name,conditions={},patch={}}
        local ok,err=V.Replace(M.EnsureDB(),current)
        if ok then selected=name end
        return P.Result(ctx,ok,err)
    end,width)
    if not entry then return end
    W.Text(section,"Change conditions below, then save them. Assign hotkey slots in the game's MSUF key bindings.",
        20,-218,state.contentW-40,T.colors.muted)
    local y=Conditions(state,section,entry,schema,width,specs)
    P.Button(state,section,"Save conditions","variant.conditions.save",20,y,function() return Put(ctx,schema) end,width)
    P.Button(state,section,"Delete variant","variant.delete",30+width,y,function()
        local current,err=Schema()
        if not current then return P.Result(ctx,false,err) end
        for i,v in ipairs(current.entries) do if v.name==selected then table.remove(current.entries,i); break end end
        selected=nil
        return Put(ctx,current)
    end,width)
    y=y-64
    local editing=V.IsRecording()
    W.Text(section,editing and M.Format("Editing %s: use the normal settings pages or Edit Mode, then return here to save or cancel.",V.RecordingName())
        or "Edit values records only changed settings. Removing an overridden value returns that setting to the base profile.",
        20,y,state.contentW-40,T.colors.muted)
    y=y-64
    if editing then
        P.Button(state,section,"Save variant values","variant.values.save",20,y,function() return P.Result(ctx,V.SaveRecording()) end,width)
        P.Button(state,section,"Cancel variant editing","variant.values.cancel",30+width,y,function() return P.Result(ctx,V.CancelRecording()) end,width)
    else
        P.Button(state,section,"Edit variant values","variant.values.edit",20,y,function() return P.Result(ctx,V.BeginRecording(selected)) end,width)
        P.Button(state,section,"Use hotkey variant","variant.activate",30+width,y,function()
            -- The saved entry decides, not this page's unsaved copy of the conditions.
            local saved=V.Find(M.EnsureDB(),selected)
            if not (saved and type(saved.conditions)=="table" and saved.conditions.manual) then
                return P.Result(ctx,false,"Choose a hotkey slot and save the conditions first.")
            end
            V.SetManual(selected); V.RequestApply("PROFILE_VARIANT_PREVIEW",true); P.Refresh(ctx)
        end,width)
    end
    y=y-56
    local fields={{value="",text="Choose an overridden setting"}}
    for _,field in ipairs(entry.patch) do fields[#fields+1]={value=F.ID(field.path),text=P.FieldLabel(field.path)} end
    P.Drop(state,section,M.Format("Overridden settings (%d)",#entry.patch),"variant.field.select",fields,
        function() return fieldID or "" end,function(value) fieldID=value end,20,y,width)
    P.Button(state,section,"Return setting to base","variant.field.remove",30+width,y-24,function()
        local current,err=Schema()
        if not current then return P.Result(ctx,false,err) end
        local owner=Entry(current)
        if owner then
            for i,field in ipairs(owner.patch) do if F.ID(field.path)==fieldID then table.remove(owner.patch,i); break end end
        end
        return Put(ctx,current)
    end,width)
end
function P.Transport(state)
    local section=state.b:CollapsibleSection("profiles_variant_transport","Variant import and export",192,true)
    W.Text(section,"Full-profile strings can include the base settings and their variants. Partial exports contain base settings only. Excluding variants on import keeps your existing variants.",
        20,-42,state.contentW-40,T.colors.muted)
    for i,spec in ipairs({{"Export profile variants","profileExportVariants","MSUF_Profiles_SetExportVariants"},
        {"Import profile variants","profileImportVariants","MSUF_Profiles_SetImportVariants"}}) do
        local toggle=W.SwitchAt(section,spec[1],20,-104-(i-1)*36,state.contentW-40)
        P.BindBool(state.ctx,toggle,function() return M[spec[2]]~=false end,function(value)
            M[spec[2]]=value==true; _G[spec[3]](value)
        end,P.Meta("profiles_variant_transport",spec[2]))
    end
end

M.ProfileSearch.RegisterSelector("variant",function(name) selected=name; fieldID=nil end)
