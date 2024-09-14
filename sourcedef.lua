bit = require("bit")
obs = obslua

local M = {}

function M.create_source_def(whiteboard)
    local source_def = {}
    source_def.id = "whiteboard"
    source_def.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO, obs.OBS_SOURCE_CUSTOM_DRAW)

    source_def.get_name = function()
        return "Whiteboard"
    end

    source_def.create = function(source, settings)
        local data = {}
        
        data.active = false
        
        obs.vec4_from_rgba(whiteboard.eraser_v4, 0x00000000)
        
        data.prev_mouse_pos = nil
        
        -- Create the vertices needed to draw our lines.
        whiteboard.update_vertices()

        local video_info = obs.obs_video_info()
        if obs.obs_get_video_info(video_info) then
            data.width = video_info.base_width
            data.height = video_info.base_height

            whiteboard.create_textures(data)
        else
            print "Failed to get video resolution"
        end

        return data
    end

    source_def.destroy = function(data)
        data.active = false
        obs.obs_enter_graphics()
        obs.gs_texture_destroy(data.canvas_texture)
        obs.gs_texture_destroy(data.ui_texture)
        obs.obs_leave_graphics()
    end

    source_def.video_tick = function(data, dt)
        local video_info = obs.obs_video_info()

        -- Check to see if stream resoluiton resized and recreate texture if so
        -- TODO: Is there a signal that does this?
        if obs.obs_get_video_info(video_info) and (video_info.base_width ~= data.width or video_info.base_height ~= data.height) then
            data.width = video_info.base_width
            data.height = video_info.base_height
            whiteboard.create_textures(data)
        end

        if data.canvas_texture == nil or data.ui_texture == nil then
            return
        end
        
        if not data.active then
            return
        end

        if whiteboard.needs_redraw then
            local prev_render_target = obs.gs_get_render_target()
            local prev_zstencil_target = obs.gs_get_zstencil_target()

            obs.gs_viewport_push()
            obs.gs_set_viewport(0, 0, data.width, data.height)

            obs.obs_enter_graphics()
            obs.gs_set_render_target(data.canvas_texture, nil)
            obs.gs_clear(obs.GS_CLEAR_COLOR, obs.vec4(), 1.0, 0)

            whiteboard.draw_lines(data, whiteboard.lines, true)

            obs.gs_viewport_pop()
            obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

            obs.obs_leave_graphics()

            whiteboard.needs_redraw = false
        end

        local prev_render_target = obs.gs_get_render_target()
        local prev_zstencil_target = obs.gs_get_zstencil_target()

        obs.gs_viewport_push()
        obs.gs_set_viewport(0, 0, data.width, data.height)

        obs.obs_enter_graphics()
        obs.gs_set_render_target(data.ui_texture, nil)
        obs.gs_clear(obs.GS_CLEAR_COLOR, obs.vec4(), 1.0, 0)

        obs.gs_viewport_pop()
        obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

        obs.obs_leave_graphics()

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

        if mouse_down then
            if window and window == whiteboard.target_window then
                local mouse_pos = whiteboard.get_mouse_pos(data, window)

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
                            { x = data.prev_mouse_pos.x, y = data.prev_mouse_pos.y },
                            { x = mouse_pos.x, y = mouse_pos.y }
                        }
                    }
                    table.insert(
                        whiteboard.lines[#(whiteboard.lines)].points,
                        { x = mouse_pos.x, y = mouse_pos.y }
                    )
                    whiteboard.draw_lines(data, { new_segment }, false)
                else
                    if whiteboard.valid_position(mouse_pos.x, mouse_pos.y, data.width, data.height) then
                        table.insert(whiteboard.lines, {
                            color = whiteboard.color_index,
                            size = size,
                            arrow = whiteboard.arrow_mode,
                            points = {{ x = mouse_pos.x, y = mouse_pos.y }}
                        })
                        whiteboard.drawing = true
                    end
                end

                data.prev_mouse_pos = mouse_pos
            end
        end

        if window and window == whiteboard.target_window then
            local mouse_pos = whiteboard.get_mouse_pos(data, window)
            if whiteboard.valid_position(mouse_pos.x, mouse_pos.y, data.width, data.height) then
                whiteboard.draw_cursor(data, mouse_pos)
            end
        end

        if not mouse_down then
            if data.prev_mouse_pos then
                if #(whiteboard.lines) >= 1 and whiteboard.arrow_mode and whiteboard.color_index ~= 0 then
                    whiteboard.draw_arrow_head(data, data.canvas_texture, whiteboard.lines[#(whiteboard.lines)])
                end

                data.prev_mouse_pos = nil
                whiteboard.drawing = false
            end
        end
    end

    -- Render our output to the screen.
    source_def.video_render = function(data, effect)
        effect = obs.obs_get_base_effect(obs.OBS_EFFECT_DEFAULT)

        if effect and data.canvas_texture and data.ui_texture then
            obs.gs_blend_state_push()
            obs.gs_reset_blend_state()
            obs.gs_matrix_push()
            obs.gs_matrix_identity()

            obs.gs_blend_function(obs.GS_BLEND_ONE, obs.GS_BLEND_INVSRCALPHA)

            while obs.gs_effect_loop(effect, "Draw") do
                obs.obs_source_draw(data.canvas_texture, 0, 0, 0, 0, false);
                obs.obs_source_draw(data.ui_texture, 0, 0, 0, 0, false);
            end

            obs.gs_matrix_pop()
            obs.gs_blend_state_pop()
        end
    end

    source_def.get_width = function(data)
        return 0
    end

    source_def.get_height = function(data)
        return 0
    end

    -- When source is active, get the currently displayed scene's name and
    -- set the active flag to true.
    source_def.activate = function(data)
        local scene = obs.obs_frontend_get_current_scene()
        whiteboard.scene_name = obs.obs_source_get_name(scene)
        data.active = true
        obs.obs_source_release(scene)
    end

    source_def.deactivate = function(data)
        data.active = false
    end

    return source_def
end

return M