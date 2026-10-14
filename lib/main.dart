import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'services/admin_auth_service.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // Same Supabase project as the farmer app (IsdaSafeV2).
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  AdminAuthService.listenForPasswordRecovery();
  await ThemeController.instance.load();

  runApp(const IsdaSafeAdminApp());
}
