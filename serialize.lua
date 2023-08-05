local tolua = require 'ext.tolua'
local function mytolua(x)
	return tolua(x, {
		serializeForType = {
			cdata = function(state, x, ...)
				return tostring(x)
			end,
		}
	})
end

local fromlua = require 'ext.fromlua'
local function myfromlua(x)
	-- empty env ... sandboxed?
	return fromlua(x, nil, nil, {})
end

return {
	tolua = mytolua,
	fromlua = myfromlua,
}
