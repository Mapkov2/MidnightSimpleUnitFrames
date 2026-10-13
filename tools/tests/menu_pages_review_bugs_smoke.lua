-- menu_pages_review_bugs_smoke.lua <repoRoot> <flavor>
--
-- Menu2 page bugs found by the 7.0 page review, each driven through the real
-- core and Options graph (menu_core_world.lua):
--   1. Castbars > Shake on interrupt reads the same default the runtime uses
--      (CastbarUtils shakes unless the setting is false), so a fresh profile
--      shows On while the bars shake.
--   2. Unit > Target > Inline Text: an NPC inline colour whose NPC colours are
--      off stays stored and shown as NPC; opening the page does not rewrite it.
--   3. Master toggles that gate other controls re-run the page refreshers: the
--      unit aura style "Mark Stealable Buffs" and the Custom aura style and
--      filter switches no longer leave their gated controls greyed out until the
--      page is rebuilt.
--   4. The Aura Style copy carries a Custom aura's Lane Padding.
--   5. A Pet aura request takes the targeted unit route like the other unit
--      scopes instead of the shared aura batch.
--   6. Group aura cooldown/stack anchors, offsets and large-group scaling queue
--      the "auras" apply mode, which recompiles the aura lanes ("geometry" never
--      reached them).
--   7. The unit Copy To status category carries the keys the runtime reads and
--      does not list a key nothing reads; the Copy To All prompt names every
--      frame it overwrites.
--   8. Dragging a Group spell indicator tile reaches the next slot and the last
--      one.
-- Every section runs on its own; all failures are listed together.
-- Plain Lua 5.1 with the repo root and a flavor as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env, core = mw.M, mw.env, mw.core
local db = env.MSUF_DB
-- The queued unit-frame, module and class-power applies read runtime APIs the
-- harness only stubs; this contract is about the menu.
env.MSUF_UFCore_NotifyConfigChanged = function() return true end
env.MSUF_ApplyModules = function() return true end
env.MSUF_ClassPower_Apply = function() return true end
env.MSUF_RefreshStatusIndicators = env.MSUF_RefreshStatusIndicators or function() end

local failures = {}
local function Section(name, fn)
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
local function Check(condition, message)
    if not condition then error(message, 0) end
    return condition
end

local function ReadSource(path)
    local file = assert(io.open(root .. "/" .. path, "rb"), "missing file: " .. path)
    local text = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return text
