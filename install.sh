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

        # Initialize the variables
        NEED_CURL=0
        NEED_JQ=0

        case $DISTRO in
            debian|ubuntu)
                if [[ $NEED_CURL -eq 1 ]] || [[ $NEED_JQ -eq 1 ]]; then
                            sudo apt-get update
                        fi
                        [[ $NEED_CURL -eq 1 ]] && sudo apt-get install -y curl
                        [[ $NEED_JQ -eq 1 ]] && sudo apt-get install -y jq
                        ;;
            fedora|centos|rhel)
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
    local max_attempts=3
    local attempt=0

    while (( attempt < max_attempts )); do
        echo "Setting up environment variables..."

        read -p "Enter TADO_USERNAME: " TADO_USERNAME
        read -p "Enter TADO_PASSWORD: " TADO_PASSWORD
        read -p "Enter CHECKING_INTERVAL (default: 15): " CHECKING_INTERVAL
        read -p "Enable log? (true/false, default: false): " ENABLE_LOG
        read -p "Enter log file path (default: /var/log/tado-assistant.log): " LOG_FILE

        cat > /etc/tado-assistant.env <<EOL
export TADO_USERNAME=$TADO_USERNAME
export TADO_PASSWORD=$TADO_PASSWORD
export CHECKING_INTERVAL=${CHECKING_INTERVAL:-10}
export ENABLE_LOG=${ENABLE_LOG:-false}
export LOG_FILE=${LOG_FILE:-/var/log/tado-assistant.log}
EOL

        # Validate the credentials
        validate_credentials && break

        (( attempt++ ))
        if (( attempt < max_attempts )); then
            echo "Please try again. ($((max_attempts - attempt)) attempts left)"
        fi
    done

    if (( attempt == max_attempts )); then
        echo "Maximum attempts reached. Exiting."
        exit 1
    fi

    chmod 644 /etc/tado-assistant.env
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

# 4. Validate credentials
validate_credentials() {
    local response
    local error_message

    response=$(curl -s -X POST "https://auth.tado.com/oauth/token" \
        -d "client_id=public-api-preview" \
        -d "client_secret=4HJGRffVR8xb3XdEUQpjgZ1VplJi6Xgw" \
        -d "grant_type=password" \
        -d "password=${TADO_PASSWORD}" \
        -d "scope=home.user" \
        -d "username=${TADO_USERNAME}")

    # Check if curl command was successful
    if [ $? -ne 0 ]; then
        echo "Error connecting to the API."
        return 1
    fi

    TOKEN=$(echo "$response" | jq -r '.access_token')
    error_message=$(echo "$response" | jq -r '.error_description // empty')

    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
        echo "Login error. ${error_message:-Check the username/password!}"
        return 1
    fi
    return 0
}

# 5. Update the script
update_script() {
    echo "Checking for updates..."

    # Navigate to the directory of the script
    cd "$(dirname "$0")" || exit

    # Fetch the latest changes from the remote repository
    git fetch

    # Check if the local version is behind the remote version
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
        # If they're different, stop the service
        echo "Stopping the Tado Assistant service..."
        sudo systemctl stop tado-assistant.service

        # Pull the latest changes
        git pull
        echo "Script updated successfully!"

        # Recheck dependencies
        install_dependencies

        # Replace the service script with the updated version
        echo "Updating the script used by the service..."
        cp tado-assistant.sh /usr/local/bin/tado-assistant.sh
        chmod +x /usr/local/bin/tado-assistant.sh

        # Restart the service
        echo "Starting the Tado Assistant service..."
        sudo systemctl start tado-assistant.service
    else
        echo "You already have the latest version of the script."
    fi
}

# Check if the script is run with the --update flag
if [[ "$1" == "--update" ]]; then
    # Call the update function
    update_script
    exit 0
fi

install_dependencies
set_env_variables
validate_credentials
setup_service
echo "Tado Assistant has been successfully installed and started!"