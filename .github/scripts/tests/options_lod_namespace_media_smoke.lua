-- Contract: WoW passes the Options addon its own namespace and addonName.
-- Menu2 must still mutate the canonical core namespace and resolve core media.
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
  return text
end

local coreName = "MidnightSimpleUnitFrames"
local optionsName = "MidnightSimpleUnitFrames_Options"
local main = {
  AddonName = coreName,
  MSUF2 = {
    Lines = function(rows)
      return tostring(rows or ""):gmatch("[^\r\n]+")
    end,
  },
  Locale = { marker = "locale" },
  Locales = { marker = "locales" },
  ExportPublic = function(name, value)
    _G[name] = value
    return value
  end,
}
local private = {}
_G.MSUF_NS = main
_G.MSUF2 = nil

local bootstrapPath = root .. "/MidnightSimpleUnitFrames_Options/MSUF_OptionsLOD_Bootstrap.lua"
assert(loadfile(bootstrapPath))(optionsName, private)

Check(_G.MSUF_NS == main, "Options bootstrap replaced the canonical core namespace")
Equal(main.AddonName, coreName, "Options bootstrap changed the core addon identity")
Equal(main.OptionsAddonName, optionsName, "Options runtime identity")
Equal(private.AddonName, coreName, "proxied core addon identity")
Check(private.MSUF2 == main.MSUF2 and _G.MSUF2 == main.MSUF2,
  "Options did not share the canonical MSUF2 table")
Check(private.ExportPublic == main.ExportPublic
  and private.Locale == main.Locale and private.Locales == main.Locales,
  "Options namespace did not inherit core services")
private.OptionsProxyWrite = "forwarded"
Equal(main.OptionsProxyWrite, "forwarded", "Options namespace write forwarding")
Equal(rawget(private, "OptionsProxyWrite"), nil, "Options namespace leaked a shadow write")

local themePath = root
  .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua"
assert(loadfile(themePath))(optionsName, private)
local theme = assert(main.MSUF2.Theme, "theme tokens were not published to core MSUF2")
for key, path in pairs(theme.media or {}) do
  if type(path) == "string" and path:find("Interface\\AddOns\\", 1, true) then
    Check(not path:find(optionsName, 1, true),
      "theme media points at the LoD addon for " .. tostring(key) .. ": " .. path)
    Check(path:find("Interface\\AddOns\\" .. coreName .. "\\", 1, true) == 1,
      "theme media does not point at core for " .. tostring(key) .. ": " .. path)
  end
end

local previewPath = root
  .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewHelpers.lua"
assert(loadfile(previewPath))(optionsName, private)
Equal(main.MSUF2.ClassPowerPreview.MEDIA,
  "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\ClassPower\\",
  "class-power preview media root")

local inventoryCommand = 'git -C "' .. root:gsub('"', '\\"')
  .. '" ls-files --cached --others --exclude-standard -- '
  .. '"MidnightSimpleUnitFrames_Options/Shell/Menu2/**.lua"'
local inventoryPipe = assert(io.popen(inventoryCommand, "r"),
  "could not start Options Lua inventory")
local addonNameConsumers = {}
for path in inventoryPipe:lines() do
  path = path:gsub("\\", "/")
  local source = Read(path)
  local occurrences = 0
  for _ in source:gmatch("%f[%w_]addonName%f[^%w_]") do
    occurrences = occurrences + 1
  end
  -- Every Menu2 chunk receives addonName as its first vararg, but only files
  -- with another occurrence consume it for metadata or media construction.
  if occurrences > 1 then
    addonNameConsumers[#addonNameConsumers + 1] =
      assert(path:match("^MidnightSimpleUnitFrames_Options/(.+)$"))
  end
end
local inventoryOk = inventoryPipe:close()
Check(inventoryOk ~= nil, "Options Lua inventory failed")
Equal(#addonNameConsumers, 9,
  "unexpected addonName consumer count (a new consumer needs core normalization)")

local normalization = "MSUF.AddonName"
for _, relativePath in ipairs(addonNameConsumers) do
  local source = Read("MidnightSimpleUnitFrames_Options/" .. relativePath)
  local normalizeAt = source:find(normalization, 1, true)
  local entryLines = normalizeAt and select(2, source:sub(1, normalizeAt):gsub("\n", "\n")) + 1
  Check(normalizeAt and entryLines <= 15,
    "addonName is not normalized at module entry: " .. relativePath)
  Check(source:find('or "MidnightSimpleUnitFrames"', 1, true),
    "addonName consumer lacks a stable core fallback: " .. relativePath)
end

print("PASS: Options namespace proxy and real-addonName core media contract")
