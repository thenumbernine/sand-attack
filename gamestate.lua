local ffi = require 'ffi'
local sdl = require 'ffi.sdl'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local math = require 'ext.math'
local tolua = require 'ext.tolua'
local ops = require 'ext.op'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local ig = require 'imgui'
local getTime = require 'ext.timer'.getTime

local showDebug = false	-- show debug info in gui

local GameState = class()
function GameState:init(app)
	local App = require 'sandtetris.app'
	assert(App:isa(app))
	self.app = assert(app)
end
-- TODO change the style around
function GameState:beginFullView(name, estheight)
	-- TODO put in lua-imgui
	local viewport = ig.igGetMainViewport()
	ig.igSetNextWindowPos(viewport.WorkPos, 0, ig.ImVec2())
	ig.igSetNextWindowSize(viewport.WorkSize, 0)
	ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowRounding, 0)
	ig.igBegin('Main Menu', nil, bit.bor(
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
end
function GameState:endFullView()
	ig.igEnd()
	ig.igPopStyleVar(1)
end
local tmp = ffi.new('ImVec2[1]')
function GameState:centerGUI(fn, text, ...)
	-- TODO put in lua-imgui
	-- TODO TODO for buttons and text this is fine, but for inputs the width can be *much wider* than the text width.
	local textwidth
	if self.overrideTextWidth ~= nil then
		textwidth = self.overrideTextWidth
	else
		ig.igCalcTextSize(tmp, text, nil, false, -1)
		textwidth = tmp[0].x
	end
	ig.igSetCursorPosX(self.viewCenterX - .5 * textwidth)
	return fn(text, ...)
end
function GameState:centerText(...)
	return self:centerGUI(ig.igText, ...)
end
function GameState:centerButton(...)
	return self:centerGUI(ig.igButton, ...)
end

-- is ugly enough i have to fix this often enough so:
-- TODO fix somehow
function GameState:centerLuatableInputInt(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableInputInt, ...)
	self.overrideTextWidth = nil
end
function GameState:centerLuatableTooltipInputInt(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableTooltipInputInt, ...)
	self.overrideTextWidth = nil
end
function GameState:centerLuatableInputFloat(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableInputFloat, ...)
	self.overrideTextWidth = nil
end
function GameState:centerLuatableTooltipInputFloat(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableTooltipInputFloat, ...)
	self.overrideTextWidth = nil
end
function GameState:centerLuatableSliderFloat(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableSliderFloat, ...)
	self.overrideTextWidth = nil
end
function GameState:centerLuatableTooltipSliderFloat(...)
	self.overrideTextWidth = 360
	self:centerGUI(ig.luatableTooltipSliderFloat, ...)
	self.overrideTextWidth = nil
end


local LoseScreen = class(GameState)

local PlayingState = class(GameState)
GameState.PlayingState = PlayingState
function PlayingState:init(app)
	PlayingState.super.init(self, app)
	app.paused = false
end
function PlayingState:update()
end
function PlayingState:updateGUI()
	local app = self.app
	-- [[
	ig.igSetNextWindowPos(ig.ImVec2(0, 0), 0, ig.ImVec2())
	ig.igSetNextWindowSize(ig.ImVec2(150, -1), 0)
	ig.igBegin('X', nil, bit.bor(
		ig.ImGuiWindowFlags_NoMove,
		ig.ImGuiWindowFlags_NoResize,
		ig.ImGuiWindowFlags_NoCollapse,
		ig.ImGuiWindowFlags_NoDecoration
	))
	--]]
	--[[
	ig.igBegin('Config', nil, 0)
	--]]

	ig.igText('Level: '..tostring(app.level))
	ig.igText('Score: '..tostring(app.score))
	ig.igText('Lines: '..tostring(app.lines))
	if app.showFPS then ig.igText('FPS: '..app.fps) end
	if showDebug then
		ig.igText('Num Voxels: '..app.numSandVoxels)
		ig.igText('Ticks to fall: '..tostring(app.ticksToFall))
	end

	if ig.igButton(app.paused and 'Resume' or 'Pause') then
		app.paused = not app.paused
	end
	if ig.igButton'End Game' then
		app.loseTime = nil
		app.paused = true
		app.state = GameState.HighScoreState(app, true)
	end

	ig.igEnd()
end


-- TODO save config
local ConfigState = class(GameState)
local tmpcolor = ig.ImVec4()
function ConfigState:updateGUI()
	local app = self.app
	self:beginFullView('Config', 6 * 32)
	self:centerLuatableInputInt('Number of Next Pieces', app, 'numNextPieces')
	self:centerLuatableInputFloat('Drop Speed', app, 'dropSpeed')

	self:centerText'Colors:'
	if ig.igButton'+' then
		app.numColors = app.numColors + 1
		app.nextColors = app.baseColors:sub(1, app.numColors)
	end
	ig.igSameLine()
	if app.numColors > 1 and ig.igButton'-' then
		app.numColors = app.numColors - 1
		app.nextColors = app.baseColors:sub(1, app.numColors)
	end
	ig.igSameLine()

	for i=1,app.numColors do
		local c = app.nextColors[i]
		tmpcolor.x = c.x
		tmpcolor.y = c.y
		tmpcolor.z = c.z
		tmpcolor.w = 1
		if ig.igColorButton('Color '..i, tmpcolor) then
			self.currentColorEditing = i
		end
		if i % 6 ~= 4 and i < app.numColors then
			ig.igSameLine()
		end
	end

	if self.currentColorEditing then
		ig.igBegin('Color', nil, bit.bor(
			ig.ImGuiWindowFlags_NoTitleBar,
			ig.ImGuiWindowFlags_NoResize,
			ig.ImGuiWindowFlags_NoCollapse,
			ig.ImGuiWindowFlags_AlwaysAutoResize,
			ig.ImGuiWindowFlags_Modal
		))
		if #app.nextColors > 1 then
			if ig.igButton'Delete Color' then
				app.nextColors:remove(self.currentColorEditing)
				app.numColors = app.numColors - 1
				self.currentColorEditing = nil
			end
		end
		if self.currentColorEditing then
			ig.igColorPicker3('Edit Color', app.nextColors[self.currentColorEditing].s, 0)
		end
		if ig.igButton'Done' then
			self.currentColorEditing = nil
		end
		ig.igEnd()
	end

	self:centerText'Board:'
	self:centerLuatableTooltipInputInt('Board Width', app.nextSandSize, 'x')
	self:centerLuatableTooltipInputInt('Board Height', app.nextSandSize, 'y')
	self:centerLuatableTooltipSliderFloat('Topple Chance', app.cfg, 'toppleChance', 0, 1)

	if app.useAudio then
		self:centerText'Audio:'
		if self:centerLuatableSliderFloat('FX Volume', app.cfg, 'effectVolume', 0, 1) then
			--[[ if you want, update all previous audio sources...
			for _,src in ipairs(app.audioSources) do
				-- TODO if the gameplay sets the gain down then we'll want to multiply by their default gain
				src:setGain(app.cfg.effectVolume * src.gain)
			end
			--]]
		end
		if self:centerLuatableSliderFloat('BG Volume', app.cfg, 'backgroundVolume', 0, 1) then
			app.bgAudioSource:setGain(app.cfg.backgroundVolume)
		end
	end


	if self:centerButton'Done' then
		app:saveConfig()
		app.state = GameState.MainMenuState(app)
	end
	self:endFullView()
end

local StartNewGameState = class(GameState)
function StartNewGameState:init(app, multiplayer)
	StartNewGameState.super.init(self, app)
	self.multiplayer = multiplayer
	if multiplayer then
		app.numPlayers = math.max(app.numPlayers, 2)
	else
		app.numPlayers = 1
	end
end
function StartNewGameState:updateGUI()
	local app = self.app

	self:beginFullView(self.multiplayer and 'New Game Multiplayer' or 'New Game', 3 * 32)

	if self.multiplayer then
		self:centerText'Number of Players:'
		self:centerLuatableTooltipInputInt('Number of Players', app, 'numPlayers')
		app.numPlayers = math.max(app.numPlayers, 2)
	end

	self:centerText'Level:'
	self:centerLuatableTooltipInputInt('Level', app.cfg, 'startLevel')
	app.cfg.startLevel = math.clamp(app.cfg.startLevel, 1, 20)

	if self:centerButton'Back' then
		app.state = GameState.MainMenuState(app)
	end
	--ig.igSameLine() -- how to work with centered multiple widgets...
	if self:centerButton'Go!' then
		app:reset()
		app.state = PlayingState(app)	-- sets paused=false
	end

	self:endFullView()
end


local MainMenuState = class(GameState)
GameState.MainMenuState = MainMenuState
function MainMenuState:init(...)
	MainMenuState.super.init(self, ...)
	self.app.paused = true
end
function MainMenuState:updateGUI()
	local app = self.app
	self:beginFullView('Main Menu', 6 * 32)

	if self:centerButton'New Game' then
		-- TODO choose gametype and choose level
		app.state = StartNewGameState(app)
	end
	if self:centerButton'New Game Co-op' then
		app.state = StartNewGameState(app, true)
		-- TODO pick same as before except pick # of players
	end
	-- TODO RESUME GAME here
	if self:centerButton'Config' then
		app.state = ConfigState(app)
	end
	if self:centerButton'High Scores' then
		app.state = GameState.HighScoreState(app)
	end
	local url = 'https://github.com/thenumbernine/sand-tetris'
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

local SplashScreenState = class(GameState)
GameState.SplashScreenState = SplashScreenState
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
	local s = w / h

	app.projMat:setOrtho(-.5 * aspectRatio, .5 * aspectRatio, -.5, .5, -1, 1)
	app.displayShader:use()
	app.displayShader.vao:use()

	app.mvMat
		:setTranslate(-.5 * s, -.5)
		:applyScale(s, 1)
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(app.displayShader.uniforms.modelViewProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)

	gl.glEnable(gl.GL_ALPHA_TEST)
	app.splashTex:bind()
	gl.glDrawArrays(gl.GL_QUADS, 0, 4)
	gl.glDisable(gl.GL_ALPHA_TEST)

	app.displayShader.vao:useNone()
	GLTex2D:unbind()
	app.displayShader:useNone()


	if getTime() - self.startTime > self.duration then
		app.state = MainMenuState(app)
	end
end
function SplashScreenState:event(e)
	local app = self.app
	if e.type == sdl.SDL_KEYDOWN
	or e.type == sdl.SDL_MOUSEBUTTONDOWN
	or e.type == sdl.SDL_JOYBUTTONDOWN
	then
		app.state = MainMenuState(app)
	end
end

local HighScoreState = class(GameState)
GameState.HighScoreState = HighScoreState
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
	'toppleCoeff',
	'boardWidth',
	'boardHeight',
}
function HighScoreState:updateGUI()
	local app = self.app
	self:beginFullView'High Scores:'

	-- TODO separate state for this?
	if self.needsName then
		ig.luatableInputText('Your Name:', self, 'name')
		if ig.igButton'Ok' then
			self.needsName = false
			local record = {}
			for _,field in ipairs(self.fields) do
				if field == 'name' then
					record[field] = self[field]
				elseif field == 'toppleCoeff' then
					record[field] = app.cfg[field]
				elseif field == 'boardWidth' then
					record[field] = tonumber(app.sandSize.x)
				elseif field == 'boardHeight' then
					record[field] = tonumber(app.sandSize.y)
				else
					record[field] = app[field]
				end
			end
			table.insert(app.cfg.highscores, record)
			table.sort(app.cfg.highscores, function(a,b)
				return a.score > b.score
			end)
			app:saveConfig()
		end
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
		if not self.rowindexes or #self.rowindexes ~= #app.cfg.highscores then
			self.rowindexes = range(#app.cfg.highscores)
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
				local a = app.cfg.highscores[ia]
				local b = app.cfg.highscores[ib]
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
			local score = app.cfg.highscores[i]
			ig.igTableNextRow(0, 0)
			for _,field in ipairs(self.fields) do
				ig.igTableNextColumn()
				ig.igText(tostring(score[field]))
			end
		end
		ig.igEndTable()
	end
	if ig.igButton'Clear' then
		app.cfg.highscores = {}
		app:saveConfig()
	end
	ig.igSameLine()
	if ig.igButton'Done' then
		app.state = MainMenuState(app)
	end
	self:endFullView()
end

return GameState
