-- Name formats are opt-in, share the runtime sink, and never inspect secret names.
local root, flavor = assert(arg[1]), assert(arg[2])
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
Secrets.Install()
local ns, text, output, scans = {}, {}, nil, 0
local env = setmetatable({ string = setmetatable({ find = function(...)
    scans = scans + 1
    return string.find(...)
end }, { __index = string }) }, { __index = _G })
local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Name.lua"
local chunk = assert(loadfile(path))
setfenv(chunk, env)
chunk("test", ns)
ns.UFModuleFactories.TextName(function() end, nil, function() return true end,
    function(_, value) output = value end, text, math.floor, issecretvalue, string.byte, string.sub, tonumber)
assert(text.ResolveNameFormat, "name format resolver missing")
assert(text.ResolveNameFormat(nil) == nil and text.ResolveNameFormat("LEGACY") == nil)
assert(text.ResolveNameFormat("unknown") == nil)
local frame = { nameText = {}, _msufTextRuntime = {} }
local function write(frame, name)
    local mode = frame._msufTextRuntime.nameFormat
    if mode then output = text.FormatName(frame, name, mode) else output = name end
end
local function Check(format, name, expected)
    frame._msufTextRuntime.nameFormat = text.ResolveNameFormat(format)
    write(frame, name)
    assert(output == expected, format .. " failed for " .. name .. ": " .. tostring(output))
end
Check("LEGACY", "World of Warcraft", "World of Warcraft")
Check("FULL", "World of Warcraft", "World of Warcraft")
Check("ABBREV", "World of Warcraft", "W. o. Warcraft")
Check("ABBREV", "Mapko", "Mapko")
Check("ABBREV", "Älterer Wächter", "Ä. Wächter")
Check("ABBREV", "Железный Страж", "Ж. Страж")
Check("ABBREV", "艾泽拉斯 守护者", "艾. 守护者")
Check("ABBREV", "  World\t of  Warcraft  ", "W. o. Warcraft")
Check("VERYSHORT", "ÄÖÜßName", "ÄÖÜß")
Check("SHORT", "1234567890abc", "1234567890")
Check("MEDIUM", "123456789012345678", "123456789012345")
Check("ABBREV_SHORT", "World of Warcraft", "W. o. Warc")
Check("ABBREV_VERYSHORT", "World of Warcraft", "W. o")
Check("ABBREV_MEDIUM", "Ancient Forest Guardian", "A. F. Guardian")
Check("ABBREV", "", "")
frame._msufTextRuntime.nameFormat = "ABBREV"
write(frame, "World of Warcraft")
local before = scans
local allocated = math.huge
for _ = 1, 2 do
    collectgarbage("collect")
    collectgarbage("stop")
    local kb = collectgarbage("count")
    for _ = 1, 10000 do write(frame, "World of Warcraft") end
    allocated = math.min(allocated, collectgarbage("count") - kb)
    collectgarbage("restart")
