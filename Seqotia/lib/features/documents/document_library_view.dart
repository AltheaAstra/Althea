import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/workspace_widgets.dart';
import '../../core/api_client.dart';

class DocumentLibraryView extends StatefulWidget {
  const DocumentLibraryView({
    required this.api,
    this.folderId,
    this.folderName,
    super.key,
  });

  final SeqotiaApi api;
  final int? folderId;
  final String? folderName;

  @override
  State<DocumentLibraryView> createState() => _DocumentLibraryViewState();
}

class _DocumentLibraryViewState extends State<DocumentLibraryView> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _documents;
  Timer? _debounce;
  bool _grid = false;
  bool _uploading = false;
  String _category = '';
  String _processingStatus = '';
  String _approvalStatus = '';
  String _sort = 'updated_desc';

  @override
  void initState() {
    super.initState();
    _documents = widget.api.documents(folderId: widget.folderId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _load() => setState(() {
        _documents = widget.api.documents(
          search: _search.text,
          folderId: widget.folderId,
          category: _category,
          processingStatus: _processingStatus,
          approvalStatus: _approvalStatus,
          sort: _sort,
        );
      });

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _upload() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx', 'xlsx', 'pptx', 'txt'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      final document = await widget.api.upload(
        result.files.single,
        folderId: widget.folderId,
      );
      if (!mounted) return;
      _snack('เพิ่ม ${document['file_name']} แล้ว');
      _load();
    } catch (error) {
      if (mounted) _snack(error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => WorkspacePageFrame(
        title: widget.folderName == null ? 'คลังเอกสาร' : widget.folderName!,
        subtitle: widget.folderId == null
            ? 'ค้นหา แยกประเภท และจัดการเอกสารในพื้นที่ทำงาน'
            : 'เอกสารที่จัดเก็บในโฟลเดอร์นี้',
        actions: FilledButton.icon(
          onPressed: _uploading ? null : _upload,
          icon: _uploading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_file_rounded, size: 18),
          label: Text(_uploading ? 'กำลังอัปโหลด' : 'อัปโหลด'),
        ),
        body: Column(
          children: [
            _Toolbar(
              search: _search,
              onSearchChanged: _searchChanged,
              onSearchSubmitted: (_) => _load(),
              category: _category,
              onCategoryChanged: (value) {
                setState(() => _category = value);
                _load();
              },
              processingStatus: _processingStatus,
              onProcessingChanged: (value) {
                setState(() => _processingStatus = value);
                _load();
              },
              approvalStatus: _approvalStatus,
              onApprovalChanged: (value) {
                setState(() => _approvalStatus = value);
                _load();
              },
              sort: _sort,
              onSortChanged: (value) {
                setState(() => _sort = value);
                _load();
              },
              grid: _grid,
              onGridChanged: (value) => setState(() => _grid = value),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _documents,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _LibraryNotice(
                      icon: Icons.cloud_off_outlined,
                      title: 'เชื่อมต่อคลังเอกสารไม่ได้',
                      detail: snapshot.error.toString(),
                      action: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('ลองใหม่')),
                    );
                  }
                  final documents = snapshot.data ?? const [];
                  if (documents.isEmpty) {
                    return _LibraryNotice(
                      icon: Icons.folder_open_rounded,
                      title: _search.text.isEmpty ? 'ยังไม่มีเอกสาร' : 'ไม่พบเอกสารที่ตรงกัน',
                      detail: _search.text.isEmpty
                          ? 'อัปโหลด PDF, DOCX, XLSX, PPTX หรือ TXT เพื่อเริ่มต้นคลังของคุณ'
                          : 'ลองเปลี่ยนคำค้นหาหรือตัวกรอง',
                      action: _search.text.isEmpty
                          ? FilledButton.icon(onPressed: _upload, icon: const Icon(Icons.add_rounded), label: const Text('เพิ่มเอกสารแรก'))
                          : TextButton(onPressed: () { _search.clear(); _load(); }, child: const Text('ล้างการค้นหา')),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _load(),
                    child: _grid
                        ? GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              mainAxisExtent: 190,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: documents.length,
                            itemBuilder: (context, index) => _GridDocumentCard(
                              document: documents[index],
                              onOpen: () => _details(documents[index]),
                              onAction: (action) => _documentAction(action, documents[index]),
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: documents.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) => _ListDocumentCard(
                              document: documents[index],
                              onOpen: () => _details(documents[index]),
                              onAction: (action) => _documentAction(action, documents[index]),
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      );

  Future<void> _documentAction(String action, Map<String, dynamic> document) async {
    final id = document['id']?.toString() ?? '';
    if (action == 'details') {
      _details(document);
      return;
    }
    if (action == 'move') {
      await _move(document);
      return;
    }
    if (action == 'download') {
      await _download(document);
      return;
    }
    if (action == 'reprocess') {
      try {
        await widget.api.reprocessDocument(id);
        if (mounted) {
          _snack('ส่งเอกสารเข้าประมวลผลใหม่แล้ว');
          _load();
        }
      } catch (error) {
        if (mounted) _snack(error.toString());
      }
      return;
    }
    if (action == 'archive') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('เก็บเอกสารเข้าคลังถาวร?'),
          content: Text('“${document['file_name']}” จะถูกซ่อนจากคลังเอกสาร แต่ไฟล์ต้นฉบับจะยังคงอยู่ในเครื่อง'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('เก็บเข้าคลัง')),
          ],
        ),
      );
      if (accepted != true) return;
      try {
        await widget.api.archiveDocument(id);
        if (mounted) _load();
      } catch (error) {
        if (mounted) _snack(error.toString());
      }
    }
  }

  Future<void> _move(Map<String, dynamic> document) async {
    try {
      final folders = await widget.api.folders();
      if (!mounted) return;
      final selected = await showDialog<int?>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('ย้ายไปยังโฟลเดอร์'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(context, -1), child: const ListTile(leading: Icon(Icons.home_outlined), title: Text('รากคลัง'))),
            for (final folder in folders)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, folder['id'] as int),
                child: ListTile(leading: const Icon(Icons.folder_outlined), title: Text(folder['name'].toString()), subtitle: folder['parent_id'] == null ? null : const Text('โฟลเดอร์ย่อย')),
              ),
          ],
        ),
      );
      if (selected == null) return;
      await widget.api.moveDocument(document['id'].toString(), selected == -1 ? null : selected);
      if (mounted) {
        _snack('ย้ายเอกสารแล้ว');
        _load();
      }
    } catch (error) {
      if (mounted) _snack(error.toString());
    }
  }

  Future<void> _download(Map<String, dynamic> document) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'บันทึกไฟล์ต้นฉบับ',
      fileName: document['original_file_name']?.toString() ?? document['file_name']?.toString(),
    );
    if (path == null || !mounted) return;
    try {
      await widget.api.downloadDocument(document['id'].toString(), path);
      if (mounted) _snack('บันทึกไฟล์แล้ว');
    } catch (error) {
      if (mounted) _snack(error.toString());
    }
  }

  void _details(Map<String, dynamic> document) {
    final metadata = Map<String, dynamic>.from(document['metadata'] as Map? ?? const {});
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 25),
        decoration: const BoxDecoration(color: Color(0xFFF8FAF8), borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD4DFD8), borderRadius: BorderRadius.circular(5)))),
          const SizedBox(height: 18),
          Row(children: [const Icon(Icons.description_outlined, color: Color(0xFF26744E)), const SizedBox(width: 10), Expanded(child: Text(document['file_name']?.toString() ?? 'Document', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
          const SizedBox(height: 8),
          Expanded(child: ListView(children: [
            _detailLine('ประเภท', document['file_type']?.toString().toUpperCase() ?? '—'),
            _detailLine('หมวดหมู่', document['category']?.toString() ?? '—'),
            _detailLine('สถานะการประมวลผล', document['processing_status']?.toString() ?? '—'),
            _detailLine('สถานะเอกสาร', document['approval_status']?.toString() ?? '—'),
            _detailLine('วันที่แก้ไข', document['updated_at']?.toString() ?? '—'),
            const SizedBox(height: 14),
            if (metadata.isNotEmpty) ...[
              const Text('รายละเอียด', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 7),
              for (final entry in metadata.entries.where((entry) => entry.key != 'processing_note'))
                _detailLine(entry.key.replaceAll('_', ' '), entry.value.toString()),
            ],
            if (document['content_preview'] != null) ...[
              const SizedBox(height: 12),
              const Text('ข้อความที่แยกได้', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 7),
              Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)), child: SelectableText(document['content_preview'].toString(), style: const TextStyle(height: 1.5, fontSize: 12))),
            ],
            if (metadata['processing_note'] != null) ...[
              const SizedBox(height: 12),
              Text(metadata['processing_note'].toString(), style: const TextStyle(color: Color(0xFF92631B), fontSize: 12)),
            ],
            const SizedBox(height: 20),
            const Text('ประวัติเอกสาร', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 7),
            _HistoryList(api: widget.api, documentId: document['id'].toString()),
          ])),
        ]),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.api, required this.documentId});
  final SeqotiaApi api;
  final String documentId;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: api.documentHistory(documentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const LinearProgressIndicator();
          if (snapshot.hasError) return const Text('โหลดประวัติไม่ได้', style: TextStyle(color: Color(0xFF8A6A2C), fontSize: 11));
          final items = snapshot.data ?? const [];
          if (items.isEmpty) return const Text('ยังไม่มีรายการประวัติ', style: TextStyle(color: Color(0xFF728178), fontSize: 11));
          return Column(children: [
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.history_rounded, color: Color(0xFF4A8962), size: 18),
                title: Text('${item['action']} · ${item['actor']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                subtitle: Text(item['created_at']?.toString() ?? '', style: const TextStyle(fontSize: 10)),
              ),
          ]);
        },
      );
}

