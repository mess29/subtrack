import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

// --- YAPILANDIRMA ---
// NOT: Bu anahtarı üretim ortamında güvenli saklayın.
// Google AI Studio'dan alddart run flutter_launcher_iconsığınız anahtarı buraya yapıştırın.
const String apiKey = "AIzaSyBsl0y7sqPBrRi0fBVCoZk5QOm0yZzBQbg";

// KULLANILACAK MODEL İSMİ
// Google AI Studio'da "Get Code" kısmında gördüğünüz model ismidir.
// Alternatifler: 'gemini-1.5-flash', 'gemini-1.5-pro'
const String modelName = 'gemini-2.5-flash';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SubTrackApp());
}

// --- MODEL ---
class Subscription {
  String id;
  String name;
  double price;
  String category;
  int paymentDay; // 1-31

  Subscription({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.paymentDay,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'category': category,
        'paymentDay': paymentDay,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'],
      name: json['name'],
      price: json['price'],
      category: json['category'],
      paymentDay: json['paymentDay'] ?? 1, // Geriye dönük uyumluluk
    );
  }
}

// --- ANA UYGULAMA ---
class SubTrackApp extends StatelessWidget {
  const SubTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SubTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F46E5), // Indigo
          background: const Color(0xFFF8FAFC), // Slate-50
        ),
        textTheme: GoogleFonts.interTextTheme(),
      ),
      home: StreamBuilder<User?>(
        stream: AuthService().user,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) {
            return const MainScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Durum Yönetimi
  List<Subscription> _subscriptions = [];
  bool _isLoadingAI = false;

  // Controller'lar
  final TextEditingController _aiInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // --- VERİ YÖNETİMİ (SharedPreferences) ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? dataString = prefs.getString('subTrackData');

    if (dataString != null) {
      final List<dynamic> jsonList = jsonDecode(dataString);
      setState(() {
        _subscriptions =
            jsonList.map((e) => Subscription.fromJson(e)).toList();
      });
    } else {
      // Dummy Data
      setState(() {
        _subscriptions = [
          Subscription(id: '1', name: 'Netflix', price: 199.99, category: 'Eğlence', paymentDay: 15),
          Subscription(id: '2', name: 'Spotify', price: 59.99, category: 'Müzik', paymentDay: 1),
          Subscription(id: '3', name: 'Adobe CC', price: 355.00, category: 'Yazılım', paymentDay: 25),
        ];
      });
      _saveData();
    }
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final String dataString =
        jsonEncode(_subscriptions.map((e) => e.toJson()).toList());
    await prefs.setString('subTrackData', dataString);
  }

  void _addSubscription(String name, double price, String category, int paymentDay) {
    setState(() {
      _subscriptions.add(Subscription(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        price: price,
        category: category,
        paymentDay: paymentDay,
      ));
    });
    _saveData();
  }

  void _deleteSubscription(String id) {
    setState(() {
      _subscriptions.removeWhere((item) => item.id == id);
    });
    _saveData();
  }

  // --- GEMINI AI İŞLEMLERİ ---
  
  // 1. Smart Fill (Hızlı Doldur)
  Future<void> _performSmartFill(BuildContext context, Function(String, String, String, int) onFill) async {
    if (_aiInputController.text.isEmpty) return;

    setState(() => _isLoadingAI = true);
    
    try {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      
      final prompt = '''
        Aşağıdaki metinden abonelik adı, fiyatı, kategorisini ve varsa ödeme gününü çıkar.
        Metin: "${_aiInputController.text}"
        Kategoriler: Eğlence, Müzik, Yazılım, Eğitim, Diğer.
        Fiyatı sadece sayı olarak ver.
        Ödeme günü (paymentDay) 1 ile 31 arasında bir sayı olsun. Eğer metinde gün yoksa, varsayılan olarak bu ayın kalan günlerinden mantıklı bir gün veya 1 ver.
        JSON formatında cevap ver: {"name": "...", "price": 0, "category": "...", "paymentDay": 1}.
        Sadece JSON ver.
      ''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      String? resultText = response.text;
      if (resultText != null) {
        // Markdown temizliği
        resultText = resultText.replaceAll('```json', '').replaceAll('```', '').trim();
        
        final startIndex = resultText.indexOf('{');
        final endIndex = resultText.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1) {
          resultText = resultText.substring(startIndex, endIndex + 1);
        }

        final Map<String, dynamic> data = jsonDecode(resultText);
        
        onFill(
          data['name'] ?? '',
          data['price'].toString(),
          data['category'] ?? 'Diğer',
          data['paymentDay'] is int ? data['paymentDay'] : 1
        );
        _aiInputController.clear();
      }
    } catch (e) {
      // Hata Detayını Göster
      _showErrorDialog(context, e.toString());
    } finally {
      setState(() => _isLoadingAI = false);
    }
  }

  // 2. AI Advisor (Finans Danışmanı)
  Future<void> _showAIAdvisor(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) {
        return _AIAdvisorDialog(subscriptions: _subscriptions);
      },
    );
  }

  void _showErrorDialog(BuildContext context, String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hata Oluştu"),
        content: SingleChildScrollView(
          child: Text(
            "Gemini API Hatası:\n\n$error\n\nLütfen API Key'inizi ve internet bağlantınızı kontrol edin.",
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Tamam"))
        ],
      ),
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return _buildDashboard();
  }


  // BÖLÜM 2: DASHBOARD
  Widget _buildDashboard() {
    double totalMonthly = _subscriptions.fold(0, (sum, item) => sum + item.price);
    
    // Tarihe göre sıralama (En yakın ödeme en üstte)
    final today = DateTime.now().day;
    _subscriptions.sort((a, b) {
      // Eğer ödeme günü bugünden büyükse (gelecek), küçükse (geçmiş/gelecek ay)
      // Mantık: (Day - Today + 30) % 30 gibi bir modüler aritmetik yerine basitçe:
      
      int daysUntilA = a.paymentDay >= today ? a.paymentDay - today : (30 - today + a.paymentDay);
      int daysUntilB = b.paymentDay >= today ? b.paymentDay - today : (30 - today + b.paymentDay);
      
      return daysUntilA.compareTo(daysUntilB);
    });
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text("SubTrack", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(FontAwesomeIcons.rightFromBracket, color: Colors.grey, size: 20),
            onPressed: () => AuthService().signOut(),
          )
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.indigo),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(FontAwesomeIcons.layerGroup, color: Colors.white, size: 40),
                  SizedBox(height: 10),
                  Text('SubTrack Menu', style: TextStyle(color: Colors.white, fontSize: 24)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(FontAwesomeIcons.wandMagicSparkles, color: Colors.purple),
              title: const Text('AI Finans Danışmanı', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
              onTap: () {
                Navigator.pop(context);
                _showAIAdvisor(context);
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddModal(context),
        label: const Text("Yeni Ekle"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.indigo[600],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Hoşgeldin, Kullanıcı 👋", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Finansal durumun harika görünüyor.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            
            // İstatistik Kartları
            SizedBox(
              height: 140,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildStatCard("Aylık Gider", "₺${totalMonthly.toStringAsFixed(2)}", FontAwesomeIcons.calendarDays, Colors.blue),
                  _buildStatCard("Yıllık Tahmin", "₺${(totalMonthly * 12).toStringAsFixed(2)}", FontAwesomeIcons.sackDollar, Colors.purple),
                  _buildStatCard("Abonelik Sayısı", "${_subscriptions.length} Adet", FontAwesomeIcons.list, Colors.orange),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Grafik ve Liste
            _buildChartSection(),
            const SizedBox(height: 24),
            
            const Text("Aboneliklerim", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _subscriptions.isEmpty 
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Henüz veri yok."))) 
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _subscriptions.length,
                  itemBuilder: (context, index) {
                    final sub = _subscriptions[index];
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getCategoryColor(sub.category).withOpacity(0.1),
                          child: Icon(_getCategoryIcon(sub.category), color: _getCategoryColor(sub.category), size: 20),
                        ),
                        title: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Row(
                          children: [
                            Text(sub.category),
                            const SizedBox(width: 8),
                            _buildNextPaymentBadge(sub.paymentDay),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₺${sub.price.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
                              onPressed: () => _deleteSubscription(sub.id),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
             const SizedBox(height: 80), // Fab için boşluk
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    if (_subscriptions.isEmpty) return const SizedBox.shrink();

    Map<String, double> dataMap = {};
    for (var sub in _subscriptions) {
      if (dataMap.containsKey(sub.category)) {
        dataMap[sub.category] = dataMap[sub.category]! + sub.price;
      } else {
        dataMap[sub.category] = sub.price;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Kategori Dağılımı", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: dataMap.entries.map((e) {
                  return PieChartSectionData(
                    color: _getCategoryColor(e.key),
                    value: e.value,
                    title: '',
                    radius: 50,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 5,
            children: dataMap.keys.map((cat) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: _getCategoryColor(cat), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(cat, style: const TextStyle(fontSize: 12)),
              ],
            )).toList(),
          )
        ],
      ),
    );
  }

  Widget _buildNextPaymentBadge(int day) {
    int today = DateTime.now().day;
    int daysLeft = day >= today ? day - today : (30 - today + day);
    
    Color color;
    String text;

    if (daysLeft == 0) {
      color = Colors.red;
      text = "Bugün";
    } else if (daysLeft == 1) {
      color = Colors.orange;
      text = "Yarın";
    } else if (daysLeft <= 3) {
      color = Colors.orange[300]!;
      text = "$daysLeft gün kaldı";
    } else {
      color = Colors.green[300]!;
      text = "$daysLeft gün";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Eğlence': return Colors.red[400]!;
      case 'Müzik': return Colors.green[400]!;
      case 'Yazılım': return Colors.blue[400]!;
      case 'Eğitim': return Colors.yellow[700]!;
      default: return Colors.grey[400]!;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Eğlence': return FontAwesomeIcons.film;
      case 'Müzik': return FontAwesomeIcons.music;
      case 'Yazılım': return FontAwesomeIcons.laptopCode;
      case 'Eğitim': return FontAwesomeIcons.book;
      default: return FontAwesomeIcons.box;
    }
  }

  // MODAL: EKLEME FORMU
  void _showAddModal(BuildContext context) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final dayController = TextEditingController();
    String selectedCategory = 'Diğer';
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text("Yeni Abonelik Ekle", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
                  ]),
                  
                  // AI Smart Fill
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.purple[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple[100]!)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(FontAwesomeIcons.wandMagicSparkles, size: 14, color: Colors.purple[700]),
                          const SizedBox(width: 6),
                          Text("YAPAY ZEKA İLE DOLDUR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple[700])),
                        ]),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _aiInputController,
                                decoration: const InputDecoration(
                                  hintText: "Örn: Disney Plus 64.90 TL",
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            _isLoadingAI
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[600], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12), tapTargetSize: MaterialTapTargetSize.shrinkWrap, minimumSize: const Size(0, 32)),
                                  onPressed: () {
                                    setModalState(() => _isLoadingAI = true); // Modal state güncelle
                                    _performSmartFill(context, (name, price, category, day) {
                                      nameController.text = name;
                                      priceController.text = price;
                                      dayController.text = day.toString();
                                      setModalState(() {
                                        selectedCategory = category;
                                        _isLoadingAI = false;
                                      });
                                    }).then((_) => setModalState(() => _isLoadingAI = false));
                                  },
                                  child: const Text("Doldur", style: TextStyle(fontSize: 12)),
                                )
                          ],
                        )
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Platform Adı", border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Boş bırakılamaz" : null,
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: "Fiyat (TL)", border: OutlineInputBorder()),
                          validator: (v) => v!.isEmpty ? "Gerekli" : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: dayController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Ödeme Günü (1-31)", border: OutlineInputBorder()),
                          validator: (v) {
                            if (v == null || v.isEmpty) return "Gerekli";
                            final n = int.tryParse(v);
                            if (n == null || n < 1 || n > 31) return "Geçersiz";
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: "Kategori", border: OutlineInputBorder()),
                    items: ['Eğlence', 'Müzik', 'Yazılım', 'Eğitim', 'Diğer'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => selectedCategory = v!),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                      onPressed: () {
                        if (formKey.currentState!.validate()) {
                          _addSubscription(
                              nameController.text, 
                              double.parse(priceController.text.replaceAll(',', '.')), 
                              selectedCategory,
                              int.parse(dayController.text)
                          );
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Kaydet"),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}

// DIALOG: AI ADVISOR
class _AIAdvisorDialog extends StatefulWidget {
  final List<Subscription> subscriptions;
  const _AIAdvisorDialog({required this.subscriptions});

  @override
  State<_AIAdvisorDialog> createState() => _AIAdvisorDialogState();
}

class _AIAdvisorDialogState extends State<_AIAdvisorDialog> {
  bool isLoading = false;
  String? result;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 500,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [
                  Icon(FontAwesomeIcons.brain, color: Colors.purple),
                  SizedBox(width: 10),
                  Text("AI Danışman", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
              ],
            ),
            const Divider(),
            Expanded(
              child: isLoading
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text("Analiz ediliyor...")]))
                  : result != null
                      ? Markdown(data: result!)
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(FontAwesomeIcons.wandMagicSparkles, size: 50, color: Colors.grey),
                              const SizedBox(height: 20),
                              const Text("Aboneliklerini analiz etmemi ister misin?", textAlign: TextAlign.center),
                              const SizedBox(height: 20),
                              ElevatedButton(
                                onPressed: _analyze,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                                child: const Text("Analizi Başlat"),
                              )
                            ],
                          ),
                        ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _analyze() async {
    setState(() => isLoading = true);
    
    try {
      final model = GenerativeModel(model: modelName, apiKey: apiKey);
      final jsonList = widget.subscriptions.map((e) => e.toJson()).toList().toString();
      
      final prompt = '''
        Sen uzman bir finans danışmanısın. Aşağıdaki listeyi analiz et:
        $jsonList
        
        Türkçe olarak şunları Markdown formatında yaz:
        1. **Genel Bakış**: 1 cümlelik özet.
        2. **Tasarruf Fırsatları**: 2-3 madde.
        3. **Tavsiye**: 1 genel tavsiye.
        
        Samimi ol.
      ''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      setState(() {
        result = response.text;
      });
    } catch (e) {
      // Hata Detayını Göster
      setState(() => result = "Bir hata oluştu:\n$e");
    } finally {
      setState(() => isLoading = false);
    }
  }
}