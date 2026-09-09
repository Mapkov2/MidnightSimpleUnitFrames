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

function menu.SupportsFrameScope(scope)
    local client = main.Client
    if not client then return true end
    local group = type(scope) == "string" and (scope:match("^gf_(.+)$") or scope)
    if group == "party" or group == "raid" or group == "mythicraid" then
        return not client.SupportsGroupKind or client.SupportsGroupKind(group)
    end
    return not client.SupportsUnit or client.SupportsUnit(scope)
end

function menu.NormalizeGroupScope(scope)
    return menu.SupportsFrameScope(scope) and scope or "raid"
end

function menu.SupportsUnitPage(pageKey, settingKey)
    local unit = type(pageKey) == "string" and pageKey:match("^uf_(.+)$")
    if settingKey == "general.bossTargetOutlineMode" then unit = "boss" end
    local settingScope = type(settingKey) == "string" and settingKey:match("^([^%.]+)%.")
    if settingScope and not menu.SupportsFrameScope(settingScope) then return false end
    return not unit or menu.SupportsFrameScope(unit)
end

function menu.FilterSupportedUnitValues(values)
    local client = main.Client
    if client and client.SupportsUnit then
        for i = #values, 1, -1 do
            if not menu.SupportsFrameScope(values[i].value or values[i].key) then table.remove(values, i) end
        end
    end
    return values
end
