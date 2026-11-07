import 'package:flutter_test/flutter_test.dart';
import 'package:teleai/features/brief/brief_prefs.dart';
import 'package:teleai/features/brief/brief_widget.dart';

void main() {
  test('left-out folders are kept with their account', () {
    const p = BriefPrefs(excludedFolders: {'a1:3': 'Work', 'main:5': 'Crypto'});
    final back = BriefPrefs.fromJson(p.toJson());
    expect(back.excludedFolders, {'a1:3': 'Work', 'main:5': 'Crypto'});
    expect(BriefPrefs.fromJson(const BriefPrefs().toJson()).excludedFolders, isEmpty);
  });

  test('the scrolling widget gets the whole brief', () {
    final long = List.generate(400, (i) => 'Line $i of a long brief.').join('\n\n');
    final cut = BriefHomeWidget.forWidget(long, WidgetContent.full);
    final whole = BriefHomeWidget.forWidget(long, WidgetContent.full, null);
    expect(cut.length, lessThanOrEqualTo(1401), reason: 'places that can\'t scroll still get a short version');
    expect(whole, contains('Line 399 of a long brief.'));
  });
}
