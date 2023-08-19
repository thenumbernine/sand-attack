local ffi = require 'ffi'
local vec2i = require 'vec-ffi.vec2i'
local Image = require 'image'
local SandModel = require 'sand-attack.sandmodel.sandmodel'

-- gpu implementation of automata sand
-- TODO add toppleChance

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
		vertexCode = app.shaderHeader..[[
in vec2 vertex;

out vec2 texcoordv;

uniform mat4 mvProjMat;

void main() {
	texcoordv = vertex;
	gl_Position = mvProjMat * vec4(vertex, 0., 1.);
}
]],
		fragmentCode = app.shaderHeader..[[
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
	}:useNone()

	self.testMergeShader = GLProgram{
		vertexCode = app.shaderHeader..[[
in vec2 vertex;
out vec2 texcoordv;
uniform mat4 mvProjMat;

void main() {
	texcoordv = vertex.xy;
	gl_Position = mvProjMat * vec4(vertex.xy, 0., 1.);
}
]],
		fragmentCode = app.shaderHeader..[[
in vec2 texcoordv;
out vec4 fragColor;

uniform ivec2 piecePos;
uniform ivec2 pieceSize;
uniform int row;

uniform sampler2D boardTex;
uniform sampler2D pieceTex;

void main() {
	int itcx = int(texcoordv.x * float(pieceSize.x));
	// calculate texel on boardtex and on piecetex
	ivec2 pieceitc = ivec2(itcx, row);
	ivec2 boarditc = pieceitc + piecePos;
	vec4 boardColor = texelFetch(boardTex, boarditc, 0);
	vec4 pieceColor = texelFetch(pieceTex, pieceitc, 0);

	if (boardColor.w != 0. && pieceColor.w != 0.) {
		fragColor = vec4(1.);
	} else {
		fragColor = vec4(0.);
	}
}
]],
		uniforms = {
			boardTex = 0,
			pieceTex = 1,
		},
	}:useNone()

	-- temp texture used for testing collisions
	self.testMergeTex = app:makeTexWithBlankImage(vec2i(app.pieceSize.x, 1))
end

-- [[ how to test merge on GPU?
-- same trick as histogram ...
-- render to a FBO that is [pieceSize.x, 1] in size.
-- input textures are the piece tex and current board tex
-- shader writes '1' if either overlaps
-- enable blend (one, one)
-- then sum results with CPU
function AutomataSandGPU:testPieceMerge(player)
	local app = self.app
	local w, h = app.sandSize:unpack()

	-- test board bottom boundary ...
	if player.pieceRowMin	-- if we have a shape ...
	and math.floor(player.piecePos.y) + player.pieceRowMin <= 0
	then
		return true
	end

	local fbo = self.fbo
	local dsttex = self.testMergeTex
	local shader = self.testMergeShader
	local sceneObj = app.displayQuadSceneObj 
	local sandTex = self:getSandTex()

	gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE)
	gl.glEnable(gl.GL_BLEND)

	shader:use()
	sceneObj:enableAndSetAttrs()

	gl.glViewport(0, 0, app.pieceSize.x, 1)

	fbo:bind()
		:setColorAttachmentTex2D(dsttex.id)
	local res, err = fbo.check()
	if not res then print(err) end

	gl.glClearColor(0,0,0,0)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	app.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)
	gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)
	gl.glUniform2i(shader.uniforms.piecePos.loc, math.floor(player.piecePos.x), math.floor(player.piecePos.y))
	gl.glUniform2i(shader.uniforms.pieceSize.loc, app.pieceSize:unpack())
	sandTex:bind(0)
	player.pieceTex:bind(1)

	for row=0,app.pieceSize.y-1 do
		gl.glUniform1i(shader.uniforms.row.loc, row)
		gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
	end

	player.pieceTex:unbind(1)
	sandTex:unbind(0)

	gl.glReadPixels(
		0,							--GLint x,
		0,							--GLint y,
		app.pieceSize.x,			--GLsizei width,
		1,							--GLsizei height,
		gl.GL_RGBA,					--GLenum format,
		gl.GL_UNSIGNED_BYTE,		--GLenum type,
		dsttex.image.buffer)		--void *pixels

	fbo:unbind()

	gl.glDisable(gl.GL_BLEND)

	sceneObj:disableAttrs()
	shader:useNone()

	gl.glViewport(0, 0, app.width, app.height)

	local overlap
	local p = dsttex.image.buffer
	for i=0,app.pieceSize.x-1 do
		if p[3] ~= 0 then
			overlap = true
			break
		end
		p = p + 4
	end

	return overlap
