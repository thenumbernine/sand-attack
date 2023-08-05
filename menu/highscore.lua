local table = require 'ext.table'
local range = require 'ext.range'
local ops = require 'ext.op'
local ig = require 'imgui'
local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
local Menu = require 'sand-attack.menu.menu'

local HighScoresMenu = Menu:subclass()

function HighScoresMenu:init(app, needsName)
	HighScoresMenu.super.init(self, app)
	self.needsName = needsName
	self.name = ''
end

HighScoresMenu.fields = table{
	-- from HighScoresMenu
	'name',
	-- from app:
	'lines',
	'level',
	'score',
	'numPlayers',
	-- from cfg:
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
		elseif field == 'numColors'
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
	return record
end

function HighScoresMenu:updateGUI()
	local app = self.app
	self:beginFullView'High Scores:'

	-- TODO separate state for this?
	if self.needsName then
		ig.igText'Your Name:'
		ig.luatableTooltipInputText('Your Name', self, 'name')
		if ig.igButton'Ok' then
			self.needsName = false
			local record = self:makeNewRecord()
			table.insert(app.highscores, record)
			table.sort(app.highscores, function(a,b)
				return a.score > b.score
			end)
			app:saveHighScores()
		end
		ig.igNewLine()
	end

	if ig.igBeginTable('High Scores', #self.fields, bit.bor(
		ig.ImGuiTableFlags_Resizable,
		ig.ImGuiTableFlags_Reorderable,
		ig.ImGuiTableFlags_Sortable,
		ig.ImGuiTableFlags_SortMulti,
		ig.ImGuiTableFlags_BordersOuter,
		ig.ImGuiTableFlags_BordersV,
	0), ig.ImVec2(0,0), 0) then

		for i,field in ipairs(self.fields) do
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
					local field = self.fields[tonumber(col)]
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
			ig.igTableNextRow(0, 0)
			for _,field in ipairs(self.fields) do
				ig.igTableNextColumn()
				ig.igText(tostring(score[field]))
			end
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
			app:saveHighScores()
		end
	end
	self:endFullView()
end

return HighScoresMenu
