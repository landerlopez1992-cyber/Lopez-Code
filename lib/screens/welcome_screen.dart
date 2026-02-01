import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/project_service.dart';
import '../services/native_file_picker.dart';
import '../services/repository_service.dart';
import '../services/permission_service.dart';
import '../services/run_debug_service.dart';
import '../widgets/cursor_theme.dart';
import 'multi_chat_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  List<String> _recentProjects = [];

  @override
  void initState() {
    super.initState();
    _loadRecentProjects();
  }

  Future<void> _loadRecentProjects() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentProjects = prefs.getStringList('recent_projects') ?? [];
      // Filtrar proyectos que no existen
      _recentProjects = _recentProjects.where((path) => Directory(path).existsSync()).toList();
    });
  }

  Future<void> _saveRecentProject(String projectPath) async {
    final prefs = await SharedPreferences.getInstance();
    _recentProjects.remove(projectPath);
    _recentProjects.insert(0, projectPath);
    if (_recentProjects.length > 10) {
      _recentProjects = _recentProjects.sublist(0, 10);
    }
    await prefs.setStringList('recent_projects', _recentProjects);
  }

  Future<void> _openProject() async {
    // Verificar permisos antes de abrir proyecto
    final hasPermissions = await PermissionService.checkFileAccess();
    if (!hasPermissions) {
      final granted = await PermissionService.requestFilePermission(context);
      if (!granted) {
        // Si no se otorgaron permisos, no continuar
        return;
      }
    }

    bool dialogShown = false;
    try {
      // Mostrar indicador de carga
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(CursorTheme.primary),
            ),
          ),
        );
        dialogShown = true;
      }

      // Intentar abrir el diálogo de selección
      String? result;
      
      // PRIMERO intentar con file_picker (más confiable en Flutter)
      print('🔍 Intentando con file_picker primero...');
      try {
        result = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Seleccionar Directorio del Proyecto',
        ).timeout(
          const Duration(seconds: 30), // Aumentado a 30 segundos
          onTimeout: () {
            print('⏱️ Timeout en file_picker después de 30 segundos');
            return null;
          },
        );
        
        if (result != null && result.isNotEmpty) {
          print('✅ file_picker funcionó correctamente: $result');
          
          // Verificar que el directorio existe
          final dir = Directory(result);
          if (await dir.exists()) {
            print('✅ El directorio existe y es válido');
          } else {
            print('❌ El directorio no existe: $result');
            result = null;
          }
        } else {
          print('⚠️ file_picker retornó null o vacío');
        }
      } catch (e, stackTrace) {
        print('❌ file_picker falló con error: $e');
        print('Stack trace: $stackTrace');
        result = null;
      }
      
      // Si file_picker no funcionó, intentar con diálogo nativo como fallback
      if (result == null || result.isEmpty) {
        print('🔄 file_picker no funcionó, intentando diálogo nativo de macOS...');
        try {
          result = await NativeFilePicker.selectDirectory().timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              print('⏱️ Timeout en diálogo nativo después de 60 segundos');
              return null;
            },
          );
          
          if (result != null && result.isNotEmpty) {
            print('✅ Diálogo nativo funcionó: $result');
            
            // Verificar que el directorio existe
            final dir = Directory(result);
            if (await dir.exists()) {
              print('✅ El directorio existe y es válido');
            } else {
              print('❌ El directorio no existe: $result');
              result = null;
            }
          } else {
            print('⚠️ Diálogo nativo retornó null o vacío');
          }
        } catch (e, stackTrace) {
          print('❌ Error al abrir diálogo nativo: $e');
          print('Stack trace: $stackTrace');
          result = null;
        }
      }
      
      print('📋 Resultado final de selección: ${result ?? "null"}');

      // Cerrar indicador de carga
      if (mounted && dialogShown) {
        Navigator.of(context).pop();
        dialogShown = false;
      }

      if (result != null && result.isNotEmpty) {
        print('✅ Path seleccionado: $result');
        
        // Verificar si es un proyecto Flutter (solo para logging, no bloquea)
        final isFlutter = await ProjectService.isFlutterProject(result);
        if (isFlutter) {
          final projectName = await ProjectService.getProjectName(result);
          print('✅ Proyecto Flutter detectado');
          print('   Nombre: ${projectName ?? "N/A"}');
        } else {
          print('ℹ️ Proyecto no-Flutter detectado (permitido - editor de código)');
        }
        print('   Ruta: $result');
        
        print('📁 Guardando proyecto...');
        
        // ✅ FIX: Limpiar servicios antes de cambiar de proyecto (evita cuelgues)
        print('🧹 Limpiando servicios del proyecto anterior...');
        await RunDebugService.cleanup();
        
        await ProjectService.saveProjectPath(result);
        
        // Verificar que se guardó correctamente
        final savedPath = await ProjectService.getProjectPath();
        print('✅ Proyecto guardado en ProjectService: $savedPath');
        
        if (savedPath == null || savedPath.isEmpty) {
          print('❌ ERROR: El proyecto no se guardó correctamente');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: No se pudo guardar el proyecto'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        
        await _saveRecentProject(result);
        print('✅ Proyecto agregado a recientes');
        
        if (mounted) {
          print('🚀 Navegando a MultiChatScreen...');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MultiChatScreen()),
          );
        }
      } else if (mounted) {
        // Usuario canceló o no seleccionó nada
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se seleccionó ningún proyecto'),
            duration: Duration(seconds: 2),
            backgroundColor: CursorTheme.textSecondary,
          ),
        );
      }
    } catch (e) {
      // Cerrar indicador de carga si está abierto
      if (mounted && dialogShown) {
        try {
          Navigator.of(context).pop();
        } catch (_) {
          // Ignorar si ya está cerrado
        }
      }

      if (mounted) {
        String errorMessage = 'Error al seleccionar proyecto: $e';
        String detailedMessage = errorMessage;
        
        // Mensajes más específicos según el tipo de error
        if (e.toString().contains('Permission') || e.toString().contains('permission')) {
          detailedMessage = '''Error de permisos: macOS necesita permisos para acceder a archivos.

Solución:
1. Ve a Preferencias del Sistema > Seguridad y Privacidad
2. Busca "Lopez Code" en la lista
3. Otorga permisos de acceso a archivos y carpetas

Error original: $e''';
        } else if (e.toString().contains('Timeout')) {
          detailedMessage = '''El diálogo de selección tardó demasiado.

Posibles causas:
- Permisos de macOS no otorgados
- Problema con file_picker

Error original: $e''';
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error al abrir proyecto'),
            content: SingleChildScrollView(
              child: Text(detailedMessage),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openProject();
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _cloneRepository() async {
    final repoUrlController = TextEditingController();
    final targetPathController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CursorTheme.surface,
        title: const Text(
          'Clonar Repositorio',
          style: TextStyle(color: CursorTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repoUrlController,
              decoration: const InputDecoration(
                labelText: 'URL del Repositorio',
                hintText: 'https://github.com/usuario/repo.git',
                labelStyle: TextStyle(color: CursorTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: CursorTheme.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: CursorTheme.primary),
                ),
              ),
              style: const TextStyle(color: CursorTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: targetPathController,
              decoration: const InputDecoration(
                labelText: 'Ruta de destino (opcional)',
                hintText: '/Users/usuario/Desktop/Proyectos',
                labelStyle: TextStyle(color: CursorTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: CursorTheme.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: CursorTheme.primary),
                ),
              ),
              style: const TextStyle(color: CursorTheme.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: CursorTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: CursorTheme.primary,
            ),
            child: const Text('Clonar'),
          ),
        ],
      ),
    );

    if (result == true && repoUrlController.text.trim().isNotEmpty) {
      final repoUrl = repoUrlController.text.trim();
      String targetPath = targetPathController.text.trim();
      
      if (targetPath.isEmpty) {
        targetPath = '${Platform.environment['HOME']}/Desktop/Proyectos/${repoUrl.split('/').last.replaceAll('.git', '')}';
      }

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        final cloneResult = await RepositoryService.cloneRepository(repoUrl, targetPath);
        
        if (mounted) {
          Navigator.of(context).pop(); // Cerrar indicador de carga
          
          if (cloneResult['success'] == true) {
            // Verificar si es Flutter (solo para logging, no bloquea)
            final isFlutter = await ProjectService.isFlutterProject(targetPath);
            if (isFlutter) {
              final projectName = await ProjectService.getProjectName(targetPath);
              print('✅ Proyecto Flutter detectado');
              print('   Nombre: ${projectName ?? "N/A"}');
            } else {
              print('ℹ️ Repositorio no-Flutter clonado (permitido - editor de código)');
            }
            print('   Ruta: $targetPath');
            
            await ProjectService.saveProjectPath(targetPath);
            await _saveRecentProject(targetPath);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ ${cloneResult['message']}'),
                backgroundColor: Colors.green,
              ),
            );
            
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const MultiChatScreen()),
              );
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Error: ${cloneResult['error']}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Cerrar indicador de carga
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _openRecentProject(String projectPath) async {
    // Verificar permisos antes de abrir proyecto
    final hasPermissions = await PermissionService.checkFileAccess();
    if (!hasPermissions) {
      final granted = await PermissionService.requestFilePermission(context);
      if (!granted) {
        // Si no se otorgaron permisos, no continuar
        return;
      }
    }

    // Normalizar el path - eliminar barra final si existe
    final normalizedPath = projectPath.endsWith('/') 
        ? projectPath.substring(0, projectPath.length - 1)
        : projectPath;
    
    // Verificar que el directorio existe
    if (!Directory(normalizedPath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El proyecto "$projectPath" no existe'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        // Eliminar del historial
        setState(() {
          _recentProjects.remove(projectPath);
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('recent_projects', _recentProjects);
      }
      return;
    }
    
    // Verificar si es Flutter (solo para logging, no bloquea)
    final isFlutter = await ProjectService.isFlutterProject(normalizedPath);
    if (isFlutter) {
      print('✅ Proyecto Flutter detectado');
    } else {
      print('ℹ️ Proyecto no-Flutter (permitido - editor de código)');
    }
    
    print('📁 Abriendo proyecto reciente: $normalizedPath');
    
    // ✅ FIX: Limpiar servicios antes de cambiar de proyecto (evita cuelgues)
    print('🧹 Limpiando servicios del proyecto anterior...');
    await RunDebugService.cleanup();
    
    await ProjectService.saveProjectPath(normalizedPath);
    await _saveRecentProject(normalizedPath);
    
    // Verificar que se guardó correctamente
    final savedPath = await ProjectService.getProjectPath();
    print('✅ Proyecto guardado: $savedPath');
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MultiChatScreen()),
      );
    }
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CursorTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CursorTheme.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: CursorTheme.textPrimary),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CursorTheme.background,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, // ✅ FIX: Evita altura infinita
            children: [
              // Logo y título - Logo de chevrones azules
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chevron_left,
                    size: 48,
                    color: CursorTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 48,
                    color: CursorTheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'LOPEZ CODE',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pro · Settings',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 48),
              
              // Acciones principales
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: _buildActionCard(
                      icon: Icons.folder_open,
                      title: 'Open project',
                      onTap: _openProject,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildActionCard(
                      icon: Icons.cloud_download,
                      title: 'Clone repo',
                      onTap: _cloneRepository,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildActionCard(
                      icon: Icons.terminal,
                      title: 'Connect via SSH',
                      onTap: () {
                        // TODO: Implementar SSH
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Función en desarrollo'),
                            backgroundColor: CursorTheme.primary,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              
              // Proyectos recientes
              if (_recentProjects.isNotEmpty) ...[
                const SizedBox(height: 48),
                Row(
                  children: [
                    const Text(
                      'Recent projects',
                      style: TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_recentProjects.length} proyecto${_recentProjects.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: CursorTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: CursorTheme.border, width: 1),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _recentProjects.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      color: CursorTheme.border,
                    ),
                    itemBuilder: (context, index) {
                      final projectPath = _recentProjects[index];
                      final projectName = projectPath.split('/').last;
                      final projectDir = projectPath.split('/').sublist(0, projectPath.split('/').length - 1).join('/');
                      
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.folder,
                          color: CursorTheme.textSecondary,
                          size: 20,
                        ),
                        title: Text(
                          projectName,
                          style: const TextStyle(
                            color: CursorTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          projectDir,
                          style: const TextStyle(
                            color: CursorTheme.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openRecentProject(projectPath),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Botón para eliminar del historial
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: CursorTheme.textSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Eliminar del historial',
                              onPressed: () async {
                                setState(() {
                                  _recentProjects.remove(projectPath);
                                });
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setStringList('recent_projects', _recentProjects);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Proyecto "$projectName" eliminado del historial'),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: CursorTheme.primary,
                                    ),
                                  );
                                }
                              },
                            ),
                            // Botón para cerrar (ocultar)
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              color: CursorTheme.textSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Ocultar',
                              onPressed: () async {
                                setState(() {
                                  _recentProjects.remove(projectPath);
                                });
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setStringList('recent_projects', _recentProjects);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

