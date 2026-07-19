import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class MenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const MenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool tablet = width >= 700;

    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,

        child: Container(
          padding: EdgeInsets.all(tablet ? 20 : 16),

          decoration: BoxDecoration(
            color: color,

            borderRadius: BorderRadius.circular(28),

            boxShadow: AppColors.cardShadow,
          ),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: tablet ? 60 : 50,
                height: tablet ? 60 : 50,

                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.75),

                  borderRadius: BorderRadius.circular(18),
                ),

                child: Icon(
                  icon,
                  color: AppColors.textPrimary,
                  size: tablet ? 30 : 24,
                ),
              ),

              const Spacer(),

              Text(
                title,

                style: TextStyle(
                  fontSize: tablet ? 20 : 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                subtitle,

                style: TextStyle(
                  fontSize: tablet ? 13 : 12,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}