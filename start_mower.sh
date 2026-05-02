#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-help}"
MAP_NAME="${2:-mower_map}"

WS="$HOME/dev_ws"
MAP_DIR="$HOME/maps"
BAG_DIR="$HOME/mower_bags"

ROS_SETUP="/opt/ros/jazzy/setup.bash"
WS_SETUP="$WS/install/setup.bash"

EKF_PARAMS="$WS/src/my_bot/config/ekf.yaml"
NAV2_PARAMS="$WS/src/my_bot/config/nav2_params.yaml"
TMP_NAV2_PARAMS="$WS/src/my_bot/config/nav2_params_runtime.yaml"
MAPPER_PARAMS="$WS/src/my_bot/config/mapper_params_online_async.yaml"
SCAN_FILTER_PARAMS="$WS/src/my_bot/config/scan_filter.yaml"

MAP_YAML="$MAP_DIR/${MAP_NAME}.yaml"

PIDS=()

log() {
  echo
  echo "[INFO] $1"
}

run_bg() {
  local name="$1"
  shift

  log "Starting $name"
  bash -lc "source '$ROS_SETUP'; source '$WS_SETUP'; $*" \
    > "$WS/${name}.log" 2>&1 &

  local pid=$!
  PIDS+=("$pid")
  echo "  -> $name PID: $pid"
  sleep 1
}

kill_old_robot() {
  log "Killing old robot-side ROS processes"

  pkill -f "joy_node" || true
  pkill -f "teleop_twist_joy" || true
  pkill -f "xbox_command_mapper" || true

  pkill -f "sllidar_node" || true
  pkill -f "rplidar" || true
  pkill -f "scan_to_scan_filter_chain" || true

  pkill -f "imu_node" || true
  pkill -f "bno080" || true

  pkill -f "robot_state_publisher" || true
  pkill -f "twist_mux" || true
  pkill -f "twist_stamper" || true
  pkill -f "ros2_control_node" || true
  pkill -f "spawner" || true

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

  sleep 2
}

cleanup() {
  echo
  echo "🛑 Stopping started processes..."
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
  echo "✅ Stopped."
}

trap cleanup SIGINT SIGTERM EXIT

