local ffi = require 'ffi'
local math = require 'ext.math'
local vector = require 'ffi.cpp.vector'
local vec2f = require 'vec-ffi.vec2f'
local Image = require 'image'
local ig = require 'imgui'

local SandModel = require 'sand-attack.sandmodel.sandmodel'

-- TODO put this in ext.math
--local DBL_EPSILON = 2.220446049250313080847e-16
local FLT_EPSILON = 1.1920928955078125e-7

ffi.cdef[[
typedef struct {
	vec2f pos;
	vec2f vel;
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
	self.vel = ffi.new('vec3f[?]', w * h)
end

function SPHSand:checkClearBlobs()
	local app = self.app
	local w, h = app.sandSize:unpack()
	ffi.fill(self.currentClearImage.buffer, 4 * w * h)
	return SPHSand.super.checkClearBlobs(self)
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
				if app.rng() < app.cfg.toppleChance then
					-- hmm symmetry? check left vs right first?
					-- 50/50 check left then right, vs check right then left
					if app.rng(2) == 2 then
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
	ffi.fill(self.vel, 0, ffi.sizeof'vec3f' * w * h)
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
			g.vel.y = g.vel.y + (app.rng() - .5) * pushForceTimesDT
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
	--local vel = app.rng() * 150 * (vec2f(0,-1) + (vec2f(x+.5,y+.5)-vec2f(app.pieceSize:unpack())*.5) / tonumber(app.pieceSize.x))
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

return SPHSand 
