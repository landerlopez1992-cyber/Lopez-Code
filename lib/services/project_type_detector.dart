import 'dart:io';
import 'dart:convert';

/// Servicio para detectar el tipo de proyecto automáticamente
/// Similar a Cursor IDE - detecta y ejecuta el comando correcto
class ProjectTypeDetector {
  /// Verifica si un puerto está en uso
  static Future<bool> isPortInUse(int port) async {
    try {
      final result = await Process.run(
        'lsof',
        ['-ti', ':$port'],
        runInShell: true,
      );
      return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
    } catch (e) {
      // Si lsof no está disponible, intentar con netstat
      try {
        final result = await Process.run(
          'netstat',
          ['-an'],
          runInShell: true,
        );
        final output = result.stdout.toString();
        return output.contains(':$port ') && output.contains('LISTEN');
      } catch (e2) {
        print('⚠️ No se pudo verificar el puerto $port: $e2');
        return false;
      }
    }
  }
  
  /// Encuentra un puerto disponible comenzando desde el puerto base
  static Future<int> findAvailablePort(int basePort) async {
    int port = basePort;
    int maxAttempts = 100; // Intentar hasta 100 puertos
    
    for (int i = 0; i < maxAttempts; i++) {
      if (!await isPortInUse(port)) {
        return port;
      }
      port++;
    }
    
    // Si no se encuentra ningún puerto disponible, retornar el base
    print('⚠️ No se encontró puerto disponible, usando: $basePort');
    return basePort;
  }
  
