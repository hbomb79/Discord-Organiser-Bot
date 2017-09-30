local Logger = require "src.client.Logger"
local Reporter = require "src.helpers.Reporter"
local Worker = require "src.client.Worker"
local CommandHandler = require "src.lib.class".getClass "CommandHandler"

--[[
	WIP
]]

Logger.d "Building commands list (commands.lua)"
-- format: command = { help = "help desc", admin = true|false, action = function };
-- If 'admin' then only users that are administrators on the BGnS guild will be able to execute
local commands
commands = {
	help = {
		help = "Display this help menu.\n\nRun **!help commands [command1, command2, ...]** to see help on the given commands (eg: **!help commands create cancel** gives help for the *create* and *cancel* command).",
		action = function( worker, message, _, ... )
			local args = { ... }
			if args[ 1 ] == "commands" then
				if args[ 2 ] then
					Logger.i "Serving help information for requested commands"
					local fields, invalidFields = {}, {}
					for i = 2, #args do
						local com = args[ i ]
						if commands[ com ] then
							local h = commands[ com ].help
							Logger.d( "Serving help for cmd " .. com )
							fields[ #fields + 1 ] = { name = "__!".. com .. "__", value = ( com.admin and "*This command can only be executed by BGnS administrators*\n\n" or "" ) .. ( #h == 0 and "**HELP UNAVAILABLE**" or h ) }
						else
							Logger.w( "Help information not available for "..com )
							invalidFields[ #invalidFields + 1 ] = com
						end
					end

					Reporter.info( message.author, "Command Help", "Below is a list of help information for each of the commands you requested", unpack( fields ) )

					if #invalidFields >= 1 then
						local str = ""
						for i = 1, #invalidFields do
							str = str .. "'" .. invalidFields[ i ] .. "'"
							if i ~= #invalidFields then str = str .. ( #invalidFields - i > 1 and ", " or " or " ) end
						end

						Reporter.warning( message.author, "Command Help", "We could not find command help for " .. str .. " because the commands don't exist" )
					end
				else
					local fields = {}
					for name, config in pairs( commands ) do
						fields[ #fields + 1 ] = { name = "__!" .. name .. "__", value = ( config.admin and "*This command can only be executed by BGnS administrators*\n\n" or "" ) .. ( #config.help == 0 and "**HELP UAVAILABLE**" or config.help ) }
					end

					Reporter.info( message.author, "Command Help", "Below is a list of help information for each of the commands you can use. " .. tostring( #fields ), unpack( fields ) )
				end
			else
				Reporter.info( message.author, "Hoorah! You're ready to learn a little bit about meee!", "Using this bot is dead simple! Before we get going select what information you need\n\n", 
					{ name = "Hosting", value = "To host an event use the **!create** command inside this DM.\nOnce created you will be sent more instructions here (regarding configuration and publishing of your event)" },
					{ name = "Responding", value = "If you want to let the host of an event know whether or not you're coming, use **!yes**, **!no** or **!maybe** inside this DM. The event manager will be notified." },
					{ name = "Current Event", value = "If you'd like to see information regarding the current event visit the $HOST_CHANNEL inside the $GUILD (BG'n'S server)." },
					{ name = "Further Commands", value = "Use **!help commands** to see information on all commands.\n\nIf you're only interested in certain commands, provide the names of the commands as well to see information for those commands only (eg: !help commands create)."}
				)
			end
		end
	},

	create = {
		help = "Creates a new event for the user. If an event already exists (published or not) the command will refuse to complete",
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

				worker.messageManager:setPromptMode( userID, CommandHandler.PROMPT_MODE_ENUM.CREATE_TITLE )
			else
				Logger.w("Failed to create new event -- notifying user")
				Reporter.warning( user, "Failed to create new event", "Please try again later." )
			end
		end
	},

	cancel = {
		help = "Removes an UNPUBLISHED event from the records. This has no affect on any other user.\n\nAll data tied to this event will be lost",
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
		help = "Removed a PUBLISHED event from the records. All users that RSVP'd to the event will be notified of it's removal.\n\nAll data tied to this event will be lost",
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
		help = "Pushes your current event to the BGnS server, allowing other users to see the event and RSVP via DMs to this bot",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to publish event for user " .. user.fullname, userID )

			local event, current = events:getEvent( userID ), events:getPublishedEvent()
			if not event then
				Logger.w "User has no events but is trying to publish. Notifying user."
				Reporter.warning( user, "Failed to publish", "You don't own any events. Create an event using **!create** before trying to publish" )
			elseif current then
				if current.author == userID then
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
		help = "Similar to delete, but doesn't remove event data after unpublishing. All users that RSVP'd to the event will be notified that it is no longer published",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to unpublish event. Checking that author of published event matches the issuer of the command ("..user.fullname.." ["..userID.."])" )

			local published = events:getPublishedEvent()
			if not published then
				Logger.w "Cannot unpublish event, no event is published"
				Reporter.warning( user, "Failed to Unpublish Event", "No event has been published" )
			elseif published.author ~= userID then
				Logger.w "Cannot unpublish event. The author of the currently published event does not match the issuer of this command"
				Reporter.warning( user, "Failed to Unpublish Event", "You do not own the currently published event. Contact the event host <@"..published.author.."> for more information" )
			else
				Logger.s "Confirmed published event is owned by command issuer"
				if events:unpublishEvent() then
					Reporter.success( user, "Unpublished Event", "Your event has been unpublished. If you want to delete it entirely use **!cancel**" )
				else
					Reporter.failure( user, "Failed to Unpublish Event", "Your event could not be unpublished due to an unknown error. Please try again later, or contact <@157827690668359681> to report" )
				end
			end
		end
	},

	refreshRemote = {
		help = "Forces the bot to refresh the BGnS server. If an event is published it will be refreshed on the server.\n\nThe bot should automatically push to remote so only use this command if the bot failed.",
		admin = true,
		action = function( worker, message ) worker.eventManager:refreshRemote( true ); Reporter.success( message.author, "Remote refreshed", "The BGnS server has been refreshed to show most recent information" ) end
	},

	revokeRemote = {
		help = "Forces the bot to unpublish the currently published event. The event host will be notified. It is suggested that troublesome users be banned using **!banUser**.",
		admin = true,
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " is attempting to revoke remote." )

			local ev = events:getPublishedEvent()
			if not ev then
				Logger.w( "Unable to revoke remote. No event is currently pushed." )
				Reporter.failure( user, "Failed to revoke remote", "No event is currently published so no event can be revoked." )

				return
			end

			local issuerLevel, authorLevel = worker:getAdminLevel( userID ), worker:getAdminLevel( ev.author )
			if ev.author == userID or ( not authorLevel or authorLevel > issuerLevel ) then
				Logger.s( "User is within their rights to revoke event" )
				events:unpublishEvent()

				Reporter.success( user, "Event revoked", "The published event has been revoked -- the event host will be notified" )
				Reporter.failure( worker.client:getUser( ev.author ), "Your event has been revoked", "Your event has been forcefully revoked from the BGnS server. If you believe this is in error, or wish to learn more about why this decision was made, contact <@"..userID..">" )

				return true
			end
		end
	},

	createPoll = {
		help = "Creates a poll on the current event",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " is attempting to create a poll on their event" )

			local ev = events:getEvent( userID )
			if not ev then
				Logger.w( "Cannot create poll. User " .. user.fullname, userID .. " has no event" )
				return Reporter.warning( user, "Failed to create poll", "You don't own an event. Create an event using **!create** before trying to create a poll" )
			elseif ev.poll then
				Logger.w( "Refusing to create poll. User " .. user.fullname, userID .. " already has a poll on their event -- creating another would overwrite the current poll" )
				return Reporter.warning( user, "Failed to create poll", "You already have an active poll on your event. Use **!deletePoll** to remove your other poll" )
			else
				if events:createPoll( userID ) then
					return Reporter.success( user, "Created poll", "Your poll has been created. Edit the description with **!setPollDesc** and add/remove/list options with **!addPollOption**, **!removePollOption** and **!listPollOptions**\n\nRemove the poll using **!deletePoll**. The poll will appear under your event while it is published (**!publish**)" )
				else
					Logger.e( "Failed to create poll for " .. user.fullname, userID )
					return Reporter.failure( user, "Failed to create poll", "An unknown error has occurred which prevented the creation of your poll. Please try again later -- if issue persists contact <@157827690668359681> to report")
				end
			end
		end
	},

	setPollDesc = {
		help = "Set's the description of the poll attached to the users event",
		action = function( worker, message, desc )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " attempting to set poll description" )

			local ev = events:getEvent( userID )
			if not ev then
				Logger.w( "Cannot edit poll desc. User " .. user.fullname, userID .. " has no event" )
				return Reporter.warning( user, "Failed to edit poll", "You don't own an event. Create an event using **!create** before editing a poll" )
			elseif not ev.poll then
				Logger.w( "Cannot edit poll desc. User " .. user.fullname, userID .. " has no poll" )
				return Reporter.warning( user, "Failed to edit poll", "You don't have a poll. Create a poll using **!createPoll** before editing a poll" )
			else
				if events:setPollDesc( userID, desc ) then
					return Reporter.success( user, "Edited poll", "Your poll description has been edited" )
				else
					Logger.e( "Failed to edit poll for " .. user.fullname, userID )
					return Reporter.failure( user, "Failed to edit poll", "An unknown error has occurred which prevented editing your poll. Please try again later -- if issue persists contact <@157827690668359681> to report")
				end
			end
		end
	},

	addPollOption = {
		help = "Adds a poll option the poll attached to the users event",
		action = function( worker, message, choice )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " attempting to add poll option" )

			local ev = events:getEvent( userID )
			if not ev then
				Logger.w( "Cannot edit poll choices. User " .. user.fullname, userID .. " has no event" )
				return Reporter.warning( user, "Failed to edit poll", "You don't own an event. Create an event using **!create** before editing a poll" )
			elseif not ev.poll then
				Logger.w( "Cannot edit poll choices. User " .. user.fullname, userID .. " has no poll" )
				return Reporter.warning( user, "Failed to edit poll", "You don't have a poll. Create a poll using **!createPoll** before editing a poll" )
			elseif #ev.poll.choices >= 10 then
				Logger.w( "Refusing to edit poll choices. User " .. user.fullname, userID .. " already has 10 options saved." )
				return Reporter.failure( user, "Failed to edit poll", "You have reached the maximum amount of poll choices (10). Remove some options using **!removePollOption**")
			elseif not ( choice and choice:find "%w" ) then
				worker.messageManager:setPromptMode( userID, CommandHandler.PROMPT_MODE_ENUM.POLL_CHOICE_ADD )
			else
				if events:addPollOption( userID, choice ) then
					Reporter.success( user, "Edited poll", "Your new option has been added to your poll at position " .. #ev.poll.choices .. ". Use **!removePollOption " .. #ev.poll.choices .. "** to remove this choice, or **!listPollOptions** to see all choices" )
					return true
				else
					Logger.e( "Failed to edit poll for " .. user.fullname, userID )
					return Reporter.failure( user, "Failed to edit poll", "An unknown error has occurred which prevented editing your poll. Please try again later -- if issue persists contact <@157827690668359681> to report" )
				end
			end
		end
	},

	listPollOptions = {
		help = "Lists the poll options for the poll attached to the users event",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " attempting to list poll choices" )

			local ev = events:getEvent( userID )
			if not ev then
				Logger.w( "Cannot view poll options. User " .. user.fullname, userID .. " has no event" )
				return Reporter.warning( user, "Failed to view poll", "You don't own an event. Create an event using **!create** before editing a poll" )
			elseif not ev.poll then
				Logger.w( "Cannot view poll options. User " .. user.fullname, userID .. " has no poll" )
				return Reporter.warning( user, "Failed to view poll", "You don't have a poll. Create a poll using **!createPoll** before editing a poll" )
			else
				local choices, str = ev.poll.choices, ""
				if #choices == 0 then
					Reporter.info( user, "Poll Options", "No options. Add one by using **!addPollOption**.\n\nYour poll won't display on the BGnS server until it has options attached to it" )
				else
					for i = 1, #choices do
						str = str .. ( "%s) %s%s" ):format( i, choices[ i ], ( i == #choices and "" or "\n\n" ) )
					end

					Reporter.info( user, "Poll Options", str )
				end
			end
		end
	},

	removePollOption = {
		help = "Removes the poll option at the index provided: **!removePollOption [index]**\n\nIf index is nil (not provided or invalid number) then a list of poll options is shown and the user is asked which option to remove",
		action = function( worker, message, index )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " attempting to remove poll choice" )

			index = tonumber( index )
			local ev = events:getEvent( userID )
			if not ev then
				Logger.w( "Cannot view poll options. User " .. user.fullname, userID .. " has no event" )
				return Reporter.warning( user, "Failed to edit poll", "You don't own an event. Create an event using **!create** before editing a poll" )
			elseif not ev.poll then
				Logger.w( "Cannot view poll options. User " .. user.fullname, userID .. " has no poll" )
				return Reporter.warning( user, "Failed to edit poll", "You don't have a poll. Create a poll using **!createPoll** before editing a poll" )
			else
				local choices, str = ev.poll.choices, ""
				if #choices == 0 then
					return Reporter.warning( user, "Cannot remove option", "You have no options stored on you poll. Add them using **!addPollOption**" )
				elseif not index then
					Logger.i( "Command was not issued with a target option. Displaying options for removal." )
					for i = 1, #choices do
						str = str .. ( "%s) %s%s" ):format( i, choices[ i ], ( i == #choices and "" or "\n\n" ) )
					end

					Reporter.info( user, "Poll Options", str )
					if worker.messageManager.promptModes[ userID ] == CommandHandler.PROMPT_MODE_ENUM.POLL_REMOVE then
						Reporter.failure( user, "Invalid index", "The index provided is invalid. Please retry with a valid index (a integer that corresponds to an option in the list)" )
					else
						worker.messageManager:setPromptMode( userID, CommandHandler.PROMPT_MODE_ENUM.POLL_REMOVE )
					end
				else
					if events:removePollOption( userID, index ) then
						Reporter.success( user, "Removed poll option", "We removed that option for you. Use **!listPollOptions** to see the remaining options for your poll" )
						return true
					else
						Reporter.failure( user, "Failed to remove poll option", "An unkown error occured. Ensure that a poll option at index '"..index.."' exists before retrying" )
					end
				end
			end
		end
	},

	deletePoll = {
		help = "Remove the poll attached to your event. If the event is published the remote is refreshed",
		action = function( worker, message )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "User " .. user.fullname .. " is attempting to delete poll" )

			local ev = events:getEvent( userID )
			if not ev then
				Logger.w( "Cannot delete poll. User " .. user.fullname, userID .. " has no event" )
				return Reporter.warning( user, "Failed to delete poll", "You don't own an event." )
			elseif not ev.poll then
				Logger.w( "Cannot delete poll. User " .. user.fullname, userID .. " has no poll attached to their event" )
				return Reporter.warning( user, "Failed to delete poll", "You don't have a poll." )
			else
				if events:deletePoll( userID ) then
					Reporter.success( user, "Deleted poll", "Your poll has been deleted." .. ( ev.published and " It has been revoked from the remote server (BGnS server) and can no longer be voted on" or "" ) )
				else
					Reporter.failure( user, "Cannot delete poll", "An unknown error has occurred which prevented editing your poll. Please try again later -- if issue persists contact <@157827690668359681> to report" )
				end
			end
		end
	},

	yes = {
		help = "Tell the host of the published event that you *are attending*",
		action = function( worker, message ) worker.eventManager:respondToEvent( message.author.id, 2 ) end
	},

	maybe = {
		help = "Tell the host of the published event that you *might be attending*",
		action = function( worker, message ) worker.eventManager:respondToEvent( message.author.id, 1 ) end
	},

	no = {
		help = "Tell the host of the published event that you *not attending*",
		action = function( worker, message ) worker.eventManager:respondToEvent( message.author.id, 0 ) end
	},

	view = {
		help = "NYI"
	},

	banUser = {
		help = "Ban the userID provided from interacting with the bot. Command must be provided with a resolvable userID (member of cached guild)\n\nThe user will be notified",
		admin = true,
		action = function( worker, message, banTargetID )
			local user, events = message.author, worker.eventManager
			local userID = user.id

			local banTarget = worker.client:getUser( banTargetID )
			if not banTarget then
				Logger.w( "Failed to perform ban. User: " .. banTargetID, "Is not valid" )
				return Reporter.warning( user, "Failed to ban", "The provided userID **"..banTargetID.."** is invalid. Please provide a valid userID" )
			elseif worker.messageManager.restrictionManager.bannedUsers[ banTargetID ] then
				Logger.w( "Failed to perform ban. User " .. banTarget.fullname, banTargetID .. " is already banned" )
				return Reporter.warning( user, "Failed to ban", "User " .. banTarget.fullname .. " already banned. Use **!unbanUser " .. banTarget .. "** to unban user" )
			end

			Logger.i( "User " .. user.fullname .. " is attempting to ban user " .. banTarget.fullname )
			local issuerAdminLevel, targetAdminLevel = worker:getAdminLevel( userID ), worker:getAdminLevel( banTargetID )
			if banTargetID == userID then
				Logger.e( "User " .. user.fullname .. " tried to ban themselves. Rejecting request" )
				return Reporter.failure( user, "Failed to ban", "You cannot ban yourself, silly!" )
			elseif targetAdminLevel and issuerAdminLevel > targetAdminLevel then
				-- Target has a higher rank than issuer
				Logger.w( "Refusing to ban user. User " .. banTarget.fullname .. " is a higher rank than the command issuer" )
				Reporter.warning( user, "Refusing to ban user", "Your account is a lower administrator level than the ban target." )
			else
				Logger.s( "Issuer of command is within rights to ban" )
				if worker.messageManager.restrictionManager:banUser( banTarget.id ) then
					Logger.s( "Banned user " .. banTarget.fullname )
					Reporter.success( user, "Banned user", "User " .. banTarget.fullname .. " has been banned. Future interactions initiated by this user will be ignored.\n\nThe user has been notified." )
					Reporter.failure( banTarget, "You have been banned", "A BGnS administrator has banned you from interacting with this bot. Contact <@"..userID.."> if you believe this is in error" )
				else
					Reporter.failure( user, "Failed to ban user", "Unknown error occurred. Please try again later" )
				end
			end
		end
	},

	unbanUser = {
		help = "Lifts a ban on the userID provided. Command must be provided with a resolvable userID (member of cached guild)\n\nThe user will be notified",
		admin = true,
		action = function( worker, message, unbanTargetID )
			local user, events = message.author, worker.eventManager
			local userID = user.id

			local banTarget = worker.client:getUser( unbanTargetID )
			if not banTarget then
				Logger.w( "Failed to perform unban. User: " .. unbanTargetID, "Is not valid" )
				return Reporter.warning( user, "Failed to unban", "The provided userID **"..unbanTargetID.."** is invalid. Please provide a valid userID" )
			elseif not worker.messageManager.restrictionManager.bannedUsers[ unbanTargetID ] then
				Logger.w( "Failed to lift user ban on " .. banTarget.fullname, "User is not banned" )
				return Reporter.warning( user, "Failed to lift ban", banTarget.fullname .. " is not banned" )
			end

			Logger.i( "User " .. user.fullname .. " is attempting to lift ban on user " .. banTarget.fullname )
			if worker.messageManager.restrictionManager:unbanUser( banTarget.id ) then
				Logger.s( "Unbanned user " .. banTarget.fullname )
				Reporter.success( user, "Lifted user ban", "User " .. banTarget.fullname .. " has been unbanned. \n\nThe user has been notified." )
				Reporter.success( banTarget, "You have been un-banned", "A BGnS administrator has explicitly lifted your ban. You are now free to interact with this bot (within reason -- spam will automatically trigger a permanent suspension)." )
			else
				Reporter.failure( user, "Failed to lift user ban", "Unknown error occurred. Please try again later" )
			end
		end
	}
}

-- Generate commands dynamically for the following properties. The function will simply change the property key-value of the users event.
local VALID_FIELDS = { "title", "desc", "timeframe", "location" }
for i = 1, #VALID_FIELDS do
	local field = VALID_FIELDS[ i ]

	local name = field:sub( 1, 1 ):upper() .. field:sub( 2 )
	commands[ "set" .. name ] = {
		help = "Set the field " .. field .. " on your event to the value provided (eg: !set" .. name .. " This is my title).\n\nIf the event is published all users that have RSVP'd will be notified of the change.",
		action = function( worker, message, value )
			local user, events = message.author, worker.eventManager
			local userID = user.id
			Logger.i( "Attempting to set '"..field.."' to " .. value .."' for event owned by " .. user.fullname, userID )

			if not events:getEvent( userID ) then
				Logger.w( "Cannot set field " .. field .." because the user (".. user.fullname ..") has no event" )
				local current = events:getPublishedEvent()
				Reporter.warning( user, "Failed to set " .. field, "You don't own any events. Create one using **!create**", current and { name = "Change current event details", value = "As of this version (of the bot), only the event author can change details regarding the current event. Contact the host here: <@" .. current.author .. ">"} or nil )
			else
				if events:updateEvent( userID, field, value ) then
					Logger.s "Updated event successfully"
					Reporter.success( user, "Successfully set field", "The " .. field .. " property for your event is now '".. value.."'.")

					return true
				else
					Logger.e( "Failed to set field '"..field.."' for event owned by " .. tostring( user.fullname ) )
					Reporter.failure( user, "Failed to set " .. field, "Unknown error occurred. Please try again later, or contact <@157827690668359681> directly for assistance" )
				end
			end
		end
	}

	commands[ "get" .. name ] = {
		help = "Returns the value for the field '" .. field .. "' in your event.",
		action = function( worker, message, ... )
			local user, events = message.author, worker.eventManager
			Logger.i( "Attempting to get field '"..field.."' for event owned by " .. user.fullname, user.id )

			local e = events:getEvent( user.id )
			if not e then
				local current = events:getPublishedEvent()
				Reporter.warning( user, "Failed to get " .. field, "You don't own any events. Create one using **!create**", current and { name = "Get current event details", value = "See the BGnS planning channel for information regarding the current event" } or nil )
			else
				Logger.i( "Returning information for field '"..tostring( field ).."'" )
				Reporter.info( user, "Property - " .. name, "The " .. field .. " property for your event is '"..tostring( e[ field ] ).."'. Change with **!set" .. name .. "**" )
			end
		end
	}
end

return commands