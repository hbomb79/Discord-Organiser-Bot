local Class = require "src.lib.class"

local function formLog( clock, mode, msg, fg, bg, attr, entire )
	if entire then
		return( "\27[%s;%s" .. (attr and ";" .. attr or "") .. "m%s | [%s] %s\27[0m" ):format( fg, bg, clock, mode, msg )
	else
		return( "\27[37m%s | \27[%s;%sm[%s]\27[37m %s\27[0m" ):format( clock, fg, bg, mode, msg )
	end
end

--[[
	A basic class that provides static function for outputting at various levels (info, warning, error, fatal) as well
	as a custom assertion function that automatically closes the active worker when assertion fails.
]]

local Logger = class "Logger" {
	static = {
		worker = false;
		debug = true;

		colours = {
			INFO = { 36, 49 },
			SUCCESS = { 32, 49, "3" },
			DEBUG = { 37, 49, "2;3", true },
			WARNING = { 33, 49 },
			ERROR = { 31, 49, "1" },
			FATAL = { 37, 41, "1", true },
		}
	}
}

--[[
	@static
	@desc WIP
]]
function Logger.static.out( mode, ... )
	print( formLog( os.date "%F %T", mode, table.concat( { ... }, " | " ), unpack( Logger.colours[ mode ] ) ) )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.i( ... )
	Logger.static.out( "INFO", ... )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.s( ... )
	Logger.static.out( "SUCCESS", ... )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.d( ... )
	if not Logger.debug then return end
	Logger.static.out( "DEBUG", ... )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.w( ... )
	Logger.static.out( "WARNING", ... )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.e( ... )
	Logger.static.out( "ERROR", ... )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.f( ... )
	Logger.static.out( "FATAL", ... )
end

--[[
	@static
	@desc WIP
]]
function Logger.static.assert( v, failureMessage, successMessage, worker )
	if not v then
		local worker, m = ( Class.typeOf( worker, "Worker", true ) and worker.alive and worker ) or ( Logger.static.worker and Logger.static.worker.alive and Logger.static.worker )
		if worker then m = Logger.f else m = error end

		m("Failed to assert '"..tostring( v ).."'" .. " | " .. ( failureMessage or "" ) .. " | " .. ( worker and "Attempting to gracefully close Discordapp gateway (via worker directly -- killing)" or "No worker directly accessible. Cannot gracfully close -- forcing termination" ) )
		
		if worker then worker:kill() end
	else
		Logger.d( "Successfully asserted '"..tostring( v ).."'", successMessage or "" )
		return v
	end
end

--[[
	@static
	@desc WIP
]]
function Logger.static.bind( worker )
	if Logger.static.worker and Logger.static.worker.alive then
		Logger.e("Failed to bind Logger to worker instance '"..tostring( worker ).."'. This is because a worker is already bound to this Logger (and is still active).", "Kill the active worker before re-attempting to bind again.")
	elseif not Class.typeOf( worker, "Worker", true ) then
		Logger.e("Failed to bind Logger to worker instance. The worker instance provided '"..tostring( worker ).."' is not a worker instance (or not typeOf).")
	else
		Logger.static.worker = worker

		return true
	end
end

return abstract( true ):compile()
