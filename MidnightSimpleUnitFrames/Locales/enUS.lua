-- ============================================================================
-- MSUF - enUS (base)
-- This file is optional. The fallback is the key itself.
-- Keeping this as a template makes it easier to add "special-case" wording.
-- ============================================================================
local addonName, ns = ...
ns = ns or {}
ns.LOCALE = ns.LOCALE or ((type(GetLocale) == "function" and GetLocale()) or "enUS")
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then setmetatable(L, { __index = function(t, k) return k end }) end
if _G then _G.MSUF_L = L end
if ns.LOCALE ~= "enUS" then return end

-- Put overrides here if you ever want to change wording without touching code.
-- local T = { ["Old"] = "New" }
-- for k, v in pairs(T) do L[k] = v end
