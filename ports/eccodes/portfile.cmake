vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO ecmwf/eccodes
    REF "${VERSION}"
    SHA512 14b75d100fbf4ee68b62406051b49b341567a346477f36c88a7fa59e5f1b7d5b0886d82c222ebe8b66809dcdb4a3bebe96da418694ac759e5c18ad904467624c
    HEAD_REF develop
    PATCHES
        use-system-ecbuild.patch
)

if(VCPKG_HOST_IS_WINDOWS)
    vcpkg_acquire_msys(MSYS_ROOT)
    set(ENV{PATH} "${MSYS_ROOT}/usr/bin;$ENV{PATH}")
endif()

vcpkg_find_acquire_program(PERL)
get_filename_component(PERL_PATH "${PERL}" DIRECTORY)
vcpkg_add_to_path("${PERL_PATH}")

vcpkg_find_acquire_program(PYTHON3)
get_filename_component(PYTHON3_PATH "${PYTHON3}" DIRECTORY)
get_filename_component(PYTHON3_ROOT "${PYTHON3_PATH}" DIRECTORY)
vcpkg_add_to_path("${PYTHON3_PATH}")

set(ECCODES_OPTIONS
    -DBUILD_TESTING=OFF
    -DCMAKE_DISABLE_FIND_PACKAGE_Git=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_Jasper=ON
    -DENABLE_MEMFS=ON
    -DENABLE_INSTALL_ECCODES_DEFINITIONS=ON
    -DENABLE_INSTALL_ECCODES_SAMPLES=ON
    -DENABLE_EXTRA_TESTS=OFF
    -DENABLE_JPG=ON
    -DENABLE_JPG_LIBJASPER=OFF
    -DENABLE_JPG_LIBOPENJPEG=ON
    -DENABLE_AEC=OFF
    -DENABLE_FORTRAN=OFF
    -DENABLE_NETCDF=OFF
    -DENABLE_PNG=OFF
    -DREPLACE_TPL_ABSOLUTE_PATHS=OFF
    -DENABLE_ECCODES_THREADS=OFF
    -DENABLE_ECCODES_OMP_THREADS=OFF
)

# vcpkg all-features CI can select both thread features together.
# ecCodes treats them as alternative implementations, so prefer OpenMP when
# both are requested instead of hard-failing configuration.
if("openmp-threads" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS
        -DENABLE_ECCODES_OMP_THREADS=ON
    )
elseif("threads" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS
        -DENABLE_ECCODES_THREADS=ON
    )
endif()

if("aec" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS
        -DENABLE_AEC=ON
    )
endif()

if("fortran" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS -DENABLE_FORTRAN=ON)
endif()

if("netcdf" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS
        -DENABLE_NETCDF=ON
    )

    # ecCodes links grib_to_netcdf against NetCDF::NetCDF_C, but on static builds
    # that target can miss part of the transitive closure on some triplets.
    file(APPEND "${SOURCE_PATH}/tools/CMakeLists.txt" [=[

if(TARGET grib_to_netcdf AND NOT BUILD_SHARED_LIBS)
  find_package(HDF5 COMPONENTS C HL QUIET)
  find_package(tinyxml2 CONFIG QUIET)
  find_package(CURL QUIET)

  if(TARGET hdf5::hdf5_hl)
    target_link_libraries(grib_to_netcdf hdf5::hdf5_hl)
  endif()
  if(TARGET HDF5::HDF5)
    target_link_libraries(grib_to_netcdf HDF5::HDF5)
  elseif(HDF5_FOUND AND DEFINED HDF5_LIBRARIES)
    target_link_libraries(grib_to_netcdf ${HDF5_LIBRARIES})
  endif()

  if(TARGET tinyxml2::tinyxml2)
    target_link_libraries(grib_to_netcdf tinyxml2::tinyxml2)
  endif()

  if(TARGET CURL::libcurl)
    target_link_libraries(grib_to_netcdf CURL::libcurl)
  elseif(CURL_FOUND AND DEFINED CURL_LIBRARIES)
    target_link_libraries(grib_to_netcdf ${CURL_LIBRARIES})
  endif()
endif()
]=])
endif()

if("png" IN_LIST FEATURES)
    list(APPEND ECCODES_OPTIONS
        -DENABLE_PNG=ON
    )
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
        -Decbuild_DIR=${CURRENT_HOST_INSTALLED_DIR}/share/ecbuild
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

function(eccodes_move_tools_from_bin bin_dir tools_dir)
    if(NOT EXISTS "${bin_dir}")
        return()
    endif()

    file(GLOB _entries "${bin_dir}/*")
    foreach(_entry IN LISTS _entries)
        if(IS_DIRECTORY "${_entry}")
            continue()
        endif()

        get_filename_component(_name "${_entry}" NAME)
        if(_name MATCHES [[\.(dll|pdb|so(\..*)?|dylib)$]])
            continue()
        endif()

        file(MAKE_DIRECTORY "${tools_dir}")
        file(RENAME "${_entry}" "${tools_dir}/${_name}")
    endforeach()
endfunction()

eccodes_move_tools_from_bin("${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/tools/${PORT}")
eccodes_move_tools_from_bin("${CURRENT_PACKAGES_DIR}/debug/bin" "${CURRENT_PACKAGES_DIR}/tools/${PORT}/debug")


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

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

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

# Upstream installs both release and debug helper scripts named codes_config.
# Scrub every installed copy so post-build validation does not find build or
# package paths if a triplet lays them out slightly differently.
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

# Installing ecCodes definitions/samples can leave empty data directories on
# Linux (for example definitions/metar/stations). vcpkg rejects empty installed
# directories, so remove all of them after every install/post-process step.
function(eccodes_remove_empty_directories root_dir)
    if(NOT IS_DIRECTORY "${root_dir}")
        return()
    endif()

    foreach(_pass RANGE 1 20)
        file(GLOB_RECURSE _all_entries LIST_DIRECTORIES true "${root_dir}/*")
        set(_removed_empty_dir FALSE)

        foreach(_entry IN LISTS _all_entries)
            if(IS_DIRECTORY "${_entry}")
                file(GLOB _children "${_entry}/*")
                if(NOT _children)
                    file(REMOVE_RECURSE "${_entry}")
                    set(_removed_empty_dir TRUE)
                endif()
            endif()
        endforeach()

        if(NOT _removed_empty_dir)
            break()
        endif()
    endforeach()
endfunction()

eccodes_remove_empty_directories("${CURRENT_PACKAGES_DIR}")
