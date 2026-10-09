-- rc1_d_smoke.lua <repoRoot> <flavor> <mode>
--
-- rc1 package D: options-menu and profile data fixes, on the client's real
-- load graph (tools/tests/client_world.lua; menu modes through
-- tools/tests/bh3_menu_page_fixture.lua, which builds the real pages hidden).
--
-- textures (DM-1): Party/Raid bar textures. GF.ResolveBarTexture lets an
--   explicit barTextureOverride win and otherwise follows the scope's Custom
--   settings switch (hlOverride). The Group page Copy To wrote an explicit
--   false for a source without any texture flag, and the Bars page read and
--   wrote only hlOverride: a texture picked on the Bars page showed in the
--   dropdown while the frames kept the shared one, and Custom settings off or
--   Reset left a group texture on screen. The Bars page now reads, writes and
--   clears texture ownership by the runtime's rule, and Copy To copies no flag
--   as no flag.
-- owner (C02-K4): a "Selected unitframes" string carries only what the
--   selected frames own. The Colors page's Cast Target Name Color
--   (general.castbarTargetNameR/G/B, read by every castbar) starts with
--   "castbarTarget", so the prefix rule gave it to the Target frame: a
--   Target string exported it and its import replaced or deleted the
--   receiver's colour. The Target castbar's own cast-target colour still
--   travels, and a string made before the fix still imports without it.
-- basics (C26-A1): the Unit page Basics "Reset section" left the legacy
--   per-unit frameBarShape (ROUNDED/SQUARE), which the rounded surface still
--   honours although its picker was removed; the reset now clears it and the
--   rounded state follows at once.
-- anchor (C28-A6): the Combat Timer anchor list offers only frames the client
--   has (Classic Era has no Focus). A stored Focus stays visible and read-only,
--   is not rewritten, and the runtime keeps falling back to the screen centre.
--
-- Plain Lua 5.1, repo root, a flavor (client matrix Suffix or Forever) and a mode.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local mode = assert(arg[3], "mode required: textures, owner, basics or anchor")
local testRoot = root .. "/tools/tests/"

local function Check(condition, message)
    if not condition then error("rc1_d_smoke " .. mode .. " " .. flavor .. ": " .. message, 2) end
    return condition
end

local function Fixture()
    return assert(loadfile(testRoot .. "bh3_menu_page_fixture.lua"))()
end

