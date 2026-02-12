-- ============================================================================
-- MSUF - zhCN
--
-- Translator: fill the table below and open a PR.
-- Keys are the original English UI strings.
--
-- Perf note:
-- This file is an immediate no-op unless the active locale is zhCN.
-- ============================================================================
local addonName, ns = ...

-- Fast exit for non-zhCN clients (use ns.LOCALE if already initialized).
local loc = (ns and ns.LOCALE) or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
if loc ~= "zhCN" then return end

ns = ns or {}
ns.LOCALE = loc
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
if _G then _G.MSUF_L = L end

-- Add / edit translations below.
local T = {
    ["Open MSUF Menu"] = "打开 MSUF 菜单",
    ["Edit Mode"] = "编辑模式",
    ["Exit MSUF Edit Mode"] = "退出 MSUF 编辑模式",
    ["Profiles"] = "配置文件",
    ["Snap to grid"] = "吸附到网格",
    ["On"] = "开",
    ["Off"] = "关",
    -- Add more as you go:
    -- ["..."] = "...",
}

for k, v in pairs(T) do
    L[k] = v
end
