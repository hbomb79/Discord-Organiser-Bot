return {
	check = function() return type( json ) == "table" and type( json.encode ) == "function" and type( json.decode ) == "function" end,
	saveTable = function( table, path )
		log.i("Saving table " .. tostring( table ) .. " to path '"..tostring( path ).."'")
		local h = io.open( path, "w+" )
		h:write( json.encode( table ) )
		h:close()

		log.i("Save complete")
	end,

	loadTable = function( path )
		log.i("Loading table from " .. tostring( path ))
		local h = io.open( path )
		if not log:assert( h, "Failed to open " .. tostring( path )) then return end
		local c = h:read "*a"
		h:close()

		local j = json.decode( c )
		if not log:assert( j, "Failed to decode content of " .. tostring( path )) then return end

		log.i("Load complete")
		return j
	end
}
