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

local function expectUnknown(text)
    local parsed = A.Parse(text)
    assert(parsed.kind == "unknown", text .. ": expected unknown, got " .. tostring(parsed.kind))
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
expectAction("quick setup class resources", "class_power_quick_setup")
expectActionArg("diagnose target castbar", "diagnose_castbar_visibility", "unit", "target")
expectActionArg("diagnose party frames", "diagnose_group_visibility", "scope", "party")
expectActionArg("diagnose player frame", "diagnose_unit_visibility", "unit", "player")
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
expectActionArg("turn off party hp move text as one group", "set_menu_selector_state", "selector", "group_text_move_together")
expectActionArg("turn off party hp move text as one group", "set_menu_selector_state", "scope", "party")
expectActionArg("turn off party hp move text as one group", "set_menu_selector_state", "value", false)
expectActionArg("set player power text per slot", "set_menu_selector_state", "selector", "unit_text_move_together")
expectActionArg("set player power text per slot", "set_menu_selector_state", "unit", "player")
expectActionArg("set player power text per slot", "set_menu_selector_state", "value", false)
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
expectSetting("move player portrait 5 right", "player.portraitOffsetX", nil, "portraitOffsetX", 5)
expectSetting("set player name anchor to right", "player.nameTextAnchor", "RIGHT", "nameTextAnchor")
expectSetting("move player name text 5 right", "player.nameOffsetX", nil, "nameOffsetX", 5)
expectSetting("set bars texture to Smooth", "general.barTexture", "Smooth", "texture")
expectSettingAt("set player alpha to 50", 1, "player.alphaInCombat", 0.5, "alphaInCombat")
expectSettingAt("set player alpha to 50", 2, "player.alphaOutOfCombat", 0.5, "alphaOutOfCombat")
expectSetting("increase player width by 5", "player.width", nil, "width", 5)
expectSetting("decrease player name font size by 2", "player.nameFontSize", nil, "nameFontSize", -2)
expectSettingAt("increase player alpha by 5", 1, "player.alphaInCombat", nil, "alphaInCombat", 0.05)
expectSettingAt("increase player alpha by 5", 2, "player.alphaOutOfCombat", nil, "alphaOutOfCombat", 0.05)
expectSetting("decrease castbar outline thickness by 1", "general.castbarOutlineThickness", nil, "outline", -1)
expectSetting("set castbar text color to red", "general.castbarFontColor", nil, "castbarFontColor")
expectSetting("set target castbar text x offset to 3", "general.castbarTargetTextOffsetX", 3, "textOffsetX")
expectSetting("make unitframe dark mode a bit lighter", "general.darkBarGray", nil, "darkModeBarColor", 0.03)
expectSetting("make unitframe dark mode super dark", "general.darkBarGray", 0.01, "darkModeBarColor")
expectSetting("turn on class color mode for raidframe", "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 1, "gf_party.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 2, "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 3, "gf_mythicraid.gfBarMode", "CLASS", "groupBarMode")
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

print("assistant_parser_smoke: ok")
