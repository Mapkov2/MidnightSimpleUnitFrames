-- Opt-in declaration preserves real unconverted and automatic shortcut owners.
local root, flavor = assert(arg[1]), assert(arg[2])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local OwnerAssert = assert(loadfile(root .. "/tools/tests/menu_button_owner_assert.lua"))()
-- Misc declares its cards now. The real unconverted automatic card is the pre-conversion
-- Misc page, pinned by blob so this fixture does not depend on which pages convert next.
local MISC_FILE = "MSUF_Menu2_GlobalMisc.lua"
local MISC_BLOB = "7fcf34bfa27269c65e550daa8ff12abd2f97f401"
local scratch = root .. "/.checks"
local windows = package.config:sub(1, 1) == "\\"
local function Quote(text)
    if windows then return '"' .. text .. '"' end
    return "'" .. text:gsub("'", "'\\''") .. "'"
end
os.execute((windows and "if not exist " or "mkdir -p ") .. Quote(scratch)
    .. (windows and (" mkdir " .. Quote(scratch)) or ""))
local pipe = assert(io.popen("git -C " .. Quote(root) .. " cat-file blob " .. MISC_BLOB, "r"))
local legacyMisc = pipe:read("*a")
pipe:close()
assert(#legacyMisc > 1000 and legacyMisc:find("local M =", 1, true), "pinned Misc page unavailable")
local legacyPath = scratch .. "/optin-parent-" .. flavor .. "-" .. MISC_FILE
local legacyFile = assert(io.open(legacyPath, "wb"))
legacyFile:write(legacyMisc)
legacyFile:close()
local mw = MenuWorld.Open(root, flavor, { clientScriptBindings = true, beforeCore = function(world)
    local load = world.LoadFile
    world.LoadFile = function(self, path, ...)
        if path:match("([^/\\]+)$") == MISC_FILE then path = legacyPath end
        return load(self, path, ...)
    end
end })
local M, W = mw.M, mw.M.Widgets
mw:Select("opt_misc")
for _, section in pairs(M.cache.opt_misc.sections) do
    local e = section._msuf2CollapsibleEntry
    if e then e.SetOpenImmediate(true) end
end
mw:RunTimers()
local automatic, color
for _, w in ipairs(mw.world.widgets.frames) do
    if w._msuf2BoundColorShortcut and not w._msuf2ControlSchema then automatic = w end
end
assert(automatic, "real unconverted automatic color card missing")
for _, w in ipairs(mw.world.widgets.frames) do
    if w._msuf2ContextColorSearchAnchor == automatic then color = w break end
end
assert(color, "automatic shortcut lost its actual bound color")
local card = automatic:GetParent()
local options, action = automatic._msuf2ContextColorOptions, automatic:GetScript("OnClick")
assert(W.AttachContextColorShortcut(card, options) == automatic)
assert(not automatic._msuf2ControlSchema and automatic:GetScript("OnClick") == action,
    "unconverted caller acquired a declaration or changed its action")
M.ControlSchema.ContextColors(card, "menu2.fixture.automatic.colors", "fixture")
assert(W._Shared.AttachBoundColorToContextCard(color) == true)
local spec = assert(automatic._msuf2ControlSchema)
assert(spec.owner == automatic and spec.get() == automatic._msuf2ContextColorOptions)
OwnerAssert.Button(automatic, spec)
assert(spec.get().getTargets()[1] == card._msuf2ContextColorOwners[1], "automatic target owner was copied")
local revised = {}
for key, value in pairs(automatic._msuf2ContextColorOptions) do revised[key] = value end
revised.title = "Current options"
local declare, calls = card._msuf2DeclareContextColorShortcut, 0
card._msuf2DeclareContextColorShortcut = function(widget)
    calls = calls + 1
    return declare(widget)
end
assert(W.AttachContextColorShortcut(card, revised) == automatic)
assert(calls == 1, "existing shortcut skipped its opt-in owner callback")
assert(automatic._msuf2ControlSchema.get() == revised and automatic:GetScript("OnClick") == action,
    "reattachment captured stale options or replaced action")
local before = mw.core.ProfileFields.CopySnapshot(mw.env.MSUF_DB)
mw.core.Util.InCombat("PLAYER_REGEN_DISABLED")
assert(automatic._msuf2ControlSchema.action(automatic) == nil)
assert(mw.core.ProfileFields.Equal(before, mw.env.MSUF_DB), "opt-in seam bypassed combat refusal")
mw.core.Util.InCombat("PLAYER_REGEN_ENABLED")
print("menu_context_shortcut_optin_smoke " .. flavor .. ": real automatic/unconverted/current-options/combat owners OK")
