#!/bin/bash
# usage: backup.sh NAME  -> /data/v17/NAME.tgz (code + notes; no assets)
N=${1:-wip}
cd /data/ronins_edge && tar czf /data/v17/$N.tgz --exclude=game/.godot --exclude=game/assets --exclude=game/override.cfg --exclude=game/.git game tools/pack.py /data/v17/*.md /data/v17/*.sh /data/v17/patch 2>/dev/null; ls -la /data/v17/$N.tgz
