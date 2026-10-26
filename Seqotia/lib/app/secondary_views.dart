import 'package:flutter/material.dart';

import '../core/api_client.dart';
import 'workspace_widgets.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({required this.api, super.key});
  final SeqotiaApi api;

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  late Future<List<Object>> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<List<Object>> _load() => Future.wait<Object>([
        widget.api.dashboard(),
        widget.api.documents(),
      ]);

  void _refresh() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) => WorkspacePageFrame(
        title: 'สถิติการใช้งาน',
        subtitle: 'สรุปตัวเลขจากเอกสารจริงในฐานข้อมูลท้องถิ่น',
        actions: IconButton.filledTonal(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
        body: FutureBuilder<List<Object>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return _InfoState(icon: Icons.cloud_off_outlined, title: 'Backend ยังไม่พร้อม', detail: snapshot.error.toString());
            final summary = snapshot.data![0] as Map<String, dynamic>;
            final documents = snapshot.data![1] as List<Map<String, dynamic>>;
            final categories = <String, int>{};
            final states = <String, int>{};
            for (final doc in documents) {
              final category = doc['category']?.toString() ?? 'general';
              categories[category] = (categories[category] ?? 0) + 1;
              final state = doc['processing_status']?.toString() ?? 'unknown';
              states[state] = (states[state] ?? 0) + 1;
            }
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                LayoutBuilder(builder: (context, constraints) {
                  final count = constraints.maxWidth < 600 ? 2 : 4;
                  final width = (constraints.maxWidth - (count - 1) * 12) / count;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    _CountCard(width: width, title: 'เอกสารทั้งหมด', count: summary['total_documents'] ?? 0, icon: Icons.description_outlined),
                    _CountCard(width: width, title: 'เพิ่มใน 7 วัน', count: summary['created_last_7_days'] ?? 0, icon: Icons.add_chart_rounded),
                    _CountCard(width: width, title: 'รออนุมัติ', count: summary['pending_approval'] ?? 0, icon: Icons.hourglass_empty_rounded),
                    _CountCard(width: width, title: 'ต้องตรวจสอบ', count: summary['needs_attention'] ?? 0, icon: Icons.fact_check_outlined),
                  ]);
                }),
                const SizedBox(height: 16),
                _BreakdownCard(title: 'ตามประเภท', values: categories.isEmpty ? {'ยังไม่มีข้อมูล': 0} : categories),
                const SizedBox(height: 13),
                _BreakdownCard(title: 'ตามสถานะประมวลผล', values: states.isEmpty ? {'ยังไม่มีข้อมูล': 0} : states),
                const SizedBox(height: 14),
                Text('อัปเดตจากข้อมูล ณ ${summary['generated_at']}  ·  ${summary['timezone']}', style: const TextStyle(color: Color(0xFF75847A), fontSize: 10)),
              ]),
            );
          },
        ),
      );
}

class TemplateView extends StatefulWidget {
  const TemplateView({required this.api, super.key});
  final SeqotiaApi api;

  @override
  State<TemplateView> createState() => _TemplateViewState();
}

class _TemplateViewState extends State<TemplateView> {
  late Future<List<Map<String, dynamic>>> _templates;

  @override
  void initState() {
    super.initState();
    _templates = widget.api.templates();
  }

  @override
  Widget build(BuildContext context) => WorkspacePageFrame(
        title: 'แม่แบบเอกสาร',
        subtitle: 'แม่แบบระบบสำหรับเอกสารจัดซื้อและการแจ้งซ่อม',
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _templates,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return _InfoState(icon: Icons.cloud_off_outlined, title: 'โหลดแม่แบบไม่ได้', detail: snapshot.error.toString());
            final templates = snapshot.data ?? [];
            if (templates.isEmpty) return const _InfoState(icon: Icons.dashboard_customize_outlined, title: 'ยังไม่มีแม่แบบ', detail: 'แม่แบบที่ผู้ดูแลสร้างจะแสดงที่นี่');
            return ListView.separated(
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(height: 11),
              itemBuilder: (context, index) {
                final template = templates[index];
                final fields = (template['fields'] as List? ?? const []).map((field) => field.toString()).toList();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(19),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEAF5EF), borderRadius: BorderRadius.circular(13)), child: Icon(_templateIcon(template['category']?.toString()), color: const Color(0xFF28744E))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(template['name']?.toString() ?? 'Template', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)), const SizedBox(height: 3), Text(template['description']?.toString() ?? '', style: const TextStyle(color: Color(0xFF728178), fontSize: 11))])), Chip(label: Text((template['category']?.toString() ?? '').toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)), visualDensity: VisualDensity.compact, backgroundColor: const Color(0xFFEAF5EF), side: BorderSide.none)]),
                      const SizedBox(height: 15),
                      Wrap(spacing: 7, runSpacing: 7, children: [for (final field in fields) Chip(label: Text(field.replaceAll('_', ' '), style: const TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact, backgroundColor: const Color(0xFFF3F6F3), side: BorderSide.none)]),
                      const SizedBox(height: 12),
                      Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: () => Navigator.pushReplacementNamed(context, '/studio', arguments: template['category']?.toString()), icon: const Icon(Icons.open_in_new_rounded, size: 16), label: const Text('สร้างจากแม่แบบ'))),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      );
}

