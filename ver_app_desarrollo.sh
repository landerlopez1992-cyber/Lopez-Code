#!/bin/bash

echo "🚀 Iniciando app en modo desarrollo (hot reload)..."
echo "📝 Puedes editar los archivos en Cursor y ver los cambios en tiempo real"
echo ""
echo "Para ver cambios:"
echo "  1. Edita lib/screens/multi_chat_screen.dart en Cursor"
echo "  2. Guarda el archivo (Cmd+S)"
echo "  3. Presiona 'r' en esta terminal para hot reload"
echo "  4. O presiona 'R' para hot restart"
echo ""

cd "$(dirname "$0")"
flutter run -d macos
