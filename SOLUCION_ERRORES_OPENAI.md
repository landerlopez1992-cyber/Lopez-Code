# 🔧 Solución: Errores de OpenAI cuando se carga el proyecto

## Problema

Cuando se carga un proyecto, la app muestra errores como "sin crédito" o "rate limit", pero **SÍ hay crédito** y la IA funciona cuando **NO** se carga el proyecto.

## Causa Raíz

El problema es que cuando se carga el proyecto, se envía **demasiado contexto** a la API de OpenAI:

- **Antes:** Hasta 20 archivos × 50KB = **1MB de contexto** por solicitud
- Esto puede causar:
  - ❌ Errores de `context_length_exceeded` (mensaje demasiado largo)
  - ❌ Errores de rate limit por tamaño de solicitud
  - ❌ Errores que se interpretan incorrectamente como "sin crédito"

## Solución Implementada

### 1. Reducción del Contexto

**Archivo:** `lib/services/project_context_service.dart`

```dart
// ANTES:
int maxFiles = 20;
int maxFileSize = 50000; // 50KB

// AHORA:
int maxFiles = 5;        // Solo 5 archivos principales
int maxFileSize = 10000; // Solo 10KB por archivo
```

Esto reduce el contexto de **1MB a ~50KB máximo**.

### 2. Manejo de Errores Específicos

**Archivo:** `lib/services/openai_service.dart`

- ✅ Agregado manejo de `context_length_exceeded` (error 400)
- ✅ Mejorado el parsing de errores para distinguir entre:
  - `insufficient_quota` (sin crédito real)
  - `rate_limit` (demasiadas solicitudes)
  - `context_length_exceeded` (mensaje muy largo)
  - `invalid_api_key` (clave inválida)

### 3. Logging y Truncamiento

**Archivo:** `lib/screens/chat_screen.dart`

- ✅ Agregado logging del tamaño del contexto
- ✅ Truncamiento automático si el contexto excede 50KB
- ✅ Manejo de errores al obtener el contexto (continúa sin contexto si falla)

## Verificación

Para verificar que funciona:

1. **Carga un proyecto pequeño primero** para probar
2. **Revisa los logs** en la consola de Flutter:
   ```
   📊 Tamaño del contexto del proyecto: X caracteres
   📊 Tamaño del resumen: Y caracteres
   ```

3. **Si el contexto es muy grande**, se truncará automáticamente:
   ```
   ⚠️ Contexto muy grande (X chars), reduciendo...
   ```

## Próximos Pasos (Opcional)

Si aún tienes problemas con proyectos muy grandes, puedes:

1. **Reducir más el contexto:**
   - Cambiar `maxFiles` de 5 a 3
   - Cambiar `maxFileSize` de 10000 a 5000

2. **Hacer el contexto opcional:**
   - Solo enviar contexto cuando el usuario lo pida explícitamente
   - O enviar solo la estructura, no el contenido de archivos

3. **Usar archivos específicos:**
   - Solo enviar archivos relevantes según el mensaje del usuario
   - No enviar todo el proyecto siempre

## Notas Importantes

- **Los límites de tokens de OpenAI:**
  - `gpt-4o`: ~128,000 tokens de contexto
  - `gpt-4-turbo`: ~128,000 tokens de contexto
  - `gpt-3.5-turbo`: ~16,385 tokens de contexto

- **1 token ≈ 4 caracteres** (en promedio)
- **50KB de contexto ≈ 12,500 tokens** (dentro del límite)

- **Si el proyecto es muy grande**, considera:
  - Usar archivos específicos en lugar del proyecto completo
  - Implementar un sistema de "lazy loading" del contexto
  - Usar resúmenes de archivos en lugar del contenido completo

