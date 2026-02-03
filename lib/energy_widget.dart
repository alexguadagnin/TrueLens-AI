import 'package:flutter/material.dart';

class EnergyWidget extends StatelessWidget {
  final int energyLevel;
  final VoidCallback onTap;

  const EnergyWidget({
    super.key,
    required this.energyLevel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Padding compatto
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: energyLevel > 0
                ? const Color(0xFF03DAC6)
                : const Color(0xFFCF6679),
            width: 1,
          ),
        ),
        // Row MINIMA: occupa solo lo spazio che serve
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              energyLevel > 0 ? Icons.bolt : Icons.battery_alert,
              size: 14,
              color: energyLevel > 0
                  ? const Color(0xFF03DAC6)
                  : const Color(0xFFCF6679),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return Container(
                  width: 5,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: index < energyLevel
                        ? const Color(0xFF03DAC6)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
