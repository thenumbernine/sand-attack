#!/usr/bin/env luajit
--[[
sanitation check
--]]
local path = require 'ext.path'

local fn = assert(..., "expected filename")
local data = assert(path(fn):read())

-- ULL suffix on numbers, luajit but not lua ...
-- TODO add ULL suffix to parser
data = data:gsub('(\trandseed=%d+)ULL,', '%1,')

local parser = require 'parser'
local tree = parser.parse('return '..data)
local usedTypes = {}
local function check(x)
	for k,v in pairs(x) do
		if type(v) == 'table'
		and k ~= 'parent'	-- TODO need a list of child keys
		then
			if v.type then
				usedTypes[v.type] = (usedTypes[v.type] or 0) + 1
			end
			check(v)
		end
	end
end
check(tree)
if usedTypes['function'] then
	print('... got an evil file')
end
