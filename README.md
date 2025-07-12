<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/a868506b-5300-4e39-8256-caf5c2bd2274" />

# Spicetify Plus ✨ v1.0

Welcome to **Spicetify Plus**, the ultimate all-in-one tool for managing your Spotify and Spicetify experience on Windows! 🚀

This powerful, menu-driven tool simplifies every step of the process, from installation to advanced configuration, all wrapped in a simple `.exe` file for maximum convenience.

Created with the help of AI and refined by [MBNpro-ir](https://github.com/MBNpro-ir).

---

## 🌟 Features

Spicetify Plus provides a user-friendly interface to handle all your needs:

-   **✨ One-Click Setup**: The easiest way to get started. Just run the `.exe` and you're good to go.
-   **✅ Smart Spotify Installation**: Automatically detects if Spotify is installed (standard or Microsoft Store version). If not, it downloads and installs it silently.
-   **🎨 Effortless Spicetify Installation**: Installs the latest version of Spicetify-CLI with all necessary configurations handled automatically.
-   **🔧 Comprehensive Settings Menu**: A dedicated sub-menu to manage almost every Spicetify command and configuration option, including core actions, feature toggles, and advanced launch flags.
-   **🛍️ Marketplace Ready**: Includes an option to directly install the Spicetify Marketplace to browse and install themes and extensions from within Spotify.
-   **🗑️ Clean Uninstallation**: Completely and safely remove Spotify and/or Spicetify, including clearing backup files and cleaning the system's PATH variable.
-   **🔐 Rate Limit Prevention**: Easily add your own GitHub API token within the script to avoid download rate limits from GitHub.
-   **👨‍💻 Admin-Ready**: The executable automatically handles Windows Administrator privileges for a seamless experience.

---

## 🚀 Getting Started

Getting started is as simple as downloading a file.

### Prerequisites

-   **Windows Operating System**
-   **PowerShell 5.1** or higher (pre-installed on Windows 10 and 11).

### 👉 For Users (Easiest Method)

1.  **Download the executable** 📥
    -   Download the `spicetify-plus.exe` file directly from the repository.

2.  **Run it!** ▶️
    -   Just double-click the downloaded file. It will handle everything for you, including asking for administrator permissions. That's it!

### 🧑‍💻 For Developers

Want to see the code or contribute?

1.  **Download the Source Code** 📦
    -   You can download the entire project as a `.zip` file by clicking [here](https://github.com/MBNpro-ir/spicetify-plus/archive/refs/heads/main.zip).

2.  **Explore the files** 🛠️
    -   Inside you will find the `spicetify-plus.ps1` PowerShell script that the `.exe` is based on.

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

### GitHub API Rate Limit Error

-   **Problem**: You see an error message like `API rate limit exceeded`. This happens when too many unauthenticated requests are made to GitHub from your IP address.
-   **Solution**: The script allows you to use a GitHub personal access token to prevent this.
    1.  [Generate a new Personal Access Token](https://github.com/settings/tokens) on GitHub (no scopes/permissions are required for public repos).
    2.  If you are a developer, open the `spicetify-plus.ps1` script in a text editor.
    3.  Find the line `$Global:githubToken = ""` at the top of the script.
    4.  Place your new token inside the quotes.

---

## 🤝 Contributing

This project was developed by [MBNpro-ir](https://github.com/MBNpro-ir). Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/MBNpro-ir/spicetify-plus/issues).

## 📄 License

This project is open-source. Feel free to use and modify it as you see fit.
