--[[
	Bootstrap the Discord bot by loading the OOP class system, Discordia, and
	creating (and starting) a new instance of Worker.

	This program uses a modified version of the Titanium class system (Copyright (c) Harry Felton).
	See src/lib/class.lua for more information regarding licensing.

	Copyright (c) Harry Felton 2017
]]

print "Starting bootstrap process"

-- Luvit's 'require' breaks down after I require a file (ie: when a require a file, that file uses Vanilla Lua's require instead
-- of luvit's -- this means that files end up being executed more than once!). This block of code essentially means that this file
-- uses Lua's vanilla `require` instead of luvits to avoid issues with files being loaded more than once.
_G.luvitRequire = require;
local require = _G.require

-- Require and store Discordia (currently here for debug purposes)
local discordia = luvitRequire "discordia"
assert( discordia, "Failed to bootstrap: Discordia failed to load" )

-- Store the class API in the 'Class' global
Class = require "src.lib.class"
assert( type( class ) == "function" and type( Class ) == "table" and abstract and mixin and extends, "Failed to bootstrap: Class library references could not be found" )

local Logger = require "src.util.Logger"

-- Instantiate a Worker
local ok, err = pcall( require "src.Worker" )
if not ok then
	Logger.f( "Worker instance failed", tostring( err ) )
	return false
end

Logger.s "Finished bootstrap -- Control given to worker"
