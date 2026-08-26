// ── CONFIG ───────────────────────────────────────────────────────
var STATUS_URL = "status.json"; // written once, synchronously, by
                                 // launch.sh before this page opens — just
                                 // the initial state; the Start/Stop
                                 // button below updates the page directly
                                 // from the bridge's response afterward,
                                 // no reload/relaunch needed.
var BRIDGE_URL = null;          // http://127.0.0.1:<bridge_port>/ — set
                                 // once status.json's initial load tells
                                 // us the port; confirmed on-device that
                                 // this webview can XHR to 127.0.0.1
                                 // despite the page itself being file://.

function escapeHtml(s) {
    return String(s)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}

function statRow(label, value) {
    return "<tr><td class='stat-label'>" + escapeHtml(label) + "</td>" +
           "<td class='stat-value'>" + escapeHtml(value) + "</td></tr>";
}

function fetchStatus() {
    var xhr = new XMLHttpRequest();
    xhr.open("GET", STATUS_URL + "?t=" + Date.now(), true);
    xhr.timeout = 5000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        if (xhr.status === 200 || xhr.status === 0) {
            // status 0 is normal for successful file:// XHR in this webview
            var data;
            try { data = JSON.parse(xhr.responseText); }
            catch (e) { setStatus("Parse error"); return; }
            if (data.bridge_port) { BRIDGE_URL = "http://127.0.0.1:" + data.bridge_port + "/"; }
            renderUI(data);
        } else {
            setStatus("Read error " + xhr.status);
        }
    };
    xhr.ontimeout = function() { setStatus("Timeout reading status"); };
    xhr.onerror   = function() { setStatus("Cannot read status.json"); };
    xhr.send();
}

function renderUI(data) {
    var stateEl = document.getElementById("state");
    var detailsSection = document.getElementById("details-section");
    var btn = document.getElementById("toggle-btn");
    var keepawakeCheck = document.getElementById("keepawake-check");

    if (data.running) {
        stateEl.textContent = "RUNNING";
        stateEl.style.background = "#000000";
        stateEl.style.color = "#ffffff";

        var detailsHtml = "<table class='stat-table'>" +
            statRow("Connect", "ssh -p " + data.port + " root@" + data.ip) +
            statRow("Password", data.password || "--") +
            "</table>";
        document.getElementById("details").innerHTML = detailsHtml;
        detailsSection.style.display = "";

        btn.textContent = "Stop Server";
    } else {
        stateEl.textContent = "STOPPED";
        stateEl.style.background = "#ffffff";
        stateEl.style.color = "#000000";

        detailsSection.style.display = "none";

        btn.textContent = "Start Server";
    }
    btn.disabled = !BRIDGE_URL;

    keepawakeCheck.checked = !!data.keepawake;
    keepawakeCheck.disabled = !BRIDGE_URL;

    document.getElementById("update-btn").disabled = !BRIDGE_URL;

    setStatus("Updated " + data.time);
}

function toggleServer() {
    if (!BRIDGE_URL) { return; }
    var btn = document.getElementById("toggle-btn");
    btn.disabled = true;
    setStatus("Working...");

    var xhr = new XMLHttpRequest();
    xhr.open("GET", BRIDGE_URL + "?t=" + Date.now(), true);
    xhr.timeout = 8000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        if (xhr.status === 200 || xhr.status === 0) {
            var data;
            try { data = JSON.parse(xhr.responseText); }
            catch (e) { setStatus("Parse error"); btn.disabled = false; return; }
            renderUI(data);
        } else {
            setStatus("Toggle failed (" + xhr.status + ")");
            btn.disabled = false;
        }
    };
    xhr.ontimeout = function() { setStatus("Toggle timed out"); btn.disabled = false; };
    xhr.onerror   = function() { setStatus("Toggle error"); btn.disabled = false; };
    xhr.send();
}

function toggleKeepawake() {
    if (!BRIDGE_URL) { return; }
    var keepawakeCheck = document.getElementById("keepawake-check");
    keepawakeCheck.disabled = true;
    setStatus("Working...");

    var xhr = new XMLHttpRequest();
    // /keepawake path is what bridge_handler.sh routes on — the plain
    // BRIDGE_URL (no path) request toggleServer() sends is still the
    // server toggle, unchanged.
    xhr.open("GET", BRIDGE_URL + "keepawake?t=" + Date.now(), true);
    xhr.timeout = 8000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        if (xhr.status === 200 || xhr.status === 0) {
            var data;
            try { data = JSON.parse(xhr.responseText); }
            catch (e) { setStatus("Parse error"); keepawakeCheck.disabled = false; return; }
            // Full renderUI, not just the checkbox — the checkbox's own
            // checked state already flipped optimistically when clicked,
            // so this re-syncs it (and everything else) to whatever the
            // device actually did, same pattern toggleServer() uses.
            renderUI(data);
        } else {
            setStatus("Toggle failed (" + xhr.status + ")");
            keepawakeCheck.disabled = false;
        }
    };
    xhr.ontimeout = function() { setStatus("Toggle timed out"); keepawakeCheck.disabled = false; };
    xhr.onerror   = function() { setStatus("Toggle error"); keepawakeCheck.disabled = false; };
    xhr.send();
}

function runUpdate() {
    if (!BRIDGE_URL) { return; }
    var updateBtn = document.getElementById("update-btn");
    updateBtn.disabled = true;
    updateBtn.textContent = "Updating...";
    setStatus("Update started...");

    var xhr = new XMLHttpRequest();
    // /update: bridge_handler.sh kicks off the real install in a
    // detached helper script and responds immediately (this route
    // never waits for the install to finish — see that file for why),
    // so this response only confirms the update started, not its
    // result. There's no reliable "it's done" signal to wait for from
    // here — reopening the app afterward is what shows the real result.
    xhr.open("GET", BRIDGE_URL + "update?t=" + Date.now(), true);
    xhr.timeout = 8000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        updateBtn.textContent = "Check for Update";
        if (xhr.status === 200 || xhr.status === 0) {
            var data;
            try { data = JSON.parse(xhr.responseText); }
            catch (e) { setStatus("Parse error"); updateBtn.disabled = false; return; }
            renderUI(data);
            setStatus("Update started — reopen the app in a few seconds to see the result");
        } else {
            setStatus("Update failed to start (" + xhr.status + ")");
            updateBtn.disabled = false;
        }
    };
    xhr.ontimeout = function() {
        updateBtn.textContent = "Check for Update";
        setStatus("Update request timed out");
        updateBtn.disabled = false;
    };
    xhr.onerror = function() {
        updateBtn.textContent = "Check for Update";
        setStatus("Update request error");
        updateBtn.disabled = false;
    };
    xhr.send();
}

function setStatus(msg) {
    document.getElementById("status-line").innerHTML = msg;
}

document.addEventListener("DOMContentLoaded", function() {
    document.getElementById("toggle-btn").addEventListener("click", toggleServer);
    document.getElementById("keepawake-check").addEventListener("change", toggleKeepawake);
    document.getElementById("update-btn").addEventListener("click", runUpdate);
    fetchStatus();
});
