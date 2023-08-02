local ffi = require 'ffi'
local math = require 'ext.math'
local class = require 'ext.class'
local table = require 'ext.table'
local vec4ub = require 'vec-ffi.vec4ub'
local vec2f = require 'vec-ffi.vec2f'
local Image = require 'image'


local SandModel = class()

-- for cpu driven sandTex
-- this flag means we need to copy from sandTex.image to sandTex
-- used to aggregate some changes during App:updateGame
SandModel.sandImageDirty = false

function SandModel:init(app)
	self.app = assert(app)

	self.sandTex = app:makeTexWithBlankImage(app.sandSize)
		:unbind()

	-- FBO the size of the sand texture
	self.fbo = require 'gl.fbo'{width=w, height=h}
		:unbind()

	--[[
	image's getBlobs is a mess... straighten it out
	should probably be a BlobGetter() class which holds the context, classify callback, results, etc.
	--]]
	self.getBlobCtx = {
		classify = function(p) return p[3] end,	-- classify by alpha channel
	}
end

function SandModel:getSandTex()
	return self.sandTex
end

-- functions all cpu-based sand models use:
function SandModel:reset()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local sandTex = self:getSandTex()
	ffi.fill(sandTex.image.buffer, 4 * w * h)
	assert(sandTex.data == sandTex.image.buffer)
	sandTex:bind():subimage():unbind()
end

function SandModel:testPieceMerge(player)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local sandTex = self:getSandTex()
	local ptr = ffi.cast('uint32_t*',sandTex.image.buffer)
	for j=0,app.pieceSize.y-1 do
		for i=0,app.pieceSize.x-1 do
			local k = i + app.pieceSize.x * j
			local color = ffi.cast('uint32_t*', player.pieceTex.image.buffer)[k]
			if color ~= 0 then
				local x = player.piecePos.x + i
				local y = player.piecePos.y + j
				-- if the piece hit the bottom, consider it a merge for the sake of converting to sand
				if y < 0 then return true end
				-- otherwise test vs pixels
				if x >= 0 and x < w
				and y < h
				and ptr[x + w * y] ~= 0
				then
					return true
				end
			end
		end
	end
end

function SandModel:mergePiece(player)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local sandTex = self:getSandTex()
	local dstp = ffi.cast('uint32_t*', sandTex.image.buffer)
	local srcp = ffi.cast('uint32_t*', player.pieceTex.image.buffer)
	for j=0,app.pieceSize.y-1 do
		-- I could abstract out the merge code to each sandmodel
		-- but meh, sph wants random col order, automata doesn't care,
		-- so i'll just have it random ehre
		--[[
		for i=0,app.pieceSize.x-1 do
		--]]
		-- [[
		local istart,iend,istep
		if math.random(2) == 2 then
			istart = 0
			iend = app.pieceSize.x-1
			istep = 1
		else
			istart = app.pieceSize.x-1
			iend = 0
			istep = -1
		end
		for i=istart,iend,istep do
		--]]
			local k = i + app.pieceSize.x * j
			local color = srcp[k]
			if color ~= 0 then
				local x = player.piecePos.x + i
				local y = player.piecePos.y + j
				if x >= 0 and x < w
				and y >= 0 and y < h
				and dstp[x + w * y] == 0
				then
					dstp[x + w * y] = color
					-- [[ this is only for sph sand
					if self.mergepixel then
						self:mergepixel(x,y,color)
					end
					--]]
				end
			end
		end
	end
	self.sandImageDirty = true
end

ffi.cdef[[
typedef struct {
	int y1;
	int y2;
	int x;
	int cl;		//classification
	int blob;	//blob index
} ImageBlobColInterval_t;
]]
local ImageBlobColInterval_t = ffi.metatype('ImageBlobColInterval_t', {
	__tostring = function(self)
		return 'ImageBlobColInterval_t{'
			..'y1='..self.y1..','
			..'y2='..self.y2..','
			..'x='..self.x..','
			..'cl='..self.cl
		..'}'
	end,
})

local vector = require 'ffi.cpp.vector'

-- unlike Image's Blob, this is a collection of column intervals
-- maybe I should move it to Image, but then again, its usage here is pretty specialized
local BlobCol = class()
BlobCol.init = table.init
BlobCol.insert = table.insert
BlobCol.append = table.append


-- prune a pair of columns from any intervals that are not touching one another and have matching class ids
function SandModel:pruneCols(colL, colR)
	for swap=0,1 do
		-- scan through last colregions
		-- if any on it dont touch matching colors in this col then get rid of them
		-- same with intervals in this col / touching last col
		for il=colL.size-1,0,-1 do
			local intl = colL.v[il]
			local touches = false
			for ir=0,colR.size-1 do
				local intr = colR.v[ir]
--print('testing', intl, intr)
				if intr.y1 > intl.y2 then break end	-- too far
				if intr.y2 >= intl.y1 then
					if intr.cl == intl.cl then
--print('touches')
						touches = true
						break
					end
				end
			end
			if not touches then
				colL:erase(colL.v+il, colL.v+il+1)
--print('not touches, erasing', il, 'colL size is now', colL.size)
			end
		end
		if colL.size == 0 then
			-- no intervals touch - short-circuit that we're done
			return true
		end
		colL, colR = colR, colL
	end
end

