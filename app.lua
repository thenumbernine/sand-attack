local ffi = require 'ffi'
local sdl = require 'sdl'
local table = require 'ext.table'
local path = require 'ext.path'
local class = require 'ext.class'
local math = require 'ext.math'
local string = require 'ext.string'
local range = require 'ext.range'
local template = require 'template'
local matrix = require 'matrix.ffi'
local Image = require 'image'
local gl = require 'gl'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local GLGeometry = require 'gl.geometry'
local GLSceneObject = require 'gl.sceneobject'
local GLArrayBuffer = require 'gl.arraybuffer'
local GLFramebuffer = require 'gl.framebuffer'
local glreport = require 'gl.report'
local vec2i = require 'vec-ffi.vec2i'
local vec2f = require 'vec-ffi.vec2f'
local vec3f = require 'vec-ffi.vec3f'
local getTime = require 'ext.timer'.getTime
local ig = require 'imgui'
local Audio = require 'audio'
local AudioSource = require 'audio.source'
local AudioBuffer = require 'audio.buffer'
local Player = require 'sand-attack.player'
local SandModel = require 'sand-attack.sandmodel.sandmodel'

local readDemo = require 'sand-attack.serialize'.readDemo
local writeDemo = require 'sand-attack.serialize'.writeDemo
local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
local sandModelClassForName = require 'sand-attack.sandmodel.all'.classForName

ffi.cdef[[
// what type to use for time?
// 60 fps ...
// 2 bytes = 65535 ticks = 1092 seconds @ 60 fps = 18.2 minutes
// 4 bytes = 4294967295 ticks = 71582788.25 seconds = 1193046.4708333 minutes = 19884.107847222 hours = 828.50449363426 days = 27.388578301959 months = 2.268321680039 years
typedef uint32_t gameTick_t;

typedef uint64_t randSeed_t;
]]

-- I'm trying to make reproducible random #s
-- it is reproducible up to the generation of the next pieces
-- but the very next piece after will always be dif
-- this maybe is due to the sand toppling also using rand?
-- but why wouldn't that random() call even be part of the determinism?
-- seems something external must be contributing?
--[[ TODO put this in ext? or its own lib?
local RNG = class()
-- TODO max and the + and % constants are bad, fix them
RNG.max = 2147483647ull
require 'ffi.req' 'c.time'
function RNG:init(seed)
	self.seed = ffi.cast('uint64_t', tonumber(seed) or ffi.C.time(nil))
end
function RNG:next(max)
	self.seed = self.seed * 1103515245ull + 12345ull
	return self.seed % (self.max + 1)
end
function RNG:__call(max)
	if max then
		return tonumber(self:next() % max) + 1	-- +1 for lua compat
	else
		return tonumber(self:next()) / tonumber(self.max)
	end
end
--]]
-- [[ Lua code says: xoshira256** algorithm
-- but is only a singleton...
local RNG = class()
function RNG:init(seed)
	math.randomseed(tonumber(seed))
end
function RNG:__call(...)
	return math.random(...)
end
--]]

local mytolua = require 'sand-attack.serialize'.tolua
local myfromlua = require 'sand-attack.serialize'.fromlua

local App = require 'imgui.app':subclass()

if App.sdlMajorVersion == 2 then
	App.sdlEventKeyUp = sdl.SDL_KEYUP
	App.sdlEventKeyDown = sdl.SDL_KEYDOWN
	App.sdlEventJoystickHatMotion = sdl.SDL_JOYHATMOTION
	App.sdlEventJoystickAxisMotion = nil
	App.sdlEVentJoystickButtonDown = nil
	App.sdlEVentJoystickButtonUp = nil
	App.sdlEventGamepadAxisMotion = sdl.SDL_CONTROLLERAXISMOTION
	App.sdlEventGamepadButtonDown = sdl.SDL_CONTROLLERBUTTONDOWN
	App.sdlEventGamepadButtonUp = sdl.SDL_CONTROLLERBUTTONUP
	App.sdlEventMouseButtonDown = sdl.SDL_MOUSEBUTTONDOWN
	App.sdlEventMouseButtonUp = sdl.SDL_MOUSEBUTTONUP
	App.sdlEventFingerDown = sdl.SDL_FINGERDOWN
	App.sdlEventFingerUp = sdl.SDL_FINGERUP
else
	App.sdlEventKeyUp = sdl.SDL_EVENT_KEY_UP
	App.sdlEventKeyDown = sdl.SDL_EVENT_KEY_DOWN
	App.sdlEventJoystickHatMotion = sdl.SDL_EVENT_JOYSTICK_HAT_MOTION
	App.sdlEventJoystickAxisMotion = sdl.SDL_EVENT_JOYSTICK_AXIS_MOTION
	App.sdlEventJoystickButtonDown = sdl.SDL_EVENT_JOYSTICK_BUTTON_DOWN
	App.sdlEventJoystickButtonUp = sdl.SDL_EVENT_JOYSTICK_BUTTON_UP
	App.sdlEventGamepadAxisMotion = sdl.SDL_EVENT_GAMEPAD_AXIS_MOTION
	App.sdlEventGamepadButtonDown = sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN
	App.sdlEventGamepadButtonUp = sdl.SDL_EVENT_GAMEPAD_BUTTON_UP
	App.sdlEventMouseButtonDown = sdl.SDL_EVENT_MOUSE_BUTTON_DOWN
	App.sdlEventMouseButtonUp = sdl.SDL_EVENT_MOUSE_BUTTON_UP
	App.sdlEventFingerDown = sdl.SDL_EVENT_FINGER_DOWN
	App.sdlEventFingerUp = sdl.SDL_EVENT_FINGER_UP
end

App.title = 'Sand Attack'
App.sdlInitFlags = bit.bor(
	sdl.SDL_INIT_VIDEO,
	sdl.SDL_INIT_JOYSTICK
)

App.useAudio = true		-- set to false to disable audio altogether
App.showFPS = false		-- show fps in gui / console
App.showDebug = false	-- show some more debug stuff
local dontCheckForLinesEver = false	-- means don't ever ever check for lines.  used for fps testing the sand topple simulation.

App.updateInterval = 1/60
--App.updateInterval = 1/120
--App.updateInterval = 0

App.defaultColors = table{
	{1,0,0},
	{0,0,1},
	{0,1,0},
	{1,1,0},
	{1,0,1},
	{0,1,1},
	{1,1,1},
}
-- assumes we have full 8 bits of resolution in th alpha channel (not always the case .... ?)
App.maxColors = 255

App.maxAudioDist = 10

App.chainDuration = 2
App.lineFlashDuration = 1
App.lineNumFlashes = 5

App.cfgfilename = 'config.lua'

App.highScorePath = 'highscores'

function App:initGL(...)
	App.super.initGL(self, ...)

	-- allow keys to navigate menu
	-- TODO how to make it so player keys choose menus, not just space bar/
	-- or meh?
	local igio = ig.igGetIO()
	igio[0].ConfigFlags = bit.bor(
		igio[0].ConfigFlags,
		ig.ImGuiConfigFlags_NavEnableKeyboard,
		ig.ImGuiConfigFlags_NavEnableGamepad
	)
	igio[0].FontGlobalScale = 2

