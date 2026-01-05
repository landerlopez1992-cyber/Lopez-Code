# Cómo Instalar Lopez Code en macOS

## Opción 1: Instalación desde el código fuente (Recomendado)

### Paso 1: Compilar la app para release

Abre una terminal en la carpeta del proyecto y ejecuta:

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
flutter build macos --release
```

Esto creará la app en: `build/macos/Build/Products/Release/Lopez Code.app`

### Paso 2: Instalar la app

1. Abre Finder
2. Navega a: `build/macos/Build/Products/Release/`
3. Arrastra `Lopez Code.app` a tu carpeta `Aplicaciones` (Applications)
4. O haz clic derecho en `Lopez Code.app` > "Abrir" (puede que macOS te pida confirmar la primera vez)

### Paso 3: Otorgar permisos

1. La primera vez que abras la app, macOS te pedirá permisos
2. Si no aparece automáticamente, ve a:
   - **Preferencias del Sistema** > **Seguridad y Privacidad** > **Archivos y Carpetas**
   - Busca "Lopez Code" en la lista
   - Activa:
     - ✅ Escritorio
     - ✅ Carpetas de documentos
     - ✅ Acceso completo al disco (opcional, pero recomendado)

## Opción 2: Crear un instalador (.dmg)

### Paso 1: Compilar para release

```bash
flutter build macos --release
```

### Paso 2: Crear un DMG (opcional)

Puedes usar herramientas como `create-dmg` para crear un instalador:

```bash
# Instalar create-dmg (si no lo tienes)
brew install create-dmg

# Crear el DMG
create-dmg \
  --volname "Lopez Code" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Lopez Code.app" 200 190 \
  --hide-extension "Lopez Code.app" \
  --app-drop-link 600 185 \
  "Lopez Code.dmg" \
  "build/macos/Build/Products/Release/"
```

## Solución de problemas

### La app no aparece en Configuración del Sistema

- **Causa**: La app está corriendo en modo debug, no está "instalada"
- **Solución**: Compila para release e instálala siguiendo los pasos arriba

### Error "Operation not permitted"

- **Causa**: La app no tiene permisos para acceder a archivos
- **Solución**: 
  1. Ve a Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas
  2. Busca "Lopez Code" y activa los permisos necesarios
  3. Si no aparece, instala la app primero (no solo ejecútala en debug)

### La app no se abre después de instalarla

- **Causa**: macOS bloquea apps de desarrolladores no identificados
- **Solución**:
  1. Ve a Preferencias del Sistema > Seguridad y Privacidad
  2. Haz clic en "Abrir de todas formas" junto al mensaje sobre "Lopez Code"
  3. O haz clic derecho en la app > "Abrir" > "Abrir" (confirma dos veces)

## Notas importantes

- En modo **debug**, la app corre desde Flutter y no aparece como app instalada
- Para que aparezca en Configuración del Sistema, debes **compilar e instalar** la versión release
- La primera vez que instales, macOS puede pedirte confirmar que quieres abrir la app

