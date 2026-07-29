import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/sms_service.dart';
import 'data/sos_local_datasource.dart';
import 'data/sos_remote_datasource.dart';
import 'data/sos_repository.dart';
import 'domain/send_sos_usecase.dart';
import 'presentation/manage_contacts_controller.dart';
import 'presentation/sos_controller.dart';

import 'presentation/sos_screen.dart';

/// Composition root for the SOS feature. Wraps [SosScreen] with a
/// [ChangeNotifierProvider<SosController>] wired up with real
/// implementations of every dependency.
class SosFeature extends StatelessWidget {
  const SosFeature({super.key, this.voiceAction});

  final String? voiceAction;

  @override
  Widget build(BuildContext context) {
    final repository = SosRepositoryImpl(
      remoteDatasource: SosRemoteDatasource(),
      localDatasource: SosLocalDatasource(),
      smsService: SmsService(),
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SosController(
            sendSosUseCase: SendSosUseCase(repository: repository),
            repository: repository,
            locationService: LocationService(),
            permissionService: PermissionService(),
            notificationService: NotificationService(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ManageContactsController(repository),
        ),
      ],
      child: SosScreen(voiceAction: voiceAction),
    );
  }
}
