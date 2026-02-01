import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cursor_theme.dart';
import '../models/inspector_element.dart';

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
  final bool inspectorMode; // Modo inspector activo desde el exterior
  final Function(InspectorElement)? onElementSelected; // Callback cuando se selecciona un elemento

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
    this.inspectorMode = false,
    this.onElementSelected,
  });

  @override
  State<PhoneEmulator> createState() => _PhoneEmulatorState();
}

class _PhoneEmulatorState extends State<PhoneEmulator> {
  late WebViewController _webViewController;
  bool _webViewInitialized = false;
  bool _inspectorMode = false;
  InspectorElement? _selectedElement;

  @override
  void initState() {
    super.initState();
    _inspectorMode = widget.inspectorMode;
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
      ..addJavaScriptChannel(
        'InspectorChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleInspectorMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('🌐 WebView cargando: $url');
            _selectedElement = null;
          },
          onPageFinished: (String url) {
            print('✅ WebView cargado: $url');
            if (mounted) {
              setState(() {
                _webViewInitialized = true;
              });
              // Inyectar script de inspector si está activo (con delay para asegurar que el canal JS esté listo)
              if (_inspectorMode) {
                // Esperar más tiempo para asegurar que todo esté listo
                Future.delayed(const Duration(milliseconds: 1000), () {
                  if (mounted && _inspectorMode) {
                    _injectInspectorScript();
                  }
                });
              }
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ Error WebView: ${error.description}');
          },
        ),
      );
  }

  /// Inyecta el script JavaScript para el inspector de elementos
  Future<void> _injectInspectorScript() async {
    const script = '''
      (function() {
        // Remover listeners anteriores si existen
        if (window.__inspectorActive) {
          document.removeEventListener('click', window.__inspectorClickHandler, true);
          document.removeEventListener('touchstart', window.__inspectorTouchStartHandler, true);
          document.removeEventListener('touchend', window.__inspectorTouchEndHandler, true);
          document.removeEventListener('touchmove', window.__inspectorTouchMoveHandler, true);
          document.removeEventListener('mouseover', window.__inspectorHoverHandler, true);
          document.removeEventListener('mouseout', window.__inspectorHoverOutHandler, true);
          
          // Restaurar navegación
          const eventsToBlock = ['click', 'mousedown', 'mouseup', 'touchstart', 'touchend', 'touchmove', 
                                 'contextmenu', 'dblclick', 'submit', 'change', 'input', 'keydown', 'keyup'];
          eventsToBlock.forEach(eventType => {
            document.removeEventListener(eventType, preventAllNavigation, true);
          });
          
          // Restaurar history API
          if (window.__originalPushState) {
            history.pushState = window.__originalPushState;
          }
          if (window.__originalReplaceState) {
            history.replaceState = window.__originalReplaceState;
          }
          
          if (window.__inspectorHighlightDiv) {
            window.__inspectorHighlightDiv.remove();
          }
          if (window.__inspectorSelectedDiv) {
            window.__inspectorSelectedDiv.remove();
          }
        }

        // Crear divs para resaltar elementos (hover y seleccionado)
        const highlightDiv = document.createElement('div');
        highlightDiv.id = '__inspector_highlight';
        highlightDiv.style.cssText = 'position: fixed; pointer-events: none; z-index: 999998; border: 2px solid #007AFF; background: rgba(0, 122, 255, 0.1); box-sizing: border-box; display: none;';
        document.body.appendChild(highlightDiv);
        window.__inspectorHighlightDiv = highlightDiv;

        const selectedDiv = document.createElement('div');
        selectedDiv.id = '__inspector_selected';
        selectedDiv.style.cssText = 'position: fixed; pointer-events: none; z-index: 999999; border: 3px solid #00FF00; background: rgba(0, 255, 0, 0.15); box-sizing: border-box; display: none;';
        document.body.appendChild(selectedDiv);
        window.__inspectorSelectedDiv = selectedDiv;

        let currentHoveredElement = null;
        let currentSelectedElement = null;
        let touchStartElement = null;
        let touchStartTime = null;

        // Función para actualizar la posición del div de resaltado
        function updateHighlightDiv(element, div, color, bgColor) {
          if (!element || element === document.body || element === document.documentElement) {
            div.style.display = 'none';
            return;
          }

          const rect = element.getBoundingClientRect();
          const scrollX = window.pageXOffset || document.documentElement.scrollLeft;
          const scrollY = window.pageYOffset || document.documentElement.scrollTop;

          div.style.left = (rect.left + scrollX) + 'px';
          div.style.top = (rect.top + scrollY) + 'px';
          div.style.width = rect.width + 'px';
          div.style.height = rect.height + 'px';
          div.style.borderColor = color;
          div.style.background = bgColor;
          div.style.display = 'block';
        }

        // Función para obtener información de un elemento
        function getElementInfo(element) {
          if (!element || !element.tagName) return null;

          const rect = element.getBoundingClientRect();
          const computed = window.getComputedStyle(element);
          
          // Obtener estilos relevantes
          const styles = {};
          const styleProps = ['width', 'height', 'padding', 'margin', 'backgroundColor', 
                             'color', 'fontSize', 'fontFamily', 'display', 'position',
                             'border', 'borderRadius', 'opacity', 'zIndex'];
          styleProps.forEach(prop => {
            styles[prop] = computed.getPropertyValue(prop);
          });

          // Obtener atributos
          const attrs = {};
          for (let attr of element.attributes) {
            attrs[attr.name] = attr.value;
          }

          // Obtener hijos
          const children = [];
          for (let child of element.children) {
            const childInfo = getElementInfo(child);
            if (childInfo) children.push(childInfo);
          }

          return {
            tagName: element.tagName,
            id: element.id || null,
            className: element.className || null,
            attributes: attrs,
            textContent: element.textContent ? element.textContent.trim().substring(0, 100) : null,
            computedStyles: styles,
            boundingRect: {
              x: rect.x,
              y: rect.y,
              width: rect.width,
              height: rect.height
            },
            children: children
          };
        }

        // Función para seleccionar un elemento
        function selectElement(element) {
          if (!element || element === document.body || element === document.documentElement) {
            return;
          }

          currentSelectedElement = element;
          updateHighlightDiv(element, selectedDiv, '#00FF00', 'rgba(0, 255, 0, 0.15)');
          
          const elementInfo = getElementInfo(element);
          if (elementInfo) {
            console.log('🔍 Elemento seleccionado:', elementInfo);
            // Enviar información al Flutter
            if (window.flutter_inspector && window.flutter_inspector.postMessage) {
              try {
                window.flutter_inspector.postMessage(JSON.stringify({
                  type: 'elementSelected',
                  element: elementInfo
                }));
              } catch (err) {
                console.error('❌ Error al enviar mensaje:', err);
              }
            } else {
              console.error('❌ window.flutter_inspector no está disponible');
            }
          }
        }

        // Handler para clics (desktop)
        window.__inspectorClickHandler = function(e) {
          if (!window.__inspectorActive) return;
          
          // Marcar como procesado por el inspector
          e.__inspectorProcessed = true;
          
          // NO prevenir el evento aquí, solo seleccionar el elemento
          const element = e.target;
          if (element && element !== document.body && element !== document.documentElement && 
              element.id !== '__inspector_highlight' && element.id !== '__inspector_selected') {
            selectElement(element);
            // Ahora sí prevenir la navegación
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            return false;
          }
        };

        // Handler para touchstart (móvil)
        window.__inspectorTouchStartHandler = function(e) {
          if (!window.__inspectorActive) return;
          
          e.__inspectorProcessed = true;
          
          if (e.touches && e.touches.length > 0) {
            const touch = e.touches[0];
            const element = document.elementFromPoint(touch.clientX, touch.clientY);
            
            // Ignorar si es el div de resaltado
            if (element && element.id !== '__inspector_highlight' && element.id !== '__inspector_selected') {
              touchStartElement = element;
              touchStartTime = Date.now();
              
              if (element !== document.body && element !== document.documentElement) {
                currentHoveredElement = element;
                updateHighlightDiv(element, highlightDiv, '#007AFF', 'rgba(0, 122, 255, 0.1)');
              }
            }
          }
          
          // Prevenir navegación pero permitir selección
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        };

        // Handler para touchmove (móvil)
        window.__inspectorTouchMoveHandler = function(e) {
          if (!window.__inspectorActive) return;
          
          e.__inspectorProcessed = true;
          
          if (e.touches && e.touches.length > 0) {
            const touch = e.touches[0];
            const element = document.elementFromPoint(touch.clientX, touch.clientY);
            
            if (element && element.id !== '__inspector_highlight' && element.id !== '__inspector_selected' &&
                element !== document.body && element !== document.documentElement) {
              if (currentHoveredElement !== element) {
                currentHoveredElement = element;
                updateHighlightDiv(element, highlightDiv, '#007AFF', 'rgba(0, 122, 255, 0.1)');
              }
            }
          }
          
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        };

        // Handler para touchend (móvil) - seleccionar elemento
        window.__inspectorTouchEndHandler = function(e) {
          if (!window.__inspectorActive) return;
          
          e.__inspectorProcessed = true;
          
          if (e.changedTouches && e.changedTouches.length > 0) {
            const touch = e.changedTouches[0];
            const element = document.elementFromPoint(touch.clientX, touch.clientY);
            const touchDuration = Date.now() - (touchStartTime || 0);
            
            // Solo seleccionar si fue un tap rápido (no un scroll) y no es el div de resaltado
            if (touchDuration < 300 && element === touchStartElement && 
                element && element.id !== '__inspector_highlight' && element.id !== '__inspector_selected' &&
                element !== document.body && element !== document.documentElement) {
              selectElement(element);
            }
            
            touchStartElement = null;
            touchStartTime = null;
          }
          
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        };

        // Handler para hover (resaltar elemento con azul)
        window.__inspectorHoverHandler = function(e) {
          const element = e.target;
          if (element && element !== document.body && element !== document.documentElement) {
            currentHoveredElement = element;
            updateHighlightDiv(element, highlightDiv, '#007AFF', 'rgba(0, 122, 255, 0.1)');
            element.style.cursor = 'pointer';
          }
        };

        // Handler para quitar hover
        window.__inspectorHoverOutHandler = function(e) {
          const element = e.target;
          if (element && element.style) {
            element.style.cursor = '';
          }
          // Solo ocultar el highlight si no es el elemento seleccionado
          if (currentHoveredElement !== currentSelectedElement) {
            highlightDiv.style.display = 'none';
          }
          currentHoveredElement = null;
        };

        // Agregar listeners con captura para interceptar antes que otros handlers
        // IMPORTANTE: Los handlers del inspector deben ejecutarse PRIMERO
        document.addEventListener('click', window.__inspectorClickHandler, true);
        document.addEventListener('touchstart', window.__inspectorTouchStartHandler, true);
        document.addEventListener('touchmove', window.__inspectorTouchMoveHandler, true);
        document.addEventListener('touchend', window.__inspectorTouchEndHandler, true);
        document.addEventListener('mouseover', window.__inspectorHoverHandler, true);
        document.addEventListener('mouseout', window.__inspectorHoverOutHandler, true);
        
        // Prevenir navegación SOLO después de que el inspector haya procesado el evento
        // Esto permite que el inspector seleccione elementos pero previene la navegación
        document.addEventListener('click', function(e) {
          if (window.__inspectorActive && !e.__inspectorProcessed) {
            const target = e.target;
            const link = target.closest('a');
            const button = target.closest('button');
            const form = target.closest('form');
            
            // Solo prevenir si NO es el div de resaltado
            if ((link || button || form) && target.id !== '__inspector_highlight' && target.id !== '__inspector_selected') {
              e.preventDefault();
              e.stopPropagation();
              e.stopImmediatePropagation();
              return false;
            }
          }
        }, true);
        
        // Prevenir navegación de formularios
        document.addEventListener('submit', function(e) {
          if (window.__inspectorActive) {
            e.preventDefault();
            e.stopPropagation();
            return false;
          }
        }, true);
        
        // Prevenir cambios de URL
        window.addEventListener('beforeunload', function(e) {
          if (window.__inspectorActive) {
            e.preventDefault();
            e.returnValue = '';
            return '';
          }
        }, true);
        
        // Prevenir navegación programática
        window.__originalPushState = history.pushState;
        window.__originalReplaceState = history.replaceState;
        
        history.pushState = function() {
          if (!window.__inspectorActive) {
            return window.__originalPushState.apply(history, arguments);
          }
        };
        
        history.replaceState = function() {
          if (!window.__inspectorActive) {
            return window.__originalReplaceState.apply(history, arguments);
          }
        };
        
        // Actualizar posición del highlight cuando se hace scroll
        window.addEventListener('scroll', function() {
          if (currentHoveredElement) {
            updateHighlightDiv(currentHoveredElement, highlightDiv, '#007AFF', 'rgba(0, 122, 255, 0.1)');
          }
          if (currentSelectedElement) {
            updateHighlightDiv(currentSelectedElement, selectedDiv, '#00FF00', 'rgba(0, 255, 0, 0.15)');
          }
        }, true);
        
        window.__inspectorActive = true;
        
        // Crear canal de comunicación con Flutter
        if (typeof InspectorChannel !== 'undefined') {
          window.flutter_inspector = {
            postMessage: function(message) {
              try {
                InspectorChannel.postMessage(message);
                console.log('✅ Mensaje enviado al inspector');
              } catch (e) {
                console.error('❌ Error enviando mensaje al inspector:', e);
              }
            }
          };
          console.log('✅ Canal de inspector inicializado');
        } else {
          console.error('❌ InspectorChannel no está disponible');
          setTimeout(function() {
            if (typeof InspectorChannel !== 'undefined') {
              window.flutter_inspector = {
                postMessage: function(message) {
                  try {
                    InspectorChannel.postMessage(message);
                    console.log('✅ Mensaje enviado al inspector (reintento)');
                  } catch (e) {
                    console.error('❌ Error enviando mensaje al inspector:', e);
                  }
                }
              };
            }
          }, 1000);
        }
      })();
    ''';

    try {
      await _webViewController.runJavaScript(script);
      print('✅ Script de inspector inyectado');
    } catch (e) {
      print('❌ Error al inyectar script de inspector: $e');
    }
  }

  /// Remueve el script del inspector
  Future<void> _removeInspectorScript() async {
    const script = '''
      (function() {
        if (window.__inspectorActive) {
          document.removeEventListener('click', window.__inspectorClickHandler, true);
          document.removeEventListener('touchstart', window.__inspectorTouchStartHandler, true);
          document.removeEventListener('touchmove', window.__inspectorTouchMoveHandler, true);
          document.removeEventListener('touchend', window.__inspectorTouchEndHandler, true);
          document.removeEventListener('mouseover', window.__inspectorHoverHandler, true);
          document.removeEventListener('mouseout', window.__inspectorHoverOutHandler, true);
          
          // Los listeners se remueven individualmente arriba
          
          // Restaurar history API
          if (window.__originalPushState) {
            history.pushState = window.__originalPushState;
          }
          if (window.__originalReplaceState) {
            history.replaceState = window.__originalReplaceState;
          }
          
          // Remover divs de resaltado
          if (window.__inspectorHighlightDiv) {
            window.__inspectorHighlightDiv.remove();
            window.__inspectorHighlightDiv = null;
          }
          if (window.__inspectorSelectedDiv) {
            window.__inspectorSelectedDiv.remove();
            window.__inspectorSelectedDiv = null;
          }
          
          // Remover cursor pointer de todos los elementos
          const allElements = document.querySelectorAll('*');
          allElements.forEach(el => {
            if (el.style) {
              el.style.cursor = '';
            }
          });
          
          window.__inspectorActive = false;
        }
      })();
    ''';

    try {
      await _webViewController.runJavaScript(script);
      print('✅ Script de inspector removido');
    } catch (e) {
      print('❌ Error al remover script de inspector: $e');
    }
  }


  /// Maneja mensajes del JavaScript del inspector
  void _handleInspectorMessage(String message) {
    try {
      final data = jsonDecode(message);
      if (data['type'] == 'elementSelected' && data['element'] != null) {
        final element = InspectorElement.fromJson(data['element']);
        setState(() {
          _selectedElement = element;
          print('✅ Elemento seleccionado: ${element.tagName}');
        });
        
        // Notificar al callback si existe
        if (widget.onElementSelected != null) {
          widget.onElementSelected!(element);
        }
      }
    } catch (e) {
      print('❌ Error al procesar mensaje del inspector: $e');
    }
  }


  @override
  void didUpdateWidget(PhoneEmulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Sincronizar el modo inspector con el widget
    if (widget.inspectorMode != oldWidget.inspectorMode) {
      setState(() {
        _inspectorMode = widget.inspectorMode;
        if (_inspectorMode) {
          if (_webViewInitialized) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _inspectorMode) {
                _injectInspectorScript();
              }
            });
          }
        } else {
          _removeInspectorScript();
          _selectedElement = null;
        }
      });
    }
    
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
    try {
      final platform = widget.platform.toLowerCase();
      final isIOS = platform == 'ios';
      final isAndroid = platform == 'android';
      final isWeb = platform == 'web';
      
      // Si es web, mostrar monitor de PC rectangular sin frame de teléfono
      if (isWeb) {
        if (widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
          print('🌐 PhoneEmulator (Web): Mostrando WebView con URL: ${widget.appUrl}');
          return _buildWebMonitor(
            child: Stack(
              children: [
                // WebView a todo ancho
                _buildWebViewWithInspector(),
                // Botón para abrir en navegador externo
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
          return _buildWebMonitor(
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
          // No está ejecutándose - Mostrar placeholder tipo monitor de PC
          return _buildWebMonitor(
            child: _buildPlaceholder(),
          );
        }
      }
    
      // Si no es Android ni iOS ni Web, tratar como web (fallback)
      if (!isIOS && !isAndroid && !isWeb) {
        // Si hay una URL disponible y está ejecutándose, mostrar WebView tipo monitor
        if (widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
          print('🌐 PhoneEmulator (Fallback Web): Mostrando WebView con URL: ${widget.appUrl}');
          return _buildWebMonitor(
            child: Stack(
              children: [
                _buildWebViewWithInspector(),
                // Botón para abrir en navegador externo
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
        }
        // Si no hay URL, mostrar placeholder tipo monitor
        return _buildWebMonitor(
          child: _buildPlaceholder(),
        );
      }

      return Container(
        width: widget.width,
        height: widget.height,
        color: CursorTheme.background,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // Scroll funcional en el emulador
          padding: EdgeInsets.zero, // Sin padding adicional
          child: Align(
            alignment: Alignment.topCenter, // Alinear arriba en lugar de centrar
            child: _buildPhoneFrame(isIOS),
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('❌ Error en PhoneEmulator.build: $e');
      print('Stack trace: $stackTrace');
      // Retornar un widget de error seguro
      return Container(
        width: widget.width,
        height: widget.height,
        color: CursorTheme.background,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error al cargar el emulador',
                style: TextStyle(color: CursorTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Plataforma: ${widget.platform}',
                style: TextStyle(color: CursorTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Construye un contenedor tipo monitor de PC para Web (rectangular, sin frame de teléfono)
  Widget _buildWebMonitor({required Widget child}) {
    // Si width y height están especificados, usarlos; si no, expandir para llenar el espacio disponible
    if (widget.width != null && widget.height != null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: CursorTheme.background,
          border: Border.all(
            color: CursorTheme.border,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: child,
        ),
      );
    } else {
      // Expandir para llenar el espacio disponible
      return Container(
        decoration: BoxDecoration(
          color: CursorTheme.background,
          border: Border.all(
            color: CursorTheme.border,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: child,
        ),
      );
    }
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
              // Navigation bar con botones funcionales
              Container(
                height: 48,
                width: double.infinity,
                color: Colors.black,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Botón Atrás (izquierda)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Navegar hacia atrás en el WebView si está disponible
                          if (_webViewInitialized && widget.isRunning) {
                            _webViewController.goBack();
                            print('🔙 Navegación hacia atrás');
                          }
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                    ),
                    // Botón Home (centro)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Ir al inicio/raíz de la app
                          if (_webViewInitialized && widget.isRunning && widget.appUrl != null) {
                            _webViewController.loadRequest(Uri.parse(widget.appUrl!));
                            print('🏠 Navegación al inicio');
                          }
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
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
                      ),
                    ),
                    // Botón Opciones/Menú (derecha)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Mostrar menú de opciones o recargar
                          if (_webViewInitialized && widget.isRunning) {
                            _webViewController.reload();
                            print('🔄 Recargando aplicación');
                          }
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.more_vert,
                            size: 20,
                            color: Colors.white.withOpacity(0.8),
                          ),
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
    final isAndroid = widget.platform.toLowerCase() == 'android';
    final isIOS = widget.platform.toLowerCase() == 'ios';
    
    // PRIORIDAD 0: Si hay un error de compilación, mostrarlo de manera prominente
    final hasError = widget.compilationStatus.contains('❌') || 
                     widget.compilationStatus.contains('No se encontró') ||
                     widget.compilationStatus.contains('Error') ||
                     widget.compilationStatus.contains('falló') ||
                     widget.compilationStatus.contains('fallida');
    
    if (hasError && !widget.isRunning) {
      print('❌ PRIORIDAD 0: Mostrando error de compilación');
      return _buildErrorState();
    }
    
    // PRIORIDAD 1: Si es WEB y hay URL, mostrar WebView con inspector
    if (isWeb && widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
      print('✅ PRIORIDAD 1: WebView para WEB con URL: ${widget.appUrl}');
      // Cargar URL si aún no se ha cargado
      if (!_webViewInitialized) {
        print('🔄 WebView no inicializado, cargando URL...');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAppUrl();
        });
      }
      return _buildWebViewWithInspector();
    }
    
    // PRIORIDAD 2: Si es ANDROID o iOS y hay URL (fallback web), mostrar WebView dentro del frame del teléfono
    // Esto simula que la app Android/iOS está ejecutándose, pero en realidad es la versión web
    if ((isAndroid || isIOS) && widget.isRunning && widget.appUrl != null && widget.appUrl!.isNotEmpty) {
      print('✅ PRIORIDAD 2: WebView para ${widget.platform.toUpperCase()} con URL (fallback web): ${widget.appUrl}');
      // Cargar URL si aún no se ha cargado
      if (!_webViewInitialized) {
        print('🔄 WebView no inicializado, cargando URL...');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAppUrl();
        });
      }
      return _buildWebViewWithInspector();
    }
    
    // PRIORIDAD 3: Si es ANDROID o iOS y está ejecutándose (sin URL), mostrar mensaje de que la app está en el dispositivo
    // (Las apps nativas se ejecutan en el emulador/dispositivo real, no en el WebView)
    if ((isAndroid || isIOS) && widget.isRunning && (widget.appUrl == null || widget.appUrl!.isEmpty)) {
      if (widget.compilationProgress >= 1.0) {
        print('✅ PRIORIDAD 3: App ejecutándose en ${widget.platform.toUpperCase()} (dispositivo/emulador)');
        return Container(
          color: CursorTheme.surface,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isAndroid
                    ? Icons.android
                    : isIOS
                        ? Icons.apple
                        : Icons.web,
                size: 64,
                color: CursorTheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                '✅ Aplicación ejecutándose',
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'La aplicación se está ejecutando en el ${isAndroid ? "emulador/dispositivo Android" : "simulador/dispositivo iOS"}.\n\n'
                'Revisa el emulador o dispositivo físico para ver la aplicación.',
                style: TextStyle(
                  color: CursorTheme.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.child != null) ...[
                const SizedBox(height: 24),
                Text(
                  'Vista previa:',
                  style: TextStyle(
                    color: CursorTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: widget.child!),
              ],
            ],
          ),
        );
      }
    }
    
    // PRIORIDAD 4: Si está compilando, mostrar barra de progreso
    if (widget.isRunning && widget.compilationProgress > 0.0 && widget.compilationProgress < 1.0) {
      print('⏳ PRIORIDAD 4: Mostrando barra de progreso: ${widget.compilationProgress}');
      return _buildCompilationProgress();
    }
    
    // PRIORIDAD 5: Si hay child personalizado, usarlo (para casos especiales)
    if (widget.child != null) {
      print('👶 PRIORIDAD 5: Usando child personalizado');
      return widget.child!;
    }
    
    // PRIORIDAD 6: Placeholder por defecto
    print('⚠️ PRIORIDAD 6: Mostrando placeholder');
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
            widget.platform.toLowerCase() == 'ios'
                ? Icons.apple
                : widget.platform.toLowerCase() == 'android'
                    ? Icons.android
                    : Icons.web,
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
    // Si hay un mensaje de error en compilationStatus, mostrarlo de manera prominente
    final hasError = widget.compilationStatus.contains('❌') || 
                     widget.compilationStatus.contains('No se encontró') ||
                     widget.compilationStatus.contains('Error') ||
                     widget.compilationStatus.contains('falló') ||
                     widget.compilationStatus.contains('fallida');
    
    if (hasError && !widget.isRunning) {
      return _buildErrorState();
    }
    
    // Contenido placeholder que va DENTRO del frame del teléfono
    // NO llamar a _buildPhoneFrame() aquí porque ya estamos dentro del frame
    // Mostrar el logo de la app (igual que en la pantalla de bienvenida)
    return Container(
      color: CursorTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo de chevrones azules (igual que en welcome_screen)
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
            const SizedBox(height: 32),
            Text(
              'Presiona Run/Debug para iniciar',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La aplicación aparecerá aquí',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CursorTheme.textSecondary.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Container(
      color: CursorTheme.background,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.7),
            ),
            const SizedBox(height: 24),
            Text(
              'Error de Compilación',
              style: TextStyle(
                color: Colors.red,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: SelectableText(
                widget.compilationStatus,
                style: TextStyle(
                  color: CursorTheme.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Revisa el Debug Console para más detalles',
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el WebView con el inspector y overlay
  Widget _buildWebViewWithInspector() {
    return Stack(
      children: [
        WebViewWidget(controller: _webViewController),
        // Overlay del inspector si está activo y hay un elemento seleccionado
        // Solo mostrar el overlay si el inspector está activo y hay un elemento seleccionado
        if (_inspectorMode && _selectedElement != null)
          _buildInspectorOverlay(),
      ],
    );
  }


  /// Construye el overlay con información del elemento seleccionado
  Widget _buildInspectorOverlay() {
    if (_selectedElement == null) return const SizedBox.shrink();

    // El overlay solo debe cubrir el área del WebView, no toda la pantalla
    // Usamos Positioned para colocar el panel lateral sin cubrir todo
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: false, // Permitir interacción con el panel
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: CursorTheme.surface,
            border: Border(
              left: BorderSide(
                color: CursorTheme.border,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(-2, 0),
              ),
            ],
          ),
          child: _buildInspectorPanel(),
        ),
      ),
    );
  }

  /// Construye el panel de información del inspector
  Widget _buildInspectorPanel() {
    if (_selectedElement == null) return const SizedBox.shrink();

    final element = _selectedElement!;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CursorTheme.background,
            border: Border(
              bottom: BorderSide(
                color: CursorTheme.border,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.code,
                size: 20,
                color: CursorTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Inspector de Elementos',
                  style: TextStyle(
                    color: CursorTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: CursorTheme.textSecondary,
                onPressed: () {
                  setState(() {
                    _selectedElement = null;
                  });
                },
                tooltip: 'Cerrar inspector',
              ),
            ],
          ),
        ),
        // Contenido
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Información básica
                _buildInspectorSection(
                  'Elemento',
                  [
                    _buildInspectorRow('Tag', element.tagName),
                    if (element.id != null && element.id!.isNotEmpty)
                      _buildInspectorRow('ID', element.id!),
                    if (element.className != null && element.className!.isNotEmpty)
                      _buildInspectorRow('Clase', element.className!),
                    _buildInspectorRow('Selector', element.fullSelector),
                  ],
                ),
                const SizedBox(height: 16),
                // Dimensiones
                if (element.boundingRect != null)
                  _buildInspectorSection(
                    'Dimensiones',
                    [
                      _buildInspectorRow('X', '${element.boundingRect!.x.toInt()}px'),
                      _buildInspectorRow('Y', '${element.boundingRect!.y.toInt()}px'),
                      _buildInspectorRow('Ancho', '${element.boundingRect!.width.toInt()}px'),
                      _buildInspectorRow('Alto', '${element.boundingRect!.height.toInt()}px'),
                    ],
                  ),
                const SizedBox(height: 16),
                // Estilos
                if (element.computedStyles.isNotEmpty)
                  _buildInspectorSection(
                    'Estilos',
                    element.computedStyles.entries.map((entry) {
                      return _buildInspectorRow(entry.key, entry.value);
                    }).toList(),
                  ),
                const SizedBox(height: 16),
                // Atributos
                if (element.attributes.isNotEmpty)
                  _buildInspectorSection(
                    'Atributos',
                    element.attributes.entries.map((entry) {
                      return _buildInspectorRow(entry.key, entry.value);
                    }).toList(),
                  ),
                const SizedBox(height: 16),
                // Contenido de texto
                if (element.textContent != null && element.textContent!.isNotEmpty)
                  _buildInspectorSection(
                    'Contenido',
                    [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: CursorTheme.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: CursorTheme.border,
                            width: 1,
                          ),
                        ),
                        child: SelectableText(
                          element.textContent!,
                          style: TextStyle(
                            color: CursorTheme.textPrimary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                // Hijos
                if (element.children.isNotEmpty)
                  _buildInspectorSection(
                    'Elementos Hijos (${element.children.length})',
                    element.children.take(5).map((child) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: CursorTheme.background,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: CursorTheme.border,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.label_outline,
                                size: 16,
                                color: CursorTheme.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  child.displayName,
                                  style: TextStyle(
                                    color: CursorTheme.textPrimary,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInspectorSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: CursorTheme.primary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildInspectorRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: CursorTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: CursorTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
