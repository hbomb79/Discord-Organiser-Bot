local Reporter, Logger, Manager, RemoteHandler = require "src.util.Reporter", require "src.util.Logger", require "src.manager.Manager", require "src.util.RemoteHandler"

local VALID_SETTINGS = { title = true, desc = true, location = true, timeframe = true }

local REFUSE_ERROR, SUCCESS = "Refusing to %s at guild %s for user %s because %s", "%s at guild %s for user %s"
local function report( code, ... )
    local _, reason = Logger.w( ... )
    return false, reason, code
end

local function notifyMembers( worker, guildID, userID, event, title, desc )
    for userID, responseState in pairs( event.responses ) do
        if responseState == 1 or responseState == 2 then
            Reporter.info( worker.client:getUser( userID ):getPrivateChannel(), title, desc )
        end
    end
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
    @desc Flags the event provided as being updated (if an
          event is provided).

          Then saves all event details via worker:saveGuilds
    @param [table - event]
]]
function EventManager:saveEvents( event )
    if event then event.updated = true end
    self.worker:saveGuilds()
end

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
    @desc Returns the currently published event for the guild provided, or nil
          if none published.

          If a valid userID is provided then the published event for
          that user (in the guild) will be returned, or nil if the user has no
          published event in this guild.
    @param <string - guildID>, [string - userID]
    @return <table - event> - If a userID was provided and the user owns an event at the guild, the event will be returned
    @return <table - events> - If no userID was provided a table of all the published events will be returned
    @return nil - No event published (by user, or in general)
]]
function EventManager:getPublishedEvents( guildID, userID )
    local guild = self.worker.guilds[ guildID ]
    if not ( guild and guild.events ) then return end

    local events = guild.events
    if userID then
        if not ( events[ userID ] and events[ userID ].published ) then return end

        return events[ userID ]
    else
        local evs = {}
        for user, event in pairs( events ) do
            if event.published then table.insert( evs, event ) end
        end

        return evs
    end
end

