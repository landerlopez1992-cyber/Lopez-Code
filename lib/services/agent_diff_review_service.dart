import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Un bloque de cambios (1 of N) entre el contenido previo del agente y el
/// contenido nuevo en disco. Las líneas [startLine]/[endLine] son 1-based en
/// el archivo **nuevo**. Si solo hubo borrados, [startLine] apunta a la línea
/// que queda justo después de la zona borrada (o a `lines+1` al final).
class DiffHunk {
  final String id;
  final int startLine;
  final int endLine;
  final List<String> removedLines;
  final List<String> addedLines;

  const DiffHunk({
    required this.id,
    required this.startLine,
    required this.endLine,
    required this.removedLines,
    required this.addedLines,
  });

  bool get hasAdditions => addedLines.isNotEmpty;
  bool get hasDeletions => removedLines.isNotEmpty;

  /// Índice 0-based de la primera línea añadida en el archivo nuevo.
  int get addedStart0 => math.max(0, startLine - 1);

  /// Número de líneas añadidas (0 si solo hubo borrados).
  int get addedCount => addedLines.length;

  DiffHunk copyWith({
    String? id,
    int? startLine,
    int? endLine,
    List<String>? removedLines,
    List<String>? addedLines,
  }) {
    return DiffHunk(
      id: id ?? this.id,
      startLine: startLine ?? this.startLine,
      endLine: endLine ?? this.endLine,
      removedLines: removedLines ?? this.removedLines,
      addedLines: addedLines ?? this.addedLines,
    );
  }
}

/// Revisión pendiente de un archivo editado por el agente.
class FileDiffReview {
  final String filePath;
  final String baseContent;
  final List<DiffHunk> hunks;
  final int activeIndex;

  const FileDiffReview({
    required this.filePath,
    required this.baseContent,
    required this.hunks,
    this.activeIndex = 0,
  });

  bool get isEmpty => hunks.isEmpty;
  int get length => hunks.length;

  DiffHunk? get activeHunk {
    if (hunks.isEmpty) return null;
    return hunks[activeIndex.clamp(0, hunks.length - 1)];
  }

  FileDiffReview copyWith({
    String? filePath,
    String? baseContent,
    List<DiffHunk>? hunks,
    int? activeIndex,
  }) {
    final nextHunks = hunks ?? this.hunks;
    final rawIndex = activeIndex ?? this.activeIndex;
    final nextIndex = nextHunks.isEmpty
        ? 0
        : rawIndex.clamp(0, nextHunks.length - 1);
    return FileDiffReview(
      filePath: filePath ?? this.filePath,
      baseContent: baseContent ?? this.baseContent,
      hunks: nextHunks,
      activeIndex: nextIndex,
    );
  }
}

/// Diff línea a línea (LCS / greedy) → lista de [DiffHunk].
class LineDiffer {
  static const int _lcsCellLimit = 2500000;
  static const int _contextGap = 0;

  /// Compara [before] vs [after] y agrupa cambios contiguos en hunks.
  static List<DiffHunk> computeHunks(String before, String after) {
    if (before == after) return const [];
    final a = _splitLines(before);
    final b = _splitLines(after);
    final ops = _diffOps(a, b);
    return _opsToHunks(ops);
  }

  static List<String> _splitLines(String text) {
    if (text.isEmpty) return <String>[];
    final lines = text.split('\n');
    // Un archivo "vacío" realmente vacío → 0 líneas. Si termina en \n,
    // split produce un '' final que representa la línea vacía tras el salto;
    // lo conservamos para que el diff sea fiel al contenido en disco.
    return lines;
  }

  /// equal | insert | delete
  static List<_Op> _diffOps(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 && m == 0) return const [];
    if (n == 0) {
      return [for (var j = 0; j < m; j++) _Op.insert(b[j])];
    }
    if (m == 0) {
      return [for (var i = 0; i < n; i++) _Op.delete(a[i])];
    }

