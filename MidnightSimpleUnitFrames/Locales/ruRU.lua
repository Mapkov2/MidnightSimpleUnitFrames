-- ============================================================================
-- MSUF - ruRU
--
-- Translator: fill the table below and open a PR.
-- Keys are the original English UI strings.
--
-- Perf note:
-- This file is an immediate no-op unless the active locale is ruRU.
-- ============================================================================
local addonName, ns = ...

-- Fast exit for non-ruRU clients (use ns.LOCALE if already initialized).
local loc = (ns and ns.LOCALE) or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
if loc ~= "ruRU" then return end

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
    -- ["Open MSUF Menu"] = "...",
}

for k, v in pairs(T) do
    L[k] = v
end
