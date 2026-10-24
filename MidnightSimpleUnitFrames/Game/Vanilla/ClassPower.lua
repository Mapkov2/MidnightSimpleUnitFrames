--- Classic Era ClassPower provider.
--- Era combo points are target-owned and no later class resource exists, so the
--- whole provider is the shared target-combo one.

local _, MSUF = ...

local TargetCombo = assert(MSUF.CPTargetCombo, "shared target-combo module must load first")
local _, playerClass = UnitClass("player")

MSUF.CPClient = TargetCombo.NewComboOnlyProvider("Vanilla", playerClass)
