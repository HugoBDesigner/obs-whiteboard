local create_whiteboard = require('whiteboard').create_whiteboard
local create_source = require('source').create_source

function script_load(settings)
end

function script_update(settings)
end

function script_save(settings)
end

function script_properties()
    return obs.obs_properties_create()
end

function script_defaults(settings)
end

function script_description()
    -- Using [==[ and ]==] as string delimiters, purely for IDE syntax parsing reasons.
    return [==[Adds a whiteboard.
    
Add this source on top of your scene, then project your entire scene and draw on the projector window. Each scene can have one whiteboard.
    
Hotkeys can be set to toggle color, draw_size, and eraser. An additional hotkey can be set to wipe the canvas.]==]
end

local whiteboard = create_whiteboard()
local source = create_source(whiteboard)
obs.obs_register_source(source)
