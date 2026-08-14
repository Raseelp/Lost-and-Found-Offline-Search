import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color backGroundColor = Color(0xFFF5F1E8);
  static const Color primarybuttonColor = Color(0xFF165E59);
  static const Color secondoryButtonColor = Color(0xFFE8BC52);
  static const Color surfaceColor = Color(0xFFFFFCF7);
  static const Color elevatedSurface = Color(0xFFF1E4CF);
  static const Color surfaceAccent = Color(0xFFD7E8E2);
  static const Color accentColor = Color(0xFFE27A52);
  static const Color accentSoft = Color(0xFFF7D9CB);
  static const Color borderColor = Color(0xFF1B2233);
  static const Color textPrimary = Color(0xFF1B2233);
  static const Color textSecondary = Color(0xFF5D6777);
  static const Color successColor = Color(0xFF3D9968);
  static const Color dangerColor = Color(0xFFD05757);
  static const Color infoColor = Color(0xFF6B8BFF);
  static const Color shadowColor = Color(0x331B2233);

  static const LinearGradient screenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8F4EC), Color(0xFFF1E8D9)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1F6C67), Color(0xFF2A837A)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0C960), Color(0xFFE68C56)],
  );
}
