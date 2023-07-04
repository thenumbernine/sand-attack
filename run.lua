#!/usr/bin/env luajit
local ffi = require 'ffi'
local table = require 'ext.table'
local string = require 'ext.string'
local template = require 'template'
local gl = require 'gl'
local sdl = require 'ffi.sdl'
local Image = require 'image'
local GLTex2D = require 'gl.tex2d'
local GLProgram  = require 'gl.program'
local glreport = require 'gl.report'
local vec2i = require 'vec-ffi.vec2i'
local getTime = require 'ext.timer'.getTime
local App = require 'imguiapp.withorbit'()
	
local pieceSize = vec2i(40,40)

App.title = 'Sand Tetris'

function App:initGL(...)
	App.super.initGL(self, ...)

	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

	math.randomseed(os.time())

	self.view.ortho = true
	self.view.orthoSize = .5
	self.view.orbit:set(.5, .5, 0)
	self.view.pos:set(.5, .5, 10)

	-- board size is 80 x 144 visible
	-- piece is 4 blocks arranged
	-- blocks are 8 x 8

	self.sandSize = vec2i(80, 144)
	self.sandVolume = tonumber(self.sandSize.x * self.sandSize.y)
	self.sandCPU = ffi.new('int[?]', self.sandVolume)
	self.sandTex = GLTex2D{
		internalFormat = gl.GL_RGBA,
		width = tonumber(self.sandSize.x),
		height = tonumber(self.sandSize.y),
		format = gl.GL_RGBA,
		type = gl.GL_UNSIGNED_BYTE,
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,
	}

	self.pieceTex = GLTex2D{
		internalFormat = gl.GL_RGBA,
		width = tonumber(pieceSize.x),
		height = tonumber(pieceSize.y),
		format = gl.GL_RGBA,
		type = gl.GL_UNSIGNED_BYTE,
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,
	}
	self.pieceImage = Image(pieceSize.x, pieceSize.y, 4, 'unsigned char')
	
	self:reset()
	
	glreport'here'
end

local function makePieceImage(s)
	s = string.split(s, '\n')
	local img = Image(pieceSize.x, pieceSize.y, 4, 'unsigned char')
	ffi.fill(img.buffer, 4 * img.width * img.height)
	for j=0,3 do
		for i=0,3 do
			if s[j+1]:sub(i+1,i+1) == '#' then
				for u=0,7 do
					for v=0,7 do
						ffi.cast('int*', img.buffer)[(u + 8 * i) + img.width * (v + 8 * j)] = -1
					end
				end
			end
		end
	end
	return img
end

local pieceImages = table{
	makePieceImage[[
 #
 #
 #
 #
]],
	makePieceImage[[
 #
 #
 ##

]],
	makePieceImage[[
   #
   #
  ##

]],
	makePieceImage[[

 ##
 ##

]],
	makePieceImage[[

 #
###

]],
	makePieceImage[[
 #
 ##
  #

]],
	makePieceImage[[
  #
 ##
 #

]],
}

local colors = table{
	0xff0000,
	0x00ff00,
	0xffff00,
	0x0000ff,
}

function App:reset()
	local w, h = self.sandSize:unpack()
	ffi.fill(self.sandCPU, ffi.sizeof'int' * w * h)
	self.sandTex
		:bind()
		:subimage{data=self.sandCPU}	--a case for saving .data ? like I do with gl buffers?
		:unbind()

	self:newPiece()
	
	self.lastUpdateTime = getTime()
end

function App:newPiece()
	local w, h = self.sandSize:unpack()
	local srcimage = pieceImages:pickRandom()
	--[[
	ffi.copy(self.pieceImage.buffer, srcimage.buffer, pieceSize.x*pieceSize.y*4)
	--]]
	-- [[
	local srcp = ffi.cast('uint32_t*', srcimage.buffer)
	local dstp = ffi.cast('uint32_t*', self.pieceImage.buffer)
	for j=0,pieceSize.y-1 do
		for i=0,pieceSize.x-1 do
			local k = i + pieceSize.x * j
			if srcp[0] ~= 0 then
				dstp[0] = math.random(0,16777215)
			else
				dstp[0] = math.random(0,16777215)
			end
			dstp[0] = bit.bor(dstp[0], 0xff000000)
			srcp = srcp + 1
			dstp = dstp + 1
		end
	end
	--]]
	self:updatePieceTex()
	self.piecePos = vec2i(bit.rshift(w,1), h-1)
	self.pieceColor = colors:pickRandom()	
	if self:testPieceMerge() then
		print("YOU LOSE!!!")
	end
end

function App:updatePieceTex()
	self.pieceTex:bind()
		:subimage{data=self.pieceImage.buffer}
end

function App:rotatePiece()
	if not self.pieceImage then return end
	local newshape = ''
	self.pieceImage2 = self.pieceImage2 or (self.pieceImage + 0)
	for j=0,pieceSize.x-1 do
		for i=0,pieceSize.y-1 do
			for ch=0,3 do
				self.pieceImage2.buffer[ch + 4 * (i + pieceSize.x * j)] = self.pieceImage.buffer[ch + 4 * ((pieceSize.x - 1 - j) + pieceSize.x * i)]
			end
		end
	end
	self.pieceImage, self.pieceImage2 = self.pieceImage2, self.pieceImage
	self:updatePieceTex()
end


local vtxs = {
	{0,0},
	{1,0},
	{1,1},
	{0,1},
}

local updateInterval = 1/60
--local updateInterval = 0

