#!/usr/bin/env luajit
local ffi = require 'ffi'
local template = require 'template'
local table = require 'ext.table'
local math = require 'ext.math'
local string = require 'ext.string'
local range = require 'ext.range'
local gl = require 'gl'
local sdl = require 'ffi.sdl'
local Image = require 'image'
local GLTex2D = require 'gl.tex2d'
local GLProgram  = require 'gl.program'
local glreport = require 'gl.report'
local vec2i = require 'vec-ffi.vec2i'
local vec3f = require 'vec-ffi.vec3f'
local getTime = require 'ext.timer'.getTime
local App = require 'imguiapp.withorbit'()

-- board size is 80 x 144 visible
-- piece is 4 blocks arranged
-- blocks are 8 x 8
local voxelsPerBlock = 8	-- original
--local voxelsPerBlock = 16
local pieceSizeInBlocks = vec2i(4,4)
local pieceSize = pieceSizeInBlocks * voxelsPerBlock

local updateInterval = 1/60
--local updateInterval = 1/120
--local updateInterval = 0

local toppleChance = .5
local ticksToFall = 5

App.title = 'Sand Tetris'

function App:initGL(...)
	App.super.initGL(self, ...)

	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)

	math.randomseed(os.time())

	self.view.ortho = true
	self.view.orthoSize = .5
	self.view.orbit:set(.5, .5, 0)
	self.view.pos:set(.5, .5, 10)

	self.sandSize = vec2i(80, 144)	-- original:
	--self.sandSize = vec2i(160, 288)

	local function makeImageAndTex(size)
		local img = Image(size.x, size.y, 4, 'unsigned char')
		ffi.fill(img.buffer, 4 * size.x * size.y)
		local tex = GLTex2D{
			internalFormat = gl.GL_RGBA,
			width = tonumber(size.x),
			height = tonumber(size.y),
			format = gl.GL_RGBA,
			type = gl.GL_UNSIGNED_BYTE,
			wrap = {
				s = gl.GL_CLAMP_TO_EDGE,
				t = gl.GL_CLAMP_TO_EDGE,
			},
			minFilter = gl.GL_NEAREST,
			magFilter = gl.GL_NEAREST,
			data = img.buffer,	-- stored
		}
		tex.image = img
		-- TODO store tex.image as img?
		return tex
	end
	
	self.sandTex, self.sandImage = makeImageAndTex(self.sandSize)
	self.flashTex, self.flashImage = makeImageAndTex(self.sandSize)
	self.pieceTex, self.pieceImage = makeImageAndTex(pieceSize)
	self.rotPieceTex, self.rotPieceImage = makeImageAndTex(pieceSize)
	self.nextPieces = range(3):mapi(function(i)
		local tex = makeImageAndTex(pieceSize)
		return {tex=tex}
	end)

	self:reset()
	
	glreport'here'
end

local function makePieceImage(s)
	s = string.split(s, '\n')
	local img = Image(pieceSize.x, pieceSize.y, 4, 'unsigned char')
	ffi.fill(img.buffer, 4 * img.width * img.height)
	for j=0,pieceSizeInBlocks.y-1 do
		for i=0,pieceSizeInBlocks.x-1 do
			if s[j+1]:sub(i+1,i+1) == '#' then
				for u=0,voxelsPerBlock-1 do
					for v=0,voxelsPerBlock-1 do
						ffi.cast('int*', img.buffer)[(u + voxelsPerBlock * i) + img.width * (v + voxelsPerBlock * j)] = -1
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
	vec3f(1,0,0),
	vec3f(1,1,0),
	vec3f(0,1,0),
	vec3f(0,0,1),
}

function App:reset()
	local w, h = self.sandSize:unpack()
	ffi.fill(self.sandTex.image.buffer, 4 * w * h)
	assert(self.sandTex.data == self.sandTex.image.buffer)
	self.sandTex:bind():subimage():unbind()

	self:newPiece()
	for i=1,#self.nextPieces do
		self:newPiece()
	end

	self.lastUpdateTime = getTime()
	self.gameTime = 0
	self.flashTime = -math.huge
end

function App:populatePiece(args)
	local srcimage = pieceImages:pickRandom()
	local color = colors:pickRandom()	
	local srcp = ffi.cast('uint32_t*', srcimage.buffer)
	local dstp = ffi.cast('uint32_t*', args.tex.image.buffer)
	for j=0,pieceSize.y-1 do
		for i=0,pieceSize.x-1 do
			local k = i + pieceSize.x * j
			if srcp[0] ~= 0 then
				local l = math.random() * .5 + .5
				dstp[0] = bit.bor(
					math.floor(l * color.x * 255),
					bit.lshift(math.floor(l * color.y * 255), 8),
					bit.lshift(math.floor(l * color.z * 255), 16),
					0xff000000
				)
			else
				dstp[0] = 0
			end
			srcp = srcp + 1
			dstp = dstp + 1
		end
	end
	args.tex:bind():subimage()
