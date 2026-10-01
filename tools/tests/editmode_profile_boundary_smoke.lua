-- Profile switch, reset and import are one boundary for MSUF Edit Mode and the
-- Menu2 undo history (review F1, F5):
--   * the boundary closes an open MSUF Edit Mode session against the profile
--     it edited, so Cancel All after a switch can never write the old profile
--     into the new one;
--   * the Menu2 history is rebased onto the new profile, so Undo/Redo never
--     replay another profile's snapshot, even across a closed menu session;
--   * every restore path (Cancel All, history surface cancel, Undo, Redo,
--     session reset and the Edit Mode fallback stack) refuses a snapshot of
--     another profile, also when something swaps MSUF_DB past the boundary;
--   * a profile apply never pushes the stored Blizzard Edit Mode snapshot over
--     the live layout (review F5); only an import that carries it with the
--     opt-in switch on applies it, exactly once.
-- Real core and Options graphs through tools/tests/client_world.lua; only the
-- runtime fan-out targets of MSUF.ProfileRuntime.Apply are stubbed.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local World = assert(loadfile(root .. "/tools/tests/client_world.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
    return condition
end

local FANOUT = {
    "MSUF_ApplyMsufScale", "MSUF_TargetSoundDriver_ApplySetting", "MSUF_NSRTNicknames_ApplySetting",
    "MSUF_EllesmereEditMode_SetEnabled", "MSUF_Grid2EditMode_SetEnabled", "MSUF_DetailsEditMode_SetEnabled",
    "MSUF_DominosEditMode_SetEnabled", "MSUF_DandersEditMode_SetEnabled", "MSUF_BlizzardEditMode_SetEnabled",
    "MSUF_UFCore_NotifyConfigChanged", "MSUF_ApplyModules", "MSUF_GF_RebuildAll", "MSUF_ClassPower_Apply",
    "MSUF_ApplyPowerBarEmbedLayout_All", "MSUF_Castbars_OnSettingsChanged", "MSUF_ApplyAllCastbarsAndSync",
    "MSUF_UpdateAllFonts_Immediate", "MSUF_ApplyCurrentProfileGlobalUiScale", "MSUF_ForceReanchorAllUnitFrames_Once",
}

-- Reversible stand-in for the native codec: CBOR keeps a deep copy in a
-- registry, compression prefixes a byte, base64 is RFC 4648.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end
local function EncodeBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1, c2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
        local c3, c4 = math.floor(n / 64) % 64, n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end
local function DecodeBase64(text)
    if type(text) ~= "string" or #text % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local pad = select(2, chunk:gsub("=", ""))
        local n = 0
        for j = 1, 4 do
            local ch = chunk:sub(j, j)
            local v = ch == "=" and 0 or B64_INDEX[ch]
            if v == nil then return nil end
            n = n * 64 + v
        end
        out[#out + 1] = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256):sub(1, 3 - pad)
    end
    return table.concat(out)
end
local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, inner in pairs(value) do out[DeepCopy(key)] = DeepCopy(inner) end
    return out
end
local function InstallCodec(env)
    local registry = {}
    env.C_EncodingUtil = {
        SerializeCBOR = function(value) registry[#registry + 1] = DeepCopy(value); return "CBOR" .. #registry end,
        DeserializeCBOR = function(blob)
            local id = type(blob) == "string" and tonumber(blob:match("^CBOR(%d+)$"))
            return id and DeepCopy(registry[id]) or nil
        end,
        CompressString = function(plain) return "Z" .. plain end,
        DecompressString = function(packed)
            if type(packed) ~= "string" or packed:sub(1, 1) ~= "Z" then return nil end
            return packed:sub(2)
        end,
        EncodeBase64 = EncodeBase64,
        DecodeBase64 = DecodeBase64,
    }
end

local function Boot(flavor)
    local world = World.New(root, flavor)
    InstallCodec(world.env)
    world:Boot()
    local failure = world:FirstFailure()
    assert(not failure, flavor .. ": boot failed: " .. tostring(failure and failure.file) .. ": "
        .. tostring(failure and failure.message))
    local env, core = world.env, world.core
    for _, name in ipairs(FANOUT) do env[name] = function() end end
    core.UF.DisableBlizzardFrames = function() end
    -- The unit-frame engine has no unit data offline; its apply is out of scope.
    core.UF.Apply = function() return true end
    if core.SwingTimer then core.SwingTimer.Apply = function() end end
    local applied = { count = 0 }
    env.MSUF_BlizzardEditMode_ApplyProfileSnapshot = function() applied.count = applied.count + 1; return true end
    world.snapshotApplies = applied
    env.MSUF_InitProfiles()
    local history = assert(env.MSUF2, flavor .. ": Menu2 history missing")
    history.ApplyService.Flush = function() return true end
    return world, env, history
end

local function Profiles(env)
    return env.MSUF_GlobalDB.profiles
end

-- Two profiles with a marker on the player frame each, Default active.
local function Seed(env, flavor)
    local active = env.MSUF_ActiveProfile
    assert(env.MSUF_CopyProfile(active, "Second"), flavor .. ": profile copy failed")
    local a, b = Profiles(env)[active], Profiles(env).Second
    assert(a == env.MSUF_DB and a ~= b, flavor .. ": profile tables are not separate")
    a.player, b.player = a.player or {}, b.player or {}
    a.player.offsetX, b.player.offsetX = 111, 222
    return active, a, b
end

local function RunEditModeSwitch(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local first, a, b = Seed(env, flavor)
    local context = flavor .. " Edit Mode switch"
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    Check(EM2.Undo.BeginChange("unit", "player", "Move") == true, context .. ": undo transaction did not open")
    a.player.offsetX = 150
    EM2.Undo.CommitChange()
    Check(history.GetHistoryState().undoCount == 1, context .. ": the move was not recorded")

    Check(env.MSUF_SwitchProfile("Second") == true and env.MSUF_DB == b, context .. ": switch failed")
    world.widgets:RunTimers()
    Check(EM2.State.IsActive() ~= true, context .. ": the profile switch left MSUF Edit Mode open")
    Check(history.GetHistoryState().undoCount == 0 and history.GetHistoryState().redoCount == 0,
        context .. ": the profile switch kept the previous profile's undo history")
    EM2.State.CancelAll()
    history.Undo()
    world.widgets:RunTimers()
    Check(b.player.offsetX == 222, context .. ": Cancel All or Undo wrote the previous profile into the new one ("
        .. tostring(b.player.offsetX) .. ")")
    Check(a.player.offsetX == 150, context .. ": the edited profile lost its saved session edit")
    Check(world.snapshotApplies.count == 0, context .. ": a profile switch applied the stored Blizzard layout")
    Check(env.MSUF_SwitchProfile(first) == true, context .. ": switch back failed")
    Check(world.snapshotApplies.count == 0, context .. ": switching back applied the stored Blizzard layout")
end

-- Something swaps MSUF_DB without the boundary: every restore path refuses.
local function RunBypassedSwap(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local first, a, b = Seed(env, flavor)
    local context = flavor .. " bypassed swap"
    Check(EM2.State.Enter("player") == true, context .. ": Edit Mode did not open")
    world.widgets:RunTimers()
    EM2.Undo.BeginChange("unit", "player", "Move")
    a.player.offsetX = 160
    EM2.Undo.CommitChange()
    env.MSUF_ActiveProfile, env.MSUF_DB = "Second", b
    Check(history.Undo() ~= true and b.player.offsetX == 222,
        context .. ": Undo replayed the previous profile's snapshot into the new one")
    EM2.State.CancelAll()
    world.widgets:RunTimers()
    Check(EM2.State.IsActive() ~= true, context .. ": Cancel All did not close Edit Mode")
    Check(b.player.offsetX == 222, context .. ": Cancel All wrote the previous profile into the new one ("
        .. tostring(b.player.offsetX) .. ")")
    env.MSUF_ActiveProfile, env.MSUF_DB = first, a
end

-- A closed menu keeps its stacks; reopening on another profile must not undo.
local function RunMenuSessionSwitch(flavor)
    local world, env, history = Boot(flavor)
    local first, a, b = Seed(env, flavor)
    local context = flavor .. " menu session switch"
    Check(history.StartHistorySession("menu"), context .. ": menu history session did not start")
    Check(history.CaptureHistory("Width", "unit:player:width", function() a.player.offsetX = 170; return true end),
        context .. ": menu change was not captured")
    history.EndHistorySession("menu")
    Check(env.MSUF_SwitchProfile("Second") == true, context .. ": switch failed")
    Check(history.StartHistorySession("menu"), context .. ": menu history session did not restart")
    Check(history.Undo() ~= true, context .. ": Undo replayed a change of the previous profile")
    Check(b.player.offsetX == 222, context .. ": menu Undo wrote the previous profile into the new one ("
        .. tostring(b.player.offsetX) .. ")")
    Check(a.player.offsetX == 170, context .. ": the previous profile lost its change")
    history.EndHistorySession("menu")

    -- The rebase waits for combat to end; Undo in between must still refuse.
    Check(history.StartHistorySession("menu"), context .. ": menu session did not start on the second profile")
    Check(history.CaptureHistory("Width", "unit:player:width", function() b.player.offsetX = 230; return true end),
        context .. ": second profile change was not captured")
    world.widgets:SetCombat(true)
    Check(env.MSUF_SwitchProfile(first) == true, context .. ": switch in combat failed")
    world.widgets:SetCombat(false)
    Check(history.Undo() ~= true and a.player.offsetX == 170,
        context .. ": Undo after a combat-deferred switch replayed the other profile")
    Check(b.player.offsetX == 230, context .. ": the second profile lost its change")
    history.EndHistorySession("menu")
end

-- Import keeps the table and the name; the boundary still rebases history and
-- applies the Blizzard layout only when the string carries it with the switch on.
local function RunImport(flavor)
    local world, env, history = Boot(flavor)
    local _, a = Seed(env, flavor)
    local context = flavor .. " import"
    a.gameplay = { crosshairSize = 31 }
    local encoded = env.MSUF_ExportSelectionToString("gameplay")
    Check(type(encoded) == "string", context .. ": gameplay export failed")
    Check(history.StartHistorySession("menu"), context .. ": menu history session did not start")
    Check(history.CaptureHistory("Gameplay", "gameplay:crosshairSize", function() a.gameplay.crosshairSize = 7; return true end),
        context .. ": change before import was not captured")
    Check(env.MSUF_ImportFromString(encoded) == true and env.MSUF_DB == a, context .. ": import failed")
    Check(a.gameplay.crosshairSize == 31, context .. ": import did not apply")
    Check(history.Undo() ~= true and a.gameplay.crosshairSize == 31,
        context .. ": Undo replayed a snapshot from before the import")
    Check(world.snapshotApplies.count == 0, context .. ": an import without Blizzard data applied the stored layout")

    local guided = history.CaptureGuidedTourRestorePoint()
    a.gameplay.crosshairSize = 9
    Check(env.MSUF_ImportFromString(encoded) == true, context .. ": second import failed")
    a.gameplay.crosshairSize = 11
    Check(history.RestoreGuidedTourRestorePoint(guided) == true and a.gameplay.crosshairSize == 31,
        context .. ": the guided tour restore point no longer restores on its own profile")
    history.EndHistorySession("menu")

    -- Opt-in import with Blizzard data: applied exactly once, by the import
    -- itself; the runtime apply after it adds nothing. Without the opt-in the
    -- string's data is stripped and nothing is applied.
    a.general = a.general or {}
    a.general.blizzardEditModeSnapshot = { minimap = { point = "CENTER", x = 1, y = 2 } }
    env.MSUF_Profiles_SetExportBlizzardEditMode(true)
    local full = env.MSUF_ExportSelectionToString("all")
    env.MSUF_Profiles_SetExportBlizzardEditMode(false)
    env.MSUF_Profiles_SetImportBlizzardEditMode(true)
    local before = world.snapshotApplies.count
    Check(env.MSUF_ImportFromString(full) == true, context .. ": full opt-in import failed")
    Check(world.snapshotApplies.count == before + 1, context .. ": opt-in import applied the Blizzard layout "
        .. (world.snapshotApplies.count - before) .. " times")
    env.MSUF_Profiles_SetImportBlizzardEditMode(false)
    before = world.snapshotApplies.count
    Check(env.MSUF_ImportFromString(full) == true, context .. ": full import without opt-in failed")
    Check(world.snapshotApplies.count == before, context .. ": import without the opt-in applied the Blizzard layout")
end

-- Without the Menu2 history the Edit Mode fallback stack also refuses.
local function RunFallbackStack(flavor)
    local world, env, history = Boot(flavor)
    local EM2 = env.MSUF_EM2
    local first, a, b = Seed(env, flavor)
    local context = flavor .. " fallback undo"
    local saved = {}
    for _, name in ipairs({ "Undo", "Redo", "BeginHistoryTransaction", "PrepareHistoryChange",
        "CommitHistoryTransaction", "CancelHistoryTransaction", "GetHistoryState" }) do
        saved[name], history[name] = history[name], nil
    end
    EM2.Undo.BeforeChange("unit", "player")
    a.player.offsetX = 180
    Check(EM2.Undo.CanUndo() == true, context .. ": fallback stack recorded nothing")
    env.MSUF_ActiveProfile, env.MSUF_DB = "Second", b
    EM2.Undo.DoUndo()
    Check(b.player.offsetX == 222, context .. ": fallback Undo wrote the previous profile into the new one")
    Check(EM2.Undo.CanUndo() ~= true, context .. ": fallback stack kept another profile's entries")
    for name, fn in pairs(saved) do history[name] = fn end
    env.MSUF_ActiveProfile, env.MSUF_DB = first, a
end

for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    RunEditModeSwitch(flavor)
    RunBypassedSwap(flavor)
    RunMenuSessionSwitch(flavor)
    RunImport(flavor)
    RunFallbackStack(flavor)
end

if #failures > 0 then
    error("editmode_profile_boundary_smoke failed:\n  " .. table.concat(failures, "\n  "))
end
print("editmode_profile_boundary_smoke: ok (5 clients; switch, bypassed swap, menu session, import, fallback stack)")
