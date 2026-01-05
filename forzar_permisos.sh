#!/bin/bash

# Script para forzar que macOS reconozca la app y aparezca en Configuración

echo "🔧 Forzando reconocimiento de Lopez Code en macOS..."
echo ""

APP_PATH="/Applications/Lopez Code.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: La app no está instalada en /Applications"
    echo "   Por favor, instala la app primero desde el DMG"
    exit 1
fi

echo "✅ App encontrada en: $APP_PATH"
echo ""

# Paso 1: Ejecutar la app brevemente para que macOS la registre
echo "📱 Paso 1: Ejecutando la app para registro en macOS..."
open "$APP_PATH" &
APP_PID=$!

# Esperar 3 segundos para que la app se inicie
sleep 3

# Cerrar la app
echo "   Cerrando la app..."
kill $APP_PID 2>/dev/null || pkill -f "Lopez Code" 2>/dev/null

echo "✅ App ejecutada y registrada"
echo ""

# Paso 2: Abrir Configuración del Sistema directamente en la sección de permisos
echo "📱 Paso 2: Abriendo Configuración del Sistema..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

echo ""
echo "✅ Configuración abierta"
echo ""
echo "📋 Instrucciones:"
echo "   1. Busca 'Lopez Code' en la lista de apps"
echo "   2. Si no aparece, espera unos segundos y recarga la página (haz scroll)"
echo "   3. Si aún no aparece, ejecuta la app manualmente desde Aplicaciones"
echo "   4. Luego vuelve a Configuración y debería aparecer"
echo ""
echo "💡 Nota: A veces macOS tarda unos segundos en mostrar apps nuevas"
echo "   Si no aparece, cierra y vuelve a abrir Configuración del Sistema"

