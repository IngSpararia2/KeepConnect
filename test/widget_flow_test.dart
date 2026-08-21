import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_interna/features/maintenance/presentation/area_selection_screen.dart';
import 'package:gestion_interna/features/maintenance/presentation/create_ticket_screen.dart';

void main() {
  testWidgets('selector inicial muestra únicamente Planta', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AreaSelectionScreen())),
    );
    expect(find.text('Planta'), findsOneWidget);
    expect(find.byKey(const Key('select-plant')), findsOneWidget);
    expect(find.text('Mantenimiento'), findsNothing);
  });

  testWidgets('constructor añade una pregunta de texto libre', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CreateTicketScreen())),
    );
    await tester.tap(find.byKey(const Key('add-question')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('question-prompt')),
      '¿Qué encontró?',
    );
    await tester.tap(find.byKey(const Key('save-question')));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué encontró?'), findsOneWidget);
    expect(find.text('Texto libre'), findsOneWidget);
  });
}
