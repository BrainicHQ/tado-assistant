# 🏡 Tado Assistant: Your User-Friendly, Free Tado Auto-Assist Alternative

Discover the ultimate free alternative to Tado's Auto-Assist with Tado Assistant! This innovative utility enhances your
Tado smart home experience by seamlessly integrating with the Tado API, offering advanced features like mobile
device-based home state monitoring and open window detection in various zones. Ideal for those in search of a "Tado Auto
Assist free" solution, Tado Assistant provides an efficient and cost-effective way to automate and optimize your home
environment. It's designed to be user-friendly and accessible, requiring minimal dependencies, making it a perfect
choice for both technical and non-technical users.

## 🚀 Key Features - Free Tado Auto Assist

- **State Monitoring**: Tado Assistant vigilantly tracks your home's status (HOME or AWAY) in real-time, offering a free
  alternative to Tado's Auto-Assist feature.
- **Smart Adjustments**: Detects discrepancies, such as no devices at home but the state is set to HOME, and adjusts
  accordingly.
- **Open Window Detection**: Recognizes open windows in different zones and activates the appropriate mode.

## ⚠️ **Disclaimer**

This project is an independent initiative and is not affiliated, endorsed, or sponsored by Tado GmbH. All trademarks and
logos mentioned are the property of their respective owners. Please use this software responsibly and at your own risk.

## 🛠 Prerequisites

- A Unix-based system (Linux distributions or macOS).
- `git` installed to clone the repository.
- Root or sudo privileges for the installation script.
- `curl` and `jq` (Don't worry, our installer will help you set these up if they're not present).
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
- Prompt you for your Tado credentials and other optional configurations.
- Initialize `tado-assistant.sh` as a background service.

## 🔄 Updating

To ensure you're running the latest version of Tado Assistant:

1. Navigate to the `tado-assistant` directory:

    ```bash
    cd path/to/tado-assistant
    ```

2. Run the installation script with the `--update` flag:

    ```bash
    sudo ./install.sh --update
    ```

This will check for the latest version of the script, update any dependencies if necessary, and restart the service.

## 🔧 Configuration

Several environment variables drive the Tado Assistant:

- `TADO_USERNAME`: Your Tado account username.
- `TADO_PASSWORD`: Your Tado account password.
- `CHECKING_INTERVAL`: Frequency (in seconds) for home state checks. Default is every 15 seconds.
- `ENABLE_LOG`: Toggle logging. Values: `true` or `false`. Default is `false`.
- `LOG_FILE`: Destination for the log file. Default is `/var/log/tado-assistant.log`.

These variables are stored in `/etc/tado-assistant.env`. Feel free to tweak them directly if needed.

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

4. **Environment Variables**: To tweak the behavior of Tado Assistant, adjust the environment variables
   in `/etc/tado-assistant.env`. After making changes, restart the service for them to take effect.

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

Currently, a dedicated uninstallation script is not provided. To manually uninstall:

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