local Logger = require "src.client.Logger"
local Reporter = require "src.helpers.Reporter"
local Worker = require "src.client.Worker"
local CommandHandler = require "src.lib.class".getClass "CommandHandler"

local function report( code, ... )
	local _, reason = Logger.w( ... )
	return false, reason, code
end

local function splitArguments( val )
    local parts = {}
    for match in val:gmatch "(%S+)%s*" do parts[ #parts + 1 ] = match end

    return parts
end

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
		action = function( evManager, user, message, arg )
			local args = splitArguments( arg )
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

					Reporter.info( user, "Command Help", "Below is a list of help information for each of the commands you requested", unpack( fields ) )

					if #invalidFields >= 1 then
						local str = ""
						for i = 1, #invalidFields do
							str = str .. "'" .. invalidFields[ i ] .. "'"
							if i ~= #invalidFields then str = str .. ( #invalidFields - i > 1 and ", " or " or " ) end
						end

						Reporter.warning( user, "Command Help", "We could not find command help for " .. str .. " because the commands don't exist" )
					end

					return Logger.s "Served help information for selected commands"
				else
					local fields = {}
					for name, config in pairs( commands ) do
						fields[ #fields + 1 ] = { name = "__!" .. name .. "__", value = ( config.admin and "*This command can only be executed by BGnS administrators*\n\n" or "" ) .. ( #config.help == 0 and "**HELP UAVAILABLE**" or config.help ) }
					end

					Reporter.info( user, "Command Help", "Below is a list of help information for each of the commands you can use. " .. tostring( #fields ), unpack( fields ) )
					return Logger.s "Served help information for all commands"
				end
			else
				Reporter.info( user, "Hoorah! You're ready to learn a little bit about meee!", "Using this bot is dead simple! Before we get going select what information you need\n\n", 
					{ name = "Hosting", value = "To host an event use the **!create** command inside this DM.\nOnce created you will be sent more instructions here (regarding configuration and publishing of your event)" },
					{ name = "Responding", value = "If you want to let the host of an event know whether or not you're coming, use **!yes**, **!no** or **!maybe** inside this DM. The event manager will be notified." },
					{ name = "Current Event", value = "If you'd like to see information regarding the current event visit the $HOST_CHANNEL inside the $GUILD (BG'n'S server)." },
					{ name = "Further Commands", value = "Use **!help commands** to see information on all commands.\n\nIf you're only interested in certain commands, provide the names of the commands as well to see information for those commands only (eg: !help commands create)."}
				)

				return Logger.s "Served general help information"
			end
		end
	},

	create = {
		help = "Creates a new event for the user. If an event already exists (published or not) the command will refuse to complete",
		action = function( evManager, user, message ) return evManager:createEvent( user.id ) end,
		onSuccess = function( evManager, user, message, output )
			Reporter.success( user, "Created event", "Your event has been successfully created.\n\nCustomize it using any of: !setTitle, !setLocation, !setTimeframe, !setDesc\n\n*Happy hosting!*" )
			evManager.worker.messageManager:setPromptMode( user.id, CommandHandler.PROMPT_MODE_ENUM.CREATE_TITLE )
		end,
		onFailure = function( evManager, user, message, output )
			Reporter.warning( user, "Failed to create event", output )
		end
	},

	cancel = {
		help = "Removes an UNPUBLISHED event from the records. This has no affect on any other user.\n\nAll data tied to this event will be lost",
		action = function( evManager, user, message ) return evManager:removeEvent( user.id, true ) end,
		onSuccess = function( _, user )
			Reporter.success( user, "Cancelled event", "Your event has been removed" )
		end,
		onFailure = function( evManager, user, message, output )
			Reporter.warning( user, "Failed to cancel event", output )
		end
	},

	delete = {
		help = "Removed a PUBLISHED event from the records. All users that RSVP'd to the event will be notified of it's removal.\n\nAll data tied to this event will be lost",
		action = function( evManager, user, message ) return evManager:removeEvent( userID ) end,
		onSuccess = function( _, user )
			Reporter.success( user, "Deleted event", "Your event has been unpublished and removed from our records" )
		end,
		onFailure = function( evManager, user, message, output, errCode )
			Reporter.warning( user, "Failed to delete event", ( errCode > 2 and "Before deleting your event we tried to unpublish it from the BGnS server. We failed and he is why: " or "" ) .. output )
		end
	},

	publish = {
		help = "Pushes your current event to the BGnS server, allowing other users to see the event and RSVP via DMs to this bot",
		action = function( evManager, user, message ) return evManager:publishEvent( user.id ) end,
		onSuccess = function( _, user )
			Reporter.success( user, "Published Event", "Your event has been published. View it now in the planning chat in BGnS.")
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, "Failed to Publish Event", output )
		end
	},

	unpublish = {
		help = "Similar to delete, but doesn't remove event data after unpublishing. All users that RSVP'd to the event will be notified that it is no longer published",
		action = function( evManager ) return evManager:unpublishEvent() end,
		onSuccess = function( _, user )
			Reporter.success( user, "Unpublished Event", "Your event has been unpublished. If you want to delete it entirely use **!cancel**" )
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, "Failed to unpublish event", output )
		end
	},

	refreshRemote = {
		help = "Forces the bot to refresh the BGnS server. If an event is published it will be refreshed on the server.\n\nThe bot should automatically push to remote so only use this command if the bot failed.",
		admin = true,
		action = function( evManager ) return evManager:refreshRemote( true ) end,
		onSuccess = function( evManager, user )
			Reporter.success( user, "Remote refreshed", "The BGnS server has been refreshed to show most recent information" )
		end,
		onFailure = function( evManager, user, message, output )
			Reporter.warning( user, "Failed to refresh remote", output )
		end
	},

	revokeRemote = {
		help = "Forces the bot to unpublish the currently published event. The event host will be notified. It is suggested that troublesome users be banned using **!banUser**.",
		admin = true,
		action = function( evManager, user, message )
			local userID = user.id
			Logger.i( "Revoking remote for " .. user.fullname, userID )

			local ev = evManager:getPublishedEvent()
			if not ev then
				return report( 1, "Unable to revoke remote. No event is currently pushed." )
			end

			local issuerLevel, authorLevel = worker:getAdminLevel( userID ), worker:getAdminLevel( ev.author )
			if ev.author == userID or ( not authorLevel or authorLevel > issuerLevel ) then
				Logger.s( "User is within their rights to revoke event" )
				local ok, reason, code = evManager:unpublishEvent()
				if not ok then Logger.d "Failed to unpublish event while revoking remote"; return ok, reason, code + 2 end

				Reporter.failure( worker.client:getUser( ev.author ), "Your event has been revoked", "Your event has been forcefully revoked from the BGnS server. If you believe this is in error, or wish to learn more about why this decision was made, contact <@"..userID..">" )
				return Logger.s( "Revoked remote for user " .. user.fullname )
			else
				return report( 2, "User ("..user.fullname..") does not have the correct rights to revoke the remote" )
			end
		end,
		onSuccess = function( _, user )
			Reporter.success( user, "Event revoked", "The published event has been revoked -- the event host has been notified" )
		end,
		onFailure = function( _, user, message, output, errCode )
			Reporter.warning( user, "Failed to revoke remote", ( errCode > 2 and "In order to revoke the remote we had to unpublish the event that was currently published. We tried to unpublish and encountered an error: " or "" ) .. output )
		end
	},

	createPoll = {
		help = "Creates a poll on the current event",
		action = function( evManager, user ) return evManager:createPoll( user.id ) end,
		onSuccess = function( _, user )
			Reporter.success( user, "Created poll", "Your poll has been created. Edit the description with **!setPollDesc** and add/remove/list options with **!addPollOption**, **!removePollOption** and **!listPollOptions**\n\nRemove the poll using **!deletePoll**. The poll will appear under your event while it is published (**!publish**)" )
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, "Failed to create poll", output )
		end
	},

	setPollDesc = {
		help = "Set's the description of the poll attached to the users event",
		action = function( evManager, user, message, arg ) return evManager:setPollDesc( user.id, arg ) end,
		onSuccess = function( _, user )
			Reporter.success( user, "Set poll description", "Your poll description has been edited" )
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, "Failed to edit poll", output )
		end
	},

	addPollOption = {
		help = "Adds a poll option the poll attached to the users event",
		action = function( evManager, user, message, arg )
			if not ( arg and arg:find "%w" ) then
				evManager.worker.messageManager:setPromptMode( user.id, CommandHandler.PROMPT_MODE_ENUM.POLL_CHOICE_ADD )
				return false, "PROMPT"
			else
				return evManager:addPollOption( user.id, arg )
			end
		end,
		onSuccess = function( evManager, user )
			Reporter.success( user, "Added poll option", "Your new poll option has been added at position " .. #evManager:getEvent( user.id ).poll.choices )
		end,
		onFailure = function( evManager, user, message, output )
			if output == "PROMPT" then Logger.d "ignoring failure" return end -- The user is being prompted for their input
			Reporter.warning( user, "Failed to add poll option", output )
			evManager.worker.messageManager:setPromptMode( user.id )
		end
	},

	listPollOptions = {
		help = "Lists the poll options for the poll attached to the users event",
		action = function( evManager, user, message )
			local userID = user.id
			Logger.i( "Listing poll choices for " .. user.fullname, userID )

			local ev = evManager:getEvent( userID )
			if not ( ev and ev.poll ) then
				return report( ev and 2 or 1, "Refusing to list poll options because user ("..name..") has no " .. ( event and "poll" or "event" ) )
			else
				local choices, str = ev.poll.choices, ""
				if #choices == 0 then
					local _, reason = Logger.s( "No poll options to display for " .. user.fullname ); return true, reason, 1
				else
					for i = 1, #choices do
						str = str .. ( "%s) %s%s" ):format( i, choices[ i ], ( i == #choices and "" or "\n\n" ) )
					end

					local _, reason = Logger.s( "Poll options retrieved -- submitting to user" ); return true, reason, 2
				end
			end
		end,
		onSuccess = function( _, user, message, output, code )
			Logger.assert( code == 1 or code == 2, "Failed to establish code. Should be 1 or 2, got other.", "Code established. Proceeding")
			if code == 1 then
				Reporter.info( user, "Poll Options", "No options. Add one by using **!addPollOption**.\n\nYour poll won't display on the BGnS server until it has options attached to it" )
			elseif code == 2 then
				Reporter.info( user, "Poll Options", output )
			end
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, output )
		end
	},

	removePollOption = {
		help = "Removes the poll option at the index provided: **!removePollOption [index]**\n\nIf index is nil (not provided or invalid number) then a list of poll options is shown and the user is asked which option to remove",
		action = function( evManager, user, message, arg ) return evManager:removePollOption( user.id, arg ) end,
		onSuccess = function( _, user )
			Reporter.success( user, "Removed poll option", "We removed that option for you. Use **!listPollOptions** to see the remaining options for your poll" )
		end,
		onFailure = function( evManager, user, message, output, code, arg )
			if code == 1 and ( not arg or arg == "" ) then
				-- The user didn't provide an index. Prompt them for one
				evManager.worker.messageManager:setPromptMode( user.id, CommandHandler.PROMPT_MODE_ENUM.POLL_REMOVE )
				return
			elseif code ~= 1 then
				evManager.worker.messageManager:setPromptMode( user.id )
			end

			Reporter.warning( user, "Failed to remove poll option", output )
		end
	},

	deletePoll = {
		help = "Remove the poll attached to your event. If the event is published the remote is refreshed",
		action = function( evManager, user ) return evManager:deletePoll( user.id ) end,
		onSuccess = function( eventManager, user )
			local ev = eventManager:getEvent( user.id )
			Reporter.success( user, "Deleted poll", "Your poll has been deleted." .. ( ev.published and " It has been revoked from the remote server (BGnS server) and can no longer be voted on" or "" ) )
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, "Failed to delete poll", output )
		end
	},

	yes = {
		help = "Tell the host of the published event that you *are attending*",
		action = function( evManager, user ) return evManager:respondToEvent( user.id, 2 ) end
	},

	maybe = {
		help = "Tell the host of the published event that you *might be attending*",
		action = function( evManager, user ) return evManager:respondToEvent( user.id, 1 ) end
	},

	no = {
		help = "Tell the host of the published event that you *not attending*",
		action = function( evManager, user ) return evManager:respondToEvent( user.id, 0 ) end
	},

	view = {
		help = "NYI"
	},

	banUser = {
		help = "Ban the userID provided from interacting with the bot. Command must be provided with a resolvable userID (member of cached guild)\n\nThe user will be notified",
		admin = true,
		action = function( evManager, user, message, banTargetID )
			Logger.i( "Attempting to ban user " .. tostring( banTargetID ) )
			local name, banTarget = user.fullname, evManager.worker.client:getUser( banTargetID )

			if not banTarget then
				return report( 1, "Failed to perform ban because the ID provided ("..tostring( banTargetID )..") is invalid (either not found on the client, or not resolvable/invalid syntax)" )
			elseif evManager.worker.messageManager.restrictionManager.bannedUsers[ banTargetID ] then
				return report( 2, "Failed to perform ban because the user ("..banTarget.fullname..") is already banned" )
			elseif banTargetID == user.id then
				return report( 3, "Failed to perform ban because the user is attempting to ban themselves" )
			end

			local issuerAdminLevel, targetAdminLevel = evManager.worker:getAdminLevel( user.id ), evManager.worker:getAdminLevel( banTargetID )
			if targetAdminLevel and issuerAdminLevel > targetAdminLevel then
				return report( 4, "Failed to perform ban because the target of the ban ("..banTarget.fullname..") is a higher administrative rank than the command issuer ("..name..")" )
			elseif evManager.worker.messageManager.restrictionManager:banUser( banTargetID ) then
				Reporter.failure( banTarget, "You have been banned", "A BGnS administrator has banned you from interacting with this bot. Contact <@"..user.id.."> if you believe this is in error" )
				return Logger.s( "Banned user " .. banTarget.fullname )
			else
				return report( 5, "Failed to ban user via restrictionManager -- unknown reason" )
			end
		end,
		onSuccess = function( _, user, message, output )
			Reporter.success( user, "Banned user", output .. ". Future interactions initiated by this user will be ignored.\n\nThe user has been notified." )
		end,
		onFailure = function( _, user, message, output )
			Reporter.warning( user, "Failed to ban user", output )
		end
	},

	unbanUser = {
		help = "Lifts a ban on the userID provided. Command must be provided with a resolvable userID (member of cached guild)\n\nThe user will be notified",
		admin = true,
		action = function( evManager, user, message, unbanTargetID )
			Logger.i( "Attempting to lift ban on user " .. tostring( unbanTargetID ) )
			local name, unbanTarget = user.fullname, evManager.worker.client:getUser( unbanTargetID )

			if not unbanTarget then
				return report( 1, "Failed to lift user ban because the target of the ban (".. tostring( unbanTargetID ) .. ") is invalid (either not found on the client, or not resolvable/invalid syntax)" )
			elseif not evManager.worker.messageManager.restrictionManager.bannedUsers[ unbanTargetID ] then
				return report( 2, "Failed to lift user ban because the user ("..unbanTarget.fullname..") is not banned" )
			elseif evManager.worker.messageManager.restrictionManager:unbanUser( unbanTargetID ) then
				Reporter.success( unbanTarget, "Ban lifted", "A BGnS administrator has explicitly lifted your ban. You are now free to interact with this bot (within reason -- spam will automatically trigger a permanent suspension)." )
				return Logger.s( "Lifted ban on " .. unbanTarget.fullname )
			else
				return report( 3, "Failed to lift user ban because an unknown error occurred" )
			end
		end,
		onSuccess = function( evManager, user, message, output, code, arg )
			Reporter.success( user, "Lifted ban", "The ban on user " .. evManager.worker.client:getUser( arg ).fullname .. " has been lifted. The user has been notified that they are unbanned." )
		end,
		onFailure = function( _, user, message, output )
			Reporter.failure( user, "Failed to lift ban", output )
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
		action = function( evManager, user, message, arg ) return evManager:updateEvent( user.id, field, arg ) end,
		onSuccess = function( _, user, message, output, code, arg )
			Reporter.success( user, "Successfully set field", "The field '"..field.."' property for your event has been updated to '"..tostring( arg ).."'" )
		end,
		onFailure = function( _, user, message, output )
			Reporter.failure( user, "Failed to set field", output )
		end
	}

	commands[ "get" .. name ] = {
		help = "Returns the value for the field '" .. field .. "' in your event.",
		action = function( evManager, user, message )
			Logger.i( "Attempting to get field '"..field.."' for event owned by " .. user.fullname, user.id )

			local e = evManager:getEvent( user.id )
			if not e then
				return report( 1, "Failed to get " .. field .. "because the user ("..user.fullname..") don't own any events" )
			else
				Reporter.info( user, "Property - " .. name, "The " .. field .. " property for your event is '"..tostring( e[ field ] ).."'. Change with **!set" .. name .. "**" )

				return Logger.s( "Returned information for field " .. field )
			end
		end
	}
end

return commands