#!/bin/bash

# Script para actualizar el icono de la app en macOS
# Esto limpia la caché del icono y reconstruye la app

echo "🔄 Actualizando icono de la app..."

# 1. Limpiar caché de iconos de macOS
echo "🧹 Limpiando caché de iconos..."
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

# 2. Limpiar build anterior
echo "🧹 Limpiando build anterior..."
cd "$(dirname "$0")"
flutter clean

# 3. Reconstruir la app
echo "🔨 Reconstruyendo la app..."
flutter build macos

echo ""
echo "✅ ¡Icono actualizado!"
echo "💡 Si el icono no se actualiza en el dock, cierra y vuelve a abrir la app."
echo "💡 También puedes hacer clic derecho en el icono del dock > Opciones > Quitar del dock,"
echo "   y luego arrastrar la app de nuevo al dock desde Aplicaciones."
