cmake_minimum_required(VERSION 3.5)
project(mower_control_ros2)

# Default to C++14
if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(std_msgs REQUIRED)
find_package(serial REQUIRED)
find_package(sensor_msgs REQUIRED)

# Existing executable
add_executable(arduino_interface_node src/arduino_interface_node.cpp)
ament_target_dependencies(arduino_interface_node
  rclcpp
  std_msgs
  serial
)

# **Add your new executable explicitly**
add_executable(xbox_command_mapper src/xbox_command_mapper.cpp)
ament_target_dependencies(xbox_command_mapper
  rclcpp
  std_msgs
  sensor_msgs
)

# Install both executables explicitly
install(TARGETS
  arduino_interface_node
  xbox_command_mapper
  DESTINATION lib/${PROJECT_NAME}
)

ament_package()
