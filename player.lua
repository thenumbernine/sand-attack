local ffi = require 'ffi'
local sdl = require 'ffi.sdl'
local template = require 'template'
local class = require 'ext.class'
local table = require 'ext.table'
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

-- static, used by gamestate and app
function Player:getEventName(sdlEventID, a,b,c)
	if not a then return '?' end
	local function dir(d)
		local s = table()
		local ds = 'udlr'
		for i=1,4 do
			if 0 ~= bit.band(d,bit.lshift(1,i-1)) then
				s:insert(ds:sub(i,i))
			end
		end
		return s:concat()
	end
	local function key(k)
		return ffi.string(sdl.SDL_GetKeyName(k))
	end
	return template(({
		[sdl.SDL_JOYHATMOTION] = 'joy<?=a?> hat<?=b?> <?=dir(c)?>',
		[sdl.SDL_JOYAXISMOTION] = 'joy<?=a?> axis<?=b?> <?=c?>',
		[sdl.SDL_JOYBUTTONDOWN] = 'joy<?=a?> button<?=b?>',
		[sdl.SDL_KEYDOWN] = 'key <?=key(a)?>',
	})[sdlEventID], {
		a=a, b=b, c=c,
		dir=dir, key=key,
	})
end

-- default key mappings for first few players
Player.defaultKeys = {
	{
		up = {sdl.SDL_KEYDOWN, sdl.SDLK_UP},
		down = {sdl.SDL_KEYDOWN, sdl.SDLK_DOWN},
		left = {sdl.SDL_KEYDOWN, sdl.SDLK_LEFT},
		right = {sdl.SDL_KEYDOWN, sdl.SDLK_RIGHT},
		pause = {sdl.SDL_KEYDOWN, sdl.SDLK_ESCAPE},
	},
	{
		up = {sdl.SDL_KEYDOWN, ('w'):byte()},
		down = {sdl.SDL_KEYDOWN, ('s'):byte()},
		left = {sdl.SDL_KEYDOWN, ('a'):byte()},
		right = {sdl.SDL_KEYDOWN, ('d'):byte()},
		pause = {},	-- sorry keypad player 2
	},
}
for _,keyEvents in ipairs(Player.defaultKeys) do
	for keyName,event in pairs(keyEvents) do
		event.name = Player:getEventName(table.unpack(event))
	end
end

return Player
