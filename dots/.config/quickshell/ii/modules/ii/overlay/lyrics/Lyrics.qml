import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root

    title: "Lyrics"
    showCenterButton: true
    minimumWidth: 320
    minimumHeight: 220

    function syncServiceActivity() {
        LyricsController.active = GlobalStates.overlayOpen || root.actuallyPinned;
        if (LyricsController.active) LyricsController.refresh();
    }

    Component.onCompleted: syncServiceActivity()
    Component.onDestruction: LyricsController.active = false
    onActuallyPinnedChanged: syncServiceActivity()

    Connections {
        target: GlobalStates
        function onOverlayOpenChanged() {
            root.syncServiceActivity();
        }
    }

    contentItem: OverlayBackground {
        id: contentBackground
        radius: root.contentRadius

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "lyrics"
                    iconSize: 20
                    color: Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: LyricsController.title || "Spotify"
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: LyricsController.artist
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }

            StyledText {
                visible: LyricsController.loading
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: "Loading lyrics..."
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            StyledText {
                visible: !LyricsController.loading && LyricsController.lines.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: LyricsController.isSpotify ? (LyricsController.error || "No lyrics found") : "Spotify not playing"
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
            }

            ListView {
                id: lyricsList
                visible: !LyricsController.loading && LyricsController.lines.length > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 7
                model: LyricsController.lines
                boundsBehavior: Flickable.StopAtBounds
                delegate: StyledText {
                    required property var modelData
                    required property int index
                    width: lyricsList.width
                    text: modelData.text || "♪"
                    color: LyricsController.hasSync && index === LyricsController.currentLine
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnLayer1
                    font.pixelSize: LyricsController.hasSync && index === LyricsController.currentLine
                        ? Appearance.font.pixelSize.large
                        : Appearance.font.pixelSize.normal
                    font.weight: LyricsController.hasSync && index === LyricsController.currentLine
                        ? Font.Bold
                        : Font.Normal
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                Connections {
                    target: LyricsController
                    function onCurrentLineChanged() {
                        if (LyricsController.currentLine >= 0)
                            lyricsList.positionViewAtIndex(LyricsController.currentLine, ListView.Center);
                    }
                }
            }
        }
    }
}
