#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Imu, MagneticField
import board
import busio
from adafruit_bno08x import BNO_REPORT_ROTATION_VECTOR, BNO_REPORT_ACCELEROMETER, BNO_REPORT_GYROSCOPE, BNO_REPORT_MAGNETOMETER
from adafruit_bno08x.i2c import BNO08X_I2C

class IMUNode(Node):
    def __init__(self):
        super().__init__('bno080_node')

        self.imu_pub = self.create_publisher(Imu, 'imu/data', 10)
        self.mag_pub = self.create_publisher(MagneticField, 'imu/mag', 10)

        i2c = busio.I2C(board.SCL, board.SDA)
        self.bno = BNO08X_I2C(i2c, address=0x4B)

        self.bno.enable_feature(BNO_REPORT_ROTATION_VECTOR)
        self.bno.enable_feature(BNO_REPORT_ACCELEROMETER)
        self.bno.enable_feature(BNO_REPORT_GYROSCOPE)
        self.bno.enable_feature(BNO_REPORT_MAGNETOMETER)

        self.timer = self.create_timer(0.02, self.publish_imu_data)

    def publish_imu_data(self):
        imu_msg = Imu()
        mag_msg = MagneticField()

        quat_i, quat_j, quat_k, quat_real = self.bno.quaternion
        acc_x, acc_y, acc_z = self.bno.acceleration
        gyro_x, gyro_y, gyro_z = self.bno.gyro
        mag_x, mag_y, mag_z = self.bno.magnetic

        imu_msg.header.stamp = self.get_clock().now().to_msg()
        imu_msg.header.frame_id = 'imu_link'
        imu_msg.orientation.x = quat_i
        imu_msg.orientation.y = quat_j
        imu_msg.orientation.z = quat_k
        imu_msg.orientation.w = quat_real
        imu_msg.linear_acceleration.x = acc_x
        imu_msg.linear_acceleration.y = acc_y
        imu_msg.linear_acceleration.z = acc_z
        imu_msg.angular_velocity.x = gyro_x
        imu_msg.angular_velocity.y = gyro_y
        imu_msg.angular_velocity.z = gyro_z
        self.imu_pub.publish(imu_msg)

        mag_msg.header = imu_msg.header
        mag_msg.magnetic_field.x = mag_x
        mag_msg.magnetic_field.y = mag_y
        mag_msg.magnetic_field.z = mag_z
        self.mag_pub.publish(mag_msg)

def main(args=None):
    rclpy.init(args=args)
    node = IMUNode()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()

