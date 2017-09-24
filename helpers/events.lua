local function createNewEvent( user )
	return {
		title = "No Title",
		desc = "No description",
		location = "No location set",
		timeframe = "No timeframe set",

		author = user.id,
		rules = false,
		published = false,
		polls = {},
		responses = {}
	}
end

local events = {}

events.evs = {}
events.check = function() return discordia end

--[[
	Basic event administration
]]
events.getCurrentEvent = function( self )
	local e = self.evs
	for i = 1, #e do
		if e[ i ].published then
			return e[ i ], i
		end
	end
end

events.getEvent = function( self, user )
	local e = self.evs
	for i = 1, #e do
		if e[ i ].author == user.id then
			return e[ i ], i
		end
	end
end

events.createEvent = function( self, user )
	log.i( "Attempting to create event data for "..tostring( user ))
	if self:getEvent( user ) then
		log.w( "Refusing to create event data -- an event for this user already exists" )
		return false
	end

	self.evs[ #self.evs + 1 ] = createNewEvent( user )
	self:saveEvents()

	log.i "Created event"
	return true
end

events.cancelEvent = function( self, user )
	log.i( "Attempting to remove event data for " .. tostring( user ) )
	local e, index = self:getEvent( user )
	if not e or e.published then
		log.w( "Refusing the remove event data -- event cannot be canceled (either doesn't exist or is published)" )
		return false
	end

	if table.remove( self.evs, index ).author ~= user.id then
		log.c("Event data removed belonged to the incorrect user. Recovering event data by method: reloading events from file. Unsaved event changes will be lost.")
		self:loadEvents()
		return false
	end

	log.i("Removed event data from index '"..index.."'. Saving event data")
	self:saveEvents()

	return true
end

events.publishEvent = function( self, user )
	log.i( "Attempting to publish event")
	local e = self:getEvent( user )
	if e.published then
		log.w("Event already published")
		return
	else
		log.i("Publishing event authored by " .. tostring( user ))
		e.published = true

		self:saveEvents()
		self:pushPublishedEvent()

		return true
	end
end

events.unpublishEvent = function( self, user )
	log.i("Attempting to unpublish event")
	local currentEvent = self:getCurrentEvent()
	if not currentEvent then
		log.w("No published event. Cannot unpublish")
		reporter:warning( user, "No Published Event", "Cannot unpublish event. No events are currently published" )
	elseif currentEvent.author ~= user.id then
		log.w("Published event is NOT owned by user that sent unpublish request. Rejecting")
		reporter:warning( user, "Failed to Unpublish Event", "The currently published event is owned by someone else. Contact the author of the published event (<@"..tostring( user.id )..">) for more information" )
	else
		log.i("Event has been confirmed as published and owned by request maker. Unpublishing")
		reporter:success( user, "Unpublished Event", "The event has been unpublished. All members that have RSVP'd have been notified (and their responses have been removed)" )

		currentEvent.published = false
		self:saveEvents()
		self:refreshRemote()
	end
end

events.refreshRemote = function( self )
	log.i("Refreshing remote (pushing)")
	local current = self:getCurrentEvent()
	if current then
		self:pushPublishedEvent()
	else
		CHANNEL:bulkDelete()
		reporter:info( CHANNEL, "No Event", "No one has published an event yet. Send this bot the message '!help' (via direct messaging, accessible by clicking the bots icon).\n\nThe bot will respond with helpful information regarding how to use the event planner." )
	end
end

events.pushEvent = function( self, user, target )
	local target = target or CHANNEL
	log.i("Pushing event to target chat ("..tostring( target )..")")

	local event = self:getEvent { id = user }

	if target == CHANNEL then target:bulkDelete() end
	reporter:info(
		target, event.title, event.desc,
		{ name = "Location", value = event.location, inline = true },
		{ name = "Timeframe", value = event.timeframe, inline = true },
		{ name = "Attendees", value = "Literally nobody -- This doesn't work yet" }
	)
end

events.pushPublishedEvent = function( self, target )
	log.i("Forwarding request to push published event to events:pushEvent")
	local e = self:getCurrentEvent()

	if not e then
		log.w("Cannot push published event -- no events have been published")
		return
	end

	self:pushEvent( e.author, target )
end

events.updateEvent = function( self, user, field, value )
	log.i("Attempting to update " .. tostring( user ) .. "'s event (field '"..tostring( field ) .. "', value '"..tostring( value ).."')")
	local event = self:getEvent( user )
	if not event then
		log.w "No event exists for user -- unable to edit fields on non-existent events... duh"
	else
		event[ field ] = value

		-- Save to file
		self:saveEvents()

		-- Handle published event
		if event.published then
			-- The field has been updated. If the event has been published let all members that have RSVP'd know the event has been updated
			local rsvps = event.responses
			for userID, response in pairs( rsvps ) do
				local m = GUILD:getMember( userID )
				log.i( "TODO: Send edit information to user " .. tostring( m ) .. " | userID: " .. tostring( userID ) )
			end

			-- Push to server
			self:pushPublishedEvent()
		end

		return true
	end
end

events.saveEvents = function( self )
	log.i "Saving events"
	jpersist.saveTable( self.evs, "./events.cfg" )
	log.i "Events saved"
end

--[[
	@instance
	@desc Open the events file './events.cfg', read all content, unpickle, and save into 'self.evs'
]]
events.loadEvents = function( self )
	log.i "Loading events"
	self.evs = jpersist.loadTable( "./events.cfg" ) or {}
	-- self.evs = table.load "./events.cfg"
	if not self.evs then
		log.w "Events may have failed to load (table loaded from file is 'nil'). However this *could* be due to no events be found"
		self.evs = {}
	end

	log.i "Events loaded"
end

--[[
	Event polling
]]
events.getPolls = function( self )

end

events.getOpenPoll = function( self )

end

events.createPoll = function( self )

end

events.closePoll = function( self )

end

events.removePoll = function( self )

end

return events
