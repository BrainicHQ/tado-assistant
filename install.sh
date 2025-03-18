#!/bin/bash
echo "WARNING: This script requires root privileges. Please review the script before proceeding."
# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Please run this script as root or with sudo privileges."
   exit 1
fi

# 1. Install Dependencies
install_dependencies() {
    echo "Installing dependencies..."

    # Initialize the variables
    NEED_CURL=0
    NEED_JQ=0

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
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
                    sudo apt-get update
                fi
                [[ $NEED_CURL -eq 1 ]] && sudo apt-get install -y curl
                [[ $NEED_JQ -eq 1 ]] && sudo apt-get install -y jq
                ;;
            fedora|centos|rhel|ol)
                [[ $NEED_CURL ]] && sudo yum install -y curl
                [[ $NEED_JQ ]] && sudo yum install -y jq
                ;;
            arch|manjaro)
                [[ $NEED_CURL || $NEED_JQ ]] && sudo pacman -Sy
                [[ $NEED_CURL ]] && sudo pacman -S curl
                [[ $NEED_JQ ]] && sudo pacman -S jq
                ;;
            suse|opensuse*)
                [[ $NEED_CURL ]] && sudo zypper install curl
                [[ $NEED_JQ ]] && sudo zypper install jq
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

# 2. Set Environment Variables with Device Code Flow
set_env_variables() {
    echo "Setting up environment variables for multiple Tado accounts..."

    # Prompt for the number of accounts
    read -rp "Enter the number of Tado accounts: " NUM_ACCOUNTS

    # Initialize the env file with NUM_ACCOUNTS
    echo "export NUM_ACCOUNTS=$NUM_ACCOUNTS" > /etc/tado-assistant.env

    # Loop through each account for configuration
    i=1
    while [ "$i" -le "$NUM_ACCOUNTS" ]; do
        echo "Configuring account $i..."

        response=$(curl -s -X POST "https://login.tado.com/oauth2/device_authorize" \
            -d "client_id=1bb50063-6b0c-4d11-bd99-387f4a91cc46" \
            -d "scope=offline_access")
        if [ $? -ne 0 ]; then
            echo "Failed to initiate device code flow."
            exit 1
        fi

        device_code=$(echo "$response" | jq -r '.device_code')
        user_code=$(echo "$response" | jq -r '.user_code')
        verification_uri_complete=$(echo "$response" | jq -r '.verification_uri_complete')
        interval=$(echo "$response" | jq -r '.interval')
        expires_in=$(echo "$response" | jq -r '.expires_in')

        if [ -z "$device_code" ] || [ "$device_code" == "null" ]; then
            echo "Error: Failed to retrieve device code."
            exit 1
        fi

        echo "Please visit in your browser: $verification_uri_complete"
        echo "User code: $user_code"
        echo "Waiting for authentication..."

        start_time=$(date +%s)
        while true; do
            current_time=$(date +%s)
            if (( current_time - start_time > expires_in )); then
                echo "Authentication timed out."
                exit 1
            fi

            token_response=$(curl -s -X POST "https://login.tado.com/oauth2/token" \
                -d "client_id=1bb50063-6b0c-4d11-bd99-387f4a91cc46" \
                -d "device_code=$device_code" \
                -d "grant_type=urn:ietf:params:oauth:grant-type:device_code")

            error=$(echo "$token_response" | jq -r '.error // empty')
            if [ "$error" == "authorization_pending" ]; then
                sleep "$interval"
                continue
            elif [ -n "$error" ]; then
                echo "Error: $error"
                exit 1
            else
                refresh_token=$(echo "$token_response" | jq -r '.refresh_token')
                break
            fi
        done

        read -rp "Enter CHECKING_INTERVAL for account $i (default: 15): " CHECKING_INTERVAL
        read -rp "Enter MAX_OPEN_WINDOW_DURATION for account $i (in seconds): " MAX_OPEN_WINDOW_DURATION
        read -rp "Enable geofencing check for account $i? (true/false, default: true): " ENABLE_GEOFENCING
        read -rp "Enable log for account $i? (true/false, default: false): " ENABLE_LOG
        read -rp "Enter log file path for account $i (default: /var/log/tado-assistant.log): " LOG_FILE

        escaped_refresh_token=$(printf '%s' "$refresh_token" | sed "s/'/'\\\\''/g")
        {
            echo "export TADO_REFRESH_TOKEN_$i='$escaped_refresh_token'"
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
    cp "$(dirname "$0")/tado-assistant.sh" "$SCRIPT_PATH"
    chmod +x $SCRIPT_PATH

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        SERVICE_CONTENT="[Unit]
Description=Tado Assistant Service

[Service]
ExecStart=$SCRIPT_PATH
User=$(whoami)
Restart=always

[Install]
WantedBy=multi-user.target"

        echo "$SERVICE_CONTENT" | sudo tee /etc/systemd/system/tado-assistant.service > /dev/null
        sudo systemctl enable tado-assistant.service
        sudo systemctl restart tado-assistant.service

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