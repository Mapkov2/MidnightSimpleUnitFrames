local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local loaderPath = exists("tools/assistant_runtime_manifest_loader.lua")
    and "tools/assistant_runtime_manifest_loader.lua"
    or "../tools/assistant_runtime_manifest_loader.lua"
local RuntimeManifest = dofile(loaderPath)
local assistantRoot = RuntimeManifest.ResolveCompanionRoot() .. "/Assistant/"

local banned = {
    "zeige", "anzeigen", "oeffne", "waehle", "zurueck", "rueckgaengig",
    "abbrechen", "anwenden", "ausfuehren", "einstellung", "einstellungen",
    "assistent", "nicht", "keine", "bitte", "loeschen", "kopiere",
    "verschiebe", "groesse", "hilfe", "spieler", "ziel", "auren",
    "profil", "zauberleiste", "menue", "fuer",
}

local function visibleLine(line)
    return line:find("return%s+true%s*,%s*\"", 1, false)
        or line:find("return%s+false%s*,%s*\"", 1, false)
        or line:find("text%s*=%s*\"", 1, false)
        or line:find("label%s*=%s*\"", 1, false)
        or line:find("summary%s*=%s*\"", 1, false)
        or line:find("status%s*=%s*\"", 1, false)
        or line:find("message%s*=%s*\"", 1, false)
        or line:find("error%s*=%s*\"", 1, false)
        or line:find("tooltip%s*=%s*\"", 1, false)
        or line:find("title%s*=%s*\"", 1, false)
        or line:find("help%s*=%s*\"", 1, false)
        or line:find("body%s*=%s*\"", 1, false)
        or line:find("goal%s*=%s*\"", 1, false)
        or line:find("answer%s*=%s*\"", 1, false)
        or line:find("description%s*=%s*\"", 1, false)
        or line:find("target%s*=%s*\"", 1, false)
        or line:find("valueLabel%s*=%s*\"", 1, false)
        or line:find("confirmText%s*=%s*\"", 1, false)
        or line:find("actions%s*=%s*%{", 1, false)
        or line:find("examples%s*=%s*%{", 1, false)
        or line:find("local%s+lines%s*=%s*%{", 1, false)
        or line:find("local%s+parts%s*=%s*%{", 1, false)
        or line:find("lines%[#lines%s*%+%s*1%]%s*=", 1, false)
        or line:find("parts%[#parts%s*%+%s*1%]%s*=", 1, false)
        or line:find("SetAssistantText%b()", 1, false)
        or line:find("SetStatus%b()", 1, false)
        or line:find("SetText%b()", 1, false)
        or line:find("CopyText%b()", 1, false)
        or line:find("AddTooltip%b()", 1, false)
        or line:find("AddHistory%s*%(%s*\"assistant\"%s*,%s*\"", 1, false)
end

local function startsVisibleTable(line)
    if line:find("}", 1, true) then return false end
    return line:find("local%s+lines%s*=%s*%{", 1, false)
        or line:find("actions%s*=%s*%{", 1, false)
        or line:find("examples%s*=%s*%{", 1, false)
        or line:find("local%s+parts%s*=%s*%{", 1, false)
end

local function closesVisibleTable(line)
    return line:find("^%s*%}", 1, false) ~= nil
end

local function normalize(text)
    text = tostring(text or ""):lower()
    text = text:gsub("[^%w]+", " ")
    text = text:gsub("%s+", " ")
    return " " .. text .. " "
end

local function eachString(line, fn)
    local i = 1
    while i <= #line do
        local s = line:find('"', i, true)
        if not s then return end
        local e = s + 1
        local escaped = false
        while e <= #line do
            local ch = line:sub(e, e)
            if ch == "\\" and not escaped then
                escaped = true
            elseif ch == '"' and not escaped then
                fn(line:sub(s + 1, e - 1))
                i = e + 1
                break
            else
                escaped = false
            end
            e = e + 1
        end
        if e > #line then return end
    end
end

local VISIBLE_FUNCTION_NAME_PARTS = {
    "Text", "Label", "Message", "Status", "Help", "Title", "Summary",
    "Tooltip", "Error", "Hint", "Prompt", "Greeting",
}

