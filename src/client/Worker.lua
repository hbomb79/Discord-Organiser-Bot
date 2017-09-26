local Logger = require "src.client.Logger"
local discordia = luvitRequire "discordia"

--[[
	A core class designed to handle the primary workload of the bot. Handles:
		- Gateway connection
		- Guild/channel retrieval
		- messageCreate events
		- Command parsing and execution	
]]

Logger.d "Compiling Worker"
local Worker = class "Worker" {
	static = {
		GUILD_ID = "158038708057145344",
		CHANNEL_ID = "361062102732898314"
	};

	tokenLocation = ".token";
	alive = false;

	client = false;
	cachedChannel = false;
	cachedGuild = false;
}

--[[
	@constructor
	@desc Loads the worker instance by connecting to the Discord gateway, and fetching information about the guild (and their channels)
	@param [string - tokenLocation]
]]
function Worker:__init__( ... )
	self:resolve( ... )
	Logger.i( "Instantiating Worker", "Attempting to bind Worker to Logger statically" )
	Logger.bind( self )

	Logger.i( "Attempting to bind manager (MessageManager)" )
	self.messageManager = Logger.assert( require( "src.managers.MessageManager" )( self ), "Failed to bind MessageManager", "Bound MessageManager" )

	-- Create the Discordia client
	self.client = discordia.Client( self.clientOptions )

	-- Load the token information
	local h = io.open( self.tokenLocation )
	Logger.assert( h, "Failed to open token information", "Token information loaded" )
	local token = h:read "*a"
	h:close()

	-- Bind a ready callback (only need this once)
	self.client:once( "ready", function()
		Logger.s "Successfully connected to Discordapp gateway. Starting worker"
		self:start()
	end )

	Logger.i "Connecting..."
	self.client:run( token )
end

--[[
	@instance
	@desc Starts the worker by fetching channel/guild information and assigning a messageCreate callback. This callback will feed incoming
		  messages to the MessageManager (self.messageManager)
]]
function Worker:start()
	self.cachedGuild = Logger.assert( self.client:getGuild( Worker.GUILD_ID ), "Failed to fetch guild information", "Saved guild information" )
	self.cachedChannel = Logger.assert( self.cachedGuild:getChannel( Worker.CHANNEL_ID ), "Failed to fetch channel information", "Saved channel information" )

	Logger.s "Fetching guild and channel information"

	self.client:on( "messageCreate", function( message ) self.messageManager:handleInbound( message ) end )
	Logger.s "Worker ready -- waiting for messages"
end

--[[
	@instance
	@desc Kills the worker (if alive) by termination any connections (shards) to the Discordapp gateway.
]]
function Worker:kill()
	Logger.i "Killing worker (gracefully) | Disconnecting from gateway"
	if not self.client then
		return Logger.w "Cannot kill worker. No client bound. There is NO active connection -- no need to kill"
	end

	return self.client:stop()
end

configureConstructor {
	orderedArguments = { "tokenLocation", "clientOptions" },
	argumentTypes = { tokenLocation = "string", clientOptions = "table" }
}

return Worker:compile()
