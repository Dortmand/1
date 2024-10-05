import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

class Product {
  String name;
  String type;
  DateTime? startDate;
  DateTime? endDate;
  bool isStartDateBased;
  int? daysUntilExpiry;

  Product({
    required this.name,
    required this.type,
    this.startDate,
    this.endDate,
    this.isStartDateBased = false,
    this.daysUntilExpiry,
  });

  bool hasIncompleteFields() {
    return (startDate == null && isStartDateBased) || (endDate == null && !isStartDateBased);
  }

  DateTime? getComputedExpiryDate() {
    if (isStartDateBased && startDate != null && daysUntilExpiry != null) {
      return startDate!.add(Duration(days: daysUntilExpiry!));
    }
    return endDate;
  }
}

class ProductList extends StatefulWidget {
  @override
  _ProductListState createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  List<Product> products = [];
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  final ImagePicker _picker = ImagePicker();
  
  @override
  void initState() {
    super.initState();
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    var initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    var initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void addProduct(Product product) {
    setState(() {
      products.add(product);
    });
    scheduleExpiryNotification(product);
  }

  void editProduct(Product updatedProduct, int index) {
    setState(() {
      products[index] = updatedProduct;
    });
    scheduleExpiryNotification(updatedProduct);
  }

  bool isExpiringSoon(Product product) {
    final today = DateTime.now();
    final expiryDate = product.getComputedExpiryDate();
    
    if (expiryDate == null) return false;
    
    final difference = expiryDate.difference(today).inDays;
    return difference == 1;
  }

  int countIncompleteProducts() {
    return products.where((product) => product.hasIncompleteFields()).length;
  }

  void scheduleExpiryNotification(Product product) {
    final expiryDate = product.getComputedExpiryDate();
    if (expiryDate == null) return;

    final notificationTime = expiryDate.subtract(Duration(days: 1));

    flutterLocalNotificationsPlugin.zonedSchedule(
      product.hashCode,
      'Товар скоро истечет',
      '${product.name} истекает завтра',
      notificationTime.toLocal(),
      NotificationDetails(
          android: AndroidNotificationDetails('expiry_channel', 'Сроки годности',
              channelDescription: 'Напоминания о сроках годности')),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
    );
  }

  // Метод для распознавания текста из изображения
  Future<void> pickImageAndRecognizeText() async {
    final XFile? pickedImage = await _picker.pickImage(source: ImageSource.camera);
    if (pickedImage != null) {
      final File imageFile = File(pickedImage.path);
      final InputImage inputImage = InputImage.fromFile(imageFile);
      final textRecognizer = GoogleMlKit.vision.textRecognizer();
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      String extractedText = recognizedText.text;
      List<String> extractedDates = extractDatesFromText(extractedText);

      if (extractedDates.isNotEmpty) {
        // Обрабатываем распознанные даты и добавляем их в продукт
        setState(() {
          for (String date in extractedDates) {
            products.add(Product(
              name: 'Распознанный товар',
              type: 'Штучный товар',
              endDate: DateTime.parse(date), // Добавляем дату как конечный срок реализации
              isStartDateBased: false,
            ));
          }
        });
      }

      await textRecognizer.close();
    }
  }

  // Простой метод для извлечения дат из текста (в формате ГГГГ-ММ-ДД)
  List<String> extractDatesFromText(String text) {
    final dateRegExp = RegExp(r'\b\d{4}-\d{2}-\d{2}\b');
    return dateRegExp.allMatches(text).map((match) => match.group(0)!).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Хоп Хей: Сроки годности'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Text('Незаполненные: ${countIncompleteProducts()}'),
            ),
          )
        ],
      ),
      body: ListView.builder(
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          final isExpiring = isExpiringSoon(product);
          final hasIncompleteFields = product.hasIncompleteFields();

          return ListTile(
            title: Text(product.name),
            subtitle: Text(
              'Тип: ${product.type}, Срок годности: ${product.getComputedExpiryDate() ?? 'Не указан'}',
            ),
            tileColor: isExpiring
                ? Colors.red
                : hasIncompleteFields
                    ? Colors.yellow
                    : Colors.white,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.edit),
                  onPressed: () {
                    _showProductForm(context, product: product, index: index);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      products.removeAt(index);
                    });
                  },
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () {
              _showProductForm(context);
            },
            child: Icon(Icons.add),
          ),
          SizedBox(height: 10),
          FloatingActionButton(
            onPressed: pickImageAndRecognizeText,
            child: Icon(Icons.camera_alt),
          ),
        ],
      ),
    );
  }

  void _showProductForm(BuildContext context, {Product? product, int? index}) {
    final nameController = TextEditingController(text: product?.name ?? '');
    final typeController = TextEditingController(text: product?.type ?? '');
    DateTime? startDate = product?.startDate;
    DateTime? endDate = product?.endDate;
    bool isStartDateBased = product?.isStartDateBased ?? false;
    final daysUntilExpiryController =
        TextEditingController(text: product?.daysUntilExpiry?.toString() ?? '');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(product == null ? 'Добавить товар' : 'Редактировать товар'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: 'Название товара'),
                ),
                TextField(
                  controller: typeController,
                  decoration: InputDecoration(labelText: 'Тип товара'),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: isStartDateBased,
                      onChanged: (bool? value) {
                        setState(() {
                          isStartDateBased = value!;
                        });
                      },
                    ),
                    Text('Использовать начальную дату'),
                  ],
                ),
                ElevatedButton(
                  onPressed: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2101),
                    );
                    setState(() {
                      if (isStartDateBased) {
                        startDate = pickedDate;
                      } else {
                        endDate = pickedDate;
                      }
                    });
},
                  child: Text(isStartDateBased
                      ? 'Выбрать начальную дату'
                      : 'Выбрать конечную дату'),
                ),
                if (isStartDateBased)
                  TextField(
                    controller: daysUntilExpiryController,
                    decoration: InputDecoration(
                        labelText: 'Кол-во дней до истечения срока'),
                    keyboardType: TextInputType.number,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final String name = nameController.text;
                final String type = typeController.text;
                final int? daysUntilExpiry = isStartDateBased
                    ? int.tryParse(daysUntilExpiryController.text)
                    : null;

                if (name.isNotEmpty && type.isNotEmpty) {
                  final newProduct = Product(
                    name: name,
                    type: type,
                    startDate: startDate,
                    endDate: endDate,
                    isStartDateBased: isStartDateBased,
                    daysUntilExpiry: daysUntilExpiry,
                  );

                  if (product == null) {
                    addProduct(newProduct);
                  } else {
                    editProduct(newProduct, index!);
                  }

                  Navigator.of(context).pop();
                } else {
                  // Отображаем сообщение, если поля пусты
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Пожалуйста, заполните все поля')),
                  );
                }
              },
              child: Text(product == null ? 'Добавить' : 'Сохранить'),
            ),
          ],
        );
      },
    );
  }
}