---------------------------------------------------------------------------
-- DM-1: one texture ownership rule for the Bars page, Copy To and the runtime
---------------------------------------------------------------------------
local function Textures()
    local h = Fixture()
    local M, core, env = h.M, h.MSUF, h.env
    local GF, GroupPage, Global = core.GF, Check(M.GroupPage, "no Group page"), Check(M.GlobalPage, "no Global page")
    local db = env.MSUF_DB
    GF.EnsureDB()
    local names = {}
    for key in pairs(Check(env.MSUF_BUILTIN_BAR_TEXTURES, "no built-in textures")) do names[#names + 1] = key end
    table.sort(names)
    local SHARED, GROUP, BACKGROUND = names[1], names[2], names[3]
    local resolve = core.Require("MSUF_ResolveStatusbarTextureKey", "rc1_d_smoke")
    db.general.barTexture, db.general.barBackgroundTexture = SHARED, ""
    local function Runtime(kind)
        GF.InvalidateConfCache(true)
        return GF.ResolveBarTexture(kind)
    end
    local function RuntimeBg(kind)
        GF.InvalidateConfCache(true)
        return GF.ResolveBarBgTexture(kind)
    end
    Check(resolve(SHARED) ~= resolve(GROUP) and resolve(GROUP) ~= resolve(BACKGROUND), "test textures resolve alike")

    -- The Bars page's own texture controls and scope section, as it builds them.
    local labels, binds, scopeOpts = {}, {}, nil
    local Dropdown, Bind, BuildScope = M.Widgets.Dropdown, M.BindDropdownWidget, Global.BuildScopeOverrideSection
    M.Widgets.Dropdown = function(parent, label, ...)
        local widget = Dropdown(parent, label, ...)
        labels[widget] = label
        return widget
    end
    M.BindDropdownWidget = function(ctx, widget, getValue, setValue, ...)
        if labels[widget] then binds[labels[widget]] = { get = getValue, set = setValue } end
        return Bind(ctx, widget, getValue, setValue, ...)
    end
    Global.BuildScopeOverrideSection = function(ctx, builder, opts)
        scopeOpts = scopeOpts or opts
        return BuildScope(ctx, builder, opts)
    end
    h.BuildPage("opt_bars")
    M.Widgets.Dropdown, M.BindDropdownWidget, Global.BuildScopeOverrideSection = Dropdown, Bind, BuildScope
    local bar = Check(binds["Bar textures (SharedMedia)"], "the Bars page built no bar texture dropdown")
    local background = Check(binds["Background texture"], "the Bars page built no background texture dropdown")
    Check(scopeOpts and scopeOpts.setOverride and scopeOpts.reset and scopeOpts.hasOverride, "the Bars page built no scope section")
    local function Scope(scope) db.general.hpPowerTextSelectedKey = scope end
    -- The Bars page Raid scope covers Raid and (on Midnight) Mythic Raid.
    local function RaidEntries(fields, cleared)
        for _, key in ipairs({ "gf_raid", "gf_mythicraid" }) do
            local entry = db[key]
            if entry then
                for field, value in pairs(fields) do entry[field] = value end
                for _, field in ipairs(cleared or {}) do entry[field] = nil end
            end
        end
    end

    -- 1. Copy To from a Party without any texture flag keeps Raid without one.
    local party, raid = db.gf_party, db.gf_raid
    party.hlOverride, party.barTextureOverride, party.barTexture = nil, nil, nil
    raid.hlOverride, raid.barTextureOverride = true, nil
    Check(GroupPage.CopyGroupSettings("party", "raid", { health = true }), "Copy To Health & Bars failed")
    Check(raid.barTextureOverride == nil, "Copy To wrote barTextureOverride=" .. tostring(raid.barTextureOverride)
        .. " for a source without a texture flag")
    Check(Runtime("raid") == resolve(SHARED), "Copy To changed the raid texture")

    -- 2. A Bars page pick reaches the frames even over an explicit false an
    -- earlier Copy To left behind.
    Scope("gf_raid")
    RaidEntries({ hlOverride = true, barTextureOverride = false })
    bar.set(GROUP)
    Check(bar.get() == GROUP, "the Bars page dropdown shows " .. tostring(bar.get()))
    Check(Runtime("raid") == resolve(GROUP), "Raid frames kept " .. tostring(Runtime("raid")) .. " after a Bars page pick")
    RaidEntries({ barTextureOverride = false }, { "barBackgroundTexture", "barBgTexture" })
    Check(RuntimeBg("raid") ~= resolve(BACKGROUND), "precondition: Raid frames draw the shared background")
    background.set(BACKGROUND)
    Check(RuntimeBg("raid") == resolve(BACKGROUND), "Raid frames kept background " .. tostring(RuntimeBg("raid")))

    -- 3. The dropdown shows what the frames draw: an explicit false wins over a
    -- stale texture under Custom settings.
    RaidEntries({ hlOverride = true, barTextureOverride = false, barTexture = GROUP })
    Check(Runtime("raid") == resolve(SHARED), "precondition: the runtime ignores the stale raid texture")
    Check(bar.get() == SHARED, "the Bars page shows " .. tostring(bar.get()) .. " while Raid frames draw the shared texture")

    -- 4. A texture the frames own without Custom settings (Copy To from a scope
    -- with its own texture) shows in the dropdown.
    RaidEntries({ hlOverride = false, barTextureOverride = true, barTexture = GROUP })
    Check(Runtime("raid") == resolve(GROUP), "precondition: Raid frames draw their own texture")
    Check(bar.get() == GROUP, "the Bars page shows " .. tostring(bar.get()) .. " while Raid frames draw their own texture")

    -- 5. Custom settings off and Reset hand the texture back to Shared.
    Scope("gf_party")
    Check(GroupPage.Set("party", "barTexture", GROUP, "visual"), "the Group page texture pick failed")
    Check(party.barTextureOverride == true and Runtime("party") == resolve(GROUP), "precondition: Party draws its own texture")
    scopeOpts.setOverride(false)
    Check(Runtime("party") == resolve(SHARED), "Custom settings off left " .. tostring(Runtime("party")) .. " on Party frames")
    Check(bar.get() == SHARED, "Custom settings off: the Bars page shows " .. tostring(bar.get()))
    scopeOpts.setOverride(true)
    Check(Runtime("party") == resolve(GROUP) and bar.get() == GROUP, "Custom settings on did not bring the Party texture back")
    Check(GroupPage.Set("party", "barTexture", BACKGROUND, "visual"), "the second Group page texture pick failed")
    Check(party.barTextureOverride == true and Runtime("party") == resolve(BACKGROUND), "precondition: Party draws its own texture again")
    scopeOpts.reset()
    Check(Runtime("party") == resolve(SHARED), "Reset left " .. tostring(Runtime("party")) .. " on Party frames")
    Check(scopeOpts.hasOverride("gf_party") ~= true, "Reset left Party marked as customized")
    print("rc1_d_smoke textures: ok (" .. flavor .. ")")
end

---------------------------------------------------------------------------
-- C02-K4: the shared Cast Target Name Color stays out of Selected unitframes
---------------------------------------------------------------------------
local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local function Owner()
    local World = assert(loadfile(testRoot .. "client_world.lua"))()
    local w = World.New(root, flavor)
    local env, ns = w.env, w.core
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.IsInGroup = function() return false end
    local load = w.LoadFile
    function w:LoadFile(path, addon, namespace)
        if path:match("/State/MSUF_Profiles.lua$") then
            -- The real storage and normalization; the frame renderers behind
            -- the runtime apply are outside this test.
            ns.ProfileRuntime.Apply = function() ns.ProfileVariants.ResolveCurrent() end
        end
        return load(self, path, addon, namespace)
    end
    w:Boot()
    local failure = w:FirstFailure()
    Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))
    env.MSUF_InitProfiles()

    -- The encoder hands back the snapshot it was given; the decoder returns it.
    local captured
    env.MSUF_EncodeCompactTableMSUF3 = function(value) captured = Copy(value); return "MSUF3:captured" end
    env.MSUF_EncodeCompactTable = env.MSUF_EncodeCompactTableMSUF3
    env.MSUF_TryDecodeCompactString = function() return Copy(captured) end
    env.print = function() end
    local function Payload(snapshot)
        return snapshot.msuf6 and snapshot.msuf6.payload or snapshot.payload
    end
    local function SharedColor()
        local r, g, b, custom = env.MSUF_GetCastbarTargetNameColor()
        return string.format("%s,%s,%s,%s", tostring(r), tostring(g), tostring(b), tostring(custom))
    end

    local g = env.MSUF_DB.general
    -- Exporter: a red shared colour and a blue Target-castbar cast-target colour.
    g.castbarTargetNameR, g.castbarTargetNameG, g.castbarTargetNameB = 1, 0, 0
    g.castbarTargetTargetNameColor = { 0, 0, 1 }
    Check(type(env.MSUF_ExportSelectionToString("unitselection", { target = true })) == "string",
        "a Selected unitframes export of Target failed")
    local exported = Payload(captured).general
    Check(exported.castbarTargetNameR == nil and exported.castbarTargetNameG == nil and exported.castbarTargetNameB == nil,
        "the Target-only string carries the shared Cast Target Name Color")
    Check(type(exported.castbarTargetTargetNameColor) == "table", "the Target castbar's own cast-target colour no longer travels")
    local targetOnly = captured

    -- Receiver: a green shared colour survives the import.
    g.castbarTargetNameR, g.castbarTargetNameG, g.castbarTargetNameB = 0, 1, 0
    g.castbarTargetTargetNameColor = nil
    captured = targetOnly
    Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "importing a Target selection was refused")
    g = env.MSUF_DB.general
    Check(SharedColor() == "0,1,0,true", "the Target import changed the shared Cast Target Name Color to " .. SharedColor())
    Check(type(g.castbarTargetTargetNameColor) == "table" and g.castbarTargetTargetNameColor[3] == 1,
        "the Target import did not bring the Target castbar's cast-target colour")

    -- A string from a build that still exported the shared colour imports, and
    -- the colour it carries stays out.
    local legacy = Copy(targetOnly)
    local legacyGeneral = Payload(legacy).general
    legacyGeneral.castbarTargetNameR, legacyGeneral.castbarTargetNameG, legacyGeneral.castbarTargetNameB = 1, 0, 0
    captured = legacy
    Check(env.MSUF_ImportFromString("MSUF3:captured") == true, "a Target string carrying the shared colour was refused")
    Check(SharedColor() == "0,1,0,true", "a string carrying the shared colour replaced it with " .. SharedColor())
    print("rc1_d_smoke owner: ok (" .. flavor .. ")")
