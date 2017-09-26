-- local JSONPersist = require "src.lib.JSONPersist"
local Logger = require "src.client.Logger"

--[[
	WIP
]]

Logger.d "Compiling RestrictionManager"
local RestrictionManager = class "RestrictionManager" {
	restrictedUsers = {};
	bannedUsers = {};
}

-- Administrative --

--[[
	@constructor
	@desc Calls the Manager super and then loads banned users
]]
function RestrictionManager:__init__( ... )
	self:super( ... )
	self:loadBannedUsers()
end

--[[
	@instance
	@desc
]]
function RestrictionManager:loadBannedUsers()

end

--[[
	@instance
	@desc
]]
function RestrictionManager:saveBannedUsers()

end

-- Main --

--[[
	@instance
	@desc
]]
function RestrictionManager:banUser( userID )

end

--[[
	@instance
	@desc
]]
function RestrictionManager:isUserBanned( userID )

end

--[[
	@instance
	@desc
]]
function RestrictionManager:restrictUser()

end

--[[
	@instance
	@desc
]]
function RestrictionManager:isUserRestricted( userID, orBanned )

end

--[[
	@instance
	@desc
]]
function RestrictionManager:reportRestrictionViolation( userID )

end

extends "Manager"
return RestrictionManager:compile()