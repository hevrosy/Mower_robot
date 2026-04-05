#!/usr/bin/env python3
import math
import threading
import time

import rclpy
from rclpy.node import Node
from nav_msgs.msg import Odometry


def yaw_from_quat(z: float, w: float) -> float:
    return 2.0 * math.atan2(z, w)


def normalize_angle(a: float) -> float:
    while a > math.pi:
        a -= 2.0 * math.pi
    while a < -math.pi:
        a += 2.0 * math.pi
    return a


class OdomTurnRecorder(Node):
    def __init__(self):
        super().__init__('odom_turn_recorder')
        self.sub = self.create_subscription(Odometry, '/diff_cont/odom', self.cb, 50)

        self.lock = threading.Lock()
        self.have_data = False
        self.last_yaw = 0.0
        self.prev_yaw = 0.0
        self.total_yaw_rad = 0.0

    def cb(self, msg: Odometry):
        z = msg.pose.pose.orientation.z
        w = msg.pose.pose.orientation.w
        yaw = yaw_from_quat(z, w)

        with self.lock:
            if not self.have_data:
                self.last_yaw = yaw
                self.prev_yaw = yaw
                self.have_data = True
                return

            dyaw = normalize_angle(yaw - self.last_yaw)
            self.total_yaw_rad += dyaw
            self.prev_yaw = self.last_yaw
            self.last_yaw = yaw

    def reset(self):
        with self.lock:
            self.total_yaw_rad = 0.0

    def total_yaw_deg(self) -> float:
        with self.lock:
            return math.degrees(self.total_yaw_rad)


def main():
    rclpy.init()
    node = OdomTurnRecorder()

    spinner = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spinner.start()

    print("[INFO] Waiting for /diff_cont/odom ...")
    while rclpy.ok() and not node.have_data:
        time.sleep(0.05)

    print("[INFO] Odom received.")
    input("[INFO] Align robot forward marker with a floor line, then press ENTER...")

    node.reset()

    print("\n[INFO] Rotate the robot in place.")
    print("[INFO] Best method: do EXACTLY 3 full turns and stop when the marker points")
    print("[INFO] again along the same floor line.")
    print("[INFO] Press Ctrl+C when finished.\n")

    try:
        while True:
            angle = node.total_yaw_deg()
            print(f"\rAccumulated odom angle: {angle:.2f} deg", end="", flush=True)
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass

    odom_angle = node.total_yaw_deg()
    print(f"\n\n[RESULT] Final accumulated odom angle = {odom_angle:.6f} deg")

    real_turns = float(input("Enter REAL number of full turns (example: 3): ").strip())
    old_sep = float(input("Enter current wheel_separation from YAML: ").strip())

    real_angle = 360.0 * real_turns
    new_sep = old_sep * (real_angle / odom_angle)

    print("\n===== CALIBRATION RESULT =====")
    print(f"Old wheel_separation : {old_sep:.6f}")
    print(f"Odom angle           : {odom_angle:.6f} deg")
    print(f"Real turns           : {real_turns:.3f}")
    print(f"Real angle           : {real_angle:.6f} deg")
    print(f"New wheel_separation : {new_sep:.6f}")
    print("==============================")

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()