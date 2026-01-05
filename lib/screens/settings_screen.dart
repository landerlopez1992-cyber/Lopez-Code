import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/settings_service.dart';
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
                          'Nota: GPT-4o es el más reciente y recomendado. Soporta análisis de imágenes.',
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
