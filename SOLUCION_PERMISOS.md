# 🔐 Solución: App no aparece en Configuración del Sistema

## Problema

La app "Lopez Code" no aparece en la lista de Configuración del Sistema > Archivos y Carpetas, por lo que no puedes otorgar permisos.

## Solución Rápida

### Opción 1: Ejecutar script automático

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
./forzar_permisos.sh
```

Este script:
- ✅ Ejecuta la app brevemente para que macOS la registre
- ✅ Abre Configuración del Sistema automáticamente
- ✅ Te guía para encontrar la app

### Opción 2: Manual

1. **Abre la app manualmente:**
   - Ve a **Aplicaciones**
   - Haz doble clic en **"Lopez Code"**
   - La primera vez, macOS puede pedirte confirmar (haz clic en "Abrir")

2. **Espera unos segundos** mientras la app se inicia

3. **Cierra la app** (Cmd+Q)

4. **Abre Configuración del Sistema:**
   - Preferencias del Sistema > Seguridad y Privacidad > Archivos y Carpetas
   - O ejecuta: `open "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"`

5. **Busca "Lopez Code"** en la lista
   - Si no aparece inmediatamente, espera 10-15 segundos
   - Haz scroll arriba y abajo para refrescar
   - O cierra y vuelve a abrir Configuración

## ¿Por qué no aparece?

macOS solo muestra apps en la lista de permisos cuando:
- ✅ La app está instalada en `/Applications` o `/Applications/Utilities`
- ✅ La app se ha ejecutado al menos una vez
- ✅ La app ha intentado acceder a archivos (lo que activa la solicitud de permisos)

## Verificación

Para verificar que la app está instalada:

```bash
ls -la "/Applications/Lopez Code.app"
```

Si aparece, la app está instalada. Solo necesitas ejecutarla una vez.

## Si aún no aparece

1. **Reinstala la app:**
   ```bash
   # Eliminar si existe
   rm -rf "/Applications/Lopez Code.app"
   
   # Abrir el instalador
   open Lopez_Code_Installer.dmg
   
   # Arrastrar la app a Applications
   # Luego ejecutar la app
   ```

2. **Verifica que la app se puede ejecutar:**
   ```bash
   open "/Applications/Lopez Code.app"
   ```

3. **Si macOS dice "La app está dañada":**
   ```bash
   sudo xattr -cr "/Applications/Lopez Code.app"
   ```

4. **Luego ejecuta la app de nuevo:**
   ```bash
   open "/Applications/Lopez Code.app"
   ```

## Nota Importante

- En modo **debug** (cuando ejecutas `flutter run`), la app NO aparece en Configuración
- Solo aparece cuando está **instalada** en Aplicaciones y se ha **ejecutado** al menos una vez
- Después de ejecutarla, puede tardar 10-30 segundos en aparecer en la lista

