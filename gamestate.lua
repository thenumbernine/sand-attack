local class = require 'ext.class'
local math = require 'ext.math'
local ig = require 'imgui'
local getTime = require 'ext.timer'.getTime

local showDebug = false	-- show debug info in gui

local GameState = class()
function GameState:init(app)
	local App = require 'sandtetris.app'
	assert(App:isa(app))
	self.app = assert(app)
end


local LoseScreen = class(GameState)

local PlayingState = class(GameState)
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
		app.state = GameState.MainMenuState(app)
	end
	
	ig.igEnd()
end


local ConfigState = class(GameState)
local tmpcolor = ig.ImVec4()
function ConfigState:updateGUI()
	local app = self.app
	ig.igBegin('Config', nil, 0)
	ig.luatableInputInt('Num Next Pieces', app, 'numNextPieces')
	ig.luatableInputFloat('Drop Speed', app, 'dropSpeed')

	ig.igText'Colors:'
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

	ig.igText'Board:'
	ig.luatableTooltipInputInt('Board Width', app.nextSandSize, 'x')
	ig.luatableTooltipInputInt('Board Height', app.nextSandSize, 'y')
	ig.luatableTooltipSliderFloat('Topple Chance', app, 'toppleChance', 0, 1)

	if app.useAudio then
		ig.igText'Audio:'
		if ig.luatableSliderFloat('FX Volume', app.audioConfig, 'effectVolume', 0, 1) then
			--[[ if you want, update all previous audio sources...
			for _,src in ipairs(app.audioSources) do
				-- TODO if the gameplay sets the gain down then we'll want to multiply by their default gain
				src:setGain(audioConfig.effectVolume * src.gain)
			end
			--]]
		end
		if ig.luatableSliderFloat('BG Volume', app.audioConfig, 'backgroundVolume', 0, 1) then
			app.bgAudioSource:setGain(app.audioConfig.backgroundVolume)
		end
	end


	if ig.igButton'Done' then
		app.state = GameState.MainMenuState(app)
	end
	ig.igEnd()
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

	if self.multiplayer then
		ig.igBegin('New Game Multiplayer', nil, 0)
		ig.luatableInputInt('Num Players', app, 'numPlayers')
		app.numPlayers = math.max(app.numPlayers, 2)
	else
		ig.igBegin('New Game', nil, 0)
	end

	ig.luatableInputInt('Level:', app, 'level')
	app.level = math.clamp(app.level, 1, 20)

	if ig.igButton'Back' then
		app.state = GameState.MainMenuState(app)
	end
	ig.igSameLine()
	if ig.igButton'Go!' then
		app:reset()
		app.state = PlayingState(app)	-- sets paused=false
	end
	ig.igEnd()
end

local MainMenuState = class(GameState)
GameState.MainMenuState = MainMenuState
function MainMenuState:init(...)
	MainMenuState.super.init(self, ...)
	self.app.paused = true
end
function MainMenuState:updateGUI()
	local app = self.app
	ig.igBegin('Main Menu', nil, 0)
	if ig.igButton'New Game' then
		-- TODO choose gametype and choose level
		app.state = StartNewGameState(app)
	end
	if ig.igButton'New Game Co-op' then
		app.state = StartNewGameState(app, true)
		-- TODO pick same as before except pick # of players
	end
	-- TODO RESUME GAME here
	if ig.igButton'Config' then
		-- TODO config state
		app.state = ConfigState(app)
	end
	
	local url = 'https://github.com/thenumbernine/sand-tetris'
	if ig.igButton'About' then
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

	if ig.igButton'Exit' then
		app:requestExit()
	end
	ig.igEnd()
end

local SplashScreenState = class(GameState)
GameState.SplashScreenState = SplashScreenState
SplashScreenState.duration = 0
SplashScreenState.startTime = getTime()
function SplashScreenState:update()
	local app = self.app
	-- TODO show a splash screen logo.
	if getTime() - self.startTime > self.duration then
		app.state = MainMenuState(app)
	end
end

return GameState
