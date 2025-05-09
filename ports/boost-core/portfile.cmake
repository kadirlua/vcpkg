# Automatically generated by scripts/boost/generate-ports.ps1

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO boostorg/core
    REF boost-${VERSION}
    SHA512 4d5b8ca8fdecd97d3d4028498495c6d75f21d7e128335347acf4a18621f27ac05f5d07174e1bc4086121ae9334cbe12553df5ec32038b49e4c1166bae74c0334
    HEAD_REF master
)

set(FEATURE_OPTIONS "")
boost_configure_and_install(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS ${FEATURE_OPTIONS}
)
