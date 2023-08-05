local ig = require 'imgui'
local Menu = require 'sand-attack.menu.menu'

local PlayingMenu = Menu:subclass()

function PlayingMenu:init(app)
	PlayingMenu.super.init(self, app)
	app.paused = false
end

function PlayingMenu:update()
	self.app:drawTouchRegions()
end

function PlayingMenu:updateGUI()
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

	-- if esc / pause-key was pushed ...
	if app.paused then
        local size = ig.igGetMainViewport().WorkSize
        ig.igSetNextWindowPos(ig.ImVec2(size.x/2, size.y/2), ig.ImGuiCond_Appearing, ig.ImVec2(.5, .5));
		ig.igBegin'Paused'
		if ig.igButton(app.paused and 'Resume' or 'Pause') then
			app.paused = not app.paused
		end
		if ig.igButton'Config' then
			app.pushMenuState = app.menustate
			local ConfigMenu = require 'sand-attack.menu.config'
			app.menustate = ConfigMenu(app)
		end
		if ig.igButton'End Game' then
			app:endGame()
		end
		ig.igEnd()
	end
end

return PlayingMenu
