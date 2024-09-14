bit = require("bit")
obs = obslua

local create_renderer = require('renderer').create_renderer
local utils = require('utils')

local M = {}

function M.create_source(whiteboard)
    local source = {}
    source.id = "whiteboard"
    source.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

    source.get_name = function()
        return "Whiteboard"
    end

    source.create = function()
        local source = {}
        
        source.active = false

        local video_info = obs.obs_video_info()
        if obs.obs_get_video_info(video_info) then
            source.width = video_info.base_width
            source.height = video_info.base_height

            source.renderer = create_renderer(source, whiteboard)
        else
            print "Failed to get video resolution"
        end

        return source
    end

    source.destroy = function(source)
        source.active = false
        source.renderer.destroy()
    end

    source.video_tick = function(source, dt)
        local video_info = obs.obs_video_info()

        local renderer = source.renderer

        -- Check to see if stream resoluiton resized and recreate texture if so
        if obs.obs_get_video_info(video_info) and (video_info.base_width ~= source.width or video_info.base_height ~= source.height) then
            source.width = video_info.base_width
            source.height = video_info.base_height

            renderer.enter_graphics(function(graphics)
                graphics.recreate_textures(source)
            end)
        end

        if not renderer.ready() then
            return
        end
        
        if not source.active then
            return
        end

        if whiteboard.needs_redraw then
            renderer.enter_graphics(function(graphics)
                graphics.render_to_texture(renderer.canvas_texture, function()
                    graphics.clear()

                    graphics.draw_lines(whiteboard.lines)

                    for _, line in ipairs(whiteboard.lines) do
                        if line.arrow and line.color ~= 0 and #(line.points) > 1 then
                            graphics.draw_arrow_head(line)
                        end
                    end
                end)
            end)

            whiteboard.needs_redraw = false
        end

        renderer.enter_graphics(function(graphics)
            graphics.render_to_texture(renderer.ui_texture, function()
                graphics.clear()
            end)
        end)

        local mouse_down = winapi.GetAsyncKeyState(winapi.VK_LBUTTON)
        local window = winapi.GetForegroundWindow()
        if mouse_down then
            if whiteboard.is_drawable_window(window) then
                whiteboard.target_window = window
            else
                whiteboard.target_window = nil
            end
        end

        if not whiteboard.drawing and window == whiteboard.target_window then
            whiteboard.update_color()
            whiteboard.update_size()
            whiteboard.update_mode()
            whiteboard.check_undo()
            whiteboard.check_clear()
        end

        renderer.enter_graphics(function(graphics)
            if mouse_down then
                if window and window == whiteboard.target_window then
                    local mouse_pos = whiteboard.get_mouse_pos(source, window)

                    local size = whiteboard.draw_size
                    if whiteboard.color_index == 0 then
                        size = whiteboard.eraser_size
                    end
                    
                    if whiteboard.drawing then
                        local effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)
                        if not effect then
                            return
                        end

                        local new_segment = {
                            color = whiteboard.color_index,
                            size = size,
                            arrow = whiteboard.arrow_mode,
                            points = {
                                { x = whiteboard.prev_mouse_pos.x, y = whiteboard.prev_mouse_pos.y },
                                { x = mouse_pos.x, y = mouse_pos.y }
                            }
                        }

                        local current_line = whiteboard.lines[#(whiteboard.lines)]

                        table.insert(
                            current_line.points,
                            { x = mouse_pos.x, y = mouse_pos.y }
                        )

                        graphics.render_to_texture(renderer.canvas_texture, function()
                            graphics.draw_lines({ new_segment })
                        end)

                        if whiteboard.arrow_mode then
                            graphics.render_to_texture(renderer.ui_texture, function()
                                graphics.draw_arrow_head(current_line)
                            end)
                        end
                    else
                        if whiteboard.valid_position(mouse_pos.x, mouse_pos.y, source.width, source.height) then
                            table.insert(whiteboard.lines, {
                                color = whiteboard.color_index,
                                size = size,
                                arrow = whiteboard.arrow_mode,
                                points = {{ x = mouse_pos.x, y = mouse_pos.y }}
                            })
                            whiteboard.drawing = true
                        end
                    end

                    whiteboard.prev_mouse_pos = mouse_pos
                end
            end

            if window and window == whiteboard.target_window then
                local mouse_pos = whiteboard.get_mouse_pos(source, window)
                if whiteboard.valid_position(mouse_pos.x, mouse_pos.y, source.width, source.height) then
                    graphics.render_to_texture(renderer.ui_texture, function()
                        graphics.draw_cursor(mouse_pos)
                    end)
                end
            end

            if not mouse_down then
                if whiteboard.prev_mouse_pos then
                    if #(whiteboard.lines) >= 1 and whiteboard.arrow_mode and whiteboard.color_index ~= 0 then
                        graphics.render_to_texture(renderer.canvas_texture, function()
                            graphics.draw_arrow_head(whiteboard.lines[#(whiteboard.lines)])
                        end)
                    end

                    whiteboard.prev_mouse_pos = nil
                    whiteboard.drawing = false
                end
            end
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
                obs.obs_source_draw(source.renderer.canvas_texture.render_target, 0, 0, 0, 0, false);
                obs.obs_source_draw(source.renderer.ui_texture.render_target, 0, 0, 0, 0, false);
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
        -- TODO: Feels like this should be in whiteboard?
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