--[[
    @instance
    @desc Creates an event for the user at the guild provided.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user already has an event at this guild
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
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

    self:saveEvents( self.worker.guilds[ guildID ].events[ userID ] )
    return Logger.s( SUCCESS:format( "Created and saved event", guildID, userID ) )
end

--[[
    @instance
    @desc Deletes the event owned by the user at the guild provided. If the event is published
          it will be unpublished automatically before deletion.

          All RSVPs, poll votes and event details will be lost when the event is deleted. These could
          potentially be reconstructed from log details, however it is unlikely.

          Take care when deleting events.

          If not 'noNotify', users that RSVPd as 'going' or 'maybe going'
          to the event being deleted will be notified that the event
          has been cancelled (NOTE: This only applies if the event has
          been published).

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:deleteEvent( guildID, userID, noNotify )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "delete event", guildID, userID, "the user doesn't own an event at this guild" ) )
    end

    if event.published then
        Logger.i( "Attempting to delete published event -- unpublishing event first" )
        self:unpublishEvent( guildID, userID, noNotify )
    end

    self.worker.guilds[ guildID ].events[ userID ] = nil
    self:saveEvents()

    return Logger.s( SUCCESS:format( "Deleted event", guildID, userID ) )
end

--[[
    @instance
    @desc Concludes the event owner by the user at the guild provided.
          The event will be deleted and all members that RSVPd as 'going'
          or 'maybe going' will be notified that the event has finished.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
            2: user's event is not published
    @param <string - guildID>, <string - userID>
]]
function EventManager:concludeEvent( guildID, userID )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "conclude event", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.published then
        return report( 2, REFUSE_ERROR:format( "conclude event", guildID, userID, "the user's event is not published, and cannot be concluded" ) )
    end

    local success, output, errorCode = self:deleteEvent( guildID, userID, true )
    if success then
        notifyMembers( self.worker, guildID, userID, event, "Event Finished", "The event **" .. ( event.title or "no title" ) .. "** at guild " .. guildID .. " authored by user " .. userID .. " has completed." )
    else return false, output, errorCode + 2 end

    return Logger.s( SUCCESS:format( "Conluded event", guildID, userID ) )
end

--[[
    @instance
    @desc Publishes the event owned by the user at the guild provided.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
            2: user's event is already published
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:publishEvent( guildID, userID )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "publish event", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif event.published then
        return report( 2, REFUSE_ERROR:format( "publish event", guildID, userID, "the user's event is already published" ) )
    end

    event.published = true
    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )
    self:saveEvents()

    return Logger.s( SUCCESS:format( "Published event", guildID, userID ) )
end

--[[
    @instance
    @desc Unpublishes the event owned by the user at the guild provided.

          If NOT 'noNotify', users that RSVPd as 'going' or 'maybe going'
          to the event being unpublished will be notified that the event
          has been CANCELLED.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
            2: user's event is not published
    @param <string - guildID>, <string - userID>, [boolean - noNotify]
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:unpublishEvent( guildID, userID, noNotify )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "unpublish event", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.published then
        return report( 2, REFUSE_ERROR:format( "unpublish event", guildID, userID, "the user's event is not published" ) )
    end

    coroutine.wrap( self.revokeFromRemote )( self, guildID, userID )
    event.published = nil

    if not noNotify then
        notifyMembers( self.worker, guildID, userID, event, "Event Cancelled", "The event **" .. ( event.title or "no title" ) .. "** by user " .. event.author.id .. " at guild " .. guildID .. " has been cancelled." )
    end

    self:saveEvents()

    return Logger.s( SUCCESS:format( "Unpublished event", guildID, userID ) )
end

--[[
    @instance
    @desc Sets the property to the value given on the event provided.

          * Will fail for the following reasons -- user 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
            2: property name is invalid
    @param <string - guildID>, <string - userID>, <string - property>, <Any - value>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:setEventProperty( guildID, userID, property, value )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "set event property", guildID, userID, "the user doesn't an event at this guild" ) )
    elseif not VALID_SETTINGS[ property ] then
        return report( 2, REFUSE_ERROR:format( "set event property", guildID, userID, "the setting provided '"..tostring( property ).."' is invalid. Valid settings: title, desc, location, timeframe." ) )
    end

    event[ property ] = value ~= "none" and value or nil
    self:saveEvents( event )
    coroutine.wrap( self.repairUserEvent )( self, guildID, userID )

    return Logger.s( SUCCESS:format( "Set event property '"..property.."' to '"..value.."'", guildID, userID ) )
end

--[[
    @instance
    @desc Sets the attending state of the user provided to the level provided
          on the event published at guild/user provided.

          If 'noUpdate', the event that has been responded to will NOT be repaired (repairUserEvent should
          be called manually to ensure proper display of message now that RSVPs may have changed).

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
            2: event selected is not published
            3: responding user state is invalid
            4: responding user has already responded using the same state
    @param <string - guildID>, <string - userID>, <string - respondingUserID>, <number - respondingUserState>, [boolean - noUpdate]
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:respondToEvent( guildID, userID, respondingUserID, respondingUserState, noUpdate )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "respond to event", guildID, userID, "the user doesn't have an event at this guild" ) )
    elseif not event.published then
        return report( 2, REFUSE_ERROR:format( "respond to event", guildID, userID, "the users event is not published" ) )
    elseif not ( type( respondingUserState ) == "number" and respondingUserState >= 0 and respondingUserState <= 2 ) then
        return report( 3, REFUSE_ERROR:format( "respond to event", guildID, userID, "the responding state is invalid. Can only be 0 (not attending), 1 (maybe attending), or 2 (is attending). Received: " .. tostring( respondingUserState ) ) )
    elseif event.responses[ respondingUserID ] == respondingUserState then
        return report( 4, REFUSE_ERROR:format( "respond to event", guildID, userID, "the responding user has already responded using the same responding state ("..respondingUserState..")" ) )
    end

    event.responses[ respondingUserID ] = respondingUserState
    self:saveEvents( event )
    if not noUpdate then coroutine.wrap( self.repairUserEvent )( self, guildID, userID ) end

    return Logger.s( SUCCESS:format( "Responded to event (for user '"..respondingUserID.."' as state '"..respondingUserState.."')", guildID, userID ) )
end

extends "Manager" mixin "RemoteHandler"
return EventManager:compile()