Widget _detailLine(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 145, child: Text(label, style: const TextStyle(color: Color(0xFF728178), fontSize: 12))), Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF293D31))))]),
    );

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.search, required this.onSearchChanged, required this.onSearchSubmitted, required this.category, required this.onCategoryChanged, required this.processingStatus, required this.onProcessingChanged, required this.approvalStatus, required this.onApprovalChanged, required this.sort, required this.onSortChanged, required this.grid, required this.onGridChanged});
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final String processingStatus;
  final ValueChanged<String> onProcessingChanged;
  final String approvalStatus;
  final ValueChanged<String> onApprovalChanged;
  final String sort;
  final ValueChanged<String> onSortChanged;
  final bool grid;
  final ValueChanged<bool> onGridChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.search_rounded, color: Color(0xFF83948A)),
              const SizedBox(width: 7),
              Expanded(child: TextField(controller: search, onChanged: onSearchChanged, onSubmitted: onSearchSubmitted, decoration: const InputDecoration(hintText: 'ค้นหาชื่อหรือข้อความในเอกสาร', border: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(vertical: 10)))),
            ]),
            const Divider(height: 1, color: Color(0xFFEAF0EB)),
            const SizedBox(height: 5),
            Wrap(spacing: 3, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _FilterMenu<String>(label: _category.isEmpty ? 'ทุกประเภท' : _categoryLabel(_category), icon: Icons.filter_list_rounded, value: category, onSelected: onCategoryChanged, options: const [('', 'ทุกประเภท'), ('general', 'ไฟล์อัปโหลด'), ('po', 'PO'), ('pr', 'PR'), ('repair', 'แจ้งซ่อม')]),
              _FilterMenu<String>(label: _processingStatus.isEmpty ? 'ทุกสถานะ' : _processingLabel(_processingStatus), icon: Icons.sync_alt_rounded, value: processingStatus, onSelected: onProcessingChanged, options: const [('', 'ทุกสถานะ'), ('uploaded', 'Uploaded'), ('processing', 'Processing'), ('completed', 'Completed'), ('needs_review', 'Needs review'), ('failed', 'Failed')]),
              _FilterMenu<String>(label: _approvalStatus.isEmpty ? 'ทุกขั้นตอน' : _approvalLabel(_approvalStatus), icon: Icons.fact_check_outlined, value: approvalStatus, onSelected: onApprovalChanged, options: const [('', 'ทุกขั้นตอน'), ('draft', 'Draft'), ('pending', 'Pending'), ('approved', 'Approved'), ('rejected', 'Rejected')]),
              _FilterMenu<String>(label: _sortLabel(sort), icon: Icons.sort_rounded, value: sort, onSelected: onSortChanged, options: const [('updated_desc', 'แก้ไขล่าสุด'), ('updated_asc', 'แก้ไขเก่าสุด'), ('created_desc', 'สร้างใหม่สุด'), ('created_asc', 'สร้างเก่าสุด'), ('name_asc', 'ชื่อ A–Z'), ('name_desc', 'ชื่อ Z–A'), ('category_asc', 'ประเภท')]),
              IconButton(tooltip: 'รายการ', onPressed: () => onGridChanged(false), icon: Icon(Icons.view_list_rounded, color: grid ? const Color(0xFF9AABA0) : const Color(0xFF167A53))),
              IconButton(tooltip: 'ตารางการ์ด', onPressed: () => onGridChanged(true), icon: Icon(Icons.grid_view_rounded, color: grid ? const Color(0xFF167A53) : const Color(0xFF9AABA0))),
            ]),
          ]),
        ),
      );
}

