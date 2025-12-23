#!/bin/bash
echo "WARNING: This script requires root privileges. Please review the script before proceeding."
# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "Please run this script as root or with sudo privileges."
   exit 1
fi

ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(eval echo "~${ORIGINAL_USER}" 2>/dev/null)
if [ -z "$ORIGINAL_HOME" ] || [ "$ORIGINAL_HOME" == "~${ORIGINAL_USER}" ]; then
    ORIGINAL_HOME="/root"
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

escape_squote() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

proxy_platform_supported() {
    local os
    local arch

    os=$(uname -s)
    case "$os" in
        Linux) PROXY_OS="linux" ;;
        Darwin) PROXY_OS="darwin" ;;
        *) return 1 ;;
    esac

    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) PROXY_ARCH="x86_64" ;;
        arm64|aarch64) PROXY_ARCH="arm64" ;;
        i386|i686) PROXY_ARCH="i386" ;;
        *) return 1 ;;
    esac

    return 0
}

proxy_asset_name() {
    echo "tado-api-proxy_${PROXY_OS}_${PROXY_ARCH}.tar.gz"
}

get_latest_proxy_version() {
    if [ -n "$TADO_API_PROXY_VERSION" ]; then
        echo "$TADO_API_PROXY_VERSION"
        return 0
    fi

    local version
    version=$(curl -fsSL https://api.github.com/repos/s1adem4n/tado-api-proxy/releases/latest | jq -r '.tag_name')
    if [ -z "$version" ] || [ "$version" = "null" ]; then
        return 1
    fi
    echo "$version"
}

verify_proxy_checksum() {
    local version="$1"
    local asset="$2"
    local file_path="$3"
    local version_no_v="${version#v}"
    local checksum_url="https://github.com/s1adem4n/tado-api-proxy/releases/download/${version}/tado-api-proxy_${version_no_v}_checksums.txt"
    local checksum_file=""
    local expected=""
    local actual=""

    if command -v sha256sum &> /dev/null; then
        checksum_file=$(mktemp)
        curl -fsSL "$checksum_url" -o "$checksum_file" || rm -f "$checksum_file"
        if [ -f "$checksum_file" ]; then
            expected=$(grep " ${asset}$" "$checksum_file" | awk '{print $1}')
            rm -f "$checksum_file"
            if [ -n "$expected" ]; then
                actual=$(sha256sum "$file_path" | awk '{print $1}')
            fi
        fi
    elif command -v shasum &> /dev/null; then
        checksum_file=$(mktemp)
        curl -fsSL "$checksum_url" -o "$checksum_file" || rm -f "$checksum_file"
        if [ -f "$checksum_file" ]; then
            expected=$(grep " ${asset}$" "$checksum_file" | awk '{print $1}')
            rm -f "$checksum_file"
            if [ -n "$expected" ]; then
                actual=$(shasum -a 256 "$file_path" | awk '{print $1}')
            fi
        fi
    fi

    if [ -n "$expected" ] && [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
        echo "Checksum verification failed for ${asset}."
        return 1
    fi

    return 0
}

download_proxy_binary() {
    proxy_platform_supported || return 1

    local version
    local asset
    local url
    local tmpdir
    local bin_path

    version=$(get_latest_proxy_version) || return 1
    asset=$(proxy_asset_name)
    url="https://github.com/s1adem4n/tado-api-proxy/releases/download/${version}/${asset}"
    tmpdir=$(mktemp -d)

    if ! curl -fsSL "$url" -o "${tmpdir}/${asset}"; then
        rm -rf "$tmpdir"
        return 1
    fi

    if ! verify_proxy_checksum "$version" "$asset" "${tmpdir}/${asset}"; then
        rm -rf "$tmpdir"
        return 1
    fi

    if ! tar -xzf "${tmpdir}/${asset}" -C "$tmpdir"; then
        rm -rf "$tmpdir"
        return 1
    fi

    bin_path=$(find "$tmpdir" -maxdepth 2 -type f -name "tado-api-proxy" | head -n1)
    if [ -z "$bin_path" ]; then
        rm -rf "$tmpdir"
        return 1
    fi

    cp "$bin_path" /usr/local/bin/tado-api-proxy
    chmod 755 /usr/local/bin/tado-api-proxy
    rm -rf "$tmpdir"
    return 0
}

ensure_proxy_binary() {
    if [ -x /usr/local/bin/tado-api-proxy ]; then
        return 0
    fi

    echo "Downloading tado-api-proxy binary..."
    download_proxy_binary
}

install_chromium_linux() {
    local distro=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        distro=$ID
    fi

    echo "Installing Chromium (this may take a few minutes)..."

    case $distro in
        debian|ubuntu|raspbian)
            DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends chromium || \
                DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends chromium-browser
            ;;
        fedora|centos|rhel|ol)
            if command -v dnf &> /dev/null; then
                dnf install -y chromium
            else
                yum install -y chromium
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm chromium
            ;;
        suse|opensuse*)
            zypper install -y chromium
            ;;
        alpine)
            apk add --no-cache chromium
            ;;
        *)
            return 1
            ;;
    esac
}

