#!/bin/bash

# set -euo pipefail

package="xwayland"

if apt-cache policy "${package}" 2>/dev/null | grep --quiet 'Candidate:'; then
    sudo apt-get install --yes --no-install-recommends "${package}"
else
    echo "Warning: Package '${package}' is missing in apt sources"
fi

script="set_xauth_cookies"
qualified_script="/usr/local/bin/${script}"

echo "Installing script \"${qualified_script}\" ..."

if ! command -v xauth &>/dev/null; then
    echo "Error: xauth is not installed. Please install it before running this script."
    exit 1
fi

sudo tee "${qualified_script}" >/tmp/${script}.log <<'EOF'
#!/bin/bash

#set -euo pipefail

xauth_file="/tmp/.cookies.xauth"
xauth_log_file="/tmp/xauth_cookies.log"

set_empty_xauth_file() {
  touch "${xauth_file}"
  chmod a+r "${xauth_file}"
}

# Remove any existing X11 cookie file to ensure clean state
[ -e "${xauth_file}" ] && rm -f "${xauth_file}"


echo "Generating cookies at '$(date)' for DISPLAY=${DISPLAY:-<unset>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>}" >> "${xauth_log_file}"

# Check if running under Wayland, which does not use X11 cookies, or DISPLAY is unset, meaning no graphical session
# available. Create empty file for compatibility.
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -z "${DISPLAY:-}" ]; then
  set_empty_xauth_file
  exit 0
fi

# Attempt to generate cookies for multiple displays (in case of :0, :1, etc.)
for display in $(who | awk '{print $2}' | grep -oE ':[0-9]+'); do
    if [[ "${display}" =~ ^:[0-9]+$ ]]; then
        echo "Processing DISPLAY=${display}" >> "${xauth_log_file}"
        xauth_list="$(xauth nlist "${display}" | sed -e 's/^..../ffff/')"

        if [ -n "${xauth_list}" ]; then
            echo "${xauth_list}" | xauth -f "${xauth_file}" nmerge - 2>/dev/null
        fi
    fi
done

if [ -s "${xauth_file}" ];then
    # Ensure the cookie file is readable.
    chmod a+r "${xauth_file}"
else
    # No X11 cookies found for the current DISPLAY; create empty file to avoid errors.
    set_empty_xauth_file
fi
EOF

sudo chmod a+x "${qualified_script}"

autostart_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/autostart"
desktop_file="${autostart_dir}/${script}.desktop"

echo "Installing startup application \"${desktop_file}\""

mkdir -p "${autostart_dir}"
chmod 700 "${autostart_dir}"

cat >"${desktop_file}" <<EOF
[Desktop Entry]
Type=Application
Exec=/bin/bash -c '${qualified_script}'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=1
OnlyShowIn=GNOME;Unity;KDE;X-Cinnamon;MATE;XFCE;
Name=Set XAuth cookie
Comment=Generates X11 cookies for Docker GUI access (Wayland safe)
EOF

chmod 644 "${desktop_file}"

echo "Executing script \"${qualified_script}\" ..."
"${qualified_script}"
