local debug = debug
local class = require('discordia').class
local extensions = require('./extensions')
local Command, get, set = class('Command')
Command._description = "A command object for Flamanis's Command Manager"

--[[
Command properties
REQUIRED
Name - String - Signifies the name of the command, is also the command word
Func - Function - The function to run when the command is validated

OPTIONAL
aliases - String Array - Array of aliases for the command, function same as name
ignoreCase - Bool -  Can the command be run in any caSe.
description - String - Short description of the command, usage in help commands
longDescription - String - Longer description of the command
usage - String - Usage string for help
preconditions - String/Table Array - Array of preconditions to add to this command.

OPTIONAL PARAMETER OPTIONS
optionalParameters - Bool - Sets the default state of each parameter to be optional
optionalParams - See above ^
runoff - Bool - Allows for parameters for the command to exceed the listed parameters, always true if you use vararg in the parameter list (...)
params - Table - A table of parameter options, can reference specific parameters by name or index.
parameters - See params, params takes precedent


PRECONDITION SPECIFIC OPTIONS
Precondition options are usually a string
However you can pass a table to allow for passing in arguments, such as {'RequireGuild', '81384788765712384' }
Indexes of properties are allowed (1 for name, 2 for args)

name - The name of the precondition to use
args - A value to pass to the precondition on run



PARAMETER SPECIFIC OPTIONS
Parameter options are usually a table of values:
Indexes of properties are allowed (1 for optional, 2 for type, 3 for remainder)

optional - Bool - Is the command optional? Defaults to the optionalParameters option if not set.
type - String - The typecaster to use to try to convert this parameter into a different type
remainder - Bool - Sets this parameter to capture the remainder of the text. CAN ONLY BE SET ON THE LAST PARAMETER



HOWEVER, you can instead just have a bool to set if the parameter is optional

]]


--[[
Internal options - All are prepended with _
manager - The command manager
name - The command name
func - The function to run



argCount - The number of arguments in the function
runoff - Do we allow for runoff in the parameters
optionalParams - The default value to set parameters to be defaulted by

ignoreCase - Bool to ignore CaSe
preconditions - String array of precondition names
aliases - The aliases array

description
longDescription
usage

params - parameter options
reqArgs - Number of required arguments, makes for a quick check if they've entered the right amount
paramNames - The names of the parameters as displayed in the code, lower

]]


--[[
Command Methods, pretty much all of these are run when you make your command
They return the command object itself so you can chain them. If you wanna.
setParametersOptions - Sets parameter options, type, optional, remainder.
SetParameterOptions ^ but for one

]]

Command._optionTypes = {
	name = 'string',
	func = 'function',
	aliases = 'table',
	ignoreCase = 'boolean',
	description = 'string',
	longDescription = 'string',
	usage = 'string',
	preconditions = 'table',
	optionalParams = 'boolean',
	runoff = 'boolean',
	params = 'table',
}
Command._paramTypes = {
	optional = 'bool',
	type = 'string',
	remainder = 'boolean'
}

function Command:__init(manager, env)

	--Check our required arguments
	if type(env.name) ~= 'string' then self._err = 'Command name must be a string' end
	if type(env.func) ~= 'function' then self._err = 'Command function must be a function' end

	if not self._err then
		--Register REQUIRED values
		self._manager = manager
		self._name = env.name
		self._func = env.func


		--Get information about function
		local funcTbl = debug.getinfo(env.func)

		self._argCount = funcTbl.nparams
		self._runoff = funcTbl.isvararg or env.runoff or false
		self._optionalParams = env.optionalParameters or env.optionalParams or false



		--Register defaults
		self._ignoreCase = env.ignoreCase or false
		self._preconditions = {}
		self._aliases = {}
		self._desc = ""
		self._longDescription = ""
		self._usage = ""

		self._params = {}
		self._reqArgs = self._optionalParams and 0 or self._argCount

		--Default all of the parameter options
		for i=1, self._argCount do
			if not self._params[i] then
				self._params[i] = {optional = self._optionalParams, type = 'string'}
			end
		end

		--Log all parameter names for lookup.
		self._paramNames = {}
		for i=1,self._argCount do
			if self._paramNames[debug.getlocal(self._func, i):lower()] then
				self._err = 'Cannot have duplicate parameter names'
			end
			self._paramNames[debug.getlocal(self._func,i):lower()] = i
		end


		--Set help stuff
		self:SetDescription(env.description)
		self:SetLongDescription(env.longDescription)
		self:SetUsage(env.usage)

		--Use builder functions
		self:AddAliases(env.aliases)
		self:SetParametersOptions(env.params or env.parameters)
		self:AddPreconditions(env.preconditions)

	end

	if self._err then self._notValid = true end

end

local function tblFind(tbl,val)
	for k,v in pairs(tbl) do
		if v == val then
			return k
		end
	end
	return false
end

--Function to test if we should try to pull from our paramNames table, or just use the index, or return nil
local function getArg(tbl,numOrName)
	if type(numOrName) == 'string' then
	 return tbl[numOrName:lower()]
  elseif type(numOrName) == 'number' then
	 return numOrName
	end
	return nil
end


