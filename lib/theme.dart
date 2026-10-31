import 'package:flutter/material.dart';

/// Theme dùng chung cho toàn app — chỉ đổi giao diện, không đổi logic/API.
/// Bảng màu: xanh dương chủ đạo + violet phụ, nền sáng, chữ tối rõ.
class AppColors {
  static const primary = Color(0xFF2B6CF0);
  static const primaryDark = Color(0xFF1D4ED8);
  static const violet = Color(0xFF7C5CFC);
  static const background = Color(0xFFF5F6FA);
  static const surface = Colors.white;
  static const inputFill = Color(0xFFEEF1F6);
  static const bubbleOther = Color(0xFFEDF1F7);
  static const border = Color(0xFFE3E7F0);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const primarySoft = Color(0xFFE8F0FE);
  static const violetSoft = Color(0xFFEFEBFF);
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFE11D48);
  static const gradient = LinearGradient(
    colors: [primary, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const darkGradient = LinearGradient(
    colors: [Color(0xFF1C1E21), Color(0xFF1E3A8A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

/// Bo tròn + khoảng cách chuẩn, dùng chung để các màn nhìn nhất quán.
class AppRadii {
  static const card = 20.0;
  static const button = 16.0;
  static const input = 16.0;
  static const chip = 999.0;
}

class AppSpacing {
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
}

/// Trang trí card trắng, bóng nhẹ — dùng cho các khối nội dung.
class AppDecor {
  static BoxDecoration card({Color? color}) => BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration softCard(Color color) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.card),
      );
}

class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.violet,
      tertiary: AppColors.violet,
      surface: AppColors.surface,
      primaryContainer: AppColors.primarySoft,
      secondaryContainer: AppColors.violetSoft,
      onPrimary: Colors.white,
      onSurface: AppColors.text,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
        titleMedium: TextStyle(fontWeight: FontWeight.bold, color: AppColors.text),
        bodyMedium: TextStyle(color: AppColors.text),
        bodySmall: TextStyle(color: AppColors.muted),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          minimumSize: const Size(0, 50),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primarySoft,
        labelStyle: const TextStyle(color: AppColors.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1F2937),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/// Card trắng bóng nhẹ, dùng chung cho các khối nội dung.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: AppDecor.card(color: color),
        padding: padding,
        child: child,
      );
}

/// Tiêu đề section: icon trong ô màu + chữ đậm + số lượng (nếu có).
class SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? count;
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.count,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: AppDecor.softCard(AppColors.primarySoft),
          child: Icon(icon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            count == null ? title : '$title ($count)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
      ]);
}

/// Trạng thái trống: icon lớn trong vòng màu + tiêu đề + hướng dẫn.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: AppDecor.softCard(AppColors.primarySoft),
              child: Icon(icon, size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ],
          ]),
        ),
      );
}

/// Icon/logo trên nền gradient xanh → violet.
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  const GradientIcon({super.key, required this.icon, this.size = 80});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(size * 0.28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x335B6CF0),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.55, color: Colors.white),
      );
}
