import QtQuick
import QtQuick.Layouts
import qs
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root

    title: "Visualizer"
    showCenterButton: true
    minimumWidth: 320
    minimumHeight: 150
    collapseHeaderWhenClosed: true
    collapseContentPaddingWhenClosed: true
    padding: 0
    resizeMargin: 2

    property real phase: 0
    readonly property bool animating: GlobalStates.overlayOpen || root.actuallyPinned
    property list<real> spectrum: []
    property bool waveMode: false
    readonly property real responseGain: 0.88

    function spectrumSample(position) {
        if (root.spectrum.length === 0) return 0;
        const scaled = Math.max(0, Math.min(root.spectrum.length - 1, position * (root.spectrum.length - 1)));
        const left = Math.floor(scaled);
        const right = Math.min(root.spectrum.length - 1, left + 1);
        const fraction = scaled - left;
        return (root.spectrum[left] * (1 - fraction) + root.spectrum[right] * fraction) / 100;
    }

    Timer {
        interval: 50
        repeat: true
        running: root.animating
        onTriggered: {
            root.phase += 0.18;
        }
    }

Process {
    id: cavaProc
    running: root.animating
    command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]

    onRunningChanged: {
        if (!running) root.spectrum = [];
    }

    stdout: SplitParser {
        onRead: data => {
            const next = data.split(";")
                .map(value => Number(value.trim()))
                .filter(value => Number.isFinite(value));
            const peak = Math.max(1, ...next);
            root.spectrum = next.map((value, index) => {
                const normalized = value / peak * 100;
                const previous = root.spectrum[index] ?? normalized;
                return previous * 0.82 + normalized * 0.18;
            });
        }
    }
}

    contentItem: OverlayBackground {
        id: contentBackground
        radius: root.contentRadius
        color: GlobalStates.overlayOpen
            ? Appearance.colors.colLayer1
            : "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: GlobalStates.overlayOpen ? 12 : 0
            anchors.bottomMargin: GlobalStates.overlayOpen ? 12 : 0
            spacing: 8

            RowLayout {
                visible: GlobalStates.overlayOpen
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: modeButton
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: height / 2
                    toggled: root.waveMode
                    onClicked: root.waveMode = !root.waveMode
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive

                    contentItem: Item {
                        anchors.fill: parent
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.waveMode ? "graphic_eq" : "bar_chart"
                            fill: modeButton.toggled
                            iconSize: 18
                            color: modeButton.toggled
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnSurface
                        }
                    }

                    StyledToolTip {
                        text: root.waveMode ? "Show bars" : "Show wave"
                    }
                }

                StyledText {
                    text: `${Math.round(Audio.value * 100)}%`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }

            Item {
                id: bars
                visible: !root.waveMode
                Layout.fillWidth: true
                Layout.preferredHeight: root.waveMode ? 0 : 92
                Layout.fillHeight: true

                Row {
                    anchors.fill: parent
                    anchors.bottomMargin: 2
                    spacing: 0.5

                    Repeater {
                        model: 200

                        Rectangle {
                            required property int index
                            width: Math.max(0.25, (bars.width - 99.5) / 200)
                            readonly property real sample: root.spectrumSample(index / 199)
                            height: Math.max(2, bars.height * Math.min(0.94, Math.sqrt(sample) * root.responseGain))
                            anchors.bottom: parent.bottom
                            radius: width / 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            Item {
                id: wave
                visible: root.waveMode
                Layout.fillWidth: true
                Layout.preferredHeight: root.waveMode ? 92 : 0

                Canvas {
                    id: waveCanvas
                    anchors.fill: parent
                    antialiasing: true

                    Connections {
                        target: root
                        function onSpectrumChanged() { waveCanvas.requestPaint(); }
                        function onPhaseChanged() { waveCanvas.requestPaint(); }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.clearRect(0, 0, width, height);

                        var samples = root.spectrum;
                        var baseline = height;
                        var maxAmp = (height - 2) * root.responseGain;
                        var points = 64;

                        ctx.beginPath();
                        ctx.moveTo(0, height);
                        ctx.beginPath();

                        for (var i = 0; i <= points; i++) {
                            var t = i / points;
                            var x = t * width;
                            var sampleIndex = samples.length > 0
                                ? Math.min(samples.length - 1, Math.floor(t * samples.length))
                                : 0;
                            var amp = root.spectrumSample(t);
                            var y = baseline - (0.35 + 0.65 * Math.abs(
                                Math.sin(t * Math.PI * 4 + root.phase)
                            )) * amp * maxAmp;

                            if (i === 0) ctx.moveTo(x, y);
                            else ctx.lineTo(x, y);
                        }

                        ctx.lineTo(width, height);
                        ctx.lineTo(0, height);
                        ctx.closePath();
                        ctx.fillStyle = Qt.rgba(
                            Appearance.colors.colPrimary.r,
                            Appearance.colors.colPrimary.g,
                            Appearance.colors.colPrimary.b,
                            0.35
                        );
                        ctx.fill();

                        ctx.beginPath();
                        for (var j = 0; j <= points; j++) {
                            var lineT = j / points;
                            var lineX = lineT * width;
                            var lineIndex = samples.length > 0
                                ? Math.min(samples.length - 1, Math.floor(lineT * samples.length))
                                : 0;
                            var lineAmp = samples.length > 0 ? (samples[lineIndex] / 100) : 0;
                            var lineY = baseline - (0.35 + 0.65 * Math.abs(
                                Math.sin(lineT * Math.PI * 4 + root.phase)
                            )) * lineAmp * maxAmp;
                            if (j === 0) ctx.moveTo(lineX, lineY);
                            else ctx.lineTo(lineX, lineY);
                        }
                        ctx.strokeStyle = Appearance.colors.colPrimary;
                        ctx.lineWidth = 1.5;
                        ctx.stroke();
                    }
                }
            }
        }
    }
}