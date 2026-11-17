import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/code_indexing_service.dart';
import '../services/vector_database_service.dart';
import '../services/project_service.dart';
import 'auth/login_screen.dart';
import 'git_settings_screen.dart';
import '../widgets/app_toast.dart';
import '../widgets/cursor_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _rulesController = TextEditingController();
  final TextEditingController _behaviorController = TextEditingController();
  bool _isSaving = false;
  String _selectedModel = SettingsService.defaultModel;
  
  // Indexación de código
  bool _isIndexing = false;
  double _indexingProgress = 0.0;
  String _indexingStatus = '';
  DatabaseStats? _dbStats;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final rules = await SettingsService.getSystemRules();
    final behavior = await SettingsService.getSystemBehavior();
    final model = await SettingsService.getSelectedModel();

    setState(() {
      _rulesController.text = rules;
      _behaviorController.text = behavior;
      _selectedModel = model;
    });
    
    // Cargar estadísticas de indexación
    await _loadIndexStats();
  }
  
  Future<void> _loadIndexStats() async {
    try {
      final stats = await VectorDatabaseService.getStats();
      if (mounted) {
        setState(() {
          _dbStats = stats;
        });
      }
    } catch (e) {
      print('⚠️ Error al cargar estadísticas: $e');
    }
  }
  
  Future<void> _indexProject() async {
    try {
      final projectPath = await ProjectService.getProjectPath();
      
      if (projectPath == null || projectPath.isEmpty) {
        if (mounted) {
          AppToast.warning(context, '⚠️ No hay proyecto cargado');
        }
        return;
      }
      
      setState(() {
        _isIndexing = true;
        _indexingProgress = 0.0;
        _indexingStatus = 'Iniciando indexación...';
      });
      
      // Indexar proyecto
      final result = await CodeIndexingService.indexProject(projectPath);
      
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexingProgress = 1.0;
          _indexingStatus = 'Indexación completada';
        });
        
        // Recargar estadísticas
        await _loadIndexStats();
        
        // Mostrar resultado
        if (result.success) {
          AppToast.success(
            context,
            'Proyecto indexado: ${result.filesProcessed} archivos, '
            '${result.embeddingsCreated} embeddings '
            '(${result.duration.inSeconds}s)',
          );
        } else {
          AppToast.warning(
            context,
            'Indexación con errores: ${result.filesProcessed} procesados, '
            '${result.errors} errores',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexingStatus = 'Error';
        });
        
        AppToast.error(context, '❌ Error al indexar: $e');
      }
    }
  }
  
  Future<void> _clearIndex() async {
    try {
      await VectorDatabaseService.clearDatabase();
      await _loadIndexStats();
      
      if (mounted) {
        AppToast.success(context, '✅ Índice limpiado correctamente');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, '❌ Error al limpiar índice: $e');
      }
    }
  }

  Future<void> _saveRules() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await SettingsService.saveSystemRules(_rulesController.text);
      
      setState(() {
        _isSaving = false;
      });

      AppToast.success(context, '✅ Reglas guardadas correctamente');
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      AppToast.error(context, 'Error al guardar: $e');
    }
  }

  Future<void> _saveBehavior() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await SettingsService.saveSystemBehavior(_behaviorController.text);
      
      setState(() {
        _isSaving = false;
      });

      AppToast.success(context, '✅ Comportamiento guardado correctamente');
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      AppToast.error(context, 'Error al guardar: $e');
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _confirmDeleteAccount() async {
    final passwordController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D30),
        title: const Text(
          'Eliminar cuenta',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esta acción es permanente. Confirma con tu contraseña.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF3C3C3C),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      passwordController.dispose();
      return;
    }
    try {
      await AuthService.instance.deleteAccount(
        password: passwordController.text,
      );
      passwordController.dispose();
      if (!mounted) return;
      AppToast.success(context, 'Cuenta eliminada');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      passwordController.dispose();
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  void dispose() {
    _rulesController.dispose();
    _behaviorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252526),
        title: const Text(
          'Configuración',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isSaving
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                // Columna centrada — sin estirar de lado a lado en pantallas anchas.
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  children: [
                // Cuenta del usuario (Firebase / local)
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: AnimatedBuilder(
                      animation: AuthService.instance,
                      builder: (context, _) {
                        final user = AuthService.instance.currentUser;
                        final signedIn = user != null;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_outline, color: Colors.white70),
                                SizedBox(width: 8),
                                Text(
                                  'Tu cuenta',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              signedIn ? user.email : 'Modo anónimo',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              signedIn
                                  ? (AuthService.instance.usesFirebase
                                      ? 'Firebase Auth · puedes recargar billetera'
                                      : 'Cuenta local · puedes recargar billetera')
                                  : 'Puedes usar la app sin cuenta. '
                                      'Inicia sesión para agregar saldo. '
                                      'Sin saldo el agente no funciona.',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (!signedIn)
                                  TextButton.icon(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const LoginScreen(
                                            popOnSuccess: true,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.login, size: 16),
                                    label: const Text('Iniciar sesión'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: CursorTheme.primary,
                                    ),
                                  )
                                else ...[
                                  TextButton.icon(
                                    onPressed: () async {
                                      await AuthService.instance.signOut();
                                      if (!context.mounted) return;
                                      // Sigue en la app como anónimo.
                                    },
                                    icon: const Icon(Icons.logout, size: 16),
                                    label: const Text('Cerrar sesión'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: const Color(0xFF3C3C3C),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: _confirmDeleteAccount,
                                    icon: const Icon(
                                      Icons.delete_forever,
                                      size: 16,
                                    ),
                                    label: const Text('Eliminar cuenta'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: const Color(0xFF8B1E1E),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Model Selection Section
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.smart_toy, color: Colors.white70),
                            const SizedBox(width: 8),
                            const Text(
                              'Modelo de IA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedModel,
                          decoration: const InputDecoration(
                            labelText: 'Seleccionar Modelo',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFF3C3C3C),
                            labelStyle: TextStyle(color: Colors.white70),
                          ),
                          dropdownColor: const Color(0xFF3C3C3C),
                          style: const TextStyle(color: Colors.white),
                          items: const [
                            DropdownMenuItem(value: 'gpt-4o', child: Text('GPT-4o (Por defecto / Agente)')),
                            DropdownMenuItem(value: 'gpt-4.1', child: Text('GPT-4.1 (Agéntico superior)')),
                            DropdownMenuItem(value: 'o4-mini', child: Text('o4-mini (Razonamiento rápido)')),
                            DropdownMenuItem(value: 'gpt-4o-mini', child: Text('GPT-4o Mini (Bajo Costo)')),
                            DropdownMenuItem(value: 'gpt-4-turbo', child: Text('GPT-4 Turbo')),
                            DropdownMenuItem(value: 'gpt-4', child: Text('GPT-4')),
                            DropdownMenuItem(value: 'gpt-3.5-turbo', child: Text('GPT-3.5 Turbo')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedModel = value;
                              });
                              SettingsService.saveSelectedModel(value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'GPT-4o (default): mejor para el Agent Loop (multi-paso, run/debug).\n'
                          'GPT-4.1 / o4-mini: alternativas de razonamiento agéntico.\n'
                          'GPT-4o Mini: más económico para tareas simples.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                
                // Code Indexing Section (como Cursor)
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.code, color: Colors.white70),
                            const SizedBox(width: 8),
                            const Text(
                              'Indexación de Código (RAG)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Indexa tu proyecto para que la IA pueda buscar código relevante automáticamente (como Cursor)',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Estadísticas de indexación
                        if (_dbStats != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3C3C3C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '📊 Estadísticas',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildStatRow('Archivos indexados', '${_dbStats!.uniqueFiles}'),
                                _buildStatRow('Embeddings creados', '${_dbStats!.totalEmbeddings}'),
                                if (_dbStats!.languageDistribution.isNotEmpty)
                                  ...(_dbStats!.languageDistribution.entries.map((e) =>
                                    _buildStatRow('  ${e.key}', '${e.value} fragmentos')
                                  )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        
                        // Progress bar (cuando está indexando)
                        if (_isIndexing) ...[
                          LinearProgressIndicator(
                            value: _indexingProgress > 0 ? _indexingProgress : null,
                            backgroundColor: const Color(0xFF3C3C3C),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF007ACC)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _indexingStatus,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Botones de indexación
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isIndexing ? null : _indexProject,
                              icon: _isIndexing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: Text(_isIndexing ? 'Indexando...' : 'Indexar Proyecto'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF007ACC),
                                foregroundColor: Colors.white,
                              ),
                            ),
                            if (_dbStats != null && _dbStats!.totalEmbeddings > 0)
                              OutlinedButton.icon(
                                onPressed: _isIndexing ? null : _clearIndex,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Limpiar Índice'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                              ),
                          ],
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Información adicional
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007ACC).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF007ACC).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFF007ACC), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Primera vez: puede tardar 1-15 minutos según el tamaño del proyecto. '
                                  'Después solo se reindexan archivos modificados.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // System Rules Section
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.rule, color: Colors.white70),
                            const SizedBox(width: 8),
            const Text(
                              'Reglas del Sistema',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
            ),
            const SizedBox(height: 8),
            const Text(
                          'Estas reglas son OBLIGATORIAS. La IA NO puede violarlas bajo ninguna circunstancia.',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
            ),
            const SizedBox(height: 16),
                        TextField(
                controller: _rulesController,
                          decoration: const InputDecoration(
                            labelText: 'Reglas (una por línea)',
                            hintText: 'Ejemplo:\n- No puedes acceder a archivos del sistema\n- Siempre pregunta antes de modificar código crítico',
                            border: OutlineInputBorder(),
                  filled: true,
                            fillColor: Color(0xFF3C3C3C),
                          ),
                          maxLines: 10,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _saveRules,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar Reglas'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007ACC),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                ),
                  ),
                ),

                const SizedBox(height: 16),

                // System Behavior Section
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.psychology, color: Colors.white70),
                            const SizedBox(width: 8),
                            const Text(
                              'Comportamiento y Forma de Ser',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
              ),
                          ],
            ),
                        const SizedBox(height: 8),
                        const Text(
                          'Define cómo debe comportarse la IA. Esta configuración se aplica a todas las respuestas.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _behaviorController,
                          decoration: const InputDecoration(
                            labelText: 'Comportamiento',
                            hintText: 'Ejemplo:\nEres un asistente de desarrollo profesional. Siempre proporcionas código limpio y bien documentado. Eres amigable pero directo.',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFF3C3C3C),
                          ),
                          maxLines: 10,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _saveBehavior,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar Comportamiento'),
                style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007ACC),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Git Configuration Section
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.storage, color: Colors.white70),
                            const SizedBox(width: 8),
                            const Text(
                              'Configuración de Git',
                              style: TextStyle(
                          color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                        ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Conecta tu proyecto con un repositorio Git y haz commit/push desde aquí.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const GitSettingsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.settings),
                          label: const Text('Configurar Git'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007ACC),
                            foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
                ),

                const SizedBox(height: 16),

                // Permissions Section
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.security, color: Colors.white70),
                            const SizedBox(width: 8),
                            const Text(
                              'Permisos del Sistema',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Para que la app funcione correctamente, necesita los siguientes permisos:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        _PermissionItem(
                          icon: Icons.folder,
                          title: 'Acceso a Archivos',
                          description: 'Para leer y editar archivos de código',
                          onRequest: () {
                            // macOS pedirá permisos automáticamente
        AppToast.info(context, 'Los permisos se solicitarán automáticamente cuando uses la función de archivos');
                          },
                        ),
                        const SizedBox(height: 8),
                        _PermissionItem(
                          icon: Icons.network_check,
                          title: 'Conexión de Red',
                          description: 'Para comunicarse con la API de OpenAI',
                          onRequest: () {
        AppToast.info(context, 'Ve a: Configuración del Sistema → Red → Firewall\nY permite conexiones para esta app');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onRequest;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onRequest,
          child: const Text('Solicitar'),
        ),
      ],
    );
  }
}
