import 'dart:async';
import 'dart:ui'; // For Rect

import 'package:dart_libayatana_appindicator/dart_libayatana_appindicator.dart';
import 'package:dbus/dbus.dart';
import 'package:menu_base/menu_base.dart';

typedef TrayEventHandler = void Function(String method, dynamic arguments);

class TrayManagerLinux {
  AppIndicator? _indicator;
  TrayEventHandler? _eventHandler;

  String? _indicatorId;
  String? _iconPath;
  DBusMenuItem? _currentMenuRoot;
  bool _hasInstalledMenu = false;

  static void registerWith() {
    // No-op for now as we handle logic manually in TrayManager.
    // This method is required by flutter build to register the plugin.
  }

  void setEventHandler(TrayEventHandler handler) {
    _eventHandler = handler;
  }

  Future<void> _ensureClient({DBusMenuItem? initialMenu}) async {
    if (_indicator != null) {
      return;
    }

    if (_indicatorId == null || _iconPath == null) {
      return;
    }

    _indicator = AppIndicator(id: _indicatorId!);

    _indicator!.onActivate = (x, y) {
      _eventHandler?.call('onTrayIconMouseDown', null);
      _eventHandler?.call('onTrayIconMouseUp', null);
    };

    _indicator!.onSecondaryActivate = (x, y) {
      _eventHandler?.call('onTrayIconRightMouseDown', null);
      _eventHandler?.call('onTrayIconRightMouseUp', null);
    };

    _indicator!.onScroll = (delta, orientation) {
      // Keep callback wiring so behavior stays aligned with non-Linux backends.
    };

    _indicator!.iconName = _iconPath!;

    final DBusMenuItem? rootMenu = initialMenu ?? _currentMenuRoot;
    if (rootMenu != null) {
      _indicator!.setMenu(rootMenu.children);
      _hasInstalledMenu = true;
    }

    _indicator!.status = AppIndicatorStatus.active;
  }

  Future<void> destroy() async {
    if (_indicator != null) {
      _indicator!.status = AppIndicatorStatus.passive;
      await _indicator!.close();
      _indicator = null;
    }

    _indicatorId = null;
    _iconPath = null;
    _currentMenuRoot = null;
    _hasInstalledMenu = false;
  }

  Future<void> setIcon(String id, String iconPath) async {
    final bool shouldRecreateForIdChange =
        _indicator != null && _indicatorId != null && _indicatorId != id;

    _indicatorId = id;
    _iconPath = iconPath;

    if (shouldRecreateForIdChange) {
      await _recreateClient(_currentMenuRoot);
    } else {
      await _ensureClient(initialMenu: _currentMenuRoot);
    }

    if (_indicator != null) {
      _indicator!.iconName = iconPath;
    }
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


  bool _hasCompatibleMenuStructure(DBusMenuItem previous, DBusMenuItem next) {
    if (previous.children.length != next.children.length) {
      return false;
    }

    for (var i = 0; i < previous.children.length; i++) {
      final previousChild = previous.children[i];
      final nextChild = next.children[i];

      if (previousChild.id != nextChild.id) {
        return false;
      }

      if (!_hasCompatibleMenuStructure(previousChild, nextChild)) {
        return false;
      }
    }

    return true;
  }

  bool _hasSameMenuProperties(DBusMenuItem previous, DBusMenuItem next) {
    if (previous.properties.length != next.properties.length) {
      return false;
    }

    for (final key in previous.properties.keys) {
      if (!next.properties.containsKey(key)) {
        return false;
      }

      if (previous.properties[key].toString() != next.properties[key].toString()) {
        return false;
      }
    }

    return true;
  }

  bool _requiresClientRecreation(DBusMenuItem previous, DBusMenuItem next) {
    if (!_hasCompatibleMenuStructure(previous, next)) {
      return true;
    }

    if (!_hasSameMenuProperties(previous, next)) {
      return true;
    }

    for (var i = 0; i < previous.children.length; i++) {
      if (_requiresClientRecreation(previous.children[i], next.children[i])) {
        return true;
      }
    }

    return false;
  }

  Future<void> _recreateClient([DBusMenuItem? rootMenu]) async {
    if (_indicator != null) {
      _indicator!.status = AppIndicatorStatus.passive;
      await _indicator!.close();
      _indicator = null;
    }

    _hasInstalledMenu = false;
    await _ensureClient(initialMenu: rootMenu ?? _currentMenuRoot);
  }

  Future<void> setContextMenu(Menu menu) async {
    final rootMenu = _buildDBusMenu(menu);

    if (_indicator == null) {
      _currentMenuRoot = rootMenu;
      await _ensureClient(initialMenu: rootMenu);
      return;
    }

    if (!_hasInstalledMenu) {
      _indicator!.setMenu(rootMenu.children);
      _currentMenuRoot = rootMenu;
      _hasInstalledMenu = true;
      return;
    }

    final previousRootMenu = _currentMenuRoot;
    if (previousRootMenu != null &&
        _requiresClientRecreation(previousRootMenu, rootMenu)) {
      _currentMenuRoot = rootMenu;
      await _recreateClient(rootMenu);
      return;
    }

    _indicator!.setMenu(rootMenu.children);
    _currentMenuRoot = rootMenu;
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

  DBusMenuItem _buildDBusMenu(Menu menu) {
    return DBusMenuItem(children: _buildDBusMenuItems(menu.items ?? []));
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
