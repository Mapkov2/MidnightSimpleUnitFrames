-- Real profile editor selection, persistence and close/reopen; optional original-source overlay.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local observe = arg[4] == "--observe"
local Open = assert(loadfile(root .. "/tools/tests/menu_l4_world.lua"))()
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true, locale = arg[5] or "enUS",
    beforeCore = function(world)
        local MW = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
        MW.InstallNativeUnitInputs(world)
    end, beforeOptions = function(world)
        if arg[5] == "deDE" then
            assert(world.core.FinalizeLocale() == "deDE", "German locale did not finalize")
            assert(world.core.Translate("Player") == "Spieler", "German literal-label fixture stayed English")
        end
        if arg[6] ~= "specs" then return end
        -- Native specialization inputs, supplied before the real page owner binds them.
        world.core.Specialization.GetNumSpecializations = function() return 2 end
        world.core.Specialization.GetSpecializationInfo = function(index)
            return index == 1 and 71 or 72, index == 1 and "Arms" or "Fury"
        end
    end }, arg[3] ~= "-" and arg[3] or nil)
local M, V, env = mw.M, mw.core.ProfileVariants, mw.env
assert(V.Replace(M.EnsureDB(), { version = 1, entries = {
    { name = "A", conditions = { context = "party", dark = true, specs = { ["71"] = true } }, hotkey = 1, patch = {
        { path = { "player", "width" }, value = 251 },
    } },
    { name = "B", enabled = false, conditions = { context = "raid", dark = false, specs = { ["72"] = true } }, hotkey = 2, patch = {
        { path = { "target", "width" }, value = 252 }, { path = { "player", "height" }, value = 45 },
    } },
} }))
local function Settle() mw:RunTimers() M.Theme.StopAllMenuAnimations() end
assert(mw:Select("profiles")) Settle()
local original = M.cache.profiles
local function Control(path)
    local suffix = "." .. path
    for _, widget in ipairs(M.cache.profiles.searchWidgets) do
        local record = widget._msuf2RuntimeControlRecord
        if record and widget:IsShown() and (record.controlId:sub(-#suffix) == suffix
            or record.controlId:find(suffix .. ".s", 1, true)) then return widget end
    end
    error("missing profile control " .. path)
end
local function Choose(name)
    local drop = Control("variant.select")
    drop._msuf2OnValueChanged(name)
    Settle()
    local a = name == "A"
    assert(Control("variant.condition.context"):GetValue() == (a and "party" or "raid"), "stale context: " .. tostring(Control("variant.condition.context"):GetValue()) .. " selected=" .. tostring(Control("variant.select"):GetValue()) .. " wanted=" .. name)
    assert(Control("variant.condition.dark"):GetValue() == (a and "on" or "off"), "stale dark condition")
    assert(Control("variant.condition.hotkey"):GetValue() == (a and 1 or 2), "stale activation")
    assert(Control("variant.enabled"):GetChecked() == a, "stale enabled value")
    if arg[6] == "specs" then
        assert(Control("variant.spec.1"):GetChecked() == a, "stale first specialization")
        assert(Control("variant.spec.2"):GetChecked() == not a, "stale second specialization")
    end
    local fields = Control("variant.field.select").values
    assert(#fields == (a and 2 or 3), "stale overridden settings")
end
Choose("B") Choose("A")
local frames, refreshers = mw:Frames(), #M.cache.profiles.refreshers
for i = 1, 8 do
    Choose(i % 2 == 1 and "B" or "A")
    if i % 2 == 0 then
        M.HideSlashMenuAndMinibar(mw.win) Settle()
        assert(M.Open("profiles") ~= false) Settle()
    end
end
local delta = mw:Frames() - frames
print("PROFILE_REUSE " .. flavor .. " warm_frames=" .. frames .. " new_frames=" .. delta)
assert(observe or delta == 0, "variant selection/close/reopen created " .. delta .. " new frames after warm-up")
assert(observe or M.cache.profiles == original, "variant selection replaced the profiles page")
assert(observe or #original.refreshers == refreshers, "variant selection accumulated refreshers")
-- Writes after rebinding must affect the selected draft, and Save uses that draft.
Control("variant.condition.context")._msuf2OnValueChanged("solo") Settle()
Control("variant.conditions.save"):Click() Settle()
assert(V.Find(M.EnsureDB(), "A").conditions.context == "solo", "save wrote the old variant")
assert(V.Find(M.EnsureDB(), "B").conditions.context == "raid", "save changed another variant")


-- Search still describes every named entry, independently of the row currently pooled.
local function Rows(stage)
    local rows = M.ProfileSearch.Collect()
    local texts = {}
    for _, row in ipairs(rows) do
        texts[#texts + 1] = table.concat({ row.pageKey, row.sectionId, row.controlId:gsub("%.s%d+$", ".sTOKEN"),
            row.label, row.kind, row.prepareKind or "", row.help or "",
            type(row.keywords) == "table" and table.concat(row.keywords, "|") or row.keywords }, "\t")
    end
    table.sort(texts)
    local hash = 0
    for _, text in ipairs(texts) do
        for i = 1, #text do hash = (hash * 33 + text:byte(i)) % 2147483647 end
    end
    print("PROFILE_ROWS " .. flavor .. " " .. stage .. " " .. #rows .. " " .. hash)
    -- Original page/provider receipts, including literal names, labels, kinds and paths.
    local expected = { variants = { 28, 1012884891 }, recording = { 28, 194511301 },
        sync = { 64, 319858610 }, empty = { 8, 1179886473 } }
    if (not arg[5] or arg[5] == "enUS") and arg[6] ~= "specs" then
        local pin = assert(expected[stage])
        assert(#rows == pin[1] and hash == pin[2], "profile search rows changed at " .. stage)
    end
    return rows
end
local rows = Rows("variants")
local target
for _, row in ipairs(rows) do
    if row.help == "B" and row.controlId:find("variant.condition.context", 1, true) then target = row end
end
assert(target, "missing off-page B search row")
assert(mw:Select("home"))
assert(M.ProfileSearch.Prepare(target), "could not prepare B search target off page")
assert(mw:Select("profiles")) Settle()
assert(Control("variant.condition.context"):GetValue() == "raid", "off-page search target kept A")
assert(Control("variant.condition.context")._msuf2SearchMeta.searchPrepareValue == target.prepareValue,
    "pooled search control kept A's identity")
local function Recording()
    Control("variant.values.edit"):Click() Settle()
    assert(V.IsRecording(), "could not begin recording")
    Rows("recording")
    local noteText = M.Format("Editing %s: use the normal settings pages or Edit Mode, then return here to save or cancel.", V.RecordingName())
    local note
    for _, widget in ipairs(M.cache.profiles.searchWidgets) do
        if widget.GetText and widget:GetText() == noteText and widget:IsShown() then note = widget break end
    end
    assert(note and not note._msuf2SearchRegistryId, "recording note kept stale idle search text")
    assert(Control("variant.values.save")._msuf2Label:IsShown(), "save label stayed hidden")
    Control("variant.values.cancel"):Click() Settle()
    assert(not V.IsRecording(), "cancel did not end recording")
    assert(Control("variant.values.edit")._msuf2Label:IsShown(), "edit label stayed hidden")
end
Recording()
local warm = mw:Frames()
Recording()
assert(observe or mw:Frames() == warm, "recording mode did not reuse rows")
-- A saved schema replacement while hidden must be read on reopen without a page rebuild.
M.HideSlashMenuAndMinibar(mw.win) Settle()
local copy = assert(V.Validate(M.EnsureDB().profileVariants))
copy.entries[2].conditions.context = "world"
M.EnsureDB().profileVariants = copy
assert(M.Open("profiles") ~= false) Settle()
assert(observe or Control("variant.condition.context"):GetValue() == "world", "reopen kept replaced schema")
-- Sync editors share the pool, including literal profile names and varying row counts.
local S = mw.core.ProfileSync
local account = env.MSUF_GlobalDB
account.profiles.Player = mw.core.ProfileFields.Copy(M.EnsureDB())
assert(S.Replace({
    { name = "One", members = { Player = true }, modules = { unitframes = true }, exclude = {} },
    { name = "Two", members = { Default = true }, modules = { colors = true }, exclude = {} },
}))
M.ProfileVariantPage.Refresh(M.cache.profiles.context) Settle()
Rows("sync")
local function Sync(name)
    Control("sync.group.select")._msuf2OnValueChanged(name) Settle()
    assert(Control("sync.module.unitframes"):GetChecked() == (name == "One"), "sync module did not rebind")
    local names = mw.core.Require("MSUF_GetAllProfiles", "profile pool test")()
    for i, profile in ipairs(names) do
        if profile == "Player" then
            local member = Control("sync.member." .. i)
            assert(member._msuf2Label:GetText() == "Player", "pooled literal name was translated")
            assert(member:GetChecked() == (name == "One"), "sync member did not rebind")
        end
    end
end
Sync("Two") Sync("One")
warm = mw:Frames()
Sync("Two") Sync("One")
assert(observe or mw:Frames() == warm, "sync selection created frames")
-- Removed controls must hide their sibling click proxies, too.
local variantToggle, memberToggle = Control("variant.enabled"), Control("sync.member.1")
for _ = 1, 2 do Control("variant.delete"):Click() Settle() end
for _ = 1, 2 do Control("sync.group.delete"):Click() Settle() end
Rows("empty")
assert(observe or not variantToggle._msuf2LabelHit:IsShown(), "removed variant proxy stayed clickable")
assert(observe or not memberToggle._msuf2LabelHit:IsShown(), "removed sync proxy stayed clickable")
local variantBody = M.cache.profiles.sections.profiles_variants
assert(variantBody._msuf2CollapsibleEntry.contentHeight == 250, "empty editor height stale")
Control("variant.name"):SetText("Again")
Control("variant.create"):Click() Settle()
assert(V.Find(M.EnsureDB(), "Again"), "pooled create used a stale input")
assert(Control("variant.enabled")._msuf2LabelHit:IsShown(), "reused toggle proxy stayed hidden")
-- Bad saved schemas keep their diagnostic and block writes; returning to a valid schema reuses rows.
local valid = M.EnsureDB().profileVariants
M.EnsureDB().profileVariants = { version = 99, entries = {} }
M.ProfileVariantPage.Refresh(M.cache.profiles.context) Settle()
local errorText = M.Format("The saved profile variants cannot be read (%s). They are kept unchanged, and editing them here is blocked.",
    M.Tr("invalid profile variants"))
local function ErrorRow()
    for _, widget in ipairs(M.cache.profiles.searchWidgets) do
        if widget._msuf2SearchText == errorText and widget:IsShown() then return widget end
    end
    error("saved schema diagnostic is missing")
end
assert(ErrorRow()._msuf2SearchRegistryId, "schema diagnostic lost search registration")
Control("variant.name"):SetText("Blocked")
Control("variant.create"):Click() Settle()
assert(M.EnsureDB().profileVariants.version == 99, "invalid schema was overwritten")
M.EnsureDB().profileVariants = valid
M.ProfileVariantPage.Refresh(M.cache.profiles.context) Settle()
local framesBeforeError = mw:Frames()
M.EnsureDB().profileVariants = { version = 99, entries = {} }
M.ProfileVariantPage.Refresh(M.cache.profiles.context) Settle()
assert(ErrorRow()._msuf2SearchRegistryId, "reused diagnostic lost search registration")
assert(observe or mw:Frames() == framesBeforeError, "reused diagnostic created a frame")
M.EnsureDB().profileVariants = valid
M.ProfileVariantPage.Refresh(M.cache.profiles.context) Settle()
assert(observe or M.cache.profiles == original, "editor state cycle rebuilt the profiles page")
print("PASS profile variant page reuse and editor lifecycle " .. flavor .. " " .. (arg[5] or "enUS") .. " specs=" .. #M.GetProfileSpecializations())