detect_chrome_executable() {
    if [ -n "$TADO_PROXY_CHROME_EXECUTABLE" ] && [ -x "$TADO_PROXY_CHROME_EXECUTABLE" ]; then
        echo "$TADO_PROXY_CHROME_EXECUTABLE"
        return 0
    fi

    if [[ "$OSTYPE" == "linux"* ]]; then
        for candidate in chromium chromium-browser google-chrome google-chrome-stable brave-browser; do
            if command -v "$candidate" &> /dev/null; then
                command -v "$candidate"
                return 0
            fi
        done

        if install_chromium_linux; then
            for candidate in chromium chromium-browser; do
                if command -v "$candidate" &> /dev/null; then
                    command -v "$candidate"
                    return 0
                fi
            done
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        local mac_candidates=(
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            "/Applications/Chromium.app/Contents/MacOS/Chromium"
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
        )
        for candidate in "${mac_candidates[@]}"; do
            if [ -x "$candidate" ]; then
                echo "$candidate"
                return 0
            fi
        done
    fi

    read -rp "Enter Chrome/Chromium executable path: " CHROME_EXECUTABLE
    if [ -n "$CHROME_EXECUTABLE" ] && [ -x "$CHROME_EXECUTABLE" ]; then
        echo "$CHROME_EXECUTABLE"
        return 0
    fi

    return 1
}

in_container() {
    if [ -f /.dockerenv ]; then
        return 0
    fi
    if [ -r /proc/1/cgroup ] && grep -qE '(docker|lxc|containerd|kubepods)' /proc/1/cgroup; then
        return 0
    fi
    return 1
}

setup_systemd_proxy_service() {
    local service_file="/etc/systemd/system/tado-api-proxy@.service"

    if [ ! -f "$service_file" ]; then
        cat <<EOF > "$service_file"
[Unit]
Description=Tado API Proxy (Account %i)
After=network.target

[Service]
EnvironmentFile=/etc/tado-api-proxy/account%i.env
ExecStart=/usr/local/bin/tado-api-proxy
User=${ORIGINAL_USER}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload 1>&2
}

