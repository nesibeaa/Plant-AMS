import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../../services/api_service.dart';
import '../../state/app_state.dart';
import '../theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// PlantVillage dataset bitki türü çevirileri
const Map<String, String> _plantTypeTranslations = {
  'Apple': 'Elma',
  'Cherry': 'Kiraz',
  'Corn': 'Mısır',
  'Grape': 'Üzüm',
  'Peach': 'Şeftali',
  'Pepper': 'Biber',
  'Pepper,_bell': 'Biber',
  'Pepper, bell': 'Biber',
  'bell_pepper': 'Biber',
  'Potato': 'Patates',
  'Strawberry': 'Çilek',
  'Tomato': 'Domates',
  'Blueberry': 'Yaban Mersini',
  'Raspberry': 'Ahududu',
  'Soybean': 'Soya',
  'Squash': 'Kabak',
  'Orange': 'Portakal',
  'Citrus': 'Turunçgil',
};

// Bitki türü normalize fonksiyonu
String _normalizePlantType(String rawType) {
  // Virgül ve alt çizgi ile ayrılmış formatları normalize et
  var normalized = rawType.trim();
  
  // "Pepper,_bell" veya "Pepper, bell" -> "Pepper"
  if (normalized.toLowerCase().contains('pepper')) {
    if (normalized.contains(',') || normalized.contains('_')) {
      normalized = 'Pepper';
    }
  }
  
  // "Corn_(maize)" -> "Corn"
  if (normalized.contains('(')) {
    normalized = normalized.split('(')[0].trim();
  }
  
  // Alt çizgileri temizle
  normalized = normalized.replaceAll(RegExp(r'_+$'), '').trim();
  
  return normalized;
}

// PlantVillage dataset hastalık çevirileri (sadece hastalıklar, healthy değil)
const Map<String, String> _plantVillageDiseaseTranslations = {
  'Apple_scab': 'Elma Kabuğu',
  'Black_rot': 'Siyah Çürüklük',
  'Cedar_apple_rust': 'Sedir Elma Pası',
  'Powdery_mildew': 'Külleme',
  'Cercospora_leaf_spot Gray_leaf_spot': 'Cercospora Yaprak Lekesi',
  'Common_rust': 'Yaygın Pas',
  'Esca_(Black_Measles)': 'Esca (Siyah Kızamık)',
  'Leaf_blight_(Isariopsis_Leaf_Spot)': 'Yaprak Yanıklığı (Isariopsis)',
  'Haunglongbing_(Citrus_greening)': 'Huanglongbing (Turunçgil Yeşillenmesi)',
  'Bacterial_spot': 'Bakteriyel Leke',
  'Early_blight': 'Erken Yanıklık',
  'Late_blight': 'Geç Yanıklık',
  'Leaf_Mold': 'Yaprak Küfü',
  'Septoria_leaf_spot': 'Septoria Yaprak Lekesi',
  'Spider_mites Two-spotted_spider_mite': 'İki Noktalı Kırmızı Örümcek',
  'Target_Spot': 'Hedef Leke',
  'Tomato_mosaic_virus': 'Domates Mozaik Virüsü',
  'Tomato_Yellow_Leaf_Curl_Virus': 'Domates Sarı Yaprak Kıvırcık Virüsü',
  'Leaf_scorch': 'Yaprak Yanması',
};

class PlantScanPage extends StatefulWidget {
  const PlantScanPage({super.key});

  @override
  State<PlantScanPage> createState() => _PlantScanPageState();
}

