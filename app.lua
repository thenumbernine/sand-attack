local ffi = require 'ffi'
local sdl = require 'ffi.sdl'
local table = require 'ext.table'
local file = require 'ext.file'
local class = require 'ext.class'
local math = require 'ext.math'
local string = require 'ext.string'
local range = require 'ext.range'
local fromlua = require 'ext.fromlua'
local tolua = require 'ext.tolua'
local matrix = require 'matrix.ffi'
local Image = require 'image'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local GLArrayBuffer = require 'gl.arraybuffer'
local glreport = require 'gl.report'
local vec2i = require 'vec-ffi.vec2i'
local vec2f = require 'vec-ffi.vec2f'
local vec3f = require 'vec-ffi.vec3f'
local getTime = require 'ext.timer'.getTime
local ig = require 'imgui'
local ImGuiApp = require 'imguiapp'
local Audio = require 'audio'
local AudioSource = require 'audio.source'
local AudioBuffer = require 'audio.buffer'
local Player = require 'sandtetris.player'
local GameState = require 'sandtetris.gamestate'

local App = class(ImGuiApp)

App.useAudio = true	-- set to false to disable audio altogether
App.showFPS = false	-- show fps in gui
local dontCheckForLinesEver = false	-- means don't ever ever check for lines.  used for fps testing the sand topple simulation.

local updateInterval = 1/60
--local updateInterval = 1/120
--local updateInterval = 0

App.defaultColors = table{
	{1,0,0},
	{0,0,1},
	{0,1,0},
	{1,1,0},
	{1,0,1},
	{0,1,1},
	{1,1,1},
}
-- populate # colors
while #App.defaultColors < 255 do
	App.defaultColors:insert{vec3f():map(function()
		return math.random()
	end):normalize():unpack()}
end

-- ... but not all 8 bit alpha channels are really 8 bits ...


App.title = 'Samd'

-- board size is 80 x 144 visible
-- piece is 4 blocks arranged
-- blocks are 8 x 8
App.voxelsPerBlock = 8	-- original
--App.voxelsPerBlock = 16
App.pieceSizeInBlocks = vec2i(4,4)
App.pieceSize = App.pieceSizeInBlocks * App.voxelsPerBlock

App.maxAudioDist = 10

App.chainDuration = 2
App.lineFlashDuration = 1
App.lineNumFlashes = 5

App.cfgfilename = 'config.lua'

function App:initGL(...)
	App.super.initGL(self, ...)

	gl.glClearColor(.5, .5, .5, 1)
	gl.glAlphaFunc(gl.GL_GREATER, 0)


