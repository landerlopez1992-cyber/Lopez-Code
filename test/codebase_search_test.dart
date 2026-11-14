import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopez_code_ai/services/codebase_search_service.dart';

void main() {
  test('grepSearch ignora build/.lopez_code_backups y devuelve líneas previas',
      () async {
    final dir = await Directory.systemTemp.createTemp('lopez_grep_');
    await Directory('${dir.path}/lib').create(recursive: true);
    await Directory('${dir.path}/build').create(recursive: true);
    await Directory('${dir.path}/.lopez_code_backups').create(recursive: true);

    await File('${dir.path}/lib/i18n.dart').writeAsString('''
final map = {
  'mh6nye0z': {
    'en': ' Sign Up',
    'es': 'Inscribirse',
  },
};
''');
    await File('${dir.path}/build/out.dart')
        .writeAsString("const x = 'Inscribirse';\n");
    await File('${dir.path}/.lopez_code_backups/old.dart')
        .writeAsString("const y = 'Inscribirse';\n");

    final matches = await CodebaseSearchService.grepSearch(
      projectPath: dir.path,
      query: 'Inscribirse',
    );
    expect(matches, hasLength(1));
    expect(matches.first['filePath'], 'lib/i18n.dart');
    final ctx = matches.first['context'] as Map<String, dynamic>;
    expect(ctx['before2'], contains("'mh6nye0z'"));

    await dir.delete(recursive: true);
  });
}
