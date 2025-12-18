<img width="1600" height="900" alt="image" src="https://github.com/user-attachments/assets/a868506b-5300-4e39-8256-caf5c2bd2274" />

# Spicetify Plus ✨

**[🇮🇷 فارسی](README-FA.md)** | **[🇺🇸 English](README.md)**

Welcome to **Spicetify Plus**, the ultimate all-in-one tool for managing your Spotify and Spicetify experience on Windows! 🚀

This powerful, menu-driven PowerShell tool simplifies every step of the process, from installation to advanced configuration, all wrapped in both a PowerShell script and a convenient `.exe` file for maximum ease of use.

Created with the help of AI and refined by [MBNpro-ir](https://github.com/MBNpro-ir).

---

## 🌟 Features

Spicetify Plus provides a comprehensive, user-friendly interface to handle all your Spotify customization needs:

### 🎵 Spotify Management

- **✅ Smart Spotify Detection & Installation**: Automatically detects if Spotify is installed (standard or Microsoft Store version). If not, downloads and installs it silently.
- **🔄 Spotify Updates**: Check for and manage Spotify updates with guidance.
- **🗑️ Clean Spotify Removal**: Safely uninstall Spotify with complete cleanup.

### 🎨 Spicetify Management

- **🚀 One-Click Spicetify Installation**: Installs the latest version of Spicetify-CLI with all necessary configurations handled automatically.
- **📦 Spicetify Updates**: Keep your Spicetify installation up-to-date with the latest features.
- **🛍️ Marketplace Integration**: Direct installation of Spicetify Marketplace to browse and install themes and extensions from within Spotify.
- **🔧 Comprehensive Settings Menu**: Dedicated sub-menu to manage almost every Spicetify command and configuration option.

### ⚙️ Advanced Features

- **🎭 Theme Management**: Install, configure, and switch between various Spicetify themes.
- **🧩 Extension Management**: Browse and install from 20+ available extensions including bookmarks, lyrics, shuffle improvements, and more.
- **📱 Custom Apps**: Install additional custom applications like History, Visualizer, Better Library, and community-developed apps.
- **🔐 GitHub API Integration**: Built-in GitHub token management to avoid download rate limits.
- **👨‍💻 Admin-Ready**: Automatically handles Windows Administrator privileges for seamless operation.
- **🧹 Complete Cleanup**: Safely remove Spicetify with full restoration of original Spotify.

---

## 🚀 Getting Started

Getting started is as simple as downloading and running a file.

### Prerequisites

- **Windows Operating System** (Windows 10/11 recommended)
- **PowerShell 5.1** or higher (pre-installed on Windows 10 and 11)
- **Internet Connection** for downloading Spotify and Spicetify components

### 📁 Project Files

The repository contains the following files:

- **`spicetify-plus.exe`**: Ready-to-run executable file (recommended for most users)
- **`spicetify-plus.ps1`**: PowerShell source script (for developers and advanced users)
- **`README.md`**: English documentation (this file)
- **`README-FA.md`**: Persian/Farsi documentation

### 👉 For Users (Recommended Method)

1.  **Download the executable** 📥

    - **Method 1**: Click on `spicetify-plus.exe` in the repository → Click "Download" button
    - **Method 2**: Download entire project as ZIP → Extract → Use the `.exe` file
    - **Method 3**: Right-click on the file → "Save link as..." (if viewing raw file)

2.  **Run it!** ▶️
    - Double-click the downloaded `.exe` file
    - Allow administrator permissions when prompted
    - Follow the interactive menu to install and configure everything

### 🧑‍💻 For Developers & Advanced Users

Want to see the code, contribute, or run the PowerShell script directly?

1.  **Download the Source Code** 📦

    - **Option 1**: Clone the repository: `git clone https://github.com/MBNpro-ir/spicetify-plus.git`
    - **Option 2**: Download as ZIP by clicking the green "Code" button → "Download ZIP"
    - **Option 3**: Download individual files directly from the repository

2.  **Run the PowerShell Script** 🛠️
    - Open PowerShell as Administrator
    - Navigate to the project directory
    - Run: `.\spicetify-plus.ps1`
    - The script contains the same functionality as the `.exe` file

---

## 🔧 Menu Structure & Options

### 🏠 Main Menu

- **[1] Install Spotify**: Automatically detects and installs Spotify if missing (supports both standard and Microsoft Store versions)
- **[2] Update Spotify**: Check for Spotify updates and get guidance on updating
- **[3] Remove Spotify**: Safely uninstall Spotify with complete cleanup
- **[4] Install Spicetify**: Download and install the latest Spicetify-CLI with automatic configuration
- **[5] Install Spicetify Marketplace**: Set up the Marketplace for browsing themes and extensions
- **[6] Update Spicetify**: Update Spicetify to the latest version while preserving your configuration
- **[7] Spicetify Settings**: Access the comprehensive settings and management menu
- **[8] Remove Spicetify**: Completely remove Spicetify and restore original Spotify
- **[9] GitHub API Token Settings**: Configure GitHub token to avoid rate limits

### ⚙️ Spicetify Settings Sub-Menu

Comprehensive management interface with the following sections:

#### Core Actions

- **Backup & Apply Changes**: Create Spotify backup and apply all Spicetify modifications
- **Restore Spotify**: Restore Spotify to its original, unmodified state
- **Advanced Refresh & Watch Operations**: Granular control over refreshing and real-time monitoring
  - Refresh Theme (CSS, JS, Colors, Assets)
  - Refresh Extensions Only
  - Refresh Custom Apps Only
  - Refresh Active Theme Only
  - Watch Extensions (auto-refresh on file changes)
  - Watch Custom Apps (auto-refresh on file changes)
  - Watch Active Theme (auto-refresh on file changes)
  - Watch All Components (comprehensive monitoring)
- **Clear Backup Files**: Clean up old backup files to free space
- **Enable/Disable Developer Tools**: Toggle Spotify developer console access
- **Block/Unblock Spotify Updates**: Control Spotify's auto-update behavior

#### Theme Management

- **Install Themes**: Browse and install from 15+ available themes including Dribbblish, Sleek, Text, Turntable, and more
- **Configure Current Theme**: Set active theme and color scheme
- **Theme Settings**: Manage theme-specific configurations

#### Extension Management

- **Install Extensions**: Choose from official Spicetify extensions and community additions:
  - **Official Extensions** (from Spicetify CLI):
    - **Auto Skip Video**: Skip videos that can't play in your region
    - **Bookmark**: Store and browse pages, play tracks or tracks in specific time
    - **Christian Spotify**: Auto skip explicit tracks
    - **Keyboard Shortcut**: Vim-like keyboard navigation controls
    - **Loopy Loop**: Mark start/end points and loop track portions
    - **Shuffle+**: Better shuffle using Fisher-Yates algorithm with zero bias
    - **Trash Bin**: Throw songs/artists to trash and auto-skip them
    - **Full App Display**: Minimal album cover art display with blur effect
    - **Pop-up Lyrics**: Pop-up window with current song's lyrics
    - **WebNowPlaying**: For Rainmeter users - WebNowPlaying plugin support
  - **Community Extensions**: Auto-skip tracks by duration, DJ Mode, and more
  - **Legacy Extensions**: New Release aggregator, Queue All button

#### Custom Apps

- **Install Custom Apps**: Add functionality with apps like:
  - **History**: Track your listening history
  - **Visualizer**: Audio visualization effects
  - **Better Library**: Enhanced library management
  - **Playlist Tags**: Organize playlists with tags
  - **Enhancify**: Additional UI enhancements

#### Theme & Colors

- **Manage Theme Colors**: Advanced color management system
  - View All Colors (with color preview)
  - Change Single Color
  - Change Multiple Colors
  - Reset Colors to Theme Default

#### Configuration Management

- **Configuration Toggles**: Manage boolean settings (0 = Disabled, 1 = Enabled)
  - `inject_css`: Enable custom CSS injection
  - `inject_theme_js`: Enable theme JavaScript injection
  - `replace_colors`: Replace Spotify colors with theme colors
  - `overwrite_assets`: Overwrite theme assets during apply
  - `always_enable_devtools`: Always enable developer tools
  - `check_spicetify_update`: Check for Spicetify updates on launch
  - `disable_sentry`: Disable Spotify crash reporting
  - `disable_ui_logging`: Disable UI logging
  - `remove_rtl_rule`: Remove right-to-left CSS rules
  - `expose_apis`: Expose Spicetify APIs to extensions
  - `experimental_features`: Enable experimental Spicetify features
  - `home_config`: Enable home screen configuration
  - `sidebar_config`: Enable sidebar configuration
- **Text Settings**: Configure themes, color schemes, and paths
- **Launch Flags Management**: Control Spotify startup flags
  - Add, remove, or clear Spotify executable launch flags
  - Persistent shortcut-based flag management

#### Path & Directory Management

- **Path Information**: View important Spicetify paths
  - Show Spotify Executable Path
  - Show Spicetify Userdata Path
  - Show All Paths
  - Show Extensions Path
  - Show Custom Apps Path
  - Show Active Theme Path
  - Show Config File Path
  - Open Config Directory in File Explorer

---

## ⚠️ Troubleshooting

### Common Issues & Solutions

#### GitHub API Rate Limit Error

- **Problem**: Error message `API rate limit exceeded` appears during downloads
- **Cause**: Too many unauthenticated requests to GitHub from your IP address
- **Solution**: Configure a GitHub Personal Access Token
  1.  Go to [GitHub Token Settings](https://github.com/settings/tokens)
  2.  Generate a new token (no special permissions needed for public repositories)
  3.  In the script, go to **Main Menu → [9] GitHub API Token Settings**
  4.  Enter your token when prompted
  5.  The token will be saved and used automatically for all future downloads

#### Spicetify Not Working After Installation

- **Problem**: Spicetify commands not recognized or Spotify looks unchanged
- **Solution**:
  1.  Use **Settings → Core Actions → Backup & Apply Changes**
  2.  Restart Spotify completely
  3.  If issues persist, try **Settings → Core Actions → Restore Spotify** then reinstall

#### Spotify Won't Start or Crashes

- **Problem**: Spotify fails to launch after applying Spicetify
- **Solution**:
  1.  Use **Settings → Core Actions → Restore Spotify** to revert to original state
  2.  Restart Spotify to ensure it works normally
  3.  Try reinstalling Spicetify with a different theme or fewer extensions

#### Extensions Not Appearing

- **Problem**: Installed extensions don't show up in Spotify
- **Solution**:
  1.  Ensure you've run **Backup & Apply Changes** after installing extensions
  2.  Restart Spotify completely (close all Spotify processes)
  3.  Check that the extension is compatible with your Spicetify version

#### Permission Errors

- **Problem**: Access denied or permission errors during installation
- **Solution**:
  1.  Run the script as Administrator (right-click → "Run as administrator")
  2.  Ensure Spotify is completely closed before making changes
  3.  Temporarily disable antivirus if it's blocking the script

---

## 🔧 Advanced Usage

### GitHub Token Configuration

The script includes built-in GitHub API token management to avoid rate limits:

- Tokens are stored securely in your user profile directory
- Automatic validation and error handling
- Environment variable configuration for Spicetify CLI compatibility

### Backup and Restore

- Automatic backup creation before applying changes
- Safe restore functionality to revert to original Spotify
- Configuration preservation during updates

### Custom Installation Paths

The script automatically handles:

- Standard Spotify installations
- Microsoft Store Spotify versions
- Custom Spicetify installation directories
- PATH environment variable management

---

## 🤝 Contributing

This project is developed and maintained by [MBNpro-ir](https://github.com/MBNpro-ir).

### How to Contribute

- 🐛 **Report Bugs**: Use the [Issues page](https://github.com/MBNpro-ir/spicetify-plus/issues) to report problems
- 💡 **Suggest Features**: Share your ideas for new functionality
- 🔧 **Submit Pull Requests**: Contribute code improvements or new features
- 📖 **Improve Documentation**: Help make the documentation clearer and more comprehensive

### Development

- The main script is `spicetify-plus.ps1` written in PowerShell
- The executable is compiled from the PowerShell script for easier distribution
- All GitHub API interactions include proper error handling and rate limit management

---

## 📄 License

This project is open-source and available under the MIT License. Feel free to use, modify, and distribute it as you see fit.

---

## 📅 Changelog

### Version 2.2.0 - December 19, 2024

#### 🆕 New Features

- **Auto Check & Apply (Smart Update)**: New intelligent command that automatically checks if backup is needed and applies changes
  - Detects if Spicetify backup is outdated or missing
  - Automatically re-creates backup if needed
  - Applies customizations only when necessary
  - Available as option [2] in Spicetify Settings menu
  - Based on upstream CLI `auto` command for smart maintenance

#### 🔄 Updates

- **Code Synchronization**: Full synchronization with latest Spicetify upstream repositories
  - Verified all extensions match CLI manifest (10 official extensions)
  - Confirmed all custom apps align with upstream sources (3 official + 16 community apps)
  - Validated all Spicetify CLI commands and features are up-to-date
  - All configuration toggles verified against latest CLI version
  - Added support for `spicetify auto` command
- **Installation Paths**: Confirmed correct installation path (`$env:LOCALAPPDATA\spicetify`)
- **GitHub API Integration**: All download functions properly utilize GitHub tokens for rate limit prevention

---

## 🙏 Acknowledgments

- **Spicetify Team**: For creating the amazing Spicetify CLI tool
- **Spotify**: For the music streaming platform that makes this all possible
- **Community Contributors**: For themes, extensions, and feedback that make this tool better
- **AI Assistance**: For helping with development and refinement

---

## 📞 Support

If you encounter any issues or need help:

1.  Check the [Troubleshooting](#️-troubleshooting) section above
2.  Search existing [Issues](https://github.com/MBNpro-ir/spicetify-plus/issues) for similar problems
3.  Create a new issue with detailed information about your problem
4.  Include your Windows version, PowerShell version, and any error messages

**Enjoy your customized Spotify experience! 🎵✨**

<img width="1163" height="641" alt="image" src="https://github.com/user-attachments/assets/ba816d53-dc0b-4896-8484-ee95ef452df3" />
