local sdl = require 'ffi.sdl'
local class = require 'ext.class'

local Player = class()

function Player:init(args)
	self.index = args.index
	local app = assert(args.app)
	self.app = app
	self.color = app.baseColors[self.index]
	self.keyPress = {}
	self.keyPressLast = {}

	if self.index == 1 then
		self.keys = {
			up = sdl.SDLK_UP,
			down = sdl.SDLK_DOWN,
			left = sdl.SDLK_LEFT,
			right = sdl.SDLK_RIGHT,
		}
	elseif self.index == 2 then
		self.keys = {
			up = ('w'):byte(),
			down = ('s'):byte(),
			left = ('a'):byte(),
			right = ('d'):byte(),
		}
	end
	assert(self.keys, "failed to find key mapping for player "..self.index)
	self.pieceTex = app:makeTexWithImage(app.pieceSize)
	-- give pieces an outline so you can tell players apart
	self.pieceOutlineTex = app:makeTexWithImage(app.pieceSize)
end

function Player:handleKeyUpDown(sym, down)
	for k,v in pairs(self.keys) do
		if sym == v then
			self.keyPress[k] = down
		end
	end
end

return Player
