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
                                fields[ #fields + 1 ] = { name = "'cmd ".. com .. "'", value = h }
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
                            fields[ #fields + 1 ] = { name = "'cmd " .. name .. "'", value = config.help }
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
        action = function( eventManager, guildID, userID, message )
            local args = splitArguments( select( 2, eventManager.worker.commandManager:splitCommand( guildID, message.content ) ) )
            local guildConfig = eventManager.worker.guilds[ guildID ]

            local settingArg = args[ 1 ]
            if not settingArg then
                local fields = {}
                for name, config in pairs( SettingsHandler.SETTINGS ) do
                    local currentOverride = eventManager.worker:getOverrideForDisplay( guildID, name )
                    local isOverrideDefault = eventManager.worker:isOverrideDefault( guildID, name )
                    fields[ #fields + 1 ] = { name = ("__%s__"):format( name ), value = config.help .. "\n*Currently " .. tostring( currentOverride ) .. ( isOverrideDefault and " - default value" or "" ) .. "*" }
                end

                Reporter.info( message.channel, "Guild Settings", "This command can be used to configure the bot specifically for your guild. Use 'cmd settings command [value]', where `command` is one of below. If 'value' is given, the setting will be set to that value (unless value is 'none', in which case the setting will be reset) -- otherwise the current value will be shown.", unpack( fields ) )
                return Logger.s( "Served general settings information to user " .. userID .." via guild " .. guildID .. " channel " .. message.channel.id .. " ("..message.channel.name..")" )
            end

            local isGetting = not ( args[ 2 ] and #args[ 2 ] > 0 )
            local function reportVal( updated )
                local currentOverride = eventManager.worker:getOverrideForDisplay( guildID, settingArg )
                local isOverrideDefault = eventManager.worker:isOverrideDefault( guildID, settingArg )

                Reporter[ updated and "success" or "info" ]( message.channel, "Guild setting '"..settingArg.."'", "The value for this guild setting is " .. ( updated and "now " or "" ) .. tostring( currentOverride ) .. ( isOverrideDefault and "\n\n*This is the default value*" or "" ) )
            end

            if SettingsHandler.SETTINGS[ settingArg ] then
                if isGetting then
                    reportVal()
                    return Logger.s( "Served guild setting '"..settingArg.."' for guild '"..guildID.."'" )
                else
                    local ok, err = eventManager.worker:setOverride( guildID, settingArg, args[ 2 ] ~= "none" and args[ 2 ] or nil )
                    if ok then
                        reportVal( true )
                        return Logger.s( "Updated guild setting '"..settingArg.."' to '"..args[ 2 ].."' under instruction from user '"..userID.."' at guild '"..guildID.."'" )
                    else
                        Reporter.failure( message.channel, "Failed to update guild override", tostring( err ) )
                    end
                end
            else
                Reporter.failure( message.channel, "Unknown guild setting", "The guild setting '"..settingArg.."' doesn't exist, ensure you haven't made a typing mistake. Check 'cmd settings' for a list of valid settings" )
            end
        end
    },

    create = {
        action = "createEvent",
        onFailure = function( eventManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to create event", reason )
        end
    },

    delete = {
        action = "deleteEvent",
        onFailure = function( eventManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to delete event", reason )
        end
    },

    publish = {
        action = "publishEvent",
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to publish event", reason )
        end
    },

    unpublish = {
        action = "unpublishEvent",
        onFailure = function( evManager, user, message, status, reason, statusCode )
            Reporter.failure( message.channel, "Failed to unpublish event", reason )
        end
    },

    set = {
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

    createPoll = {},

    setPollDesc = {},

    addPollOption = {},

    listPollOptions = {},

    removePollOption = {},

    deletePoll = {},

    yes = {},

    maybe = {},

    no = {},

    view = {},

    refreshRemote = {}, -- ADMIN

    revokeRemote = {}, -- ADMIN

    banUser = {}, -- ADMIN

    unbanUser = {} -- ADMIN
}

-- Generate commands dynamically for the following properties. The function will simply change the property key-value of the users event.
--local VALID_FIELDS = { "title", "desc", "timeframe", "location" }
--for i = 1, #VALID_FIELDS do
    --local field = VALID_FIELDS[ i ]

    --local name = field:sub( 1, 1 ):upper() .. field:sub( 2 )
    --commands[ "set" .. name ] = {}
    --commands[ "get" .. name ] = {}
--end

return commands
