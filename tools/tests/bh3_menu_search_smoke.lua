local root, flavor, mode = assert(arg[1]), arg[2] or "Mainline", arg[3] or "identity"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { locale = mode == "profile" and "deDE" or "enUS", beforeOptions = function(w) w.core.FinalizeLocale() end })
local M, env = mw.M, mw.env
local api, routing = M.Search._CoreAPI, M.Search._RoutingAPI
if mode == "identity" then
    M.SelectPage("opt_castbar"); mw:RunTimers()
    local section = assert(M.cache.opt_castbar.sections.castbar_interrupt_ready)
    section._msuf2CollapsibleEntry.SetOpenImmediate(true); mw:RunTimers()
    local count = 0
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.key == "opt_castbar" and rec.label == "Show on Target castbar" then
            count = count + 1
            assert(rec.exactTarget and rec.exactTarget.controlId, "bound row lost exact identity")
        elseif rec.label == "Show on enemy nameplates (MSUF Suite)" then
            assert(M.CastbarSuiteNameplatesSupported(), "hidden unsupported nameplate setting leaked into warm search")
        end
    end
    assert(count == 1, "cold/live copies must merge into one canonical row; count=" .. count)
elseif mode == "scope" then
    local route = routing.SearchRouteForTarget("gf_auras", "mythic raid buffs", "")
    routing.ApplySearchRoute("gf_auras", route)
    assert(M.gfScope ~= "mythicraid" or flavor == "Mainline", "query persisted unsupported Mythic Raid")
    local oldScope = M.gfScope
    local result = routing.OpenSearchTarget("gf_auras", "", "", nil, nil,
        { prepareKind = "groupAuraWorkspace", prepareValue = "mythicraid_buff_filters" })
    if flavor ~= "Mainline" then assert(result == false and M.gfScope == oldScope, "unsupported exact scope must fail before mutation") end
    for _, rec in ipairs(api.GetSearchRecords()) do
        local target = rec.exactTarget
        if target and target.prepareKind == "groupAuraWorkspace" and target.prepareValue:match("^mythicraid_") then
            assert(flavor == "Mainline", "unsupported scope leaked into search")
        end
    end
    local target = { controlId = "menu2.gf_layout.group.field.targetsenabled",
        settingKey = "gf_party.targetsEnabled", sectionId = "party_targets",
        prepareKind = "groupScope", prepareValue = "party" }
    local partyEntry
    for i = 1, 2 do
        M.SetMenuStateValue("gfScope", "raid")
        M.SelectPage("gf_layout")
        mw:RunTimers()
        assert(not M.cache.gf_layout.sections.party_targets, "party section leaked into raid view")
        local selected, reached, exact = routing.OpenSearchTarget("gf_layout", "unrelated", "", nil,
            { accordion = { ["gf_layout:party_targets"] = true } }, target)
        mw:RunTimers()
        assert(selected and reached and exact and M.gfScope == "party", "deep link did not select its declared group view")
        if partyEntry then assert(M.cache.gf_layout == partyEntry, "declared party view was unnecessarily rebuilt") end
        partyEntry = M.cache.gf_layout
    end
