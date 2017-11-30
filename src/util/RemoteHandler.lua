local Logger, Reporter, Worker, CommandManager = require "src.util.Logger", require "src.util.Reporter", require "src.lib.class".getClass "Worker", require "src.lib.class".getClass "CommandManager"
local discordia = luvitRequire "discordia"

local function formResponses( client, responses )
	local str, states = "", { {}, {}, {} }
	for userID, response in pairs( responses ) do table.insert( states[ response + 1 ], userID ) end

	local function out( a ) str = str .. "\n" .. a end
	for s = #states, 1, -1 do
		local state = states[ s ]
		if #state > 0 then
			local name = Worker.ATTEND_ENUM[ s ]
			out( ("__%s%s__ (%s)"):format( name:sub( 1, 1 ):upper(), name:sub( 2 ), #state ) )

			for r = 1, #state do out( "- <@" .. state[ r ] .. ">" ) end
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
        POLL_REACTIONS = { "1⃣", "2⃣", "3⃣", "4⃣", "5⃣", "6⃣", "7⃣", "8⃣", "9⃣", "🔟" };
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

    local accumulatedReactions = {}
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
                if user.id ~= self.worker.client.user.id then
                    accumulatedReactions[ user.id ] = CommandManager.REACTION_ATTENDANCE_CODES[ reaction.emojiName ]

                    reaction:delete( user.id )
                end
            end
        end
    end

    if next( accumulatedReactions ) then
        local count, evManager = 0, self.worker.eventManager
        for userID, code in pairs( accumulatedReactions ) do
            evManager:respondToEvent( guildID, event.author, userID, code, true )
            Reporter.info( self.worker.client:getUser( userID ):getPrivateChannel(), "RSVP Applied", "You RSVPd to an event while this bot was offline (event **"..event.title.."**, authored by user "..event.author.." in guild "..guildID..").\n\nYour RSVP was found on bot startup has been applied (set RSVP state to **"..tostring( Worker.ATTEND_ENUM[ code + 1 ] ).."**)" )
            count = count + 1
        end

        coroutine.wrap( evManager.repairUserEvent )( self, guildID, userID )
        Logger.s( "Resolved " .. count .. " offline RSVPs for event at guild " .. guildID .. " for user " .. userID .. " -- repairing event" )
    end

    if not event.poll then return end
    local pollMessage = channel:getMessage( event.poll.snowflake )

    -- Repair poll options.
    local maxNeeded, accumulatedPollReactions = #event.poll.options, {}
    for i = 1, #RemoteHandler.POLL_REACTIONS do
        local reaction = pollMessage.reactions:get( RemoteHandler.POLL_REACTIONS[ i ] )
        if i > maxNeeded then
            if reaction then
                local users = reaction:getUsers()
                if not users then return Logger.w( "Failed to fetch users for reaction. Assuming message or reaction has been removed. Bailing out" ) end

                for user in users:iter() do reaction:delete( user.id ) end
            end
        else
            if not reaction then
                if not pollMessage:addReaction( RemoteHandler.POLL_REACTIONS[ i ] ) then
                    return Logger.w "Reaction failed to add to poll message. Assuming message has been deleted. Bailing out"
                end
            elseif reaction.count > 1 then
                local users = reaction:getUsers()
                if not users then return Logger.w( "Failed to fetch users for reaction. Assuming message or reaction has been removed. Bailing out" ) end

                for user in users:iter() do
                    if user.id ~= self.worker.client.user.id then
                        reaction:delete( user.id )
                    end
                end
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
        local poll = event.poll
        -- Count all votes for the options
        local voteCount, fields = {}, {}
        for ID, response in pairs( poll.responses ) do voteCount[ response ] = voteCount[ response ] and voteCount[ response ] + 1 or 1 end

        local options = poll.options
        for i = 1, #options do
            local votes = voteCount[ i ] or 0

            table.insert( fields, {
                name = ( "%i) %s" ):format( i, options[ i ] ),
                value = "*" .. votes .. " vote" .. ( votes == 1 and "" or "s" ) .. "*"
            } )
        end

        if #fields == 0 then table.insert( fields, { name = "No Options", value = "There are no options for this poll yet." } ) end

        return {
            title = event.title .. " - Poll",
            description = poll.desc,
            fields = fields,

            color = discordia.Color.fromRGB( 114, 137, 218 ).value
        }
	else
		local nickname = self.worker.client:getGuild( guildID ):getMember( userID ).nickname
		return {
			title = event.title,
			description = event.desc,
			fields = {
				{ name = "Location", value = event.location, inline = true },
				{ name = "Timeframe", value = event.timeframe, inline = true },
				{ name = "RSVPs", value = formResponses( client, event.responses ) }
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

          If 'noSave' the guilds won't be saved after this function
          completes. This is to prevent mass-saving when all guilds
          are repaired. Should be left as 'nil', or set to 'false' when
          only repairing one event.
    @param <string - guildID>, <string - userID>, [boolean - force], [boolean - noSave]
]]
function RemoteHandler:repairUserEvent( guildID, userID, force, noSave )
    if force then
        Logger.i( "Attempting to FORCIBLY repair user event at guild " .. guildID .. " for user " .. userID, "Revoking messages from target channel before proceeding" )
        self:revokeFromRemote( guildID, userID )
        Logger.s( "Messages from remote revoked. Proceeding with repair (messages will be missing, causing recreation)" )
    end

    local event, channel = verifyAndFetchChannel( self, guildID, userID )
    if not ( event and event.published ) then return end
    if not ( event.snowflake and channel:getMessage( event.snowflake ) ) then
        Logger.w( "Event snowflake invalid, pushing event message to remote" )

        local eventMessage = channel:send { content = self.worker:getOverride( guildID, "leadingMessage" ) or "", embed = self:generateEmbed( guildID, userID ) }
        if not eventMessage then
            return Logger.e( "Failed to push event message for user "..userID.." to guild " .. guildID )
        end

        event.snowflake, event.updated = eventMessage.id, false
    elseif event.updated then
        local message = channel:getMessage( event.snowflake )
        message:setEmbed( self:generateEmbed( guildID, userID ) )
        message:setContent( self.worker:getOverride( guildID, "leadingMessage" ) or "" )
        event.updated = false

        Logger.i( "Event snowflake valid, but event has changed — editing message" )
    end

    if event.poll then
        if not ( event.poll.snowflake and channel:getMessage( event.poll.snowflake ) ) then
            Logger.w( "Poll snowflake invalid, pushing event message to remote" )

            local pollMessage = channel:send { embed = self:generateEmbed( guildID, userID, true ) }
            if not pollMessage then
                return Logger.e( "Failed to push poll message for user " .. userID .. " to guild " .. guildID )
            end

            event.poll.snowflake, event.poll.updated = pollMessage.id, false
        elseif event.poll.updated then
            Logger.i( "Poll snowflake valid, but event has changed — editing message" )
            channel:getMessage( event.poll.snowflake ):setEmbed( self:generateEmbed( guildID, userID, true ) )
        end
    end

    -- Repair the reactions attached to both event and poll messages (if present).
    coroutine.wrap( self.repairReactions )( self, guildID, userID, event, channel )
    if not noSave then self.worker:saveGuilds() end

    return true
end

--[[
    @instance
    @desc Fixes all events published to the guild

          If 'force', all messages will first be deleted and then
          recreated. In this sense, the messages are not being
          repaired, but replaced.

          Using 'force' should be avoided as it is rather
          intensive. Only use force if a normal repair
          didn't resolve the issue.
    @param <string - guildID>, [boolean - force]
]]
function RemoteHandler:repairGuild( guildID, force )
    local events = self:getPublishedEvents( guildID )
    for e = 1, #events do
        self:repairUserEvent( guildID, events[ e ].author, force, true )
    end

    self.worker:saveGuilds()
end

--[[
    @instance
    @desc Repairs all events published to all registered guilds

          If 'force', all messages will first be deleted and then
          recreated. In this sense, the messages are not being
          repaired, but replaced.

          Using 'force' should be avoided as it is rather
          intensive. Only use force if a normal repair
          didn't resolve the issue.
    @param [boolean - force]
]]
function RemoteHandler:repairAllGuilds( force )
    Logger.i( "Repairing all guilds", "Force: " .. tostring( force ) )
    for guildID in pairs( self.worker.guilds ) do
        coroutine.wrap( self.repairGuild )( self, guildID, force ) -- Each guild has it's own coroutine to repair itself in. Event's inside the same guild will run synchronously
    end
end

return abstract( true ):compile()
