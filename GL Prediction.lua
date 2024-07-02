local horizontal_aiming = true -- For horizontal helper
local debug_prediction = false -- Debug, keep disabled
local GL_MAX_DISTANCE = 148
local GRAVITY = 9.81

local function atan2(y, x)
    if (x == 0) then
        if (y > 0) then return math.pi / 2
        elseif (y < 0) then return -math.pi / 2
        else return 0 end
    end
    local angle = math.atan(y / x)
    if (x < 0) then angle = angle + math.pi
    elseif (y < 0 and x > 0) then angle = angle + 2 * math.pi end
    return angle
end

function magnitude(vector)
    return math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
end

function normalize(vector)
    local mag = magnitude(vector)
    if mag == 0 then
        -- If the magnitude is 0, return the original vector to avoid division by zero
        return vector
    end
    return v3(
        vector.x / mag,
        vector.y / mag,
        vector.z / mag
    )
end

local function get_distance(point1, point2)
    return math.sqrt((point1.x - point2.x)^2 + (point1.y - point2.y)^2 + (point1.z - point2.z)^2)
end

local function horizontal_distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

local function calculate_velocity(distance, time)
    return distance / time
end

local function calculate_pitch_angle(velocity, gravity, distance, height_diff)
    local angle_radians = atan2(velocity^2 - math.sqrt(velocity^4 - gravity * (gravity * distance^2 + 2 * height_diff * velocity^2)), gravity * distance)
    return angle_radians * (180.0 / math.pi)
end

local function adjust_pitch_for_distance(distance, pitch_angle)
    if distance < 35 then
        return math.max(0, pitch_angle - (35 - distance) * 2)  -- Decrease pitch for close targets
    end
    return pitch_angle
end

local function calculate_dynamic_pitch(distance, height_diff)
    local base_angle = 45  -- Start with 45 degrees as base
    local distance_factor = distance / GL_MAX_DISTANCE
    local height_factor = height_diff / distance
    local adjusted_angle = base_angle * (1 - distance_factor) + height_factor * 45
    return math.max(0, math.min(adjusted_angle, 75))  -- Clamp between 0 and 75 degrees
end

local function adjust_for_bounce(predicted_position, launch_position)
    local direction = normalize(predicted_position - launch_position)
    return predicted_position + direction * 0.5
end

local function predict_grenade_trajectory(launch_position, target_position)
    -- Data taken from a test I've done, 100% accurately measured
    local example_shot_position = v3(-1435.865, -2902.595, 13.944)
    local example_land_position = v3(-1485.926, -2873.476, 13.944)
    local example_flight_time = 1.503
    local example_distance = horizontal_distance(example_shot_position.x, example_shot_position.y, example_land_position.x, example_land_position.y)
    local average_speed = calculate_velocity(example_distance, example_flight_time)

    local distance = horizontal_distance(launch_position.x, launch_position.y, target_position.x, target_position.y)
    local height_diff = target_position.z - launch_position.z
    
    -- Adjust distance factor based on distance
    local distance_factor
    if distance < 50 then
        distance_factor = 0.95 - (distance / 100) * 0.05  -- Reduced factor for short range
    elseif distance < 100 then
        distance_factor = 1.02 + ((distance - 50) / 50) * 0.02  -- Keep medium range as is
    else
        distance_factor = 1.04 + (distance / 1000) * 0.005  -- Slightly reduced factor for long range
    end
    local adjusted_distance = distance * distance_factor
    
    local flight_time = adjusted_distance / average_speed
    local velocity = calculate_velocity(adjusted_distance, flight_time)
    
    -- Adjust pitch calculation
    local pitch_angle
    if distance < 50 then
        pitch_angle = atan2(height_diff, distance) * (180 / math.pi)
        pitch_angle = math.max(pitch_angle - 5, 0) -- Reduce pitch for short range
    elseif distance < 100 then
        -- Keep medium range calculation as is
        pitch_angle = calculate_pitch_angle(velocity, GRAVITY, adjusted_distance, height_diff)
        local direct_angle = atan2(height_diff, distance) * (180 / math.pi)
        local blend_factor = (distance - 50) / 50
        pitch_angle = direct_angle * (1 - blend_factor) + pitch_angle * blend_factor
    else
        pitch_angle = calculate_pitch_angle(velocity, GRAVITY, adjusted_distance, height_diff)
        pitch_angle = math.min(pitch_angle, 30)  -- Limit long-range pitch to 30 degrees
    end
    
    pitch_angle = adjust_pitch_for_distance(adjusted_distance, pitch_angle)
    
    local dynamic_pitch = calculate_dynamic_pitch(adjusted_distance, height_diff)
    pitch_angle = (pitch_angle + dynamic_pitch) / 2
    
    -- Adjust landing position
    local direction = normalize(target_position - launch_position)
    local right_vector = v3(direction.y, -direction.x, 0)
    local rightward_bias = 0.005 + (distance / 2000) * 0.005
    
    local predicted_landing = launch_position + direction * adjusted_distance
    predicted_landing = predicted_landing + right_vector * (rightward_bias * adjusted_distance)
    
    -- Adjust height prediction
    local height_adjustment
    if distance < 50 then
        height_adjustment = -0.05 - (50 - distance) / 50 * 0.1
    elseif distance < 100 then
        height_adjustment = 0.05 + ((distance - 50) / 50) * 0.1  -- Keep medium range as is
    else
        height_adjustment = 0.15 + (height_diff / distance) * 0.05  -- Slightly reduced for long range
    end
    predicted_landing.z = predicted_landing.z + height_adjustment
    
    predicted_landing = adjust_for_bounce(predicted_landing, launch_position)
    
    if debug_prediction then
        print("Predicted grenade landing position (adjusted): " .. tostring(predicted_landing))
        print("Required pitch angle: " .. pitch_angle .. " degrees")
        print("Predicted flight time: " .. flight_time .. " seconds")
    end

    return pitch_angle, predicted_landing
