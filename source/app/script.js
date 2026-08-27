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
    document.getElementById("set-password-btn").disabled = !BRIDGE_URL;

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

var UPDATE_POLL_MAX = 20;       // 20 * 1.5s = 30s max wait for a result
var UPDATE_POLL_INTERVAL = 1500;

function updateBtnReset() {
    var updateBtn = document.getElementById("update-btn");
    updateBtn.textContent = "Check for Update";
    updateBtn.disabled = !BRIDGE_URL;
}

function runUpdate() {
    if (!BRIDGE_URL) { return; }
    var updateBtn = document.getElementById("update-btn");
    updateBtn.disabled = true;
    updateBtn.textContent = "Checking...";
    setStatus("Checking for update...");

    var xhr = new XMLHttpRequest();
    // /update only kicks off the real install in a detached helper
    // script and responds immediately (see bridge_handler.sh for why:
    // kpm install replaces the app's own files, including whichever
    // script is still running at the time). This response just confirms
    // it started — pollUpdateResult() below is what finds out what
    // actually happened.
    xhr.open("GET", BRIDGE_URL + "update?t=" + Date.now(), true);
    xhr.timeout = 8000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        if (xhr.status === 200 || xhr.status === 0) {
            pollUpdateResult(0);
        } else {
            setStatus("Update failed to start (" + xhr.status + ")");
            updateBtnReset();
        }
    };
    xhr.ontimeout = function() { setStatus("Update request timed out"); updateBtnReset(); };
    xhr.onerror   = function() { setStatus("Update request error"); updateBtnReset(); };
    xhr.send();
}

function pollUpdateResult(attempt) {
    // update_helper.sh writes update_result.json only once it's actually
    // done (including the before/after version compare, so this can
    // honestly distinguish "nothing changed" from "updated" — kpm
    // install's own output can't, it always reports "upgrading" even for
    // an identical version). Polled as a plain file:// fetch, same
    // pattern as status.json's own fetch, not through the HTTP bridge.
    var xhr = new XMLHttpRequest();
    xhr.open("GET", "update_result.json?t=" + Date.now(), true);
    xhr.timeout = 5000;

    var next = function() {
        if (attempt < UPDATE_POLL_MAX) {
            // Old webview here — no String.prototype.repeat, build the
            // dots by hand instead.
            var dots = "";
            for (var i = 0; i <= (attempt % 3); i++) { dots += "."; }
            setStatus("Updating" + dots);
            setTimeout(function() { pollUpdateResult(attempt + 1); }, UPDATE_POLL_INTERVAL);
        } else {
            setStatus("Still working — reopen the app in a moment to check");
            updateBtnReset();
        }
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        var data = null;
        if (xhr.status === 200 || xhr.status === 0) {
            try { data = JSON.parse(xhr.responseText); } catch (e) { data = null; }
        }
        if (data && data.done) {
            if (data.updated) {
                // A real version change may have altered index.html/
                // script.js/style.css themselves (new buttons, fields,
                // etc.) -- renderUI() alone only updates data inside the
                // page that's already loaded, it can't retroactively add
                // HTML that didn't exist when this page was parsed.
                // Confirmed the hard way: a real update landed fine, but
                // a brand new UI section just never appeared until the
                // app was manually reopened. A real reload re-fetches
                // the actual files, so it can't miss this on any future
                // update, structural or not. Held long enough to
                // actually read the message first, and skipped entirely
                // on "already up to date" (below) since nothing to
                // reload for.
                setStatus("Updated to v" + data.version + "! Reloading...");
                setTimeout(function() { location.reload(); }, 1800);
            } else {
                renderUI(data);
                setStatus("Already up to date (v" + data.version + ")");
                updateBtnReset();
            }
        } else {
            next();
        }
    };
    xhr.ontimeout = next;
    xhr.onerror = next; // the result file not existing yet also lands here for file:// XHR
    xhr.send();
}

function setPassword() {
    if (!BRIDGE_URL) { return; }
    var input = document.getElementById("new-password-input");
    var btn = document.getElementById("set-password-btn");
    var pw = input.value;
    if (!pw) { setStatus("Enter a password first"); return; }

    btn.disabled = true;
    setStatus("Setting password...");

    var xhr = new XMLHttpRequest();
    // encodeURIComponent on the way out, matched by bridge_handler.sh's
    // own url-decode on the way in — this is the one action here that
    // sends real user input across the bridge, everything else so far
    // has just been a bare toggle.
    xhr.open("GET", BRIDGE_URL + "setpassword?pw=" + encodeURIComponent(pw) + "&t=" + Date.now(), true);
    xhr.timeout = 8000;

    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) { return; }
        if (xhr.status === 200 || xhr.status === 0) {
            var data;
            try { data = JSON.parse(xhr.responseText); }
            catch (e) { setStatus("Parse error"); btn.disabled = !BRIDGE_URL; return; }
            input.value = "";
            renderUI(data);
            setStatus(data.running ? "Password updated, server restarted" : "Password updated");
        } else {
            setStatus("Set password failed (" + xhr.status + ")");
            btn.disabled = !BRIDGE_URL;
        }
    };
    xhr.ontimeout = function() { setStatus("Set password timed out"); btn.disabled = !BRIDGE_URL; };
    xhr.onerror   = function() { setStatus("Set password error"); btn.disabled = !BRIDGE_URL; };
    xhr.send();
}

function setStatus(msg) {
    document.getElementById("status-line").innerHTML = msg;
}

document.addEventListener("DOMContentLoaded", function() {
    document.getElementById("toggle-btn").addEventListener("click", toggleServer);
    document.getElementById("keepawake-check").addEventListener("change", toggleKeepawake);
    document.getElementById("update-btn").addEventListener("click", runUpdate);
    document.getElementById("set-password-btn").addEventListener("click", setPassword);

    // Native <label for="..."> click-through to the checkbox isn't
    // reliable in this webview (confirmed the checkbox itself was too
    // small a target to hit reliably even with the label wrapping it),
    // so the whole row is wired to toggle it directly too — guarded so
    // a tap that already landed on the checkbox itself doesn't fire this
    // a second time and double-toggle.
    document.querySelector(".keepawake-row").addEventListener("click", function(e) {
        if (e.target && e.target.id === "keepawake-check") { return; }
        var check = document.getElementById("keepawake-check");
        if (check.disabled) { return; }
        check.checked = !check.checked;
        toggleKeepawake();
    });

    fetchStatus();
});
