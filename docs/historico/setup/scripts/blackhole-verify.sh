> ARCHIVADO — referencia histórica, NO es estado vivo del proyecto.

#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
artifact_dir="$repo_root/docs/setup/artifacts"
artifact_file="$artifact_dir/blackhole-system-profiler.txt"

mkdir -p "$artifact_dir"
system_profiler SPAudioDataType > "$artifact_file"

echo "Evidencia guardada en:"
echo "  $artifact_file"
echo

if rg -q "BlackHole 16ch" "$artifact_file"; then
  echo "BlackHole 16ch encontrado en CoreAudio:"
  rg -n -A6 -B2 "BlackHole 16ch|Input Channels: 16" "$artifact_file"
else
  echo "BlackHole 16ch todavia no aparece en CoreAudio."
  echo "Prueba este paso manual y vuelve a ejecutar este script:"
  echo "  sudo killall coreaudiod"
  exit 2
fi
