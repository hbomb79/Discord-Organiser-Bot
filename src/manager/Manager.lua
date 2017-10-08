local Class, Logger = require "src.lib.class", require "src.util.Logger"

--[[
	WIP
]]

local Manager = class "Manager" {
	owner = false;
}

--[[
	@constructor
	@desc
]]
function Manager:__init__( owner )
	self.owner = Logger.assert( Class.typeOf( owner, "Worker", true ) or Class.typeOf( owner, "Manager", true ) and owner, "Cannot bind to manager. A worker/manager instance is required", "Bound instance" )

	self.worker = owner.worker
	if not self.worker then
		if Logger.assert( Class.typeOf( owner, "Worker" ), "No worker found", "Found worker for manager, binding" ) then self.worker = owner end
	end

	Logger.i("Instantiating Manager (type " .. tostring( self.__type ) .. ")", "Owner: " .. tostring( owner ))
end

return abstract( true ):compile()
