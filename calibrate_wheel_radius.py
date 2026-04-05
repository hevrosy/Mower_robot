#!/usr/bin/env python3
import math
import threading
import time

import rclpy
from rclpy.node import Node
from nav_msgs.msg import Odometry


class OdomDistanceRecorder(Node):
    def __init__(self):
        super().__init__('odom_distance_recorder_live')
        self.sub = self.create_subscription(Odometry, '/diff_cont/odom', self.cb, 50)

        self.lock = threading.Lock()
        self.have_data = False

        self.start_x = 0.0
        self.start_y = 0.0
        self.last_x = 0.0
        self.last_y = 0.0

    def cb(self, msg: Odometry):
        x = msg.pose.pose.position.x
        y = msg.pose.pose.position.y

        with self.lock:
            if not self.have_data:
                self.start_x = x
                self.start_y = y
                self.have_data = True

            self.last_x = x
            self.last_y = y

    def reset_start(self):
        with self.lock:
            self.start_x = self.last_x
            self.start_y = self.last_y

    def distance(self) -> float:
        with self.lock:
            return math.hypot(self.last_x - self.start_x, self.last_y - self.start_y)


def main():
    rclpy.init()
    node = OdomDistanceRecorder()

    spinner = threading.Thread(target=rclpy.spin, args=(node,), daemon=True)
    spinner.start()

    print("[INFO] Waiting for /diff_cont/odom ...")
    while rclpy.ok() and not node.have_data:
        time.sleep(0.05)

    input("[INFO] Put robot on start line, then press ENTER...")
    node.reset_start()

    print("[INFO] Drive straight now.")
    print("[INFO] Watch the live odom distance below.")
    print("[INFO] When finished, press Ctrl+C.\n")

    try:
        while True:
            d = node.distance()
            print(f"\rOdom distance: {d:.4f} m", end="", flush=True)
            time.sleep(0.1)
    except KeyboardInterrupt:
        pass

    odom_distance = node.distance()
    print(f"\n\n[RESULT] Final odom distance = {odom_distance:.6f} m")

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()