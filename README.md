# Grenade Launcher Prediction (GTA 5)
Prediction concept for the grenade launcher, written for 2Take1 in Lua

# Known issues
- Medium distances work badly

# How it works
It uses sample data:
```lua
-- Real-world data for calculating average speed
local shot_position = v3(-1379.319, -3101.559, 13.964)
local land_position = v3(-1297.986, -3148.781, 13.964)
local target_position_real = v3(-1321.882, -3134.708, 13.964)
    
-- Estimate flight time (you may need to adjust this based on actual observations)
local estimated_flight_time = 2.5  -- seconds
```

And it makes mathematical calculations just by knowing YOUR position and the ENEMY position.

```lua
-- Predict trajectory
local pitch_angle, predicted_coords = predict_grenade_trajectory(my_coords, enemy_coords)
```

It gives out the needed weapon pitch which we use to aim with.

```lua
print("Predicted grenade landing position (adjusted): " .. tostring(target_position))
print("Required pitch angle: " .. pitch_angle .. " degrees")
print("Predicted flight time: " .. flight_time .. " seconds")
```
```lua
-- Apply the smooth heading adjustment
native.call(0x103991D4A307D472, heading_diff) -- SET_FIRST_PERSON_SHOOTER_CAMERA_HEADING
```
150 is the maximum distance a grenade can fly, and 75 is the maximum pitch.

# How can I use it
This script was specifically writen for 2Take1Menu, but you can rewrite it in C++ for your own purposes.