prepare_runtime_nav2_params() {
  mkdir -p "$MAP_DIR"

  if [[ ! -f "$NAV2_PARAMS" ]]; then
    echo "[ERROR] Missing nav2 params: $NAV2_PARAMS"
    exit 1
  fi

  if [[ ! -f "$MAP_YAML" ]]; then
    echo "[ERROR] Map not found: $MAP_YAML"
    echo "Available maps:"
    ls -1 "$MAP_DIR"/*.yaml 2>/dev/null || true
    exit 1
  fi

  python3 - <<PY
from pathlib import Path

src = Path("$NAV2_PARAMS")
dst = Path("$TMP_NAV2_PARAMS")
map_yaml = "$MAP_YAML"

text = src.read_text(encoding="utf-8")

# Works for both old PC path and robot path
import re
text = re.sub(
    r'yaml_filename:\s*".*?mower_map\.yaml"',
    f'yaml_filename: "{map_yaml}"',
    text
)

dst.write_text(text, encoding="utf-8")
print(f"[INFO] Runtime Nav2 params written: {dst}")
PY
}

start_base() {
  run_bg lidar "ros2 launch my_bot rplidar.launch.py"

  run_bg scan_filter \
    "ros2 run laser_filters scan_to_scan_filter_chain --ros-args --params-file '$SCAN_FILTER_PARAMS' -r /scan:=/scan -r /scan_filtered:=/scan_filtered"

  run_bg imu "ros2 run bno080_ros2 imu_node"
  run_bg robot_core "ros2 launch my_bot launch_robot.launch.py"

  sleep 3
}

start_ekf() {
  run_bg ekf "ros2 run robot_localization ekf_node --ros-args --params-file '$EKF_PARAMS'"
}

start_mapping() {
  start_ekf

  run_bg slam_toolbox \
    "ros2 launch slam_toolbox online_async_launch.py slam_params_file:='$MAPPER_PARAMS'"

  log "Mapping is running. Use RViz from PC. Map topic: /map. Scan topic: /scan_filtered"
}

start_localization() {
  prepare_runtime_nav2_params
  start_ekf

  run_bg map_server \
    "ros2 run nav2_map_server map_server --ros-args --params-file '$TMP_NAV2_PARAMS'"

  run_bg amcl \
    "ros2 run nav2_amcl amcl --ros-args --params-file '$TMP_NAV2_PARAMS'"

  run_bg lifecycle_localization \
    "ros2 run nav2_lifecycle_manager lifecycle_manager --ros-args -r __node:=lifecycle_manager_localization --params-file '$TMP_NAV2_PARAMS'"
}

start_navigation() {
  prepare_runtime_nav2_params
  start_localization

  sleep 4

  run_bg planner_server \
    "ros2 run nav2_planner planner_server --ros-args --params-file '$TMP_NAV2_PARAMS'"

  run_bg controller_server \
    "ros2 run nav2_controller controller_server --ros-args --params-file '$TMP_NAV2_PARAMS' -r /cmd_vel:=/cmd_vel_nav_raw"

  run_bg behavior_server \
    "ros2 run nav2_behaviors behavior_server --ros-args --params-file '$TMP_NAV2_PARAMS' -r /cmd_vel:=/cmd_vel_nav_raw"

  run_bg bt_navigator \
    "ros2 run nav2_bt_navigator bt_navigator --ros-args --params-file '$TMP_NAV2_PARAMS'"

  run_bg waypoint_follower \
    "ros2 run nav2_waypoint_follower waypoint_follower --ros-args --params-file '$TMP_NAV2_PARAMS'"

  run_bg velocity_smoother \
    "ros2 run nav2_velocity_smoother velocity_smoother --ros-args --params-file '$TMP_NAV2_PARAMS' -r /cmd_vel:=/cmd_vel_nav_raw -r /cmd_vel_smoothed:=/cmd_vel_nav"

  run_bg lifecycle_navigation \
    "ros2 run nav2_lifecycle_manager lifecycle_manager --ros-args -r __node:=lifecycle_manager_navigation --params-file '$TMP_NAV2_PARAMS'"
}

save_map() {
  mkdir -p "$MAP_DIR"
  log "Saving map: $MAP_NAME"

  bash -lc "source '$ROS_SETUP'; source '$WS_SETUP'; ros2 run nav2_map_server map_saver_cli -f '$MAP_DIR/$MAP_NAME'"

  log "Saved:"
  ls -lh "$MAP_DIR/$MAP_NAME".*
}

record_bag() {
  mkdir -p "$BAG_DIR"
  local bag_name="${MAP_NAME}_$(date +%Y%m%d_%H%M%S)"

  log "Recording bag locally on Raspberry Pi: $BAG_DIR/$bag_name"

  bash -lc "source '$ROS_SETUP'; source '$WS_SETUP'; ros2 bag record \
    -o '$BAG_DIR/$bag_name' \
    /scan /scan_filtered /tf /tf_static /diff_cont/odom /odometry/filtered /imu/data /cmd_vel_joy /cmd_vel_nav /diff_cont/cmd_vel_unstamped"
}

list_maps() {
  mkdir -p "$MAP_DIR"
  log "Maps in $MAP_DIR:"
  ls -1 "$MAP_DIR"/*.yaml 2>/dev/null || echo "No maps found."
}

status() {
  bash -lc "source '$ROS_SETUP'; source '$WS_SETUP'; \
    echo '--- nodes ---'; ros2 node list | sort; \
    echo; echo '--- cmd topics ---'; ros2 topic list | grep cmd_vel || true; \
    echo; echo '--- scan topics ---'; ros2 topic list | grep scan || true; \
    echo; echo '--- lifecycle ---'; \
    ros2 lifecycle get /controller_server 2>/dev/null || true; \
    ros2 lifecycle get /planner_server 2>/dev/null || true; \
    ros2 lifecycle get /behavior_server 2>/dev/null || true; \
    ros2 lifecycle get /bt_navigator 2>/dev/null || true; \
    ros2 lifecycle get /velocity_smoother 2>/dev/null || true"
}

show_help() {
  cat <<EOF
Usage:
  ./start_mower_robot.sh free-drive
  ./start_mower_robot.sh mapping <map_name>
  ./start_mower_robot.sh save-map <map_name>
  ./start_mower_robot.sh localization <map_name>
  ./start_mower_robot.sh navigation <map_name>
  ./start_mower_robot.sh record-bag <name>
  ./start_mower_robot.sh list-maps
  ./start_mower_robot.sh status
  ./start_mower_robot.sh stop

Modes:
  free-drive     robot base + lidar + scan_filter + imu + joystick + ekf
  mapping        free-drive + slam_toolbox
  save-map       saves current /map to ~/maps/<map_name>
  localization   free-drive + map_server + amcl
  navigation     localization + full Nav2 stack
  record-bag     records important topics locally on Raspberry Pi
  list-maps      lists ~/maps/*.yaml
  status         prints useful ROS status
  stop           kills known robot-side nodes

Examples:
  ./start_mower_robot.sh free-drive
  ./start_mower_robot.sh mapping dvor_test_01
  ./start_mower_robot.sh save-map dvor_test_01
  ./start_mower_robot.sh navigation dvor_test_01
  ./start_mower_robot.sh record-bag dvor_test_01

Important:
  PC should run only RViz. Mapping and Nav2 now run on Raspberry Pi.
EOF
}

main() {
  if [[ ! -f "$ROS_SETUP" ]]; then
    echo "[ERROR] Missing ROS setup: $ROS_SETUP"
    exit 1
  fi

  if [[ ! -f "$WS_SETUP" ]]; then
    echo "[ERROR] Missing workspace setup: $WS_SETUP"
    echo "Run: cd ~/dev_ws && colcon build && source install/setup.bash"
    exit 1
  fi

  case "$MODE" in
    stop)
      kill_old_robot
      ;;
    free-drive)
      kill_old_robot
      start_base
      start_ekf
      log "Free-drive running. Press Ctrl+C to stop."
      wait
      ;;
    mapping)
      kill_old_robot
      start_base
      start_mapping
      log "Mapping running for map name: $MAP_NAME"
      log "When done, run in another terminal: ./start_mower_robot.sh save-map $MAP_NAME"
      wait
      ;;
    save-map)
      save_map
      ;;
    localization)
      kill_old_robot
      start_base
      start_localization
      log "Localization running with map: $MAP_YAML"
      wait
      ;;
    navigation)
      kill_old_robot
      start_base
      start_navigation
      log "Navigation running with map: $MAP_YAML"
      wait
      ;;
    record-bag)
      record_bag
      ;;
    list-maps)
      list_maps
      ;;
    status)
      status
      ;;
    help|*)
      show_help
      ;;
  esac
}

main "$@"