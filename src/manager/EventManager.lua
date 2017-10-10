local Reporter, Logger, Manager, RemoteHandler = require "src.util.Reporter", require "src.util.Logger", require "src.manager.Manager", require "src.util.RemoteHandler"

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

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:deleteEvent( guildID, userID )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "delete event", guildID, userID, "the user doesn't own an event at this guild" ) )
    end

    if event.published then
        Logger.i( "Attempting to delete published event -- unpublishing event first" )
        self:unpublishEvent( guildID, userID )
    end

    self.worker.guilds[ guildID ].events[ userID ] = nil
    self:saveEvents()

    return Logger.s( SUCCESS:format( "Deleted event", guildID, userID ) )
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
    self:repairUserEvent( guildID, userID )
    self:saveEvents()

    return Logger.s( SUCCESS:format( "Published event", guildID, userID ) )
end

--[[
    @instance
    @desc Unpublishes the event owned by the user at the guild provided.

          * Will fail for the following reasons -- use 'errorCode' to determine reason:
            1: user doesn't own an event at this guild
            2: user's event is not published
    @param <string - guildID>, <string - userID>
    @return <boolean - success>, <string - output>, [number - errorCode]
]]
function EventManager:unpublishEvent( guildID, userID )
    local event = self:getEvent( guildID, userID )
    if not event then
        return report( 1, REFUSE_ERROR:format( "unpublish event", guildID, userID, "the user doesn't own an event at this guild" ) )
    elseif not event.published then
        return report( 2, REFUSE_ERROR:format( "unpublish event", guildID, userID, "the user's event is not published" ) )
    end

    self:revokeFromRemote( guildID, userID )
    event.published = nil

    self:saveEvents()

    return Logger.s( SUCCESS:format( "Unpublished event", guildID, userID ) )
end

extends "Manager" mixin "RemoteHandler"
return EventManager:compile()
