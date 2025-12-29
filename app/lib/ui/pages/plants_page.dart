import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../theme/app_theme.dart';
import 'plant_detail_page.dart';

class PlantsPage extends StatefulWidget {
  const PlantsPage({super.key});
  @override
  State<PlantsPage> createState() => _PlantsPageState();
}

class _PlantsPageState extends State<PlantsPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _savedPlants = [];
  List<Map<String, dynamic>> _deletedPlants = [];
  Set<String> _favoriteIds = {};
  bool _isLoading = true;
  int _selectedTab = 0; // 0: Benim Bahçem, 1: Snap Geçmişi
  bool _showFavoritesOnly = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTab = _tabController.index;
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  List<Map<String, dynamic>> get _displayedPlants {
    final plants = _selectedTab == 0 ? _savedPlants : _deletedPlants;
    List<Map<String, dynamic>> filteredPlants;
    
    if (_selectedTab == 0 && _showFavoritesOnly) {
      filteredPlants = plants.where((plant) => _favoriteIds.contains(plant['id'])).toList();
    } else {
      filteredPlants = List.from(plants);
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
            const SizedBox(height: 8),
            // Tab Bar
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Benim Bahçem'),
                Tab(text: 'Geçmiş'),
              ],
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
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Bitkileri ara',
                                hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
                  // Diğer ikonlar
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      Icons.access_time,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
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
    final message = _selectedTab == 0
        ? (_showFavoritesOnly 
            ? 'Henüz favori bitki yok'
            : 'Henüz bitki kaydedilmedi')
        : 'Geçmişte bitki yok';
    final subtitle = _selectedTab == 0
        ? (_showFavoritesOnly
            ? 'Bitkilere kalp işaretine basarak favorileyebilirsiniz'
            : 'Analiz sayfasından bitki analizi yapıp kaydedebilirsiniz')
        : 'Silinen bitkiler burada görünecek';

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

    return InkWell(
      onTap: () async {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PlantDetailPage(plant: plant),
          ),
        );
        if (result == true) {
          _loadData(); // Bitki güncellendiğinde listeyi yenile
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
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
            // Favori butonu (sadece aktif listede)
            if (_selectedTab == 0)
              IconButton(
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: isFavorite ? AppColors.danger : AppColors.textSecondary,
                ),
                onPressed: () => _toggleFavorite(plantId),
              ),
            // Silme butonu
            IconButton(
              icon: Icon(
                _selectedTab == 0 ? Icons.delete_outline : Icons.delete_forever,
                color: AppColors.danger,
              ),
              onPressed: () => _selectedTab == 0
                  ? _showMoveToHistoryDialog(plantId)
                  : _showDeletePermanentlyDialog(plantId),
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
}
