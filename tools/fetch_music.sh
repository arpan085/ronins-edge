#!/bin/bash
# CC0 music from OpenGameArt used by tools/build_audio.py (saved as /tmp/oga/<slug>.<ext>)
mkdir -p /tmp/oga && cd /tmp/oga
B=https://opengameart.org/sites/default/files
get() { [ -s "$1" ] || curl -s -L --max-time 120 -o "$1" "$2"; }
get the-last-samurai.mp3 "$B/The_fallen_samurai.mp3"
get koto-booth.ogg "$B/kotobooth.ogg"
get lapsy-koto.ogg "$B/lapsykoto_0.ogg"
get sugimai.ogg "$B/sujijami.ogg"
get hot-springs-town.ogg "$B/hot_spring_town_1.ogg"
get orient-peace-valley.ogg "$B/orien1_0.ogg"
get asianoriental2.ogg "$B/asianoriental2_0.ogg"
get oriental-somber.ogg "$B/orientalsomber_0.ogg"
get orient-5.ogg "$B/orien5_0.ogg"
get ninja-theme.ogg "$B/ninja%20theme_0.ogg"
get tyhosiasian.ogg "$B/tyhosiasian_0.ogg"
get bosskoto.mp3 "$B/boss_koto.mp3"
get prepare-your-swords.ogg "$B/prepare_your_swords_0.ogg"
get great-boss.ogg "$B/Great%20Boss_0.ogg"
ls -la /tmp/oga
