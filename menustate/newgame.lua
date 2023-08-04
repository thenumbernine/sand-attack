local table = require 'ext.table'
local math = require 'ext.math'
local sdl = require 'ffi.req' 'sdl'
local vec3f = require 'vec-ffi.vec3f'
local ig = require 'imgui'
local MenuState = require 'sand-attack.menustate.menustate'

-- default key mappings for first few players
local defaultKeys

local NewGameState = MenuState:subclass()

function NewGameState:init(app, multiplayer)
	NewGameState.super.init(self, app)
	self.multiplayer = multiplayer
	if multiplayer then
		app.numPlayers = math.max(app.numPlayers, 2)
	else
		app.numPlayers = 1
	end

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

-- if we're editing keys then show keys
function NewGameState:update()
	if self.currentPlayerIndex then
		self.app:drawTouchRegions()
	end
end

local tmpcolor = ig.ImVec4()	-- for imgui button
local tmpcolorv = vec3f()		-- for imgui color picker

function NewGameState:updateGUI()
	local Player = require 'sand-attack.player'
	local app = self.app

	self:beginFullView(self.multiplayer and 'New Game Multiplayer' or 'New Game', 3 * 32)

	--ig.igSameLine() -- how to work with centered multiple widgets...
	if self:centerButton'Go!' then
		app:reset()
		local PlayingState = require 'sand-attack.menustate.playing'
		app.menustate = PlayingState(app)	-- sets paused=false
	end
	if self:centerButton'Back' then
		local MainMenuState = require 'sand-attack.menustate.main'
		app.menustate = MainMenuState(app)
	end

	if self.multiplayer then
		self:centerText'Number of Players:'
		self:centerLuatableTooltipInputInt('Number of Players', app, 'numPlayers')
		app.numPlayers = math.max(app.numPlayers, 2)
	end

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
		if ig.igButton(not self.multiplayer and 'change keys' or 'change player '..i..' keys') then
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


	self:centerText'Level:'
	self:centerLuatableTooltipInputInt('Level', app.cfg, 'startLevel')
	app.cfg.startLevel = math.clamp(app.cfg.startLevel, 1, 20)

	-- [[ allow modifying colors
	self:centerText'Colors:'
	if ig.igButton'+' then
		app.cfg.numColors = app.cfg.numColors + 1
	end
	ig.igSameLine()
	if app.cfg.numColors > 1 and ig.igButton'-' then
		app.cfg.numColors = app.cfg.numColors - 1
	end
	ig.igSameLine()

	for i=1,app.cfg.numColors do
		local c = app.cfg.colors[i]
		tmpcolor.x = c[1]
		tmpcolor.y = c[2]
		tmpcolor.z = c[3]
		tmpcolor.w = 1
		if ig.igColorButton('Color '..i, tmpcolor) then
			tmpcolorv:set(table.unpack(c))
			self.currentColorIndex = i
			-- name maches 'BeginPopupModal' name below:
			ig.igOpenPopup_Str('Edit Color', 0)
		end
		if i % 6 ~= 4 and i < app.cfg.numColors then
			ig.igSameLine()
		end
	end

	if self.currentColorIndex then
		assert(self.currentColorIndex >= 1 and self.currentColorIndex <= app.cfg.numColors)
		assert(app.cfg.numColors >= 1 and app.cfg.numColors <= #app.defaultColors)
		if ig.igBeginPopupModal('Edit Color', nil, 0) then
			if ig.igColorPicker3('Color', tmpcolorv.s, 0) then
				local c = app.cfg.colors[self.currentColorIndex]
				c[1], c[2], c[3] = tmpcolorv:unpack()
			end
			if app.cfg.numColors > 1 then
				if ig.igButton'Delete Color' then
					table.remove(app.cfg.colors, self.currentColorIndex)
					table.insert(app.cfg.colors, {table.unpack(app.defaultColors:last())})
					app.cfg.numColors = app.cfg.numColors - 1
					self.currentColorIndex = nil
				end
			end
			if ig.igButton'Done' then
				ig.igCloseCurrentPopup()
				self.currentColorIndex = nil
				app:saveConfig()
			end
			ig.igEnd()
		end
	end
	if self:centerButton'Reset Colors' then
		for i,dstc in ipairs(app.cfg.colors) do
			local srcc = app.defaultColors[i]
			for j=1,3 do
				dstc[j] = srcc[j]
			end
		end
	end
	--]]
	self:endFullView()
end

return NewGameState
