local Logger, SettingsHandler = require "src.util.Logger"
local patternMatches = { ["^"] = "%^", ["$"] = "%$", ["("] = "%(", [")"] = "%)", ["%"] = "%%", ["*"] = "%*", ["."] = "%.", ["["] = "%[", ["]"] = "%]", ["+"] = "%+", ["-"] = "%-" }
local function checkPrefix( worker, guildID, value )
    if value == nil or ( #value >= 1 and #value <= 10 and not value:find "%s" ) then return true end

    return false, "Prefix is invalid. Must be between 1-10 character long and contain no spaces"
end

local function checkChannel( worker, guildID, value )
    if value == nil then return true end
    value = value:match "%<#(%w+)%>" or value

    local guild = worker.client:getGuild( guildID )
    if not guild:getChannel( value ) then
        return false, "Channel provided doesn't exist (either provide the channel ID, or mention the channel using `#channel-name-here`)"
    end

    return value
end

local function checkGuildAndProperty( worker, guildID, property )
    local guildConfig, config = worker.guilds[ guildID ], SettingsHandler.SETTINGS[ property ]
    if not config then
        return false, "Invalid property"
    elseif not guildConfig then
        return false, "Unknown guild"
    end

    return guildConfig, config
end

local function getProperty( worker, guildID, property )
    local guildConfig, config = checkGuildAndProperty( worker, guildID, property )
    if not guildConfig then return false end

    local fallbackProperty = type( config.useFallback ) == "string" and config.useFallback or "_" .. property
    return guildConfig[ property ] or ( config.useFallback and guildConfig[ fallbackProperty ] ) or config.default, config
end

--[[
    A simple mixin class that abstracts the management of guild
    specific settings.

    Handles assigning setting values, defaults and getting/saving
    settings to file.

    Each setting can have the following configurations:
        help: A string displayed when the user requests help for the setting (via 'cmd settings')
        default: The value returned when no other value can be found
        predicate: A function that is called before the value is set. If the function returns false, the value won't be updated.
                   If the function returns true, the value will be set. If the function returns another value, the returned
                   value will be used to set the property
        show: A function called when the property is requested for display purposes (via self:getOverrideForDisplay). Allows
              markdown/Discord formatting (such as for channel names, etc).
        useFallback: If true, the value of the property with an underscore prefixed (eg: prefix -> _prefix) will be used if a normal value cannot be found
        get: If set as a function, this function is called when getting the override.
        preSet: If set as a function, it is called just before setting the override value. Has no bearing on the value being set
        postSet: If set as a function, it is called just after setting the override value. Like preSet, this function has no control over the value being set
]]

SettingsHandler = class "SettingsHandler" {
    static = {
        SETTINGS = {
            prefix = {
                help = "",
                default = "!",
                predicate = checkPrefix,
                get = function( _, __, val ) return val and val:gsub( ".", patternMatches ) or val end
            },
            channel = {
                help = "",
                useFallback = true,
                predicate = checkChannel,
                show = function( _, __, val ) return "<#" .. val .. ">" end,
                preSet = function( self, guildID, old, new )
                    if not old then return end

                    local events = self.guilds[ guildID ].events
                    for userID in pairs( events ) do
                        self.eventManager:revokeFromRemote( guildID, userID )
                    end
                end,
                postSet = function( self, guildID, channel )
                    if not channel then return end

                    self.eventManager:repairGuild( guildID )
                end
            },
            leadingMessage = {
                help = "The content of the message that leads the embed. This is usually used to tag people, or provide generic information. Not controllable on a per-event basis",
                postSet = function( self, guildID )
                    self.eventManager:repairGuild( guildID, true )
                end
            }
        };
    }
}

--[[
    @instance
    @desc Sets the value of the guild override given.

          If fails, returns false and a reason for failure.
    @param <string - guildID>, <string - property>, <Any - value>
    @return <boolean - success>, [string - failureReason]
]]
function SettingsHandler:setOverride( guildID, property, value )
    local guildConfig, config = checkGuildAndProperty( self, guildID, property )
    if not guildConfig then return false, config end

    local function set( property, val )
        if type( config.preSet ) == "function" then config.preSet( self, guildID, guildConfig[ property ], val ) end
        guildConfig[ property ] = val
        if type( config.postSet ) == "function" then config.postSet( self, guildID, val ) end
    end
    if type( config.predicate ) == "function" then
        local ok, err = config.predicate( self, guildID, value )
        if not ok then return false, err end

        set( property, ok ~= true and ok or value )
    else set( property, value ) end

    self:saveGuilds()
    return true
end

--[[
    @instance
    @desc Returns the guild override for the property.

          If no guild override, tries to use fallback override
          if available. If not, returns default (or nil if no default)
    @param <string - guildID>, <string - property>
    @return [Any - value] - Returns the value regardless of whether it found a value (ie: could return nil if that's the value it found -- a default)
    @return <boolean - succcess>, <string - failureReason> - Returns false and the reason if it couldn't search for value
]]
function SettingsHandler:getOverride( guildID, property )
    local ret, config = getProperty( self, guildID, property )
    if not ( ret and config ) then return ret, config end

    if type( config.get ) == "function" then return config.get( self, guildID, ret ) end

    return ret
end

--[[
    @instance
    @desc Returns the value for the guild override in a user
          readable way by using the 'show' method attached
          to the setting type

          It's important to note that this function does NOT
          use the properties 'get' method unless told to
          via arg #3 (useGetter)
    @param <string - guildID>, <string - property>, [boolean - useGetter]
]]
function SettingsHandler:getOverrideForDisplay( guildID, property, useGetter )
    local ret, config = getProperty( self, guildID, property )
    if not ( ret and config ) then return ret, config end

    if useGetter and type( config.get ) == "function" then ret = config.get( self, guildID, ret ) end
    if type( config.show ) == "function" then
        return config.show( self, guildID, ret )
    end

    return ret
end

--[[
    @instance
    @desc Returns true if the property provided has no
          explicit value set for the guild (ie: returns
          true if the default value is being used for
          the property).

          Does NOT return true if the value being used
          is the *same as* the default value -- the value
          has to be used as a result of no value being set
          for the guild specifically.
    @param <string - guildID>, <string - property>
    @return <boolean - isUsingDefault>
]]
function SettingsHandler:isOverrideDefault( guildID, property )
    local guildConfig, config = checkGuildAndProperty( self, guildID, property )
    if not guildConfig then return false, config end

    local fallbackProperty = type( config.useFallback ) == "string" and config.useFallback or "_" .. property
    if guildConfig[ property ] or ( config.useFallback and guildConfig[ fallbackProperty ] ) then return false end

    return true
end

return abstract( true ):compile()