    // Prefijo / sufijo comunes → reduce el núcleo del LCS.
    var start = 0;
    while (start < n && start < m && a[start] == b[start]) {
      start++;
    }
    var endA = n;
    var endB = m;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }

    final prefix = [for (var i = 0; i < start; i++) _Op.equal(a[i])];
    final suffix = [for (var i = endA; i < n; i++) _Op.equal(a[i])];
    final aMid = a.sublist(start, endA);
    final bMid = b.sublist(start, endB);
    final mid = (aMid.length + 1) * (bMid.length + 1) <= _lcsCellLimit
        ? _lcsOps(aMid, bMid)
        : _greedyOps(aMid, bMid);
    return [...prefix, ...mid, ...suffix];
  }

  static List<_Op> _lcsOps(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (a[i] == b[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = math.max(dp[i + 1][j], dp[i][j + 1]);
        }
      }
    }
    final ops = <_Op>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        ops.add(_Op.equal(a[i]));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        ops.add(_Op.delete(a[i]));
        i++;
      } else {
        ops.add(_Op.insert(b[j]));
        j++;
      }
    }
    while (i < n) {
      ops.add(_Op.delete(a[i++]));
    }
    while (j < m) {
      ops.add(_Op.insert(b[j++]));
    }
    return ops;
  }

  /// Fallback O(n+m) aproximado para archivos grandes.
  static List<_Op> _greedyOps(List<String> a, List<String> b) {
    final indexB = <String, List<int>>{};
    for (var j = 0; j < b.length; j++) {
      indexB.putIfAbsent(b[j], () => <int>[]).add(j);
    }
    final matchedB = List<bool>.filled(b.length, false);
    final matchedA = List<bool>.filled(a.length, false);
    var searchFrom = 0;
    for (var i = 0; i < a.length; i++) {
      final candidates = indexB[a[i]];
      if (candidates == null) continue;
      for (final j in candidates) {
        if (j >= searchFrom && !matchedB[j]) {
          matchedA[i] = true;
          matchedB[j] = true;
          searchFrom = j + 1;
          break;
        }
      }
    }
    final ops = <_Op>[];
    var i = 0;
    var j = 0;
    while (i < a.length || j < b.length) {
      while (i < a.length && !matchedA[i]) {
        ops.add(_Op.delete(a[i++]));
      }
      while (j < b.length && !matchedB[j]) {
        ops.add(_Op.insert(b[j++]));
      }
      if (i < a.length && j < b.length && matchedA[i] && matchedB[j]) {
        ops.add(_Op.equal(a[i]));
        i++;
        j++;
      } else if (i >= a.length && j >= b.length) {
        break;
      } else if (i >= a.length) {
        ops.add(_Op.insert(b[j++]));
      } else if (j >= b.length) {
        ops.add(_Op.delete(a[i++]));
      } else {
        // Desync del matching greedy: consumir como delete/insert.
        ops.add(_Op.delete(a[i++]));
      }
    }
    return ops;
  }

  static List<DiffHunk> _opsToHunks(List<_Op> ops) {
    final hunks = <DiffHunk>[];
    var newLine = 1; // 1-based en archivo nuevo
    var i = 0;
    var seq = 0;
    while (i < ops.length) {
      if (ops[i].type == _OpType.equal) {
        newLine++;
        i++;
        continue;
      }
      final removed = <String>[];
      final added = <String>[];
      final startLine = newLine;
      while (i < ops.length && ops[i].type != _OpType.equal) {
        if (ops[i].type == _OpType.delete) {
          removed.add(ops[i].text);
        } else {
          added.add(ops[i].text);
          newLine++;
        }
        i++;
      }
      // Saltar equal internos del gap si _contextGap > 0 (reservado).
      for (var g = 0; g < _contextGap && i < ops.length; g++) {
        if (ops[i].type == _OpType.equal) {
          i++;
          newLine++;
        }
      }
      final endLine = added.isEmpty ? startLine - 1 : newLine - 1;
      seq++;
      hunks.add(DiffHunk(
        id: 'h$seq',
        startLine: startLine,
        endLine: endLine < startLine - 1 ? startLine - 1 : endLine,
        removedLines: removed,
        addedLines: added,
      ));
    }
    return hunks;
  }

  /// Aplica el inverso de [hunk] sobre [current] (contenido nuevo).
  static String reverseHunk(String current, DiffHunk hunk) {
    final lines = _splitLines(current);
    final start0 = hunk.addedStart0;
    final count = hunk.addedCount;
    if (count > 0) {
      if (start0 > lines.length) {
        return current;
      }
      final end = math.min(start0 + count, lines.length);
      lines.replaceRange(start0, end, hunk.removedLines);
    } else {
      // Solo borrados: reinsertar removedLines en startLine-1.
      final insertAt = math.min(start0, lines.length);
      lines.insertAll(insertAt, hunk.removedLines);
    }
    return lines.join('\n');
  }
}

enum _OpType { equal, insert, delete }

class _Op {
  final _OpType type;
  final String text;
  const _Op._(this.type, this.text);
  factory _Op.equal(String t) => _Op._(_OpType.equal, t);
  factory _Op.insert(String t) => _Op._(_OpType.insert, t);
  factory _Op.delete(String t) => _Op._(_OpType.delete, t);
}

/// Estado centralizado de revisiones Keep / Undo del agente.
class AgentDiffReviewService extends ChangeNotifier {
  static final AgentDiffReviewService _instance = AgentDiffReviewService._();
  factory AgentDiffReviewService() => _instance;
  AgentDiffReviewService._();

  final Map<String, FileDiffReview> _reviews = {};
  int _revision = 0;
  int _idSeq = 0;

  int get revision => _revision;

  Map<String, FileDiffReview> get reviews =>
      Map<String, FileDiffReview>.unmodifiable(_reviews);

  bool get hasAnyPending => _reviews.values.any((r) => r.hunks.isNotEmpty);

  FileDiffReview? reviewFor(String? path) {
    if (path == null || path.isEmpty) return null;
    return _reviews[_normalize(path)];
  }

  bool hasPending(String? path) {
    final r = reviewFor(path);
    return r != null && r.hunks.isNotEmpty;
  }

