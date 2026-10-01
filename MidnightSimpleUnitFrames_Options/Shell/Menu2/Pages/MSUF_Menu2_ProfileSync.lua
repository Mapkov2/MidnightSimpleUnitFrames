local _,MSUF=...
local M=MSUF.MSUF2
local W,T=M.Widgets,M.Theme
local P,F,S= M.ProfileVariantPage,MSUF.ProfileFields,MSUF.ProfileSync
local selected,selectedField,excludedField
local labels={unitframes="Unitframes",groupframes="Group frames",castbars="Castbars",colors="Colors",
    auras="Auras",resources="Class Resources",gameplay="Gameplay"}
local function Entry(groups)
    for _,group in ipairs(groups) do if group.name==selected then return group end end
end
local function GroupValues()
    local out={{value="",text="Choose a sync group"}}
    for _,group in ipairs(S.GetGroups() or {}) do out[#out+1]={value=group.name,text=group.name} end
    return out
end
-- The exclusion catalog walks every leaf of the profile's base snapshot. It is
-- built on first use and kept while the profile and the menu's data revision
-- (bumped by every recorded menu change) stay the same, so a page rebuild after a
-- variant or sync action reuses it and a new setting still appears.
local catalogCache
local function FieldCatalog()
    local db,profile,revision=M.EnsureDB(),_G.MSUF_ActiveProfile,M._msuf2MenuDataRevision
    local cached=catalogCache
    if cached and cached.db==db and cached.profile==profile and cached.revision==revision then return cached.list end
    local out,path={},{}
    local function Visit(value,depth)
        if depth>12 then return end
        if type(value)=="table" then
            for key,child in pairs(value) do
                if not (type(key)=="string" and key:match("^_")) then
                    path[depth+1]=key; Visit(child,depth+1); path[depth+1]=nil
                end
            end
        elseif depth>=2 and F.Path(path) and S.Owner(path) then
            out[#out+1]={path=F.Copy(path),id=F.ID(path),label=P.FieldLabel(path),module=S.Owner(path)}
        end
    end
    Visit(MSUF.ProfileVariants.BaseSnapshot(db,true) or {},0)
    table.sort(out,function(a,b) return a.label<b.label end)
    catalogCache={db=db,profile=profile,revision=revision,list=out}
    return out
end
local function Save(ctx,groups) return P.Result(ctx,S.Replace(groups)) end
local function Exclusions(state,section,group,groups,y,width)
    local query=""
    local input=W.TextInput(section,"Find a setting to exclude",width)
    W.MoveWidget(input,section,20,y,width)
    M.AdvancedPage.RegisterControl(input,P.Meta("profiles_sync","sync.field.search"),"Find a setting to exclude","editbox")
    input:HookScript("OnTextChanged",function(self) query=tostring(self:GetText() or ""):lower() end)
    local function Values()
        local out={{value="",text="Choose a setting"}}
        for _,field in ipairs(FieldCatalog()) do
            if group.modules[field.module] and (query=="" or field.label:lower():find(query,1,true)) then
                out[#out+1]={value=field.id,text=field.label}
                if #out>=101 then break end
            end
        end
        return out
    end
    P.Drop(state,section,"Setting","sync.field.select",Values,function() return selectedField or "" end,
        function(value) selectedField=value end,30+width,y,width)
    y=y-78
    P.Button(state,section,"Exclude this setting","sync.field.exclude",20,y,function()
        for _,field in ipairs(FieldCatalog()) do
            if field.id==selectedField then
                for _,path in ipairs(group.exclude) do if F.ID(path)==field.id then return end end
                group.exclude[#group.exclude+1]=F.Copy(field.path)
                return Save(state.ctx,groups)
            end
        end
    end,width)
    local function Excluded()
        local out={{value="",text="Choose an excluded setting"}}
        for _,path in ipairs(group.exclude) do out[#out+1]={value=F.ID(path),text=P.FieldLabel(path)} end
        return out
    end
    y=y-56
    P.Drop(state,section,"Excluded settings","sync.exclusion.select",Excluded,function() return excludedField or "" end,
        function(value) excludedField=value end,20,y,width)
    P.Button(state,section,"Remove exclusion","sync.exclusion.remove",30+width,y-24,function()
        for i,path in ipairs(group.exclude) do if F.ID(path)==excludedField then table.remove(group.exclude,i); break end end
        return Save(state.ctx,groups)
    end,width)
end
function M.ProfileSyncPageBuild(state)
    if not S then return end
    local ctx=state.ctx
    local groups=S.GetGroups() or {}
    local group=Entry(groups)
    if not group and groups[1] then selected=groups[1].name; group=groups[1] end
    M.ProfileSearch.Selecting("sync",selected)
    local names=_G.MSUF_GetAllProfiles()
    local rows=math.ceil(#names/2)
    local width=math.max(180,math.floor((state.contentW-50)/2))
    local section=state.b:CollapsibleSection("profiles_sync","Profile synchronization",group and (950+rows*32+math.max(0,math.ceil(#S.Modules/2)-4)*32) or 250,true)
    W.Text(section,"Share selected modules between profiles. Changes sync when switching profiles or logging out. Local variant settings and excluded fields stay independent.",
        20,-40,state.contentW-40,T.colors.muted)
    P.Drop(state,section,"Sync group","sync.group.select",GroupValues,function() return selected or "" end,
        function(value) selected=value; selectedField=nil; excludedField=nil; P.Refresh(ctx) end,20,-108,width)
    local input=W.TextInput(section,"New sync group name",width)
    W.MoveWidget(input,section,30+width,-108,width)
    M.AdvancedPage.RegisterControl(input,P.Meta("profiles_sync","sync.group.name"),"New sync group name","editbox")
    P.Button(state,section,"Create sync group","sync.group.create",30+width,-178,function()
        local current=S.GetGroups() or {}
        local name=tostring(input:GetText() or ""):match("^%s*(.-)%s*$")
        current[#current+1]={name=name,members={[_G.MSUF_ActiveProfile]=true},modules={unitframes=true},exclude={}}
        local ok,why=S.Replace(current)
        if ok then selected=name end
        return P.Result(ctx,ok,why)
    end,width)
    if not group then return end
    W.Text(section,"Member profiles",20,-234,state.contentW-40,T.colors.text)
    for i,name in ipairs(names) do
        local toggle=W.SwitchAt(section,name,20+((i-1)%2)*(width+10),-266-math.floor((i-1)/2)*32,width)
        P.BindBool(ctx,toggle,function() return group.members[name]==true end,
            function(value) group.members[name]=value and true or nil end,P.Meta("profiles_sync","sync.member."..i))
    end
    local y=-282-rows*32
    W.Text(section,"Shared modules",20,y,state.contentW-40,T.colors.text)
    y=y-34
    for i,id in ipairs(S.Modules) do
        local toggle=W.SwitchAt(section,labels[id] or (S.Labels and S.Labels[id]) or id,20+((i-1)%2)*(width+10),y-math.floor((i-1)/2)*32,width)
        P.BindBool(ctx,toggle,function() return group.modules[id]==true end,
            function(value) group.modules[id]=value and true or nil end,P.Meta("profiles_sync","sync.module."..id))
    end
    y=y-20-math.ceil(#S.Modules/2)*32
    P.Button(state,section,"Save sync group","sync.group.save",20,y,function() return Save(ctx,groups) end,width)
    P.Button(state,section,"Delete sync group","sync.group.delete",30+width,y,function()
        local current=S.GetGroups() or {}
        for i,g in ipairs(current) do if g.name==selected then table.remove(current,i); break end end
        selected=nil
        return Save(ctx,current)
    end,width)
    y=y-44
    P.Button(state,section,"Synchronize changes now","sync.flush",20,y,function() return P.Result(ctx,S.Flush()) end,width)
    P.Button(state,section,"Copy shared modules now","sync.initialize",30+width,y,function() return P.Result(ctx,S.Flush(true)) end,width)
    y=y-42
    W.Text(section,"Copy shared modules now uses the active profile as the starting point for its groups. Existing local exclusions and variant values are preserved. Save the group first.",
        20,y,state.contentW-40,T.colors.muted)
    Exclusions(state,section,group,groups,y-62,width)
end
M.ProfileSyncPage={Build=M.ProfileSyncPageBuild}

M.ProfileSearch.RegisterSelector("sync",function(name) selected=name; selectedField=nil; excludedField=nil end)