-- [[ imgui custom font
	if not self.skipCustomFont then
		xpcall(function()
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
			require 'ffi.req' 'c.stdlib'	-- free()
			ffi.C.free(outPixels[0])	-- just betting here I have to free this myself ...
			ig.ImFontAtlas_SetTexID(self.fontAtlas, ffi.cast('ImTextureID', self.fontTex.id))
		end, function(err)
			print(err)
			print(debug.traceback())
			self.fontAtlas = nil
			self.font = nil
			self.fontTex = nil
		end)
	end
--]]

	-- load config if it exists
	xpcall(function()
		local cfgpath = path(self.cfgfilename)
		if cfgpath:exists() then
			self.cfg = myfromlua(assert(cfgpath:read()))
		end
	end, function(err)
		print('failed to read lua from file '..tostring(self.cfgfilename)..'\n'
			..tostring(err)..'\n'
			..debug.traceback())
	end)
	self.cfg = self.cfg or {}

	-- load high scores if it exists
	self.highscores = {}
	-- TODO WARNING
	-- for some reason in the Windows version, distributable ONLY (not in runtime setup), errors thrown in the app ctor are being hidden.
	-- especially starting right around here ...
	if not self.highScorePath then
		print('WARNING: high scores are disabled !!!')
	else
		path(self.highScorePath):mkdir()
		for f in path(self.highScorePath):dir() do
			if f.path:match'%.demo$' then
				table.insert(
					self.highscores,
					readDemo(self.highScorePath..'/'..f)
				)
			end
		end
	end

	-- board size is 80 x 144 visible
	-- piece is 4 blocks arranged
	-- blocks are 8 x 8 by default
	self.pieceSizeInBlocks = vec2i(4,4)	-- fixed

	--self.cfg.voxelsPerBlock = self.cfg.voxelsPerBlock or 8	-- original
	self.cfg.voxelsPerBlock = self.cfg.voxelsPerBlock or 16	-- double
	--self.cfg.voxelsPerBlock = self.cfg.voxelsPerBlock or 32		-- quadruple

	self.cfg.effectVolume = self.cfg.effectVolume or 1
	self.cfg.backgroundVolume = self.cfg.backgroundVolume or .3
	self.cfg.startLevel = self.cfg.startLevel or 1
	self.cfg.movedx = self.cfg.movedx or 1				-- TODO configurable
	self.cfg.dropSpeed = self.cfg.dropSpeed or 5
	self.cfg.sandModel = self.cfg.sandModel or sandModelClassNames[1]
	self.cfg.speedupCoeff = self.cfg.speedupCoeff or .007
	self.cfg.toppleChance = self.cfg.toppleChance or 1
	self.cfg.playerKeys = self.cfg.playerKeys or {}
	self.cfg.screenButtonRadius = self.cfg.screenButtonRadius or .05
	if self.cfg.continuousDrop == nil then
		self.cfg.continuousDrop = true
	end
	if not self.cfg.colors then
		self.cfg.colors = {}
	end
	self.cfg.numColors = self.cfg.numColors or 4
	for i=1,self.cfg.numColors do
		self.cfg.colors[i] = self.cfg.colors[i] or self:getDefaultColor(i)
	end
	self.cfg.boardWidthInBlocks = self.cfg.boardWidthInBlocks or 10		-- original
	self.cfg.boardHeightInBlocks = self.cfg.boardHeightInBlocks or 18	-- original
	--[[
	self.cfg.boardWidthInBlocks = self.cfg.boardWidthInBlocks or 20
	self.cfg.boardHeightInBlocks = self.cfg.boardHeightInBlocks or 25
	--]]
	--[[
	self.cfg.boardWidthInBlocks = self.cfg.boardWidthInBlocks or 10
	self.cfg.boardHeightInBlocks = self.cfg.boardHeightInBlocks or 45
	--]]
	--[[
	self.cfg.boardWidthInBlocks = self.cfg.boardWidthInBlocks or 64
	self.cfg.boardHeightInBlocks = self.cfg.boardHeightInBlocks or 64
	--]]
	self.cfg.numNextPieces = self.cfg.numNextPieces or 3
	-- hmm ... don't save this ... instead generate it new every game ... unless specified ... hmmm ....
	-- but do allow editing it in the config screen ... hmm ....
	-- and do allow saving it in highscores and in demos ...
	self.cfg.randseed = self.cfg.randseed or ffi.new('randSeed_t', -1)

	self.cfg.numPlayers = 1

	self.fps = 0
	self.numSandVoxels = 0

	self.loseScreenDuration = 3

	local buttonImg = Image(256, 256, 4, 'unsigned char', function(i,j)
		-- (i,j) are in [0,255)^2
		local x = ((i+.5)/256 - .5) * 2
		local y = ((j+.5)/256 - .5) * 2
		-- (x,y) are in [-1,1]^2 (plus or minus 1/n ...)
		local r2 = x*x + y*y
		if r2 < 1 and r2 > .9*.9 then
			return 255,255,255,255
		else
			return 0,0,0,0
		end
	end)
	self.buttonTex = GLTex2D{
		image = buttonImg,
		wrap = {
			s = gl.GL_CLAMP_TO_EDGE,
			t = gl.GL_CLAMP_TO_EDGE,
		},
		minFilter = gl.GL_NEAREST,
		magFilter = gl.GL_LINEAR,
	}

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

