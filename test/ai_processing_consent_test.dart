import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyoora/widgets/ai_processing_consent.dart';

void main(){
  testWidgets('skincare photo and conversation consent distinguish recipients and cancellation',(tester)async{
    bool? approved;
    var chat=false;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context)=>Scaffold(body:TextButton(
      onPressed:()async{approved=await confirmSkincareProcessing(context,chat:chat);},child:const Text('Request AI'))))));
    await tester.tap(find.text('Request AI'));await tester.pumpAndSettle();
    expect(find.textContaining('selected label photo'),findsOneWidget);
    expect(find.textContaining('OpenAI'),findsWidgets);
    expect(approved,isNull);
    await tester.tap(find.text('Cancel'));await tester.pumpAndSettle();expect(approved,isFalse);
    chat=true;await tester.tap(find.text('Request AI'));await tester.pumpAndSettle();
    expect(find.textContaining('recent conversation context'),findsOneWidget);
    await tester.tap(find.byKey(const Key('skincare-ai-consent')));await tester.pumpAndSettle();expect(approved,isTrue);
    expect(tester.takeException(),isNull);
  });
}
