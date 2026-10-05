-- menu_locale_key_tracking_smoke.lua <repoRoot> <flavor>
--
-- Every themed font string translates its text and records it as a locale
-- key (Theme TrackLocaleKey), and off English an untranslated one as missing;
-- /msuf locale reports both tables. Composed text must use the raw setter
-- (T.SetTranslatedText). The resize grip's size label wrote every "W x H" a
-- drag passed through, and the menu scale label every "Menu N%", into both
-- tables for the rest of the session (bh2 R-C7-07).
--
-- Opens the real menu on a German client (menu_core_world.lua), drags the
-- real resize grip and moves the menu scale slider. Plain Lua 5.1, repo root
-- and client flavor.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("menu_locale_key_tracking_smoke " .. flavor .. ": " .. message, 2) end
    return condition
end

local mw = MenuWorld.Open(root, flavor, { locale = "deDE", page = "home" })
local M, env = mw.M, mw.env
local f = Check(M.frame, "the menu window was not built")
local cursorX, cursorY = 900, 500
env.GetCursorPosition = function() return cursorX, cursorY end
env.IsMouseButtonDown = function() return true end

-- Keys with a number in them, outside those the opened pages already set.
local before = {}
local function Composed()
    local list = {}
    for _, tableName in ipairs({ "localeKeys", "missingLocaleKeys" }) do
        for key in pairs(M[tableName] or {}) do
            local id = tableName .. ": " .. tostring(key)
            if type(key) == "string" and key:find("%d") and not before[id] then list[#list + 1] = id end
        end
    end
    table.sort(list)
    return list
end
for _, id in ipairs(Composed()) do before[id] = true end

-- Resize grip drag: the proxy repaints its size label on every cursor step.
local grip = Check(f.resizeGrip, "the resize grip is missing")
grip:GetScript("OnMouseDown")(grip, "LeftButton")
local proxy = Check(f._msuf2ResizeProxy, "the resize proxy is missing")
local update = Check(proxy:GetScript("OnUpdate"), "the resize proxy does not follow the cursor")
for _ = 1, 12 do
    cursorX, cursorY = cursorX + 7, cursorY - 5
    update(proxy, 0.016)
end
Check(proxy.sizeLabel and tostring(proxy.sizeLabel:GetText() or ""):find("^%d+ x %d+$"),
    "the resize proxy did not show the size")
grip:GetScript("OnHide")(grip)

-- Menu scale control: its label repaints with every slider step.
local scaled = 0
for _, frame in ipairs(mw.world.widgets.frames) do
    local parent = frame._msuf2UpdateFill and frame.GetParent and frame:GetParent()
    if parent and parent.GetParent and parent:GetParent() == f then
        for value = 80, 120, 10 do
            frame:SetValue(value)
            frame:_msuf2UpdateFill()
        end
        scaled = scaled + 1
    end
end
Check(scaled == 1, "found " .. scaled .. " menu scale sliders")

local composed = Composed()
Check(#composed == 0, "composed text became locale keys: " .. table.concat(composed, ", "))
print("menu_locale_key_tracking_smoke: " .. flavor .. " ok (resize drag and menu scale add no locale keys)")
