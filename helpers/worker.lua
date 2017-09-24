-- Define constants here to allow quick access in future.
HOST_ROLE, HOST_CHANNEL, BOT_SNOWFLAKE = "", "361062102732898314", "361038817840332800"
commands, reporter, restrict, events, jpersist, log = require "helpers.commands", require "helpers.reporter", require "helpers.restrict", require "helpers.events", require "helpers.jpersist", require "helpers.logger"

return {
	isWorkerRunning = false,
	queue = {},
	userRequests = {},

	init = function( self, client, j, d )
		log.i "Fetching GUILD information"
		CLIENT = client

		-- Get guild
		GUILD = CLIENT:getGuild "158038708057145344"
		if not log:assert( GUILD, "Failed to start worker -- Guild unavailable" ) then return end

		-- Get channel
		CHANNEL = GUILD:getChannel( HOST_CHANNEL )
		if not log:assert( CHANNEL, "Failed to start worker -- channel (HOST) unavailable" ) then return end

		log:assert( j, "Failed to import JSON library" )
		json = j

		log.i( "Imported JSON library to global space " .. tostring( json ) )

		log:assert( d, "Failed to import Discordia library" )
		discordia = d

		log.i( "Imported Discordia library to global space " .. tostring( discordia ) )

		-- Check that all workers have what they need
		for k, v in pairs { commands = commands, reporter = reporter, restrict = restrict, events = events, jpersist = jpersist } do
			if not log:assert( v:check(), "Required '"..k.."' library (helpers/"..k..".lua) unable to start. Bot cannot start without all requirements fully functional -- aborting" ) then return end
			log.i("Required '"..k.."' has confirmed alive status - OK")
		end

		events:loadEvents()
		restrict.bannedUsers = jpersist.loadTable( "./banned.cfg" ) or {}
		events:refreshRemote()

		log.i "Done - All OK"
		return true
	end,

	addToQueue = function( self, content )
		local author = content.author
		if author.bot then return end

		log.i( "Checking message '"..tostring( content ).."' from " .. tostring( author ), true )
		if not content.channel.isPrivate or restrict:isUserBanned( author.id ) then
			-- Message outside relevant context, or submitted by a bot. Ignore completely.
			log.i "Message is outside of relevant scope (not inside a DM). Ignoring message."
			return
		elseif restrict:isUserRestricted( author.id ) then
			-- This is a message from a timed out user (or bot). Remove and ignore
			log.i "Message received was created by a restricted user. Adding one (1) violation to restriction record"
			restrict:violate( author )
			return
		end

		local uR = self.userRequests[ author.id ]
		uR = type( uR ) == "number" and uR + 1 or 1

		self.userRequests[ author.id ] = uR
		if uR >= 3 then
			log.w("Author " .. tostring( author ) .. " has " .. uR .. " requests in the queue. Restricting user")
			restrict:restrictUser( author.id )

			reporter:warning( author, "User Restricted", "Your account has been restricted due to heavy inbound traffic. This restriction will automatically be lifted in a few seconds.\n\nFurther abuse will lead to permanent blacklisting.")
			return
		end

		log.i("Adding message to queue (position #"..#self.queue..").")
		table.insert( self.queue, content )

		if not self.isWorkerRunning then self:startWorker() end
	end,

	startWorker = function( self )
		log.i( "WORKER START. Items currently in queue: " .. tostring( #self.queue ) )
		self.isWorkerRunning = true
		while #self.queue > 0 do
			log.i( "Handling queue item '" .. tostring( self.queue[ 1 ] ) .. "'" )
			local content = self.queue[ 1 ]
			local author = content.author

			if not ( restrict:isUserRestricted( author.id ) or restrict:isUserBanned( author.id ) ) then
				author.privateChannel:broadcastTyping()
				if not restrict:checkMutualGuilds( author ) then
					-- This is a message from a user OUTSIDE of the guild. Notify and ignore.
					log.i "Message received was created by a foreign user -- notifying user"
					reporter:warning( author, "Unknown User", "Your user is not recognised. Ensure you are a member of the BGnS guild and try again.\n\nIf you believe this is in error contact the guild owner" )
				else
					local validCommand = commands:checkCommand( content )
					if not validCommand then
						-- Invalid syntax
						log.i "Message received was malformed -- notifying user."
						reporter:warning( author, "Command Malformed", "The command sent to this bot was not recognised. Ensure format is '!command' and check for typing mistakes\n\nTry **!help**" )
					else
						log.i "Message received is a valid command, executing command"
						commands:runCommand( content, validCommand )
					end
				end
			else
				log.w("Skipping queue #1 item handling because author ("..tostring( author )..") is restricted or banned")
			end

			table.remove( self.queue, 1 )

			self.userRequests[ author.id ] = self.userRequests[ author.id ] - 1
			if self.userRequests[ author.id ] == 0 then
				log.i( "Unrestricted user " .. tostring( author ) )
				restrict:unrestrictUser( author.id )
			end

			log.i( "Queue item handled. Removing from queue and continuing. User " .. tostring( author ) .. " now has " .. self.userRequests[ author.id ] .. " items in queue. Total items left in queue: " .. tostring( #self.queue ) )
		end

		log.i( "Worker stopped. No more items in queue (0)" )
		self.isWorkerRunning = false
	end
}
