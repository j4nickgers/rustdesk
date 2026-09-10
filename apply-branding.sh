#!/usr/bin/env bash
set -e

# ==============================================================================
# Script di personalizzazione e White-Label per Telesolver Client (RustDesk)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRANDING_DIR="${SCRIPT_DIR}/branding"

if [ ! -d "$BRANDING_DIR" ]; then
    if [ -d "./branding" ]; then
        BRANDING_DIR="./branding"
    else
        echo "ERRORE: Cartella branding non trovata in $BRANDING_DIR o ./branding"
        exit 1
    fi
fi

echo "=== APPLICAZIONE BRANDING TELESOLVER ==="
echo "Cartella asset: $BRANDING_DIR"

# 1. Sostituzione Asset Grafici (Icone e Loghi)
echo "--> Sostituzione loghi e icone..."
mkdir -p flutter/assets res flutter/windows/runner/resources

[ -f "$BRANDING_DIR/logo.svg" ] && cp -f "$BRANDING_DIR/logo.svg" flutter/assets/logo.svg
[ -f "$BRANDING_DIR/logo.png" ] && cp -f "$BRANDING_DIR/logo.png" flutter/assets/logo.png
[ -f "$BRANDING_DIR/logo.png" ] && cp -f "$BRANDING_DIR/logo.png" res/logo.png
[ -f "$BRANDING_DIR/logo.png" ] && cp -f "$BRANDING_DIR/logo.png" res/icon.png
[ -f "$BRANDING_DIR/logo-256.png" ] && cp -f "$BRANDING_DIR/logo-256.png" flutter/assets/logo-256.png
[ -f "$BRANDING_DIR/logo-128.png" ] && cp -f "$BRANDING_DIR/logo-128.png" flutter/assets/logo-128.png
[ -f "$BRANDING_DIR/logo-64.png" ] && cp -f "$BRANDING_DIR/logo-64.png" flutter/assets/logo-64.png
[ -f "$BRANDING_DIR/logo-32.png" ] && cp -f "$BRANDING_DIR/logo-32.png" flutter/assets/logo-32.png

if [ -f "$BRANDING_DIR/icon.ico" ]; then
    cp -f "$BRANDING_DIR/icon.ico" res/icon.ico
    cp -f "$BRANDING_DIR/icon.ico" flutter/windows/runner/resources/app_icon.ico
fi

# 2. Rebranding Metadati Eseguibile Windows (Runner.rc)
if [ -f "flutter/windows/runner/Runner.rc" ]; then
    echo "--> Aggiornamento metadati binario in flutter/windows/runner/Runner.rc..."
    sed -i 's/VALUE "CompanyName",.*/VALUE "CompanyName", "Telesolver\\0"/g' flutter/windows/runner/Runner.rc || true
    sed -i 's/VALUE "FileDescription",.*/VALUE "FileDescription", "Telesolver Assistenza Remota\\0"/g' flutter/windows/runner/Runner.rc || true
    sed -i 's/VALUE "InternalName",.*/VALUE "InternalName", "Telesolver\\0"/g' flutter/windows/runner/Runner.rc || true
    sed -i 's/VALUE "LegalCopyright",.*/VALUE "LegalCopyright", "Copyright (C) 2026 Telesolver. Tutti i diritti riservati.\\0"/g' flutter/windows/runner/Runner.rc || true
    sed -i 's/VALUE "OriginalFilename",.*/VALUE "OriginalFilename", "Telesolver-Support.exe\\0"/g' flutter/windows/runner/Runner.rc || true
    sed -i 's/VALUE "ProductName",.*/VALUE "ProductName", "Telesolver QuickSupport\\0"/g' flutter/windows/runner/Runner.rc || true
fi

# 3. Aggiornamento Titolo Finestra Principale Windows (main.cpp)
if [ -f "flutter/windows/runner/main.cpp" ]; then
    echo "--> Aggiornamento titolo finestra in flutter/windows/runner/main.cpp..."
    sed -i 's/L"RustDesk"/L"Telesolver - Assistenza Remota"/g' flutter/windows/runner/main.cpp || true
fi

# 4. Aggiornamento Traduzioni UI (Sostituzione 'RustDesk' con 'Telesolver')
if [ -d "flutter/assets/translations" ]; then
    echo "--> Aggiornamento stringhe di traduzione UI in flutter/assets/translations/..."
    find flutter/assets/translations -name "*.json" -type f -exec sed -i 's/RustDesk/Telesolver/g' {} + || true
fi

# 5. Configurazione Server Predefinita Hardcoded
# Relay Host: 93.186.255.165:21116
# Public Key: 4R2S3XpjLllf+dP47e0y9HBJwyyeQ3kxcwfzJNWQOu4=
echo "--> Verifica e iniezione parametri server hardcoded..."

# Iniezione in libs/hbb_common se presente
if [ -d "libs/hbb_common" ]; then
    find libs/hbb_common -name "*.rs" -type f -exec sed -i 's/rs-ny.rustdesk.com/93.186.255.165/g' {} + || true
    find libs/hbb_common -name "*.rs" -type f -exec sed -i 's/rustdesk.com/93.186.255.165/g' {} + || true
fi

# Iniezione in src/ se presente
if [ -d "src" ]; then
    find src -name "*.rs" -type f -exec sed -i 's/rs-ny.rustdesk.com/93.186.255.165/g' {} + || true
fi

echo "=== BRANDING TELESOLVER APPLICATO CON SUCCESSO ==="
