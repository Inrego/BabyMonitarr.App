import 'package:flutter/material.dart';

IconData iconForRoom(String icon) {
  switch (icon) {
    case 'baby':
      return Icons.child_care;
    case 'baby-carriage':
      return Icons.stroller;
    case 'bed':
      return Icons.bed;
    case 'moon':
      return Icons.nightlight_round;
    case 'star':
      return Icons.star;
    case 'heart':
      return Icons.favorite;
    case 'home':
      return Icons.home;
    case 'door-open':
      return Icons.door_front_door;
    default:
      return Icons.videocam;
  }
}
