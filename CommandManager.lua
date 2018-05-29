local d = require('discordia')
local class = d.class
d.extensions()
local baseEnv = getfenv(0)
local Command = require('./Command')
local fs = require('fs')
local preconditions = require('./Preconditions')
local pp = require('pretty-print').prettyPrint

local format = string.format

local CommandManager, get, set = class('CommandManager')
CommandManager._description = "The client's handler of chat commands."


local function tblFind(tbl,val)
	for k,v in pairs(tbl) do 
		if v == val then 
			return true
		end 
	end 
	return false
end


local function messageHandler(manager)
	return function(msg) if not manager._isReady then return end manager:_handler(msg) end
end

local function defaultHandler(self, msg)
	--Get bool of comparing if the author is the current user
	local isUserMe = msg.author.id == self._client.user.id
	--Check the flags of ignoring bots, others and self.
	if msg.author.bot and self._options.ignoreBots or self._options.ignoreOthers and not isUserMe or self._options.ignoreSelf and isUserMe then return end
	--Get the prefix for the current context
	local prefix = self:_getPrefix(msg)
	--If there is no prefix returned (happens if only guild set) or the command doesn't start without prefix
	if not prefix or not msg.content:startswith(prefix) then return end
	--Match the command and the rest of the string
	local cmd, args = msg.content:sub(prefix:len()+1):match('^(%S+)%s*(.*)')
	--Get the command object if possible.
	local command = self:getCommand(cmd)
	--If there's no command, tell the user
	if not command and self._options.echoErrors then return msg:reply('Error: Command not found.') end
	--If we got one, for now just run the command
	if command ~= nil then
		local succ, err = self:_checkPreconditions(msg, command.preconditions)
		if succ then
			command:_run(self._client, msg, args)
		elseif self._options.echoErrors then 
			return msg:reply("Error: ".. err)
		end
	end
end

--Default options for the manager. Does stuffs.
local defaultOptions = {
	ignoreBots = true,
	ignoreSelf = true,
	ignoreOthers = false,
	echoErrors = true,
	defaultHelpCommand = true, --Todo: still write this
	description = 'A Discordia Discord bot'
}
CommandManager._defaultOptions = defaultOptions

--Function for setting the options of the handler
function CommandManager:setOptions(options)
	--If they sent us something and it's a table
	if options and type(options) == 'table' then
		--Loop through the options on the default options table. If it exists in the passed table then set it in our options
		for k,v in pairs(defaultOptions) do
			if options[k] ~= nil then
				self._options[k] = options[k]
			end
		end
		--Make sure that each type in our options table is the correct type.
		--This could be one loop, but it's less readable.
		for k,v in pairs(options) do
			local a = type(v)
			local b = type(defaultOptions[k])
			if a ~= b then
				return self:error(format('Invalid manager option type for %q: Expected %q, got %q',k, b, a))
			end
		end
	end
end

--Initialization of class
function CommandManager:__init(client)
	--Initialization
	self._client = client
	self._commands = {}
	self._aliases = {}
	self._isReady = false
	self._options = table.copy(defaultOptions)
	self._guildPrefixes = {}
	self._preconditions = preconditions
	self._globals = {}

	self._defaultCommandOptions = table.deepcopy(Command._defaultOptions)

	--Handler initialization. _handler is a modifiable handler while _readHandler should never be changed.
	self._handler = defaultHandler
	self._realHandler = messageHandler(self)
	client:on('messageCreate', self._realHandler)
end

--Function for errors
function CommandManager:error(str)
	--Pass errors to the client.
	return self._client:error(str)
end

--Function for warnings
function CommandManager:warning(str)
	--Pass warnings to the client.
	return self._client:warning(str)
end

function CommandManager:_checkPreconditions(msg, preconditions)
	for k,v in pairs(preconditions) do
		local name, args
		if type(v) == 'string' then
			name = v
			args = nil
		elseif type(v) == 'table' then
			name = v[1] or v.name
			if type(name) ~= 'string' then
				return false, string.format("Precondition name must be a string")
			end
			args = v[2] or v.args
		end
		if self._preconditions[name] then
			local succ, err = self._preconditions[name](args, self._client, msg, self, self._globals)
			if not succ then return false, err end
		else
			return false, string.format("Precondition [%s] not found", name)
		end
	end
	return true
