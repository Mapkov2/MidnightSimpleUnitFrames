-- preview_sample_effect_layers_smoke.lua <repoRoot> [flavor]
--
-- The Dispel Overlay and Dispel Symbol preview layers paint a stand-in effect the frame does not carry right now.
-- Pins, on the Options unit preview and on the group preview (both share the layer rail helpers), that
--   * both layers start switched off while their settings stay on, and the chips stay available to switch them on;
--   * a hint under the preview shows exactly while one of them paints, names it, and a click hides it;
--   * the chip tooltip says the effect is a sample;
--   * the matching settings section switches the layer on while it is open, and off again when it closes, unless
--     the user clicked the chip in between.
local root = assert(arg and arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local World = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local w = World.Open(root, flavor, { page = "home", clientScriptBindings = true })
local env, core, M = w.env, w.core, w.M
-- The persisted accordion states the settings sections write; the previews read them.
local accordion = M.GetPersistentMenuStateTable("accordionState")
M.accordionState = accordion

local function Check(condition, message)
    if not condition then error("preview_sample_effect_layers_smoke " .. flavor .. ": " .. message, 2) end
end

local tips = {}
env.GameTooltip.SetOwner = function() tips[#tips + 1] = "owner" end
env.GameTooltip.SetText = function(_, text) tips[#tips + 1] = tostring(text) end
env.GameTooltip.AddLine = function(_, text) tips[#tips + 1] = tostring(text) end
env.GameTooltip.Show = function() end
env.GameTooltip.Hide = function() end
local function Tooltip(chip)
    for i = #tips, 1, -1 do tips[i] = nil end
    World.FireScript(chip, "OnEnter")
    local joined = table.concat(tips, "\n")
    World.FireScript(chip, "OnLeave")
    return joined
end

local SAMPLE_TIP = "Shows a sample effect your frame does not currently have."
-- The hint button is built the first time a sample effect paints, so a preview without one carries no extra frame.
local function HintText(owner)
    local hint = owner._msuf2SampleEffectHint
    return hint, hint ~= nil and hint:IsShown(), hint and hint._text:GetText()
end

---------------------------------------------------------------------------
-- Unit preview
---------------------------------------------------------------------------
do
    local Preview, A3 = core.UFPreview, core.MSUF_Auras3
    local selected = "player"
    local panel = env.CreateFrame("Frame", nil, env.UIParent)
    panel._msufGetCurrentKey = function() return selected end
    local adb = A3.EnsureDB()
    adb.enabled, adb.showPlayer = true, true
    for _, key in ipairs({ "unitDispelOverlayEnabled", "unitDispelSymbolEnabled" }) do
        env.MSUF_DB.general[key] = true
        env.MSUF_DB.player[key] = true
    end
    local function NewBox()
        local box = Preview._BuildPreview(env.UIParent, panel, 900, 400)
        World.FireVisibilityScripts(box)
        box:Show()
        box.canvas:SetSize(600, 260)
        return box
    end
    local function Refresh(box)
        A3.InvalidateUnitRuntimeConfig(selected)
        Preview.Refresh(box, "SETTINGS")
        return box.mock._body
    end
    local function Chip(box, key)
        for _, chip in ipairs(box.layerButtons) do if chip.key == key then return chip end end
        error("no " .. key .. " chip")
    end
    local function Click(chip) World.FireScript(chip, "OnClick", "LeftButton") end

    local box = NewBox()
    Check(box.layerVisibility.dispelOverlay == false and box.layerVisibility.dispelSymbol == false,
        "unit preview sample-effect layers do not start switched off")
    Check(box.layerVisibility.nameText == true and box.layerVisibility.buff == true and box.layerVisibility.status == true,
        "unit preview configured layers no longer start switched on")
    local body = Refresh(box)
    Check(box.layerAvailable.dispelOverlay == true and box.layerAvailable.dispelSymbol == true,
        "an off sample layer lost its availability (its chip would open settings instead of switching it on)")
    Check(body._msufSceneDispelOverlay and not body._msufSceneDispelOverlay:IsShown(), "the dispel overlay painted while its layer is off")
    Check(not (body._msufSceneDispelSymbol and body._msufSceneDispelSymbol:IsShown()), "the dispel symbols painted while their layer is off")
    local _, shown = HintText(box)
    Check(not shown and box._msuf2SampleEffectHint == nil, "the hint existed while no sample effect paints")
    Refresh(box)
    Check(box.layerAvailable.dispelOverlay == true, "a second refresh made the off overlay chip unavailable")

    Click(Chip(box, "dispelOverlay"))
    body = Refresh(box)
    Check(box.layerVisibility.dispelOverlay == true and body._msufSceneDispelOverlay:IsShown(), "the overlay chip did not switch the overlay on")
    local _, hintShown, text = HintText(box)
    Check(hintShown and text == "Sample effects shown: Dispel Overlay - not your live state",
        "hint text after the overlay chip: " .. tostring(text))
    Check(Tooltip(Chip(box, "dispelOverlay")):find(SAMPLE_TIP, 1, true), "the overlay chip tooltip does not say it is a sample")
    Check(not Tooltip(Chip(box, "nameText")):find(SAMPLE_TIP, 1, true), "a configured layer chip claims to be a sample")

    Click(Chip(box, "dispelSymbol"))
    Refresh(box)
    _, hintShown, text = HintText(box)
    Check(hintShown and text == "Sample effects shown: Dispel Overlay, Dispel Symbol - not your live state",
        "hint text with both layers: " .. tostring(text))

    World.FireScript(box._msuf2SampleEffectHint, "OnClick", "LeftButton")
    Check(box.layerVisibility.dispelOverlay == false and box.layerVisibility.dispelSymbol == false, "the hint did not hide the sample layers")
    Check(box.layerVisibility.nameText == true, "the hint hid a configured layer")
    body = Refresh(box)
    _, hintShown = HintText(box)
    Check(not hintShown, "the hint stayed after it hid the sample layers")
    Check(not body._msufSceneDispelOverlay:IsShown() and box.layerAvailable.dispelOverlay == true, "the hint left the overlay painted or unavailable")

    -- The settings section switches its layer on while it is open (an edge: a chip click in between sticks).
    -- A preview pinned to a page only repaints (and stays shown) while that page is the active one.
    box._msuf2PinnedPreviewPageKey, M.activeKey = "uf_player", "uf_player"
    accordion["uf_player:unit_dispel_overlay"] = true
    body = Refresh(box)
    Check(box.layerVisibility.dispelOverlay == true and box.layerVisibility.dispelSymbol == false, "the open overlay section did not switch the overlay on alone")
    Check(body._msufSceneDispelOverlay:IsShown(), "the open overlay section did not paint the overlay")
    _, hintShown = HintText(box)
    Check(hintShown, "the hint hid while the overlay section was open")
    Refresh(box)
    Check(box.layerVisibility.dispelOverlay == true, "a repaint undid the section switch")
    accordion["uf_player:unit_dispel_overlay"] = false
    body = Refresh(box)
    Check(box.layerVisibility.dispelOverlay == false and not body._msufSceneDispelOverlay:IsShown(), "closing the overlay section left the overlay on")

    accordion["uf_player:unit_dispel_symbol"] = true
    Refresh(box)
    Check(box.layerVisibility.dispelSymbol == true, "the open symbol section did not switch the symbols on")
    Click(Chip(box, "dispelSymbol"))
    Check(box.layerVisibility.dispelSymbol == false, "a chip click did not switch the symbols off during the section")
    Refresh(box)
    Check(box.layerVisibility.dispelSymbol == false, "a repaint re-opened the symbols the user switched off")
    Click(Chip(box, "dispelSymbol"))
    accordion["uf_player:unit_dispel_symbol"] = false
    Refresh(box)
    Check(box.layerVisibility.dispelSymbol == true, "closing the symbol section switched off a layer the user chose")
    Click(Chip(box, "dispelSymbol"))
    Check(box.layerVisibility.dispelSymbol == false, "the symbol chip could not switch the chosen layer off again")

    -- A section that opens or closes asks the shown preview for a repaint.
    Preview.active = box
    local requests = 0
    local request = Preview.RequestRefresh
    Preview.RequestRefresh = function(reason)
        if reason == "UNIT_PREVIEW_SAMPLE_LAYER" then requests = requests + 1 end
        return request(reason)
    end
    M.OnCollapsibleSectionStateChanged("uf_player", "unit_dispel_symbol", true, nil)
    M.OnCollapsibleSectionStateChanged("uf_player", "unit_castbar", true, nil)
    M.OnCollapsibleSectionStateChanged("uf_target", "unit_dispel_symbol", true, nil)
    Preview.RequestRefresh = request
    Check(requests == 1, "section changes requested " .. requests .. " sample-layer repaints, expected exactly the matching one")
    Preview.active = nil
    box:Hide()
    M.activeKey = nil
end

---------------------------------------------------------------------------
-- Group preview
---------------------------------------------------------------------------
do
    local GF = core.GF
    local conf = GF.GetConf("party")
    conf.dispelOverlayEnabled, conf.dispelSymbolEnabled = true, true
    GF.InvalidateCompiledSpecs("party")
    Check(M.gfPreviewLayerVisible == nil or M.gfPreviewLayerVisible.dispelOverlay == nil, "group layer state existed before a preview was built")
    local group = M.GroupPreview.CreateNative(env.UIParent, { width = 720, key = "gf_bars" })
    group:Show()
    group:Refresh("SAMPLE_LAYERS_TEST")
    local layers = M.gfPreviewLayerVisible
    Check(layers.dispelOverlay == false and layers.dispelSymbol == false, "group preview sample-effect layers do not start switched off")
    Check(layers.text == true and layers.buff == true and layers.status == true, "group preview configured layers no longer start switched on")
    local function Chip(key)
        for _, chip in ipairs(group._layerButtons) do if chip._layerKey == key then return chip end end
        error("no " .. key .. " group chip")
    end
    Check(group._layerAvailable.dispelOverlay == true and group._layerAvailable.dispelSymbol == true,
        "group sample-effect chips are unavailable although their settings are on")
    local _, shown = HintText(group)
    Check(not shown and group._msuf2SampleEffectHint == nil, "the group hint existed while no sample effect paints")
    local mock = group._mock
    local function OverlayShown()
        local host = mock._msufGFPreviewDispelOverlayHost
        return host ~= nil and host:IsShown()
    end
    Check(not OverlayShown(), "the group overlay painted while its layer is off")

    World.FireScript(Chip("dispelOverlay"), "OnClick", "LeftButton")
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == true and OverlayShown(), "the group overlay chip did not switch the overlay on")
    local _, hintShown, text = HintText(group)
    Check(hintShown and text == "Sample effects shown: Dispel Overlay - not your live state", "group hint text: " .. tostring(text))
    Check(Tooltip(Chip("dispelOverlay")):find(SAMPLE_TIP, 1, true), "the group overlay chip tooltip does not say it is a sample")
    Check(not Tooltip(Chip("text")):find(SAMPLE_TIP, 1, true), "a configured group layer chip claims to be a sample")

    World.FireScript(group._msuf2SampleEffectHint, "OnClick", "LeftButton")
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == false and not OverlayShown(), "the group hint did not hide the overlay")
    _, hintShown = HintText(group)
    Check(not hintShown, "the group hint stayed after it hid the sample layers")

    -- Shift-click solo on an off sample layer asks for it, so it paints.
    env.IsShiftKeyDown = function() return true end
    World.FireScript(Chip("dispelOverlay"), "OnClick", "LeftButton")
    env.IsShiftKeyDown = function() return false end
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(M.gfPreviewSoloLayer == "dispelOverlay" and layers.dispelOverlay == true and OverlayShown(), "soloing the off overlay chip did not paint it")
    World.FireScript(group._msuf2SampleEffectHint, "OnClick", "LeftButton")
    Check(M.gfPreviewSoloLayer == nil and layers.dispelOverlay == false, "the group hint left the solo layer behind")
    group:Refresh("SAMPLE_LAYERS_TEST")

    -- The Group Bars sections switch their layers on while open, only while that page is the one shown.
    M.activeKey = "gf_bars"
    accordion["gf_bars:dispel"] = true
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == true and layers.dispelSymbol == false and OverlayShown(), "the open group overlay section did not switch the overlay on alone")
    _, hintShown = HintText(group)
    Check(hintShown, "the group hint did not follow the section's overlay")
    M.activeKey = "gf_layout"
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == false and not OverlayShown(), "leaving the Group Bars page left the section's overlay on")
    _, hintShown = HintText(group)
    Check(not hintShown, "the group hint stayed after the section's overlay went away")
    M.activeKey = "gf_bars"
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == true, "returning to the Group Bars page did not bring the overlay back")
    World.FireScript(Chip("dispelOverlay"), "OnClick", "LeftButton")
    Check(layers.dispelOverlay == false, "a chip click did not switch the overlay off during the section")
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == false, "a repaint re-opened the overlay the user switched off")
    World.FireScript(Chip("dispelOverlay"), "OnClick", "LeftButton")
    accordion["gf_bars:dispel"] = false
    group:Refresh("SAMPLE_LAYERS_TEST")
    Check(layers.dispelOverlay == true, "closing the section switched off a layer the user chose")
    World.FireScript(Chip("dispelOverlay"), "OnClick", "LeftButton")
    Check(layers.dispelOverlay == false, "the overlay chip could not switch the chosen layer off again")
    M.activeKey = nil
    group:Hide()
