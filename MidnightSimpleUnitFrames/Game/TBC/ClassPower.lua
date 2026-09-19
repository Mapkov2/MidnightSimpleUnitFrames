--- Burning Crusade Classic ClassPower provider.
--- TBC has target-owned combo points but none of the later class resources, so
--- the whole provider is the shared target-combo one.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local TargetCombo = assert(MSUF.CPTargetCombo, "shared target-combo module must load first")
local _, playerClass = _G.UnitClass("player")

MSUF.CPClient = TargetCombo.NewComboOnlyProvider("TBC", playerClass)
