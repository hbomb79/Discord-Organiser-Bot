--[[
	Bootstrap the discord bot by:
		- starting the client
		- connecting to the guild
		- retrieving channel information
		- loading event information
		- running the client with token
]]

-- Require Discordia and fetch the client instance.

local discordia, worker, log, json = require "discordia", require "helpers.worker", require "helpers.logger", require "json"

CLIENT = discordia.Client()

-- Bind the event listeners so we can respond to the creation, update, deletion of messages
CLIENT:on( "messageCreate", function( message )
	worker:addToQueue( message )
end )

CLIENT:once( "ready", function()
	log.i "Client started, initialising worker"
	worker:init( CLIENT, json )
end )

-- Run the client
log.i "Starting client"
local h = io.open("./.token")
if not log:assert( h, "Unable to open .token file -- Not found or unable to read (in use/invalid permission/etc)" ) then return end
local token = h:read "*a"
h:close()

CLIENT:run( token )