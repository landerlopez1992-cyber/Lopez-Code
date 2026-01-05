#!/bin/bash

# Instalador visual para macOS - Similar a Windows pero adaptado para macOS

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "          🚀 INSTALADOR DE LOPEZ CODE PARA macOS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Paso 1: Verificar si la app ya está compilada
echo -e "${BLUE}📋 PASO 1/4: Verificando archivos...${NC}"
echo ""

APP_SOURCE=""
if [ -d "build/macos/Build/Products/Release/Lopez Code.app" ]; then
    APP_SOURCE="build/macos/Build/Products/Release/Lopez Code.app"
elif [ -d "android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app" ]; then
    APP_SOURCE="android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app"
else
    APP_SOURCE=$(find . -name "Lopez Code.app" -type d -path "*/Release/*" 2>/dev/null | head -1)
fi

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    echo -e "${YELLOW}⚠️  App no encontrada. Compilando primero...${NC}"
    echo ""
    echo -e "${BLUE}📦 Compilando app para release...${NC}"
    flutter build macos --release
    
    # Buscar de nuevo
    if [ -d "build/macos/Build/Products/Release/Lopez Code.app" ]; then
        APP_SOURCE="build/macos/Build/Products/Release/Lopez Code.app"
    elif [ -d "android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app" ]; then
        APP_SOURCE="android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app"
    else
        APP_SOURCE=$(find . -name "Lopez Code.app" -type d -path "*/Release/*" 2>/dev/null | head -1)
    fi
fi

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    echo -e "${RED}❌ Error: No se pudo encontrar la app compilada${NC}"
    exit 1
fi

APP_SIZE=$(du -sh "$APP_SOURCE" | cut -f1)
echo -e "${GREEN}✅ App encontrada: $APP_SOURCE ($APP_SIZE)${NC}"
echo ""

# Paso 2: Verificar ubicación de instalación
echo -e "${BLUE}📋 PASO 2/4: Preparando instalación...${NC}"
echo ""

INSTALL_DIR="/Applications"
INSTALL_PATH="$INSTALL_DIR/Lopez Code.app"

# Verificar permisos
if [ ! -w "$INSTALL_DIR" ]; then
    echo -e "${RED}❌ Error: No tienes permisos para escribir en $INSTALL_DIR${NC}"
    echo "   Por favor, ejecuta este script con: sudo $0"
    exit 1
fi

# Si ya está instalada, preguntar si reemplazar
if [ -d "$INSTALL_PATH" ]; then
    echo -e "${YELLOW}⚠️  Lopez Code ya está instalada en $INSTALL_PATH${NC}"
    echo ""
    echo "¿Deseas reinstalar? (s/n)"
    read -r response
    if [[ ! "$response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
        echo "Instalación cancelada."
        exit 0
    fi
    
    echo ""
    echo -e "${BLUE}🗑️  Eliminando versión anterior...${NC}"
    rm -rf "$INSTALL_PATH"
    echo -e "${GREEN}✅ Versión anterior eliminada${NC}"
    echo ""
fi

# Paso 3: Instalar
echo -e "${BLUE}📋 PASO 3/4: Instalando aplicación...${NC}"
echo ""
echo -e "   📦 Copiando archivos..."
echo -e "   📍 Origen: $APP_SOURCE"
echo -e "   📍 Destino: $INSTALL_PATH"
echo ""

# Mostrar progreso
cp -R "$APP_SOURCE" "$INSTALL_PATH"

if [ $? -eq 0 ]; then
    INSTALLED_SIZE=$(du -sh "$INSTALL_PATH" | cut -f1)
    echo -e "${GREEN}✅ Instalación completada exitosamente ($INSTALLED_SIZE)${NC}"
    echo ""
else
    echo -e "${RED}❌ Error durante la instalación${NC}"
    exit 1
fi

# Paso 4: Configurar permisos
echo -e "${BLUE}📋 PASO 4/4: Configurando permisos...${NC}"
echo ""

# Remover atributos extendidos que pueden causar problemas
echo -e "   🔧 Limpiando atributos de seguridad..."
xattr -cr "$INSTALL_PATH" 2>/dev/null || true
echo -e "${GREEN}✅ Permisos configurados${NC}"
echo ""

# Resumen
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}          ✅ INSTALACIÓN COMPLETADA${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📦 App instalada en: $INSTALL_PATH"
echo "📊 Tamaño: $INSTALLED_SIZE"
echo ""
echo "📋 Próximos pasos:"
echo ""
echo "   1. Ejecutar la app:"
echo "      • Ve a Aplicaciones (Applications)"
echo "      • Haz doble clic en 'Lopez Code'"
echo ""
echo "   2. Otorgar permisos:"
echo "      • La primera vez, macOS pedirá permisos automáticamente"
echo "      • O ve a: Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas"
echo "      • Busca 'Lopez Code' y activa: Escritorio y Carpetas de documentos"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Preguntar si quiere abrir la app ahora
echo "¿Deseas abrir la app ahora? (s/n)"
read -r response
if [[ "$response" =~ ^([sS][iI][mM]|[sS])$ ]]; then
    echo ""
    echo -e "${BLUE}🚀 Abriendo Lopez Code...${NC}"
    open "$INSTALL_PATH"
    echo ""
    echo "✅ App abierta. Cuando se inicie, debería aparecer en Configuración del Sistema."
    echo ""
    
    # Esperar 5 segundos y abrir Configuración
    sleep 5
    echo "📱 Abriendo Configuración del Sistema para otorgar permisos..."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
fi

echo ""
echo -e "${GREEN}¡Instalación completada!${NC}"

