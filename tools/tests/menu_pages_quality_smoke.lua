-- menu_pages_quality_smoke.lua <repoRoot> <flavor>
--
-- Boots the flavor's whole shipped core and Options graph through
-- tools/tests/client_world.lua, builds the real Menu2 pages hidden (as the
-- search index does) and checks page-level defects that only show once the
-- page is built:
--
--   1. Group Auras > Spell Indicators, multi-spec mode: the "Multi-Spec Entry"
--      dropdown, the "Track selected multi spec" toggle, the "Aura Spell IDs"
--      input and the rest of the "Edit Spell" column never overlap, and the
--      "Show on Frame" card keeps its column when the spell grid re-lays it out.
--   2. The group growth direction tiles show their label in the client language.
--   3. Labels in the client language are drawn with the client's own font
--      (STANDARD_TEXT_FONT): FRIZQT__.TTF has no Cyrillic or CJK glyphs
--      (Blizzard_Fonts_Shared/Mainline/Fonts.xml maps those alphabets to
--      FRIZQT___CYR.TTF, ARKai_T.ttf, 2002.TTF ...). The world boots as ruRU.
--   4.-5. Group Resource Bar: the detached width seed and the power height
--      fallback.
--   6. A custom group buff never saves a placeholder name or icon.
--   7. Status icon Reset selected queues the geometry pass.
--   8. The health bar highlight color keeps the Tint Alpha value.
--   9.-10. Corner Indicators status and the page badges, tooltips, labels and
--      history entries are translated, never concatenated English.
--
-- Plain Lua 5.1 with the repo root and a flavor (a client matrix Suffix or
-- Forever) as arguments.

local root = assert(arg and arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg and arg[2], "flavor required (a client matrix Suffix or Forever)")
assert(rawget(_G, "MSUF_Auras3TestLoader") == nil,
    "menu_pages_quality_smoke boots the real TOC graph; run it with plain Lua 5.1")

local World = assert(loadfile(root .. "/tools/tests/client_world.lua"),
    "menu_pages_quality_smoke: tools/tests/client_world.lua is missing")()

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end

---------------------------------------------------------------------------
-- Boot the client and give the page builders the widget surface they use.
---------------------------------------------------------------------------
-- ruRU, so labels are translated and the client font is the Cyrillic one.
local CLIENT_FONT = "Fonts\\FRIZQT___CYR.TTF"
local world = World.New(root, flavor, { locale = "ruRU" })
local env = world.env
env.STANDARD_TEXT_FONT = CLIENT_FONT
-- world:Boot(), with the core's ADDON_LOADED (which selects the language pack)
-- between the core and the load-on-demand Options addon, as in the client.
do
    local gameType = world.client.isForever and "camelot" or nil
    local suffix = world.client.tocSuffix or flavor
    world.corePaths = World.Graph(world.root, World.CoreTOC(suffix), env.GetLocale(), gameType)
    world.optionsPaths = World.Graph(world.root, World.OptionsTOC(suffix), env.GetLocale(), gameType)
    world:LoadGraph("MidnightSimpleUnitFrames", world.corePaths, world.core)
    Check(type(world.core.FinalizeLocale) == "function", "the core has no FinalizeLocale")
    world.core.FinalizeLocale()
    world:LoadGraph("MidnightSimpleUnitFrames_Options", world.optionsPaths, world.options)
end
local failure = world:FirstFailure()
Check(failure == nil, "load failed in " .. tostring(failure and failure.file) .. ": " .. tostring(failure and failure.message))

local Methods = world.widgets.Methods
local function Store(field) return function(self, value) self[field] = value end end
local function Fetch(field) return function(self) return self[field] end end
for name, method in pairs({
    SetChecked = Store("checked"), GetChecked = Fetch("checked"),
    SetCheckedTexture = Store("checkedTexture"), GetCheckedTexture = Fetch("checkedTexture"),
    SetDisabledCheckedTexture = Store("disabledCheckedTexture"), GetDisabledCheckedTexture = Fetch("disabledCheckedTexture"),
    GetDisabledTexture = Fetch("disabledTexture"), GetHighlightTexture = Fetch("highlightTexture"),
    GetNormalTexture = Fetch("normalTexture"), GetPushedTexture = Fetch("pushedTexture"),
    SetThumbTexture = Store("thumbTexture"), GetThumbTexture = Fetch("thumbTexture"),
    SetValueStep = Store("valueStep"), SetObeyStepOnDrag = Store("obeyStepOnDrag"), SetStepsPerPage = Store("stepsPerPage"),
    SetAutoFocus = Store("autoFocus"), SetNumeric = Store("numeric"), SetMaxLetters = Store("maxLetters"),
    SetPropagateMouseWheel = Store("propagateMouseWheel"),
    SetGradientAlpha = function(self, ...) self.gradientAlpha = { ... } end,
    HasFocus = function() return false end, ClearFocus = function() end, SetFocus = function() end,
    HighlightText = function() end, SetCursorPosition = function() end, GetCursorPosition = function() return 0 end,
    SetTextInsets = function() end, SetTimerDuration = function() end,
}) do
    if Methods[name] == nil then Methods[name] = method end
