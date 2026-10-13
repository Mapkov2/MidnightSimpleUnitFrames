-- Existing public signatures see live geometry, even without a menu revision write.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local MenuWorld = assert(loadfile(root .. "/tools/tests/menu_core_world.lua"))()
local mw = MenuWorld.Open(root, "Mainline", { page = "home", keepFlush = true })
local env, castbars = mw.env, mw.core.Castbars
local Config = castbars.Config
local general = env.MSUF_DB.general
general.arenaCastbarDetached, general.bossCastbarDetached = true, true
general.arenaCastbarOffsetX, general.bossCastbarOffsetX = 0, 0
env.MSUF_Castbars_OnSettingsChanged("public geometry")
env.MSUF_ApplyAllCastbarsAndSync()
local failures, cases = {}, 0
local function Check(label, fn)
    cases = cases + 1
    local ok, err = pcall(fn)
    if not ok then failures[#failures + 1] = label .. ": " .. tostring(err) end
end
local function X(frame) local _, _, _, x = frame:GetPoint(1) return x end
for _, kind in ipairs({ "arena", "boss" }) do
    local bars = assert(env[kind == "arena" and "MSUF_ArenaCastbars" or "MSUF_BossCastbars"])
    local apply = env[kind == "arena" and "MSUF_ApplyArenaCastbarPositionSetting" or "MSUF_ApplyBossCastbarPositionSetting"]
    local key, frame = kind .. "CastbarOffsetX", assert(bars[2])
    Check(kind .. " original public oracle", function()
        local x = X(frame)
        general[key] = 40
        apply(nil, true, true)
        assert(X(frame) == x + 40, "bar 2 ignored X=0->40")
    end)
    for _, geometryOnly in ipairs({ true, false }) do
        local label = kind .. (geometryOnly and " geometry" or " normal")
        apply(false, true)
        Config.Read()
        Check(label .. " repeated/no-op", function()
            local count, compile = 0, Config.Compile
            Config.Compile = function(...) count = count + 1 return compile(...) end
            local setPoint, points = frame.SetPoint, 0
            frame.SetPoint = function(...) points = points + 1 return setPoint(...) end
            local ok, err = pcall(function()
                local x = X(frame)
                general[key] = general[key] + 20
                apply(false, true, geometryOnly)
                assert(X(frame) == x + 20, "changed setting ignored")
                local changed = points
                apply(false, true, geometryOnly)
                apply(false, true, geometryOnly)
                assert(points == changed, "unchanged geometry repeated native SetPoint")
                assert(count == 0, "position-only apply compiled eagerly: " .. count)
                Config.Read()
                assert(count == (geometryOnly and 0 or 1), "repeated applies caused compile fanout: " .. count)
            end)
            Config.Compile, frame.SetPoint = compile, setPoint
            assert(ok, err)
        end)
        Check(label .. " error recovery", function()
            local setPoint = frame.SetPoint
            frame.SetPoint = function() error("anchor failure") end
            general[key] = general[key] + 10
            local ok, err = pcall(apply, false, true, geometryOnly)
            frame.SetPoint = setPoint
            assert(not ok and tostring(err):find("anchor failure", 1, true), "anchor error did not escape")
            local expected = general[key]
            general[key] = expected + 10
            apply(false, true, geometryOnly)
            assert(X(frame) == general[key], "error poisoned next public apply")
        end)
        Check(label .. " reentrant apply", function()
            local first, setPoint, entered = bars[1], bars[1].SetPoint, false
            first.SetPoint = function(self, ...)
                setPoint(self, ...)
                if not entered then
                    entered = true
                    general[key] = general[key] + 10
                    apply(false, true, geometryOnly)
                end
            end
            general[key] = general[key] + 10
            local ok, err = pcall(apply, false, true, geometryOnly)
            first.SetPoint = setPoint
            assert(ok, err)
            assert(entered and X(frame) == general[key], "nested apply lost newer geometry")
        end)
    end
    Check(kind .. " live drag and replaced profile tables", function()
        local x = X(frame)
        general[key] = general[key] + 10
        frame:UpdateAnchorBase()
        assert(X(frame) == x + 10, "drag anchor kept old setting")
        local replacement = {}
        for key, value in pairs(general) do replacement[key] = value end
        replacement[key] = replacement[key] + 10
        env.MSUF_DB.general, general = replacement, replacement
        apply(nil, true, true)
        assert(X(frame) == general[key], "geometry retained replaced profile table")
    end)
    Check(kind .. " size, row layout and attachment", function()
        general[kind .. "CastbarWidth"] = 280
        general[kind .. "CastbarHeight"] = 22
        general[kind .. "CastbarOffsetY"] = 17
        local unitDB = {}
        for key, value in pairs(env.MSUF_DB[kind]) do unitDB[key] = value end
        unitDB.bossLayoutMode, unitDB.width, unitDB.height, unitDB.spacing = "HORIZONTAL_RIGHT", 200, 30, -42
        env.MSUF_DB[kind] = unitDB
        apply(nil, true, true)
        local _, _, _, x, y = frame:GetPoint(1)
        assert(x == general[key] + 212 and y == 17, "replaced unit row settings ignored")
        assert(frame:GetWidth() == 280 and frame:GetHeight() == 22, "live size ignored")
        general[kind .. "CastbarDetached"] = false
        apply(nil, true, true)
        local point = frame:GetPoint(1)
        assert(point ~= "CENTER", "live attachment ignored")
        general[kind .. "CastbarDetached"] = true
    end)
end
for _, failure in ipairs(failures) do io.stderr:write("FAIL ", failure, "\n") end
assert(#failures == 0, #failures .. " public geometry failures")
print("castbar pool public geometry smoke: ok (" .. cases .. " cases)")