end

function App:newPiece()
	local w, h = self.sandSize:unpack()

	local lastPiece = self.nextPieces:last()
	-- cycle pieces
	do
		local tex = self.pieceTex
		local np1 = self.nextPieces[1]
		self.pieceTex = np1.tex
		for i=1,#self.nextPieces-1 do
			local np = self.nextPieces[i]
			local np2 = self.nextPieces[i+1]
			np.tex = np2.tex
		end
		lastPiece.tex = tex
	end
	App:populatePiece(lastPiece)

	--]]
	self:updatePieceTex()
	self.piecePos = vec2i(bit.rshift(w-pieceSize.x,1), h-1)
	if self:testPieceMerge() then
		print("YOU LOSE!!!")
	end
	self.fallTick = 0 
end

function App:updatePieceTex()
	-- while we're here, find the first and last cols with content
	for _,info in ipairs{
		{0,pieceSize.x-1,1, 'pieceColMin'},
		{pieceSize.x-1,0,-1, 'pieceColMax'},
	} do
		local istart, iend, istep, ifield = table.unpack(info)
		for i=istart,iend,istep do
			local found
			for j=0,pieceSize.y-1 do
				if ffi.cast('int*', self.pieceTex.image.buffer)[i + pieceSize.x * j] ~= 0 then
					found = true
					break
				end
			end
			if found then
				self[ifield] = i
				break
			end
		end
	end
	self.pieceTex:bind():subimage()
end

function App:rotatePiece()
	if not self.pieceTex then return end
	for j=0,pieceSize.x-1 do
		for i=0,pieceSize.y-1 do
			for ch=0,3 do
				self.rotPieceTex.image.buffer[ch + 4 * (i + pieceSize.x * j)] 
				= self.pieceTex.image.buffer[ch + 4 * ((pieceSize.x - 1 - j) + pieceSize.x * i)]
			end
		end
	end
	self.pieceTex, self.rotPieceTex = self.rotPieceTex, self.pieceTex
	self:updatePieceTex()
	self:constrainPiecePos()
end

function App:constrainPiecePos()
	-- TODO check blit and don't move if any pixels are oob
	local w, h = self.sandSize:unpack()
	if self.piecePos.x < -self.pieceColMin then self.piecePos.x = -self.pieceColMin end
	if self.piecePos.x > w-1-self.pieceColMax then
		self.piecePos.x = w-1-self.pieceColMax
	end
end

local vtxs = {
	{0,0},
	{1,0},
	{1,1},
	{0,1},
}

