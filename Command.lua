local debug = debug
local class = require('discordia').class
local Command, get, set = class('Command')

Command._defaultOptions = {
	ignoreCase = false,
	description = "",
	longDescription = "",
	usage = "",
	defaultOptional = false,
	allowExtra = false,
	preconditions = {}
}

Command._commandOptions = {
	ignoreCase = false, --Sets if the command is case insensitive
	description = "", --Sets the description of the command (For help command functionality)
	longDescription = "", --Sets the long description of the command (For help command functionality)
	usage = "", --Sets the usage of the command (For help command functionality)
	defaultOptional = false, --Sets parameters of functions to be by default optional if set
	allowExtra = false, --Allows for run off on command parameters
	preconditions = {}, --Preconditions to run before the command to make sure it can be run
	params = {}, --Parameter options
	parameters = {}, --See above, mutally exclusive
	aliases = {}, --Aliases for the command name
	name = "", --Name of command REQUIRED
	func = "" --Function to run for command REQUIRED
}


local function getArg(tbl,numOrName)
	if type(numOrName) == 'string' then
	 return tbl[numOrName:lower()]
	end
	if type(numOrName) == 'number' then
	 return numOrName
	end
	return nil
end

local function splitArgs(self, str)
	--Our table to return the split args
  	local outTbl = {}
	--Counter of what arg we're on
	local i = 1
	local lastArg = 1
	local inQuotes = false
	local ignoreLast = false
	local justIn = false
	for c in str:gmatch('.') do
		local currArg = #outTbl+1
		if currArg == self._numArgs and self._paramOptions[currArg].remainder then
			table.insert(outTbl,str:sub(lastArg))
			ignoreLast = true
			break
		end
		if c == ' ' and not inQuotes then
			if not justIn then
				table.insert(outTbl,str:sub(lastArg,i-1))
			end
			justIn = false
			lastArg = i + 1
		elseif c == "'" then
			if not inQuotes and lastArg == i then
				inQuotes = "'"
			elseif inQuotes == "'" then
				table.insert(outTbl,str:sub(lastArg+1,i-1))
				inQuotes = false
				lastArg = i + 1
				justIn = true
			end
		elseif c == '"' then
			if not inQuotes and lastArg == i then
				inQuotes = '"'
			elseif inQuotes == '"' then
				table.insert(outTbl,str:sub(lastArg+1,i-1))
				inQuotes = false
				lastArg = i + 1
				justIn = true
			end
		end
		i = i + 1
	end
	if not ignoreLast and i ~= 1 then
		table.insert(outTbl,str:sub(lastArg))
	end
	if(#outTbl < self._reqArgs) then
		return "Not enough arguments provided to command"
	end
	if(#outTbl > self._numArgs and not self._allowExtra) then
		return "Too many arguments provided to command"
	end
  return outTbl
end

function Command:__init(cmdHandler, env)
	--Check our required arguments
	if type(env.name) ~= 'string' then self._err = 'Command name must be a string' end
	if type(env.func) ~= 'function' then self._err = 'Command function must be a function' end
	
	--Register needed values
	self._handler = cmdHandler
	self._name = env.name
	self._func = env.func

	local funcTbl = debug.getinfo(env.func)

	self._numArgs = funcTbl.nparams
	self._allowExtra = funcTbl.isvararg or env.allowExtra
	self._defaultOptional = env.defaultOptional

	--Register defaults
	self._aliases = {}
	self._paramOptions = {}
	self._reqArgs = self._defaultOptional and 0 or self._numArgs
	for i=1, self._numArgs do
		if not self._paramOptions[i] then
			self._paramOptions[i] = {optional = self._defaultOptional}
		end
	end
	self._paramNames = {}
	for i=1,self._numArgs do
		self._paramNames[debug.getlocal(self._func,i):lower()] = i
	end


	--Run through defaults with builders
	self._ignoreCase = env.ignoreCase
	self._description = ""
	self:setDescription(env.description)
	self:setLongDescription(env.longDescription)
	self:setUsage(env.usage)
	if env.aliases then
		self:addAliases(type(env.aliases) == 'table' and table.unpack(env.aliases) or env.aliases)
	end

	if env.parameters or env.params then
	  local paramTbl = env.params or env.parameters
	  self:setParametersOptions(paramTbl)
	end

	self._preconditions = {}
	if env.preconditions then
		self:addPreconditions(env.preconditions)
	end


	if self._err then self._notValid = true return end

end


local function tblFind(tbl,val)
	for k,v in pairs(tbl) do 
		if v == val then 
			return true
		end 
	end 
	return false
end


--Builder functions:
--All return self so that you can chain them.

--addAliases
function Command:addAliases(...)
	--Loop through all values in our parameters and add to the aliases table if they're not already
	local inserted = false
	for _,v in ipairs({...}) do
		if not tblFind(self._aliases, v) then
			table.insert(self._aliases, v)
			inserted = true
		end
	end

	--Update the aliases on the handler
	if inserted then
		self._handler:_updateAliases(self)
	end
	return self
end

function set.description(self, arg)
	if type(arg) == type(self._defaultOptions.description) then
		self._description = arg
	end
end

function Command:setDescription(description)
	self.description = description
	return self
end

function set.longDescription(self,longDescription)
	if type(longDescription) == type(self._defaultOptions.longDescription) then
		self._longDescription = longDescription
	end
end


function Command:setLongDescription(longDescription)
	self.longDescription = longDescription
	return self
end

function set.usage(self,use)
	if type(use) == type(self._defaultOptions.usage) then
		self._usage = use
	end
end


function Command:setUsage(use)
	self.usage = use
	return self
end

function Command:setParametersOptions(paramTbl)
	--Loop through our options table
	for k,v in pairs(paramTbl) do
		--Use our getArg func to find the argument "index" in the names
		local args = getArg(self._paramNames, k)
		if args and args <= self._numArgs then
			if type(v) == 'table' then
				if v.optional ~= nil and type(v.optional) == 'boolean' then
					self._paramOptions[args].optional = v.optional
				elseif v[1] ~= nil and type(v[1]) == 'boolean' then
					self._paramOptions[args].optional = v[1]
				end
				if v.remainder and type(v.remainder) == 'boolean' then
					if args ~= self._numArgs then
						self._err = ('Remainder parameter must be the final parameter')
						return
					elseif self._allowExtra then
						self._err = ('Remainder cannot be applied to a command that allows overflow')
						return
					end
					self._paramOptions[args].remainder = v.remainder
				end

			elseif type(v) == 'boolean' then
				self._paramOptions[args].optional = v
			end
		end
	end
	local foundReq = 0
	local foundOptional = false
	for i = 1, self._numArgs do
		if(not self._paramOptions[i].optional and foundOptional) then
			self._err = ("Cannot have required parameter after optional parameter")
			return
		elseif(self._paramOptions[i].optional) then
			foundOptional = true
		else
			foundReq = foundReq + 1
		end
	end
	self._reqArgs = foundReq
	return self
end

function Command:setParameterOptions(param, options)
	return setParametersOptions(self, {[param] = options})
end



function Command:addPreconditions(preconditions)
	for k,v in pairs(preconditions) do
		if type(v) == 'string' then
			table.insert(self._preconditions,{v})
		elseif type(v) == 'table' then
			local name, args
			name = v[1] or v.name
			if not name then 
				self._err = string.format("Precondition must have a name")
				return
			end
			table.insert(self._preconditions,{name,v[2] or v.args})
		else
			self._err = string.format("Precondition name is of invalid type")
		end
	end
	return self
end
















function Command:_run(client, message, args)
	local context = {
		message = message,
		guild = message.guild,
		channel = message.channel,
		author = message.author,
		member = message.member
	}
	local fenv = getfenv(self._func)
	fenv.context = context
	setfenv(self._func, fenv)
	local params = splitArgs(self, args)
	if type(params) == 'table' then
		local succ, ret = pcall(self._func, table.unpack(params))
		if not succ then message:reply(ret) end
	elseif self._handler._options.echoErrors then
		message:reply(params)
	end
end

function get.caseInsensitive(self)
	return self._ignoreCase
end

function get.name(self)
	return self._name
end

function get.aliases(self)
	return self._aliases
end

function get.description(self)
	return self._description
end

function get.longDescription(self)
	return self._longDescription
end

function get.usage(self)
	return self._usage
end

function get.preconditions(self)
	return self._preconditions
end

return Command
