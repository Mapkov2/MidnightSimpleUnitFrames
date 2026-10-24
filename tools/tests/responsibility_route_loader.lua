-- Cache compilation only. Every world executes every real manifest chunk in
-- a fresh environment, with fresh main closures, module locals and providers.
-- No product operation, preparation, timer or measurement is cached.
local rawLoad, rawCompile, dump, rawExecute = loadfile, loadstring, string.dump, dofile
local bytecode = {}
local function Compile(path)
    local bytes = bytecode[path]
    if not bytes then
        local chunk, err = rawLoad(path)
        if not chunk then return nil, err end
        bytes = dump(chunk)
        bytecode[path] = bytes
    end
    return rawCompile(bytes, "@" .. path)
end

-- dofile is a native loader; replacing loadfile alone does not cache its parses.
local function Execute(path)
    if path == nil then return rawExecute() end
    local chunk, err = Compile(path)
    if not chunk then error(err, 2) end
    return chunk()
end
return Compile, Execute
