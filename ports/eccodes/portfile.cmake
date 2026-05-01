vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO ecmwf/eccodes
    REF "${VERSION}"
    SHA512 14b75d100fbf4ee68b62406051b49b341567a346477f36c88a7fa59e5f1b7d5b0886d82c222ebe8b66809dcdb4a3bebe96da418694ac759e5c18ad904467624c
    HEAD_REF develop
    PATCHES
        fix-netcdf-linkage.patch
)

if(VCPKG_HOST_IS_WINDOWS)
    vcpkg_acquire_msys(MSYS_ROOT)
    vcpkg_add_to_path(PREPEND "${MSYS_ROOT}/usr/bin")
endif()

vcpkg_find_acquire_program(PERL)
vcpkg_find_acquire_program(PYTHON3)
get_filename_component(PYTHON3_PATH "${PYTHON3}" DIRECTORY)
get_filename_component(PYTHON3_ROOT "${PYTHON3_PATH}" DIRECTORY)

vcpkg_check_features(OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
        aec ENABLE_AEC
        fortran ENABLE_FORTRAN
        netcdf ENABLE_NETCDF
        png ENABLE_PNG
)

if(VCPKG_TARGET_IS_WINDOWS)
    set(ECCODES_ENABLE_THREADS OFF)
else()
    set(ECCODES_ENABLE_THREADS ON)
endif()

set(ECCODES_OPTIONS
    ${FEATURE_OPTIONS}
    -DBUILD_TESTING=OFF
    -DCMAKE_DISABLE_FIND_PACKAGE_Git=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_Jasper=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_OpenMP=ON
    -DENABLE_MEMFS=ON
    -DENABLE_INSTALL_ECCODES_DEFINITIONS=ON
    -DENABLE_INSTALL_ECCODES_SAMPLES=ON
    -DENABLE_EXTRA_TESTS=OFF
    -DENABLE_JPG=ON
    -DENABLE_JPG_LIBJASPER=OFF
    -DENABLE_JPG_LIBOPENJPEG=ON
    -DREPLACE_TPL_ABSOLUTE_PATHS=OFF
    -DENABLE_ECCODES_THREADS=${ECCODES_ENABLE_THREADS}
    -DENABLE_ECCODES_OMP_THREADS=OFF
)

if(NOT "aec" IN_LIST FEATURES AND NOT "netcdf" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS -DCMAKE_DISABLE_FIND_PACKAGE_libaec=ON)
endif()

if(NOT "netcdf" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS -DCMAKE_DISABLE_FIND_PACKAGE_NetCDF=ON)
endif()

if(NOT "png" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS -DCMAKE_DISABLE_FIND_PACKAGE_PNG=ON)
endif()

# ecCodes uses try_run() for IEEE endianness probes. Those cannot execute when
# vcpkg cross-compiles, so preseed the known little-endian results.
if(VCPKG_CROSSCOMPILING)
    list(APPEND ECCODES_OPTIONS
        -DIEEE_LE_EXITCODE=0
        -DIEEE_BE_EXITCODE=1
    )
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        ${ECCODES_OPTIONS}
        -DCMAKE_REQUIRE_FIND_PACKAGE_ecbuild=ON
        -Decbuild_ROOT=${CURRENT_HOST_INSTALLED_DIR}
        -DPERL_EXECUTABLE=${PERL}
        -DPYTHON_EXECUTABLE=${PYTHON3}
        -DPython_EXECUTABLE=${PYTHON3}
        -DPython3_EXECUTABLE=${PYTHON3}
        -DPython_ROOT_DIR=${PYTHON3_ROOT}
        -DPython3_ROOT_DIR=${PYTHON3_ROOT}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/eccodes)
vcpkg_fixup_pkgconfig()

set(_eccodes_tool_names
    codes_bufr_filter
    codes_count
    codes_export_resource
    codes_info
    codes_parser
    codes_split_file
    bufr_compare
    bufr_copy
    bufr_count
    bufr_dump
    bufr_get
    bufr_index_build
    bufr_ls
    bufr_set
    grib2ppm
    grib_compare
    grib_copy
    grib_count
    grib_dump
    grib_filter
    grib_get
    grib_get_data
    grib_histogram
    grib_index_build
    grib_ls
    grib_set
    gts_compare
    gts_copy
    gts_count
    gts_dump
    gts_filter
    gts_get
    gts_ls
)

if("netcdf" IN_LIST FEATURES)
    list(APPEND _eccodes_tool_names grib_to_netcdf)
