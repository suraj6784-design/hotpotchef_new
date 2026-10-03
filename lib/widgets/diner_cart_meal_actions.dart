import 'package:flutter/material.dart';

import '../utils/helpers.dart';
import 'group_order_modal.dart';

/// Side-by-side cart actions: add another plate, or open the group-order sheet.
class DinerCartMealActions extends StatelessWidget {
  final VoidCallback onAddMoreMeals;
  final bool showGroupOrder;

  const DinerCartMealActions({
    super.key,
    required this.onAddMoreMeals,
    required this.showGroupOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add more meals'),
            onPressed: onAddMoreMeals,
          ),
        ),
        if (showGroupOrder) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.apartment_outlined),
              label: const Text(
                kSocietyOfficeHotpotLabel,
                textAlign: TextAlign.center,
              ),
              onPressed: () => showSocietyOfficeHotpotSheet(context),
            ),
          ),
        ],
      ],
    );
  }
}

void showSocietyOfficeHotpotSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: AppTheme.bottomSheetDecoration(
        isDark: Theme.of(context).brightness == Brightness.dark,
      ),
      child: const GroupOrderModal(),
    ),
  );
}
