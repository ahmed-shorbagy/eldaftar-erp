import 'dart:io';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/nominal_weight_suggestions.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_close_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_app_bar.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/trade_nominal_picker.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'meeting_calendar_and_count_test.dart' show calendarBody;
import 'meeting_pdf_handoff_test.dart' show PdfGateway;
import 'package:eldafttar/src/features/daily_ledger/presentation/invoice_pdf_share_dialog.dart';

class CountGateway extends FakeFinancialGateway implements ClosingObservationGateway {}
const closingDay = FinancialDayState(state:'open',dayId:'day-1',dayVersion:1,
  counts:{'cash':{'cash':'100','instant_transfer':'0','wallet':'0','card':'0'},
    'stock':[{'category':'worked_jewelry','karat':21,'count':'5','milligrams':'5000'}],
    'scrap':[{'karat':21,'milligrams':'1000'}]});

void main() {
  if (!const bool.fromEnvironment('OWNER_MEETING_CAPTURE')) return;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in {'Cairo':'assets/fonts/Cairo.ttf',
      'MaterialIcons':r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'}.entries) {
      await (FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(await File(entry.value).readAsBytes())))).load();
    }
  });
  for (final width in [320.0,390.0,1440.0]) {
    for (final dark in [false,true]) {
      for (final scale in [1.0,1.7]) {
        final suffix='${width.toInt()}-${dark ? 'dark':'light'}-$scale';
        testWidgets('meeting captures $suffix',(t) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          t.view.physicalSize=Size(width,width==1440 ? 900:850);t.view.devicePixelRatio=1;
          addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
          final key=GlobalKey();
          Widget host(Widget child)=>MaterialApp(debugShowCheckedModeBanner:false,
            locale:const Locale('ar'),supportedLocales:const [Locale('ar')],
            localizationsDelegates:GlobalMaterialLocalizations.delegates,
            theme:dark ? AppTheme.dark():AppTheme.light(),
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:TextScaler.linear(scale)),
              child:RepaintBoundary(key:key,child:child!)),home:child);
          Future<void> shot(String state) async {
            await t.pumpAndSettle();expect(t.takeException(),isNull,reason:'$state-$suffix');
            await expectLater(find.byKey(key),matchesGoldenFile('../../docs/reviews/owner-meeting-2026-10-18/captures/$state-$suffix.png'));
          }
          Future<void> tap(Finder finder) async {
            if (finder.evaluate().isEmpty) {
              await t.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
            }
            await t.ensureVisible(finder);await t.pumpAndSettle();await t.tap(finder);await t.pumpAndSettle();
          }
          final gateway=FakeFinancialGateway();
          await t.pumpWidget(host(FinancialTradeScreen(kind:FinancialKind.sale,gateway:gateway,statusGateway:gateway,userId:'owner-1',shopId:'shop-1')));
          await shot('sale');
          await tap(find.byKey(const Key('trade-add-item')));await shot('add-category');
          await tap(find.text('إلغاء'));
          await t.pumpWidget(host(FinancialTradeScreen(key:const ValueKey('scrap'),kind:FinancialKind.scrapSale,gateway:gateway,statusGateway:gateway,userId:'owner-1',shopId:'shop-1')));
          await shot('scrap');
          await t.pumpWidget(host(Scaffold(body:TradeNominalPicker(category:'coin',suggestions:nominalSuggestionsFor(category:'coin')))));
          await tap(find.byKey(const Key('nominal-select-0')));
          await t.enterText(find.byKey(const Key('nominal-count-0')),'2');
          await tap(find.byKey(const Key('nominal-select-1')));await shot('denominations');
          final count=CountGateway();
          await t.pumpWidget(host(DailyCloseScreen(gateway:count,statusGateway:count,userId:'owner-1',shopId:'shop-1',day:closingDay)));
          await t.pumpAndSettle();
          final typeField=find.byType(DropdownButtonFormField<String>);
          if (typeField.evaluate().isEmpty) {
            await t.scrollUntilVisible(typeField,200,scrollable:find.byType(Scrollable).first);
          }
          await t.ensureVisible(typeField.first);await shot('close-count');
          await t.pumpWidget(host(Scaffold(appBar:LedgerAppBar(shopName:'متجر الذهب التجريبي',collapsed:true,
            topInset:0,onToggleTheme:(_)async{},textScaler:TextScaler.linear(scale)),
            body:SingleChildScrollView(child:ConfirmedLedgerDashboard(shopId:'shop-1',ledger:parseDailyLedger(calendarBody()),onDailyNotes:(){})))));
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const Key('ledger-book-notes')));await shot('compact-books');
          await t.pumpWidget(host(Scaffold(body:InvoicePdfShareDialog(gateway:PdfGateway(),userId:'owner-1',shopId:'shop-1',operationId:'operation-1',canRead:()=>true,canWrite:()=>true))));
          await shot('pdf-share');
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
