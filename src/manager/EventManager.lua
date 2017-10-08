local Reporter, Logger, Manager = require "src.util.Reporter", require "src.util.Logger", require "src.manager.Manager"

local REFUSE_ERROR, SUCCESS = "Refusing to %s at guild %s for user %s because %s", "%s at guild %s for user %s"
local function report( code, ... )
	local _, reason = Logger.w( ... )
	return false, reason, code
end

--[[
	A manager class that provides the ability for the bot
	to create, edit, remove and organise user created
	events.

	Events can be manipulated directly, or via bot commands.

	Events are stored in `Worker.guilds[ guildID ].events` for
	centralised storage of guild-related information (events,
	settings).

	All methods that manipulate event details require the 'guildID'
	and 'userID' property. Some methods may require extra
	properties -- see those methods for information.
]]

local EventManager = class "EventManager" {}

--[[
	@instance
	@desc Returns the event for user 'userID' at guild 'guildID' if
		  present
	@param <string - guildID>, <string - userID>
	@return <table - event> - If event exists
	@return <false - failure> - If event doesn't exist
]]
function EventManager:getEvent( guildID, userID )
	local guild = self.worker.guilds[ guildID ]
	return guild and guild.events[ userID ] or false
end

--[[
	@instance
	@desc
]]
function EventManager:createEvent( guildID, userID )
	if self:getEvent( guildID, userID ) then
		return report( 1, REFUSE_ERROR:format( "create event", guildID, userID, "the user already has an event at this guild" ) )
	end

	self.worker.guilds[ guildID ].events[ userID ] = {
		title = "";
		desc = "";
		location = "N/A";
		timeframe = "N/A";

		author = userID;
		responses = {};

		poll = false;
		rules = false;
		published = false;
	}

	self.worker:saveGuilds()
	return Logger.s( SUCCESS:format( "Created and saved event", guildID, userID ) )
end

extends "Manager"
return EventManager:compile()
