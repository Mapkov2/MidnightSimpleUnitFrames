-- search_exact_visibility_smoke.lua <repoRoot> [flavor]
--
-- An exact search result must land on a control the player can see. The exact
-- contracts of the static index (kind=value=settingKey per selectable view:
-- portrait tabs, texture layer slots, aura workspaces, the Bars scope, ...)
-- decide which view search switches to before it resolves the control. On one
-- client's real core and Options graph with the menu open:
--   * the contract names every view kind: the resolver derives the kind from the
--     contract instead of a hand-kept list, so a new view kind needs no edit here;
--   * a row whose contract names exactly one view prepares that view, and a row
--     without a setting key of its own (the texture layer slot controls, the Bars
--     scope controls) takes the setting that view edits as its target key;
--   * the live record of a built page carries the same kind and key;
--   * every static exact row and every live absorb control is opened; the actual
--     control or its declared visible anchor and all parents must be shown.
--     Only explicit data/state gates below may leave a row hidden.
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then
        failures[#failures + 1] = flavor .. ": " .. message
    end
    return condition
end

-- Controls that stay hidden after an exact open behind a deliberate state gate
-- (one reason each), never behind an unselected view. Their rows are opened
-- like every other row and must still resolve (or, notBuilt, not exist in that
-- state); an entry whose rows all land shown fails as stale.
local KNOWN_HIDDEN = {
    { pattern = "^menu2%.home%.first_load_6%.", reason = "the one-time welcome has been dismissed", notBuilt = true },
    { pattern = "%.texture_layer%.healthabovemode$",
        reason = "shown only while the layer colors by HP gradient and the health condition is not Below" },
    { pattern = "%.texture_layer%.healthlowalpha$",
        reason = "shown only while 'Change opacity below threshold' is on" },
    { pattern = "%.unit%.basics%.enable_now$", reason = "the Enable action appears only for a disabled unit frame" },
    { pattern = "%.unit%.power%.enable_now$", reason = "the Show Power action appears only when the power bar is off" },
    { pattern = "%.unit%.castbar%.use_msuf$", reason = "the MSUF activation action appears only with another castbar backend" },
    { pattern = "%.unit%.status%.midnight_style$", reason = "the selected status must support a symbol or icon pack" },
    { pattern = "%.unit%.status%.selected%.customicon$", reason = "the selected status must support a custom icon" },
    { pattern = "%.unit%.status%.selected%.iconstyle$", reason = "the selected status must support an icon pack" },
    { pattern = "%.unit%.status%.selected%.symbol$", reason = "the selected status must support a symbol" },
    { pattern = "%.unit%.status%.raid_group%.style$", reason = "the selected status must be an inline raid-group indicator" },
    { pattern = "%.unit%.status%.preview%.msuf2_status_test$", reason = "the selected status must have a runtime test mode" },
    { pattern = "%.unit%.status%.preview%.msuf2_status_adv_test$", reason = "the selected status must have a runtime test mode" },
    { pattern = "%.unit%.anchoring%.cooldown_manager$", clients = { Vanilla = true, TBC = true, Mists = true },
        reason = "no cooldown manager to follow: the switch hides until one exists" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.frame%.color$", reason = "the selected spell must have a frame highlight" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.selected%.color$", reason = "a colored spell must be selected" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.placed%.iconeffect$", clients = { Mainline = true, Forever = true },
        reason = "a placed icon spell must be selected (this client's default spell is not one)" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.placed%.barsmoothfill$", reason = "a placed bar spell must be selected" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.placed%.barshowtimer$", reason = "a placed bar spell must be selected" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.placed%.bartimeranchor$", reason = "a placed bar with timer text must be selected" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.placed%.bartimerx$", reason = "a placed bar with timer text must be selected" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.placed%.bartimery$", reason = "a placed bar with timer text must be selected" },
    { pattern = "^menu2%.gf_auras%.group%.spell%.multi_spec%.tracked$", reason = "multi-spec mode and a specific specialization are required" },
    { pattern = "^menu2%.gf_priority%.group%.pins%.row%.[1-5]%.up$", reason = "the pinned player row must exist and have a previous row" },
    { pattern = "^menu2%.gf_priority%.group%.pins%.row%.[1-5]%.down$", reason = "the pinned player row must exist and have a following row" },
    { pattern = "^menu2%.gf_priority%.group%.pins%.row%.[1-5]%.remove$", reason = "the pinned player row must contain a player" },
    { pattern = "^menu2%.gf_priority%.group%.pins%.page%.next$", reason = "the pinned list must have a following page" },
    { pattern = "^menu2%.gf_priority%.group%.pins%.page%.previous$", reason = "the pinned list must have a previous page" },
    { pattern = "^menu2%.opt%.bars%.global%.scope%.overrides%.reset$", reason = "the selected Bars scope must have overrides" },
    { pattern = "^menu2%.opt%.fonts%.global%.scope%.overrides%.reset$", reason = "the selected Fonts scope must have overrides" },
    { pattern = "^menu2%.opt%.fonts%.global%.scope%.override%.enabled$", reason = "the selected Fonts scope must be a frame scope" },
    { pattern = "^menu2%.opt%.colors%.advanced%.class%.power%.resource%.slots%.slot%.([6789])$",
        reason = "the preview resource must have at least this many slots" },
    { pattern = "^menu2%.opt%.colors%.advanced%.class%.power%.resource%.slots%.slot%.10$",
        reason = "the preview resource must have ten slots" },
    { pattern = "%.auras%.custom%-container%.custom[123]%.ordering%.debuff%-sort%-method$",
        reason = "the custom container must be configured to show debuffs", notBuilt = true },
    { pattern = "%.auras%.custom%-container%.filters%.crowdcontrol$",
        reason = "the custom container must be configured to show debuffs", notBuilt = true },
}
-- clients: the gate holds only on these clients; elsewhere the row must show.
local function KnownHidden(controlId)
    for i = 1, #KNOWN_HIDDEN do
        local gate = KNOWN_HIDDEN[i]
        if (not gate.clients or gate.clients[flavor]) and tostring(controlId):find(gate.pattern) then return gate end
    end
end

local function Open()
    local mw = MenuWorld.Open(root, flavor, { locale = "enUS", page = "opt_misc", beforeOptions = function(world)
        -- Use the lifecycle's real session deferral before a home view is built.
        if world.core.FirstLoad6 then world.core.FirstLoad6.deferredThisSession = true end
    end })
    mw.env.InCombatLockdown = function() return false end
    mw.env.UnitAffectingCombat = function() return false end
    return mw
end

-- The harness answers IsVisible() from the widget alone, so walk the parents.
local function ChainShown(widget)
    if not (widget and widget.IsShown) then return false end
    local node = widget
    while node do
        if node.IsShown and not node:IsShown() then return false end
        node = node.GetParent and node:GetParent() or nil
    end
    return true
end

local function StaticRows(M)
    local rows = {}
    for _, rec in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
        local target = rec.exactTarget
        if rec.static and target and target.controlId and target.controlId ~= "" then rows[#rows + 1] = rec end
    end
    return rows
end

local function Pairs(contracts)
    local out = {}
    for kind, value, setting in tostring(contracts or ""):gmatch("([^|=]+)=([^|=]+)=([^|]+)") do
        out[#out + 1] = { kind = kind, value = value, setting = setting }
    end
    return out
end

-- Open one static row the way the result list does and report what it reached.
local function OpenRow(mw, rec)
    local M = mw.M
    mw:Select(rec.key == "opt_misc" and "opt_fonts" or "opt_misc")
    local cached = M.cache[rec.key]
    if cached and cached.wrapper then cached.wrapper._msuf2SearchHighlight = nil end
    local target = rec.exactTarget
    local selected, _, exact = M.Search.OpenTarget(rec.key, rec.label, rec.anchorFallback or rec.label, rec.anchor,
        rec.route, target)
    mw:RunTimers()
    local record, widget = M.RuntimeControlCatalog.ResolveExactTarget(rec.key,
        { controlId = target.controlId, pageKey = rec.key })
    local anchor = record and record.anchor
        or (widget and widget.IsShown and not widget:IsShown() and widget._msuf2ContextColorSearchAnchor) or widget
    return selected == true and exact == true and anchor ~= nil, anchor ~= nil and ChainShown(anchor)
end

local function Describe(rec)
    return ("%s '%s' (%s) contract %s"):format(rec.key, rec.label, rec.exactTarget.controlId,
        tostring(rec.exactTarget.prepareContracts))
end

---------------------------------------------------------------------------
-- The resolver reads the contract, not a list of known kinds.
---------------------------------------------------------------------------
do
    local mw = Open()
    local Search = mw.M.Search
    local kind, value = Search.ResolveExactPreparation("brandNewView=a=player.someKey", "player.someKey")
    Check(kind == "brandNewView" and value == "a", "a contract kind outside any hand list was dropped: " .. tostring(kind))
    kind, value = Search.ResolveExactPreparation({ brandNewView = { a = "player.someKey" } }, "player.someKey")
    Check(kind == "brandNewView" and value == "a", "a live contract kind outside any hand list was dropped")
    local setting
    kind, value, setting = Search.ResolveExactPreparation("viewKind=slot_one=player.texLayerAnchor", "")
    Check(kind == "viewKind" and value == "slot_one" and setting == "player.texLayerAnchor",
        "a key-less control with one concrete view did not take that view's setting: " .. tostring(setting))
    kind = Search.ResolveExactPreparation("viewKind=a=player.x|viewKind=b=player.y", "")
    Check(kind == nil, "a key-less control with two concrete views was not left ambiguous")
    kind, value = Search.ResolveExactPreparation("viewKind=a=player.x|viewKind=b=player.y", "player.y")
    Check(kind == "viewKind" and value == "b", "a control's own setting key did not pick its view")
    kind, value = Search.ResolveExactPreparation("scopeKind=party=gf_party.x|tabKind=tier10=*", "")
    Check(kind == "tabKind" and value == "tier10", "a wildcard view must outrank concrete views of a key-less control")

    -- Every static row: a contract with one view prepares that view.
    local checked, ambiguous = 0, 0
    for _, rec in ipairs(StaticRows(mw.M)) do
        local target = rec.exactTarget
        local list = Pairs(target.prepareContracts)
        if #list == 1 then
            checked = checked + 1
            local only = list[1]
            if target.prepareKind ~= only.kind or target.prepareValue ~= only.value then
                Check(false, "single-view row has no prepareKind: " .. Describe(rec))
            elseif only.setting ~= "*" and tostring(target.settingKey or "") ~= only.setting then
                Check(false, "single-view row does not carry the view's setting: " .. Describe(rec))
            end
        elseif #list > 1 and target.prepareKind == nil then
            ambiguous = ambiguous + 1
        end
    end
    Check(checked > 500, "fewer single-view static rows than expected: " .. checked)
    Check(ambiguous < 100, "too many multi-view rows lost their view: " .. ambiguous)
end

---------------------------------------------------------------------------
-- A built page's live record names the same view and key.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    mw:Select("opt_bars")
    local live
    for _, rec in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
        if not rec.static and rec.key == "opt_bars" and rec.label == "Include healing from others" then live = rec end
    end
    if Check(live ~= nil and live.exactTarget ~= nil, "no live record for the Bars 'Include healing from others'") then
        Check(live.exactTarget.prepareKind == "barsAbsorbTab" and live.exactTarget.prepareValue == "heal",
            "the live Bars record lost its view: " .. tostring(live.exactTarget.prepareKind))
        Check(live.exactTarget.settingKey == "general.healPredAllHealers",
            "the live Bars record has no setting key: " .. tostring(live.exactTarget.settingKey))
    end
    local rows = {}
    for _, rec in ipairs(M.Search._CoreAPI.GetSearchRecords()) do
        local target = rec.exactTarget
        if not rec.static and rec.key == "opt_bars" and target
            and target.controlId:find("%.absorb%.") and not target.controlId:find("workspace%.tab") then
            rows[#rows + 1] = rec
        end
    end
    Check(#rows >= 21, "fewer live absorb controls than expected: " .. #rows)
    for _, rec in ipairs(rows) do
        local reached, shown = OpenRow(mw, rec)
        Check(rec.exactTarget.prepareKind == "barsAbsorbTab" and reached and shown, "live absorb tab: " .. Describe(rec))
    end
    local marks, example, healing, positive
    for _, rec in ipairs(StaticRows(Open().M)) do
        local id = rec.exactTarget.controlId
        if id:find("resource%.extras%.marks%.") then marks = rec end
        if id:find("resource%.extras%.preview%.state$") then example = rec end
        if rec.key == "opt_bars" and rec.label == "Include healing from others" then healing = rec end
        if rec.key == "opt_bars" and rec.label == "Show positive absorbs" then positive = rec end
    end
    if marks and example then
        Check(OpenRow(mw, marks), "resource marks could not be opened")
        local reached, shown = OpenRow(mw, example)
        Check(reached and shown, "Example state remained hidden after Resource marks")
    end
    if Check(healing and positive, "absorb sequence rows missing") then
        Check(OpenRow(mw, healing), "heal tab could not be opened")
        local reached, shown = OpenRow(mw, positive)
        Check(reached and shown, "positive absorbs remained hidden after healing")
    end
end

---------------------------------------------------------------------------
-- Open every exact row, including rows behind deliberate state gates.
---------------------------------------------------------------------------
do
    local mw = Open()
    local M = mw.M
    local opened = 0
    -- Taken once: a built page replaces its static rows with live ones.
    local rows = StaticRows(M)
    table.sort(rows, function(a, b)
        local at, bt = a.exactTarget, b.exactTarget
        return a.key .. tostring(at.prepareKind) .. tostring(at.prepareValue) .. at.controlId
            < b.key .. tostring(bt.prepareKind) .. tostring(bt.prepareValue) .. bt.controlId
    end)
    for rowIndex, rec in ipairs(rows) do
        -- Fresh worlds bound the harness's retained frame inventory. The real
        -- client owns frames permanently; this sweep visits thousands of views.
        if rowIndex % 100 == 1 then
            mw, M = nil, nil
            collectgarbage("collect")
            mw = Open()
            M = mw.M
        end
        local target = rec.exactTarget
        do
            opened = opened + 1
            local reached, shown = OpenRow(mw, rec)
            local gate = KnownHidden(target.controlId)
            if gate then
                gate.probed = (gate.probed or 0) + 1
                if not (reached and shown) then gate.hidden = (gate.hidden or 0) + 1 end
                Check(reached or (not shown and gate.notBuilt), "deliberate gate failed to resolve: " .. Describe(rec)
                    .. "; " .. gate.reason)
            elseif not reached then
                Check(false, "exact open did not resolve its control: " .. Describe(rec))
            elseif not shown then
                Check(false, "exact open left the control on a hidden view: " .. Describe(rec))
            end
        end
    end
    Check(opened > 50, "fewer rows opened than expected: " .. opened)
    -- An entry whose rows all land shown now is stale: remove it.
    for _, gate in ipairs(KNOWN_HIDDEN) do
        Check(not gate.probed or (gate.hidden or 0) > 0, "KNOWN_HIDDEN entry is stale, every row it matches is shown now ("
            .. gate.pattern .. "): " .. gate.reason)
    end
end

if #failures > 0 then
    -- A broken contract fails hundreds of rows alike: show the first few.
    local shown = {}
    for i = 1, math.min(#failures, 25) do shown[i] = failures[i] end
    if #failures > #shown then shown[#shown + 1] = flavor .. ": ... and " .. (#failures - #shown) .. " more" end
    error("search_exact_visibility_smoke failed (" .. #failures .. "):\n  " .. table.concat(shown, "\n  "))
end
print("search_exact_visibility_smoke: ok (" .. flavor .. "; contract kinds are derived, key-less single-view controls"
    .. " take their view's setting, exact opens leave the control shown)")
