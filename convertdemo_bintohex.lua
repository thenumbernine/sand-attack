#!/usr/bin/env luajit
-- convert the old binary-trailing keystroke demo to new hex-encoded strings as the .demoPlayback field
require 'ext'
local ffi = require 'ffi'
require 'ffi.req' 'c.string'	--strlen
local infn, outfn = ...
assert(infn and outfn, "expected <in> <out>")
local d = assert(path(infn):read())
local n = tonumber(ffi.C.strlen(d))	-- TODO same as just d:find'\0' ? ... with endline?
local cfgstr = d:sub(1,n)
local cfg = assert(fromlua(cfgstr))
assert(d:byte(n+1) == 0)
local demoPlayback = d:sub(n+2)

local Player = require 'sand-attack.player'
-- matches app.lua
ffi.cdef[[ typedef uint32_t gameTick_t; ]]
local recordingEventSize = ffi.sizeof'gameTick_t' + math.ceil(cfg.numPlayers * #Player.gameKeyNames / 8)
assert(#demoPlayback % recordingEventSize == 0)

local strtohex = require 'sand-attack.serialize'.strtohex

cfg.demoPlayback = strtohex(demoPlayback)

-- make sure we encode cdata correctly
local mytolua = require 'sand-attack.serialize'.mytolua
assert(path(outfn):write(assert(mytolua(cfg))))
