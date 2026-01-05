# 🔧 Solución de Errores Comunes

## Error: "Operation not permitted" al conectar con OpenAI

### Problema
```
Connection failed (OS Error: Operation not permitted, errno = 1)
```

### Solución 1: Otorgar Permisos de Red en macOS

1. **Abre Preferencias del Sistema (System Settings)**
   - Haz clic en el ícono de Apple (🍎) en la esquina superior izquierda
   - Selecciona "Configuración del Sistema" o "System Settings"

2. **Ve a Privacidad y Seguridad**
   - Busca "Privacidad y Seguridad" o "Privacy & Security"
   - O busca "Firewall" en la barra de búsqueda

3. **Configura el Firewall**
   - Si el Firewall está activado, haz clic en "Opciones del Firewall"
   - Busca "cursor_ai_assistant" en la lista
   - Si no aparece, cierra y vuelve a abrir la app, luego verifica de nuevo
   - Asegúrate de que tenga permisos para "Permitir conexiones entrantes"

4. **Alternativa: Desactivar temporalmente el Firewall**
   - Solo para probar, puedes desactivar el Firewall temporalmente
   - **⚠️ No recomendado para uso permanente**

### Solución 2: Verificar Permisos de Red en la App

1. **Cierra completamente la app**
   - Presiona ⌘ + Q para cerrar completamente

2. **Vuelve a abrir la app**
   - macOS debería pedirte permiso para conexiones de red
   - Acepta el permiso cuando aparezca

3. **Verifica en Preferencias del Sistema**
   - Ve a: Configuración del Sistema → Red → Firewall
   - Busca tu app y verifica que tenga permisos

### Solución 3: Verificar Conexión a Internet

1. **Verifica tu conexión Wi-Fi**
   - Asegúrate de estar conectado a internet
   - Prueba abrir https://platform.openai.com en tu navegador

2. **Verifica que no haya bloqueos**
   - Algunos antivirus o firewalls corporativos pueden bloquear conexiones
   - Verifica si hay algún software de seguridad activo

### Solución 4: Recompilar la App

Si los permisos no se aplican, recompila la app:

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
flutter clean
flutter pub get
flutter run -d macos
```

## Error: "API Key inválida"

### Problema
La API Key no es válida o no está configurada.

### Solución
1. Verifica que tu API Key sea correcta
2. Asegúrate de que empiece con `sk-`
3. Verifica que tengas créditos en tu cuenta de OpenAI
4. Ve a la configuración de la app (ícono de engranaje) y actualiza la API Key

## Error: "No se puede leer el archivo"

### Problema
La app no tiene permisos para leer archivos.

### Solución
1. Ve a: Configuración del Sistema → Privacidad y Seguridad → Acceso completo al disco
2. Asegúrate de que "cursor_ai_assistant" tenga permisos
3. Si no aparece, cierra y vuelve a abrir la app

## Error: "Xcode no encontrado"

### Problema
Flutter no puede encontrar Xcode.

### Solución
1. Verifica que Xcode esté instalado: `/Applications/Xcode.app`
2. Ejecuta: `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`
3. Ejecuta: `sudo xcodebuild -license accept`
4. Ejecuta: `flutter doctor` para verificar

## Consejos Generales

- **Siempre acepta los permisos** cuando macOS los solicite
- **Reinicia la app** después de otorgar permisos
- **Verifica tu conexión a internet** antes de usar la app
- **Mantén tu API Key segura** y no la compartas


