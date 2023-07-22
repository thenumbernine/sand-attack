#!/usr/bin/env luajit

-- hack require packages first:

-- TODO this variable is half hardwired into lua-gl and luajit-ffi-bindings projects ... I don't like how it is set up
--ffi_OpenGL = nil	-- for desktop GL
--ffi_OpenGL = 'ffi.OpenGLES1'	-- for GLES1 ... but GLES1 has no shaders afaik?
--ffi_OpenGL = 'ffi.OpenGLES2'	-- for GLES2
ffi_OpenGL = 'ffi.OpenGLES3'	-- for GLES3
local gl = require 'gl'

local matrix = require 'matrix.ffi'
matrix.real = 'float'

-- then load app

local App = require 'sandtetris.app'

-- then run app

local app = App()
app.gl = gl	-- tell app to use a dif gl (in case i'm using a dif gl)
return app:run()
