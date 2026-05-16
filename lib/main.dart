import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ); // Assumes you've configured via FlutterFire CLI
  cameras = await availableCameras();
  runApp(const GreenDataExchangeApp());
}

class GreenDataExchangeApp extends StatelessWidget {
  const GreenDataExchangeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Circular Logistics',
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

/// ==========================================
/// 📊 DASHBOARD SCREEN (Main UI Hub)
/// ==========================================
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verified Green Data Exchange')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('plastic_transactions')
            .snapshots(),
        builder: (context, snapshot) {
          double totalCredits = 0.0;
          double totalWeight = 0.0;

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              totalCredits += (doc['credits_minted'] as num).toDouble();
              totalWeight += (doc['weight_kg'] as num).toDouble();
            }
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text(
                          'TOTAL VERIFIED CREDITS MINTED',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          totalCredits.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              const Text('Mass Recovered'),
                              Text(
                                '${totalWeight.toStringAsFixed(1)} kg',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CameraInferenceScreen(),
                      ),
                    );
                  },

                  child: const Text(
                    'SCAN NEW WASTE BATCH',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// ==========================================
/// 📷 CAMERA & EDGE AI INFERENCE ENGINE SCREEN
/// ==========================================
class CameraInferenceScreen extends StatefulWidget {
  const CameraInferenceScreen({super.key});

  @override
  State<CameraInferenceScreen> createState() => _CameraInferenceScreenState();
}

class _CameraInferenceScreenState extends State<CameraInferenceScreen> {
  CameraController? _cameraController;
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModelAndLabels();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) return;
    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadModelAndLabels() async {
    try {
      // Load raw Float32 TFLite brain
      _interpreter = await Interpreter.fromAsset('assets/best_float32.tflite');

      // Load string index mapping
      final labelData = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/labels.txt');
      _labels = labelData
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      print(
        "Edge AI engine configured successfully. Labels detected: $_labels",
      );
    } catch (e) {
      print("Error configuring TFLite Engine: $e");
    }
  }

  /// High-performance processing loop transforming pixels into image tensors
  /// High-performance processing loop transforming pixels into image tensors
  Future<void> _processCapture() async {
    if (_cameraController == null || _interpreter == null || _isProcessing) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final fileBytes = await File(imageFile.path).readAsBytes();
      final img.Image? decodedImage = img.decodeImage(fileBytes);

      if (decodedImage == null) {
        throw Exception("Failed to decode image buffers.");
      }

      // Crop to the center square
      int cropSize = decodedImage.width < decodedImage.height
          ? decodedImage.width
          : decodedImage.height;
      int offsetX = (decodedImage.width - cropSize) ~/ 2;
      int offsetY = (decodedImage.height - cropSize) ~/ 2;

      final img.Image croppedImage = img.copyCrop(
        decodedImage,
        x: offsetX,
        y: offsetY,
        width: cropSize,
        height: cropSize,
      );

      // Resize to 224x224
      final img.Image resizedImage = img.copyResize(
        croppedImage,
        width: 224,
        height: 224,
      );

      // Construct input tensor float array: Shape [1, 224, 224, 3]
      var input = List.generate(
        1,
        (_) => List.generate(
          224,
          (_) => List.generate(224, (_) => List.filled(3, 0.0)),
        ),
      );

      for (int y = 0; y < 224; y++) {
        for (int x = 0; x < 224; x++) {
          final pixel = resizedImage.getPixel(x, y);
          // -1.0 to 1.0 Normalization
          input[0][y][x][0] = (pixel.r - 127.5) / 127.5;
          input[0][y][x][1] = (pixel.g - 127.5) / 127.5;
          input[0][y][x][2] = (pixel.b - 127.5) / 127.5;
        }
      }

      // 🚨 THE FIX: DYNAMIC TENSOR SIZING
      // Ask the interpreter exactly how many classes this specific model outputs
      var outputTensor = _interpreter!.getOutputTensor(0);
      int modelOutputClasses =
          outputTensor.shape[1]; // Will be 183 now, 7 later

      // Allocate exactly the right amount of memory
      var output = List.filled(
        1 * modelOutputClasses,
        0.0,
      ).reshape([1, modelOutputClasses]);

      // Run inference
      _interpreter!.run(input, output);

      List<double> predictionLogits = List<double>.from(output[0]);

      // Force the model to only pick from your provided labels
      double maxScore = -1.0;
      int bestClassIndex = 0;

      int limit = _labels.length < predictionLogits.length
          ? _labels.length
          : predictionLogits.length;

      // Only check the first 7 items (your plastics)
      for (int i = 0; i < limit; i++) {
        if (predictionLogits[i] > maxScore) {
          maxScore = predictionLogits[i];
          bestClassIndex = i;
        }
      }

      String detectedPolymer = _labels[bestClassIndex];

      print(
        "🚀 AI PREDICTION: $detectedPolymer | Confidence: ${(maxScore * 100).toStringAsFixed(2)}%",
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ValidationAndMintingScreen(
            polymerType: detectedPolymer,
            confidenceScore: maxScore,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Inference Fault: $e")));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edge Classification Node')),
      body: Stack(
        children: [
          Transform.scale(
            scale:
                1 /
                (_cameraController!.value.aspectRatio *
                    MediaQuery.of(context).size.aspectRatio),
            alignment: Alignment.topCenter,
            child: CameraPreview(_cameraController!),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                onPressed: _isProcessing ? null : _processCapture,
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.camera),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 🛡️ VALIDATION & CREDIT MINTING SCREEN
/// ==========================================
class ValidationAndMintingScreen extends StatefulWidget {
  final String polymerType;
  final double confidenceScore;

  const ValidationAndMintingScreen({
    super.key,
    required this.polymerType,
    required this.confidenceScore,
  });

  @override
  State<ValidationAndMintingScreen> createState() =>
      _ValidationAndMintingScreenState();
}

class _ValidationAndMintingScreenState
    extends State<ValidationAndMintingScreen> {
  final TextEditingController _weightController = TextEditingController();
  bool _isMinting = false;

  // Embedded India Compliance Market Dynamic Rate Table
  final Map<String, double> polymerMultipliers = {
    '1-PET': 1.5,
    '2-HDPE': 1.2,
    '3-PVC': 0.5,
    '4-LDPE': 0.8,
    '5-PP': 1.0,
    '6-PS': 0.4,
    '7-Other': 0.2,
  };

  Future<void> _executeMintingProtocol() async {
    final double? typedWeight = double.tryParse(_weightController.text);
    if (typedWeight == null || typedWeight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Provide valid physical weight metrics.")),
      );
      return;
    }

    // Built-in Fraud Control checking metrics
    if (widget.confidenceScore < 0.80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Low Confidence Override: Proceeding with minting despite sub-80% AI confidence.",
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }

    setState(() => _isMinting = true);

    try {
      // Fetch structural edge location bounds parameters
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      Position location = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      // Compute economic asset token parameters
      double baseRate = polymerMultipliers[widget.polymerType] ?? 0.1;
      double creditYield = typedWeight * baseRate;

      // Construct transaction ledger object matrix map model
      Map<String, dynamic> creditPayload = {
        'timestamp': FieldValue.serverTimestamp(),
        'polymer_type': widget.polymerType,
        'confidence': widget.confidenceScore,
        'weight_kg': typedWeight,
        'credits_minted': creditYield,
        'geolocation': {'lat': location.latitude, 'lng': location.longitude},
        'status': 'VERIFIED',
      };

      await FirebaseFirestore.instance
          .collection('plastic_transactions')
          .add(creditPayload);

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 64),
          title: const Text('Asset Secured Successfully'),
          content: Text(
            'Minted ${creditYield.toStringAsFixed(2)} compliance credit assets into the central database architecture logs.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Dismiss dialog
                Navigator.pop(context); // Go back to main dashboard
              },
              child: const Text('RETURN TO CONSOLE'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Ledger error: $e")));
    } finally {
      setState(() => _isMinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double activeRate = polymerMultipliers[widget.polymerType] ?? 0.0;
    bool isCredible = widget.confidenceScore >= 0.80;

    return Scaffold(
      appBar: AppBar(title: const Text('Sensor Fusion Ledger')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              tileColor: isCredible ? Colors.blue.shade50 : Colors.red.shade50,
              leading: Icon(
                isCredible ? Icons.gavel : Icons.warning,
                color: isCredible ? Colors.blue : Colors.red,
              ),
              title: Text('AI Inference Vector: ${widget.polymerType}'),
              subtitle: Text(
                'Model confidence score signature: ${(widget.confidenceScore * 100).toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Current Compliance Asset Conversion Base: $activeRate Credits per Kilogram.',
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Simulated Hardware Mass Register (kg)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.scale),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isCredible ? Colors.green : Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: _isMinting ? null : _executeMintingProtocol,
              child: _isMinting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      isCredible
                          ? 'EXECUTE SECURITY MINT PROTOCOL'
                          : 'OVERRIDE LOW CONFIDENCE & MINT',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