  /// Intenta terminar el proceso que está usando un puerto
  static Future<bool> killProcessOnPort(int port) async {
    try {
      final result = await Process.run(
        'lsof',
        ['-ti', ':$port'],
        runInShell: true,
      );
      
      if (result.exitCode == 0) {
        final pid = result.stdout.toString().trim();
        if (pid.isNotEmpty) {
          print('🛑 Terminando proceso $pid en puerto $port...');
          final killResult = await Process.run(
            'kill',
            ['-9', pid],
            runInShell: true,
          );
          if (killResult.exitCode == 0) {
            // Esperar un momento para que el puerto se libere
            await Future.delayed(const Duration(milliseconds: 500));
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('⚠️ Error al terminar proceso en puerto $port: $e');
      return false;
    }
  }
  /// Detecta el tipo de proyecto basándose en archivos clave
  static Future<ProjectType> detectProjectType(String projectPath) async {
    print('🔍 Detectando tipo de proyecto en: $projectPath');
    
    final projectDir = Directory(projectPath);
    if (!await projectDir.exists()) {
      print('❌ El directorio no existe');
      return ProjectType.unknown;
    }
    
    // 1. Flutter (pubspec.yaml con dependencia de Flutter)
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (await pubspecFile.exists()) {
      try {
        final content = await pubspecFile.readAsString();
        if (content.contains('flutter:') || content.contains('sdk: flutter')) {
          print('✅ Proyecto Flutter detectado');
          return ProjectType.flutter;
        }
      } catch (e) {
        print('⚠️ Error al leer pubspec.yaml: $e');
      }
    }
    
    // 2. Node.js / JavaScript / TypeScript
    final packageJsonFile = File('$projectPath/package.json');
    if (await packageJsonFile.exists()) {
      try {
        final content = await packageJsonFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        
        // Next.js
        final dependencies = (json['dependencies'] as Map<String, dynamic>?) ?? {};
        final devDependencies = (json['devDependencies'] as Map<String, dynamic>?) ?? {};
        final allDeps = {...dependencies, ...devDependencies};
        
        if (allDeps.containsKey('next')) {
          print('✅ Proyecto Next.js detectado');
          return ProjectType.nextjs;
        }
        
        // React
        if (allDeps.containsKey('react')) {
          print('✅ Proyecto React detectado');
          return ProjectType.react;
        }
        
        // Vue
        if (allDeps.containsKey('vue')) {
          print('✅ Proyecto Vue detectado');
          return ProjectType.vue;
        }
        
        // Vite
        if (allDeps.containsKey('vite')) {
          print('✅ Proyecto Vite detectado');
          return ProjectType.vite;
        }
        
        // Express
        if (allDeps.containsKey('express')) {
          print('✅ Proyecto Express (Node.js) detectado');
          return ProjectType.nodejs;
        }
        
        // Node.js genérico
        print('✅ Proyecto Node.js detectado');
        return ProjectType.nodejs;
      } catch (e) {
        print('⚠️ Error al leer package.json: $e');
      }
    }
    
    // 3. Django (buscar PRIMERO, antes de Python genérico)
    final commonSubdirs = ['', 'backend', 'src', 'app', 'server', 'api'];
    for (final subdir in commonSubdirs) {
      final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
      final manageFile = File('$basePath/manage.py');
      if (await manageFile.exists()) {
        print('✅ Proyecto Django detectado (encontrado: ${subdir.isEmpty ? 'manage.py' : '$subdir/manage.py'})');
        return ProjectType.django;
      }
    }
    
    // 4. FastAPI / Flask (buscar ANTES de Python genérico)
    for (final subdir in commonSubdirs) {
      final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
      final reqFile = File('$basePath/requirements.txt');
      if (await reqFile.exists()) {
        try {
          final content = await reqFile.readAsString();
          if (content.toLowerCase().contains('fastapi')) {
            print('✅ Proyecto FastAPI detectado (encontrado: ${subdir.isEmpty ? 'requirements.txt' : '$subdir/requirements.txt'})');
            return ProjectType.fastapi;
          }
          if (content.toLowerCase().contains('flask')) {
            print('✅ Proyecto Flask detectado (encontrado: ${subdir.isEmpty ? 'requirements.txt' : '$subdir/requirements.txt'})');
            return ProjectType.flask;
          }
        } catch (e) {
          print('⚠️ Error al leer requirements.txt: $e');
        }
      }
    }
    
    // 5. Python genérico (solo si no es Django/FastAPI/Flask)
    final pythonFiles = ['main.py', 'app.py', 'run.py', 'server.py', 'wsgi.py'];
    
    for (final subdir in commonSubdirs) {
      final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
      
      // Buscar archivos Python principales
      for (final fileName in pythonFiles) {
        final file = File('$basePath/$fileName');
        if (await file.exists()) {
          print('✅ Proyecto Python detectado (encontrado: ${subdir.isEmpty ? fileName : '$subdir/$fileName'})');
          return ProjectType.python;
        }
      }
      
      // Verificar requirements.txt o pyproject.toml (solo si no se detectó FastAPI/Flask antes)
      final requirementsFile = File('$basePath/requirements.txt');
      final pyprojectFile = File('$basePath/pyproject.toml');
      if (await requirementsFile.exists() || await pyprojectFile.exists()) {
        final foundFile = await requirementsFile.exists() ? 'requirements.txt' : 'pyproject.toml';
        print('✅ Proyecto Python detectado (encontrado: ${subdir.isEmpty ? foundFile : '$subdir/$foundFile'})');
        return ProjectType.python;
      }
    }
    
    // 6. Go
    final goModFile = File('$projectPath/go.mod');
    if (await goModFile.exists()) {
      print('✅ Proyecto Go detectado');
      return ProjectType.golang;
    }
    
    // 7. Rust
    final cargoFile = File('$projectPath/Cargo.toml');
    if (await cargoFile.exists()) {
      print('✅ Proyecto Rust detectado');
      return ProjectType.rust;
    }
    
    // 8. HTML estático
    final indexHtmlFile = File('$projectPath/index.html');
    if (await indexHtmlFile.exists()) {
      print('✅ Proyecto HTML estático detectado');
      return ProjectType.html;
    }
    
    // 9. Java / Maven
    final pomFile = File('$projectPath/pom.xml');
    if (await pomFile.exists()) {
      print('✅ Proyecto Maven (Java) detectado');
      return ProjectType.maven;
    }
    
    // 10. Java / Gradle
    final gradleFile = File('$projectPath/build.gradle');
    final gradleKtsFile = File('$projectPath/build.gradle.kts');
    if (await gradleFile.exists() || await gradleKtsFile.exists()) {
      print('✅ Proyecto Gradle (Java) detectado');
      return ProjectType.gradle;
    }
    
    print('⚠️ Tipo de proyecto desconocido');
    return ProjectType.unknown;
  }
  
  /// Detecta y retorna el comando de Python con soporte para entornos virtuales
  static Future<String> _getPythonCommand(String workingDir) async {
    // Verificar si existe un entorno virtual en el directorio de trabajo
    final venvDirs = ['venv', '.venv', 'env', '.env'];
    for (final venvDir in venvDirs) {
      final venvPath = Directory('$workingDir/$venvDir');
      if (await venvPath.exists()) {
        // Verificar si existe el ejecutable de Python en el venv
        final pythonExec = File('$workingDir/$venvDir/bin/python3');
        if (await pythonExec.exists()) {
          print('✅ Entorno virtual detectado: $venvDir');
          return '$workingDir/$venvDir/bin/python3';
        }
        // También verificar python (sin el 3) para compatibilidad
        final pythonExecAlt = File('$workingDir/$venvDir/bin/python');
        if (await pythonExecAlt.exists()) {
          print('✅ Entorno virtual detectado: $venvDir');
          return '$workingDir/$venvDir/bin/python';
        }
      }
    }
    // Si no se encuentra venv, usar python3 del sistema
    return 'python3';
  }
  
  /// Obtiene el comando de ejecución para el tipo de proyecto
  static Future<RunCommand> getRunCommand(String projectPath, ProjectType type, {bool isDebug = false}) async {
    print('🎯 Obteniendo comando de ejecución para: $type (debug: $isDebug)');
    
    switch (type) {
      case ProjectType.flutter:
        return RunCommand(
          command: 'flutter',
          args: ['run', if (isDebug) '--debug' else '--release'],
          workingDirectory: projectPath,
          description: 'Flutter ${isDebug ? 'Debug' : 'Release'}',
          requiresDevice: true,
        );
        
      case ProjectType.python:
        // Buscar el archivo principal en el directorio raíz y subdirectorios comunes
        String mainFile = 'main.py';
        String workingDir = projectPath;
        final commonSubdirs = ['', 'backend', 'src', 'app', 'server', 'api'];
        final pythonFiles = ['main.py', 'app.py', 'run.py', 'server.py'];
        
        bool found = false;
        for (final subdir in commonSubdirs) {
          if (found) break;
          final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
          for (final file in pythonFiles) {
            final filePath = File('$basePath/$file');
            if (await filePath.exists()) {
              mainFile = file;
              workingDir = basePath;
              found = true;
              break;
            }
          }
        }
        
        // Detectar si es FastAPI ejecutándose directamente desde main.py
        // Si contiene uvicorn.run, usar uvicorn desde línea de comandos en su lugar
        bool isFastAPI = false;
        int? defaultPort;
        try {
          final mainFileContent = await File('$workingDir/$mainFile').readAsString();
          if (mainFileContent.contains('from fastapi import') || mainFileContent.contains('import fastapi')) {
            isFastAPI = true;
            // Intentar detectar el puerto del código
            final portMatch = RegExp(r'port[=\s:]+(\d+)').firstMatch(mainFileContent);
            if (portMatch != null) {
              defaultPort = int.tryParse(portMatch.group(1)!);
            } else {
              defaultPort = 8000; // Puerto por defecto para FastAPI
            }
          } else if (mainFileContent.contains('uvicorn.run')) {
            isFastAPI = true;
            defaultPort = 8000;
          }
        } catch (e) {
          print('⚠️ No se pudo leer $mainFile para detectar configuración: $e');
        }
        
        // Si es FastAPI, usar uvicorn desde línea de comandos para controlar el puerto
        if (isFastAPI) {
          // Detectar y usar entorno virtual si existe
          final venvDirs = ['venv', '.venv', 'env', '.env'];
          String uvicornCommand = 'uvicorn';
          for (final venvDir in venvDirs) {
            final venvPath = Directory('$workingDir/$venvDir');
            if (await venvPath.exists()) {
              final uvicornExec = File('$workingDir/$venvDir/bin/uvicorn');
              if (await uvicornExec.exists()) {
                uvicornCommand = '$workingDir/$venvDir/bin/uvicorn';
                print('✅ Entorno virtual detectado para FastAPI: $venvDir');
                break;
              }
            }
          }
          
          // Gestionar puerto
          int port = defaultPort ?? 8000;
          if (await isPortInUse(port)) {
            print('⚠️ Puerto $port está en uso, buscando puerto disponible...');
            // Intentar terminar el proceso anterior
            final killed = await killProcessOnPort(port);
            if (!killed) {
              // Si no se pudo terminar, buscar otro puerto
              port = await findAvailablePort(port + 1);
              print('✅ Usando puerto alternativo: $port');
            } else {
              print('✅ Proceso anterior terminado, usando puerto $port');
            }
          }
          
          // Extraer el nombre del módulo (main.py -> main)
          final moduleName = mainFile.replaceAll('.py', '');
          
          return RunCommand(
            command: uvicornCommand,
            args: ['$moduleName:app', '--reload', '--host', '0.0.0.0', '--port', port.toString()],
            workingDirectory: workingDir,
            description: 'FastAPI Server (puerto $port)',
            requiresDevice: false,
          );
        }
        
        // Para otros tipos de servidores web Python (Flask, etc.)
        bool isWebServer = false;
        try {
          final mainFileContent = await File('$workingDir/$mainFile').readAsString();
          if (mainFileContent.contains('app.run') || mainFileContent.contains('flask')) {
            isWebServer = true;
            final portMatch = RegExp(r'port[=\s:]+(\d+)').firstMatch(mainFileContent);
            if (portMatch != null) {
              defaultPort = int.tryParse(portMatch.group(1)!);
            } else {
              defaultPort = 5000; // Puerto por defecto para Flask
            }
          }
        } catch (e) {
          print('⚠️ No se pudo leer $mainFile: $e');
        }
        
        // Si es un servidor web, gestionar el puerto
        Map<String, String>? environment;
        if (isWebServer && defaultPort != null) {
          int port = defaultPort;
          if (await isPortInUse(port)) {
            print('⚠️ Puerto $port está en uso, buscando puerto disponible...');
            // Intentar terminar el proceso anterior
            final killed = await killProcessOnPort(port);
            if (!killed) {
              // Si no se pudo terminar, buscar otro puerto
              port = await findAvailablePort(port + 1);
              print('✅ Usando puerto alternativo: $port');
              // Configurar variable de entorno para que la app use el nuevo puerto
              environment = {'PORT': port.toString()};
            } else {
              print('✅ Proceso anterior terminado, usando puerto $port');
            }
          }
        }
        
        // Detectar y usar entorno virtual si existe
        final pythonCommand = await _getPythonCommand(workingDir);
        
        return RunCommand(
          command: pythonCommand,
          args: [mainFile],
          workingDirectory: workingDir,
          description: isWebServer ? 'Python Web Server' : 'Python App',
          requiresDevice: false,
          environment: environment,
        );
        
      case ProjectType.django:
        // Buscar manage.py en subdirectorios
        String djangoDir = projectPath;
        final commonSubdirs = ['', 'backend', 'src', 'app', 'server', 'api'];
        for (final subdir in commonSubdirs) {
          final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
          if (await File('$basePath/manage.py').exists()) {
            djangoDir = basePath;
            break;
          }
        }
        
        // Gestionar puerto: Django usa 8000 por defecto
        int port = 8000;
        if (await isPortInUse(8000)) {
          print('⚠️ Puerto 8000 está en uso, buscando puerto disponible...');
          // Intentar terminar el proceso anterior
          final killed = await killProcessOnPort(8000);
          if (!killed) {
            // Si no se pudo terminar, buscar otro puerto
            port = await findAvailablePort(8001);
            print('✅ Usando puerto alternativo: $port');
          } else {
            print('✅ Proceso anterior terminado, usando puerto 8000');
          }
        }
        
        // Detectar y usar entorno virtual si existe
        final djangoPythonCommand = await _getPythonCommand(djangoDir);
        return RunCommand(
          command: djangoPythonCommand,
          args: ['manage.py', 'runserver', '0.0.0.0:$port'],
          workingDirectory: djangoDir,
          description: 'Django Server (puerto $port)',
          requiresDevice: false,
        );
        
      case ProjectType.fastapi:
        // Buscar main.py en subdirectorios
        String fastapiDir = projectPath;
        final commonSubdirs = ['', 'backend', 'src', 'app', 'server', 'api'];
        for (final subdir in commonSubdirs) {
          final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
          if (await File('$basePath/main.py').exists()) {
            fastapiDir = basePath;
            break;
          }
        }
        // Detectar y usar entorno virtual si existe
        // Para FastAPI, uvicorn debe estar en el PATH del venv
        final venvDirs = ['venv', '.venv', 'env', '.env'];
        String uvicornCommand = 'uvicorn';
        for (final venvDir in venvDirs) {
          final venvPath = Directory('$fastapiDir/$venvDir');
          if (await venvPath.exists()) {
            final uvicornExec = File('$fastapiDir/$venvDir/bin/uvicorn');
            if (await uvicornExec.exists()) {
              uvicornCommand = '$fastapiDir/$venvDir/bin/uvicorn';
              print('✅ Entorno virtual detectado para FastAPI: $venvDir');
              break;
            }
          }
        }
        
        // Gestionar puerto: verificar si 8000 está en uso, si no, encontrar uno disponible
        int port = 8000;
        if (await isPortInUse(8000)) {
          print('⚠️ Puerto 8000 está en uso, buscando puerto disponible...');
          // Intentar terminar el proceso anterior
          final killed = await killProcessOnPort(8000);
          if (!killed) {
            // Si no se pudo terminar, buscar otro puerto
            port = await findAvailablePort(8001);
            print('✅ Usando puerto alternativo: $port');
          } else {
            print('✅ Proceso anterior terminado, usando puerto 8000');
          }
        }
        
        return RunCommand(
          command: uvicornCommand,
          args: ['main:app', '--reload', '--host', '0.0.0.0', '--port', port.toString()],
          workingDirectory: fastapiDir,
          description: 'FastAPI Server (puerto $port)',
          requiresDevice: false,
        );
        
      case ProjectType.flask:
        // Buscar app.py en subdirectorios
        String flaskDir = projectPath;
        String flaskFile = 'app.py';
        final commonSubdirs = ['', 'backend', 'src', 'app', 'server', 'api'];
        for (final subdir in commonSubdirs) {
          final basePath = subdir.isEmpty ? projectPath : '$projectPath/$subdir';
          if (await File('$basePath/app.py').exists()) {
            flaskDir = basePath;
            flaskFile = 'app.py';
            break;
          } else if (await File('$basePath/main.py').exists()) {
            flaskDir = basePath;
            flaskFile = 'main.py';
            break;
          }
        }
        
        // Gestionar puerto: Flask usa 5000 por defecto
        int port = 5000;
        if (await isPortInUse(5000)) {
          print('⚠️ Puerto 5000 está en uso, buscando puerto disponible...');
          // Intentar terminar el proceso anterior
          final killed = await killProcessOnPort(5000);
          if (!killed) {
            // Si no se pudo terminar, buscar otro puerto
            port = await findAvailablePort(5001);
            print('✅ Usando puerto alternativo: $port');
          } else {
            print('✅ Proceso anterior terminado, usando puerto 5000');
          }
        }
        
        // Detectar y usar entorno virtual si existe
        final flaskPythonCommand = await _getPythonCommand(flaskDir);
        return RunCommand(
          command: flaskPythonCommand,
          args: [flaskFile],
          workingDirectory: flaskDir,
          description: 'Flask Server (puerto $port)',
          requiresDevice: false,
          environment: {
            'FLASK_ENV': 'development',
            'FLASK_RUN_PORT': port.toString(),
          },
        );
        
      case ProjectType.nodejs:
        // Intentar con npm start, si no existe usar node
        final packageJsonFile = File('$projectPath/package.json');
        if (await packageJsonFile.exists()) {
          return RunCommand(
            command: 'npm',
            args: ['start'],
            workingDirectory: projectPath,
            description: 'Node.js App',
            requiresDevice: false,
          );
        }
        return RunCommand(
          command: 'node',
          args: ['index.js'],
          workingDirectory: projectPath,
          description: 'Node.js App',
          requiresDevice: false,
        );
        
      case ProjectType.react:
        return RunCommand(
          command: 'npm',
          args: ['start'],
          workingDirectory: projectPath,
          description: 'React App',
          requiresDevice: false,
        );
        
      case ProjectType.nextjs:
        return RunCommand(
          command: 'npm',
          args: ['run', 'dev'],
          workingDirectory: projectPath,
          description: 'Next.js App',
          requiresDevice: false,
        );
        
      case ProjectType.vue:
        return RunCommand(
          command: 'npm',
          args: ['run', 'dev'],
          workingDirectory: projectPath,
          description: 'Vue App',
          requiresDevice: false,
        );
        
      case ProjectType.vite:
        return RunCommand(
          command: 'npm',
          args: ['run', 'dev'],
          workingDirectory: projectPath,
          description: 'Vite App',
          requiresDevice: false,
        );
        
      case ProjectType.golang:
        return RunCommand(
          command: 'go',
          args: ['run', '.'],
          workingDirectory: projectPath,
          description: 'Go App',
          requiresDevice: false,
        );
        
      case ProjectType.rust:
        return RunCommand(
          command: 'cargo',
          args: ['run', if (isDebug) '--' else '--release'],
          workingDirectory: projectPath,
          description: 'Rust App',
          requiresDevice: false,
        );
        
      case ProjectType.maven:
        return RunCommand(
          command: 'mvn',
          args: ['spring-boot:run'],
          workingDirectory: projectPath,
          description: 'Maven (Java) App',
          requiresDevice: false,
        );
        
      case ProjectType.gradle:
        return RunCommand(
          command: './gradlew',
          args: ['bootRun'],
          workingDirectory: projectPath,
          description: 'Gradle (Java) App',
          requiresDevice: false,
        );
        
      case ProjectType.html:
        // Puerto fijo 8000 chocaba con Runs anteriores (Address already in use).
        // Liberar zombie típico y elegir puerto libre; bind IPv4 para Preview.
        await killProcessOnPort(8000);
        final htmlPort = await findAvailablePort(8000);
        return RunCommand(
          command: 'python3',
          args: [
            '-m',
            'http.server',
            '$htmlPort',
            '--bind',
            '127.0.0.1',
          ],
          workingDirectory: projectPath,
          description: 'Static HTML Server :$htmlPort',
          requiresDevice: false,
        );
        
      case ProjectType.unknown:
        throw Exception('Tipo de proyecto desconocido. No se puede ejecutar.');
    }
  }
  
  /// Obtiene el nombre amigable del tipo de proyecto
  static String getProjectTypeName(ProjectType type) {
    switch (type) {
      case ProjectType.flutter: return 'Flutter';
      case ProjectType.python: return 'Python';
      case ProjectType.django: return 'Django';
      case ProjectType.fastapi: return 'FastAPI';
      case ProjectType.flask: return 'Flask';
      case ProjectType.nodejs: return 'Node.js';
      case ProjectType.react: return 'React';
      case ProjectType.nextjs: return 'Next.js';
      case ProjectType.vue: return 'Vue.js';
      case ProjectType.vite: return 'Vite';
      case ProjectType.golang: return 'Go';
      case ProjectType.rust: return 'Rust';
      case ProjectType.maven: return 'Maven (Java)';
      case ProjectType.gradle: return 'Gradle (Java)';
      case ProjectType.html: return 'HTML/CSS/JS';
      case ProjectType.unknown: return 'Desconocido';
    }
  }
  
  /// Obtiene el icono para el tipo de proyecto
  static String getProjectTypeIcon(ProjectType type) {
    switch (type) {
      case ProjectType.flutter: return '📱';
      case ProjectType.python: return '🐍';
      case ProjectType.django: return '🎸';
      case ProjectType.fastapi: return '⚡';
      case ProjectType.flask: return '🌶️';
      case ProjectType.nodejs: return '🟢';
      case ProjectType.react: return '⚛️';
      case ProjectType.nextjs: return '▲';
      case ProjectType.vue: return '💚';
      case ProjectType.vite: return '⚡';
      case ProjectType.golang: return '🔵';
      case ProjectType.rust: return '🦀';
      case ProjectType.maven: return '☕';
      case ProjectType.gradle: return '☕';
      case ProjectType.html: return '🌐';
      case ProjectType.unknown: return '❓';
    }
  }
}

/// Tipos de proyecto soportados
enum ProjectType {
  flutter,
  python,
  django,
  fastapi,
  flask,
  nodejs,
  react,
  nextjs,
  vue,
  vite,
  golang,
  rust,
  maven,
  gradle,
  html,
  unknown,
}

/// Comando de ejecución para un proyecto
class RunCommand {
  final String command;
  final List<String> args;
  final String workingDirectory;
  final String description;
  final bool requiresDevice;
  final Map<String, String>? environment;
  
  const RunCommand({
    required this.command,
    required this.args,
    required this.workingDirectory,
    required this.description,
    required this.requiresDevice,
    this.environment,
  });
  
  @override
  String toString() {
    return '$command ${args.join(' ')}';
  }
}
