-- Schema-bound setters, the real apply dispatcher, and engine-created frames.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local Harness = assert(loadfile(root .. "/tools/tests/group_header_world.lua"))()
local boundaryErrors = {}
local h = Harness.New(root, flavor, { nativeLayout = arg[3] == "edit", beforeBoot = function(harness)
    MenuWorld.ApplyCoreTocMetadata(harness.world)
    MenuWorld.InstallNativeUnitInputs(harness.world)
    if arg[3] == "edit" then
        -- Independent geometry checks: replacement preserves other anchors;
        -- TOP + LEFT constrains different axes and follows a moving parent.
        local parent = harness.env.CreateFrame("Frame", nil, harness.env.UIParent)
        parent:SetSize(100, 80)
        parent:SetPoint("BOTTOMLEFT", harness.env.UIParent, "BOTTOMLEFT", 20, 30)
        local child = harness.env.CreateFrame("Frame", nil, parent)
        child:SetSize(10, 8)
        child:SetPoint("TOP", parent, "TOP", 0, 0)
        child:SetPoint("LEFT", parent, "LEFT", 0, 0)
        assert(child:GetLeft() == 20 and child:GetTop() == 110, "native cross-axis anchor geometry")
        child:SetPoint("LEFT", parent, "LEFT", 5, 0)
        assert(child:GetNumPoints() == 2 and child:GetLeft() == 25, "native SetPoint must replace the same point")
        parent:SetPoint("BOTTOMLEFT", harness.env.UIParent, "BOTTOMLEFT", 40, 50)
        assert(child:GetLeft() == 45 and child:GetTop() == 130, "native child must follow its parent")
        child:Hide()
        parent:Hide()
    end
    harness.env.MAX_BOSS_FRAMES = 5
    harness.env.GetCursorPosition = function() return 300, 400 end
    harness.env.IsAltKeyDown = function() return false end
    harness.env.IsControlKeyDown = function() return false end
    harness.env.IsShiftKeyDown = function() return false end
    harness.env.geterrorhandler = function()
        return function(message) boundaryErrors[#boundaryErrors + 1] = tostring(message) end
    end
end })
local ns, env, GF = h.core, h.env, h.GF
GF.GetConf("party").enabled, GF.GetConf("party").showPlayer = true, true
h:SetRoster({ "player", "party1", "party2" })
h:Event("GROUP_ROSTER_UPDATE")
GF.RefreshHeaderLayout()
h:RunTimers()
-- Prepare the native roster before the menu captures its history baseline.
local mw = MenuWorld.Open(root, flavor, { world = h.world, keepFlush = true, clientScriptBindings = true })
local M = mw.M
assert(ns.UF.Factory.SpawnAll(), "unit factory refused to spawn")
local player = assert(ns.UF.GetFrame("player"), "factory created no player")
local group = assert(h:Children(assert(GF.headers.party))[1], "header created no group child")
assert(player.MSUFSpec and group.MSUFSpec, "live frames have no compiled spec")
local failures, passed = {}, 0
local function Case(name, callback)
    local firstError = #boundaryErrors + 1
    local ok, err = pcall(callback)
    if #boundaryErrors >= firstError then
        local collected = table.concat(boundaryErrors, "\n", firstError)
        ok, err = false, (err and tostring(err) .. "\n" or "") .. collected
    end
    if ok then passed = passed + 1 print("PASS apply:" .. name)
    else failures[#failures + 1] = name .. ": " .. tostring(err) print("FAIL apply:" .. failures[#failures]) end
end
local function Expand(page)
    assert(mw:Select(page), "page selection refused: " .. page)
    for _ = 1, 3 do
        for _, section in pairs(M.cache[page].sections or {}) do
            local entry = section._msuf2CollapsibleEntry
            if entry then entry.SetOpenImmediate(true) end
        end
        mw:RunTimers()
    end
end
local function Widget(page, id)
    Expand(page)
    local record = M.RuntimeControlCatalog.Get(id)
    if not record then
        for _, row in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
            if row.exactTarget and row.exactTarget.controlId == id then
                assert(M.Search.OpenTarget(row.key, row.label, row.anchorFallback or row.label,
                    row.anchor, row.route, row.exactTarget), "exact view preparation refused")
                mw:RunTimers()
                break
            end
        end
        record = M.RuntimeControlCatalog.Get(id)
    end
    assert(record, "missing control: " .. id)
    local widget = assert(record.widget)
    assert(widget._msuf2ControlSchema, "setter has no schema declaration")
    return widget, assert(widget._msuf2CommandAction)
end
local function Settle()
    -- Flush is never stubbed. Run callbacks without swallowing apply errors.
    mw:RunTimers()
    M.ApplyService.Flush()
    mw:RunTimers()
end
local function Edit(page, id, value, observe, expected)
    local widget, command = Widget(page, id)
    local before = observe()
    assert(before ~= expected, "fixture already has requested state")
    M.ClearHistory()
    assert(M.BeginHistoryTransaction(id, "release", nil), "history refused")
    command.set(value)
    M.CommitHistoryTransaction()
    Settle()
    assert(observe() == expected, "live state " .. tostring(observe()) .. ", expected " .. tostring(expected))
    assert(M.Undo(), "history undo refused")
    Settle()
    assert(observe() == before, "undo did not restore live state")
end
local function Health(frame) return assert(frame.hpBar or frame.healthBar or frame.Health, "missing health bar") end
local function Power(frame) return assert(frame.powerBar or frame.Power, "missing power bar") end
if arg[3] == "edit" then
    local em = ns.EditModeController
    local function Pose(frame)
        local point, relative, to, x, y = frame:GetPoint()
        return table.concat({ tostring(point), tostring(relative), tostring(to), tostring(x), tostring(y) }, "/")
    end
    for _, key in ipairs({ "player", "gf_party" }) do
        Case("edit:" .. key, function()
            local surfaceCount = ns.History.GetHistoryState().activeSurfaces
            assert(ns.Require("MSUF_SetMSUFEditModeDirect", "release edit")(true, key), "unlock refused")
            Settle()
            local cfg = assert(em.Registry.Get(key), "element not registered")
            local frame = assert(cfg.getFrame(), "unlock built no frame/container")
            local conf = assert(cfg.getConf())
            local x, y, pose = conf.offsetX, conf.offsetY, Pose(frame)
            local centerX, centerY = frame:GetCenter()
            local strategy = ns.EditModeKinds[key == "player" and "unit" or "group"]
            assert(em.Undo.BeginChange(key == "player" and "unit" or "gf", key == "player" and key or "party"))
            local drag = assert(strategy:beginDrag(frame, key, cfg, { bar = frame }), "drag refused")
            assert(strategy:applyDrag(drag, drag.startCX + 17, drag.startCY + 7, 1), "move refused")
            assert(strategy:commit(drag, drag.startCX + 17, drag.startCY + 7), "commit refused")
            em.Undo.CommitChange()
            Settle()
            local movedX, movedY, movedPose = conf.offsetX, conf.offsetY, Pose(frame)
            assert((movedX ~= x or movedY ~= y) and movedPose ~= pose, "move did not reach actual frame points")
            assert(movedX == x + 17 and movedY == y + 7, "move lost the requested offset delta")
            local movedCenterX, movedCenterY = frame:GetCenter()
            assert(movedCenterX == centerX + 17 and movedCenterY == centerY + 7, "move lost the native center delta")
            assert(em.Nudge.By(1, 0), "nudge refused")
            Settle()
            assert(conf.offsetX ~= movedX and Pose(frame) ~= movedPose, "nudge did not reach actual frame points")
            assert(em.Undo.DoUndo(), "nudge undo refused")
            Settle()
            assert(conf.offsetX == movedX and conf.offsetY == movedY and Pose(frame) == movedPose, "nudge undo lost actual position")
            assert(em.Undo.DoUndo(), "move undo refused")
            Settle()
            assert(conf.offsetX == x and conf.offsetY == y and Pose(frame) == pose, "move undo lost actual position")
            assert(ns.Require("MSUF_SetMSUFEditModeDirect", "release edit")(false, key), "lock refused")
            Settle()
            assert(not ns.EditMode.IsActive(), "lock left edit mode active")
            assert(ns.History.GetHistoryState().activeSurfaces == surfaceCount, "lock leaked a history surface")
        end)
    end
    assert(#h.violations == 0, "protected edit write: " .. tostring(h.violations[1]))
    assert(#failures == 0, table.concat(failures, "\n"))
    print("Edit Mode: " .. flavor .. " live unit/group unlock, move, nudge, undo and lock passed")
    return
end
Case("health", function()
    Edit("uf_player", "menu2.uf_player.unit.transparency.hpbaralpha", 0.37,
        -- Foreground opacity is applied to the native fill texture, independently of its status-bar tint.
        function() return assert(Health(player):GetStatusBarTexture(), "missing health fill texture"):GetAlpha() end, 0.37)
end)
Case("power", function()
    Edit("uf_player", "menu2.uf_player.unit.power.powerbarheight", 13,
        function() return Power(player):GetHeight() end, 13)
end)
Case("castbar", function()
    Edit("uf_player", "menu2.uf_player.unit.castbar.height", 29,
        function() return assert(ns.Castbars.Frames.Get("player"), "no live castbar"):GetHeight() end, 29)
end)
Case("fonts", function()
    local _, show = Widget("uf_player", "menu2.uf_player.unit.text.name.show")
    show.set(true)
    Settle()
    Edit("uf_player", "menu2.uf_player.unit.text.name.size", 19, function()
        local text = assert(player.nameText or player.Name or player.name, "no name font string")
        local _, size = text:GetFont()
        return size
    end, 19)
end)
Case("group", function()
    Edit("gf_layout", "menu2.gf_layout.group.field.width", 167,
        function() return group:GetWidth() end, 167)
end)
Case("colors", function()
    -- The schema setter's colour mode changes the live health paint.
    local _, command = Widget("uf_player", "menu2.uf_player.unit.basics.health_color_mode")
    local prior = command.get()
    M.ClearHistory()
    local before = { Health(player):GetStatusBarColor() }
    assert(M.BeginHistoryTransaction("color", "release", nil))
    command.set(player.MSUFSpec.health.mode == "dark" and "class" or "dark")
    M.CommitHistoryTransaction()
    Settle()
    local after = { Health(player):GetStatusBarColor() }
    assert(after[1] ~= before[1] or after[2] ~= before[2] or after[3] ~= before[3], "health color sink did not change")
    assert(M.Undo())
    Settle()
    local restored = { Health(player):GetStatusBarColor() }
    assert(restored[1] == before[1] and restored[2] == before[2] and restored[3] == before[3], "undo lost health color")
end)
Case("border-test-modes", function()
    for _, kind in ipairs({ "aggro", "dispel", "purge" }) do
        local _, mode = Widget("opt_bars", "menu2.opt.bars.global.highlight.border.mode." .. kind .. ".outline.mode")
        local previousMode = mode.get()
        mode.set(1)
        Settle()
        local _, command = Widget("opt_bars", "menu2.opt.bars.global.highlight.preview." .. kind)
        local frame = kind == "purge" and assert(ns.UF.GetFrame("target")) or player
        local before = { frame._msufBorderR, frame._msufBorderG, frame._msufBorderB }
        local source, shown = frame._msufBorderVisualSource, frame._msufBorderShown
        command.set(true)
        Settle()
        assert(command.get() == true, kind .. " test did not activate")
        local visible = 0
        for _, edge in pairs(frame.MSUFBorderEdges or {}) do
            if edge:IsShown() then visible = visible + 1 end
        end
        assert(frame._msufBorderShown == true and visible > 0, kind .. " test painted no live border")
        assert(frame._msufBorderVisualSource == kind, kind .. " test did not change the active border source")
        command.set(false)
        Settle()
        assert(command.get() == false, kind .. " test did not stop")
        assert(frame._msufBorderVisualSource == source and frame._msufBorderShown == shown,
            kind .. " test did not restore border ownership/visibility")
        assert(frame._msufBorderR == before[1] and frame._msufBorderG == before[2] and frame._msufBorderB == before[3],
            kind .. " test did not restore border color")
        mode.set(previousMode)
        Settle()
    end
end)
Case("auras", function()
    local _, cap = Widget("uf_player", "menu2.uf_player.auras.unit-workspace.lane.buff.layout.max-icons")
    cap.set(3)
    Settle()
    local id = "menu2.uf_player.auras.unit-workspace.lane.buff.layout.icon-size"
    Edit("uf_player", id, 37, function()
        local config = ns.Client.IsClassic and player._msufA3State and player._msufA3State.config
            or player.Auras and player.Auras._msufA3Config
        assert(config, "live aura owner has no applied config")
        return assert(config.lanes.buff, "live aura owner has no buff lane").size
    end, 37)
end)
assert(#h.violations == 0, "protected frame write: " .. tostring(h.violations[1]))
assert(#failures == 0, flavor .. " apply failures:\n" .. table.concat(failures, "\n"))
print("apply: " .. flavor .. ", " .. passed .. " live domains including history passed")
