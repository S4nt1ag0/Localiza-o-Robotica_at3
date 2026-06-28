cmake_minimum_required(VERSION 3.0.2)
project(localiza_o_robotica_at3)

find_package(catkin REQUIRED)

catkin_package()

catkin_install_python(PROGRAMS
  scripts/check_mapping_topics.py
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(PROGRAMS
  scripts/check_dependencies.sh
  scripts/start_simulation.sh
  scripts/record_mapping.sh
  scripts/generate_hector_map.sh
  scripts/generate_gmapping_map.sh
  scripts/run_mapping.sh
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY config launch
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
