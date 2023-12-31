local table = require 'ext.table'

local classes = table{
	require 'sand-attack.sandmodel.automatagpu',
	require 'sand-attack.sandmodel.automatacpu',
	require 'sand-attack.sandmodel.sph',
	require 'sand-attack.sandmodel.cfd',
}
local classNames = classes:mapi(function(cl) return cl.name end)
local classForName = classes:mapi(function(cl) return cl, cl.name end):setmetatable(nil)

return {
	classes = classes,
	classNames = classNames,
	classForName = classForName,
}
