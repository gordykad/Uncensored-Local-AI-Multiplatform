import 'package:get/get.dart';

import '../controllers/model_controller.dart';
import 'local_api_server_service.dart';
import 'mesh_service.dart';

/// Phone-as-node (T-05 app side): the join payload and the on/off
/// orchestration shared by the Settings switch and the app-start
/// re-arm. The gateway stores {name, url, gpu, kind,
/// via_tunnel_proxy, models_hint, ram_gb}; the model list uses the
/// same display names the phone's /api/tags serves, so a model the
/// mesh routes here resolves to a local file.
Future<Map<String, dynamic>> phoneNodePayload() async {
  final api = Get.find<LocalApiServerService>();
  final ctrl = Get.find<ModelController>();
  final ip = await MeshService.advertisedIp();
  return {
    'name': MeshService.phoneNodeName,
    'url': ip == null ? '' : 'http://$ip:${api.port.value}',
    'kind': 'phone',
    'via_tunnel_proxy': true,
    'gpu': 'Apple GPU',
    // Kai's device floor (iPhone 14, 6 GB). The gateway uses this
    // only for fit-marking; a bigger phone is under-marked, never
    // over-promised.
    'ram_gb': 6,
    'models': [
      for (final f in ctrl.downloadedModels) ctrl.getModelInfo(f)?.name ?? f,
    ],
  };
}

/// Turn phone-node presence on or off. Turning it on makes sure the
/// local API is serving on the tailnet interface first (the gateway
/// probes this phone's /api/tags and posts chats to /api/chat).
/// Returns false when the phone has no tailnet address to offer.
Future<bool> setPhoneNode(bool on) async {
  final mesh = MeshService();
  if (!on) {
    await mesh.stopPresence();
    return true;
  }
  final api = Get.find<LocalApiServerService>();
  if (!api.allInterfaces.value) await api.setAllInterfaces(true);
  if (!api.isRunning.value) await api.start();
  if (await MeshService.advertisedIp() == null) return false;
  return mesh.startPresence(phoneNodePayload);
}
