import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cursor_theme.dart';
import 'voryxel_brand_logo.dart';
import '../models/inspector_element.dart';
import '../services/inspector_selection_service.dart';

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
  final Function(InspectorElement?)? onElementHovered;
  /// Cuando cambia (Hot Reload/Restart), recarga el WebView con [appUrl].
  final int previewReloadNonce;

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
    this.onElementHovered,
    this.previewReloadNonce = 0,
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
    const script = r'''
      (function() {
        function teardown() {
          if (!window.__inspectorActive) return;
          [
            ['click', window.__inspectorClickHandler],
            ['mousedown', window.__inspectorMouseDownHandler],
            ['mousemove', window.__inspectorMouseMoveHandler],
            ['mouseout', window.__inspectorHoverOutHandler],
            ['touchstart', window.__inspectorTouchStartHandler],
            ['touchmove', window.__inspectorTouchMoveHandler],
            ['touchend', window.__inspectorTouchEndHandler],
          ].forEach(function(pair) {
            if (pair[1]) document.removeEventListener(pair[0], pair[1], true);
          });
          if (window.__inspectorHighlightDiv) window.__inspectorHighlightDiv.remove();
          if (window.__inspectorSelectedDiv) window.__inspectorSelectedDiv.remove();
          if (window.__inspectorLabelDiv) window.__inspectorLabelDiv.remove();
          window.__inspectorActive = false;
        }
        teardown();

        function ensureChannel() {
          if (typeof InspectorChannel === 'undefined') return false;
          window.flutter_inspector = {
            postMessage: function(message) {
              try { InspectorChannel.postMessage(message); } catch (e) {}
            }
          };
          return true;
        }
        ensureChannel();
        setTimeout(ensureChannel, 400);

        // Intentar exponer nodos de semántica Flutter (mejor hit-test).
        try {
          if (window.flutterCanvasKit == null) {
            // html renderer / glass pane
          }
          var a11yBtn = document.querySelector('flt-semantics-placeholder') ||
                        document.querySelector('[aria-label="Enable accessibility"]');
          if (a11yBtn && a11yBtn.click) a11yBtn.click();
        } catch (e) {}

        var highlightDiv = document.createElement('div');
        highlightDiv.id = '__inspector_highlight';
        highlightDiv.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483645;border:2px solid #3B82F6;background:rgba(59,130,246,0.12);box-sizing:border-box;display:none;';
        document.body.appendChild(highlightDiv);
        window.__inspectorHighlightDiv = highlightDiv;

        var selectedDiv = document.createElement('div');
        selectedDiv.id = '__inspector_selected';
        selectedDiv.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483646;border:2px solid #22C55E;background:rgba(34,197,94,0.14);box-sizing:border-box;display:none;';
        document.body.appendChild(selectedDiv);
        window.__inspectorSelectedDiv = selectedDiv;

        var labelDiv = document.createElement('div');
        labelDiv.id = '__inspector_label';
        labelDiv.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;display:none;padding:4px 8px;border-radius:4px;background:rgba(15,23,42,0.92);color:#E2E8F0;font:11px/1.3 ui-monospace,SFMono-Regular,Menlo,monospace;white-space:nowrap;max-width:240px;overflow:hidden;text-overflow:ellipsis;box-shadow:0 4px 14px rgba(0,0,0,0.35);border:1px solid rgba(148,163,184,0.35);';
        document.body.appendChild(labelDiv);
        window.__inspectorLabelDiv = labelDiv;

        var currentHoveredElement = null;
        var currentSelectedElement = null;
        var lastHoverSentAt = 0;

        function isOverlay(el) {
          if (!el || !el.id) return false;
          return el.id === '__inspector_highlight' ||
                 el.id === '__inspector_selected' ||
                 el.id === '__inspector_label';
        }

        function isBoring(el) {
          if (!el || !el.tagName) return true;
          var tag = el.tagName.toLowerCase();
          if (tag === 'html' || tag === 'body' || tag === 'script' || tag === 'style') return true;
          if (tag === 'flt-glass-pane' || tag === 'flt-scene-host' || tag === 'canvas') return true;
          return false;
        }

        function scoreElement(el) {
          if (!el || isOverlay(el) || isBoring(el)) return -1;
          var score = 1;
          var tag = el.tagName.toLowerCase();
          if (tag.indexOf('flt-semantics') === 0) score += 8;
          if (tag === 'button' || tag === 'a' || tag === 'input' || tag === 'textarea') score += 6;
          if (el.getAttribute && (el.getAttribute('role') || el.getAttribute('aria-label'))) score += 5;
          if (el.id) score += 3;
          var text = (el.innerText || el.textContent || '').trim();
          if (text && text.length > 0 && text.length < 40) score += 4;
          var rect = el.getBoundingClientRect();
          var area = Math.max(0, rect.width) * Math.max(0, rect.height);
          if (area > 0 && area < 40000) score += 2;
          if (area > 120000) score -= 3;
          return score;
        }

        function pickInspectable(x, y, fallback) {
          var stack = [];
          try { stack = document.elementsFromPoint(x, y) || []; } catch (e) {}
          var best = null;
          var bestScore = -1;
          for (var i = 0; i < stack.length; i++) {
            var el = stack[i];
            var s = scoreElement(el);
            if (s > bestScore) {
              bestScore = s;
              best = el;
            }
          }
          if (best) return best;
          var cur = fallback;
          while (cur && (isOverlay(cur) || isBoring(cur))) {
            cur = cur.parentElement;
          }
          return cur || fallback;
        }

        function updateBox(element, div) {
          if (!element || element === document.body || element === document.documentElement) {
            div.style.display = 'none';
            return null;
          }
          var rect = element.getBoundingClientRect();
          div.style.left = rect.left + 'px';
          div.style.top = rect.top + 'px';
          div.style.width = Math.max(0, rect.width) + 'px';
          div.style.height = Math.max(0, rect.height) + 'px';
          div.style.display = 'block';
          return rect;
        }

        function updateLabel(element, rect, selected) {
          if (!element || !rect) {
            labelDiv.style.display = 'none';
            return;
          }
          var tag = (element.tagName || 'node').toLowerCase();
          var text = (element.getAttribute && (element.getAttribute('aria-label') || element.getAttribute('title'))) ||
                     (element.innerText || element.textContent || '');
          text = (text || '').trim().replace(/\s+/g, ' ').substring(0, 28);
          var size = Math.round(rect.width) + '×' + Math.round(rect.height);
          labelDiv.textContent = (selected ? '✓ ' : '') + tag + (text ? ' "' + text + '"' : '') + '  ' + size;
          labelDiv.style.borderColor = selected ? 'rgba(34,197,94,0.55)' : 'rgba(59,130,246,0.55)';
          var left = rect.left;
          var top = rect.top - 26;
          if (top < 4) top = rect.bottom + 6;
          if (left + 200 > window.innerWidth) left = Math.max(4, window.innerWidth - 210);
          labelDiv.style.left = left + 'px';
          labelDiv.style.top = top + 'px';
          labelDiv.style.display = 'block';
        }

        function classNameOf(el) {
          var c = el.className;
          if (!c) return null;
          if (typeof c === 'string') return c;
          if (typeof c.baseVal === 'string') return c.baseVal;
          return String(c);
        }

        function getElementInfo(element) {
          if (!element || !element.tagName) return null;
          var rect = element.getBoundingClientRect();
          var computed = window.getComputedStyle(element);
          var styles = {};
          ['width','height','padding','margin','backgroundColor','color','fontSize','fontFamily','display','position','border','borderRadius','opacity','zIndex'].forEach(function(prop) {
            styles[prop] = computed.getPropertyValue(prop);
          });
          var attrs = {};
          if (element.attributes) {
            for (var i = 0; i < element.attributes.length; i++) {
              var a = element.attributes[i];
              attrs[a.name] = a.value;
            }
          }
          var children = [];
          var kids = element.children || [];
          for (var j = 0; j < Math.min(kids.length, 8); j++) {
            var child = kids[j];
            if (!child || !child.tagName || isOverlay(child)) continue;
            children.push({
              tagName: child.tagName,
              id: child.id || null,
              className: classNameOf(child),
              attributes: {},
              textContent: (child.innerText || child.textContent || '').trim().substring(0, 40) || null,
              computedStyles: {},
              boundingRect: null,
              children: []
            });
          }
          var labelText = (element.getAttribute && (element.getAttribute('aria-label') || element.getAttribute('title'))) ||
                          (element.innerText || element.textContent || '');
          return {
            tagName: element.tagName,
            id: element.id || null,
            className: classNameOf(element),
            attributes: attrs,
            textContent: (labelText || '').trim().substring(0, 100) || null,
            computedStyles: styles,
            boundingRect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
            children: children
          };
        }

        function post(type, element) {
          var info = getElementInfo(element);
          if (!info) return;
          if (!window.flutter_inspector || !window.flutter_inspector.postMessage) {
            ensureChannel();
          }
          if (window.flutter_inspector && window.flutter_inspector.postMessage) {
            try {
              window.flutter_inspector.postMessage(JSON.stringify({ type: type, element: info }));
            } catch (e) {}
          }
        }

        function hoverElement(element) {
          if (!element || element === document.body || element === document.documentElement) return;
          currentHoveredElement = element;
          var rect = updateBox(element, highlightDiv);
          updateLabel(element, rect, false);
          var now = Date.now();
          if (now - lastHoverSentAt > 80) {
            lastHoverSentAt = now;
            post('elementHovered', element);
          }
        }

        function selectElement(element) {
          if (!element || element === document.body || element === document.documentElement) return;
          currentSelectedElement = element;
          currentHoveredElement = element;
          var rect = updateBox(element, selectedDiv);
          updateBox(element, highlightDiv);
          updateLabel(element, rect, true);
          post('elementSelected', element);
        }

        function stopEvent(e) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        }

        window.__inspectorMouseMoveHandler = function(e) {
          if (!window.__inspectorActive) return;
          var el = pickInspectable(e.clientX, e.clientY, e.target);
          if (el && el !== currentHoveredElement) hoverElement(el);
        };

        window.__inspectorHoverOutHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (!e.relatedTarget) {
            if (currentSelectedElement) {
              var rect = updateBox(currentSelectedElement, selectedDiv);
              updateLabel(currentSelectedElement, rect, true);
              highlightDiv.style.display = 'none';
            } else {
              highlightDiv.style.display = 'none';
              labelDiv.style.display = 'none';
            }
            currentHoveredElement = null;
          }
        };

        window.__inspectorMouseDownHandler = function(e) {
          if (!window.__inspectorActive) return;
          stopEvent(e);
        };

        window.__inspectorClickHandler = function(e) {
          if (!window.__inspectorActive) return;
          var el = pickInspectable(e.clientX, e.clientY, e.target);
          if (el) selectElement(el);
          return stopEvent(e);
        };

        window.__inspectorTouchStartHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (e.touches && e.touches.length > 0) {
            var t = e.touches[0];
            var el = pickInspectable(t.clientX, t.clientY, document.elementFromPoint(t.clientX, t.clientY));
            if (el) hoverElement(el);
          }
          return stopEvent(e);
        };

        window.__inspectorTouchMoveHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (e.touches && e.touches.length > 0) {
            var t = e.touches[0];
            var el = pickInspectable(t.clientX, t.clientY, document.elementFromPoint(t.clientX, t.clientY));
            if (el && el !== currentHoveredElement) hoverElement(el);
          }
          return stopEvent(e);
        };

        window.__inspectorTouchEndHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (e.changedTouches && e.changedTouches.length > 0) {
            var t = e.changedTouches[0];
            var el = pickInspectable(t.clientX, t.clientY, document.elementFromPoint(t.clientX, t.clientY));
            if (el) selectElement(el);
          }
          return stopEvent(e);
        };

        document.addEventListener('mousemove', window.__inspectorMouseMoveHandler, true);
        document.addEventListener('mouseout', window.__inspectorHoverOutHandler, true);
        document.addEventListener('mousedown', window.__inspectorMouseDownHandler, true);
        document.addEventListener('click', window.__inspectorClickHandler, true);
        document.addEventListener('touchstart', window.__inspectorTouchStartHandler, true);
        document.addEventListener('touchmove', window.__inspectorTouchMoveHandler, true);
        document.addEventListener('touchend', window.__inspectorTouchEndHandler, true);

        window.__inspectorActive = true;
        document.documentElement.style.cursor = 'crosshair';
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
    const script = r'''
      (function() {
        if (!window.__inspectorActive) return;
        [
          ['click', window.__inspectorClickHandler],
          ['mousedown', window.__inspectorMouseDownHandler],
          ['mousemove', window.__inspectorMouseMoveHandler],
          ['mouseout', window.__inspectorHoverOutHandler],
          ['touchstart', window.__inspectorTouchStartHandler],
          ['touchmove', window.__inspectorTouchMoveHandler],
          ['touchend', window.__inspectorTouchEndHandler],
        ].forEach(function(pair) {
          if (pair[1]) document.removeEventListener(pair[0], pair[1], true);
        });
        if (window.__inspectorHighlightDiv) {
          window.__inspectorHighlightDiv.remove();
          window.__inspectorHighlightDiv = null;
        }
        if (window.__inspectorSelectedDiv) {
          window.__inspectorSelectedDiv.remove();
          window.__inspectorSelectedDiv = null;
        }
        if (window.__inspectorLabelDiv) {
          window.__inspectorLabelDiv.remove();
          window.__inspectorLabelDiv = null;
        }
        document.documentElement.style.cursor = '';
        window.__inspectorActive = false;
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
      final type = data['type']?.toString();
      if (data['element'] == null) return;
      final element = InspectorElement.fromJson(
        Map<String, dynamic>.from(data['element'] as Map),
      );

      if (type == 'elementHovered') {
        InspectorSelectionService().setHovered(element);
        widget.onElementHovered?.call(element);
        return;
      }

      if (type == 'elementSelected') {
        setState(() {
          _selectedElement = element;
        });
        InspectorSelectionService().setSelected(element);
        widget.onElementSelected?.call(element);
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
        InspectorSelectionService().setActive(_inspectorMode);
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

    // Hot Reload / Hot Restart → recargar Preview con la URL de la app.
    if (widget.previewReloadNonce != oldWidget.previewReloadNonce &&
        widget.previewReloadNonce > 0 &&
        widget.isRunning &&
        widget.appUrl != null &&
        widget.appUrl!.isNotEmpty) {
      print(
        '🔄 PhoneEmulator: previewReloadNonce '
        '${oldWidget.previewReloadNonce} → ${widget.previewReloadNonce}',
      );
      _loadAppUrl(forceReload: true);
    }
    
    // Cargar URL si cambió o si ahora está disponible
    final becameReady = widget.compilationProgress >= 1.0 &&
        oldWidget.compilationProgress < 1.0 &&
        widget.appUrl != null &&
        widget.appUrl!.isNotEmpty &&
        widget.isRunning;
    if (widget.appUrl != null && 
        widget.appUrl!.isNotEmpty && 
        widget.isRunning &&
        (widget.appUrl != oldWidget.appUrl || 
         (oldWidget.appUrl == null && widget.appUrl != null) ||
         !_webViewInitialized ||
         becameReady)) {
      print('🔄 PhoneEmulator: URL actualizada de "${oldWidget.appUrl}" a "${widget.appUrl}"'
          '${becameReady ? ' (app lista → reload)' : ''}');
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

  void _loadAppUrl({bool forceReload = false}) {
    final raw = widget.appUrl;
    if (raw == null || raw.isEmpty) {
      print('⚠️ PhoneEmulator._loadAppUrl: No hay URL disponible');
      return;
    }
    // Cache-bust para que Hot Restart no sirva la página vieja.
    final base = raw.split('#').first;
    final sep = base.contains('?') ? '&' : '?';
    final url = forceReload
        ? '$base${sep}_lopez_preview=${DateTime.now().millisecondsSinceEpoch}'
        : raw;
    print('📱 PhoneEmulator._loadAppUrl: $url (forceReload=$forceReload)');
    try {
      final uri = Uri.parse(url);
      _webViewController.loadRequest(uri);
    } catch (e) {
      print('❌ Error al cargar URL en WebView: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final platform = widget.platform.toLowerCase();
      final isIOS = platform == 'ios' || platform == 'ios_native';
      final isAndroid =
          platform == 'android' || platform == 'android_native';
      final isWeb = platform == 'web' || platform == 'macos';

      // Web/macOS: monitor rectangular sin carcasa de teléfono
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: CursorTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Esperando URL de la app...',
                      style: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
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

      // Frame móvil: usa width/height del Preview (pegado arriba, sin hueco).
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: _buildPhoneFrame(isIOS),
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

  /// Monitor Web: llena width×height del Preview (sin hueco hasta la Debug Console).
  Widget _buildWebMonitor({required Widget child}) {
    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CursorTheme.background,
          border: Border.all(
            color: CursorTheme.border,
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _buildPhoneFrame(bool isIOS) {
    // Carcasa según plataforma: iOS notch/home · Android status + nav.
    if (isIOS) {
      return _buildIOSFrame();
    }
    return _buildAndroidFrame();
  }

  Widget _buildIOSFrame() {
    final frameW = widget.width ?? 300;
    final frameH = widget.height ?? 650;
    final notchH = (frameH * 0.06).clamp(22.0, 44.0);
    final homeH = (frameH * 0.04).clamp(16.0, 28.0);
    final islandW = (frameW * 0.38).clamp(60.0, frameW * 0.7);
    final islandH = (notchH * 0.55).clamp(12.0, notchH - 4);
    final homeBarW = (frameW * 0.35).clamp(48.0, 120.0);
    return SizedBox(
      width: frameW,
      height: frameH,
      child: Container(
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
          clipBehavior: Clip.hardEdge,
          child: ColoredBox(
            color: CursorTheme.surface,
            child: Column(
              children: [
                SizedBox(
                  height: notchH,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Container(
                        width: islandW,
                        height: islandH,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: CursorTheme.surface,
                    child: ClipRect(child: _buildScreenContent()),
                  ),
                ),
                SizedBox(
                  height: homeH,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Container(
                        width: homeBarW,
                        height: (homeH * 0.22).clamp(3.0, 5.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidFrame() {
    final frameW = widget.width ?? 300;
    final frameH = widget.height ?? 650;
    // Chrome flexible: NUNCA overflow del marco (solo el proyecto en WebView puede).
    final statusH = (frameH * 0.035).clamp(12.0, 22.0);
    final navH = (frameH * 0.07).clamp(28.0, 44.0);
    // Botones siempre caben dentro de navH (antes 48px en nav de 32 → overflow).
    final sideBtn = (navH - 6).clamp(16.0, 36.0);
    final homeBtn = (navH - 4).clamp(18.0, 40.0);
    final sideIcon = (sideBtn * 0.45).clamp(10.0, 18.0);
    final homeDot = (homeBtn * 0.45).clamp(8.0, 18.0);
    final statusIcon = (statusH * 0.55).clamp(8.0, 12.0);
    final statusFont = (statusH * 0.55).clamp(8.0, 11.0);

    return SizedBox(
      width: frameW,
      height: frameH,
      child: Container(
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
          clipBehavior: Clip.hardEdge,
          child: ColoredBox(
            color: CursorTheme.surface,
            child: Column(
              children: [
                SizedBox(
                  height: statusH,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Icon(Icons.signal_cellular_4_bar,
                              size: statusIcon, color: Colors.white),
                          SizedBox(width: statusIcon * 0.3),
                          Icon(Icons.wifi,
                              size: statusIcon, color: Colors.white),
                          SizedBox(width: statusIcon * 0.3),
                          Icon(Icons.battery_full,
                              size: statusIcon, color: Colors.white),
                          const Spacer(),
                          Text(
                            '9:41',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: statusFont,
                              fontWeight: FontWeight.w500,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Área del proyecto: único sitio donde puede haber overflow real.
                Expanded(
                  child: ColoredBox(
                    color: CursorTheme.surface,
                    child: ClipRect(child: _buildScreenContent()),
                  ),
                ),
                SizedBox(
                  height: navH,
                  width: double.infinity,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _navCircleButton(
                          size: sideBtn,
                          onTap: () {
                            if (_webViewInitialized && widget.isRunning) {
                              _webViewController.goBack();
                            }
                          },
                          child: Icon(
                            Icons.arrow_back,
                            size: sideIcon,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                        _navCircleButton(
                          size: homeBtn,
                          fill: 0.15,
                          onTap: () {
                            if (_webViewInitialized &&
                                widget.isRunning &&
                                widget.appUrl != null) {
                              _webViewController
                                  .loadRequest(Uri.parse(widget.appUrl!));
                            }
                          },
                          child: Container(
                            width: homeDot,
                            height: homeDot,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        _navCircleButton(
                          size: sideBtn,
                          onTap: () {
                            if (_webViewInitialized && widget.isRunning) {
                              _webViewController.reload();
                            }
                          },
                          child: Icon(
                            Icons.more_vert,
                            size: sideIcon,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navCircleButton({
    required double size,
    required Widget child,
    required VoidCallback onTap,
    double fill = 0.1,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(fill),
              shape: BoxShape.circle,
            ),
            child: Center(child: child),
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
    
    final plat = widget.platform.toLowerCase();
    final isWeb = plat == 'web' || plat == 'macos';
    final isAndroid = plat == 'android' || plat == 'android_native';
    final isIOS = plat == 'ios' || plat == 'ios_native';
    final isMobilePreview = plat == 'android' || plat == 'ios';

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

    // Compilando primero (evita WebView en blanco con URL provisional).
    final statusLower = widget.compilationStatus.toLowerCase();
    final stillLaunching = statusLower.contains('instal') ||
        statusLower.contains('iniciando') ||
        statusLower.contains('compil') ||
        statusLower.contains('lanzand') ||
        statusLower.contains('prepar') ||
        statusLower.contains('waiting') ||
        statusLower.contains('syncing');
    final isBuilding = widget.isRunning &&
        widget.compilationProgress < 1.0 &&
        (widget.appUrl == null ||
            widget.appUrl!.isEmpty ||
            stillLaunching ||
            widget.compilationProgress < 0.95);
    if (isBuilding) {
      print(
        '⏳ PRIORIDAD build: Compilando (${widget.compilationProgress}) '
        '· ${widget.compilationStatus}',
      );
      return _buildCompilationProgress();
    }

    // WebView: Web full-bleed O Android/iOS Preview dentro del marco.
    final hasUrl = widget.appUrl != null && widget.appUrl!.isNotEmpty;
    if (widget.isRunning &&
        hasUrl &&
        (isWeb || isMobilePreview || isAndroid || isIOS)) {
      print(
        '✅ WebView Preview (${widget.platform}) → ${widget.appUrl}'
        '${isMobilePreview ? ' (marco teléfono)' : ''}',
      );
      if (!_webViewInitialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAppUrl();
        });
      }
      return _buildWebViewWithInspector();
    }

    // PRIORIDAD 3: Si es ANDROID o iOS y está ejecutándose (sin URL), mostrar mensaje de que la app está en el dispositivo
    // (Las apps nativas se ejecutan en el emulador/dispositivo real, no en el WebView)
    if ((isAndroid || isIOS) &&
        widget.isRunning &&
        (widget.appUrl == null || widget.appUrl!.isEmpty) &&
        widget.compilationProgress >= 1.0) {
      print('✅ PRIORIDAD 3: App ejecutándose en ${widget.platform.toUpperCase()} (dispositivo/emulador)');
      return Container(
        color: CursorTheme.surface,
        width: double.infinity,
        height: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 280;
            return SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 12 : 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight.isFinite
                      ? constraints.maxHeight - (compact ? 24 : 40)
                      : 0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isAndroid
                          ? Icons.android
                          : isIOS
                              ? Icons.apple
                              : Icons.web,
                      size: compact ? 40 : 56,
                      color: CursorTheme.primary,
                    ),
                    SizedBox(height: compact ? 12 : 20),
                    Text(
                      '✅ Aplicación ejecutándose',
                      style: TextStyle(
                        color: CursorTheme.textPrimary,
                        fontSize: compact ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: compact ? 8 : 12),
                    Text(
                      'La aplicación se está ejecutando en el '
                      '${isAndroid ? "emulador/dispositivo Android" : "simulador/dispositivo iOS"}.\n\n'
                      'Revisa el emulador o dispositivo físico para verla.',
                      style: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: compact ? 12 : 13,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                      softWrap: true,
                    ),
                    if (widget.child != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: compact ? 120 : 180,
                        width: double.infinity,
                        child: widget.child!,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
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
        : 'Iniciando compilación...';
    final percent = (progress * 100).toInt();
    final useIndeterminate = progress < 0.08 || progress >= 0.99;

    // FittedBox evita el stripe "OVERFLOWED BY N PIXELS" en frames bajos.
    return ColoredBox(
      color: CursorTheme.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 280.0;
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.platform.toLowerCase() == 'ios'
                            ? Icons.apple
                            : widget.platform.toLowerCase() == 'android'
                                ? Icons.android
                                : widget.platform.toLowerCase() == 'macos'
                                    ? Icons.desktop_mac
                                    : Icons.web,
                        size: 48,
                        color: CursorTheme.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        status,
                        style: const TextStyle(
                          color: CursorTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: (maxW - 32).clamp(80.0, 220.0),
                        height: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: useIndeterminate
                              ? const LinearProgressIndicator(
                                  minHeight: 6,
                                  backgroundColor: CursorTheme.surface,
                                  color: CursorTheme.primary,
                                )
                              : LinearProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: CursorTheme.surface,
                                  color: CursorTheme.primary,
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        useIndeterminate ? 'En progreso…' : '$percent%',
                        style: const TextStyle(
                          color: CursorTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
    
    // Bloque fijo centrado; FittedBox lo escala entero (sin romper líneas).
    return const ColoredBox(
      color: CursorTheme.surface,
      child: SizedBox.expand(
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    VoryxelBrandLogo(
                      iconSize: 64,
                      fontSize: 17,
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Presiona Run/Debug para iniciar',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'La aplicación aparecerá aquí',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        color: Color(0xB3858585),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
