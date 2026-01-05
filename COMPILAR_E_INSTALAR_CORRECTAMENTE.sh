#!/bin/bash

# Script para COMPILAR e INSTALAR correctamente la app
# Esto es necesario para que macOS la reconozca y aparezca en Configuración

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "          🔨 COMPILACIÓN E INSTALACIÓN CORRECTA"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Paso 1: Cerrar todas las instancias
echo -e "${BLUE}📋 PASO 1/6: Cerrando instancias existentes...${NC}"
pkill -f "Lopez Code" 2>/dev/null || true
killall "Lopez Code" 2>/dev/null || true
sleep 2
echo -e "${GREEN}✅ Instancias cerradas${NC}"
echo ""

# Paso 2: Limpiar builds anteriores
echo -e "${BLUE}📋 PASO 2/6: Limpiando builds anteriores...${NC}"
flutter clean
echo -e "${GREEN}✅ Build limpio${NC}"
echo ""

# Paso 3: Compilar para release
echo -e "${BLUE}📋 PASO 3/6: Compilando app para release...${NC}"
echo -e "${YELLOW}⏳ Esto puede tardar varios minutos...${NC}"
flutter build macos --release
echo -e "${GREEN}✅ Compilación completada${NC}"
echo ""

# Paso 4: Encontrar la app compilada
echo -e "${BLUE}📋 PASO 4/6: Localizando app compilada...${NC}"
APP_SOURCE=""

# Buscar en todas las ubicaciones posibles
POSSIBLE_PATHS=(
    "android/app/build/outputs/apk/macos/Build/Products/Release/Lopez Code.app"
    "build/macos/Build/Products/Release/Lopez Code.app"
    "build/macos/Build/Products/x86_64/Release/Lopez Code.app"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        APP_SOURCE="$path"
        break
    fi
done

# Si no se encontró, buscar recursivamente
if [ -z "$APP_SOURCE" ]; then
    APP_SOURCE=$(find . -name "Lopez Code.app" -type d -path "*/Release/*" 2>/dev/null | head -1)
fi

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    echo -e "${RED}❌ Error: No se encontró la app compilada${NC}"
    echo "   Buscando en: build/macos/Build/Products/Release/"
    exit 1
fi

echo -e "${GREEN}✅ App encontrada: $APP_SOURCE${NC}"
APP_SIZE=$(du -sh "$APP_SOURCE" | cut -f1)
echo "   Tamaño: $APP_SIZE"
echo ""

# Paso 5: Instalar en /Applications
echo -e "${BLUE}📋 PASO 5/6: Instalando en /Applications...${NC}"

INSTALL_PATH="/Applications/Lopez Code.app"

# Eliminar versión anterior si existe
if [ -d "$INSTALL_PATH" ]; then
    echo -e "${YELLOW}⚠️  Eliminando versión anterior...${NC}"
    rm -rf "$INSTALL_PATH"
fi

# Copiar nueva versión
echo -e "${YELLOW}📦 Copiando archivos...${NC}"
cp -R "$APP_SOURCE" "$INSTALL_PATH"

# Remover atributos extendidos problemáticos
echo -e "${YELLOW}🔧 Limpiando atributos...${NC}"
xattr -cr "$INSTALL_PATH" 2>/dev/null || true

echo -e "${GREEN}✅ Instalación completada en: $INSTALL_PATH${NC}"
echo ""

# Paso 6: Ejecutar la app
echo -e "${BLUE}📋 PASO 6/6: Ejecutando app desde /Applications...${NC}"
open "$INSTALL_PATH"

echo -e "${GREEN}✅ App ejecutada${NC}"
echo ""
echo -e "${YELLOW}⏳ Esperando 15 segundos mientras la app se inicia...${NC}"
sleep 15

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}          ✅ PROCESO COMPLETADO${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 PRÓXIMOS PASOS:"
echo ""
echo "   1. La app está ejecutándose desde /Applications"
echo "   2. Abre Configuración del Sistema:"
echo "      Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas"
echo ""
echo "   3. Busca 'Lopez Code' en la lista"
echo "      • Si no aparece, espera 30 segundos y haz scroll"
echo "      • O cierra y vuelve a abrir Configuración"
echo ""
echo "   4. Cuando aparezca, haz clic en el triángulo y activa:"
echo "      • Escritorio"
echo "      • Carpetas de documentos"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Abrir Configuración automáticamente
sleep 5
echo "📱 Abriendo Configuración del Sistema..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

echo ""
echo -e "${GREEN}¡Proceso completado!${NC}"

