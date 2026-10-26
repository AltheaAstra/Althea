import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../features/dashboard/dashboard_view.dart';
import '../features/documents/document_library_view.dart';
import '../features/document_studio/document_studio_view.dart';
import '../features/folders/folder_view.dart';
import 'secondary_views.dart';

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({required this.activePage, this.initialTemplate, this.initialDocument, this.initialDocumentCategory, this.initialRepairStatus, this.initialFolderId, this.initialFolderName, super.key});

  final String activePage;
  final String? initialTemplate;
  final Map<String, dynamic>? initialDocument;
  final String? initialDocumentCategory;
  final String? initialRepairStatus;
  final int? initialFolderId;
  final String? initialFolderName;
  static final SeqotiaApi api = SeqotiaApi();

  static const _nav = <(String, String, IconData)>[
    ('dashboard', 'ภาพรวม', Icons.space_dashboard_rounded),
    ('documents', 'คลังเอกสาร', Icons.folder_copy_rounded),
    ('folders', 'โฟลเดอร์', Icons.folder_rounded),
    ('studio', 'สร้างเอกสาร', Icons.edit_document),
    ('templates', 'แม่แบบเอกสาร', Icons.dashboard_customize_outlined),
    ('analytics', 'สถิติ', Icons.query_stats_rounded),
    ('users', 'ผู้ใช้งาน', Icons.people_alt_rounded),
    ('settings', 'ตั้งค่า', Icons.tune_rounded),
  ];

  String get _title => switch (activePage) {
        'documents' => 'คลังเอกสาร',
        'folders' => 'โฟลเดอร์',
        'studio' => 'Document Studio',
        'templates' => 'แม่แบบเอกสาร',
        'analytics' => 'สถิติการใช้งาน',
        'users' => 'ผู้ใช้งาน',
        'settings' => 'ตั้งค่า',
        _ => 'พื้นที่ทำงาน',
      };

  Widget _page() => switch (activePage) {
        'documents' => DocumentLibraryView(api: api, folderId: initialFolderId, folderName: initialFolderName, initialCategory: initialDocumentCategory, initialRepairStatus: initialRepairStatus),
        'folders' => FolderView(api: api),
        'studio' => DocumentStudioView(api: api, initialCategory: initialTemplate, initialDocument: initialDocument),
        'templates' => TemplateView(api: api),
        'analytics' => AnalyticsView(api: api),
        'users' => const UsersView(),
        'settings' => const SettingsView(),
        _ => DashboardView(api: api),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F4),
      appBar: wide
          ? null
          : AppBar(
              title: Text(_title),
              leading: activePage == 'studio' && initialDocument != null
                  ? IconButton(
                      tooltip: 'กลับไปคลังเอกสาร',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  : Builder(
                      builder: (context) => IconButton(
                        tooltip: 'เปิดเมนู',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
              actions: const [Padding(padding: EdgeInsets.only(right: 14), child: _BackendStatus())],
            ),
      drawer: wide
          ? null
          : Drawer(
              width: 285,
              backgroundColor: const Color(0xFF071B14),
              child: _Sidebar(activePage: activePage, nav: _nav, mobile: true),
            ),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 250,
              child: _Sidebar(activePage: activePage, nav: _nav, mobile: false),
            ),
          Expanded(
            child: Column(
              children: [
                if (wide)
                  Container(
                    height: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAF8),
                      border: Border(bottom: BorderSide(color: Color(0xFFE4ECE7))),
                    ),
                    child: Row(
                      children: [
                        Text(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF28463A))),
                        const Spacer(),
                        const _BackendStatus(),
                        const SizedBox(width: 18),
                        const CircleAvatar(
                          radius: 17,
                          backgroundColor: Color(0xFFDDF3E7),
                          child: Icon(Icons.person_rounded, size: 19, color: Color(0xFF167A53)),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: _page()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.activePage, required this.nav, required this.mobile});
  final String activePage;
  final List<(String, String, IconData)> nav;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B2A1F), Color(0xFF071B14), Color(0xFF0D241B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 17, 18, 26),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF55D39B).withValues(alpha: .17),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF55D39B).withValues(alpha: .35)),
                      ),
                      child: const Icon(Icons.forest_rounded, color: Color(0xFF80E5B6)),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Seqotia', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: .2)),
                        Text('DOCUMENT WORKSPACE', style: TextStyle(color: Color(0xFF8CB8A2), fontSize: 9, letterSpacing: 1.25)),
                      ],
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 16, 10),
                child: Text('WORKSPACE', style: TextStyle(color: Color(0xFF719A85), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
              ),
              for (final item in nav)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: _NavItem(
                    title: item.$2,
                    icon: item.$3,
                    selected: activePage == item.$1,
                    onTap: () {
                      if (mobile) Scaffold.of(context).closeDrawer();
                      if (activePage != item.$1) Navigator.pushReplacementNamed(context, '/${item.$1}');
                    },
                  ),
                ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: Colors.white.withValues(alpha: .09)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline_rounded, color: Color(0xFF81DDB1), size: 18),
                    SizedBox(width: 9),
                    Expanded(child: Text('ไฟล์เก็บในเครื่อง\nAI อยู่ในโหมดตัวอย่าง', style: TextStyle(color: Color(0xFFB3CCBF), fontSize: 11, height: 1.5))),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 16, 20),
                child: Text('SEQOTIA  ·  DEVELOPMENT', style: TextStyle(color: Color(0xFF5E816F), fontSize: 9, letterSpacing: .8)),
              ),
            ],
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.title, required this.icon, required this.selected, required this.onTap});
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0xFF174E37) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 19, color: selected ? const Color(0xFF8BE8B9) : const Color(0xFF87A997)),
                const SizedBox(width: 13),
                Text(title, style: TextStyle(color: selected ? Colors.white : const Color(0xFFB5C9BD), fontWeight: selected ? FontWeight.w600 : FontWeight.w400, fontSize: 13)),
                if (selected) ...[
                  const Spacer(),
                  Container(width: 5, height: 5, decoration: const BoxDecoration(color: Color(0xFF69DEA7), shape: BoxShape.circle)),
                ],
              ],
            ),
          ),
        ),
      );
}

class _BackendStatus extends StatefulWidget {
  const _BackendStatus();

  @override
  State<_BackendStatus> createState() => _BackendStatusState();
}

class _BackendStatusState extends State<_BackendStatus> {
  late Future<Map<String, dynamic>> _health;

  @override
  void initState() {
    super.initState();
    _health = WorkspaceShell.api.health();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _health,
        builder: (context, snapshot) {
          final connected = snapshot.hasData;
          final color = connected ? const Color(0xFF14774F) : const Color(0xFF9B6B18);
          final label = connected ? 'Local API' : 'API ไม่เชื่อมต่อ';
          return Tooltip(
            message: connected ? 'Backend และ SQLite พร้อมใช้งาน · กดเพื่อตรวจอีกครั้ง' : 'กดเพื่อตรวจ Backend อีกครั้ง',
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => setState(() => _health = WorkspaceShell.api.health()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(30)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
