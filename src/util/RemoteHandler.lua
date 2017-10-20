local Logger, Worker = require "src.util.Logger", require "src.lib.class".getClass "Worker"
local discordia = luvitRequire "discordia"

local function formResponses( client, responses )
	local str, states = "", { {}, {}, {} }
	for userID, response in pairs( responses ) do table.insert( states[ response + 1 ], userID ) end

	local function out( a ) str = str .. "\n" .. a end
	for s = 1, #states do
		local state = states[ s ]
		if #state > 0 then
			local name = Worker.ATTEND_ENUM[ s ]
			out( ("__%s%s__"):format( name:sub( 1, 1 ):upper(), name:sub( 2 ) ) )

			for r = 1, #state do
				out( ("- %s"):format( client:getUser( state[ r ] ).fullname ) )
			end
		end
	end

	return str == "" and "*No RSVPs*" or str
end

local function verifyAndFetchChannel( self, guildID, userID )
    local event = self:getEvent( guildID, userID )
    local channelID = self.worker:getOverride( guildID, "channel" )
    if not channelID then return end

    local channel = self.worker.client:getGuild( guildID ):getChannel( channelID )
    if not ( event and event.published and channel ) then return else return event, channel end
end

--[[
    @instance repairing - table (def. {}) - A key-value pair table that is used to keep track of the guilds currently being repaired.

    An abstract class that is mixed-in by the EventManager class.

    Is used to handle event details being pushed to guild channels.

    The channel used is defined by the servers, therefore if no
    configuration for the guild is available on the worker -- or
    no channel has been defined, the guild will not be pushed.
]]

local RemoteHandler = class "RemoteHandler" {
    static = {
        ATTEND_REACTIONS = { "✅", "❔", "🚫" };
    };

    repairing = {};
}

--[[
    @instance
    @desc Removes the messages attached to the event provided
    @param <string - guildID>, <string - userID>
]]
function RemoteHandler:revokeFromRemote( guildID, userID )
    local event, channel = verifyAndFetchChannel( self, guildID, userID )
    if not event then return end

    if event.snowflake then
        local eventMessage = channel:getMessage( event.snowflake )
        if eventMessage then eventMessage:delete() end

        event.snowflake = nil
    end

    if event.poll and event.poll.snowflake then
        local pollMessage = channel:getMessage( event.poll.snowflake )
        if pollMessage then pollMessage:delete() end

        event.poll.snowflake = nil
    end

    self.worker:saveGuilds()
end

--[[
    @instance
    @desc Repairs the reactions for the event provided (both
          poll and event message(s)).
    @param <string - guildID>, <string - userID>, <table - event>, <Discordia Channel Instance - channel>
]]
function RemoteHandler:repairReactions( guildID, userID, event, channel )
    local eventMessage = channel:getMessage( event.snowflake )
    if not eventMessage then return Logger.e( "Cannot repair reactions on event message because the message doesn't exist at the snowflake on record" ) end

    for i = 1, #RemoteHandler.ATTEND_REACTIONS do
        local reaction = eventMessage.reactions:get( RemoteHandler.ATTEND_REACTIONS[ i ] )
        if not reaction then
            if not eventMessage:addReaction( RemoteHandler.ATTEND_REACTIONS[ i ] ) then
                return Logger.w "Reaction failed to add to message. Assuming message has been deleted. Bailing out"
            end
        elseif reaction.count > 1 then
            local users = reaction:getUsers()
            if not users then return Logger.w "Reaction missing from message. Assuming message has been deleted. Bailing out" end
            for user in users:iter() do
                if user.id ~= self.worker.client.user.id then reaction:delete( user.id ) end
            end
        end
    end
end

