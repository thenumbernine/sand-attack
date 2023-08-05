local ffi = require 'ffi'
local table = require 'ext.table'
local range = require 'ext.range'
local math = require 'ext.math'
local vec3f = require 'vec-ffi.vec3f'
require 'ffi.req' 'c.stdlib'	-- strtoll
local ig = require 'imgui'
local Menu = require 'sand-attack.menu.menu'
local PlayerKeysEditor = require 'sand-attack.menu.playerkeys'

local NewGameMenu = Menu:subclass()

function NewGameMenu:init(app, multiplayer)
	NewGameMenu.super.init(self, app)
	self.multiplayer = multiplayer
	if multiplayer then
		app.cfg.numPlayers = math.max(app.cfg.numPlayers, 2)
	else
		app.cfg.numPlayers = 1
	end

	self.playerKeysEditor = PlayerKeysEditor(app)

	-- the newgame menu is init'd upon clicking 'single player' or 'multi player' in the main menu
	-- every time
	-- so re-randomize the game seed here
	app.cfg.randseed = ffi.cast('randSeed_t', bit.bxor(
		ffi.cast('randSeed_t', bit.bxor(os.time(), app.rng(0xffffffff))),
		bit.lshift(ffi.cast('randSeed_t', bit.bxor(os.time(), app.rng(0xffffffff))), 32)
	))
end

-- if we're editing keys then show keys
function NewGameMenu:update()
	self.playerKeysEditor:update()
end

local tmpcolor = ig.ImVec4()	-- for imgui button
local tmpcolorv = vec3f()		-- for imgui color picker

function NewGameMenu:goOrBack(bleh)
	local app = self.app

	ig.igPushID_Int(bleh)

	--ig.igSameLine() -- how to work with centered multiple widgets...
	if self:centerButton'Go!' then
		app:saveConfig()
		app:reset()
		local PlayingMenu = require 'sand-attack.menu.playing'
		app.menustate = PlayingMenu(app)	-- sets paused=false
	end
	if self:centerButton'Back' then
		-- save config upon 'back' ?
		app:saveConfig()
		local MainMenu = require 'sand-attack.menu.main'
		app.menustate = MainMenu(app)
	end

	ig.igPopID()
end

local tmpbuf = ffi.new('char[256]')

