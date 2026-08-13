-- Assistant Auras shared reminder setting registry.
-- Loaded before the Auras setting installer; this is cold Assistant metadata only.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.AurasRegistry = A.AurasRegistry or {}

-- Buff reminders belonged to Auras2. Auras3 has no runtime consumer for these
-- fields, so keeping Assistant settings here would acknowledge writes that can
-- never affect an aura. Leave the entry points in place for load-order
-- compatibility, but deliberately register nothing.
function A.AurasRegistry.RegisterSharedReminderCoreSettings()
    return false
end

function A.AurasRegistry.RegisterSharedReminderToggleSettings()
    return false
end
