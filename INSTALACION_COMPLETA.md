# 🚀 Instalación Completa de Lopez Code

## Método 1: Instalador .dmg (Recomendado - Como Cursor)

Este método crea un instalador profesional similar a Cursor.

### Paso 1: Crear el instalador

Ejecuta en la terminal:

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
./crear_instalador.sh
```

Este script:
- ✅ Compila la app para release
- ✅ Crea un archivo `.dmg` profesional
- ✅ Incluye la app y un enlace a Aplicaciones
- ✅ Listo para distribuir

### Paso 2: Instalar desde el .dmg

1. **Abre el archivo `Lopez_Code_Installer.dmg`**
   - Haz doble clic en el archivo `.dmg` que se creó
   - Se abrirá una ventana con la app

2. **Arrastra la app a Aplicaciones**
   - En la ventana del DMG, verás "Lopez Code.app"
   - También verás una carpeta "Applications" (enlace)
   - Arrastra "Lopez Code.app" a "Applications"

3. **Abre la app**
   - Ve a Aplicaciones (Applications)
   - Haz doble clic en "Lopez Code"
   - La primera vez, macOS puede pedirte confirmar (haz clic en "Abrir")

4. **Otorga permisos**
   - La app te pedirá permisos automáticamente
   - O ve a: **Preferencias del Sistema** > **Seguridad y Privacidad** > **Archivos y Carpetas**
   - Busca "Lopez Code" y activa:
     - ✅ Escritorio
     - ✅ Carpetas de documentos

## Método 2: Instalación directa (Rápida)

Si solo quieres probar la app rápidamente:

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
./instalar.sh
```

Este script compila e instala directamente en Aplicaciones.

## Método 3: Manual

```bash
# 1. Compilar
flutter build macos --release

# 2. Instalar manualmente
# Abre Finder y navega a:
# build/macos/Build/Products/Release/
# Arrastra "Lopez Code.app" a Aplicaciones
```

## Verificación

Después de instalar, verifica que la app aparezca en:

1. **Aplicaciones**: Deberías ver "Lopez Code.app"
2. **Configuración del Sistema**: 
   - Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas
   - Deberías ver "Lopez Code" en la lista

## Solución de problemas

### La app no aparece en Configuración del Sistema

- **Causa**: Solo ejecutaste en modo debug, no instalaste
- **Solución**: Usa `./crear_instalador.sh` o `./instalar.sh` para instalar

### Error "La app está dañada"

- **Causa**: macOS bloquea apps no firmadas
- **Solución**: 
  ```bash
  sudo xattr -cr "/Applications/Lopez Code.app"
  ```
  Luego abre la app normalmente

### No puedo abrir la app

1. Haz clic derecho en la app > "Abrir" > "Abrir" (confirma dos veces)
2. O ve a Preferencias del Sistema > Seguridad y Privacidad > Haz clic en "Abrir de todas formas"

## Distribución

Si quieres compartir la app con otros:

1. Crea el instalador: `./crear_instalador.sh`
2. Comparte el archivo `Lopez_Code_Installer.dmg`
3. Los usuarios solo necesitan:
   - Abrir el `.dmg`
   - Arrastrar la app a Aplicaciones
   - Listo ✅

