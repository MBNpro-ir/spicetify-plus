# Spicetify Plus ✨ v1.0

Welcome to **Spicetify Plus**, the ultimate all-in-one PowerShell script for managing your Spotify and Spicetify experience on Windows! 🚀

This powerful, menu-driven tool simplifies every step of the process, from installation to advanced configuration, making it accessible for both beginners and power users.

Created with the help of AI and refined by [ME](https://github.com/MBNpro-ir).

---

## 🌟 Features

Spicetify Plus provides a user-friendly command-line interface to handle all your needs:

-   **✅ Smart Spotify Installation**: Automatically detects if Spotify is installed (standard or Microsoft Store version). If not, it downloads and installs it silently.
-   **🎨 One-Click Spicetify Installation**: Installs the latest version of Spicetify-CLI with all necessary configurations handled automatically.
-   **🔧 Comprehensive Settings Menu**: A dedicated sub-menu to manage almost every Spicetify command and configuration option, including:
    -   Core actions like `backup`, `apply`, and `restore`.
    -   Toggling features like custom CSS, dev tools, and experimental settings.
    -   Managing advanced launch flags for Spotify.
-   **🗑️ Clean Uninstallation**: Completely and safely remove Spotify and/or Spicetify, including clearing backup files and cleaning the system's PATH variable.
-   **🤖 Automated API Handling**: Comes pre-configured to use a GitHub API token, avoiding common rate-limit errors during installation and updates.
-   **👨‍💻 Admin-Ready**: Automatically handles Windows Administrator privileges, bypassing Spicetify's internal checks for a seamless experience.

---

## 🚀 Getting Started

Getting started is as simple as running a single command.

### Prerequisites

-   **Windows Operating System**
-   **PowerShell 5.1** or higher (pre-installed on Windows 10 and 11).

### Method 1: Using the Automatic Updater (Recommended)

This is the easiest and most recommended way to get started. Simply download and run the updater file.

1.  **Download the Updater**:
    -   Go to the project repository: [https://github.com/MBNpro-ir/spicetify-plus](https://github.com/MBNpro-ir/spicetify-plus)
    -   Find and download the `spicetify-plus-updater.bat` file.

2.  **Run the file**:
    -   Double-click on the downloaded file (`spicetify-plus-updater.bat`).
    -   The script will automatically request administrator privileges, download the latest version of `spicetify-plus.ps1`, and run it for you.

### Method 2: Direct PowerShell Execution

This method downloads and runs the latest version of the script directly in PowerShell without saving any files permanently.

1.  **Open PowerShell as Administrator**:
    Right-click on the Windows Start Menu and select **"Windows Terminal (Admin)"** or **"PowerShell (Admin)"**.

2.  **Run the Command**:
    Copy and paste the entire command below into the PowerShell window and press Enter.

    ```powershell
    Invoke-RestMethod -Uri "https://raw.githubusercontent.com/MBNpro-ir/spicetify-plus/main/spicetify-plus.ps1" | Invoke-Expression
    ```

    *This command fetches the script content and executes it in memory.*

3.  **Use the Menu**:
    The interactive menu will appear. Simply enter the number corresponding to your desired action and press Enter.

### Method 3: Manual Script Download

If you prefer to download the script before running it, follow these steps.

1.  **Download the Script**:
    -   Go to the project repository: [https://github.com/MBNpro-ir/spicetify-plus](https://github.com/MBNpro-ir/spicetify-plus)
    -   Click on the `spicetify-plus.ps1` file.
    -   Click the **"Raw"** button, then right-click on the page and select **"Save As..."** to save the file to your computer (e.g., in your `Downloads` folder).

2.  **Open PowerShell as Administrator**:
    Right-click on the Windows Start Menu and select **"Windows Terminal (Admin)"** or **"PowerShell (Admin)"**.

3.  **Navigate to the File Location**:
    Use the `cd` command to go to the directory where you saved the script. For example:
    ```powershell
    cd C:\Users\YourUser\Downloads
    ```

4.  **Set Execution Policy (if needed)**:
    If this is your first time running a local script, you may need to bypass the execution policy for this single instance.
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
    ```

5.  **Run the Script**:
    Execute the script by typing its name:
    ```powershell
    .\spicetify-plus.ps1
    ```

6.  **Use the Menu**:
    The interactive menu will now be displayed.

---

## 🔧 Menu Options

### Main Menu
-   **[1] Install Spotify**: Checks for and installs Spotify if it's missing.
-   **[2] Install Spicetify**: Installs the latest version of Spicetify.
-   **[3] Install Spicetify Marketplace**: Installs Spicetify Marketplace.
-   **[4] Spicetify Settings & Actions**: Opens a detailed sub-menu for advanced management.
-   **[5] Remove Spotify**: Uninstalls Spotify from your system.
-   **[6] Remove Spicetify**: Completely removes all Spicetify files and restores Spotify.
-   **[7] Exit**: Closes the script.

### Settings & Actions Sub-Menu
This menu gives you granular control over Spicetify:
-   **Core Actions**: Apply changes, restore backups, refresh themes, etc.
-   **Configuration**: Manage boolean toggles, text settings (like themes), and complex launch flags from intuitive menus.

---

## ⚠️ Troubleshooting

This script was designed to be robust, but here are solutions to common issues:

### GitHub API Rate Limit Error

-   **Problem**: You see an error message like `API rate limit exceeded`. This happens when too many unauthenticated requests are made to GitHub from your IP address.
-   **Solution**: This script includes a built-in GitHub personal access token to prevent this. However, if this token expires or is revoked, you may encounter this issue. To fix it:
    1.  [Generate a new Personal Access Token](https://github.com/settings/tokens) on GitHub (no scopes/permissions are required).
    2.  Open the `spicetify-plus.ps1` script in a text editor.
    3.  Find the line `$Global:githubToken = "..."` at the top of the script.
    4.  Replace the old token with your new one.

---

## 🤝 Contributing

This project was developed by [MBNpro-ir](https://github.com/MBNpro-ir). Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/MBNpro-ir/spicetify-plus/issues).

## 📄 License

This project is open-source. Feel free to use and modify it as you see fit.