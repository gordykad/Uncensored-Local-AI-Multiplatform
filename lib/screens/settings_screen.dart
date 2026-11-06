import 'dart:io';
import 'package:flutter/material.dart';
import '../app_version.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../services/image_gen_service.dart';
import '../widgets/faithful/widgets.dart';
import '../widgets/faithful/controls_meta.dart';
import '../widgets/faithful/textfx.dart';
import '../widgets/faithful/glitch.dart';
import '../widgets/faithful/particle.dart';
import '../widgets/faithful/gravity.dart';
import '../widgets/faithful/shared.dart';
import '../controllers/chat_controller.dart';
import '../controllers/model_controller.dart';
import '../services/local_api_server_service.dart';
import '../services/mesh_service.dart';
import '../services/haptics.dart';
import '../services/phone_node.dart';
import '../services/custom_connections_service.dart';
import '../services/model_manager.dart';
import '../services/background_optimizer_service.dart';
import '../services/chat_storage_service.dart';
import '../services/memory_probe.dart';

class SettingsScreen extends StatelessWidget {
  /// When true, no Scaffold — just the body content for embedding in tabs.
  final bool embedded;

  const SettingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      return _SettingsBody(showBackButton: false);
    }
    return Scaffold(
      backgroundColor: context.bg,
      body: _SettingsBody(showBackButton: true),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  final bool showBackButton;

  const _SettingsBody({this.showBackButton = false});

  @override
  Widget build(BuildContext context) {
    final chatCtrl = Get.find<ChatController>();
    final modelManager = Get.find<ModelManager>();
    final apiServer = Get.find<LocalApiServerService>();
    final storage = Get.find<ChatStorageService>();

    return Column(
      children: [
        // ── Top bar ──────────────────────────────────
        Container(
          padding: EdgeInsets.only(
            top: showBackButton ? MediaQuery.of(context).padding.top : 0,
            left: 4,
            right: 4,
          ),
          decoration: BoxDecoration(
            color: context.bg,
            border: Border(
              bottom: BorderSide(color: context.border, width: 0.5),
            ),
          ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                if (showBackButton)
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: context.text),
                    onPressed: () => Get.back(),
                  ),
                if (!showBackButton) const SizedBox(width: 16),
                BlurReveal(
                  text: 'Settings',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Body ─────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ── Identity lockup (ticket 08) ──────────────
              _card(
                context,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.35),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.asset(
                            'assets/icon/minix-icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ASTRO MINIX',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                                color: context.text,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Black box build \u00b7 dark only, by law',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: context.textD,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const RedactionBars(widths: [44, 30], barHeight: 7),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (Platform.isAndroid) ...[
                const SizedBox(height: 12),
                _card(
                  context,
                  child: ListTile(
                    title: Text(
                      'Battery Optimization',
                      style: TextStyle(color: context.text, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Disable to prevent background killing',
                      style: TextStyle(color: context.textD, fontSize: 12),
                    ),
                    trailing: FutureBuilder<bool>(
                      future:
                          BackgroundOptimizerService.isOptimizationDisabled(),
                      builder: (context, snapshot) {
                        final disabled = snapshot.data ?? false;
                        if (disabled) {
                          return const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.green,
                            size: 20,
                          );
                        }
                        return const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: AppColors.orange,
                        );
                      },
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    onTap: () async {
                      await BackgroundOptimizerService.openBatterySettings();
                      // Ignore setState, it will rebuild on next visit
                    },
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ── System Prompt ─────────────────────────────
              _sectionHeader(context, 'Global System Prompt'),
              const SizedBox(height: 8),
              Text(
                'Applied to all new chats. Existing chats keep their own prompt.',
                style: TextStyle(fontSize: 12, color: context.textD),
              ),
              const SizedBox(height: 12),
              Obx(
                () => TextField(
                  controller:
                      TextEditingController(text: chatCtrl.systemPrompt.value)
                        ..selection = TextSelection.fromPosition(
                          TextPosition(
                            offset: chatCtrl.systemPrompt.value.length,
                          ),
                        ),
                  maxLines: 4,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.text,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. You are a helpful assistant...',
                    hintStyle: TextStyle(color: context.textD),
                    filled: true,
                    fillColor: context.bgInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                  onChanged: (v) => chatCtrl.setGlobalSystemPrompt(v),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    chatCtrl.clearGlobalSystemPrompt();
                    Get.snackbar(
                      'Cleared',
                      'Global system prompt removed.',
                      snackPosition: SnackPosition.BOTTOM,
                    );
                  },
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  style: TextButton.styleFrom(foregroundColor: AppColors.red),
                  label: const Text(
                    'Clear Prompt',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Temperature ───────────────────────────────
              _sectionHeader(context, 'Temperature'),
              const SizedBox(height: 12),
              _card(
                context,
                child: Obx(
                  () => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.thermostat_rounded,
                          size: 20,
                          color: context.textM,
                        ),
                        Expanded(
                          child: Slider(
                            value: chatCtrl.temperature.value,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: AppColors.accent,
                            inactiveColor: context.border,
                            label: chatCtrl.temperature.value.toStringAsFixed(
                              1,
                            ),
                            onChanged: (v) => chatCtrl.updateTemperature(v),
                          ),
                        ),
                        Container(
                          width: 44,
                          alignment: Alignment.center,
                          child: Text(
                            chatCtrl.temperature.value.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Hardware Configuration ──────────────────────────
              _sectionHeader(context, 'Hardware Configuration'),
              const SizedBox(height: 8),
              _HardwareSettingsCard(storage: storage),

              const SizedBox(height: 28),

              // ── Local API Server ──────────────────────────
              _sectionHeader(context, 'Local API Server'),
              const SizedBox(height: 8),
              Text(
                'Expose the loaded model to OpenAI-compatible local clients.',
                style: TextStyle(fontSize: 12, color: context.textD),
              ),
              const SizedBox(height: 12),
              _card(
                context,
                child: Obx(() {
                  final running = apiServer.isRunning.value;
                  final starting = apiServer.isStarting.value;
                  final ready = apiServer.hasLoadedModel;
                  final busy = apiServer.isBusy;
                  final statusText = starting
                      ? 'Starting'
                      : running
                      ? ready
                            ? busy
                                  ? 'Busy'
                                  : 'Running'
                            : 'No model loaded'
                      : 'Stopped';
                  final statusColor = running && ready
                      ? AppColors.green
                      : running
                      ? AppColors.orange
                      : context.textD;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.api_rounded,
                              color: running ? AppColors.accent : context.textM,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Local API server',
                                    style: TextStyle(
                                      color: context.text,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'OpenAI base URL: ${apiServer.baseUrl}',
                                    style: TextStyle(
                                      color: context.textD,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            MinixSwitch(
                              value: running,
                              onChanged: starting
                                  ? (_) {}
                                  : (enabled) async {
                                      try {
                                        if (enabled) {
                                          await apiServer.start();
                                        } else {
                                          await apiServer.stop();
                                        }
                                      } catch (e) {
                                        Get.snackbar(
                                          'Local API Error',
                                          e.toString(),
                                          snackPosition: SnackPosition.BOTTOM,
                                        );
                                      }
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Allow External Connections',
                                    style: TextStyle(
                                      color: context.text,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Listen on 0.0.0.0 instead of localhost',
                                    style: TextStyle(
                                      color: context.textD,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            MinixSwitch(
                              value: apiServer.allInterfaces.value,
                              onChanged: starting
                                  ? (_) {}
                                  : (enabled) async {
                                      try {
                                        await apiServer.setAllInterfaces(
                                          enabled,
                                        );
                                      } catch (e) {
                                        Get.snackbar(
                                          'Settings Error',
                                          e.toString(),
                                          snackPosition: SnackPosition.BOTTOM,
                                        );
                                      }
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        StatefulBuilder(
                          builder: (context, setRow) {
                            final svc = ImageGenService();
                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Connectivity',
                                        style: TextStyle(
                                          color: context.text,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Hosted image lanes + shared config. Local models and the local API are unaffected when off.',
                                        style: TextStyle(
                                          color: context.textD,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                MinixSwitch(
                                  value: svc.connectivityOn,
                                  onChanged: (v) =>
                                      setRow(() => svc.connectivityOn = v),
                                ),
                              ],
                            );
                          },
                        ),
                        if (apiServer.allInterfaces.value)
                          Container(
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.orange.withOpacity(0.1),
                              border: Border.all(
                                color: AppColors.orange.withOpacity(0.3),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: AppColors.orange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Anyone on your network can access your loaded model.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _statusChip(context, statusText, statusColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FutureBuilder<String?>(
                                future: apiServer.allInterfaces.value
                                    ? apiServer.getDeviceIp()
                                    : Future.value(null),
                                builder: (context, snapshot) {
                                  String url = apiServer.baseUrl;
                                  if (apiServer.allInterfaces.value &&
                                      snapshot.hasData) {
                                    url =
                                        'http://${snapshot.data}:${apiServer.port.value}/v1';
                                  }
                                  return SelectableText(
                                    url,
                                    style: TextStyle(
                                      color: context.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: ValueKey('api-port-${apiServer.port.value}'),
                          initialValue: apiServer.port.value.toString(),
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: context.text, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Port',
                            helperText:
                                'Use API key "local" in clients that require one.',
                            labelStyle: TextStyle(color: context.textM),
                            helperStyle: TextStyle(
                              color: context.textD,
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: context.bgInput,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: context.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                          onFieldSubmitted: (value) async {
                            final parsed = int.tryParse(value.trim());
                            if (parsed == null ||
                                parsed < 1024 ||
                                parsed > 65535) {
                              Get.snackbar(
                                'Invalid Port',
                                'Choose a port from 1024 to 65535.',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                              return;
                            }
                            try {
                              await apiServer.setPort(parsed);
                              Get.snackbar(
                                'Local API Updated',
                                'Base URL is ${apiServer.baseUrl}',
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            } catch (e) {
                              Get.snackbar(
                                'Local API Error',
                                e.toString(),
                                snackPosition: SnackPosition.BOTTOM,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Get.toNamed('/api-endpoints');
                            },
                            icon: const Icon(Icons.api_rounded, size: 18),
                            label: const Text('Sample Endpoints & Testing'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.text,
                              side: BorderSide(color: context.border),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        if (apiServer.errorMessage.value.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            apiServer.errorMessage.value,
                            style: const TextStyle(
                              color: AppColors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ),

              const SizedBox(height: 28),

              // ── Mesh (ticket 31) ────────────────────────
              _sectionHeader(context, 'Mesh'),
              const SizedBox(height: 8),
              Text(
                'The Astro OS lanes, served by the mesh on your PC. Keys stay on the PC - the app only holds this address.',
                style: TextStyle(fontSize: 12, color: context.textD),
              ),
              const SizedBox(height: 12),
              const _MeshSettingsCard(),

              const SizedBox(height: 28),

              // ── Custom Connections (ticket 31) ──────────
              _sectionHeader(context, 'Custom Connections'),
              const SizedBox(height: 8),
              Text(
                'Your own URL/API seats. They answer straight from this phone, anywhere - no PC needed. Keys live on this device only.',
                style: TextStyle(fontSize: 12, color: context.textD),
              ),
              const SizedBox(height: 12),
              const _CustomConnectionsCard(),

              const SizedBox(height: 28),

              // ── Storage ───────────────────────────────────
              _sectionHeader(context, 'Storage'),
              const SizedBox(height: 12),
              _card(
                context,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: context.textM,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          modelManager.modelsDir,
                          style: TextStyle(fontSize: 13, color: context.text),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Danger Zone ───────────────────────────────
              _sectionHeader(context, 'Danger Zone'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                label: const Text(
                  'Delete All Chats',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                onPressed: () {
                  Get.dialog(
                    AlertDialog(
                      backgroundColor: context.bgPanel,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: Text(
                        'Delete All Chats?',
                        style: TextStyle(color: context.text),
                      ),
                      content: Text(
                        'This cannot be undone.',
                        style: TextStyle(color: context.textM),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: context.textD),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            await chatCtrl.deleteAllChats();
                            Get.back();
                            Get.snackbar(
                              'Done',
                              'All chats deleted.',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            elevation: 0,
                          ),
                          child: const Text(
                            'Delete All',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.red,
                  side: const BorderSide(color: AppColors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                label: const Text(
                  'Clear Temporary Cache',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                onPressed: () => Get.find<ModelController>().clearCache(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.text,
                  side: BorderSide(color: context.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ── Identity (ticket 08) ──────────────────────
              const ParticleText(height: 130),
              const SizedBox(height: 10),
              Center(
                child: Column(
                  children: [
                    TextGlitch(
                      text: 'ASTRO MINIX',
                      hoverText: 'BLACK BOX',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.text,
                      ),
                    ),
                    const SizedBox(height: 7),
                    GlitchText(
                      text: 'UNCENSORED',
                      intensity: GlitchIntensity.medium,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: context.text,
                      ),
                    ),
                    const SizedBox(height: 9),
                    SignalReveal(
                      text: 'NOTHING LEAVES THIS PHONE.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: context.text,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Astro MiniX $kAppVersion · Powered by llamadart + llama.cpp',
                      style: TextStyle(fontSize: 11, color: context.textD),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const GravityStars(height: 150),
              const SizedBox(height: 28),

              // ── App Logs ──────────────────────────────────
              _sectionHeader(context, 'Debugging'),
              const SizedBox(height: 8),
              _card(
                context,
                child: ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.article_outlined,
                      size: 18,
                      color: AppColors.orange,
                    ),
                  ),
                  title: Text(
                    'App Logs',
                    style: TextStyle(color: context.text, fontSize: 14),
                  ),
                  subtitle: Text(
                    'View logs, errors & share with developers',
                    style: TextStyle(color: context.textD, fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: context.textD,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  onTap: () => Get.toNamed('/logs'),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.textM,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _statusChip(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HardwareSettingsCard extends StatefulWidget {
  final ChatStorageService storage;

  const _HardwareSettingsCard({required this.storage});

  @override
  State<_HardwareSettingsCard> createState() => _HardwareSettingsCardState();
}

class _HardwareSettingsCardState extends State<_HardwareSettingsCard> {
  late String _backend;
  late double _gpuLayers;
  bool _showManual = false;
  // Ticket 03 knobs (0 = platform/auto default)
  late int _contextSize;
  late int _threadCount;
  late int _cpuMoeLayers;
  late int _moeCacheMb;
  late String _flashMode;

  // Auto-detect the best backend and GPU layers for this device
  static Map<String, dynamic> _detectBestConfig() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Desktop: CPU is safest, Vulkan if available
      return {
        'backend': 'cpu',
        'gpuLayers': 0,
        'reason': 'CPU mode — most compatible on desktop',
      };
    }

    if (Platform.isIOS) {
      // Ticket 03a: Metal is the iOS GPU path - OpenCL does not exist on
      // iOS, so the old recommendation could never have engaged a GPU.
      // GPU layers 0 = auto-fit at load time (ticket 01 headroom probe).
      return {
        'backend': 'metal',
        'gpuLayers': 0,
        'reason': 'Metal GPU - layers auto-fit to available memory',
      };
    }

    // Android: detect available RAM and processor count
    final cores = Platform.numberOfProcessors;

    if (cores >= 8) {
      // High-end device (e.g. Snapdragon 8 Gen 2+, Dimensity 9000+)
      return {
        'backend': 'opencl',
        'gpuLayers': 33,
        'reason': 'OpenCL GPU — best for high-end SoC ($cores cores detected)',
      };
    } else if (cores >= 6) {
      // Mid-range device
      return {
        'backend': 'cpu',
        'gpuLayers': 0,
        'reason': 'CPU mode — safe for mid-range devices ($cores cores)',
      };
    } else {
      // Low-end device
      return {
        'backend': 'cpu',
        'gpuLayers': 0,
        'reason': 'CPU mode — optimized for lower-end devices ($cores cores)',
      };
    }
  }

  @override
  void initState() {
    super.initState();
    _backend = widget.storage.backendType;
    _gpuLayers = widget.storage.gpuLayers.toDouble();
    _contextSize = widget.storage.contextSize;
    _threadCount = widget.storage.threadCount;
    _flashMode = widget.storage.flashAttentionMode;
    _cpuMoeLayers = widget.storage.cpuMoeLayers;
    _moeCacheMb = widget.storage.moeCacheMb;
  }

  void _applyAutoConfig() {
    final config = _detectBestConfig();
    setState(() {
      _backend = config['backend'] as String;
      _gpuLayers = (config['gpuLayers'] as int).toDouble();
    });
    widget.storage.backendType = _backend;
    widget.storage.gpuLayers = _gpuLayers.toInt();
    Get.snackbar(
      'Auto Config Applied',
      config['reason'] as String,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }

  void _saveBackend(String val) {
    setState(() => _backend = val);
    widget.storage.backendType = val;
    // Auto-set sensible GPU layers when switching. Metal/Auto keep 0:
    // at load time 0 resolves to "offload whatever fits" (ticket 03a).
    if (val == 'cpu') {
      setState(() => _gpuLayers = 0);
      widget.storage.gpuLayers = 0;
    } else if (val != 'metal' && val != 'auto' && _gpuLayers == 0) {
      setState(() => _gpuLayers = 33);
      widget.storage.gpuLayers = 33;
    }
  }

  void _saveGpuLayers(double val) {
    setState(() => _gpuLayers = val);
    widget.storage.gpuLayers = val.toInt();
  }

  String get _currentConfigLabel {
    switch (_backend) {
      case 'metal':
        return _gpuLayers.toInt() == 0
            ? 'GPU (Metal) - auto-fit layers'
            : 'GPU (Metal) - ${_gpuLayers.toInt()} layers';
      case 'auto':
        return 'Auto (best available backend)';
      case 'vulkan':
        return 'GPU (Vulkan) • ${_gpuLayers.toInt()} layers';
      case 'opencl':
        return 'GPU (OpenCL) • ${_gpuLayers.toInt()} layers';
      default:
        return 'CPU Only';
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoConfig = _detectBestConfig();

    return Container(
      decoration: BoxDecoration(
        color: context.bgPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Recommended Auto Config ──
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Text(
                'Compute Device',
                style: TextStyle(
                  color: context.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Current: $_currentConfigLabel',
            style: TextStyle(color: context.textM, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // Recommended button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _applyAutoConfig,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Apply Recommended Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    autoConfig['reason'] as String,
                    style: TextStyle(color: context.textM, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Manual Override Toggle ──
          InkWell(
            onTap: () => setState(() => _showManual = !_showManual),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _showManual ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: context.textM,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Manual Override',
                    style: TextStyle(
                      color: context.textM,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_showManual) ...[
            const SizedBox(height: 12),
            MinixSegmented(
              options: _backendOptionLabels(),
              index: _backendOptionValues().indexOf(_backend).clamp(0, 2),
              onChanged: (i) => _saveBackend(_backendOptionValues()[i]),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'GPU Layers',
                  style: TextStyle(color: context.text, fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgInput,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _gpuLayers.toInt().toString(),
                    style: TextStyle(
                      color: context.text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: context.border,
                thumbColor: AppColors.accent,
                overlayColor: AppColors.accent.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: _gpuLayers,
                min: 0,
                max: 99,
                divisions: 99,
                onChanged: _backend == 'cpu' ? null : _saveGpuLayers,
              ),
            ),
            Text(
              'GPU layers 0 with Metal/Auto = offload every layer that fits in memory. If the app crashes when loading a model, reduce GPU layers or switch to CPU. Reload the model after changing settings.',
              style: TextStyle(color: context.textD, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 20),
            // ── Engine knobs (ticket 03): context + threads ──
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Text(
                  'Engine Knobs',
                  style: TextStyle(
                    color: context.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Context, threads and flash attention apply on the next model load.',
              style: TextStyle(color: context.textD, fontSize: 11),
            ),
            const SizedBox(height: 12),
            Text(
              'Context Size',
              style: TextStyle(color: context.text, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MinixSegmented(
              options: const ['Default', '1024', '2048', '4096', '8192'],
              index: const [
                0,
                1024,
                2048,
                4096,
                8192,
              ].indexOf(_contextSize).clamp(0, 4),
              onChanged: (i) =>
                  _onContextSelected(const [0, 1024, 2048, 4096, 8192][i]),
            ),
            const SizedBox(height: 16),
            Text(
              'Threads',
              style: TextStyle(color: context.text, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MinixSegmented(
              options: const ['Auto', '2', '4', '6', '8'],
              index: const [0, 2, 4, 6, 8].indexOf(_threadCount).clamp(0, 4),
              onChanged: (i) {
                const values = [0, 2, 4, 6, 8];
                setState(() => _threadCount = values[i]);
                widget.storage.threadCount = values[i];
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Flash Attention',
              style: TextStyle(color: context.text, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MinixSegmented(
              options: const ['On', 'Auto', 'Off'],
              index: const [
                'on',
                'auto',
                'off',
              ].indexOf(_flashMode).clamp(0, 2),
              onChanged: (i) {
                const values = ['on', 'auto', 'off'];
                setState(() => _flashMode = values[i]);
                widget.storage.flashAttentionMode = values[i];
              },
            ),
            const SizedBox(height: 4),
            Text(
              'On keeps the shipped rule (CPU loads on, GPU auto). Flash attention is the prefill lever - A/B it against the METER lines in Diagnostics.',
              style: TextStyle(color: context.textD, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text(
              'MoE Host Expert Layers',
              style: TextStyle(color: context.text, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MinixSegmented(
              options: const ['Off', '4', '8', '16', 'All'],
              index: const [0, 4, 8, 16, -1].indexOf(_cpuMoeLayers).clamp(0, 4),
              onChanged: (i) {
                const values = [0, 4, 8, 16, -1];
                setState(() => _cpuMoeLayers = values[i]);
                widget.storage.cpuMoeLayers = values[i];
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Keeps the first layers of a mixture-of-experts model in phone memory instead of the GPU, so a 26B can fit. Dense models ignore it.',
              style: TextStyle(color: context.textD, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
            Text(
              'MoE Expert Cache',
              style: TextStyle(color: context.text, fontSize: 14),
            ),
            const SizedBox(height: 8),
            MinixSegmented(
              options: const ['Off', '256 MB', '512 MB', '1 GB', '2 GB'],
              index: const [
                0,
                256,
                512,
                1024,
                2048,
              ].indexOf(_moeCacheMb).clamp(0, 4),
              onChanged: (i) {
                const values = [0, 256, 512, 1024, 2048];
                setState(() => _moeCacheMb = values[i]);
                widget.storage.moeCacheMb = values[i];
              },
            ),
            const SizedBox(height: 4),
            Text(
              'GPU cache for hot experts - the speed lever for MoE models. Turning it on also disables CPU weight repacking, the ticket 12 safety rule.',
              style: TextStyle(color: context.textD, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  // Ticket 08: backend choices as segmented-control data.
  List<String> _backendOptionValues() => (Platform.isIOS || Platform.isMacOS)
      ? const ['auto', 'metal', 'cpu']
      : const ['cpu', 'vulkan', 'opencl'];
  List<String> _backendOptionLabels() => (Platform.isIOS || Platform.isMacOS)
      ? const ['Auto', 'Metal', 'CPU']
      : const ['CPU', 'Vulkan', 'OpenCL'];

  // Platform-appropriate backend choices (ticket 03a): Apple platforms
  // get Auto/Metal/CPU - Vulkan and OpenCL do not exist on iOS.
  List<Widget> _backendOptions() {
    final List<List<String>> options = (Platform.isIOS || Platform.isMacOS)
        ? [
            ['Auto', 'auto'],
            ['Metal', 'metal'],
            ['CPU', 'cpu'],
          ]
        : [
            ['CPU', 'cpu'],
            ['Vulkan', 'vulkan'],
            ['OpenCL', 'opencl'],
          ];
    final widgets = <Widget>[];
    for (var i = 0; i < options.length; i++) {
      if (i > 0) widgets.add(const SizedBox(width: 8));
      widgets.add(_buildBackendButton(options[i][0], options[i][1]));
    }
    return widgets;
  }

  int get _effectiveContext {
    if (_contextSize > 0) return _contextSize;
    return Platform.isAndroid ? 1024 : 2048;
  }

  // Raising the context grows the KV cache roughly in proportion; per
  // ticket 03 the consequence - with the live headroom from ticket 01 -
  // is shown BEFORE the new value is saved.
  Future<void> _onContextSelected(int val) async {
    if (val > 0 && val > _effectiveContext) {
      final headroom = await MemoryProbe.availableLabel();
      if (!mounted) return;
      final factor = (val / _effectiveContext).toStringAsFixed(1);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Raise context size?'),
          content: Text(
            'Context $val grows the KV cache to roughly ${factor}x the '
            'current size. Memory available right now: $headroom. '
            'The change applies on the next model load.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _contextSize = val);
    widget.storage.contextSize = val;
  }

  // Small selectable chips in the backend-button visual language.
  List<Widget> _chips({
    required List<int> values,
    required List<String> labels,
    required int selected,
    required void Function(int) onTap,
  }) {
    final widgets = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      if (i > 0) widgets.add(const SizedBox(width: 6));
      final isSel = values[i] == selected;
      widgets.add(
        Expanded(
          child: InkWell(
            onTap: () => onTap(values[i]),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: isSel ? AppColors.accent : context.bgInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSel ? AppColors.accent : context.border,
                ),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: isSel ? Colors.white : context.text,
                    fontSize: 11,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildBackendButton(String label, String value) {
    final selected = _backend == value;
    return Expanded(
      child: InkWell(
        onTap: () => _saveBackend(value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : context.bgInput,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.accent : context.border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.text,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ticket 31: Mesh settings card ──────────────────────────────

class _MeshSettingsCard extends StatefulWidget {
  const _MeshSettingsCard();

  @override
  State<_MeshSettingsCard> createState() => _MeshSettingsCardState();
}

class _MeshSettingsCardState extends State<_MeshSettingsCard> {
  final _svc = MeshService();
  late final TextEditingController _addr;
  String _status = 'Checking...';
  bool _phoneNode = false;
  bool _phoneNodeBusy = false;

  @override
  void initState() {
    super.initState();
    _addr = TextEditingController(text: _svc.address);
    _phoneNode = _svc.phoneNodeOn;
    _refresh();
  }

  @override
  void dispose() {
    _addr.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final totals = await _svc.fetchTotals();
    if (!mounted) return;
    setState(() {
      _status = totals == null
          ? 'Unreachable - check the address and that your PC is on'
          : '${totals['providers']} providers - ${totals['seats']} seats - ${totals['proven']} proven';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _addr,
            style: TextStyle(color: context.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Mesh address (host:port)',
              labelStyle: TextStyle(color: context.textM, fontSize: 12),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: context.border),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _status,
                  style: TextStyle(fontSize: 12, color: context.textM),
                ),
              ),
              TextButton(
                onPressed: () {
                  _svc.address = _addr.text;
                  setState(() => _status = 'Checking...');
                  _refresh();
                },
                child: const Text('Save + check'),
              ),
            ],
          ),
          const Divider(height: 24),
          // Phone-as-node (T-05): this phone joins the mesh and
          // answers chats routed to it, Ollama-style, over the
          // tailnet. The local API serves the tailnet while on.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offer this phone as a mesh node',
                      style: TextStyle(fontSize: 13, color: context.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _phoneNodeBusy
                          ? 'Working...'
                          : _phoneNode
                          ? 'Joined as node "phone" - the mesh can route chats to this phone\'s models'
                          : 'The mesh can route chats to this phone\'s local models over your tailnet',
                      style: TextStyle(fontSize: 11, color: context.textM),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _phoneNode,
                activeThumbColor: AppColors.accent,
                onChanged: _phoneNodeBusy
                    ? null
                    : (v) async {
                        TapFx.select();
                        setState(() => _phoneNodeBusy = true);
                        final ok = await setPhoneNode(v);
                        if (!mounted) return;
                        setState(() {
                          _phoneNodeBusy = false;
                          _phoneNode = ok ? v : _svc.phoneNodeOn;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: context.bgPanel,
                            content: Text(
                              ok
                                  ? (v
                                        ? 'This phone is on the mesh as node "phone"'
                                        : 'Phone node off - the mesh will forget this phone in about 3 minutes')
                                  : 'No tailnet address found - is Tailscale up on this phone?',
                              style: TextStyle(color: context.text),
                            ),
                          ),
                        );
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Ticket 31: Custom Connections card ─────────────────────────

class _CustomConnectionsCard extends StatefulWidget {
  const _CustomConnectionsCard();

  @override
  State<_CustomConnectionsCard> createState() => _CustomConnectionsCardState();
}

class _CustomConnectionsCardState extends State<_CustomConnectionsCard> {
  final _svc = CustomConnectionsService();

  Widget _field(
    BuildContext context,
    TextEditingController c,
    String label, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: TextStyle(color: context.text, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: context.textM, fontSize: 12),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.border),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.accent),
          ),
        ),
      ),
    );
  }

  Future<void> _form([CustomConnection? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final base = TextEditingController(text: existing?.baseUrl ?? '');
    final model = TextEditingController(text: existing?.model ?? '');
    final key = TextEditingController(text: existing?.apiKey ?? '');
    var type = existing?.type ?? 'openai';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: dlgCtx.bgPanel,
          title: Text(
            existing == null ? 'Add connection' : 'Edit connection',
            style: TextStyle(color: dlgCtx.text),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(dlgCtx, name, 'Name'),
                _field(dlgCtx, base, 'Base URL (https://...)'),
                _field(dlgCtx, model, 'Model id'),
                _field(dlgCtx, key, 'API key (optional)', obscure: true),
                Row(
                  children: [
                    Text(
                      'API type',
                      style: TextStyle(color: dlgCtx.textM, fontSize: 12),
                    ),
                    const Spacer(),
                    DropdownButton<String>(
                      value: type,
                      dropdownColor: dlgCtx.bgPanel,
                      style: TextStyle(color: dlgCtx.text, fontSize: 13),
                      items: const [
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI'),
                        ),
                        DropdownMenuItem(
                          value: 'ollama',
                          child: Text('Ollama'),
                        ),
                      ],
                      onChanged: (v) => setDlg(() => type = v ?? 'openai'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dlgCtx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (name.text.trim().isEmpty ||
        base.text.trim().isEmpty ||
        model.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.bgPanel,
          content: Text(
            'Name, base URL and model are all required',
            style: TextStyle(color: context.text),
          ),
        ),
      );
      return;
    }
    final conn = CustomConnection(
      id: existing?.id ?? 'c${DateTime.now().millisecondsSinceEpoch}',
      name: name.text.trim(),
      baseUrl: CustomConnection.normalizeBase(base.text, type),
      model: model.text.trim(),
      apiKey: key.text.trim(),
      type: type,
    );
    if (existing == null) {
      _svc.add(conn);
    } else {
      _svc.update(conn);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final conns = _svc.list();
    return Container(
      decoration: BoxDecoration(
        color: context.bgPanel,
        border: Border.all(color: context.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conns.isEmpty)
            Text(
              'No connections yet. Add one and it shows up in the model picker as your own seat.',
              style: TextStyle(fontSize: 12, color: context.textM),
            ),
          for (final c in conns)
            Row(
              children: [
                Icon(Icons.link_outlined, size: 16, color: context.textM),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: TextStyle(fontSize: 13, color: context.text),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${c.model} - ${c.type == 'ollama' ? 'Ollama API' : 'OpenAI API'}',
                        style: TextStyle(fontSize: 11, color: context.textM),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: context.textM,
                  ),
                  onPressed: () => _form(c),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.red,
                  ),
                  onPressed: () {
                    _svc.remove(c.id);
                    setState(() {});
                  },
                ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _form(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add connection'),
            ),
          ),
        ],
      ),
    );
  }
}
