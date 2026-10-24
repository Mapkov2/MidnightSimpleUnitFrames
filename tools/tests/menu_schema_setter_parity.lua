-- Differential replay of every converted declaration against its frozen hand setter.
-- Usage: lua menu_schema_setter_parity.lua <root> <Mainline|Vanilla|TBC|Mists|Forever>
local root, flavor = assert(arg[1]), assert(arg[2])
root = root:gsub("\\", "/"):gsub("/$", "")
local reportDirectory = os.getenv("MSUF_SCHEMA_SETTER_REPORT_DIR") or os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
local fixtures = assert(loadfile(root .. "/tools/tests/menu_schema_setter_legacy.lua"))()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local function Read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local function Copy(value, seen)
    if not seen then
        if type(value) ~= "table" then return value end
        seen = {}
    end
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        if type(item) == "table" then out[key] = Copy(item, seen)
        else out[key] = item end
    end
    return out
end
local function Replace(dst, src)
    for key in pairs(dst) do if src[key] == nil then dst[key] = nil end end
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            Replace(dst[key], value)
        else dst[key] = value end
    end
end
local function Equal(a, b, path)
    local kind = type(a)
    if kind ~= type(b) then return false, (path or "") .. " types" end
    if kind ~= "table" then
        if a == b then return true end
        return false, (path or "") .. " values " .. tostring(a) .. " / " .. tostring(b)
    end
    for key, value in pairs(a) do
        local ok, why = Equal(value, b[key])
        if not ok then return false, (path or "") .. "." .. tostring(key) .. why end
    end
    for key in pairs(b) do
        if a[key] == nil then return false, (path or "") .. "." .. tostring(key) .. " extra" end
    end
    return true
