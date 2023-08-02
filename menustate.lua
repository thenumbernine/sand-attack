local ffi = require 'ffi'
local sdl = require 'ffi.req' 'sdl'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local math = require 'ext.math'
local ops = require 'ext.op'
local vec3f = require 'vec-ffi.vec3f'
local gl = require 'gl'
local ig = require 'imgui'
local getTime = require 'ext.timer'.getTime

local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames

local MenuState = class()
function MenuState:init(app)
	local App = require 'sand-attack.app'
	assert(App:isa(app))
	self.app = assert(app)
end
-- TODO change the style around
function MenuState:beginFullView(name, estheight)
estheight = nil
	-- TODO put in lua-imgui
	local viewport = ig.igGetMainViewport()
	ig.igSetNextWindowPos(viewport.WorkPos, 0, ig.ImVec2())
	ig.igSetNextWindowSize(viewport.WorkSize, 0)
	ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowRounding, 0)
	ig.igBegin(name, nil, bit.bor(
		ig.ImGuiWindowFlags_NoMove,
		ig.ImGuiWindowFlags_NoResize,
		ig.ImGuiWindowFlags_NoCollapse,
		ig.ImGuiWindowFlags_NoDecoration
	))
	self.viewCenterX = viewport.WorkSize.x * .5
	local viewheight = viewport.WorkSize.y * .5

	-- TODO calc this?
	if estheight and estheight < viewheight then
		ig.igSetCursorPosY(viewheight - .5 * estheight)
	end

	ig.igSetWindowFontScale(2)
	self:centerText(name)
	ig.igSetWindowFontScale(1)
end
function MenuState:endFullView()
	ig.igEnd()
	ig.igPopStyleVar(1)
end
local tmp = ffi.new'ImVec2[1]'
function MenuState:centerGUI(fn, text, ...)
	-- TODO put in lua-imgui
	-- TODO TODO for buttons and text this is fine, but for inputs the width can be *much wider* than the text width.
	local textwidth
	if self.overrideTextWidth ~= nil then
		textwidth = self.overrideTextWidth
	else
		ig.igCalcTextSize(tmp, text, nil, false, -1)
		textwidth = tmp[0].x
	end
	local x = self.viewCenterX - .5 * textwidth
	if x >= 0 then
		ig.igSetCursorPosX(x)
	end
	return fn(text, ...)
end
function MenuState:centerText(...)
	return self:centerGUI(ig.igText, ...)
end
function MenuState:centerButton(...)
	return self:centerGUI(ig.igButton, ...)
end
function MenuState:centerLuatableCheckbox(...)
	return self:centerGUI(ig.luatableCheckbox, ...)
end

-- is ugly enough i have to fix this often enough so:
-- TODO fix somehow
function MenuState:centerLuatableInputInt(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableInputInt, ...)
	self.overrideTextWidth = nil
end
function MenuState:centerLuatableTooltipInputInt(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableTooltipInputInt, ...)
	self.overrideTextWidth = nil
end
function MenuState:centerLuatableInputFloat(...)
	print"WARNING imgui gamepad nav can't change input float"
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableInputFloat, ...)
	self.overrideTextWidth = nil
end
function MenuState:centerLuatableTooltipInputFloat(...)
	print"WARNING imgui gamepad nav can't change input float"
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableTooltipInputFloat, ...)
	self.overrideTextWidth = nil
end
function MenuState:centerLuatableSliderFloat(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableSliderFloat, ...)
	self.overrideTextWidth = nil
end
function MenuState:centerLuatableTooltipSliderFloat(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableTooltipSliderFloat, ...)
	self.overrideTextWidth = nil
end


local LoseScreen = class(MenuState)

local PlayingState = class(MenuState)
MenuState.PlayingState = PlayingState
function PlayingState:init(app)
	PlayingState.super.init(self, app)
	app.paused = false
end
function PlayingState:update()
	self.app:drawTouchRegions()
