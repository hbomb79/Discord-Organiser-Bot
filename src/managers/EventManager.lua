local JSONPersist = require "src.helpers.JSONPersist"
local Reporter = require "src.helpers.Reporter"
local Logger = require "src.client.Logger"
local Worker = require "src.client.Worker"
local discordia = luvitRequire "discordia"

local wrap = function( f ) return coroutine.wrap( f )() end
local function nilToEmptyString( val ) return val == nil and "" or val end

local function bulkDelete( channel )
	local msgs = channel:getMessages()
	if #msgs > 1 then
		channel:bulkDelete( msgs )
	elseif #msgs == 1 then
		msgs:iter()():delete()
	end
end

local function formResponses( client, responses )
	local lastState, str, states = false, "", { {}, {}, {} }
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

local function formPollFields( poll )
	local fields, choices, responses = {}, poll.choices, poll.responses
	local voteCount = {}
	for _, index in pairs( responses ) do
		local currentVoteCount = voteCount[ index ]
		if not currentVoteCount then
			voteCount[ index ] = 1
		else
			voteCount[ index ] = currentVoteCount + 1
		end
	end

	for i = 1, #choices do
		local votes = voteCount[ i ] or 0
		table.insert( fields, {
			name = ( "%i) %s" ):format( i, choices[ i ] ),
			value = "*" .. votes .. " vote" .. ( votes ~= 1 and "s" or "" ) .. "*"
		} )
	end

	return fields
end

local function generateEmbed( event, worker, forPoll )
	local client = worker.client
	if forPoll then
		local poll = event.poll
		return {
			title = "Event Poll",
			description = poll.desc,

			fields = formPollFields( event.poll ),

			color = discordia.Color.fromRGB( 114, 137, 218 ).value,
		    timestamp = os.date "!%Y-%m-%dT%H:%M:%S",
			footer = { text = "Bot written by Hazza Bazza Boo" }
		}
	else
		local userID = event.author
		local nickname = worker.cachedGuild:getMember( userID ).nickname
		return {
			title = event.title,
			description = event.desc,
			fields = {
				{ name = "Location", value = event.location, inline = true },
				{ name = "Timeframe", value = event.timeframe, inline = true },
				{ name = "RSVPs (use the reactions underneath)", value = formResponses( client, event.responses ) }
			},

			author = {
				name = ( nickname and nickname .. " (" or "" ) .. client:getUser( userID ).name .. ( nickname and ")" or "" ),
				icon_url = client:getUser( userID ).avatarURL,
			},

			color = discordia.Color.fromRGB( 114, 137, 218 ).value,
		    timestamp = os.date "!%Y-%m-%dT%H:%M:%S",
			footer = { text = "Bot written by Hazza Bazza Boo" }
		}
	end
end

--[[
	WIP
]]

Logger.d "Compiling EventManager"
local EventManager = class "EventManager" {
	static = {
		ATTEND_ENUM = { [ 0 ] = "not going", [ 1 ] = "might be going", [ 2 ] = "going" },
		CHOICE_REACTIONS = { "1⃣", "2⃣", "3⃣", "4⃣", "5⃣", "6⃣", "7⃣", "8⃣", "9⃣", "🔟" },
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
	@desc Forcefully pushes to the remote by clearing the target channel (if not private) and sending the event messages. Much more taxing than a update (:updatePushedEvent)
]]
function EventManager:pushEvent( target, userID )
	if self.refreshing then return Logger.w "Ignoring request to force push remote -- a force push is already in progress" end
	self.refreshing = true

	local target = target or self.worker.cachedChannel
	Logger.i( "Pushing event to target chat ("..tostring( target )..")" )

	local event = self.events[ userID ]
	if target == self.worker.cachedChannel then bulkDelete( target ) end

	local message = Logger.assert( target:send { embed = generateEmbed( event, self.worker ) }, "Failed to push remote. Cannot continue", "Remote pushed" )
	local poll, pollMessage = event.poll
	if poll then
		pollMessage = Logger.assert( target:send { embed = generateEmbed( event, self.worker, true ) }, "Failed to push poll message", "Poll pushed" )
	end

	-- Messages have been pushed (sync). We can add reactions (async) now.
	if event.published then
		Logger.d "Updating .events file to hold correct event snowflake under published event"
		event.pushedSnowflake = message.id
		if poll then poll.pushedSnowflake = pollMessage.id end

		JSONPersist.saveToFile( ".events", self.events )

		wrap( function()
			Logger.d "Adding message reactions for RSVPs"
			local reactions = { "✅", "❔", "🚫" }
			for r = 1, #reactions do
				Logger.assert( message:addReaction( reactions[ r ] ), "Failed to add reaction to event message during FORCE push", "Added reaction to event message" )
			end

			if poll then
				Logger.d "Adding message reactions for poll votes"
				for i = 1, #poll.choices do
					Logger.assert( pollMessage:addReaction( EventManager.CHOICE_REACTIONS[ i ] ), "Failed to add reaction to poll message during FORCE push", "Added reaction to poll message" )
				end
			end

			self.refreshing = false
		end )
	else
		self.refreshing = false
	end

	Logger.s "Pushed event to target"
	return true, message
