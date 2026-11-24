import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import M3Loading 1.0

ApplicationWindow {
    id: window
    visible: true
    width: 1180
    height: 820
    minimumWidth: 900
    minimumHeight: 620
    title: "John's Windows Fixer"
    color: theme.mdBackground

    // Soft ambient glow in the upper-left, giving the dark surface depth.
    Rectangle {
        id: backgroundGradient
        anchors.fill: parent
        z: -1
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1E222C" }
            GradientStop { position: 0.45; color: theme.mdBackground }
            GradientStop { position: 1.0; color: theme.mdBackground }
        }
    }

    FontLoader {
        id: appFont
        source: "fonts/Roboto-Regular.woff2"
    }

    // ------------------------------------------------------------------ #
    // Material 3 Expressive tokens — dark baseline seeded from the
    // reference lime (#DFE278) on a deep neutral (#1A1C23).
    // ------------------------------------------------------------------ #
    QtObject {
        id: theme

        readonly property color mdBackground: "#1A1C23"
        readonly property color mdSurface: "#1E2129"
        readonly property color mdSurfaceHigh: "#2A2E3A"
        readonly property color mdSurfaceContainer: "#242833"
        readonly property color mdOnSurface: "#E6E8F2"
        readonly property color mdOnSurfaceVariant: "#C2C6D0"
        readonly property color mdPrimary: "#DFE278"
        readonly property color mdOnPrimary: "#2A3100"
        readonly property color mdPrimaryContainer: "#4A530F"
        readonly property color mdOnPrimaryContainer: "#ECF09B"
        readonly property color mdSecondary: "#C6C9A6"
        readonly property color mdOnSecondary: "#2F3313"
        readonly property color mdSecondaryContainer: "#474B2A"
        readonly property color mdOnSecondaryContainer: "#E4E8BC"
        readonly property color mdTertiary: "#A6D9C0"
        readonly property color mdOnTertiary: "#0E3827"
        readonly property color mdTertiaryContainer: "#2C5242"
        readonly property color mdOnTertiaryContainer: "#C1F2DC"
        readonly property color mdError: "#FFB4AB"
        readonly property color mdOnError: "#690005"
        readonly property color mdErrorContainer: "#93000A"
        readonly property color mdOnErrorContainer: "#FFDAD6"
        readonly property color mdOutline: "#8B909C"
        readonly property color mdOutlineVariant: "#43474F"

        // Expressive shape scale.
        readonly property real radiusSm: 12
        readonly property real radiusMd: 16
        readonly property real radiusLg: 24
        readonly property real radiusXl: 32
    }

    readonly property string fontFamily: appFont.status === FontLoader.Ready ? appFont.name : "Segoe UI"
    readonly property string monoFamily: "Consolas"

    property bool sidebarCollapsed: false
    property bool logExpanded: false

    property var categories: []
    property string currentCategory: "Home"
    property var tweaksList: []
    property var startupApps: []
    property var backgroundApps: []
    property var debloatApps: []
    property string appSearch: ""
    property string debloatSearch: ""
    property var debloatSelected: []
    property int debloatSelectedCount: 0
    property int debloatSelectionVersion: 0
    property int debloatRemovalPercent: 0
    property string debloatRemovalStatus: ""

    property int optimizationProgress: 0
    property string optimizationStatus: ""

    property string windowsVersion: "Windows"
    property string cpuInfo: "Unknown CPU"
    property string graphicsInfo: "Unknown GPU"
    property string ramInfo: "Unknown RAM"
    property string storageInfo: "Unknown"
    property string appliedTweaksInfo: "0%"
    property string uptimeInfo: "Unknown"
    property int memoryUsedPercent: 0
    property int storageUsedPercent: 0

    property real appliedPercent: {
        var v = parseFloat(appliedTweaksInfo)
        return isNaN(v) ? 0.0 : v / 100.0
    }

    ListModel {
        id: logModel
    }

    function loadTweaksForCategory(category) {
        currentCategory = category
        appSearch = ""
        if (category === "Startup") {
            startupApps = optimizer.getStartupApps()
            optimizer.refreshStartupImpactSettings()
            optimizer.refreshStartupImpact()
            tweaksList = []
        } else if (category === "Background") {
            backgroundApps = optimizer.getBackgroundApps()
            optimizer.refreshBackgroundApps()
            tweaksList = []
        } else if (category === "Debloat") {
            debloatApps = optimizer.getDebloatApps()
            optimizer.refreshDebloatApps()
            tweaksList = []
        } else {
            tweaksList = optimizer.getTweaksByCategory(category)
        }
    }

    function appsForPage() {
        var source = currentCategory === "Startup" ? startupApps : backgroundApps
        var query = appSearch.trim().toLowerCase()
        if (!query) return source
        return source.filter(function(app) {
            return String(app.name || "").toLowerCase().indexOf(query) >= 0
        })
    }

    function debloatAppsForPage() {
        // Only show apps that are actually installed, so the page reflects
        // what can really be removed.  The search filters within those.
        var installed = debloatApps.filter(function(app) {
            return app.installed
        })
        var query = debloatSearch.trim().toLowerCase()
        if (!query) return installed
        return installed.filter(function(app) {
            return String(app.name || "").toLowerCase().indexOf(query) >= 0
        })
    }

    function toggleDebloatSelection(id, value) {
        var idx = debloatSelected.indexOf(id)
        if (value && idx < 0) {
            debloatSelected.push(id)
            debloatSelectedCount += 1
        } else if (!value && idx >= 0) {
            debloatSelected.splice(idx, 1)
            debloatSelectedCount -= 1
        }
        debloatSelectionVersion += 1
    }

    function selectRecommendedDebloat() {
        debloatSelected = []
        var count = 0
        for (var i = 0; i < debloatApps.length; i++) {
            var app = debloatApps[i]
            if (app.installed && app.level === "Recommended") {
                debloatSelected.push(app.id)
                count += 1
            }
        }
        debloatSelectedCount = count
        debloatSelectionVersion += 1
    }

    function refreshSystemInfo() {
        windowsVersion = optimizer.getWindowsVersion()
        cpuInfo = optimizer.getCPUInfo()
        graphicsInfo = optimizer.getGraphicsInfo()
        ramInfo = optimizer.getRAMInfo()
        storageInfo = optimizer.getStorageInfo()
        appliedTweaksInfo = optimizer.getAppliedTweaksCount()
        uptimeInfo = optimizer.getUptime()
        memoryUsedPercent = optimizer.getMemoryUsedPercent()
        storageUsedPercent = optimizer.getStorageUsedPercent()
    }

    function showAdminPrompt() {
        if (optimizer.isWindows && !optimizer.isAdmin) {
            optimizer.adminPromptVisible = true
        } else {
            showRestorePrompt()
        }
    }
    function showRestorePrompt() {
        if (optimizer.restorePointPromptVisible) {
            showNextPromptAfterRestore()
            return
        }
        optimizer.restorePointPromptVisible = true
    }
    function showIntroPrompt() {
        introVisible = true
    }

    function introDismissed() {
        // The profile overlay binds to firstRunStarted && profileNeedsSetup
        // && !introVisible, so it appears automatically once the intro closes.
        introVisible = false
    }
    function firstRunAllowed() {
        // The one-time intro and profile prompts run for everyone: the app is
        // fully usable without administrator rights (admin-only tweaks are
        // dimmed), so the first-run flow must not depend on elevation.
        return true
    }
    function showNextPromptAfterAdmin() {
        optimizer.dismissAdminPrompt()
        showRestorePrompt()
    }
    function showNextPromptAfterRestore() {
        optimizer.dismissRestorePointPrompt()
        if (optimizer.profileNeedsSetup && firstRunAllowed()) {
            firstRunStarted = true
            showIntroPrompt()
        }
    }
    function runLaunchPrompts() {
        showAdminPrompt()
    }

    function iconFor(category) {
        if (category === "Home") return icons.home
        if (category === "Performance") return icons.bolt
        if (category === "Storage") return icons.storage
        if (category === "Privacy") return icons.shield
        if (category === "Debloat") return icons.trash
        if (category === "Startup") return icons.startup
        if (category === "Background") return icons.apps
        return icons.info
    }

    Connections {
        target: optimizer
        ignoreUnknownSignals: true
        function onToggleStateChanged(key, enabled) {
            loadTweaksForCategory(currentCategory)
            appliedTweaksInfo = optimizer.getAppliedTweaksCount()
        }
        function onOptionStateChanged(key, option) {
            loadTweaksForCategory(currentCategory)
        }
        function onOptimizationProgress(percent, status) {
            optimizationProgress = percent
            optimizationStatus = status
        }
        function onOptimizationComplete() {
            loadTweaksForCategory(currentCategory)
            appliedTweaksInfo = optimizer.getAppliedTweaksCount()
        }
        function onStartupAppsChanged() {
            if (currentCategory === "Startup") startupApps = optimizer.getStartupApps()
        }
        function onStartupImpactChanged() {
            if (currentCategory === "Startup") startupApps = optimizer.getStartupApps()
        }
        function onBackgroundAppsChanged() {
            if (currentCategory === "Background") backgroundApps = optimizer.getBackgroundApps()
        }
        function onDebloatAppsChanged() {
            if (currentCategory === "Debloat") debloatApps = optimizer.getDebloatApps()
        }
        function onDebloatRemovalProgress(percent, status) {
            debloatRemovalPercent = percent
            debloatRemovalStatus = status
        }
        function onSelectedPresetChanged() {
            appliedTweaksInfo = optimizer.getAppliedTweaksCount()
        }
        function onLogMessage(msg) {
            logModel.append({ text: msg })
            if (logModel.count > 300) logModel.remove(0)
            logView.positionViewAtEnd()
        }
    }

    Component.onCompleted: {
        categories = optimizer.getCategories()
        loadTweaksForCategory("Home")
        refreshSystemInfo()
        runLaunchPrompts()
    }

    // ------------------------------------------------------------------ #
    // Material icon path data (Material Symbols / Icons, 24px filled).
    // Rendered as crisp, themeable vectors via Shape + PathSvg.
    // ------------------------------------------------------------------ #
    QtObject {
        id: icons

        readonly property string settings: "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.488.488 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"
        readonly property string home: "M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"
        readonly property string bolt: "M11 21h-1l1-7H7.5c-.58 0-.57-.32-.38-.66.19-.34.05-.08.07-.12C8.48 10.94 10.42 7.54 13 3h1l-1 7h3.5c.49 0 .56.33.47.51l-.07.15C12.96 17.55 11 21 11 21z"
        readonly property string storage: "M2 20h20v-4H2v4zm2-3h2v2H4v-2zM2 4v4h20V4H2zm4 3H4V5h2v2zm-4 7h20v-4H2v4zm2-3h2v2H4v-2z"
        readonly property string shield: "M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4z"
        readonly property string restore: "M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z"
        readonly property string memory: "M15 9H9v6h6V9zm-2 4h-2v-2h2v2zm8-2V9h-2V7c0-1.1-.9-2-2-2h-2V3h-2v2h-2V3H9v2H7c-1.1 0-2 .9-2 2v2H3v2h2v2H3v2h2v2c0 1.1.9 2 2 2h2v2h2v-2h2v2h2v-2h2c1.1 0 2-.9 2-2v-2h2v-2h-2v-2h2zm-4 6H7V7h10v10z"
        readonly property string monitor: "M21 2H3c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h7v2H8v2h8v-2h-2v-2h7c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H3V4h18v12z"
        readonly property string speed: "M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z"
        readonly property string checkCircle: "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"
        readonly property string timer: "M15 1H9v2h6V1zm-4 13h2V8h-6v2h4v4zm8.03-6.61l1.42-1.42c-.43-.51-.9-.99-1.41-1.41l-1.42 1.42C16.07 4.74 14.12 4 12 4c-4.97 0-9 4.03-9 9s4.02 9 9 9 9-4.03 9-9c0-2.12-.74-4.07-1.97-5.61zM12 20c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z"
        readonly property string warning: "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"
        readonly property string info: "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z"
        readonly property string play: "M8 5v14l11-7z"
        readonly property string chevronDown: "M16.59 8.59L12 13.17 7.41 8.59 6 10l6 6 6-6z"
        readonly property string chevronUp: "M12 8l-6 6 1.41 1.41L12 10.83l4.59 4.58L18 14z"
        readonly property string chevronLeft: "M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z"
        readonly property string chevronRight: "M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z"
        readonly property string restartAlt: "M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"
        readonly property string startup: "M4 4h16v2H4V4zm0 4h16v2H4V8zm0 4h10v2H4v-2zm0 4h10v2H4v-2zm13-4v3h-3v2h3v3h2v-3h3v-2h-3v-3h-2z"
        readonly property string apps: "M4 4h6v6H4V4zm10 0h6v6h-6V4zM4 14h6v6H4v-6zm10 0h6v6h-6v-6z"
        readonly property string cross: "M18.3 5.71L12 12l6.3 6.29L16.59 20 12 15.41 7.41 20 5.71 18.3 12 12 5.71 5.71 7.41 4 12 8.59 16.59 4z"
        readonly property string check: "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"
        readonly property string trash: "M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"
    }

    // ------------------------------------------------------------------ #
    // Reusable components
    // ------------------------------------------------------------------ #

    component M3Icon: Shape {
        id: iconShape
        property string iconPath: ""
        property color color: theme.mdOnSurfaceVariant
        property int size: 24

        width: size
        height: size
        transform: Scale { xScale: size / 24; yScale: size / 24 }

        ShapePath {
            fillColor: iconShape.color
            strokeColor: "transparent"
            strokeWidth: 0
            PathSvg { path: iconShape.iconPath }
        }
    }

    component M3NavItem: Rectangle {
        id: nav
        property string iconPath: ""
        property string label: ""
        property bool active: false
        property bool collapsed: false
        signal activated()

        // A stable row height prevents the rail from jumping when its width
        // animates. The selected surface is deliberately narrower than the
        // rail so it reads as a navigation item, not a full-width stripe.
        implicitHeight: 56
        color: "transparent"
        scale: navMouse.pressed ? 0.97 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

        Rectangle {
            id: navSurface
            anchors.centerIn: parent
            width: nav.collapsed ? 56 : parent.width - 28
            height: nav.collapsed ? 42 : 48
            radius: nav.collapsed ? 21 : 18
            color: nav.active
                   ? theme.mdSecondaryContainer
                   : (navMouse.containsMouse ? theme.mdSurfaceHigh : "transparent")
            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            M3Icon {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: nav.collapsed ? undefined : parent.left
                anchors.leftMargin: nav.collapsed ? 0 : 18
                anchors.horizontalCenter: nav.collapsed ? parent.horizontalCenter : undefined
                iconPath: nav.iconPath
                color: nav.active ? theme.mdOnSecondaryContainer : theme.mdOnSurfaceVariant
                size: 22
            }

            Text {
                visible: !nav.collapsed
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 58
                anchors.right: parent.right
                anchors.rightMargin: 14
                text: nav.label
                color: nav.active ? theme.mdOnSecondaryContainer : theme.mdOnSurface
                font.pixelSize: 14
                font.weight: nav.active ? Font.DemiBold : Font.Normal
                font.family: fontFamily
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.activated()
            ToolTip.visible: nav.collapsed && containsMouse
            ToolTip.delay: 250
            ToolTip.text: nav.label
        }
    }

    component M3Toggle: Rectangle {
        id: toggle
        property bool checked: false
        property bool supported: true
        signal toggled(bool value)

        width: 52
        height: 32
        radius: height / 2
        color: !toggle.supported ? theme.mdOutlineVariant
               : (toggle.checked ? theme.mdPrimary : theme.mdOutlineVariant)
        Behavior on color { ColorAnimation { duration: 200 } }
        opacity: toggle.supported ? 1.0 : 0.45

        Rectangle {
            id: knob
            width: 26
            height: 26
            radius: 13
            color: toggle.checked ? theme.mdOnPrimary : theme.mdOutline
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - 3 : 3
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Rectangle {
            visible: !toggle.supported
            width: 20
            height: 20
            radius: 10
            color: theme.mdErrorContainer
            border.color: theme.mdOnErrorContainer
            border.width: 1
            anchors.centerIn: parent
            M3Icon {
                anchors.centerIn: parent
                iconPath: icons.cross
                color: theme.mdOnErrorContainer
                size: 12
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: toggle.supported
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled(!toggle.checked)
        }
    }

    component M3PillButton: Rectangle {
        id: btn
        property string label: ""
        property string iconPath: ""
        property color fg: theme.mdPrimary
        property bool emphasized: false
        property bool tonal: false
        property bool interactive: true
        property bool fullWidth: false
        property string tooltip: ""
        signal clicked()

        implicitWidth: 136
        implicitHeight: 44
        radius: height / 2
        color: btn.emphasized ? theme.mdPrimary : (btn.tonal ? theme.mdSecondaryContainer : "transparent")
        scale: btnMouse.pressed ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
        opacity: btn.interactive ? 1.0 : 0.55
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: theme.mdSecondary
            opacity: !btn.emphasized && btn.interactive && (btnMouse.pressed ? 0.14 : (btnMouse.containsMouse ? 0.06 : 0.0))
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        Row {
            anchors.centerIn: parent
            spacing: 8

            M3Icon {
                visible: btn.iconPath.length > 0
                anchors.verticalCenter: parent.verticalCenter
                iconPath: btn.iconPath
                color: btn.emphasized ? theme.mdOnPrimary : (btn.tonal ? theme.mdOnSecondaryContainer : btn.fg)
                size: 18
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: btn.emphasized ? theme.mdOnPrimary : (btn.tonal ? theme.mdOnSecondaryContainer : btn.fg)
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.family: fontFamily
                maximumLineCount: 1
                elide: Text.ElideRight
                width: btn.fullWidth ? btn.width - 36 : implicitWidth
                horizontalAlignment: Text.AlignHCenter
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: btn.interactive
            onClicked: btn.clicked()
            ToolTip.visible: btn.tooltip.length > 0 && containsMouse
            ToolTip.delay: 250
            ToolTip.text: btn.tooltip
        }
    }

    component M3StatusChip: Rectangle {
        id: statusChip
        property string label: ""
        property string iconPath: ""
        property color fill: theme.mdSecondaryContainer
        property color contentColor: theme.mdOnSecondaryContainer

        implicitWidth: 128
        implicitHeight: 36
        radius: 18
        color: statusChip.fill

        Row {
            anchors.centerIn: parent
            spacing: 7
            M3Icon {
                anchors.verticalCenter: parent.verticalCenter
                iconPath: statusChip.iconPath
                color: statusChip.contentColor
                size: 16
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: statusChip.label
                color: statusChip.contentColor
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.family: fontFamily
            }
        }
    }

    component M3InfoChip: Rectangle {
        id: infoChip
        property string tip: ""
        width: 26
        height: 26
        radius: 13
        color: theme.mdSecondaryContainer

        M3Icon {
            anchors.centerIn: parent
            iconPath: icons.info
            color: theme.mdOnSecondaryContainer
            size: 16
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
            ToolTip.visible: containsMouse
            ToolTip.delay: 200
            ToolTip.text: infoChip.tip
        }
    }

    component M3ProgressBar: Rectangle {
        id: bar
        property real progress: 0.0
        height: 8
        radius: 4
        color: theme.mdSurfaceContainer

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, bar.progress))
            height: parent.height
            radius: 4
            color: theme.mdPrimary
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    component M3SpecCard: Rectangle {
        id: spec
        property string label: ""
        property string value: ""
        property string iconPath: ""
        property real progress: -1

        // Two compact rows plus spacing; the grid uses this implicit height
        // to keep every dashboard module inside a real tonal container.
        implicitHeight: 116
        radius: theme.radiusXl
        color: theme.mdSurfaceContainer
        border.color: theme.mdOutlineVariant
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                M3Icon {
                    iconPath: spec.iconPath
                    color: theme.mdPrimary
                    size: 18
                }
                Text {
                    text: spec.label
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                Layout.maximumHeight: 38
                text: spec.value
                color: theme.mdOnSurface
                font.pixelSize: 16
                font.weight: Font.Medium
                font.family: fontFamily
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                maximumLineCount: 2
            }
            M3ProgressBar {
                visible: spec.progress >= 0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 150
                Layout.maximumWidth: 150
                progress: spec.progress
            }
            Item { Layout.fillHeight: true }
        }
    }

    component M3TweakCard: Rectangle {
        id: card
        property var tweak
        readonly property bool unsupported: card.tweak && card.tweak.supported === false

        radius: theme.radiusLg
        color: theme.mdSurfaceContainer
        border.color: theme.mdOutlineVariant
        border.width: 1
        implicitHeight: card.tweak && card.tweak.controlType === "select" ? 178 : (card.unsupported ? 164 : 138)
        opacity: card.unsupported ? 0.82 : 1.0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: card.tweak.content
                    color: theme.mdOnSurface
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.family: fontFamily
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                M3InfoChip {
                    tip: card.tweak.description
                }
            }

            Text {
                text: card.tweak.description
                color: theme.mdOnSurfaceVariant
                font.pixelSize: 12
                font.family: fontFamily
                Layout.fillWidth: true
                Layout.fillHeight: true
                wrapMode: Text.Wrap
                maximumLineCount: card.unsupported ? 1 : 2
                elide: Text.ElideRight
            }

            Text {
                visible: card.unsupported
                Layout.fillWidth: true
                text: card.tweak.supportReason === "admin"
                      ? "Needs administrator permission"
                      : "Not supported on this PC"
                color: theme.mdError
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.family: fontFamily
            }

            RowLayout {
                visible: card.tweak.controlType === "select"
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: card.tweak.options
                    delegate: M3PillButton {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        label: modelData.label
                        emphasized: card.tweak.selectedOption === modelData.key
                        tonal: card.tweak.selectedOption !== modelData.key
                        interactive: !card.unsupported
                        onClicked: optimizer.setTweakOption(card.tweak.key, modelData.key)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                M3Toggle {
                    visible: card.tweak.controlType === "toggle"
                    checked: card.tweak.enabled
                    supported: !card.unsupported
                    onToggled: function(v) { optimizer.setToggleState(card.tweak.key, v) }
                }
                M3PillButton {
                    visible: card.tweak.controlType === "button"
                    label: card.tweak.actionLabel
                    iconPath: icons.play
                    emphasized: true
                    implicitWidth: 92
                    interactive: !card.unsupported
                    onClicked: optimizer.executeTweakOnce(card.tweak.key)
                }
            }
        }
    }

    component M3AppCard: Rectangle {
        id: appCard
        property var app
        property bool backgroundApp: false
        signal changed(bool enabled)

        radius: theme.radiusLg
        color: theme.mdSurfaceContainer
        border.color: theme.mdOutlineVariant
        border.width: 1
        implicitHeight: 96

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 42
                Layout.preferredHeight: 42
                radius: 14
                color: appCard.backgroundApp ? theme.mdTertiaryContainer : theme.mdPrimaryContainer
                M3Icon {
                    anchors.centerIn: parent
                    iconPath: appCard.backgroundApp ? icons.apps : icons.startup
                    color: appCard.backgroundApp ? theme.mdOnTertiaryContainer : theme.mdOnPrimaryContainer
                    size: 21
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                Text {
                    text: appCard.app ? appCard.app.name : ""
                    color: theme.mdOnSurface
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    font.family: fontFamily
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: appCard.app
                          ? (appCard.backgroundApp ? appCard.app.recommendationLabel : appCard.app.detail)
                          : ""
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 12
                    font.family: fontFamily
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Text {
                    text: appCard.app
                          ? (appCard.backgroundApp ? appCard.app.recommendationDetail : appCard.app.impactLabel)
                          : ""
                    color: appCard.backgroundApp
                           ? theme.mdOnSurfaceVariant
                           : (appCard.app && appCard.app.impactLabel === "Impact: High" ? theme.mdError : theme.mdPrimary)
                    opacity: 0.9
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: fontFamily
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                M3Toggle {
                    Layout.alignment: Qt.AlignHCenter
                    checked: appCard.app ? appCard.app.enabled : false
                    onToggled: function(value) { appCard.changed(value) }
                }
                Text {
                    text: appCard.app && appCard.app.enabled ? "On" : "Off"
                    color: appCard.app && appCard.app.enabled ? theme.mdPrimary : theme.mdOnSurfaceVariant
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: fontFamily
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    component M3Checkbox: Rectangle {
        id: check
        property bool checked: false
        property bool interactive: true
        signal toggled(bool value)

        width: 26
        height: 26
        radius: 8
        color: check.interactive && check.checked ? theme.mdPrimary : theme.mdSurfaceHigh
        border.color: check.interactive && check.checked ? theme.mdPrimary : theme.mdOutline
        border.width: 1.5
        Behavior on color { ColorAnimation { duration: 140 } }
        opacity: check.interactive ? 1.0 : 0.45

        M3Icon {
            visible: check.checked
            anchors.centerIn: parent
            iconPath: icons.check
            color: theme.mdOnPrimary
            size: 18
        }

        MouseArea {
            anchors.fill: parent
            enabled: check.interactive
            cursorShape: Qt.PointingHandCursor
            onClicked: check.toggled(!check.checked)
        }
    }

    component M3DebloatCard: Rectangle {
        id: dcard
        property var app
        property bool selected: false
        signal toggled(bool value)

        radius: theme.radiusLg
        color: theme.mdSurfaceContainer
        border.color: theme.mdOutlineVariant
        border.width: 1
        implicitHeight: 128
        opacity: dcard.app && dcard.app.installed ? 1.0 : 0.55

        RowLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            M3Checkbox {
                Layout.alignment: Qt.AlignVCenter
                checked: dcard.selected
                interactive: dcard.app ? dcard.app.installed : false
                onToggled: function(value) { dcard.toggled(value) }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: dcard.app ? dcard.app.name : ""
                        color: theme.mdOnSurface
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.family: fontFamily
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: recLabel.width + 18
                        Layout.preferredHeight: 22
                        radius: 11
                        color: dcard.app && dcard.app.level === "Recommended" ? theme.mdPrimaryContainer
                             : (dcard.app && dcard.app.level === "Optional" ? theme.mdTertiaryContainer : theme.mdErrorContainer)
                        Text {
                            id: recLabel
                            anchors.centerIn: parent
                            text: dcard.app ? dcard.app.level : ""
                            color: dcard.app && dcard.app.level === "Recommended" ? theme.mdOnPrimaryContainer
                                 : (dcard.app && dcard.app.level === "Optional" ? theme.mdOnTertiaryContainer : theme.mdOnErrorContainer)
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            font.family: fontFamily
                        }
                    }
                }

                Text {
                    text: dcard.app ? dcard.app.reason : ""
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 12
                    font.family: fontFamily
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: dcard.app && dcard.app.installed ? "Installed" : "Not installed"
                    color: dcard.app && dcard.app.installed ? theme.mdPrimary : theme.mdOnSurfaceVariant
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.family: fontFamily
                }
            }
        }
    }

    // ------------------------------------------------------------------ #
    // Layout
    // ------------------------------------------------------------------ #

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---- Navigation rail ----
        Rectangle {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: sidebarCollapsed ? 88 : 252
            color: theme.mdSurface
            border.color: theme.mdOutlineVariant
            border.width: 1

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: sidebarCollapsed ? 8 : 12
                anchors.rightMargin: sidebarCollapsed ? 8 : 12
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 8

                // Brand block: expanded shows the product name; collapsed
                // becomes a quiet app mark with a clearly separate expand
                // affordance. Both states keep the same visual anchor.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: sidebarCollapsed ? 84 : 72
                    radius: theme.radiusLg
                    color: sidebarCollapsed ? theme.mdSurfaceContainer : theme.mdPrimaryContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 10
                        spacing: 10
                        visible: !sidebarCollapsed

                        M3Icon {
                            Layout.alignment: Qt.AlignVCenter
                            iconPath: icons.settings
                            color: theme.mdOnPrimaryContainer
                            size: 22
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: "John's Windows Fixer"
                                color: theme.mdOnPrimaryContainer
                                font.pixelSize: 14
                                font.weight: Font.Bold
                                font.family: fontFamily
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "System utility"
                                color: theme.mdOnPrimaryContainer
                                opacity: 0.72
                                font.pixelSize: 11
                                font.family: fontFamily
                            }
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            radius: 17
                            color: sidebarCollapseExpanded.containsMouse ? theme.mdSecondaryContainer : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            M3Icon {
                                anchors.centerIn: parent
                                iconPath: icons.chevronLeft
                                color: theme.mdOnPrimaryContainer
                                size: 18
                            }
                            MouseArea {
                                id: sidebarCollapseExpanded
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sidebarCollapsed = true
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 300
                                ToolTip.text: "Collapse navigation"
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        visible: sidebarCollapsed

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 42
                            height: 42
                            radius: 15
                            color: theme.mdPrimaryContainer
                            M3Icon {
                                anchors.centerIn: parent
                                iconPath: icons.settings
                                color: theme.mdOnPrimaryContainer
                                size: 22
                            }
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 34
                            height: 26
                            radius: 13
                            color: sidebarExpandMouse.containsMouse ? theme.mdSecondaryContainer : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            M3Icon {
                                anchors.centerIn: parent
                                iconPath: icons.chevronRight
                                color: theme.mdOnSurfaceVariant
                                size: 18
                            }
                            MouseArea {
                                id: sidebarExpandMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: sidebarCollapsed = false
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 300
                                ToolTip.text: "Expand navigation"
                            }
                        }
                    }
                }

                // Navigation destinations are kept in a dedicated group so
                // the compact rail has an intentional rhythm rather than
                // looking like a squeezed desktop menu.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: categories
                        delegate: M3NavItem {
                            Layout.fillWidth: true
                            iconPath: iconFor(modelData)
                            label: modelData
                            active: currentCategory === modelData
                            collapsed: sidebarCollapsed
                            onActivated: loadTweaksForCategory(modelData)
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                M3PillButton {
                    Layout.alignment: sidebarCollapsed ? Qt.AlignHCenter : Qt.AlignLeft
                    Layout.fillWidth: !sidebarCollapsed
                    Layout.preferredWidth: sidebarCollapsed ? 52 : -1
                    label: sidebarCollapsed ? "" : "Create restore point"
                    iconPath: icons.restore
                    tooltip: "Create a Windows restore point"
                    tonal: true
                    onClicked: optimizer.createRestorePoint()
                }
            }
        }

        // ---- Content ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 16

                // ---- Admin banner (Windows only) ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: theme.radiusLg
                    color: theme.mdErrorContainer
                    visible: optimizer.isWindows && !optimizer.isAdmin

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 12
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 16

                        M3Icon {
                            iconPath: icons.warning
                            color: theme.mdOnErrorContainer
                            size: 22
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Text {
                            text: "Standard mode — tweaks that need administrator permission are dimmed below. Restart elevated to enable them."
                            color: theme.mdOnErrorContainer
                            font.pixelSize: 13
                            font.family: fontFamily
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        M3PillButton {
                            label: "Restart as admin"
                            iconPath: icons.restartAlt
                            implicitWidth: 160
                            implicitHeight: 34
                            emphasized: true
                            onClicked: optimizer.restartAsAdmin()
                        }
                    }
                }

                // ---- Page header (hidden on Home) ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 78
                    radius: theme.radiusLg
                    color: theme.mdSurfaceContainer
                    visible: currentCategory !== "Home"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16

                        Rectangle {
                            width: 6
                            height: 42
                            radius: 3
                            color: theme.mdPrimary
                            Layout.alignment: Qt.AlignVCenter
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 1400 }
                                NumberAnimation { to: 1.0; duration: 1400 }
                            }
                        }
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2
                            Text {
                                text: currentCategory === "Background" ? "Background activity" : currentCategory
                                color: theme.mdOnSurface
                                font.pixelSize: 21
                                font.weight: Font.DemiBold
                                font.family: fontFamily
                            }
                            Text {
                                text: optimizer.getCategoryTooltip(currentCategory)
                                color: theme.mdOnSurfaceVariant
                                font.pixelSize: 13
                                font.family: fontFamily
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: currentCategory === "Startup"
                                  ? startupApps.length + " apps"
                                  : (currentCategory === "Background" ? backgroundApps.length + " apps"
                                     : (currentCategory === "Debloat" ? debloatApps.filter(function(a) { return a.installed }).length + " installed" : tweaksList.length + " tweaks"))
                            color: theme.mdOnSurfaceVariant
                            font.pixelSize: 13
                            font.family: fontFamily
                        }
                    }
                }

                // ---- Page content ----
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: currentCategory === "Home" ? 0
                                  : ((currentCategory === "Startup" || currentCategory === "Background") ? 1
                                     : (currentCategory === "Debloat" ? 2 : 3))

                    // ================= HOME =================
                    ColumnLayout {
                        spacing: 16

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text {
                                    text: "System overview"
                                    color: theme.mdOnSurface
                                    font.pixelSize: 27
                                    font.weight: Font.Bold
                                    font.family: fontFamily
                                }
                                Text {
                                    text: windowsVersion + "  ·  " + appliedTweaksInfo + " of recommended settings ready"
                                    color: theme.mdOnSurfaceVariant
                                    font.pixelSize: 13
                                    font.family: fontFamily
                                    elide: Text.ElideRight
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 8
                                M3PillButton {
                                    label: "Gaming"
                                    implicitWidth: 82
                                    implicitHeight: 36
                                    emphasized: optimizer.selectedPreset === "Gaming"
                                    tonal: optimizer.selectedPreset !== "Gaming"
                                    onClicked: optimizer.setSelectedPreset("Gaming")
                                }
                                M3PillButton {
                                    label: "Productivity"
                                    implicitWidth: 104
                                    implicitHeight: 36
                                    emphasized: optimizer.selectedPreset === "Productivity"
                                    tonal: optimizer.selectedPreset !== "Productivity"
                                    onClicked: optimizer.setSelectedPreset("Productivity")
                                }
                                M3PillButton {
                                    label: "Restore point"
                                    iconPath: icons.restore
                                    tooltip: "Create a Windows restore point"
                                    tonal: true
                                    onClicked: optimizer.createRestorePoint()
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 248
                            Layout.minimumHeight: 248
                            columns: 3
                            rows: 2
                            columnSpacing: 16
                            rowSpacing: 16

                            M3SpecCard { label: "Processor"; iconPath: icons.memory; value: cpuInfo; Layout.fillWidth: true }
                            M3SpecCard { label: "Graphics"; iconPath: icons.monitor; value: graphicsInfo; Layout.fillWidth: true }
                            M3SpecCard { label: "Memory"; iconPath: icons.speed; value: ramInfo; progress: memoryUsedPercent / 100; Layout.fillWidth: true }
                            M3SpecCard { label: "Storage (C:)"; iconPath: icons.storage; value: storageInfo; progress: storageUsedPercent / 100; Layout.fillWidth: true }
                            M3SpecCard { label: "Applied tweaks"; iconPath: icons.checkCircle; value: appliedTweaksInfo; progress: appliedPercent; Layout.fillWidth: true }
                            M3SpecCard { label: "Uptime"; iconPath: icons.timer; value: uptimeInfo; Layout.fillWidth: true }
                        }

                        // ---- Optimize hero ----
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: theme.radiusXl
                            color: theme.mdSurfaceContainer
                            border.color: theme.mdOutlineVariant
                            border.width: 1

                            Item {
                                id: optimizeHero
                                anchors.fill: parent

                                // The morphing blob is the centerpiece.  Sized large
                                // enough that the progress text always sits inside it.
                                Item {
                                    id: heroLoader
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: -14
                                    width: Math.min(320, Math.max(180, parent.width - 48))
                                    height: Math.min(320, Math.max(180, parent.height - 92))

                                    M3ExpressiveIndicator {
                                        id: loadingIndicator
                                        anchors.fill: parent
                                        indicatorColor: theme.mdPrimary
                                        running: optimizer.isOptimizing
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - 30, 210)
                                        spacing: 4
                                        visible: true

                                        Text {
                                            width: parent.width
                                            text: "Optimize now"
                                            visible: !optimizer.isOptimizing
                                            color: theme.mdOnPrimary
                                            font.pixelSize: 20
                                            font.weight: Font.Bold
                                            font.family: fontFamily
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            width: parent.width
                                            text: optimizationProgress + "%"
                                            visible: optimizer.isOptimizing
                                            color: theme.mdOnPrimary
                                            font.pixelSize: 30
                                            font.weight: Font.Bold
                                            font.family: fontFamily
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            width: parent.width
                                            text: optimizationStatus
                                            visible: optimizer.isOptimizing
                                            color: theme.mdOnPrimary
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            font.family: fontFamily
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                        }
                                    }

                                    MouseArea {
                                        id: heroLoaderMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: optimizer.runOptimization()
                                    }
                                }

                                ColumnLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 20
                                    spacing: 8

                                    M3ProgressBar {
                                        Layout.alignment: Qt.AlignHCenter
                                        Layout.fillWidth: true
                                        Layout.maximumWidth: 340
                                        progress: optimizationProgress / 100
                                        visible: optimizer.isOptimizing
                                    }
                                }
                            }
                        }
                    }

                    // ================= APP MANAGEMENT =================
                    ColumnLayout {
                        spacing: 16

                        Rectangle {
                            visible: currentCategory === "Startup"
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 74 : 0
                            radius: theme.radiusLg
                            color: theme.mdSurfaceContainer
                            border.color: theme.mdOutlineVariant
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 12

                                M3Icon {
                                    iconPath: icons.timer
                                    color: theme.mdPrimary
                                    size: 22
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: "Measure startup impact"
                                        color: theme.mdOnSurface
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                        font.family: fontFamily
                                    }
                                    Text {
                                        text: "Let Windows record startup times so impact ratings can appear."
                                        color: theme.mdOnSurfaceVariant
                                        font.pixelSize: 11
                                        font.family: fontFamily
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }
                                M3Toggle {
                                    checked: optimizer.startupImpactEnabled
                                    onToggled: function(value) { optimizer.setStartupImpactEnabled(value) }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            TextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                placeholderText: currentCategory === "Startup" ? "Search startup apps" : "Search apps"
                                text: appSearch
                                font.family: fontFamily
                                font.pixelSize: 13
                                color: theme.mdOnSurface
                                placeholderTextColor: theme.mdOnSurfaceVariant
                                leftPadding: 16
                                rightPadding: 16
                                background: Rectangle {
                                    radius: 21
                                    color: theme.mdSurfaceContainer
                                    border.color: theme.mdOutlineVariant
                                    border.width: 1
                                }
                                onTextChanged: appSearch = text
                            }
                            M3PillButton {
                                label: "Refresh"
                                iconPath: icons.restartAlt
                                tonal: true
                                implicitWidth: 104
                                onClicked: {
                                    if (currentCategory === "Startup") {
                                        startupApps = optimizer.getStartupApps()
                                    } else {
                                        optimizer.refreshBackgroundApps()
                                    }
                                }
                            }
                        }

                        Text {
                            visible: (currentCategory === "Startup" ? startupApps.length : backgroundApps.length) === 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 58 : 0
                            text: !optimizer.isWindows
                                  ? "Available on Windows."
                                  : (currentCategory === "Background" && optimizer.backgroundAppsLoading
                                     ? "Finding installed apps…"
                                     : "No apps found.")
                            color: theme.mdOnSurfaceVariant
                            font.pixelSize: 13
                            font.family: fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        Text {
                            visible: (currentCategory === "Startup" ? startupApps.length : backgroundApps.length) > 0 && appsForPage().length === 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 58 : 0
                            text: "No matching apps."
                            color: theme.mdOnSurfaceVariant
                            font.pixelSize: 13
                            font.family: fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        ScrollView {
                            id: appScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded
                            contentWidth: availableWidth

                            Flow {
                                id: appFlow
                                width: appScroll.availableWidth
                                spacing: 16

                                Repeater {
                                    model: appsForPage()
                                    delegate: M3AppCard {
                                        app: modelData
                                        backgroundApp: currentCategory === "Background"
                                        width: Math.max(260, Math.floor((appFlow.width - appFlow.spacing) / 2))
                                        onChanged: function(value) {
                                            if (backgroundApp) {
                                                optimizer.setBackgroundAppEnabled(app.id, value)
                                            } else {
                                                optimizer.setStartupAppEnabled(app.id, value)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ================= DEBLOAT =================
                    ColumnLayout {
                        spacing: 16

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: debloatHeaderCol.implicitHeight + 40
                            radius: theme.radiusXl
                            color: theme.mdSurfaceContainer
                            border.color: theme.mdOutlineVariant
                            border.width: 1

                            ColumnLayout {
                                id: debloatHeaderCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 14

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    M3Icon {
                                        Layout.alignment: Qt.AlignVCenter
                                        iconPath: icons.trash
                                        color: theme.mdPrimary
                                        size: 26
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text {
                                            text: "Remove bloatware"
                                            color: theme.mdOnSurface
                                            font.pixelSize: 18
                                            font.weight: Font.DemiBold
                                            font.family: fontFamily
                                        }
                                        Text {
                                            text: "Select preinstalled apps you don't need. Removed apps can be reinstalled anytime from the Microsoft Store."
                                            color: theme.mdOnSurfaceVariant
                                            font.pixelSize: 12
                                            font.family: fontFamily
                                            Layout.fillWidth: true
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    M3PillButton {
                                        id: debloatRemoveBtn
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 52
                                        label: optimizer.debloatRemoving
                                              ? debloatRemovalStatus
                                              : ("Remove selected (" + debloatSelectedCount + ")")
                                        iconPath: icons.trash
                                        emphasized: true
                                        fullWidth: true
                                        interactive: !optimizer.debloatRemoving && debloatSelectedCount > 0
                                        onClicked: optimizer.removeDebloatApps(debloatSelected)
                                    }
                                    M3PillButton {
                                        label: "Select recommended"
                                        iconPath: icons.checkCircle
                                        tonal: true
                                        implicitHeight: 52
                                        implicitWidth: 168
                                        interactive: !optimizer.debloatRemoving
                                        onClicked: selectRecommendedDebloat()
                                    }
                                }

                                M3ProgressBar {
                                    Layout.fillWidth: true
                                    visible: optimizer.debloatRemoving
                                    progress: debloatRemovalPercent / 100
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: "Recommendations:"
                                color: theme.mdOnSurfaceVariant
                                font.pixelSize: 12
                                font.family: fontFamily
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Rectangle {
                                Layout.preferredWidth: legendRec.width + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: theme.mdPrimaryContainer
                                Text {
                                    id: legendRec
                                    anchors.centerIn: parent
                                    text: "Recommended"
                                    color: theme.mdOnPrimaryContainer
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.family: fontFamily
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: legendOpt.width + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: theme.mdTertiaryContainer
                                Text {
                                    id: legendOpt
                                    anchors.centerIn: parent
                                    text: "Optional"
                                    color: theme.mdOnTertiaryContainer
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.family: fontFamily
                                }
                            }
                            Rectangle {
                                Layout.preferredWidth: legendCau.width + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: theme.mdErrorContainer
                                Text {
                                    id: legendCau
                                    anchors.centerIn: parent
                                    text: "Caution"
                                    color: theme.mdOnErrorContainer
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    font.family: fontFamily
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            TextField {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 42
                                placeholderText: "Search apps"
                                text: debloatSearch
                                font.family: fontFamily
                                font.pixelSize: 13
                                color: theme.mdOnSurface
                                placeholderTextColor: theme.mdOnSurfaceVariant
                                leftPadding: 16
                                rightPadding: 16
                                background: Rectangle {
                                    radius: 21
                                    color: theme.mdSurfaceContainer
                                    border.color: theme.mdOutlineVariant
                                    border.width: 1
                                }
                                onTextChanged: debloatSearch = text
                            }
                            M3PillButton {
                                label: "Refresh"
                                iconPath: icons.restartAlt
                                tonal: true
                                implicitWidth: 104
                                onClicked: optimizer.refreshDebloatApps()
                            }
                        }

                        Text {
                            visible: debloatAppsForPage().length === 0 && !optimizer.debloatAppsLoading
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? 58 : 0
                            text: !optimizer.isWindows
                                  ? "Available on Windows."
                                  : "No installed apps found."
                            color: theme.mdOnSurfaceVariant
                            font.pixelSize: 13
                            font.family: fontFamily
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        ScrollView {
                            id: debloatScroll
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded
                            contentWidth: availableWidth

                            Flow {
                                id: debloatFlow
                                width: debloatScroll.availableWidth
                                spacing: 16

                                Repeater {
                                    model: debloatAppsForPage()
                                    delegate: M3DebloatCard {
                                        app: modelData
                                        selected: debloatSelected.indexOf(modelData.id) >= 0 && debloatSelectionVersion >= 0
                                        width: Math.max(280, Math.floor((debloatFlow.width - debloatFlow.spacing) / 2))
                                        onToggled: function(value) { toggleDebloatSelection(modelData.id, value) }
                                    }
                                }
                            }
                        }
                    }

                    // ================= CATEGORY =================
                    ScrollView {
                        id: tweaksScroll
                        clip: true
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded
                        contentWidth: availableWidth

                        Flow {
                            id: tweaksFlow
                            width: tweaksScroll.availableWidth
                            spacing: 16

                            Repeater {
                                model: tweaksList
                                delegate: M3TweakCard {
                                    tweak: modelData
                                    width: Math.floor((tweaksFlow.width - tweaksFlow.spacing * 2) / 3)
                                }
                            }
                        }
                    }
                }

                // ---- Activity log ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: logExpanded ? 190 : 46
                    radius: theme.radiusLg
                    color: theme.mdSurfaceContainer
                    clip: true
                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Text {
                                text: "Activity"
                                color: theme.mdOnSurfaceVariant
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: fontFamily
                            }
                            Text {
                                text: logModel.count > 0 ? logModel.get(logModel.count - 1).text : "No activity yet"
                                color: theme.mdOnSurface
                                font.pixelSize: 12
                                font.family: monoFamily
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                leftPadding: 12
                            }
                            M3PillButton {
                                label: "Clear"
                                implicitHeight: 28
                                implicitWidth: 64
                                onClicked: logModel.clear()
                            }
                            Rectangle {
                                width: 28
                                height: 28
                                radius: 14
                                color: "transparent"
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: logExpanded = !logExpanded
                                }
                                M3Icon {
                                    anchors.centerIn: parent
                                    iconPath: logExpanded ? icons.chevronDown : icons.chevronUp
                                    color: theme.mdOnSurfaceVariant
                                    size: 20
                                }
                            }
                        }

                        ListView {
                            id: logView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: logExpanded
                            clip: true
                            model: logModel
                            delegate: Text {
                                text: model.text
                                color: theme.mdOnSurfaceVariant
                                font.pixelSize: 12
                                font.family: monoFamily
                                width: logView.width
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }

    // First launch asks for the user's intent, while the same two choices
    // remain available on Home whenever they want to switch later.
    // Restore-point prompt shown at launch. The skip button unlocks
    // after a short countdown so users actually read the recommendation.
    property bool introVisible: false
    property bool firstRunStarted: false
    property int adminCountdown: 5
    property bool adminTimerActive: false
    property int restoreCountdown: 5
    property bool restoreTimerActive: false

    Timer {
        id: restoreTimer
        interval: 1000
        repeat: true
        running: restoreTimerActive
        onTriggered: {
            restoreCountdown -= 1
            if (restoreCountdown <= 0) {
                restoreTimerActive = false
                restoreCountdown = 0
            }
        }
    }

    Timer {
        id: adminTimer
        interval: 1000
        repeat: true
        running: adminTimerActive
        onTriggered: {
            adminCountdown -= 1
            if (adminCountdown <= 0) {
                adminTimerActive = false
                adminCountdown = 0
            }
        }
    }

    Rectangle {
        id: adminOverlay
        objectName: "adminOverlay"
        anchors.fill: parent
        z: 23
        visible: optimizer.adminPromptVisible
        color: "#B31A1C23"

        onVisibleChanged: {
            if (visible) {
                adminCountdown = 5
                adminTimerActive = true
            } else {
                adminTimerActive = false
            }
        }
        Component.onCompleted: {
            if (visible) {
                adminCountdown = 5
                adminTimerActive = true
            }
        }

        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 48)
            height: 330
            radius: theme.radiusXl
            color: theme.mdSurfaceContainer
            border.color: theme.mdOutlineVariant
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                M3Icon {
                    Layout.alignment: Qt.AlignHCenter
                    iconPath: icons.warning
                    color: theme.mdError
                    size: 34
                }
                Text {
                    Layout.fillWidth: true
                    text: "Run as administrator?"
                    color: theme.mdOnSurface
                    font.pixelSize: 23
                    font.weight: Font.Bold
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    Layout.fillWidth: true
                    text: "Some settings need administrator permission to apply."
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 13
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    text: "You can skip this — the app still works, and admin-only tweaks stay dimmed until you restart elevated."
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 12
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
                M3PillButton {
                    Layout.fillWidth: true
                    label: "Restart as administrator"
                    iconPath: icons.restartAlt
                    emphasized: true
                    implicitHeight: 48
                    onClicked: {
                        optimizer.restartAsAdminFromPrompt()
                        showNextPromptAfterAdmin()
                    }
                }
                M3PillButton {
                    Layout.fillWidth: true
                    label: adminCountdown > 0 ? "Skip (" + adminCountdown + ")" : "Skip"
                    tonal: true
                    implicitHeight: 44
                    interactive: adminCountdown <= 0
                    onClicked: showNextPromptAfterAdmin()
                }
            }
        }
    }

    Rectangle {
        id: introOverlay
        objectName: "introOverlay"
        anchors.fill: parent
        z: 22
        visible: introVisible
        color: "#E61A1C23"

        onVisibleChanged: {
            if (visible) {
                introEntrance.restart()
                introGlowPulse.restart()
                auraPulse.restart()
            } else {
                introGlowPulse.stop()
                auraPulse.stop()
            }
        }

        MouseArea { anchors.fill: parent }

        // Soft ambient color fields floating behind the card for depth.
        Rectangle {
            id: auraOne
            x: 150
            y: 110
            width: 340
            height: 340
            radius: 170
            color: theme.mdTertiary
            opacity: 0.08
            scale: 1.0
        }
        Rectangle {
            id: auraTwo
            x: 820
            y: 420
            width: 300
            height: 300
            radius: 150
            color: theme.mdSecondary
            opacity: 0.07
            scale: 1.0
        }

        // The hero card: layered gradient surface with a lime edge.
        Rectangle {
            id: introCard
            anchors.centerIn: parent
            width: Math.min(580, parent.width - 48)
            height: Math.min(540, parent.height - 40)
            radius: 44
            scale: 0.86
            opacity: 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#3B4311" }
                GradientStop { position: 0.5; color: "#262B36" }
                GradientStop { position: 1.0; color: "#1A1C23" }
            }
            border.color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.35)
            border.width: 1.5

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.22)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 40
                spacing: 0

                // ---- Morphing blob centerpiece with breathing glow ----
                Item {
                    id: introBlobBlock
                    Layout.fillWidth: true
                    Layout.preferredHeight: 172
                    property real introIn: 0
                    opacity: introIn
                    transform: Translate { y: (1 - introBlobBlock.introIn) * 32 }

                    Rectangle {
                        id: introBlobGlow
                        anchors.centerIn: parent
                        width: 200
                        height: 200
                        radius: 100
                        color: theme.mdPrimary
                        opacity: 0.15
                        scale: 1.08

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: theme.mdPrimary
                            opacity: 0.5
                            scale: 0.62
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: theme.mdPrimary
                            opacity: 0.85
                            scale: 0.32
                        }
                    }

                    M3ExpressiveIndicator {
                        id: introBlob
                        anchors.centerIn: parent
                        width: 128
                        height: 128
                        indicatorColor: theme.mdPrimary
                        running: introOverlay.visible
                    }
                }

                // ---- Title ----
                Row {
                    id: titleRow
                    Layout.alignment: Qt.AlignHCenter
                    property real introIn: 0
                    opacity: introIn
                    transform: Translate { y: (1 - titleRow.introIn) * 26 }
                    spacing: 0

                    Text {
                        text: "John's Windows "
                        color: theme.mdOnPrimaryContainer
                        font.pixelSize: 34
                        font.weight: Font.Bold
                        font.family: fontFamily
                    }
                    Text {
                        text: "Fixer"
                        color: theme.mdPrimary
                        font.pixelSize: 34
                        font.weight: Font.Bold
                        font.family: fontFamily
                    }
                }

                Text {
                    id: subtitleIntro
                    Layout.topMargin: 10
                    Layout.fillWidth: true
                    property real introIn: 0
                    opacity: introIn
                    transform: Translate { y: (1 - subtitleIntro.introIn) * 22 }
                    text: "Make Windows faster, cleaner, and more private"
                    color: theme.mdOnPrimaryContainer
                    font.pixelSize: 15
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                // ---- Feature pills ----
                Row {
                    Layout.topMargin: 28
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    Rectangle {
                        id: pill1
                        property real introIn: 0
                        opacity: introIn
                        transform: Translate { y: (1 - pill1.introIn) * 20 }
                        width: pill1Row.implicitWidth + 30
                        height: 40
                        radius: 20
                        color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.10)
                        border.color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.32)
                        border.width: 1

                        Row {
                            id: pill1Row
                            anchors.centerIn: parent
                            spacing: 7
                            M3Icon {
                                iconPath: icons.bolt
                                color: theme.mdPrimary
                                size: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Gaming presets"
                                color: theme.mdOnPrimaryContainer
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: fontFamily
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Rectangle {
                        id: pill2
                        property real introIn: 0
                        opacity: introIn
                        transform: Translate { y: (1 - pill2.introIn) * 20 }
                        width: pill2Row.implicitWidth + 30
                        height: 40
                        radius: 20
                        color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.10)
                        border.color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.32)
                        border.width: 1

                        Row {
                            id: pill2Row
                            anchors.centerIn: parent
                            spacing: 7
                            M3Icon {
                                iconPath: icons.storage
                                color: theme.mdPrimary
                                size: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Storage cleanup"
                                color: theme.mdOnPrimaryContainer
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: fontFamily
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Rectangle {
                        id: pill3
                        property real introIn: 0
                        opacity: introIn
                        transform: Translate { y: (1 - pill3.introIn) * 20 }
                        width: pill3Row.implicitWidth + 30
                        height: 40
                        radius: 20
                        color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.10)
                        border.color: Qt.rgba(223 / 255, 226 / 255, 120 / 255, 0.32)
                        border.width: 1

                        Row {
                            id: pill3Row
                            anchors.centerIn: parent
                            spacing: 7
                            M3Icon {
                                iconPath: icons.shield
                                color: theme.mdPrimary
                                size: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Privacy controls"
                                color: theme.mdOnPrimaryContainer
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                font.family: fontFamily
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // ---- CTA ----
                M3PillButton {
                    id: ctaButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 54
                    property real introIn: 0
                    opacity: introIn
                    transform: Translate { y: (1 - ctaButton.introIn) * 20 }
                    label: "Let's go"
                    iconPath: icons.play
                    emphasized: true
                    fg: theme.mdOnPrimary
                    onClicked: introDismissed()
                }
            }
        }

        // ---- Staggered entrance ----
        SequentialAnimation {
            id: introEntrance

            ParallelAnimation {
                NumberAnimation { target: introCard; property: "scale"; from: 0.86; to: 1.0; duration: 520; easing.type: Easing.OutBack }
                NumberAnimation { target: introCard; property: "opacity"; from: 0; to: 1; duration: 320 }
            }
            PauseAnimation { duration: 70 }
            ParallelAnimation {
                NumberAnimation { target: introBlobBlock; property: "introIn"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: titleRow; property: "introIn"; from: 0; to: 1; duration: 380; easing.type: Easing.OutCubic }
                NumberAnimation { target: subtitleIntro; property: "introIn"; from: 0; to: 1; duration: 340; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: pill1; property: "introIn"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: pill2; property: "introIn"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: pill3; property: "introIn"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: ctaButton; property: "introIn"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
            }
        }

        // ---- Breathing glow behind the blob ----
        SequentialAnimation {
            id: introGlowPulse
            loops: Animation.Infinite
            running: false
            ParallelAnimation {
                NumberAnimation { target: introBlobGlow; property: "opacity"; from: 0.13; to: 0.24; duration: 1300; easing.type: Easing.InOutSine }
                NumberAnimation { target: introBlobGlow; property: "scale"; from: 1.0; to: 1.18; duration: 1300; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
                NumberAnimation { target: introBlobGlow; property: "opacity"; from: 0.24; to: 0.13; duration: 1300; easing.type: Easing.InOutSine }
                NumberAnimation { target: introBlobGlow; property: "scale"; from: 1.18; to: 1.0; duration: 1300; easing.type: Easing.InOutSine }
            }
        }

        // ---- Ambient aura breathing ----
        SequentialAnimation {
            id: auraPulse
            loops: Animation.Infinite
            running: false
            ParallelAnimation {
                NumberAnimation { target: auraOne; property: "opacity"; from: 0.07; to: 0.13; duration: 2800; easing.type: Easing.InOutSine }
                NumberAnimation { target: auraTwo; property: "opacity"; from: 0.06; to: 0.11; duration: 3200; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
                NumberAnimation { target: auraOne; property: "opacity"; from: 0.13; to: 0.07; duration: 2800; easing.type: Easing.InOutSine }
                NumberAnimation { target: auraTwo; property: "opacity"; from: 0.11; to: 0.06; duration: 3200; easing.type: Easing.InOutSine }
            }
        }
    }

    Rectangle {
        id: restoreOverlay
        objectName: "restoreOverlay"
        anchors.fill: parent
        z: 21
        visible: optimizer.restorePointPromptVisible && !introVisible
        color: "#B31A1C23"

        onVisibleChanged: {
            if (visible) {
                restoreCountdown = 5
                restoreTimerActive = true
            } else {
                restoreTimerActive = false
            }
        }
        Component.onCompleted: {
            if (visible) {
                restoreCountdown = 5
                restoreTimerActive = true
            }
        }

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(460, parent.width - 48)
            height: 320
            radius: theme.radiusXl
            color: theme.mdSurfaceContainer
            border.color: theme.mdOutlineVariant
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                M3Icon {
                    Layout.alignment: Qt.AlignHCenter
                    iconPath: icons.restore
                    color: theme.mdPrimary
                    size: 34
                }
                Text {
                    Layout.fillWidth: true
                    text: "Create a restore point?"
                    color: theme.mdOnSurface
                    font.pixelSize: 23
                    font.weight: Font.Bold
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    Layout.fillWidth: true
                    text: "Highly recommended before changing system settings."
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 13
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Text {
                    Layout.fillWidth: true
                    text: "This makes it easy to undo any changes if something goes wrong."
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 12
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
                M3PillButton {
                    Layout.fillWidth: true
                    label: "Create restore point"
                    iconPath: icons.restore
                    emphasized: true
                    implicitHeight: 48
                    onClicked: {
                        optimizer.createRestorePointFromPrompt()
                        showNextPromptAfterRestore()
                    }
                }
                M3PillButton {
                    Layout.fillWidth: true
                    label: restoreCountdown > 0 ? "Skip (" + restoreCountdown + ")" : "Skip"
                    tonal: true
                    implicitHeight: 44
                    interactive: restoreCountdown <= 0
                    onClicked: showNextPromptAfterRestore()
                }
            }
        }
    }

    Rectangle {
        id: profileOverlay
        objectName: "profileOverlay"
        anchors.fill: parent
        z: 20
        visible: firstRunStarted && optimizer.profileNeedsSetup && !introVisible
        color: "#B31A1C23"

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(440, parent.width - 48)
            height: 300
            radius: theme.radiusXl
            color: theme.mdSurfaceContainer
            border.color: theme.mdOutlineVariant
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 12

                M3Icon {
                    Layout.alignment: Qt.AlignHCenter
                    iconPath: icons.settings
                    color: theme.mdPrimary
                    size: 30
                }
                Text {
                    Layout.fillWidth: true
                    text: "How will you use this PC?"
                    color: theme.mdOnSurface
                    font.pixelSize: 23
                    font.weight: Font.Bold
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    Layout.fillWidth: true
                    text: "Choose a starting setup. You can change it later from the Home page."
                    color: theme.mdOnSurfaceVariant
                    font.pixelSize: 13
                    font.family: fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    M3PillButton {
                        Layout.fillWidth: true
                        label: "Gaming"
                        iconPath: icons.bolt
                        emphasized: true
                        implicitHeight: 48
                        onClicked: optimizer.setSelectedPreset("Gaming")
                    }
                    M3PillButton {
                        Layout.fillWidth: true
                        label: "Productivity"
                        iconPath: icons.monitor
                        tonal: true
                        implicitHeight: 48
                        onClicked: optimizer.setSelectedPreset("Productivity")
                    }
                }
            }
        }
    }
}
