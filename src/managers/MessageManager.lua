local Logger = require "src.client.Logger"
local Manager = require "src.managers.manager"
local Class = require "src.lib.class"

--[[
	A manager (a class that must be bound to a parent instance -- a worker) that handles
	the parsing and execution on incoming messages (caught via messageCreate event).
]]

Logger.d "Compiling MessageManager"
local MessageManager = class "MessageManager" {
	owner = false;
}

function MessageManager:__init__( ... )
	self:super( ... )
	Logger.i( "Attempting to bind manager (RestrictionManager)" )
	self.restrictionManager = Logger.assert( require( "src.managers.RestrictionManager" )( self ), "Failed to bind RestrictionManager", "Bound RestrictionManager" )
end

--[[
	@instance
	@desc WIP
]]
function MessageManager:handleInbound( message )
	if message.author.bot or self.restrictionManager:isUserRestricted( message.author.id, true ) then return end

	Logger.i( "Handling inbound message " .. tostring( message ) .. " from " .. tostring( message.author ) )
	if not self.owner then
		Logger.e("No owner bound to this manager instance (MessageManager). Cannot continue -- ignoring message")
		return false
	end

	return true
end

function MessageManager:addToQueue( message )

end


extends "Manager"
return MessageManager:compile()