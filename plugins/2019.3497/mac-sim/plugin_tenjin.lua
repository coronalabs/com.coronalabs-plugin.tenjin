-- Tenjin plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name="plugin.tenjin", publisherId="com.coronalabs" }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local tenjin = require "plugin.tenjin"
--    tenjin.init()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The Tenjin plugin is only supported on Android & iOS devices. Please build for device")
end

function lib.init()
    showWarning("tenjin.init()")
end

function lib.logEvent()
    showWarning("tenjin.logEvent()")
end

function lib.logPurchase()
    showWarning("tenjin.logPurchase()")
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
