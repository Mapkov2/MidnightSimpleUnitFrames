-- preview_status_text_locale_smoke.lua <repoRoot> [flavor ...]
--
-- The live status text keeps DEAD, GHOST, OFFLINE, AFK and DND as the state
-- tokens the health element compares and paints MSUF.Translate(token) on the
-- font string. The menu previews show the same words:
--   * the unit preview's status text icons paint through
--     PreviewStatus.StatusTokenText (it used to paint the English token);
--   * the group preview's status handles are Theme font strings, whose SetText
--     translates already, so their words come out translated as they are.
-- Boots the real core and Options graph on a German client, shows every status
-- text indicator in both previews and compares the painted words with
-- MSUF.Translate. Red on the old unit preview line: it painted "DEAD", the
-- German pack says "TOT".
-- Plain Lua 5.1, repo root as arg 1; optional flavors after it.

local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()

local function Check(condition, message)
    if not condition then error("preview_status_text_locale_smoke: " .. message, 2) end
end

-- spec id -> state token and the DB switch that shows it.
local UNIT_TEXTS = {
    { id = "statusText", token = "DEAD", show = "statusDeadTextEnabled" },
    { id = "statusGhostText", token = "GHOST", show = "statusGhostTextEnabled" },
    { id = "statusAFKText", token = "AFK", show = "statusAFKTextEnabled" },
    { id = "statusDNDText", token = "DND", show = "statusDNDTextEnabled" },
}
local GROUP_TEXTS = {
    statusText = "DEAD", statusGhostText = "GHOST", statusAFKText = "AFK", statusDNDText = "DND",
}

local flavors = {}
for i = 2, #arg do flavors[#flavors + 1] = arg[i] end
if #flavors == 0 then flavors = { "Mainline", "Vanilla" } end

for _, flavor in ipairs(flavors) do
    local mw = MenuWorld.Open(root, flavor, { locale = "deDE", open = false })
    local core, env, M, widgets = mw.core, mw.env, mw.M, mw.world.widgets
    core.FinalizeLocale()
    Check(core.LOCALE == "deDE", flavor .. ": the German pack was not selected")
    Check(core.Translate("DEAD") == "TOT", flavor .. ": the German pack lost its DEAD translation")

    -- Unit preview: every status text indicator on, all of them shown at once.
    local db = env.MSUF_DB
    for _, row in ipairs(UNIT_TEXTS) do
        db.target[row.show] = true
        db.general[row.show] = true
    end
    db.general.statusIndicators = db.general.statusIndicators or {}
    for _, field in ipairs({ "showDead", "showGhost", "showAFK", "showDND" }) do
        db.general.statusIndicators[field] = true
    end
    assert(M.Open("uf_target") ~= false, "the target page did not open")
    widgets:RunTimers()
    local Preview = mw.world.options.UFPreview or core.UFPreview
    Check(type(Preview) == "table" and type(Preview.SetStatusPreviewMode) == "function",
        flavor .. ": the unit preview API moved")
    Preview.SetStatusPreviewMode("all")
    widgets:RunTimers()
    local box = Preview.active
    Check(box and box.mock and box.mock.icons, flavor .. ": no active unit preview")
    for _, row in ipairs(UNIT_TEXTS) do
        local icon = box.mock.icons[row.id]
        Check(icon and icon.txt, flavor .. ": the unit preview has no " .. row.id .. " icon")
        Check(icon:IsShown(), flavor .. ": the unit preview hides " .. row.id .. " with its switch on")
        local painted = icon.txt:GetText()
        Check(painted == core.Translate(row.token), flavor .. ": the unit preview paints " .. row.id .. " as '"
            .. tostring(painted) .. "', the live text paints '" .. tostring(core.Translate(row.token)) .. "'")
    end
    Check(box.mock.icons.statusText.txt:GetText() == "TOT", flavor .. ": the unit preview Dead text is not German")

    -- Group preview: the status handles paint through the Theme's translating
    -- SetText, so every handle shows the translated word.
    M.gfScope = "party"
    assert(M.Open("gf_indicators") ~= false, "the group indicators page did not open")
    widgets:RunTimers()
    local seen, deadText = 0, nil
    for i = 1, #widgets.frames do
        local frame = widgets.frames[i]
        local spec = rawget(frame, "_statusSpec")
        local token = spec and GROUP_TEXTS[spec.value]
        local text = token and rawget(frame, "_statusText")
        if text and text:IsShown() then
            seen = seen + 1
            if spec.value == "statusText" then deadText = text:GetText() end
            Check(text:GetText() == core.Translate(token), flavor .. ": the group preview paints " .. spec.value
                .. " as '" .. tostring(text:GetText()) .. "'")
        end
    end
    Check(seen >= 1, flavor .. ": the group preview showed no status text handle")
    Check(deadText == "TOT", flavor .. ": the group preview Dead text is '" .. tostring(deadText) .. "', not German")
    print("preview_status_text_locale_smoke: " .. flavor .. " ok (" .. seen .. " group status texts)")
end
print("preview_status_text_locale_smoke: ok")
