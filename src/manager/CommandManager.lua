local Logger, Manager = require "src.util.Logger", require "src.manager.Manager"
local discordia = luvitRequire "discordia"

--[[
	A manager class that is utilised by the Worker class in order to provide
	command handling capabilities (the execution of commands).
]]
local CommandManager = class "CommandManager" {
	commands = require "src.lib.commands"
}

--[[
	@instance
	@desc Handles the item given by validating that the command provided is of
		  the correct syntax, and that the command exists.

		  The function will also ensure that the user is allowed to run a command
		  before execution to ensure that no 401 UNAUTHORIZED responses are
		  received from the server.

		  The item provided must be a queue item (from the worker). This function
		  will determine whether it is a text-command or a reaction-based command
		  and deal with it accordingly.
	@param <Discordia Message Instance - message> - If handling a message the message instance must be passed
	@param <table - reaction> - If handling a reaction, a Lua table must be passed containing the Discordia Reaction Instance at index 1, and the userID at index 2
	@return <true - status> - If command execution successful, true will be returned
	@return <false - status>, <number - status> - If command execution failed, false AND a status code will be returned
	@return <false - status>, <string - error> - If the command execution failed for an unknown reason (unable to provide status code) the warning/error log will be returned
]]
function CommandManager:handleItem( item )
	if type( item ) == "table" and ( discordia.class.type( item ) == "Message" or discordia.class.type( item ) == "Reaction" ) then
		if discordia.class.type( item ) == "Message" then
			return self:handleMessage( item )
		else
			return Logger.w "Item provided is a reaction. The bot is unable to process reaction-based commands (NYI)"
		end
	else
		return Logger.w( "Item provided '"..tostring( item ).."' for handling is INVALID. *Must* be a Discordia Message/Reaction instance" )
	end
end

--[[
	@instance
	@desc Continues item handling by checking that the command received is valid
		  and that the user is within their rights to execute it.
	@param <Discordia Message Instance - message>
]]
function CommandManager:handleMessage( message )
	local content = message.content
	if not ( content and content:find "^!%w+" ) then return false, 1 end

	local commandName, trailing = content:match "^!(%w+)(.*)"
	local com = self.commands[ commandName ]

	if not ( com and com.action ) then
		return false, 2
	elseif com.permissions then
		if not message.member:getPermissions():has( unpack( com.permissions ) ) then return false, 3 end
	end

	return self:executeCommand( commandName, message )
end

--[[
	@instance
	@desc Executes the command given, with the context being the message
		  provided (arg #2).

		  When the command is executed, the action is checked for a response.
		  If the response was success, the commands 'onSuccess' callback
		  will be invoked (if one exists) -- if it doesn't exist, and
		  checkmark reaction will be applied to the message context.

		  If the command failed to execute, a command response for the
		  status code provided will be used. If one cannot be found, the
		  'onFailure' callback will be executed. If the callback is not
		  set, the message will be reacted with a cross.

		  In all instances, this function will return true if the command
		  was executed -- regardless of it's state. The success state, and
		  status code are returned as arg #2 and #3.
	@param <string - commandName>, <Discordia Message Instance - message>
	@return <true - executed>, <boolean - success>, [number - statusCode]
]]
function CommandManager:executeCommand( commandName, messageContext )
	local com = self.commands[ commandName ]
	local success, statusCode
	if type( com.action ) == "string" then
		success, statusCode = self.worker.eventManager[ com.action ]( self.worker.eventManager, messageContext.guild.id, messageContext.author.id )
	else
		success, statusCode = com.action( self.worker.eventManager, messageContext.guild.id, messageContext.author.id, messageContext )
	end

	if success then
		-- The command executed successfully. Call 'onSuccess' if present, otherwise react to the message with a checkmark.
		if type( com.onSuccess ) == "function" then
			com.onSuccess( self.worker.eventManager, messageContext.author.id, messageContext, success, statusCode )
		else
			messageContext:addReaction "✅"
		end
	else
		if com.responses and com.responses[ statusCode ] then
			Reporter.failure( messageContext.channel, "Failed to execute '"..commandName.."'", com.responses[ statusCode ] )
		elseif type( com.onFailure ) == "function" then
			com.onFailure( self.worker.eventManager, messageContext.author.id, messageContext, success, statusCode )
		else
			messageContext:addReaction "❌"
		end
	end

	return true, success, statusCode
end

extends "Manager"
return CommandManager:compile()
