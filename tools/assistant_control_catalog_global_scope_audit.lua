-- Local-only static audit for the global/advanced Menu2 catalog migration.
local addonRoot = arg[1] or "MidnightSimpleUnitFrames"

local files = {
    "Shell/Menu2/Pages/MSUF_Menu2_Global.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GlobalFonts.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GlobalMisc.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Advanced.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_AdvancedGameplay.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua",
    "Shell/Menu2/MSUF_Menu2_Dashboard.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua",
}

local function Read(relative)
    local file, err = io.open(addonRoot .. "/" .. relative, "rb")
    if not file then error(err) end
    local content = file:read("*a")
    file:close()
    return content
end

local function Normalize(value)
    local path = tostring(value or "")
    path = path:gsub("([%l%d])([%u])", "%1_%2"):lower()
    return path:gsub("[^%w]+", "."):gsub("^%.*", ""):gsub("%.*$", ""):gsub("%.+", ".")
end

local failures, bindCalls, annotatedBinds = {}, 0, 0
local rawByNormalized, declarations = {}, 0
local function Fail(message) failures[#failures + 1] = message end

local interactiveFactory = {
    Toggle = true, ToggleAt = true, SwitchAt = true, Slider = true, Dropdown = true,
    Color = true, TextInput = true, SegmentTabs = true, Button = true, TopButton = true, RoleButton = true,
}
local factorySites = 0
for _, relative in ipairs(files) do
    local content = Read(relative)
    for name in content:gmatch("W%.([%a]+)%s*%(") do if interactiveFactory[name] then factorySites = factorySites + 1 end end
    for _ in content:gmatch("T%.Button%s*%(") do factorySites = factorySites + 1 end
    for _ in content:gmatch("CreateFrame%s*%(%s*['\"]Button['\"]") do factorySites = factorySites + 1 end
end
if factorySites ~= 113 then Fail(string.format("global/advanced interactive factory inventory drifted: expected 113, got %d", factorySites)) end

local function BalancedCall(content, openAt)
    local depth, quote, escaped, lineComment = 0, nil, false, false
    for i = openAt, #content do
        local ch = content:sub(i, i)
        if lineComment then
            if ch == "\n" then lineComment = false end
        elseif quote then
            if escaped then escaped = false
            elseif ch == "\\" then escaped = true
            elseif ch == quote then quote = nil end
        elseif ch == "-" and content:sub(i + 1, i + 1) == "-" then
            lineComment = true
        elseif ch == '"' or ch == "'" then
            quote = ch
        elseif ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then return content:sub(openAt, i) end
        end
    end
end

local function AuditNamedCalls(relative, helperNames, validate)
    local content = Read(relative)
    for _, helperName in ipairs(helperNames) do
        local escapedName = helperName:gsub("([^%w_])", "%%%1")
        local cursor = 1
        while true do
            local startAt, endAt = content:find("%f[%w_]" .. escapedName .. "%s*%(", cursor)
            if not startAt then break end
            cursor = endAt + 1
            local before = content:sub(math.max(1, startAt - 24), startAt - 1)
            if content:sub(startAt - 1, startAt - 1) ~= "." and not before:match("function%s+$") then
                local call = BalancedCall(content, endAt)
                if not call then
                    local line = 1 + select(2, content:sub(1, startAt):gsub("\n", ""))
                    Fail(string.format("%s:%d unterminated %s call", relative, line, helperName))
                else
                    local ok, reason = validate(helperName, call)
                    if not ok then
                        local line = 1 + select(2, content:sub(1, startAt):gsub("\n", ""))
                        Fail(string.format("%s:%d %s %s", relative, line, helperName, reason or "has no canonical metadata"))
                    end
                end
            end
        end
    end
end

AuditNamedCalls("Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua", {
    "ColorValueAt", "ValueToggleAt", "ValueSwitchAt", "ValueSliderAt", "ValueDropdownAt",
    "SliderAt", "SwitchAt", "BindTableToggle", "CH.ButtonAt",
}, function(helperName, call)
    if helperName == "CH.ButtonAt" then
        return call:match(',%s*"[%w_%.]+"%s*%)$') ~= nil, "has no stable semantic action path"
    end
    return call:find("Meta%(") ~= nil or call:find("metadata", 1, true) ~= nil,
        "has no canonical setting metadata"
end)

AuditNamedCalls("Shell/Menu2/MSUF_Menu2_Dashboard.lua", { "Button" }, function(_, call)
    local hasLiteralPath = call:find('"bug_report%.') or call:find('"display_recovery%.')
        or call:find('"scaling%.') or call:find('"guided_setup%.')
    local hasDynamicPath = call:find("opts.semanticPath", 1, true)
    return hasLiteralPath ~= nil or hasDynamicPath ~= nil, "has no stable dashboard action path"
end)

local previewRegistrationCalls = 0
AuditNamedCalls("Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua", { "RegisterPreviewControl" }, function(_, call)
    previewRegistrationCalls = previewRegistrationCalls + 1
    local hasSemanticPath = call:find('"handle%.') or call:find('"layer%.') or call:find('"animation%.') or call:find('"keyboard%.')
        or call:find('"zoom%.') or call:find('"hint%.') or call:find('"canvas"') or call:find('"pin%.')
        or call:find('"height%.')
        or call:find("info[2]", 1, true)
    return hasSemanticPath ~= nil, "has no stable Class Resources preview semantic path"
end)

local previewSemanticPaths = {
    "canvas", "keyboard.nudge_surface", "zoom.surface", "zoom.out", "zoom.fit", "zoom.one_to_one", "zoom.in", "zoom.help",
    "hint.dismiss", "animation.toggle", "pin.toggle", "height.toggle", "layer.popover",
}
for _, key in ipairs({ "guides", "border", "reference", "class", "classText", "power", "powerText", "hp", "hpText", "bounds" }) do
    previewSemanticPaths[#previewSemanticPaths + 1] = "layer." .. key
end
for _, key in ipairs({ "classPower", "classPowerText", "detachedPower", "detachedPowerText", "playerHP", "playerHPText" }) do
    previewSemanticPaths[#previewSemanticPaths + 1] = "handle." .. key
    previewSemanticPaths[#previewSemanticPaths + 1] = "handle." .. key .. ".open_settings"
end
local previewPathsSeen = {}
for _, rawPath in ipairs(previewSemanticPaths) do
    local normalized = Normalize(rawPath)
    if previewPathsSeen[normalized] then
        Fail("Class Resources preview normalized semantic collision: " .. previewPathsSeen[normalized] .. " vs " .. rawPath)
    end
    previewPathsSeen[normalized] = rawPath
end

local bindPattern = "M%.Bind(Toggle|Slider|Segment|Dropdown|TextInput|Color|BoolWidget|NumberWidget)%s*%b()"
for _, relative in ipairs(files) do
    local content = Read(relative)
    for call in content:gmatch(bindPattern) do
        -- Lua captures only the alternation above with gmatch; balanced calls are audited below.
    end
    local cursor = 1
    while true do
        local startAt, endAt = content:find("M%.Bind[%a]+%s*%(", cursor)
        if not startAt then break end
        local name = content:sub(startAt, endAt):match("M%.(Bind[%a]+)")
        cursor = endAt + 1
        if name == "BindToggle" or name == "BindSlider" or name == "BindSegment" or name == "BindDropdown"
            or name == "BindTextInput" or name == "BindColor" or name == "BindBoolWidget" or name == "BindNumberWidget"
        then
            bindCalls = bindCalls + 1
            local call = BalancedCall(content, endAt)
            if not call then
                Fail(relative .. ": unterminated " .. name .. " call")
            elseif call:find("Meta%(") or call:find("metadata", 1, true) or call:find("opts.meta", 1, true)
                or call:find("spec.meta", 1, true) or call:find("s.meta", 1, true)
                or call:find("overrideMeta", 1, true)
                or call:find(", opts", 1, true)
            then
                annotatedBinds = annotatedBinds + 1
            else
                local line = 1 + select(2, content:sub(1, startAt):gsub("\n", ""))
                Fail(string.format("%s:%d has no catalog metadata in %s", relative, line, name))
            end
        end
    end

    for helper, rawPath in content:gmatch("([%a_]*Meta)%s*%(%s*\"([^\"]+)\"") do
        declarations = declarations + 1
        local normalized = Normalize(rawPath)
        if normalized == "" or normalized:find("[^%w_%.]") then
            Fail(relative .. ": invalid semantic path " .. rawPath)
        end
        local previous = rawByNormalized[normalized]
        if previous and previous.raw ~= rawPath then
            Fail(string.format("normalized semantic collision: %s (%s) vs %s (%s)", previous.raw, previous.file, rawPath, relative))
        else
            rawByNormalized[normalized] = { raw = rawPath, file = relative, helper = helper }
        end
    end
end

local requiredRawCoverage = {
    ["Shell/Menu2/Pages/MSUF_Menu2_GlobalBars.lua"] = { "RegisterControl(btn, Meta(\"gradient.\" .. kind .. \".direction.", "RegisterSegment(W.SegmentTabs", "RegisterDragRows(" },
    ["Shell/Menu2/Pages/MSUF_Menu2_GlobalCastbars.lua"] = { "RegisterControl(btn, Meta(semanticPath", "RegisterControl(interrupt", "RegisterControl(resetFocus" },
    ["Shell/Menu2/Pages/MSUF_Menu2_AdvancedGameplay.lua"] = { "RegisterControl(previewBtn", "RegisterControl(resetTotemBtn" },
    ["Shell/Menu2/Pages/MSUF_Menu2_AdvancedProfiles.lua"] = { "RegisterControl(profileDrop", "RegisterControl(import,", "RegisterControl(importCreateNew", "RegisterControl(importProfileName" },
    ["Shell/Menu2/Pages/MSUF_Menu2_AdvancedClassPower.lua"] = { "RegisterControl(preview,", "W.AttachContextColorReferences(resourcesCard", "RegisterControl(quick,", "RegisterSegment(W.SegmentTabs" },
    ["Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua"] = { "M.BindColor(ctx, color, getRGB, setRGB, metadata)", "RegisterControl(btn, Meta(semanticPath", "Meta(\"appearance.bar_mode\"", "Meta(\"gameplay.combat_state_color_sync\"" },
    ["Shell/Menu2/MSUF_Menu2_Dashboard.lua"] = { "RegisterDashboardControl(header", "RegisterDashboardControl(btn", "RegisterDashboardControl(head", "RegisterDashboardControl(slider", "DashboardMeta(\"support.link." },
    ["Shell/Menu2/Preview/MSUF_Menu2_ClassPowerPreview.lua"] = { "identity = pageKey .. \".class-power-preview.\"", "RegisterPreviewControl(preview._catalogCtx, h, \"handle.\"", "RegisterPreviewControl(preview._catalogCtx, gear", "RegisterPreviewControl(box._catalogCtx, btn, \"layer.\"", "RegisterPreviewControl(preview._catalogCtx, btn, \"animation.toggle\"", "RegisterPreviewControl(ctx, box, \"keyboard.nudge_surface\"", "RegisterPreviewControl(ctx, box.zoomBar, \"zoom.surface\"", "RegisterPreviewControl(ctx, box.canvas, \"canvas\"", "RegisterPreviewControl(ctx, box._msuf2PinButton, \"pin.toggle\"" },
}

local dashboard = Read("Shell/Menu2/MSUF_Menu2_Dashboard.lua")
for _, marker in ipairs({
    '"scaling.global_ui.percent", globalScaleCommand',
    'opts.semanticPath .. ".percent", command',
    'kind = "slider", min = opts.minPct, max = opts.maxPct, step = opts.stepPct, percentIsValue = true',
    'opts.apply(pct / 100)',
    'local DASHBOARD_DIRECT_BY_ACTION = {}',
    'function M.RunDashboardDirectAction(actionKey)',
    'actionKey = "dashboard.globalUiScale.apply"',
    'actionKey = "dashboard.globalUiScale.revertPending"',
    'actionKey = "dashboard.globalUiScale.disable"',
    'actionKey = "dashboard.msufFrameScale.apply"',
    'actionKey = "dashboard.msufFrameScale.revertPending"',
    'actionKey = "dashboard.menuScale.apply"',
    'actionKey = "dashboard.menuScale.revertPending"',
    'actionKey = "guided_setup"',
    'actionKey = "copy_support_link"',
}) do
    if not dashboard:find(marker, 1, true) then
        Fail("Dashboard scale assistant command is missing marker: " .. marker)
    end
end
for relative, needles in pairs(requiredRawCoverage) do
    local content = Read(relative)
    for _, needle in ipairs(needles) do
        if not content:find(needle, 1, true) then Fail(relative .. ": missing raw-control coverage marker: " .. needle) end
    end
end

if #failures > 0 then
    for _, failure in ipairs(failures) do io.stderr:write("GLOBAL CONTROL AUDIT FAIL: " .. failure .. "\n") end
    os.exit(1)
end

print("GLOBAL/ADVANCED CONTROL CATALOG STATIC AUDIT PASS")
print(string.format("Files: %d; annotated Bind call sites: %d/%d; direct semantic declarations: %d",
    #files, annotatedBinds, bindCalls, declarations))
print(string.format("Interactive factory drift sentinel: %d/%d", factorySites, 113))
print("Normalized semantic-path collisions: 0; required raw-button/selector coverage markers: present")
print(string.format("Class Resources preview: %d registration call sites; %d generated canonical controls; collisions: 0",
    previewRegistrationCalls, #previewSemanticPaths))
