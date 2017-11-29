local Logger, Class, JSONPersist, Reporter, SettingsHandler = require "src.util.Logger", require "src.lib.class", require "src.util.JSONPersist", require "src.util.Reporter", require "src.util.SettingsHandler"
local discordia = luvitRequire "discordia"

--[[
    @instance client - Discord Client Instance (def. false) - The Discordia client object used by the bot, created at instantiation. Shouldn't be manually edited as `client` is used internally.
    @instance tokenPath - string (def. ".token") - The path to the bot token, used to authenticate with DiscordApp servers.
    @instance alive - boolean (def. false) - Indicates whether or not the bot is currently waiting for events. If 'false' the bot either hasn't started, or has been stopped (`self:kill()`).
    @instance working - boolean (def. false) - While true the instance is currently processing items in the worker queue. It is not recommended the bot is stopped while handling commands.
    @instance queue - table (def. {}) - The queue of message/reaction requests waiting to be processed.

    A core class used as the entry point to the bot.

    The Worker class facilitates basic bot functionality, and is extended
    by other classes such as `CommandManager`, `EventManager` and other
    such utility classes.
]]

local Worker = class "Worker" {
    static = {
        ATTEND_ENUM = { "not going", "might be going", "going" };
    };

    client = false;
    tokenPath = ".token";
    guildPath = ".guilds.cfg";

    alive = false;
    working = false;

    queue = {};
    guilds = {};
    userCommandRequests = {};
}

--[[
    @constructor
    @desc Constructs the Worker instance by opening a connection to the Discordia client.

          Once the connection is opened, the request is passed off to `Worker:start()` to
          start the bot's listerners.

          'clientOptions' will be passed to the Discordia client upon instantiation if
          provided.
    @param [table - clientOptions], [string - tokenPath]
]]
function Worker:__init__( ... )
    self:resolve( ... )

    Logger.bindActiveWorker( self )
    self.commandManager = self:bindManager( require "src.manager.CommandManager" )
    self.eventManager = self:bindManager( require "src.manager.EventManager" )

    self.client = Logger.assert( discordia.Client( self.clientOptions ), "Failed to instantiate Discordia client", "Discordia client opening" )
    self.guilds = Logger.assert( JSONPersist.loadFromFile( self.guildPath ), "Failed to load guild information", "Guilds loaded" )

    local h = io.open( self.tokenPath )
    Logger.assert( h, "Failed to open token information", "Token information loaded" )
    local token = h:read "*a"
    h:close()

    self.client:once( "ready", function()
        Logger.s "Connected to DiscordApp gateway. Finishing bot initialisation"
        self:start()
    end )

    Logger.i "Attempting to connect"
    self.client:run( token )
end

--[[
    @instance
    @desc Sets the the fallback channel for the guild. This channel will be used
          if the bot isn't configured to use a specific channel ('cmd settings channel')
          OR if the specified channel becomes unavailable
    @param <Discordia Guild Instance - guild>
]]
function Worker:setFallbackChannel( guild )
    local guildConfig = self.guilds[ guild.id ]
    local channelsArray = guild.textChannels:toArray()

    guildConfig._channel = channelsArray[ 1 ] and channelsArray[ 1 ].id or nil
    self:saveGuilds()

    return channelsArray[ 1 ]
end

