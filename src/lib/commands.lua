local Logger, Reporter, Worker, CommandHandler = require "src.util.Logger", require "src.util.Reporter", require "src.Worker", require "src.lib.class".getClass "CommandHandler"

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
        help = "Display this help menu.\n\nRun **!help commands [command1, command2, ...]** to see help on the given commands (eg: **!help commands create cancel** gives help for the *create* and *cancel* command).",
        action = function( evManager, guildID, userID, message )
            local user = evManager.worker.client:getUser( userID )
            local args = splitArguments( message.content:match "^%!%w+%s*(.*)$" )
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
                                fields[ #fields + 1 ] = { name = "__!".. com .. "__", value = h }
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
                            fields[ #fields + 1 ] = { name = "__!" .. name .. "__", value = config.help }
                        end
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
