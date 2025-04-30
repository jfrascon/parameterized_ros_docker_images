#!/bin/bash

script="set_xauth_cookies"
qualified_script="/usr/local/bin/${script}"
autostart_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/autostart"
desktop_file="${autostart_dir}/${script}.desktop"
xauth_file="/tmp/.cookies.xauth"
xauth_log_file="/tmp/xauth_cookies.log"

echo "Uninstalling X11 Docker GUI cookie support..."

if [ -f "${qualified_script}" ]; then
    echo "Removing script '${qualified_script}'"
    sudo rm -f "${qualified_script}"
else
    echo "Script '${qualified_script}' not found."
fi

if [ -f "${desktop_file}" ]; then
    echo "Removing desktop file '${desktop_file}'"
    rm -f "${desktop_file}"
else
    echo "Desktop file '${desktop_file}' not found"
fi

if [ -f "${xauth_file}" ]; then
    echo "Removing X11 cookie file '${xauth_file}'"
    rm -f "${xauth_file}"
else
    echo "X11 cookie file '${xauth_file}' not found"
fi

if [ -f "${xauth_log_file}" ]; then
    echo "Removing X11 cookie log file '${xauth_log_file}'"
    rm -f "${xauth_log_file}"
else
    echo "X11 cookie log file '${xauth_log_file}' not found"
fi

echo "Uninstallation complete"
