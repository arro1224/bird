import 'package:aves/bird_companion/features/review/presentation/widgets/review_conflict_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('real review conflict is an inline draft banner', (tester) async {
    var remote = 0;
    var local = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewConflictBanner(
            saving: false,
            onUseRemote: () => remote++,
            onKeepDraft: () => local++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('review-conflict-banner')), findsOneWidget);
    expect(find.text('盒子中有更新，本机草稿尚未同步'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('载入盒子最新版本'));
    await tester.tap(find.text('保留本机草稿'));
    expect(remote, 1);
    expect(local, 1);
  });
}
