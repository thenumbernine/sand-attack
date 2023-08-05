local table = require 'ext.table'
local path = require 'ext.path'
local range = require 'ext.range'
local ops = require 'ext.op'
local ig = require 'imgui'
local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
local mytolua = require 'sand-attack.serialize'.tolua
local Menu = require 'sand-attack.menu.menu'
local readDemo = require 'sand-attack.serialize'.readDemo

local HighScoresMenu = Menu:subclass()

function HighScoresMenu:init(app, needsName, recordingDemo)
	HighScoresMenu.super.init(self, app)
	self.needsName = needsName
	self.name = ''
	self.recordingDemo = recordingDemo
	if needsName then assert(self.recordingDemo) end
end

-- shown fields
HighScoresMenu.shownFields = table{
	'name',
	'score',
}

-- all recorded fields
HighScoresMenu.fields = table{
	-- from HighScoresMenu
	'name',
	-- from app:
	'lines',
	'level',
	'score',
	-- from cfg:
	'numPlayers',
	'numColors',
	'boardWidthInBlocks',
	'boardHeightInBlocks',
	'toppleChance',
	'voxelsPerBlock',
	'speedupCoeff',
	'randseed',
	-- from cfg but needs to be mapped
	'sandModel',
}

function HighScoresMenu:makeNewRecord()
	local app = self.app
	local record = {}
	for _,field in ipairs(self.fields) do
		if field == 'name' then
			record[field] = self[field]
		elseif field == 'numPlayers'
		or field == 'numColors'
		or field == 'boardWidthInBlocks'
		or field == 'boardHeightInBlocks'
		or field == 'toppleChance'
		or field == 'voxelsPerBlock'
		or field == 'speedupCoeff'
		or field == 'randseed'
		then
			record[field] = app.playcfg[field]
		elseif field == 'sandModel' then
			record[field] = sandModelClassNames[app.playcfg[field]]
		else
			record[field] = app[field]
		end
	end
	
	-- give it a new unique id
	record.demofilename = (
		-- use the next integer available
		(table.mapi(app.highscores, function(r)
			return tonumber((r.demofilename:match'^(%d+)%.demo$')) or 0
		end):sup() or 0) + 1
	)..'.demo'

	return record
end

-- TODO mkdir and save one file per entry
function HighScoresMenu:saveHighScore(record, recordingDemo)
	assert(record.demofilename, "every record needs a demofilename")
	local fn = 'highscores/'..assert(record.demofilename)
print('writing highscore', fn)
	assert(not path(fn):exists(), "tried to write but it's already there")
	
	-- write new unique name?
	-- what happens if i write twice?  duplicate entries?
	-- how to fix this?
	-- give unique id?
	-- but unique ids are only locally unique ...
	path(fn):write(
		mytolua(record)
		..'\0'
		..recordingDemo
	)
end

function HighScoresMenu:updateGUI()
	local app = self.app
	self:beginFullView'High Scores:'

	-- TODO separate state for this?
	if self.needsName then
		assert(self.recordingDemo)
		ig.igText'Your Name:'
		ig.luatableTooltipInputText('Your Name', self, 'name')
		if ig.igButton'Ok' then
			self.needsName = false
			local record = self:makeNewRecord()
			table.insert(app.highscores, record)
			table.sort(app.highscores, function(a,b) return a.score > b.score end)
			self:saveHighScore(record, self.recordingDemo)
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
			local score = app.highscores[i]
			ig.igPushID_Int(i)
			ig.igTableNextRow(0, 0)
			for j,field in ipairs(self.shownFields) do
				ig.igPushID_Int(j)
				ig.igTableNextColumn()
				local s = tostring(score[field])
				if j == 1 then
					if ig.igButton(s) then
						local record, demo = readDemo('highscores/'..score.demofilename)
						-- demos sandModel is stored as a string
						-- TODO all should be
						record.sandModel = sandModelClassNames:find(record.sandModel)
						-- TODO I need to save these too
						record.numNextPieces = record.numNextPieces or 3
						record.colors = table(app.colors):setmetatable(nil)
						while #record.colors < record.numColors do
							table.insert(record.colors, app:getDefaultColor(#record.colors+1))
						end
						-- TODO TODO TODO save this in the demo file
						record.startLevel = app.cfg.startLevel
						record.movedx = app.cfg.movedx
						record.dropSpeed = app.cfg.dropSpeed
						
						if record.sandModel then
							app:reset{
								playingDemoRecord = record,
								playingDemoDemo = demo,
							}
							local PlayingMenu = require 'sand-attack.menu.playing'
							app.menustate = PlayingMenu(app)	-- sets paused=false
						end
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
			path'highscores':mkdir()
			for f in path'highscores':dir() do
				if f:match'%.demo$' then
					path('highscores/'..f):remove()
				end
			end
		end
	end
	self:endFullView()
end

return HighScoresMenu