local function visibleFunctionName(line)
    local name = line:match("^%s*local%s+function%s+([%w_%.:]+)%s*%(")
        or line:match("^%s*function%s+([%w_%.:]+)%s*%(")
    if not name then return nil end
    if name:find("ForText", 1, true) or name:find("HasText", 1, true) then return nil end
    for i = 1, #VISIBLE_FUNCTION_NAME_PARTS do
        if name:find(VISIBLE_FUNCTION_NAME_PARTS[i], 1, true) then return name end
    end
    return nil
end

local function stripQuotedStrings(line)
    local out, i = {}, 1
    while i <= #line do
        local ch = line:sub(i, i)
        if ch ~= '"' then
            out[#out + 1] = ch
            i = i + 1
        else
            out[#out + 1] = '""'
            i = i + 1
            local escaped = false
            while i <= #line do
                ch = line:sub(i, i)
                if ch == "\\" and not escaped then
                    escaped = true
                elseif ch == '"' and not escaped then
                    i = i + 1
                    break
                else
                    escaped = false
                end
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

local function countPattern(text, pattern)
    local count = 0
    for _ in text:gmatch(pattern) do count = count + 1 end
    return count
end

local function blockDelta(line)
    line = stripQuotedStrings(line)
    local opens = countPattern(line, "%f[%w]function%f[%W]")
        + countPattern(line, "%f[%w]then%f[%W]")
        + countPattern(line, "%f[%w]do%f[%W]")
        + countPattern(line, "%f[%w]repeat%f[%W]")
    local closes = countPattern(line, "%f[%w]end%f[%W]")
        + countPattern(line, "%f[%w]until%f[%W]")
    return opens - closes
end

local checked, literals, failures = 0, 0, {}

local scripts, seenScripts = {}, {}
local function addScript(script)
    script = tostring(script or ""):gsub("\\", "/")
    if script == "" or seenScripts[script] then return end
    local handle = io.open(assistantRoot .. script, "r")
    if handle then
        handle:close()
        seenScripts[script] = true
        scripts[#scripts + 1] = script
    end
end

for _, entry in ipairs(RuntimeManifest.ReadRuntimeEntries()) do
    local script = entry.relative:match("^Assistant/(.+)$")
    if script then addScript(script) end
end

for _, script in ipairs(scripts) do
    local path = assistantRoot .. script:gsub("\\", "/")
    local file = assert(io.open(path, "r"))
    local lineNo = 0
    local inVisibleTable = false
    local visibleReturnDepth = 0
    for line in file:lines() do
        lineNo = lineNo + 1
        local scanLine = line
        scanLine = scanLine:gsub("terms%s*=%s*%b{}", "terms = {}")
        scanLine = scanLine:gsub("aliases%s*=%s*%b{}", "aliases = {}")
        scanLine = scanLine:gsub("valueAliases%s*=%s*%b{}", "valueAliases = {}")
        local startsVisibleFunction = visibleFunctionName(scanLine) ~= nil
        local inVisibleReturnFunction = visibleReturnDepth > 0 or startsVisibleFunction
        if startsVisibleTable(scanLine) then inVisibleTable = true end
        if visibleLine(scanLine)
            or inVisibleTable
            or (inVisibleReturnFunction
                and scanLine:find("return%s+\"", 1, false)
                and not scanLine:find("ContainsAny%(%s*text", 1, false)) then
            checked = checked + 1
            eachString(scanLine, function(literal)
                literals = literals + 1
                local hay = normalize(literal)
                for _, term in ipairs(banned) do
                    if hay:find(" " .. term .. " ", 1, true) then
                        failures[#failures + 1] = path .. ":" .. tostring(lineNo) .. ": " .. term .. " in " .. literal
                    end
                end
            end)
        end
        if inVisibleReturnFunction then
            visibleReturnDepth = visibleReturnDepth + blockDelta(scanLine)
            if visibleReturnDepth < 0 then visibleReturnDepth = 0 end
        end
        if inVisibleTable and closesVisibleTable(scanLine) then inVisibleTable = false end
    end
    file:close()
end

if #failures > 0 then
    for i = 1, #failures do io.stderr:write(failures[i], "\n") end
    error("assistant_visible_language_static_audit failed")
end

io.write("assistant_visible_language_static_audit: ok scripts=" .. tostring(#scripts)
    .. " lines=" .. tostring(checked)
    .. " literals=" .. tostring(literals)
    .. "\n")
