local Class = require "src.lib.class"

--[[
	A basic class that provides static function for outputting at various levels (info, warning, error, fatal) as well
	as a custom assertion function that automatically closes the active worker when assertion fails.
]]

local Logger = class "Logger" {
	static = {
		worker = false;
	}
}

--[[
	@static
	@desc WIP
]]
function Logger.static.out( mode, ... )
	print( ("[%s][%s] %s"):format( os.clock(), mode, table.concat( { ... }, " | " ) ) )
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
		
		if worker then print( tostring( worker ) ) worker:kill() end
	else
		Logger.i( "Successfully asserted '"..tostring( v ).."'", successMessage or "" )
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