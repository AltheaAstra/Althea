import 'package:flutter/material.dart';

import '../../app/workspace_widgets.dart';
import '../../core/api_client.dart';

class FolderView extends StatefulWidget {
  const FolderView({required this.api, super.key});
  final SeqotiaApi api;

  @override
  State<FolderView> createState() => _FolderViewState();
}

class _FolderViewState extends State<FolderView> {
  late Future<List<Map<String, dynamic>>> _folders;
  int? _parentId;
  final List<Map<String, dynamic>> _ancestors = [];

  @override
  void initState() {
    super.initState();
    _folders = widget.api.folders();
  }

  void _load() => setState(() => _folders = widget.api.folders());

  void _enter(Map<String, dynamic> folder) {
    _ancestors.add(folder);
    setState(() => _parentId = folder['id'] as int);
  }

  void _returnTo(int depth) {
    setState(() {
      if (depth < 0) {
        _ancestors.clear();
        _parentId = null;
      } else {
        _ancestors.removeRange(depth + 1, _ancestors.length);
        _parentId = _ancestors[depth]['id'] as int;
      }
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => WorkspacePageFrame(
        title: 'โฟลเดอร์',
        subtitle: 'จัดเอกสารเป็นหมวดหมู่และโฟลเดอร์ย่อย',
        actions: FilledButton.icon(
          onPressed: () => _createFolder(),
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('สร้างโฟลเดอร์'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _folders,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return _FolderEmpty(title: 'โหลดโฟลเดอร์ไม่ได้', detail: snapshot.error.toString(), action: TextButton(onPressed: _load, child: const Text('ลองอีกครั้ง')));
            final all = snapshot.data ?? const <Map<String, dynamic>>[];
            final current = all.where((folder) => folder['parent_id'] == _parentId).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Breadcrumbs(ancestors: _ancestors, onSelect: _returnTo),
              const SizedBox(height: 12),
              Expanded(
                child: current.isEmpty
                    ? _FolderEmpty(
                        title: _parentId == null ? 'ยังไม่มีโฟลเดอร์' : 'โฟลเดอร์นี้ยังว่าง',
                        detail: _parentId == null ? 'สร้างโฟลเดอร์เพื่อจัดระเบียบไฟล์และเอกสาร' : 'สร้างโฟลเดอร์ย่อย หรือเพิ่มเอกสารเข้ามา',
                        action: FilledButton.icon(onPressed: _createFolder, icon: const Icon(Icons.add_rounded), label: const Text('สร้างโฟลเดอร์')),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => _load(),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: current.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _FolderTile(
                            folder: current[index],
                            onOpen: () => _enter(current[index]),
                            onAction: (action) => _folderAction(action, current[index]),
                          ),
                        ),
                      ),
              ),
              if (current.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('${current.length} โฟลเดอร์', style: const TextStyle(color: Color(0xFF75847A), fontSize: 11)),
                ),
            ]);
          },
        ),
      );

  Future<void> _createFolder() async {
    final name = await _nameDialog(title: _parentId == null ? 'สร้างโฟลเดอร์' : 'สร้างโฟลเดอร์ย่อย');
    if (name == null) return;
    try {
      await widget.api.createFolder(name, parentId: _parentId);
      if (mounted) {
        _snack('สร้างโฟลเดอร์แล้ว');
        _load();
      }
    } catch (error) {
      if (mounted) _snack(error.toString());
    }
  }

  Future<String?> _nameDialog({required String title, String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'ชื่อโฟลเดอร์'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('บันทึก')),
        ],
      ),
    ).then((value) {
      controller.dispose();
      return value?.isEmpty == true ? null : value;
    });
  }

  Future<void> _folderAction(String action, Map<String, dynamic> folder) async {
    final id = folder['id'] as int;
    if (action == 'documents') {
      Navigator.pushReplacementNamed(context, '/documents', arguments: {'folderId': id, 'folderName': folder['name']});
      return;
    }
    if (action == 'subfolder') {
      final name = await _nameDialog(title: 'สร้างโฟลเดอร์ย่อย');
      if (name == null) return;
      try {
        await widget.api.createFolder(name, parentId: id);
        if (mounted) _load();
      } catch (error) {
        if (mounted) _snack(error.toString());
      }
      return;
    }
    if (action == 'rename') {
      final name = await _nameDialog(title: 'เปลี่ยนชื่อโฟลเดอร์', initial: folder['name'].toString());
      if (name == null) return;
      try {
        await widget.api.updateFolder(id, {'name': name});
        if (mounted) _load();
      } catch (error) {
        if (mounted) _snack(error.toString());
      }
      return;
    }
    if (action == 'archive') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('เก็บโฟลเดอร์เข้าคลัง?'),
          content: const Text('ต้องย้ายหรือเก็บเอกสารและโฟลเดอร์ย่อยก่อน โฟลเดอร์นี้จึงจะถูกเก็บได้'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('เก็บเข้าคลัง')),
          ],
        ),
      );
      if (accepted != true) return;
      try {
        await widget.api.archiveFolder(id);
        if (mounted) _load();
      } catch (error) {
        if (mounted) _snack(error.toString());
      }
    }
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.ancestors, required this.onSelect});
  final List<Map<String, dynamic>> ancestors;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          TextButton.icon(onPressed: () => onSelect(-1), icon: const Icon(Icons.home_outlined, size: 17), label: const Text('โฟลเดอร์ทั้งหมด')),
          for (var index = 0; index < ancestors.length; index++) ...[
            const Icon(Icons.chevron_right_rounded, size: 17, color: Color(0xFF91A096)),
            TextButton(onPressed: () => onSelect(index), child: Text(ancestors[index]['name'].toString())),
          ],
        ]),
      );
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.onOpen, required this.onAction});
  final Map<String, dynamic> folder;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onOpen,
          leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFEAF5EF), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.folder_rounded, color: Color(0xFF4A946A))),
          title: Text(folder['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Text('${folder['document_count'] ?? 0} เอกสาร', style: const TextStyle(fontSize: 11)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'ดูเอกสารในโฟลเดอร์', onPressed: () => onAction('documents'), icon: const Icon(Icons.description_outlined, size: 19)),
            PopupMenuButton<String>(
              onSelected: onAction,
              itemBuilder: (_) => const [PopupMenuItem(value: 'subfolder', child: Text('สร้างโฟลเดอร์ย่อย')), PopupMenuItem(value: 'rename', child: Text('เปลี่ยนชื่อ')), PopupMenuItem(value: 'archive', child: Text('เก็บเข้าคลัง'))],
            ),
          ]),
        ),
      );
}

class _FolderEmpty extends StatelessWidget {
  const _FolderEmpty({required this.title, required this.detail, required this.action});
  final String title;
  final String detail;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 430),
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE1EAE4))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_open_outlined, size: 38, color: Color(0xFF4B8964)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 7),
            Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF728178), height: 1.5, fontSize: 12)),
            const SizedBox(height: 14),
            action,
          ]),
        ),
      );
}
