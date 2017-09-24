return {
	check = function() return HOST_CHANNEL end,
	send = function( self, user, title, description, ... )
		if restrict.bannedUsers[ user.id ] then log.w("Refusing to send message to user " .. tostring( user ).." because they're banned.") return end

		local f = { ... }
		coroutine.wrap( function()
			user:sendMessage({
				embed = {
					title = title or "No title",
					description = description or "No description",
					fields = f
				}
			})
		end )()
	end
}