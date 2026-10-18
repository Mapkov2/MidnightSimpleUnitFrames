-- Replay all five immutable a178bb7bd batch blobs in the same real-menu harness.
-- Default/edge inputs, rebuilt Party, absent keys, search and 400/1040 layouts
-- compare directly; candidate declarations are structural assertions, with no receipts.
-- Native rendering is modeled; this does not establish live visuals or taint.
local args = ... and { ... } or arg
local root, flavor = assert(args[1]):gsub("\\", "/"):gsub("/$", ""), assert(args[2])
local mode, mutationPage = args[3], args[4]
local parentWorker = mode == "parent-compare" or mode == "parent-review"
assert(not mode or mode == "compare" or mode == "review" or mode == "review-stack" or parentWorker, "unknown replay mode")
local stack = mode == "review-stack"
local mutationFile = mutationPage and mutationPage:gsub("\\", "/"):match("[^/]+$")
local parents = {
    { "GroupLayout", "338b2b51dbdf350a3baf03f90e4757cdeae53321", "-- Menu2 Group Layout page:" },
    { "GroupLayoutAdditional", "effc70829f21fa11c0c84c059d42487c09fe22fa", "-- Additional group units and size-dependent appearance;" },
    { "GroupPriority", "46a025e38266736190ea28bfff888059e82dbdc6", "--- Menu2 Priority Frames page." },
    { "GroupSpecs", "0ec10819957592d904673bc2cbff88bcff8457b9", "-- Group page spec catalogue." },
    { "Group_SpellModel", "4f84b7981622393805a15f159bcabfc17892334d", "-- Menu2 Group page spell/corner indicator model." },
}
if package.config:sub(1, 1) == "\\" then
    os.execute('if not exist "' .. root .. '/.checks" mkdir "' .. root .. '/.checks"')
else
    os.execute('mkdir -p "' .. root .. '/.checks"')
