local Logger = require "src.client.Logger"
local Class = require "src.lib.class"
local Reporter = require "src.helpers.Reporter"

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

		PROMPT_MODE_ENUM = {
			CREATE_TITLE = 1;
			CREATE_DESC = 2;
			CREATE_LOCATION = 3;
			CREATE_TIMEFRAME = 4;

			POLL_REMOVE = 5;
		};
	};
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
function CommandHandler:handlePromptResponse( message, response )
	local user = message.author
	local userID = user.id

	local function tryExe( target, ... )
		if response:find "^%!cancel" then
			self.promptModes[ userID ] = nil
			Reporter.success( user, "Successfully cancelled input", "Canceled prompt input -- ready for direct commands" )

			return
		else
			if self:executeCommand( ... ) then self.promptModes[ userID ] = target end
		end
	end

	local MODES, mode = CommandHandler.PROMPT_MODE_ENUM, self.promptModes[ userID ]
	if not mode then
		return Logger.e( "Failed to handle prompt response from " .. user.fullname, userID .. " no prompt mode set for this user. Should probably be handled as a direct command" )
	elseif mode == MODES.CREATE_TITLE then
		tryExe( MODES.CREATE_DESC, "setTitle", message, response )
	elseif mode == MODES.CREATE_DESC then
		tryExe( MODES.CREATE_LOCATION, "setDesc", message, response )
	elseif mode == MODES.CREATE_LOCATION then
		tryExe( MODES.CREATE_TIMEFRAME, "setLocation", message, response )
	elseif mode == MODES.CREATE_TIMEFRAME then
		tryExe( nil, "setTimeframe", message, response )
	elseif mode == MODES.POLL_REMOVE then
		-- TODO
	end
end

--[[
	@instance
	@desc WIP
]]
function CommandHandler:executeCommand( commandName, ... )
	local com = CommandHandler.static.commands[ commandName ]
	if not com then return Logger.e( "Failed to load action for command '"..commandName.."'" ) end

	Logger.i( "Executing action for command '" .. commandName .. "'" )
	local r = { com.action( self.worker, ... ) }
	Logger.s( "Command for '" .. commandName .. "' executed" )

	return unpack( r )
end

--[[
	@instance
	@desc WIP
]]
function CommandHandler:handleCommand( message, command )
	local commandName, arg = command:match "^%!(%w+)%s*(.*)$"

	local cmd = CommandHandler.static.commands[ commandName ]

	if cmd.admin then
		Logger.i( "Validating user admin level in order to execute '" .. commandName .. "' command." )
		if not self.worker:getAdminLevel( message.author.id ) then
			Logger.w( "Refusing to execute command '"..commandName.."'. User is not admin" )
			Reporter.failure( message.author, "Failed to execute administrator command", "Your user is not authorized to execute this command. Contact the BGnS guild owner or a server administrator if you believe this is in error.")
			return 
		end

		Logger.s( "User is authorized to execute command" )
	end

	return self:executeCommand( commandName, message, arg, unpack( splitArguments( arg ) ) )
end

return abstract( true ):compile()