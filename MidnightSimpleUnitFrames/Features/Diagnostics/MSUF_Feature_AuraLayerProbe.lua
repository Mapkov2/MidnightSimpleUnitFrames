--- MSUF_Feature_AuraLayerProbe.lua - temporary diagnostic: aura frame levels.
--- /msufauralayers dumps the level/strata chain (unit frame -> aura root ->
--- layout host -> native container -> first AuraButton) for the player and
--- target buff/debuff lanes, then probes two PTR-behaviour questions live:
---   1. does SetFrameLevel on the host propagate to its children?
---   2. does SetFrameLevel on the sealed container stick at all?
--- Zero cost unless invoked; every probe restores the original level.
local _addonName, _MSUF = ...

local function Level(frame)
    if not (frame and frame.GetFrameLevel) then return "?" end
    return tostring(frame:GetFrameLevel())
end

local function Strata(frame)
    if not (frame and frame.GetFrameStrata) then return "?" end
    return tostring(frame:GetFrameStrata())
end

local function Say(text)
    print("|cff7fd5ffMSUF|r aura layers: " .. text)
end

local function ProbeLane(unitKey, rootKey)
    local frame = _G["MSUF_" .. unitKey]
    if not frame then
        Say(unitKey .. ": no unit frame")
        return
    end
    local root = frame.Auras
    local container = root and root[rootKey]
    if not container then
        Say(("%s %s: no container (root=%s)"):format(unitKey, rootKey, root and "yes" or "no"))
        return
    end
    local host = container._msufA3LayoutHost
    local hostParent = host and host.GetParent and host:GetParent()
    local containerParent = container.GetParent and container:GetParent()
    local button
    if container.GetAuraGroupFrame and container._msufA3ManagedGroupKey then
        button = container:GetAuraGroupFrame(container._msufA3ManagedGroupKey, 1)
    end
    button = button or container[1]
    Say(("%s %s: frame L%s/%s root L%s/%s host L%s/%s(parent=%s) container L%s/%s(parent=%s) btn1 L%s/%s"):format(
        unitKey, rootKey,
        Level(frame), Strata(frame), Level(root), Strata(root),
        Level(host), Strata(host),
        hostParent == root and "root" or tostring(hostParent and "other" or "nil"),
        Level(container), Strata(container),
        containerParent == host and "host" or (containerParent == root and "root" or "other"),
        Level(button), Strata(button)))
    local hpBar = frame.hpBar or frame.Health or frame.health
    Say(("  neighbors: hpBar L%s/%s power L%s"):format(
        Level(hpBar), Strata(hpBar),
        Level(frame.powerBar or frame.Power or frame.power)))

    if host and host.SetFrameLevel and host.GetFrameLevel and container.GetFrameLevel then
        local hostBefore = host:GetFrameLevel()
        local containerBefore = container:GetFrameLevel()
        host:SetFrameLevel(hostBefore + 3)
        local containerAfter = container:GetFrameLevel()
        host:SetFrameLevel(hostBefore)
        Say(("  probe host+3: containerDelta=%s (3 = children follow, 0 = no propagation)"):format(
            tostring(containerAfter - containerBefore)))
    end
    if container.SetFrameLevel and container.GetFrameLevel then
        local before = container:GetFrameLevel()
        container:SetFrameLevel(before + 1)
        local after = container:GetFrameLevel()
        container:SetFrameLevel(before)
        Say(("  probe container+1: stuck=%s (true = sealed container still accepts SetFrameLevel)"):format(
            tostring(after == before + 1)))
    end
end

_G.SLASH_MSUFAURALAYERS1 = "/msufauralayers"
_G.SlashCmdList["MSUFAURALAYERS"] = function()
    ProbeLane("player", "Buffs")
    ProbeLane("player", "Debuffs")
    ProbeLane("target", "Buffs")
    ProbeLane("target", "Debuffs")
    Say("done - paste this output when reporting layering issues")
end
--- Listed in /msuf help only while this file is actually loaded.
if _MSUF and _MSUF.SlashCommands and _MSUF.SlashCommands.RegisterExternal then
    _MSUF.SlashCommands.RegisterExternal({
        usage = "/msufauralayers",
        help = "Dump the aura frame levels for a layering bug report.",
        dev = true,
    })
end
