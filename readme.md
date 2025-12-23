# 🏡 Tado Assistant: Your User-Friendly, Free Tado Auto-Assist Alternative

Discover the ultimate free alternative to Tado's Auto-Assist with Tado Assistant! This innovative utility enhances your
Tado smart home experience by seamlessly integrating with the Tado API, offering advanced features like mobile
device-based home state monitoring, open window detection in various zones, and customizable settings for open window
duration. Now with added support for multiple accounts, it's ideal for those managing several Tado devices across
different locations. Tado Assistant provides an efficient and cost-effective way to automate and optimize your home
environment. It's designed to be user-friendly and accessible, requiring minimal dependencies, making it a perfect
choice for both technical and non-technical users.

## 🚀 Key Features - Free Tado Auto Assist

- **Multi-Account Support**: Manage multiple Tado accounts seamlessly, perfect for users with devices in different
  locations.
- **State Monitoring**: Tado Assistant vigilantly tracks your home's status (HOME or AWAY) in real-time, offering a free
  alternative to Tado's Auto-Assist feature.
- **Smart Adjustments**: Detects discrepancies, such as no devices at home but the state is set to HOME, and adjusts
  accordingly.
- **Open Window Detection**: Recognizes open windows in different zones and activates the appropriate mode.
- **Customizable Open Window Duration**: Set your preferred duration for the 'Open Window' detection feature, allowing
  for personalized energy-saving adjustments.

## ⚠️ **Disclaimer**

This project is an independent initiative and is not affiliated, endorsed, or sponsored by Tado GmbH. All trademarks and
logos mentioned are the property of their respective owners. Please use this software responsibly and at your own risk.

## 🛠 Prerequisites

- A Unix-based system (Linux distributions or macOS).
- `git` installed to clone the repository.
- Root or sudo privileges for the installation script.
- `curl` and `jq` (Don't worry, our installer will help you set these up if they're not present).
- Chrome/Chromium installed (required for the tado-api-proxy binary).
- Ensure both scripts (`install.sh` and `tado-assistant.sh`) reside in the same directory.

## 📥 Installation

1. Clone this repository to dive in:

   ```bash
   git clone https://github.com/BrainicHQ/tado-assistant.git
   ```

   ```bash
   cd tado-assistant
   ```

2. Grant the installation script the necessary permissions:

   ```bash
   chmod +x install.sh
   ```

3. Kick off the installation with root or sudo privileges:

   ```bash 
   sudo ./install.sh
   ```

During the installation, the script will:

- Set up the required dependencies.
- Configure additional settings, including setting the checking interval and the maximum duration for the 'Open Window' detection feature.
- Auto-setup tado-api-proxy (binary) and configure a base URL per account.
- Initialize `tado-assistant.sh` as a background service.
- Introduce a new configuration option for the 'Open Window' feature. You will be prompted to enter the maximum
  duration (in seconds) that the system should wait before resuming normal operation after an open window is detected.
  You can specify a custom duration or leave it empty to use the default duration set in the Tado app.

## 🐳 Docker Installation

Tado Assistant can run as a Docker container in interactive mode to configure accounts and connect to your proxy.

1. **Pull the Docker Image:**
   Pull the latest version of Tado Assistant from Docker Hub:

   ```bash
   docker pull brainic/tado-assistant
   ```

2. **Run the Docker Container in Interactive Mode:**

   Run the container with an interactive terminal so you can provide the proxy base URL during setup:
   ```bash
   docker run -it --name tado-assistant --restart=always -e NUM_ACCOUNTS=1 brainic/tado-assistant
   ```

   Once the configuration is complete, you can detach from the container (using Ctrl+P followed by Ctrl+Q) or stop the container if needed.

3. **Docker Logs:**
   To check the logs of your Tado Assistant Docker container, use:

   ```bash
   docker logs tado-assistant
   ```

4. **Stopping and Removing the Container:**
   When you need to stop and remove the container, use the following commands:

   ```bash
   docker stop tado-assistant
   docker rm tado-assistant
   ```

This Docker setup offers a straightforward way to deploy Tado Assistant without the need for manual environment setup on
your host system.

Note: When running Tado Assistant inside Docker, the installer downloads the proxy binary and starts it in the container
alongside the assistant.
On systems without systemd/launchd, Tado Assistant will start the proxy in the background using the per-account env file.

## 🔌 tado-api-proxy

