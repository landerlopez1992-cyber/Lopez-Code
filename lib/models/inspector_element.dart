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
    return InspectorElement(
      tagName: json['tagName'] ?? 'unknown',
      id: json['id'],
      className: json['className'],
      attributes: Map<String, String>.from(json['attributes'] ?? {}),
      textContent: json['textContent'],
      computedStyles: Map<String, String>.from(json['computedStyles'] ?? {}),
      boundingRect: json['boundingRect'] != null
          ? Rect.fromJson(json['boundingRect'])
          : null,
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => InspectorElement.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      parent: null, // Se establecerá después
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
    if (id != null && id!.isNotEmpty) return '#$id';
    if (className != null && className!.isNotEmpty) {
      return '.${className!.split(' ').first}';
    }
    return tagName.toLowerCase();
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
