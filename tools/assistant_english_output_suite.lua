_G = _G or _ENV

local tests = {
    "tools/assistant_output_english_audit.lua",
    "tools/assistant_command_surface_output_audit.lua",
    "tools/assistant_router_conversation_output_audit.lua",
    "tools/assistant_dialog_output_audit.lua",
    "tools/assistant_explanations_output_audit.lua",
    "tools/assistant_followup_surface_output_audit.lua",
    "tools/assistant_workflow_output_audit.lua",
    "tools/assistant_guided_setup_output_audit.lua",
    "tools/assistant_undo_output_audit.lua",
    "tools/assistant_history_output_english_audit.lua",
    "tools/assistant_nomatch_output_english_audit.lua",
    "tools/assistant_combat_smoke.lua",
    "tools/assistant_parse_metadata_english_audit.lua",
    "tools/assistant_aura_output_audit.lua",
    "tools/assistant_action_output_english_audit.lua",
    "tools/assistant_setting_search_output_english_audit.lua",
    "tools/assistant_registry_label_language_audit.lua",
    "tools/assistant_registry_metadata_english_audit.lua",
    "tools/assistant_value_display_english_audit.lua",
    "tools/assistant_aura_registry_coverage_audit.lua",
    "tools/assistant_locale_output_audit.lua",
    "tools/assistant_locale_action_output_audit.lua",
    "tools/assistant_visible_language_static_audit.lua",
}

if os.getenv("MSUF_ENGLISH_SUITE_FULL") == "1" then
    tests[#tests + 1] = "tools/assistant_real_prompt_output_audit.lua"
end

local function exists(path)
    local handle = io.open(path, "r")
    if handle then handle:close(); return true end
    return false
end

local function quote(path)
    return '"' .. tostring(path):gsub('"', '\\"') .. '"'
end

local bomRunner = "tools/lua51_bom_runner.lua"
assert(exists(bomRunner), "missing Lua 5.1 BOM runner: " .. tostring(bomRunner))

local failed = {}
for _, path in ipairs(tests) do
    assert(exists(path), "missing English output audit: " .. tostring(path))
    io.write("assistant_english_output_suite: run " .. tostring(path) .. "\n")
    io.flush()
    local ok, why, code = os.execute("lua " .. quote(bomRunner) .. " " .. quote(path))
    if ok ~= true and ok ~= 0 then
        failed[#failed + 1] = tostring(path) .. " (" .. tostring(why) .. " " .. tostring(code) .. ")"
    elseif ok == 0 then
        -- Lua 5.1 can return a numeric shell status.
    end
end

if #failed > 0 then
    io.stderr:write("assistant_english_output_suite failures: " .. tostring(#failed) .. "\n")
    for i = 1, #failed do io.stderr:write(failed[i] .. "\n") end
    os.exit(1)
end

io.write("assistant_english_output_suite: ok audits=" .. tostring(#tests) .. "\n")
