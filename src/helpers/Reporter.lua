local Logger = require "src.client.Logger"
local discordia = luvitRequire "discordia"

--[[
	A simple class that provides a shortcut to sending messages (embed) to a target.

	4 modes exist: info, success, warning, failure. Any of these methods can be used by
	calling Reporter.static[ method ]( targetChannel, title, description, ... ) where '...'
	are any fields you want to send inside the embed object.
]]

Logger.d "Compiling Reporter"
local Reporter = class "Reporter" {
	static = {
		modes = {
			info = discordia.Color.fromRGB(114, 137, 218 ).value;
			success = discordia.Color.fromRGB( 14, 199, 100 ).value;
			warning = discordia.Color.fromRGB( 219, 145, 15 ).value;
			failure = discordia.Color.fromRGB( 219, 36, 15 ).value;
		}
	}
}

function Reporter.static.send( target, colour, title, description, ... )
	local f = { ... }
	if discordia.class.type( target ) == "User" then
		if Logger.worker and Logger.worker.messageManager.restrictionManager:isUserRestricted( target.id, true ) then
			return Logger.w( "Refusing to send message '"..title.."' to user " .. target.fullname, "User is banned or restricted" )
		end
	end

	coroutine.wrap( function()
		target:send {
			embed = {
				title = title or "No title",
				description = description or "No description",
				fields = f,

				color = colour,
			    timestamp = os.date('!%Y-%m-%dT%H:%M:%S'),
				footer = { text = "Bot written by Hazza Bazza Boo" }
			}
		}
	end )()
end

for method, colour in pairs( Reporter.static.modes ) do
	Reporter.static[ method ] = function( target, title, description, ... ) Reporter.send( target, colour, title, description, ... ) end
end

return abstract( true ):compile()
