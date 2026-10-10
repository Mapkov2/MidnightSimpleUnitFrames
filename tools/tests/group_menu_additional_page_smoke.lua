-- group_menu_additional_page_smoke.lua <repoRoot>
--
-- Group Frames > Layout, the additional group sections, built by the real
-- page builders on every client's booted core and Options graph:
--   * the name bar's background opacity saves fractions (shown in percent),
--     not only fully clear or fully opaque;
--   * a section or control a client cannot use is not built there, and its
--     static search rows stay hidden: Friendly bosses need boss units (none
--     on Classic Era and TBC), the Mythic raid group cap needs the Mythic Raid
--     scope (Midnight only).
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg[1], "usage: group_menu_additional_page_smoke.lua <root>"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local function Boot(flavor)
    local world = World.New(root, flavor)
    world.env.MAX_BOSS_FRAMES = 5
    world.env.PET, world.env.TARGET, world.env.HEALER, world.env.BOSS = "Pet", "Target", "Healer", "Boss"
    world:Boot()
    assert(not world:FirstFailure(), flavor .. ": client boot failed")
    local methods = world.widgets.Methods
    for _, name in ipairs({ "EnableKeyboard", "SetAutoFocus", "SetNumeric", "SetMaxLetters", "SetTextInsets", "ClearFocus",
        "SetCursorPosition", "HighlightText", "SetPropagateKeyboardInput", "SetPropagateMouseWheel", "SetValueStep",
        "SetObeyStepOnDrag" }) do
        methods[name] = methods[name] or function() end
    end
    methods.GetFont = methods.GetFont or function() return "Fonts\\FRIZQT__.TTF", 12, "OUTLINE" end
    methods.SetChecked = function(self, value) self.checked = value end
    methods.GetChecked = function(self) return self.checked end
    methods.GetValue = function(self) return self.value or self.minimum or 0 end
    methods.HasFocus = methods.HasFocus or function() return false end
    world.env.MSUF_EnsureDB(true)
    world.env.MSUF_ActiveProfile = "Default"
    world.env.MSUF_GlobalDB = { profiles = { Default = world.env.MSUF_DB }, char = {}, global = {} }
    world.core.GF.EnsureDB()
    return world
end

