-- arena_trinket_preview_smoke.lua <repoRoot> <flavor>
--
-- The enemy arena PvP trinket icon is placed by settings now (size, side, X/Y,
-- 0-30 layer, the show switch) and appears in every arena preview. One client
-- per run, placed by the real Game/Shared/Initialize.lua in a client_world
-- sandbox; the real trinket runtime, layer scale, unit defaults, Arena page
-- section and Layer Overview run against a recorded EventBus.
--
--   1. The factory profile reproduces the original icon: 20 px, LEFT of the
--      icon on the arena frame's RIGHT, +4/0, drawn above every factory layer
--      of the arena frame (custom aura containers sit on 9).
--   2. Arena events never re-place the icon (comparison only, no layout write,
--      no update script); a unit-frame apply of the arena scope (what
--      Factory.Apply calls) carries new size, side, offset and layer to it.
--   3. The menu's unit preview paints its icon from the same resolver: same
--      points and layer, scaled with the mock, and the fit footprint grows by
--      the same rectangle.
--   4. The arena frame preview of the menu and of MSUF Edit Mode is the live
--      holder itself: every forced arena frame shows it with the sample swipe,
--      anchored by the runtime geometry, and releasing the preview hides it.
--   5. The show switch hides the live icon, the frame preview and the menu
--      preview; the PvP Trinket section binds all six keys and the Layer
--      Overview lists the trinket layer.
-- Clients without arena frames (Classic Era, WoW Forever) wire nothing and
-- list nothing. Plain Lua 5.1.
local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = flavor .. ": " .. message end
    return condition
end

local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "missing " .. relative)
    local source = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return source
end

-- Body of the named function: from its header to the next line starting "end".
local function Body(source, header)
    local start = source:find(header, 1, true)
    if not start then return "" end
    local stop = source:find("\nend\n", start, true) or #source
    return source:sub(start, stop)
end

local CORE = root .. "/MidnightSimpleUnitFrames/"
local OPTIONS = root .. "/MidnightSimpleUnitFrames_Options/"
local ADDON = "MidnightSimpleUnitFrames"

local world = World.New(root, flavor)
local env = world.env
local ns = {}
local function Load(path)
    local ok, message = world:LoadFile(path, ADDON, ns)
    assert(ok, flavor .. ": " .. path .. ": " .. tostring(message))
end

-- Client facts first, as every core TOC loads them.
Load(CORE .. "Game/Shared/Initialize.lua")
local client = assert(ns.Client, flavor .. ": no client model")
ns.ExportPublic = function(name, value)
    env[name] = value
    return value
end
Load(CORE .. "Kernel/MSUF_Require.lua")
Load(CORE .. "Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")
local Layers = ns.UF.Layers

-- The factory unit defaults, filled by the real stage.
Load(CORE .. "State/Defaults/MSUF_Defaults_Units.lua")
local stages = ns.DefaultsStageFactories.Units({
    MSUF_DEFAULT_ARENA_OFFSET_X = 0, MSUF_DEFAULT_ARENA_OFFSET_Y = 0,
    MSUF_DEFAULT_BOSS_OFFSET_X = 0, MSUF_DEFAULT_BOSS_OFFSET_Y = 0,
    MSUF_Defaults_NormalizePortraitClassStyleValue = function(value) return value end,
    MSUF_Defaults_NormalizePortraitRenderValue = function(value) return value end,
})
local profile = {}
stages.MSUF_Defaults_Stage_FillUnitFrameDefaults(profile)
env.MSUF_DB = profile
local arena = profile.arena

-- The client side of an arena match: the opponent units that exist, the match
-- state and the recorded EventBus.
local live = {}
local inArena = false
local now = 500
local bus = {}
env.GetTime = function() return now end
env.issecretvalue = function() return false end
env.UnitExists = function(unit) return live[unit] == true end
env.IsInInstance = function() return inArena, inArena and "arena" or "none" end
env.C_PvP = {
    IsMatchConsideredArena = function() return inArena end,
    IsMatchActive = function() return inArena end,
    IsMatchComplete = function() return false end,
    GetActiveMatchState = function() return inArena and 3 or 0 end,
    RequestCrowdControlSpell = function() end,
    GetArenaCrowdControlInfo = function() return nil end,
}
env.CombatLogGetCurrentEventInfo = function() return nil end
for index = 1, 5 do env["CompactArenaFrameMember" .. index] = false end
env.MSUF_EventBus_Register = function(event, key, handler)
    bus[event] = bus[event] or {}
    bus[event][key] = handler
    return true
end
env.MSUF_EventBus_Unregister = function(event, key)
    if bus[event] then bus[event][key] = nil end
end
local function Fire(event, ...)
    for _, handler in pairs(bus[event] or {}) do handler(event, ...) end
end

