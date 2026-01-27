local table = require 'ext.table'
local path = require 'ext.path'
local range = require 'ext.range'
local string = require 'ext.string'
local ops = require 'ext.op'
local ig = require 'imgui'
local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
local mytolua = require 'sand-attack.serialize'.tolua
local writeDemo = require 'sand-attack.serialize'.writeDemo
local Menu = require 'sand-attack.menu.menu'

local HighScoreMenu = Menu:subclass()

function HighScoreMenu:init(app, newRecord)
	HighScoreMenu.super.init(self, app)
	self.newRecord = newRecord
	if newRecord then
		newRecord.name = ''
	end
end

-- shown fields
HighScoreMenu.shownFields = table{
	'name',
	'score',
	'level',
	'lines',
}

-- called only by HighScoreMenu:updateGUI
-- mkdirs and saves one file per entry
function HighScoreMenu:saveHighScore(record)
	assert(record.demoFileName, "every record needs a demoFileName")
	assert(record.demoPlayback, "every record needs a demoPlayback")

	local fn = assert(record.demoFileName)
	assert(not path(fn):exists(), "tried to write but it's already there")

	writeDemo(fn, record)
end

function HighScoreMenu:updateGUI()
	local app = self.app
	self:beginFullView'High Scores:'

	-- TODO separate state for this?
	if self.newRecord then
		ig.igText'Your Name:'
		ig.luatableTooltipInputText('Your Name', self.newRecord, 'name')
		local gotOk = ig.igButton'Ok'
		ig.igSameLine()
		local gotSubmit = ig.igButton'Submit'

		if gotOk or gotSubmit then
			if not app.highScorePath then
				self.newRecord = nil
			else
				-- assigns demoFileName
				local record = self.newRecord
				self.newRecord = nil

				-- give it a new unique filename for saving
				local base = app.highScorePath..'/'..os.date'%Y-%m-%d-%H-%M-%S'
				local fn
				for i=0,math.huge do
					fn = base..(i == 0 and '' or ('-'..i))..'.demo'
					if not path(fn):exists() then break end
				end
				record.demoFileName = fn

				table.insert(app.highscores, record)
				table.sort(app.highscores, function(a,b) return a.score > b.score end)

				self:saveHighScore(record)

				if gotSubmit then
					self:submitScore(record)
				end
			end
		end

		ig.igNewLine()
	end

	if ig.igBeginTable('High Scores', #self.shownFields, bit.bor(
		ig.ImGuiTableFlags_Resizable,
		ig.ImGuiTableFlags_Reorderable,
		ig.ImGuiTableFlags_Sortable,
		ig.ImGuiTableFlags_SortMulti,
		ig.ImGuiTableFlags_BordersOuter,
		ig.ImGuiTableFlags_BordersV,
	0), ig.ImVec2(0,0), 0) then

		for i,field in ipairs(self.shownFields) do
			ig.igTableSetupColumn(tostring(field), bit.bor(
					ig.ImGuiTableColumnFlags_DefaultSort
				),
				0,
				i	-- ColumnUserID in the sort
			)
		end
		ig.igTableHeadersRow()
		local sortSpecs = ig.igTableGetSortSpecs()
		if not self.rowindexes or #self.rowindexes ~= #app.highscores then
			self.rowindexes = range(#app.highscores)
		end
		if sortSpecs[0].SpecsDirty then
			local typescore = {
				string = 1,
				number = 2,
				table = 3,
				['nil'] = math.huge,
			}
			-- sort from imgui_demo.cpp CompareWithSortSpecs
			-- TODO maybe put this in lua-imgui
			table.sort(self.rowindexes, function(ia,ib)
				local a = app.highscores[ia]
				local b = app.highscores[ib]
				for n=0,sortSpecs[0].SpecsCount-1 do
					local sortSpec = sortSpecs[0].Specs[n]
					local col = sortSpec.ColumnUserID
					local field = self.shownFields[tonumber(col)]
					local afield = a[field]
					local bfield = b[field]
					local tafield = type(afield)
					local tbfield = type(bfield)
--print('testing', afield, bfield, tafield, tbfield)
					if afield ~= bfield then
						local op = sortSpec.SortDirection == ig.ImGuiSortDirection_Ascending and ops.lt or ops.gt
						if tafield ~= tbfield then
							-- put nils last ... score for type?
							return op(typescore[tafield], typescore[tbfield])
						end
						return op(afield, bfield)
					end
				end
				return ia < ib
			end)
			sortSpecs[0].SpecsDirty = false
		end
		for _,i in ipairs(self.rowindexes) do
			local record = app.highscores[i]
			ig.igPushID_Int(i)
			ig.igTableNextRow(0, 0)
			for j,field in ipairs(self.shownFields) do
				ig.igPushID_Int(j)
				ig.igTableNextColumn()
				local s = tostring(record[field])
				local isbutton = j == 1 and record.demoPlayback and not self.newRecord
				if isbutton then
					if ig.igButton(s) then
						xpcall(function()
							-- use the current configured colors...
							record.colors = table(app.cfg.colors):setmetatable(nil)
							while #record.colors < record.numColors do
								table.insert(record.colors, app:getDefaultColor(#record.colors+1))
							end

							app:reset{
								-- "demoConfig"?
								playingDemoRecord = record,
							}
							local PlayingMenu = require 'sand-attack.menu.playing'
							app.menustate = PlayingMenu(app)	-- sets paused=false
						end, function(err)
							print('failed to play demo file '..tostring(record.demoFileName)..'\n'
								..tostring(err)..'\n'
								..debug.traceback())
						end)
					end
					ig.igSameLine()
					if ig.igButton'Submit' then
						self:submitScore(record)
					end
				else
					ig.igText(s)
				end
				ig.igPopID()
			end
			ig.igPopID()
		end
		ig.igEndTable()
	end

	-- Do popups always need to be run from root /newframe scope of imgui?
	-- If so then why does my color picker popup work?
	-- Does pushid affect openpopup?  i would think no.
	-- Does it affect beginpopup?  I would think yes.
	-- Hmm seems openpopup_id / beginpopupex (using id) works, but using strings (with pushid around the openpopup) fails ...
	--- would be better if imgui didn't have pushed IDs affect the open popup
	--  because ... if you want to open a more-global-scoped ID ... you can't.  because the pushed IDs will always be appended to you.
	-- I mean thats just a guess, but here's the real world case where pushid / openpopup fails (but openpopup alone works in newgamme color editor)
	--  and pushid/ openpopup (via id)/ beginpopupex(via id) works.
	if self.submitResponse then
		--if ig.igBeginPopupModal('Response', nil, 0) then
		--if ig.igBeginPopup('Response', 0) then
		-- TODO now to just find how to give it a title...
		if ig.igBeginPopupEx(12345, 0) then
			ig.igPushID_Str'SubmitResponse'
			ig.igText(self.submitResponse)
			if ig.igButton'Close' then
				ig.igCloseCurrentPopup()
				self.submitResponse = nil
			end
			ig.igPopID()
			ig.igEndPopup()
		end
	end

	if ig.igButton'Done' then
		self.newRecord = nil
		local MainMenu = require 'sand-attack.menu.main'
		app.menustate = MainMenu(app)
	end
	if not self.newRecord
	and app.highScorePath
	then
		ig.igSameLine()
		if ig.igButton'Clear' then
			app.highscores = {}
			path(app.highScorePath):mkdir()
			for f in path(app.highScorePath):dir() do
				if f.path:match'%.demo$' then
					path(app.highScorePath..'/'..f):remove()
				end
			end
		end
	end
	self:endFullView()
end

function HighScoreMenu:submitScore(record)
	xpcall(function()
		local record = table(record)
		-- encode as hex string (for serialization's sake) (just like in writeDemo)
		if record.demoPlayback then
			record.demoPlayback = string.hex(record.demoPlayback)
		end
		-- matches the test-submit-demo.lua
		local URL = require 'socket.url'
		local reqbody = 'data='..URL.escape(mytolua(record))
		local respbody = table()
		print('response:')
		local http = require 'socket.http'
		local ltn12 = require 'ltn12'
		print(mytolua{http.request{
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
		local response = string.trim(respbody:concat())
		print(response)

		if response == '{"result":"win"}' then
			self.submitResponse = 'Success!'
		else
			self.submitResponse = 'Server Problems...'
		end

	end, function(err)
		print('failed to submit highscore '..mytolua(s)..'\n'
			..tostring(err)..'\n'
			..debug.traceback())
		self.submitResponse = 'Something Broke...'
	end)
	if self.submitResponse then
		--ig.igOpenPopup_Str('Response', 0)	-- doesn't work.  I think pushid is mixing with openpopup when that's a horrible implementation idea.
		ig.igOpenPopup_ID(12345, 0)			-- works
	end
end

return HighScoreMenu