end
local StubGetValue = Methods.GetValue
Methods.GetValue = function(self)
    local value = StubGetValue(self)
    if value == nil then value = self.minimum or 0 end
    return value
end

local MSUF = world.core
local M = Check(world.options.MSUF2, "Menu2 did not load")
Check(type(M.BuildPageEntry) == "function", "Menu2 has no hidden page builder")
env.InCombatLockdown = function() return false end
env.MSUF_EnsureDB(true)
M.frame = M.frame or { IsShown = function() return true end }
M.cache = M.cache or {}
M.scrollChild = M.scrollChild or env.CreateFrame("Frame", nil, env.UIParent)

-- Every bound control registers with the runtime control catalog; keep its
-- widget by control id.
local widgetById = {}
local RegisterRuntimeControl = Check(M.RegisterRuntimeControl, "M.RegisterRuntimeControl is missing")
M.RegisterRuntimeControl = function(widget, payload, ...)
    if type(payload) == "table" and type(payload.controlId) == "string" then widgetById[payload.controlId] = widget end
    return RegisterRuntimeControl(widget, payload, ...)
end
local RegisterSearchWidget = Check(M.RegisterSearchWidget, "M.RegisterSearchWidget is missing")
M.RegisterSearchWidget = function(widget, meta, ...)
    if type(meta) == "table" and type(meta.controlId) == "string" then widgetById[meta.controlId] = widget end
    return RegisterSearchWidget(widget, meta, ...)
end
local Translate = Check(MSUF.Translate, "MSUF.Translate is missing")
-- Control cards by their (translated) title, the last one built.
local cardByTitle = {}
local ControlCard = Check(M.Widgets and M.Widgets.ControlCard, "W.ControlCard is missing")
M.Widgets.ControlCard = function(parent, title, ...)
    local card = ControlCard(parent, title, ...)
    if type(title) == "string" then cardByTitle[title] = card end
    return card
end
-- Color shortcut options by history source, the last one attached.
local shortcutBySource = {}
local AttachShortcut = Check(M.Widgets.AttachContextColorShortcut, "W.AttachContextColorShortcut is missing")
M.Widgets.AttachContextColorShortcut = function(owner, opts, ...)
    if type(opts) == "table" and type(opts.historySource) == "string" then shortcutBySource[opts.historySource] = opts end
    return AttachShortcut(owner, opts, ...)
end
-- Every W.Text label, by its (translated) initial text.
local textsByInitial = {}
local Text = Check(M.Widgets.Text, "W.Text is missing")
M.Widgets.Text = function(parent, text, ...)
    local label = Text(parent, text, ...)
    local key = tostring(text)
    textsByInitial[key] = textsByInitial[key] or {}
    table.insert(textsByInitial[key], label)
    return label
end
local function Card(title)
    return Check(cardByTitle[Translate(title)], "no control card titled " .. title)
end
local function LeftOf(region)
    local _, _, _, x = region:GetPoint(1)
    return Check(x, "a region has no anchor")
end
local function Widget(id)
    return Check(widgetById[id], "no control registered as " .. id)
end
local function RunRefreshers(entry)
    for _, refresh in ipairs(entry.refreshers or {}) do refresh() end
end
local function BuildPage(key)
    local entry = M.BuildPageEntry(key, true)
    world.widgets:RunTimers(20000)
    return Check(entry, "the " .. key .. " page did not build")
end

-- The vertical band a placed control covers in its section: from its title (or
-- its own top) down to the bottom of the control.
local function TopOf(region)
    local _, _, _, _, y = region:GetPoint(1)
    return Check(y, "a region has no anchor")
end
local function Band(control)
    local top = TopOf(control)
    if control._msuf2Title then top = math.max(top, TopOf(control._msuf2Title)) end
    return top, TopOf(control) - (control:GetHeight() or 0)
end
local function Shown(control) return control.IsShown and control:IsShown() ~= false end

