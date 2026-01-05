# Cursor AI Assistant

Una aplicación Flutter para macOS que proporciona un asistente de IA similar a Cursor, capaz de leer imágenes, interpretar código y editar archivos locales.

## 🚀 Características

- 💬 Chat con IA usando OpenAI API
- 🖼️ Soporte para leer e interpretar imágenes
- 📝 **Creación y edición automática de archivos de código**
- 🤖 **Desarrollo asistido por IA** - Pide crear apps/páginas web y la IA genera el código
- 💾 Guardado automático de archivos generados
- 🎨 Interfaz moderna con tema oscuro
- 💾 Historial de conversación
- 📋 Visualización de código con sintaxis destacada
- 🔧 **Acceso completo al sistema de archivos local**

## 📋 Requisitos Previos

- Flutter SDK (versión 3.10.4 o superior)
- macOS (MacBook Air, MacBook Pro, iMac, Mac mini, etc.)
- Una cuenta de OpenAI con API Key

## 🔑 Cómo Obtener tu API Key de OpenAI

1. **Visita el sitio de OpenAI:**
   - Ve a [https://platform.openai.com](https://platform.openai.com)

2. **Inicia sesión o crea una cuenta:**
   - Si no tienes cuenta, crea una nueva
   - Si ya tienes cuenta, inicia sesión

3. **Navega a la sección de API Keys:**
   - Haz clic en tu perfil (esquina superior derecha)
   - Selecciona "API keys" o ve directamente a [https://platform.openai.com/api-keys](https://platform.openai.com/api-keys)

4. **Crea una nueva API Key:**
   - Haz clic en el botón "Create new secret key"
   - Dale un nombre descriptivo (opcional)
   - **IMPORTANTE:** Copia la clave inmediatamente, ya que no podrás verla de nuevo

5. **Configura tu crédito:**
   - Asegúrate de tener créditos en tu cuenta de OpenAI
   - Ve a [https://platform.openai.com/account/billing](https://platform.openai.com/account/billing) para agregar créditos

## 🛠️ Instalación

1. **Clona o navega al directorio del proyecto:**
   ```bash
   cd /Users/cubcolexpress/Desktop/Proyectos/constructor
   ```

2. **Instala las dependencias:**
   ```bash
   flutter pub get
   ```

3. **Ejecuta la aplicación:**
   ```bash
   flutter run -d macos
   ```

## ⚙️ Configuración

La primera vez que ejecutes la aplicación, se te pedirá que ingreses tu API Key de OpenAI. Puedes cambiarla en cualquier momento desde el menú de configuración (ícono de engranaje en la barra superior).

## 📖 Uso

### Enviar un Mensaje
- Escribe tu mensaje en el campo de texto inferior
- Presiona Enter o haz clic en el botón de enviar

### Adjuntar una Imagen
- Haz clic en el ícono de imagen (📷) en la barra de entrada
- Selecciona una imagen de tu Mac
- La IA podrá ver y analizar la imagen

### Adjuntar un Archivo de Código
- Haz clic en el ícono de archivo (📄) en la barra de entrada
- Selecciona un archivo de código
- La IA podrá leer y editar el contenido del archivo

### Crear y Editar Archivos Automáticamente
La IA puede crear y editar archivos automáticamente. Ejemplos:

**Crear archivos nuevos:**
- "Crea una página web HTML con un formulario de contacto"
- "Genera una app Flutter con una lista de tareas"
- "Crea un archivo Python que lea un CSV y muestre estadísticas"

**Editar archivos existentes:**
- Adjunta un archivo y di: "Agrega una función que calcule el factorial"
- "Corrige los errores de sintaxis en este archivo"
- "Optimiza este código para mejor rendimiento"

**La app detectará automáticamente:**
- Cuando quieres crear un archivo nuevo
- Cuando quieres editar un archivo existente
- Extraerá el código de la respuesta de la IA
- Te preguntará dónde guardar el archivo
- Guardará el código automáticamente en tu Mac

## 🏗️ Estructura del Proyecto

```
lib/
├── main.dart                 # Punto de entrada de la aplicación
├── models/
│   └── message.dart          # Modelo de mensaje
├── screens/
│   └── chat_screen.dart      # Pantalla principal del chat
├── services/
│   ├── openai_service.dart   # Servicio para comunicarse con OpenAI
│   ├── file_service.dart     # Servicio para manejar archivos
│   └── config_service.dart   # Servicio para guardar configuración
└── widgets/
    ├── message_bubble.dart   # Widget para mostrar mensajes
    └── code_viewer.dart      # Widget para visualizar código
```

## 🔒 Seguridad

- Tu API Key se guarda localmente en tu Mac usando `shared_preferences`
- La API Key nunca se comparte ni se envía a servidores externos (excepto a OpenAI para las solicitudes)
- Puedes eliminar tu API Key en cualquier momento desde la configuración

## 🐛 Solución de Problemas

### Error: "Error al comunicarse con OpenAI"
- Verifica que tu API Key sea correcta
- Asegúrate de tener créditos en tu cuenta de OpenAI
- Verifica tu conexión a internet

### La aplicación no inicia
- Verifica que Flutter esté correctamente instalado: `flutter doctor`
- Asegúrate de tener las herramientas de desarrollo de macOS instaladas

### No puedo seleccionar archivos
- Verifica los permisos de la aplicación en Preferencias del Sistema > Seguridad y Privacidad

## 📝 Notas

- Esta aplicación está diseñada específicamente para macOS
- No está configurada para Android o iOS
- Usa el modelo GPT-4o de OpenAI (puedes cambiarlo en `openai_service.dart`)

## 🔄 Actualizaciones Futuras

- [ ] Soporte para múltiples modelos de IA
- [ ] Historial de conversaciones persistente
- [ ] Exportar conversaciones
- [ ] Temas personalizables
- [ ] Soporte para edición de archivos directamente desde la app

## 📄 Licencia

Este proyecto es de uso personal/educacional.

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Siéntete libre de abrir un issue o pull request.

---

**Desarrollado con ❤️ usando Flutter**
