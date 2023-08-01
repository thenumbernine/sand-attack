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

	self.pieceTex = app:makeTexWithBlankImage(app.pieceSize)
	--[[ don't need to hold onto image
	self.pieceTex.data = nil
	self.pieceTex.image = nil
	--]]
	-- ...nah, still needed by:
	-- 	- App:updatePieceTex for calculating pieceColMin and pieceColMax
	--	- SandModel:testPieceMerge and SandModel:mergePiece

	-- give pieces an outline so you can tell players apart
	self.pieceOutlineTex = app:makeTexWithBlankImage(app.pieceOutlineSize)
	-- don't need to hold onto image
	self.pieceOutlineTex.data = nil
	self.pieceOutlineTex.image = nil
end

return Player
