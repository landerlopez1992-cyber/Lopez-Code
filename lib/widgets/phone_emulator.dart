import 'dart:async';
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
  /// `false` = ⚡ soft reload; `true` = 🔄 hard reload (cache-bust + URL raíz).
  final bool previewReloadHard;
  /// UI Builder: al soltar/mover un bloque con el mouse.
  final void Function(String blockId, double left, double top)? onUiBuilderMoved;
  /// UI Builder: reparentar bloque dentro de otro contenedor.
  final void Function(String blockId, String parentId, String? parentKind)?
      onUiBuilderReparent;
  /// UI Builder: texto editado inline (doble clic) en bloque data-voryxel-id.
  final void Function(String blockId, String text)? onUiBuilderTextEdited;
  /// Texto editado en cualquier elemento (Inspector / doble clic).
  final void Function({
    required String newText,
    String? oldText,
    String? tagName,
    String? blockId,
  })? onInspectorTextEdited;

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
    this.previewReloadHard = true,
    this.onUiBuilderMoved,
    this.onUiBuilderReparent,
    this.onUiBuilderTextEdited,
    this.onInspectorTextEdited,
  });

  @override
  State<PhoneEmulator> createState() => PhoneEmulatorState();
}

class PhoneEmulatorState extends State<PhoneEmulator> {
  late WebViewController _webViewController;
  bool _webViewInitialized = false;
  bool _inspectorMode = false;
  InspectorElement? _selectedElement;
  /// Evita bucle loadRequest → GET log → rebuild → loadRequest…
  String? _lastLoadedUrl;
  DateTime? _lastLoadAt;
  bool _loadInFlight = false;
  bool _initialLoadScheduled = false;
  /// Flash visible en Hot Restart (sin esto el HTML idéntico “parece” no recargar).
  bool _restartFlash = false;

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
    if (widget.appUrl != null && widget.appUrl!.isNotEmpty) {
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
      ..addJavaScriptChannel(
        'UiBuilderChannel',
        onMessageReceived: (JavaScriptMessage message) {
          _handleUiBuilderMessage(message.message);
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
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted) _injectUiBuilderHelpers();
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

  void _handleUiBuilderMessage(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final type = data['type']?.toString();
      if (type == 'moved') {
        final id = data['id']?.toString();
        final left = (data['left'] as num?)?.toDouble();
        final top = (data['top'] as num?)?.toDouble();
        if (id == null || left == null || top == null) return;
        widget.onUiBuilderMoved?.call(id, left, top);
        return;
      }
      if (type == 'reparent') {
        final id = data['id']?.toString();
        final parentId = data['parentId']?.toString();
        if (id == null || parentId == null || parentId.isEmpty) return;
        widget.onUiBuilderReparent?.call(
          id,
          parentId,
          data['parentKind']?.toString(),
        );
        return;
      }
      if (type == 'textEdited') {
        final id = data['id']?.toString();
        final text = data['text']?.toString();
        if (text == null) return;
        if (widget.onInspectorTextEdited != null) {
          widget.onInspectorTextEdited!(
            newText: text,
            oldText: data['oldText']?.toString(),
            tagName: data['tag']?.toString(),
            blockId: (id != null && id.isNotEmpty) ? id : null,
          );
        } else if (id != null && id.isNotEmpty) {
          widget.onUiBuilderTextEdited?.call(id, text);
        }
      }
    } catch (e) {
      print('⚠️ UiBuilderChannel: $e');
    }
  }

  /// Helpers JS: drop en coordenadas + arrastrar (document-level, no lo bloquea el Inspector).
  Future<void> _injectUiBuilderHelpers() async {
    const script = r'''
      (function() {
        if (!document.body) return;
        if (!document.getElementById('__voryxel_body_pos')) {
          var s = document.createElement('style');
          s.id = '__voryxel_body_pos';
          s.textContent = 'body{position:relative;min-height:100vh;} [data-voryxel-id]{cursor:move;} [data-voryxel-id].__voryxel-dragging{opacity:0.85;outline:2px dashed #3B82F6;} .__voryxel-drop-target{outline:2px solid #22c55e !important;outline-offset:2px;background-image:linear-gradient(0deg,rgba(34,197,94,0.08),rgba(34,197,94,0.08)) !important;} [data-voryxel-container="1"]{min-height:48px;}';
          document.documentElement.appendChild(s);
        }

        window.__voryxelResolveDrop = function(nx, ny, childKind) {
          var x = Math.max(0, Math.min(1, nx)) * (window.innerWidth || 1);
          var y = Math.max(0, Math.min(1, ny)) * (window.innerHeight || 1);
          childKind = (childKind || '').toLowerCase();
          function isTopLevel(n) {
            var p = n.parentElement;
            while (p && p !== document.body) {
              if (p.getAttribute && p.getAttribute('data-voryxel-id')) return false;
              p = p.parentElement;
            }
            return true;
          }
          function kindOf(n) {
            return ((n && n.getAttribute) ? (n.getAttribute('data-voryxel') || '') : '').toLowerCase();
          }
          function isContainer(n) {
            if (!n || !n.getAttribute) return false;
            if (n.getAttribute('data-voryxel-container') === '1') return true;
            var kind = kindOf(n);
            return kind === 'container' || kind === 'card' || kind === 'hero' ||
              kind === 'column' || kind === 'row' || kind === 'stack' ||
              kind === 'wrap' || kind === 'form' || kind === 'listview' ||
              kind === 'gridview' || kind === 'expandable' || kind === 'tabbar' ||
              kind === 'pageview' || kind === 'carousel' || kind === 'drawer' ||
              kind === 'navbar';
          }
          // Resaltar contenedores válidos mientras se resuelve el drop.
          try {
            var prev = document.querySelectorAll('.__voryxel-drop-target');
            for (var pi = 0; pi < prev.length; pi++) prev[pi].classList.remove('__voryxel-drop-target');
          } catch (e0) {}
          var nodes = Array.prototype.slice.call(document.querySelectorAll('[data-voryxel-id]'));
          var top = nodes.filter(isTopLevel);
          var parentId = null, parentKind = null, beforeId = null, afterId = null;
          var el = null;
          try { el = document.elementFromPoint(x, y); } catch (e) {}
          var cur = el;
          while (cur && cur !== document.body && cur !== document.documentElement) {
            try {
              if (isContainer(cur) && cur.getAttribute('data-voryxel-id')) {
                parentId = cur.getAttribute('data-voryxel-id');
                parentKind = kindOf(cur);
                try { cur.classList.add('__voryxel-drop-target'); } catch (e3) {}
                break;
              }
            } catch (e2) {}
            cur = cur.parentElement;
          }
          if (!parentId) {
            for (var i = 0; i < top.length; i++) {
              var r = top[i].getBoundingClientRect();
              var mid = r.top + r.height / 2;
              if (y < mid) { beforeId = top[i].getAttribute('data-voryxel-id'); break; }
              afterId = top[i].getAttribute('data-voryxel-id');
            }
          }
          return JSON.stringify({
            parentId: parentId,
            parentKind: parentKind,
            beforeId: beforeId,
            afterId: afterId,
            childKind: childKind,
            x: Math.round(x + (window.scrollX || 0)),
            y: Math.round(y + (window.scrollY || 0)),
            placeAbsolute: false
          });
        };

        // Drag a nivel document: el Inspector ya no se traga el mousedown.
        if (!window.__voryxelMoveInstalled) {
          window.__voryxelMoveInstalled = true;
          window.__voryxelMoveId = null;
          window.__voryxelDragging = false;
          var primed = false, dragging = false, sx = 0, sy = 0, ol = 0, ot = 0, el = null;

          function currentEl() {
            var id = window.__voryxelMoveId;
            if (!id) return null;
            return document.querySelector('[data-voryxel-id="' + id + '"]');
          }

          document.addEventListener('mousedown', function(e) {
            if (e.button !== 0) return;
            var t = e.target;
            var hit = null;
            while (t && t !== document.body) {
              if (t.getAttribute && t.getAttribute('data-voryxel-id')) {
                hit = t; break;
              }
              t = t.parentElement;
            }
            if (!hit) return;
            var id = hit.getAttribute('data-voryxel-id');
            // Preferir el seleccionado; si no, el que se clickeó.
            if (window.__voryxelMoveId && window.__voryxelMoveId !== id) {
              // Si hay uno seleccionado y clickeas otro, no arrastrar el viejo.
              if (!window.__inspectorActive) return;
            }
            window.__voryxelMoveId = id;
            el = hit;
            primed = true;
            dragging = false;
            sx = e.clientX; sy = e.clientY;
          }, true);

          document.addEventListener('mousemove', function(e) {
            if (!primed && !dragging) return;
            el = el || currentEl();
            if (!el) return;
            var dx = e.clientX - sx, dy = e.clientY - sy;
            if (!dragging) {
              if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
              dragging = true;
              window.__voryxelDragging = true;
              primed = false;
              el.classList.add('__voryxel-dragging');
              // Layout flow (FlutterFlow): no sacar a absolute; solo preview con translate.
              ol = 0; ot = 0;
              sx = e.clientX; sy = e.clientY;
            }
            try { e.preventDefault(); e.stopPropagation(); } catch (e1) {}
            el.style.transform = 'translate(' + (e.clientX - sx) + 'px,' + (e.clientY - sy) + 'px)';
          }, true);

          document.addEventListener('mouseup', function(e) {
            primed = false;
            if (!dragging) return;
            dragging = false;
            window.__voryxelDragging = false;
            el = el || currentEl();
            if (el) {
              el.classList.remove('__voryxel-dragging');
              el.style.transform = '';
            }
            // Reparent si se suelta sobre otro contenedor válido.
            try {
              var dropX = e && e.clientX != null ? e.clientX : 0;
              var dropY = e && e.clientY != null ? e.clientY : 0;
              var hit = null;
              try { hit = document.elementFromPoint(dropX, dropY); } catch (e4) {}
              var targetParent = null;
              var cur = hit;
              while (cur && cur !== document.body) {
                if (cur !== el && isContainer(cur) && cur.getAttribute('data-voryxel-id')) {
                  targetParent = cur; break;
                }
                cur = cur.parentElement;
              }
              // No persistir absolute; el reorden se hace con Subir/Bajar.
              if (el && typeof UiBuilderChannel !== 'undefined' && targetParent) {
                var ownParent = el.parentElement;
                while (ownParent && ownParent !== document.body) {
                  if (ownParent.getAttribute && ownParent.getAttribute('data-voryxel-id')) break;
                  ownParent = ownParent.parentElement;
                }
                var tid = targetParent.getAttribute('data-voryxel-id');
                var oid = ownParent && ownParent.getAttribute ? ownParent.getAttribute('data-voryxel-id') : null;
                if (tid && tid !== oid) {
                  UiBuilderChannel.postMessage(JSON.stringify({
                    type: 'reparent',
                    id: window.__voryxelMoveId,
                    parentId: tid,
                    parentKind: (targetParent.getAttribute('data-voryxel') || '')
                  }));
                }
              }
            } catch (e3) {}
          }, true);
        }

        function isContainer(n) {
          if (!n || !n.getAttribute) return false;
          if (n.getAttribute('data-voryxel-container') === '1') return true;
          var kind = (n.getAttribute('data-voryxel') || '').toLowerCase();
          return kind === 'container' || kind === 'card' || kind === 'hero' ||
            kind === 'column' || kind === 'row' || kind === 'stack' ||
            kind === 'wrap' || kind === 'form' || kind === 'listview' ||
            kind === 'gridview' || kind === 'expandable';
        }

        window.__voryxelBindMove = function(id) {
          window.__voryxelMoveId = id;
          var el = document.querySelector('[data-voryxel-id="' + id + '"]');
          if (el) el.style.cursor = 'move';
        };

        // Subir/Bajar: el host reordena el HTML en flow (no absolute).
        window.__voryxelNudge = function(id, dy) {
          return JSON.stringify({ ok: false });
        };

        // Doble clic texto (una sola vez).
        if (!window.__voryxelTextInstalled) {
          window.__voryxelTextInstalled = true;
          document.addEventListener('dblclick', function(e) {
            if (!window.__inspectorActive) return;
            var root = e.target;
            while (root && root !== document.body) {
              if (root.getAttribute && root.getAttribute('data-voryxel-id')) break;
              root = root.parentElement;
            }
            if (!root || !root.getAttribute) return;
            var id = root.getAttribute('data-voryxel-id');
            var target = e.target;
            var tag = (target.tagName || '').toLowerCase();
            var editable = {h1:1,h2:1,h3:1,h4:1,h5:1,h6:1,p:1,span:1,a:1,button:1,li:1,strong:1,label:1};
            if (!editable[tag]) {
              target = root.querySelector('h1,h2,h3,h4,h5,h6,p,a,button,span,li,strong,label');
            }
            if (!target) return;
            e.preventDefault(); e.stopPropagation();
            target.setAttribute('contenteditable', 'true');
            target.focus();
            function finish() {
              target.removeAttribute('contenteditable');
              target.removeEventListener('blur', finish);
              var text = (target.innerText || target.textContent || '').trim();
              try {
                if (typeof UiBuilderChannel !== 'undefined') {
                  UiBuilderChannel.postMessage(JSON.stringify({
                    type: 'textEdited', id: id, text: text
                  }));
                }
              } catch (e5) {}
            }
            target.addEventListener('blur', finish);
          }, true);
        }
      })();
    ''';
    try {
      await _webViewController.runJavaScript(script);
    } catch (e) {
      print('⚠️ UiBuilder helpers: $e');
    }
  }

  /// Subir/Bajar visual: mueve `top` en el DOM y devuelve left/top.
  Future<({double left, double top})?> nudgeUiBuilderBlock(
    String blockId, {
    required int direction,
  }) async {
    if (!_webViewInitialized || blockId.isEmpty) return null;
    try {
      await _injectUiBuilderHelpers();
      final dy = direction < 0 ? -48.0 : 48.0;
      final raw = await _webViewController.runJavaScriptReturningResult(
        'window.__voryxelNudge(${jsonEncode(blockId)}, $dy)',
      );
      var text = raw?.toString() ?? '';
      if (text.startsWith('"') && text.endsWith('"')) {
        text = text.substring(1, text.length - 1).replaceAll(r'\"', '"');
      }
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['ok'] == true) {
        return (
          left: (decoded['left'] as num?)?.toDouble() ?? 0,
          top: (decoded['top'] as num?)?.toDouble() ?? 0,
        );
      }
    } catch (e) {
      print('⚠️ nudgeUiBuilderBlock: $e');
    }
    return null;
  }