-- [[ using generic image blob detection
function SandModel:checkClearBlobs()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	local blobs = self:getSandTex().image:getBlobs(self.getBlobCtx)
--print('#blobs', #blobs)
	for _,blob in pairs(blobs) do
		if blob.cl ~= 0 then
			local xmin = math.huge
			local xmax = -math.huge
			for _,int in ipairs(blob) do
				xmin = math.min(xmin, int.x1)
				xmax = math.max(xmax, int.x2)
			end
			local blobwidth = xmax - xmin + 1
			if blobwidth == w then
--print('clearing blob of class', blob.cl)
				clearedCount = clearedCount + self:clearBlobHorz(blob)
			end
		end
	end
	return clearedCount
end
--]]
--[[ tracking columsn left to right, seeing what connects
function SandModel:checkClearBlobs()
	local app = self.app
	local w, h = app.sandSize:unpack()

	self.colctx = self.colctx or {}
	local ctx = self.colctx

	local colregions = ctx.colregions
	if not colregions then
		colregions = {}
		ctx.colregions = colregions
	end
	for j=1,h do
		local col = colregions[j]
		if not col then
			col = vector'ImageBlobColInterval_t'
			colregions[j] = col
		else
			col:clear()
		end
	end
	for j=h+1,#colregions do
		colregions[j] = nil
	end

	--[[
	local blobs = ctx.blobs
	if not blobs then
		blobs = Blobs()
		ctx.blobs = blobs
	else
		for k in pairs(blobs) do blobs[k] = nil end
	end
	local nextblobindex = 1
	--]]

	local sandTex = self:getSandTex()
	local ptr = ffi.cast('uint8_t*', sandTex.image.buffer)

	-- get first column of intervals
	for x = 0,w-1 do
		local col = colregions[x+1]

		local p = ptr + 4 * x
		local y = 0
		local cl = p[3]
		repeat
			local cl2
			local ystart = y
			repeat
				y = y + 1
				p = p + 4 * w
				if y == h then break end
				cl2 = p[3]
			until cl ~= cl2
			if cl ~= 0 then
				local c = col:emplace_back()
				c.y1 = ystart
				c.y2 = y - 1
				c.x = x
				c.cl = cl
				c.blob = -1
			end
			-- prepare for next col
			cl = cl2
		until y == h

		-- no intervals <-> no connection
		if col.size == 0 then return 0 end

		if x > 0 then
			local colL = colregions[x]	-- cuz colregions is 1-based
			local colR = col
			if self:pruneCols(colL, colR) then return 0 end
		end
	end

	--[[
	for x=0,w-1 do
		io.write(x)
		local col = colregions[x+1]
		for i=0,col.size-1 do
			local c = col.v[i]
			io.write(tostring(c))
			--' [',c.y1,',',c.y2,':',c.cl,']')
		end
		print()
	end
	--]]
	-- find connection
	-- go back and check intervals and eliminate any that are not connected
	-- also form blobs while we go
	for x=w-1,0,-1 do
		local col = colregions[x+1]
		if x > 0 then
			local colL = colregions[x]
			if self:pruneCols(colL, col) then return 0 end
		end
		-- if col was empty then we've returned by now

		if x == w-1 then
			-- init blobs
			for i=0,col.size-1 do
				local int = col.v[i]
				local blob = BlobCol()
			end

		else
	end

	-- now that we're here we made it
	print'made it'

	local clearedCount = 0

	return clearedCount
end
--]]

local AutomataSandCPU = SandModel:subclass()

AutomataSandCPU.name = 'Automata CPU'

function AutomataSandCPU:update()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local needsCheckLine = false
	for i=1,app.updatesPerFrame do
		-- update
		local prow = ffi.cast('int32_t*', self.sandTex.image.buffer) + w
		for j=1,h-1 do
			-- 50/50 cycling left-to-right vs right-to-left
			local istart, iend, istep
			if app.rng(2) == 2 then
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
						needsCheckLine = true
					-- hmm symmetry? check left vs right first?
					elseif app.rng() < app.cfg.toppleChance then
						-- 50/50 check left then right, vs check right then left
						if app.rng(2) == 2 then
							if i > 0 and p[-w-1] == 0 then
								p[0], p[-w-1] = p[-w-1], p[0]
								needsCheckLine = true
							elseif i < w-1 and p[-w+1] == 0 then
								p[0], p[-w+1] = p[-w+1], p[0]
								needsCheckLine = true
							end
						else
							if i < w-1 and p[-w+1] == 0 then
								p[0], p[-w+1] = p[-w+1], p[0]
								needsCheckLine = true
							elseif i > 0 and p[-w-1] == 0 then
								p[0], p[-w-1] = p[-w-1], p[0]
								needsCheckLine = true
							end
						end
					end
				end
				p = p + istep
			end
			prow = prow + w
		end
	end

	self.sandImageDirty = needsCheckLine
	return needsCheckLine
end

