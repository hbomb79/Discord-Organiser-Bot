local Logger = require "src.client.Logger"
local Reporter = require "src.helpers.Reporter"

--[[
	WIP
]]

Logger.d "Building commands list (commands.lua)"
-- format: command = { help = "help desc", admin = true|false, action = function };
-- If 'admin' then only users that are administrators on the BGnS guild will be able to execute
local commands = {
	help = {
		help = "Display this help menu.\n\nRun **!help commands [command1, command2, ...]** to see help on the given commands (eg: **!help commands create cancel** gives help for the *create* and *cancel* command).",
	},

	create = {
		help = "",
		action = function( worker, message )
			local user = message.author
			local userID = user.id
			Logger.i( "Attempting to create a new event for user " .. tostring( user.fullname ) )

			local ev = worker.eventManager:getEvent( userID )
			if ev then
				Logger.w "User already has a registered event -- notifying user"
				Reporter.warning( user, "Event already exists", "You already own an event. " .. ( ev.published and "Use **!delete** to unpublish and remove your event" or "Use **!cancel** to allow a new event to be made" ) )
				return
			end

			if worker.eventManager:createEvent( userID ) then
				Logger.i("Created new event -- notifying user")
				Reporter.success( user, "Created event", "Your event has been successfully created.\n\nCustomize it using any of: !setTitle, !setLocation, !setTimeframe, !setDesc (for each 'set' command their is a 'get' version too)!\n\n*Happy hosting!*")
			else
				Logger.w("Failed to create new event -- notifying user")
				Reporter.warning( user, "Failed to create new event", "Please try again later." )
			end
		end
	},

	cancel = {
		help = "",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to cancel owned event for user " .. tostring( user.fullname ) )

			local event = events:getEvent( userID )
			if not event then
				Logger.w( "Failed to cancel event -- the user owns no events. Notifying user." )
				Reporter.warning( user, "Failed to cancel event", "You don't own any unpublished events." )
			elseif event.published then
				Logger.w( "Failed to cancel event -- the user has already published their event. Notifying user." )
				Reporter.failure( user, "Failed to cancel event", "You're event has already been published. Use **!delete** to unpublish AND remove your event", { name = "Warning", value = "Deleting an event will remove all RSVPs to the event -- members that RSVP'd will be notified. RSVPs are unrecoverable." } )
			else
				if events:removeEvent( userID, true ) then
					Logger.i "Event cancelled"
					Reporter.success( user, "Event cancelled", "Your event has been successfully cancelled. No further action is required" )
				else
					Logger.w "Unknown error occurred while cancelling event"
					Reporter.failure( user, "Failed to cancel event", "An unknown exception has occurred while trying to cancel your event. Notify <@157827690668359681> of this issue" )
				end
			end
		end
	},

	delete = {
		help = "",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to delete published event for user " .. tostring( user.fullname ), userID )

			local event = events:getEvent( userID )
			if not event or not event.published then
				Logger.w( "Failed to delete event data -- the user owns no published events" )
				Reporter.warning( user, "Failed to delete event", "You don't own any published events. Perhaps you meant to use **!cancel**?" )
			else
				if events:removeEvent( userID ) then
					Logger.i( "Successfully deleted (unpublished and discarded) event" )
					Reporter.success( user, "Event deleted", "Your event has been successfully deleted. No further action is required", { name = "Attendees", value = "It is important to note that all RSVP information has been lost. All users who responded to this event have been notified of the event's removal" })
				else
					Logger.w( "Failed to unpublish" )
					Reporter.failure( user, "Failed to unpublish event", "Please try again later, or contact <@157827690668359681> directly for removal" )
				end
			end
		end
	},

	publish = {
		help = "",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to publish event for user " .. user.fullname, userID )

			local event, current = events:getEvent( userID ), events:getPublishedEvent()
			if not event then
				Logger.w "User has no events but is trying to publish. Notifying user."
				Reporter.warning( user, "Failed to publish", "You don't own any events. Create an event using **!create** before trying to publish" )
			elseif current then
				if event.author == userID then
					Logger.w "User has already published their event"
					Reporter.warning( user, "Already published", "Your event is already published -- you can see it in the BGnS planning chat. Un-publish with **!unpublish**, or delete completely with **!delete**.\n\nYou can still change details of your event, anyone that has RSVP'd will be notified (via direct messaging) of any changes you make.")
				else
					Logger.w "Another event has already been published"
					Reporter.warning( user, "Another Event Is Active", "An event has been published by someone else. You will not be able to publish your event until their event has concluded.\n\nIf you feel this is in error, contact the event owner (<@"..current.author..">).")
				end
			else
				if events:publishEvent( userID ) then
					Reporter.success( user, "Published Event", "Your event has been published. View it now in the planning chat in BGnS.")
				else
					Reporter.failure( user, "Failed to Publish Event", "Your event could not be published due to an unknown error. Please try again later, or contact <@157827690668359681> to report")
				end
			end
		end
	},

	unpublish = {
		help = "",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to unpublish event. Checking that author of published event matches the issuer of the command ("..user.fullname.." ["..userID.."])" )

			local published = events:getPublishedEvent()
			if not published then
				return Logger.w "Cannot unpublish event, no event is published"
			elseif published.author ~= userID then
				return Logger.w "Cannot unpublish event. The author of the currently published event does not match the issuer of this command"
			end

			Logger.s "Confirmed published event is owned by command issuer"
			events:unpublishEvent()
		end
	},
	view = {
		help = ""
	},

	banUser = {
		help = ""
	},
	unbanUser = {
		help = ""
	}
}

return commands