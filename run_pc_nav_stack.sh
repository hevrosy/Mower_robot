#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-help}"
MAP_NAME="${2:-mower_map}"

WS="$HOME/Desktop/Mower/dev_ws"
MAP_DIR="$HOME/Desktop/maps"
ROS_SETUP="/opt/ros/jazzy/setup.bash"
WS_SETUP="$WS/install/setup.bash"
EKF_PARAMS="$WS/src/my_bot/config/ekf.yaml"
NAV2_PARAMS="$WS/src/my_bot/config/nav2_params.yaml"
TMP_NAV2_PARAMS="$WS/src/my_bot/config/nav2_params_runtime.yaml"

MAP_YAML="$MAP_DIR/${MAP_NAME}.yaml"

log() {
  echo
  echo "[INFO] $1"
}

run_bg() {
  local name="$1"
  shift
  log "Starting $name"
  nohup bash -lc "source '$ROS_SETUP'; source '$WS_SETUP'; $*" \
    > "$WS/${name}.log" 2>&1 &
  sleep 1
}

kill_old_pc() {
  log "Killing old PC-side ROS/Nav2 processes"
  pkill -f "joy_node" || true
  pkill -f "teleop_twist_joy" || true
  pkill -f "ekf_node" || true
  pkill -f "ekf_filter_node" || true
  pkill -f "slam_toolbox" || true
  pkill -f "map_server" || true
  pkill -f "amcl" || true
  pkill -f "planner_server" || true
  pkill -f "controller_server" || true
  pkill -f "behavior_server" || true
  pkill -f "bt_navigator" || true
  pkill -f "waypoint_follower" || true
  pkill -f "velocity_smoother" || true
  pkill -f "lifecycle_manager" || true
  pkill -f "rviz2" || true
  sleep 2
}

prepare_runtime_nav2_params() {
  mkdir -p "$MAP_DIR"

  if [[ ! -f "$NAV2_PARAMS" ]]; then
    echo "[ERROR] Base nav2 params file not found: $NAV2_PARAMS"
    exit 1
  fi

  python3 - <<PY
from pathlib import Path
src = Path("$NAV2_PARAMS")
dst = Path("$TMP_NAV2_PARAMS")
text = src.read_text(encoding="utf-8")
text = text.replace('yaml_filename: "/home/base/Desktop/maps/mower_map.yaml"',
                    'yaml_filename: "$MAP_YAML"')
dst.write_text(text, encoding="utf-8")
print(f"[INFO] Wrote runtime params: {dst}")
PY
}

start_joystick() {
  run_bg joystick "ros2 launch my_bot joystick.launch.py"
}

start_ekf() {
  run_bg ekf "ros2 run robot_localization ekf_node --ros-args --params-file '$EKF_PARAMS'"
}

open_rviz() {
  run_bg rviz "rviz2"
}

start_mapping() {
  start_ekf
  run_bg slam "ros2 launch slam_toolbox online_async_launch.py"
}

start_localization() {
  if [[ ! -f "$MAP_YAML" ]]; then
    echo "[ERROR] Map not found: $MAP_YAML"
    exit 1
  fi

  prepare_runtime_nav2_params
  start_ekf
  run_bg map_server "ros2 run nav2_map_server map_server --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg amcl "ros2 run nav2_amcl amcl --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg lifecycle_localization "ros2 run nav2_lifecycle_manager lifecycle_manager --ros-args -r __node:=lifecycle_manager_localization --params-file '$TMP_NAV2_PARAMS'"
}

start_navigation() {
  if [[ ! -f "$MAP_YAML" ]]; then
    echo "[ERROR] Map not found: $MAP_YAML"
    exit 1
  fi

  prepare_runtime_nav2_params
  start_ekf
  run_bg map_server "ros2 run nav2_map_server map_server --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg amcl "ros2 run nav2_amcl amcl --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg lifecycle_localization "ros2 run nav2_lifecycle_manager lifecycle_manager --ros-args -r __node:=lifecycle_manager_localization --params-file '$TMP_NAV2_PARAMS'"
  sleep 4
  run_bg planner_server "ros2 run nav2_planner planner_server --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg controller_server "ros2 run nav2_controller controller_server --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg behavior_server "ros2 run nav2_behaviors behavior_server --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg bt_navigator "ros2 run nav2_bt_navigator bt_navigator --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg waypoint_follower "ros2 run nav2_waypoint_follower waypoint_follower --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg velocity_smoother "ros2 run nav2_velocity_smoother velocity_smoother --ros-args --params-file '$TMP_NAV2_PARAMS'"
  run_bg lifecycle_navigation "ros2 run nav2_lifecycle_manager lifecycle_manager --ros-args -r __node:=lifecycle_manager_navigation --params-file '$TMP_NAV2_PARAMS'"
}

