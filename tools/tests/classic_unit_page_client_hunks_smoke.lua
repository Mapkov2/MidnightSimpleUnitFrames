-- Vanilla, TBC and Mists load the Retail-named Unit page and status section
-- (Pages/MSUF_Menu2_Unit.lua, Pages/MSUF_Menu2_UnitStatusSection.lua). Their
-- Classic behaviour lives in small hunks gated on MSUF.Client facts read once at
-- load. This smoke loads both files under the real client model of every client
-- and pins each hunk where it applies and its absence on Midnight and WoW
-- Forever, so an override rebase that drops or widens one fails here.
local root = assert(arg[1], "repo root missing")
local MENU = root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/"

local function Check(ok, message)
    if not ok then error(message, 2) end
end

-- Widget stubs record every method call as "Method(args)" per object.
local function Recorder()
    local object = { calls = {}, scripts = {} }
    return setmetatable(object, { __index = function(_, key)
        if type(key) ~= "string" or not key:match("^%u") then return nil end
        return function(self, ...)
            local args = {}
            for i = 1, select("#", ...) do args[i] = tostring((select(i, ...))) end
            self.calls[#self.calls + 1] = key .. "(" .. table.concat(args, ",") .. ")"
            if key == "SetScript" then self.scripts[(...)] = select(2, ...) end
            if key == "Show" then self.hidden = false end
            if key == "Hide" then self.hidden = true end
            if key == "IsShown" then return self.hidden ~= true end
            if key == "CreateTexture" or key == "CreateFontString" then return Recorder() end
        end
    end })
end
local function Called(object, prefix)
    for _, call in ipairs(object.calls) do
        if call:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local createdFrames, arenaApplies, atlasQueries = {}, 0, {}
local function LoadClient(case)
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
    _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC, _G.WOW_PROJECT_MISTS_CLASSIC = 5, 19
    _G.WOW_PROJECT_ID = case.project
    _G.MAX_ARENA_ENEMIES = nil
    _G.GameEvent = case.forever and { RegisterCamelotEvents = function() end } or nil
    _G.C_AddOns = { GetAddOnMetadata = function(_, field) if field == "X-MSUF-Client" then return case.tag end end }
    _G.CreateFrame = nil
    local core = {}
    assert(loadfile(root .. "/MidnightSimpleUnitFrames/Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", core)
    return core.Client
end

local function LoadPages(client)
    _G.CreateFrame = function(_, _, parent)
        local frame = Recorder()
        frame.parent = parent
        createdFrames[#createdFrames + 1] = frame
        return frame
    end
    _G.C_Timer = { After = function() end, NewTimer = function() return { Cancel = function() end } end }
    _G.InCombatLockdown = function() return false end
    _G.UnitAffectingCombat = function() return false end
    _G.GameTooltip = Recorder()
    _G.C_Texture = { GetAtlasInfo = function(atlas)
        atlasQueries[#atlasQueries + 1] = atlas
        if atlas ~= "nameplates-icon-elite-silver" then return { width = 16, height = 16 } end
    end }
    _G.MSUF_ApplyArenaUnitframePreviewState = function() arenaApplies = arenaApplies + 1 end
    -- No CoreFrame global: the page must not depend on one (see step 2).
    _G.CoreFrame = nil
    -- arena4 is hidden: a five-slot client sees an incomplete preview, a three-slot one does not.
    for i = 1, 5 do
        _G["MSUF_arena" .. i] = Recorder()
        _G["MSUF_arena" .. i].hidden = i == 4
    end
    _G.MSUF2_ArenaUnitframePreviewActive = nil
    local ns = {
        Client = client,
        UF = { GetFrame = function() return nil end },
        ExportPublic = function() end,
        Translate = function(text) return text end,
        MSUF2 = {
            Widgets = { LabelAt = function() return Recorder() end },
            Theme = { colors = { accent = { 1, 1, 1, 1 } } },
            UnitSectionsShared = {},
        },
    }
    assert(loadfile(MENU .. "MSUF_Menu2_Support.lua"))("MidnightSimpleUnitFrames_Options", ns)
    local M = ns.MSUF2
    local db = { general = {} }
    M.EnsureDB = function() return db end
    M.GetUnitDB = function(unit) db[unit] = db[unit] or {}; return db[unit] end
    M.GetGeneralDB = function() return db.general end
    M.RequestUnitApply = function() end
    assert(loadfile(MENU .. "Pages/MSUF_Menu2_Unit.lua"))("MidnightSimpleUnitFrames_Options", ns)
    local file = assert(io.open(MENU .. "Pages/MSUF_Menu2_UnitStatusSection.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local status = assert(loadstring(source .. "\nreturn StatusSection", "@MSUF_Menu2_UnitStatusSection.lua"))(
        "MidnightSimpleUnitFrames_Options", ns)
    return M, M.UnitPage, status, db
end

-- Builds the status preview card for a unit and returns its icon holders.
local function PreviewCard(status, unit)
    local state = {
        previewCard = Recorder(), previewControlW = 300,
        BindStatusTestToggle = function() return Recorder() end,
        StatusPreviewButton = function() return Recorder() end,
    }
    status.PrepareIconResolvers(state, unit)
    local first = #createdFrames + 1
    status.BuildPreviewCard(state, unit)
    local strip, holders = createdFrames[first], {}
    for i = first + 1, #createdFrames do
        if createdFrames[i].parent == strip then holders[#holders + 1] = createdFrames[i] end
    end
    Check(#holders == 5, unit .. " preview card no longer builds five icon holders")
    return state, holders
end

local HAPPINESS_LABELS = { "Unhappy - 75% damage", "Content - 100% damage", "Happy - 125% damage" }
-- arenaSlots: the slots ArenaPreviewFramesVisible walks (Unit page ARENA_SLOTS).
local CLIENTS = {
    { name = "Vanilla", project = 2, tag = "Vanilla", classic = true, arenaTargets = 0, arenaSlots = 0, arenaResync = true, happiness = true },
    { name = "TBC", project = 5, tag = "TBC", classic = true, arenaTargets = 5, arenaSlots = 5, arenaResync = true, happiness = true },
    { name = "Mists", project = 19, tag = "Mists", classic = true, arenaTargets = 5, arenaSlots = 5, arenaResync = true, happiness = false },
    { name = "Midnight", project = 1, classic = false, arenaTargets = 3, arenaSlots = 3, arenaResync = false, happiness = false },
    { name = "Forever", project = 1, forever = true, classic = false, arenaTargets = 0, arenaSlots = 3, arenaResync = false, happiness = true },
}
local knownDefectClients = {}
for _, case in ipairs(CLIENTS) do
    local client = LoadClient(case)
    Check((client.Family == "Classic") == case.classic, case.name .. ": client family")
    local _, page, status, db = LoadPages(client)

    -- 1. Aura Copy To reaches every arena slot the client fields (Unit page ARENA_SLOTS).
    db.auras3 = { perUnit = { player = { marker = "player" } } }
    page.CopyUnitSettings("player", "arena", { auras = true })
    local reached = 0
    for i = 1, 6 do
        if type(db.auras3.perUnit["arena" .. i]) == "table" then reached = reached + 1 end
    end
    Check(reached == case.arenaTargets,
        case.name .. ": Aura Copy To Arena reached " .. reached .. " arena slots, expected " .. case.arenaTargets)

    -- 2. The Arena page preview re-syncs when a fielded slot is not shown.
    -- KNOWN DEFECT, left alone with the owner-deferred arena work: the repeat
    -- request reaches ArenaPreviewFramesVisible, which calls the global
    -- CoreFrame that no addon or Blizzard file defines (the other Menu2 files
    -- bind local CoreFrame = MSUF.UF.GetFrame). Every client that fields an
    -- arena slot raises there. This pin keeps the defect visible instead of
    -- stubbing it away; whoever fixes it deletes the pin and the stand-in below.
    arenaApplies = 0
    page.SetArenaPagePreviewActive(true)
    local afterActivate = arenaApplies
    local repeated, repeatError = pcall(page.SetArenaPagePreviewActive, true)
    if case.arenaSlots > 0 then
        Check(not repeated and tostring(repeatError):find("global 'CoreFrame'", 1, true),
            case.name .. ": the Arena page preview's CoreFrame defect changed (" .. tostring(repeatError)
                .. "); if it is fixed, drop this known-defect pin and the stand-in")
        knownDefectClients[#knownDefectClients + 1] = case.name
        -- Stand-in for the missing local binding, only so the slot count is
        -- still checked past the defect; MSUF.UF.GetFrame answers nil here too.
        _G.CoreFrame = function() return nil end
        page.SetArenaPagePreviewActive(true)
        _G.CoreFrame = nil
    else
        Check(repeated, case.name .. ": the Arena page preview fails without arena slots: " .. tostring(repeatError))
    end
    Check((arenaApplies > afterActivate) == case.arenaResync,
        case.name .. ": Arena page preview " .. (case.arenaResync and "must" or "must not")
            .. " re-sync with arena4 hidden")
    page.SetArenaPagePreviewActive(false)

    -- 3. Status preview icons: tooltips and mouse only on Classic.
    local happinessSpec = page.FindStatusSpec("pet", "statusPetHappiness")
    happinessSpec = happinessSpec and happinessSpec.value == "statusPetHappiness" and happinessSpec or nil
    Check((happinessSpec ~= nil) == case.happiness, case.name .. ": Pet Happiness selector presence")
    local petState, petHolders = PreviewCard(status, "pet")
    for _, holder in ipairs(petHolders) do
        Check(Called(holder, "EnableMouse(true)") == case.classic and (holder.scripts.OnEnter ~= nil) == case.classic,
            case.name .. ": status preview icons " .. (case.classic and "lost" or "gained") .. " their Classic tooltip")
    end
    if happinessSpec then
        petState.RefreshIconPreviewStrip(happinessSpec, true)
        for i = 1, 3 do
            local label = petHolders[i]._msufStatusPreviewLabel
            Check(label == (case.classic and HAPPINESS_LABELS[i] or nil),
                case.name .. ": Pet Happiness preview icon " .. i .. " label is " .. tostring(label))
            if case.classic then
                _G.GameTooltip.calls = {}
                petHolders[i].scripts.OnEnter(petHolders[i])
                Check(Called(_G.GameTooltip, "SetText(" .. HAPPINESS_LABELS[i] .. ","),
                    case.name .. ": Pet Happiness preview icon " .. i .. " shows no tooltip")
            end
        end
    end

    -- 4. Classic skips a preview atlas its client does not ship and draws the file texture.
    local eliteSpec = page.FindStatusSpec("target", "eliteicon")
    Check(eliteSpec and eliteSpec.value == "eliteicon", case.name .. ": Elite indicator missing on Target")
    local targetState, targetHolders = PreviewCard(status, "target")
    atlasQueries = {}
    targetState.RefreshIconPreviewStrip(eliteSpec, true)
    -- Holder 2 previews Rare Elite, whose atlas this stub client lacks; holder 1 (Elite) has its atlas.
    local silver, gold = targetHolders[2].tex, targetHolders[1].tex
    Check(Called(gold, "SetAtlas(nameplates-icon-elite-gold)"), case.name .. ": an existing preview atlas must still be used")
    Check(Called(silver, "SetAtlas(nameplates-icon-elite-silver)") ~= case.classic
        and Called(silver, "SetTexture(Interface\\TargetingFrame\\UI-TargetingFrame-Skull)") == case.classic,
        case.name .. ": a missing preview atlas must fall back to the file texture on Classic only")
    Check((#atlasQueries > 0) == case.classic,
        case.name .. ": GetAtlasInfo must be asked on Classic only, asked " .. #atlasQueries .. " times")
end

print("classic_unit_page_client_hunks_smoke: ok (" .. #CLIENTS .. " clients; known defect, undefined CoreFrame in the Arena page preview re-check on "
    .. table.concat(knownDefectClients, ", ") .. ")")
