local root = arg and arg[1] or "."

local function Read(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local widgets = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_Widgets.lua")
local unitText = Read("MidnightSimpleUnitFrames/Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua")
local quickSettings = Read("MidnightSimpleUnitFrames/Shell/Menu2/MSUF_Menu2_TextQuickSettings.lua")

local helperStart = assert(widgets:find("local CONTEXT_COLOR_SHORTCUT_TEXT", 1, true),
    "card-local RGB shortcut helper is missing")
local helperEnd = assert(widgets:find("local function AttachBoundColorToContextCard", helperStart, true),
    "card-local RGB helper boundary is missing")
local helper = widgets:sub(helperStart, helperEnd - 1)

assert(helper:find('shortcut:SetPoint("TOPRIGHT", card, "TOPRIGHT", tonumber(opts.offsetX) or -12, tonumber(opts.offsetY) or -10)', 1, true),
    "RGB shortcut does not expose an exact top-right card anchor")
assert(helper:find("math.min(4, tonumber(opts.maxTargets) or 4)", 1, true),
    "RGB shortcut does not enforce the compact four-target limit")
assert(helper:find("if #targets > maxTargets then return false end", 1, true),
    "RGB shortcut silently truncates an oversized target set")
for _, forbidden in ipairs({ 'SetScript("OnUpdate"', "RegisterEvent", "C_Timer" }) do
    assert(not helper:find(forbidden, 1, true), "RGB shortcut adds recurring work: " .. forbidden)
end

assert(widgets:find("card._msuf2ControlCard = true", 1, true),
    "ControlCard does not identify the local shortcut host")
assert(widgets:find("section._msuf2ContextColorHost = true", 1, true)
    and widgets:find("body._msuf2ContextColorHost = true", 1, true),
    "standard and accordion content surfaces are not registered as color hosts")
assert(widgets:find("local function PositionedContextColorCard", 1, true),
    "sibling controls cannot resolve their visible ControlCard")
assert(widgets:find("#card._msuf2ContextColorOwners > 4", 1, true),
    "large palettes are not protected from arbitrary four-color truncation")
assert(widgets:find("AttachBoundColorToContextCard(colorControl)", 1, true),
    "ordinary bound colors are not registered with their local ControlCard")
assert(unitText:find("W.AttachContextColorShortcut(nameContent", 1, true),
    "Name submenu does not attach the shortcut to its primary content card")
assert(unitText:find("W.AttachContextColorShortcut(content", 1, true),
    "HP/Power submenus do not attach the shortcut to their shared primary content card")
assert(unitText:find("offsetY = -24", 1, true),
    "Text shortcuts are not aligned with the marked switch row")
assert(unitText:find("textSettings = { scope = unit, unit = unit, kind = kind }", 1, true),
    "HP/Power submenu does not pass its mode-local descriptor")
assert(quickSettings:find('if mode == "HEALTH" then', 1, true),
    "HP health mode does not expose its three gradient stops")
assert(quickSettings:find('return { PowerColorTarget(data.powerToken or "MANA") }', 1, true),
    "Power type mode does not resolve the deterministic preview power color")
assert(not unitText:find("W.AttachContextColorShortcut(advancedLayers", 1, true),
    "More Options incorrectly exposes a color shortcut without a color target")

do
    local function Noop() end
    local function Frame(parent)
        local frame = { parent = parent, scripts = {}, hooks = {} }
        function frame:GetParent() return self.parent end
        function frame:GetFrameLevel() return 7 end
        function frame:SetFrameLevel(value) self.frameLevel = value end
        function frame:ClearAllPoints() self.point = nil end
        function frame:SetPoint(...) self.point = { ... } end
        function frame:SetAlpha(value) self.alpha = value end
        function frame:SetShown(value) self.shown = value and true or false end
        function frame:Show() self.shown = true end
        function frame:Hide() self.shown = false end
        function frame:HookScript(script, callback) self.hooks[script] = callback end
        function frame:SetScript(script, callback) self.scripts[script] = callback end
        return frame
    end

    local providerCalls, historyBegins, historyCommits = 0, 0, 0
    local trackedRefreshes = {}
    local combatLocked = false
    local M = {
        AddTooltip = Noop,
        BlockCombatAction = function() return combatLocked end,
        BeginHistoryTransaction = function() historyBegins = historyBegins + 1; return true end,
        CommitHistoryTransaction = function() historyCommits = historyCommits + 1; return true end,
        TrackRefresh = function(_, refresh) trackedRefreshes[#trackedRefreshes + 1] = refresh end,
    }
    local T = {
        Button = function(parent, text, width, height)
            local button = Frame(parent)
            button.text, button.width, button.height = text, width, height
            button._msuf2Label = {
                ClearAllPoints = Noop, SetAllPoints = Noop, SetJustifyH = Noop,
            }
            return button
        end,
    }
    local W = {}
    local factory = assert(loadstring("return function(W, M, T, max) " .. helper .. " return W end"))
    W = factory()(W, M, T, math.max)

    local opened, openCount
    openCount = 0
    W.OpenColorContextPicker = function(title, owners, note, initial)
        openCount = openCount + 1
        opened = { title = title, owners = owners, note = note, initial = initial }
    end

    local values = {}
    for i = 1, 5 do values[i] = { 0.1 * i, 0.2, 0.3 } end
    local function Targets()
        providerCalls = providerCalls + 1
        local targets = {}
        for i = 1, 4 do
            local index = i
            targets[i] = {
                label = "Color " .. tostring(i),
                getRGB = function() return values[index][1], values[index][2], values[index][3] end,
                setRGB = function(r, g, b) values[index] = { r, g, b } end,
            }
        end
        return targets
    end

    local card = Frame()
    card._msuf2Width = 420
    card._msuf2ControlCardTitle = "HP Text colors"
    card.title = { SetWidth = function(_, width) card.titleWidth = width end }
    local shortcut = assert(W.AttachContextColorShortcut(card, { getTargets = Targets, offsetY = -24 }))
    assert(providerCalls == 0, "target provider ran during card construction")
    assert(W.AttachContextColorShortcut(card, { getTargets = Targets }) == shortcut,
        "duplicate attachment created a second shortcut")
    assert(shortcut.point and shortcut.point[1] == "TOPRIGHT" and shortcut.point[2] == card
        and shortcut.point[3] == "TOPRIGHT" and shortcut.point[4] == -12 and shortcut.point[5] == -24,
        "shortcut lost the exact top-right card anchor")

    local buildContext = { _msuf2Building = true }
    local contextParent = Frame()
    contextParent._msuf2CollapsibleEntry = { builder = { ctx = buildContext } }
    local replacedCard = Frame(contextParent)
    local replacedProviderCalls = 0
    local replaced = assert(W.AttachContextColorShortcut(replacedCard, {
        getTargets = function() replacedProviderCalls = replacedProviderCalls + 1; return Targets() end,
    }))
    assert(#trackedRefreshes == 0, "shortcut without dynamic relevance registered needless refresh work")
    assert(W.AttachContextColorShortcut(replacedCard, {
        isRelevant = function() return false end,
        getTargets = function() replacedProviderCalls = replacedProviderCalls + 1; return Targets() end,
    }) == replaced, "semantic replacement created a duplicate shortcut")
    assert(#trackedRefreshes == 1, "later semantic relevance was not registered exactly once")
    assert(replaced.shown == false, "hidden-build shortcut ignored its initial relevance state")
    assert(replacedProviderCalls == 0, "relevance check eagerly resolved semantic color targets")
    replaced.scripts.OnClick(replaced)
    assert(replacedProviderCalls == 0 and openCount == 0,
        "irrelevant shortcut resolved targets or opened from its click path")

    shortcut.scripts.OnClick(shortcut)
    assert(providerCalls == 1, "target provider did not run exactly once on click")
    assert(opened and opened.title == "HP Text colors", "card context title was not preserved")
    assert(#opened.owners == 4, "shortcut did not pass exactly the compact four-target maximum")
    assert(opened.initial == opened.owners[1], "first relevant target is not selected initially")
    opened.owners[1]:_msuf2BeginColorInteraction()
    opened.owners[1]:SetRGB(0.9, 0.8, 0.7)
    opened.owners[1]._msuf2OnColorChanged(0.9, 0.8, 0.7)
    opened.owners[1]:_msuf2CommitColorInteraction()
    assert(values[1][1] == 0.9 and values[1][2] == 0.8 and values[1][3] == 0.7,
        "virtual owner did not apply its RGB target")
    assert(historyBegins == 1 and historyCommits == 1,
        "virtual owner did not preserve one color history transaction")

    local overflowCard = Frame()
    local overflow = W.AttachContextColorShortcut(overflowCard, { getTargets = function()
        local targets = Targets()
        targets[5] = {
            label = "Color 5",
            getRGB = function() return values[5][1], values[5][2], values[5][3] end,
            setRGB = function(r, g, b) values[5] = { r, g, b } end,
        }
        return targets
    end })
    overflow.scripts.OnClick(overflow)
    assert(openCount == 1, "oversized target context opened a silently truncated picker")

    local emptyCard = Frame()
    local empty = W.AttachContextColorShortcut(emptyCard, { getTargets = function() return {} end })
    empty.scripts.OnClick(empty)
    assert(openCount == 1, "empty target context opened a picker")

    combatLocked = true
    shortcut.scripts.OnClick(shortcut)
    assert(providerCalls == 2 and openCount == 1,
        "combat-gated shortcut still resolved targets or opened the picker")
end

do
    local contextStart = assert(widgets:find("local function PositionedContextColorCard", 1, true))
    local contextEnd = assert(widgets:find("--- Register every bound color", contextStart, true))
    local contextHelpers = widgets:sub(contextStart, contextEnd - 1)
    local W = {}
    local factory = assert(loadstring("return function(W) " .. contextHelpers
        .. " return AttachBoundColorToContextCard end"))
    local attach = factory()(W)
    W.AttachContextColorShortcut = function(host)
        if host._msuf2ContextColorShortcut then return host._msuf2ContextColorShortcut end
        local shortcut = { hidden = false }
        function shortcut:Hide() self.hidden = true end
        host._msuf2ContextColorShortcut = shortcut
        return shortcut
    end

    local host = {
        _msuf2ContextColorHost = true,
        _msuf2ControlCards = {},
    }
    local left = {
        _msuf2ControlCard = true,
        _msuf2ContextColorLeft = 0, _msuf2ContextColorTop = -20,
        _msuf2ContextColorWidth = 180, _msuf2ContextColorHeight = 180,
    }
    local right = {
        _msuf2ControlCard = true,
        _msuf2ContextColorLeft = 220, _msuf2ContextColorTop = -20,
        _msuf2ContextColorWidth = 180, _msuf2ContextColorHeight = 180,
    }
    host._msuf2ControlCards = { left, right }
    local function Color(index)
        local control = { _msuf2CommandAction = { settingKey = "color." .. tostring(index) } }
        function control:GetParent() return host end
        function control:GetRGB() return 1, 1, 1 end
        function control:SetRGB() end
        return control
    end

    local first = Color(1)
    assert(attach(first) == false, "unpositioned sibling color attached to the outer host too early")
    first._msuf2ContextLayoutParent = host
    first._msuf2ContextLayoutX, first._msuf2ContextLayoutY = 250, -80
    assert(attach(first) == true and right._msuf2ContextColorOwners[1] == first,
        "positioned sibling color did not attach to its matching ControlCard")
    for i = 2, 5 do
        local control = Color(i)
        control._msuf2ContextLayoutParent = host
        control._msuf2ContextLayoutX, control._msuf2ContextLayoutY = 250, -80
        assert(attach(control) == true)
    end
    assert(right._msuf2ContextColorShortcut.hidden == true,
        "a palette larger than four kept a misleading truncated shortcut")

    local plainHost = { _msuf2ContextColorHost = true }
    local direct = Color("direct")
    function direct:GetParent() return plainHost end
    assert(attach(direct) == true and plainHost._msuf2ContextColorOwners[1] == direct,
        "ordinary content surface did not receive its bound color")
end

print("text_context_color_shortcut_smoke: ok")
