-- Preview reads must leave published specs and deferred runtime work intact.
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = assert(arg[2], "client flavor required")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local failures = {}

local function Check(ok, message)
    if not ok then error(message, 0) end
end

local function Case(label, fn)
    local ok, message = pcall(fn)
    print((ok and "PASS " or "FAIL ") .. label .. (ok and "" or (": " .. tostring(message))))
    if not ok then failures[#failures + 1] = label .. ": " .. tostring(message) end
end

local function Start()
    local mw = MenuWorld.Open(root, flavor, { open = false })
    mw.env.MSUF_DB.player.portraitMode = "LEFT"
    local config = mw.core.UF.Config
    config.Refresh()
    local spec = assert(config.specs.player)
    local frame = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
    frame:SetSize(spec.width, spec.height)
    frame.MSUFSpec = spec
    frame._msufPortraitRuntimeCfg = spec.portrait
    frame.MSUFPortraitHolder = { _msufLayoutWidth = 37, _msufLayoutHeight = 39 }
    mw.core.UF.frames.player = frame
    return mw, config, spec, frame
end

local function Snapshot(config, spec)
    return { serial = config.serial, portrait = spec.portrait, health = spec.health, text = spec.text }
end

local function Unchanged(mw, config, spec, before)
    Check(config.serial == before.serial, "preview advanced the live compiler serial")
    Check(spec.portrait == before.portrait, "preview replaced the applied portrait config")
    Check(spec.health == before.health and spec.text == before.text, "preview replaced live health/text configs")
    local w, h = mw.core.UFPreviewRuntime.AppliedPortraitSizeForPreviewKey("player")
    Check(w == 37 and h == 39, "preview invalidated the applied portrait size identity")
end

local function Pending(mw, config)
    mw.world.widgets:SetCombat(true)
    Check(mw.core.UF.NotifyConfigChanged("player", true, true, "PREVIEW_SPEC_LIFECYCLE") == false,
        "combat apply was not deferred")
    Check(config.dirty == true and mw.core.UF.pendingApply.player == true, "runtime did not queue the change")
    -- Read before the deferred runtime driver flushes after lockdown ends.
    mw.world.widgets:SetCombat(false)
end

Case("clean first read and profile reference change", function()
    local mw, config, spec = Start()
    local before = Snapshot(config, spec)
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("player") == spec, "preview lost the published spec")
    local swapped = {}
    for key, value in pairs(mw.env.MSUF_DB) do swapped[key] = value end
    mw.env.MSUF_DB = swapped
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("player") == spec, "profile swap lost the published spec")
    Unchanged(mw, config, spec, before)
end)

Case("dirty first read leaves deferred apply authoritative", function()
    local mw, config, spec = Start()
    local before = Snapshot(config, spec)
    Pending(mw, config)
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("player") == spec, "preview lost the published spec")
    Unchanged(mw, config, spec, before)
    Check(config.dirty == true and mw.core.UF.pendingApply.player == true, "preview consumed pending runtime work")
    -- Once the runtime publishes its next config, the preview follows it.
    config.Refresh()
    Check(config.serial == before.serial + 1, "runtime did not retain compiler ownership")
    local nextSpec = config.specs.player
    local nextPortrait = nextSpec.portrait
    Check(nextPortrait ~= before.portrait, "runtime did not publish a new portrait config")
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("player") == nextSpec, "preview kept an obsolete spec")
    Check(nextSpec.portrait == nextPortrait and config.serial == before.serial + 1,
        "preview recompiled the runtime's newly published spec")
end)

Case("first visible refresh preserves live config identities", function()
    local mw, config, spec = Start()
    local before = Snapshot(config, spec)
    Pending(mw, config)
    local env, preview = mw.env, mw.core.UFPreview
    local parent = env.CreateFrame("Frame", nil, env.UIParent)
    parent:SetSize(900, 400)
    local panel = env.CreateFrame("Frame", nil, parent)
    panel._msufGetCurrentKey = function() return "player" end
    local box = preview._BuildPreview(parent, panel, 900, 400)
    box:Show()
    box.canvas:SetSize(600, 260)
    preview.Refresh(box, "SHOW")
    Unchanged(mw, config, spec, before)
    Check(box._msufPreviewScene.runtimeSpec == spec, "visible preview did not use the published spec")
    Check(config.dirty == true and mw.core.UF.pendingApply.player == true, "refresh consumed deferred runtime work")
end)

Case("absent supported spec never triggers live compilation", function()
    local mw, config, spec = Start()
    local before = Snapshot(config, spec)
    config.specs.player = nil
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("player") == nil, "preview compiled an absent live spec")
    Check(config.specs.player == nil and config.serial == before.serial, "absent read changed live compiler state")
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("not_a_unit") == nil, "unsupported preview acquired a spec")
    Check(config.serial == before.serial, "unsupported read changed live compiler state")
    config.specs.player = spec
    Unchanged(mw, config, spec, before)
end)

Case("combat read preserves config and the preview refresh gate", function()
    local mw, config, spec = Start()
    local before = Snapshot(config, spec)
    mw.world.widgets:SetCombat(true)
    config.dirty = true
    Check(mw.core.UFPreviewRuntime.SpecForPreviewKey("player") == spec, "combat read lost the published spec")
    Unchanged(mw, config, spec, before)
    Check(config.dirty == true, "combat read cleared deferred config work")
    local box = mw.env.CreateFrame("Frame", nil, mw.env.UIParent)
    box:Show()
    mw.core.UFPreview.RequestRefreshForBox(box, "SHOW")
    Check(box._refreshAfterCombatReason == "SHOW" and not box._refreshQueued, "preview bypassed its combat gate")
    mw.world.widgets:SetCombat(false)
end)

Check(#failures == 0, table.concat(failures, "\n"))
print("preview_spec_lifecycle_smoke: ok (" .. flavor .. ")")
