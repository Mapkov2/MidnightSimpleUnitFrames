local _, ns = ...

local framework = ns and ns.MSUFUnitFrames
if not framework then
  error("MSUFUnitFrames finalize.lua loaded without an initialized framework.", 2)
end

-- API functions retain their private instance state in closures. Consumers get
-- only the supported public surface, matching oUF's embedded-instance model.
framework.Private = nil
