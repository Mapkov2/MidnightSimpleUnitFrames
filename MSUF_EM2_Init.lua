-- ============================================================================
-- MSUF_EM2_Init.lua
-- Loads last. Compat.lua already provides all legacy globals.
-- This file ensures combat listener and exposes version tag.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

if EM2.State and EM2.State.EnsureCombatListener then
    EM2.State.EnsureCombatListener()
end

EM2.VERSION = "2.0.0"
