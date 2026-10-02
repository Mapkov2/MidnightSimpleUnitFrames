-- menu_preview_focus_clear_smoke.lua <repoRoot> <flavor>
--
-- Hovering a text control on a unit page highlights its text on the docked
-- unit preview; leaving the control clears the highlight again. The clear
-- went through _G.MSUF_UFPreview_ClearFocus, a provider nothing defines (the
-- preview publishes MSUF_UFPreview_ClearTextFocus), so the highlight stayed
-- on the preview after the mouse left (review 2026-10-01, menu-core dead
-- links). W.SetPreviewFocus(nil) must clear the unit preview's text focus.
--
-- Boots the real core and Options graph of one client (menu_core_world.lua).
-- Plain Lua 5.1, repo root and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_preview_focus_clear_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { page = "uf_player" })
local M, env = mw.M, mw.env
local W = Check(M.Widgets, "Menu2 widgets missing")
Check(type(env.MSUF_UFPreview_FocusTextSlot) == "function", "the unit preview focus provider is missing")
Check(type(env.MSUF_UFPreview_ClearTextFocus) == "function", "the unit preview clear provider is missing")

-- The docked unit preview the page shows: the preview owns one active box.
local cleared = 0
local ClearTextFocus = env.MSUF_UFPreview_ClearTextFocus
env.MSUF_UFPreview_ClearTextFocus = function(...)
    cleared = cleared + 1
    return ClearTextFocus(...)
end
local focused = {}
local FocusTextSlot = env.MSUF_UFPreview_FocusTextSlot
env.MSUF_UFPreview_FocusTextSlot = function(unitKey, kind, slot, active)
    focused[#focused + 1] = { unitKey, kind, slot, active }
    return FocusTextSlot(unitKey, kind, slot, active)
end

W.SetPreviewFocus("player", "name", nil, false)
Check(#focused == 1 and focused[1][1] == "player" and focused[1][2] == "name", "hovering a text control focused nothing")
W.SetPreviewFocus(nil, nil, nil, false)
Check(cleared == 1, "leaving a text control did not clear the unit preview's text focus")

print("menu_preview_focus_clear_smoke " .. flavor .. ": ok")
