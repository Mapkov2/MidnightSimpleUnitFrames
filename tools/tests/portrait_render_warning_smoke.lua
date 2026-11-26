-- Exercise actual mouse and keyboard selections in the unit and Party Render dropdowns.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, flavor, {
    locale = arg[3], tocMetadata = true, beforeCore = MenuWorld.InstallNativeUnitInputs,
})
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
local function Pick(dropdown, value, keyboard)
    assert(dropdown:IsEnabled(), "could not use the Render dropdown")
    dropdown:Click()
    for _, row in ipairs(mw.world.widgets.frames) do
        if row:IsShown() and row._msuf2Owner == dropdown and row._msuf2Value == value then
            assert(not row._msuf2DropdownDisabled, "Render option was disabled")
            if keyboard then
                local list = row:GetParent():GetParent():GetParent()
                assert(list._msuf2KeyboardIndex == row._msuf2Index, "the current render option was not focused")
                list:GetScript("OnKeyDown")(list, "ENTER")
            else
                row:Click()
            end
            M.Widgets.CloseDropdown({ immediate = true })
            mw:RunTimers()
            return row
        end
    end
    error("Render option not found: " .. value)
end

local function Choose3D(dropdown, conf, fallsBack, keyboard)
    local row = Pick(dropdown, "3D", keyboard)
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
    return row
end

local target = OpenRender("uf_target", "target")
target:SetValue("3D")
assert(not prompt and db.target.portraitRender == "2D", "refreshing the dropdown showed a warning or changed the setting")
target:SetValue("2D")
Choose3D(target, db.target, retail)
Choose3D(target, db.target, retail)
local selectedRow = Choose3D(target, db.target, retail, true)
selectedRow:GetScript("OnClick")(selectedRow)
assert(not prompt, "a closed dropdown row showed the warning")
Pick(target, "CLASS")
assert(not prompt and db.target.portraitRender == "CLASS", "switching to Class showed a warning")
Pick(target, "2D")
assert(not prompt and db.target.portraitRender == "2D", "switching to 2D showed a warning")

Choose3D(OpenRender("uf_player", "player"), db.player, false)
Choose3D(OpenRender("uf_pet", "pet"), db.pet, false)

mw.core.GF.EnsureDB()
db.gf_party.enabled = true
db.gf_party.portraitModelInstanceCombat = false
local party = OpenRender("gf_layout", "gf_party")
Choose3D(party, db.gf_party, retail)
Choose3D(party, db.gf_party, retail)
if retail then
    db.gf_party.portraitModelInstanceCombat = true
    Pick(party, "2D")
    Choose3D(party, db.gf_party, false)
end

print("portrait_render_warning_smoke: ok (" .. flavor .. ")")
