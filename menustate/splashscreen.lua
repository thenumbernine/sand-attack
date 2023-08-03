local getTime = require 'ext.timer'.getTime
local sdl = require 'ffi.req' 'sdl'
local ig = require 'imgui'
local gl = require 'gl'
local MenuState = require 'sand-attack.menustate.menustate'

local SplashScreenState = MenuState:subclass()

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

	app.displayShader
		:use()
		:enableAttrs()

	app.projMat:setOrtho(-.5 * aspectRatio, .5 * aspectRatio, -.5, .5, -1, 1)
	app.mvMat
		:setTranslate(-.5 * aspectRatio, -.5)
		:applyScale(aspectRatio, 1)
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(app.displayShader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)

	gl.glUniform1i(app.displayShader.uniforms.useAlphaTest.loc, 1)

	app.splashTex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

	app.splashTex:unbind()
	app.displayShader
		:disableAttrs()
		:useNone()

	if getTime() - self.startTime > self.duration then
		local MainMenuState = require 'sand-attack.menustate.main'
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
		local MainMenuState = require 'sand-attack.menustate.main'
		app.menustate = MainMenuState(app)
	end
end

return SplashScreenState
