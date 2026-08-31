import QtQuick

Rectangle {
    id: control
    required property string label
    property bool active: false
    signal clicked()
    width: textItem.implicitWidth + 22; height: 34; radius: 8
    color: hover.hovered ? Qt.rgba(1, 1, 1, 0.055) : "transparent"
    Text { id: textItem; anchors.centerIn: parent; text: control.label; color: control.active ? "#ffffff" : "#b7bfcd"; font.pixelSize: 11; font.weight: control.active ? Font.DemiBold : Font.Normal }
    Rectangle {
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
        width: control.active ? textItem.implicitWidth : 0; height: 1; radius: 1; color: Qt.rgba(1, 1, 1, 0.86)
        Behavior on width { NumberAnimation { duration: 160 } }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: control.clicked() }
}
