# Copyright (C) 2014 Tai Chi Minh Ralph Eastwood.
# Redistribution and use of this file is allowed according to the terms of the MIT license.
# For details see the COPYRIGHT file distributed with Flymir LuaDist.
# Please note that the package source code is licensed under its own license.

project ( rima )
cmake_minimum_required ( VERSION 2.8 )

include ( cmake/dist.cmake )
include ( lua )

find_package(COIN REQUIRED)

include_directories( ${COIN_INCLUDE_DIRS} )
install_lua_module ( rima_clp_core c/rima_clp_core.cpp c/rima_solver_tools.cpp LINK ${COIN_LIBRARIES} )
install_lua_module ( rima lua/rima.lua )

install ( DIRECTORY lua/rima DESTINATION ${INSTALL_LMOD}/rima COMPONENT Runtime )
install_data ( README.md LICENSE AUTHORS )

install_test ( lua/rima-test.lua )
install_test ( lua/rima-test-solvers.lua )
install_test ( lua/tests/ )
install_test ( lua/test/ )
install_test ( lua/examples/ )
