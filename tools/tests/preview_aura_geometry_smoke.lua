-- preview_aura_geometry_smoke.lua <repoRoot>
-- Exercise the shipped config adapter before the shared runtime workbench sees it.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local f = assert(io.open(arg[2] or (root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_Auras_Preview.lua"), "rb"))
local source = f:read("*a"):gsub("\r\n", "\n")
f:close()
local body = assert(source:match("local function FitMiniAuraPreview%([^\n]+\n(.-)\nend"))
local env = { max = math.max, min = math.min, floor = math.floor, ceil = math.ceil, tonumber = tonumber,
    Round = function(n) return math.floor((tonumber(n) or 0) + 0.5) end }
local fit = assert(loadstring("return function(cfg, width, height)\n" .. body .. "\nend"))
setfenv(fit, env)
fit = fit()
local cases = 0
for _, spacing in ipairs({ 12, 64, 0, 2, 10 }) do
    for _, growth in ipairs({ "RIGHTDOWN", "LEFTUP", "UP", "DOWN" }) do
        for _, viewport in ipairs({ { 300, 104 }, { 90, 60 }, { 760, 300 } }) do
            local cfg = { size = 96, spacing = spacing, perRow = 7, maxIcons = 14, growth = growth,
                heightPercent = 60, stackSize = 6, cooldownSize = 6, durationBarHeight = 12 }
            fit(cfg, viewport[1], viewport[2])
            assert(cfg.spacing == spacing, "configured spacing changed: " .. spacing .. " -> " .. cfg.spacing)
            assert(cfg.size == 96 and cfg.actualSize == 96, "viewport changed icon geometry")
            assert(cfg.perRow == 7 and cfg.count == 14, "viewport changed sample wrapping/count")
            assert(cfg.stackSize == 6 and cfg.cooldownSize == 6 and cfg.durationBarHeight == 12,
                "viewport changed text or duration-bar geometry")
            cases = cases + 1
        end
    end
end
assert(source:find("workbench:Fit(scale)", 1, true), "whole-canvas fitting disappeared")
print("preview_aura_geometry_smoke: PASS " .. cases .. " configured geometries")