end
function PlayingState:updateGUI()
	local app = self.app
	ig.igSetNextWindowPos(ig.ImVec2(0, 0), 0, ig.ImVec2())
	ig.igSetNextWindowSize(ig.ImVec2(-1, -1), 0)
	ig.igBegin('X', nil, bit.bor(
		ig.ImGuiWindowFlags_NoMove,
		ig.ImGuiWindowFlags_NoResize,
		ig.ImGuiWindowFlags_NoCollapse,
		ig.ImGuiWindowFlags_NoDecoration,
		ig.ImGuiWindowFlags_NoBackground
	))
	ig.igSetWindowFontScale(.5)

	ig.igText('Level: '..tostring(app.level))
	ig.igText('Score: '..tostring(app.score))
	ig.igText('Lines: '..tostring(app.lines))

	if app.showDebug then
		if app.showFPS then ig.igText('FPS: '..app.fps) end
		-- TODO readpixels or something to copy latest sand image
		--ig.igText('Num Voxels: '..app.numSandVoxels)
		ig.igText('Ticks to Fall: '..tostring(app.ticksToFall))
		if app.sandmodel.updateDebugGUI then
			app.sandmodel:updateDebugGUI()
		end
	end

	-- where on the screen to put this?
	if app.gameTime - app.lastLineTime < app.chainDuration then
		ig.igText('chain x'..tostring(app.scoreChain + 1))
	end
	ig.igSetWindowFontScale(1)

	ig.igEnd()

	if app.paused then
        local size = ig.igGetMainViewport().WorkSize
        ig.igSetNextWindowPos(ig.ImVec2(size.x/2, size.y/2), ig.ImGuiCond_Appearing, ig.ImVec2(.5, .5));
		ig.igBegin'Paused'
		if ig.igButton(app.paused and 'Resume' or 'Pause') then
			app.paused = not app.paused
		end
		if ig.igButton'End Game' then
			app.loseTime = nil
			app.paused = true
			app.menustate = MenuState.HighScoreState(app, true)
		end
		ig.igEnd()
	end
end


-- TODO save config
local ConfigState = class(MenuState)
function ConfigState:updateGUI()
	local app = self.app
	self:beginFullView('Config', 6 * 32)

	self:centerLuatableTooltipInputInt('Number of Next Pieces', app.cfg, 'numNextPieces')
	self:centerLuatableTooltipSliderFloat('Drop Speed', app.cfg, 'dropSpeed', .1, 100, nil, ig.ImGuiSliderFlags_Logarithmic)
	self:centerLuatableTooltipInputInt('Move Speed', app.cfg, 'movedx')
	self:centerLuatableCheckbox('Continuous Drop', app.cfg, 'continuousDrop')

	self:centerLuatableTooltipSliderFloat('Per-Level Speedup Coeff', app.cfg, 'speedupCoeff', .07, .00007, '%.5f', ig.ImGuiSliderFlags_Logarithmic)

	self:centerText'Board:'
	self:centerLuatableTooltipInputInt('Board Width', app.cfg.boardSizeInBlocks, 'x')
	self:centerLuatableTooltipInputInt('Board Height', app.cfg.boardSizeInBlocks, 'y')
	self:centerLuatableTooltipSliderFloat('Topple Chance', app.cfg, 'toppleChance', 0, 1)
	self:centerLuatableTooltipInputInt('Pixels Per Block', app.cfg, 'voxelsPerBlock')
	app.cfg.voxelsPerBlock = math.max(1, app.cfg.voxelsPerBlock)

	ig.luatableCombo('Sand Model', app.cfg, 'sandModel', sandModelClassNames)

	if app.useAudio then
		self:centerText'Audio:'
		if self:centerLuatableTooltipSliderFloat('FX Volume', app.cfg, 'effectVolume', 0, 1) then
			--[[ if you want, update all previous audio sources...
			for _,src in ipairs(app.audioSources) do
				-- TODO if the gameplay sets the gain down then we'll want to multiply by their default gain
				src:setGain(app.cfg.effectVolume * src.gain)
			end
			--]]
		end
		if self:centerLuatableTooltipSliderFloat('BG Volume', app.cfg, 'backgroundVolume', 0, 1) then
			app.bgAudioSource:setGain(app.cfg.backgroundVolume)
		end
	end

	self:centerText'Controls:'
	self:centerLuatableTooltipSliderFloat('On-Screen Button Radius', app.cfg, 'screenButtonRadius', .001, 1)

	if self:centerButton'Done' then
		app:saveConfig()
		app.menustate = MenuState.MainMenuState(app)
	end
	self:endFullView()
end


-- default key mappings for first few players
local defaultKeys

local StartNewGameState = class(MenuState)
function StartNewGameState:init(app, multiplayer)
	StartNewGameState.super.init(self, app)
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
function StartNewGameState:update()
	if self.currentPlayerIndex then
		self.app:drawTouchRegions()
	end
end

local tmpcolor = ig.ImVec4()	-- for imgui button
local tmpcolorv = vec3f()		-- for imgui color picker
function StartNewGameState:updateGUI()
	local Player = require 'sand-attack.player'
	local app = self.app

	self:beginFullView(self.multiplayer and 'New Game Multiplayer' or 'New Game', 3 * 32)

	--ig.igSameLine() -- how to work with centered multiple widgets...
	if self:centerButton'Go!' then
		app:reset()
		app.menustate = PlayingState(app)	-- sets paused=false
	end
	if self:centerButton'Back' then
		app.menustate = MenuState.MainMenuState(app)
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


