local root=assert(arg[1])
local World=assert(loadfile(root.."/tools/tests/client_world.lua"))()
for _,flavor in ipairs({"Mainline","Forever","Vanilla","TBC","Mists"}) do
    local world=World.New(root,flavor):Boot()
    local failure=world:FirstFailure();assert(not failure,failure and failure.message)
    local env,ns=world.env,world.core
    local PA=assert(ns.PreviewAnimation)
    env.MSUF_EnsureDB(true)
    PA.enabled=true;PA.source="edit_mode"
    for _,unit in ipairs({"pet","pettarget"}) do
        local frame=env.CreateFrame("Frame",nil,env.UIParent);frame.MSUFUnitKey=unit;frame:Show()
        frame.MSUFSpec={power={enabled=false},prediction={enabled=false}}
        frame.hpBar=env.CreateFrame("StatusBar",nil,frame)
        frame.hpBar:SetMinMaxValues(0,100);frame.hpBar:SetValue(73)
        frame.targetPowerBar=env.CreateFrame("StatusBar",nil,frame)
        local power=frame.targetPowerBar;power:SetMinMaxValues(0,100);power:SetValue(41);power:Hide()
        assert(PA.ApplyUnitFrame(frame,1,unit))
        assert(not power:IsShown(),flavor.." "..unit..": disabled powerbar became visible during Edit Mode animation")
        frame.MSUFSpec.power.enabled=true
        assert(PA.ApplyUnitFrame(frame,1,unit) and power:IsShown(),"enabled powerbar did not animate")
        frame.MSUFSpec.power.enabled=false
        assert(PA.ApplyUnitFrame(frame,1,unit) and not power:IsShown(),"disabling a previously animated powerbar failed")
    end
    PA.enabled=false;PA.source=nil
    -- The menu renderer must follow the same configured pet/pet-target power
    -- flag while retaining independent synthetic values and dimensions.
    local methods=world.widgets.Methods
    for _,key in ipairs({"SetStartPoint","SetEndPoint","SetThickness","SetAutoFocus","SetMaxLetters","EnableKeyboard"}) do
        if not methods[key] then methods[key]=function() end end
    end
    env.C_Texture={GetAtlasInfo=function() return nil end}
    local Preview=assert(ns.UFPreview)
    local parent=env.CreateFrame("Frame",nil,env.UIParent);parent:SetSize(900,400)
    local panel=env.CreateFrame("Frame",nil,env.UIParent)
    local selected="pet";panel._msufGetCurrentKey=function() return selected end
    local box=Preview._BuildPreview(parent,panel,900,400);box:Show();box.canvas:SetSize(400,200)
    for _,unit in ipairs({"pet","pettarget"}) do
        selected=unit
        local conf=env.MSUF_DB[unit];conf.width=177;conf.height=43
        for _,on in ipairs({false,true,false}) do
            conf.showPowerBar=on;ns.UF.Config.Refresh();Preview.Refresh(box,"PET_PREVIEW_LIFECYCLE")
            assert(box.key==unit and box.mock.power:IsShown()==on,flavor.." "..unit..": menu configured power visibility mismatch")
            assert(ns.UF.Config.GetSpec(unit).width==177 and ns.UF.Config.GetSpec(unit).height==43,"pet dimensions failed compilation")
        end
    end

end
print("unit_preview_pet_lifecycle_smoke: OK (5 clients, Pet/Pet Target configured power visibility)")
