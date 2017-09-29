local JSONPersist = require "src.helpers.JSONPersist"
local Reporter = require "src.helpers.Reporter"
local Logger = require "src.client.Logger"
local discordia = luvitRequire "discordia"

local wrap = function( f ) return coroutine.wrap( f )() end

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
	static = {
		ATTEND_ENUM = { [ 0 ] = "not going", [ 1 ] = "might be going", [ 2 ] = "going" }
	};

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

		responses = {};

		poll = false;
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
			self:unpublishEvent( userID )
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
	publishedEvent.pushedSnowflake = nil

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
	local function formResponses()
		local lastState, client, responses, str, states = false, self.worker.client, event.responses, "", { {}, {}, {} }
		for userID, response in pairs( responses ) do table.insert( states[ response + 1 ], userID ) end

		local function out( a ) str = str .. "\n" .. a end
		for s = 1, #states do
			local state = states[ s ]
			if #state > 0 then
				local name = EventManager.ATTEND_ENUM[ s - 1 ]
				out( ("__%s%s__"):format( name:sub( 1, 1 ):upper(), name:sub( 2 ) ) )

				for r = 1, #state do
					out( ("- %s"):format( client:getUser( state[ r ] ).fullname ) )
				end
			end
		end

		return str == "" and "*No RSVPs*" or str
	end

	local nickname = self.worker.cachedGuild:getMember( userID ).nickname
	if target == self.worker.cachedChannel then bulkDelete( target ) end
	local message = Logger.assert( target:send {
		embed = {
			title = event.title,
			description = event.desc,
			fields = {
				{ name = "Location", value = event.location, inline = true },
				{ name = "Timeframe", value = event.timeframe, inline = true },
				{ name = "RSVPs (use the reactions underneath)", value = formResponses() }
			},

			author = {
				name = ( nickname and nickname .. " (" or "" ) .. self.worker.client:getUser( userID ).name .. ( nickname and ")" or "" ),
				icon_url = self.worker.client:getUser( userID ).avatarURL,
			},

			color = discordia.Color.fromRGB( 114, 137, 218 ).value,
		    timestamp = os.date "!%Y-%m-%dT%H:%M:%S",
			footer = { text = "Bot written by Hazza Bazza Boo" }
		}
	}, "Failed to push remote. Cannot continue", "Remote pushed" )

	if event.published then
		Logger.d( "Pushing a published event -- caching event announcement snowflake for use with reaction based RSVPs", "ID: " .. message.id )
		if event.pushedSnowflake ~= message.id then
			Logger.d "Updating .events file to hold correct event snowflake under published event"
			event.pushedSnowflake = message.id

			JSONPersist.saveToFile( ".events", self.events )
		end

		wrap( function()
			Logger.d "Adding message reactions for RSVPs"
			message:addReaction "✅"
			message:addReaction "❔"
			message:addReaction "🚫"
		end )
	end

	Logger.s "Pushed event to target"
	return true, message
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
	local client = self.worker.client
	local name = client:getUser( userID ).fullname
	Logger.i("Attempting to update " .. name .. " event (field '"..tostring( field ) .. "', value '"..tostring( value ).."')")

	local event = self:getEvent( userID )
	if not event then
		Logger.w( "No event exists for user " .. name, "Unable to edit fields on non-existent events... duh" )
	else
		event[ field ] = value
		JSONPersist.saveToFile( ".events", self.events )

		if event.published then
			Logger.i( "Notifying users that have RSVP'd to event that details have changed" )
			local notif = "<@"..event.author.."> has changed the details of the published event. You are currently set to **%s**.\n\nChange your RSVP state using the reactions under the announcement message in BGnS"

			local rsvps = event.responses
			for userID, response in pairs( rsvps ) do
				local user = client:getUser( userID )
				Logger.d( "Notifying " .. user.fullname )

				Reporter.info( user, "Event Plans Have Changed", notif:format( EventManager.ATTEND_ENUM[ response ] ) )
			end

			self:refreshRemote()
		end

		return true
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:respondToEvent( userID, state )
	local user, event = self.worker.client:getUser( userID ), self:getPublishedEvent()
	local eventAuthor, stateName = self.worker.client:getUser( event.author ), EventManager.ATTEND_ENUM[ state ]
	Logger.i( "Attempting to set RSVP state for " .. user.fullname .. " on published event (author: "..eventAuthor.fullname..") to state "..tostring( state ), userID )

	if not state or not ( state == 0 or state == 1 or state == 2 ) then
		return Logger.e( "Failed to RSVP. State '"..tostring( state ).."' is invalid. Can only be 0, 1, or 2 (not going, maybe, going respectively)" )
	elseif not event then
		Reporter.warning( user, "Failed to RSVP", "No event is published -- can only RSVP to published events" )
		return Logger.w "Cannot respond to event -- no event published"
	elseif event.author == userID then
		Reporter.warning( user, "Failed to RSVP", "The published event is owned by you! Cannot RSVP to own event." )
		Logger.w "Cannot respond to event -- cannot respond to own events"
	elseif event.responses[ userID ] == state then
		Reporter.warning( user, "Failed to RSVP", "You have already set your state to **" .. stateName .. "**.\n\nYou can change your RSVP state using **!yes**, **!no**, or **!maybe** (or you can use the reactions on the announcement message in BGnS)." )
		Logger.w( "Refusing to respond to event -- user has already set RSVP state to " .. state )
	else
		event.responses[ userID ] = state
		JSONPersist.saveToFile( ".events", self.events )

		Logger.i( "Notifying event host of new RSVP" )
		Reporter.info( eventAuthor, "A user has RSVP'd", "<@"..userID.."> has set their RSVP status to **"..stateName.."**" )

		Logger.s( "Set response for event authored by " .. eventAuthor.fullname, userID, "to state " .. state )
		Reporter.success( user, "RSVP Approved", "Your RSVP state **" .. stateName .. "** has been saved and the event host <@"..event.author.."> has been notified." )
	end

	self:refreshRemote()
