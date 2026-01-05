import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/project_service.dart';

class ProjectSelectionScreen extends StatelessWidget {
  const ProjectSelectionScreen({super.key});

  Future<void> _selectProject(BuildContext context) async {
    try {
      // Seleccionar directorio en macOS
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Selecciona la carpeta del proyecto',
      );

      if (result != null) {
        await ProjectService.saveProjectPath(result);
        
        if (context.mounted) {
          Navigator.of(context).pop(true); // Retornar true para indicar que se seleccionó
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar proyecto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: Card(
          color: const Color(0xFF2D2D30),
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 64,
                  color: Color(0xFF007ACC),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Selecciona tu Proyecto',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Selecciona la carpeta del proyecto donde la IA podrá leer, editar y crear archivos.\n\n'
                    'La IA solo tendrá acceso a los archivos dentro de esta carpeta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => _selectProject(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Seleccionar Carpeta del Proyecto'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007ACC),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


