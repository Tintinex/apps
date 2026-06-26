"""
Applet: CTA Wilson Trains
Summary: Red & Purple arrivals
Description: Live CTA Train Tracker arrival times for the Red and Purple lines at the Wilson stop (Chicago).
Author: tintinex
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

# CTA Train Tracker "Arrivals" endpoint.
# Docs: https://www.transitchicago.com/developers/traintracker/
CTA_URL = "https://lapi.transitchicago.com/api/1.0/ttarrivals.aspx"

# Wilson station (Red + Purple lines). "mapid" returns every platform/stop at the station.
WILSON_MAPID = "41200"

# CTA reports all times in Chicago local time.
TIMEZONE = "America/Chicago"

# CTA timestamp format, e.g. "20240915 14:30:00".
CTA_TIME_FORMAT = "20060102 15:04:05"

# How long to cache the upstream response (seconds). Keeps us well under any rate limit
# while still feeling live on a 15s display rotation.
CACHE_TTL_SECONDS = 20

# Route code -> (badge letter, badge color, text color).
LINE_STYLES = {
    "Red": ("R", "#c60c30", "#ffffff"),
    "P": ("P", "#522398", "#ffffff"),
    "Brn": ("B", "#62361b", "#ffffff"),
}
DEFAULT_LINE_STYLE = ("?", "#666666", "#ffffff")

MAX_ROWS = 3

def main(config):
    api_key = config.str("api_key", "").strip()
    if api_key == "":
        return _message("Set CTA API key", "#ffcc00")

    lines = config.str("lines", "both")

    resp = http.get(
        CTA_URL,
        params = {
            "key": api_key,
            "mapid": WILSON_MAPID,
            "max": "10",
            "outputType": "JSON",
        },
        ttl_seconds = CACHE_TTL_SECONDS,
    )

    if resp.status_code != 200:
        return _message("CTA HTTP %d" % resp.status_code, "#ff5555")

    ctatt = resp.json().get("ctatt", {})

    # errCd "0" means success; anything else is an upstream error (e.g. bad key).
    if ctatt.get("errCd", "0") != "0":
        return _message("CTA error", "#ff5555")

    etas = ctatt.get("eta", [])
    etas = _filter_lines(etas, lines)
    etas = sorted(etas, key = lambda e: e.get("arrT", ""))

    now = time.now().in_location(TIMEZONE)
    rows = []
    for eta in etas[:MAX_ROWS]:
        rows.append(_arrival_row(eta, now))

    if len(rows) == 0:
        return _with_header(render.Box(
            child = render.Text("No trains", font = "tom-thumb", color = "#888888"),
        ))

    return _with_header(render.Column(
        expanded = True,
        main_align = "space_evenly",
        children = rows,
    ))

def _filter_lines(etas, lines):
    if lines == "red":
        wanted = ["Red"]
    elif lines == "purple":
        wanted = ["P"]
    else:
        wanted = ["Red", "P"]
    return [e for e in etas if e.get("rt", "") in wanted]

def _arrival_row(eta, now):
    letter, badge_color, badge_text = LINE_STYLES.get(eta.get("rt", ""), DEFAULT_LINE_STYLE)

    badge = render.Box(
        width = 7,
        height = 7,
        color = badge_color,
        child = render.Text(content = letter, font = "tom-thumb", color = badge_text),
    )

    dest = _short_dest(eta.get("destNm", "?"))

    return render.Row(
        expanded = True,
        main_align = "space_between",
        cross_align = "center",
        children = [
            render.Row(
                cross_align = "center",
                children = [
                    badge,
                    render.Box(width = 2, height = 1),
                    render.Text(content = dest, font = "tom-thumb", color = "#ffffff"),
                ],
            ),
            render.Text(
                content = _minutes_label(eta, now),
                font = "tom-thumb",
                color = "#ffcc00",
            ),
        ],
    )

def _minutes_label(eta, now):
    if eta.get("isDly", "0") == "1":
        return "Dly"
    if eta.get("isApp", "0") == "1":
        return "Due"

    arr = time.parse_time(eta.get("arrT", ""), format = CTA_TIME_FORMAT, location = TIMEZONE)
    mins = int((arr - now).minutes)
    if mins <= 0:
        return "Due"
    return "%dm" % mins

def _short_dest(name):
    # Trim the longer CTA destination names so a route badge + destination + countdown
    # all fit on a single 64px row.
    overrides = {
        "95th/Dan Ryan": "95th",
        "Howard": "Howard",
        "Linden": "Linden",
        "Loop": "Loop",
    }
    if name in overrides:
        return overrides[name]
    if len(name) > 9:
        return name[:9]
    return name

def _with_header(body):
    header = render.Box(
        height = 7,
        color = "#1a1a1a",
        child = render.Row(
            expanded = True,
            main_align = "center",
            cross_align = "center",
            children = [
                render.Box(width = 3, height = 3, color = "#c60c30"),
                render.Box(width = 2, height = 1),
                render.Box(width = 3, height = 3, color = "#522398"),
                render.Box(width = 2, height = 1),
                render.Text(content = "WILSON", font = "tom-thumb", color = "#dddddd"),
            ],
        ),
    )
    return render.Root(
        child = render.Column(
            children = [
                header,
                render.Box(
                    height = 25,
                    padding = 1,
                    child = body,
                ),
            ],
        ),
    )

def _message(text, color):
    return _with_header(render.Box(
        child = render.WrappedText(content = text, font = "tom-thumb", color = color, align = "center"),
    ))

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "api_key",
                name = "CTA API Key",
                desc = "Your free CTA Train Tracker API key (transitchicago.com/developers).",
                icon = "key",
            ),
            schema.Dropdown(
                id = "lines",
                name = "Lines",
                desc = "Which lines to show at Wilson.",
                icon = "train",
                default = "both",
                options = [
                    schema.Option(display = "Red & Purple", value = "both"),
                    schema.Option(display = "Red only", value = "red"),
                    schema.Option(display = "Purple only", value = "purple"),
                ],
            ),
        ],
    )
