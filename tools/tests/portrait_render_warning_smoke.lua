-- Exercise the actual unit and Party Render dropdown bindings.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, { locale = arg[3] })
local M, db = mw.M, mw.env.MSUF_DB
local retail = mw.core.Client.IsRetail == true

local prompt
local ShowPrompt = M.ShowPrompt
M.ShowPrompt = function(key, spec)
    prompt = ShowPrompt(key, spec)
    return prompt
end

local function OpenRender(page, scope)
    local conf = assert(db[scope])
    conf.portraitMode, conf.portraitRender = "LEFT", "2D"
    assert(mw:Select(page))
    local section = assert(M.cache[page].sections.portrait)
    section._msuf2CollapsibleEntry.SetOpenImmediate(true)
    assert(M.Widgets.EnsureSectionContent(section))
    mw:RunTimers()
    assert(not prompt, "opening the portrait options showed a warning")
    for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
        if record.pageKey == page and record.settingKey == scope .. ".portraitRender" then
            return assert(M.RuntimeControlCatalog.Get(record.controlId).widget)
        end
    end
    error("Render dropdown not found for " .. scope)
end

local performance = M.Tr("3D portraits can severely reduce performance.")
local fallback = M.Tr("During instanced combat, 3D portraits can render unreliably. MSUF automatically uses 2D portraits there.")
local function Choose3D(dropdown, conf, fallsBack)
    dropdown._msuf2OnValueChanged("3D")
    assert(conf.portraitRender == "3D", "showing the warning did not apply the selection")
    assert(prompt and prompt:IsShown(), "selecting 3D did not show a warning")
    local spec = prompt._msufPromptSpec
    assert(spec.single and spec.showAlert, "warning needs one acknowledgement button")
    assert(spec.text == (fallsBack and performance .. "\n\n" .. fallback or performance),
        "warning does not match the frame's fallback behavior")
    local okay = prompt._msufPromptButtons[1]
    okay:GetScript("OnClick")(okay)
    assert(not prompt:IsShown() and conf.portraitRender == "3D", "acknowledging the warning changed the selection")
    prompt = nil
end

local target = OpenRender("uf_target", "target")
Choose3D(target, db.target, retail)
target._msuf2OnValueChanged("3D")
assert(not prompt, "reselecting the current render showed a warning")
target._msuf2OnValueChanged("CLASS")
assert(not prompt and db.target.portraitRender == "CLASS", "switching to Class showed a warning")
target._msuf2OnValueChanged("2D")
assert(not prompt and db.target.portraitRender == "2D", "switching to 2D showed a warning")

Choose3D(OpenRender("uf_player", "player"), db.player, false)
Choose3D(OpenRender("uf_pet", "pet"), db.pet, false)

mw.core.GF.EnsureDB()
db.gf_party.portraitModelInstanceCombat = false
local party = OpenRender("gf_layout", "gf_party")
Choose3D(party, db.gf_party, retail)
if retail then
    db.gf_party.portraitModelInstanceCombat = true
    party._msuf2OnValueChanged("2D")
    Choose3D(party, db.gf_party, false)
end

print("portrait_render_warning_smoke: ok (" .. flavor .. ")")
