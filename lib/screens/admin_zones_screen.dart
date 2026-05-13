// lib/screens/admin_zones_screen.dart
//
// Admin screen to create, toggle, and delete geo-fence zones.
// Uses the device's current GPS to pre-fill coordinates when adding a zone.

import 'package:facial_attendance/core/geo_fence_service.dart' hide GeoZone;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../local_database/app_database.dart' ;
import '../main.dart';
import 'package:drift/drift.dart' show Value;

class AdminZonesScreen extends StatefulWidget {
  const AdminZonesScreen({super.key});

  @override
  State<AdminZonesScreen> createState() => _AdminZonesScreenState();
}

class _AdminZonesScreenState extends State<AdminZonesScreen> {
  final AppDatabase _db = getIt<AppDatabase>();
  final GeoFenceService _geo = GeoFenceService();

  List<GeoZone> _zones = [];
  bool _loading = true;

  static const Color _primary  = Color(0xFF1A73E8);
  static const Color _danger   = Color(0xFFD32F2F);
  static const Color _success  = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    setState(() => _loading = true);
    final zones = await _db.getAllZones();
    if (mounted) setState(() { _zones = zones; _loading = false; });
  }

  // ── Add / Edit zone dialog ─────────────────────────────────────────────────

  Future<void> _showZoneDialog({GeoZone? existing}) async {
    final nameController = TextEditingController(
        text: existing?.name ?? '');
    final latController  = TextEditingController(
        text: existing?.latitude.toString() ?? '');
    final lonController  = TextEditingController(
        text: existing?.longitude.toString() ?? '');
    final radController  = TextEditingController(
        text: existing?.radiusMeters.toString() ?? '100');

    bool fetchingLocation = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.location_on_rounded,
                        color: _primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    existing == null ? 'Add Zone' : 'Edit Zone',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ]),
                const SizedBox(height: 20),

                // Zone name
                _DialogField(
                  controller: nameController,
                  label: 'Zone Name',
                  hint: 'e.g. Main Office, Lab 3',
                  icon: Icons.label_rounded,
                ),
                const SizedBox(height: 14),

                // Use my location
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: fetchingLocation
                        ? null
                        : () async {
                            setDlg(() => fetchingLocation = true);
                            try {
                              final pos =
                                  await _geo.getCurrentPosition();
                              latController.text =
                                  pos.latitude.toStringAsFixed(6);
                              lonController.text =
                                  pos.longitude.toStringAsFixed(6);
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(e
                                        .toString()
                                        .replaceFirst('Exception: ', '')),
                                    backgroundColor: _danger,
                                  ),
                                );
                              }
                            } finally {
                              setDlg(() => fetchingLocation = false);
                            }
                          },
                    icon: fetchingLocation
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(fetchingLocation
                        ? 'Getting location...'
                        : 'Use My Current Location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: BorderSide(color: _primary.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Lat / Lon
                Row(children: [
                  Expanded(
                    child: _DialogField(
                      controller: latController,
                      label: 'Latitude',
                      hint: '18.520430',
                      icon: Icons.explore_rounded,
                      keyboard: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DialogField(
                      controller: lonController,
                      label: 'Longitude',
                      hint: '73.856744',
                      icon: Icons.explore_outlined,
                      keyboard: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),

                // Radius
                _DialogField(
                  controller: radController,
                  label: 'Radius (metres)',
                  hint: '100',
                  icon: Icons.radar_rounded,
                  keyboard: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
                const SizedBox(height: 6),
                Text(
                  '  Tip: 50 m for a single room, 200 m for a building',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),

                const SizedBox(height: 24),

                // Actions
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        final lat  = double.tryParse(latController.text.trim());
                        final lon  = double.tryParse(lonController.text.trim());
                        final rad  = double.tryParse(radController.text.trim());

                        if (name.isEmpty || lat == null ||
                            lon == null || rad == null || rad <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Please fill all fields correctly'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                          return;
                        }

                        Navigator.pop(ctx);

                        if (existing == null) {
                          await _db.insertZone(GeoZonesCompanion(
                            name:          Value(name),
                            latitude:      Value(lat),
                            longitude:     Value(lon),
                            radiusMeters:  Value(rad),
                          ));
                        } else {
                          await _db.updateZone(existing.copyWith(
                            name:         name,
                            latitude:     lat,
                            longitude:    lon,
                            radiusMeters: rad,
                          ));
                        }
                        _loadZones();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(existing == null ? 'Add Zone' : 'Save'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Delete confirm ─────────────────────────────────────────────────────────

  Future<void> _deleteZone(GeoZone zone) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_rounded,
                  color: _danger, size: 32),
            ),
            const SizedBox(height: 14),
            const Text('Delete Zone',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Remove "${zone.name}"?\nAttendance records will be kept.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Delete'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );

    if (confirm == true) {
      await _db.deleteZone(zone.id);
      _loadZones();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance Zones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Admin — Geo-fence settings',
                style: TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadZones,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _zones.isEmpty
              ? _buildEmptyState()
              : _buildZoneList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showZoneDialog(),
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Zone',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.location_off_rounded,
              size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No zones configured',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Tap + Add Zone to create an attendance zone',
              style: TextStyle(color: Colors.grey.shade400)),
        ]),
      );

  Widget _buildZoneList() => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _zones.length,
        itemBuilder: (context, index) {
          final zone = _zones[index];
          return _ZoneCard(
            zone: zone,
            onEdit: () => _showZoneDialog(existing: zone),
            onDelete: () => _deleteZone(zone),
            onToggle: (active) async {
              await _db.toggleZone(zone.id, active);
              _loadZones();
            },
          );
        },
      );
}

// ── Zone card ──────────────────────────────────────────────────────────────────
class _ZoneCard extends StatelessWidget {
  final GeoZone zone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  static const Color _primary = Color(0xFF1A73E8);
  static const Color _danger  = Color(0xFFD32F2F);

  const _ZoneCard({
    required this.zone,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: zone.isActive
                    ? _primary.withOpacity(0.10)
                    : Colors.grey.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: zone.isActive ? _primary : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    'Radius: ${zone.radiusMeters.toStringAsFixed(0)} m',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            // Active toggle
            Switch.adaptive(
              value: zone.isActive,
              activeColor: _primary,
              onChanged: onToggle,
            ),
            // 3-dot menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Edit Zone'),
                  ]),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(Icons.delete_rounded,
                        size: 18, color: Color(0xFFD32F2F)),
                    const SizedBox(width: 10),
                    Text('Delete',
                        style: const TextStyle(color: Color(0xFFD32F2F))),
                  ]),
                ),
              ],
            ),
          ]),
        ),

        // Coordinates row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(children: [
            _CoordChip(
              label: zone.latitude.toStringAsFixed(5),
              icon: Icons.arrow_upward_rounded,
            ),
            const SizedBox(width: 8),
            _CoordChip(
              label: zone.longitude.toStringAsFixed(5),
              icon: Icons.arrow_forward_rounded,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: zone.isActive
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                zone.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: zone.isActive
                      ? Colors.green.shade700
                      : Colors.grey,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CoordChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _CoordChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontFamily: 'monospace')),
        ]),
      );
}

class _DialogField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;

  const _DialogField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboard,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
        ),
      );
}