--[[ assign a view but not a view setup call every frame
	local View = require 'glapp.view'
	self.view = View()
	self.projMat = self.view.projMat
	self.mvMat = self.view.mvMat
	self.mvProjMat = self.view.projMat
--]]
-- [[
	self.projMat = matrix({4,4}, 'float'):zeros():setIdent()
	self.mvMat = matrix({4,4}, 'float'):zeros():setIdent()
	self.mvProjMat = matrix({4,4}, 'float'):zeros():setIdent()
--]]

	local vtxbufCPU = ffi.new('vec2f_t[4]', {
		vec2f(0,0),
		vec2f(1,0),
		vec2f(0,1),
		vec2f(1,1),
	})
	self.quadVertexBuf = GLArrayBuffer{
		size = ffi.sizeof(vtxbufCPU),
		data = vtxbufCPU,
	}:unbind()

	self.quadGeom = GLGeometry{
		mode = gl.GL_TRIANGLE_STRIP,
		count = 4,
	}

	self.displayShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = [[
in vec2 vertex;
out vec2 texcoordv;
uniform mat4 mvProjMat;
void main() {
	texcoordv = vertex;
	gl_Position = mvProjMat * vec4(vertex, 0., 1.);
}
]],
		fragmentCode = [[
in vec2 texcoordv;
out vec4 fragColor;
uniform sampler2D tex;
uniform bool useAlphaTest;
void main() {
	fragColor = texture(tex, texcoordv);
	if (useAlphaTest && fragColor.a == 0.) discard;
}
]],
		uniforms = {
			tex = 0,
			useAlphaTest = false,
		},
	}:useNone()

	self.splashScreenSceneObj = GLSceneObject{
		geometry = self.quadGeom,
		program = self.displayShader,
		attrs = {
			vertex = self.quadVertexBuf,
		},
		texs = {
			self.splashTex,
		},
	}

	-- same as splashScreenSceneObj but without texs
	-- I could separate the attr+shader+geom from texs for the sake of minimizing VAO creation...
	self.displayQuadSceneObj = GLSceneObject{
		geometry = self.quadGeom,
		program = self.displayShader,
		attrs = {
			vertex = self.quadVertexBuf,
		},
	}

	self.populatePieceShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = [[
in vec2 vertex;
out vec2 texcoordv;
uniform mat4 mvProjMat;
void main() {
	texcoordv = vertex;
	gl_Position = mvProjMat * vec4(vertex, 0., 1.);
}
]],
		fragmentCode = [[
in vec2 texcoordv;
out vec4 fragColor;

uniform sampler2D tex;
uniform sampler2D randtex;
uniform vec4 color;
uniform vec3 pieceSize;	//.z = voxelsPerBlock

void main() {
	vec4 dstc = texture(tex, texcoordv) * color;
	vec2 ij = texcoordv * pieceSize.xy;
	float voxelsPerBlock = pieceSize.z;
	vec2 uv = mod(ij, voxelsPerBlock );
	float c = max(
		abs(uv.x - voxelsPerBlock*.5),
		abs(uv.y - voxelsPerBlock*.5)
	) / (voxelsPerBlock*.5);
	float l = texture(randtex, texcoordv).r * .25 + .75;
	l *= .25 + .75 * sqrt(1. - c*c);
	fragColor = vec4(dstc.xyz * l, dstc.w);
}
]],
		uniforms = {
			tex = 0,
			randtex = 1,
		},
	}:useNone()

	self.updatePieceOutlineShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = [[
in vec2 vertex;
out vec2 texcoordv;
uniform mat4 mvProjMat;
void main() {
	texcoordv = vertex;
	gl_Position = mvProjMat * vec4(vertex, 0., 1.);
}
]],
		fragmentCode = [[
in vec2 texcoordv;
out vec4 fragColor;

uniform sampler2D pieceTex;
uniform ivec2 pieceSize;
uniform ivec3 pieceOutlineSize;	//.z = pieceOutlineRadius;
uniform vec3 color;

float lenSq(vec2 v) {
	return dot(v,v);
}

void main() {
	float maxDistSq = float(pieceOutlineSize.x + pieceOutlineSize.y);
	float bestDistSq = maxDistSq;

	int pieceOutlineRadius = pieceOutlineSize.z;
	ivec2 ij = ivec2(texcoordv * vec2(pieceOutlineSize));
	ivec2 ofs;
	for (ofs.y = -pieceOutlineRadius; ofs.y <= pieceOutlineRadius; ++ofs.y) {
		for (ofs.x = -pieceOutlineRadius; ofs.x <= pieceOutlineRadius; ++ofs.x) {
			ivec2 xy = ij - pieceOutlineRadius + ofs;
			if (xy.x >= 0 && xy.x < pieceSize.x &&
				xy.y >= 0 && xy.y < pieceSize.y
			) {
				vec4 c = texelFetch(pieceTex, xy, 0);
				if (c != vec4(0.)) {
					float distSq = max(1., lenSq(vec2(ofs)));
					bestDistSq = min(bestDistSq, distSq);
				}
			}
		}
	}

	if (bestDistSq < maxDistSq) {
		float frac = 1. / bestDistSq;
		fragColor = vec4(color * frac, 1.);
	} else {
		fragColor = vec4(0.);
	}
}
]],
		uniforms = {
			pieceTex = 0,
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

			self.bgMusicFiles = table()
			for f in path'music':dir() do
				if f.path:match'%.ogg$' then
					self.bgMusicFiles:insert('music/'..f)
				end
			end
			self.bgMusicFileName = self.bgMusicFiles:pickRandom()
			if self.bgMusicFileName then
				self.bgMusic = self:loadSound(self.bgMusicFileName)
				self.bgAudioSource = AudioSource()
				self.bgAudioSource:setBuffer(self.bgMusic)
				self.bgAudioSource:setLooping(true)
				-- self.usercfg
				self.bgAudioSource:setGain(self.cfg.backgroundVolume)
				self.bgAudioSource:play()
			end
		end, function(err)
			print('failed to init audio'
				..tostring(err)..'\n'
				..debug.traceback())
			self.audio = nil
			self.useAudio = false	-- or just test audio's existence?
		end)
	end

	local SplashScreenMenu = require 'sand-attack.menu.splashscreen'

	-- set this up to valid events within getEventName
	SplashScreenMenu.endSplashEventTypes = table{
		App.sdlEventKeyDown,
		App.sdlEventMouseButtonDown,
		App.sdlEventFingerDown,
	}:mapi(function(v) return true, v end):setmetatable(nil)
	if self.sdlMajorVersion > 2 then
		if App.sdlEventJoystickHatMotion then
			SplashScreenMenu.endSplashEventTypes[App.sdlEventJoystickHatMotion] = true
		end
		if App.sdlEventGamepadAxisMotion then
			SplashScreenMenu.endSplashEventTypes[App.sdlEventGamepadAxisMotion] = true
		end
		if App.sdlEventGamepadButtonDown then
			SplashScreenMenu.endSplashEventTypes[App.sdlEventGamepadButtonDown] = true
		end
		if App.sdlEventJoystickAxisMotion then
			SplashScreenMenu.endSplashEventTypes[App.sdlEventJoystickAxisMotion] = true
		end
		if App.sdlEventJoystickButtonDown then
			SplashScreenMenu.endSplashEventTypes[App.sdlEventJoystickButtonDown] = true
		end
	end

	-- setup more valid events
	require 'sand-attack.menu.playerkeys'.sdlEventKeyDown = self.sdlEventKeyDown


	self.menustate = SplashScreenMenu(self)

	-- play a demo in the background when the game starts
	self:reset{
		playingDemoRecord = readDemo'splash.demo',
	}

	glreport'here'
end

function App:getDefaultColor(i)
	if i <= #self.defaultColors then
		return {table.unpack(self.defaultColors[i])}
	else
		return {vec3f():map(function() return math.random() end):normalize():unpack()}
	end
end


