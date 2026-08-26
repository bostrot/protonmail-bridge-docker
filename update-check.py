#!/usr/bin/env python3
"""Pin this repository to the latest upstream Proton Bridge release.

Rewrites VERSION and deb/PACKAGE when a newer release is available. Git
operations are left to the caller so that this script stays side effect free
apart from the two files, which makes it safe to run locally.

Under GitHub Actions the results are also written to $GITHUB_OUTPUT as
`version`, `deb` and `changed`.
"""

import json
import os
import sys
import urllib.error
import urllib.request

RELEASE_API = "https://api.github.com/repos/ProtonMail/proton-bridge/releases/latest"
VERSION_FILE = "VERSION"
PACKAGE_FILE = "deb/PACKAGE"


def fetch_latest_release():
    request = urllib.request.Request(
        RELEASE_API,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "protonmail-bridge-docker-update-check",
        },
    )
    # Authenticating lifts the very low anonymous rate limit on shared runners.
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")

    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def find_deb_url(release):
    debs = [asset for asset in release["assets"] if asset["name"].endswith(".deb")]
    if not debs:
        raise LookupError(f"release {release['tag_name']} has no .deb asset")
    # The deb image is amd64 only, so prefer that asset if the release ever
    # starts shipping more than one architecture.
    for asset in debs:
        if "amd64" in asset["name"]:
            return asset["browser_download_url"]
    return debs[0]["browser_download_url"]


def read(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except FileNotFoundError:
        return ""


def write(path, value):
    # No trailing newline, to match how these files have always been written.
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(value)


def emit_outputs(**outputs):
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        return
    with open(path, "a", encoding="utf-8") as handle:
        for key, value in outputs.items():
            handle.write(f"{key}={value}\n")


def main():
    try:
        release = fetch_latest_release()
    except (urllib.error.URLError, json.JSONDecodeError, OSError) as error:
        print(f"Could not query the Proton Bridge releases API: {error}", file=sys.stderr)
        return 1

    try:
        version = release["tag_name"]
        deb = find_deb_url(release)
    except (KeyError, LookupError) as error:
        print(f"Unexpected release payload: {error}", file=sys.stderr)
        return 1

    current = read(VERSION_FILE)
    changed = version != current or read(PACKAGE_FILE) != deb

    print(f"Latest Proton Bridge release: {version}")
    print(f"Currently pinned:             {current or '(nothing)'}")

    if changed:
        write(VERSION_FILE, version)
        write(PACKAGE_FILE, deb)
        print(f"Updated {VERSION_FILE} and {PACKAGE_FILE} to {version}.")
    else:
        print("Already up to date, nothing to do.")

    emit_outputs(version=version, deb=deb, changed="true" if changed else "false")
    return 0


if __name__ == "__main__":
    sys.exit(main())
