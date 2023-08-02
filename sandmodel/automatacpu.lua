local ffi = require 'ffi'
local SandModel = require 'sand-attack.sandmodel.sandmodel'

local AutomataCPU = SandModel:subclass()

AutomataCPU.name = 'Automata CPU'

function AutomataCPU:update()
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
function AutomataCPU:clearBlobHorz(blob)
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

function AutomataCPU:flipBoard()
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

return AutomataCPU 
