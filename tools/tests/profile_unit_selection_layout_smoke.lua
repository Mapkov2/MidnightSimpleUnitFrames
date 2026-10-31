-- profile_unit_selection_layout_smoke.lua <repoRoot> <flavor>
--
-- The Profiles page note under the "Selected unitframes" switches
-- (Pages/MSUF_Menu2_AdvancedProfiles.lua, ProfilesPage.UnitSelection) sits a
-- full row below the last frame switch, also where Arena Frames adds a fifth
-- row, and inside the section's height. Built on the client's real menu.
-- Plain Lua 5.1, repo root and flavor as arguments.

local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home" })
local M = mw.M
local NOTE = "Includes each frame's own settings, auras and castbar. Shared appearance settings stay unchanged."

local function Check(condition, message)
    if not condition then error(flavor .. ": " .. message, 2) end
    return condition
end
local function OffsetY(region)
    local _, _, _, _, y = region:GetPoint(1)
    return y
end

Check(mw:Select("profiles"), "the Profiles page did not open")
mw:RunTimers()
local page = Check(M.cache.profiles, "the Profiles page did not build")

local section, lowest, count = nil, nil, 0
for _, widget in ipairs(page.searchWidgets) do
    local record = widget._msuf2RuntimeControlRecord
    if record and record.controlId:find("export.unit.", 1, true) then
        local y = Check(OffsetY(widget), "a frame switch has no anchor: " .. record.controlId)
        section = section or widget:GetParent()
        Check(widget:GetParent() == section, "the frame switches do not share one section")
        count = count + 1
        if not lowest or y < lowest then lowest = y end
    end
end
Check(count > 0, "the Selected unitframes section built no frame switch")

local function FindNote(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetText and region:GetText() == NOTE then return region end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local found = FindNote(child)
        if found then return found end
    end
end
local note = Check(FindNote(section), "the Selected unitframes note is missing")
local noteY = Check(OffsetY(note), "the note has no anchor")
Check(noteY <= lowest - 28, ("the note at y %d overlaps the last frame switch at y %d"):format(noteY, lowest))
Check((section:GetHeight() or 0) >= 24 - noteY,
    ("the section height %s clips the note at y %d"):format(tostring(section:GetHeight()), noteY))

print(("profile_unit_selection_layout_smoke: ok (%s, %d switches, note at y %d)"):format(flavor, count, noteY))
