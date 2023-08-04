local ffi = require 'ffi'
local ig = require 'imgui'
local MenuState = require 'sand-attack.menustate.menustate'

local MainMenuState = MenuState:subclass()

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
		local NewGameState = require 'sand-attack.menustate.newgame'
		app.menustate = NewGameState(app)
	end
	if self:centerButton'New Game Co-op' then
		local NewGameState = require 'sand-attack.menustate.newgame'
		app.menustate = NewGameState(app, true)
		-- TODO pick same as before except pick # of players
	end
	-- TODO RESUME GAME here
	if self:centerButton'Config' then
		-- pushMenuState only used for entering config menu
		-- if I need any more 'back' options than this then i'll turn the menustate into a stack
		app.pushMenuState = app.menustate
		local ConfigState = require 'sand-attack.menustate.config'
		app.menustate = ConfigState(app)
	end
	if self:centerButton'High Scores' then
		local HighScoreState = require 'sand-attack.menustate.highscore'
		app.menustate = HighScoreState(app)
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

return MainMenuState 
