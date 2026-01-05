#!/bin/bash

# Solución DEFINITIVA para que Lopez Code aparezca en Configuración del Sistema

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

APP_PATH="/Applications/Lopez Code.app"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "          🔧 SOLUCIÓN DEFINITIVA PARA PERMISOS"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Paso 1: Cerrar TODAS las instancias de la app
echo -e "${BLUE}📋 PASO 1/5: Cerrando todas las instancias de Lopez Code...${NC}"

# Cerrar todas las instancias
pkill -f "Lopez Code" 2>/dev/null || true
killall "Lopez Code" 2>/dev/null || true

# Esperar un momento para asegurar que se cerraron
sleep 2

echo -e "${GREEN}✅ Todas las instancias cerradas${NC}"
echo ""

# Paso 2: Verificar que la app está instalada
echo -e "${BLUE}📋 PASO 2/5: Verificando instalación...${NC}"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Error: La app NO está instalada en $APP_PATH${NC}"
    echo "   Por favor, instala la app primero con: ./INSTALAR_APP_MACOS.sh"
    exit 1
fi

echo -e "${GREEN}✅ App instalada en: $APP_PATH${NC}"
echo ""

# Paso 3: Limpiar atributos extendidos (pueden causar problemas)
echo -e "${BLUE}📋 PASO 3/5: Limpiando atributos de seguridad...${NC}"

xattr -cr "$APP_PATH" 2>/dev/null || true

echo -e "${GREEN}✅ Atributos limpiados${NC}"
echo ""

# Paso 4: Ejecutar la app DESDE /Applications (no desde build/)
echo -e "${BLUE}📋 PASO 4/5: Ejecutando app desde /Applications...${NC}"

# Abrir la app usando open (esto asegura que se ejecute desde /Applications)
open "$APP_PATH"

echo -e "${GREEN}✅ App ejecutada${NC}"
echo ""

# Esperar a que la app se inicie
echo -e "${YELLOW}⏳ Esperando 10 segundos mientras la app se inicia...${NC}"
sleep 10

# Paso 5: Abrir Configuración del Sistema
echo -e "${BLUE}📋 PASO 5/5: Abriendo Configuración del Sistema...${NC}"

open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}          ✅ PROCESO COMPLETADO${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 INSTRUCCIONES:"
echo ""
echo "   1. En Configuración del Sistema (que acaba de abrirse):"
echo "      • Busca 'Lopez Code' en la lista de apps"
echo "      • Si no aparece, haz scroll arriba y abajo"
echo ""
echo "   2. Si aún NO aparece:"
echo "      • Espera 30 segundos"
echo "      • Haz scroll arriba y abajo varias veces"
echo "      • Cierra y vuelve a abrir Configuración"
echo ""
echo "   3. Cuando aparezca 'Lopez Code':"
echo "      • Haz clic en el triángulo para expandir"
echo "      • Activa: Escritorio y Carpetas de documentos"
echo "      • Cierra Configuración"
echo ""
echo "   4. Vuelve a la app Lopez Code:"
echo "      • Haz clic en 'Verificar' en el diálogo de permisos"
echo "      • O cierra y vuelve a abrir la app"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

