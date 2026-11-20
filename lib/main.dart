import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const App());

const aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

String tl(double v) {
  final parts = v.abs().toStringAsFixed(2).split('.');
  final ip = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) b.write('.');
    b.write(ip[i]);
  }
  final neg = v < -0.004;
  return '${neg ? '-' : ''}$b,${parts[1]} ₺';
}

String ds(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
double num2(dynamic v) => (v as num).toDouble();
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

// ---------- Renkler (pastel) ----------
const palette = [
  Color(0xFF93C5FD),
  Color(0xFFFCA5A5),
  Color(0xFF6EE7B7),
  Color(0xFFFCD34D),
  Color(0xFFC4B5FD),
  Color(0xFFF9A8D4),
  Color(0xFF67E8F9),
  Color(0xFFFDBA74),
  Color(0xFFBEF264),
  Color(0xFFCBD5E1),
];
Color colorAt(int i) => palette[i % palette.length];

// Pastel zeminlerin üstündeki yazı/ikon rengi
const ink = Color(0xFF1E1B2E);

// Sekme renkleri: Stok, Alış, Satış, Gider, Rapor, Yedek (hepsi paletten)
const tabColors = [
  Color(0xFFC4B5FD), // lavanta
  Color(0xFFFDBA74), // şeftali
  Color(0xFF6EE7B7), // nane
  Color(0xFFFCA5A5), // mercan
  Color(0xFF93C5FD), // gökyüzü
  Color(0xFFCBD5E1), // gri-mavi
];
const tabIcons = [
  Icons.inventory_2_outlined,
  Icons.add_shopping_cart,
  Icons.sell_outlined,
  Icons.receipt_long_outlined,
  Icons.bar_chart,
  Icons.backup_outlined,
];

const pGreen = Color(0xFF6EE7B7);
const pRed = Color(0xFFFCA5A5);
const pBlue = Color(0xFF93C5FD);
const pOrange = Color(0xFFFDBA74);
const pPurple = Color(0xFFC4B5FD);
const pYellow = Color(0xFFFCD34D);

// Pastel rengin açık temada okunur koyu tonu, koyu temada kendisi
Color tone(BuildContext c, Color x) => Theme.of(c).brightness == Brightness.dark
    ? x
    : HSLColor.fromColor(x).withLightness(0.30).withSaturation(0.55).toColor();

// ---------- Veri ----------
class Data {
  List<Map<String, dynamic>> products = [], purchases = [], sales = [], expenses = [], adjustments = [];
  int nextId = 1;
  String? lastBackup;

  void load(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) =>
        ((j[k] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    products = l('products');
    purchases = l('purchases');
    sales = l('sales');
    expenses = l('expenses');
    adjustments = l('adjustments');
    lastBackup = j['lastBackup'] as String?;
    var maxId = 0;
    for (final list in [products, purchases, sales, expenses, adjustments]) {
      for (final e in list) {
        if ((e['id'] as int) > maxId) maxId = e['id'] as int;
      }
    }
    final n = (j['nextId'] ?? 1) as int;
    nextId = n > maxId ? n : maxId + 1;
  }

  Map<String, dynamic> toJson() => {
        'products': products,
        'purchases': purchases,
        'sales': sales,
        'expenses': expenses,
        'adjustments': adjustments,
        'nextId': nextId,
        'lastBackup': lastBackup,
      };

  bool get hasData => purchases.isNotEmpty || sales.isNotEmpty;

  int stock(int pid) {
    var s = 0;
    for (final e in purchases) {
      if (e['pid'] == pid) s += e['qty'] as int;
    }
    for (final e in sales) {
      if (e['pid'] == pid) s -= e['qty'] as int;
    }
    for (final e in adjustments) {
      if (e['pid'] == pid) s += e['qty'] as int;
    }
    return s;
  }

  double avgCost(int pid) {
    var q = 0;
    var t = 0.0;
    for (final e in purchases) {
      if (e['pid'] == pid) {
        q += e['qty'] as int;
        t += (e['qty'] as int) * num2(e['price']);
      }
    }
    return q == 0 ? 0 : t / q;
  }

  String name(int pid) {
    for (final p in products) {
      if (p['id'] == pid) return p['name'] as String;
    }
    return '(silinmiş)';
  }

  Color colorOf(int pid) {
    for (final p in products) {
      if (p['id'] == pid) {
        final c = p['color'];
        return colorAt(c is int ? c : pid);
      }
    }
    return Colors.grey;
  }
}

Future<File> dataFile() async => File('${(await getApplicationDocumentsDirectory()).path}/anahtarlik.json');

// ---------- Uygulama ----------
ThemeData buildTheme(Brightness b) {
  final base = ThemeData(colorSchemeSeed: const Color(0xFFC4B5FD), brightness: b, useMaterial3: true);
  return base.copyWith(textTheme: GoogleFonts.nunitoTextTheme(base.textTheme));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KeyFlow',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Data d = Data();
  int tab = 0;
  bool ready = false, loadError = false;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  int period = 0;
  static const pad = EdgeInsets.fromLTRB(12, 12, 12, 90);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await dataFile();
    if (await f.exists()) {
      try {
        d = Data()..load(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        await f.copy('${f.path}.bozuk');
        loadError = true;
      }
    }
    setState(() => ready = true);
  }

  Future<void> save() async {
    final f = await dataFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(d.toJson()), flush: true);
    await tmp.rename(f.path);
  }

  void change(VoidCallback fn) {
    setState(fn);
    save();
  }

  void snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> confirm(String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Evet')),
          ],
        ),
      ) ??
      false;

  // ----- Formlar -----
  String priceText(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String lastPrice(bool sale, int pid) {
    final l = sorted(sale ? d.sales : d.purchases).where((e) => e['pid'] == pid).toList();
    return l.isEmpty ? '' : priceText(num2(l.first['price']));
  }

  int nextColor() {
    final used = d.products.map((p) => p['color'] is int ? p['color'] as int : (p['id'] as int) % palette.length).toSet();
    for (var i = 0; i < palette.length; i++) {
      if (!used.contains(i)) return i;
    }
    return d.products.length % palette.length;
  }

  Future<void> addProduct() => productDialog();
  Future<void> renameProduct(Map<String, dynamic> p) => productDialog(edit: p);

  Future<void> productDialog({Map<String, dynamic>? edit}) async {
    final name = TextEditingController(text: (edit?['name'] as String?) ?? '');
    final qty = TextEditingController();
    final price = TextEditingController();
    var color = edit == null ? nextColor() : ((edit['color'] as int?) ?? (edit['id'] as int) % palette.length);
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (x, set) => AlertDialog(
          title: Text(edit == null ? 'Yeni çeşit' : 'Çeşidi düzenle'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: name,
                autofocus: edit == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Çeşit adı', hintText: 'Örn. Kedi'),
              ),
              const SizedBox(height: 16),
              const Text('Renk'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < palette.length; i++)
                  GestureDetector(
                    onTap: () => set(() => color = i),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: palette[i],
                      child: color == i ? const Icon(Icons.check, size: 18, color: ink) : null,
                    ),
                  ),
              ]),
              if (edit == null) ...[
                const SizedBox(height: 16),
                const Text('Elindeki stok (isteğe bağlı)'),
                Row(children: [
                  Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Adet'))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Alış fiyatı ₺'),
                    ),
                  ),
                ]),
              ],
              if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: Theme.of(x).colorScheme.error))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  set(() => err = 'Çeşit adını yaz.');
                  return;
                }
                if (edit == null) {
                  final q = qty.text.trim().isEmpty ? 0 : int.tryParse(qty.text.trim());
                  if (q == null || q < 0) {
                    set(() => err = 'Adedi doğru yaz.');
                    return;
                  }
                  final pr = parseNum(price.text);
                  if (q > 0 && (pr == null || pr < 0)) {
                    set(() => err = 'Stok girdiysen alış fiyatını da yaz (yaklaşık olabilir).');
                    return;
                  }
                }
                Navigator.pop(x, true);
              },
              child: Text(edit == null ? 'Ekle' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = name.text.trim();
    if (edit != null) {
      change(() {
        edit['name'] = n;
        edit['color'] = color;
      });
      return;
    }
    final q = int.tryParse(qty.text.trim()) ?? 0;
    final pr = parseNum(price.text) ?? 0;
    change(() {
      final id = d.nextId++;
      d.products.add({'id': id, 'name': n, 'color': color});
      if (q > 0) {
        d.purchases.add({'id': d.nextId++, 'pid': id, 'qty': q, 'price': pr, 'date': ds(DateTime.now()), 'note': 'Başlangıç stoku'});
      }
    });
  }

  Future<void> deleteProduct(Map<String, dynamic> p) async {
    final id = p['id'];
    if (d.purchases.any((e) => e['pid'] == id) || d.sales.any((e) => e['pid'] == id)) {
      snack('Önce bu çeşidin alış/satış kayıtlarını sil.');
      return;
    }
    if (await confirm('${p['name']} silinsin mi?')) {
      change(() {
        d.products.remove(p);
        d.adjustments.removeWhere((e) => e['pid'] == id);
      });
    }
  }

  Future<void> adjustStock(Map<String, dynamic> p) async {
    final id = p['id'] as int;
    final cur = d.stock(id);
    final c = TextEditingController(text: '$cur');
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Stok sayımı'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['name']}: kayıtlara göre $cur adet görünüyor.'),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Gerçekte kaç tane var?'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;
    final n = int.tryParse(c.text.trim());
    if (n == null || n < 0) {
      snack('Geçerli bir adet gir.');
      return;
    }
    final diff = n - cur;
    if (diff == 0) return;
    change(() => d.adjustments.add({'id': d.nextId++, 'pid': id, 'qty': diff, 'date': ds(DateTime.now())}));
    snack('Stok $n olarak düzeltildi.');
  }

  Future<void> productSheet(Map<String, dynamic> p) async {
    final id = p['id'] as int;
    await showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: CircleAvatar(backgroundColor: d.colorOf(id), child: const Icon(Icons.vpn_key, color: ink, size: 20)),
            title: Text(p['name'] as String, style: Theme.of(c).textTheme.titleLarge),
            subtitle: Text('Stok ${d.stock(id)} · ort. alış ${tl(d.avgCost(id))}'),
          ),
          ListTile(leading: const Icon(Icons.sell_outlined), title: const Text('Satış ekle'), onTap: () { Navigator.pop(c); tradeSheet(true, pid: id); }),
          ListTile(leading: const Icon(Icons.add_shopping_cart), title: const Text('Alış ekle'), onTap: () { Navigator.pop(c); tradeSheet(false, pid: id); }),
          ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('Stok düzelt (sayım)'), onTap: () { Navigator.pop(c); adjustStock(p); }),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Ad ve rengi değiştir'), onTap: () { Navigator.pop(c); renameProduct(p); }),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Sil'), onTap: () { Navigator.pop(c); deleteProduct(p); }),
        ]),
      ),
    );
  }

  Future<DateTime?> pickDate(BuildContext c, DateTime init) =>
      showDatePicker(context: c, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2100));

  Future<void> tradeSheet(bool sale, {int? pid, Map<String, dynamic>? edit}) async {
    if (d.products.isEmpty) {
      snack('Önce Stok sekmesinden çeşit ekle.');
      return;
    }
    var sel = (edit?['pid'] as int?) ?? pid ?? (d.products.first['id'] as int);
    final q = TextEditingController(text: edit == null ? '' : '${edit['qty']}');
    final pr = TextEditingController(text: edit == null ? lastPrice(sale, sel) : priceText(num2(edit['price'])));
    final note = TextEditingController(text: (edit?['note'] as String?) ?? '');
    var date = edit == null ? DateTime.now() : DateTime.parse(edit['date'] as String);
    String? err;
    final title = edit == null ? (sale ? 'Satış ekle' : 'Alış ekle') : (sale ? 'Satışı düzenle' : 'Alışı düzenle');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: Theme.of(c).textTheme.titleLarge),
              DropdownButtonFormField<int>(
                value: sel,
                items: [
                  for (final p in d.products)
                    DropdownMenuItem(
                      value: p['id'] as int,
                      child: Row(children: [
                        Icon(Icons.circle, size: 14, color: d.colorOf(p['id'] as int)),
                        const SizedBox(width: 8),
                        Text('${p['name']} (stok ${d.stock(p['id'] as int)})'),
                      ]),
                    ),
                ],
                onChanged: (v) => set(() {
                  sel = v!;
                  if (edit == null) pr.text = lastPrice(sale, sel);
                }),
              ),
              TextField(controller: q, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Adet')),
              TextField(
                controller: pr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: sale ? 'Satış fiyatı (₺/adet)' : 'Alış fiyatı (₺/adet)',
                  helperText: sale ? 'Hediye ya da kayıp için 0 yaz' : null,
                ),
              ),
              TextField(
                controller: note,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: sale ? 'Müşteri / not (isteğe bağlı)' : 'Not (isteğe bağlı)'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Tarih: ${ds(date)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final x = await pickDate(c, date);
                  if (x != null) set(() => date = x);
                },
              ),
              if (err != null) Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final qty = int.tryParse(q.text.trim());
                    final price = parseNum(pr.text);
                    if (qty == null || qty < 1 || price == null || price < 0) {
                      set(() => err = 'Adet ve fiyatı doğru gir.');
                      return;
                    }
                    final avail = d.stock(sel) + ((edit != null && edit['pid'] == sel) ? (edit['qty'] as int) : 0);
                    if (sale && qty > avail && !await confirm('Stokta $avail tane görünüyor, yine de kaydedilsin mi?')) return;
                    final entry = <String, dynamic>{'pid': sel, 'qty': qty, 'price': price, 'date': ds(date), 'note': note.text.trim()};
                    change(() {
                      if (edit != null) {
                        edit.addAll(entry);
                      } else {
                        (sale ? d.sales : d.purchases).add({'id': d.nextId++, ...entry});
                      }
                    });
                    if (c.mounted) Navigator.pop(c);
                  },
                  child: const Text('Kaydet'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> expenseSheet({Map<String, dynamic>? edit}) async {
    final n = TextEditingController(text: (edit?['note'] as String?) ?? '');
    final a = TextEditingController(text: edit == null ? '' : priceText(num2(edit['amount'])));
    var date = edit == null ? DateTime.now() : DateTime.parse(edit['date'] as String);
    String? err;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(edit == null ? 'Gider ekle' : 'Gideri düzenle', style: Theme.of(c).textTheme.titleLarge),
              TextField(controller: n, decoration: const InputDecoration(labelText: 'Ne için? (kargo, filament, ambalaj...)')),
              TextField(
                controller: a,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tutar (₺)'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Tarih: ${ds(date)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final x = await pickDate(c, date);
                  if (x != null) set(() => date = x);
                },
              ),
              if (err != null) Text(err!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final amount = parseNum(a.text);
                    if (n.text.trim().isEmpty || amount == null || amount < 0) {
                      set(() => err = 'Açıklama ve tutarı doldur.');
                      return;
                    }
                    final entry = <String, dynamic>{'note': n.text.trim(), 'amount': amount, 'date': ds(date)};
                    change(() {
                      if (edit != null) {
                        edit.addAll(entry);
                      } else {
                        d.expenses.add({'id': d.nextId++, ...entry});
                      }
                    });
                    Navigator.pop(c);
                  },
                  child: const Text('Kaydet'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ----- Sayfalar -----
  Future<void> quickSale(int pid) async {
    final lp = lastPrice(true, pid);
    final price = parseNum(lp);
    if (price == null) {
      tradeSheet(true, pid: pid);
      return;
    }
    if (d.stock(pid) <= 0 && !await confirm('Stokta görünmüyor, yine de satış yazılsın mı?')) return;
    final entry = <String, dynamic>{'id': d.nextId++, 'pid': pid, 'qty': 1, 'price': price, 'date': ds(DateTime.now()), 'note': ''};
    change(() => d.sales.add(entry));
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text('Satıldı: ${d.name(pid)} · ${tl(price)}'),
      action: SnackBarAction(label: 'Geri al', onPressed: () => change(() => d.sales.remove(entry))),
    ));
  }

  Widget statCard(IconData icon, Color c, String label, String value) {
    final t = tone(context, c);
    return Card(
      color: c.withAlpha(70),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: t),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: t)),
          ),
        ]),
      ),
    );
  }

  Widget infoRow(IconData icon, Color c, String label, String value) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: c.withAlpha(90), child: Icon(icon, color: tone(context, c))),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
      );

  Widget stokCard(Map<String, dynamic> p) {
    final id = p['id'] as int;
    final st = d.stock(id);
    final cs = Theme.of(context).colorScheme;
    final pc = d.colorOf(id);
    final stColor = st <= 0 ? cs.error : (st <= 3 ? Colors.orange.shade800 : null);
    final avg = 'Ort. alış ${tl(d.avgCost(id))}';
    return Card(
      color: pc.withAlpha(45),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: pc, width: 1.5)),
      child: Column(children: [
        ListTile(
          onTap: () => productSheet(p),
          leading: CircleAvatar(backgroundColor: pc, child: const Icon(Icons.vpn_key, color: ink, size: 20)),
          title: Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          subtitle: Text(st <= 0 ? 'Stok bitti · $avg' : (st <= 3 ? 'Azaldı · $avg' : avg)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (st <= 3) Icon(Icons.warning_amber_rounded, color: stColor),
            const SizedBox(width: 6),
            Text('$st', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: stColor)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: pc, foregroundColor: ink),
                onPressed: () => quickSale(id),
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('1 sattım'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: tone(context, pc), side: BorderSide(color: pc)),
                onPressed: () => tradeSheet(false, pid: id),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Alış ekle'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget stokPage() {
    var total = 0.0, pieces = 0;
    for (final p in d.products) {
      final id = p['id'] as int;
      total += d.stock(id) * d.avgCost(id);
      pieces += d.stock(id);
    }
    final old = d.lastBackup == null || DateTime.now().difference(DateTime.parse(d.lastBackup!)).inDays > 7;
    final ps = [...d.products]..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
    return ListView(padding: pad, children: [
      if (loadError)
        const Card(child: ListTile(title: Text('Veri dosyası okunamadı. Eski dosyanın kopyası saklandı, bana haber ver.'))),
      if (d.hasData && old)
        Card(child: ListTile(title: const Text('Yedek almayı unutma'), subtitle: const Text('Dokun ve yedekle'), onTap: () => setState(() => tab = 5))),
      Row(children: [
        Expanded(child: statCard(Icons.inventory_2, pPurple, 'Eldeki toplam', '$pieces adet')),
        const SizedBox(width: 8),
        Expanded(child: statCard(Icons.savings, pYellow, 'Maliyet değeri', tl(total))),
      ]),
      if (d.products.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Başlamak için:\n\n1) Aşağıdan "Çeşit ekle" ile çeşidin adını, rengini ve elindeki stoğu gir.\n2) Satınca çeşidin altındaki "1 sattım" düğmesine bas.\n3) Yeni mal alınca "Alış ekle" de.\n4) Rapor sekmesinde kârını gör.'),
          ),
        )
      else
        const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 0), child: Text('Çeşide dokun: stok düzelt, ad ve renk değiştir, sil.')),
      for (final p in ps) stokCard(p),
    ]);
  }

  List<Map<String, dynamic>> sorted(List<Map<String, dynamic>> src) => [...src]
    ..sort((a, b) {
      final c = (b['date'] as String).compareTo(a['date'] as String);
      return c != 0 ? c : (b['id'] as int).compareTo(a['id'] as int);
    });

  String tradeSub(Map<String, dynamic> e) {
    final n = (e['note'] as String?) ?? '';
    final base = '${e['date']} · ${e['qty']} adet × ${tl(num2(e['price']))} = ${tl((e['qty'] as int) * num2(e['price']))}';
    return n.isEmpty ? base : '$base\n$n';
  }

  Widget emptyMsg(String m, IconData icon, Color color) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 72, color: color),
            const SizedBox(height: 12),
            Text(m, textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget tradePage(bool sale) {
    final list = sorted(sale ? d.sales : d.purchases);
    if (list.isEmpty) {
      return emptyMsg(
        sale ? 'Henüz satış yok.\nAşağıdan "Satış ekle"ye bas.' : 'Henüz alış yok.\nAşağıdan "Alış ekle"ye bas.',
        sale ? Icons.sell_outlined : Icons.add_shopping_cart,
        sale ? pGreen : pOrange,
      );
    }
    return ListView(padding: pad, children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: Text('Düzeltmek için kayda dokun.')),
      for (final e in list)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            onTap: () => tradeSheet(sale, edit: e),
            leading: CircleAvatar(backgroundColor: d.colorOf(e['pid'] as int), child: Icon(sale ? Icons.sell_outlined : Icons.add_shopping_cart, color: ink, size: 20)),
            isThreeLine: ((e['note'] as String?) ?? '').isNotEmpty,
            title: Text(d.name(e['pid'] as int), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tradeSub(e)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm('Silinsin mi?')) change(() => (sale ? d.sales : d.purchases).remove(e));
              },
            ),
          ),
        ),
    ]);
  }

  Widget giderPage() {
    final list = sorted(d.expenses);
    if (list.isEmpty) return emptyMsg('Henüz gider yok.\nKargo, filament, ambalaj gibi masrafları buraya yaz.', Icons.receipt_long, pRed);
    return ListView(padding: pad, children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: Text('Düzeltmek için kayda dokun.')),
      for (final e in list)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            onTap: () => expenseSheet(edit: e),
            leading: const CircleAvatar(backgroundColor: pRed, child: Icon(Icons.receipt_long, color: ink, size: 20)),
            title: Text(e['note'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${e['date']} · ${tl(num2(e['amount']))}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm('Silinsin mi?')) change(() => d.expenses.remove(e));
              },
            ),
          ),
        ),
    ]);
  }

  void shiftPeriod(int n) => setState(() => month = period == 0 ? DateTime(month.year, month.month + n) : DateTime(month.year + n, month.month));

  Widget raporPage() {
    final key = period == 0 ? '${month.year}-${month.month.toString().padLeft(2, '0')}' : (period == 1 ? '${month.year}' : '');
    final title = period == 0 ? '${aylar[month.month - 1]} ${month.year}' : (period == 1 ? '${month.year} yılı' : 'Tüm zamanlar');
    var rev = 0.0, cogs = 0.0, spent = 0.0, gid = 0.0;
    final rows = <int, List<double>>{};
    for (final e in d.sales) {
      if (!(e['date'] as String).startsWith(key)) continue;
      final pid = e['pid'] as int;
      final qty = e['qty'] as int;
      final r = qty * num2(e['price']);
      final k = qty * d.avgCost(pid);
      rev += r;
      cogs += k;
      final row = rows.putIfAbsent(pid, () => [0, 0, 0]);
      row[0] += qty;
      row[1] += r;
      row[2] += r - k;
    }
    for (final e in d.purchases) {
      if ((e['date'] as String).startsWith(key)) spent += (e['qty'] as int) * num2(e['price']);
    }
    for (final e in d.expenses) {
      if ((e['date'] as String).startsWith(key)) gid += num2(e['amount']);
    }
    final net = rev - cogs - gid;
    final good = tone(context, pGreen), bad = tone(context, pRed);
    final entries = rows.entries.toList()..sort((a, b) => b.value[2].compareTo(a.value[2]));
    return ListView(padding: pad, children: [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Ay')),
          ButtonSegment(value: 1, label: Text('Yıl')),
          ButtonSegment(value: 2, label: Text('Tümü')),
        ],
        selected: {period},
        onSelectionChanged: (s) => setState(() => period = s.first),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        period == 2 ? const SizedBox(width: 48, height: 48) : IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => shiftPeriod(-1)),
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        period == 2 ? const SizedBox(width: 48, height: 48) : IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => shiftPeriod(1)),
      ]),
      Card(
        color: (net >= 0 ? pGreen : pRed).withAlpha(80),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(net >= 0 ? Icons.trending_up : Icons.trending_down, color: net >= 0 ? good : bad),
              const SizedBox(width: 8),
              Text(net >= 0 ? 'Net kâr' : 'Net zarar', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            Text(tl(net), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: net >= 0 ? good : bad)),
          ]),
        ),
      ),
      infoRow(Icons.payments, pBlue, 'Satış geliri', tl(rev)),
      infoRow(Icons.sell, pOrange, 'Satılanın maliyeti', tl(cogs)),
      infoRow(Icons.receipt_long, pRed, 'Diğer giderler', tl(gid)),
      infoRow(Icons.inventory_2, pPurple, 'Yaptırana ödenen (alış)', tl(spent)),
      const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('Çeşit bazında (brüt kâr)', style: TextStyle(fontWeight: FontWeight.w700))),
      if (entries.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Bu dönemde satış yok.')),
      for (final en in entries)
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: d.colorOf(en.key), child: const Icon(Icons.vpn_key, color: ink, size: 18)),
            title: Text(d.name(en.key), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${en.value[0].toInt()} adet · gelir ${tl(en.value[1])}'),
            trailing: Text(tl(en.value[2]), style: TextStyle(fontWeight: FontWeight.w800, color: en.value[2] >= 0 ? good : bad)),
          ),
        ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Maliyet, çeşidin ortalama alış fiyatından hesaplanır. Net kâr = gelir − satılanın maliyeti − diğer giderler. Alış harcaması kâra girmez, sadece ne kadar ödediğini gösterir.'),
      ),
    ]);
  }

  Future<void> backup() async {
    d.lastBackup = ds(DateTime.now());
    setState(() {});
    await save();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/anahtarlik-yedek-${ds(DateTime.now())}.json');
    await f.writeAsString(jsonEncode(d.toJson()));
    await Share.shareXFiles([XFile(f.path)], text: 'Anahtarlık yedek');
  }

  Future<void> restore() async {
    final r = await FilePicker.platform.pickFiles();
    final path = r?.files.single.path;
    if (path == null) return;
    try {
      final j = jsonDecode(await File(path).readAsString());
      if (j is! Map || j['products'] is! List || j['purchases'] is! List || j['sales'] is! List) throw 'gecersiz';
      if (!await confirm('Mevcut veriler silinip yedek yüklenecek. Emin misin?')) return;
      final nd = Data()..load(Map<String, dynamic>.from(j));
      change(() => d = nd);
      snack('Yedek yüklendi.');
    } catch (_) {
      snack('Bu dosya geçerli bir yedek değil.');
    }
  }

  Widget yedekPage() => ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Yedek al', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Telefon değiştirirsen ya da uygulamayı silersen verilerini buradan geri yüklersin. Dosyayı WhatsApp’tan kendine, Drive’a ya da e-postaya gönder.'),
              const SizedBox(height: 6),
              Text('Son yedek: ${d.lastBackup ?? 'hiç alınmadı'}'),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: tabColors[5], foregroundColor: ink),
                onPressed: backup,
                icon: const Icon(Icons.share),
                label: const Text('Yedeği paylaş (WhatsApp, Drive...)'),
              ),
            ]),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Yedekten geri yükle', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Yeni telefonda uygulamayı aç, yedek dosyasını seç.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: restore, icon: const Icon(Icons.upload_file), label: const Text('Yedek dosyası seç')),
            ]),
          ),
        ),
      ]);

  Widget? fab() {
    Widget f(VoidCallback onTap, String label) => FloatingActionButton.extended(
          backgroundColor: tabColors[tab],
          foregroundColor: ink,
          elevation: 2,
          onPressed: onTap,
          icon: const Icon(Icons.add),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    switch (tab) {
      case 0:
        return f(addProduct, 'Çeşit ekle');
      case 1:
        return f(() => tradeSheet(false), 'Alış ekle');
      case 2:
        return f(() => tradeSheet(true), 'Satış ekle');
      case 3:
        return f(expenseSheet, 'Gider ekle');
    }
    return null;
  }

  // ----- Üst başlık -----
  Widget header(String title) {
    final c = tabColors[tab];
    final now = DateTime.now();
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, Color.lerp(c, Colors.white, 0.5)!],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [BoxShadow(color: c.withAlpha(90), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: Colors.white.withAlpha(150), borderRadius: BorderRadius.circular(18)),
              child: Icon(tabIcons[tab], color: ink, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: ink, height: 1.1)),
                const SizedBox(height: 2),
                Text(
                  '${now.day} ${aylar[now.month - 1]} ${now.year}',
                  style: tt.bodyMedium?.copyWith(color: ink.withAlpha(170), fontWeight: FontWeight.w600),
                ),
              ]),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: Colors.white.withAlpha(110), shape: BoxShape.circle),
              child: const Icon(Icons.vpn_key_rounded, color: ink, size: 20),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Stok', 'Alış', 'Satış', 'Gider', 'Rapor', 'Yedek'];
    final List<Widget Function()> pages = [stokPage, () => tradePage(false), () => tradePage(true), giderPage, raporPage, yedekPage];
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Column(children: [
          header(titles[tab]),
          Expanded(child: ready ? pages[tab]() : const Center(child: CircularProgressIndicator())),
        ]),
      ),
      floatingActionButton: ready ? fab() : null,
      bottomNavigationBar: NavigationBar(
        indicatorColor: tabColors[tab].withAlpha(140),
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Stok'),
          NavigationDestination(icon: Icon(Icons.add_shopping_cart), label: 'Alış'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), label: 'Satış'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Gider'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Rapor'),
          NavigationDestination(icon: Icon(Icons.backup_outlined), label: 'Yedek'),
        ],
      ),
    );
  }
}