String _categoryLabel(String value) => switch (value) {'
      'general' => 'ไฟล์อัปโหลด',
      'po' => 'PO',
      'pr' => 'PR',
      'repair' => 'แจ้งซ่อม',
      _ => value,
    };

String _processingLabel(String value) => switch (value) {
      'uploaded' => 'Uploaded',
      'processing' => 'Processing',
      'completed' => 'Completed',
      'needs_review' => 'Needs review',
      'failed' => 'Failed',
      _ => value,
    };

String _approvalLabel(String value) => switch (value) {
      'draft' => 'Draft',
      'pending' => 'Pending',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      _ => value,
    };

String _sortLabel(String value) => switch (value) {
      'updated_asc' => 'แก้ไขเก่าสุด',
      'created_desc' => 'สร้างใหม่สุด',
      'created_asc' => 'สร้างเก่าสุด',
      'name_asc' => 'ชื่อ A–Z',
      'name_desc' => 'ชื่อ Z–A',
      'category_asc' => 'ประเภท',
      _ => 'แก้ไขล่าสุด',
    };

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({required this.label, required this.icon, required this.value, required this.onSelected, required this.options});
  final String label;
  final IconData icon;
  final T value;
  final ValueChanged<T> onSelected;
  final List<(T, String)> options;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: label,
        initialValue: value,
        onSelected: onSelected,
        itemBuilder: (_) => [for (final option in options) PopupMenuItem<T>(value: option.$1, child: Text(option.$2))],
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: const Color(0xFF597264)), const SizedBox(width: 5), Text(label, style: const TextStyle(color: Color(0xFF597264), fontSize: 10, fontWeight: FontWeight.w600))])),
      );
}

