# Tado Assistant

Tado Assistant is a utility that interfaces with the Tado API to monitor and adjust the state of a home based on the presence of mobile devices and the detection of open windows in different zones of the home. This repository contains two main scripts:

1. `install.sh`: A script to set up the necessary dependencies and configure the environment.
2. `tado-assistant.sh`: The main script that interacts with the Tado API.

## Disclaimer

**This project is an independent work and is not affiliated, endorsed, or sponsored by Tado GmbH. All trademarks, service marks, trade names, trade dress, product names, and logos appearing in this project are the property of their respective owners. Use this software at your own risk. The author(s) of this project are not responsible for any potential harm, damage, or unintended behavior caused by the use of this software.**

## Prerequisites

- A Unix-based system (Linux distributions or macOS).
- Root or sudo privileges for the installation script.
- `curl` and `jq` (The installer will attempt to install these if they're not present).
- Both scripts (`install.sh` and `tado-assistant.sh`) should be in the same directory.

## Installation

1. Clone this repository or download the scripts to your local machine.
   ```bash
   git clone https://github.com/s1lviu/tado-assistant
   cd tado-assistant
   ```

2. Make the installation script executable:
   ```bash
   chmod +x install.sh
   ```

3. Run the installation script with root or sudo privileges:
   ```bash
   sudo ./install.sh
   ```

   During the installation:
    - The script will install necessary dependencies.
    - You will be prompted to enter your Tado username, password, and other optional configurations.
    - The main `tado-assistant.sh` script will be set up as a service.

## Usage

Once installed, the Tado Assistant will run as a service in the background. It will continuously check the home state based on the presence of mobile devices and open windows in different zones.

The service will:
- Log the state of the home (HOME or AWAY).
- Adjust the home state if it detects discrepancies (e.g., no devices at home but the state is HOME).
- Detect open windows in different zones and activate the appropriate mode.

## Configuration

The installation script sets up several environment variables which the main script uses:

- `TADO_USERNAME`: Your Tado account username.
- `TADO_PASSWORD`: Your Tado account password.
- `CHECKING_INTERVAL`: Interval (in seconds) at which the script checks the home state. Default is 10 seconds.
- `ENABLE_LOG`: Whether to log messages to a file. Values: `true` or `false`. Default is `false`.
- `LOG_FILE`: Path to the log file. Default is `/var/log/tado-assistant.log`.

These variables are saved in your shell's configuration file (e.g., `.bashrc` or `.zshrc`). You can modify them directly in the configuration file if needed.

## Logs

If logging is enabled (`ENABLE_LOG=true`), you can check the log file (default location: `/var/log/tado-assistant.log`) for messages and updates from the Tado Assistant.

## Uninstallation

Currently, a dedicated uninstallation script is not provided. To manually uninstall:

1. Stop the service.
    - For Linux: `sudo systemctl stop tado-assistant.service`
    - For macOS: `launchctl unload ~/Library/LaunchAgents/com.user.tadoassistant.plist`

2. Remove the service configuration.
    - For Linux: `sudo rm /etc/systemd/system/tado-assistant.service`
    - For macOS: `rm ~/Library/LaunchAgents/com.user.tadoassistant.plist`

3. Remove the main script: `sudo rm /usr/local/bin/tado-assistant.sh`

4. Optionally, uninstall `curl` and `jq` if they were installed by the script and are no longer needed.

## Contributing

Contributions are welcome! Please ensure your contributions adhere to good coding practices and respect the project's goals. Submit pull requests or open issues if you have suggestions, improvements, or bug reports.