  List<DiffHunk> hunksFor(String? path) =>
      List<DiffHunk>.from(reviewFor(path)?.hunks ?? const []);

  /// Registra un edit del agente. Si ya había revisión, conserva el
  /// [FileDiffReview.baseContent] original y recalcula hunks.
  void recordEdit({
    required String filePath,
    required String before,
    required String after,
  }) {
    final key = _normalize(filePath);
    if (key.isEmpty || before == after) return;

    final existing = _reviews[key];
    final base = existing?.baseContent ?? before;
    final hunks = LineDiffer.computeHunks(base, after);
    if (hunks.isEmpty) {
      if (existing != null) {
        _reviews.remove(key);
        _bump();
      }
      return;
    }
    final stamped = [
      for (final h in hunks)
        h.copyWith(id: 'h${++_idSeq}_${h.id}'),
    ];
    final keepIndex = existing == null
        ? 0
        : existing.activeIndex.clamp(0, stamped.length - 1);
    _reviews[key] = FileDiffReview(
      filePath: key,
      baseContent: base,
      hunks: stamped,
      activeIndex: keepIndex,
    );
    _bump();
  }

  void setActiveHunk(String filePath, int index) {
    final key = _normalize(filePath);
    final review = _reviews[key];
    if (review == null || review.hunks.isEmpty) return;
    final next = index.clamp(0, review.hunks.length - 1);
    if (next == review.activeIndex) return;
    _reviews[key] = review.copyWith(activeIndex: next);
    _bump();
  }

  void selectNext(String filePath) {
    final review = reviewFor(filePath);
    if (review == null || review.hunks.isEmpty) return;
    setActiveHunk(filePath, (review.activeIndex + 1) % review.hunks.length);
  }

  void selectPrevious(String filePath) {
    final review = reviewFor(filePath);
    if (review == null || review.hunks.isEmpty) return;
    final next = review.activeIndex <= 0
        ? review.hunks.length - 1
        : review.activeIndex - 1;
    setActiveHunk(filePath, next);
  }

  /// Keep: confirma el bloque y quita su resaltado.
  void acceptHunk(String filePath, String hunkId) {
    final key = _normalize(filePath);
    final review = _reviews[key];
    if (review == null) return;
    final next = review.hunks.where((h) => h.id != hunkId).toList();
    if (next.isEmpty) {
      _reviews.remove(key);
    } else {
      _reviews[key] = review.copyWith(hunks: next);
    }
    _bump();
  }

  /// Undo: revierte solo ese bloque en disco y recalcula hunks.
  Future<bool> rejectHunk(String filePath, String hunkId) async {
    final key = _normalize(filePath);
    final review = _reviews[key];
    if (review == null) return false;
    DiffHunk? hunk;
    for (final h in review.hunks) {
      if (h.id == hunkId) {
        hunk = h;
        break;
      }
    }
    if (hunk == null) return false;

    try {
      final file = File(key);
      final current = await file.exists() ? await file.readAsString() : '';
      final reverted = LineDiffer.reverseHunk(current, hunk);
      await file.parent.create(recursive: true);
      await file.writeAsString(reverted);

      final remaining = LineDiffer.computeHunks(review.baseContent, reverted);
      if (remaining.isEmpty) {
        _reviews.remove(key);
      } else {
        final stamped = [
          for (final h in remaining) h.copyWith(id: 'h${++_idSeq}_${h.id}'),
        ];
        _reviews[key] = review.copyWith(hunks: stamped);
      }
      _bump();
      return true;
    } catch (e) {
      debugPrint('AgentDiffReviewService.rejectHunk: $e');
      return false;
    }
  }

  void acceptAll(String filePath) {
    final key = _normalize(filePath);
    if (_reviews.remove(key) != null) _bump();
  }

  /// Undo File: restaura el contenido base completo.
  Future<bool> rejectAll(String filePath) async {
    final key = _normalize(filePath);
    final review = _reviews[key];
    if (review == null) return false;
    try {
      final file = File(key);
      await file.parent.create(recursive: true);
      await file.writeAsString(review.baseContent);
      _reviews.remove(key);
      _bump();
      return true;
    } catch (e) {
      debugPrint('AgentDiffReviewService.rejectAll: $e');
      return false;
    }
  }

  void clearFile(String filePath) {
    final key = _normalize(filePath);
    if (_reviews.remove(key) != null) _bump();
  }

  void clearAll() {
    if (_reviews.isEmpty) return;
    _reviews.clear();
    _bump();
  }

  /// Visible para tests: inyecta una revisión sin tocar disco.
  @visibleForTesting
  void debugSetReview(FileDiffReview review) {
    _reviews[_normalize(review.filePath)] = review;
    _bump();
  }

  @visibleForTesting
  void debugReset() {
    _reviews.clear();
    _idSeq = 0;
    _revision = 0;
  }

  String _normalize(String path) => path.trim().replaceAll('\\', '/');

  void _bump() {
    _revision++;
    notifyListeners();
  }
}