setup_launchd_proxy_service() {
    local account_index=$1
    local wrapper_path="/usr/local/bin/tado-api-proxy-account${account_index}"
    local launch_agents_dir="${ORIGINAL_HOME}/Library/LaunchAgents"
    local plist_path="${launch_agents_dir}/com.user.tadoapiproxy.account${account_index}.plist"

    mkdir -p "$launch_agents_dir"

    cat <<EOF > "$wrapper_path"
#!/bin/bash
set -a
. /etc/tado-api-proxy/account${account_index}.env
set +a
exec /usr/local/bin/tado-api-proxy
EOF
    chmod 755 "$wrapper_path"

    cat <<EOF > "$plist_path"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.tadoapiproxy.account${account_index}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${wrapper_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

    sudo -u "$ORIGINAL_USER" launchctl unload "$plist_path" &> /dev/null || true
    sudo -u "$ORIGINAL_USER" launchctl load "$plist_path" 1>&2
}

setup_proxy_binary() {
    local account_index=$1
    local chrome_executable="$2"
    local default_port=$((8080 + account_index - 1))
    local listen_addr=""
    local host_port=""
    local email=""
    local password=""
    local proxy_data_root="/var/lib/tado-api-proxy"
    local proxy_data_dir="${proxy_data_root}/account${account_index}"
    local proxy_env_dir="/etc/tado-api-proxy"
    local proxy_env_file="${proxy_env_dir}/account${account_index}.env"

    read -rp "Enter tado account email for account ${account_index}: " email
    read -rsp "Enter tado account password for account ${account_index}: " password
    printf "\n" >&2
    read -rp "Enter proxy host port for account ${account_index} (default: ${default_port}): " host_port
    host_port=${host_port:-$default_port}
    if in_container; then
        listen_addr="0.0.0.0:${host_port}"
    else
        listen_addr="127.0.0.1:${host_port}"
    fi

    mkdir -p "$proxy_data_dir" "$proxy_env_dir"
    chown -R "$ORIGINAL_USER" "$proxy_data_dir"

    local email_escaped
    local password_escaped
    local chrome_escaped
    local listen_escaped
    local token_path
    local cookies_path

    email_escaped=$(escape_squote "$email")
    password_escaped=$(escape_squote "$password")
    chrome_escaped=$(escape_squote "$chrome_executable")
    listen_escaped=$(escape_squote "$listen_addr")
    token_path="${proxy_data_dir}/token.json"
    cookies_path="${proxy_data_dir}/cookies.json"

    cat <<EOF > "$proxy_env_file"
EMAIL='${email_escaped}'
PASSWORD='${password_escaped}'
LISTEN_ADDR='${listen_escaped}'
TOKEN_PATH='${token_path}'
COOKIES_PATH='${cookies_path}'
CHROME_EXECUTABLE='${chrome_escaped}'
HEADLESS='true'
EOF
    chown "$ORIGINAL_USER" "$proxy_env_file"
    chmod 600 "$proxy_env_file"

    if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
        setup_systemd_proxy_service
        systemctl enable --now "tado-api-proxy@${account_index}.service" 1>&2
    elif [[ "$OSTYPE" == "darwin"* ]] && command -v launchctl &> /dev/null; then
        setup_launchd_proxy_service "$account_index"
    else
        local log_file="/var/log/tado-api-proxy-account${account_index}.log"
        mkdir -p "$(dirname "$log_file")"
        (
            set -a
            . "$proxy_env_file"
            set +a
            nohup /usr/local/bin/tado-api-proxy >> "$log_file" 2>&1 &
        )
    fi

    printf '%s\n' "http://localhost:${host_port}"
}

# 2. Set Environment Variables (tado-api-proxy)
set_env_variables() {
    echo "Setting up environment variables for multiple Tado accounts..."

    # Prompt for the number of accounts
    read -rp "Enter the number of Tado accounts: " NUM_ACCOUNTS

    # Initialize the env file with NUM_ACCOUNTS
    echo "export NUM_ACCOUNTS=$NUM_ACCOUNTS" > /etc/tado-assistant.env

    local chrome_executable=""

    if ! ensure_proxy_binary; then
        echo "Failed to auto-setup tado-api-proxy. Ensure the binary can be downloaded."
        exit 1
    fi

    echo "Using proxy setup method: binary"
    echo "Checking for Chrome/Chromium (this may take a few minutes)..."

    chrome_executable=$(detect_chrome_executable) || true
    if [ -z "$chrome_executable" ]; then
        echo "Chrome/Chromium executable not found. Install Chrome/Chromium or set TADO_PROXY_CHROME_EXECUTABLE."
        exit 1
    fi

    # Loop through each account for configuration
    i=1
    while [ "$i" -le "$NUM_ACCOUNTS" ]; do
        echo "Configuring account $i..."

        proxy_output=$(setup_proxy_binary "$i" "$chrome_executable")
        if [ $? -ne 0 ]; then
            exit 1
        fi

        API_BASE_URL=""
        while IFS= read -r line; do
            line=${line%$'\r'}
            case "$line" in
                http://*|https://*)
                    API_BASE_URL="$line"
                    ;;
            esac
        done <<< "$proxy_output"

        if [ -z "$API_BASE_URL" ]; then
            echo "Failed to configure proxy for account $i."
            exit 1
        fi

        read -rp "Enter CHECKING_INTERVAL for account $i (default: 15): " CHECKING_INTERVAL
        read -rp "Enter MAX_OPEN_WINDOW_DURATION for account $i (in seconds, leave empty to use the Tado app default): " MAX_OPEN_WINDOW_DURATION
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

    if [[ "$OSTYPE" == "linux"* ]]; then
        if command -v systemctl &> /dev/null && [ -d /run/systemd/system ]; then
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
        elif command -v rc-update &> /dev/null && [ -d /etc/init.d ]; then
            cat <<'EOF' > /etc/init.d/tado-assistant
#!/sbin/openrc-run

command="/usr/local/bin/tado-assistant.sh"
command_background="yes"
pidfile="/run/tado-assistant.pid"
output_log="/var/log/tado-assistant.log"
error_log="/var/log/tado-assistant.log"

depend() {
    need net
}
EOF
            chmod +x /etc/init.d/tado-assistant
            rc-update add tado-assistant default || true
            rc-service tado-assistant restart || rc-service tado-assistant start || true
        else
            echo "No supported service manager found. Run $SCRIPT_PATH manually or set up your own service."
        fi
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
