-- Full-page observations for immutable pre-schema parity receipts.
local root, flavor, width, state = assert(arg[1]), assert(arg[2]), tonumber(arg[3]), assert(arg[4])
root = root:gsub("\\", "/")
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local target = "MSUF_Menu2_GroupIndicators.lua"
-- Optional authentic source directory is used only when capturing baseline receipts.
local proofRoot = arg[5]
local frames, frameIds, calls, tips, rowCount = {}, {}, {}, {}, 0
local output = {}
local function Encode(v, seen)
    if type(v) == "function" then return "<function>" end
    if type(v) ~= "table" then return (type(v) .. ":" .. tostring(v)):gsub("[\r\n\t]", " ") end
    if v.GetObjectType then return "widget:" .. tostring(frameIds[v] or "external") end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a,b) return type(a) .. ":" .. tostring(a) < type(b) .. ":" .. tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = Encode(k) .. "=" .. Encode(v[k], seen) end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Add(...)
    local row = {}
    for i = 1, select("#", ...) do row[i] = Encode((select(i, ...))) end
    output[#output + 1] = table.concat(row, "\t")
    rowCount = rowCount + 1
    if #output == 256 then
        io.write(table.concat(output, "\n"), "\n")
        output = {}
    end
end
local function Index(world)
    local function Include(f)
        if frameIds[f] then return end
        frames[#frames + 1], frameIds[f] = f, #frames + 1
        for _, r in ipairs(f.regions or {}) do Include(r) end
    end
    for _, f in ipairs(world.widgets.frames) do Include(f) end
end
local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
    beforeCore = function(world)
        local load = world.LoadFile
        world.LoadFile = function(self, path, ...)
            if proofRoot then
                if path:sub(-#"MSUF_Menu2_ControlSchema.lua") == "MSUF_Menu2_ControlSchema.lua" then
                    path = proofRoot .. "/main-schema.lua"
                elseif path:sub(-#target) == target then path = proofRoot .. "/main-page.lua" end
            end
            return load(self, path, ...)
        end
        -- The original source genuinely reaches FlipBook animations. Model their
        -- native setters in this fixture and record their ordered inputs.
        for _,name in ipairs({"Rows","Columns","Frames","FrameWidth","FrameHeight"}) do
            local field="flipBook"..name
            world.widgets.Methods["SetFlipBook"..name]=function(f,value)
                f[field]=value
                calls[#calls+1]={"flipbook",field,value}
            end
        end
        world.widgets.Methods.GetCenter = function(f)
            return (tonumber(f.left) or 0) + (tonumber(f.width) or 0)/2,
                (tonumber(f.bottom) or 0) + (tonumber(f.height) or 0)/2
        end
    end })
local M, env, core = mw.M, mw.env, mw.core
local F = core.ProfileFields
local factory = F.CopySnapshot(env.MSUF_DB)
core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
core.ProfileRuntime.Apply = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
env.MSUF_UFCore_NotifyConfigChanged = function() end
local builder = M.Widgets.PageBuilder
M.Widgets.PageBuilder = function(ctx, opts) ctx.width = width return builder(ctx, opts) end
env.GameTooltip.SetOwner = function(_, ...) tips[#tips + 1] = { "owner", ... } end
env.GameTooltip.SetText = function(_, ...) tips[#tips + 1] = { "title", ... } end
env.GameTooltip.AddLine = function(_, ...) tips[#tips + 1] = { "line", ... } end
env.GameTooltip.Show = function() tips[#tips + 1] = { "show" } end
env.GameTooltip.Hide = function() tips[#tips + 1] = { "hide" } end
local preview = false
env.MSUF_SetDispelOverlayPreview = function(v, scope)
    preview = v == true
    env.MSUF_DispelOverlayPreviewMode = preview
    calls[#calls + 1] = { "dispelPreview", v, scope }
end
for name, fn in pairs(M.ApplyService) do
    if type(fn) == "function" then M.ApplyService[name] = function(...)
        calls[#calls + 1] = { name, ... }
        return fn(...)
    end end
end
local function Diff(a,b,path,out)
    path, out = path or "", out or {}
    if type(a) == "table" and type(b) == "table" then
        local keys = {}
        for k in pairs(a) do keys[k] = true end
        for k in pairs(b) do keys[k] = true end
        for k in pairs(keys) do Diff(a[k],b[k],path .. "." .. tostring(k),out) end
    elseif Encode(a) ~= Encode(b) then out[path] = { before = Encode(a), after = Encode(b) } end
    return out
end
local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
local function Input(w,v)
    local cmd = Command(w)
    if cmd.kind == "color" then w._msuf2OnColorChanged(v[1], v[2], v[3])
    elseif cmd.kind == "toggle" then w:SetChecked(v) w:Click("LeftButton")
    elseif w.buttons then
        for _, b in ipairs(w.buttons) do if b._msuf2Value == v then b:Click("LeftButton") end end
    elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(v)
    elseif w._msuf2OnCommit then w._msuf2OnCommit(v)
    else w:SetValue(v) World.FireScript(w,"OnValueChanged",v) end
    mw:RunTimers()
end
local sections = { indicators=true, sicons=true, si=true, ci=true, si_style=true }
local function Own(w,entry)
    while w do
        for id,s in pairs(entry.sections) do
            if sections[id] and (w == s or w == s._msuf2CollapsibleEntry.header) then return id end
        end
        w = w.GetParent and w:GetParent()
    end
end
local function Gates(page)
    local out = {}
    for _,r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local w = M.RuntimeControlCatalog.Get(r.controlId).widget
        if r.pageKey == page and w and Own(w,M.cache[page]) then out[r.controlId] = {w:IsShown(),w:IsEnabled()} end
    end
    return out
end
local function Snapshot(page,scope,tag)
    Index(mw.world)
    local entry = M.cache[page]
    for _,w in ipairs(frames) do
        if Own(w,entry) then
            local points = {}
            for i=1,w:GetNumPoints() do points[#points+1] = {w:GetPoint(i)} end
            Add("layout",scope,page,tag,w,w:GetParent(),w:GetObjectType(),w.width,w.height,w.text,points,
                w.allPoints,w.alpha,w.level,w.texture,w:IsShown(),w:IsEnabled(),w._msuf2CursorY)
        end
    end
    for _,r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local w = M.RuntimeControlCatalog.Get(r.controlId).widget
        if r.pageKey == page and w and Own(w,entry) then
            tips = {}
            if w:HasScript("OnEnter") then World.FireScript(w,"OnEnter") end
            local cmd, low,high = Command(w)
            if r.kind == "slider" then low,high = w:GetMinMaxValues() end
            if w:HasScript("OnLeave") then World.FireScript(w,"OnLeave") end
            Add("control",scope,page,tag,r,w,w._msuf2SearchMeta,low,high,w.valueStep,
                w.GetValues and w:GetValues() or w.values,cmd and cmd.get and cmd.get(),tips)
        end
    end
end
local function Edit(page,scope,w,v)
    local conf = M.GroupPage.Conf(scope)
    conf.enabled = true
    for _,spec in ipairs(M.GroupPage.GF_STATUS_ICON_SPECS) do conf[spec.enabled] = true end
    if page=="gf_auras" then
        M.GroupPage.SpellIndicators(scope).enabled=true
        local cfg=M.GroupPage.CurrentSpellConfig(scope,true)
        if not cfg then
            local registry=M.GroupPage.GF().SpellIndicators
            for _,v in ipairs(M.GroupPage.SpellSpecValues()) do
                local auras=registry.TrackableAuras[v.value]
                if auras and #auras>0 then
                    M.GroupPage.SpellIndicators(scope).spec=v.value
                    M.GroupPage.ClearCurrentSpellAura(scope)
                    cfg=M.GroupPage.CurrentSpellConfig(scope,true)
                    if cfg then break end
                end
            end
        end
        assert(cfg,"selected config lost before edit:"..w._msuf2RuntimeControlRecord.controlId)
        cfg.enabled=true
    else
        conf.ciEnabled=true
    end
    M.Refresh(M.cache[page].ctx)
    M.ClearHistory()
    local before = F.CopySnapshot(env.MSUF_DB)
    calls = {}
    Input(w,v)
    local after = F.CopySnapshot(env.MSUF_DB)
    Add("input",scope,page,w._msuf2RuntimeControlRecord.controlId,v,Diff(before,after),Command(w).get(),calls,Gates(page))
    local undo = M.Undo()
    mw:RunTimers()
    Add("undo",scope,page,w._msuf2RuntimeControlRecord.controlId,undo,Diff(before,env.MSUF_DB),Command(w).get())
    local redo = M.Redo()
    mw:RunTimers()
    Add("redo",scope,page,w._msuf2RuntimeControlRecord.controlId,redo,Diff(after,env.MSUF_DB),Command(w).get())
    M.ClearHistory()
    before = F.CopySnapshot(env.MSUF_DB)
    core.Util.InCombat("PLAYER_REGEN_DISABLED")
    env.InCombatLockdown = function() return false end
    Input(w,v)
    Add("combat-edge",scope,page,w._msuf2RuntimeControlRecord.controlId,Diff(before,env.MSUF_DB),Command(w).get(),M.Undo())
    env.InCombatLockdown = function() return true end
    Input(w,v)
    Add("combat",scope,page,w._msuf2RuntimeControlRecord.controlId,Diff(before,env.MSUF_DB),Command(w).get(),M.Undo())
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    env.InCombatLockdown = function() return false end
    mw:Fire("PLAYER_REGEN_ENABLED")
    mw:RunTimers()
end
for _,scope in ipairs({"party","raid","mythicraid"}) do
    if core.Client.SupportsGroupKind(scope) then
        M.gfScope = scope
        if state ~= "default" then
            for _,kind in ipairs({"party","raid","mythicraid"}) do env.MSUF_DB["gf_"..kind] = {} end
            if state == "general" then
                env.MSUF_DB.general.hidePercentSymbol = true
                env.MSUF_DB.general.dispelOverlayTrigger = "GROUP"
            end
        end
        local selection = "record"
        for _,page in ipairs({"gf_indicators","gf_auras"}) do
            assert(mw:Select(page))
            local entry = M.cache[page]
            local ids = {}
            for id in pairs(entry.sections) do ids[#ids+1] = id end
            table.sort(ids)
            for _,id in ipairs(ids) do
                if sections[id] then entry.sections[id]._msuf2CollapsibleEntry.SetOpenImmediate(true) end
            end
            mw:RunTimers()
            M.GroupPage.Set(scope,"enabled",true,"visual")
            M.Refresh(entry.ctx)
            local gp=M.GroupPage
            if page=="gf_auras" then
                gp.SpellIndicators(scope).enabled=true
                for _,v in ipairs(gp.SpellSpecValues()) do
                    if v.value~="auto" and v.value~="multi" then gp.SpellIndicators(scope).spec=v.value break end
                end
                assert(gp.CurrentSpellConfig(scope,true),"real selected spell absent")
                gp.CurrentSpellConfig(scope,true).enabled=true
                if state=="edge" then
                    gp.SpellIndicators(scope).style={showTooltip=0,showCooldownText=false,showCooldownSwipe=0,
                        showStacks="true",showDurationBar=false,cooldownSize=0,cooldownX=false,stackX=0,stackAnchor=false}
                    local cfg=gp.CurrentSpellConfig(scope,true)
                    cfg.placed=false
                    cfg.frame=false
                    cfg.autoBlacklist=false
                    cfg.onlyOwn=nil
                end
            else
                gp.Set(scope,"ciEnabled",true,"visual")
                gp.Set(scope,"ciSlotTL","custom","visual")
                M.SetMenuStateValue("gfCornerSlotSelection","TL")
                if state == "edge" then
                    local color = gp.CICustomConfig(scope, "TL", true)
                    color.r, color.g, color.b = 0, false, 0
                end
            end
            M.Refresh(entry.ctx)
            Snapshot(page,scope,"open:"..selection)
            M.GroupPage.Set(scope,"enabled",true,"visual")
            M.GroupPage.Set(scope=="party" and "raid" or "party","enabled",true,"visual")
            M.Refresh(entry.ctx)
            local controls = {}
            for _,r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
                local w = M.RuntimeControlCatalog.Get(r.controlId).widget
                local path=r.controlId:lower()
                local target = r.kind == "toggle" or r.kind == "slider" or r.kind == "dropdown"
                    or r.kind == "segment" or r.kind == "textinput" or r.kind == "color"
                if target and r.pageKey == page and w and Own(w,entry) and Command(w) and Command(w).get and Command(w).set then
                    controls[#controls+1] = w
                end
            end
            assert(#controls >= (page == "gf_auras" and 47 or 20), "incomplete whole-page target set "..page..":"..#controls)
            Add("target-count", scope, page, #controls)
            for _,w in ipairs(controls) do
                local r,cmd = w._msuf2RuntimeControlRecord,Command(w)
                if r.kind == "color" then Edit(page,scope,w,{0,0.25,1}) Edit(page,scope,w,{1,0,0})
                elseif r.kind == "toggle" then Edit(page,scope,w,true) Edit(page,scope,w,false)
                elseif r.kind == "slider" then
                    local low,high = w:GetMinMaxValues()
                    Edit(page,scope,w,low) Edit(page,scope,w,high)
                elseif r.kind == "textinput" then Edit(page,scope,w,"12345, 67890") Edit(page,scope,w,"")
                elseif r.kind == "dropdown" or r.kind == "segment" then
                    local values = w.GetValues and w:GetValues() or w.values
                    if type(values) == "function" then values = values() end
                    for _,v in ipairs(values or {}) do Edit(page,scope,w,v.value or v[1]) end
                end
            end
            local previewControl
            for _,w in ipairs(controls) do
                if w._msuf2RuntimeControlRecord.controlId:lower():find("dispeloverlaypreview",1,true) then previewControl=w end
            end
            if previewControl then
                M.GroupPage.Set(scope,"dispelOverlayEnabled",true,"visual")
                M.Refresh(entry.ctx)
                Input(previewControl,true)
                Add("preview-active",scope,preview)
                World.FireScript(previewControl,"OnHide")
                Add("preview-hidden",scope,preview,previewControl:GetChecked())
            end
            for _,id in ipairs(ids) do
                local section = entry.sections[id]
                local actions = sections[id] and section._msuf2CollapsibleEntry._msuf2SectionActions
                if actions then
                    local existing = actions._msuf2GetSectionPopup()
                    if existing and existing:IsShown() then existing:Hide() end
                    actions:Click()
                    local popup = actions._msuf2GetSectionPopup()
                    assert(popup, page .. ": section popup absent " .. id .. " enabled=" .. tostring(actions:IsEnabled()))
                    local reset
                    for _,w in ipairs(mw.world.widgets.frames) do
                        if w:GetParent()==popup and w._msuf2Label and w._msuf2Label:GetText()=="Reset section" then reset=w end
                    end
                    if reset then
                        local before=F.CopySnapshot(env.MSUF_DB)
                        calls={} reset:Click() mw:RunTimers()
                        Add("reset",scope,page,id,Diff(before,env.MSUF_DB),calls)
                        M.Undo() mw:RunTimers()
                        Add("reset-undo",scope,page,id,Diff(before,env.MSUF_DB))
                        M.Redo() mw:RunTimers()
                    end
                    local dest=scope=="party" and "raid" or "party"
                    local before=F.CopySnapshot(env.MSUF_DB)
                    calls={}
                    local copied=popup._msuf2CopySection(dest)
                    mw:RunTimers()
                    Add("copy",scope,page,id,dest,copied,Diff(before,env.MSUF_DB),calls)
                    popup:Hide()
                end
            end
            Snapshot(page,scope,"edited:"..selection)
            mw:Select("home")
        end
    end
end
-- Exercise every real status/spec selection with the existing widgets. The
-- preceding replay covers all input types; these states additionally verify
-- each selected owner, its fields, choices, gates, tooltips and geometry.
for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
    if core.Client.SupportsGroupKind(scope) then
        M.gfScope = scope
        M.GroupPage.Set(scope, "enabled", true, "visual")
        for _, page in ipairs({ "gf_indicators", "gf_auras" }) do
            assert(mw:Select(page))
            local entry, selector = M.cache[page]
            local suffix = page == "gf_indicators" and ".status.selector" or ".spell.spec"
            for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
                if r.pageKey == page and r.controlId:sub(-#suffix) == suffix then
                    assert(not selector, "ambiguous selected-owner control")
                    selector = M.RuntimeControlCatalog.Get(r.controlId).widget
                end
            end
            assert(selector, "selected-owner control missing: " .. suffix)
            local values = selector.GetValues and selector:GetValues() or selector.values
            if type(values) == "function" then values = values() end
            local count = 0
            for _, choice in ipairs(values) do
                local value = choice.value or choice[1]
                if value ~= nil and not choice.disabled and not choice.header then
                    local before = F.CopySnapshot(env.MSUF_DB)
                    calls = {}
                    Input(selector, value)
                    M.Refresh(entry.ctx)
                    count = count + 1
                    Add("selection", scope, page, value, Command(selector).get(),
                        Diff(before, env.MSUF_DB), calls, Gates(page))
                    Snapshot(page, scope, "selection:" .. tostring(value))
                end
            end
            assert(count >= 2, "selected-owner choices were not exercised")
            Add("selection-count", scope, page, count)
            mw:Select("home")
        end
    end
end
if #output > 0 then io.write(table.concat(output, "\n"), "\n") end
io.stderr:write("group parity " .. flavor .. " " .. width .. " " .. state .. " " .. rowCount .. " rows\n")
