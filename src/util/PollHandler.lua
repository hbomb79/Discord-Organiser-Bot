local Logger, Reporter = require "src.util.Logger", require "src.util.Reporter"

local REFUSE_ERROR, SUCCESS = "Refusing to %s at guild %s for user %s because %s", "%s at guild %s for user %s"
local PollHandler = class "PollHandler" {}

--[[
    @instance
    @desc
]]
function PollHandler:assignPollIDs( guildID, noSave )
    local guildEvents, ID = self.worker.guilds[ guildID ].events, 1
    for userID, event in pairs( guildEvents ) do
        if event.poll and event.published then
            if event.poll.id ~= ID then event.poll.updated = true end

            event.poll.id, ID = ID, ID + 1
        end
    end

    if not noSave then self:saveEvents() end
end

--[[
    @instance
    @desc Creates a poll structure on the event at the
          guild provided by the user provided.

          The poll will not appear when the event
          is published unless it has options
          attached to it (more than 0).

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: The user doesn't own an event at the guild
            2: The user already has a poll attached to this event
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function PollHandler:createPoll( guildID, userID )
    local event = self:getEvent( guildID, userID )
    if not event then
        return self:report( 1, REFUSE_ERROR:format( "create poll", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif event.poll then
        return self:report( 2, REFUSE_ERROR:format( "create poll", guildID, userID, "the user has already attached a poll to their event" ) )
    end

    event.poll = {
        desc = "No Poll Description",
        options = {},
        responses = {}
    }

    self:saveEvents( event.poll )
    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Created poll", guildID, userID ) )
end

--[[
    @instance
    @desc Removes a poll from the event at the guild
          provided by the user provided.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: The user doesn't own an event at this guild
            2: The user's event has no poll attached
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function PollHandler:deletePoll( guildID, userID )
    local event = self:getEvent( guildID, userID )
    if not event then
        return self:report( 1, REFUSE_ERROR:format( "delete poll", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.poll then
        return self:report( 2, REFUSE_ERROR:format( "delete poll", guildID, userID, "the user's event has no poll attached" ) )
    end

    self:revokeFromRemote( guildID, userID )

    event.poll = false
    self:saveEvents( event.poll )

    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Deleted poll", guildID, userID ) )
end

--[[
    @instance
    @desc Sets the description of the poll attached to
          the event at the guild provided by the user
          provided.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: The user doesn't own an event at this guild
            2: The user's event has no poll attached
    @param <string - guildID>, <string - userID>, <string - desc>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function PollHandler:setPollDescription( guildID, userID, desc )
    local event = self:getEvent( guildID, userID )
    if not event then
        return self:report( 1, REFUSE_ERROR:format( "set poll description", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.poll then
        return self:report( 2, REFUSE_ERROR:format( "set poll description", guildID, userID, "the user's event has no poll attached" ) )
    end

    event.poll.desc = desc
    self:saveEvents( event.poll )

    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Set poll description", guildID, userID ) )
end

--[[
    @instance
    @desc Adds a poll option to the poll attached to the
          event at the guild provided for the user
          provided.

          A maximum of 10 poll options can exist on
          the poll and they are automatically numbered
          based on the order they were added.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: The user doesn't own an event at this guild
            2: The user's event has no poll attached
            3: The poll attached to the user's event has already got 10 options (10 being the max.).
    @param <string - guildID>, <string - userID>, <string - option>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function PollHandler:addPollOption( guildID, userID, option )
    local event = self:getEvent( guildID, userID )
    if not event then
        return self:report( 1, REFUSE_ERROR:format( "add poll option", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.poll then
        return self:report( 2, REFUSE_ERROR:format( "add poll option", guildID, userID, "the user's event has no poll attached" ) )
    elseif #event.poll.options >= 10 then
        return self:report( 3, REFUSE_ERROR:format( "add poll option", guildID, userID, "the event's poll has already got 10 poll options, which is the maximum amount" ) )
    end

    table.insert( event.poll.options, option )
    self:saveEvents( event.poll )

    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Added poll option", guildID, userID ) )
end

--[[
    @instance
    @desc Removes the poll option at the index provided
          from the poll attached to the event at the guild
          provided by the user provided.

          * Will fail for the following reasons -- use 'errorCode' to determine the reason:
            1: The user doesn't own an event at this guild
            2: The user's event has no poll attached
            3: The index provided is invalid
            4: There is no poll option at the index provided
    @param <string - guildID>, <string - userID>, <number - index>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function PollHandler:removePollOption( guildID, userID, index )
    local event, index = self:getEvent( guildID, userID ), index and tonumber( index )
    if not event then
        return self:report( 1, REFUSE_ERROR:format( "remove poll option", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.poll then
        return self:report( 2, REFUSE_ERROR:format( "remove poll option", guildID, userID, "the user's event has no poll attached" ) )
    elseif not index then
        return self:report( 3, REFUSE_ERROR:format( "remove poll option", guildID, userID, "the index '" .. tostring( index ) .. "' provided is invalid. Must be a number that represents a poll option" ) )
    elseif not event.poll.options[ index ] then
        return self:report( 4, REFUSE_ERROR:format( "remove poll option", guildID, userID, "the index provided '"..tostring( index ) .. "' doesn't represent a valid poll option" ) )
    end

    table.remove( event.poll.options, index )

    local responses = event.poll.responses
    for ID, response in pairs( responses ) do
        if response == index then
            responses[ ID ] = nil

            Reporter.warning( self.worker.client:getUser( ID ), "Vote Discarded", "Your vote cast on the event poll for the event **"..event.title.."** inside guild " .. guildID .. " has been discarded because the option you voted on has been removed" )
        elseif response > index then responses[ ID ] = response - 1 end
    end

    self:saveEvents( event.poll )
    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Removed poll option", guildID, userID ) )
end

--[[
    @instance
    @desc Submits a poll vote for 'castingUserID' on poll option 'index'
          on the poll attached to the event at the guild provided for
          the user provided.

          * Will fail for the following reasons -- use 'errorCode' to determine the reason:
            1: The user doesn't own a published event at this guild
            2: The user's event has no poll attached
            3: The index provided doesn't represent a valid poll option
    @param <string - guildID>, <string - userID>, <string - castingUserID>, <number - index>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function PollHandler:submitPollVote( guildID, userID, castingUserID, index )
    local event, index = self:getEvent( guildID, userID ), index and tonumber( index )
    if not ( event and event.published ) then
        return self:report( 1, REFUSE_ERROR:format( "submit user " .. userID .. " poll vote", guildID, userID, "the user doesn't own a published event at this guild" ) )
    elseif not event.poll then
        return self:report( 2, REFUSE_ERROR:format( "submit user " .. userID .. " poll vote", guildID, userID, "the user's event has no poll attached" ) )
    elseif not ( index and event.poll.options[ index ] ) then
        return self:report( 3, REFUSE_ERROR:format( "submit user " .. userID .. " poll vote", guildID, userID, "the index ("..tostring( index )..") is invalid as it doesn't represent an existing poll option" ) )
    end

    event.poll.responses[ castingUserID ] = index
    self:saveEvents( event.poll )
    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Submitted user " .. castingUserID .. " poll vote", guildID, userID ) )
end

return abstract( true ):compile()
