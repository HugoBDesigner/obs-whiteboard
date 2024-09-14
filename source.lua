bit = require("bit")
obs = obslua

local create_renderer = require('renderer').create_renderer
local utils = require('utils')

local M = {}

function M.create_source(whiteboard)
    local source = {}
    source.id = "whiteboard"
    source.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

    function ensure_renderer_valid(source)
        local video_info = obs.obs_video_info()
        if not obs.obs_get_video_info(video_info) then
            print "Failed to get video resolution"
            return
        end

        if video_info.base_width == source.width and video_info.base_height == source.height then
            return
        end

        source.width = video_info.base_width
        source.height = video_info.base_height

        source.renderer = create_renderer(source, whiteboard)
    end

    function redraw_canvas(graphics, whiteboard)
        graphics.render_to_texture(graphics.canvas_texture, function()
            graphics.clear()

            graphics.draw_lines(whiteboard.lines)

            for _, line in ipairs(whiteboard.lines) do
                if line.arrow and line.color ~= 0 and #(line.points) > 1 then
                    graphics.draw_arrow_head(line)
                end
            end
        end)
    end

    function clear_ui(graphics)
        graphics.render_to_texture(graphics.ui_texture, function()
            graphics.clear()
        end)
    end

    source.get_name = function()
        return "Whiteboard"
    end

    source.create = function()
        local source = {}
        
        source.active = false
        ensure_renderer_valid(source)

        return source
    end

    source.destroy = function(source)
        source.active = false
        source.renderer.destroy()
    end

    source.video_tick = function(source, dt)
        local renderer = source.renderer

        ensure_renderer_valid(source)
        if not renderer.ready() then
            return
        end
        
        if not source.active then
            return
        end

        renderer.enter_graphics(function(graphics)
            if whiteboard.needs_redraw then
                redraw_canvas(graphics, whiteboard)
                whiteboard.needs_redraw = false
            end

            clear_ui(graphics)

            whiteboard.update(source, graphics)
        end)
    end

    source.video_render = function(source, effect)
        effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)

        if effect and source.renderer.ready() then
            obs.gs_blend_state_push()
            obs.gs_reset_blend_state()
            obs.gs_matrix_push()
            obs.gs_matrix_identity()

            obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_INVSRCALPHA)

            while obs.gs_effect_loop(effect, "Draw") do
                obs.obs_source_draw(source.renderer.graphics.canvas_texture.render_target, 0, 0, 0, 0, false);
                obs.obs_source_draw(source.renderer.graphics.ui_texture.render_target, 0, 0, 0, 0, false);
            end

            obs.gs_matrix_pop()
            obs.gs_blend_state_pop()
        end
    end

    source.get_width = function(source)
        return 0
    end

    source.get_height = function(source)
        return 0
    end

    source.activate = function(source)
        local scene = obs.obs_frontend_get_current_scene()
        whiteboard.scene_name = obs.obs_source_get_name(scene)
        source.active = true
        obs.obs_source_release(scene)
    end

    source.deactivate = function(source)
        source.active = false
    end

    return source
end

return M