function App:makeTexFromImage(img)
	local tex = GLTex2D{
		internalFormat = gl.GL_RGBA,
		width = tonumber(img.width),
		height = tonumber(img.height),
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
		:unbind()
	tex.image = img
	return tex
end

-- static method
function App:makeTexWithBlankImage(size)
	local img = Image(size.x, size.y, 4, 'unsigned char')
	ffi.fill(img.buffer, 4 * size.x * size.y)
	return self:makeTexFromImage(img)
end

-- called from App:reset()
function App:makePieceImage(s)
	s = string.split(s, '\n')
	local img = Image(self.pieceSize.x, self.pieceSize.y, 4, 'unsigned char')
	local ptr = ffi.cast('uint32_t*', img.buffer)
	ffi.fill(ptr, 4 * img.width * img.height)
	local vpb = self.playcfg.voxelsPerBlock
	for j=0,self.pieceSizeInBlocks.y-1 do
		for i=0,self.pieceSizeInBlocks.x-1 do
			if s[j+1]:sub(i+1,i+1) == '#' then
				for u=0,vpb-1 do
					for v=0,vpb-1 do
						ptr[(u + vpb * i) + img.width * (v + vpb * j)] = 0xffffffff
					end
				end
			end
		end
	end
	return self:makeTexFromImage(img)
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
	writeDemo(self.cfgfilename, self.cfg)
end

-- called by App:reset
-- would be called by NewGameMenu:updateGUI once I sort out .cfg vs .playcfg
function App:updateGameScale()
	self.gameScaleFloat = self.playcfg.voxelsPerBlock / 8
	self.gameScale = math.ceil(self.gameScaleFloat)
	self.updatesPerFrame = self.gameScale
end

function App:reset(args)
	args = args or {}

	self:saveConfig()

	self.playingDemo = nil
	self.recordingDemo = nil

	--[[
	demoPlayback blob format:
	struct {
		gameTick_t gameTick;
		uint8_t buttonFlags[ceil(numPlayers * #gameKeyNames / 8)];
	} events[];
	... packed
	--]]
	if not args.dontRecordOrPlay then
		if args.playingDemoRecord then
			xpcall(function()
				local data = assert(args.playingDemoRecord.demoPlayback)
				local ptr = ffi.cast('char*', data)
				-- TODO why reinvent the wheel.  just use fread/feof.
				-- TODO rename this also to something else, idk what
				self.playingDemo = setmetatable({
					ptr = ptr,
					data = data,
					index = 0,
					size = #data,
				}, {
					__index = {
						-- without advancing, returns ptr
						get = function(self, size)
							if self.index + size > self.size then
								return nil, "tried to read past end of file"
							end
							return self.ptr + self.index
						end,
						-- return cdata value and advance
						read = function(self, ctype)
							local resultsize = ffi.sizeof(ctype)
							local result = self:get(resultsize)
							if not result then return result end
							self.index = self.index + resultsize
							return ffi.cast(ctype..'*', result)[0]
						end,
						-- return str value and advance
						readstr = function(self, len)
							len = len or ffi.C.strlen(self.ptr + self.index)
							local s, msg = self:get(len)
							if not s then return s, msg end
							self.index = self.index + len
							return ffi.string(s, len)
						end,
					},
				})

				self.playingDemo.config = args.playingDemoRecord

				-- put currently-playing cfg in playcfg
				self.playcfg = self.playingDemo.config

			end, function(err)
				print('failed to load demo\n'
					..tostring(err)..'\n'
					..debug.traceback())
				self.playingDemo = nil
			end)
		end
		if not self.playingDemo then
--print('recording demo...')
			-- ... then record
			self.recordingDemo = table()

			-- NOTICE THIS IS A SHALLOW COPY
			-- that means subtables (player keys, custom colors) won't be copied
			-- not sure if i should bother since neither of those things are used by playcfg but ....
			self.playcfg = table(self.cfg):setmetatable(nil)
		end
	end

	local playcfg = self.playcfg

	-- used only for writing demo file
	self.recordingEventSize = ffi.sizeof'gameTick_t' + math.ceil(playcfg.numPlayers * #Player.gameKeyNames / 8)
	-- used for reading and writing
	self.recordingEvent = ffi.new('uint8_t[?]', self.recordingEventSize)

	--[[ print event list
	if self.playingDemo then
		print('all upcoming events:')
		for i=0,#self.playingDemo.data-1,self.recordingEventSize do
			local event = self.playingDemo.ptr + i
			io.write(('... %08x'):format(ffi.cast('gameTick_t*', event)[0]))
			for i=ffi.sizeof'gameTick_t',self.recordingEventSize-1 do
				io.write((' %02x'):format(event[i]))
			end
		end
		print()
	end
	--]]

	-- what happens if the replay config is bad?
	-- should we lose the old config?
	-- or what if it's good?
	-- should we allow the demo config to overwrite the previous config?
	-- ....
	-- thinking more about it, mayb the whoel of :reset() should be wrapped in that xpcall
	-- in case the base config.lua file itself was corrupted
	self.rng = RNG(playcfg.randseed)

	self:updateGameScale()

	-- init pieces

	self.pieceSize = self.pieceSizeInBlocks * playcfg.voxelsPerBlock

	self.pieceFBO = GLFramebuffer{width=self.pieceSize.x, height=self.pieceSize.y}
		:unbind()

	self.pieceOutlineSize = self.pieceSize + 2 * self.pieceOutlineRadius
	self.pieceOutlineFBO = GLFramebuffer{width=self.pieceOutlineSize.x, height=self.pieceOutlineSize.y}
		:unbind()

	do
		local size = self.pieceSize
		local img = Image(size.x, size.y, 4, 'unsigned char')
		local ptr = ffi.cast('uint32_t*', img.buffer)
		for j=0,size.y-1 do
			for i=0,size.x-1 do
				ptr[0] = bit.bor(
					self.rng(0,255),
					bit.lshift(self.rng(0,255), 8),
					bit.lshift(self.rng(0,255), 16),
					bit.lshift(self.rng(0,255), 24)
				)
				ptr = ptr + 1
			end
		end
		self.pieceRandomColorTex = self:makeTexFromImage(img)
	end


	self.pieceSourceTexs = table{
		[[
 #
 #
 #
 #
]],
		[[
 #
 #
 ##
]],
		[[
   #
   #
  ##
]],
		[[

 ##
 ##
]],
		[[

 #
###
]],
		[[
 #
 ##
  #
]],
		[[
  #
 ##
 #
]],
	}:mapi(function(s)
		return self:makePieceImage(s)
	end)

	-- init board


	self.sandSize = vec2i(
		playcfg.boardWidthInBlocks * playcfg.voxelsPerBlock,
		playcfg.boardHeightInBlocks * playcfg.voxelsPerBlock)
	local w, h = self.sandSize:unpack()

	self.loseTime = nil

	local sandModelClass = assert(sandModelClassForName[playcfg.sandModel])
	self.sandmodel = sandModelClass(self)

	-- I only really need to recreate the sand & flash texs if the board size changes ...
	self.flashTex = self:makeTexWithBlankImage(self.sandSize)

	-- and I only really need to recreate these if the piece size changes ...
	self.rotPieceTex = self:makeTexWithBlankImage(self.pieceSize)
	self.nextPieces = range(playcfg.numNextPieces):mapi(function(i)
		local tex = self:makeTexWithBlankImage(self.pieceSize)
		return {tex=tex}
	end)


	self.sandmodel:reset()

	-- TODO don't store the custom colors in the config file unless they've been defined
	-- especially now that it's a model file
	self.gameColors = table.sub(playcfg.colors, 1, playcfg.numColors):mapi(function(c) return vec3f(c) end)		-- colors used now
	assert(#self.gameColors == playcfg.numColors)	-- menu system should handle this

	self.players = range(playcfg.numPlayers):mapi(function(i)
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
	self.gameTick = ffi.new('gameTick_t', 0)
	self.fallTick = 0
	self.lastLineTime = -math.huge
	self.score = 0
	self.lines = 0
	self.level = playcfg.startLevel
	self.scoreChain = 0
	self:updateFallSpeed()

-- debugging:
--self.sandmodel:test()
end

-- called in App:reset() and App:updateGame() upon level up
function App:updateFallSpeed()
	-- https://harddrop.com/wiki/Tetris_Worlds
	local maxSpeedLevel = 13 -- fastest level .. no faster is permitted
	local effectiveLevel = math.min(self.level, maxSpeedLevel)
	-- TODO make this curve customizable
	local secondsPerRow = (.8 - ((effectiveLevel-1.)*self.playcfg.speedupCoeff))^(effectiveLevel-1.)
	local secondsPerLine = secondsPerRow / self.playcfg.voxelsPerBlock
	-- how many ticks to wait before dropping a piece
	self.ticksToFall = secondsPerLine / self.updateInterval
--print('effectiveLevel', effectiveLevel, 'secondsPerRow', secondsPerRow, 'scondsPerLin', secondsPerLine, 'ticksToFall', self.ticksToFall)
end

-- called by App:newPiece()
-- fill in a new piece texture
-- generate it based on the piece template
function App:populatePiece(args)
	local srctex = self.pieceSourceTexs:pickRandom()
	local colorIndex = self.rng(#self.gameColors)	-- 1..n for n colors
	local color = self.gameColors[colorIndex]
	local alpha = colorIndex/#self.gameColors		-- [1/n, 1]

	local fbo = self.pieceFBO
	local dsttex = args.tex
	local shader = self.populatePieceShader
	local sceneObj = self.displayQuadSceneObj

	gl.glViewport(0, 0, self.pieceSize.x, self.pieceSize.y)

	fbo:bind()
		:setColorAttachmentTex2D(dsttex.id)
	local res, err = fbo.check()
	if not res then print(err) end

	shader:use()
	sceneObj:enableAndSetAttrs()

	self.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)
	gl.glUniformMatrix4fv(
		shader.uniforms.mvProjMat.loc,
		1,
		gl.GL_FALSE,
		self.mvProjMat.ptr)
	gl.glUniform4f(shader.uniforms.color.loc, color.x, color.y, color.z, alpha)
	gl.glUniform3f(shader.uniforms.pieceSize.loc,
		self.pieceSize.x,
		self.pieceSize.y,
		self.playcfg.voxelsPerBlock)

	srctex:bind(0)
	self.pieceRandomColorTex:bind(1)

	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

	self.pieceRandomColorTex:unbind(1)
	srctex:unbind(0)

	sceneObj:disableAttrs()
	shader:useNone()

	gl.glReadPixels(
		0,						--GLint x,
		0,						--GLint y,
		self.pieceSize.x,		--GLsizei width,
		self.pieceSize.y,		--GLsizei height,
		gl.GL_RGBA,				--GLenum format,
		gl.GL_UNSIGNED_BYTE,	--GLenum type,
		dsttex.image.buffer)	--void *pixels

	fbo:unbind()

	gl.glViewport(0, 0, self.width, self.height)
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
	player.piecePos = vec2f((w-self.pieceSize.x)*.5, h-1)
	player.piecePosLast = vec2f(player.piecePos)
	if self.sandmodel:testPieceMerge(player) then
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

-- called by new piece tex, and after rotating the pice
App.pieceOutlineRadius = 5
function App:updatePieceTex(player)
	-- TODO use player.pieceTex.image:getZealousCropRect()
	-- while we're here, find the first and last cols with content
	-- use this for testing screen bounds
	local pieceBuf = ffi.cast('uint32_t*', player.pieceTex.image.buffer)
	for _,info in ipairs{
		{0,self.pieceSize.x-1,1, 'pieceColMin'},
		{self.pieceSize.x-1,0,-1, 'pieceColMax'},
	} do
		local istart, iend, istep, ifield = table.unpack(info)
		for i=istart,iend,istep do
			local found
			for j=0,self.pieceSize.y-1 do
				if pieceBuf[i + self.pieceSize.x * j] ~= 0 then
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

	-- same thing with rows to determine max row, to determine when we hit th ground
	for _,info in ipairs{
		{0,self.pieceSize.y-1,1, 'pieceRowMin'},
		{self.pieceSize.y-1,0,-1, 'pieceRowMax'},
	} do
		local jstart, jend, jstep, jfield = table.unpack(info)
		for j=jstart,jend,jstep do
			local found
			for i=0,self.pieceSize.x-1 do
				if pieceBuf[i + self.pieceSize.x * j] ~= 0 then
					found = true
					break
				end
			end
			if found then
				player[jfield] = j
				break
			end
		end
	end

	-- [[ update the piece outline
	local fbo = self.pieceOutlineFBO
	local dsttex = player.pieceOutlineTex
	local shader = self.updatePieceOutlineShader
	local sceneObj = self.displayQuadSceneObj
	local srctex = player.pieceTex

	gl.glViewport(0, 0, fbo.width, fbo.height)

	fbo:bind()
		:setColorAttachmentTex2D(dsttex.id)
	local res, err = fbo.check()
	if not res then print(err) end

	shader:use()
	sceneObj:enableAndSetAttrs()

	self.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)
	gl.glUniformMatrix4fv(
		shader.uniforms.mvProjMat.loc,
		1,
		gl.GL_FALSE,
		self.mvProjMat.ptr)
	gl.glUniform2i(shader.uniforms.pieceSize.loc,
		self.pieceSize.x,
		self.pieceSize.y)
	gl.glUniform3i(shader.uniforms.pieceOutlineSize.loc,
		self.pieceOutlineSize.x,
		self.pieceOutlineSize.y,
		self.pieceOutlineRadius)
	gl.glUniform3f(shader.uniforms.color.loc, player.color:unpack())

	srctex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
	srctex:unbind()

	sceneObj:disableAttrs()
	shader:useNone()

	fbo:unbind()

	gl.glViewport(0, 0, self.width, self.height)
	--]]
end

function App:rotatePiece(player)
	if not player.pieceTex then return end

	local fbo = self.pieceFBO
	local srctex = player.pieceTex
	local dsttex = self.rotPieceTex
	local shader = self.displayShader
	local sceneObj = self.displayQuadSceneObj
	gl.glViewport(0, 0, self.pieceSize.x, self.pieceSize.y)

	fbo:bind()
		:setColorAttachmentTex2D(dsttex.id)
	local res, err = fbo.check()
	if not res then print(err) end

	shader:use()
	sceneObj:enableAndSetAttrs()

	self.projMat:setOrtho(0, 1, 0, 1, -1, 1)
	self.mvMat
		:setTranslate(.5, .5, 0)
		:applyRotate(math.pi*.5, 0, 0, 1)
		:applyTranslate(-.5, -.5, 0)
	self.mvProjMat:mul4x4(self.projMat, self.mvMat)
	gl.glUniformMatrix4fv(
		shader.uniforms.mvProjMat.loc,
		1,
		gl.GL_FALSE,
		self.mvProjMat.ptr)
	gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 0)

	srctex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
	srctex:unbind()

	sceneObj:disableAttrs()
	shader:useNone()

	-- still needed by
	-- 	- App:updatePieceTex for calculating pieceColMin and pieceColMax
	--	- SandModel:testPieceMerge and SandModel:mergePiece
	gl.glReadPixels(
		0,						--GLint x,
		0,						--GLint y,
		self.pieceSize.x,		--GLsizei width,
		self.pieceSize.y,		--GLsizei height,
		gl.GL_RGBA,				--GLenum format,
		gl.GL_UNSIGNED_BYTE,	--GLenum type,
		dsttex.image.buffer)	--void *pixels

	fbo:unbind()

	gl.glViewport(0, 0, self.width, self.height)

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

function App:updateGame()
	local w, h = self.sandSize:unpack()
	local dt = self.thisTime - self.lastUpdateTime
	if dt <= self.updateInterval then return end
	dt = self.updateInterval

	--[[ fast-forward to catch up? messes up with pause too
	self.lastUpdateTime = self.lastUpdateTime + self.updateInterval
	--]]
	-- [[ stutter
	self.lastUpdateTime = self.thisTime
	--]]
	self.gameTime = self.gameTime + self.updateInterval
	self.gameTick = self.gameTick + 1

	local sandmodel = self.sandmodel
	local needsCheckLine = sandmodel:update()

	for _,player in ipairs(self.players) do
		player.piecePosLast:set(player.piecePos:unpack())
	end

	if self.recordingDemo then
		ffi.fill(self.recordingEvent, self.recordingEventSize)
		ffi.cast('gameTick_t*', self.recordingEvent)[0] = self.gameTick
		local buttonsPtr = ffi.cast('uint8_t*', self.recordingEvent) + ffi.sizeof'gameTick_t'
		local flagindex = 0
		local needwrite
		for playerIndex,player in ipairs(self.players) do
			for keyIndex,k in ipairs(player.gameKeyNames) do
				buttonsPtr[0] = bit.bor(
					buttonsPtr[0],
					bit.lshift(player.keyPress[k] and 1 or 0, flagindex)
				)
				if player.keyPress[k] ~= player.keyPressLast[k] then
					needwrite = true
				end
				flagindex = flagindex + 1
				if flagindex == 8 then
					flagindex = 0
					buttonsPtr = buttonsPtr + 1
				end
			end
		end
		if needwrite then
			--[[ print event
			io.write(('%08x'):format(ffi.cast('gameTick_t*', self.recordingEvent)[0]))
			for i=ffi.sizeof'gameTick_t',self.recordingEventSize-1 do
				io.write((' %02x'):format(self.recordingEvent[i]))
			end
			print()
			--]]
			self.recordingDemo:insert(ffi.string(self.recordingEvent, self.recordingEventSize))
		end
	elseif self.playingDemo then
		local event = self.playingDemo:get(self.recordingEventSize)
		if event and ffi.cast('gameTick_t*', event)[0] == self.gameTick then
			--[[ print event
			io.write(('%08x'):format(ffi.cast('gameTick_t*', event)[0]))
			for i=ffi.sizeof'gameTick_t',self.recordingEventSize-1 do
				io.write((' %02x'):format(event[i]))
			end
			print()
			--]]
			self.playingDemo.index = self.playingDemo.index + self.recordingEventSize
		else
			event = nil
		end
		if event then
			local buttonsPtr = ffi.cast('uint8_t*', event) + ffi.sizeof'gameTick_t'
			local flagindex = 0
			for playerIndex,player in ipairs(self.players) do
				for _,k in ipairs(player.gameKeyNames) do
					player.keyPress[k] = 1 == bit.band(1, bit.rshift(buttonsPtr[0], flagindex))
					flagindex = flagindex + 1
					if flagindex == 8 then
						flagindex = 0
						buttonsPtr = buttonsPtr + 1
					end
				end
			end
		end
	end

	-- now draw the shape over the sand
	-- test piece for collision with sand
	-- if it collides then merge it
	for _,player in ipairs(self.players) do
		-- TODO key updates at higher interval than drop rate ...
		-- but test collision for both
		-- TODO tap to move vs hold to move ... just like with dropping?  nah cuz that is still hold-to-go-full-speed
		-- maybe something more like original tetris, push to go one block, hold past a delay to go full speed
		local dx = 0
		if player.keyPress.left then dx = dx - 1 end
		if player.keyPress.right then dx = dx + 1 end
		player.piecePos.x = player.piecePos.x + dx * self.playcfg.movedx * self.gameScaleFloat
		self:constrainPiecePos(player)

		-- don't allow holding down through multiple drops ... ?
		if player.keyPress.down
		and not player.keyPressLast.down
		then
			player.droppingPiece = true
		end
		if not player.keyPress.down then
			player.droppingPiece = false
		end
		if player.droppingPiece then
			player.piecePos.y = player.piecePos.y - self.playcfg.dropSpeed * self.gameScaleFloat
		end
		if player.keyPress.up and not player.keyPressLast.up then
			self:rotatePiece(player)
		end
		if player.keyPress.pause
		and not player.keyPressLast.pause
		then
			-- only allow esc <-> pause/menu in th playing-state screen
			-- and also only when it's not yet paused
			-- hmmmmm pause is exceptional for player keys ...
			-- I'd like to make this always toggle the main menu or be the 'back' key (like Doom menu)
			local PlayingMenu = require 'sand-attack.menu.playing'
			if PlayingMenu:isa(self.menustate) then
				self.paused = not self.paused
			end
		end
	end

	self.fallTick = self.fallTick + 1
	if self.fallTick >= self.ticksToFall then
		self.fallTick = 0
		local falldy = 1/self.ticksToFall
		for _,player in ipairs(self.players) do
			player.piecePos.y = player.piecePos.y - falldy
		end
	end

	for _,player in ipairs(self.players) do
		local merge
		if player.piecePos.y <= -self.pieceSize.y then
			player.piecePos.x = player.piecePosLast.x
			for y=-self.pieceSize.y,math.floor(player.piecePosLast.y) do
				player.piecePos.y = y
				if not sandmodel:testPieceMerge(player) then break end
			end
			merge = true
		else
			if sandmodel:testPieceMerge(player) then
				player.piecePos.x = player.piecePosLast.x
				for y=math.floor(player.piecePos.y)+1,math.floor(player.piecePosLast.y) do
					player.piecePos.y = y
					if not sandmodel:testPieceMerge(player) then break end
				end
				merge = true
			end
		end
		if merge then
			self:playSound'sfx/place.wav'
			-- TODO should this be a game variable or a user variable?
			-- game variable.
			-- since it influences key press/release resolution
			-- and that's what drives the demo.
			if not self.playcfg.continuousDrop then
				player.droppingPiece = false	-- stop dropping piece
			end

			sandmodel:mergePiece(player)
			needsCheckLine = true

			-- piece Y + pieceRowMin is the row [0,h)
			-- so Y + pieceRowMax is the top ...
			-- so if that is ever >= h then we lose
			if player.piecePos.y + player.pieceRowMin >= h then
				self.loseTime = self.thisTime
			end

			self:newPiece(player)
		end
	end

	if not dontCheckForLinesEver then

		-- try to find a connection from left to right
		local anyCleared
		if needsCheckLine then
			local clearedCount = sandmodel:checkClearBlobs()
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
					self:playSound'sfx/levelup.wav'
					self:updateFallSpeed()
				end

				self:playSound'sfx/line.wav'

				-- flashTex was filled in by sandmodel:clearBlob
				-- ... which is still on CPU
				self.flashTex:bind():subimage()
				self.lastLineTime = self.gameTime

				-- sph only
				if sandmodel.doneClearingBlobs then
					sandmodel:doneClearingBlobs()
				end
			end
		end
	end

	-- TODO for sand model automata-gpu,
	--  we don't need to update in case of 'needsCheckLine' alone
	if sandmodel.sandImageDirty then
		local sandTex = sandmodel:getSandTex()
		sandTex:bind():subimage()
		sandmodel.sandImageDirty = false
	end

	for _,player in ipairs(self.players) do
		for k,v in pairs(player.keyPress) do
			player.keyPressLast[k] = v
		end
	end
end

function App:update(...)
	self.thisTime = getTime()

	gl.glClearColor(.5, .5, .5, 1)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	local w, h = self.sandSize:unpack()
	local sandmodel = self.sandmodel

	if not self.paused then
		-- if we haven't lost yet ...
		if not self.loseTime then
			self:updateGame()
		end

		--[[ pouring sand
		self.sandCPU[bit.rshift(w,1) + w * (h - 1)] = bit.bor(
			self.rng(0,16777215),
			0xff000000,
		)
		--]]

		-- draw

		local shader = self.displayShader
		local sceneObj = self.displayQuadSceneObj

		local aspectRatio = self.width / self.height
		local s = w / h

		if s < aspectRatio then
			-- if s < aspectRatio then we are vert-constrained, and we scale by [aspectRatio, 1]
			self.projMat:setOrtho(
				-.5 * aspectRatio / s,
				.5 * aspectRatio / s,
				-.5,
				.5,
				-1,
				1)
		else
			-- if s > aspectRatio then we are horz-constrained, and we scale by [1, 1/aspectRatio]
			--self.projMat:setOrtho(-.5, .5, -.5 / aspectRatio, .5 / aspectRatio, -1, 1)
			self.projMat:setOrtho(
				-.5,
				.5,
				-.5 * s / aspectRatio,
				.5 * s / aspectRatio,
				-1,
				1)
			-- TODO also translate so it lines up with the bottom of the screen ....
		end

		shader:use()
		sceneObj:enableAndSetAttrs()

		self.mvMat:setTranslate(-.5, -.5)
		self.mvProjMat:mul4x4(self.projMat, self.mvMat)
		gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

		gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 0)

		--[[ transparent for the background for sand area?
		gl.glEnable(gl.GL_ALPHA_TEST)
		--]]

		sandmodel:getSandTex():bind()
		gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

		--[[ transparent for the background for sand area?
		gl.glDisable(gl.GL_ALPHA_TEST)
		--]]

		-- draw the current piece
		for _,player in ipairs(self.players) do
			-- draw outline for multiplayer
			if self.playcfg.numPlayers > 1 then
				self.mvMat:setTranslate(
						(math.floor(player.piecePos.x) - self.pieceOutlineRadius) / w - .5,
						(math.floor(player.piecePos.y) - self.pieceOutlineRadius) / h - .5
					)
					:applyScale(
						(self.pieceSize.x + 2 * self.pieceOutlineRadius) / w,
						(self.pieceSize.y + 2 * self.pieceOutlineRadius) / h
					)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

				gl.glEnable(gl.GL_BLEND)
				gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE)

				player.pieceOutlineTex:bind()
				gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

				gl.glDisable(gl.GL_BLEND)
			end

			-- draw piece

			self.mvMat:setTranslate(
					math.floor(player.piecePos.x) / w - .5,
					math.floor(player.piecePos.y) / h - .5
				)
				:applyScale(
					self.pieceSize.x / w,
					self.pieceSize.y / h
				)
			self.mvProjMat:mul4x4(self.projMat, self.mvMat)
			gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

			gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 1)
			player.pieceTex:bind()
			gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

			gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 0)
		end

		-- draw flashing background if necessary
		local flashDt = self.gameTime - self.lastLineTime
		if flashDt < self.lineFlashDuration then
			self.wasFlashing = true
			gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 1)
			local flashInt = bit.band(math.floor(flashDt * self.lineNumFlashes * 2), 1) == 0
			if flashInt then
				self.mvMat
					:setTranslate(-.5, -.5)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

				self.flashTex:bind()
				gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
			end
			gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 0)
		elseif self.wasFlashing then
			-- clear once we're done flashing
			self.wasFlashing = false

			local dsttex = self.flashTex
			local fbo = sandmodel.fbo

			gl.glViewport(0, 0, w, h)
			fbo:bind()
				:setColorAttachmentTex2D(dsttex.id)
			local res, err = fbo.check()
			if not res then print(err) end

			gl.glClearColor(0, 0, 0, 0)
			gl.glClear(gl.GL_COLOR_BUFFER_BIT)

			gl.glReadPixels(
				0,						--GLint x,
				0,						--GLint y,
				w,						--GLsizei width,
				h,						--GLsizei height,
				gl.GL_RGBA,				--GLenum format,
				gl.GL_UNSIGNED_BYTE,	--GLenum type,
				dsttex.image.buffer)	--void *pixels

			fbo:unbind()
			gl.glViewport(0, 0, self.width, self.height)
		end

		if self.loseTime then
			local loseDuration = self.thisTime - self.loseTime
			if math.floor(loseDuration * 2) % 2 == 0 then
				self.mvMat
					:setTranslate(-.5, -.5)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

				gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 1)
				self.youloseTex:bind()
				gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
				gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 0)
			end
		end

		self.projMat:setOrtho(
			-.5 * aspectRatio,
			.5 * aspectRatio,
			-.5,
			.5,
			-1,
			1)

		local nextPieceSize = .1
		for i=#self.nextPieces,1,-1 do
			local it = self.nextPieces[i]
			local dy = #self.nextPieces == 1 and 0 or (1 - nextPieceSize)/(#self.nextPieces-1)
			dy = math.min(dy, nextPieceSize * 1.1)

			self.mvMat
				:setTranslate(aspectRatio * .5 - nextPieceSize, .5 - (i-1) * dy)
				:applyScale(nextPieceSize, -nextPieceSize)
			self.mvProjMat:mul4x4(self.projMat, self.mvMat)
			gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)

			it.tex:bind()
			gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
		end

		GLTex2D:unbind()
		sceneObj:disableAttrs()
		shader:useNone()
	end

	if self.loseTime
	and self.thisTime - self.loseTime > self.loseScreenDuration
	then
		if self.playingDemo then
			self:reset{
				playingDemoRecord = self.playcfg,
			}
			return
		else
			self:endGame()
		end
	end

	-- update GUI
	App.super.update(self, ...)
	glreport'here'


	-- draw menustate over gui?
	-- right now it's just the splash screen and the touch buttons
	if self.menustate.update then
		self.menustate:update()
	end

	if self.showFPS then
		self.fpsSampleCount = self.fpsSampleCount + 1
		if self.thisTime - self.lastFrameTime >= 1 then
			local deltaTime = self.thisTime - self.lastFrameTime
			self.fps = self.fpsSampleCount / deltaTime