class _ListDocumentCard extends StatelessWidget {
  const _ListDocumentCard({required this.document, required this.onOpen, required this.onAction});
  final Map<String, dynamic> document;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: onOpen,
          leading: _FileIcon(type: document['file_type']?.toString() ?? ''),
          title: Text(document['file_name']?.toString() ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text('${document['category'] ?? 'general'}  ·  ${document['processing_status'] ?? 'uploaded'}  ·  ${document['updated_at'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF728178)))),
          trailing: _ActionsMenu(onSelected: onAction, hasFile: document['storage_key'] != null),
        ),
      );
}

class _GridDocumentCard extends StatelessWidget {
  const _GridDocumentCard({required this.document, required this.onOpen, required this.onAction});
  final Map<String, dynamic> document;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [_FileIcon(type: document['file_type']?.toString() ?? ''), const Spacer(), _ActionsMenu(onSelected: onAction, hasFile: document['storage_key'] != null)]),
              const Spacer(),
              Text(document['file_name']?.toString() ?? 'Document', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text('${document['category'] ?? 'general'}  ·  ${document['processing_status'] ?? 'uploaded'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF728178))),
            ]),
          ),
        ),
      );
}

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type.toLowerCase()) {
      'pdf' => const Color(0xFFB5473A),
      'docx' => const Color(0xFF3E6BA5),
      'xlsx' => const Color(0xFF3D8062),
      'pptx' => const Color(0xFFBD7043),
      _ => const Color(0xFF6D8275),
    };
    return Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(13)), child: Icon(type == 'seqotia' ? Icons.edit_document : Icons.insert_drive_file_outlined, color: color, size: 20));
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.onSelected, required this.hasFile});
  final ValueChanged<String> onSelected;
  final bool hasFile;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'การทำงานกับเอกสาร',
        onSelected: onSelected,
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'details', child: Text('รายละเอียด')),
          if (hasFile) const PopupMenuItem(value: 'download', child: Text('บันทึกไฟล์ต้นฉบับ')),
          if (hasFile) const PopupMenuItem(value: 'reprocess', child: Text('ประมวลผลใหม่')),
          const PopupMenuItem(value: 'move', child: Text('ย้ายโฟลเดอร์')),
          const PopupMenuItem(value: 'archive', child: Text('เก็บเข้าคลัง')),
        ],
      );
}

class _LibraryNotice extends StatelessWidget {
  const _LibraryNotice({required this.icon, required this.title, required this.detail, required this.action});
  final IconData icon;
  final String title;
  final String detail;
  final Widget action;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(27),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE0E9E3))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 37, color: const Color(0xFF4E8565)),
            const SizedBox(height: 13),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF728178), fontSize: 12, height: 1.5)),
            const SizedBox(height: 15),
            action,
          ]),
        ),
      );
}

