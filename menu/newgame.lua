local ffi = require 'ffi'
local table = require 'ext.table'
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
		app.numPlayers = math.max(app.numPlayers, 2)
	else
		app.numPlayers = 1
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
		self:centerLuatableTooltipInputInt('Number of Players', app, 'numPlayers')
		app.numPlayers = math.max(app.numPlayers, 2)
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
		app:updateGameScale()
	end
	-- TODO should this be customizable?
	self:centerText('(updates/tick: '..app.gameScale..')')

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
