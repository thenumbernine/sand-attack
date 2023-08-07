#!/usr/bin/env luajit
-- https://stackoverflow.com/questions/17372330/lua-socket-post 
require 'ext'
local URL = require 'socket.url'
local http = require 'socket.http'
local ltn12 = require 'ltn12'
local fn = assert(..., "usage: <filename>")
local reqbody = 'data='..URL.escape(assert(path(fn):read()))
local respbody = table()
print('response:')
print(tolua{http.request{
	method = 'POST',
	url = 'http://ihavenoparachute.com/sand-attack/submit.js.lua',
	source = ltn12.source.string(reqbody),
	sink = ltn12.sink.table(respbody),
	headers = {
		['Accept'] = '/*',
		['Accept-Encoding'] = 'gzip, deflate',
		['Accept-Language'] = 'en-us',
		['Content-Type'] = 'application/x-www-form-urlencoded',
		['Content-Length'] = #reqbody,
	},
}})
print('response body:')
print(respbody:concat())
