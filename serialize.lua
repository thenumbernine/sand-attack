local ffi = require 'ffi'
local table = require 'ext.table'
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
	return fromlua(x, nil, 't', {})
end

local function hextostr(h)
	if bit.band(#h, 1) == 1
	or h:find'[^0-9a-fA-F]'
	then
		return nil, "string is not hex"
	end
	return h:gsub('..', function(d)
		return string.char(assert(tonumber(d, 16)))
	end)
end

local function strtohex(s)
	return (s:gsub('.', function(c)
		return ('%02x'):format(c:byte())
	end))
end

local function readDemo(fn)
	local cfg
	xpcall(function()
		local cfgstr = assert(path(fn):read())
		cfg = assert(myfromlua(cfgstr))
		cfg.demoFileName = fn

		if cfg.demoPlayback then
			cfg.demoPlayback = assert(hextostr(cfg.demoPlayback))
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
			cfg.demoPlayback = strtohex(cfg.demoPlayback)
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
	strtohex = strtohex,
	hextostr = hextostr,
}
