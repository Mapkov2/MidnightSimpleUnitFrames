-- Local static gate for the Unit/Group Menu2 control-catalog migration.
-- It deliberately excludes GroupAuras: that page is owned by the Aura migration.
local function exists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close(); return true end
    return false
end

local root = exists("Shell/Menu2/Pages/MSUF_Menu2_Group.lua") and "" or "MidnightSimpleUnitFrames/"
local files = {
    "Shell/Menu2/Pages/MSUF_Menu2_Group.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupBars.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupIndicators.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_GroupLayout.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_Unit.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitAlpha.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitFrameVisuals.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitRangeFade.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSectionShared.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitSections.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua",
    "Shell/Menu2/Pages/MSUF_Menu2_UnitText.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Handles.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua",
    "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_View.lua",
}

local function read(path)
    local handle, err = io.open(path, "rb")
    if not handle then error(path .. ": " .. tostring(err)) end
    local text = handle:read("*a")
    handle:close()
    return text
end

local failures, bindCalls, literalPaths, registrationMarkers = {}, 0, 0, 0
local seen = {}
local function fail(path, message)
    failures[#failures + 1] = path .. ": " .. message
end

for _, path in ipairs(files) do
    local fullPath = root .. path
    local text = read(fullPath)
    local chunk, syntaxError = loadfile(fullPath)
    if not chunk then fail(path, "syntax error: " .. tostring(syntaxError)) end
    for key in text:gmatch("settingKey%s*=%s*['\"]([^'\"]+)['\"]") do
        if not key:match("^general%.") then fail(path, "dynamic Unit/Group scope must not claim static settingKey " .. key) end
    end
    for key in text:gmatch("actionKey%s*=%s*['\"]([^'\"]+)['\"]") do
        fail(path, "dynamic Unit/Group scope must not claim static actionKey " .. key)
    end

    local count = 0
    for _ in text:gmatch("M%.Bind[%w_]*%s*%(") do count = count + 1 end
    bindCalls = bindCalls + count
    if count > 0 then
        local migrated = text:find("ControlMeta%s*%(") or text:find("ResolveGroupControlMeta%s*%(")
            or text:find("SettingMeta%s*%(") or text:find("ReviewedMeta%s*%(")
            or text:find("RegisterStatusSearch%s*%(")
        if not migrated then fail(path, tostring(count) .. " Bind call(s) have no catalog metadata route") end
    end

    local markerCount = 0
    for _ in text:gmatch("Register[%w_]*Control%s*%(") do markerCount = markerCount + 1 end
    for _ in text:gmatch("RegisterStatusSearch%s*%(") do markerCount = markerCount + 1 end
    registrationMarkers = registrationMarkers + markerCount

    -- Only fully literal semantic paths are collision-checked. Concatenated field/spec
    -- paths are intentionally dynamic and are checked by their stable runtime keys.
    local localSeen = {}
    local patterns = {
        'ControlMeta%s*%(%s*ctx%s*,%s*"([%w_%.%-]+)"%s*[,)]',
        'RegisterControl%s*%([^,]+,%s*ctx%s*,%s*"([%w_%.%-]+)"%s*,',
        'RegisterUnitPreviewControl%s*%([^,]+,%s*"([%w_%.%-]+)"%s*,',
        'RegisterGroupPreviewControl%s*%([^,]+,%s*"([%w_%.%-]+)"%s*,',
    }
    for _, pattern in ipairs(patterns) do
        for semanticPath in text:gmatch(pattern) do
            literalPaths = literalPaths + 1
            if not semanticPath:match("^[%w_%.%-]+$") then
                fail(path, "non-portable semantic path " .. semanticPath)
            elseif localSeen[semanticPath] then
                fail(path, "duplicate literal semantic path " .. semanticPath)
            else
                localSeen[semanticPath] = true
            end
            seen[path .. "\0" .. semanticPath] = true
        end
    end
end

if #failures > 0 then
    for _, message in ipairs(failures) do io.stderr:write("FAIL ", message, "\n") end
    os.exit(1)
end

print(string.format("PASS unit/group control catalog static audit: files=%d bind_calls=%d literal_paths=%d registration_markers=%d collisions=0 static_scope_claims=0",
    #files, bindCalls, literalPaths, registrationMarkers))
