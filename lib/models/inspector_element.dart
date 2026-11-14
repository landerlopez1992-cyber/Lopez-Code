/// Modelo para representar un elemento del DOM detectado por el inspector
class InspectorElement {
  final String tagName;
  final String? id;
  final String? className;
  final Map<String, String> attributes;
  final String? textContent;
  final Map<String, String> computedStyles;
  final Rect? boundingRect;
  final List<InspectorElement> children;
  final InspectorElement? parent;

  InspectorElement({
    required this.tagName,
    this.id,
    this.className,
    required this.attributes,
    this.textContent,
    required this.computedStyles,
    this.boundingRect,
    required this.children,
    this.parent,
  });

  factory InspectorElement.fromJson(Map<String, dynamic> json) {
    Map<String, String> stringMap(dynamic raw) {
      if (raw is! Map) return {};
      return raw.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    }

    return InspectorElement(
      tagName: (json['tagName'] ?? 'unknown').toString(),
      id: json['id']?.toString(),
      className: json['className']?.toString(),
      attributes: stringMap(json['attributes']),
      textContent: json['textContent']?.toString(),
      computedStyles: stringMap(json['computedStyles']),
      boundingRect: json['boundingRect'] is Map
          ? Rect.fromJson(Map<String, dynamic>.from(json['boundingRect'] as Map))
          : null,
      children: (json['children'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(
                (e) => InspectorElement.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList() ??
          [],
      parent: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tagName': tagName,
      'id': id,
      'className': className,
      'attributes': attributes,
      'textContent': textContent,
      'computedStyles': computedStyles,
      'boundingRect': boundingRect?.toJson(),
      'children': children.map((e) => e.toJson()).toList(),
    };
  }

  String get displayName {
    final text = textContent?.trim() ?? '';
    final role = attributes['role']?.trim();
    final shortText =
        text.isNotEmpty && text.length <= 24 ? text : null;

    if (id != null && id!.isNotEmpty) {
      return shortText != null ? '#$id "$shortText"' : '#$id';
    }
    if (role != null && role.isNotEmpty) {
      return shortText != null ? '$role "$shortText"' : role;
    }
    if (className != null && className!.isNotEmpty) {
      final cls = '.${className!.split(' ').first}';
      return shortText != null ? '$cls "$shortText"' : cls;
    }
    final tag = tagName.toLowerCase();
    if (shortText != null) return '$tag "$shortText"';
    return tag;
  }

  /// Etiqueta corta para la lista de capas (botón / texto / contenedor…).
  String get layerLabel {
    final text = textContent?.trim() ?? '';
    final role = attributes['role']?.trim() ?? '';
    final tag = tagName.toLowerCase();
    final isSemantics =
        tag.contains('semantics') || (id?.startsWith('flt-semantic') ?? false);

    String kind;
    if (role == 'button' || tag == 'button') {
      kind = 'botón';
    } else if (role == 'text' || role == 'statictext') {
      kind = 'texto';
    } else if (text.isNotEmpty && text.length <= 3 && isSemantics) {
      kind = 'control';
    } else if (isSemantics) {
      kind = 'capa';
    } else if (tag == 'div' || tag == 'span') {
      kind = 'contenedor';
    } else {
      kind = tag;
    }

    if (text.isNotEmpty && text.length <= 20) {
      return '$kind · "$text"';
    }
    final r = boundingRect;
    if (r != null) {
      return '$kind · ${r.width.toStringAsFixed(0)}×${r.height.toStringAsFixed(0)}';
    }
    return kind;
  }

  String get fullSelector {
    final parts = <String>[];
    if (id != null && id!.isNotEmpty) {
      parts.add('#$id');
    } else {
      parts.add(tagName.toLowerCase());
      if (className != null && className!.isNotEmpty) {
        parts.add('.${className!.split(' ').join('.')}');
      }
    }
    return parts.join('');
  }
}

class Rect {
  final double x;
  final double y;
  final double width;
  final double height;

  Rect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory Rect.fromJson(Map<String, dynamic> json) {
    return Rect(
      x: (json['x'] ?? 0).toDouble(),
      y: (json['y'] ?? 0).toDouble(),
      width: (json['width'] ?? 0).toDouble(),
      height: (json['height'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }
}