class _PlantScanPageState extends State<PlantScanPage> {
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();
  XFile? _selectedImageFile;
  Uint8List? _selectedImageBytes;
  bool _uploading = false;
  Map<String, dynamic>? _analysisResult;
  String? _error;
  // Artık sadece PlantVillage dataseti kullanılıyor, model seçimi yok

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
        // Fotoğraf seçildiğinde otomatik olarak analizi başlat
        _analyzeImage();
      }
    } catch (e) {
      setState(() {
        _error = 'Fotoğraf seçilirken hata: $e';
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
      final data = await _apiService.analyzePlant(
        imageBytes: _selectedImageBytes!,
        model: 'plantvillage', // Sadece PlantVillage dataseti kullanılıyor
      );
      setState(() {
        _analysisResult = data;
        _uploading = false;
      });
      
      // Analiz sonucunu modal bottom sheet'te göster
      if (mounted && data != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showAnalysisResultModal();
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Analiz hatası: $e';
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        // Header Section with green background
        Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TEŞHİS VE TEDAVİ',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bitki Analizi',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                      letterSpacing: -0.5,
                    ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Main Photo Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Plant Image or Placeholder
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: _selectedImageBytes != null
                          ? AspectRatio(
                              aspectRatio: 4 / 3,
                              child: Image.memory(
                                _selectedImageBytes!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Container(
                              height: 280,
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/Analiz2.png',
                                    width: 180,
                                    height: 180,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Icon(
                                        Icons.eco_outlined,
                                        size: 80,
                                        color: AppColors.primary.withOpacity(0.3),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                    ),
                    // Camera Button (overlay at bottom center)
                    Positioned(
                      bottom: 20,
                      child: GestureDetector(
                        onTap: () => _showImageSourceDialog(context),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Subtitle text
              Text(
                'Fotoğraf ile bitki sağlığını kontrol edin',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Common Issues Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showCommonIssues(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.withOpacity(0.9),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Yaygın Sorunlar',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
              ),

              // Loading indicator
              if (_uploading) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Analiz yapılıyor...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.danger,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  void _showAnalysisResultModal() {
    if (_analysisResult == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.border, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Analiz Sonucu',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: _buildAnalysisResultCard(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCommonIssues(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Yaygın Sorunlar',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark,
                              ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Diseases list
                  Expanded(
                    child: _CommonIssuesContent(scrollController: scrollController),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showImageSourceDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Fotoğraf Seç',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // İpucu Bölümü
                      _buildPhotoTips(),
                      const SizedBox(height: 32),
                      // Fotoğraf Seçme Seçenekleri
                      Row(
                        children: [
                          Expanded(
                            child: _ImageSourceOption(
                              icon: Icons.camera_alt,
                              label: 'Kamera',
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.camera);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ImageSourceOption(
                              icon: Icons.photo_library,
                              label: 'Galeri',
                              onTap: () {
                                Navigator.pop(context);
                                _pickImage(ImageSource.gallery);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoTips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nasıl fotoğraf çekmelisiniz?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 24),
        // Doğru örnek - Büyük daire
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.border,
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/uygun.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppColors.surface,
                        child: const Icon(Icons.image_outlined, size: 48),
                      );
                    },
                  ),
                ),
              ),
              // Yeşil check ikonu
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E), // yeşil
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 48),
        // Yanlış örnekler - 3 küçük daire
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildWrongExample(
              imagePath: 'assets/images/cok_yakin.png',
              label: 'Çok yakın',
            ),
            _buildWrongExample(
              imagePath: 'assets/images/cok_uzak.png',
              label: 'Çok uzak',
            ),
            _buildWrongExample(
              imagePath: 'assets/images/birden_fazla_tur.png',
              label: 'Birden fazla tür',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWrongExample({required String imagePath, required String label}) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.border,
                  width: 1.5,
                ),
              ),
              child: ClipOval(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.surface,
                      child: const Icon(Icons.image_outlined, size: 24),
                    );
                  },
                ),
              ),
            ),
            // Kırmızı X ikonu
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444), // kırmızı
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 90,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysisResultCard() {
    final result = Map<String, dynamic>.from(_analysisResult!);
    final Map<String, dynamic>? analysis = result['analysis'] != null
        ? Map<String, dynamic>.from(result['analysis'] as Map)
        : null;
    final List<Map<String, dynamic>> alternatives = (analysis?['alternatives'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ??
        [];
    final displayName = (result['disease_display'] as String?)?.trim() ??
        (result['disease'] as String?) ??
        'Bilinmiyor';
    final message = result['message'] as String?;
    final healthScore = result['health_score'] as num?;
    final healthLabel = result['health_label'] as String?;
    final confidenceScore = result['confidence_score'] as num?;
    
    // Bitki türü ve sağlık durumunu belirle (Türkçe çeviri ile)
    String? plantType;
    bool isHealthy = false;
    String? rawClassName;
    
    if (alternatives.isNotEmpty) {
      rawClassName = alternatives.first['class_name']?.toString();
      if (rawClassName != null && rawClassName.contains('___')) {
        final parts = rawClassName.split('___');
        var rawPlantType = parts[0];
        
        // Plant type'ı normalize et: "Corn_(maize)" -> "Corn", "Pepper,_bell" -> "Pepper"
        rawPlantType = _normalizePlantType(rawPlantType);
        
        final rawDiseaseOrStatus = parts.length > 1 ? parts[1] : '';
        var normalizedDisease = rawDiseaseOrStatus.replaceAll(RegExp(r'_+$'), '').trim();
        plantType = _plantTypeTranslations[rawPlantType] ?? rawPlantType;
        isHealthy = normalizedDisease.toLowerCase() == 'healthy';
      }
    }
    // Alternatif olarak result'tan da bakabiliriz
    if (plantType == null) {
      final rawDisease = result['disease']?.toString() ?? '';
      rawClassName ??= rawDisease;
      if (rawDisease.contains('___')) {
        final parts = rawDisease.split('___');
        var rawPlantType = parts[0];
        
        // Plant type'ı normalize et: "Corn_(maize)" -> "Corn", "Pepper,_bell" -> "Pepper"
        rawPlantType = _normalizePlantType(rawPlantType);
        
        final rawDiseaseOrStatus = parts.length > 1 ? parts[1] : '';
        var normalizedDisease = rawDiseaseOrStatus.replaceAll(RegExp(r'_+$'), '').trim();
        if (plantType == null) {
          plantType = _plantTypeTranslations[rawPlantType] ?? rawPlantType;
        }
        isHealthy = normalizedDisease.toLowerCase() == 'healthy';
      }
    }
    
    // Son kontrol: Eğer hala rawClassName yoksa ama displayName'den çıkarabilirsek
    if ((rawClassName == null || rawClassName.isEmpty) && displayName.contains('•')) {
      // Display name formatı: "Corn (maize) • Northern Leaf Blight" gibi
      // Bunu "Corn___Northern_Leaf_Blight" formatına çevirmeye çalış
      final displayParts = displayName.split('•');
      if (displayParts.length >= 2) {
        final plantPart = displayParts[0].trim();
        final diseasePart = displayParts[1].trim();
        
        // Plant type'ı bul
        String? foundPlantType;
        for (var entry in _plantTypeTranslations.entries) {
          if (plantPart.toLowerCase().contains(entry.key.toLowerCase()) || 
              plantPart.toLowerCase().contains(entry.value.toLowerCase())) {
            foundPlantType = entry.key;
            break;
          }
        }
        
        if (foundPlantType != null) {
          // Disease part'ı normalize et
          final normalizedDisease = diseasePart.replaceAll(' ', '_');
          rawClassName = '${foundPlantType}___$normalizedDisease';
          if (plantType == null) {
            plantType = _plantTypeTranslations[foundPlantType] ?? foundPlantType;
          }
          isHealthy = normalizedDisease.toLowerCase() == 'healthy';
        }
      }
    }
    
    // DEBUG: Parse edilen değerleri yazdır
    // Türkçe display name oluştur
    final turkishDisplayName = _getTurkishDisplayName(rawClassName, plantType, isHealthy);
    // Türkçe bitki türünü al (analiz sonuçlarında gösterim için)
    final turkishPlantType = plantType ?? 'Bilinmeyen Bitki';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: const Icon(Icons.eco_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Analiz Sonucu',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _resultRow(
            'Hastalık Tahmini',
            isHealthy ? turkishPlantType : turkishDisplayName,
            badgeColor: isHealthy 
                ? AppColors.success.withOpacity(0.1)
                : AppColors.warning.withOpacity(0.1),
            badgeBorder: isHealthy
                ? AppColors.success.withOpacity(0.4)
                : AppColors.warning.withOpacity(0.4),
            badgeText: isHealthy 
                ? AppColors.success
                : AppColors.warning,
          ),
          if (confidenceScore != null)
            _resultRow(
              'Güven Skoru',
              '${(confidenceScore * 100).clamp(0, 100).toStringAsFixed(0)}%',
              progressValue: confidenceScore.toDouble(),
            ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.warning,
                    ),
              ),
            ),
          ],
          if (healthScore != null)
            _resultRow(
              'Sağlık Skoru',
              '${(healthScore * 100).clamp(0, 100).toStringAsFixed(0)}%',
              progressValue: healthScore.toDouble(),
            ),
          if (healthLabel != null && healthLabel.isNotEmpty)
            _resultRow('Sağlık Durumu', healthLabel),
          
          // Bakım Detayları Bölümü
          const SizedBox(height: 24),
          Text(
            'Bakım',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 16),
          ..._buildCareDetails(plantType, isHealthy, rawClassName),
          
          // Tesis Gereksinimleri Bölümü
          const SizedBox(height: 32),
          Text(
            'Tesis Gereksinimleri',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 16),
          ..._buildFacilityRequirements(plantType, isHealthy, rawClassName),
          
          // Bitkilerime Kaydet Butonu
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _savePlantToMyPlants(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
              ),
              child: Text(
                'Bitkilerime Kaydet',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCareDetails(String? plantType, bool isHealthy, String? rawClassName) {
    final careInfo = _getPlantCareInfo(plantType, isHealthy, rawClassName);
    
    return [
      _buildCareDetailCard(
        icon: Icons.bar_chart,
        label: 'Zorluk',
        value: careInfo['difficulty'] ?? 'Orta',
        details: careInfo['difficultyDetails'] ?? 'Bu bitki türü için orta seviye bakım bilgisi gereklidir.',
      ),
      const SizedBox(height: 12),
      _buildCareDetailCard(
        icon: Icons.water_drop,
        label: 'Su',
        value: careInfo['water'] ?? 'Haftada 2-3 kez',
        details: careInfo['waterDetails'] ?? 'Toprak kurumaya başladığında sulama yapın.',
      ),
      const SizedBox(height: 12),
      _buildCareDetailCard(
        icon: Icons.inventory_2,
        label: 'Gübreleme',
        value: careInfo['fertilization'] ?? 'Ayda bir',
        details: careInfo['fertilizationDetails'] ?? 'Büyüme mevsiminde düzenli gübreleme yapın.',
      ),
      const SizedBox(height: 12),
      _buildCareDetailCard(
        icon: Icons.content_cut,
        label: 'Budama',
        value: careInfo['pruning'] ?? 'Gerektiğinde',
        details: careInfo['pruningDetails'] ?? 'Ölü ve hastalıklı dalları düzenli olarak budayın.',
      ),
      const SizedBox(height: 12),
      _buildCareDetailCard(
        icon: Icons.agriculture,
        label: 'Saksı değişimi',
        value: careInfo['repotting'] ?? '2 yılda bir',
        details: careInfo['repottingDetails'] ?? 'Kökler saksıyı doldurduğunda daha büyük saksıya alın.',
      ),
    ];
  }

  // Tesis Gereksinimleri Bölümü
  List<Widget> _buildFacilityRequirements(String? plantType, bool isHealthy, String? rawClassName) {
    final requirements = _getFacilityRequirements(plantType, isHealthy, rawClassName);
    
    return [
      _buildRequirementCard(
        icon: Icons.local_florist,
        label: 'Yetiştirme Ortamı',
        value: requirements['pot'] ?? 'Standart saksı',
        description: requirements['potDetails'] ?? 'Bitki boyutuna uygun saksı kullanın.',
      ),
      const SizedBox(height: 12),
      _buildRequirementCard(
        icon: Icons.eco,
        label: 'Toprak',
        value: requirements['soil'] ?? 'Drenajlı toprak',
        description: requirements['soilDetails'] ?? 'İyi drenajlı toprak karışımı kullanın.',
      ),
      const SizedBox(height: 12),
      _buildRequirementCard(
        icon: Icons.wb_sunny,
        label: 'Aydınlatma',
        value: requirements['lighting'] ?? 'Orta ışık',
        description: requirements['lightingDetails'] ?? 'Bitki türüne uygun aydınlatma sağlayın.',
      ),
      const SizedBox(height: 12),
      _buildRequirementCard(
        icon: Icons.water_drop_outlined,
        label: 'Nem',
        value: requirements['humidity'] ?? 'Orta nem',
        description: requirements['humidityDetails'] ?? 'Uygun nem seviyesi sağlayın.',
      ),
      const SizedBox(height: 12),
      _buildRequirementCard(
        icon: Icons.bedtime,
        label: 'Hazırda bekletme',
        value: requirements['dormancy'] ?? 'Yok',
        description: requirements['dormancyDetails'] ?? 'Bitki türüne göre dinlenme dönemi.',
      ),
      const SizedBox(height: 12),
      _buildRequirementCard(
        icon: Icons.air,
        label: 'CO2 Seviyesi',
        value: requirements['co2'] ?? 'Normal',
        description: requirements['co2Details'] ?? 'Uygun CO2 seviyesi sağlayın.',
      ),
      const SizedBox(height: 12),
      _buildRequirementCard(
        icon: Icons.thermostat,
        label: 'Sıcaklık',
        value: requirements['temperature'] ?? 'Oda sıcaklığı',
        description: requirements['temperatureDetails'] ?? 'Bitki türüne uygun sıcaklık aralığı.',
      ),
    ];
  }

  Map<String, String> _getFacilityRequirements(String? plantType, bool isHealthy, String? rawClassName) {
    if (plantType == null) {
      return _defaultFacilityRequirements();
    }
    
    // Plant type'ı normalize et: "Corn_(maize)" -> "corn", "Mısır" -> "mısır", "Yaban Mersini" -> "yaban_mersini"
    // Önce İngilizce'den Türkçe'ye çevir varsa
    var normalizedEnglish = _normalizePlantType(plantType);
    var plantTypeLower = normalizedEnglish.toLowerCase().trim();
    
    // Eğer Türkçe ise direkt kullan
    if (_plantTypeTranslations.containsValue(plantType)) {
      plantTypeLower = plantType.toLowerCase().trim();
    }
    
    if (plantTypeLower.contains('(')) {
      plantTypeLower = plantTypeLower.split('(')[0].trim();
    }
    plantTypeLower = plantTypeLower.replaceAll(RegExp(r'_+$'), '').trim();
    // Boşlukları alt çizgiye çevir: "yaban mersini" -> "yaban_mersini"
    plantTypeLower = plantTypeLower.replaceAll(' ', '_');
    
    // "Pepper,_bell" veya "Pepper, bell" -> "pepper"
    if (plantTypeLower.contains('pepper')) {
      plantTypeLower = 'pepper';
    }
    
    // Bitki türüne göre tesis gereksinimleri
    switch (plantTypeLower) {
      case 'apple':
      case 'elma':
        return _appleFacilityRequirements();
      case 'tomato':
      case 'domates':
        return _tomatoFacilityRequirements();
      case 'corn':
      case 'mısır':
        return _cornFacilityRequirements();
      case 'grape':
      case 'üzüm':
        return _grapeFacilityRequirements();
      case 'cherry':
      case 'kiraz':
        return _cherryFacilityRequirements();
      case 'peach':
      case 'şeftali':
        return _peachFacilityRequirements();
      case 'pepper':
      case 'bell_pepper':
      case 'biber':
        return _pepperFacilityRequirements();
      case 'potato':
      case 'patates':
        return _potatoFacilityRequirements();
      case 'strawberry':
      case 'çilek':
        return _strawberryFacilityRequirements();
      case 'citrus':
      case 'orange':
      case 'lemon':
      case 'turunçgil':
        return _citrusFacilityRequirements();
      case 'blueberry':
      case 'yaban_mersini':
        return _blueberryFacilityRequirements();
      case 'raspberry':
      case 'ahududu':
        return _raspberryFacilityRequirements();
      case 'soybean':
      case 'soya':
        return _soybeanFacilityRequirements();
      case 'squash':
      case 'kabak':
        return _squashFacilityRequirements();
      default:
        return _defaultFacilityRequirements();
    }
  }

  Widget _buildRequirementCard({
    required IconData icon,
    required String label,
    required String value,
    required String description,
  }) {
    return GestureDetector(
      onTap: () => _showRequirementDetailDialog(context, label, value, description),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.primary,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showRequirementDetailDialog(BuildContext context, String label, String value, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Map<String, String> _getPlantCareInfo(String? plantType, bool isHealthy, String? rawClassName) {
    // Önce hastalığa özel bakım bilgisi var mı kontrol et
    // rawClassName varsa ve bitki hasta ise, mutlaka özel bakım bilgisi ara
    if (rawClassName != null && rawClassName.isNotEmpty && !isHealthy) {
      // rawClassName'i trim et ve normalize et
      var normalizedRawClass = rawClassName.trim();
      
      // Önce orijinal formatı dene
      var diseaseSpecific = _getDiseaseSpecificCareInfo(normalizedRawClass);
      
      // Eğer eşleşmediyse, lowercase versiyonu dene
      if (diseaseSpecific == null && normalizedRawClass != normalizedRawClass.toLowerCase()) {
        diseaseSpecific = _getDiseaseSpecificCareInfo(normalizedRawClass.toLowerCase());
      }
      
      if (diseaseSpecific != null) {
        return diseaseSpecific;
      }
    }
    
    if (plantType == null) {
      return _defaultCareInfo(isHealthy);
    }
    
    // Plant type'ı normalize et: "Corn_(maize)" -> "corn", "Mısır" -> "mısır", "Yaban Mersini" -> "yaban_mersini"
    // Önce İngilizce'den Türkçe'ye çevir varsa
    var normalizedEnglish = _normalizePlantType(plantType);
    var plantTypeLower = normalizedEnglish.toLowerCase().trim();
    
    // Eğer Türkçe ise direkt kullan
    if (_plantTypeTranslations.containsValue(plantType)) {
      plantTypeLower = plantType.toLowerCase().trim();
    }
    
    // Parantez içindeki kısımları temizle: "corn_(maize)" -> "corn"
    if (plantTypeLower.contains('(')) {
      plantTypeLower = plantTypeLower.split('(')[0].trim();
    }
    // Alt çizgileri temizle: "corn_" -> "corn"
    plantTypeLower = plantTypeLower.replaceAll(RegExp(r'_+$'), '').trim();
    // Boşlukları alt çizgiye çevir: "yaban mersini" -> "yaban_mersini"
    plantTypeLower = plantTypeLower.replaceAll(' ', '_');
    
    // "Pepper,_bell" veya "Pepper, bell" -> "pepper"
    if (plantTypeLower.contains('pepper')) {
      plantTypeLower = 'pepper';
    }
    
    // Bitki türüne göre bakım bilgileri
    switch (plantTypeLower) {
      case 'apple':
      case 'elma':
        return isHealthy ? _appleCareInfoHealthy() : _appleCareInfoSick();
      case 'tomato':
      case 'domates':
        return isHealthy ? _tomatoCareInfoHealthy() : _tomatoCareInfoSick();
      case 'corn':
      case 'mısır':
        return isHealthy ? _cornCareInfoHealthy() : _cornCareInfoSick();
      case 'grape':
      case 'üzüm':
        return isHealthy ? _grapeCareInfoHealthy() : _grapeCareInfoSick();
      case 'cherry':
      case 'kiraz':
        return isHealthy ? _cherryCareInfoHealthy() : _cherryCareInfoSick();
      case 'peach':
      case 'şeftali':
        return isHealthy ? _peachCareInfoHealthy() : _peachCareInfoSick();
      case 'pepper':
      case 'bell_pepper':
      case 'biber':
        return isHealthy ? _pepperCareInfoHealthy() : _pepperCareInfoSick();
      case 'potato':
      case 'patates':
        return isHealthy ? _potatoCareInfoHealthy() : _potatoCareInfoSick();
      case 'strawberry':
      case 'çilek':
        return isHealthy ? _strawberryCareInfoHealthy() : _strawberryCareInfoSick();
      case 'citrus':
      case 'orange':
      case 'lemon':
      case 'turunçgil':
        return isHealthy ? _citrusCareInfoHealthy() : _citrusCareInfoSick();
      case 'blueberry':
      case 'yaban_mersini':
        return isHealthy ? _blueberryCareInfoHealthy() : _defaultCareInfo(false);
      case 'raspberry':
      case 'ahududu':
        return isHealthy ? _raspberryCareInfoHealthy() : _defaultCareInfo(false);
      case 'soybean':
      case 'soya':
        return isHealthy ? _soybeanCareInfoHealthy() : _defaultCareInfo(false);
      case 'squash':
      case 'kabak':
        return isHealthy ? _squashCareInfoHealthy() : _squashCareInfoSick();
      default:
        return _defaultCareInfo(isHealthy);
    }
  }

  // Hastalığa özel bakım bilgileri (bitki___hastalık formatı için)
  Map<String, String>? _getDiseaseSpecificCareInfo(String rawClass) {
    if (!rawClass.contains('___')) return null;
    
    final parts = rawClass.split('___');
    if (parts.length < 2) return null;
    
    // Plant type'ı normalize et: "Corn_(maize)" -> "corn", "Pepper,_bell" -> "pepper"
    var rawPlantType = parts[0];
    var normalizedEnglish = _normalizePlantType(rawPlantType);
    var plantType = normalizedEnglish.toLowerCase().trim();
    
    // Alt çizgileri temizle: "corn_" -> "corn"
    plantType = plantType.replaceAll(RegExp(r'_+$'), '').trim();
    
    // "Pepper,_bell" veya "Pepper, bell" -> "pepper"
    if (plantType.contains('pepper')) {
      plantType = 'pepper';
    }
    
    var disease = parts[1].toLowerCase().trim(); // Hastalık adını da küçük harfe çevir ve trim et
    // Disease'deki son alt çizgileri temizle: "common_rust_" -> "common_rust"
    disease = disease.replaceAll(RegExp(r'_+$'), '').trim();
    
    // Her bitki-hastalık kombinasyonu için özel bakım bilgileri
    var key = '${plantType}___$disease';
    
    print('=== DEBUG: _getDiseaseSpecificCareInfo ===');
    print('rawClass: $rawClass');
    print('plantType: $plantType');
    print('disease: $disease');
    print('key: $key');
    
    // Debug: Tüm olası formatları dene
    Map<String, String>? result;
    
    // Önce normal key ile dene
    result = _tryGetDiseaseInfo(key);
    if (result != null) {
      print('✅ Found match with key: $key');
      return result;
    }
    print('❌ No match with key: $key');
    
    // Eğer disease'de boşluk varsa, underscore ile de dene
    if (disease.contains(' ')) {
      key = '${plantType}___${disease.replaceAll(' ', '_')}';
      result = _tryGetDiseaseInfo(key);
      if (result != null) return result;
    }
    
    // Eğer disease'de underscore varsa, boşluk ile de dene
    if (disease.contains('_')) {
      key = '${plantType}___${disease.replaceAll('_', ' ')}';
      result = _tryGetDiseaseInfo(key);
      if (result != null) return result;
    }
    
    return null;
  }
  
  // Switch case'leri ayrı bir fonksiyona taşı
  Map<String, String>? _tryGetDiseaseInfo(String key) {
    switch (key) {
      // ELMA HASTALIKLARI
      case 'apple___apple_scab':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Elma kabuğu (Venturia inaequalis) ciddi bir mantar hastalığıdır. Erken tespit ve düzenli ilaçlama kritiktir. Tomurcuk patlamadan önce koruyucu ilaçlama yapılmalıdır.',
          'water': 'Yaprakları ıslatmadan sabah sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Sabah erken saatlerde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Aşırı nemden kaçının. Düşen yaprakları toplayın ve yakın.',
          'fertilization': 'Dengeli, potasyum ağırlıklı gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırır. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. İlkbahar başında azotlu, yaz başında potasyum-fosforlu gübre uygulayın.',
          'pruning': 'Hastalıklı dalları derhal budayın, havalandırmayı artırın',
          'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri hemen çıkarın ve yakın. Budama aletlerini %10 çamaşır suyu ile sterilize edin. Ağacın iç kısmını açarak hava sirkülasyonunu artırın. Düşen yaprakları toplayın.',
          'repotting': 'Hastalık kontrol altına alındıktan sonra',
          'repottingDetails': 'Hastalık tamamen kontrol altına alındıktan sonra temiz toprak kullanarak değiştirin. Kök çürümesi varsa sağlıklı köklere kadar temizleyin. İlaçlama: Tomurcuk patlamadan önce ve çiçeklenme döneminde uygun fungisitlerle koruyucu ilaçlama yapın.',
        };
      case 'apple___black_rot':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Siyah çürüklük (Botryosphaeria obtusa) elma ağaçlarında ciddi hasara neden olur. Enfekte meyve ve yapraklar derhal temizlenmelidir.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Aşırı nemden kaçının.',
          'fertilization': 'Dengeli, organik gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
          'pruning': 'Enfekte meyve ve yaprakları derhal temizleyin',
          'pruningDetails': 'Enfekte meyve, yaprak ve dalları hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın. Havalandırmayı artırın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalık kontrol altına alındıktan sonra temiz toprak kullanın. İlaçlama: Bakır bazlı fungisitlerle koruyucu ilaçlama yapın.',
        };
      case 'apple___cedar_apple_rust':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Sedir elma pası (Gymnosporangium juniperi-virginianae) sedir ağaçlarından bulaşır. Alternatif konakları (sedir/ardıç) uzaklaştırmak önemlidir.',
          'water': 'Yaprakları ıslatmadan sabah sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Sabah erken saatlerde, yaprakları ıslatmadan toprağa doğrudan sulama yapın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Potasyum içeren gübreler hastalık direncini artırır.',
          'pruning': 'Hastalıklı yaprakları temizleyin, havalandırmayı artırın',
          'pruningDetails': 'Hastalıklı yaprakları toplayın ve yakın. Ağacın iç kısmını açarak hava sirkülasyonunu artırın. Alternatif konakları (sedir/ardıç) 500 metre uzaklığa taşıyın veya kaldırın.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Elma ağaçları genellikle bahçede yetiştirilir. İlaçlama: Fungisit uygulamaları yapın. Alternatif konakları uzaklaştırmak en etkili önlemdir.',
        };
      
      // DOMATES HASTALIKLARI
      case 'tomato___early_blight':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Erken yanıklık (Alternaria solani) domates bitkilerinde yaygın bir hastalıktır. Alt yapraklardan başlar ve yukarı doğru yayılır. Erken tespit ve önleyici ilaçlama önemlidir.',
          'water': 'Yaprakları ıslatmadan damla sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı hızla yayar. Damla sulama sistemi kullanın veya sabah erken saatlerde toprağa doğrudan sulama yapın. Yaprakları asla ıslatmayın. Bitkiler arası mesafeyi koruyun.',
          'fertilization': 'Dengeli, potasyum ağırlıklı gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırır. Potasyum içeren gübreler hastalık direncini artırır. Yarı dozda dengeli gübre kullanın. Organik gübreler tercih edin.',
          'pruning': 'Alt yaprakları düzenli temizleyin',
          'pruningDetails': 'Hastalıklı alt yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Bitkiler arası mesafeyi artırın. Havalandırmayı iyileştirin. Budama aletlerini sterilize edin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Hastalık belirtileri görülmeye başlandığında uygun fungisitlerle (mancozeb, chlorothalonil) önleyici ilaçlama yapın. Dayanıklı çeşitler tercih edin.',
        };
      case 'tomato___late_blight':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Geç yanıklık (Phytophthora infestans) domates bitkilerinde çok ciddi bir hastalıktır. Hızlı yayılır ve tüm bitkiyi öldürebilir. Acil müdahale gereklidir.',
          'water': 'Yaprakları ıslatmadan damla sulama, sabah sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı çok hızlı yayar. Mutlaka damla sulama sistemi kullanın. Sabah erken saatlerde, yaprakları asla ıslatmadan toprağa doğrudan sulama yapın. Serin ve nemli koşullardan koruyun.',
          'fertilization': 'Dengeli, hafif gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırır. Potasyum içeren gübreler hastalık direncini artırır. Yarı dozda dengeli gübre kullanın.',
          'pruning': 'Hastalıklı bitkileri hemen ortamdan çıkarın',
          'pruningDetails': 'Hastalıklı bitkileri derhal ortamdan çıkarın ve yakın. Bu hastalık çok hızlı yayılır. Tüm bitki artıklarını temizleyin. Bitkiler arası mesafeyi artırın. Havalandırmayı iyileştirin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Sistemik fungisitlerle (mefenoxam, dimethomorph) acil müdahale yapın. Dayanıklı çeşitler tercih edin. Serin ve nemli koşullardan koruyun.',
        };
      case 'tomato___bacterial_spot':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Bakteriyel leke (Xanthomonas spp.) domates, şeftali ve biber bitkilerinde yaygındır. Yapraklarda ve meyvelerde siyah lekeler oluşturur. Bakteriyel hastalık olduğu için fungisitler etkisizdir.',
          'water': 'Yaprakları ıslatmadan damla sulama',
          'waterDetails': 'Yaprak ıslanması bakteriyi yayar. Mutlaka damla sulama sistemi kullanın veya sabah erken saatlerde toprağa doğrudan sulama yapın. Yaprakları asla ıslatmayın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Dengeli bir gübre programı uygulayın. Organik gübreler tercih edin.',
          'pruning': 'Hastalıklı bitki kısımlarını budayın',
          'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri derhal çıkarın ve yakın. Budama aletlerini sterilize edin. Bitkiler arası mesafeyi artırın. Havalandırmayı iyileştirin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Bakırlı bakterisitlerle önleyici ilaçlama yapın. Temiz tohum ve sağlıklı fide kullanın. Alet ve ekipmanları dezenfekte edin.',
        };
      case 'tomato___septoria_leaf_spot':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Septoria yaprak lekesi (Septoria lycopersici) domates bitkilerinde yaygın bir hastalıktır. Alt yapraklarda küçük kahverengi lekeler ve delikler oluşturur.',
          'water': 'Yaprakları ıslatmadan damla sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Damla sulama sistemi kullanın veya sabah erken saatlerde toprağa doğrudan sulama yapın. Yaprakları asla ıslatmayın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Potasyum içeren gübreler hastalık direncini artırır.',
          'pruning': 'Alt yaprakları düzenli temizleyin',
          'pruningDetails': 'Hastalıklı alt yaprakları düzenli olarak çıkarın ve yakın. Bu hastalığın yayılmasını önler. Bitkiler arası mesafeyi artırın. Havalandırmayı iyileştirin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Fungisit uygulamaları (chlorothalonil, mancozeb) yapın. Alt yaprakları düzenli temizlemek çok önemlidir.',
        };
      case 'tomato___leaf_mold':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Yaprak küfü (Passalora fulva) domates bitkilerinde nemli koşullarda görülen bir hastalıktır. Yaprakların alt yüzeyinde yeşil-sarı küf oluşturur.',
          'water': 'Yaprakları ıslatmadan damla sulama',
          'waterDetails': 'Yaprak ıslanması ve yüksek nem hastalığı yayar. Mutlaka damla sulama sistemi kullanın. Sabah erken saatlerde, yaprakları asla ıslatmadan toprağa doğrudan sulama yapın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Aşırı azot hastalık şiddetini artırabilir.',
          'pruning': 'Havalandırmayı artırın, alt yaprakları temizleyin',
          'pruningDetails': 'Hastalıklı yaprakları çıkarın. Bitkiler arası mesafeyi artırın. Havalandırmayı iyileştirin. Nem oranını düşürün.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Fungisit uygulamaları yapın. Nem oranını düşürmek ve havalandırmayı artırmak çok önemlidir.',
        };
      case 'tomato___tomato_mosaic_virus':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Domates mozaik virüsü (Tobacco mosaic virus) viral bir hastalıktır. Yapraklarda mozaik desenleri ve büyüme geriliğine neden olur. Tedavisi yoktur, önleme kritiktir.',
          'water': 'Normal sulama',
          'waterDetails': 'Sulama normal şekilde yapılabilir ancak yaprakları ıslatmamaya özen gösterin.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Bitkinin genel sağlığını korumak önemlidir.',
          'pruning': 'Enfekte bitkileri hemen uzaklaştırın',
          'pruningDetails': 'Enfekte bitkileri derhal ortamdan çıkarın ve yakın. Bu virüs mekanik yollarla (eller, aletler) bulaşır. Alet ve ekipmanları düzenli dezenfekte edin. Böceklerle mücadele edin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Enfekte bitkileri temiz toprak ve sterilize edilmiş saksılara alın. Önleme: Sağlıklı ve sertifikalı tohum ve fideler kullanın. Alet ve ekipmanları dezenfekte edin. Böceklerle mücadele edin. Tedavisi yoktur, önleme tek çözümdür.',
        };
      case 'tomato___tomato_yellow_leaf_curl_virus':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Domates sarı yaprak kıvırcık virüsü (TYLCV) ciddi bir viral hastalıktır. Yaprakların sararması ve kıvrılmasına neden olur. Beyaz sineklerle taşınır. Tedavisi yoktur.',
          'water': 'Normal sulama',
          'waterDetails': 'Sulama normal şekilde yapılabilir ancak yaprakları ıslatmamaya özen gösterin.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Bitkinin genel sağlığını korumak önemlidir.',
          'pruning': 'Enfekte bitkileri hemen uzaklaştırın',
          'pruningDetails': 'Enfekte bitkileri derhal ortamdan çıkarın ve yakın. Bu virüs beyaz sineklerle taşınır. Beyaz sineklerle mücadele edin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Enfekte bitkileri temiz toprak ve sterilize edilmiş saksılara alın. Önleme: Sağlıklı ve sertifikalı tohum ve fideler kullanın. Beyaz sineklerle mücadele edin (sarı yapışkan tuzaklar, insektisitler). Tedavisi yoktur, önleme tek çözümdür.',
        };
      case 'tomato___target_spot':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Hedef leke (Corynespora cassiicola) domates bitkilerinde yapraklarda hedef tahtası benzeri lekeler oluşturur.',
          'water': 'Yaprakları ıslatmadan damla sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Damla sulama sistemi kullanın veya sabah erken saatlerde toprağa doğrudan sulama yapın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın.',
          'pruning': 'Hastalıklı yaprakları toplayın ve imha edin',
          'pruningDetails': 'Hastalıklı yaprakları toplayın ve yakın. Havalandırmayı artırın. Bitkiler arası mesafeyi artırın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Uygun fungisitlerle kültürel önlemler alın.',
        };
      case 'tomato___spider_mites':
      case 'tomato___two-spotted_spider_mite':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'İki noktalı kırmızı örümcek (Tetranychus urticae) domates bitkilerinde yapraklarda sararma ve kurumaya neden olan bir zararlıdır. Böcek değil, akar türüdür.',
          'water': 'Yaprakları düzenli su ile yıkayın',
          'waterDetails': 'Yaprakları düzenli olarak su ile yıkayın. Bu zararlıyı uzaklaştırır. Nem oranını artırın. Damla sulama sistemi kullanın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Aşırı azot zararlı popülasyonunu artırabilir.',
          'pruning': 'Hastalıklı yaprakları temizleyin',
          'pruningDetails': 'Hastalıklı yaprakları çıkarın. Havalandırmayı artırın. Bitkiler arası mesafeyi artırın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Akarisit uygulamaları yapın. Biyolojik kontrol yöntemleri (predatör akarlar) kullanın. Nem oranını artırmak çok önemlidir.',
        };
      
      // ÜZÜM HASTALIKLARI
      case 'grape___black_rot':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Siyah çürüklük (Guignardia bidwellii) üzüm asmalarında ciddi bir hastalıktır. Enfekte meyve ve yapraklar derhal temizlenmelidir.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Drip sulama veya toprağa doğrudan sulama yapın. Aşırı nemden kaçının.',
          'fertilization': 'Dengeli, organik gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
          'pruning': 'Enfekte meyve ve yaprakları derhal temizleyin',
          'pruningDetails': 'Enfekte meyve, yaprak ve salkımları hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın. Havalandırmayı artırmak için yaprakları seyreltin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalık kontrol altına alındıktan sonra temiz toprak ve sterilize edilmiş saksı kullanın. İlaçlama: Bakır bazlı fungisitlerle koruyucu ilaçlama yapın.',
        };
      case 'grape___esca_(black_measles)':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Esca (Siyah Kızamık) üzüm asmalarında ciddi bir hastalıktır. Yapraklarda siyah noktalar ve çürüme ile karakterizedir. Sağlıklı fidan kullanmak önemlidir.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Drip sulama veya toprağa doğrudan sulama yapın. Aşırı sulamadan kaçının.',
          'fertilization': 'Dengeli, organik gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Organik gübreler tercih edin.',
          'pruning': 'Dikkatli budama yapın, yaraları kapatın',
          'pruningDetails': 'Hastalıklı yaprak, dal ve salkımları hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını mutlaka koruyucu ile kapatın. Dikkatli budama yapın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalık kontrol altına alındıktan sonra temiz toprak ve sterilize edilmiş saksı kullanın. Önleme: Sağlıklı fidan kullanın. Budama yaralarını mutlaka kapatın.',
        };
      case 'grape___leaf_blight_(isariopsis_leaf_spot)':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Isariopsis yaprak yanıklığı üzüm bitkilerinde yapraklarda kahverengi lekeler ve yanıklık oluşturur.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Drip sulama veya toprağa doğrudan sulama yapın.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın.',
          'pruning': 'Kahverengi lekeli yaprakları temizleyin',
          'pruningDetails': 'Kahverengi lekeli yaprakları çıkarın ve yakın. Havalandırmayı artırmak için yaprakları seyreltin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Fungisit uygulamaları yapın.',
        };
      
      // MISIR HASTALIKLARI
      case 'corn___common_rust':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Yaygın pas (Puccinia sorghi) mısır bitkilerinde yapraklarda turuncu-kırmızı pas benzeri yapılar oluşturan mantar hastalığıdır.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Drip sulama veya toprağa doğrudan sulama yapın. Sabah saatlerinde sulayın. Aşırı nemden kaçının.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Dengeli bir gübre programı uygulayın. Potasyum içeren gübreler hastalık direncini artırır. Azotlu gübreyi dengeli kullanın.',
          'pruning': 'Hastalıklı yaprakları temizleyin',
          'pruningDetails': 'Hastalıklı yaprakları çıkarın ve yakın. Hasat sonrası tüm bitki artıklarını temizleyin ve yakın.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Mısır genellikle sezonsal olarak yetiştirilir. İlaçlama: Fungisit uygulamaları (propiconazole, azoxystrobin) yapın. Dayanıklı çeşitler seçin. Kültürel önlemler alın. Ekim nöbeti uygulayın.',
        };
      case 'corn___northern_leaf_blight':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Kuzey yaprak yanıklığı (Exserohilum turcicum) mısır bitkilerinde yapraklarda uzun, elips şeklinde kahverengi lekeler oluşturan ciddi bir mantar hastalığıdır.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Drip sulama veya toprağa doğrudan sulama yapın. Sabah saatlerinde sulayın. Aşırı nemden kaçının.',
          'fertilization': 'Dengeli, potasyum ağırlıklı gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın. Azotlu gübreyi yarı dozda kullanın.',
          'pruning': 'Hastalıklı yaprakları temizleyin',
          'pruningDetails': 'Hastalıklı yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin ve yakın.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Mısır genellikle sezonsal olarak yetiştirilir. İlaçlama: Uygun fungisitlerle (propiconazole, azoxystrobin) önleyici ilaçlama yapın. Dayanıklı çeşitler seçin. Ekim nöbeti uygulayın.',
        };
      
      // KİRAZ HASTALIKLARI
      case 'cherry___powdery_mildew':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Külleme (Podosphaera clandestina) kiraz ağaçlarında yapraklarda beyaz toz benzeri bir tabaka oluşturan mantar hastalığıdır.',
          'water': 'Yaprakları ıslatmadan sabah sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Sabah erken saatlerde, yaprakları ıslatmadan toprağa doğrudan sulama yapın.',
          'fertilization': 'Dengeli, hafif gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
          'pruning': 'Hastalıklı yaprakları temizleyin, havalandırmayı artırın',
          'pruningDetails': 'Hastalıklı yaprakları çıkarın ve yakın. Ağacın iç kısmını açarak hava sirkülasyonunu artırın. Bitkiler arası mesafeyi artırın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalık kontrol altına alındıktan sonra temiz toprak kullanın. İlaçlama: Kükürtlü fungisitler kullanın. Hava sirkülasyonunu artırmak çok önemlidir.',
        };
      
      // ŞEFTALİ HASTALIKLARI
      case 'peach___bacterial_spot':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Bakteriyel leke (Xanthomonas arboricola pv. pruni) şeftali ağaçlarında yapraklarda ve meyvelerde siyah lekeler oluşturan bakteriyel hastalıktır.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması bakteriyi yayar. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Aşırı nemden kaçının.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
          'pruning': 'Hastalıklı dalları derhal budayın',
          'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalık kontrol altına alındıktan sonra temiz toprak kullanın. İlaçlama: Bakırlı bakterisitlerle önleyici ilaçlama yapın. Temiz tohum ve sağlıklı fide kullanın.',
        };
      
      // BİBER HASTALIKLARI
      case 'pepper___bacterial_spot':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Bakteriyel leke (Xanthomonas spp.) biber bitkilerinde yapraklarda ve meyvelerde siyah lekeler oluşturan bakteriyel hastalıktır.',
          'water': 'Yaprakları ıslatmadan damla sulama',
          'waterDetails': 'Yaprak ıslanması bakteriyi yayar. Mutlaka damla sulama sistemi kullanın veya sabah erken saatlerde toprağa doğrudan sulama yapın. Yaprakları asla ıslatmayın.',
          'fertilization': 'Hafif, dengeli gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Yarı dozda gübre kullanın.',
          'pruning': 'Hastalıklı yaprakları hemen çıkarın',
          'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri derhal çıkarın ve yakın. Budama aletlerini sterilize edin. Havalandırmayı artırmak için alt yaprakları temizleyin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Bakırlı bakterisitlerle önleyici ilaçlama yapın. Temiz tohum ve sağlıklı fide kullanın.',
        };
      
      // PATATES HASTALIKLARI
      case 'potato___early_blight':
        return {
          'difficulty': 'Orta-Zor',
          'difficultyDetails': 'Erken yanıklık (Alternaria solani) patates bitkilerinde yapraklarda halka şeklinde kahverengi lekeler oluşturan yaygın bir hastalıktır.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması geç yanıklık ve erken yanıklık gibi hastalıkları yayar. Drip sulama veya toprağa doğrudan sulama yapın. Sabah saatlerinde sulayın.',
          'fertilization': 'Dengeli, hafif gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın.',
          'pruning': 'Hastalıklı yaprakları temizleyin',
          'pruningDetails': 'Hastalıklı yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Patates sezonsal olarak yetiştirilir. İlaçlama: Uygun fungisitlerle (mancozeb, chlorothalonil) önleyici ilaçlama yapın. Dayanıklı çeşitler tercih edin.',
        };
      case 'potato___late_blight':
        return {
          'difficulty': 'Zor',
          'difficultyDetails': 'Geç yanıklık (Phytophthora infestans) patates bitkilerinde yapraklarda ve yumrularda hızlı çürümeye neden olan çok ciddi bir hastalıktır. Acil müdahale gereklidir.',
          'water': 'Yaprakları ıslatmadan damla sulama, sabah sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı çok hızlı yayar. Mutlaka damla sulama sistemi kullanın. Sabah erken saatlerde, yaprakları asla ıslatmadan toprağa doğrudan sulama yapın. Serin ve nemli koşullardan koruyun.',
          'fertilization': 'Dengeli, hafif gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın.',
          'pruning': 'Hastalıklı bitkileri hemen ortamdan çıkarın',
          'pruningDetails': 'Hastalıklı bitkileri derhal ortamdan çıkarın ve yakın. Bu hastalık çok hızlı yayılır. Tüm bitki artıklarını temizleyin. Hasat sonrası tüm bitki artıklarını temizleyin.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Patates sezonsal olarak yetiştirilir. İlaçlama: Sistemik fungisitlerle (mefenoxam, dimethomorph) acil müdahale yapın. Dayanıklı çeşitler tercih edin. Serin ve nemli koşullardan koruyun.',
        };
      
      // ÇİLEK HASTALIKLARI
      case 'strawberry___leaf_scorch':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Yaprak yanması çilek bitkilerinde yaprak kenarlarında kuruma ve kahverengileşme ile karakterize bir hastalıktır.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması yaprak yanması gibi hastalıkları yayar. Drip sulama veya toprağa doğrudan sulama yapın. Aşırı nemden kaçının, kök çürümesine neden olabilir.',
          'fertilization': 'Dengeli, hafif gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
          'pruning': 'Hastalıklı yaprakları derhal çıkarın',
          'pruningDetails': 'Hastalıklı yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. İlaçlama: Su yönetimini düzenleyin. Dayanıklı çeşitler seçin. Güneş ışığına maruziyeti kontrol edin.',
        };
      
      // TURUNÇGİL HASTALIKLARI
      case 'citrus___haunglongbing_(citrus_greening)':
        return {
          'difficulty': 'Çok Zor',
          'difficultyDetails': 'Turunçgil yeşillenmesi (Huanglongbing) portakal ağaçlarında yaprakların sararması ve meyvelerin küçük kalmasına neden olan çok ciddi bir hastalıktır. Asya turunçgil psillidi ile taşınır. Tedavisi yoktur.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalıkları yayar. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Kök çürümesinden kaçının.',
          'fertilization': 'Dengeli, mikro besin içeren gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Demir, çinko gibi mikro besinler önemlidir. Turunçgil için özel formüle edilmiş gübreler kullanın.',
          'pruning': 'Hastalıklı dalları derhal budayın',
          'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın.',
          'repotting': 'Hastalık kontrolü sonrası',
          'repottingDetails': 'Hastalıklı ağaçları sökün. Önleme: Asya turunçgil psillidi mücadelesi yapın. Sağlıklı fidan kullanın. Tedavisi yoktur, önleme tek çözümdür.',
        };
      
     
      
      
      
      
      
      // MISIR HASTALIKLARI - Cercospora ve Gray Leaf Spot (birleşik ve ayrı formatlar)
      case 'corn___cercospora_leaf_spot gray_leaf_spot':
      case 'corn___cercospora_leaf_spot_gray_leaf_spot':
      case 'corn___cercospora_leaf_spot':
      case 'corn___gray_leaf_spot':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Cercospora ve gri yaprak lekesi mısır bitkilerinde yapraklarda gri-kahverengi lekeler oluşturan mantar hastalıklarıdır. Cercospora zeae-maydis etmeni tarafından oluşturulur. Alt yapraklardan başlayarak yukarı doğru yayılır.',
          'water': 'Yaprakları ıslatmadan toprağa sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Drip sulama veya toprağa doğrudan sulama yapın. Sabah saatlerinde sulayın. Aşırı nemden kaçının. Gece sulamasından kaçının.',
          'fertilization': 'Dengeli, hafif gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın. Azotlu gübreyi yarı dozda kullanın. Fosfor ve potasyum ağırlıklı gübreler tercih edin.',
          'pruning': 'Hastalıklı yaprakları temizleyin',
          'pruningDetails': 'Hastalıklı alt yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin ve yakın. Bitki artıklarını toprağa gömmeyin.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Mısır genellikle sezonsal olarak yetiştirilir. İlaçlama: Uygun fungisitlerle (azoxystrobin, propiconazole, tebuconazole) önleyici ilaçlama yapın. İlk belirtiler görüldüğünde başlayın. Dayanıklı çeşitler seçin. Ekim nöbeti uygulayın (mısır-mısır yerine dönüşümlü ekim).',
        };
      
      // KABAK HASTALIKLARI
      case 'squash___powdery_mildew':
        return {
          'difficulty': 'Orta',
          'difficultyDetails': 'Külleme (Podosphaera xanthii) kabak bitkilerinde yapraklarda ve meyvelerde beyaz toz benzeri bir tabaka oluşturan mantar hastalığıdır.',
          'water': 'Yaprakları ıslatmadan sabah sulama',
          'waterDetails': 'Yaprak ıslanması hastalığı yayar. Sabah erken saatlerde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Drip sulama sistemi kullanın. Aşırı nemden kaçının.',
          'fertilization': 'Dengeli gübreleme',
          'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın. Organik gübreler tercih edin.',
          'pruning': 'Hastalıklı yaprakları temizleyin, havalandırmayı artırın',
          'pruningDetails': 'Hastalıklı yaprakları çıkarın ve yakın. Bitkiler arası mesafeyi artırın. Havalandırmayı iyileştirin. Alt yaprakları düzenli temizleyin.',
          'repotting': 'Genellikle gerekli değil',
          'repottingDetails': 'Kabak genellikle bahçede yetiştirilir. İlaçlama: Kükürtlü fungisitler kullanın. Hava sirkülasyonunu artırmak çok önemlidir. Dayanıklı çeşitler seçin.',
        };
      
      default:
        return null; // Hastalığa özel bakım bilgisi yoksa null döndür
    }
  }

  Widget _buildCareDetailCard({
    required IconData icon,
    required String label,
    required String value,
    required String details,
  }) {
    return GestureDetector(
      onTap: () => _showCareDetailDialog(context, label, value, details),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showCareDetailDialog(BuildContext context, String label, String value, String details) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              details,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Tamam',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showNicknameDialog(BuildContext context, {String? errorMessage}) async {
    final TextEditingController controller = TextEditingController();
    String? error = errorMessage;
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Bitkinizi İsimlendirin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error!,
                              style: TextStyle(color: AppColors.warning, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Bitki adı girin',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (error != null) {
                        setState(() {
                          error = null;
                        });
                      }
                    },
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        Navigator.of(dialogContext).pop(value.trim());
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (controller.text.trim().isNotEmpty) {
                      Navigator.of(dialogContext).pop(controller.text.trim());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _savePlantToMyPlants(BuildContext context) async {
    if (_analysisResult == null) return;
    
    // Önce nickname al (döngü ile kontrol yapılacak)
    String? nickname;
    String? errorMessage;
    
    while (true) {
      nickname = await _showNicknameDialog(context, errorMessage: errorMessage);
      if (nickname == null || nickname.trim().isEmpty) {
        return; // Kullanıcı iptal etti veya boş bıraktı
      }
      
      // Aynı nickname kontrolü
      final prefs = await SharedPreferences.getInstance();
      final savedPlantsJson = prefs.getString('saved_plants') ?? '[]';
      final savedPlants = List<Map<String, dynamic>>.from(
        jsonDecode(savedPlantsJson) as List
      );
      
      final nicknameExists = savedPlants.any((plant) => 
        (plant['name'] as String?)?.trim().toLowerCase() == nickname!.trim().toLowerCase()
      );
      
      if (nicknameExists) {
        // Hata mesajı ile dialog'u tekrar aç
        errorMessage = 'Bu zaten bahçenizde var!';
        continue; // Dialog'u tekrar aç
      } else {
        // Nickname geçerli, döngüden çık
        break;
      }
    }
    
    try {
      // Bitki bilgilerini hazırla
      final result = Map<String, dynamic>.from(_analysisResult!);
      
      // Bitki türü ve sağlık durumunu belirle (aynı mantık _buildAnalysisResultCard ile)
      final analysis = result['analysis'] != null
          ? Map<String, dynamic>.from(result['analysis'] as Map)
          : null;
      final alternatives = (analysis?['alternatives'] as List?)
              ?.map((item) => Map<String, dynamic>.from(item as Map))
              .toList() ??
          [];
      
      String? plantType;
      bool isHealthy = false;
      String? rawClassName;
      
      if (alternatives.isNotEmpty) {
        rawClassName = alternatives.first['class_name']?.toString();
        if (rawClassName != null && rawClassName.contains('___')) {
          final parts = rawClassName.split('___');
          var rawPlantType = parts[0];
          
          // Plant type'ı normalize et: "Corn_(maize)" -> "Corn", "Pepper,_bell" -> "Pepper"
          rawPlantType = _normalizePlantType(rawPlantType);
          
          final rawDiseaseOrStatus = parts.length > 1 ? parts[1] : '';
          var normalizedDisease = rawDiseaseOrStatus.replaceAll(RegExp(r'_+$'), '').trim();
          plantType = _plantTypeTranslations[rawPlantType] ?? rawPlantType;
          isHealthy = normalizedDisease.toLowerCase() == 'healthy';
        }
      }
      
      if (plantType == null) {
        final rawDisease = result['disease']?.toString() ?? '';
        rawClassName ??= rawDisease;
        if (rawDisease.contains('___')) {
          final parts = rawDisease.split('___');
          var rawPlantType = parts[0];
          
          // Plant type'ı normalize et: "Corn_(maize)" -> "Corn", "Pepper,_bell" -> "Pepper"
          rawPlantType = _normalizePlantType(rawPlantType);
          
          final rawDiseaseOrStatus = parts.length > 1 ? parts[1] : '';
          var normalizedDisease = rawDiseaseOrStatus.replaceAll(RegExp(r'_+$'), '').trim();
          plantType = _plantTypeTranslations[rawPlantType] ?? rawPlantType;
          isHealthy = normalizedDisease.toLowerCase() == 'healthy';
        }
      }
      
      // Bitki ismini ve hastalık bilgisini ayrı ayrı hazırla
      final turkishPlantType = plantType ?? 'Bilinmeyen Bitki';
      String? turkishDisease;
      
      if (!isHealthy && rawClassName != null && rawClassName.contains('___')) {
        final parts = rawClassName.split('___');
        if (parts.length >= 2) {
          var diseaseKey = parts[1];
          diseaseKey = diseaseKey.replaceAll(RegExp(r'_+$'), '').trim();
          
          // Hastalık Türkçe çevirisini bul
          turkishDisease = _plantVillageDiseaseTranslations[diseaseKey] ?? '';
          if (turkishDisease.isEmpty && diseaseKey.contains(' ')) {
            turkishDisease = _plantVillageDiseaseTranslations[diseaseKey] ?? '';
          }
          if (turkishDisease.isEmpty) {
            final spacedKey = diseaseKey.replaceAll('_', ' ');
            turkishDisease = _plantVillageDiseaseTranslations[spacedKey] ?? '';
          }
          if (turkishDisease.isEmpty) {
            turkishDisease = _prettifyClassName(diseaseKey);
          }
        }
      }
      
      // Bitki verisini hazırla (nickname kullanıcıdan alınan isim)
      final plantData = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': nickname.trim(), // Kullanıcının verdiği nickname
        'plantType': plantType ?? 'Unknown',
        'originalPlantType': turkishPlantType, // Orijinal bitki türü (gösterim için)
        'isHealthy': isHealthy,
        'disease': turkishDisease ?? '', // Hastalık ayrı
        'confidenceScore': result['confidence_score'],
        'healthScore': result['health_score'],
        'healthLabel': result['health_label'],
        'savedAt': DateTime.now().toIso8601String(),
        'imagePath': _selectedImageFile?.path, // Sadece path kaydediyoruz
      };
      
      // SharedPreferences'a kaydet
      final prefs = await SharedPreferences.getInstance();
      final savedPlantsJson = prefs.getString('saved_plants') ?? '[]';
      final savedPlants = List<Map<String, dynamic>>.from(
        jsonDecode(savedPlantsJson) as List
      );
      
      savedPlants.add(plantData);
      await prefs.setString('saved_plants', jsonEncode(savedPlants));
        
        // İlk analiz sonucunu history'ye kaydet
        final plantId = plantData['id'] as String;
        final initialAnalysisEntry = {
          'id': 'initial_$plantId',
          'imagePath': _selectedImageFile?.path,
          'analysisResult': result, // Tam analiz sonucu
          'date': plantData['savedAt'] as String,
        };
        
        final historyJson = prefs.getString('plant_analysis_history_$plantId') ?? '[]';
        final history = List<Map<String, dynamic>>.from(
          jsonDecode(historyJson) as List
        );
        
      // İlk entry yoksa ekle
      if (history.isEmpty || !history.any((entry) => entry['id'] == initialAnalysisEntry['id'])) {
        history.insert(0, initialAnalysisEntry);
        await prefs.setString('plant_analysis_history_$plantId', jsonEncode(history));
      }
      
      if (context.mounted) {
        // Modal'ı kapat
        Navigator.of(context).pop();
        // Kısa bir gecikme sonrası SnackBar'ı göster (modal kapanma animasyonu için)
        await Future.delayed(const Duration(milliseconds: 300));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Bitki başarıyla kaydedildi!'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        // Modal'ı kapat
        Navigator.of(context).pop();
        // Kısa bir gecikme sonrası SnackBar'ı göster
        await Future.delayed(const Duration(milliseconds: 300));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Kayıt hatası: $e'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  // Varsayılan bakım bilgileri
  Map<String, String> _defaultCareInfo(bool isHealthy) {
    if (isHealthy) {
      return {
        'difficulty': 'Orta',
        'difficultyDetails': 'Bu bitki için orta seviye bakım bilgisi gereklidir. Düzenli sulama ve gübreleme ile sağlıklı kalır.',
        'water': 'Haftada 2-3 kez',
        'waterDetails': 'Toprak üst yüzeyi kurumaya başladığında sulama yapın. Aşırı sulamadan kaçının, kök çürümesine neden olabilir.',
        'fertilization': 'Büyüme mevsiminde ayda bir',
        'fertilizationDetails': 'Büyüme mevsiminde (ilkbahar-yaz) dengeli bir gübre ile ayda bir gübreleme yapın. Kış aylarında gübrelemeyi azaltın.',
        'pruning': 'Gerektiğinde',
        'pruningDetails': 'Ölü, hastalıklı veya zayıf dalları düzenli olarak budayın. Şekil vermek için büyüme mevsiminde budama yapabilirsiniz.',
        'repotting': '2 yılda bir',
        'repottingDetails': 'Kökler saksıyı doldurduğunda veya toprak kalitesi düştüğünde daha büyük bir saksıya alın. İlkbahar mevsimi uygun zamandır.',
      };
    } else {
      return {
        'difficulty': 'Zor',
        'difficultyDetails': 'Hastalıklı bitki için daha dikkatli ve özenli bakım gereklidir. Erken müdahale önemlidir.',
        'water': 'Dikkatli sulama - toprak kurudukça',
        'waterDetails': 'Hastalıklı bitkilerde aşırı nem hastalığı yayabilir. Toprak tamamen kuruduktan sonra sulayın. Yaprakları ıslatmaktan kaçının.',
        'fertilization': 'Hafif gübreleme - ayda bir',
        'fertilizationDetails': 'Hastalıklı bitkiler için gübreyi yarı dozda kullanın. Aşırı azot hastalığı şiddetlendirebilir. Potasyum ve fosfor içeren gübreler tercih edin.',
        'pruning': 'Hastalıklı kısımları derhal budayın',
        'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri hemen çıkarın. Budama aletlerini sterilize edin. Budama yaralarına koruyucu uygulayın.',
        'repotting': 'Hastalık kontrolü sonrası',
        'repottingDetails': 'Hastalık tamamen kontrol altına alındıktan sonra temiz toprak ve sterilize edilmiş saksı ile değiştirin. Kökleri kontrol edin.',
      };
    }
  }

  // Elma - Sağlıklı
  Map<String, String> _appleCareInfoHealthy() {
    return {
      'difficulty': 'Kolay',
      'difficultyDetails': 'Elma ağaçları dayanıklı bitkilerdir ve bakımı nispeten kolaydır. Uygun toprak ve iklim koşullarında iyi gelişir.',
      'water': 'Haftada 2-3 kez derin sulama',
      'waterDetails': 'Elma ağaçları derin köklüdür, bu yüzden derin sulama önemlidir. Yaz aylarında toprak nemini koruyun. Genç ağaçlar daha sık sulama gerektirir.',
      'fertilization': 'İlkbahar ve yaz başında',
      'fertilizationDetails': 'İlkbaharda azotlu gübre, meyve oluşumunda potasyum-fosforlu gübre uygulayın. Organik gübreler (kompost, gübre) elma ağaçları için idealdir.',
      'pruning': 'Kış sonu-İlkbahar başı',
      'pruningDetails': 'Dormant dönemde (kış sonu) ana budama yapılır. Ölü, hastalıklı ve çapraz dalları çıkarın. Ağacın şeklini koruyun ve hava sirkülasyonunu sağlayın.',
      'repotting': 'Saksıda yetiştiriyorsanız 2-3 yılda bir',
      'repottingDetails': 'Elma ağaçları genellikle bahçede yetiştirilir. Saksıda yetiştiriyorsanız kökler saksıyı doldurduğunda daha büyük saksıya alın. Drenaj çok önemlidir.',
    };
  }

  // Elma - Hasta
  Map<String, String> _appleCareInfoSick() {
    return {
      'difficulty': 'Zor',
      'difficultyDetails': 'Hastalıklı elma ağaçları için özel bakım gereklidir. Erken tespit ve müdahale çok önemlidir.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması mantar hastalıklarını yayabilir. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Aşırı nemden kaçının.',
      'fertilization': 'Dengeli, hafif gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalığı şiddetlendirebilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
      'pruning': 'Hastalıklı dalları hemen budayın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri derhal çıkarın. Budama aletlerini %10 çamaşır suyu ile sterilize edin. Budama yaralarını koruyucu ile kapatın.',
      'repotting': 'Hastalık kontrol altına alındıktan sonra',
      'repottingDetails': 'Hastalık tamamen kontrol altına alındıktan sonra temiz toprak kullanarak değiştirin. Kök çürümesi varsa sağlıklı köklere kadar temizleyin.',
    };
  }

  // Domates - Sağlıklı
  Map<String, String> _tomatoCareInfoHealthy() {
    return {
      'difficulty': 'Kolay-Orta',
      'difficultyDetails': 'Domates bitkileri bakımı nispeten kolaydır ancak düzenli sulama ve gübreleme gerektirir. Uygun destek sistemi önemlidir.',
      'water': 'Haftada 3-4 kez düzenli sulama',
      'waterDetails': 'Domates bitkileri düzenli ve derin sulama sever. Toprak nemini koruyun ancak aşırı sulamadan kaçının. Sabah saatlerinde sulama yapın, yaprakları ıslatmadan.',
      'fertilization': 'Büyüme boyunca 2 haftada bir',
      'fertilizationDetails': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanın. Çiçeklenme ve meyve oluşumunda potasyum önemlidir. Organik gübreler (kompost) idealdir.',
      'pruning': 'Alt yaprakları ve yan dalları budayın',
      'pruningDetails': 'Alt kısımdaki sararmış yaprakları çıkarın. Yan dalları (suckers) düzenli olarak budayarak ana gövdeyi güçlendirin. Havalandırmayı artırır.',
      'repotting': 'Tohumdan yetiştiriyorsanız fide aşamasında',
      'repottingDetails': 'Domates fidelerini tohum çimlendirme sonrası daha büyük saksılara alın. Köklerin rahatça gelişebileceği derin saksılar tercih edin.',
    };
  }

  // Domates - Hasta
  Map<String, String> _tomatoCareInfoSick() {
    return {
      'difficulty': 'Zor',
      'difficultyDetails': 'Hastalıklı domates bitkileri için özel bakım ve erken müdahale kritiktir. Hastalık türüne göre tedavi uygulanmalıdır.',
      'water': 'Yaprakları ıslatmadan sabah sulama',
      'waterDetails': 'Yaprak ıslanması mantar hastalıklarını (geç yanıklık, erken yanıklık) yayar. Drip sulama sistemi kullanın veya toprağa doğrudan sulayın. Aşırı nemden kaçının.',
      'fertilization': 'Hafif, dengeli gübreleme',
      'fertilizationDetails': 'Aşırı azot yaprak hastalıklarını şiddetlendirir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Yarı dozda gübre kullanın.',
      'pruning': 'Hastalıklı yaprakları hemen çıkarın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri derhal çıkarın ve yakın. Budama aletlerini sterilize edin. Havalandırmayı artırmak için alt yaprakları temizleyin.',
      'repotting': 'Hastalık kontrolü sonrası yeniden dikim',
      'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. Kök sistemini kontrol edin, çürümüş kökleri temizleyin. Drenajı iyileştirin.',
    };
  }

  // Mısır - Sağlıklı
  Map<String, String> _cornCareInfoHealthy() {
    return {
      'difficulty': 'Kolay',
      'difficultyDetails': 'Mısır bitkileri bakımı kolaydır ancak yeterli alan ve güneş ışığı gerektirir. Bol su ve gübre sever.',
      'water': 'Haftada 2-3 kez derin sulama',
      'waterDetails': 'Mısır derin köklüdür ve düzenli su gerektirir. Özellikle çiçeklenme ve koçan oluşum döneminde su eksikliği olmamalıdır. Toprak nemini koruyun.',
      'fertilization': 'Dikimde ve çiçeklenme öncesi',
      'fertilizationDetails': 'Azotlu gübre mısır için kritiktir. Dikim sırasında ve bitki 30-45 cm olduğunda gübreleme yapın. Kompost ve organik gübreler idealdir.',
      'pruning': 'Gereksiz',
      'pruningDetails': 'Mısır bitkileri budama gerektirmez. Sadece hasat sonrası kuru yaprakları temizleyebilirsiniz.',
      'repotting': 'Saksıda yetiştiriyorsanız geniş saksı gerekli',
      'repottingDetails': 'Mısır genellikle bahçede yetiştirilir. Saksıda yetiştiriyorsanız en az 40 cm derinlik ve genişlik gereklidir. Kökler derin gelişir.',
    };
  }

  // Mısır - Hasta
  Map<String, String> _cornCareInfoSick() {
    return {
      'difficulty': 'Orta-Zor',
      'difficultyDetails': 'Hastalıklı mısır bitkileri için dikkatli bakım gerekir. Özellikle yaprak hastalıklarına karşı önlem alınmalıdır.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması pas ve yaprak lekesi hastalıklarını yayar. Drip sulama veya toprağa doğrudan sulama yapın. Sabah saatlerinde sulayın.',
      'fertilization': 'Dengeli, hafif gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın.',
      'pruning': 'Hastalıklı yaprakları temizleyin',
      'pruningDetails': 'Hastalıklı alt yaprakları çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin.',
      'repotting': 'Genellikle gerekli değil',
      'repottingDetails': 'Mısır genellikle sezonsal olarak yetiştirilir. Eğer saksıda yetiştiriyorsanız ve hastalık varsa, toprağı değiştirin ve sterilize edin.',
    };
  }

  // Üzüm - Sağlıklı
  Map<String, String> _grapeCareInfoHealthy() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Üzüm asmaları bakımı orta seviyededir. Düzenli budama ve destek sistemi önemlidir.',
      'water': 'Haftada 1-2 kez derin sulama',
      'waterDetails': 'Üzüm asmaları kuraklığa dayanıklıdır ancak meyve oluşum döneminde düzenli su gerektirir. Toprağın iyi drene olması önemlidir. Genç asmalar daha sık sulama gerektirir.',
      'fertilization': 'İlkbahar başında bir kez',
      'fertilizationDetails': 'İlkbaharda azotlu gübre uygulayın. Meyve oluşumunda potasyum önemlidir. Organik gübreler (kompost, gübre) üzüm asmaları için idealdir.',
      'pruning': 'Kış sonu budama, yaz boyunca sürgün kontrolü',
      'pruningDetails': 'Kış sonu (dormant dönem) ana budama zamanıdır. Yeni sürgünleri kontrol edin, gereksiz dalları çıkarın. Havalandırma için yaprakları seyreltin.',
      'repotting': 'Saksıda yetiştiriyorsanız 3-4 yılda bir',
      'repottingDetails': 'Üzüm asmaları genellikle bahçede yetiştirilir. Saksıda yetiştiriyorsanız derin saksılar gereklidir. Kökler geniş alan kaplar.',
    };
  }

  // Üzüm - Hasta
  Map<String, String> _grapeCareInfoSick() {
    return {
      'difficulty': 'Zor',
      'difficultyDetails': 'Hastalıklı üzüm asmaları için özel bakım ve düzenli ilaçlama gerekebilir. Erken tespit kritiktir.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması külleme, esca gibi mantar hastalıklarını yayar. Drip sulama veya toprağa doğrudan sulama yapın. Aşırı nemden kaçının.',
      'fertilization': 'Dengeli, organik gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
      'pruning': 'Hastalıklı dalları derhal budayın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve salkımları hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Havalandırmayı artırmak için yaprakları seyreltin.',
      'repotting': 'Hastalık kontrolü sonrası',
      'repottingDetails': 'Hastalık kontrol altına alındıktan sonra temiz toprak ve sterilize edilmiş saksı kullanın. Kök sistemini kontrol edin, çürümüş kökleri temizleyin.',
    };
  }

  // Kiraz - Sağlıklı
  Map<String, String> _cherryCareInfoHealthy() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Kiraz ağaçları bakımı orta seviyededir. Soğuk iklim gerektirir ve düzenli budama önemlidir.',
      'water': 'Haftada 2-3 kez derin sulama',
      'waterDetails': 'Kiraz ağaçları düzenli su gerektirir. Özellikle meyve oluşum döneminde su eksikliği olmamalıdır. Genç ağaçlar daha sık sulama gerektirir. Toprak nemini koruyun.',
      'fertilization': 'İlkbahar başında bir kez',
      'fertilizationDetails': 'İlkbaharda azotlu gübre uygulayın. Meyve oluşumunda potasyum önemlidir. Organik gübreler (kompost, gübre) kiraz ağaçları için idealdir.',
      'pruning': 'Kış sonu budama',
      'pruningDetails': 'Kış sonu (dormant dönem) budama zamanıdır. Ölü, hastalıklı ve çapraz dalları çıkarın. Ağacın şeklini koruyun ve merkezi açın.',
      'repotting': 'Saksıda yetiştiriyorsanız 3-4 yılda bir',
      'repottingDetails': 'Kiraz ağaçları genellikle bahçede yetiştirilir. Saksıda yetiştiriyorsanız derin saksılar gereklidir. Drenaj çok önemlidir.',
    };
  }

  // Kiraz - Hasta
  Map<String, String> _cherryCareInfoSick() {
    return {
      'difficulty': 'Zor',
      'difficultyDetails': 'Hastalıklı kiraz ağaçları için özel bakım ve düzenli ilaçlama gerekebilir. Erken tespit ve müdahale çok önemlidir.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması külleme gibi mantar hastalıklarını yayar. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın.',
      'fertilization': 'Dengeli, hafif gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
      'pruning': 'Hastalıklı dalları hemen budayın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri derhal çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın.',
      'repotting': 'Hastalık kontrolü sonrası',
      'repottingDetails': 'Hastalık tamamen kontrol altına alındıktan sonra temiz toprak kullanarak değiştirin. Kök çürümesi varsa sağlıklı köklere kadar temizleyin.',
    };
  }

  // Şeftali - Sağlıklı
  Map<String, String> _peachCareInfoHealthy() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Şeftali ağaçları bakımı orta seviyededir. Soğuk iklim gerektirir ve düzenli budama önemlidir.',
      'water': 'Haftada 2-3 kez derin sulama',
      'waterDetails': 'Şeftali ağaçları düzenli su gerektirir. Özellikle meyve oluşum döneminde su eksikliği olmamalıdır. Toprak nemini koruyun ancak aşırı sulamadan kaçının.',
      'fertilization': 'İlkbahar başında bir kez',
      'fertilizationDetails': 'İlkbaharda azotlu gübre uygulayın. Meyve oluşumunda potasyum önemlidir. Organik gübreler şeftali ağaçları için idealdir.',
      'pruning': 'Kış sonu budama',
      'pruningDetails': 'Kış sonu (dormant dönem) budama zamanıdır. Ölü, hastalıklı dalları çıkarın. Ağacın şeklini koruyun ve merkezi açarak hava sirkülasyonunu sağlayın.',
      'repotting': 'Saksıda yetiştiriyorsanız 3-4 yılda bir',
      'repottingDetails': 'Şeftali ağaçları genellikle bahçede yetiştirilir. Saksıda yetiştiriyorsanız derin saksılar gereklidir. İyi drenaj çok önemlidir.',
    };
  }

  // Şeftali - Hasta
  Map<String, String> _peachCareInfoSick() {
    return {
      'difficulty': 'Zor',
      'difficultyDetails': 'Hastalıklı şeftali ağaçları için özel bakım gereklidir. Bakteriyel ve mantar hastalıklarına karşı dikkatli olunmalıdır.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması hastalıkları yayar. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Aşırı nemden kaçının.',
      'fertilization': 'Dengeli gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
      'pruning': 'Hastalıklı dalları derhal budayın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın.',
      'repotting': 'Hastalık kontrolü sonrası',
      'repottingDetails': 'Hastalık tamamen kontrol altına alındıktan sonra temiz toprak kullanarak değiştirin. Kök çürümesi varsa sağlıklı köklere kadar temizleyin.',
    };
  }

  // Biber - Sağlıklı
  Map<String, String> _pepperCareInfoHealthy() {
    return {
      'difficulty': 'Kolay-Orta',
      'difficultyDetails': 'Biber bitkileri bakımı nispeten kolaydır. Düzenli sulama ve gübreleme ile iyi gelişir.',
      'water': 'Haftada 3-4 kez düzenli sulama',
      'waterDetails': 'Biber bitkileri düzenli su gerektirir. Toprak nemini koruyun ancak aşırı sulamadan kaçının. Sabah saatlerinde sulama yapın, yaprakları ıslatmadan.',
      'fertilization': 'Büyüme boyunca 2-3 haftada bir',
      'fertilizationDetails': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanın. Meyve oluşumunda potasyum önemlidir. Organik gübreler (kompost) idealdir.',
      'pruning': 'Alt yaprakları temizleyin',
      'pruningDetails': 'Alt kısımdaki sararmış yaprakları çıkarın. Bu havalandırmayı artırır ve hastalık riskini azaltır.',
      'repotting': 'Tohumdan yetiştiriyorsanız fide aşamasında',
      'repottingDetails': 'Biber fidelerini tohum çimlendirme sonrası daha büyük saksılara alın. Köklerin rahatça gelişebileceği saksılar tercih edin.',
    };
  }

  // Biber - Hasta
  Map<String, String> _pepperCareInfoSick() {
    return {
      'difficulty': 'Orta-Zor',
      'difficultyDetails': 'Hastalıklı biber bitkileri için dikkatli bakım gereklidir. Bakteriyel ve mantar hastalıklarına karşı önlem alınmalıdır.',
      'water': 'Yaprakları ıslatmadan sabah sulama',
      'waterDetails': 'Yaprak ıslanması hastalıkları yayar. Drip sulama sistemi kullanın veya toprağa doğrudan sulayın. Aşırı nemden kaçının.',
      'fertilization': 'Hafif, dengeli gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum ve kalsiyum içeren gübreler hastalık direncini artırır. Yarı dozda gübre kullanın.',
      'pruning': 'Hastalıklı yaprakları hemen çıkarın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri derhal çıkarın ve yakın. Budama aletlerini sterilize edin. Havalandırmayı artırmak için alt yaprakları temizleyin.',
      'repotting': 'Hastalık kontrolü sonrası',
      'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. Kök sistemini kontrol edin, çürümüş kökleri temizleyin.',
    };
  }

  // Patates - Sağlıklı
  Map<String, String> _potatoCareInfoHealthy() {
    return {
      'difficulty': 'Kolay',
      'difficultyDetails': 'Patates bitkileri bakımı kolaydır. Uygun toprak ve düzenli sulama ile iyi gelişir.',
      'water': 'Haftada 2-3 kez düzenli sulama',
      'waterDetails': 'Patates düzenli su gerektirir ancak aşırı sulamadan kaçının. Toprak nemini koruyun. Yumru oluşum döneminde düzenli sulama önemlidir.',
      'fertilization': 'Dikim öncesi ve çiçeklenme öncesi',
      'fertilizationDetails': 'Dikim öncesi kompost veya organik gübre uygulayın. Çiçeklenme öncesi potasyum içeren gübre uygulayın. Aşırı azot yaprak büyümesini artırır ancak yumru verimini düşürür.',
      'pruning': 'Gereksiz',
      'pruningDetails': 'Patates bitkileri budama gerektirmez. Sadece hasat sonrası bitki artıklarını temizleyin.',
      'repotting': 'Genellikle gerekli değil',
      'repottingDetails': 'Patates genellikle sezonsal olarak yetiştirilir. Saksıda yetiştiriyorsanız derin saksılar gereklidir. Yumrular için yeterli alan sağlayın.',
    };
  }

  // Patates - Hasta
  Map<String, String> _potatoCareInfoSick() {
    return {
      'difficulty': 'Orta-Zor',
      'difficultyDetails': 'Hastalıklı patates bitkileri için dikkatli bakım gereklidir. Geç yanıklık gibi ciddi hastalıklara karşı önlem alınmalıdır.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması geç yanıklık ve erken yanıklık gibi hastalıkları yayar. Drip sulama veya toprağa doğrudan sulama yapın. Sabah saatlerinde sulayın.',
      'fertilization': 'Dengeli, hafif gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın.',
      'pruning': 'Hastalıklı yaprakları temizleyin',
      'pruningDetails': 'Hastalıklı yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin.',
      'repotting': 'Genellikle gerekli değil',
      'repottingDetails': 'Patates sezonsal olarak yetiştirilir. Eğer saksıda yetiştiriyorsanız ve hastalık varsa, toprağı değiştirin ve sterilize edin.',
    };
  }

  // Çilek - Sağlıklı
  Map<String, String> _strawberryCareInfoHealthy() {
    return {
      'difficulty': 'Kolay',
      'difficultyDetails': 'Çilek bitkileri bakımı kolaydır. Uygun toprak, düzenli sulama ve güneş ışığı ile iyi gelişir.',
      'water': 'Haftada 3-4 kez düzenli sulama',
      'waterDetails': 'Çilek bitkileri düzenli su gerektirir. Toprak nemini koruyun ancak yaprakları ıslatmamaya özen gösterin. Meyve oluşum döneminde su eksikliği olmamalıdır.',
      'fertilization': 'İlkbahar ve yaz başında',
      'fertilizationDetails': 'İlkbaharda azotlu gübre, çiçeklenme ve meyve oluşumunda potasyum-fosforlu gübre uygulayın. Organik gübreler (kompost) çilek için idealdir.',
      'pruning': 'Hasat sonrası yaprakları temizleyin',
      'pruningDetails': 'Hasat sonrası eski yaprakları çıkarın. Yeni sürgünleri teşvik eder. Kış öncesi bitkiyi temizleyin.',
      'repotting': 'Her 2-3 yılda bir',
      'repottingDetails': 'Çilek bitkileri saksıda yetiştirilebilir. Kökler saksıyı doldurduğunda veya verim düştüğünde yeniden dikim yapın. Yeni fide kullanabilirsiniz.',
    };
  }

  // Çilek - Hasta
  Map<String, String> _strawberryCareInfoSick() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Hastalıklı çilek bitkileri için dikkatli bakım gereklidir. Yaprak yanması ve kök çürümesi gibi hastalıklara karşı önlem alınmalıdır.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması yaprak yanması gibi hastalıkları yayar. Drip sulama veya toprağa doğrudan sulama yapın. Aşırı nemden kaçının, kök çürümesine neden olabilir.',
      'fertilization': 'Dengeli, hafif gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Organik gübreler tercih edin.',
      'pruning': 'Hastalıklı yaprakları derhal çıkarın',
      'pruningDetails': 'Hastalıklı yaprakları hemen çıkarın ve yakın. Bu hastalığın yayılmasını önler. Hasat sonrası tüm bitki artıklarını temizleyin.',
      'repotting': 'Hastalık kontrolü sonrası',
      'repottingDetails': 'Hastalıklı bitkileri temiz toprak ve sterilize edilmiş saksılara alın. Kök çürümesi varsa sağlıklı köklere kadar temizleyin.',
    };
  }

  // Turunçgil - Sağlıklı
  Map<String, String> _citrusCareInfoHealthy() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Turunçgil ağaçları bakımı orta seviyededir. Soğuktan korunma ve düzenli bakım gerektirir.',
      'water': 'Haftada 2-3 kez derin sulama',
      'waterDetails': 'Turunçgil ağaçları düzenli su gerektirir ancak aşırı sulamadan kaçının. Toprak iyi drene olmalıdır. Genç ağaçlar daha sık sulama gerektirir.',
      'fertilization': 'İlkbahar, yaz ve sonbahar başında',
      'fertilizationDetails': 'Turunçgil ağaçları için özel formüle edilmiş gübreler kullanın. Azot, potasyum ve mikro besinler önemlidir. Organik gübreler de uygundur.',
      'pruning': 'İlkbahar sonu - yaz başı',
      'pruningDetails': 'Ölü, hastalıklı ve çapraz dalları çıkarın. Ağacın şeklini koruyun ve merkezi açın. Aşırı budamadan kaçının.',
      'repotting': 'Saksıda yetiştiriyorsanız 2-3 yılda bir',
      'repottingDetails': 'Turunçgil ağaçları saksıda yetiştirilebilir. Kökler saksıyı doldurduğunda daha büyük saksıya alın. İyi drenaj çok önemlidir.',
    };
  }

  // Turunçgil - Hasta
  Map<String, String> _citrusCareInfoSick() {
    return {
      'difficulty': 'Zor',
      'difficultyDetails': 'Hastalıklı turunçgil ağaçları için özel bakım gereklidir. Turunçgil yeşillenmesi gibi ciddi hastalıklara karşı erken müdahale kritiktir.',
      'water': 'Yaprakları ıslatmadan toprağa sulama',
      'waterDetails': 'Yaprak ıslanması hastalıkları yayar. Sabah saatlerinde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Kök çürümesinden kaçının.',
      'fertilization': 'Dengeli, mikro besin içeren gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Demir, çinko gibi mikro besinler önemlidir. Turunçgil için özel formüle edilmiş gübreler kullanın.',
      'pruning': 'Hastalıklı dalları derhal budayın',
      'pruningDetails': 'Hastalıklı yaprak, dal ve meyveleri hemen çıkarın ve yakın. Budama aletlerini sterilize edin. Budama yaralarını koruyucu ile kapatın.',
      'repotting': 'Hastalık kontrolü sonrası',
      'repottingDetails': 'Hastalık tamamen kontrol altına alındıktan sonra temiz toprak kullanarak değiştirin. Kök çürümesi varsa sağlıklı köklere kadar temizleyin.',
    };
  }

  // Yaban Mersini - Sağlıklı
  Map<String, String> _blueberryCareInfoHealthy() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Yaban mersini bitkileri asidik toprak ve düzenli bakım gerektirir. Uygun koşullar sağlandığında verimli yetişir.',
      'water': 'Haftada 2-3 kez, toprak nemli kalmalı',
      'waterDetails': 'Yaban mersini bitkileri düzenli su gerektirir. Toprak sürekli nemli kalmalı ancak su birikintisi olmamalıdır. Özellikle meyve oluşumu döneminde düzenli sulama önemlidir. Yağmurlama yerine damla sulama tercih edilmelidir.',
      'fertilization': 'İlkbahar başında ve yaz ortasında',
      'fertilizationDetails': 'Yaban mersini için özel asidik gübreler kullanın. Organik gübreler (kompost, çam iğneleri) çok uygundur. Azot ihtiyacı düşüktür, potasyum ve fosfor önemlidir. Aşırı gübrelemeden kaçının.',
      'pruning': 'Kış sonu - ilkbahar başı',
      'pruningDetails': 'Ölü, hastalıklı ve yaşlı dalları çıkarın. Genç, verimli dalları koruyun. İnce ve zayıf dalları budayarak havalandırmayı artırın. Çalıların merkezini açın.',
      'repotting': 'Saksıda yetiştiriyorsanız 2-3 yılda bir',
      'repottingDetails': 'Yaban mersini saksıda yetiştirilebilir. Kökler saksıyı doldurduğunda asidik toprak karışımı ile daha büyük saksıya alın. İyi drenaj çok önemlidir.',
    };
  }

  // Ahududu - Sağlıklı
  Map<String, String> _raspberryCareInfoHealthy() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Ahududu bitkileri hızlı büyür ve bakımı orta seviyededir. Düzenli budama ve destek sistemi gerektirir.',
      'water': 'Haftada 2-3 kez, özellikle meyve oluşumu döneminde',
      'waterDetails': 'Ahududu bitkileri düzenli su gerektirir. Toprak nemli kalmalı ancak su birikintisi olmamalıdır. Meyve oluşumu ve olgunlaşma döneminde daha sık sulama yapın. Yaprakları ıslatmadan toprağa doğrudan sulama yapın.',
      'fertilization': 'İlkbahar başında ve meyve oluşumundan önce',
      'fertilizationDetails': 'Ahududu için dengeli gübreler kullanın. İlkbahar başında azot, meyve oluşumundan önce potasyum ve fosfor ağırlıklı gübre uygulayın. Organik gübreler (kompost, gübre) çok uygundur.',
      'pruning': 'Kış sonu ve yaz sonu',
      'pruningDetails': 'Kış sonunda ölü ve verimsiz dalları çıkarın. Yaz sonunda meyve vermiş dalları budayın. Genç sürgünleri destek sistemine bağlayın. Havalandırmayı artırmak için sıkışık dalları seyreltin.',
      'repotting': 'Saksıda yetiştiriyorsanız 2 yılda bir',
      'repottingDetails': 'Ahududu saksıda yetiştirilebilir ancak genellikle bahçede yetiştirilir. Kökler saksıyı doldurduğunda daha büyük saksıya alın. İyi drenaj çok önemlidir.',
    };
  }

  // Soya - Sağlıklı
  Map<String, String> _soybeanCareInfoHealthy() {
    return {
      'difficulty': 'Kolay-Orta',
      'difficultyDetails': 'Soya bitkileri bakımı kolay-orta seviyededir. Uygun toprak koşulları ve düzenli bakım ile verimli yetişir.',
      'water': 'Toprak kurudukça, düzenli sulama',
      'waterDetails': 'Soya bitkileri düzenli su gerektirir. Özellikle çiçeklenme ve bakla oluşumu döneminde yeterli su çok önemlidir. Toprak kurumaya başladığında sulama yapın. Drip sulama sistemi idealdir.',
      'fertilization': 'Ekim öncesi ve çiçeklenme öncesi',
      'fertilizationDetails': 'Soya bitkileri azot fiksasyonu yapar, bu yüzden azot ihtiyacı düşüktür. Fosfor ve potasyum önemlidir. Ekim öncesi toprağa fosfor ve potasyum gübreleri karıştırın. Rhizobium bakterisi ile aşılanmış tohumlar kullanın.',
      'pruning': 'Genellikle gerekli değil',
      'pruningDetails': 'Soya bitkileri genellikle budama gerektirmez. Sadece hastalıklı veya zararlı hasarlı yaprakları temizleyin. Yabani ot kontrolü önemlidir.',
      'repotting': 'Genellikle gerekli değil',
      'repottingDetails': 'Soya bitkileri genellikle tarlada yetiştirilir. Saksıda yetiştirilebilir ancak derin kök yapısı nedeniyle büyük saksılar gerekir. İyi drenaj çok önemlidir.',
    };
  }

  // Kabak - Sağlıklı
  Map<String, String> _squashCareInfoHealthy() {
    return {
      'difficulty': 'Kolay',
      'difficultyDetails': 'Kabak bitkileri bakımı kolaydır. Hızlı büyür ve bol ürün verir. Uygun toprak ve düzenli sulama ile verimli yetişir.',
      'water': 'Haftada 2-3 kez, derin sulama',
      'waterDetails': 'Kabak bitkileri düzenli su gerektirir. Toprak kurumaya başladığında sulama yapın. Yaprakları ıslatmadan toprağa doğrudan sulama yapın. Özellikle meyve oluşumu döneminde düzenli sulama çok önemlidir. Sabah saatlerinde sulama yapın.',
      'fertilization': 'Ekim öncesi ve çiçeklenme öncesi',
      'fertilizationDetails': 'Kabak bitkileri için dengeli gübreler kullanın. Kompost ve organik gübreler çok uygundur. Fosfor çiçeklenme için, potasyum meyve kalitesi için önemlidir. Aşırı azot yaprak gelişimini artırır ancak meyve üretimini azaltır.',
      'pruning': 'Gerektiğinde, yaprakları seyreltme',
      'pruningDetails': 'Kabak bitkileri genellikle budama gerektirmez ancak çok sıkışık yapraklar varsa havalandırmayı artırmak için bazı yaprakları çıkarabilirsiniz. Hastalıklı yaprakları derhal temizleyin.',
      'repotting': 'Genellikle gerekli değil',
      'repottingDetails': 'Kabak bitkileri genellikle bahçede yetiştirilir. Saksıda yetiştirilebilir ancak büyük saksılar gerekir. İyi drenaj çok önemlidir.',
    };
  }

  // Kabak - Hasta
  Map<String, String> _squashCareInfoSick() {
    return {
      'difficulty': 'Orta',
      'difficultyDetails': 'Hastalıklı kabak bitkileri için özel bakım gereklidir. Külleme gibi yaygın hastalıklara karşı erken müdahale önemlidir.',
      'water': 'Yaprakları ıslatmadan sabah sulama',
      'waterDetails': 'Yaprak ıslanması hastalıkları yayar. Sabah erken saatlerde, yaprakları ıslatmadan toprağa doğrudan sulama yapın. Drip sulama sistemi kullanın. Aşırı nemden kaçının.',
      'fertilization': 'Dengeli gübreleme',
      'fertilizationDetails': 'Aşırı azot hastalık şiddetini artırabilir. Potasyum içeren gübreler hastalık direncini artırır. Dengeli bir gübre programı uygulayın. Organik gübreler tercih edin.',
      'pruning': 'Hastalıklı yaprakları temizleyin',
      'pruningDetails': 'Hastalıklı yaprakları derhal çıkarın ve yakın. Havalandırmayı artırmak için sıkışık yaprakları seyreltin. Budama aletlerini sterilize edin.',
      'repotting': 'Genellikle gerekli değil',
      'repottingDetails': 'Kabak bitkileri genellikle bahçede yetiştirilir. Hastalık kontrol altına alındıktan sonra temiz toprak kullanın. İlaçlama: Uygun fungisitlerle ilaçlama yapın.',
    };
  }

  Widget _resultRow(String label, String value,
      {Color? badgeColor, Color? badgeBorder, Color? badgeText, double? progressValue}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
              Expanded(
                child: badgeColor != null
                    ? Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: badgeBorder ?? badgeColor),
                        ),
                        child: Text(
                          value,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: badgeText ?? AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      )
                    : Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                      ),
              ),
            ],
          ),
          if (progressValue != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.border),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progressValue.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ],
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
            style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ),
      ],
    );
  }

  // Türkçe display name oluştur (bitki türü + hastalık/sağlık durumu)
  String _getTurkishDisplayName(String? rawClassName, String? plantType, bool isHealthy) {
    if (rawClassName == null || rawClassName.isEmpty) {
      return 'Bilinmiyor';
    }
    
    // Plant type Türkçe'sini al
    String turkishPlantType = plantType ?? 'Bilinmeyen Bitki';
    
    // Analiz sonuçlarında gösterim için: Bitki ismi • Hastalık formatı
    if (isHealthy) {
      return turkishPlantType; // Sağlıklı için sadece bitki ismi
    }
    
    // Hastalık durumunda, rawClassName'den hastalık adını çıkar
    if (rawClassName.contains('___')) {
      final parts = rawClassName.split('___');
      if (parts.length >= 2) {
        var diseaseKey = parts[1];
        // Normalize et
        diseaseKey = diseaseKey.replaceAll(RegExp(r'_+$'), '').trim();
        
        // Önce tam key ile dene
        String turkishDisease = _plantVillageDiseaseTranslations[diseaseKey] ?? '';
        
        // Eğer bulunamadıysa, lowercase versiyonu dene
        if (turkishDisease.isEmpty) {
          turkishDisease = _plantVillageDiseaseTranslations[diseaseKey.toLowerCase()] ?? '';
        }
        
        // Eğer hala bulunamadıysa, boşlukla ayrılmış formatı dene (örn: "Cercospora_leaf_spot Gray_leaf_spot")
        if (turkishDisease.isEmpty && diseaseKey.contains(' ')) {
          turkishDisease = _plantVillageDiseaseTranslations[diseaseKey] ?? '';
        }
        
        // Eğer hala bulunamadıysa, underscore'ları boşlukla değiştirip dene
        if (turkishDisease.isEmpty) {
          final spacedKey = diseaseKey.replaceAll('_', ' ');
          turkishDisease = _plantVillageDiseaseTranslations[spacedKey] ?? '';
        }
        
        // Son çare: prettify et
        if (turkishDisease.isEmpty) {
          turkishDisease = _prettifyClassName(diseaseKey);
        }
        
        return '$turkishPlantType • $turkishDisease';
      }
    }
    
    // Fallback
    return '$turkishPlantType • ${_prettifyClassName(rawClassName)}';
  }

  Map<String, String> _translateDisease(String? displayName, String rawClass) {
    final latin = (displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : _prettifyClassName(rawClass));
    // PlantVillage class formatı: "Plant___Status" şeklinde olabilir
    final statusPart = rawClass.split('___').last; // Status kısmını al
    final turkish = _plantVillageDiseaseTranslations[statusPart] ?? 
                    _plantVillageDiseaseTranslations[rawClass] ?? 
                    latin;
    return {'tr': turkish, 'latin': latin};
  }

  String _prettifyClassName(String value) {
    return value
        .split('_')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  // Tesis Gereksinimleri Fonksiyonları
  Map<String, String> _defaultFacilityRequirements() {
    return {
      'pot': 'Standart saksı',
      'potDetails': 'Bitki boyutuna uygun, drenaj delikli saksı kullanın.',
      'soil': 'Drenajlı toprak',
      'soilDetails': 'İyi drenajlı, organik madde içeren toprak karışımı kullanın.',
      'lighting': 'Orta ışık',
      'lightingDetails': 'Günde 4-6 saat dolaylı güneş ışığı veya parlak yapay ışık.',
      'humidity': 'Orta nem (%40-60)',
      'humidityDetails': 'Ortam nemini %40-60 aralığında tutun. Gerekirse nemlendirici kullanın.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Bu bitki türü için belirgin bir dinlenme dönemi yoktur.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '18-24°C',
      'temperatureDetails': 'Oda sıcaklığında (18-24°C) yetiştirilebilir.',
    };
  }

  Map<String, String> _appleFacilityRequirements() {
    return {
      'pot': 'Büyük saksı (min 50L)',
      'potDetails': 'Elma ağaçları için büyük, derin saksılar gereklidir. Minimum 50 litre kapasiteli saksı kullanın. Drenaj delikleri olmalı.',
      'soil': 'Zengin, drenajlı toprak',
      'soilDetails': 'Organik madde bakımından zengin, iyi drenajlı toprak. pH 6.0-7.0 arası. Kompost ve perlit karışımı ideal.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Güney veya batı cephe tercih edilir.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok kuru hava yaprak kurumasına neden olur.',
      'dormancy': 'Soğuk dönem (0-7°C)',
      'dormancyDetails': 'Kış aylarında 0-7°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir. Serada yetiştiriyorsanız 800-1000 ppm optimal.',
      'temperature': '15-25°C (yaz), 0-7°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-25°C, kış aylarında 0-7°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _tomatoFacilityRequirements() {
    return {
      'pot': 'Orta-büyük saksı (20-30L)',
      'potDetails': 'Domates bitkileri için minimum 20-30 litre kapasiteli, derin saksılar gereklidir. Destek için saksı yanında kazık kullanın.',
      'soil': 'Zengin, organik toprak',
      'soilDetails': 'Organik madde bakımından çok zengin, iyi drenajlı toprak. pH 6.0-6.8 arası. Kompost, perlit ve vermikülit karışımı.',
      'lighting': 'Tam güneş (8+ saat)',
      'lightingDetails': 'Günde en az 8 saat direkt güneş ışığı gereklidir. Yetersiz ışık verimi düşürür.',
      'humidity': 'Orta-yüksek nem (%60-80)',
      'humidityDetails': 'Orta-yüksek nem seviyesi (%60-80) idealdir. Çok kuru hava çiçek dökümüne neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Domates tek yıllık bir bitkidir, dinlenme dönemi yoktur. Sezon sonunda ölür.',
      'co2': 'Yüksek (800-1200 ppm)',
      'co2Details': 'Serada yetiştiriyorsanız yüksek CO2 seviyesi (800-1200 ppm) verimi artırır. Açık havada normal seviye yeterlidir.',
      'temperature': '18-27°C (gündüz), 15-18°C (gece)',
      'temperatureDetails': 'Gündüz 18-27°C, gece 15-18°C idealdir. 30°C üzeri sıcaklıklar çiçek dökümüne neden olur.',
    };
  }

  Map<String, String> _cornFacilityRequirements() {
    return {
      'pot': 'Büyük saksı veya toprak',
      'potDetails': 'Mısır bitkileri için geniş alan gereklidir. Saksıda yetiştirilecekse minimum 40 litre, tercihen toprakta yetiştirilir.',
      'soil': 'Zengin, derin toprak',
      'soilDetails': 'Organik madde bakımından zengin, derin ve iyi drenajlı toprak. pH 6.0-7.0 arası. Azot bakımından zengin toprak tercih edilir.',
      'lighting': 'Tam güneş (8+ saat)',
      'lightingDetails': 'Günde en az 8 saat direkt güneş ışığı gereklidir. Yetersiz ışık büyümeyi engeller.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Mısır tek yıllık bir bitkidir, dinlenme dönemi yoktur. Hasat sonrası ölür.',
      'co2': 'Yüksek (800-1000 ppm)',
      'co2Details': 'Mısır C4 bitkisi olduğu için yüksek CO2 seviyesi (800-1000 ppm) verimi önemli ölçüde artırır.',
      'temperature': '21-30°C',
      'temperatureDetails': '21-30°C arası sıcaklık idealdir. 15°C altı büyümeyi yavaşlatır, 35°C üzeri stres yaratır.',
    };
  }

  Map<String, String> _grapeFacilityRequirements() {
    return {
      'pot': 'Büyük saksı (min 50L)',
      'potDetails': 'Üzüm asmaları için büyük, derin saksılar gereklidir. Minimum 50 litre kapasiteli saksı kullanın. Destek için kafes veya pergola gerekir.',
      'soil': 'Drenajlı, kireçli toprak',
      'soilDetails': 'İyi drenajlı, hafif kireçli toprak. pH 6.5-7.5 arası. Organik madde içeren, derin toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Düşük-orta nem (%40-60)',
      'humidityDetails': 'Düşük-orta nem seviyesi (%40-60) idealdir. Yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Soğuk dönem (0-10°C)',
      'dormancyDetails': 'Kış aylarında 0-10°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir. Serada yetiştiriyorsanız 700-900 ppm optimal.',
      'temperature': '15-30°C (yaz), 0-10°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-30°C, kış aylarında 0-10°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _cherryFacilityRequirements() {
    return {
      'pot': 'Büyük saksı (min 50L)',
      'potDetails': 'Kiraz ağaçları için büyük, derin saksılar gereklidir. Minimum 50 litre kapasiteli saksı kullanın.',
      'soil': 'Drenajlı, hafif asidik toprak',
      'soilDetails': 'İyi drenajlı, hafif asidik toprak. pH 6.0-6.5 arası. Organik madde içeren toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok kuru hava yaprak kurumasına neden olur.',
      'dormancy': 'Soğuk dönem (0-7°C)',
      'dormancyDetails': 'Kış aylarında 0-7°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '15-25°C (yaz), 0-7°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-25°C, kış aylarında 0-7°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _peachFacilityRequirements() {
    return {
      'pot': 'Büyük saksı (min 50L)',
      'potDetails': 'Şeftali ağaçları için büyük, derin saksılar gereklidir. Minimum 50 litre kapasiteli saksı kullanın.',
      'soil': 'Drenajlı, hafif asidik toprak',
      'soilDetails': 'İyi drenajlı, hafif asidik toprak. pH 6.0-6.5 arası. Organik madde içeren toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok kuru hava yaprak kurumasına neden olur.',
      'dormancy': 'Soğuk dönem (0-7°C)',
      'dormancyDetails': 'Kış aylarında 0-7°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '15-25°C (yaz), 0-7°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-25°C, kış aylarında 0-7°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _pepperFacilityRequirements() {
    return {
      'pot': 'Orta saksı (15-20L)',
      'potDetails': 'Biber bitkileri için orta boy, derin saksılar gereklidir. Minimum 15-20 litre kapasiteli saksı kullanın.',
      'soil': 'Zengin, drenajlı toprak',
      'soilDetails': 'Organik madde bakımından zengin, iyi drenajlı toprak. pH 6.0-7.0 arası. Kompost ve perlit karışımı ideal.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık verimi düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Biber tek yıllık bir bitkidir, dinlenme dönemi yoktur. Sezon sonunda ölür.',
      'co2': 'Yüksek (800-1000 ppm)',
      'co2Details': 'Serada yetiştiriyorsanız yüksek CO2 seviyesi (800-1000 ppm) verimi artırır. Açık havada normal seviye yeterlidir.',
      'temperature': '21-29°C',
      'temperatureDetails': '21-29°C arası sıcaklık idealdir. 15°C altı büyümeyi yavaşlatır, 32°C üzeri çiçek dökümüne neden olur.',
    };
  }

  Map<String, String> _potatoFacilityRequirements() {
    return {
      'pot': 'Büyük saksı veya toprak',
      'potDetails': 'Patates bitkileri için geniş ve derin saksılar gereklidir. Minimum 30 litre kapasiteli saksı kullanın. Tercihen toprakta yetiştirilir.',
      'soil': 'Hafif, drenajlı toprak',
      'soilDetails': 'Hafif, iyi drenajlı, organik madde içeren toprak. pH 5.0-6.0 arası. Ağır topraklardan kaçının.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık verimi düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Patates tek yıllık bir bitkidir, dinlenme dönemi yoktur. Hasat sonrası ölür.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '15-21°C',
      'temperatureDetails': '15-21°C arası sıcaklık idealdir. 10°C altı büyümeyi durdurur, 25°C üzeri verimi düşürür.',
    };
  }

  Map<String, String> _strawberryFacilityRequirements() {
    return {
      'pot': 'Orta saksı (10-15L)',
      'potDetails': 'Çilek bitkileri için orta boy saksılar yeterlidir. Minimum 10-15 litre kapasiteli saksı kullanın. Geniş ağızlı saksılar tercih edilir.',
      'soil': 'Asidik, drenajlı toprak',
      'soilDetails': 'Hafif asidik, iyi drenajlı toprak. pH 5.5-6.5 arası. Organik madde içeren toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Soğuk dönem (0-5°C)',
      'dormancyDetails': 'Kış aylarında 0-5°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '15-25°C (yaz), 0-5°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-25°C, kış aylarında 0-5°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _citrusFacilityRequirements() {
    return {
      'pot': 'Büyük saksı (min 40L)',
      'potDetails': 'Turunçgil ağaçları için büyük, derin saksılar gereklidir. Minimum 40 litre kapasiteli saksı kullanın.',
      'soil': 'Drenajlı, hafif asidik toprak',
      'soilDetails': 'İyi drenajlı, hafif asidik toprak. pH 6.0-7.0 arası. Organik madde içeren toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Orta-yüksek nem (%60-80)',
      'humidityDetails': 'Orta-yüksek nem seviyesi (%60-80) idealdir. Çok kuru hava yaprak kurumasına neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Turunçgil ağaçları yaprak dökmez, sürekli yeşil kalır. Belirgin bir dinlenme dönemi yoktur.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '18-29°C',
      'temperatureDetails': '18-29°C arası sıcaklık idealdir. 10°C altı büyümeyi yavaşlatır, don olaylarına hassastır.',
    };
  }

  Map<String, String> _blueberryFacilityRequirements() {
    return {
      'pot': 'Orta-büyük saksı (20-30L)',
      'potDetails': 'Yaban mersini için orta-büyük, derin saksılar gereklidir. Minimum 20-30 litre kapasiteli saksı kullanın.',
      'soil': 'Çok asidik, drenajlı toprak',
      'soilDetails': 'Çok asidik, iyi drenajlı toprak. pH 4.5-5.5 arası. Organik madde içeren, turba bazlı toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Orta-yüksek nem (%60-80)',
      'humidityDetails': 'Orta-yüksek nem seviyesi (%60-80) idealdir. Çok kuru hava yaprak kurumasına neden olur.',
      'dormancy': 'Soğuk dönem (0-7°C)',
      'dormancyDetails': 'Kış aylarında 0-7°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '15-25°C (yaz), 0-7°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-25°C, kış aylarında 0-7°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _raspberryFacilityRequirements() {
    return {
      'pot': 'Büyük saksı (min 30L)',
      'potDetails': 'Ahududu için büyük, derin saksılar gereklidir. Minimum 30 litre kapasiteli saksı kullanın. Destek için kafes gerekir.',
      'soil': 'Drenajlı, hafif asidik toprak',
      'soilDetails': 'İyi drenajlı, hafif asidik toprak. pH 5.5-6.5 arası. Organik madde içeren toprak tercih edilir.',
      'lighting': 'Tam güneş (6-8 saat)',
      'lightingDetails': 'Günde en az 6-8 saat direkt güneş ışığı gereklidir. Yetersiz ışık meyve kalitesini düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Soğuk dönem (0-7°C)',
      'dormancyDetails': 'Kış aylarında 0-7°C arası soğuk dönem gereklidir. Bu dönemde yaprak döker ve dinlenir.',
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '15-25°C (yaz), 0-7°C (kış)',
      'temperatureDetails': 'Yaz aylarında 15-25°C, kış aylarında 0-7°C arası sıcaklık gereklidir. Don olaylarına dayanıklıdır.',
    };
  }

  Map<String, String> _soybeanFacilityRequirements() {
    return {
      'pot': 'Büyük saksı veya toprak',
      'potDetails': 'Soya bitkileri için geniş alan gereklidir. Saksıda yetiştirilecekse minimum 30 litre, tercihen toprakta yetiştirilir.',
      'soil': 'Zengin, drenajlı toprak',
      'soilDetails': 'Organik madde bakımından zengin, iyi drenajlı toprak. pH 6.0-7.0 arası. Azot bakımından zengin toprak tercih edilir.',
      'lighting': 'Tam güneş (8+ saat)',
      'lightingDetails': 'Günde en az 8 saat direkt güneş ışığı gereklidir. Yetersiz ışık büyümeyi engeller.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Soya tek yıllık bir bitkidir, dinlenme dönemi yoktur. Hasat sonrası ölür.',
      'co2': 'Yüksek (800-1000 ppm)',
      'co2Details': 'Soya C3 bitkisi olduğu için yüksek CO2 seviyesi (800-1000 ppm) verimi artırır.',
      'temperature': '20-30°C',
      'temperatureDetails': '20-30°C arası sıcaklık idealdir. 15°C altı büyümeyi yavaşlatır, 35°C üzeri stres yaratır.',
    };
  }

  Map<String, String> _squashFacilityRequirements() {
    return {
      'pot': 'Büyük saksı veya toprak',
      'potDetails': 'Kabak bitkileri için geniş alan gereklidir. Saksıda yetiştirilecekse minimum 40 litre, tercihen toprakta yetiştirilir.',
      'soil': 'Zengin, drenajlı toprak',
      'soilDetails': 'Organik madde bakımından çok zengin, iyi drenajlı toprak. pH 6.0-7.0 arası. Kompost içeren toprak tercih edilir.',
      'lighting': 'Tam güneş (8+ saat)',
      'lightingDetails': 'Günde en az 8 saat direkt güneş ışığı gereklidir. Yetersiz ışık verimi düşürür.',
      'humidity': 'Orta nem (%50-70)',
      'humidityDetails': 'Orta nem seviyesi (%50-70) idealdir. Çok yüksek nem mantar hastalıklarına neden olur.',
      'dormancy': 'Yok',
      'dormancyDetails': 'Kabak tek yıllık bir bitkidir, dinlenme dönemi yoktur. Sezon sonunda ölür.',
      'co2': 'Yüksek (800-1000 ppm)',
      'co2Details': 'Serada yetiştiriyorsanız yüksek CO2 seviyesi (800-1000 ppm) verimi artırır. Açık havada normal seviye yeterlidir.',
      'temperature': '18-27°C',
      'temperatureDetails': '18-27°C arası sıcaklık idealdir. 15°C altı büyümeyi yavaşlatır, 30°C üzeri stres yaratır.',
    };
  }
}

class _ImageSourceOption extends StatelessWidget {
  const _ImageSourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}


class _CommonIssuesContent extends StatelessWidget {
  const _CommonIssuesContent({required this.scrollController});

  final ScrollController scrollController;

  // Genel hastalık isimleri (Türkçe literatür bazlı)
  static const Map<String, String> _generalDiseaseNames = {
    'Early_blight': 'Yanıklık',
    'Late_blight': 'Yanıklık',
    'Black_rot': 'Siyah Çürüklük',
    'Bacterial_spot': 'Bakteriyel Leke',
    'Cercospora_leaf_spot Gray_leaf_spot': 'Yaprak Lekesi',
    'Septoria_leaf_spot': 'Yaprak Lekesi',
    'Target_Spot': 'Yaprak Lekesi',
    'Leaf_blight_(Isariopsis_Leaf_Spot)': 'Yaprak Lekesi',
    'Cedar_apple_rust': 'Pas',
    'Common_rust': 'Pas',
    'Powdery_mildew': 'Külleme',
    'Leaf_Mold': 'Yaprak Küfü',
    'Apple_scab': 'Uyuz',
    'Tomato_mosaic_virus': 'Mozaik Virüsü',
    'Tomato_Yellow_Leaf_Curl_Virus': 'Yaprak Kıvırcık Virüsü',
    'Spider_mites Two-spotted_spider_mite': 'Kırmızı Örümcek',
    'Leaf_scorch': 'Yaprak Yanması',
    'Esca_(Black_Measles)': 'Esca',
    'Haunglongbing_(Citrus_greening)': 'Turunçgil Yeşillenmesi',
  };

  // Bakım önerileri (hastalık key -> öneriler listesi)
  static final Map<String, List<Map<String, dynamic>>> _careRecommendations = {
    'Early_blight': [
      {'text': 'Etkilenen yaprakları derhal temizleyin ve yakın', 'icon': Icons.delete_outline},
      {'text': 'Yaprakları ıslatmadan toprağa doğrudan sulama yapın', 'icon': Icons.water_drop_outlined},
      {'text': 'Havalandırmayı artırın, bitkiler arası mesafeyi koruyun', 'icon': Icons.air_outlined},
      {'text': 'Uygun fungisitlerle önleyici ilaçlama yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Late_blight': [
      {'text': 'Hastalıklı bitkileri hemen ortamdan çıkarın', 'icon': Icons.remove_circle_outline},
      {'text': 'Yaprakların ıslanmasını önleyin, damla sulama kullanın', 'icon': Icons.water_drop_outlined},
      {'text': 'Serin ve nemli koşullardan koruyun', 'icon': Icons.ac_unit_outlined},
      {'text': 'Sistemik fungisitlerle acil müdahale yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Black_rot': [
      {'text': 'Enfekte meyve ve yaprakları temizleyin', 'icon': Icons.cleaning_services_outlined},
      {'text': 'Budama aletlerini sterilize edin', 'icon': Icons.content_cut},
      {'text': 'Havalandırmayı iyileştirin', 'icon': Icons.air_outlined},
      {'text': 'Bakır bazlı fungisitler kullanın', 'icon': Icons.medical_services_outlined},
    ],
    'Bacterial_spot': [
      {'text': 'Hastalıklı bitki kısımlarını budayın', 'icon': Icons.content_cut},
      {'text': 'Yaprakları ıslatmadan sulama yapın', 'icon': Icons.water_drop_outlined},
      {'text': 'Bakırlı fungisitlerle önleyici ilaçlama yapın', 'icon': Icons.medical_services_outlined},
      {'text': 'Temiz tohum ve sağlıklı fidan kullanın', 'icon': Icons.local_florist_outlined},
    ],
    'Cercospora_leaf_spot Gray_leaf_spot': [
      {'text': 'Hastalıklı yaprakları temizleyin', 'icon': Icons.delete_outline},
      {'text': 'Dayanıklı çeşitler seçin', 'icon': Icons.eco_outlined},
      {'text': 'Uygun fungisitlerle ilaçlama yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Septoria_leaf_spot': [
      {'text': 'Alt yaprakları düzenli temizleyin', 'icon': Icons.cleaning_services_outlined},
      {'text': 'Yaprakları ıslatmadan sulama yapın', 'icon': Icons.water_drop_outlined},
      {'text': 'Fungisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Target_Spot': [
      {'text': 'Hastalıklı yaprakları toplayın ve imha edin', 'icon': Icons.delete_outline},
      {'text': 'Havalandırmayı artırın', 'icon': Icons.air_outlined},
      {'text': 'Uygun fungisitlerle kültürel önlemler alın', 'icon': Icons.medical_services_outlined},
    ],
    'Leaf_blight_(Isariopsis_Leaf_Spot)': [
      {'text': 'Kahverengi lekeli yaprakları temizleyin', 'icon': Icons.cleaning_services_outlined},
      {'text': 'Fungisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Cedar_apple_rust': [
      {'text': 'Alternatif konakları (sedir/ardıç) uzaklaştırın', 'icon': Icons.remove_circle_outline},
      {'text': 'Havalandırmayı artırın', 'icon': Icons.air_outlined},
      {'text': 'Fungisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Common_rust': [
      {'text': 'Dayanıklı çeşitler seçin', 'icon': Icons.eco_outlined},
      {'text': 'Kültürel önlemler alın', 'icon': Icons.agriculture_outlined},
      {'text': 'Fungisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Powdery_mildew': [
      {'text': 'Hava sirkülasyonunu artırın, bitkiler arası mesafe bırakın', 'icon': Icons.air_outlined},
      {'text': 'Sabah erken saatlerde sulama yapın', 'icon': Icons.wb_sunny_outlined},
      {'text': 'Kükürtlü fungisitler kullanın', 'icon': Icons.medical_services_outlined},
      {'text': 'Hastalıklı yaprakları temizleyin', 'icon': Icons.delete_outline},
    ],
    'Leaf_Mold': [
      {'text': 'Havalandırmayı artırın', 'icon': Icons.air_outlined},
      {'text': 'Nem oranını düşürün', 'icon': Icons.water_drop_outlined},
      {'text': 'Fungisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Apple_scab': [
      {'text': 'Hastalıklı yaprak ve meyveleri temizleyin', 'icon': Icons.cleaning_services_outlined},
      {'text': 'Havalandırmayı iyileştirin', 'icon': Icons.air_outlined},
      {'text': 'Fungisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
    ],
    'Tomato_mosaic_virus': [
      {'text': 'Hastalıklı bitkileri hemen uzaklaştırın', 'icon': Icons.remove_circle_outline},
      {'text': 'Alet sterilizasyonu yapın', 'icon': Icons.cleaning_services_outlined},
      {'text': 'Vektör kontrolü yapın', 'icon': Icons.bug_report_outlined},
      {'text': 'Temiz tohum kullanın', 'icon': Icons.local_florist_outlined},
    ],
    'Tomato_Yellow_Leaf_Curl_Virus': [
      {'text': 'Beyaz sinek mücadelesi yapın', 'icon': Icons.bug_report_outlined},
      {'text': 'Dayanıklı çeşitler seçin', 'icon': Icons.eco_outlined},
      {'text': 'Hastalıklı bitkileri imha edin', 'icon': Icons.delete_outline},
    ],
    'Spider_mites Two-spotted_spider_mite': [
      {'text': 'Yaprakları düzenli su ile yıkayın', 'icon': Icons.water_drop_outlined},
      {'text': 'Akarisit uygulamaları yapın', 'icon': Icons.medical_services_outlined},
      {'text': 'Biyolojik kontrol yöntemleri kullanın', 'icon': Icons.eco_outlined},
      {'text': 'Nem oranını artırın', 'icon': Icons.water_drop_outlined},
    ],
    'Leaf_scorch': [
      {'text': 'Su yönetimini düzenleyin', 'icon': Icons.water_drop_outlined},
      {'text': 'Dayanıklı çeşitler seçin', 'icon': Icons.eco_outlined},
      {'text': 'Güneş ışığına maruziyeti kontrol edin', 'icon': Icons.wb_sunny_outlined},
    ],
    'Esca_(Black_Measles)': [
      {'text': 'Sağlıklı fidan kullanın', 'icon': Icons.local_florist_outlined},
      {'text': 'Dikkatli budama yapın, yaraları kapatın', 'icon': Icons.content_cut},
      {'text': 'Aşırı sulamadan kaçının', 'icon': Icons.water_drop_outlined},
    ],
    'Haunglongbing_(Citrus_greening)': [
      {'text': 'Hastalıklı ağaçları sökün', 'icon': Icons.remove_circle_outline},
      {'text': 'Asya turunçgil psillidi mücadelesi yapın', 'icon': Icons.bug_report_outlined},
      {'text': 'Sağlıklı fidan kullanın', 'icon': Icons.local_florist_outlined},
    ],
  };

  // Hastalık açıklamaları (Türkçe tarım literatürü bazlı)
  static const Map<String, String> _diseaseDescriptions = {
    'Apple_scab': 'Elma kabuğu, elma ağaçlarında yapraklarda ve meyvelerde kahverengi-siyah lekeler oluşturan mantar hastalığıdır. Nemli ve serin havalarda yayılır.',
    'Black_rot': 'Siyah çürüklük, elma ve üzüm bitkilerinde meyvelerde ve yapraklarda siyah çürük alanlar oluşturan ciddi bir hastalıktır.',
    'Cedar_apple_rust': 'Sedir elma pası, elma ağaçlarında turuncu-kahverengi pas benzeri yapılar oluşturan mantar enfeksiyonudur. Sedir ağaçlarından bulaşır.',
    'Powdery_mildew': 'Külleme, bitki yapraklarında beyaz toz benzeri bir tabaka oluşturan mantar hastalığıdır. Kiraz ve kabak bitkilerinde yaygındır.',
    'Cercospora_leaf_spot Gray_leaf_spot': 'Cercospora yaprak lekesi, mısır bitkilerinde yapraklarda gri-kahverengi lekeler oluşturan hastalıktır.',
    'Common_rust': 'Yaygın pas, mısır bitkilerinde yapraklarda turuncu-kırmızı pas benzeri yapılar oluşturan mantar hastalığıdır.',
    'Esca_(Black_Measles)': 'Esca (Siyah Kızamık), üzüm asmalarında yapraklarda siyah noktalar ve çürüme ile karakterize ciddi bir hastalıktır.',
    'Leaf_blight_(Isariopsis_Leaf_Spot)': 'Isariopsis yaprak yanıklığı, üzüm bitkilerinde yapraklarda kahverengi lekeler ve yanıklık oluşturur.',
    'Haunglongbing_(Citrus_greening)': 'Huanglongbing (Turunçgil Yeşillenmesi), portakal ağaçlarında yaprakların sararması ve meyvelerin küçük kalmasına neden olan ciddi bir hastalıktır.',
    'Bacterial_spot': 'Bakteriyel leke, domates, şeftali ve biber bitkilerinde yapraklarda ve meyvelerde siyah lekeler oluşturan bakteriyel hastalıktır.',
    'Early_blight': 'Erken yanıklık, domates ve patates bitkilerinde yapraklarda halka şeklinde kahverengi lekeler oluşturan yaygın bir hastalıktır.',
    'Late_blight': 'Geç yanıklık, domates ve patates bitkilerinde yapraklarda ve meyvelerde hızlı çürümeye neden olan ciddi bir hastalıktır.',
    'Leaf_Mold': 'Yaprak küfü, domates bitkilerinde yaprakların alt yüzeyinde yeşil-sarı küf oluşturan nemli koşullarda görülen hastalıktır.',
    'Septoria_leaf_spot': 'Septoria yaprak lekesi, domates bitkilerinde yapraklarda küçük kahverengi lekeler ve delikler oluşturan yaygın bir hastalıktır.',
    'Spider_mites Two-spotted_spider_mite': 'İki noktalı kırmızı örümcek, domates bitkilerinde yapraklarda sararma ve kurumaya neden olan zararlıdır.',
    'Target_Spot': 'Hedef leke, domates bitkilerinde yapraklarda hedef tahtası benzeri lekeler oluşturan hastalıktır.',
    'Tomato_mosaic_virus': 'Domates mozaik virüsü, domates bitkilerinde yapraklarda mozaik desenleri ve büyüme geriliğine neden olan viral hastalıktır.',
    'Tomato_Yellow_Leaf_Curl_Virus': 'Domates sarı yaprak kıvırcık virüsü, domates bitkilerinde yaprakların sararması ve kıvrılmasına neden olan ciddi bir viral hastalıktır.',
    'Leaf_scorch': 'Yaprak yanması, çilek bitkilerinde yaprak kenarlarında kuruma ve kahverengileşme ile karakterize bir hastalıktır.',
  };

  @override
  Widget build(BuildContext context) {
    // Genel hastalık isimlerini unique olarak al (her genel isimden bir tane)
    final uniqueGeneralNames = <String>{};
    final generalDiseaseMap = <String, String>{}; // genel isim -> ilk hastalık key'i
    
    for (var disease in _plantVillageDiseaseTranslations.entries) {
      final generalName = _generalDiseaseNames[disease.key] ?? disease.value;
      if (!uniqueGeneralNames.contains(generalName)) {
        uniqueGeneralNames.add(generalName);
        generalDiseaseMap[generalName] = disease.key;
      }
    }

    final generalDiseases = uniqueGeneralNames.toList()..sort();

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        // Grid layout ile genel hastalık kartları
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: generalDiseases.length,
          itemBuilder: (context, index) {
            final generalName = generalDiseases[index];
            final diseaseKey = generalDiseaseMap[generalName] ?? '';
            final description = _diseaseDescriptions[diseaseKey] ?? 'Bu hastalık hakkında bilgi mevcut değil.';
            
            return _DiseaseGridCard(
              diseaseName: generalName,
              description: description,
              imagePath: _getDiseaseImagePath(diseaseKey),
              diseaseKey: diseaseKey,
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _getDiseaseImagePath(String diseaseKey) {
    // Genel hastalık ismine göre dosya adı
    final generalName = _generalDiseaseNames[diseaseKey] ?? diseaseKey;
    // Türkçe karakterleri değiştir ve küçük harfe çevir
    final imageName = generalName
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(' ', '_');
    
    // Fotoğraf dosya uzantılarını kontrol et (jpg, png)
    // Bazı fotoğraflar png formatında (Pas, Külleme, Turunçgil Yeşillenmesi)
    final imageMap = {
      'yaniklik': 'assets/images/diseases/yaniklik.jpg',
      'siyah_curukluk': 'assets/images/diseases/siyah_curukluk.jpg',
      'bakteriyel_leke': 'assets/images/diseases/bakteriyel_leke.jpg',
      'yaprak_lekesi': 'assets/images/diseases/yaprak_lekesi.jpg',
      'pas': 'assets/images/diseases/pas.png',
      'kulleme': 'assets/images/diseases/kulleme.png',
      'yaprak_kufu': 'assets/images/diseases/yaprak_kufu.jpg',
      'uyuz': 'assets/images/diseases/uyuz.jpg',
      'mozaik_virusu': 'assets/images/diseases/mozaik_virusu.jpg',
      'yaprak_kivircik_virusu': 'assets/images/diseases/yaprak_kivircik_virusu.jpg',
      'kirmizi_orumcek': 'assets/images/diseases/kirmizi_orumcek.jpg',
      'yaprak_yanmasi': 'assets/images/diseases/yaprak_yanmasi.jpg',
      'esca': 'assets/images/diseases/esca.jpg',
      'turuncgil_yesillenmesi': 'assets/images/diseases/turuncgil_yesillenmesi.png',
    };
    
    return imageMap[imageName] ?? 'assets/images/diseases/$imageName.jpg';
  }
}

class _DiseaseGridCard extends StatelessWidget {
  const _DiseaseGridCard({
    required this.diseaseName,
    required this.description,
    required this.imagePath,
    required this.diseaseKey,
  });

  final String diseaseName;
  final String description;
  final String imagePath;
  final String diseaseKey;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDiseaseDetail(context, diseaseName, description, imagePath, diseaseKey),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Fotoğraf bulunamazsa placeholder göster
                  return Container(
                    color: AppColors.surface,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.eco_outlined,
                            color: AppColors.primary.withOpacity(0.3),
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fotoğraf yükleniyor...',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Gradient overlay for text readability
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
              ),
              // Text content overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diseaseName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getCategorySubtitle(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategorySubtitle() {
    // Hastalık kategorisine göre alt başlık
    if (diseaseName.contains('Virüs') || diseaseName.contains('Mozaik')) {
      return 'Viral hastalık';
    } else if (diseaseName.contains('Bakteri')) {
      return 'Bakteriyel hastalık';
    } else if (diseaseName.contains('Kırmızı Örümcek')) {
      return 'Zararlı';
    } else if (diseaseName.contains('Yanıklık') || diseaseName.contains('Çürüklük') || 
               diseaseName.contains('Lekesi') || diseaseName.contains('Pas') || 
               diseaseName.contains('Külleme') || diseaseName.contains('Küfü') || 
               diseaseName.contains('Uyuz') || diseaseName.contains('Esca')) {
      return 'Mantar hastalığı';
    } else {
      return 'Bitki hastalığı';
    }
  }

  void _showDiseaseDetail(BuildContext context, String name, String description, String imagePath, String diseaseKey) {
    // Bakım önerilerini al
    final recommendations = _CommonIssuesContent._careRecommendations[diseaseKey] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Image
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            imagePath,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.surface,
                                child: const Icon(
                                  Icons.image_outlined,
                                  color: AppColors.textTertiary,
                                  size: 48,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Description
                      Text(
                        'Açıklama',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.6,
                            ),
                      ),
                      // Bakım Önerileri
                      if (recommendations.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Text(
                          'Bakım Önerileri',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 16),
                        ...recommendations.map((rec) => _CareRecommendationItem(
                              text: rec['text'] as String,
                              icon: rec['icon'] as IconData,
                            )).toList(),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _CareRecommendationItem extends StatelessWidget {
  const _CareRecommendationItem({
    required this.text,
    required this.icon,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
