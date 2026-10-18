-- Replay the immutable batch parent and current pages through real menu input owners.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local candidate = arg[3]
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local names = { "ResourceExtras", "SwingTimers" }
local parents = {}
local null = package.config:sub(1,1) == "\\" and "NUL" or "/dev/null"
os.execute('mkdir "' .. root .. '/.checks" 2>' .. null)
for _, name in ipairs(names) do
    local path = "MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_" .. name .. ".lua"
    local pipe = assert(io.popen('git -C "' .. root .. '" show e48e595c3eef2009f5f4933ec5cf9303c36bed96:' .. path, "r"))
    local source = pipe:read("*a")
    pipe:close()
    assert(#source > 100, "cannot read immutable parent " .. path)
    parents[name] = root .. "/.checks/parent-" .. name .. "-" .. flavor .. ".lua"
    local file = assert(io.open(parents[name], "wb"))
    file:write(source)
    file:close()
end
local function Encode(value)
    if type(value) == "function" then return "function" end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = Encode(key) .. "=" .. Encode(value[key]) end
    return "{" .. table.concat(out, ";") .. "}"
end
local function Replay(parent)
    local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
        world.env.GetSpecialization = function() return 1 end
        world.env.GetSpecializationInfo = function() return 62 end
        world.env.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
            GetSpecializationInfo = function() return 62 end }
        world.widgets.Methods.GetCenter = function() return 0, 0 end
        local load = world.LoadFile
        world.LoadFile = function(self, path, ...)
            local name = path:match("MSUF_Menu2_(%w+)%.lua$")
            if parents[name] then
                if parent then path = parents[name]
                elseif candidate and candidate:find(name, 1, true) then path = candidate end
            end
            return load(self, path, ...)
        end
    end })
    local M, core, env = mw.M, mw.core, mw.env
    local narrowWidth
    local pageBuilder = M.Widgets.PageBuilder
    M.Widgets.PageBuilder = function(ctx, opts)
        if narrowWidth then ctx.width = narrowWidth end
        return pageBuilder(ctx, opts)
    end
    local F, lines, counters = core.ProfileFields, {}, {}
    local tips = {}
    env.GameTooltip.SetOwner = function(_, _, anchor) tips[#tips + 1] = { "owner", anchor } end
    for _, name in ipairs({ "SetText", "AddLine", "Show", "Hide" }) do
        env.GameTooltip[name] = function(_, ...) tips[#tips + 1] = { name, ... } end
    end
    core.ProfileRuntime.Apply = function() end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_UFCore_NotifyConfigChanged = function() end
    local function Count(owner, key)
        local original = assert(owner[key], key)
        owner[key] = function(...)
            counters[key] = (counters[key] or 0) + 1
            return original(...)
        end
    end
    Count(M, "Refresh")
    Count(M, "RequestRefresh")
    Count(M.ApplyService, "RequestClassPowerDomains")
    Count(M, "RequestGeneralDomains")
    if core.SwingTimer then Count(core.SwingTimer, "Set") end
    local function Row(id, phase, value) lines[#lines + 1] = id .. " " .. phase .. " " .. Encode(value) end
    local function DB() return { bars = env.MSUF_DB.bars, swingTimers = env.MSUF_DB.swingTimers } end
    local function Expand(page)
        for _, section in pairs(M.cache[page].sections) do
            local entry = section._msuf2CollapsibleEntry
            if entry then entry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
        M.Refresh(M.cache[page].ctx)
    end
    local function Wanted(r, page)
        if r.pageKey ~= page then return false end
        if page == "swingtimers" then return true end
        return r.controlId:find("resource.extras", 1, true) ~= nil
    end
    local function Value(w, kind)
        local c = w._msuf2CommandAction
        if kind == "color" and c and c.get then return { c.get() } end
        if c and c.get then return c.get() end
    end
    local function Search(w)
        local meta = w._msuf2SearchMeta or {}
        return { label=meta.label, stable=w._msuf2StableSearchLabel, kind=meta.kind, prepare=meta.searchPrepareKind,
            value=meta.searchPrepareValue, exact=meta.prepareExactSearchTarget ~= nil }
    end
    local function Input(w, kind, value)
        if kind == "toggle" then w:SetChecked(value) w:Click("LeftButton")
        elseif kind == "slider" then w:SetValue(value) MenuWorld.FireScript(w, "OnValueChanged", value)
        elseif kind == "dropdown" then w._msuf2OnValueChanged(value)
        elseif kind == "textinput" then w._msuf2OnCommit(value)
        elseif kind == "color" then w._msuf2OnColorChanged(unpack(value))
        elseif kind == "segment" then
            local hit
            for _, button in ipairs(w.buttons or {}) do
                if button._msuf2Value == value then button:Click("LeftButton") hit = true break end
            end
            assert(hit, "segment native button missing")
        elseif kind == "button" then w:Click("LeftButton")
        else error("unhandled control " .. tostring(kind)) end
        mw:RunTimers()
    end
    local function Values(w)
        local values = w.GetValues and w:GetValues() or w.values or w._msuf2Values or w.items
        return type(values) == "function" and values() or values
    end
    local function Next(w, kind, state)
        if kind == "toggle" then return not Value(w, kind) end
        if kind == "slider" then
            local lo, hi = w:GetMinMaxValues()
            return state == 1 and math.min(hi, lo + (w.valueStep or 1) * 3) or hi
        end
        if kind == "dropdown" or kind == "segment" then
            local values = assert(Values(w), "missing choices")
            local current = Value(w, kind)
            for i = #values, 1, -1 do
                local item = values[i]
                if not item.disabled and item.value ~= current then return item.value end
            end
            return values[1].value
        end
        if kind == "textinput" then return state == 1 and "  Test attack  " or "" end
        if kind == "color" then return state == 1 and { .21, .32, .43 } or { .65, .54, .43 } end
    end
    local total = 0
    local function Records(page)
        local records = {}
        for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            if Wanted(r, page) then records[#records + 1] = r end
        end
        if page == "swingtimers" then
            records[#records + 1] = { controlId="menu2.swingtimers.swing.copy.button", kind="button", label="Copy To",
                controlPath="copy.button", widget=core.SwingTimer.menuContext._msuf2SwingTimerPreview.copyButton }
        end
        assert(#records > 0, "no controls replayed on " .. page)
        table.sort(records, function(a, b) return a.controlId < b.controlId end)
        return records
    end
    local function Inventory(id, r, w, kind)
        local values, lo, hi = Values(w)
        if kind == "slider" then lo, hi = w:GetMinMaxValues() end
        local point, _, relative, x, y = w:GetPoint()
        tips = {}
        MenuWorld.FireScript(w,"OnEnter")
        MenuWorld.FireScript(w,"OnLeave")
        Row(id, "inventory", { kind=kind, label=r.label, key=r.settingKey, path=r.controlPath,
            classification=r.classification, search=r.searchSettingKeys, identity=Search(w), values=values,
            lo=lo, hi=hi, step=w.valueStep, width=w:GetWidth(), height=w:GetHeight(),
            point=point, relative=relative, x=x, y=y, value=Value(w,kind), enabled=w:IsEnabled(), shown=w:IsShown(),
            tips=tips })
    end
    local function Exercise(page, state)
        local ctx = M.cache[page].ctx
        local records = Records(page)
        local base = F.CopySnapshot(DB())
        for _, r in ipairs(records) do
            local w = r.widget or assert(M.RuntimeControlCatalog.Get(r.controlId).widget)
            local id, kind = r.controlId .. ":" .. state, r.kind
            env.MSUF_DB.bars, env.MSUF_DB.swingTimers = F.CopySnapshot(base.bars), F.CopySnapshot(base.swingTimers)
            if page == "swingtimers" then
                core.SwingTimer.menuContext._msuf2SwingTimerPreview.SelectHand(r.controlId:match("%.swing%.(%w+)%.") or "main")
            end
            M.Refresh(ctx)
            mw:RunTimers()
            if state == 2 and kind ~= "button" then Input(w, kind, Next(w,kind,1)) end
            Inventory(id, r, w, kind)
            local value = Next(w, kind, state)
            M.ClearHistory()
            counters = {}
            Input(w, kind, value)
            Row(id, "input", { db=DB(), counts=counters, value=Value(w,kind), enabled=w:IsEnabled(), identity=Search(w) })
            M.Refresh(ctx)
            Row(id, "refresh", { db=DB(), counts=counters, value=Value(w,kind), enabled=w:IsEnabled() })
            Row(id, "undo", { result=M.Undo() and true or false, db=F.CopySnapshot(DB()) })
            Row(id, "redo", { result=M.Redo() and true or false, db=F.CopySnapshot(DB()) })
            M.ClearHistory()
            core.Util.InCombat("PLAYER_REGEN_DISABLED")
            env.InCombatLockdown = function() return false end
            counters = {}
            Input(w, kind, Next(w,kind,state == 1 and 2 or 1))
            Row(id, "combat", { db=DB(), counts=counters, undo=M.Undo() and true or false })
            core.Util.InCombat("PLAYER_REGEN_ENABLED")
            total = total + 1
        end
        env.MSUF_DB.bars, env.MSUF_DB.swingTimers = F.CopySnapshot(base.bars), F.CopySnapshot(base.swingTimers)
    end
    assert(mw:Select("classpower"))
    M.ClassPowerWorkspace.current:Select("extras")
    Expand("classpower")
    for state = 1, 2 do
        if state == 2 then
            local rules = { (F.CopySnapshot(M.ControlSchema.MarkDefaults)), (F.CopySnapshot(M.ControlSchema.MarkDefaults)) }
            rules[2].mode, rules[2].target, rules[2].resource, rules[2].value = "ABSOLUTE", "ALTMANA", "MANA", 1234
            rules[2].mark, rules[2].threshold = false, true
            env.MSUF_DB.bars.resourceMarks = rules
            M.RuntimeControlCatalog.Get("menu2.classpower.advanced.resource.extras.marks.select").widget._msuf2OnValueChanged(2)
        end
        Exercise("classpower",state)
        assert(mw:Select("opt_colors"))
        local resolve = M.GetMissingSectionResolver(M.cache.opt_colors)
        assert(resolve("colors_resource_extras"))
        assert(resolve("colors_resource_marks"))
        Exercise("opt_colors",state)
        mw:Select("classpower")
        M.ClassPowerWorkspace.current:Select("extras")
    end
    if M.pages.swingtimers then
        assert(mw:Select("swingtimers"))
        Expand("swingtimers")
        core.SwingTimer.menuContext._msuf2SwingTimerPreview.copyButton:Click("LeftButton")
        mw:RunTimers()
        for state = 1, 2 do
            if state == 2 then
                for _, hand in ipairs({ "main", "off", "ranged" }) do
                    core.SwingTimer.Set(hand,"width",411)
                    core.SwingTimer.Set(hand,"display","text")
                    core.SwingTimer.Set(hand,"enabled",true)
                end
            end
            Exercise("swingtimers",state)
        end
    else Row("swingtimers", "absent", true) end
    -- A narrow page builds the one-column layouts, whose geometry and search identity must match too.
    M.formContentMaxWidth, narrowWidth = 420, 456
    M.InvalidatePage("classpower")
    assert(mw:Select("classpower"))
    M.ClassPowerWorkspace.current:Select("extras")
    Expand("classpower")
    for _, r in ipairs(Records("classpower")) do
        Inventory(r.controlId .. ":narrow", r, r.widget or assert(M.RuntimeControlCatalog.Get(r.controlId).widget), r.kind)
    end
    if M.pages.swingtimers then
        M.InvalidatePage("swingtimers")
        assert(mw:Select("swingtimers"))
        Expand("swingtimers")
        for _, r in ipairs(Records("swingtimers")) do
            Inventory(r.controlId .. ":narrow", r, r.widget or assert(M.RuntimeControlCatalog.Get(r.controlId).widget), r.kind)
        end
    end
    M.formContentMaxWidth, narrowWidth = nil, nil
    assert(total >= 24, "empty resource control replay")
    return lines, total
end
local before = Replay(true)
local after, count = Replay(false)
assert(#before == #after, "parent control count drift " .. #before .. " -> " .. #after)
for i = 1, #before do
    if before[i] ~= after[i] then
        local file = assert(io.open(root .. "/.checks/resources-parity-diff-" .. flavor .. ".txt", "wb"))
        file:write("PARENT\n",before[i],"\nCURRENT\n",after[i],"\n") file:close()
        error("parent parity drift at " .. after[i]:sub(1,180) .. "; see .checks/resources-parity-diff-" .. flavor .. ".txt")
    end
end
print("menu_resources_parity_smoke " .. flavor .. ": " .. count .. " controls/states; input/DB/apply/refresh/history/combat match parent")
