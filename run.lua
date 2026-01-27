#!/usr/bin/env luajit

local cmdline = require 'ext.cmdline'(...)

--[[ specify GL version first:
require 'gl.setup'()	-- for desktop GL.  Windows needs this.
--require 'gl.setup' 'OpenGLES1'	-- for GLES1 ... but GLES1 has no shaders afaik?
--require 'gl.setup' 'OpenGLES2'	-- for GLES2
--require 'gl.setup' 'OpenGLES3'	-- for GLES3.  Linux or Raspberry Pi can handle this.
--]]
-- [[ pick gl vs gles based on OS (Linux has GLES and includes embedded)
local glfn = nil	-- default gl
local ffi = require 'ffi'
if ffi.os == 'Linux' then
	glfn = 'OpenGLES3'	-- linux / raspi (which is also classified under ffi.os == 'Linux') can use GLES3
end
if cmdline.gl ~= nil then	-- allow cmdline override
	glfn = cmdline.gl
end
require 'gl.setup'(glfn)
--]]
-- [[ sdl too
if cmdline.sdl == 2 then
	-- TODO right now imgui/ffi/imgui.lua lib loads cimgui_sdl3 ...
	-- but if we're asking for sdl2 then ...
	-- ... then for desktop I'm going to want to override that ffi.load
	-- ... or, for Browser, well, honestly, this is the default behavior for browser until I can get emscripten to run on my system again since the apt is broken and the git repo is bigger than the free space on my harddrive (smh why?)
	-- so in that case, override ffi.load for cimgui_sdl3
	require 'ffi.load'.cimgui_sdl3 = 'cimgui_sdl2'
end
require 'sdl.setup'(cmdline.sdl or '3')
--]]

if not pcall(require, 'socket') then
	print("WARNING: can't find luasocket -- you won't be able to submit highscores")
end

local App = require 'sand-attack.app'
App.cfgfilename = cmdline.config or App.cfgfilename
App.skipCustomFont = cmdline.skipCustomFont
if cmdline.skipHighScores then App.highScorePath = nil end
if cmdline.nosound then App.useAudio = nil end
if cmdline.nodemo then App.disableSplashDemo = true end
return App():run()
