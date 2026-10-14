-- Complete real pilot action inventory, independent of the runtime catalog.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
assert(not arg[3], "original action receipts are immutable")
local original = false
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    world.env.GetSpecialization = function() return 1 end
    world.env.GetSpecializationInfo = function() return 62 end
    world.env.C_SpecializationInfo = { GetSpecialization = function() return 1 end,
        GetSpecializationInfo = function() return 62 end }
    world.widgets.Methods.GetCenter = function() return 500, 500 end
    -- Native ColorSelect rendering only; targets, picker and history remain real.
    local methods = world.widgets.Methods
    for _, kind in ipairs({ "Wheel", "Value" }) do
        methods["SetColor" .. kind .. "Texture"] = function(self, texture) self[kind] = texture end
        methods["SetColor" .. kind .. "ThumbTexture"] = function(self) self[kind .. "Thumb"] = self:CreateTexture() end
        methods["GetColor" .. kind .. "ThumbTexture"] = function(self) return self[kind .. "Thumb"] end
    end
    methods.SetColorRGB = function(self, r, g, b) self.rgb = { r, g, b } end
end })
local M, W, env, core = mw.M, mw.M.Widgets, mw.env, mw.core
local F = core.ProfileFields
core.ProfileRuntime.Apply = function() end
core.MSUF_ApplyGameplayVisuals = function() end
env.MSUF_UFCore_NotifyConfigChanged = function() end
env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
local lines, shortcuts, identities = {}, {}, {}
local sectionEntries = {}
local function Encode(value)
    if type(value) == "table" then
        local keys, out = {}, {}
        for key, item in pairs(value) do
            if type(item) ~= "function" and type(item) ~= "userdata" then keys[#keys + 1] = key end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do out[#out + 1] = tostring(key) .. "=" .. Encode(value[key]) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return type(value) .. ":" .. tostring(value):gsub("[\r\n\t]", " ")
end
local function Row(...)
    local out = {}
    for i = 1, select("#", ...) do out[i] = Encode(select(i, ...)) end
    lines[#lines + 1] = table.concat(out, "\t")
end
local function Resolve(value) if type(value) == "function" then return value() end return value end
local function Visible(widget)
    while widget do
        if not widget:IsShown() then return false end
        widget = widget:GetParent()
    end
    return true
end
local function SectionWanted(page, id)
    return page == "gameplay" or page == "swingtimers" or id:match("^classpower_resource_")
        or id == "transparency" or id == "range_fade"
end
local function Sections(page, open)
    local roots, entries = {}, {}
    for id, section in pairs(M.cache[page].sections or {}) do
        if SectionWanted(page, id) then
            local e = assert(section._msuf2CollapsibleEntry)
            roots[e.outer], entries[#entries + 1] = id, e
            sectionEntries[e.outer] = e
            if open ~= nil then e.SetOpenImmediate(open) end
        end
    end
    mw:RunTimers()
    M.Refresh(M.cache[page].ctx)
    mw:RunTimers()
    return roots, entries
end
local function Label(w)
    return w._msuf2Label and w._msuf2Label:GetText() or w.text and type(w.text) == "table" and w.text:GetText()
        or w.GetText and w:GetText()
end
local function Owner(w)
    return w._msuf2ControlPartOf or w
end
local function Snapshot(page, state, roots)
    local indices = {}
    for _, w in ipairs(mw.world.widgets.frames) do
        local click, mouse = w.GetScript and w:GetScript("OnClick"), w.GetScript and w:GetScript("OnMouseUp")
        if click or mouse then
            local p, id = w, nil
            while p do
                id = roots[p]
                if id then break end
                p = p.GetParent and p:GetParent()
            end
            if id then
                indices[id] = (indices[id] or 0) + 1
                local owner = Owner(w)
                local r, spec = owner._msuf2RuntimeControlRecord, owner._msuf2ControlSchema
                local parent = w:GetParent()
                local e = parent and parent._msuf2CollapsibleEntry
                local chrome = e and (w == e._msuf2SectionActions or w == e._msuf2CustomBadge)
                local sectionEntry = sectionEntries[p]
                local sharedChrome = sectionEntry
                    and (w == sectionEntry._msuf2SectionActions or w == sectionEntry._msuf2CustomBadge)
                local shortcut = parent and parent._msuf2ContextColorShortcut == w
                if not original then
                    if shortcut then
                        spec = assert(w._msuf2ControlSchema, "undeclared real shortcut: " .. page .. "." .. id)
                        local suffix = parent._msuf2ControlCardTitle
                        local expected = "menu2." .. page .. ".section." .. id .. ".expanded.colors"
                        if suffix then expected = "menu2." .. page .. ".section." .. id .. ".colors" end
                        if suffix then expected = expected .. (suffix == "Health Bar" and ".health" or ".resource") end
                        assert(spec.id == expected and spec.kind == "button" and spec.labelKey == Label(w),
                            "shortcut identity/kind/raw label drift: " .. expected)
                        assert(spec.owner == w
                            and spec.get() == w._msuf2ContextColorOptions
                            and spec.gate == w._msuf2RefreshContextColorVisibility,
                            "shortcut replaced installed action/options/relevance owner")
                        OwnerAssert.Button(w, spec)
                        assert(not w._msuf2RuntimeControlRecord and not w._msuf2CommandAction,
                            "no-search shortcut manufactured a catalog/binding row")
                        assert(spec.scope and spec.applyDomain == "contextColors", "shortcut scope/domain lost")
                        if not identities[w] then
                            assert(not identities[spec.id], "duplicate scoped shortcut ID")
                            identities[w], identities[spec.id] = true, w
                        end
                    elseif not sharedChrome then
                        assert(spec, "unowned real action/component: " .. page .. "." .. id .. "." .. tostring(Label(w)))
                        if w == sectionEntry.header then
                            assert(M.Format("%s section", sectionEntry.label:GetText()) == r.label,
                                "real section title lost its raw catalog label")
                        end
                    end
                end
                if spec and spec.action and w == owner then OwnerAssert.Button(w, spec) end
                if spec and spec.kind == "button" and w == owner then OwnerAssert.Button(w, spec) end
                if shortcut then shortcuts[w] = { page = page, section = id } end
                local options = shortcut and w._msuf2ContextColorOptions
                local command = owner._msuf2CommandAction
                local lo, hi
                if r and r.kind == "slider" then lo, hi = owner:GetMinMaxValues() end
                Row("inventory", page, state, id, indices[id], w:GetObjectType(), Label(w),
                    r and r.controlId, r and r.kind, r and r.label, r and r.settingKey, r and r.actionKey,
                    r and r.controlPath, command and command.get and command.get(), lo, hi, owner.valueStep,
                    owner.GetValues and owner:GetValues(), w:IsEnabled(), w:IsShown(), Visible(w),
                    (debug.getinfo(click or mouse, "S").source:match("[^/\\]+$")),
                    options and Resolve(options.title), options and Resolve(options.note), options and options.historySource,
                    options and options.maxTargets, options and options.textSettings,
                    options and w:_msuf2RefreshContextColorVisibility(), chrome and "sectionChrome" or nil)
            end
        end
    end
end
local opened, open = nil, W.OpenColorContextPicker
W.OpenColorContextPicker = function(...)
    opened = open(...)
    return opened
end
local function Probe(page, state)
    for _, w in ipairs(mw.world.widgets.frames) do
        local item = shortcuts[w]
        if item and item.page == page then
            opened = nil
            local spec = w._msuf2ControlSchema
            local action = original and w:GetScript("OnClick") or spec.action
            local before = F.CopySnapshot(env.MSUF_DB)
            local result = action(w, "LeftButton")
            Row("open", page, state, item.section, Label(w), result, opened and opened:IsShown(),
                w:_msuf2RefreshContextColorVisibility())
            if opened and opened:IsShown() then
                Row("picker", page, state, item.section, opened.infoButton._msuf2PickerInfoTitle,
                    opened.infoButton._msuf2PickerInfoText, #opened.owners)
                for i, owner in ipairs(opened.owners) do
                    local r, g, b = owner:GetRGB()
                    Row("target", page, state, item.section, i, owner._msuf2ColorLabel, r, g, b,
                        owner._msuf2ColorHasOpacity, owner.IsEnabled and owner:IsEnabled())
                    -- Exercise actual edit owner; pin its full setting destination and input result.
                    if owner._msuf2BeginColorInteraction then owner:_msuf2BeginColorInteraction() end
                    if owner._msuf2OnColorChanged then owner._msuf2OnColorChanged(.21, .32, .43, .54) end
                    Row("write", page, state, item.section, i, F.Diff(before, env.MSUF_DB))
                    if owner._msuf2CommitColorInteraction then owner:_msuf2CommitColorInteraction() end
                    env.MSUF_DB = F.CopySnapshot(before)
                end
                opened:Finish(true)
                Row("close", page, state, item.section, opened:IsShown())
            end
            env.MSUF_DB = before
            M.ClearHistory()
        end
    end
end
local function Visit(page)
    assert(mw:Select(page))
    if page == "classpower" then M.ClassPowerWorkspace.current:Select("extras") end
    local roots = Sections(page, nil)
    Snapshot(page, "collapsed", roots)
    roots = Sections(page, true)
    Snapshot(page, "cold", roots)
    Probe(page, "cold")
    mw:Select("home")
    assert(mw:Select(page))
    if page == "classpower" then M.ClassPowerWorkspace.current:Select("extras") end
    roots = Sections(page, true)
    Snapshot(page, "warm", roots)
    Probe(page, "warm")
    if page == "classpower" then
        env.MSUF_DB.bars.resourceMarks = { { target = "PLAYER", resource = "ALL", mode = "PERCENT",
            value = 50, width = 2, color = { 1, 1, 1 }, mark = true } }
        M.Refresh(M.cache[page].ctx)
        Snapshot(page, "mark", roots)
        Probe(page, "mark")
    elseif page:match("^uf_") then
        local unit = page:sub(4)
        for _, mode in ipairs({ "dark", "class", "gradient", "unified", "global", "invalid" }) do
            env.MSUF_DB[unit].healthColorMode = mode
            env.MSUF_DB.general.barMode = "gradient"
            env.MSUF_DB.general.enableHealthGradient = true
            for _, matched in ipairs({ false, true }) do
                env.MSUF_DB.general.powerBarBgMatchBarColor = matched
                M.Refresh(M.cache[page].ctx)
                Probe(page, mode .. ":" .. tostring(matched))
            end
        end
        local selector = M.RuntimeControlCatalog.Get("menu2." .. page .. ".unit.transparency.state_selector").widget
        selector:SetValue("ooc")
        Snapshot(page, "ooc", roots)
        Probe(page, "ooc")
        selector:SetValue("combat")
    elseif page == "swingtimers" then
        for _, hand in ipairs({ "main", "off", "ranged" }) do
            core.SwingTimer.menuContext._msuf2SwingTimerPreview.SelectHand(hand)
            Snapshot(page, hand, roots)
            Probe(page, hand)
        end
    end
    core.Util.InCombat("PLAYER_REGEN_DISABLED")
    env.InCombatLockdown = function() return false end
    Probe(page, "combat")
    core.Util.InCombat("PLAYER_REGEN_ENABLED")
    -- Cached actions must resolve the new profile, not captured tables or virtual owners.
    env.MSUF_InitProfiles()
    local active = env.MSUF_ActiveProfile
    env.MSUF_GlobalDB.profiles["Action alternate"] = F.CopySnapshot(env.MSUF_DB)
    assert(env.MSUF_SwitchProfile("Action alternate") == true)
    M.Refresh(M.cache[page].ctx)
    Probe(page, "profile-switch")
    assert(env.MSUF_SwitchProfile(active) == true)
    M.HideSlashMenuAndMinibar(mw.win)
    assert(M.Open(page) ~= false)
    mw:RunTimers()
    roots = Sections(page, false)
    Snapshot(page, "close", roots)
    roots = Sections(page, true)
    Snapshot(page, "reopen", roots)
    Probe(page, "reopen")
end
Visit("gameplay")
Visit("classpower")
for _, unit in ipairs({ "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "boss", "arena" }) do
    if M.pages["uf_" .. unit] then Visit("uf_" .. unit) end
end
if M.pages.swingtimers then Visit("swingtimers") else Row("capability", "swingtimers", false) end
table.sort(lines)
local result = table.concat(lines, "\n") .. "\n"
local f = assert(io.open(root .. "/tools/fixtures/menu-pilot-actions/" .. flavor .. ".tsv", "rb"))
local expected = f:read("*a"):gsub("\r\n", "\n")
f:close()
assert(result == expected, "complete original9c real action/target/owner inventory drift: " .. flavor)
print("menu_pilot_action_owner_smoke " .. flavor .. ": " .. #lines .. " original real action/target rows OK")
