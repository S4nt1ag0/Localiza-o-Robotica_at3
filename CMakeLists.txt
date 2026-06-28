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
  scripts/record_localization.sh
  scripts/generate_hector_map.sh
  scripts/generate_gmapping_map.sh
  scripts/run_mapping.sh
  scripts/localize_hector_map.sh
  scripts/localize_gmapping_map.sh
  scripts/run_amcl_localization.sh
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)

install(DIRECTORY config launch maps
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
)
