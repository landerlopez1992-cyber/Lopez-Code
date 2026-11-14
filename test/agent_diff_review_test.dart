import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopez_code_ai/services/agent_diff_review_service.dart';

void main() {
  late AgentDiffReviewService service;

  setUp(() {
    service = AgentDiffReviewService()..debugReset();
  });

  group('LineDiffer.computeHunks', () {
    test('detecta inserción, borrado y reemplazo', () {
      const before = 'a\nb\nc\nd\n';
      const after = 'a\nX\nc\nY\n';
      final hunks = LineDiffer.computeHunks(before, after);
      expect(hunks.length, greaterThanOrEqualTo(2));

      final flatRemoved = hunks.expand((h) => h.removedLines).toList();
      final flatAdded = hunks.expand((h) => h.addedLines).toList();
      expect(flatRemoved, containsAll(['b', 'd']));
      expect(flatAdded, containsAll(['X', 'Y']));
    });

    test('archivo nuevo completo es un solo hunk de adiciones', () {
      const after = 'line1\nline2\nline3';
      final hunks = LineDiffer.computeHunks('', after);
      expect(hunks, hasLength(1));
      expect(hunks.first.removedLines, isEmpty);
      expect(hunks.first.addedLines, ['line1', 'line2', 'line3']);
      expect(hunks.first.startLine, 1);
      expect(hunks.first.endLine, 3);
    });

    test('sin cambios → lista vacía', () {
      expect(LineDiffer.computeHunks('same\n', 'same\n'), isEmpty);
    });

    test('solo borrados deja startLine en la línea ancla', () {
      const before = 'keep\ngone\nkeep2';
      const after = 'keep\nkeep2';
      final hunks = LineDiffer.computeHunks(before, after);
      expect(hunks, hasLength(1));
      expect(hunks.first.removedLines, ['gone']);
      expect(hunks.first.addedLines, isEmpty);
      expect(hunks.first.startLine, 2);
    });
  });

  group('reverseHunk', () {
    test('deshace un reemplazo parcial', () {
      const current = 'a\nNEW\nc';
      const hunk = DiffHunk(
        id: 'h1',
        startLine: 2,
        endLine: 2,
        removedLines: ['OLD'],
        addedLines: ['NEW'],
      );
      expect(LineDiffer.reverseHunk(current, hunk), 'a\nOLD\nc');
    });

    test('deshace solo inserciones', () {
      const current = 'a\nb\nc';
      const hunk = DiffHunk(
        id: 'h1',
        startLine: 2,
        endLine: 2,
        removedLines: [],
        addedLines: ['b'],
      );
      expect(LineDiffer.reverseHunk(current, hunk), 'a\nc');
    });

    test('restaura solo borrados', () {
      const current = 'a\nc';
      const hunk = DiffHunk(
        id: 'h1',
        startLine: 2,
        endLine: 1,
        removedLines: ['b'],
        addedLines: [],
      );
      expect(LineDiffer.reverseHunk(current, hunk), 'a\nb\nc');
    });
  });

  group('AgentDiffReviewService Keep / Undo', () {
    test('acceptHunk quita el bloque sin tocar el resto', () {
      service.debugSetReview(
        FileDiffReview(
          filePath: '/tmp/demo.dart',
          baseContent: 'a\nb\nc',
          hunks: const [
            DiffHunk(
              id: 'h1',
              startLine: 1,
              endLine: 1,
              removedLines: ['a'],
              addedLines: ['A'],
            ),
            DiffHunk(
              id: 'h2',
              startLine: 3,
              endLine: 3,
              removedLines: ['c'],
              addedLines: ['C'],
            ),
          ],
        ),
      );

      service.acceptHunk('/tmp/demo.dart', 'h1');
      final review = service.reviewFor('/tmp/demo.dart')!;
      expect(review.hunks, hasLength(1));
      expect(review.hunks.first.id, 'h2');
    });

    test('acceptAll limpia la revisión del archivo', () {
      service.recordEdit(
        filePath: '/tmp/x.dart',
        before: 'old',
        after: 'new',
      );
      expect(service.hasPending('/tmp/x.dart'), isTrue);
      service.acceptAll('/tmp/x.dart');
      expect(service.hasPending('/tmp/x.dart'), isFalse);
    });

    test('rejectHunk revierte solo ese bloque en disco', () async {
      final dir = await Directory.systemTemp.createTemp('lopez_diff_');
      final file = File('${dir.path}/sample.dart');
      const base = 'alpha\nbeta\ngamma\n';
      const after = 'alpha\nBETA\ngamma\n';
      await file.writeAsString(after);

      service.recordEdit(
        filePath: file.path,
        before: base,
        after: after,
      );
      final review = service.reviewFor(file.path)!;
      expect(review.hunks, isNotEmpty);
      final hunkId = review.hunks.first.id;

      final ok = await service.rejectHunk(file.path, hunkId);
      expect(ok, isTrue);
      expect(await file.readAsString(), base);
      expect(service.hasPending(file.path), isFalse);

      await dir.delete(recursive: true);
    });

    test('reject parcial con dos hunks deja el otro aplicado', () async {
      final dir = await Directory.systemTemp.createTemp('lopez_diff2_');
      final file = File('${dir.path}/multi.dart');
      const base = 'one\ntwo\nthree\nfour\n';
      const after = 'one\nTWO\nthree\nFOUR\n';
      await file.writeAsString(after);

      service.recordEdit(
        filePath: file.path,
        before: base,
        after: after,
      );
      final review = service.reviewFor(file.path)!;
      expect(review.hunks.length, greaterThanOrEqualTo(2));

      // Undo del primer hunk (TWO → two).
      final firstId = review.hunks.first.id;
      final ok = await service.rejectHunk(file.path, firstId);
      expect(ok, isTrue);

      final content = await file.readAsString();
      expect(content.contains('TWO'), isFalse);
      expect(content.contains('FOUR'), isTrue);

      final left = service.reviewFor(file.path);
      expect(left, isNotNull);
      expect(left!.hunks, isNotEmpty);

      await dir.delete(recursive: true);
    });

    test('edits sucesivos conservan el baseContent original', () {
      service.recordEdit(
        filePath: '/tmp/chain.dart',
        before: 'v1',
        after: 'v2',
      );
      service.recordEdit(
        filePath: '/tmp/chain.dart',
        before: 'v2',
        after: 'v3',
      );
      final review = service.reviewFor('/tmp/chain.dart')!;
      expect(review.baseContent, 'v1');
      final hunks = LineDiffer.computeHunks('v1', 'v3');
      expect(review.hunks.length, hunks.length);
    });

    test('navegación next/previous cicla el índice activo', () {
      service.debugSetReview(
        const FileDiffReview(
          filePath: '/tmp/nav.dart',
          baseContent: 'a',
          hunks: [
            DiffHunk(
              id: 'a',
              startLine: 1,
              endLine: 1,
              removedLines: [],
              addedLines: ['1'],
            ),
            DiffHunk(
              id: 'b',
              startLine: 2,
              endLine: 2,
              removedLines: [],
              addedLines: ['2'],
            ),
          ],
        ),
      );
      expect(service.reviewFor('/tmp/nav.dart')!.activeIndex, 0);
      service.selectNext('/tmp/nav.dart');
      expect(service.reviewFor('/tmp/nav.dart')!.activeIndex, 1);
      service.selectNext('/tmp/nav.dart');
      expect(service.reviewFor('/tmp/nav.dart')!.activeIndex, 0);
      service.selectPrevious('/tmp/nav.dart');
      expect(service.reviewFor('/tmp/nav.dart')!.activeIndex, 1);
    });
  });
}
