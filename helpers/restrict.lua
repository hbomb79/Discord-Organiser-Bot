local function newRestriction( userID )
	return { id = userID, violations = 0, restricted = true }
end

return {
	restrictedUsers = {},
	bannedUsers = {},

	check = function( self )
		return true
	end,

	restrictUser = function( self, userID )
		log.i("Restricting user " .. tostring( userID ))
		if self.restrictedUsers[ userID ] then
			log.i("User already has a restriction record. Modifiying record to avoid violation losses")
			self.restrictedUsers[ userID ].restricted = true
		else
			log.i("User has no record. Creating new restriction")
			self.restrictedUsers[ userID ] = newRestriction( userID )
		end
	end,

	violate = function( self, user )
		log.i("User "..tostring( user ).." has violated restriction")
		local userID = user.id

		local restriction = self.restrictedUsers[ userID ]
		restriction.violations = restriction.violations + 1

		log.i("User has violated restriction " .. restriction.violations .. " times.")
		if restriction.violations > 10 then
			log.w("User has been banned due to excessive restriction violation")
			if not self.bannedUsers[ userID ] then reporter:failure( user, "Account Banned", "Your account has been permanently suspended. This bot will no longer respond to messages originating from this account.\n\nIf you believe this is in error please contact the guild owner/server administrators." ) end
			self.bannedUsers[ userID ] = true

			log.i("Saving banned users:")
			jpersist.saveTable( self.bannedUsers, "./banned.cfg" )
		end 
	end,

	unrestrictUser = function( self, userID )
		if self.restrictedUsers[ userID ] then
			log.i("Unrestricted user " .. tostring( userID ))
			self.restrictedUsers[ userID ].restricted = false
		end
	end,

	isUserRestricted = function( self, userID )
		return self.restrictedUsers[ userID ] and self.restrictedUsers[ userID ].restricted
	end,

	isUserBanned = function( self, userID )
		return self.bannedUsers[ userID ]
	end,

	checkMutualGuilds = function( self, user, targetGuild )
		local targetGuild = targetGuild or GUILD.id
		for guild in user.mutualGuilds do
			if guild.id == targetGuild then
				log.i("Target guild confirmed to be mutual between bot and user.")
				return true
			end
		end

		log.w("Checking for mutual guilds FAILED -- target guild '"..tostring( targetGuild ).."' NOT found.")
		return false
	end
}
