local ffi = require 'ffi'
local path = require 'ext.path'
local ig = require 'imgui'
local Menu = require 'sand-attack.menu.menu'


local MainMenu = Menu:subclass()

function MainMenu:init(app, ...)
	MainMenu.super.init(self, app, ...)
	app.paused = false
	-- play a demo in the background ...
	-- and merge in splash-screen with the first demo's game start
end

function MainMenu:updateGUI()
	local app = self.app
	self:beginFullView('Sand Attack', 6 * 32)

	if self:centerButton'New Game' then
		-- TODO choose gametype and choose level
		local NewGameMenu = require 'sand-attack.menu.newgame'
		app.menustate = NewGameMenu(app)
	end
	if self:centerButton'New Game Co-op' then
		local NewGameMenu = require 'sand-attack.menu.newgame'
		app.menustate = NewGameMenu(app, true)
		-- TODO pick same as before except pick # of players
	end
	-- TODO RESUME GAME here
	if self:centerButton'Config' then
		-- pushMenuState only used for entering config menu
		-- if I need any more 'back' options than this then i'll turn the menustate into a stack
		app.pushMenuState = app.menustate
		local ConfigMenu = require 'sand-attack.menu.config'
		app.menustate = ConfigMenu(app)
	end
	if self:centerButton'High Scores' then
		local HighScoreMenu = require 'sand-attack.menu.highscore'
		app.menustate = HighScoreMenu(app)
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

return MainMenu
