--- Namespace adapter for MidnightSimpleUnitFrames_Assistant.
--- The load-on-demand addon receives its own private table from WoW; all
--- Assistant modules must operate on the already-loaded core MSUF namespace.

local _, private = ...
local main = _G.MSUF_NS
if type(main) ~= "table" then return end

if private == main then
    main.MSUF2 = main.MSUF2 or _G.MSUF2 or {}
    main.Assistant = main.Assistant or {}
    main.MSUF2.Assistant = main.Assistant
    return
end

private.MSUF2 = main.MSUF2 or _G.MSUF2 or {}
private.Assistant = main.Assistant or {}
private.ExportPublic = main.ExportPublic
private.Locale = main.Locale
private.Locales = main.Locales

main.MSUF2 = private.MSUF2
main.Assistant = private.Assistant
private.MSUF2.Assistant = private.Assistant

setmetatable(private, {
    __index = main,
    __newindex = function(_, key, value)
        main[key] = value
    end,
})
