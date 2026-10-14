-- Cache compilation only. Every world executes every real manifest chunk in
-- a fresh environment, with fresh main closures, module locals and providers.
-- No product operation, preparation, timer or measurement is cached.
local rawLoad, rawCompile, dump = loadfile, loadstring, string.dump
local bytecode = {}
return function(path)
    local bytes = bytecode[path]
    if not bytes then
        local chunk, err = rawLoad(path)
        if not chunk then return nil, err end
        bytes = dump(chunk)
        bytecode[path] = bytes
    end
    return rawCompile(bytes, "@" .. path)
end