-- clear blobs represented as a list of horizontal intervals
function AutomataSandCPU:clearBlobHorz(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		ffi.fill(self.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			app.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
		end
	end
	self.sandImageDirty = true
	return clearedCount
end

function AutomataSandCPU:flipBoard()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local p1 = ffi.cast('int32_t*', self.sandTex.image.buffer)
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


local vector = require 'ffi.cpp.vector'

-- TODO put this in ext.math
--local DBL_EPSILON = 2.220446049250313080847e-16
local FLT_EPSILON = 1.1920928955078125e-7

ffi.cdef[[
typedef struct {
	vec2f_t pos;
	vec2f_t vel;
	uint32_t color;
} grain_t;
]]

local SPHSand = SandModel:subclass()

SPHSand.name = 'SPH'

function SPHSand:init(app)
	SPHSand.super.init(self, app)
	self.grains = vector'grain_t'

	-- keep track of what is being cleared this frame
	-- use this to test for what particles to remove
	self.currentClearImage = Image(app.sandSize.x, app.sandSize.y, 4, 'unsigned char')

	-- use for diffusing velocity
	local w, h = app.sandSize:unpack()
	-- x,y, weight
	self.vel = ffi.new('vec3f_t[?]', w * h)
end

function SPHSand:checkClearBlobs()
	local app = self.app
	local w, h = app.sandSize:unpack()
	ffi.fill(self.currentClearImage.buffer, 4 * w * h)
	SPHSand.super.checkClearBlobs(self)
end

function SPHSand:update()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local dt = app.updateInterval

	local needsCheckLine = false
	local grav = -9.8 * tonumber(app.pieceSize.x)
	local dragCoeff = .9
	local groundFriction = .1
	-- move particles, collide based on last iteration's blits
	for gi=0,self.grains.size-1 do
		local g = self.grains.v + gi
		g.pos.x = g.pos.x + g.vel.x * dt
		g.pos.y = g.pos.y + g.vel.y * dt
		g.vel.x = g.vel.x * dragCoeff
		g.vel.y = g.vel.y + grav * dt
		if g.pos.x < .5 then
			g.vel.x = 0     -- TOOD bounce? does sand bounce?
			g.pos.x = .5
		elseif g.pos.x > w-.5 then
			g.vel.x = 0
			g.pos.x = w-.5
		end
		g.pos.y = math.clamp(g.pos.y, 0, h-FLT_EPSILON)

		local x = math.floor(g.pos.x)
		local y = math.floor(g.pos.y)
		local onground
		if y == 0 then
			onground = true
		else
			local p = ffi.cast('uint32_t*', self.sandTex.image.buffer) + (x + w * y)

			-- if the cell is blank and there's a sand cell above us ... pull it down
			--if p[0] ~= 0 then -- should be true from blitting last frame?
			if p[-w] ~= 0 then
				if g.vel.y < 0 then
					g.vel.y = -groundFriction * g.vel.y
				end
			end
			-- resting velocity
			if math.abs(g.vel.x) + math.abs(g.vel.y) < 10 then
				if p[-w] ~= 0 then
					onground = true
				end
				if math.random() < app.cfg.toppleChance then
					-- hmm symmetry? check left vs right first?
					-- 50/50 check left then right, vs check right then left
					if math.random(2) == 2 then
						if x > 0 and p[-w-1] == 0 then
							-- swap colors
							p[0], p[-w-1] = p[-w-1], p[0]
							-- move sand
							g.pos.x = g.pos.x - 1
							g.pos.y = g.pos.y - 1
							needsCheckLine = true
						elseif x < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							g.pos.x = g.pos.x + 1
							g.pos.y = g.pos.y - 1
							needsCheckLine = true
						else
							onground = true
						end
					else
						if x < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							g.pos.x = g.pos.x + 1
							g.pos.y = g.pos.y - 1
							needsCheckLine = true
						elseif x > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							g.pos.x = g.pos.x - 1
							g.pos.y = g.pos.y - 1
							needsCheckLine = true
						else
							onground = true
						end
					end
				end
			end
		end
		if onground then
			g.vel.y = 0
			g.vel.x = g.vel.x * groundFriction
		end
	end

	--[[
	-- TODO here blit velocity to a separate buffer,
	-- then read back that buffer for advection of velocity
	ffi.fill(self.vel, 0, ffi.sizeof'vec3f_t' * w * h)
	local weights = {
		[-1] = {[-1] = 1/36, [0]=4/36, [1]=1/36},
		[0] = {[-1] = 4/36, [0]=16/36, [1]=4/36},
		[1] = {[-1] = 1/36, [0]=4/36, [1]=1/36},
	}
	for gi=0,self.grains.size-1 do
		local g = self.grains.v + gi
		local x = math.floor(g[0].pos.x)
		local y = math.floor(g[0].pos.y)
		-- diffuse and accumulate
		for ofx=-1,1 do
			for ofy=-1,1 do
				local weight = weights[ofx][ofy]
				local xd = math.clamp(x + ofx, 0, w-1)
				local yd = math.clamp(y + ofy, 0, h-1)
				local v = self.vel + (xd + w * yd)
				v[0].x = v[0].x + g[0].vel.x * weight
				v[0].y = v[0].y + g[0].vel.y * weight
				v[0].z = v[0].z + weight
			end
		end
	end
	-- read back
	for gi=0,self.grains.size-1 do
		local g = self.grains.v + gi
		local x = math.floor(g[0].pos.x)
		local y = math.floor(g[0].pos.y)
		local v = self.vel + (x + w * y)
		g[0].vel.x = v[0].x / v[0].z
		g[0].vel.y = v[0].y / v[0].z
	end
	--]]

	-- now clear and blit all grains onto the board
	ffi.fill(self.sandTex.image.buffer, w * h * 4)
	local pushForceTimesDT = 1
	local numOverlaps = 0
	for gi=0,self.grains.size-1 do
		local g = self.grains.v[gi]
		local x = math.floor(g.pos.x)
		local y = math.floor(g.pos.y)
		local p = ffi.cast('uint32_t*', self.sandTex.image.buffer) + (x + w * y)
		-- if there's already a color here / sand here
		if p[0] ~= 0 then
			numOverlaps = numOverlaps + 1
			-- give it a push up?
			g.vel.y = g.vel.y + (math.random() - .5) * pushForceTimesDT
			g.vel.y = g.vel.y + pushForceTimesDT
			g.pos.y = math.clamp(g.pos.y + 1, 0, h-FLT_EPSILON)
		end
		p[0] = g.color
	end
	--print('numOverlaps ',numOverlaps)

	self.sandImageDirty = needsCheckLine
	return needsCheckLine
end
function SPHSand:mergepixel(x,y,color)
	local app = self.app
	local g = self.grains:emplace_back()
	g.pos:set(x+.5, y+.5)
	--local vel = math.random() * 150 * (vec2f(0,-1) + (vec2f(x+.5,y+.5)-vec2f(app.pieceSize:unpack())*.5) / tonumber(app.pieceSize.x))
	local vel = vec2f(0,-1)
	g.vel:set(vel:unpack())
	--g.vel:set(0,0)
	g.color = color
end
function SPHSand:clearBlobHorz(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		--ffi.fill(self.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			self.currentClearImage.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
			app.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
		end
	end
	return clearedCount
end
function SPHSand:doneClearingBlobs()
	local app = self.app
	local w, h = app.sandSize:unpack()
	for gi=self.grains.size-1,0,-1 do
		local g = self.grains.v + gi
		local x = math.floor(g.pos.x)
		local y = math.floor(g.pos.y)
		local ofs = x + w * y
		if ffi.cast('uint32_t*', self.currentClearImage.buffer)[ofs] ~= 0 then
			ffi.cast('uint32_t*', self.sandTex.image.buffer)[ofs] = 0
			self.grains:erase(g, g+1)
		end
	end
end
function SPHSand:flipBoard()
	local w, h = app.sandSize:unpack()
	for i=0,self.grains.size-1 do
		local g = self.grains.v+i
		g[0].pos.y = h-g[0].pos.y-FLT_EPSILON
	end
	self.sandTex:bind():subimage()
end
function SPHSand:updateDebugGUI()
	ig.igText('Num Grains: '..self.grains.size)
end


local CFDSand = SandModel:subclass()
CFDSand.name = 'CFD (experimental)'
function CFDSand:init(app)
	CFDSand.super.init(self, app)
	local w, h = app.sandSize:unpack()
	local function make()
		local f = ffi.new('float[?]', w * h)
		ffi.fill(f, ffi.sizeof'float' * w * h)
		return f
	end
	self.u = make()
	self.v = make()
	self.uprev = make()
	self.vprev = make()
	self.sandTexPrev = app:makeTexWithBlankImage(app.sandSize)
	self.div = make()
	self.p = make()

	self.dx = 1/4
end
function CFDSand:update()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local dt = app.updateInterval
	local grav = -9.8 * tonumber(app.pieceSize.x)

	local needsCheckLine = false
	-- update
	local sandip = ffi.cast('int32_t*', self.sandTex.image.buffer)
	local prow = sandip + w
	local urow = ffi.cast('float*', self.u) + w
	local vrow = ffi.cast('float*', self.v) + w
	for j=1,h-1 do
		-- 50/50 cycling left-to-right vs right-to-left
		local istart, iend, istep
		if app.rng(2) == 2 then
			istart,iend,istep = 0, w-1, 1
		else
			istart,iend,istep = w-1, 0, -1
		end
		local p = prow + istart
		local u = urow + istart
		local v = vrow + istart
		for i=istart,iend,istep do
			-- if the cell is blank and there's a sand cell above us ... pull it down
			if p[0] ~= 0 then
				if p[-w] == 0 then
					p[0], p[-w] = p[-w], p[0]
					u[0], u[-w] = u[-w], u[0]
					v[0], v[-w] = v[-w], v[0]
					v[0] = v[0] + grav * dt
					needsCheckLine = true
				-- hmm symmetry? check left vs right first?
				elseif app.rng() < app.cfg.toppleChance then
					-- 50/50 check left then right, vs check right then left
					if app.rng(2) == 2 then
						if i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							u[0], u[-w-1] = u[-w-1], u[0]
							v[0], v[-w-1] = v[-w-1], v[0]
							u[0] = u[0] - grav * dt
							v[0] = v[0] + grav * dt
							needsCheckLine = true
						elseif i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							u[0], u[-w+1] = u[-w+1], u[0]
							v[0], v[-w+1] = v[-w+1], v[0]
							u[0] = u[0] + grav * dt
							v[0] = v[0] + grav * dt
							needsCheckLine = true
						end
					else
						if i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							u[0], u[-w+1] = u[-w+1], u[0]
							v[0], v[-w+1] = v[-w+1], v[0]
							u[0] = u[0] + grav * dt
							v[0] = v[0] + grav * dt
							needsCheckLine = true
						elseif i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							u[0], u[-w-1] = u[-w-1], u[0]
							v[0], v[-w-1] = v[-w-1], v[0]
							u[0] = u[0] - grav * dt
							v[0] = v[0] + grav * dt
							needsCheckLine = true
						end
					end
				end
			end
			p = p + istep
			u = u + istep
			v = v + istep
		end
		prow = prow + w
		urow = urow + w
		vrow = vrow + w
	end

	--[[ external forces?
	for j=0,h-1 do
		for i=0,w-1 do
			local f = i/(w-1)
			local v = self.v + (i + w * j)
			v[0] = v[0] + grav * dt
		end
	end
	--]]

	assert(dt)
	local visc = .01
	local diff = .05
	self:velocityStep(visc, dt)
	self:densityStep(diff, dt)

	self.sandImageDirty = needsCheckLine
	return needsCheckLine
end
function CFDSand:densityStep(diff, dt)
	--self:addSource()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local rgbaImage = ffi.cast('uint32_t*', self.sandTex.image.buffer)
	local rgbaPrevImage = ffi.cast('uint32_t*', self.sandTexPrev.image.buffer)
	-- diffuse
	--self:diffuse(0, rgbaPrevImage, rgbaImage, diff, dt)
	-- or just copy?
	ffi.copy(rgbaPrevImage, rgbaImage, 4 * w * h)
	self:advect(0, rgbaImage, rgbaPrevImage, self.u, self.v, dt, true)
end
function CFDSand:velocityStep(visc, dt)
	--self:addSource()
	self.u, self.uprev = self.uprev, self.u
	self:diffuse(1, self.u, self.uprev, visc, dt)
	self.v, self.vprev = self.vprev, self.v
	self:diffuse(2, self.v, self.vprev, visc, dt)
	self:projectVel()
	self.u, self.uprev = self.uprev, self.u
	self.v, self.vprev = self.vprev, self.v
	-- advect u0 & v0 into u & v
	self:advect(1, self.u, self.uprev, self.uprev, self.vprev, dt)
	self:advect(2, self.v, self.vprev, self.uprev, self.vprev, dt)
	self:projectVel()
end
function CFDSand:diffuse(dir, dst, src, diff, dt)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local dx = self.dx
	local dy = dx
	local dA = dx * dy
	local a = diff * dt / dA
	-- Gauss-Seidel implementation of Backward-Euler integration...
	for k=1,20 do
		for j=1,h-2 do
			local jR = j+1
			local jL = j-1
			for i=1,w-2 do
				local iR = i+1
				local iL = i-1
				dst[i + w * j] = src[i + w * j] + a * (
					dst[iL + w * j]
					+ dst[iR + w * j]
					+ dst[i + w * jL]
					+ dst[i + w * jR]
				)
			end
		end
		self:updateBoundary(dir, dst)
	end
end
function CFDSand:advect(dir, dst, src, u, v, dt, nearest)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local dx = self.dx
	local dy = dx
	local dt_dx = dt / dx
	local dt_dy = dt / dy
	for j=1,h-2 do
		for i=1,w-2 do
			local x = i - dt_dx * u[i + w * j]
			x = math.clamp(x, .5, w + .5)
			local i0 = math.floor(x)
			local i1 = i0 + 1
			local s1 = x - i0

			local y = j - dt_dy * v[i + w * j]
			y = math.clamp(y, .5, h + .5)
			local j0 = math.floor(y)
			local j1 = j0 + 1
			local t1 = y - j0

			if nearest then
				dst[i + w * j] =
					s1 < .5 and (
						t1 < .5
						and src[i0 + w * j0]
						or src[i0 + w * j1]
					) or (
						t1 < .5
						and src[i1 + w * j0]
						or src[i1 + w * j1]
					)
			else
				local s0 = 1 - s1
				local t0 = 1 - t1
				dst[i + w * j] = s0 * (t0 * src[i0 + w * j0] + t1 * src[i0 + w * j1])
								+ s1 * (t0 * src[i1 + w * j0] + t1 * src[i1 + w * j1])
			end
		end
	end
	self:updateBoundary(dir, dst)
end
-- Helmholtz decomposition to make a divergence-free fluid
function CFDSand:projectVel()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local u = self.u
	local v = self.v
	local div = self.div
	local p = self.p
	local dx = self.dx
	local dy = dx
	for j=1,h-2 do
		local jR = j+1
		local jL = j-1
		for i=1,w-2 do
			local iR = i+1
			local iL = i-1
			div[i + w * j] = -.5 * (
				dx * (u[iR + w * j] - u[iL + w * j])
				+ dy * (v[i + w * jR] - v[i + w * jL])
			)
			p[i + w * j] = 0
		end
	end
	self:updateBoundary(0, div)
	self:updateBoundary(0, p)

	for k=1,20 do
		for j=1,h-2 do
			local jR = j+1
			local jL = j-1
			for i=1,w-2 do
				local iR = i+1
				local iL = i-1
				p[i + w * j] = (div[i + w * j] + p[iL + w * j] + p[iR + w * j] + p[i + w * jL] + p[i + w * jR]) * .25
			end
		end
	end
	self:updateBoundary(0, p)

	for j=1,h-2 do
		local jR = j+1
		local jL = j-1
		for i=1,w-2 do
			local iR = i+1
			local iL = i-1
			u[i + w * j] = u[i + w * j] - .5 * (p[iR + w * j] - p[iL + w * j]) / dx
			v[i + w * j] = v[i + w * j] - .5 * (p[i + w * jR] - p[i + w * jL]) / dy
		end
	end
	self:updateBoundary(1, u)
	self:updateBoundary(2, v)
end
function CFDSand:updateBoundary(dir, dst)
	local app = self.app
	local w, h = app.sandSize:unpack()
	for j=1,h-2 do
		dst[0 + w * j] = dir==1 and -dst[1 + w * j] or dst[1 + w * j]
		dst[w-1 + w * j] = dir==1 and -dst[w-2 + w * j] or dst[w-2 + w * j]
	end
	for i=1,w-2 do
		dst[i + w * 0] = dir==2 and -dst[i + w * 1] or dst[i + w * 1]
		dst[i + w * (h-1)] = dir==2 and -dst[i + w * (h-2)] or dst[i + w * (h-2)]
	end
	dst[0 + w * 0] = .5 * (dst[1 + w * 0] + dst[0 + w * 1])
	dst[0 + w * (h-1)] = .5 * (dst[1 + w * (h-1)] + dst[0 + w * (h-2)])
	dst[w-1 + w * 0] = .5 * (dst[w-2 + w * 0] + dst[w-1 + w * 1])
	dst[w-1 + w * (h-1)] = .5 * (dst[w-2 + w * (h-1)] + dst[w-1 + w * (h-2)])
end
function CFDSand:mergepixel(x,y,color)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local v = self.v + x + w * y
	v[0] = v[0] - 0
end
function CFDSand:clearBlobHorz(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		ffi.fill(self.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			app.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
			self.u[k + 4 * (int.x1 + w * int.y)] = 0
			self.v[k + 4 * (int.x1 + w * int.y)] = 0
		end
	end
	self.sandImageDirty = true
	return clearedCount
end
function CFDSand:flipBoard()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local p1 = ffi.cast('int32_t*', self.sandTex.image.buffer)
	local p2 = p1 + w * h - 1
	local u1 = ffi.cast('float*', self.u)
	local u2 = u1 + w * h - 1
	local v1 = ffi.cast('float*', self.v)
	local v2 = v1 + w * h - 1
	for j=0,bit.rshift(h,1)-1 do
		for i=0,w-1 do
			p1[0], p2[0] = p2[0], p1[0]
			p1 = p1 + 1
			p2 = p2 - 1
			u1[0], u2[0] = u2[0], u1[0]
			u1 = u1 + 1
			u2 = u2 - 1
			v1[0], v2[0] = v2[0], v1[0]
			v1 = v1 + 1
			v2 = v2 - 1
		end
	end
	self.sandTex:bind():subimage()
end



-- proof-of-concept for gpu updates
-- I'm not moving all operations (in app.lua) to the gpu just yet
-- esp since cfd and sph sand use cpu operations

local gl = require 'gl'
local GLPingPong = require 'gl.pingpong'
local GLProgram = require 'gl.program'

local AutomataSandGPU = SandModel:subclass()

AutomataSandGPU.name = 'Automata GPU'

function AutomataSandGPU:init(app)
	AutomataSandGPU.super.init(self, app)
	local w, h = app.sandSize:unpack()

	self.sandTex = nil	-- not needed for GPU .. instad use the pingpong
	self.pp = GLPingPong{
		-- args copied from App:makeTexWithBlankImage
		internalFormat = gl.GL_RGBA,
		width = tonumber(app.sandSize.x),
		height = tonumber(app.sandSize.y),
		format = gl.GL_RGBA,
		type = gl.GL_UNSIGNED_BYTE,
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,

		fbo = self.fbo,
		-- pingpong arg
		-- for desktop gl i'd attach a tex per attachment
		-- but for gles2 / webgl1 this isn't ideal
		-- (but for gles3 / webgl2 it's fine)
		dontAttach = true,
	}

	-- give each pingpong buffer an image
	for _,t in ipairs(self.pp.hist) do
		local size = app.sandSize
		local img = Image(size.x, size.y, 4, 'unsigned char')
		ffi.fill(img.buffer, 4 * size.x * size.y)
		t.image = img
		t.data = img.buffer
	end

	-- init here?  or elsewhere?  or every time we bind?
	self.pp.fbo:bind()
	self.pp.fbo:setColorAttachmentTex2D(self.pp:cur().id, 0)
	local res,err = self.pp.fbo.check()
	if not res then print(err) end
	self.pp.fbo:unbind()

	--[[
	handle 2x2 blocks offset at 00 10 01 11

yofs = alternating rows
xofs = 0 <-> fall right, xofs = 1 <-> fall left

for xofs=0 (fall right)

+---+---+    +---+---+
|   | ? |    |   | ? |
+---+---+ => +---+---+
| ? | ? |    | ? | ? |
+---+---+    +---+---+

+---+---+    +---+---+
| A | ? |    |   | ? |
+---+---+ => +---+---+
|   | ? |    | A | ? |
+---+---+    +---+---+

+---+---+    +---+---+
| A | ? |    |   | ? |
+---+---+ => +---+---+
| B |   |    | B | A |
+---+---+    +---+---+

+---+---+    +---+---+
| A | ? |    | A | ? |
+---+---+ => +---+---+
| B | C |    | B | C |
+---+---+    +---+---+

for xofs=1 (fall left), same but mirrored

	--]]
	self.updateShader = GLProgram{
		vertexCode = [[
#version ]]..app.glslVersion..[[

precision highp float;

in vec2 vertex;

out vec2 texcoordv;

uniform mat4 mvProjMat;

void main() {
	texcoordv = vertex;
	gl_Position = mvProjMat * vec4(vertex, 0., 1.);
}
]],
		fragmentCode = [[
#version ]]..app.glslVersion..[[

precision highp float;

in vec2 texcoordv;

out vec4 fragColor;

uniform ivec2 texsize;
uniform ivec3 ofs;		//x=xofs (0,1), y=yofs (0,1), z = topple-right
uniform sampler2D tex;

void main() {
	//current integer texcoord
	ivec2 itc = ivec2(texcoordv * vec2(texsize));

	//get the [0,1]^2 offset within our 2x2 block
	ivec2 lc = (itc & 1) ^ ofs.xy;

	//get the upper-left integer texcoord of the block
	//ivec2 ulitc = itc & (~ivec2(1,1));
	ivec2 ulitc = itc - lc;

	//if we're on a 2x2 box that extends beneath the bottom ...
	if (
		ulitc.y < 0 ||
		ulitc.y >= texsize.y-1 ||

		ulitc.x < 0 ||
		ulitc.x >= texsize.x-1
	) {
		// then just keep whatever's here
		fragColor = texelFetch(tex, itc, 0);
		return;
	}

	//get the blocks
	//vec4 c[2][2];
	// glsl 310 es needed for arrays of arrays
	// so instead ...
	vec4 c[4];
	c[0 + (0 << 1)] = texelFetch(tex, ulitc + ivec2(0, 0), 0);
	c[1 + (0 << 1)] = texelFetch(tex, ulitc + ivec2(1, 0), 0);
	c[0 + (1 << 1)] = texelFetch(tex, ulitc + ivec2(0, 1), 0);
	c[1 + (1 << 1)] = texelFetch(tex, ulitc + ivec2(1, 1), 0);

	//fall down + right...
	if (ofs.z == 0) {

		// upper-left is empty
		if (c[0 + (1 << 1)] == vec4(0.)) {
			//then do nothing -- draw the output as input
			fragColor = c[lc.x + (lc.y << 1)];
		// upper-left isn't empty, but lower-left is ...
		} else if (c[0 + (0 << 1)] == vec4(0.)) {
			// swap y for lc.x == ofs.x, keep y for xofs=1
			if (lc.x == 0) {
				fragColor = c[lc.x + (((~lc.y)&1) << 1)];
			} else {
				fragColor = c[lc.x + (lc.y << 1)];
			}
			//fragColor = c[lc.x + ((lc.x ^ ((~lc.x)&1)) << 1)];
		// upper-left isn't empty, lower-left isn't empty, lower-right is empty ...
		} else if (c[1 + (0 << 1)] == vec4(0.)) {
			if (lc.x != lc.y) {
				fragColor = c[((~lc.x)&1) + (((~lc.y)&1) << 1)];
			} else {
				fragColor = c[lc.x + (lc.y << 1)];
			}
		// all are full -- keep
		} else {
			fragColor = c[lc.x + (lc.y << 1)];
		}

	//fall down + left ...
	} else {

		// upper-right is empty
		if (c[1 + (1 << 1)] == vec4(0.)) {
			//then do nothing -- draw the output as input
			fragColor = c[lc.x + (lc.y << 1)];
		// upper-right isn't empty, but lower-right is ...
		} else if (c[1 + (0 << 1)] == vec4(0.)) {
			// swap y for lc.x == ofs.x, keep y for xofs=1
			if (lc.x == 1) {
				fragColor = c[lc.x + (((~lc.y)&1) << 1)];
			} else {
				fragColor = c[lc.x + (lc.y << 1)];
			}
			//fragColor = c[lc.x + ((lc.x ^ ((~lc.x)&1)) << 1)];
		// upper-right isn't empty, lower-right isn't empty, lower-left is empty ...
		} else if (c[0 + (0 << 1)] == vec4(0.)) {
			if (lc.x == lc.y) {
				fragColor = c[((~lc.x)&1) + (((~lc.y)&1) << 1)];
			} else {
				fragColor = c[lc.x + (lc.y << 1)];
			}
		// all are full -- keep
		} else {
			fragColor = c[lc.x + (lc.y << 1)];
		}
	}
}
]],
		uniforms = {
			tex = 0,
			texsize = {w, h},
		},

		attrs = {
			vertex = app.quadVertexBuf,
		},
	}
end

local function printBuf(buf, w, h, yofs)
	local p = ffi.cast('uint32_t*', buf)
	local s = ''
	for j=0,h-1 do
		local l = ''
		for i=0,w-1 do
			local c = ('| %8x '):format(p[0])
			l = l .. c
			p=p+1
		end
		l = l .. '\n'
		if j % 2 == yofs then
			l = l .. '\n'
		end
		s = l .. s
	end
	print(s)
	return s
end

function AutomataSandGPU:test()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local p = ffi.cast('uint32_t*', self.sandTex.image.buffer)
	for j=0,h-1 do
		for i=0,w-1 do
			if math.random() < .5 then
				p[0] = math.random(0, 0xffffffff)
			end
			p=p+1
		end
	end

	print'before'
	local beforeStr = printBuf(self.sandTex.image.buffer, w, h, 0)

	-- copy sandtex to pingpong
	self.pp:prev()
		:bind()
		:subimage{data=self.sandTex.image.buffer}
		:unbind()

	app.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)

	self.updateShader
		:use()
		:enableAttrs()
	gl.glUniformMatrix4fv(
		self.updateShader.uniforms.mvProjMat.loc,
		1,
		gl.GL_FALSE,
		app.mvProjMat.ptr)

	gl.glViewport(0, 0, w, h)

	for i=1,app.updatesPerFrame do
		for toppleRight=1,1 do
			for yofs=0,0 do
				for xofs=0,0 do
					-- update
					self.pp:draw{
						callback = function()
							gl.glUniform3i(self.updateShader.uniforms.ofs.loc, xofs, yofs, toppleRight)
							local tex = self.pp:prev()
							tex:bind()
							gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
							tex:unbind()
						end,
					}
					self.pp:swap()

					-- get pingpong
					self.pp:prev():toCPU(self.sandTex.image.buffer)

					print('after ofs', xofs, yofs, toppleRight)
					local afterStr = printBuf(self.sandTex.image.buffer, w, h, yofs)
				end
			end
		end
	end
	gl.glViewport(0, 0, app.width, app.height)

	self.updateShader
		:disableAttrs()
		:useNone()

	os.exit()
end

local glreport = require 'gl.report'
function AutomataSandGPU:update()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local fbo = self.pp.fbo
	local shader = self.updateShader

	shader:use()
		:enableAttrs()

	app.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)
	gl.glUniformMatrix4fv(
		shader.uniforms.mvProjMat.loc,
		1,
		gl.GL_FALSE,
		app.mvProjMat.ptr)

	local rightxor = math.random(0,1)
	local xofsxor = math.random(0,1)
	local yofsxor = math.random(0,1)

	fbo:bind()
	gl.glViewport(0, 0, w, h)

	for i=1,app.updatesPerFrame do
		for toppleRight=0,1 do
			for xofs=0,1 do
				for yofs=0,1 do
					-- update
					--[[
					self.pp:draw{
						callback = function()
					--]]
					-- [[
					fbo:setColorAttachmentTex2D(self.pp:cur().id)
					-- check per-bind or per-set-attachment?
					local res,err = fbo.check()
					if not res then print(err) end
					--]]
							gl.glUniform3i(shader.uniforms.ofs.loc,
								bit.bxor(xofs, xofsxor),
								bit.bxor(yofs, yofsxor),
								bit.bxor(toppleRight, rightxor))
							local tex = self.pp:prev()
							tex:bind()
							gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
							tex:unbind()
					--[[
						end,
					}
					--]]
					-- [[
					--]]

					self.pp:swap()
				end
			end
		end
	end

	-- [[ while we're here, readpixels into the image
	gl.glReadPixels(
		0,							--GLint x,
		0,							--GLint y,
		w,							--GLsizei width,
		h,							--GLsizei height,
		gl.GL_RGBA,					--GLenum format,
		gl.GL_UNSIGNED_BYTE,		--GLenum type,
		self.pp:prev().image.buffer)	--void *pixels
	--]]

	fbo:unbind()
	gl.glViewport(0, 0, app.width, app.height)

	shader:disableAttrs()
		:useNone()
	return true
end

function AutomataSandGPU:clearBlobHorz(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local sandTex = self:getSandTex()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		ffi.fill(sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			app.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
		end
	end
	self.sandImageDirty = true
	return clearedCount
end

-- TODO
function AutomataSandGPU:flipBoard()
	-- hmm, needs the pingpong here
	-- so I need to assert the pingpong state too ...
	-- should the sand model be responsible for the sandTex ?
	local app = self.app
	local w, h = app.sandSize:unpack()
	local sandTex = self:getSandTex()
	local p1 = ffi.cast('int32_t*', sandTex.image.buffer)
	local p2 = p1 + w * h - 1
	for j=0,bit.rshift(h,1)-1 do
		for i=0,w-1 do
			p1[0], p2[0] = p2[0], p1[0]
			p1 = p1 + 1
			p2 = p2 - 1
		end
	end
	sandTex:bind():subimage()
end

function AutomataSandGPU:getSandTex()
	return self.pp:prev()
end

--[[ TODO
function AutomataSandGPU:mergePiece(player)
	local app = self.app
	local w, h = app.sandSize:unpack()

	local fbo = self.pp.fbo
	local srctex = self.pp:prev()
	local dsttex = self.pp:cur()
	local shader = app.displayShader

	gl.glViewport(0, 0, w, h)

	fbo:bind()
	fbo:setColorAttachmentTex2D(dsttex.id)
	local res,err = fbo.check()
	if not res then print(err) end

	gl.glClearColor(0,0,0,0)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	shader:use()
		:enableAttrs()

	app.projMat:setOrtho(0, 1, 0, 1, -1, 1)
	app.mvMat:setTranslate(
			player.piecePos.x / w - .5,
			player.piecePos.y / h - .5
		)
		:applyScale(app.pieceSize.x / w, app.pieceSize.y / h)
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)
	gl.glUniform1i(shader.uniforms.useAlpha.loc, 1)

	player.pieceTex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

	app.projMat:setOrtho(0, 1, 0, 1, -1, 1)
	app.mvMat:setIdent()
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)
	gl.glUniform1i(shader.uniforms.useAlpha.loc, 0)

	srctex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

	shader:disableAttrs()
		:useNone()

	self.pp:swap()

	gl.glReadPixels(
		0,							--GLint x,
		0,							--GLint y,
		w,							--GLsizei width,
		h,							--GLsizei height,
		gl.GL_RGBA,					--GLenum format,
		gl.GL_UNSIGNED_BYTE,		--GLenum type,
		dsttex.image.buffer)		--void *pixels

	fbo:unbind()

	gl.glViewport(0, 0, app.width, app.height)

	self.sandImageDirty = true
end
--]]

SandModel.subclasses = table{
	AutomataSandGPU,
	AutomataSandCPU,
	SPHSand,
	CFDSand,
}
SandModel.subclassNames = SandModel.subclasses:mapi(function(cl) return cl.name end)

return SandModel
