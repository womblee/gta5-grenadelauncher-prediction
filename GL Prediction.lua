menu.add_feature("Grenade Trajectory Prediction", "toggle", 0, function(f)
    local GL_MAX_DISTANCE = 150 -- Maximum tested distance of the grenade landing
    local GRAVITY = 9.81        -- Gravity, might need adjustment
    
    local function atan2(y, x)
      if (x == 0) then
        if (y > 0) then
          return math.pi / 2
        elseif (y < 0) then
          return -math.pi / 2
        else
          return 0
        end
      end
    
      local angle = math.atan(y / x)
      if (x < 0) then
        angle = angle + math.pi
      elseif (y < 0 and x > 0) then
        angle = angle + 2 * math.pi
      end
    
      return angle
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
        local angle_radians = math.atan((velocity^2 - math.sqrt(velocity^4 - gravity * (gravity * distance^2 + 2 * height_diff * velocity^2))) / (gravity * distance))
        return angle_radians * (180.0 / math.pi)
    end

    local function predict_grenade_trajectory(launch_position, target_position)
      -- Real-world data for calculating average speed
      local shot_position = v3(-1379.319, -3101.559, 13.964)
      local land_position = v3(-1297.986, -3148.781, 13.964)
      local target_position_real = v3(-1321.882, -3134.708, 13.964)
    
      -- Estimate flight time (you may need to adjust this based on actual observations)
      local estimated_flight_time = 2.5  -- seconds
    
      local actual_distance = horizontal_distance(shot_position.x, shot_position.y, land_position.x, land_position.y)
      local average_speed = calculate_velocity(actual_distance, estimated_flight_time)
    
      -- Calculate overshoot
      local target_to_land_distance = horizontal_distance(target_position_real.x, target_position_real.y, land_position.x, land_position.y)
      local overshoot_ratio = target_to_land_distance / actual_distance
    
      -- Generalize flight time calculation based on average speed
      local distance = horizontal_distance(launch_position.x, launch_position.y, target_position.x, target_position.y)
    
      -- Adjust target position to land 2 meters closer (modify based on your coordinate system)
      local adjusted_distance = horizontal_distance(launch_position.x, launch_position.y, target_position.x, target_position.y)  -- Adjust distance based on modified target
      local flight_time = adjusted_distance / average_speed
    
      local height_diff = target_position.z - launch_position.z
    
      -- Ensure the distance does not exceed the maximum allowed distance
      if adjusted_distance > GL_MAX_DISTANCE then
        adjusted_distance = GL_MAX_DISTANCE
      end
    
      local velocity = calculate_velocity(adjusted_distance, flight_time)
      local pitch_angle = calculate_pitch_angle(velocity, GRAVITY, adjusted_distance, height_diff)
    
      -- Adjust pitch angle based on observed overshoot
      pitch_angle = math.min(pitch_angle * (1 - overshoot_ratio * 1.5), 75) -- Limit to 75 degrees
    
      print("Predicted grenade landing position (adjusted): " .. tostring(target_position))
      print("Required pitch angle: " .. pitch_angle .. " degrees")
      print("Predicted flight time: " .. flight_time .. " seconds")
    
      return pitch_angle, target_position
    end

    while f.on do
        if player.is_player_free_aiming(player.player_id()) then
            local weapon_hash = ped.get_current_ped_weapon(player.player_ped())
            
            -- There must always be one grenade loaded
            if weapon_hash == gameplay.get_hash_key("WEAPON_GRENADELAUNCHER") then
                -- Personal coords
                local my_coords = player.get_player_coords(player.player_id())

                -- Find closest enemy
                local min_distance = math.huge
                local closest_enemy = -1

                for pid = 0, 31 do
                    if player.is_player_valid(pid) and pid ~= player.player_id() then
                        local coords = player.get_player_coords(pid)
                        local distance = get_distance(my_coords, coords)

                        if distance < min_distance then
                            min_distance = distance
                            closest_enemy = pid
                        end
                    end
                end

                if closest_enemy ~= -1 then
                    if not entity.is_entity_dead(player.get_player_ped(closest_enemy)) then
                        -- IS_PED_IN_FLYING_VEHICLE
                        if native.call(0x9134873537FA419C, player.get_player_ped(closest_enemy)):__tonumber() == 0 then
                            local enemy_coords = player.get_player_coords(closest_enemy)
                            
                            -- Predict trajectory
                            local pitch_angle, predicted_coords = predict_grenade_trajectory(my_coords, enemy_coords)
        
                            if native.call(0x8D4D46230B2C353A):__tointeger() == 4 then -- GET_FOLLOW_PED_CAM_VIEW_MODE (4 is first person)
                                -- Horizontal aiming, disabled due to working badly
                                if false then
                                    local camera_coords = native.ByteBuffer16()
                                    native.call(0x14D6F5678D8F1B37, camera_coords) -- GET_GAMEPLAY_CAM_COORD
                                    camera_coords = camera_coords:__tov3()
    
                                    print(camera_coords.x .. ", " .. camera_coords.y .. ", " .. camera_coords.z)
    
                                    local camera_target = v3(
                                        enemy_coords.x - camera_coords.x,
                                        enemy_coords.y - camera_coords.y,
                                        enemy_coords.z - camera_coords.z
                                    )
    
                                    -- Calculate heading using atan
                                    local camera_heading = atan2(camera_target.x, camera_target.y) * (180.0 / math.pi)
                                    local self_heading = entity.get_entity_heading(player.player_ped())
                                    
                                    if camera_heading >= 0.0 and camera_heading <= 180.0 then
                                        camera_heading = 360.0 - camera_heading
                                    elseif camera_heading <= -0.0 and camera_heading >= -180.0 then
                                        camera_heading = -camera_heading
                                    end
    
                                    -- Diff
                                    heading_diff = camera_heading - self_heading
    
                                    -- Implement smoothing (adjust the factor as needed)
                                    local smoothing_factor = 0.1
                                    heading_diff = heading_diff * smoothing_factor
                    
                                    -- Apply the smooth heading adjustment
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

        system.wait(0)
    end
end)