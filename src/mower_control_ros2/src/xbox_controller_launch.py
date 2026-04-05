from launch import LaunchDescription
from launch_ros.actions import Node

def generate_launch_description():
    return LaunchDescription([
        Node(
            package='joy',
            executable='joy_node',
            name='joy_node',
            parameters=[{'dev': '/dev/input/js0'}],
        ),
        Node(
            package='mower_control_ros2',
            executable='xbox_command_mapper',
            name='xbox_command_mapper'
        ),
        Node(
            package='mower_control_ros2',
            executable='arduino_interface_node',
            name='arduino_interface_node'
        ),
    ])