-- [[ imgui custom font
	--local fontfile = 'font/moenstrum.ttf'				-- no numbers
	--local fontfile = 'font/PixelGamer-Regular.otf'	-- no numbers
	--local fontfile = 'font/goldingots.ttf'
	local fontfile = 'font/Billow twirl Demo.ttf'
	self.fontAtlas = ig.ImFontAtlas_ImFontAtlas()
	self.font = ig.ImFontAtlas_AddFontFromFileTTF(self.fontAtlas, fontfile, 16, nil, nil)
	-- just change the font, and imgui complains that you need to call FontAtlas::Build() ...
	assert(ig.ImFontAtlas_Build(self.fontAtlas))
	-- just call FontAtlas::Build() and you just get white blobs ...
	-- is this proper behavior?  or a bug in imgui?
	-- you have to download the font texture pixel data, make a GL texture out of it, and re-upload it
	local width = ffi.new('int[1]')
	local height = ffi.new('int[1]')
	local bpp = ffi.new('int[1]')
	local outPixels = ffi.new('unsigned char*[1]')
	-- GL_LUMINANCE textures are deprecated ... khronos says use GL_RED instead ... meaning you have to write extra shaders for greyscale textures to be used as greyscale in opengl ... ugh
	--ig.ImFontAtlas_GetTexDataAsAlpha8(self.fontAtlas, outPixels, width, height, bpp)
	ig.ImFontAtlas_GetTexDataAsRGBA32(self.fontAtlas, outPixels, width, height, bpp)
	self.fontTex = GLTex2D{
		internalFormat = gl.GL_RGBA,
		--internalFormat = gl.GL_RED,
		format = gl.GL_RGBA,
		--format = gl.GL_RED,
		width = width[0],
		height = height[0],
		type = gl.GL_UNSIGNED_BYTE,
		data = outPixels[0],
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
	}
	require 'ffi.c.stdlib'	-- free()
	ffi.C.free(outPixels[0])	-- just betting here I have to free this myself ...
	ig.ImFontAtlas_SetTexID(self.fontAtlas, ffi.cast('ImTextureID', self.fontTex.id))
--]]

	-- TODO this upon every :reset, save seed, and save it in the high score as well
	math.randomseed(os.time())

	-- load config if it exists
	xpcall(function()
		self.cfg = fromlua(assert(file(self.cfgfilename):read()))
	end, function(err)
		print("failed to read config file: "..tostring(err))
	end)
	self.cfg = self.cfg or {}

	self.cfg.effectVolume = self.cfg.effectVolume or 1
	self.cfg.backgroundVolume = self.cfg.backgroundVolume or .3
	self.cfg.startLevel = self.cfg.startLevel or 1
	-- TODO this shouldn't be in the config ... should it?
	self.cfg.toppleChance = self.cfg.toppleChance or 1
	self.cfg.playerKeys = self.cfg.playerKeys or {}
	self.cfg.highscores = self.cfg.highscores or {}
	self.cfg.numColors = self.cfg.numColors or 4
	if not self.cfg.colors then
		self.cfg.colors = {}
		for i,color in ipairs(self.defaultColors) do
			self.cfg.colors[i] = {table.unpack(color)}
		end
	end

	self.numPlayers = 1
	self.numNextPieces = 3
	self.dropSpeed = 5

	self.fps = 0
	self.numSandVoxels = 0

	self.nextSandSize = vec2i(80, 144)	-- original:
	--self.nextSandSize = vec2i(160, 200)
	--self.nextSandSize = vec2i(160, 288)
	--self.nextSandSize = vec2i(80, 360)
	--self.nextSandSize = vec2i(512, 512)

	self.loseScreenDuration = 5

	self.youloseTex = GLTex2D{
		image = Image'tex/youlose.png':flip(),
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,
	}
	self.splashTex = GLTex2D{
		image = Image'tex/splash.png':flip(),
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_NEAREST,
	}

	--[[
	image's getBlobs is a mess... straighten it out
	should probably be a BlobGetter() class which holds the context, classify callback, results, etc.
	--]]
	self.getBlobCtx = {
		classify = function(p) return p[3] end,	-- classify by alpha channel
	}

	self.projMat = matrix{4,4}:zeros()
	self.mvMat = matrix{4,4}:zeros()
	self.mvProjMat = matrix{4,4}:zeros()

	local vtxbufCPU = ffi.new('float[8]', {
		0,0,
		1,0,
		1,1,
		0,1,
	})
	local vertexBuf = GLArrayBuffer{
		size = ffi.sizeof(vtxbufCPU),
		data = vtxbufCPU,
	}

	--local glslVersion = 460	-- too new?
	local glslVersion = 430
	self.displayShader = GLProgram{
		vertexCode = [[
#version ]]..glslVersion..[[

in vec2 vertex;
out vec2 texcoordv;
uniform mat4 modelViewProjMat;
void main() {
	texcoordv = vertex;
	gl_Position = modelViewProjMat * vec4(vertex, 0., 1.);
}
]],
		fragmentCode = [[
#version ]]..glslVersion..[[

in vec2 texcoordv;
out vec4 fragColor;
uniform sampler2D tex;
void main() {
	fragColor = texture(tex, texcoordv);
}
]],
		uniforms = {
			tex = 0,
		},

		attrs = {
			vertex = vertexBuf,
		},
	}:useNone()

	self.sounds = {}

	if self.useAudio then
		xpcall(function()
			self.audio = Audio()
			self.audioSources = table()
			self.audioSourceIndex = 0
			self.audio:setDistanceModel'linear clamped'
			for i=1,31 do	-- 31 for DirectSound, 32 for iphone, infinite for all else?
				local src = AudioSource()
				src:setReferenceDistance(1)
				src:setMaxDistance(self.maxAudioDist)
				src:setRolloffFactor(1)
				self.audioSources[i] = src
			end

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
				self.bgAudioSource:setGain(self.cfg.backgroundVolume)
				self.bgAudioSource:play()
			end
		end, function(err)
			print(err..'\n'..debug.traceback())
			self.audio = nil
			self.useAudio = false	-- or just test audio's existence?
		end)
	end

	self.state = GameState.SplashScreenState(self)

	self:reset()

	glreport'here'
