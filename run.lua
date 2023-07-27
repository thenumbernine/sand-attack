#!/usr/bin/env luajit

-- specify GL version first:
local gl = require 'gl.setup'()	-- for desktop GL
--local gl = require 'gl.setup' 'ffi.OpenGLES1'	-- for GLES1 ... but GLES1 has no shaders afaik?
--local gl = require 'gl.setup' 'ffi.OpenGLES2'	-- for GLES2
--local gl = require 'gl.setup' 'ffi.OpenGLES3'	-- for GLES3

return require 'sandtetris.app'():run()