function App:testPieceMerge()
	local w, h = self.sandSize:unpack()
	for j=0,pieceSize.y-1 do
		for i=0,pieceSize.x-1 do
			local k = i + pieceSize.x * j
			local color = ffi.cast('int*', self.pieceImage.buffer)[k]
			if color ~= 0 then
				local x = self.piecePos.x + i
				local y = self.piecePos.y + j
				if x >= 0 and x < w
				and y >= 0 and y < h
				and self.sandCPU[x + w * y] ~= 0
				then
					return true
				end
			end
		end
	end
end

function App:updateGame()
	local w, h = self.sandSize:unpack()
	local thisTime = getTime()
	local dt = thisTime - self.lastUpdateTime
	if dt <= updateInterval then return end

	self.lastUpdateTime = self.lastUpdateTime + updateInterval

	-- update
	local prow = self.sandCPU + w
	for j=1,h-1 do
		-- 50/50 cycling left-to-right vs right-to-left
		local istart, iend, istep
		if math.random(2) == 2 then
			istart,iend,istep = 0, w-1, 1
		else
			istart,iend,istep = w-1, 0, -1
		end
		local p = prow + istart
		for i=istart,iend,istep do
			-- if the cell is blank and there's a sand cell above us ... pull it down
			if p[0] ~= 0 then
				if p[-w] == 0 then
					p[0], p[-w] = p[-w], p[0]
				-- hmm symmetry? check left vs right first?
				else
					-- 50/50 check left then right, vs check right then left
					if math.random(2) == 2 then
						if i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
						elseif i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
						end
					else	
						if i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
						elseif i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
						end
					end
				end
			end
			p = p + istep
		end
		prow = prow + w
	end

	-- now draw the shape over the sand
	-- test piece for collision with sand
	-- if it collides then merge it
	local merge
	self.piecePos.y = self.piecePos.y - 1
	-- TODO key updates at higher interval than drop rate ...
	-- but test collision for both
	if self.leftPress then
		self.piecePos.x = self.piecePos.x - 1
		-- TODO check blit and don't move if any pixels are oob
		if self.piecePos.x < 0 then self.piecePos.x = 0 end
	end
	if self.rightPress then 
		self.piecePos.x = self.piecePos.x + 1 
		if self.piecePos.x > w-pieceSize.x-1 then self.piecePos.x = w-pieceSize.x-1 end
	end
	if self.downPress then self.piecePos.y = self.piecePos.y - 1 end
	if self.piecePos.y <= 0 then
		self.piecePos.y = 0
		merge = true
	else
		merge = self:testPieceMerge()
	end
	if merge then
		for j=0,pieceSize.y-1 do
			for i=0,pieceSize.x-1 do
				local k =  i + pieceSize.x * j
				local color = ffi.cast('int*', self.pieceImage.buffer)[k]
				if color ~= 0 then
					local x = self.piecePos.x + i
					local y = self.piecePos.y + j
					if x >= 0 and x < w
					and y >= 0 and y < h
					and self.sandCPU[x + w * y] == 0
					then
						self.sandCPU[x + w * y] = color
					end
				end
			end
		end
	
		self:newPiece()
	end
end

function App:update(...)
	local t = 
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)
	
	local w, h = self.sandSize:unpack()

	self:updateGame()

	--[[ pouring sand
	self.sandCPU[bit.rshift(w,1) + w * (h - 1)] = bit.bor(
		math.random(0,255),
		bit.lshift(math.random(0,255),8),
		bit.lshift(math.random(0,255),16)
	)
	--]]

	-- draw
	self.view:setup(self.width / self.height)
	
	GLTex2D:enable()

	self.sandTex
		:bind()
		:subimage{data=self.sandCPU}
	local s = w / h
	gl.glBegin(gl.GL_QUADS)
	for _,v in ipairs(vtxs) do
		local x,y = table.unpack(v)
		gl.glTexCoord2f(x,y)
		gl.glVertex2f((x - .5) * s + .5, y)
	end
	gl.glEnd()	
	self.sandTex
		:unbind()

	-- draw the current piece
	if self.pieceImage then
		self.pieceTex:bind()
		gl.glEnable(gl.GL_BLEND)
		gl.glBegin(gl.GL_QUADS)
		for _,v in ipairs(vtxs) do
			local x,y = table.unpack(v)
			gl.glTexCoord2f(x,y)
			gl.glVertex2f(
				((self.piecePos.x + x * pieceSize.x) / w - .5) * s + .5,
				(self.piecePos.y + y * pieceSize.y) / h
			)
		end
		gl.glEnd()
		gl.glDisable(gl.GL_BLEND)
		self.pieceTex:unbind()
		gl.glColor3f(1,1,1)
	end

	GLTex2D:disable()

	App.super.update(self, ...)
	glreport'here'
end

function App:event(e)
	if e.type == sdl.SDL_KEYDOWN 
	or e.type == sdl.SDL_KEYUP
	then
		local down = e.type == sdl.SDL_KEYDOWN
		if e.key.keysym.sym == sdl.SDLK_LEFT then
			self.leftPress = down 
		elseif e.key.keysym.sym == sdl.SDLK_RIGHT then
			self.rightPress = down
		elseif e.key.keysym.sym == sdl.SDLK_DOWN then
			self.downPress = down
		elseif e.key.keysym.sym == sdl.SDLK_UP then
			if down then self:rotatePiece() end
		elseif e.key.keysym.sym == ('r'):byte() then
			if down then self:reset() end
		end
	end
end

return App():run()
