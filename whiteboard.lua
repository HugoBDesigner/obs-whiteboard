-- OBS Whiteboard Script
-- Authors: Mike Welsh (mwelsh@gmail.com), Tari, Joseph Mansfield
-- v1.3

obs = obslua

winapi = require("winapi")
require("winapi.cursor")
require("winapi.keyboard")
require("winapi.window")
require("winapi.winbase")

utils = require('utils')

local M = {}

function M.create_whiteboard()
    local whiteboard = {}

    whiteboard.needs_redraw = false
    whiteboard.swap_color = false
    whiteboard.toggle_size = false
    whiteboard.scene_name = nil

    whiteboard.eraser_v4 = obs.vec4()
    whiteboard.color_index = 1
    --Color format is 0xABGR
    whiteboard.color_array = {0xff4d4de8, 0xff4d9de8, 0xff4de5e8, 0xff4de88e, 0xff95e84d, 0xffe8d34d, 0xffe8574d, 0xffe84d9d, 0xffbc4de8}
    whiteboard.draw_size = 6
    whiteboard.eraser_size = 18
    whiteboard.size_max = 12  -- size_max must be a minimum of 2.

    whiteboard.eraser_vert = obs.gs_vertbuffer_t
    whiteboard.dot_vert = obs.gs_vertbuffer_t
    whiteboard.line_vert = obs.gs_vertbuffer_t
    whiteboard.arrow_cursor_vert = obs.gs_vertbuffer_t

    whiteboard.drawing = false
    whiteboard.arrow_mode = false
    whiteboard.lines = {}

    whiteboard.target_window = nil

    whiteboard.plus_pressed = false
    whiteboard.minus_pressed = false
    whiteboard.a_pressed = false
    whiteboard.backspace_pressed = false
    whiteboard.c_pressed = false

    whiteboard.update_color = function()
        for i=0,#(whiteboard.color_array) do
            local key_down = winapi.GetAsyncKeyState(0x30 + i)
            if key_down then
                whiteboard.color_index = i
            end
        end

        local key_down = winapi.GetAsyncKeyState(0x45)
        if key_down then
            whiteboard.color_index = 0
        end
    end

    whiteboard.update_size = function ()
        local plus_down = winapi.GetAsyncKeyState(winapi.VK_OEM_PLUS)
        if plus_down then
            if not whiteboard.plus_pressed and whiteboard.draw_size < 100 then
                if whiteboard.color_index == 0 then
                    whiteboard.eraser_size = whiteboard.eraser_size + 4
                else
                    whiteboard.draw_size = whiteboard.draw_size + 4
                end
                whiteboard.plus_pressed = true
            end
        else
            whiteboard.plus_pressed = false
        end

        local minus_down = winapi.GetAsyncKeyState(winapi.VK_OEM_MINUS)
        if minus_down then
            if not whiteboard.minus_pressed and whiteboard.draw_size > 3 then
                if color_index == 0 then
                    whiteboard.eraser_size = whiteboard.eraser_size - 4
                else
                    whiteboard.draw_size = whiteboard.draw_size - 4
                end
                whiteboard.minus_pressed = true
            end
        else
            whiteboard.minus_pressed = false
        end
    end

    whiteboard.update_mode = function ()
        local key_down = winapi.GetAsyncKeyState(0x41)
        if key_down then
            if not whiteboard.a_pressed then
                whiteboard.arrow_mode = not whiteboard.arrow_mode
                whiteboard.a_pressed = true
            end
        else
            whiteboard.a_pressed = false
        end
    end

    whiteboard.is_drawable_window = function (window)
        local window_name = winapi.InternalGetWindowText(window, nil)
        if not window_name then
            return false
        end

        return whiteboard.window_match(window_name) and
            (string.find(window_name, "Windowed Projector", 1, true) or
            string.find(window_name, "Fullscreen Projector", 1, true))
    end

    whiteboard.get_mouse_pos = function (data, window)
        local mouse_pos = winapi.GetCursorPos()
        winapi.ScreenToClient(window, mouse_pos)

        local window_rect = winapi.GetClientRect(window)
        
        local output_aspect = data.width / data.height

        local window_width = window_rect.right - window_rect.left
        local window_height = window_rect.bottom - window_rect.top
        local window_aspect = window_width / window_height
        local offset_x = 0
        local offset_y = 0
        if window_aspect >= output_aspect then
            offset_x = (window_width - window_height * output_aspect) / 2
        else
            offset_y = (window_height - window_width / output_aspect) / 2
        end

        mouse_pos.x = data.width * (mouse_pos.x - offset_x) / (window_width - offset_x*2)
        mouse_pos.y = data.height * (mouse_pos.y - offset_y) / (window_height - offset_y*2)

        return mouse_pos
    end

    whiteboard.draw_lines = function (data, lines_to_draw, is_redraw)
        obs.obs_enter_graphics()

        local prev_render_target = obs.gs_get_render_target()
        local prev_zstencil_target = obs.gs_get_zstencil_target()

        obs.gs_set_render_target(data.canvas_texture, nil)
        obs.gs_viewport_push()
        obs.gs_set_viewport(0, 0, data.width, data.height)
        obs.gs_projection_push()
        obs.gs_ortho(0, data.width, 0, data.height, 0.0, 1.0)

        for _, line in ipairs(lines_to_draw) do
            if #(line.points) > 1 then
                obs.gs_blend_state_push()
                obs.gs_reset_blend_state()
                
                -- Set the color being used (or set the eraser).
                local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
                local color = obs.gs_effect_get_param_by_name(solid, "color")
                local tech  = obs.gs_effect_get_technique(solid, "Solid")

                if line.color == 0 then
                    obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
                    obs.gs_effect_set_vec4(color, whiteboard.eraser_v4)
                else
                    local color_v4 = obs.vec4()
                    obs.vec4_from_rgba(color_v4, whiteboard.color_array[line.color])
                    obs.gs_effect_set_vec4(color, color_v4)
                end

                obs.gs_technique_begin(tech)
                obs.gs_technique_begin_pass(tech, 0)

                for i=1, (#(line.points) - 1) do
                    local start_pos = line.points[i]
                    local end_pos = line.points[i+1]

                    -- Calculate distance mouse has traveled since our
                    -- last update.
                    local dx = end_pos.x - start_pos.x
                    local dy = end_pos.y - start_pos.y
                    local len = math.sqrt(dx*dx + dy*dy)
                    local angle = math.atan2(dy, dx)
                    
                    -- Perform matrix transformations for the dot at the
                    -- start of the line (start cap).
                    obs.gs_matrix_push()
                    obs.gs_matrix_identity()
                    obs.gs_matrix_translate3f(start_pos.x, start_pos.y, 0)

                    obs.gs_matrix_push()
                    obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                    
                    -- Draw start of line.
                    obs.gs_load_vertexbuffer(whiteboard.dot_vert)
                    obs.gs_draw(obs.GS_TRIS, 0, 0)

                    obs.gs_matrix_pop()

                    -- Perform matrix transformations for the actual line.
                    obs.gs_matrix_rotaa4f(0, 0, 1, angle)
                    obs.gs_matrix_translate3f(0, -line.size, 0)
                    obs.gs_matrix_scale3f(len, line.size, 1.0)

                    -- Draw actual line.
                    obs.gs_load_vertexbuffer(whiteboard.line_vert)
                    obs.gs_draw(obs.GS_TRIS, 0, 0)

                    -- Perform matrix transforms for the dot at the end
                    -- of the line (end cap).
                    obs.gs_matrix_identity()
                    obs.gs_matrix_translate3f(end_pos.x, end_pos.y, 0)
                    obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                    obs.gs_load_vertexbuffer(whiteboard.dot_vert)
                    obs.gs_draw(obs.GS_TRIS, 0, 0)

                    obs.gs_matrix_pop()
                end

                -- Done drawing line, restore everything.
                obs.gs_technique_end_pass(tech)
                obs.gs_technique_end(tech)

                obs.gs_blend_state_pop()
            end
        end

        obs.gs_projection_pop()
        obs.gs_viewport_pop()
        obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

        obs.obs_leave_graphics()

        if is_redraw then
            for _, line in ipairs(lines_to_draw) do
                if line.arrow and line.color ~= 0 and #(line.points) > 1 then
                    whiteboard.draw_arrow_head(data, data.canvas_texture, line)
                end
            end
        else
            if whiteboard.arrow_mode then
                whiteboard.draw_arrow_head(data, data.ui_texture, whiteboard.lines[#(whiteboard.lines)])
            end
        end
    end

    whiteboard.draw_arrow_head = function (data, texture, line)
        if #(line.points) < 2 then
            return
        end

        obs.obs_enter_graphics()

        local prev_render_target = obs.gs_get_render_target()
        local prev_zstencil_target = obs.gs_get_zstencil_target()

        obs.gs_set_render_target(texture, nil)
        obs.gs_viewport_push()
        obs.gs_set_viewport(0, 0, data.width, data.height)
        obs.gs_projection_push()
        obs.gs_ortho(0, data.width, 0, data.height, 0.0, 1.0)

        obs.gs_blend_state_push()
        obs.gs_reset_blend_state()
        
        -- Set the color being used (or set the eraser).
        local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
        local color = obs.gs_effect_get_param_by_name(solid, "color")
        local tech  = obs.gs_effect_get_technique(solid, "Solid")

        if line.color == 0 then
            obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
            obs.gs_effect_set_vec4(color, whiteboard.eraser_v4)
        else
            local color_v4 = obs.vec4()
            obs.vec4_from_rgba(color_v4, whiteboard.color_array[line.color])
            obs.gs_effect_set_vec4(color, color_v4)
        end

        local arrow_head_angle = math.pi / 4

        local start_pos = line.points[#(line.points)]

        local prev_pos = nil
        local i = #(line.points) - 1
        while i >= 1 do
            prev_pos = line.points[i]
            local dx = start_pos.x - prev_pos.x
            local dy = start_pos.y - prev_pos.y
            if (dx*dx + dy*dy) >= (line.size * line.size * line.size) then
                break
            end
            i = i - 1
        end

        if prev_pos ~= nil and i ~= 0 then
            obs.gs_technique_begin(tech)
            obs.gs_technique_begin_pass(tech, 0)

            local dx = start_pos.x - prev_pos.x
            local dy = start_pos.y - prev_pos.y
            local prev_segment_angle = math.atan2(dy, dx)

            local len = 6 * line.size

            local directions = {-1, 1}
            for i=1,2 do
                local direction = directions[i]

                -- Calculate distance mouse has traveled since our
                -- last update.
                local angle = direction * (math.pi - arrow_head_angle) + prev_segment_angle

                local arm_end_x = start_pos.x + (len * math.cos(angle))
                local arm_end_y = start_pos.y + (len * math.sin(angle))
                
                -- Perform matrix transformations for the dot at the
                -- start of the line (start cap).
                obs.gs_matrix_push()
                obs.gs_matrix_identity()
                obs.gs_matrix_translate3f(start_pos.x, start_pos.y, 0)

                -- Perform matrix transformations for the actual line.
                obs.gs_matrix_rotaa4f(0, 0, 1, angle)
                obs.gs_matrix_translate3f(0, -line.size, 0)
                obs.gs_matrix_scale3f(len, line.size, 1.0)

                -- Draw actual line.
                obs.gs_load_vertexbuffer(whiteboard.line_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                -- Perform matrix transforms for the dot at the end
                -- of the line (end cap).
                obs.gs_matrix_identity()
                obs.gs_matrix_translate3f(arm_end_x, arm_end_y, 0)
                obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                obs.gs_load_vertexbuffer(whiteboard.dot_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                obs.gs_matrix_pop()
            end

            obs.gs_technique_end_pass(tech)
            obs.gs_technique_end(tech)
        end

        -- Done drawing line, restore everything.

        obs.gs_blend_state_pop()

        obs.gs_projection_pop()
        obs.gs_viewport_pop()
        obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

        obs.obs_leave_graphics()
    end

    whiteboard.draw_cursor = function (data, mouse_pos)
        obs.obs_enter_graphics()

        local prev_render_target = obs.gs_get_render_target()
        local prev_zstencil_target = obs.gs_get_zstencil_target()

        obs.gs_set_render_target(data.ui_texture, nil)
        obs.gs_viewport_push()
        obs.gs_set_viewport(0, 0, data.width, data.height)
        obs.gs_projection_push()
        obs.gs_ortho(0, data.width, 0, data.height, 0.0, 1.0)

        obs.gs_blend_state_push()
        obs.gs_reset_blend_state()
        
        -- Set the color being used (or set the eraser).
        local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
        local color = obs.gs_effect_get_param_by_name(solid, "color")
        local tech  = obs.gs_effect_get_technique(solid, "Solid")

        local size = whiteboard.draw_size
        local color_v4 = obs.vec4()

        if whiteboard.color_index == 0 then
            obs.vec4_from_rgba(color_v4, 0xff000000)
            obs.gs_effect_set_vec4(color, color_v4)
            size = whiteboard.eraser_size
        else
            obs.vec4_from_rgba(color_v4, whiteboard.color_array[whiteboard.color_index])
            obs.gs_effect_set_vec4(color, color_v4)
        end

        obs.gs_technique_begin(tech)
        obs.gs_technique_begin_pass(tech, 0)

        -- Perform matrix transformations for the dot at the
        -- start of the line (start cap).
        obs.gs_matrix_push()
        obs.gs_matrix_identity()
        obs.gs_matrix_translate3f(mouse_pos.x, mouse_pos.y, 0)

        obs.gs_matrix_push()
        obs.gs_matrix_scale3f(size, size, 1.0)
        
        -- Draw cursor
        if whiteboard.color_index == 0 then
            obs.gs_load_vertexbuffer(whiteboard.eraser_vert)
            obs.gs_draw(obs.GS_LINESTRIP, 0, 0)
        else
            obs.gs_load_vertexbuffer(whiteboard.dot_vert)
            obs.gs_draw(obs.GS_TRIS, 0, 0)

            if whiteboard.arrow_mode then
                obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
                obs.gs_effect_set_vec4(color, whiteboard.eraser_v4)
                obs.gs_load_vertexbuffer(whiteboard.arrow_cursor_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)
            end
        end

        obs.gs_matrix_pop()
        obs.gs_matrix_pop()

        -- Done drawing line, restore everything.
        obs.gs_technique_end_pass(tech)
        obs.gs_technique_end(tech)

        obs.gs_blend_state_pop()

        obs.gs_projection_pop()
        obs.gs_viewport_pop()
        obs.gs_set_render_target(prev_render_target, prev_zstencil_target)

        obs.obs_leave_graphics()
    end

    -- Check whether current foreground window is relevant to us.
    whiteboard.window_match = function (window_name)
        local valid_names = {}
        
        -- If studio mode is enabled, only allow drawing on main
        -- window (Program). If non-studio mode, allow drawing on
        -- the (Preview) window, instead.
        if obs.obs_frontend_preview_program_mode_active() then
            table.insert(valid_names, "(Program)")
        else
            table.insert(valid_names, "(Preview)")
        end
        
        -- Always allow drawing on projection of the scene containing
        -- the active whiteboard.
        if whiteboard.scene_name then
            table.insert(valid_names, whiteboard.scene_name)
        end

        -- Check that the currently selected projector matches one
        -- of the ones listed above.
        for name_index = 1, #valid_names do
            local valid_name = valid_names[name_index]
            local window_name_suffix = string.sub(window_name, -string.len(valid_name) - 1)
            if window_name_suffix == (" " .. valid_name) then
                return true
            end
        end

        return false
    end

    whiteboard.update_vertices = function ()
        obs.obs_enter_graphics()
        
        -- LINE VERTICES
        -- Create vertices for line of given width (user-defined 'draw_size').
        -- These vertices are for two triangles that make up each line.
        if whiteboard.line_vert then
            obs.gs_vertexbuffer_destroy(whiteboard.line_vert)
        end

        obs.gs_render_start(true)
        obs.gs_vertex2f(0, 0)
        obs.gs_vertex2f(1, 0)
        obs.gs_vertex2f(0, 2)
        obs.gs_vertex2f(0, 2)
        obs.gs_vertex2f(1, 2)
        obs.gs_vertex2f(1, 0)
        
        whiteboard.line_vert = obs.gs_render_save()
        
        -- DOT VERTICES
        -- Create vertices for a dot (filled circle) of specified width,
        -- which is used to round off the ends of the lines.
        if whiteboard.dot_vert then
            obs.gs_vertexbuffer_destroy(whiteboard.dot_vert)
        end
        
        obs.gs_render_start(true)

        local sectors = 100
        local angle_delta = (2 * math.pi) / sectors

        local circum_points = {}
        for i=0,(sectors-1) do
            table.insert(circum_points, {
                math.sin(angle_delta * i),
                math.cos(angle_delta * i)
            })
        end

        for i=0,(sectors-1) do
            local point_a = circum_points[i + 1]
            local point_b = circum_points[((i + 1) % sectors) + 1]
            obs.gs_vertex2f(0, 0)
            obs.gs_vertex2f(point_a[1], point_a[2])
            obs.gs_vertex2f(point_b[1], point_b[2])
        end

        whiteboard.dot_vert = obs.gs_render_save()

        -- ERASER CURSOR VERTICES
        -- Create vertices for a circle outline
        -- which is shown as the cursor when using the eraser

        if whiteboard.eraser_vert then
            obs.gs_vertexbuffer_destroy(whiteboard.eraser_vert)
        end
        
        obs.gs_render_start(true)

        for i=0,sectors do
            obs.gs_vertex2f(
                math.sin(angle_delta * i),
                math.cos(angle_delta * i)
            )
        end

        whiteboard.eraser_vert = obs.gs_render_save()

        -- ARROW CURSOR VERTICES
        -- Create vertices for a triangle cursor
        -- which is shown as the cursor when in arrow mode

        if whiteboard.arrow_cursor_vert then
            obs.gs_vertexbuffer_destroy(whiteboard.arrow_cursor_vert)
        end
        
        obs.gs_render_start(true)

        local angle_delta = (2 * math.pi) / 3
        for i=0,3 do
            obs.gs_vertex2f(
                math.sin(angle_delta * (i + 0.5)) * 0.75,
                math.cos(angle_delta * (i + 0.5)) * 0.75
            )
        end

        whiteboard.arrow_cursor_vert = obs.gs_render_save()
        
        obs.obs_leave_graphics()
    end

    whiteboard.valid_position = function (cur_x, cur_y, width, height)
        -- If the mouse is within the boundaries of the screen, or was
        -- previously within the boundaries of the screen, it is a valid
        -- position to draw a line to.
        if (cur_x >= 0 and cur_x < width and cur_y >= 0 and cur_y < height) then
            return true
        end    
        return false
    end

    whiteboard.check_clear = function ()
        local key_down = winapi.GetAsyncKeyState(0x43)
        if key_down then
            if not whiteboard.c_pressed then
                utils.clear_table(whiteboard.lines)
                whiteboard.needs_redraw = true
                whiteboard.c_pressed = true
            end
        else
            whiteboard.c_pressed = false
        end
    end

    whiteboard.check_undo = function ()
        local key_down = winapi.GetAsyncKeyState(0x08)
        if key_down then
            if not whiteboard.backspace_pressed then
                if #(whiteboard.lines) > 0 then
                    table.remove(whiteboard.lines, #(whiteboard.lines))
                end

                whiteboard.needs_redraw = true
                whiteboard.backspace_pressed = true
            end
        else
            whiteboard.backspace_pressed = false
        end
    end

    -- whiteboard.image_source_load(image, file)
    --     obs.obs_enter_graphics()
    --     obs.gs_image_file_free(image);
    --     obs.obs_leave_graphics()

    --     obs.gs_image_file_init(image, file);

    --     obs.obs_enter_graphics()
    --     obs.gs_image_file_init_texture(image);
    --     obs.obs_leave_graphics()

    --     if not image.loaded then
    --         print("failed to load texture " .. file);
    --     end
    -- end

    whiteboard.create_textures = function (data)
        obs.obs_enter_graphics()
        
        if data.canvas_texture ~= nil then
            obs.gs_texture_destroy(data.canvas_texture)
        end

        data.canvas_texture = obs.gs_texture_create(data.width, data.height, obs.GS_RGBA, 1, nil, obs.GS_RENDER_TARGET)
        print("create canvas texture " .. data.width .. " " .. data.height)
        
        if data.ui_texture ~= nil then
            obs.gs_texture_destroy(data.ui_texture)
        end

        data.ui_texture = obs.gs_texture_create(data.width, data.height, obs.GS_RGBA, 1, nil, obs.GS_RENDER_TARGET)
        print("create ui texture " .. data.width .. " " .. data.height)

        obs.obs_leave_graphics()
    end

    return whiteboard
end

return M