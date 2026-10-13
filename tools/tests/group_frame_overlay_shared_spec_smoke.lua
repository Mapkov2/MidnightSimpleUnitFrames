-- Runtime, Edit Mode samples and Menu2 consume one binding overlay.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local flavor = arg[2] or "Mainline"
local h = dofile(root .. "/tools/tests/group_header_world.lua").New(root, flavor)
local GF = h.GF
assert(type(GF.ComputeFrameOverlay) == "function", "missing shared frame-overlay provider")
GF.EnsureDB()
local conf = GF.GetConf("raid")
conf.nameBarEnabled, conf.nameBarHeight, conf.height, conf.powerHeight = true, 18, 20, 8
conf.showPowerText, conf.powerShowHealer, conf.powerShowDamager = true, true, false
GF.InvalidateCompiledSpecs("raid")
local base = GF.CompileSpec("raid")
local oldHeight, oldInset, oldNameY = base.group.nameBarHeight, base.health.topInset, base.text.nameY
local metrics = { base = base, conf = conf, width = base.width, height = base.height }
local healer = GF.ComputeFrameOverlay("raid", "HEALER", metrics)
assert(healer.power.enabled and healer.power.height > 0 and healer.showPowerText, "healer power overlay lost")
assert(healer.status.roleValue == "HEALER", "synthetic role lost")
assert(rawget(healer, "font") == nil and rawget(healer.power, "texture") == nil, "frame data was shallow-copied")
assert(base.group.nameBarHeight == oldHeight and base.health.topInset == oldInset and base.text.nameY == oldNameY,
    "overlay wrote shared scope geometry")
local power, status, group, health, text = healer.power, healer.status, healer.group, healer.health, healer.text
assert(GF.ComputeFrameOverlay("raid", "HEALER", metrics) == healer, "stable binding replaced its spec")
local dps = GF.ComputeFrameOverlay("raid", "DAMAGER", metrics)
assert(dps == healer and not dps.power.enabled and not dps.showPowerText, "role shift retained healer power")
assert(dps.power == power and dps.status == status and dps.group == group and dps.health == health and dps.text == text,
    "role shift allocated overlay tables")
local independent = GF.ComputeFrameOverlay("raid", "HEALER", { base = base, conf = conf, height = 10 })
assert(independent ~= dps and independent.power ~= power and independent.group ~= group, "bindings share writable overlays")
assert(independent.health.topInset == math.max(0, 10 - independent.power.height - 1), "Priority dimensions ignored")

-- Compile only at a scope boundary; targeted font/color/border refreshes keep
-- the binding and the compiler base identities while inheriting fresh values.
local frame = {}
local live = GF.CompileSpec("raid", frame, "raid3")
conf.nameFontSize = 19
assert(GF.RefreshCompiledSpecDomains("raid", GF.DIRTY_FONT), "font domain refresh rejected")
assert(GF.CompileSpec("raid", frame, "raid3") == live and live.nameFontSize == 19, "font refresh missed inherited scope data")
assert(GF.CompileSpec("raid") == base, "targeted refresh replaced the compiled base")
assert(frame._msufGFTextLayoutRevision == nil and frame._msufGFTextColorRevision == nil
    and frame._msufGFPowerVisualRevision == nil and frame._msufGFBorderVisualRevision == nil, "redundant binding revisions remain")

-- Exercise the actual Menu2 adapter with the same metrics and synthetic role.
local file = assert(io.open(root .. "/MidnightSimpleUnitFrames_Options/Shell/Menu2/Preview/MSUF_Menu2_GroupPreview_Native.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local adapter = assert(source:match("(local previewSpecSlots = {}.-)\nlocal function PageForGFSection"), "Menu2 adapter moved")
local factory = assert(loadstring("return function(MSUF,CurrentScope,Conf,PreviewRole)\n" .. adapter .. "\nreturn CompiledSpec end"))()
local menu = factory(h.core, function() return "raid" end, function() return conf end, function() return "HEALER" end)
local sample = menu("raid")
local direct = GF.ComputeFrameOverlay("raid", "HEALER", { base = base, conf = conf })
assert(sample.power.height == direct.power.height and sample.health.topInset == direct.health.topInset
    and sample.text.nameY == direct.text.nameY and sample.status.roleValue == direct.status.roleValue,
    "Menu2 and runtime overlays diverged")
assert(menu("raid") == sample, "Menu2 repaint replaced its binding")
print("group_frame_overlay_shared_spec_smoke: ok (" .. flavor .. ": shared scope, independent reusable overlays, Menu2 parity)")
