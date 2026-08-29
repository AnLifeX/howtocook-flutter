import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:howtocook/features/ai_chat/domain/entities/chat_message.dart';
import 'package:howtocook/features/ai_chat/presentation/widgets/message_bubble.dart';

void main() {
  testWidgets('本地聊天图片可显示并打开全屏预览', (tester) async {
    final directory = Directory.systemTemp.createTempSync('chat-image-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final image = File('${directory.path}${Platform.pathSeparator}photo.png');
    image.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: ChatMessage(
              id: 'image-message',
              role: MessageRole.user,
              content: [MessageContent.image(data: '', localPath: image.path)],
              timestamp: DateTime(2026, 8, 29),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片文件不可用'), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('关闭预览'), findsOneWidget);
  });
}
