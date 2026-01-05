# 📦 Cómo Instalar Lopez Code en macOS

## ⚠️ Diferencia entre macOS y Windows

**En Windows:**
- Las apps tienen instaladores `.exe`
- El instalador muestra un proceso de instalación paso a paso
- Los archivos se copian automáticamente

**En macOS:**
- Las apps son archivos `.app` (carpetas especiales)
- NO hay instaladores ejecutables como en Windows
- La instalación es simplemente **arrastrar el .app a la carpeta Aplicaciones**
- O usar nuestro script automatizado

## 🚀 Método 1: Instalador Automático (Recomendado)

Este método simula un instalador como Windows, mostrando el proceso paso a paso.

### Ejecutar el instalador:

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
./INSTALAR_APP_MACOS.sh
```

Este script:
1. ✅ Verifica si la app está compilada (si no, la compila)
2. ✅ Muestra el proceso de instalación paso a paso
3. ✅ Copia la app a `/Applications`
4. ✅ Configura los permisos necesarios
5. ✅ Abre la app automáticamente
6. ✅ Abre Configuración del Sistema para otorgar permisos

### Qué verás:

```
═══════════════════════════════════════════════════════════════
          🚀 INSTALADOR DE LOPEZ CODE PARA macOS
═══════════════════════════════════════════════════════════════

📋 PASO 1/4: Verificando archivos...
✅ App encontrada: ... (46.2MB)

📋 PASO 2/4: Preparando instalación...

📋 PASO 3/4: Instalando aplicación...
   📦 Copiando archivos...
   📍 Origen: ...
   📍 Destino: /Applications/Lopez Code.app
✅ Instalación completada exitosamente

📋 PASO 4/4: Configurando permisos...
✅ Permisos configurados

═══════════════════════════════════════════════════════════════
          ✅ INSTALACIÓN COMPLETADA
═══════════════════════════════════════════════════════════════
```

## 📦 Método 2: Desde el .dmg (Como apps comerciales)

### Paso 1: Crear el DMG

```bash
./crear_instalador.sh
```

Esto crea `Lopez_Code_Installer.dmg`

### Paso 2: Instalar desde el DMG

1. Haz doble clic en `Lopez_Code_Installer.dmg`
2. Se abrirá una ventana con:
   - `Lopez Code.app`
   - Carpeta `Applications` (enlace)
3. Arrastra `Lopez Code.app` a `Applications`
4. La instalación está completa

## 📋 Método 3: Manual (Sin instalador)

```bash
# 1. Compilar
flutter build macos --release

# 2. Copiar manualmente
# Abre Finder y navega a:
# build/macos/Build/Products/Release/
# Arrastra "Lopez Code.app" a tu carpeta Aplicaciones
```

## ✅ Verificar Instalación

Para verificar que la app está instalada:

```bash
ls -la "/Applications/Lopez Code.app"
```

Si aparece, la app está instalada correctamente.

## 🔐 Otorgar Permisos

**IMPORTANTE:** La app NO aparecerá en Configuración del Sistema hasta que:

1. ✅ Esté instalada en `/Applications`
2. ✅ Se haya ejecutado al menos una vez
3. ✅ Haya intentado acceder a archivos

### Pasos:

1. **Ejecuta la app:**
   ```bash
   open "/Applications/Lopez Code.app"
   ```

2. **Espera unos segundos** mientras la app se inicia

3. **Abre Configuración del Sistema:**
   - Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas
   - O ejecuta: `./forzar_permisos.sh`

4. **Busca "Lopez Code"** en la lista
   - Si no aparece inmediatamente, espera 10-30 segundos
   - Haz scroll arriba y abajo
   - O cierra y vuelve a abrir Configuración

5. **Activa los permisos:**
   - ✅ Escritorio
   - ✅ Carpetas de documentos

## 🆘 Solución de Problemas

### La app no aparece en Configuración

**Solución:**
```bash
# 1. Ejecutar la app
open "/Applications/Lopez Code.app"

# 2. Esperar 10 segundos

# 3. Cerrar la app (Cmd+Q)

# 4. Abrir Configuración
open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"

# 5. Buscar "Lopez Code"
```

### Error "La app está dañada"

**Solución:**
```bash
sudo xattr -cr "/Applications/Lopez Code.app"
```

Luego vuelve a abrir la app.

### La app no se abre

**Solución:**
1. Haz clic derecho en la app > "Abrir" > "Abrir" (confirma dos veces)
2. O ve a Preferencias del Sistema > Seguridad y Privacidad > Haz clic en "Abrir de todas formas"

## 📝 Resumen

**En macOS, el "instalador" es simplemente:**
- Copiar el `.app` a `/Applications`
- Ejecutar la app una vez
- Otorgar permisos cuando macOS lo solicite

**Nuestro script automatiza todo esto:**
```bash
./INSTALAR_APP_MACOS.sh
```

¡Es así de simple! 🎉

