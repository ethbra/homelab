#!/usr/bin/env python3
"""List Crafty's Minecraft servers and show which one is running.

Nothing in this repo hard-codes a server: whichever server Crafty is running
is the live one (they all share 127.0.0.1:25565, so only one runs at a time).

  scripts/crafty-servers.py           table of servers, running one marked
  scripts/crafty-servers.py --path    host path of the running server(s)

  tail -f "$(scripts/crafty-servers.py --path)/logs/latest.log"

Reads Crafty's database read-only and the container's processes (as the
container's `crafty` user, the only one that may read their working dirs).
"""
import argparse
import sqlite3
import subprocess
import sys

DB = "/srv/appdata/crafty/config/db/crafty.sqlite"
CONTAINER = "crafty-container"
HOST_SERVERS = "/srv/appdata/crafty/servers"
CONTAINER_SERVERS = "/crafty/servers"

# For each java process: "<server dir> <java binary>".
PROBE = r"""
for p in /proc/[0-9]*; do
  grep -qa java "$p/cmdline" 2>/dev/null || continue
  echo "$(readlink "$p/cwd") $(readlink "$p/exe")"
done
"""


def running():
    out = subprocess.run(
        ["docker", "exec", "-u", "crafty", CONTAINER, "sh", "-c", PROBE],
        capture_output=True, text=True, check=True,
    ).stdout
    found = {}
    for line in out.splitlines():
        cwd, _, exe = line.partition(" ")
        if cwd.startswith(CONTAINER_SERVERS + "/") and exe.endswith("/java"):
            found[cwd.rsplit("/", 1)[1]] = exe
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--path", action="store_true",
                    help="print the host path of each running server")
    args = ap.parse_args()

    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    servers = db.execute(
        "select server_id, server_name, type, auto_start, execution_command"
        " from servers order by created").fetchall()
    live = running()

    if args.path:
        if not live:
            sys.exit("no Crafty server is running")
        for uuid in live:
            print(f"{HOST_SERVERS}/{uuid}")
        return

    for uuid, name, kind, auto, cmd in servers:
        mark = "RUNNING" if uuid in live else "       "
        java = live.get(uuid, "")
        print(f"{mark}  {name:<16} {uuid}  {kind:<15} auto-start={'yes' if auto else 'no '}"
              f"  {java or cmd[:40]}")


if __name__ == "__main__":
    main()
