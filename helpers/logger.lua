local function out( p, m )
	print( ("["..os.clock().."][%s] %s"):format( p, m ) )
end

return {
	i = function( m )
		out( "INFO", m )
	end,

	w = function( m )
		out( "WARN", m )
	end,

	c = function( m )
		out( "CRITICAL", m )
	end,

	f = function( m )
		out( "FATAL", m )
	end,

	assert = function( self, v, m )
		if not v then
			self.f( m )
			self.w "Client is attempting to gracefully stop after fatal exception"

			if CLIENT then CLIENT:stop() end
			return false
		end

		return true
	end
}