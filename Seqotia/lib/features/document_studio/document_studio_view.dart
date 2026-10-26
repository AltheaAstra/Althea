import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/workspace_widgets.dart';
import '../../core/api_client.dart';

class DocumentStudioView extends StatefulWidget {
  const DocumentStudioView({required this.api, this.initialCategory, this.initialDocument, super.key});
  final SeqotiaApi api;
  final String? initialCategory;
  final Map<String, dynamic>? initialDocument;

  @override
  State<DocumentStudioView> createState() => _DocumentStudioViewState();
}

class _DocumentStudioViewState extends State<DocumentStudioView> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final List<_LineItem> _items = [_LineItem()];
  late Future<List<Map<String, dynamic>>> _templates;
  String _category = 'po';
  String _urgency = 'normal';
  String _repairStatus = 'reported';
  String? _suggestionField;
  String? _suggestionId;
  String? _suggestionError;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _suggestionTimer;
  bool _loadingSuggestion = false;
  bool _saving = false;
  String? _draftId;

  @override
  void initState() {
    super.initState();
    _put('document_date', _today());
    _put('request_date', _today());
    _put('report_date', _today());
    final document = widget.initialDocument;
    if (document != null && ['po', 'pr', 'repair'].contains(document['category'])) {
      _category = document['category'].toString();
      _draftId = document['id']?.toString();
      _loadDraft(Map<String, dynamic>.from(document['metadata'] as Map? ?? const {}));
    } else if (['po', 'pr', 'repair'].contains(widget.initialCategory)) {
      _category = widget.initialCategory!;
    }
    _templates = widget.api.templates();
  }

  void _loadDraft(Map<String, dynamic> metadata) {
    for (final entry in metadata.entries) {
      final key = entry.key == 'reference' && _category == 'pr' ? 'pr_reference' :
          entry.key == 'notes' && _category == 'repair' ? 'repair_notes' : entry.key;
      if (entry.value is! List && entry.value is! Map) {
        _put(key, entry.value?.toString() ?? '');
      }
    }
    if (_category == 'repair' && ['low', 'normal', 'high'].contains(metadata['urgency'])) {
      _urgency = metadata['urgency'].toString();
    }
    if (_category == 'repair' && ['reported', 'in_progress', 'completed'].contains(metadata['repair_status'])) {
      _repairStatus = metadata['repair_status'].toString();
    }
    final savedItems = metadata['items'];
    if ((_category == 'po' || _category == 'pr') && savedItems is List && savedItems.isNotEmpty) {
      for (final item in _items) {
        item.dispose();
      }
      _items
        ..clear()
        ..addAll(savedItems.whereType<Map>().map((value) {
          final item = _LineItem();
          item.name.text = value['name']?.toString() ?? '';
          item.quantity.text = value['quantity']?.toString() ?? '1';
          item.unit.text = value['unit']?.toString() ?? '';
          item.unitPrice.text = value['unit_price']?.toString() ?? '0';
          return item;
        }));
      if (_items.isEmpty) _items.add(_LineItem());
    }
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _docxFilename(String title) {
    var fileName = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (fileName.isEmpty) fileName = 'seqotia-document';
    if (!fileName.toLowerCase().endsWith('.docx')) fileName += '.docx';
    return fileName;
  }

  TextEditingController _controller(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  void _put(String key, String value) => _controller(key).text = value;

  @override
  void dispose() {
    _suggestionTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _changeCategory(String? value) {
    if (value == null) return;
    setState(() {
      _category = value;
      _suggestionField = null;
      _suggestionId = null;
      _suggestions = [];
      _suggestionError = null;
      _loadingSuggestion = false;
    });
  }

  void _queueSuggestion(String field, String text) {
    _suggestionTimer?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _suggestionField = null;
        _suggestionError = null;
      });
      return;
    }
    setState(() {
      _suggestionField = field;
      _suggestionId = null;
      _suggestions = [];
      _suggestionError = null;
      _loadingSuggestion = false;
    });
    _suggestionTimer = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() {
        _suggestionField = field;
        _loadingSuggestion = true;
        _suggestionError = null;
      });
      try {
        final result = await widget.api.suggest(
          documentType: _category,
          field: field,
          text: text.trim(),
        );
        if (!mounted || _controller(field).text.trim() != text.trim()) return;
        setState(() {
          _suggestionId = result['suggestion_id']?.toString();
          _suggestions = (result['suggestions'] as List? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _suggestionError = 'ยังเชื่อมต่อบริการคำแนะนำไม่ได้';
          });
        }
      } finally {
        if (mounted) setState(() => _loadingSuggestion = false);
      }
    });
  }

  Future<void> _acceptSuggestion(String value) async {
    final field = _suggestionField;
    if (field == null) return;
    final controller = _controller(field);
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    final id = _suggestionId;
    setState(() {
      _suggestions = [];
      _suggestionError = null;
    });
    if (id != null) {
      try {
        await widget.api.feedback(id, accepted: true);
      } catch (_) {
        // The field remains editable even if optional feedback storage is offline.
      }
    }
  }

  Future<void> _dismissSuggestions() async {
    final id = _suggestionId;
    setState(() => _suggestions = []);
    if (id != null) {
      try {
        await widget.api.feedback(id, accepted: false);
      } catch (_) {
        // Feedback is optional; dismissing a suggestion always works locally.
      }
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'กรุณากรอกข้อมูลนี้' : null;

  Widget _field(
    String key,
    String label, {
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? hint,
    bool suggestion = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextFormField(
            controller: _controller(key),
            validator: validator,
            maxLines: maxLines,
            keyboardType: keyboardType,
            onChanged: suggestion ? (value) => _queueSuggestion(key, value) : null,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              alignLabelWithHint: maxLines > 1,
            ),
          ),
          if (suggestion && _suggestionField == key)
            _SuggestionPanel(
              suggestions: _suggestions,
              loading: _loadingSuggestion,
              error: _suggestionError,
              onAccept: _acceptSuggestion,
              onDismiss: _dismissSuggestions,
            ),
        ]),
      );

  List<_LineItem> get _activeItems => _items;

  double get _estimatedTotal => _activeItems.fold<double>(0, (sum, item) {
        final quantity = double.tryParse(item.quantity.text) ?? 0;
        final price = double.tryParse(item.unitPrice.text) ?? 0;
        return sum + quantity * price;
      });

  Future<void> _save({bool downloadWord = false}) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final creating = _draftId == null;
      final metadata = <String, dynamic>{};
      switch (_category) {
        case 'po':
          metadata.addAll({
            'po_number': _controller('po_number').text.trim(),
            'document_date': _controller('document_date').text.trim(),
            'vendor': _controller('vendor').text.trim(),
            'items': _items.map((item) => item.toPayload()).toList(),
            'reference': _controller('reference').text.trim(),
            'terms': _controller('terms').text.trim(),
            'notes': _controller('notes').text.trim(),
          });
          break;
        case 'pr':
          metadata.addAll({
            'pr_number': _controller('pr_number').text.trim(),
            'request_date': _controller('request_date').text.trim(),
            'requester': _controller('requester').text.trim(),
            'department': _controller('department').text.trim(),
            'purpose': _controller('purpose').text.trim(),
            'items': _items.map((item) => item.toPayload()).toList(),
            'justification': _controller('justification').text.trim(),
            'reference': _controller('pr_reference').text.trim(),
          });
          break;
        case 'repair':
          metadata.addAll({
            'request_number': _controller('request_number').text.trim(),
            'report_date': _controller('report_date').text.trim(),
            'reporter': _controller('reporter').text.trim(),
            'equipment_name': _controller('equipment_name').text.trim(),
            'asset_id': _controller('asset_id').text.trim(),
            'location': _controller('location').text.trim(),
            'issue_description': _controller('issue_description').text.trim(),
            'urgency': _urgency,
            'repair_status': _repairStatus,
            'technician_name': _controller('technician_name').text.trim(),
            'diagnosis': _controller('diagnosis').text.trim(),
            'work_performed': _controller('work_performed').text.trim(),
            'parts_used': _controller('parts_used').text.trim(),
            'repair_cost': _controller('repair_cost').text.trim(),
            'completed_date': _controller('completed_date').text.trim(),
            'notes': _controller('repair_notes').text.trim(),
          });
          break;
      }
      final title = switch (_category) {
        'po' => 'PO · ${_controller('vendor').text.trim()}',
        'pr' => 'PR · ${_controller('purpose').text.trim()}',
        _ => 'แจ้งซ่อม · ${_controller('equipment_name').text.trim()}',
      };
      final safeTitle = title.length > 255 ? title.substring(0, 255) : title;
      final saved = _draftId == null
          ? await widget.api.saveDraft(
              category: _category,
              title: safeTitle,
              metadata: metadata,
            )
          : await widget.api.updateDraft(
              id: _draftId!,
              title: safeTitle,
              metadata: metadata,
            );
      if (!mounted) return;
      _draftId ??= saved['id']?.toString();
      var downloaded = false;
      if (downloadWord && _draftId != null) {
        final path = await FilePicker.saveFile(
          dialogTitle: 'บันทึกเอกสาร Word',
          fileName: _docxFilename(safeTitle),
        );
        if (path != null) {
          await widget.api.exportDocument(_draftId!, path);
          downloaded = true;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${creating ? 'บันทึกร่างแล้ว' : 'อัปเดตร่างแล้ว'}${downloaded ? 'และบันทึก Word แล้ว' : ''} · ${saved['approval_status']}')),
      );
      if (creating) {
        Navigator.pushReplacementNamed(context, '/documents');
      } else {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePageFrame(
        title: 'Document Studio',
        subtitle: _draftId == null
            ? 'สร้างเอกสารจากแม่แบบ · ระบบจะบันทึกเป็นร่างเพื่อให้คุณตรวจสอบก่อน'
            : 'แก้ไขร่างเอกสาร · บันทึกแต่ละครั้งจะเพิ่มรายการในประวัติ',
        actions: FilledButton.icon(
          onPressed: _saving ? null : () => _save(),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'กำลังบันทึก' : _draftId == null ? 'บันทึกร่าง' : 'บันทึกการแก้ไข'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _templates,
          builder: (context, snapshot) => Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _TemplateSelector(
                  templates: snapshot.data ?? _fallbackTemplates,
                  selected: _category,
                  onChanged: _draftId == null ? _changeCategory : null,
                  error: snapshot.hasError,
                ),
                const SizedBox(height: 14),
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('ใช้แม่แบบตัวอย่างในเครื่อง · ตรวจสอบการเชื่อมต่อ Backend', style: TextStyle(color: Color(0xFF9B6B18), fontSize: 11)),
                  ),
                _formCard(context),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(downloadWord: true),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('บันทึกและดาวน์โหลดเอกสาร Word'),
                  ),
                ),
                const SizedBox(height: 18),
                const _DraftDisclaimer(),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      );

  Widget _formCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_categoryTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF193526))),
            const SizedBox(height: 5),
            const Text('ช่องที่มีเครื่องหมายดอกจันต้องกรอกก่อนบันทึก', style: TextStyle(color: Color(0xFF79877F), fontSize: 11)),
            const SizedBox(height: 18),
            if (_category == 'po') _purchaseOrderForm(),
            if (_category == 'pr') _purchaseRequestForm(),
            if (_category == 'repair') _repairForm(),
          ]),
        ),
      );

  String get _categoryTitle => switch (_category) {
        'po' => 'ใบสั่งซื้อ (Purchase Order)',
        'pr' => 'ใบขอซื้อ (Purchase Requisition)',
        _ => 'ใบแจ้งซ่อมอุปกรณ์ (Repair Request)',
      };

  Widget _purchaseOrderForm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _responsiveFields([_field('po_number', 'เลข PO (ถ้ามี)'), _field('document_date', 'วันที่เอกสาร', hint: 'YYYY-MM-DD'), _field('vendor', 'ผู้ขาย *', validator: _required)]),
        _itemsEditor(),
        const SizedBox(height: 12),
        _responsiveFields([_field('reference', 'เลขที่อ้างอิง'), _field('terms', 'เงื่อนไข'), _field('notes', 'หมายเหตุ', maxLines: 2, suggestion: true)]),
      ]);

  Widget _purchaseRequestForm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _responsiveFields([_field('pr_number', 'เลข PR (ถ้ามี)'), _field('request_date', 'วันที่ขอซื้อ', hint: 'YYYY-MM-DD'), _field('requester', 'ผู้ขอ *', validator: _required), _field('department', 'แผนก / หน่วยงาน *', validator: _required)]),
        _field('purpose', 'วัตถุประสงค์ *', validator: _required, maxLines: 2, suggestion: true),
        _itemsEditor(),
        _responsiveFields([_field('justification', 'เหตุผลความจำเป็น', maxLines: 2, suggestion: true), _field('pr_reference', 'ข้อมูลอ้างอิง')]),
      ]);

  Widget _repairForm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _responsiveFields([_field('request_number', 'เลขที่แจ้งซ่อม (ถ้ามี)'), _field('report_date', 'วันที่แจ้ง', hint: 'YYYY-MM-DD'), _field('reporter', 'ผู้แจ้ง *', validator: _required), _field('equipment_name', 'ชื่ออุปกรณ์ *', validator: _required)]),
        _responsiveFields([_field('asset_id', 'หมายเลขอุปกรณ์ / Asset ID'), _field('location', 'สถานที่ติดตั้ง')]),
        _field('issue_description', 'อาการเสีย *', validator: _required, maxLines: 4, suggestion: true),
        Row(children: [const Text('ระดับความเร่งด่วน', style: TextStyle(fontSize: 12, color: Color(0xFF536A5D))), const SizedBox(width: 14), DropdownButton<String>(value: _urgency, items: const [DropdownMenuItem(value: 'low', child: Text('ต่ำ')), DropdownMenuItem(value: 'normal', child: Text('ปกติ')), DropdownMenuItem(value: 'high', child: Text('เร่งด่วน'))], onChanged: (value) { if (value != null) setState(() => _urgency = value); })]),
        const SizedBox(height: 8),
        Row(children: [
          const Text('สถานะงานซ่อม', style: TextStyle(fontSize: 12, color: Color(0xFF536A5D))),
          const SizedBox(width: 14),
          DropdownButton<String>(
            value: _repairStatus,
            items: const [
              DropdownMenuItem(value: 'reported', child: Text('รับแจ้งแล้ว')),
              DropdownMenuItem(value: 'in_progress', child: Text('กำลังซ่อม')),
              DropdownMenuItem(value: 'completed', child: Text('ซ่อมเสร็จแล้ว')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _repairStatus = value;
                if (value == 'completed' && _controller('completed_date').text.isEmpty) {
                  _put('completed_date', _today());
                }
              });
            },
          ),
        ]),
        if (_repairStatus != 'reported') ...[
          _responsiveFields([
            _field('technician_name', _repairStatus == 'completed' ? 'ช่างผู้รับผิดชอบ *' : 'ช่างผู้รับผิดชอบ', validator: _repairStatus == 'completed' ? _required : null),
            _field('completed_date', 'วันที่ซ่อมเสร็จ', hint: 'YYYY-MM-DD', validator: _repairStatus == 'completed' ? _required : null),
          ]),
          _field('diagnosis', 'สาเหตุ / ผลการตรวจสอบ', maxLines: 2),
          _field('work_performed', _repairStatus == 'completed' ? 'รายละเอียดงานที่ซ่อม *' : 'รายละเอียดงานที่ซ่อม', maxLines: 3, validator: _repairStatus == 'completed' ? _required : null),
          _responsiveFields([
            _field('parts_used', 'อะไหล่ที่ใช้', maxLines: 2),
            _field('repair_cost', 'ค่าใช้จ่ายรวม (บาท)', keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: _optionalCost),
          ]),
        ],
        const SizedBox(height: 10),
        _field('repair_notes', 'หมายเหตุ', maxLines: 2, suggestion: true),
      ]);

  String? _optionalCost(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final pieces = value.trim().split('.');
    if (pieces.length > 2 || (pieces.length == 2 && pieces.last.length > 2)) {
      return 'กรอกทศนิยมได้ไม่เกิน 2 ตำแหน่ง';
    }
    final amount = double.tryParse(value.trim());
    return amount == null || !amount.isFinite || amount < 0
        ? 'กรอกค่าใช้จ่ายเป็นตัวเลขตั้งแต่ 0 ขึ้นไป'
        : null;
  }

  Widget _responsiveFields(List<Widget> children) => LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 650 ? 1 : 2;
        if (columns == 1) return Column(children: children);
        return Wrap(spacing: 14, runSpacing: 1, children: [for (final child in children) SizedBox(width: (constraints.maxWidth - 14) / 2, child: child)]);
      });

  Widget _itemsEditor() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('รายการสินค้าและบริการ *', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF294636)))), TextButton.icon(onPressed: () => setState(() => _items.add(_LineItem())), icon: const Icon(Icons.add_rounded, size: 17), label: const Text('เพิ่มรายการ'))]),
        for (var index = 0; index < _items.length; index++)
          _LineItemEditor(
            index: index,
            item: _items[index],
            onChanged: () => setState(() {}),
            onRemove: _items.length == 1 ? null : () => setState(() { final removed = _items.removeAt(index); removed.dispose(); }),
          ),
        Padding(padding: const EdgeInsets.only(top: 10, bottom: 14), child: Align(alignment: Alignment.centerRight, child: Text('ยอดรวมโดยประมาณ  ฿${_estimatedTotal.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF1D6746), fontWeight: FontWeight.w700, fontSize: 13)))),
      ]);
}