print(self.fps)
			self.lastFrameTime = self.thisTime
			self.fpsSampleCount = 0
		end
	end
end
App.lastFrameTime = 0
App.fpsSampleCount = 0

-- called from menu upon early end
-- or from App loseTime is finished
function App:endGame()
	if self.playingDemo then
		-- :endGame called from PlayingMenu
		-- when you push esc while playing back a menu
		-- TODO menu/demos is all a mess
		local MainMenu = require 'sand-attack.menu.main'
		self.menustate = MainMenu(self)
		return
	end

	-- while we're here, write out the last key recording
	-- maybe in th future it'll go into the highscores data
	-- or maybe i'll compress it further meh
	-- Do this after opening the high-scores menu so that it has the option of doing something with this file?
	-- or maybe highscores overall will handle it?
	self.loseTime = nil
	self.paused = true
	-- if we're not playing a demo then we should be recording one
	-- I guess this might happen something something played a game, it ended, and something is replaying or something ...
	local demoPlayback = self.recordingDemo and self.recordingDemo:concat() or nil
	self.recordingDemo = nil
	if demoPlayback then
		local HighScoreMenu = require 'sand-attack.menu.highscore'
		self.menustate = HighScoreMenu(self, table(self.playcfg, {
			level = self.level,
			lines = self.lines,
			score = self.score,
			demoPlayback = demoPlayback,
		}))

		-- and reset and play demo again
		self:reset{
			playingDemoRecord = readDemo'splash.demo',
		}
	end
