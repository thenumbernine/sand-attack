local ffi = require 'ffi'
local class = require 'ext.class'
local ig = require 'imgui'

local Menu = class()

function Menu:init(app)
	local App = require 'sand-attack.app'
	assert(App:isa(app))
	self.app = assert(app)
end

-- TODO change the style around
function Menu:beginFullView(name, estheight)
estheight = nil
	-- TODO put in lua-imgui
	local viewport = ig.igGetMainViewport()
	ig.igSetNextWindowPos(viewport.WorkPos, 0, ig.ImVec2())
	ig.igSetNextWindowSize(viewport.WorkSize, 0)
	ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowRounding, 0)
	ig.igBegin(name, nil, bit.bor(
		ig.ImGuiWindowFlags_NoMove,
		ig.ImGuiWindowFlags_NoResize,
		ig.ImGuiWindowFlags_NoCollapse,
		ig.ImGuiWindowFlags_NoDecoration
	))
	self.viewCenterX = viewport.WorkSize.x * .5
	local viewheight = viewport.WorkSize.y * .5

	-- TODO calc this?
	if estheight and estheight < viewheight then
		ig.igSetCursorPosY(viewheight - .5 * estheight)
	end

	ig.igSetWindowFontScale(2)
	self:centerText(name)
	ig.igSetWindowFontScale(1)
end

function Menu:endFullView()
	ig.igEnd()
	ig.igPopStyleVar(1)
end

local tmp = ffi.new'ImVec2[1]'

function Menu:centerGUI(fn, text, ...)
	-- TODO put in lua-imgui
	-- TODO TODO for buttons and text this is fine, but for inputs the width can be *much wider* than the text width.
	local textwidth
	if self.overrideTextWidth ~= nil then
		textwidth = self.overrideTextWidth
	else
		ig.igCalcTextSize(tmp, text, nil, false, -1)
		textwidth = tmp[0].x
	end
	local x = self.viewCenterX - .5 * textwidth
	if x >= 0 then
		ig.igSetCursorPosX(x)
	end
	return fn(text, ...)
end

function Menu:centerText(...)
	return self:centerGUI(ig.igText, ...)
end

function Menu:centerButton(...)
	return self:centerGUI(ig.igButton, ...)
end

function Menu:centerLuatableCheckbox(...)
	return self:centerGUI(ig.luatableCheckbox, ...)
end

-- is ugly enough i have to fix this often enough so:
-- TODO fix somehow
function Menu:centerLuatableInputInt(...)
	self.overrideTextWidth = 360
	local result = self:centerGUI(ig.luatableInputInt, ...)
	self.overrideTextWidth = nil
	return result
end

function Menu:centerLuatableTooltipInputInt(...)
	self.overrideTextWidth = 360
	local result = self:centerGUI(ig.luatableTooltipInputInt, ...)
	self.overrideTextWidth = nil
	return result
end

function Menu:centerLuatableInputFloat(...)
	print"WARNING imgui gamepad nav can't change input float"
	self.overrideTextWidth = 360
	local result = self:centerGUI(ig.luatableInputFloat, ...)
	self.overrideTextWidth = nil
	return result
end

function Menu:centerLuatableTooltipInputFloat(...)
	print"WARNING imgui gamepad nav can't change input float"
	self.overrideTextWidth = 360
	local result = self:centerGUI(ig.luatableTooltipInputFloat, ...)
	self.overrideTextWidth = nil
	return result
end

function Menu:centerLuatableSliderFloat(...)
	self.overrideTextWidth = 360
	local result = self:centerGUI(ig.luatableSliderFloat, ...)
	self.overrideTextWidth = nil
	return result
end

function Menu:centerLuatableTooltipSliderFloat(...)
	self.overrideTextWidth = 360
	local result = self:centerGUI(ig.luatableTooltipSliderFloat, ...)
	self.overrideTextWidth = nil
	return result
end

return Menu
