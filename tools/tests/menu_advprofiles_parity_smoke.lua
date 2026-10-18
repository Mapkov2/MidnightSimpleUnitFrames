-- Replay the immutable parent and replacing rows through the same native owners.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
io.stdout:setvbuf("no")
local flavor = arg[2] or "Mainline"
local started = os.clock()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local sources = {}
-- Blob pins survive package rebases and need no scratch directory in a gate checkout.
for _, fixture in ipairs({
    { "Advanced", "71335f624ddf3788a6f3fa562df9c654de4337df" },
    { "AdvancedGameplay", "f844393b907abac9f27784549fab26b615c9581d" },
    { "AdvancedProfiles", "bfd77d2284e9c9f13ed33c7dca3e7c4711e9506c" },
    { "ProfileCleanup", "78825e58cc692c64cf066390bb7a35353e120184" },
    { "ProfileSearch", "cd2dfa54cefc74035fa43fe26067b72af8e37c04" },
    { "ProfileSync", "382c2e64e5f94ede11f6649a658870f0125029b8" },
    { "ProfileVariants", "d27bbd240a9ad8637da1dd54b1ef734349935692" },
}) do
    local path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_" .. fixture[1] .. ".lua"
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. fixture[2], "r"))
    local source = pipe:read("*a")
    pipe:close()
    assert(#source > 100, "parent source unavailable: " .. path)
    sources[path] = source
end
local function Serialize(value, seen)
    local kind = type(value)
    if kind ~= "table" then
        if kind == "string" then return string.format("%q", value) end
        if kind == "function" or kind == "userdata" then return kind end
        return tostring(value)
    end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out+1] = Serialize(key) .. "=" .. Serialize(value[key], seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Same(a,b,where)
    local seen={}
    local function Compare(left,right,path)
        local kind=type(left)
        if kind==type(right) then
            if kind=="function" or kind=="userdata" or left==right then return end
            if kind=="table" then
                if seen[left]==right then return end
                seen[left]=right
                for key,value in pairs(left) do Compare(value,right[key],path.."."..tostring(key)) end
                for key,value in pairs(right) do
                    if left[key]==nil then Compare(nil,value,path.."."..tostring(key)) end
                end
                return
            end
        end
        error(flavor .. " " .. where .. " " .. path .. "\nparent: " .. Serialize(left):sub(1,600)
            .. "\nrows:   " .. Serialize(right):sub(1,600), 2)
    end
    Compare(a,b,"")
end
local function Open(prior, edge)
    local counts = { apply = 0, refresh = 0 }
    local h = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local load = world.LoadFile
            function world:LoadFile(path, addon, namespace)
                if path:match("/State/MSUF_Profiles.lua$") then
                    -- Count the real profile-to-runtime boundary; native frame painting is outside this fixture.
                    world.core.ProfileRuntime.Apply=function()
                        counts.apply=counts.apply+1
                        world.core.ProfileVariants.ResolveCurrent()
                    end
                end
                local relative = path:sub(#root+2)
                if prior and sources[relative] then
                    local chunk = assert(loadstring(sources[relative], "@" .. path))
                    setfenv(chunk, self.env)
                    chunk(addon,namespace)
                    return true
                end
                if not prior and arg[3] and sources[relative] then
                    local candidate=arg[3] .. "/" .. relative
                    local file=io.open(candidate,"rb")
                    if file then
                        file:close()
                        path=candidate
                    end
                end
                return load(self,path,addon,namespace)
            end
            world.env.GetSpecialization = function() return 1 end
            world.env.GetNumSpecializations = function() return 2 end
            world.env.GetSpecializationInfo = function(i) return i == 2 and 63 or 62, i == 2 and "Fire" or "Arcane" end
            world.env.C_SpecializationInfo = { GetSpecialization = world.env.GetSpecialization,
                GetNumSpecializations = world.env.GetNumSpecializations, GetSpecializationInfo = world.env.GetSpecializationInfo }
            world.env.UnitAffectingCombat = function() return false end
            world.widgets.Methods.GetCenter = function() return 400,300 end
        end })
    local M,e,n = h.M,h.env,h.core
    h.prior = prior
    h.counts = counts
    local refresh = M.Refresh
    M.Refresh = function(...)
        h.counts.refresh=h.counts.refresh+1
        return refresh(...)
    end
    n.MSUF_RequestGameplayApply = function()
        h.counts.apply=h.counts.apply+1
        return true
    end
    n.ProfileRuntime.Apply = function()
        h.counts.apply=h.counts.apply+1
        n.ProfileVariants.ResolveCurrent()
    end
    e.MSUF_UFCore_NotifyConfigChanged = function() end
    e.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    local factory = n.ProfileFields.CopySnapshot(e.MSUF_DB)
    n.MSUF_CreateFactoryDefaultProfile = function() return n.ProfileFields.CopySnapshot(factory) end
    -- Native CBOR/compression is a client boundary. Compare its complete payload instead.
    e.MSUF_EncodeCompactTableMSUF3=function(value)
        h.exported=n.ProfileFields.CopySnapshot(value)
        return "MSUF3:captured"
    end
    e.MSUF_EncodeCompactTable=e.MSUF_EncodeCompactTableMSUF3
    e.MSUF_TryDecodeCompactString=function(value)
        if value=="MSUF3:captured" then return n.ProfileFields.CopySnapshot(h.exported) end
    end
    e.MSUF_ActiveProfile = "Default"
    e.MSUF_GlobalDB = { profiles = { Default=e.MSUF_DB, Other=n.ProfileFields.CopySnapshot(factory),
        Unused=n.ProfileFields.CopySnapshot(factory) }, char={}, global={} }
    assert(n.ProfileVariants.Replace(e.MSUF_DB,{version=1,entries={{name="Dungeon",enabled=not edge,
        hotkey=edge and 2 or nil, conditions=edge and {dark=false,manual=true,context="party"} or {},
        patch={{path={"player","width"},value=321}}}}}))
    assert(n.ProfileSync.Replace({{name="Shared",members={Default=true,Other=true},modules={unitframes=true,gameplay=edge or nil},
        exclude=edge and {{"player","width"}} or {}}}))
    if edge then
        local g=e.MSUF_DB.gameplay
        g.enableCombatTimer,g.enableCombatStateText,g.enableCombatCrosshair,g.enablePlayerTotems=true,true,true,true
        g.enableCombatCrosshairMeleeRangeColor,g.meleeSpellPerClass,g.meleeSpellPerSpec=true,true,true
        g.combatFontSize,g.combatOffsetX,g.crosshairThickness=31,0,7
        M.profileImportCreateNew=true
        assert(n.ProfileVariants.BeginRecording("Dungeon"))
    end
    h.prompts={}
    M.ShowPrompt=function(id,options)
        h.prompts[#h.prompts+1]={id=id,text=options.text}
        h.accept=options.onAccept
    end
    h.built={}
    -- Capture real native constructor outputs, including unregistered cleanup controls.
    h.native={}
    for _, pair in ipairs({{M.Theme,"Button"},{M.Widgets,"TextInput"},{M.Widgets,"SwitchAt"},
        {M.Widgets,"Dropdown"},{M.Widgets,"Slider"},{M.Widgets,"Toggle"},{M.Widgets,"Text"},
        {M.Widgets,"LabelAt"},{M.Widgets,"ControlCard"}}) do
        local owner,key=pair[1],pair[2]
        local original=owner[key]
        owner[key]=function(parent,label,...)
            local widget=original(parent,label,...)
            h.native[#h.native+1]={widget=widget,kind=key,label=label,args={...}}
            return widget
        end
    end
    function h:Build(page)
        self:Select(page)
        for _,section in pairs(M.cache[page].sections) do
            local entry=section._msuf2CollapsibleEntry
            if entry then entry.SetOpenImmediate(true) end
        end
        self:RunTimers()
        M.Refresh(M.cache[page].ctx)
        self.built[page]=true
    end
    return h
end
local function Read(widget,kind)
    local command=widget._msuf2CommandAction
    if command and command.get then return command.get() end
    if kind=="toggle" then return widget:GetChecked() end
    if kind=="slider" or kind=="dropdown" then return widget:GetValue() end
    if kind=="editbox" or kind=="textinput" then return widget:GetText() end
end
local function State(h)
    local menu={}
    for key,value in pairs(h.M) do
        if type(key)=="string" and key:match("^profile") and type(value)~="function" then menu[key]=value end
    end
    return {db=h.env.MSUF_DB,global=h.env.MSUF_GlobalDB,active=h.env.MSUF_ActiveProfile,
        menu=menu,counts=h.counts,prompts=h.prompts,search=h.M.ProfileSearch.Collect(),exported=h.exported}
end
local function Inventory(h,page)
    local out={}
    for _,record in ipairs(h.M.RuntimeControlCatalog.GetRecords()) do
        if record.pageKey==page then
            local widget=h.M.RuntimeControlCatalog.Get(record.controlId).widget
            if not h.prior and (record.kind=="toggle" or record.kind=="slider" or record.kind=="dropdown"
                or record.kind=="textinput" or record.kind=="editbox") then
                local declaration=assert(widget._msuf2ControlSchema,"undeclared input: "..record.controlId)
                assert(declaration.id==record.controlId,"declaration identity drift: "..record.controlId)
                if declaration.get then Same(Read(widget,record.kind),declaration.get(),record.controlId.." declared getter") end
            end
            out[#out+1]={id=record.controlId,label=record.label,kind=record.kind,setting=record.settingKey,action=record.actionKey,
                searchLabel=widget._msuf2SearchMeta and widget._msuf2SearchMeta.label,
                stableLabel=widget._msuf2StableSearchLabel,workspace=record.workspace,
                searchWorkspace=widget._msuf2SearchMeta and widget._msuf2SearchMeta.workspace,
                value=Read(widget,record.kind),enabled=widget.IsEnabled and widget:IsEnabled(),shown=widget:IsShown(),
                width=widget:GetWidth(),height=widget:GetHeight(),values=widget.GetValues and widget:GetValues(),help=record.help}
        end
    end
    table.sort(out,function(a,b) return a.id<b.id end)
    return out
end
local function NativeInventory(h)
    local ids,out={},{}
    for i,frame in ipairs(h.world.widgets.frames) do ids[frame]=i end
    for _,entry in ipairs(h.native) do
        local widget,points=entry.widget,{}
        local args={}
        for key,value in pairs(entry.args) do args[key]=value end
        -- Dense row arguments spell out the native default before the literal-name flag.
        if entry.kind=="SwitchAt" then args[4]=args[4] or "RIGHT" end
        for i=1,widget:GetNumPoints() do
            local point,relative,anchor,x,y=widget:GetPoint(i)
            points[i]={point,ids[relative],anchor,x,y}
        end
        out[#out+1]={kind=entry.kind,label=entry.label,args=args,points=points,
            width=widget:GetWidth(),height=widget:GetHeight(),shown=widget:IsShown(),enabled=widget:IsEnabled()}
    end
    return out
end
local function Input(h,w,kind,value)
    if kind=="toggle" then
        w:SetChecked(value)
        w:Click()
    elseif kind=="slider" then
        w:SetValue(value)
        MenuWorld.FireScript(w,"OnValueChanged",value)
    elseif kind=="dropdown" then w._msuf2OnValueChanged(value)
    elseif kind=="textinput" or kind=="editbox" then
        w:SetText(value)
        MenuWorld.FireScript(w,"OnTextChanged",true)
        if w._msuf2OnCommit then w._msuf2OnCommit(value) end
        MenuWorld.FireScript(w,"OnEditFocusLost")
    elseif kind=="button" then w:Click() end
    h:RunTimers()
end
local exercised=0
for _,edge in ipairs({false,true}) do
    local old,new=Open(true,edge),Open(false,edge)
    for _,page in ipairs({"gameplay","modules","profiles"}) do
        old:Build(page)
        new:Build(page)
        Same(Inventory(old,page),Inventory(new,page),page.." inventory "..tostring(edge))
        Same(NativeInventory(old),NativeInventory(new),page.." native labels/layout/order "..tostring(edge))
        Same(State(old),State(new),page.." initial "..tostring(edge))
        -- Fix the initial record set. Rebuilds retain the same real command owners.
        local records=Inventory(old,page)
        local owners={}
        for _,r in ipairs(records) do
            owners[r.id]={old.M.RuntimeControlCatalog.Get(r.id).widget,new.M.RuntimeControlCatalog.Get(r.id).widget}
        end
        print(page.." "..tostring(edge).." replay "..string.format("%.2fs",os.clock()-started))
        for _,r in ipairs(records) do
            local a,b=unpack(owners[r.id])
            local kind,value=r.kind
            if kind=="toggle" then value=not Read(a,kind)
            elseif kind=="slider" then
                local low,high=a:GetMinMaxValues()
                value=edge and high or low
                if value==Read(a,kind) then value=math.min(high,low+(a.valueStep or 1)) end
            elseif kind=="dropdown" then
                local values=a.GetValues and a:GetValues() or a.values
                if type(values)=="function" then values=values() end
                if type(values)=="table" then
                    for _,choice in ipairs(values) do
                        if choice.value~=Read(a,kind) then
                            value=choice.value
                            break
                        end
                    end
                end
            elseif kind=="editbox" or kind=="textinput" then value=edge and "Edge profile" or "Draft"
            end
            if value~=nil or kind=="button" then
                -- First test the event-latched combat edge, then real ordinary input.
                old.M.ClearHistory()
                new.M.ClearHistory()
                old.core.Util.InCombat("PLAYER_REGEN_DISABLED")
                new.core.Util.InCombat("PLAYER_REGEN_DISABLED")
                Input(old,a,kind,value)
                Input(new,b,kind,value)
                Same(State(old),State(new),r.id.." combat")
                Same(old.M.Undo(),new.M.Undo(),r.id.." combat history")
                old.core.Util.InCombat("PLAYER_REGEN_ENABLED")
                new.core.Util.InCombat("PLAYER_REGEN_ENABLED")
                old.M.ClearHistory()
                new.M.ClearHistory()
                Input(old,a,kind,value)
                Input(new,b,kind,value)
                Same(State(old),State(new),r.id.." input")
                Same(Read(a,kind),Read(b,kind),r.id.." repaint")
                Same(old.M.Undo(),new.M.Undo(),r.id.." undo")
                Same(State(old),State(new),r.id.." undo state")
                Same(old.M.Redo(),new.M.Redo(),r.id.." redo")
                Same(State(old),State(new),r.id.." redo state")
                exercised=exercised+1
            end
        end
    end
    -- The cleanup list is a native custom owner outside the page catalog.
    for _,h in ipairs({old,new}) do h.M.ProfileCleanup.Open(function() end) end
    local function Cleanup(h)
        local out={}
        for _,entry in ipairs(h.native) do
            local widget=entry.widget
            if widget._msuf2ProfileName then
                out[#out+1]={name=widget._msuf2ProfileName,locked=widget._msuf2Locked,enabled=widget:IsEnabled()}
                widget:Click()
            end
        end
        return out
    end
    Same(Cleanup(old),Cleanup(new),"cleanup selection")
    Same(State(old),State(new),"cleanup state")
    local function Footer(h,label)
        for i=#h.native,1,-1 do
            local entry=h.native[i]
            if entry.kind=="Button" and entry.label==label then
                entry.widget:Click()
                h:RunTimers()
                return entry.widget:GetParent()
            end
        end
        error("cleanup button missing: "..label)
    end
    local function FooterState(panel)
        return {shown=panel:IsShown(),label=panel._deleteBtn._msuf2Label:GetText(),enabled=panel._deleteBtn:IsEnabled()}
    end
    for _,label in ipairs({"Clear selection","Select unused","Delete selected (%d)"}) do
        Same(FooterState(Footer(old,label)),FooterState(Footer(new,label)),"cleanup "..label)
        Same(State(old),State(new),"cleanup "..label.." state")
    end
    assert(old.accept and new.accept,"cleanup did not offer confirmation")
    old.accept()
    new.accept()
    old:RunTimers()
    new:RunTimers()
    Same(State(old),State(new),"cleanup confirmed deletion")
    local footerIds = {}
    for _, entry in ipairs(new.native) do
        local spec = entry.widget._msuf2ControlSchema
        if spec and spec.id:match("^profilecleanup%.") and spec.kind == "button" then
            assert(not footerIds[spec.id], "duplicate cleanup button declaration: " .. spec.id)
            footerIds[spec.id] = true
        end
    end
    for _, key in ipairs({ "close", "selectUnused", "clearSelection", "deleteSelected" }) do
        assert(footerIds["profilecleanup." .. key], "missing cleanup declaration: " .. key)
    end
    Same(FooterState(Footer(old,"x")),FooterState(Footer(new,"x")),"cleanup close")
    -- Rebuild at the narrow width with absent settings, preserving all existing replay assertions.
    for _, h in ipairs({old,new}) do
        h.M.formContentMaxWidth = 420
        for key in pairs(h.env.MSUF_DB.gameplay) do h.env.MSUF_DB.gameplay[key] = nil end
        h.native = {}
    end
    for _, page in ipairs({"gameplay","modules","profiles"}) do
        old.M.InvalidatePage(page)
        new.M.InvalidatePage(page)
        old:Build(page)
        new:Build(page)
        Same(Inventory(old,page),Inventory(new,page),page.." narrow absent-key inventory")
        Same(NativeInventory(old),NativeInventory(new),page.." narrow absent-key layout")
        Same(State(old),State(new),page.." narrow absent-key state")
    end
    local cardIds = {}
    for _, entry in ipairs(new.native) do
        local spec = entry.widget._msuf2ControlSchema
        if spec and spec.id:match("^advancedprofiles%.specialization%.") then
            assert(not cardIds[spec.id], "duplicate specialization card declaration: " .. spec.id)
            cardIds[spec.id] = true
        end
    end
    for _, entry in ipairs(new.M.GetProfileSpecializations()) do
        assert(cardIds["advancedprofiles.specialization." .. entry.id .. ".card"], "missing specialization card")
    end
end
local function NativeToggleSetter()
    local h = Open(false,false)
    h:Build("profiles")
    local id = "menu2.profiles.advanced.export.unit.player"
    local widget = assert(h.M.RuntimeControlCatalog.Get(id)).widget
    local declaration = assert(widget._msuf2ControlSchema)
    local click, calls = widget.Click, 0
    -- The shared harness dispatches scripts only. Model the engine's CheckButton flip here.
    widget.Click = function(self, ...)
        if not self:IsEnabled() then return end
        self:SetChecked(not self:GetChecked())
        return click(self, ...)
    end
    widget:HookScript("OnClick", function() calls = calls + 1 end)
    for _, value in ipairs({false,true,true,false,false,true}) do
        local changed = widget:GetChecked() ~= value
        local before = calls
        declaration.set(value)
        assert(widget:GetChecked() == value, "native toggle setter inverted the requested value")
        assert(h.M.profileExportUnits.player == value, "native toggle setter missed the current owner")
        assert(calls == before + (changed and 1 or 0), "native toggle setter lost or repeated click hooks")
    end
    widget:Disable()
    local before, checked = calls, widget:GetChecked()
    declaration.set(not checked)
    assert(calls == before and widget:GetChecked() == checked, "disabled native toggle accepted input")
    print("PASS native CheckButton declaration setter and late hooks")
end
NativeToggleSetter()
assert(exercised>100,"too few controls replayed: "..exercised)
print("menu_advprofiles_parity_smoke: OK ("..flavor..", "..exercised.." inputs plus combat/undo/redo, "
    ..string.format("%.2fs",os.clock()-started)..")")
