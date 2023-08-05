local ffi = require 'ffi'
local math = require 'ext.math'
local SandModel = require 'sand-attack.sandmodel.sandmodel'

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
				elseif app.rng() < app.playcfg.toppleChance then
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

return CFDSand