end

menu.add_feature("[GL] Trajectory Prediction", "toggle", 0, function(f)
    while f.on do
        if player.is_player_free_aiming(player.player_id()) then
            local weapon_hash = ped.get_current_ped_weapon(player.player_ped())
            
            if weapon_hash == gameplay.get_hash_key("WEAPON_GRENADELAUNCHER") then
                local my_coords = player.get_player_coords(player.player_id())
                local min_distance = math.huge
                local closest_enemy = -1
                
                for pid = 0, 31 do
                    if player.is_player_valid(pid) and pid ~= player.player_id() then
                        local coords = player.get_player_coords(pid)
                        local distance = get_distance(my_coords, coords)
                
                        if distance <= GL_MAX_DISTANCE and distance < min_distance then
                            min_distance = distance
                            closest_enemy = pid
                        end
                    end
                end

                if closest_enemy ~= -1 then
                    if not entity.is_entity_dead(player.get_player_ped(closest_enemy)) then
                        if native.call(0x9134873537FA419C, player.get_player_ped(closest_enemy)):__tointeger() == 0 then -- IS_PED_IN_FLYING_VEHICLE
                            local enemy_coords = player.get_player_coords(closest_enemy)
                            
                            if not (enemy_coords.x == 0.0 and enemy_coords.y == 0.0 and enemy_coords.z == 0.0) then
                                local pitch_angle, predicted_coords = predict_grenade_trajectory(my_coords, enemy_coords)
            
                                if native.call(0x8D4D46230B2C353A):__tointeger() == 4 then -- GET_FOLLOW_PED_CAM_VIEW_MODE
                                    if horizontal_aiming then
                                        local camera_coords = native.call(0x14D6F5678D8F1B37):__tov3() -- GET_GAMEPLAY_CAM_COORD
                                        print("Cam Coords: " .. camera_coords.x .. ", " .. camera_coords.y .. ", " .. camera_coords.z)
        
                                        local camera_target = v3(
                                            enemy_coords.x - camera_coords.x,
                                            enemy_coords.y - camera_coords.y,
                                            enemy_coords.z - camera_coords.z
                                        )
        
                                        local camera_heading = atan2(camera_target.x, camera_target.y) * (180.0 / math.pi)
                                        local self_heading = entity.get_entity_heading(player.player_ped())
                                        
                                        if camera_heading >= 0.0 and camera_heading <= 180.0 then
                                            camera_heading = 360.0 - camera_heading
                                        elseif camera_heading <= 0.0 and camera_heading >= -180.0 then
                                            camera_heading = -camera_heading
                                        end
        
                                        local heading_diff = camera_heading - self_heading
        
                                        native.call(0x103991D4A307D472, heading_diff) -- SET_FIRST_PERSON_SHOOTER_CAMERA_HEADING
                                    end
    
                                    if pitch_angle ~= nil then
                                        native.call(0x759E13EBC1C15C5A, pitch_angle) -- SET_FIRST_PERSON_SHOOTER_CAMERA_PITCH
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        system.wait(0)
    end
end)

menu.add_feature("[GL] Disable Horizontal Helper", "toggle", 0, function(f)
    if f.on then
        horizontal_aiming = not horizontal_aiming
    end
end)
