--[[
this isn't a menustate
but it's going to contain some controls used by both the NewGame and Config menustates
--]]
local table = require 'ext.table'
local class = require 'ext.class'
local ig = require 'imgui'
local sdl = require 'ffi.req' 'sdl'

local PlayerKeysEditor = class()

-- default key mappings for first few players
local defaultKeys

function PlayerKeysEditor:init(app)
	self.app = assert(app)
	--static-init after the app has been created
	if not defaultKeys then
		local App = require 'sand-attack.app'
		defaultKeys = {
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
		for _,keyEvents in ipairs(defaultKeys) do
			for keyName,event in pairs(keyEvents) do
				event.name = App:getEventName(table.unpack(event))
			end
		end
	end
end

function PlayerKeysEditor:update()
	if self.currentPlayerIndex then
		self.app:drawTouchRegions()
	end
end

function PlayerKeysEditor:updateGUI()
	local Player = require 'sand-attack.player'
	local app = self.app
	local multiplayer = app.numPlayers > 1	
	-- should player keys be here or config?
	-- config: because it is in every other game
	-- here: because key config is based on # players, and # players is set here.
	for i=1,app.numPlayers do
		if not app.cfg.playerKeys[i] then
			app.cfg.playerKeys[i] = {}
			local defaultsrc = defaultKeys[i]
			for _,keyname in ipairs(Player.keyNames) do
				app.cfg.playerKeys[i][keyname] = defaultsrc and defaultsrc[keyname] or {}
			end
		end
		if ig.igButton(not multiplayer and 'change keys' or 'change player '..i..' keys') then
			self.currentPlayerIndex = i
			ig.igOpenPopup_Str('Edit Keys', 0)
		end
	end
	if self.currentPlayerIndex then
		assert(self.currentPlayerIndex >= 1 and self.currentPlayerIndex <= app.numPlayers)
		-- this is modal but it makes the drawn onscreen gui hard to see
		if ig.igBeginPopupModal'Edit Keys' then
		-- this isn't modal so you can select off this window
		--if ig.igBeginPopup('Edit Keys', 0) then
			for _,keyname in ipairs(Player.keyNames) do
				ig.igPushID_Str(keyname)
				ig.igText(keyname)
				ig.igSameLine()
				local ev = app.cfg.playerKeys[self.currentPlayerIndex][keyname]
				if ig.igButton(
					app.waitingForEvent
					and app.waitingForEvent.key == keyname
					and app.waitingForEvent.playerIndex == self.currentPlayerIndex
					and 'Press Button...' or (ev and ev.name) or '?')
				then
					app.waitingForEvent = {
						key = keyname,
						playerIndex = self.currentPlayerIndex,
						callback = function(ev)
							--[[ always reserve escape?  or allow player to configure it as the pause key?
							if ev[1] == sdl.SDL_KEYDOWN and ev[2] == sdl.SDLK_ESCAPE then
								app.cfg.playerKeys[self.currentPlayerIndex][keyname] = {}
								return
							end
							--]]
							-- mouse/touch requires two clicks to determine size? meh... no, confusing.
							app.cfg.playerKeys[self.currentPlayerIndex][keyname] = ev
						end,
					}
				end
				ig.igPopID()
			end
			if ig.igButton'Done' then
				app:saveConfig()
				ig.igCloseCurrentPopup()
				self.currentPlayerIndex = nil
			end
			ig.igEnd()
		end
	end
end

return PlayerKeysEditor
