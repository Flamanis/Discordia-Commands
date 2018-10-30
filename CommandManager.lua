local d = require('discordia')
local class = d.class
local extensions = require('./Extensions')
local baseEnv = getfenv(0)
local Command = require('./Command')
local fs = require('fs')
local preconditions = require('./Preconditions')
local pp = require('pretty-print').prettyPrint
local typeReaders = require('./Typereaders')

local format = string.format

local CommandManager, get, set = class('CommandManager')
CommandManager._description = "The client's handler of chat commands."

--[[
Manager Properties:
All start with _ internally, access without outside.
client - Discordia client object
commands - array of command objects, keyed by name
aliases - array of command objects, keyed by aliases
isReady- bool of if ready to start reading chat
globalPrefix - string prefix to use on all chats the bot is in
guildPrefixes - array of string prefixes to use on specific guilds, if set to '' ignores guild
preconditions - Precondition functions.
globals - Globals to inject into commands.
types - Typereader functions

manager - the handler to use in messageCreate
realManager - the function that subscribes the 'handler' function to messageCreate, used for loading/unloading.

options - array of options for the manager


defaultOptions - default options for commands, keys = properties in command object


]]


local managerOptions = {
	failInChat = true,
	errorLog = false
}


local function messageManager(manager)
	return function(msg) manager:_manager(msg) end
end

local function defaultManager(self, msg)
	if not self._isReady then return end
	--Get bool of comparing if the author is the current user
	local isUserMe = msg.author.id == self._client.user.id
	--Check the flags of ignoring bots, others and self.
	if msg.author.bot or isUserMe then return end
	--Get the prefix for the current context
	local prefix = self:GetPrefix(msg)
	--If there is no prefix returned (happens if only guild set) or the command doesn't start without prefix
	if not prefix or not extensions.startswith(msg.content, prefix, true) then return end
	--Match the command and the rest of the string
	local cmd, args = msg.content:sub(prefix:len()+1):match('^(%S+)%s*(.*)')
	--Get the command object if possible.
	local command, argTbl = self:GetCommand(cmd, msg, args)
	--If there's no command, tell the user
	if not command then return self:Fail(msg, argTbl) end
	--If we got one, for now just run the command
	command:_Run(self._client, msg, argTbl)
end


local function tblFind(tbl,val)
	if not tbl then return nil end
	for k,v in pairs(tbl) do
		if v == val then
			return k
		end
	end
	return false
end

function CommandManager:__init(client, options)
	--Initialization
	self._client = client
	self._commands = {}
	self._aliases = {}
	self._isReady = true
	self._options = extensions.copy(managerOptions)
	for k,v in pairs(options) do
		self._options[k] = v
	end
	self._globalPrefix = ''
	self._guildPrefixes = {}
	self._globals = {}

	self._preconditions = preconditions
	self._types = typeReaders

	self._defaultOptions = {optionalParams = true}

	--Handler initialization. _handler is a modifiable handler while _readHandler should never be changed.
	self._manager = defaultManager
	self._realManager = messageManager(self)
end

function CommandManager:Error(str)
	if not self._options.errorLog then
		return self._client:error(str)
	else
		return self._client:warning(str)
	end
end

function CommandManager:Fail(msg, str)
	if self._options.failInChat then
		return msg:reply(str)
	else
		return self._client:warning(str)
	end
end


function CommandManager:Start()
	self._client:on('messageCreate', self._realManager)
end

function CommandManager:Stop()
	self._client:removeListener('messageCreate', self._realManager)
end

function CommandManager:Pause()
	self._isReady = false
end

function CommandManager:Play()
	self._isReady = true
end

function CommandManager:SetPrefix(prefix)
	if not prefix then self._globalPrefix = '' return  end
	if type(prefix) ~= 'string' then return false, format('Prefix must be a string. Got %q', type(prefix)) end
	self._globalPrefix = prefix
	return true
end