end
local policies, controls, seenFixtures, loaded = {}, {}, {}, {}
local customMissing = {}
local sectionPolicies, sectionResetChecks, sectionWatched = {}, 0, false
local legacy, watching, combat, setterCalls = false, false, false, 0
local function Rewrite(source, path)
    return (source:gsub("([%w_.]*write)%s*=%s*(%b{})(%s*,?%s*)%-%-%[%[schema setter: ([%w.]+)%]%]",
        function(lhs, policy, separator, id)
            local fixture = assert(fixtures[id], "unfrozen policy " .. id)
            assert(path:sub(-#fixture.path) == fixture.path, "fixture moved " .. id)
            loaded[id] = true
            local setter = assert(fixture.source:match("=%s*(function.*)"))
            return lhs .. " = __SchemaSetterPolicy(" .. policy .. ", " .. setter .. ", " .. string.format("%q", id) .. ")"
                .. separator
        end))
end
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    if not world.client.isForever then return end
    -- Forever has no legacy global GetSpecialization. The shared world's
    -- unknown-global stub is callable and returns an opaque table instead.
    local meta = getmetatable(world.env)
    local lookup = meta.__index
    meta.__index = function(env, key)
        if key == "GetSpecialization" then return nil end
        return lookup(env, key)
    end
end, beforeOptions = function(world)
    if world.core.Client.IsForever then
        assert(world.core.Specialization.GetSpecialization == nil, "Forever captured a specialization stub")
    end
    world.core.FirstLoad6.deferredThisSession = true
    world.core.Public.IsConfigCombatLocked = function() return combat end
    world.env.__SchemaSetterPolicy = function(policy, setter, id)
        policies[policy] = { setter = setter, id = id }
        return policy
    end
    local load = world.LoadFile
    function world:LoadFile(path, addon, namespace)
        local source = path:find("/Shell/Menu2/", 1, true) and Rewrite(Read(path), path)
        local ok, message
        if source then
            local chunk = assert(loadstring(source, "@" .. path))
            setfenv(chunk, self.env)
            ok, message = pcall(chunk, addon, namespace)
        else ok, message = load(self, path, addon, namespace) end
        if ok and not watching and self.core.MSUF2 and self.core.MSUF2.ControlSchema then
            watching = true
            local M = self.core.MSUF2
            local schema, bind = M.ControlSchema, M.ControlSchema.Bind
            local custom = schema.Custom
            schema.Custom = function(widget, spec)
                local result = custom(widget, spec)
                if spec._parityFrozen then
                    controls[#controls + 1] = { widget = widget, spec = spec, frozen = spec._parityFrozen,
                        page = M.activeKey, command = true }
                    seenFixtures[spec._parityFrozen.id] = true
                elseif spec.set and not spec.write and not spec.customSetReason then
                    local info = debug.getinfo(spec.set, "S")
                    customMissing[spec.id] = info.short_src .. ":" .. info.linedefined
                end
                return result
            end
            local setter = assert(schema.Setter, "schema-derived setter missing (red baseline)")
            schema.Setter = function(spec)
                local derived = setter(spec)
                local frozen = policies[spec.write]
                if not frozen then return derived end
                spec._parityFrozen = frozen
                return function(...)
                    setterCalls = setterCalls + 1
                    if legacy then return frozen.setter(...) end
                    return derived(...)
                end
            end
            schema.Bind = function(ctx, widget, spec)
                local frozen = policies[spec.write]
                local result = bind(ctx, widget, spec)
                frozen = frozen or spec._parityFrozen
                if frozen then
                    controls[#controls + 1] = { widget = widget, spec = spec, frozen = frozen, page = ctx.key }
                    seenFixtures[frozen.id] = true
                elseif spec.set and not spec.write and not spec.customSetReason then
                    local info = debug.getinfo(spec.set, "S")
                    customMissing[spec.id] = info.short_src .. ":" .. info.linedefined
                end
                return result
            end
        end
        local shared = self.core.MSUF2 and self.core.MSUF2.UnitSectionsShared
        if ok and not sectionWatched and shared and shared.AttachSectionUX then
            sectionWatched = true
            local attach = shared.AttachSectionUX
            shared.AttachSectionUX = function(ctx, opts)
                local result = attach(ctx, opts)
                for id, policy in pairs(opts.sections) do
                    local section = ctx.entry.sections and ctx.entry.sections[id]
                    local entry = section and section._msuf2CollapsibleEntry
                    if entry then sectionPolicies[entry] = { opts = opts, policy = policy } end
                end
                return result
            end
        end
        return ok, message
    end
end })
local M, env = mw.M, mw.env
if mw.core.Client.IsForever then assert(env.GetSpecialization == nil, "Forever legacy specialization fixture drift") end
M.ShowHistoryFeedback, M.ShowStatusFeedback = function() end, function() end
-- Match the section-parity harness: the codec-free world uses its normalized
-- initial profile as a deterministic factory, shared by both reset branches.
local resetFixture = Copy(M.EnsureDB())
mw.core.MSUF_CreateFactoryDefaultProfile = function() return Copy(resetFixture) end
-- The shared headless scene does not supply the optional bar override record.
-- Isolate setter parity from that unrelated scene composition boundary.
local sceneStatic = M.ClassPowerPreview.SceneStatic
M.ClassPowerPreview.SceneStatic = function(sample, ...)
    sample.bars = sample.bars or {}
    return sceneStatic(sample, ...)
end
env.InCombatLockdown = function() return combat end
env.UnitAffectingCombat = function() return combat end
local pages = {}
for key in pairs(M.pages) do pages[#pages + 1] = key end
table.sort(pages)
for _, key in ipairs(pages) do
    assert(mw:Select(key), key .. ": selection refused")
    local entry = assert(M.cache[key])
    -- Use the real section policy before expanding lazy bodies. Test both the
    -- existing record and an absent key against the exact former raw-key loop.
    for _, section in pairs(entry.sections or {}) do
        local disclosure = section._msuf2CollapsibleEntry
        local owner = disclosure and sectionPolicies[disclosure]
        if owner then
            local shared, opts = M.UnitSectionsShared, owner.opts
            local scope = opts.scope()
            local conf, defaults = opts.conf(scope), opts.defaults(scope)
            if defaults then
                local keys = shared.SectionFieldKeys(owner.policy, conf, defaults)
                for sparse = 1, 2 do
                    local before = Copy(conf)
                    if sparse == 2 and keys[1] then conf[keys[1]] = nil end
                    local expected = Copy(conf)
                    for _, field in ipairs(keys) do expected[field] = Copy(defaults[field]) end
                    shared.RestoreSectionValues(disclosure, keys, conf, defaults, true)
                    local same, why = Equal(conf, expected)
                    assert(same, key .. ": lazy/sparse section reset " .. tostring(why))
                    Replace(conf, before)
                    sectionResetChecks = sectionResetChecks + 1
                end
            end
        end
    end
    for _ = 1, 3 do
        for _, section in pairs(entry.sections or {}) do
            local disclosure = section._msuf2CollapsibleEntry
            if disclosure then
                if disclosure._msuf2EnsureContent then disclosure._msuf2EnsureContent() end
                disclosure.SetOpenImmediate(true)
            end
        end
        mw:RunTimers()
    end
    assert(not entry._msuf2BuildIncomplete, key .. ": incomplete page")
end
-- These exported factories currently have no page consumer. Exercise their real
-- declaration/binding seam so their conversion cannot escape the differential.
do
    local ctx = { key = "gameplay", refreshers = {}, entry = M.cache.gameplay }
    M.AdvancedPage.BindTableDropdown(ctx, M.frame, "Choice fixture", { { value = "none", text = "None" },
        { value = "player", text = "Player" } }, 220, M.AdvancedPage.Gameplay, "combatTimerAnchor", "none", nil,
        { controlId = "setter.fixture.table.choice", settingKey = "gameplay.combatTimerAnchor" })
    local row = { "dropdown", "rangeFadeLayerMode", "frame", { "Scope fixture",
        { { value = "frame", text = "Frame" }, { value = "health", text = "Health" } }, 220 }, binding = "scopeValue" }
    M.ControlSchema.Build({ key = "gf_layout", refreshers = {}, entry = M.cache.gf_layout }, M.frame, { row },
        M.ControlSchema.GroupOptions())
end
assert(#controls > 100, "too few converted controls: " .. #controls)
assert(sectionResetChecks > 20, "real lazy/sparse section policies were not exercised")
if arg[3] == "--inventory-only" then
    local ids = {}
    for id in pairs(loaded) do if not seenFixtures[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    print("unbuilt " .. flavor .. ": " .. table.concat(ids, ", "))
    local file = assert(io.open(reportDirectory .. "/f3-custom-missing-" .. flavor .. ".txt", "wb"))
    for id, where in pairs(customMissing) do file:write(id, " ", where, "\n") end
    file:close()
    return
end
local function Candidates(control)
    local spec, widget = control.spec, control.widget
    if control.command then return { true } end
    local current = widget._msuf2CommandAction.get()
    if spec.kind == "toggle" then return { not current } end
    if spec.kind == "slider" then
        local range = assert(spec.range)
        return { range[1], range[2] }
    end
    if spec.kind == "textinput" then return { "", " / ", { nilCommit = true } } end
    if spec.kind == "segment" then
        local out = {}
        for index in ipairs(widget.buttons) do out[#out + 1] = { button = index } end
        return out
    end
    local choices = spec.values or widget.values or widget._msuf2Values
    if type(choices) == "function" then choices = choices() end
    local values = {}
    for _, button in ipairs(widget.buttons or {}) do values[#values + 1] = button._msuf2Value end
    for _, item in ipairs(type(choices) == "table" and choices or {}) do
        values[#values + 1] = type(item) == "table" and item.value or item
    end
    assert(#values > 0, "no candidates: " .. spec.id)
    local first = values[1]
    for _, value in ipairs(values) do if value ~= current then first = value; break end end
    if values[#values] ~= first then return { first, values[#values] } end
    return { first }
end
local function Drive(control, value)
    local widget, kind = control.widget, control.spec.kind
    if control.command then MenuWorld.FireScript(widget, "OnClick", "LeftButton"); return end
    if kind == "toggle" then MenuWorld.FireScript(widget, "OnClick", "LeftButton")
    elseif kind == "slider" then MenuWorld.FireScript(widget, "OnValueChanged", value)
    elseif kind == "dropdown" then widget._msuf2OnValueChanged(value)
    elseif kind == "textinput" then
        if type(value) == "table" and value.nilCommit then value = nil end
        widget._msuf2OnCommit(value)
    elseif kind == "segment" then
        widget:SetValue(widget._msuf2CommandAction.get())
        if type(value) == "table" then
            MenuWorld.FireScript(widget.buttons[value.button], "OnClick", "LeftButton")
            return
        end
        for _, button in ipairs(widget.buttons) do
            if button._msuf2Value == value then MenuWorld.FireScript(button, "OnClick", "LeftButton"); return end
        end
        error("missing segment choice")
    else error("unsupported candidate kind " .. kind) end
end
local function HistoryPathLess(a, b)
    for index = 1, math.min(#a, #b) do
        local left, right = a[index], b[index]
        local kind, other = type(left), type(right)
        if kind ~= other then return kind < other end
        if left ~= right then
            if kind == "boolean" then return left == false end
            return left < right
        end
    end
    return #a < #b
end
local function OrderHistory(entries)
    for _, entry in ipairs(entries) do
        assert(type(entry.diff) == "table", "history diff missing")
        for _, change in ipairs(entry.diff) do
            assert(type(change.path) == "table" and #change.path > 0, "history path missing")
            for _, key in ipairs(change.path) do
                local kind = type(key)
                assert(kind == "string" or kind == "number" or kind == "boolean", "history path key invalid")
                assert(kind ~= "number" or key == key, "history path NaN")
            end
        end
        table.sort(entry.diff, function(a, b) return HistoryPathLess(a.path, b.path) end)
        for index = 2, #entry.diff do
            local left, right, overlaps = entry.diff[index - 1].path, entry.diff[index].path, true
            for key = 1, math.min(#left, #right) do
                if left[key] ~= right[key] then overlaps = false; break end
            end
            assert(not overlaps, "history diff paths overlap or repeat")
        end
    end
    return entries
end
local function History()
    local entries = Copy(M.historyUndo)
    for _, entry in ipairs(entries) do entry.seq = nil end
    return OrderHistory(entries)
end
local checks, failures = 0, {}
local applyLog, applyDepth, tracing = {}, 0, false
for name, original in pairs(mw.core.ApplyService) do
    if type(original) == "function" and name:match("^Request") then
        mw.core.ApplyService[name] = function(...)
            if tracing and applyDepth == 0 then
                applyLog[#applyLog + 1] = { name = name, args = Copy({ n = select("#", ...), ... }) }
            end
            applyDepth = applyDepth + 1
            local result = original(...)
            applyDepth = applyDepth - 1
            return result
        end
    end
end
local function Check(ok, message)
    if not ok then failures[#failures + 1] = message end
end
local resets, scopeChecks = 0, 0
for _, control in ipairs(controls) do
    local spec = control.spec
    local scopes = { "party" }
    if spec.scope == "group" then
        for _, scope in ipairs({ "raid", "mythicraid" }) do
            if mw.core.Client.SupportsGroupKind(scope) then scopes[#scopes + 1] = scope end
        end
    end
    for _, scope in ipairs(scopes) do
    M.gfScope = scope
    scopeChecks = scopeChecks + 1
    local baseline = Copy(M.EnsureDB())
    local labels = {}
    for _, field in ipairs({ "_msuf2Title", "_msuf2Label" }) do
        local font = control.widget[field]
        if font and font.GetText then labels[font] = font:GetText() end
    end
    local candidates = Candidates(control)
    for candidateIndex, value in ipairs(candidates) do
        local frozenOutcome, frozenReset, derivedResetObserved
        for _, old in ipairs({ true, false }) do
            legacy = old
            Replace(M.EnsureDB(), baseline)
            M.ClearHistory()
            for font, text in pairs(labels) do font:SetText(text) end
            applyLog, tracing = {}, true
            local ok, why = pcall(Drive, control, value)
            tracing, applyDepth = false, 0
            Check(ok, spec.id .. ": " .. tostring(why))
            if old then
                frozenOutcome = { profile = Copy(M.EnsureDB()), history = History(), apply = applyLog }
            else
                local same, difference = Equal(frozenOutcome, { profile = M.EnsureDB(), history = History(), apply = applyLog })
                Check(same, control.frozen.id .. " / " .. spec.id .. ": " .. tostring(difference))
            end
            -- Drive the same section-reset operation the popup calls. The
            -- frozen branch is its former raw-key copy; the new branch uses
            -- the production declaration routing, inside identical history.
            local path = M.ControlSchema.ResolvePath(spec)
            local targetRoot, field = path:match("^([^.]+)%.([^.]+)$")
            if candidateIndex == 1 and targetRoot and scope == "party" then
                local parent, entry = control.widget:GetParent()
                while parent do
                    entry = parent._msuf2CollapsibleEntry
                    if entry then break end
                    parent = parent:GetParent()
                end
                if entry then
                    local shared = M.UnitSectionsShared
                    local factory = shared.FactoryProfile()
                    local conf, defaults = M.EnsureDB()[targetRoot], factory[targetRoot] or {}
                    M.ClearHistory()
                    M.RunWithHistory("Reset section", "section:setter-parity", function()
                        if old then conf[field] = Copy(defaults[field])
                        else shared.RestoreSectionValues(entry, { field }, conf, defaults, true) end
                    end)
                    if not old then derivedResetObserved = true end
                    if old then frozenReset = { profile = Copy(M.EnsureDB()), history = History() }
                    else
                        local same, difference = Equal(frozenReset, { profile = M.EnsureDB(), history = History() })
                        Check(same, control.frozen.id .. " / " .. spec.id .. ": reset " .. tostring(difference))
                    end
                    resets = resets + 1
                end
            end
        end
        Check((frozenReset ~= nil) == (derivedResetObserved == true), spec.id .. ": reset presence changed")
        checks = checks + 1
    end
    local frozenCombat
    for _, old in ipairs({ true, false }) do
        legacy = old
        Replace(M.EnsureDB(), baseline)
        M.ClearHistory()
        combat, setterCalls = true, 0
        local ok, why = pcall(Drive, control, candidates[1])
        combat = false
        Check(ok, spec.id .. ": combat " .. tostring(why))
        -- Native command tiles keep their existing history owner's inner combat
        -- gate. Standard widgets refuse before reaching the schema accessor.
        Check((control.command or setterCalls == 0) and #M.historyUndo == 0, spec.id .. ": combat reached setter/history")
        if control.command then Check(Equal(M.EnsureDB(), baseline), spec.id .. ": combat command wrote profile") end
        if old then frozenCombat = Copy(M.EnsureDB())
        else Check(Equal(frozenCombat, M.EnsureDB()), spec.id .. ": combat refresh changed profile behavior") end
    end
    Replace(M.EnsureDB(), baseline)
    end
end
if #failures > 0 then
    local file = assert(io.open(reportDirectory .. "/f3-parity-" .. flavor .. ".log", "wb"))
    file:write(table.concat(failures, "\n")); file:close()
    error(#failures .. " failures; first: " .. failures[1])
end
local fixtureCount = 0
for _ in pairs(seenFixtures) do fixtureCount = fixtureCount + 1 end
local missing = {}
local unavailable = {
    ["AdvancedColors.9"] = not mw.core.Client.SupportsTapDenied,
    ["SwingTimers.1"] = not mw.core.Client.IsForever,
    ["UnitArenaTrinket.1"] = not mw.core.Client.SupportsUnit("arena"),
    ["UnitSections.17"] = not mw.core.Client.SupportsUnit("boss"),
    ["UnitSections.19"] = not mw.core.Client.SupportsUnit("boss"),
    ["Schema.Unit"] = flavor == "Vanilla", -- only the default Boss/Arena layout rows use this factory
}
for id in pairs(loaded) do
    if not seenFixtures[id] and not unavailable[id] then missing[#missing + 1] = id end
end
table.sort(missing)
assert(#missing == 0, "loaded policies were not replayed: " .. table.concat(missing, ", "))
local reasonFile = assert(io.open(reportDirectory .. "/f3-custom-missing-" .. flavor .. ".txt", "wb"))
for id in pairs(customMissing) do reasonFile:write(id, "\n") end
reasonFile:close()
assert(next(customMissing) == nil, "custom setters without a reason; see " .. reportDirectory .. "/f3-custom-missing-" .. flavor .. ".txt")
local receipt = assert(io.open(reportDirectory .. "/F3-controls-" .. flavor .. ".tsv", "wb"))
receipt:write("Page\tControl\tPolicy\n")
for _, control in ipairs(controls) do receipt:write(control.page, "\t", control.spec.id, "\t", control.frozen.id, "\n") end
receipt:close()
print(("PASS schema setters %s: %d controls, %d scope contexts, %d cases, %d reset replays, %d lazy/sparse resets, %d policies")
    :format(flavor, #controls, scopeChecks, checks, resets, sectionResetChecks, fixtureCount))