class _LineItem {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController();
  final unitPrice = TextEditingController(text: '0');

  Map<String, dynamic> toPayload() => {
        'name': name.text.trim(),
        'quantity': quantity.text.trim(),
        'unit': unit.text.trim(),
        'unit_price': unitPrice.text.trim().isEmpty ? '0' : unitPrice.text.trim(),
      };

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
    unitPrice.dispose();
  }
}

class _LineItemEditor extends StatelessWidget {
  const _LineItemEditor({required this.index, required this.item, required this.onChanged, this.onRemove});
  final int index;
  final _LineItem item;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF5F8F5), borderRadius: BorderRadius.circular(15)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text('รายการ ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Color(0xFF54705F)))), if (onRemove != null) IconButton(visualDensity: VisualDensity.compact, tooltip: 'ลบรายการ', onPressed: onRemove, icon: const Icon(Icons.close_rounded, size: 17))]),
          LayoutBuilder(builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final fields = [
              TextFormField(controller: item.name, onChanged: (_) => onChanged(), validator: (value) => value == null || value.trim().isEmpty ? 'กรุณาระบุรายการ' : null, decoration: const InputDecoration(labelText: 'รายการ *')),
              TextFormField(controller: item.quantity, onChanged: (_) => onChanged(), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (value) { final number = double.tryParse(value ?? ''); return number == null || !number.isFinite || number <= 0 ? 'จำนวนต้องมากกว่า 0' : null; }, decoration: const InputDecoration(labelText: 'จำนวน *')),
              TextFormField(controller: item.unit, onChanged: (_) => onChanged(), decoration: const InputDecoration(labelText: 'หน่วย')),
              TextFormField(controller: item.unitPrice, onChanged: (_) => onChanged(), keyboardType: const TextInputType.numberWithOptions(decimal: true), validator: (value) { final number = double.tryParse(value ?? '0'); return number == null || !number.isFinite || number < 0 ? 'ราคาไม่ถูกต้อง' : null; }, decoration: const InputDecoration(labelText: 'ราคาต่อหน่วย')),
            ];
            if (narrow) return Column(children: [for (final field in fields) Padding(padding: const EdgeInsets.only(bottom: 9), child: field)]);
            return Row(children: [Expanded(flex: 4, child: fields[0]), const SizedBox(width: 9), Expanded(child: fields[1]), const SizedBox(width: 9), Expanded(child: fields[2]), const SizedBox(width: 9), Expanded(flex: 2, child: fields[3])]);
          }),
        ]),
      );
}

