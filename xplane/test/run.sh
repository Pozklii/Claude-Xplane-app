#!/bin/sh
# Tests cinematic_view.lua outside X-Plane: builds a mock XPLM library, then
# runs the script under a simulated FlyWithLua with the SDK (ffi) and without
# it (fallback), plus the camera math checks. Needs luajit and a C compiler.
set -e
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../FlyWithLua/Scripts/cinematic_view.lua"
work=$(mktemp -d)
mkdir -p "$work/Resources/plugins" "$work/ffi" "$work/fallback" "$work/math"
cc -shared -fPIC -O1 -o "$work/Resources/plugins/XPLM_64.so" "$here/xplm_mock.c"
cd "$work"
TMPDIR_TEST="$work/ffi" luajit "$here/harness.lua" "$script" ffi
TMPDIR_TEST="$work/fallback" luajit "$here/harness.lua" "$script" fallback
TMPDIR_TEST="$work/math" luajit "$here/mathtest.lua" "$script"
echo "Test files left in $work"
