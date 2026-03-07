import 'dart:async';

import 'package:dart_xdg_status_notifier_item/dart_xdg_status_notifier_item.dart';
import 'package:menu_base/menu_base.dart';
import 'package:shortid/shortid.dart';

class TrayManagerLinux {
  TrayManagerLinux._();

  static final TrayManagerLinux instance = TrayManagerLinux._();

  static void registerWith() {
    // No-op for registering the plugin since it's instantiated directly by TrayManager
    // but this satisfies flutter's dartPluginClass expectation.
  }

  StatusNotifierItemClient? _client;

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
    }
  }

  Future<void> setIcon(String iconPath) async {
    await _ensureClient();
    _client!.iconName = iconPath;
  }

  Future<void> setToolTip(String toolTip) async {
    await _ensureClient();
    _client!.toolTip = StatusNotifierToolTip(
      iconName: _client!.iconName,
      iconPixmap: [],
      title: toolTip,
      body: '',
    );
  }

  Future<void> setTitle(String title) async {
    await _ensureClient();
    _client!.title = title;
  }

  Future<void> setContextMenu(Menu menu) async {
    await _ensureClient();
    DBusMenuItem rootMenu = _buildDBusMenu(menu);
    await _client!.updateMenu(rootMenu);
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

  Future<void> _ensureClient() async {
    if (_client == null) {
      String id = 'tray_manager_${shortid.generate()}';
      _client = StatusNotifierItemClient(
        id: id,
        menu: DBusMenuItem(children: []),
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
      _client!.iconName = 'flutter'; // Default fallback
      await _client!.connect();
    }
  }
}