end

---------------------------------------------------------------------------
-- C26-A1: Basics "Reset section" clears the legacy per-unit frame bar shape
---------------------------------------------------------------------------
local function Basics()
    local h = Fixture()
    local M, core, env = h.M, h.MSUF, h.env
    local F = Check(core.ProfileFields, "ProfileFields did not load")
    local db = env.MSUF_DB
    -- The harness cannot decode the embedded factory string, so the booted
    -- profile is the factory baseline the reset returns to.
    local factory = Check(F.CopySnapshot(M.EnsureDB()), "booted profile is not snapshot-safe")
    core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
    Check(factory.target and factory.target.frameBarShape == nil, "precondition: the factory Target has no frame bar shape")
    db.bars.roundedFramesEnabled = false
    local entry = h.BuildPage("uf_target")
    h.RunRefreshers(entry)
    local section = Check(entry.sections and entry.sections.frame_basics, "the Target page has no Basics section")
    local more = Check(section._msuf2CollapsibleEntry and section._msuf2CollapsibleEntry._msuf2SectionActions,
        "the Basics section has no section actions")
    for _, shape in ipairs({ "ROUNDED", "SQUARE" }) do
        db.target.frameBarShape = shape
        db.target.smoothFill = not factory.target.smoothFill
        env.MSUF_ApplyRoundedUnitframes()
        if shape == "ROUNDED" then Check(env.MSUF_RoundedUF_Active == true, "precondition: a Rounded Target turns the rounded runtime on") end
        more:GetScript("OnClick")(more)
        Check(more._msuf2GetSectionPopup()._msuf2ResetSection() == true, "Basics Reset section was refused")
        -- The queued unit apply is outside this contract (no timers run); the
        -- reset and its rounded refresh run synchronously.
        Check(db.target.smoothFill == factory.target.smoothFill, "Basics reset no longer restores Smooth fill")
        Check(db.target.frameBarShape == nil, "Basics reset left the hidden frame bar shape " .. tostring(db.target.frameBarShape))
        Check(env.MSUF_RoundedUF_Active == nil, "the rounded runtime still runs for a shape the reset cleared (" .. shape .. ")")
    end
    print("rc1_d_smoke basics: ok (" .. flavor .. ")")
