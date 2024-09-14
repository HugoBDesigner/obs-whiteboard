local M = {}

function M.create_renderer(source_data, whiteboard)
    local renderer = {}

    local graphics = {}

    graphics.canvas_texture = nil
    graphics.ui_texture = nil

    graphics.eraser_vert = obs.gs_vertbuffer_t
    graphics.dot_vert = obs.gs_vertbuffer_t
    graphics.line_vert = obs.gs_vertbuffer_t
    graphics.arrow_cursor_vert = obs.gs_vertbuffer_t

    graphics.eraser_v4 = obs.vec4()

    graphics.draw_lines = function(lines)
        for _, line in ipairs(lines) do
            if #(line.points) > 1 then
                obs.gs_blend_state_push()
                obs.gs_reset_blend_state()
                
                -- Set the color being used (or set the eraser).
                local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
                local color = obs.gs_effect_get_param_by_name(solid, "color")
                local tech  = obs.gs_effect_get_technique(solid, "Solid")

                if line.color == 0 then
                    obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
                    obs.gs_effect_set_vec4(color, graphics.eraser_v4)
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
                    obs.gs_load_vertexbuffer(graphics.dot_vert)
                    obs.gs_draw(obs.GS_TRIS, 0, 0)

                    obs.gs_matrix_pop()

                    -- Perform matrix transformations for the actual line.
                    obs.gs_matrix_rotaa4f(0, 0, 1, angle)
                    obs.gs_matrix_translate3f(0, -line.size, 0)
                    obs.gs_matrix_scale3f(len, line.size, 1.0)

                    -- Draw actual line.
                    obs.gs_load_vertexbuffer(graphics.line_vert)
                    obs.gs_draw(obs.GS_TRIS, 0, 0)

                    -- Perform matrix transforms for the dot at the end
                    -- of the line (end cap).
                    obs.gs_matrix_identity()
                    obs.gs_matrix_translate3f(end_pos.x, end_pos.y, 0)
                    obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                    obs.gs_load_vertexbuffer(graphics.dot_vert)
                    obs.gs_draw(obs.GS_TRIS, 0, 0)

                    obs.gs_matrix_pop()
                end

                -- Done drawing line, restore everything.
                obs.gs_technique_end_pass(tech)
                obs.gs_technique_end(tech)

                obs.gs_blend_state_pop()
            end
        end
    end

    graphics.draw_arrow_head = function(line)
        if #(line.points) < 2 then
            return
        end

        obs.gs_blend_state_push()
        obs.gs_reset_blend_state()
        
        -- Set the color being used (or set the eraser).
        local solid = obs.obs_get_base_effect(obs.OBS_EFFECT_SOLID)
        local color = obs.gs_effect_get_param_by_name(solid, "color")
        local tech  = obs.gs_effect_get_technique(solid, "Solid")

        if line.color == 0 then
            obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
            obs.gs_effect_set_vec4(color, graphics.eraser_v4)
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
                obs.gs_load_vertexbuffer(graphics.line_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                -- Perform matrix transforms for the dot at the end
                -- of the line (end cap).
                obs.gs_matrix_identity()
                obs.gs_matrix_translate3f(arm_end_x, arm_end_y, 0)
                obs.gs_matrix_scale3f(line.size, line.size, 1.0)
                obs.gs_load_vertexbuffer(graphics.dot_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)

                obs.gs_matrix_pop()
            end

            obs.gs_technique_end_pass(tech)
            obs.gs_technique_end(tech)
        end

        -- Done drawing line, restore everything.

        obs.gs_blend_state_pop()
    end

    graphics.draw_cursor = function(mouse_pos)
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
            obs.gs_load_vertexbuffer(graphics.eraser_vert)
            obs.gs_draw(obs.GS_LINESTRIP, 0, 0)
        else
            obs.gs_load_vertexbuffer(graphics.dot_vert)
            obs.gs_draw(obs.GS_TRIS, 0, 0)

            if whiteboard.arrow_mode then
                obs.gs_blend_function(obs.GS_BLEND_SRCALPHA, obs.GS_BLEND_SRCALPHA)
                obs.gs_effect_set_vec4(color, graphics.eraser_v4)
                obs.gs_load_vertexbuffer(graphics.arrow_cursor_vert)
                obs.gs_draw(obs.GS_TRIS, 0, 0)
            end
        end

        obs.gs_matrix_pop()
        obs.gs_matrix_pop()

        -- Done drawing line, restore everything.
        obs.gs_technique_end_pass(tech)
        obs.gs_technique_end(tech)

        obs.gs_blend_state_pop()
    end

    graphics.recreate_textures = function(source_data)
        if graphics.canvas_texture ~= nil then
            obs.gs_texture_destroy(graphics.canvas_texture.render_target)
        end

        graphics.canvas_texture = {
            width = source_data.width,
            height = source_data.height,
            render_target = obs.gs_texture_create(source_data.width, source_data.height, obs.GS_RGBA, 1, nil, obs.GS_RENDER_TARGET)
        }
        
        if graphics.ui_texture ~= nil then
            obs.gs_texture_destroy(graphics.ui_texture.render_target)
        end

        graphics.ui_texture = {
            width = source_data.width,
            height = source_data.height,
            render_target = obs.gs_texture_create(source_data.width, source_data.height, obs.GS_RGBA, 1, nil, obs.GS_RENDER_TARGET)
        }
    end

    graphics.clear = function()
        obs.gs_clear(obs.GS_CLEAR_COLOR, obs.vec4(), 1.0, 0)
    end

    graphics.render_to_texture = function(texture, callback)
        local prev_render_target = obs.gs_get_render_target()
        local prev_zstencil_target = obs.gs_get_zstencil_target()

        obs.gs_viewport_push()
        obs.gs_set_viewport(0, 0, texture.width, texture.height)

        obs.gs_set_render_target(texture.render_target, nil)

        obs.gs_projection_push()
        obs.gs_ortho(0, texture.width, 0, texture.height, 0.0, 1.0)

        callback(texture)

        obs.gs_projection_pop()

        obs.gs_viewport_pop()
        obs.gs_set_render_target(prev_render_target, prev_zstencil_target)
    end

    renderer.graphics = graphics

    renderer.enter_graphics = function(callback)
        obs.obs_enter_graphics()
        callback(graphics)
        obs.obs_leave_graphics()
    end

    renderer.destroy = function()
        renderer.enter_graphics(function(graphics)
            obs.gs_texture_destroy(graphics.canvas_texture.render_target)
            graphics.canvas_texture = nil
            obs.gs_texture_destroy(graphics.ui_texture.render_target)
            graphics.ui_texture = nil
        end)
    end

    renderer.ready = function()
        return graphics.canvas_texture ~= nil and graphics.ui_texture ~= nil
    end

    obs.vec4_from_rgba(graphics.eraser_v4, 0x00000000)

    renderer.enter_graphics(function(graphics)
        graphics.line_vert = create_line_vertex_buffer()
        graphics.dot_vert = create_dot_vertex_buffer()
        graphics.eraser_vert = create_eraser_vertex_buffer()
        graphics.arrow_cursor_vert = create_arrow_cursor_vertex_buffer()

        graphics.recreate_textures(source_data)
    end)

    return renderer
end

function create_line_vertex_buffer()
    obs.gs_render_start(true)

    obs.gs_vertex2f(0, 0)
    obs.gs_vertex2f(1, 0)
    obs.gs_vertex2f(0, 2)
    obs.gs_vertex2f(0, 2)
    obs.gs_vertex2f(1, 2)
    obs.gs_vertex2f(1, 0)
    
    return obs.gs_render_save()
end

function create_dot_vertex_buffer()
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

    return obs.gs_render_save()
end

function create_eraser_vertex_buffer()
    obs.gs_render_start(true)

    local sectors = 100
    local angle_delta = (2 * math.pi) / sectors

    for i=0,sectors do
        obs.gs_vertex2f(
            math.sin(angle_delta * i),
            math.cos(angle_delta * i)
        )
    end

    return obs.gs_render_save()
end

function create_arrow_cursor_vertex_buffer()
    obs.gs_render_start(true)

    local angle_delta = (2 * math.pi) / 3
    for i=0,3 do
        obs.gs_vertex2f(
            math.sin(angle_delta * (i + 0.5)) * 0.75,
            math.cos(angle_delta * (i + 0.5)) * 0.75
        )
    end

    return obs.gs_render_save()
end

return M