end
local sources = {}
for _, item in ipairs(parents) do
    local pipe = assert(io.popen('git -C "' .. root .. '" show ' .. item[2], "r"))
    local original = pipe:read("*a")
    pipe:close()
    assert(#original > 1000 and original:find(item[3], 1, true), "immutable parent unavailable: " .. item[2])
    local name = "MSUF_Menu2_" .. item[1] .. ".lua"
    local scratch = root .. "/.checks/grouplayout-parent-" .. flavor .. "-" .. name
    local file = assert(io.open(scratch, "wb"))
    file:write(original)
    file:close()
    sources[name] = scratch
end
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Replay(parent, review)
local observations, frames, ids, calls, tips = {}, {}, {}, {}, {}
local scalarCache = { string = {}, boolean = {} }
local function Encode(v, seen)
    local kind = type(v)
    if kind == "function" then return "<function>" end
    if kind ~= "table" then
        if kind == "nil" then return "nil:nil" end
        local cache = scalarCache[kind]
        if cache and cache[v] then return cache[v] end
        -- Runtime catalogue cache keys contain tostring(table) addresses. The
        -- values themselves are recorded below; allocator addresses are not UI state.
        local scalar = tostring(v)
        if kind == "string" and scalar:find("table: ", 1, true) then
            scalar = scalar:gsub("table: 0x%x+", "table:<address>"):gsub("table: %x+", "table:<address>")
        end
        local encoded = (kind .. ":" .. scalar):gsub("[\r\n\t]", " ")
        if cache then cache[v] = encoded end
        return encoded
    end
    if v.GetObjectType then return "widget:" .. tostring(ids[v] or "external") end
    seen = seen or {}
    if seen[v] then return "<cycle>" end
    seen[v] = true
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = Encode(k) .. "=" .. Encode(v[k], seen) end
    seen[v] = nil
    return "{" .. table.concat(out, ",") .. "}"
end
local function Add(tag, ...)
    local row = { tag }
    for i = 1, select("#", ...) do row[#row + 1] = Encode((select(i, ...))) end
    local actual = table.concat(row, "\t")
    observations[#observations + 1] = actual
end
local mw = World.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true,
    beforeCore = function(world)
        local load = world.LoadFile
        world.LoadFile = function(self, path, ...)
            if stack and path:match("/MSUF_Menu2_Group.lua$") then
                path = "C:/tmp/m7/w5p-group/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Group.lua"
            end
            local name = path:match("[^/]+$")
            if parent and sources[name] then path = sources[name]
            elseif not parent and name == mutationFile then path = mutationPage end
            return load(self, path, ...)
        end
        for _, name in ipairs({ "Rows", "Columns", "Frames", "FrameWidth", "FrameHeight" }) do
            local field = "flipBook" .. name
            world.widgets.Methods["SetFlipBook" .. name] = function(f, v) f[field] = v end
        end
        world.widgets.Methods.GetCenter = function(f)
            return (tonumber(f.left) or 0) + (tonumber(f.width) or 0) / 2,
                (tonumber(f.bottom) or 0) + (tonumber(f.height) or 0) / 2
        end
    end })
local M, env, core = mw.M, mw.env, mw.core
local F, GP = core.ProfileFields, M.GroupPage
local ownedRows = {}
if review and not parent then
    local schema, build, label = M.ControlSchema, M.ControlSchema.Build, M.Widgets.LabelAt
    local rowKinds = { switch = "toggle", sectionSwitch = "toggle", flowToggle = "toggle",
        scopebar = "segment", topButton = "button", roleButton = "button" }
    schema.Build = function(ctx, owner, rows, options, refs)
        local controls = build(ctx, owner, rows, options, refs)
        for _, row in ipairs(rows) do ownedRows[assert(controls[row[2]])] = rowKinds[row[1]] or row[1] end
        return controls
    end
    M.Widgets.LabelAt = function(...)
        local widget = label(...)
        local caller = debug.getinfo(2, "S").source:match("[^/\\]+$")
        if sources[caller] then ownedRows[widget] = "font" end
        return widget
    end
end
local function CopyDB()
    local db = env.MSUF_DB
    local snapshot = F.CopySnapshot({ gf_party = db.gf_party, gf_raid = db.gf_raid, gf_mythicraid = db.gf_mythicraid,
        gf_priority = db.gf_priority, general = db.general })
    return snapshot
end
local factory = F.CopySnapshot(env.MSUF_DB)
core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
core.ProfileRuntime.Apply = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
env.MSUF_UFCore_NotifyConfigChanged = function() end
-- The fixture does not instantiate XML parentKey regions for secure additional
-- unit buttons. Record this native rendering boundary after the real apply route.
core.GF.RefreshAdditionalGroups = function(...) calls[#calls + 1] = { "additional-render", ... } end
for name, fn in pairs(M.ApplyService) do
    if type(fn) == "function" then M.ApplyService[name] = function(...)
        calls[#calls + 1] = { name, ... }
        return fn(...)
    end end
end
local refresh = M.Refresh
M.Refresh = function(...) calls[#calls + 1] = { "refresh" } return refresh(...) end
for _, name in ipairs({ "SetOwner", "SetText", "AddLine", "Show", "Hide" }) do
    env.GameTooltip[name] = function(_, ...) tips[#tips + 1] = { name, ... } end
end
local function Index()
    local function Include(f)
        if ids[f] then return end
        frames[#frames + 1], ids[f] = f, #frames + 1
        for _, r in ipairs(f.regions or {}) do Include(r) end
    end
    for _, f in ipairs(mw.world.widgets.frames) do Include(f) end
end
local function Diff(a, b, path, out)
    path, out = path or "", out or {}
    if a == b then return out end
    if type(a) == "table" and type(b) == "table" then
        local keys = {}
        for k in pairs(a) do keys[k] = true end
        for k in pairs(b) do keys[k] = true end
        for k in pairs(keys) do Diff(a[k], b[k], path .. "." .. tostring(k), out) end
    elseif Encode(a) ~= Encode(b) then out[path] = { before = a, after = b } end
    return out
end
local function Command(w) return w._msuf2CommandAction or (w._msuf2RuntimeControlRecord or {}).command end
local function Input(w, value)
    local cmd = Command(w)
    if cmd.kind == "color" then w._msuf2OnColorChanged(unpack(value))
    elseif cmd.kind == "toggle" then w:SetChecked(value) w:Click("LeftButton")
    elseif w.buttons then
        for _, b in ipairs(w.buttons) do if b._msuf2Value == value then b:Click("LeftButton") end end
    elseif w._msuf2OnValueChanged then w._msuf2OnValueChanged(value)
    elseif w._msuf2OnCommit then w._msuf2OnCommit(value)
    else w:SetValue(value) World.FireScript(w, "OnValueChanged", value) end
    mw:RunTimers()
end
local function Owned(w, page)
    local entry = M.cache[page]
    while w do
        for id, section in pairs(entry.sections) do
            if w == section or w == section._msuf2CollapsibleEntry.header then return id end
        end
        w = w.GetParent and w:GetParent()
    end
end
local function Controls(page)
    local result = {}
    for _, r in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        local w = M.RuntimeControlCatalog.Get(r.controlId).widget
        if r.pageKey == page and w and Owned(w, page) then result[#result + 1] = w end
    end
    table.sort(result, function(a, b) return a._msuf2RuntimeControlRecord.controlId < b._msuf2RuntimeControlRecord.controlId end)
    return result
end
local function Gates(controls)
    local result = {}
    for _, w in ipairs(controls) do result[#result + 1] = { w:IsShown(), w:IsEnabled() } end
    return result
end
local function Snapshot(page, tag)
    Index()
    for _, w in ipairs(frames) do
        if Owned(w, page) then
            local points = {}
            for i = 1, w:GetNumPoints() do points[#points + 1] = { w:GetPoint(i) } end
            Add("layout:" .. page .. ":" .. tag, w, w:GetParent(), w:GetObjectType(), w.width, w.height,
                w.text, points, w.allPoints, w.alpha, w:IsShown(), w:IsEnabled())
        end
    end
    for _, w in ipairs(Controls(page)) do
        local r, cmd = w._msuf2RuntimeControlRecord, Command(w)
        tips = {}
        if w:HasScript("OnEnter") then World.FireScript(w, "OnEnter") end
        if w:HasScript("OnLeave") then World.FireScript(w, "OnLeave") end
        local low, high
        if r.kind == "slider" then low, high = w:GetMinMaxValues() end
        Add("control:" .. page .. ":" .. tag, r, w._msuf2SearchMeta, low, high, w.valueStep,
            w.GetValues and w:GetValues() or w.values, cmd and cmd.get and { cmd.get() }, tips)
    end
end
local enabled = { "enabled", "hideOfflineEnabled", "nameBarEnabled", "targetsEnabled", "petsEnabled",
    "friendlyBossEnabled", "healerManaEnabled", "buffCoverageEnabled", "buffCoverageBlessingPriorities",
    "layoutTiersEnabled", "tier10Position", "tier20Position", "tier25Position", "tier40Position",
    "oocFadeEnabled", "sortClassPriority", "preserveRaidGroups" }
local migrated = { general = true, anchor = true, scaling = true, transparency = true, layout_advanced = true,
    sorting = true, buff_coverage = true, blessing_priorities = true, name_bar = true,
    party_targets = true, group_pets = true, friendly_bosses = true, healer_mana = true }
local function CheckInputOwners(ctx)
    local record = M.RuntimeControlCatalog.Get("menu2.gf_layout.group.field.showsolo")
    local widget = record and record.widget
    assert(widget, "wrong-key: Show while solo lost its setting route")
    local conf, cmd = GP.Conf("party"), Command(widget)
    local enabledBefore, before = conf.enabled, conf.showSolo
    conf.enabled = true
    M.Refresh(ctx)
    local value = not cmd.get()
    M.ClearHistory()
    Input(widget, value)
    assert(conf.showSolo == value, "Show while solo input did not reach DB")
    assert(M.Undo() and GP.Conf("party").showSolo == before, "lost-history: Show while solo cannot undo")
    mw:RunTimers()
    M.ClearHistory()
    core.Util.InCombat("PLAYER_REGEN_DISABLED")
    env.InCombatLockdown = function() return true end
    Input(widget, value)
    assert(GP.Conf("party").showSolo == before and not M.Undo(), "lost-combat-guard: Show while solo wrote in combat")
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    env.InCombatLockdown = function() return false end
    mw:Fire("PLAYER_REGEN_ENABLED")
    GP.Conf("party").enabled = enabledBefore
    M.Refresh(ctx)
    mw:RunTimers()
    M.ClearHistory()
end
local count, touched, required = 0, {}, {}
local function InputControl(w, page)
    local r, cmd = w._msuf2RuntimeControlRecord, Command(w)
    return cmd and cmd.get and cmd.set and r.classification == "setting"
        and (page == "gf_priority" or migrated[Owned(w, page)])
end
-- One input through the native control: DB, apply, refresh, undo, combat refusal and redo.
local function RunInput(w, state, scope, controls)
    local cmd, r = Command(w), w._msuf2RuntimeControlRecord
    local ordinary = r.kind == "toggle" or r.kind == "slider" or r.kind == "dropdown" or r.kind == "color"
    if ordinary then required[r.controlId] = true end
    if not parent and ordinary then
        assert(w._msuf2ControlSchema, "ordinary control escaped the schema: " .. r.controlId)
    end
    local value
    if cmd.kind == "toggle" then value = not cmd.get()
    elseif cmd.kind == "slider" or r.kind == "slider" then
        local low, high = w:GetMinMaxValues()
        value = state == 1 and low + (high - low) * .37 or high
    elseif cmd.kind == "color" then value = state == 1 and { .2, .4, .6 } or { 0, 1, .5 }
    elseif cmd.kind == "textinput" then value = state == 1 and "TestFrame" or ""
    else
        local values = w.GetValues and w:GetValues() or w.values
        if type(values) == "function" then values = values() end
        if values and #values > 0 then value = values[state == 1 and #values or 1].value end
    end
    if value == nil then return end
    count = count + 1
    M.ClearHistory()
    local before = CopyDB()
    calls = {}
    Input(w, value)
    local after = CopyDB()
    if next(Diff(before, after)) then touched[r.controlId] = true end
    Add("input:" .. scope .. ":" .. r.controlId, value, Diff(before, after), { cmd.get() }, calls, Gates(controls))
    local undo = M.Undo()
    mw:RunTimers()
    Add("undo:" .. scope .. ":" .. r.controlId, undo, Diff(before, CopyDB()), { cmd.get() })
    -- Refusal is checked while the requested value is still undone.
    before = CopyDB()
    core.Util.InCombat("PLAYER_REGEN_DISABLED")
    env.InCombatLockdown = function() return false end
    Input(w, value)
    Add("combat-edge:" .. scope .. ":" .. r.controlId, Diff(before, CopyDB()), M.Undo())
    env.InCombatLockdown = function() return true end
    Input(w, value)
    Add("combat:" .. scope .. ":" .. r.controlId, Diff(before, CopyDB()), M.Undo())
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    env.InCombatLockdown = function() return false end
    mw:Fire("PLAYER_REGEN_ENABLED")
    mw:RunTimers()
    local redo = M.Redo()
    mw:RunTimers()
    Add("redo:" .. scope .. ":" .. r.controlId, redo, Diff(after, CopyDB()), { cmd.get() })
    M.Undo()
    mw:RunTimers()
end
local function OpenSections(entry)
    local sections = {}
    for id in pairs(entry.sections) do sections[#sections + 1] = id end
    table.sort(sections)
    for _, id in ipairs(sections) do entry.sections[id]._msuf2CollapsibleEntry.SetOpenImmediate(true) end
    mw:RunTimers()
    M.Refresh(entry.ctx)
end
if review then
    if stack then
        assert(mw:Select("gf_layout"))
        OpenSections(M.cache.gf_layout)
        Index()
        local count = 0
        for _, w in ipairs(frames) do
            local spec = w._msuf2ControlSchema
            if Owned(w, "gf_layout") and spec and spec.kind == "growthTiles" then
                assert(spec.id == "menu2.gf_layout.group.growth.tiles" and spec.labelKey == "Growth Direction"
                    and spec.scope == "group" and spec.applyDomain == "layout" and spec.owner == w,
                    "stacked growth-holder declaration was overwritten")
                count = count + 1
            end
        end
        assert(count == 1, "stacked growth-holder declaration missing or duplicated")
        print("stacked Group growth-holder owner OK")
        return
    end
    local schemaByPage, declarationCount = {}, 0
    local kinds = { toggle = true, slider = true, dropdown = true, color = true, textinput = true,
        text = true, font = true, button = true, card = true, segment = true,
        pinRow = true, dragSort = true, dragrow = true, growthTiles = true }
    local domains = { rebuild = true, visual = true, layout = true, priority = true,
        presentation = true, contextColors = true, menuState = true, keyBinding = true, sectionNavigation = true }
    local visualKeys = { hideinhousing = true, hideinclientscene = true, hideofflineenabled = true,
        hideofflinedelay = true, hideofflineincombat = true, chunkedfill = true, smoothfill = true, reversefill = true,
        alphaexcludetextportrait = true, alphaexcludepredictionbars = true }
    local function Declaration(w, page, seen)
        -- Group.lua owns Portrait/Text; those sections still participate in parity.
        if page == "gf_layout" and not migrated[Owned(w, page)] then return end
        local spec, record = w._msuf2ControlSchema, w._msuf2RuntimeControlRecord
        -- Every recorded owner in this batch, including navigation and ephemeral
        -- controls, must declare itself. Unrecorded regions use their composite owner.
        if ownedRows[w] or record then
            assert(spec, "owned frame declaration missing: " .. tostring(record and record.controlId or ids[w]))
        end
        if not spec then return end
        local id, kind, scope, domain = spec.id, spec.kind, spec.scope, spec.applyDomain
        assert(type(id) == "string" and id:match("^menu2%." .. page .. "%.[%w_%.]+$")
            and not id:find("..", 1, true) and not id:match("%.$"), "unreadable declaration ID: " .. tostring(id))
        assert(not seen[id], "duplicate declaration ID: " .. id)
        assert(kinds[kind], "invalid declaration kind: " .. id)
        assert(not ownedRows[w] or kind == ownedRows[w], "owned frame declaration kind mismatch: " .. id)
        assert(domains[domain], "invalid declaration apply domain: " .. id)
        assert(not spec.owner or spec.owner == w, "declaration owner drift: " .. id)
        local section = assert(Owned(w, page))
        local expectedScope = page == "gf_layout" and "group" or (kind == "pinRow" and "character" or "profile")
        assert(scope == expectedScope, "schema scope/section mismatch: " .. id)
        local expectedDomain
        if id:match("%.section%.[%w_]+%.expanded$") then expectedDomain = "sectionNavigation"
        elseif kind == "text" or kind == "font" then expectedDomain = "presentation"
        elseif kind == "card" or kind == "growthTiles" then expectedDomain = "layout"
        elseif id:match("%.field%.growth%.option%.") then expectedDomain = "layout"
        elseif domain == "contextColors" then
            assert(kind == "button" and id:match("%.colors$"), "context colors owner mismatch: " .. id)
            expectedDomain = "contextColors"
        elseif page == "gf_priority" then
            expectedDomain = id == "menu2.gf_priority.group.binding.capture" and "keyBinding" or "priority"
        elseif domain == "menuState" then
            assert(kind == "segment" and (section == "scaling" or section == "transparency"), "menu state owner mismatch: " .. id)
            expectedDomain = "menuState"
        else
            local key = id:match("%.([^%.]+)$")
            expectedDomain = (section == "transparency" or section == "buff_coverage" or section == "blessing_priorities"
                or visualKeys[key] or id == "menu2.gf_layout.group.basics.raid_manager") and "visual" or "rebuild"
        end
        assert(domain == expectedDomain, "schema apply domain/section mismatch: " .. id)
        if record then
            assert(id == record.controlId and kind == record.kind, "schema/search identity mismatch: " .. id)
        end
        seen[id] = { kind, scope, domain, section }
        declarationCount = declarationCount + 1
    end
    -- Exact non-record chrome/help IDs, sorted as suffixes of menu2.<page>.
    -- Client-only additions are explicit; no observations or schema receipts live here.
    local chromeIds = {
        gf_layout = [[
basics.behavior_title basics.offline_title basics.providerHelp basics.raidManagerHelp geometry.grid geometry.growth
geometry.rules geometry.visibility_help healerMana.position_help healerMana.role_help pets.position_help
scaling.appearance scaling.modeCard scaling.rules scaling.sizeCard scaling.size_help scaling.tier10.help
scaling.tier20.help scaling.tier25.help scaling.tier40.help section.general.expanded.colors
section.healer_mana.expanded.colors section.name_bar.expanded.colors sizingtier.help.tier10 sizingtier.help.tier20
sizingtier.help.tier25 sizingtier.help.tier40 sorting.classCard sorting.class_priority sorting.roleCard
sorting.role_priority sorting.sortCard targets.position_help transparency.healthOpacityCard
transparency.healthOpacityCard.colors transparency.oocCard transparency.opacityOptionsCard
]],
        gf_priority = [[
binding.title bindingcapture.hint overview.help pins.name.1 pins.name.2 pins.name.3 pins.name.4 pins.name.5
pins.number.1 pins.number.2 pins.number.3 pins.number.4 pins.number.5 pins.row.1 pins.row.2 pins.row.3 pins.row.4
pins.row.5 pins.status.1 pins.status.2 pins.status.3 pins.status.4 pins.status.5 placement.help
prioritypage.behavior prioritypage.bindingCard prioritypage.emptyPins prioritypage.hotkeyHint
prioritypage.liveStatus prioritypage.pageText prioritypage.pinsCard prioritypage.pinsStatus
prioritypage.placementHint
]],
    }
    if core.Client.SupportsUnit("boss") then
        chromeIds.gf_layout = chromeIds.gf_layout .. " friendlyBoss.position_help friendlyBoss.role_help"
    end
    if core.Client.IsForever then
        chromeIds.gf_layout = chromeIds.gf_layout .. [[
 blessingpriorities.class_help blessingpriorities.help blessingpriorities.role.DPS
blessingpriorities.role.Healer blessingpriorities.role.Tank buffcoverage.help]]
    end
    local expectedChrome = {}
    for page, list in pairs(chromeIds) do
        local ids = {}
        for id in list:gmatch("%S+") do ids[#ids + 1] = "menu2." .. page .. "." .. id end
        table.sort(ids)
        expectedChrome[page] = table.concat(ids, "\n")
    end
    local pageBuilder = M.Widgets.PageBuilder
    local width
    local function Workspace(widget)
        local result = {}
        while widget do
            if widget._msuf2GroupSizingTab then result.sizing = widget._msuf2GroupSizingTab end
            local view = widget._msuf2ExactTabView
            if view then result[view.kind] = view.value end
            widget = widget.GetParent and widget:GetParent()
        end
        return result
    end
    M.Widgets.PageBuilder = function(ctx)
        ctx.width = width
        return pageBuilder(ctx)
    end
    for _, size in ipairs({ 400, 1040 }) do
        width, M.formContentMaxWidth = size, size == 400 and 420 or 1040
        for _, page in ipairs({ "gf_layout", "gf_priority" }) do
            M.gfScope = "party"
            M.InvalidatePage(page)
            assert(mw:Select(page))
            local entry = M.cache[page]
            OpenSections(entry)
            Snapshot(page, "width-" .. size)
            local seenDeclarations, chrome = {}, {}
            for _, w in ipairs(frames) do
                if Owned(w, page) then
                    Add("search:" .. page .. ":" .. size, w, w._msuf2SearchMeta, w._msuf2StableSearchLabel,
                        w._msuf2SearchText, Workspace(w), w._msuf2ExactTargetKinds, w._msuf2ExactTargetContracts)
                    if not parent then
                        Declaration(w, page, seenDeclarations)
                        local spec = w._msuf2ControlSchema
                        if spec and not w._msuf2RuntimeControlRecord then chrome[#chrome + 1] = spec.id end
                    end
                end
            end
            if not parent then
                table.sort(chrome)
                assert(table.concat(chrome, "\n") == expectedChrome[page], "chrome/help declaration IDs drift: " .. page)
                if page == "gf_priority" then
                    for i = 1, 5 do
                        local row = seenDeclarations["menu2.gf_priority.pins.row." .. i]
                        assert(row and row[1] == "pinRow", "pooled pin row declaration missing: " .. i)
                    end
                else
                    for _, owner in ipairs({ "class_priority", "role_priority" }) do
                        local row = seenDeclarations["menu2.gf_layout.sorting." .. owner]
                        assert(row and row[1] == "dragSort", "drag sort owner declaration missing: " .. owner)
                    end
                end
                if schemaByPage[page] then
                    for id, declaration in pairs(seenDeclarations) do
                        local prior = schemaByPage[page][id]
                        assert(not prior or Encode(prior) == Encode(declaration), "rebuilt declaration identity drift: " .. id)
                    end
                else schemaByPage[page] = seenDeclarations end
            end
            -- Clear every stored scalar in the relevant records together. Read the
            -- installed getters before refresh can seed any native defaults.
            local saved = {}
            for _, conf in ipairs({ GP.Conf("party"), GP.Conf("raid"), GP.Conf("mythicraid"), core.GF.GetPriorityConf() }) do
                local values = {}
                for key, value in pairs(conf) do
                    if type(value) ~= "table" then values[key], conf[key] = value, nil end
                end
                saved[#saved + 1] = { conf, values }
            end
            for _, w in ipairs(Controls(page)) do
                local cmd, record = Command(w), w._msuf2RuntimeControlRecord
                if cmd and cmd.get then Add("absent:" .. record.controlId, { cmd.get() }) end
            end
            -- The optional core value provider normally supplies another default.
            -- Also exercise the page's supported local fallback when it is absent.
            local coreValue = core.GF.Val
            core.GF.Val = nil
            for _, w in ipairs(Controls(page)) do
                local cmd, record = Command(w), w._msuf2RuntimeControlRecord
                if cmd and cmd.get then Add("page-fallback:" .. record.controlId, { cmd.get() }) end
            end
            core.GF.Val = coreValue
            for _, item in ipairs(saved) do for key, value in pairs(item[2]) do item[1][key] = value end end
        end
    end
    if not parent then assert(declarationCount >= 400, "incomplete owned declaration coverage") end
else
for _, page in ipairs({ "gf_layout", "gf_priority" }) do
    M.gfScope = "party"
    assert(mw:Select(page), "page missing: " .. page)
    local entry = M.cache[page]
    OpenSections(entry)
    if page == "gf_layout" then CheckInputOwners(entry.ctx) end
    Snapshot(page, "default")
    local controls = Controls(page)
    local inputControls = {}
    for _, w in ipairs(controls) do
        if InputControl(w, page) then inputControls[#inputControls + 1] = w end
    end
    local edgeScope = core.Client.SupportsGroupKind("mythicraid") and "mythicraid" or "raid"
    for state, scope in ipairs({ "party", edgeScope }) do
        -- Existing widgets must resolve a different scope at input time.
        M.gfScope = scope
        if state == 2 then
            -- Party-only options are enabled in the Party scope, so both scopes carry the optional settings.
            for _, optionScope in ipairs({ "party", scope }) do
                for _, key in ipairs(enabled) do GP.Conf(optionScope)[key] = true end
                GP.Conf(optionScope).sortMode, GP.Conf(optionScope).frameScaleMode = "GROUP_ROLE", "auto"
            end
            if page == "gf_priority" then env.MSUF_DB.gf_priority.placement = "FREE" end
        end
        M.Refresh(entry.ctx)
        Add("gates:" .. page .. ":" .. scope, Gates(controls))
        for _, w in ipairs(inputControls) do RunInput(w, state, scope, controls) end
    end
    Snapshot(page, "edge")
    -- Options that were disabled or absent so far (Party-only ones) run on a rebuilt live Party page.
    local pending = false
    for id in pairs(required) do
        if not touched[id] and id:find("menu2." .. page .. ".", 1, true) then pending = true end
    end
    if pending then
        M.SetMenuStateValue("gfScope", "party")
        mw:RunTimers()
        entry = M.cache[page]
        OpenSections(entry)
        mw:RunTimers()
        local live = Controls(page)
        Add("gates:" .. page .. ":party-live", Gates(live))
        local liveInputs = {}
        for _, w in ipairs(live) do
            local id = w._msuf2RuntimeControlRecord.controlId
            if InputControl(w, page) and required[id] and not touched[id] then liveInputs[#liveInputs + 1] = w end
        end
        for _, w in ipairs(liveInputs) do RunInput(w, 2, "party-live", live) end
    end
end
-- The other two batch files are pure catalogue/model owners, without page constructors.
Add("specs", M.GroupSpecs)
for _, scope in ipairs({ "party", "raid" }) do
    Add("spell-model:" .. scope, GP.SpellSpecValues(), GP.SpellTrackedSpecValues(), GP.SpellIndicators(scope),
        GP.EffectiveSpellSpec(scope), GP.SpellAuraValues(scope), GP.CurrentSpellAura(scope), GP.CurrentSpellConfig(scope, false))
end
assert(count >= 150, "incomplete input coverage: " .. count)
local missing = {}
for id in pairs(required) do if not touched[id] then missing[#missing + 1] = id end end
table.sort(missing)
assert(#missing == 0, "settings without an effective input: " .. table.concat(missing, ", "))
end
return observations, count
end
local started, total, inputs = os.clock(), 0, 0
if stack then Replay(false, true) return end
if parentWorker then
    local rows, count = Replay(true, mode == "parent-review")
    io.write("group layout parent replay\n", count, "\n", #rows, "\n")
    for _, row in ipairs(rows) do io.write(row, "\n") end
    io.write("end of parent replay\n")
    return
end
local function Quote(value)
    assert(not value:find('["\r\n]'), "invalid replay path")
    return '"' .. value .. '"'
end
for _, review in ipairs({ false, true }) do
    if not mode or (review and mode == "review") or (not review and mode == "compare") then
        -- One client at a time, Jobs 2 within the caller's Lua slot. The child
        -- inherits BelowNormal priority and streams observations from this same
        -- harness; no replay output is persisted. Drain it even on candidate failure.
        local command = Quote(assert(arg[-1], "Lua interpreter path missing")) .. " "
            .. Quote(root .. "/tools/tests/menu_grouplayout_parity_smoke.lua") .. " "
            .. Quote(root) .. " " .. Quote(flavor) .. " parent-" .. (review and "review" or "compare")
        if package.config:sub(1, 1) == "\\" then command = '"' .. command .. '"' end
        local pipe = assert(io.popen(command, "r"))
        local ok, actual, count = pcall(Replay, false, review)
        local output = pipe:read("*a")
        pipe:close()
        if not ok then error(actual, 0) end
        local nextLine = output:gmatch("([^\n]*)\n")
        local function Read() return ((nextLine() or ""):gsub("\r$", "")) end
        assert(Read() == "group layout parent replay", "immutable parent replay failed")
        assert(tonumber(Read()) == count, "parent/candidate input count drift")
        local rows = assert(tonumber(Read()), "parent observations missing")
        assert(rows == #actual, "lost trailing observations")
        for i = 1, rows do
            local prior = Read()
            if prior ~= actual[i] then
                local diagnostic = assert(io.open(root .. "/.checks/parity-mismatch-" .. flavor .. ".txt", "wb"))
                diagnostic:write("parent\n", prior, "\ncandidate\n", actual[i], "\n")
                diagnostic:close()
                error(flavor .. " parity row " .. i .. " " .. actual[i]:match("^[^\t]+"))
            end
        end
        assert(Read() == "end of parent replay" and nextLine() == nil, "trailing parent observations")
        total, inputs = total + #actual, inputs + count
        output, actual = nil, nil
        collectgarbage("collect")
    end
end
print("menu_grouplayout_parity_smoke " .. flavor .. ": " .. inputs .. " inputs; " .. total
    .. " live parent observations OK (" .. string.format("%.2fs", os.clock() - started) .. ")")