end

--Function to get the prefix in the context of the message.
function CommandManager:_getPrefix(msg)
	--Get the prefix for the current context.
	return msg.guild and self._guildPrefixes[msg.guild.id] or self._prefix
end

--Function to get a command by name or alias
function CommandManager:getCommand(name)
	if not name  then return false end
	--Check for exact match in commands and aliases
	local command = self._commands[name] or self._aliases[name]
	--Check for case insensitive match
	name = name:lower()
	--These two checks are a bit long, so I split it into multiple lines
	--Check just the commands table
	command = command or (self._commands[name] and self._commands[name]._caseInsensitive and self._commands[name])
	--Check the aliases table
	command = command or (self._aliases[name] and self._aliases[name]._caseInsensitive and self._aliases[name])
	return command
end

--Function to update the aliases table when a command has them modified
function CommandManager:_updateAliases(cmd)
	--Loop through the aliases of the command
	for _,v in ipairs(cmd.aliases) do
		--If the command is case insensitive, set it to lowercase
		if cmd._caseInsensitive then
			v = v:lower()
		end

		--Get the value at command table at the alias
		local possibleAlias = self._aliases[tblFind(self._aliases,v)]

		--If it's nil, set it to be cmd, if it's not then we need to send a warning message
		if possibleAlias == nil then
			self._aliases[v] = cmd
		elseif possibleAlias ~= cmd then
			self:warning(format("Confliction of alias (%s) from commands: %s and %s", v, cmd.name, possibleAlias.name))
		end
	end
end

--Create command and add to handler
function CommandManager:create(name, func, options)

	local opt = table.deepcopy(self._defaultCommandOptions)
	if options then
		for k,v in pairs(options) do
			opt[k] = v
		end
	end
	for k,v in pairs(Command._defaultOptions) do
		local a = type(self._defaultCommandOptions[k])
		local b = type(opt[k])
		if a ~= b then
			return self:error(format('Invalid option type given for command creation. Command: %q, Option %q. Expected %q, got %q', name, k, a, b))
		end
	end
	opt.name = name
	opt.func = func
	--Generate a new one using the constructor
	local cmd = Command(self, opt)
	if cmd._notValid then return false, cmd._err end
	--If we set it to be case insensitive then check that and set name as lower
	if cmd.caseInsensitive then
		self._commands[cmd.name:lower()] = cmd
	else
		self._commands[cmd.name] = cmd
	end
	--Return the newly generated command so that it can be used by the user if they wish
	return cmd
end

--Remove command from handler
function CommandManager:remove(command)
	--Can remove by name/alias, so if we get that attempt to get the command
	if type(command) == 'string' then
		command = self:getCommand(command)
	end
	--If we're a table and our class is "Command" then remove the name and aliases from the table
	if type(command) == 'table' and command.isInstanceOf and command:isInstanceOf("Command") then
		for a, v in pairs(command.aliases) do
			if command.caseInsensitive then
				v = v:lower()
			end
			self._aliases[v] = nil
		end
		if command.caseInsensitive then
			self._commands[command.name:lower()] = nil
		else
			self._commands[command.name] = nil
		end
	end
end

--Function to set global prefix
function CommandManager:setPrefix(prefix)
	if type(prefix) ~= 'string' then return self:error("Prefix must be a string") end
	--If function hasn't been called before, make us handle messages now
	self:setReady()
	self._prefix = prefix
end

--Function to set the handler, no checks here just straight setting.
--If the user want to change the handler, it's stuff is on them.
function CommandManager:setHandler( func)
	self._handler = func
 end

