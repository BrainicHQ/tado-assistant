#!/bin/bash
echo "WARNING: This script requires root privileges. Please review the script before proceeding."
# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Please run this script as root or with sudo privileges."
   exit 1
fi

DOCKER_USER=""
DOCKER_BIN=""
if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    DOCKER_USER="$SUDO_USER"
fi

# 1. Install Dependencies
install_dependencies() {
    echo "Installing dependencies..."

    # Initialize the variables
    NEED_CURL=0
    NEED_JQ=0

    if [[ "$OSTYPE" == "linux"* ]]; then
        # Detecting the distribution
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
        fi

        # Check if curl and jq are installed
        if ! command -v curl &> /dev/null; then
            NEED_CURL=1
        fi
        if ! command -v jq &> /dev/null; then
            NEED_JQ=1
        fi

        case $DISTRO in
            debian|ubuntu|raspbian)
                if [[ $NEED_CURL -eq 1 ]] || [[ $NEED_JQ -eq 1 ]]; then
                    apt-get update
                fi
                [[ $NEED_CURL -eq 1 ]] && apt-get install -y curl
                [[ $NEED_JQ -eq 1 ]] && apt-get install -y jq
                ;;
            fedora|centos|rhel|ol)
                [[ $NEED_CURL ]] && yum install -y curl
                [[ $NEED_JQ ]] && yum install -y jq
                ;;
            arch|manjaro)
                [[ $NEED_CURL || $NEED_JQ ]] && pacman -Sy
                [[ $NEED_CURL ]] && pacman -S curl
                [[ $NEED_JQ ]] && pacman -S jq
                ;;
            suse|opensuse*)
                [[ $NEED_CURL ]] && zypper install curl
                [[ $NEED_JQ ]] && zypper install jq
                ;;
            alpine)
                [[ $NEED_CURL -eq 1 ]] && apk add --no-cache curl
                [[ $NEED_JQ -eq 1 ]] && apk add --no-cache jq
                ;;
            *)
                echo "Unsupported Linux distribution"
                exit 1
                ;;
        esac

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! command -v brew &> /dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        if ! command -v curl &> /dev/null; then
            brew install curl
        fi
        if ! command -v jq &> /dev/null; then
            brew install jq
        fi
    else
        echo "Unsupported OS"
        exit 1
    fi
}

detect_docker_bin() {
    if [ -n "$DOCKER_BIN" ]; then
        return 0
    fi

    local bin=""
    bin=$(command -v docker 2>/dev/null) || true
    if [ -n "$bin" ]; then
        DOCKER_BIN="$bin"
        return 0
    fi

    for candidate in /usr/local/bin/docker /opt/homebrew/bin/docker /usr/bin/docker; do
        if [ -x "$candidate" ]; then
            DOCKER_BIN="$candidate"
            return 0
        fi
    done

    return 1
}

docker_cmd() {
    detect_docker_bin || return 1
    if [ -n "$DOCKER_USER" ] && [ "$DOCKER_USER" != "root" ]; then
        sudo -u "$DOCKER_USER" -H "$DOCKER_BIN" "$@"
    else
        "$DOCKER_BIN" "$@"
    fi
}

docker_available() {
    detect_docker_bin
}

docker_running() {
    docker_cmd info &> /dev/null
}

docker_container_exists() {
    local name="$1"
    docker_cmd ps -a --filter "name=^/${name}$" --format '{{.Names}}' | grep -qx "$name"
}

docker_container_port() {
    local name="$1"
    docker_cmd port "$name" 8080/tcp 2>/dev/null | head -n1 | awk -F: '{print $NF}'
}

