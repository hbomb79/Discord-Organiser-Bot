local Logger = require "src.util.Logger"
local json = luvitRequire "json"

--[[
    WIP
]]

Logger.d "Compiling JSONPersist"
local JSONPersist = class "JSONPersist" {}

--[[
    @static
    @desc WIP
]]
function JSONPersist.static.loadFromFile( path )
    Logger.i( "Loading table from " .. tostring( path ) )

    local h = Logger.assert( io.open( path ), "Failed to open path " .. tostring( path ), "Opened path " .. tostring( path ) .. " successfully" )
    local c = h:read "*a"
    h:close()

    return json.decode( c )
end

--[[
    @static
    @desc WIP
]]
function JSONPersist.static.saveToFile( path, table )
    Logger.i("Saving table " .. tostring( table ) .. " to path '"..tostring( path ).."'")

    local h = io.open( path, "w+" )
    h:write( json.encode( table ) )
    h:close()
end

return abstract( true ):compile()
