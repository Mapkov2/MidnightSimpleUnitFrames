-- Exercise the real page, scan button and menu lifecycle across page splits.
local root = assert(arg[1])
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, "Mainline", { clientScriptBindings = true })
local M = mw.M
M.AurasParts.SetUnitAuraTool("player", "buff", "blacklist")
M.unitAuraTabSelection = { player = "buff" }
assert(mw:Select("uf_player"))
for _ = 1, 3 do
    for _, section in pairs(M.cache.uf_player.sections or {}) do
        local disclosure = section._msuf2CollapsibleEntry
        if disclosure then
            if disclosure._msuf2EnsureContent then disclosure._msuf2EnsureContent() end
            disclosure.SetOpenImmediate(true)
        end
    end
    mw:RunTimers()
end
local start
for _, frame in ipairs(mw.world.widgets.frames) do
    local label = frame._msuf2Label
    if (frame.GetText and frame:GetText() == "Start combat scan")
        or (label and label.GetText and label:GetText() == "Start combat scan") then start = frame; break end
end
assert(start, "real aura page has no scan control")
local reads, combat = 0, false
mw.core.MSUF_Auras3.MenuModel.LiveBlacklistAuraValues = function()
    reads = reads + 1
    return {}, 0, false
end
M.IsConfigCombatLocked = function() return combat end
MenuWorld.FireScript(start, "OnClick", "LeftButton")
local scanner = assert(M._auraCombatScanner, "scan button did not create the scanner")
assert(scanner._scanning and scanner:GetScript("OnUpdate"), "scan session did not start")
scanner:GetScript("OnUpdate")(scanner, 0.4)
assert(reads == 1, "open scanner did not scan")
M.HideSlashMenuAndMinibar(mw.win)
local callback = scanner:GetScript("OnUpdate")
for _ = 1, 25 do if callback then callback(scanner, 0.4) end end
print("scanner closed, 10 s: " .. (reads - 1) .. " aura reads; OnUpdate=" .. tostring(callback ~= nil))
assert(reads == 1 and callback == nil and not next(scanner.events), "closed scanner still polls/listens")
assert(M.frame:HasScript("OnShow"), "scanner has no reopen route")
combat = true
M.frame:Show()
assert(scanner:GetScript("OnUpdate") == nil, "combat resumed a paused scanner")
combat = false
MenuWorld.FireScript(M.frame, "OnShow")
scanner:GetScript("OnUpdate")(scanner, 0.4)
assert(reads == 2 and scanner:IsShown(), "reopen lost scan session")
scanner.Finish(false)
assert(not scanner._scanning and not scanner:GetScript("OnUpdate") and not next(scanner.events), "stopped scanner resumes")
MenuWorld.FireScript(M.frame, "OnShow")
assert(not scanner:GetScript("OnUpdate"), "finished scan restarted")
