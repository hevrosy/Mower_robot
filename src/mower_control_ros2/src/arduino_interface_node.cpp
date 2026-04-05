#include <chrono>
#include <memory>
#include <string>
#include <sstream>

#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
#include "serial/serial.h"

using namespace std::chrono_literals;

class ArduinoInterface : public rclcpp::Node
{
public:
  ArduinoInterface()
  : Node("arduino_interface_node")
  {
    // Publisher for messages coming from Arduino (status messages)
    publisher_ = this->create_publisher<std_msgs::msg::String>("arduino_status", 10);
    
    // Subscription for commands to be sent to the Arduino.
    // Publish command strings (e.g., "UP50", "MR075", "DN20", etc.) on the "arduino_commands" topic.
    subscription_ = this->create_subscription<std_msgs::msg::String>(
      "arduino_commands", 10,
      std::bind(&ArduinoInterface::command_callback, this, std::placeholders::_1));

    // Setup serial port
    try {
      serial_port_.setPort("/dev/ttyUSB0");  // Adjust the port as needed (e.g., /dev/ttyUSB0 on Linux)
      serial_port_.setBaudrate(500000);        // Must match the baud rate in your Arduino code
      serial::Timeout timeout = serial::Timeout::simpleTimeout(1000);
      serial_port_.setTimeout(timeout);
      serial_port_.open();

      if (serial_port_.isOpen()) {
        RCLCPP_INFO(this->get_logger(), "Serial port opened successfully");
      }
    } catch (serial::IOException &e) {
      RCLCPP_ERROR(this->get_logger(), "Unable to open serial port: %s", e.what());
    }

    // Create a timer to poll the serial port periodically.
    timer_ = this->create_wall_timer(100ms, std::bind(&ArduinoInterface::read_serial, this));
  }

private:
  void command_callback(const std_msgs::msg::String::SharedPtr msg)
  {
    std::string command = msg->data;
    if (serial_port_.isOpen()) {
      // Write the command followed by a newline to match the Arduino's readStringUntil('\n')
      serial_port_.write(command + "\n");
      RCLCPP_INFO(this->get_logger(), "Sent command: '%s'", command.c_str());
    }
  }

  void read_serial()
  {
    if (serial_port_.available()) {
      std::string line = serial_port_.readline(65536, "\n");
      if (!line.empty()) {
        std_msgs::msg::String status_msg;
        status_msg.data = line;
        publisher_->publish(status_msg);
        RCLCPP_INFO(this->get_logger(), "Received: %s", line.c_str());
      }
    }
  }

  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher_;
  rclcpp::Subscription<std_msgs::msg::String>::SharedPtr subscription_;
  rclcpp::TimerBase::SharedPtr timer_;
  serial::Serial serial_port_;
};

int main(int argc, char * argv[])
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<ArduinoInterface>());
  rclcpp::shutdown();
  return 0;
}
