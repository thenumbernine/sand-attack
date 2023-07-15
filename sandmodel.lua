local ffi = require 'ffi'
local math = require 'ext.math'
local class = require 'ext.class'
local table = require 'ext.table'
local vec4ub = require 'vec-ffi.vec4ub'
local vec2f = require 'vec-ffi.vec2f'
local Image = require 'image'

local SandModel = class()
function SandModel:init(app)
	self.app = assert(app)
end

local AutomataSand = class(SandModel)
AutomataSand.name = 'Automata'
function AutomataSand:update()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local needsCheckLine = false
	-- update
	local prow = ffi.cast('int32_t*', app.sandTex.image.buffer) + w
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

	return needsCheckLine
end
function AutomataSand:clearBlob(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		ffi.fill(app.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			app.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
		end
	end
	return clearedCount
end
function AutomataSand:flipBoard()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local p1 = ffi.cast('int32_t*', app.sandTex.image.buffer)
	local p2 = p1 + w * h - 1
	for j=0,bit.rshift(h,1)-1 do
		for i=0,w-1 do
			p1[0], p2[0] = p2[0], p1[0]
			p1 = p1 + 1
			p2 = p2 - 1
		end
	end
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

local SPHSand = class(SandModel)
SPHSand.name = 'SPH'
function SPHSand:init(app)
	SPHSand.super.init(self, app)
	self.grains = vector'grain_t'

	-- keep track of what is being cleared this frame
	-- use this to test for what particles to remove
	self.currentClearImage = Image(app.sandSize.x, app.sandSize.y, 4, 'unsigned char')
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
			local p = ffi.cast('uint32_t*', app.sandTex.image.buffer) + (x + w * y)

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

	-- TODO here blit velocity to a separate buffer,
	-- then read back that buffer for advection of velocity

	-- now clear and blit all grains onto the board
	ffi.fill(app.sandTex.image.buffer, w * h * 4)
	local pushForceTimesDT = 1
	local numOverlaps = 0
	for gi=0,self.grains.size-1 do
		local g = self.grains.v[gi]
		local x = math.floor(g.pos.x)
		local y = math.floor(g.pos.y)
		local p = ffi.cast('uint32_t*', app.sandTex.image.buffer) + (x + w * y)
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

	return needsCheckLine
end
function SPHSand:mergepixel(x,y,color)
	local app = self.app
	local g = self.grains:emplace_back()
	g.pos:set(x+.5, y+.5)
	--local vel = math.random() * 150 * (vec2f(0,1) + (vec2f(i+.5,j+.5)-vec2f(app.pieceSize:unpack())*.5) / tonumber(app.pieceSize.x))
	--g.vel:set(vel:unpack())
	g.vel:set(0,0)
	g.color = color
end
function SPHSand:clearBlob(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		--ffi.fill(app.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			app.currentClearImage.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
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
		if ffi.cast('uint32_t*', app.currentClearImage.buffer)[ofs] ~= 0 then
			ffi.cast('uint32_t*', app.sandTex.image.buffer)[ofs] = 0
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
end
function SPHSand:updateDebugGUI()
	ig.igText('Num Grains: '..self.grains.size)
end


local CFDSand = class(SandModel)
CFDSand.name = 'CFD'
function CFDSand:init(app)
	CFDSand.super.init(self, app)
	local w, h = app.sandSize:unpack()
	self.vel = ffi.new('vec2f_t[?]', w * h)
	self.nextvel = ffi.new('vec2f_t[?]', w * h)
	ffi.fill(self.vel, ffi.sizeof'vec2f_t' * w * h)
	ffi.fill(self.nextvel, ffi.sizeof'vec2f_t' * w * h)
end
function CFDSand:update()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local dt = app.updateInterval
	local grav = -9.8 * tonumber(app.pieceSize.x)
	
	local needsCheckLine = false
	-- update
	local sandip = ffi.cast('int32_t*', app.sandTex.image.buffer)
	local prow = sandip + w
	local vrow = ffi.cast('vec2f_t*', self.vel) + w
	for j=1,h-1 do
		-- 50/50 cycling left-to-right vs right-to-left
		local istart, iend, istep
		if app.rng(2) == 2 then
			istart,iend,istep = 0, w-1, 1
		else
			istart,iend,istep = w-1, 0, -1
		end
		local p = prow + istart
		local v = vrow + istart
		for i=istart,iend,istep do
			-- if the cell is blank and there's a sand cell above us ... pull it down
			if p[0] ~= 0 then
				if p[-w] == 0 then
					p[0], p[-w] = p[-w], p[0]
					v[0], v[-w] = v[-w], v[0]
					v[0].y = v[0].y + grav * dt
					needsCheckLine = true
				-- hmm symmetry? check left vs right first?
				elseif app.rng() < app.cfg.toppleChance then
					-- 50/50 check left then right, vs check right then left
					if app.rng(2) == 2 then
						if i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							v[0], v[-w-1] = v[-w-1], v[0]
							v[0].x = v[0].x - grav * dt
							v[0].y = v[0].y + grav * dt
							needsCheckLine = true
						elseif i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							v[0], v[-w+1] = v[-w+1], v[0]
							v[0].x = v[0].x + grav * dt
							v[0].y = v[0].y + grav * dt
							needsCheckLine = true
						end
					else
						if i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							v[0], v[-w+1] = v[-w+1], v[0]
							v[0].x = v[0].x + grav * dt
							v[0].y = v[0].y + grav * dt
							needsCheckLine = true
						elseif i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							v[0], v[-w-1] = v[-w-1], v[0]
							v[0].x = v[0].x - grav * dt
							v[0].y = v[0].y + grav * dt
							needsCheckLine = true
						end
					end
				end
			end
			p = p + istep
			v = v + istep
		end
		prow = prow + w
		vrow = vrow + w
	end

	-- external forces?
	for j=0,h-1 do
		for i=0,w-1 do
			local f = i/(w-1)
			local v = self.vel + (i + w * j)
			v[0].y = v[0].y + 5 * math.cos(math.pi * f)
		end
	end

	-- advect sand
	for j=0,h-1 do
		for i=0,w-1 do
			local vx, vy = self.vel[i + w * j]:unpack()
			local ni = i+.5 - vx
			local nj = j+.5 - vy
			ni = math.floor(math.clamp(ni, 0, w-1))
			nj = math.floor(math.clamp(nj, 0, h-1))
			if not (ni == i and nj == j) then
--print('advecting sand', i, j)				
				assert(i >= 0 and i < w and j >= 0 and j < h)
				-- advect sand
				sandip[i + w * j],
				sandip[ni + w * nj]
				--= 0xffffffff, 0xffffffff
				=	sandip[i + w * j],
					sandip[ni + w * nj]		
			end	
		end
	end
	
	-- advect velocity
	for j=0,h-1 do
		for i=0,w-1 do
			-- [[ advect
			local vx, vy = self.vel[i + w * j]:unpack()
			local ni = i+.5 - vx
			local nj = j+.5 - vy
			ni = math.floor(math.clamp(ni, 0, w-1))
			nj = math.floor(math.clamp(nj, 0, h-1))
			if not (ni == i and nj == j) then
--print('advecting vel', i, j)				
				assert(i >= 0 and i < w and j >= 0 and j < h)
				self.nextvel[i + w * j],
				self.nextvel[ni + w * nj]
				=	self.vel[i + w * j],
					self.vel[ni + w * nj]
				needsCheckLine = true
			end
			--]]
		end
	end
	
	self.vel, self.nextvel = self.nextvel, self.vel

	return needsCheckLine
end
function CFDSand:mergepixel(x,y,color)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local v = self.vel + x + w * y
	v[0].y = v[0].y - 1
end
function CFDSand:clearBlob(blob)
	local app = self.app
	local w, h = app.sandSize:unpack()
	local clearedCount = 0
	for _,int in ipairs(blob) do
		local iw = int.x2 - int.x1 + 1
		clearedCount = clearedCount + iw
		ffi.fill(app.sandTex.image.buffer + 4 * (int.x1 + w * int.y), 4 * iw)
		for k=0,4*iw-1 do
			app.flashTex.image.buffer[k + 4 * (int.x1 + w * int.y)] = 0xff
			self.vel[k + 4 * (int.x1 + w * int.y)] = vec2f()
		end
	end
	return clearedCount
end
function CFDSand:flipBoard()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local p1 = ffi.cast('int32_t*', app.sandTex.image.buffer)
	local p2 = p1 + w * h - 1
	local v1 = ffi.cast('vec2f_t*', self.vel)
	local v2 = v1 + w * h - 1
	for j=0,bit.rshift(h,1)-1 do
		for i=0,w-1 do
			p1[0], p2[0] = p2[0], p1[0]
			p1 = p1 + 1
			p2 = p2 - 1
			v1[0], v2[0] = v2[0], v1[0]
			v1 = v1 + 1
			v2 = v2 - 1
		end
	end
end

SandModel.subclasses = table{
	AutomataSand,
	SPHSand,
	--CFDSand,	-- crashing and doing nothing new
}
SandModel.subclassNames = SandModel.subclasses:mapi(function(cl) return cl.name end)

return SandModel