endif()

vcpkg_copy_tools(
    TOOL_NAMES ${_eccodes_tool_names}
    AUTO_CLEAN
)

foreach(_script IN ITEMS codes_config bufr_compare_dir bufr_filter)
    if(EXISTS "${CURRENT_PACKAGES_DIR}/bin/${_script}")
        file(MAKE_DIRECTORY "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
        file(RENAME
            "${CURRENT_PACKAGES_DIR}/bin/${_script}"
            "${CURRENT_PACKAGES_DIR}/tools/${PORT}/${_script}"
        )
    endif()

    if(EXISTS "${CURRENT_PACKAGES_DIR}/debug/bin/${_script}")
        file(REMOVE "${CURRENT_PACKAGES_DIR}/debug/bin/${_script}")
    endif()
endforeach()

vcpkg_copy_tool_dependencies("${CURRENT_PACKAGES_DIR}/tools/${PORT}")

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
    "${CURRENT_PACKAGES_DIR}/share/${PORT}/definitions/metar/stations"
)

function(eccodes_remove_dir_if_empty dir_path)
    if(NOT IS_DIRECTORY "${dir_path}")
        return()
    endif()

    file(GLOB _dir_entries "${dir_path}/*")
    if(NOT _dir_entries)
        file(REMOVE_RECURSE "${dir_path}")
    endif()
endfunction()

eccodes_remove_dir_if_empty("${CURRENT_PACKAGES_DIR}/bin")
eccodes_remove_dir_if_empty("${CURRENT_PACKAGES_DIR}/debug/bin")

function(eccodes_replace_prefix_in_file file_path from to)
    if(NOT EXISTS "${file_path}")
        return()
    endif()

    file(READ "${file_path}" _content)
    set(_updated "${_content}")
    string(REPLACE "${from}" "${to}" _updated "${_updated}")
    if(NOT _updated STREQUAL _content)
        file(WRITE "${file_path}" "${_updated}")
    endif()
endfunction()

function(eccodes_scrub_vcpkg_paths file_path)
    if(NOT EXISTS "${file_path}")
        return()
    endif()

    set(_prefix_pairs
        "${CURRENT_PACKAGES_DIR}" "@VCPKG_PACKAGES_DIR@"
        "${CURRENT_INSTALLED_DIR}" "@VCPKG_INSTALLED_DIR@"
        "${CURRENT_HOST_INSTALLED_DIR}" "@VCPKG_HOST_INSTALLED_DIR@"
        "${CURRENT_BUILDTREES_DIR}" "@VCPKG_BUILDTREES_DIR@"
        "${DOWNLOADS}" "@VCPKG_DOWNLOADS_DIR@"
    )

    list(LENGTH _prefix_pairs _pair_count)
    math(EXPR _last_index "${_pair_count} - 1")
    foreach(_index RANGE 0 ${_last_index} 2)
        math(EXPR _next_index "${_index} + 1")
        list(GET _prefix_pairs ${_index} _from)
        list(GET _prefix_pairs ${_next_index} _to)

        file(TO_CMAKE_PATH "${_from}" _from_cmake)
        string(REPLACE "/" "\\" _from_native "${_from_cmake}")

        eccodes_replace_prefix_in_file("${file_path}" "${_from_cmake}" "${_to}")
        eccodes_replace_prefix_in_file("${file_path}" "${_from_native}" "${_to}")
    endforeach()
endfunction()

set(_eccodes_files_to_scrub
    "${CURRENT_PACKAGES_DIR}/include/eccodes_config.h"
    "${CURRENT_PACKAGES_DIR}/include/eccodes_ecbuild_config.h"
    "${CURRENT_PACKAGES_DIR}/tools/${PORT}/codes_config"
    "${CURRENT_PACKAGES_DIR}/tools/${PORT}/debug/codes_config"
)

file(GLOB_RECURSE _eccodes_codes_config_files
    "${CURRENT_PACKAGES_DIR}/tools/${PORT}/*codes_config"
)
list(APPEND _eccodes_files_to_scrub ${_eccodes_codes_config_files})
list(REMOVE_DUPLICATES _eccodes_files_to_scrub)

foreach(_file IN LISTS _eccodes_files_to_scrub)
    eccodes_scrub_vcpkg_paths("${_file}")
endforeach()

file(INSTALL
    "${CMAKE_CURRENT_LIST_DIR}/usage"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}"
)

file(INSTALL
    "${SOURCE_PATH}/LICENSE"
    DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}"
    RENAME copyright
)
