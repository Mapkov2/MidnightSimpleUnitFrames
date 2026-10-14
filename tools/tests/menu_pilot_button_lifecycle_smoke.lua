-- Real pilot controls: central input bindings, exact navigation and diff history.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, nativeButtonLifecycle = true, beforeCore = function(world)
    world.env.GetSpecialization = function() return 1 end
    world.env.GetSpecializationInfo = function() return 62 end
    world.env.C_SpecializationInfo = {
        GetSpecialization = function() return 1 end, GetSpecializationInfo = function() return 62 end,
    }
    world.widgets.Methods.GetCenter = function(frame)
        return (tonumber(frame.left) or 0) + (tonumber(frame.width) or 0) / 2,
            (tonumber(frame.bottom) or 0) + (tonumber(frame.height) or 0) / 2
    end
end })
local M, env, core = mw.M, mw.env, mw.core
local function Check(value, message) assert(value, flavor .. ": " .. message) return value end
local originalOnly = arg[4] == "--actual-oracle"
if not originalOnly then Check(M.ControlSchema, "schema did not load") end
local F = core.ProfileFields
local factory = F.CopySnapshot(env.MSUF_DB)
core.MSUF_CreateFactoryDefaultProfile = function() return F.CopySnapshot(factory) end
core.ProfileRuntime.Apply = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
-- This smoke proves menu-to-apply requests; native UF rendering has its own fixture.
env.MSUF_UFCore_NotifyConfigChanged = function() end
local function Expand(page)
    for _, section in pairs(M.cache[page].sections) do
        local entry = section._msuf2CollapsibleEntry
        if entry then entry.SetOpenImmediate(true) end
    end
    mw:RunTimers()
    M.Refresh(M.cache[page].ctx)
end
local function Control(key, page)
    local record, widget = M.RuntimeControlCatalog.FindBySettingKey(key, page)
    Check(record and widget, "missing real control " .. key)
    Check(widget._msuf2ControlSchema, "control escaped reviewed declarations: " .. key)
    return widget, record
end
local function Visible(widget)
    while widget do
        if not widget:IsShown() then return false end
        widget = widget:GetParent()
    end
    return true
end

local function Pack(...) return { n = select("#", ...), ... } end
local function Action(w) return assert(w._msuf2ControlSchema.action or w._msuf2ControlSchema.set) end
-- Native gameplay rendering is the same seam used by the original action oracle.
core.MSUF_ApplyGameplayVisuals = function() end
local total = 0
local function Compare(a, b, name)
    Check(F.Equal(a, b), "complete button lifecycle drift: " .. name)
    total = total + 1
end
local refreshCalls, applyCalls, selectionCalls = 0, 0, 0
local requestRefresh = M.RequestRefresh
M.RequestRefresh = function(...) refreshCalls = refreshCalls + 1 return requestRefresh(...) end
local selectPreview = M.ResourceExtrasPreview.Select
M.ResourceExtrasPreview.Select = function(...) selectionCalls = selectionCalls + 1 return selectPreview(...) end
local applyGameplay = core.MSUF_RequestGameplayApply
core.MSUF_RequestGameplayApply = function(...) applyCalls = applyCalls + 1 return applyGameplay(...) end
local markDefaults = { target = "PLAYER", resource = "ALL", mode = "PERCENT", value = 50,
    width = 2, color = { 1, 1, 1 }, mark = true }
