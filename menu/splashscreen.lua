local getTime = require 'ext.timer'.getTime
local sdl = require 'sdl'
local ig = require 'imgui'
local gl = require 'gl'
local Menu = require 'sand-attack.menu.menu'

local SplashScreenMenu = Menu:subclass()

SplashScreenMenu.duration = 3

-- TODO cool sand effect or something
function SplashScreenMenu:init(app, ...)
	SplashScreenMenu.super.init(self, app, ...)
	self.startTime = getTime()
	app.paused = true
end

function SplashScreenMenu:update()
	local app = self.app

	local w, h = app.sandSize:unpack()

	local aspectRatio = app.width / app.height
	
	app.projMat:setOrtho(-.5 * aspectRatio, .5 * aspectRatio, -.5, .5, -1, 1)
	app.mvMat
		:setTranslate(-.5 * aspectRatio, -.5)
		:applyScale(aspectRatio, 1)
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	
	local sceneObj = app.splashScreenSceneObj
	sceneObj.uniforms.mvProjMat = app.mvProjMat.ptr
	sceneObj.uniforms.useAlphaTest = 1
	sceneObj:draw()

	if getTime() - self.startTime > self.duration then
		self:endSplashScreen()
	end
end

function SplashScreenMenu:event(e)
	local app = self.app
	if e[0].type == sdl.SDL_EVENT_JOYSTICK_HAT_MOTION
	or e[0].type == sdl.SDL_EVENT_JOYSTICK_AXIS_MOTION
	or e[0].type == sdl.SDL_EVENT_JOYSTICK_BUTTON_DOWN
	or e[0].type == sdl.SDL_EVENT_GAMEPAD_AXIS_MOTION
	or e[0].type == sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN
	or e[0].type == sdl.SDL_EVENT_KEY_DOWN
	or e[0].type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN
	or e[0].type == sdl.SDL_EVENT_FINGER_DOWN
	then
		self:endSplashScreen()
	end
end

function SplashScreenMenu:endSplashScreen()
	local app = self.app
	local MainMenu = require 'sand-attack.menu.main'
	-- play the demo
	app.paused = false
	app.menustate = MainMenu(app)
end

return SplashScreenMenu
