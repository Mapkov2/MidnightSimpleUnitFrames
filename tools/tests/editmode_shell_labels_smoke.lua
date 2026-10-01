-- MSUF Edit Mode shell labels and HUD tools (review 2, classic-shell):
--   F17 arena is a stacked cluster like boss: no "Arena Name Position" mover
--       label, an "Arena" inspector label, and an open arena aura lane shows in
--       the HUD inspector like a boss lane;
--   F18 the unit popup's "Copy size to" targets only list units the client
--       has (Client.SupportsUnit), so "All units" creates no foreign tables;
--   F19 each detached power bar names its unit, and HUD Reset on a selection
--       it cannot reset says so instead of "select a frame first";
--   F20 HUD Reset puts a unit frame at its default position, like the frame
--       popup's Reset, not at 0,0;
--   F23 a toolbar tooltip still raised when the HUD hides gives its frame
--       level back.
-- Real core and Options graphs (tools/tests/client_world.lua).
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local function FindUpvalue(fn, name, seen)
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 255 do
        local upName, value = debug.getupvalue(fn, i)
        if not upName then break end
        if upName == name then return value end
        local found = type(value) == "function" and FindUpvalue(value, name, seen)
        if found then return found end
    end
end

local function Boot(flavor)
    local world = World.New(root, flavor):Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env = world.env
    world.core.UF.Apply = function() return true end
    env.MSUF_ForceReanchorAllUnitFrames_Once = function() end
    env.MSUF_InitProfiles()
    env.MSUF2.ApplyService.Flush = function() return true end
    local tooltip = env.CreateFrame("GameTooltip")
    tooltip.level, tooltip.strata = 7, "TOOLTIP"
    function tooltip:SetOwner(owner) self.owner = owner end
    function tooltip:SetText(text) self.text = text end
    function tooltip:GetFrameLevel() return self.level end
    function tooltip:SetFrameLevel(level) self.level = level end
    function tooltip:GetFrameStrata() return self.strata end
    function tooltip:SetFrameStrata(strata) self.strata = strata end
    env.GameTooltip = tooltip
    return world, env
end

local function LabelTexts(world)
    local texts = {}
    for _, frame in ipairs(world.widgets.frames) do
        local label = frame._msuf2Label or frame._label
        local text = label and label.GetText and label:GetText()
        if text then texts[text] = frame end
    end
    return texts
end

local function InspectorText(world, env)
    env.MSUF_EM2.HUD.RefreshControls(true)
    for _, frame in ipairs(world.widgets.frames) do
        if frame.frameName == "MSUF_EM2_HUD_Row2" and frame._inspectorSelectionFS then
            return frame._inspectorSelectionFS:GetText()
        end
    end
end

local EXPECTED_COPY_TARGETS = {
    Mainline = "player,target,focus,focustarget,targettarget,pet,pettarget,boss,arena",
    Forever = "player,target,focus,focustarget,targettarget,pet,pettarget,boss",
    Vanilla = "player,target,targettarget,pet,pettarget",
    TBC = "player,target,focus,focustarget,targettarget,pet,pettarget,arena",
    Mists = "player,target,focus,focustarget,targettarget,pet,pettarget,boss,arena",
}

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local world, env = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local context = flavor
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    local client = world.core.Client

    -- F18
    local targets = FindUpvalue(EM2.UnitPopup.Open, "UNIT_COPY_TARGETS")
    if Check(type(targets) == "table", context .. " F18: unit copy targets not reachable") then
        local keys = {}
        for i = 1, #targets do keys[i] = targets[i].key end
        Check(table.concat(keys, ",") == EXPECTED_COPY_TARGETS[flavor], context
            .. " F18: copy targets are " .. table.concat(keys, ","))
    end

    -- F17 movers and inspector
    local texts = LabelTexts(world)
    Check(texts["Arena Name Position"] == nil, context .. " F17: the arena cluster shows a name-position label")
    if client.SupportsUnit("arena") then
        local saveUnit, saveGroup, isOpen = env.MSUF_EM2_ActiveAuraUnit, env.MSUF_EM2_ActiveAuraGroup, EM2.AuraPopup.IsOpen
        env.MSUF_EM2_ActiveAuraUnit, env.MSUF_EM2_ActiveAuraGroup = "arena2", "buff"
        EM2.AuraPopup.IsOpen = function() return true end
        local text = tostring(InspectorText(world, env))
        Check(text:find("^Arena") and text:find("Auras", 1, true), context
            .. " F17: an open arena aura lane shows in the inspector as " .. text)
        env.MSUF_EM2_ActiveAuraUnit, env.MSUF_EM2_ActiveAuraGroup, EM2.AuraPopup.IsOpen = saveUnit, saveGroup, isOpen
        EM2.State.SetUnitKey("arena")
        local arenaText = tostring(InspectorText(world, env))
        Check(arenaText:find("^Arena"), context .. " F17: the arena selection is labelled " .. arenaText)
    end

    -- F19 labels
    local seen = {}
    for _, unit in ipairs({ "player", "target", "focus", "targettarget", "focustarget", "pet", "pettarget" }) do
        local key = "power_" .. unit
        local label = EM2.Util.ElementLabel and EM2.Util.ElementLabel(key, EM2.Registry.Get(key))
        Check(type(label) == "string" and not seen[label], context .. " F19: detached power label for "
            .. unit .. " is " .. tostring(label))
        if label then seen[label] = true end
    end
    EM2.State.SetUnitKey("power_player")
    local powerText = tostring(InspectorText(world, env))
    Check(powerText:find("Detached power bar (Player)", 1, true) == 1, context
        .. " F19: the inspector shows the player power bar as " .. powerText)

    -- F19 Reset message, F20 default position
    local status
    local setStatus = EM2.HUD.SetStatus
    EM2.HUD.SetStatus = function(text, kind, seconds) status = text; return setStatus(text, kind, seconds) end
    EM2.State.SetUnitKey("classpower")
    EM2.HUD.ResetCurrentPosition()
    Check(status == env.MSUF_EM2.Util.Tr("Reset unavailable"), context
        .. " F19: HUD Reset on Class Resources said " .. tostring(status))
    local conf = env.MSUF_DB.player
    conf.offsetX, conf.offsetY = 5, 5
    EM2.State.SetUnitKey("player")
    EM2.HUD.ResetCurrentPosition()
    local defaultX, defaultY = env.MSUF_GetDefaultUnitOffsets("player")
    Check(conf.offsetX == defaultX and conf.offsetY == defaultY, context .. " F20: HUD Reset put the player frame at "
        .. tostring(conf.offsetX) .. ", " .. tostring(conf.offsetY))
    EM2.HUD.SetStatus = setStatus

    -- F23
    local tooltip = env.GameTooltip
    local tipped
    for _, frame in ipairs(world.widgets.frames) do
        if frame._msufTipText and frame.scripts and frame.scripts.OnEnter then tipped = frame; break end
    end
    if Check(tipped ~= nil, context .. " F23: no toolbar control carries a tooltip") then
        tipped.scripts.OnEnter(tipped)
        Check(tooltip.level == 1620, context .. " F23: the toolbar tip did not raise the tooltip")
        EM2.HUD.Hide()
        Check(tooltip.level == 7, context .. " F23: hiding the HUD left the tooltip at level " .. tostring(tooltip.level))
    end
    EM2.State.Exit("test")
    world.widgets:RunTimers()
end

if #failures > 0 then
    error("editmode_shell_labels_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_shell_labels_smoke: ok (5 clients; arena labels, copy targets, power labels, HUD reset, tooltip level)")