end
--]]

-- [=[
function AutomataSandGPU:mergePiece(player)
	local app = self.app
	local w, h = app.sandSize:unpack()

	local fbo = self.fbo
	local srctex = self.pp:prev()
	local dsttex = self.pp:cur()
	local sceneObj = app.displayQuadSceneObj 
	local shader = app.displayShader

	gl.glViewport(0, 0, w, h)

	fbo:bind()
	fbo:setColorAttachmentTex2D(dsttex.id)
	local res,err = fbo.check()
	if not res then print(err) end

	gl.glClearColor(0,0,0,0)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	shader:use()
	sceneObj:enableAndSetAttrs()
	
	gl.glUniform1i(shader.uniforms.useAlphaTest.loc, 1)
	
	app.projMat:setOrtho(0, 1, 0, 1, -1, 1)
	app.mvMat
		:setIdent()
		:applyTranslate(
			math.floor(player.piecePos.x) / w,
			math.floor(player.piecePos.y) / h
		)
		:applyScale(
			app.pieceSize.x / w,
			app.pieceSize.y / h
		)
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)

	player.pieceTex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)

	app.mvMat:setIdent()
	app.mvProjMat:mul4x4(app.projMat, app.mvMat)
	gl.glUniformMatrix4fv(shader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, app.mvProjMat.ptr)

	srctex:bind()
	gl.glDrawArrays(gl.GL_TRIANGLE_STRIP, 0, 4)
	srctex:unbind()

	sceneObj:disableAttrs()
	shader:useNone()

	self.pp:swap()

-- [[
	-- read to srctex instead of dsttex because swap()
	-- still needed for blob detection
	gl.glReadPixels(
		0,							--GLint x,
		0,							--GLint y,
		w,							--GLsizei width,
		h,							--GLsizei height,
		gl.GL_RGBA,					--GLenum format,
		gl.GL_UNSIGNED_BYTE,		--GLenum type,
		self:getSandTex().image.buffer)		--void *pixels
-- 	sandImageDirty says to copy cpu -> gpu so ...
-- we're already on the gpu ...
--	self.sandImageDirty = true
--]]

	fbo:unbind()

	gl.glViewport(0, 0, app.width, app.height)
end
--]=]

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
			if app.rng() < .5 then
				p[0] = app.rng(0, 0xffffffff)
			end
			p=p+1
		end
	end

	print'before'
	local beforeStr = printBuf(self.sandTex.image.buffer, w, h, 0)

	local shader = self.updateShader
	local sceneObj = app.displayQuadSceneObj 
	
	-- copy sandtex to pingpong
	self.pp:prev()
		:bind()
		:subimage{data=self.sandTex.image.buffer}
		:unbind()

	app.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)

	shader:use()
	sceneObj:enableAndSetAttrs()
	gl.glUniformMatrix4fv(
		shader.uniforms.mvProjMat.loc,
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
							gl.glUniform3i(shader.uniforms.ofs.loc, xofs, yofs, toppleRight)
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

	sceneObj:disableAttrs()
	shader:useNone()

	os.exit()
end

local glreport = require 'gl.report'
function AutomataSandGPU:update()
	local app = self.app
	local w, h = app.sandSize:unpack()

	local fbo = self.pp.fbo
	local shader = self.updateShader
	local sceneObj = app.displayQuadSceneObj 

	shader:use()
	sceneObj:enableAndSetAttrs()

	app.mvProjMat:setOrtho(0, 1, 0, 1, -1, 1)
	gl.glUniformMatrix4fv(
		shader.uniforms.mvProjMat.loc,
		1,
		gl.GL_FALSE,
		app.mvProjMat.ptr)

	local rightxor = app.rng(0,1)
	local xofsxor = app.rng(0,1)
	local yofsxor = app.rng(0,1)

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
	-- still needed for blob detection
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

	sceneObj:disableAttrs()
	shader:useNone()
	
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

-- TODO :cur() should be current soooo
-- ... swap usage of cur() and prev(), and put :swap() *before* the FBO update
function AutomataSandGPU:getSandTex()
	return self.pp:prev()
end

return AutomataSandGPU
