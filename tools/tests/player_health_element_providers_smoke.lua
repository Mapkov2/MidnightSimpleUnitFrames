-- Missing and wrong-shaped collaborators must fail at the real load boundary.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local World = dofile(root .. "/tools/tests/classpower_world.lua")
local ownerPath = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_PlayerHP.lua"
local count = 0
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local t = World.Start(root, flavor == "Forever" and "Mainline" or flavor, "WARRIOR", 1, World.PT.RAGE,
        { showClassPower = false }, { beforeLoad = function()
            MSUF_NS.Client.IsForever = flavor == "Forever"
            local factory = CreateFrame
            CreateFrame = setmetatable({}, { __call = function(_, ...) return factory(...) end })
        end })
    local ns = MSUF_NS
    local function Reject(tbl, key, expected, load, wrong)
        local original = tbl[key]
        for _, bad in ipairs({ false, wrong or {} }) do
            if bad == false then tbl[key] = nil else tbl[key] = bad end
            local ok, err = pcall(load or function() assert(loadfile(ownerPath))("MSUF", ns) end)
            tbl[key] = original
            assert(not ok and tostring(err):find(expected, 1, true),
                "unnamed/missing dependency failure: " .. expected .. " -> " .. tostring(err))
            count = count + 1
        end
    end
    for _, method in ipairs({ "RegisterElement", "AttachFrame", "ApplyElementToFrame", "SetFrameSpec", "attachedFrames" }) do
        Reject(ns.UF, method, "UF." .. method, nil, method == "attachedFrames" and 17 or nil)
    end
    for _, name in ipairs({ "MSUF_IsPlayerInCombat", "UnitAffectingCombat", "MSUF_GetFontPath", "MSUF_GetFontFlags",
        "MSUF_FontPathEquals", "MSUF_MarkFontApplyFailed", "MSUF_PixelLayoutRegion", "MSUF_UF_NormalizeClassPowerShape",
        "MSUF_UF_NormalizePlayerHPShape", "MSUF_UF_ShapeOutlineAlpha" }) do Reject(_G, name, name) end
    Reject(MSUF_CP_CONST, "BuilderRegistry", "MSUF_CP_CONST.BuilderRegistry")
    Reject(MSUF_CP_CORE_BUILDERS, "PLAYER_HP_VISUAL", "PLAYER_HP_VISUAL")
    Reject(MSUF_CP_CORE_BUILDERS, "PLAYER_HP_API", "PLAYER_HP_API")
    local function LoadController()
        __MSUF_ClassPower_Loaded = nil
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Controller.lua"))("MSUF", ns)
    end
    Reject(_G, "CreateFrame", "PlayerHP injected APIs.CreateFrame", LoadController)
    Reject(ns.UF, "PlayerHP", "UF.PlayerHP", LoadController)
    Reject(MSUF_CP_CORE_BUILDERS, "PLAYER_HP", "UF.PlayerHP binding", LoadController)
    Reject(ns.UF.PlayerHP, "ValidateBinding", "UF.PlayerHP", LoadController)
    t.module.Disable()
end
print("player_health_element_providers_smoke: OK (" .. count .. " named load-time counterexamples, five clients)")
