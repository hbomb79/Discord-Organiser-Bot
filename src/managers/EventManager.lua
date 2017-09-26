local JSONPersist = require "src.helpers.JSONPersist"
local Reporter = require "src.helpers.Reporter"
local Logger = require "src.client.Logger"

local function bulkDelete( channel )
	local msgs = channel:getMessages()
	if #msgs > 1 then
		channel:bulkDelete( msgs )
	elseif #msgs == 1 then
		msgs:iter()():delete()
	end
end

--[[
	WIP
]]

Logger.d "Compiling EventManager"
local EventManager = class "EventManager" {
	events = {}
}

--[[
	@constructor
	@desc WIP
]]
function EventManager:__init__( ... )
	self:super( ... )
	Logger.i( "Instantiated EventManager", "Loading saved events" )
	self.events = JSONPersist.loadFromFile ".events"
end

--[[
	@instance
	@desc WIP
]]
function EventManager:getEvent( userID )
	return self.events[ userID ]
end

--[[
	@instance
	@desc WIP
]]
function EventManager:getPublishedEvent()
	for author, event in pairs( self.events ) do
		if event.published then
			return event
		end
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:createEvent( userID )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Creating event for " .. name )

	if self.events[ userID ] then
		Logger.e( "Refusing to create event for user: " .. name, "The user ("..userID..") already owns an event." )
		return false
	end

	self.events[ userID ] = {
		title = "";
		desc = "";
		location = "N/A";
		timeframe = "N/A";
		author = userID;

		polls = {};
		responses = {};

		rules = false;
		published = false;
	}

	JSONPersist.saveToFile( ".events", self.events )
	Logger.s( "Created and saved event for " .. name .. " ["..userID.."]" )

	return true
end

--[[
	@instance
	@desc WIP
]]
function EventManager:removeEvent( userID, noUnpublish )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Removing event for " .. name )

	if not self.events[ userID ] then
		Logger.e( "Refusing to remove event for user: " .. name, "The user ("..userID..") owns no event.")
		return false
	elseif self.events[ userID ].published then
		if noUnpublish then
			return Logger.e( "Attempting to remove '" .. name .. "' event although it has already been published -- refusing to remove" )
		else
			Logger.i( "Attempting to remove '" .. name .. "' event although it has already been published -- unpublishing event first" )
			self:unpublish( userID )
		end
	end

	self.events[ userID ] = nil
	JSONPersist.saveToFile( ".events", self.events )
	Logger.s( "Removed event for " .. name .. " ["..userID.."]" )

	return true
end

--[[
	@instance
	@desc WIP
]]
function EventManager:publishEvent( userID )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Publishing event for " .. name )

	local event = self.events[ userID ]
	if not event then
		return Logger.e( "Refusing to publish event for user " .. name, "The user ("..userID..") owns no event." )
	elseif event.published then
		return Logger.w( "Refusing to publish event for user " .. name, "Event already published" )
	end

	event.published = true
	JSONPersist.saveToFile( ".events", self.events )
	Logger.s( "Published event for " .. name .. " ["..userID.."]" )

	self:refreshRemote()

	return true
end

--[[
	@instance
	@desc WIP
]]
function EventManager:unpublishEvent()
	local publishedEvent = self:getPublishedEvent()
	if not publishedEvent then
		return Logger.e( "Unable to unpublish event. No event is published" )
	end

	local name = self.worker.client:getUser( publishedEvent.author ).fullname
	Logger.i( "Unpublishing currently published event", "Author: " .. name )

	publishedEvent.published = false

	JSONPersist.saveToFile( ".events", self.events )
	Logger.s( "Unpublished event for " .. name .. " ["..publishedEvent.author.."]" )

	self:refreshRemote()

	return true
end

--[[
	@instance
	@desc WIP
]]
function EventManager:pushEvent( target, userID )
	local target = target or self.worker.cachedChannel
	Logger.i( "Pushing event to target chat ("..tostring( target )..")" )

	local event = self.events[ userID ]

	if target == self.worker.cachedChannel then bulkDelete( target ) end
	Reporter.info(
		target, event.title, event.desc,
		{ name = "Location", value = event.location, inline = true },
		{ name = "Timeframe", value = event.timeframe, inline = true },
		{ name = "RSVPs", value = "Literally nobody -- This doesn't work yet." }
	)

	Logger.s "Pushed event to target"
end

--[[
	@instance
	@desc WIP
]]
function EventManager:pushPublishedEvent( target )
	local pub = self:getPublishedEvent()
	if not pub then
		return Logger.e("Cannot push published event to target", "No event is published")
	end

	self:pushEvent( target, pub.author )
end

--[[
	@instance
	@desc WIP
]]
function EventManager:refreshRemote()
	Logger.i "Refreshing remote (pushing)"
	local pub = self:getPublishedEvent()
	if pub then
		self:pushPublishedEvent()
	else
		local channel = Logger.assert( self.worker.cachedChannel, "Cannot push to remote -- channel has not been cached. Call refreshRemote AFTER starting worker", "Found cached channel" )
		bulkDelete( channel )

		Reporter.info( channel, "No Event", "No one has published an event yet. Send this bot the message '!help' (via direct messaging, accessible by clicking the bots icon).\n\nThe bot will respond with helpful information regarding how to use the event planner." )
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:updateEvent( userID, field, value )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i("Attempting to update " .. name .. " event (field '"..tostring( field ) .. "', value '"..tostring( value ).."')")

	local event = self:getEvent( userID )
	if not event then
		Logger.w( "No event exists for user " .. name, "Unable to edit fields on non-existent events... duh" )
	else
		event[ field ] = value
		JSONPersist.saveToFile( ".events", self.events )

		if event.published then
			-- The field has been updated. If the event has been published let all members that have RSVP'd know the event has been updated
			local rsvps = event.responses
			for userID, response in pairs( rsvps ) do
				-- local m = GUILD:getMember( userID )
				-- log.i( "TODO: Send edit information to user " .. tostring( m ) .. " | userID: " .. tostring( userID ) )
			end

			self:refreshRemote()
		end

		return true
	end
end

extends "Manager"
return EventManager:compile()
