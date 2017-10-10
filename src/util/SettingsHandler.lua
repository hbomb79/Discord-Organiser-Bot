local SettingsHandler
local function checkPrefix( worker, guildID, value )
    if value == nil or ( #value >= 1 and #value <= 10 and not value:find "%s" ) then return true end

    return false, "Prefix is invalid. Must be between 1-10 character long and contain no spaces"
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

--[[
    A simple mixin class that abstracts the management of guild
    specific settings.

    Handles assigning setting values, defaults and getting/saving
    settings to file.
]]

SettingsHandler = class "SettingsHandler" {
    static = {
        SETTINGS = {
            prefix = {
                help = "",
                default = "!", -- This value will be returned when getting the property if was isn't set for the guild
                predicate = checkPrefix, -- This function will be called (if set) when the setting is changed. If this function returns false, the property will NOT be set and the 2nd return from this function will be used as the reason (string).
            },
            channelID = {
                help = "",
                useFallback = true, -- If the property isn't set, the fallback value (in this case, _channelID) will be used on the guild properties
                default = false -- If the fallback isn't available, false will be used. This will stop the bot from attempting to push events for this guild (no channel)
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

    local ok, err = type( config.predicate ) ~= "function" and true or config.predicate( self, guildID, value )
    if not ok then return false, err end

    guildConfig[ property ] = value
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
    local guildConfig, config = checkGuildAndProperty( self, guildID, property )
    if not guildConfig then return false, config end

    local fallbackProperty = type( config.useFallback ) == "string" and config.useFallback or "_" .. property
    return guildConfig[ property ] or ( config.useFallback and guildConfig[ fallbackProperty ] ) or config.default
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
