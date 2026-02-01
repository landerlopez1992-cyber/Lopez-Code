import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
import '../services/code_indexing_service.dart';
import '../services/vector_database_service.dart';
import '../services/project_service.dart';
import 'git_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _rulesController = TextEditingController();
  final TextEditingController _behaviorController = TextEditingController();
  bool _isSaving = false;
  bool _apiKeySaved = false;
  bool _showApiKey = false;
  String _selectedModel = 'gpt-4o';
  
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
    final apiKey = await SettingsService.getApiKey();
    final rules = await SettingsService.getSystemRules();
    final behavior = await SettingsService.getSystemBehavior();
    final model = await SettingsService.getSelectedModel();

    setState(() {
      _apiKeyController.text = apiKey ?? '';
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ No hay proyecto cargado'),
              backgroundColor: Colors.orange,
            ),
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Proyecto indexado:\n'
                '${result.filesProcessed} archivos procesados\n'
                '${result.embeddingsCreated} embeddings creados\n'
                'Tiempo: ${result.duration.inSeconds}s',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Indexación con errores:\n'
                '${result.filesProcessed} procesados, ${result.errors} errores',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIndexing = false;
          _indexingStatus = 'Error';
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al indexar: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  Future<void> _clearIndex() async {
    try {
      await VectorDatabaseService.clearDatabase();
      await _loadIndexStats();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Índice limpiado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al limpiar índice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveApiKey() async {
    if (_apiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa una API Key'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _apiKeySaved = false;
    });

    try {
      await SettingsService.saveApiKey(_apiKeyController.text.trim());
      
      // Verificar que se guardó
      final saved = await SettingsService.getApiKey();
      if (saved == _apiKeyController.text.trim()) {
        setState(() {
          _apiKeySaved = true;
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ API Key guardada correctamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Ocultar el check después de 2 segundos
        Future.delayed(const Duration(seconds: 2), () {
    if (mounted) {
            setState(() {
              _apiKeySaved = false;
            });
          }
        });
      } else {
        throw Exception('No se pudo verificar el guardado');
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Reglas guardadas correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Comportamiento guardado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copiado al portapapeles'),
        duration: Duration(seconds: 1),
      ),
    );
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
  
  @override
  void dispose() {
    _apiKeyController.dispose();
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // API Key Section
                Card(
                  color: const Color(0xFF2D2D30),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                        Row(
                          children: [
                            const Icon(Icons.key, color: Colors.white70),
                            const SizedBox(width: 8),
            const Text(
                              'API Key de OpenAI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_apiKeySaved) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.check_circle, color: Colors.green),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _apiKeyController,
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-...',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: const Color(0xFF3C3C3C),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showApiKey ? Icons.visibility_off : Icons.visibility,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showApiKey = !_showApiKey;
                                });
                              },
                              tooltip: _showApiKey ? 'Ocultar' : 'Mostrar',
                            ),
                          ),
                          obscureText: !_showApiKey,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _saveApiKey,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar API Key'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: const Color(0xFF007ACC),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            _copyToClipboard('https://platform.openai.com/api-keys');
                          },
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text(
                            'Obtener API Key',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                          ),
            ),
                      ],
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
                            DropdownMenuItem(value: 'gpt-4o-mini', child: Text('GPT-4o Mini (Bajo Costo)')),
                            DropdownMenuItem(value: 'gpt-4o', child: Text('GPT-4o (Recomendado)')),
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
                          'GPT-4o Mini: Muy económico (~\$0.15/millón tokens). Recomendado para uso frecuente.\nGPT-4o: El más reciente y potente. Soporta análisis de imágenes.',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () {
                            // Abrir dashboard de uso de OpenAI
                            Clipboard.setData(const ClipboardData(text: 'https://platform.openai.com/usage'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('URL copiada. Ve a platform.openai.com/usage para verificar tu uso y facturación'),
                                duration: Duration(seconds: 4),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Verificar uso y facturación: platform.openai.com/usage',
                                  style: TextStyle(
                                    color: Colors.blue[300],
                                    fontSize: 11,
                                    decoration: TextDecoration.underline,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
                                content: Text(
                                  'Los permisos se solicitarán automáticamente cuando uses la función de archivos',
                                ),
          ),
        );
                          },
                        ),
                        const SizedBox(height: 8),
                        _PermissionItem(
                          icon: Icons.network_check,
                          title: 'Conexión de Red',
                          description: 'Para comunicarse con la API de OpenAI',
                          onRequest: () {
        ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Ve a: Configuración del Sistema → Red → Firewall\nY permite conexiones para esta app',
                                ),
                                duration: Duration(seconds: 4),
          ),
        );
                          },
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
