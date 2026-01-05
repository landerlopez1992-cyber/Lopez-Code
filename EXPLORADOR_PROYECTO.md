# 📁 Sistema de Explorador de Proyectos

## ✅ Funcionalidades Implementadas

### 1. **Selección de Proyecto al Iniciar**
- ✅ Al abrir la app por primera vez, se pide seleccionar la carpeta del proyecto
- ✅ La selección se guarda automáticamente
- ✅ Al volver a abrir la app, carga el proyecto guardado
- ✅ Puedes cambiar el proyecto desde el menú (ícono de carpeta)

### 2. **Panel Lateral de Explorador de Archivos**
- ✅ Panel lateral izquierdo que muestra todos los archivos del proyecto
- ✅ Estructura de árbol navegable (como Cursor)
- ✅ Iconos diferentes según el tipo de archivo
- ✅ Colores según la extensión del archivo
- ✅ Click para seleccionar archivo
- ✅ Doble click para ver contenido del archivo

### 3. **Restricción de Acceso**
- ✅ La IA **SOLO** puede acceder a archivos dentro del proyecto seleccionado
- ✅ Si intentas seleccionar un archivo fuera del proyecto, se muestra un error
- ✅ Al crear/editar archivos, se verifica que estén dentro del proyecto
- ✅ Seguridad: No puede acceder a archivos del sistema fuera del proyecto

### 4. **Interfaz Visual**
- ✅ Panel lateral con ancho de 300px
- ✅ Botón para mostrar/ocultar el panel
- ✅ Header con nombre del proyecto
- ✅ Botón de actualizar para refrescar la lista
- ✅ Resaltado del archivo seleccionado

## 🎨 Características del Explorador

### Iconos por Tipo de Archivo
- 📁 **Carpetas**: Icono de carpeta (amarillo)
- 💙 **Dart**: Icono de código (azul)
- 💛 **JavaScript/JSX**: Icono JavaScript (amarillo)
- 🔵 **TypeScript/TSX**: Icono TypeScript (azul claro)
- 🟠 **HTML**: Icono HTML (naranja)
- 🔵 **CSS**: Icono CSS (azul)
- 🟢 **JSON**: Icono JSON (verde)
- 🟣 **YAML**: Icono YAML (morado)
- ⚪ **Markdown**: Icono Markdown (gris)
- 📄 **Otros**: Icono genérico de archivo

### Funcionalidades
- **Expandir/Colapsar**: Click en carpetas para expandir/colapsar
- **Selección**: Click en archivo para seleccionarlo
- **Vista Previa**: Doble click para ver contenido del archivo
- **Actualizar**: Botón de refresh para actualizar la lista
- **Ocultar/Mostrar**: Botón en el borde para ocultar/mostrar el panel

## 🔒 Seguridad

### Restricciones Implementadas
1. **Solo archivos del proyecto**: La IA no puede acceder a archivos fuera del proyecto
2. **Verificación automática**: Cada operación verifica que el archivo esté en el proyecto
3. **Carpetas ocultas ignoradas**: No se muestran `.git`, `.dart_tool`, `node_modules`, etc.
4. **Archivos ocultos ignorados**: No se muestran archivos que empiezan con `.`

## 📝 Cómo Usar

### Seleccionar un Proyecto

1. **Primera vez:**
   - Al abrir la app, aparecerá un diálogo
   - Haz clic en "Seleccionar Carpeta del Proyecto"
   - Elige la carpeta de tu proyecto
   - ✅ El proyecto se guarda automáticamente

2. **Cambiar proyecto:**
   - Haz clic en el ícono de 📁 en la barra superior
   - Selecciona una nueva carpeta
   - ✅ El nuevo proyecto se guarda

### Usar el Explorador

1. **Ver archivos:**
   - El panel lateral muestra todos los archivos
   - Click en carpetas para expandir/colapsar

2. **Seleccionar archivo:**
   - Click simple en un archivo para seleccionarlo
   - El archivo se resalta en azul
   - Puedes usarlo en el chat

3. **Ver contenido:**
   - Doble click en un archivo
   - Se abre un diálogo con el contenido
   - Puedes copiar o usar el archivo

4. **Ocultar panel:**
   - Click en el borde del panel (línea gris)
   - O usa el botón en la barra superior

## 🎯 Ejemplos de Uso

### Ejemplo 1: Seleccionar archivo para editar
1. Abre el explorador (si está oculto)
2. Navega hasta el archivo que quieres editar
3. Click simple para seleccionarlo
4. En el chat, di: "Edita este archivo y agrega una función X"
5. ✅ La IA solo puede editar ese archivo (está en el proyecto)

### Ejemplo 2: Crear nuevo archivo
1. En el chat, di: "Crea un archivo llamado `utils.dart` en la carpeta `lib`"
2. ✅ La IA creará el archivo dentro del proyecto
3. El explorador se actualizará automáticamente

### Ejemplo 3: Ver estructura del proyecto
1. Abre el explorador
2. Navega por las carpetas
3. Ve la estructura completa de tu proyecto
4. ✅ Solo ves archivos dentro del proyecto seleccionado

## ⚠️ Notas Importantes

1. **Solo archivos del proyecto**: La IA no puede acceder a nada fuera del proyecto
2. **Carpetas ocultas**: `.git`, `node_modules`, `.dart_tool` no se muestran
3. **Actualización**: Si agregas archivos manualmente, usa el botón de refresh
4. **Seguridad**: Todos los accesos se verifican antes de permitirse

## 🔄 Próximas Mejoras

- [ ] Búsqueda de archivos en el explorador
- [ ] Crear carpetas/archivos desde el explorador
- [ ] Drag & drop de archivos
- [ ] Filtros por tipo de archivo
- [ ] Vista de cambios (git status)


