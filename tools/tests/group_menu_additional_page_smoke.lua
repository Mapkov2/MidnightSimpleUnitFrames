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

    -- Static search rows: offered exactly where the control is built.
    M.frame = { IsShown = function() return true end }
    world.env.InCombatLockdown = function() return false end
    world.env.UnitAffectingCombat = function() return false end
    local api = assert(M.Search and M.Search._CoreAPI, flavor .. ": the search core API did not load")
    local blob = assert(M.Search.StaticIndexBlob, flavor .. ": no static index blob")
    local function Offered(identity)
        local label
        for line in blob:gmatch("[^\n]+") do
            local fields = {}
            for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
            if fields[8] == identity then label = fields[2] end
        end
        assert(label, flavor .. ": the index it loads lost the row " .. identity:gsub("\031", "|"))
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
    assert(toggles["Center party frames while solo"], flavor .. ": the full Layout page did not build")
    assert((toggles["Only while you are a healer"] == true) == hasBoss, flavor .. ": Friendly bosses built against the client's boss support")
    assert((toggles["Hide groups 5–8 in Mythic raids"] == true) == hasMythic,
        flavor .. ": the Mythic raid group cap built against the client's Mythic Raid scope")
    -- Buff coverage (WoW Forever) keeps the missing-buff section's Thorns and glow switches.
    local forever = flavor == "Forever"
    assert((toggles["Thorns only on tanks"] == true) == forever and (toggles["Glow missing icons"] == true) == forever,
        flavor .. ": Buff coverage lost its Thorns only on tanks or Glow missing icons switch")
end

print("group_menu_additional_page_smoke: PASS")