local function getGuild(guild)
	--If we're a table, then we need to check some stuffs
	if type(guild) == 'table' then
		--If we're a class by having isInstanceOf, if not then it's a table that ain't good
		if guild.isInstanceOf then
			--If we're a guild, then get the guild id, otherwise error because you can only do guild.
			if guild:isInstanceOf('Guild') then
				guild = guild.id
			else
				return false, format('Invalid guild object type given: %q.', guild._name or guild)
			end
		else
			return false, format('Invalid guild type given: table.')
		end
	--If we're not a string, then we say what type we are (number or func or nil) and how that is bad
	elseif type(guild) ~= 'string' then
		return false, format('Invalid guild type given: %q.', type(guild))
	elseif not tonumber(guild) then
		return false, format('Guild id must be a number. Got %q', guild)
	end
	return true, guild
end

--Function to set a prefix for a guild. Takes an id or a guild object.
function CommandManager:setGuildPrefix(guild, prefix)
	--Attempt to get the guild based on id/object
	local succ, guildToRegister = getGuild(guild)
	if not succ then return self:error(guildToRegister) end
	--Then we check if the prefix is valid and error accordingly.
	if type(prefix) ~= 'string' then
		return self:error(format('Invalid prefix type given for guild (%q): %q.', guild, type(prefix) ))
	end
	--If we made it here, we have good prefix!
	self._guildPrefixes[guildToRegister] = prefix
	self:setReady()
end


--Function to remove a registered prefix for a guild. Takes an id or a guild object.
function CommandManager:removeGuildPrefix(guild)
	local succ, guildToRegister = getGuild(guild)
	if not succ then return self:warning(guildToRegister) end
	self._guildPrefixes[guildToRegister] = nil
 end

--Function to set the ready status of the handler. used internally for prefixes and such.
--Allowed for use externally so that those that want to remake the handler can
function CommandManager:setReady(bool)
	bool = bool ~= false
	if self._isReady ~= bool then self._isReady = bool end
end

--Function to set the default options to pass to a command on initialization
function CommandManager:setDefaultCommandOptions(options)
	--Make sure we're a table
	if type(options) == 'table' then
		--This is the generic check for options.
		for k,v in pairs(Command._defaultOptions) do
			if options[k] ~= nil then
				self._defaultCommandOptions[k] = v
			end
		end
		for k,v in pairs(options) do
			local optionType = type(v)
			local defaultType = type(Command._defaultOptions[k])
			if optionType ~= defaultType then
				return self:error(format('Invalid default command option type for %q: Expected %q, got %q', k, defaultType, optionType))
			end
		end
	end
end

local function min(...)
	local args = {...}
	local tbl = {}
	for k,v in pairs(args) do
		table.insert(tbl,v)
	end
	if #tbl == 0 then return -1 end
	return math.min(table.unpack(tbl))
end

function CommandManager:loadCommands(filepath)
	local str, err = fs.readFileSync(filepath)
	if not str then return self:error(err) end
	local func,err = loadstring(str)
	if not func then return self:error(err) end
	local env = table.copy(baseEnv)
	
	for k,v in pairs(self._globals) do
		env[k] = v
	end
	local comTbl = {}
	local comCount = 1

	local function add()
		local newEnv = getfenv(func)
		local com, err = self:create(newEnv.name,newEnv.func,newEnv)
		if not com then return self:error(string.format("Error in generating command #%d from file: %s\nError: %s", comCount, filepath, err)) end
		for k,v in pairs(Command._commandOptions) do
			newEnv[k] = nil
		end
		table.insert(comTbl, com)
		comCount = comCount + 1
	end
	env.add = add
	env.client = self._client
	env.handler = self
	setfenv(func,env)
	func()
	return comTbl
end

function CommandManager:addGlobals(tbl)
	for k,v in pairs(tbl) do
		self._globals[k] = v
	end
end


function get.commands(self)
	return self._commands
end
function get.prefix(self)
	return self._prefix
end

function get.guildPrefixes(self)
	return self._guildPrefixes
end
function get.options(self)
	return self._options
end
function get.defaultOptions(self)
	return self._defaultOptions
end
function get.defaultCommandOptions(self)
	return self._defaultCommandOptions
end



return CommandManager
