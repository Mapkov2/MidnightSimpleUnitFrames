-- A logs out with one profile, B logs in with another: every startup consumer
-- sees B's bound alias, including the first NumberFormat refresh.
local root = assert(arg[1], "repository root required"):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local Corpus = assert(loadfile(root .. "/tools/profile_corpus_golden.lua"))()
for _, client in ipairs({ "Mainline", "Vanilla", "TBC", "Mists" }) do
    local path = root .. "/MidnightSimpleUnitFrames/MidnightSimpleUnitFrames_" .. client .. ".toc"
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    local variables = assert(text:match("## SavedVariables:%s*([^\r\n]+)"), client .. ": SavedVariables declaration missing")
    assert(variables == "MSUF_DB, MSUF_GlobalDB", client .. ": legacy profile is not declared for migration")
end
local function New(character)
    return Corpus.NewWorld(root, flavor, character)
end
local function Profile(width, style)
    return { _msufProfileSchema = 600, general = { numberAbbrevStyle = style }, player = { width = width } }
end
local saved = {
    MSUF_GlobalDB = {
        profiles = { A = Profile(181, "GAME"), B = Profile(282, "COMPACT") },
        char = { ["A-Realm"] = { activeProfile = "A" }, ["B-Realm"] = { activeProfile = "B" } },
    },
}
local a = New("A-Realm")
Corpus.Login(a, Corpus.Copy(saved))
assert(a.env.MSUF_DB == a.env.MSUF_GlobalDB.profiles.A, "A did not bind its profile")
local logout = { MSUF_GlobalDB = Corpus.Copy(a.env.MSUF_GlobalDB), MSUF_DB = Corpus.Copy(a.env.MSUF_DB) }
local b = New("B-Realm")
local clearRetired = b.core.ClearRetiredAssistantData
b.core.ClearRetiredAssistantData = function(...)
    if b.core.Lifecycle.Phase == "migrate" then
        assert(rawget(b.env, "MSUF_DB") == nil, "migration consumers could still read A through the runtime alias")
    end
    return clearRetired(...)
end
local reads = 0
local refresh = b.core.NumberFormat.Refresh
b.core.NumberFormat.Refresh = function(...)
    reads = reads + 1
    assert(b.env.MSUF_DB == b.env.MSUF_GlobalDB.profiles.B,
        "NumberFormat read the previous character's alias before binding")
    return refresh(...)
end
local observer = b.env.CreateFrame("Frame")
observer:RegisterEvent("ADDON_LOADED")
observer:RegisterEvent("PLAYER_LOGIN")
observer:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "MidnightSimpleUnitFrames" then return end
    assert(b.env.MSUF_DB == b.env.MSUF_GlobalDB.profiles.B,
        event .. " consumer saw A before B's explicit binding")
end)
b:LoadSavedVariables("MidnightSimpleUnitFrames", logout)
assert(b.env.MSUF_DB == b.env.MSUF_GlobalDB.profiles.B, "ADDON_LOADED did not explicitly bind B")
Corpus.Login(b, {})
assert(reads > 0 and b.env.MSUF_DB.player.width == 282, "B's effective profile changed")
assert(b.core.Lifecycle.Bound and b.core.Lifecycle.Phase == "running", "the ordered login lifecycle did not finish")

-- Stored profiles win over a divergent standalone copy, exactly as in 6.50.
-- The one-time migration must not create a new permanent archive key.
local divergent = Corpus.Copy(logout)
divergent.MSUF_DB.player.width = 999
local recovery = New("B-Realm")
recovery:LoadSavedVariables("MidnightSimpleUnitFrames", divergent)
assert(recovery.env.MSUF_DB.player.width == 282, "standalone edits overrode the stored character profile")
assert(recovery.env.MSUF_GlobalDB.legacyStandaloneProfiles == nil, "migration retained an unrequested standalone archive")

-- The old texture callback has not run: the migration belongs to ADDON_LOADED.
local textures = New("B-Realm")
local textureSaved = Corpus.Copy(logout)
textureSaved.MSUF_GlobalDB.profiles.B.general.barTexture = "Midnight Smooth v2"
textureSaved.MSUF_GlobalDB.profiles.B.general.castbarTexture = "MSUF Flat"
textures:LoadSavedVariables("MidnightSimpleUnitFrames", textureSaved)
assert(textures.env.MSUF_DB.general.barTexture == "MSUF Smooth v2", "bar rename waited for a file-load timer")
assert(textures.env.MSUF_DB.general.castbarTexture == "Solid", "legacy flat castbar did not migrate")
assert(textures.env.MSUF_GlobalDB.profiles.A.general.barTexture ~= "MSUF Smooth v2", "the migration changed A")

-- With only the account SavedVariable, old install evidence and bindings survive.
local accountOnly = New("B-Realm")
local accountRefresh = accountOnly.core.NumberFormat.Refresh
accountOnly.core.NumberFormat.Refresh = function(...)
    assert(accountOnly.env.MSUF_DB == accountOnly.env.MSUF_GlobalDB.profiles.B, "account-only startup read A's profile")
    return accountRefresh(...)
end
accountOnly:LoadSavedVariables("MidnightSimpleUnitFrames", { MSUF_GlobalDB = Corpus.Copy(a.env.MSUF_GlobalDB) })
assert(accountOnly.env.MSUF_DB == accountOnly.env.MSUF_GlobalDB.profiles.B, "account-only login lost B's binding")
assert(accountOnly.core.FirstLoad6:GetInstallKind() == "upgrade", "account-only data was mistaken for a fresh install")
local pre6 = New("B-Realm")
pre6:LoadSavedVariables("MidnightSimpleUnitFrames", {
    MSUF_GlobalDB = { profiles = { Old = { player = { width = 77 } } }, char = { ["B-Realm"] = { activeProfile = "Old" } } },
})
assert(pre6.core.FirstLoad6:GetDetection().legacyProfile, "5.x account-only detection was lost")
assert(pre6.env.MSUF_GlobalDB.ignoredPre6Profiles.Old.player.width == 77, "5.x archive changed")
assert(pre6.env.MSUF_ActiveProfile == "Default", "5.x archive did not rebind to Default")

local legacyOnly = New("B-Realm")
local standalone = Profile(333, "GAME")
standalone.general.barTexture = "Midnight Charcoal"
legacyOnly:LoadSavedVariables("MidnightSimpleUnitFrames", { MSUF_DB = standalone })
assert(legacyOnly.env.MSUF_DB.player.width == 333, "standalone-only 6.x edits were not seeded into Default")
assert(legacyOnly.env.MSUF_DB.general.barTexture == "MSUF Charcoal", "standalone-only bar texture did not migrate")
local missing = New("B-Realm")
local missingSaved = Corpus.Copy(logout)
missingSaved.MSUF_GlobalDB.char["B-Realm"].activeProfile = "Missing"
missingSaved.MSUF_GlobalDB.profiles.Default = Profile(444, "GAME")
missingSaved.MSUF_GlobalDB.profiles.Default.general.barTexture = "Midnight Smoother"
missing:LoadSavedVariables("MidnightSimpleUnitFrames", missingSaved)
assert(missing.env.MSUF_DB.player.width == 444 and missing.env.MSUF_ActiveProfile == "Missing", "missing-profile donor changed")
assert(missing.env.MSUF_DB.general.barTexture == "MSUF Smoother", "missing-profile donor's texture did not migrate")
assert(missing.env.MSUF_GlobalDB.profiles.Default.general.barTexture == "Midnight Smoother", "the donor profile was mutated")
print("profile_binding_before_consumers_smoke: ok (" .. flavor .. ")")