--[[
    @instance
    @desc Finishes the construction of the Worker instance by creating the remaining event listeners
]]
function Worker:start()
    local function addReactionToQueue( reaction, userID )
        local guildID = reaction.message.guild.id
        if guildID and self.guilds[ guildID ] and not self.client:getUser( userID ).bot then
            self:addToQueue( reaction, userID )
        end
    end

    self.client:on( "reactionAddUncached", function( channel, messageID, hash, userID )
        addReactionToQueue( channel:getMessage( messageID ).reactions:get( hash ), userID )
    end )
    self.client:on( "reactionAdd", function( reaction, userID )
        addReactionToQueue( reaction, userID )
    end )
    self.client:on( "messageCreate", function( message )
        local guildID = message.guild and message.guild.id
        if message.author.bot or not ( guildID and self.guilds[ guildID ] ) or not ( message.content and message.content:find( "^".. self:getOverride( guildID, "prefix" ) .."%w+" ) ) then return end

        local reqs = self.userCommandRequests[ message.author.id ] or 0
        if reqs >= 3 then
            return Logger.w( "User " .. message.author.fullname .. " already has 3 or more requests in the queue -- ignoring message" )
        end

        Logger.i( "Inserting message into queue at position #" .. #self.queue + 1, "User " .. message.author.fullname .. " now has " .. reqs + 1 .. " request(s) in the queue" )
        self.userCommandRequests[ message.author.id ] = reqs + 1

        self:addToQueue( message )
    end )
    self.client:on( "guildCreate", function( guild ) self:handleNewGuild( guild ) end )
    self.client:on( "guildDelete", function( guild ) if self.guilds[ guild.id ] then self.guilds[ guild.id ] = nil; self:saveGuilds() end end )
    self.client:on( "channelDelete", function( channel )
        if not channel.guild then return end

        local guildConfig = self.guilds[ channel.guild.id ]
        if guildConfig._channel == channel.id then
            local newChannel = self:setFallbackChannel( channel.guild )
            if not guildConfig.channel and newChannel then
                Reporter.failure( newChannel, "Bot channel removed", "The configured channel for this bot has been deleted. The bot has fallen back to the automatically selected channel <#"..newChannel.id..">. Reconfigure the channel using 'cmd settings channel'." )
            end
        end

        if guildConfig.channel == channel.id then
            guildConfig.channel = nil

            local fallbackChannel = self:getOverride( channel.guild.id, "channel" )
            if not fallbackChannel then return end

            Reporter.failure( channel.guild:getChannel( fallbackChannel ), "Bot channel removed", "The configured channel for this bot has been deleted. The bot has fallen back to the automatically selected channel <#"..fallbackChannel..">. Reconfigure the channel using 'cmd settings channel'." )
        end

        self:saveGuilds()
    end )
    self.client:on( "channelCreate", function( channel )
        if not channel.guild then return end

        local guildConfig = self.guilds[ channel.guild.id ]
        if not guildConfig._channel then
            local newChannel = self:setFallbackChannel( channel.guild )
            if newChannel and not guildConfig.channel then
                Reporter.info( newChannel, "Event Organiser Channel Selection", "This channel has been automatically selected for the event organiser.\n\nIf you don't want this channel being used by the bot, use 'cmd settings channel #mention-chanel' to specify which channel the bot should use to announce events" )
            end
        end

        self:saveGuilds()
    end )

    self.eventManager:repairAllGuilds()
    self.alive = true
    Logger.s "Started worker"
end

--[[
    @instance
    @desc Kills the active worker by closing the Discordia client (if one is present)

          If 'silent' no warning will be raised when trying to kill a worker that has no attached client
    @param [boolean - silent]
]]
function Worker:kill( silent )
    if not self.client then
        if silent then return end
        return Logger.w( "Cannot kill worker '"..tostring( worker ).."' because no client has been attached to this worker." )
    elseif not self.alive then
        if silent then return end
        return Logger.w( "Cannot kill worker '"..tostring( worker ).."' because it is not alive" )
    end

    self.alive = false
    self.client:stop()
end

--[[
    @instance
    @desc Checks that the guild provided is already acknowledged by the bot. If the guild is 'new', create an
          entry for the guild and save the config.
]]
function Worker:handleNewGuild( guild )
    if not discordia.class.isInstance( guild, discordia.class.classes.Guild ) then
        return Logger.w( "Invalid guild instance '"..tostring( guild ).."' provided to Worker:handleNewGuild. Ensure the argument is a valid Guild instance" )
    end

    local guilds, guildID = self.guilds, guild.id
    if not guilds[ guildID ] then
        guilds[ guildID ] = { events = {} }
        local newChannel = self:setFallbackChannel( guild )

        if newChannel then
            guilds[ guildID ]._channel = newChannel and newChannel.id or nil
            Reporter.info( newChannel, "Event Manager Channel", "The event manager bot has been invited to this guild and has automatically decided to use this channel for event information. Use 'cmd settings channel #mention-channel' to change the channel that the bot uses" )
        end

        Logger.i( "New guild detected (or records of this guild have been lost)", guild.name, "This guild has been registered with the bot" )
        self:saveGuilds()
    end
end

--[[
    @instance
    @desc Inserts the command provided into the worker queue.

          The entry can either be a 'Message' instance, or a 'Reaction' instance -- depending
          on the origin of the event (messageCreate, reactionAdd respectively)
    @param <Message Instance - originMessage> - If originating from messageCreate event
    @param <Reaction Instance - reaction>, <string - userID> - If originating from reactionAdd event (userID is required too because Reaction instances do not represent user action)
    @return <boolean - success>
]]
function Worker:addToQueue( target, userID )
    if discordia.class.isInstance( target, discordia.class.classes.Message ) then
        table.insert( self.queue, target )
    elseif discordia.class.isInstance( target, discordia.class.classes.Reaction ) then
        if not userID then return Logger.w( "Cannot add Reaction to worker queue because no userID was provided (arg #2)" ) end

        table.insert( self.queue, { target, userID } )
    else
        return Logger.w( "Unknown target '"..tostring( target ).."' for worker queue" )
    end

    coroutine.wrap( self.checkQueue )( self )
    return true
end

--[[
    @instance
    @desc Checks if the queue has any items inside of it. If the queue is populated, the Worker will
          begin processing it (setting `self.working` to `true` until the queue is complete).
]]
function Worker:checkQueue()
    local queue = self.queue
    if #queue == 0 or self.working then return end

    self.working = true
    while #queue > 0 do
        local item = queue[ 1 ]
        self.commandManager:handleItem( item )

        local authorID = item.author and item.author.id or item[ 2 ]

        local reqs = self.userCommandRequests[ authorID ]
        if reqs then self.userCommandRequests[ authorID ] = reqs - 1 end

        table.remove( queue, 1 )
    end

    self.working = false
end

--[[
    @instance
    @desc Saves the Worker 'guilds' table to file for persistent storage
]]
function Worker:saveGuilds()
    JSONPersist.saveToFile( self.guildPath, self.guilds )
end

--[[
    @instance
    @desc This function, when given a string, will return that string
          modified so that the word 'guild' or 'user', followed by a
          guild/userID is replaced with the guild/users name.

          Primarialy used for removing unreadable IDs from user
          reports, while retaining that useful information in
          log files (names can change, and can exist as duplicates
          removing any identification purpose).
    @param <string - textToClean>
    @return <string - cleanedText>
]]
function Worker:resolveNames( textToClean, prefix )
    local guilds = setmetatable( {}, { __index = function( _, k ) local g = self.client.guilds:get( k ); return g and "**" .. g.name .. "**" end } )
    local users = setmetatable( {}, { __index = function( _, k ) local u = self.client.users:get( k ); return u and "**" .. u.fullname .. "**" end } )

    return textToClean:gsub( "guild (%w+)", guilds ):gsub( "user (%w+)", users ):gsub( "%'cmd%s+(.-)%'", function( v ) return v and ( "**%s%s**" ):format( prefix or "!", v ) end )
end

--[[
    @instance
    @desc Binds the manager class provided by creating an instance of it
          and setting it's worker to the 'self' object (this worker instance).
]]
function Worker:bindManager( managerClass, ... )
    Logger.assert( Class.typeOf( managerClass, "Manager" ), "Failed to bind manager '"..tostring( managerClass ).."' to worker because the manager class provided is NOT a class derived from 'Manager'", "Class provided is valid -- binding" )

    return managerClass( self, ... )
end

configureConstructor {
    orderedArguments = { "clientOptions", "tokenPath" },
    argumentTypes = {
        clientOptions = "table",
        tokenPath = "string"
    }
}

mixin "SettingsHandler"
return Worker:compile()