local MainMenuState = class(MenuState)
MenuState.MainMenuState = MainMenuState
function MainMenuState:init(...)
	MainMenuState.super.init(self, ...)
	self.app.paused = true
end
function MainMenuState:updateGUI()
	local app = self.app
	self:beginFullView('Sand Attack', 6 * 32)

	--[[ how to get default focus... smh imgui ...
	-- i remember when this was called 'tabstop' and 'tabindex' and it is incrediblly easy to configure in windows...
	--https://github.com/ocornut/imgui/issues/455
	if ig.igIsWindowFocused(ig.ImGuiFocusedFlags_RootAndChildWindows)
	and not ig.igIsAnyItemActive()
	and not ig.igIsMouseClicked(0, false)
	then
		ig.igSetKeyboardFocusHere(0)
	end
	--]]

	if self:centerButton'New Game' then
		-- TODO choose gametype and choose level
		app.menustate = StartNewGameState(app)
	end
	if self:centerButton'New Game Co-op' then
		app.menustate = StartNewGameState(app, true)
		-- TODO pick same as before except pick # of players
	end
	-- TODO RESUME GAME here
	if self:centerButton'Config' then
		app.menustate = ConfigState(app)
	end
	if self:centerButton'High Scores' then
		app.menustate = MenuState.HighScoreState(app)
	end
	local url = 'https://github.com/thenumbernine/sand-attack'
	if self:centerButton'About' then
		if ffi.os == 'Windows' then
			os.execute('explorer "'..url..'"')
		elseif ffi.os == 'OSX' then
			os.execute('open "'..url..'"')
		else
			os.execute('xdg-open "'..url..'"')
		end
	end
	if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
		ig.igSetMouseCursor(ig.ImGuiMouseCursor_Hand)
		ig.igBeginTooltip()
		ig.igText('by Christopher Moore')
		ig.igText('click to go to')
		ig.igText(url)
		ig.igEndTooltip()
	end

	if self:centerButton'Exit' then
		app:requestExit()
	end

	self:endFullView()
end

local SplashScreenState = class(MenuState)
MenuState.SplashScreenState = SplashScreenState
SplashScreenState.duration = 3
-- TODO cool sand effect or something
function SplashScreenState:init(...)
	SplashScreenState.super.init(self, ...)
	self.startTime = getTime()
end
function SplashScreenState:update()
	local app = self.app

	local w, h = app.sandSize:unpack()

	local aspectRatio = app.width / app.height

	app.projMat:setOrtho(-.5 * aspectRatio, .5 * aspectRatio, -.5, .5, -1, 1)
	app.displayShader
		:use()
		:enableAttrs()

	app.mvMat
		:setTranslate(-.5 * aspectRatio, -.5)
		:applyScale(aspectRatio, 1)
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(app.displayShader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)

	gl.glUniform1i(app.displayShader.uniforms.useAlpha.loc, 1)

	app.splashTex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

	gl.glUniform1i(app.displayShader.uniforms.useAlpha.loc, 0)

	app.splashTex:unbind()
	app.displayShader
		:disableAttrs()
		:useNone()


	if getTime() - self.startTime > self.duration then
		app.menustate = MainMenuState(app)
	end
end
function SplashScreenState:event(e)
	local app = self.app
	if e.type == sdl.SDL_JOYHATMOTION
	or e.type == sdl.SDL_JOYAXISMOTION
	or e.type == sdl.SDL_JOYBUTTONDOWN
	or e.type == sdl.SDL_CONTROLLERAXISMOTION
	or e.type == sdl.SDL_CONTROLLERBUTTONDOWN
	or e.type == sdl.SDL_KEYDOWN
	or e.type == sdl.SDL_MOUSEBUTTONDOWN
	or e.type == sdl.SDL_FINGERDOWN
	then
		app.menustate = MainMenuState(app)
	end
end

local HighScoreState = class(MenuState)
MenuState.HighScoreState = HighScoreState
function HighScoreState:init(app, needsName)
	HighScoreState.super.init(self, app)
	self.needsName = needsName
	self.name = ''
end
-- save state info pertinent to the gameplay
-- TODO save recording of all keystrokes and game rand seed?
HighScoreState.fields = table{
	'name',
	'lines',
	'level',
	'score',
	'numColors',
	'numPlayers',
	'boardWidth',
	'boardHeight',
	'toppleChance',
	'voxelsPerBlock',
	'sandModel',
	'speedupCoeff',
}
function HighScoreState:makeNewRecord()
	local app = self.app
	local record = {}
	for _,field in ipairs(self.fields) do
		if field == 'name' then
			record[field] = self[field]
		elseif field == 'toppleChance'
		or field == 'voxelsPerBlock'
		or field == 'numColors'
		or field == 'speedupCoeff'
		then
			record[field] = app.cfg[field]
		elseif field == 'sandModel' then
			record[field] = sandModelClassNames[app.cfg[field]]
		elseif field == 'boardWidth' then
			record[field] = tonumber(app.cfg.boardSizeInBlocks.x)
		elseif field == 'boardHeight' then
			record[field] = tonumber(app.cfg.boardSizeInBlocks.y)
		else
			record[field] = app[field]
		end
	end
	return record
