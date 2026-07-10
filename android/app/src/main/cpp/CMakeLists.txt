cmake_minimum_required(VERSION 3.10.2)
project(native_render)

add_library(native_render SHARED native-render.cpp native-audio.cpp)

find_library(log-lib log)
find_library(android-lib android)
find_library(egl-lib EGL)
find_library(gles-lib GLESv2)
find_library(aaudio-lib aaudio)

target_link_libraries(native_render ${log-lib} ${android-lib} ${egl-lib} ${gles-lib} ${aaudio-lib})
