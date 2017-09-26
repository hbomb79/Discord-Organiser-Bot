local Logger = require "src.client.Logger"
local Manager = require "src.managers.manager"
local Class = require "src.lib.class"
local discordia = luvitRequire "discordia"

--[[
	A manager (a class that must be bound to a parent instance -- a worker) that handles
	the parsing and execution on incoming messages (caught via messageCreate event).
]]

Logger.d "Compiling MessageManager"
local MessageManager = class "MessageManager" {
	owner = false;
	queue = {};
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

	Logger.i( "Handling inbound message " .. tostring( message ) .. " from " .. tostring( message.author ) .. " via channel " .. tostring( message.channel ) .. " of type " .. tostring( message.channel.type ) )
	if not self.owner then
		return Logger.w("No owner bound to this manager instance (MessageManager). Cannot continue -- ignoring message")
	elseif message.channel.type ~= discordia.enums.channelType.private then
		return Logger.w( "Message recieved from public source", tostring( message.channel ), "Commands issued to bot must be sent via a direct message" )
	end

	self:addToQueue( message )

	return true
end

--[[
	@instance
	@desc WIP
]]
function MessageManager:addToQueue( message )
	Logger.i( "Adding message " .. tostring( message ) .. " to queue at position #" .. tostring( #self.queue + 1 ) )
	table.insert( self.queue, message )
end


extends "Manager"
return MessageManager:compile()