function Command:SetParametersOptions(paramTbl)
	--Make sure that the input is a table
	if type(paramTbl) ~= 'table' then
		paramTbl = {paramTbl}
	end
	--Loop through our options table
	for k,v in pairs(paramTbl) do
		--Use our getArg func to find the argument "index" in the names
		local arg = getArg(self._paramNames, k)
		if arg and arg <= self._argCount then

			--If it's a table, then deal with the information
			if type(v) == 'table' then
				local op = v.optional or v[1]
				if type(op) == self._paramTypes.optional then
					self._params[arg].optional = op
				end
				local ty = v.type or v[2]
				if type(ty) == self._paramTypes.type then
						self._params[arg].type = ty
				end

				local rem = v.remainder or v[3]
				if type(rem) == self._paramTypes.remainder then
					if arg ~= self._argCount then
						self._err = ('Remainder parameter must be the final parameter')
						return false
					elseif self._runoff then
						self._err = ('Remainder cannot be applied to a command that allows overflow')
						return false
					end
					self._params[arg].remainder = rem
				end

			elseif type(v) == 'boolean' then
				self._params[arg].optional = v
			end
		end
	end

	--Check to make sure that tomfoolery didn't happen
	local foundReq = 0
	local foundOptional = false
	for i = 1, self._argCount do
		if(not self._params[i].optional and foundOptional) then
			self._err = ("Cannot have required parameter after optional parameter")
			return
		elseif(self._params[i].optional) then
			foundOptional = true
		else
			foundReq = foundReq + 1
		end
	end
	self._reqArgs = foundReq
	return self
end

function Command:SetParameterOptions(param, options)
	return self:SetParametersOptions({[param] = options})
end

function Command:AddPreconditions(preconditions)
	if preconditions == nil then return end
	for k,v in pairs(preconditions) do
		if type(v) == 'string' then
			table.insert(self._preconditions,{v})
		elseif type(v) == 'table' then
			local name, args
			name = v.name or v[1]
			if not name then
				self._err = string.format("Precondition must have a name")
				return
			end
			table.insert(self._preconditions,{name, v.args or v[2]})
		else
			self._err = string.format("Precondition name is of invalid type")
			return
		end
	end
	return self
end

--AddAliases
function Command:AddAliases(...)
	--Loop through all values in our parameters and add to the aliases table if they're not already
	local arg = {...}
	if type(arg[1]) == 'table' then
		arg = unpack(arg)
	end

	local inserted = false
	local new = {}
	for _,v in pairs(arg) do

		if not tblFind(self._aliases, v) then
			table.insert(new, v)
			table.insert(self._aliases, v)
			inserted = true
		end
	end

	--Update the aliases on the handler
	if inserted then
		self._manager:_AddAliases(self)
	end
	return self
end

function Command:RemoveAliases(...)
	local arg = {...}
	if type(arg[1]) == 'table' then
		arg = unpack(arg)
	end

	local removed = false
	local old = {}

	for k,v in pairs(arg) do
		local val = tblFind(self._aliases, v)
		if val then
			table.insert(old, val)
			self._aliases[val] = nil
			removed = true
		end
	end

	if removed then
		self._manager._RemoveAliases(self, old)
	end
	return self
end

function Command:_SplitArgs(str)
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
		if currArg == self._argCount and self._params[currArg].remainder then
			table.insert(outTbl,str:sub(lastArg))
			ignoreLast = true
			break
		end
		if c == ' ' and not inQuotes then
			if not justIn then
				table.insert(outTbl,str:sub(lastArg, i - 1))
			end
			justIn = false
			lastArg = i + 1
		elseif c == "'" then
			if not inQuotes and lastArg == i then
				inQuotes = "'"
			elseif inQuotes == "'" then
				table.insert(outTbl,str:sub(lastArg + 1, i - 1))
				inQuotes = false
				lastArg = i + 1
				justIn = true
			end
		elseif c == '"' then
			if not inQuotes and lastArg == i then
				inQuotes = '"'
			elseif inQuotes == '"' then
				table.insert(outTbl,str:sub(lastArg + 1, i - 1))
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
		return false, "Not enough arguments provided to command"
	end
	if(#outTbl > self._argCount and not self._runoff) then
		return false, "Too many arguments provided to command"
	end
  return outTbl
end


function Command:_Run(client, message, args)
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
	local succ, ret = pcall(self._func, table.unpack(args))
	if not succ then self._manager:fail(ret) end
end



function set.description(self, arg)
	if type(arg) == self._optionTypes.description then
		self._desc = arg
	end
end

function Command:SetDescription(description)
	self.description = description
	return self
end

function set.longDescription(self,longDescription)
	if type(longDescription) == self._optionTypes.longDescription then
		self._longDescription = longDescription
	end
end


function Command:SetLongDescription(longDescription)
	self.longDescription = longDescription
	return self
end

function set.usage(self,use)
	if type(use) == self._optionTypes.usage then
		self._usage = use
	end
end


function Command:SetUsage(use)
	self.usage = use
	return self
end


function get.ignoreCase(self)
	return self._ignoreCase
end

function set.ignoreCase(self, bool)
	if bool == self._ignoreCase then return end
	local name = self._ignoreCase and self.name:lower() or self.name
	self._manager:_RemoveAliases(self, self._aliases)
	local k = tblFind(self._manager._commands[name], self)
	self._manager._commands[name][k] = nil
	self._ignoreCase = bool
	name = self._ignoreCase and self.name:lower() or self.name
	self._manager:_AddAliases(self, self._aliases)
	table.insert(self._manager._commands[name], cmd)
end


function get.name(self)
	return self._name
end

function get.aliases(self)
	return self._aliases
end

function get.description(self)
	return self._desc
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
