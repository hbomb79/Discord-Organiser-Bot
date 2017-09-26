local Logger = require "src.client.Logger"
local Manager = require "src.managers.manager"
local Class = require "src.lib.class"
local Reporter = require "src.helpers.Reporter"
local discordia = luvitRequire "discordia"

-- Compile CommandHandler so we can mixin later
require "src.client.CommandHandler"

local function checkMutalGuild( author )
	local targetGuild = Class.getClass "Worker".static.GUILD_ID

	for id, val in pairs( author.mutualGuilds ) do
		if id == targetGuild then
			Logger.s "Target guild confirmed to be mutual between bot and user."
			return true
		end
	end

	Logger.w( "Checking for mutual guilds FAILED -- target guild '"..tostring( targetGuild ).."' NOT found." )
	return false
end

--[[
	A manager (a class that must be bound to a parent instance -- a worker) that handles
	the parsing and execution on incoming messages (caught via messageCreate event).
]]

Logger.d "Compiling MessageManager"
local MessageManager = class "MessageManager" {
	owner = false;
	queue = {};
	userRequests = {};
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
	local uID = message.author.id
	if not self.owner then
		-- Cannot process message if we have no owner/worker
		return Logger.w("No owner bound to this manager instance (MessageManager). Cannot continue -- ignoring message")
	elseif message.author.bot or self.restrictionManager:isUserBanned( uID ) then
		-- Ignore banned user/bot messages
		return
	end

	-- Check that message came from a private channel
	Logger.i( "Handling inbound message with content: " .. tostring( message.content ) .. ", from: " .. message.author.fullname .. ", via channel: " .. tostring( message.channel ) .. " @ " .. tostring( message.channel.name ) .. ". Channel type: " .. tostring( message.channel.type ) )
	if message.channel.type ~= discordia.enums.channelType.private then
		return Logger.w( "Message recieved from public source", tostring( message.channel ), "Commands issued to bot must be sent via a direct message" )
	elseif self.restrictionManager:isUserRestricted( uID ) then
		-- User is restricted. Add one violation and ignore
		Logger.w( "Received message from " .. message.author.fullname, "This user is restricted! Adding one violation" )
		self.restrictionManager:reportRestrictionViolation( uID )

		return false
	end

	self:addToQueue( message )

	return true
end

--[[
	@instance
	@desc WIP
]]
function MessageManager:addToQueue( message )
	local uID = message.author.id
	local reqs = self.userRequests[ uID ] or 0

	if reqs >= 3 then
		Logger.w( "User " .. message.author.fullname .. " already has " .. reqs .. " items in the queue. Restricting user." )
		return self.restrictionManager:restrictUser( uID )
	else
		Logger.i( "Adding message " .. tostring( message ) .. " to queue at position #" .. tostring( #self.queue + 1 ) )
		self.userRequests[ uID ] = reqs + 1
		Logger.i( "User " .. message.author.fullname .. " now has " .. reqs + 1 .. " items in the queue" )

		table.insert( self.queue, message )
		if not self.worker.workerRunning then self:startQueue() end
	end
end

--[[
	@instance
	@desc WIP
]]
function MessageManager:startQueue()
	local queue = self.queue
	if self.worker.workerRunning then
		return Logger.w( "Attempted to start queue while queue is already running. Ignoring startQueue request" )
	elseif #queue == 0 then
		return Logger.w( "Attempted to start queue when no items are queued. Ignoring startQueue request" )
	end

	Logger.d( "Starting worker", "Items in queue: " .. #queue )
	self.worker.workerRunning = true
	while #queue > 0 and self.worker.workerRunning do
		local item = queue[ 1 ]
		local author = item.author
		Logger.i( "Starting processing of next queue item (" .. tostring( item ) .. ", with content: "..tostring( item.content )..")" )

		if checkMutalGuild( item.author ) then
			local state = self:checkCommandValid( item.content )
			if state == 0 then
				Logger.w( "Cannot process command " .. item.content, "Invalid syntax" )
				Reporter.warning( author, "Failed to Process Command", "The command is syntactically invalid. Ensure it is in the form **!<commandName> [arg1, [arg2, [...]]]**" )
			elseif state == 1 then
				Logger.w( "Cannot process command " .. item.content, "Does not exist" )
				Reporter.warning( author, "Failed to Process Command", "The command you requested does not exist. Check for typos and ensure you have whitespace between your arguments" )
			elseif state == 2 then
				Logger.i( "Executing command " .. item.content )
				self:executeCommand( item, item.content )
			end
		else Reporter.warning( author, "Failed to Process Command", "Your user is not a member of the target guild. You are not permitted to execute commands via this bot.\n\nContact the guild owner if you believe this warning is incorrect" ) end

		self.userRequests[ author.id ] = self.userRequests[ author.id ] - 1
		Logger.d( "User '" .. author.fullname .. "' now has " .. self.userRequests[ author.id ] .. " requests in the queue" )
		table.remove( queue, 1 )

		Logger.i( "Removed item from queue. Items remaining in queue: " .. #queue )
	end

	Logger.d "Stopping worker. Queue is now empty"
	self.worker.workerRunning = false
end

extends "Manager" mixin "CommandHandler"
return MessageManager:compile()
