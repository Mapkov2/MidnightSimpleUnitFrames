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
