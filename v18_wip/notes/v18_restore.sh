#!/bin/bash
# Restore Ronin's Edge v0.18 WIP on a fresh or old sandbox.
# usage: v18_restore.sh <wip.tgz> [char_tex2.tgz]
# Needs session files uploaded first: v16 play 017d9ee7..., v16 dev a1de80c7...
WIP="$1"; TEX="$2"; F=/data/.agent-service/files
if ! command -v Xvfb >/dev/null; then
  sudo dnf install -y xorg-x11-server-Xvfb mesa-vulkan-drivers mesa-dri-drivers vulkan-loader libXcursor libXinerama libXrandr libXi libXrender libXext mesa-libGL mesa-libEGL > /tmp/dnf.log 2>&1
fi
if [ ! -x /data/godot_install/Godot_v4.3-stable_linux.x86_64 ]; then
  mkdir -p /data/godot_install && cd /data/godot_install && \
  curl -sSL -o g.zip https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip && unzip -q -o g.zip && rm g.zip && chmod +x Godot_v4.3-stable_linux.x86_64
fi
cd /data && [ -d ronins_edge ] && mv ronins_edge ronins_edge_prev_$(date +%s)
mkdir -p /data/r16 /data/ronins_edge/game /data/v17 && cd /data/r16 && \
unzip -q -o $F/017d9ee7-9ee0-4ee0-aba1-38880d922c0c/RoninsEdge_v16_play.zip -d play && \
unzip -q -o $F/a1de80c7-d8c4-49fb-8212-5019ba87d817/RoninsEdge_v16_dev_tools.zip -d dev
cd /data && cp -a r16/dev/. ronins_edge/ && cp -a r16/play/RoninsEdge/. ronins_edge/game/
cd /data/ronins_edge && tar xzf "$WIP" && if [ -d data/v17 ]; then cp -a data/v17/. /data/v17/; rm -rf data; fi
[ -n "$TEX" ] && (cd /data/ronins_edge/game && tar xzf "$TEX")
printf '[rendering]\ntextures/default_filters/anisotropic_filtering_level=0\n' > /data/ronins_edge/game/override.cfg
cat > /data/renv.sh <<'EOS'
#!/bin/bash
export DISPLAY=:99
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
pgrep -x Xvfb >/dev/null || { Xvfb :99 -screen 0 1280x720x24 >/tmp/xvfb.log 2>&1 & sleep 2; }
cd /data/ronins_edge/game
exec /data/godot_install/Godot_v4.3-stable_linux.x86_64 --path . "$@"
EOS
chmod +x /data/renv.sh
cat > /data/v17/backup.sh <<'EOB'
#!/bin/bash
N=${1:-wip}
cd /data/ronins_edge && tar czf /data/v17/$N.tgz --exclude=game/.godot --exclude=game/assets --exclude=game/override.cfg --exclude=game/.git game tools/pack.py /data/v17/*.md /data/v17/*.sh /data/v17/patch 2>/dev/null; ls -la /data/v17/$N.tgz
EOB
chmod +x /data/v17/backup.sh
cd /data/ronins_edge/game && timeout 1200 /data/godot_install/Godot_v4.3-stable_linux.x86_64 --headless --path . --import > /tmp/imp.log 2>&1
timeout 300 /data/godot_install/Godot_v4.3-stable_linux.x86_64 --headless --path . -s tools/check_scripts.gd 2>&1 | grep SCRIPTS_CHECKED
echo RESTORE_DONE
