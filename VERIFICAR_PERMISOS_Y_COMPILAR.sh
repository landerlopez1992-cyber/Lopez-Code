#!/bin/bash

# Script para verificar permisos y compilar la app con el nuevo system prompt

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "          🔧 VERIFICAR PERMISOS Y COMPILAR"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Paso 1: Resetear permisos
echo -e "${BLUE}📋 PASO 1/3: Reseteando permisos de macOS...${NC}"
tccutil reset All com.cubcolexpress.lopezCode 2>&1
echo -e "${GREEN}✅ Permisos reseteados${NC}"
echo ""

# Paso 2: Compilar
echo -e "${BLUE}📋 PASO 2/3: Compilando app con nuevo system prompt...${NC}"
flutter build macos --release
echo -e "${GREEN}✅ Compilación completada${NC}"
echo ""

# Paso 3: Instalar y ejecutar
echo -e "${BLUE}📋 PASO 3/3: Instalando y ejecutando...${NC}"

# Encontrar app
APP_SOURCE=$(find . -name "Lopez Code.app" -type d -path "*/Release/*" 2>/dev/null | head -1)

if [ -z "$APP_SOURCE" ] || [ ! -d "$APP_SOURCE" ]; then
    echo -e "${RED}❌ Error: No se encontró la app compilada${NC}"
    exit 1
fi

# Instalar
if [ -d "/Applications/Lopez Code.app" ]; then
    rm -rf "/Applications/Lopez Code.app"
fi
cp -R "$APP_SOURCE" "/Applications/Lopez Code.app"
xattr -cr "/Applications/Lopez Code.app" 2>/dev/null || true

echo -e "${GREEN}✅ App instalada${NC}"
echo ""

# Ejecutar
open "/Applications/Lopez Code.app"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}          ✅ PROCESO COMPLETADO${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "📋 PRÓXIMOS PASOS:"
echo ""
echo "   1. Cuando la app se abra, macOS pedirá permisos"
echo "   2. Otorga permisos cuando macOS lo solicite:"
echo "      • Ve a Configuración del Sistema"
echo "      • Seguridad y Privacidad > Archivos y Carpetas"
echo "      • Busca 'Lopez Code' y activa: Escritorio y Carpetas de documentos"
echo ""
echo "   3. La IA ahora NO dirá 'no puedo aplicar cambios'"
echo "      • Proporcionará código completo directamente"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

