import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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

// ---------- Veri ----------
class Data {
  List<Map<String, dynamic>> products = [], purchases = [], sales = [], expenses = [];
  int nextId = 1;
  String? lastBackup;

  void load(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) =>
        ((j[k] ?? []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    products = l('products');
    purchases = l('purchases');
    sales = l('sales');
    expenses = l('expenses');
    lastBackup = j['lastBackup'] as String?;
    var maxId = 0;
    for (final list in [products, purchases, sales, expenses]) {
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
}

Future<File> dataFile() async => File('${(await getApplicationDocumentsDirectory()).path}/anahtarlik.json');

// ---------- Uygulama ----------
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Anahtarlık Takip',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF0F766E), useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF0F766E), brightness: Brightness.dark, useMaterial3: true),
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

  Future<void> addProduct() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Yeni çeşit'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Örn. Kedi'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Ekle')),
        ],
      ),
    );
    final n = c.text.trim();
    if (ok == true && n.isNotEmpty) change(() => d.products.add({'id': d.nextId++, 'name': n}));
  }

  Future<void> renameProduct(Map<String, dynamic> p) async {
    final c = TextEditingController(text: p['name'] as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Çeşit adı'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final n = c.text.trim();
    if (ok == true && n.isNotEmpty) change(() => p['name'] = n);
  }

  Future<void> deleteProduct(Map<String, dynamic> p) async {
    final id = p['id'];
    if (d.purchases.any((e) => e['pid'] == id) || d.sales.any((e) => e['pid'] == id)) {
      snack('Önce bu çeşidin alış/satış kayıtlarını sil.');
      return;
    }
    if (await confirm('${p['name']} silinsin mi?')) change(() => d.products.remove(p));
  }

  Future<void> productSheet(Map<String, dynamic> p) async {
    final id = p['id'] as int;
    await showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(p['name'] as String, style: Theme.of(c).textTheme.titleLarge),
            subtitle: Text('Stok ${d.stock(id)} · ort. alış ${tl(d.avgCost(id))}'),
          ),
          ListTile(leading: const Icon(Icons.sell_outlined), title: const Text('Satış ekle'), onTap: () { Navigator.pop(c); tradeSheet(true, pid: id); }),
          ListTile(leading: const Icon(Icons.add_shopping_cart), title: const Text('Alış ekle'), onTap: () { Navigator.pop(c); tradeSheet(false, pid: id); }),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Adını değiştir'), onTap: () { Navigator.pop(c); renameProduct(p); }),
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
                    DropdownMenuItem(value: p['id'] as int, child: Text('${p['name']} (stok ${d.stock(p['id'] as int)})')),
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
  Widget stokPage() {
    var total = 0.0, pieces = 0;
    for (final p in d.products) {
      final id = p['id'] as int;
      total += d.stock(id) * d.avgCost(id);
      pieces += d.stock(id);
    }
    final old = d.lastBackup == null || DateTime.now().difference(DateTime.parse(d.lastBackup!)).inDays > 7;
    final ps = [...d.products]..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
    const big = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
    return ListView(padding: pad, children: [
      if (loadError)
        const Card(child: ListTile(title: Text('Veri dosyası okunamadı. Eski dosyanın kopyası saklandı, bana haber ver.'))),
      if (d.hasData && old)
        Card(child: ListTile(title: const Text('Yedek almayı unutma'), subtitle: const Text('Dokun ve yedekle'), onTap: () => setState(() => tab = 5))),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Eldeki toplam'), Text('$pieces adet', style: big)])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Maliyet değeri'), Text(tl(total), style: big)])),
          ]),
        ),
      ),
      if (d.products.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Başlamak için:\n\n1) Aşağıdan "Çeşit ekle" ile anahtarlık çeşitlerini yaz.\n2) Elindeki koliyi sayıp adetleri "Alış" olarak gir (fiyatı yaklaşık yazabilirsin).\n3) Müşteriye verdikçe "Satış" gir.\n4) Rapor sekmesinde kârını gör.'),
          ),
        )
      else
        const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 0), child: Text('Çeşide dokun: hızlı satış, alış, ad değiştirme, silme.')),
      for (final p in ps)
        Card(
          child: ListTile(
            onTap: () => productSheet(p),
            title: Text(p['name'] as String),
            subtitle: Text('Ort. alış ${tl(d.avgCost(p['id'] as int))}'),
            trailing: Text(
              '${d.stock(p['id'] as int)}',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: d.stock(p['id'] as int) <= 0 ? Theme.of(context).colorScheme.error : (d.stock(p['id'] as int) <= 3 ? Colors.orange : null),
              ),
            ),
          ),
        ),
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

  Widget emptyMsg(String m) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(m, textAlign: TextAlign.center)));

  Widget tradePage(bool sale) {
    final list = sorted(sale ? d.sales : d.purchases);
    if (list.isEmpty) return emptyMsg(sale ? 'Henüz satış yok.\nAşağıdan "Satış ekle"ye bas.' : 'Henüz alış yok.\nAşağıdan "Alış ekle"ye bas.');
    return ListView(padding: pad, children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: Text('Düzeltmek için kayda dokun.')),
      for (final e in list)
        Card(
          child: ListTile(
            onTap: () => tradeSheet(sale, edit: e),
            isThreeLine: ((e['note'] as String?) ?? '').isNotEmpty,
            title: Text(d.name(e['pid'] as int)),
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
    if (list.isEmpty) return emptyMsg('Henüz gider yok.\nKargo, filament, ambalaj gibi masrafları buraya yaz.');
    return ListView(padding: pad, children: [
      const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: Text('Düzeltmek için kayda dokun.')),
      for (final e in list)
        Card(
          child: ListTile(
            onTap: () => expenseSheet(edit: e),
            title: Text(e['note'] as String),
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
    final good = Colors.green.shade600, bad = Theme.of(context).colorScheme.error;
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
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        period == 2 ? const SizedBox(width: 48, height: 48) : IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => shiftPeriod(1)),
      ]),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(net >= 0 ? 'Net kâr' : 'Net zarar'),
            Text(tl(net), style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: net >= 0 ? good : bad)),
          ]),
        ),
      ),
      Card(child: ListTile(title: const Text('Satış geliri'), trailing: Text(tl(rev)))),
      Card(child: ListTile(title: const Text('Satılanın maliyeti'), trailing: Text(tl(cogs)))),
      Card(child: ListTile(title: const Text('Diğer giderler'), trailing: Text(tl(gid)))),
      Card(child: ListTile(title: const Text('Yaptırana ödenen (alış)'), trailing: Text(tl(spent)))),
      const Padding(padding: EdgeInsets.fromLTRB(4, 12, 4, 4), child: Text('Çeşit bazında (brüt kâr)')),
      if (entries.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Bu dönemde satış yok.')),
      for (final en in entries)
        Card(
          child: ListTile(
            title: Text(d.name(en.key)),
            subtitle: Text('${en.value[0].toInt()} adet · gelir ${tl(en.value[1])}'),
            trailing: Text(tl(en.value[2]), style: TextStyle(fontWeight: FontWeight.bold, color: en.value[2] >= 0 ? good : bad)),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Yedek al', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('Telefon değiştirirsen ya da uygulamayı silersen verilerini buradan geri yüklersin. Dosyayı WhatsApp’tan kendine, Drive’a ya da e-postaya gönder.'),
              const SizedBox(height: 6),
              Text('Son yedek: ${d.lastBackup ?? 'hiç alınmadı'}'),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: backup, icon: const Icon(Icons.share), label: const Text('Yedeği paylaş')),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Yedekten geri yükle', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('Yeni telefonda uygulamayı aç, yedek dosyasını seç.'),
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: restore, icon: const Icon(Icons.upload_file), label: const Text('Yedek dosyası seç')),
            ]),
          ),
        ),
      ]);

  Widget? fab() {
    switch (tab) {
      case 0:
        return FloatingActionButton.extended(onPressed: addProduct, icon: const Icon(Icons.add), label: const Text('Çeşit ekle'));
      case 1:
        return FloatingActionButton.extended(onPressed: () => tradeSheet(false), icon: const Icon(Icons.add), label: const Text('Alış ekle'));
      case 2:
        return FloatingActionButton.extended(onPressed: () => tradeSheet(true), icon: const Icon(Icons.add), label: const Text('Satış ekle'));
      case 3:
        return FloatingActionButton.extended(onPressed: expenseSheet, icon: const Icon(Icons.add), label: const Text('Gider ekle'));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Stok', 'Alış', 'Satış', 'Gider', 'Rapor', 'Yedek'];
    final List<Widget Function()> pages = [stokPage, () => tradePage(false), () => tradePage(true), giderPage, raporPage, yedekPage];
    return Scaffold(
      appBar: AppBar(title: Text('Anahtarlık Takip · ${titles[tab]}')),
      body: ready ? pages[tab]() : const Center(child: CircularProgressIndicator()),
      floatingActionButton: ready ? fab() : null,
      bottomNavigationBar: NavigationBar(
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
