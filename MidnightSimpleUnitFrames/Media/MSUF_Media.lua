-- Media bootstrap (safe, cold-path)
-- This file is intentionally tiny: MSUF_Libs.lua owns the actual LibSharedMedia registrations.
-- We keep this here so the .toc can load a stable entrypoint regardless of refactors.

local addonName = ...

-- If the libs file already provided a force-register helper, run it once.
if type(_G.MSUF_ForceRegisterBundledMedia) == "function" then
    _G.MSUF_ForceRegisterBundledMedia()
end
