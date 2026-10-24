local root = assert(arg[1])
local Slice = assert(loadfile(root .. "/.github/scripts/msuf_source_slice.lua"))()
local path = arg[2] or root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras.lua"
local source = Slice.Read(path)
local methods = {}
local function Widget()
    return setmetatable({ scripts = {}, shown = true, events = {} }, { __index = methods })
end
function methods:SetScript(k, v) self.scripts[k] = v end
function methods:HookScript(k, v) self.scripts[k] = v end
function methods:GetScript(k) return self.scripts[k] end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
function methods:RegisterEvent(k) self.events[k] = true end
function methods:UnregisterEvent(k) self.events[k] = nil end
function methods:CreateTexture() return Widget() end
for _, k in ipairs({"SetSize", "SetPoint", "SetFrameStrata", "SetMovable", "EnableMouse", "RegisterForDrag", "SetClampedToScreen", "SetJustifyH", "SetText"}) do methods[k] = function() end end
local M = { frame = Widget(), MenuRuntime = {}, Format = string.format }
local settlers, reads = {}, 0
function M.MenuRuntime:SetQuiesceSettler(k, f) settlers[k] = f end
local combat = false
function M.IsConfigCombatLocked() return combat end
local Model = { LiveBlacklistAuraValues = function() reads = reads + 1; return {}, 0, false end }
local T = { colors = {}, Font = function() return Widget() end, SetTranslatedText = function() end }
local env = setmetatable({ M = M, Model = Model, T = T, UIParent = Widget(), CreateFrame = Widget,
    PixelLayoutRegion = function(w) return w end, ActionButton = Widget, Tr = function(s) return s end }, { __index = _G })
local chunk = assert(loadstring(Slice.Function(source, "local function EnsureAuraCombatScanner", path) .. "\nreturn EnsureAuraCombatScanner"))
setfenv(chunk, env)
local scanner = chunk()()
scanner._scope, scanner._lane, scanner._recent, scanner._scanning = "player", "buff", {}, true
if scanner.Resume then scanner.Resume() else scanner:Show() end
scanner:GetScript("OnUpdate")(scanner, 0.4)
assert(reads == 1, "open scanner did not scan")
for _, f in pairs(settlers) do f("menu-hide") end
local callback = scanner:GetScript("OnUpdate")
for i = 1, 25 do if callback then callback(scanner, 0.4) end end
print("scanner closed, 10 s: " .. (reads-1) .. " aura reads; OnUpdate=" .. tostring(callback ~= nil))
assert(reads == 1 and callback == nil and not next(scanner.events), "closed scanner still polls/listens")
local resume = M.frame:GetScript("OnShow")
assert(resume, "scanner has no reopen route")
combat = true
resume()
assert(scanner:GetScript("OnUpdate") == nil, "combat resumed a paused scanner")
combat = false
resume()
scanner:GetScript("OnUpdate")(scanner, 0.4)
assert(reads == 2 and scanner:IsShown(), "reopen lost scan session")
scanner.Finish(false)
assert(not scanner._scanning and not scanner:GetScript("OnUpdate") and not next(scanner.events), "stopped scanner resumes")
resume()
assert(not scanner:GetScript("OnUpdate"), "finished scan restarted")
