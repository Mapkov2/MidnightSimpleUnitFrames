-- Minimal LibStub (compatible subset)
-- This is a lightweight implementation to support embedded libraries.
local LIBSTUB_MAJOR, LIBSTUB_MINOR = "LibStub", 3
local LibStub = _G[LIBSTUB_MAJOR]

if not LibStub or (LibStub.minor or 0) < LIBSTUB_MINOR then
    LibStub = LibStub or { libs = {}, minors = {}, minor = LIBSTUB_MINOR }

    function LibStub:NewLibrary(major, minor)
        assert(type(major) == "string", "LibStub:NewLibrary() - major must be a string")
        minor = assert(tonumber(minor), "LibStub:NewLibrary() - minor must be a number")

        local oldminor = self.minors[major]
        if oldminor and oldminor >= minor then
            return nil
        end

        self.minors[major] = minor
        local lib = self.libs[major]
        if not lib then
            lib = {}
            self.libs[major] = lib
        end

        return lib, oldminor
    end

    function LibStub:GetLibrary(major, silent)
        if not self.libs[major] then
            if silent then return nil end
            error("LibStub: Library '" .. tostring(major) .. "' not found.")
        end
        return self.libs[major], self.minors[major]
    end

    function LibStub:IterateLibraries()
        return pairs(self.libs)
    end

    setmetatable(LibStub, {
        __call = function(self, major, silent)
            return self:GetLibrary(major, silent)
        end,
    })

    LibStub.minor = LIBSTUB_MINOR
    _G[LIBSTUB_MAJOR] = LibStub
end
