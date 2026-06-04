_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local assistantRoot = "MidnightSimpleUnitFrames/Shell/Menu2/Assistant/"
if not exists(assistantRoot .. "MSUF_AssistantParser.lua") then
    assistantRoot = "Shell/Menu2/Assistant/"
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = { general = {}, bars = {}, gameplay = {} }

local files = {
    "MSUF_AssistantRegistry.lua",
    "MSUF_AssistantRegistry_Core.lua",
    "MSUF_AssistantRegistry_Unitframes.lua",
    "MSUF_AssistantRegistry_Castbars.lua",
    "MSUF_AssistantRegistry_Auras.lua",
    "MSUF_AssistantRegistry_GroupFrames.lua",
    "MSUF_AssistantRegistry_Boss.lua",
    "MSUF_AssistantRegistry_ClassPower.lua",
    "MSUF_AssistantRegistry_Gameplay.lua",
    "MSUF_AssistantRegistry_Global.lua",
    "MSUF_AssistantRegistry_Dashboard.lua",
    "MSUF_AssistantRegistry_Profiles.lua",
    "MSUF_AssistantRegistry_EditMode.lua",
    "MSUF_AssistantRegistry_Workflows.lua",
    "MSUF_AssistantRegistry_Diagnostics.lua",
    "MSUF_AssistantParser.lua",
}

for _, name in ipairs(files) do
    local path = assistantRoot .. name
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MidnightSimpleUnitFrames", MSUF)
end

local A = assert(MSUF.Assistant, "Assistant namespace missing")
assert(type(A.Parse) == "function", "Assistant parser missing")
local parserContext = {}
A.GetContext = A.GetContext or function() return parserContext end

local function firstChange(parsed)
    assert(parsed.kind == "changes", "expected changes, got " .. tostring(parsed.kind))
    local change = parsed.changes and parsed.changes[1]
    assert(change, "missing first change")
    assert(change.setting, "missing first setting")
    return change
end

local function expectAction(text, actionKey, page)
    local parsed = A.Parse(text)
    assert(parsed.kind == "action", text .. ": expected action, got " .. tostring(parsed.kind))
    assert(parsed.action and parsed.action.key == actionKey, text .. ": wrong action key")
    if page then
        assert(parsed.args and parsed.args.page == page, text .. ": wrong page " .. tostring(parsed.args and parsed.args.page))
    end
end

local function expectActionArg(text, actionKey, argKey, argValue)
    local parsed = A.Parse(text)
    assert(parsed.kind == "action", text .. ": expected action, got " .. tostring(parsed.kind))
    assert(parsed.action and parsed.action.key == actionKey, text .. ": wrong action key")
    assert(parsed.args and parsed.args[argKey] == argValue, text .. ": wrong arg " .. tostring(argKey) .. "=" .. tostring(parsed.args and parsed.args[argKey]))
end

local function expectActionArgList(text, actionKey, argKey, expected)
    local parsed = A.Parse(text)
    assert(parsed.kind == "action", text .. ": expected action, got " .. tostring(parsed.kind))
    assert(parsed.action and parsed.action.key == actionKey, text .. ": wrong action key")
    local actual = parsed.args and parsed.args[argKey]
    assert(type(actual) == "table", text .. ": missing list arg " .. tostring(argKey))
    for i = 1, #(expected or {}) do
        assert(actual[i] == expected[i], text .. ": wrong list arg " .. tostring(argKey) .. "[" .. tostring(i) .. "]=" .. tostring(actual[i]))
    end
end

local function expectCopy(text, actionKey, source, targets, scopes)
    local parsed = A.Parse(text)
    assert(parsed.kind == "action", text .. ": expected action, got " .. tostring(parsed.kind))
    assert(parsed.action and parsed.action.key == actionKey, text .. ": wrong action key")
    assert(parsed.args and parsed.args.source == source, text .. ": wrong source " .. tostring(parsed.args and parsed.args.source))
    assert(type(parsed.args.targets) == "table", text .. ": missing targets")
    for i = 1, #(targets or {}) do
        assert(parsed.args.targets[i] == targets[i], text .. ": wrong target " .. tostring(i) .. "=" .. tostring(parsed.args.targets[i]))
    end
    for key, value in pairs(scopes or {}) do
        assert(parsed.args.scopes and parsed.args.scopes[key] == value, text .. ": wrong scope " .. tostring(key) .. "=" .. tostring(parsed.args.scopes and parsed.args.scopes[key]))
    end
end

local function expectSetting(text, key, value, attr, delta)
    local parsed = A.Parse(text)
    local change = firstChange(parsed)
    assert(change.setting.key == key, text .. ": wrong setting " .. tostring(change.setting.key))
    if value ~= nil then
        assert(change.value == value, text .. ": wrong value " .. tostring(change.value))
    end
    if attr then
        assert(change.setting.attribute == attr, text .. ": wrong attr " .. tostring(change.setting.attribute))
    end
    if delta ~= nil then
        assert(change.relativeDelta == delta, text .. ": wrong delta " .. tostring(change.relativeDelta))
    end
end

