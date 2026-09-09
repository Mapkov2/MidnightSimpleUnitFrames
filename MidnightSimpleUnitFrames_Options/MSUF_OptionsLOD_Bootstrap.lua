--- Bridge the private Options-addon namespace to the canonical MSUF namespace.
--- WoW gives every addon its own `...` table; Menu2 historically received the
--- main addon's table and must keep that exact read/write behavior after the
--- physical LoadOnDemand split.

local addonName, private = ...
local main = _G.MSUF_NS
if type(main) ~= "table" or type(private) ~= "table" then return end

main.OptionsAddonName = addonName

if private ~= main then
    setmetatable(private, {
        __index = main,
        __newindex = function(_, key, value)
            main[key] = value
        end,
    })
end

local menu = main.MSUF2 or _G.MSUF2 or {}
main.MSUF2 = menu
_G.MSUF2 = menu

function menu.SupportsUnitPage(pageKey, settingKey)
    local unit = type(pageKey) == "string" and pageKey:match("^uf_(.+)$")
    if settingKey == "general.bossTargetOutlineMode" then unit = "boss" end
    local client = main.Client
    return not unit or not client or not client.SupportsUnit or client.SupportsUnit(unit)
end

function menu.FilterSupportedUnitValues(values)
    local client = main.Client
    if client and client.SupportsUnit then
        for i = #values, 1, -1 do
            if not client.SupportsUnit(values[i].value or values[i].key) then table.remove(values, i) end
        end
    end
    return values
end
