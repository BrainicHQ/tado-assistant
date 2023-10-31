# 🏡 Tado Assistant

Enhance your Tado experience! Tado Assistant is a powerful utility that seamlessly interfaces with the Tado API, allowing you to monitor and adjust your home's state based on mobile device presence and open window detection in different zones.

## 🚀 Features

-   **State Monitoring**: Continuously logs the state of your home (HOME or AWAY).
-   **Smart Adjustments**: Detects discrepancies, such as no devices at home but the state is set to HOME, and adjusts accordingly.
-   **Open Window Detection**: Recognizes open windows in different zones and activates the appropriate mode.

## ⚠️ **Disclaimer**

This project is an independent initiative and is not affiliated, endorsed, or sponsored by Tado GmbH. All trademarks and logos mentioned are the property of their respective owners. Please use this software responsibly and at your own risk.

## 🛠 Prerequisites

-   A Unix-based system (Linux distributions or macOS).
- `git` installed to clone the repository.
-   Root or sudo privileges for the installation script.
-   `curl` and `jq` (Don't worry, our installer will help you set these up if they're not present).
-   Ensure both scripts (`install.sh` and `tado-assistant.sh`) reside in the same directory.

## 📥 Installation

1.  Clone this repository to dive in:

    `git clone https://github.com/s1lviu/tado-assistant`

    `cd tado-assistant`

2.  Grant the installation script the necessary permissions:

    `chmod +x install.sh`

3.  Kick off the installation with root or sudo privileges:

    `sudo ./install.sh`


During the installation, the script will:

-   Set up the required dependencies.
-   Prompt you for your Tado credentials and other optional configurations.
-   Initialize `tado-assistant.sh` as a background service.

## 🔧 Configuration

Several environment variables drive the Tado Assistant:

-   `TADO_USERNAME`: Your Tado account username.
-   `TADO_PASSWORD`: Your Tado account password.
-   `CHECKING_INTERVAL`: Frequency (in seconds) for home state checks. Default is every 15 seconds.
-   `ENABLE_LOG`: Toggle logging. Values: `true` or `false`. Default is `false`.
-   `LOG_FILE`: Destination for the log file. Default is `/var/log/tado-assistant.log`.

These variables are stored in `/etc/tado-assistant.env`. Feel free to tweak them directly if needed.

## 🔄 Usage

After successfully installing the Tado Assistant, it will run silently in the background, ensuring your home's environment is always optimal. Here's how you can interact with it:

1. **Checking Service Status**:
   - **Linux**: `sudo systemctl status tado-assistant.service`
   - **macOS**: `launchctl list | grep com.user.tadoassistant`

2. **Manual Adjustments**: If you ever need to make manual adjustments to your Tado settings, simply use the Tado app. Tado Assistant will recognize these changes and adapt accordingly.

3. **Logs**: To understand what Tado Assistant is doing behind the scenes, refer to the logs. If logging is enabled, you can tail the log file for real-time updates:
    ```bash
    tail -f /var/log/tado-assistant.log
    ```

4. **Environment Variables**: To tweak the behavior of Tado Assistant, adjust the environment variables in `/etc/tado-assistant.env`. After making changes, restart the service for them to take effect.

Remember, Tado Assistant is designed to be hands-off. Once set up, it should require minimal interaction, letting you enjoy a comfortable home environment without any fuss.

## 📜 Logs

If you've enabled logging (`ENABLE_LOG=true`), you can peek into the log file (default location: `/var/log/tado-assistant.log`) for real-time updates and messages.
## 🗑️ Uninstallation

Currently, a dedicated uninstallation script is not provided. To manually uninstall:

1. Stop the service.
    - For Linux: `sudo systemctl stop tado-assistant.service`
    - For macOS: `launchctl unload ~/Library/LaunchAgents/com.user.tadoassistant.plist`

2. Remove the service configuration.
    - For Linux: `sudo rm /etc/systemd/system/tado-assistant.service`
    - For macOS: `rm ~/Library/LaunchAgents/com.user.tadoassistant.plist`

3. Remove the main script: `sudo rm /usr/local/bin/tado-assistant.sh`

4. Remove the environment variables file: `sudo rm /etc/tado-assistant.env`

5. Optionally, uninstall `curl` and `jq` if they were installed by the script and are no longer needed.

## 🤝 Contributing

Your insights can make Tado Assistant even better! We welcome contributions. Please ensure your code aligns with the project's ethos. Feel free to submit pull requests or open issues for suggestions, improvements, or bug reports.
