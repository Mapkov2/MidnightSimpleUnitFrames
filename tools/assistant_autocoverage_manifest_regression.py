from __future__ import annotations

import base64
import datetime as dt
import pathlib
import re
import subprocess
import sys
import zlib

import cbor2


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULTS_PATH = ROOT / "MidnightSimpleUnitFrames" / "State" / "MSUF_Defaults.lua"
MANIFEST_PATH = (
    ROOT
    / "MidnightSimpleUnitFrames_Assistant"
    / "Assistant"
    / "MSUF_AssistantRegistry_AutoCoverage_Manifest.lua"
)
WRITE = sys.argv[1:] == ["--write"]
if sys.argv[1:] and not WRITE:
    raise SystemExit("usage: assistant_autocoverage_manifest_regression.py [--write]")


def decode(value):
    if isinstance(value, bytes):
        return value.decode("utf-8")
    if isinstance(value, dict):
        return {decode(key): decode(item) for key, item in value.items()}
    if isinstance(value, list):
        return [decode(item) for item in value]
    return value


def lua_literal(value) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        escaped = (
            value.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\r", "\\r")
            .replace("\n", "\\n")
        )
        return f'"{escaped}"'
    if isinstance(value, list):
        return "{" + ",".join(lua_literal(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(
            f"[{lua_literal(key)}]={lua_literal(item)}" for key, item in value.items()
        ) + "}"
    raise TypeError(f"unsupported decoded value: {type(value)!r}")


defaults_source = DEFAULTS_PATH.read_text(encoding="utf-8-sig")
match = re.search(
    r"local MSUF_FACTORY_DEFAULT_PROFILE_COMPACT = \[\[MSUF3:(.*?)\]\]",
    defaults_source,
    re.DOTALL,
)
if not match:
    raise SystemExit("factory MSUF3 payload not found")
decoded = decode(cbor2.loads(zlib.decompress(base64.b64decode(match.group(1).strip()), -15)))

lua = f"""
local emitGenerated = {"true" if WRITE else "false"}
local decoded = {lua_literal(decoded)}
_G = _G or _ENV
_G.PowerBarColor = {{}}
_G.Enum = {{ CompressionMethod = {{ Deflate = 1 }} }}
_G.C_EncodingUtil = {{
    DecodeBase64 = function() return "blob" end,
    DeserializeCBOR = function() return decoded end,
    DecompressString = function() return "plain" end,
}}

local defaultsNS = {{}}
assert(loadfile({lua_literal(str(DEFAULTS_PATH))}))("MidnightSimpleUnitFrames", defaultsNS)
_G.MSUF_DB = assert(_G.MSUF_CreateFactoryDefaultProfile())
assert(_G.MSUF_EnsureDB)(true)

local manifestNS = {{}}
assert(loadfile({lua_literal(str(MANIFEST_PATH))}))("MidnightSimpleUnitFrames_Assistant", manifestNS)
local manifest = assert(manifestNS.Assistant.AutoCoverageManifest)
local scopes = {{
    "bars", "boss", "focus", "focustarget", "gameplay", "general",
    "gf_mythicraid", "gf_party", "gf_raid", "pet", "player", "target", "targettarget",
}}

local function isScalar(value)
    local kind = type(value)
    return kind == "boolean" or kind == "number" or kind == "string"
end

local function sortedStringKeys(root)
    local keys = {{}}
    if type(root) ~= "table" then return keys end
    for key in pairs(root) do
        if type(key) == "string" and key ~= "" and key:sub(1, 1) ~= "_" and not key:match("^%d+$") then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function flatten(root)
    local out, active = {{}}, {{}}
    local function walk(node, prefix, depth)
        if type(node) ~= "table" or active[node] or depth > 8 then return end
        active[node] = true
        local keys = sortedStringKeys(node)
        for i = 1, #keys do
            local key = keys[i]
            local path = prefix and (prefix .. "." .. key) or key
            local value = node[key]
            if type(value) == "table" then
                walk(value, path, depth + 1)
            elseif isScalar(value) then
                out[path] = value
            end
        end
        active[node] = nil
    end
    walk(root, nil, 1)
    return out
end

-- AutoCoverage's shipped manifest is a lean fallback for scalar settings that
-- can be absent from a live profile table. Nested public controls are covered
-- by explicit registry/catalog metadata; copying every nested profile scalar
-- here would eagerly materialize thousands of internal fallback settings.
local function topLevelScalars(root)
    local out = {{}}
    local keys = sortedStringKeys(root)
    for i = 1, #keys do
        local key, value = keys[i], root[keys[i]]
        if isScalar(value) then out[key] = value end
    end
    return out
end

local expectedByScope, expectedTotal = {{}}, 0
for i = 1, #scopes do
    local scope = scopes[i]
    local expected = topLevelScalars(assert(_G.MSUF_DB[scope], "factory profile omitted scope " .. scope))
    expectedByScope[scope] = expected
    for _ in pairs(expected) do expectedTotal = expectedTotal + 1 end
end

local listed, required = {{}}, {{}}
for i = 1, #scopes do required[scopes[i]] = true end
for _, scope in ipairs(assert(manifest.requiredScopes)) do
    assert(required[scope], "unexpected required manifest scope: " .. tostring(scope))
    assert(not listed[scope], "duplicate required manifest scope: " .. tostring(scope))
    listed[scope] = true
end

local mismatches, actualTotal = {{}}, 0
for i = 1, #scopes do
    local scope = scopes[i]
    if not listed[scope] then mismatches[#mismatches + 1] = "required scope metadata omitted " .. scope end
    local expected = expectedByScope[scope]
    local actualRoot = type(manifest.defaults) == "table" and manifest.defaults[scope] or nil
    local actual = flatten(actualRoot)
    for key, value in pairs(expected) do
        local actualValue = actual[key]
        if not isScalar(actualValue) then
            mismatches[#mismatches + 1] = scope .. "." .. key .. " omitted"
        elseif type(actualValue) ~= type(value) then
            mismatches[#mismatches + 1] = scope .. "." .. key .. " type mismatch"
        elseif actualValue ~= value then
            mismatches[#mismatches + 1] = scope .. "." .. key .. " value mismatch expected="
                .. string.format("%q", tostring(value)) .. " actual=" .. string.format("%q", tostring(actualValue))
        end
    end
    for key in pairs(actual) do
        actualTotal = actualTotal + 1
        if not isScalar(expected[key]) then mismatches[#mismatches + 1] = scope .. "." .. key .. " stale" end
    end
end
if tonumber(manifest.scalarCount) ~= actualTotal then
    mismatches[#mismatches + 1] = ("declared scalar count mismatch declared=%s actual=%d")
        :format(tostring(manifest.scalarCount), actualTotal)
end
if expectedTotal ~= actualTotal then
    mismatches[#mismatches + 1] = ("factory scalar count mismatch expected=%d actual=%d")
        :format(expectedTotal, actualTotal)
end

local function luaString(value)
    return string.format("%q", tostring(value or ""))
end

local function luaKey(key)
    if key:match("^[%a_][%w_]*$") then return key end
    return "[" .. luaString(key) .. "]"
end

local function luaValue(value)
    local kind = type(value)
    if kind == "boolean" then return value and "true" or "false" end
    if kind == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge, "non-finite manifest number")
        return string.format("%.17g", value)
    end
    return luaString(value)
end

if emitGenerated then
    local lines = {{ "Manifest.defaults = {{" }}
    for i = 1, #scopes do
        local scope = scopes[i]
        lines[#lines + 1] = "    " .. luaKey(scope) .. " = {{"
        local values = expectedByScope[scope]
        local keys = sortedStringKeys(values)
        for j = 1, #keys do
            local key = keys[j]
            lines[#lines + 1] = "        " .. luaKey(key) .. " = " .. luaValue(values[key]) .. ","
        end
        lines[#lines + 1] = "    }},"
    end
    lines[#lines + 1] = "}}"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "-- top-level scalar paths: " .. tostring(expectedTotal)
    print("__MANIFEST_BEGIN__")
    print(table.concat(lines, "\\n"))
    print("__MANIFEST_END__")
else
    if #mismatches > 0 then
        table.sort(mismatches)
        error("AutoCoverage manifest drift (" .. tostring(#mismatches) .. " issues):\\n- "
            .. table.concat(mismatches, "\\n- "))
    end
    print(("assistant_autocoverage_manifest_regression: ok scalars=%d scopes=%d")
        :format(actualTotal, #scopes))
end
"""

completed = subprocess.run(
    ["lua", "-"],
    input=lua,
    text=True,
    encoding="utf-8",
    cwd=ROOT,
    capture_output=True,
)
if completed.returncode != 0:
    if completed.stdout:
        sys.stdout.write(completed.stdout)
    if completed.stderr:
        sys.stderr.write(completed.stderr)
    raise SystemExit(completed.returncode)

if WRITE:
    generated = re.search(
        r"__MANIFEST_BEGIN__\r?\n(.*?)\r?\n__MANIFEST_END__",
        completed.stdout,
        re.DOTALL,
    )
    if not generated:
        raise SystemExit("generated manifest markers were not returned")
    body = generated.group(1).replace("\r\n", "\n")
    scalar_match = re.search(r"-- top-level scalar paths: (\d+)", body)
    if not scalar_match:
        raise SystemExit("generated manifest scalar count missing")
    scalar_count = int(scalar_match.group(1))
    current = MANIFEST_PATH.read_text(encoding="utf-8-sig")
    prefix = current.split("Manifest.defaults = {", 1)[0]
    generated_comment = (
        f"-- Defaults generated offline on {dt.date.today().isoformat()} from the current factory profile\n"
        "-- through the same decode and normalization path used by MSUF in game.\n"
        "-- Regenerate and verify with tools/assistant_autocoverage_manifest_regression.py.\n"
        f"-- {scalar_count} top-level scalar fallbacks across every required AutoCoverage scope.\n"
    )
    prefix = re.sub(
        r"-- Defaults generated offline.*?(?=Manifest\.scalarCount)",
        generated_comment,
        prefix,
        flags=re.DOTALL,
    )
    prefix = re.sub(
        r"Manifest\.scalarCount\s*=\s*\d+",
        f"Manifest.scalarCount = {scalar_count}",
        prefix,
    )
    MANIFEST_PATH.write_text(prefix + body + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {MANIFEST_PATH.relative_to(ROOT)} ({scalar_count} scalar paths)")
else:
    sys.stdout.write(completed.stdout)
