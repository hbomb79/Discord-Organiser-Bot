local function splitArguments( val )
    local parts = {}
    for match in val:gmatch "(%S+)%s*" do parts[ #parts + 1 ] = match end

    return parts
end

local COMMAND_HELP = {
	help = "When called, the bot will reply with information regarding how to use it's basic commands (!create, !yes, !no, etc..)",
	create = "Creates a new event for the user. If an event already exists (published or not) the command will refuse to complete",
	cancel = "Removes an UNPUBLISHED event from the records. This has no affect on any other user.\n\nAll data tied to this event will be lost",
	delete = "Removed a PUBLISHED event from the records. All users that RSVP'd to the event will be notified of it's removal.\n\nAll data tied to this event will be lost",
	unpublish = "Similar to delete, but doesn't remove event data after unpublishing. All users that RSVP'd to the event will be notified that it is no longer published"
}

local VALID_COMMANDS = {
	help = function( commands, message, _, ... )
		local args = { ... }
		if args[ 1 ] == "commands" then
			if args[ 2 ] then
				log.i("Serving help information for requested commands")
				for i = 2, #args do
					local com = args[ i ]
					if COMMAND_HELP[ com ] then
						log.i("Serving help for cmd " .. com)
						reporter:send( message.author, "Help ["..com.."]", COMMAND_HELP[ com ] )
					else
						log.w("Help information not available for "..com)
						reporter:send( message.author, "Help ["..com.."]", "Unknown command '"..com.."'" )
					end
				end
			else
				for name, desc in pairs( COMMAND_HELP ) do
					reporter:send( message.author, "Help ["..name.."]", desc )
				end
			end
		else
			message.author:sendMessage {
				embed = {
					title = "Hoorah! You're ready to learn a little bit about meee!",
					description = "Using this bot is dead simple! Before we get going select what information you need\n\n",
					fields = {
						{ name = "Hosting", value = "To host an event use the **!create** command inside this DM.\nOnce created you will be sent more instructions here (regarding configuration and publishing of your event)" },
						{ name = "Responding", value = "If you want to let the host of an event know whether or not you're coming, use **!yes**, **!no** or **!maybe** inside this DM. The event manager will be notified." },
						{ name = "Current Event", value = "If you'd like to see information regarding the current event visit the $HOST_CHANNEL inside the $GUILD (BG'n'S server)." },
						{ name = "Further Commands", value = "Use **!help commands** to see information on all commands.\n\nIf you're only interested in certain commands, provide the names of the commands as well to see information for those commands only (eg: !help commands create)."}
					}
				}
			}
		end
	end,

	create = function( commands, message, ... )
		local user = message.author
		log.i("Attempting to create a new event for user " .. tostring( user ))

		local ev = events:getEvent( user )
		if ev then
			log.i("User already has a registered event -- notifying user")
			-- There is already an event for this user, tell them to remove it first
			reporter:send( user, "Event already exists", "You already own an event. " .. ( ev.published and "Use **!delete** to unpublish and remove your event" or "Use **!cancel** to allow a new event to be made" ) )
			return
		end

		if events:createEvent( user ) then
			log.i("Created new event -- notifying user")
			reporter:send( user, "Created event", "Your event has been successfully created.")
		else
			log.w("Failed to create new event -- notifying user")
			reporter:send( user, "Failed to create new event", "Please try again later." )
		end
	end,

	cancel = function( commands, message, ... )
		local user = message.author
		local event = events:getEvent( user )

		log.i( "Attempting to cancel event creation for user "..tostring( user ) )
		if not event then
			log.w( "Failed to cancel event -- the user owns no events. Notifying user." )
			reporter:send( user, "Failed to cancel event", "You don't own any unpublished events." )
		elseif event.published then
			log.w( "Failed to cancel event -- the user has already published their event. Notifying user." )
			reporter:send( user, "Failed to cancel event", "You're event has already been published. Use **!delete** to unpublish AND remove your event", { name = "WARNING", value = "Deleting an event will remove all RSVPs to the event without warning. This action is irreversible" } )
		else
			if events:cancelEvent( user ) then
				log.i( "Event cancelled" )
				reporter:send( user, "Event cancelled", "Your event has been successfully cancelled. No further action is required" )
			else
				log.w( "Unknown error occurred while cancelling event" )
				reporter:send( user, "Failed to cancel event", "An unknown exception has occurred while trying to cancel your event. Notify <@157827690668359681> of this issue" )
			end
		end
	end,

	delete = function( commands, message, ... )
		local user = message.author
		local e = events:getEvent( user )

		log.i( "Attempting to delete published event for user " .. tostring( user ) )
		if not e or not e.published then
			log.w( "Failed to delete event data -- the user owns no published events" )
			reporter:send( user, "Failed to delete event", "You don't own any published events. Perhaps you meant to use **!cancel**?" )
		else
			if events:unpublish( user ) then
				if events:cancelEvent( user ) then
					log.i( "Successfully deleted (unpublished and discarded) event" )
					reporter:send( user, "Event deleted", "Your event has been successfully deleted. No further action is required", { name = "Attendees", value = "It is important to note that all RSVP information has been lost. All users who responded to this event have been notified of the event's removal" })
				else
					log.w( "Unpublished event but failed to cancel")
					reporter:send( user, "Failed to fully removed event", "You're event has been successfully unpublished, however it could not be fully removed. Try running **!cancel** later." )
				end
			else
				log.w( "Failed to unpublish" )
				reported:send( user, "Failed to unpublish event", "Please try again later, or contact <@157827690668359681> directly for removal" )
			end
		end
	end
}

-- Generate commands dynamically for the following properties. The function will simply change the property key-value of the users event.
local VALID_FIELDS = { "title", "description", "timeframe", "location" }
for i = 1, #VALID_FIELDS do
	local field = VALID_FIELDS[ i ]

	local name = field:sub( 1, 1 ):upper() .. field:sub( 2 )
	COMMAND_HELP[ "set" .. name ] = "Set the field " .. field .. " on your event to the value provided (eg: !set" .. name .. " This is my title).\n\nIf the event is published all users that have RSVP'd will be notified of the change."
	VALID_COMMANDS[ "set" .. name ] = function( command, message, ... )
		local user = message.author
		if not events:getEvent( user ) then
			-- This user owns no event
			log.w("Cannot set field " .. field .." because the user ("..tostring( user )..") has no event")
			local current = events:getCurrentEvent()
			reporter:send( user, "Failed to set " .. field, "You don't own any events. Create one using **!create**", current and { name = "Change current event details", value = "As of this version (of the bot), only the event author can change details regarding the current event. Contact the host here: <@" .. current.author .. ">"} or nil )
		else
			if not events:updateEvent( user, field, ... ) then
				log.c("Failed to set field '"..field.."' for event owned by " .. tostring( user ))
				reporter:send( user, "Failed to set " .. field, "Unknown error occurred. Please try again later, or contact <@157827690668359681> directly for assistance" )
			end
		end
	end

	COMMAND_HELP[ "get" .. name ] = "Returns the value for the field '" .. field .. "' in your event."
	VALID_COMMANDS[ "get" .. name ] = function( command, message, ... )
		local user = message.author
		local e = events:getEvent( user )
		if not e then
			local current = events:getCurrentEvent()
			reporter:send( user, "Failed to get " .. field, "You don't own any events. Create one using **!create**", current and { name = "Get current event details", value = "See the BGnS planning channel for information regarding the current event" } or nil )
		else
			log.i("Returning information for field '"..tostring( field ).."'")
			reporter:send( user, "Property - " .. name, "The " .. field .. " property for your event is '"..tostring( e[ field ] ).."'. Change with **!set" .. name .. "**" )
		end
	end
end

return {
	check = function() return HOST_CHANNEL and CLIENT and CHANNEL and GUILD end,
	fragmentCommand = function( self, message )
		return { message.content:match "%!(%w+)%s*(.*)$" }
	end,

	checkCommand = function( self, message )
		local p = self:fragmentCommand( message )
		return #p > 0 and p or false
	end,

	runCommand = function( self, message, parts )
		parts = parts or self:fragmentCommand( message )
		
		if VALID_COMMANDS[ parts[ 1 ] ] then
			VALID_COMMANDS[ parts[ 1 ] ]( self, message, parts[ 2 ], unpack( splitArguments( parts[ 2 ] ) ) )
		else
			reporter:send( message.author, "Invalid command", "The command you sent was of valid syntax but references an unknown command. Did you make a typing mistake?" )
		end
	end
}