end

-- static method
function App:makeTexWithImage(size)
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

local function makePieceImage(s)
	s = string.split(s, '\n')
	local img = Image(App.pieceSize.x, App.pieceSize.y, 4, 'unsigned char')
	ffi.fill(img.buffer, 4 * img.width * img.height)
	for j=0,App.pieceSizeInBlocks.y-1 do
		for i=0,App.pieceSizeInBlocks.x-1 do
			if s[j+1]:sub(i+1,i+1) == '#' then
				for u=0,App.voxelsPerBlock-1 do
					for v=0,App.voxelsPerBlock-1 do
						ffi.cast('uint32_t*', img.buffer)[(u + App.voxelsPerBlock * i) + img.width * (v + App.voxelsPerBlock * j)] = 0xffffffff
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
	if not self.useAudio then return end
	local source = self:getNextAudioSource()
	if not source then
		print('all audio sources used')
		return
	end

	local sound = self:loadSound(name)
	source:setBuffer(sound)
	source.volume = volume	-- save for later
	source:setGain((volume or 1) * self.cfg.effectVolume)
	source:setPitch(pitch or 1)
	source:setPosition(0, 0, 0)
	source:setVelocity(0, 0, 0)
	source:play()

	return source
end

function App:saveConfig()
	file(self.cfgfilename):write(tolua(self.cfg))
end

