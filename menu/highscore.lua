local table = require 'ext.table'
local path = require 'ext.path'
local range = require 'ext.range'
local ops = require 'ext.op'
local ig = require 'imgui'
local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
local mytolua = require 'sand-attack.serialize'.tolua
local writeDemo = require 'sand-attack.serialize'.writeDemo
local Menu = require 'sand-attack.menu.menu'

local HighScoresMenu = Menu:subclass()

function HighScoresMenu:init(app, needsName, demoPlayback)
	HighScoresMenu.super.init(self, app)
	self.needsName = needsName
	self.name = ''
	self.demoPlayback = demoPlayback
	if needsName then assert(self.demoPlayback) end
end

-- shown fields
HighScoresMenu.shownFields = table{
	'name',
	'score',
}

function HighScoresMenu:makeNewRecord()
	local app = self.app
	local record = table(app.playcfg):setmetatable(nil)

	-- copy from self:
	record.name = self.name
	-- copy from app:
	record.lines = app.lines
	record.level = app.level
	record.score = app.score

	-- give it a new unique filename for saving
	local base = app.highScorePath..'/'..os.date'%Y-%m-%d-%H-%M-%S'
	local fn
	for i=0,math.huge do
		fn = base..(i == 0 and '' or ('-'..i))..'.demo'
		if not path(fn):exists() then break end
	end
	record.demoFileName = fn

	return record
end

-- called only by HighScoresMenu:updateGUI
-- mkdirs and saves one file per entry
function HighScoresMenu:saveHighScore(record)
	assert(record.demoFileName, "every record needs a demoFileName")
	assert(record.demoPlayback, "every record needs a demoPlayback")

	local fn = assert(record.demoFileName)
	assert(not path(fn):exists(), "tried to write but it's already there")

	writeDemo(fn, record)
end

function HighScoresMenu:updateGUI()
	local app = self.app
	self:beginFullView'High Scores:'

	-- TODO separate state for this?
	if self.needsName then
		assert(self.demoPlayback)
		ig.igText'Your Name:'
		ig.luatableTooltipInputText('Your Name', self, 'name')
		if ig.igButton'Ok' then
			local record = self:makeNewRecord()
			record.demoPlayback = self.demoPlayback

			table.insert(app.highscores, record)
			table.sort(app.highscores, function(a,b) return a.score > b.score end)

			self:saveHighScore(record)

			self.needsName = false
			self.demoPlayback = nil
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
				local isbutton = j == 1 and record.demoPlayback
				if j == 1 then
					if ig.igButton(s) then
						xpcall(function()
							-- use the current configured colors...
							record.colors = table(app.colors):setmetatable(nil)
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
				else
					ig.igText(s)
				end
				ig.igPopID()
			end
			ig.igPopID()
		end
		ig.igEndTable()
	end
	if ig.igButton'Done' then
		self.needsName = false
		local MainMenu = require 'sand-attack.menu.main'
		app.menustate = MainMenu(app)
	end
	if not self.needsName then
		ig.igSameLine()
		if ig.igButton'Clear' then
			app.highscores = {}
			path(app.highScorePath):mkdir()
			for f in path(app.highScorePath):dir() do
				if f:match'%.demo$' then
					path(app.highScorePath..'/'..f):remove()
				end
			end
		end
	end
	self:endFullView()
end

return HighScoresMenu
