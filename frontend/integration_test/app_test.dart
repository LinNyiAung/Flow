// Single entry point for the whole E2E suite (one APK build per run).
//
//   cd frontend
//   python <scratchpad>/e2e/seed_rich.py          # reset backend data first
//   flutter test integration_test -d emulator-5554 \
//       --dart-define=API_BASE_URL=http://10.0.2.2:8765
//
// One area only: add  --plain-name "03 Transactions"  (group names below).
// Large-text tour: adb shell settings put system font_scale 1.3, then add
//   --dart-define=E2E_LARGE_TEXT=true --plain-name "14 Large text tour"
import 'flows/ai_flows.dart';
import 'flows/analytics_report_flows.dart';
import 'flows/auth_flows.dart';
import 'flows/budget_goal_flows.dart';
import 'flows/home_flows.dart';
import 'flows/notification_settings_flows.dart';
import 'flows/recurring_flows.dart';
import 'flows/tour_flows.dart';
import 'flows/transaction_flows.dart';
import 'support/harness.dart';

void main() {
  initBinding();
  authFlows(); //            01
  homeFlows(); //            02
  transactionFlows(); //     03
  recurringFlows(); //       04
  budgetFlows(); //          05
  goalFlows(); //            06
  analyticsFlows(); //       07
  reportFlows(); //          08
  insightFlows(); //         09
  chatFlows(); //            10
  notificationFlows(); //    11
  settingsFlows(); //        12
  tourFlows(); //            13 + 14
}
