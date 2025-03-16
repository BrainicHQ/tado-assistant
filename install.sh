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

# 2. Set Environment Variables
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
        echo "Requesting device code from tado°..."

        device_response=$(curl -s -X POST "https://login.tado.com/oauth2/device_authorize" \
            -d "client_id=1bb50063-6b0c-4d11-bd99-387f4a91cc46" \
            -d "scope=offline_access")

        device_code=$(echo "$device_response" | jq -r '.device_code')
        user_code=$(echo "$device_response" | jq -r '.user_code')
        verification_uri_complete=$(echo "$device_response" | jq -r '.verification_uri_complete')
        interval=$(echo "$device_response" | jq -r '.interval')
        expires_in=$(echo "$device_response" | jq -r '.expires_in')

        if [[ "$device_code" == "null" || -z "$device_code" ]]; then
            echo "Error: Unable to get device_code from tado°. Response:"
            echo "$device_response"
            exit 1
        fi

        echo "Account $i: Please open the following URL in your browser to authorize:"
        echo "  $verification_uri_complete"
        echo "User code (should auto-fill on that page): $user_code"
        echo "You have about $expires_in seconds to complete it before the code expires."

        # Wait for user to press enter (optional, but friendlier)
        read -rp "Press ENTER once you've approved access in the browser..."

        echo "Polling tado° for the token. Polling every $interval seconds until success..."

        access_token=""
        refresh_token=""
        pollStart=$(date +%s)

        # We poll for up to 'expires_in' seconds
        while :; do
            pollResponse=$(curl -s -X POST "https://login.tado.com/oauth2/token" \
                -d "client_id=1bb50063-6b0c-4d11-bd99-387f4a91cc46" \
                -d "device_code=$device_code" \
                -d "grant_type=urn:ietf:params:oauth:grant-type:device_code")

            errorVal=$(echo "$pollResponse" | jq -r '.error // empty')
            if [ "$errorVal" == "authorization_pending" ]; then
                # Not authorized yet; wait and poll again
                sleep "$interval"
            elif [ "$errorVal" == "access_denied" ]; then
                echo "You denied the request or took too long. Try again."
                exit 1
            else
                # Possibly success
                access_token=$(echo "$pollResponse" | jq -r '.access_token // empty')
                refresh_token=$(echo "$pollResponse" | jq -r '.refresh_token // empty')
                if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
                    echo "Received Access Token + Refresh Token!"
                    break
                fi
                # Some other error
                echo "Error from tado°: $pollResponse"
                exit 1
            fi

            # Timeout if user is not done in e.g. expires_in + 30
            now=$(date +%s)
            elapsed=$(( now - pollStart ))
            if [ "$elapsed" -ge $(( expires_in + 30 )) ]; then
                echo "Timed out waiting for user to authorize. Exiting."
                exit 1
            fi
        done

        # Ask user for optional config (interval, logs, etc.) as before:
        echo
        read -rp "Enter CHECKING_INTERVAL for account $i (default: 15): " CHECKING_INTERVAL
        read -rp "Enter MAX_OPEN_WINDOW_DURATION for account $i (in seconds): " MAX_OPEN_WINDOW_DURATION
        read -rp "Enable geofencing check for account $i? (true/false, default: true): " ENABLE_GEOFENCING
        read -rp "Enable log for account $i? (true/false, default: false): " ENABLE_LOG
        read -rp "Enter log file path for account $i (default: /var/log/tado-assistant.log): " LOG_FILE

        # Append the settings for each account to the env file, enclosing values in single quotes
        {
            echo "export TADO_ACCESS_TOKEN_$i='$access_token'"
            echo "export TADO_REFRESH_TOKEN_$i='$refresh_token'" 
            echo "export CHECKING_INTERVAL_$i='${CHECKING_INTERVAL:-15}'"
            echo "export MAX_OPEN_WINDOW_DURATION_$i='${MAX_OPEN_WINDOW_DURATION:-}'"
            echo "export ENABLE_GEOFENCING_$i='${ENABLE_GEOFENCING:-true}'"
            echo "export ENABLE_LOG_$i='${ENABLE_LOG:-true}'"
            echo "export LOG_FILE_$i='${LOG_FILE:-/var/log/tado-assistant.log}'"
        } >> /etc/tado-assistant.env

        i=$((i+1)) # Move to next account

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