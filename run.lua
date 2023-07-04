#!/usr/bin/env luajit
local ffi = require 'ffi'
local table = require 'ext.table'
local template = require 'template'
local gl = require 'gl'
local sdl = require 'ffi.sdl'
local GLTex2D = require 'gl.tex2d'
local GLProgram  = require 'gl.program'
local glreport = require 'gl.report'
local vec2i = require 'vec-ffi.vec2i'
local getTime = require 'ext.timer'.getTime
local App = require 'imguiapp.withorbit'()

App.title = 'Sand Tetris'

function App:initGL(...)
	App.super.initGL(self, ...)

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
	self:reset()

	glreport'here'
end

local pieces = table{
	'.   '..
	'.   '..
	'.   '..
	'.   ',
	
	'    '..
	'.   '..
	'.   '..
	'..  ',
	
	'    '..
	' .  '..
	' .  '..
	'..  ',
	
	'    '..
	'    '..
	'..  '..
	'..  ',
	
	'    '..
	'    '..
	' .  '..
	'... ',
	
	'    '..
	'.   '..
	'..  '..
	' .  ',
	
	'    '..
	' .  '..
	'..  '..
	'.   ',
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
	--[[
	for i=0,30 do
		self.sandCPU[bit.rshift(w,1) + w * (h - 1 - i)] = bit.bor(
			math.random(0,255),
			bit.lshift(math.random(0,255),8),
			bit.lshift(math.random(0,255),16)
		)
	end
	--]]
	self.sandTex
		:bind()
		:subimage{data=self.sandCPU}	--a case for saving .data ? like I do with gl buffers?
		:unbind()

	self:newPiece()
	
	self.lastUpdateTime = getTime()
end

function App:newPiece()
	local w, h = self.sandSize:unpack()
	self.pieceShape = pieces:pickRandom()
	self.piecePos = vec2i(bit.rshift(w,1), h-1)
	self.pieceColor = colors:pickRandom()	
	if self:testPieceMerge() then
		print("YOU LOSE!!!")
	end
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
	for i=0,3 do
		for j=0,3 do
			local k = 1 + i + 4 * j
			if self.pieceShape:sub(k,k) ~= ' ' then
				for u=0,7 do
					for v=0,7 do
						local x = self.piecePos.x+u+8*i
						local y = self.piecePos.y+v+8*j
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
		if self.piecePos.x > w-1 then self.piecePos.x = w-1 end
	end
	if self.downPress then self.piecePos.y = self.piecePos.y - 1 end
	if self.piecePos.y <= 0 then
		self.piecePos.y = 0
		merge = true
	else
		merge = self:testPieceMerge()
	end
	if merge then
		for i=0,3 do
			for j=0,3 do
				local k = 1 + i + 4 * j
				if self.pieceShape:sub(k,k) ~= ' ' then
					for u=0,7 do
						for v=0,7 do
							local x = self.piecePos.x+u+8*i
							local y = self.piecePos.y+v+8*j
							if x >= 0 and x < w
							and y >= 0 and y < h
							and self.sandCPU[x + w * y] == 0
							then
								self.sandCPU[x + w * y] = self.pieceColor
							end
						end
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

	self.sandTex
		:bind()
		:subimage{data=self.sandCPU}
		:enable()
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
		:disable()

	-- draw the current piece
	if self.pieceShape then
		gl.glColor3f(
			bit.band(self.pieceColor, 0xff)/0xff,
			bit.band(bit.rshift(self.pieceColor,8), 0xff)/0xff,
			bit.band(bit.rshift(self.pieceColor,16), 0xff)/0xff
		)
		gl.glBegin(gl.GL_QUADS)
		for i=0,3 do
			for j=0,3 do
				local k = 1 + i + 4 * j
				if self.pieceShape:sub(k,k) ~= ' ' then
					for _,v in ipairs(vtxs) do
						local x,y = table.unpack(v)
						gl.glVertex2f(
							((self.piecePos.x + (i + x) * 8) / w - .5) * s + .5,
							(self.piecePos.y + (j + y) * 8) / h
						)
					end
				end
			end
		end
		gl.glEnd()
		gl.glColor3f(1,1,1)
	end

	App.super.update(self, ...)
	glreport'here'
end

function App:rotatePiece()
	if not self.pieceShape then return end
	local newshape = ''
	for j=0,3 do
		for i=0,3 do
			local k = 1 + (3 - j) + 4 * i
			newshape = newshape .. self.pieceShape:sub(k,k)
		end
	end
	self.pieceShape = newshape
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
		end
	end
end

return App():run()