end
assert(scans == before, "unchanged names were rescanned")
assert(allocated < 1, "warm formatter allocated " .. allocated .. " KB")
local secret = Secrets.New("string")
local stop = Secrets.Watch(path, { strict = true })
write(frame, secret)
assert(issecretvalue(output), "secret name did not reach the sink")
local violations = stop()
assert(#violations == 0, table.concat(violations, "\n"))
Check("ABBREV", "Forest Guardian", "F. Guardian")

-- Use the real profile/compiler/menu graph, including scoped commands and history.
local World = dofile(root .. "/tools/tests/menu_core_world.lua")
local mw = World.Open(root, flavor, { beforeCore = World.InstallNativeUnitInputs })
local M, core = mw.M, mw.core
local db, config = M.EnsureDB(), core.UF.Config
local function Spec()
    config.Refresh()
    return config.GetSpec("target").text
end
db.general.nameFormat = nil
assert(Spec().nameFormat == nil, "old profiles enabled a format")
db.shortenNames, db.general.shortenNameMaxChars = true, 6
assert(Spec().nameShorten == true, "legacy shortening changed")
db.general.nameFormat = false
assert(Spec().nameFormat == nil and Spec().nameShorten == true, "false format changed legacy shortening")
db.general.nameFormat = "ABBREV"
assert(Spec().nameFormat == "ABBREV" and Spec().nameShorten == false, "format was clipped a second time")
db.target.fontOverride, db.target.nameFormat = true, "SHORT"
assert(Spec().nameFormat == "SHORT", "unit override ignored")
db.target.fontOverride = false
assert(Spec().nameFormat == "ABBREV", "disabled unit override did not inherit")
for _, kind in ipairs({ "party", "raid" }) do
    local conf = core.GF.GetConf(kind)
    conf.fontOverride, conf.nameFormat = false, "FULL"
    assert(core.GF.CompileSpec(kind).text.nameFormat == "ABBREV", "group did not inherit")
    conf.fontOverride, conf.nameFormat = true, "SHORT"
    core.GF.InvalidateCompiledSpecs(kind)
    assert(core.GF.CompileSpec(kind).text.nameFormat == "SHORT", "group override ignored")
end
db.general._fontScopeKey = "shared"
assert(mw:Select("opt_fonts"))
local entry = assert(M.cache.opt_fonts)
local section = assert(entry.sections.fonts_name_shortening)
local disclosure = assert(section._msuf2CollapsibleEntry)
if disclosure._msuf2EnsureContent then disclosure._msuf2EnsureContent() end
disclosure.SetOpenImmediate(true)
M.Refresh()
local control
for _, widget in ipairs(entry.searchWidgets) do
    local record = widget._msuf2RuntimeControlRecord
    if record and record.controlId:sub(-#"name.shortening.format") == "name.shortening.format" then control = widget end
end
assert(control, "name format control missing")
assert(section._msufNameFormatPreview, "name format preview missing")
local preview = section._msufNameFormatPreview
local rawName = flavor == "Forever" and "Alexandriana Brightwhisper" or "Alexandriana"
db.general.shortenNameMaxChars, db.general.shortenNameClipSide, db.general.shortenNameShowDots = 10, "RIGHT", false
local function Pick(mode, expected)
    control._msuf2CommandAction.set(mode)
    assert(preview.value:GetText() == expected, "preview did not immediately follow " .. mode)
    assert(preview.original:GetText():find(rawName, 1, true), "wrong client example")
end
Pick("FULL", rawName)
Pick("CUT", "Alexandria")
Pick("ABBREV", flavor == "Forever" and "A. Brightwhisper" or rawName)
Pick("ABBREV_CUT", flavor == "Forever" and "A. Brightw" or "Alexandria")
local chars, side, dots, hiddenToggle
for _, widget in ipairs(entry.searchWidgets) do
    local record = widget._msuf2RuntimeControlRecord
    local id = record and record.controlId or ""
    if id:match("name.shortening.max.length$") then chars = widget end
    if id:match("name.shortening.style$") then side = widget end
    if id:match("name.shortening.no.ellipsis$") then dots = widget end
    if id:match("name.shortening.enabled$") then hiddenToggle = widget end
end
Pick("FULL", rawName)
assert(chars._msuf2DesiredEnabled == false and side._msuf2DesiredEnabled == false and dots._msuf2DesiredEnabled == false,
    "full name left length controls enabled")
control._msuf2OnValueChanged("CUT")
assert(chars._msuf2DesiredEnabled == true and side._msuf2DesiredEnabled == true and dots._msuf2DesiredEnabled == true,
    "native dropdown click did not immediately enable length controls")
control._msuf2OnValueChanged("ABBREV")
assert(chars._msuf2DesiredEnabled == false and side._msuf2DesiredEnabled == false and dots._msuf2DesiredEnabled == false,
    "word abbreviation left length controls enabled")
assert(hiddenToggle and hiddenToggle:IsShown() == false, "duplicate master toggle is visible")
assert(not hiddenToggle._msuf2Label:IsShown() and not hiddenToggle._msuf2LabelHit:IsShown(),
    "hidden compatibility toggle left visible text or a clickable sibling")
Pick("CUT", "Alexandria")
chars._msuf2CommandAction.set(7)
assert(preview.value:GetText() == "Alexand", "slider did not update the name format")
side._msuf2CommandAction.set("LEFT")
assert(preview.value:GetText() == (flavor == "Forever" and "whisper" or "ndriana"), "preview ignored clipping side")
dots._msuf2CommandAction.set(false)
assert(preview.value:GetText() == (flavor == "Forever" and "..whisper" or "..ndriana"), "preview ignored ellipsis")
if flavor == "Forever" then
    Pick("FULL", rawName)
    db.general.characterNameParts = "FIRST"
    M.Refresh()
    assert(preview.value:GetText() == "Alexandriana", "Forever first-name preview mismatch")
    db.general.characterNameParts = "SURNAME"
    M.Refresh()
    assert(preview.value:GetText() == "Brightwhisper", "Forever surname preview mismatch")
    db.general.characterNameParts = nil
end
db.general.nameFormat, db.general.shortenNameMaxChars = "SHORT", 6
db.general.shortenNameClipSide, db.general.shortenNameShowDots = "LEFT", true
M.Refresh()
assert(preview.value:GetText() == "Alexandria", "old preset no longer shows its saved length")
M.SyncExternalHistoryState()
chars._msuf2CommandAction.set(8)
assert(db.general.nameFormat == "CUT" and db.general.shortenNameClipSide == "RIGHT"
    and db.general.shortenNameShowDots == false, "editing an old preset lost its effective style")
assert(preview.value:GetText() == "Alexandr", "old preset did not convert to the slider length")
assert(M.Undo() and db.general.nameFormat == "SHORT", "old preset was not restored by undo")
db.general.nameFormat = "ABBREV"
M.Refresh()
M.SyncExternalHistoryState()
control._msuf2CommandAction.set("MEDIUM")
assert(db.general.nameFormat == "MEDIUM", "menu did not save the format")
assert(M.Undo(), "format change was not undoable")
assert(db.general.nameFormat == "ABBREV", "undo lost the old format")
assert(M.Redo() and db.general.nameFormat == "MEDIUM", "redo lost the format")
local C = dofile(root .. "/tools/profile_corpus_golden.lua")
local H = dofile(root .. "/tools/tests/profile_state_harness.lua")
local stored = C.Copy(db)
stored.general.nameFormat, stored.target.nameFormat, stored.gf_raid.nameFormat = "ABBREV", "SHORT", "MEDIUM"
core.DefaultsSchema.Persist(stored)
stored = assert(loadstring("return " .. H.Literal(stored)))()
core.DefaultsSchema.RestorePersistence(stored)
assert(stored.general.nameFormat == "ABBREV" and stored.target.nameFormat == "SHORT"
    and stored.gf_raid.nameFormat == "MEDIUM", "sparse persistence lost name formats")
db.general.nameFormat, db.player.fontOverride = "VERYSHORT", false
db.player.showRaidGroupInName = true
local sample = mw.env.UIParent:CreateFontString(nil, "OVERLAY")
M.UnitNameSample.Paint(sample, "player", "Mapko", true)
assert(sample:GetText() == "Mapk (2)", "Text-page sample ignored the format or clipped its group suffix")

local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local currentName = "World of Warcraft"
local h = Harness.New(root, flavor, { beforeBoot = function(world)
    world.env.UnitName = function() return currentName end
end })
local GF = h.GF
GF.EnsureDB()
h.env.MSUF_DB.general.nameFormat = "ABBREV"
local conf = GF.GetConf("raid")
conf.enabled, conf.fontOverride = true, false
GF.InvalidateCompiledSpecs("raid")
GF.RefreshHeaderLayout()
h:SetRaid(2)
h:Event("GROUP_ROSTER_UPDATE")
h:RunTimers()
local live = assert(h:Children(GF.headers.raid)[1])
assert(live.nameText:GetText() == "W. o. Warcraft", "live name bypassed formatting")
h:EnterCombat()
currentName = "Ancient Forest Guardian"
h:Event("UNIT_NAME_UPDATE", live.MSUFUnitKey)
h:RunTimers()
assert(live.nameText:GetText() == "A. F. Guardian", "combat name update kept a stale cached name")
h:LeaveCombat()
h.env.MSUF_DB.general.nameFormat = "VERYSHORT"
GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT)
GF.RefreshVisuals("raid", GF.DIRTY_FONT)
assert(live.nameText:GetText() == "Anci", "font refresh did not repaint the new format")
h.core.UFText.PaintSampleName(live, "Älterer Wächter")
assert(live.nameText:GetText() == "Älte", "scene sample bypassed the runtime format")
live._msufPreviewNameText = nil
conf.fontOverride, conf.nameFormat, conf._msufLegacyNameAnchorToFrame = true, "LEGACY", true
conf.nameShortenEnabled, conf.nameMaxChars, conf.nameClipSide, conf.nameNoEllipsis = true, 4, "RIGHT", false
GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT)
GF.RefreshVisuals("raid", GF.DIRTY_FONT)
assert(live.nameText:GetText() == "Anci..", "returning to legacy changed saved truncation")
conf.nameFormat = "FULL"
GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT)
GF.RefreshVisuals("raid", GF.DIRTY_FONT)
assert(live.nameText:GetText() == currentName, "full format retained legacy truncation")
conf.fontOverride = false
local general = h.env.MSUF_DB.general
general.nameFormat, general.shortenNames = "CUT", false
general.shortenNameMaxChars, general.shortenNameClipSide, general.shortenNameShowDots = 7, "LEFT", false
GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT)
GF.RefreshVisuals("raid", GF.DIRTY_FONT)
assert(live.nameText:GetText() == "uardian", "shared group cut ignored the slider or side while legacy shortening was off")
general.shortenNameShowDots = true
GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT)
GF.RefreshVisuals("raid", GF.DIRTY_FONT)
assert(live.nameText:GetText() == "..uardian", "shared group cut ignored ellipsis")
local text = h.core.UFText
local inlineFrame = h.env.CreateFrame("Frame", nil, h.env.UIParent)
inlineFrame.nameText = inlineFrame:CreateFontString(nil, "OVERLAY")
inlineFrame.totInlineSep = inlineFrame:CreateFontString(nil, "OVERLAY")
inlineFrame.totInlineText = inlineFrame:CreateFontString(nil, "OVERLAY")
inlineFrame.MSUFSpec = { key = "target", showName = true, textColor = { r = 1, g = 1, b = 1, a = 1 } }
text.CompileTextRuntime(inlineFrame, inlineFrame.MSUFSpec, { nameAnchor = "CENTER", inlineToT = {
    enabled = true, unit = "targettarget", separator = ">", nameFormat = "CUT", nameShortenMax = 7,
    nameShortenDots = true, nameShortenSide = "RIGHT" } })
