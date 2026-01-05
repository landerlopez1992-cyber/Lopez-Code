#!/bin/bash

echo "🔧 Configurando Xcode para Flutter..."
echo ""

# Verificar que Xcode esté instalado
if [ ! -d "/Applications/Xcode.app" ]; then
    echo "❌ Error: Xcode no se encuentra en /Applications/Xcode.app"
    echo "   Por favor, asegúrate de que Xcode esté completamente instalado."
    exit 1
fi

echo "✓ Xcode encontrado"
echo ""

# Configurar el path de desarrollador
echo "📝 Configurando herramientas de línea de comandos..."
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

if [ $? -eq 0 ]; then
    echo "✓ Path de desarrollador configurado"
else
    echo "❌ Error al configurar el path"
    exit 1
fi

echo ""

# Aceptar licencia
echo "📄 Aceptando licencia de Xcode..."
sudo xcodebuild -license accept

if [ $? -eq 0 ]; then
    echo "✓ Licencia aceptada"
else
    echo "⚠️  Puede que necesites aceptar la licencia manualmente"
fi

echo ""
echo "✅ Configuración completada!"
echo ""
echo "Ahora puedes ejecutar:"
echo "  flutter doctor"
echo "  flutter run -d macos"
echo ""


