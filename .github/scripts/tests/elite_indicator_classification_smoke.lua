local root = arg and arg[1] or "."

local function Check(value, message)
    if not value then error(message or "check failed", 2) end
end

local function ReadSource(path)
    local file = assert(io.open(root .. "/" .. path, "rb"))
    local source = file:read("*a")
    file:close()
    return source:gsub("\r\n", "\n")
end

-- Runtime: one texture region follows all classifications at the shared
-- Elite Indicator position and uses Blizzard's current classification atlases.
do
    local classification = "elite"
    _G.issecretvalue = function() return false end
    _G.UnitClassification = function() return classification end
    _G.UnitLevel = function() return 80 end
    _G.UnitIsPlayer = function() return false end
    _G.CreateFrame = function() return {} end

    local elements = {}
    local UF = {
        Layers = {},
        elements = elements,
        FreshUnitState = function() return nil end,
        ReadUnitExistsCached = function() return true, true end,
        ReadUnitIsPlayerCached = function() return false, true end,
        RegisterElement = function(name, element) elements[name] = element end,
    }
    local MSUF = { UF = UF, Secrets = {} }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Status.lua"))(
        "MidnightSimpleUnitFrames", MSUF)

    local texture = { shown = false }
    function texture:SetShown(value) self.shown = value == true end
    function texture:SetAtlas(value) self.atlas = value end
    function texture:SetTexture(value) self.texture = value end
    function texture:SetTexCoord(...) self.texCoord = { ... } end

    local frame = { MSUFUnitKey = "target", eliteIcon = texture }
    local status = { elite = { enabled = true, style = "BLIZZARD" } }
    local update = assert(MSUF.UFStatusRuntime and MSUF.UFStatusRuntime.UpdateElite,
        "elite runtime updater missing")
    local cases = {
        elite = "nameplates-icon-elite-gold",
        worldboss = "nameplates-icon-elite-gold",
        rareelite = "nameplates-icon-elite-silver",
        rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
    }
    for state, atlas in pairs(cases) do
        classification = state
        update(frame, status)
        Check(texture.shown == true, state .. " classification did not show the shared indicator")
        Check(texture.atlas == atlas, state .. " classification used the wrong atlas")
    end
    Check(frame.eliteIcon == texture, "classification update replaced the shared Elite Indicator region")
end

-- Menu preview: the selected indicator remains visible independent of the
-- current live target and resolves the exact live/fallback classification.
do
    local MSUF = {
        UFPreview = { Model = {
            MakeFS = function() return {} end,
            FontColor = function() return 1, 1, 1 end,
        } },
    }
    assert(loadfile(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Status.lua"))(
        "MidnightSimpleUnitFrames_Options", MSUF)
    local Status = assert(MSUF.UFPreviewStatus, "unit preview status helpers missing")

    local texture = {}
    function texture:Show() self.shown = true end
    function texture:Hide() self.shown = false end
    function texture:SetVertexColor(...) self.vertex = { ... } end
    function texture:SetTexCoord(...) self.texCoord = { ... } end
    function texture:SetAtlas(value) self.atlas = value; self.texture = nil end
    function texture:SetTexture(value) self.texture = value; self.atlas = nil end
    local text = { Hide = function(self) self.shown = false end }
    local icon = { tex = texture, txt = text }
    local spec = {
        id = "elite",
        iconStyle = "eliteIconStyle",
        defaultIconStyle = "BLIZZARD",
        customIcon = "eliteIconCustomIcon",
    }
    local cases = {
        elite = "nameplates-icon-elite-gold",
        worldboss = "nameplates-icon-elite-gold",
        rareelite = "nameplates-icon-elite-silver",
        rare = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
    }
    for classification, atlas in pairs(cases) do
        Status.SetIconTexture(icon, spec, {}, {}, "target", { classification = classification },
            { style = "BLIZZARD" })
        Check(texture.atlas == atlas, classification .. " preview used the wrong atlas")
    end
    Status.SetIconTexture(icon, spec, {}, {}, "target", { classification = "normal" },
        { style = "BLIZZARD" })
    Check(texture.atlas == "nameplates-icon-elite-gold",
        "selected Elite Indicator preview disappeared instead of using its deterministic fallback")

end

local render = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_UnitPreview_Render.lua")
Check(not render:find('spec.id == "elite" and not data.elite', 1, true),
    "live target classification can still hide the selected Elite Indicator preview")

local section = ReadSource("MidnightSimpleUnitFrames_Options/Shell/Menu2/Pages/MSUF_Menu2_UnitStatusSection.lua")
for _, variant in ipairs({ '"ELITE"', '"RAREELITE"', '"RARE"' }) do
    Check(section:find('{ "elite", ' .. variant .. ' }', 1, true),
        variant .. " is missing from the Elite Indicator icon strip")
end
Check(not section:find("rareEliteIconOffset", 1, true) and not section:find("rareIconOffset", 1, true),
    "classification variants introduced separate positions instead of sharing Elite Indicator placement")

print("PASS elite indicator classifications: runtime and preview share one position with Elite/Rare Elite/Rare visuals")