save_map() {
  mkdir -p "$MAP_DIR"
  log "Saving current map as: $MAP_NAME"
  bash -lc "source '$ROS_SETUP'; source '$WS_SETUP'; ros2 run nav2_map_server map_saver_cli -f '$MAP_DIR/$MAP_NAME'"
  log "Saved files:"
  ls -lh "$MAP_DIR/$MAP_NAME".*
}

list_maps() {
  mkdir -p "$MAP_DIR"
  log "Available maps in $MAP_DIR"
  ls -1 "$MAP_DIR"/*.yaml 2>/dev/null || echo "No maps found"
}

print_free_drive_instructions() {
  cat <<EOF

============= FREE DRIVE MODE =============
Какво пуска на PC:
- joystick
- EKF
- RViz

Какво НЕ пуска:
- slam_toolbox
- map_server
- amcl
- nav2 planner/controller

Използвай го когато:
- искаш само ръчно каране
- искаш да виждаш scan/robot model в RViz
- не ти трябва карта или автономия

На робота трябва вече да работят:
- robot bringup / drive stack
- lidar
- imu

Какво да направиш в RViz:
1. Fixed Frame = odom
2. Add:
   - LaserScan
   - TF
   - RobotModel
   - Odometry (optional)

Команда:
  $WS/run_pc_nav_stack.sh free-drive

===========================================
EOF
}

print_mapping_instructions() {
  cat <<EOF

================ MAPPING MODE ================
Какво пуска на PC:
- EKF
- slam_toolbox
- RViz

Какво прави:
- позволява да караш ръчно и да правиш нова карта

На робота трябва вече да работят:
- robot bringup / drive stack
- lidar
- imu

Текущо име на картата за запис:
  $MAP_NAME

Какво да направиш в RViz:
1. Fixed Frame = map
2. Add:
   - Map
   - LaserScan
   - TF
   - RobotModel
3. Карай бавно с joystick
4. Направи картата
5. Като си готов, запази я с:
   $WS/run_pc_nav_stack.sh save-map $MAP_NAME

Команда за старт:
  $WS/run_pc_nav_stack.sh mapping $MAP_NAME

================================================
EOF
}

print_localization_instructions() {
  cat <<EOF

============= LOCALIZATION MODE =============
Какво пуска на PC:
- EKF
- map_server
- amcl
- lifecycle_manager_localization
- RViz

Какво прави:
- зарежда избраната карта
- локализира робота върху нея

На робота трябва вече да работят:
- robot bringup / drive stack
- lidar
- imu

Заредена карта:
  $MAP_YAML

Какво да направиш в RViz:
1. Fixed Frame = map
2. Add:
   - Map
   - LaserScan
   - TF
   - RobotModel
3. За Map display:
   - Topic = /map
   - Reliability = Reliable
   - Durability = Transient Local
4. Изчакай 5–10 секунди
5. Натисни "2D Pose Estimate"
6. Щракни приблизително къде е роботът
7. Завлечи мишката, за да зададеш посоката
8. Помръдни робота леко, ако трябва AMCL да се донастрои

Проверка:
  ros2 topic echo /amcl_pose --once

Команда за старт:
  $WS/run_pc_nav_stack.sh localization $MAP_NAME

=============================================
EOF
}

print_navigation_instructions() {
  cat <<EOF

============= NAVIGATION MODE =============
Какво пуска на PC:
- EKF
- map_server
- amcl
- localization lifecycle manager
- planner_server
- controller_server
- behavior_server
- bt_navigator
- waypoint_follower
- velocity_smoother
- navigation lifecycle manager
- RViz

Какво прави:
- локализация + пълния Nav2 stack
- позволява да даваш Nav2 Goal

На робота трябва вече да работят:
- robot bringup / drive stack
- lidar
- imu

Заредена карта:
  $MAP_YAML

Какво да направиш в RViz:
1. Fixed Frame = map
2. Add:
   - Map
   - LaserScan
   - TF
   - RobotModel
3. За Map display:
   - Topic = /map
   - Reliability = Reliable
   - Durability = Transient Local
4. Изчакай 5–10 секунди
5. Натисни "2D Pose Estimate"
6. Увери се, че локализацията е стабилна
7. После натисни "Nav2 Goal" / "2D Goal Pose"
8. Избери кратка, лесна цел

За първи тестове:
- ножът да е изключен
- избирай близки цели
- стой до робота готов да го спреш

Проверки:
  ros2 topic echo /amcl_pose --once
  ros2 topic echo /plan --once
  ros2 topic echo /cmd_vel --once

Команда за старт:
  $WS/run_pc_nav_stack.sh navigation $MAP_NAME

===========================================
EOF
}

print_save_map_instructions() {
  cat <<EOF

============= SAVE MAP MODE =============
Какво прави:
- записва текущата карта от slam_toolbox / map topic

Къде я записва:
- $MAP_DIR/${MAP_NAME}.yaml
- $MAP_DIR/${MAP_NAME}.pgm

Изискване:
- mapping режимът трябва още да работи
- /map topic трябва да е наличен

Команда:
  $WS/run_pc_nav_stack.sh save-map $MAP_NAME

=========================================
EOF
}

print_list_maps_instructions() {
  cat <<EOF

============= LIST MAPS MODE =============
Какво прави:
- показва всички налични .yaml карти в $MAP_DIR

Команда:
  $WS/run_pc_nav_stack.sh list-maps

==========================================
EOF
}

show_help() {
  cat <<EOF
Usage:
  ./run_pc_nav_stack.sh free-drive
  ./run_pc_nav_stack.sh mapping <map_name>
  ./run_pc_nav_stack.sh save-map <map_name>
  ./run_pc_nav_stack.sh localization <map_name>
  ./run_pc_nav_stack.sh navigation <map_name>
  ./run_pc_nav_stack.sh list-maps
  ./run_pc_nav_stack.sh stop
  ./run_pc_nav_stack.sh help

Modes:
  free-drive     joystick + ekf + rviz
  mapping        ekf + slam_toolbox + rviz
  save-map       save current map with chosen name
  localization   ekf + map_server + amcl + rviz
  navigation     localization + full nav2 stack + rviz
  list-maps      list all saved maps
  stop           stop all PC-side processes

Examples:
  ./run_pc_nav_stack.sh free-drive
  ./run_pc_nav_stack.sh mapping kitchen
  ./run_pc_nav_stack.sh save-map kitchen
  ./run_pc_nav_stack.sh localization kitchen
  ./run_pc_nav_stack.sh navigation kitchen

IMPORTANT:
- This script is for PC-side nodes.
- Robot-side nodes must already be running on the robot.

Logs:
  $WS/*.log
EOF
}

main() {
  if [[ ! -f "$ROS_SETUP" ]]; then
    echo "[ERROR] ROS setup not found: $ROS_SETUP"
    exit 1
  fi

  if [[ ! -f "$WS_SETUP" ]]; then
    echo "[ERROR] Workspace setup not found: $WS_SETUP"
    exit 1
  fi

  case "$MODE" in
    stop)
      kill_old_pc
      log "All known PC-side processes stopped"
      ;;
    free-drive)
      kill_old_pc
      start_joystick
      start_ekf
      sleep 2
      open_rviz
      print_free_drive_instructions
      ;;
    mapping)
      kill_old_pc
      start_joystick
      start_mapping
      sleep 2
      open_rviz
      print_mapping_instructions
      ;;
    save-map)
      print_save_map_instructions
      save_map
      ;;
    localization)
      kill_old_pc
      start_joystick
      start_localization
      sleep 3
      open_rviz
      print_localization_instructions
      ;;
    navigation)
      kill_old_pc
      start_joystick
      start_navigation
      sleep 3
      open_rviz
      print_navigation_instructions
      ;;
    list-maps)
      print_list_maps_instructions
      list_maps
      ;;
    help|*)
      show_help
      ;;
  esac
}

main "$@"