local function getGuild(guild)
	--If we're a table, then we need to check some stuffs
	local err = ''
	if class.isInstance(guild, class.classes.Guild) then
		guild = guild.id
	elseif type(guild) ~= 'string' or not tonumber(guild) then
		err = format('Guild provided must be a string id or guild object. Got %q. Type:%q', guild, type(guild))
	end
	if err ~= '' then return false, err end
	return true, guild
end

function CommandManager:SetGuildPrefix(guild, prefix)
	--Attempt to get the guild based on id/object
	local succ, guildToRegister = getGuild(guild)
	if not succ then return false, guildToRegister end
	--Then we check if the prefix is valid and error accordingly.
	if prefix == nil then self._guildPrefixes[guildToRegister] = '' return end
	if type(prefix) ~= 'string' then
		return false, format('Guild (%q) prefix must be a string. Got %q', guild, type(prefix))
	end
	--If we made it here, we have good prefix!
	self._guildPrefixes[guildToRegister] = prefix
	return true
end


function CommandManager:RemoveGuildPrefix(guild)
	local succ, guildToDelete = getGuild(guild)
	if not succ then return false, guildToDelete end
	self._guildPrefixes[guildToDelete] = nil
	return true
 end

 function CommandManager:GetPrefix(msg)
 	if not msg or not class.isInstance(msg, class.classes.Message) then return nil end
 	--Get the prefix for the current context.
 	local pre = msg.guild and self._guildPrefixes[msg.guild.id] or self._globalPrefix
	if pre == '' then return nil end
	return pre
end

--Function to set the handler, no checks here just straight setting.
--If the user want to change the handler, it's stuff is on them.
function CommandManager:SetManager( func)
	self._manager = func
 end

function CommandManager:_CheckPreconditions(msg, preconditions)
	if type(preconditions) ~= 'table' then return false, format('Precondition names must be in a table. Got: %q', preconditions) end
 	for k,v in pairs(preconditions) do
		local name, args
		if type(v) == 'string' then
			name = v
			args = nil
		elseif type(v) == 'table' then
			name = v[1] or v.name
			if type(name) ~= 'string' then
				return false, format("Precondition name must be a string. Got: %q. Type:%q",name, type(name))
			end
			args = v[2] or v.args
		end
		if self._preconditions[name] then
			local succ, err = self._preconditions[name](args, self._client, msg, self, self._globals)
			if not succ then return false, err end
		else
			return false, format("Precondition (%s) not found", name)
		end
	end
	return true
end

 --Function to update the aliases table when a command has them modified
 function CommandManager:_RemoveAliases(cmd, tbl)
	--Loop through the aliases of the command
	for _,v in pairs(tbl) do
		--If the command is case insensitive, set it to lowercase
		if cmd.ignoreCase then
			v = v:lower()
		end
		--Get the value at command table at the alias
		local key = tblFind(self._aliases[v], cmd)
			if key then
			self._aliases[v][key] = nil
		end
	end
end

--Function to update the aliases table when a command has them modified
 function CommandManager:_AddAliases(cmd, tbl)
 	--Loop through the aliases of the command
 	for _,v in pairs(tbl) do
 		--If the command is case insensitive, set it to lowercase
 		if cmd.ignoreCase then
 			v = v:lower()
 		end
 		--Get the value at command table at the alias
 		if not self._aliases[v] then
			self._aliases[v] = {}
		end
		table.insert(self._aliases[v], cmd)
 	end
 end

function CommandManager:AddGlobals(tbl)
	if type(tbl) ~= 'table' then return end
 	for k,v in pairs(tbl) do
 		self._globals[k] = v
 	end
end

 --Create command and add to handler
 function CommandManager:Create(env)
 	--Generate a new one using the constructor
	local cmd = env
	if not class.isInstance(env, command) then
 		cmd = Command(self, env)
	end
 	if cmd._notValid then return false, cmd._err end
 	--If we set it to be case insensitive then check that and set name as lower
	local name = cmd.ignoreCase and cmd.name:lower() or cmd.name
	if not self._commands[name] then
		self._commands[name] = {}
	end
	table.insert(self._commands[name], cmd)

 	--Return the newly generated command so that it can be used by the user if they wish
 	return cmd
