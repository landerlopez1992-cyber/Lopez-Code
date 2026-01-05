import 'package:flutter/material.dart';
import '../models/agent_chat.dart';
import '../widgets/cursor_theme.dart';
import '../services/project_service.dart';
import '../services/chat_storage_service.dart';
import 'chat_screen.dart';
import 'welcome_screen.dart';

class MultiChatScreen extends StatefulWidget {
  const MultiChatScreen({super.key});

  @override
  State<MultiChatScreen> createState() => _MultiChatScreenState();
}

class _MultiChatScreenState extends State<MultiChatScreen> {
  final List<AgentChat> _chats = [];
  String? _activeChatId;
  String? _currentProjectPath;
  double _sidebarWidth = 250.0;

  String? _lastProjectPath; // Para detectar cambios

  @override
  void initState() {
    super.initState();
    _loadProjectAndChats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Verificar si el proyecto cambió cuando se vuelve a esta pantalla
    _checkProjectChange();
  }

  Future<void> _checkProjectChange() async {
    final currentProjectPath = await ProjectService.getProjectPath();
    if (currentProjectPath != _lastProjectPath) {
      print('🔄 Proyecto cambió en MultiChatScreen. Recargando...');
      _lastProjectPath = currentProjectPath;
      await _loadProjectAndChats();
    }
  }

  Future<void> _loadProjectAndChats() async {
    final projectPath = await ProjectService.getProjectPath();
    print('📁 MultiChatScreen: Cargando proyecto: $projectPath');
    
    setState(() {
      _currentProjectPath = projectPath;
      _lastProjectPath = projectPath;
    });
    
    if (projectPath != null) {
      await _loadChatsForProject(projectPath);
    } else {
      // Si no hay proyecto, crear uno nuevo
      _createNewChat();
    }
  }

  Future<void> _loadChatsForProject(String projectPath) async {
    print('📁 Cargando chats para proyecto: $projectPath');
    final allChats = await ChatStorageService.loadAgentChats();
    print('📁 Total de chats en almacenamiento: ${allChats.length}');
    
    // Filtrar chats por proyecto - normalizar rutas para comparación
    final projectChats = allChats.where((chat) {
      final chatPath = chat.projectPath ?? '';
      final normalizedChatPath = chatPath.replaceAll('\\', '/');
      final normalizedProjectPath = projectPath.replaceAll('\\', '/');
      final matches = normalizedChatPath == normalizedProjectPath;
      if (matches) {
        print('✅ Chat "${chat.name}" pertenece a este proyecto');
      }
      return matches;
    }).toList();
    
    print('📁 Chats encontrados para este proyecto: ${projectChats.length}');
    
    // Ordenar por última actualización (más reciente primero)
    projectChats.sort((a, b) {
      final aTime = a.lastUpdated ?? a.createdAt;
      final bTime = b.lastUpdated ?? b.createdAt;
      return bTime.compareTo(aTime);
    });
    
    setState(() {
      _chats.clear();
      _chats.addAll(projectChats);
      
      if (_chats.isEmpty) {
        print('📁 No hay chats para este proyecto, creando uno nuevo...');
        _createNewChat();
      } else {
        // Activar el chat más reciente (primero en la lista)
        print('📁 Activando chat más reciente: ${_chats.first.name} (${_chats.first.id})');
        _chats.first.isActive = true;
        _activeChatId = _chats.first.id;
      }
    });
  }