-- Build one additional section with the real builder; returns its sliders by label.
local function BuildSection(world, builderName)
    local M = world.core.MSUF2
    local W = M.Widgets
    local ctx = { key = "gf_layout", refreshers = {} }
    ctx.entry = { key = "gf_layout", refreshers = ctx.refreshers, frame = world.env.UIParent }
    M.activeKey = "gf_layout"
    local sliders, texts = {}, {}
    local Slider, ToggleAt, Text = W.Slider, W.ToggleAt, W.Text
    W.Slider = function(parent, label, ...)
        local control = Slider(parent, label, ...)
        sliders[label], texts[#texts + 1] = control, label
        return control
    end
    W.ToggleAt = function(parent, label, ...) texts[#texts + 1] = label; return ToggleAt(parent, label, ...) end
    W.Text = function(parent, text, ...) texts[#texts + 1] = text; return Text(parent, text, ...) end
    local builder = { width = 720 }
    function builder:CollapsibleSection(id, title)
        texts[#texts + 1] = title
        local section = world.env.CreateFrame("Frame", nil, world.env.UIParent)
        section._msuf2Width, section._msufTitle = 720, title
        return section
    end
    M.GroupFrameAdditionalSections[builderName](ctx, builder)
    W.Slider, W.ToggleAt, W.Text = Slider, ToggleAt, Text
    return sliders, texts
end

-- Every text the additional sections show is translated in all ten non-English
-- packs (enUS and enGB fall back to the English key itself).
local PACKS = { "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
local packText = {}
for _, pack in ipairs(PACKS) do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Locales/" .. pack .. ".lua", "rb"))
    packText[pack] = handle:read("*a")
    handle:close()
end
local function AssertTranslated(flavor, texts)
    for _, text in ipairs(texts) do
        -- L["key"] lines or ["key"] entries of the MSUF2_* tables copied into L.
        local key = '["' .. text:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"]'
        for _, pack in ipairs(PACKS) do
            assert(packText[pack]:find(key, 1, true), flavor .. ": " .. pack .. " does not translate \"" .. text .. "\"")
        end
    end
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world = Boot(flavor)
    local M, GF = world.core.MSUF2, world.core.GF
    M.gfScope = "party"
    local conf = GF.GetConf("party")

    for _, builderName in ipairs({ "Targets", "Pets", "FriendlyBosses", "HealerMana", "NameBar" }) do
        local _, texts = BuildSection(world, builderName)
        AssertTranslated(flavor, texts)
    end

    -- Name bar opacity: 60 % saves 0.6, 40 % saves 0.4.
    local sliders = BuildSection(world, "NameBar")
    local opacity = assert(sliders["Strip opacity"], flavor .. ": the name bar opacity slider is missing")
    for _, percent in ipairs({ 60, 40, 95 }) do
        opacity:GetScript("OnValueChanged")(opacity, percent)
        world.widgets:RunTimers(100)
        assert(math.abs((tonumber(conf.nameBarAlpha) or -1) - percent / 100) < 1e-9,
            flavor .. ": name bar opacity " .. percent .. " % saved " .. tostring(conf.nameBarAlpha))
    end

    -- A cold search must not inherit the isolated section probes above: those
    -- deliberately build even sections the real page excludes on this client.
    local searchWorld = Boot(flavor)
    local searchMenu = searchWorld.core.MSUF2
    searchMenu.frame = { IsShown = function() return true end }
    searchWorld.env.InCombatLockdown = function() return false end
    searchWorld.env.UnitAffectingCombat = function() return false end
    local api = assert(searchMenu.Search and searchMenu.Search._CoreAPI, flavor .. ": the search core API did not load")
    local blob = assert(searchMenu.Search.StaticIndexBlob, flavor .. ": no static index blob")
    local function Offered(identity)
        local label
        for line in blob:gmatch("[^\n]+") do
            local fields = {}
            for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
            if fields[8] == identity then label = fields[2] end
        end
        if not label then return false end -- Shared index omits rows unsupported by every included client.
        for _, rec in ipairs(api.SearchPages(label)) do
            if rec.searchIdentity == identity then return true end
        end
        return false
    end
    local ID = "id\031gf_layout\031menu2%2Egf_layout%2Egroup%2Efield%2E"
    local hasBoss, hasMythic = flavor ~= "Vanilla" and flavor ~= "TBC", flavor == "Mainline"
    assert(Offered(ID .. "friendlybosshealeronly") == hasBoss and Offered(ID .. "friendlybossenabled") == hasBoss,
        flavor .. ": search disagrees with the Friendly bosses section's client support")
    assert(Offered(ID .. "hidemythicgroupsfivetoeight") == hasMythic,
        flavor .. ": search disagrees with the Mythic raid group cap's client support")

    -- The real page, every section built at once.
    local toggles = {}
    local Color, inlineManaColors = M.Widgets.Color, 0
    M.Widgets.Color = function(parent, label, ...)
        if parent._msuf2SectionId == "healer_mana" then inlineManaColors = inlineManaColors + 1 end
        return Color(parent, label, ...)
    end
    local ToggleAt = M.Widgets.ToggleAt
    M.Widgets.ToggleAt = function(parent, label, ...)
        toggles[label] = true
        return ToggleAt(parent, label, ...)
    end
    local lazy = M.UnitPage.BuildSectionLazy
    M.UnitPage.BuildSectionLazy = nil
    local content = world.env.CreateFrame("Frame", nil, world.env.UIParent)
    content:SetSize(760, 4000)
    local ctx = { key = "gf_layout", refreshers = {}, content = content, frame = content }
    ctx.entry = { key = "gf_layout", refreshers = ctx.refreshers, frame = content, content = content }
    M.pages.gf_layout.build(ctx)
    M.UnitPage.BuildSectionLazy, M.Widgets.ToggleAt = lazy, ToggleAt
    M.Widgets.Color = Color
    assert(inlineManaColors == 0, flavor .. ": healer mana retained an inline color control")
    assert(toggles["Center party frames while solo"], flavor .. ": the full Layout page did not build")
    assert((toggles["Only while you are a healer"] == true) == hasBoss, flavor .. ": Friendly bosses built against the client's boss support")
    assert((toggles["Hide groups 5–8 in Mythic raids"] == true) == hasMythic,
        flavor .. ": the Mythic raid group cap built against the client's Mythic Raid scope")
    -- Buff coverage (WoW Forever) keeps the missing-buff section's Thorns and glow switches.
    local forever = flavor == "Forever"
    assert((toggles["Thorns only on tanks"] == true) == forever and (toggles["Glow missing icons"] == true) == forever,
        flavor .. ": Buff coverage lost its Thorns only on tanks or Glow missing icons switch")

    -- The Colors control and the semantic three-dot target share storage,
    -- rebuild applies and cancel restores all group scopes.
    local colorContent = world.env.CreateFrame("Frame", nil, world.env.UIParent)
    colorContent:SetSize(760, 1600)
    local colorCtx = { key = "opt_colors", refreshers = {}, content = colorContent, frame = colorContent }
    colorCtx.entry = { key = "opt_colors", refreshers = colorCtx.refreshers, frame = colorContent, content = colorContent }
    local manaColor
    M.Widgets.Color = function(parent, label, ...)
        local control = Color(parent, label, ...)
        if parent._msuf2SectionId == "colors_group_frames_healer_mana" then manaColor = control end
        return control
    end
    M.ColorsPage.BuildGroupFrameColors(colorCtx, M.Widgets.PageBuilder(colorCtx))
    M.Widgets.Color = Color
    assert(manaColor, flavor .. ": Colors menu lost the healer mana text color")
    manaColor._msuf2OnColorChanged(.2, .4, .6)
    local targets = M.ResolveContextColorReferences({ "group.healer_mana_text" })
    assert(#targets == 1, flavor .. ": healer mana three-dot target missing")
    local target = targets[1]
    local r, g, b = target.getRGB()
    assert(r == .2 and g == .4 and b == .6, flavor .. ": central and contextual color diverged")
    local previous = target.captureState()
    target.setRGB(.7, .8, .9)
    for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
        local conf = GF.GetConf(scope)
        assert(conf.healerManaTextR == .7 and conf.healerManaTextG == .8 and conf.healerManaTextB == .9,
            flavor .. ": contextual color missed " .. scope)
    end
    target.restoreState(previous)
    r, g, b = target.getRGB()
    assert(r == .2 and g == .4 and b == .6, flavor .. ": contextual Cancel lost the prior text color")

    -- The cold Layout page exposes masters before any additional body builds.
    -- Opening a body must keep the same command; scope changes refresh that master.
    local masters = {
        name_bar = "nameBarEnabled", party_targets = "targetsEnabled", group_pets = "petsEnabled",
        healer_mana = "healerManaEnabled",
    }
    if hasBoss then masters.friendly_bosses = "friendlyBossEnabled" end
    if forever then masters.buff_coverage = "buffCoverageEnabled" end
    M.gfScope = "party"
    local raidConf = GF.GetConf("raid")
    for _, key in pairs(masters) do conf[key], raidConf[key] = true, false end
    local state = M.GetPersistentMenuStateTable("accordionState")
    for id in pairs(masters) do state["gf_layout:" .. id] = false end
    local coldContent = world.env.CreateFrame("Frame", nil, world.env.UIParent)
    coldContent:SetSize(760, 4000)
    local coldCtx = { key = "gf_layout", refreshers = {}, content = coldContent, frame = coldContent }
    coldCtx.entry = { key = "gf_layout", refreshers = coldCtx.refreshers, frame = coldContent, content = coldContent }
    M.pages.gf_layout.build(coldCtx)
    for id, key in pairs(masters) do
        local section = assert(coldCtx.entry.sections[id], flavor .. ": missing section " .. id)
        local entry = section._msuf2CollapsibleEntry
        local toggle = assert(entry.featureSwitch, flavor .. ": closed section has no master " .. id)
        assert(not entry.open and toggle:GetParent() == entry.header, flavor .. ": master is not in closed header " .. id)
        assert(toggle:GetChecked() == true, flavor .. ": header missed saved Party value " .. id)
        toggle:GetScript("OnClick")(toggle, "LeftButton")
        assert(conf[key] == false and raidConf[key] == false, flavor .. ": header did not toggle only Party " .. id)
        toggle:GetScript("OnClick")(toggle, "LeftButton")
        assert(conf[key] == true, flavor .. ": closed header cannot re-enable " .. id)
        entry.open = true
        entry._msuf2RefreshState(entry)
        assert(entry.featureSwitch == toggle, flavor .. ": body replaced header binding " .. id)
        M.gfScope = "raid"
        for _, refresh in ipairs(coldCtx.refreshers) do refresh() end
        assert(toggle:GetChecked() == false, flavor .. ": header retained stale Party state " .. id)
        toggle:GetScript("OnClick")(toggle, "LeftButton")
        assert(raidConf[key] == true and conf[key] == true, flavor .. ": header did not use current Raid scope " .. id)
        raidConf[key] = false
        M.gfScope = "party"
        for _, refresh in ipairs(coldCtx.refreshers) do refresh() end
    end

end

-- Exercise real cold headers and first-open construction with all features off.
-- Existing probes above covered the master binding, but not its body controls.
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local mw = MenuWorld.Open(root, flavor, {
        page = "home", clientScriptBindings = true,
        beforeOptions = function(world)
            world.env.MSUF_EnsureDB()
            for _, scope in ipairs({ "gf_party", "gf_raid", "gf_mythicraid" }) do
                local conf = world.env.MSUF_DB[scope]
                conf.enabled = true
                for _, key in ipairs({ "nameBarEnabled", "targetsEnabled", "petsEnabled",
                    "friendlyBossEnabled", "healerManaEnabled", "buffCoverageEnabled" }) do
                    conf[key] = false
                end
            end
        end,
    })
    local M, W, T = mw.M, mw.M.Widgets, mw.M.Theme
    mw.env.MSUF_UFCore_NotifyConfigChanged = function() return true end
    mw.env.GameTooltip.SetOwner = function() end
    mw.env.GameTooltip.AddLine = function() end
    local masters = {
        name_bar = "nameBarEnabled", party_targets = "targetsEnabled", group_pets = "petsEnabled",
        friendly_bosses = "friendlyBossEnabled", healer_mana = "healerManaEnabled", buff_coverage = "buffCoverageEnabled",
    }
    local state = M.GetPersistentMenuStateTable("accordionState")
    for id in pairs(masters) do state["gf_layout:" .. id] = false end
    mw:Select("gf_layout")
    local function BodyState(section, enabled, phase, masterEnabled)
        local count = 0
        M.ControlGates.ForEachControl(section, nil, function(control)
            count = count + 1
            assert((control:IsEnabled() and true or false) == enabled,
                flavor .. "/" .. M.gfScope .. "/" .. section._msuf2SectionId .. ": " .. phase .. " input state")
            local color = enabled and T.colors.text or T.colors.disabled
            for _, label in ipairs({ control._msuf2Title or false, control._msuf2Label or false }) do
                if label then
                    local r, g, b = label:GetTextColor()
                    assert(r == color[1] and g == color[2] and b == color[3], phase .. ": label did not grey/restore")
                end
            end
            local edit = control.editBox or control.__MSUF_valueBox
            if edit then assert((edit:IsEnabled() and true or false) == enabled, phase .. ": value input still editable") end
            for _, step in ipairs(control._msuf2StepButtons or {}) do
                assert((step:IsEnabled() and true or false) == enabled, phase .. ": step button still editable")
            end
        end)
        assert(count >= 3, phase .. ": additional body did not build its controls")
        if masterEnabled == nil then masterEnabled = true end
        assert((section._msuf2CollapsibleEntry.featureSwitch:IsEnabled() and true or false) == masterEnabled,
            phase .. ": feature master state")
    end
    for _, scope in ipairs({ "party", "raid", "mythicraid" }) do
        if M.SupportsFrameScope(scope) then
            local selector
            for _, frame in ipairs(mw.world.widgets.frames) do
                if frame._msuf2GuidedSelectScope then selector = frame end
            end
            assert(selector, "group scope selector missing")._msuf2GuidedSelectScope(scope)
            mw:RunTimers()
            assert(M.gfScope == scope, "group scope selector failed")
            local sections = assert(M.cache.gf_layout.sections)
            for id, key in pairs(masters) do
                local section = sections[id]
                if section then
                    local entry = section._msuf2CollapsibleEntry
                    local toggle = assert(entry.featureSwitch)
                    if entry.open then entry.header:Click("LeftButton") end
                    assert(not toggle:GetChecked(), id .. ": fixture feature already enabled")
                    entry.header:Click("LeftButton")
                    mw:RunTimers()
                    BodyState(section, false, id .. " first open while off")
                    toggle:Click("LeftButton")
                    mw:RunTimers()
                    assert(mw.core.GF.GetConf(scope)[key] == true, id .. ": master did not save")
                    BodyState(section, true, id .. " enable while open")
                    -- Another master must not unlock this feature's disabled body.
                    for otherId in pairs(masters) do
                        local other = sections[otherId]
                        if other and other ~= section and other._msuf2CollapsibleEntry.open then
                            BodyState(other, false, otherId .. " independent gate")
                        end
                    end
                    entry.header:Click("LeftButton")
                    toggle:Click("LeftButton")
                    mw:RunTimers()
                    entry.header:Click("LeftButton")
                    mw:RunTimers()
                    BodyState(section, false, id .. " reopen after disable")
                    M.GroupPage.RefreshContext({ entry = M.cache.gf_layout, key = "gf_layout" })
                    mw:RunTimers()
                    BodyState(section, false, id .. " page refresh")
                end
            end
            -- A feature's own on-state must never clear the parent frame gate.
            local nameBar = assert(sections.name_bar)
            local nameToggle = nameBar._msuf2CollapsibleEntry.featureSwitch
            nameToggle:Click("LeftButton")
            mw:RunTimers()
            local frameToggle = assert(sections.general._msuf2CollapsibleEntry.featureSwitch)
            frameToggle:Click("LeftButton")
            mw:RunTimers()
            M.GroupPage.RefreshContext({ entry = M.cache.gf_layout, key = "gf_layout" })
            mw:RunTimers()
            BodyState(nameBar, false, "parent frame disabled", false)
            frameToggle:Click("LeftButton")
            mw:RunTimers()
            BodyState(nameBar, true, "parent frame restored")
            nameToggle:Click("LeftButton")
            mw:RunTimers()
            BodyState(nameBar, false, "feature remains independently disabled")
        end
    end
end

print("group_menu_additional_page_smoke: PASS")
