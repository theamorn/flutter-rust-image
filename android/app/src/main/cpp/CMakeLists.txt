cmake_minimum_required(VERSION 3.10)
project(live_effects C)

add_library(live_effects SHARED live_effects.c)
target_compile_options(live_effects PRIVATE -O2)