function App:testPieceMerge()
	local w, h = self.sandSize:unpack()
	for j=0,pieceSize.y-1 do
		for i=0,pieceSize.x-1 do
			local k = i + pieceSize.x * j
			local color = ffi.cast('int*', self.pieceTex.image.buffer)[k]
			if color ~= 0 then
				local x = self.piecePos.x + i
				local y = self.piecePos.y + j
				if x >= 0 and x < w
				and y >= 0 and y < h
				and ffi.cast('int*',self.sandTex.image.buffer)[x + w * y] ~= 0
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
	self.gameTime = self.gameTime + updateInterval

	-- update
	local prow = ffi.cast('int*', self.sandTex.image.buffer) + w
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
				elseif math.random() < toppleChance then
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
	local movedx = 1
	local movedy = 3
	-- TODO key updates at higher interval than drop rate ...
	-- but test collision for both
	if self.leftPress then
		self.piecePos.x = self.piecePos.x - movedx
	end
	if self.rightPress then 
		self.piecePos.x = self.piecePos.x + movedx 
	end
	self:constrainPiecePos()
	if self.downPress then self.piecePos.y = self.piecePos.y - movedy end
	
	self.fallTick = self.fallTick + 1
	if self.fallTick >= ticksToFall then
		self.fallTick = 0
		self.piecePos.y = self.piecePos.y - movedx
	end

	local merge
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
				local color = ffi.cast('int*', self.pieceTex.image.buffer)[k]
				if color ~= 0 then
					local x = self.piecePos.x + i
					local y = self.piecePos.y + j
					if x >= 0 and x < w
					and y >= 0 and y < h
					and ffi.cast('int*', self.sandTex.image.buffer)[x + w * y] == 0
					then
						ffi.cast('int*', self.sandTex.image.buffer)[x + w * y] = color
					end
				end
			end
		end
	
		self:newPiece()
	end

	--[[ now ... try to find a connection from left to right
	local function checkNextCol(i, jmin, jmax, color)
	
	end
	local j = 0
	while j < h-1 do
		local color = self.sandCPU[0 + w * j]
		if color ~= 0 then
			-- this is the start of our color interval
			local jmin = j
			-- find the end of i
			repeat
				j = j + 1
			until j >= h or self.sandCPU[0 + w * j] ~= color
			local jmax = j - 1
			if checkNextCol(1, jmin, jmax, color) then
			end
		end
	end
	--]]

	-- TOOD do this faster. This is the lazy way ...
	local anyCleared
	for _,color in ipairs(colors) do
		local clearedCount = 0
		local r = color.x
		local g = color.y
		local b = color.z
		local blobs = self.sandTex.image:getBlobs(function(p)
			return p[3] == 0xff
			and (p[0] == 0) == (r == 0)
			and (p[1] == 0) == (g == 0)
			and (p[2] == 0) == (b == 0)
		end)
		for _,blob in ipairs(blobs) do
			local xmin = math.huge
			local xmax = -math.huge
			for _,int in ipairs(blob) do
				xmin = math.min(xmin, int.x1)
				xmax = math.max(xmax, int.x2)
			end
			local blobwidth = xmax - xmin + 1
			if blobwidth == w then
				print("GOT", color)
				for _,int in ipairs(blob) do
					local iw = int.x2 - int.x1 + 1
					clearedCount = clearedCount + iw
					ffi.fill(self.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
					for k=0,4*iw-1 do
						self.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
					end
				end
			end
		end
		if clearedCount ~= 0 then
			anyCleared = true
			print('cleared', clearedCount, color)
		end
	end
	if anyCleared then
		self.flashTex:bind():subimage()
		self.flashTime = self.gameTime
	end
end

function App:update(...)
	local t = 
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)
	
	local w, h = self.sandSize:unpack()

	self:updateGame()

	--[[ pouring sand
	self.sandCPU[bit.rshift(w,1) + w * (h - 1)] = bit.bor(
		math.random(0,16777215),
		0xff000000,
	)
	--]]

	-- draw
	self.view:setup(self.width / self.height)
	
	GLTex2D:enable()

	assert(self.sandTex.data == self.sandTex.image.buffer)
	self.sandTex:bind():subimage()
	local s = w / h
	gl.glBegin(gl.GL_QUADS)
	for _,v in ipairs(vtxs) do
		local x,y = table.unpack(v)
		gl.glTexCoord2f(x,y)
		gl.glVertex2f((x - .5) * s + .5, y)
	end
	gl.glEnd()	
	self.sandTex:unbind()

	-- draw the current piece
	if self.pieceTex then
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

	-- draw flashing background if necessary
	local flashDuration = 1 
	local numFlashes = 5
	local flashDt = self.gameTime - self.flashTime
	if flashDt < flashDuration then
		self.wasFlashing = true
		gl.glEnable(gl.GL_BLEND)
		local flashInt = bit.band(math.floor(flashDt * numFlashes * 2), 1) == 0
		if flashInt then
			self.flashTex:bind()
			local s = w / h
			gl.glBegin(gl.GL_QUADS)
			for _,v in ipairs(vtxs) do
				local x,y = table.unpack(v)
				gl.glTexCoord2f(x,y)
				gl.glVertex2f((x - .5) * s + .5, y)
			end
			gl.glEnd()	
			self.flashTex:unbind()
		end
		gl.glDisable(gl.GL_BLEND)
	elseif self.wasFlashing then
		self.wasFlashing = false
		print'CLEARING FLASHING'
		ffi.fill(self.flashTex.image.buffer, 4 * w * h)
		assert(self.flashTex.data == self.flashTex.image.buffer)
		self.flashTex:bind():subimage():unbind()
	end

	local s = w / h
	for i,it in ipairs(self.nextPieces) do
		it.tex:bind()
		gl.glBegin(gl.GL_QUADS)
		for _,v in ipairs(vtxs) do
			local x,y = table.unpack(v)
			gl.glTexCoord2f(x,y)
			gl.glVertex2f(.8 + x * .1, 1 - (y + 1.1 * i) * .1)
		end
		gl.glEnd()
	end

	GLTex2D:disable()

	App.super.update(self, ...)
	glreport'here'
end

function App:flipBoard()
	local w, h = self.sandSize:unpack()
	local p1 = ffi.cast('int*', self.sandTex.image.buffer)
	local p2 = p1 + w * h - 1
	for j=0,bit.rshift(h,1)-1 do
		for i=0,w-1 do
			p1[0], p2[0] = p2[0], p1[0]
			p1 = p1 + 1
			p2 = p2 - 1
		end
	end
	self.sandTex:bind():subimage()
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
		elseif e.key.keysym.sym == ('f'):byte() then
			if down then self:flipBoard() end
		end
	end
end

return App():run()