To bypass the public API rate limits, Tado Assistant routes all API calls through
[tado-api-proxy](https://github.com/s1adem4n/tado-api-proxy). The proxy authenticates via the browser OAuth client and
applies its own access token to each request.

When using the binary setup, `install.sh` downloads the proxy to `/usr/local/bin/tado-api-proxy` and manages one service
per account (`tado-api-proxy@N` on Linux or a LaunchAgent on macOS).

Quick setup overview:

1. Let `install.sh` auto-setup the proxy binary.
2. The installer sets `TADO_API_BASE_URL_n` automatically (default `http://localhost:8080`).
3. Restart the Tado Assistant service if you change any proxy settings manually.

For multiple accounts, run one proxy per account on different ports and set a different `TADO_API_BASE_URL_n` value for
each.

## 🔄 Updating

To ensure you're running the latest version of Tado Assistant, follow these steps:

1. Navigate to the `tado-assistant` directory:

    ```bash
    cd path/to/tado-assistant
    ```

2. To update normally, run the installation script with the `--update` flag:

    ```bash
    sudo ./install.sh --update
    ```

   This will check for the latest version of the script, update any dependencies if necessary, and restart the service.

3. If you need to force an update (for instance, to revert local changes to the official version), use
   the `--force-update` flag:

    ```bash
    sudo ./install.sh --force-update
    ```

   This option will update Tado Assistant to the latest version from the repository, regardless of any local changes.
   It's useful for ensuring your script matches the official release.

### Note on Local Changes

- When updating, the script automatically detects and backs up any local modifications. These backups are stored as
  patch files, allowing you to restore your changes if needed.
- In case of conflicts during a normal update, the script will halt and prompt you to resolve these manually, ensuring
  your modifications are not unintentionally overwritten.

## 🔧 Configuration

Tado Assistant relies on tado-api-proxy for authentication and rate-limit bypass. Proxy credentials are stored in
`/etc/tado-api-proxy/accountN.env` and token data is stored under `/var/lib/tado-api-proxy/accountN`.
The following environment variables are stored in `/etc/tado-assistant.env`:

- `NUM_ACCOUNTS`: Number of Tado accounts you wish to manage. This should be set to the total number of accounts.
- `TADO_API_BASE_URL`: Global base URL for Tado API calls (default `http://localhost:8080`). Overridden by
  `TADO_API_BASE_URL_n` when set.

For each account (replace `n` with the account number, e.g., 1, 2, 3, ...):

- `TADO_API_BASE_URL_n`: Base URL for Tado API calls. Default is `http://localhost:8080`.
- `CHECKING_INTERVAL_n`: Frequency (in seconds) for home state checks for the nth account. Default is every 15 seconds.
- `ENABLE_GEOFENCING_n`: Toggle geofencing check for the nth account. Values: `true` or `false`. Default is `true`.
- `ENABLE_LOG_n`: Toggle logging for the nth account. Values: `true` or `false`. Default is `false`.
- `LOG_FILE_n`: Destination for the log file for the nth account. Default is `/var/log/tado-assistant.log`.
- `MAX_OPEN_WINDOW_DURATION_n`: Define the maximum duration (in seconds) for the 'Open Window' detection feature to be
  active for the nth account. Leave this field empty to use the default duration set in the Tado app.

Feel free to tweak these variables directly if needed. Ensure to adjust the variable suffix `n` to match the corresponding account number.

Optional installer overrides (set before running `install.sh`):

- `TADO_PROXY_CHROME_EXECUTABLE`: Path override to Chrome/Chromium for binary proxy setup.
- `TADO_API_PROXY_VERSION`: Proxy version tag (for example `v0.2.7`) to pin the binary download.

## 🔄 Usage

After successfully installing the Tado Assistant, it will run silently in the background, ensuring your home's
environment is always optimal. Here's how you can interact with it:

1. **Checking Service Status**:
    - **Linux**:
   ```bash
   sudo systemctl status tado-assistant.service
    ``` 
    - **macOS**:
   ```bash
   launchctl list | grep com.user.tadoassistant
    ``` 

2. **Manual Adjustments**: If you ever need to make manual adjustments to your Tado settings, simply use the Tado app.
   Tado Assistant will recognize these changes and adapt accordingly.

3. **Logs**: To understand what Tado Assistant is doing behind the scenes, refer to the logs. If logging is enabled, you
   can tail the log file for real-time updates:
    ```bash
    tail -f /var/log/tado-assistant.log
    ```

4. **Adjusting 'Open Window' Duration**: The 'Open Window' detection feature's duration can be customized to suit your
   preferences. To modify this setting:
    - Edit the `/etc/tado-assistant.env` file.
    - Locate the `MAX_OPEN_WINDOW_DURATION` variable.
    - Set its value to the desired number of seconds. For example, `MAX_OPEN_WINDOW_DURATION=300` for a 5-minute
      duration.
    - Save the changes and restart the service for them to take effect.
        - For Linux:
          ```bash
          sudo systemctl restart tado-assistant.service
          ```
        - For macOS:
          ```bash
          launchctl unload ~/Library/LaunchAgents/com.user.tadoassistant.plist
          launchctl load ~/Library/LaunchAgents/com.user.tadoassistant.plist
          ```
   This setting defines how long the system should wait before resuming normal operation after an open window is
   detected, allowing for energy-saving adjustments tailored to your needs.

Remember, Tado Assistant is designed to be hands-off. Once set up, it should require minimal interaction, letting you
enjoy a comfortable home environment without any fuss.

## 🌟 Running Tado Assistant Continuously

Ensuring Tado Assistant runs continuously is crucial for maintaining an optimal home environment. Here are some
cost-effective solutions for running the software 24/7, suitable for both technical and non-technical users.

### ☁️ Free Tier Cloud Services

Cloud services offer reliable and free solutions to run small-scale projects like Tado Assistant. Here are some popular
options:

#### AWS EC2

- **Amazon Web Services (AWS)** provides a free tier EC2 instance which is more than capable of handling small
  applications.
- [AWS EC2 Free Tier Guide](https://aws.amazon.com/free/)

#### Google Cloud Platform

- **Google Cloud Platform (GCP)** offers a free tier with a micro VM instance.
- [GCP Free Tier Guide](https://cloud.google.com/free/docs/free-cloud-features)

#### Microsoft Azure

- **Microsoft Azure** also provides a free tier with virtual machines.
- [Azure Free Tier Guide](https://azure.microsoft.com/en-us/free/)

### 🖥️ Raspberry Pi or Old Laptop/PC

For those who prefer a more hands-on approach or wish to utilize existing hardware:

#### Raspberry Pi

- A **Raspberry Pi** can be a cost-effective and energy-efficient server.
- [Setting up Tado Assistant on Raspberry Pi](https://www.raspberrypi.com/documentation/computers/getting-started.html)

#### Repurposed Old Laptop/PC

- Use an **old laptop or PC** as a dedicated server for Tado Assistant.
- Ensure it's configured to run the software on startup and adjust power settings for continuous operation.

## 📜 Logs

If you've enabled logging (`ENABLE_LOG=true`), you can peek into the log file (default
location: `/var/log/tado-assistant.log`) for real-time updates and messages.

## 🗑️ Uninstallation

You can uninstall using the provided script:

```bash
sudo ./uninstall.sh
```

This removes the assistant service, proxy services/containers, and proxy data under `/etc/tado-api-proxy` and
`/var/lib/tado-api-proxy`.

To manually uninstall:

1. Stop the service.
    - For Linux:
   ```bash 
   sudo systemctl stop tado-assistant.service
    ```
    - For macOS:
   ```bash 
   launchctl unload ~/Library/LaunchAgents/com.user.tadoassistant.plist
    ```

2. Remove the service configuration.
    - For Linux:
   ```bash 
   sudo rm /etc/systemd/system/tado-assistant.service
    ```
    - For macOS:
   ```bash 
   rm ~/Library/LaunchAgents/com.user.tadoassistant.plist
    ```

3. Remove the main script:
   ```bash 
   sudo rm /usr/local/bin/tado-assistant.sh
    ```

4. Remove the environment variables file:
   ```bash
   sudo rm /etc/tado-assistant.env
    ```

5. Optionally, uninstall `curl` and `jq` if they were installed by the script and are no longer needed.

## 🤝 Contributing

Your insights can make Tado Assistant even better! We welcome contributions. Please ensure your code aligns with the
project's ethos. Feel free to submit pull requests or open issues for suggestions, improvements, or bug reports.

## 🍕 Support

Love Tado Assistant? You can show your support by starring the repository, sharing it with others,
or [buying me a pizza](https://www.buymeacoffee.com/silviu). All contributions are greatly appreciated and help keep the
project running.

Alternatively, contributions to the codebase or documentation are also welcome. Every bit of help counts!