end

--Remove command from handler
function CommandManager:Remove(command)
	if class.isInstance(command, Command) then
		self:_RemoveAliases(command, command.aliases)
		local name = command.ignoreCase and command.name:lower() or command.name
		local key = tblFind(self._commands[name], command)
		self._commands[name][key] = nil
	end
end

local function cmdTblFind(tbl,val)
	if not tbl then return nil end
	for k,v in pairs(tbl) do
		if v[1] == val then
			return k
		end
	end
	return false
end

function CommandManager:Type(ty, arg, msg)
	return self._types[ty](arg, msg)
end

local function score(manager, cmd, msg, args)
	local precon, err = manager:_CheckPreconditions(msg, cmd.preconditions)
	if not precon then return false, err  end
	local sc = 0
	local argsTbl = cmd:_SplitArgs(args)
	local argsOut = {}
	for k,v in ipairs(argsTbl) do
		if cmd._params[k] then
			local val, err = manager:Type(cmd._params[k].type, v, msg)
			if val == nil then return false, err end
			table.insert(argsOut, val)
			sc = sc + 10
		else
			table.insert(argsOut, v)
		end
	end
	return {cmd, sc, argsOut}
end


function CommandManager:GetCommand(name, msg, args)
 	if not name then return false end
 	local possCommands = {}
	if self._commands[name] then
		for k,v in ipairs(self._commands[name]) do
			local val = score(self, v, msg, args)
			if val then
				val[2] = val[2] + 3
				table.insert(possCommands, val)
			end
		end
	end
	if self._aliases[name] then
		for k,v in ipairs(self._aliases[name]) do
			local val = score(self, v, msg, args)
			if val then
				val[2] = val[2] + 2
				if not cmdTblFind(possCommands, val[1]) then
					table.insert(possCommands, val)
				end
			end
		end
	end
	name = name:lower()
	if self._commands[name] then
		for k,v in ipairs(self._commands[name]) do
			local val = score(self, v, msg, args)
			if val then
				val[2] = val[2] + 2
				if not cmdTblFind(possCommands, val[1]) then
					table.insert(possCommands, val)
				end
			end
		end
	end
	if self._aliases[name] then
		for k,v in ipairs(self._aliases[name]) do
			local val = score(self, v, msg, args)
			if val then
				val[2] = val[2] + 2
				if not cmdTblFind(possCommands, val[1]) then
					table.insert(possCommands, val)
				end
			end
		end
	end
	if #possCommands == 0 then return false, 'Command not found' end
	local max = {'err', -1,''}
	for k,v in ipairs(possCommands) do
		if v[2] > max[2] then
			max = v
		end
	end
	return max[1], max[3]
end


function CommandManager:LoadCommands(filepath)
	local str, err = fs.readFileSync(filepath)
	if not str then return self:Error(err) end
	local func,err = loadstring(str, '='..filepath:match("/?([^/]*)$"))
	if not func then return self:Error(err) end
	local env = extensions.copy(baseEnv)

	for k,v in pairs(self._globals) do
		env[k] = v
	end

	for k,v in pairs(Command._optionTypes) do
		env[k] = self._defaultOptions[k]
	end

	local comTbl = {}
	local comCount = 1

	local function add()
		local newEnv = getfenv(func)
		local com, err = self:Create(newEnv)
		if not com then return self:Error(format("Error in generating command #%d from file: %s\nError: %s", comCount, filepath, err)) end
		for k,v in pairs(Command._optionTypes) do
			newEnv[k] = self._defaultOptions[k]
		end
		table.insert(comTbl, com)
		comCount = comCount + 1
	end
	env.add = add
	env.client = self._client
	env.manager = self
	setfenv(func,env)
	func()
	return comTbl
end



return CommandManager
