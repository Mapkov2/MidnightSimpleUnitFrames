local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2])
local path = root .. "/MidnightSimpleUnitFrames/Features/Diagnostics/MSUF_Feature_TaintReport.lua"
local Manifest = dofile(root .. "/tools/tests/client_manifest.lua")
local toc = flavor == "Forever" and "Mainline" or flavor
local gameType = flavor == "Forever" and "camelot" or (flavor == "Mainline" and "standard" or nil)
local found = false
for _, file in ipairs(Manifest.Paths(root, toc, "enUS", gameType)) do
    if file == path then found = true end
end
assert(found, "report is not in the active client TOC")

local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local secret = Secrets.New("string")
local stopWatching = Secrets.Watch(path, { strict = true })
local combat, frames, stackReads = false, {}, 0
local now, command = "2026-11-16 10:00:00"
local blocked, forbidden = "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN"
local control = {}
function control:SetScript(event, callback) self.scripts[event] = callback end
function control:RegisterEvent(event) self.events[event] = true end
function control:UnregisterAllEvents() self.events = {} end
function control:IsShown() return self.visible end
function control:Show() self.visible = true end
function control:Hide()
    self.visible = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function control:SetText(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function control:SetFocus() self.focused = true end
function control:HighlightText() assert(self.focused); self.highlighted = true end
function control:ClearFocus() self.focused = false end
local function NewControl(kind, parent)
    return setmetatable({ kind = kind, parent = parent, scripts = {}, events = {}, visible = true },
        { __index = function(_, key) return control[key] or function() end end })
end
function control:CreateTexture() return NewControl("Texture", self) end
function control:CreateFontString() return NewControl("FontString", self) end
UIParent = {}
function CreateFrame(kind, name, parent)
    assert(name == nil, "diagnostic exported a frame global")
    local frame = NewControl(kind, parent)
    frames[#frames + 1] = frame
    return frame
end
function GetBuildInfo() return "test-version", "test-build" end
function date() return now end
function debugstack()
    stackReads = stackReads + 1
    if stackReads == 1 then return "stack at protected call" end
    return secret
end

local core = {
    Client = { IsSupported = true, Flavor = toc, IsForever = flavor == "Forever", Interface = 321 },
    Util = { IsSecret = issecretvalue, InCombat = function() return combat end },
    L = setmetatable({}, { __index = function(_, key) return key end }),
    GetAddonVersion = function() return "7.0" end,
    SlashCommands = { Register = function(entry)
        assert(entry.name == "taint")
        command = entry.run
    end },
}
assert(loadfile(path))("MidnightSimpleUnitFrames", core)
assert(#frames == 0 and command, "report touched the frame system on cold load")
combat = true
command()
assert(#frames == 0, "report built a dialog while in combat")
combat = false
command()
local panel = frames[1]
local edit = panel.edit
local startButton = panel.toggle
local copyButton, closeButton
for _, frame in ipairs(frames) do
    if frame.kind == "Button" and frame.text == "Copy report" then copyButton = frame end
    if frame.kind == "Button" and frame.text == "Close" then closeButton = frame end
end
assert(edit and copyButton and closeButton and #frames == 6)
local function Click(frame) frame.scripts.OnClick(frame) end
local function Contains(value) assert(edit.text:find(value, 1, true), value) end
Contains("Client: " .. (flavor == "Forever" and "WoW Forever" or flavor) .. " test-version")
Contains("(build test-build, interface 321)")
Contains("No blocked actions recorded.")
Click(startButton)
local listener = frames[#frames]
assert(listener.events[blocked] and listener.events[forbidden] and rawget(listener, "parent") == nil)
Click(closeButton)
local function Fire(event, addon, action)
    assert(listener.events[event])
    listener.scripts.OnEvent(listener, event, addon, action)
end
Fire(blocked, "ExampleAddon", "UseAction()")
now = "2026-11-16 10:00:01"
Fire(blocked, "ExampleAddon", "UseAction()")
assert(stackReads == 1, "duplicate blocks failed to coalesce")
combat = true
Fire(forbidden, secret, secret)
combat = false
command()
Click(copyButton)
assert(edit.focused and edit.highlighted)
Contains("2026-11-16 10:00:00  ADDON_ACTION_BLOCKED  (2 occurrence(s))")
Contains("Last occurrence: 2026-11-16 10:00:01")
Contains("Reported addon: ExampleAddon")
Contains("Protected action: UseAction()")
Contains("Stack at first event:\nstack at protected call")
Contains("Reported addon: (unavailable)\nProtected action: (unavailable)\nCombat lockdown: yes")
local snapshot = edit.text
edit.text = "discard this edit"
edit.scripts.OnTextChanged(edit, true)
assert(edit.text == snapshot, "manual input changed the report")

for i = 1, 25 do Fire(blocked, "Flood", tostring(i)) end
Click(copyButton)
Contains("Older occurrences omitted: 8")
Contains("Protected action: 25")
assert(not edit.text:find("ExampleAddon", 1, true), "old blocks survived the cap")
core.TaintReport.Stop()
assert(next(listener.events) == nil and panel.toggle.text == "Start new recording")
Click(startButton)
Contains("No blocked actions recorded.")
assert(not edit.text:find("Older occurrences omitted:", 1, true))
local longAddon = string.rep("a", 159)
Fire(blocked, longAddon .. string.char(195, 164), "Cut on a UTF-8 boundary")
Click(copyButton)
Contains("Reported addon: " .. longAddon .. "\n")
Click(startButton)
assert(next(listener.events) == nil)
local violations = stopWatching()
assert(#violations == 0, table.concat(violations, "\n"))
print("taint_report_smoke " .. flavor .. ": PASS")
