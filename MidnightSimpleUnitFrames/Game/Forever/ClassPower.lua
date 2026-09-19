--- WoW Forever ClassPower provider.
---
--- Forever reads the Mainline TOC and runs the Retail ClassPower controller,
--- but Blizzard loads none of the Retail class resource bars for its camelot
--- game type (Blizzard_UnitFrame.toc excludes the Paladin, Shard, Arcane
--- Charges, Rogue/Druid combo point, Rune, Essence, Insanity, Harmony and
--- Stagger bars). Its only class resource display is the target-owned
--- ComboFrame: GetComboPoints(unit, "target"), refreshed on
--- PLAYER_TARGET_CHANGED. Forever therefore routes like the Classic Era
--- provider - combo points for Rogues and Cat Form Druids, nothing for any
--- other class - and reads no Retail specialization index.
---
--- Blizzard's ComboFrame is not suppressed from here: on Forever it is a
--- UIParent child that Blizzard re-anchors to TargetFrame, so it follows the
--- Blizzard target frame in Kernel/MSUF_BlizzardFrames.lua, not the class
--- resource suppression the Classic compat layer drives.
---
--- Every other Mainline client returns at once, so Midnight keeps its routing,
--- its event bindings and MSUF.CPClient nil.
local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local Client = MSUF.Client
if not (Client and Client.IsForever == true) then return end

local TargetCombo = assert(MSUF.CPTargetCombo, "shared target-combo module must load first")
local K = _G.MSUF_CP_CONST or {}
local CPK = K.CPK or {}
local MODE = CPK.MODE or {}
local PT = K.PT or {}
local NotSecret = MSUF.Secrets.NotSecret
local UnitPowerType = _G.UnitPowerType
local GetShapeshiftFormID = _G.GetShapeshiftFormID
local PLAYER_CLASS = select(2, _G.UnitClass("player"))

local Provider = { Flavor = "Forever" }

Provider.UnitPower = TargetCombo.NewPowerReader()
Provider.AcceptPowerToken = TargetCombo.NewPowerTokenTest(PLAYER_CLASS)

--- The Mainline controller reads the target-change rule through a Client table,
--- where the Classic controller reads it from the provider itself.
Provider.Client = { NeedsTargetChanged = TargetCombo.NeedsTargetChanged }

--- Combo points can move to a new target without a target swap.
local supportsEvent = Client.SupportsEvent
Provider.comboTargetEvent = type(supportsEvent) == "function"
    and supportsEvent("COMBO_TARGET_CHANGED") == true

function Provider.GetClassPowerType()
    if PLAYER_CLASS == "ROGUE" then
        return PT.ComboPoints, MODE.SEGMENTED, false
    end
    if PLAYER_CLASS == "DRUID" then
        local primaryPower = UnitPowerType("player")
        if NotSecret(primaryPower) then
            if primaryPower == PT.Energy then return PT.ComboPoints, MODE.SEGMENTED, false end
        elseif GetShapeshiftFormID and GetShapeshiftFormID() == 1 then
            --- DRUID_CAT_FORM is 1 on Forever (Blizzard_FrameXMLBase Constants.lua).
            return PT.ComboPoints, MODE.SEGMENTED, false
        end
    end
    return nil, MODE.NONE, false
end

MSUF.CPClient = Provider