end

-- called from PlayingMenu:update, PlayerKeysEditor:update
-- because it's a ui / input feature I'll use app.cfg instead of app.playcfg
function App:drawTouchRegions()
	local buttonRadius = self.width * self.cfg.screenButtonRadius

	local shader = self.displayShader
	local sceneObj = self.displayQuadSceneObj

	gl.glEnable(gl.GL_BLEND)
	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE)
	shader:use()
	sceneObj:enableAndSetAttrs()
	gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 0)
	self.buttonTex:bind()
	self.projMat:setOrtho(0, self.width, self.height, 0, -1, 1)
	for i=1,self.cfg.numPlayers do
		for _,keyname in ipairs(Player.keyNames) do
			local e = self.cfg.playerKeys[i][keyname]
			if e	-- might not exist for new players >2 ...
			and (e[1] == App.sdlEventMouseButtonDown
				or e[1] == App.sdlEventFingerDown
			) then
				local x = e[2] * self.width
				local y = e[3] * self.height
				self.mvMat:setTranslate(
					x-buttonRadius,
					y-buttonRadius)
					:applyScale(2*buttonRadius, 2*buttonRadius)
				self.mvProjMat:mul4x4(self.projMat, self.mvMat)
				gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.mvProjMat.ptr)
				gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
			end
		end
	end
	self.buttonTex:unbind()
	sceneObj:disableAttrs()
	shader:useNone()
	gl.glDisable(gl.GL_BLEND)
