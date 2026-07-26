-- External MSUF Assistant training/eval runner.
-- Usage: lua Tools/AssistantTraining/runner.lua --root <addon-root> [--out <dir>]

local function dirname(path)
    path = tostring(path or "")
    return (path:gsub("[/\\][^/\\]*$", ""))
end

local TOOL_DIR = dirname(arg and arg[0] or "Tools/AssistantTraining/runner.lua")
package.path = TOOL_DIR .. "/?.lua;" .. TOOL_DIR .. "\\?.lua;"
    .. TOOL_DIR .. "/../?.lua;" .. TOOL_DIR .. "\\..\\?.lua;" .. package.path

local stubs = require("wow_stubs")
local RuntimeManifestLoader = require("assistant_runtime_manifest_loader")

local sep = package.config:sub(1, 1)

local function normalizePath(path)
    path = tostring(path or "")
    if sep == "\\" then return (path:gsub("/", "\\")) end
    return (path:gsub("\\", "/"))
end

local function join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local part = tostring(select(i, ...) or "")
        if part ~= "" then
            part = normalizePath(part)
            part = part:gsub("[/\\]+$", "")
            part = part:gsub("^[/\\]+", "")
            if i == 1 and part:match("^%a:[/\\]") then
                part = part:gsub("[/\\]+$", "")
            end
            out[#out + 1] = part
        end
    end
    local path = table.concat(out, sep)
    path = path:gsub(sep .. sep .. "+", sep)
    if path:match("^%a:" .. sep) then return path end
    return path
end

local function loadCoverageDispositions()
    local path = join(TOOL_DIR, "..", "..", ".github", "scripts", "assistant_training_coverage_dispositions.lua")
    local chunk, err = loadfile(path)
    if not chunk then return nil, tostring(err or "unable to load coverage dispositions"), path end
    local ok, value = pcall(chunk)
    if not ok then return nil, tostring(value), path end
    if type(value) ~= "table" then return nil, "coverage dispositions did not return a table", path end
    return value, nil, path
end

local function parseArgs(argv)
    local opts = {
        root = ".",
        out = "Tools/AssistantTraining/out",
        -- Zero means the complete registry inventory. A release gate must not
        -- silently certify only the first slice of the settings list.
        generatedLimit = 0,
        seedOnly = false,
        -- Loader misses are always fatal. Keep the field for report/backward
        -- compatibility with older command lines that passed --strict-load.
        strictLoad = true,
        failSlow = false,
        slowMs = 8,
        skipAutoCoverage = false,
    }
    local optionNames = {
        generatedlimit = "generatedLimit",
        seedonly = "seedOnly",
        strictload = "strictLoad",
        failslow = "failSlow",
        slowms = "slowMs",
        skipautocoverage = "skipAutoCoverage",
    }
    local function optionName(name)
        name = tostring(name or ""):gsub("-", ""):lower()
        return optionNames[name] or name
    end
    local i = 1
    while i <= #(argv or {}) do
        local item = tostring(argv[i] or "")
        local key, value = item:match("^%-%-([^=]+)=(.*)$")
        if key then
            opts[optionName(key)] = value
        elseif item == "--root" or item == "--out" or item == "--generated-limit" or item == "--slow-ms" then
            local normalized = optionName(item:gsub("^%-%-", ""))
            opts[normalized] = argv[i + 1]
            i = i + 1
        elseif item == "--seed-only" then
            opts.seedOnly = true
        elseif item == "--skip-auto-coverage" then
            opts.skipAutoCoverage = true
        elseif item == "--strict-load" then
            opts.strictLoad = true
        elseif item == "--fail-slow" then
            opts.failSlow = true
        elseif item == "--help" or item == "-h" then
            opts.help = true
        end
        i = i + 1
    end
    opts.root = normalizePath(opts.root)
    opts.out = normalizePath(opts.out)
    opts.generatedLimit = tonumber(opts.generatedLimit) or 0
    if opts.generatedLimit < 0 then opts.generatedLimit = 0 end
    opts.slowMs = tonumber(opts.slowMs) or 8
    return opts
end

local opts = parseArgs(arg)

if opts.help then
    io.write([[
MSUF Assistant Training Runner

Options:
  --root <path>             Addon root. Default: current directory.
  --out <path>              Output directory. Default: Tools/AssistantTraining/out.
  --generated-limit <n>     Max generated inventory cases. Default: 0 (all).
  --seed-only               Run only curated regression cases.
  --strict-load             Compatibility flag; loader misses always fail.
  --fail-slow               Count parser calls over --slow-ms as failures.
  --slow-ms <n>             Mark parser calls slower than n ms. Default: 8.
]])
    os.exit(0)
end

local function readAll(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, err end
    local text = f:read("*a")
    f:close()
    return text
end

local function writeAll(path, text)
    local f, err = io.open(path, "wb")
    if not f then return nil, err end
    f:write(text or "")
    f:close()
    return true
end

local function ensureDir(path)
    path = normalizePath(path)
    if sep == "\\" then
        os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
    else
        os.execute('mkdir -p "' .. path .. '"')
    end
end

local function jsonEscape(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
    value = value:gsub('"', '\\"')
    value = value:gsub("\b", "\\b")
    value = value:gsub("\f", "\\f")
    value = value:gsub("\n", "\\n")
    value = value:gsub("\r", "\\r")
    value = value:gsub("\t", "\\t")
    return value
end

local function isArray(tbl)
    if type(tbl) ~= "table" then return false end
    local max = 0
    local count = 0
    for key in pairs(tbl) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        if key > max then max = key end
        count = count + 1
    end
    return count == max
end

local function encodeJson(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "nil" then return "null" end
    if t == "boolean" then return value and "true" or "false" end
    if t == "number" then return tostring(value) end
    if t == "string" then return '"' .. jsonEscape(value) .. '"' end
    if t ~= "table" then return '"' .. jsonEscape(tostring(value)) .. '"' end

    local childIndent = indent .. "  "
    local parts = {}
    if isArray(value) then
        for i = 1, #value do
            parts[#parts + 1] = childIndent .. encodeJson(value[i], childIndent)
        end
        if #parts == 0 then return "[]" end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end

    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, #keys do
        local key = keys[i]
        parts[#parts + 1] = childIndent .. '"' .. jsonEscape(key) .. '": ' .. encodeJson(value[key], childIndent)
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local function loadAddonFile(path, loadReport)
    local chunk, err = loadfile(path)
    if not chunk then
        loadReport[#loadReport + 1] = { path = path, ok = false, error = err }
        return false
    end
    local ok, result = pcall(chunk, "MidnightSimpleUnitFrames_Assistant", _G.MSUF_NS)
    loadReport[#loadReport + 1] = { path = path, ok = ok, error = ok and nil or tostring(result) }
    return ok
end

local function resolveCompanionRoot(root)
    local candidates = {
        root,
        join(root, "MidnightSimpleUnitFrames_Assistant"),
        join(dirname(root), "MidnightSimpleUnitFrames_Assistant"),
    }
    for i = 1, #candidates do
        local candidate = candidates[i]
        if readAll(join(candidate, "MidnightSimpleUnitFrames_Assistant.toc"))
            and readAll(join(candidate, "MSUF_AssistantRuntime.xml")) then
            return candidate
        end
    end
    return nil
end

local function assistantFilesFromXml(root)
    local companionRoot = resolveCompanionRoot(root)
    if not companionRoot then return nil, "V1 LoD companion root not found from " .. tostring(root) end
    local xmlPath = join(companionRoot, "MSUF_AssistantRuntime.xml")
    local xml, err = readAll(xmlPath)
    if not xml then return nil, err end

    local manifestCount, files, seen = 0, {}, {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        manifestCount = manifestCount + 1
        file = file:gsub("\\", "/")
        local path = join(companionRoot, file)
        if not readAll(path) then return nil, "missing V1 manifest file: " .. path end
        local base = file:match("([^/]+)$")
        if file:match("^Assistant/") and base ~= "MSUF_AssistantDashboard.lua" and not seen[path] then
            seen[path] = true
            files[#files + 1] = path
        end
    end
    if manifestCount < 3 then return nil, "V1 LoD manifest is incomplete" end
    if #files ~= manifestCount - 3 then
        return nil, "V1 parser harness inventory mismatch: manifest=" .. tostring(manifestCount) .. ", non-dashboard=" .. tostring(#files)
    end
    return files, nil, companionRoot
end

local function loadAssistant(root)
    local files, err = assistantFilesFromXml(root)
    if not files then return nil, { { path = "MSUF_Menu2.xml", ok = false, error = err } } end
    local loadReport = {}
    for i = 1, #files do
        loadAddonFile(files[i], loadReport)
    end
    return _G.MSUF_NS and _G.MSUF_NS.Assistant or nil, loadReport
end

local function ensureAssistantRuntime(root, loadReport)
    local A = _G.MSUF_NS and _G.MSUF_NS.Assistant or nil
    if A and type(A.HandleInput) == "function" then return true end
    loadReport = type(loadReport) == "table" and loadReport or {}
    local companionRoot = resolveCompanionRoot(root)
    if not companionRoot then return false end
    return loadAddonFile(join(companionRoot, "Assistant", "MSUF_Assistant.lua"), loadReport)
end

local function firstAlias(setting)
    local function pick(list, requiredText)
        if type(list) ~= "table" then return nil end
        for i = 1, #list do
            local value = tostring(list[i] or "")
            local lower = value:lower()
            local requiredMatch = true
            if requiredText then requiredMatch = value:lower():find(tostring(requiredText):lower(), 1, true) ~= nil end
            if value ~= "" and #value <= 80 and not value:find("|", 1, true)
                and not lower:match("^(set|change|make|turn|show|hide|enable|disable|open)%s+")
                and requiredMatch
            then
                return value
            end
        end
        return nil
    end
    if type(setting.intentGuard) == "function" then
        local guarded = pick(setting.exactAliases, "detached") or pick(setting.aliases, "detached") or pick(setting.aliases)
        if guarded then return guarded end
    end
    local key = tostring(setting.key or "")
    if key == "bars.classPowerHideWhenFull" then
        return pick(setting.exactAliases, "hide class resource when full")
            or pick(setting.aliases, "hide when full")
            or pick(setting.aliases)
    elseif key == "bars.classPowerHideWhenEmpty" then
        return pick(setting.exactAliases, "hide class resource when empty")
            or pick(setting.aliases, "hide when empty")
            or pick(setting.aliases)
    elseif key == "bars.classPowerHideOOC" then
        return pick(setting.exactAliases, "hide class resource out of combat")
            or pick(setting.aliases, "hide out of combat")
            or pick(setting.aliases)
    end
    if tostring(setting.key or ""):match("^bars%.playerHPBar") then
        local scoped = pick(setting.exactAliases, "class resources")
            or pick(setting.aliases, "class resources")
            or pick(setting.aliases, "class resource")
            or pick(setting.aliases, "second")
            or pick(setting.aliases, "duplicate")
        if scoped then return scoped end
    end
    if key:match("^general%.classPowerColorOverrides%.") or key:match("^general%.classPowerBgColorOverrides%.") then
        local scoped = pick(setting.aliases, "class resource")
            or pick(setting.aliases, "class power")
            or pick(setting.exactAliases, "class resource")
            or pick(setting.exactAliases, "class power")
        if scoped then return scoped end
    end
    if key:match("^gf_.*%.offsetX$") then
        local scoped = pick(setting.exactAliases, "x offset")
            or pick(setting.aliases, "x offset")
            or pick(setting.aliases, "offset x")
            or pick(setting.aliases, "horizontal")
        if scoped then return scoped end
        if tostring(setting.label or "") ~= "" then return tostring(setting.label) end
    elseif key:match("^gf_.*%.offsetY$") then
        local scoped = pick(setting.exactAliases, "y offset")
            or pick(setting.aliases, "y offset")
            or pick(setting.aliases, "offset y")
            or pick(setting.aliases, "vertical")
        if scoped then return scoped end
        if tostring(setting.label or "") ~= "" then return tostring(setting.label) end
    elseif key == "gameplay.playerTotemsAnchorFrom" then
        local scoped = pick(setting.exactAliases, "from point")
            or pick(setting.aliases, "from point")
            or pick(setting.aliases, "anchor from")
            or pick(setting.aliases, "frame from")
        if scoped then return scoped end
    elseif key == "gameplay.playerTotemsAnchorTo" then
        local scoped = pick(setting.exactAliases, "to point")
            or pick(setting.aliases, "to point")
            or pick(setting.aliases, "anchor to")
            or pick(setting.aliases, "attach")
        if scoped then return scoped end
    elseif key:match("^gf_raid%.raidMarker") or key:match("^gf_mythicraid%.raidMarker") then
        local scope = key:match("^gf_mythicraid%.") and "mythic raid frame" or "raid frame"
        local attr = key:match("%.([^%.]+)$") or ""
        local suffix = ({
            raidMarker = "",
            raidMarkerSize = " size",
            raidMarkerAnchor = " anchor",
            raidMarkerX = " x",
            raidMarkerY = " y",
            raidMarkerLayer = " layer",
            raidMarkerCustomIcon = " custom icon",
        })[attr]
        if suffix ~= nil then return scope .. " raid marker" .. suffix end
    end
    return pick(setting.exactAliases)
        or pick(setting.aliases)
        or tostring(setting.label or "") ~= "" and tostring(setting.label)
        or tostring(setting.key or "")
end

local function firstActionAlias(action)
    local function pick(list)
        if type(list) ~= "table" then return nil end
        local best
        local bestLen = 0
        for i = 1, #list do
            local value = tostring(list[i] or "")
            local wordCount = 0
            for _ in value:gmatch("%S+") do wordCount = wordCount + 1 end
            if value ~= "" and #value <= 110 and not value:find("|", 1, true) and wordCount >= 2 then
                local len = #value
                if len > bestLen then
                    best = value
                    bestLen = len
                end
            end
        end
        if best then return best end
        for i = 1, #list do
            local value = tostring(list[i] or "")
            if value ~= "" and #value <= 110 and not value:find("|", 1, true) then return value end
        end
        return nil
    end
    return pick(action and action.aliases)
        or tostring(action and action.label or "") ~= "" and tostring(action.label)
        or tostring(action and action.key or "")
end

local ACTION_SAMPLE_PROMPTS = {
    copy_unit = "copy player text options to target",
    reset_unit_position = "reset player position",
    reset_all_unit_positions = "reset all frame positions",
    reset_unit_page = "reset player options",
    reset_unit_status_indicator = "reset player raid marker status icon",
    preview_unit_status_indicator = "preview player raid marker status icon",
    clear_unit_custom_anchor = "clear player custom anchor",
    preview_castbar = "preview target castbar",
    set_castbar_test_mode = "start target castbar test mode",
    reset_focus_kick_position = "reset focus kick position",

    aura_blacklist_add_spell = "hide aura spell Rejuvenation",
    aura_blacklist_remove_spell = "allow hidden aura spell Rejuvenation",
    aura_group_category_blacklist_set = "blacklist raid buff category raid buffs",
    aura_group_blacklist_add_spell = "hide raid aura spell Rejuvenation",
    aura_group_blacklist_remove_spell = "allow raid aura spell Rejuvenation",
    aura_group_blacklist_add_preset = "blacklist preset for raid auras cooldowns",

    aura_custom_whitelist_add_spell = "whitelist Rejuvenation for target custom aura 1",
    aura_custom_whitelist_remove_spell = "remove Rejuvenation from target custom aura 1 whitelist",
    aura_custom_whitelist_clear_spells = "clear target custom aura 1 whitelist",
    aura_custom_whitelist_summary = "show target custom aura 1 whitelist",
    reset_aura_custom_container = "reset custom aura container 1 for target",

    reset_group_status_icon = "reset party raid marker status icon",
    reset_group_status_icons = "reset party status icons",
    preview_group_status_icon = "preview party raid marker status icon",
    copy_group = "copy party health and text options to raid",
    clear_group_custom_anchor = "clear party custom anchor",
    set_group_spell_indicator_aura = "turn on party holy paladin beacon of light spell indicator",
    reset_group_spell_indicator_aura = "reset party holy paladin beacon of light spell indicator",
    set_group_spell_indicator_multi_spec = "track holy paladin group spell indicator multi spec",
    move_group_spell_indicator_order = "move party holy paladin beacon of light spell indicator to slot 1",
    reset_group_corner_indicator_slot = "reset party top left corner indicator",
    reset_group_corner_indicators = "reset party corner indicators",

    set_crosshair_melee_spell = "set crosshair melee range spell to 12345",
    preview_player_totems = "preview totem frame",
    reset_player_totems_layout = "reset totem frame layout",

    apply_global_scale_preset = "apply 1080p global ui scale preset",
    set_global_font_color = "set global font color to yellow",
    reset_global_font_color = "reset global font color",
    reset_power_color_token = "reset energy power color",
    reset_class_power_color_token = "reset maelstrom class resource color",
    reset_class_power_combo_slot_colors = "reset combo point slot colors",
    reset_class_power_slot_colors = "reset holy power slot colors",
    reset_scoped_global_bars_override = "reset player bars override",
    reset_all_scoped_global_bars_overrides = "reset all bar overrides",
    reset_scoped_global_font_override = "reset player font override",
    reset_all_scoped_global_font_overrides = "reset all font overrides",
    toggle_absorb_bar_test = "test absorb bar",
    toggle_highlight_border_test = "test aggro border",
    set_dispel_border_test_type = "set dispel border test type to Magic",
    reset_class_colors = "reset class bar colors",
    reset_bar_background_color = "reset bar background color",
    reset_unitframe_colors = "reset unit frame colors",
    reset_health_gradient_colors = "reset health gradient colors",
    reset_bar_gradient_colors = "reset bar gradient colors",
    reset_npc_type_colors = "reset npc type colors",
    reset_bar_colors = "reset bar colors",
    reset_dispel_colors = "reset dispel colors",
    reset_castbar_colors = "reset castbar colors",
    reset_gameplay_colors = "reset gameplay colors",
    reset_aura_colors = "reset aura colors",
    reset_portrait_colors = "reset portrait colors",
    reset_resource_colors = "reset resource colors",

    open_recovery_tools = "open recovery tools",
    open_dashboard_panel = "open scaling tools",
    set_dashboard_panel = "toggle scaling tools",
    set_nav_section = "open group frames navigation section",
    set_nav_search_intro = "reset search intro",
    set_menu_selector_state = "select all group copy categories",
    menu_window_close = "close msuf menu",
    menu_window_minimize = "minimize msuf menu",
    menu_window_maximize = "maximize msuf menu",
    menu_window_restore = "restore msuf menu",
    menu_reset_current_page_prompt = "reset current menu page",
    factory_reset_all = "factory reset all",
    ["assistant.action.history.undo"] = "undo last assistant change",
    ["assistant.action.history.redo"] = "redo last assistant change",
    menu_history_undo = "undo menu change",
    menu_history_redo = "redo menu change",
    menu_history_reset_session = "reset menu session changes",

    reset_profile = "reset active profile",
    profile_summary = "show profile summary",
    copy_wago_profiles_link = "copy wago profiles link",
    export_profile = "export current profile",
    open_profile_import = "open profile import",
    import_profile_string = "import profile MSUF3:abcd",
    import_profile_string_new = "import profile MSUF3:abcd as new profile Training Copy",
    import_legacy_profile_string = "import legacy profile MSUF3:abcd",
    delete_profile = "delete profile Training Delete",
    switch_profile = "switch to profile Training Profile",
    create_profile = "create profile Training New",
    copy_profile = "copy current profile to Training Backup",
    set_spec_profile = "set spec profile frost to Training Profile",
    clear_spec_profile = "clear spec profile frost",

    ["assistant.action.editMode.enter"] = "enter edit mode",
    ["assistant.action.editMode.exit"] = "exit edit mode",
    ["assistant.action.editMode.cancel"] = "cancel edit mode",
    ["assistant.action.editMode.toggle"] = "toggle edit mode",
    ["assistant.action.editMode.preview"] = "turn on edit mode preview",
    ["assistant.action.editMode.bossPreview"] = "turn on boss frames preview",
    ["assistant.action.editMode.auras"] = "turn on edit mode aura preview",
    ["assistant.action.editMode.groupPreview"] = "turn on party frame preview in edit mode",
    ["assistant.action.editMode.snap"] = "turn on edit mode snap",
    ["assistant.action.editMode.grid"] = "turn on edit mode grid",
    ["assistant.action.editMode.gridStep"] = "set edit mode grid spacing to 20",
    ["assistant.action.editMode.backgroundOpacity"] = "set edit mode background opacity to 50",
    ["assistant.action.editMode.cdm"] = "turn on edit mode cooldown manager anchor",
    ["assistant.action.editMode.undo"] = "undo edit mode position change",
    ["assistant.action.editMode.redo"] = "redo edit mode position change",
    ["assistant.action.editMode.resetPosition"] = "reset selected edit mode position",
    ["assistant.action.editMode.anchorPicker"] = "open edit mode anchor picker",
    ["assistant.diagnostic.editMode.status"] = "edit mode status",

    ["assistant.workflow.status"] = "assistant workflow status",
    ["assistant.workflow.cancel"] = "cancel assistant workflow",
    ["assistant.panel.close"] = "close assistant panel",
    dashboard_page_back = "open previous page",
    dashboard_page_forward = "open next page",
    start_unit_custom_anchor_picker = "open player custom anchor picker",
    start_group_custom_anchor_picker = "open party custom anchor picker",
    cancel_custom_anchor_picker = "cancel custom anchor picker",
    custom_anchor_picker_status = "custom anchor picker status",
    copy_profile_from_to = "copy profile Training Source to Training Destination",
    start_profile_copy_flow = "copy from profile Training Source",
    rename_profile = "rename profile Training Source to Training Renamed",
    start_profile_rename_flow = "rename profile Training Source",
    open_page = "open player frame page",
    assistant_status = "assistant status",
    assistant_nomatch_telemetry = "show no match telemetry",
    assistant_nomatch_worklist = "show action no match worklist",
    assistant_nomatch_clear = "clear no match telemetry",
    assistant_help = "assistant help",
    assistant_scope_help = "help for player frame",
    copy_support_link = "copy discord support link",
    support_links_summary = "show support links",
    diagnose_castbar_visibility = "diagnose target castbar",
    diagnose_unit_visibility = "diagnose player frame",
    diagnose_group_visibility = "diagnose party frames",
    diagnose_aura_visibility = "diagnose target buffs",
    clear_broken_spec_profile_mappings = "clear broken spec profile mappings",
    diagnose_profile_status = "diagnose profiles",
    diagnose_class_power_status = "diagnose class resources",
    diagnose_gameplay_helpers = "diagnose gameplay helpers",
    diagnose_dashboard_setup = "diagnose dashboard",
    guided_setup = "guided setup",
    guided_setup_step = "show setup",
}

local function sampleActionPrompt(action)
    local key = tostring(action and action.key or "")
    local sample = ACTION_SAMPLE_PROMPTS[key]
    if type(sample) == "string" and sample ~= "" then return sample end
    return nil
end

local SCOPE_TERMS = {
    player = { "player", "self" },
    target = { "target" },
    targettarget = { "targettarget", "target of target", "tot" },
    focustarget = { "focustarget", "focus target" },
    focus = { "focus" },
    pet = { "pet" },
    boss = { "boss" },
    party = { "party" },
    raid = { "raid" },
    mythicraid = { "mythicraid", "mythic raid" },
    gf_party = { "party" },
    gf_raid = { "raid" },
    gf_mythicraid = { "mythicraid", "mythic raid" },
    priority = { "priority frames", "pinned frames", "priority" },
    gf_priority = { "priority frames", "pinned frames", "priority" },
}

local SCOPE_PREFIX = {
    player = "player",
    target = "target",
    targettarget = "target of target",
    focustarget = "focus target",
    focus = "focus",
    pet = "pet",
    boss = "boss",
    party = "party",
    raid = "raid",
    mythicraid = "mythic raid",
    gf_party = "party",
    gf_raid = "raid",
    gf_mythicraid = "mythic raid",
    priority = "priority frames",
    gf_priority = "priority frames",
}

local function normalizeWords(text)
    return tostring(text or ""):lower():gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function containsPhrase(text, phrase)
    text = " " .. normalizeWords(text) .. " "
    phrase = " " .. normalizeWords(phrase) .. " "
    return phrase ~= "  " and text:find(phrase, 1, true) ~= nil
end

local function scopedAlias(setting, alias)
    alias = tostring(alias or "")
    local unit = tostring(setting and setting.unit or "")
    if unit == "" or unit == "global" or unit == "shared" then return alias end
    local terms = SCOPE_TERMS[unit]
    if type(terms) == "table" then
        for i = 1, #terms do
            if containsPhrase(alias, terms[i]) then return alias end
        end
    end
    local prefix = SCOPE_PREFIX[unit]
    if not prefix or prefix == "" then return alias end
    return prefix .. " " .. alias
end

local function sampleNumber(setting)
    local minValue = tonumber(setting.min)
    local maxValue = tonumber(setting.max)
    local step = tonumber(setting.step) or 1
    local value
    if minValue and maxValue then
        value = minValue + ((maxValue - minValue) * 0.5)
    elseif minValue then
        value = minValue + (step * 4)
    elseif maxValue then
        value = maxValue - (step * 4)
    else
        value = 20
    end
    if step >= 1 then value = math.floor(value + 0.5) end
    return value
end

local function sampleEnum(setting)
    if type(setting.values) ~= "table" then return nil end
    for i = 1, #setting.values do
        local value = setting.values[i]
        if value ~= nil and tostring(value) ~= "" then return value end
    end
    return nil
end

local function sampleString(setting)
    local key = tostring(setting and setting.key or ""):lower()
    local label = tostring(setting and setting.label or ""):lower()
    if key:find("outline", 1, true) or label:find("outline", 1, true) then return "OUTLINE" end
    if key:find("%.spells", 1, true) or label:find("spell", 1, true) then return "12345,67890" end
    if key:find("separator", 1, true) or label:find("separator", 1, true) or label:find("delimiter", 1, true) then return "/" end
    if key:find("entertext", 1, true) or label:find("enter text", 1, true) then return "Combat" end
    if key:find("leavetext", 1, true) or label:find("leave text", 1, true) then return "Clear" end
    if key:find("anchorframename", 1, true) or key:find("customanchorframe", 1, true) or label:find("anchor frame", 1, true) then return "UIParent" end
    if key:find("font", 1, true) or label:find("font", 1, true) then return "Friz Quadrata TT" end
    if key:find("texture", 1, true) or label:find("texture", 1, true) then return "Minimalist" end
    if key:find("style", 1, true) or label:find("style", 1, true) or label:find("icon pack", 1, true) then return "default" end
    return "custom value"
end

local seedCases = {
    {
        id = "power-color-energy-yellow",
        prompt = "change the color of energy to yellow",
        expect = { kind = "changes", key = "general.powerColorOverrides.ENERGY", valueColor = "yellow" },
        category = "power-color",
    },
    {
        id = "power-color-energy-default",
        prompt = "change the color of energy to default",
        expect = { kind = "action" },
        category = "power-color-reset",
    },
    {
        id = "power-text-energy-default",
        prompt = "change the color of powertext from energy to default",
        expect = { kind = "changes", key = "fontScope.shared.colorPowerTextByType", value = "DEFAULT" },
        category = "from-to-font-mode",
    },
    {
        id = "power-text-default-energy",
        prompt = "change the color of powertext from default to energy",
        expect = { kind = "changes", key = "fontScope.shared.colorPowerTextByType", value = "RESOURCE" },
        category = "from-to-font-mode",
    },
    {
        id = "castbar-color-needs-scope",
        prompt = "change castbar color from green to red",
        expect = { kind = "ambiguous" },
        category = "safe-clarification",
    },
    {
        id = "action-input-reset-custom-aura-needs-target",
        prompt = "reset custom aura container",
        expect = { kind = "answer", status = "ambiguous", textContains = { "kept MSUF unchanged" } },
        category = "safe-action-input-clarification",
    },
    {
        id = "action-input-dashboard-panel-needs-target",
        prompt = "toggle dashboard panel",
        expect = { kind = "answer", status = "ambiguous", textContains = { "kept MSUF unchanged" } },
        category = "safe-action-input-clarification",
    },
    {
        id = "edit-mode-background-opacity-percent",
        prompt = "set edit mode background opacity to 50",
        expect = { kind = "action", actionKey = "assistant.action.editMode.backgroundOpacity", args = { value = 0.5 } },
        category = "edit-mode-action-input",
    },
    {
        id = "edit-mode-background-opacity-one-percent-word",
        prompt = "set edit mode background opacity to 1 percent",
        expect = { kind = "action", actionKey = "assistant.action.editMode.backgroundOpacity", args = { value = 0.01 } },
        category = "edit-mode-action-input",
    },
    {
        id = "edit-mode-background-opacity-one-percent-symbol",
        prompt = "set edit mode background opacity to 1%",
        expect = { kind = "action", actionKey = "assistant.action.editMode.backgroundOpacity", args = { value = 0.01 } },
        category = "edit-mode-action-input",
    },
    {
        id = "combo-point-red-yellow",
        prompt = "change combo point color from red to yellow",
        expect = { kind = "changes", valueColor = "yellow" },
        category = "from-to-color",
    },
    {
        id = "party-off-on",
        prompt = "change party frames from off to on",
        expect = { kind = "changes", value = true },
        category = "from-to-boolean",
    },
    {
        id = "party-on-off",
        prompt = "change party frames from on to off",
        expect = { kind = "changes", value = false },
        category = "from-to-boolean",
    },
    {
        id = "name-color-default-class",
        prompt = "change name text color from default to class",
        expect = { kind = "changes", key = "fontScope.shared.nameColorMode", value = "CLASS" },
        category = "from-to-font-mode",
    },
    {
        id = "health-color-default-health",
        prompt = "change health text color from default to health",
        expect = { kind = "changes", key = "fontScope.shared.colorHealthTextByHealth", value = "HEALTH" },
        category = "from-to-font-mode",
    },
    {
        id = "global-font-family-friz",
        prompt = "set font to Friz Quadrata TT",
        expect = { kind = "changes", key = "general.fontKey", value = "Fonts\\FRIZQT___CYR.TTF" },
        category = "global-font",
    },
    {
        id = "global-font-family-expressway-human",
        prompt = "Can you change all Fonts to Expressway ?",
        expect = { kind = "changes", key = "general.fontKey", value = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf" },
        category = "global-font",
    },
    {
        id = "misc-menu-font-expressway-human",
        prompt = "change the font of the msuf menu to expressway",
        expect = { kind = "changes", key = "general.menuFontKey", value = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway Regular.ttf" },
        category = "miscellaneous",
    },
    {
        id = "global-font-rendering-smooth",
        prompt = "set font rendering to SMOOTH",
        expect = { kind = "changes", key = "fontScope.shared.fontMonochrome", value = "SMOOTH" },
        category = "global-font",
    },
    {
        id = "global-custom-font-color-fast",
        prompt = "set custom font color to yellow",
        expect = { kind = "changes", key = "general.customFontColor", valueColor = "yellow" },
        category = "global-font",
    },
    {
        id = "global-font-color-action-not-setting",
        prompt = "set global font color to yellow",
        expect = { kind = "action", actionKey = "set_global_font_color" },
        category = "global-font",
    },
    {
        id = "warrior-class-color-fast",
        prompt = "set warrior class color to yellow",
        expect = { kind = "changes", key = "classColors.WARRIOR", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "rogue-class-color-human",
        prompt = "Can you make the color for Rogue Red ?",
        expect = { kind = "changes", key = "classColors.ROGUE", valueColor = "red" },
        category = "global-color",
    },
    {
        id = "bar-background-tint-fast",
        prompt = "set bar background tint to yellow",
        expect = { kind = "changes", key = "general.classBarBgColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "bar-background-hp-fast",
        prompt = "turn on background follows hp color",
        expect = { kind = "changes", key = "general.barBgMatchHPColor", value = true },
        category = "global-color",
    },
    {
        id = "bar-background-class-fast",
        prompt = "turn on health background follows class color",
        expect = { kind = "changes", key = "general.barBgClassColor", value = true },
        category = "global-color",
    },
    {
        id = "player-power-left-slot-x-fast",
        prompt = "set player power left slot x to 0",
        expect = { kind = "changes", key = "player.powerTextLeftOffsetX", value = 0 },
        category = "text-slot-offset",
    },
    {
        id = "raid-power-center-slot-y-fast",
        prompt = "set raid power center slot y to 0",
        expect = { kind = "changes", key = "gf_raid.powerTextCenterOffsetY", value = 0 },
        category = "text-slot-offset",
    },
    {
        id = "dark-mode-custom-color-toggle-fast",
        prompt = "turn on custom color in dark mode",
        expect = { kind = "changes", key = "general.darkBgCustomColor", value = true },
        category = "global-color",
    },
    {
        id = "unified-bar-color-fast",
        prompt = "set unified bar color to yellow",
        expect = { kind = "changes", key = "general.unifiedBarColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "dark-mode-bar-color-fast",
        prompt = "set dark mode bar color to 0.5",
        expect = { kind = "changes", key = "general.darkBarGray", value = 0.5 },
        category = "global-color",
    },
    {
        id = "power-bar-background-color-fast",
        prompt = "set power bar background color to yellow",
        expect = { kind = "changes", key = "general.powerBarBgColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "power-background-matches-hp-fast",
        prompt = "turn on power background matches hp",
        expect = { kind = "changes", key = "general.powerBarBgMatchBarColor", value = true },
        category = "global-color",
    },
    {
        id = "absorb-bar-color-fast",
        prompt = "set absorb bar color to yellow",
        expect = { kind = "changes", key = "general.absorbBarColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "heal-absorb-bar-color-fast",
        prompt = "set heal absorb bar color to yellow",
        expect = { kind = "changes", key = "general.healAbsorbBarColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "aggro-border-color-fast",
        prompt = "set aggro border color to yellow",
        expect = { kind = "changes", key = "general.aggroBorderColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "purge-border-color-fast",
        prompt = "set purge border color to yellow",
        expect = { kind = "changes", key = "general.purgeBorderColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "bar-outline-color-fast",
        prompt = "set bar outline color to yellow",
        expect = { kind = "changes", key = "general.barOutlineColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "player-bar-outline-color-fast",
        prompt = "set player bar outline color to yellow",
        expect = { kind = "changes", key = "barScope.player.barOutlineColor", valueColor = "yellow" },
        category = "scoped-bar-color",
    },
    {
        id = "raid-bar-outline-color-fast",
        prompt = "set raid bar outline color to yellow",
        expect = { kind = "changes", key = "barScope.gf_raid.barOutlineColor", valueColor = "yellow" },
        category = "scoped-bar-color",
    },
    {
        id = "maelstrom-power-color-fast",
        prompt = "set maelstrom power color to yellow",
        expect = { kind = "changes", key = "general.powerColorOverrides.MAELSTROM", valueColor = "yellow" },
        category = "power-color",
    },
    {
        id = "astral-power-color-fast",
        prompt = "set astral power color to yellow",
        expect = { kind = "changes", key = "general.powerColorOverrides.LUNAR_POWER", valueColor = "yellow" },
        category = "power-color",
    },
    {
        id = "focus-power-color-fast",
        prompt = "set focus power color to yellow",
        expect = { kind = "changes", key = "general.powerColorOverrides.FOCUS", valueColor = "yellow" },
        category = "power-color",
    },
    -- Dispel color seeds removed 2026-07-03: the dispel color feature was
    -- deleted from MSUF and will not return (keys general.hlDispelColor*,
    -- general.dispelType* no longer exist as registered settings).
    {
        id = "player-castbar-color-override-fast",
        prompt = "turn on player castbar color override",
        expect = { kind = "changes", key = "general.playerCastbarOverrideEnabled", value = true },
        category = "global-color",
    },
    {
        id = "interrupt-unavailable-fill-color-fast",
        prompt = "set interrupt unavailable fill color to yellow",
        expect = { kind = "changes", key = "general.castbarInterruptUnavailableColor", valueColor = "yellow" },
        category = "castbar-color",
    },
    {
        id = "interrupt-feedback-color-fast",
        prompt = "set interrupt feedback color to yellow",
        expect = { kind = "changes", key = "general.castbarInterruptFeedbackColor", valueColor = "yellow" },
        category = "castbar-color",
    },
    {
        id = "noninterruptible-cast-color-fast",
        prompt = "set non interruptible cast color to yellow",
        expect = { kind = "changes", key = "general.castbarNonInterruptibleColor", valueColor = "yellow" },
        category = "castbar-color",
    },
    {
        id = "interruptible-cast-color-fast",
        prompt = "set interruptible cast color to yellow",
        expect = { kind = "changes", key = "general.castbarInterruptibleColor", valueColor = "yellow" },
        category = "castbar-color",
    },
    {
        id = "castbar-text-color-fast",
        prompt = "set castbar text color to yellow",
        expect = { kind = "changes", key = "general.castbarFontColor", valueColor = "yellow" },
        category = "castbar-color",
    },
    {
        id = "castbar-target-name-color-fast",
        prompt = "set castbar target name color to red",
        expect = { kind = "changes", key = "general.castbarTargetNameColor", valueColor = "red" },
        category = "castbar-color",
    },
    {
        id = "player-castbar-override-color-fast",
        prompt = "set player castbar override color to yellow",
        expect = { kind = "changes", key = "general.playerCastbarOverrideColor", valueColor = "yellow" },
        category = "castbar-color",
    },
    {
        id = "player-castbar-override-mode-class-fast",
        prompt = "set player castbar override mode to CLASS",
        expect = { kind = "changes", key = "general.playerCastbarOverrideMode", value = "CLASS" },
        category = "castbar-color",
    },
    {
        id = "mouseover-highlight-toggle-fast",
        prompt = "turn on mouseover highlight",
        expect = { kind = "changes", key = "general.highlightEnabled", value = true },
        category = "global-color",
    },
    {
        id = "mouseover-highlight-color-fast",
        prompt = "set mouseover highlight color to yellow",
        expect = { kind = "changes", key = "general.highlightColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "boss-target-highlight-color-fast",
        prompt = "set boss target highlight color to yellow",
        expect = { kind = "changes", key = "general.bossTargetHighlightColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "combat-timer-text-color-fast",
        prompt = "set combat timer text color to yellow",
        expect = { kind = "changes", key = "gameplay.combatTimerColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "combat-enter-text-color-fast",
        prompt = "set combat enter text color to yellow",
        expect = { kind = "changes", key = "gameplay.combatStateEnterColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "combat-leave-text-color-fast",
        prompt = "set combat leave text color to yellow",
        expect = { kind = "changes", key = "gameplay.combatStateLeaveColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "crosshair-in-range-color-fast",
        prompt = "set crosshair in range color to yellow",
        expect = { kind = "changes", key = "gameplay.crosshairInRangeColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "crosshair-out-of-range-color-fast",
        prompt = "set crosshair out of range color to yellow",
        expect = { kind = "changes", key = "gameplay.crosshairOutRangeColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "class-resource-chi-background-color-exact-fast",
        prompt = "set chi class power background color to yellow",
        expect = { kind = "changes", key = "general.classPowerBgColorOverrides.CHI", valueColor = "yellow" },
        category = "exact-color",
    },
    {
        id = "class-resource-arcane-charges-color-exact-fast",
        prompt = "set arcane charges class resource color to yellow",
        expect = { kind = "changes", key = "general.classPowerColorOverrides.ARCANE_CHARGES", valueColor = "yellow" },
        category = "exact-color",
    },
    {
        id = "combo-point-slot-duplicate-set-exact-fast",
        prompt = "set set combo point slot 1 to yellow",
        expect = { kind = "changes", key = "general.classPowerColorOverrides.COMBO_POINTS_1", valueColor = "yellow" },
        category = "exact-color",
    },
    {
        id = "group-corner-custom-color-exact-fast",
        prompt = "set raid top right corner custom color to yellow",
        expect = { kind = "changes", key = "gf_raid.ciCustomTR.color", valueColor = "yellow" },
        category = "exact-color",
    },
    {
        id = "own-buff-highlight-color-fast",
        prompt = "set own buff highlight color to yellow",
        expect = { kind = "changes", key = "general.aurasOwnBuffHighlightColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "own-debuff-highlight-color-fast",
        prompt = "set own debuff highlight color to yellow",
        expect = { kind = "changes", key = "general.aurasOwnDebuffHighlightColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "health-color-gradient-toggle-fast",
        prompt = "turn on health color gradient",
        expect = { kind = "changes", key = "general.enableHealthGradient", value = true },
        category = "global-color",
    },
    {
        id = "health-gradient-low-color-fast",
        prompt = "set health gradient low to yellow",
        expect = { kind = "changes", key = "general.healthGradientLow", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "health-gradient-mid-color-fast",
        prompt = "set health gradient mid to yellow",
        expect = { kind = "changes", key = "general.healthGradientMid", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "health-gradient-high-color-fast",
        prompt = "set health gradient high to yellow",
        expect = { kind = "changes", key = "general.healthGradientHigh", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "bar-gradient-colors-reset-action",
        prompt = "reset bar gradient colors",
        expect = { kind = "action", actionKey = "reset_bar_gradient_colors" },
        category = "global-color",
    },
    {
        id = "friendly-npc-color-fast",
        prompt = "set friendly npc color to yellow",
        expect = { kind = "changes", key = "npcColors.friendly", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "neutral-npc-color-fast",
        prompt = "set neutral npc color to yellow",
        expect = { kind = "changes", key = "npcColors.neutral", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "enemy-npc-color-fast",
        prompt = "set enemy npc color to yellow",
        expect = { kind = "changes", key = "npcColors.enemy", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "dead-npc-color-fast",
        prompt = "set dead npc color to yellow",
        expect = { kind = "changes", key = "npcColors.dead", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "pet-frame-color-fast",
        prompt = "set pet frame color to yellow",
        expect = { kind = "changes", key = "general.petFrameColor", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "npc-type-colors-fast",
        prompt = "turn on npc type colors",
        expect = { kind = "changes", key = "general.npcColorMode", value = true },
        category = "global-color",
    },
    {
        id = "npc-type-colors-target-fast",
        prompt = "turn on npc type colors target",
        expect = { kind = "changes", key = "general.npcTypeTarget", value = true },
        category = "global-color",
    },
    {
        id = "npc-type-colors-focus-fast",
        prompt = "turn on npc type colors focus",
        expect = { kind = "changes", key = "general.npcTypeFocus", value = true },
        category = "global-color",
    },
    {
        id = "npc-type-colors-boss-fast",
        prompt = "turn on npc type colors boss",
        expect = { kind = "changes", key = "general.npcTypeBoss", value = true },
        category = "global-color",
    },
    {
        id = "npc-type-colors-tot-fast",
        prompt = "turn on npc type colors targettarget",
        expect = { kind = "changes", key = "general.npcTypeToT", value = true },
        category = "global-color",
    },
    {
        id = "boss-npc-type-color-fast",
        prompt = "set boss npc type color to yellow",
        expect = { kind = "changes", key = "npcColors.npcBoss", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "miniboss-npc-type-color-fast",
        prompt = "set miniboss npc type color to yellow",
        expect = { kind = "changes", key = "npcColors.npcMiniboss", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "caster-npc-type-color-fast",
        prompt = "set caster npc type color to yellow",
        expect = { kind = "changes", key = "npcColors.npcCaster", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "melee-npc-type-color-fast",
        prompt = "set melee npc type color to yellow",
        expect = { kind = "changes", key = "npcColors.npcMelee", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "regular-npc-type-color-fast",
        prompt = "set regular npc type color to yellow",
        expect = { kind = "changes", key = "npcColors.npcRegular", valueColor = "yellow" },
        category = "global-color",
    },
    {
        id = "class-resources-hp-bar-fast",
        prompt = "turn on class resources hp bar",
        expect = { kind = "changes", key = "bars.playerHPBarEnabled", value = true },
        category = "class-resource",
    },
    {
        id = "class-resources-hp-bar-off-fast",
        prompt = "turn off class resources hp bar",
        expect = { kind = "changes", key = "bars.playerHPBarEnabled", value = false },
        category = "class-resource",
    },
    {
        id = "player-raid-marker-y-fast",
        prompt = "set player raid marker y offset to 0",
        expect = { kind = "changes", key = "player.raidMarkerOffsetY", value = 0 },
        category = "raid-marker",
    },
    {
        id = "party-raid-marker-x-fast",
        prompt = "set party raid marker x to 0",
        expect = { kind = "changes", key = "gf_party.raidMarkerX", value = 0 },
        category = "raid-marker",
    },
    {
        id = "player-font-text-opacity",
        prompt = "set player text opacity to 0.8",
        expect = { kind = "changes", key = "fontScope.player.fontTextAlpha", value = 0.8 },
        category = "global-font",
    },
    {
        id = "direction-right-left",
        prompt = "move target castbar from right to left",
        expect = { kind = "changes" },
        category = "from-to-direction",
    },
    {
        id = "boss-castbar-width-mode-manual",
        prompt = "set boss castbar width mode to manual",
        expect = { kind = "changes", key = "general.bossCastbarMatchWidth", value = "manual" },
        category = "castbar-width-mode",
    },
    {
        id = "global-dead-text-ghost",
        prompt = "turn on dead text ghost units",
        expect = { kind = "changes", key = "general.statusIndicators.showGhost", value = true },
        category = "status-text",
    },
    {
        id = "global-status-icons-midnight",
        prompt = "turn on status icons midnight style",
        expect = { kind = "changes", key = "general.statusIconsUseMidnightStyle", value = true },
        category = "status-icons",
    },
    {
        id = "raid-role-icon-tanks",
        prompt = "turn on raid role icon tanks",
        expect = { kind = "changes", key = "gf_raid.roleIconShowTank", value = true },
        category = "group-status-icons",
    },
    {
        id = "party-raid-marker-x",
        prompt = "set party raid marker x to 0",
        expect = { kind = "changes", key = "gf_party.raidMarkerX", value = 0 },
        category = "group-status-icons",
    },
    {
        id = "raid-group-border-color",
        prompt = "set raid group border color to yellow",
        expect = { kind = "changes", key = "gf_raid.groupBorderColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "party-group-backdrop-color",
        prompt = "set party group backdrop color to yellow",
        expect = { kind = "changes", key = "gf_party.bgColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "party-dead-background-color",
        prompt = "set party dead background color to yellow",
        expect = { kind = "changes", key = "gf_party.deadBgColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "party-dead-background-enabled",
        prompt = "turn on party dead background",
        expect = { kind = "changes", key = "gf_party.deadBgEnabled", value = true },
        category = "group-dead-background",
    },
    {
        id = "party-dead-background-opacity",
        prompt = "set party dead background opacity to 0.525",
        expect = { kind = "changes", key = "gf_party.deadBgA", value = 0.525 },
        category = "group-dead-background",
    },
    {
        id = "party-dead-background-offline-tint",
        prompt = "turn on party tint offline members",
        expect = { kind = "changes", key = "gf_party.deadBgOffline", value = true },
        category = "group-dead-background",
    },
    {
        id = "party-debuff-stripe-color",
        prompt = "set party debuff stripe color to yellow",
        expect = { kind = "changes", key = "gf_party.debuffStripeColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "raid-target-highlight-color",
        prompt = "set raid target highlight color to yellow",
        expect = { kind = "changes", key = "gf_raid.targetColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "raid-focus-highlight-color",
        prompt = "set raid focus highlight color to yellow",
        expect = { kind = "changes", key = "gf_raid.hlFocusColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "raid-custom-health-color",
        prompt = "set raid custom health color to yellow",
        expect = { kind = "changes", key = "gf_raid.healthCustomColor", valueColor = "yellow" },
        category = "group-color",
    },
    {
        id = "party-frame-anchor-free",
        prompt = "set party frames anchor to player to FREE",
        expect = { kind = "changes", key = "gf_party.anchorToFrame", value = "FREE" },
        category = "group-anchor",
    },
    {
        id = "party-frame-anchor-point",
        prompt = "set party anchor point to TOPLEFT",
        expect = { kind = "changes", key = "gf_party.anchorPoint", value = "TOPLEFT" },
        category = "group-anchor",
    },
    {
        id = "mythicraid-frame-anchor-free",
        prompt = "set mythic raid frames anchor to player to FREE",
        expect = { kind = "changes", key = "gf_mythicraid.anchorToFrame", value = "FREE" },
        category = "group-anchor",
    },
    {
        id = "party-class-color-mode-global",
        prompt = "set party class color to GLOBAL",
        expect = { kind = "changes", key = "gf_party.gfBarMode", value = "GLOBAL" },
        category = "group-bar-color-mode",
    },
    {
        id = "party-health-color-mode-class",
        prompt = "set party health color mode to CLASS",
        expect = { kind = "changes", key = "gf_party.healthColorMode", value = "CLASS" },
        category = "group-bar-color-mode",
    },
    {
        id = "mythicraid-class-color-mode-global",
        prompt = "set mythic raid class color to GLOBAL",
        expect = { kind = "changes", key = "gf_mythicraid.gfBarMode", value = "GLOBAL" },
        category = "group-bar-color-mode",
    },
    {
        id = "party-hide-name-dead-offline",
        prompt = "turn on party hide name on dead offline",
        expect = { kind = "changes", key = "gf_party.hideNameOnDeadOffline", value = true },
        category = "group-name-text",
    },
    {
        id = "mythicraid-hide-name-dead-offline",
        prompt = "turn on mythicraid hide name on dead offline",
        expect = { kind = "changes", key = "gf_mythicraid.hideNameOnDeadOffline", value = true },
        category = "group-name-text",
    },
    {
        id = "party-hp-text-delimiter-empty",
        prompt = "set party hp text delimiter to  ",
        expect = { kind = "changes", key = "gf_party.textDelimiter", value = false },
        category = "group-text-format",
    },
    {
        id = "raid-power-text-delimiter-empty",
        prompt = "set raid power text delimiter to  ",
        expect = { kind = "changes", key = "gf_raid.powerTextDelimiter", value = false },
        category = "group-text-format",
    },
    {
        id = "party-reverse-hp-text",
        prompt = "turn on party reverse hp text",
        expect = { kind = "changes", key = "gf_party.hpTextReverse", value = true },
        category = "group-text-format",
    },
    {
        id = "party-hp-text-x",
        prompt = "set party hp text x to 0",
        expect = { kind = "changes", key = "gf_party.hpOffsetX", value = 0 },
        category = "group-text-format",
    },
    {
        id = "party-hp-text-y",
        prompt = "set party hp text y to 0",
        expect = { kind = "changes", key = "gf_party.hpOffsetY", value = 0 },
        category = "group-text-format",
    },
    {
        id = "raid-power-text-x",
        prompt = "set raid power text x to 0",
        expect = { kind = "changes", key = "gf_raid.powerOffsetX", value = 0 },
        category = "group-text-format",
    },
    {
        id = "raid-hp-text-layer",
        prompt = "set raid hp text layer to 8",
        expect = { kind = "changes", key = "gf_raid.textLayer", value = 8 },
        category = "group-text-format",
    },
    {
        id = "party-dispel-overlay",
        prompt = "turn on party dispel overlay",
        expect = { kind = "changes", key = "gf_party.dispelOverlayEnabled", value = true },
        category = "group-dispel-overlay",
    },
    {
        id = "party-dispel-overlay-detects",
        prompt = "set party dispel overlay detects to BORDER",
        expect = { kind = "changes", key = "gf_party.dispelOverlayTrigger", value = "BORDER" },
        category = "group-dispel-overlay",
    },
    {
        id = "party-dispel-overlay-style",
        prompt = "set party dispel overlay style to FULL",
        expect = { kind = "changes", key = "gf_party.dispelOverlayStyle", value = "FULL" },
        category = "group-dispel-overlay",
    },
    {
        id = "party-dispel-overlay-current-health",
        prompt = "turn on party dispel overlay current health",
        expect = { kind = "changes", key = "gf_party.dispelOverlayOnHealth", value = true },
        category = "group-dispel-overlay",
    },
    {
        id = "party-range-fade-affects-frame",
        prompt = "set party range fade affects to frame",
        expect = { kind = "changes", key = "gf_party.rangeFadeLayerMode", value = "frame" },
        category = "group-range-fade",
    },
    {
        id = "party-range-fade-alpha",
        prompt = "set party range fade alpha to 0.5",
        expect = { kind = "changes", key = "gf_party.rangeFadeAlpha", value = 0.5 },
        category = "group-range-fade",
    },
    {
        id = "party-offline-alpha",
        prompt = "set party offline alpha to 0.5",
        expect = { kind = "changes", key = "gf_party.offlineAlpha", value = 0.5 },
        category = "group-range-fade",
    },
    {
        id = "party-health-fade",
        prompt = "turn on party health fade",
        expect = { kind = "changes", key = "gf_party.healthFadeEnabled", value = true },
        category = "group-range-fade",
    },
    {
        id = "party-health-fade-threshold",
        prompt = "set party health fade threshold to 51",
        expect = { kind = "changes", key = "gf_party.healthFadeThreshold", value = 51 },
        category = "group-range-fade",
    },
    {
        id = "party-health-fade-opacity",
        prompt = "set party health fade opacity to 0.525",
        expect = { kind = "changes", key = "gf_party.healthFadeAlpha", value = 0.525 },
        category = "group-range-fade",
    },
    {
        id = "party-group-number",
        prompt = "turn on party group number",
        expect = { kind = "changes", key = "gf_party.showGroupNumber", value = true },
        category = "group-number",
    },
    {
        id = "party-group-number-size",
        prompt = "set party group number size to 15",
        expect = { kind = "changes", key = "gf_party.groupNumberSize", value = 15 },
        category = "group-number",
    },
    {
        id = "party-group-number-anchor",
        prompt = "set party group number anchor to TOPLEFT",
        expect = { kind = "changes", key = "gf_party.groupNumberAnchor", value = "TOPLEFT" },
        category = "group-number",
    },
    {
        id = "party-group-number-x",
        prompt = "set party group number x to 0",
        expect = { kind = "changes", key = "gf_party.groupNumberX", value = 0 },
        category = "group-number",
    },
    {
        id = "party-group-number-y",
        prompt = "set party group number y to 0",
        expect = { kind = "changes", key = "gf_party.groupNumberY", value = 0 },
        category = "group-number",
    },
    {
        id = "party-hover-highlight-thickness",
        prompt = "set party hover highlight thickness to 4",
        expect = { kind = "changes", key = "general.highlightThickness", value = 4 },
        category = "group-highlight",
    },
    {
        id = "party-fallback-aggro-border",
        prompt = "turn on party fallback aggro border",
        expect = { kind = "changes", key = "gf_party.aggroEnabled", value = true },
        category = "group-highlight",
    },
    {
        id = "party-fallback-aggro-shows-all",
        prompt = "set party fallback aggro shows for to ALL",
        expect = { kind = "changes", key = "gf_party.aggroMode", value = "ALL" },
        category = "group-highlight",
    },
    {
        id = "party-fallback-dispel-border",
        prompt = "turn on party fallback dispel border",
        expect = { kind = "changes", key = "gf_party.dispelEnabled", value = true },
        category = "group-highlight",
    },
    {
        id = "party-target-highlight",
        prompt = "turn on party target highlight",
        expect = { kind = "changes", key = "gf_party.targetIndicator", value = true },
        category = "group-highlight",
    },
    {
        id = "party-focus-highlight",
        prompt = "turn on party focus highlight",
        expect = { kind = "changes", key = "gf_party.hlFocusEnabled", value = true },
        category = "group-highlight",
    },
    {
        id = "party-focus-highlight-thickness",
        prompt = "set party focus highlight thickness to 4",
        expect = { kind = "changes", key = "gf_party.hlFocusSize", value = 4 },
        category = "group-highlight",
    },
    {
        id = "party-group-border",
        prompt = "turn on party group border",
        expect = { kind = "changes", key = "gf_party.groupBorderEnabled", value = true },
        category = "group-border",
    },
    {
        id = "party-group-border-thickness",
        prompt = "set party group border thickness to 7",
        expect = { kind = "changes", key = "gf_party.groupBorderSize", value = 7 },
        category = "group-border",
    },
    {
        id = "party-group-border-padding",
        prompt = "set party group border padding to 4",
        expect = { kind = "changes", key = "gf_party.groupBorderPadding", value = 4 },
        category = "group-border",
    },
    {
        id = "mythicraid-group-border-opacity",
        prompt = "set mythicraid group border opacity to 0.5",
        expect = { kind = "changes", key = "gf_mythicraid.groupBorderA", value = 0.5 },
        category = "group-border",
    },
    {
        id = "party-status-icon-style-blizzard",
        prompt = "set party status icon style to BLIZZARD",
        expect = { kind = "changes", key = "gf_party.iconStyle", value = "BLIZZARD" },
        category = "group-status-icons",
    },
    {
        id = "party-midnight-status-icons",
        prompt = "turn on party midnight status icons",
        expect = { kind = "changes", key = "gf_party.useMidnightIcons", value = true },
        category = "group-status-icons",
    },
    {
        id = "unit-aura-root-tooltip-exact-alias",
        prompt = "turn on player show tooltip",
        expect = { kind = "changes", key = "auras3.player.showTooltip", value = true },
        category = "aura-parent-child-routing",
    },
    {
        id = "group-aura-lane-tooltip-exact-alias",
        prompt = "turn on party buff tooltip",
        expect = { kind = "changes", key = "gf_party.auras.buff.showTooltip", value = true },
        category = "aura-parent-child-routing",
    },
    {
        id = "group-aura-root-tooltip-exact-alias",
        prompt = "turn on mythicraid aura tooltip",
        expect = { kind = "changes", key = "gf_mythicraid.auras.showTooltip", value = true },
        category = "aura-parent-child-routing",
    },
    {
        id = "group-self-heal-prediction-canonical-owner",
        prompt = "turn on party show self heal prediction",
        expect = { kind = "changes", key = "barScope.gf_party.healPredEnabled", value = true },
        category = "canonical-storage-owner",
    },
    {
        id = "global-self-heal-prediction-canonical-owner",
        prompt = "turn on show self heal prediction",
        expect = { kind = "changes", key = "general.showSelfHealPrediction", value = true },
        category = "canonical-storage-owner",
    },
    {
        id = "global-health-text-color-canonical-owner",
        prompt = "turn on general color health text by health",
        expect = { kind = "changes", key = "fontScope.shared.colorHealthTextByHealth", value = "HEALTH" },
        category = "canonical-storage-owner",
    },
    {
        id = "raid-corner-helpful-player-filter",
        prompt = "set raid top left corner custom filter to HELPFUL|PLAYER",
        expect = { kind = "changes", key = "gf_raid.ciCustomTL.filter", value = "HELPFUL|PLAYER" },
        category = "corner-indicator",
    },
    {
        id = "raid-corner-custom-mode-fast",
        prompt = "set raid top right corner custom mode to present",
        expect = { kind = "changes", key = "gf_raid.ciCustomTR.mode", value = "present" },
        category = "corner-indicator",
    },
    {
        id = "party-corner-custom-spells-fast",
        prompt = "set party bottom left corner custom spells to 12345,67890",
        expect = { kind = "changes", key = "gf_party.ciCustomBL.spells", value = "12345,67890" },
        category = "corner-indicator",
    },
    {
        id = "class-resource-hp-smooth-fill",
        prompt = "turn on class resources player hp smooth fill",
        expect = { kind = "changes", key = "bars.playerHPBarSmoothFill", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-root-toggle-show",
        prompt = "turn on show class resource",
        expect = { kind = "changes", key = "bars.showClassPower", value = true },
        category = "class-resource",
    },
    {
        id = "class-resources-hp-bar-toggle",
        prompt = "turn on class resources hp bar",
        expect = { kind = "changes", key = "bars.playerHPBarEnabled", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-hp-anchor-guard",
        prompt = "set class resource hp anchor to CLASS_TOP",
        expect = { kind = "changes", key = "bars.playerHPBarAnchor", value = "CLASS_TOP" },
        category = "class-resource",
    },
    {
        id = "class-resource-empowered-combo-fast",
        prompt = "turn on class power empowered combo points",
        expect = { kind = "changes", key = "bars.showChargedComboPoints", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-rune-time-fast",
        prompt = "turn on class power rune time",
        expect = { kind = "changes", key = "bars.runeShowTime", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-elemental-maelstrom-fast",
        prompt = "turn on class power elemental maelstrom",
        expect = { kind = "changes", key = "bars.showEleMaelstrom", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-ebon-might-fast",
        prompt = "turn on class power ebon might",
        expect = { kind = "changes", key = "bars.showEbonMight", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-shadow-insanity-fast",
        prompt = "turn on class power shadow insanity",
        expect = { kind = "changes", key = "bars.showShadowMana", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-prediction-fast",
        prompt = "turn on class resource prediction",
        expect = { kind = "changes", key = "bars.classPowerShowPrediction", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-color-by-type-fast",
        prompt = "turn on class power color by type",
        expect = { kind = "changes", key = "bars.classPowerColorByType", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-combo-color-mode-fast",
        prompt = "set class power combo point color mode to default",
        expect = { kind = "changes", key = "bars.classPowerComboPointColorMode", value = "default" },
        category = "class-resource",
    },
    {
        id = "class-resource-font-size-fast",
        prompt = "set class resource font to 19",
        expect = { kind = "changes", key = "bars.classPowerFontSize", value = 19 },
        category = "class-resource",
    },
    {
        id = "class-resource-outline-fast",
        prompt = "set class power outline to 2",
        expect = { kind = "changes", key = "bars.classPowerOutline", value = 2 },
        category = "class-resource",
    },
    {
        id = "class-resource-foreground-texture-fast",
        prompt = "set class resource foreground texture to Minimalist",
        expect = { kind = "changes", key = "bars.classPowerTexture", value = "Minimalist" },
        category = "class-resource",
    },
    {
        id = "class-resource-background-texture-fast",
        prompt = "set class resource background texture to Minimalist",
        expect = { kind = "changes", key = "bars.classPowerBgTexture", value = "Minimalist" },
        category = "class-resource",
    },
    {
        id = "detached-power-width-mode-fast",
        prompt = "set detached power bar width mode to manual",
        expect = { kind = "changes", key = "bars.detachedPowerBarWidthMode", value = "manual" },
        category = "class-resource",
    },
    {
        -- bars.detachedPowerBarTexture is retired: State/MSUF_Defaults.lua
        -- migrates any stored value to the unit power texture and clears the
        -- key, and bars.powerBarTexture now owns power art for every unit bar
        -- whether it is detached or not.
        id = "detached-power-foreground-texture-fast",
        prompt = "set detached power bar foreground texture to Minimalist",
        expect = { kind = "changes", key = "bars.powerBarTexture", value = "Minimalist" },
        category = "class-resource",
    },
    {
        id = "class-resource-player-hp-width-mode-fast",
        prompt = "set player hp follows class resource to class",
        expect = { kind = "changes", key = "bars.playerHPBarWidthMode", value = "class" },
        category = "class-resource",
    },
    {
        id = "class-resource-second-hp-x-fast",
        prompt = "set second hp x to 0",
        expect = { kind = "changes", key = "bars.playerHPBarOffsetX", value = 0 },
        category = "class-resource",
    },
    {
        id = "class-resource-player-hp-orb-size-fast",
        prompt = "set class resources player hp orb size to 90",
        expect = { kind = "changes", key = "bars.playerHPBarOrbSize", value = 90 },
        category = "class-resource",
    },
    {
        id = "class-resource-alt-mana-fast",
        prompt = "turn on alternative mana bar",
        expect = { kind = "changes", key = "bars.showAltMana", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-preview-resource-fast",
        prompt = "set class resource preview resource to deathknight_runes",
        expect = { kind = "changes", key = "menu.classPowerPreviewResource", value = "deathknight_runes" },
        category = "class-resource",
    },
    {
        id = "gameplay-combat-timer-fast",
        prompt = "turn on combat timer enabled",
        expect = { kind = "changes", key = "gameplay.enableCombatTimer", value = true },
        category = "gameplay",
    },
    {
        id = "gameplay-combat-enter-text-fast",
        prompt = "set combat enter text to Combat",
        expect = { kind = "changes", key = "gameplay.combatStateEnterText", value = "Combat" },
        category = "gameplay",
    },
    {
        id = "gameplay-melee-range-spell-fast",
        prompt = "set melee range spell to 500000",
        expect = { kind = "changes", key = "gameplay.nameplateMeleeSpellID", value = 500000 },
        category = "gameplay",
    },
    {
        id = "global-bar-mode-fast",
        prompt = "set bar mode to dark",
        expect = { kind = "changes", key = "general.barMode", value = "dark" },
        category = "global-bars",
    },
    {
        id = "global-bar-texture-fast",
        prompt = "set bar texture to Minimalist",
        expect = { kind = "changes", key = "general.barTexture", value = "Minimalist" },
        category = "global-bars",
    },
    {
        id = "global-bar-background-texture-fast",
        prompt = "set bar background texture to Minimalist",
        expect = { kind = "changes", key = "general.barBackgroundTexture", value = "Minimalist" },
        category = "global-bars",
    },
    {
        id = "global-bar-gradient-strength-fast",
        prompt = "set gradient strength to 0.5",
        expect = { kind = "changes", key = "general.gradientStrength", value = 0.5 },
        category = "global-bars",
    },
    {
        id = "global-rounded-frame-texture-fast",
        prompt = "turn on rounded frame texture",
        expect = { kind = "changes", key = "bars.roundedFramesEnabled", value = true },
        category = "global-bars",
    },
    {
        id = "global-unitframe-dispel-overlay-fast",
        prompt = "turn on unitframe dispel overlay",
        expect = { kind = "changes", key = "general.unitDispelOverlayEnabled", value = true },
        category = "global-bars",
    },
    {
        id = "scoped-player-unitframe-dispel-overlay-fast",
        prompt = "turn on player unitframe dispel overlay",
        expect = { kind = "changes", key = "barScope.player.unitDispelOverlayEnabled", value = true },
        category = "global-bars",
    },
    {
        id = "global-smooth-power-bar-fast",
        prompt = "turn on smooth power bar",
        expect = { kind = "changes", key = "bars.smoothPowerBar", value = true },
        category = "global-bars",
    },
    {
        id = "scoped-player-bars-override-fast",
        prompt = "turn on player bars override",
        expect = { kind = "changes", key = "barScope.player.override", value = true },
        category = "global-bars",
    },
    {
        id = "scoped-player-gradient-strength-fast",
        prompt = "set player gradient strength to 0.5",
        expect = { kind = "changes", key = "barScope.player.gradientStrength", value = 0.5 },
        category = "global-bars",
    },
    {
        id = "global-font-size-fast",
        prompt = "set font size to 20",
        expect = { kind = "changes", key = "general.fontSize", value = 20 },
        category = "global-fonts",
    },
    {
        id = "global-menu-edge-snap-fast",
        prompt = "turn on menu edge snap",
        expect = { kind = "changes", key = "general.slashMenuSnapEnabled", value = true },
        category = "global-ui",
    },
    {
        id = "global-advanced-menu-fast",
        prompt = "turn on advanced menu",
        expect = { kind = "changes", key = "general.hideAdvancedMenu", value = true },
        category = "global-ui",
    },
    {
        id = "font-scope-player-override-fast",
        prompt = "turn on player font override",
        expect = { kind = "changes", key = "fontScope.player.override", value = true },
        category = "fonts",
    },
    {
        id = "font-scope-shared-outline-fast",
        prompt = "set font outline to OUTLINE",
        expect = { kind = "changes", key = "fontScope.shared.outline", value = "OUTLINE" },
        category = "fonts",
    },
    {
        id = "mythic-raid-font-outline-aggregate-scope",
        prompt = "set mythic raid font outline to OUTLINE",
        expect = { kind = "changes", key = "fontScope.gf_raid.outline", value = "OUTLINE" },
        category = "aggregate-scope",
    },
    {
        id = "mythic-raid-absorb-opacity-aggregate-scope",
        prompt = "set mythic raid absorb bar opacity to 80%",
        expect = { kind = "changes", key = "barScope.gf_raid.absorbBarOpacity", value = 0.8 },
        category = "aggregate-scope",
    },
    {
        id = "mythic-raid-absorb-texture-aggregate-scope",
        prompt = "set mythic raid absorb bar texture to Minimalist",
        expect = { kind = "changes", key = "barScope.gf_raid.absorbBarTexture", value = "Minimalist" },
        category = "aggregate-scope",
    },
    {
        id = "font-scope-shared-shorten-names-fast",
        prompt = "turn on shared shorten names",
        expect = { kind = "changes", key = "fontScope.shared.shortenNames", value = true },
        category = "fonts",
    },
    {
        id = "font-scope-shared-no-ellipsis-fast",
        prompt = "turn on shared no ellipsis",
        expect = { kind = "changes", key = "fontScope.shared.shortenNameNoEllipsis", value = true },
        category = "fonts",
    },
    {
        id = "font-scope-shared-show-ellipsis-fast",
        prompt = "turn off shared no ellipsis",
        expect = { kind = "changes", key = "fontScope.shared.shortenNameNoEllipsis", value = false },
        category = "fonts",
    },
    {
        id = "class-resource-height",
        prompt = "set class resource height to 21",
        expect = { kind = "changes", key = "bars.classPowerHeight", value = 21 },
        category = "class-resource",
    },
    {
        id = "class-resource-frame-level-fast",
        prompt = "set class power frame level to 15",
        expect = { kind = "changes", key = "bars.classPowerFrameLevelOffset", value = 15 },
        category = "class-resource",
    },
    {
        id = "class-resource-width-mode-player",
        prompt = "set class resource width mode to player",
        expect = { kind = "changes", key = "bars.classPowerWidthMode", value = "player" },
        category = "class-resource",
    },
    {
        id = "class-resource-anchor-cooldown-fast",
        prompt = "turn on anchor class resource to cooldownmanager",
        expect = { kind = "changes", key = "bars.classPowerAnchorToCooldown", value = true },
        category = "class-resource",
    },
    {
        id = "class-resource-shape-bar",
        prompt = "set class power shape to BAR",
        expect = { kind = "changes", key = "bars.classPowerShape", value = "BAR" },
        category = "class-resource",
    },
    {
        id = "class-resource-shape-alignment-left",
        prompt = "set class power shape alignment to LEFT",
        expect = { kind = "changes", key = "bars.classPowerShapeAlign", value = "LEFT" },
        category = "class-resource",
    },
    {
        id = "class-bar-colors-reset-action",
        prompt = "reset class bar colors",
        expect = { kind = "action", actionKey = "reset_class_colors" },
        category = "class-resource",
    },
    {
        id = "class-resource-hide-when-full",
        prompt = "turn on class resource when full",
        expect = { kind = "changes", key = "bars.classPowerHideWhenFull", value = false },
        category = "class-resource",
    },
    {
        id = "class-power-text-x",
        prompt = "set class power text x to 0",
        expect = { kind = "changes", key = "bars.classPowerTextOffsetX", value = 0 },
        category = "class-resource",
    },
    {
        id = "class-resource-move-left-fast",
        prompt = "set move class resource left to 0",
        expect = { kind = "changes", key = "bars.classPowerOffsetX" },
        category = "class-resource",
    },
    {
        id = "class-resource-move-up-fast",
        prompt = "set move class resource up to 0",
        expect = { kind = "changes", key = "bars.classPowerOffsetY" },
        category = "class-resource",
    },
    {
        id = "class-resource-human-move-up-fast",
        prompt = "move class resources up",
        expect = { kind = "changes", key = "bars.classPowerOffsetY", relativeDelta = 10 },
        category = "class-resource",
    },
    {
        id = "class-resource-human-move-down-fast",
        prompt = "move class resources down",
        expect = { kind = "changes", key = "bars.classPowerOffsetY", relativeDelta = -10 },
        category = "class-resource",
    },
    {
        id = "class-resource-human-layer-down-fast",
        prompt = "move class resources layer down",
        expect = { kind = "changes", key = "bars.classPowerFrameLevelOffset", relativeDelta = -1 },
        category = "class-resource",
    },
    {
        id = "pet-dispel-overlay-current-health",
        prompt = "turn on pet dispel overlay current health only",
        expect = { kind = "changes", key = "barScope.pet.unitDispelOverlayOnHealth", value = true },
        category = "dispel-overlay",
    },
    {
        id = "player-dispel-overlay-opacity",
        prompt = "set player dispel overlay opacity to 0.525",
        expect = { kind = "changes", key = "barScope.player.unitDispelOverlayAlpha", value = 0.525 },
        category = "dispel-overlay",
    },
    {
        id = "maelstrom-power-color",
        prompt = "set maelstrom power color to yellow",
        expect = { kind = "changes", key = "general.powerColorOverrides.MAELSTROM", valueColor = "yellow" },
        category = "power-color",
    },
    {
        id = "maelstrom-class-resource-color",
        prompt = "set maelstrom power class resource color to yellow",
        expect = { kind = "changes", key = "general.classPowerColorOverrides.MAELSTROM_POWER", valueColor = "yellow" },
        category = "class-resource-color",
    },
    {
        id = "raid-frame-x-offset",
        prompt = "set raid frame x offset to 0",
        expect = { kind = "changes", key = "gf_raid.offsetX", value = 0 },
        category = "group-layout",
    },
    {
        id = "party-show-player",
        prompt = "turn on party show player",
        expect = { kind = "changes", key = "gf_party.showPlayer", value = true },
        category = "group-visibility",
    },
    {
        id = "party-show-solo",
        prompt = "turn on party show solo",
        expect = { kind = "changes", key = "gf_party.showSolo", value = true },
        category = "group-visibility",
    },
    {
        id = "raid-hide-in-housing",
        prompt = "turn on raid hide in housing",
        expect = { kind = "changes", key = "gf_raid.hideInHousing", value = true },
        category = "group-visibility",
    },
    {
        id = "party-click-casting",
        prompt = "turn on party click casting",
        expect = { kind = "changes", key = "gf_party.clickCastEnabled", value = true },
        category = "group-visibility",
    },
    {
        id = "party-blizzard-fallback-auto",
        prompt = "set party blizzard fallback to AUTO",
        expect = { kind = "changes", key = "gf_party.blizzardFallbackMode", value = "AUTO" },
        category = "group-fallback",
    },
    {
        id = "raid-blizzard-fallback-none",
        prompt = "set raid blizzard fallback to NONE",
        expect = { kind = "changes", key = "gf_raid.blizzardFallbackMode", value = "NONE" },
        category = "group-fallback",
    },
    {
        id = "raid-blizzard-fallback-show-natural",
        prompt = "show blizzard raid frames when disabled",
        expect = { kind = "changes", key = "gf_raid.blizzardFallbackMode", value = "SHOW" },
        category = "group-fallback",
    },
    {
        id = "party-hide-offline-delay",
        prompt = "set party hide offline delay to 60",
        expect = { kind = "changes", key = "gf_party.hideOfflineDelay", value = 60 },
        category = "group-visibility",
    },
    {
        id = "mythicraid-hide-offline-delay",
        prompt = "set mythicraid hide offline delay to 60",
        expect = { kind = "changes", key = "gf_mythicraid.hideOfflineDelay", value = 60 },
        category = "group-visibility",
    },
    {
        id = "party-reverse-fill",
        prompt = "turn on party reverse fill",
        expect = { kind = "changes", key = "gf_party.reverseFill", value = true },
        category = "group-bars",
    },
    {
        id = "raid-normal-fill",
        prompt = "set raid normal fill",
        expect = { kind = "changes", key = "gf_raid.reverseFill", value = false },
        category = "group-bars",
    },
    {
        id = "focustarget-reverse-fill-fast",
        prompt = "turn on focustarget reverse fill direction",
        expect = { kind = "changes", key = "focustarget.reverseFillBars", value = true },
        category = "unit-bars",
    },
    {
        id = "party-background-texture-fast",
        prompt = "set party background texture to Minimalist",
        expect = { kind = "changes", key = "gf_party.barBackgroundTexture", value = "Minimalist" },
        category = "group-texture",
    },
    {
        id = "party-bar-texture-fast",
        prompt = "set party bar texture to Minimalist",
        expect = { kind = "changes", key = "barScope.gf_party.barTexture", value = "Minimalist" },
        category = "group-texture",
    },
    {
        id = "raid-bar-background-texture-fast",
        prompt = "set raid bar background texture to Minimalist",
        expect = { kind = "changes", key = "barScope.gf_raid.barBackgroundTexture", value = "Minimalist" },
        category = "group-texture",
    },
    {
        id = "party-name-max-chars",
        prompt = "set party name max chars to 15",
        expect = { kind = "changes", key = "gf_party.nameMaxChars", value = 15 },
        category = "group-name",
    },
    {
        id = "party-shorten-group-names",
        prompt = "turn on party shorten group names",
        expect = { kind = "changes", key = "gf_party.nameShortenEnabled", value = true },
        category = "group-name",
    },
    {
        id = "raid-name-truncation-left",
        prompt = "set raid name truncation style to LEFT",
        expect = { kind = "changes", key = "gf_raid.nameClipSide", value = "LEFT" },
        category = "group-name",
    },
    {
        id = "mythicraid-name-no-ellipsis",
        prompt = "turn on mythicraid name no ellipsis",
        expect = { kind = "changes", key = "gf_mythicraid.nameNoEllipsis", value = true },
        category = "group-name",
    },
    {
        id = "party-no-ellipsis-short",
        prompt = "turn on party no ellipsis",
        expect = { kind = "changes", key = "gf_party.nameNoEllipsis", value = true },
        category = "group-name",
    },
    {
        id = "party-power-bars",
        prompt = "turn on party power bars",
        expect = { kind = "changes", key = "gf_party.powerBarEnabled", value = true },
        category = "group-bars",
    },
    {
        id = "raid-power-bars",
        prompt = "turn on raid power bars",
        expect = { kind = "changes", key = "gf_raid.powerBarEnabled", value = true },
        category = "group-bars",
    },
    {
        id = "party-tank-power-guard",
        prompt = "turn on party tank power",
        expect = { kind = "changes", key = "gf_party.powerShowTank", value = true },
        category = "group-bars",
    },
    {
        id = "raid-healer-power",
        prompt = "turn on raid healer power",
        expect = { kind = "changes", key = "gf_raid.powerShowHealer", value = true },
        category = "group-bars",
    },
    {
        id = "party-dps-power",
        prompt = "turn on party dps power",
        expect = { kind = "changes", key = "gf_party.powerShowDamager", value = true },
        category = "group-bars",
    },
    {
        id = "party-frame-spacing",
        prompt = "set party spacing to 10",
        expect = { kind = "changes", key = "gf_party.spacing", value = 10 },
        category = "group-layout",
    },
    {
        id = "party-units-per-column",
        prompt = "set party units per column to 21",
        expect = { kind = "changes", key = "gf_party.unitsPerColumn", value = 21 },
        category = "group-layout",
    },
    {
        id = "raid-max-columns",
        prompt = "set raid max columns to 5",
        expect = { kind = "changes", key = "gf_raid.maxColumns", value = 5 },
        category = "group-layout",
    },
    {
        id = "party-buff-spacing-guard",
        prompt = "set party buff spacing to 6",
        expect = { kind = "changes", key = "gf_party.auras.buff.spacing", value = 6 },
        category = "group-aura-geometry",
    },
    {
        id = "party-growth-down",
        prompt = "set party grow right to DOWN",
        expect = { kind = "changes", key = "gf_party.growth", value = "DOWN" },
        category = "group-ordering",
    },
    {
        id = "raid-sort-mode-index",
        prompt = "set raid sort mode to INDEX",
        expect = { kind = "changes", key = "gf_raid.sortMode", value = "INDEX" },
        category = "group-ordering",
    },
    {
        id = "party-sort-by-role",
        prompt = "turn on party sort by role",
        expect = { kind = "changes", key = "gf_party.sortByRole", value = true },
        category = "group-ordering",
    },
    {
        id = "party-player-first-role",
        prompt = "turn on party player first in role",
        expect = { kind = "changes", key = "gf_party.playerFirstInRole", value = true },
        category = "group-ordering",
    },
    {
        id = "party-role-priority-order-guard",
        prompt = "set party role priority order to TANK,HEALER,DAMAGER",
        expect = { kind = "changes", key = "gf_party.roleOrder", value = "TANK,HEALER,DAMAGER" },
        category = "group-ordering",
    },
    {
        id = "raid-role-priority-order-dps-first",
        prompt = "set raid role priority order to dps tank healer",
        expect = { kind = "changes", key = "gf_raid.roleOrder", value = "DAMAGER,TANK,HEALER" },
        category = "group-ordering",
    },
    {
        id = "party-buff-growth-guard",
        prompt = "set party buff growth to RIGHTDOWN",
        expect = { kind = "changes", key = "gf_party.auras.buff.growth", value = "RIGHTDOWN" },
        category = "group-aura-geometry",
    },
    {
        id = "party-scale-mode-off",
        prompt = "set party scale mode to off",
        expect = { kind = "changes", key = "gf_party.frameScaleMode", value = "off" },
        category = "group-scaling",
    },
    {
        id = "party-frame-scaling",
        prompt = "turn on party frame scaling",
        expect = { kind = "changes", key = "gf_party.frameScaleEnabled", value = true },
        category = "group-scaling",
    },
    {
        id = "raid-manual-scale",
        prompt = "set raid manual scale to 100",
        expect = { kind = "changes", key = "gf_raid.frameScaleManual", value = 100 },
        category = "group-scaling",
    },
    {
        id = "party-scale-at-20",
        prompt = "set party scale at 20 to 75",
        expect = { kind = "changes", key = "gf_party.scaleAt20", value = 75 },
        category = "group-scaling",
    },
    {
        id = "mythicraid-scale-over-25",
        prompt = "set mythicraid scale over 25 to 75",
        expect = { kind = "changes", key = "gf_mythicraid.scaleOver25", value = 75 },
        category = "group-scaling",
    },
    {
        id = "global-ui-scale-guard",
        prompt = "turn on global ui scale override",
        expect = { kind = "changes", key = "general.globalUiScaleEnabled", value = true },
        category = "global-scale",
    },
    {
        id = "global-ui-scale-value",
        prompt = "set global ui scale to 0.9",
        expect = { kind = "changes", key = "general.globalUiScale", value = 0.9 },
        category = "global-scale",
    },
    {
        id = "global-ui-scale-natural-percent",
        prompt = "scale the ui to 53%",
        expect = { kind = "changes", key = "general.globalUiScale", value = 0.53 },
        category = "global-scale",
    },
    {
        id = "dashboard-msuf-frame-scale-fast",
        prompt = "set msuf frame scale to 0.875",
        expect = { kind = "changes", key = "general.msufUiScale", value = 0.875 },
        category = "dashboard-scale",
    },
    {
        id = "dashboard-msuf-menu-scale-fast",
        prompt = "set msuf menu scale to 0.875",
        expect = { kind = "changes", key = "general.slashMenuScale", value = 0.875 },
        category = "dashboard-scale",
    },
    {
        id = "dashboard-msuf-frame-scale-percent",
        prompt = "set msuf frame scale to 120",
        expect = { kind = "changes", key = "general.msufUiScale", value = 1.2 },
        category = "dashboard-scale",
    },
    {
        id = "global-ui-scale-preset-action-guard",
        prompt = "apply 1080p global ui scale preset",
        expect = { kind = "action" },
        category = "global-scale",
    },
    {
        id = "party-spell-indicators-visibility-guard",
        prompt = "turn on party spell indicators",
        expect = { kind = "changes", key = "gf_party.spellIndicators.enabled", value = true },
        category = "group-feature-guard",
    },
    {
        id = "party-spell-indicators-layer",
        prompt = "set party spell indicator layer to 8",
        expect = { kind = "changes", key = "gf_party.spellIndicators.layer", value = 8 },
        category = "group-feature-guard",
    },
    {
        id = "raid-spell-indicators-spec-auto",
        prompt = "set raid spell indicator spec to auto",
        expect = { kind = "changes", key = "gf_raid.spellIndicators.spec", value = "auto" },
        category = "group-feature-guard",
    },
    {
        id = "unitframe-gradient-from-right",
        prompt = "turn on gradient from right for all unitframes",
        expect = {
            kind = "changes",
            changes = {
                { key = "barScope.player.enableGradient", value = true },
                { key = "barScope.player.gradientDirection", value = "RIGHT" },
                { key = "barScope.focustarget.enableGradient", value = true },
                { key = "barScope.focustarget.gradientDirection", value = "RIGHT" },
            },
        },
        category = "bar-gradient",
    },
    {
        id = "unitframe-gradiant-typo-from-right",
        prompt = "turn on gradiant from right for all unitframes",
        expect = {
            kind = "changes",
            changes = {
                { key = "barScope.player.enableGradient", value = true },
                { key = "barScope.player.gradientDirection", value = "RIGHT" },
                { key = "barScope.focustarget.enableGradient", value = true },
                { key = "barScope.focustarget.gradientDirection", value = "RIGHT" },
            },
        },
        category = "bar-gradient",
    },
    {
        id = "unitframe-gradient-direction-from-right",
        prompt = "set gradient from right for all unitframes",
        expect = {
            kind = "changes",
            changes = {
                { key = "barScope.player.gradientDirection", value = "RIGHT" },
                { key = "barScope.focustarget.gradientDirection", value = "RIGHT" },
            },
        },
        category = "bar-gradient",
    },
    {
        id = "unitframe-bar-gradients-both-from-right",
        prompt = "turn on bar gradients from right for all unitframes",
        expect = {
            kind = "changes",
            changes = {
                { key = "barScope.player.enableGradient", value = true },
                { key = "barScope.player.enablePowerGradient", value = true },
                { key = "barScope.player.gradientDirection", value = "RIGHT" },
                { key = "barScope.focustarget.enableGradient", value = true },
                { key = "barScope.focustarget.enablePowerGradient", value = true },
                { key = "barScope.focustarget.gradientDirection", value = "RIGHT" },
            },
        },
        category = "bar-gradient",
    },
    {
        id = "unitframe-power-gradient-from-left",
        prompt = "turn on power bar gradient from left for all unitframes",
        expect = {
            kind = "changes",
            changes = {
                { key = "barScope.player.enablePowerGradient", value = true },
                { key = "barScope.player.gradientDirection", value = "LEFT" },
                { key = "barScope.focustarget.enablePowerGradient", value = true },
                { key = "barScope.focustarget.gradientDirection", value = "LEFT" },
            },
        },
        category = "bar-gradient",
    },
    {
        id = "group-gradient-followup-after-unitframes",
        prompt = "also for all group frames",
        ctx = {
            lastChangeBundle = {
                { key = "barScope.player.enableGradient", value = false },
                { key = "barScope.target.enableGradient", value = false },
            },
        },
        expect = {
            kind = "changes",
            changes = {
                { key = "barScope.gf_party.enableGradient", value = false },
                { key = "barScope.gf_raid.enableGradient", value = false },
            },
        },
        category = "bar-gradient-followup",
    },
    {
        id = "group-gradient-followup-needs-gradient-context",
        prompt = "also for all group frames",
        expect = { kind = "unknown", status = "ambiguous" },
        category = "bar-gradient-followup",
    },
    {
        id = "unit-name-toggle-fast",
        prompt = "turn on player name",
        expect = { kind = "changes", key = "player.showName", value = true },
        category = "fast-simple-unit",
    },
    {
        id = "unit-level-toggle-fast",
        prompt = "turn on target level",
        expect = { kind = "changes", key = "target.showLevelIndicator", value = true },
        category = "fast-simple-unit",
    },
    {
        id = "unit-dead-text-toggle-fast",
        prompt = "turn on player dead text",
        expect = { kind = "changes", key = "player.statusTextEnabled", value = true },
        category = "fast-simple-unit",
    },
    {
        id = "unit-raid-group-style-fast",
        prompt = "set player raid group style to PAREN",
        expect = { kind = "changes", key = "player.raidGroupNameStyle", value = "PAREN" },
        category = "fast-simple-unit",
    },
    {
        id = "unit-raid-marker-anchor-fast",
        prompt = "set boss raid marker anchor to TOPLEFT",
        expect = { kind = "changes", key = "boss.raidMarkerAnchor", value = "TOPLEFT" },
        category = "fast-simple-unit",
    },
    {
        id = "unit-raidgroup-human-move-fast",
        prompt = "move playerframe raidgroup indicator to the right",
        expect = { kind = "changes", key = "player.raidGroupNameOffsetX", relativeDelta = 10 },
        category = "human-indicators",
    },
    {
        id = "unit-pvpflag-human-move-fast",
        prompt = "move targetframe pvpflag indicator up",
        expect = { kind = "changes", key = "target.pvpIndicatorOffsetY", relativeDelta = 10 },
        category = "human-indicators",
    },
    {
        id = "unit-rested-icon-layer-down-fast",
        prompt = "change player rested icon layer down",
        expect = { kind = "changes", key = "player.restedStateIndicatorLayer", relativeDelta = -1 },
        category = "human-indicators",
    },
    {
        id = "unit-rested-icon-layer-up-fast",
        prompt = "change player resting icon layer up",
        expect = { kind = "changes", key = "player.restedStateIndicatorLayer", relativeDelta = 1 },
        category = "human-indicators",
    },
    {
        id = "group-power-smooth-fill-fast",
        prompt = "turn on party power smooth fill",
        expect = { kind = "changes", key = "gf_party.powerSmoothFill", value = true },
        category = "fast-simple-group",
    },
    {
        id = "group-smooth-fill-fast",
        prompt = "turn on raid smooth fill",
        expect = { kind = "changes", key = "gf_raid.smoothFill", value = true },
        category = "fast-simple-group",
    },
    {
        id = "group-corner-indicators-fast",
        prompt = "turn on party corner indicators",
        expect = { kind = "changes", key = "gf_party.ciEnabled", value = true },
        category = "fast-simple-group",
    },
    {
        id = "group-readycheck-human-move-fast",
        prompt = "move raidframe readycheck indicator right",
        expect = { kind = "changes", key = "gf_raid.readyCheckX", relativeDelta = 10 },
        category = "human-indicators",
    },
    {
        id = "group-readycheck-layer-down-fast",
        prompt = "change raid ready check icon layer down",
        expect = { kind = "changes", key = "gf_raid.readyCheckLayer", relativeDelta = -1 },
        category = "human-indicators",
    },
    {
        id = "group-raidmarker-human-anchor-fast",
        prompt = "set partyframe raidmarker icon anchor to TOPLEFT",
        expect = { kind = "changes", key = "gf_party.raidMarkerAnchor", value = "TOPLEFT" },
        category = "human-indicators",
    },
    {
        id = "group-number-fast",
        prompt = "turn on raid group number",
        expect = { kind = "changes", key = "gf_raid.showGroupNumber", value = true },
        category = "fast-simple-group",
    },
    {
        id = "group-power-text-fast",
        prompt = "turn on party power text",
        expect = { kind = "changes", key = "gf_party.showPowerText", value = true },
        category = "fast-group-text",
    },
    {
        id = "group-hp-font-size-fast",
        prompt = "set party hp font size to 15",
        expect = { kind = "changes", key = "gf_party.hpFontSize", value = 15 },
        category = "fast-group-text",
    },
    {
        id = "group-power-right-text-fast",
        prompt = "set raid power right text to NONE",
        expect = { kind = "changes", key = "gf_raid.powerTextRight", value = "NONE" },
        category = "fast-group-text",
    },
    {
        id = "global-dead-text-ghost-fast",
        prompt = "turn on dead text ghost units",
        expect = { kind = "changes", key = "general.statusIndicators.showGhost", value = true },
        category = "fast-global-status",
    },
    {
        id = "global-dead-text-dead-fast",
        prompt = "turn on dead text dead units",
        expect = { kind = "changes", key = "general.statusIndicators.showDead", value = true },
        category = "fast-global-status",
    },
    {
        id = "global-status-icons-midnight-fast",
        prompt = "turn on status icons midnight style",
        expect = { kind = "changes", key = "general.statusIconsUseMidnightStyle", value = true },
        category = "fast-global-status",
    },
    {
        id = "unit-anchor-point-fast",
        prompt = "set focustarget anchor point to TOPLEFT",
        expect = { kind = "changes", key = "focustarget.point", value = "TOPLEFT" },
        category = "fast-unit-anchor",
    },
    {
        id = "boss-target-highlight-fast",
        prompt = "turn on boss target highlight",
        expect = { kind = "changes", key = "general.bossTargetHighlightEnabled", value = true },
        category = "fast-bars",
    },
    {
        id = "class-resource-fill-fast",
        prompt = "turn on class resource fill",
        expect = { kind = "changes", key = "bars.classPowerFillReverse", value = true },
        category = "fast-class-resource",
    },
    {
        id = "aura-blacklist-preset-fast",
        prompt = "set aura blacklist preset to RAID_BUFFS",
        expect = { kind = "changes", key = "menu.auraBlacklistPreset", value = "RAID_BUFFS" },
        category = "fast-aura",
    },
    {
        id = "dispel-border-detects-fast",
        prompt = "set dispel border detects to BY_ME",
        expect = { kind = "changes", key = "general.dispelBorderTrigger", value = "BY_ME" },
        category = "fast-bars",
    },
    {
        id = "unit-portrait-shape-fast",
        prompt = "set focustarget portrait shape to SQUARE",
        expect = { kind = "changes", key = "focustarget.portraitShape", value = "SQUARE" },
        category = "fast-unit-portrait",
    },
    {
        id = "raid-filter-recommendation-answer",
        prompt = "what is a good filter for raid?",
        expect = { kind = "answer", textContains = { "Raid", "Raid In Combat", "Dispellable" } },
        category = "aura-filter-guidance",
    },
    {
        id = "unitframe-texture-location-immediate",
        prompt = "how do I change the texture of the unitframes?",
        mode = "immediate",
        expect = { status = "info", textContains = { "Global Bar Texture", "Open Bars" } },
        category = "immediate-help",
    },
    {
        id = "target-debuff-active-filter-answer",
        prompt = "what active target debuff filters do I have",
        expect = { kind = "answer", textContains = { "Target Debuff filters", "Active filters right now", "Native filter string" } },
        category = "aura-filter-guidance",
    },
    {
        id = "raid-filter-active-needs-lane",
        prompt = "is raid filter active",
        expect = { kind = "answer", textContains = { "frame", "lane" } },
        category = "safe-clarification",
    },
    {
        id = "filter-toggle-needs-scope",
        prompt = "turn on filter",
        expect = { kind = "answer", textContains = { "scope", "Buffs", "Debuffs" } },
        category = "safe-clarification",
    },
    {
        id = "filter-token-needs-lane",
        prompt = "set filter to raid",
        expect = { kind = "answer", textContains = { "lane", "Buffs", "Debuffs" } },
        category = "safe-clarification",
    },
    {
        id = "party-buff-x-offset",
        prompt = "set party buff x to 0",
        expect = { kind = "changes", key = "gf_party.auras.buff.x", value = 0 },
        category = "group-aura-geometry",
    },
    {
        id = "party-buff-cooldown-x-offset",
        prompt = "set party buff cooldown x to 0",
        expect = { kind = "changes", key = "gf_party.auras.buff.cooldownX", value = 0 },
        category = "group-aura-geometry",
    },
    {
        id = "party-buff-cooldown-font-size",
        prompt = "set party buff cooldown font to 15",
        expect = { kind = "changes", key = "gf_party.auras.buff.cooldownSize", value = 15 },
        category = "group-aura-geometry",
    },
    {
        id = "party-buff-cooldown-text",
        prompt = "turn on party buff cooldown text",
        expect = { kind = "changes", key = "gf_party.auras.buff.showCooldown", value = true },
        category = "group-aura-geometry",
    },
    {
        id = "party-buff-stack-count",
        prompt = "turn on party buff stack count",
        expect = { kind = "changes", key = "gf_party.auras.buff.showStacks", value = true },
        category = "group-aura-geometry",
    },
    {
        id = "party-aura-cooldown-darkens-on-loss",
        prompt = "turn on party aura cooldown darkens on loss",
        expect = { kind = "changes", key = "gf_party.cooldownSwipeDarkenOnLoss", value = true },
        category = "group-aura-geometry",
    },
    {
        id = "broad-bars-prettier-guidance",
        prompt = "make the bars prettier",
        expect = { kind = "answer", textContains = { "I did not change", "examples" } },
        category = "safe-clarification",
    },
    {
        id = "raid-frames-less-cluttered-guidance",
        prompt = "make raid frames less cluttered",
        expect = { kind = "answer", textContains = { "I did not change", "raid frames" } },
        category = "safe-clarification",
    },
    {
        id = "generic-color-needs-target",
        prompt = "change color to yellow",
        expect = { kind = "answer", textContains = { "Which color", "health bar", "text" } },
        category = "safe-clarification",
    },
    {
        id = "target-text-color-needs-slot",
        prompt = "change the target text color to class",
        expect = { kind = "answer", textContains = { "Name Text", "Health Text", "Power Text" } },
        category = "safe-clarification",
    },
    {
        id = "power-text-default-natural",
        prompt = "set power text to default",
        expect = { kind = "changes", key = "fontScope.shared.colorPowerTextByType", value = "DEFAULT" },
        category = "font-text-color",
    },
    {
        id = "continuation-target-leader-up",
        prompt = "now move target leader up",
        seedContext = {
            turnSerial = 2,
            lastSubjectTurn = 1,
            lastSetting = "target.showLeaderIcon",
            lastUnit = "target",
            lastFrameType = "unit",
            lastCategory = "Target / Status Icons",
        },
        expect = { kind = "changes", key = "target.leaderIconOffsetY", relativeDelta = 10 },
        category = "context-continuation",
    },
    {
        id = "continuation-target-leader-stale-hp-context-falls-through",
        prompt = "now move target leader up",
        seedContext = {
            turnSerial = 2,
            lastSubjectTurn = 1,
            lastSetting = "target.hpBarAlpha",
            lastUnit = "target",
            lastFrameType = "unit",
            lastCategory = "unit.transparency",
        },
        expect = { kind = "changes", key = "target.offsetY" },
        category = "context-continuation",
    },
    {
        id = "context-score-target-name-up",
        prompt = "move target name up",
        seedContext = {
            turnSerial = 2,
            lastSubjectTurn = 1,
            lastSetting = "target.nameTextAnchor",
            lastUnit = "target",
            lastFrameType = "unit",
            lastCategory = "unit.text",
            lastTextArea = "name",
        },
        expect = { kind = "changes", key = "target.nameOffsetY", relativeDelta = 10 },
        category = "context-scoring",
    },
}

local colorLabels = {
    red = { r = 1, g = 0, b = 0 },
    yellow = { r = 1, g = 1, b = 0 },
    green = { r = 0, g = 1, b = 0 },
    blue = { r = 0, g = 0, b = 1 },
    purple = { r = 0.6, g = 0.2, b = 1 },
}

local function near(a, b)
    a = tonumber(a)
    b = tonumber(b)
    return a ~= nil and b ~= nil and math.abs(a - b) <= 0.025
end

local function colorMatches(value, label)
    if type(value) ~= "table" then return false end
    local color = colorLabels[label]
    if not color then return false end
    return near(value.r, color.r) and near(value.g, color.g) and near(value.b, color.b)
end

local function firstChange(result)
    if type(result) ~= "table" or type(result.changes) ~= "table" then return nil end
    return result.changes[1]
end

local function findChange(result, key)
    if type(result) ~= "table" or type(result.changes) ~= "table" then return nil end
    key = tostring(key or "")
    for i = 1, #result.changes do
        local change = result.changes[i]
        local setting = change and change.setting
        if setting and tostring(setting.key or "") == key then return change end
    end
    return nil
end

local function actionKey(result)
    if type(result) ~= "table" then return nil end
    if type(result.action) == "table" then return result.action.key end
    if type(result.actions) == "table" and type(result.actions[1]) == "table" then return result.actions[1].key end
    return result.key or result.actionKey
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return out
end

local function replaceTableContents(target, source)
    if type(target) ~= "table" then return end
    for key in pairs(target) do target[key] = nil end
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do target[key] = deepCopy(value) end
end

local function seedAssistantContext(A, seed)
    if type(seed) ~= "table" or type(A.GetContext) ~= "function" then return nil end
    local ctx = A.GetContext()
    local snapshot = deepCopy(ctx)
    replaceTableContents(ctx, seed)
    return snapshot
end

local function restoreAssistantContext(A, snapshot)
    if not snapshot or type(A.GetContext) ~= "function" then return end
    replaceTableContents(A.GetContext(), snapshot)
end

local function resultSummary(result)
    local change = firstChange(result)
    local setting = change and change.setting
    local value = nil
    if change then value = change.value end
    return {
        kind = type(result) == "table" and result.kind or type(result),
        status = type(result) == "table" and result.status or nil,
        text = type(result) == "table" and result.text or nil,
        label = type(result) == "table" and result.label or nil,
        changeCount = type(result) == "table" and type(result.changes) == "table" and #result.changes or 0,
        key = setting and setting.key or nil,
        value = value,
        valueLabel = change and change.valueLabel or nil,
        actionKey = actionKey(result),
    }
end

local function checkExpectation(result, expect)
    if type(expect) ~= "table" then return true end
    if expect.kind and (type(result) ~= "table" or result.kind ~= expect.kind) then
        return false, "expected kind " .. tostring(expect.kind) .. ", got " .. tostring(type(result) == "table" and result.kind or type(result))
    end
    if expect.notKind and type(result) == "table" and result.kind == expect.notKind then
        return false, "expected not kind " .. tostring(expect.notKind)
    end
    if expect.status and (type(result) ~= "table" or result.status ~= expect.status) then
        return false, "expected status " .. tostring(expect.status) .. ", got " .. tostring(type(result) == "table" and result.status or nil)
    end
    if type(expect.textContains) == "table" then
        local text = tostring(type(result) == "table" and result.text or "")
        local lower = text:lower()
        for i = 1, #expect.textContains do
            local needle = tostring(expect.textContains[i] or "")
            if needle ~= "" and not lower:find(needle:lower(), 1, true) then
                return false, "expected answer text to contain " .. needle
            end
        end
    end
    local change = firstChange(result)
    if expect.key then
        -- Plans may lead with companion changes (enabling the parent feature
        -- before the requested option); accept the expected key anywhere in
        -- the change list and validate values against that change.
        local match = findChange(result, expect.key)
        if not match then
            return false, "expected key " .. tostring(expect.key) .. ", got " .. tostring(change and change.setting and change.setting.key)
        end
        change = match
    end
    if expect.value ~= nil and (not change or change.value ~= expect.value) then
        return false, "expected value " .. tostring(expect.value) .. ", got " .. tostring(change and change.value)
    end
    if expect.relativeDelta ~= nil and (not change or change.relativeDelta ~= expect.relativeDelta) then
        return false, "expected relative delta " .. tostring(expect.relativeDelta) .. ", got " .. tostring(change and change.relativeDelta)
    end
    if expect.valueColor and (not change or not colorMatches(change.value, expect.valueColor)) then
        return false, "expected color " .. tostring(expect.valueColor)
    end
    if type(expect.changes) == "table" then
        for i = 1, #expect.changes do
            local wanted = expect.changes[i]
            local wantedKey = wanted and wanted.key
            local found = findChange(result, wantedKey)
            if not found then
                return false, "expected change " .. tostring(wantedKey)
            end
            if wanted.value ~= nil and found.value ~= wanted.value then
                return false, "expected change " .. tostring(wantedKey) .. " value " .. tostring(wanted.value) .. ", got " .. tostring(found.value)
            end
            if wanted.relativeDelta ~= nil and found.relativeDelta ~= wanted.relativeDelta then
                return false, "expected change " .. tostring(wantedKey) .. " relative delta " .. tostring(wanted.relativeDelta) .. ", got " .. tostring(found.relativeDelta)
            end
            if wanted.valueColor and not colorMatches(found.value, wanted.valueColor) then
                return false, "expected change " .. tostring(wantedKey) .. " color " .. tostring(wanted.valueColor)
            end
        end
    end
    if expect.actionKey and actionKey(result) ~= expect.actionKey then
        return false, "expected action " .. tostring(expect.actionKey) .. ", got " .. tostring(actionKey(result))
    end
    if type(expect.args) == "table" then
        local actualArgs = type(result) == "table" and result.args or nil
        for key, wanted in pairs(expect.args) do
            if type(actualArgs) ~= "table" or actualArgs[key] ~= wanted then
                return false, "expected action arg " .. tostring(key) .. "=" .. tostring(wanted)
                    .. ", got " .. tostring(type(actualArgs) == "table" and actualArgs[key] or nil)
            end
        end
    end
    return true
end

local function settingByKey(A, key)
    local Registry = A and A.Registry
    if not (Registry and type(Registry.GetSetting) == "function") then return nil end
    return Registry:GetSetting(key)
end

local function settingValue(setting)
    if setting and type(setting.get) == "function" then return setting.get() end
    return nil
end

local function setSettingValue(setting, value)
    if setting and type(setting.set) == "function" then setting.set(value) end
end

local function clearConversationState(A)
    if type(A) ~= "table" then return end
    A.pendingChoices = nil
    A.pendingCandidates = nil
    A.pendingConfirmation = nil
    A.pendingFlow = nil
    if type(A.GetContext) == "function" then replaceTableContents(A.GetContext(), {}) end
end

local function snapshotPublicSmokeState(A)
    return {
        msufDB = deepCopy(_G.MSUF_DB),
        globalDB = deepCopy(_G.MSUF_GlobalDB),
        pendingChoices = deepCopy(A and A.pendingChoices),
        pendingCandidates = deepCopy(A and A.pendingCandidates),
        pendingConfirmation = deepCopy(A and A.pendingConfirmation),
        pendingFlow = deepCopy(A and A.pendingFlow),
    }
end

local function restorePublicSmokeState(A, snapshot)
    if type(snapshot) ~= "table" then return end
    _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
    _G.MSUF_GlobalDB = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {}
    replaceTableContents(_G.MSUF_DB, snapshot.msufDB)
    replaceTableContents(_G.MSUF_GlobalDB, snapshot.globalDB)
    if type(A) == "table" then
        A.pendingChoices = snapshot.pendingChoices
        A.pendingCandidates = snapshot.pendingCandidates
        A.pendingConfirmation = snapshot.pendingConfirmation
        A.pendingFlow = snapshot.pendingFlow
    end
end

local publicSmokeCases = {
    {
        id = "public-p0-1-noop-relative-nudge",
        prompt = "phase 0.1 public no-op relative nudge sequence",
        category = "public-context-smoke",
        run = function(A)
            local anchor = settingByKey(A, "targettarget.nameTextAnchor")
            local offsetX = settingByKey(A, "targettarget.nameOffsetX")
            if not (anchor and offsetX and type(A.HandleInput) == "function") then return false, "required settings or HandleInput missing" end

            clearConversationState(A)
            setSettingValue(anchor, "RIGHT")
            setSettingValue(offsetX, 0)
            local first = A.HandleInput("move target of target name more to the right")
            if tonumber(settingValue(offsetX)) ~= 10 then
                return false, "relative no-op did not nudge nameOffsetX; result=" .. tostring(first and (first.result or first.status))
            end

            -- A movement verb aimed at a direction is a position request, never
            -- a Name Text Anchor change: "move ... to the right" nudges the X
            -- offset and leaves the anchor alone, whatever the anchor happens to
            -- be. Only an explicit anchor/align word or centering reaches the
            -- anchor. See the move-vs-anchor guard in
            -- MSUF_AssistantParser_Geometry_Text.lua.
            clearConversationState(A)
            setSettingValue(anchor, "LEFT")
            setSettingValue(offsetX, 0)
            local second = A.HandleInput("move target of target name to the right")
            if tostring(settingValue(anchor)) ~= "LEFT" or tonumber(settingValue(offsetX)) ~= 10 then
                return false, "plain movement changed wrong setting; anchor=" .. tostring(settingValue(anchor)) .. " offsetX=" .. tostring(settingValue(offsetX)) .. " result=" .. tostring(second and (second.result or second.status))
            end

            clearConversationState(A)
            setSettingValue(anchor, "RIGHT")
            setSettingValue(offsetX, 0)
            local third = A.HandleInput("set target of target name anchor to right")
            local text = tostring(third and third.text or "")
            if tonumber(settingValue(offsetX)) ~= 0 or not text:lower():find("already set", 1, true) then
                return false, "explicit set did not stay no-op; offsetX=" .. tostring(settingValue(offsetX)) .. " text=" .. text
            end
            return true, "relative no-op nudged offset; plain anchor and explicit no-op stayed unchanged"
        end,
    },
    {
        id = "public-p0-2-target-leader-continuation",
        prompt = "enable target leader icon -> now move target leader up",
        category = "public-context-smoke",
        run = function(A)
            local show = settingByKey(A, "target.showLeaderIcon")
            local leaderY = settingByKey(A, "target.leaderIconOffsetY")
            local frameY = settingByKey(A, "target.offsetY")
            if not (show and leaderY and frameY and type(A.HandleInput) == "function") then return false, "required settings or HandleInput missing" end
            clearConversationState(A)
            setSettingValue(show, false)
            setSettingValue(leaderY, 0)
            setSettingValue(frameY, 0)
            A.HandleInput("enable target leader icon")
            local beforeLeaderY = tonumber(settingValue(leaderY)) or 0
            local beforeFrameY = tonumber(settingValue(frameY)) or 0
            local result = A.HandleInput("now move target leader up")
            if tonumber(settingValue(leaderY)) ~= beforeLeaderY + 10 or tonumber(settingValue(frameY)) ~= beforeFrameY then
                return false, "continuation changed wrong setting; leaderY=" .. tostring(settingValue(leaderY)) .. " frameY=" .. tostring(settingValue(frameY)) .. " result=" .. tostring(result and (result.result or result.status))
            end
            return true, "continuation nudged target.leaderIconOffsetY and left target.offsetY unchanged"
        end,
    },
    {
        id = "public-p0-1-frame-move-unchanged",
        prompt = "move target frame up without prior subject context",
        category = "public-context-smoke",
        run = function(A)
            local leaderY = settingByKey(A, "target.leaderIconOffsetY")
            local frameY = settingByKey(A, "target.offsetY")
            if not (leaderY and frameY and type(A.HandleInput) == "function") then return false, "required settings or HandleInput missing" end
            clearConversationState(A)
            setSettingValue(leaderY, 0)
            setSettingValue(frameY, 0)
            local result = A.HandleInput("move target frame up")
            if tonumber(settingValue(frameY)) ~= 10 or tonumber(settingValue(leaderY)) ~= 0 then
                return false, "frame move changed wrong setting; frameY=" .. tostring(settingValue(frameY)) .. " leaderY=" .. tostring(settingValue(leaderY)) .. " result=" .. tostring(result and (result.result or result.status))
            end
            return true, "plain frame move adjusted target.offsetY and left leader offset unchanged"
        end,
    },
    {
        id = "public-p0-2-stale-hp-context-falls-through",
        prompt = "set target hp bar opacity to 80% -> now move target leader up",
        category = "public-context-smoke",
        run = function(A)
            local hpAlpha = settingByKey(A, "target.hpBarAlpha")
            local leaderY = settingByKey(A, "target.leaderIconOffsetY")
            local frameY = settingByKey(A, "target.offsetY")
            if not (hpAlpha and leaderY and frameY and type(A.HandleInput) == "function") then return false, "required settings or HandleInput missing" end
            clearConversationState(A)
            A.HandleInput("set target hp bar opacity to 80%")
            setSettingValue(leaderY, 0)
            setSettingValue(frameY, 0)
            local result = A.HandleInput("now move target leader up")
            if tonumber(settingValue(leaderY)) ~= 0 or tonumber(settingValue(frameY)) ~= 10 then
                return false, "stale HP context did not fall through; leaderY=" .. tostring(settingValue(leaderY)) .. " frameY=" .. tostring(settingValue(frameY)) .. " result=" .. tostring(result and (result.result or result.status))
            end
            return true, "stale HP context fell through to existing target frame movement"
        end,
    },
    {
        id = "public-p0-2-freshness-expired-falls-through",
        prompt = "expired target leader context -> now move target leader up",
        category = "public-context-smoke",
        run = function(A)
            local show = settingByKey(A, "target.showLeaderIcon")
            local leaderY = settingByKey(A, "target.leaderIconOffsetY")
            local frameY = settingByKey(A, "target.offsetY")
            if not (show and leaderY and frameY and type(A.HandleInput) == "function" and type(A.GetContext) == "function") then return false, "required settings, context, or HandleInput missing" end
            clearConversationState(A)
            setSettingValue(show, false)
            setSettingValue(leaderY, 0)
            setSettingValue(frameY, 0)
            A.HandleInput("enable target leader icon")
            local ctx = A.GetContext()
            local subjectTurn = tonumber(ctx.lastSubjectTurn or ctx.turnSerial or ctx.lastTurnSerial) or 0
            ctx.turnSerial = subjectTurn + 4
            ctx.lastTurnSerial = ctx.turnSerial
            local result = A.HandleInput("now move target leader up")
            if tonumber(settingValue(leaderY)) ~= 0 or tonumber(settingValue(frameY)) ~= 10 then
                return false, "expired context did not fall through; leaderY=" .. tostring(settingValue(leaderY)) .. " frameY=" .. tostring(settingValue(frameY)) .. " result=" .. tostring(result and (result.result or result.status))
            end
            return true, "expired continuation context fell through to existing target frame movement"
        end,
    },
    {
        id = "public-p1-3-ambiguity-ordinal",
        prompt = "change castbar color from green to red -> the second one",
        category = "public-context-smoke",
        run = function(A)
            if type(A.HandleInput) ~= "function" then return false, "HandleInput missing" end
            clearConversationState(A)
            local ambiguous = A.HandleInput("change castbar color from green to red")
            local pending = type(A.pendingChoices) == "table" and #A.pendingChoices or 0
            if tostring(ambiguous and (ambiguous.result or ambiguous.status)) ~= "ambiguous" or pending < 2 then
                return false, "ambiguity did not store pending choices; status=" .. tostring(ambiguous and (ambiguous.result or ambiguous.status)) .. " pending=" .. tostring(pending)
            end
            local ordinal = A.HandleInput("the second one")
            if tostring(ordinal and (ordinal.result or ordinal.status)) == "ambiguous" then
                return false, "ordinal remained ambiguous"
            end
            if not ordinal or tostring(ordinal.result or ordinal.status) ~= "applied" then
                return false, "ordinal did not apply pending candidate; status=" .. tostring(ordinal and (ordinal.result or ordinal.status))
            end
            return true, "ordinal resolved against " .. tostring(pending) .. " pending choices"
        end,
    },
    {
        id = "public-p2-generated-and-manifest-export",
        prompt = "phase 2 generated fallback report and manifest export APIs",
        category = "public-coverage-smoke",
        run = function(A)
            local Audit = A and A.CoverageAudit
            local Auto = A and A.AutoCoverage
            if not (Audit and type(Audit.BuildGeneratedReport) == "function") then return false, "BuildGeneratedReport missing" end
            if not (Auto and type(Auto.BuildManifestText) == "function" and type(Auto.StoreManifestExport) == "function") then return false, "manifest API missing" end
            _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
            _G.MSUF_DB.target = type(_G.MSUF_DB.target) == "table" and _G.MSUF_DB.target or {}
            _G.MSUF_DB.target.trainingGeneratedSmoke = 17
            if type(Auto.Fill) == "function" then Auto.Fill() end
            local report = Audit.BuildGeneratedReport("target")
            if not tostring(report or ""):find("%[target%] generated fallbacks:", 1, false) then
                return false, "generated report missing target header"
            end
            local text, total = Auto.BuildManifestText()
            Auto.StoreManifestExport(text, total)
            local saved = _G.MSUF_GlobalDB and _G.MSUF_GlobalDB.assistantAutoCoverageManifest or nil
            if (tonumber(total) or 0) <= 0 or not tostring(text or ""):find("Manifest.defaults", 1, true) then
                return false, "manifest export text empty"
            end
            if type(saved) ~= "table" or (tonumber(saved.total) or 0) ~= (tonumber(total) or 0) then
                return false, "manifest export not stored"
            end
            return true, "generated report and manifest export available with " .. tostring(total) .. " scalar defaults"
        end,
    },
    {
        id = "public-p2-top-level-autocoverage-contract",
        prompt = "phase 2 auto-coverage uses only manifest-backed top-level scalar identities",
        category = "public-coverage-smoke",
        run = function(A)
            local Auto = A and A.AutoCoverage
            local Registry = A and A.Registry
            if not (Auto and type(Auto.Fill) == "function" and Registry and type(Registry.GetSetting) == "function") then
                return false, "auto-coverage API missing"
            end
            _G.MSUF_DB = type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {}
            _G.MSUF_DB.target = type(_G.MSUF_DB.target) == "table" and _G.MSUF_DB.target or {}
            _G.MSUF_DB.target.trainingNested = {
                display = { enabled = true, opacity = 0.45 },
                spells = { [12345] = { enabled = true } },
            }
            Auto.Fill()
            if Registry:GetSetting("target.trainingNested.display.opacity") then
                return false, "live nested profile state became a public setting"
            end
            if Registry:GetSetting("target.trainingNested.spells.12345.enabled") then
                return false, "numeric dynamic map was exposed as a setting"
            end
            A.AutoCoverageManifest = type(A.AutoCoverageManifest) == "table" and A.AutoCoverageManifest or {}
            A.AutoCoverageManifest.defaults = type(A.AutoCoverageManifest.defaults) == "table" and A.AutoCoverageManifest.defaults or {}
            A.AutoCoverageManifest.defaults.target = type(A.AutoCoverageManifest.defaults.target) == "table" and A.AutoCoverageManifest.defaults.target or {}
            A.AutoCoverageManifest.defaults.target["trainingManifest.display.enabled"] = true
            A.AutoCoverageManifest.defaults.target.trainingManifestTopLevel = true
            Auto.Fill()
            if Registry:GetSetting("target.trainingManifest.display.enabled") then
                return false, "dotted manifest path bypassed the top-level identity contract"
            end
            local manifestSetting = Registry:GetSetting("target.trainingManifestTopLevel")
            if not (manifestSetting and manifestSetting.manifestDefault == true and manifestSetting.get() == true) then
                return false, "top-level manifest default was not registered"
            end
            manifestSetting.set(false)
            if _G.MSUF_DB.target.trainingManifestTopLevel ~= false then
                return false, "top-level manifest setter did not materialize the DB key"
            end
            local text = Auto.BuildManifestText()
            if tostring(text or ""):find("trainingNested", 1, true) then
                return false, "nested live table leaked into the manifest export"
            end
            if not tostring(text or ""):find("trainingManifestTopLevel", 1, true) then
                return false, "top-level scalar missing from manifest export"
            end
            return true, "manifest-backed top-level scalar generated; nested state excluded"
        end,
    },
    {
        id = "public-p2-acceptance-gate-api",
        prompt = "phase 2 acceptance gate API over saved smoke, manifest, and coverage evidence",
        category = "public-coverage-smoke",
        run = function(A)
            local Audit = A and A.CoverageAudit
            if not (Audit and type(Audit.BuildAcceptanceGate) == "function" and type(Audit.AcceptanceSmokeCases) == "table") then return false, "acceptance gate API missing" end
            _G.MSUF_GlobalDB = type(_G.MSUF_GlobalDB) == "table" and _G.MSUF_GlobalDB or {}
            _G.MSUF_GlobalDB.assistantAcceptance = { cases = {} }
            for i = 1, #Audit.AcceptanceSmokeCases do
                local item = Audit.AcceptanceSmokeCases[i]
                _G.MSUF_GlobalDB.assistantAcceptance.cases[item.id] = { status = "pass", time = "runner-smoke" }
            end
            _G.MSUF_GlobalDB.assistantAutoCoverageManifest = {
                total = 1,
                text = "Manifest.defaults = {\n}\n",
                time = "runner-smoke",
            }
            _G.MSUF_GlobalDB.assistantCoverage = {
                settings = 1,
                generated = 0,
                scopes = { target = { settings = 1 } },
                time = "runner-smoke",
            }
            -- This is an aggregation/API contract test.  Runtime control-page
            -- visitation and the real dependency graph have dedicated gates;
            -- supply complete fixtures here so this case verifies that saved
            -- smoke/manifest/coverage plus those two evidence APIs compose.
            local M = _G.MSUF_NS and _G.MSUF_NS.MSUF2 or {}
            local oldCatalog = M.GetRuntimeControlCoverageReport
            local oldGraph = A.GetSettingDependencyGraphCoverageReport
            M.GetRuntimeControlCoverageReport = function()
                return {
                    total = 1,
                    catalogComplete = true,
                    targetValidationAvailable = true,
                    unresolvedTargetCount = 0,
                }
            end
            A.GetSettingDependencyGraphCoverageReport = function()
                return { coveragePercent = 100, specificCoveragePercent = 100, unresolved = {} }
            end
            local ok, gate = pcall(Audit.BuildAcceptanceGate)
            M.GetRuntimeControlCoverageReport = oldCatalog
            A.GetSettingDependencyGraphCoverageReport = oldGraph
            if not ok then return false, "acceptance gate raised: " .. tostring(gate) end
            if not (gate and gate.complete == true) then
                return false, "gate not complete"
            end
            if gate.smoke.pass ~= #Audit.AcceptanceSmokeCases or gate.manifest.available ~= true or gate.coverage.available ~= true then
                return false, "gate counts incomplete"
            end
            return true, "acceptance gate complete with " .. tostring(gate.smoke.pass) .. "/" .. tostring(gate.smoke.total) .. " smoke checks"
        end,
    },
}

local function readOnlyMutationPrompt(setting, alias)
    if setting.type == "number" then
        return "set " .. alias .. " to " .. tostring(sampleNumber(setting))
    elseif setting.type == "string" then
        return "set " .. alias .. " to " .. tostring(sampleString(setting))
    elseif setting.type == "boolean" then
        return "turn on " .. alias
    elseif setting.type == "enum" then
        local value = sampleEnum(setting)
        if value ~= nil then return "set " .. alias .. " to " .. tostring(value) end
    elseif setting.type == "color" then
        return "set " .. alias .. " to yellow"
    end
    return nil
end

local function generateSettingCases(A, limit, coverageDispositions)
    local Registry = A and A.Registry
    local settings = Registry and Registry.AllSettings and Registry:AllSettings() or {}
    local out = {}
    local readOnly = {}
    local uncovered = {}
    local policies = type(coverageDispositions) == "table" and coverageDispositions.settingPolicies or nil
    local aliasShadows = type(coverageDispositions) == "table" and coverageDispositions.settingAliasShadows or nil
    local seenAliasShadows = {}
    for i = 1, #settings do
        local setting = settings[i]
        if limit > 0 and (#out + #readOnly) >= limit then
            uncovered[#uncovered + 1] = {
                key = tostring(setting.key or ""),
                label = tostring(setting.label or ""),
                type = tostring(setting.type or ""),
                reason = "generation limit",
            }
        else
            local alias = scopedAlias(setting, firstAlias(setting))
            local skipReason
            if alias and alias ~= "" then
                local value
                local prompt
                if setting.assistantMutationSafe == false then
                    local policyKey = tostring(setting.generatedMutationSafety or "")
                    local policy = type(policies) == "table" and policies[policyKey] or nil
                    prompt = readOnlyMutationPrompt(setting, alias)
                    if type(policy) ~= "table" then
                        skipReason = "unreviewed read-only policy " .. (policyKey ~= "" and policyKey or "<missing>")
                    elseif tostring(policy.classification or "") == "" or tostring(policy.evidence or "") == "" or tostring(policy.reason or "") == "" then
                        skipReason = "incomplete read-only policy " .. policyKey
                    elseif type(setting.get) ~= "function" then
                        skipReason = "read-only setting has no getter"
                    elseif tostring(setting.unsafeMutationReason or "") == "" then
                        skipReason = "read-only setting has no unsafe mutation reason"
                    elseif not prompt then
                        skipReason = "read-only setting has no mutation probe"
                    else
                        local aliasShadow = type(aliasShadows) == "table" and aliasShadows[tostring(setting.key or "")] or nil
                        if aliasShadow then seenAliasShadows[tostring(setting.key or "")] = true end
                        readOnly[#readOnly + 1] = {
                            id = "generated-read-only-" .. tostring(#readOnly + 1),
                            prompt = prompt,
                            category = "generated-read-only-" .. tostring(setting.type or "unknown"),
                            generated = true,
                            settingKey = setting.key,
                            setting = setting,
                            policyKey = policyKey,
                            policy = policy,
                            alias = alias,
                            aliasShadow = aliasShadow,
                        }
                        prompt = nil
                    end
                else
                    if setting.type == "boolean" then
                        value = true
                        prompt = "turn on " .. alias
                    elseif setting.type == "number" then
                        value = sampleNumber(setting)
                        prompt = "set " .. alias .. " to " .. tostring(value)
                    elseif setting.type == "enum" then
                        value = sampleEnum(setting)
                        if value ~= nil then prompt = "set " .. alias .. " to " .. tostring(value) end
                    elseif setting.type == "color" then
                        value = "yellow"
                        prompt = "set " .. alias .. " to yellow"
                    elseif setting.type == "string" then
                        value = sampleString(setting)
                        if value ~= nil then prompt = "set " .. alias .. " to " .. tostring(value) end
                    else
                        skipReason = "unsupported type " .. tostring(setting.type)
                    end
                    if prompt then
                        out[#out + 1] = {
                            id = "generated-" .. tostring(#out + 1),
                            prompt = prompt,
                            expect = { kind = "changes", key = setting.key },
                            category = "generated-" .. tostring(setting.type or "unknown"),
                            generated = true,
                            settingKey = setting.key,
                        }
                    end
                end
                if skipReason then
                    uncovered[#uncovered + 1] = {
                        key = tostring(setting.key or ""),
                        label = tostring(setting.label or ""),
                        type = tostring(setting.type or ""),
                        reason = skipReason,
                    }
                elseif setting.assistantMutationSafe ~= false and not prompt then
                    -- This path is retained for future setting types that can
                    -- be described but do not yet have a deterministic sample.
                    uncovered[#uncovered + 1] = {
                        key = tostring(setting.key or ""),
                        label = tostring(setting.label or ""),
                        type = tostring(setting.type or ""),
                        reason = "no sample value",
                    }
                end
            else
                uncovered[#uncovered + 1] = {
                    key = tostring(setting.key or ""),
                    label = tostring(setting.label or ""),
                    type = tostring(setting.type or ""),
                    reason = "no usable alias",
                }
            end
        end
    end
    if type(aliasShadows) == "table" then
        for key in pairs(aliasShadows) do
            if not seenAliasShadows[key] then
                uncovered[#uncovered + 1] = {
                    key = tostring(key),
                    label = "",
                    type = "",
                    reason = "stale read-only alias-shadow disposition",
                }
            end
        end
    end
    return out, #settings, uncovered, readOnly
end

local function generateActionCases(A, coverageDispositions)
    local Registry = A and A.Registry
    local actions = Registry and Registry.AllActions and Registry:AllActions() or {}
    local out = {}
    local uncovered = {}
    local disposed = {}
    local dispositions = type(coverageDispositions) == "table" and coverageDispositions.actions or nil
    local seenActions = {}
    for i = 1, #actions do
        local action = actions[i]
        local actionKey = tostring(action and action.key or "")
        seenActions[actionKey] = true
        local samplePrompt = sampleActionPrompt(action)
        local alias = firstActionAlias(action)
        local disposition = type(dispositions) == "table" and dispositions[actionKey] or nil
        if samplePrompt and disposition then
            uncovered[#uncovered + 1] = {
                key = actionKey,
                label = tostring(action and action.label or ""),
                type = tostring(action and action.type or ""),
                reason = "action has both a conversational sample and a non-conversational disposition",
            }
        elseif samplePrompt then
            out[#out + 1] = {
                id = "generated-action-" .. tostring(#out + 1),
                prompt = samplePrompt,
                expect = { kind = "action", actionKey = action.key },
                category = "generated-action-" .. tostring(action.type or "unknown"),
                generated = true,
                actionKey = action.key,
            }
        elseif disposition then
            disposed[#disposed + 1] = {
                id = "action-disposition-" .. tostring(#disposed + 1),
                actionKey = actionKey,
                action = action,
                disposition = disposition,
                category = "action-disposition-" .. tostring(disposition.classification or "unknown"),
            }
        elseif type(action.aliases) ~= "table" or #action.aliases == 0 then
            uncovered[#uncovered + 1] = {
                key = tostring(action and action.key or ""),
                label = tostring(action and action.label or ""),
                type = tostring(action and action.type or ""),
                reason = "no action alias",
            }
        elseif not (action.aliasNoArgs == true or type(action.parseAliasArgs) == "function") then
            uncovered[#uncovered + 1] = {
                key = tostring(action and action.key or ""),
                label = tostring(action and action.label or ""),
                type = tostring(action and action.type or ""),
                reason = "no alias parser",
            }
        elseif not alias or alias == "" then
            uncovered[#uncovered + 1] = {
                key = tostring(action and action.key or ""),
                label = tostring(action and action.label or ""),
                type = tostring(action and action.type or ""),
                reason = "no usable alias",
            }
        elseif type(action.parseAliasArgs) == "function" and action.aliasNoArgs ~= true then
            local ok, parsedArgs = pcall(action.parseAliasArgs, alias, alias, action)
            if not ok or parsedArgs == false then
                uncovered[#uncovered + 1] = {
                    key = tostring(action and action.key or ""),
                    label = tostring(action and action.label or ""),
                    type = tostring(action and action.type or ""),
                    reason = "sample args required",
                }
            else
                out[#out + 1] = {
                    id = "generated-action-" .. tostring(#out + 1),
                    prompt = alias,
                    expect = { kind = "action", actionKey = action.key },
                    category = "generated-action-" .. tostring(action.type or "unknown"),
                    generated = true,
                    actionKey = action.key,
                }
            end
        else
            out[#out + 1] = {
                id = "generated-action-" .. tostring(#out + 1),
                prompt = alias,
                expect = { kind = "action", actionKey = action.key },
                category = "generated-action-" .. tostring(action.type or "unknown"),
                generated = true,
                actionKey = action.key,
            }
        end
    end
    if type(dispositions) == "table" then
        for key, disposition in pairs(dispositions) do
            if not seenActions[key] then
                disposed[#disposed + 1] = {
                    id = "action-disposition-stale-" .. tostring(#disposed + 1),
                    actionKey = tostring(key),
                    action = nil,
                    disposition = disposition,
                    category = "action-disposition-stale",
                }
            end
        end
    end
    table.sort(disposed, function(left, right) return tostring(left.actionKey) < tostring(right.actionKey) end)
    return out, #actions, uncovered, disposed
end

local function generateActionDiscoveryCases(A)
    local Registry = A and A.Registry
    local actions = Registry and Registry.AllActions and Registry:AllActions() or {}
    local out = {}
    for i = 1, #actions do
        local action = actions[i]
        local label = tostring(action and action.label or "")
        if label ~= "" then
            out[#out + 1] = {
                id = "action-discovery-" .. tostring(#out + 1),
                prompt = "explain " .. label,
                category = "action-discovery-" .. tostring(action.type or "unknown"),
                actionKey = action.key,
                actionLabel = label,
            }
        end
    end
    return out
end

local function runCase(A, case, slowMs, failSlow)
    local started = os.clock()
    local parser = A.ParseForTest or A.Parse
    if case.mode == "immediate" then
        parser = A.TryImmediateConversationReply
    elseif case.mode == "immediateMutation" then
        parser = function(prompt)
            local runtime = A.RuntimePrivate or {}
            if type(runtime.TryImmediateMutationResult) == "function" then
                return runtime.TryImmediateMutationResult(prompt, { skipUserHistory = true })
            end
            return nil
        end
    elseif case.mode == "deferredSubmit" then
        parser = function(prompt)
            if type(A.SubmitDeferred) == "function" then
                return A.SubmitDeferred(prompt, nil)
            end
            return nil
        end
    end
    local contextSnapshot = seedAssistantContext(A, case.seedContext)
    local parseContext = case.ctx or case.context or case.seedContext or {}
    local ok, result = pcall(parser, case.prompt, parseContext)
    restoreAssistantContext(A, contextSnapshot)
    local elapsedMs = (os.clock() - started) * 1000
    local slow = elapsedMs > slowMs
    local passed = false
    local reason
    if not ok then
        reason = tostring(result)
    elseif (case.mode == "immediate" or case.mode == "immediateMutation" or case.mode == "deferredSubmit") and not result then
        reason = "expected immediate result"
    else
        passed, reason = checkExpectation(result, case.expect)
        if passed and slow and failSlow then
            passed = false
            reason = string.format("slow parse %.2fms > %.2fms", elapsedMs, slowMs)
        end
    end
    return {
        id = case.id,
        prompt = case.prompt,
        category = case.category,
        generated = case.generated == true,
        settingKey = case.settingKey,
        actionKey = case.actionKey,
        passed = passed,
        reason = reason,
        elapsedMs = elapsedMs,
        slow = slow,
        result = ok and resultSummary(result) or { kind = "error", text = tostring(result) },
    }
end

local function runReadOnlySettingCase(A, case, slowMs, failSlow)
    local started = os.clock()
    local setting = case and case.setting
    local passed = false
    local reason
    local result
    local ok = true

    if type(setting) ~= "table" or tostring(setting.key or "") ~= tostring(case and case.settingKey or "") then
        ok, reason = false, "read-only case lost its exact registry setting"
    elseif setting.assistantMutationSafe ~= false then
        ok, reason = false, "read-only case is not fail-closed by mutation policy"
    elseif setting.generated ~= true then
        ok, reason = false, "read-only disposition is only valid for generated fallback settings"
    elseif tostring(setting.generatedMutationSafety or "") ~= tostring(case.policyKey or "") then
        ok, reason = false, "setting mutation policy does not match its reviewed disposition"
    elseif type(setting.get) ~= "function" then
        ok, reason = false, "read-only setting has no getter"
    elseif tostring(setting.unsafeMutationReason or "") == "" then
        ok, reason = false, "read-only setting has no human-readable safety reason"
    elseif type(case.policy) ~= "table"
        or tostring(case.policy.classification or "") ~= "read-only-generated-fallback"
        or tostring(case.policy.evidence or "") ~= "getter-and-fail-closed-mutation-probe"
        or tostring(case.policy.reason or "") == "" then
        ok, reason = false, "reviewed read-only disposition is incomplete"
    end

    local before
    if ok then
        local getOk, value = pcall(setting.get)
        if not getOk then
            ok, reason = false, "read-only getter raised: " .. tostring(value)
        elseif setting.type == "number" and type(value) ~= "number" then
            ok, reason = false, "read-only numeric getter returned " .. type(value)
        elseif setting.type == "string" and type(value) ~= "string" then
            ok, reason = false, "read-only string getter returned " .. type(value)
        else
            before = value
        end
    end

    if ok then
        local parser = A.ParseForTest or A.Parse
        local parseOk, parsed = pcall(parser, case.prompt, {})
        if not parseOk then
            ok, reason = false, "fail-closed mutation probe raised: " .. tostring(parsed)
        elseif type(parsed) ~= "table" then
            ok, reason = false, "fail-closed mutation probe returned no Assistant response"
        elseif type(A.ExecutePlan) ~= "function" then
            ok, reason = false, "Assistant execution boundary is unavailable"
        else
            local exactChange = findChange(parsed, case.settingKey)
            local executionPlan = parsed
            if exactChange and case.aliasShadow then
                ok, reason = false, "read-only alias-shadow disposition is stale because the exact setting now resolves"
            elseif not exactChange then
                local parsedChange = firstChange(parsed)
                local parsedKey = parsedChange and parsedChange.setting and parsedChange.setting.key or "<none>"
                local shadow = case.aliasShadow
                if type(shadow) ~= "table" or tostring(shadow.resolvesTo or "") == ""
                    or tostring(shadow.reason or "") == "" then
                    ok, reason = false, "mutation probe did not resolve its exact read-only setting; got " .. tostring(parsedKey)
                elseif tostring(parsedKey) ~= tostring(shadow.resolvesTo) then
                    ok, reason = false, "reviewed alias shadow drifted; expected " .. tostring(shadow.resolvesTo) .. ", got " .. tostring(parsedKey)
                else
                    -- The natural alias is explicitly non-addressable. Probe the
                    -- exact registry identity at the real execution boundary so
                    -- its read-only policy is still proven without pretending
                    -- the shadowing parser result covers it.
                    executionPlan = {
                        kind = "changes",
                        changes = { { setting = setting, value = parsedChange.value } },
                        label = tostring(setting.label or setting.key),
                        summary = "Synthetic exact read-only execution-boundary probe.",
                        raw = case.prompt,
                        sourceText = case.prompt,
                    }
                end
            end
            local executeOk, executed
            if ok then executeOk, executed = pcall(A.ExecutePlan, executionPlan, { sourceText = case.prompt }) end
            if not ok then
                -- Keep the specific resolution/disposition failure above.
            elseif not executeOk then
                ok, reason = false, "execution-boundary mutation probe raised: " .. tostring(executed)
            elseif type(executed) ~= "table" then
                ok, reason = false, "execution boundary returned no fail-closed response"
            else
                result = executed
            end
            local summary = result and resultSummary(result) or {}
            if summary.kind == "changes" or summary.kind == "action"
                or (tonumber(summary.changeCount) or 0) > 0 or summary.actionKey ~= nil then
                ok, reason = false, "read-only mutation probe produced an executable plan"
            elseif ok then
                local text = tostring(summary.text or ""):lower()
                if not text:find("kept msuf unchanged", 1, true) then
                    ok, reason = false, "execution boundary did not return the explicit fail-closed explanation"
                end
            end
        end
    end

    if ok then
        local getOk, after = pcall(setting.get)
        if not getOk then
            ok, reason = false, "read-only getter raised after probe: " .. tostring(after)
        elseif before ~= after then
            ok, reason = false, "parser probe changed the read-only setting"
        end
    end

    local elapsedMs = (os.clock() - started) * 1000
    local slow = elapsedMs > slowMs
    passed = ok
    if passed and slow and failSlow then
        passed = false
        reason = string.format("slow read-only probe %.2fms > %.2fms", elapsedMs, slowMs)
    end
    return {
        id = case.id,
        prompt = case.prompt,
        category = case.category,
        generated = true,
        settingKey = case.settingKey,
        coverageClassification = case.aliasShadow and "read-only-alias-shadow" or tostring(case.policy and case.policy.classification or ""),
        aliasShadowOwner = case.aliasShadow and case.aliasShadow.resolvesTo or nil,
        policyKey = case.policyKey,
        readable = ok == true,
        passed = passed,
        reason = reason,
        elapsedMs = elapsedMs,
        slow = slow,
        result = result and resultSummary(result) or { kind = ok and "read-only-contract" or "error", text = reason },
    }
end

local function runActionDispositionCase(case, slowMs)
    local started = os.clock()
    local action = case and case.action
    local disposition = case and case.disposition
    local passed = true
    local reason
    local classification = tostring(disposition and disposition.classification or "")
    if type(action) ~= "table" then
        passed, reason = false, "disposition references an action that is no longer registered"
    elseif tostring(action.key or "") ~= tostring(case.actionKey or "") then
        passed, reason = false, "disposition resolved the wrong action"
    elseif classification ~= "ui-only" and classification ~= "internal" then
        passed, reason = false, "non-conversational action has an invalid classification"
    elseif tostring(disposition.reason or "") == "" or tostring(disposition.entrypoint or "") == "" then
        passed, reason = false, "non-conversational action disposition lacks reason or entrypoint evidence"
    elseif tostring(action.type or "") ~= tostring(disposition.expectedType or "") then
        passed, reason = false, "action type drifted from reviewed disposition"
    elseif tostring(action.mutability or "") ~= tostring(disposition.expectedMutability or "") then
        passed, reason = false, "action mutability drifted from reviewed disposition"
    elseif type(action.run) ~= "function" then
        passed, reason = false, "non-conversational action has no executable adapter"
    elseif action.aliasNoArgs == true or type(action.parseAliasArgs) == "function"
        or ((type(action.aliases) == "table" and #action.aliases > 0) and disposition.allowDescriptiveAliases ~= true) then
        passed, reason = false, "disposed action acquired a conversational alias/parser and now requires an executable sample case"
    end
    local elapsedMs = (os.clock() - started) * 1000
    return {
        id = case.id,
        prompt = "review non-conversational action " .. tostring(case.actionKey or ""),
        category = case.category,
        generated = false,
        actionKey = case.actionKey,
        coverageClassification = classification,
        passed = passed,
        reason = reason,
        elapsedMs = elapsedMs,
        slow = elapsedMs > slowMs,
        result = {
            kind = "action-disposition-contract",
            status = passed and "passed" or "failed",
            text = passed and tostring(disposition.entrypoint) or tostring(reason or ""),
            actionKey = case.actionKey,
        },
    }
end

local function runCoverageInventoryContract(spec, slowMs)
    local started = os.clock()
    local settingsCovered = tonumber(spec.generatedSettings or 0) + tonumber(spec.readOnlySettings or 0)
    local actionsCovered = tonumber(spec.generatedActions or 0) + tonumber(spec.disposedActions or 0)
    local passed = true
    local reason
    if type(spec.dispositions) ~= "table" then
        passed, reason = false, "coverage disposition catalog failed to load: " .. tostring(spec.dispositionError or "unknown error")
    elseif tonumber(spec.dispositions.version) ~= 1 then
        passed, reason = false, "unsupported coverage disposition catalog version"
    elseif tonumber(spec.uncoveredSettings or 0) ~= 0 then
        passed, reason = false, tostring(spec.uncoveredSettings) .. " registry settings have no executable or reviewed read-only coverage"
    elseif tonumber(spec.uncoveredActions or 0) ~= 0 then
        passed, reason = false, tostring(spec.uncoveredActions) .. " registry actions have no executable or reviewed non-conversational coverage"
    elseif settingsCovered ~= tonumber(spec.registrySettings or 0) then
        passed, reason = false, "setting coverage partition does not equal the registry inventory"
    elseif actionsCovered ~= tonumber(spec.registryActions or 0) then
        passed, reason = false, "action coverage partition does not equal the registry inventory"
    end
    local elapsedMs = (os.clock() - started) * 1000
    return {
        id = "registry-coverage-inventory-contract",
        prompt = "partition every registry setting and action into executable or reviewed fail-closed coverage",
        category = "registry-coverage-inventory",
        generated = false,
        passed = passed,
        reason = reason,
        elapsedMs = elapsedMs,
        slow = elapsedMs > slowMs,
        result = {
            kind = "coverage-contract",
            status = passed and "passed" or "failed",
            text = passed and (tostring(settingsCovered) .. " settings and " .. tostring(actionsCovered) .. " actions classified") or tostring(reason or ""),
        },
    }
end

local function runPublicSmokeCase(A, case, slowMs)
    local started = os.clock()
    local snapshot = snapshotPublicSmokeState(A)
    local ok, passed, detail = pcall(case.run, A)
    restorePublicSmokeState(A, snapshot)
    local elapsedMs = (os.clock() - started) * 1000
    local success = ok and passed == true
    local reason
    if not ok then
        reason = tostring(passed)
    elseif not success then
        reason = tostring(detail or "public smoke failed")
    end
    return {
        id = case.id,
        prompt = case.prompt,
        category = case.category,
        generated = false,
        passed = success,
        reason = reason,
        elapsedMs = elapsedMs,
        slow = elapsedMs > slowMs,
        result = {
            kind = "public-smoke",
            status = success and "passed" or "failed",
            text = tostring(detail or ""),
        },
    }
end

local function runDiscoveryCase(A, case, slowMs, failSlow)
    local started = os.clock()
    local ok, result = pcall(A.ParseForTest or A.Parse, case.prompt, {})
    local elapsedMs = (os.clock() - started) * 1000
    local summary = ok and resultSummary(result) or { kind = "error", text = tostring(result) }
    local kind = tostring(summary.kind or "nil")
    local passed = false
    local classification
    local reason

    if not ok or kind == "error" or kind == "nil" then
        classification = "unknown"
        reason = ok and "action explanation returned no usable result" or tostring(result)
    elseif kind == "ambiguous" or tostring(summary.status or "") == "ambiguous" then
        classification = "ambiguous"
        reason = "registered action explanation remained ambiguous"
    elseif kind == "unknown" then
        classification = "unknown"
        reason = "registered action explanation returned unknown"
    elseif kind == "action" or kind == "changes" or summary.actionKey ~= nil or (tonumber(summary.changeCount) or 0) > 0 then
        classification = "unsafe"
        reason = "explanation probe returned an executable plan"
    elseif kind ~= "answer" then
        classification = "unexpected"
        reason = "expected a non-mutating answer, got " .. kind
    elseif tostring(summary.text or "") == "" then
        classification = "unexpected"
        reason = "action explanation returned an empty answer"
    else
        classification = "safe-answer"
        passed = true
    end

    local slow = elapsedMs > slowMs
    if passed and slow and failSlow then
        passed = false
        classification = "slow"
        reason = string.format("slow action explanation %.2fms > %.2fms", elapsedMs, slowMs)
    end

    return {
        id = case.id,
        prompt = case.prompt,
        category = case.category,
        actionKey = case.actionKey,
        actionLabel = case.actionLabel,
        generated = false,
        passed = passed,
        reason = reason,
        classification = classification,
        elapsedMs = elapsedMs,
        slow = slow,
        result = summary,
    }
end

local function runRuntimeSmokeCase(path, addonRoot, slowMs, spec)
    spec = type(spec) == "table" and spec or {}
    local started = os.clock()
    local chunk, loadError = loadfile(path)
    local ok, runtimeError
    if chunk then
        ok, runtimeError = pcall(chunk, addonRoot)
    else
        ok, runtimeError = false, loadError
    end
    local elapsedMs = (os.clock() - started) * 1000
    return {
        id = spec.id or "runtime-transaction-smoke",
        prompt = spec.prompt or "ExecutePlan transaction rollback, verification, commit, no-op, undo, and action snapshot invariants",
        category = spec.category or "runtime-transaction-smoke",
        generated = false,
        passed = ok == true,
        reason = ok and nil or tostring(runtimeError or "transaction smoke failed"),
        elapsedMs = elapsedMs,
        -- This is an integration invariant suite, not a single parser timing
        -- sample. Its duration is reported but never treated as a slow parse.
        slow = false,
        result = {
            kind = "runtime-smoke",
            status = ok and "passed" or "failed",
            text = ok and "ExecutePlan transaction invariants passed." or tostring(runtimeError or "transaction smoke failed"),
        },
    }
end

local function countLoadMisses(loadReport)
    local count = 0
    for i = 1, #(loadReport or {}) do
        if not loadReport[i].ok then count = count + 1 end
    end
    return count
end

local function topFailures(results)
    local out = {}
    for i = 1, #results do
        if not results[i].passed then out[#out + 1] = results[i] end
        if #out >= 25 then break end
    end
    return out
end

local function markdownReport(summary, loadReport, results)
    local lines = {}
    lines[#lines + 1] = "# MSUF Assistant Training Report"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "- Total gate checks: " .. tostring(summary.total)
    lines[#lines + 1] = "- Passed: " .. tostring(summary.passed)
    lines[#lines + 1] = "- Gate failures: " .. tostring(summary.failed)
    lines[#lines + 1] = "- Parser/public case failures: " .. tostring(summary.parserFailures)
    lines[#lines + 1] = "- Action explanation failures: " .. tostring(summary.actionDiscoveryFailures)
    lines[#lines + 1] = "- Runtime transaction smoke failures: " .. tostring(summary.runtimeSmokeFailures)
    lines[#lines + 1] = "- Slow cases: " .. tostring(summary.slow)
    lines[#lines + 1] = "- Parser warmup ms: " .. string.format("%.2f", tonumber(summary.warmupMs) or 0)
    lines[#lines + 1] = "- Registry settings loaded: " .. tostring(summary.registrySettings)
    lines[#lines + 1] = "- Registry key fingerprint: " .. tostring(summary.registryKeyFingerprint)
    lines[#lines + 1] = "- AutoCoverage fallbacks filled: " .. tostring(summary.autoCoverageFilled or 0)
    lines[#lines + 1] = "- Generated writable setting cases: " .. tostring(summary.generatedCases)
    lines[#lines + 1] = "- Generated read-only getter + fail-closed probes: " .. tostring(summary.generatedReadOnlySettingCases)
    lines[#lines + 1] = "- Classified setting coverage: " .. tostring(summary.classifiedSettingCases) .. "/" .. tostring(summary.registrySettings)
    lines[#lines + 1] = "- Settings without executable/reviewed coverage: " .. tostring(summary.uncoveredSettings)
    lines[#lines + 1] = "- Read-only setting contract failures: " .. tostring(summary.readOnlySettingFailures)
    lines[#lines + 1] = "- Registry actions loaded: " .. tostring(summary.registryActions)
    lines[#lines + 1] = "- Generated conversational action cases: " .. tostring(summary.generatedActionCases)
    lines[#lines + 1] = "- Reviewed non-conversational action contracts: " .. tostring(summary.reviewedNonConversationalActions)
    lines[#lines + 1] = "- Classified action coverage: " .. tostring(summary.classifiedActionCases) .. "/" .. tostring(summary.registryActions)
    lines[#lines + 1] = "- Actions without executable/reviewed coverage: " .. tostring(summary.uncoveredActions)
    lines[#lines + 1] = "- Non-conversational action contract failures: " .. tostring(summary.actionDispositionFailures)
    lines[#lines + 1] = "- Coverage inventory contract failures: " .. tostring(summary.coverageInventoryFailures)
    lines[#lines + 1] = "- Public path smoke cases: " .. tostring(summary.publicSmokeCases)
    lines[#lines + 1] = "- Action explanation probes: " .. tostring(summary.actionDiscoveryCases)
    lines[#lines + 1] = "- Action explanation ambiguous: " .. tostring(summary.actionDiscoveryAmbiguous)
    lines[#lines + 1] = "- Action explanation unknown/error: " .. tostring(summary.actionDiscoveryUnknown)
    lines[#lines + 1] = "- Action explanation returned actions: " .. tostring(summary.actionDiscoveryUnsafeActions)
    lines[#lines + 1] = "- Action explanation unexpected: " .. tostring(summary.actionDiscoveryUnexpected)
    lines[#lines + 1] = "- Assistant file load misses: " .. tostring(summary.loadMisses)
    lines[#lines + 1] = "- Loader misses are fatal: yes"
    lines[#lines + 1] = "- Slow parses are fatal: " .. (summary.failSlow and "yes (performance gate)" or "no (reported only)")
    lines[#lines + 1] = ""
    if summary.loadMisses > 0 then
        lines[#lines + 1] = "## Loader Misses"
        lines[#lines + 1] = ""
        for i = 1, #loadReport do
            local item = loadReport[i]
            if not item.ok then
                lines[#lines + 1] = "- `" .. tostring(item.path) .. "`: " .. tostring(item.error)
            end
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "## First Failures"
    lines[#lines + 1] = ""
    local failures = topFailures(results)
    if #failures == 0 then
        lines[#lines + 1] = "No parser failures in this run."
    else
        for i = 1, #failures do
            local item = failures[i]
            lines[#lines + 1] = tostring(i) .. ". `" .. item.id .. "` `" .. item.prompt .. "`"
            lines[#lines + 1] = "   - reason: " .. tostring(item.reason)
            lines[#lines + 1] = "   - result: kind=`" .. tostring(item.result.kind) .. "` key=`" .. tostring(item.result.key) .. "` value=`" .. tostring(item.result.value) .. "`"
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Repair Prompt"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Fix the first failing MSUF Assistant parser cases from `tools/AssistantTraining/out/failures.json`, rerun `tools/AssistantTraining/run.ps1`, and keep any fixed case as a regression."
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

local function repairPrompt(results)
    local lines = {}
    lines[#lines + 1] = "Fix these MSUF Assistant parser training failures."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Use the real parser/registry code, keep changes scoped, then rerun:"
    lines[#lines + 1] = "`tools/AssistantTraining/run.ps1`"
    lines[#lines + 1] = ""
    local failures = topFailures(results)
    for i = 1, #failures do
        local item = failures[i]
        lines[#lines + 1] = tostring(i) .. ". " .. item.prompt
        lines[#lines + 1] = "   Expected category: " .. tostring(item.category)
        lines[#lines + 1] = "   Failure: " .. tostring(item.reason)
        lines[#lines + 1] = "   Result kind/key/value: " .. tostring(item.result.kind) .. " / " .. tostring(item.result.key) .. " / " .. tostring(item.result.value)
    end
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

local function warmParserIndexes(A)
    local started = os.clock()
    local Registry = A and A.Registry
    local Parser = A and A.Parser
    local settings = Registry and Registry.AllSettings and Registry:AllSettings() or nil
    local actions = Registry and Registry.AllActions and Registry:AllActions() or nil
    if Registry and type(Registry.BuildFindSettingsIndex) == "function" then
        Registry:BuildFindSettingsIndex()
    end
    if Parser and settings and type(Parser._EnsureRegistryCandidateIndex) == "function" then
        Parser._EnsureRegistryCandidateIndex(settings, false)
        Parser._EnsureRegistryCandidateIndex(settings, true)
    end
    if Parser and settings and type(Parser._EnsureExactColorSettingIndex) == "function" then
        Parser._EnsureExactColorSettingIndex(settings)
    end
    if Parser and settings and type(Parser._EnsureRegistryExactAliasIndex) == "function" then
        Parser._EnsureRegistryExactAliasIndex(settings)
    end
    if Parser and actions and type(Parser._EnsureExactActionPhraseIndex) == "function" then
        Parser._EnsureExactActionPhraseIndex(actions)
    end
    if Parser and actions and type(Parser._EnsureRegistryActionAliasIndex) == "function" then
        Parser._EnsureRegistryActionAliasIndex(actions)
    end
    if A and A.Knowledge and type(A.Knowledge.EnsureIndex) == "function" then
        A.Knowledge.EnsureIndex()
    end
    return (os.clock() - started) * 1000
end

ensureDir(opts.out)

local coverageDispositions, coverageDispositionError, coverageDispositionPath = loadCoverageDispositions()
local A, loadReport = loadAssistant(opts.root)
if not (A and type(A.ParseForTest or A.Parse) == "function") then
    local report = {
        summary = { total = 0, passed = 0, failed = 1, registrySettings = 0, loadMisses = countLoadMisses(loadReport) },
        loadReport = loadReport,
        failures = { { id = "loader", prompt = "load assistant parser", passed = false, reason = "A.ParseForTest was not available" } },
    }
    writeAll(join(opts.out, "failures.json"), encodeJson(report))
    io.stderr:write("Assistant parser failed to load. See " .. join(opts.out, "failures.json") .. "\n")
    os.exit(2)
end

-- The PLAYER_LOGIN event never fires under the stubs, so run the AutoCoverage
-- fill (live-DB + shipped manifest) explicitly. Without this the ~2000
-- generated fallback settings stay invisible to case generation and the
-- harness only certifies the hand-written registry.
local autoCoverageFilled = 0
if not (opts.seedOnly or opts.skipAutoCoverage) then
    local Auto = A and A.AutoCoverage
    if Auto and type(Auto.Fill) == "function" then
        autoCoverageFilled = tonumber(Auto.Fill()) or 0
    end
end

local generated, generatedActions, registrySettings, registryActions = {}, {}, 0, 0
local uncoveredSettings, uncoveredActions, readOnlySettings, disposedActions = {}, {}, {}, {}
if not opts.seedOnly then
    generated, registrySettings, uncoveredSettings, readOnlySettings = generateSettingCases(A, opts.generatedLimit, coverageDispositions)
    generatedActions, registryActions, uncoveredActions, disposedActions = generateActionCases(A, coverageDispositions)
else
    local Registry = A.Registry
    local settings = Registry and Registry.AllSettings and Registry:AllSettings() or {}
    registrySettings = #settings
    local actions = Registry and Registry.AllActions and Registry:AllActions() or {}
    registryActions = #actions
end
local registryKeyFingerprint = RuntimeManifestLoader.RegistryInventoryFingerprint(assert(A.Registry))

local cases = {}
for i = 1, #seedCases do cases[#cases + 1] = seedCases[i] end
for i = 1, #generated do cases[#cases + 1] = generated[i] end
for i = 1, #generatedActions do cases[#cases + 1] = generatedActions[i] end

local warmupMs = warmParserIndexes(A)

local results = {}
local passed = 0
for i = 1, #cases do
    local result = runCase(A, cases[i], opts.slowMs, opts.failSlow)
    results[#results + 1] = result
    if result.passed then passed = passed + 1 end
end

local readOnlySettingFailures = 0
local readOnlyStateSnapshot = snapshotPublicSmokeState(A)
for i = 1, #readOnlySettings do
    local result = runReadOnlySettingCase(A, readOnlySettings[i], opts.slowMs, opts.failSlow)
    results[#results + 1] = result
    if result.passed then passed = passed + 1 else readOnlySettingFailures = readOnlySettingFailures + 1 end
end
restorePublicSmokeState(A, readOnlyStateSnapshot)

local actionDispositionFailures = 0
for i = 1, #disposedActions do
    local result = runActionDispositionCase(disposedActions[i], opts.slowMs)
    results[#results + 1] = result
    if result.passed then passed = passed + 1 else actionDispositionFailures = actionDispositionFailures + 1 end
end

local coverageInventoryContract = runCoverageInventoryContract({
    dispositions = coverageDispositions,
    dispositionError = coverageDispositionError,
    registrySettings = registrySettings,
    registryActions = registryActions,
    generatedSettings = #generated,
    readOnlySettings = #readOnlySettings,
    generatedActions = #generatedActions,
    disposedActions = #disposedActions,
    uncoveredSettings = #uncoveredSettings,
    uncoveredActions = #uncoveredActions,
}, opts.slowMs)
results[#results + 1] = coverageInventoryContract
local coverageInventoryFailures = coverageInventoryContract.passed and 0 or 1
if coverageInventoryContract.passed then passed = passed + 1 end

local publicSmokeRunnable = ensureAssistantRuntime(opts.root, loadReport)
if publicSmokeRunnable then
    for i = 1, #publicSmokeCases do
        local result = runPublicSmokeCase(A, publicSmokeCases[i], opts.slowMs)
        results[#results + 1] = result
        if result.passed then passed = passed + 1 end
    end
else
    results[#results + 1] = {
        id = "public-smoke-loader",
        prompt = "load MSUF_Assistant.lua for public path smokes",
        category = "public-context-smoke",
        passed = false,
        reason = "MSUF_Assistant.lua did not load",
        elapsedMs = 0,
        slow = false,
        result = { kind = "error", text = "MSUF_Assistant.lua did not load" },
    }
end

local loadMisses = countLoadMisses(loadReport)
local parserFailures = #results - passed

local actionDiscoveryCases = opts.seedOnly and {} or generateActionDiscoveryCases(A)
local actionDiscoveryResults = {}
local actionDiscoveryUnknown = 0
local actionDiscoveryAmbiguous = 0
local actionDiscoveryUnsafeActions = 0
local actionDiscoveryUnexpected = 0
local actionDiscoveryFailures = 0
for i = 1, #actionDiscoveryCases do
    local item = runDiscoveryCase(A, actionDiscoveryCases[i], opts.slowMs, opts.failSlow)
    actionDiscoveryResults[#actionDiscoveryResults + 1] = item
    results[#results + 1] = item
    if item.passed then passed = passed + 1 else actionDiscoveryFailures = actionDiscoveryFailures + 1 end
    if item.classification == "unknown" then actionDiscoveryUnknown = actionDiscoveryUnknown + 1 end
    if item.classification == "ambiguous" then actionDiscoveryAmbiguous = actionDiscoveryAmbiguous + 1 end
    if item.classification == "unsafe" then actionDiscoveryUnsafeActions = actionDiscoveryUnsafeActions + 1 end
    if item.classification == "unexpected" then actionDiscoveryUnexpected = actionDiscoveryUnexpected + 1 end
end

-- Parser-only coverage is insufficient for a mutation assistant. This smoke
-- loads the real executor and proves rollback/verification/commit/undo
-- invariants through ExecutePlan. A missing smoke file is itself a hard fail.
local transactionSmokePath = join(TOOL_DIR, "..", "assistant_transaction_smoke.lua")
local transactionSmoke = runRuntimeSmokeCase(transactionSmokePath, opts.root, opts.slowMs)
results[#results + 1] = transactionSmoke
local runtimeSmokeFailures = transactionSmoke.passed and 0 or 1
if transactionSmoke.passed then passed = passed + 1 end

local ownerTransactionSmokePath = join(TOOL_DIR, "..", "assistant_owner_transaction_smoke.lua")
local ownerTransactionSmoke = runRuntimeSmokeCase(ownerTransactionSmokePath, opts.root, opts.slowMs, {
    id = "runtime-owner-transaction-smoke",
    prompt = "Owner-specific action capture/restore, undo/redo, nil factory reset, commit rollback, and fail-closed adapter invariants",
    category = "runtime-owner-transaction-smoke",
})
results[#results + 1] = ownerTransactionSmoke
if ownerTransactionSmoke.passed then
    passed = passed + 1
else
    runtimeSmokeFailures = runtimeSmokeFailures + 1
end

local slow = 0
local failures = {}
for i = 1, #results do
    if results[i].slow then slow = slow + 1 end
    if not results[i].passed then failures[#failures + 1] = results[i] end
end
local failed = #failures + loadMisses

local summary = {
    total = #results + loadMisses,
    passed = passed,
    failed = failed,
    parserFailures = parserFailures,
    slow = slow,
    failSlow = opts.failSlow == true,
    warmupMs = warmupMs,
    registrySettings = registrySettings,
    registryKeyFingerprint = registryKeyFingerprint,
    autoCoverageFilled = autoCoverageFilled,
    registryActions = registryActions,
    loadMisses = loadMisses,
    generatedCases = #generated,
    generatedReadOnlySettingCases = #readOnlySettings,
    classifiedSettingCases = #generated + #readOnlySettings,
    generatedActionCases = #generatedActions,
    reviewedNonConversationalActions = #disposedActions,
    classifiedActionCases = #generatedActions + #disposedActions,
    seedCases = #seedCases,
    publicSmokeCases = #publicSmokeCases,
    ungeneratedSettings = #uncoveredSettings,
    ungeneratedActions = #uncoveredActions,
    uncoveredSettings = #uncoveredSettings,
    uncoveredActions = #uncoveredActions,
    readOnlySettingFailures = readOnlySettingFailures,
    actionDispositionFailures = actionDispositionFailures,
    coverageInventoryFailures = coverageInventoryFailures,
    coverageDispositionVersion = type(coverageDispositions) == "table" and coverageDispositions.version or nil,
    coverageDispositionPath = coverageDispositionPath,
    actionDiscoveryCases = #actionDiscoveryCases,
    actionDiscoveryFailures = actionDiscoveryFailures,
    actionDiscoveryAmbiguous = actionDiscoveryAmbiguous,
    actionDiscoveryUnknown = actionDiscoveryUnknown,
    actionDiscoveryUnsafeActions = actionDiscoveryUnsafeActions,
    actionDiscoveryUnexpected = actionDiscoveryUnexpected,
    runtimeSmokeCases = 2,
    runtimeSmokeFailures = runtimeSmokeFailures,
}

local report = {
    summary = summary,
    failures = failures,
    results = results,
    loadReport = loadReport,
    ungeneratedSettings = uncoveredSettings,
    ungeneratedActions = uncoveredActions,
    uncoveredSettings = uncoveredSettings,
    uncoveredActions = uncoveredActions,
    actionDiscoveryResults = actionDiscoveryResults,
}

local readOnlySettingEvidence = {}
for i = 1, #readOnlySettings do
    local item = readOnlySettings[i]
    readOnlySettingEvidence[#readOnlySettingEvidence + 1] = {
        key = item.settingKey,
        label = item.setting and item.setting.label or nil,
        type = item.setting and item.setting.type or nil,
        policy = item.policyKey,
        classification = item.policy and item.policy.classification or nil,
        evidence = item.policy and item.policy.evidence or nil,
        unsafeMutationReason = item.setting and item.setting.unsafeMutationReason or nil,
        probe = item.prompt,
        aliasShadowOwner = item.aliasShadow and item.aliasShadow.resolvesTo or nil,
        aliasShadowReason = item.aliasShadow and item.aliasShadow.reason or nil,
    }
end
local actionDispositionEvidence = {}
for i = 1, #disposedActions do
    local item = disposedActions[i]
    local disposition = item.disposition or {}
    actionDispositionEvidence[#actionDispositionEvidence + 1] = {
        key = item.actionKey,
        classification = disposition.classification,
        entrypoint = disposition.entrypoint,
        reason = disposition.reason,
        expectedType = disposition.expectedType,
        expectedMutability = disposition.expectedMutability,
    }
end

writeAll(join(opts.out, "failures.json"), encodeJson({ summary = summary, failures = failures, loadReport = loadReport }))
writeAll(join(opts.out, "coverage_gaps.json"), encodeJson({
    summary = summary,
    uncoveredSettings = uncoveredSettings,
    uncoveredActions = uncoveredActions,
    reviewedReadOnlySettings = readOnlySettingEvidence,
    reviewedNonConversationalActions = actionDispositionEvidence,
}))
writeAll(join(opts.out, "action_discovery.json"), encodeJson({ summary = summary, results = actionDiscoveryResults }))
writeAll(join(opts.out, "results.json"), encodeJson(report))
writeAll(join(opts.out, "report.md"), markdownReport(summary, loadReport, results))
writeAll(join(opts.out, "repair_prompt.md"), repairPrompt(results))

io.write(string.format(
    "MSUF Assistant gate: %d/%d passed, %d gate failures (%d parser/public/coverage, %d action explanation, %d transaction), %d slow cases, %d/%d settings classified, %d/%d actions classified, %d load misses\n",
    passed,
    summary.total,
    failed,
    parserFailures,
    actionDiscoveryFailures,
    runtimeSmokeFailures,
    slow,
    #generated + #readOnlySettings,
    registrySettings,
    #generatedActions + #disposedActions,
    registryActions,
    loadMisses
))
io.write("Report: " .. join(opts.out, "report.md") .. "\n")

if failed > 0 then os.exit(1) end
os.exit(0)
