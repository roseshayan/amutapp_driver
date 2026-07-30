# AmutBar Driver App

[![Flutter](https://img.shields.io/badge/Flutter-3.12.0+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

AmutBar Driver is a professional mobile application designed for logistics drivers to manage their trips, receive load assignments, navigate to destinations, and provide real-time shipment status updates.

## 🚀 Key Features

- **User Authentication:** Secure login with OTP (One-Time Password) and identity verification.
- **Onboarding:** Streamlined vehicle setup and video verification for new drivers.
- **Load Management:** Browse, search, and view detailed information about available load assignments.
- **Trip Tracking:** Real-time GPS tracking and status updates for active shipments.
- **Communication:** Integrated support ticket chat system and call history tracking.
- **Profile Management:** Manage personal identity information and vehicle details.
- **Persian Support:** Fully localized for RTL (Right-to-Left) languages with Persian (Farsi) calendar and fonts.

## 🛠 Tech Stack

- **Framework:** [Flutter](https://flutter.dev)
- **Navigation:** [go_router](https://pub.dev/packages/go_router)
- **API Communication:** [Dio](https://pub.dev/packages/dio)
- **Local Storage:** [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
- **State Management:** (Context-specific/Built-in)
- **Connectivity:** [connectivity_plus](https://pub.dev/packages/connectivity_plus)
- **Maps & Location:** [geolocator](https://pub.dev/packages/geolocator) & [geocoding](https://pub.dev/packages/geocoding)
- **UI Components:** Custom Persian date-time pickers, `Vazir` font.

## 📁 Project Structure

```text
lib/
├── core/             # Core utilities, themes, and connectivity guards
├── features/         # Feature-based modules
│   ├── auth/         # Login, OTP, and Identity screens
│   ├── calls/        # Call history and communication
│   ├── dashboard/    # Main application shell and home screen
│   ├── loads/        # Load searching and details
│   ├── onboarding/   # Vehicle setup and verification
│   ├── profile/      # User profile, support, and ticket chat
│   └── splash/       # Initial splash screen
├── app.dart          # App-wide configuration (routing, localization)
└── main.dart         # Entry point of the application
```

## 🏁 Getting Started

### Prerequisites

- Flutter SDK `^3.12.0`
- Android Studio / VS Code
- Android SDK / Xcode for iOS

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/amutbar_driver.git
    cd amutbar_driver
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    flutter analyze
    ```

3.  **Run the application:**
    ```bash
    flutter run
    ```

### Asset Generation

To update launcher icons:
```bash
flutter pub run flutter_launcher_icons
```

## 📝 Configuration

- **Localization:** The app defaults to Persian (`fa_IR`). RTL support is enabled by default.
- **Permissions:** Ensure location and camera permissions are granted for full functionality.
- **API URL:** Pass the production endpoint with
  `--dart-define=API_BASE_URL=https://YOUR_DOMAIN/YOUR_ADMIN_PATH`.
- **Release signing:** Copy `android/key.properties.example` to the ignored
  `android/key.properties` and reference only the authorized Driver keystore.
  Release builds fail clearly when signing is not configured.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is proprietary and confidential. Unauthorized copying of this file, via any medium, is strictly prohibited.
