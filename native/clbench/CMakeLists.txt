cmake_minimum_required(VERSION 3.22.1)
project(clbench C)
add_library(clbench SHARED clbench.c)
target_link_options(clbench PRIVATE "-Wl,-z,max-page-size=16384")
