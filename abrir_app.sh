#!/bin/bash

echo "🚀 Abriendo Lopez Code AI..."

# Buscar la app en diferentes ubicaciones posibles
APP_PATHS=(
    "/Applications/Lopez Code AI.app"
    "$HOME/Applications/Lopez Code AI.app"
    "build/macos/Build/Products/Release/Lopez Code AI.app"
    "build/macos/Build/Products/Debug/Lopez Code AI.app"
)

APP_FOUND=false

for APP_PATH in "${APP_PATHS[@]}"; do
    if [ -d "$APP_PATH" ]; then
        echo "✅ App encontrada en: $APP_PATH"
        echo "📱 Abriendo app..."
        open "$APP_PATH"
        APP_FOUND=true
        break
    fi
done

if [ "$APP_FOUND" = false ]; then
    echo "❌ App no encontrada. Compilando primero..."
    
    # Compilar la app
    echo "🔨 Compilando app para macOS..."
    flutter build macos --release
    
    if [ $? -eq 0 ]; then
        echo "✅ Compilación exitosa!"
        APP_PATH="build/macos/Build/Products/Release/Lopez Code AI.app"
        
        if [ -d "$APP_PATH" ]; then
            echo "📱 Abriendo app compilada..."
            open "$APP_PATH"
        else
            echo "❌ Error: App compilada no encontrada en $APP_PATH"
            exit 1
        fi
    else
        echo "❌ Error al compilar la app"
        exit 1
    fi
fi

echo "✅ ¡App abierta! Deberías ver la pantalla principal con el chat."