elseif mode == "aura" then
    M.SetMenuStateValue("gfScope", "party")
    M.gfAuraLaneSelection = { party = "buff" }
    M.gfAuraToolSelection = { party = { buff = "filters" } }
    M.SelectPage("gf_auras"); mw:RunTimers()
    local row
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.key == "gf_auras" and rec.label == "Big Defensive" then row = rec; break end
    end
    assert(row and row.exactTarget, "filter row missing")
    assert(row.exactTarget.prepareKind == "groupAuraWorkspace" and row.exactTarget.prepareValue == "party_buff_filters", "aura row lost its view")
    M.gfAuraToolSelection.party.buff = "layout"
    M.SelectPage("gf_auras"); mw:RunTimers()
    local selected, reached, exact = routing.OpenSearchTarget(row.key, "unrelated words", "", nil, nil, row.exactTarget)
    mw:RunTimers()
    assert(selected and reached and exact, "aura exact row did not reach control independent of query")

    -- Search and focus open collapsed sections at once (PageBuilder: "Search/focus ... remain
    -- immediate"); only a header click animates. The scroll target is rechecked at 0 and 0.05 s,
    -- so an animated open would measure a page that is still growing and, for a control in the
    -- page's last screenful, land short of it (the scroll clamps to the partly grown page).
    -- Time-stepped at 60 fps: frames drive the OnUpdate motions and the queued C_Timer callbacks.
    local widgets, INSET, FRAME = mw.world.widgets, 44, 1 / 60
    local Methods = widgets.Methods
    local viewport = 800
    M.scrollFrame.GetHeight = function() return viewport end
    -- Flow layout is enough here: the top edge comes from the first top anchor, down the chain.
    local function TopOf(frame, depth)
        if not frame or (depth or 0) > 80 then return 0 end
        local point
        for _, candidate in ipairs(frame.points or {}) do
            if tostring(candidate.point):upper():find("TOP") then point = candidate break end
        end
        point = point or (frame.points and frame.points[1])
        if not point then return TopOf(frame.parent, (depth or 0) + 1) end
        local relative = point.relativeTo or frame.parent
        if type(relative) == "string" then relative = env[relative] end
        if type(relative) ~= "table" then relative = frame.parent end
        local relativeTop = relative and TopOf(relative, (depth or 0) + 1) or 0
        local relativeHeight = relative and tonumber(relative.height) or 0
        local anchor = tostring(point.relativePoint or point.point):upper()
        local base = anchor:find("TOP") and relativeTop or anchor:find("BOTTOM") and (relativeTop - relativeHeight)
            or (relativeTop - relativeHeight / 2)
        base = base + (tonumber(point.y) or 0)
        local own, height = tostring(point.point):upper(), tonumber(frame.height) or 0
        if own:find("TOP") then return base end
        return base + (own:find("BOTTOM") and height or height / 2)
    end
    Methods.GetTop = function(self) return TopOf(self) end
    Methods.GetBottom = function(self) return TopOf(self) - (tonumber(self.height) or 0) end
    local function Shown(frame)
        while frame do
            if frame.IsShown and not frame:IsShown() then return false end
            frame = frame.GetParent and frame:GetParent() or nil
        end
        return true
    end
    -- Frames holding an OnUpdate script: the ones present now plus every later SetScript.
    local ticking = {}
    local setScript = Methods.SetScript
    Methods.SetScript = function(self, name, handler)
        if name == "OnUpdate" then ticking[self] = handler and true or nil end
        return setScript(self, name, handler)
    end
    for _, frame in ipairs(widgets.frames) do
        if frame.scripts and frame.scripts.OnUpdate then ticking[frame] = true end
    end
    local function Step()
        widgets.now = widgets.now + FRAME
        local drivers = {}
        for frame in pairs(ticking) do
            local update = frame.scripts and frame.scripts.OnUpdate
            if update and debug.getinfo(update, "S").source:find("MidnightSimpleUnitFrames_Options", 1, true)
                and Shown(frame) then drivers[#drivers + 1] = { frame, update } end
        end
        for _, driver in ipairs(drivers) do driver[2](driver[1], FRAME) end
        local index = 1
        while index <= #widgets.timers do
            local timer = widgets.timers[index]
            timer.due = timer.due or (widgets.now - FRAME + (tonumber(timer.delay) or 0))
            if timer.due <= widgets.now + 1e-9 then
                table.remove(widgets.timers, index)
                if not timer.cancelled then timer.callback() end
                index = 1
            else
                index = index + 1
            end
        end
    end
    local function RunFor(seconds) for _ = 1, math.ceil(seconds / FRAME) do Step() end end
    local function Resolve(rec)
        local record, widget = M.RuntimeControlCatalog.ResolveExactTarget(rec.key,
            { controlId = rec.exactTarget.controlId, pageKey = rec.key })
        return record and record.anchor or widget
    end
    local function Chain(region)
        local entries, node = {}, region
        while node do
            local entry = node._msuf2CollapsibleEntry
            if entry and entries[#entries] ~= entry then entries[#entries + 1] = entry end
            node = node.GetParent and node:GetParent() or nil
        end
        return entries
    end
    local function SetChain(region, open)
        for _, entry in ipairs(Chain(region)) do entry.SetOpenImmediate(open) end
    end
    local function Motion(entry)
        local driver = entry._msuf2AccordionMotion
        return entry._msuf2MotionActive == true or (driver and driver:GetScript("OnUpdate") ~= nil)
    end
    local function Open(rec)
        return M.Search.OpenTarget(rec.key, rec.label, rec.anchorFallback or rec.label, rec.anchor, rec.route, rec.exactTarget)
    end
    -- Settled geometry of a nested gf_auras row: the scroll that puts it at INSET, and the page height.
    -- A first search selects the row's own Aura workspace (lane and tool), which decides what is built.
    local function Settled(rec)
        Open(rec); mw:RunTimers()
        local region = M.activeKey == "gf_auras" and Resolve(rec)
        if not region or #Chain(region) < 2 then return nil end
        SetChain(region, true)
        local raw = TopOf(M.cache.gf_auras.wrapper) - TopOf(region) - INSET
        local pageHeight = M.scrollChild:GetHeight()
        SetChain(region, false)
        M.Theme.StopAllMenuAnimations()
        return raw, pageHeight, region
    end

    local landed, animatedClicks = 0, 0
    for _, rec in ipairs(api.GetSearchRecords()) do
        if landed >= 3 then break end
        local target = rec.exactTarget
        if rec.key == "gf_auras" and rec.static and target and target.controlId and target.controlId ~= "" then
            local raw, pageHeight = Settled(rec)
            -- The control sits in the last screenful: a viewport of exactly the page below its scroll position.
            local view = raw and math.floor(pageHeight - raw)
            if view and raw >= 100 and view >= 200 and view <= 4000 then
                viewport = view
                mw:Select("opt_misc"); RunFor(0.2)
                M.scrollFrame:SetVerticalScroll(0)
                Open(rec)
                local region = Resolve(rec)
                local chain, animated = Chain(region), nil
                for _ = 1, math.ceil(0.6 / FRAME) do
                    Step()
                    for _, entry in ipairs(chain) do animated = animated or (entry._msuf2MotionActive and entry.stateKey) end
                end
                region = Resolve(rec)
                assert(region and M.activeKey == "gf_auras", "search did not land on " .. tostring(rec.label))
                local scroll = M.scrollFrame:GetVerticalScroll()
                local placed = TopOf(M.cache.gf_auras.wrapper) - TopOf(region) - scroll
                assert(math.abs(placed - INSET) <= 1, string.format(
                    "search to '%s' in the last screenful landed %.1f px off the control (scroll %.1f, wanted %.1f)",
                    tostring(rec.label), placed - INSET, scroll, raw))
                for _, entry in ipairs(chain) do assert(entry.open, "search left a section closed") end
                assert(not animated, "search animated the section it opened: " .. tostring(animated))
                landed = landed + 1

                -- A manual header click still animates: the body grows over frames, not at once.
                local entry = Chain(region)[1]
                entry.SetOpenImmediate(false)
                M.Theme.StopAllMenuAnimations()
                local header, full = entry.header, entry.contentHeight
                assert(not Motion(entry) and entry.outer:GetHeight() <= entry.headerHeight + 0.5, "section did not start closed")
                header:Click()
                assert(entry.open and entry._msuf2MotionActive == true, "a header click no longer animates the section")
                assert(entry.outer:GetHeight() < entry.headerHeight + full, "animated open jumped to full height")
                RunFor(0.03)
                local mid = entry.outer:GetHeight()
                assert(mid > entry.headerHeight and mid < entry.headerHeight + full, "animated open has no intermediate height")
                RunFor(0.6)
                assert(not entry._msuf2MotionActive and math.abs(entry.outer:GetHeight() - (entry.headerHeight + full)) <= 0.5,
                    "animated open did not settle at the full height")
                animatedClicks = animatedClicks + 1
            end
        end
    end
    assert(landed >= 1, "no nested gf_auras row sits in a last screenful: the search landing check is vacuous")
    assert(animatedClicks == landed, "header click animation was not checked for every landed row")
elseif mode == "alpha" then
    M.SelectPage("uf_target"); mw:RunTimers()
    local section = M.cache.uf_target.sections.transparency
    section._msuf2CollapsibleEntry.SetOpenImmediate(true); mw:RunTimers()
    local row
    for _, rec in ipairs(api.GetSearchRecords()) do
        if rec.key == "uf_target" and rec.exactTarget and rec.exactTarget.settingKey == "target.oocFadeAlpha" then row = rec; break end
    end
    assert(row and row.exactTarget.prepareKind == "unitAlphaTab" and row.exactTarget.prepareValue == "ooc", "OOC row must declare exact tab")
    local selected, reached, exact = routing.OpenSearchTarget(row.key, "irrelevant words", "", nil, nil, row.exactTarget)
    local _, widget = M.RuntimeControlCatalog.ResolveExactTarget(row.key, row.exactTarget)
    assert(selected and reached and exact and widget and widget:IsVisible(), "OOC exact navigation must reveal its control")
elseif mode == "profile" then
    env.MSUF_GlobalDB.global.profileSyncGroups = { { name = "Regression", members = { Default = true }, modules = { unitframes = true }, exclude = {} } }
    local found = {}
    for _, row in ipairs(M.ProfileSearch.Collect()) do
        if row.controlId and row.controlId:find("sync.module.", 1, true) then found[row.label] = true end
    end
    assert(found[M.Tr("Unitframes")] and found[M.Tr("Class Resources")], "sync search labels differ from page labels")
    assert(not found.unitframes and not found.resources, "raw module IDs leaked into translated search")
else error(mode) end
print("search regression " .. mode .. ": PASS")
