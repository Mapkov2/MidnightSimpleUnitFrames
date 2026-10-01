-- MSUF_SetFontChecked reports an unavailable font on the Mainline family so
-- every caller's fallback font can run (review F11: it returned true on every
-- client, so a missing SharedMedia font left a FontString without a font on
-- Midnight and WoW Forever). Classic clients keep reporting success because a
-- cold Classic client's SetFont result is no readiness guarantee.
-- Usage: lua tools/tests/font_checked_family_smoke.lua <repoRoot>
local repo = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
local function Load(family)
    _G.MSUF_SetFontChecked = nil
    local ns = { UF = {}, Client = { Family = family, IsClassic = family == "Classic" } }
    ns.ExportPublic = function(name, value) _G[name] = value end
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua"))("MidnightSimpleUnitFrames", ns)
    return assert(_G.MSUF_SetFontChecked, "MSUF_SetFontChecked not published")
end
local function FontString(result)
    return { SetFont = function(self, path, size, flags) self.path, self.size, self.flags = path, size, flags; return result end }
end
for _, family in ipairs({ "Mainline", "Classic" }) do
    local check = Load(family)
    local fs = FontString(false)
    local ok = check(fs, "Interface\\AddOns\\Missing\\Font.ttf", 12, "OUTLINE")
    assert(fs.path and fs.size == 12, family .. ": SetFont was not called")
    if family == "Mainline" then
        assert(ok == false, "Mainline: an unavailable font was reported as applied")
    else
        assert(ok == true, "Classic: a cold-client SetFont result aborted the font application")
    end
    assert(check(FontString(true), "Fonts\\FRIZQT__.TTF", 12, "") == true, family .. ": an applied font was reported as failed")
end
print("font_checked_family_smoke: OK")
