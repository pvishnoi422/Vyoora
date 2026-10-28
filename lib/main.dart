// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_shell.dart';
import 'navigation/fashion_routes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const VyooraApp());
}

class VyooraApp extends StatelessWidget {
  const VyooraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.cinzelTextTheme(ThemeData.dark().textTheme);
    return MaterialApp(
      title: 'Vyoora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080808),
        textTheme: base.copyWith(
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 15,
            height: 1.7,
            fontWeight: FontWeight.w500,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.6,
            fontWeight: FontWeight.w500,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFF9B59D4),
          surface: Color(0xFF111111),
          onPrimary: Color(0xFF080808),
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF080808),
          foregroundColor: const Color(0xFFD4AF37),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.cormorantGaramond(
            color: const Color(0xFFD4AF37),
            fontSize: 22,
            fontWeight: FontWeight.w600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      initialRoute: '/',
      routes: {
        ...fashionRoutes,
        '/': (_) => const SplashScreen(),
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeShell(),
      },
    );
  }
}
