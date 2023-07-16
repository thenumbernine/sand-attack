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
	local function make()
		local f = ffi.new('float[?]', w * h)
		ffi.fill(f, ffi.sizeof'float' * w * h)
		return f
	end
	self.u = make()
	self.v = make()
	self.uprev = make()
	self.vprev = make()
	--[[ instead of rho and rhoprev I want sandtex ...
	self.rho = make()
	self.rhoprev = make()
	--]]
	--[[ hmm, how easy would this be to fit into the current framework?
	self.sandTexPrev = app:makeTexWithImage(app.sandSize)
	--]]
	-- [[ I'll try for this way
	self.r, self.rprev = make(), make()
	self.g, self.gprev = make(), make()
	self.b, self.bprev = make(), make()
	self.a, self.aprev = make(), make()
	--]]
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
	local sandip = ffi.cast('int32_t*', app.sandTex.image.buffer)
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

	-- [[  copy color to our float buffers
	-- TODO just use sandTex
	for j=0,h-1 do
		for i=0,w-1 do
			self.r[i + w * j] = app.sandTex.image.buffer[0 + 4 * (i + w * j)]
			self.g[i + w * j] = app.sandTex.image.buffer[1 + 4 * (i + w * j)]
			self.b[i + w * j] = app.sandTex.image.buffer[2 + 4 * (i + w * j)]
			self.a[i + w * j] = app.sandTex.image.buffer[3 + 4 * (i + w * j)]
		end
	end
	--]]

	assert(dt)
	local visc = .01
	local diff = .05
	self:velocityStep(visc, dt)
	self:densityStep(diff, dt)

	-- [[  copy back
	for j=0,h-1 do
		for i=0,w-1 do
			app.sandTex.image.buffer[0 + 4 * (i + w * j)] = math.clamp(self.r[i + w * j], 0, 255)
			app.sandTex.image.buffer[1 + 4 * (i + w * j)] = math.clamp(self.g[i + w * j], 0, 255)
			app.sandTex.image.buffer[2 + 4 * (i + w * j)] = math.clamp(self.b[i + w * j], 0, 255)
			app.sandTex.image.buffer[3 + 4 * (i + w * j)] = math.clamp(self.a[i + w * j], 0, 255)
		end
	end
	--]]

	return needsCheckLine
end
function CFDSand:densityStep(diff, dt)
	--self:addSource()
	--[[
	self.rho, self.rhoprev = self.rhoprev, self.rho
	self:diffuse(0, self.rho, self.rhoprev, diff, dt)
	self.rho, self.rhoprev = self.rhoprev, self.rho
	self:advect(0, self.rho, self.rhoprev, self.u, self.v, dt)
	--]]
	-- [[
	self.r, self.rprev = self.rprev, self.r
	self:diffuse(0, self.r, self.rprev, diff, dt)
	self.r, self.rprev = self.rprev, self.r
	self:advect(0, self.r, self.rprev, self.u, self.v, dt)
	
	self.g, self.gprev = self.gprev, self.g
	self:diffuse(0, self.g, self.gprev, diff, dt)
	self.g, self.gprev = self.gprev, self.g
	self:advect(0, self.g, self.gprev, self.u, self.v, dt)
	
	self.b, self.bprev = self.bprev, self.b
	self:diffuse(0, self.b, self.bprev, diff, dt)
	self.b, self.bprev = self.bprev, self.b
	self:advect(0, self.b, self.bprev, self.u, self.v, dt)
	
	self.a, self.aprev = self.aprev, self.a
	self:diffuse(0, self.a, self.aprev, diff, dt)
	self.a, self.aprev = self.aprev, self.a
	self:advect(0, self.a, self.aprev, self.u, self.v, dt)
	--]]
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
	-- Jacobi implementation of Backward-Euler integration...
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
function CFDSand:advect(dir, dst, src, u, v, dt)
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
			local s0 = 1 - s1
			
			local y = j - dt_dx * v[i + w * j]
			y = math.clamp(y, .5, h + .5)
			local j0 = math.floor(y)
			local j1 = j0 + 1
			local t1 = y - j0
			local t0 = 1 - t1	
		
			dst[i + w * j] = s0 * (t0 * src[i0 + w * j0] + t1 * src[i0 + w * j1])
							+ s1 * (t0 * src[i1 + w * j0] + t1 * src[i1 + w * j1])
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
	v[0] = v[0] - 1
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
			self.u[k + 4 * (int.x1 + w * int.y)] = 0
			self.v[k + 4 * (int.x1 + w * int.y)] = 0
		end
	end
	return clearedCount
end
function CFDSand:flipBoard()
	local app = self.app
	local w, h = app.sandSize:unpack()
	local p1 = ffi.cast('int32_t*', app.sandTex.image.buffer)
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
end

SandModel.subclasses = table{
	AutomataSand,
	SPHSand,
	CFDSand,
}
SandModel.subclassNames = SandModel.subclasses:mapi(function(cl) return cl.name end)

return SandModel