class _TemplateSelector extends StatelessWidget {
  const _TemplateSelector({required this.templates, required this.selected, required this.onChanged, required this.error});
  final List<Map<String, dynamic>> templates;
  final String selected;
  final ValueChanged<String?>? onChanged;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final options = templates.isEmpty ? _fallbackTemplates : templates;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF5EF), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.article_outlined, color: Color(0xFF28744E))),
          const SizedBox(width: 12),
          const Text('แม่แบบ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(child: DropdownButton<String>(isExpanded: true, value: options.any((item) => item['category'] == selected) ? selected : options.first['category']?.toString(), underline: const SizedBox.shrink(), items: [for (final item in options) DropdownMenuItem(value: item['category']?.toString(), child: Text(item['name']?.toString() ?? item['category'].toString()))], onChanged: onChanged)),
          if (error) const Tooltip(message: 'กำลังใช้แม่แบบตัวอย่างที่มาพร้อมแอป', child: Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF9B6B18))),
        ]),
      ),
    );
  }
}

const _fallbackTemplates = <Map<String, dynamic>>[
  {'id': 'po', 'name': 'ใบสั่งซื้อ (PO)', 'category': 'po'},
  {'id': 'pr', 'name': 'ใบขอซื้อ (PR)', 'category': 'pr'},
  {'id': 'repair', 'name': 'ใบแจ้งซ่อม', 'category': 'repair'},
];

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.suggestions, required this.loading, required this.error, required this.onAccept, required this.onDismiss});
  final List<Map<String, dynamic>> suggestions;
  final bool loading;
  final String? error;
  final ValueChanged<String> onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!loading && suggestions.isEmpty && error == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: const Color(0xFFFFF7E7), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xFFF2E2BD))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.auto_awesome_outlined, size: 15, color: Color(0xFF9B6B18)), const SizedBox(width: 6), const Expanded(child: Text('ตัวอย่างข้อความจำลอง · ตรวจสอบก่อนเลือก', style: TextStyle(fontSize: 10, color: Color(0xFF856018), fontWeight: FontWeight.w600))), if (loading) const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8)), if (!loading) IconButton(onPressed: onDismiss, tooltip: 'ปิดคำแนะนำ', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 16))]),
        if (loading && suggestions.isEmpty) const Padding(padding: EdgeInsets.all(7), child: Text('กำลังขอข้อความตัวอย่าง…', style: TextStyle(fontSize: 11, color: Color(0xFF856018)))),
        if (error != null) Padding(padding: const EdgeInsets.all(7), child: Text(error!, style: const TextStyle(fontSize: 11, color: Color(0xFF856018)))),
        for (final suggestion in suggestions)
          Padding(padding: const EdgeInsets.only(top: 5), child: ActionChip(label: Text(suggestion['text'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)), onPressed: () => onAccept(suggestion['text'].toString()))),
      ]),
    );
  }
}

class _DraftDisclaimer extends StatelessWidget {
  const _DraftDisclaimer();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFEAF3ED), borderRadius: BorderRadius.circular(15)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.fact_check_outlined, size: 18, color: Color(0xFF3F7C59)), SizedBox(width: 9), Expanded(child: Text('เอกสารนี้จะบันทึกเป็นร่าง เลขที่ PO/PR ต้องกรอกหรือกำหนดโดยระบบขององค์กร ข้อความแนะนำเป็นตัวอย่างจำลองและไม่มีผลอนุมัติเอกสาร', style: TextStyle(fontSize: 11, color: Color(0xFF4F715A), height: 1.45)))]),
      );
}
