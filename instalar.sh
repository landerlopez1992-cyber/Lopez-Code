#!/bin/bash

# Script para compilar e instalar Lopez Code en macOS

echo "🚀 Compilando Lopez Code para macOS..."
echo ""

# Compilar para release
flutter build macos --release

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Compilación exitosa!"
    echo ""
    
    # Ruta de la app compilada
    APP_PATH="build/macos/Build/Products/Release/Lopez Code.app"
    
    if [ -d "$APP_PATH" ]; then
        echo "📦 App compilada en: $APP_PATH"
        echo ""
        echo "¿Deseas instalar la app en Aplicaciones? (s/n)"
        read -r response
        
        if [[ "$response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
            echo ""
            echo "📥 Instalando en /Applications..."
            cp -R "$APP_PATH" "/Applications/Lopez Code.app"
            
            if [ $? -eq 0 ]; then
                echo "✅ ¡App instalada exitosamente!"
                echo ""
                echo "🎉 Ahora puedes:"
                echo "   1. Abrir la app desde Aplicaciones"
                echo "   2. Otorgar permisos cuando macOS lo solicite"
                echo "   3. O ve a: Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas"
                echo ""
                echo "¿Deseas abrir la app ahora? (s/n)"
                read -r open_response
                
                if [[ "$open_response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
                    open "/Applications/Lopez Code.app"
                fi
            else
                echo "❌ Error al instalar la app"
                exit 1
            fi
        else
            echo ""
            echo "ℹ️  App compilada pero no instalada."
            echo "   Puedes instalarla manualmente arrastrando:"
            echo "   $APP_PATH"
            echo "   a tu carpeta Aplicaciones"
        fi
    else
        echo "❌ No se encontró la app compilada en: $APP_PATH"
        exit 1
    fi
else
    echo ""
    echo "❌ Error al compilar la app"
    exit 1
fi

