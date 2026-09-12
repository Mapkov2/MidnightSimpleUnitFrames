-- Shared setters must keep plain-value caching and secret forwarding distinct.
local hasAny = assert(_G.MSUF_AuraTableHasAnyKey)
assert(hasAny({ enabled = false }, { enabled = true }), "explicit false is still a stored key")
assert(not hasAny({}, { enabled = true }) and not hasAny(nil, {}))
local original = { nested = { enabled = false, ids = { 1, 2 } } }
local copy = _G.MSUF_GF_CopySpellConfig(original)
copy.nested.ids[1] = 99
assert(original.nested.ids[1] == 1 and copy.nested.enabled == false, "spell config copy aliases input")
_G.MSUF_IsCooldownAnchorSupported = function() return true end
_G.MSUF_IsCooldownAnchorEnabled = nil
assert(_G.MSUF_GlobalCooldownAnchorEnabled({ anchorToCooldown = true }))
assert(not _G.MSUF_GlobalCooldownAnchorEnabled({ anchorToCooldown = false }))
_G.MSUF_IsCooldownAnchorEnabled = function() return false end
assert(not _G.MSUF_GlobalCooldownAnchorEnabled({ anchorToCooldown = true }), "late capability owner ignored")
_G.MSUF_IsCooldownAnchorEnabled, _G.MSUF_IsCooldownAnchorSupported = nil, nil
local secret = {}
_G.issecretvalue = function(value) return rawequal(value, secret) end
local ns = { Secrets = { IsSecret = _G.issecretvalue } }
assert(loadfile("MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Apply.lua"))("MSUF", ns)
local writes = 0
local region = { SetText = function(self, value)
    writes = writes + 1
    if rawequal(value, secret) then
        assert(self._aText == nil and self._aTextPlain == nil, "cache must clear before native secret call")
    end
end }
ns.Apply.Text(region, "ready")
ns.Apply.Text(region, "ready")
assert(writes == 1, "unchanged plain text reached native setter")
ns.Apply.Text(region, secret)
ns.Apply.Text(region, secret)
assert(writes == 3 and region._aTextPlain == nil, "secret text was cached")
ns.Apply.Text(region, "ready")
assert(writes == 4, "plain text did not resume after secret")

-- Only the current visible Bars page may refresh its priority-row widgets.
local shown, refreshes = true, 0
local entry = { refreshHighlightPriorityColors = function() refreshes = refreshes + 1 end }
local M = {
    cache = { opt_bars = entry }, activeKey = "opt_bars",
    frame = { IsShown = function() return shown end },
}
_G.InCombatLockdown = function() return false end
_G.C_Timer = { After = function() end }
_G.MSUF_UFPreview_RequestRefresh = function() end
_G.MSUF_RefreshAllFrameColors = function(scope) assert(scope == "player") end
local menuNS = { MSUF2 = M }
local host = assert(loadfile(".github/scripts/msuf_test_stubs.lua"))().New()
_G.CreateFrame = function(...) return host:CreateFrame(...) end
assert(loadfile("MidnightSimpleUnitFrames/Kernel/MSUF_Bootstrap.lua"))("MSUF", menuNS)
assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Engine/Group/MSUF_UF_Group_Runtime.lua"))("MSUF", menuNS)
assert(loadfile("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_ApplyService.lua"))("MSUF", menuNS)
local function refresh()
    M.ApplyService.RequestColors("contract", "player")
    M.ApplyService.Flush()
end
refresh()
assert(refreshes == 1, "visible priority colors were not refreshed")
entry._msuf2Invalidated = true
refresh()
assert(refreshes == 1, "invalidated entry received a refresh")
entry._msuf2Invalidated = nil
shown = false
refresh()
assert(refreshes == 1, "hidden menu received a widget refresh")
shown, M.activeKey = true, "opt_fonts"
refresh()
assert(refreshes == 1, "inactive page received a widget refresh")
M.activeKey = "opt_bars"
local replacement = { refreshHighlightPriorityColors = function() refreshes = refreshes + 10 end }
M.cache.opt_bars = replacement
refresh()
assert(refreshes == 11, "refresh retained stale page ownership")
print("PASS lean runtime: plain/secret text cache and current visible priority widget ownership")
