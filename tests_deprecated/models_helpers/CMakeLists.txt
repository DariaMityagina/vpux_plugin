#
# Copyright (C) 2022 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
#

# Append "src/" prefix to MODELS_LST items
foreach(item IN LISTS MODELS_LST)
    list(APPEND MODELS_LST_UPDATED "src/${item}")
endforeach()
configure_file(get_model_repos.hpp.in ${CMAKE_CURRENT_BINARY_DIR}/get_model_repos.hpp @ONLY)

addIeTarget(
    NAME kmbTestData
    TYPE STATIC
    ROOT ${CMAKE_CURRENT_SOURCE_DIR}
    INCLUDES
        ${CMAKE_CURRENT_BINARY_DIR}
        $<TARGET_PROPERTY:IE::ieTestHelpers,INTERFACE_INCLUDE_DIRECTORIES>
        $<TARGET_PROPERTY:IE::ieTestHelpers,INTERFACE_SYSTEM_INCLUDE_DIRECTORIES>
    DEFINES
        INSTANTIATE_TESTS=1
        PUBLIC
        DATA_PATH=\"${DATA_PATH}\"
        MODELS_PATH=\"${MODELS_PATH}\"
)
