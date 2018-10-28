function copy(tbl)
	local ret = {}
	for k, v in pairs(tbl) do
		ret[k] = v
	end
	return ret
end

function deepcopy(tbl)
	local ret = {}
	for k, v in pairs(tbl) do
		ret[k] = type(v) == 'table' and deepcopy(v) or v
	end
	return ret
end

function startswith(str, pattern, plain)
	local start = 1
	return string.find(str, pattern, start, plain) == start
end

return {startswith = startswith, copy = copy, deepcopy = deepcopy}
