_G = _G or _ENV

local function exists(path)
    local handle = io.open(path, "r")
    if handle then
        handle:close()
        return true
    end
    return false
end

local MSUF = { MSUF2 = {} }
_G.MSUF_NS = MSUF
_G.MSUF2 = MSUF.MSUF2
_G.MSUF_DB = { general = {}, bars = {}, gameplay = {} }

local runtimeLoaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(runtimeLoaderPath)
RuntimeManifest.LoadAssistantRuntime(MSUF)
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
    assert(parsed.action and parsed.action.key == actionKey,
        text .. ": wrong action key " .. tostring(parsed.action and parsed.action.key) .. ", expected " .. tostring(actionKey))
    if page then
        assert(parsed.args and parsed.args.page == page, text .. ": wrong page " .. tostring(parsed.args and parsed.args.page))
    end
end

local function expectActionArg(text, actionKey, argKey, argValue)
    local parsed = A.Parse(text)
    assert(parsed.kind == "action", text .. ": expected action, got " .. tostring(parsed.kind))
    assert(parsed.action and parsed.action.key == actionKey,
        text .. ": wrong action key " .. tostring(parsed.action and parsed.action.key) .. ", expected " .. tostring(actionKey))
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

local function expectActionInputClarification(text)
    local parsed = A.Parse(text)
    assert(parsed.kind == "answer" and parsed.status == "ambiguous"
        and parsed.actionInputClarification == true and parsed.action == nil,
        text .. ": expected a non-executable action-input clarification, got " .. tostring(parsed.kind))
end

local function expectNoChange(text)
    local parsed = A.Parse(text)
    assert(parsed.kind ~= "changes", text .. ": expected no changes, got changes")
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

local function expectAnySetting(text, key, value, attr, delta)
    local parsed = A.Parse(text)
    assert(parsed.kind == "changes", text .. ": expected changes, got " .. tostring(parsed.kind))
    for _, change in ipairs(parsed.changes or {}) do
        if change.setting and change.setting.key == key then
            if value ~= nil then
                assert(change.value == value, text .. ": wrong value " .. tostring(change.value))
            end
            if attr then
                assert(change.setting.attribute == attr, text .. ": wrong attr " .. tostring(change.setting.attribute))
            end
            if delta ~= nil then
                assert(change.relativeDelta == delta, text .. ": wrong delta " .. tostring(change.relativeDelta))
            end
            return
        end
    end
    assert(false, text .. ": missing setting " .. tostring(key))
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
        assert(tostring(parsed.text or ""):find(contains, 1, true), text .. ": missing answer text " .. tostring(contains) .. "; actual " .. tostring(parsed.text or ""))
    end
end

local function expectKind(text, kind)
    local parsed = A.Parse(text)
    assert(parsed.kind == kind, text .. ": expected " .. tostring(kind) .. ", got " .. tostring(parsed.kind))
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

