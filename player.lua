local class = require 'ext.class'
local vec2i = require 'vec-ffi.vec2i'
local vec3f = require 'vec-ffi.vec3f'

local Player = class()

Player.keyNames = {
	'up',
	'down',
	'left',
	'right',
	'pause',
}

function Player:init(args)
	self.index = args.index
	local app = assert(args.app)
	self.app = app
	self.color = vec3f(app.cfg.colors[self.index])
	self.keyPress = {}
	self.keyPressLast = {}

	self.pieceTex = app:makeTexWithImage(app.pieceSize)
	-- give pieces an outline so you can tell players apart
	self.pieceOutlineTex = app:makeTexWithImage(vec2i(
		app.pieceSize.x + 2 * app.pieceOutlineRadius,
		app.pieceSize.y + 2 * app.pieceOutlineRadius
	))
end

return Player
