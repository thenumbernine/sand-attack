#!/usr/bin/env luajit
local ffi = require 'ffi'
local template = require 'template'
local table = require 'ext.table'
local class = require 'ext.class'
local math = require 'ext.math'
local string = require 'ext.string'
local range = require 'ext.range'
local gl = require 'gl'
local sdl = require 'ffi.sdl'
local Image = require 'image'
local GLTex2D = require 'gl.tex2d'
local glreport = require 'gl.report'
local vec2i = require 'vec-ffi.vec2i'
local vec3f = require 'vec-ffi.vec3f'
local vec4f = require 'vec-ffi.vec4f'
local getTime = require 'ext.timer'.getTime
local ig = require 'imgui'
local Audio = require 'audio'
local AudioSource = require 'audio.source'
local AudioBuffer = require 'audio.buffer'

-- board size is 80 x 144 visible
-- piece is 4 blocks arranged
-- blocks are 8 x 8
local voxelsPerBlock = 8	-- original
--local voxelsPerBlock = 16
local pieceSizeInBlocks = vec2i(4,4)
local pieceSize = pieceSizeInBlocks * voxelsPerBlock

local baseColors = table{
	vec3f(1,0,0),
	vec3f(0,1,0),
	vec3f(0,0,1),
	vec3f(1,1,0),
	vec3f(1,0,1),
	vec3f(0,1,1),
	vec3f(1,1,1),
}
-- ... but not all 8 bit alpha channels are really 8 bits ...

local dontCheck = false	-- don't ever ever check for lines.  used for fps testing the sand topple simulation.
local showFPS = false
local useAudio = true

local updateInterval = 1/60
--local updateInterval = 1/120
--local updateInterval = 0

local ticksToFall = 5


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

local Player = class()

function Player:init(args)
	self.index = args.index
	self.app = args.app

	self.keyPress = {}
	self.keyPressLast = {}

	if self.index == 1 then
		self.keys = {
			up = sdl.SDLK_UP,
			down = sdl.SDLK_DOWN,
			left = sdl.SDLK_LEFT,
			right = sdl.SDLK_RIGHT,
		}
	elseif self.index == 2 then
		self.keys = {
			up = ('w'):byte(),
			down = ('s'):byte(),
			left = ('a'):byte(),
			right = ('d'):byte(),
		}
	end
	assert(self.keys, "failed to find key mapping for player "..self.index)
	self.pieceTex, self.pieceImage = makeImageAndTex(pieceSize)
end

function Player:handleKeyUpDown(sym, down)
	for k,v in pairs(self.keys) do
		if sym == v then
			self.keyPress[k] = down
		end
	end
end

local App = require 'imguiapp.withorbit'()

App.title = 'Sand Tetris'

App.maxAudioDist = 10

function App:initGL(...)
	App.super.initGL(self, ...)

	gl.glClearColor(.5, .5, .5, 1)
	gl.glAlphaFunc(gl.GL_GREATER, 0)

	math.randomseed(os.time())

	self.view.ortho = true
	self.view.orthoSize = .5
	self.view.orbit:set(.5, .5, 0)
	self.view.pos:set(.5, .5, 10)

	self.numPlayers = 1
	self.numColors = 4
	self.numNextPieces = 9
	self.toppleChance = 1

	self.nextSandSize = vec2i(80, 144)	-- original:
	--self.nextSandSize = vec2i(160, 200)
	--self.nextSandSize = vec2i(160, 288)
	--self.nextSandSize = vec2i(80, 360)
	--self.nextSandSize = vec2i(512, 512)


	--[[
	image's getBlobs is a mess... straighten it out
	should probably be a BlobGetter() class which holds the context, classify callback, results, etc.
	--]]
	self.getBlobCtx = {
		classify = function(p) return p[3] end,	-- classify by alpha channel
	}

	self.sounds = {}

	self.audio = Audio()
	self.audioSources = table()
	self.audioSourceIndex = 0
	self.audio:setDistanceModel'linear clamped'
	for i=1,31 do	-- 31 for DirectSound, 32 for iphone, infinite for all else?
		local src = AudioSource()
		src:setReferenceDistance(self.view.orthoSize)
		src:setMaxDistance(self.maxAudioDist)
		src:setRolloffFactor(1)
		self.audioSources[i] = src
	end

	if useAudio then
		self.audioConfig = {
			effectVolume = 1,
			backgroundVolume = .3,
		}

		self.bgMusicFiles = table{
			'music/Desert-City.ogg',
			'music/Exotic-Plains.ogg',
			'music/Ibn-Al-Noor.ogg',
			'music/Market_Day.ogg',
			'music/Return-of-the-Mummy.ogg',
			'music/temple-of-endless-sands.ogg',
			'music/wombat-noises-audio-the-legend-of-narmer.ogg',
		}
		self.bgMusicFileName = self.bgMusicFiles:pickRandom()
		if self.bgMusicFileName then
			self.bgMusic = self:loadSound(self.bgMusicFileName)
			self.bgAudioSource = AudioSource()
			self.bgAudioSource:setBuffer(self.bgMusic)
			self.bgAudioSource:setLooping(true)
			self.bgAudioSource:setGain(self.audioConfig.backgroundVolume)
			self.bgAudioSource:play()
		end
	end
	
	self:reset()

	glreport'here'
