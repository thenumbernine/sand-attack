local ffi = require 'ffi'
local table = require 'ext.table'
local string = require 'ext.string'
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
	return fromlua(x, nil, 't', {math={huge=math.huge}})
end

local function readDemo(fn)
	local cfg
	xpcall(function()
		local cfgstr = assert(path(fn):read())
		cfg = assert(myfromlua(cfgstr))
		cfg.demoFileName = fn

		if cfg.demoPlayback then
			cfg.demoPlayback = assert(string.unhex(cfg.demoPlayback))
		end

		-- fix old files
		-- TODO rename to 'sandModelName' so it doesn't get mixed up with app.sandModel which is the instanciated object
		if type(cfg.sandModel) == 'number' then
			local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
			cfg.sandModel = sandModelClassNames[cfg.sandModel]
				or error("failed to find sandModel index "..tostring(cfg.sandModel))
		end
	end, function(err)
		print('failed to read file '..tostring(fn)..'\n'
			..tostring(err)..'\n'
			..debug.traceback())
	end)
	return cfg
end

local function writeDemo(fn, cfg)
	xpcall(function()
		-- shallow copy so I can convert the demoPlayback to a hex string upon writing without modifying the input table
		cfg = table(cfg):setmetatable(nil)
		if cfg.demoPlayback then
			cfg.demoPlayback = string.hex(cfg.demoPlayback)
		end
		assert(path(fn):write(
			assert(mytolua(cfg))
		))
	end, function(err)
		print('failed to write file '..tostring(fn)..'\n'
			..tostring(err)..'\n'
			..debug.traceback())
	end)
end

return {
	tolua = mytolua,
	fromlua = myfromlua,
	readDemo = readDemo,
	writeDemo = writeDemo,
}
