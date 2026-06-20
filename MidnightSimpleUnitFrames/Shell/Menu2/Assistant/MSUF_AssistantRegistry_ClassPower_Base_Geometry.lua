-- Assistant ClassPower base geometry setting registry.
-- Loaded before MSUF_AssistantRegistry_ClassPower_Base.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.ClassPowerRegistry = A.ClassPowerRegistry or {}

function A.ClassPowerRegistry.RegisterBaseGeometrySettings(ctx)
    if type(ctx) ~= "table" then return end

    local RegisterBarsNumber = ctx.RegisterBarsNumber
    local ClassPowerAliases = ctx.ClassPowerAliases
    if type(RegisterBarsNumber) ~= "function" or type(ClassPowerAliases) ~= "function" then return end

    RegisterBarsNumber("classPowerWidth", "width", "Class Resource Width", 0, 30, 800, ClassPowerAliases("width", "class resource bar width"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_WIDTH",
        relativeStep = 10,
        exactAliases = {
            "class resource width",
            "class resources width",
            "class power width",
            "class resource bar width",
            "class resources bar width",
            "class resource wider",
            "class resources wider",
            "class resource narrower",
            "class resources narrower",
            "combo point width",
            "combo points width",
            "combo point wider",
            "combo points wider",
            "combo point narrower",
            "combo points narrower",
        },
    })
    RegisterBarsNumber("classPowerOffsetX", "offsetX", "Class Resource Offset X", 0, -800, 800, ClassPowerAliases("x offset", "class resource x", "class power x", "move class resource horizontally"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_X",
        moveAxis = "x",
        moveStep = 10,
        exactAliases = {
            "move class resource left",
            "move class resource right",
            "move class resources left",
            "move class resources right",
            "nudge class resource left",
            "nudge class resource right",
            "shift class resource left",
            "shift class resource right",
            "move class power left",
            "move class power right",
            "move combo point left",
            "move combo point right",
            "move combo points left",
            "move combo points right",
            "shift combo points left",
            "shift combo points right",
            "verschiebe class resource links",
            "verschiebe class resource rechts",
            "verschiebe combo points links",
            "verschiebe combo points rechts",
        },
    })
    RegisterBarsNumber("classPowerOffsetY", "offsetY", "Class Resource Offset Y", 0, -800, 800, ClassPowerAliases("y offset", "class resource y", "class power y", "move class resource vertically"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_Y",
        moveAxis = "y",
        moveStep = 10,
        exactAliases = {
            "move class resource up",
            "move class resource down",
            "move class resources up",
            "move class resources down",
            "nudge class resource up",
            "nudge class resource down",
            "shift class resource up",
            "shift class resource down",
            "move class power up",
            "move class power down",
            "move combo point up",
            "move combo point down",
            "move combo points up",
            "move combo points down",
            "shift combo points up",
            "shift combo points down",
            "verschiebe class resource hoch",
            "verschiebe class resource runter",
            "verschiebe combo points hoch",
            "verschiebe combo points runter",
        },
    })
    RegisterBarsNumber("classPowerFrameLevelOffset", "frameLevel", "Class Resource Frame Level", 5, 0, 30, ClassPowerAliases("frame level", "class resource strata level"), {
        reason = "MSUF_ASSISTANT_CLASSPOWER_FRAME_LEVEL",
    })
end
