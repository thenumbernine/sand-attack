local ig = require 'imgui'
local sandModelClassNames = require 'sand-attack.sandmodel.all'.classNames
local MenuState = require 'sand-attack.menustate.menustate'

local ConfigState = MenuState:subclass()

function ConfigState:updateGUI()
	local app = self.app
	self:beginFullView('Config', 6 * 32)

	self:centerLuatableTooltipInputInt('Number of Next Pieces', app.cfg, 'numNextPieces')
	self:centerLuatableTooltipSliderFloat('Drop Speed', app.cfg, 'dropSpeed', .1, 100, nil, ig.ImGuiSliderFlags_Logarithmic)
	self:centerLuatableTooltipSliderFloat('Move Speed', app.cfg, 'movedx', .1, 100, nil, ig.ImGuiSliderFlags_Logarithmic)
	self:centerLuatableCheckbox('Continuous Drop', app.cfg, 'continuousDrop')

	self:centerLuatableTooltipSliderFloat('Per-Level Speedup Coeff', app.cfg, 'speedupCoeff', .07, .00007, '%.5f', ig.ImGuiSliderFlags_Logarithmic)

	self:centerText'Board:'
	self:centerLuatableTooltipInputInt('Board Width', app.cfg.boardSizeInBlocks, 'x')
	self:centerLuatableTooltipInputInt('Board Height', app.cfg.boardSizeInBlocks, 'y')

	if self:centerLuatableTooltipInputInt('Pixels Per Block', app.cfg, 'voxelsPerBlock') then
		app:updateGameScale()
	end
	-- TODO should this be customizable?
	self:centerText('(updates/tick: '..app.gameScale..')')

	-- TODO this is only for AutomataCPU ...
	self:centerLuatableTooltipSliderFloat('Topple Chance', app.cfg, 'toppleChance', 0, 1)

	ig.luatableCombo('Sand Model', app.cfg, 'sandModel', sandModelClassNames)

	if app.useAudio then
		self:centerText'Audio:'
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

	self:centerText'Controls:'
	self:centerLuatableTooltipSliderFloat('On-Screen Button Radius', app.cfg, 'screenButtonRadius', .001, 1)

	if self:centerButton'Done' then
		app:saveConfig()
		local MainMenuState = require 'sand-attack.menustate.main'
		app.menustate = MainMenuState(app)
	end
	self:endFullView()
end

return ConfigState
