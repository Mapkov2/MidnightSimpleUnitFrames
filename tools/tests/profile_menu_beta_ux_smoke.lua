local root, flavor = assert(arg[1]):gsub("\\", "/"), arg[2] or "Forever"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = MenuWorld.InstallNativeUnitInputs })
local M, core = mw.M, mw.core
assert(mw:Select("profiles") ~= false)

local function Drain()
    for _ = 1, 30 do
        if #mw.world.widgets.timers == 0 then return end
        mw:RunTimers(1000)
    end
    error("menu timers did not settle")
end
Drain()
local entry = assert(M.cache.profiles)

local function Find(frame, label)
    if frame.GetText and frame:GetText() == label then return frame end
    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetText and region:GetText() == label then return region end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        local found = Find(child, label)
        if found then return found end
    end
end

local function Control(suffix)
    for _, widget in ipairs(entry.searchWidgets or {}) do
        local record = widget._msuf2RuntimeControlRecord
        if record and record.controlId:sub(-#suffix) == suffix then return widget end
    end
    error("control missing: " .. suffix)
end

local switch = assert(Find(entry.wrapper, "Switch profile"))
local switchButton = switch:GetObjectType() == "Button" and switch or switch:GetParent()
local hero = switchButton:GetParent()
assert(not Find(hero, "Export backup"), "old one-click export shortcut is still present")
local link = assert(Find(hero, "Import & Export"), "import/export shortcut is missing")
local linkButton = link:GetObjectType() == "Button" and link or link:GetParent()
local _, relative, point, _, y = linkButton:GetPoint()
assert(relative == switchButton and point == "BOTTOMRIGHT" and y < 0, "shortcut is not in the second row")

local ioSection = assert(entry.sections.profiles_io)
local management = assert(entry.sections.profiles_management)
local chooser = assert(entry.sections.profiles_unit_selection)
local ioEntry, manageEntry = ioSection._msuf2CollapsibleEntry, management._msuf2CollapsibleEntry
assert(not ioEntry.open and manageEntry.open, "unexpected default section state")
assert(ioEntry.guidedOrder > manageEntry.guidedOrder and chooser._msuf2CollapsibleEntry.guidedOrder > ioEntry.guidedOrder,
    "transfer and export controls are out of order")
local export = core.PublicGlobals.MSUF_ExportSelectionToString
local exports = 0
core.PublicGlobals.MSUF_ExportSelectionToString = function()
    exports = exports + 1
    return "unexpected export"
end
local before = M.profileImportString
linkButton:Click()
Drain()
assert(ioEntry.open and exports == 0 and M.profileImportString == before, "shortcut serialized or rewrote the draft")
core.PublicGlobals.MSUF_ExportSelectionToString = export

local box = Control("import.export.buffer")
local selectionHint = "Choose which frames to include when exporting Selected unitframes."
assert(Find(chooser, selectionHint), "unit-frame selection is not presented as export-only")
assert(not Control("import.export.quick.mode"):GetChecked(), "quick mode replaced the default full editor")

local raw = "MSUFS3:MSUF3:" .. string.rep("A", 100000) .. "\r\nMSUFM1:MSUF3:É雪\r\nMSKIN1:" .. string.rep("B", 6000)
box:SetText(raw)
MenuWorld.FireScript(box, "OnTextChanged", true)
assert(M.profileImportString == raw and box:GetText() == raw, "normal editor changed multiline input")

local target = Control("import.create.new.mode")
local name = Control("import.new.profile.name")
local legacy
for _, child in ipairs({ name:GetParent():GetChildren() }) do
    local label = child._msuf2Label
    if label and label:GetText() == "Old profile is from Retail" then legacy = child end
end
assert(legacy, "legacy source switch missing")
assert(not legacy:GetChecked(), "new strings inherit the Retail origin flag")
assert(not legacy:IsEnabled(), "Retail source is offered for a Suite bundle it cannot affect")
box:SetText("MSUF3:standalone profile")
MenuWorld.FireScript(box, "OnTextChanged", true)
assert(legacy:IsEnabled(), "Retail source remains disabled for a standalone MSUF profile")
if not target:GetChecked() then target:Click() end
Drain()
assert(name:IsVisible(), "the new profile name is hidden")
local _, _, _, _, legacyY = legacy:GetPoint()
local _, _, _, _, titleY = name._msuf2Title:GetPoint()
assert(legacyY - legacy:GetHeight() > titleY, "the legacy source switch overlaps the profile name")
legacy:Click()
assert(legacy:GetChecked(), "cannot select Retail as the legacy source")
MenuWorld.FireScript(box, "OnTextChanged", true)
assert(legacy:GetChecked(), "unchanged input lost its source selection")
box:SetText("different profile")
MenuWorld.FireScript(box, "OnTextChanged", true)
assert(not legacy:GetChecked(), "changed input retained the old source selection")

M.profileExportKind = "unitselection"
M.profileExportUnits = { player = true, target = false }
local exportButton = Control("export.generate")
core.PublicGlobals.MSUF_ExportSelectionToString = function(kind, units)
    assert(kind == "unitselection" and units.player and units.target == false, "wrong export selection")
    return "selected frame export"
end
assert(exportButton:Click() == true and box:GetText() == "selected frame export", "export could not fill the field")
core.PublicGlobals.MSUF_ExportSelectionToString = export
print(flavor .. ": beta profile shortcut, full editor, Retail source and selected-frame export passed")
