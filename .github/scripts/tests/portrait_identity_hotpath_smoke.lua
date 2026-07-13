-- Regression coverage for the CLASS portrait target-change fast path.
local root = arg and arg[1] or "."

local function Check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local classToken = "WARRIOR"
local SECRET = {}
local timeReads, classReads, mediaReads, portraitWrites = 0, 0, 0, 0
local frameShownReads, holderShownReads = 0, 0

_G.issecretvalue = function(value) return value == SECRET end
_G.GetTime = function()
    timeReads = timeReads + 1
    return timeReads
end

local elements = {}
local UF = {
    Layers = {},
    RegisterElement = function(name, element) elements[name] = element end,
}
local Visuals = {
    UF = UF,
    UnitClass = function()
        classReads = classReads + 1
        return classToken, classToken
    end,
    UnitGUID = function() return "Creature-0-0-0-0-1" end,
    UnitExists = function() return true end,
    SetPortraitTexture = function(texture, unit)
        portraitWrites = portraitWrites + 1
        texture.unitPortrait = unit
    end,
    SetShown = function(region, shown)
        region._msufShown = shown == true
        region.shown = shown == true
    end,
}
local MSUF = {
    UF = UF,
    UFVisuals = Visuals,
    PortraitMedia = {
        ResolveClassPortrait = function(class, style)
            mediaReads = mediaReads + 1
            if class == nil then return nil end
            return { texture = class .. ":" .. style }
        end,
    },
}
_G.MSUF_NS = MSUF

assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Portrait.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

local Portrait = assert(elements.Portrait, "portrait element missing")
local texture = { textureWrites = 0 }
function texture:SetTexture(value)
    self.texture = value
    self.textureWrites = self.textureWrites + 1
end
function texture:SetTexCoord() end
function texture:SetVertexColor() end

local holder = {
    _msufShown = true,
    IsShown = function()
        holderShownReads = holderShownReads + 1
        return true
    end,
}
local portraitCfg = { enabled = true, render = "CLASS", classStyle = "BLIZZARD", border = { style = "NONE" } }
local frame = {
    unit = "target",
    _msufCoreVisible = true,
    _msufPortraitRuntimeCfg = portraitCfg,
    portrait = texture,
    MSUFPortraitHolder = holder,
    IsShown = function()
        frameShownReads = frameShownReads + 1
        return true
    end,
}

Portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
Check(timeReads == 0, "CLASS portrait touched 2D generation timing")
Check(mediaReads == 1 and texture.textureWrites == 1, "initial CLASS portrait was not resolved once")
Check(frameShownReads == 0 and holderShownReads == 0, "cached visible CLASS portrait called native IsShown")

Portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
Check(timeReads == 0, "steady CLASS portrait touched 2D generation timing")
Check(mediaReads == 1 and texture.textureWrites == 1, "unchanged CLASS portrait repeated media/texture work")

classToken = "MAGE"
Portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
Check(mediaReads == 2 and texture.textureWrites == 2, "CLASS change did not refresh portrait")

portraitCfg.render = "2D"
Portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
Check(timeReads == 1, "2D portrait lost target generation bump")
Check(portraitWrites == 1, "2D portrait lost target refresh")
Check(classReads >= 3, "CLASS identity was not checked on target changes")

portraitCfg.render = "CLASS"
classToken = SECRET
Portrait.Update(frame, "PLAYER_TARGET_CHANGED", "target")
Check(portraitWrites == 2, "secret class token did not use the safe unit-portrait fallback")

print("PASS portrait identity hotpath: CLASS skips 2D generation and unchanged media work")
