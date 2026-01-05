import 'package:flutter/material.dart';
import '../services/git_service.dart';
import '../services/project_service.dart';

class GitSettingsScreen extends StatefulWidget {
  const GitSettingsScreen({super.key});

  @override
  State<GitSettingsScreen> createState() => _GitSettingsScreenState();
}

class _GitSettingsScreenState extends State<GitSettingsScreen> {
  final TextEditingController _repoUrlController = TextEditingController();
  final TextEditingController _branchController = TextEditingController();
  final TextEditingController _commitMessageController = TextEditingController();
  
  String? _projectPath;
  Map<String, dynamic>? _gitStatus;
  bool _isLoading = false;
  bool _isGitRepo = false;

  @override
  void initState() {
    super.initState();
    _loadGitConfig();
  }

  Future<void> _loadGitConfig() async {
    setState(() {
      _isLoading = true;
    });

    final projectPath = await ProjectService.getProjectPath();
    if (projectPath != null) {
      _projectPath = projectPath;
      
      final isRepo = await GitService.isGitRepository(projectPath);
      final config = await GitService.getGitConfig(projectPath);
      final status = await GitService.getGitStatus(projectPath);

      setState(() {
        _isGitRepo = isRepo;
        _repoUrlController.text = config?['repoUrl'] ?? '';
        _branchController.text = config?['branch'] ?? 'main';
        _gitStatus = status;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGitConfig() async {
    if (_projectPath == null) return;

    if (_repoUrlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa la URL del repositorio'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await GitService.saveGitConfig(
        projectPath: _projectPath!,
        repoUrl: _repoUrlController.text.trim(),
        branch: _branchController.text.trim().isEmpty 
            ? 'main' 
            : _branchController.text.trim(),
      );

      // Si no es un repo Git, inicializarlo
      if (!_isGitRepo) {
        await GitService.initGitRepository(_projectPath!);
      }

      // Agregar remoto si no existe
      try {
        await GitService.addRemote(
          projectPath: _projectPath!,
          remoteName: 'origin',
          remoteUrl: _repoUrlController.text.trim(),
        );
      } catch (e) {
        // El remoto ya existe, está bien
      }

      setState(() {
        _isLoading = false;
        _isGitRepo = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Configuración de Git guardada'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadGitConfig();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _doCommit() async {
    if (_projectPath == null) return;

    if (_commitMessageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa un mensaje de commit'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await GitService.commit(
        projectPath: _projectPath!,
        message: _commitMessageController.text.trim(),
      );

      setState(() {
        _isLoading = false;
        _commitMessageController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $result'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadGitConfig();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _doPush() async {
    if (_projectPath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await GitService.push(projectPath: _projectPath!);

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $result'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadGitConfig();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _branchController.dispose();
    _commitMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _projectPath == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E1E),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF252526),
        title: const Text(
          'Configuración de Git',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Información del proyecto
          Card(
            color: const Color(0xFF2D2D30),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder, color: Colors.white70),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _projectPath?.split('/').last ?? 'Sin proyecto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_projectPath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _projectPath!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Estado de Git
          if (_gitStatus != null)
            Card(
              color: const Color(0xFF2D2D30),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info, color: Colors.white70),
                        SizedBox(width: 8),
                        Text(
                          'Estado de Git',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _isGitRepo ? Icons.check_circle : Icons.cancel,
                          color: _isGitRepo ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isGitRepo ? 'Repositorio Git inicializado' : 'No es un repositorio Git',
                          style: TextStyle(
                            color: _isGitRepo ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    if (_gitStatus!['branch'] != null && _gitStatus!['branch'].toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Rama: ${_gitStatus!['branch']}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                    if (_gitStatus!['hasChanges'] == true) ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Hay cambios sin commitear',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Configuración del repositorio
          Card(
            color: const Color(0xFF2D2D30),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings, color: Colors.white70),
                      SizedBox(width: 8),
                      Text(
                        'Configuración del Repositorio',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _repoUrlController,
                    decoration: const InputDecoration(
                      labelText: 'URL del Repositorio',
                      hintText: 'https://github.com/usuario/repo.git',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF3C3C3C),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _branchController,
                    decoration: const InputDecoration(
                      labelText: 'Rama (Branch)',
                      hintText: 'main',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF3C3C3C),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveGitConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar Configuración'),
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

          // Commit y Push
          Card(
            color: const Color(0xFF2D2D30),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.code, color: Colors.white70),
                      SizedBox(width: 8),
                      Text(
                        'Commit y Push',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commitMessageController,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje de Commit',
                      hintText: 'Agregar nueva funcionalidad',
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Color(0xFF3C3C3C),
                    ),
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading || !_isGitRepo ? null : _doCommit,
                          icon: const Icon(Icons.commit),
                          label: const Text('Commit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading || !_isGitRepo ? null : _doPush,
                          icon: const Icon(Icons.upload),
                          label: const Text('Push'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF007ACC),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
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


