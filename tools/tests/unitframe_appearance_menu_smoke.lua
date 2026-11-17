local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Forever"
local MW = dofile(root .. "/tools/tests/menu_core_world.lua")
local mw = MW.Open(root, flavor, { page = "uf_player", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(world) MW.InstallNativeUnitInputs(world) end })
local core, M, env = mw.core, mw.M, mw.env
local function Settle() mw:RunTimers(20000) M.Theme.StopAllMenuAnimations() end
local function Find(key)
    for _, widget in ipairs(mw.world.widgets.frames) do
        local action = widget._msuf2CommandAction
        if action and action.settingKey == key then return widget end
        local schema = widget._msuf2ControlSchema
        if key:match("^gf_") and schema and schema.scope == "group" and schema.key == key:match("%.(.+)$") then return widget end
    end
end
local units = { "player", "target", "targettarget", "focustarget", "focus", "pet", "pettarget", "boss", "arena" }
local count = 0
for _, unit in ipairs(units) do
    local token = (unit == "boss" or unit == "arena") and (unit .. "1") or unit
    if core.UF.IsManagedUnit(token) then
        mw:Select("uf_" .. unit)
        Settle()
        M.Widgets.EnsureSectionContent(assert(M.cache["uf_" .. unit].sections.transparency))
        Settle()
        local toggle = assert(Find(unit .. ".fadeInOnShow"), unit .. " lacks an appearance toggle")
        assert(env.MSUF_DB[unit].fadeInOnShow == false, unit .. " must default off")
        MW.FireScript(toggle, "OnClick", "LeftButton")
        Settle()
        assert(env.MSUF_DB[unit].fadeInOnShow == true, unit .. " toggle did not persist")
        assert(core.UF.Config.RefreshUnit(token).alpha.fadeIn == true, unit .. " setting did not reach the real compiler")
        count = count + 1
    end
end
mw:Select("uf_target")
Settle()
local conf = env.MSUF_DB.target
conf.hpBarAlpha, conf.powerBarAlpha, conf.hpBgAlpha = .6, .4, .25
core.UF.Config.RefreshUnit("target")
local preview
for _, frame in ipairs(mw.world.widgets.frames) do
    local scene = frame._msufPreviewScene
    if scene and scene.unit == "target" and frame.hpBar then preview = frame end
end
assert(preview and preview._msufAppearance, "real target preview lacks appearance owner")
assert(preview._msufPreviewScene:Refresh())
local Motion = core.UF.Appearance
Motion.Cancel(preview)
assert(math.abs(preview.hpBar:GetAlpha() * preview.hpBar:GetStatusBarTexture():GetAlpha() - .6) < .0001,
    "real unit preview does not preserve 60% foreground opacity")
Motion.Begin(preview)
local progress = preview._msufAppearance.value
preview._msufPreviewScene:Refresh()
assert(preview._msufAppearance.value == progress, "preview repaint restarted appearance")
conf.hpBarAlpha = .4
core.UF.Config.RefreshUnit("target")
preview._msufPreviewScene:Refresh()
assert(preview._msufAppearance.value == progress, "opacity edit restarted preview appearance")
Motion.Cancel(preview)
assert(math.abs(preview.hpBar:GetAlpha() * preview.hpBar:GetStatusBarTexture():GetAlpha() - .4) < .0001,
    "real unit preview delayed or squared foreground opacity")
mw:Select("gf_layout")
Settle()
M.Widgets.EnsureSectionContent(assert(M.cache.gf_layout.sections.transparency))
Settle()
local toggle = assert(Find("gf_party.fadeInOnShow"), "Party transparency toggle missing")
assert(env.MSUF_DB.gf_party.fadeInOnShow == false, "Party default must be off")
MW.FireScript(toggle, "OnClick", "LeftButton")
Settle()
assert(env.MSUF_DB.gf_party.fadeInOnShow == true, "Party toggle did not persist")
local GF, confGroup = core.GF, env.MSUF_DB.gf_party
confGroup.hpBarAlpha, confGroup.hpBgAlpha, confGroup.rangeFadeEnabled = .6, .25, false
GF.InvalidateCompiledSpecs("party")
local host = env.CreateFrame("Frame", nil, env.UIParent)
host:SetSize(500, 300)
local sceneRoot = GF.NewPreviewScene(host)
local group = assert(sceneRoot:Group("party", 4))
sceneRoot:Activate()
group:Show(4, { immediate = true })
Settle()
local member = assert(group.t.frames.party[1])
assert(member._msufAppearance, "real group preview lacks appearance owner")
Motion.Cancel(member)
assert(math.abs(member.hpBar:GetAlpha() * member.hpBar:GetStatusBarTexture():GetAlpha() - .6) < .0001,
    "real group preview squared/lost the 60% foreground setting")
assert(member.MSUFSpec.alpha.fadeIn == true, "group appearance flag absent from compiled overlay")
member._msufGFPriorityFrame = true
assert(GF.CompileSpec("party", member, "party1").alpha.fadeIn == true, "Priority overlay lost the inherited appearance setting")
sceneRoot:Deactivate()
confGroup.enabled, confGroup.petsEnabled, confGroup.targetsEnabled = true, true, true
for _, prefix in ipairs({ "targets", "pets" }) do
    local holder = assert(GF.RenderAdditionalPreview(host, "party", prefix, 3, { position = false }))
    local extra = assert(holder.buttons[1])
    assert(extra._msufAppearance, prefix .. " preview missed the inherited appearance setting")
    local state = extra._msufAppearance
    GF.RenderAdditionalPreview(host, "party", prefix, 3, { position = false })
    assert(extra._msufAppearance == state, prefix .. " refresh recreated the animation state")
    GF.HideAdditionalPreview(host, prefix)
end
mw:Select("opt_misc")
Settle()
for _, section in pairs(M.cache.opt_misc.sections) do M.Widgets.EnsureSectionContent(section) end
Settle()
MW.FireScript(assert(Find("general.reduceMotion")), "OnClick", "LeftButton")
Settle()
assert(env.MSUF_DB.general.reduceMotion == true, "reduce-motion control failed")
print("unitframe_appearance_menu_smoke " .. flavor .. ": " .. count .. " unit controls, real unit/group opacity, Priority and reduced motion passed")
