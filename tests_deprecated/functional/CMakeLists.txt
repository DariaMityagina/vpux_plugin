#
# Copyright (C) 2022 Intel Corporation.
# SPDX-License-Identifier: Apache-2.0
#

# TODO: It is disabled for Windows due dependency on Boost.fs
if (UNIX)
    set(TARGET_NAME "KmbFunctionalTests")

    find_package(Boost REQUIRED COMPONENTS system filesystem)

    addIeTargetTest(
            NAME ${TARGET_NAME}
            ROOT
                ${CMAKE_CURRENT_SOURCE_DIR}/kmb_tests
            ADDITIONAL_SOURCE_DIRS
                ${CMAKE_CURRENT_SOURCE_DIR}/base
                ${CMAKE_CURRENT_SOURCE_DIR}/common
            INCLUDES
                ${CMAKE_CURRENT_SOURCE_DIR}/base
                ${CMAKE_CURRENT_SOURCE_DIR}/common
                ${IE_MAIN_VPUX_PLUGIN_SOURCE_DIR}/include
            DEFINES
                -DKMB_ALPHA_TESTS_DATA_PATH="${MODELS_PATH}"
            LINK_LIBRARIES
                IE::IESharedTests
                IE::funcTestUtils
                vpux_utils
                IE::ngraph
                IE::ngraph_reference
                kmb_utils
                Boost::filesystem
                common_tests_helpers
            LINK_LIBRARIES_WHOLE_ARCHIVE
                kmbTestData
            LABELS  # Must be the last parameter. Reason: see description comment for addIeTargetTest().
                KMB
                VPU
    )

    add_dependencies(${TARGET_NAME} ${VPUX_PLUGIN_TARGET})

    enable_warnings_as_errors(${TARGET_NAME})

    install(TARGETS ${TARGET_NAME}
            RUNTIME DESTINATION tests
            COMPONENT ${VPUX_TESTS_COMPONENT}
            EXCLUDE_FROM_ALL
    )

    # TODO: Remove duplication E#31024
    install(TARGETS ${TARGET_NAME}
            RUNTIME DESTINATION tests
            COMPONENT tests
            EXCLUDE_FROM_ALL
    )
endif()
