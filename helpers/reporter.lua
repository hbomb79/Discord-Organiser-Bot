return {
	check = function() return HOST_CHANNEL end,
	send = function( self, user, colour, title, description, ... )
		if restrict.bannedUsers[ user.id ] then log.w("Refusing to send message to user " .. tostring( user ).." because they're banned.") return end

		local f = { ... }
		coroutine.wrap( function()
			user:sendMessage({
				embed = {
					title = title or "No title",
					description = description or "No description",
					fields = f,

					color = colour,
				    timestamp = os.date('!%Y-%m-%dT%H:%M:%S'),
					footer = { text = "Bot written by Hazza Bazza Boo" }
				}
			})
		end )()
	end,

	info = function( self, user, title, description, ... )
		self:send( user, discordia.Color(114, 137, 218 ).value, title, description, ... )
	end,

	success = function( self, user, title, description, ... )
		self:send( user, discordia.Color( 14, 199, 100 ).value, title, description, ... )
	end,

	warning = function( self, user, title, description, ... )
		self:send( user, discordia.Color( 219, 145, 15 ).value, title, description, ... )
	end,

	failure = function( self, user, title, description, ... )
		self:send( user, discordia.Color( 219, 36, 15 ).value, title, description, ... )
	end
}
