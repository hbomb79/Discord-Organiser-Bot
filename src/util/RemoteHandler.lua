local discordia = luvitRequire "discordia"
local Worker = require "src.lib.class".getClass "Worker"

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


--[[
    @instance pushing - table (def. {}) - A key-value pair table that is used to keep track of the guilds currently being pushed.

    An abstract class that is mixed-in by the EventManager class.

    Is used to handle event details being pushed to guild channels.

    The channel used is defined by the servers, therefore if no
    configuration for the guild is available on the worker -- or
    no channel has been defined, the guild will not be pushed.
]]

local RemoteHandler = class "RemoteHandler" {
    pushing = {};
}

--[[
    @instance
    @desc Removes the messages attached to the event provided
    @param <string - guildID>, <string - userID>
]]
function RemoteHandler:revokeFromRemote( guildID, userID )
    --TODO local guild, user = self.worker.client:getGuild( guildID ), self.worker.client:getUser( userID )
end

--[[
    @instance
    @desc Pushes the event message (not the poll) for user at
          guild to the remote. If not 'noReact' then the valid
          reactions (for RSVPs) will be added to the message
          asynchronously
    @param <string - guildID>, <string - userID>
]]
function RemoteHandler:pushEventToRemote( guildID, userID )

end

--[[
    @instance
    @desc Pushes the poll message (not the event) for user at
          the guild to the remote. If not 'noReact' then the
          value reactions (for voting) will be added to the
          message asynchronously
    @param <string - guildID>, <string - userID>
]]
function RemoteHandler:pushPollToRemote( guildID, userID )

end

--[[
    @instance
    @desc Repairs the reactions for the event provided (both
          poll and event message(s)).
    @param <string - guildID>, <string - userID>
]]
function RemoteHandler:repairReactions( guildID, userID )

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
function RemoteHandler:generateEmbed( event, forPoll )
    local client = self.worker.client
	if forPoll then
        print "Generating embeds for poll information is NYI"
	else
		local userID = event.author
		local nickname = worker.cachedGuild:getMember( userID ).nickname
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
    local event = self:getEvent( guildID, userID )
    if not ( event and event.published ) then return end

    local channelID = self.worker.guilds[ guildID ].channelID
    if not channelID then return end

    local channel = self.worker:getGuild( guildID ):getChannel( channelID )
    if not channel then return end

    if not ( event.snowflake and channel:getMessage( event.snowflake ) ) then
        self:pushEventToRemote( guildID, userID, true )
    elseif event.updated then
        -- Edit the message
    end

    if event.poll and not ( event.poll.snowflake and channel:getMessage( event.poll.snowflake ) ) then
        self:pushPollToRemote( guildID, userID, true )
    elseif event.poll.updated then
        -- Edit the message
    end

    -- Repair the reactions attached to both event and poll messages (if present).
    self:repairReactions( guildID, userID )
end

--[[
    @instance
    @desc Fixes all events published to the guild
    @param <string - guildID>, [boolean - force]
]]
function RemoteHandler:repairGuildEvents( guildID, force )
    local events = self:getPublishedEvents( guildID )
    for e = 1, #events do
        self:repairUserEvent( guildID, events[ e ].author, force )
    end
end

return abstract( true ):compile()