local function Encode(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys, out = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do out[#out + 1] = tostring(key) .. "=" .. Encode(value[key]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local function Receipt(name, state)
    if arg[5] ~= "--states" then return end
    local row = {}
    for key, value in pairs(state) do
        if key ~= "before" and key ~= "after" and key ~= "undone" and key ~= "redone" then row[key] = value end
    end
    row.changes = F.Diff(state.before, state.after)
    if state.undone then row.undoChanges = F.Diff(state.before, state.undone) end
    if state.redone then row.redoChanges = F.Diff(state.after, state.redone) end
    print("STATE\t" .. name .. "\t" .. Encode(row))
end
local function Marks()
    mw:Select("classpower") M.ClassPowerWorkspace.current:Select("extras") Expand("classpower")
    local prefix = "menu2.classpower.advanced.resource.extras.marks."
    local function Mark(suffix) return assert(M.RuntimeControlCatalog.Get(prefix .. suffix)).widget end
    local selector, width = Mark("select"), Mark("width")
    local initProfiles = env.MSUF_InitProfiles
    initProfiles()
    local active = env.MSUF_ActiveProfile
    local alternate = F.CopySnapshot(env.MSUF_DB)
    alternate.bars.resourceMarks = { (F.CopySnapshot(markDefaults)) }
    alternate.bars.resourceMarks[1].width = 17
    env.MSUF_GlobalDB.profiles["Button alternate"] = alternate
    Check(env.MSUF_SwitchProfile("Button alternate") == true, "mark real profile switch failed")
    local currentCount = #env.MSUF_DB.bars.resourceMarks
    Check(env.MSUF_DB.bars.resourceMarks[1].width == 17, "real profile current mark target lost")
    local w = Mark("add") M.ClearHistory()
    if originalOnly then w:Click("LeftButton", false) else Action(w)(w, "LeftButton", false) end
    Check(#env.MSUF_DB.bars.resourceMarks == currentCount + 1 and env.MSUF_DB.bars.resourceMarks[1].width == 17 and M.Undo(),
        "cached mark action ignored current real profile/history")
    Check(env.MSUF_SwitchProfile(active) == true, "mark real profile return failed")
    local seed = F.CopySnapshot(env.MSUF_DB)
    env.MSUF_InitProfiles = function() end
    local callbackCalls, hookCalls = 0, 0
    for _, suffix in ipairs({ "add", "remove" }) do
        local w = Mark(suffix)
        local handler = w._msuf2OnClickHandler
        w:SetScript("OnClick", function(self, button, down)
            Check(self == w and button == "LeftButton" and down == false, "mark callback inputs/owner lost")
            callbackCalls = callbackCalls + 1
            return handler(self, button, down)
        end)
        w:HookScript("OnClick", function(self) Check(self == w, "late mark hook wrong owner") hookCalls = hookCalls + 1 end)
        for _, count in ipairs({ 0, 1, 3 }) do
            for _, index in ipairs({ 1, 2, 99 }) do
                for _, mode in ipairs({ "normal", "combat", "disabled", "reopen", "profile" }) do
                    local function Run(declared, setter)
                        env.MSUF_DB = F.CopySnapshot(seed)
                        env.MSUF_DB.bars.resourceMarks = {}
                        for i = 1, count do
                            local rule = F.CopySnapshot(markDefaults)
                            rule.width, rule.value = i + 2, i * 13
                            env.MSUF_DB.bars.resourceMarks[i] = rule
                        end
                        selector._msuf2CommandAction.set(index)
                        mw:RunTimers() M.Refresh(M.cache.classpower.ctx)
                        local oldProfile = env.MSUF_DB
                        if mode == "profile" then
                            env.MSUF_DB = F.CopySnapshot(oldProfile)
                            env.MSUF_DB.general.fontSize = 37
                        elseif mode == "reopen" then
                            mw:Select("home") mw:Select("classpower") M.ClassPowerWorkspace.current:Select("extras")
                            Expand("classpower")
                        end
                        core.Util.InCombat(mode == "combat" and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
                        env.InCombatLockdown = function() return false end
                        w:SetEnabled(mode ~= "disabled")
                        M.ClearHistory()
                        local before, selected = F.CopySnapshot(env.MSUF_DB), selector._msuf2CommandAction.get()
                        refreshCalls, applyCalls, selectionCalls, callbackCalls, hookCalls = 0, 0, 0, 0, 0
                        local result
                        if declared then
                            local spec = assert(w._msuf2ControlSchema)
                            result = Pack((setter and assert(spec.set) or Action(w))(w, "LeftButton", false))
                        else result = Pack(w:Click("LeftButton", false)) end
                        mw:RunTimers()
                        local after = F.CopySnapshot(env.MSUF_DB)
                        local state = { before = before, after = after, selectedBefore = selected,
                            selectedAfter = selector._msuf2CommandAction.get(), width = width:GetValue(),
                            refresh = refreshCalls, apply = applyCalls, selection = selectionCalls,
                            callback = callbackCalls, hook = hookCalls, result = result }
                        state.undo = M.Undo() == true
                        state.undone = F.CopySnapshot(env.MSUF_DB)
                        state.redo = M.Redo() == true
                        state.redone = F.CopySnapshot(env.MSUF_DB)
                        local refused = mode == "combat" or mode == "disabled"
                        local changes = not refused and (suffix == "add" or count > 0)
                        Check((not F.Equal(before, after)) == changes, "mark native/declaration mutation/refusal drift")
                        Check(state.undo == changes and state.redo == changes, "mark native/declaration history drift")
                        if changes then
                            Check(F.Equal(before, state.undone) and F.Equal(after, state.redone), "mark undo/redo DB drift")
                        end
                        if mode == "profile" then
                            Check(F.Equal(before.bars, oldProfile.bars), "mark wrote stale profile") end
                        core.Util.InCombat("PLAYER_REGEN_ENABLED") w:SetEnabled(true)
                        return state
                    end
                    local actual = Run(false)
                    Receipt(suffix .. ":" .. count .. ":" .. index .. ":" .. mode, actual)
                    if not originalOnly then
                        Compare(actual, Run(true), suffix .. ":" .. count .. ":" .. index .. ":" .. mode)
                        Compare(actual, Run(true, true), "setter:" .. suffix .. ":" .. count .. ":" .. index .. ":" .. mode)
                    end
                end
            end
        end
        w:SetScript("OnClick", handler)
    end
    env.MSUF_DB = seed env.MSUF_InitProfiles = initProfiles
    print("marks actual/declared selected/no-mark/remove-last/clamp/refusal/history/profile/reopen OK")
end
local function Totem()
    mw:Select("gameplay") Expand("gameplay")
    env.TotemFrame = env.CreateFrame("Frame", nil, env.UIParent)
    M.Refresh(M.cache.gameplay.ctx)
    local w = assert(M.RuntimeControlCatalog.Get("menu2.gameplay.advanced.totem.frame.reset.layout")).widget
    local function Run(declared)
        env.MSUF_DB.gameplay.playerTotemsIconSize = 41 M.ClearHistory()
        local before = F.CopySnapshot(env.MSUF_DB)
        local result = declared and Pack(Action(w)(w, "LeftButton", false)) or Pack(w:Click("LeftButton", false))
        Check(env.MSUF_DB.gameplay.playerTotemsIconSize == 24, "Totem reset no-op")
        local after = F.CopySnapshot(env.MSUF_DB)
        Check(M.Undo() and F.Equal(before, env.MSUF_DB), "Totem separate history hook lost")
        Check(M.Redo() and F.Equal(after, env.MSUF_DB), "Totem reset redo lost")
        return { before = before, after = after, result = result }
    end
    local actual = Run(false)
    Receipt("Totem", actual)
    if not originalOnly then Compare(actual, Run(true), "Totem complete history") end
    print("Totem actual/declared separate hook/history OK")
end
-- Enumerate existing declared action widgets across complete built pages and lazy
-- popups. This does not select actions by labels, a catalog allowlist or a cap.
local function Sweep()
    local pages = { "gameplay", "classpower" }
    for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
        if M.pages["uf_" .. unit] then pages[#pages + 1] = "uf_" .. unit end
    end
    if M.pages.swingtimers then pages[#pages + 1] = "swingtimers" end
    for _, page in ipairs(pages) do
        mw:Select(page)
        if page == "classpower" then M.ClassPowerWorkspace.current:Select("extras") end
        Expand(page)
        if page == "swingtimers" then
            local ui = core.SwingTimer.menuContext._msuf2SwingTimerPreview
            ui.copyPopup.Show(ui.copyButton)
        end
    end
    local count = 0
    for _, w in ipairs(mw.world.widgets.frames) do
        local spec = w._msuf2ControlSchema
        if spec and w:GetScript("OnClick") and (spec.action or spec.kind == "button") then
            OwnerAssert.Button(w, spec)
            count = count + 1
            local oldHandler = w._msuf2RawSetScript and w._msuf2OnClickHandler or w:GetScript("OnClick")
            local oldHooks, copy = w._clientHooks, {}
            for name, hooks in pairs(oldHooks or {}) do
                copy[name] = {} for i, hook in ipairs(hooks) do copy[name][i] = hook end
            end
            w._clientHooks = copy
            local trace, token = {}, {}
            local function Row(name, self, button, down)
                Check(self == w and button == "RightButton" and down == true, "button callback calling convention drift")
                trace[#trace + 1] = name
            end
            for _, name in ipairs({ "PreClick", "OnClick", "PostClick" }) do
                w:HookScript(name, function(self, button, down) Row(name, self, button, down) end)
            end
            local wasEnabled = w:IsEnabled()
            for generation = 1, 2 do
                w:SetScript("OnClick", function(self, button, down)
                    Row("handler" .. generation, self, button, down)
                    return token, nil, false, generation
                end)
                for _, mode in ipairs({ "normal", "disabled", "combat" }) do
                    local function Run(declared)
                        trace = {}
                        w:SetEnabled(mode ~= "disabled")
                        core.Util.InCombat(mode == "combat" and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
                        local result = declared and Pack(Action(w)(w, "RightButton", true)) or Pack(w:Click("RightButton", true))
                        return { trace = table.concat(trace, ","), result = result }
                    end
                    local actual = Run(false)
                    Compare(actual, Run(true), spec.id .. ":late-wrapper-" .. generation .. ":" .. mode)
                    if mode == "normal" then Check(actual.trace == "PreClick,handler" .. generation .. ",OnClick,PostClick",
                        "native complete lifecycle fixture incomplete") end
                    if mode == "disabled" then Check(actual.trace == "", "native disabled fixture executed scripts") end
                end
            end
            core.Util.InCombat("PLAYER_REGEN_ENABLED") w:SetEnabled(wasEnabled)
            w:SetScript("OnClick", oldHandler) w._clientHooks = oldHooks
        end
    end
    Check(count > 0, "complete pilot action inventory empty")
    print("complete native button sweep " .. count .. " owners; late wrappers/hooks/disabled/combat/current inputs/returns OK")
end
local function Minimal()
    -- A minimal button still implements the client API; production has no fake route.
    local w = env.CreateFrame("Button", nil, env.UIParent)
    local calls, hooks = 0, 0
    w:SetScript("OnClick", function(self, button, down)
        calls = calls + 1 return self, button, down
    end)
    w:HookScript("OnClick", function() hooks = hooks + 1 end)
    local dispatch = M.ControlSchema.ButtonAction(w)
    local a, b, d = dispatch({}, "RightButton", true)
    Check(a == w and b == "RightButton" and d == true and calls == 1 and hooks == 1,
        "minimal native owner inputs/returns/hooks lost")
    local nativeClick = w.Click
    w.Click = function(self, button, down)
        Check(self == w and button == "RightButton" and down == true, "minimal current native wrapper inputs lost")
        return "current native", nil, false
    end
    a, b, d = dispatch({}, "RightButton", true)
    Check(a == "current native" and b == nil and d == false, "minimal captured stale native API/returns")
    w.Click = nativeClick
    w:SetScript("OnClick", function() return false, nil, "late" end)
    a, b, d = dispatch(w, "LeftButton", false)
    Check(a == false and b == nil and d == "late" and hooks == 2, "minimal native current handler/returns lost")
    w:Disable()
    dispatch(w, "LeftButton", false)
    Check(hooks == 2, "minimal disabled native owner executed")
    print("minimal faithful native owner/current scripts/hooks/inputs/returns OK")
end
if not arg[3] or arg[3] == "marks" or arg[3] == "semantic" then Marks() end
if not arg[3] or arg[3] == "totem" or arg[3] == "semantic" then Totem() end
if not arg[3] or arg[3] == "sweep" then Sweep() end
if not arg[3] or arg[3] == "minimal" then Minimal() end
print("menu_pilot_button_lifecycle_smoke " .. flavor .. ": " .. total .. " native/declared complete lifecycle comparisons OK")
