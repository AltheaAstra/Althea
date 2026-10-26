import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/workspace_widgets.dart';
import '../../core/api_client.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({required this.api, super.key});
  final SeqotiaApi api;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late Future<Map<String, dynamic>> _summary;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.api.dashboard();
  }

  void _reload() => setState(() => _summary = widget.api.dashboard());

  Future<void> _upload() async {
    final choice = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'xlsx', 'pptx', 'txt'],
    );
    if (choice == null || choice.files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      final document = await widget.api.upload(choice.files.single);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เพิ่ม ${document['file_name']} ในคลังแล้ว')),
      );
      _reload();
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) => WorkspacePageFrame(
        title: 'สวัสดี 👋',
        subtitle: 'พื้นที่ทำงานเอกสารของคุณในวันนี้',
        actions: IconButton.filledTonal(
          onPressed: _reload,
          tooltip: 'โหลดข้อมูลใหม่',
          icon: const Icon(Icons.refresh_rounded),
        ),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _summary,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _BackendEmptyState(onRetry: _reload);
            }
            final data = snapshot.data!;
            final recent = (data['recent_documents'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _WelcomeCard(generatedAt: data['generated_at']?.toString() ?? ''),
                  const SizedBox(height: 20),
                  LayoutBuilder(builder: (context, constraints) {
                    final columns = constraints.maxWidth < 600 ? 2 : 4;
                    final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(width: width, label: 'เอกสารทั้งหมด', value: data['total_documents'], icon: Icons.description_outlined, tint: const Color(0xFFEAF5EF)),
                        _MetricCard(width: width, label: 'สร้างใน 7 วัน', value: data['created_last_7_days'], icon: Icons.auto_awesome_motion_rounded, tint: const Color(0xFFEAF1FA)),
                        _MetricCard(width: width, label: 'รออนุมัติ', value: data['pending_approval'], icon: Icons.hourglass_top_rounded, tint: const Color(0xFFFFF4DF)),
                        _MetricCard(width: width, label: 'ต้องตรวจสอบ', value: data['needs_attention'], icon: Icons.fact_check_outlined, tint: const Color(0xFFFFEEEA)),
                      ],
                    );
                  }),
                  const SizedBox(height: 22),
                  _QuickActions(uploading: _uploading, onUpload: _upload),
                  const SizedBox(height: 22),
                  _RecentDocuments(documents: recent, onBrowse: () => Navigator.pushReplacementNamed(context, '/documents')),
                  const SizedBox(height: 18),
                  const _PrivacyNote(),
                ],
              ),
            );
          },
        ),
      );
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.generatedAt});
  final String generatedAt;

  @override
  Widget build(BuildContext context) {
    final hourText = RegExp(r'T(\d{2}):').firstMatch(generatedAt)?.group(1);
    final hour = int.tryParse(hourText ?? '') ?? 12;
    final greeting = hour < 12 ? 'อรุณสวัสดิ์' : hour < 18 ? 'สวัสดีตอนบ่าย' : 'สวัสดีตอนเย็น';
    final date = generatedAt.length >= 16 ? generatedAt.substring(0, 16).replaceFirst('T', '  ·  ') : 'เวลา Asia/Bangkok';
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123F2C), Color(0xFF0B281C), Color(0xFF071B14)],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF0B3D28).withValues(alpha: .12), blurRadius: 25, offset: const Offset(0, 11))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('YOUR FOREST OF KNOWLEDGE', style: TextStyle(color: Color(0xFF93D5B1), fontSize: 10, letterSpacing: 1.55, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('$greeting, ยินดีต้อนรับกลับมา', style: TextStyle(color: Colors.white, fontSize: compact ? 21 : 25, height: 1.3, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('จัดการเอกสาร ค้นหาความรู้ และร่างงานได้ในพื้นที่เดียว', style: TextStyle(color: const Color(0xFFD6E9DE).withValues(alpha: .82), fontSize: 13)),
            const SizedBox(height: 17),
            Row(children: [const Icon(Icons.schedule_rounded, size: 15, color: Color(0xFF8BDDB3)), const SizedBox(width: 7), Text('$date  ·  UTC+7', style: const TextStyle(color: Color(0xFFB5D8C4), fontSize: 11))]),
          ],
        );
        final mark = Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: .12))),
          child: const Icon(Icons.forest_rounded, size: 44, color: Color(0xFF7DE0AE)),
        );
        return Row(children: [Expanded(child: text), if (!compact) ...[const SizedBox(width: 18), mark]]);
      }),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.width, required this.label, required this.value, required this.icon, required this.tint});
  final double width;
  final String label;
  final Object? value;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Container(width: 35, height: 35, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 18, color: const Color(0xFF286649))), const Spacer(), const Icon(Icons.more_horiz_rounded, size: 20, color: Color(0xFF99A89E))]),
              const SizedBox(height: 16),
              Text('$value', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, color: Color(0xFF142C20))),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF718178))),
            ]),
          ),
        ),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.uploading, required this.onUpload});
  final bool uploading;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('เริ่มต้นอย่างรวดเร็ว', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A3527))),
            const SizedBox(height: 13),
            Wrap(spacing: 9, runSpacing: 9, children: [
              _ActionButton(icon: Icons.upload_file_rounded, label: 'อัปโหลดเอกสาร', onPressed: uploading ? null : onUpload, busy: uploading),
              _ActionButton(icon: Icons.shopping_bag_outlined, label: 'สร้าง PO', onPressed: () => Navigator.pushReplacementNamed(context, '/studio', arguments: 'po')),
              _ActionButton(icon: Icons.playlist_add_rounded, label: 'สร้าง PR', onPressed: () => Navigator.pushReplacementNamed(context, '/studio', arguments: 'pr')),
              _ActionButton(icon: Icons.build_outlined, label: 'แจ้งซ่อม', onPressed: () => Navigator.pushReplacementNamed(context, '/studio', arguments: 'repair')),
            ]),
          ]),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onPressed, this.busy = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF20543A), side: const BorderSide(color: Color(0xFFDDE9E1)), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
      );
}

