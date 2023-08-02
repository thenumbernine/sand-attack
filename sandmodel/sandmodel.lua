local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local GLFBO = require 'gl.fbo'
local ig = require 'imgui'

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
	self.fbo = GLFBO{width=w, height=h}
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

--[=[ tracking columns left to right, seeing what connects
-- TODO still some kinks in it

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
			..'cl='..self.cl..','
			..'blob='..self.blob
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

	local blobs = ctx.blobs
	if not blobs then
		blobs = table()
		ctx.blobs = blobs
	else
		for k in pairs(blobs) do blobs[k] = nil end
	end
	local nextblobindex = 1

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

		--[[ hmm there is always a chance that intervals loop back ...
		if x > 0 then
			local colL = colregions[x]	-- cuz colregions is 1-based
			local colR = col
			if self:pruneCols(colL, colR) then return 0 end
		end
		--]]
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
		-- before doing any blob detection, prune our col with the next to see if it gets eliminated
		local col = colregions[x+1]
		--[[ hmm there is always a chance that intervals loop back ...
		if x > 0 then
			local colL = colregions[x]
			if self:pruneCols(colL, col) then return 0 end
		end
		--]]
		-- if col was empty then we've returned by now

		if x == w-1 then
			-- init blobs
			for i=0,col.size-1 do
				local int = col.v[i]
				local blob = BlobCol()
				blobs[nextblobindex] = blob
				int.blob = nextblobindex
				nextblobindex = nextblobindex + 1
				blob:insert(int)
				blob.cl = int.cl
			end
		else
			local lastcol = colregions[x+2]
			if col.size > 0 then
				for i=0,col.size-1 do
					local int = col.v[i]
					for j=0,lastcol.size-1 do
						local lint = lastcol.v[j]
						if lint.blob <= -1 then
							print("col["..x.."] previous-col interval had no blob "..lint.blob)
							error'here'
						end
						if lint.y1 <= int.y2
						and lint.y2 >= int.y1
						then
							-- touching - make sure they are in the same blob
							if int.blob ~= lint.blob
							and int.cl == lint.cl
							then
								local oldblobindex = int.blob
								if oldblobindex > -1 then
									local oldblob = blobs[oldblobindex]
									-- remove the old blob
									blobs[oldblobindex] = nil

									for _,oint in ipairs(oldblob) do
										oint.blob = lint.blob
									end
									blobs[lint.blob]:append(oldblob)
								else
									int.blob = lint.blob
									blobs[lint.blob]:insert(int)
								end
							end
						end
					end
					if int.blob == -1 then
						local blob = BlobCol()
						blobs[nextblobindex] = blob
						int.blob = nextblobindex
						nextblobindex = nextblobindex + 1
						blob:insert(int)
						blob.cl = int.cl
					end
				end
			end
		end
		for i=0,col.size-1 do
			if col.v[i].blob <= -1 then
				print("on col "..x.." failed to assign all intervals to blobs")
			end
		end
	end

	for _,blobindex in ipairs(table.keys(blobs)) do
		local blob = blobs[blobindex]
		-- if the blob doesn't contain all columns ...
		if #blob < w then
			-- remove all cols that point to this blob
			-- means cycling through all cols o this blob
			-- means TODO blobs should key by col first, then be a vector of intervals next
			for x=1,w do
				local col = colregions[x]
				for j=col.size-1,0,-1 do
					local int = col.v[j]
					if int.blob == blobindex then
						col:erase(col.v+j,col.v+j+1)
					end
				end
			end
			blobs[blobindex] = nil
		else
			blob.debugColor = bit.bor(
				math.random(0,255),
				bit.lshift(math.random(0,255), 8),
				bit.lshift(math.random(0,255), 16),
				0xff000000
			)
		end
	end

	if #blobs == 0 then return 0 end

	-- now that we're here we made it
	--print('found connection with', #blobs,'blobs')
	-- debug print
	self.numBlobs = #blobs

	local p = ffi.cast('uint32_t*', app.flashTex.image.buffer)
	ffi.fill(p, 4*w*h)
	for x=0,w-1 do
		local col = colregions[x+1]
		for i=0,col.size-1 do
			local int = col.v[i]
			for y=int.y1,int.y2 do
assert(blobs[int.blob] and blobs[int.blob].debugColor, require 'ext.tolua'{blobs=blobs, int=int})
				p[x + w * y] = blobs[int.blob].debugColor
				--p[x + w * y] = 0xffffffff
			end
		end
	end
	
	app.flashTex:bind():subimage()
	app.lastLineTime = app.gameTime

	-- TODO count blob size
	local clearedCount = 0

	return clearedCount
end

function SandModel:updateDebugGUI()
	ig.igText('Num Blobs: '..tostring(self.numBlobs))
end
--]=]

return SandModel 
