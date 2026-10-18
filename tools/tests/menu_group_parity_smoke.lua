-- Lean real-menu replay against the immutable parent, one default and one edge state.
-- Offline control/layout observations do not establish native rendering or taint.
local root, flavor = assert(arg[1]):gsub("\\", "/"):gsub("/$", ""), arg[2] or "Mainline"
local target = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua"
local parent = "1b1e8a4201b63a1b8b1cbef5bf6aa7a79ba1a13b"
local scratch = root .. "/.checks/group-parent-" .. flavor .. ".lua"
local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. parent, "r"))
local original = pipe:read("*a")
pipe:close()
assert(original:find("function GroupPage.BuildPortrait", 1, true), "immutable parent unavailable")
if package.config:sub(1,1) == "\\" then
    os.execute('if not exist "' .. root .. '/.checks" mkdir "' .. root .. '/.checks"')
else
    os.execute('mkdir -p "' .. root .. '/.checks"')
end
local file = assert(io.open(scratch, "wb"))
file:write(original)
file:close()
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Pack(...) return { n = select("#", ...), ... } end
local function Encode(value, ids, seen)
    if type(value) == "function" then return "<function>" end
    -- Catalog revision strings include VM table addresses, not persisted identity.
    if type(value) == "string" then return "string:" .. value:gsub("table: %x+", "table:<address>") end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    if value.GetObjectType then return "widget:" .. tostring(ids[value] or "external") end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key, ids) .. "=" .. Encode(value[key], ids, seen) end
    seen[value] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Replay(source, candidate)
    local rows, ids, calls, refreshes, tips = {}, {}, {}, 0, {}
    local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
        beforeCore = function(world)
            local load = world.LoadFile
            world.LoadFile = function(self, path, ...)
                if source and path:sub(-#target) == target then path = source end
                return load(self, path, ...)
            end
        end })
    local M, env, core = mw.M, mw.env, mw.core
    local GP, F = M.GroupPage, core.ProfileFields
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local factory = F.CopySnapshot(env.MSUF_DB)
    core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
    local function Add(tag, ...)
        rows[#rows + 1] = tag .. "\t" .. Encode(Pack(...), ids)
    end
    local function Diff(a,b,path,out)
        path, out = path or "", out or {}
        if type(a) == "table" and type(b) == "table" then
            local keys = {}
            for key in pairs(a) do keys[key] = true end
            for key in pairs(b) do keys[key] = true end
            for key in pairs(keys) do Diff(a[key],b[key],path .. "." .. tostring(key),out) end
        elseif Encode(a,ids) ~= Encode(b,ids) then out[path] = { Encode(a,ids), Encode(b,ids) } end
        return out
    end
    local function Command(w) return w._msuf2CommandAction or w._msuf2RuntimeControlRecord.command end
    local function Input(w,value)
        local kind = Command(w).kind
        if kind == "color" then w._msuf2OnColorChanged(unpack(value))
        elseif kind == "toggle" then
            w:SetChecked(value)
            w:Click("LeftButton")
        elseif w.buttons then
            for _,button in ipairs(w.buttons) do if button._msuf2Value == value then button:Click("LeftButton") end end
        elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
        else
            w:SetValue(value)
            World.FireScript(w,"OnValueChanged",value)
        end
        mw:RunTimers()
    end
    for _, scope in ipairs({"party","raid","mythicraid"}) do GP.Conf(scope).enabled = true end
    M.gfScope = "party"
    assert(mw:Select("gf_layout"))
    local entry = M.cache.gf_layout
    local section = assert(entry.sections.portrait)
    section._msuf2CollapsibleEntry.SetOpenImmediate(true)
    mw:RunTimers()
    local controls = {}
    for _,record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local w = M.RuntimeControlCatalog.Get(record.controlId).widget
        if record.pageKey == "gf_layout" and record.controlId:find(".group.portrait.",1,true)
            and w and Command(w) and Command(w).get and Command(w).set then
            controls[#controls + 1] = w
        end
    end
    assert(#controls == 30, "Portrait control inventory changed: " .. #controls)
    -- Exercise the shared constructors with full metadata and input-time scope changes.
    local host = env.CreateFrame("Frame",nil,entry.frame)
    host._msuf2Width = 720
    controls[#controls + 1] = GP.ScopeDropdown(entry.ctx,host,"Growth",GP.GROWTH_VALUES,220,"growth","DOWN","geometry",16,-40,220,"LEFT")
    controls[#controls + 1] = GP.ScopeSlider(entry.ctx,host,"Width",20,400,1,280,"width",100,"geometry",16,-100,280,"CENTER")
    controls[#controls + 1] = GP.ScopeColor(entry.ctx,host,"Border color",220,"groupBorderR","groupBorderG","groupBorderB",{0,0.5,1},"color",16,-160,220,"LEFT")
    -- The live sorting card omits these optional headings, so exercise their
    -- constructor branch explicitly alongside the existing scope constructors.
    GP.BuildRoleOrderRows(entry.ctx, host, {
        title = "Role Priority", hint = "Drag roles to reorder.",
        x = 16, y = -220, width = 220, advanceCursor = false,
    })
    table.sort(controls,function(a,b) return a._msuf2RuntimeControlRecord.controlId < b._msuf2RuntimeControlRecord.controlId end)
    if candidate then
        for _,w in ipairs(controls) do assert(w._msuf2ControlSchema,"control lacks schema: " .. w._msuf2RuntimeControlRecord.controlId) end
    end
    local serial = 0
    local function Index(w)
        if not ids[w] then
            serial = serial + 1
            ids[w] = serial
        end
        for _,region in ipairs(w.regions or {}) do Index(region) end
    end
    for _,w in ipairs(mw.world.widgets.frames) do Index(w) end
    local function Own(w)
        while w do
            if w == section or w == section._msuf2CollapsibleEntry.header then return true end
            w = w.GetParent and w:GetParent()
        end
    end
    env.GameTooltip.SetOwner = function(_,...) tips[#tips+1] = {"owner",...} end
    env.GameTooltip.SetText = function(_,...) tips[#tips+1] = {"title",...} end
    env.GameTooltip.AddLine = function(_,...) tips[#tips+1] = {"line",...} end
    env.GameTooltip.Show = function() tips[#tips+1] = {"show"} end
    env.GameTooltip.Hide = function() tips[#tips+1] = {"hide"} end
    local function Observe(tag)
        for _,w in ipairs(mw.world.widgets.frames) do
            if Own(w) then
                local points = {}
                for i=1,w:GetNumPoints() do points[i] = Pack(w:GetPoint(i)) end
                Add(tag .. ":layout",w,w:GetParent(),w:GetObjectType(),w.width,w.height,w.text,points,w:IsShown(),w:IsEnabled(),w._msuf2CursorY)
                for _,region in ipairs(w.regions or {}) do
                    local rp = {}
                    for i=1,region:GetNumPoints() do rp[i] = Pack(region:GetPoint(i)) end
                    Add(tag .. ":region",region,region.text,region.width,region.height,rp,region:IsShown())
                end
            end
        end
        for _,w in ipairs(controls) do
            tips = {}
            if w:HasScript("OnEnter") then World.FireScript(w,"OnEnter") end
            if w:HasScript("OnLeave") then World.FireScript(w,"OnLeave") end
            local low,high = w:GetMinMaxValues()
            Add(tag .. ":control",w._msuf2RuntimeControlRecord,w._msuf2SearchMeta,w._msuf2SearchText,
                low,high,w.valueStep,w.GetValues and w:GetValues() or w.values,Pack(Command(w).get()),tips)
        end
    end
    local refresh = M.Refresh
    M.Refresh = function(...)
        refreshes = refreshes + 1
        return refresh(...)
    end
    for name,fn in pairs(M.ApplyService) do
        if type(fn) == "function" then
            M.ApplyService[name] = function(...)
                calls[#calls+1] = {name,...}
                return fn(...)
            end
        end
    end
    local function Gates()
        local out = {}
        for _,w in ipairs(controls) do out[w._msuf2RuntimeControlRecord.controlId] = {w:IsShown(),w:IsEnabled()} end
        return out
    end
    local conf = GP.Conf("party")
    local defaults = F.CopySnapshot(conf)
    local function Setup(state,w)
        conf = GP.Conf("party")
        for key in pairs(conf) do conf[key] = nil end
        for key,value in pairs(F.CopySnapshot(defaults)) do conf[key] = value end
        M.gfScope = state == "default" and "party" or "raid"
        if state == "edge" then
            conf.portraitMode,conf.portraitRender = "RIGHT","2D"
            conf.portraitBgEnabled,conf.portraitBgColorR,conf.portraitBgColorA = true,0,0
            conf.portraitClickable,conf.portraitSizeMode = false,"SEPARATE"
            conf.portraitBorderStyle,conf.portraitBorderArt = "SOLID","RELIEF"
            conf.portraitPlacement = "DETACHED"
            local id = w and w._msuf2RuntimeControlRecord.controlId or ""
            if id:find("position$",1) then conf.portraitPlacement = "ATTACHED" end
            if id:find("portraitsizeoverride",1,true) then conf.portraitSizeMode = "UNIFORM" end
            if id:find("portraitclassstyle",1,true) then conf.portraitRender = "CLASS" end
            if id:find("portraitoverlaya",1,true) then conf.portraitPlacement = "OVERLAY" end
            if id:find("portraitedgesoftness",1,true) then conf.portraitBorderStyle = "NONE" end
            if id:find("portraitfillborder",1,true) then conf.portraitBorderArt = "FLAT" end
        end
        M.Refresh(entry.ctx)
        mw:RunTimers()
        M.ClearHistory()
    end
    local function Value(w,alternate)
        local cmd,kind = Command(w),Command(w).kind
        local old = cmd.get()
        if kind == "toggle" then return not old end
        if kind == "color" then return alternate and {0.8,0.2,0} or {0,0.25,1} end
        if kind == "slider" then
            local lo,hi = w:GetMinMaxValues()
            if w.valueStep and w.valueStep < 1 then return old == 0.35 and 0.65 or 0.35 end
            return old == hi and lo or hi
        end
        local values = w.GetValues and w:GetValues() or w.values
        if type(values) == "function" then values = values() end
        for i = #values,1,-1 do
            local v = values[i].value or values[i][1]
            if v ~= old then return v end
        end
        return old
    end
    for _,state in ipairs({"default","edge"}) do
        Setup(state)
        Observe(state)
        for _,w in ipairs(controls) do
            Setup(state,w)
            local id = state .. ":" .. w._msuf2RuntimeControlRecord.controlId
            local before = F.CopySnapshot(env.MSUF_DB)
            local value = Value(w)
            calls,refreshes = {},0
            Input(w,value)
            local after = F.CopySnapshot(env.MSUF_DB)
            Add(id .. ":input",value,Diff(before,after),Pack(Command(w).get()),calls,refreshes,Gates())
            local undo = M.Undo()
            mw:RunTimers()
            Add(id .. ":undo",undo,Diff(before,env.MSUF_DB),Pack(Command(w).get()))
            local redo = M.Redo()
            mw:RunTimers()
            Add(id .. ":redo",redo,Diff(after,env.MSUF_DB),Pack(Command(w).get()))
            Setup(state,w)
            before = F.CopySnapshot(env.MSUF_DB)
            core.Util.InCombat("PLAYER_REGEN_DISABLED")
            env.InCombatLockdown = function() return true end
            calls,refreshes = {},0
            Input(w,value)
            Add(id .. ":combat",Diff(before,env.MSUF_DB),Pack(Command(w).get()),calls,refreshes,M.Undo())
            core.Util.InCombat("PLAYER_REGEN_ENABLED")
            env.InCombatLockdown = function() return false end
            mw:Fire("PLAYER_REGEN_ENABLED")
            mw:RunTimers()
        end
    end
    -- Warm tab/scope lifecycle, Copy To and retained composite owners.
    for _,tab in ipairs({"general","placement","geometry","border","advanced"}) do
        section._msuf2GuidedSelectTab(tab)
        mw:RunTimers()
        Add("tab",tab,Gates(),section:GetHeight())
    end
    for _,scope in ipairs({"raid","party"}) do
        M.gfScope = scope
        M.Refresh(entry.ctx)
        mw:RunTimers()
        Add("scope",scope,section._msuf2CollapsibleEntry.outer:IsShown(),section:GetHeight())
    end
    local before = F.CopySnapshot(env.MSUF_DB)
    Add("copy",GP.CopyGroupSettings("party","raid",GP.NewGFCopyScopes()),Diff(before,env.MSUF_DB))
    mw:Select("home")
    mw:Select("gf_layout")
    M.Refresh(entry.ctx)
    mw:RunTimers()
    Add("reopen",Gates())
    -- Replay the remaining Group chrome in the same worlds. Observe each live
    -- page subtree once, rather than repeatedly serializing unrelated menu pages.
    local function Under(w, top)
        while w do
            if w == top or w._msuf2PageOwnerWrapper == top then return true end
            w = w.GetParent and w:GetParent()
        end
        return false
    end
    local declaredChrome = {}
    local function ChromeLayout(tag, top, first)
        for _, w in ipairs(mw.world.widgets.frames) do Index(w) end
        for i = first or 1, #mw.world.widgets.frames do
            local w = mw.world.widgets.frames[i]
            if not top or Under(w, top) then
                local points = {}
                for p = 1, w:GetNumPoints() do points[p] = Pack(w:GetPoint(p)) end
                Add(tag .. ":layout", w, w:GetParent(), w:GetObjectType(), w.width, w.height,
                    w.text, points, w:IsShown(), w:IsEnabled(), w._msuf2CursorY)
                for _, region in ipairs(w.regions or {}) do
                    local rp = {}
                    for p = 1, region:GetNumPoints() do rp[p] = Pack(region:GetPoint(p)) end
                    Add(tag .. ":region", region, region.text, region.width, region.height,
                        rp, region:IsShown(), region.justifyH, region.font)
                    local spec = region._msuf2ControlSchema
                    if spec then declaredChrome[spec.id] = true end
                end
                local spec = w._msuf2ControlSchema
                if spec then declaredChrome[spec.id] = true end
            end
        end
    end
    local function Records(tag, page)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if record.pageKey == page then
                local w = M.RuntimeControlCatalog.Get(record.controlId).widget
                local cmd = w and Command(w)
                Add(tag .. ":record", record, w and w._msuf2SearchMeta, w and w._msuf2SearchText,
                    cmd and cmd.get and Pack(cmd.get()))
            end
        end
    end
    local function Find(page, suffix)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if record.pageKey == page and record.controlId:sub(-#suffix) == suffix then
                return M.RuntimeControlCatalog.Get(record.controlId).widget
            end
        end
        error("missing chrome: " .. page .. suffix)
    end
    local function ClickValue(bar, value)
        for _, button in ipairs(bar.buttons) do
            if button._msuf2Value == value then
                button:Click("LeftButton")
                mw:RunTimers()
                return
            end
        end
        error("missing selector value: " .. value)
    end
    local function OpenSections(page)
        local current = M.cache[page]
        for _, sec in pairs(current.sections or {}) do
            if sec._msuf2CollapsibleEntry then sec._msuf2CollapsibleEntry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        return current
    end
    ChromeLayout("constructors", host)
    M.gfScope = "party"
    for _, page in ipairs({ "gf_layout", "gf_priority", "gf_bars", "gf_auras", "gf_indicators" }) do
        assert(mw:Select(page), page)
        local current = OpenSections(page)
        ChromeLayout(page, assert(current.wrapper))
        Records(page, page)
    end
    if candidate then
        for _, id in ipairs({ "menu2.gf_priority.group.scope.priority_note", "menu2.gf_layout.group.growth.title",
            "menu2.gf_layout.group.sorting.title", "menu2.gf_layout.group.sorting.hint" }) do
            assert(declaredChrome[id], "unobserved chrome declaration: " .. id)
        end
    end
    assert(mw:Select("gf_layout"))
    local scopes = flavor == "Mainline" and { "raid", "mythicraid", "party" } or { "raid", "party" }
    assert(#Find("gf_layout", ".group.scope.selector").buttons == #scopes, "scope inventory drift")
    for _, value in ipairs(scopes) do
        ClickValue(Find("gf_layout", ".group.scope.selector"), value)
        local current = OpenSections("gf_layout")
        Add("scope-click:" .. value, M.gfScope, Find("gf_layout", ".group.scope.selector"):GetValue())
        assert(M.gfScope == value, "scope selector did not change scope")
        ChromeLayout("scope-click:" .. value, assert(current.wrapper))
    end
    ClickValue(Find("gf_layout", ".group.navigation.section.selector"), "gf_bars")
    Add("page-click", M.activeKey)
    assert(M.activeKey == "gf_bars", "page selector did not navigate")
    assert(mw:Select("gf_layout"))
    local copy = Find("gf_layout", ".group.copy.open")
    if candidate then assert(copy._msuf2ControlSchema.action, "copy opener action is undeclared") end
    local known, popupControls = {}, {}
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do known[record.controlId] = true end
    local firstPopupFrame = #mw.world.widgets.frames + 1
    copy:Click("LeftButton")
    mw:RunTimers()
    for _, w in ipairs(mw.world.widgets.frames) do Index(w) end
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if not known[record.controlId] then
            popupControls[#popupControls + 1] = record.controlId
            local w = M.RuntimeControlCatalog.Get(record.controlId).widget
            Add("copy-popup:record", record, w._msuf2SearchMeta, w:IsShown())
            if candidate then assert(w._msuf2ControlSchema, "undeclared popup control: " .. record.controlId) end
        end
    end
    assert(#popupControls == 15 + #scopes, "copy popup inventory drift: " .. #popupControls)
    Add("copy-popup:count", #popupControls)
    ChromeLayout("copy-popup", nil, firstPopupFrame)
    -- Distinct values make both the copy and its undo observable.
    GP.Conf("party").width, GP.Conf("raid").width = 151, 117
    M.ClearHistory()
    local snapshot = F.CopySnapshot(env.MSUF_DB)
    calls, refreshes = {}, 0
    Find("gf_layout", ".copy.target.raid"):Click("LeftButton")
    mw:RunTimers()
    Add("copy-run", Diff(snapshot, env.MSUF_DB), calls, refreshes)
    assert(GP.Conf("raid").width == 151, "popup did not copy the source width")
    local undo = M.Undo()
    mw:RunTimers()
    Add("copy-undo", undo, Diff(snapshot, env.MSUF_DB))
    assert(undo and GP.Conf("raid").width == 117, "popup copy lost undo")
    local growthCount = 0
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local growthTile = record.controlId:find(".group.field.growth.option.", 1, true)
        local growthTier = record.controlId:match("%.group%.field%.tier%d+growth$")
        if record.pageKey == "gf_layout" and (growthTile or growthTier) then
            local w = M.RuntimeControlCatalog.Get(record.controlId).widget
            if w:GetObjectType() == "Button" and w:HasScript("OnClick") then
                growthCount = growthCount + 1
                for _, initial in ipairs({ "DOWN", "LEFT" }) do
                    GP.Conf("party").growth = initial
                    M.Refresh(M.cache.gf_layout.ctx)
                    mw:RunTimers()
                    M.ClearHistory()
                    snapshot = F.CopySnapshot(env.MSUF_DB)
                    calls, refreshes = {}, 0
                    w:Click("LeftButton")
                    mw:RunTimers()
                    local tag = initial .. ":" .. record.controlId
                    Add("growth:" .. tag, Diff(snapshot, env.MSUF_DB), calls, refreshes)
                    undo = M.Undo()
                    mw:RunTimers()
                    Add("growth-undo:" .. tag, undo, Diff(snapshot, env.MSUF_DB))
                    snapshot = F.CopySnapshot(env.MSUF_DB)
                    core.Util.InCombat("PLAYER_REGEN_DISABLED")
                    env.InCombatLockdown = function() return true end
                    calls, refreshes = {}, 0
                    w:Click("LeftButton")
                    mw:RunTimers()
                    Add("growth-combat:" .. tag, Diff(snapshot, env.MSUF_DB), calls, refreshes, M.Undo())
                    core.Util.InCombat("PLAYER_REGEN_ENABLED")
                    env.InCombatLockdown = function() return false end
                    mw:Fire("PLAYER_REGEN_ENABLED")
                    mw:RunTimers()
                end
            end
        end
    end
    assert(growthCount == 8, "growth control inventory drift: " .. growthCount)
    return rows,#controls
end
local started = os.clock()
local baseline,count = Replay(scratch,false)
local actual = Replay(arg[3],true)
assert(#baseline == #actual,"observation count drift: " .. #baseline .. " / " .. #actual)
for i=1,#baseline do
    if baseline[i] ~= actual[i] then
        local f = assert(io.open(root .. "/.checks/group-parity-diff-" .. flavor .. ".txt","wb"))
        f:write("parent\n",baseline[i],"\ncandidate\n",actual[i],"\n")
        f:close()
        error("Group parity drift at observation " .. i .. " " .. baseline[i]:match("^[^\t]+"))
    end
end
print("menu_group_parity_smoke " .. flavor .. ": " .. count .. " controls, " .. #baseline .. " observations, "
    .. "default/edge input/DB/apply/refresh/history/combat/layout/copy and five-page chrome OK ("
    .. string.format("%.2fs", os.clock() - started) .. ")")
