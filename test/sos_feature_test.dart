import 'package:flutter_test/flutter_test.dart';
import 'package:vision_mate/core/services/location_service.dart';
import 'package:vision_mate/core/services/notification_service.dart';
import 'package:vision_mate/core/services/permission_service.dart';
import 'package:vision_mate/features/emergency/sos/data/sos_local_datasource.dart';
import 'package:vision_mate/features/emergency/sos/data/sos_remote_datasource.dart';
import 'package:vision_mate/features/emergency/sos/data/sos_repository.dart';
import 'package:vision_mate/features/emergency/sos/domain/send_sos_usecase.dart';
import 'package:vision_mate/features/emergency/sos/presentation/sos_controller.dart';
import 'package:vision_mate/features/emergency/sos/presentation/sos_state.dart';

void main() {
  test('SosController initializes with default contacts', () async {
    final repository = SosRepositoryImpl(
      remoteDatasource: SosRemoteDatasource(),
      localDatasource: SosLocalDatasource(),
    );
    final controller = SosController(
      sendSosUseCase: SendSosUseCase(repository: repository),
      repository: repository,
      locationService: LocationService(),
      permissionService: PermissionService(),
      notificationService: NotificationService(),
    );

    await controller.initialize();

    expect(controller.state.contacts, isNotEmpty);
    expect(controller.state.status, SosStatus.idle);
  });
}
