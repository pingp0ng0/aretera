import 'package:flutter/material.dart';

/// Icons a pack category can use. Keys are stored on [GearCategory.icon].
const gearIconChoices = <String, IconData>{
  'shelter': Icons.holiday_village_outlined,
  'sleep': Icons.bed_outlined,
  'clothing': Icons.checkroom,
  'cook': Icons.local_fire_department_outlined,
  'safety': Icons.medical_services_outlined,
  'myog': Icons.content_cut,
  'category': Icons.category_outlined,
  'water': Icons.water_drop_outlined,
  'food': Icons.restaurant_outlined,
  'light': Icons.flashlight_on_outlined,
  'electronics': Icons.battery_charging_full,
  'navigation': Icons.explore_outlined,
  'hygiene': Icons.soap_outlined,
  'pack': Icons.backpack_outlined,
  'camera': Icons.photo_camera_outlined,
  'winter': Icons.ac_unit,
  'tools': Icons.handyman_outlined,
  'star': Icons.star_outline,
};

IconData gearIcon(String key) => gearIconChoices[key] ?? Icons.category_outlined;