end
function HighScoreState:updateGUI()
	local app = self.app
	self:beginFullView'High Scores:'

	-- TODO separate state for this?
	if self.needsName then
		ig.igText'Your Name:'
		ig.luatableTooltipInputText('Your Name', self, 'name')
		if ig.igButton'Ok' then
			self.needsName = false
			local record = self:makeNewRecord()
			table.insert(app.highscores, record)
			table.sort(app.highscores, function(a,b)
				return a.score > b.score
			end)
			app:saveHighScores()
		end
		ig.igNewLine()
	end

	if ig.igBeginTable('High Scores', #self.fields, bit.bor(
		--[[
		ig.ImGuiTableFlags_SizingFixedFit,
		ig.ImGuiTableFlags_ScrollX,
		ig.ImGuiTableFlags_ScrollY,
		ig.ImGuiTableFlags_RowBg,
		ig.ImGuiTableFlags_BordersOuter,
		ig.ImGuiTableFlags_BordersV,
		ig.ImGuiTableFlags_Resizable,
		ig.ImGuiTableFlags_Reorderable,
		ig.ImGuiTableFlags_Hideable,
		ig.ImGuiTableFlags_Sortable
		--]]
		-- [[
		ig.ImGuiTableFlags_Resizable,
		ig.ImGuiTableFlags_Reorderable,
		--ig.ImGuiTableFlags_Hideable,
		ig.ImGuiTableFlags_Sortable,
		ig.ImGuiTableFlags_SortMulti,
		--ig.ImGuiTableFlags_RowBg,
		ig.ImGuiTableFlags_BordersOuter,
		ig.ImGuiTableFlags_BordersV,
		--ig.ImGuiTableFlags_NoBordersInBody,
		--ig.ImGuiTableFlags_ScrollY,
		--]]
	0), ig.ImVec2(0,0), 0) then

		for i,field in ipairs(self.fields) do
			ig.igTableSetupColumn(tostring(field), bit.bor(
					ig.ImGuiTableColumnFlags_DefaultSort
				),
				0,
				i	-- ColumnUserID in the sort
			)
		end
		ig.igTableHeadersRow()
		local sortSpecs = ig.igTableGetSortSpecs()
		if not self.rowindexes or #self.rowindexes ~= #app.highscores then
			self.rowindexes = range(#app.highscores)
		end
		if sortSpecs[0].SpecsDirty then
			local typescore = {
				string = 1,
				number = 2,
				table = 3,
				['nil'] = math.huge,
			}
			-- sort from imgui_demo.cpp CompareWithSortSpecs
			-- TODO maybe put this in lua-imgui
			table.sort(self.rowindexes, function(ia,ib)
				local a = app.highscores[ia]
				local b = app.highscores[ib]
				for n=0,sortSpecs[0].SpecsCount-1 do
					local sortSpec = sortSpecs[0].Specs[n]
					local col = sortSpec.ColumnUserID
					local field = self.fields[tonumber(col)]
					local afield = a[field]
					local bfield = b[field]
					local tafield = type(afield)
					local tbfield = type(bfield)
--print('testing', afield, bfield, tafield, tbfield)
					if afield ~= bfield then
						local op = sortSpec.SortDirection == ig.ImGuiSortDirection_Ascending and ops.lt or ops.gt
						if tafield ~= tbfield then
							-- put nils last ... score for type?
							return op(typescore[tafield], typescore[tbfield])
						end
						return op(afield, bfield)
					end
				end
				return ia < ib
			end)
			sortSpecs[0].SpecsDirty = false
		end
		for _,i in ipairs(self.rowindexes) do
			local score = app.highscores[i]
			ig.igTableNextRow(0, 0)
			for _,field in ipairs(self.fields) do
				ig.igTableNextColumn()
				ig.igText(tostring(score[field]))
			end
		end
		ig.igEndTable()
	end
	if ig.igButton'Done' then
		self.needsName = false
		app.menustate = MainMenuState(app)
	end
	if not self.needsName then
		ig.igSameLine()
		if ig.igButton'Clear' then
			app.highscores = {}
			app:saveHighScores()
		end
	end
	self:endFullView()
end

return MenuState
