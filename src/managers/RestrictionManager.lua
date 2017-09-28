local JSONPersist = require "src.helpers.JSONPersist"
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
	self.bannedUsers = JSONPersist.loadFromFile ".banned"
end

-- Main --

--[[
	@instance
	@desc
]]
function RestrictionManager:banUser( userID )
	self.bannedUsers[ userID ] = true
	JSONPersist.saveToFile( ".banned", self.bannedUsers )

	Logger.s( "Banned user " .. self.worker.client:getUser( userID ).fullname, userID )
	return true
end

--[[
	@instance
	@desc
]]
function RestrictionManager:unbanUser( userID )
	if not self.bannedUsers[ userID ] then
		return Logger.e( "Refusing to lift ban on user " .. userID, "The user is not banned" )
	end

	self.bannedUsers[ userID ] = nil
	JSONPersist.saveToFile( ".banned", self.bannedUsers )

	Logger.s( "Lifted ban on user " .. self.worker.client:getUser( userID ).fullname, userID )
	return true
end

--[[
	@instance
	@desc
]]
function RestrictionManager:isUserBanned( userID )
	return self.bannedUsers[ userID ]
end

--[[
	@instance
	@desc
]]
function RestrictionManager:restrictUser( userID )
	self.restrictedUsers[ userID ] = 0
end

--[[
	@instance
	@desc
]]
function RestrictionManager:isUserRestricted( userID, orBanned )
	return self.restrictedUsers[ userID ] or ( orBanned and self.bannedUsers[ userID ] )
end

--[[
	@instance
	@desc
]]
function RestrictionManager:reportRestrictionViolation( userID )
	local name = self.worker.client:getUser( userID ).fullname
	Logger.i( "Attempting to record restriction violation for user " .. name, userID )

	if not self.restrictedUsers[ userID ] then
		Logger.w( "No restriction on record for " .. name, "Restricting user now" )
		self:restrictUser( userID )
	end

	self.restrictedUsers[ userID ] = self.restrictedUsers[ userID ] + 1
	Logger.i("User " .. name .. " has violated their restriction " .. self.restrictedUsers[ userID ] .. " times" )

	if self.restrictedUsers[ userID ] >= 10 then
		Logger.w( "Banning user " .. name .. " for excessive restriction violation" )
		self:banUser( userID )
	end

	Logger.s( "Reported restriction violation for " .. name )
	return true
end

extends "Manager"
return RestrictionManager:compile()