local function expectSettingAt(text, index, key, value, attr, delta)
    local parsed = A.Parse(text)
    assert(parsed.kind == "changes", text .. ": expected changes, got " .. tostring(parsed.kind))
    local change = parsed.changes and parsed.changes[index]
    assert(change, text .. ": missing change " .. tostring(index))
    assert(change.setting and change.setting.key == key, text .. ": wrong setting " .. tostring(change.setting and change.setting.key))
    if value ~= nil then
        assert(change.value == value, text .. ": wrong value " .. tostring(change.value))
    end
    if attr then
        assert(change.setting.attribute == attr, text .. ": wrong attr " .. tostring(change.setting.attribute))
    end
    if delta ~= nil then
        assert(change.relativeDelta == delta, text .. ": wrong delta " .. tostring(change.relativeDelta))
    end
end

local function assertNear(actual, expected, label)
    assert(type(actual) == "number", tostring(label) .. ": expected number, got " .. tostring(actual))
    assert(math.abs(actual - expected) < 0.0005, tostring(label) .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function expectColorSetting(text, key, r, g, b, attr)
    local parsed = A.Parse(text)
    local change = firstChange(parsed)
    assert(change.setting.key == key, text .. ": wrong setting " .. tostring(change.setting.key))
    if attr then
        assert(change.setting.attribute == attr, text .. ": wrong attr " .. tostring(change.setting.attribute))
    end
    assert(type(change.value) == "table", text .. ": expected color table")
    assertNear(change.value.r or change.value[1], r, text .. " red")
    assertNear(change.value.g or change.value[2], g, text .. " green")
    assertNear(change.value.b or change.value[3], b, text .. " blue")
end

local function expectUnknown(text)
    local parsed = A.Parse(text)
    assert(parsed.kind == "unknown", text .. ": expected unknown, got " .. tostring(parsed.kind))
end

local function expectAnswer(text, contains)
    local parsed = A.Parse(text)
    assert(parsed.kind == "answer", text .. ": expected answer, got " .. tostring(parsed.kind))
    if contains then
        assert(tostring(parsed.text or ""):find(contains, 1, true), text .. ": missing answer text " .. tostring(contains))
    end
end

local function setFollowupContext(frameType, attribute, value)
    local ctx = A.GetContext()
    ctx.lastChangeBundle = {
        { frameType = frameType, attribute = attribute, value = value },
    }
end

local function setRepeatContext(key, delta, direction)
    local ctx = A.GetContext()
    ctx.lastChangeBundle = {
        { key = key, relativeDelta = delta, direction = direction },
    }
    ctx.lastSetting = key
end

local function setNumericContext(key, value)
    local ctx = A.GetContext()
    ctx.lastChangeBundle = {
        { key = key, value = value },
    }
    ctx.lastSetting = key
    ctx.lastValue = value
end

local function setTextContext(frameType, unit, tab, slot, settingKey, value)
    local ctx = A.GetContext()
    ctx.lastTextFrameType = frameType
    ctx.lastTextUnit = unit
    ctx.lastTextArea = tab
    ctx.lastTextSlot = slot
    ctx.lastTextSetting = settingKey
    ctx.lastTextValue = value
    ctx.selectedTextEditorTarget = {
        frameType = frameType,
        unit = unit,
        tab = tab,
        slot = slot,
    }
end

expectAction("open target of target", "open_page", "uf_targettarget")
expectAction("open pet", "open_page", "uf_pet")
expectAction("target of target settings", "open_page", "uf_targettarget")
expectAction("pet settings", "open_page", "uf_pet")
expectAction("pet", "open_page", "uf_pet")
expectAction("close msuf menu", "menu_window_close")
expectAction("minimize msuf menu", "menu_window_minimize")
expectAction("maximize msuf menu", "menu_window_maximize")
expectAction("restore msuf menu", "menu_window_restore")
expectAction("open recovery tools", "set_dashboard_panel")
expectAction("close scaling tools", "set_dashboard_panel")
expectAction("toggle changelog", "set_dashboard_panel")
expectActionArg("collapse frames navigation section", "set_nav_section", "section", "unitframes")
expectActionArg("collapse frames navigation section", "set_nav_section", "open", false)
expectActionArg("open group frames navigation section", "set_nav_section", "section", "groupframes")
expectActionArg("open group frames navigation section", "set_nav_section", "open", true)
expectActionArg("show search intro", "set_nav_search_intro", "command", "show")
expectActionArg("reset search intro", "set_nav_search_intro", "command", "reset")
expectAction("help", "assistant_help")
expectActionArg("help for player frame", "assistant_scope_help", "unit", "player")
expectActionArg("help for player frame", "assistant_scope_help", "frameType", "unitframe")
expectAction("back", "dashboard_page_back")
expectAction("open previous page", "dashboard_page_back")
expectActionArg("copy profile Test", "copy_profile", "name", "Test")
expectActionArg("copy from profile Test", "start_profile_copy_flow", "source", "Test")
expectActionArg("rename profile Test to New", "rename_profile", "source", "Test")
expectActionArg("rename profile Test to New", "rename_profile", "name", "New")
expectCopy("copy player text and castbar to target", "copy_unit", "player", { "target" }, { text = true, castbar = true, basics = false, layout = false })
expectCopy("copy player size to target", "copy_unit", "player", { "target" }, { layout = true, basics = true, text = false })
expectCopy("copy player all settings to target", "copy_unit", "player", { "target" }, { basics = true, text = true, portrait = true, power = true, castbar = true, status = true, load = true, transparency = true, layout = true })
expectCopy("copy party health and text to raid", "copy_group", "party", { "raid" }, { health = true, text = true, general = false, font = false })
expectCopy("copy party all settings to all groups", "copy_group", "party", { "raid", "mythicraid" }, { general = true, health = true, text = true, font = true, border = true, range = true, indicators = true, auras = true, highlight = true, dstripe = true, features = true })
expectActionArg("apply 1440p global ui scale preset", "apply_global_scale_preset", "preset", "1440p")
expectAction("start guided setup", "guided_setup")
expectActionArg("next setup step", "guided_setup_step", "command", "next")
expectActionArg("cancel setup", "guided_setup_step", "command", "cancel")
expectActionArg("copy discord link", "copy_support_link", "link", "discord")
expectAction("support links", "support_links_summary")
expectActionArg("confirm wago backup", "confirm_wago_backup", "confirmed", true)
expectActionArg("clear wago backup", "confirm_wago_backup", "confirmed", false)
expectAction("recovery tools", "open_recovery_tools")
expectAction("enter edit mode", "assistant.action.editMode.enter")
expectAction("exit edit mode", "assistant.action.editMode.exit")
expectAction("edit mode status", "assistant.diagnostic.editMode.status")
expectAction("cancel edit mode", "assistant.action.editMode.cancel")
expectAction("undo menu change", "menu_history_undo")
expectAction("redo menu change", "menu_history_redo")
expectAction("reset all menu changes from this session", "menu_history_reset_session")
expectAction("quick setup class resources", "class_power_quick_setup")
expectActionArg("diagnose target castbar", "diagnose_castbar_visibility", "unit", "target")
expectActionArg("diagnose party frames", "diagnose_group_visibility", "scope", "party")
expectActionArg("diagnose player frame", "diagnose_unit_visibility", "unit", "player")
expectAction("diagnose profiles", "diagnose_profile_status")
expectAction("diagnose class resources", "diagnose_class_power_status")
expectAction("diagnose dashboard setup", "diagnose_dashboard_setup")
expectAction("factory reset all", "factory_reset_all")
expectActionArg("reset player position", "reset_unit_position", "unit", "player")
expectAction("reset all frame positions", "reset_all_unit_positions")
expectActionArg("reset player settings", "reset_unit_page", "unit", "player")
expectAction("reset totem frame layout", "reset_player_totems_layout")
expectAction("reset all bars overrides", "reset_all_scoped_global_bars_overrides")
expectAction("reset all font overrides", "reset_all_scoped_global_font_overrides")
expectActionArg("reset player bars override", "reset_scoped_global_bars_override", "scope", "player")
expectActionArg("reset target font override", "reset_scoped_global_font_override", "scope", "target")
expectActionArg("reset party spell indicator Rejuvenation", "reset_group_spell_indicator_aura", "scope", "party")
expectActionArg("reset party status icons", "reset_group_status_icons", "scope", "party")
expectActionArg("select player hp left slot", "set_menu_selector_state", "selector", "unit_text")
expectActionArg("select player hp left slot", "set_menu_selector_state", "unit", "player")
expectActionArg("select player hp left slot", "set_menu_selector_state", "slot", "left")
expectActionArg("select party power text right slot", "set_menu_selector_state", "selector", "group_text")
expectActionArg("select party power text right slot", "set_menu_selector_state", "scope", "party")
expectActionArg("set player hp text anchor to right", "set_menu_selector_state", "selector", "unit_text")
expectActionArg("set player hp text anchor to right", "set_menu_selector_state", "unit", "player")
expectActionArg("set player hp text anchor to right", "set_menu_selector_state", "tab", "hp")
expectActionArg("set player hp text anchor to right", "set_menu_selector_state", "slot", "right")
expectActionArg("align player hp text right", "set_menu_selector_state", "selector", "unit_text")
expectActionArg("align player hp text right", "set_menu_selector_state", "unit", "player")
expectActionArg("align player hp text right", "set_menu_selector_state", "tab", "hp")
expectActionArg("align player hp text right", "set_menu_selector_state", "slot", "right")
expectActionArg("set party power text anchor to left", "set_menu_selector_state", "selector", "group_text")
expectActionArg("set party power text anchor to left", "set_menu_selector_state", "scope", "party")
expectActionArg("set party power text anchor to left", "set_menu_selector_state", "tab", "power")
expectActionArg("set party power text anchor to left", "set_menu_selector_state", "slot", "left")
expectActionArg("put party power text on left", "set_menu_selector_state", "selector", "group_text")
expectActionArg("put party power text on left", "set_menu_selector_state", "scope", "party")
expectActionArg("put party power text on left", "set_menu_selector_state", "tab", "power")
expectActionArg("put party power text on left", "set_menu_selector_state", "slot", "left")
expectActionArg("turn off party hp move text as one group", "set_menu_selector_state", "selector", "group_text_move_together")
expectActionArg("turn off party hp move text as one group", "set_menu_selector_state", "scope", "party")
expectActionArg("turn off party hp move text as one group", "set_menu_selector_state", "value", false)
expectActionArg("use individual party hp text units", "set_menu_selector_state", "selector", "group_text_move_together")
expectActionArg("use individual party hp text units", "set_menu_selector_state", "scope", "party")
expectActionArg("use individual party hp text units", "set_menu_selector_state", "value", false)
expectActionArg("set player power text per slot", "set_menu_selector_state", "selector", "unit_text_move_together")
expectActionArg("set player power text per slot", "set_menu_selector_state", "unit", "player")
expectActionArg("set player power text per slot", "set_menu_selector_state", "value", false)
expectActionArg("use individual player power text units", "set_menu_selector_state", "selector", "unit_text_move_together")
expectActionArg("use individual player power text units", "set_menu_selector_state", "unit", "player")
expectActionArg("use individual player power text units", "set_menu_selector_state", "value", false)
expectActionArg("select target advanced status tab", "set_menu_selector_state", "selector", "unit_status")
expectActionArg("select target advanced status tab", "set_menu_selector_state", "tab", "advanced")
expectActionArg("select party leader icon indicator", "set_menu_selector_state", "selector", "group_status")
expectActionArg("select party leader icon indicator", "set_menu_selector_state", "icon", "leaderIcon")
expectActionArg("select bottom right corner editor slot", "set_menu_selector_state", "selector", "group_corner")
expectActionArg("select bottom right corner editor slot", "set_menu_selector_state", "slot", "BR")
expectActionArg("select mana power color token", "set_menu_selector_state", "selector", "color_token")
expectActionArg("select mana power color token", "set_menu_selector_state", "token", "MANA")
expectActionArg("set profile name field to Raid Draft", "set_menu_selector_state", "selector", "profile_staging")
expectActionArg("set profile name field to Raid Draft", "set_menu_selector_state", "field", "profileCreateCopyName")
expectActionArg("select profile export kind group frames", "set_menu_selector_state", "field", "profileExportKind")
expectActionArg("select profile export kind group frames", "set_menu_selector_state", "kind", "groupframe")
expectActionArg("turn on profile import and create new profile", "set_menu_selector_state", "field", "profileImportCreateNew")
expectActionArg("turn on profile import and create new profile", "set_menu_selector_state", "value", true)
expectActionArg("set profile import new profile name to Imported Raid", "set_menu_selector_state", "field", "profileImportNewName")
expectActionArg("set profile string field to MSUF5:staged", "set_menu_selector_state", "field", "profileString")
expectActionArg("clear player copy categories", "set_menu_selector_state", "selector", "unit_copy_scope")
expectActionArg("clear player copy categories", "set_menu_selector_state", "unit", "player")
expectActionArg("clear player copy categories", "set_menu_selector_state", "command", "none")
expectActionArg("turn off unit copy portrait category", "set_menu_selector_state", "category", "portrait")
expectActionArg("turn off unit copy portrait category", "set_menu_selector_state", "value", false)
expectActionArg("select only unit copy text and castbar categories", "set_menu_selector_state", "selector", "unit_copy_scope")
expectActionArg("select only unit copy text and castbar categories", "set_menu_selector_state", "command", "only")
expectActionArgList("select only unit copy text and castbar categories", "set_menu_selector_state", "categories", { "text", "castbar" })
expectActionArg("clear group copy categories", "set_menu_selector_state", "selector", "group_copy_scope")
expectActionArg("clear group copy categories", "set_menu_selector_state", "command", "none")
expectActionArg("turn off group copy auras category", "set_menu_selector_state", "category", "auras")
expectActionArg("turn off group copy auras category", "set_menu_selector_state", "value", false)

expectSetting("turn off target castbar", "general.enableTargetCastbar", false, "enabled")
expectSetting("turn off target castbar name", "general.castbarTargetShowSpellName", false, "text")
expectSetting("turn off focus castbar text", "general.castbarFocusShowSpellName", false, "text")
expectSetting("turn off player castbar icon", "general.castbarPlayerShowIcon", false, "icon")
expectSetting("turn off target castbar time", "general.showTargetCastTime", false, "time")
expectSetting("turn off boss castbar spell name", "general.showBossCastName", false, "text")
expectSetting("turn off player castbar interrupt", "player.showInterrupt", false, "showInterrupt")
expectSetting("turn off target castbar channel ticks", "general.castbarShowChannelTicks", false, "channelTicks")
expectSetting("turn off target castbar glow", "general.castbarShowGlow", false, "glow")
expectSetting("turn off target castbar spark", "general.castbarShowSpark", false, "spark")
expectSetting("turn off target castbar latency", "general.castbarShowLatency", false, "latency")
expectSetting("turn off target castbar unified direction", "general.castbarUnifiedDirection", false, "unifiedDirection")
expectSetting("move pet frame 12px right", "pet.offsetX", nil, "offsetX", 12)
expectSetting("set player border color to red", "barScope.player.barOutlineColor", nil, "barOutlineColor")
expectColorSetting("set player border color to rgb 255 128 0", "barScope.player.barOutlineColor", 1, 128 / 255, 0, "barOutlineColor")
expectColorSetting("set player border color to r 0.2 g 0.4 b 0.6", "barScope.player.barOutlineColor", 0.2, 0.4, 0.6, "barOutlineColor")
expectColorSetting("set castbar text color to #336699", "general.castbarFontColor", 0x33 / 255, 0x66 / 255, 0x99 / 255, "castbarFontColor")
expectSetting("move player portrait 5 right", "player.portraitOffsetX", nil, "portraitOffsetX", 5)
expectSetting("set player name anchor to right", "player.nameTextAnchor", "RIGHT", "nameTextAnchor")
expectSetting("move player name text 5 right", "player.nameOffsetX", nil, "nameOffsetX", 5)
expectSetting("move player unit name label up 2", "player.nameOffsetY", nil, "nameOffsetY", 2)
expectSetting("move player health down 4", "player.hpOffsetY", nil, "hpOffsetY", -4)
expectSetting("move target mana up 2", "target.powerOffsetY", nil, "powerOffsetY", 2)
expectSetting("move party frame name down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
expectSetting("move party frame name text down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
expectSetting("move the party frames name down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
expectSetting("move party names up 2", "gf_party.nameOffsetY", nil, "nameOffsetY", 2)
do
    local savedAliases = A.UnitAliases
    A.UnitAliases = {}
    expectSetting("move party frame name down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
    expectSetting("move player name text down", "player.nameOffsetY", nil, "nameOffsetY", -10)
    A.UnitAliases = savedAliases
end
expectSetting("move raid health down 4", "gf_raid.hpOffsetY", nil, "healthTextOffsetY", -4)
expectSetting("move party mana right 2", "gf_party.powerOffsetX", nil, "powerTextOffsetX", 2)
expectSetting("move raid frame hp text right 5", "gf_raid.hpOffsetX", nil, "healthTextOffsetX", 5)
expectSetting("move party power text up 3", "gf_party.powerOffsetY", nil, "powerTextOffsetY", 3)
expectSetting("move party hp left text down 3", "gf_party.hpTextLeftOffsetY", nil, "hpTextLeftOffsetY", -3)
expectSetting("move raid right power label up 2", "gf_raid.powerTextRightOffsetY", nil, "powerTextRightOffsetY", 2)
expectSetting("set player hp y offset to -8", "player.hpOffsetY", -8, "hpOffsetY")
expectSetting("set target mana x offset to 7", "target.powerOffsetX", 7, "powerOffsetX")
expectSetting("set party name y offset to -6", "gf_party.nameOffsetY", -6, "nameOffsetY")
expectSetting("set raid hp x offset to 12", "gf_raid.hpOffsetX", 12, "healthTextOffsetX")
expectSetting("set party mana y offset to -3", "gf_party.powerOffsetY", -3, "powerTextOffsetY")
expectSetting("move player left hp text down 3", "player.hpTextLeftOffsetY", nil, "hpTextLeftOffsetY", -3)
expectSetting("set target right mana text x offset to 9", "target.powerTextRightOffsetX", 9, "powerTextRightOffsetX")
expectSetting("move party power right text up 2", "gf_party.powerTextRightOffsetY", nil, "powerTextRightOffsetY", 2)
expectSetting("set raid hp center slot x offset to 5", "gf_raid.hpTextCenterOffsetX", 5, "hpTextCenterOffsetX")
expectSetting("set player left hp text to current health", "player.textLeft", "CURRENT", "hpTextLeft")
expectSetting("set player right hp text to current percent", "player.textRight", "CURPERCENT", "hpTextRight")
expectSetting("set target right mana text to current max", "target.powerTextRight", "CURMAX", "powerTextRight")
expectSetting("create new hp text at player frame anchor left side with hp max", "player.textLeft", "MAX", "hpTextLeft")
expectSetting("add max hp text left side player frame", "player.textLeft", "MAX", "hpTextLeft")
expectSetting("put max hp on left side player frame", "player.textLeft", "MAX", "hpTextLeft")
expectSetting("set player hp text left to max hp", "player.textLeft", "MAX", "hpTextLeft")
expectSetting("create new mana text at target frame anchor right side with mana current max", "target.powerTextRight", "CURMAX", "powerTextRight")
expectSetting("create new hp text at raid frame anchor center side with hp percent", "gf_raid.textCenter", "PERCENT", "healthTextCenter")
expectSetting("hide player left hp text", "player.textLeft", "NONE", "hpTextLeft")
expectSetting("clear player hp text left", "player.textLeft", "NONE", "hpTextLeft")
expectSetting("set raid center hp text to percent", "gf_raid.textCenter", "PERCENT", "healthTextCenter")
expectSetting("set party right hp text to deficit", "gf_party.textRight", "DEFICIT", "healthTextRight")
expectSetting("set party power center text to current percent", "gf_party.powerTextCenter", "CURPERCENT", "powerTextCenter")
expectSetting("set target hp text right to current/max", "target.textRight", "CURMAX", "hpTextRight")
expectSettingAt("remove player power text", 1, "player.powerTextLeft", "NONE", "powerTextLeft")
expectSettingAt("remove player power text", 2, "player.powerTextCenter", "NONE", "powerTextCenter")
expectSettingAt("remove player power text", 3, "player.powerTextRight", "NONE", "powerTextRight")
expectSetting("set player power text right to percent", "player.powerTextRight", "PERCENT", "powerTextRight")
setTextContext("unitframe", "player", "hp", "left", "player.textLeft", "MAX")
expectSetting("change hp text player to only %", "player.textLeft", "PERCENT", "hpTextLeft")
expectSetting("show only percent on player hp text", "player.textLeft", "PERCENT", "hpTextLeft")
expectSetting("change it to only %", "player.textLeft", "PERCENT", "hpTextLeft")
expectSetting("now make it max hp", "player.textLeft", "MAX", "hpTextLeft")
setFollowupContext("unitframe", "hpTextLeft", "MAX")
expectSetting("do same for target", "target.textLeft", "MAX", "hpTextLeft")
expectSetting("set player hp text size to 18", "player.hpFontSize", 18, "hpFontSize")
expectSetting("increase target power text size by 2", "target.powerFontSize", nil, "powerFontSize", 2)
expectSetting("set party power text size to 11", "gf_party.powerFontSize", 11, "powerFontSize")
expectSetting("set raid name text size to 12", "gf_raid.nameFontSize", 12, "nameFontSize")
expectSetting("set player hp text layer to 8", "player.hpTextLayer", 8, "hpTextLayer")
expectSetting("bring player hp text layer forward", "player.hpTextLayer", nil, "hpTextLayer", 1)
expectSetting("increase target power text layer by 1", "target.powerTextLayer", nil, "powerTextLayer", 1)
expectSetting("set party power text layer to 4", "gf_party.powerTextLayer", 4, "powerTextLayer")
expectSetting("set raid name text layer to 6", "gf_raid.nameTextLayer", 6, "nameTextLayer")
expectSetting("send raid name text layer behind", "gf_raid.nameTextLayer", nil, "nameTextLayer", -1)
expectSetting("set raid hp text layer to 7", "gf_raid.textLayer", 7, "healthTextLayer")
MSUF.MSUF2.activeKey = "uf_player"
expectSetting("set left hp text to current", "player.textLeft", "CURRENT", "hpTextLeft")
expectSetting("set hp text size to 17", "player.hpFontSize", 17, "hpFontSize")
expectSetting("set hp text layer to 8", "player.hpTextLayer", 8, "hpTextLayer")
expectSetting("move left hp text down 2", "player.hpTextLeftOffsetY", nil, "hpTextLeftOffsetY", -2)
MSUF.MSUF2.activeKey = "gf_bars"
MSUF.MSUF2.gfScope = "raid"
expectSetting("set center hp text to percent", "gf_raid.textCenter", "PERCENT", "healthTextCenter")
expectSetting("set hp text size to 13", "gf_raid.hpFontSize", 13, "hpFontSize")
expectSetting("set hp text layer to 7", "gf_raid.textLayer", 7, "healthTextLayer")
expectSetting("set center hp text y offset to -4", "gf_raid.hpTextCenterOffsetY", -4, "hpTextCenterOffsetY")
MSUF.MSUF2.activeKey = "home"
expectSetting("set bars texture to Smooth", "general.barTexture", "Smooth", "texture")
expectSettingAt("set player alpha to 50", 1, "player.alphaInCombat", 0.5, "alphaInCombat")
expectSettingAt("set player alpha to 50", 2, "player.alphaOutOfCombat", 0.5, "alphaOutOfCombat")
expectSettingAt("set raid alpha to 50", 1, "gf_raid.alphaCurrentInCombat", 0.5, "alphaInCombat")
expectSettingAt("set raid alpha to 50", 2, "gf_raid.alphaCurrentOutOfCombat", 0.5, "alphaOutOfCombat")
expectSettingAt("make party frames more transparent by 10", 1, "gf_party.alphaCurrentInCombat", nil, "alphaInCombat", -0.1)
expectSettingAt("make party frames more transparent by 10", 2, "gf_party.alphaCurrentOutOfCombat", nil, "alphaOutOfCombat", -0.1)
MSUF.MSUF2.activeKey = "gf_layout"
MSUF.MSUF2.gfScope = "raid"
expectSettingAt("set alpha to 60", 1, "gf_raid.alphaCurrentInCombat", 0.6, "alphaInCombat")
expectSettingAt("set alpha to 60", 2, "gf_raid.alphaCurrentOutOfCombat", 0.6, "alphaOutOfCombat")
MSUF.MSUF2.activeKey = "home"
expectSetting("increase player width by 5", "player.width", nil, "width", 5)
expectSetting("decrease player name font size by 2", "player.nameFontSize", nil, "nameFontSize", -2)
expectSettingAt("increase player alpha by 5", 1, "player.alphaInCombat", nil, "alphaInCombat", 0.05)
expectSettingAt("increase player alpha by 5", 2, "player.alphaOutOfCombat", nil, "alphaOutOfCombat", 0.05)
expectSetting("set target range fade alpha to 30", "target.rangeFadeAlpha", 0.3, "rangeFadeAlpha")
expectSetting("set target range fade affects health", "target.rangeFadeLayerMode", "health", "rangeFadeLayerMode")
expectUnknown("turn on player range fade")
expectUnknown("set player range fade alpha to 30")
expectSetting("turn on unitframe dispel overlay", "general.unitDispelOverlayEnabled", true, "unitDispelOverlay")
expectSetting("set unitframe dispel overlay detects any debuff", "general.unitDispelOverlayTrigger", "ANY_DEBUFF", "unitDispelOverlayTrigger")
expectSetting("set unitframe dispel overlay style top", "general.unitDispelOverlayStyle", "TOP", "unitDispelOverlayStyle")
expectSetting("turn off unitframe dispel overlay current health only", "general.unitDispelOverlayOnHealth", false, "unitDispelOverlayHealthOnly")
expectSetting("set unitframe dispel overlay opacity to 45", "general.unitDispelOverlayAlpha", 0.45, "unitDispelOverlayOpacity")
expectSettingAt("set only target unitframe dispel overlay opacity to 40", 1, "barScope.target.override", true, "override")
expectSettingAt("set only target unitframe dispel overlay opacity to 40", 2, "barScope.target.unitDispelOverlayAlpha", 0.4, "unitDispelOverlayOpacity")
expectSetting("decrease castbar outline thickness by 1", "general.castbarOutlineThickness", nil, "outline", -1)
expectSetting("set castbar text color to red", "general.castbarFontColor", nil, "castbarFontColor")
expectSetting("set target castbar text x offset to 3", "general.castbarTargetTextOffsetX", 3, "textOffsetX")
expectSetting("make unitframe dark mode a bit lighter", "general.darkBarGray", nil, "darkModeBarColor", 0.03)
expectSetting("make unitframe dark mode super dark", "general.darkBarGray", 0.01, "darkModeBarColor")
expectSetting("set unitframe dark mode to 20", "general.darkBarGray", 0.2, "darkModeBarColor")
expectSetting("make unitframe dark mode 20 percent", "general.darkBarGray", 0.2, "darkModeBarColor")
expectSetting("make unitframe dark mode darker by 5", "general.darkBarGray", nil, "darkModeBarColor", -0.05)
expectSetting("move class resource down 5", "bars.classPowerOffsetY", nil, "offsetY", -5)
expectSetting("set class resource width mode to custom", "bars.classPowerWidthMode", "custom", "widthMode")
expectSetting("set class resource background opacity to 40", "bars.classPowerBgAlpha", 0.4, "backgroundAlpha")
expectSetting("turn off class resource prediction", "bars.classPowerShowPrediction", false, "prediction")
expectSetting("set alt mana height to 12", "bars.altManaHeight", 12, "height")
expectSetting("turn on combat timer", "gameplay.enableCombatTimer", true, "enabled")
expectSetting("set combat timer size to 32", "gameplay.combatFontSize", 32, "fontSize")
expectSetting("move combat timer down 10", "gameplay.combatOffsetY", nil, "offsetY", -10)
expectSetting("set combat timer x offset to 12", "gameplay.combatOffsetX", 12, "offsetX")
expectSetting("set combat timer anchor to player", "gameplay.combatTimerAnchor", "player", "anchor")
expectSetting("turn on combat timer click through", "gameplay.combatTimerClickThrough", true, "clickThrough")
expectSetting("turn on combat enter leave text", "gameplay.enableCombatStateText", true, "enabled")
expectSetting("set combat enter leave text size to 28", "gameplay.combatStateFontSize", 28, "fontSize")
expectSetting("set combat state duration to 2.5", "gameplay.combatStateDuration", 2.5, "duration")
expectSetting("move combat enter leave text up 8", "gameplay.combatStateOffsetY", nil, "offsetY", 8)
expectSetting("set combat enter text to Pulling", "gameplay.combatStateEnterText", "Pulling", "enterText")
expectSetting("turn on totem frame", "gameplay.enablePlayerTotems", true, "enabled")
expectSetting("set totem frame icon size to 32", "gameplay.playerTotemsIconSize", 32, "size")
expectSetting("move totem frame right 6", "gameplay.playerTotemsOffsetX", nil, "offsetX", 6)
expectSetting("set totem frame from anchor to top left", "gameplay.playerTotemsAnchorFrom", "TOPLEFT", "anchorFrom")
expectSetting("set totem frame to anchor to bottom left", "gameplay.playerTotemsAnchorTo", "BOTTOMLEFT", "anchorTo")
expectSetting("turn on first dance", "gameplay.enableFirstDanceTimer", true, "enabled")
expectSetting("set first dance size to 44", "gameplay.firstDanceIconSize", 44, "size")
expectSetting("move first dance down 12", "gameplay.firstDanceOffsetY", nil, "offsetY", -12)
expectSetting("turn off first dance ready", "gameplay.firstDanceShowReady", false, "showReady")
expectSetting("turn on combat crosshair", "gameplay.enableCombatCrosshair", true, "enabled")
expectSetting("set crosshair size to 44", "gameplay.crosshairSize", 44, "size")
expectSetting("make crosshair thicker by 2", "gameplay.crosshairThickness", nil, "thickness", 2)
expectSetting("turn on crosshair range color", "gameplay.enableCombatCrosshairMeleeRangeColor", true, "rangeColor")
expectSetting("turn on crosshair spell per spec", "gameplay.meleeSpellPerSpec", true, "perSpec")
expectActionArg("set crosshair spell to 12345", "set_crosshair_melee_spell", "value", "12345")
expectUnknown("move crosshair down 5")
MSUF.MSUF2.activeKey = "gameplay"
expectSetting("turn on timer", "gameplay.enableCombatTimer", true, "enabled")
expectSetting("move timer down 5", "gameplay.combatOffsetY", nil, "offsetY", -5)
expectSetting("set timer anchor to target", "gameplay.combatTimerAnchor", "target", "anchor")
expectSetting("set crosshair thickness to 4", "gameplay.crosshairThickness", 4, "thickness")
MSUF.MSUF2.activeKey = "home"
expectSetting("turn on class color mode for raidframe", "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 1, "gf_party.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 2, "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 3, "gf_mythicraid.gfBarMode", "CLASS", "groupBarMode")
expectSetting("set raid anchor to target", "gf_raid.anchorToFrame", "target", "anchorToFrame")
expectSetting("set raid frames to grow right", "gf_raid.growth", "RIGHT", "growth")
expectSetting("set raid scale to 90", "gf_raid.frameScaleManual", 90, "frameScaleManual")
expectSetting("set raid scale at 10 to 95", "gf_raid.scaleAt10", 95, "scaleAt10")
expectSetting("set raid 11-20 player scale to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("increase raid scale at 10 by 5", "gf_raid.scaleAt10", nil, "scaleAt10", 5)
expectSetting("set raid backdrop opacity to 50", "gf_raid.bgA", 0.5, "bgAlpha")
expectSetting("set raid hp fill opacity to 75", "gf_raid.hpBarAlpha", 0.75, "hpBarAlpha")
expectSetting("set raid hp track opacity to 25", "gf_raid.hpBgAlpha", 0.25, "hpBgAlpha")
expectSetting("turn on raid dispel overlay", "gf_raid.dispelOverlayEnabled", true, "dispelOverlay")
expectSetting("set raid dispel overlay detects any debuff", "gf_raid.dispelOverlayTrigger", "ANY_DEBUFF", "dispelOverlayTrigger")
expectSetting("set raid dispel overlay style bottom", "gf_raid.dispelOverlayStyle", "BOTTOM", "dispelOverlayStyle")
expectSetting("turn off raid dispel overlay current health only", "gf_raid.dispelOverlayOnHealth", false, "dispelOverlayOnHealth")
expectSetting("set raid dispel overlay opacity to 55", "gf_raid.dispelOverlayAlpha", 0.55, "dispelOverlayAlpha")
expectSetting("set player custom anchor frame to PlayerFrame", "player.anchorFrameName", "PlayerFrame", "anchorFrameName")
expectSetting("set raid custom anchor to CompactRaidFrame1", "gf_raid.customAnchorFrame", "CompactRaidFrame1", "customAnchorFrame")
expectSetting("only player bars on", "barScope.player.override", true, "override")
expectSetting("only target fonts on", "fontScope.target.override", true, "override")
expectSettingAt("set only player bar outline thickness to 3", 1, "barScope.player.override", true, "override")
expectSettingAt("set only player bar outline thickness to 3", 2, "barScope.player.barOutlineThickness", 3, "outline")
expectSettingAt("set only party bars dispel border off", 1, "barScope.gf_party.override", true, "override")
expectSettingAt("set only party bars dispel border off", 2, "barScope.gf_party.dispelOutlineMode", "off", "dispelBorder")
expectSettingAt("set target font outline only to THICKOUTLINE", 1, "fontScope.target.override", true, "override")
expectSettingAt("set target font outline only to THICKOUTLINE", 2, "fontScope.target.outline", "THICKOUTLINE", "outline")
expectSettingAt("increase only player bar outline thickness by 1", 1, "barScope.player.override", true, "override")
expectSettingAt("increase only player bar outline thickness by 1", 2, "barScope.player.barOutlineThickness", nil, "outline", 1)
setFollowupContext("unitframe", "name", false)
expectSetting("same for target", "target.showName", false, "name")
setFollowupContext("unitframe", "name", false)
expectSetting("same for raid", "gf_raid.showName", false, "name")
setFollowupContext("group", "name", false)
expectSetting("do that for target", "target.showName", false, "name")
setFollowupContext("globalBars", "outline", 3)
expectSetting("also target", "barScope.target.barOutlineThickness", 3, "outline")
setFollowupContext("globalBars", "outline", 3)
expectSetting("same for party", "barScope.gf_party.barOutlineThickness", 3, "outline")
setFollowupContext("globalBars", "barOutlineColor", { r = 1, g = 128 / 255, b = 0 })
expectColorSetting("same for target", "barScope.target.barOutlineColor", 1, 128 / 255, 0, "barOutlineColor")
setRepeatContext("player.hpOffsetY", 10, "up")
expectSetting("more", "player.hpOffsetY", nil, "hpOffsetY", 10)
expectSetting("more by 2", "player.hpOffsetY", nil, "hpOffsetY", 2)
expectSetting("a little more", "player.hpOffsetY", nil, "hpOffsetY", 5)
expectSetting("too much", "player.hpOffsetY", nil, "hpOffsetY", -10)
expectSetting("not enough", "player.hpOffsetY", nil, "hpOffsetY", 10)
expectSetting("left", "player.hpOffsetX", nil, "hpOffsetX", -10)
expectSetting("right", "player.hpOffsetX", nil, "hpOffsetX", 10)
expectSetting("opposite", "player.hpOffsetY", nil, "hpOffsetY", -10)
setRepeatContext("player.hpOffsetY", -10, "down")
expectSetting("more", "player.hpOffsetY", nil, "hpOffsetY", -10)
expectSetting("up", "player.hpOffsetY", nil, "hpOffsetY", 10)
setNumericContext("bars.barOutlineThickness", 2)
expectSetting("more", "bars.barOutlineThickness", nil, "outline", 1)
expectSetting("bigger", "bars.barOutlineThickness", nil, "outline", 1)
expectSetting("smaller", "bars.barOutlineThickness", nil, "outline", -1)
expectSetting("higher by 2", "bars.barOutlineThickness", nil, "outline", 2)
expectSetting("make it 6", "bars.barOutlineThickness", 6, "outline")
expectSetting("7", "bars.barOutlineThickness", 7, "outline")
expectSetting("max", "bars.barOutlineThickness", 8, "outline")
expectSetting("min", "bars.barOutlineThickness", 0, "outline")
expectAnswer("what did you change", "Global Bar Outline Thickness")

print("assistant_parser_smoke: ok")