local function setLastChangeBundle(entries)
    local ctx = A.GetContext()
    ctx.lastChangeBundle = entries or {}
    local last = entries and entries[#entries] or nil
    ctx.lastSetting = last and last.key or nil
    ctx.lastValue = last and last.value or nil
end

local function setColorContext(key, value)
    local setting = assert(A.Registry:GetSetting(key), "missing color setting " .. tostring(key))
    local ctx = A.GetContext()
    ctx.lastChangeBundle = {
        {
            key = key,
            frameType = setting.frameType,
            attribute = setting.attribute,
            value = value,
        },
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
expectAction("restore maximized menu", "menu_window_restore")
expectAction("open recovery tools", "open_recovery_tools")
expectAction("close scaling tools", "set_dashboard_panel")
expectAction("toggle changelog", "set_dashboard_panel")
expectActionArg("close dashboard panel", "set_dashboard_panel", "panel", "all")
expectActionArg("close dashboard panel", "set_dashboard_panel", "open", false)
expectActionArg("open scale section", "set_dashboard_panel", "panel", "scaling")
expectActionArg("open scale section", "set_dashboard_panel", "open", true)
expectActionArg("close recovery section", "set_dashboard_panel", "panel", "recovery")
expectActionArg("close recovery section", "set_dashboard_panel", "open", false)
expectActionArg("collapse frames navigation section", "set_nav_section", "section", "unitframes")
expectActionArg("collapse frames navigation section", "set_nav_section", "open", false)
expectActionArg("open group frames navigation section", "set_nav_section", "section", "groupframes")
expectActionArg("open group frames navigation section", "set_nav_section", "open", true)
expectActionInputClarification("open navigation section")
expectActionArg("show search intro", "set_nav_search_intro", "command", "show")
expectActionArg("reset search intro", "set_nav_search_intro", "command", "reset")
expectActionArg("mark search intro seen", "set_nav_search_intro", "command", "seen")
expectAction("help", "assistant_help")
expectActionArg("help for player frame", "assistant_scope_help", "unit", "player")
expectActionArg("help for player frame", "assistant_scope_help", "frameType", "unitframe")
expectActionArg("help profile", "assistant_scope_help", "page", "profiles")
expectActionArg("profile help", "assistant_scope_help", "frameType", "profiles")
expectActionArg("how do profiles work", "assistant_scope_help", "page", "profiles")
expectAnswer("explain import profile", "Import Profile String into New Profile")
expectActionArg("how to copy profile", "assistant_scope_help", "page", "profiles")
expectActionArg("help group frames", "assistant_scope_help", "page", "gf_layout")
expectActionArg("group frames help", "assistant_scope_help", "frameType", "group")
expectActionArg("help class resource", "assistant_scope_help", "page", "classpower")
expectActionArg("gameplay help", "assistant_scope_help", "frameType", "gameplay")
expectActionArg("help edit mode", "assistant_scope_help", "frameType", "editMode")
expectActionArg("how do I move target frame left", "assistant_scope_help", "page", "uf_target")
expectActionArg("how do I move target frame left", "assistant_scope_help", "frameType", "unitframe")
expectActionArg("how do I hide target name", "assistant_scope_help", "unit", "target")
expectActionArg("how do I move target castbar down", "assistant_scope_help", "frameType", "castbar")
expectActionArg("how do I move class resource down", "assistant_scope_help", "page", "classpower")
expectActionArg("where can I change combat timer click through", "assistant_scope_help", "page", "gameplay")
expectActionArg("how do I make raid frames wider", "assistant_scope_help", "page", "gf_layout")
expectActionArg("how do I hide ready check on raid frames", "assistant_scope_help", "page", "gf_indicators")
expectActionArg("how do I make menu bigger", "set_dashboard_panel", "panel", "scaling")
-- Real Dashboard acceptance questions must never become setting plans. These
-- assertions protect the same parser-owned guard used by Submit's immediate
-- mutation path; the end-to-end safety audit additionally compares DB state.
expectNoChange("what is target frame width")
expectNoChange("where is raid ready check")
expectNoChange("what depends on target buffs")
expectNoChange("why is player power text hidden")
expectNoChange("how do profiles work")
expectNoChange("explain class resource width mode")
expectNoChange("where can I change castbar texture")
expectNoChange("why are party frames missing")
expectNoChange("what are your limits")
expectNoChange("answer in German what is aura filtering")
expectAction("where is raid ready check", "open_page", "gf_indicators")
expectActionArg("why is player power text hidden", "diagnose_unit_visibility", "unit", "player")
expectAnswer("what depends on target buffs", "Auras, buffs, and debuffs help")
expectAnswer("answer in German what is aura filtering", "Auras, buffs, and debuffs help")
expectAction("back", "dashboard_page_back")
expectAction("open previous page", "dashboard_page_back")
expectAction("forward", "dashboard_page_forward")
expectAction("open next page", "dashboard_page_forward")
expectAction("where is profile import", "open_page", "profiles")
expectAction("where is profile export", "open_page", "profiles")
expectAction("what profile am i using", "profile_summary")
expectActionArg("copy profile Test", "copy_profile", "name", "Test")
expectActionArg("copy from profile Test", "start_profile_copy_flow", "source", "Test")
expectActionArg("backup current profile as Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("clone current profile as Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("duplicate my active profile called Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("copy my current profile called Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("create profile from current called Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("make backup of current profile called Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("duplicate current profile as Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("save my current profile as Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("make a copy of this profile called Raid Backup", "copy_profile", "name", "Raid Backup")
expectActionArg("duplicate profile Raid as Raid Backup", "copy_profile_from_to", "source", "Raid")
expectActionArg("duplicate profile Raid as Raid Backup", "copy_profile_from_to", "name", "Raid Backup")
expectActionArg("copy profile Raid as Raid Backup", "copy_profile_from_to", "source", "Raid")
expectActionArg("copy profile Raid as Raid Backup", "copy_profile_from_to", "name", "Raid Backup")
expectActionArg("clone profile Raid as Raid Backup", "copy_profile_from_to", "source", "Raid")
expectActionArg("clone profile Raid as Raid Backup", "copy_profile_from_to", "name", "Raid Backup")
expectActionArg("dupe profile Raid to Raid Backup", "copy_profile_from_to", "source", "Raid")
expectActionArg("dupe profile Raid to Raid Backup", "copy_profile_from_to", "name", "Raid Backup")
expectActionArg("make a copy of profile Raid called Raid Backup", "copy_profile_from_to", "source", "Raid")
expectActionArg("make a copy of profile Raid called Raid Backup", "copy_profile_from_to", "name", "Raid Backup")
expectActionArg("delete profile Raid Backup", "delete_profile", "name", "Raid Backup")
expectActionArg("remove profile Raid Backup", "delete_profile", "name", "Raid Backup")
expectActionArg("remove the profile Raid Backup", "delete_profile", "name", "Raid Backup")
expectActionArg("use profile Raid", "switch_profile", "name", "Raid")
expectActionArg("use the Raid profile", "switch_profile", "name", "Raid")
expectActionArg("use my raid profile", "switch_profile", "name", "raid")
expectActionArg("use Raid Backup profile", "switch_profile", "name", "Raid Backup")
expectActionArg("load Raid profile", "switch_profile", "name", "Raid")
expectActionArg("activate Raid profile", "switch_profile", "name", "Raid")
expectActionArg("share my msuf profile", "export_profile", "kind", "all")
expectActionArg("save a backup of my profile", "export_profile", "kind", "all")
expectActionArg("backup my msuf settings", "export_profile", "kind", "all")
expectActionArg("backup my current settings", "export_profile", "kind", "all")
expectActionArg("backup before import", "export_profile", "kind", "all")
expectActionArg("backup before importing profile", "export_profile", "kind", "all")
expectActionArg("make a backup before importing", "export_profile", "kind", "all")
expectActionArg("backup first then import", "export_profile", "kind", "all")
expectActionArg("make a backup then import", "export_profile", "kind", "all")
expectAnswer("how do i backup before importing", "backup before importing profile")
expectActionArg("backup raid profile", "export_profile", "kind", "groupframe")
expectAnswer("restore my backup profile", "full profile name")
expectAnswer("use last backup profile", "full profile name")
expectAnswer("load backup profile", "full profile name")
expectActionArg("show me my profile string", "export_profile", "kind", "all")
expectActionArg("export group frames settings", "export_profile", "kind", "groupframe")
expectActionArg("export unit frame settings", "export_profile", "kind", "unitframe")
expectAction("import safely", "open_profile_import")
expectAction("import after backup", "open_profile_import")
expectAction("paste this safely", "open_profile_import")
expectActionArg("import this safely MSUF5:abcdef", "import_profile_string", "value", "MSUF5:abcdef")
expectAnswer("import this as new profile safely MSUF5:abcdef", "new profile be called")
expectActionArg("import this as new profile Raid Safe MSUF5:abcdef", "import_profile_string_new", "name", "Raid Safe")
expectActionArg("import this as new profile Raid Import safely MSUF5:abcdef", "import_profile_string_new", "name", "Raid Import")
expectActionArg("import this profile as Raid Import MSUF5:abcdef", "import_profile_string_new", "name", "Raid Import")
expectActionArg("import this profile as Raid Import MSUF5:abcdef", "import_profile_string_new", "value", "MSUF5:abcdef")
expectActionArg("paste profile string as Raid Import MSUF5:abcdef", "import_profile_string_new", "name", "Raid Import")
expectActionArg("paste profile string as Raid Import MSUF5:abcdef", "import_profile_string_new", "value", "MSUF5:abcdef")
expectActionArg("paste MSUF5:abcdef as new profile Import Test", "import_profile_string_new", "name", "Import Test")
expectActionArg("paste MSUF5:abcdef as new profile Import Test", "import_profile_string_new", "value", "MSUF5:abcdef")
expectActionArg("rename profile Test", "start_profile_rename_flow", "source", "Test")
expectActionArg("rename profile Test to New", "rename_profile", "source", "Test")
expectActionArg("rename profile Test to New", "rename_profile", "name", "New")
expectActionArg("benenne profil Raid in Raid Neu um", "rename_profile", "source", "Raid")
expectActionArg("benenne profil Raid in Raid Neu um", "rename_profile", "name", "Raid Neu")
expectActionArg("profil Raid in Raid Neu umbenennen", "rename_profile", "source", "Raid")
expectActionArg("profil Raid in Raid Neu umbenennen", "rename_profile", "name", "Raid Neu")
expectActionArg("profil Raid umbenennen", "start_profile_rename_flow", "source", "Raid")
expectCopy("copy target profile to player", "copy_unit", "target", { "player" }, { basics = true, text = true, portrait = true, power = true, castbar = true, status = true, load = true, transparency = true, layout = true })
do
    local parsed = A.Parse("copy target profile to player")
    assert(parsed.confirmRequired == true, "unit profile copy should ask for confirmation before copying all categories")
end
expectCopy("copy player profile to target without text", "copy_unit", "player", { "target" }, { basics = true, text = false, portrait = true, power = true, castbar = true, status = true, load = true, transparency = true, layout = true })
do
    local parsed = A.Parse("copy player profile to target without text")
    assert(parsed.confirmRequired == true, "unit profile copy with excluded categories should still ask for confirmation")
end
expectCopy("copy target profile to player without castbar", "copy_unit", "target", { "player" }, { basics = true, text = true, portrait = true, power = true, castbar = false, status = true, load = true, transparency = true, layout = true })
expectCopy("copy target to player without text", "copy_unit", "target", { "player" }, { basics = true, text = false, portrait = true, power = true, castbar = true, status = true, load = true, transparency = true, layout = false })
expectCopy("copy taregt profie to player", "copy_unit", "target", { "player" }, { basics = true, text = true, portrait = true, power = true, castbar = true, status = true, load = true, transparency = true, layout = true })
expectCopy("copy only text from target profile to player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("copy target text settings onto player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("copy target text and position onto player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = true })
expectCopy("uebernehme target text fuer player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("can you copy just the text options from target to player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("please copy just the text options from target to target of target", "copy_unit", "target", { "targettarget" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("use player frame transparency settings for target of target", "copy_unit", "player", { "targettarget" }, { basics = false, text = false, portrait = false, power = false, castbar = false, status = false, load = false, transparency = true, layout = false })
expectCopy("copy hp and energy settings from target to target of target frame", "copy_unit", "target", { "targettarget" }, { basics = false, text = true, power = true, portrait = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("also copy power text settings from target to target of target", "copy_unit", "target", { "targettarget" }, { basics = false, text = true, power = true, portrait = false, castbar = false, status = false, load = false, transparency = false, layout = false })
expectCopy("copy positioning from player to target", "copy_unit", "player", { "target" }, { basics = false, text = false, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = true })
expectCopy("copy just the text options from target to the same position to player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = true })
expectCopy("can you copy just the text options and position from target to player", "copy_unit", "target", { "player" }, { basics = false, text = true, portrait = false, power = false, castbar = false, status = false, load = false, transparency = false, layout = true })
expectCopy("copy raid profile to party", "copy_group", "raid", { "party" }, { general = true, health = true, dispel = true, text = true, font = true, range = true, indicators = true, auras = true, highlight = true, dstripe = true, features = true })
expectCopy("copy raid profile to party without text", "copy_group", "raid", { "party" }, { general = true, health = true, dispel = true, text = false, font = true, range = true, indicators = true, auras = true, highlight = true, dstripe = true, features = true })
expectCopy("copy raid settings to party except indicators", "copy_group", "raid", { "party" }, { general = true, health = true, dispel = true, text = true, font = true, range = true, indicators = false, auras = true, highlight = true, dstripe = true, features = true })
expectCopy("copy player text and castbar to target", "copy_unit", "player", { "target" }, { text = true, castbar = true, basics = false, layout = false })
expectCopy("copy player size to target", "copy_unit", "player", { "target" }, { layout = true, basics = true, text = false })
expectSettingAt("can you make the focus frame as big as player", 1, "focus.width", 275, "width")
expectSettingAt("can you make the focus frame as big as player", 2, "focus.height", 40, "height")
expectSettingAt("mach den fokus frame so gross wie spieler", 1, "focus.width", 275, "width")
expectSettingAt("mach den fokus frame so gross wie spieler", 2, "focus.height", 40, "height")
expectSettingAt("set player width to 300 and height to 45", 1, "player.width", 300, "width")
expectSettingAt("set player width to 300 and height to 45", 2, "player.height", 45, "height")
expectSettingAt("set player width and height to 300 and 45", 1, "player.width", 300, "width")
expectSettingAt("set player width and height to 300 and 45", 2, "player.height", 45, "height")
expectSettingAt("set player width and height to 300", 1, "player.width", 300, "width")
expectSettingAt("set player width and height to 300", 2, "player.height", 300, "height")
expectSettingAt("set player width 300, height 45", 1, "player.width", 300, "width")
expectSettingAt("set player width 300, height 45", 2, "player.height", 45, "height")
expectSettingAt("set player width 300 height 45", 1, "player.width", 300, "width")
expectSettingAt("set player width 300 height 45", 2, "player.height", 45, "height")
expectSettingAt("make player width 300 height 45", 1, "player.width", 300, "width")
expectSettingAt("make player width 300 height 45", 2, "player.height", 45, "height")
expectSettingAt("player width 300 height 45", 1, "player.width", 300, "width")
expectSettingAt("player width 300 height 45", 2, "player.height", 45, "height")
expectSettingAt("set player width=300 height=45", 1, "player.width", 300, "width")
expectSettingAt("set player width=300 height=45", 2, "player.height", 45, "height")
expectSettingAt("set player x 10 y 20", 1, "player.offsetX", 10, "offsetX")
expectSettingAt("set player x 10 y 20", 2, "player.offsetY", 20, "offsetY")
expectSettingAt("set player x and y to 10 and 20", 1, "player.offsetX", 10, "offsetX")
expectSettingAt("set player x and y to 10 and 20", 2, "player.offsetY", 20, "offsetY")
expectSettingAt("set player x offset 10 y offset 20", 1, "player.offsetX", 10, "offsetX")
expectSettingAt("set player x offset 10 y offset 20", 2, "player.offsetY", 20, "offsetY")
expectSettingAt("move player right 10 down 5", 1, "player.offsetX", nil, "offsetX", 10)
expectSettingAt("move player right 10 down 5", 2, "player.offsetY", nil, "offsetY", -5)
expectSettingAt("move player 10 right 5 down", 1, "player.offsetX", nil, "offsetX", 10)
expectSettingAt("move player 10 right 5 down", 2, "player.offsetY", nil, "offsetY", -5)
_G.MSUF_DB.player = _G.MSUF_DB.player or {}
_G.MSUF_DB.player.offsetX = -100
_G.MSUF_DB.player.offsetY = 0
_G.MSUF_DB.target = _G.MSUF_DB.target or {}
_G.MSUF_DB.target.offsetX = 100
_G.MSUF_DB.target.offsetY = 0
expectSettingAt("move player and target closer together", 1, "player.offsetX", nil, "offsetX", 10)
expectSettingAt("move player and target closer together", 2, "target.offsetX", nil, "offsetX", -10)
expectSettingAt("move player and target closer", 1, "player.offsetX", nil, "offsetX", 10)
expectSettingAt("move player and target closer", 2, "target.offsetX", nil, "offsetX", -10)
expectSettingAt("move player and target farther apart", 1, "player.offsetX", nil, "offsetX", -10)
expectSettingAt("move player and target farther apart", 2, "target.offsetX", nil, "offsetX", 10)
expectSettingAt("add more space between player and target", 1, "player.offsetX", nil, "offsetX", -10)
expectSettingAt("add more space between player and target", 2, "target.offsetX", nil, "offsetX", 10)
_G.MSUF_DB.player.offsetY = -100
_G.MSUF_DB.focus = _G.MSUF_DB.focus or {}
_G.MSUF_DB.focus.offsetX = 0
_G.MSUF_DB.focus.offsetY = 80
expectSettingAt("move player and focus closer together", 1, "player.offsetY", nil, "offsetY", 10)
expectSettingAt("move player and focus closer together", 2, "focus.offsetY", nil, "offsetY", -10)
_G.MSUF_DB.gf_party = _G.MSUF_DB.gf_party or {}
_G.MSUF_DB.gf_raid = _G.MSUF_DB.gf_raid or {}
_G.MSUF_DB.gf_party.offsetX = -50
_G.MSUF_DB.gf_party.offsetY = 0
_G.MSUF_DB.gf_raid.offsetX = 50
_G.MSUF_DB.gf_raid.offsetY = 0
expectSettingAt("move party and raid closer together", 1, "gf_party.offsetX", nil, "offsetX", 10)
expectSettingAt("move party and raid closer together", 2, "gf_raid.offsetX", nil, "offsetX", -10)
expectSettingAt("move player portrait x 5 y -3", 1, "player.portraitOffsetX", 5, "portraitOffsetX")
expectSettingAt("move player portrait x 5 y -3", 2, "player.portraitOffsetY", -3, "portraitOffsetY")
expectSettingAt("set player size to 300 by 45", 1, "player.width", 300, "width")
expectSettingAt("set player size to 300 by 45", 2, "player.height", 45, "height")
expectSettingAt("set player size 300x45", 1, "player.width", 300, "width")
expectSettingAt("set player size 300x45", 2, "player.height", 45, "height")
expectSettingAt("make player 300 wide 45 high", 1, "player.width", 300, "width")
expectSettingAt("make player 300 wide 45 high", 2, "player.height", 45, "height")
expectSettingAt("set player 300x45 target 250x40", 1, "player.width", 300, "width")
expectSettingAt("set player 300x45 target 250x40", 2, "player.height", 45, "height")
expectSettingAt("set player 300x45 target 250x40", 3, "target.width", 250, "width")
expectSettingAt("set player 300x45 target 250x40", 4, "target.height", 40, "height")
expectSettingAt("set player size 300x45 target size 250x40", 1, "player.width", 300, "width")
expectSettingAt("set player size 300x45 target size 250x40", 2, "player.height", 45, "height")
expectSettingAt("set player size 300x45 target size 250x40", 3, "target.width", 250, "width")
expectSettingAt("set player size 300x45 target size 250x40", 4, "target.height", 40, "height")
expectSettingAt("make player 300 by 45 and target 250 by 40", 1, "player.width", 300, "width")
expectSettingAt("make player 300 by 45 and target 250 by 40", 2, "player.height", 45, "height")
expectSettingAt("make player 300 by 45 and target 250 by 40", 3, "target.width", 250, "width")
expectSettingAt("make player 300 by 45 and target 250 by 40", 4, "target.height", 40, "height")
expectSettingAt("set party 120x36 raid 140x42 mythic raid 160x48", 1, "gf_party.width", 120, "width")
expectSettingAt("set party 120x36 raid 140x42 mythic raid 160x48", 2, "gf_party.height", 36, "height")
expectSettingAt("set party 120x36 raid 140x42 mythic raid 160x48", 3, "gf_raid.width", 140, "width")
expectSettingAt("set party 120x36 raid 140x42 mythic raid 160x48", 4, "gf_raid.height", 42, "height")
expectSettingAt("set party 120x36 raid 140x42 mythic raid 160x48", 5, "gf_mythicraid.width", 160, "width")
expectSettingAt("set party 120x36 raid 140x42 mythic raid 160x48", 6, "gf_mythicraid.height", 48, "height")
expectSettingAt("set party width 120 height 36 raid width 140 height 42", 1, "gf_party.width", 120, "width")
expectSettingAt("set party width 120 height 36 raid width 140 height 42", 2, "gf_party.height", 36, "height")
expectSettingAt("set party width 120 height 36 raid width 140 height 42", 3, "gf_raid.width", 140, "width")
expectSettingAt("set party width 120 height 36 raid width 140 height 42", 4, "gf_raid.height", 42, "height")
expectSettingAt("set party width 120 height 36 raid 140x42", 1, "gf_party.width", 120, "width")
expectSettingAt("set party width 120 height 36 raid 140x42", 2, "gf_party.height", 36, "height")
expectSettingAt("set party width 120 height 36 raid 140x42", 3, "gf_raid.width", 140, "width")
expectSettingAt("set party width 120 height 36 raid 140x42", 4, "gf_raid.height", 42, "height")
expectSettingAt("set player width to 300 and target height to 50", 1, "player.width", 300, "width")
expectSettingAt("set player width to 300 and target height to 50", 2, "target.height", 50, "height")
expectSettingAt("set player width 300 and target 250", 1, "player.width", 300, "width")
expectSettingAt("set player width 300 and target 250", 2, "target.width", 250, "width")
expectSettingAt("set player width to 300 and target to 250", 1, "player.width", 300, "width")
expectSettingAt("set player width to 300 and target to 250", 2, "target.width", 250, "width")
expectSettingAt("set player and target width to 300", 1, "player.width", 300, "width")
expectSettingAt("set player and target width to 300", 2, "target.width", 300, "width")
expectSettingAt("set player and target width and height to 300 and 45", 1, "player.width", 300, "width")
expectSettingAt("set player and target width and height to 300 and 45", 2, "target.width", 300, "width")
expectSettingAt("set player and target width and height to 300 and 45", 3, "player.height", 45, "height")
expectSettingAt("set player and target width and height to 300 and 45", 4, "target.height", 45, "height")
expectSettingAt("set player width and height 300 and 45", 1, "player.width", 300, "width")
expectSettingAt("set player width and height 300 and 45", 2, "player.height", 45, "height")
expectSettingAt("set player width height to 300 45", 1, "player.width", 300, "width")
expectSettingAt("set player width height to 300 45", 2, "player.height", 45, "height")
expectSettingAt("set player width height 300 45", 1, "player.width", 300, "width")
expectSettingAt("set player width height 300 45", 2, "player.height", 45, "height")
expectSettingAt("set player target focus widths to 300", 1, "player.width", 300, "width")
expectSettingAt("set player target focus widths to 300", 2, "target.width", 300, "width")
expectSettingAt("set player target focus widths to 300", 3, "focus.width", 300, "width")
expectSettingAt("increase player and target width by 5", 1, "player.width", nil, "width", 5)
expectSettingAt("increase player and target width by 5", 2, "target.width", nil, "width", 5)
expectSettingAt("increase player width and height by 5 and 10", 1, "player.width", nil, "width", 5)
expectSettingAt("increase player width and height by 5 and 10", 2, "player.height", nil, "height", 10)
expectSettingAt("decrease player width and height by 5 and 10", 1, "player.width", nil, "width", -5)
expectSettingAt("decrease player width and height by 5 and 10", 2, "player.height", nil, "height", -10)
expectSettingAt("make player width and height bigger by 5 and 10", 1, "player.width", nil, "width", 5)
expectSettingAt("make player width and height bigger by 5 and 10", 2, "player.height", nil, "height", 10)
expectSettingAt("increase player and target width and height by 5 and 10", 1, "player.width", nil, "width", 5)
expectSettingAt("increase player and target width and height by 5 and 10", 2, "target.width", nil, "width", 5)
expectSettingAt("increase player and target width and height by 5 and 10", 3, "player.height", nil, "height", 10)
expectSettingAt("increase player and target width and height by 5 and 10", 4, "target.height", nil, "height", 10)
expectSettingAt("increase player width by 5 and target by 10", 1, "player.width", nil, "width", 5)
expectSettingAt("increase player width by 5 and target by 10", 2, "target.width", nil, "width", 10)
expectSettingAt("decrease player width by 5 and target by 10", 1, "player.width", nil, "width", -5)
expectSettingAt("decrease player width by 5 and target by 10", 2, "target.width", nil, "width", -10)
expectSettingAt("decrease player width by 5 height by 10", 1, "player.width", nil, "width", -5)
expectSettingAt("decrease player width by 5 height by 10", 2, "player.height", nil, "height", -10)
expectSettingAt("make player and target width 300 height 45", 1, "player.width", 300, "width")
expectSettingAt("make player and target width 300 height 45", 2, "target.width", 300, "width")
expectSettingAt("make player and target width 300 height 45", 3, "player.height", 45, "height")
expectSettingAt("make player and target width 300 height 45", 4, "target.height", 45, "height")
expectSettingAt("set player width 300 height 45 name off", 1, "player.width", 300, "width")
expectSettingAt("set player width 300 height 45 name off", 2, "player.height", 45, "height")
expectSettingAt("set player width 300 height 45 name off", 3, "player.showName", false, "name")
expectSettingAt("set player width 300 height 45 name off portrait off", 1, "player.width", 300, "width")
expectSettingAt("set player width 300 height 45 name off portrait off", 2, "player.height", 45, "height")
expectSettingAt("set player width 300 height 45 name off portrait off", 3, "player.showName", false, "name")
expectSettingAt("set player width 300 height 45 name off portrait off", 4, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player width 300 height 45 and target name off", 1, "player.width", 300, "width")
expectSettingAt("set player width 300 height 45 and target name off", 2, "player.height", 45, "height")
expectSettingAt("set player width 300 height 45 and target name off", 3, "target.showName", false, "name")
expectSettingAt("set player width 300 height 45 target width 250 height 40 names off", 1, "player.width", 300, "width")
expectSettingAt("set player width 300 height 45 target width 250 height 40 names off", 2, "player.height", 45, "height")
expectSettingAt("set player width 300 height 45 target width 250 height 40 names off", 3, "target.width", 250, "width")
expectSettingAt("set player width 300 height 45 target width 250 height 40 names off", 4, "target.height", 40, "height")
expectSettingAt("set player width 300 height 45 target width 250 height 40 names off", 5, "player.showName", false, "name")
expectSettingAt("set player width 300 height 45 target width 250 height 40 names off", 6, "target.showName", false, "name")
expectSettingAt("set player width height 300 45 target width height 250 40", 1, "player.width", 300, "width")
expectSettingAt("set player width height 300 45 target width height 250 40", 2, "player.height", 45, "height")
expectSettingAt("set player width height 300 45 target width height 250 40", 3, "target.width", 250, "width")
expectSettingAt("set player width height 300 45 target width height 250 40", 4, "target.height", 40, "height")
expectSettingAt("set player width and height 300 and 45 target width and height 250 and 40", 1, "player.width", 300, "width")
expectSettingAt("set player width and height 300 and 45 target width and height 250 and 40", 2, "player.height", 45, "height")
expectSettingAt("set player width and height 300 and 45 target width and height 250 and 40", 3, "target.width", 250, "width")
expectSettingAt("set player width and height 300 and 45 target width and height 250 and 40", 4, "target.height", 40, "height")
expectSettingAt("set player width height 300 45 target width height 250 40 names off", 1, "player.width", 300, "width")
expectSettingAt("set player width height 300 45 target width height 250 40 names off", 2, "player.height", 45, "height")
expectSettingAt("set player width height 300 45 target width height 250 40 names off", 3, "target.width", 250, "width")
expectSettingAt("set player width height 300 45 target width height 250 40 names off", 4, "target.height", 40, "height")
expectSettingAt("set player width height 300 45 target width height 250 40 names off", 5, "player.showName", false, "name")
expectSettingAt("set player width height 300 45 target width height 250 40 names off", 6, "target.showName", false, "name")
expectSettingAt("set player and target width 300 height 45 name off", 1, "player.width", 300, "width")
expectSettingAt("set player and target width 300 height 45 name off", 2, "target.width", 300, "width")
expectSettingAt("set player and target width 300 height 45 name off", 3, "player.height", 45, "height")
expectSettingAt("set player and target width 300 height 45 name off", 4, "target.height", 45, "height")
expectSettingAt("set player and target width 300 height 45 name off", 5, "player.showName", false, "name")
expectSettingAt("set player and target width 300 height 45 name off", 6, "target.showName", false, "name")
expectSettingAt("set player and target width and height 300 and 45 and names off", 1, "player.width", 300, "width")
expectSettingAt("set player and target width and height 300 and 45 and names off", 2, "target.width", 300, "width")
expectSettingAt("set player and target width and height 300 and 45 and names off", 3, "player.height", 45, "height")
expectSettingAt("set player and target width and height 300 and 45 and names off", 4, "target.height", 45, "height")
expectSettingAt("set player and target width and height 300 and 45 and names off", 5, "player.showName", false, "name")
expectSettingAt("set player and target width and height 300 and 45 and names off", 6, "target.showName", false, "name")
expectSettingAt("turn off player name and portrait", 1, "player.showName", false, "name")
expectSettingAt("turn off player name and portrait", 2, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player name and portrait off", 1, "player.showName", false, "name")
expectSettingAt("set player name and portrait off", 2, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player and target name and portrait off", 1, "player.showName", false, "name")
expectSettingAt("set player and target name and portrait off", 2, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player and target name and portrait off", 3, "target.showName", false, "name")
expectSettingAt("set player and target name and portrait off", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player name off portrait on", 1, "player.showName", false, "name")
expectSettingAt("set player name off portrait on", 2, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off player name and target name on", 1, "player.showName", false, "name")
expectSettingAt("turn off player name and target name on", 2, "target.showName", true, "name")
expectSettingAt("turn off player name and on target portrait", 1, "player.showName", false, "name")
expectSettingAt("turn off player name and on target portrait", 2, "target.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off player name, target name on, focus portrait off", 1, "player.showName", false, "name")
expectSettingAt("turn off player name, target name on, focus portrait off", 2, "target.showName", true, "name")
expectSettingAt("turn off player name, target name on, focus portrait off", 3, "focus.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player name but keep portrait on", 1, "player.showName", false, "name")
expectSettingAt("turn off player name but keep portrait on", 2, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off player and target names but keep portraits on", 1, "player.showName", false, "name")
expectSettingAt("turn off player and target names but keep portraits on", 2, "target.showName", false, "name")
expectSettingAt("turn off player and target names but keep portraits on", 3, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off player and target names but keep portraits on", 4, "target.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off names but keep portraits on for player and target", 1, "player.showName", false, "name")
expectSettingAt("turn off names but keep portraits on for player and target", 2, "target.showName", false, "name")
expectSettingAt("turn off names but keep portraits on for player and target", 3, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off names but keep portraits on for player and target", 4, "target.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off player name and turn on player portrait", 1, "player.showName", false, "name")
expectSettingAt("turn off player name and turn on player portrait", 2, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("set player name and portrait on target name and portrait off", 1, "player.showName", true, "name")
expectSettingAt("set player name and portrait on target name and portrait off", 2, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("set player name and portrait on target name and portrait off", 3, "target.showName", false, "name")
expectSettingAt("set player name and portrait on target name and portrait off", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player name on portrait on target name off portrait off", 1, "player.showName", true, "name")
expectSettingAt("set player name on portrait on target name off portrait off", 2, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("set player name on portrait on target name off portrait off", 3, "target.showName", false, "name")
expectSettingAt("set player name on portrait on target name off portrait off", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player and target names", 1, "player.showName", false, "name")
expectSettingAt("turn off player and target names", 2, "target.showName", false, "name")
expectSettingAt("turn off player, target, and focus names", 1, "player.showName", false, "name")
expectSettingAt("turn off player, target, and focus names", 2, "target.showName", false, "name")
expectSettingAt("turn off player, target, and focus names", 3, "focus.showName", false, "name")
expectSettingAt("hide names for player target focus", 1, "player.showName", false, "name")
expectSettingAt("hide names for player target focus", 2, "target.showName", false, "name")
expectSettingAt("hide names for player target focus", 3, "focus.showName", false, "name")
expectSettingAt("turn off player target focus names", 1, "player.showName", false, "name")
expectSettingAt("turn off player target focus names", 2, "target.showName", false, "name")
expectSettingAt("turn off player target focus names", 3, "focus.showName", false, "name")
expectSettingAt("set player target focus names off", 1, "player.showName", false, "name")
expectSettingAt("set player target focus names off", 2, "target.showName", false, "name")
expectSettingAt("set player target focus names off", 3, "focus.showName", false, "name")
expectSettingAt("turn off names and portraits for player and target", 1, "player.showName", false, "name")
expectSettingAt("turn off names and portraits for player and target", 2, "target.showName", false, "name")
expectSettingAt("turn off names and portraits for player and target", 3, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off names and portraits for player and target", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player and target names and portraits", 1, "player.showName", false, "name")
expectSettingAt("turn off player and target names and portraits", 2, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player and target names and portraits", 3, "target.showName", false, "name")
expectSettingAt("turn off player and target names and portraits", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player target focus names and portraits", 1, "player.showName", false, "name")
expectSettingAt("turn off player target focus names and portraits", 2, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player target focus names and portraits", 3, "target.showName", false, "name")
expectSettingAt("turn off player target focus names and portraits", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player target focus names and portraits", 5, "focus.showName", false, "name")
expectSettingAt("turn off player target focus names and portraits", 6, "focus.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player target focus names portraits", 1, "player.showName", false, "name")
expectSettingAt("turn off player target focus names portraits", 2, "player.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player target focus names portraits", 3, "target.showName", false, "name")
expectSettingAt("turn off player target focus names portraits", 4, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player target focus names portraits", 5, "focus.showName", false, "name")
expectSettingAt("turn off player target focus names portraits", 6, "focus.portraitMode", "OFF", "portraitMode")
expectSettingAt("set player portrait shape to rounded and size to 64", 1, "player.portraitShape", "ROUNDED", "portraitShape")
expectSettingAt("set player portrait shape to rounded and size to 64", 2, "player.portraitSizeOverride", 64, "portraitSizeOverride")
expectSettingAt("set player portrait shape rounded border class color", 1, "player.portraitShape", "ROUNDED", "portraitShape")
expectSettingAt("set player portrait shape rounded border class color", 2, "player.portraitBorderStyle", "CLASS_COLOR", "portraitBorderStyle")
expectSettingAt("set player portrait shape rounded and portrait border class color", 1, "player.portraitShape", "ROUNDED", "portraitShape")
expectSettingAt("set player portrait shape rounded and portrait border class color", 2, "player.portraitBorderStyle", "CLASS_COLOR", "portraitBorderStyle")
expectSettingAt("set player name color class hp text color health", 1, "fontScope.player.nameColorMode", "CLASS", "nameColor")
expectSettingAt("set player name color class hp text color health", 2, "fontScope.player.colorHealthTextByHealth", "HEALTH", "healthTextColor")
expectSetting("set party hp text class color", "fontScope.shared.colorHealthTextByHealth", "CLASS", "healthTextColor")
expectSettingAt("set player border color red bar background color black", 1, "barScope.player.barOutlineColor", nil, "barOutlineColor")
expectSettingAt("set player border color red bar background color black", 2, "general.classBarBgColor", nil, "barBackgroundTint")
expectSettingAt("set player hp text left current and right percent", 1, "player.textLeft", "CURRENT", "hpTextLeft")
expectSettingAt("set player hp text left current and right percent", 2, "player.textRight", "PERCENT", "hpTextRight")
expectSettingAt("set player hp text left current right percent center max", 1, "player.textLeft", "CURRENT", "hpTextLeft")
expectSettingAt("set player hp text left current right percent center max", 2, "player.textRight", "PERCENT", "hpTextRight")
expectSettingAt("set player hp text left current right percent center max", 3, "player.textCenter", "MAX", "hpTextCenter")
expectSettingAt("set player hp text left current target hp text left percent", 1, "player.textLeft", "CURRENT", "hpTextLeft")
expectSettingAt("set player hp text left current target hp text left percent", 2, "target.textLeft", "PERCENT", "hpTextLeft")
expectSettingAt("set player hp text left current right percent target hp text left percent right current", 1, "player.textLeft", "CURRENT", "hpTextLeft")
expectSettingAt("set player hp text left current right percent target hp text left percent right current", 2, "player.textRight", "PERCENT", "hpTextRight")
expectSettingAt("set player hp text left current right percent target hp text left percent right current", 3, "target.textLeft", "PERCENT", "hpTextLeft")
expectSettingAt("set player hp text left current right percent target hp text left percent right current", 4, "target.textRight", "CURRENT", "hpTextRight")
expectSettingAt("set player power text left current target power text right percent", 1, "player.powerTextLeft", "CURRENT", "powerTextLeft")
expectSettingAt("set player power text left current target power text right percent", 2, "target.powerTextRight", "PERCENT", "powerTextRight")
expectSettingAt("set player portrait size 64 border thickness 6 background on", 1, "player.portraitSizeOverride", 64, "portraitSizeOverride")
expectSettingAt("set player portrait size 64 border thickness 6 background on", 2, "player.portraitBorderThickness", 6, "portraitBorderThickness")
expectSettingAt("set player portrait size 64 border thickness 6 background on", 3, "player.portraitBgEnabled", true, "portraitBgEnabled")
expectSettingAt("set player portrait shape rounded border thickness 6 background on", 1, "player.portraitShape", "ROUNDED", "portraitShape")
expectSettingAt("set player portrait shape rounded border thickness 6 background on", 2, "player.portraitBorderThickness", 6, "portraitBorderThickness")
expectSettingAt("set player portrait shape rounded border thickness 6 background on", 3, "player.portraitBgEnabled", true, "portraitBgEnabled")
expectSettingAt("turn off player name target portrait focus power bar", 1, "player.showName", false, "name")
expectSettingAt("turn off player name target portrait focus power bar", 2, "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("turn off player name target portrait focus power bar", 3, "focus.showPowerBar", false, "powerBar")
expectSettingAt("set party width to 120 and height to 36 and power bar height to 5", 1, "gf_party.width", 120, "width")
expectSettingAt("set party width to 120 and height to 36 and power bar height to 5", 2, "gf_party.height", 36, "height")
expectSettingAt("set party width to 120 and height to 36 and power bar height to 5", 3, "gf_party.powerHeight", 5, "powerHeight")
expectCopy("copy player all settings to target", "copy_unit", "player", { "target" }, { basics = true, text = true, portrait = true, power = true, castbar = true, status = true, load = true, transparency = true, layout = true })
expectCopy("copy party health and text to raid", "copy_group", "party", { "raid" }, { health = true, dispel = false, text = true, general = false, font = false })
expectCopy("can you copy just health and text options from party to raid", "copy_group", "party", { "raid" }, { health = true, dispel = false, text = true, general = false, font = false })
expectCopy("copy party health bars to raid", "copy_group", "party", { "raid" }, { health = true, dispel = false, text = false, highlight = false, dstripe = false })
expectCopy("copy party dispel overlay to raid", "copy_group", "party", { "raid" }, { general = false, health = false, dispel = true, text = false, font = false, range = false, indicators = false, auras = false, highlight = false, dstripe = false, features = false })
expectCopy("copy raid layout but not auras to party", "copy_group", "raid", { "party" }, { general = true, health = false, text = false, auras = false })
expectCopy("copy raid layout without auras to party", "copy_group", "raid", { "party" }, { general = true, health = false, text = false, auras = false })
expectCopy("make party look like raid without auras", "copy_group", "raid", { "party" }, { general = true, health = true, text = true, auras = false })
expectCopy("copy raid buffs to party", "copy_group", "raid", { "party" }, { general = false, health = false, dispel = false, text = false, font = false, range = false, indicators = false, auras = true, highlight = false, dstripe = false, features = false })
expectCopy("copy raid auras to party", "copy_group", "raid", { "party" }, { general = false, health = false, dispel = false, text = false, font = false, range = false, indicators = false, auras = true, highlight = false, dstripe = false, features = false })
expectCopy("copy party all settings to all groups", "copy_group", "party", { "raid", "mythicraid" }, { general = true, health = true, dispel = true, text = true, font = true, range = true, indicators = true, auras = true, highlight = true, dstripe = true, features = true })
expectAnswer("copy just text options from target to party group frame", "different layout options")
expectActionArg("apply 1440p global ui scale preset", "apply_global_scale_preset", "preset", "1440p")
expectActionArg("apply 1080p ui preset", "apply_global_scale_preset", "preset", "1080p")
expectSetting("turn on general.globalUiScaleEnabled", "general.globalUiScaleEnabled", true, "globalUiScaleEnabled")
expectSetting("turn on global ui scale", "general.globalUiScaleEnabled", true, "globalUiScaleEnabled")
expectSetting("turn off global ui scale", "general.globalUiScaleEnabled", false, "globalUiScaleEnabled")
expectSetting("make msuf menu bigger", "general.slashMenuScale", nil, "menuScale", 0.05)
expectSetting("make the msuf menu smaller", "general.slashMenuScale", nil, "menuScale", -0.05)
expectSetting("make all msuf frames bigger", "general.msufUiScale", nil, "msufFrameScale", 0.05)
expectSetting("make wow ui bigger", "general.globalUiScale", nil, "globalUiScale", 0.05)
expectAction("start guided setup", "guided_setup")
expectAction("i never used msuf can you guide me", "guided_setup")
expectAction("can you show me around msuf", "guided_setup")
for _, case in ipairs({
    { "help me setup group frames", "guided_setup" },
    { "castbar setup guide", "guided_setup" },
    { "profile setup guide", "guided_setup" },
    { "show setup", "guided_setup_step" },
}) do
    local input, expectedKey = case[1], case[2]
    local parsed = A.Parse(input)
    assert(parsed and parsed.kind == "action" and parsed.action and parsed.action.key == expectedKey,
        input .. ": expected guided setup action " .. expectedKey)
    assert(next(parsed.args or {}) == nil,
        input .. ": native guided setup must not retain legacy text-wizard arguments")
end
do
    local ctx = A.GetContext()
    ctx.guidedSetup = { step = 2, styleLabel = "clean" }
    local parsed = A.Parse("next")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Legacy guidedSetup context must not hijack bare next")
    parsed = A.Parse("back")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Legacy guidedSetup context must not hijack bare back")
    parsed = A.Parse("cancel")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Legacy guidedSetup context must not hijack bare cancel")
    parsed = A.Parse("next setup step")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Native tour steps must use the highlighted menu controls")
    parsed = A.Parse("back setup step")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Native tour back must use the guided bar")
    parsed = A.Parse("cancel setup")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Native tour pause must use the guided bar")
    parsed = A.Parse("open previous page")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Guided setup must not hijack normal commands that mention previous/back")
    parsed = A.Parse("continue changing player frame")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "guided_setup_step"), "Guided setup must not hijack longer normal commands that mention continue")
    ctx.guidedSetup = nil
end
expectActionArg("copy discord link", "copy_support_link", "link", "discord")
expectAction("support links", "support_links_summary")
expectActionArg("turn on absorb test bars", "toggle_absorb_bar_test", "value", true)
expectActionArg("stop absorb test bars", "toggle_absorb_bar_test", "value", false)
expectActionArg("turn on aggro test border", "toggle_highlight_border_test", "kind", "aggro")
expectActionArg("turn on aggro test border", "toggle_highlight_border_test", "value", true)
expectActionArg("turn off dispel test border", "toggle_highlight_border_test", "kind", "dispel")
expectActionArg("turn off dispel test border", "toggle_highlight_border_test", "value", false)
expectActionArg("preview purge border test", "toggle_highlight_border_test", "kind", "purge")
expectActionArg("turn on boss target test border", "toggle_highlight_border_test", "kind", "bossTarget")
expectAction("recovery tools", "open_recovery_tools")
expectAction("enter edit mode", "assistant.action.editMode.enter")
expectAction("exit edit mode", "assistant.action.editMode.exit")
expectAction("edit mode status", "assistant.diagnostic.editMode.status")
expectActionArg("diagnose gameplay", "diagnose_gameplay_helpers", "feature", "all")
expectActionArg("why is my combat timer not showing", "diagnose_gameplay_helpers", "feature", "combatTimer")
expectActionArg("wieso ist das fadenkreuz nicht sichtbar", "diagnose_gameplay_helpers", "feature", "combatCrosshair")
expectAction("cancel edit mode", "assistant.action.editMode.cancel")
expectActionArg("in edit mode turn off preview auras", "assistant.action.editMode.auras", "value", false)
expectActionArg("turn off edit mode preview", "assistant.action.editMode.preview", "value", false)
expectActionArg("turn off edit mode gf preview", "assistant.action.editMode.groupPreview", "value", false)
expectActionArg("turn on raid frame preview", "assistant.action.editMode.groupPreview", "value", true)
expectActionArg("turn on raid frame preview", "assistant.action.editMode.groupPreview", "scope", "raid")
expectActionArg("turn on party frame preview", "assistant.action.editMode.groupPreview", "scope", "party")
expectActionArg("turn on edit mode snap", "assistant.action.editMode.snap", "value", true)
expectActionArg("turn off edit mode snapping", "assistant.action.editMode.snap", "value", false)
expectActionArg("turn on edit mode cdm", "assistant.action.editMode.cdm", "value", true)
expectAction("reset selected edit mode frame position", "assistant.action.editMode.resetPosition")
expectAction("open edit mode anchor picker", "assistant.action.editMode.anchorPicker")
expectSetting("turn off snapping feature", "general.slashMenuSnapEnabled", false, "menuSnap")
expectSetting("turn off snappign feature", "general.slashMenuSnapEnabled", false, "menuSnap")
expectSetting("turn off menu snapping", "general.slashMenuSnapEnabled", false, "menuSnap")
expectSetting("hide advanced menu section", "general.hideAdvancedMenu", false, "advancedMenuVisible")
expectSetting("show advanced menu section", "general.hideAdvancedMenu", true, "advancedMenuVisible")
expectSetting("turn on reduce menu motion", "general.reduceMotion", true, "reduceMotion")
expectSetting("turn off welcome message", "general.showWelcomeMessage", false, "welcomeMessage")
expectSetting("turn off peer version check", "general.versionCheckEnabled", false, "versionCheck")
expectSetting("hide minimap icon", "general.showMinimapIcon", false, "minimapIcon")
expectSetting("turn on target lost sounds", "general.playTargetSelectLostSounds", true, "targetSounds")
expectSetting("disable blizzard unitframes", "general.disableBlizzardUnitFrames", false, "blizzardFramesVisible")
expectSetting("enable blizzard unitframes", "general.disableBlizzardUnitFrames", true, "blizzardFramesVisible")
expectSetting("fully hide blizzard player frame", "general.hardKillBlizzardPlayerFrame", true, "hardKillBlizzardPlayerFrame")
expectSetting("set menu language to german", "general.menuLocale", "deDE", "menuLocale")
expectSetting("set tooltip source to msuf", "general.unitTooltipProvider", "MSUF", "tooltipProvider")
expectSetting("set tooltip anchor to cursor", "general.unitTooltipAnchor", "CURSOR", "tooltipAnchor")
expectSetting("show tooltips only out of combat", "general.unitTooltipMode", "OOC", "tooltipMode")
expectSetting("set tooltip modifier to shift", "general.unitTooltipModifier", "SHIFT", "tooltipModifier")
expectAction("undo menu change", "menu_history_undo")
expectAction("redo menu change", "menu_history_redo")
expectKind("revert that", "undo")
expectKind("take it back", "undo")
expectKind("mach das rueckgaengig", "undo")
expectKind("redo that", "redo")
expectAction("reset all menu changes from this session", "menu_history_reset_session")
expectAction("reset assistant changes", "menu_history_reset_session")
expectAction("quick setup class resources", "class_power_quick_setup")
expectActionArg("start class resource preview animation", "class_power_preview_animate", "value", true)
expectActionArg("stop class resource preview animation", "class_power_preview_animate", "value", false)
expectActionArg("animate class resource", "class_power_preview_animate", "value", true)
expectActionArg("stop class power animation", "class_power_preview_animate", "value", false)
do
    local classPowerAction = A.Parser and A.Parser.ParseClassPowerAction
    if A.Parser then A.Parser.ParseClassPowerAction = nil end
    local quick = A.Parse("quick setup class resources")
    assert(quick and quick.kind == "action" and quick.action and quick.action.key == "class_power_quick_setup", "Class Resource quick setup should resolve through registry action aliases without the specialty action parser")
    local start = A.Parse("start class resource preview animation")
    assert(start and start.kind == "action" and start.action and start.action.key == "class_power_preview_animate", "Class Resource preview animation should resolve through registry action aliases without the specialty action parser")
    assert(start.args and start.args.value == true, "Class Resource preview animation registry action alias did not parse start=true")
    local stop = A.Parse("stop class power animation")
    assert(stop and stop.kind == "action" and stop.action and stop.action.key == "class_power_preview_animate", "Class Power animation stop should resolve through registry action aliases without the specialty action parser")
    assert(stop.args and stop.args.value == false, "Class Resource preview animation registry action alias did not parse stop=false")
    local preview = A.Parse("preview class resource mage arcane")
    local change = preview and preview.changes and preview.changes[1]
    assert(preview and preview.kind == "changes", "Class Resource preview resource should parse as a setting change")
    assert(change and change.setting and change.setting.key == "menu.classPowerPreviewResource", "Class Resource preview resource registry exact alias picked the wrong setting")
    assert(change.value == "mage_arcane", "Class Resource preview resource registry exact alias picked the wrong value")
    if A.Parser then A.Parser.ParseClassPowerAction = classPowerAction end
end
expectActionArg("diagnose target castbar", "diagnose_castbar_visibility", "unit", "target")
expectActionArg("target castbar disappeared", "diagnose_castbar_visibility", "unit", "target")
expectActionArg("diagnose target auras", "diagnose_aura_visibility", "scope", "target")
expectActionArg("why are my raid buffs missing", "diagnose_aura_visibility", "scope", "raid")
expectActionArg("why are my raid buffs missing", "diagnose_aura_visibility", "lane", "buff")
expectActionArg("target buffs filtered out", "diagnose_aura_visibility", "scope", "target")
expectActionArg("target buffs filtered out", "diagnose_aura_visibility", "lane", "buff")
expectActionArg("raid buffs blacklisted", "diagnose_aura_visibility", "scope", "raid")
expectActionArg("raid buffs blacklisted", "diagnose_aura_visibility", "lane", "buff")
expectActionArg("clear all raid buff category blacklist", "aura_group_category_blacklist_clear", "scope", "raid")
expectActionArg("clear all raid buff category blacklist", "aura_group_category_blacklist_clear", "lane", "buff")
expectActionArg("blacklist cooldowns raid buff category", "aura_group_category_blacklist_set", "scope", "raid")
expectActionArg("blacklist cooldowns raid buff category", "aura_group_category_blacklist_set", "lane", "buff")
expectActionArg("blacklist cooldowns raid buff category", "aura_group_category_blacklist_set", "category", "COOLDOWNS")
expectActionArg("blacklist cooldowns raid buff category", "aura_group_category_blacklist_set", "value", true)
expectActionArg("show raid buff category blacklist", "aura_group_category_blacklist_summary", "scope", "raid")
expectActionArg("show raid buff category blacklist", "aura_group_category_blacklist_summary", "lane", "buff")
expectActionArg("current raid buff category blacklist", "aura_group_category_blacklist_summary", "scope", "raid")
expectActionArg("current raid buff category blacklist", "aura_group_category_blacklist_summary", "lane", "buff")
expectActionArg("list party debuff category blacklist", "aura_group_category_blacklist_summary", "scope", "party")
expectActionArg("list party debuff category blacklist", "aura_group_category_blacklist_summary", "lane", "debuff")
expectActionArg("allow all party debuff categories", "aura_group_category_blacklist_clear", "scope", "party")
expectActionArg("allow all party debuff categories", "aura_group_category_blacklist_clear", "lane", "debuff")
expectActionArg("reset party debuff category blacklist", "aura_group_category_blacklist_clear", "scope", "party")
expectActionArg("reset party debuff category blacklist", "aura_group_category_blacklist_clear", "lane", "debuff")
expectActionArg("blacklist Rejuvenation for raid buff blacklist", "aura_group_blacklist_add_spell", "scope", "raid")
expectActionArg("blacklist Rejuvenation for raid buff blacklist", "aura_group_blacklist_add_spell", "lane", "buff")
expectActionArg("blacklist Rejuvenation for raid buff blacklist", "aura_group_blacklist_add_spell", "value", "Rejuvenation")
expectActionArg("blacklist |cff71d5ff|Hspell:774:0|h[Rejuvenation]|h|r for party debuff blacklist", "aura_group_blacklist_add_spell", "scope", "party")
expectActionArg("blacklist |cff71d5ff|Hspell:774:0|h[Rejuvenation]|h|r for party debuff blacklist", "aura_group_blacklist_add_spell", "lane", "debuff")
expectActionArg("blacklist |cff71d5ff|Hspell:774:0|h[Rejuvenation]|h|r for party debuff blacklist", "aura_group_blacklist_add_spell", "value", "spell:774")
expectActionArg("allow Rejuvenation on raid buff blacklist", "aura_group_blacklist_remove_spell", "scope", "raid")
expectActionArg("allow Rejuvenation on raid buff blacklist", "aura_group_blacklist_remove_spell", "lane", "buff")
expectActionArg("allow Rejuvenation on raid buff blacklist", "aura_group_blacklist_remove_spell", "value", "Rejuvenation")
expectActionArg("clear all raid buff aura blacklist spells", "aura_group_blacklist_clear_spells", "scope", "raid")
expectActionArg("clear all raid buff aura blacklist spells", "aura_group_blacklist_clear_spells", "lane", "buff")
expectActionArg("add cooldown aura blacklist preset to party debuff blacklist", "aura_group_blacklist_add_preset", "scope", "party")
expectActionArg("add cooldown aura blacklist preset to party debuff blacklist", "aura_group_blacklist_add_preset", "lane", "debuff")
expectActionArg("add cooldown aura blacklist preset to party debuff blacklist", "aura_group_blacklist_add_preset", "preset", "COOLDOWNS")
expectActionArg("show raid buff aura blacklist", "aura_group_blacklist_summary", "scope", "raid")
expectActionArg("show raid buff aura blacklist", "aura_group_blacklist_summary", "lane", "buff")
expectActionArg("show raid buff blacklist", "aura_group_blacklist_summary", "scope", "raid")
expectActionArg("show raid buff blacklist", "aura_group_blacklist_summary", "lane", "buff")
expectActionArg("party debuffs not showing", "diagnose_aura_visibility", "scope", "party")
expectActionArg("party debuffs not showing", "diagnose_aura_visibility", "lane", "debuff")
expectActionArg("diagnose party frames", "diagnose_group_visibility", "scope", "party")
expectActionArg("raid frames disappeared", "diagnose_group_visibility", "scope", "raid")
expectActionArg("diagnose player frame", "diagnose_unit_visibility", "unit", "player")
expectActionArg("party frames disappeared", "diagnose_group_visibility", "scope", "party")
expectActionArg("my player frame disappeared", "diagnose_unit_visibility", "unit", "player")
expectAction("diagnose profiles", "diagnose_profile_status")
expectAction("my profile is broken", "diagnose_profile_status")
expectAction("profile import broken", "diagnose_profile_status")
expectAction("profile import failed", "diagnose_profile_status")
expectAction("profile import error", "diagnose_profile_status")
expectAction("profile export failed", "diagnose_profile_status")
expectAction("profile copy failed", "diagnose_profile_status")
expectAction("my profile import does not work", "diagnose_profile_status")
expectAction("fix profile mappings", "clear_broken_spec_profile_mappings")
expectAction("clear broken profile mappings", "clear_broken_spec_profile_mappings")
expectAction("diagnose class resources", "diagnose_class_power_status")
expectAction("class resources disappeared", "diagnose_class_power_status")
expectAction("combo points disappeared", "diagnose_class_power_status")
expectActionArg("crosshair disappeared", "diagnose_gameplay_helpers", "feature", "combatCrosshair")
expectAction("diagnose dashboard setup", "diagnose_dashboard_setup")
expectAction("dashboard is broken", "diagnose_dashboard_setup")
expectAction("assistant is stuck", "diagnose_dashboard_setup")
expectAnswer("detached power bar disappeared", "Which unit-frame power bar")
expectAction("assistant debug report", "assistant_status")
expectUnknown("is the assistant slow")
expectAction("assistant no match telemetry", "assistant_nomatch_telemetry")
expectAction("show unmatched commands", "assistant_nomatch_telemetry")
expectAction("assistant no match worklist", "assistant_nomatch_worklist")
expectAction("show alias candidates", "assistant_nomatch_worklist")
expectActionArg("show registry alias candidates", "assistant_nomatch_worklist", "owner", "registry-alias")
expectActionArg("show anchor no match worklist", "assistant_nomatch_worklist", "owner", "anchor-intent")
expectActionArg("show aura no match worklist", "assistant_nomatch_worklist", "owner", "aura-registry/backend")
expectActionArg("show knowledge no match worklist", "assistant_nomatch_worklist", "owner", "knowledge/help")
expectActionArg("show unresolved no match worklist", "assistant_nomatch_worklist", "resolution", "unresolved")
expectActionArg("show resolved no match worklist", "assistant_nomatch_worklist", "resolution", "resolved")
expectActionArg("show high priority no match worklist", "assistant_nomatch_worklist", "priority", "high")
expectActionArg("show medium priority no match worklist", "assistant_nomatch_worklist", "priority", "medium")
expectActionArg("show low priority no match worklist", "assistant_nomatch_worklist", "priority", "low")
expectActionArg("show high priority registry alias candidates", "assistant_nomatch_worklist", "owner", "registry-alias")
expectActionArg("show high priority registry alias candidates", "assistant_nomatch_worklist", "priority", "high")
expectActionArg("show geometry no match worklist", "assistant_nomatch_worklist", "tag", "geometry")
expectActionArg("show media tagged no match worklist", "assistant_nomatch_worklist", "tag", "media")
expectActionArg("show high priority geometry no match worklist", "assistant_nomatch_worklist", "priority", "high")
expectActionArg("show high priority geometry no match worklist", "assistant_nomatch_worklist", "tag", "geometry")
expectAction("clear assistant no match telemetry", "assistant_nomatch_clear")
expectAction("factory reset all", "factory_reset_all")
expectActionArg("reset player position", "reset_unit_position", "unit", "player")
expectAction("reset all frame positions", "reset_all_unit_positions")
expectAction("reset the position of all my frames", "recover_frames")
expectAction("restore the layout of every frame", "recover_frames")
expectAction("reset focus kick position", "reset_focus_kick_position")
expectActionArg("reset player settings", "reset_unit_page", "unit", "player")
expectAction("reset totem frame layout", "reset_player_totems_layout")
expectAction("reset all bars overrides", "reset_all_scoped_global_bars_overrides")
expectAction("reset all font overrides", "reset_all_scoped_global_font_overrides")
expectActionArg("reset player bars override", "reset_scoped_global_bars_override", "scope", "player")
expectActionArg("reset target font override", "reset_scoped_global_font_override", "scope", "target")
expectActionArg("reset party spell indicator Rejuvenation", "reset_group_spell_indicator_aura", "scope", "party")
expectActionArg("reset party status icons", "reset_group_status_icons", "scope", "party")
expectSetting("show test status icons on target frame", "target.stateIconsTestMode", true, "stateIconsTestMode")
expectSetting("hide test status icons on target frame", "target.stateIconsTestMode", false, "stateIconsTestMode")
expectSetting("turn off afk indicator for player frame", "general.statusIndicators.showAFK", false, "statusTextAFK")
expectSetting("turn on afk indicator for player frame", "general.statusIndicators.showAFK", true, "statusTextAFK")
expectSetting("turn off dnd indicator for player frame", "general.statusIndicators.showDND", false, "statusTextDND")
expectSetting("turn on dnd indicator for player frame", "general.statusIndicators.showDND", true, "statusTextDND")
expectSetting("turn off raid indicator for player", "player.showRaidMarker", false, "raidMarker")
expectSetting("turn on raid indicator for player", "player.showRaidMarker", true, "raidMarker")
expectSetting("turn on player raid marker", "player.showRaidMarker", true, "raidMarker")
do
    local oldPage = MSUF.MSUF2.activeKey
    MSUF.MSUF2.activeKey = "uf_player"
    expectSetting("set raid icon x offset to 4", "player.raidMarkerOffsetX", 4, "raidmarkerOffsetX")
    MSUF.MSUF2.activeKey = "uf_target"
    expectSetting("set raid icon x offset to 5", "target.raidMarkerOffsetX", 5, "raidmarkerOffsetX")
    MSUF.MSUF2.activeKey = oldPage
end
expectSetting("turn off elite indicator for target", "target.showEliteIcon", false, "showEliteIcon")
expectSetting("turn off rare symbol for target", "target.showEliteIcon", false, "showEliteIcon")
expectSetting("turn off group number indicator for player", "player.showRaidGroupInName", false, "showRaidGroupInName")
expectSetting("turn off dead indicator for player", "player.statusTextEnabled", false, "statusTextEnabled")
expectSetting("turn off ghost indicator for player", "player.statusTextEnabled", false, "statusTextEnabled")
expectSetting("turn off combat indicator for player", "player.showCombatStateIndicator", false, "showCombatStateIndicator")
expectSetting("turn off combat symbol for player", "player.showCombatStateIndicator", false, "showCombatStateIndicator")
expectSetting("turn off rested icon player", "player.showRestingIndicator", false, "showRestingIndicator")
expectSetting("turn off midnight style for rested icon player", "general.statusIconsUseMidnightStyle", false, "statusIconsUseMidnightStyle")
expectSetting("turn on midnight style for combat icon target", "general.statusIconsUseMidnightStyle", true, "statusIconsUseMidnightStyle")
expectSetting("turn on general.statusIconsUseMidnightStyle", "general.statusIconsUseMidnightStyle", true, "statusIconsUseMidnightStyle")
expectSetting("turn on status icons midnight style", "general.statusIconsUseMidnightStyle", true, "statusIconsUseMidnightStyle")
expectSetting("turn off status icons midnight style", "general.statusIconsUseMidnightStyle", false, "statusIconsUseMidnightStyle")
do
    local oldUnitStatusIconStyle = A.Parser.ParseUnitStatusIconStyle
    A.Parser.ParseUnitStatusIconStyle = function() error("legacy unit status icon style parser should not be in the live parse path") end
    local parsed = A.Parse("turn off midnight style for rested icon player")
    assert(parsed and parsed.kind == "changes", "unit status icon Midnight style should parse as a setting change")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "general.statusIconsUseMidnightStyle", "unit status icon Midnight style registry exact alias picked the wrong setting")
    assert(parsed.changes[1].value == false, "unit status icon Midnight style registry exact alias picked the wrong false value")
    parsed = A.Parse("turn on midnight style for combat icon target")
    assert(parsed and parsed.kind == "changes", "unit status icon Midnight style enable should parse as a setting change")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "general.statusIconsUseMidnightStyle", "unit status icon Midnight style enable picked the wrong setting")
    assert(parsed.changes[1].value == true, "unit status icon Midnight style registry exact alias picked the wrong true value")
    A.Parser.ParseUnitStatusIconStyle = oldUnitStatusIconStyle
end
expectSetting("send player rested icon layer behind", "player.restedStateIndicatorLayer", nil, "statusRestingLayer", -1)
expectSetting("bring player rested icon layer forward", "player.restedStateIndicatorLayer", nil, "statusRestingLayer", 1)
expectSetting("set player leader icon pack to midnight", "player.leaderIconStyle", "MIDNIGHT", "leaderIconStyle")
expectSetting("set player level anchor to top left", "player.levelIndicatorAnchor", "TOPLEFT", "levelAnchor")
expectSetting("set player dead text anchor to center", "player.statusTextAnchor", "CENTER", "statusTextAnchor")
expectSetting("set player raid marker anchor to top right", "player.raidMarkerAnchor", "TOPRIGHT", "raidmarkerAnchor")
expectSetting("move target raid marker to the top right", "target.raidMarkerAnchor", "TOPRIGHT", "raidmarkerAnchor")
expectSetting("put raid marker above target frame", "target.raidMarkerAnchor", "TOP", "raidmarkerAnchor")
expectSetting("set target elite icon anchor to top right", "target.eliteIconAnchor", "TOPRIGHT", "eliteiconAnchor")
expectSetting("set player incoming rez indicator anchor to bottom right", "player.incomingResIndicatorAnchor", "BOTTOMRIGHT", "statusIncomingResAnchor")
expectSetting("turn on focus level indicator", "focus.showLevelIndicator", true, "showLevelIndicator")
expectSetting("set focus level indicator size to 36", "focus.levelIndicatorSize", 36, "levelSize")
expectSetting("set focus level indicator anchor to top left", "focus.levelIndicatorAnchor", "TOPLEFT", "levelAnchor")
expectSetting("set focus level indicator layer to 5", "focus.levelIndicatorLayer", 5, "levelLayer")
expectSetting("make for focus frame the afk indicator smaller", "focus.statusTextSize", nil, "statusTextSize", -1)
expectSetting("set focus afk indicator size to 12", "focus.statusTextSize", 12, "statusTextSize")
expectSetting("move focus afk indicator down 3", "focus.statusTextOffsetY", nil, "statusTextOffsetY", -3)
expectSetting("make target raid indicator smaller", "target.raidMarkerSize", nil, "raidmarkerSize", -1)
expectSetting("make target raid marker bigger", "target.raidMarkerSize", nil, "raidmarkerSize", 1)
expectSetting("make target elite symbol bigger", "target.eliteIconSize", nil, "eliteiconSize", 1)
expectSetting("move target pvp flag left", "target.pvpIndicatorOffsetX", nil, nil, -10)
expectSetting("turn off combat load condition for player", "player.loadCondHideInCombat", false, "loadCondHideInCombat")
expectSetting("turn off ready check symbol for party", "gf_party.readyCheckIcon", false, "statusIconreadyCheckIconEnabled")
expectSetting("hide ready check on raid frames", "gf_raid.readyCheckIcon", false, "statusIconreadyCheckIconEnabled")
expectSetting("show ready check on raid frames", "gf_raid.readyCheckIcon", true, "statusIconreadyCheckIconEnabled")
expectSetting("make party ready check icon smaller", "gf_party.readyCheckSize", nil, "statusIconreadyCheckIconSize", -1)
expectSetting("send party ready check icon layer behind", "gf_party.readyCheckLayer", nil, "statusIconreadyCheckIconLayer", -1)
expectSetting("turn off midnight style for party ready check icon", "gf_party.useMidnightIcons", false, "useMidnightIcons")
expectSetting("set party leader icon pack to midnight", "gf_party.leaderIconStyle", "MIDNIGHT", "statusIconleaderIconStyle")
expectSetting("set party raid marker anchor to top left", "gf_party.raidMarkerAnchor", "TOPLEFT", "statusIconraidMarkerAnchor")
expectSetting("set raid ready check anchor to center", "gf_raid.readyCheckAnchor", "CENTER", "statusIconreadyCheckIconAnchor")
expectSetting("move raid ready check icon to top right", "gf_raid.readyCheckAnchor", "TOPRIGHT", "statusIconreadyCheckIconAnchor")
expectSetting("put raid ready check icon above the frame", "gf_raid.readyCheckAnchor", "TOP", "statusIconreadyCheckIconAnchor")
expectSetting("put raid role icons on the left", "gf_raid.roleIconAnchor", "LEFT", "statusIconroleIconAnchor")
expectSetting("make raid resurrection icon bigger", "gf_raid.resurrectIconSize", nil, "statusIconresurrectIconSize", 1)
expectSetting("hide summon icon on raid frames", "gf_raid.summonIcon", false, "statusIconsummonIconEnabled")
expectSetting("show summon icon on raid frames", "gf_raid.summonIcon", true, "statusIconsummonIconEnabled")
expectSetting("make raid summon icon bigger", "gf_raid.summonIconSize", nil, "statusIconsummonIconSize", 1)
expectSetting("put raid summon icon above the frame", "gf_raid.summonAnchor", "TOP", "statusIconsummonIconAnchor")
expectSetting("hide phase icon on party frames", "gf_party.phaseIcon", false, "statusIconphaseIconEnabled")
expectSetting("show pvp flag on raid frames", "gf_raid.pvpIcon", true, "statusIconpvpIconEnabled")
expectSetting("hide leader icon on raid frames", "gf_raid.leaderIcon", false, "statusIconleaderIconEnabled")
expectSetting("hide assist icon on raid frames", "gf_raid.assistIcon", false, "statusIconassistIconEnabled")
expectSetting("make raid assist icon smaller", "gf_raid.assistIconSize", nil, "statusIconassistIconSize", -1)
expectSetting("put raid leader icon top right", "gf_raid.leaderIconAnchor", "TOPRIGHT", "statusIconleaderIconAnchor")
do
    local parsed = A.Parse("where can I change summon icon on raid frames")
    assert(parsed.kind ~= "changes", "where-can group status icon question must not mutate settings")
end
expectSettingAt("turn off combat indicator for all unitframes", 1, "player.showCombatStateIndicator", false, "showCombatStateIndicator")
expectSettingAt("turn off combat indicator for all unitframes", 2, "target.showCombatStateIndicator", false, "showCombatStateIndicator")
expectSettingAt("turn off ready check symbol for all group frames", 1, "gf_party.readyCheckIcon", false, "statusIconreadyCheckIconEnabled")
expectSettingAt("turn off ready check symbol for all group frames", 2, "gf_raid.readyCheckIcon", false, "statusIconreadyCheckIconEnabled")
expectSettingAt("turn off ready check symbol for all group frames", 3, "gf_mythicraid.readyCheckIcon", false, "statusIconreadyCheckIconEnabled")
do
    local parsed = A.Parse("turn off ready check symbol for all group frames")
    for i = 1, #(parsed.changes or {}) do
        assert(parsed.changes[i].setting.key ~= "gf_party.enabled", "Ready Check symbol bulk command must not disable Party group frames")
    end
end
expectActionArg("show all status icons target", "preview_unit_status_indicator", "unit", "target")
expectActionArg("show all status icons target", "preview_unit_status_indicator", "mode", "all")
expectActionArg("test all status icons", "preview_unit_status_indicator", "unit", "player")
expectActionArg("test all status icons", "preview_unit_status_indicator", "mode", "all")
MSUF.MSUF2.activeKey = "uf_player"
MSUF.MSUF2.unitStatusSelection = { player = "level" }
expectActionArg("reset selected status indicator", "reset_unit_status_indicator", "unit", "player")
expectActionArg("reset selected status indicator", "reset_unit_status_indicator", "status", "level")
expectActionArg("preview current status indicator", "preview_unit_status_indicator", "unit", "player")
expectActionArg("preview current status indicator", "preview_unit_status_indicator", "status", "level")
expectActionArg("clear custom anchor", "clear_unit_custom_anchor", "unit", "player")
expectActionArg("open custom anchor picker", "start_unit_custom_anchor_picker", "unit", "player")
MSUF.MSUF2.activeKey = "gf_layout"
MSUF.MSUF2.gfScope = "raid"
MSUF.MSUF2.unitStatusSelection = {}
expectActionArg("clear custom anchor", "clear_group_custom_anchor", "scope", "raid")
expectActionArg("open custom anchor picker", "start_group_custom_anchor_picker", "scope", "raid")
MSUF.MSUF2.activeKey = nil
MSUF.MSUF2.gfScope = nil
MSUF.MSUF2.unitStatusSelection = {}
expectAnswer("where is custom anchor picker", "open player custom anchor picker")
expectActionInputClarification("reset selected status indicator")
expectActionInputClarification("reset unit status icon")
expectActionInputClarification("clear custom anchor")
MSUF.MSUF2.activeKey = "home"
expectActionArg("show all group status icons", "preview_group_status_icon", "scope", "party")
expectActionArg("show raid ready check test icons", "preview_group_status_icon", "scope", "raid")
expectActionArg("show raid ready check test icons", "preview_group_status_icon", "icon", "readyCheckIcon")
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
expectActionArg("put target health text right", "set_menu_selector_state", "selector", "unit_text")
expectActionArg("put target health text right", "set_menu_selector_state", "unit", "target")
expectActionArg("put target health text right", "set_menu_selector_state", "tab", "hp")
expectActionArg("put target health text right", "set_menu_selector_state", "slot", "right")
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
expectActionArg("select combo point class resource color", "set_menu_selector_state", "selector", "color_token")
expectActionArg("select combo point class resource color", "set_menu_selector_state", "kind", "classPower")
expectActionArg("select combo point class resource color", "set_menu_selector_state", "token", "COMBO_POINTS")
expectActionArg("select class resource style text tab", "set_menu_selector_state", "selector", "class_power_style_tab")
expectActionArg("select class resource style text tab", "set_menu_selector_state", "tab", "text")
expectActionArg("select class power style pips tab", "set_menu_selector_state", "tab", "pips")
expectActionArg("select highlight borders preview tab", "set_menu_selector_state", "selector", "bars_highlight_tab")
expectActionArg("select highlight borders preview tab", "set_menu_selector_state", "tab", "preview")
expectActionArg("select highlight priority tab", "set_menu_selector_state", "tab", "priority")
expectAction("assistant.workflow.status", "assistant.workflow.status")
expectAction("factory_reset_all", "factory_reset_all")
expectAnswer("copy group settings", "Which source and target group frames")
expectAnswer("copy raid settings", "Which source and target group frames")
expectAnswer("select text tab", "Which frame, text area, and slot or mode")
expectAnswer("select status indicator", "Which frame and indicator do you want me to use?")
expectAnswer("select power color token", "Which color slot do you want me to use?")
expectAnswer("set unit copy category", "Which copy categories do you want me to set?")
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
expectActionArg("turn on group copy dispel overlay category", "set_menu_selector_state", "category", "dispel")
expectActionArg("turn on group copy dispel overlay category", "set_menu_selector_state", "value", true)

expectSetting("turn off target castbar", "general.enableTargetCastbar", false, "enabled")
expectSetting("turn off target castbar name", "general.castbarTargetShowSpellName", false, "text")
expectSetting("turn off focus castbar text", "general.castbarFocusShowSpellName", false, "text")
expectSetting("turn off player castbar icon", "general.castbarPlayerShowIcon", false, "icon")
expectSettingAt("turn off player and target castbar icons", 1, "general.castbarPlayerShowIcon", false, "icon")
expectSettingAt("turn off player and target castbar icons", 2, "general.castbarTargetShowIcon", false, "icon")
expectSettingAt("set player and target castbar height and icon size to 20 and 18", 1, "general.castbarPlayerBarHeight", 20, "height")
expectSettingAt("set player and target castbar height and icon size to 20 and 18", 2, "general.castbarTargetBarHeight", 20, "height")
expectSettingAt("set player and target castbar height and icon size to 20 and 18", 3, "general.castbarPlayerIconSize", 18, "iconSize")
expectSettingAt("set player and target castbar height and icon size to 20 and 18", 4, "general.castbarTargetIconSize", 18, "iconSize")
expectSetting("make target castbar wider", "general.castbarTargetBarWidth", nil, "width", 25)
expectSetting("make target castbar narrower", "general.castbarTargetBarWidth", nil, "width", -25)
expectSetting("make focus castbar taller", "general.castbarFocusBarHeight", nil, "height", 5)
expectSetting("make boss castbars shorter", "general.bossCastbarHeight", nil, "height", -5)
expectSetting("move target castbar under target frame", "general.castbarTargetOffsetY", nil, "offsetY", -20)
expectSetting("put target castbar below target frame", "general.castbarTargetOffsetY", nil, "offsetY", -20)
expectSetting("put focus castbar above focus frame", "general.castbarFocusOffsetY", nil, "offsetY", 20)
expectSetting("make target castbar spell name bigger", "general.castbarTargetSpellNameFontSize", nil, "spellNameFontSize", 1)
expectSetting("make target castbar timer smaller", "general.castbarTargetTimeFontSize", nil, "timeFontSize", -1)
expectSetting("turn off target castbar time", "general.showTargetCastTime", false, "time")
expectSetting("turn off boss castbar spell name", "general.showBossCastName", false, "text")
expectSetting("set Player Castbar Icon Position to LEFT", "general.castbarPlayerIconPosition", "LEFT", "iconPosition")
expectSetting("set Target Castbar Spell Name Position to RIGHT", "general.castbarTargetSpellNamePosition", "RIGHT", "spellNamePosition")
expectSetting("set Focus Castbar Time Position to BELOW", "general.castbarFocusTimePosition", "BELOW", "timePosition")
expectSetting("set Player Castbar Spell Name Alignment to LEFT", "general.castbarPlayerSpellNameAlign", "LEFT", "spellNameAlign")
expectSetting("set player castbar spell text alignment to right", "general.castbarPlayerSpellNameAlign", "RIGHT", "spellNameAlign")
expectSetting("set Boss Castbar Icon Position to inside right", "general.bossCastIconPosition", "INSIDE_RIGHT", "iconPosition")
expectSetting("put target castbar icon on the right", "general.castbarTargetIconPosition", "RIGHT", "iconPosition")
expectSetting("put target castbar text in the middle", "general.castbarTargetSpellNamePosition", "CENTER", "spellNamePosition")
expectSetting("put target castbar time on the left", "general.castbarTargetTimePosition", "LEFT", "timePosition")
expectSetting("make castbar fill left to right", "general.castbarFillDirection", "LTR", "fillDirection")
expectSetting("make castbar fill right to left", "general.castbarFillDirection", "RTL", "fillDirection")
expectSetting("make castbar fill backwards", "general.castbarFillDirection", "RTL", "fillDirection")
expectSetting("reverse castbar fill", "general.castbarFillDirection", "RTL", "fillDirection")
expectSetting("make castbar fill normal direction", "general.castbarFillDirection", "LTR", "fillDirection")
expectSetting("make target castbar fill opposite", "general.castbarOpositeDirectionTarget", true, "targetOppositeDirection")
expectSetting("make target castbar use normal direction", "general.castbarOpositeDirectionTarget", false, "targetOppositeDirection")
expectSetting("stop target castbar filling opposite", "general.castbarOpositeDirectionTarget", false, "targetOppositeDirection")
expectSetting("turn off target power bar", "target.showPowerBar", false, "powerBar")
expectSetting("turn off target powerbar", "target.showPowerBar", false, "powerBar")
expectSetting("set target power bar height to 8", "target.powerBarHeight", 8, "powerBarHeight")
expectSetting("increase power bar hight target", "target.powerBarHeight", nil, "powerBarHeight", 1)
expectSetting("make player power bar a little taller", "player.powerBarHeight", nil, "powerBarHeight", 1)
expectSetting("make player powerbar thinner", "player.powerBarHeight", nil, "powerBarHeight", -1)
expectAnswer("make player power bar wider", "Power Bar width follows the frame")
expectSetting("turn on player power bar border", "player.powerBarBorderEnabled", true, "powerBarBorder")
expectSetting("set player power bar border thickness to 3", "player.powerBarBorderThickness", 3, "powerBarBorderThickness")
expectSetting("turn on player power border", "player.powerBarBorderEnabled", true, "powerBarBorder")
expectSetting("set player power border size to 3", "player.powerBarBorderThickness", 3, "powerBarBorderThickness")
expectSetting("set player bar outline thickness to 3", "barScope.player.barOutlineThickness", 3, "outline")
expectSetting("turn on player power bar gradient", "barScope.player.enablePowerGradient", true, "powerGradient")
expectSetting("turn off target power gradient", "barScope.target.enablePowerGradient", false, "powerGradient")
expectSetting("turn on power bar gradient", "general.enablePowerGradient", true, "powerGradient")
expectSettingAt("only turn on target power bar gradient", 1, "barScope.target.override", true, "override")
expectSettingAt("only turn on target power bar gradient", 2, "barScope.target.enablePowerGradient", true, "powerGradient")
expectSetting("turn on player reverse hp text order", "player.hpTextReverse", true, "hpTextReverse")
expectSetting("turn off player reverse hp text order", "player.hpTextReverse", false, "hpTextReverse")
expectSetting("turn on target reverse hp text", "target.hpTextReverse", true, "hpTextReverse")
expectSetting("turn on Player Keep Text & Portrait Visible", "player.alphaExcludeTextPortrait", true, "alphaExcludeTextPortrait")
expectSetting("turn off Boss Keep Text & Portrait Visible", "boss.alphaExcludeTextPortrait", false, "alphaExcludeTextPortrait")
expectSetting("turn on player text on detached power bar", "player.detachedPowerBarTextOnBar", true, "detachedPowerBarTextOnBar")
expectSetting("turn off player text on detached power bar", "player.detachedPowerBarTextOnBar", false, "detachedPowerBarTextOnBar")
expectSetting("set player detached power bar width to 410", "player.detachedPowerBarWidth", 410, "detachedPowerBarWidth")
expectSetting("set player detached power bar height to 41", "player.detachedPowerBarHeight", 41, "detachedPowerBarHeight")
expectSetting("make player detached powerbar wider", "player.detachedPowerBarWidth", nil, "detachedPowerBarWidth", 25)
expectSetting("make player detached powerbar taller", "player.detachedPowerBarHeight", nil, "detachedPowerBarHeight", 5)
expectSetting("set player detached power bar layer to 10", "player.detachedPowerBarFrameLevelOffset", 10, "detachedPowerBarFrameLevelOffset")
expectSetting("detach target power bar", "target.powerBarDetached", true, "powerBarDetached")
_G.MSUF_DB.target = _G.MSUF_DB.target or {}
_G.MSUF_DB.target.powerBarDetached = true
do
    local parsed = A.Parse("move target powerbar to the left")
    local change = firstChange(parsed)
    assert(parsed.kind == "changes", "detached powerbar movement should produce a concrete setting change")
    assert(change.setting.key == "target.detachedPowerBarOffsetX", "move target powerbar left: wrong setting " .. tostring(change.setting.key))
    assert(change.setting.attribute == "detachedPowerBarOffsetX", "move target powerbar left: wrong attr " .. tostring(change.setting.attribute))
    assert(change.relativeDelta == -10, "move target powerbar left: wrong delta " .. tostring(change.relativeDelta))
end
expectSetting("move target power bar left", "target.detachedPowerBarOffsetX", nil, "detachedPowerBarOffsetX", -10)
expectSetting("move target detached powerbar up 4", "target.detachedPowerBarOffsetY", nil, "detachedPowerBarOffsetY", 4)
expectSetting("set target powerbar x offset to 12", "target.detachedPowerBarOffsetX", 12, "detachedPowerBarOffsetX")
expectAnswer("move target powerbar closer to cooldownmanager", "Detached Power Bars use X/Y offsets instead of direct anchors")
do
    local parsed = A.Parse("move target powerbar under cooldownmanager")
    assert(parsed.kind == "answer", "target powerbar under cooldownmanager should explain detached anchor limits")
    assert(not (parsed.changes and parsed.changes[1]), "target powerbar under cooldownmanager must not change Target anchor")
end
expectSetting("move target power text left", "target.powerOffsetX", nil, "powerOffsetX", -10)
_G.MSUF_DB.target.powerBarDetached = false
expectKind("move target powerbar to the left", "unknown")
expectSetting("attach target power bar", "target.powerBarDetached", false, "powerBarDetached")
expectSetting("turn off raid power bar", "gf_raid.powerBarEnabled", false, "powerBar")
expectSetting("set raid power bar height to 9", "gf_raid.powerHeight", 9, "powerHeight")
expectSetting("make raid power bars taller", "gf_raid.powerHeight", nil, "powerHeight", 1)
expectAnswer("make raid power bars wider", "Power Bar width follows the group frame width")
expectSetting("turn off smooth power bar", "bars.smoothPowerBar", false, "smoothPower")
expectSetting("turn on bars.realtimePowerText", "bars.realtimePowerText", true, "realtimePowerText")
expectSetting("turn on realtime power text", "bars.realtimePowerText", true, "realtimePowerText")
expectSetting("turn off real time power text", "bars.realtimePowerText", false, "realtimePowerText")
expectKind("turn on bars.roundedUnitFrames", "unknown")
expectSetting("turn off target of target inline text", "targettarget.showToTInTargetName", false, "totInline")
do
    local parsed = A.Parse("turn off target of target inline")
    assert(parsed.kind == "ambiguous", "partial inline text command should suggest a numbered choice")
    assert(type(parsed.choices) == "table" and #parsed.choices >= 1, "partial inline text choices missing")
    assert(parsed.choices[1].setting and parsed.choices[1].setting.key == "targettarget.showToTInTargetName", "partial inline text wrong suggested setting")
    assert(parsed.choices[1].value == false, "partial inline text wrong suggested value")
end
expectSetting("change target inline seperator to /", "targettarget.totInlineSeparator", "/", "totInlineSeparator")
expectSetting("change target of target inline seperator to /", "targettarget.totInlineSeparator", "/", "totInlineSeparator")
expectSetting("change target inline separator to ->", "targettarget.totInlineCustomSeparator", "->", "totInlineCustomSeparator")
expectSetting("set player hp text delimiter to blank", "player.hpTextSeparator", "", "hpTextSeparator")
expectSetting("set target power text separator to pipe", "target.powerTextSeparator", "|", "powerTextSeparator")
expectSetting("set party hp text delimiter to slash", "gf_party.textDelimiter", " / ", "healthTextDelimiter")
expectSetting("set raid power text delimiter to dash", "gf_raid.powerTextDelimiter", " - ", "powerTextDelimiter")
expectSetting("set target inline separator to blank", "targettarget.totInlineSeparator", "", "totInlineSeparator")
do
    local parsed = A.Parse("change target inline seperator")
    assert(parsed.kind == "ambiguous", "missing inline separator value should ask for a numbered choice")
    assert(type(parsed.choices) == "table" and #parsed.choices >= 3, "inline separator choices missing")
    assert(parsed.choices[3].setting and parsed.choices[3].setting.key == "targettarget.totInlineSeparator", "inline separator slash choice wrong setting")
    assert(parsed.choices[3].value == "/", "inline separator slash choice wrong value")
end
expectSetting("turn off player castbar interrupt", "player.showInterrupt", false, "showInterrupt")
expectSetting("turn off interrupt for player", "player.showInterrupt", false, "showInterrupt")
expectSetting("turn off interrupt shake for player", "player.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off for all castbars interrupt", 1, "player.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off for all castbars interrupt", 2, "target.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off for all castbars interrupt", 3, "focus.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off for all castbars interrupt", 4, "boss.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off player target focus castbar interrupt", 1, "player.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off player target focus castbar interrupt", 2, "target.showInterrupt", false, "showInterrupt")
expectSettingAt("turn off player target focus castbar interrupt", 3, "focus.showInterrupt", false, "showInterrupt")
expectSetting("turn off target castbar channel ticks", "general.castbarShowChannelTicks", false, "channelTicks")
expectSetting("turn off target castbar glow", "general.castbarShowGlow", false, "glow")
expectSetting("turn off target castbar spark", "general.castbarShowSpark", false, "spark")
expectSetting("turn off target castbar latency", "general.castbarShowLatency", false, "latency")
expectSetting("turn off target castbar unified direction", "general.castbarUnifiedDirection", false, "unifiedDirection")
expectSetting("move pet frame 12px right", "pet.offsetX", nil, "offsetX", 12)
expectSetting("set player border color to red", "barScope.player.barOutlineColor", nil, "barOutlineColor")
expectColorSetting("set player border color to rgb 255 128 0", "barScope.player.barOutlineColor", 1, 128 / 255, 0, "barOutlineColor")
expectColorSetting("set player border color to r 0.2 g 0.4 b 0.6", "barScope.player.barOutlineColor", 0.2, 0.4, 0.6, "barOutlineColor")
expectColorSetting("set general.customFontColor to red", "general.customFontColor", 1, 0, 0, "customFontColor")
expectColorSetting("set castbar text color to #336699", "general.castbarFontColor", 0x33 / 255, 0x66 / 255, 0x99 / 255, "castbarFontColor")
expectColorSetting("set castbar target name color to red", "general.castbarTargetNameColor", 1, 0, 0, "castbarTargetNameColor")
expectColorSetting("set cast target name color to #336699", "general.castbarTargetNameColor", 0x33 / 255, 0x66 / 255, 0x99 / 255, "castbarTargetNameColor")
expectColorSetting("make mana color blue", "general.powerColorOverrides.MANA", 0, 0, 1, "powerColor")
expectColorSetting("set combo point slot 3 to red", "general.classPowerColorOverrides.COMBO_POINTS_3", 1, 0, 0, "classPowerSlotColor")
setColorContext("general.powerColorOverrides.MANA", { r = 0, g = 0, b = 1 })
expectColorSetting("same for rage", "general.powerColorOverrides.RAGE", 0, 0, 1, "powerColor")
setColorContext("general.powerColorOverrides.MANA", { r = 0, g = 0, b = 1 })
expectColorSetting("same for energy", "general.powerColorOverrides.ENERGY", 0, 0, 1, "powerColor")
setColorContext("general.classPowerColorOverrides.COMBO_POINTS_3", { r = 1, g = 0, b = 0 })
expectColorSetting("same for 4", "general.classPowerColorOverrides.COMBO_POINTS_4", 1, 0, 0, "classPowerSlotColor")
setColorContext("general.classPowerBgColorOverrides.HOLY_POWER", { r = 0, g = 0, b = 0 })
expectColorSetting("same for soul shards", "general.classPowerBgColorOverrides.SOUL_SHARDS", 0, 0, 0, "classPowerBackgroundColor")
expectColorSetting("change the interrupt castbar color to blue", "general.castbarInterruptibleColor", 0, 0, 1, "castbarInterruptibleColor")
expectColorSetting("change the interupt castbar color to blue", "general.castbarInterruptibleColor", 0, 0, 1, "castbarInterruptibleColor")
expectColorSetting("change non interruptible castbar color to blue", "general.castbarNonInterruptibleColor", 0, 0, 1, "castbarNonInterruptibleColor")
expectColorSetting("make interruptible casts green", "general.castbarInterruptibleColor", 0, 1, 0, "castbarInterruptibleColor")
expectColorSetting("make uninterruptible casts red", "general.castbarNonInterruptibleColor", 1, 0, 0, "castbarNonInterruptibleColor")
expectColorSetting("change interrupt feedback color to blue", "general.castbarInterruptFeedbackColor", 0, 0, 1, "castbarInterruptFeedbackColor")
do
    local parsed = A.Parse("change the interrupt color to blue")
    assert(parsed.kind == "ambiguous", "plain interrupt color should ask instead of silently changing feedback color")
    assert(parsed.choices and parsed.choices[1] and parsed.choices[1].setting and parsed.choices[1].setting.key == "general.castbarInterruptibleColor", "interrupt color first choice should be interruptible cast color")
    assert(parsed.choices[2] and parsed.choices[2].setting and parsed.choices[2].setting.key == "general.castbarNonInterruptibleColor", "interrupt color second choice should be non-interruptible cast color")
    assert(parsed.choices[3] and parsed.choices[3].setting and parsed.choices[3].setting.key == "general.castbarInterruptFeedbackColor", "interrupt color third choice should be feedback cast color")
end
expectColorSetting("change raid group border color to blue", "gf_raid.groupBorderColor", 0, 0, 1, "groupBorderColor")
expectColorSetting("change party health bar color to blue", "gf_party.healthBarColor", 0, 0, 1, "healthBarColor")
expectColorSetting("change raid backdrop color to blue", "gf_raid.bgColor", 0, 0, 1, "groupBackdropColor")
expectColorSetting("change mythic raid focus highlight color to blue", "gf_mythicraid.hlFocusColor", 0, 0, 1, "focusHighlightColor")
do
    local parsed = A.Parse("change group frame health color to blue")
    assert(parsed.kind == "ambiguous", "unspecified group-frame health color should ask for Party/Raid/Mythic Raid")
    assert(parsed.choices and #parsed.choices == 3, "group-frame health color should offer the three real group scopes")
    assert(parsed.choices[1].setting and parsed.choices[1].setting.key == "gf_party.healthBarColor", "group-frame health color first choice should be Party")
    assert(parsed.choices[2].setting and parsed.choices[2].setting.key == "gf_raid.healthBarColor", "group-frame health color second choice should be Raid")
    assert(parsed.choices[3].setting and parsed.choices[3].setting.key == "gf_mythicraid.healthBarColor", "group-frame health color third choice should be Mythic Raid")
end
expectSetting("move player portrait 5 right", "player.portraitOffsetX", nil, "portraitOffsetX", 5)
_G.MSUF_DB.player.portraitMode = "LEFT"
expectSetting("move player portrait closer to player unitframe", "player.portraitOffsetX", nil, "portraitOffsetX", 10)
expectSetting("move player portrait farther from player unitframe", "player.portraitOffsetX", nil, "portraitOffsetX", -10)
_G.MSUF_DB.player.portraitMode = "RIGHT"
expectSetting("move player portrait closer to player unitframe", "player.portraitOffsetX", nil, "portraitOffsetX", -10)
_G.MSUF_DB.player.portraitMode = "LEFT"
expectSetting("change player portrait to 2D", "player.portraitRender", "2D", "portraitRender")
expectSetting("change player portrait to class portrait", "player.portraitRender", "CLASS", "portraitRender")
expectSetting("change player portrait to class", "player.portraitRender", "CLASS", "portraitRender")
expectSetting("set player portrait shape to circle", "player.portraitShape", "CIRCLE", "portraitShape")
expectSetting("set player portrait shape to rounded", "player.portraitShape", "ROUNDED", "portraitShape")
expectSetting("set player portrait size to 64", "player.portraitSizeOverride", 64, "portraitSizeOverride")
expectSetting("set player portrait x offset to 7", "player.portraitOffsetX", 7, "portraitOffsetX")
expectSetting("set player portrait y offset to -6", "player.portraitOffsetY", -6, "portraitOffsetY")
expectSetting("set player class portrait style to rondo color", "player.portraitClassStyle", "rondo color", "portraitClassStyle")
expectSetting("set player portrait border to class color", "player.portraitBorderStyle", "CLASS_COLOR", "portraitBorderStyle")
expectSetting("set player portrait border thickness to 6", "player.portraitBorderThickness", 6, "portraitBorderThickness")
expectSetting("turn on player portrait background", "player.portraitBgEnabled", true, "portraitBgEnabled")
expectSetting("turn off player portrait background", "player.portraitBgEnabled", false, "portraitBgEnabled")
expectSetting("turn on player portrait fill border into frame gap", "player.portraitFillBorder", true, "portraitFillBorder")
expectSetting("turn off player portrait fill border", "player.portraitFillBorder", false, "portraitFillBorder")
expectSetting("move player detached power bar right 5", "player.detachedPowerBarOffsetX", nil, "detachedPowerBarOffsetX", 5)
expectSetting("move player raid marker right 3", "player.raidMarkerOffsetX", nil, "raidmarkerOffsetX", 3)
expectSetting("move raid ready check icon up 2", "gf_raid.readyCheckY", nil, "statusIconreadyCheckIconY", 2)
expectSetting("move raid group number right 2", "gf_raid.groupNumberX", nil, "groupNumberX", 2)
expectSettingAt("turn on portraits for all unitframes", 1, "player.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn on portraits for all unitframes", 2, "target.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn on portraits for all unitframes", 7, "boss.portraitMode", "LEFT", "portraitMode")
expectSettingAt("turn off all portraits", 1, "player.portraitMode", "OFF", "portraitMode")
do
    local parsed = A.Parse("turn on portraits for all unitframes")
    assert(parsed.kind == "changes", "all portraits should produce direct changes")
    assert(parsed.bulkSafe == true, "all portrait changes should not require confirmation")
    for i = 1, #(parsed.changes or {}) do
        assert(parsed.changes[i].setting.attribute == "portraitMode", "all portraits routed to non-portrait setting")
    end
end
expectSetting("anchor player frame to cooldownmanager", "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSetting("attach player frame to cooldown manager", "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSetting("anchor target to cooldownmanager", "target.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSetting("put player under cooldownmanager", "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSetting("use cooldownmanager as player anchor", "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSetting("undock target frame", "target.anchorToUnitframe", "GLOBAL", "anchorToUnitframe")
expectSetting("detach target frame", "target.anchorToUnitframe", "GLOBAL", "anchorToUnitframe")
expectSetting("anchor target frame to player frame", "target.anchorToUnitframe", "player", "anchorToUnitframe")
expectAnswer("anchor all frames to cooldownmanager", "too broad to change safely")
expectAnswer("move frames closer to cooldownmanager", "anchor unit frames to Cooldown Manager")
expectAnswer("put frames near cooldownmanager", "anchor party and raid frames to Cooldown Manager")
expectSettingAt("put player and target near cooldownmanager", 1, "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("put player and target near cooldownmanager", 2, "target.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("make player and target close to cooldownmanager", 1, "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("make player and target close to cooldownmanager", 2, "target.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("move player and target closer to cooldownmanager", 1, "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("move player and target closer to cooldownmanager", 2, "target.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectAnswer("open cooldownmanager anchor settings", "external custom anchor target")
expectSetting("put player next to target frame", "player.anchorToUnitframe", "target", "anchorToUnitframe")
expectSetting("put raid frames near cooldownmanager", "gf_raid.customAnchorFrame", "EssentialCooldownViewer", "customAnchorFrame")
expectSetting("undock raid frames", "gf_raid.anchorToFrame", "FREE", "anchorToFrame")
expectSetting("anchor raid frames to CompactRaidFrame1", "gf_raid.customAnchorFrame", "CompactRaidFrame1", "customAnchorFrame")
expectSetting("put raid frames under CompactRaidFrame1", "gf_raid.customAnchorFrame", "CompactRaidFrame1", "customAnchorFrame")
expectSettingAt("anchor unitframes to cooldownmanager", 1, "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("anchor unitframes to cooldownmanager", 7, "boss.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
do
    local parsed = A.Parse("anchor unitframes to cooldownmanager")
    assert(parsed.kind == "changes", "all unitframe cooldown anchor should produce direct changes")
    assert(parsed.bulkSafe == true, "all unitframe cooldown anchor should be bulk safe")
    assert(#(parsed.changes or {}) == 7, "all unitframe cooldown anchor should touch every unitframe")
end
expectSetting("set player name anchor to right", "player.nameTextAnchor", "RIGHT", "nameTextAnchor")
_G.MSUF_DB.player = _G.MSUF_DB.player or {}
_G.MSUF_DB.player.showName = true
expectSetting("move player name to middle", "player.nameTextAnchor", "CENTER", "nameTextAnchor")
expectSetting("move player text to the middle of player unitframe", "player.nameTextAnchor", "CENTER", "nameTextAnchor")
do
    local ctx = A.GetContext()
    ctx.lastChangeBundle = {
        { key = "player.showName", unit = "player", frameType = "unitframe", attribute = "name", value = true },
    }
    ctx.lastSetting = "player.showName"
    ctx.lastUnit = "player"
    ctx.lastFrameType = "unitframe"
    ctx.lastValue = true
end
expectSetting("move it to the middle", "player.nameTextAnchor", "CENTER", "nameTextAnchor")
for key in pairs(parserContext) do parserContext[key] = nil end
_G.MSUF_DB.player.showName = false
expectSettingAt("move player name to middle", 1, "player.showName", true, "name")
expectSettingAt("move player name to middle", 2, "player.nameTextAnchor", "CENTER", "nameTextAnchor")
_G.MSUF_DB.player.showName = true
expectSetting("move player name text 5 right", "player.nameOffsetX", nil, "nameOffsetX", 5)
expectSetting("put player name above the frame", "player.nameOffsetY", nil, "nameOffsetY", 10)
expectSetting("set player name anchor to top", "player.nameOffsetY", nil, "nameOffsetY", 10)
expectSetting("move player unit name label up 2", "player.nameOffsetY", nil, "nameOffsetY", 2)
expectSetting("move player health down 4", "player.hpOffsetY", nil, "hpOffsetY", -4)
expectSetting("move target mana up 2", "target.powerOffsetY", nil, "powerOffsetY", 2)
expectSetting("move party frame name down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
expectSetting("move party frame name text down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
expectSetting("move the party frames name down", "gf_party.nameOffsetY", nil, "nameOffsetY", -10)
expectSetting("move party names up 2", "gf_party.nameOffsetY", nil, "nameOffsetY", 2)
expectSetting("put raid names below the frames", "gf_raid.nameOffsetY", nil, "nameOffsetY", -10)
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
expectSetting("move party power number on the right up", "gf_party.powerTextRightOffsetY", nil, "powerTextRightOffsetY", 10)
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
expectSettingAt("show target health as current and percent", 1, "target.textRight", "CURPERCENT", "hpTextRight")
expectSettingAt("show target health as current and percent", 2, "target.showHP", true, "hpText")
expectSetting("put raid mana percent on the right", "gf_raid.powerTextRight", "PERCENT", "powerTextRight")
expectSetting("show target health percent left", "target.textLeft", "PERCENT", "hpTextLeft")
expectSetting("hide player left hp text", "player.textLeft", "NONE", "hpTextLeft")
expectSetting("clear player hp text left", "player.textLeft", "NONE", "hpTextLeft")
expectSetting("set raid center hp text to percent", "gf_raid.textCenter", "PERCENT", "healthTextCenter")
expectSetting("set party right hp text to deficit", "gf_party.textRight", "DEFICIT", "healthTextRight")
expectSetting("set party power center text to current percent", "gf_party.powerTextCenter", "CURPERCENT", "powerTextCenter")
expectSetting("set target hp text right to current/max", "target.textRight", "CURMAX", "hpTextRight")
expectSetting("turn off player hp text", "player.showHP", false, "hpText")
expectSetting("turn of player hp text", "player.showHP", false, "hpText")
do
    local parsed = A.Parse("turn of player focus hp text")
    assert(parsed.kind == "ambiguous", "player focus hp text should ask which unit instead of changing both")
    assert(type(parsed.choices) == "table" and #parsed.choices == 2, "player focus hp text choices missing")
    assert(parsed.choices[1].setting and parsed.choices[1].setting.key == "player.showHP", "player focus hp text first choice wrong")
    assert(parsed.choices[1].value == false, "player focus hp text first choice wrong value")
    assert(parsed.choices[2].setting and parsed.choices[2].setting.key == "focus.showHP", "player focus hp text second choice wrong")
    assert(parsed.choices[2].value == false, "player focus hp text second choice wrong value")
end
expectSettingAt("remove player power text", 1, "player.powerTextLeft", "NONE", "powerTextLeft")
expectSettingAt("remove player power text", 2, "player.powerTextCenter", "NONE", "powerTextCenter")
expectSettingAt("remove player power text", 3, "player.powerTextRight", "NONE", "powerTextRight")
expectSetting("set player power text right to percent", "player.powerTextRight", "PERCENT", "powerTextRight")
_G.MSUF_DB.target = _G.MSUF_DB.target or {}
_G.MSUF_DB.target.powerTextLeft = "NONE"
_G.MSUF_DB.target.powerTextCenter = "NONE"
_G.MSUF_DB.target.powerTextRight = "CURPERCENT"
expectSetting("set target power text to percent", "target.powerTextRight", "PERCENT", "powerTextRight")
expectSetting("hide target power text", "target.showPowerText", false, "powerText")
do
    local parsed = A.Parse("how do I hide target power text")
    assert(parsed.kind ~= "changes", "how-do-I target power text question must not mutate settings")
end
_G.MSUF_DB.target.powerTextLeft = "CURRENT"
_G.MSUF_DB.target.powerTextCenter = "NONE"
_G.MSUF_DB.target.powerTextRight = "CURPERCENT"
local powerTextChoice = A.Parse("set target power text to percent")
assert(powerTextChoice.kind == "ambiguous", "target power text with two active slots should ask which slot")
assert(#(powerTextChoice.choices or {}) == 2, "target power text should only offer active slots")
assert(powerTextChoice.choices[1].setting.key == "target.powerTextLeft", "target power text first active slot should be left")
assert(powerTextChoice.choices[2].setting.key == "target.powerTextRight", "target power text second active slot should be right")
setTextContext("unitframe", "player", "hp", "left", "player.textLeft", "MAX")
expectSetting("change hp text player to only %", "player.textLeft", "PERCENT", "hpTextLeft")
expectSetting("show only percent on player hp text", "player.textLeft", "PERCENT", "hpTextLeft")
expectSetting("change it to only %", "player.textLeft", "PERCENT", "hpTextLeft")
expectSetting("now make it max hp", "player.textLeft", "MAX", "hpTextLeft")
setFollowupContext("unitframe", "hpTextLeft", "MAX")
expectSetting("do same for target", "target.textLeft", "MAX", "hpTextLeft")
expectSetting("do the same for raid", "gf_raid.textLeft", "MAX", "healthTextLeft")
do
    local setting = assert(A.Registry:GetSetting("player.textLeft"), "missing player.textLeft")
    local ctx = A.GetContext()
    ctx.lastChangeBundle = {
        { key = "player.textLeft", frameType = setting.frameType, unit = setting.unit, attribute = setting.attribute, value = "MAX" },
    }
    expectSetting("move it down 2", "player.hpTextLeftOffsetY", nil, "hpTextLeftOffsetY", -2)
    expectSetting("hide it", "player.textLeft", "NONE", "hpTextLeft")
    expectSetting("make it bigger", "player.hpFontSize", nil, "hpFontSize", 1)
end
expectSetting("set player hp text size to 18", "player.hpFontSize", 18, "hpFontSize")
expectSettingAt("make all text bigger on target", 1, "target.nameFontSize", nil, "nameFontSize", 1)
expectSettingAt("make all text bigger on target", 2, "target.hpFontSize", nil, "hpFontSize", 1)
expectSettingAt("make all text bigger on target", 3, "target.powerFontSize", nil, "powerFontSize", 1)
expectSetting("increase target power text size by 2", "target.powerFontSize", nil, "powerFontSize", 2)
expectSetting("set party power text size to 11", "gf_party.powerFontSize", 11, "powerFontSize")
expectSetting("set raid name text size to 12", "gf_raid.nameFontSize", 12, "nameFontSize")
expectSetting("make raid frame names bigger", "gf_raid.nameFontSize", nil, "nameFontSize", 1)
expectSetting("make raid health text bigger", "gf_raid.hpFontSize", nil, "hpFontSize", 1)
expectSetting("make raid power text smaller", "gf_raid.powerFontSize", nil, "powerFontSize", -1)
expectSetting("make party names smaller", "gf_party.nameFontSize", nil, "nameFontSize", -1)
expectSetting("make target name bigger", "target.nameFontSize", nil, "nameFontSize", 1)
expectSetting("make party health numbers bigger", "gf_party.hpFontSize", nil, "hpFontSize", 1)
expectSetting("make party mana numbers smaller", "gf_party.powerFontSize", nil, "powerFontSize", -1)
expectSetting("show raid health numbers", "gf_raid.showHPText", true, "hpText")
expectSetting("show party power numbers", "gf_party.showPowerText", true, "powerText")
expectSetting("hide raid mana numbers", "gf_raid.showPowerText", false, "powerText")
expectSetting("show target health numbers", "target.showHP", true, "hpText")
expectSetting("hide target mana numbers", "target.showPowerText", false, "powerText")
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
expectSetting("set barScope.gf_party.barTexture to \"Test\"", "barScope.gf_party.barTexture", "Test")
expectSetting("set player alpha to 50", "player.hpBarAlpha", 0.5, "hpBarAlpha")
expectSetting("set raid alpha to 50", "gf_raid.hpBarAlpha", 0.5, "hpBarAlpha")
expectSetting("make party frames more transparent by 10", "gf_party.hpBarAlpha", nil, "hpBarAlpha", -0.1)
MSUF.MSUF2.activeKey = "gf_layout"
MSUF.MSUF2.gfScope = "raid"
expectSetting("set alpha to 60", "gf_raid.hpBarAlpha", 0.6, "hpBarAlpha")
MSUF.MSUF2.activeKey = "home"
expectSetting("increase player width by 5", "player.width", nil, "width", 5)
expectSetting("decrease player name font size by 2", "player.nameFontSize", nil, "nameFontSize", -2)
expectSetting("increase player alpha by 5", "player.hpBarAlpha", nil, "hpBarAlpha", 0.05)
expectSetting("set target range fade alpha to 30", "target.rangeFadeAlpha", 0.3, "rangeFadeAlpha")
expectSetting("set target range fade affects health", "target.rangeFadeLayerMode", "health", "rangeFadeLayerMode")
expectUnknown("turn on player range fade")
expectUnknown("set player range fade alpha to 30")
expectSetting("turn on unitframe dispel overlay", "general.unitDispelOverlayEnabled", true, "unitDispelOverlay")
expectSetting("set unitframe dispel overlay detects any debuff", "general.unitDispelOverlayTrigger", "DISPEL_TYPE", "unitDispelOverlayTrigger")
expectSetting("set unitframe dispel overlay detects dispellable by group", "general.unitDispelOverlayTrigger", "BY_RAID", "unitDispelOverlayTrigger")
expectSetting("set unitframe dispel overlay style top", "general.unitDispelOverlayStyle", "TOP", "unitDispelOverlayStyle")
expectSetting("turn off unitframe dispel overlay current health only", "general.unitDispelOverlayOnHealth", false, "unitDispelOverlayHealthOnly")
expectSetting("set unitframe dispel overlay opacity to 45", "general.unitDispelOverlayAlpha", 0.45, "unitDispelOverlayOpacity")
expectSettingAt("set only target unitframe dispel overlay opacity to 40", 1, "barScope.target.override", true, "override")
expectSettingAt("set only target unitframe dispel overlay opacity to 40", 2, "barScope.target.unitDispelOverlayAlpha", 0.4, "unitDispelOverlayOpacity")
expectSetting("decrease castbar outline thickness by 1", "general.castbarOutlineThickness", nil, "outline", -1)
expectSetting("set castbar text color to red", "general.castbarFontColor", nil, "castbarFontColor")
expectSetting("set target castbar text x offset to 3", "general.castbarTargetTextOffsetX", 3, "textOffsetX")
expectSetting("move target castbar icon right 4", "general.castbarTargetIconOffsetX", nil, "iconOffsetX", 4)
expectSetting("move focus kick icon down 3", "general.focusKickIconOffsetY", nil, "focusKickOffsetY", -3)
expectSetting("move focus kick tracker left 10", "general.focusKickIconOffsetX", nil, "focusKickOffsetX", -10)
expectSettingAt("make focus kick tracker bigger", 1, "general.focusKickIconWidth", nil, "focusKickWidth", 1)
expectSettingAt("make focus kick tracker bigger", 2, "general.focusKickIconHeight", nil, "focusKickHeight", 1)
expectSetting("turn on show interrupt ready on target castbar", "general.kickReadyShowTarget", true, "kickReadyTarget")
expectSetting("turn on show interrupt ready on focus castbar", "general.kickReadyShowFocus", true, "kickReadyFocus")
expectSetting("turn on show interrupt ready on boss castbars", "general.kickReadyShowBoss", true, "kickReadyBoss")
expectSetting("set interrupt ready indicator size to 20", "general.kickReadySize", 20, "kickReadySize")
expectSetting("set interrupt ready indicator anchor to right", "general.kickReadyAnchor", "RIGHT", "kickReadyAnchor")
expectSetting("put kick ready indicator left", "general.kickReadyAnchor", "LEFT", "kickReadyAnchor")
expectSetting("move kick ready indicator down 3", "general.kickReadyOffsetY", nil, "kickReadyOffsetY", -3)
expectSetting("make kick ready icon bigger", "general.kickReadySize", nil, "kickReadySize", 1)
expectSetting("turn off interrupt for target", "target.showInterrupt", false, "showInterrupt")
expectSetting("make unitframe dark mode a bit lighter", "general.darkBarGray", nil, "darkModeBarColor", 0.03)
expectSetting("make unitframe dark mode super dark", "general.darkBarGray", 0.01, "darkModeBarColor")
expectSetting("set unitframe dark mode to 20", "general.darkBarGray", 0.2, "darkModeBarColor")
expectSetting("make unitframe dark mode 20 percent", "general.darkBarGray", 0.2, "darkModeBarColor")
expectSetting("make unitframe dark mode darker by 5", "general.darkBarGray", nil, "darkModeBarColor", -0.05)
_G.MSUF_DB.player = _G.MSUF_DB.player or {}
_G.MSUF_DB.player.height = 40
expectSetting("turn on class resources", "bars.showClassPower", true, "enabled")
expectSetting("turn off class resources", "bars.showClassPower", false, "enabled")
expectSetting("hide combo points", "bars.showClassPower", false, "enabled")
do
    local cases = {
        { "turn on class resources", true },
        { "turn off class resources", false },
        { "hide combo points", false },
        { "class resources on", true },
        { "class resources off", false },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource root toggle should produce a concrete setting change")
        assert(change and change.setting and change.setting.key == "bars.showClassPower", cases[i][1] .. ": registry exact alias picked the wrong Class Resource root setting")
        assert(change.value == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource root value")
    end
    local search = A.Parse("show me class resource settings")
    assert(search and search.kind ~= "changes", "show me class resource settings must not toggle Class Resources")
end
expectSetting("move class resource down 5", "bars.classPowerOffsetY", nil, "offsetY", -5)
do
    local moveShortcut = A._ParseClassPowerMoveShortcut
    A._ParseClassPowerMoveShortcut = nil
    local cases = {
        { "move class resource down 5", "bars.classPowerOffsetY", -5 },
        { "move class resource up", "bars.classPowerOffsetY", 10 },
        { "move combo points left 7", "bars.classPowerOffsetX", -7 },
        { "shift combo points right", "bars.classPowerOffsetX", 10 },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource movement should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource movement setting")
        assert(change.relativeDelta == cases[i][3], cases[i][1] .. ": registry exact alias picked the wrong Class Resource movement delta")
    end
    A._ParseClassPowerMoveShortcut = moveShortcut
end
expectSettingAt("move class resource under player frame", 1, "bars.classPowerAnchorToCooldown", false, "anchorToCooldown")
expectSettingAt("move class resource under player frame", 2, "bars.classPowerWidthMode", "player", "widthMode")
expectSettingAt("move class resource under player frame", 3, "bars.classPowerOffsetX", 0, "offsetX")
expectSettingAt("move class resource under player frame", 4, "bars.classPowerOffsetY", -50, "offsetY")
expectSettingAt("put combo points under player frame", 1, "bars.classPowerAnchorToCooldown", false, "anchorToCooldown")
expectSettingAt("put combo points under player frame", 4, "bars.classPowerOffsetY", -50, "offsetY")
expectSettingAt("move combo points above player frame", 4, "bars.classPowerOffsetY", 10, "offsetY")
do
    local placementShortcut = A._ParseClassPowerPlacementShortcut
    A._ParseClassPowerPlacementShortcut = nil
    local cases = {
        { "move class resource under player frame", -50 },
        { "put combo points under player frame", -50 },
        { "move combo points above player frame", 10 },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource placement should resolve through registry exact aliases without the specialty shortcut")
        assert(parsed.changes and #parsed.changes >= 2, cases[i][1] .. ": Class Resource fallback should at least detach from cooldowns and use Player width")
        assert(parsed.changes[1].setting and parsed.changes[1].setting.key == "bars.classPowerAnchorToCooldown" and parsed.changes[1].value == false, cases[i][1] .. ": registry placement picked the wrong anchor change")
        assert(parsed.changes[2].setting and parsed.changes[2].setting.key == "bars.classPowerWidthMode" and parsed.changes[2].value == "player", cases[i][1] .. ": registry placement picked the wrong width mode change")
    end
    A._ParseClassPowerPlacementShortcut = placementShortcut
end
expectSetting("anchor class resources to essential cooldownmanager", "bars.classPowerAnchorToCooldown", true, "anchorToCooldown")
expectSetting("anchor class resource player frame", "bars.classPowerAnchorToCooldown", false, "anchorToCooldown")
expectSetting("detach combo points from cooldown manager", "bars.classPowerAnchorToCooldown", false, "anchorToCooldown")
expectSettingAt("anchor unitframes to cooldownmanager", 1, "player.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSettingAt("anchor unitframes to cooldownmanager", 7, "boss.anchorToUnitframe", "EssentialCooldownViewer", "anchorToUnitframe")
expectSetting("move class resource text right 5", "bars.classPowerTextOffsetX", nil, "textOffsetX", 5)
expectSetting("make combo points bigger", "bars.classPowerHeight", nil, "height", 1)
expectSetting("make combo points smaller", "bars.classPowerHeight", nil, "height", -1)
do
    local sizeShortcut = A._ParseClassPowerSizeShortcut
    A._ParseClassPowerSizeShortcut = nil
    local cases = {
        { "make combo points bigger", "bars.classPowerHeight", nil, 1 },
        { "make combo points smaller", "bars.classPowerHeight", nil, -1 },
        { "set class resource height to 6", "bars.classPowerHeight", 6, nil },
        { "set class resource size to 7", "bars.classPowerHeight", 7, nil },
        { "make combo points wider", "bars.classPowerWidth", nil, 10 },
        { "make combo points narrower", "bars.classPowerWidth", nil, -10 },
        { "set class resource width to 120", "bars.classPowerWidth", 120, nil },
        { "set class resources width to 120", "bars.classPowerWidth", 120, nil },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource size should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource size setting")
        assert(change.value == cases[i][3], cases[i][1] .. ": registry exact alias picked the wrong Class Resource size value")
        assert(change.relativeDelta == cases[i][4], cases[i][1] .. ": registry exact alias picked the wrong Class Resource size delta")
    end
    A._ParseClassPowerSizeShortcut = sizeShortcut
end
expectSetting("make class resource text bigger", "bars.classPowerFontSize", nil, "fontSize", 1)
do
    local textSizeShortcut = A._ParseClassPowerTextSizeShortcut
    A._ParseClassPowerTextSizeShortcut = nil
    local cases = {
        { "make class resource text bigger", nil, 1 },
        { "make class resource text smaller", nil, -1 },
        { "set class resource text size to 20", 20, nil },
        { "set combo point numbers size to 18", 18, nil },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource text size should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == "bars.classPowerFontSize", cases[i][1] .. ": registry exact alias picked the wrong Class Resource text-size setting")
        assert(change.value == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource text-size value")
        assert(change.relativeDelta == cases[i][3], cases[i][1] .. ": registry exact alias picked the wrong Class Resource text-size delta")
    end
    A._ParseClassPowerTextSizeShortcut = textSizeShortcut
end
expectSetting("make class resource fill right to left", "bars.classPowerFillReverse", true, "reverseFill")
expectSetting("make class resource fill backwards", "bars.classPowerFillReverse", true, "reverseFill")
expectSetting("reverse class resource fill", "bars.classPowerFillReverse", true, "reverseFill")
expectSetting("make class resource fill normal direction", "bars.classPowerFillReverse", false, "reverseFill")
expectSetting("make class power fill left to right", "bars.classPowerFillReverse", false, "reverseFill")
expectSetting("turn off class resource reverse fill", "bars.classPowerFillReverse", false, "reverseFill")
do
    local fillShortcut = A._ParseClassPowerFillDirectionShortcut
    A._ParseClassPowerFillDirectionShortcut = nil
    local cases = {
        { "make class resource fill right to left", true },
        { "make class resource fill backwards", true },
        { "reverse class resource fill", true },
        { "make class resource fill normal direction", false },
        { "make class power fill left to right", false },
        { "turn off class resource reverse fill", false },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource fill direction should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == "bars.classPowerFillReverse", cases[i][1] .. ": registry exact alias picked the wrong Class Resource fill setting")
        assert(change.value == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource fill value")
    end
    A._ParseClassPowerFillDirectionShortcut = fillShortcut
end
expectSettingAt("show class resources as text", 1, "bars.showClassPower", true, "enabled")
expectSettingAt("show class resources as text", 2, "bars.classPowerShowText", true, "text")
expectSettingAt("show combo point numbers", 1, "bars.showClassPower", true, "enabled")
expectSettingAt("show combo point numbers", 2, "bars.classPowerShowText", true, "text")
expectSettingAt("show resource numbers", 2, "bars.classPowerShowText", true, "text")
expectSettingAt("show class resources as pips", 2, "bars.classPowerShowText", false, "text")
expectSetting("hide combo point numbers", "bars.classPowerShowText", false, "text")
expectColorSetting("make combo points blue", "general.classPowerColorOverrides.COMBO_POINTS", 0, 0, 1, "classPowerColor")
expectColorSetting("make holy power background black", "general.classPowerBgColorOverrides.HOLY_POWER", 0, 0, 0, "classPowerBackgroundColor")
do
    local colorShortcut = A._ParseClassPowerColorShortcut
    A._ParseClassPowerColorShortcut = nil
    local cases = {
        { "make combo points blue", "general.classPowerColorOverrides.COMBO_POINTS", 0, 0, 1, "classPowerColor" },
        { "set combo point slot 3 to red", "general.classPowerColorOverrides.COMBO_POINTS_3", 1, 0, 0, "classPowerSlotColor" },
        { "make holy power background black", "general.classPowerBgColorOverrides.HOLY_POWER", 0, 0, 0, "classPowerBackgroundColor" },
        { "set soul shards background color to black", "general.classPowerBgColorOverrides.SOUL_SHARDS", 0, 0, 0, "classPowerBackgroundColor" },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        local value = change and change.value
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource color should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource color setting")
        assert(change.setting.attribute == cases[i][6], cases[i][1] .. ": registry exact alias picked the wrong Class Resource color attribute")
        assert(value and value.r == cases[i][3] and value.g == cases[i][4] and value.b == cases[i][5], cases[i][1] .. ": registry exact alias picked the wrong Class Resource color value")
    end
    A._ParseClassPowerColorShortcut = colorShortcut
end
expectSetting("increase class resource spacing", "bars.classPowerGap", nil, "gap", 1)
expectSetting("make combo point gaps bigger", "bars.classPowerGap", nil, "gap", 1)
do
    local gapShortcut = A._ParseClassPowerGapShortcut
    A._ParseClassPowerGapShortcut = nil
    local cases = {
        { "increase class resource spacing", 1 },
        { "make combo point gaps bigger", 1 },
        { "make combo points spacing smaller", -1 },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource gap should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == "bars.classPowerGap", cases[i][1] .. ": registry exact alias picked the wrong Class Resource gap setting")
        assert(change.relativeDelta == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource gap delta")
    end
    A._ParseClassPowerGapShortcut = gapShortcut
end
expectSetting("make combo point separators wider", "bars.classPowerTickWidth", nil, "separator", 1)
do
    local separatorShortcut = A._ParseClassPowerSeparatorShortcut
    A._ParseClassPowerSeparatorShortcut = nil
    local cases = {
        { "make combo point separators wider", nil, 1 },
        { "make class resource separators smaller", nil, -1 },
        { "set class resource separator width to 2", 2, nil },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource separator should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == "bars.classPowerTickWidth", cases[i][1] .. ": registry exact alias picked the wrong Class Resource separator setting")
        assert(change.value == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource separator value")
        assert(change.relativeDelta == cases[i][3], cases[i][1] .. ": registry exact alias picked the wrong Class Resource separator delta")
    end
    A._ParseClassPowerSeparatorShortcut = separatorShortcut
end
expectSetting("turn off class resource background", "bars.classPowerBgAlpha", 0, "backgroundAlpha")
expectSetting("show class resource background", "bars.classPowerBgAlpha", 0.3, "backgroundAlpha")
expectSetting("set class resource background opacity to 40", "bars.classPowerBgAlpha", 0.4, "backgroundAlpha")
expectSetting("increase class resource background opacity", "bars.classPowerBgAlpha", nil, "backgroundAlpha", 0.05)
do
    local backgroundShortcut = A._ParseClassPowerBackgroundShortcut
    A._ParseClassPowerBackgroundShortcut = nil
    local cases = {
        { "turn off class resource background", 0, nil },
        { "show class resource background", 0.3, nil },
        { "set class resource background opacity to 40", 0.4, nil },
        { "increase class resource background opacity", nil, 0.05 },
        { "make combo point background smaller", nil, -0.05 },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource background should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == "bars.classPowerBgAlpha", cases[i][1] .. ": registry exact alias picked the wrong Class Resource background setting")
        assert(change.value == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource background value")
        assert(change.relativeDelta == cases[i][3], cases[i][1] .. ": registry exact alias picked the wrong Class Resource background delta")
    end
    A._ParseClassPowerBackgroundShortcut = backgroundShortcut
end
expectSetting("set class resource width mode to custom", "bars.classPowerWidthMode", "custom", "widthMode")
expectSetting("set class resources to player width", "bars.classPowerWidthMode", "player", "widthMode")
expectSetting("set class resources width to essential cooldowns", "bars.classPowerWidthMode", "cooldown", "widthMode")
do
    local widthModeShortcut = A._ParseClassPowerWidthModeShortcut
    A._ParseClassPowerWidthModeShortcut = nil
    local cases = {
        { "set class resource width mode to custom", "custom" },
        { "set class resources to player width", "player" },
        { "set class resources width to essential cooldowns", "cooldown" },
        { "set class resource width to utility cooldowns", "utility" },
        { "set class resource width to tracked buffs", "tracked_buffs" },
        { "set class resource auto fit pips", "auto_pips" },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change
        for _, candidate in ipairs(parsed and parsed.changes or {}) do
            if candidate.setting and candidate.setting.key == "bars.classPowerWidthMode" then change = candidate; break end
        end
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource width mode should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == "bars.classPowerWidthMode", cases[i][1] .. ": registry exact alias picked the wrong Class Resource width setting")
        assert(change.value == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource width mode")
    end
    A._ParseClassPowerWidthModeShortcut = widthModeShortcut
end
expectSetting("set class resource preview resource to mage arcane", "menu.classPowerPreviewResource", "mage_arcane", "classPowerPreviewResource")
expectSetting("preview class resource mage arcane", "menu.classPowerPreviewResource", "mage_arcane", "classPowerPreviewResource")
expectSetting("show mage arcane class resource preview", "menu.classPowerPreviewResource", "mage_arcane", "classPowerPreviewResource")
expectSetting("preview resource as rogue combo", "menu.classPowerPreviewResource", "rogue_combo", "classPowerPreviewResource")
expectSetting("preview combo points", "menu.classPowerPreviewResource", "rogue_combo", "classPowerPreviewResource")
expectSetting("preview monk class resources", "menu.classPowerPreviewResource", "monk_windwalker", "classPowerPreviewResource")
expectSetting("turn off class resource prediction", "bars.classPowerShowPrediction", false, "prediction")
expectSetting("hide class resource out of combat", "bars.classPowerHideOOC", true, "hideOOC")
expectSetting("show class resource out of combat", "bars.classPowerHideOOC", false, "hideOOC")
expectSetting("dont hide class resource when empty", "bars.classPowerHideWhenEmpty", false, "hideEmpty")
expectSetting("show combo points when full", "bars.classPowerHideWhenFull", false, "hideFull")
do
    local visibilityShortcut = A._ParseClassPowerVisibilityShortcut
    A._ParseClassPowerVisibilityShortcut = nil
    local cases = {
        { "hide class resource out of combat", "bars.classPowerHideOOC", true },
        { "show class resource out of combat", "bars.classPowerHideOOC", false },
        { "dont hide class resource when empty", "bars.classPowerHideWhenEmpty", false },
        { "hide combo points when empty", "bars.classPowerHideWhenEmpty", true },
        { "show combo points when full", "bars.classPowerHideWhenFull", false },
        { "hide class resource when full", "bars.classPowerHideWhenFull", true },
    }
    for i = 1, #cases do
        local parsed = A.Parse(cases[i][1])
        local change = parsed and parsed.changes and parsed.changes[1]
        assert(parsed and parsed.kind == "changes", cases[i][1] .. ": Class Resource visibility should resolve through registry exact aliases without the specialty shortcut")
        assert(change and change.setting and change.setting.key == cases[i][2], cases[i][1] .. ": registry exact alias picked the wrong Class Resource visibility setting")
        assert(change.value == cases[i][3], cases[i][1] .. ": registry exact alias picked the wrong Class Resource visibility value")
    end
    A._ParseClassPowerVisibilityShortcut = visibilityShortcut
end
expectSetting("set class resource combo colors to ramp", "bars.classPowerSlotColorModes.COMBO_POINTS", "ramp", "classPowerSlotColorMode")
expectSetting("set combo point slot mode to custom", "bars.classPowerSlotColorModes.COMBO_POINTS", "custom", "classPowerSlotColorMode")
expectAction("reset combo point colors", "reset_class_power_combo_slot_colors")
expectActionArg("reset holy power background color", "reset_class_power_color_token", "token", "HOLY_POWER")
expectActionArg("reset holy power background color", "reset_class_power_color_token", "background", true)
expectSetting("set alt mana height to 12", "bars.altManaHeight", 12, "height")
expectSetting("turn on combat timer", "gameplay.enableCombatTimer", true, "enabled")
expectSetting("set combat timer size to 32", "gameplay.combatFontSize", 32, "fontSize")
expectSetting("move combat timer down 10", "gameplay.combatOffsetY", nil, "offsetY", -10)
expectSetting("set combat timer x offset to 12", "gameplay.combatOffsetX", 12, "offsetX")
expectSetting("set combat timer anchor to player", "gameplay.combatTimerAnchor", "player", "anchor")
expectSetting("turn on combat timer click through", "gameplay.combatTimerClickThrough", true, "clickThrough")
expectSetting("lock combat timer", "gameplay.lockCombatTimer", true, "locked")
expectSetting("unlock combat timer", "gameplay.lockCombatTimer", false, "locked")
expectSetting("make combat timer click through", "gameplay.combatTimerClickThrough", true, "clickThrough")
expectSetting("make combat timer clickable", "gameplay.combatTimerClickThrough", false, "clickThrough")
expectSetting("turn on combat enter leave text", "gameplay.enableCombatStateText", true, "enabled")
expectSetting("set combat enter leave text size to 28", "gameplay.combatStateFontSize", 28, "fontSize")
expectSetting("set combat state duration to 2.5", "gameplay.combatStateDuration", 2.5, "duration")
expectSetting("move combat enter leave text up 8", "gameplay.combatStateOffsetY", nil, "offsetY", 8)
expectSetting("set combat enter text to Pulling", "gameplay.combatStateEnterText", "Pulling", "enterText")
expectSetting("turn on gameplay.combatStateColorSync", "gameplay.combatStateColorSync", true, "combatStateColorSync")
expectSetting("sync combat state colors", "gameplay.combatStateColorSync", true, "combatStateColorSync")
expectSetting("turn on sync combat state colors", "gameplay.combatStateColorSync", true, "combatStateColorSync")
expectSetting("turn off combat state color sync", "gameplay.combatStateColorSync", false, "combatStateColorSync")
expectSetting("turn on totem frame", "gameplay.enablePlayerTotems", true, "enabled")
expectSetting("set totem frame icon size to 32", "gameplay.playerTotemsIconSize", 32, "size")
expectSetting("move totem frame right 6", "gameplay.playerTotemsOffsetX", nil, "offsetX", 6)
expectSetting("move totem icons right 6", "gameplay.playerTotemsOffsetX", nil, "offsetX", 6)
expectSetting("make totem icons bigger", "gameplay.playerTotemsIconSize", nil, "size", 1)
expectSetting("set totem frame from anchor to top left", "gameplay.playerTotemsAnchorFrom", "TOPLEFT", "anchorFrom")
expectSetting("set totem frame to anchor to bottom left", "gameplay.playerTotemsAnchorTo", "BOTTOMLEFT", "anchorTo")
_G.MSUF_DB.player = _G.MSUF_DB.player or {}
_G.MSUF_DB.player.offsetX = -256
_G.MSUF_DB.player.offsetY = -180
_G.MSUF_DB.player.width = 275
_G.MSUF_DB.player.height = 40
_G.MSUF_DB.target = _G.MSUF_DB.target or {}
_G.MSUF_DB.target.offsetX = -9
_G.MSUF_DB.target.offsetY = 9
_G.MSUF_DB.target.width = 275
_G.MSUF_DB.target.height = 40
_G.MSUF_DB.focus = _G.MSUF_DB.focus or {}
_G.MSUF_DB.focus.anchorToUnitframe = "player"
_G.MSUF_DB.focus.offsetX = 20
_G.MSUF_DB.focus.offsetY = -60
_G.MSUF_DB.focus.width = 250
_G.MSUF_DB.focus.height = 40
_G.MSUF_DB.boss = _G.MSUF_DB.boss or {}
_G.MSUF_DB.boss.offsetX = 0
_G.MSUF_DB.boss.offsetY = 160
_G.MSUF_DB.boss.width = 250
_G.MSUF_DB.boss.height = 40
_G.MSUF_DB.gf_party = _G.MSUF_DB.gf_party or {}
_G.MSUF_DB.gf_party.offsetX = 100
_G.MSUF_DB.gf_party.offsetY = 50
_G.MSUF_DB.gf_party.width = 120
_G.MSUF_DB.gf_party.height = 40
expectSettingAt("move combat timer middle of player frame", 1, "gameplay.combatTimerAnchor", "player", "anchor")
expectSettingAt("move combat timer middle of player frame", 2, "gameplay.combatOffsetX", 0, "offsetX")
expectSettingAt("move combat timer middle of player frame", 3, "gameplay.combatOffsetY", 0, "offsetY")
expectSettingAt("move combat timer middle of boss frame", 1, "gameplay.combatTimerAnchor", "none", "anchor")
expectSettingAt("move combat timer middle of boss frame", 2, "gameplay.combatOffsetX", 0, "offsetX")
expectSettingAt("move combat timer middle of boss frame", 3, "gameplay.combatOffsetY", 160, "offsetY")
expectSetting("turn on combat crosshair", "gameplay.enableCombatCrosshair", true, "enabled")
expectSetting("set crosshair size to 44", "gameplay.crosshairSize", 44, "size")
expectSetting("make crosshair thicker by 2", "gameplay.crosshairThickness", nil, "thickness", 2)
expectSetting("turn on crosshair range color", "gameplay.enableCombatCrosshairMeleeRangeColor", true, "rangeColor")
expectSetting("turn on crosshair spell per spec", "gameplay.meleeSpellPerSpec", true, "perSpec")
expectActionArg("set crosshair spell to 12345", "set_crosshair_melee_spell", "value", "12345")
expectSetting("set gameplay.nameplateMeleeSpellID to 499999", "gameplay.nameplateMeleeSpellID", 499999, "spellID")
expectSetting("set nameplate melee spell id to 12345", "gameplay.nameplateMeleeSpellID", 12345, "spellID")
expectSetting("set melee nameplate spell id to 12345", "gameplay.nameplateMeleeSpellID", 12345, "spellID")
expectUnknown("move crosshair down 5")
MSUF.MSUF2.activeKey = "gameplay"
expectSetting("turn on timer", "gameplay.enableCombatTimer", true, "enabled")
expectSetting("move timer down 5", "gameplay.combatOffsetY", nil, "offsetY", -5)
expectSetting("set timer anchor to target", "gameplay.combatTimerAnchor", "target", "anchor")
expectSetting("set crosshair thickness to 4", "gameplay.crosshairThickness", 4, "thickness")
MSUF.MSUF2.activeKey = "home"
expectSetting("turn on class color mode for raidframe", "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSetting("raidframe class color", "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSetting("make party frames use class colors", "gf_party.gfBarMode", "CLASS", "groupBarMode")
expectSetting("make raid frames colored by class", "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSetting("make party frames use global colors", "gf_party.gfBarMode", "GLOBAL", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 1, "gf_party.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 2, "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("turn on class color mode for group frames", 3, "gf_mythicraid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("group frames class color", 1, "gf_party.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("group frames class color", 2, "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("group frames class color", 3, "gf_mythicraid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("group frames global colors", 1, "gf_party.gfBarMode", "GLOBAL", "groupBarMode")
expectSettingAt("group frames global colors", 2, "gf_raid.gfBarMode", "GLOBAL", "groupBarMode")
expectSettingAt("group frames global colors", 3, "gf_mythicraid.gfBarMode", "GLOBAL", "groupBarMode")
expectSettingAt("make all group frames class colored", 1, "gf_party.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("make all group frames class colored", 2, "gf_raid.gfBarMode", "CLASS", "groupBarMode")
expectSettingAt("make all group frames class colored", 3, "gf_mythicraid.gfBarMode", "CLASS", "groupBarMode")
expectSetting("set raid anchor to target", "gf_raid.anchorToFrame", "target", "anchorToFrame")
expectSetting("set raid frames to grow right", "gf_raid.growth", "RIGHT", "growth")
expectSetting("make raid groups grow right then down", "gf_raid.growth", "RIGHT", "growth")
expectSetting("make party grow down then right", "gf_party.growth", "DOWN", "growth")
do
    local oldGroupGrowth = A.Parser.ParseGroupGrowthDirectionShortcut
    A.Parser.ParseGroupGrowthDirectionShortcut = function() error("legacy group growth shortcut should not be in the live parse path") end
    local parsed = A.Parse("make party grow down then right")
    assert(parsed and parsed.kind == "changes", "group growth should produce a concrete setting change")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_party.growth", "group growth registry exact alias picked the wrong setting")
    assert(parsed.changes[1].value == "DOWN", "group growth registry exact alias picked the wrong value")
    parsed = A.Parse("set group frames to grow right")
    assert(parsed and parsed.kind == "changes", "bulk group growth should produce concrete setting changes")
    assert(#(parsed.changes or {}) == 3, "bulk group growth should update all three group-frame scopes")
    assert(parsed.changes[1].setting.key == "gf_party.growth" and parsed.changes[1].value == "RIGHT", "bulk group growth picked the wrong party value")
    assert(parsed.changes[2].setting.key == "gf_raid.growth" and parsed.changes[2].value == "RIGHT", "bulk group growth picked the wrong raid value")
    assert(parsed.changes[3].setting.key == "gf_mythicraid.growth" and parsed.changes[3].value == "RIGHT", "bulk group growth picked the wrong mythic raid value")
    A.Parser.ParseGroupGrowthDirectionShortcut = oldGroupGrowth
end
expectSetting("set raid scale to 90", "gf_raid.frameScaleManual", 90, "frameScaleManual")
expectSetting("set raid scale at 10 to 95", "gf_raid.scaleAt10", 95, "scaleAt10")
expectSetting("set raid 11-20 player scale to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("scale raid frames for 20 people to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("scale raid frames when there are 18 raiders to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("scale raid frames when there is 1 player to 100", "gf_raid.scaleAt10", 100, "scaleAt10")
expectSetting("set raid scale for 20 player group to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("can you change the scaling of the raid frame when there are 20 players in it to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("make raid scale 80 when we are 20", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("set raid scale to 80 if we have 20", "gf_raid.scaleAt20", 80, "scaleAt20")
expectSetting("make raid frames smaller if we have 20", "gf_raid.scaleAt20", nil, "scaleAt20", -5)
expectAnswer("can you change the scaling of the raid frame when there are 20 players in", "Group frame scaling breakpoints")
expectAnswer("can you change the scaling of the raid frame when there are 20 players in", "set raid scale for 20 players to 80")
expectAnswer("how do i scale raid at 20 players", "set raid scale for 20 players to 80")
expectSetting("make party frames closer together", "gf_party.spacing", nil, "spacing", -1)
expectSetting("add more space between party frames", "gf_party.spacing", nil, "spacing", 1)
expectSetting("spread raid frames apart by 3", "gf_raid.spacing", nil, "spacing", 3)
expectSetting("make raid group spacing tighter", "gf_raid.spacing", nil, "spacing", -1)
expectSetting("make raid frames closer vertically", "gf_raid.spacing", nil, "spacing", -1)
expectAnySetting("when there are 20 people set raid frame scale to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectAnySetting("when there are 5 people set raid frame scale to 90", "gf_raid.scaleAt10", 90, "scaleAt10")
expectAnySetting("when there are 15 people set raid frame scale to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectAnySetting("make raid frames smaller when 20 people", "gf_raid.scaleAt20", nil, "scaleAt20", -5)
expectAnySetting("make raid frames bigger when 20 people", "gf_raid.scaleAt20", nil, "scaleAt20", 5)
expectAnySetting("lower raid scale for 15 players by 10", "gf_raid.scaleAt20", nil, "scaleAt20", -10)
expectAnySetting("change raid frame scale for a 15 player raid to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectAnySetting("set raid frame scaling for 15 man raid to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectAnySetting("set raid scaling for a 15-man raid to 80", "gf_raid.scaleAt20", 80, "scaleAt20")
expectAnySetting("scale raid frames for 23 players to 75", "gf_raid.scaleAt25", 75, "scaleAt25")
expectAnySetting("set raid scaling for twenty players to eighty", "gf_raid.scaleAt20", 80, "scaleAt20")
expectAnySetting("set raid scale for twenty-five players to seventy five", "gf_raid.scaleAt25", 75, "scaleAt25")
expectSetting("make raid frames smaller when twenty people", "gf_raid.scaleAt20", nil, "scaleAt20", -5)
expectSetting("scale raid frames for 30 players to 70", "gf_raid.scaleOver25", 70, "scaleOver25")
expectSetting("scale raid frames for more than 25 players to 70", "gf_raid.scaleOver25", 70, "scaleOver25")
expectSetting("set raid scale 25+ players to 70", "gf_raid.scaleOver25", 70, "scaleOver25")
expectSetting("set raid frames to 70 percent in full raid", "gf_raid.scaleOver25", 70, "scaleOver25")
expectSetting("when the raid is full make raid frames 70 percent", "gf_raid.scaleOver25", 70, "scaleOver25")
expectSetting("make raid frames smaller in full raid", "gf_raid.scaleOver25", nil, "scaleOver25", -5)
expectSetting("make raid smaller when full", "gf_raid.scaleOver25", nil, "scaleOver25", -5)
expectSetting("make raid frames bigger in large raid", "gf_raid.scaleOver25", nil, "scaleOver25", 5)
expectSetting("make raid frames normal size for small raid", "gf_raid.scaleAt10", 100, "scaleAt10")
expectSetting("make party frames smaller in five man group", "gf_party.scaleAt10", nil, "scaleAt10", -5)
expectSetting("make raid bigger with 18 raiders", "gf_raid.scaleAt20", nil, "scaleAt20", 5)
expectSetting("set mythic raid scale for 30 raiders to 60", "gf_mythicraid.scaleOver25", 60, "scaleOver25")
expectSetting("set mythic raid scale for thirty raiders to sixty", "gf_mythicraid.scaleOver25", 60, "scaleOver25")
expectSetting("increase raid scale at 10 by 5", "gf_raid.scaleAt10", nil, "scaleAt10", 5)
expectSetting("scale raid for 10m to 95", "gf_raid.scaleAt10", 95, "scaleAt10")
expectSetting("increase raid scale for 20m by 5", "gf_raid.scaleAt20", nil, "scaleAt20", 5)
expectSetting("set raid scaling to auto", "gf_raid.frameScaleMode", "auto", "frameScaleMode")
expectSetting("enable automatic raid scaling", "gf_raid.frameScaleMode", "auto", "frameScaleMode")
expectSetting("make raid frames scale by player count", "gf_raid.frameScaleMode", "auto", "frameScaleMode")
expectSetting("make raid frames scale based on raid size", "gf_raid.frameScaleMode", "auto", "frameScaleMode")
expectSetting("disable raid frame scaling", "gf_raid.frameScaleEnabled", false, "frameScaleEnabled")
expectSetting("turn on gf_party.frameScaleEnabled", "gf_party.frameScaleEnabled", true, "frameScaleEnabled")
expectSetting("turn on party frame scaling", "gf_party.frameScaleEnabled", true, "frameScaleEnabled")
expectSetting("turn on raid frame scaling", "gf_raid.frameScaleEnabled", true, "frameScaleEnabled")
expectSetting("turn on mythic raid frame scaling", "gf_mythicraid.frameScaleEnabled", true, "frameScaleEnabled")
expectSetting("turn on raid frame scaling mode", "gf_raid.frameScaleMode", "manual", "frameScaleMode")
expectSetting("turn off raid frame scaling mode", "gf_raid.frameScaleMode", "off", "frameScaleMode")
expectSetting("sort raid frames by role", "gf_raid.sortMode", "ROLE", "sortMode")
expectSetting("turn on party sort by role", "gf_party.sortByRole", true, "sortByRole")
expectSetting("sort party by name", "gf_party.sortMode", "NAME", "sortMode")
expectSettingAt("put tanks first in raid frames", 1, "gf_raid.sortMode", "ROLE", "sortMode")
expectSettingAt("put tanks first in raid frames", 2, "gf_raid.roleOrder", "TANK,HEALER,DAMAGER", "roleOrder")
expectSetting("put raid groups first by group then role", "gf_raid.sortMode", "GROUP_ROLE", "sortMode")
expectSetting("put myself first in raid role sorting", "gf_raid.playerFirstInRole", true, "playerFirstInRole")
expectSetting("sort raid with tanks at top", "gf_raid.sortMode", "ROLE", "sortMode")
expectSettingAt("sort raid with tanks at top", 2, "gf_raid.roleOrder", "TANK,HEALER,DAMAGER", "roleOrder")
expectSetting("sort raid groups then roles", "gf_raid.sortMode", "GROUP_ROLE", "sortMode")
expectSetting("put myself at the top of raid role sorting", "gf_raid.playerFirstInRole", true, "playerFirstInRole")
expectSetting("turn on party hide name on dead or offline", "gf_party.hideNameOnDeadOffline", true, "hideNameOnDeadOffline")
expectSetting("turn off party hide name on dead or offline", "gf_party.hideNameOnDeadOffline", false, "hideNameOnDeadOffline")
expectSetting("turn on party reverse hp text", "gf_party.hpTextReverse", true, "healthTextReverse")
expectSetting("make raid frames fill backwards", "gf_raid.reverseFill", true, "reverseFill")
expectSetting("make raid frames fill right to left", "gf_raid.reverseFill", true, "reverseFill")
expectSetting("make raid frames fill normal direction", "gf_raid.reverseFill", false, "reverseFill")
expectSetting("make party frames fill left to right", "gf_party.reverseFill", false, "reverseFill")
expectSetting("turn off raid reverse fill", "gf_raid.reverseFill", false, "reverseFill")
expectSettingAt("make group frames fill backwards", 1, "gf_party.reverseFill", true, "reverseFill")
expectSettingAt("make group frames fill backwards", 3, "gf_mythicraid.reverseFill", true, "reverseFill")
do
    local oldGroupFill = A.Parser.ParseGroupFrameFillDirectionShortcut
    A.Parser.ParseGroupFrameFillDirectionShortcut = function() error("legacy group fill-direction shortcut should not be in the live parse path") end
    local parsed = A.Parse("make raid frames fill right to left")
    assert(parsed and parsed.kind == "changes", "group reverse fill should produce a concrete setting change")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_raid.reverseFill", "group reverse fill registry exact alias picked the wrong setting")
    assert(parsed.changes[1].value == true, "group reverse fill registry exact alias picked the wrong true value")
    parsed = A.Parse("make party frames fill left to right")
    assert(parsed and parsed.kind == "changes", "group normal fill should produce a concrete setting change")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_party.reverseFill", "group normal fill registry exact alias picked the wrong setting")
    assert(parsed.changes[1].value == false, "group normal fill registry exact alias picked the wrong false value")
    parsed = A.Parse("make group frames fill backwards")
    assert(parsed and parsed.kind == "changes", "bulk group reverse fill should produce concrete setting changes")
    assert(#(parsed.changes or {}) == 3, "bulk group reverse fill should update all three group-frame scopes")
    A.Parser.ParseGroupFrameFillDirectionShortcut = oldGroupFill
end
expectSetting("turn on mythic raid shorten group names", "gf_mythicraid.nameShortenEnabled", true, "nameShortening")
expectSetting("set mythic raid name truncation style to left", "gf_mythicraid.nameClipSide", "LEFT", "nameClipSide")
expectSetting("turn on mythic raid no ellipsis", "gf_mythicraid.nameNoEllipsis", true, "nameNoEllipsis")
expectSetting("set party debuff stripe opacity to 50", "gf_party.debuffStripeAlpha", 0.5, "debuffStripeAlpha")
expectSetting("set party debuff stripe height to 4", "gf_party.debuffStripeHeight", 4, "debuffStripeHeight")
expectColorSetting("set party debuff stripe color to red", "gf_party.debuffStripeColor", 1, 0, 0, "debuffStripeColor")
expectSetting("set party offline opacity to 50", "gf_party.offlineAlpha", 0.5, "offlineAlpha")
expectSetting("fade offline raid members to 30", "gf_raid.offlineAlpha", 0.3, "offlineAlpha")
expectSetting("make offline party members more transparent", "gf_party.offlineAlpha", nil, "offlineAlpha", -0.05)
expectSetting("only hide offline raid members in combat", "gf_raid.hideOfflineInCombat", true, "hideOfflineInCombat")
expectSetting("hide healer power bars in raid frames", "gf_raid.powerShowHealer", false, "powerShowHealer")
expectSetting("show healer mana in party frames", "gf_party.powerShowHealer", true, "powerShowHealer")
expectSetting("hide dps power in raid frames", "gf_raid.powerShowDamager", false, "powerShowDamager")
expectSetting("show tank power in party frames", "gf_party.powerShowTank", true, "powerShowTank")
expectSetting("turn on party role icon for tanks", "gf_party.roleIconShowTank", true, "roleIconShowTank")
expectSetting("turn off raid role icon for healers", "gf_raid.roleIconShowHealer", false, "roleIconShowHealer")
expectSetting("turn on mythic raid role icon for dps", "gf_mythicraid.roleIconShowDPS", true, "roleIconShowDPS")
expectSetting("set party power height to 15", "gf_party.powerHeight", 15, "powerHeight")
expectSetting("turn on party group number", "gf_party.showGroupNumber", true, "groupNumber")
expectSetting("make party group number bigger", "gf_party.groupNumberSize", nil, "groupNumberSize", 1)
expectSetting("set party group number strata to 15", "gf_party.groupNumberLayer", 15, "groupNumberLayer")
expectSetting("set player group number strata to 21", "player.raidGroupNameLayer", 21, "raidgroupnameLayer")
expectSetting("turn on party group border", "gf_party.groupBorderEnabled", true, "groupBorder")
expectSetting("make raid group border thicker", "gf_raid.groupBorderSize", nil, "groupBorderSize", 1)
expectSetting("set party group border thickness to 6", "gf_party.groupBorderSize", 6, "groupBorderSize")
expectSetting("add padding around party frames", "gf_party.groupBorderPadding", nil, "groupBorderPadding", 1)
expectSetting("set party group border padding to 20", "gf_party.groupBorderPadding", 20, "groupBorderPadding")
expectSetting("turn on party power bar gradient", "barScope.gf_party.enablePowerGradient", true, "powerGradient")
expectSetting("turn on mythic raid power bar gradient", "barScope.gf_raid.enablePowerGradient", true, "powerGradient")
expectSetting("set party corner indicator opacity to 50", "gf_party.ciAlpha", 0.5, "cornerIndicatorAlpha")
expectSetting("set party text opacity to 70", "fontScope.gf_party.fontTextAlpha", 0.7, "textOpacity")
expectSetting("set party absorb bar opacity to 50", "barScope.gf_party.absorbBarOpacity", 0.5, "absorbOpacity")
expectSetting("set party heal absorb bar opacity to 50", "barScope.gf_party.healAbsorbBarOpacity", 0.5, "healAbsorbOpacity")
expectSetting("disable target full health absorb stripe", "barScope.target.fullHealthAbsorbStripe", false, "fullHealthAbsorbStripe")
expectSetting("enable raid full health absorb stripe", "barScope.gf_raid.fullHealthAbsorbStripe", true, "fullHealthAbsorbStripe")
expectSetting("set raid backdrop opacity to 50", "gf_raid.hpBgAlpha", 0.5, "hpBgAlpha")
expectSetting("set raid hp fill opacity to 75", "gf_raid.hpBarAlpha", 0.75, "hpBarAlpha")
expectSetting("set raid hp track opacity to 25", "gf_raid.hpBgAlpha", 0.25, "hpBgAlpha")
expectSetting("turn on raid keep text portrait visible", "gf_raid.alphaExcludeTextPortrait", true, "alphaExcludeTextPortrait")
expectSetting("turn on Party Keep Text & Portrait Visible", "gf_party.alphaExcludeTextPortrait", true, "alphaExcludeTextPortrait")
expectSetting("keep raid names visible when transparent", "gf_raid.alphaExcludeTextPortrait", true, "alphaExcludeTextPortrait")
expectSetting("make raid frames transparent when out of range", "gf_raid.rangeFadeEnabled", true, "rangeFade")
expectSettingAt("make raid frames more transparent when out of range", 1, "gf_raid.rangeFadeEnabled", true, "rangeFade")
expectSettingAt("make raid frames more transparent when out of range", 2, "gf_raid.rangeFadeAlpha", nil, "rangeFadeAlpha", -0.05)
expectSettingAt("make party frames less transparent out of range", 1, "gf_party.rangeFadeEnabled", true, "rangeFade")
expectSettingAt("make party frames less transparent out of range", 2, "gf_party.rangeFadeAlpha", nil, "rangeFadeAlpha", 0.05)
expectSetting("set raid out of range opacity to 30", "gf_raid.rangeFadeAlpha", 0.3, "rangeFadeAlpha")
do
    local parsed = A.Parse("where can I change raid range fade")
    assert(parsed.kind ~= "changes", "where-can Raid range fade question must not mutate settings")
end
expectSetting("keep raid text visible when faded", "gf_raid.alphaExcludeTextPortrait", true, "alphaExcludeTextPortrait")
expectSetting("set raid range fade affects health", "gf_raid.rangeFadeLayerMode", "health", "rangeFadeLayerMode")
expectSetting("turn on raid dead background", "gf_raid.deadBgEnabled", true, "deadBgEnabled")
expectColorSetting("set party dead background color to red", "gf_party.deadBgColor", 1, 0, 0, "deadBgColor")
expectSetting("set party dead background opacity to 50", "gf_party.deadBgA", 0.5, "deadBgAlpha")
expectSetting("turn off raid tint offline members", "gf_raid.deadBgOffline", false, "deadBgOffline")
expectSetting("dont show party player in group when solo", "gf_party.showPlayer", false, "showPlayer")
expectSetting("do not show raid player in group when solo", "gf_raid.showPlayer", false, "showPlayer")
expectSetting("turn off party show while solo", "gf_party.showSolo", false, "showSolo")
expectSetting("show party frames while solo", "gf_party.showSolo", true, "showSolo")
expectSetting("show party frame while solo", "gf_party.showSolo", true, "showSolo")
expectSetting("hide party frame when solo", "gf_party.showSolo", false, "showSolo")
expectSetting("hide offline players in raid frames", "gf_raid.hideOfflineEnabled", true, "hideOfflineEnabled")
expectSettingAt("hide offline raid members after 10 seconds", 1, "gf_raid.hideOfflineEnabled", true, "hideOfflineEnabled")
expectSettingAt("hide offline raid members after 10 seconds", 2, "gf_raid.hideOfflineDelay", 10, "hideOfflineDelay")
expectSetting("put raid frames in 4 columns", "gf_raid.maxColumns", 4, "maxColumns")
expectSetting("put raid in four columns", "gf_raid.maxColumns", 4, "maxColumns")
expectSetting("show 5 raid members per column", "gf_raid.unitsPerColumn", 5, "unitsPerColumn")
expectSetting("start new raid column after 5 players", "gf_raid.unitsPerColumn", 5, "unitsPerColumn")
expectSetting("break raid columns after 5 members", "gf_raid.unitsPerColumn", 5, "unitsPerColumn")
expectSetting("change load condition from target frame to not show out of combat", "target.loadCondHideOutOfCombat", true, "loadCondHideOutOfCombat")
expectSetting("change load condtion from taregt frame to not show out of combat", "target.loadCondHideOutOfCombat", true, "loadCondHideOutOfCombat")
expectSetting("show target frame out of combat", "target.loadCondHideOutOfCombat", false, "loadCondHideOutOfCombat")
expectSetting("turn off target hide out of combat load condition", "target.loadCondHideOutOfCombat", false, "loadCondHideOutOfCombat")
expectSetting("hide player frame when mounted", "player.loadCondHideMounted", true, "loadCondHideMounted")
expectSetting("turn on player hide in group", "player.loadCondHideInGroup", true, "loadCondHideInGroup")
expectSetting("change player load condition to hide in group", "player.loadCondHideInGroup", true, "loadCondHideInGroup")
expectSettingAt("hide all unitframes in combat", 1, "player.loadCondHideInCombat", true, "loadCondHideInCombat")
expectSettingAt("hide all unitframes in combat", 2, "target.loadCondHideInCombat", true, "loadCondHideInCombat")
expectSettingAt("hide all unitframes in combat", 7, "boss.loadCondHideInCombat", true, "loadCondHideInCombat")
expectSetting("change raid group load condition to show while solo", "gf_raid.showSolo", true, "showSolo")
expectSetting("change raid group load condition to not show while solo", "gf_raid.showSolo", false, "showSolo")
expectAnswer("change raid group load condition to hide out of combat", "has no load-condition toggle yet")
do
    local parsed = A.Parse("dont show player in group when solo")
    assert(parsed.kind == "ambiguous", "bare group player solo command should ask for Party/Raid/Mythic Raid")
    assert(type(parsed.choices) == "table" and #parsed.choices == 3, "bare group player solo choices missing")
    assert(parsed.choices[1].setting and parsed.choices[1].setting.key == "gf_party.showPlayer", "bare group player solo choice 1 wrong")
    assert(parsed.choices[2].setting and parsed.choices[2].setting.key == "gf_raid.showPlayer", "bare group player solo choice 2 wrong")
    assert(parsed.choices[3].setting and parsed.choices[3].setting.key == "gf_mythicraid.showPlayer", "bare group player solo choice 3 wrong")
end
MSUF.MSUF2.activeKey = "gf_layout"
MSUF.MSUF2.gfScope = "raid"
expectSetting("dont show player in group when solo", "gf_raid.showPlayer", false, "showPlayer")
MSUF.MSUF2.activeKey = "home"
expectSetting("turn on raid dispel overlay", "gf_raid.dispelOverlayEnabled", true, "dispelOverlay")
expectSetting("set raid dispel overlay detects any debuff", "gf_raid.dispelOverlayTrigger", "DISPEL_TYPE", "dispelOverlayTrigger")
expectSetting("set raid dispel overlay detects dispellable by group", "gf_raid.dispelOverlayTrigger", "BY_RAID", "dispelOverlayTrigger")
expectSetting("set raid dispel overlay style bottom", "gf_raid.dispelOverlayStyle", "BOTTOM", "dispelOverlayStyle")
expectSetting("turn off raid dispel overlay current health only", "gf_raid.dispelOverlayOnHealth", false, "dispelOverlayOnHealth")
expectSetting("set raid dispel overlay opacity to 55", "gf_raid.dispelOverlayAlpha", 0.55, "dispelOverlayAlpha")
expectSetting("set player custom anchor frame to PlayerFrame", "player.anchorFrameName", "PlayerFrame", "anchorFrameName")
expectSetting("set player custom anchor to cooldownmanager", "player.anchorFrameName", "EssentialCooldownViewer", "anchorFrameName")
expectSetting("use cooldownmanager as target custom anchor", "target.anchorFrameName", "EssentialCooldownViewer", "anchorFrameName")
expectSetting("use CompactRaidFrame1 as target custom anchor", "target.anchorFrameName", "CompactRaidFrame1", "anchorFrameName")
expectSetting("anchor player to CompactRaidFrame1", "player.anchorFrameName", "CompactRaidFrame1", "anchorFrameName")
expectSetting("set raid custom anchor to CompactRaidFrame1", "gf_raid.customAnchorFrame", "CompactRaidFrame1", "customAnchorFrame")
expectSetting("only player bars on", "barScope.player.override", true, "override")
expectSetting("only target fonts on", "fontScope.target.override", true, "override")
expectSettingAt("set only player bar outline thickness to 3", 1, "barScope.player.override", true, "override")
expectSettingAt("set only player bar outline thickness to 3", 2, "barScope.player.barOutlineThickness", 3, "outline")
expectSettingAt("set only party bars dispel border off", 1, "barScope.gf_party.override", true, "override")
expectSettingAt("set only party bars dispel border off", 2, "barScope.gf_party.dispelOutlineMode", "off", "dispelBorder")
expectSettingAt("set target font outline only to THICKOUTLINE", 1, "fontScope.target.override", true, "override")
expectSettingAt("set target font outline only to THICKOUTLINE", 2, "fontScope.target.outline", "THICKOUTLINE", "outline")
expectSetting("set text opacity to 70", "fontScope.shared.fontTextAlpha", 0.7, "textOpacity")
expectSetting("set absorb bar opacity to 50", "general.absorbBarOpacity", 0.5, "absorbOpacity")
expectSetting("set heal absorb opacity to 60", "general.healAbsorbBarOpacity", 0.6, "healAbsorbOpacity")
expectSetting("enable full health absorb stripe", "general.fullHealthAbsorbStripe", true, "fullHealthAbsorbStripe")
expectSetting("enable full health absorb overlay", "general.overAbsorbOverlay", true, "overAbsorbOverlay")
expectSetting("turn off text shadows", "fontScope.shared.textBackdrop", false, "textShadow")
expectSetting("disable font shadows", "fontScope.shared.textBackdrop", false, "textShadow")
expectSetting("turn off shadows", "fontScope.shared.textBackdrop", false, "textShadow")
expectSetting("turn off player text shadows", "fontScope.player.textBackdrop", false, "textShadow")
expectSetting("set shadow strengths to soft", "fontScope.shared.fontShadowStrength", "SOFT", "shadowStrength")
expectSetting("turn off player names", "player.showName", false, "name")
expectSetting("set font sizes to 16", "general.fontSize", 16, "fontSize")
expectSetting("set bar outline thicknesses to 2", "bars.barOutlineThickness", 2, "outline")
expectSetting("turn off castbar sparks", "general.castbarShowSpark", false, "spark")
expectSetting("turn off target portraits", "target.portraitMode", "OFF", "portraitMode")
expectSettingAt("only turn on color text by power for target", 1, "fontScope.target.override", true, "override")
expectSettingAt("only turn on color text by power for target", 2, "fontScope.target.colorPowerTextByType", "RESOURCE", "powerTextColor")
expectSettingAt("change focus target power text to power color", 1, "fontScope.focustarget.colorPowerTextByType", "RESOURCE", "powerTextColor")
expectSettingAt("change focus target power text to power color", 2, "fontScope.focustarget.override", true, "override")
expectSetting("change power text font for all the power color", "fontScope.shared.colorPowerTextByType", "RESOURCE", "powerTextColor")
expectSetting("set power text to font color", "fontScope.shared.colorPowerTextByType", "DEFAULT", "powerTextColor")
expectSetting("turn off color text by power for target", "fontScope.target.colorPowerTextByType", "DEFAULT", "powerTextColor")
expectSetting("color name not by class", "fontScope.shared.nameColorMode", "DEFAULT", "nameColor")
expectSetting("name text not by class", "fontScope.shared.nameColorMode", "DEFAULT", "nameColor")
expectSetting("player name not by class", "fontScope.player.nameColorMode", "DEFAULT", "nameColor")
expectSetting("party name not by class", "fontScope.gf_party.nameColorMode", "DEFAULT", "nameColor")
expectAnySetting("color everything white", "general.customFontColor", nil, "customFontColor")
expectAnySetting("color everything white", "fontScope.shared.nameColorMode", "DEFAULT", "nameColor")
expectAnySetting("color everything white", "fontScope.shared.colorHealthTextByHealth", "DEFAULT", "healthTextColor")
expectAnySetting("color everything white", "fontScope.shared.colorPowerTextByType", "DEFAULT", "powerTextColor")
expectSettingAt("only turn on color text by health for focus", 1, "fontScope.focus.override", true, "override")
expectSettingAt("only turn on color text by health for focus", 2, "fontScope.focus.colorHealthTextByHealth", "HEALTH", "healthTextColor")
expectSettingAt("increase only player bar outline thickness by 1", 1, "barScope.player.override", true, "override")
expectSettingAt("increase only player bar outline thickness by 1", 2, "barScope.player.barOutlineThickness", nil, "outline", 1)
setFollowupContext("unitframe", "name", false)
expectSetting("same for target", "target.showName", false, "name")
setFollowupContext("unitframe", "name", false)
expectSetting("same for raid", "gf_raid.showName", false, "name")
setFollowupContext("group", "name", false)
expectSetting("do that for target", "target.showName", false, "name")
setFollowupContext("unitframe", "name", false)
expectSetting("repeat that for focus", "focus.showName", false, "name")
setFollowupContext("unitframe", "name", false)
expectSetting("apply that to target", "target.showName", false, "name")
setFollowupContext("unitframe", "name", false)
expectSetting("make the same change on focus", "focus.showName", false, "name")
setFollowupContext("unitframe", "anchorFrameName", "CompactRaidFrame1")
expectSetting("same for raid", "gf_raid.customAnchorFrame", "CompactRaidFrame1", "customAnchorFrame")
setFollowupContext("group", "customAnchorFrame", "CompactRaidFrame1")
expectSetting("same for target", "target.anchorFrameName", "CompactRaidFrame1", "anchorFrameName")
setFollowupContext("unitframe", "anchorToUnitframe", "EssentialCooldownViewer")
expectSetting("same for raid", "gf_raid.customAnchorFrame", "EssentialCooldownViewer", "customAnchorFrame")
setFollowupContext("unitframe", "anchorToUnitframe", "target")
expectSetting("same for raid", "gf_raid.anchorToFrame", "target", "anchorToFrame")
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
expectAnswer("what did you just change", "Global Bar Outline Thickness")
expectAnswer("what exactly did you change", "Global Bar Outline Thickness")
expectAnswer("what was the last assistant change", "Global Bar Outline Thickness")
local actionCtx = A.GetContext()
actionCtx.lastChangeBundle = {}
actionCtx.lastSetting = nil
actionCtx.lastAction = "copy_unit"
actionCtx.lastActionLabel = "Copy Unit Settings"
actionCtx.lastActionMessage = "Done. I copied Target settings to Player."
actionCtx.lastActionUndoable = true
actionCtx.lastActionArgs = {
    source = "target",
    targets = { "player" },
    scopes = { basics = false, text = true, portrait = false, power = true, castbar = false, status = false, load = false, transparency = false, layout = false },
}
expectAnswer("what did you change", "Copy Unit Settings")
expectAnswer("what did you do", "Ask for 'undo' to revert it.")
expectAnswer("what did you just copy", "Copy Unit Settings")
expectCopy("copy that to focus", "copy_unit", "target", { "focus" }, { basics = false, text = true, power = true, castbar = false, layout = false })
actionCtx.lastAction = "copy_group"
actionCtx.lastActionLabel = "Copy Group Frame Settings"
actionCtx.lastActionMessage = "Done. I copied Party group-frame settings to Raid."
actionCtx.lastActionUndoable = true
actionCtx.lastActionArgs = {
    source = "party",
    targets = { "raid" },
    scopes = { general = false, health = true, dispel = false, text = true, font = false, range = false, indicators = false, auras = false, highlight = false, dstripe = false, features = false },
}
expectCopy("same for mythic raid", "copy_group", "party", { "mythicraid" }, { general = false, health = true, dispel = false, text = true, auras = false, indicators = false })
actionCtx.lastAction = nil
actionCtx.lastActionArgs = nil
expectAnswer("copy that to target", "Start with a full copy request first")
expectAnswer("what did you copy", "I don't have an earlier copy task to repeat yet.")
expectSetting("set mythic raid width to 170", "gf_mythicraid.width", 170)
expectSetting("set party raid marker size to 23", "gf_party.raidMarkerSize", 23)
expectSetting("turn on party preserve raid groups", "gf_party.preserveRaidGroups", true)
expectSetting("turn on party shorten group names", "gf_party.nameShortenEnabled", true, "nameShortening")
expectSetting("do not shorten party name text", "gf_party.nameShortenEnabled", false, "nameShortening")
expectSetting("turn off party name shorten text", "gf_party.nameShortenEnabled", false, "nameShortening")
expectSetting("set party name truncation style to left", "gf_party.nameClipSide", "LEFT", "nameClipSide")
expectSetting("turn on shared buff raid filter", "auras3.shared.buff.filter.raid", true, "aurabuffFilterraid")
expectSetting("turn on target buff player filter", "auras3.target.buff.filter.onlyMine", true, "aurabuffFilteronlyMine")
expectSetting("set target buff icon size to 30", "auras3.target.buff.size", 30, "auraBuffsize")
expectSetting("set party buff icon size to 24", "gf_party.auras.buff.size", 24, "gfAurabuffSize")
expectSetting("make target buffs bigger", "auras3.target.buff.size", nil, "auraBuffsize", 1)
setLastChangeBundle({ { key = "auras3.target.buff.size", relativeDelta = 1 } })
expectSetting("same for debuffs", "auras3.target.debuff.size", nil, "auraDebuffsize", 1)
expectSettingAt("make party aura icons bigger", 1, "gf_party.auras.buff.size", nil, "gfAurabuffSize", 1)
expectSettingAt("make party aura icons bigger", 2, "gf_party.auras.debuff.size", nil, "gfAuradebuffSize", 1)
expectSettingAt("make all aura icons bigger", 1, "auras3.player.buff.size", nil, "auraBuffsize", 1)
expectSettingAt("make all aura icons bigger", 9, "gf_party.auras.buff.size", nil, "gfAurabuffSize", 1)
expectSettingAt("make all buff icons bigger", 7, "gf_mythicraid.auras.buff.size", nil, "gfAurabuffSize", 1)
expectSettingAt("make all unit aura icons bigger", 8, "auras3.boss.debuff.size", nil, "auraDebuffsize", 1)
expectSettingAt("set all aura icon size to 24", 14, "gf_mythicraid.auras.debuff.size", 24, "gfAuradebuffSize")
expectSetting("make target buffs grow up", "auras3.target.buff.growth", "UP", "auraBuffgrowth")
expectSettingAt("set all unit aura growth to up", 8, "auras3.boss.debuff.growth", "UP", "auraDebuffgrowth")
expectSettingAt("set all unit aura max icons to 10", 8, "auras3.boss.debuff.max", 10, "auraDebuffmax")
expectSetting("set target buff anchor to bottom right", "auras3.target.buff.anchor", "BOTTOMRIGHT", "auraBuffanchor")
expectSetting("set target buff layer to 8", "auras3.target.buff.layer", 8, "auraBufflayer")
expectSetting("set target buff spacing to 4", "auras3.target.buff.spacing", 4, "auraBuffspacing")
expectSetting("set target buff stack x offset to 5", "auras3.target.buff.stackTextOffsetX", 5, "auraBuffstackTextOffsetX")
expectSetting("set target debuff cooldown y offset to -3", "auras3.target.debuff.cooldownTextOffsetY", -3, "auraDebuffcooldownTextOffsetY")
expectNoChange("set target buff exclusive filter to none")
expectNoChange("set target buff exclusive filter to important")
expectSetting("set party buff anchor to bottom right", "gf_party.auras.buff.anchor", "BOTTOMRIGHT", "gfAurabuffAnchor")
expectSettingAt("anchro group frame buffs to the left", 1, "gf_party.auras.buff.anchor", "BOTTOMLEFT", "gfAurabuffAnchor")
expectSettingAt("anchro group frame buffs to the left", 3, "gf_mythicraid.auras.buff.anchor", "BOTTOMLEFT", "gfAurabuffAnchor")
setLastChangeBundle({ { key = "gf_raid.auras.buff.anchor", value = "BOTTOMLEFT" } })
expectSetting("same for debuffs", "gf_raid.auras.debuff.anchor", "BOTTOMLEFT", "gfAuradebuffAnchor")
expectSetting("set raid buff filter to raid", "gf_raid.auras.buff.filterToken", "Raid", "gfAurabuffFilterToken")
expectSetting("set raid buff filter to important", "gf_raid.auras.buff.filterToken", "IMPORTANT", "gfAurabuffFilterToken")
expectSetting("set party buff cooldown anchor to top left", "gf_party.auras.buff.cooldownAnchor", "TOPLEFT", "gfAurabuffCooldownAnchor")
expectSettingAt("set party aura spacing to 4", 2, "gf_party.auras.debuff.spacing", 4, "gfAuradebuffSpacing")
expectSettingAt("set all group aura layer to 9", 6, "gf_mythicraid.auras.debuff.layer", 9, "gfAuradebuffLayer")
expectSetting("move target buffs left", "auras3.target.buff.offsetX", nil, "auraBuffoffsetX", -10)
expectSetting("move party buffs left", "gf_party.auras.buff.x", nil, "gfAurabuffOffsetX", -10)
expectSettingAt("move all unit auras left", 8, "auras3.boss.debuff.offsetX", nil, "auraDebuffoffsetX", -10)
expectSettingAt("move all auras left", 9, "gf_party.auras.buff.x", nil, "gfAurabuffOffsetX", -10)
expectSetting("turn on aura timer color buckets", "general.aurasCooldownTextUseBuckets", true, "auraCooldownBuckets")
expectColorSetting("set aura safe timer color to red", "general.aurasCooldownTextSafeColor", 1, 0, 0, "aurasCooldownTextSafeColor")
expectColorSetting("set aura warning timer color to #ffaa00", "general.aurasCooldownTextWarningColor", 1, 170 / 255, 0, "aurasCooldownTextWarningColor")
expectColorSetting("set aura stack count color to green", "general.aurasStackCountColor", 0, 1, 0, "auraStackColor")
expectColorSetting("set own buff aura highlight color to blue", "general.aurasOwnBuffHighlightColor", 0, 0, 1, "ownBuffHighlightColor")
expectColorSetting("set own debuff aura highlight color to red", "general.aurasOwnDebuffHighlightColor", 1, 0, 0, "ownDebuffHighlightColor")
expectSetting("set aura safe seconds to 80", "general.aurasCooldownTextSafeSeconds", 80, "auraCooldownTextSafeSeconds")
expectSetting("set aura warning seconds to 12", "general.aurasCooldownTextWarningSeconds", 12, "auraCooldownTextWarningSeconds")
expectSetting("set aura urgent seconds to 4", "general.aurasCooldownTextUrgentSeconds", 4, "auraCooldownTextUrgentSeconds")
expectSetting("turn off unit auras", "auras3.enabled", false, "auraSystemEnabled")
expectSetting("turn off aura edit preview", "auras3.shared.showInEditMode", false, "auraEditPreview")
expectSetting("turn off aura buffs", "auras3.shared.showBuffs", false)
expectSetting("turn off aura filters", "auras3.shared.filters.enabled", false, "auraFiltersEnabled")
expectSetting("turn on aura tooltips", "auras3.shared.showTooltip", true)
expectSetting("turn on aura click through", "auras3.shared.clickThroughAuras", true)
expectSetting("turn on aura debuff type borders", "auras3.shared.useDebuffTypeBorders", true)
expectSetting("set aura editing scope to target", "menu.auraScope", "target", "auraEditScope")
expectActionArg("edit target auras", "set_aura_edit_scope", "scope", "target")
expectSetting("set aura editing scope to raid", "menu.auraScope", "raid", "auraEditScope")
expectActionArg("edit party auras", "set_aura_edit_scope", "scope", "party")
expectSetting("set aura style lane to buff", "menu.auraStyleGFLane", "buff", "auraStyleLane")
expectSetting("set aura filter lane to debuff", "menu.auraFilterLane", "debuff", "auraFilterLane")
expectSetting("set aura settings view to all settings", "menu.aurasUXMode", "advanced", "auraSettingsView")
expectSetting("show basic aura settings", "menu.aurasUXMode", "basic", "auraSettingsView")
do
    local parsed = A.Parse("show basic aura settings")
    assert(parsed and parsed.kind == "changes", "aura settings view should produce a concrete setting change")
end
expectSetting("turn on target aura custom filters", "auras3.target.overrideFilters", true, "auraOverrideFilters")
expectSetting("turn on target custom aura filters", "auras3.target.overrideFilters", true, "auraOverrideFilters")
expectSetting("use custom aura style for player", "auras3.player.customStyle", true)
expectSetting("use custom aura filters for target", "auras3.target.overrideFilters", true, "auraOverrideFilters")
expectSetting("player custom aura filters", "auras3.player.overrideFilters", true, "auraOverrideFilters")
expectSetting("use shared aura style for player", "auras3.player.useSharedStyle", true)
expectSettingAt("raid cooldown swipe direction reverse", 1, "gf_raid.auras.buff.cooldownSwipeReverse", "REVERSE")
expectSettingAt("raid cooldown swipe direction reverse", 2, "gf_raid.auras.debuff.cooldownSwipeReverse", "REVERSE")
expectSettingAt("set target cooldown swipe direction to reverse", 1, "auras3.target.buff.cooldownSwipeReverse", "REVERSE")
expectSettingAt("set target cooldown swipe direction to reverse", 2, "auras3.target.debuff.cooldownSwipeReverse", "REVERSE")
expectAnswer("raid debuff dispel border mode", "Use off, border, or symbol")
expectSetting("raid debuff dispel border mode to border", "gf_raid.auras.debuff.dispelBorderMode", "BORDER")
expectSetting("turn on target custom aura caps", "auras3.target.overrideSharedLayout", true, "auraOverrideSharedLayout")
expectSetting("turn on target custom aura layout", "auras3.target.overrideLayout", true, "auraOverrideLayout")
expectSetting("turn on target custom aura ignore", "auras3.target.overrideIgnore", true, "auraOverrideIgnore")
expectActionArg("reset target aura scope", "reset_aura_scope_overrides", "scope", "target")
expectActionArg("reset target aura overrides", "reset_aura_scope_overrides", "scope", "target")
expectActionArg("reset player aura custom settings", "reset_aura_scope_overrides", "scope", "player")
expectActionArg("clear target aura overrides", "reset_aura_scope_overrides", "scope", "target")
expectActionArg("remove boss aura overrides", "reset_aura_scope_overrides", "scope", "boss")
expectActionArg("reset focus custom aura settings", "reset_aura_scope_overrides", "scope", "focus")
expectAction("reset all aura overrides", "reset_all_aura_overrides")
expectAction("reset all custom aura settings", "reset_all_aura_overrides")
expectAction("reset buff aura style overrides", "reset_all_aura_style_overrides")
expectAction("use shared aura style everywhere", "reset_all_aura_style_overrides")
expectSetting("set aura buff growth to up", "auras3.shared.buffGrowth", "UP", "auraBuffGrowth")
expectSetting("set aura buff wrap rows to up", "auras3.shared.buffRowWrap", "UP", "auraBuffRowWrap")
expectSetting("set aura sort order to 3", "auras3.shared.sortOrder", 3, "auraSortOrder")
expectSetting("turn off show sated exhaustion", "auras3.shared.showSated", false)
expectSetting("set sated threshold to 30", "auras3.shared.satedShowAtSeconds", 30, "auraSatedShowAtSeconds")
expectSetting("turn off buff reminders", "auras3.shared.showReminders", false, "auraShowReminders")
expectSetting("turn off fortitude reminder", "auras3.shared.reminders.FORTITUDE", false, "auraReminderFORTITUDE")
expectSetting("set buff reminder expiry warning to 30", "auras3.shared.reminderThreshold", 30, "auraReminderThreshold")
expectSetting("set buff reminder growth to up", "auras3.shared.reminderGrowth", "UP", "auraReminderGrowth")
expectActionArg("apply clean aura preset", "apply_aura_quick_preset", "preset", "clean")
expectActionArg("apply clean aura preset", "apply_aura_quick_preset", "scope", "shared")
expectActionArg("apply performance aura preset", "apply_aura_quick_preset", "preset", "performance")
expectActionArg("use focused aura preset", "apply_aura_quick_preset", "preset", "focused")
expectActionArg("use clean aura quick preset", "apply_aura_quick_preset", "preset", "clean")
expectActionArg("aura quick setup clean", "apply_aura_quick_preset", "preset", "clean")
do
    local parsed = A.Parse("aura quick setup clean")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "apply_aura_quick_preset", "aura quick setup should use the registered quick-preset action")
end
expectActionArg("blacklist raid buffs for target auras", "aura_blacklist_add_preset", "scope", "target")
expectActionArg("blacklist raid buffs for target auras", "aura_blacklist_add_preset", "preset", "RAID_BUFFS")
expectActionArg("add cooldown aura blacklist preset to player auras", "aura_blacklist_add_preset", "scope", "player")
expectActionArg("add cooldown aura blacklist preset to player auras", "aura_blacklist_add_preset", "preset", "COOLDOWNS")
do
    local parsed = A.Parse("blacklist raid buffs for target auras")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_blacklist_add_preset", "aura blacklist preset should use the registered preset action")
end
expectActionArg("blacklist spell 12345 for player auras", "aura_blacklist_add_spell", "scope", "player")
expectActionArg("blacklist spell 12345 for player auras", "aura_blacklist_add_spell", "value", "12345")
expectActionArg("blacklist |cff71d5ff|Hspell:774:0|h[Rejuvenation]|h|r for target auras", "aura_blacklist_add_spell", "scope", "target")
expectActionArg("blacklist |cff71d5ff|Hspell:774:0|h[Rejuvenation]|h|r for target auras", "aura_blacklist_add_spell", "value", "spell:774")
expectActionArg("blacklist Rejuvenation on target auras", "aura_blacklist_add_spell", "scope", "target")
expectActionArg("blacklist Rejuvenation on target auras", "aura_blacklist_add_spell", "value", "Rejuvenation")
expectActionArg("blacklist [Rejuvenation] for target auras", "aura_blacklist_add_spell", "scope", "target")
expectActionArg("blacklist [Rejuvenation] for target auras", "aura_blacklist_add_spell", "value", "Rejuvenation")
expectActionArg("hide Rejuvenation on target buffs", "aura_blacklist_add_spell", "scope", "target")
expectActionArg("hide Rejuvenation on target buffs", "aura_blacklist_add_spell", "value", "Rejuvenation")
expectActionArg("stop showing Power Word: Fortitude on player auras", "aura_blacklist_add_spell", "scope", "player")
expectActionArg("stop showing Power Word: Fortitude on player auras", "aura_blacklist_add_spell", "value", "Power Word: Fortitude")
expectActionArg("remove Rejuvenation from target aura blacklist", "aura_blacklist_remove_spell", "scope", "target")
expectActionArg("remove Rejuvenation from target aura blacklist", "aura_blacklist_remove_spell", "value", "Rejuvenation")
expectActionArg("remove [Rejuvenation] from target aura blacklist", "aura_blacklist_remove_spell", "scope", "target")
expectActionArg("remove [Rejuvenation] from target aura blacklist", "aura_blacklist_remove_spell", "value", "Rejuvenation")
expectActionArg("allow |cff71d5ff|Hspell:21562:0|h[Power Word: Fortitude]|h|r for player auras", "aura_blacklist_remove_spell", "scope", "player")
expectActionArg("allow |cff71d5ff|Hspell:21562:0|h[Power Word: Fortitude]|h|r for player auras", "aura_blacklist_remove_spell", "value", "spell:21562")
expectActionArg("allow Power Word: Fortitude for player auras", "aura_blacklist_remove_spell", "scope", "player")
expectActionArg("allow Power Word: Fortitude for player auras", "aura_blacklist_remove_spell", "value", "Power Word: Fortitude")
expectActionArg("unhide Rejuvenation on target buffs", "aura_blacklist_remove_spell", "scope", "target")
expectActionArg("unhide Rejuvenation on target buffs", "aura_blacklist_remove_spell", "value", "Rejuvenation")
expectActionArg("show Power Word: Fortitude again on player auras", "aura_blacklist_remove_spell", "scope", "player")
expectActionArg("show Power Word: Fortitude again on player auras", "aura_blacklist_remove_spell", "value", "Power Word: Fortitude")
expectActionArg("let Power Word: Fortitude show on player auras", "aura_blacklist_remove_spell", "scope", "player")
expectActionArg("let Power Word: Fortitude show on player auras", "aura_blacklist_remove_spell", "value", "Power Word: Fortitude")
expectActionArg("clear target aura blacklist", "aura_blacklist_clear_spells", "scope", "target")
expectActionArg("allow all player aura blacklist spells", "aura_blacklist_clear_spells", "scope", "player")
expectActionArg("empty target aura blacklist", "aura_blacklist_clear_spells", "scope", "target")
expectActionArg("reset target aura blacklist", "aura_blacklist_clear_spells", "scope", "target")
expectActionArg("delete all focus aura blacklist spells", "aura_blacklist_clear_spells", "scope", "focus")
expectActionArg("show current target aura blacklist", "aura_blacklist_summary", "scope", "target")
expectActionArg("what is player aura blacklist", "aura_blacklist_summary", "scope", "player")
expectActionArg("list boss aura blacklist", "aura_blacklist_summary", "scope", "boss")
do
    assert(A.Parser.ParseAuraEditScope == nil, "Aura edit scope should resolve through registry action metadata, not legacy parser export")
    assert(A.Parser.ParseAuraReset == nil, "Aura reset should resolve through registry action metadata, not legacy parser export")
    assert(A.Parser.ParseAuraSettingsView == nil, "Aura settings view should resolve through registry exact-alias metadata, not legacy parser export")
    assert(A.Parser.ParseAuraQuickPreset == nil, "Aura quick preset should resolve through registry action metadata, not legacy parser export")
    local parsed = A.Parse("set aura editing scope to target")
    assert(parsed.kind == "changes" and parsed.changes and parsed.changes[1]
        and parsed.changes[1].setting and parsed.changes[1].setting.key == "menu.auraScope",
        "explicit aura edit scope should use the canonical menu.auraScope setting")
    parsed = A.Parse("clear player aura custom settings")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "reset_aura_scope_overrides", "aura scope custom clear should use the registered reset action")
    parsed = A.Parse("reset all aura overrides")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "reset_all_aura_overrides", "all aura reset should use the registered reset-all action")
    parsed = A.Parse("show basic aura settings")
    assert(parsed and parsed.kind == "changes", "aura settings view should produce a concrete setting change")
    parsed = A.Parse("aura quick setup clean")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "apply_aura_quick_preset", "aura quick setup should use the registered quick-preset action")
    local geometryShortcut = A.Parser.ParseAuraGeometryShortcut
    local function isRegistrySingleSummary(summary)
        return summary == "Registry-backed settings change."
            or summary == "Registry exact-alias setting change."
    end
    local function isRegistryMultiSummary(summary)
        return summary == "Registry-backed multi-scope setting change."
            or summary == "Registry exact-alias multi-scope setting change."
    end
    parsed = A.Parse("make target buffs grow up")
    assert(parsed.kind == "changes", "unit aura growth should have a concrete registry fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "auras3.target.buff.growth", "unit aura growth registry fallback picked the wrong setting")
    parsed = A.Parse("set all unit aura growth to up")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 8, "all unit aura growth should resolve as registry multi-scope fallback without Aura geometry shortcut")
    parsed = A.Parse("move target buffs right 5")
    assert(parsed.kind == "changes", "unit aura movement should have a concrete registry fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "auras3.target.buff.offsetX", "unit aura movement registry fallback picked the wrong setting")
    assert(parsed.changes[1].relativeDelta == 5, "unit aura movement registry fallback picked the wrong delta")
    parsed = A.Parse("move all unit auras left")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 8, "all unit aura movement should resolve as registry multi-scope fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "auras3.player.buff.offsetX", "all unit aura movement registry fallback picked the wrong first setting")
    assert(parsed.changes[1].relativeDelta == -10, "all unit aura movement registry fallback picked the wrong delta")
    parsed = A.Parse("move party buffs left")
    assert(parsed.kind == "changes", "group aura movement should have a concrete registry fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_party.auras.buff.x", "group aura movement registry fallback picked the wrong setting")
    assert(parsed.changes[1].relativeDelta == -10, "group aura movement registry fallback picked the wrong delta")
    parsed = A.Parse("move raid debuffs down 3")
    assert(parsed.kind == "changes", "group aura y movement should have a concrete registry fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_raid.auras.debuff.y", "group aura y movement registry fallback picked the wrong setting")
    assert(parsed.changes[1].relativeDelta == -3, "group aura y movement registry fallback picked the wrong delta")
    parsed = A.Parse("move all group auras right")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 6, "all group aura movement should resolve as registry multi-scope fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_party.auras.buff.x", "all group aura movement registry fallback picked the wrong first setting")
    assert(parsed.changes[1].relativeDelta == 10, "all group aura movement registry fallback picked the wrong delta")
    parsed = A.Parse("move all group debuffs down 4")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 3, "all group debuff movement should resolve as registry multi-scope fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "gf_party.auras.debuff.y", "all group debuff movement registry fallback picked the wrong first setting")
    assert(parsed.changes[1].relativeDelta == -4, "all group debuff movement registry fallback picked the wrong delta")
    parsed = A.Parse("move all auras left")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 14, "all aura movement should resolve as registry multi-scope fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "auras3.player.buff.offsetX", "all aura movement registry fallback picked the wrong first setting")
    assert(parsed.changes[1].relativeDelta == -10, "all aura movement registry fallback picked the wrong delta")
    parsed = A.Parse("move all debuffs down 4")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 7, "all debuff movement should resolve as registry multi-scope fallback without Aura geometry shortcut")
    assert(parsed.changes and parsed.changes[1] and parsed.changes[1].setting and parsed.changes[1].setting.key == "auras3.player.debuff.offsetY", "all debuff movement registry fallback picked the wrong first setting")
    assert(parsed.changes[1].relativeDelta == -4, "all debuff movement registry fallback picked the wrong delta")
    parsed = A.Parse("move group debuffs down 4")
    assert(parsed.kind == "changes" and #(parsed.changes or {}) == 3,
        "generic group Aura movement should consistently target Party, Raid, and Mythic Raid")

    local function assertAuraIconSizeOnly(text, expectedCount, expectedFirstKey, expectedDelta)
        local sizeParsed = A.Parse(text)
        assert(sizeParsed.kind == "changes" and sizeParsed.summary and #(sizeParsed.changes or {}) == expectedCount, text .. ": Aura icon size should resolve as a registry change without Aura geometry shortcut")
        if expectedCount > 1 then
            assert(sizeParsed.bulkSafe == true, text .. ": Aura icon-size bulk fallback should stay confirmation-safe")
        end
        assert(sizeParsed.changes and sizeParsed.changes[1] and sizeParsed.changes[1].setting and sizeParsed.changes[1].setting.key == expectedFirstKey, text .. ": registry fallback picked the wrong first Aura icon size setting")
        for i = 1, #(sizeParsed.changes or {}) do
            local change = sizeParsed.changes[i]
            local setting = change.setting or {}
            local key = tostring(setting.key or "")
            assert(setting.type == "number", text .. ": vague Aura icon size wording must only hit number settings")
            assert(setting.frameType == "aura" or setting.frameType == "groupAura", text .. ": vague Aura icon size wording must not fall through to non-Aura settings")
            assert(key:find("%.size$", 1, false), text .. ": vague Aura icon size wording must only hit icon size settings")
            assert(not key:find("filter", 1, true), text .. ": vague Aura icon size wording must not hit Aura filters")
            assert(change.relativeDelta == expectedDelta, text .. ": registry fallback picked the wrong Aura icon size delta")
        end
    end

    assertAuraIconSizeOnly("make all auras bigger", 14, "auras3.player.buff.size", 1)
    assertAuraIconSizeOnly("make all auras smaller", 14, "auras3.player.buff.size", -1)
    assertAuraIconSizeOnly("make all buffs bigger", 7, "auras3.player.buff.size", 1)
    assertAuraIconSizeOnly("make all debuffs smaller", 7, "auras3.player.debuff.size", -1)
    assertAuraIconSizeOnly("make target buffs bigger", 1, "auras3.target.buff.size", 1)
    assertAuraIconSizeOnly("make party buffs smaller", 1, "gf_party.auras.buff.size", -1)
    assertAuraIconSizeOnly("make group buffs bigger", 3, "gf_party.auras.buff.size", 1)
    assertAuraIconSizeOnly("make all aura icons bigger", 14, "auras3.player.buff.size", 1)
    assertAuraIconSizeOnly("make all buff icons bigger", 7, "auras3.player.buff.size", 1)

    local function assertAuraBulkValue(text, expectedCount, expectedFirstKey, expectedLastKey, expectedValue, expectedKeySuffix)
        local bulkParsed = A.Parse(text)
        assert(bulkParsed.kind == "changes" and #(bulkParsed.changes or {}) == expectedCount, text .. ": broad Aura geometry wording should resolve through registry aliases without Aura geometry shortcut")
        assert(bulkParsed.bulkSafe == true, text .. ": broad Aura geometry fallback should stay confirmation-safe")
        assert(bulkParsed.changes and bulkParsed.changes[1] and bulkParsed.changes[1].setting and bulkParsed.changes[1].setting.key == expectedFirstKey, text .. ": registry fallback picked the wrong first broad Aura setting")
        assert(bulkParsed.changes and bulkParsed.changes[#bulkParsed.changes] and bulkParsed.changes[#bulkParsed.changes].setting and bulkParsed.changes[#bulkParsed.changes].setting.key == expectedLastKey, text .. ": registry fallback picked the wrong last broad Aura setting")
        for i = 1, #(bulkParsed.changes or {}) do
            local change = bulkParsed.changes[i]
            local setting = change.setting or {}
            local key = tostring(setting.key or "")
            local expected = expectedValue
            if type(expectedValue) == "table" and expectedValue.byFrame == true then
                expected = expectedValue[setting.frameType]
            end
            assert(setting.frameType == "aura" or setting.frameType == "groupAura", text .. ": broad Aura geometry wording must only hit Aura settings")
            assert(key:sub(-#expectedKeySuffix) == expectedKeySuffix, text .. ": broad Aura geometry wording hit the wrong setting family: " .. key)
            assert(change.value == expected, text .. ": broad Aura geometry fallback picked the wrong value")
        end
    end

    assertAuraBulkValue("set all unit aura max icons to 10", 8, "auras3.player.buff.max", "auras3.boss.debuff.max", 10, ".max")
    assertAuraBulkValue("set all auras max icons to 10", 14, "auras3.player.buff.max", "gf_mythicraid.auras.debuff.max", 10, ".max")
    assertAuraBulkValue("set all group aura max icons to 6", 6, "gf_party.auras.buff.max", "gf_mythicraid.auras.debuff.max", 6, ".max")
    assertAuraBulkValue("set all unit aura icons per row to 8", 8, "auras3.player.buff.perRow", "auras3.boss.debuff.perRow", 8, ".perRow")
    assertAuraBulkValue("set all auras per row to 8", 14, "auras3.player.buff.perRow", "gf_mythicraid.auras.debuff.perRow", 8, ".perRow")
    assertAuraBulkValue("set all group aura icons per row to 4", 6, "gf_party.auras.buff.perRow", "gf_mythicraid.auras.debuff.perRow", 4, ".perRow")
    assertAuraBulkValue("set all unit aura spacing to 4", 8, "auras3.player.buff.spacing", "auras3.boss.debuff.spacing", 4, ".spacing")
    assertAuraBulkValue("set all auras spacing to 4", 14, "auras3.player.buff.spacing", "gf_mythicraid.auras.debuff.spacing", 4, ".spacing")
    assertAuraBulkValue("set all group aura spacing to 4", 6, "gf_party.auras.buff.spacing", "gf_mythicraid.auras.debuff.spacing", 4, ".spacing")
    assertAuraBulkValue("set all unit aura layer to 9", 8, "auras3.player.buff.layer", "auras3.boss.debuff.layer", 9, ".layer")
    assertAuraBulkValue("set all auras layer to 9", 14, "auras3.player.buff.layer", "gf_mythicraid.auras.debuff.layer", 9, ".layer")
    assertAuraBulkValue("set all group aura layer to 9", 6, "gf_party.auras.buff.layer", "gf_mythicraid.auras.debuff.layer", 9, ".layer")
    assertAuraBulkValue("set all unit aura anchor to bottom right", 8, "auras3.player.buff.anchor", "auras3.boss.debuff.anchor", "BOTTOMRIGHT", ".anchor")
    assertAuraBulkValue("set all auras anchor to bottom right", 14, "auras3.player.buff.anchor", "gf_mythicraid.auras.debuff.anchor", "BOTTOMRIGHT", ".anchor")
    assertAuraBulkValue("set all group aura anchor to bottom right", 6, "gf_party.auras.buff.anchor", "gf_mythicraid.auras.debuff.anchor", "BOTTOMRIGHT", ".anchor")
    assertAuraBulkValue("set all auras growth to up", 14, "auras3.player.buff.growth", "gf_mythicraid.auras.debuff.growth", "UP", ".growth")
    assertAuraBulkValue("set all group aura growth to right up", 6, "gf_party.auras.buff.growth", "gf_mythicraid.auras.debuff.growth", "RIGHTUP", ".growth")

    assertAuraBulkValue("set target auras icon size to 24", 2, "auras3.target.buff.size", "auras3.target.debuff.size", 24, ".size")
    assertAuraBulkValue("set party auras max icons to 10", 2, "gf_party.auras.buff.max", "gf_party.auras.debuff.max", 10, ".max")
    assertAuraBulkValue("set raid auras icons per row to 6", 2, "gf_raid.auras.buff.perRow", "gf_raid.auras.debuff.perRow", 6, ".perRow")
    assertAuraBulkValue("set target auras spacing to 4", 2, "auras3.target.buff.spacing", "auras3.target.debuff.spacing", 4, ".spacing")
    assertAuraBulkValue("set party auras layer to 9", 2, "gf_party.auras.buff.layer", "gf_party.auras.debuff.layer", 9, ".layer")
    assertAuraBulkValue("set raid auras anchor to bottom right", 2, "gf_raid.auras.buff.anchor", "gf_raid.auras.debuff.anchor", "BOTTOMRIGHT", ".anchor")
    assertAuraBulkValue("set party auras growth to up", 2, "gf_party.auras.buff.growth", "gf_party.auras.debuff.growth", "UP", ".growth")

    local function assertAuraBulkDelta(text, expectedCount, expectedFirstKey, expectedLastKey, expectedDelta, expectedKeySuffix)
        local bulkParsed = A.Parse(text)
        assert(bulkParsed.kind == "changes" and #(bulkParsed.changes or {}) == expectedCount, text .. ": broad Aura movement wording should resolve through registry aliases without Aura geometry shortcut")
        assert(bulkParsed.bulkSafe == true, text .. ": broad Aura movement fallback should stay confirmation-safe")
        assert(bulkParsed.changes and bulkParsed.changes[1] and bulkParsed.changes[1].setting and bulkParsed.changes[1].setting.key == expectedFirstKey, text .. ": registry fallback picked the wrong first Aura movement setting")
        assert(bulkParsed.changes and bulkParsed.changes[#bulkParsed.changes] and bulkParsed.changes[#bulkParsed.changes].setting and bulkParsed.changes[#bulkParsed.changes].setting.key == expectedLastKey, text .. ": registry fallback picked the wrong last Aura movement setting")
        for i = 1, #(bulkParsed.changes or {}) do
            local change = bulkParsed.changes[i]
            local setting = change.setting or {}
            local key = tostring(setting.key or "")
            assert(setting.frameType == "aura" or setting.frameType == "groupAura", text .. ": broad Aura movement wording must only hit Aura settings")
            assert(key:sub(-#expectedKeySuffix) == expectedKeySuffix, text .. ": broad Aura movement wording hit the wrong setting family: " .. key)
            assert(change.relativeDelta == expectedDelta, text .. ": broad Aura movement fallback picked the wrong delta")
        end
    end

    assertAuraBulkDelta("move target auras left", 2, "auras3.target.buff.offsetX", "auras3.target.debuff.offsetX", -10, ".offsetX")
    assertAuraBulkDelta("move party auras down 3", 2, "gf_party.auras.buff.y", "gf_party.auras.debuff.y", -3, ".y")

    A.Parser.ParseAuraGeometryShortcut = geometryShortcut
    assert(A.Parser.ParseAuraBlacklist == nil, "Unit Aura blacklist should resolve through registry action metadata, not legacy parser export")
    assert(A.Parser.ParseAuraGroupCategoryBlacklist == nil, "Group Aura category blacklist should resolve through registry action metadata, not legacy parser export")
    parsed = A.Parse("blacklist cooldowns raid buff category")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_category_blacklist_set", "category blacklist set should use the registered action")
    parsed = A.Parse("allow all party debuff categories")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_category_blacklist_clear", "category blacklist clear should use the registered action")
    parsed = A.Parse("current raid buff category blacklist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_category_blacklist_summary", "current category blacklist should use the registered action")
    parsed = A.Parse("reset target aura blacklist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_blacklist_clear_spells", "aura blacklist reset should use the registered clear action")
    parsed = A.Parse("hide Rejuvenation on target buffs")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_blacklist_add_spell", "dynamic aura hide wording should use the registered add-spell action")
    parsed = A.Parse("show Power Word: Fortitude again on player auras")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_blacklist_remove_spell", "dynamic aura show-again wording should use the registered remove-spell action")
    parsed = A.Parse("blacklist Rejuvenation for raid buff blacklist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_blacklist_add_spell", "direct group aura blacklist add should use the registered add-spell action")
    parsed = A.Parse("show raid buff aura blacklist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_blacklist_summary", "direct group aura blacklist summary should use the registered summary action")
    parsed = A.Parse("show raid buff blacklist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_blacklist_summary", "direct group aura blacklist summary without aura word should use the registered summary action")
    parsed = A.Parse("allow Rejuvenation in raid buffs")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_group_blacklist_remove_spell", "natural group allow wording should remove one exact native blacklist spell instead of enabling the whole lane")
    parsed = A.Parse("add Rejuvenation to target custom 1 whitelist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_custom_whitelist_add_spell" and parsed.args.index == 1, "custom aura whitelist add should use the registered native whitelist action")
    parsed = A.Parse("remove Rejuvenation from target custom 1 whitelist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_custom_whitelist_remove_spell" and parsed.args.index == 1, "custom aura whitelist remove should use the registered native whitelist action")
    parsed = A.Parse("show target custom 1 whitelist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_custom_whitelist_summary" and parsed.args.index == 1, "custom aura whitelist summary should stay read-only and target the requested container")
    parsed = A.Parse("clear target custom 1 whitelist")
    assert(parsed.kind == "action" and parsed.action and parsed.action.key == "aura_custom_whitelist_clear_spells" and parsed.args.index == 1, "custom aura whitelist clear should use the confirmed clear action")
    parsed = A.Parse("let buffs show on target auras")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "aura_blacklist_remove_spell"), "generic buff lane wording must not be treated as a spell blacklist removal")
    parsed = A.Parse("hide buffs on target auras")
    assert(not (parsed.kind == "action" and parsed.action and parsed.action.key == "aura_blacklist_add_spell"), "generic buff lane wording must not be treated as a spell blacklist add")
end
expectSetting("set boss target border to off", "general.bossTargetOutlineMode", "off")
-- Rondo Color is a portrait style, not a reviewed leader/assist icon pack.
-- The Assistant must retain choices instead of writing an unrelated enum.
expectKind("set player leader assist icon pack to rondo color", "ambiguous")
expectSetting("set player combat indicator symbol to default", "player.combatStateIndicatorSymbol", "DEFAULT", "combatStateIndicatorSymbol")
expectSetting("set target combat indicator symbol to swords", "target.combatStateIndicatorSymbol", "weapon_swords_crossed", "combatStateIndicatorSymbol")
expectSetting("set player rested indicator symbol to moon", "player.restedStateIndicatorSymbol", "rested_moonzzz", "restedStateIndicatorSymbol")
expectSetting("set target incoming rez indicator symbol to ankh", "target.incomingResIndicatorSymbol", "resurrection_ankh", "incomingResIndicatorSymbol")
expectAnswer("set target raid marker icon to star", "Raid Marker shows the actual WoW raid target marker")

local function smokeTrim(text)
    return tostring(text or ""):gsub("[%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function smokeEnumCandidates(setting)
    local out = {}
    for _, value in ipairs(setting.values or {}) do
        if tostring(value) ~= "" and tostring(value) ~= "__CUSTOM__" then out[#out + 1] = tostring(value) end
    end
    for alias in pairs(setting.valueAliases or {}) do out[#out + 1] = tostring(alias) end
    if #out == 0 then out[1] = "on" end
    return out
end

local function smokeNumberValue(setting)
    if setting.percent then return "50" end
    local minValue = tonumber(setting.min)
    local maxValue = tonumber(setting.max)
    if minValue and maxValue then return tostring(math.floor((minValue + maxValue) / 2)) end
    return "1"
end

local function smokeCommandForSetting(setting, phrase, enumValue)
    if setting.type == "boolean" then return "turn on " .. phrase end
    if setting.type == "number" then return "set " .. phrase .. " to " .. smokeNumberValue(setting) end
    if setting.type == "enum" then return "set " .. phrase .. " to " .. tostring(enumValue or "on") end
    if setting.type == "color" then return "set " .. phrase .. " to red" end
    -- Runtime-extensible string controls (for example status icon packs) can
    -- still publish a reviewed built-in value list. Exercise one of those
    -- values instead of inventing an invalid free-form placeholder.
    if enumValue ~= nil then return "set " .. phrase .. " to " .. tostring(enumValue) end
    return "set " .. phrase .. " to audit value"
end

local function smokeRegistryValueOk(setting, normalized, raw)
    local P = A.Parser
    local relativeDelta = setting.type == "number" and P.RelativeNumberDeltaForText(setting, normalized) or nil
    local value = P.ValueForRegistrySetting(setting, normalized, raw)
    if setting.type == "boolean" then return value ~= nil end
    return value ~= nil or relativeDelta ~= nil
end

local function smokeBestRegistryCommand(setting)
    local phrases = {}
    local label = smokeTrim(setting.label)
    if label ~= "" then phrases[#phrases + 1] = label end
    for _, alias in ipairs(setting.aliases or {}) do
        alias = smokeTrim(alias)
        if alias ~= "" then phrases[#phrases + 1] = alias end
    end
    if #phrases == 0 then phrases[1] = tostring(setting.key or "") end
    local hasDeclaredValues = type(setting.values) == "table" and #setting.values > 0
    local values = (setting.type == "enum" or hasDeclaredValues) and smokeEnumCandidates(setting) or { false }
    local P = A.Parser
    for _, phrase in ipairs(phrases) do
        for _, enumValue in ipairs(values) do
            local raw = smokeCommandForSetting(setting, phrase, enumValue ~= false and enumValue or nil)
            local normalized = P.Normalize(raw)
            if P.SettingMatchScore(setting, normalized) > 0 and smokeRegistryValueOk(setting, normalized, raw) then
                return raw
            end
        end
    end
    return smokeCommandForSetting(setting, phrases[1], values[1] ~= false and values[1] or nil)
end

do
    local P = assert(A.Parser, "Parser helpers missing")
    assert(type(P.SettingMatchScore) == "function", "SettingMatchScore helper missing")
    assert(type(P.ValueForRegistrySetting) == "function", "ValueForRegistrySetting helper missing")
    local failures = {}
    for _, setting in ipairs(A.Registry:AllSettings() or {}) do
        local raw = smokeBestRegistryCommand(setting)
        local normalized = P.Normalize(raw)
        if P.SettingMatchScore(setting, normalized) <= 0 or not smokeRegistryValueOk(setting, normalized, raw) then
            failures[#failures + 1] = tostring(setting.key or "?") .. " via " .. raw
        end
    end
    assert(#failures == 0, "Registry setting command coverage failed: " .. table.concat(failures, "; "))
end

print("assistant_parser_smoke: ok")
