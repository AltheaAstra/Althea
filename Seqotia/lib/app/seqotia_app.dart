import 'package:flutter/material.dart';

import 'workspace_shell.dart';

class SeqotiaApp extends StatelessWidget {
  const SeqotiaApp({super.key});

  static const Color forest = Color(0xFF071B14);
  static const Color emerald = Color(0xFF55D39B);
  static const Color mint = Color(0xFFB8F5D8);
  static const Color paper = Color(0xFFF8FAF8);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: emerald,
      primary: const Color(0xFF167A53),
      secondary: emerald,
      surface: paper,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'Seqotia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: paper,
        fontFamily: 'Segoe UI',
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: forest,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDCE8E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFDCE8E1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: emerald, width: 1.5),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE3ECE7)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF167A53),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final path = settings.name ?? '/dashboard';
        final page = path == '/' ? 'dashboard' : path.replaceFirst('/', '');
        if (page == 'login') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const LoginPage(),
          );
        }
        const pages = {
          'dashboard',
          'documents',
          'folders',
          'studio',
          'templates',
          'analytics',
          'users',
          'settings',
        };
        final selected = pages.contains(page) ? page : 'dashboard';
        final arguments = settings.arguments;
        final template = arguments is String ? arguments : null;
        final routeArgs = arguments is Map ? arguments : const <String, dynamic>{};
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => WorkspaceShell(
            activePage: selected,
            initialTemplate: template,
            initialFolderId: routeArgs['folderId'] is int ? routeArgs['folderId'] as int : null,
            initialFolderName: routeArgs['folderName'] is String ? routeArgs['folderName'] as String : null,
          ),
        );
      },
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [SeqotiaApp.forest, Color(0xFF124F38), Color(0xFF071B14)],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.forest_rounded,
                          size: 40, color: Color(0xFF167A53)),
                      const SizedBox(height: 18),
                      Text(
                        'ยินดีต้อนรับสู่ Seqotia',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                          'โหมดพัฒนาในเครื่อง · ระบบเข้าสู่ระบบยังไม่ได้เชื่อมต่อ'),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, '/dashboard'),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('เข้าสู่พื้นที่ทดลอง'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
