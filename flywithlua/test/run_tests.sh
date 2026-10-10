#!/bin/sh
# Builds the mock X-Plane library and runs the Cinematic Views tests under LuaJIT.
# Needs a C compiler and luajit.
set -e
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/Resources/plugins/FlyWithLua/Scripts"
cc -shared -fPIC -O1 -o "$work/Resources/plugins/XPLM_64.so" "$here/mock_xplm.c"
cd "$work"
luajit "$here/run_tests.lua" "$here/../Cinematic_Views.lua" "$work"