function NewGameMenu:updateGUI()
	local app = self.app

	self:beginFullView(self.multiplayer and 'New Game Multiplayer' or 'New Game', 3 * 32)

	self:goOrBack(1)

	if self.multiplayer then
		self:centerText'Number of Players:'
		self:centerLuatableTooltipInputInt('Number of Players', app.cfg, 'numPlayers')
		app.cfg.numPlayers = math.max(app.cfg.numPlayers, 2)
	end

	self.playerKeysEditor:updateGUI()

	self:centerText'Level:'
	self:centerLuatableTooltipInputInt('Level', app.cfg, 'startLevel')
	app.cfg.startLevel = math.clamp(app.cfg.startLevel, 1, 10)

	-- [[ allow modifying colors
	-- modifying colors should be do-able mid-game
	-- however there's no system atm for adjusting current sand pixel colors live mid-game
	-- though there could be if I encode th sand board as just 2 channels (luminance & color-index)
	-- then I could dynamically update the RGB colors of the color-index live
	-- but then I wouldn't be able to put sailor moon gifs on my blocks or any other RGB image ... more on that later
	-- so either way
	-- overall choice
	-- no adjusting colors live.
	-- only adjust colors in the 'new game' menu.
	ig.igNewLine()
	ig.igSeparatorText'Colors'
	ig.igNewLine()

	if app.cfg.numColors < app.maxColors and ig.igButton'+' then
		app.cfg.numColors = app.cfg.numColors + 1
		while #app.cfg.colors < app.cfg.numColors do
			table.insert(app.cfg.colors, app:getDefaultColor(#app.cfg.colors+1))
		end
	end
	ig.igSameLine()
	if app.cfg.numColors > 1 and ig.igButton'-' then
		app.cfg.numColors = app.cfg.numColors - 1
		-- don't remove colors that have previously been added (except via "delete" below)
		-- because then a subsequent + will re-add the old color
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
		assert(app.cfg.numColors >= 1 and app.cfg.numColors <= app.maxColors)
		if ig.igBeginPopupModal('Edit Color', nil, 0) then
			if ig.igColorPicker3('Color', tmpcolorv.s, 0) then
				local c = app.cfg.colors[self.currentColorIndex]
				c[1], c[2], c[3] = tmpcolorv:unpack()
			end
			if app.cfg.numColors > 1 then
				if ig.igButton'Delete Color' then
					table.remove(app.cfg.colors, self.currentColorIndex)
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
		app.cfg.colors = range(app.cfg.numColors):mapi(function(i)
			return app:getDefaultColor(i)
		end):setmetatable(nil)
	end
	--]]

	ig.igNewLine()
	ig.igSeparatorText'Advanced'
	ig.igNewLine()

	self:centerLuatableTooltipInputInt('Number of Next Pieces', app.cfg, 'numNextPieces')
	self:centerLuatableTooltipSliderFloat('Drop Speed', app.cfg, 'dropSpeed', .1, 100, nil, ig.ImGuiSliderFlags_Logarithmic)
	self:centerLuatableTooltipSliderFloat('Move Speed', app.cfg, 'movedx', .1, 100, nil, ig.ImGuiSliderFlags_Logarithmic)
	self:centerLuatableCheckbox('Continuous Drop', app.cfg, 'continuousDrop')

	self:centerLuatableTooltipSliderFloat('Per-Level Speedup Coeff', app.cfg, 'speedupCoeff', .07, .00007, '%.5f', ig.ImGuiSliderFlags_Logarithmic)

	self:centerText'Board:'
	if self:centerLuatableTooltipInputInt('Board Width', app.cfg, 'boardWidthInBlocks') then
		app.cfg.boardWidthInBlocks = math.max(app.cfg.boardWidthInBlocks, 4)
	end
	if self:centerLuatableTooltipInputInt('Board Height', app.cfg, 'boardHeightInBlocks') then
		app.cfg.boardHeightInBlocks = math.max(app.cfg.boardHeightInBlocks, 4)
	end

	if self:centerLuatableTooltipInputInt('Pixels Per Block', app.cfg, 'voxelsPerBlock') then
		app.cfg.voxelsPerBlock = math.max(1, app.cfg.voxelsPerBlock)
		--app:updateGameScale()
	end
	-- TODO should this be customizable?
	-- TODO since it's derived from voxelsPerBlock, it'll show the current-game game-scale
	-- not the same as the app.cfg editing configuration game-scale
	-- I gotta sort out updateGameScale and the split of .cfg (user) vs .playcfg (game)
	-- until then ...
	--self:centerText('(updates/tick: '..app.gameScale..')')

	-- TODO this is only for AutomataCPU ...
	self:centerLuatableTooltipSliderFloat('Topple Chance', app.cfg, 'toppleChance', 0, 1)

	local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
	ig.luatableCombo('Sand Model', app.cfg, 'sandModel', sandModelClassNames)

	-- looks like the standard printf is in the macro PRIx64 ... which I've gotta now make sure is in the ported header ...
	ffi.C.snprintf(tmpbuf, ffi.sizeof(tmpbuf), '%llx', app.cfg.randseed)
	if self:centerInputText('seed', tmpbuf, ffi.sizeof(tmpbuf)) then
		print('updating seed', ffi.string(tmpbuf))
		-- strtoll is long-long should be int64_t ... I could sizeof assert that but meh
		app.cfg.randseed = ffi.C.strtoll(tmpbuf, nil, 16),
		print('updated randseed to', app.cfg.randseed)
	end

	ig.igNewLine()
	self:goOrBack(2)

	self:endFullView()
end

return NewGameMenu
