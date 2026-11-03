local root, flavor = assert(arg[1]), arg[2] or "Mainline"
local MenuWorld = dofile(root .. "/tools/tests/menu_core_world.lua")
local Open = dofile(root .. "/tools/tests/menu_l4_world.lua")
local mw = Open(root, flavor, { page = "home", clientScriptBindings = true, tocMetadata = true,
    beforeCore = function(w)
        MenuWorld.InstallNativeUnitInputs(w)
    end })
local M = mw.M
M.GetContentMetrics = function() return tonumber(arg[3]) or 1000, 900 end
local previousSpell = mw.world.env.C_Spell
mw.world.env.C_Spell = setmetatable({
    GetSpellInfo = function(id)
        if id == 123 or id == "Test spell" then return { spellID = 123, name = "Test spell" } end
        return previousSpell.GetSpellInfo(id)
    end,
    GetOverrideSpell = function(id) return id end,
    GetSpellPowerCost = function() return {{ type = 3, minCost = 40, cost = 40 }} end,
}, { __index = previousSpell })
mw.world.env.C_SpellBook = { IsSpellInSpellBook = function(id) return id == 123 end }
mw.world.env.Enum.SpellBookSpellBank = { Player = 0 }
local function Settle() for _ = 1, 20 do mw:RunTimers(1000) end end
assert(mw:Select("classpower") ~= false)
M.ClassPowerWorkspace.Select("extras")
Settle()
local section = assert(M.cache.classpower.sections.classpower_resource_marks)
M.Widgets.FocusCollapsibleSection(section, { scroll = false, flash = false })
Settle()
local function Control(key)
    local id = M.ControlMeta("classpower", "advanced", "resource_extras.marks." .. key).controlId
    local entry = assert(M.RuntimeControlCatalog.Get(id), "missing control " .. id)
    return entry.widget
end
Control("add"):Click()
Settle()
Control("mode")._msuf2OnValueChanged("SPELL")
Settle()
local spell = Control("spellID")
spell:SetText("Test spell")
spell:GetScript("OnEnterPressed")(spell)
Settle()
assert(M.EnsureDB().bars.resourceMarks[1].spellID == 123, "spell input did not store resolved ID")
assert(type(M.EnsureDB().bars.resourceMarks[1].spellID) == "number", "spell ID must persist as a number")
M.Undo()
Settle()
assert(M.EnsureDB().bars.resourceMarks[1].spellID ~= 123, "undo did not restore prior spell")
M.Redo()
Settle()
assert(M.EnsureDB().bars.resourceMarks[1].spellID == 123, "redo did not restore spell")
spell:SetText("99999999999999999999999999999999")
spell:GetScript("OnEnterPressed")(spell)
Settle()
assert(M.EnsureDB().bars.resourceMarks[1].spellID == 0, "invalid ID did not clear unavailable selection")
M.Undo()
Settle()
assert(M.EnsureDB().bars.resourceMarks[1].spellID == 123)
local captured
local env, public = mw.world.env, mw.world.core.PublicGlobals
local previousEncoding = env.C_EncodingUtil
env.C_EncodingUtil = {
    SerializeCBOR = function(value) captured = value return "cbor" end,
    CompressString = function(value) return value end,
    EncodeBase64 = function(value) return value end,
}
assert(type(public.MSUF_ExportSelectionToString("all")) == "string", "export failed")
env.C_EncodingUtil = previousEncoding
local snapshot = captured and (captured.payload and captured or captured.snapshot)
assert(snapshot and snapshot.payload.bars.resourceMarks[1].spellID == 123, "export lost spell ID")
M.EnsureDB().bars.resourceMarks[1].spellID = 321
local H = dofile(root .. "/tools/tests/profile_state_harness.lua")
local imported, why = public.MSUF_ImportFromString(H.Literal(snapshot))
assert(imported, tostring(why))
assert(M.EnsureDB().bars.resourceMarks[1].spellID == 123, "import lost spell ID")
assert(M.EnsureDB().bars.resourceMarks[1].mode == "SPELL", "import lost spell-cost source")
M.EnsureDB().bars.resourceMarks[1].mode = nil
MenuWorld.FireScript(Control("value"), "OnValueChanged", 500)
assert(M.EnsureDB().bars.resourceMarks[1].value == 100, "legacy missing mode must retain percentage cap")
assert(#mw.world.reported == 0, table.concat(mw.world.reported, "\n"))
print("resource_mark_spell_menu_smoke: passed " .. flavor)
