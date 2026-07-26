-- Contract: the complete Menu2 source tree is owned by one LoadOnDemand
-- companion while the core keeps only the small runtime/facade contracts.
local root = arg and arg[1] or "."

local function Check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

local function Equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

local function Read(relativePath)
  local file = assert(io.open(root .. "/" .. relativePath, "rb"), relativePath)
  local text = file:read("*a")
  file:close()
  return text:gsub("\r\n", "\n")
end

local function Exists(relativePath)
  local file = io.open(root .. "/" .. relativePath, "rb")
  if not file then return false end
  file:close()
  return true
end

local function Normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  repeat
    local reduced, count = path:gsub("[^/]+/%.%./", "")
    path = reduced
    if count == 0 then break end
  until false
  return path:gsub("/%./", "/"):gsub("^%./", "")
end

local function Directory(path)
  return path:match("^(.*)/[^/]+$") or ""
end

local function TocPayload(text)
  local payload = {}
  text = text:gsub("^\239\187\191", "")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      payload[#payload + 1] = Normalize(line)
    end
  end
  return payload
end

local function Metadata(text, key)
  return text:match("##%s*" .. key .. ":%s*([^\n]+)")
end

local coreRoot = "MidnightSimpleUnitFrames/"
local optionsRoot = "MidnightSimpleUnitFrames_Options/"
local assistantRoot = "MidnightSimpleUnitFrames_Assistant/"
local coreToc = Read(coreRoot .. "MidnightSimpleUnitFrames.toc")
local optionsToc = Read(optionsRoot .. "MidnightSimpleUnitFrames_Options.toc")
local assistantToc = Read(assistantRoot .. "MidnightSimpleUnitFrames_Assistant.toc")

Check(not coreToc:find("Shell\\Menu2\\", 1, true)
  and not coreToc:find("Shell/Menu2/", 1, true),
  "core TOC still eagerly owns a Menu2 payload")
Check(coreToc:find("Runtime\\MSUF_UIScaleRuntime.lua", 1, true),
  "core TOC lost the always-loaded scale runtime")
Check(coreToc:find("Runtime\\MSUF_PreviewBuildWarning.lua", 1, true),
  "core TOC lost the login preview warning")
Check(coreToc:find("Kernel\\MSUF_OptionsLoader.lua", 1, true),
  "core TOC lacks the zero-idle Options facade")

local scaleAt = assert(coreToc:find("Runtime\\MSUF_UIScaleRuntime.lua", 1, true))
local warningAt = assert(coreToc:find("Runtime\\MSUF_PreviewBuildWarning.lua", 1, true))
local loaderAt = assert(coreToc:find("Kernel\\MSUF_OptionsLoader.lua", 1, true))
local lateRuntimeAt = assert(coreToc:find("Castbars\\MSUF_InterruptReady.lua", 1, true))
Check(scaleAt < warningAt and warningAt < loaderAt and loaderAt < lateRuntimeAt,
  "core runtime/facade order no longer replaces the historical Menu2 slot")

Equal(Metadata(optionsToc, "LoadOnDemand"), "1", "Options addon LoD metadata")
Equal(Metadata(optionsToc, "Dependencies"), "MidnightSimpleUnitFrames",
  "Options addon core dependency")
Equal(Metadata(optionsToc, "Interface"), Metadata(coreToc, "Interface"),
  "Options/core Interface parity")
Equal(Metadata(optionsToc, "Version"), Metadata(coreToc, "Version"),
  "Options/core Version parity")
Check(not optionsToc:find("SavedVariables", 1, true),
  "Options addon must not own SavedVariables")

local expectedPayload = {
  "MSUF_OptionsLOD_Bootstrap.lua",
  "Shell/Menu2/MSUF_Menu2.xml",
  "Shell/Menu2/Search/MSUF_Menu2_Search.xml",
  "Shell/Menu2/MSUF_Menu2_AfterSearch.xml",
  "Shell/Menu2/Preview/MSUF_Menu2_UnitPreview.xml",
  "Shell/Menu2/MSUF_Menu2_AfterUnitPreview.xml",
  "Shell/Menu2/Preview/MSUF_Menu2_GroupPreview.xml",
  "Shell/Menu2/MSUF_Menu2_AfterGroupPreview.xml",
  "MSUF_OptionsLOD_Finalize.lua",
}
local payload = TocPayload(optionsToc)
Equal(#payload, #expectedPayload, "Options TOC payload count")
for index = 1, #expectedPayload do
  Equal(payload[index], expectedPayload[index], "Options TOC order at entry " .. index)
  Check(Exists(optionsRoot .. payload[index]), "Options TOC target missing: " .. payload[index])
end

local xmlSeen, scriptSeen = {}, {}
local xmlCount, scriptCount = 0, 0
local function VisitXml(xmlPath)
  xmlPath = Normalize(xmlPath)
  Check(not xmlSeen[xmlPath], "Menu2 XML loaded twice: " .. xmlPath)
  xmlSeen[xmlPath] = true
  xmlCount = xmlCount + 1
  local xml = Read(optionsRoot .. xmlPath)
  local base = Directory(xmlPath)

  for kind, reference in xml:gmatch("<(Script)%s+file=\"([^\"]+)\"") do
    Check(kind == "Script", "unexpected XML payload kind")
    local child = Normalize((base ~= "" and base .. "/" or "") .. reference)
    Check(child:match("^Shell/Menu2/"), "Menu2 script escapes Options ownership: " .. child)
    Check(not scriptSeen[child], "Menu2 Lua loaded twice: " .. child)
    scriptSeen[child] = true
    scriptCount = scriptCount + 1
    Check(Exists(optionsRoot .. child), "Options Menu2 script missing: " .. child)
    Check(not Exists(coreRoot .. child), "Menu2 script is duplicated in core: " .. child)
  end
  for reference in xml:gmatch("<Include%s+file=\"([^\"]+)\"") do
    VisitXml(Normalize((base ~= "" and base .. "/" or "") .. reference))
  end
end

for index = 2, #payload - 1 do
  VisitXml(payload[index])
end

Equal(xmlCount, 7, "owned Menu2 XML count")
Equal(scriptCount, 92, "owned Menu2 Lua count")
for xmlPath in pairs(xmlSeen) do
  Check(not Exists(coreRoot .. xmlPath), "Menu2 XML is duplicated in core: " .. xmlPath)
end
Check(not Exists(coreRoot .. "Shell/Menu2/MSUF_Menu2.xml"),
  "legacy core Menu2 root still exists")

local inventoryCommand = 'git -C "' .. root:gsub('"', '\\"')
  .. '" ls-files --cached --others --exclude-standard -- '
  .. '"MidnightSimpleUnitFrames/Shell/Menu2/**" '
  .. '"MidnightSimpleUnitFrames_Options/Shell/Menu2/**"'
local inventoryPipe = assert(io.popen(inventoryCommand, "r"),
  "could not start Git Menu2 ownership inventory")
local inventory, inventoryCount = {}, 0
for path in inventoryPipe:lines() do
  path = Normalize(path)
  Check(not path:match("^MidnightSimpleUnitFrames/Shell/Menu2/"),
    "Git closure still owns core Menu2 source: " .. path)
  Check(path:match("^MidnightSimpleUnitFrames_Options/Shell/Menu2/"),
    "unexpected Menu2 ownership path: " .. path)
  Check(not inventory[path], "duplicate Git Menu2 inventory path: " .. path)
  inventory[path] = true
  inventoryCount = inventoryCount + 1
end
inventoryPipe:close()
Equal(inventoryCount, 99, "Git-owned Menu2 source count")
for xmlPath in pairs(xmlSeen) do
  local path = optionsRoot:gsub("/$", "") .. "/" .. xmlPath
  Check(inventory[path], "manifest XML absent from Git closure: " .. path)
  inventory[path] = nil
end
for scriptPath in pairs(scriptSeen) do
  local path = optionsRoot:gsub("/$", "") .. "/" .. scriptPath
  Check(inventory[path], "manifest Lua absent from Git closure: " .. path)
  inventory[path] = nil
end
Check(next(inventory) == nil, "Git closure contains an orphan Menu2 file")

local dependencies = Metadata(assistantToc, "Dependencies") or ""
Check(dependencies:find("MidnightSimpleUnitFrames", 1, true)
  and dependencies:find("MidnightSimpleUnitFrames_Options", 1, true),
  "Assistant does not depend on both core and Options")
Check(dependencies:find("MidnightSimpleUnitFrames", 1, true)
    < dependencies:find("MidnightSimpleUnitFrames_Options", 1, true),
  "Assistant dependency order is not core then Options")

print("PASS: Options LoD manifest and 99-file physical ownership contract")
