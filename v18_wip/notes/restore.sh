#!/bin/bash
# One-shot restore after a sandbox reset. Usage: restore.sh <wip.tgz>
WIP="$1"; F=/data/.agent-service/files
(sudo dnf install -y xorg-x11-server-Xvfb mesa-vulkan-drivers vulkan-loader libXcursor libXinerama libXrandr libXi libXrender libXext mesa-libGL mesa-libEGL > /tmp/dnf.log 2>&1; echo $? > /tmp/dnf.done) &
cd /data && mkdir -p r16 && cd r16 && unzip -q -o $F/017d9ee7-9ee0-4ee0-aba1-38880d922c0c/RoninsEdge_v16_play.zip -d play && unzip -q -o $F/a1de80c7-d8c4-49fb-8212-5019ba87d817/RoninsEdge_v16_dev_tools.zip -d dev
cd /data && cp -n r16/dev/tools/make_kanji_font.py r16/dev/tools/make_smoke_sfx.py ronins_edge/tools/ 2>/dev/null; cp -a r16/play/RoninsEdge/. ronins_edge/game/
cd /data/ronins_edge && tar xzf "$WIP" game && tar xzf "$WIP" -C / data/v17 2>/dev/null
printf '[rendering]\ntextures/default_filters/anisotropic_filtering_level=0\n' > /data/ronins_edge/game/override.cfg
cat > /data/renv.sh <<'EOR'
#!/bin/bash
export DISPLAY=:99
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
pgrep -x Xvfb >/dev/null || { Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2; }
cd /data/ronins_edge/game
exec /data/godot_install/Godot_v4.3-stable_linux.x86_64 --path . "$@"
EOR
chmod +x /data/renv.sh
cat > /data/v17/backup.sh <<'EOB'
#!/bin/bash
cd /data/ronins_edge && tar czf /data/v17/wip.tgz --exclude=game/.godot --exclude=game/assets --exclude=game/override.cfg game /data/v17/PLAN.md /data/v17/patch /data/v17/whatsnew17.md /data/v17/restore.sh 2>/dev/null; ls -la /data/v17/wip.tgz
EOB
chmod +x /data/v17/backup.sh
cd /data/ronins_edge/game && timeout 900 /data/godot_install/Godot_v4.3-stable_linux.x86_64 --headless --path . --import > /tmp/imp.log 2>&1; echo $? > /tmp/imp.done
wait
echo RESTORE_DONE
