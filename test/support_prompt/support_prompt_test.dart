import 'package:flutter_test/flutter_test.dart';
import 'package:vorsorgeheft/support/support_prompt.dart';

void main() {
  test('nothing before the third recorded appointment', () {
    expect(supportPromptDue(completed: 0, dismissed: false), isFalse);
    expect(supportPromptDue(completed: 2, dismissed: false), isFalse);
  });

  test('due at the third, and still due after it', () {
    expect(supportPromptDue(completed: 3, dismissed: false), isTrue);
    expect(supportPromptDue(completed: 30, dismissed: false), isTrue);
  });

  test('once dismissed, never again, however many are recorded', () {
    expect(supportPromptDue(completed: 3, dismissed: true), isFalse);
    expect(supportPromptDue(completed: 300, dismissed: true), isFalse);
  });
}
