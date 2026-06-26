> ARCHIVADO — referencia histórica, NO es estado vivo del proyecto.

#!/usr/bin/env bash

set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  cat <<'EOF'
Homebrew no esta disponible en este Mac.

ACCION-USUARIO
1. Instala Homebrew:
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
2. O usa el instalador oficial de BlackHole:
   https://existential.audio/blackhole/
3. Repo oficial:
   https://github.com/ExistentialAudio/BlackHole
EOF
  exit 1
fi

echo "Reinstalando BlackHole 16ch por Homebrew..."
echo "macOS puede pedir la contrasena de administrador para instalar el driver."
brew reinstall --cask blackhole-16ch

cat <<'EOF'

Instalacion lanzada.

Siguiente paso:
  bash docs/setup/scripts/blackhole-verify.sh

Si BlackHole no aparece todavia:
  sudo killall coreaudiod
  bash docs/setup/scripts/blackhole-verify.sh
EOF
