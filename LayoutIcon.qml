import QtQuick

Item {
    id: control
    required property string glyph
    required property string label
    property bool active: false
    signal clicked()

    width: 38; height: 38

    Rectangle {
        anchors.fill: parent
        radius: 19
        color: control.active ? Qt.rgba(1, 1, 1, 0.16)
                              : (hover.hovered ? Qt.rgba(1, 1, 1, 0.075) : "transparent")
        border.width: 0
        Behavior on color { ColorAnimation { duration: 140 } }

        Text {
            anchors.centerIn: parent
            text: control.glyph
            color: control.active ? "#ffffff" : "#b8c0cf"
            font.pixelSize: 18
        }
    }

    Rectangle {
        visible: hover.hovered
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top; anchors.bottomMargin: 7
        width: tip.implicitWidth + 18; height: 26; radius: 8
        color: Qt.rgba(0.06, 0.07, 0.09, 0.9)
        border.width: 1; border.color: Qt.rgba(0.78, 0.84, 0.94, 0.2)
        Text { id: tip; anchors.centerIn: parent; text: control.label; color: "#dce3ef"; font.pixelSize: 10 }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: control.clicked() }
}
