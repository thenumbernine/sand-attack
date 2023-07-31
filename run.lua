#!/usr/bin/env luajit

--[[ specify GL version first:
require 'gl.setup'()	-- for desktop GL.  Windows needs this.
--require 'gl.setup' 'OpenGLES1'	-- for GLES1 ... but GLES1 has no shaders afaik?
--require 'gl.setup' 'OpenGLES2'	-- for GLES2
--require 'gl.setup' 'OpenGLES3'	-- for GLES3.  Linux or Raspberry Pi can handle this.
--]]
-- [[ or detect
local glfn = nil	-- default gl
local ffi = require 'ffi'
if ffi.os == 'Linux' then
	glfn = 'OpenGLES3'	-- linux / raspi (also linux) can use GLES3
end
require 'gl.setup'(glfn)
--]]

return require 'sand-attack.app'():run()
