#!/bin/sh
# Start (or reuse) a nested Xephyr display for GUI tests: xephyr.sh start [:N] [WxH]; xephyr.sh stop [:N]
cmd=${1:-start}; d=${2:-:5}; geo=${3:-1280x800}; n=${d#:}
case $cmd in
start)
    if [ -S /tmp/.X11-unix/X$n ] && DISPLAY=$d xdpyinfo >/dev/null 2>&1; then exit 0; fi
    rm -f /tmp/.X$n-lock /tmp/.X11-unix/X$n
    setsid Xephyr $d -screen $geo -nolisten tcp -br -ac >/dev/null 2>&1 < /dev/null &
    i=0; while [ $i -lt 50 ]; do [ -S /tmp/.X11-unix/X$n ] && exit 0; sleep 0.1; i=$((i+1)); done
    echo "Xephyr $d failed to start" >&2; exit 1;;
stop) pkill -f "Xephyr $d " ;;
esac
