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
local characterParts = "name_shortening.character_name_parts"
assert((rows[characterParts] ~= nil) == (flavor == "Forever"), "wrong Shared character-name visibility")
rows[characterParts], rows["menu2.opt_fonts.name_shortening.scopeNotice"] = nil, nil
scopeOptions.setValue("nameplates")
mw:RunTimers()
assert(M.GlobalPage.CurrentFontScope() == "nameplates", "nameplate font scope not selectable")
assert(not rows[characterParts], "Nameplates duplicates Shared character names")
assert(not rows["menu2.opt_fonts.name_shortening.scopeNotice"], "Nameplates repeats the scope notice in Name Shortening")
local target = assert(M.ResolveContextColorReferences({ "font.default.current" }, { scope = "nameplates" })[1])
local original = target.captureState()
local sharedR, sharedG, sharedB = db.general.fontColorCustomR, db.general.fontColorCustomG, db.general.fontColorCustomB
assert(not target.isEnabled(), "the inherited default font color is editable")
target.setRGB(.2, .4, .6)
assert(not db.nameplates or not db.nameplates.fontColorR, "a disabled nameplate color was stored")
scopeOptions.setOverride(true)
mw:RunTimers()
assert(target.isEnabled(), "the nameplate default color stayed locked")
target.setRGB(.2, .4, .6)
local tinted = mw.core.UF.Config.ResolveNameplateFont({}).textColor
assert(tinted.r == .2 and tinted.g == .4 and tinted.b == .6, "the picker did not change the nameplate runtime font color")
assert(db.general.fontColorCustomR == sharedR and db.general.fontColorCustomG == sharedG and db.general.fontColorCustomB == sharedB,
    "editing nameplate font color changed Shared")
target.restoreState(original)
assert(not db.nameplates.fontColorR, "cancel retained the scoped color")
assert(not rows["font.nameplate_size"] and not rows["font.nameplate_name_size"], "Fonts still builds nameplate size controls")
db.nameplates.fontSize, db.nameplates.nameFontSize = 19, 23
rows["font.family"].set("EXPRESSWAY")
mw:RunTimers()
local selectedFont = db.nameplates.fontKey
assert(selectedFont and db.nameplates.fontSize == 19 and db.nameplates.nameFontSize == 23,
    "font picker changed the stored nameplate sizes or failed to write the scoped family")
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
local foundCharacterNames
for _, row in ipairs(api.GetSearchRecords()) do
    local key = row.exactTarget and row.exactTarget.settingKey
    assert(key ~= "nameplates.fontSize" and key ~= "nameplates.nameFontSize", "removed Fonts size is still in search")
    if key == "general.characterNameParts" then
        foundCharacterNames = true
        local routed, shown, exact = (M.Search._RoutingAPI or api).OpenSearchTarget(row.key, row.label, row.label,
            row.anchor, row.route, row.exactTarget)
        assert(routed and shown and exact and M.GlobalPage.CurrentFontScope() == "shared", "character names search missed Shared")
    end
end
assert((foundCharacterNames == true) == (flavor == "Forever"), "wrong character-name search visibility")
print("nameplate font scope " .. flavor .. ": scoped family, saved size inheritance and search passed")

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
