-- menu_client_capability_text_smoke.lua <repoRoot> <flavor>
--
-- Menu controls and help text that name a client capability must match the
-- running client.
--
--   1. Miscellaneous > Blizzard Frames: "Enable native Player resource pings"
--      drives Blizzard's ping system (Blizzard_PingUI, the PingableType
--      mixins). The mirror ships it on upstream/live and upstream/forever only;
--      classic_era, classic_anniversary and classic define
--      PingableUnitFrameTemplate as an empty stub (Blizzard_SharedXML/Classic/
--      Stubs.xml), so UF.ConfigurePlayerResourcePing never enables it there.
--      The switch is built on Midnight and WoW Forever and nowhere else, and
--      search offers its row there only, before and after the page is built.
--      The Classic index still carries the row until it is regenerated, and a
--      regenerated one would carry it again if the page built the switch on
--      any Classic client, so the search contract ties the row to the client
--      (STATIC_ROW_CLIENT_CAPABILITY in MSUF_Menu2_Search_IndexQuery.lua).
--   2. Auras > Dots on target: the DoT picker's help named the list "Curated
--      Retail 12.0+ and 12.1 DoT auras" on every client, while Classic Era,
--      TBC, Mists and WoW Forever load their own client's DoT catalogue. Only
--      Midnight keeps that sentence; the others say the list is curated for
--      this game version, and every pack translates the sentence shown.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_client_capability_text_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- Clients whose mirror branch ships Blizzard_PingUI.
local PING_CLIENTS = { Mainline = true, Forever = true }

local RETAIL_DOT_HELP = "Curated Retail 12.0+ and 12.1 DoT auras. Tracking is restricted to this UnitFrame's unit"
    .. " and your own aura source; Boss settings bind separately to boss1 through boss5."
local CLIENT_DOT_HELP = "Curated DoT auras for this game version. Tracking is restricted to this UnitFrame's unit"
    .. " and your own aura source; Boss settings bind separately to boss1 through boss5."

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M = mw.M
local frames = mw.world.widgets.frames

---------------------------------------------------------------------------
-- 1. Resource ping switch
---------------------------------------------------------------------------
local PING_LABEL = "Enable native Player resource pings (12.1)"
local PING_KEY = "general.playerResourcePingEnabled"
local PING_ID = "id\031opt_misc\031menu2%2Eopt%2Emisc%2Eglobal%2Esetting%2Eplayer%2Eresource%2Eping%2Eenabled"
local api = Check(M.Search and M.Search._CoreAPI, "precondition: the search core API did not load")
local function SearchOffersPing()
    api.MarkSearchIndexDirty()
    for _, rec in ipairs(api.SearchPages(PING_LABEL)) do
        if rec.searchIdentity == PING_ID or (rec.exactTarget and rec.exactTarget.settingKey == PING_KEY) then return true end
    end
    return false
end
-- The tie itself, so it keeps holding once a regenerated Classic index has no row.
local queryFile = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Search/MSUF_Menu2_Search_IndexQuery.lua", "rb"))
local querySource = queryFile:read("*a"):gsub("\r\n", "\n")
queryFile:close()
local tiedRows = assert(loadstring("return " .. Check(querySource:match("\nlocal STATIC_ROW_CLIENT_CAPABILITY = (%b{})\n"),
    "MSUF_Menu2_Search_IndexQuery.lua lost STATIC_ROW_CLIENT_CAPABILITY")))()
local capability = Check(tiedRows[PING_ID], "the resource ping search row is not tied to a client capability")
Check((mw.core.Client[capability] == true) == (PING_CLIENTS[flavor] == true),
    "the resource ping search row follows MSUF.Client." .. capability .. ", which does not match the ping system here")
local blob = Check(M.Search.StaticIndexBlob, "precondition: the static index blob is gone before any search")
local indexed = blob:find(PING_ID, 1, true) ~= nil
if PING_CLIENTS[flavor] then Check(indexed, "the index this client loads has no resource ping row") end
Check(SearchOffersPing() == (PING_CLIENTS[flavor] == true), "search " .. (PING_CLIENTS[flavor] and "misses" or "offers")
    .. " the resource ping switch before the page is built (row " .. (indexed and "in" or "not in") .. " the index)")
-- The page context is borrowed for the aura tool built in part 2.
local pageCtx
local miscSpec = M.pages.opt_misc
local miscBuild = miscSpec.build
miscSpec.build = function(ctx, ...)
    pageCtx = pageCtx or ctx
    return miscBuild(ctx, ...)
end
Check(mw:Select("opt_misc"), "Miscellaneous page did not open")
miscSpec.build = miscBuild
local pingSwitch, minimapSwitch
for _, widget in ipairs(frames) do
    local action = widget._msuf2CommandAction
    if action and action.settingKey == "general.playerResourcePingEnabled" then pingSwitch = widget end
    if action and action.settingKey == "general.showMinimapIcon" then minimapSwitch = widget end
end
Check(minimapSwitch, "precondition: the Blizzard Frames section was not built")
if PING_CLIENTS[flavor] then
    Check(pingSwitch, "the resource ping switch is missing on a client with Blizzard's ping system")
else
    Check(not pingSwitch, "the resource ping switch is built on a client without Blizzard's ping system")
end
Check(SearchOffersPing() == (PING_CLIENTS[flavor] == true), "search " .. (PING_CLIENTS[flavor] and "misses" or "offers")
    .. " the resource ping switch after the page is built")

---------------------------------------------------------------------------
-- 2. Dots on target help
---------------------------------------------------------------------------
Check(pageCtx, "precondition: no page context was captured")
local tooltips = {}
local addTooltip = M.AddTooltip
M.AddTooltip = function(widget, title, body, opts)
    tooltips[title] = body
    return addTooltip(widget, title, body, opts)
end
M.BuildAuras3CompactCustomWorkspace(pageCtx, M.Widgets.PageBuilder(pageCtx), "target", 4, "dots")
mw:RunTimers()
M.AddTooltip = addTooltip
local help = Check(tooltips["Target DoT"], "the Dots on target picker has no help")
local midnight = flavor == "Mainline"
Check(help == (midnight and RETAIL_DOT_HELP or CLIENT_DOT_HELP),
    "the DoT picker help does not describe this client's DoT list: " .. tostring(help))
-- The sentence is a whole key in every pack (enUS and enGB included).
local packs = { "enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }
for _, locale in ipairs(packs) do
    local handle = assert(io.open(root .. "/MidnightSimpleUnitFrames/Locales/" .. locale .. ".lua", "rb"))
    local text = handle:read("*a")
    handle:close()
    Check(text:find('["' .. help .. '"]', 1, true), locale .. " has no translation of the DoT picker help")
end

print("menu_client_capability_text_smoke " .. flavor .. ": OK (resource ping switch "
    .. (pingSwitch and "built" or "absent") .. ", " .. (midnight and "Retail" or "client") .. " DoT help)")
