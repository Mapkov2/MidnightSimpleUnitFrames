local root = assert(arg[1]):gsub("\\", "/")
local function Run()
    local flavor, measure = arg[2] or "Mainline", arg[3] == "measure"
    local w = dofile(root .. "/tools/tests/health_tick_world.lua").New(root, flavor)
    local c, h, UF = w.core, w.h, w.UF
    local Pixel = c.PublicGlobals.MSUF_PixelLayoutRegion
    local count, counting = 0, false
    -- Count native-widget boundaries, including geometry calls outside health sinks.
    local methods = getmetatable(w.single).__index
    local originalMethods = {}
    for name, fn in pairs(methods) do originalMethods[name] = fn end
    if flavor == "Mainline" or flavor == "Forever" then
        methods.SetRoundLayoutToNearestPixel = function(self, value) self.roundLayout = value end
    end
    for key, fn in pairs(methods) do
        if type(fn) == "function" then
            methods[key] = function(...)
                if counting then count = count + 1 end
                return fn(...)
            end
        end
    end
    local function Bench(label, fn)
        collectgarbage("collect")
        collectgarbage("stop")
        local kb, vm = collectgarbage("count"), 0
        count, counting = 0, true
        debug.sethook(function() vm = vm + 1 end, "", 1)
        fn()
        debug.sethook()
        counting = false
        local delta = collectgarbage("count") - kb
        collectgarbage("restart")
        print(string.format("A2 %s %s vm=%d kb=%.3f native=%d", flavor, label, vm, delta, count))
        return vm, delta
    end
    local region = w.env.CreateFrame("Frame", nil, w.env.UIParent)
    Pixel(region)
    local vm = Bench("pixel-warm-x1000", function() for i = 1, 1000 do assert(Pixel(region) == region) end end)
    if not measure then assert(vm < 18000, "completed pixel region still visits setup") end
    Pixel(region, true)
    assert(not region._msufPixelLayoutEnabled, "logical owner retained native rounding")
    Pixel(region)
    assert(not region._msufPixelLayoutEnabled, "ordinary revisit removed explicit exclusion")
    local shape = { SetRoundLayoutToNearestPixel = function(self, v) self.rounded = v end,
        GetObjectType = function() return "MaskTexture" end }
    Pixel(shape)
    assert(not shape.rounded, "mask was rounded")
    local protected = { SetRoundLayoutToNearestPixel = function(self, v) self.rounded = v end,
        IsProtected = function() return true end, GetObjectType = function() return "Frame" end }
    h.widgets:SetCombat(true)
    Pixel(protected)
    assert(not protected.rounded and not protected._msufPixelLayoutTemplateVisited, "combat skip was marked complete")
    h.widgets:SetCombat(false)
    Pixel(protected)
    if flavor == "Mainline" or flavor == "Forever" then assert(protected.rounded) end

    -- A native geometry update may synchronously re-enter the same owner.
    if flavor == "Mainline" or flavor == "Forever" then
        local entered, walks = false, 0
        local reentrant = {
            GetObjectType = function() return "Frame" end,
            GetRegions = function() walks = walks + 1 end,
            SetRoundLayoutToNearestPixel = function(self)
                if not entered then entered = true Pixel(self) end
            end,
        }
        Pixel(reentrant)
        assert(walks == 1, "reentrant native rounding repeated a completed template walk")
    end

    local spec = UF.Config.GetSpec("target")
    local function Apply() UF.ApplySpec(w.single, spec, "MSUF_APPLY", true) end
    Apply()
    Bench("frame-apply", Apply)
    Bench("frame-apply-repeat", Apply)
    Bench("roster-20", function() h:SetRaid(20) h:Event("GROUP_ROSTER_UPDATE") h:RunTimers() end)
    Bench("roster-unchanged", function() h:Event("GROUP_ROSTER_UPDATE") h:RunTimers() end)
    assert(#h.eventErrors == 0, tostring(h.eventErrors[1]))
    assert(#h.violations == 0, tostring(h.violations[1]))
    for name in pairs(methods) do methods[name] = originalMethods[name] end
    print("PASS uf_pixel_layout_budget_smoke " .. flavor)
end
Run()
Run()
