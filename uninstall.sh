#!/bin/bash
echo "WARNING: This script requires root privileges. Please review the script before proceeding."

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Please run this script as root or with sudo privileges."
   exit 1
fi

# Enable error tracing for debug purposes
set -x

ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(eval echo "~${ORIGINAL_USER}" 2>/dev/null)
if [ -z "$ORIGINAL_HOME" ] || [ "$ORIGINAL_HOME" == "~${ORIGINAL_USER}" ]; then
    ORIGINAL_HOME="/root"
fi

remove_proxy_services() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if systemctl list-unit-files | grep -q "tado-api-proxy@"; then
            for env_file in /etc/tado-api-proxy/account*.env; do
                [ -f "$env_file" ] || continue
                account_id=$(basename "$env_file" | sed -e 's/^account//' -e 's/\.env$//')
                systemctl disable --now "tado-api-proxy@${account_id}.service" || true
            done
            rm -f /etc/systemd/system/tado-api-proxy@.service
            systemctl daemon-reload
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        for plist in "$ORIGINAL_HOME/Library/LaunchAgents"/com.user.tadoapiproxy.account*.plist; do
            [ -f "$plist" ] || continue
            sudo -u "$ORIGINAL_USER" launchctl unload "$plist" || true
            rm -f "$plist"
        done
        rm -f /usr/local/bin/tado-api-proxy-account*
    fi
}

remove_proxy_files() {
    rm -rf /etc/tado-api-proxy /var/lib/tado-api-proxy
    rm -f /usr/local/bin/tado-api-proxy
}

# Remove the service
remove_service() {
    echo "Removing the service..."

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        systemctl stop tado-assistant.service
        systemctl disable tado-assistant.service
        rm -f /etc/systemd/system/tado-assistant.service
        systemctl daemon-reload
        systemctl reset-failed

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        launchctl unload ~/Library/LaunchAgents/com.user.tadoassistant.plist
        rm -f ~/Library/LaunchAgents/com.user.tadoassistant.plist
    fi
}

# Remove the persistent environment file (which now stores tokens and configuration)
remove_env_variables() {
    echo "Removing environment file /etc/tado-assistant.env..."
    if [ -f /etc/tado-assistant.env ]; then
        rm -f /etc/tado-assistant.env
    else
        echo "/etc/tado-assistant.env not found."
    fi
}

# Remove the main script
remove_script() {
    echo "Removing the script..."
    if [ -f /usr/local/bin/tado-assistant.sh ]; then
        rm -f /usr/local/bin/tado-assistant.sh
    else
        echo "/usr/local/bin/tado-assistant.sh not found."
    fi
}

remove_service
remove_env_variables
remove_script
remove_proxy_services
remove_proxy_files
echo "Tado Assistant has been successfully uninstalled!"