--[[
    @instance
    @desc Returns a table that can be used as the embed for
          an event/poll message (depending on arguments).

          If 'forPoll' the table removed will be populated
          with information regarding the poll for the event
          given (for the user provided and the guild).

          If not 'forPoll', the table returned will be populated
          with information regarding the event (for the user
          provided and the guild)
    @param <table - event>, [boolean - forPoll]
]]
function RemoteHandler:generateEmbed( guildID, userID, forPoll )
    local client, event = self.worker.client, self.worker.guilds[ guildID ].events[ userID ]
	if forPoll then
        print "Generating embeds for poll information is NYI"
	else
		local nickname = self.worker.client:getGuild( guildID ):getMember( userID ).nickname
		return {
			title = event.title,
			description = event.desc,
			fields = {
				{ name = "Location", value = event.location, inline = true },
				{ name = "Timeframe", value = event.timeframe, inline = true },
				{ name = "RSVPs (use the reactions underneath)", value = formResponses( client, event.responses ) }
			},

			author = {
				name = ( nickname and nickname .. " (" or "" ) .. client:getUser( userID ).name .. ( nickname and ")" or "" ),
				icon_url = client:getUser( userID ).avatarURL,
			},

			color = discordia.Color.fromRGB( 114, 137, 218 ).value,
		    timestamp = os.date "!%Y-%m-%dT%H:%M:%S",
			footer = { text = "Written by hbomb79 -- GitLab/GitHub" }
		}
	end
end

--[[
    @instance
    @desc Repairs the users event at the guild provided by ensuring that
          the messages for pushed events are fully intact (values match,
          reactions balanced, snowflake exists).

          If 'force' the channel will be cleared and the details for
          each published event will be pushed.
    @param <string - guildID>, <string - userID>, [boolean - force]
]]
function RemoteHandler:repairUserEvent( guildID, userID, force )
    local hash = guildID .. ":" .. userID
    -- if self.repairing[ hash ] then return Logger.w( "Refusing to repair user event (hash: " .. hash .. ") because this user event is currently being repaired" ) end
    self.repairing[ hash ] = true

    local event, channel = verifyAndFetchChannel( self, guildID, userID )
    if not ( event and event.published ) then return end
    if not ( event.snowflake and channel:getMessage( event.snowflake ) ) then
        local eventMessage = channel:send { embed = self:generateEmbed( guildID, userID ) }
        if not eventMessage then
            return Logger.e( "Failed to push event message for user "..userID.." event to guild " .. guildID )
        end

        event.snowflake, event.updated = eventMessage.id, false
        Logger.w( "Event snowflake missing (or message missing from remote), pushing event message to remote" )
    elseif event.updated then
        channel:getMessage( event.snowflake ):setEmbed( self:generateEmbed( guildID, userID ) )
        event.updated = false

        Logger.i( "Event snowflake valid, but event has changed — editing message" )
    end

    if event.poll then
        if not ( event.poll.snowflake and channel:getMessage( event.poll.snowflake ) ) then
            Logger.w( "Poll snowflake missing (or message missing from remote), pushing event message to remote" )
            self:pushPollToRemote( guildID, userID, true )
        elseif event.poll.updated then
            Logger.i( "Poll snowflake valid, but event has changed — editing message" )
            channel:getMessage( event.poll.snowflake ):setEmbed( self:generateEmbed( guildID, userID, true ) )
        end
    end

    -- Repair the reactions attached to both event and poll messages (if present).
    coroutine.wrap( self.repairReactions )( self, guildID, userID, event, channel )
    self.worker:saveGuilds()
    self.repairing[ hash ] = nil
    return Logger.s( "Repaired user event (on remote) at guild '"..guildID.."' for user '"..userID.."'" )
end

--[[
    @instance
    @desc Fixes all events published to the guild
    @param <string - guildID>, [boolean - force]
]]
function RemoteHandler:repairGuild( guildID, force )
    local events = self:getPublishedEvents( guildID )
    for e = 1, #events do
        self:repairUserEvent( guildID, events[ e ].author, force )
    end
end

--[[
    @instance
    @desc Repairs all events published to all registered guilds
    @param [boolean - force]
]]
function RemoteHandler:repairAllGuilds( force )
    for guildID in pairs( self.worker.guilds ) do
        coroutine.wrap( self.repairGuild )( self, guildID, force ) -- Each guild has it's own coroutine to repair itself in. Event's inside the same guild will run synchronously
    end
end

return abstract( true ):compile()