end

function App:flipBoard()
	self.sandmodel:flipBoard()
end

-- static, used by gamestate and app
function App:getEventName(sdlEventID, a,b,c)
	if not a then return '?' end
	local function dir(d)
		local s = table()
		local ds = 'udlr'
		for i=1,4 do
			if 0 ~= bit.band(d,bit.lshift(1,i-1)) then
				s:insert(ds:sub(i,i))
			end
		end
		return s:concat()
	end
	local function key(k)
		return ffi.string(sdl.SDL_GetKeyName(k))
	end
	if self.sdlMajorVersion == 2 then
		return template(({
			--[App.sdlEventJoystickHatMotion] = 'joy<?=a?> hat<?=b?> <?=dir(c)?>',	-- not in 2?
			--[App.sdlEventJoystickAxisMotion] = 'joy<?=a?> axis<?=b?> <?=c?>',
			--[App.sdlEventJoystickButtonDown] = 'joy<?=a?> button<?=b?>',
			--[sdl.SDL_EVENT_GAMEPAD_AXIS_MOTION] = 'gamepad<?=a?> axis<?=b?> <?=c?>',
			--[sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN] = 'gamepad<?=a?> button<?=b?>',
			[App.sdlEventKeyDown] = 'key <?=key(a)?>',
			[App.sdlEventMouseButtonDown] = 'mouse <?=c?> x<?=math.floor(a*100)?> y<?=math.floor(b*100)?>',
			[App.sdlEventFingerDown] = 'finger x<?=math.floor(a*100)?> y<?=math.floor(b*100)?>',
		})[sdlEventID], {
			a=a, b=b, c=c,
			dir=dir, key=key,
		})
	else
		return template(({
			[App.sdlEventJoystickHatMotion] = 'joy<?=a?> hat<?=b?> <?=dir(c)?>',
			[App.sdlEventJoystickAxisMotion] = 'joy<?=a?> axis<?=b?> <?=c?>',
			[App.sdlEventJoystickButtonDown] = 'joy<?=a?> button<?=b?>',
			[App.sdlEventGamepadAxisMotion] = 'gamepad<?=a?> axis<?=b?> <?=c?>',
			[App.sdlEventGamepadButtonDown] = 'gamepad<?=a?> button<?=b?>',
			[App.sdlEventKeyDown] = 'key <?=key(a)?>',
			[App.sdlEventMouseButtonDown] = 'mouse <?=c?> x<?=math.floor(a*100)?> y<?=math.floor(b*100)?>',
			[App.sdlEventFingerDown] = 'finger x<?=math.floor(a*100)?> y<?=math.floor(b*100)?>',
		})[sdlEventID], {
			a=a, b=b, c=c,
			dir=dir, key=key,
		})
	end