end

--[[
	@instance
	@desc
]]
function EventManager:updatePushedEvent()
	if self.refreshing then return Logger.w "Ignoring request to update remote -- a force push is in progress" end

	local event, targetChannel = self:getPublishedEvent(), self.worker.cachedChannel
	if not event then return Logger.f( "Cannot update pushed event: No event has been published!" ) end

	local poll = event.poll
	if not ( event.pushedSnowflake and ( not poll or ( poll and poll.pushedSnowflake ) ) ) then
		Logger.w( "Unable to update pushed event! Missing snowflake information. Force pushing to remote.", "Main: " .. tostring( event.pushedSnowflake ), event.poll and "Poll: " .. tostring( event.poll.pushedSnowflake ) or "No poll information" )
		return self:pushPublishedEvent()
	end

	local eventMessage = targetChannel:getMessage( event.pushedSnowflake )
	if not eventMessage then
		Logger.w( "Unable to update pushed event! Snowflake information is invalid for main message (messages removed or never pushed).", tostring( eventMessage ) )
		return self:pushPublishedEvent()
	end

	if not self.refreshingEvent then
		local eventReactions, VALID_REACTIONS, updateEvent = eventMessage.reactions, { Worker.ATTEND_YES_REACTION, Worker.ATTEND_MAYBE_REACTION, Worker.ATTEND_NO_REACTION }
		for r = 1, #VALID_REACTIONS do
			local reaction = eventReactions:get( VALID_REACTIONS[ r ] )

			if not reaction or reaction.count > 1 then
				-- A user has RSVPd OR a member has deleted a reaction. Clear reactions, re populate and update message to show up-to-date RSVPs.
				Logger.d( "Detected a change in reaction count on event message. Refreshing event reactions and message" )
				updateEvent = true

				break
			end
		end

		local embed = eventMessage.embeds[ 1 ]
		updateEvent = updateEvent or ( nilToEmptyString( embed.title ) ~= event.title or nilToEmptyString( embed.description ) ~= event.desc or nilToEmptyString( embed.fields[ 1 ].value ) ~= event.location or nilToEmptyString( embed.fields[ 2 ].value ) ~= event.timeframe )

		if updateEvent then
			self.refreshingEvent = true
			Logger.d "Updating event message as it is out of sync with the local machine"

			local status = eventMessage:setEmbed( generateEmbed( event, self.worker ) )
			if not status then
				Logger.e( "Failed to update event message! Force pushing to remote." )
				return self:pushPublishedEvent()
			end

			Logger.d "Adding message reactions for RSVPs"

			waitForEvent = true
			wrap( function()
				eventMessage:clearReactions()
				for i = 1, #VALID_REACTIONS do if not eventMessage:addReaction( VALID_REACTIONS[ i ] ) then Logger.e("Failed to add reaction to event message during UPDATE. Initiating FORCE push"); self:pushPublishedEvent(); break end end

				Logger.d "Asynchronous push of reactions for event message complete."
				self.refreshingEvent = false
			end )

			Logger.s "Updated main event information"
		end
	else Logger.d("Refusing to update event message -- already being updated") end

	if poll and not self.refreshingPoll then
		local pollMessage = targetChannel:getMessage( poll.pushedSnowflake )
		if not pollMessage then
			Logger.w( "Unable to update pushed event! Snowflake information is invalid for poll message (messages removed or never pushed).", tostring( pollMessage ) )
			return self:pushPublishedEvent()
		end

		local pollReactions, VALID_POLL_REACTIONS = pollMessage.reactions, EventManager.CHOICE_REACTIONS
		for p = 1, #poll.choices do
			local reaction = pollReactions:get( VALID_POLL_REACTIONS[ p ] )
			if not reaction or reaction.count > 1 then
				self.refreshingPoll = true
				Logger.d( "Detected a change in reaction count on poll message.", tostring( not reaction ), tostring( reaction and reaction.count or 'cannot count' ), tostring( reaction.emojiName ) )
				local status = pollMessage:setEmbed( generateEmbed( event, self.worker, true ) )

				if not status then
					Logger.e( "Failed to update poll message! Force pushing to remote." )
					return self:pushPublishedEvent()
				end

				Logger.d "Adding message reactions for poll votes"
				waitForPoll = true
				wrap( function()
					pollMessage:clearReactions()
					for i = 1, #poll.choices do if not pollMessage:addReaction( EventManager.CHOICE_REACTIONS[ i ] ) then Logger.e("Failed to add reaction to poll message during UPDATE. Initiating FORCE push"); self:pushPublishedEvent(); break end end

					Logger.d "Asynchronous push of reactions for poll message complete."
					self.refreshingPoll = false
				end )

				Logger.s "Updated poll information"
				break
			end
		end
	else Logger.d("Refusing to update poll message -- already being updated") end

	JSONPersist.saveToFile( ".events", self.events )
	Logger.s( "Updated remote", ( ( self.refreshingPoll or self.refreshingEvent ) and "Refreshes may still be running asynchronously" or "No need to edit remote" ) )
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
function EventManager:refreshRemote( force )
	Logger.i( "Refreshing remote", force and "Force pushing" or "Detecting changes" )
	local pub = self:getPublishedEvent()
	if pub then
		if force then
			if self.refreshingPoll or self.refreshingEvent then
				Logger.w("Force refresh is occurring at the same time as an update of the remote. This could easily cause server NOT FOUND (404) responses (due to the message being overwritten)", "The responses can be ignored, however running a force refresh at the same time as an update should be avoided if possible" )
			end

			self:pushPublishedEvent()
		else
			self:updatePushedEvent()
		end
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
	if not event then
		Reporter.warning( user, "Failed to RSVP", "No event is published -- can only RSVP to published events" )
		return Logger.w "Cannot respond to event -- no event published"
	end

	local eventAuthor, stateName = self.worker.client:getUser( event.author ), EventManager.ATTEND_ENUM[ state ]
	Logger.i( "Attempting to set RSVP state for " .. user.fullname .. " on published event (author: "..eventAuthor.fullname..") to state "..tostring( state ), userID )

	if not state or not ( state == 0 or state == 1 or state == 2 ) then
		return Logger.e( "Failed to RSVP. State '"..tostring( state ).."' is invalid. Can only be 0, 1, or 2 (not going, maybe, going respectively)" )
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

		self:refreshRemote()

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

		self:refreshRemote( true )

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

		self:refreshRemote()

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

		self:refreshRemote()

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

		for user, choice in pairs( event.poll.responses ) do
			if choice == index then
				-- Notify user that their vote has been discarded
				event.poll.responses[ user ] = nil

				Reporter.warning( self.worker.client:getUser( user ), "Vote discarded", "The vote you cast on the current event poll has been discarded because the option you voted on is *no longer available*. Please consider re-casting a vote for another option." )
			elseif choice > index then event.poll.responses[ user ] = choice - 1 end
		end

		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Removed poll option '"..val.."' ("..index..") for " .. user.fullname )

		self:refreshRemote( true )

		return true
	end
end

--[[
	@instance
	@desc
]]
function EventManager:submitPollVote( userID, index )
	index = tonumber( index )
	if not index then
		return Logger.e( "Failed to vote on poll option. Index provided '" .. index .. "' is invalid. Provide a valid number" )
	end

	local user, event = self.worker.client:getUser( userID ), self:getPublishedEvent()
	if not ( event and event.poll ) then
		return Logger.e( "Failed to vote on poll option. There is no published poll" )
	elseif not event.poll.choices[ index ] then
		return Logger.e( "Failed to vote on poll option. There is no poll option #" .. index )
	else
		event.poll.responses[ userID ] = index
		JSONPersist.saveToFile( ".events", self.events )
		Logger.s( "Cast poll vote '"..event.poll.choices[ index ].."' ("..index..") for " .. user.fullname )

		self:refreshRemote()

		return true
	end
end


extends "Manager"
return EventManager:compile()
