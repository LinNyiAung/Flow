import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/budget.dart';

void main() {
  group('CategoryBudget sub category', () {
    test('fromJson reads sub_category', () {
      final line = CategoryBudget.fromJson({
        'main_category': 'Food & Daily Living',
        'sub_category': 'Groceries',
        'allocated_amount': 100,
        'spent_amount': 20,
        'percentage_used': 20,
        'is_exceeded': false,
      });
      expect(line.mainCategory, 'Food & Daily Living');
      expect(line.subCategory, 'Groceries');
    });

    test('fromJson reads a null sub_category as main only', () {
      final line = CategoryBudget.fromJson({
        'main_category': 'Food & Daily Living',
        'sub_category': null,
        'allocated_amount': 100,
        'spent_amount': 0,
        'percentage_used': 0,
        'is_exceeded': false,
      });
      expect(line.subCategory, isNull);
    });

    test('toJson writes sub_category, null for main only', () {
      final sub = CategoryBudget(
        mainCategory: 'Main',
        subCategory: 'Sub',
        allocatedAmount: 1,
        spentAmount: 0,
        percentageUsed: 0,
        isExceeded: false,
      ).toJson();
      expect(sub['main_category'], 'Main');
      expect(sub['sub_category'], 'Sub');

      final main = CategoryBudget(
        mainCategory: 'Main',
        allocatedAmount: 1,
        spentAmount: 0,
        percentageUsed: 0,
        isExceeded: false,
      ).toJson();
      expect(main.containsKey('sub_category'), isTrue);
      expect(main['sub_category'], isNull);
    });

    test('label composes Main - Sub', () {
      CategoryBudget line({String? sub}) => CategoryBudget(
            mainCategory: 'Main',
            subCategory: sub,
            allocatedAmount: 1,
            spentAmount: 0,
            percentageUsed: 0,
            isExceeded: false,
          );
      expect(line(sub: 'Sub').label, 'Main - Sub');
      expect(line().label, 'Main');
    });
  });
}
