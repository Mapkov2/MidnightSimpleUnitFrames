--- Last-file readiness marker used by the core loader. Reaching this file
--- proves that every Menu2 XML manifest and script was visited in TOC order.

local _, private = ...
local main = _G.MSUF_NS
if type(main) ~= "table" then return end

local menu = main.MSUF2 or _G.MSUF2
local requiredFunctions = {
    "Open",
    "Toggle",
    "SelectPage",
    "OpenExactSettingControl",
    "OpenExactColorSettingPicker",
    "OpenExactCatalogControl",
    "ShowLocaleReloadRequired",
}
if type(menu) ~= "table" then
    main.OptionsLODLoadError = "MSUF2 namespace missing"
    return
end
for i = 1, #requiredFunctions do
    local name = requiredFunctions[i]
    local stillStubbed = type(main.OptionsLODMenuStubs) == "table"
        and main.OptionsLODMenuStubs[name] == menu[name]
    if type(menu[name]) ~= "function" or stillStubbed then
        main.OptionsLODLoadError = "MSUF2." .. name .. " missing"
        return
    end
end
for _, name in ipairs({ "Theme", "Widgets", "ApplyService", "SearchBridge", "pages" }) do
    if type(menu[name]) ~= "table" then
        main.OptionsLODLoadError = "MSUF2." .. name .. " missing"
        return
    end
end

local globalStubs = main.OptionsLODGlobalStubs
if type(globalStubs) == "table" then
    for name, stub in pairs(globalStubs) do
        if rawget(_G, name) == stub then
            main.OptionsLODLoadError = name .. " still stubbed"
            return
        end
    end
end

local commandSpecs = main.OptionsLODCommandSpecs
local commands = main.SlashCommands
if type(commandSpecs) == "table" and type(commands) == "table"
    and type(commands.Get) == "function"
then
    for i = 1, #commandSpecs do
        local name = commandSpecs[i].name
        local entry = commands.Get(name)
        if type(entry) == "table" and entry._msufOptionsLODDeferred == true then
            main.OptionsLODLoadError = "slash command " .. tostring(name) .. " still deferred"
            return
        end
    end
end

main.OptionsLODLoadError = nil
main.OptionsLODReady = true
main.OptionsLODLoadCount = (tonumber(main.OptionsLODLoadCount) or 0) + 1
main.OptionsLODCommandSpecs = nil

if type(private) == "table" and private ~= main then
    private.OptionsLODReady = true
end