---------------------------------------------------------------------------
-- 1. Spell Indicators in multi-spec mode: the Edit Spell column does not overlap.
---------------------------------------------------------------------------
local aurasEntry
do
    local GP = Check(M.GroupPage, "the group page model did not load")
    local entry = BuildPage("gf_auras")
    aurasEntry = entry
    Check(GP.CurrentScope() == "party", "the group pages do not start on the Party scope")
    GP.SpellIndicators("party").spec = "multi"
    -- A spec of its own (not the shared all-specs entry), so the track toggle shows.
    for _, item in ipairs(GP.SpellTrackedSpecValues()) do
        if item.value ~= "" and not GP.IsAllSpecsSpellSpec(item.value) then
            M.gfSpellMultiSpecSelection = { party = item.value }
            break
        end
    end
    RunRefreshers(entry)
    local prefix = "menu2.gf_auras.group.spell."
    local column = {
        { "Layer", prefix .. "selected.layer" },
        { "Multi-Spec Entry", prefix .. "multi_spec.selector" },
        { "Track selected multi spec", prefix .. "multi_spec.tracked" },
        { "Aura Spell IDs", prefix .. "selected.spell_ids" },
        { "Choose spell", prefix .. "selected_aura" },
        { "Show this spell", prefix .. "selected.enabled" },
        { "Only show my casts", prefix .. "selected.only_mine" },
        { "Hide duplicate Buff icon", prefix .. "selected.auto_blacklist" },
    }
    local placed = {}
    for _, item in ipairs(column) do
        local control = Widget(item[2])
        Check(Shown(control), item[1] .. " is hidden in multi-spec mode")
        local top, bottom = Band(control)
        placed[#placed + 1] = { label = item[1], top = top, bottom = bottom }
    end
    for i = 1, #placed do
        for j = i + 1, #placed do
            local a, b = placed[i], placed[j]
            Check(a.bottom >= b.top or b.bottom >= a.top, string.format(
                "Spell Indicators (multi-spec): %q (%d..%d) overlaps %q (%d..%d)",
                a.label, a.top, a.bottom, b.label, b.top, b.bottom))
        end
    end
    -- The Show on Frame card stays in the left column after the spell grid
    -- re-lays it out; it is built and moved with the same offset.
    Check(LeftOf(Card("Show on Frame")) == LeftOf(Card("Choose Spells")), string.format(
        "the Show on Frame card moved to x=%s after the spell grid refresh; Choose Spells is at x=%s",
        tostring(LeftOf(Card("Show on Frame"))), tostring(LeftOf(Card("Choose Spells")))))
    GP.SpellIndicators("party").spec = nil
end

---------------------------------------------------------------------------
-- 2. Growth direction tiles: translated labels.
-- 3. Tile labels use the client font.
---------------------------------------------------------------------------
local function CheckClientFont(region, where)
    local path = Check(region and region:GetFont(), where .. " has no font")
    Check(path == CLIENT_FONT, where .. " is drawn with " .. tostring(path) .. ", not the client font " .. CLIENT_FONT)
end
do
    BuildPage("gf_layout")
    for _, item in ipairs({ { "DOWN", "Down" }, { "UP", "Up" }, { "RIGHT", "Right" }, { "LEFT", "Left" } }) do
        local tile = Widget("menu2.gf_layout.group.field.growth.option." .. item[1]:lower())
        local wanted = Translate(item[2])
        Check(wanted ~= item[2], "harness: ruRU has no translation for " .. item[2])
        Check(tile._label and tile._label:GetText() == wanted, "the " .. item[2] .. " growth tile reads "
            .. tostring(tile._label and tile._label:GetText()) .. ", not " .. wanted)
        CheckClientFont(tile._label, "the " .. item[2] .. " growth tile label")
        CheckClientFont(tile._firstText, "the " .. item[2] .. " growth tile order mark")
        CheckClientFont(tile._arrow, "the " .. item[2] .. " growth tile arrow")
    end
    -- Spell tiles show spell names, which the client reports in its language.
    local spellTile = Widget("menu2.gf_auras.group.spell.tile.slot.1")
    CheckClientFont(spellTile.label, "the first spell indicator tile label")
    if MSUF.Client.SupportsUnit("boss1") then
        local entry = BuildPage("uf_boss")
        local layout
        for _, section in pairs(entry.sections or {}) do
            for _, child in ipairs(section.GetChildren and { section:GetChildren() } or {}) do
                if child._msuf2ControlKind == "segment" and child.values and child.buttons and child.buttons[1]
                    and child.buttons[1]._msuf2Value == "VERTICAL_DOWN" then
                    layout = child
                end
            end
        end
        Check(layout, "the Boss page built no boss layout tiles")
        for i, tile in ipairs(layout.buttons) do
            CheckClientFont(tile._label, "boss layout tile " .. i .. " label")
            CheckClientFont(tile._firstText, "boss layout tile " .. i .. " order mark")
            CheckClientFont(tile._arrow, "boss layout tile " .. i .. " arrow")
        end
    end
end

---------------------------------------------------------------------------
-- 4. Group Resource Bar: detaching a bar whose saved width is 0 seeds the
--    detached width from the frame width, as for a bar without one.
---------------------------------------------------------------------------
local GP = Check(M.GroupPage, "the group page model did not load")
local function Click(widget)
    local onClick = Check(widget:GetScript("OnClick"), "a control has no OnClick")
    onClick(widget, "LeftButton")
    world.widgets:RunTimers(20000)
end
do
    BuildPage("gf_layout")
    local detach = Widget("menu2.gf_layout.group.field.powerbardetached")
    for _, saved in ipairs({ 0, false }) do
        local conf = GP.Conf("party")
        conf.powerBarDetached, conf.width = false, 77
        conf.detachedPowerBarWidth = saved or nil
        Click(detach)
        Check(conf.powerBarDetached == true, "Detach from frame did not detach the party power bar")
        Check(conf.detachedPowerBarWidth == 77, "detaching with a saved width of " .. tostring(saved or nil)
            .. " left the detached width at " .. tostring(conf.detachedPowerBarWidth) .. ", not the frame width 77")
        Click(detach)
    end
end

---------------------------------------------------------------------------
-- 5. Group Resource Bar: the power height fallback (a value that is not a
--    number) is the scope's default height, not a third, drifted one.
---------------------------------------------------------------------------
do
    local height = Widget("menu2.gf_layout.group.field.powerheight")
    local command = Check(height._msuf2CommandAction, "Power height has no command action")
    local conf = GP.Conf("party")
    conf.powerHeight = 12
    command.set("not a number")
    local wanted = MSUF.GF.GetDefault("party", "powerHeight")
    Check(conf.powerHeight == wanted, "a non-numeric Power height wrote " .. tostring(conf.powerHeight)
        .. ", not the Party default " .. tostring(wanted))
end

---------------------------------------------------------------------------
-- 6. Spell Indicators: a custom buff added before the client has its spell
--    data saves no placeholder name or icon. The runtime names the tile from
--    the spell once the data arrives (SpellRegistry EnsureTrackable), but a
--    saved display wins over it in the compiled item.
---------------------------------------------------------------------------
do
    local spellID = 987654
    local original = env.C_Spell
    env.C_Spell = setmetatable({
        GetSpellInfo = function() return nil end,
        GetSpellName = function() return nil end,
        GetSpellTexture = function() return nil end,
        RequestLoadSpellData = function() end,
    }, { __index = original })
    local legacyGetSpellInfo = env.GetSpellInfo
    env.GetSpellInfo = nil
    -- The page reselects itself after the add; a hidden build has no window.
    local SelectPage = M.SelectPage
    M.SelectPage = function() end
    GP.SpellIndicators("party").enabled = true
    RunRefreshers(aurasEntry)
    local addTile
    for id, widget in pairs(widgetById) do
        if id:find("^menu2%.gf_auras%.group%.spell%.tile%.slot%.") and widget._isAddTile and widget:IsShown() then
            addTile = widget
        end
    end
    Check(addTile and addTile._specKey, "the spell grid has no add tile")
    Check(addTile._msuf2CommandAction.set(tostring(spellID)), "adding custom buff " .. spellID .. " failed")
    local specCfg = GP.SpellIndicators("party").specs[addTile._specKey]
    local saved = Check(specCfg and specCfg[tostring(spellID)], "the custom buff was not saved")
    Check(saved.display == nil, "the custom buff saved the placeholder name " .. tostring(saved.display))
    Check(saved.icon == nil, "the custom buff saved the placeholder icon " .. tostring(saved.icon))
    env.C_Spell, env.GetSpellInfo, M.SelectPage = original, legacyGetSpellInfo, SelectPage
end

---------------------------------------------------------------------------
-- 7. Status & Indicators > Reset selected restores the anchor and offsets
--    too, so it queues the geometry pass the Anchor dropdown itself queues.
---------------------------------------------------------------------------
local indicatorsEntry
do
    indicatorsEntry = BuildPage("gf_indicators")
    local apply = Check(M.ApplyService and M.ApplyService.RequestGroup and M.ApplyService,
        "the menu apply service has no RequestGroup")
    local RequestGroup = apply.RequestGroup
    local modes = {}
    apply.RequestGroup = function(kind, mode, ...)
        modes[#modes + 1] = tostring(kind) .. ":" .. tostring(mode)
        return RequestGroup(kind, mode, ...)
    end
    Click(Widget("menu2.gf_indicators.group.status.selected.reset"))
    apply.RequestGroup = RequestGroup
    local queued = table.concat(modes, ",")
    Check(queued:find("party:geometry", 1, true) ~= nil, "Reset selected queued " .. queued
        .. " for the Party scope; the reset anchor and offsets need party:geometry")
end

---------------------------------------------------------------------------
-- 8. Spell Indicators > Highlight Health Bar: the color picker keeps the
--    alpha the Tint Alpha slider shows (frame.alpha before color[4], the
--    order the slider and the runtime's tint read).
---------------------------------------------------------------------------
do
    local cfg = Check(GP.CurrentSpellConfig("party", true), "no selected spell to configure")
    cfg.frame = { type = "border", alpha = 0.3, color = { 1, 0, 0, 0.8 } }
    local slider = Widget("menu2.gf_auras.group.spell.frame.alpha")
    Check(slider._msuf2CommandAction.get() == 30, "Tint Alpha shows " .. tostring(slider._msuf2CommandAction.get())
        .. " for frame.alpha 0.3")
    local opts = Check(shortcutBySource["menu:group-spell-frame-color"], "the health bar highlight color has no shortcut")
    local target = Check(opts.getTargets()[1], "the health bar highlight shortcut has no target")
    target.setRGB(0, 1, 0)
    local color = cfg.frame.color
    Check(color[1] == 0 and color[2] == 1 and color[3] == 0, "the highlight color was not written")
    Check(color[4] == 0.3, "picking a highlight color set its alpha to " .. tostring(color[4])
        .. " while Tint Alpha shows 30")
end

---------------------------------------------------------------------------
-- 9. Corner Indicators: the custom spell editor status names the slot and
--    its indicator in the client language, never the saved key ("none").
---------------------------------------------------------------------------
do
    M.SetMenuStateValue("gfCornerSlotSelection", "TL")
    GP.Conf("party").ciSlotTL = "none"
    RunRefreshers(indicatorsEntry)
    -- The status line sits under the Selected Slot Indicator dropdown (y -230).
    local status
    for _, label in ipairs(textsByInitial[""] or {}) do
        local _, _, _, _, y = label:GetPoint(1)
        if y == -230 and type(label:GetText()) == "string" and label:GetText() ~= "" then status = label end
    end
    local text = Check(status, "the Corner Indicators editor shows no custom spell status"):GetText()
    Check(text:find(Translate("None"), 1, true) and not text:find("%a"),
        "the Corner Indicators editor status is not fully translated: " .. text)
end

---------------------------------------------------------------------------
-- 10. No page string is concatenated before translation: the badge, tooltip,
--     label and history texts these pages build are format strings that the
--     language packs translate (menu_page_labels_locale_smoke REQUIRED).
---------------------------------------------------------------------------
do
    local PAGES_DIR = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/"
    local BANNED = {
        ["MSUF_Menu2_GroupBars.lua"] = { '%.%. "px"', '"Name " %.%.', '"HP " %.%.', '"Power " %.%.', '"Offline " %.%.' },
        ["MSUF_Menu2_Auras.lua"] = { '"Border " %.%.' },
        ["MSUF_Menu2_GroupIndicators.lua"] = { '"IDs: " %.%.', '%.%. " Indicator"', 'CurrentScope%(%) %.%. ": "',
            'tostring%(category or "none"%)' },
        ["MSUF_Menu2_Group.lua"] = { 'RunWithHistory%("Group " %.%.', '"Growth: " %.%.' },
        ["MSUF_Menu2_UnitTextureLayer.lua"] = { '"Texture: " %.%.' },
    }
    for file, patterns in pairs(BANNED) do
        local handle = assert(io.open(PAGES_DIR .. file, "rb"))
        local source = handle:read("*a")
        handle:close()
        for _, pattern in ipairs(patterns) do
            Check(not source:find(pattern), file .. " concatenates a string before translating it: " .. pattern)
        end
    end
end

print(string.format("menu_pages_quality_smoke: ok (%s)", flavor))
