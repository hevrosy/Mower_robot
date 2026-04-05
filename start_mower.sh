#!/bin/bash

# Зареждаме работната среда
source ~/dev_ws/install/setup.bash

# Функция, която се изпълнява при натискане на Ctrl+C
cleanup() {
    echo ""
    echo "🛑 Спиране на всички ROS 2 възли..."
    kill $PID1 $PID2 $PID3 $PID4
    wait $PID1 $PID2 $PID3 $PID4 2>/dev/null
    echo "✅ Всички възли са спрени успешно!"
    exit 0
}

# Казваме на скрипта да слуша за Ctrl+C (SIGINT) и да пусне функцията cleanup
trap cleanup SIGINT SIGTERM

echo "🚀 Стартиране на системата..."

# 1. Контролер
ros2 launch mower_control_ros2 xbox_controller_launch.py &
PID1=$!
echo "-> Xbox Controller стартиран (PID: $PID1)"

# 2. LiDAR
ros2 launch my_bot rplidar.launch.py &
PID2=$!
echo "-> RPLidar стартиран (PID: $PID2)"

# 3. IMU
ros2 run bno080_ros2 imu_node &
PID3=$!
echo "-> IMU Node стартиран (PID: $PID3)"

# 4. Основен робот
ros2 launch my_bot launch_robot.launch.py &
PID4=$!
echo "-> Core Robot стартиран (PID: $PID4)"

echo ""
echo "🟢 Системата работи! Натисни [Ctrl + C], за да спреш всичко."

# Скриптът чака тук безкрайно, докато не натиснеш Ctrl+C
wait