  Future<void> _changeProject() async {
    // Navegar a WelcomeScreen para cambiar de proyecto
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const WelcomeScreen(),
      ),
    );
  }

  Future<void> _createNewChat() async {
    final newChat = AgentChat(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Agente ${_chats.length + 1}',
      messages: [],
      createdAt: DateTime.now(),
      projectPath: _currentProjectPath,
      isActive: true,
    );

    setState(() {
      // Desactivar todos los chats anteriores
      for (var chat in _chats) {
        chat.isActive = false;
      }
      _chats.add(newChat);
      _activeChatId = newChat.id;
    });
    
    // Guardar el chat
    await ChatStorageService.saveAgentChat(newChat);
  }

  void _switchChat(String chatId) {
    setState(() {
      for (var chat in _chats) {
        chat.isActive = chat.id == chatId;
      }
      _activeChatId = chatId;
    });
  }

  Future<void> _deleteChat(String chatId) async {
    if (_chats.length <= 1) {
      // No permitir eliminar el último chat
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe haber al menos un chat'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _chats.removeWhere((chat) => chat.id == chatId);
      
      // Si se eliminó el chat activo, activar otro
      if (_activeChatId == chatId) {
        _chats.first.isActive = true;
        _activeChatId = _chats.first.id;
      }
    });

    // Eliminar de almacenamiento
    final allChats = await ChatStorageService.loadAgentChats();
    allChats.removeWhere((chat) => chat.id == chatId);
    await ChatStorageService.saveAgentChats(allChats);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CursorTheme.background,
      appBar: AppBar(
        backgroundColor: CursorTheme.surface,
        elevation: 0,
        title: Text(
          _currentProjectPath != null
              ? 'Proyecto: ${_currentProjectPath!.split('/').last}'
              : 'Lopez Code',
          style: const TextStyle(
            color: CursorTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18, color: CursorTheme.textPrimary),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _changeProject,
            tooltip: 'Cambiar Proyecto',
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18, color: CursorTheme.primary),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _createNewChat,
            tooltip: 'Nuevo Agente',
          ),
        ],
      ),
      body: Row(
        children: [
          // Panel lateral con lista de chats (redimensionable)
          Container(
            width: _sidebarWidth,
            decoration: BoxDecoration(
              color: CursorTheme.explorerBackground,
              border: Border(
                right: BorderSide(color: CursorTheme.border, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CursorTheme.surface,
                    border: Border(
                      bottom: BorderSide(color: CursorTheme.border, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Agentes',
                        style: TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_chats.length}',
                        style: const TextStyle(
                          color: CursorTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Botón + para agregar nuevo agente
                      IconButton(
                        icon: const Icon(Icons.add, size: 18, color: CursorTheme.primary),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: _createNewChat,
                        tooltip: 'Nuevo Agente',
                      ),
                    ],
                  ),
                ),
                // Lista de chats
                Expanded(
                  child: _chats.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 32,
                                color: CursorTheme.textSecondary,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No hay chats',
                                style: TextStyle(
                                  color: CursorTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _chats.length,
                          itemBuilder: (context, index) {
                            final chat = _chats[index];
                            final isActive = chat.id == _activeChatId;
                            
                            return Dismissible(
                              key: Key(chat.id),
                              direction: _chats.length > 1
                                  ? DismissDirection.endToStart
                                  : DismissDirection.none,
                              onDismissed: (direction) {
                                _deleteChat(chat.id);
                              },
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete, color: Colors.white, size: 18),
                              ),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? CursorTheme.explorerItemSelected
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: ListTile(
                                  dense: true,
                                  selected: isActive,
                                  selectedTileColor: Colors.transparent,
                                  title: Text(
                                    chat.name,
                                    style: TextStyle(
                                      color: isActive
                                          ? CursorTheme.textPrimary
                                          : CursorTheme.textSecondary,
                                      fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${chat.messages.length} mensajes',
                                    style: TextStyle(
                                      color: isActive
                                          ? CursorTheme.textSecondary
                                          : CursorTheme.textDisabled,
                                      fontSize: 11,
                                    ),
                                  ),
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: isActive
                                        ? CursorTheme.primary
                                        : CursorTheme.surface,
                                    child: Icon(
                                      Icons.smart_toy,
                                      color: isActive
                                          ? Colors.white
                                          : CursorTheme.textSecondary,
                                      size: 14,
                                    ),
                                  ),
                                  onTap: () => _switchChat(chat.id),
                                  trailing: _chats.length > 1
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 14),
                                          color: CursorTheme.textSecondary,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _deleteChat(chat.id),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          // Divisor redimensionable
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _sidebarWidth += details.delta.dx;
                // Límites: mínimo 150, máximo 400
                if (_sidebarWidth < 150) _sidebarWidth = 150;
                if (_sidebarWidth > 400) _sidebarWidth = 400;
              });
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: Container(
                width: 4,
                color: CursorTheme.border,
                child: Center(
                  child: Container(
                    width: 1,
                    color: CursorTheme.textDisabled,
                  ),
                ),
              ),
            ),
          ),
          // Chat activo
          Expanded(
            child: _activeChatId != null && _chats.isNotEmpty && _currentProjectPath != null
                ? ChatScreen(
                    key: ValueKey('${_activeChatId}_${_currentProjectPath}'), // Incluir projectPath en la key para forzar rebuild
                    chatId: _activeChatId!,
                    projectPath: _currentProjectPath,
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 48,
                          color: CursorTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No hay chats activos',
                          style: TextStyle(
                            color: CursorTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _createNewChat,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Crear nuevo agente'),
                          style: TextButton.styleFrom(
                            foregroundColor: CursorTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () {
                            // Volver a WelcomeScreen
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                              (route) => false,
                            );
                          },
                          icon: const Icon(Icons.home, size: 16),
                          label: const Text('Volver a inicio'),
                          style: TextButton.styleFrom(
                            foregroundColor: CursorTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