-- Arena frames as the factory builds them: children of the LOW-strata pet
-- battle hider, so they draw on LOW.
local slots = tonumber(client.MaxArenaOpponents) or 0
local frames = {}
for index = 1, 5 do
    local frame = env.CreateFrame("Button", "MSUF_arena" .. index, env.UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetFrameLevel(3)
    frame:SetSize(180, 30)
    frames["arena" .. index] = frame
end
ns.UF.GetFrame = function(unit) return frames[unit] end
ns.Secrets = { UnitExistsPlain = function(unit) return live[unit] == true end }

Load(CORE .. "Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua")
local Trinkets = ns.ArenaTrinkets

-- The Arena page section and the menu preview painter; the menu namespace is
-- the core one, as MSUF_OptionsLOD_Bootstrap.lua links it.
env.MSUF_PixelLayoutRegion = function(region) return region end
local registered
local writes = {}
local function Write(unit, key, value, _, opts)
    writes[#writes + 1] = { unit = unit, key = key, value = value, preview = opts and opts.preview }
    profile[unit][key] = value
end
ns.MSUF2 = {
    Widgets = {},
    UnitPage = {
        RegisterSection = function(spec) registered = spec end,
        ReadBool = function(unit, key, default)
            local value = profile[unit][key]
            if value == nil then return default end
            return value == true
        end,
        ReadNumber = function(unit, key, default) return tonumber(profile[unit][key]) or default end,
        SetBool = Write, SetNumber = Write, SetString = Write,
        GetConf = function(unit) return profile[unit] end,
        SettingMeta = function(_, path, unit, key) return { path = path, settingKey = unit .. "." .. key } end,
    },
}
Load(OPTIONS .. "Shell/Menu2/Pages/MSUF_Menu2_UnitArenaTrinket.lua")
local M = ns.MSUF2

-- The sandbox does not publish frame names, so holders are found by name.
local function Holder(index)
    local name = "MSUF_ArenaTrinket" .. index
    for _, frame in ipairs(world.widgets.frames) do
        if frame.frameName == name then return frame end
    end
end

-- Every write that places or stacks a holder, counted per holder.
local layoutWrites = 0
local function CountLayout(holder)
    if not holder or holder._smokeCounted then return end
    holder._smokeCounted = true
    for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetSize", "SetFrameStrata", "SetFrameLevel" }) do
        local original = holder[method]
        holder[method] = function(...)
            layoutWrites = layoutWrites + 1
            return original(...)
        end
    end
end

local function Geometry(region)
    local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y,
        width = region:GetWidth(), height = region:GetHeight(), level = region:GetFrameLevel(),
        strata = region:GetFrameStrata(), points = region:GetNumPoints() }
end

local function CheckPlacement(holder, frame, point, relativePoint, x, y, size, layer, context)
    local g = Geometry(holder)
    Check(g.points == 1 and g.point == point and g.relativeTo == frame and g.relativePoint == relativePoint
        and g.x == x and g.y == y,
        context .. ": icon placed at " .. tostring(g.point) .. "/" .. tostring(g.relativePoint) .. " "
            .. tostring(g.x) .. "," .. tostring(g.y) .. " instead of " .. point .. "/" .. relativePoint .. " " .. x .. "," .. y)
    Check(g.width == size and g.height == size, context .. ": icon size " .. tostring(g.width) .. " instead of " .. size)
    Check(g.strata == frame:GetFrameStrata(), context .. ": icon strata " .. tostring(g.strata) .. " is not the arena frame's")
    local level = Layers.ElementLevel(layer, 10, 0)
    Check(g.level == level, context .. ": icon level " .. tostring(g.level) .. " is not layer " .. layer .. " (" .. level .. ")")
    Check(holder.cooldown:GetFrameLevel() == level + 1, context .. ": the swipe is not one level above its icon")
end

if slots == 0 then
    -- Classic Era and WoW Forever: no arena frames, so nothing listens and no
    -- holder or row exists.
    Check(client.SupportsUnit("arena1") == false, "a client without arena slots reports arena1 as supported")
    Check(next(bus) == nil, "the trinket runtime subscribed events on a client without arena frames")
    env.MSUF_ArenaTrinkets_SyncPreview()
    env.MSUF_ArenaTrinkets_RefreshLayout("arena")
    Check(Holder(1) == nil, "a trinket holder was created on a client without arena frames")
else
    Check(slots == (flavor == "Mainline" and 3 or 5), "unexpected arena slot count " .. slots)

    ---------------------------------------------------------------- 1. factory look
    Check(arena.showTrinket == true and arena.trinketSize == 20 and arena.trinketAnchor == "RIGHT"
        and arena.trinketOffsetX == 4 and arena.trinketOffsetY == 0 and arena.trinketLayer == 10,
        "the factory profile does not seed the original trinket placement")
    inArena, live.arena1 = true, true
    Fire("PLAYER_LOGIN")
    local holder = Holder(1)
    Check(holder and holder:IsShown(), "the live arena1 trinket is hidden in an arena match")
    CheckPlacement(holder, frames.arena1, "LEFT", "RIGHT", 4, 0, 20, 10, "factory profile")
    Check(holder:GetFrameLevel() > Layers.ElementLevel(9, 0, Layers.ELEMENT_DETAIL_MAX),
        "the factory layer no longer draws the icon above every factory layer of the arena frame")
    Check(Holder(2) and not Holder(2):IsShown(), "an arena slot without an opponent shows a trinket")

    ---------------------------------------------------------------- 2. cold path only
    arena.trinketSize, arena.trinketAnchor, arena.trinketOffsetX, arena.trinketOffsetY, arena.trinketLayer =
        32, "LEFT", -6, 3, 2
    for index = 1, slots do CountLayout(Holder(index)) end
    for _ = 1, 25 do
        Fire("ARENA_COOLDOWNS_UPDATE")
        Fire("ARENA_OPPONENT_UPDATE", "arena1", "seen")
        Fire("ARENA_CROWD_CONTROL_SPELL_UPDATE", "arena1", 0, 0)
    end
    Check(layoutWrites == 0, "arena events re-placed the icon " .. layoutWrites .. " times (settings belong to the cold path)")
    CheckPlacement(holder, frames.arena1, "LEFT", "RIGHT", 4, 0, 20, 10, "after arena events")
    env.MSUF_ArenaTrinkets_RefreshLayout("player")
    Check(layoutWrites == 0, "a player-frame apply re-placed the arena trinket")
    env.MSUF_ArenaTrinkets_RefreshLayout("arena")
    CheckPlacement(holder, frames.arena1, "RIGHT", "LEFT", -6, 3, 32, 2, "arena apply")
    for _, frame in ipairs(world.widgets.frames) do
        Check(not (frame.scripts and frame.scripts.OnUpdate), "a frame runs an OnUpdate script")
    end
    local factory = Body(Read("MidnightSimpleUnitFrames/UnitFrames/Engine/MSUF_UF_Factory.lua"), "function Factory.Apply(unit, applyMask)")
    Check(factory:find('Dep("MSUF_ArenaTrinkets_RefreshLayout")(unit)', 1, true),
        "Factory.Apply does not carry unit-frame applies to the trinket holders")

    ---------------------------------------------------------------- 3. menu unit preview
    local mock = env.CreateFrame("Frame", nil, env.UIParent)
    local function S(value) return math.floor((tonumber(value) or 0) * 2 + 0.5) end
    Check(M.ArenaTrinketPreview.Paint(mock, "arena", true, S) == true, "the arena unit preview paints no trinket")
    local icon = mock._msufArenaTrinketPreview
    local live1 = Geometry(holder)
    local shown = Geometry(icon)
    Check(icon:IsShown() and shown.point == live1.point and shown.relativeTo == mock and shown.relativePoint == live1.relativePoint
        and shown.x == S(live1.x) and shown.y == S(live1.y) and shown.width == S(live1.width) and shown.height == S(live1.height),
        "the unit preview icon is not the live geometry at preview scale")
    Check(shown.level == live1.level, "the unit preview icon is not on the live layer")
    local footprint
    M.ArenaTrinketPreview.Footprint(0, 180, 0, 30, 180, 30, function(...)
        footprint = { ... }
        return 0, 180, 0, 30
    end)
    Check(footprint and footprint[5] == live1.point and footprint[6] == live1.relativePoint and footprint[7] == live1.x
        and footprint[8] == live1.y and footprint[9] == live1.width and footprint[11] == 180 and footprint[12] == 30,
        "the preview footprint does not grow by the live trinket rectangle")
    Check(M.ArenaTrinketPreview.Paint(mock, "arena", false, S) == true and not icon:IsShown(),
        "a hidden Status layer did not hide the preview icon or dropped the layer")
    Check(M.ArenaTrinketPreview.Paint(mock, "boss", true, S) == false and not icon:IsShown(),
        "a non-arena preview offers or shows the trinket")
    local render = Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
    local refresh = Body(render, "function Preview.Refresh(box, reason)")
    local auras, painted = refresh:find("Stage.RenderAurasAndStatus(st, Preview)", 1, true), refresh:find("Stage.RenderArenaTrinket(st)", 1, true)
    Check(auras and painted and auras < painted, "the unit preview refresh does not paint the trinket after Status")
    Check(Body(render, "function Stage.MeasureLayerFootprint(st)"):find("arenaTrinket.Footprint(", 1, true),
        "the unit preview fit ignores the trinket footprint")

    ---------------------------------------------------------------- 4. arena frame preview (menu page and Edit Mode)
    inArena, live.arena1 = false, nil
    Fire("PLAYER_ENTERING_WORLD")
    Check(not holder:IsShown(), "the trinket stayed shown after leaving the arena")
    for index = 1, slots do frames["arena" .. index]._msufArenaPreviewForced = true end
    env.MSUF_ArenaTrinkets_SyncPreview()
    for index = 1, slots do
        local previewHolder = Holder(index)
        local context = "arena" .. index .. " preview"
        Check(previewHolder and previewHolder:IsShown(), context .. ": the forced arena frame shows no trinket")
        if previewHolder then
            CheckPlacement(previewHolder, frames["arena" .. index], "RIGHT", "LEFT", -6, 3, 32, 2, context)
            Check(previewHolder.icon.texture == Trinkets.FallbackTexture, context .. ": the preview does not show the stock trinket icon")
            Check(previewHolder.cooldown.cooldownDuration == 120 and previewHolder.cooldown.cooldownStart == now - 42,
                context .. ": the preview has no sample swipe")
        end
    end
    local conditions = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua")
    for _, header in ipairs({ "local function ApplyArenaPreviewFrames(active)", "local function ClearArenaPreviewFramesForCombat()" }) do
        Check(Body(conditions, header):find('MSUF.Require("MSUF_ArenaTrinkets_SyncPreview"', 1, true),
            "the arena preview owner does not sync the trinkets in " .. header)
    end

    ---------------------------------------------------------------- 5. the show switch, the section and the overview
    Check(registered and registered.id == "pvp_trinket" and registered.placement == "after_inline_text"
        and registered.units and registered.units.arena == true and registered.units.boss == nil,
        "the PvP Trinket section is not registered for the Arena page only")
    local controls, gate = {}, nil
    local W = M.Widgets
    W.ControlCard = function() return env.CreateFrame("Frame", nil, env.UIParent) end
    M.RefreshProxy = function()
        local target
        return function(candidate)
            if type(candidate) == "function" then target = candidate return candidate end
            if target then return target() end
        end
    end
    M.BindToggleAt = function(_, _, label, _, _, _, get, set, meta)
        controls[#controls + 1] = { label = label, get = get, set = set, meta = meta }
        return env.CreateFrame("CheckButton")
    end
    M.BindSliderAt = function(_, _, label, _, _, low, high, _, _, get, set, meta)
        controls[#controls + 1] = { label = label, get = get, set = set, meta = meta, low = low, high = high }
        return env.CreateFrame("Slider")
    end
    M.BindDropdownAt = function(_, _, label, _, _, values, _, get, set, meta)
        controls[#controls + 1] = { label = label, get = get, set = set, meta = meta, values = values }
        return env.CreateFrame("Frame")
    end
    M.BindGateGroup = function(_, source, entries)
        gate = { source = source, entries = entries }
        return function() end
    end
    M.AddTooltip = function() end
    local section = env.CreateFrame("Frame", nil, env.UIParent)
    registered.build({ width = 720 }, { CollapsibleSection = function() return section end }, "arena")
    local byKey = {}
    for _, control in ipairs(controls) do byKey[control.meta and control.meta.settingKey or "?"] = control end
    for _, key in ipairs({ "showTrinket", "trinketSize", "trinketAnchor", "trinketOffsetX", "trinketOffsetY", "trinketLayer" }) do
        Check(byKey["arena." .. key], "the PvP Trinket section has no control for arena." .. key)
    end
    local layerControl = byKey["arena.trinketLayer"]
    Check(layerControl and layerControl.label == "Layer" and layerControl.low == 0 and layerControl.high == 30,
        "the trinket layer control is not a 0-30 Layer slider")
    Check(byKey["arena.trinketAnchor"] and #byKey["arena.trinketAnchor"].values == 4, "the side choice does not offer four sides")
    Check(gate and #gate.entries == 1 and #gate.entries[1].controls == 5, "the show switch does not gate the five placement controls")
    if byKey["arena.trinketSize"] and byKey["arena.trinketLayer"] then
        byKey["arena.trinketSize"].set(26)
        byKey["arena.trinketLayer"].set(14)
        Check(arena.trinketSize == 26 and arena.trinketLayer == 14 and writes[#writes].preview == true,
            "the section does not write the trinket keys with a preview refresh")
        env.MSUF_ArenaTrinkets_RefreshLayout("arena")
        CheckPlacement(Holder(1), frames.arena1, "RIGHT", "LEFT", -6, 3, 26, 14, "section edit")
    end

    -- The Layer Overview row (real provider), on the client's own unit gate.
    ns.MSUF2.Tr = function(text) return text end
    ns.MSUF2.Format = string.format
    ns.MSUF2.FilterSupportedUnitValues = function(rows)
        for index = #rows, 1, -1 do
            if not client.SupportsUnit(rows[index].key) then table.remove(rows, index) end
        end
        return rows
    end
    Load(OPTIONS .. "Shell/Menu2/MSUF_Menu2_LayerOverview.lua")
    local function TrinketRow()
        for _, row in ipairs(M.CollectLayerOverviewRows()) do
            if row.id == "unit.arena.trinketLayer" then return row end
        end
    end
    local row = TrinketRow()
    Check(row and row.layer == 14 and row.settingKey == "arena.trinketLayer" and row.enabled == true,
        "the Layer Overview does not list the trinket layer")

    -- The switch: live icon, frame preview and menu preview all follow it.
    if byKey["arena.showTrinket"] then byKey["arena.showTrinket"].set(false) end
    Check(arena.showTrinket == false, "the show switch does not write arena.showTrinket")
    env.MSUF_ArenaTrinkets_RefreshLayout("arena")
    for index = 1, slots do
        Check(not Holder(index):IsShown(), "arena" .. index .. ": the switch did not hide the trinket preview")
    end
    Check(M.ArenaTrinketPreview.Paint(mock, "arena", true, S) == false and not icon:IsShown(),
        "the switch did not hide the unit preview icon")
    row = TrinketRow()
    Check(row and row.enabled == false, "the Layer Overview still marks a hidden trinket as shown")
    inArena, live.arena2 = true, true
    for index = 1, slots do frames["arena" .. index]._msufArenaPreviewForced = nil end
    env.MSUF_ArenaTrinkets_SyncPreview()
    Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen")
    Check(not Holder(2):IsShown(), "the switch did not hide the live trinket in a match")
    arena.showTrinket = true
    env.MSUF_ArenaTrinkets_RefreshLayout("arena")
    Check(Holder(2):IsShown() and Holder(2).cooldown.cooldownDuration ~= 120,
        "the live trinket did not return without the preview sample")
    Check(not Holder(1):IsShown(), "a released preview slot kept its trinket")

    ---------------------------------------------------------------- 6. Edit Mode arena popup
    -- The real unit popup of MSUF Edit Mode over recorded quick-popup widgets:
    -- the arena popup carries a PvP Trinket card whose edits write the same
    -- keys, open one undo entry each and apply the arena scope.
    local applied, history, shells = {}, {}, {}
    local function Box(callback)
        local box = env.CreateFrame("EditBox")
        box.commit = callback
        return box
    end
    local function Toggle(parent, onClick)
        local toggle = env.CreateFrame("Button", nil, parent)
        toggle.click = onClick
        function toggle:SetCheckedVisual(checked) self._checked = checked and true or false end
        toggle:SetCheckedVisual(false)
        return toggle
    end
    env.MSUF_EM_UndoBeforeChange = function(kind, key) history[#history + 1] = kind .. ":" .. key end
    env.MSUF_EM2_Menu2Style = { Card = function() end }
    env.MSUF_EM2 = {
        Util = {
            NormalizeUnitKey = function(key) return key end,
            UnitLabel = function(key) return key end,
            UnitPageKey = function() return "uf_arena" end,
            ApplySettingsForKeySafe = function(key) applied[#applied + 1] = key return true end,
            ApplyAllSettingsSafe = function() applied[#applied + 1] = "*" end,
            SyncMovers = function() end,
            NotifyPositionChanged = function() end,
        },
        PopupFactory = {
            Colors = { cardBg = { 0, 0, 0 }, cardEdge = { 0, 0, 0 }, white = { 1, 1, 1 } },
            FontString = function(parent) return env.CreateFrame("Frame", nil, parent) end,
            Tr = function(text) return text end,
            RefreshPalette = function() end,
            BlockConfigCombatLocked = function() return false end,
            RefreshUFPreview = function() end,
        },
        QuickPopup = {
            San = function(value, fallback) return tonumber(value) or fallback end,
            CreateShell = function(name)
                local shell = env.CreateFrame("Frame", name, env.UIParent)
                shell._titleFS = env.CreateFrame("Frame", nil, shell)
                shells[name] = shell
                return shell
            end,
            ValueCard = function(owner, parent, _, _, _, _, rows)
                for _, row in ipairs(rows) do owner[row.key] = Box(row.onChanged) end
                return env.CreateFrame("Frame", nil, parent)
            end,
            ValuePairAt = function(owner, parent, _, _, _, key1, cb1, _, key2, cb2)
                owner[key1], owner[key2] = Box(cb1), Box(cb2)
                return env.CreateFrame("Frame", nil, parent)
            end,
            SingleValueAt = function(owner, parent, _, _, _, key, cb)
                owner[key] = Box(cb)
                return env.CreateFrame("Frame", nil, parent)
            end,
            ToggleAt = function(parent, _, _, _, _, _, onClick) return Toggle(parent, onClick) end,
            ButtonAt = function(parent) return env.CreateFrame("Button", nil, parent) end,
            MenuButtonAt = function(parent) return env.CreateFrame("Button", nil, parent) end,
            SetBoxText = function(box, value) box:SetText(tostring(value)) end,
            AddFooterControls = function() end,
        },
    }
    Load(CORE .. "Shell/EditMode/MSUF_EditMode_Popups.lua")
    local UnitPopup = env.MSUF_EM2.UnitPopup
    Check(UnitPopup.Open("arena", frames.arena1) == true, "the Edit Mode arena popup did not open")
    local popup = shells.MSUF_EM2_UnitPopup
    local card = popup and popup.trinketPanel
    Check(card and card:IsShown(), "the Edit Mode arena popup has no PvP Trinket card")
    if card then
        Check(popup:GetHeight() == 370 + 136, "the arena popup did not grow by the trinket card")
        Check(popup.trinketShowBtn._checked == true and popup.trinketSizeBox:GetText() == "26"
            and popup.trinketLayerBox:GetText() == "14" and popup.trinketXBox:GetText() == "-6"
            and popup.trinketYBox:GetText() == "3", "the trinket card does not show the profile values")
        popup.trinketSizeBox:SetText("40")
        popup.trinketSizeBox.commit()
        popup.trinketLayerBox:SetText("45")
        popup.trinketLayerBox.commit()
        Check(arena.trinketSize == 40 and arena.trinketLayer == 30, "the trinket card did not write a clamped size and layer")
        Check(#history == 2 and history[1] == "unit:arena" and applied[#applied] == "arena",
            "a trinket card edit did not open its undo entry and apply the arena scope")
        env.MSUF_ArenaTrinkets_RefreshLayout("arena")
        CheckPlacement(Holder(2), frames.arena2, "RIGHT", "LEFT", -6, 3, 40, 30, "Edit Mode card edit")
        popup.trinketShowBtn:SetCheckedVisual(false)
        popup.trinketShowBtn.click(false)
        Check(arena.showTrinket == false, "the Edit Mode switch did not write arena.showTrinket")
        Check(UnitPopup.Open("player", frames.arena1) == true and not card:IsShown() and popup:GetHeight() == 370,
            "a non-arena popup shows the PvP Trinket card")
    end
    arena.showTrinket = true
end

--------------------------------------------------------------------------------
-- 7. The menu unit preview as the player uses it. The flavor's whole core and
-- Options graph boots in a second client_world sandbox; the real unit preview
-- is built and refreshed from MSUF_DB. The trinket is a preview element like
-- every other: click selects it, a drag and the arrow keys move it (clamped to
-- the runtime range, one history entry per drag, the arena scope applied), Tab
-- reaches it, the selection bar names it and edits, resets and opens it, and
-- the Trinket legend entry shows or hides it.
--------------------------------------------------------------------------------
-- Widget calls the menu preview and the Edit Mode popups make that the shared
-- stubs do not model; added after the boot, as mainline_unit_preview_boss_target_smoke does.
local function AddWidgetMethods(full)
    local Methods = full.widgets.Methods
    for name, method in pairs({
        SetStartPoint = function(self, ...) self.startPoint = { ... } end,
        SetEndPoint = function(self, ...) self.endPoint = { ... } end,
        SetThickness = function(self, value) self.thickness = value end,
        SetAutoFocus = function(self, value) self.autoFocus = value end,
        SetMaxLetters = function(self, value) self.maxLetters = value end,
        EnableKeyboard = function(self, value) self.keyboardEnabled = value end,
        ClearFocus = function(self) self.focused = nil end,
    }) do
        if Methods[name] == nil then Methods[name] = method end
    end
end

local function PreviewInteraction()
    local full = World.New(root, flavor)
    full:Boot()
    local failure = full:FirstFailure()
    if not Check(failure == nil, "boot failed in " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message)) then
        return
    end
    AddWidgetMethods(full)
    local fenv, core = full.env, full.core
    local cursorX, cursorY, shift, ctrl = 500, 300, false, false
    fenv.GetCursorPosition = function() return cursorX, cursorY end
    fenv.IsMouseButtonDown = function() return true end
    fenv.IsShiftKeyDown = function() return shift end
    fenv.IsControlKeyDown = function() return ctrl end
    fenv.GetCurrentKeyBoardFocus = function() return nil end
    fenv.C_Texture = { GetAtlasInfo = function() return nil end }
    fenv.MSUF_EnsureDB(true)
    local menu, Preview = fenv.MSUF2, core.UFPreview
    local parent = fenv.CreateFrame("Frame", nil, fenv.UIParent)
    parent:SetSize(900, 400)
    local panel = fenv.CreateFrame("Frame", nil, fenv.UIParent)
    local previewKey = "arena"
    panel._msufGetCurrentKey = function() return previewKey end
    local box = Preview._BuildPreview(parent, panel, 900, 400)
    box:Show()
    box.canvas:SetSize(400, 200)
    local function Refresh(key)
        previewKey = key
        core.UF.Config.Refresh()
        Preview.Refresh(box, "ARENA_TRINKET_PREVIEW_SMOKE")
    end
    local function Chip()
        for _, button in ipairs(box.layerButtons or {}) do
            if button.key == "trinket" then return button end
        end
    end
    local handle, chip = box.handleArenaTrinket, Chip()
    if slots == 0 then
        Check(handle == nil, "a client without arena frames builds a trinket preview element")
        Refresh("player")
        Check(chip == nil or not chip:IsShown(), "a client without arena frames shows the Trinket legend entry")
        return
    end
    if not Check(handle ~= nil and chip ~= nil, "the unit preview has no trinket element or no Trinket legend entry") then
        return
    end
    local listed = 0
    for _, entry in ipairs(box.handles) do
        if entry._key == "arenaTrinket" then listed = listed + 1 end
    end
    Check(listed == 1, "the trinket handle is listed " .. listed .. " times")
    local arenaDB = fenv.MSUF_DB.arena
    arenaDB.showTrinket, arenaDB.trinketOffsetX, arenaDB.trinketOffsetY = true, 4, 0

    Refresh("player")
    Check(not handle:IsShown() and not chip:IsShown(), "the Player preview offers the trinket")
    Refresh("arena")
    local icon = box.mock._msufArenaTrinketPreview
    local _, handleOn = handle:GetPoint(1)
    Check(icon and icon:IsShown() and handle:IsShown() and handleOn == icon, "the trinket handle does not sit on the preview icon")
    Check(chip:IsShown() and box.layerAvailable.trinket == true, "the Arena preview does not offer the Trinket legend entry")

    -- Click selects; with guides on, the selection border shows like any element.
    box.layerVisibility.guides = true
    handle:GetScript("OnClick")(handle, "LeftButton")
    Check(box._selectedHandle == handle and handle._selBorder:IsShown(), "a click does not select the trinket")
    local bar = box._msuf2SelectionBar
    Check(bar and bar.label:GetText() == "PvP Trinket", "the selection bar does not name the PvP Trinket")

    -- Drag: one history entry, the stored offset follows the cursor, the arena
    -- scope applies (in game Factory.Apply then re-places the live holders,
    -- section 2), and the runtime range clamps it. This sandbox has no unit
    -- frames to apply, so the unit-frame apply entry point is recorded.
    local applied = {}
    fenv.MSUF_UFCore_NotifyConfigChanged = function(key)
        applied[#applied + 1] = key
        return true
    end
    -- The menu starts a history session when it shows; so does this test.
    menu.StartHistorySession("menu")
    local history = menu.GetHistoryState()
    local undoBefore = history and history.undoCount or 0
    local scale = box._mockEffectiveScale or 1
    handle:GetScript("OnMouseDown")(handle, "LeftButton")
    cursorX, cursorY = cursorX + 12 * scale, cursorY - 7 * scale
    box._onDragUpdate(box.dragFrame)
    cursorX = cursorX + 3 * scale
    box._onDragUpdate(box.dragFrame)
    handle:GetScript("OnMouseUp")(handle, "LeftButton")
    Check(arenaDB.trinketOffsetX == 19 and arenaDB.trinketOffsetY == -7, "a drag stored "
        .. tostring(arenaDB.trinketOffsetX) .. "," .. tostring(arenaDB.trinketOffsetY) .. " instead of 19,-7")
    history = menu.GetHistoryState()
    Check(history and history.undoCount == undoBefore + 1, "a drag did not leave exactly one history entry ("
        .. tostring(undoBefore) .. " -> " .. tostring(history and history.undoCount) .. ")")
    local arenaApplied = false
    for _, key in ipairs(applied) do
        if key == "arena" then arenaApplied = true end
    end
    Check(arenaApplied, "a drag did not apply the arena scope to the live trinkets")
    handle:GetScript("OnMouseDown")(handle, "LeftButton")
    cursorX = cursorX + 900 * scale
    box._onDragUpdate(box.dragFrame)
    handle:GetScript("OnMouseUp")(handle, "LeftButton")
    Check(arenaDB.trinketOffsetX == 200, "a drag past the edge stored " .. tostring(arenaDB.trinketOffsetX)
        .. ", not the runtime limit 200")

    -- Arrow keys with their modifier steps (1, Shift 5, Ctrl 10).
    arenaDB.trinketOffsetX, arenaDB.trinketOffsetY = 4, 0
    Refresh("arena")
    local keyDown = handle:GetScript("OnKeyDown")
    local function Key(name)
        full.widgets:AdvanceTime(1)
        keyDown(handle, name)
    end
    Key("RIGHT")
    Key("UP")
    shift = true
    Key("RIGHT")
    shift, ctrl = false, true
    Key("DOWN")
    ctrl = false
    Check(arenaDB.trinketOffsetX == 10 and arenaDB.trinketOffsetY == -9, "arrow nudges stored "
        .. tostring(arenaDB.trinketOffsetX) .. "," .. tostring(arenaDB.trinketOffsetY) .. " instead of 10,-9")

    -- Tab reaches the trinket from the element before it and leaves it again.
    local SelectionBar = menu.PreviewSelectionBar
    local placed = {}
    for _, entry in ipairs(box.handles) do
        if entry._msufPlaced ~= false and entry:IsShown() then placed[#placed + 1] = entry end
    end
    local at
    for index, entry in ipairs(placed) do
        if entry == handle then at = index end
    end
    if Check(at ~= nil and #placed > 1, "the trinket is not among the placed preview elements") then
        local before = placed[at == 1 and #placed or at - 1]
        before:GetScript("OnClick")(before, "LeftButton")
        SelectionBar.CycleHandle(box, false)
        Check(box._selectedHandle == handle, "Tab does not reach the trinket")
        SelectionBar.CycleHandle(box, false)
        SelectionBar.CycleHandle(box, true)
        Check(box._selectedHandle == handle, "Shift-Tab does not return to the trinket")
    end

    -- The selection bar: exact X, Reset to the factory offset, Open settings.
    handle:GetScript("OnClick")(handle, "LeftButton")
    SelectionBar.Refresh(box)
    local shownX, storedX = tonumber(bar.editX:GetText()), arenaDB.trinketOffsetX
    if Check(shownX ~= nil, "the selection bar shows no X for the trinket") then
        bar.editX:SetText(tostring(shownX + 6))
        bar.editX:GetScript("OnEnterPressed")(bar.editX)
        Check(arenaDB.trinketOffsetX == storedX + 6, "the selection bar X stored " .. tostring(arenaDB.trinketOffsetX)
            .. " instead of " .. tostring(storedX + 6))
    end
    bar.resetButton:GetScript("OnClick")(bar.resetButton)
    Check(arenaDB.trinketOffsetX == 4 and arenaDB.trinketOffsetY == 0, "Reset did not restore the factory offset 4,0")
    local opened
    menu.SelectPage = function(pageKey)
        opened = pageKey
        return true
    end
    bar.openButton:GetScript("OnClick")(bar.openButton)
    local request = fenv.MSUF_EM2_MenuFocusRequest
    Check(opened == "uf_arena" and request and request.sectionId == "pvp_trinket",
        "Open settings does not jump to the PvP Trinket section")

    -- The legend entry hides and shows the icon and its handle; the switch
    -- turns the entry into the route to its settings.
    chip:GetScript("OnClick")(chip)
    Check(box.layerVisibility.trinket == false and not icon:IsShown() and not handle:IsShown(),
        "the Trinket legend entry does not hide the trinket")
    chip:GetScript("OnClick")(chip)
    Refresh("arena")
    Check(icon:IsShown() and handle:IsShown(), "the Trinket legend entry does not show the trinket again")
    arenaDB.showTrinket = false
    Refresh("arena")
    Check(box.layerAvailable.trinket == false and not icon:IsShown() and not handle:IsShown(),
        "the show switch does not hide the preview trinket or keep its legend entry offered")
    arenaDB.showTrinket = true
end
PreviewInteraction()

--------------------------------------------------------------------------------
-- 8. MSUF Edit Mode: the trinket is a mover like the detached power bar, a
-- sub-element whose X/Y offset from its anchor side drags and nudges in place.
-- Arena 1's icon carries the mover, the other slots add mouse regions, the
-- saved offset stays in the runtime range, a nudge goes through Edit Mode's
-- arrow route with its undo entry, and a click opens the arena frame popup on
-- its PvP Trinket card. Clients without arena frames register no mover.
--------------------------------------------------------------------------------
local function EditModeMover()
    local full = World.New(root, flavor)
    full:Boot()
    local failure = full:FirstFailure()
    if not Check(failure == nil, "Edit Mode boot failed in " .. tostring(failure and failure.file)) then return end
    AddWidgetMethods(full)
    local fenv, core = full.env, full.core
    fenv.MSUF_EnsureDB(true)
    local EM2 = fenv.MSUF_EM2
    local cfg = EM2 and EM2.Registry and EM2.Registry.Get("arena_trinket")
    if slots == 0 then
        Check(cfg == nil, "a client without arena frames registers an Edit Mode trinket mover")
        return
    end
    if not Check(cfg ~= nil and cfg.popupType == "resource" and cfg.canNudge == true
        and cfg.subframeOffsetXKey == "trinketOffsetX" and cfg.subframeOffsetYKey == "trinketOffsetY"
        and cfg.historyCategory == "unit" and cfg.historyKey == "arena",
        "Edit Mode has no trinket mover built like the detached power bar's") then
        return
    end
    local stubHolders = {}
    for index = 1, slots do
        local holder = fenv.CreateFrame("Frame", nil, fenv.UIParent)
        holder:SetSize(12, 12)
        holder.left, holder.bottom = 600, 700 - index * 60
        holder:Show()
        stubHolders[index] = holder
    end
    local trinkets = core.ArenaTrinkets
    local realHolder = trinkets.Holder
    trinkets.Holder = function(index) return stubHolders[index] end
    Check(cfg.getFrame() == stubHolders[1], "the trinket mover does not ride arena 1's icon")
    local l, r, t, b = cfg.getMoverBounds()
    Check(l ~= nil and r - l >= 18 and t - b >= 18, "a small trinket icon gets no 18 px grab area")
    Check(#cfg.getSupplementalMoverBounds() == slots - 1, "the other arena slots add no trinket mouse regions")
    stubHolders[1]:Hide()
    Check(cfg.getFrame() == nil, "a hidden trinket keeps its Edit Mode mover")
    stubHolders[1]:Show()

    -- The sandbox's unit apply re-resolves the active profile, so the arena
    -- table is read again after every write instead of being held.
    local function Arena() return fenv.MSUF_DB.arena end
    local ufApplied = {}
    local realApply = core.UF.Apply
    core.UF.Apply = function(key)
        ufApplied[#ufApplied + 1] = key
        return true
    end
    Arena().trinketOffsetX, Arena().trinketOffsetY = 260, -300
    Check(cfg.commitSubframePosition() == true and Arena().trinketOffsetX == 200 and Arena().trinketOffsetY == -200
        and ufApplied[#ufApplied] == "arena", "a drag commit does not keep the offset in range and apply the arena scope")

    -- Entering Edit Mode starts its history session (MSUF_EditMode_State.lua);
    -- the selected element is the trinket mover.
    local state, menu = EM2.State, fenv.MSUF2
    local isActive, getUnitKey = state.IsActive, state.GetUnitKey
    state.IsActive = function() return true end
    state.GetUnitKey = function() return "arena_trinket" end
    menu.StartHistorySession("edit_mode")
    Arena().trinketOffsetX, Arena().trinketOffsetY = 4, 0
    local undoBefore = menu.GetHistoryState().undoCount
    EM2.Nudge.By(1, -2)
    Check(Arena().trinketOffsetX == 5 and Arena().trinketOffsetY == -2, "an Edit Mode nudge stored "
        .. tostring(Arena().trinketOffsetX) .. "," .. tostring(Arena().trinketOffsetY) .. " instead of 5,-2")
    -- Edit Mode nudges fold into one debounced history entry; let it settle.
    full.widgets:AdvanceTime(2)
    full.widgets:RunTimers()
    Check(menu.GetHistoryState().undoCount == undoBefore + 1, "an Edit Mode nudge left no undo entry")
    Arena().trinketOffsetX = 200
    EM2.Nudge.By(1, 0)
    Check(Arena().trinketOffsetX == 200, "an Edit Mode nudge pushed the trinket past the runtime range")
    state.IsActive, state.GetUnitKey = isActive, getUnitKey

    -- The arena popup and its card are pinned in section 6; here the click route.
    local unitPopup = EM2.UnitPopup
    local realOpen, openedUnit = unitPopup.Open, nil
    unitPopup.Open = function(unit)
        openedUnit = unit
        return true
    end
    EM2.Popups.Open("arena_trinket", nil)
    Check(openedUnit == "arena", "a click on the trinket mover does not open the arena frame popup with its PvP Trinket card")
    unitPopup.Open = realOpen
    trinkets.Holder, core.UF.Apply = realHolder, realApply
end
EditModeMover()

-- The Arena page loads the section on every client, and the unit sections
-- offer Reset section for it.
Check(Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml")
    :find('<Script file="Pages\\MSUF_Menu2_UnitArenaTrinket.lua"/>', 1, true), "no Options manifest loads the PvP Trinket section")
Check(Read("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua")
    :find("pvp_trinket = { fields = UP.ARENA_TRINKET_FIELDS, noCopy = true }", 1, true), "the PvP Trinket section has no Reset section")

if #failures > 0 then
    error("arena_trinket_preview_smoke failed:\n  " .. table.concat(failures, "\n  "), 0)
end
print("arena_trinket_preview_smoke: ok (" .. flavor .. ", " .. slots .. " arena slots)")
