"""John's Windows Fixer — system optimizer backend.

Windows-only PyQt6 backend exposed to QML as the "optimizer" context
property.  Tweak definitions live in newTweaks.json.  Every tweak is
applied for real; commands run asynchronously through QProcess so the UI
(and the morphing loading animation) stays responsive even while a tweak
like Disk Cleanup runs for minutes.
"""

import json
import os
import platform
import re
import subprocess
import sys
import time

import psutil
from PyQt6.QtCore import (
    QObject,
    QProcess,
    QTimer,
    QUrl,
    QSettings,
    pyqtProperty,
    pyqtSignal,
    pyqtSlot,
)
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine, qmlRegisterType

from materialLoading import M3ExpressiveExactIndicator

try:
    import GPUtil
    HAS_GPU = True
except ImportError:
    HAS_GPU = False

APP_DIR = os.path.dirname(os.path.abspath(__file__))

# Default command timeout (seconds).  Individual tweaks can override via a
# "Timeout" field in newTweaks.json.
DEFAULT_TIMEOUT = 120


def is_windows_admin():
    """True when the process holds administrator privileges (Windows)."""
    if platform.system() != "Windows":
        return False
    try:
        import ctypes
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


class SystemOptimizer(QObject):
    logMessage = pyqtSignal(str)
    tweaksLoaded = pyqtSignal()
    toggleStateChanged = pyqtSignal(str, bool)
    optionStateChanged = pyqtSignal(str, str)
    optimizationProgress = pyqtSignal(int, str)  # percent, status text
    optimizationComplete = pyqtSignal()
    isOptimizingChanged = pyqtSignal()
    adminStatusChanged = pyqtSignal()
    platformInfoChanged = pyqtSignal()
    selectedPresetChanged = pyqtSignal()
    profileNeedsSetupChanged = pyqtSignal()
    startupAppsChanged = pyqtSignal()
    startupImpactChanged = pyqtSignal()
    startupImpactSettingsChanged = pyqtSignal()
    backgroundAppsChanged = pyqtSignal()
    backgroundAppsLoadingChanged = pyqtSignal()
    debloatAppsChanged = pyqtSignal()
    debloatAppsLoadingChanged = pyqtSignal()
    debloatRemovingChanged = pyqtSignal()
    debloatRemovalProgress = pyqtSignal(int, str)  # percent, status text

    # Tweaks whose applied state is surfaced on the Home screen.
    OPTIMIZE_TWEAKS = [
        "WPFTweaksHiber",
        "WPFTweaksServices",
        "WPFTweaksTelemetry",
        "WPFTweaksDeliveryOptimization",
        "WPFTweaksDisableExplorerAutoDiscovery",
        "WPFTweaksActivity",
        "WPFTweaksConsumerFeatures",
        "WPFTweaksGameMode",
        "WPFTweaksWindowedGames",
        "WPFTweaksHAGS",
        "WPFTweaksStorageSenseEnable",
    ]

    # win32service start-type constants.
    START_TYPES = {
        "Boot": 0,
        "System": 1,
        "Automatic": 2,
        "Manual": 3,
        "Disabled": 4,
    }

    # Preinstalled apps offered on the Debloat page.  "name" is the package
    # identifier used for removal and matching; "matches" adds extra
    # substrings used to detect installed copies whose package name differs
    # (e.g. SpotifyAB.SpotifyMusic).  Levels: Recommended / Optional / Caution.
    DEBLOAT_CATALOG = [
        {"name": "Microsoft.BingFinance", "label": "Bing Finance", "level": "Recommended", "reason": "A financial-news shortcut; the website does the same"},
        {"name": "Microsoft.BingNews", "label": "Bing News", "level": "Recommended", "reason": "A news shortcut; the website does the same"},
        {"name": "Microsoft.BingSports", "label": "Bing Sports", "level": "Recommended", "reason": "A sports-news shortcut; the website does the same"},
        {"name": "Microsoft.BingTranslator", "label": "Bing Translator", "level": "Recommended", "reason": "Any web translator does the same"},
        {"name": "Microsoft.BingWeather", "label": "Bing Weather", "level": "Optional", "reason": "Keep if you check the weather in it daily"},
        {"name": "Microsoft.549981C3F5F10", "label": "Cortana", "level": "Recommended", "reason": "The voice assistant is retired in Windows"},
        {"name": "Microsoft.GetHelp", "label": "Get Help", "level": "Optional", "reason": "Only used to contact Microsoft support"},
        {"name": "Microsoft.Getstarted", "label": "Tips", "level": "Recommended", "reason": "A one-time introduction to Windows"},
        {"name": "Microsoft.WindowsFeedbackHub", "label": "Feedback Hub", "level": "Recommended", "reason": "Only used to report bugs to Microsoft"},
        {"name": "Microsoft.Messaging", "label": "Messaging", "level": "Recommended", "reason": "Legacy SMS app that is no longer supported"},
        {"name": "Microsoft.Microsoft3DViewer", "label": "3D Viewer", "level": "Recommended", "reason": "Only needed for viewing 3D model files"},
        {"name": "Microsoft.3DBuilder", "label": "3D Builder", "level": "Recommended", "reason": "Legacy 3D printing app from Windows 10"},
        {"name": "Microsoft.Print3D", "label": "Print 3D", "level": "Recommended", "reason": "Legacy 3D printing companion app"},
        {"name": "Microsoft.MixedReality.Portal", "label": "Mixed Reality Portal", "level": "Recommended", "reason": "Only needed for VR headsets"},
        {"name": "Microsoft.NetworkSpeedTest", "label": "Network Speed Test", "level": "Recommended", "reason": "A browser speed test does the same"},
        {"name": "Microsoft.OneConnect", "label": "OneConnect", "level": "Recommended", "reason": "Phone companion that most people never use"},
        {"name": "Microsoft.Office.Sway", "label": "Sway", "level": "Recommended", "reason": "Legacy presentation app"},
        {"name": "Microsoft.ZuneMusic", "label": "Groove Music", "level": "Recommended", "reason": "Legacy music player replaced by Spotify and others"},
        {"name": "Microsoft.ZuneVideo", "label": "Movies & TV", "level": "Recommended", "reason": "Legacy video player; streaming apps do it better"},
        {"name": "Microsoft.WindowsSoundRecorder", "label": "Voice Recorder", "level": "Optional", "reason": "Keep if you record voice notes"},
        {"name": "Facebook", "label": "Facebook", "level": "Recommended", "reason": "Just a shortcut to the website"},
        {"name": "Flipboard", "label": "Flipboard", "level": "Recommended", "reason": "A news shortcut; works in your browser"},
        {"name": "Twitter", "label": "Twitter / X", "level": "Recommended", "reason": "Just a shortcut to the website"},
        {"name": "Wunderlist", "label": "Wunderlist", "level": "Recommended", "reason": "Discontinued; replaced by Microsoft To Do"},
        {"name": "PandoraMediaInc", "label": "Pandora", "level": "Recommended", "matches": ["pandoramediainc"], "reason": "Pandora works in any browser"},
        {"name": "Spotify", "label": "Spotify", "level": "Recommended", "matches": ["spotifyab"], "reason": "Spotify works in any browser"},
        {"name": "Duolingo-LearnLanguagesforFree", "label": "Duolingo", "level": "Recommended", "reason": "Duolingo works in any browser"},
        {"name": "HULULLC.HULUPLUS", "label": "Hulu", "level": "Recommended", "reason": "Hulu works in any browser"},
        {"name": "Picsart-Photostudio", "label": "Picsart", "level": "Optional", "reason": "Keep if you edit photos with it"},
        {"name": "AdobeSystemsIncorporated.AdobePhotoshopExpress", "label": "Photoshop Express", "level": "Recommended", "reason": "Photo editing works in any browser"},
        {"name": "Speed test", "label": "Speedtest by Ookla", "level": "Recommended", "matches": ["speedtest", "ookla"], "reason": "A browser speed test does the same"},
        {"name": "Clipchamp.Clipchamp", "label": "Clipchamp", "level": "Recommended", "reason": "Free browser video editors do the same"},
        {"name": "Microsoft.MicrosoftSolitaireCollection", "label": "Solitaire Collection", "level": "Recommended", "reason": "Solitaire works in any browser"},
        {"name": "Microsoft.MicrosoftStickyNotes", "label": "Sticky Notes", "level": "Optional", "reason": "Keep if you jot quick notes"},
        {"name": "Microsoft.Todos", "label": "Microsoft To Do", "level": "Optional", "reason": "Keep if you use task lists"},
        {"name": "Microsoft.WindowsAlarms", "label": "Alarms & Clock", "level": "Optional", "reason": "Keep if you use alarms or the timer"},
        {"name": "Microsoft.WindowsMaps", "label": "Maps", "level": "Optional", "reason": "Keep if you use offline maps"},
        {"name": "Microsoft.News", "label": "News", "level": "Recommended", "reason": "A news shortcut; the website does the same"},
        {"name": "Microsoft.SkypeApp", "label": "Skype", "level": "Recommended", "reason": "Skype works in any browser"},
        {"name": "Microsoft.MicrosoftOfficeHub", "label": "Office Hub", "level": "Optional", "reason": "Used by some for Office and OneDrive shortcuts"},
        {"name": "Microsoft.Asphalt8Airborne", "label": "Asphalt 8", "level": "Recommended", "reason": "Preinstalled racing game"},
        {"name": "Royal Revolt", "label": "Royal Revolt", "level": "Recommended", "matches": ["royalrevolt"], "reason": "Preinstalled game"},
        {"name": "king.com.BubbleWitch3Saga", "label": "Bubble Witch 3 Saga", "level": "Recommended", "reason": "Preinstalled game"},
        {"name": "king.com.CandyCrushSaga", "label": "Candy Crush Saga", "level": "Recommended", "reason": "Preinstalled game"},
        {"name": "king.com.CandyCrushSodaSaga", "label": "Candy Crush Soda Saga", "level": "Recommended", "reason": "Preinstalled game"},
        {"name": "Dolby", "label": "Dolby Audio", "level": "Caution", "matches": ["dolbylaboratories"], "reason": "May be needed for Dolby sound on supported hardware"},
        {"name": "Microsoft.Office.OneNote", "label": "OneNote", "level": "Caution", "reason": "Keep if you take notes"},
        {"name": "Microsoft.RemoteDesktop", "label": "Remote Desktop", "level": "Caution", "reason": "Keep if you connect to other PCs"},
    ]

    def __init__(self, parent=None):
        super().__init__(parent)
        self._tweaksData = {}
        self._toggleStates = {}
        self._optionStates = {}
        self._isOptimizing = False
        self._optimizeQueue = []
        self._optimizeTotal = 0
        self._optimizeDone = 0
        self._isAdmin = is_windows_admin()
        self._runningProcesses = set()
        # Local, deletable settings file next to the app (not the registry or
        # per-user config), so a fresh install or a deleted settings.ini is a
        # true first run. Deleting settings.ini resets the first-run prompts.
        self._settings = QSettings(os.path.join(APP_DIR, "settings.ini"), QSettings.Format.IniFormat)
        self._selectedPreset = self._settings.value("preset", "", type=str)
        if self._selectedPreset not in {"Gaming", "Productivity"}:
            self._selectedPreset = ""
        self._restorePointPromptVisible = False
        self._adminPromptVisible = False
        self._startupImpactCache = {}
        self._startupImpactProcess = None
        self._startupImpactEnabled = False
        self._startupImpactSettingsProcess = None
        self._startupImpactCommandProcess = None
        self._backgroundAppsCache = []
        self._backgroundProcess = None
        self._backgroundAppsLoading = False
        self._debloatAppsCache = []
        self._debloatProcess = None
        self._debloatAppsLoading = False
        self._debloating = False
        self._debloatQueue = []
        self._debloatDone = 0

    # ------------------------------------------------------------------ #
    # Presets and user-managed app lists
    # ------------------------------------------------------------------ #

    @pyqtProperty(str, notify=selectedPresetChanged)
    def selectedPreset(self):
        return self._selectedPreset or "Gaming"

    @pyqtProperty(bool, notify=profileNeedsSetupChanged)
    def profileNeedsSetup(self):
        return not bool(self._selectedPreset)

    @pyqtSlot(str)
    def setSelectedPreset(self, preset):
        if preset not in {"Gaming", "Productivity"}:
            return
        wasUnconfigured = not bool(self._selectedPreset)
        if preset == self._selectedPreset and not wasUnconfigured:
            return
        self._selectedPreset = preset
        self._settings.setValue("preset", preset)
        self._settings.sync()
        # Changing the profile changes what Optimize will apply; it must not
        # pretend that already-applied Windows settings were reverted.
        self.selectedPresetChanged.emit()
        if wasUnconfigured:
            self.profileNeedsSetupChanged.emit()
        self.logMessage.emit(f"{preset} preset selected")

    @pyqtSlot(result=list)
    def getPresets(self):
        presets = self._tweaksData.get("presets", {})
        return [
            {"key": key, "name": value.get("name", key), "description": value.get("description", "")}
            for key, value in presets.items()
            if key in {"Gaming", "Productivity"}
        ]

    # ------------------------------------------------------------------ #
    # Administrator status (Windows)
    # ------------------------------------------------------------------ #

    @pyqtProperty(bool, notify=adminStatusChanged)
    def isAdmin(self):
        return self._isAdmin

    @pyqtProperty(bool, notify=platformInfoChanged)
    def isWindows(self):
        return platform.system() == "Windows"

    @pyqtSlot()
    def restartAsAdmin(self):
        """Relaunch this app with elevated privileges (UAC prompt)."""
        if platform.system() != "Windows":
            self.logMessage.emit("Run the app as Administrator on Windows.")
            return
        if self._isAdmin:
            self.logMessage.emit("The app is already running as Administrator.")
            return
        try:
            import ctypes
            params = subprocess.list2cmdline(sys.argv[1:])
            script = os.path.abspath(__file__)
            ctypes.windll.shell32.ShellExecuteW(
                None, "runas", sys.executable, f'"{script}" {params}', None, 1
            )
            self.logMessage.emit("Launching with administrator permission. Approve the Windows prompt.")
        except Exception as exc:
            self.logMessage.emit(f"Could not restart with administrator permission: {exc}")

    # ------------------------------------------------------------------ #
    # Tweak data
    # ------------------------------------------------------------------ #

    @pyqtSlot(str)
    def loadTweaksJson(self, jsonFilePath):
        with open(jsonFilePath, "r", encoding="utf-8") as f:
            self._tweaksData = json.load(f)
        self._validateToggleReversibility()
        self._refreshAppliedStates()
        self.tweaksLoaded.emit()

    def _validateToggleReversibility(self):
        """Warn at load time if any toggle lacks a way to revert.

        Every tweak the UI shows as a toggle must carry OriginalValue on all
        of its registry entries, OriginalType on all of its services, or an
        UndoScript -- otherwise flipping it off would not restore anything.
        """
        for key, tweak in self._tweaksData.items():
            if key == "presets" or self._determineControlType(tweak) != "toggle":
                continue
            registry = tweak.get("registry") or []
            services = tweak.get("service") or []
            reversible = bool(tweak.get("UndoScript")) or (
                bool(registry) and all("OriginalValue" in entry for entry in registry)
            ) or (
                bool(services) and all("OriginalType" in entry for entry in services)
            )
            if not reversible:
                print(f"[WARNING] {key} is a toggle with no revert data")

    @pyqtSlot(result=list)
    def getCategories(self):
        return ["Home", "Performance", "Storage", "Privacy", "Debloat", "Startup", "Background"]

    def _tweakRequiresAdmin(self, tweakKey):
        tweak = self._tweaksData.get(tweakKey)
        return bool(tweak and tweak.get("RequiresAdmin", False))

    def _adminBlocked(self, tweakKey):
        """True when this tweak needs elevation and the app is not elevated."""
        return (
            platform.system() == "Windows"
            and not self._isAdmin
            and self._tweakRequiresAdmin(tweakKey)
        )

    def _tweakSupportReason(self, tweakKey):
        if self._adminBlocked(tweakKey):
            return "admin"
        return "platform"

    def _isTweakSupported(self, tweakKey):
        if platform.system() != "Windows":
            return False
        if tweakKey == "WPFTweaksHAGS":
            if platform.system() != "Windows":
                return False
            try:
                build = int(platform.version().split(".")[2]) if len(platform.version().split(".")) >= 3 else 0
            except (ValueError, IndexError):
                build = 0
            if build < 19041:
                return False
            try:
                import GPUtil
                gpus = GPUtil.getGPUs()
                return bool(gpus) and any(gpu.driver for gpu in gpus)
            except Exception:
                # Without a GPU query we cannot claim support: the apply
                # script still re-checks at runtime, but the toggle stays
                # conservative rather than guessing.
                return False
        if self._adminBlocked(tweakKey):
            # Standard (non-elevated) mode: admin-only tweaks stay dimmed
            # instead of failing halfway through a partial apply.
            return False
        return True

    @pyqtSlot(str, result=list)
    def getTweaksByCategory(self, category):
        result = []
        for key, tweak in self._tweaksData.items():
            if key == "presets":
                continue
            if tweak.get("category") == category:
                result.append({
                    "key": key,
                    "content": tweak.get("Content", key),
                    "description": tweak.get("Description", ""),
                    "controlType": self._determineControlType(tweak),
                    "actionLabel": tweak.get("ActionLabel", "Apply"),
                    "supported": self._isTweakSupported(key),
                    "supportReason": self._tweakSupportReason(key),
                    "options": tweak.get("Options", []),
                    "selectedOption": self._optionStates.get(
                        key, tweak.get("DefaultOption", "")
                    ),
                    "enabled": self._toggleStates.get(key, False),
                })
        return result

    @pyqtSlot(str, result=str)
    def getCategoryTooltip(self, category):
        return {
            "Home": "System overview and one-click optimization",
            "Performance": "Improve responsiveness and reduce background work",
            "Storage": "Free disk space and manage storage settings",
            "Privacy": "Reduce telemetry and data collection",
            "Debloat": "Remove preinstalled apps you don't need",
            "Startup": "Choose which apps start with Windows",
            "Background": "Choose which apps may run in the background",
        }.get(category, "")

    # ------------------------------------------------------------------ #
    # Startup applications
    # ------------------------------------------------------------------ #

    @staticmethod
    def _startup_views():
        try:
            import winreg
            return [("64-bit", winreg.KEY_WOW64_64KEY), ("32-bit", winreg.KEY_WOW64_32KEY)]
        except (ImportError, AttributeError):
            return [("default", 0)]

    def _startup_hive(self, name):
        import winreg
        return {"HKCU": winreg.HKEY_CURRENT_USER, "HKLM": winreg.HKEY_LOCAL_MACHINE}.get(name)

    @staticmethod
    def _startup_folder_paths():
        paths = []
        app_data = os.environ.get("APPDATA", "")
        program_data = os.environ.get("PROGRAMDATA", "")
        if app_data:
            paths.append(("HKCU", os.path.join(app_data, "Microsoft", "Windows", "Start Menu", "Programs", "Startup")))
        if program_data:
            paths.append(("HKLM", os.path.join(program_data, "Microsoft", "Windows", "Start Menu", "Programs", "Startup")))
        return paths

    @staticmethod
    def _startup_approval_path(source):
        return rf"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\{source}"

    def _read_startup_approval(self, hive_name, source, name, view_flag=0):
        try:
            import winreg
            with winreg.OpenKey(
                self._startup_hive(hive_name), self._startup_approval_path(source),
                0, winreg.KEY_READ | view_flag
            ) as key:
                value, _ = winreg.QueryValueEx(key, name)
                return bytes(value) if isinstance(value, (bytes, bytearray)) else None
        except (OSError, TypeError, ValueError):
            return None

    @staticmethod
    def _startup_is_enabled(approval):
        # StartupApproved byte 0: 2 = enabled, 3 = disabled,
        # 6 = disabled by the user. Unknown/missing defaults to enabled.
        return not approval or approval[0] in (0, 2)

    def _set_startup_approval(self, hive_name, source, name, enabled, view_flag=0):
        import winreg
        path = self._startup_approval_path(source)
        access = winreg.KEY_QUERY_VALUE | winreg.KEY_SET_VALUE | view_flag
        with winreg.CreateKeyEx(self._startup_hive(hive_name), path, 0, access) as key:
            try:
                existing, _ = winreg.QueryValueEx(key, name)
            except OSError:
                existing = bytes(12)
            data = bytearray(existing if isinstance(existing, (bytes, bytearray)) else bytes(12))
            if len(data) < 12:
                data.extend(bytes(12 - len(data)))
            data[0] = 2 if enabled else 3
            winreg.SetValueEx(key, name, 0, winreg.REG_BINARY, bytes(data))

    @staticmethod
    def _friendly_package_name(package_name):
        text = str(package_name or "Windows app").replace(".", " ").replace("_", " ")
        text = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", text)
        return " ".join(text.split())

    @staticmethod
    def _startup_impact_keys(*values):
        keys = set()
        for value in values:
            text = str(value or "").strip().strip('"')
            if not text:
                continue
            lowered = text.lower()
            keys.add(lowered)
            keys.add(os.path.basename(lowered))
        return keys

    def _startup_impact_for(self, *values):
        for key in self._startup_impact_keys(*values):
            result = self._startupImpactCache.get(key)
            if result:
                return result
        return {
            "label": "Impact: Not measured",
            "detail": "Windows has no recent startup measurement",
        }

    @pyqtSlot()
    def refreshStartupApps(self):
        self.startupAppsChanged.emit()
        self.refreshStartupImpact()

    @pyqtProperty(bool, notify=startupImpactSettingsChanged)
    def startupImpactEnabled(self):
        return self._startupImpactEnabled

    @pyqtSlot()
    def refreshStartupImpactSettings(self):
        if platform.system() != "Windows":
            self._startupImpactEnabled = False
            self.startupImpactSettingsChanged.emit()
            return
        if self._startupImpactSettingsProcess is not None and self._startupImpactSettingsProcess.state() != QProcess.ProcessState.NotRunning:
            return
        command = (
            "(Get-WinEvent -ListLog 'Microsoft-Windows-Diagnostics-Performance/Operational' "
            "-ErrorAction SilentlyContinue).IsEnabled"
        )
        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._startupImpactSettingsProcess = process
        process.finished.connect(
            lambda code, status, p=process: self._onStartupImpactSettingsFinished(p, code)
        )
        process.errorOccurred.connect(
            lambda err, p=process: self._onStartupImpactSettingsFinished(p, -1)
            if err == QProcess.ProcessError.FailedToStart else None
        )
        process.start(
            "powershell",
            ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        )

    def _onStartupImpactSettingsFinished(self, process, code):
        output = bytes(process.readAllStandardOutput()).decode("utf-8", errors="replace").strip()
        if code == 0:
            self._startupImpactEnabled = output.lower().splitlines()[-1:] == ["true"]
        else:
            self._startupImpactEnabled = False
        self._startupImpactSettingsProcess = None
        process.deleteLater()
        self.startupImpactSettingsChanged.emit()

    @pyqtSlot(bool)
    def setStartupImpactEnabled(self, enabled):
        enabled = bool(enabled)
        if platform.system() != "Windows":
            self.logMessage.emit("Startup measurements are available on Windows.")
            return
        if self._startupImpactEnabled == enabled:
            return
        if self._startupImpactCommandProcess is not None and self._startupImpactCommandProcess.state() != QProcess.ProcessState.NotRunning:
            return
        state = "true" if enabled else "false"
        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._startupImpactCommandProcess = process
        process.finished.connect(
            lambda code, status, p=process, value=enabled: self._onStartupImpactCommandFinished(p, code, value)
        )
        process.start(
            "wevtutil.exe",
            ["sl", "Microsoft-Windows-Diagnostics-Performance/Operational", f"/e:{state}"],
        )

    def _onStartupImpactCommandFinished(self, process, code, enabled):
        output = bytes(process.readAllStandardOutput()).decode("utf-8", errors="replace").strip()
        self._startupImpactCommandProcess = None
        process.deleteLater()
        if code == 0:
            self.logMessage.emit("Startup measurements " + ("enabled" if enabled else "disabled"))
            self.refreshStartupImpactSettings()
            if enabled:
                self.refreshStartupImpact()
        else:
            self.logMessage.emit("Could not change startup measurement settings")
            if output:
                self.logMessage.emit(output)

    @pyqtSlot()
    def refreshStartupImpact(self):
        """Read recent Windows startup diagnostics when available.

        Windows records application startup performance in the Diagnostics-
        Performance event log. If the log is unavailable or has no matching
        event, the UI deliberately reports Not measured instead of guessing.
        """
        if platform.system() != "Windows":
            self._startupImpactCache = {}
            self.startupImpactChanged.emit()
            return
        if self._startupImpactProcess is not None and self._startupImpactProcess.state() != QProcess.ProcessState.NotRunning:
            return
        command = (
            "$events = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; "
            "Id=101; StartTime=(Get-Date).AddDays(-30)} -MaxEvents 300 -ErrorAction SilentlyContinue); "
            "$result = foreach ($event in $events) { $xml = [xml]$event.ToXml(); $data = @{}; "
            "foreach ($item in $xml.Event.EventData.Data) { $data[$item.Name] = [string]$item.'#text' }; "
            "[pscustomobject]@{ FriendlyName=$data['FriendlyName']; FileName=$data['FileName']; "
            "ProcessName=$data['ProcessName']; MainPath=$data['MainPath']; TotalTime=$data['TotalTime']; "
            "DegradationTime=$data['DegradationTime']; TimeCreated=$event.TimeCreated.ToString('o') } }; "
            "$result | ConvertTo-Json -Compress"
        )
        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._startupImpactProcess = process
        process.finished.connect(
            lambda code, status, p=process: self._onStartupImpactFinished(p, code)
        )
        process.errorOccurred.connect(
            lambda err, p=process: self._onStartupImpactFinished(p, -1)
            if err == QProcess.ProcessError.FailedToStart else None
        )
        process.start(
            "powershell",
            ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        )

    def _onStartupImpactFinished(self, process, code):
        output = bytes(process.readAllStandardOutput()).decode("utf-8", errors="replace").strip()
        cache = {}
        if code == 0 and output:
            try:
                rows = json.loads(output)
                if isinstance(rows, dict):
                    rows = [rows]
                for row in rows or []:
                    try:
                        raw_time = row.get("TotalTime") or row.get("DegradationTime") or "0"
                        milliseconds = int(float(str(raw_time)))
                    except (TypeError, ValueError):
                        continue
                    if milliseconds <= 0:
                        continue
                    if milliseconds <= 500:
                        label = "Impact: Low"
                    elif milliseconds <= 1500:
                        label = "Impact: Medium"
                    else:
                        label = "Impact: High"
                    result = {
                        "label": label,
                        "detail": "Measured by Windows during startup",
                    }
                    values = [
                        row.get("FriendlyName"), row.get("FileName"),
                        row.get("ProcessName"), row.get("MainPath"),
                    ]
                    for key in self._startup_impact_keys(*values):
                        cache[key] = result
            except json.JSONDecodeError:
                pass
        self._startupImpactCache = cache
        self._startupImpactProcess = None
        process.deleteLater()
        self.startupImpactChanged.emit()

    @pyqtSlot(result=list)
    def getStartupApps(self):
        """Return registry startup entries and Startup-folder items."""
        if platform.system() != "Windows":
            return []
        import winreg
        apps = []
        seen = set()
        disabled_prefix = "JohnsFixerDisabled::"
        locations = [
            ("HKCU", r"Software\Microsoft\Windows\CurrentVersion\Run"),
            ("HKLM", r"Software\Microsoft\Windows\CurrentVersion\Run"),
        ]

        for hive_name, path in locations:
            for view_label, view_flag in self._startup_views():
                try:
                    with winreg.OpenKey(self._startup_hive(hive_name), path, 0, winreg.KEY_READ | view_flag) as key:
                        index = 0
                        while True:
                            try:
                                name, value, _ = winreg.EnumValue(key, index)
                                index += 1
                            except OSError:
                                break
                            legacy = name.startswith(disabled_prefix)
                            display_name = name[len(disabled_prefix):] if legacy else name
                            signature = (display_name.lower(), str(value).lower())
                            if not display_name or signature in seen:
                                continue
                            seen.add(signature)
                            approval_source = "Run32" if view_label == "32-bit" else "Run"
                            approval = self._read_startup_approval(hive_name, approval_source, display_name, view_flag)
                            if approval is None and approval_source == "Run32":
                                approval = self._read_startup_approval(hive_name, "Run", display_name, view_flag)
                            apps.append({
                                "id": json.dumps({
                                    "kind": "legacy" if legacy else "registry",
                                    "hive": hive_name, "path": path, "name": display_name,
                                    "view": view_label, "viewFlag": view_flag,
                                    "approvalSource": approval_source,
                                }),
                                "name": display_name,
                                "source": "Startup apps",
                                "detail": "Starts when you sign in",
                                "impactLabel": self._startup_impact_for(display_name, value)["label"],
                                "impactDetail": self._startup_impact_for(display_name, value)["detail"],
                                "enabled": False if legacy else self._startup_is_enabled(approval),
                                "canDisable": True,
                            })
                except OSError:
                    continue

        for hive_name, folder in self._startup_folder_paths():
            if not os.path.isdir(folder):
                continue
            try:
                entries = sorted(os.scandir(folder), key=lambda item: item.name.lower())
            except OSError:
                continue
            for entry in entries:
                if not entry.is_file() or os.path.splitext(entry.name)[1].lower() not in {".lnk", ".url", ".exe", ".bat", ".cmd"}:
                    continue
                signature = (entry.name.lower(), os.path.abspath(folder).lower())
                if signature in seen:
                    continue
                seen.add(signature)
                approval = self._read_startup_approval(hive_name, "StartupFolder", entry.name)
                apps.append({
                    "id": json.dumps({"kind": "folder", "hive": hive_name, "path": os.path.abspath(entry.path), "name": entry.name}),
                    "name": os.path.splitext(entry.name)[0],
                    "source": "Startup folder",
                    "detail": "Starts when you sign in",
                    "impactLabel": self._startup_impact_for(entry.name, entry.path)["label"],
                    "impactDetail": self._startup_impact_for(entry.name, entry.path)["detail"],
                    "enabled": self._startup_is_enabled(approval),
                    "canDisable": True,
                })

        apps.sort(key=lambda app: (not app["enabled"], app["name"].lower()))
        return apps

    @pyqtSlot(str, bool)
    def setStartupAppEnabled(self, appId, enabled):
        if platform.system() != "Windows":
            self.logMessage.emit("Startup changes are available on Windows.")
            return
        name = "startup app"
        try:
            import winreg
            entry = json.loads(appId)
            if isinstance(entry, list):
                entry = {"kind": "legacy", "hive": entry[0], "path": entry[1], "name": entry[2]}
            kind = entry.get("kind")
            hive_name = entry.get("hive")
            name = entry.get("name", name)
            if kind == "registry":
                if "CurrentVersion\\Run" not in entry.get("path", ""):
                    raise ValueError("unsupported startup entry")
                self._set_startup_approval(
                    hive_name, entry.get("approvalSource", "Run"), name, enabled,
                    int(entry.get("viewFlag", 0))
                )
            elif kind == "folder":
                path = os.path.abspath(entry.get("path", ""))
                if not os.path.isfile(path):
                    raise ValueError("startup item no longer exists")
                self._set_startup_approval(hive_name, "StartupFolder", os.path.basename(path), enabled)
            elif kind == "legacy":
                hive = self._startup_hive(hive_name)
                path = entry.get("path", "")
                prefix = "JohnsFixerDisabled::"
                with winreg.OpenKey(hive, path, 0, winreg.KEY_READ | winreg.KEY_WRITE) as key:
                    if enabled:
                        value, value_type = winreg.QueryValueEx(key, prefix + name)
                        winreg.SetValueEx(key, name, 0, value_type, value)
                        winreg.DeleteValue(key, prefix + name)
                    else:
                        value, value_type = winreg.QueryValueEx(key, name)
                        winreg.SetValueEx(key, prefix + name, 0, value_type, value)
                        winreg.DeleteValue(key, name)
            else:
                raise ValueError("unsupported startup entry")
            self.logMessage.emit(f"{'Enabled' if enabled else 'Disabled'} {name}")
            self.startupAppsChanged.emit()
        except PermissionError:
            self.logMessage.emit("Windows permission is required for this startup app.")
        except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
            self.logMessage.emit(f"Could not change {name}: {exc}")

    # ------------------------------------------------------------------ #
    # Microsoft Store background applications
    # ------------------------------------------------------------------ #

    @staticmethod
    def _background_recommendation(package_name, display_name):
        text = f"{package_name} {display_name}".lower()
        keep_patterns = (
            "security", "defender", "onedrive", "outlook", "mail", "calendar",
            "teams", "phone link", "phonecompanion", "backup", "authenticator",
        )
        optional_patterns = (
            "xbox", "clipchamp", "solitaire", "bingnews", "bing news",
            "feedback hub", "feedbackhub", "cortana", "mixed reality", "3d viewer",
            "zunemusic", "zunevideo", "tiktok", "netflix", "disney", "spotify",
        )
        if any(pattern in text for pattern in keep_patterns):
            return "Suggested: Keep on", "May support sync, messages, or security alerts"
        if any(pattern in text for pattern in optional_patterns):
            return "Suggested: Usually optional", "Often used for games, media, or suggestions"
        return "Suggested: Review", "Choose based on how you use this app"

    @staticmethod
    def _format_background_apps(rows):
        apps = []
        if isinstance(rows, dict):
            rows = [rows]
        for app in rows or []:
            package_name = str(app.get("Name", "")).strip()
            family = str(app.get("PackageFamilyName", "")).strip()
            name = str(app.get("DisplayName", "")).strip() or SystemOptimizer._friendly_package_name(package_name)
            if not family:
                continue
            recommendation, recommendation_detail = SystemOptimizer._background_recommendation(
                package_name, name
            )
            apps.append({
                "id": family,
                "name": name,
                "source": "Installed app",
                "detail": "Can run in the background",
                "recommendationLabel": recommendation,
                "recommendationDetail": recommendation_detail,
                "enabled": SystemOptimizer._background_enabled(family),
                "canDisable": True,
            })
        apps.sort(key=lambda app: app["name"].lower())
        return apps

    @pyqtProperty(bool, notify=backgroundAppsLoadingChanged)
    def backgroundAppsLoading(self):
        return self._backgroundAppsLoading

    @pyqtSlot()
    def refreshBackgroundApps(self):
        """Discover Store apps without blocking the QML thread."""
        if platform.system() != "Windows":
            self._backgroundAppsLoading = False
            self.backgroundAppsLoadingChanged.emit()
            self._backgroundAppsCache = []
            self.backgroundAppsChanged.emit()
            return
        if self._backgroundProcess is not None and self._backgroundProcess.state() != QProcess.ProcessState.NotRunning:
            return
        self._backgroundAppsLoading = True
        self.backgroundAppsLoadingChanged.emit()
        command = (
            "$start = @(Get-StartApps); "
            "Get-AppxPackage | Where-Object { -not $_.IsFramework -and $_.PackageFamilyName } | "
            "ForEach-Object { $pkg = $_; $match = $start | Where-Object { $_.AppID -like (($pkg.PackageFamilyName + '!') + '*') } | Select-Object -First 1; "
            "if ($match) { $display = $match.Name } else { $display = $pkg.Name }; "
            "[pscustomobject]@{ Name = $pkg.Name; PackageFamilyName = $pkg.PackageFamilyName; DisplayName = $display } } | "
            "ConvertTo-Json -Compress"
        )
        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._backgroundProcess = process
        process.finished.connect(
            lambda code, status, p=process: self._onBackgroundDiscoveryFinished(p, code)
        )
        process.errorOccurred.connect(
            lambda err, p=process: self._onBackgroundDiscoveryFinished(p, -1)
            if err == QProcess.ProcessError.FailedToStart else None
        )
        process.start(
            "powershell",
            ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
        )

    def _onBackgroundDiscoveryFinished(self, process, code):
        output = bytes(process.readAllStandardOutput()).decode("utf-8", errors="replace").strip()
        if code == 0 and output:
            try:
                self._backgroundAppsCache = self._format_background_apps(json.loads(output))
            except json.JSONDecodeError:
                self._backgroundAppsCache = []
        else:
            self._backgroundAppsCache = []
            self.logMessage.emit("Could not read installed apps")
        self._backgroundProcess = None
        self._backgroundAppsLoading = False
        self.backgroundAppsLoadingChanged.emit()
        process.deleteLater()
        self.backgroundAppsChanged.emit()

    @staticmethod
    def _background_enabled(packageFamilyName):
        try:
            import winreg
            path = rf"Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\{packageFamilyName}"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, path) as key:
                disabled, _ = winreg.QueryValueEx(key, "Disabled")
                return int(disabled) != 1
        except (ImportError, OSError, ValueError, TypeError):
            return True

    @pyqtSlot(result=list)
    def getBackgroundApps(self):
        return self._backgroundAppsCache

    @pyqtSlot(str, bool)
    def setBackgroundAppEnabled(self, packageFamilyName, enabled):
        if platform.system() != "Windows":
            self.logMessage.emit("Background settings are available on Windows.")
            return
        try:
            import winreg
            if not packageFamilyName or any(char in packageFamilyName for char in "\\/:\"'"):
                raise ValueError("invalid app identifier")
            path = rf"Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\{packageFamilyName}"
            with winreg.CreateKey(winreg.HKEY_CURRENT_USER, path) as key:
                winreg.SetValueEx(key, "Disabled", 0, winreg.REG_DWORD, 0 if enabled else 1)
            self.logMessage.emit(f"{'Allowed' if enabled else 'Blocked'} background activity")
            self.backgroundAppsChanged.emit()
        except PermissionError:
            self.logMessage.emit("Could not change background activity")
        except (OSError, ValueError) as exc:
            self.logMessage.emit(f"Could not change background activity: {exc}")

    # ------------------------------------------------------------------ #
    # Debloat: preinstalled app removal (per-user, reversible via Store)
    # ------------------------------------------------------------------ #

    @staticmethod
    def _debloat_matches(entry, installed_names):
        patterns = [str(entry.get("name", "")).lower()]
        patterns += [str(m).lower() for m in entry.get("matches", [])]
        for installed in installed_names:
            lowered = installed.lower()
            for pattern in patterns:
                if pattern and pattern in lowered:
                    return True
        return False

    @staticmethod
    def _debloat_app_state(entry, installed):
        return {
            "id": entry.get("name", ""),
            "name": entry.get("label", entry.get("name", "")),
            "level": entry.get("level", "Optional"),
            "reason": entry.get("reason", ""),
            "installed": bool(installed),
        }

    @pyqtSlot(result=list)
    def getDebloatApps(self):
        return self._debloatAppsCache

    @pyqtProperty(bool, notify=debloatAppsLoadingChanged)
    def debloatAppsLoading(self):
        return self._debloatAppsLoading

    @pyqtProperty(bool, notify=debloatRemovingChanged)
    def debloatRemoving(self):
        return self._debloating

    @pyqtSlot()
    def refreshDebloatApps(self):
        """Enumerate installed Store apps and mark catalog entries as present."""
        if platform.system() != "Windows":
            self._debloatAppsCache = [
                self._debloat_app_state(entry, False) for entry in self.DEBLOAT_CATALOG
            ]
            self.debloatAppsChanged.emit()
            return
        if self._debloatProcess is not None and self._debloatProcess.state() != QProcess.ProcessState.NotRunning:
            return
        self._debloatAppsLoading = True
        self.debloatAppsLoadingChanged.emit()
        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._debloatProcess = process
        process.finished.connect(
            lambda code, status, p=process: self._onDebloatDiscoveryFinished(p, code)
        )
        process.errorOccurred.connect(
            lambda err, p=process: self._onDebloatDiscoveryFinished(p, -1)
            if err == QProcess.ProcessError.FailedToStart else None
        )
        process.start(
            "powershell",
            ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
             "Get-AppxPackage | ForEach-Object { $_.Name } | Sort-Object -Unique"],
        )

    def _onDebloatDiscoveryFinished(self, process, code):
        output = bytes(process.readAllStandardOutput()).decode("utf-8", errors="replace")
        installed = {line.strip().lower() for line in output.splitlines() if line.strip()}
        cache = [
            self._debloat_app_state(entry, self._debloat_matches(entry, installed))
            for entry in self.DEBLOAT_CATALOG
        ]
        self._debloatAppsCache = cache
        self._debloatProcess = None
        self._debloatAppsLoading = False
        self.debloatAppsLoadingChanged.emit()
        process.deleteLater()
        self.debloatAppsChanged.emit()

    @pyqtSlot(list)
    def removeDebloatApps(self, names):
        """Remove the selected apps one at a time (current user only).

        Removed apps can be reinstalled from the Microsoft Store, which keeps
        this action reversible without needing a full system backup.
        """
        if self._debloating:
            self.logMessage.emit("App removal is already running.")
            return
        if platform.system() != "Windows":
            self.logMessage.emit("App removal is available on Windows.")
            return
        clean = []
        for name in names or []:
            name = str(name).strip()
            if name and not any(char in name for char in "\\/:*?\"<>|"):
                clean.append(name)
        if not clean:
            self.logMessage.emit("No apps selected to remove.")
            return
        self._debloating = True
        self._debloatQueue = clean
        self._debloatDone = 0
        self._debloatFailed = 0
        self.debloatRemovingChanged.emit()
        self.debloatRemovalProgress.emit(0, "Removing selected apps")
        QTimer.singleShot(0, self._applyNextDebloatRemoval)

    def _applyNextDebloatRemoval(self, code=0):
        if code != 0:
            self._debloatFailed += 1
        
        if self._debloatDone >= len(self._debloatQueue):
            self._debloating = False
            self.debloatRemovingChanged.emit()
            self.debloatRemovalProgress.emit(100, "Removal complete")
            if self._debloatFailed:
                self.logMessage.emit(f"App removal finished with {self._debloatFailed} failure(s)")
            else:
                self.logMessage.emit("App removal complete")
            self.refreshDebloatApps()
            return
        name = self._debloatQueue[self._debloatDone]
        self._debloatDone += 1
        percent = int(self._debloatDone / len(self._debloatQueue) * 100)
        self.debloatRemovalProgress.emit(percent, f"Removing {self._debloatDone} of {len(self._debloatQueue)}")
        safe_name = str(name).replace("'", "''")
        command = (
            "$ErrorActionPreference = 'Stop'; "
            f"$package = Get-AppxPackage -Name '{safe_name}' -ErrorAction Stop; "
            "if (-not $package) { throw 'Package is not installed' }; "
            "$package | Remove-AppxPackage -ErrorAction Stop"
        )
        self.runPowerShell(f"Remove {name}", command, timeout=180, onFinished=self._applyNextDebloatRemoval)

    # ------------------------------------------------------------------ #
    # System info (Windows-focused; degrades gracefully elsewhere)
    # ------------------------------------------------------------------ #

    @pyqtSlot(result=str)
    def getWindowsVersion(self):
        try:
            if platform.system() != "Windows":
                return "Windows"
            release = platform.release()
            version = platform.version()  # e.g. "10.0.22631.XXXX"
            build = 0
            parts = version.split(".")
            if len(parts) >= 3 and parts[2].isdigit():
                build = int(parts[2])
            if release == "10" and build >= 22000:
                return "Windows 11"
            return f"Windows {release}"
        except Exception:
            return "Windows"

    @pyqtSlot(result=str)
    def getCPUInfo(self):
        try:
            if platform.system() == "Windows":
                import winreg
                with winreg.OpenKey(
                    winreg.HKEY_LOCAL_MACHINE,
                    r"HARDWARE\DESCRIPTION\System\CentralProcessor\0",
                ) as key:
                    name, _ = winreg.QueryValueEx(key, "ProcessorNameString")
                    if name and name.strip():
                        return name.strip()
            return platform.processor() or "Unknown CPU"
        except Exception:
            return "Unknown CPU"

    @pyqtSlot(result=str)
    def getGraphicsInfo(self):
        try:
            if HAS_GPU:
                gpus = GPUtil.getGPUs()
                if gpus:
                    return gpus[0].name
            # GPUtil only sees NVIDIA GPUs; fall back to the Windows display
            # adapter registry key so AMD/Intel or GPUtil-less systems still
            # show the real card name.
            if platform.system() == "Windows":
                import winreg
                with winreg.OpenKey(
                    winreg.HKEY_LOCAL_MACHINE,
                    r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000",
                ) as key:
                    name, _ = winreg.QueryValueEx(key, "DriverDesc")
                    if name and name.strip():
                        return name.strip()
            return "No GPU detected"
        except Exception:
            return "Unknown GPU"

    @pyqtSlot(result=str)
    def getRAMInfo(self):
        try:
            return f"{psutil.virtual_memory().total / (1024 ** 3):.1f} GB RAM"
        except Exception:
            return "Unknown RAM"

    @pyqtSlot(result=str)
    def getStorageInfo(self):
        try:
            return f"{psutil.disk_usage('C:\\').percent:.0f}% used"
        except Exception:
            return "Unknown"

    @pyqtSlot(result=int)
    def getMemoryUsedPercent(self):
        try:
            return int(psutil.virtual_memory().percent)
        except Exception:
            return 0

    @pyqtSlot(result=int)
    def getStorageUsedPercent(self):
        try:
            return int(psutil.disk_usage('C:\\').percent)
        except Exception:
            return 0

    @pyqtSlot(result=str)
    def getUptime(self):
        try:
            seconds = int(time.time() - psutil.boot_time())
            hours, minutes = seconds // 3600, (seconds % 3600) // 60
            if hours >= 24:
                return f"{hours // 24}d {hours % 24}h"
            return f"{hours}h {minutes}m"
        except Exception:
            return "Unknown"

    @pyqtSlot(result=str)
    def getAppliedTweaksCount(self):
        preset = self._tweaksData.get("presets", {}).get(self.selectedPreset, {})
        keys = [
            key for key in preset.get("tweaks", [])
            if key in self._tweaksData and self._determineControlType(self._tweaksData[key]) == "toggle"
        ]
        if not keys:
            return "0%"
        applied = sum(1 for key in keys if self._toggleStates.get(key, False))
        return f"{int(applied / len(keys) * 100)}%"

    # ------------------------------------------------------------------ #
    # Applied-state detection (Windows only; safe fallback elsewhere)
    # ------------------------------------------------------------------ #

    def _refreshAppliedStates(self):
        # Replace stale toggle values with the actual registry state.
        # Only reversible toggles have a meaningful "applied" state; one-shot
        # buttons and visual-effects selectors must never be forced into the
        # toggle map (they have no undo history here).
        if platform.system() != "Windows":
            return
        for key in set(self.OPTIMIZE_TWEAKS + [
            key for preset in self._tweaksData.get("presets", {}).values()
            for key in preset.get("tweaks", [])
        ]):
            tweak = self._tweaksData.get(key)
            if not tweak or self._determineControlType(tweak) != "toggle":
                continue
            applied = self._isTweakApplied(key)
            if self._toggleStates.get(key, False) != applied:
                self._toggleStates[key] = applied
                self.toggleStateChanged.emit(key, applied)

    def _isTweakApplied(self, tweakKey):
        tweak = self._tweaksData.get(tweakKey)
        if not tweak:
            return False

        registry = tweak.get("registry") or []
        if registry:
            for entry in registry:
                current = self._readRegistryValue(
                    entry.get("Path", ""), entry.get("Name", "")
                )
                if current is None or str(current).lower() != str(entry.get("Value", "")).lower():
                    return False
            return True

        services = tweak.get("service") or []
        if services:
            for entry in services:
                expected = self.START_TYPES.get(entry.get("StartupType", ""))
                if expected is None:
                    return False
                current = self._getServiceStartType(entry.get("Name", ""))
                if current != expected:
                    return False
            return True

        # Script-only tweaks cannot be detected reliably.
        return False

    @staticmethod
    def _readRegistryValue(path, name):
        try:
            import winreg
            roots = {
                "HKLM": winreg.HKEY_LOCAL_MACHINE,
                "HKCU": winreg.HKEY_CURRENT_USER,
            }
            root, _, sub = path.partition(":")
            hive = roots.get(root.strip().upper())
            if hive is None:
                return None
            with winreg.OpenKey(hive, sub.lstrip("\\")) as key:
                value, _ = winreg.QueryValueEx(key, name)
                return value
        except Exception:
            return None

    @staticmethod
    def _getServiceStartType(name):
        try:
            import win32service
            scm = win32service.OpenSCManager(None, None, win32service.SC_MANAGER_CONNECT)
            try:
                handle = win32service.OpenService(scm, name, win32service.SERVICE_QUERY_CONFIG)
                try:
                    return win32service.QueryServiceConfig(handle)[1]
                finally:
                    win32service.CloseServiceHandle(handle)
            finally:
                win32service.CloseServiceHandle(scm)
        except Exception:
            return None

    # ------------------------------------------------------------------ #
    # Optimization (non-blocking: advances when each command completes)
    # ------------------------------------------------------------------ #

    @pyqtProperty(bool, notify=isOptimizingChanged)
    def isOptimizing(self):
        return self._isOptimizing

    @pyqtSlot()
    def runOptimization(self):
        if self._isOptimizing:
            return
        presetName = self.selectedPreset
        preset = self._tweaksData.get("presets", {}).get(presetName, {})
        if not preset:
            self.logMessage.emit(f"The {presetName} preset is unavailable.")
            return
        self._optimizeQueue = [
            key for key in preset.get("tweaks", []) if key in self._tweaksData
        ]
        skipped = [
            (key, not self._isTweakSupported(key))
            for key in self._optimizeQueue
        ]
        skipped_keys = [key for key, unsupported in skipped if unsupported]
        for key in skipped_keys:
            name = self._shortTweakName(self._tweaksData[key].get("Content", key))
            if self._tweakSupportReason(key) == "admin":
                self.logMessage.emit(f"Skipped {name} — needs administrator permission (restart elevated to enable)")
            else:
                self.logMessage.emit(f"Skipped {name} — not supported on this PC")
        self._optimizeQueue = [key for key, unsupported in skipped if not unsupported]
        if not self._optimizeQueue:
            self.logMessage.emit("No supported optimization steps are available.")
            return

        self._optimizeTotal = len(self._optimizeQueue)
        self._optimizeDone = 0
        self._optimizeAppliedKeys = set()
        self._optimizeCurrentKey = ""
        self._isOptimizing = True
        self.isOptimizingChanged.emit()
        self.logMessage.emit(f"Starting {presetName} optimization")
        self.optimizationProgress.emit(0, f"Starting {presetName} optimization")
        QTimer.singleShot(0, self._applyNextOptimizationTweak)

    def _markPresetApplied(self):
        # Only tweaks whose command actually succeeded are marked applied.
        # _refreshAppliedStates() above already reconciled the registry, so
        # this only fills in steps that ran cleanly but have no detectable
        # registry state (e.g. script-only tweaks).
        for key in self._optimizeAppliedKeys:
            tweak = self._tweaksData.get(key)
            if not tweak or self._determineControlType(tweak) != "toggle":
                continue
            if not self._toggleStates.get(key, False):
                self._toggleStates[key] = True
                self.toggleStateChanged.emit(key, True)

    def _applyNextOptimizationTweak(self):
        if self._optimizeDone >= self._optimizeTotal:
            self._isOptimizing = False
            self._refreshAppliedStates()
            self._markPresetApplied()
            self.isOptimizingChanged.emit()
            self.optimizationProgress.emit(100, "Optimization complete")
            self.optimizationComplete.emit()
            return

        key = self._optimizeQueue[self._optimizeDone]
        self._optimizeDone += 1
        tweak = self._tweaksData.get(key)
        name = self._shortTweakName(tweak.get("Content", key) if tweak else key)
        percent = int(self._optimizeDone / self._optimizeTotal * 100)
        self.optimizationProgress.emit(percent, f"Applying {name}")

        # The queue advances only when this tweak's commands finish, so
        # slow commands never overlap the next one.  Each step's outcome is
        # recorded in _onProcessFinished (keyed by _optimizeCurrentKey), so
        # failed commands are never marked as applied on the Home screen.
        self._optimizeCurrentKey = key
        continuation = self._continueOptimization
        if self._determineControlType(tweak) == "select":
            option_key = tweak.get("PresetOption", tweak.get("DefaultOption", ""))
            self.executeTweakOption(key, option_key, onFinished=continuation)
        else:
            self.executeTweak(key, True, onFinished=continuation)

    def _continueOptimization(self, code=0):
        self._applyNextOptimizationTweak()

    @staticmethod
    def _shortTweakName(content):
        """Turn data labels into short, readable progress text."""
        return str(content).split(" - ", 1)[0].strip() or "tweak"

    # ------------------------------------------------------------------ #
    # Tweak execution
    # ------------------------------------------------------------------ #

    @pyqtSlot(str, bool)
    def executeTweak(self, tweakKey, enable, onFinished=None):
        tweak = self._tweaksData.get(tweakKey)
        if not tweak:
            self.logMessage.emit("That setting is unavailable.")
            if onFinished:
                onFinished(-1)
            return
        if self._adminBlocked(tweakKey):
            self.logMessage.emit(
                f"{tweak.get('Content', tweakKey)} needs administrator permission — restart elevated to apply it."
            )
            if onFinished:
                onFinished(-1)
            return
        if enable and self._determineControlType(tweak) == "toggle":
            self._captureToggleSnapshot(tweakKey)
        script = self.buildScriptFromTweak(tweak, enable)
        timeout = int(tweak.get("Timeout", DEFAULT_TIMEOUT))
        if script:
            action = f"{tweak.get('Content', tweakKey)} ({'apply' if enable else 'revert'})"

            def finished(code):
                if code == 0:
                    self._toggleStates[tweakKey] = bool(enable)
                    self.toggleStateChanged.emit(tweakKey, bool(enable))
                    self._refreshAppliedStates()
                    if not enable:
                        self._settings.remove(f"revert/{tweakKey}")
                        self._settings.sync()
                if onFinished:
                    onFinished(code)

            self.runPowerShell(action, script, timeout=timeout, onFinished=finished)
        else:
            self.logMessage.emit("That setting has no action available.")
            if onFinished:
                onFinished(-1)

    @pyqtSlot(str)
    def executeTweakOnce(self, tweakKey):
        tweak = self._tweaksData.get(tweakKey)
        if tweak and self._adminBlocked(tweakKey):
            self.logMessage.emit(
                f"{tweak.get('Content', tweakKey)} needs administrator permission — restart elevated to apply it."
            )
            return
        self.executeTweak(tweakKey, True)

    def executeTweakOption(self, tweakKey, optionKey, onFinished=None):
        tweak = self._tweaksData.get(tweakKey)
        if not tweak:
            self.logMessage.emit("That setting is unavailable.")
            if onFinished:
                onFinished(-1)
            return
        option = next((item for item in tweak.get("Options", []) if item.get("key") == optionKey), None)
        if not option:
            self.logMessage.emit("That visual-effects option is unavailable.")
            if onFinished:
                onFinished(-1)
            return
        if self._adminBlocked(tweakKey):
            self.logMessage.emit(
                f"{tweak.get('Content', tweakKey)} needs administrator permission — restart elevated to apply it."
            )
            if onFinished:
                onFinished(-1)
            return
        script = self.buildScriptFromOption(tweak, option)
        action = f"{tweak.get('Content', tweakKey)}: {option.get('label', optionKey)}"
        self.runPowerShell(
            action,
            script,
            timeout=int(tweak.get("Timeout", DEFAULT_TIMEOUT)),
            onFinished=onFinished,
        )

    @pyqtSlot(str, str)
    def setTweakOption(self, tweakKey, optionKey):
        tweak = self._tweaksData.get(tweakKey)
        if not tweak or self._determineControlType(tweak) != "select":
            self.logMessage.emit("That setting is unavailable.")
            return
        if not any(item.get("key") == optionKey for item in tweak.get("Options", [])):
            return

        def finished(code):
            if code == 0:
                self._optionStates[tweakKey] = optionKey
                self.optionStateChanged.emit(tweakKey, optionKey)

        self.executeTweakOption(tweakKey, optionKey, onFinished=finished)

    @pyqtSlot(str, bool)
    def setToggleState(self, tweakKey, enabled):
        if tweakKey not in self._tweaksData:
            self.logMessage.emit("That setting is unavailable.")
            return
        if self._adminBlocked(tweakKey):
            self.logMessage.emit(
                f"{self._tweaksData[tweakKey].get('Content', tweakKey)} needs administrator permission — restart elevated to apply it."
            )
            return
        # Do not optimistically move the switch. The backend is the source of
        # truth; a failed PowerShell command must leave the control unchanged.
        self.executeTweak(tweakKey, bool(enabled))

    @pyqtSlot()
    def createRestorePoint(self):
        if platform.system() != "Windows":
            self.logMessage.emit("Restore points are available on Windows.")
            return
        if not self._isAdmin:
            self.logMessage.emit("Create a restore point from an Administrator session.")
            return
        self.runPowerShell(
            "Create restore point",
            "Checkpoint-Computer -Description 'JohnsWindowsFixer' -RestorePointType 'MODIFY_SETTINGS'",
            timeout=120,
        )

    restorePointPromptChanged = pyqtSignal()
    adminPromptChanged = pyqtSignal()

    @pyqtProperty(bool, notify=adminPromptChanged)
    def adminPromptVisible(self):
        return self._adminPromptVisible

    @adminPromptVisible.setter
    def adminPromptVisible(self, value):
        value = bool(value)
        if self._adminPromptVisible == value:
            return
        self._adminPromptVisible = value
        self.adminPromptChanged.emit()

    @pyqtSlot()
    def dismissAdminPrompt(self):
        self._adminPromptVisible = False
        self.adminPromptChanged.emit()

    @pyqtSlot()
    def restartAsAdminFromPrompt(self):
        self._adminPromptVisible = False
        self.adminPromptChanged.emit()
        self.restartAsAdmin()

    @pyqtProperty(bool, notify=restorePointPromptChanged)
    def restorePointPromptVisible(self):
        return self._restorePointPromptVisible

    @restorePointPromptVisible.setter
    def restorePointPromptVisible(self, value):
        value = bool(value)
        if self._restorePointPromptVisible == value:
            return
        self._restorePointPromptVisible = value
        self.restorePointPromptChanged.emit()

    @pyqtSlot()
    def dismissRestorePointPrompt(self):
        self._restorePointPromptVisible = False
        self.restorePointPromptChanged.emit()

    @pyqtSlot()
    def createRestorePointFromPrompt(self):
        self._restorePointPromptVisible = False
        self.restorePointPromptChanged.emit()
        self.createRestorePoint()

    # ------------------------------------------------------------------ #
    # Async PowerShell runner (QProcess, non-blocking)
    # ------------------------------------------------------------------ #

    def runPowerShell(self, actionName, psCommand, timeout=DEFAULT_TIMEOUT, onFinished=None):
        self.logMessage.emit(f"Running: {actionName}")

        proc = QProcess(self)
        proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._runningProcesses.add(proc)
        completion = [False]

        def finish_once(code):
            # A process that never started (missing powershell) emits
            # errorOccurred but never finished; without this, the
            # optimization queue would stall forever.
            if completion[0]:
                return
            completion[0] = True
            self._onProcessFinished(proc, code, actionName, onFinished)

        if timeout and timeout > 0:
            killer = QTimer(proc)
            killer.setSingleShot(True)
            killer.setInterval(timeout * 1000)
            killer.timeout.connect(
                lambda p=proc, a=actionName, k=killer: self._onProcessTimeout(p, a, k)
            )
            killer.start()

        proc.finished.connect(
            lambda code, status, p=proc: finish_once(code)
        )
        proc.errorOccurred.connect(
            lambda err, p=proc: finish_once(-1)
            if err == QProcess.ProcessError.FailedToStart else None
        )
        proc.readyReadStandardOutput.connect(
            lambda p=proc, a=actionName: self._onProcessOutput(p, a)
        )
        proc.start(
            "powershell",
            ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", psCommand],
        )

    def _onProcessOutput(self, proc, actionName):
        try:
            chunk = bytes(proc.readAllStandardOutput()).decode("utf-8", errors="replace")
        except Exception:
            return
        for line in chunk.splitlines():
            line = line.strip()
            if line:
                self.logMessage.emit(f"  {line}")

    def _onProcessTimeout(self, proc, actionName, killer):
        if proc.state() != QProcess.ProcessState.NotRunning:
            self.logMessage.emit(f"Timed out: {actionName}")
            # Killing is enough: the finished signal still fires afterwards and
            # drives cleanup + the optimization continuation. Waiting here
            # would freeze the UI for up to the wait timeout.
            proc.kill()

    def _onProcessFinished(self, proc, code, actionName, onFinished):
        self._runningProcesses.discard(proc)
        output = bytes(proc.readAllStandardOutput()).decode("utf-8", errors="replace").strip()
        if code == 0:
            self.logMessage.emit(f"Done: {actionName}")
            if output:
                self.logMessage.emit(f"  {output}")
        else:
            self.logMessage.emit(f"Could not complete: {actionName}")
            if output:
                self.logMessage.emit(f"  {output}")
        proc.deleteLater()
        if self._isOptimizing and self._optimizeCurrentKey and code == 0:
            self._optimizeAppliedKeys.add(self._optimizeCurrentKey)
        if onFinished:
            onFinished(code)

    # ------------------------------------------------------------------ #
    # Reversible toggle snapshots
    # ------------------------------------------------------------------ #

    @staticmethod
    def _registry_path_parts(path):
        root, separator, subpath = str(path or "").partition(":")
        roots = {
            "HKLM": "HKEY_LOCAL_MACHINE",
            "HKCU": "HKEY_CURRENT_USER",
        }
        return roots.get(root.strip().upper()), subpath.lstrip("\\") if separator else ""

    @staticmethod
    def _registry_value_type_name(value_type):
        try:
            import winreg
            return {
                winreg.REG_SZ: "String",
                winreg.REG_EXPAND_SZ: "ExpandString",
                winreg.REG_BINARY: "Binary",
                winreg.REG_DWORD: "DWord",
                winreg.REG_QWORD: "QWord",
                winreg.REG_MULTI_SZ: "MultiString",
            }.get(value_type, "String")
        except ImportError:
            return "String"

    @staticmethod
    def _powershell_quote(value):
        return "'" + str(value).replace("'", "''") + "'"

    @classmethod
    def _powershell_value(cls, value, value_type):
        if value_type in {"DWord", "QWord"}:
            return str(int(value))
        if value_type == "Binary":
            return "[byte[]](" + ",".join(str(int(item)) for item in value) + ")"
        if value_type == "MultiString":
            return "@(" + ",".join(cls._powershell_quote(item) for item in value) + ")"
        return cls._powershell_quote(value)

    def _readRegistryState(self, path, name):
        try:
            import winreg
            root_name, subpath = self._registry_path_parts(path)
            hive = {
                "HKEY_LOCAL_MACHINE": winreg.HKEY_LOCAL_MACHINE,
                "HKEY_CURRENT_USER": winreg.HKEY_CURRENT_USER,
            }.get(root_name)
            if hive is None:
                return {"exists": False}
            with winreg.OpenKey(hive, subpath) as key:
                value, value_type = winreg.QueryValueEx(key, name)
            if isinstance(value, bytes):
                value = list(value)
            elif isinstance(value, tuple):
                value = list(value)
            return {
                "exists": True,
                "type": self._registry_value_type_name(value_type),
                "value": value,
            }
        except (ImportError, OSError, TypeError, ValueError):
            return {"exists": False}

    def _getServiceStartTypeName(self, name):
        if platform.system() != "Windows" or not name:
            return None
        try:
            result = subprocess.run(
                ["sc.exe", "qc", name], capture_output=True, text=True,
                timeout=10, check=False,
            )
            match = re.search(r"START_TYPE\\s*:\\s*\\d+\\s+(\\w+)", result.stdout)
            if not match:
                return None
            return {
                "BOOT_START": "Boot",
                "SYSTEM_START": "System",
                "AUTO_START": "Automatic",
                "DEMAND_START": "Manual",
                "DISABLED": "Disabled",
            }.get(match.group(1).upper())
        except (OSError, subprocess.TimeoutExpired):
            return None

    def _captureToggleSnapshot(self, tweakKey):
        if platform.system() != "Windows":
            return
        settings_key = f"revert/{tweakKey}"
        if self._settings.value(settings_key, "", type=str):
            return
        tweak = self._tweaksData.get(tweakKey, {})
        snapshot = {"registry": [], "services": []}
        for entry in tweak.get("registry", []):
            snapshot["registry"].append({
                "path": entry.get("Path", ""),
                "name": entry.get("Name", ""),
                "state": self._readRegistryState(entry.get("Path", ""), entry.get("Name", "")),
            })
        for entry in tweak.get("service", []):
            snapshot["services"].append({
                "name": entry.get("Name", ""),
                "startup": self._getServiceStartTypeName(entry.get("Name", "")),
            })
        self._settings.setValue(settings_key, json.dumps(snapshot))
        self._settings.sync()

    def _toggleSnapshot(self, tweakKey):
        raw = self._settings.value(f"revert/{tweakKey}", "", type=str)
        if not raw:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return None

    def _restoreSnapshotScript(self, tweak, snapshot):
        parts = []
        for item in snapshot.get("registry", []):
            path, name, state = item.get("path", ""), item.get("name", ""), item.get("state", {})
            if not path or not name or not state.get("exists"):
                parts.append(
                    f"Remove-ItemProperty -Path {self._powershell_quote(path)} -Name {self._powershell_quote(name)} -ErrorAction SilentlyContinue"
                )
                continue
            value_type = state.get("type", "String")
            value = self._powershell_value(state.get("value", ""), value_type)
            parts.append(
                f"if (!(Test-Path {self._powershell_quote(path)})) {{ New-Item -Path {self._powershell_quote(path)} -Force | Out-Null }}; "
                f"Set-ItemProperty -Path {self._powershell_quote(path)} -Name {self._powershell_quote(name)} -Value {value} -Type {value_type} -Force"
            )
        for item in snapshot.get("services", []):
            if item.get("name") and item.get("startup"):
                parts.append(
                    f"Set-Service -Name {self._powershell_quote(item['name'])} -StartupType {item['startup']}"
                )
        scripts = tweak.get("UndoScript", [])
        if isinstance(scripts, str):
            scripts = [scripts]
        parts.extend(scripts)
        return "; ".join(parts)

    # ------------------------------------------------------------------ #
    # Script building
    # ------------------------------------------------------------------ #

    def _determineControlType(self, tweak):
        # Data can explicitly choose a one-shot action even when an undo
        # script exists (for example, setting DNS is not a persistent toggle).
        explicit = tweak.get("ControlType", tweak.get("controlType", ""))
        if not explicit and str(tweak.get("Type", "")).lower() in {"button", "action"}:
            explicit = "button"
        if str(explicit).lower() in {"button", "action"}:
            return "button"
        if str(explicit).lower() in {"select", "choice", "options"}:
            return "select"
        if str(explicit).lower() == "toggle":
            return "toggle"

        # A tweak is a reversible toggle only if it defines a way to revert.
        for reg in tweak.get("registry", []):
            if "OriginalValue" in reg:
                return "toggle"
        for svc in tweak.get("service", []):
            if "OriginalType" in svc:
                return "toggle"
        if "UndoScript" in tweak:
            return "toggle"
        return "button"

    def buildScriptFromTweak(self, tweak, enable):
        parts = []
        tweakKey = next((key for key, value in self._tweaksData.items() if value is tweak), "")
        snapshot = self._toggleSnapshot(tweakKey) if not enable else None
        if snapshot:
            restored = self._restoreSnapshotScript(tweak, snapshot)
            if restored:
                return restored

        for reg in tweak.get("registry", []):
            path = reg.get("Path", "")
            name = reg.get("Name", "")
            valueType = reg.get("Type", "DWord")
            target = reg.get("Value", "") if enable else reg.get("OriginalValue", "")

            if not path or not name:
                continue
            if target == "<RemoveEntry>":
                parts.append(
                    f"Remove-ItemProperty -Path '{path}' -Name '{name}' -ErrorAction SilentlyContinue"
                )
                continue
            if valueType.lower() == "string":
                target = f"'{target}'"
            parts.append(
                f"if (!(Test-Path '{path}')) {{ New-Item -Path '{path}' -Force }}; "
                f"Set-ItemProperty -Path '{path}' -Name '{name}' -Value {target} -Type {valueType} -Force"
            )

        for svc in tweak.get("service", []):
            name = svc.get("Name", "")
            startup = svc.get("StartupType", "") if enable else svc.get("OriginalType", "")
            if name and startup:
                parts.append(f"Set-Service -Name '{name}' -StartupType {startup}")

        scripts = tweak.get("InvokeScript" if enable else "UndoScript", [])
        if isinstance(scripts, str):
            scripts = [scripts]
        parts.extend(scripts)

        return "; ".join(parts) if parts else ""

    def buildScriptFromOption(self, tweak, option):
        parts = []
        for reg in option.get("registry", []):
            path = reg.get("Path", "")
            name = reg.get("Name", "")
            value_type = reg.get("Type", "DWord")
            target = reg.get("Value", "")
            if not path or not name:
                continue
            if target == "<RemoveEntry>":
                parts.append(
                    f"Remove-ItemProperty -Path '{path}' -Name '{name}' -ErrorAction SilentlyContinue"
                )
                continue
            if value_type.lower() == "string":
                target = f"'{target}'"
            parts.append(
                f"if (!(Test-Path '{path}')) {{ New-Item -Path '{path}' -Force }}; "
                f"Set-ItemProperty -Path '{path}' -Name '{name}' -Value {target} -Type {value_type} -Force"
            )
        scripts = option.get("InvokeScript", [])
        if isinstance(scripts, str):
            scripts = [scripts]
        parts.extend(scripts)
        return "; ".join(parts) if parts else ""


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    qmlRegisterType(M3ExpressiveExactIndicator, "M3Loading", 1, 0, "M3ExpressiveIndicator")

    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    optimizer = SystemOptimizer()
    engine.rootContext().setContextProperty("optimizer", optimizer)

    try:
        optimizer.loadTweaksJson(os.path.join(APP_DIR, "newTweaks.json"))
    except Exception as exc:
        print(f"Failed to load tweaks: {exc}")

    engine.load(QUrl.fromLocalFile(os.path.join(APP_DIR, "main.qml")))
    if not engine.rootObjects():
        print("[ERROR] No QML root objects created")
        return -1

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
