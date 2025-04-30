# ROS Metapackages Overview

This document provides an overview of the various ROS1 and ROS2 metapackages/variants and the packages they include. These bundles simplify the installation and management of related packages. Below is a detailed breakdown of the contents for each ROS version.

## Table of Contents

- [ROS Metapackages Overview](#ros-metapackages-overview)
  - [Table of Contents](#table-of-contents)
  - [ROS1 Metapackages Overview](#ros1-metapackages-overview)
    - [`ros_core`](#ros_core)
    - [`ros_base`](#ros_base)
    - [`viz`](#viz)
    - [`robot`](#robot)
    - [`perception`](#perception)
    - [`simulators`](#simulators)
    - [`desktop`](#desktop)
  - [ROS2 Variants Overview](#ros2-variants-overview)
    - [`ros_core` (ROS2)](#ros_core-ros2)
    - [`ros_base` (ROS2)](#ros_base-ros2)
    - [`desktop` (ROS2)](#desktop-ros2)
    - [`perception` (ROS2)](#perception-ros2)
    - [`simulation`](#simulation)
    - [`desktop_full`](#desktop_full)
  - [Notes on DDS](#notes-on-dds)
  - [References for DDS in ROS 2](#references-for-dds-in-ros-2)

## ROS1 Metapackages Overview

### `ros_core`

Installs the following packages:

- `catkin`
- `class_loader`
- `cmake_modules`
- `common_msgs`
- `gencpp`
- `geneus`
- `genlisp`
- `genmsg`
- `gennodejs`
- `genpy`
- `message_generation`
- `message_runtime`
- `pluginlib`
- `ros`
- `ros_comm`
- `rosbag_migration_rule`
- `rosconsole`
- `rosconsole_bridge`
- `roscpp_core`
- `rosgraph_msgs`
- `roslisp`
- `rospack`
- `std_msgs`
- `std_srvs`

### `ros_base`

Installs all the packages from `ros_core`, plus:

- `actionlib`
- `bond_core`
- `dynamic_reconfigure`
- `nodelet_core`

### `viz`

Installs all the packages from `ros_base`, plus:

- `rqt_common_plugins`
- `rqt_robot_plugins`
- `rviz`

### `robot`

Installs all the packages from `ros_base`, plus:

- `control_msgs`
- `diagnostics`
- `executive_smach`
- `filters`
- `geometry`
- `joint_state_publisher`
- `kdl_parser`
- `robot_state_publisher`
- `urdf`
- `urdf_parser_plugin`
- `xacro`

### `perception`

Installs all the packages from `ros_base`, plus:

- `image_common`
- `image_pipeline`
- `image_transport_plugins`
- `laser_pipeline`
- `perception_pcl`
- `vision_opencv`

### `simulators`

Installs all the packages from `robot`, plus:

- `gazebo_ros_pkgs`
- `rqt_common_plugins`
- `rqt_robot_plugins`
- `stage_ros`

### `desktop`

Installs all the packages from `robot`, all the packages from `viz`, plus:

- `angles`
- `common_tutorials`
- `geometry_tutorials`
- `joint_state_publisher_gui`
- `ros_tutorials`
- `roslint`
- `urdf_tutorial` (not included in Kinetic)
- `visualization_tutorials`

## ROS2 Variants Overview

### `ros_core` (ROS2)

Installs the following packages:

- `ament_cmake`
- `ament_cmake_auto`
- `ament_cmake_gtest`
- `ament_cmake_gmock`
- `ament_cmake_pytest`
- `ament_cmake_ros`
- `ament_index_cpp`
- `ament_index_python`
- `ament_lint_auto`
- `ament_lint_common`
- `rcl_lifecycle`
- `rclcpp`
- `rclcpp_action`
- `rclcpp_lifecycle`
- `rclpy`
- `rosidl_default_generators`
- `rosidl_default_runtime`
- `ros_environment`
- `common_interfaces`
- `launch`
- `launch_testing`
- `launch_testing_ament_cmake`
- `launch_xml`
- `launch_yaml`
- `launch_ros`
- `launch_testing_ros`
- `ros2launch`
- `ros2cli_common_extensions`
- `sros2`
- `sros2_cmake`
- `class_loader`
- `pluginlib`

### `ros_base` (ROS2)

Installs all the packages from `ros_core`, plus:

- `rosbag2`
- `geometry2`
- `kdl_parser`
- `urdf`
- `robot_state_publisher`

### `desktop` (ROS2)

Installs all the packages from `ros_base`, plus:

- `angles`
- `depthimage_to_laserscan`
- `joy`
- `pcl_conversions`
- `rviz2`
- `rviz_default_plugins`
- `teleop_twist_joy`
- `teleop_twist_keyboard`
- `action_tutorials_cpp`
- `action_tutorials_interfaces`
- `action_tutorials_py`
- `composition`
- `demo_nodes_cpp`
- `demo_nodes_cpp_native`
- `demo_nodes_py`
- `dummy_map_server`
- `dummy_robot_bringup`
- `dummy_sensors`
- `image_tools`
- `intra_process_demo`
- `lifecycle`
- `logging_demo`
- `pendulum_control`
- `pendulum_msgs`
- `quality_of_service_demo_cpp`
- `quality_of_service_demo_py`
- `topic_monitor`
- `tlsf`
- `tlsf_cpp`
- `examples_rclcpp_minimal_action_client`
- `examples_rclcpp_minimal_action_server`
- `examples_rclcpp_minimal_client`
- `examples_rclcpp_minimal_composition`
- `examples_rclcpp_minimal_publisher`
- `examples_rclcpp_minimal_service`
- `examples_rclcpp_minimal_subscriber`
- `examples_rclcpp_minimal_timer`
- `examples_rclcpp_multithreaded_executor`
- `examples_rclpy_executors`
- `examples_rclpy_minimal_action_client`
- `examples_rclpy_minimal_action_server`
- `examples_rclpy_minimal_client`
- `examples_rclpy_minimal_publisher`
- `examples_rclpy_minimal_service`
- `examples_rclpy_minimal_subscriber`
- `rqt_common_plugins`
- `turtlesim`

### `perception` (ROS2)

Installs all the packages from `ros_base`, plus:

- `image_common`
- `image_pipeline`
- `image_transport_plugins`
- `laser_filters`
- `laser_geometry`
- `perception_pcl`
- `vision_opencv`

### `simulation`

Installs all the packages from `ros_base`, plus:

- `ros_ign_bridge`
- `ros_ign_gazebo`
- `ros_ign_image`
- `ros_ign_interfaces`

### `desktop_full`

Installs all the packages from `desktop`, all the packages from `perception`, and all the packages from `simulation`, plus:

- `ros_ign_gazebo_demos`

For more information, visit the official [ROS1 Metapackages repository](https://github.com/ros/metapackages/) and [ROS2 Variants repository](https://github.com/ros2/variants/).

## Notes on DDS

FastRTPS (eProsima) is the default open-source DDS implementation in ROS 2. <br/>
CycloneDDS is another open-source DDS implementation recommended in many ROS 2 frameworks, such as Nav2 and MoveIt. <br/>
Installing CycloneDDS is beneficial for certain applications.<br/>
RTI DDS, on the other hand, is not open-source and is not required for this setup.<br/>
By setting RTI_NC_LICENSE_ACCEPTED=no, ([reference](https://stackoverflow.com/questions/56100217/how-to-accept-the-license-agreement-when-building-rti-connext-dds-5-3-1-with-doc)), we ensure that RTI DDS is not
installed during execution of the command `rosdep update`.<br/>
The default ROS 2 RMW implementation is `rmw_fastrtps_cpp`.<br/>
The main difference between `rmw_fastrtps_cpp` and `rmw_fastrtps_dynamic_cpp` is  that `rmw_fastrtps_dynamic_cpp` uses
introspection type support at runtime to determine serialization/deserialization mechanisms, while `rmw_fastrtps_cpp`
uses pre-generated mappings for each message type at build time.<br/>
You can change the DDS implementation used by ROS 2 by modifying the value of the `RMW_IMPLEMENTATION` environment
variable (e.g., to `rmw_cyclonedds_cpp`).<br/>
To check which DDS implementation is in use, run the command `ros2 doctor --report`.<br/>

## References for DDS in ROS 2

- General DDS implementations in ROS 2: [https://docs.ros.org/en/${ROS_DISTRO}/Installation/DDS-Implementations.html](https://docs.ros.org/en/\${ROS_DISTRO}/Installation/DDS-Implementations.html)
- About middleware vendors: [https://docs.ros.org/en/${ROS_DISTRO}/Concepts/About-Different-Middleware-Vendors.html](https://docs.ros.org/en/\${ROS_DISTRO}/Concepts/About-Different-Middleware-Vendors.html)
- Fast DDS with ROS 2: [https://fast-dds.docs.eprosima.com/en/latest/fastdds/ros2/ros2.html](https://fast-dds.docs.eprosima.com/en/latest/fastdds/ros2/ros2.html)
- ROS REP 2000: [https://www.ros.org/reps/rep-2000.html](https://www.ros.org/reps/rep-2000.html)