end

---------------------------------------------------------------------------
-- C28-A6: the Combat Timer anchor offers only frames this client has
---------------------------------------------------------------------------
local function Anchor()
    local h = Fixture()
    local M, core, env = h.M, h.MSUF, h.env
    local lists = {}
    local Dropdown = M.Widgets.Dropdown
    M.Widgets.Dropdown = function(parent, label, items, ...)
        if label == "Anchor" then lists[#lists + 1] = items end
        return Dropdown(parent, label, items, ...)
    end
    local g = Check(M.AdvancedPage and M.AdvancedPage.Gameplay, "no Gameplay settings accessor")()
    g.combatTimerAnchor = "none"
    h.BuildPage("gameplay")
    M.Widgets.Dropdown = Dropdown
    Check(#lists == 1, "expected one Combat Timer Anchor dropdown, got " .. #lists)
    local function Offered()
        local items = lists[1]
        if type(items) == "function" then items = items() end
        local out = {}
        for _, item in ipairs(items) do out[item.value] = item end
        return out
    end
    local hasFocus = core.Client.SupportsUnit("focus") == true
    local offered = Offered()
    for _, value in ipairs({ "none", "player", "target" }) do
        Check(offered[value] and offered[value].disabled ~= true, "the anchor list lacks " .. value)
    end
    if hasFocus then
        Check(offered.focus and offered.focus.disabled ~= true, "the anchor list lacks Focus on a client with a focus frame")
    else
        Check(offered.focus == nil, "the anchor list offers Focus on a client without a focus frame")
    end
    -- A stored Focus (an imported profile) stays visible, read-only where the
    -- client has no focus frame, and opening the menu does not rewrite it.
    g.combatTimerAnchor = "focus"
    offered = Offered()
    Check(offered.focus ~= nil, "a stored Focus anchor vanished from the list")
    Check((offered.focus.disabled == true) == not hasFocus, "a stored Focus anchor has the wrong availability")
    Check(g.combatTimerAnchor == "focus", "opening the anchor list rewrote the stored anchor")
    if not hasFocus then
        local frame = core.MSUF_GetCombatTimerAnchorFrame(g)
        Check(frame == env.UIParent, "a stored Focus anchor no longer falls back to the screen")
    end
    print("rc1_d_smoke anchor: ok (" .. flavor .. ")")
end

local MODES = { textures = Textures, owner = Owner, basics = Basics, anchor = Anchor }
Check(MODES[mode], "unknown mode")()
