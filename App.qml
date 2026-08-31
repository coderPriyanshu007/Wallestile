pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Rectangle {
    id: root
    color: Qt.rgba(0.025, 0.03, 0.045, 0.56)
    focus: true

    property string source: "wallhaven"
    property string style: "ring"
    property string browseFilter: "latest"
    property string query: ""
    property int page: 1
    property int selected: 0
    property var results: []
    property bool busy: false
    property string message: ""
    property bool appendResults: false
    property int pendingSelection: -1
    property bool sourceMenuOpen: false
    property int wallpaperRevision: 0
    readonly property var current: results.length > 0 ? results[Math.max(0, Math.min(selected, results.length - 1))] : null
    readonly property string script: Quickshell.shellDir + "/fetch_wallpapers.py"
    readonly property string caelestiaState: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/caelestia"
    readonly property string stateDir: caelestiaState + "/wallpaper"

    function search(resetPage, append) {
        if (resetPage) page = 1;
        appendResults = !!append;
        busy = true; message = "Fetching " + (source === "wallhaven" ? "Wallhaven" : "MoeWalls") + "…";
        searchProc.command = ["python3", script, "search", "--source", source, "--query", query,
                              "--page", "" + page, "--filter", browseFilter];
        searchProc.running = true;
    }
    function loadNext(requestedIndex) {
        if (busy) return;
        pendingSelection = requestedIndex === undefined ? results.length : requestedIndex;
        page++;
        search(false, true);
    }
    function choose(i) { if (i >= 0 && i < results.length) selected = i; }
    function move(delta) {
        if (!results.length) return;
        var wanted = selected + delta;
        if (wanted >= results.length) { loadNext(wanted); return; }
        selected = Math.max(0, wanted);
        if (style === "grid") grid.positionViewAtIndex(selected, GridView.Contain);
    }
    function applyCurrent() {
        if (!current || busy) return;
        busy = true; message = "Downloading full wallpaper…";
        downloadProc.command = ["python3", script, "download", "--url", current.full,
                                "--source", current.source, "--id", current.id];
        downloadProc.running = true;
    }
    Component.onCompleted: { forceActiveFocus(); search(true); }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_B && (event.modifiers & Qt.MetaModifier))) Qt.quit();
        else if (event.key === Qt.Key_Left) move(-1);
        else if (event.key === Qt.Key_Right) move(1);
        else if (event.key === Qt.Key_Up && style === "grid") move(-Math.max(2, Math.floor(stage.width / 330)));
        else if (event.key === Qt.Key_Down && style === "grid") move(Math.max(2, Math.floor(stage.width / 330)));
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) applyCurrent();
        else return;
        event.accepted = true;
    }

    Process {
        id: searchProc
        property string output: ""
        stdout: StdioCollector { onStreamFinished: searchProc.output = text }
        stderr: StdioCollector { onStreamFinished: root.message = text.trim() }
        onExited: code => {
            root.busy = false;
            if (code !== 0) {
                if (root.appendResults) root.page = Math.max(1, root.page - 1);
                root.pendingSelection = -1;
                if (!root.message) root.message = "Could not reach the wallpaper source";
                return;
            }
            var rows = [], lines = output.split("\n");
            try { for (var i = 0; i < lines.length; i++) if (lines[i].trim()) rows.push(JSON.parse(lines[i])); }
            catch (e) { root.message = "The source returned an unexpected response"; return; }
            if (root.appendResults) {
                var merged = root.results.slice(), known = {};
                for (var k = 0; k < merged.length; k++) known[merged[k].source + ":" + merged[k].id] = true;
                for (var j = 0; j < rows.length; j++) {
                    var key = rows[j].source + ":" + rows[j].id;
                    if (!known[key]) { known[key] = true; merged.push(rows[j]); }
                }
                root.results = merged;
                if (root.pendingSelection >= 0 && merged.length > 0)
                    root.selected = Math.min(root.pendingSelection, merged.length - 1);
            } else {
                root.results = rows; root.selected = 0;
            }
            root.pendingSelection = -1;
            root.message = rows.length ? root.results.length + " wallpapers · through page " + root.page : "No more wallpapers";
        }
    }
    Process {
        id: downloadProc
        property string path: ""
        stdout: StdioCollector { onStreamFinished: downloadProc.path = text.trim() }
        stderr: StdioCollector { onStreamFinished: root.message = text.trim() }
        onExited: code => {
            if (code !== 0 || !path) { root.busy = false; if (!root.message) root.message = "Download failed"; return; }
            root.message = "Applying wallpaper…";
            // Use the same resident service as Caelestia's own picker. Besides
            // launching the CLI, it updates Wallpapers.actualCurrent immediately,
            // which keeps the live wallpaper and Colours singletons in sync.
            applyProc.wallpaperPath = path;
            applyProc.command = ["qs", "-c", "caelestia", "ipc", "call", "wallpaper", "set", path];
            applyProc.running = true;
        }
    }
    Process {
        id: applyProc
        property string wallpaperPath: ""
        onExited: code => {
            if (code === 0) {
                root.busy = false;
                root.message = "Wallpaper and palette requested";
            } else {
                // Headless/non-Caelestia sessions still get a functional fallback.
                fallbackApply.command = ["caelestia", "wallpaper", "-f", wallpaperPath];
                fallbackApply.running = true;
            }
        }
    }
    Process {
        id: fallbackApply
        onExited: code => {
            root.busy = false;
            root.message = code === 0 ? "Wallpaper and palette applied" : "Caelestia could not apply this wallpaper";
        }
    }

    FileView {
        id: wallpaperState
        path: root.stateDir + "/path.txt"
        blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: { reload(); root.wallpaperRevision++; }
        onLoaded: root.wallpaperRevision++
    }

    Image {
        anchors.fill: parent
        source: root.current
            ? (root.current.source === "moewalls"
                ? (root.current.thumb || "")
                : (root.current.full || root.current.thumb || ""))
            : ("file://" + root.stateDir + "/thumbnail.jpg?v=" + root.wallpaperRevision)
        fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
        opacity: status === Image.Ready ? 1 : 0
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.72
            blurMax: 48
        }
        Behavior on opacity { NumberAnimation { duration: 260 } }
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.012, 0.015, 0.024, 0.54) }

    Column {
        anchors.fill: parent; anchors.margins: Math.max(24, Math.min(width, height) * 0.035); spacing: 8

        Item {
            id: stage; width: parent.width; height: parent.height - 62

            Row {
                anchors.left: parent.left; anchors.top: parent.top
                anchors.topMargin: 2; spacing: 10; z: 1000
                Text { text: "◭"; color: "#dce7ff"; font.pixelSize: 30; font.weight: Font.DemiBold }
                Text { text: "CAELESTIA"; color: "#eef3ff"; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 2.2; anchors.verticalCenter: parent.verticalCenter }
            }

            TextField {
                id: searchBox
                anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top
                width: Math.min(470, parent.width * 0.38); height: 44; z: 1000
                placeholderText: "Search wallpapers…"; color: "white"; placeholderTextColor: "#9da7b8"
                horizontalAlignment: TextInput.AlignHCenter; leftPadding: 42; rightPadding: 42
                background: Rectangle {
                    radius: 14; color: Qt.rgba(1, 1, 1, 0.065)
                    border.width: searchBox.activeFocus ? 1 : 0
                    border.color: Qt.rgba(0.82, 0.9, 1, 0.42)
                }
                onAccepted: { root.query = text; root.search(true); root.forceActiveFocus(); }
            }

            Row {
                anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 5
                spacing: 16; z: 1000
                Text {
                    text: "ARCH  ×  HYPRLAND"; color: "#c7d0df"; font.pixelSize: 10
                    font.weight: Font.Medium; font.letterSpacing: 1.8; anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "CLOSE"; color: topCloseHover.hovered ? "#ffffff" : "#aeb7c6"
                    font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    HoverHandler { id: topCloseHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Qt.quit() }
                }
            }

            GridView {
                id: grid; anchors.fill: parent; visible: root.style === "grid"; clip: true
                cellWidth: Math.floor(width / Math.max(2, Math.floor(width / 330))); cellHeight: cellWidth * 0.62
                model: root.results; cacheBuffer: 1200
                onAtYEndChanged: if (atYEnd && visible && !root.busy && root.results.length > 0) root.loadNext(root.results.length)
                delegate: WallCard { required property var modelData; required property int index; width: grid.cellWidth - 14; height: grid.cellHeight - 14; item: modelData; active: index === root.selected; onPicked: root.choose(index); onApplied: root.applyCurrent() }
            }

            Item {
                anchors.fill: parent; visible: root.style === "carousel"
                Repeater {
                    model: root.results
                    WallCard {
                        required property var modelData; required property int index
                        property int offset: index - root.selected
                        visible: Math.abs(offset) <= 3; width: Math.min(720, stage.width * 0.56); height: width * 0.61
                        x: stage.width / 2 - width / 2 + offset * width * 0.53
                        y: stage.height / 2 - height / 2 + Math.abs(offset) * 30
                        scale: Math.max(0.62, 1 - Math.abs(offset) * 0.14); opacity: Math.max(0.6, 1 - Math.abs(offset) * 0.13)
                        z: 10 - Math.abs(offset); item: modelData; active: index === root.selected
                        Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 260 } }
                        onPicked: root.choose(index); onApplied: root.applyCurrent()
                    }
                }
            }

            Item {
                anchors.fill: parent; visible: root.style === "orbit"
                Repeater {
                    model: root.results
                    WallCard {
                        required property var modelData; required property int index
                        property int offset: index - root.selected
                        property int distance: Math.abs(offset)
                        visible: distance <= 4; width: Math.min(520, stage.width * 0.38); height: width * 0.64
                        x: stage.width / 2 - width / 2 + offset * Math.min(178, stage.width * 0.115)
                        y: stage.height / 2 - height / 2 + distance * 34 + (distance > 2 ? 18 : 0)
                        scale: Math.max(0.54, 1 - distance * 0.13)
                        opacity: Math.max(0.64, 1 - distance * 0.1)
                        z: 100 - distance; rotation: offset * 5.5; item: modelData; active: index === root.selected
                        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 320 } }
                        onPicked: root.choose(index); onApplied: root.applyCurrent()
                    }
                }
            }

            Item {
                anchors.fill: parent; visible: root.style === "ring"
                Repeater {
                    model: root.results
                    WallCard {
                        required property var modelData; required property int index
                        property real angle: (index - root.selected) * 34
                        property real rad: angle * Math.PI / 180
                        visible: Math.abs(index - root.selected) <= 5
                        width: Math.min(520, stage.width * 0.39); height: width * 0.64
                        x: stage.width / 2 - width / 2 + Math.sin(rad) * Math.min(610, stage.width * 0.39)
                        y: stage.height / 2 - height / 2 + (1 - Math.cos(rad)) * 125
                        scale: 0.56 + Math.max(0, Math.cos(rad)) * 0.44
                        opacity: 0.6 + Math.max(0, Math.cos(rad)) * 0.4
                        z: 100 + Math.cos(rad) * 50
                        rotation: angle * -0.22
                        item: modelData; active: index === root.selected
                        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 320 } }
                        onPicked: root.choose(index); onApplied: root.applyCurrent()
                    }
                }
            }

            Item {
                anchors.fill: parent; visible: root.style === "crown"
                Repeater {
                    model: root.results
                    WallCard {
                        id: crownCard
                        required property var modelData; required property int index
                        property int rawOffset: index - root.selected
                        property int crownOffset: {
                            if (root.results.length < 2) return rawOffset;
                            if (rawOffset > root.results.length / 2) return rawOffset - root.results.length;
                            if (rawOffset < -root.results.length / 2) return rawOffset + root.results.length;
                            return rawOffset;
                        }
                        property int distance: Math.abs(crownOffset)
                        property real arcAngle: 180 + crownOffset * 30
                        property real arcRad: arcAngle * Math.PI / 180
                        property real frontDepth: (1 - Math.cos(arcRad)) / 2

                        // Twelve unique positions complete the loop. Excluding
                        // the duplicate -6 slot prevents two cards sharing the
                        // exact rear/top point of the circle.
                        visible: crownOffset >= -5 && crownOffset <= 6
                        width: Math.min(300, stage.width * 0.21)
                        height: Math.min(420, stage.height * 0.52)
                        x: stage.width / 2 - width / 2 + Math.sin(arcRad) * Math.min(440, stage.width * 0.29)
                        y: stage.height / 2 - height / 2 - Math.cos(arcRad) * Math.min(200, stage.height * 0.23) - 40
                        scale: 0.64 + frontDepth * 0.36
                        opacity: 0.68 + frontDepth * 0.32
                        z: 60 + frontDepth * 100
                        rotation: 0
                        item: modelData; active: index === root.selected
                        transform: Rotation {
                            origin.x: crownCard.width / 2; origin.y: crownCard.height / 2
                            axis.x: 0; axis.y: 1; axis.z: 0
                            angle: -Math.sin(crownCard.arcRad) * 38
                        }

                        Behavior on x { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 240 } }
                        onPicked: root.choose(index); onApplied: root.applyCurrent()
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.style === "stack"

                Repeater {
                    model: root.results
                    WallCard {
                        required property var modelData
                        required property int index
                        property int stackOffset: index - root.selected

                        visible: stackOffset >= 0 && stackOffset <= 4
                        width: Math.min(440, stage.width * 0.31)
                        height: Math.min(570, stage.height * 0.68)
                        x: stage.width / 2 - width / 2 - 105 + stackOffset * 58
                        y: stage.height / 2 - height / 2 + Math.abs(stackOffset - 2) * 7
                        rotation: -10 + stackOffset * 5.5
                        scale: 1 - stackOffset * 0.025
                        opacity: 1 - stackOffset * 0.075
                        z: 50 - stackOffset
                        item: modelData
                        active: index === root.selected

                        Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 240 } }

                        onPicked: root.choose(index)
                        onApplied: root.applyCurrent()
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.style === "deck"

                Repeater {
                    model: root.results
                    WallCard {
                        required property var modelData
                        required property int index
                        property int deckOffset: index - root.selected

                        visible: deckOffset >= 0 && deckOffset <= 5
                        width: Math.min(560, stage.width * 0.4)
                        height: width * 0.62
                        x: stage.width / 2 - width / 2
                        y: stage.height / 2 - height / 2 - 105 + deckOffset * 56
                        scale: 1 - deckOffset * 0.055
                        opacity: 1 - deckOffset * 0.07
                        z: 70 - deckOffset
                        item: modelData
                        active: index === root.selected

                        Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 240 } }

                        onPicked: root.choose(index)
                        onApplied: root.applyCurrent()
                    }
                }
            }

            Rectangle {
                id: layoutDock
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                width: layoutIcons.width + 14; height: 44; radius: 22
                color: Qt.rgba(1, 1, 1, 0.075)
                border.width: 0
                z: 500
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#000000"
                    shadowOpacity: 0.32
                    shadowBlur: 1.0
                    shadowVerticalOffset: 7
                    blurMax: 34
                    autoPaddingEnabled: true
                }

                Row {
                    id: layoutIcons
                    anchors.centerIn: parent; spacing: 2
                    LayoutIcon { glyph: "▦"; label: "Grid"; active: root.style === "grid"; onClicked: root.style = "grid" }
                    LayoutIcon { glyph: "◫"; label: "Carousel"; active: root.style === "carousel"; onClicked: root.style = "carousel" }
                    LayoutIcon { glyph: "◉"; label: "Orbit"; active: root.style === "orbit"; onClicked: root.style = "orbit" }
                    LayoutIcon { glyph: "◎"; label: "3D Ring"; active: root.style === "ring"; onClicked: root.style = "ring" }
                    LayoutIcon { glyph: "⌒"; label: "Crown"; active: root.style === "crown"; onClicked: root.style = "crown" }
                    LayoutIcon { glyph: "▱"; label: "Stack"; active: root.style === "stack"; onClicked: root.style = "stack" }
                    LayoutIcon { glyph: "≡"; label: "Deck"; active: root.style === "deck"; onClicked: root.style = "deck" }
                }
            }
            BusyIndicator { anchors.centerIn: parent; running: root.busy; visible: running }
        }

        Item {
            width: parent.width; height: 54

            Item {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: 168; height: 50; z: 1200
                Text { text: "SOURCE"; color: "#8f95a6"; font.pixelSize: 8; font.letterSpacing: 1.4 }
                Rectangle {
                    id: sourceButton
                    anchors.left: parent.left; anchors.bottom: parent.bottom
                    width: 154; height: 34; radius: 10
                    color: Qt.rgba(1, 1, 1, sourceHover.hovered ? 0.1 : 0.06)
                    Text { anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: root.source === "wallhaven" ? "Wallhaven" : "MoeWalls"; color: "white"; font.pixelSize: 11; font.weight: Font.Medium }
                    Text { anchors.right: parent.right; anchors.rightMargin: 11; anchors.verticalCenter: parent.verticalCenter; text: root.sourceMenuOpen ? "⌃" : "⌄"; color: "#aeb7c6"; font.pixelSize: 12 }
                    HoverHandler { id: sourceHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.sourceMenuOpen = !root.sourceMenuOpen }
                }
                Rectangle {
                    visible: root.sourceMenuOpen
                    anchors.left: sourceButton.left; anchors.bottom: sourceButton.top; anchors.bottomMargin: 8
                    width: sourceButton.width; height: 76; radius: 12; color: Qt.rgba(0.055, 0.065, 0.085, 0.96)
                    Column {
                        anchors.fill: parent; anchors.margins: 4; spacing: 2
                        Selector { width: parent.width; label: "Wallhaven"; active: root.source === "wallhaven"; onClicked: { root.sourceMenuOpen = false; root.source = "wallhaven"; root.browseFilter = "latest"; root.search(true); } }
                        Selector { width: parent.width; label: "MoeWalls"; active: root.source === "moewalls"; onClicked: { root.sourceMenuOpen = false; root.source = "moewalls"; root.browseFilter = "latest"; root.search(true); } }
                    }
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
                width: filterRow.width + 18; height: 42; radius: 21
                color: Qt.rgba(1, 1, 1, 0.055)
                Row {
                    id: filterRow; anchors.centerIn: parent; spacing: 2
                    Selector { label: "Latest"; active: root.browseFilter === "latest"; onClicked: { root.browseFilter = "latest"; root.search(true); } }
                    Selector { label: root.source === "wallhaven" ? "Toplist" : "Anime"; active: root.browseFilter === (root.source === "wallhaven" ? "toplist" : "anime"); onClicked: { root.browseFilter = root.source === "wallhaven" ? "toplist" : "anime"; root.search(true); } }
                    Selector { visible: root.source === "moewalls"; label: "Games"; active: root.browseFilter === "games"; onClicked: { root.browseFilter = "games"; root.search(true); } }
                    Selector { visible: root.source === "moewalls"; label: "Landscape"; active: root.browseFilter === "landscape"; onClicked: { root.browseFilter = "landscape"; root.search(true); } }
                }
            }

            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                Selector { label: "‹"; active: false; onClicked: { if (root.page > 1) { root.page--; root.search(false); } } }
                Text { text: root.page + " / ∞"; color: "#d4d7e0"; font.pixelSize: 10; font.letterSpacing: 1.5; anchors.verticalCenter: parent.verticalCenter }
                Selector { label: "›"; active: false; onClicked: root.loadNext(root.results.length) }
            }
        }
    }
}
