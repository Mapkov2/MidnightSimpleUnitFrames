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
