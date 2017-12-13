local TCE = require "src.lib.class"
local Logger, Reporter, Worker, CommandHandler, SettingsHandler = require "src.util.Logger", require "src.util.Reporter", require "src.Worker", TCE.getClass "CommandHandler", TCE.getClass "SettingsHandler"

local perms = luvitRequire "discordia".enums.permission

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
        help = "Display this help menu.\n\nRun 'cmd help commands [command1, command2, ...]' to see help on the given commands (eg: 'cmd help commands create cancel' gives help for the *create* and *cancel* command).",
        action = function( evManager, guildID, userID, message )
            local user = evManager.worker.client:getUser( userID )
            local args = splitArguments( select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) ) )
            if args[ 1 ] == "commands" then
                if args[ 2 ] then
                    Logger.i "Serving help information for requested commands"
                    local fields, invalidFields = {}, {}
                    for i = 2, #args do
                        local com = args[ i ]
                        if commands[ com ] then
                            local h = commands[ com ].help
                            Logger.d( "Serving help for cmd " .. com )

                            if h and #h > 0 then
                                fields[ #fields + 1 ] = { name = "__'cmd ".. com .. "'__", value = h }
                            end
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
                        if config.help and #config.help > 0 then
                            fields[ #fields + 1 ] = { name = "__'cmd " .. name .. "'__", value = config.help }
                        end
                    end

                    Reporter.info( user, "Command Help", "Below is a list of help information for each of the commands you can use. " .. tostring( #fields ), unpack( fields ) )
                    return Logger.s "Served help information for all commands"
                end
            else
                Reporter.info( user, "Hoorah! You're ready to learn a little bit about meee!", "Using this bot is dead simple! Before we get going select what information you need\n\n",
                    { name = "Hosting", value = "To host an event use the 'cmd create' command inside this DM.\nOnce created you will be sent more instructions here (regarding configuration and publishing of your event)" },
                    { name = "Responding", value = "If you want to let the host of an event know whether or not you're coming, use 'cmd yes', 'cmd no' or 'cmd maybe' inside this DM. The event manager will be notified." },
                    { name = "Current Event", value = "If you'd like to see information regarding the current event visit the $HOST_CHANNEL inside the $GUILD (BG'n'S server)." },
                    { name = "Further Commands", value = "Use 'cmd help commands' to see information on all commands.\n\nIf you're only interested in certain commands, provide the names of the commands as well to see information for those commands only (eg: !help commands create)."}
                )

                return Logger.s "Served general help information"
            end
        end
    },

    settings = {
        help = "Used in syntax 'cmd settings settingName settingValue'. If no 'settingName', all settings for the guild (and their value) will be shown (along with more indepth help information).",
        action = function( eventManager, guildID, userID, message )
            local property, value = select( 2, eventManager.worker.commandManager:splitCommand( guildID, message.content ) ):match "(%S+)%s+(.+)$"
            local guildConfig = eventManager.worker.guilds[ guildID ]

            if not property then
                local fields = {}
                for name, config in pairs( SettingsHandler.SETTINGS ) do
                    local currentOverride = eventManager.worker:getOverrideForDisplay( guildID, name )
                    local isOverrideDefault = eventManager.worker:isOverrideDefault( guildID, name )
                    fields[ #fields + 1 ] = { name = ("__%s__"):format( name ), value = config.help .. "\n*Currently " .. tostring( currentOverride ) .. ( isOverrideDefault and " - default value" or "" ) .. "*" }
                end

                Reporter.info( message.channel, "Guild Settings", "This command can be used to configure the bot specifically for your guild. Use 'cmd settings command [value]', where `command` is one of below. If 'value' is given, the setting will be set to that value (unless value is 'none', in which case the setting will be reset) -- otherwise the current value will be shown.", unpack( fields ) )
                return Logger.s( "Served general settings information to user " .. userID .." via guild " .. guildID .. " channel " .. message.channel.id .. " ("..message.channel.name..")" )
            end

            local isGetting = not ( value and #value > 0 )
            local function reportVal( updated )
                local currentOverride = eventManager.worker:getOverrideForDisplay( guildID, property )
                local isOverrideDefault = eventManager.worker:isOverrideDefault( guildID, property )

                Reporter[ updated and "success" or "info" ]( message.channel, "Guild setting '"..property.."'", "The value for this guild setting is " .. ( updated and "now " or "" ) .. tostring( currentOverride ) .. ( isOverrideDefault and "\n\n*This is the default value*" or "" ) )
            end

            if SettingsHandler.SETTINGS[ property ] then
                if isGetting then
                    reportVal()
                    return Logger.s( "Served guild setting '"..property.."' for guild '"..guildID.."'" )
                else
                    local ok, err = eventManager.worker:setOverride( guildID, property, value ~= "none" and value or nil )
                    if ok then
                        reportVal( true )
                        return Logger.s( "Updated guild setting '"..property.."' to '"..value.."' under instruction from user '"..userID.."' at guild '"..guildID.."'" )
                    else
                        Reporter.failure( message.channel, "Failed to update guild override", tostring( err ) )
                    end
                end
            else
                Reporter.failure( message.channel, "Unknown guild setting", "The guild setting '"..property.."' doesn't exist, ensure you haven't made a typing mistake. Check 'cmd settings' for a list of valid settings" )
            end
        end
    },

    create = {
        help = "Creates a new event. A user can only have one event *per guild*. An event must be created before one can be edited (and then published).",
        action = "createEvent",
        onFailure = function( eventManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to create event", reason )
        end
    },

    delete = {
        help = "Deletes the user's event at this guild (if one exists). This action is irreversible and will erase all event details. Members that have RSVPd as **going** or **might be going** will be notified that the event has been cancelled. If your event has not been cancelled, but has instead finished, use 'cmd conclude'.",
        action = "deleteEvent",
        onFailure = function( eventManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to delete event", reason )
        end
    },

    conclude = {
        help = "Use this command to mark the event as completed. This removes the event entirely (same as 'cmd delete'), this action is irreversible. Members that have RSVPd as **going** or **might be going** will be notified that the event is finished",
        action = "concludeEvent",
        onFailure = function( eventManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to conclude event", reason )
        end
    },

    publish = {
        help = "Publishes the current event to the guild. This allows members to RSVP. Ensure your event details are correct before publishing to avoid confusion.",
        action = "publishEvent",
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to publish event", reason )
        end
    },

    unpublish = {
        help = "Unpublishes your event from the guild. Members who have RSVPd as **going** or **might be going** will be notified that the event is cancelled (and all responses will be erased). There is no need to unpublish your event when editing details.",
        action = "unpublishEvent",
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to unpublish event", reason )
        end
    },

    set = {
        help = "Syntax: 'cmd set property value'.\n\nSets the property (valid properties: title, desc, location, timeframe) to the value given",
        action = function( evManager, guildID, userID, message )
            local name, value = select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) ):match "(%S+)%s+(.+)$"
            if not ( name and value ) then
                return report( 1, "Invalid syntax given to set command. Should be form 'cmd set <property> <value>'" )
            end

            local ok, output, code = evManager:setEventProperty( guildID, userID, name, value )
            if ok then return ok, output else return ok, output, 1 + ( code or 1 ) end
        end,
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to set event property", reason )
        end
    },

    createPoll = {
        help = "",
        action = "createPoll",
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to create poll", reason )
        end
    },

    setPollDesc = {
        help = "",
        action = function( evManager, guildID, userID, message )
            local trailing = select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) )
            if not ( trailing and #trailing > 0 ) then
                return report( 1, "Invalid syntax given to setPollDesc command. Should be form 'cmd setPollDesc <desc>'" )
            end

            local ok, output, code = evManager:setPollDescription( guildID, userID, trailing )
            if ok then return ok, output else return ok, output, 1 + ( code or 1 ) end
        end,
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to set poll description", reason )
        end
    },

    addPollOption = {
        help = "",
        action = function( evManager, guildID, userID, message )
            local trailing = select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) )
            if not ( trailing and #trailing > 0 ) then
                return report( 1, "Invalid syntax given to addPollOption command. Should be form 'cmd addPollOption <option>'" )
            end

            local ok, output, code = evManager:addPollOption( guildID, userID, trailing )
            if ok then return ok, output else return ok, output, 1 + ( code or 1 ) end
        end,
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to add poll option", reason )
        end
    },

    removePollOption = {
        help = "",
        action = function( evManager, guildID, userID, message )
            local trailing = select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) )
            if not ( trailing and #trailing > 0 ) then
                return report( 1, "Invalid syntax given to removePollOption command. Should be form 'cmd removePollOption <index>' where 'index' is a number representing a valid poll option" )
            end

            local ok, output, code = evManager:removePollOption( guildID, userID, trailing )
            if ok then return ok, output else return ok, output, 1 + ( code or 1 ) end
        end,
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to remove poll option", reason )
        end
    },

    deletePoll = {
        help = "",
        action = "deletePoll",
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to delete poll", reason )
        end
    },

    listPollVotes = {
        help = "Lists the votes for the poll provided, including the names of those who have voted. Used in syntax 'cmd listPollVotes <pollID>' where 'pollID' is the numeric ID found at the bottom of a poll message.",
        action = function( evManager, guildID, userID, message )
            local ID = tonumber( select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) ) )
            if not ID then
                return report( 1, "Invalid syntax given to listPollVotes command. Should be form 'cmd listPollVotes <pollID>' where 'pollID' is a VALID poll ID (found at the bottom of a poll message)" )
            end

            local events = evManager.worker.guilds[ guildID ].events
            for eventAuthorID, event in pairs( events ) do
                if event.published and event.poll and event.poll.id == ID then
                    -- List poll information
                    local poll, votes, fields = event.poll, {}, {}
                    for ID, response in pairs( poll.responses ) do
                        if not votes[ response ] then votes[ response ] = {} end
                        table.insert( votes[ response ], ID )
                    end

                    local options = poll.options
                    for i = 1, #options do
                        local v, suffix = votes[ i ], ""
                        if v then
                            for vs = 1, #v do
                                suffix = suffix .. "<@" .. v[ vs ] .. ">" .. ( #v - vs > 1 and ", " or ( #v - vs == 1 and ", and " ) or "" )
                            end
                        end

                        local len = v and #v or 0
                        table.insert( fields, {
                            name = i .. ") " .. options[ i ],
                            value = #suffix > 0 and ( len .. " vote" .. ( len ~= 1 and "s" or "" ) .. ": " .. suffix ) or "No votes"
                        } )
                    end

                    Reporter.info( message.channel, "Poll Information", "Below is the poll information for **" .. event.title .. "**", unpack( fields ) )

                    return Logger.s( "Listed poll votes at guild " .. guildID .. " for user " .. userID )
                end
            end

            return report( 2, "Invalid ID (" .. tostring( ID ) .. ") provided. No poll found with that ID." )
        end,
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to list poll votes", reason )
        end
    },

    revokeRemote = {
        help = "\\*Admin Command* Syntax: 'cmd revokeRemote @tagUser'\n\nForcibly unpublishes the event by the tagged user (alternatively, the userID can be plainly provided instead of tagging the user).",
        action = function( evManager, guildID, _userID, message, args )
            -- Remove any surrounding elements of the userID (@<>).
            local userID = tostring( splitArguments( select( 2, evManager.worker.commandManager:splitCommand( guildID, message.content ) ) )[ 1 ] ):gsub( "%<@(%w+)%>", "%1" )
            if not userID then
                return report( 1, "Invalid command syntax. Requires userID following command start (tag user/provide userID from debug)." )
            elseif not evManager.worker.client.users:get( userID ) then
                return report( 2, "Invalid userID provided -- unable to find user with matching ID in client's cache" )
            end

            local event = evManager:getEvent( guildID, userID )
            if not ( event and event.published ) then return report( 3, "Unable to revoke event for user " .. userID .. " -- user has no event published at guild " .. guildID ) end

            local ok, output, code = evManager:unpublishEvent( guildID, userID )
            if ok then return ok, output else return ok, output, 1 + ( code or 1 ) end
        end,
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to revoke remote", reason )
        end,
        permissions = { perms.manageMessages, perms.manageEmojis }
    },

    repairGuild = {
        help = "\\*Admin Command* Repairs the remote of the guild, causing the pushed messages to be reset",
        action = function( evManager, guildID, userID, message )
            evManager:repairGuild( guildID, true )
            return Logger.s( "Repairing all events at guild '" .. guildID .. "'" )
        end,
        permissions = { perms.manageEmojis, perms.manageMessages }
    },

    banUser = {}, -- ADMIN

    unbanUser = {} -- ADMIN
}

return commands
