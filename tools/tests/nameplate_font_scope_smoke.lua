local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local rows, scopeOptions = {}, nil
local mw = MenuWorld.Open(root, flavor, { page = "opt_fonts", beforeCore = function(world)
    local load = world.LoadFile
    function world:LoadFile(path, addon, ns)
        if arg[3] and (path:match("MSUF_Menu2_Global.lua$") or path:match("MSUF_Menu2_GlobalFonts.lua$")) then
            local relative = path:match("(MidnightSimpleUnitFrames_Options/.*)$")
            path = arg[3] .. "/" .. relative
        end
        if path:match("MSUF_Menu2_GlobalFonts.lua$") then
            self.core.SuiteLink.HasNameplateFonts = function() return true end
            local gp, schema = self.core.MSUF2.GlobalPage, self.core.MSUF2.ControlSchema
            local buildScope, buildRows = gp.BuildScopeOverrideSection, schema.Build
            gp.BuildScopeOverrideSection = function(ctx, box, opts)
                scopeOptions = opts
                return buildScope(ctx, box, opts)
            end
            schema.Build = function(ctx, box, definitions, options)
                for _, row in ipairs(definitions) do rows[row[2]] = row end
                return buildRows(ctx, box, definitions, options)
            end
        end
        return load(self, path, addon, ns)
    end
end })
local M, db = mw.M, mw.env.MSUF_DB
local globalKey, globalSize = db.general.fontKey, db.general.fontSize
scopeOptions.setValue("nameplates")
mw:RunTimers()
assert(M.GlobalPage.CurrentFontScope() == "nameplates", "nameplate font scope not selectable")
scopeOptions.setOverride(true)
mw:RunTimers()
assert(rows["font.nameplate_size"] and rows["font.nameplate_name_size"], "nameplate size controls missing")
rows["font.family"].set("EXPRESSWAY")
rows["font.nameplate_size"].set(19)
rows["font.nameplate_name_size"].set(23)
mw:RunTimers()
local selectedFont = db.nameplates.fontKey
assert(selectedFont and db.nameplates.fontSize == 19 and db.nameplates.nameFontSize == 23,
    "font controls failed to write the nameplate scope")
assert(db.general.fontKey == globalKey and db.general.fontSize == globalSize, "nameplate controls altered shared font settings")
local shared = mw.core.UF.Config.ResolveNameplateFont({})
assert(shared.fontSize == 19 and shared.nameFontSize == 23, "runtime ignored scoped sizes")
assert(shared.font == mw.core.MSUF_GetFontPathForKey(selectedFont), "runtime ignored scoped font family")
assert(rows["font.family"].get() == M.GlobalPage.FontKeyGet(), "font picker displays another scope")
scopeOptions.setOverride(false)
mw:RunTimers()
shared = mw.core.UF.Config.ResolveNameplateFont({})
assert(shared.fontSize == (db.general.fontSize or 12) and shared.nameFontSize == (db.general.nameFontSize or shared.fontSize),
    "reset failed to restore size inheritance")
assert(shared.font == mw.core.Require("MSUF_GetFontPath", "nameplate font scope test")(), "reset failed to restore font inheritance")
rows["font.family"].set("FRIZQT")
assert(db.general.fontKey == globalKey and db.nameplates.fontKey == selectedFont, "disabled scoped font edit escaped its owner")
local api = M.Search._CoreAPI
api.GetSearchRecords()
mw:RunTimers(1000)
local linked
for _, row in ipairs(api.GetSearchRecords()) do
    if row.exactTarget and row.exactTarget.settingKey == "nameplates.fontSize" then linked = row break end
end
assert(linked, "nameplate size is missing from search")
scopeOptions.setValue("shared")
mw:RunTimers(1000)
local opened, anchored, exact = api.OpenSearchTarget(linked.key, linked.label, linked.label, nil, linked.route, linked.exactTarget)
mw:RunTimers(1000)
assert(opened and anchored and exact and M.GlobalPage.CurrentFontScope() == "nameplates",
    "nameplate size search did not open its owning scope")
print("nameplate font scope " .. flavor .. ": picker, sizes, runtime, inheritance and exact search passed")

-- Compare the portable field resolver to the actual unit-frame typography
-- compiler, including native groups that do not inherit channel by channel.
db.general.fontSize, db.general.nameFontSize = 14, 17
db.general.noOutline, db.general.boldText, db.general.fontMonochrome = false, true, true
db.general.textBackdrop, db.general.fontShadowOpacity, db.general.fontShadowDistance = true, 0.55, 2
db.general.fontTextAlpha = 0.8
db.general.useCustomFontColor = true
db.general.fontColorCustomR, db.general.fontColorCustomG, db.general.fontColorCustomB = 0.2, 0.4, 0.6
db.general.nameColorMode, db.general.nameClassColor, db.general.npcNameRed = "CUSTOM", true, true
db.general.nameColorR, db.general.nameColorG, db.general.nameColorB = 0.3, 0.5, 0.7
for index, overrides in ipairs({
    { fontSize = 21 }, { noOutline = false }, { boldText = false },
    { fontColorR = 0.2 }, { fontColorG = 0.1 }, { nameColorMode = "CUSTOM", nameColorG = 0.8 },
    { fontSlug = true }, { textBackdrop = false, fontShadowStrength = "SOFT" },
}) do
    overrides.fontOverride = true
    db.nameplates = overrides
    local actual = mw.core.UF.Config.ResolveNameplateFont({})
    local portable = mw.core.NameplateSettings.ResolveTypography(overrides)
    assert(portable.fontSize == actual.fontSize and portable.nameFontSize == actual.nameFontSize, "font size parity " .. index)
    assert(portable.fontColorR == actual.textColor.r and portable.fontColorG == actual.textColor.g
        and portable.fontColorB == actual.textColor.b and portable.fontTextAlpha == actual.textColor.a, "font color parity " .. index)
    assert(portable.fontShadowOpacity == actual.fontShadowAlpha and portable.fontShadowDistance == actual.fontShadowX,
        "font shadow parity " .. index)
    assert((portable.textBackdrop and not portable.fontSlug) == actual.fontShadow, "font shadow enable parity " .. index)
    assert(portable.nameClassColor == actual.text.nameClassColor and portable.npcNameRed == actual.text.nameNpcColor,
        "name-color flag parity " .. index)
    if portable.nameColorMode == "CUSTOM" then
        assert(portable.nameColorR == actual.text.nameCustomColor.r and portable.nameColorG == actual.text.nameCustomColor.g
            and portable.nameColorB == actual.text.nameCustomColor.b, "custom name-color parity " .. index)
    end
end
print("nameplate portable typography " .. flavor .. ": eight partial override groups match the Core renderer")