end

function App:loadSound(filename)
	if not filename then error("warning: couldn't find sound file "..searchfilename) end

	local sound = self.sounds[filename]
	if not sound then
		sound = AudioBuffer(filename)
		self.sounds[filename] = sound
	end
	return sound
end

function App:getNextAudioSource()
	if #self.audioSources == 0 then return end
	local startIndex = self.audioSourceIndex
	repeat
		self.audioSourceIndex = self.audioSourceIndex % #self.audioSources + 1
		local source = self.audioSources[self.audioSourceIndex]
		if not source:isPlaying() then
			return source
		end
	until self.audioSourceIndex == startIndex
end

function App:playSound(name, volume, pitch)
	if not useAudio then return end
	local source = self:getNextAudioSource()
	if not source then
		print('all audio sources used')
		return
	end

	local sound = self:loadSound(name)
	source:setBuffer(sound)
	source.volume = volume	-- save for later
	source:setGain((volume or 1) * self.audioConfig.effectVolume)
	source:setPitch(pitch or 1)
	source:setPosition(0, 0, 0)
	source:setVelocity(0, 0, 0)
	source:play()

	return source
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

function App:reset()
	self.sandSize = vec2i(self.nextSandSize)

	local w, h = self.sandSize:unpack()


	-- I only really need to recreate the sand & flash texs if the board size changes ...
	self.sandTex, self.sandImage = makeImageAndTex(self.sandSize)
	self.flashTex, self.flashImage = makeImageAndTex(self.sandSize)

	-- and I only really need to recreate these if the piece size changes ...
	self.rotPieceTex, self.rotPieceImage = makeImageAndTex(pieceSize)
	self.nextPieces = range(self.numNextPieces):mapi(function(i)
		local tex = makeImageAndTex(pieceSize)
		return {tex=tex}
	end)


	ffi.fill(self.sandTex.image.buffer, 4 * w * h)
	assert(self.sandTex.data == self.sandTex.image.buffer)
	self.sandTex:bind():subimage():unbind()

	-- populate # colors
	while #baseColors < 255 do
		baseColors:insert(vec3f():map(function() return math.random() end):normalize())
	end
	self.gameColors = table(self.nextColors)		-- colors used now
	while #self.gameColors < self.numColors do
		self.gameColors[#self.gameColors+1] = baseColors[#self.gameColors+1]
	end
	self.nextColors = table(self.gameColors)		-- colors used in next game

	self.players = range(self.numPlayers):mapi(function(i)
		return Player{index=i, app=self}
	end)

	-- populate the nextpieces via rotation
	for i=1,#self.nextPieces do
		self:newPiece(self.players[1])
	end
	-- populate the players pieces
	for _,player in ipairs(self.players) do
		self:newPiece(player)
	end

	self.lastUpdateTime = getTime()
	self.gameTime = 0
	self.fallTick = 0
	self.flashTime = -math.huge
	self.score = 0
end

function App:populatePiece(args)
	local srcimage = pieceImages:pickRandom()
	local colorIndex = math.random(#self.gameColors)
	local color = self.gameColors[colorIndex]
	local alpha = math.floor(colorIndex/#self.gameColors*0xff)
	alpha = bit.lshift(alpha, 24)
	local srcp = ffi.cast('uint32_t*', srcimage.buffer)
	local dstp = ffi.cast('uint32_t*', args.tex.image.buffer)
	for j=0,pieceSize.y-1 do
		for i=0,pieceSize.x-1 do
			local u = i % voxelsPerBlock + .5
			local v = j % voxelsPerBlock + .5
			local c = math.max(
				math.abs(u - voxelsPerBlock/2),
				math.abs(v - voxelsPerBlock/2)
			) / (voxelsPerBlock/2)
			local k = i + pieceSize.x * j
			if srcp[0] ~= 0 then
				local l = math.random() * .25 + .75
				l = l * (.25 + .75 * math.sqrt(1 - c*c))
				dstp[0] = bit.bor(
					math.floor(l * color.x * 255),
					bit.lshift(math.floor(l * color.y * 255), 8),
					bit.lshift(math.floor(l * color.z * 255), 16),
					alpha
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

function App:newPiece(player)
	local w, h = self.sandSize:unpack()

	local lastPiece = self.nextPieces:last()
	-- cycle pieces
	do
		local tex = player.pieceTex
		local np1 = self.nextPieces[1]
		player.pieceTex = np1.tex
		for i=1,#self.nextPieces-1 do
			local np = self.nextPieces[i]
			local np2 = self.nextPieces[i+1]
			np.tex = np2.tex
		end
		lastPiece.tex = tex
	end
	self:populatePiece(lastPiece)

	--]]
	self:updatePieceTex(player)
	player.piecePos = vec2i(bit.rshift(w-pieceSize.x,1), h-1)
	player.pieceLastPos = vec2i(player.piecePos)
	if self:testPieceMerge(player) then
		print("YOU LOSE!!!")
		-- TODO popup, delay, scoreboard, reset, whatever
	end
end

function App:updatePieceTex(player)
	-- while we're here, find the first and last cols with content
	for _,info in ipairs{
		{0,pieceSize.x-1,1, 'pieceColMin'},
		{pieceSize.x-1,0,-1, 'pieceColMax'},
	} do
		local istart, iend, istep, ifield = table.unpack(info)
		for i=istart,iend,istep do
			local found
			for j=0,pieceSize.y-1 do
				if ffi.cast('int*', player.pieceTex.image.buffer)[i + pieceSize.x * j] ~= 0 then
					found = true
					break
				end
			end
			if found then
				player[ifield] = i
				break
			end
		end
	end
	player.pieceTex:bind():subimage()
end

function App:rotatePiece(player)
	if not player.pieceTex then return end
	for j=0,pieceSize.x-1 do
		for i=0,pieceSize.y-1 do
			for ch=0,3 do
				self.rotPieceTex.image.buffer[ch + 4 * (i + pieceSize.x * j)]
				= player.pieceTex.image.buffer[ch + 4 * ((pieceSize.x - 1 - j) + pieceSize.x * i)]
			end
		end
	end
	player.pieceTex, self.rotPieceTex = self.rotPieceTex, player.pieceTex
	self:updatePieceTex(player)
	self:constrainPiecePos(player)
end

function App:constrainPiecePos(player)
	-- TODO check blit and don't move if any pixels are oob
	local w, h = self.sandSize:unpack()
	if player.piecePos.x < -player.pieceColMin then player.piecePos.x = -player.pieceColMin end
	if player.piecePos.x > w-1-player.pieceColMax then
		player.piecePos.x = w-1-player.pieceColMax
	end
end

local vtxs = {
	{0,0},
	{1,0},
	{1,1},
	{0,1},
}

function App:testPieceMerge(player)
	local w, h = self.sandSize:unpack()
	for j=0,pieceSize.y-1 do
		for i=0,pieceSize.x-1 do
			local k = i + pieceSize.x * j
			local color = ffi.cast('int*', player.pieceTex.image.buffer)[k]
			if color ~= 0 then
				local x = player.piecePos.x + i
				local y = player.piecePos.y + j
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

	--[[ fast-forward to catch up? messes up with pause too
	self.lastUpdateTime = self.lastUpdateTime + updateInterval
	--]]
	-- [[ stutter
	self.lastUpdateTime = thisTime
	--]]
	self.gameTime = self.gameTime + updateInterval

	local needsCheck = false

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
					needsCheck = true
				-- hmm symmetry? check left vs right first?
				elseif math.random() < self.toppleChance then
					-- 50/50 check left then right, vs check right then left
					if math.random(2) == 2 then
						if i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							needsCheck = true
						elseif i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							needsCheck = true
						end
					else
						if i < w-1 and p[-w+1] == 0 then
							p[0], p[-w+1] = p[-w+1], p[0]
							needsCheck = true
						elseif i > 0 and p[-w-1] == 0 then
							p[0], p[-w-1] = p[-w-1], p[0]
							needsCheck = true
						end
					end
				end
			end
			p = p + istep
		end
		prow = prow + w
	end

	for _,player in ipairs(self.players) do
		player.pieceLastPos:set(player.piecePos:unpack())
	end

	-- now draw the shape over the sand
	-- test piece for collision with sand
	-- if it collides then merge it
	local movedx = 1
	local movedy = 3
	for _,player in ipairs(self.players) do
		-- TODO key updates at higher interval than drop rate ...
		-- but test collision for both
		if player.keyPress.left then
			player.piecePos.x = player.piecePos.x - movedx
		end
		if player.keyPress.right then
			player.piecePos.x = player.piecePos.x + movedx
		end
		self:constrainPiecePos(player)
		if player.keyPress.down then
			player.piecePos.y = player.piecePos.y - movedy
		end
		if player.keyPress.up and not player.keyPressLast.up then
			self:rotatePiece(player)
		end
	end

	self.fallTick = self.fallTick + 1
	if self.fallTick >= ticksToFall then
		self.fallTick = 0
		for _,player in ipairs(self.players) do
			player.piecePos.y = player.piecePos.y - movedx
		end
	end

	for _,player in ipairs(self.players) do
		local merge
		if player.piecePos.y <= 0 then
			player.piecePos.y = 0
			merge = true
		else
			if self:testPieceMerge(player) then
				player.piecePos:set(player.pieceLastPos:unpack())
				merge = true
			end
		end
		if merge then
			self:playSound'sfx/place.wav'
			needsCheck = true
			for j=0,pieceSize.y-1 do
				for i=0,pieceSize.x-1 do
					local k =  i + pieceSize.x * j
					local color = ffi.cast('int*', player.pieceTex.image.buffer)[k]
					if color ~= 0 then
						local x = player.piecePos.x + i
						local y = player.piecePos.y + j
						if x >= 0 and x < w
						and y >= 0 and y < h
						and ffi.cast('int*', self.sandTex.image.buffer)[x + w * y] == 0
						then
							ffi.cast('int*', self.sandTex.image.buffer)[x + w * y] = color
						end
					end
				end
			end

			self:newPiece(player)
		end
	end

	if dontCheck then needsCheck = false end

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

	if needsCheck then
		local anyCleared
		local clearedCount = 0
		local blobs = self.sandTex.image:getBlobs(self.getBlobCtx)
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
		end
		if clearedCount ~= 0 then
			anyCleared = true
			self.score = self.score + clearedCount
		end
		if anyCleared then
			self:playSound'sfx/line.wav'
			self.flashTex:bind():subimage()
			self.flashTime = self.gameTime
		end
	end

	for _,player in ipairs(self.players) do
		for k,v in pairs(player.keyPress) do
			player.keyPressLast[k] = v
		end
	end
end

function App:update(...)
	local t =
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	local w, h = self.sandSize:unpack()

	if not self.paused then
		self:updateGame()
	end

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
	for _,player in ipairs(self.players) do
		if player.pieceTex then
			player.pieceTex:bind()
			gl.glEnable(gl.GL_ALPHA_TEST)
			gl.glBegin(gl.GL_QUADS)
			for _,v in ipairs(vtxs) do
				local x,y = table.unpack(v)
				gl.glTexCoord2f(x,y)
				gl.glVertex2f(
					((player.piecePos.x + x * pieceSize.x) / w - .5) * s + .5,
					(player.piecePos.y + y * pieceSize.y) / h
				)
			end
			gl.glEnd()
			gl.glDisable(gl.GL_ALPHA_TEST)
			player.pieceTex:unbind()
			gl.glColor3f(1,1,1)
		end
	end

	-- draw flashing background if necessary
	local flashDuration = 1
	local numFlashes = 5
	local flashDt = self.gameTime - self.flashTime
	if flashDt < flashDuration then
		self.wasFlashing = true
		gl.glEnable(gl.GL_ALPHA_TEST)
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
		gl.glDisable(gl.GL_ALPHA_TEST)
	elseif self.wasFlashing then
		self.wasFlashing = false
		ffi.fill(self.flashTex.image.buffer, 4 * w * h)
		assert(self.flashTex.data == self.flashTex.image.buffer)
		self.flashTex:bind():subimage():unbind()
	end

	local aspectRatio = self.width / self.height
	local s = w / h
	local nextPieceSize = .1
	for i=#self.nextPieces,1,-1 do
		local it = self.nextPieces[i]
		local dy = #self.nextPieces == 1 and 0 or (1 - nextPieceSize)/(#self.nextPieces-1)
		dy = math.min(dy, nextPieceSize * 1.1)
		it.tex:bind()
		gl.glBegin(gl.GL_QUADS)
		for _,v in ipairs(vtxs) do
			local x,y = table.unpack(v)
			gl.glTexCoord2f(x,y)
			gl.glVertex2f(
				.5 + aspectRatio*.5 + (x - 1) * nextPieceSize,
				1 - ((i-1) * dy + y * nextPieceSize)
			)
		end
		gl.glEnd()
	end

	GLTex2D:disable()

	App.super.update(self, ...)
	glreport'here'


	if showFPS then
		self.fpsSampleCount = self.fpsSampleCount + 1
		local thisTime = getTime()
		if thisTime - self.lastFrameTime >= 1 then
			local deltaTime = thisTime - self.lastFrameTime
			local fps = self.fpsSampleCount / deltaTime
			print(fps)
			self.lastFrameTime = thisTime
			self.fpsSampleCount = 0
		end
	end
end
App.lastFrameTime = 0
App.fpsSampleCount = 0

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

function App:event(e, ...)
	App.super.event(self, e, ...)
	if e.type == sdl.SDL_KEYDOWN
	or e.type == sdl.SDL_KEYUP
	then
		local down = e.type == sdl.SDL_KEYDOWN
		for _,player in ipairs(self.players) do
			player:handleKeyUpDown(e.key.keysym.sym, down)
		end
		--[[
		if e.key.keysym.sym == sdl.SDLK_LEFT then
			self.keyPress.left = down
		elseif e.key.keysym.sym == sdl.SDLK_RIGHT then
			self.keyPress.right = down
		elseif e.key.keysym.sym == sdl.SDLK_DOWN then
			self.keyPress.down = down
		elseif e.key.keysym.sym == sdl.SDLK_UP then
			if down then self:rotatePiece() end
		else
		--]]
		--[[
		if e.key.keysym.sym == ('r'):byte() then
			if down then self:reset() end
		else
		--]]
		if e.key.keysym.sym == ('f'):byte() then
			if down then self:flipBoard() end
		end
	end
end

local function modalBegin(title, t, k)
	return ig.luatableBegin(title, t, k, bit.bor(
			ig.ImGuiWindowFlags_NoTitleBar,
			ig.ImGuiWindowFlags_NoResize,
			ig.ImGuiWindowFlags_NoCollapse,
			ig.ImGuiWindowFlags_AlwaysAutoResize,
			ig.ImGuiWindowFlags_Modal,
		0))
end

local tmpcolor = ig.ImVec4()
local modalsOpened = {}
App.paused = false
function App:updateGUI()
	-- [[
	ig.igSetNextWindowPos(ig.ImVec2(0, 0), 0, ig.ImVec2())
	ig.igSetNextWindowSize(ig.ImVec2(150, -1), 0)
	ig.igBegin('score', nil, bit.bor(
		ig.ImGuiWindowFlags_NoMove,
		ig.ImGuiWindowFlags_NoResize,
		ig.ImGuiWindowFlags_NoCollapse,
		ig.ImGuiWindowFlags_NoDecoration
	))
	--]]
	--[[
	ig.igBegin('cfg', nil, 0)
	--]]


	ig.igText('score: '..tostring(self.score))

	ig.luatableTooltipInputInt('num players', self, 'numPlayers')

	ig.luatableTooltipInputInt('num next pieces', self, 'numNextPieces')

	self.colortest = self.colortest or ig.ImVec4()
	--ig.igColorPicker3('test', self.colortest.s, 0)
	if ig.igButton'+' then
		self.numColors = self.numColors + 1
		self.nextColors = baseColors:sub(1, self.numColors)
	end
	ig.igSameLine()
	if self.numColors > 1 and ig.igButton'-' then
		self.numColors = self.numColors - 1
		self.nextColors = baseColors:sub(1, self.numColors)
	end
	ig.igSameLine()

	for i=1,self.numColors do
		local c = self.nextColors[i]
		tmpcolor.x = c.x
		tmpcolor.y = c.y
		tmpcolor.z = c.z
		tmpcolor.w = 1
		if ig.igColorButton('color '..i, tmpcolor) then
			modalsOpened.colorPicker = true
			self.paused = true
			self.currentColorEditing = i
		end
		if i % 6 ~= 4 and i < self.numColors then
			ig.igSameLine()
		end
	end

	ig.luatableTooltipInputInt('board width', self.nextSandSize, 'x')
	ig.luatableTooltipInputInt('board height', self.nextSandSize, 'y')
	ig.luatableTooltipSliderFloat('topple chance', self, 'toppleChance', 0, 1)

	if ig.igButton'New Game' then
		self:reset()
	end

	local url = 'https://github.com/thenumbernine/sand-tetris'
	if ig.igButton'about' then
		if ffi.os == 'Windows' then
			os.execute('explorer "'..url..'"')
		elseif ffi.os == 'OSX' then
			os.execute('open "'..url..'"')
		else
			os.execute('xdg-open "'..url..'"')
		end
		print'clicked'
	end
	if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
		ig.igSetMouseCursor(ig.ImGuiMouseCursor_Hand)
		ig.igBeginTooltip()
		ig.igText('by Christopher Moore')
		ig.igText('click to go to')
		ig.igText(url)
		ig.igEndTooltip()
	end

	if useAudio and ig.igButton'Audio...' then
		modalsOpened.audio = true
		self.paused = true
	end

	if ig.igButton(self.paused and 'resume' or 'pause') then
		self.paused = not self.paused
	end

	ig.igEnd()

	if modalsOpened.audio then
		modalBegin('Audio', nil)
		if ig.luatableSliderFloat('fx volume', self.audioConfig, 'effectVolume', 0, 1) then
			--[[ if you want, update all previous audio sources...
			for _,src in ipairs(self.audioSources) do
				-- TODO if the gameplay sets the gain down then we'll want to multiply by their default gain
				src:setGain(audioConfig.effectVolume * src.gain)
			end
			--]]
		end
		if ig.luatableSliderFloat('bg volume', self.audioConfig, 'backgroundVolume', 0, 1) then
			self.bgAudioSource:setGain(self.audioConfig.backgroundVolume)
		end
		if ig.igButton'Done' then
			modalsOpened.audio = false
			self.paused = false
		end
		ig.igEnd()
	end
	if modalsOpened.colorPicker then
		modalBegin('Color', nil)
		ig.igText'colors updated upon new game'
		if #self.nextColors > 1 then
			if ig.igButton'Delete' then
				self.nextColors:remove(self.currentColorEditing)
				self.numColors = self.numColors - 1
				modalsOpened.colorPicker = false
				self.paused = false
			end
		end
		if ig.igColorPicker3('edit color', self.nextColors[self.currentColorEditing].s, 0) then
			-- TODO update the other pieces in realtime?
			-- or nah?
		end
		if ig.igButton'Done' then
			modalsOpened.colorPicker = false
			self.paused = false
		end
		ig.igEnd()
	end
end

--[[ if you're not using the autorelease
function App:exit()
	self.audio:shutdown()
	App.super.exit(self)
end
--]]

return App():run()
