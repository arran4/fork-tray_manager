import 'dart:async';
import 'dart:ui'; // For Rect

import 'package:dart_libayatana_appindicator/dart_libayatana_appindicator.dart';
import 'package:dbus/dbus.dart';
import 'package:menu_base/menu_base.dart';

typedef TrayEventHandler = void Function(String method, dynamic arguments);

class TrayManagerLinux {
  AppIndicator? _indicator;
  TrayEventHandler? _eventHandler;

  static void registerWith() {
    // No-op for now as we handle logic manually in TrayManager.
    // This method is required by flutter build to register the plugin.
  }

  void setEventHandler(TrayEventHandler handler) {
    _eventHandler = handler;
  }

  Future<void> destroy() async {
    if (_indicator != null) {
      _indicator!.status = AppIndicatorStatus.passive;
      await _indicator!.close();
      _indicator = null;
    }
  }

  Future<void> setIcon(String id, String iconPath) async {
    if (_indicator == null) {
      _indicator = AppIndicator(id: id);

      _indicator!.onActivate = (x, y) {
        _eventHandler?.call('onTrayIconMouseDown', null);
        _eventHandler?.call('onTrayIconMouseUp', null);
      };

      _indicator!.onSecondaryActivate = (x, y) {
        _eventHandler?.call('onTrayIconRightMouseDown', null);
        _eventHandler?.call('onTrayIconRightMouseUp', null);
      };

      _indicator!.status = AppIndicatorStatus.active;
    }

    _indicator!.iconName = iconPath;
  }

  Future<void> setTitle(String title) async {
    if (_indicator != null) {
      _indicator!.title = title;
    }
  }

  Future<void> setToolTip(String toolTip) async {
    if (_indicator != null) {
      _indicator!.tooltipTitle = toolTip;
    }
  }

  Future<void> setContextMenu(Menu menu) async {
    if (_indicator != null) {
      final items = _buildDBusMenuItems(menu.items ?? []);
      _indicator!.setMenu(items);
    }
  }

  Future<void> popUpContextMenu() async {
    // Not supported directly by AppIndicator
  }

  Future<Rect?> getBounds() async {
    return null;
  }

  Future<void> setIconPosition(String position) async {
    // Not supported
  }

  List<DBusMenuItem> _buildDBusMenuItems(List<MenuItem> items) {
    List<DBusMenuItem> dbusItems = [];
    for (var item in items) {
      dbusItems.add(_buildDBusMenuItem(item));
    }
    return dbusItems;
  }

  DBusMenuItem _buildDBusMenuItem(MenuItem item) {
    Map<String, DBusValue> properties = {};

    properties['enabled'] = DBusBoolean(!item.disabled);
    properties['visible'] = const DBusBoolean(true);

    if (item.label != null) {
        properties['label'] = DBusString(item.label!);
    }

    if (item.type == 'separator') {
      properties['type'] = const DBusString('separator');
    } else if (item.type == 'checkbox') {
      properties['toggle-type'] = const DBusString('checkmark');
      properties['toggle-state'] = DBusInt32((item.checked == true) ? 1 : 0);
    } else if (item.type == 'submenu') {
      properties['children-display'] = const DBusString('submenu');
    }

    List<DBusMenuItem> children = [];
    if (item.submenu != null) {
      children = _buildDBusMenuItems(item.submenu!.items ?? []);
    }

    return DBusMenuItem(
      id: item.id,
      properties: properties,
      children: children,
      onActivated: () {
        _eventHandler?.call('onTrayMenuItemClick', {'id': item.id});
      },
    );
  }
}
