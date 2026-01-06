import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/app_theme.dart';
import 'plant_scan_page.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../core/config.dart';
import 'package:intl/intl.dart';

class PlantDetailPage extends StatefulWidget {
  final Map<String, dynamic> plant;
  final int initialTab;

  const PlantDetailPage({super.key, required this.plant, this.initialTab = 0});

  @override
  State<PlantDetailPage> createState() => _PlantDetailPageState();
}

class _PlantDetailPageState extends State<PlantDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _analysisHistory = [];
  bool _isLoading = true;
  Map<String, dynamic>? _currentAnalysisResult;
  bool _analyzing = false;
  final ImagePicker _picker = ImagePicker();
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();
  
  // Bildirim durumları
  Map<String, dynamic>? _wateringNotificationSettings;
  Map<String, dynamic>? _fertilizationNotificationSettings;
  
  // Son sulama ve gübreleme tarihleri
  DateTime? _lastWateringDate;
  DateTime? _lastFertilizationDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _loadPlantData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPlantData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final plantId = widget.plant['id'] as String;
      
      // Analiz geçmişini yükle
      final historyJson = prefs.getString('plant_analysis_history_$plantId') ?? '[]';
      final history = List<Map<String, dynamic>>.from(
        jsonDecode(historyJson) as List
      );
      
      // Bildirim ayarlarını yükle
      final wateringSettings = await _notificationService.getNotificationSettings(plantId, 'watering');
      final fertilizationSettings = await _notificationService.getNotificationSettings(plantId, 'fertilization');
      
      // Son sulama ve gübreleme tarihlerini yükle
      final lastWateringStr = prefs.getString('last_watering_$plantId');
      final lastFertilizationStr = prefs.getString('last_fertilization_$plantId');
      
      setState(() {
        _analysisHistory = history;
        // En son analiz sonucunu al
        if (_analysisHistory.isNotEmpty) {
          _currentAnalysisResult = _analysisHistory.first;
        }
        _wateringNotificationSettings = wateringSettings;
        _fertilizationNotificationSettings = fertilizationSettings;
        _lastWateringDate = lastWateringStr != null ? DateTime.parse(lastWateringStr) : null;
        _lastFertilizationDate = lastFertilizationStr != null ? DateTime.parse(lastFertilizationStr) : null;
        _isLoading = false;
      });
      
      // Debug: Ayarları kontrol et
      print('📋 Yüklenen ayarlar:');
      print('   Sulama: ${wateringSettings != null ? "Var (enabled: ${wateringSettings['enabled']})" : "Yok"}');
      print('   Gübreleme: ${fertilizationSettings != null ? "Var (enabled: ${fertilizationSettings['enabled']})" : "Yok"}');
      print('   Son sulama: $_lastWateringDate');
      print('   Son gübreleme: $_lastFertilizationDate');
    } catch (e) {
      print('❌ Plant data yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addNewPhoto() async {
    // Kullanıcıya kamera veya galeri seçeneği sun
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                title: const Text('Kamera ile Çek'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.primary),
                title: const Text('Galeriden Seç'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (source == null) return; // Kullanıcı iptal etti

    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image == null) return;

      setState(() => _analyzing = true);

      // Fotoğrafı Uint8List'e çevir
      final imageBytes = await image.readAsBytes();

      // Fotoğrafı analiz et
      final result = await _apiService.analyzePlant(
        imageBytes: Uint8List.fromList(imageBytes),
        model: 'plantvillage',
      );
      
      if (result != null) {
        // Analiz sonucunu geçmişe ekle
        final plantId = widget.plant['id'] as String;
        final analysisEntry = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'imagePath': image.path,
          'analysisResult': result,
          'date': DateTime.now().toIso8601String(),
        };

        final prefs = await SharedPreferences.getInstance();
        final historyJson = prefs.getString('plant_analysis_history_$plantId') ?? '[]';
        final history = List<Map<String, dynamic>>.from(
          jsonDecode(historyJson) as List
        );
        
        history.insert(0, analysisEntry);
        await prefs.setString('plant_analysis_history_$plantId', jsonEncode(history));

        // Bitki bilgilerini güncelle (son analiz sonucuna göre)
        await _updatePlantStatus(result, image.path);

        setState(() {
          _analysisHistory = history;
          _currentAnalysisResult = result;
          _analyzing = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Analiz tamamlandı!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        setState(() => _analyzing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Analiz başarısız oldu'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _analyzing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updatePlantStatus(Map<String, dynamic> analysisResult, String imagePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPlantsJson = prefs.getString('saved_plants') ?? '[]';
      final savedPlants = List<Map<String, dynamic>>.from(
        jsonDecode(savedPlantsJson) as List
      );

      final plantId = widget.plant['id'] as String;
      final plantIndex = savedPlants.indexWhere((p) => p['id'] == plantId);
      
      if (plantIndex != -1) {
        // Analiz sonucundan bitki bilgilerini çıkar
        final result = Map<String, dynamic>.from(analysisResult);
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
        String? turkishDisease;

        if (alternatives.isNotEmpty) {
          rawClassName = alternatives.first['class_name']?.toString();
          if (rawClassName != null && rawClassName.contains('___')) {
            final parts = rawClassName.split('___');
            var rawPlantType = parts[0];
            
            if (rawPlantType.contains('(')) {
              rawPlantType = rawPlantType.split('(')[0].trim();
            }
            rawPlantType = rawPlantType.replaceAll(RegExp(r'_+$'), '').trim();
            
            final rawDiseaseOrStatus = parts.length > 1 ? parts[1] : '';
            var normalizedDisease = rawDiseaseOrStatus.replaceAll(RegExp(r'_+$'), '').trim();
            plantType = _plantTypeTranslations[rawPlantType] ?? rawPlantType;
            isHealthy = normalizedDisease.toLowerCase() == 'healthy';

            if (!isHealthy) {
              var diseaseKey = normalizedDisease;
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
        }

        // Bitki bilgilerini güncelle (nickname'i koru!)
        final currentNickname = savedPlants[plantIndex]['name'] as String?; // Mevcut nickname'i koru
        final turkishPlantType = plantType ?? savedPlants[plantIndex]['originalPlantType'] as String? ?? savedPlants[plantIndex]['plantType'] as String?;
        
        savedPlants[plantIndex] = {
          ...savedPlants[plantIndex],
          'name': currentNickname, // Nickname'i koru, değiştirme!
          'originalPlantType': turkishPlantType, // Bitki türünü güncelle
          'plantType': plantType ?? savedPlants[plantIndex]['plantType'], // Orijinal plantType'ı da güncelle
          'isHealthy': isHealthy,
          'disease': turkishDisease ?? '',
          'imagePath': imagePath,
          'lastAnalysisDate': DateTime.now().toIso8601String(),
        };

        await prefs.setString('saved_plants', jsonEncode(savedPlants));
      }
    } catch (e) {
      // Hata durumunda sessizce devam et
    }
  }

  void _showAnalysisResult(Map<String, dynamic> entry) {
    // Entry'den analysisResult'ı al
    final analysisResult = entry['analysisResult'] as Map<String, dynamic>?;
    if (analysisResult == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: _buildAnalysisResultCard(analysisResult),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisResultCard(Map<String, dynamic> result) {
    // plant_scan_page.dart'taki _buildAnalysisResultCard ile aynı mantık
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
    
    // Bitki türü ve sağlık durumunu belirle
    String? plantType;
    bool isHealthy = false;
    String? rawClassName;
    
    if (alternatives.isNotEmpty) {
      rawClassName = alternatives.first['class_name']?.toString();
      if (rawClassName != null && rawClassName.contains('___')) {
        final parts = rawClassName.split('___');
        var rawPlantType = parts[0];
        if (rawPlantType.contains('(')) {
          rawPlantType = rawPlantType.split('(')[0].trim();
        }
        rawPlantType = rawPlantType.replaceAll(RegExp(r'_+$'), '').trim();
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
        if (rawPlantType.contains('(')) {
          rawPlantType = rawPlantType.split('(')[0].trim();
        }
        rawPlantType = rawPlantType.replaceAll(RegExp(r'_+$'), '').trim();
        final rawDiseaseOrStatus = parts.length > 1 ? parts[1] : '';
        var normalizedDisease = rawDiseaseOrStatus.replaceAll(RegExp(r'_+$'), '').trim();
        if (plantType == null) {
          plantType = _plantTypeTranslations[rawPlantType] ?? rawPlantType;
        }
        isHealthy = normalizedDisease.toLowerCase() == 'healthy';
      }
    }
    
    // Türkçe display name oluştur
    final turkishDisplayName = _getTurkishDisplayName(rawClassName, plantType, isHealthy);
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
        ],
      ),
    );
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
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  String _getTurkishDisplayName(String? rawClassName, String? plantType, bool isHealthy) {
    if (rawClassName == null || rawClassName.isEmpty) {
      return 'Bilinmiyor';
    }
    
    String turkishPlantType = plantType ?? 'Bilinmeyen Bitki';
    
    if (isHealthy) {
      return turkishPlantType;
    }
    
    if (rawClassName.contains('___')) {
      final parts = rawClassName.split('___');
      if (parts.length >= 2) {
        var diseaseKey = parts[1];
        diseaseKey = diseaseKey.replaceAll(RegExp(r'_+$'), '').trim();
        
        String turkishDisease = _plantVillageDiseaseTranslations[diseaseKey] ?? '';
        
        if (turkishDisease.isEmpty) {
          turkishDisease = _plantVillageDiseaseTranslations[diseaseKey.toLowerCase()] ?? '';
        }
        
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
        
        return '$turkishPlantType • $turkishDisease';
      }
    }
    
    return '$turkishPlantType • ${_prettifyClassName(rawClassName)}';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('d MMMM yyyy', 'tr_TR').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Header'da nickname göster, ama işlevler için bitki türünü kullan
    final nickname = widget.plant['name'] as String? ?? 'Bilinmeyen Bitki';
    final plantName = widget.plant['originalPlantType'] as String? ?? 
                      widget.plant['plantType'] as String? ?? 
                      nickname; // Gerçek bitki türü
    final savedAt = widget.plant['savedAt'] as String?;
    final currentImagePath = _currentAnalysisResult?['imagePath'] as String? ?? 
                            widget.plant['imagePath'] as String?;
    final isHealthy = _currentAnalysisResult != null
        ? (_currentAnalysisResult!['analysisResult']?['health_label'] == 'Sağlıklı')
        : (widget.plant['isHealthy'] as bool? ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // App Bar
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: AppColors.cardBackground,
                  iconTheme: const IconThemeData(color: Colors.white),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      nickname, // Header'da nickname göster
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    background: currentImagePath != null && File(currentImagePath).existsSync()
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(currentImagePath),
                                fit: BoxFit.cover,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.7),
                                      Colors.black.withOpacity(0.3),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Container(
                            color: AppColors.primary.withOpacity(0.1),
                            child: const Icon(
                              Icons.eco_outlined,
                              size: 80,
                              color: AppColors.primary,
                            ),
                          ),
                  ),
                ),
                // Content
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(
                              savedAt != null ? _formatDate(savedAt) : 'Tarih bilgisi yok',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      // Tabs
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Notlar'),
                          Tab(text: 'Bakım'),
                          Tab(text: 'Bitki Bilgisi'),
                        ],
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.textSecondary,
                        indicatorColor: AppColors.primary,
                      ),
                      // Tab Content
                      SizedBox(
                        height: MediaQuery.of(context).size.height - 400,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildNotesTab(),
                            _buildCareTab(),
                            _buildInfoTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildNotesTab() {
    return Column(
      children: [
        // Scrollable timeline
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPlantData,
            backgroundColor: AppColors.cardBackground,
            color: AppColors.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(16),
              children: [
                // Current Status Card (en üstte, sadece analiz sonucu varsa)
                if (_currentAnalysisResult != null && _currentAnalysisResult!['analysisResult'] != null)
                  _buildStatusCard(_currentAnalysisResult!, isFirst: true),
                // History (tüm timeline)
                ..._analysisHistory.map((entry) {
                  // İlk entry'yi atla çünkü zaten yukarıda gösterildi
                  if (entry == _currentAnalysisResult && _currentAnalysisResult!['analysisResult'] != null) {
                    return const SizedBox.shrink();
                  }
                  return _buildStatusCard(entry);
                }),
                // Bottom padding for fixed buttons
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        // Fixed buttons at bottom
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            border: Border(
              top: BorderSide(color: AppColors.border, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.camera_alt,
                  label: 'Yeni Fotoğraf',
                  onPressed: _addNewPhoto,
                  isLoading: _analyzing,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.psychology,
                  label: 'Yapay Zeka',
                  onPressed: _openAIChat,
                  isLoading: false,
                  isAI: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> entry, {bool isFirst = false}) {
    final entryType = entry['type'] as String?;
    
    // AI Sohbet kaydı
    if (entryType == 'ai_chat') {
      return _buildChatCard(entry, isFirst: isFirst);
    }
    
    final imagePath = entry['imagePath'] as String?;
    final analysisResult = entry['analysisResult'] as Map<String, dynamic>?;
    final date = entry['date'] as String?;
    
    if (analysisResult == null) {
      // Bitki eklendi kartı
      return _buildPlantAddedCard(entry);
    }

    final healthLabel = analysisResult['health_label'] as String? ?? '';
    final isHealthy = healthLabel.toLowerCase().contains('sağlıklı') || 
                     healthLabel.toLowerCase().contains('healthy');
    final borderColor = isHealthy ? AppColors.success : AppColors.danger;
    final statusText = isHealthy ? 'sağlıklı' : 'hasta';
    final statusColor = isHealthy ? AppColors.success : AppColors.danger;

    return Container(
      margin: EdgeInsets.only(bottom: isFirst ? 16 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              if (imagePath != null && File(imagePath).existsSync())
                Container(
                  width: 80,
                  height: 80,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              // Status Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyLarge,
                        children: [
                          const TextSpan(text: 'Bu bitki '),
                          TextSpan(
                            text: statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: ' görünüyor!'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _showAnalysisResult(entry),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: borderColor),
                        foregroundColor: borderColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Kontrol Et'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(Map<String, dynamic> entry, {bool isFirst = false}) {
    final date = entry['date'] as String?;
    final messages = entry['messages'] as List<dynamic>? ?? [];
    final previewText = messages.isNotEmpty 
        ? (messages.first['content'] as String? ?? 'Sohbet başladı')
        : 'Sohbet kaydı';
    
    return Container(
      margin: EdgeInsets.only(bottom: isFirst ? 16 : 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Icon(Icons.access_time, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    _formatDate(date),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI Icon
              Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Image.asset(
                  'assets/icon/ai.png',
                  width: 40,
                  height: 40,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.psychology,
                      color: AppColors.primary,
                      size: 40,
                    );
                  },
                ),
              ),
              // Chat Preview
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'AI Sohbeti',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      previewText.length > 60 ? '${previewText.substring(0, 60)}...' : previewText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _showChatHistory(entry),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Sohbeti Gör'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showChatHistory(Map<String, dynamic> chatEntry) {
    final messages = chatEntry['messages'] as List<dynamic>? ?? [];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
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
                      'Kaydedilen Sohbet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Messages
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index] as Map<String, dynamic>;
                    final isUser = message['role'] == 'user';
                    return _buildMessageBubble(message, isUser);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: isUser
            ? Text(
                message['content'] as String? ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
              )
            : MarkdownBody(
                data: message['content'] as String? ?? '',
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                  strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  listBullet: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                  h1: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  h2: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  h3: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
      ),
    );
  }

  Widget _buildPlantAddedCard(Map<String, dynamic> entry) {
    final imagePath = entry['imagePath'] as String? ?? widget.plant['imagePath'] as String?;
    final date = widget.plant['savedAt'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bitki eklendi',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (imagePath != null && File(imagePath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(imagePath),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isLoading,
    bool isAI = false,
  }) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isAI ? AppColors.primary.withOpacity(0.15) : AppColors.primary,
        foregroundColor: isAI ? AppColors.primary : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isAI ? AppColors.primary : Colors.transparent,
            width: isAI ? 2 : 1.5,
          ),
        ),
        elevation: 0,
      ),
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                isAI
                    ? Image.asset(
                        'assets/icon/ai.png',
                        width: 28,
                        height: 28,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(icon, size: 28, color: AppColors.primary);
                        },
                      )
                    : Icon(icon, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isAI ? AppColors.primary : Colors.white,
                        fontSize: isAI ? 15 : null,
                      ),
                ),
              ],
            ),
    );
  }

  void _openAIChat() {
    // Kaydedilmiş sohbetleri kontrol et
    final savedChats = _analysisHistory.where((entry) => entry['type'] == 'ai_chat').toList();
    
    if (savedChats.isNotEmpty) {
      // Kaydedilmiş sohbetler varsa, önce onları göster
      _showChatHistoryDialog(savedChats);
    } else {
      // Yeni sohbet başlat
      _startNewChat();
    }
  }

  void _showChatHistoryDialog(List<Map<String, dynamic>> savedChats) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
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
                      'Sohbet Geçmişi',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Chat List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: savedChats.length + 1, // +1 for "Yeni Sohbet" button
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Yeni Sohbet butonu
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _startNewChat();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Yeni Sohbet Başlat'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      );
                    }
                    final chat = savedChats[index - 1];
                    return _buildChatListItem(chat);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatListItem(Map<String, dynamic> chat) {
    final date = chat['date'] as String?;
    final messages = chat['messages'] as List<dynamic>? ?? [];
    final previewText = messages.isNotEmpty 
        ? (messages.first['content'] as String? ?? 'Sohbet başladı')
        : 'Sohbet kaydı';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.border),
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.asset(
            'assets/icon/ai.png',
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.psychology,
                color: AppColors.primary,
                size: 24,
              );
            },
          ),
        ),
        title: Text(
          date != null ? _formatDate(date) : 'Sohbet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(
          previewText.length > 50 ? '${previewText.substring(0, 50)}...' : previewText,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: () {
          Navigator.of(context).pop();
          _showChatHistory(chat);
        },
      ),
    );
  }

  void _startNewChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _AIChatSheet(
          plant: widget.plant,
          analysisHistory: _analysisHistory,
          currentAnalysisResult: _currentAnalysisResult,
        ),
      ),
    ).then((value) {
      // Sohbet kaydedildiyse listeyi yenile
      if (value == true) {
        _loadPlantData();
      }
    });
  }

  Widget _buildCareTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Sulama kartı
          _buildCareItemCard(
            icon: Icons.water_drop, // IconData olarak kalacak ama widget'ta Image.asset kullanılacak
            iconAsset: 'assets/images/Sulamak.png',
            title: 'Su',
            subtitle: _getCareSubtitle('watering'),
            isDue: _isCareActionDue('watering'),
            onTap: () => _showCareActionConfirmation('watering'),
            onSettingsTap: () => _showCareSettingsModal('watering'),
          ),
          const SizedBox(height: 12),
          // Gübreleme kartı
          _buildCareItemCard(
            icon: Icons.eco, // IconData olarak kalacak ama widget'ta Image.asset kullanılacak
            iconAsset: 'assets/images/Gübrelemek.png',
            title: 'Gübre',
            subtitle: _getCareSubtitle('fertilization'),
            isDue: _isCareActionDue('fertilization'),
            onTap: () => _showCareActionConfirmation('fertilization'),
            onSettingsTap: () => _showCareSettingsModal('fertilization'),
          ),
        ],
      ),
    );
  }

  String _getCareSubtitle(String type) {
    final settings = type == 'watering' 
        ? _wateringNotificationSettings 
        : _fertilizationNotificationSettings;
    
    final lastDate = type == 'watering' 
        ? _lastWateringDate 
        : _lastFertilizationDate;
    
    // Eğer ayar yoksa
    if (settings == null || settings['enabled'] != true) {
      return 'Ayarlanmadı';
    }

    try {
      final repeatValue = settings['repeatValue'] as int? ?? 13;
      final repeatUnit = settings['repeatUnit'] as String? ?? 'days';
      
      final now = DateTime.now();
      final nowDate = DateTime(now.year, now.month, now.day);
      
      // Eğer henüz işlem yapılmamışsa, bugünden itibaren hesapla
      final baseDate = lastDate ?? now;
      final baseDateOnly = DateTime(baseDate.year, baseDate.month, baseDate.day);
      
      DateTime nextDate;
      if (repeatUnit == 'weeks') {
        nextDate = baseDate.add(Duration(days: repeatValue * 7));
      } else if (repeatUnit == 'months') {
        nextDate = DateTime(baseDate.year, baseDate.month + repeatValue, baseDate.day);
      } else {
        nextDate = baseDate.add(Duration(days: repeatValue));
      }
      
      // Sadece tarih kısmını karşılaştır (saat önemli değil)
      final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
      final difference = nextDateOnly.difference(nowDate).inDays;
      
      // Eğer bugün zaten yapıldıysa, bir sonraki tarihi göster
      if (lastDate != null && baseDateOnly.isAtSameMomentAs(nowDate)) {
        // Bugün yapıldı, bir sonraki tarihi göster
        if (difference <= 0) {
          // Bir sonraki tarih bugün veya geçmişte, bu durumda tekrar hesapla
          // (Bu durum normalde olmamalı ama güvenlik için)
          return 'Yarın';
        } else if (difference == 1) {
          return 'Yarın';
        } else {
          return '$difference gün sonra';
        }
      }
      
      if (difference < 0) {
        return 'Sulanması gerekiyor';
      } else if (difference == 0) {
        // Bugünse bildirim zamanını kontrol et
        final reminderTimeStr = settings['reminderTime'] as String?;
        if (reminderTimeStr != null) {
          final parts = reminderTimeStr.split(':');
          final reminderHour = int.parse(parts[0]);
          final reminderMinute = int.parse(parts[1]);
          final now = DateTime.now();
          
          if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
            return 'Sulanması gerekiyor';
          } else {
            return 'Bugün';
          }
        }
        return 'Bugün';
      } else if (difference == 1) {
        return 'Yarın';
      } else {
        return '$difference gün sonra';
      }
    } catch (e) {
      print('❌ _getCareSubtitle hatası: $e');
      return 'Ayarlanmadı';
    }
  }

  bool _isCareActionDue(String type) {
    final settings = type == 'watering' 
        ? _wateringNotificationSettings 
        : _fertilizationNotificationSettings;
    
    final lastDate = type == 'watering' 
        ? _lastWateringDate 
        : _lastFertilizationDate;
    
    if (settings == null || settings['enabled'] != true) {
      return false;
    }

    try {
      final repeatValue = settings['repeatValue'] as int? ?? 13;
      final repeatUnit = settings['repeatUnit'] as String? ?? 'days';
      final reminderTimeStr = settings['reminderTime'] as String?;
      
      final now = DateTime.now();
      final nowDate = DateTime(now.year, now.month, now.day);
      
      // Eğer henüz işlem yapılmamışsa, bildirim zamanı geldiyse true döndür
      if (lastDate == null) {
        // Bildirim zamanını kontrol et
        if (reminderTimeStr != null) {
          final parts = reminderTimeStr.split(':');
          final reminderHour = int.parse(parts[0]);
          final reminderMinute = int.parse(parts[1]);
          
          // Bugün bildirim zamanı geçtiyse veya şu an bildirim zamanıysa
          if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
            return true;
          }
        }
        return false;
      }
      
      // Son işlem tarihinden itibaren bir sonraki tarihi hesapla
      DateTime nextDate;
      if (repeatUnit == 'weeks') {
        nextDate = lastDate.add(Duration(days: repeatValue * 7));
      } else if (repeatUnit == 'months') {
        nextDate = DateTime(lastDate.year, lastDate.month + repeatValue, lastDate.day);
      } else {
        nextDate = lastDate.add(Duration(days: repeatValue));
      }
      
      // Bildirim zamanını ekle
      if (reminderTimeStr != null) {
        final parts = reminderTimeStr.split(':');
        final reminderHour = int.parse(parts[0]);
        final reminderMinute = int.parse(parts[1]);
        nextDate = DateTime(nextDate.year, nextDate.month, nextDate.day, reminderHour, reminderMinute);
      }
      
      final nextDateOnly = DateTime(nextDate.year, nextDate.month, nextDate.day);
      
      // Eğer bugün yapıldıysa, bir sonraki tarihi kontrol et
      final lastDateOnly = DateTime(lastDate.year, lastDate.month, lastDate.day);
      if (lastDateOnly.isAtSameMomentAs(nowDate)) {
        // Bugün yapıldı, bir sonraki tarih henüz gelmedi
        return false;
      }
      
      // Bir sonraki tarih bugün veya geçmişteyse, bildirim zamanı geldi
      if (nextDateOnly.isBefore(nowDate) || nextDateOnly.isAtSameMomentAs(nowDate)) {
        // Bildirim zamanını kontrol et
        if (reminderTimeStr != null) {
          final parts = reminderTimeStr.split(':');
          final reminderHour = int.parse(parts[0]);
          final reminderMinute = int.parse(parts[1]);
          
          // Bugünse ve bildirim zamanı geçtiyse veya şu an bildirim zamanıysa
          if (nextDateOnly.isAtSameMomentAs(nowDate)) {
            if (now.hour > reminderHour || (now.hour == reminderHour && now.minute >= reminderMinute)) {
              return true;
            }
          } else {
            // Geçmişteyse kesinlikle true
            return true;
          }
        } else {
          // Bildirim zamanı yoksa, tarih kontrolü yeterli
          return true;
        }
      }
      
      return false;
    } catch (e) {
      print('❌ _isCareActionDue hatası: $e');
      return false;
    }
  }

  Widget _buildCareItemCard({
    required IconData icon,
    String? iconAsset,
    required String title,
    required String subtitle,
    required bool isDue,
    required VoidCallback onTap,
    required VoidCallback onSettingsTap,
  }) {
    final isConfigured = subtitle != 'Ayarlanmadı';
    final iconColor = isDue ? Colors.red : AppColors.primary;
    final iconBgColor = isDue ? Colors.red.withOpacity(0.1) : AppColors.primary.withOpacity(0.1);
    
    return InkWell(
      onTap: isConfigured ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDue ? Colors.red.withOpacity(0.3) : AppColors.border,
            width: isDue ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (isDue)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            title == 'Su' ? 'Sulanması gerekiyor' : (title == 'Gübre' ? 'Gübrelenmesi gerekiyor' : 'Bakım gerekiyor'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isConfigured 
                          ? (isDue ? Colors.red : AppColors.primary)
                          : AppColors.textSecondary,
                      fontWeight: isConfigured ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: iconColor,
                  width: 2,
                ),
              ),
              child: iconAsset != null
                  ? Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        iconAsset,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(icon, color: iconColor, size: 24);
                        },
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: _ControlIcon(color: AppColors.textSecondary),
              onPressed: onSettingsTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  // Kontrol ikonu widget'ı (üç yatay çizgi ve her birinin sağında küçük daire)
  Widget _ControlIcon({required Color color, double size = 20}) {
    return SizedBox(
      width: size,
      height: size * 0.75,
      child: CustomPaint(
        painter: _ControlIconPainter(color: color),
      ),
    );
  }

  Future<void> _showCareActionConfirmation(String type) async {
    final isWatering = type == 'watering';
    final actionName = isWatering ? 'sulamak' : 'gübrelemek';
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$actionName istediğinize emin misiniz?'),
        content: Text('${widget.plant['name'] ?? 'Bitki'} bitkinizi ${actionName} istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _completeCareAction(type);
    }
  }

  Future<void> _completeCareAction(String type) async {
    final plantId = widget.plant['id'] as String;
    final plantName = widget.plant['name'] ?? 'Bitki';
    final isWatering = type == 'watering';
    final actionName = isWatering ? 'sulandı' : 'gübrelendi';
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      
      // Son işlem tarihini kaydet
      if (isWatering) {
        await prefs.setString('last_watering_$plantId', now.toIso8601String());
        setState(() {
          _lastWateringDate = now;
        });
        // Sulama geçmişine ekle
        await _addToCareHistory(plantId, 'watering', now);
      } else {
        await prefs.setString('last_fertilization_$plantId', now.toIso8601String());
        setState(() {
          _lastFertilizationDate = now;
        });
        // Gübreleme geçmişine ekle
        await _addToCareHistory(plantId, 'fertilization', now);
      }
      
      // Bir sonraki tarihi hesapla ve göster
      final settings = isWatering 
          ? _wateringNotificationSettings 
          : _fertilizationNotificationSettings;
      
      String nextDateText = '';
      if (settings != null && settings['enabled'] == true) {
        final repeatValue = settings['repeatValue'] as int? ?? 13;
        final repeatUnit = settings['repeatUnit'] as String? ?? 'days';
        
        DateTime nextDate;
        if (repeatUnit == 'weeks') {
          nextDate = now.add(Duration(days: repeatValue * 7));
        } else if (repeatUnit == 'months') {
          nextDate = DateTime(now.year, now.month + repeatValue, now.day);
        } else {
          nextDate = now.add(Duration(days: repeatValue));
        }
        
        nextDateText = '\nBir sonraki ${isWatering ? "sulama" : "gübreleme"}: ${DateFormat('d MMMM yyyy', 'tr_TR').format(nextDate)}';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$plantName bitkiniz $actionName!$nextDateText'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      // Bildirimleri yeniden planla
      if (settings != null && settings['enabled'] == true) {
        final reminderTimeStr = settings['reminderTime'] as String? ?? '18:00';
        final parts = reminderTimeStr.split(':');
        final reminderTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
        final repeatValue = settings['repeatValue'] as int? ?? 13;
        final repeatUnit = settings['repeatUnit'] as String? ?? 'days';
        
        // Bir sonraki tarihi hesapla
        DateTime nextScheduledDate;
        if (repeatUnit == 'weeks') {
          nextScheduledDate = now.add(Duration(days: repeatValue * 7));
        } else if (repeatUnit == 'months') {
          nextScheduledDate = DateTime(now.year, now.month + repeatValue, now.day);
        } else {
          nextScheduledDate = now.add(Duration(days: repeatValue));
        }
        
        if (isWatering) {
          final waterAmount = settings['waterAmount'] as String? ?? 'Orta';
          final howToWater = settings['howToWater'] as String? ?? 'Topraktan';
          await _notificationService.scheduleWateringNotification(
            plantId: plantId,
            plantName: plantName,
            scheduledDate: nextScheduledDate,
            reminderTime: reminderTime,
            repeatDays: repeatUnit == 'days' ? repeatValue : (repeatUnit == 'weeks' ? repeatValue * 7 : repeatValue * 30),
            repeatUnit: repeatUnit,
            repeatValue: repeatValue,
            waterAmount: waterAmount,
            howToWater: howToWater,
          );
        } else {
          await _notificationService.scheduleFertilizationNotification(
            plantId: plantId,
            plantName: plantName,
            scheduledDate: nextScheduledDate,
            reminderTime: reminderTime,
            repeatDays: repeatUnit == 'days' ? repeatValue : (repeatUnit == 'weeks' ? repeatValue * 7 : repeatValue * 30),
            repeatUnit: repeatUnit,
            repeatValue: repeatValue,
          );
        }
        
        // Ayarları yeniden yükle
        await _loadPlantData();
      }
      
      // State'i güncelle (UI'ı yenile)
      if (mounted) {
        setState(() {
          // State zaten _loadPlantData içinde güncelleniyor ama emin olmak için
        });
      }
    } catch (e) {
      print('❌ _completeCareAction hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  // Bakım geçmişine ekle
  Future<void> _addToCareHistory(String plantId, String type, DateTime date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'care_history_${plantId}_$type';
      final historyJson = prefs.getString(key) ?? '[]';
      final history = List<String>.from(jsonDecode(historyJson) as List);
      
      // Yeni tarihi ekle (en başa)
      history.insert(0, date.toIso8601String());
      
      // Maksimum 100 kayıt tut
      if (history.length > 100) {
        history.removeRange(100, history.length);
      }
      
      await prefs.setString(key, jsonEncode(history));
    } catch (e) {
      print('❌ Bakım geçmişi kaydetme hatası: $e');
    }
  }

  // Bakım geçmişini al
  Future<List<DateTime>> _getCareHistory(String plantId, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'care_history_${plantId}_$type';
      final historyJson = prefs.getString(key) ?? '[]';
      final history = List<String>.from(jsonDecode(historyJson) as List);
      
      return history.map((dateStr) => DateTime.parse(dateStr)).toList();
    } catch (e) {
      print('❌ Bakım geçmişi okuma hatası: $e');
      return [];
    }
  }

  // Bakım geçmişi modalını göster
  Future<void> _showCareHistoryModal(BuildContext context, String plantId, bool isWatering) async {
    final history = await _getCareHistory(plantId, isWatering ? 'watering' : 'fertilization');
    final title = isWatering ? 'Sulama Geçmişi' : 'Gübreleme Geçmişi';
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Başlık
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Geçmiş listesi
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isWatering ? Icons.water_drop : Icons.eco,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz ${isWatering ? "sulama" : "gübreleme"} yapılmadı',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final date = history[index];
                        final dateOnly = DateTime(date.year, date.month, date.day);
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final yesterday = today.subtract(const Duration(days: 1));
                        
                        String dateText;
                        if (dateOnly.isAtSameMomentAs(today)) {
                          dateText = 'Bugün';
                        } else if (dateOnly.isAtSameMomentAs(yesterday)) {
                          dateText = 'Dün';
                        } else {
                          dateText = DateFormat('d MMMM yyyy', 'tr_TR').format(date);
                        }
                        
                        final timeText = DateFormat('HH:mm', 'tr_TR').format(date);
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border, width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isWatering ? Icons.water_drop : Icons.eco,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dateText,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      timeText,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCareSettingsModal(String type) async {
    final plantId = widget.plant['id'] as String;
    final plantName = widget.plant['name'] ?? 'Bitki';
    final isWatering = type == 'watering';
    
    final currentSettings = isWatering 
        ? _wateringNotificationSettings 
        : _fertilizationNotificationSettings;

    int repeatValue = 13;
    String repeatUnit = 'days'; // days, weeks, months
    String waterAmount = 'Orta';
    String howToWater = 'Topraktan';
    TimeOfDay reminderTime = const TimeOfDay(hour: 18, minute: 0);
    final lastDate = isWatering ? _lastWateringDate : _lastFertilizationDate;

    // Mevcut ayarları yükle
    if (currentSettings != null) {
      try {
        repeatValue = currentSettings['repeatValue'] as int? ?? 13;
        repeatUnit = currentSettings['repeatUnit'] as String? ?? 'days';
        waterAmount = currentSettings['waterAmount'] as String? ?? 'Orta';
        howToWater = currentSettings['howToWater'] as String? ?? 'Topraktan';
        
        // Hatırlatma zamanını yükle
        final reminderTimeStr = currentSettings['reminderTime'] as String? ?? '18:00';
        final parts = reminderTimeStr.split(':');
        if (parts.length == 2) {
          reminderTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 18,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      } catch (e) {
        // Hata durumunda varsayılan değerler kullanılacak
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Text(
                        isWatering ? 'Su' : 'Gübre',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sıklık
                      _buildSettingsRowDark(
                        icon: Icons.calendar_today,
                        iconColor: AppColors.primary,
                        title: 'Sıklık',
                        subtitle: 'Her $repeatValue ${repeatUnit == 'days' ? 'günler' : repeatUnit == 'weeks' ? 'haftalar' : 'aylar'}',
                        subtitleColor: AppColors.primary,
                        onTap: () => _showFrequencyPicker(context, setModalState, repeatValue, repeatUnit, (value, unit) {
                          setModalState(() {
                            repeatValue = value;
                            repeatUnit = unit;
                          });
                        }),
                      ),
                      const Divider(color: AppColors.border, height: 1),
                      // Hatırlatma Zamanı
                      _buildSettingsRowDark(
                        icon: Icons.access_time,
                        iconColor: AppColors.primary,
                        title: 'Hatırlatma Zamanı',
                        subtitle: '${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}',
                        subtitleColor: AppColors.primary,
                        onTap: () async {
                          final pickedTime = await showTimePicker(
                            context: context,
                            initialTime: reminderTime,
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.light(
                                    primary: AppColors.primary,
                                    onPrimary: Colors.white,
                                    onSurface: AppColors.textPrimary,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (pickedTime != null) {
                            setModalState(() {
                              reminderTime = pickedTime;
                            });
                          }
                        },
                      ),
                      const Divider(color: AppColors.border, height: 1),
                      // Son sulama / Son gübreleme
                      _buildSettingsRowDark(
                        icon: Icons.calendar_today,
                        iconColor: Colors.grey,
                        title: isWatering ? 'Son sulama' : 'Son gübreleme',
                        subtitle: lastDate != null 
                            ? DateFormat('d.MM.yyyy', 'tr_TR').format(lastDate!)
                            : 'Henüz yapılmadı',
                        onTap: () => _showCareHistoryModal(context, plantId, isWatering),
                      ),
                      const Divider(color: AppColors.border, height: 1),
                      // Programı iptal et
                      _buildSettingsRowDark(
                        icon: Icons.cancel,
                        iconColor: Colors.red,
                        title: 'Programı iptal et',
                        subtitle: '',
                        onTap: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Programı iptal et'),
                              content: Text('${isWatering ? "Sulama" : "Gübreleme"} programını iptal etmek istediğinize emin misiniz?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Hayır'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('Evet'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await _notificationService.cancelNotification(plantId, type);
                            await _loadPlantData();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              // Kaydet butonu
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // Son sulama/gübreleme tarihini kullan veya bugünü kullan
                      final baseDate = lastDate ?? DateTime.now();
                      
                      // Bir sonraki tarihi hesapla
                      DateTime nextDate;
                      if (repeatUnit == 'weeks') {
                        nextDate = baseDate.add(Duration(days: repeatValue * 7));
                      } else if (repeatUnit == 'months') {
                        nextDate = DateTime(baseDate.year, baseDate.month + repeatValue, baseDate.day);
                      } else {
                        nextDate = baseDate.add(Duration(days: repeatValue));
                      }
                      
                      // Seçilen hatırlatma zamanını kullan (yukarıda tanımlı)
                      final repeatDays = repeatUnit == 'days' 
                          ? repeatValue 
                          : (repeatUnit == 'weeks' ? repeatValue * 7 : repeatValue * 30);
                      
                      final success = isWatering
                          ? await _notificationService.scheduleWateringNotification(
                              plantId: plantId,
                              plantName: plantName,
                              scheduledDate: nextDate,
                              reminderTime: reminderTime,
                              repeatDays: repeatDays,
                              repeatUnit: repeatUnit,
                              repeatValue: repeatValue,
                              waterAmount: waterAmount,
                              howToWater: howToWater,
                            )
                          : await _notificationService.scheduleFertilizationNotification(
                              plantId: plantId,
                              plantName: plantName,
                              scheduledDate: nextDate,
                              reminderTime: reminderTime,
                              repeatDays: repeatDays,
                              repeatUnit: repeatUnit,
                              repeatValue: repeatValue,
                            );

                      // Ayarlar her durumda kaydedildi (success kontrolüne gerek yok)
                      Navigator.of(context).pop();
                      await _loadPlantData();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${isWatering ? "Sulama" : "Gübreleme"} programı kaydedildi'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Kaydet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsRowDark({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Color? subtitleColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          color: subtitleColor ?? AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _showWaterAmountPicker(
    BuildContext context,
    StateSetter setModalState,
    String currentValue,
    Function(String) onChanged,
  ) async {
    final options = ['Az', 'Orta', 'Çok'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...options.map((option) => ListTile(
              title: Text(option, style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(option),
              selected: option == currentValue,
            )),
          ],
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  Future<void> _showHowToWaterPicker(
    BuildContext context,
    StateSetter setModalState,
    String currentValue,
    Function(String) onChanged,
  ) async {
    final options = ['Topraktan', 'Yapraklardan', 'Sprey ile'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...options.map((option) => ListTile(
              title: Text(option, style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(option),
              selected: option == currentValue,
            )),
          ],
        ),
      ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  Future<void> _showFrequencyPicker(
    BuildContext context,
    StateSetter setModalState,
    int currentValue,
    String currentUnit,
    Function(int, String) onChanged,
  ) async {
    int selectedValue = currentValue;
    String selectedUnit = currentUnit;
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setPickerState) => Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('İptal', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    Text(
                      'Sıklık Seç',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: () {
                        onChanged(selectedValue, selectedUnit);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Tamam', style: TextStyle(color: AppColors.primary)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    cupertinoOverrideTheme: CupertinoThemeData(
                      brightness: Brightness.light,
                      primaryColor: AppColors.primary,
                      textTheme: CupertinoTextThemeData(
                        textStyle: TextStyle(color: AppColors.textPrimary),
                        pickerTextStyle: TextStyle(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedValue > 0 ? selectedValue - 1 : 12,
                          ),
                          itemExtent: 50,
                          backgroundColor: AppColors.cardBackground,
                          onSelectedItemChanged: (index) {
                            setPickerState(() {
                              selectedValue = index + 1;
                            });
                          },
                          children: List.generate(365, (index) {
                            return Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            );
                          }),
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: selectedUnit == 'days' ? 0 : (selectedUnit == 'weeks' ? 1 : 2),
                          ),
                          itemExtent: 50,
                          backgroundColor: AppColors.cardBackground,
                          onSelectedItemChanged: (index) {
                            setPickerState(() {
                              selectedUnit = ['days', 'weeks', 'months'][index];
                            });
                          },
                          children: [
                            Center(child: Text('Günler', style: TextStyle(color: AppColors.textPrimary))),
                            Center(child: Text('Haftalar', style: TextStyle(color: AppColors.textPrimary))),
                            Center(child: Text('Aylar', style: TextStyle(color: AppColors.textPrimary))),
                          ],
                        ),
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

  Widget _buildInfoTab() {
    final plantType = widget.plant['originalPlantType'] as String? ?? 
                      widget.plant['plantType'] as String? ?? 
                      'Bilinmeyen Bitki';
    final plantInfo = _getPlantInfo(plantType);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Kısa bilgi kutucuğu
          if (plantInfo['description'] != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      plantInfo['description'] as String,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          // Nasıl Yapılır başlığı
          Text(
            'Nasıl Yapılır',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Su kartı
          _buildInfoCard(
            icon: Icons.water_drop,
            iconColor: Colors.blue,
            title: 'Su',
            subtitle: plantInfo['watering'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Gübre kartı
          _buildInfoCard(
            icon: Icons.eco,
            iconColor: Colors.green,
            title: 'Gübre',
            subtitle: plantInfo['fertilizer'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Üretim kartı
          _buildInfoCard(
            icon: Icons.local_florist,
            iconColor: Colors.purple,
            title: 'Üretim',
            subtitle: plantInfo['propagation'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Saksı Değiştirme kartı
          _buildInfoCard(
            icon: Icons.change_circle,
            iconColor: Colors.orange,
            title: 'Saksı Değiştirme',
            subtitle: plantInfo['repotting'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 24),
          // Çevre Koşulları başlığı
          Text(
            'Çevre Koşulları',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Sıcaklık kartı
          _buildInfoCard(
            icon: Icons.thermostat,
            iconColor: Colors.red,
            title: 'Uygun Sıcaklık Aralığı',
            subtitle: plantInfo['temperature'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Nem kartı
          _buildInfoCard(
            icon: Icons.water,
            iconColor: Colors.cyan,
            title: 'Uygun Nem Aralığı',
            subtitle: plantInfo['humidity'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // CO2 kartı
          _buildInfoCard(
            icon: Icons.air,
            iconColor: Colors.teal,
            title: 'Uygun CO2 Aralığı',
            subtitle: plantInfo['co2'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Güneş Işığı kartı
          _buildInfoCard(
            icon: Icons.wb_sunny,
            iconColor: Colors.amber,
            title: 'Güneş Işığı',
            subtitle: plantInfo['light'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Toprak kartı
          _buildInfoCard(
            icon: Icons.terrain,
            iconColor: Colors.brown,
            title: 'Toprak',
            subtitle: plantInfo['soil'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          // Konum kartı
          _buildInfoCard(
            icon: Icons.location_on,
            iconColor: Colors.blue,
            title: 'Uygun Konum',
            subtitle: plantInfo['location'] as String? ?? 'Bilgi bulunamadı',
            onTap: () {},
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getPlantInfo(String plantType) {
    // Bitki türüne göre bilgileri döndür
    // Önce İngilizce'den Türkçe'ye çevir varsa
    var normalizedEnglish = _normalizePlantType(plantType);
    var turkishType = _plantTypeTranslations[normalizedEnglish] ?? normalizedEnglish;
    
    // Eğer zaten Türkçe ise direkt kullan
    if (_plantTypeTranslations.containsValue(plantType)) {
      turkishType = plantType;
    }
    
    final normalizedType = turkishType.toLowerCase().trim();
    
    // Bitki bilgileri veritabanı
    final plantDatabase = {
      // Mısır
      'mısır': {
        'description': 'Mısır, dünyada en çok yetiştirilen tahıl bitkilerinden biridir. Yüksek verimli ve besleyici bir bitkidir.',
        'watering': 'Toprak nemli tutulmalı, özellikle çiçeklenme ve koçan oluşumu döneminde düzenli sulama yapılmalı. Genellikle haftada 2-3 kez sulanır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanılmalı. Ekim öncesi toprak hazırlığında ve bitki gelişim döneminde gübreleme yapılır.',
        'propagation': 'Tohumla üretilir. İlkbahar aylarında (Nisan-Mayıs) ekim yapılır.',
        'repotting': 'Mısır genellikle açık alanda yetiştirilir, saksı değiştirme gerekmez.',
        'temperature': '15-30°C arası ideal sıcaklıktır. Minimum 10°C\'nin altına düşmemelidir.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-1000 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney cepheli, güneşli ve rüzgarlı alanlar idealdir.',
      },
      // Domates
      'domates': {
        'description': 'Domates, dünyada en çok tüketilen sebzelerden biridir. C vitamini ve likopen açısından zengindir.',
        'watering': 'Toprak yüzeyi kurudukça sulanmalı. Genellikle haftada 2-3 kez, sabah erken saatlerde sulama yapılır. Yapraklara su değdirilmemelidir.',
        'fertilizer': 'Çiçeklenme öncesi azotlu gübre, meyve oluşumunda fosfor ve potasyum ağırlıklı gübre kullanılır. Her 2-3 haftada bir gübreleme yapılabilir.',
        'propagation': 'Tohumla üretilir. Şubat-Mart aylarında fide olarak yetiştirilir, Nisan-Mayıs\'ta bahçeye dikilir.',
        'repotting': 'Fide döneminde gerekirse daha büyük saksıya alınabilir. Yetişkin bitkiler için geniş saksılar tercih edilir.',
        'temperature': '18-25°C arası ideal sıcaklıktır. Gece sıcaklığı 15°C\'nin altına düşmemelidir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-6.8 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Elma
      'elma': {
        'description': 'Elma, dünyada en çok yetiştirilen meyve ağaçlarından biridir. Lif ve antioksidan açısından zengindir.',
        'watering': 'Genç ağaçlar daha sık sulanır. Yetişkin ağaçlar için toprak kurudukça sulama yapılır. Yaz aylarında haftada 1-2 kez derin sulama yapılmalıdır.',
        'fertilizer': 'İlkbahar başında azotlu gübre, çiçeklenme sonrası fosfor ve potasyum ağırlıklı gübre kullanılır. Sonbaharda organik gübre uygulanabilir.',
        'propagation': 'Aşı ile üretilir. Tohumdan yetiştirilenler genellikle meyve vermez.',
        'repotting': 'Ağaçlar genellikle açık alanda yetiştirilir, saksı değiştirme gerekmez.',
        'temperature': 'Kışın -20°C\'ye kadar dayanabilir. Yazın 20-25°C arası ideal sıcaklıktır.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, derin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Patlıcan
      'patlıcan': {
        'description': 'Patlıcan, Akdeniz mutfağının vazgeçilmez sebzelerinden biridir. Düşük kalorili ve lif açısından zengindir.',
        'watering': 'Toprak nemli tutulmalı, özellikle meyve oluşumu döneminde düzenli sulama yapılmalı. Haftada 2-3 kez sulanır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanılır. Çiçeklenme ve meyve oluşumu döneminde gübreleme yapılır.',
        'propagation': 'Tohumla üretilir. Şubat-Mart aylarında fide olarak yetiştirilir, Nisan-Mayıs\'ta bahçeye dikilir.',
        'repotting': 'Fide döneminde gerekirse daha büyük saksıya alınabilir.',
        'temperature': '20-30°C arası ideal sıcaklıktır. Minimum 15°C\'nin altına düşmemelidir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli alanlar idealdir.',
      },
      // Biber
      'biber': {
        'description': 'Biber, hem tatlı hem de acı çeşitleriyle mutfakların vazgeçilmez sebzelerindendir. C vitamini açısından çok zengindir.',
        'watering': 'Toprak yüzeyi kurudukça sulanmalı. Düzenli ve dengeli sulama yapılmalı, aşırı sulamadan kaçınılmalıdır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanılır. Çiçeklenme ve meyve oluşumu döneminde gübreleme yapılır.',
        'propagation': 'Tohumla üretilir. Şubat-Mart aylarında fide olarak yetiştirilir, Nisan-Mayıs\'ta bahçeye dikilir.',
        'repotting': 'Fide döneminde gerekirse daha büyük saksıya alınabilir.',
        'temperature': '20-30°C arası ideal sıcaklıktır. Minimum 15°C\'nin altına düşmemelidir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli alanlar idealdir.',
      },
      // Salatalık
      'salatalık': {
        'description': 'Salatalık, düşük kalorili ve su içeriği yüksek bir sebzedir. Yaz aylarının vazgeçilmez sebzelerindendir.',
        'watering': 'Yüksek su ihtiyacı vardır. Toprak sürekli nemli tutulmalı, özellikle meyve oluşumu döneminde günlük sulama yapılabilir.',
        'fertilizer': 'Azot ağırlıklı gübre kullanılır. Çiçeklenme ve meyve oluşumu döneminde fosfor ve potasyum eklenir.',
        'propagation': 'Tohumla üretilir. Nisan-Mayıs aylarında doğrudan toprağa ekilebilir.',
        'repotting': 'Geniş saksılarda yetiştirilebilir, gerekirse daha büyük saksıya alınabilir.',
        'temperature': '18-25°C arası ideal sıcaklıktır. Minimum 15°C\'nin altına düşmemelidir.',
        'humidity': '%70-90 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Kalanchoe
      'kalanchoe': {
        'description': 'Kalanchoe, sukulent bir bitkidir. Bakımı kolay ve uzun süre çiçek açan bir iç mekan bitkisidir.',
        'watering': 'Toprak tamamen kuruduktan sonra sulanmalı. Genellikle 1-2 haftada bir sulama yeterlidir. Kış aylarında daha az sulanır.',
        'fertilizer': 'İlkbahar ve yaz aylarında ayda bir kez sukulent gübresi kullanılabilir. Kış aylarında gübreleme yapılmaz.',
        'propagation': 'Yaprak veya gövde çelikleri ile üretilir. İlkbahar ve yaz aylarında yapılır.',
        'repotting': 'Her 2-3 yılda bir, ilkbahar aylarında saksı değiştirilebilir.',
        'temperature': '15-25°C arası ideal sıcaklıktır. Minimum 10°C\'nin altına düşmemelidir.',
        'humidity': '%40-60 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Parlak, dolaylı güneş ışığı gerektirir. Doğrudan güneş ışığından kaçınılmalıdır.',
        'soil': 'İyi drene edilmiş, kumlu toprak karışımı tercih edilir. Sukulent toprağı kullanılabilir.',
        'location': 'Doğu veya batı cepheli pencere önü idealdir. İç mekan bitkisidir.',
      },
      // Kaktüs
      'kaktüs': {
        'description': 'Kaktüs, çöl bitkilerinin en bilinen örneğidir. Su depolama yeteneği sayesinde kurak koşullara dayanıklıdır.',
        'watering': 'Toprak tamamen kuruduktan sonra, genellikle 2-4 haftada bir sulanmalı. Kış aylarında çok daha az sulanır.',
        'fertilizer': 'İlkbahar ve yaz aylarında ayda bir kez sukulent/kaktüs gübresi kullanılabilir.',
        'propagation': 'Tohum, yavru veya çelik ile üretilir. İlkbahar aylarında yapılır.',
        'repotting': 'Her 2-3 yılda bir, ilkbahar aylarında saksı değiştirilebilir.',
        'temperature': '20-30°C arası ideal sıcaklıktır. Kışın 10°C\'nin altına düşmemelidir.',
        'humidity': '%30-50 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Parlak, direkt güneş ışığı gerektirir. Günde en az 4-6 saat güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, kumlu ve çakıllı toprak karışımı tercih edilir. Kaktüs toprağı kullanılabilir.',
        'location': 'Güney cepheli pencere önü idealdir. İç mekan bitkisidir.',
      },
      // Üzüm
      'üzüm': {
        'description': 'Üzüm, dünyada en çok yetiştirilen meyve bitkilerinden biridir. Şarap yapımında ve sofralık olarak tüketilir.',
        'watering': 'Genç bitkiler daha sık sulanır. Yetişkin asmalar için toprak kurudukça derin sulama yapılır. Meyve olgunlaşma döneminde düzenli sulama önemlidir.',
        'fertilizer': 'İlkbahar başında azotlu gübre, çiçeklenme sonrası fosfor ve potasyum ağırlıklı gübre kullanılır. Sonbaharda organik gübre uygulanabilir.',
        'propagation': 'Çelik veya aşı ile üretilir. İlkbahar aylarında yapılır.',
        'repotting': 'Asmalar genellikle açık alanda yetiştirilir, saksı değiştirme gerekmez.',
        'temperature': '15-30°C arası ideal sıcaklıktır. Kışın -15°C\'ye kadar dayanabilir.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, derin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Kiraz
      'kiraz': {
        'description': 'Kiraz, yaz mevsiminin en sevilen meyvelerinden biridir. Antioksidan açısından zengindir.',
        'watering': 'Genç ağaçlar daha sık sulanır. Yetişkin ağaçlar için toprak kurudukça sulama yapılır. Meyve oluşumu döneminde düzenli sulama önemlidir.',
        'fertilizer': 'İlkbahar başında azotlu gübre, çiçeklenme sonrası fosfor ve potasyum ağırlıklı gübre kullanılır.',
        'propagation': 'Aşı ile üretilir. Tohumdan yetiştirilenler genellikle meyve vermez.',
        'repotting': 'Ağaçlar genellikle açık alanda yetiştirilir, saksı değiştirme gerekmez.',
        'temperature': 'Kışın -25°C\'ye kadar dayanabilir. Yazın 20-25°C arası ideal sıcaklıktır.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, derin toprak tercih edilir. pH 6.0-7.5 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Şeftali
      'şeftali': {
        'description': 'Şeftali, yumuşak ve sulu meyvesiyle yaz mevsiminin vazgeçilmez meyvelerindendir. C vitamini açısından zengindir.',
        'watering': 'Genç ağaçlar daha sık sulanır. Yetişkin ağaçlar için toprak kurudukça derin sulama yapılır. Meyve oluşumu döneminde düzenli sulama önemlidir.',
        'fertilizer': 'İlkbahar başında azotlu gübre, çiçeklenme sonrası fosfor ve potasyum ağırlıklı gübre kullanılır.',
        'propagation': 'Aşı ile üretilir. Tohumdan yetiştirilenler genellikle meyve vermez.',
        'repotting': 'Ağaçlar genellikle açık alanda yetiştirilir, saksı değiştirme gerekmez.',
        'temperature': 'Kışın -20°C\'ye kadar dayanabilir. Yazın 20-30°C arası ideal sıcaklıktır.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, derin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Patates
      'patates': {
        'description': 'Patates, dünyada en çok tüketilen sebzelerden biridir. Karbonhidrat ve potasyum açısından zengindir.',
        'watering': 'Toprak nemli tutulmalı, özellikle yumru oluşumu döneminde düzenli sulama yapılmalı. Haftada 2-3 kez sulanır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanılır. Ekim öncesi toprak hazırlığında ve bitki gelişim döneminde gübreleme yapılır.',
        'propagation': 'Tohum patates ile üretilir. İlkbahar aylarında (Mart-Nisan) ekim yapılır.',
        'repotting': 'Patates genellikle açık alanda yetiştirilir, saksı değiştirme gerekmez.',
        'temperature': '15-20°C arası ideal sıcaklıktır. Yumru oluşumu için serin hava gereklidir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, gevşek toprak tercih edilir. pH 5.0-6.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli alanlar idealdir.',
      },
      // Çilek
      'çilek': {
        'description': 'Çilek, yaz mevsiminin en sevilen meyvelerinden biridir. C vitamini ve antioksidan açısından çok zengindir.',
        'watering': 'Toprak nemli tutulmalı, özellikle meyve oluşumu döneminde düzenli sulama yapılmalı. Haftada 2-3 kez sulanır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli gübre kullanılır. İlkbahar başında ve meyve oluşumu döneminde gübreleme yapılır.',
        'propagation': 'Yavru bitkiler (stolon) ile üretilir. İlkbahar veya sonbahar aylarında yapılır.',
        'repotting': 'Her 2-3 yılda bir, ilkbahar aylarında saksı değiştirilebilir.',
        'temperature': '15-25°C arası ideal sıcaklıktır. Kışın -10°C\'ye kadar dayanabilir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 5.5-6.5 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli alanlar idealdir.',
      },
      // Portakal
      'portakal': {
        'description': 'Portakal, C vitamini açısından çok zengin bir turunçgil meyvesidir. Bağışıklık sistemini güçlendirir.',
        'watering': 'Toprak kurudukça derin sulama yapılmalı. Yaz aylarında haftada 2-3 kez, kış aylarında daha az sulanır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli turunçgil gübresi kullanılır. İlkbahar, yaz ve sonbahar aylarında gübreleme yapılır.',
        'propagation': 'Aşı ile üretilir. Tohumdan yetiştirilenler genellikle meyve vermez.',
        'repotting': 'Genç ağaçlar için her 2-3 yılda bir saksı değiştirilebilir.',
        'temperature': '15-30°C arası ideal sıcaklıktır. Minimum -5°C\'nin altına düşmemelidir.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.5 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve korunaklı alanlar idealdir.',
      },
      // Limon
      'limon': {
        'description': 'Limon, C vitamini açısından çok zengin bir turunçgil meyvesidir. Mutfakta ve sağlık alanında yaygın olarak kullanılır.',
        'watering': 'Toprak kurudukça derin sulama yapılmalı. Yaz aylarında haftada 2-3 kez, kış aylarında daha az sulanır.',
        'fertilizer': 'Azot, fosfor ve potasyum içeren dengeli turunçgil gübresi kullanılır. İlkbahar, yaz ve sonbahar aylarında gübreleme yapılır.',
        'propagation': 'Aşı ile üretilir. Tohumdan yetiştirilenler genellikle meyve vermez.',
        'repotting': 'Genç ağaçlar için her 2-3 yılda bir saksı değiştirilebilir.',
        'temperature': '15-30°C arası ideal sıcaklıktır. Minimum -5°C\'nin altına düşmemelidir.',
        'humidity': '%50-70 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.5 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve korunaklı alanlar idealdir.',
      },
      // Yaban Mersini
      'yaban mersini': {
        'description': 'Yaban mersini, antioksidan açısından çok zengin bir meyvedir. Sağlık açısından çok faydalıdır ve süper meyve olarak bilinir.',
        'watering': 'Toprak sürekli nemli kalmalı ancak su birikintisi olmamalıdır. Özellikle meyve oluşumu döneminde düzenli sulama önemlidir. Yağmurlama yerine damla sulama tercih edilmelidir.',
        'fertilizer': 'Yaban mersini için özel asidik gübreler kullanın. Organik gübreler (kompost, çam iğneleri) çok uygundur. Azot ihtiyacı düşüktür, potasyum ve fosfor önemlidir. Aşırı gübrelemeden kaçının.',
        'propagation': 'Çelik veya yavru bitkiler ile üretilir. İlkbahar veya sonbahar aylarında yapılır.',
        'repotting': 'Yaban mersini saksıda yetiştirilebilir. Kökler saksıyı doldurduğunda asidik toprak karışımı ile daha büyük saksıya alın. İyi drenaj çok önemlidir.',
        'temperature': '15-25°C arası ideal sıcaklıktır. Kışın -20°C\'ye kadar dayanabilir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'Asidik toprak gerektirir (pH 4.5-5.5). İyi drene edilmiş, organik maddece zengin toprak tercih edilir. Çam iğneleri ve turba yosunu eklenebilir.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Ahududu
      'ahududu': {
        'description': 'Ahududu, yaz mevsiminin en sevilen meyvelerinden biridir. C vitamini ve lif açısından zengindir.',
        'watering': 'Toprak nemli kalmalı ancak su birikintisi olmamalıdır. Meyve oluşumu ve olgunlaşma döneminde daha sık sulama yapın. Yaprakları ıslatmadan toprağa doğrudan sulama yapın.',
        'fertilizer': 'Ahududu için dengeli gübreler kullanın. İlkbahar başında azot, meyve oluşumundan önce potasyum ve fosfor ağırlıklı gübre uygulayın. Organik gübreler (kompost, gübre) çok uygundur.',
        'propagation': 'Yavru bitkiler veya çelik ile üretilir. İlkbahar veya sonbahar aylarında yapılır.',
        'repotting': 'Ahududu saksıda yetiştirilebilir ancak genellikle bahçede yetiştirilir. Kökler saksıyı doldurduğunda daha büyük saksıya alın. İyi drenaj çok önemlidir.',
        'temperature': '15-25°C arası ideal sıcaklıktır. Kışın -20°C\'ye kadar dayanabilir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-600 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir. Destek sistemi gerektirir.',
      },
      // Soya
      'soya': {
        'description': 'Soya, protein açısından çok zengin bir baklagil bitkisidir. Beslenme ve tarım açısından çok önemlidir.',
        'watering': 'Özellikle çiçeklenme ve bakla oluşumu döneminde yeterli su çok önemlidir. Toprak kurumaya başladığında sulama yapın. Drip sulama sistemi idealdir.',
        'fertilizer': 'Soya bitkileri azot fiksasyonu yapar, bu yüzden azot ihtiyacı düşüktür. Fosfor ve potasyum önemlidir. Ekim öncesi toprağa fosfor ve potasyum gübreleri karıştırın. Rhizobium bakterisi ile aşılanmış tohumlar kullanın.',
        'propagation': 'Tohumla üretilir. İlkbahar aylarında (Nisan-Mayıs) ekim yapılır.',
        'repotting': 'Soya bitkileri genellikle tarlada yetiştirilir. Saksıda yetiştirilebilir ancak derin kök yapısı nedeniyle büyük saksılar gerekir.',
        'temperature': '20-30°C arası ideal sıcaklıktır. Minimum 10°C\'nin altına düşmemelidir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-1000 ppm arası normal seviyelerdir. Yüksek CO2 seviyesi verimi artırır.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, derin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
      // Kabak
      'kabak': {
        'description': 'Kabak, düşük kalorili ve besleyici bir sebzedir. Yaz mevsiminin vazgeçilmez sebzelerindendir.',
        'watering': 'Toprak kurumaya başladığında sulama yapın. Yaprakları ıslatmadan toprağa doğrudan sulama yapın. Özellikle meyve oluşumu döneminde düzenli sulama çok önemlidir. Sabah saatlerinde sulama yapın.',
        'fertilizer': 'Kabak bitkileri için dengeli gübreler kullanın. Kompost ve organik gübreler çok uygundur. Fosfor çiçeklenme için, potasyum meyve kalitesi için önemlidir. Aşırı azot yaprak gelişimini artırır ancak meyve üretimini azaltır.',
        'propagation': 'Tohumla üretilir. Nisan-Mayıs aylarında doğrudan toprağa ekilebilir.',
        'repotting': 'Kabak bitkileri genellikle bahçede yetiştirilir. Saksıda yetiştirilebilir ancak büyük saksılar gerekir.',
        'temperature': '18-25°C arası ideal sıcaklıktır. Minimum 15°C\'nin altına düşmemelidir.',
        'humidity': '%60-80 nem aralığı uygundur.',
        'co2': '400-800 ppm arası normal seviyelerdir.',
        'light': 'Tam güneş ışığı gerektirir. Günde en az 6-8 saat direkt güneş ışığı almalıdır.',
        'soil': 'İyi drene edilmiş, organik maddece zengin toprak tercih edilir. pH 6.0-7.0 arası uygundur.',
        'location': 'Güney veya güneydoğu cepheli, güneşli ve havalandırması iyi alanlar idealdir.',
      },
    };
    
    // Bitki türünü normalize et ve eşleştir
    // Önce tam eşleşme kontrolü
    for (var key in plantDatabase.keys) {
      if (normalizedType == key || normalizedType.contains(key) || key.contains(normalizedType)) {
        return plantDatabase[key]!;
      }
    }
    
    // İngilizce isimlerle eşleştirme (blueberry, raspberry, soybean, squash, pepper)
    final englishToTurkish = {
      'blueberry': 'yaban mersini',
      'raspberry': 'ahududu',
      'soybean': 'soya',
      'squash': 'kabak',
      'pepper': 'biber',
      'bell_pepper': 'biber',
      'pepper,_bell': 'biber',
      'pepper, bell': 'biber',
    };
    
    for (var englishKey in englishToTurkish.keys) {
      if (normalizedType.contains(englishKey)) {
        final turkishKey = englishToTurkish[englishKey];
        if (plantDatabase.containsKey(turkishKey)) {
          return plantDatabase[turkishKey]!;
        }
      }
    }
    
    // Eğer hala eşleşme yoksa, normalize edilmiş İngilizce ismi kontrol et
    final normalizedEnglishLower = normalizedEnglish.toLowerCase().trim();
    for (var englishKey in englishToTurkish.keys) {
      if (normalizedEnglishLower.contains(englishKey)) {
        final turkishKey = englishToTurkish[englishKey];
        if (plantDatabase.containsKey(turkishKey)) {
          return plantDatabase[turkishKey]!;
        }
      }
    }
    
    // Eşleşme bulunamazsa varsayılan bilgiler
    return {
      'description': '$plantType hakkında detaylı bilgi için bitki türünü doğru şekilde tanımlayın.',
      'watering': 'Toprak nemine göre düzenli sulama yapılmalıdır.',
      'fertilizer': 'Bitki türüne uygun dengeli gübre kullanılmalıdır.',
      'propagation': 'Tohum veya çelik ile üretilebilir.',
      'repotting': 'Gerekirse ilkbahar aylarında saksı değiştirilebilir.',
      'temperature': '15-25°C arası genel olarak uygun sıcaklıktır.',
      'humidity': '%50-70 nem aralığı genel olarak uygundur.',
      'co2': '400-600 ppm arası normal seviyelerdir.',
      'light': 'Bitki türüne göre güneş ışığı ihtiyacı değişir.',
      'soil': 'İyi drene edilmiş toprak tercih edilir.',
      'location': 'Bitki türüne uygun konum seçilmelidir.',
    };
  }

  // Bakım Detayları Bölümü
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

  Map<String, String> _getPlantCareInfo(String? plantType, bool isHealthy, String? rawClassName) {
    // Önce hastalığa özel bakım bilgisi var mı kontrol et
    if (rawClassName != null && rawClassName.isNotEmpty && !isHealthy) {
      var normalizedRawClass = rawClassName.trim();
      var diseaseSpecific = _getDiseaseSpecificCareInfo(normalizedRawClass);
      
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
    
    // Plant type'ı normalize et
    var plantTypeLower = plantType.toLowerCase().trim();
    if (plantTypeLower.contains('(')) {
      plantTypeLower = plantTypeLower.split('(')[0].trim();
    }
    plantTypeLower = plantTypeLower.replaceAll(RegExp(r'_+$'), '').trim();
    plantTypeLower = plantTypeLower.replaceAll(' ', '_');
    
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

  Map<String, String>? _getDiseaseSpecificCareInfo(String rawClass) {
    if (!rawClass.contains('___')) return null;
    
    final parts = rawClass.split('___');
    if (parts.length < 2) return null;
    
    // Plant type'ı normalize et: "Corn_(maize)" -> "corn", "Apple" -> "apple"
    var plantType = parts[0].toLowerCase().trim();
    // Parantez içindeki kısımları temizle: "corn_(maize)" -> "corn"
    if (plantType.contains('(')) {
      plantType = plantType.split('(')[0].trim();
    }
    // Alt çizgileri temizle: "corn_" -> "corn"
    plantType = plantType.replaceAll(RegExp(r'_+$'), '').trim();
    
    var disease = parts[1].toLowerCase().trim();
    // Disease'deki son alt çizgileri temizle: "common_rust_" -> "common_rust"
    disease = disease.replaceAll(RegExp(r'_+$'), '').trim();
    
    // Her bitki-hastalık kombinasyonu için özel bakım bilgileri
    var key = '${plantType}___$disease';
    
    // Debug: Tüm olası formatları dene
    Map<String, String>? result;
    
    // Önce normal key ile dene
    result = _tryGetDiseaseInfo(key);
    if (result != null) {
      return result;
    }
    
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

  Map<String, String> _getFacilityRequirements(String? plantType, bool isHealthy, String? rawClassName) {
    if (plantType == null) {
      return _defaultFacilityRequirements();
    }
    
    // Plant type'ı normalize et
    var plantTypeLower = plantType.toLowerCase().trim();
    if (plantTypeLower.contains('(')) {
      plantTypeLower = plantTypeLower.split('(')[0].trim();
    }
    plantTypeLower = plantTypeLower.replaceAll(RegExp(r'_+$'), '').trim();
    plantTypeLower = plantTypeLower.replaceAll(' ', '_');
    
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

  // Plant-specific care info functions
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

  // Plant-specific facility requirement functions
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
      'co2': 'Normal (400-600 ppm)',
      'co2Details': 'Normal atmosferik CO2 seviyesi (400-600 ppm) yeterlidir.',
      'temperature': '18-27°C',
      'temperatureDetails': '18-27°C arası sıcaklık idealdir. 15°C altı büyümeyi yavaşlatır, 30°C üzeri stres yaratır.',
    };
  }

  // Helper functions (plant_scan_page.dart'tan kopyalanacak)
  String _prettifyClassName(String value) {
    return value
        .split('_')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

// Plant type translations (plant_scan_page.dart'tan)
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

// Disease translations (plant_scan_page.dart'tan)
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

// AI Chat Sheet Widget
class _AIChatSheet extends StatefulWidget {
  final Map<String, dynamic> plant;
  final List<Map<String, dynamic>> analysisHistory;
  final Map<String, dynamic>? currentAnalysisResult;

  const _AIChatSheet({
    required this.plant,
    required this.analysisHistory,
    this.currentAnalysisResult,
  });

  @override
  State<_AIChatSheet> createState() => _AIChatSheetState();
}

class _AIChatSheetState extends State<_AIChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    // Bitki bilgilerini hazırla
    final plantInfo = _preparePlantInfo();
    
    // İlk AI mesajını gönder
    setState(() {
      _isInitializing = true;
    });

    final plantType = widget.plant['originalPlantType'] as String? ?? 
                      widget.plant['plantType'] as String? ?? 
                      widget.plant['name'] as String? ?? 
                      'bitki';
    final initialMessage = await _sendMessageToAI(
      'Merhaba! $plantType bitkim hakkında kısa bir özet verir misin?',
      plantInfo: plantInfo,
      isInitial: true,
    );

    setState(() {
      _messages.add({
        'role': 'user',
        'content': 'Merhaba!',
        'timestamp': DateTime.now(),
      });
      if (initialMessage.isNotEmpty) {
        _messages.add({
          'role': 'assistant',
          'content': initialMessage,
          'timestamp': DateTime.now(),
        });
      }
      _isInitializing = false;
    });

    _scrollToBottom();
  }

  String _preparePlantInfo() {
    final buffer = StringBuffer();
    final plantType = widget.plant['originalPlantType'] as String? ?? 
                      widget.plant['plantType'] as String? ?? 
                      widget.plant['name'] as String? ?? 
                      'Bilinmeyen Bitki';
    buffer.writeln('Bitki Bilgileri:');
    buffer.writeln('- Bitki Adı: $plantType'); // Yapay zeka için bitki türü kullan
    buffer.writeln('- Durum: ${widget.plant['isHealthy'] == true ? "Sağlıklı" : "Hasta"}');
    if (widget.plant['disease'] != null && widget.plant['disease'].toString().isNotEmpty) {
      buffer.writeln('- Hastalık: ${widget.plant['disease']}');
    }
    buffer.writeln('- Kayıt Tarihi: ${widget.plant['savedAt'] ?? "Bilinmiyor"}');
    buffer.writeln('');

    buffer.writeln('Analiz Geçmişi:');
    int analysisCount = 0;
    for (var entry in widget.analysisHistory) {
      final analysisResult = entry['analysisResult'] as Map<String, dynamic>?;
      if (analysisResult != null) {
        analysisCount++;
        final healthLabel = analysisResult['health_label'] ?? 'Bilinmiyor';
        final date = entry['date'] ?? 'Bilinmiyor';
        buffer.writeln('$analysisCount. Analiz ($date):');
        buffer.writeln('  - Sağlık Durumu: $healthLabel');
        if (analysisResult['disease_display'] != null) {
          buffer.writeln('  - Hastalık: ${analysisResult['disease_display']}');
        }
        if (analysisResult['health_score'] != null) {
          buffer.writeln('  - Sağlık Skoru: ${(analysisResult['health_score'] * 100).toStringAsFixed(0)}%');
        }
        buffer.writeln('');
      }
    }

    if (widget.currentAnalysisResult != null) {
      final current = widget.currentAnalysisResult!['analysisResult'] as Map<String, dynamic>?;
      if (current != null) {
        buffer.writeln('En Son Analiz:');
        buffer.writeln('- Sağlık Durumu: ${current['health_label'] ?? "Bilinmiyor"}');
        if (current['disease_display'] != null) {
          buffer.writeln('- Hastalık: ${current['disease_display']}');
        }
        buffer.writeln('');
      }
    }

    return buffer.toString();
  }

  Future<String> _sendMessageToAI(String message, {String? plantInfo, bool isInitial = false}) async {
    try {
      // Groq API kullan (ücretsiz ve hızlı)
      // API key'i config'den al
      await AppConfig.load();
      final apiKey = AppConfig.groqApiKey;
      
      // API key yoksa fallback kullan
      if (apiKey.isEmpty || apiKey == 'BURAYA_API_KEY_INIZI_YAZIN') {
        return _getFallbackResponse(message);
      }
      
      const apiUrl = 'https://api.groq.com/openai/v1/chat/completions';

      final systemPrompt = '''Sen bir bitki bakım uzmanısın ve Türk tarım literatüründen bilgilerle donatılmışsın. Kullanıcının bitkisi hakkında detaylı bilgilere sahipsin.

${plantInfo ?? ''}

ÖNEMLİ KURALLAR:
1. İlk mesajda sadece 2-3 cümle kısa özet ver (bitki durumu ve en önemli nokta)
2. Bakım önerilerinde MUTLAKA spesifik zaman aralıkları kullan, ancak bu zaman aralıkları bitki türüne ve hastalığa ÖZEL olmalı:
   - Her bitki türü için (Elma, Domates, Mısır, vb.) o bitkiye özgü gerçek bakım programı kullan
   - Her hastalık için (Elma Kabuğu, Yaprak Yanıklığı, vb.) o hastalığa özgü tedavi programı kullan
   - Türk tarım literatüründen araştırılmış, gerçek zaman aralıkları ver (örnek: "21 günde bir" sadece bir örnekti, sen gerçek bilgileri kullan)
   - Genel ifadeler kullanma ("düzenli", "sık sık" gibi)
   - Örnek verme, gerçek bilgileri kullan
3. Her bitki ve hastalık için Türk tarım literatüründen araştırılmış, spesifik ve doğru bilgiler ver
4. Kısa, net ve pratik cevaplar ver
5. Türkçe olarak, samimi ama profesyonel bir dil kullan
6. Analiz geçmişine bakarak bitkinin durumunu değerlendir ve spesifik öneriler sun
7. Cevaplarında uygun yerlerde emoji kullan (🌱 🌿 💧 ☀️ 🌡️ ⚠️ ✅ ❌ 🔍 📅 gibi), ancak aşırıya kaçma
8. ÖNEMLİ: Yukarıdaki "21 günde bir, 3 ayda bir" gibi ifadeler sadece ÖRNEKTİ. Sen her bitki ve hastalık için gerçek, araştırılmış zaman aralıklarını kullan. Örneğin Elma için farklı, Domates için farklı, Mısır için farklı zaman aralıkları olmalı.''';

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        ..._messages.map((m) => {
              'role': m['role'],
              'content': m['content'],
            }),
        {'role': 'user', 'content': message},
      ];

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant', // Groq'un ücretsiz modeli
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': isInitial ? 200 : 800, // İlk mesaj için daha kısa
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('API yanıt vermedi');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          return content;
        }
        return 'Üzgünüm, API\'den yanıt alınamadı.';
      } else {
        // Hata durumunda detaylı mesaj
        final errorBody = response.body;
        if (response.statusCode == 401) {
          return 'API key geçersiz. Lütfen config.dart dosyasındaki API key\'i kontrol edin.';
        } else if (response.statusCode == 429) {
          return 'Çok fazla istek gönderildi. Lütfen birkaç saniye bekleyip tekrar deneyin.';
        } else {
          return 'API hatası (${response.statusCode}): $errorBody';
        }
      }
    } on TimeoutException {
      return 'İstek zaman aşımına uğradı. İnternet bağlantınızı kontrol edin.';
    } catch (e) {
      // Hata durumunda fallback
      return 'Bağlantı hatası: ${e.toString()}. Fallback yanıt kullanılıyor.\n\n${_getFallbackResponse(message)}';
    }
  }

  String _getFallbackResponse(String message) {
    // API olmadan da çalışan basit bir yanıt sistemi
    final plantType = widget.plant['originalPlantType'] as String? ?? 
                      widget.plant['plantType'] as String? ?? 
                      widget.plant['name'] as String? ?? 
                      'bitki';
    final isHealthy = widget.plant['isHealthy'] == true;
    final disease = widget.plant['disease'] as String?;

    if (message.toLowerCase().contains('merhaba') || message.toLowerCase().contains('selam') || message.length < 10) {
      return 'Merhaba! $plantType bitkiniz ${isHealthy ? "sağlıklı görünüyor" : "hasta durumda"}. ${disease != null && disease.isNotEmpty ? "Hastalık: $disease. " : ""}Nasıl yardımcı olabilirim?';
    } else if (message.toLowerCase().contains('bakım') || message.toLowerCase().contains('öneri') || message.toLowerCase().contains('sulama') || message.toLowerCase().contains('gübre')) {
      return 'Bitkiniz için bakım önerileri:\n\n'
          '• Sulama: Haftada 2-3 kez, toprak kurudukça\n'
          '• Gübreleme: 3 ayda bir, ilkbahar ve yaz başında\n'
          '• Budama: ${isHealthy ? "Kış sonu-ilkbahar başı" : "Hastalıklı kısımları hemen çıkarın"}\n'
          '• Işık: Günde 6-8 saat direkt güneş\n\n'
          '${disease != null && disease.isNotEmpty ? "Hastalık için: Etkilenen yaprakları temizleyin, uygun ilaçlama yapın." : ""}';
    } else {
      return '$plantType bitkiniz hakkında sorularınızı sorabilirsiniz. Bakım, hastalık tedavisi veya genel bilgi için yardımcı olabilirim.';
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({
        'role': 'user',
        'content': message,
        'timestamp': DateTime.now(),
      });
      _isLoading = true;
    });

    _messageController.clear();
    _scrollToBottom();

    final plantInfo = _preparePlantInfo();
    final response = await _sendMessageToAI(message, plantInfo: plantInfo, isInitial: false);

    setState(() {
      _messages.add({
        'role': 'assistant',
        'content': response,
        'timestamp': DateTime.now(),
      });
      _isLoading = false;
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveChat() async {
    if (_messages.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final plantId = widget.plant['id'] as String;
      
      // Mesajlardaki DateTime objelerini string'e çevir
      final serializedMessages = _messages.map((msg) {
        final messageCopy = Map<String, dynamic>.from(msg);
        if (messageCopy['timestamp'] is DateTime) {
          messageCopy['timestamp'] = (messageCopy['timestamp'] as DateTime).toIso8601String();
        }
        return messageCopy;
      }).toList();
      
      // Sohbet kaydını oluştur
      final chatEntry = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': 'ai_chat',
        'messages': serializedMessages,
        'date': DateTime.now().toIso8601String(),
        'plantName': widget.plant['originalPlantType'] as String? ?? 
                     widget.plant['plantType'] as String? ?? 
                     widget.plant['name'] as String? ?? 
                     'Bilinmeyen Bitki',
      };

      // Analiz geçmişine ekle
      final historyJson = prefs.getString('plant_analysis_history_$plantId') ?? '[]';
      final history = List<Map<String, dynamic>>.from(
        jsonDecode(historyJson) as List
      );
      
      history.insert(0, chatEntry);
      await prefs.setString('plant_analysis_history_$plantId', jsonEncode(history));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Sohbet kaydedildi!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.of(context).pop(true); // Bitki detay sayfasını yenilemek için true döndür
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                // Sohbeti Kaydet butonu
                IconButton(
                  onPressed: _messages.isNotEmpty ? _saveChat : null,
                  icon: const Icon(Icons.bookmark_outline),
                  tooltip: 'Sohbeti Kaydet',
                  color: AppColors.primary,
                ),
                const Spacer(),
                Text(
                  'Yapay Zeka Asistanı',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: _isInitializing
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final message = _messages[index];
                      final isUser = message['role'] == 'user';
                      return _buildMessageBubble(message, isUser);
                    },
                  ),
          ),
          // Hızlı Mesaj Baloncukları
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              border: Border(
                top: BorderSide(color: AppColors.border, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickMessageBubble(
                    'Bitkimin durumu ne?',
                    () {
                      _messageController.text = 'Bitkimin durumu ne?';
                      _sendMessage();
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickMessageBubble(
                    'Bakım rutini nasıl olmalı?',
                    () {
                      _messageController.text = 'Bakım rutini nasıl olmalı?';
                      _sendMessage();
                    },
                  ),
                ],
              ),
            ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Mesajınızı yazın...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                  color: AppColors.primary,
                  disabledColor: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMessageBubble(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isUser) {
    final content = message['content'] as String? ?? '';
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : null,
            bottomLeft: !isUser ? const Radius.circular(4) : null,
          ),
        ),
        child: isUser
            ? Text(
                content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                    ),
              )
            : MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                  strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  listBullet: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                  h1: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  h2: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                  h3: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
      ),
    );
  }
}

// Kontrol ikonu painter (üç yatay çizgi ve her birinin sağında küçük daire)
class _ControlIconPainter extends CustomPainter {
  final Color color;

  _ControlIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final lineSpacing = size.height / 4;
    final lineLength = size.width * 0.6;
    final dotRadius = 2.0;
    final startX = 0.0;
    final startY = lineSpacing;

    // Üç yatay çizgi çiz
    for (int i = 0; i < 3; i++) {
      final y = startY + (i * lineSpacing);
      final lineStart = Offset(startX, y);
      final lineEnd = Offset(startX + lineLength, y);
      
      // Çizgiyi çiz
      canvas.drawLine(lineStart, lineEnd, paint);
      
      // Çizginin sağında küçük daire çiz
      final dotCenter = Offset(startX + lineLength + dotRadius + 2, y);
      canvas.drawCircle(dotCenter, dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