end

--[[
	@instance
	@desc WIP
]]
function EventManager:createPoll( userID )
	local user, event = self.worker.client:getUser( userID ), self.events[ userID ]
	if not event then
		return Logger.e( "Failed to create poll. User " .. user.fullname, userID .. " has no event" )
	elseif event.poll then
		return Logger.e( "Refusing to create poll. User " .. user.fullname, userID .. " already has a poll" )
	else
		event.poll = {
			responses = {},
			choices = {},
			desc = "There is no description for this poll yet!"
		}

		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Created poll for " .. user.fullname )

		return true
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:deletePoll( userID )
	local user, event = self.worker.client:getUser( userID ), self.events[ userID ]
	if not event then
		return Logger.e( "Failed to delete poll. User " .. user.fullname, userID .. " has no event" )
	elseif not event.poll then
		return Logger.e( "Refusing to delete poll. User " .. user.fullname, userID .. " has no polls" )
	else
		event.poll = nil

		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Deleted poll for " .. user.fullname )

		return true
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:setPollDesc( userID, desc )
	local user, event = self.worker.client:getUser( userID ), self.events[ userID ]
	if not event then
		return Logger.e( "Failed to edit poll description. User " .. user.fullname, userID .. " has no event" )
	elseif not event.poll then
		return Logger.e( "Failed to edit poll. User " .. user.fullname, userID .. " has no poll" )
	else
		event.poll.desc = desc

		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Edited poll desc for " .. user.fullname )

		return true
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:addPollOption( userID, option )
	local user, event = self.worker.client:getUser( userID ), self.events[ userID ]
	if not event then
		return Logger.e( "Failed to add poll option. User " .. user.fullname, userID .. " has no event" )
	elseif not event.poll then
		return Logger.e( "Failed to add poll option. User " .. user.fullname, userID .. " has no poll" )
	elseif #event.poll.choices >= 10 then
		return Logger.e( "Failed to add poll option. User " .. user.fullname, userID .. " has reached the choice limit (10)" )
	else
		table.insert( event.poll.choices, option )

		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Added poll option for " .. user.fullname )

		return true, #event.poll.choices
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:removePollOption( userID, index )
	index = tonumber( index )
	if not index then
		return Logger.e( "Failed to remove poll option. Index provided '" .. index .. "' is invalid. Provide a valid number" )
	end

	local user, event = self.worker.client:getUser( userID ), self.events[ userID ]
	if not event then
		return Logger.e( "Failed to remove poll option. User " .. user.fullname, userID .. " has no event" )
	elseif not event.poll then
		return Logger.e( "Failed to remove poll option. User " .. user.fullname, userID .. " has no poll" )
	elseif not event.poll.choices[ index ] then
		return Logger.e( "Failed to remove poll option. There is no poll option #" .. index .. " in users event " .. user.fullname, userID )
	else
		local val = table.remove( event.poll.choices, index )

		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Removed poll option '"..val.."' ("..index..") for " .. user.fullname )

		return true
	end
end


extends "Manager"
return EventManager:compile()
