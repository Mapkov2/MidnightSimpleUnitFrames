-- menu_page_reset_catalog_smoke.lua <repoRoot> <flavor>
--
-- Page resets keep hand-written key lists (MSUF_Menu2_Bindings_Reset.lua),
-- and those lists drifted from the controls each page shows: five fixes in a
-- row added a setting a page showed but its reset left at the user's value
-- (bh2 R-C7-01; R-C7-M1 was the live case on Miscellaneous). This gate opens
-- every global page that has a reset, with every lazy section built, takes the
-- "root.key" setting of each control the page registers in the runtime
-- control catalog, dirties all of them, runs the real reset and requires each
-- one back at its factory value. A control added later without its reset key
-- fails here. KNOWN lists the settings no reset owns today, each with its
-- reason; an entry that a reset starts to cover fails too, so the list
-- shrinks with the code.
--
-- Boots the real core and Options graph and opens the real menu
-- (menu_core_world.lua). Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_page_reset_catalog_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

-- Settings a page shows that its reset does not restore, and why.
-- Miscellaneous has no entry: its reset owns every setting the page shows,
-- the menu motion, accent, appearance and MapkoSkin switches included.
local KNOWN = {
    classpower = {
        ["general.classPowerPreviewGuidesEnabled"] = "menu preview preference (ProfileFields: menu preferences)",
        ["menu.classPowerPreviewResource"] = "menu preview state",
    },
    opt_colors = {
        -- Control ids, not saved keys: the R/G/B channels they edit are reset.
        ["general.healthGradientHigh"] = "control id; its R/G/B channels are reset",
        ["general.healthGradientMid"] = "control id; its R/G/B channels are reset",
        ["general.healthGradientLow"] = "control id; its R/G/B channels are reset",
    },
}
local PAGES = { "opt_bars", "opt_fonts", "opt_castbar", "opt_misc", "classpower", "gameplay", "modules", "opt_colors" }

local mw = MenuWorld.Open(root, flavor, { page = "home" })
local M, env, core = mw.M, mw.env, mw.core
-- The runtime fanout after a reset is outside this contract.
for _, name in ipairs({ "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_ClassPower_Apply",
    "MSUF_ForceReanchorAllUnitFrames_Once" }) do env[name] = function() return true end end
M.ApplyService.Flush = function() return true end
local F = Check(core.ProfileFields, "ProfileFields did not load")
-- The harness cannot decode the embedded factory string, so the booted profile
-- is the factory baseline every reset returns to.
local factory = Check(F.CopySnapshot(M.EnsureDB()), "booted profile is not snapshot-safe")
core.MSUF_CreateFactoryDefaultProfile = function() return (F.CopySnapshot(factory)) end
local function Restore()
    local live = M.EnsureDB()
    for key in pairs(live) do live[key] = nil end
    for key, value in pairs(F.CopySnapshot(factory)) do live[key] = value end
    return live
end
local Catalog = Check(M.RuntimeControlCatalog, "the runtime control catalog is missing")
M.EagerSections = true -- Build closed lazy sections too, as a hidden search build does.
-- The two Miscellaneous settings the menu applies live, not at the next
-- build: a reset that changes them must repaint the menu skin and the
-- background opacity, as their controls do. Only the MSUF Forever look
-- installs the opacity refresher; elsewhere its slider stays disabled.
local liveApplied = {}
local skin = Check(core.MenuSkin, "MSUF.MenuSkin did not load")
local SkinRefresh = skin.Refresh
skin.Refresh = function(...)
    liveApplied["general.mapkoSkinMenus"] = true
    return SkinRefresh(...)
end
local OpacityRefresh = M.Theme.RefreshMenuBackgroundOpacity
if OpacityRefresh then
    M.Theme.RefreshMenuBackgroundOpacity = function(...)
        liveApplied["general.menuBackgroundOpacity"] = true
        return OpacityRefresh(...)
    end
end

local SENTINEL = "__menu_page_reset_catalog_smoke__"
local checked, pages = 0, 0
for _, pageKey in ipairs(PAGES) do
    if M.pages and M.pages[pageKey] then
        Check(M.PageHasReset(pageKey), pageKey .. " lost its page reset")
        M.Open(pageKey)
        mw:RunTimers()
        local paths, order = {}, {}
        for _, record in ipairs(Catalog.GetRecords()) do
            if record.pageKey == pageKey then
                local keys = { record.settingKey }
                for _, key in ipairs(record.searchSettingKeys or {}) do keys[#keys + 1] = key end
                for _, key in ipairs(keys) do
                    local rootKey, leaf = tostring(key):match("^([%w_]+)%.([%w_]+)$")
                    if rootKey and not paths[key] then
                        paths[key] = { rootKey, leaf }
                        order[#order + 1] = key
                    end
                end
            end
        end
        table.sort(order)
        local live = Restore()
        for _, key in ipairs(order) do
            local path = paths[key]
            live[path[1]] = type(live[path[1]]) == "table" and live[path[1]] or {}
            live[path[1]][path[2]] = SENTINEL
        end
        for key in pairs(liveApplied) do liveApplied[key] = nil end
        local ok, result = pcall(M.ResetPageToDefaults, pageKey)
        Check(ok and result == true, "resetting " .. pageKey .. " failed: " .. tostring(result))
        live = M.EnsureDB()
        local known, kept, stale = KNOWN[pageKey] or {}, {}, {}
        for _, key in ipairs(order) do
            local path = paths[key]
            local left = type(live[path[1]]) == "table" and live[path[1]][path[2]] == SENTINEL
            if left and not known[key] then kept[#kept + 1] = key end
            if not left and known[key] then stale[#stale + 1] = key end
        end
        Check(#kept == 0, "Reset " .. pageKey .. " leaves these settings its page shows at the user's value: "
            .. table.concat(kept, ", ") .. " (add them to its reset keys, or to KNOWN with the reason)")
        Check(#stale == 0, "Reset " .. pageKey .. " now restores " .. table.concat(stale, ", ")
            .. "; remove them from KNOWN")
        if pageKey == "opt_misc" then
            for key, refresher in pairs({ ["general.mapkoSkinMenus"] = SkinRefresh,
                ["general.menuBackgroundOpacity"] = OpacityRefresh }) do
                Check(not (paths[key] and refresher) or liveApplied[key], "Reset opt_misc restored " .. key
                    .. " but left the open menu showing the old value")
            end
        end
        checked, pages = checked + #order, pages + 1
    end
end
Check(pages >= 7 and checked >= 100, "the gate saw only " .. pages .. " pages and " .. checked .. " settings")

print(string.format("menu_page_reset_catalog_smoke: %s ok (%d settings on %d page resets restored or KNOWN)",
    flavor, checked, pages))
