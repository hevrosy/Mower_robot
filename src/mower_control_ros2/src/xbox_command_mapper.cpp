#include "rclcpp/rclcpp.hpp"
#include "std_msgs/msg/string.hpp"
#include "sensor_msgs/msg/joy.hpp"
#include <algorithm>
#include <iomanip>
#include <sstream>

class XboxCommandMapper : public rclcpp::Node
{
public:
  XboxCommandMapper() : Node("xbox_command_mapper"), motor_speed_(50),
                        lt_was_pressed_(false), rt_was_pressed_(false)
  {
    command_pub_ = create_publisher<std_msgs::msg::String>("arduino_commands", 10);
    joy_sub_ = create_subscription<sensor_msgs::msg::Joy>(
      "joy", 10, std::bind(&XboxCommandMapper::joy_callback, this, std::placeholders::_1));
  }

private:
  void joy_callback(const sensor_msgs::msg::Joy::SharedPtr msg)
  {
    bool button_x = msg->buttons[3];
    bool button_a = msg->buttons[0];
    bool button_b = msg->buttons[1];
    bool button_y = msg->buttons[4];

    bool lt_pressed = msg->axes[5] < 1.0;
    bool rt_pressed = msg->axes[4] < 1.0;

    auto command = std_msgs::msg::String();
    bool should_publish = false;

    if (button_x) {
      command.data = "MOTO0000";
      should_publish = true;
    } else if (button_a) {
      command.data = "MOTO0001";
      should_publish = true;
    } else if (button_b) {
      command.data = "MDIR0000";
      should_publish = true;
    } else if (lt_pressed && !lt_was_pressed_) {
      motor_speed_ = std::max(0, motor_speed_ - 1000);
      command.data = "MRPM" + format_speed(motor_speed_);
      should_publish = true;
    } else if (rt_pressed && !rt_was_pressed_) {
      motor_speed_ = std::min(4000, motor_speed_ + 1000);
      command.data = "MRPM" + format_speed(motor_speed_);
      should_publish = true;
    } else if (button_y) {
      command.data = "MDIR0001";
      should_publish = true;
    }

    // Update previous states
    lt_was_pressed_ = lt_pressed;
    rt_was_pressed_ = rt_pressed;

    if (should_publish) {
      command_pub_->publish(command);
      RCLCPP_INFO(get_logger(), "Sending command: '%s'", command.data.c_str());
    }
  }

  std::string format_speed(int speed)
  {
    std::ostringstream oss;
    oss << std::setw(3) << std::setfill('0') << speed;
    return oss.str();
  }

  int motor_speed_;
  bool lt_was_pressed_;
  bool rt_was_pressed_;
  rclcpp::Subscription<sensor_msgs::msg::Joy>::SharedPtr joy_sub_;
  rclcpp::Publisher<std_msgs::msg::String>::SharedPtr command_pub_;
};

int main(int argc, char *argv[])
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<XboxCommandMapper>());
  rclcpp::shutdown();
  return 0;
}
