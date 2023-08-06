local ffi = require 'ffi'
local path = require 'ext.path'
local tolua = require 'ext.tolua'
local fromlua = require 'ext.fromlua'

-- TODO rename this to 'util' or something?

local function mytolua(x)
	return tolua(x, {
		serializeForType = {
			cdata = function(state, x, ...)
				return tostring(x)
			end,
		}
	})
end

local function myfromlua(x)
	-- empty env ... sandboxed?
	return fromlua(x, nil, nil, {})
end

local function readDemo(fn)
	local d = assert(path(fn):read())
	local dlen = #d
	local len = tonumber(ffi.C.strlen(d))
	local cfgstr = d:sub(1,len)
	local demo
	if dlen > len then
		assert(d:sub(len+1,len+1):byte() == 0)
		demo = d:sub(len+2)
	end
	local cfg = assert(myfromlua(cfgstr))
	cfg.demoFileName = fn
	cfg.demoPlayback = demo
	
	-- fix old files
	-- TODO rename to 'sandModelName'
	if type(cfg.sandModel) == 'number' then
		local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
		cfg.sandModel = sandModelClassNames[cfg.sandModel]
			or error("failed to find sandModel index "..tostring(cfg.sandModel))
	end

	return cfg
end

return {
	tolua = mytolua,
	fromlua = myfromlua,
	readDemo = readDemo,
}