end
-- Source text from the first marker up to, not including, the second one.
local function Slice(source, first, stop)
    local start = Check(source:find(first, 1, true), "missing " .. first)
    local finish = Check(source:find(stop, start + #first, true), "missing " .. stop)
    return source:sub(start, finish - 1)
end

-- Controls by control id, as the pages register them.
local byId = {}
local Register = M.RegisterRuntimeControl
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and payload.controlId then
        local copy = {}
        for field, value in pairs(payload) do copy[field] = value end
        copy.widget = widget
        byId[copy.controlId] = copy
    end
    return Register(widget, payload, ...)
end
local function Control(id)
    return Check(byId[id], "control " .. id .. " is not on the page")
end
local function Enabled(id) return Control(id).widget._msuf2DesiredEnabled ~= false end
local function Settle() mw:RunTimers() end
-- Select a page and build the named sections (every section when none is named).
local function Build(pageKey, pattern)
    Check(M.SelectPage(pageKey) ~= false, "could not open " .. pageKey)
    Settle()
    local entry = Check(M.cache[pageKey], "the " .. pageKey .. " page did not build")
    local names = {}
    for name in pairs(entry.sections or {}) do
        if not pattern or name:find(pattern) then names[#names + 1] = name end
    end
    for _, name in ipairs(names) do M.Widgets.EnsureSectionContent(entry.sections[name]) end
    Settle()
    return entry
end
local function OpenAurasAccordion(pageKey)
    local accordion = M.GetPersistentMenuStateTable and M.GetPersistentMenuStateTable("accordionState")
    if type(accordion) ~= "table" then
        M.accordionState = M.accordionState or {}
        accordion = M.accordionState
    end
    accordion[pageKey .. ":auras"] = true
end

---------------------------------------------------------------------------
-- 1. Shake on interrupt
---------------------------------------------------------------------------
Section("Shake on interrupt shows what the runtime does", function()
    Build("opt_castbar", "behavior")
    local control = Control("menu2.opt.castbar.global.behavior.castbar.interrupt.shake")
    local general = db.general
    local saved = general.castbarInterruptShake
    local function Shakes(value)
        general.castbarInterruptShake = value
        local frame = env.CreateFrame("Frame", nil, env.UIParent)
        env.MSUF_PlayCastbarShake(frame)
        return frame.MSUF_ShakeGroup ~= nil
    end
    for _, value in ipairs({ "unset", true, false }) do
        local stored = value ~= "unset" and value or nil
        local shakes = Shakes(stored)
        general.castbarInterruptShake = stored
        Check(control.command.get() == shakes, "with the setting " .. tostring(value) .. " the menu shows "
            .. tostring(control.command.get()) .. " while the bars " .. (shakes and "shake" or "do not shake"))
    end
    general.castbarInterruptShake = saved
end)

---------------------------------------------------------------------------
-- 2. Inline ToT colour
---------------------------------------------------------------------------
Section("An unavailable NPC inline colour is kept and shown", function()
    db.targettarget.totInlineColorMode = "NPC"
    db.general.npcNameRed = false
    local entry = Build("uf_target", "inline_text")
    M.RunEntryRefreshers(entry, { force = true })
    Settle()
    Check(db.targettarget.totInlineColorMode == "NPC", "opening the page changed the stored inline colour to "
        .. tostring(db.targettarget.totInlineColorMode))
    -- The runtime, the colour picker and the preview keep using the stored mode, so the dropdown names it too.
    local control = Control("menu2.uf_target.unit.inline_text.color")
    Check(control.command.get() == "NPC", "the dropdown shows " .. tostring(control.command.get())
        .. " while the stored inline colour is NPC")
end)

---------------------------------------------------------------------------
-- 3. Master toggles refresh the controls they gate
---------------------------------------------------------------------------
Section("Mark Stealable Buffs enables the marker style", function()
    OpenAurasAccordion("uf_target")
    M.unitAuraTabSelection = { target = "buff" }
    M.unitAuraToolSelection = { target = { buff = "style" } }
    Build("uf_target", "aura_style_target_buff")
    local switch = Control("menu2.uf_target.auras.style.lane.buff.showstealable")
    local style = "menu2.uf_target.auras.style.lane.buff.auras3-stealable-marker-style"
    switch.command.set(false)
    Settle()
    Check(not Enabled(style), "the marker style stays enabled while the marker is off")
    switch.command.set(true)
    Settle()
    Check(Enabled(style), "the marker style stayed disabled after Mark Stealable Buffs was switched on")
end)

local CUSTOM = "menu2.uf_target.auras.custom-container."
local function CustomTool(tool)
    OpenAurasAccordion("uf_target")
    M.unitAuraTabSelection = { target = "custom1" }
    M.unitAuraToolSelection = { target = { custom1 = tool } }
    Build("uf_target", "custom")
end
for _, row in ipairs({
    { "Stack count", "appearance.stack-count", "appearance.stackx" },
    { "Cooldown text", "appearance.cooldown-text", "appearance.cooldownsize" },
    { "Cooldown swipe", "appearance.cooldown-swipe", "appearance.swipe-direction" },
}) do
    Section("Custom aura " .. row[1] .. " enables its controls", function()
        CustomTool("style")
        local switch, gated = Control(CUSTOM .. row[2]), CUSTOM .. row[3]
        switch.command.set(false)
        Settle()
        Check(not Enabled(gated), row[3] .. " stays enabled while " .. row[1] .. " is off")
        switch.command.set(true)
        Settle()
        Check(Enabled(gated), row[3] .. " stayed disabled after " .. row[1] .. " was switched on")
    end)
end
Section("Custom aura Enable filters enables the filter switches", function()
    CustomTool("filters")
    local switch, gated = Control(CUSTOM .. "filters.enabled"), CUSTOM .. "filters.onlymine"
    switch.command.set(false)
    Settle()
    Check(not Enabled(gated), "the filter switches stay enabled while the filters are off")
    switch.command.set(true)
    Settle()
    Check(Enabled(gated), "the filter switches stayed disabled after Enable filters was switched on")
end)

---------------------------------------------------------------------------
-- 4. Custom aura Lane Padding in the Aura Style copy
---------------------------------------------------------------------------
Section("Aura Style copy carries a Custom aura's Lane Padding", function()
    local Model = Check(core.MSUF_Auras3 and core.MSUF_Auras3.MenuModel, "the Auras3 menu model did not load")
    local source = Model.CustomContainer("player", 1, true)
    source.placed = source.placed or {}
    source.placed.stylePadding, source.placed.iconZoom = 7, 130
    Check(Model.CopyUnitStyle("player", "target") == true, "the Aura Style copy was refused")
    local copy = Model.CustomContainer("target", 1, true)
    Check(copy.placed.iconZoom == 130, "the Aura Style copy did not carry the icon zoom")
    Check(copy.placed.stylePadding == 7, "the Aura Style copy dropped the Custom aura's Lane Padding")
end)

---------------------------------------------------------------------------
-- 5. Pet aura requests
---------------------------------------------------------------------------
Section("A Pet aura request takes the targeted unit route", function()
    local service = Check(M.ApplyService, "ApplyService missing")
    local original, routed = service.RequestUnit, {}
    service.RequestUnit = function(unit, reason, opts) routed[#routed + 1] = { unit, reason, opts } end
    service.RequestAuras("pet", "W16_PET")
    service.RequestUnit = original
    Check(#routed == 1 and routed[1][1] == "pet" and routed[1][3] and routed[1][3].auras == true,
        "the Pet aura request did not reach RequestUnit with auras=true (" .. #routed .. " calls)")
end)

---------------------------------------------------------------------------
-- 6. Group aura apply modes
---------------------------------------------------------------------------
Section("Group aura anchors, offsets and scaling queue the auras mode", function()
    local group = Check(M.GroupPage, "the Group page API is missing")
    local queued = {}
    local QueueGF = group.QueueGF
    group.QueueGF = function(kind, mode, ...)
        queued[#queued + 1] = tostring(mode)
        return QueueGF(kind, mode, ...)
    end
    M.SetMenuStateValue("gfScope", "party")
    M.auraStyleGFLane = "buff"
    M.gfAuraLaneSelection = { party = "buff" }
    M.gfAuraToolSelection = { party = { buff = "style" } }
    Build("gf_auras", "")
    local wrong = {}
    for _, row in ipairs({
        { "lane.buff.cooldownanchor", "TOPLEFT" }, { "lane.buff.cooldownx", 6 }, { "lane.buff.cooldowny", 6 },
        { "lane.buff.stackanchor", "TOPLEFT" }, { "lane.buff.stackx", 6 }, { "lane.buff.stacky", 6 },
        { "root.dynamicscale", true },
    }) do
        queued = {}
        Control("menu2.gf_auras.auras.group-style." .. row[1]).command.set(row[2])
        Settle()
        if #queued == 0 then
            wrong[#wrong + 1] = row[1] .. " queued nothing"
        elseif queued[1] ~= "auras" then
            wrong[#wrong + 1] = row[1] .. " queued '" .. queued[1] .. "'"
        end
    end
    group.QueueGF = QueueGF
    Check(#wrong == 0, table.concat(wrong, ", "))
end)

---------------------------------------------------------------------------
-- 7. Unit Copy To: status keys and the Copy To All prompt
---------------------------------------------------------------------------
Section("Status copy carries the keys the runtime reads", function()
    local UP = Check(M.UnitPage, "the unit page API is missing")
    Check(type(UP.CopyUnitSettings) == "function", "the unit copy function is missing")
    local source, target = db.player, db.target
    source.stateIconsTestMode, source.stateIconsAlpha = true, 0.4
    target.stateIconsTestMode, target.stateIconsAlpha = false, 1
    -- Nothing reads this key: a copy must not touch it.
    target.statusIconsMidnightStyle = "sentinel"
    Check(UP.CopyUnitSettings("player", "target", { status = true }, nil, true), "the status copy was refused")
    Check(target.stateIconsTestMode == true, "the status copy left the test mode switch behind")
    Check(target.stateIconsAlpha == 0.4, "the status copy left the status icon opacity behind")
    Check(target.statusIconsMidnightStyle == "sentinel", "the status copy rewrites a key the runtime never reads")
    target.statusIconsMidnightStyle = nil
end)

Section("Copy To All prompt names every frame it overwrites", function()
    local UP = Check(M.UnitPage, "the unit page API is missing")
    local shown
    local ShowPrompt = M.ShowPrompt
    M.ShowPrompt = function(_, spec) shown = spec end
    UP.ConfirmCopyToAll(function() end)
    M.ShowPrompt = ShowPrompt
    local text = Check(shown and shown.text, "no confirmation prompt was shown")
    local list = Check(text:match("settings on (.-)%.$"), "the prompt does not end with the list of frames")
    local named = {}
    for name in list:gmatch("[^/]+") do named[name] = true end
    local WORD = {
        player = "Player", target = "Target", targettarget = "Target of Target", focustarget = "Focus Target",
        focus = "Focus", boss = "Boss", arena = "Arena", pet = "Pet", pettarget = "Pet Target",
    }
    for _, entry in ipairs(UP.UNIT_COPY_TARGETS) do
        if entry.value ~= "all" then
            Check(named[Check(WORD[entry.value], "unknown copy target " .. entry.value)],
                "the prompt does not name " .. entry.value .. ": " .. list)
        end
    end
end)

---------------------------------------------------------------------------
-- 8. Spell tile reorder
---------------------------------------------------------------------------
Section("Dragging a spell tile reaches the next and the last slot", function()
    local source = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua")
    local chunk = "local max, min = math.max, math.min\n"
        .. Slice(source, "local function EnsureSpellSortOrder(", "local function SetSpellTileBorder(")
        .. "\nreturn InsertSpellAt"
    local InsertSpellAt = assert(loadstring(chunk, "@MSUF_Menu2_GroupIndicators_Reorder.lua"))()
    local trackable = { { name = "A" }, { name = "B" }, { name = "C" }, { name = "D" } }
    local function Move(aura, slot)
        local cfg = { sortOrder = { spec = { "A", "B", "C", "D" } } }
        InsertSpellAt(cfg, "spec", trackable, aura, slot)
        return table.concat(cfg.sortOrder.spec)
    end
    Check(Move("A", 2) == "BACD", "dragging the first tile onto the second slot gives " .. Move("A", 2))
    Check(Move("A", 4) == "BCDA", "dragging the first tile onto the last slot gives " .. Move("A", 4))
    Check(Move("B", 3) == "ACBD", "dragging the second tile onto the third slot gives " .. Move("B", 3))
    Check(Move("D", 1) == "DABC", "dragging the last tile onto the first slot gives " .. Move("D", 1))
    Check(Move("C", 2) == "ACBD", "dragging the third tile onto the second slot gives " .. Move("C", 2))
    Check(Move("B", 2) == "ABCD", "dropping a tile on its own slot moved it")
end)

if #failures > 0 then
    error("menu_pages_review_bugs_smoke (" .. flavor .. "): " .. #failures .. " section(s) failed\n  "
        .. table.concat(failures, "\n  "), 0)
end
print("menu pages: PASS " .. flavor)
