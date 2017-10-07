local Logger, Class = require "src.util.Logger", require "src.lib.class"
local discordia = luvitRequire "discordia"

--[[
	@instance client - Discord Client Instance (def. false) - The Discordia client object used by the bot, created at instantiation. Shouldn't be manually edited as `client` is used internally.
	@instance tokenPath - string (def. ".token") - The path to the bot token, used to authenticate with DiscordApp servers.
	@instance alive - boolean (def. false) - Indicates whether or not the bot is currently waiting for events. If 'false' the bot either hasn't started, or has been stopped (`self:kill()`).
	@instance working - boolean (def. false) - While true the instance is currently processing items in the worker queue. It is not recommended the bot is stopped while handling commands.
	@instance queue - table (def. {}) - The queue of message/reaction requests waiting to be processed.

	A core class used as the entry point to the bot.

	The Worker class facilitates basic bot functionality, and is extended
	by other classes such as `GuildManager`, `MessageManager`, `CommandHandler`
	and other such utility classes.
]]

local Worker = class "Worker" {
	client = false;
	tokenPath = ".token";
	guildPath = ".guilds.cfg";

	alive = false;
	working = false;

	queue = {};
	guilds = {};
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
	self:bindManager( require "src.manager.MessageManager" )
	self:bindManager( require "src.manager.UserManager" )

	self.client = Logger.assert( discordia.Client( self.clientOptions ), "Failed to instantiate Discordia client", "Discordia client opening" )

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
	@desc Finishes the construction of the Worker instance by creating the remaining event listeners
]]
function Worker:start()
	self.client:on( "reactionAdd", function( reaction, userID ) self.messageManager:handleInboundReaction( reaction, userID ) end ) 
	self.client:on( "messageCreate", function( message ) self.messageManager:handleInboundMessage( message ) end ) 
	self.client:on( "guildCreate", function( guild ) self:handleNewGuild( guild ) end )

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
	if not discordia.class.isInstance( guild, "Guild" ) then
		return Logger.w( "Invalid guild instance '"..tostring( guild ).."' provided to Worker:handleNewGuild. Ensure the argument is a valid Guild instance" )
	end

	local guilds = self.guilds
	if not guilds[ guildID ] then
		guilds[ guildID ] = {}

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
	if discordia.class.isInstance( target, "Message" ) then
		table.insert( self.queue, target )
	elseif discordia.class.isInstance( target, "Reaction" ) then
		if not userID then return Logger.w( "Cannot add Reaction to worker queue because no userID was provided (arg #2)" ) end

		table.insert( self.queue, { target, userID } )
	else
		return Logger.w( "Unknown target '"..tostring( target ).."' for worker queue" )
	end

	return true
end 

--[[
	@instance
	@desc Checks if the queue has any items inside of it. If the queue is populated, the Worker will
		  begin processing it (setting `self.working` to `true` until the queue is complete).
]]
function Worker:checkQueue()
	local queue = self.queue
	if #queue == 0 then return end

	Logger.i( "Starting queue in order to process items (" .. #queue .. ")" )
	while #queue > 0 do
		local item = queue[ 1 ]
		--TODO
	end
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

return Worker:compile()