setup_proxy_container() {
    local account_index=$1
    local proxy_name="tado-api-proxy-${account_index}"
    local proxy_data_root="/var/lib/tado-api-proxy"
    local proxy_data_dir="${proxy_data_root}/account${account_index}"
    local proxy_env_dir="/etc/tado-api-proxy"
    local proxy_env_file="${proxy_env_dir}/account${account_index}.env"
    local default_port=$((8080 + account_index - 1))
    local host_port=""
    local base_url=""
    local email=""
    local password=""

    if docker_container_exists "$proxy_name"; then
        read -rp "Proxy container ${proxy_name} already exists. Recreate? (true/false, default: false): " RECREATE_PROXY
        RECREATE_PROXY=${RECREATE_PROXY:-false}
        if [ "$RECREATE_PROXY" != "true" ]; then
            docker_cmd start "$proxy_name" &> /dev/null || true
            host_port=$(docker_container_port "$proxy_name")
            if [ -n "$host_port" ]; then
                echo "http://localhost:${host_port}"
                return 0
            fi
            echo "Could not detect port mapping for ${proxy_name}."
            read -rp "Enter tado-api-proxy base URL for account ${account_index} (default: http://localhost:${default_port}): " base_url
            base_url=${base_url:-http://localhost:${default_port}}
            echo "$base_url"
            return 0
        fi
        docker_cmd rm -f "$proxy_name" &> /dev/null
    fi

    read -rp "Enter tado account email for account ${account_index}: " email
    read -rsp "Enter tado account password for account ${account_index}: " password
    printf "\n"
    read -rp "Enter proxy host port for account ${account_index} (default: ${default_port}): " host_port
    host_port=${host_port:-$default_port}

    mkdir -p "$proxy_data_dir" "$proxy_env_dir"
    chown -R 1000:1000 "$proxy_data_dir"

    printf "EMAIL=%s\nPASSWORD=%s\n" "$email" "$password" > "$proxy_env_file"
    chmod 600 "$proxy_env_file"

    if ! docker_cmd run -d \
        --name "$proxy_name" \
        --restart unless-stopped \
        -p "${host_port}:8080" \
        -v "${proxy_data_dir}:/config" \
        --env-file "$proxy_env_file" \
        ghcr.io/s1adem4n/tado-api-proxy:latest; then
        echo "Failed to start ${proxy_name}. Please check Docker and try again."
        return 1
    fi

    echo "http://localhost:${host_port}"
}

# 2. Set Environment Variables (tado-api-proxy)
set_env_variables() {
    echo "Setting up environment variables for multiple Tado accounts..."

    # Prompt for the number of accounts
    read -rp "Enter the number of Tado accounts: " NUM_ACCOUNTS

    # Initialize the env file with NUM_ACCOUNTS
    echo "export NUM_ACCOUNTS=$NUM_ACCOUNTS" > /etc/tado-assistant.env

    local auto_setup_proxy=false
    if docker_available; then
        if docker_running; then
            read -rp "Auto-setup tado-api-proxy containers with Docker? (true/false, default: true): " auto_setup_proxy
            auto_setup_proxy=${auto_setup_proxy:-true}
        else
            echo "Docker is installed but the daemon is not running. Skipping auto-setup."
        fi
    else
        echo "Docker is not available. Skipping auto-setup."
    fi

    # Loop through each account for configuration
    i=1
    while [ "$i" -le "$NUM_ACCOUNTS" ]; do
        echo "Configuring account $i..."

        if [ "$auto_setup_proxy" == "true" ]; then
            API_BASE_URL=$(setup_proxy_container "$i") || exit 1
            if [ -z "$API_BASE_URL" ]; then
                echo "No proxy base URL provided for account $i."
                exit 1
            fi
        else
            read -rp "Enter tado-api-proxy base URL for account $i (default: http://localhost:8080): " API_BASE_URL
            API_BASE_URL=${API_BASE_URL:-http://localhost:8080}
        fi

        read -rp "Enter CHECKING_INTERVAL for account $i (default: 15): " CHECKING_INTERVAL
        read -rp "Enter MAX_OPEN_WINDOW_DURATION for account $i (in seconds): " MAX_OPEN_WINDOW_DURATION
        read -rp "Enable geofencing check for account $i? (true/false, default: true): " ENABLE_GEOFENCING
        read -rp "Enable log for account $i? (true/false, default: false): " ENABLE_LOG
        read -rp "Enter log file path for account $i (default: /var/log/tado-assistant.log): " LOG_FILE

        escaped_api_base_url=$(printf '%s' "$API_BASE_URL" | sed "s/'/'\\\\''/g")
        {
            echo "export TADO_API_BASE_URL_$i='$escaped_api_base_url'"
            echo "export CHECKING_INTERVAL_$i='${CHECKING_INTERVAL:-15}'"
            echo "export MAX_OPEN_WINDOW_DURATION_$i='${MAX_OPEN_WINDOW_DURATION:-}'"
            echo "export ENABLE_GEOFENCING_$i='${ENABLE_GEOFENCING:-true}'"
            echo "export ENABLE_LOG_$i='${ENABLE_LOG:-false}'"
            echo "export LOG_FILE_$i='${LOG_FILE:-/var/log/tado-assistant.log}'"
        } >> /etc/tado-assistant.env

        i=$((i+1))
    done

    chmod 600 /etc/tado-assistant.env
}

# 3. Set up as Service
setup_service() {
    echo "Setting up the service..."

    SCRIPT_PATH="/usr/local/bin/tado-assistant.sh"
    CURRENT_SCRIPT_DIR="$(dirname "$(realpath "$0")")"
    SOURCE_SCRIPT="${CURRENT_SCRIPT_DIR}/tado-assistant.sh"

    # Only copy if the source and destination are different
    if [ "$(realpath "$SOURCE_SCRIPT")" != "$(realpath "$SCRIPT_PATH")" ]; then
        echo "Installing script to $SCRIPT_PATH"
        cp "$SOURCE_SCRIPT" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
    fi

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        SERVICE_CONTENT="[Unit]
Description=Tado Assistant Service

[Service]
ExecStart=$SCRIPT_PATH
User=root
Restart=always

[Install]
WantedBy=multi-user.target"

        echo "$SERVICE_CONTENT" > /etc/systemd/system/tado-assistant.service
        systemctl enable tado-assistant.service
        systemctl restart tado-assistant.service

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        LAUNCHD_CONTENT="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>Label</key>
    <string>com.user.tadoassistant</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>"

        echo "$LAUNCHD_CONTENT" > ~/Library/LaunchAgents/com.user.tadoassistant.plist
        launchctl load ~/Library/LaunchAgents/com.user.tadoassistant.plist
    fi
}

# 4. Update the script
update_script() {
    echo "Checking for updates..."

    # Determine the original user
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        ORIGINAL_USER="$SUDO_USER"
    else
        # If not running with sudo, use the current user
        ORIGINAL_USER=$(whoami)
    fi

    # Navigate to the directory of the script
    SCRIPT_DIR="$(dirname "$0")"
    cd "$SCRIPT_DIR" || exit

    local force_update=0
    if [[ "$1" == "--force" ]]; then
        force_update=1
    fi

    if [[ $force_update -eq 1 ]]; then
        echo "Force updating. Discarding any local changes..."
        sudo -u "$ORIGINAL_USER" git reset --hard
        sudo -u "$ORIGINAL_USER" git clean -fd
    else
        # Stash any local changes to avoid conflicts
        sudo -u "$ORIGINAL_USER" git stash --include-untracked
    fi

    # Pull the latest changes from the remote repository
    if ! sudo -u "$ORIGINAL_USER" git pull --ff-only; then
        echo "Error: Update failed. Trying to resolve..."
        # In case of failure, try a hard reset to the latest remote commit
        sudo -u "$ORIGINAL_USER" git fetch origin
        if ! sudo -u "$ORIGINAL_USER" git reset --hard origin/"$(sudo -u "$ORIGINAL_USER" git rev-parse --abbrev-ref HEAD)"; then
            echo "Error: Update failed and automatic resolution failed."
            exit 1
        fi
    fi

    if [[ $force_update -eq 0 ]]; then
        # Reapply stashed changes, if any
        sudo -u "$ORIGINAL_USER" git stash pop
    fi

    echo "Script updated successfully!"

    # Recheck dependencies
    install_dependencies

    # Replace the service script with the updated version
    echo "Updating the script used by the service..."
    cp tado-assistant.sh /usr/local/bin/tado-assistant.sh
    chmod +x /usr/local/bin/tado-assistant.sh

    # Restart the service based on the OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Starting the Tado Assistant service on Linux..."
        systemctl restart tado-assistant.service
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Starting the Tado Assistant service on macOS..."
        launchctl unload ~/Library/LaunchAgents/com.user.tadoassistant.plist
        launchctl load ~/Library/LaunchAgents/com.user.tadoassistant.plist
    else
        echo "Unsupported OS for service management."
        exit 1
    fi
}

# Check if the script is run with the --update or --force-update flag
if [[ "$1" == "--update" ]] || [[ "$1" == "--force-update" ]]; then
    # Call the update function with or without the force option
    update_script "$1"
    exit 0
fi

install_dependencies
set_env_variables
setup_service
echo "Tado Assistant has been successfully installed and started!"
