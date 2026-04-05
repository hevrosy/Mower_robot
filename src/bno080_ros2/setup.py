from setuptools import find_packages, setup

package_name = "bno080_ros2"

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        (
            "share/ament_index/resource_index/packages",
            [f"resource/{package_name}"],
        ),
        (f"share/{package_name}", ["package.xml"]),
    ],
    # ►► Key change: declare the CircuitPython libs so colcon pulls them in
    install_requires=[
        "setuptools>=65.0.0",            # build‑time helper already present
        "adafruit-blinka>=8.0.0",        # Pin I/O & bus abstractions
        "adafruit-circuitpython-bno08x>=2.0.0",  # BNO08x driver
    ],
    zip_safe=True,
    maintainer="rbt",
    maintainer_email="rbt@todo.todo",
    description="BNO080 ROS2 node using I2C on Raspberry Pi",
    license="MIT",
    python_requires=">=3.8",
    tests_require=["pytest"],
    entry_points={
        "console_scripts": [
            "imu_node = bno080_ros2.imu_node:main",
        ],
    },
)
