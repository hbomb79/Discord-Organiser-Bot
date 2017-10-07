local JSONPersist = require "src.helpers.JSONPersist"
local Reporter = require "src.helpers.Reporter"
local Logger = require "src.client.Logger"
local Worker = require "src.client.Worker"
local discordia = luvitRequire "discordia"

local wrap, EventManager = function( f, ... ) return coroutine.wrap( f )( ... ) end

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

local function report( code, ... )
	local _, reason = Logger.w( ... )
	return false, reason, code
end

--[[
	WIP
]]

Logger.d "Compiling EventManager"
EventManager = class "EventManager" {
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
function EventManager:saveEvents( event )
	if event then event.updated = true end
	JSONPersist.saveToFile( ".events", self.events )
end

--[[
	@instance
	@desc WIP
]]
function EventManager:createEvent( userID )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Creating event for " .. name, userID )

	if self.events[ userID ] then
		return report( 1, "Refusing to create event because the user ("..name..") already owns an event" )
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

	self:saveEvents( event )
	return Logger.s( "Created and saved event for " .. name )
end

--[[
	@instance
	@desc WIP
]]
function EventManager:removeEvent( userID, noUnpublish )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Removing event for " .. name, userID )

	if not self.events[ userID ] then
		return report( 1, "Refusing to remove event because the user ("..name..") has no events" )
	elseif self.events[ userID ].published then
		if noUnpublish then
			return report( 2, "Refusing to remove event because the user ("..name..") has already published their event" )
		else
			Logger.i( "Attempting to remove '" .. name .. "' event although it has already been published -- unpublishing event first" )

			local ok, err, code = self:unpublishEvent( userID )
			if not ok then
				return false, err, type( code ) == "number" and code + 2 or code
			end
		end
	end

	self.events[ userID ] = nil
	self:saveEvents()
	return Logger.s( "Removed event for " .. name )
end

--[[
	@instance
	@desc WIP
]]
function EventManager:publishEvent( userID )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Publishing event for " .. name, userID )

	local event = self.events[ userID ]
	if not event then
		return report( 1, "Refusing to publish event for user (" .. name .. ") because the user has no events" )
	elseif event.published then
		return report( 2, "The users ("..name..") event has already been published" )
	end

	event.published = true
	self:saveEvents( event )
	self:refreshRemote()

	return Logger.s( "Published event for " .. name )
end

--[[
	@instance
	@desc WIP
]]
function EventManager:unpublishEvent()
	local publishedEvent = self:getPublishedEvent()
	if not publishedEvent then
		return report( 1, "Unable to unpublish event. No event is published" )
	end

	local name = self.worker.client:getUser( publishedEvent.author ).fullname
	Logger.i( "Unpublishing currently published event", "Author: " .. name )

	publishedEvent.published = false
	publishedEvent.pushedSnowflake = nil

	self:saveEvents()
	self:refreshRemote( true )

	return Logger.s( "Unpublished event for " .. name )
end

--[[
	@instance
	@desc Forcefully pushes to the remote by clearing the target channel (if not private) and sending the event messages. Much more taxing than a update (:updatePushedEvent)
]]
function EventManager:pushEvent( target, userID )
	if self.refreshing then return Logger.w "Ignoring request to force push remote -- a force push is already in progress", 1 end
	self.refreshing = true

	local target = target or self.worker.cachedChannel
	Logger.i( "Pushing event to target chat ("..tostring( target )..")" )

	local event = self.events[ userID ]
	if target == self.worker.cachedChannel then target:bulkDelete( target:getMessages() ) end

	local message = Logger.assert( target:send { embed = generateEmbed( event, self.worker ) }, "Failed to push remote. Cannot continue", "Remote pushed" )
	local poll, pollMessage = event.poll
	if poll then
		pollMessage = Logger.assert( target:send { embed = generateEmbed( event, self.worker, true ) }, "Failed to push poll message", "Poll pushed" )
	end

	-- Messages have been pushed (sync). We can add reactions (async) now.
	if event.published then
		Logger.d "Updating .events file to hold correct event snowflake under published event"
		event.pushedSnowflake = message.id
		event.updated = false
		if poll then poll.pushedSnowflake = pollMessage.id; poll.updated = false end

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

	self:saveEvents()

	return Logger.s "Pushed event to target"
end

--[[
	@instance
	@desc
]]
function EventManager:updatePushedEvent()
	if self.refreshing then return report( 1, "Ignoring request to update remote -- a force push is in progress" ) end

	local event, targetChannel = self:getPublishedEvent(), self.worker.cachedChannel
	if not event then return report( 2, "Failed to update pushed event because no event has been published" ) end

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

	local function fixReactions( message, validReactions, forLimit )
		local hadToFix = false
		for r = 1, forLimit or #validReactions do
			local reaction = message.reactions:get( validReactions[ r ] )
			if not reaction then
				if not message:addReaction( validReactions[ r ] ) then
					Logger.e("Failed to add reaction " .. validReactions[ r ] .. " to event message. Force pushing to remote")
					return self:pushPublishedEvent()
				end

				hadToFix = true
			elseif reaction.count > 1 then
				wrap( function()
					for user in reaction:getUsers():iter() do
						if user.id ~= "361038817840332800" then reaction:delete( user.id ) end
					end
				end )

				hadToFix = true
			end
		end

		return hadToFix
	end

	local updated = event.updated
	if fixReactions( eventMessage, { Worker.ATTEND_YES_REACTION, Worker.ATTEND_MAYBE_REACTION, Worker.ATTEND_NO_REACTION } ) or event.updated then
		Logger.d "Updating event message content. Event has been updated since last push"
		event.updated = false

		local status = eventMessage:setEmbed( generateEmbed( event, self.worker ) )
		if not status then
			Logger.e( "Failed to update event message! Force pushing to remote." )
			return self:pushPublishedEvent()
		end
	end

	if poll then
		local pollMessage = targetChannel:getMessage( poll.pushedSnowflake )
		if not pollMessage then
			Logger.w( "Unable to update pushed event! Snowflake information is invalid for poll message (messages removed or never pushed).", tostring( pollMessage ) )
			return self:pushPublishedEvent()
		end

		if fixReactions( pollMessage, EventManager.CHOICE_REACTIONS, #poll.choices ) or poll.updated then
			Logger.d "Updating poll message content. Poll has been updated since last push"
			poll.updated = false

			local status = pollMessage:setEmbed( generateEmbed( event, self.worker, true ) )
			if not status then
				Logger.e( "Failed to update poll message! Force pushing to remote." )
				return self:pushPublishedEvent()
			end
		end
	end

	self:saveEvents()
	return Logger.s "Updated remote"
end

--[[
	@instance
	@desc WIP
]]
function EventManager:pushPublishedEvent( target )
	local pub = self:getPublishedEvent()
	if not pub then
		return report( 1, "Cannot push published event to target", "No event is published" )
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

			wrap( self.pushPublishedEvent, self )
		else
			wrap( self.updatePushedEvent, self )
		end
	else
		wrap( function()
			local channel = Logger.assert( self.worker.cachedChannel, "Cannot push to remote -- channel has not been cached. Call refreshRemote AFTER starting worker", "Found cached channel" )
			channel:bulkDelete( channel:getMessages() )

			Reporter.info( channel, "No Event", "No one has published an event yet. Send this bot the message '!help' (via direct messaging, accessible by clicking the bots icon).\n\nThe bot will respond with helpful information regarding how to use the event planner." )
		end )
	end

	return true
end

--[[
	@instance
	@desc WIP
]]
function EventManager:updateEvent( userID, field, value )
	local client = self.worker.client
	local name = client:getUser( userID ).fullname
	Logger.i("Attempting to update " .. name, userID .. " event (field '"..tostring( field ) .. "', value '"..tostring( value ).."')")

	local event = self:getEvent( userID )
	if not event then
		return report( 1, "Refusing to edit field '"..field.."' for users ("..name..") event because the user doesn't own an event" )
	end

	event[ field ] = value
	self:saveEvents( event )

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
		return Logger.s( "Updated event for user " .. name, "Members that RSVPd have been notified" )
	end

	return Logger.s( "Updated event for user " .. name )
end

--[[
	@instance
	@desc WIP
]]
function EventManager:respondToEvent( userID, state )
	--TODO: Rewrite this function (maybe)
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
		self:saveEvents( event )

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
	local name, event = self.worker.client:getUser( userID ).fullname, self.events[ userID ]
	Logger.i( "Creating poll for " .. name, userID )

	if not event then
		return report( 1, "Refusing to create poll because user (" .. name .. ") doesn't own an event. An event is required to create a poll" )
	elseif event.poll then
		return report( 2, "Refusing to create poll because user (" .. name .. ") already has a poll" )
	else
		event.poll = {
			responses = {},
			choices = {},
			desc = "There is no description for this poll yet!"
		}

		self:saveEvents( event.poll )
		self:refreshRemote()

		return Logger.s( "Created poll for " .. name )
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:deletePoll( userID )
	local name, event = self.worker.client:getUser( userID ).fullname, self.events[ userID ]
	Logger.i( "Deleting poll for " .. name, userID )

	if not ( event and event.poll ) then
		return report( event and 2 or 1, "Refusing to delete poll because user (" .. name .. ") has no " .. ( event and "poll" or "event" ) )
	else
		event.poll = nil

		self:saveEvents()
		self:refreshRemote( true )

		return Logger.s( "Deleted poll for " .. name )
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:setPollDesc( userID, desc )
	local name, event = self.worker.client:getUser( userID ).fullname, self.events[ userID ]
	Logger.i( "Setting poll description for " .. name, userID )

	if not ( event and event.poll ) then
		return report( event and 2 or 1, "Refusing to set poll description because user ("..name..") has no " .. ( event and "poll" or "event" ) )
	else
		event.poll.desc = desc or ""

		self:saveEvents( event.poll )
		self:refreshRemote()

		return Logger.s( "Edited poll description for " .. name )
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:addPollOption( userID, option )
	local name, event = self.worker.client:getUser( userID ).fullname, self.events[ userID ]
	Logger.i( "Adding poll option for " .. name, userID )

	if not ( event and event.poll ) then
		return report( event and 2 or 1, "Refusing to add poll option because user ("..name..") has no " .. ( event and "poll" or "event" ) )
	elseif #event.poll.choices >= 10 then
		return report( 3, "Refusing to add poll option because user ("..name..") has reached the option limit (max. 10)" )
	else
		table.insert( event.poll.choices, option )

		self:saveEvents( event.poll )
		self:refreshRemote()

		return Logger.s( "Added poll option for " .. name )
	end
end

--[[
	@instance
	@desc WIP
]]
function EventManager:removePollOption( userID, index )
	local name, event = self.worker.client:getUser( userID ).fullname, self.events[ userID ]
	Logger.i( "Removing poll option for " .. name, userID .. " at index " .. tostring( index ) )

	index = tonumber( index )
	if not index then
		return report( 1, "Cannot remove poll option. Index provided '" .. tostring( index ) .. "' is invalid. Provide a valid number" )
	elseif not ( event and event.poll ) then
		return report( event and 3 or 2, "Refusing to remove poll option because user ("..name..") has no " .. ( event and "poll" or "event" ) )
	elseif not event.poll.choices[ index ] then
		return report( 4, "Cannot remove poll option because there is no poll option #" .. index .. " in users ("..name..") event" )
	else
		local val = table.remove( event.poll.choices, index )

		for user, choice in pairs( event.poll.responses ) do
			if choice == index then
				-- Notify user that their vote has been discarded
				event.poll.responses[ user ] = nil

				Reporter.warning( self.worker.client:getUser( user ), "Vote discarded", "The vote you cast on the current event poll has been discarded because the option you voted on is *no longer available*. Please consider re-casting a vote for another option." )
			elseif choice > index then event.poll.responses[ user ] = choice - 1 end
		end

		self:saveEvents( event.poll )
		self:refreshRemote( true )

		return Logger.s( "Removed poll option for user " .. name )
	end
end

--[[
	@instance
	@desc
]]
function EventManager:submitPollVote( userID, index )
	local name, event = self.worker.client:getUser( userID ).fullname, self:getPublishedEvent()
	Logger.i( "Submitting poll vote for " .. name, userID .. " for option " .. tostring( index ) )

	index = tonumber( index )
	if not ( index and event.poll.choices[ index ] ) then
		return report( index and 2 or 1, "Cannot remove poll option. Index provided '" .. index .. "' is invalid. Provide a valid index that represents a present option" )
	elseif not ( event and event.poll ) then
		return report( event and 4 or 3, "Refusing to remove poll option because user ("..name..") has no " .. ( event and "poll" or "event" ) )
	else
		event.poll.responses[ userID ] = index
		self:saveEvents( event.poll )
		self:refreshRemote()

		return Logger.s( "Cast poll vote on option '"..event.poll.choices[ index ].."' ("..index..") for " .. name )
	end
end


extends "Manager"
return EventManager:compile()
