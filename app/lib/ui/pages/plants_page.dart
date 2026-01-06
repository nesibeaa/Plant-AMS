import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../theme/app_theme.dart';
import 'plant_detail_page.dart';
import '../../services/notification_service.dart';

class PlantsPage extends StatefulWidget {
  final bool showHistory;
  const PlantsPage({super.key, this.showHistory = false});
  @override
  State<PlantsPage> createState() => _PlantsPageState();
}

class _PlantsPageState extends State<PlantsPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _savedPlants = [];
  List<Map<String, dynamic>> _deletedPlants = [];
  Set<String> _favoriteIds = {};
  bool _isLoading = true;
  int _selectedTab = 0; // 0: Benim Bahçem (artık sadece bu var)
  bool _showFavoritesOnly = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _selectedPlantIds = {}; // Seçili bitki ID'leri
  bool _isSelectionMode = false; // Seçim modu aktif mi?

  @override
  void initState() {
    super.initState();
    if (widget.showHistory) {
      _selectedTab = 1;
    }
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Aktif bitkileri yükle
      final savedPlantsJson = prefs.getString('saved_plants') ?? '[]';
      final savedPlants = List<Map<String, dynamic>>.from(
        jsonDecode(savedPlantsJson) as List
      );
      
      // Silinmiş bitkileri yükle (geçmiş)
      final deletedPlantsJson = prefs.getString('deleted_plants') ?? '[]';
      final deletedPlants = List<Map<String, dynamic>>.from(
        jsonDecode(deletedPlantsJson) as List
      );
      
      // Favori ID'leri yükle
      final favoriteIdsJson = prefs.getString('favorite_plant_ids') ?? '[]';
      final favoriteIdsList = List<String>.from(
        jsonDecode(favoriteIdsJson) as List
      );
      final favoriteIds = favoriteIdsList.toSet();
      
      setState(() {
        _savedPlants = savedPlants;
        _deletedPlants = deletedPlants;
        _favoriteIds = favoriteIds;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFavorite(String plantId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_favoriteIds.contains(plantId)) {
        _favoriteIds.remove(plantId);
      } else {
        _favoriteIds.add(plantId);
      }
      
      await prefs.setString('favorite_plant_ids', jsonEncode(_favoriteIds.toList()));
      setState(() {});
    } catch (e) {
      // Hata durumunda sessizce devam et
    }
  }

  Future<void> _moveToHistory(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Bitkiyi bul
      final plant = _savedPlants.firstWhere((p) => p['id'] == id);
      
      // Bildirimleri iptal et
      final notificationService = NotificationService();
      await notificationService.cancelNotification(id, 'watering');
      await notificationService.cancelNotification(id, 'fertilization');
      
      // Aktif listeden kaldır
      _savedPlants.removeWhere((plant) => plant['id'] == id);
      await prefs.setString('saved_plants', jsonEncode(_savedPlants));
      
      // Geçmişe ekle (zaman damgası ekle)
      final deletedPlant = {
        ...plant,
        'deletedAt': DateTime.now().toIso8601String(),
      };
      _deletedPlants.add(deletedPlant);
      await prefs.setString('deleted_plants', jsonEncode(_deletedPlants));
      
      setState(() {});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bitki geçmişe taşındı'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _deletePermanently(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Bildirimleri iptal et
      final notificationService = NotificationService();
      await notificationService.cancelNotification(id, 'watering');
      await notificationService.cancelNotification(id, 'fertilization');
      
      // Geçmişten kaldır
      _deletedPlants.removeWhere((plant) => plant['id'] == id);
      await prefs.setString('deleted_plants', jsonEncode(_deletedPlants));
      
      // Favorilerden de kaldır
      _favoriteIds.remove(id);
      await prefs.setString('favorite_plant_ids', jsonEncode(_favoriteIds.toList()));
      
      setState(() {});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bitki kalıcı olarak silindi'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // Bitkileri filtrele (arama, favori, sekme)
  List<Map<String, dynamic>> get _displayedPlants {
    final plants = _selectedTab == 0 ? _savedPlants : _deletedPlants;
    List<Map<String, dynamic>> filteredPlants;
    
    // Favori filtresi
    if (_selectedTab == 0 && _showFavoritesOnly) {
      filteredPlants = plants.where((plant) => _favoriteIds.contains(plant['id'])).toList();
    } else {
      filteredPlants = List.from(plants);
    }
    
    // Arama filtresi
    if (_searchQuery.isNotEmpty) {
      filteredPlants = filteredPlants.where((plant) {
        final nickname = (plant['name'] as String? ?? '').toLowerCase();
        final plantType = (plant['originalPlantType'] as String? ?? 
                          plant['plantType'] as String? ?? '').toLowerCase();
        
        // Bitki türü ismi veya nickname'e göre ara
        return nickname.contains(_searchQuery) || plantType.contains(_searchQuery);
      }).toList();
    }
    
    // savedAt tarihine göre sırala (en yeni en üstte)
    filteredPlants.sort((a, b) {
      final dateA = a['savedAt'] as String? ?? '';
      final dateB = b['savedAt'] as String? ?? '';
      // Tarih string'lerini karşılaştır (ISO8601 formatında)
      // En yeni tarih önce gelmeli (descending order)
      return dateB.compareTo(dateA);
    });
    
    return filteredPlants;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        backgroundColor: AppColors.cardBackground,
        color: AppColors.primary,
        child: Column(
          children: [
            const SizedBox(height: 2),
            // Başlık - Ortalanmış
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Yazı
                          Text(
                            _selectedTab == 0 ? 'Bahçem' : 'Geçmiş',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Sağ ikon
                          Image.asset(
                            'assets/icon/Bahçe.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.local_florist,
                                size: 24,
                                color: AppColors.primary,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Kapatma butonu (sadece geçmiş sayfasında)
                  if (widget.showHistory || _selectedTab == 1)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(
                              Icons.close,
                              color: AppColors.textSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Arama çubuğu ve filtreler
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _searchQuery.isNotEmpty 
                              ? AppColors.primary.withOpacity(0.3)
                              : AppColors.border,
                          width: _searchQuery.isNotEmpty ? 1.5 : 1,
                        ),
                        boxShadow: _searchQuery.isNotEmpty
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            color: _searchQuery.isNotEmpty 
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Bitki türü veya isim ara...',
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _searchQuery = value.toLowerCase().trim();
                                });
                              },
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  color: AppColors.textSecondary,
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Favori filtresi (sadece Benim Bahçem sekmesinde)
                  if (_selectedTab == 0)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showFavoritesOnly = !_showFavoritesOnly;
                        });
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _showFavoritesOnly 
                              ? AppColors.primary.withOpacity(0.2)
                              : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _showFavoritesOnly 
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Icon(
                          Icons.favorite,
                          color: _showFavoritesOnly 
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
                    ),
                  // Üç nokta menü
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(
                        Icons.more_vert,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                    onSelected: (value) {
                      if (value == 'select') {
                        setState(() {
                          _isSelectionMode = true;
                        });
                      } else if (value == 'delete_selected') {
                        _showDeleteSelectedDialog();
                      } else if (value == 'remove_selected') {
                        _showRemoveSelectedDialog();
                      }
                    },
                    itemBuilder: (context) => [
                      if (!_isSelectionMode)
                        PopupMenuItem(
                          value: 'select',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle_outline, size: 20, color: AppColors.primary),
                              const SizedBox(width: 12),
                              const Text(
                                'Seç',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      if (_isSelectionMode && _selectedPlantIds.isNotEmpty)
                        PopupMenuItem(
                          value: _selectedTab == 0 ? 'delete_selected' : 'remove_selected',
                          child: Row(
                            children: [
                              Icon(
                                _selectedTab == 0 ? Icons.delete_outline : Icons.delete_forever,
                                size: 20,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _selectedTab == 0 ? 'Seçilenleri sil' : 'Seçilenleri kaldır',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ],
                          ),
                        ),
                      if (_isSelectionMode)
                        PopupMenuItem(
                          value: 'cancel_selection',
                          onTap: () {
                            Future.delayed(Duration.zero, () {
                              setState(() {
                                _isSelectionMode = false;
                                _selectedPlantIds.clear();
                              });
                            });
                          },
                          child: Row(
                            children: [
                              Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              const Text('Seçimi iptal et'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Seçim modu bilgi çubuğu
            if (_isSelectionMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedPlantIds.length} bitki seçildi',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedPlantIds.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          if (_selectedTab == 0) {
                            _showDeleteSelectedDialog();
                          } else {
                            _showRemoveSelectedDialog();
                          }
                        },
                        icon: Icon(
                          _selectedTab == 0 ? Icons.delete_outline : Icons.delete_forever,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        label: Text(
                          _selectedTab == 0 ? 'Sil' : 'Kaldır',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSelectionMode = false;
                          _selectedPlantIds.clear();
                        });
                      },
                      child: Text(
                        'İptal',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // İçerik
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _displayedPlants.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _displayedPlants.length,
                          itemBuilder: (context, index) {
                            return _buildPlantCard(_displayedPlants[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String message;
    String subtitle;
    
    if (_searchQuery.isNotEmpty) {
      message = 'Arama sonucu bulunamadı';
      subtitle = 'Farklı bir arama terimi deneyin';
    } else if (_selectedTab == 0) {
      message = _showFavoritesOnly 
          ? 'Henüz favori bitki yok'
          : 'Henüz bitki kaydedilmedi';
      subtitle = _showFavoritesOnly
          ? 'Bitkilere kalp işaretine basarak favorileyebilirsiniz'
          : 'Analiz sayfasından bitki analizi yapıp kaydedebilirsiniz';
    } else {
      message = 'Geçmişte bitki yok';
      subtitle = 'Silinen bitkiler burada görünecek';
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_florist_outlined,
                  size: 64,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlantCard(Map<String, dynamic> plant) {
    final nickname = plant['name'] as String? ?? 'Bilinmeyen Bitki'; // Kullanıcının verdiği nickname
    final originalPlantType = plant['originalPlantType'] as String? ?? plant['plantType'] as String? ?? nickname; // Gerçek bitki türü
    final isHealthy = plant['isHealthy'] as bool? ?? false;
    final disease = plant['disease'] as String? ?? '';
    final plantId = plant['id'] as String;
    final isFavorite = _favoriteIds.contains(plantId);
    final imagePath = plant['imagePath'] as String?;

    // Hastalık bilgisi doğrudan disease alanından geliyor (artık ayrı kaydediliyor)
    String? diseaseName;
    if (!isHealthy && disease.isNotEmpty) {
      diseaseName = disease;
    }

    final isSelected = _selectedPlantIds.contains(plantId);
    
    return InkWell(
      onTap: () async {
        if (_isSelectionMode) {
          // Seçim modunda: bitkiyi seç/seçimi kaldır
          setState(() {
            if (isSelected) {
              _selectedPlantIds.remove(plantId);
            } else {
              _selectedPlantIds.add(plantId);
            }
            // Eğer hiç seçili bitki kalmadıysa seçim modunu kapat
            if (_selectedPlantIds.isEmpty) {
              _isSelectionMode = false;
            }
          });
        } else {
          // Normal modda: bitki detay sayfasına git
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PlantDetailPage(plant: plant),
            ),
          );
          if (result == true) {
            _loadData(); // Bitki güncellendiğinde listeyi yenile
          }
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: _isSelectionMode && isSelected
              ? Border.all(color: AppColors.primary, width: 2)
              : Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Seçim checkbox (seçim modunda)
            if (_isSelectionMode)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  size: 24,
                ),
              ),
            // Bitki resmi veya ikon
            Container(
              width: 80,
              height: 80,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: imagePath != null && File(imagePath).existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.eco_outlined,
                          color: AppColors.primary,
                          size: 32,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.eco_outlined,
                      color: AppColors.primary,
                      size: 32,
                    ),
            ),
            // Bitki bilgileri
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nickname (üstte)
                    Text(
                      nickname,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Bitki türü (altta, daha küçük)
                    if (originalPlantType != nickname)
                      Text(
                        originalPlantType,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    // Sağlık durumu veya hastalık
                    Row(
                      children: [
                        if (isHealthy) ...[
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Durumu iyi',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.success,
                                  fontSize: 13,
                                ),
                          ),
                        ] else if (diseaseName != null && diseaseName.isNotEmpty) ...[
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              diseaseName,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.warning,
                                    fontSize: 13,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Favori butonu (sadece aktif listede ve seçim modu kapalıyken)
            if (_selectedTab == 0 && !_isSelectionMode)
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? AppColors.danger : AppColors.textSecondary,
                ),
                onPressed: () => _toggleFavorite(plantId),
              ),
            // Silme butonu (sadece Geçmiş sekmesinde ve seçim modu kapalıyken göster)
            if (_selectedTab == 1 && !_isSelectionMode)
              IconButton(
                icon: Icon(
                  Icons.delete_forever,
                  color: AppColors.danger,
                ),
                onPressed: () => _showDeletePermanentlyDialog(plantId),
              ),
          ],
        ),
      ),
    );
  }

  void _showMoveToHistoryDialog(String plantId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bitkiyi Geçmişe Taşı'),
        content: const Text('Bu bitkiyi geçmişe taşımak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'İptal',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _moveToHistory(plantId);
            },
            child: Text(
              'Taşı',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletePermanentlyDialog(String plantId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bitkiyi Kalıcı Olarak Sil'),
        content: const Text('Bu bitkiyi kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'İptal',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deletePermanently(plantId);
            },
            child: Text(
              'Kalıcı Olarak Sil',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteSelectedDialog() {
    if (_selectedPlantIds.isEmpty) return;
    
    final count = _selectedPlantIds.length;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Seçilen Bitkileri Sil'),
        content: Text('$count bitkiyi geçmişe taşımak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'İptal',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteSelected();
            },
            child: Text(
              'Sil',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveSelectedDialog() {
    if (_selectedPlantIds.isEmpty) return;
    
    final count = _selectedPlantIds.length;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Seçilen Bitkileri Kaldır'),
        content: Text('$count bitkiyi kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'İptal',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeSelected();
            },
            child: Text(
              'Kaldır',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    try {
      final count = _selectedPlantIds.length;
      final selectedIds = List<String>.from(_selectedPlantIds);
      
      for (String plantId in selectedIds) {
        await _moveToHistory(plantId);
      }
      
      setState(() {
        _selectedPlantIds.clear();
        _isSelectionMode = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count bitki geçmişe taşındı'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print('❌ Seçilen bitkileri silme hatası: $e');
    }
  }

  Future<void> _removeSelected() async {
    try {
      final count = _selectedPlantIds.length;
      final selectedIds = List<String>.from(_selectedPlantIds);
      
      for (String plantId in selectedIds) {
        await _deletePermanently(plantId);
      }
      
      setState(() {
        _selectedPlantIds.clear();
        _isSelectionMode = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count bitki kalıcı olarak silindi'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print('❌ Seçilen bitkileri kaldırma hatası: $e');
    }
  }
}