text.PaintSampleInline(inlineFrame, "Ancient Guardian")
assert(inlineFrame.totInlineText:GetText() == "Ancient..", "centered inline name lost format ellipsis")
assert(#h.violations == 0, "name formatting caused a protected write")
local groupMenu = World.Open(root, flavor, { beforeCore = World.InstallNativeUnitInputs })
local gm, groupDB = groupMenu.M, groupMenu.M.EnsureDB()
groupDB.general._fontScopeKey, groupDB.general.nameFormat, groupDB.shortenNames = "party", nil, true
local groupConf = groupMenu.core.GF.GetConf("party")
groupConf.fontOverride, groupConf.nameShortenEnabled, groupConf.nameMaxChars, groupConf.nameFormat = true, false, 0, nil
assert(groupMenu:Select("opt_fonts"))
local groupEntry = gm.cache.opt_fonts
local groupSection = groupEntry.sections.fonts_name_shortening
local groupDisclosure = groupSection._msuf2CollapsibleEntry
if groupDisclosure._msuf2EnsureContent then groupDisclosure._msuf2EnsureContent() end
groupDisclosure.SetOpenImmediate(true)
gm.Refresh()
local groupFormat, groupLength
for _, widget in ipairs(groupEntry.searchWidgets) do
    local record = widget._msuf2RuntimeControlRecord
    local id = record and record.controlId or ""
    if id:match("name.shortening.format$") then groupFormat = widget end
    if id:match("name.shortening.max.length$") then groupLength = widget end
end
assert(groupConf.nameMaxChars == 0, "opening the old group profile wrote its length")
assert(groupLength._msuf2DesiredEnabled == false and groupLength._msuf2DisabledReason(groupLength),
    "inherited group false did not explain disabled length controls")
groupFormat._msuf2OnValueChanged("CUT")
assert(groupConf.nameFormat == "CUT" and groupConf.nameMaxChars == 6,
    "zero legacy group limit was not seeded from the effective displayed limit")
assert(groupLength._msuf2DesiredEnabled == true, "group limit did not activate on native format pick")
print("unit_name_format_smoke: PASS " .. flavor .. " (UTF-8, secrets, cache, scopes, legacy, menu/history)")