IconData _templateIcon(String? category) => switch (category) {
      'po' => Icons.shopping_bag_outlined,
      'pr' => Icons.playlist_add_rounded,
      'repair' => Icons.build_outlined,
      _ => Icons.article_outlined,
    };

class UsersView extends StatelessWidget {
  const UsersView({super.key});

  @override
  Widget build(BuildContext context) => const WorkspacePageFrame(
        title: 'ผู้ใช้งาน',
        subtitle: 'การกำหนดสิทธิ์และบัญชีผู้ใช้',
        body: _InfoState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'ยังไม่ได้เชื่อมต่อ Authentication',
          detail: 'โหมดพัฒนาในเครื่องยังไม่มีบัญชีผู้ใช้หรือ Permission Check จึงยังไม่แสดงข้อมูลผู้ใช้จำลอง',
        ),
      );
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    const apiUrl = String.fromEnvironment('SEQOTIA_API_BASE_URL', defaultValue: 'http://127.0.0.1:8000');
    return WorkspacePageFrame(
      title: 'ตั้งค่า',
      subtitle: 'การเชื่อมต่อและสถานะระบบในเครื่อง',
      body: ListView(children: [
        const _SettingCard(icon: Icons.storage_outlined, title: 'ฐานข้อมูล', value: 'SQLite · ข้อมูลเก็บในเครื่อง'),
        const _SettingCard(icon: Icons.folder_open_outlined, title: 'ที่เก็บไฟล์', value: 'โฟลเดอร์ข้อมูล Seqotia ภายใต้ Local App Data'),
        const _SettingCard(icon: Icons.link_rounded, title: 'Backend URL', value: apiUrl),
        const _SettingCard(icon: Icons.auto_awesome_outlined, title: 'AI Provider', value: 'Demo mode · ไม่มีการเรียก AI ภายนอก'),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFFFF7E7), borderRadius: BorderRadius.circular(15)), child: const Text('การเข้าสู่ระบบ, สิทธิ์ผู้ใช้, OCR ภาษาไทย, Semantic Search และ AI จริงยังไม่ได้เชื่อมต่อ API นี้จึงรับคำขอจากเครื่อง local เท่านั้น', style: TextStyle(color: Color(0xFF856018), fontSize: 11, height: 1.5))),
      ]),
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.width, required this.title, required this.count, required this.icon});
  final double width;
  final String title;
  final Object count;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: Card(child: Padding(padding: const EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF2A7550), size: 20), const SizedBox(height: 13), Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 4), Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF728178)))]))));
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.title, required this.values});
  final String title;
  final Map<String, int> values;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final entry in values.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(flex: 2, child: Text(entry.key, style: const TextStyle(fontSize: 12, color: Color(0xFF64766B)))),
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: values.values.fold<int>(0, (sum, item) => sum + item) == 0 ? 0 : entry.value / values.values.fold<int>(0, (sum, item) => sum + item), minHeight: 7, backgroundColor: const Color(0xFFEAF0EB), color: const Color(0xFF55D39B)))),
                  const SizedBox(width: 10),
                  SizedBox(width: 28, child: Text('${entry.value}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
      );
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: Icon(icon, color: const Color(0xFF28744E)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), subtitle: Text(value, style: const TextStyle(fontSize: 11, color: Color(0xFF728178)))));
}

class _InfoState extends StatelessWidget {
  const _InfoState({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(child: Container(constraints: const BoxConstraints(maxWidth: 480), padding: const EdgeInsets.all(27), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE0E9E3))), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 38, color: const Color(0xFF4B8964)), const SizedBox(height: 13), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), const SizedBox(height: 7), Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF728178), fontSize: 12, height: 1.5))])));
}
