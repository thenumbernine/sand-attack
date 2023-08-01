# Sand Attack!

[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>
[![Donate via Bitcoin](https://img.shields.io/badge/Donate-Bitcoin-green.svg)](bitcoin:37fsp7qQKU8XoHZGRQvVzQVP8FrEJ73cSJ)<br>

# [Download](https://github.com/thenumbernine/sand-attack/releases/tag/1.0)

Connect Lines From Falling Blocks of Sand

[![sand attack](http://img.youtube.com/vi/L2Irjl3f8EY/0.jpg)](https://youtu.be/L2Irjl3f8EY)

# Dependencies:

other repos of mine:
- https://github.com/thenumbernine/lua-template
- https://github.com/thenumbernine/lua-ext
- https://github.com/thenumbernine/lua-ffi-bindings
- https://github.com/thenumbernine/vec-ffi-lua
- https://github.com/thenumbernine/lua-matrix
- https://github.com/thenumbernine/lua-image
- https://github.com/thenumbernine/lua-gl
- https://github.com/thenumbernine/lua-glapp
- https://github.com/thenumbernine/lua-imgui
- https://github.com/thenumbernine/lua-imguiapp
- https://github.com/thenumbernine/lua-audio

external libraries required:
- libpng
- SDL2
- cimgui w/ OpenGL+SDL backend (build process described in my lua-imgui readme)
- libogg
- libvorbis
- libvorbisfile
- OpenAL-Soft


# TODO:

- multiplayer-versus where you can drop sand on your opponent
	and a color that they have to clear-touching to reveal to other random colors
	like that other tris game ...
- varying board width for # of players
- gameplay option of increasing # colors
- I've got SPH stuff but it's behavior is still meh. with it: exploding pieces, tilting board, obstacles in the board, etc
- choose music? 
- faster blob detection
- submit high scores? meh.  in a game, record seed, record all players' keystates per frame, and allow replaying and submitting of gamestates.  cheat-proof and pro-TAS.
- better notification of score-modifier for chaining lines
- option for multipalyer-coop sharing next-pieces vs separate next-pieces
- imgui:
- - with gamepad navigation, tooltips only work with Slider.  with Input they only show after you select the text (which you can't type) or for a brief moment after pushing + or -.
- - centering stuff horizontally is painful at best.  then try adding more than one item on the same line ...
- - InputFloat can't be edited with gamepad navigation

# Music Credit:

```
Desert City Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 3.0 License
http://creativecommons.org/licenses/by/3.0/
Music promoted by https://www.chosic.com/free-music/all/

Exotic Plains by Darren Curtis | https://www.darrencurtismusic.com/
Music promoted by https://www.chosic.com/free-music/all/
Creative Commons CC BY 3.0
https://creativecommons.org/licenses/by/3.0/

Ibn Al-Noor Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 3.0 License
http://creativecommons.org/licenses/by/3.0/
Music promoted by https://www.chosic.com/free-music/all/

Market Day RandomMind
Music: https://www.chosic.com/free-music/all/

Return of the Mummy Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 3.0 License
http://creativecommons.org/licenses/by/3.0/
Music promoted by https://www.chosic.com/free-music/all/

Temple Of Endless Sands by Darren Curtis | https://www.darrencurtismusic.com/
Music promoted by https://www.chosic.com/free-music/all/
Creative Commons CC BY 3.0
https://creativecommons.org/licenses/by/3.0/

The Legend of Narmer by WombatNoisesAudio | https://soundcloud.com/user-734462061
Creative Commons Attribution 3.0 Unported License
https://creativecommons.org/licenses/by/3.0/
Music promoted by https://www.chosic.com/free-music/all/
```

# Font Credit:

```
https://www.1001freefonts.com/billow-twril.font
```
