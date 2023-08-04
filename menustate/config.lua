--[[
TODO move the game-specific config stuff into the New Game menu.
Then the game-not-specific stuff (button size, volume, etc) allow accessible from in-game pause menu.
--]]
local ig = require 'imgui'
local MenuState = require 'sand-attack.menustate.menustate'
local PlayerKeysEditor = require 'sand-attack.menustate.playerkeys'

local ConfigState = MenuState:subclass()

function ConfigState:init(app, ...)
	ConfigState.super.init(self, app, ...)
	self.playerKeysEditor = PlayerKeysEditor(app)
end

-- if we're editing keys then show keys
function ConfigState:update()
	self.playerKeysEditor:update()
end

function ConfigState:updateGUI()
	local app = self.app
	self:beginFullView('Config', 6 * 32)

	ig.igNewLine()
	ig.igSeparatorText'Controls'
	ig.igNewLine()
	
	self.playerKeysEditor:updateGUI()
	ig.igNewLine()
	
	self:centerLuatableTooltipSliderFloat('On-Screen Button Radius', app.cfg, 'screenButtonRadius', .001, 1)

	if app.useAudio then
		ig.igNewLine()
		ig.igSeparatorText'Audio'
		ig.igNewLine()
		
		if self:centerLuatableTooltipSliderFloat('FX Volume', app.cfg, 'effectVolume', 0, 1) then
			--[[ if you want, update all previous audio sources...
			for _,src in ipairs(app.audioSources) do
				-- TODO if the gameplay sets the gain down then we'll want to multiply by their default gain
				src:setGain(app.cfg.effectVolume * src.gain)
			end
			--]]
		end
		if self:centerLuatableTooltipSliderFloat('BG Volume', app.cfg, 'backgroundVolume', 0, 1) then
			app.bgAudioSource:setGain(app.cfg.backgroundVolume)
		end
	end

	ig.igNewLine()
	if self:centerButton'Done' then
		app:saveConfig()
		-- you shouldn't be able to enter the config menustate without pushMenuState being set
		app.menustate = assert(app.pushMenuState)
		-- likewise don't leave the config menustate without clearning the last stat
		app.pushMenuState = nil
	end
	self:endFullView()
end

return ConfigState
