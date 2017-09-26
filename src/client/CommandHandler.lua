local Logger = require "src.client.Logger"

local function splitArguments( val )
    local parts = {}
    for match in val:gmatch "(%S+)%s*" do parts[ #parts + 1 ] = match end

    return parts
end


--[[
	WIP
]]

Logger.d "Compiling CommandHandler"
local CommandHandler = class "CommandHandler" {
	static = {
		commands = require "src.lib.commands";
	}
}

--[[
	@instance
	@desc WIP
]]
function CommandHandler:checkCommandValid( command )
	local c = command:match "^%!(%w+)"
	if CommandHandler.static.commands[ c ] then return 2 elseif c then return 1 else return 0 end
end

--[[
	@instance
	@desc WIP
]]
function CommandHandler:executeCommand( message, command )
	local commandName, arg = command:match "^%!(%w+)%s*(.*)$"

	local fn = CommandHandler.static.commands[ commandName ].action
	if not fn then return Logger.e( "Failed to load action for command '"..commandName.."'" ) end

	Logger.i( "Executing action for command '" .. commandName .. "'" )
	fn( self.worker, message, arg, unpack( splitArguments( arg ) ) )
end

return abstract( true ):compile()