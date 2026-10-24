-- Explicit action write targets and per-context declarations on reused previews.
local root, flavor, proposal = assert(arg[1]), arg[2] or 'Mainline', arg[3]
local MenuWorld = assert(loadfile(root .. '/tools/tests/menu_core_world.lua'))()
local options = { clientScriptBindings = true }
if proposal then
    options.beforeOptions = function(world)
        local load = world.LoadFile
        function world:LoadFile(path, addon, namespace)
            local name = path:match('([^/\\]+)$')
            if name == 'MSUF_Menu2_ControlSchema.lua' or name == 'MSUF_Menu2_ControlCatalog.lua' then
                local chunk = assert(loadfile(proposal .. '/' .. name))
                setfenv(chunk, self.env)
                return pcall(chunk, addon, namespace)
            end
            return load(self, path, addon, namespace)
        end
    end
end
local mw = MenuWorld.Open(root, flavor, options)
local M, env = mw.M, mw.world.env
for _, id in ipairs({ 'menu2.classpower.class-power-preview.handle.class.power.open.settings',
    'menu2.gf_layout.group.preview.handle.buff.open_settings',
    'menu2.menu-chrome.search-shortcut-target-size' }) do
    local widget = env.CreateFrame('Button')
    M.ControlSchema.Custom(widget, { id = id, kind = 'button', scope = 'menu', applyDomain = 'menuAction' })
    local spec = widget._msuf2ControlSchema
    assert(not spec.setting and spec.ephemeralReason, id .. ': navigation has no explicit no-write reason')
end
local tile = env.CreateFrame('Button')
M.ControlSchema.Custom(tile, { id = 'menu2.gf_auras.group.spell.tile.slot.1', kind = 'button',
    scope = 'gf_auras', applyDomain = 'menuAction' })
local spec = tile._msuf2ControlSchema
assert(spec.setting and not spec.ephemeralReason, 'spell tile command writes were described as ephemeral')
for _, path in ipairs({ 'gf_party.spellIndicators', 'gf_raid.spellIndicators', 'gf_mythicraid.spellIndicators' }) do
    assert(M.ControlSchema.Matches(spec.setting, path), 'spell tile target missing: ' .. path)
end
local zoom = env.CreateFrame('Slider')
for _, page in ipairs({ 'gf_auras', 'gf_layout' }) do
    local id = 'menu2.' .. page .. '.preview.zoom.surface'
    M.RuntimeControlCatalog.Register(zoom, { controlId = id, pageKey = page, label = 'Preview zoom',
        kind = 'slider', classification = 'ephemeral', ephemeralReason = 'Changes preview zoom only.' }, 'regression')
    assert(zoom._msuf2ControlSchema.id == id and zoom._msuf2ControlSchema.scope == page,
        page .. ': reused widget kept a different context declaration')
end
print('PASS schema action targets and reused declarations: ' .. flavor)