function App:reset()
	self:saveConfig()

	self.sandSize = vec2i(self.nextSandSize)
	local w, h = self.sandSize:unpack()

	self.loseTime = nil

	-- I only really need to recreate the sand & flash texs if the board size changes ...
	self.sandTex = self:makeTexWithImage(self.sandSize)
	self.flashTex = self:makeTexWithImage(self.sandSize)

	-- and I only really need to recreate these if the piece size changes ...
	self.rotPieceTex = self:makeTexWithImage(self.pieceSize)
	self.nextPieces = range(self.numNextPieces):mapi(function(i)
		local tex = self:makeTexWithImage(self.pieceSize)
		return {tex=tex}
	end)


	ffi.fill(self.sandTex.image.buffer, 4 * w * h)
	assert(self.sandTex.data == self.sandTex.image.buffer)
	self.sandTex:bind():subimage():unbind()

	self.gameColors = table.sub(self.cfg.colors, 1, self.cfg.numColors):mapi(function(c) return vec3f(c) end)		-- colors used now
	assert(#self.gameColors == self.cfg.numColors)	-- menu system should handle this

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
	self.lastLineTime = -math.huge
	self.score = 0
	self.lines = 0
	self.level = self.cfg.startLevel
	self.scoreChain = 0
	self:upateFallSpeed()
	self.paused = true
end

function App:upateFallSpeed()
	-- https://harddrop.com/wiki/Tetris_Worlds
	local maxSpeedLevel = 13 -- fastest level .. no faster is permitted
	local effectiveLevel = math.min(self.level, maxSpeedLevel)
	local secondsPerRow = (.8 - ((effectiveLevel-1)*.007))^(effectiveLevel-1)
	local secondsPerLine = secondsPerRow / self.voxelsPerBlock
	-- how many ticks to wait before dropping a piece
	self.ticksToFall = secondsPerLine / updateInterval
end

function App:populatePiece(args)
	local srcimage = pieceImages:pickRandom()
	local colorIndex = math.random(#self.gameColors)
	local color = self.gameColors[colorIndex]
	local alpha = math.floor(colorIndex/#self.gameColors*0xff)
	alpha = bit.lshift(alpha, 24)
	local srcp = ffi.cast('uint32_t*', srcimage.buffer)
	local dstp = ffi.cast('uint32_t*', args.tex.image.buffer)
	for j=0,self.pieceSize.y-1 do
		for i=0,self.pieceSize.x-1 do
			local u = i % self.voxelsPerBlock + .5
			local v = j % self.voxelsPerBlock + .5
			local c = math.max(
				math.abs(u - self.voxelsPerBlock/2),
				math.abs(v - self.voxelsPerBlock/2)
			) / (self.voxelsPerBlock/2)
			local k = i + self.pieceSize.x * j
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
	player.piecePos = vec2i(bit.rshift(w-self.pieceSize.x,1), h-1)
	player.pieceLastPos = vec2i(player.piecePos)
	if self:testPieceMerge(player) then
		-- but this means you can pause mid-losing ... meh
		self.loseTime = self.thisTime
	end
end

local function vec3fto4ub(v)
	return bit.bor(
		math.floor(math.clamp(v.x, 0, 1) * 255),
		bit.lshift(math.floor(math.clamp(v.y, 0, 1) * 255), 8),
		bit.lshift(math.floor(math.clamp(v.z, 0, 1) * 255), 16),
		0xff000000
	)
end

function App:updatePieceTex(player)
	-- while we're here, find the first and last cols with content
	for _,info in ipairs{
		{0,self.pieceSize.x-1,1, 'pieceColMin'},
		{self.pieceSize.x-1,0,-1, 'pieceColMax'},
	} do
		local istart, iend, istep, ifield = table.unpack(info)
		for i=istart,iend,istep do
			local found
			for j=0,self.pieceSize.y-1 do
				if ffi.cast('uint32_t*', player.pieceTex.image.buffer)[i + self.pieceSize.x * j] ~= 0 then
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

	-- [[ update the piece outline
	local outlineRadius = 5
	ffi.fill(player.pieceOutlineTex.image.buffer, 4 * self.pieceSize.x * self.pieceSize.y)
	for j=0,self.pieceSize.y-1 do
		for i=0,self.pieceSize.x-1 do
			local bestDistSq = math.huge
			for ofy=-outlineRadius,outlineRadius do
				for ofx=-outlineRadius,outlineRadius do
					local x = math.clamp(i + ofx, 0, self.pieceSize.x-1)
					local y = math.clamp(j + ofy, 0, self.pieceSize.y-1)
					if ffi.cast('uint32_t*', player.pieceTex.image.buffer)[x + self.pieceSize.x * y] ~= 0 then
						local distSq = math.max(1, ofx*ofx + ofy*ofy)
						bestDistSq = math.min(bestDistSq, distSq)
					end
				end
			end
			if bestDistSq < math.huge then
				--bestDistSq = math.sqrt(bestDistSq)
				local frac = 1 / bestDistSq
				ffi.cast('uint32_t*', player.pieceOutlineTex.image.buffer)[i + self.pieceSize.x * j] = vec3fto4ub(player.color * frac)
			end
		end
	end
	player.pieceOutlineTex:bind():subimage()
	--]]
end

function App:rotatePiece(player)
	if not player.pieceTex then return end
	for j=0,self.pieceSize.x-1 do
		for i=0,self.pieceSize.y-1 do
			for ch=0,3 do
				self.rotPieceTex.image.buffer[ch + 4 * (i + self.pieceSize.x * j)]
				= player.pieceTex.image.buffer[ch + 4 * ((self.pieceSize.x - 1 - j) + self.pieceSize.x * i)]
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
	for j=0,self.pieceSize.y-1 do
		for i=0,self.pieceSize.x-1 do
			local k = i + self.pieceSize.x * j
			local color = ffi.cast('uint32_t*', player.pieceTex.image.buffer)[k]
			if color ~= 0 then
				local x = player.piecePos.x + i
				local y = player.piecePos.y + j
				if x >= 0 and x < w
				and y >= 0 and y < h
				and ffi.cast('uint32_t*',self.sandTex.image.buffer)[x + w * y] ~= 0
				then
					return true
				end
			end
		end
	end
end

function App:updateGame()
	local w, h = self.sandSize:unpack()
	local dt = self.thisTime - self.lastUpdateTime
	if dt <= updateInterval then return end
	dt = updateInterval

	--[[ fast-forward to catch up? messes up with pause too
	self.lastUpdateTime = self.lastUpdateTime + updateInterval
	--]]
	-- [[ stutter
	self.lastUpdateTime = self.thisTime
	--]]
	self.gameTime = self.gameTime + updateInterval

	local needsCheckLine = false

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
					needsCheckLine = true
				-- hmm symmetry? check left vs right first?
				elseif math.random() < self.cfg.toppleChance then
					-- 50/50 check left then right, vs check right then left
					if math.random(2) == 2 then
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

	for _,player in ipairs(self.players) do
		player.pieceLastPos:set(player.piecePos:unpack())
	end

	-- now draw the shape over the sand
	-- test piece for collision with sand
	-- if it collides then merge it
	local movedx = 1
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
			player.piecePos.y = player.piecePos.y - self.dropSpeed
		end
		if player.keyPress.up and not player.keyPressLast.up then
			self:rotatePiece(player)
		end
	end

	self.fallTick = self.fallTick + 1
	if self.fallTick >= self.ticksToFall then
		self.fallTick = 0
		local falldy = math.max(1, 1/self.ticksToFall)
		for _,player in ipairs(self.players) do
			player.piecePos.y = player.piecePos.y - falldy
		end
	end

	local anyMerged
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
			anyMerged = true
			self:playSound'sfx/place.wav'
			needsCheckLine = true
			for j=0,self.pieceSize.y-1 do
				for i=0,self.pieceSize.x-1 do
					local k =  i + self.pieceSize.x * j
					local color = ffi.cast('uint32_t*', player.pieceTex.image.buffer)[k]
					if color ~= 0 then
						local x = player.piecePos.x + i
						local y = player.piecePos.y + j
						if x >= 0 and x < w
						and y >= 0 and y < h
						and ffi.cast('uint32_t*', self.sandTex.image.buffer)[x + w * y] == 0
						then
							ffi.cast('uint32_t*', self.sandTex.image.buffer)[x + w * y] = color
						end
					end
				end
			end
			self:newPiece(player)
		end
	end

	if dontCheckForLinesEver then needsCheckLine = false end

	-- try to find a connection from left to right
	local anyCleared
	if needsCheckLine then
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

			if self.gameTime - self.lastLineTime < self.chainDuration then
				self.scoreChain = self.scoreChain + 1
			else
				self.scoreChain = 0
			end
			-- piece chain count, score multipliers, etc
			-- https://tetris.fandom.com/wiki/Scoring
			-- 2 => x2*5/4, 3 => x3*2*5/4, 4 => x4*3*2*5/4
			local modifier = self.scoreChain == 0 and 1 or math.factorial(self.scoreChain+1) * 5/4
--print('scoreChain '..self.scoreChain, 'modifier', modifier)

			self.score = self.score + math.ceil(self.level * clearedCount * modifier)
			self.lines = self.lines + 1
			if self.lines % 10 == 0 then
				self.level = self.level + 1
				self:upateFallSpeed()
			end

			self:playSound'sfx/line.wav'
			self.flashTex:bind():subimage()
			self.lastLineTime = self.gameTime

		end
	end

	if needsCheckLine or anyMerged or anyCleared then
		self.numSandVoxels = 0
		local p = ffi.cast('uint32_t*', self.sandTex.image.buffer)
		for i=0,w*h-1 do
			if p[0] ~= 0 then self.numSandVoxels = self.numSandVoxels + 1 end
			p = p + 1
		end
		self.sandTex:bind():subimage()
	end

	for _,player in ipairs(self.players) do
		for k,v in pairs(player.keyPress) do
			player.keyPressLast[k] = v
		end
	end
end

function App:update(...)
	self.thisTime = getTime()
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	if self.state.update then
		self.state:update()
	end

	local w, h = self.sandSize:unpack()

	if not self.paused then
		-- if we haven't lost yet ...
		if not self.loseTime then
			self:updateGame()
		end

		--[[ pouring sand
		self.sandCPU[bit.rshift(w,1) + w * (h - 1)] = bit.bor(
			math.random(0,16777215),
			0xff000000,
		)
		--]]

		-- draw

		local aspectRatio = self.width / self.height
		local s = w / h

		self.projMat:setOrtho(-.5 * aspectRatio, .5 * aspectRatio, -.5, .5, -1, 1)
		self.displayShader:use()
		self.displayShader.vao:use()

		self.mvMat:setTranslate(-.5 * s, -.5)
			:applyScale(s, 1)
		self.mvProjMat:mul4x4(self.projMat, self.mvMat)
		gl.glUniformMatrix4fv(self.displayShader.uniforms.modelViewProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

		self.sandTex:bind()
		gl.glDrawArrays(gl.GL_QUADS, 0, 4)

		-- draw the current piece
		for _,player in ipairs(self.players) do
			for i=1,2 do
				local tex
				if i == 1 then
					tex = player.pieceOutlineTex
					gl.glEnable(gl.GL_BLEND)
					gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE)
				else
					tex = player.pieceTex
					gl.glEnable(gl.GL_ALPHA_TEST)
				end

				self.mvMat:setTranslate(
						(player.piecePos.x / w - .5) * s,
						player.piecePos.y / h - .5
					)
					:applyScale(self.pieceSize.x / w * s, self.pieceSize.y / h)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(self.displayShader.uniforms.modelViewProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

				tex:bind()
				gl.glDrawArrays(gl.GL_QUADS, 0, 4)

				if i == 1 then
					gl.glDisable(gl.GL_BLEND)
				else
					gl.glDisable(gl.GL_ALPHA_TEST)
				end
			end
		end

		-- draw flashing background if necessary
		local flashDt = self.gameTime - self.lastLineTime
		if flashDt < self.lineFlashDuration then
			self.wasFlashing = true
			gl.glEnable(gl.GL_ALPHA_TEST)
			local flashInt = bit.band(math.floor(flashDt * self.lineNumFlashes * 2), 1) == 0
			if flashInt then
				self.mvMat
					:setTranslate(-.5 * s, -.5)
					:applyScale(s, 1)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(self.displayShader.uniforms.modelViewProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

				self.flashTex:bind()
				gl.glDrawArrays(gl.GL_QUADS, 0, 4)
			end
			gl.glDisable(gl.GL_ALPHA_TEST)
		elseif self.wasFlashing then
			-- clear once we're done flashing
			self.wasFlashing = false
			ffi.fill(self.flashTex.image.buffer, 4 * w * h)
			assert(self.flashTex.data == self.flashTex.image.buffer)
			self.flashTex:bind():subimage()
		end

		if self.loseTime then
			local loseDuration = self.thisTime - self.loseTime
			if math.floor(loseDuration * 2) % 2 == 0 then
				self.mvMat
					:setTranslate(-.5 * s, -.5)
					:applyScale(s, 1)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(self.displayShader.uniforms.modelViewProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

				gl.glEnable(gl.GL_ALPHA_TEST)
				self.youloseTex:bind()
				gl.glDrawArrays(gl.GL_QUADS, 0, 4)
				gl.glDisable(gl.GL_ALPHA_TEST)
			end
		end

		local nextPieceSize = .1
		for i=#self.nextPieces,1,-1 do
			local it = self.nextPieces[i]
			local dy = #self.nextPieces == 1 and 0 or (1 - nextPieceSize)/(#self.nextPieces-1)
			dy = math.min(dy, nextPieceSize * 1.1)

			self.mvMat
				:setTranslate(aspectRatio * .5 - nextPieceSize, .5 - (i-1) * dy)
				:applyScale(nextPieceSize, -nextPieceSize)
			self.mvProjMat:mul4x4(self.projMat, self.mvMat)
			gl.glUniformMatrix4fv(self.displayShader.uniforms.modelViewProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

			it.tex:bind()
			gl.glDrawArrays(gl.GL_QUADS, 0, 4)
		end

		self.displayShader.vao:useNone()
		GLTex2D:unbind()
		self.displayShader:useNone()
	end

	if self.loseTime and self.thisTime - self.loseTime > self.loseScreenDuration then
		-- TODO maybe go to a high score screen instead?
		self.loseTime = nil
		self.paused = true
		self.state = GameState.HighScoreState(self, true)
	end

	-- update GUI
	App.super.update(self, ...)
	glreport'here'


	if self.showFPS then
		self.fpsSampleCount = self.fpsSampleCount + 1
		if self.thisTime - self.lastFrameTime >= 1 then
			local deltaTime = self.thisTime - self.lastFrameTime
			self.fps = self.fpsSampleCount / deltaTime
			self.lastFrameTime = self.thisTime
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

function App:processButtonEvent(press, ...)
	-- TODO put the callback somewhere, not a global
	-- it's used by the New Game menu
	if waitingForEvent then
		if press then
			local ev = {...}
			ev.name = Player:getEventName(...)
			waitingForEvent.callback(ev)
			waitingForEvent = nil
		end
	else
		local descLen = select('#', ...)
		for playerIndex, playerConfig in ipairs(self.cfg.playerKeys) do
			for buttonName, buttonDesc in pairs(playerConfig) do
				if descLen == #buttonDesc then
					local match = true
					for i=1,descLen do
						if select(i, ...) ~= buttonDesc[i] then
							match = false
							break
						end
					end
					if match then
						local player = self.players[playerIndex]
						if player then
							player.keyPress[buttonName] = press
						end
					end
				end
			end
		end
	end
end

function App:event(e, ...)
	-- handle UI
	App.super.event(self, e, ...)
	-- TODO if ui handling then return

	if self.state.event then
		if self.state:event(e, ...) then return end
	end

	-- handle any kind of sdl button event
	if e.type == sdl.SDL_JOYHATMOTION then
		--if e.jhat.value ~= 0 then
			-- TODO make sure all hat value bits are cleared
			-- or keep track of press/release
			for i=0,3 do
				local dirbit = bit.lshift(1,i)
				local press = bit.band(dirbit, e.jhat.value) ~= 0
				self:processButtonEvent(press, sdl.SDL_JOYHATMOTION, e.jhat.which, e.jhat.hat, dirbit)
			end
			--[[
			if e.jhat.value == sdl.SDL_HAT_CENTERED then
				for i=0,3 do
					local dirbit = bit.lshift(1,i)
					self:processButtonEvent(false, sdl.SDL_JOYHATMOTION, e.jhat.which, e.jhat.hat, dirbit)
				end
			end
			--]]
		--end
	elseif e.type == sdl.SDL_JOYAXISMOTION then
		-- -1,0,1 depend on the axis press
		local lr = math.floor(3 * (tonumber(e.jaxis.value) + 32768) / 65536) - 1
		local press = lr ~= 0
		if not press then
			-- clear both left and right movement
			self:processButtonEvent(press, sdl.SDL_JOYAXISMOTION, e.jaxis.which, e.jaxis.axis, -1)
			self:processButtonEvent(press, sdl.SDL_JOYAXISMOTION, e.jaxis.which, e.jaxis.axis, 1)
		else
			-- set movement for the lr direction
			self:processButtonEvent(press, sdl.SDL_JOYAXISMOTION, e.jaxis.which, e.jaxis.axis, lr)
		end
	elseif e.type == sdl.SDL_JOYBUTTONDOWN or e.type == sdl.SDL_JOYBUTTONUP then
		-- e.jbutton.state is 0/1 for up/down, right?
		local press = e.type == sdl.SDL_JOYBUTTONDOWN
		self:processButtonEvent(press, sdl.SDL_JOYBUTTONDOWN, e.jbutton.which, e.jbutton.button)
	elseif e.type == sdl.SDL_KEYDOWN or e.type == sdl.SDL_KEYUP then
		local press = e.type == sdl.SDL_KEYDOWN
		self:processButtonEvent(press, sdl.SDL_KEYDOWN, e.key.keysym.sym)
	-- else mouse buttons?
	-- else mouse motion / position?
	end

	if e.type == sdl.SDL_KEYDOWN
	or e.type == sdl.SDL_KEYUP
	then
		if down
		and e.key.keysym.sym == sdl.SDLK_ESCAPE
		and GameState.PlayingState:isa(self.state)
		then
			self.paused = not self.paused
		end
		if down and e.key.keysym.sym == ('f'):byte() then
			if down then self:flipBoard() end
		end
	end
end

function App:updateGUI()
	ig.igPushFont(self.font)
	if self.state.updateGUI then
		self.state:updateGUI()
	end
	ig.igPopFont()
end

function App:exit()
	if self.useAudio then
		self.audio:shutdown()
	end
	App.super.exit(self)
end

return App
