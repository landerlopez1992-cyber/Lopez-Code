import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cursor_theme.dart';

/// Emulador de teléfono Android/iOS
/// Similar a Flutter Flow - muestra la app dentro de un frame de teléfono
class PhoneEmulator extends StatefulWidget {
  final String platform; // 'android', 'ios', o 'web'
  final Widget? child; // Contenido de la app (fallback)
  final bool isRunning;
  final String? appUrl; // URL de la app ejecutándose (para web)
  final double? width;
  final double? height;
  final double compilationProgress; // Progreso de compilación (0.0 - 1.0)
  final String compilationStatus; // Estado de compilación

  const PhoneEmulator({
    super.key,
    required this.platform,
    this.child,
    this.isRunning = false,
    this.appUrl,
    this.width,
    this.height,
    this.compilationProgress = 0.0,
    this.compilationStatus = '',
  });

  @override
  State<PhoneEmulator> createState() => _PhoneEmulatorState();
}

class _PhoneEmulatorState extends State<PhoneEmulator> {
  late WebViewController _webViewController;
  bool _webViewInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    // Si ya hay una URL disponible al inicializar, cargarla
    if (widget.appUrl != null && widget.appUrl!.isNotEmpty && widget.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAppUrl();
      });
    }
  }

  void _initializeWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('🌐 WebView cargando: $url');
          },
          onPageFinished: (String url) {
            print('✅ WebView cargado: $url');
            if (mounted) {
              setState(() {
                _webViewInitialized = true;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ Error WebView: ${error.description}');
          },
        ),
      );
  }

  @override
  void didUpdateWidget(PhoneEmulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cargar URL si cambió o si ahora está disponible
    if (widget.appUrl != null && 
        widget.appUrl!.isNotEmpty && 
        widget.isRunning &&
        (widget.appUrl != oldWidget.appUrl || 
         (oldWidget.appUrl == null && widget.appUrl != null) ||
         !_webViewInitialized)) {
      print('🔄 PhoneEmulator: URL actualizada de "${oldWidget.appUrl}" a "${widget.appUrl}"');
      print('   isRunning: ${widget.isRunning}');
      print('   appUrl: ${widget.appUrl}');
      print('   _webViewInitialized: $_webViewInitialized');
      _loadAppUrl();
    }
    
    // Debug: mostrar estado actual
    if (widget.isRunning && widget.appUrl == null) {
      print('⚠️ PhoneEmulator: El servidor está ejecutándose pero no hay URL disponible aún');
    }
    
    // Si la URL está disponible pero el WebView no se ha inicializado, forzar carga
    if (widget.isRunning && 
        widget.appUrl != null && 
        widget.appUrl!.isNotEmpty && 
        !_webViewInitialized) {
      print('🔄 PhoneEmulator: Forzando carga de URL porque WebView no está inicializado');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAppUrl();
      });
    }
  }

  void _loadAppUrl() {
    if (widget.appUrl != null && widget.appUrl!.isNotEmpty) {
      print('📱 PhoneEmulator._loadAppUrl: Cargando app en WebView: ${widget.appUrl}');
      print('   isRunning: ${widget.isRunning}');
      print('   platform: ${widget.platform}');
      try {
        final uri = Uri.parse(widget.appUrl!);
        print('   URI parseado: $uri');
        _webViewController.loadRequest(uri);
        print('✅ loadRequest llamado en WebViewController');
      } catch (e) {
        print('❌ Error al parsear URL: $e');
      }
    } else {
      print('⚠️ PhoneEmulator._loadAppUrl: No hay URL disponible');
      print('   appUrl: ${widget.appUrl}');
      print('   isRunning: ${widget.isRunning}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = widget.platform.toLowerCase() == 'ios';
    final isAndroid = widget.platform.toLowerCase() == 'android';
    final isWeb = widget.platform.toLowerCase() == 'web';
    
    // Si es web, usar WebView directamente
    if (isWeb) {
      if (widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
        print('🌐 PhoneEmulator (Web): Mostrando WebView con URL: ${widget.appUrl}');
        return Container(
          width: widget.width,
          height: widget.height,
          color: CursorTheme.background,
          child: Stack(
            children: [
              WebViewWidget(controller: _webViewController),
              Positioned(
                top: 10,
                right: 10,
                child: FloatingActionButton.small(
                  onPressed: () async {
                    final uri = Uri.parse(widget.appUrl!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                      print('✅ URL abierta en navegador externo: ${widget.appUrl}');
                    } else {
                      print('❌ No se pudo abrir la URL en navegador externo: ${widget.appUrl}');
                    }
                  },
                  backgroundColor: CursorTheme.primary,
                  child: Icon(Icons.open_in_browser, color: Colors.white),
                  tooltip: 'Abrir en navegador externo',
                ),
              ),
            ],
          ),
        );
      } else if (widget.isRunning) {
        // Mostrar indicador de carga si está ejecutándose pero aún no hay URL
        print('⏳ PhoneEmulator (Web): Esperando URL... isRunning: ${widget.isRunning}, appUrl: ${widget.appUrl}');
        return Container(
          width: widget.width,
          height: widget.height,
          color: CursorTheme.background,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: CursorTheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Esperando URL de la app...',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // No está ejecutándose
        return Container(
          width: widget.width,
          height: widget.height,
          color: CursorTheme.background,
          child: Center(
            child: Text(
              'Presiona Run/Debug para iniciar',
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        );
      }
    }
    
    // Si no es Android ni iOS, no mostrar el emulador
    if (!isIOS && !isAndroid) {
      return Container(
        color: CursorTheme.background,
        child: Center(
          child: Text(
            'Emulador solo disponible para Android e iOS',
            style: TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: CursorTheme.background,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(), // Scroll funcional en el emulador
        child: Center(
          child: _buildPhoneFrame(isIOS),
        ),
      ),
    );
  }

  Widget _buildPhoneFrame(bool isIOS) {
    if (isIOS) {
      return _buildIOSFrame();
    } else {
      return _buildAndroidFrame();
    }
  }

  Widget _buildIOSFrame() {
    // Dimensiones más realistas y estrechas (iPhone 14 Pro: 393x852, pero en emulador más pequeño)
    return Container(
      width: 300, // Más estrecho para emulador
      height: 650, // Proporción mantenida
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: Colors.grey.shade800,
          width: 8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(42),
        child: Container(
          decoration: BoxDecoration(
            color: CursorTheme.surface,
          ),
          child: Column(
            children: [
              // Notch (Dynamic Island)
              Container(
                height: 50,
                width: double.infinity,
                color: Colors.black,
                child: Center(
                  child: Container(
                    width: 126,
                    height: 37,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              // Screen content
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: CursorTheme.surface,
                  child: _buildScreenContent(),
                ),
              ),
              // Home indicator
              Container(
                height: 34,
                width: double.infinity,
                color: Colors.black,
                child: Center(
                  child: Container(
                    width: 134,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidFrame() {
    // Dimensiones más realistas y estrechas
    return Container(
      width: 300, // Más estrecho para emulador
      height: 650, // Proporción mantenida
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: Colors.grey.shade800,
          width: 6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(
            color: CursorTheme.surface,
          ),
          child: Column(
            children: [
              // Status bar
              Container(
                height: 24,
                width: double.infinity,
                color: Colors.black,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        children: [
                          Icon(Icons.signal_cellular_4_bar, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Icon(Icons.wifi, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Icon(Icons.battery_full, size: 12, color: Colors.white),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '9:41',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Screen content
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: CursorTheme.surface,
                  child: _buildScreenContent(),
                ),
              ),
              // Navigation bar
              Container(
                height: 48,
                width: double.infinity,
                color: Colors.black,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreenContent() {
    // Debug logging
    print('📱 PhoneEmulator._buildScreenContent:');
    print('   platform: ${widget.platform}');
    print('   isRunning: ${widget.isRunning}');
    print('   appUrl: ${widget.appUrl}');
    print('   compilationProgress: ${widget.compilationProgress}');
    print('   compilationStatus: ${widget.compilationStatus}');
    print('   child: ${widget.child != null ? "presente" : "null"}');
    
    final isWeb = widget.platform.toLowerCase() == 'web';
    
    // PRIORIDAD 1: Si es web y hay URL, SIEMPRE mostrar WebView (ignorar child)
    if (isWeb && widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
      print('✅ PRIORIDAD 1: WebView para web con URL: ${widget.appUrl}');
      // Cargar URL si aún no se ha cargado
      if (!_webViewInitialized) {
        print('🔄 WebView no inicializado, cargando URL...');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAppUrl();
        });
      }
      return WebViewWidget(controller: _webViewController);
    }
    
    // PRIORIDAD 2: Si hay URL y está ejecutándose (para otras plataformas), usar WebView
    if (widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
      print('✅ PRIORIDAD 2: WebView con URL: ${widget.appUrl}');
      // Cargar URL si aún no se ha cargado
      if (!_webViewInitialized) {
        print('🔄 WebView no inicializado, cargando URL...');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAppUrl();
        });
      }
      return WebViewWidget(controller: _webViewController);
    }
    
    // PRIORIDAD 3: Si está compilando, mostrar barra de progreso
    if (widget.isRunning && widget.compilationProgress > 0.0 && widget.compilationProgress < 1.0) {
      print('⏳ PRIORIDAD 3: Mostrando barra de progreso: ${widget.compilationProgress}');
      return _buildCompilationProgress();
    }
    
    // PRIORIDAD 4: Si hay child personalizado Y no hay URL, usarlo
    if (widget.isRunning && widget.child != null && (widget.appUrl == null || widget.appUrl!.isEmpty)) {
      print('👶 PRIORIDAD 4: Usando child personalizado (no hay URL)');
      return widget.child!;
    }
    
    // PRIORIDAD 5: Placeholder por defecto
    print('⚠️ PRIORIDAD 5: Mostrando placeholder');
    print('   isRunning: ${widget.isRunning}');
    print('   appUrl: ${widget.appUrl}');
    print('   compilationProgress: ${widget.compilationProgress}');
    return _buildPlaceholder();
  }

  Widget _buildCompilationProgress() {
    final progress = widget.compilationProgress;
    final status = widget.compilationStatus.isNotEmpty 
        ? widget.compilationStatus 
        : 'Compilando...';
    final percent = (progress * 100).toInt();

    return Container(
      color: CursorTheme.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icono de la plataforma
          Icon(
            widget.platform.toLowerCase() == 'ios' ? Icons.phone_iphone : Icons.android,
            size: 64,
            color: CursorTheme.primary.withOpacity(0.7),
          ),
          const SizedBox(height: 32),
          
          // Estado de compilación
          Text(
            status,
            style: TextStyle(
              color: CursorTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          // Barra de progreso profesional
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: CursorTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: CursorTheme.border,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  // Fondo
                  Container(
                    width: double.infinity,
                    color: CursorTheme.surface,
                  ),
                  // Barra de progreso
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            CursorTheme.primary,
                            CursorTheme.primary.withOpacity(0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Porcentaje
          Text(
            '$percent%',
            style: TextStyle(
              color: CursorTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: CursorTheme.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.platform.toLowerCase() == 'ios' ? Icons.phone_iphone : Icons.android,
              size: 64,
              color: CursorTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isRunning
                  ? 'Ejecutando en ${widget.platform.toUpperCase()}...'
                  : 'Presiona Run para iniciar',
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
