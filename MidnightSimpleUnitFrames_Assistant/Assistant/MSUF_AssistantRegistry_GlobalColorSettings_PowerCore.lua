-- Assistant global power color helper core.
-- Loaded before MSUF_AssistantRegistry_GlobalColorSettings_Core.lua; isolates power override DB access.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GlobalRegistry = A.GlobalRegistry or {}

function A.GlobalRegistry.BuildPowerColorHelpers(ctx)
    if type(ctx) ~= "table" then return nil end

    local GeneralDB = ctx.GeneralDB
    local TableRGB = ctx.TableRGB
    if type(GeneralDB) ~= "function" or type(TableRGB) ~= "function" then return nil end

    local function EnsurePowerOverrides()
        local g = GeneralDB()
        g.powerColorOverrides = type(g.powerColorOverrides) == "table" and g.powerColorOverrides or {}
        return g.powerColorOverrides
    end

    local function PowerDefaultRGB(token)
        local color = _G.PowerBarColor and token and _G.PowerBarColor[token]
        if type(color) == "table" then
            local r = tonumber(color.r or color[1])
            local g = tonumber(color.g or color[2])
            local b = tonumber(color.b or color[3])
            if r and g and b then return r, g, b end
        end
        return 0.8, 0.8, 0.8
    end

    local function PowerOverrideRGB(token)
        local dr, dg, db = PowerDefaultRGB(token)
        return TableRGB(GeneralDB().powerColorOverrides, token, dr, dg, db)
    end

    local function SetPowerOverrideRGB(token, r, gCol, b)
        EnsurePowerOverrides()[token] = { r, gCol, b }
    end

    return {
        EnsurePowerOverrides = EnsurePowerOverrides,
        PowerDefaultRGB = PowerDefaultRGB,
        PowerOverrideRGB = PowerOverrideRGB,
        SetPowerOverrideRGB = SetPowerOverrideRGB,
    }
end
