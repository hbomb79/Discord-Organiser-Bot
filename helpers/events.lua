local function createNewEvent( user )
	return {
		title = "No Title",
		desc = "No description",
		location = "No location set",
		timeframe = "No timeframe set",

		author = user.id,
		rules = false,
		locked = false,
		published = false,
		polls = {}
	}
end

local events = {}

events.evs = {}
events.check = function() return true end

--[[
	Basic event administration
]]
events.getCurrentEvent = function( self )

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
		log.w( " Refusing the remove event data -- event is not cancellable (either doesn't exist or is published)" )
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

events.pushCurrentEvent = function( self )

end

events.updateEvent = function( self, user, field, value )

end

events.saveEvents = function( self )
	log.i "Saving events"
	jpersist.saveTable( self.evs, "./events.cfg" )
	-- table.save( self.evs, "./events.cfg" )

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