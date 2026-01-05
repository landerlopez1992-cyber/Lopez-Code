#!/bin/bash

# Script para crear un instalador .dmg profesional para Lopez Code

set -e  # Salir si hay errores

echo "🚀 Creando instalador profesional para Lopez Code..."
echo ""

# Colores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar que estamos en el directorio correcto
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: Debes ejecutar este script desde la raíz del proyecto"
    exit 1
fi

# Paso 1: Compilar para release
echo -e "${BLUE}📦 Paso 1: Compilando app para release...${NC}"
flutter clean
flutter build macos --release

# Buscar la app compilada en diferentes ubicaciones posibles
APP_PATH=""
if [ -d "build/macos/Build/Products/Release/Lopez Code.app" ]; then
    APP_PATH="build/macos/Build/Products/Release/Lopez Code.app"
elif [ -d "android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app" ]; then
    APP_PATH="android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app"
else
    # Buscar en cualquier ubicación
    APP_PATH=$(find . -name "Lopez Code.app" -type d -path "*/Release/*" 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: No se encontró la app compilada"
    echo "   Buscando en: build/macos/Build/Products/Release/"
    echo "   Buscando en: android/app/build/outputs/apk/macos/Build/Products/Release/"
    exit 1
fi

echo -e "${GREEN}✅ Compilación exitosa${NC}"
echo "   App encontrada en: $APP_PATH"
echo ""

# Paso 2: Crear directorio temporal para el DMG
echo -e "${BLUE}📦 Paso 2: Preparando instalador...${NC}"
DMG_DIR="dmg_build"
DMG_NAME="Lopez_Code_Installer"
DMG_PATH="${DMG_NAME}.dmg"

# Limpiar si existe
rm -rf "$DMG_DIR"
rm -f "$DMG_PATH"

# Crear directorio temporal
mkdir -p "$DMG_DIR"

# Copiar la app
cp -R "$APP_PATH" "$DMG_DIR/"

# Crear un enlace simbólico a Aplicaciones (para facilitar la instalación)
ln -s /Applications "$DMG_DIR/Applications"

echo -e "${GREEN}✅ Preparación completada${NC}"
echo ""

# Paso 3: Crear el DMG
echo -e "${BLUE}📦 Paso 3: Creando archivo .dmg profesional...${NC}"

# Usar hdiutil para crear un DMG comprimido (formato UDZO = comprimido)
# Esto crea un instalador profesional similar a Cursor
hdiutil create -volname "Lopez Code" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ DMG creado exitosamente: ${DMG_PATH}${NC}"
    echo ""
    
    # Limpiar directorio temporal
    rm -rf "$DMG_DIR"
    
    # Obtener tamaño del archivo
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    
    echo -e "${GREEN}🎉 ¡Instalador creado exitosamente!${NC}"
    echo ""
    echo "📦 Archivo: $DMG_PATH"
    echo "📊 Tamaño: $DMG_SIZE"
    echo ""
    echo "📋 Instrucciones para instalar:"
    echo "   1. Haz doble clic en: $DMG_PATH"
    echo "   2. Se abrirá una ventana con la app"
    echo "   3. Arrastra 'Lopez Code.app' a la carpeta 'Applications'"
    echo "   4. Abre la app desde Aplicaciones"
    echo "   5. Otorga permisos cuando macOS lo solicite"
    echo ""
    
    # Preguntar si quiere abrir el DMG
    echo "¿Deseas abrir el instalador ahora? (s/n)"
    read -r response
    if [[ "$response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
        open "$DMG_PATH"
    fi
else
    echo "❌ Error al crear el DMG"
    rm -rf "$DMG_DIR"
    exit 1
fi

