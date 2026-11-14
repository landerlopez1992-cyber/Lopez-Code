import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  /// Evita bucle loadRequest → GET log → rebuild → loadRequest…
  String? _lastLoadedUrl;
  DateTime? _lastLoadAt;
  bool _loadInFlight = false;
  bool _initialLoadScheduled = false;

  @override
  void initState() {
    super.initState();
    _inspectorMode = widget.inspectorMode;
    if (_inspectorMode) {
      InspectorSelectionService().setActive(true);
    }
    InspectorSelectionService().addListener(_onInspectorSelectionChanged);
    _initializeWebView();
    // Si ya hay una URL disponible al inicializar, cargarla (una sola vez).
    if (widget.appUrl != null && widget.appUrl!.isNotEmpty && widget.isRunning) {
      _initialLoadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAppUrl();
      });
    }
  }

  @override
  void dispose() {
    InspectorSelectionService().removeListener(_onInspectorSelectionChanged);
    super.dispose();
  }

  void _onInspectorSelectionChanged() {
    // Capas elegidas desde el panel lateral → resaltar en el preview.
    _highlightSelectedLayerInWebView();
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
            _loadInFlight = true;
            // Marcar pronto para que build() no re-dispare loads.
            if (!_webViewInitialized && mounted) {
              setState(() => _webViewInitialized = true);
            } else {
              _webViewInitialized = true;
            }
          },
          onPageFinished: (String url) {
            print('✅ WebView cargado: $url');
            _loadInFlight = false;
            if (mounted) {
              if (!_webViewInitialized) {
                setState(() => _webViewInitialized = true);
              }
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
          var oldCss = document.getElementById('__voryxel_inspector_a11y_css');
          if (oldCss) oldCss.remove();
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

        // Flutter web pinta en canvas: sin semántica solo existe flutter-view.
        // Activamos a11y para exponer flt-semantics, pero con CSS para que
        // el canvas siga visible y los nodos sean solo targets invisibles.
        function enableFlutterSemanticsForHitTest() {
          try {
            if (!document.getElementById('__voryxel_inspector_a11y_css')) {
              var css = document.createElement('style');
              css.id = '__voryxel_inspector_a11y_css';
              css.textContent = [
                'flt-glass-pane, flt-scene-host, canvas, flutter-view {',
                '  visibility: visible !important; opacity: 1 !important;',
                '}',
                'flt-semantics-host {',
                '  pointer-events: none !important;',
                '}',
                'flt-semantics, [id^="flt-semantic-node"] {',
                '  pointer-events: auto !important;',
                '  color: transparent !important;',
                '  background: transparent !important;',
                '  border: 0 !important;',
                '  box-shadow: none !important;',
                '  outline: none !important;',
                '  text-shadow: none !important;',
                '  -webkit-text-fill-color: transparent !important;',
                '}',
                'flt-semantics * {',
                '  color: transparent !important;',
                '  background: transparent !important;',
                '  -webkit-text-fill-color: transparent !important;',
                '}',
              ].join('\n');
              document.documentElement.appendChild(css);
            }
            var a11yBtn = document.querySelector('flt-semantics-placeholder') ||
              document.querySelector('[aria-label="Enable accessibility"]');
            if (a11yBtn && typeof a11yBtn.click === 'function') a11yBtn.click();
          } catch (e) {}
        }
        enableFlutterSemanticsForHitTest();
        setTimeout(enableFlutterSemanticsForHitTest, 500);
        setTimeout(enableFlutterSemanticsForHitTest, 1500);

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
                 el.id === '__inspector_label' ||
                 el.id === '__voryxel_inspector_a11y_css';
        }

        function isBoring(el) {
          if (!el || !el.tagName) return true;
          var tag = el.tagName.toLowerCase();
          if (tag === 'html' || tag === 'body' || tag === 'script' || tag === 'style') return true;
          if (tag === 'flt-glass-pane' || tag === 'flt-scene-host' || tag === 'canvas') return true;
          // Raíz del preview: no es un botón/widget concreto.
          if (tag === 'flutter-view' || tag === 'flt-semantics-host') return true;
          return false;
        }

        function nodeArea(el) {
          var rect = el.getBoundingClientRect();
          return Math.max(0, rect.width) * Math.max(0, rect.height);
        }

        function scoreElement(el) {
          if (!el || isOverlay(el) || isBoring(el)) return -1;
          var score = 1;
          var tag = el.tagName.toLowerCase();
          var role = (el.getAttribute && el.getAttribute('role')) || '';
          var label = (el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title'))) || '';
          var text = (label || el.innerText || el.textContent || '').trim().replace(/\\s+/g, ' ');

          if (tag.indexOf('flt-semantics') === 0 || (el.id && String(el.id).indexOf('flt-semantic') === 0)) {
            score += 10;
          }
          if (tag === 'button' || tag === 'a' || tag === 'input' || tag === 'textarea') score += 8;
          if (role === 'button' || role === 'textbox' || role === 'link') score += 8;
          if (label) score += 6;
          // Texto corto tipo "2", "+", "C" → muy probable control.
          if (text && text.length > 0 && text.length <= 3) score += 12;
          else if (text && text.length > 0 && text.length < 24) score += 5;
          // Penalizar nodos enormes (pantalla entera / scaffolds).
          var area = nodeArea(el);
          var vw = Math.max(1, window.innerWidth * window.innerHeight);
          if (area > 0 && area < 8000) score += 8;
          else if (area < 25000) score += 4;
          else if (area > vw * 0.45) score -= 20;
          else if (area > 120000) score -= 8;
          return score;
        }

        function containsPoint(el, x, y) {
          var r = el.getBoundingClientRect();
          return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom &&
                 r.width > 0 && r.height > 0;
        }

        function pickInspectable(x, y, fallback) {
          var stack = [];
          try { stack = document.elementsFromPoint(x, y) || []; } catch (e) {}
          // Semántica a veces no entra en elementsFromPoint; escanear nodos.
          try {
            var nodes = document.querySelectorAll('flt-semantics, [id^="flt-semantic-node"]');
            for (var n = 0; n < nodes.length; n++) {
              if (containsPoint(nodes[n], x, y)) stack.push(nodes[n]);
            }
          } catch (e2) {}

          var best = null;
          var bestScore = -1;
          var bestArea = Infinity;
          for (var i = 0; i < stack.length; i++) {
            var el = stack[i];
            if (isOverlay(el)) continue;
            var s = scoreElement(el);
            if (s < 0) continue;
            var area = nodeArea(el);
            // Mejor score; empate → el más pequeño (botón vs contenedor).
            if (s > bestScore || (s === bestScore && area < bestArea)) {
              bestScore = s;
              bestArea = area;
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

        function looksLikeBgClass(c) {
          if (!c || typeof c !== 'string') return false;
          var s = c.toLowerCase();
          return s.indexOf('bg-') >= 0 || s.indexOf('gradient') >= 0 ||
                 s.indexOf('from-') >= 0 || s.indexOf('via-') >= 0 ||
                 s.indexOf('to-') >= 0;
        }

        function collectLayersAt(x, y) {
          var stack = [];
          try { stack = document.elementsFromPoint(x, y) || []; } catch (e) {}
          try {
            var nodes = document.querySelectorAll('flt-semantics, [id^="flt-semantic-node"]');
            for (var n = 0; n < nodes.length; n++) {
              if (containsPoint(nodes[n], x, y)) stack.push(nodes[n]);
            }
          } catch (e2) {}
          var seen = {};
          var layers = [];
          for (var i = 0; i < stack.length; i++) {
            var el = stack[i];
            if (!el || isOverlay(el) || isBoring(el) || scoreElement(el) < 0) continue;
            var info = getElementInfo(el);
            if (!info || !info.boundingRect) continue;
            var key = (info.id || '') + '|' + info.tagName + '|' +
              Math.round(info.boundingRect.x) + '|' + Math.round(info.boundingRect.y) + '|' +
              Math.round(info.boundingRect.width) + '|' + Math.round(info.boundingRect.height);
            if (seen[key]) continue;
            seen[key] = true;
            layers.push(info);
          }
          layers.sort(function(a, b) {
            var aa = (a.boundingRect.width || 0) * (a.boundingRect.height || 0);
            var bb = (b.boundingRect.width || 0) * (b.boundingRect.height || 0);
            return aa - bb;
          });
          // Incluir body/html al final si pintan fondo (gradientes Tailwind).
          // isBoring los excluye del click, pero el agente necesita verlos.
          function appendPaintRoot(node) {
            if (!node || isOverlay(node)) return;
            var info = getElementInfo(node);
            if (!info) return;
            var cls = info.className || '';
            var bg = (info.computedStyles && info.computedStyles.backgroundColor) || '';
            var useful = looksLikeBgClass(cls) ||
              (bg && bg !== 'transparent' && bg.indexOf('rgba(0, 0, 0, 0)') < 0);
            if (!useful) return;
            var key = (info.id || '') + '|' + info.tagName + '|paint-root';
            if (seen[key]) return;
            seen[key] = true;
            layers.push(info);
          }
          appendPaintRoot(document.body);
          appendPaintRoot(document.documentElement);
          return layers.slice(0, 14);
        }

        function post(type, element, layers) {
          var info = getElementInfo(element);
          if (!info) return;
          if (!window.flutter_inspector || !window.flutter_inspector.postMessage) {
            ensureChannel();
          }
          if (window.flutter_inspector && window.flutter_inspector.postMessage) {
            try {
              window.flutter_inspector.postMessage(JSON.stringify({
                type: type,
                element: info,
                layers: layers || []
              }));
            } catch (e) {}
          }
        }

        function hoverElement(element, x, y) {
          if (!element || element === document.body || element === document.documentElement) return;
          currentHoveredElement = element;
          var rect = updateBox(element, highlightDiv);
          updateLabel(element, rect, false);
          var now = Date.now();
          if (now - lastHoverSentAt > 80) {
            lastHoverSentAt = now;
            var layers = (typeof x === 'number' && typeof y === 'number')
              ? collectLayersAt(x, y)
              : [];
            post('elementHovered', element, layers);
          }
        }

        function selectElement(element, x, y) {
          if (!element || element === document.body || element === document.documentElement) return;
          currentSelectedElement = element;
          currentHoveredElement = element;
          var rect = updateBox(element, selectedDiv);
          updateBox(element, highlightDiv);
          updateLabel(element, rect, true);
          var layers = (typeof x === 'number' && typeof y === 'number')
            ? collectLayersAt(x, y)
            : [];
          post('elementSelected', element, layers);
        }

        // Resalta un rect desde el panel de capas (Dart → JS).
        window.__inspectorHighlightRect = function(x, y, w, h, selected) {
          var div = selected ? selectedDiv : highlightDiv;
          if (!div) return;
          div.style.left = x + 'px';
          div.style.top = y + 'px';
          div.style.width = Math.max(0, w) + 'px';
          div.style.height = Math.max(0, h) + 'px';
          div.style.display = 'block';
          if (selected) {
            highlightDiv.style.display = 'none';
            labelDiv.style.display = 'none';
          }
        };

        function stopEvent(e) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          return false;
        }

        window.__inspectorMouseMoveHandler = function(e) {
          if (!window.__inspectorActive) return;
          var el = pickInspectable(e.clientX, e.clientY, e.target);
          if (el && el !== currentHoveredElement) {
            hoverElement(el, e.clientX, e.clientY);
          }
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
          if (el) selectElement(el, e.clientX, e.clientY);
          return stopEvent(e);
        };

        window.__inspectorTouchStartHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (e.touches && e.touches.length > 0) {
            var t = e.touches[0];
            var el = pickInspectable(t.clientX, t.clientY, document.elementFromPoint(t.clientX, t.clientY));
            if (el) hoverElement(el, t.clientX, t.clientY);
          }
          return stopEvent(e);
        };

        window.__inspectorTouchMoveHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (e.touches && e.touches.length > 0) {
            var t = e.touches[0];
            var el = pickInspectable(t.clientX, t.clientY, document.elementFromPoint(t.clientX, t.clientY));
            if (el && el !== currentHoveredElement) {
              hoverElement(el, t.clientX, t.clientY);
            }
          }
          return stopEvent(e);
        };

        window.__inspectorTouchEndHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (e.changedTouches && e.changedTouches.length > 0) {
            var t = e.changedTouches[0];
            var el = pickInspectable(t.clientX, t.clientY, document.elementFromPoint(t.clientX, t.clientY));
            if (el) selectElement(el, t.clientX, t.clientY);
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
        var a11yCss = document.getElementById('__voryxel_inspector_a11y_css');
        if (a11yCss) a11yCss.remove();
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
      final layers = (data['layers'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => InspectorElement.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList() ??
          const <InspectorElement>[];

      if (type == 'elementHovered') {
        InspectorSelectionService().setHovered(element, layers: layers);
        widget.onElementHovered?.call(element);
        return;
      }

      if (type == 'elementSelected') {
        // No setState aquí: un overlay local tapaba el WebView. El detalle
        // se muestra en InspectorMonitorPanel (fuera del teléfono).
        _selectedElement = element;
        InspectorSelectionService().setSelected(element, layers: layers);
        widget.onElementSelected?.call(element);
      }
    } catch (e) {
      print('❌ Error al procesar mensaje del inspector: $e');
    }
  }

  Future<void> _highlightSelectedLayerInWebView() async {
    if (!_inspectorMode || !_webViewInitialized) return;
    final el = InspectorSelectionService().selected ??
        InspectorSelectionService().hovered;
    final r = el?.boundingRect;
    if (r == null) return;
    final selected = InspectorSelectionService().selected != null;
    try {
      await _webViewController.runJavaScript(
        'if (window.__inspectorHighlightRect) '
        'window.__inspectorHighlightRect('
        '${r.x}, ${r.y}, ${r.width}, ${r.height}, $selected);',
      );
    } catch (_) {}
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
    
    // Cargar URL solo si cambió de verdad o acabó de quedar lista.
    // NUNCA recargar solo porque !_webViewInitialized: eso + logs GET
    // del http.server creaba un bucle infinito de recargas.
    final becameReady = widget.compilationProgress >= 1.0 &&
        oldWidget.compilationProgress < 1.0 &&
        widget.appUrl != null &&
        widget.appUrl!.isNotEmpty &&
        widget.isRunning;
    final urlChanged = widget.appUrl != oldWidget.appUrl &&
        widget.appUrl != null &&
        widget.appUrl!.isNotEmpty &&
        widget.isRunning;
    if (urlChanged || becameReady) {
      print(
        '🔄 PhoneEmulator: URL actualizada de "${oldWidget.appUrl}" '
        'a "${widget.appUrl}"${becameReady ? ' (app lista)' : ''}',
      );
      _loadAppUrl();
    }

    if (widget.isRunning && widget.appUrl == null) {
      print(
        '⚠️ PhoneEmulator: El servidor está ejecutándose pero no hay URL',
      );
    }
  }

  void _loadAppUrl({bool forceReload = false}) {
    final raw = widget.appUrl;
    if (raw == null || raw.isEmpty) {
      print('⚠️ PhoneEmulator._loadAppUrl: No hay URL disponible');
      return;
    }
    final now = DateTime.now();
    // forceReload (agente / ⚡ Preview) SIEMPRE recarga; el debounce solo
    // evita tormentas de loads accidentales.
    if (!forceReload && _loadInFlight) {
      print('⏳ PhoneEmulator: reload ignorado (carga en curso)');
      return;
    }
    if (!forceReload &&
        _lastLoadAt != null &&
        now.difference(_lastLoadAt!) < const Duration(milliseconds: 1200)) {
      print('⏳ PhoneEmulator: reload ignorado (debounce)');
      return;
    }
    // Cache-bust solo en forceReload (Hot Restart / edit del agente).
    final base = raw.split('#').first.split('?').first;
    final url = forceReload
        ? '$base?_lopez_preview=${now.millisecondsSinceEpoch}'
        : base;
    if (!forceReload && _lastLoadedUrl == url) {
      return;
    }
    _lastLoadedUrl = url;
    _lastLoadAt = now;
    _loadInFlight = true;
    print('📱 PhoneEmulator._loadAppUrl: $url (forceReload=$forceReload)');
    try {
      _webViewController.loadRequest(Uri.parse(url));
    } catch (e) {
      _loadInFlight = false;
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
            child: _buildWebViewWithInspector(),
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
            child: _buildWebViewWithInspector(),
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
    // NUNCA llamar _loadAppUrl desde build(): cada notify del Output
    // reconstruía y disparaba GET / en bucle (scroll temblequeaba).
    final hasUrl = widget.appUrl != null && widget.appUrl!.isNotEmpty;
    if (widget.isRunning &&
        hasUrl &&
        (isWeb || isMobilePreview || isAndroid || isIOS)) {
      if (!_initialLoadScheduled && _lastLoadedUrl == null) {
        _initialLoadScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadAppUrl();
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

  /// WebView del preview. El detalle del inspector NO va encima del teléfono
  /// (eso tapaba la app); vive en InspectorMonitorPanel al lado.
  Widget _buildWebViewWithInspector() {
    return WebViewWidget(controller: _webViewController);
  }
}
