import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class SeqotiaApi {
  SeqotiaApi()
      : dio = Dio(BaseOptions(
          baseUrl: const String.fromEnvironment(
            'SEQOTIA_API_BASE_URL',
            defaultValue: 'http://127.0.0.1:8000',
          ),
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 30),
          headers: const {'Accept': 'application/json'},
        ));

  final Dio dio;

  Future<T> _request<T>(Future<Response<dynamic>> Function() action,
      T Function(dynamic data) decode) async {
    try {
      final response = await action();
      return decode(response.data);
    } on DioException catch (error) {
      final payload = error.response?.data;
      final message = payload is Map && payload['error'] is Map
          ? (payload['error']['message']?.toString() ?? 'เชื่อมต่อบริการไม่สำเร็จ')
          : error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.connectionError
              ? 'เชื่อมต่อ Backend ไม่ได้ กรุณาเปิดบริการในเครื่องแล้วลองอีกครั้ง'
              : 'คำขอไม่สำเร็จ กรุณาลองใหม่';
      throw ApiFailure(message);
    } catch (error) {
      if (error is ApiFailure) rethrow;
      throw const ApiFailure('ได้รับข้อมูลจาก Backend ในรูปแบบที่ไม่ถูกต้อง');
    }
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  List<Map<String, dynamic>> _asList(dynamic value) =>
      (value as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();

  Future<Map<String, dynamic>> dashboard() =>
      _request(() => dio.get('/api/dashboard/summary'), _asMap);

  Future<Map<String, dynamic>> health() =>
      _request(() => dio.get('/health'), _asMap);

  Future<List<Map<String, dynamic>>> documents({
    String search = '',
    int? folderId,
    String category = '',
    String approvalStatus = '',
    String processingStatus = '',
    String sort = 'updated_desc',
  }) =>
      _request(
        () => dio.get('/api/documents', queryParameters: {
          if (search.trim().isNotEmpty) 'q': search.trim(),
          if (folderId != null) 'folder_id': folderId,
          if (category.isNotEmpty) 'category': category,
          if (approvalStatus.isNotEmpty) 'approval_status': approvalStatus,
          if (processingStatus.isNotEmpty) 'processing_status': processingStatus,
          'sort': sort,
        }),
        _asList,
      );

  Future<List<Map<String, dynamic>>> folders({String search = ''}) =>
      _request(
        () => dio.get('/api/folders', queryParameters: {
          if (search.trim().isNotEmpty) 'q': search.trim(),
        }),
        _asList,
      );

  Future<List<Map<String, dynamic>>> templates() =>
      _request(() => dio.get('/api/templates'), _asList);

  Future<Map<String, dynamic>> upload(PlatformFile file, {int? folderId}) async {
    if (file.path == null) {
      throw const ApiFailure('ไม่สามารถอ่านไฟล์จากตำแหน่งที่เลือกได้');
    }
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path!, filename: file.name),
      if (folderId != null) 'folder_id': folderId.toString(),
    });
    return _request(
      () => dio.post('/api/documents/upload', data: form),
      _asMap,
    );
  }

  Future<Map<String, dynamic>> createFolder(String name, {int? parentId}) =>
      _request(
        () => dio.post('/api/folders', data: {
          'name': name,
          'parent_id': parentId,
        }),
        _asMap,
      );

  Future<Map<String, dynamic>> updateFolder(
          int id, Map<String, dynamic> changes) =>
      _request(() => dio.patch('/api/folders/$id', data: changes), _asMap);

  Future<void> archiveFolder(int id) async {
    await _request(() => dio.delete('/api/folders/$id'), (data) => data);
  }

  Future<Map<String, dynamic>> saveDraft({
    required String category,
    required String title,
    required Map<String, dynamic> metadata,
    int? folderId,
  }) =>
      _request(
        () => dio.post('/api/documents', data: {
          'category': category,
          'title': title,
          'metadata': metadata,
          'folder_id': folderId,
        }),
        _asMap,
      );

  Future<Map<String, dynamic>> suggest({
    required String documentType,
    required String field,
    required String text,
  }) =>
      _request(
        () => dio.post('/api/ai/suggestions', data: {
          'document_type': documentType,
          'field_name': field,
          'text': text,
        }),
        _asMap,
      );

  Future<void> feedback(String suggestionId, {required bool accepted}) async {
    await _request(
      () => dio.post('/api/ai/feedback', data: {
        'suggestion_id': suggestionId,
        'accepted': accepted,
      }),
      (data) => data,
    );
  }

  Future<Map<String, dynamic>> moveDocument(String id, int? folderId) =>
      _request(
        () => dio.patch('/api/documents/$id', data: {'folder_id': folderId}),
        _asMap,
      );

  Future<void> archiveDocument(String id) async {
    await _request(() => dio.delete('/api/documents/$id'), (data) => data);
  }

  Future<Map<String, dynamic>> reprocessDocument(String id) =>
      _request(() => dio.post('/api/documents/$id/reprocess'), _asMap);

  Future<List<Map<String, dynamic>>> documentHistory(String id) =>
      _request(() => dio.get('/api/documents/$id/history'), _asList);

  Future<void> downloadDocument(String id, String path) async {
    await _request(
      () => dio.download('/api/documents/$id/download', path),
      (data) => data,
    );
  }
}