end

---------------------------------------------------------------------------
-- The real pages: opening and closing the accordion section of a page switches its preview layer.
---------------------------------------------------------------------------
local function Section(pageKey, sectionId)
    local page = M.cache[pageKey]
    local body = page and page.sections and page.sections[sectionId]
    local section = body and body._msuf2CollapsibleEntry
    Check(section and section.header and section.pageKey == pageKey and section.sectionId == sectionId
        and section.stateKey == pageKey .. ":" .. sectionId, pageKey .. " has no " .. sectionId .. " section")
    return section
end
local function Toggle(section)
    World.FireScript(section.header, "OnClick", "LeftButton")
    w.world.widgets:RunTimers()
end

Check(M.Open("uf_player") ~= false, "the unit page did not open")
w.world.widgets:RunTimers()
local unitBox = core.UFPreview.active
Check(unitBox and unitBox._msuf2PinnedPreviewPageKey == "uf_player", "the unit page has no pinned preview")
local overlaySection = Section("uf_player", "unit_dispel_overlay")
Check(overlaySection.open ~= true and unitBox.layerVisibility.dispelOverlay == false, "the unit page opened with its overlay layer on")
Toggle(overlaySection)
Check(unitBox.layerVisibility.dispelOverlay == true, "opening the unit Dispel Overlay section did not switch its layer on")
Toggle(overlaySection)
Check(unitBox.layerVisibility.dispelOverlay == false, "closing the unit Dispel Overlay section did not switch its layer off")

Check(M.Open("gf_bars") ~= false, "the Group Bars page did not open")
w.world.widgets:RunTimers()
local groupSection = Section("gf_bars", "dispel")
Check(groupSection.open ~= true and M.gfPreviewLayerVisible.dispelOverlay == false, "the Group Bars page opened with its overlay layer on")
Toggle(groupSection)
Check(M.gfPreviewLayerVisible.dispelOverlay == true, "opening the group Dispel Overlay section did not switch its layer on")
Toggle(groupSection)
Check(M.gfPreviewLayerVisible.dispelOverlay == false, "closing the group Dispel Overlay section did not switch its layer off")

print("preview_sample_effect_layers_smoke: PASS (" .. flavor .. ")")
