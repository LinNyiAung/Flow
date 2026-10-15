import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/screens/auth/forgot_password_screen.dart';
import 'package:frontend/screens/auth/login_screen.dart';
import 'package:frontend/screens/auth/register_screen.dart';
import 'package:frontend/screens/home/home_screen.dart';
import 'package:http/http.dart' as http;

import '../support/accounts.dart';
import '../support/harness.dart';

/// Unique address for this run's registration test; shared with the
/// unverified-login test that runs right after it.
final String _regEmail = 'e2e.${DateTime.now().millisecondsSinceEpoch}@example.com';
const String _regPassword = 'RegPass123';

void authFlows() {
  group('01 Auth', () {
    e2eTest('auth: wrong password shows error', (t) async {
      step('enter wrong password');
      final fields = find.byType(TextFormField);
      await enter(fields.at(0), premium.email);
      await enter(fields.at(1), 'WrongPass999');
      await hideKeyboard();
      await tap(find.widgetWithText(FilledButton, L.signIn));
      // An error banner (error_outline icon) must appear; we must stay on login.
      await expectSoon(find.byIcon(Icons.error_outline_rounded),
          'Login with a wrong password shows no error banner');
      check(find.byType(HomeScreen).evaluate().isEmpty,
          'Login with a wrong password reached Home');
    });

    e2eTest('auth: empty fields show validation', (t) async {
      step('submit empty login');
      await tap(find.widgetWithText(FilledButton, L.signIn));
      await expectSoon(find.text(L.enterEmailError), 'No "enter email" validation message on empty login');
      await expectSoon(find.text(L.enterPasswordError), 'No "enter password" validation on empty login');
    });

    e2eTest('auth: login success (premium) then logout', (t) async {
      await login(premium);
      step('home visible');
      check(find.byType(HomeScreen).evaluate().isNotEmpty, 'Home not shown after login');
      await logout();
      check(find.byType(LoginScreen).evaluate().isNotEmpty, 'Login not shown after logout');
      step('login again after logout');
      await login(premium);
      await logout();
    });

    e2eTest('auth: register validation + success → check your email', (t) async {
      step('open register');
      await tap(find.textContaining(L.createAnAccount, findRichText: true));
      await waitFor(find.byType(RegisterScreen));
      final fields = find.byType(TextFormField);
      step('submit empty');
      await tap(find.widgetWithText(FilledButton, L.createAccountButton));
      await expectSoon(find.text(L.pleaseEnterName), 'Register: no name-required message');
      step('short password');
      await enter(fields.at(0), 'E2E Tester');
      await enter(fields.at(1), _regEmail);
      await enter(fields.at(2), '123');
      await enter(fields.at(3), '123');
      await hideKeyboard();
      await tap(find.widgetWithText(FilledButton, L.createAccountButton));
      await expectSoon(find.text(L.passwordMinLengthError), 'Register: no min-length message for a 3-char password');
      step('mismatch');
      await enter(fields.at(2), _regPassword);
      await enter(fields.at(3), '${_regPassword}x');
      await hideKeyboard();
      await tap(find.widgetWithText(FilledButton, L.createAccountButton));
      await expectSoon(find.text(L.passwordsNotMatch), 'Register: no mismatch message');
      step('invalid email');
      await enter(fields.at(1), 'not-an-email');
      await enter(fields.at(3), _regPassword);
      await hideKeyboard();
      await tap(find.widgetWithText(FilledButton, L.createAccountButton));
      await expectSoon(find.text(L.enterValidEmailError), 'Register: no invalid-email message');
      step('existing email');
      await enter(fields.at(1), premium.email);
      await hideKeyboard();
      await tap(find.widgetWithText(FilledButton, L.createAccountButton));
      await expectSoon(find.byIcon(Icons.error_outline_rounded),
          'Register with an already-registered e-mail shows no error');
      step('valid registration');
      await enter(fields.at(1), _regEmail);
      await hideKeyboard();

      await tap(find.widgetWithText(FilledButton, L.createAccountButton));
      await expectSoon(find.text(L.oneTapLeft), 'Register success did not show the "check your email" step',
          timeout: const Duration(seconds: 30));
      step('verification e-mail captured');
      final mail = await latestMailTo(_regEmail, contains: 'verify-email');
      check(mail != null, 'No verification e-mail was sent to $_regEmail');
      step('back to sign in prefills email');
      await tap(find.text(L.verifiedSignInButton));
      await waitFor(find.byType(LoginScreen));
      final emailField = t.widget<TextFormField>(find.byType(TextFormField).at(0));
      check(emailField.controller?.text == _regEmail,
          'Login e-mail not prefilled with the registered address (got "${emailField.controller?.text}")');
    });

    e2eTest('auth: unverified login shows verify notice + resend, then verify via link', (t) async {
      step('login unverified');
      final fields = find.byType(TextFormField);
      await enter(fields.at(0), _regEmail);
      await enter(fields.at(1), _regPassword);
      await hideKeyboard();
      await tap(find.widgetWithText(FilledButton, L.signIn));
      final shown = await expectSoon(find.text(L.checkEmailToVerify),
          'Unverified login did not show the verify-your-email notice');
      if (shown) {
        step('resend verification');
        await tap(find.text(L.resendVerificationEmail));
        await expectSoon(find.text(L.verificationEmailResent), 'Resend verification: no confirmation snackbar');
      }
      step('verify via e-mailed link (from the emulator)');
      final mail = await latestMailTo(_regEmail, contains: 'verify-email');
      if (mail == null) {
        appBug('No verification mail for $_regEmail');
        return;
      }
      final link = RegExp(r'https?://\S+verify-email\?\S+').firstMatch(mail)!.group(0)!;
      final uri = Uri.parse(link);
      final local = Uri.parse(kApiBase).replace(path: uri.path, query: uri.query);
      final r = await http.get(local);
      check(r.statusCode < 400, 'Verify link returned ${r.statusCode}');
      step('login after verification');
      await tap(find.widgetWithText(FilledButton, L.signIn));
      await expectSoon(find.byType(HomeScreen), 'Verified account could not log in',
          timeout: const Duration(seconds: 40));
    });

    e2eTest('auth: forgot password request + wrong code + full reset', (t) async {
      step('open forgot password');
      await tap(find.text(L.forgotPasswordQuestion));
      await waitFor(find.byType(ForgotPasswordScreen));
      step('invalid email validation');
      await tap(find.text(L.sendCodeButton));
      await expectSoon(find.text(L.enterEmailError), 'Forgot password: no email-required message');
      step('request code for deleteme... (uses empty account)');
      await enter(find.byType(TextFormField).first, empty.email);
      await hideKeyboard();
      await tap(find.text(L.sendCodeButton));
      final onOtp = await expectSoon(find.byType(OtpVerificationScreen),
          'Requesting a reset code did not open the code screen', timeout: const Duration(seconds: 30));
      if (!onOtp) return;
      step('wrong code');
      // Scoped to the code screen: during the push transition the previous
      // screen's e-mail field is still in the tree and would come first.
      final otpField = find.descendant(of: find.byType(OtpVerificationScreen), matching: find.byType(EditableText)).first;
      await t.enterText(otpField, '000000');
      await settle(2500);
      await expectSoon(find.byIcon(Icons.error_outline_rounded), 'Wrong OTP shows no error');
      step('read real code from outbox');
      final mail = await latestMailTo(empty.email, contains: '');
      final code = mail == null ? null : RegExp(r'\b(\d{6})\b').firstMatch(mail)?.group(1);
      if (code == null) {
        appBug('No 6-digit OTP found in the reset e-mail: ${mail?.substring(0, mail.length.clamp(0, 200))}');
        return;
      }
      await t.enterText(otpField, code);
      await settle(2500);
      final onReset = await expectSoon(find.byType(ResetPasswordScreen), 'Correct OTP did not open the new-password step',
          timeout: const Duration(seconds: 20));
      if (!onReset) return;
      step('short new password');
      final pw = find.byType(TextFormField);
      await enter(pw.at(0), '12');
      await enter(pw.at(1), '12');
      await hideKeyboard();
      await tap(find.text(L.saveAndSignInButton));
      await expectSoon(find.text(L.minimumSixCharactersError), 'Reset: no min-length message');
      step('set same password again (keeps seed state)');
      await enter(pw.at(0), empty.password);
      await enter(pw.at(1), empty.password);
      await hideKeyboard();
      await tap(find.text(L.saveAndSignInButton));
      final r = await waitAny([find.text(L.passwordResetTitle), find.byType(HomeScreen)],
          timeout: const Duration(seconds: 30));
      check(r >= 0, 'Password reset did not finish (no success screen / home)');
    });
  });
}
