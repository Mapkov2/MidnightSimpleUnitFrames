-- Typed native output mutations. This helper is loaded only by negative probes, never by capture.
local Mutations = {}
local function Texture(r) return r.objectType == "Texture" or r.objectType == "MaskTexture" end
local function Font(r) return r.objectType == "FontString" end

local ACTIONS = {
    color = function(r)
        if r.objectType == "StatusBar" and r.color then r:SetStatusBarColor(0.031, 0.063, 0.127, 0.51) return true end
        if Texture(r) and r.vertexColor then r:SetVertexColor(0.031, 0.063, 0.127, 0.51) return true end
        if Font(r) and r.textColor then r:SetTextColor(0.031, 0.063, 0.127, 0.51) return true end
    end,
    position = function(r)
        local point = r.points[1]
        if point then r:SetPoint(point.point, point.relativeTo, point.relativePoint, point.x + 7, point.y - 3) return true end
    end,
    size = function(r) r:SetSize((r.width or 0) + 11, (r.height or 0) + 3) return true end,
    texcoord = function(r) if Texture(r) and r.texCoord then r:SetTexCoord(0.21, 0.73, 0.17, 0.81) return true end end,
    visibility = function(r) if r:IsShown() then r:Hide() return true end end,
    font = function(r)
        if Font(r) and r.fontPath then r:SetFont(r.fontPath, (r.fontSize or 12) + 4, "OUTLINE") return true end
    end,
    layer = function(r)
        if (Texture(r) or Font(r)) and r.drawLayer then r:SetDrawLayer("OVERLAY", 6) return true end
    end,
    texture = function(r)
        if Texture(r) and r.texture then r:SetTexture("Interface/Icons/INV_Misc_QuestionMark") return true end
    end,
    mask = function(r) if Texture(r) and #r.masks > 0 then r:RemoveMaskTexture(r.masks[1]) return true end end,
    value = function(r)
        if r.objectType == "StatusBar" and r.value ~= nil then r:SetValue(r.value + 0.125) return true end
    end,
    portrait = function(r, world)
        if Texture(r) and r.oraclePortrait then
            world.env.SetPortraitTexture(r, "pet", r.oraclePortrait.legacy)
            return true
        end
    end,
    text = function(r)
        if Font(r) and type(r.text) == "string" then r:SetText(r.text .. " changed") return true end
    end,
    alpha = function(r) r:SetAlpha(0.271) return true end,
    extra = function(r)
        if r.objectType == "Frame" or r.objectType == "Button" or r.objectType == "StatusBar" then
            local texture = r:CreateTexture()
            texture:SetColorTexture(1, 0, 1, 1)
            texture:Show()
            return true
        end
    end,
}

local function Priority(role, surface, property)
    if surface == "classpower" and role:match("^resources/class") then return 0 end
    if surface == "unit" and (property == "texcoord" or property == "mask") and role == "unit/portrait/tex" then return 0 end
    if surface == "castbar" and property == "texcoord" and role == "castbar/iconTexture" then return 0 end
    if role == surface or role:sub(1, #surface + 1) == surface .. "/" then return 1 end
    return 2
end

function Mutations.Apply(world, case, objects, actual, property, Regions)
    local mutate = assert(ACTIONS[property], "unknown mutation " .. property)
    local roles = Regions.Keys(objects)
    table.sort(roles, function(a, b)
        local pa, pb = Priority(a, case.surface, property), Priority(b, case.surface, property)
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    for _, role in ipairs(roles) do
        if actual[role].effectiveShown and actual[role].effectiveAlpha > 0 and mutate(objects[role], world) then return role end
    end
    error("mutation had no applicable native region: " .. property, 0)
end

return Mutations
