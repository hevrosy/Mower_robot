#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-$HOME/Desktop/mower_motion_diag_$(date +%F_%H-%M-%S)}"
mkdir -p "$OUT_DIR"

echo "[INFO] Output dir: $OUT_DIR"
echo "[INFO] Start the commands, then drive the robot:"
echo "  A) forward ~1m"
echo "  B) stop"
echo "  C) rotate left ~90 deg"
echo "  D) stop"
echo "  E) rotate right ~90 deg"
echo "  F) stop"
echo
echo "[INFO] Recording for 25 seconds..."

timeout 25s ros2 topic echo /diff_cont/odom > "$OUT_DIR/motion_diff_cont_odom.txt" 2>&1 &
PID1=$!
timeout 25s ros2 topic echo /odometry/filtered > "$OUT_DIR/motion_odometry_filtered.txt" 2>&1 &
PID2=$!
timeout 25s ros2 topic echo /imu/data > "$OUT_DIR/motion_imu_data.txt" 2>&1 &
PID3=$!
timeout 25s ros2 topic echo /scan > "$OUT_DIR/motion_scan.txt" 2>&1 &
PID4=$!

wait $PID1 || true
wait $PID2 || true
wait $PID3 || true
wait $PID4 || true

tar -czf "${OUT_DIR}.tar.gz" -C "$(dirname "$OUT_DIR")" "$(basename "$OUT_DIR")"

echo "[DONE] Saved:"
echo "  $OUT_DIR"
echo "  ${OUT_DIR}.tar.gz"