  /// Resuelve dónde insertar según coords normalizadas (0..1) del Preview.
  Future<Map<String, dynamic>?> resolveUiBuilderDrop({
    required double nx,
    required double ny,
    String? childKind,
  }) async {
    if (!_webViewInitialized) return null;
    try {
      await _injectUiBuilderHelpers();
      final kindArg = jsonEncode(childKind ?? '');
      final raw = await _webViewController.runJavaScriptReturningResult(
        'window.__voryxelResolveDrop(${nx.toStringAsFixed(4)}, ${ny.toStringAsFixed(4)}, $kindArg)',
      );
      final text = raw?.toString() ?? '';
      // WKWebView a veces envuelve el string entre comillas.
      var cleaned = text.trim();
      if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
        cleaned = cleaned.substring(1, cleaned.length - 1)
            .replaceAll(r'\"', '"');
      }
      final decoded = jsonDecode(cleaned);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      print('⚠️ resolveUiBuilderDrop: $e');
    }
    return null;
  }

  Future<void> bindUiBuilderMove(String blockId) async {
    if (!_webViewInitialized || blockId.isEmpty) return;
    try {
      await _injectUiBuilderHelpers();
      await _webViewController.runJavaScript(
        'window.__voryxelBindMove(${jsonEncode(blockId)});',
      );
    } catch (e) {
      print('⚠️ bindUiBuilderMove: $e');
    }
  }

  /// Actualiza el texto del elemento seleccionado en el DOM (sin recargar).
  Future<void> patchSelectedText(String text) async {
    await patchSelectedProps(text: text);
  }

  /// Aplica props al elemento seleccionado en el DOM (sin recargar Preview).
  Future<void> patchSelectedProps({
    String? text,
    String? width,
    String? height,
    String? color,
    String? backgroundColor,
    String? fontSize,
    String? borderRadius,
    String? opacity,
    String? href,
    String? src,
  }) async {
    if (!_webViewInitialized) return;
    try {
      final payload = <String, dynamic>{
        if (text != null) 'text': text,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (color != null) 'color': color,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        if (fontSize != null) 'fontSize': fontSize,
        if (borderRadius != null) 'borderRadius': borderRadius,
        if (opacity != null) 'opacity': opacity,
        if (href != null) 'href': href,
        if (src != null) 'src': src,
      };
      if (payload.isEmpty) return;
      final safe = jsonEncode(payload);
      await _webViewController.runJavaScript('''
        (function() {
          var p = $safe;
          var el = window.__inspectorSelectedEl || window.__inspectorLastSelected || null;
          if (!el) return;
          var tag = (el.tagName || '').toLowerCase();
          if (typeof p.text === 'string' && tag !== 'img' && tag !== 'input') {
            var editable = {h1:1,h2:1,h3:1,h4:1,h5:1,h6:1,p:1,span:1,a:1,button:1,li:1,strong:1,label:1,div:1};
            var target = editable[tag] ? el : (el.querySelector('h1,h2,h3,h4,h5,h6,p,a,button,span,li,strong,label') || el);
            target.textContent = p.text;
          }
          function setStyle(k, v) {
            if (v == null || v === '') return;
            try { el.style[k] = v; } catch (e1) {}
          }
          setStyle('width', p.width);
          setStyle('height', p.height);
          setStyle('color', p.color);
          setStyle('backgroundColor', p.backgroundColor);
          setStyle('fontSize', p.fontSize);
          setStyle('borderRadius', p.borderRadius);
          setStyle('opacity', p.opacity);
          if (typeof p.src === 'string' && p.src) {
            try {
              if (tag === 'img') el.setAttribute('src', p.src);
              else {
                var img = el.querySelector('img');
                if (img) img.setAttribute('src', p.src);
              }
            } catch (e2) {}
          }
          if (typeof p.href === 'string' && p.href) {
            try {
              if (tag === 'a') {
                el.setAttribute('href', p.href);
              } else if (tag === 'img') {
                if (el.parentElement && (el.parentElement.tagName || '').toLowerCase() === 'a') {
                  el.parentElement.setAttribute('href', p.href);
                } else {
                  var a = document.createElement('a');
                  a.setAttribute('href', p.href);
                  el.parentNode && el.parentNode.insertBefore(a, el);
                  a.appendChild(el);
                }
              } else {
                el.setAttribute('data-href', p.href);
                el.style.cursor = 'pointer';
                el.onclick = function(ev) {
                  ev.preventDefault();
                  try { window.location.href = p.href; } catch (e3) {}
                };
              }
            } catch (e4) {}
          }
          try {
            var r = el.getBoundingClientRect();
            if (window.__inspectorHighlightRect) {
              window.__inspectorHighlightRect(r.left, r.top, r.width, r.height, true);
            }
          } catch (e5) {}
        })();
      ''');
    } catch (e) {
      print('⚠️ patchSelectedProps: $e');
    }
  }

  /// Inyecta el script JavaScript para el inspector de elementos
  Future<void> _injectInspectorScript() async {
    const script = r'''
      (function() {
        function teardown() {
          if (!window.__inspectorActive) return;
          [
            ['click', window.__inspectorClickHandler],
            ['dblclick', window.__inspectorDblClickHandler],
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
        var lastClickKey = '';
        var lastClickLayerIdx = 0;
        var lastLayersAtPoint = [];

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
          // UI Builder: preferir nodos con data-voryxel-id.
          try {
            if (el.getAttribute && el.getAttribute('data-voryxel-id')) score += 25;
            else if (el.getAttribute && el.getAttribute('data-voryxel')) score += 12;
          } catch (e3) {}
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

        function measureHighlightRect(element) {
          var full = element.getBoundingClientRect();
          var tag = (element.tagName || '').toLowerCase();
          var textLike = tag === 'h1' || tag === 'h2' || tag === 'h3' ||
            tag === 'h4' || tag === 'h5' || tag === 'h6' || tag === 'p' ||
            tag === 'span' || tag === 'a' || tag === 'label' || tag === 'li' ||
            tag === 'button' || tag === 'strong' || tag === 'em';
          if (!textLike || full.height < 8) return full;
          try {
            var range = document.createRange();
            range.selectNodeContents(element);
            var cr = range.getBoundingClientRect();
            // Si hay "hueco" (height CSS / line-box inflado), ajustar al texto real.
            if (cr.height > 4 && cr.width > 4 && cr.height < full.height * 0.82) {
              var top = Math.max(full.top, cr.top - 2);
              var height = Math.min(full.height, cr.height + 6);
              return {
                left: full.left,
                top: top,
                width: full.width,
                height: height,
                right: full.left + full.width,
                bottom: top + height,
                x: full.left,
                y: top
              };
            }
          } catch (eMeas) {}
          return full;
        }

        function updateBox(element, div) {
          if (!element || element === document.body || element === document.documentElement) {
            div.style.display = 'none';
            return null;
          }
          var rect = measureHighlightRect(element);
          div.style.left = rect.left + 'px';
          div.style.top = rect.top + 'px';
          div.style.width = Math.max(0, rect.width) + 'px';
          div.style.height = Math.max(0, rect.height) + 'px';
          div.style.display = 'block';
          return rect;
        }

        function layerKindName(el) {
          if (!el || !el.tagName) return 'nodo';
          try {
            var vk = (el.getAttribute && el.getAttribute('data-voryxel')) || '';
            vk = String(vk).toLowerCase();
            if (vk) {
              if (vk === 'container' || vk === 'column' || vk === 'row' ||
                  vk === 'stack' || vk === 'card' || vk === 'wrap') return vk;
              if (vk === 'button' || vk === 'base_button') return 'botón';
              if (vk === 'text' || vk === 'heading' || vk === 'richtext') return 'texto';
              if (vk === 'image' || vk === 'circle_image') return 'imagen';
              return vk;
            }
          } catch (e0) {}
          var tag = (el.tagName || '').toLowerCase();
          var role = (el.getAttribute && el.getAttribute('role')) || '';
          if (tag === 'button' || role === 'button') return 'botón';
          if (tag === 'a') return 'enlace';
          if (tag === 'img') return 'imagen';
          if (tag === 'p' || tag === 'span' || tag === 'h1' || tag === 'h2' ||
              tag === 'h3' || tag === 'h4' || tag === 'label') return 'texto';
          if (tag === 'div' || tag === 'section' || tag === 'main') return 'contenedor';
          return tag;
        }

        function shortLayerLabel(el) {
          var kind = layerKindName(el);
          var text = (el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title'))) ||
                     (el.innerText || el.textContent || '');
          text = (text || '').trim().replace(/\s+/g, ' ').substring(0, 18);
          return text ? (kind + ' "' + text + '"') : kind;
        }

        function updateLabel(element, rect, selected, layers) {
          if (!element || !rect) {
            labelDiv.style.display = 'none';
            return;
          }
          var size = Math.round(rect.width) + '×' + Math.round(rect.height);
          var path = '';
          if (layers && layers.length > 1) {
            // layers: pequeño→grande; mostrar padre › … › hijo (máx 3).
            var names = [];
            var take = Math.min(3, layers.length);
            for (var li = take - 1; li >= 0; li--) {
              var L = layers[li];
              var kind = (L && L.attributes && L.attributes['data-voryxel']) ||
                         (L && L.tagName ? String(L.tagName).toLowerCase() : 'nodo');
              kind = String(kind).toLowerCase();
              if (kind === 'button' || kind === 'base_button') kind = 'botón';
              if (kind === 'text' || kind === 'heading') kind = 'texto';
              if (kind === 'image') kind = 'imagen';
              if (kind === 'a') kind = 'enlace';
              if (kind === 'div' || kind === 'section') kind = 'contenedor';
              var tx = (L && L.textContent) ? String(L.textContent).trim().replace(/\s+/g, ' ').substring(0, 14) : '';
              names.push(tx ? (kind + ' "' + tx + '"') : kind);
            }
            path = names.join(' › ');
          } else {
            path = shortLayerLabel(element);
          }
          labelDiv.textContent = (selected ? '✓ ' : '') + path + '  ' + size;
          labelDiv.style.borderColor = selected ? 'rgba(34,197,94,0.55)' : 'rgba(59,130,246,0.55)';
          labelDiv.style.maxWidth = '320px';
          var left = rect.left;
          var top = rect.top - 26;
          if (top < 4) top = rect.bottom + 6;
          if (left + 280 > window.innerWidth) left = Math.max(4, window.innerWidth - 290);
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
          var layers = (typeof x === 'number' && typeof y === 'number')
            ? collectLayersAt(x, y)
            : [];
          lastLayersAtPoint = layers;
          var rect = updateBox(element, highlightDiv);
          updateLabel(element, rect, false, layers);
          var now = Date.now();
          if (now - lastHoverSentAt > 80) {
            lastHoverSentAt = now;
            post('elementHovered', element, layers);
          }
        }

        function nearestVoryxel(el) {
          var cur = el;
          while (cur && cur !== document.body && cur !== document.documentElement) {
            try {
              if (cur.getAttribute && cur.getAttribute('data-voryxel-id')) return cur;
            } catch (e4) {}
            cur = cur.parentElement;
          }
          return el;
        }

        function liveNodeFromLayerInfo(info) {
          if (!info || !info.boundingRect) return null;
          var r = info.boundingRect;
          var stack = [];
          try {
            stack = document.elementsFromPoint(r.x + r.width / 2, r.y + r.height / 2) || [];
          } catch (e5) {}
          for (var i = 0; i < stack.length; i++) {
            var el = stack[i];
            if (!el || isOverlay(el) || isBoring(el)) continue;
            var er = el.getBoundingClientRect();
            if (Math.abs(er.x - r.x) < 2 && Math.abs(er.y - r.y) < 2 &&
                Math.abs(er.width - r.width) < 2 && Math.abs(er.height - r.height) < 2) {
              return el;
            }
            var tag = (el.tagName || '').toLowerCase();
            if (tag === String(info.tagName || '').toLowerCase() &&
                Math.abs(er.width - r.width) < 4 && Math.abs(er.height - r.height) < 4) {
              return el;
            }
          }
          return null;
        }

        function selectElement(element, x, y, opts) {
          if (!element || element === document.body || element === document.documentElement) return;
          opts = opts || {};
          var layers = (typeof x === 'number' && typeof y === 'number')
            ? collectLayersAt(x, y)
            : (lastLayersAtPoint || []);
          lastLayersAtPoint = layers;

          // Alt/⌥+clic o segundo clic en el mismo punto → subir de capa (padre).
          var clickKey = Math.round(x || 0) + ',' + Math.round(y || 0);
          var cycleUp = !!(opts.altKey || opts.metaKey);
          if (!cycleUp && clickKey === lastClickKey && currentSelectedElement) {
            cycleUp = true;
          }
          if (cycleUp && layers.length > 1) {
            var idx = lastClickLayerIdx + 1;
            if (idx >= layers.length) idx = 0;
            lastClickLayerIdx = idx;
            var picked = liveNodeFromLayerInfo(layers[idx]);
            if (picked) element = picked;
          } else {
            lastClickLayerIdx = 0;
          }
          lastClickKey = clickKey;

          // Si el nodo clicado ya tiene data-voryxel-id, editar ESE bloque.
          // Si no, subir al ancestro UI Builder para poder persistir.
          try {
            if (!(element.getAttribute && element.getAttribute('data-voryxel-id'))) {
              element = nearestVoryxel(element);
            }
          } catch (e6) {
            element = nearestVoryxel(element);
          }

          currentSelectedElement = element;
          currentHoveredElement = element;
          window.__inspectorLastSelected = element;
          window.__inspectorSelectedEl = element;
          var rect = updateBox(element, selectedDiv);
          updateBox(element, highlightDiv);
          updateLabel(element, rect, true, layers);
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
          if (window.__voryxelDragging) return;
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
              updateLabel(currentSelectedElement, rect, true, lastLayersAtPoint);
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
          // No bloquear drag de widgets UI Builder.
          var t = e.target;
          while (t && t !== document.body) {
            if (t.getAttribute && t.getAttribute('data-voryxel-id')) return;
            t = t.parentElement;
          }
          stopEvent(e);
        };

        window.__inspectorClickHandler = function(e) {
          if (!window.__inspectorActive) return;
          if (window.__voryxelDragging) return stopEvent(e);
          var el = pickInspectable(e.clientX, e.clientY, e.target);
          if (el) {
            selectElement(el, e.clientX, e.clientY, {
              altKey: !!(e.altKey || e.metaKey)
            });
          }
          return stopEvent(e);
        };

        // Doble clic → editar texto encima (cualquier h1–p/a/button…).
        window.__inspectorDblClickHandler = function(e) {
          if (!window.__inspectorActive) return;
          var target = e.target;
          if (!target || !target.tagName) return;
          var tag = (target.tagName || '').toLowerCase();
          var editable = {h1:1,h2:1,h3:1,h4:1,h5:1,h6:1,p:1,span:1,a:1,button:1,li:1,strong:1,label:1};
          if (!editable[tag]) {
            var cur = target;
            while (cur && cur !== document.body) {
              tag = (cur.tagName || '').toLowerCase();
              if (editable[tag]) { target = cur; break; }
              cur = cur.parentElement;
            }
            if (!editable[tag]) return;
          }
          e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
          selectElement(target, e.clientX, e.clientY);
          var oldText = (target.innerText || target.textContent || '').trim();
          var blockId = '';
          try {
            var n = target;
            while (n && n !== document.body) {
              if (n.getAttribute && n.getAttribute('data-voryxel-id')) {
                blockId = n.getAttribute('data-voryxel-id') || '';
                break;
              }
              n = n.parentElement;
            }
          } catch (e0) {}
          target.setAttribute('contenteditable', 'true');
          target.focus();
          try {
            var range = document.createRange();
            range.selectNodeContents(target);
            var sel = window.getSelection();
            sel.removeAllRanges(); sel.addRange(range);
          } catch (e1) {}
          function finish() {
            target.removeAttribute('contenteditable');
            target.removeEventListener('blur', finish);
            target.removeEventListener('keydown', onKey);
            var text = (target.innerText || target.textContent || '').trim();
            try {
              if (typeof UiBuilderChannel !== 'undefined') {
                UiBuilderChannel.postMessage(JSON.stringify({
                  type: 'textEdited',
                  id: blockId,
                  text: text,
                  oldText: oldText,
                  tag: (target.tagName || '').toLowerCase()
                }));
              }
            } catch (e2) {}
          }
          function onKey(ev) {
            if (ev.key === 'Enter' && !ev.shiftKey) { ev.preventDefault(); target.blur(); }
            if (ev.key === 'Escape') { target.blur(); }
          }
          target.addEventListener('blur', finish);
          target.addEventListener('keydown', onKey);
          return false;
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
        document.addEventListener('dblclick', window.__inspectorDblClickHandler, true);
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
          ['dblclick', window.__inspectorDblClickHandler],
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
        final vid = element.attributes['data-voryxel-id'];
        if (vid != null && vid.isNotEmpty) {
          unawaited(bindUiBuilderMove(vid));
        }
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

    // ⚡ soft vs 🔄 hard — botones distintos.
    if (widget.previewReloadNonce != oldWidget.previewReloadNonce &&
        widget.previewReloadNonce > 0 &&
        widget.appUrl != null &&
        widget.appUrl!.isNotEmpty) {
      if (widget.previewReloadHard) {
        print(
          '🔄 PhoneEmulator: Hot Restart / hard reload '
          '(${oldWidget.previewReloadNonce} → ${widget.previewReloadNonce})',
        );
        _flashAndHardReload();
      } else {
        print(
          '⚡ PhoneEmulator: Hot Reload / soft reload '
          '(${oldWidget.previewReloadNonce} → ${widget.previewReloadNonce})',
        );
        _softReloadPreview();
      }
    }
    
    // Cargar URL solo si cambió de verdad o acabó de quedar lista.
    // NUNCA recargar solo porque !_webViewInitialized: eso + logs GET
    // del http.server creaba un bucle infinito de recargas.
    final hasUrl = widget.appUrl != null && widget.appUrl!.isNotEmpty;
    final becameReady = widget.compilationProgress >= 1.0 &&
        oldWidget.compilationProgress < 1.0 &&
        hasUrl;
    final urlChanged = widget.appUrl != oldWidget.appUrl && hasUrl;
    final designBecameVisible = hasUrl &&
        (oldWidget.appUrl == null || oldWidget.appUrl!.isEmpty);
    if (urlChanged || becameReady || designBecameVisible) {
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

  /// Muestra un flash breve y luego hard-reload (cache-bust).
  /// Así el usuario ve que el Preview se reinició aunque el HTML no cambie.
  void _flashAndHardReload() {
    if (!mounted) return;
    setState(() => _restartFlash = true);
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _loadAppUrl(forceReload: true);
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (mounted) setState(() => _restartFlash = false);
      });
    });
  }

  /// ⚡ Soft: recarga la página actual sin cache-bust (estado de scroll/ruta
  /// del documento se refresca, pero sin forzar URL raíz nueva).
  void _softReloadPreview() {
    if (!_webViewInitialized) {
      _loadAppUrl(forceReload: false);
      return;
    }
    final now = DateTime.now();
    _lastLoadAt = now;
    _loadInFlight = true;
    print('⚡ PhoneEmulator: WebView.reload() (Hot Reload)');
    try {
      _webViewController.reload();
    } catch (e) {
      _loadInFlight = false;
      print('❌ Soft reload falló, hard fallback: $e');
      _loadAppUrl(forceReload: true);
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
        ? '$base?_voryxel_preview=${now.millisecondsSinceEpoch}'
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
        if (widget.appUrl != null && widget.appUrl!.isNotEmpty) {
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
        if (widget.appUrl != null && widget.appUrl!.isNotEmpty) {
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

    // Padding del borde (6+6=12) para que el Column no pida más alto que el marco.
    const borderW = 6.0;
    return SizedBox(
      width: frameW,
      height: frameH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: Colors.grey.shade800,
            width: borderW,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(borderW),
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
                              if (_webViewInitialized &&
                                  widget.appUrl != null &&
                                  widget.appUrl!.isNotEmpty) {
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
        statusLower.contains('syncing') ||
        statusLower.contains('running');
    final hasUrl = widget.appUrl != null && widget.appUrl!.isNotEmpty;
    // Si está Running pero aún no hay URL → progreso, no el placeholder HTML.
    final isBuilding = widget.isRunning &&
        (!hasUrl ||
            widget.compilationProgress < 1.0 ||
            stillLaunching ||
            widget.compilationProgress < 0.95);
    if (isBuilding && !hasUrl) {
      print(
        '⏳ PRIORIDAD build: Compilando (${widget.compilationProgress}) '
        '· ${widget.compilationStatus}',
      );
      return _buildCompilationProgress();
    }

    // WebView: Web full-bleed O Android/iOS Preview dentro del marco.
    // NUNCA llamar _loadAppUrl desde build(): cada notify del Output
    // reconstruía y disparaba GET / en bucle (scroll temblequeaba).
    // Diseño HTML o Run: con URL basta para mostrar el WebView.
    if (hasUrl &&
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
                      'Sin Preview todavía',
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
                      'Pulsa Run (Web) o abre un proyecto HTML',
                      textAlign: TextAlign.center,
                      maxLines: 2,
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
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _webViewController),
        if (_restartFlash)
          ColoredBox(
            color: const Color(0xE6080A0E),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CursorTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Reiniciando Preview…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