class _RecentDocuments extends StatelessWidget {
  const _RecentDocuments({required this.documents, required this.onBrowse});
  final List<Map<String, dynamic>> documents;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Expanded(child: Text('เอกสารล่าสุด', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A3527))),), TextButton(onPressed: onBrowse, child: const Text('เปิดคลัง'))]),
            if (documents.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(3, 5, 3, 9), child: Row(children: [const Icon(Icons.inbox_outlined, color: Color(0xFF83A28F)), const SizedBox(width: 10), const Expanded(child: Text('ยังไม่มีเอกสาร — อัปโหลดไฟล์หรือสร้างเอกสารเพื่อเริ่มต้น', style: TextStyle(color: Color(0xFF73847A), fontSize: 12)))]))
            else
              for (final document in documents.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF5EF), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.description_outlined, color: Color(0xFF26744E), size: 19)),
                  title: Text(document['file_name']?.toString() ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  subtitle: Text('${document['category'] ?? 'general'}  ·  ${document['approval_status'] ?? 'draft'}', style: const TextStyle(fontSize: 10)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF9BAC9F)),
                  onTap: onBrowse,
                ),
          ]),
        ),
      );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: const Color(0xFFEAF3ED), borderRadius: BorderRadius.circular(14)),
        child: const Row(children: [Icon(Icons.info_outline_rounded, color: Color(0xFF4D8163), size: 18), SizedBox(width: 9), Expanded(child: Text('ตัวเลขนี้คำนวณจากเอกสารในฐานข้อมูลท้องถิ่น ไม่มีข้อมูลตัวอย่างปะปน', style: TextStyle(color: Color(0xFF50715D), fontSize: 11)))]),
      );
}

class _BackendEmptyState extends StatelessWidget {
  const _BackendEmptyState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE0E9E3))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 58, height: 58, decoration: BoxDecoration(color: const Color(0xFFFFF4DF), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.cloud_off_rounded, color: Color(0xFF9B6B18))),
            const SizedBox(height: 16),
            const Text('ยังเชื่อมต่อ Backend ไม่ได้', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            const Text('เปิดบริการในเครื่องก่อน แล้วลองโหลดข้อมูลอีกครั้ง หน้านี้จะแสดงตัวเลขจากฐานข้อมูลจริงเมื่อเชื่อมต่อสำเร็จ', textAlign: TextAlign.center, style: TextStyle(height: 1.5, color: Color(0xFF6E8075), fontSize: 12)),
            const SizedBox(height: 17),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('ลองอีกครั้ง')),
          ]),
        ),
      );
}
