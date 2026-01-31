# Guía: Integración de OpenAI Agent Builder en Lopez Code

## ¿Qué es OpenAI Agent Builder?

Es una herramienta visual de OpenAI para crear agentes de IA personalizados. Te permite:

1. **Definir Instrucciones Personalizadas** (System Prompt):
   - Cómo debe comportarse el agente
   - Qué puede y no puede hacer
   - Su personalidad y estilo de respuesta

2. **Seleccionar Herramientas** (Tools):
   - **Web Search**: Buscar información en internet
   - **Code Interpreter**: Ejecutar código Python y analizar archivos
   - **Image Generation**: Generar imágenes con DALL-E

3. **Estructurar Workflows**:
   - Definir pasos del agente
   - Lógica condicional (if/else)
   - Flujos complejos

## Cómo Integrarlo en tu App

### Opción 1: Usar Workflow ID (Recomendado)

Una vez que construyas tu agente en platform.openai.com/agent-builder, obtienes un **Workflow ID** que puedes usar directamente en tu app.

**Pasos:**
1. Ve a https://platform.openai.com/agent-builder
2. Construye tu agente (instrucciones, herramientas)
3. Publica el workflow
4. Obtén el Workflow ID (ej: `wf_695b29bcf47481909d1eac465de8e6340cfb`)
5. Usa ese ID en tu app para llamar al agente

### Opción 2: Construir Agente Directamente en la App (Actual)

Actualmente tu app ya usa la API de OpenAI directamente con:
- System Prompt personalizado
- Function Calling (edit_file, create_file, read_file)
- Modelos configurables

## Diseño de Agente Poderoso para Lopez Code

### Instrucciones Recomendadas (System Prompt):

```
Eres un asistente de código experto especializado en Flutter/Dart.

TU PROPÓSITO:
- Ayudar a desarrollar aplicaciones Flutter de manera eficiente
- Escribir código limpio, mantenible y siguiendo best practices
- Analizar y corregir errores rápidamente
- Proponer mejoras arquitectónicas

COMPORTAMIENTO:
- Analiza cuidadosamente antes de actuar (como Cursor agent)
- Siempre lee archivos completos antes de editarlos
- Proporciona código completo y funcional, no fragmentos
- Mantén la estructura existente del código
- Explica brevemente tus decisiones técnicas

CAPACIDADES:
- Tienes acceso directo al sistema de archivos (read_file, edit_file, create_file)
- Puedes analizar imágenes de código/diseños
- Puedes ejecutar y depurar código Flutter
- Conoces Flutter, Dart, y arquitecturas modernas (BLoC, Provider, Riverpod)

REGLAS CRÍTICAS:
- NUNCA elimines código no relacionado con la tarea
- SIEMPRE verifica que el código compila antes de proporcionarlo
- MANTÉN imports necesarios y estructura del archivo
- TRABAJA CON PRECISIÓN, no con velocidad
```

### Herramientas Recomendadas:

1. **Code Interpreter** (Opcional):
   - Para ejecutar código Python si necesitas análisis complejo
   - Útil para procesar datos o archivos grandes

2. **Web Search** (Opcional):
   - Para buscar documentación actualizada
   - Buscar soluciones a problemas específicos
   - Verificar best practices

3. **Function Calling** (Ya implementado):
   - edit_file: Editar archivos existentes
   - create_file: Crear nuevos archivos
   - read_file: Leer archivos del proyecto

## Próximos Pasos

1. **Construir el agente en OpenAI Agent Builder** (opcional)
2. **Mejorar el System Prompt actual** en SettingsService (ya implementado)
3. **Agregar soporte para Workflow ID** en OpenAIService (si decides usar Agent Builder)
4. **Configurar herramientas adicionales** según necesidad

## Nota Importante

Tu app actual ya tiene un agente poderoso configurado. El OpenAI Agent Builder es útil si:
- Quieres una interfaz visual para configurar el agente
- Necesitas workflows complejos
- Quieres usar herramientas como Web Search o Code Interpreter fácilmente

Para tu caso de uso (asistente de código Flutter), el enfoque actual (System Prompt + Function Calling) es muy efectivo.

