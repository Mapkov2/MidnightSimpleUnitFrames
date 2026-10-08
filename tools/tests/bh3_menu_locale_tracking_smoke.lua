local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/"
-- Probe C24 (KNOWN R-C7-07, new trigger): every distinct composed string set on a T.Font
-- FontString is kept forever in M.localeKeys (Theme.lua:62-73, 85-90, 2084, 2096).
-- Trigger: ClassPowerPreview.lua:547 sets "%s   x: %d   y: %d" through hint:SetText on each move.
local ns = { Translate = function(s) return s end, GetEffectiveLocale = function() return "enUS" end }
ns.MSUF2 = {
    Assign = function(t, v) for k, x in pairs(v) do t[k] = x end end,
    WordList = function(s) local t = {} for v in s:gmatch("%S+") do t[#t + 1] = v end return t end,
    Theme = { colors = { text = { 1, 1, 1 } }, ApplyMenuAccent = function() end },
}
IsLoggedIn = function() return true end
assert(loadfile(ROOT .. "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua"))("MidnightSimpleUnitFrames", ns)
local T = ns.MSUF2.Theme
T.StyleFontString = function(fs) return fs end
local parent = { CreateFontString = function() return { SetText = function(self, s) self.text = s end } end }
local hint = T.Font(parent, "GameFontDisableSmall", "Click to open settings. Move resources in Edit Mode.")
for i = 1, 1000 do hint:SetText(string.format("%s   x: %d   y: %d", "Resource", i, 0)) end
print("retained keys after 1000 positions:", (ns.MSUF2.GetLocaleCoverage()))
for i = 1001, 2000 do hint:SetText(string.format("%s   x: %d   y: %d", "Resource", i, 0)) end
print("retained keys after 2000 positions:", (ns.MSUF2.GetLocaleCoverage()))

for i = 2001, 20000 do hint:SetText("Dynamic coordinate " .. i) end
assert(ns.MSUF2.GetLocaleCoverage() <= 8192, "locale diagnostics retain unbounded dynamic strings")
