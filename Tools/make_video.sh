#!/bin/bash
# Monta o vídeo de demonstração: quadros da UI real (--video-frames) + narração em inglês (say) + legendas em 5 idiomas.
# Uso: Tools/make_video.sh <pasta-de-trabalho> [pasta-de-saída]
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=${1:?pasta de trabalho}; OUT=${2:-server/public_html/assets/video}
FRAMES=$WORK/frames; mkdir -p "$WORK/audio" "$WORK/scenes" "$OUT"
[ -f "$FRAMES/10_end.png" ] || ./SnapLens.app/Contents/MacOS/SnapLens --video-frames "$FRAMES" en
VOICE=$(python3 -c "import json;print(json.load(open('Tools/narration.json'))['voice'])")
RATE=$(python3 -c "import json;print(json.load(open('Tools/narration.json'))['rate'])")
N=$(python3 -c "import json;print(len(json.load(open('Tools/narration.json'))['scenes']))")
W=1920; H=1200; FPS=30
: > "$WORK/concat.txt"; : > "$WORK/times.txt"
T=0
for i in $(seq 0 $((N-1))); do
  FRAME=$(python3 -c "import json;print(json.load(open('Tools/narration.json'))['scenes'][$i]['frame'])")
  PAD=$(python3 -c "import json;print(json.load(open('Tools/narration.json'))['scenes'][$i]['pad'])")
  python3 -c "import json;print(json.load(open('Tools/narration.json'))['scenes'][$i]['en'])" > "$WORK/audio/$i.txt"
  if [ -f .secrets/elevenlabs ]; then
    # Narração com ElevenLabs (voz natural). Chave fora do git.
    AUD="$WORK/audio/$i.mp3"
    [ -s "$AUD" ] || python3 - "$WORK/audio/$i.txt" "$AUD" <<'PYEOF'
import json, sys, urllib.request
text = open(sys.argv[1]).read().strip()
key = open('.secrets/elevenlabs').read().strip()
voice = 'EXAVITQu4vr4xnSDxMaL'  # Sarah — mature, reassuring, confident
req = urllib.request.Request(f'https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128',
    data=json.dumps({'text': text, 'model_id': 'eleven_multilingual_v2',
                     'voice_settings': {'stability': 0.45, 'similarity_boost': 0.8, 'style': 0.15, 'use_speaker_boost': True}}).encode(),
    headers={'xi-api-key': key, 'Content-Type': 'application/json', 'Accept': 'audio/mpeg'})
with urllib.request.urlopen(req, timeout=120) as r: open(sys.argv[2], 'wb').write(r.read())
PYEOF
  else
    AUD="$WORK/audio/$i.aiff"
    say -v "$VOICE" -r "$RATE" -f "$WORK/audio/$i.txt" -o "$AUD"
  fi
  ADUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$AUD")
  DUR=$(python3 -c "print(round($ADUR + $PAD, 2))")
  # Ken Burns suave: zoom até 1.06 ao longo da cena
  ffmpeg -v error -y -loop 1 -i "$FRAMES/$FRAME.png" -i "$AUD" \
    -filter_complex "[0:v]scale=$((W*2)):$((H*2)):flags=lanczos,zoompan=z='min(1+0.06*on/($FPS*$DUR),1.06)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${W}x${H}:fps=$FPS,format=yuv420p[v];[1:a]apad,aformat=sample_rates=48000:channel_layouts=stereo[a]" \
    -map "[v]" -map "[a]" -t "$DUR" -c:v libx264 -preset medium -crf 20 -c:a aac -b:a 160k -shortest "$WORK/scenes/$i.mp4"
  echo "file '$WORK/scenes/$i.mp4'" >> "$WORK/concat.txt"
  echo "$i $T $DUR" >> "$WORK/times.txt"
  T=$(python3 -c "print(round($T + $DUR, 2))")
done
ffmpeg -v error -y -f concat -safe 0 -i "$WORK/concat.txt" -c copy "$WORK/video-nosubs.mp4"

# Legendas SRT/VTT por idioma, sincronizadas com as cenas
python3 - "$WORK" "$OUT" <<'PY'
import json, sys
work, out = sys.argv[1], sys.argv[2]
sc = json.load(open('Tools/narration.json'))['scenes']
times = [l.split() for l in open(f'{work}/times.txt')]
def ts(t, sep): h=int(t//3600); m=int(t%3600//60); s=t%60; return f"{h:02d}:{m:02d}:{s:06.3f}".replace('.', sep)
for lang, code in [('en','en'),('pt','pt-BR'),('es','es'),('it','it'),('zh','zh-Hans')]:
    srt, vtt = [], ["WEBVTT", ""]
    for i, (idx, start, dur) in enumerate(times):
        a = float(start) + 0.15; b = float(start) + float(dur) - 0.2
        srt += [str(i+1), f"{ts(a,',')} --> {ts(b,',')}", sc[i][lang], ""]
        vtt += [f"{ts(a,'.')} --> {ts(b,'.')}", sc[i][lang], ""]
    open(f'{work}/{code}.srt','w').write("\n".join(srt))
    open(f'{out}/snaplens-demo.{code}.vtt','w').write("\n".join(vtt))
print("legendas ok")
PY
# MP4 final com faixas de legenda embutidas (mov_text) + transcrições
ffmpeg -v error -y -i "$WORK/video-nosubs.mp4" -i "$WORK/en.srt" -i "$WORK/pt-BR.srt" -i "$WORK/es.srt" -i "$WORK/it.srt" -i "$WORK/zh-Hans.srt" \
  -map 0 -map 1 -map 2 -map 3 -map 4 -map 5 -c copy -c:s mov_text \
  -metadata:s:s:0 language=eng -metadata:s:s:1 language=por -metadata:s:s:2 language=spa -metadata:s:s:3 language=ita -metadata:s:s:4 language=zho \
  -metadata title="SnapLens — demo" -movflags +faststart "$OUT/snaplens-demo.mp4"
ffmpeg -v error -y -i "$FRAMES/05_overlay_annotated.png" -vf "scale=$W:$H" -q:v 3 "$OUT/snaplens-demo-poster.jpg"
cp "$WORK"/*.srt "$OUT/" 2>/dev/null || true
echo "vídeo: $OUT/snaplens-demo.mp4 ($(du -h "$OUT/snaplens-demo.mp4" | cut -f1), $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/snaplens-demo.mp4")s)"
