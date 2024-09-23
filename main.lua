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
    return [==[Adds a whiteboard source type which can be used to draw annotations on your scene while recording.
    
Add a whiteboard source on top of your scene, then right click your scene and choose "Windowed Projector". You can then draw on that projector window.
    
The following keyboard shortcuts are available while the projector window is focused (these shortcuts cannot currently be modified):
- 1-9: select brush color
- 0: select eraser
- +/-: increase or decrease the size of your brush/eraser
- e: toggle between brush and eraser
- a: toggle brush to or from arrow mode
- backspace: undo previous change
- c: clear whiteboard (this cannot be undone)]==]
end

local whiteboard = create_whiteboard()
local source = create_source(whiteboard)
obs.obs_register_source(source)