end

-- this is used for player input, not for demo playback, so it'll use .cfg instead of .playcfg
function App:processButtonEvent(press, ...)
	local buttonRadius = self.width * self.cfg.screenButtonRadius

	-- TODO put the callback somewhere, not a global
	-- it's used by the New Game menu
	if self.waitingForEvent then
		-- this callback system is only used for editing keyboard binding
		if press then
			local ev = {...}
			ev.name = self:getEventName(...)
			self.waitingForEvent.callback(ev)
			self.waitingForEvent = nil
		end
	else
		-- this branch is only used in gameplay
		-- for that reason, if we're not in the gameplay menu-state then bail
		--if not PlayingMenu:isa(self.menustate) then return end

		local etype, ex, ey = ...
		local descLen = select('#', ...)
		for playerIndex, playerConfig in ipairs(self.cfg.playerKeys) do
			for buttonName, buttonDesc in pairs(playerConfig) do
				-- special case for mouse/touch, test within a distanc
				local match = descLen == #buttonDesc
				if match then
					local istart = 1
					-- special case for mouse/touch, click within radius ...
					if etype == App.sdlEventMouseButtonDown
					or etype == App.sdlEventFingerDown
					then
						match = etype == buttonDesc[1]
						if match then
							local dx = (ex - buttonDesc[2]) * self.width
							local dy = (ey - buttonDesc[3]) * self.height
							if dx*dx + dy*dy >= buttonRadius*buttonRadius then
								match = false
							end
							-- skip the first 2 for values
							istart = 4
						end
					end
					if match then
						for i=istart,descLen do
							if select(i, ...) ~= buttonDesc[i] then
								match = false
								break
							end
						end
					end
				end
				if match then
					local player = self.players[playerIndex]
					if player
					and (
						not self.playingDemo
						or not Player.gameKeySet[buttonName]
					) then
						player.keyPress[buttonName] = press
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

	if self.menustate.event then
		if self.menustate:event(e, ...) then return end
	end

	-- handle any kind of sdl button event
	if e[0].type == self.sdlEventJoystickHatMotion then
		--if e[0].jhat.value ~= 0 then
			-- TODO make sure all hat value bits are cleared
			-- or keep track of press/release
			for i=0,3 do
				local dirbit = bit.lshift(1,i)
				local press = bit.band(dirbit, e[0].jhat.value) ~= 0
				self:processButtonEvent(press, self.sdlEventJoystickHatMotion, e[0].jhat.which, e[0].jhat.hat, dirbit)
			end
			--[[
			if e[0].jhat.value == sdl.SDL_HAT_CENTERED then
				for i=0,3 do
					local dirbit = bit.lshift(1,i)
					self:processButtonEvent(false, self.sdlEventJoystickHatMotion, e[0].jhat.which, e[0].jhat.hat, dirbit)
				end
			end
			--]]
		--end
	elseif e[0].type == App.sdlEventJoystickAxisMotion then
		-- -1,0,1 depend on the axis press
		local lr = math.floor(3 * (tonumber(e[0].jaxis.value) + 32768) / 65536) - 1
		local press = lr ~= 0
		if not press then
			-- clear both left and right movement
			self:processButtonEvent(press, App.sdlEventJoystickAxisMotion, e[0].jaxis.which, e[0].jaxis.axis, -1)
			self:processButtonEvent(press, App.sdlEventJoystickAxisMotion, e[0].jaxis.which, e[0].jaxis.axis, 1)
		else
			-- set movement for the lr direction
			self:processButtonEvent(press, App.sdlEventJoystickAxisMotion, e[0].jaxis.which, e[0].jaxis.axis, lr)
		end
	elseif e[0].type == App.sdlEventJoystickButtonDown or e[0].type == App.sdlEventJoystickButtonUp then
		-- e[0].jbutton.menustate is 0/1 for up/down, right?
		local press = e[0].type == App.sdlEventJoystickButtonDown
		self:processButtonEvent(press, App.sdlEventJoystickButtonDown, e[0].jbutton.which, e[0].jbutton.button)
	elseif e[0].type == App.sdlEventGamepadAxisMotion then
		-- -1,0,1 depend on the axis press
		local lr = math.floor(3 * (tonumber(e[0].caxis.value) + 32768) / 65536) - 1
		local press = lr ~= 0
		if not press then
			-- clear both left and right movement
			self:processButtonEvent(press, App.sdlEventGamepadAxisMotion, e[0].caxis.which, e[0].jaxis.axis, -1)
			self:processButtonEvent(press, App.sdlEventGamepadAxisMotion, e[0].caxis.which, e[0].jaxis.axis, 1)
		else
			-- set movement for the lr direction
			self:processButtonEvent(press, App.sdlEventGamepadAxisMotion, e[0].caxis.which, e[0].jaxis.axis, lr)
		end
	elseif e[0].type == App.sdlEventGamepadButtonDown or e[0].type == App.sdlEventGamepadButtonUp then
		local press = e[0].type == App.sdlEventGamepadButtonDown
		self:processButtonEvent(press, App.sdlEventGamepadButtonDow, e[0].cbutton.which, e[0].cbutton.button)
	elseif e[0].type == App.sdlEventKeyDown or e[0].type == App.sdlEventKeyUp then
		local press = e[0].type == App.sdlEventKeyDown
		if App.sdlMajorVersion == 2 then
			self:processButtonEvent(press, App.sdlEventKeyDown, e[0].key.keysym.sym)
		else
			self:processButtonEvent(press, App.sdlEventKeyDown, e[0].key.key)
		end
	elseif e[0].type == App.sdlEventMouseButtonDown or e[0].type == App.sdlEventMouseButtonUp then
		local press = e[0].type == App.sdlEventMouseButtonDown
		self:processButtonEvent(press, App.sdlEventMouseButtonDown, tonumber(e[0].button.x)/self.width, tonumber(e[0].button.y)/self.height, e[0].button.button)
	--elseif e[0].type == sdl.SDL_MOUSEWHEEL then
	-- how does sdl do mouse wheel events ...
	elseif e[0].type == App.sdlEventFingerDown or e[0].type == App.sdlEventFingerUp then
		local press = e[0].type == App.sdlEventFingerDown
		self:processButtonEvent(press, App.sdlEventFingerDown, e[0].tfinger.x, e[0].tfinger.y)
	end

	-- TODO how to incorporate this into the gameplay ...
	--[[ don't do it for now, it'll mess with the demo recording
	if e[0].type == App.sdlEventKeyDown
	or e[0].type == App.sdlEventKeyUp
	then
		local down = e[0].type == App.sdlEventKeyDown
		if down and e[0].key.key == ('f'):byte() then
			if down then self:flipBoard() end
		end
	end
	--]]
end

function App:updateGUI()
	if self.font then
		ig.igPushFont(self.font)
	end
	if self.menustate.updateGUI then
		self.menustate:updateGUI()
	end
	if self.font then
		ig.igPopFont()
	end
end

function App:exit()
	if self.useAudio and self.audio then
		self.audio:shutdown()
	end
	App.super.exit(self)
end

return App
