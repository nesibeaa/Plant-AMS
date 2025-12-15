import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import '../../core/config.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

const Map<String, String> _diseaseTranslations = {
  'Aloe_Healthy': 'Aloe (Sağlıklı)',
  'Aloe_Anthracnose': 'Aloe - Antraknoz',
  'Aloe_LeafSpot': 'Aloe - Yaprak Lekesi',
  'Aloe_Rust': 'Aloe - Pas Hastalığı',
  'Aloe_Sunburn': 'Aloe - Güneş Yanığı',
  'Cactus_Healthy': 'Kaktüs (Sağlıklı)',
  'Cactus_Dactylopius_Opuntia': 'Kaktüs - Dactylopius Opuntia',
  'Money_Plant_Healthy': 'Para Çiçeği (Sağlıklı)',
  'Money_Plant_Bacterial_wilt_disease': 'Para Çiçeği - Bakteriyel Solgunluk',
  'Money_Plant_Manganese_Toxicity': 'Para Çiçeği - Mangan Fazlalığı',
  'Snake_Plant_Healthy': 'Paşa Kılıcı (Sağlıklı)',
  'Snake_Plant_Anthracnose': 'Paşa Kılıcı - Antraknoz',
  'Snake_Plant_Leaf_Withering': 'Paşa Kılıcı - Yaprak Solması',
  'Spider_Plant_Healthy': 'Kurdele Çiçeği (Sağlıklı)',
  'Spider_Plant_Fungal_leaf_spot': 'Kurdele Çiçeği - Mantar Lekesi',
  'Spider_Plant_Leaf_Tip_Necrosis': 'Kurdele Çiçeği - Yaprak Ucu Nekrozu',
};

class PlantScanPage extends StatefulWidget {
  const PlantScanPage({super.key});

  @override
  State<PlantScanPage> createState() => _PlantScanPageState();
}

class _PlantScanPageState extends State<PlantScanPage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _uploading = false;
  Map<String, dynamic>? _analysisResult;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImageFile = image;
          _selectedImageBytes = bytes;
          _analysisResult = null;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Fotoğraf seçilirken hata: $e\n\nWeb tarayıcıda:\n- "Galeri" butonu dosya seçme penceresi açar\n- "Kamera" butonu tarayıcı izni ister';
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImageFile == null || _selectedImageBytes == null) return;

    setState(() {
      _uploading = true;
      _error = null;
      _analysisResult = null;
    });

    try {
      final uri = Uri.parse('${AppConfig.baseUrl}/api/v1/analyze-plant');
      final request = http.MultipartRequest('POST', uri);

      if (kIsWeb) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            _selectedImageBytes!,
            filename: _selectedImageFile!.name,
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath('image', _selectedImageFile!.path),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _analysisResult = data;
          _uploading = false;
        });
      } else {
        setState(() {
          _error = 'Analiz hatası: ${response.statusCode} - ${response.body}';
          _uploading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Bağlantı hatası: $e';
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bitki Analizi', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          GlassContainer(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fotoğraf Yükle', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    color: AppColors.glassSurface(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.glassSurface(0.14), style: BorderStyle.solid, width: 1.2),
                  ),
                  child: _selectedImageBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(_selectedImageBytes!, fit: BoxFit.cover),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_camera_outlined, size: 54, color: Colors.white54),
                              const SizedBox(height: 12),
                              Text('Bitki fotoğrafı seçin', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70)),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Kamera'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galeri'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selectedImageBytes != null)
                  ElevatedButton.icon(
                    onPressed: _uploading ? null : _analyzeImage,
                    icon: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(_uploading ? 'Analiz ediliyor...' : 'Analizi Başlat'),
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            GlassContainer(
              colorOpacity: 0.14,
              borderRadius: 16,
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ],
          if (_analysisResult != null) ...[
            const SizedBox(height: 22),
            _buildAnalysisResultCard(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisResultCard(ThemeData theme) {
    final result = Map<String, dynamic>.from(_analysisResult!);
    final Map<String, dynamic>? analysis =
        result['analysis'] != null ? Map<String, dynamic>.from(result['analysis'] as Map) : null;
    final List<Map<String, dynamic>> alternatives = (analysis?['alternatives'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        [];
    final displayName = (result['disease_display'] as String?)?.trim();
    final message = result['message'] as String?;
    final healthScore = result['health_score'] as num?;
    final healthLabel = result['health_label'] as String?;
    final confidenceScore = result['confidence_score'] as num?;

    return GlassContainer(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.35)),
                ),
                child: const Icon(Icons.eco_outlined, color: AppColors.success),
              ),
              const SizedBox(width: 12),
              Text('Analiz Sonucu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          _resultRow('Güven Durumu', result['status']?.toString() ?? '—'),
          if (confidenceScore != null)
            _resultRow('Güven Skoru', '${(confidenceScore * 100).clamp(0, 100).toStringAsFixed(0)}%'),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber.withOpacity(0.4)),
              ),
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          ],
          if (healthScore != null)
            _resultRow('Sağlık Skoru', '${(healthScore * 100).clamp(0, 100).toStringAsFixed(0)}%'),
          if (healthLabel != null && healthLabel.isNotEmpty)
            _resultRow('Sağlık Durumu', healthLabel),
          if (displayName != null && displayName.isNotEmpty)
            _resultRow('Hastalık Tahmini', displayName)
          else if (result['disease'] != null)
            _resultRow('Hastalık Tahmini', result['disease'].toString()),
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Tahmin Detayları', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...alternatives.take(3).toList().asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final alt = entry.value;
              final confidence = (alt['confidence'] is num) ? (alt['confidence'] as num) : 0;
              final rawClass = alt['class_name']?.toString() ?? '';
              final names = _translateDisease(alt['display_name']?.toString(), rawClass);
              final modelName = alt['model'].toString();
              final isHealthy = rawClass.toLowerCase().contains('healthy');

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassSurface(0.2)),
                  color: AppColors.glassSurface(0.06),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$idx.', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            names['tr']!,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _detailRow(theme, 'Bilimsel Adı', names['latin']!),
                    const SizedBox(height: 4),
                    _detailRow(
                      theme,
                      'Güven Skoru',
                      '${(confidence * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    ),
                    const SizedBox(height: 4),
                    _detailRow(
                      theme,
                      'Sağlık Yorumu',
                      isHealthy ? 'Sağlıklı görünüm' : 'Riskli belirtiler',
                    ),
                    const SizedBox(height: 4),
                    _detailRow(theme, 'Model', modelName),
                  ],
                ),
              );
            }),
          ],
          if (result['recommendations'] != null) ...[
            const SizedBox(height: 14),
            Text('Bakım Önerileri', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...(result['recommendations'] as List)
                .map((rec) => Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(rec.toString(), style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    )),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: Colors.white54, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Map<String, String> _translateDisease(String? displayName, String rawClass) {
    final latin = (displayName?.trim().isNotEmpty == true ? displayName!.trim() : _prettifyClassName(rawClass));
    final turkish = _diseaseTranslations[rawClass] ?? latin;
    return {'tr': turkish, 'latin': latin};
  }

  String _prettifyClassName(String value) {
    return value
        .split('_')
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}
