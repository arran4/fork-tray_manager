import 'dart:async';

import 'package:dart_xdg_status_notifier_item/dart_xdg_status_notifier_item.dart';
import 'package:menu_base/menu_base.dart';
import 'package:shortid/shortid.dart';

class TrayManagerLinux {
  TrayManagerLinux._();

  static final TrayManagerLinux instance = TrayManagerLinux._();

  static void registerWith() {
    TrayManagerLinux.instance;
  }

  StatusNotifierItemClient? _client;
  DBusMenuItem? _currentMenu;
  String _iconName = 'flutter';
  String? _title;
  String? _toolTip;

  // Callbacks to communicate events back to the main TrayManager class
  void Function()? onTrayIconMouseDown;
  void Function()? onTrayIconMouseUp;
  void Function()? onTrayIconRightMouseDown;
  void Function()? onTrayIconRightMouseUp;
  void Function(int id)? onTrayMenuItemClick;
  void Function(int delta, String orientation)? onTrayIconScroll;

  Future<void> destroy() async {
    if (_client != null) {
      await _client!.close();
      _client = null;
      _currentMenu = null;
    }
  }

  Future<void> setIcon(String iconPath) async {
    await _ensureClient();
    _iconName = iconPath;
    _client!.iconName = iconPath;
  }

  Future<void> setToolTip(String toolTip) async {
    await _ensureClient();
    _toolTip = toolTip;
    _client!.toolTip = _buildToolTip(toolTip);
  }

  Future<void> setTitle(String title) async {
    await _ensureClient();
    _title = title;
    _client!.title = title;
  }

  Future<void> setContextMenu(Menu menu) async {
    DBusMenuItem rootMenu = _buildDBusMenu(menu);
    if (_client == null) {
      await _ensureClient(initialMenu: rootMenu);
      return;
    }

    if (_isMenuLayoutCompatible(_currentMenu, rootMenu)) {
      await _client!.updateMenu(rootMenu);
      _currentMenu = rootMenu;
      return;
    }

    // TODO(arran4): Replace full client recreation once the DBus menu layer
    // supports structural menu updates.
    await _recreateClientWithMenu(rootMenu);
  }

  DBusMenuItem _buildDBusMenu(Menu menu) {
    return DBusMenuItem(
      children: (menu.items ?? []).map((MenuItem item) {
        if (item.type == 'separator') {
          return DBusMenuItem.separator();
        }

        if (item.type == 'checkbox') {
           return DBusMenuItem.checkmark(
             item.label ?? '',
             enabled: !item.disabled,
             state: item.checked ?? false,
             onClicked: () async {
                onTrayMenuItemClick?.call(item.id);
             },
           );
        }

        if (item.type == 'radio') {
           return DBusMenuItem.radio(
             item.label ?? '',
             enabled: !item.disabled,
             state: item.checked ?? false,
             onClicked: () async {
                onTrayMenuItemClick?.call(item.id);
             },
           );
        }

        return DBusMenuItem(
          label: item.label ?? '',
          enabled: !item.disabled,
          children: item.submenu != null ? _buildDBusMenu(item.submenu!).children : [],
          onClicked: () async {
             onTrayMenuItemClick?.call(item.id);
          },
        );
      }).toList(),
    );
  }

  Future<void> _ensureClient({DBusMenuItem? initialMenu}) async {
    if (_client == null) {
      String id = 'tray_manager_${shortid.generate()}';
      _client = StatusNotifierItemClient(
        id: id,
        menu: initialMenu ?? DBusMenuItem(children: []),
        onActivate: (x, y) async {
           onTrayIconMouseDown?.call();
           onTrayIconMouseUp?.call();
        },
        onSecondaryActivate: (x, y) async {
           onTrayIconRightMouseDown?.call();
           onTrayIconRightMouseUp?.call();
        },
        onScroll: (delta, orientation) async {
           onTrayIconScroll?.call(delta, orientation);
        },
        onContextMenu: (x, y) async {
           // Provide the menu structure
        },
      );
      _currentMenu = initialMenu ?? DBusMenuItem(children: []);
      _client!.iconName = _iconName; // Default fallback
      if (_title != null) {
        _client!.title = _title!;
      }
      if (_toolTip != null) {
        _client!.toolTip = _buildToolTip(_toolTip!);
      }
      await _client!.connect();
    }
  }

  Future<void> _recreateClientWithMenu(DBusMenuItem menu) async {
    if (_client != null) {
      await _client!.close();
      _client = null;
      _currentMenu = null;
    }
    await _ensureClient(initialMenu: menu);
  }

  StatusNotifierToolTip _buildToolTip(String toolTip) {
    return StatusNotifierToolTip(
      iconName: _iconName,
      iconPixmap: [],
      title: toolTip,
      body: '',
    );
  }

  bool _isMenuLayoutCompatible(DBusMenuItem? previous, DBusMenuItem next) {
    if (previous == null) {
      return false;
    }

    List<DBusMenuItem> previousChildren = previous.children;
    List<DBusMenuItem> nextChildren = next.children;
    if (previousChildren.length != nextChildren.length) {
      return false;
    }

    for (int i = 0; i < previousChildren.length; i++) {
      if (!_isMenuLayoutCompatible(previousChildren[i], nextChildren[i])) {
        return false;
      }
    }

    return true;
  }
}
