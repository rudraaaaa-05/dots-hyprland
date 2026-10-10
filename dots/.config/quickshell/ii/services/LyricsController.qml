pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property bool active: false
    property bool loading: false
    property string error: ""
    property string title: ""
    property string artist: ""
    property string trackKey: ""
    property list<var> lines: []
    property int currentLine: -1
    property bool hasSync: false
    property string stage: ""

    readonly property var player: MprisController.activePlayer
    readonly property bool isSpotify: {
        const entry = player?.desktopEntry?.toLowerCase() ?? "";
        const identity = player?.identity?.toLowerCase() ?? "";
        return entry.includes("spotify") || identity.includes("spotify");
    }
    readonly property string spicyKey: Quickshell.env("SPICY_LYRICS_API_KEY") ?? ""
    readonly property string trackId: {
        const value = String(player?.trackUrl ?? "");
        const match = value.match(/spotify:(?:track:)?([A-Za-z0-9]{22})|open\.spotify\.com\/track\/([A-Za-z0-9]{22})/);
        return match ? (match[1] || match[2]) : "";
    }

    function activate() {
        root.active = true;
        refresh();
    }

    function refresh() {
        if (!root.active || !root.isSpotify || !root.player) {
            clear();
            return;
        }
        const nextTitle = root.player.trackTitle ?? "";
        const nextArtist = root.player.trackArtist ?? "";
        const key = `${nextArtist}\u0000${nextTitle}`;
        if (key === root.trackKey && (root.loading || root.lines.length > 0)) return;

        root.trackKey = key;
        root.title = nextTitle;
        root.artist = nextArtist;
        root.lines = [];
        root.currentLine = -1;
        root.hasSync = false;
        root.error = "";
        root.loading = true;
        root.stage = root.spicyKey && root.trackId ? "spicy" : "lrclib-get";
        request.command = root.stage === "spicy"
            ? ["curl", "--fail", "--silent", "--show-error", "--max-time", "8",
               "-H", `Authorization: ${root.spicyKey}`,
               `https://api.spicylyrics.org/v1/lyrics/${root.trackId}`]
            : ["curl", "--fail", "--silent", "--show-error", "--max-time", "8",
               "-H", "User-Agent: quickshell-lyrics/1.0",
               `https://lrclib.net/api/get?artist_name=${encodeURIComponent(nextArtist)}&track_name=${encodeURIComponent(nextTitle)}`];
        request.running = true;
        timeout.restart();
    }

    function clear() {
        request.running = false;
        timeout.stop();
        root.loading = false;
        root.error = "";
        root.trackKey = "";
        root.title = "";
        root.artist = "";
        root.lines = [];
        root.currentLine = -1;
        root.hasSync = false;
    }

    function parseLrc(response) {
        const parsed = [];
        const synced = response.syncedLyrics ?? "";
        root.hasSync = synced.trim().length > 0;
        for (const line of synced.split(/\r?\n/)) {
            const match = line.match(/\[(\d+):(\d+(?:\.\d+)?)\](.*)/);
            if (match) parsed.push({ time: Number(match[1]) * 60 + Number(match[2]), text: match[3].trim() });
        }
        if (!parsed.length && response.plainLyrics) {
            for (const line of response.plainLyrics.split(/\r?\n/)) parsed.push({ text: line.trim() });
        }
        root.lines = parsed;
        root.error = parsed.length ? "" : "No lyrics found";
        updatePosition();
        return parsed.length > 0;
    }

    function parseSpicy(response) {
        const body = response.Body ?? response.body ?? response;
        const content = body.Content ?? body.content;
        if (!Array.isArray(content)) return false;
        const parsed = [];
        function visit(value, inheritedTime = 0) {
            if (typeof value === "string") {
                if (value.trim()) parsed.push({ time: inheritedTime, text: value.trim() });
            } else if (Array.isArray(value)) {
                value.forEach(item => visit(item, inheritedTime));
            } else if (value && typeof value === "object") {
                const rawTime = value.StartTime ?? value.startTime ?? value.Time ?? value.time;
                const time = Number.isFinite(Number(rawTime)) ? Number(rawTime) : inheritedTime;
                const text = value.Text ?? value.text ?? value.Words ?? value.words;
                if (typeof text === "string" && text.trim()) parsed.push({ time, text: text.trim() });
                else visit(value.Content ?? value.content ?? value.Lines ?? value.lines ?? value.Syllables ?? value.syllables, time);
            }
        }
        visit(content);
        root.lines = parsed.sort((a, b) => a.time - b.time);
        root.hasSync = root.lines.length > 0;
        root.error = root.lines.length ? "" : "No lyrics found";
        updatePosition();
        return root.lines.length > 0;
    }

    function parsePlain(response) {
        const text = response.lyrics ?? "";
        root.hasSync = false;
        root.lines = text.split(/\r?\n/).map(line => ({ text: line.trim() })).filter(line => line.text);
        root.error = root.lines.length ? "" : "No lyrics found";
        return root.lines.length > 0;
    }

    function retryFallback() {
        if (root.stage === "lrclib-get") {
            root.stage = "lrclib-search";
            request.command = ["curl", "--fail", "--silent", "--show-error", "--max-time", "8",
                "-H", "User-Agent: quickshell-lyrics/1.0",
                `https://lrclib.net/api/search?artist_name=${encodeURIComponent(root.artist)}&track_name=${encodeURIComponent(root.title)}`];
            request.running = true;
            timeout.restart();
            return true;
        }
        if (root.stage === "lrclib-search") {
            root.stage = "lyrics-ovh";
            request.command = ["curl", "--fail", "--silent", "--show-error", "--max-time", "8",
                `https://api.lyrics.ovh/v1/${encodeURIComponent(root.artist)}/${encodeURIComponent(root.title)}`];
            request.running = true;
            timeout.restart();
            return true;
        }
        return false;
    }

    function updatePosition() {
        if (!root.hasSync || !root.player) return;
        let selected = -1;
        const position = root.player.position ?? 0;
        for (let i = 0; i < root.lines.length; ++i) {
            if (root.lines[i].time <= position) selected = i;
            else break;
        }
        root.currentLine = selected;
    }

    Process {
        id: request
        stdout: StdioCollector {
            onStreamFinished: {
                timeout.stop();
                try {
                    const response = JSON.parse(text);
                    const success = root.stage === "spicy"
                        ? root.parseSpicy(response)
                        : root.stage === "lyrics-ovh" ? root.parsePlain(response) : root.parseLrc(response);
                    if (!success && (root.stage === "spicy" || root.stage === "lrclib-get" || root.stage === "lrclib-search")) {
                        if (root.stage === "spicy") {
                            root.stage = "lrclib-get";
                            root.trackKey = "";
                            root.refresh();
                        } else {
                            root.retryFallback();
                        }
                    } else {
                        root.loading = false;
                    }
                } catch (error) {
                    if (!root.retryFallback()) {
                        root.loading = false;
                        root.error = "Lyrics unavailable";
                    }
                }
            }
        }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (code !== 0 && root.loading) {
                timeout.stop();
                if (!root.retryFallback()) {
                    root.loading = false;
                    root.error = "Lyrics unavailable";
                }
            }
        }
    }

    Timer {
        id: timeout
        interval: 10000
        onTriggered: {
            request.running = false;
            root.loading = false;
            root.error = "Lyrics request timed out";
        }
    }

    Timer {
        interval: 500
        repeat: true
        running: root.active && root.hasSync && root.player?.isPlaying === true
        onTriggered: root.updatePosition()
    }

    Connections {
        target: root.player
        function onPostTrackChanged() { root.refresh(); }
        function onPlaybackStateChanged() { root.updatePosition(); }
    }
    Connections {
        target: MprisController
        function onActivePlayerChanged() { root.refresh(); }
    }
}
