# MedicoScope — AI-Powered Clinic in Your Pocket

A professional Flutter health application providing AI-powered, multi-modal disease screening for patients and assistive diagnostics for doctors.

![Flutter](https://img.shields.io/badge/Flutter-3.6.0-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.6.0-0175C2?logo=dart)
![License](https://img.shields.io/badge/License-MIT-green)

## ✨ Features

- 🎨 **Beautiful UI/UX** — Glassmorphism design with smooth animations
- 🩺 **Multi-modal disease screening** — Diabetes, hypertension and anemia risk from lab reports, symptom questionnaires, vitals, PPG, conjunctival pallor and retinal fundus images
- ❤️ **Heart sound analysis** — On-device TFLite model classifies heart sounds (normal vs. valvular conditions) and estimates heart rate
- 🧠 **MindSpace** — Voice-based mental health check-ins with emotional analysis
- 💬 **HearMe chatbot** — LLM assistant that answers health questions with your medical context
- 📸 **Image capture** — Camera and gallery support for image-based screening
- 🧬 **3D visualization** — Interactive 3D models of organs and conditions
- 📅 **Appointments & doctor linking** — Book appointments and link with doctors via unique codes
- 🗺️ **Nearby doctors** — Find hospitals and clinics near you on a map
- 🏆 **Rewards & gamification** — Earn coins for healthy engagement
- 🌐 **Multi-language** — English, Hindi, Tamil, Telugu, Marathi, Bengali, Kannada
- 📱 **Cross-platform** — Android, iOS, Web and desktop

## 🚀 Quick Start

### Prerequisites

- Flutter SDK 3.6.0 or higher
- Dart SDK 3.6.0 or higher
- Android Studio / Xcode (for mobile development)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/atharva-awade/Team-Synora-MedicoScope-AI-Powered-Clinic-in-you-Pocket.git
   cd Team-Synora-MedicoScope-AI-Powered-Clinic-in-you-Pocket
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **ML models**

   The TFLite models ship in `assets/models/`:
   ```
   assets/models/
   ├── eye_float16.tflite
   ├── eye_float32.tflite
   ├── skin_float16.tflite
   └── heart_model.tflite
   ```

4. **3D models**

   The `.glb` 3D models ship in `assets/3d_models/` (heart and skin lesion models).

5. **Run the app**
   ```bash
   flutter run
   ```

### Backend services

The app talks to two backends (deployment config in `render.yaml`):

- **API server** (`server/`) — Node.js + MongoDB: auth, profiles, detection records, appointments, rewards, admin.
- **Chatbot** (`chatbot/`) — Python FastAPI: HearMe chat, mental-health voice analysis, vitals streaming and reward content (Groq LLMs).

Copy `chatbot/.env.example` to `chatbot/.env` and fill in your own keys before running the chatbot locally.

## 📱 Supported Platforms

- ✅ Android
- ✅ iOS
- ✅ Web (limited 3D support)
- ✅ Windows / macOS (desktop)

## 🎨 UI/UX Design

- **Glassmorphism effects** — Frosted glass cards with backdrop blur
- **Health-themed accent colors** — Clean medical palette
- **Google Fonts typography** — Modern, readable type
- **Smooth animations** — Eased transitions throughout
- **Light & dark themes** — User-selectable, persisted across sessions

## 🏗️ Architecture

```
lib/
├── core/        # Theme, locale, providers, constants, shared widgets
├── data/        # Disease database and symptom questionnaires
├── models/      # Data models (user, doctor, patient, risk results)
├── screens/     # UI screens grouped by feature
├── services/    # API, auth, analyzers, TFLite, chat, vitals
└── main.dart    # App entry point
server/          # Node.js API server
chatbot/         # Python FastAPI LLM backend
assets/          # ML models, 3D models, images
```

## 🩺 Disease Screening Methods

MedicoScope screens for **diabetes, hypertension and anemia** using six complementary methods, each producing a unified risk result (low / moderate / high / critical) with findings and recommendations:

1. **Lab report (PDF)** — parses markers such as HbA1c, FBS, PPBS, Hb, RBC, WBC
2. **Symptom questionnaire** — structured symptom scoring
3. **Vitals (wearable / manual)** — blood pressure, heart rate, SpO₂
4. **PPG blood pressure** — camera-based photoplethysmography estimation
5. **Conjunctival pallor** — eyelid image analysis for anemia
6. **Retinal fundus** — fundus image analysis for diabetic retinopathy risk

## 🔧 Configuration

### Camera & permissions

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to capture medical images</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>We need photo library access to select medical images</string>
```

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| tflite_flutter | On-device ML inference |
| image_picker / camera | Camera & gallery |
| model_viewer_plus | 3D model viewing |
| flutter_animate | Animations |
| google_fonts | Typography |
| provider | State management |
| fl_chart | Charts (heart & vitals) |
| flutter_map / geolocator | Nearby doctors map |
| syncfusion_flutter_pdf | Lab report parsing |
| health | Health Connect / HealthKit |
| record / fftea | Audio capture & signal processing |

## 🎯 Usage Flow

1. **Onboarding** — Interactive tutorial explaining features
2. **Sign up / role selection** — Patient, doctor or admin
3. **Dashboard** — Role-specific hub of available tools
4. **Screening** — Choose a disease and a detection method
5. **Analysis** — On-device or backend AI processes the input
6. **Results** — View risk level, findings, recommendations, 3D models, and ask HearMe for guidance

## ⚠️ Important Notes

- This is an **assistive tool**, not a replacement for professional medical diagnosis.
- Image and heart-sound models run best on physical devices.
- AR viewing requires iOS 12+ or an ARCore-compatible Android device.
- Never commit real API keys — `chatbot/.env` is gitignored; use `.env.example` as a template.

## 📄 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📧 Contact

For questions or support, please open an issue in the repository.

---

**Built with ❤️ using Flutter**
