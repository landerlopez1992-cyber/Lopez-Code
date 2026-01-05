# 🔧 Guía de Instalación de Xcode para macOS

## Problema Actual

Estás viendo este error:
```
xcrun: error: unable to find utility "xcodebuild", not a developer tool or in PATH
```

Esto significa que necesitas instalar **Xcode completo** (no solo las Command Line Tools).

## Solución Paso a Paso

### Opción 1: Instalar Xcode desde la App Store (Recomendado)

1. **Abre la App Store en tu Mac**
   - Haz clic en el ícono de la App Store en el Dock
   - O busca "App Store" en Spotlight (⌘ + Espacio)

2. **Busca Xcode**
   - En la barra de búsqueda, escribe "Xcode"
   - Haz clic en el resultado de Xcode (desarrollado por Apple)

3. **Instala Xcode**
   - Haz clic en el botón "Obtener" o "Instalar"
   - **NOTA:** Xcode es grande (alrededor de 10-15 GB), así que asegúrate de tener espacio y una buena conexión a internet
   - La instalación puede tardar 30 minutos a varias horas dependiendo de tu conexión

4. **Abre Xcode por primera vez**
   - Después de la instalación, abre Xcode desde la carpeta Aplicaciones
   - Acepta los términos y condiciones
   - Espera a que instale componentes adicionales (esto puede tardar unos minutos)

5. **Configura las herramientas de línea de comandos**
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

6. **Acepta la licencia de Xcode**
   ```bash
   sudo xcodebuild -license accept
   ```

### Opción 2: Instalar solo Command Line Tools (Alternativa más rápida)

Si no quieres instalar Xcode completo (que es muy grande), puedes intentar instalar solo las herramientas necesarias:

```bash
xcode-select --install
```

Sin embargo, para desarrollo de apps macOS con Flutter, **se recomienda Xcode completo**.

## Verificar la Instalación

Después de instalar, verifica que todo funciona:

```bash
# Verificar versión de Xcode
xcodebuild -version

# Verificar que Flutter detecta Xcode
flutter doctor
```

Deberías ver algo como:
```
[✓] Xcode - develop for iOS and macOS (Xcode 15.0)
```

## Si Ya Tienes Xcode Instalado

Si ya tienes Xcode pero sigue dando error, intenta:

1. **Reinstalar las herramientas:**
   ```bash
   sudo xcode-select --reset
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

2. **Actualizar Xcode:**
   - Abre la App Store
   - Ve a la pestaña "Actualizaciones"
   - Actualiza Xcode si hay una versión disponible

## Después de Instalar Xcode

Una vez que Xcode esté instalado correctamente, podrás ejecutar tu app:

```bash
cd /Users/cubcolexpress/Desktop/Proyectos/constructor
flutter run -d macos
```

## Notas Importantes

- **Espacio en disco:** Xcode requiere al menos 15-20 GB de espacio libre
- **Tiempo:** La instalación puede tardar mucho tiempo
- **Internet:** Necesitas una conexión estable a internet
- **Actualizaciones:** Xcode se actualiza frecuentemente, manténlo actualizado

## ¿Necesitas Ayuda?

Si después de instalar Xcode sigues teniendo problemas:

1. Ejecuta `flutter doctor -v` y comparte el resultado
2. Verifica que Xcode esté en `/Applications/Xcode.app`
3. Asegúrate de haber aceptado la licencia de Xcode


