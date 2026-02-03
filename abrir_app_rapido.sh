#!/bin/bash

echo "🚀 Abriendo Lopez Code AI (método rápido)..."

# Método 1: Buscar en Aplicaciones
if [ -d "/Applications/Lopez Code AI.app" ]; then
    echo "✅ App encontrada en Aplicaciones"
    open "/Applications/Lopez Code AI.app"
    exit 0
fi

# Método 2: Buscar en el escritorio del usuario
if [ -d "$HOME/Applications/Lopez Code AI.app" ]; then
    echo "✅ App encontrada en ~/Applications"
    open "$HOME/Applications/Lopez Code AI.app"
    exit 0
fi

# Método 3: Buscar en el proyecto (si ya está compilada)
if [ -d "build/macos/Build/Products/Release/Lopez Code AI.app" ]; then
    echo "✅ App encontrada en build (Release)"
    open "build/macos/Build/Products/Release/Lopez Code AI.app"
    exit 0
fi

if [ -d "build/macos/Build/Products/Debug/Lopez Code AI.app" ]; then
    echo "✅ App encontrada en build (Debug)"
    open "build/macos/Build/Products/Debug/Lopez Code AI.app"
    exit 0
fi

# Si no se encuentra, ejecutar desde Flutter directamente (más rápido que compilar)
echo "📱 Ejecutando app en modo debug (sin compilar)..."
cd "$(dirname "$0")"
flutter run -d macos
